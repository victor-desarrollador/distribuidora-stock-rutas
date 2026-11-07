// Controlador de «Confirmar salida» (B-02b.2 / S1), sin React.
//
// Única operación mutadora de la pantalla de jornadas en esta etapa. Usa sólo
// `ejecutar` de la capa B-02a con el comando `salir` (RPC `confirmar_salida`);
// la lectura sigue en jornadas_lectura.ts, que no puede mutar.
//
// Reglas (ADR-007 §2.2; ADR-001 §18.4.3–§18.4.7):
// - Quién y cuándo lo decide el servidor (dueño/encargado activo, jornada
//   `cargada`, carga neta > 0). Aquí sólo se ofrece la acción en `cargada`;
//   el control lo muestra la pantalla sólo a dueño y encargado.
// - Una clave de idempotencia por INTENCIÓN del usuario: se genera al
//   confirmar, se reutiliza en cada reintento de esa intención y se descarta
//   al terminar (éxito, rechazo definitivo, cancelación o cambio de jornada).
//   Sólo vive en memoria: nada se guarda en el navegador.
// - Envío único: mientras hay un envío o una verificación en curso, cualquier
//   otra acción se ignora (doble clic).
// - Sin respuesta (o concurrencia agotada): NO se reenvía nada por cuenta
//   propia. Primero se lee el estado real de la jornada; si ya salió, se
//   informa como registrada; si sigue `cargada`, se ofrece reintentar con la
//   MISMA clave (el servidor devuelve la respuesta original si ya se registró).
// - Tras un éxito se relee la lista desde Supabase.
// - Una intención con resultado desconocido NO se descarta por navegar a otra
//   jornada: hasta resolverla no se puede iniciar otra confirmación.
// - Respuestas tardías tras el desmontaje se descartan.

import {
  nuevaClaveIdempotencia,
  type EstadoJornada,
  type Jornada,
  type PuertoJornadas,
} from "../lib/jornadas";

export type PuertoSalida = Pick<PuertoJornadas, "ejecutar">;

/**
 * Estado real de la jornada leído de la base: el estado, `null` si ya no es
 * visible (RLS) o `undefined` si la lectura falló.
 */
export type VerificarJornada = (jornada: {
  id: string;
  fecha: string;
}) => Promise<EstadoJornada | null | undefined>;

export const MENSAJE_SALIDA_OK =
  "Salida confirmada. La jornada quedó en reparto.";
export const MENSAJE_SALIDA_YA_REGISTRADA =
  "La salida quedó registrada: la jornada ya está en reparto.";
export const MENSAJE_SALIDA_VERIFICANDO =
  "No se recibió la respuesta. Consultando el estado real de la jornada…";
export const MENSAJE_SALIDA_SIGUE_CARGADA =
  "No se pudo confirmar si la salida se registró y la jornada sigue cargada. Podés reintentar: se reenvía la misma operación y no se registra dos veces.";
export const MENSAJE_SALIDA_SIN_VERIFICAR =
  "No se pudo confirmar si la salida se registró ni leer el estado de la jornada. Verificá el estado antes de reintentar.";
export const MENSAJE_SALIDA_NO_VISIBLE =
  "No se pudo confirmar la salida y la jornada ya no está disponible. Actualizá la lista.";

export type FaseSalida =
  | { fase: "inactiva" }
  | { fase: "confirmando"; jornadaId: string }
  | { fase: "enviando"; jornadaId: string }
  | { fase: "verificando"; jornadaId: string }
  | { fase: "exito"; jornadaId: string; mensaje: string }
  | { fase: "error"; jornadaId: string; mensaje: string }
  | {
      fase: "desconocido";
      jornadaId: string;
      mensaje: string;
      // true si se pudo leer el estado (y sigue `cargada`): se puede reintentar.
      reintentable: boolean;
    };

export const SALIDA_INACTIVA: FaseSalida = { fase: "inactiva" };

// Estados posteriores a la salida (ADR-007 §2.2 y Blueprint §7.5).
const ESTADOS_TRAS_SALIDA: ReadonlySet<EstadoJornada> = new Set([
  "en_reparto",
  "ventas_finalizadas",
  "regreso_contado",
  "cerrada",
]);

// 40001/40P01 agotados: la transacción se revirtió sin efectos; la misma
// clave es segura, pero igual se verifica antes de ofrecer el reintento.
const CODIGOS_TRANSITORIOS: ReadonlySet<string> = new Set(["40001", "40P01"]);

interface Intencion {
  jornadaId: string;
  fecha: string;
  clave: string;
}

export function crearControladorSalida(
  puerto: PuertoSalida,
  verificar: VerificarJornada,
  alCambiarJornada: () => void,
  publicar: (fase: FaseSalida) => void,
  generarClave: () => string = nuevaClaveIdempotencia
) {
  let fase: FaseSalida = SALIDA_INACTIVA;
  let intencion: Intencion | null = null;
  // Jornada elegida en el paso de confirmación (todavía sin clave).
  let candidata: { id: string; fecha: string } | null = null;
  let activo = true;

  function emitir(nueva: FaseSalida) {
    fase = nueva;
    if (activo) publicar(fase);
  }

  const ocupado = () => fase.fase === "enviando" || fase.fase === "verificando";

  /**
   * Abre el paso de confirmación. Sólo para una jornada `cargada`.
   * Mientras haya una intención con resultado desconocido (de cualquier
   * jornada) no se abre otra: esa intención conserva su clave hasta
   * resolverse (verificación o reintento). Sólo el desmontaje la descarta.
   */
  function solicitar(jornada: Jornada): void {
    if (ocupado() || fase.fase === "desconocido" || jornada.estado !== "cargada") return;
    intencion = null;
    candidata = { id: jornada.id, fecha: jornada.fecha };
    emitir({ fase: "confirmando", jornadaId: jornada.id });
  }

  function cancelar(): void {
    if (fase.fase !== "confirmando") return;
    candidata = null;
    emitir(SALIDA_INACTIVA);
  }

  /** Confirmación explícita: nace la intención y su clave. */
  function confirmar(): Promise<void> {
    if (fase.fase !== "confirmando" || candidata === null) return Promise.resolve();
    intencion = { jornadaId: candidata.id, fecha: candidata.fecha, clave: generarClave() };
    candidata = null;
    return enviar(intencion);
  }

  /** Reintento de la MISMA intención (misma clave). Sólo tras verificar. */
  function reintentar(): Promise<void> {
    if (fase.fase !== "desconocido" || !fase.reintentable || intencion === null) {
      return Promise.resolve();
    }
    return enviar(intencion);
  }

  /** Vuelve a leer el estado real cuando la verificación anterior falló. */
  function verificarEstado(): Promise<void> {
    if (fase.fase !== "desconocido" || intencion === null) return Promise.resolve();
    return verificarYDecidir(intencion);
  }

  async function enviar(i: Intencion): Promise<void> {
    emitir({ fase: "enviando", jornadaId: i.jornadaId });
    const r = await puerto.ejecutar({ tipo: "salir", jornadaId: i.jornadaId }, i.clave);
    if (!activo) return;
    if (r.ok) {
      intencion = null;
      emitir({ fase: "exito", jornadaId: i.jornadaId, mensaje: MENSAJE_SALIDA_OK });
      alCambiarJornada();
      return;
    }
    const dudoso =
      r.error.resultadoDesconocido ||
      (r.error.codigo !== null && CODIGOS_TRANSITORIOS.has(r.error.codigo));
    if (dudoso) {
      await verificarYDecidir(i);
      return;
    }
    // Rechazo definitivo: la transacción se revirtió y la clave no se consumió;
    // la intención termina. La jornada pudo haber cambiado: se relee.
    intencion = null;
    emitir({ fase: "error", jornadaId: i.jornadaId, mensaje: r.error.mensaje });
    if (r.error.codigo === "jornada_estado_invalido") alCambiarJornada();
  }

  async function verificarYDecidir(i: Intencion): Promise<void> {
    emitir({ fase: "verificando", jornadaId: i.jornadaId });
    const estado = await verificar({ id: i.jornadaId, fecha: i.fecha });
    if (!activo) return;
    if (estado !== undefined && estado !== null && ESTADOS_TRAS_SALIDA.has(estado)) {
      intencion = null;
      emitir({ fase: "exito", jornadaId: i.jornadaId, mensaje: MENSAJE_SALIDA_YA_REGISTRADA });
      alCambiarJornada();
      return;
    }
    if (estado === "cargada") {
      emitir({
        fase: "desconocido",
        jornadaId: i.jornadaId,
        mensaje: MENSAJE_SALIDA_SIGUE_CARGADA,
        reintentable: true,
      });
      return;
    }
    if (estado === undefined) {
      emitir({
        fase: "desconocido",
        jornadaId: i.jornadaId,
        mensaje: MENSAJE_SALIDA_SIN_VERIFICAR,
        reintentable: false,
      });
      return;
    }
    // No visible o en un estado que no admite la salida: sin reintento.
    intencion = null;
    emitir({ fase: "error", jornadaId: i.jornadaId, mensaje: MENSAJE_SALIDA_NO_VISIBLE });
    alCambiarJornada();
  }

  /** (Re)montaje: vuelve a publicar. */
  function iniciar(): void {
    activo = true;
  }

  /** Desmontaje: las respuestas tardías ya no publican ni releen. */
  function detener(): void {
    activo = false;
  }

  return {
    obtener: () => fase,
    // Sólo para tests: la clave de la intención en curso (nunca se muestra).
    claveEnCurso: () => intencion?.clave ?? null,
    solicitar,
    cancelar,
    confirmar,
    reintentar,
    verificarEstado,
    iniciar,
    detener,
  };
}

export type ControladorSalida = ReturnType<typeof crearControladorSalida>;
