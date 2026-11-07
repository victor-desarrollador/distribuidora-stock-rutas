// Motor común de las operaciones de gestión de una jornada (B-02b.2), sin React.
//
// Extraído de S1 («Confirmar salida») para que cada operación (S1 salida, S2
// corrección) sólo defina QUÉ envía y CÓMO verifica su efecto; las garantías
// son las mismas para todas:
// - Una clave de idempotencia por INTENCIÓN: nace al confirmar, se reutiliza en
//   cada reintento de esa intención (con el MISMO comando, congelado) y se
//   descarta sólo cuando el resultado es cierto (respuesta del servidor o
//   evidencia suficiente). Sólo vive en memoria: nada se guarda en el navegador.
// - Envío único: durante un envío o una verificación cualquier acción se ignora.
// - Sin respuesta (o 40001/40P01 agotados): NO se reenvía por cuenta propia. Se
//   lee el estado real y la definición decide: registrada, sin efecto
//   (reintentable con la misma clave), incierta (con o sin reintento seguro),
//   sin poder verificar, o descartada.
// - Una intención con resultado desconocido no se descarta al navegar: hasta
//   resolverla no se inicia otra con este controlador.
// - Árbitro compartido (opcional, uno por pantalla): mientras una operación
//   confirma, envía, verifica o tiene resultado desconocido sobre una jornada,
//   ninguna OTRA operación del mismo árbitro puede iniciarse sobre esa jornada.
//   La exclusión se aplica aquí, no sólo deshabilitando botones.
// - Tras el desmontaje, las respuestas tardías no publican ni releen.
// El servidor decide siempre permisos, estados y reglas de negocio.

import {
  nuevaClaveIdempotencia,
  type ComandoJornada,
  type Jornada,
  type PuertoJornadas,
} from "../lib/jornadas";

export type PuertoOperacion = Pick<PuertoJornadas, "ejecutar">;

export type FaseOperacion =
  | { fase: "inactiva" }
  // `error`: validación local de la entrada (no se envió nada).
  | { fase: "confirmando"; jornadaId: string; error?: string }
  | { fase: "enviando"; jornadaId: string }
  | { fase: "verificando"; jornadaId: string }
  // `releida`: la lista ya se volvió a leer después del éxito; hasta entonces
  // la pantalla no ofrece otra acción sobre datos viejos.
  | { fase: "exito"; jornadaId: string; mensaje: string; releida?: true }
  | { fase: "error"; jornadaId: string; mensaje: string }
  | {
      fase: "desconocido";
      jornadaId: string;
      mensaje: string;
      // true si reenviar la MISMA intención es seguro (el servidor responde
      // con la operación original o la rechaza sin efecto).
      reintentable: boolean;
    };

export const OPERACION_INACTIVA: FaseOperacion = { fase: "inactiva" };

/** Fases que retienen la jornada frente a otras operaciones del árbitro. */
export function jornadaRetenida(fase: FaseOperacion): string | null {
  switch (fase.fase) {
    case "confirmando":
    case "enviando":
    case "verificando":
    case "desconocido":
      return fase.jornadaId;
    default:
      return null;
  }
}

/**
 * Arbitraje entre las operaciones de UNA pantalla. Cada controlador informa la
 * jornada que retiene (o null) y consulta si otra operación la retiene. Es
 * síncrono: en JavaScript la comprobación y la retención no se intercalan.
 */
export interface ArbitroJornadas {
  retenidaPorOtra(participante: symbol, jornadaId: string): boolean;
  actualizar(participante: symbol, jornadaId: string | null): void;
}

export function crearArbitroJornadas(): ArbitroJornadas {
  // null = sin retención (se sobrescribe en lugar de quitar la entrada).
  const retenciones = new Map<symbol, string | null>();
  return {
    retenidaPorOtra(participante, jornadaId) {
      for (const [otro, id] of retenciones) {
        if (otro !== participante && id === jornadaId) return true;
      }
      return false;
    },
    actualizar(participante, jornadaId) {
      retenciones.set(participante, jornadaId);
    },
  };
}

/** Resultado de leer el estado real después de una respuesta dudosa. */
export type Verificacion =
  // Evidencia suficiente de que ESTA intención se registró.
  | { resultado: "registrada"; mensaje: string }
  | { resultado: "sin_efecto"; mensaje: string }
  // Sin evidencia suficiente: la intención (clave y datos) se conserva.
  | { resultado: "incierta"; mensaje: string; reintentable: boolean }
  | { resultado: "sin_verificar"; mensaje: string }
  | { resultado: "descartada"; mensaje: string };

export type Preparacion<D> = { ok: true; datos: D } | { ok: false; mensaje: string };

export interface DefinicionOperacion<E, D extends { jornadaId: string }> {
  /** Si la operación se puede iniciar sobre esta jornada (sólo presentación). */
  admite(jornada: Jornada): boolean;
  /** Valida la entrada y congela los datos de la intención. */
  preparar(jornada: Jornada, entrada: E): Preparacion<D>;
  comando(datos: D): ComandoJornada;
  mensajeExito: string;
  verificar(datos: D): Promise<Verificacion>;
  /** Rechazos definitivos que indican que la jornada cambió: se relee. */
  releerTrasRechazo(codigo: string | null): boolean;
}

// 40001/40P01 agotados: la transacción se revirtió sin efectos; igual se
// verifica antes de ofrecer el reintento.
const CODIGOS_TRANSITORIOS: ReadonlySet<string> = new Set(["40001", "40P01"]);

export function crearControladorOperacion<E, D extends { jornadaId: string }>(
  definicion: DefinicionOperacion<E, D>,
  puerto: PuertoOperacion,
  alCambiarJornada: () => void,
  publicar: (fase: FaseOperacion) => void,
  generarClave: () => string = nuevaClaveIdempotencia,
  arbitro?: ArbitroJornadas
) {
  let fase: FaseOperacion = OPERACION_INACTIVA;
  let intencion: { datos: D; clave: string } | null = null;
  // Jornada elegida en el paso de confirmación (todavía sin clave).
  let candidata: Jornada | null = null;
  let activo = true;
  // Identidad de este controlador ante el árbitro.
  const yo = Symbol("operacion");

  function emitir(nueva: FaseOperacion) {
    fase = nueva;
    // El árbitro se actualiza siempre (también desmontado): la retención
    // describe la intención, no la pantalla.
    arbitro?.actualizar(yo, jornadaRetenida(fase));
    if (activo) publicar(fase);
  }

  const ocupado = () => fase.fase === "enviando" || fase.fase === "verificando";
  const retenidaPorOtra = (jornadaId: string) =>
    arbitro?.retenidaPorOtra(yo, jornadaId) ?? false;

  /** Abre el paso de confirmación, si la operación admite la jornada y nadie la retiene. */
  function solicitar(jornada: Jornada): void {
    if (ocupado() || fase.fase === "desconocido" || !definicion.admite(jornada)) return;
    if (retenidaPorOtra(jornada.id)) return;
    intencion = null;
    candidata = jornada;
    emitir({ fase: "confirmando", jornadaId: jornada.id });
  }

  function cancelar(): void {
    if (fase.fase !== "confirmando") return;
    candidata = null;
    emitir(OPERACION_INACTIVA);
  }

  /** Confirmación explícita: si la entrada es válida, nace la intención y su clave. */
  function confirmar(entrada: E): Promise<void> {
    if (fase.fase !== "confirmando" || candidata === null) return Promise.resolve();
    // Defensa: la retención de `confirmando` ya impide que otra operación la tome.
    if (retenidaPorOtra(candidata.id)) return Promise.resolve();
    const preparada = definicion.preparar(candidata, entrada);
    if (!preparada.ok) {
      emitir({ fase: "confirmando", jornadaId: candidata.id, error: preparada.mensaje });
      return Promise.resolve();
    }
    intencion = { datos: preparada.datos, clave: generarClave() };
    candidata = null;
    return enviar(intencion);
  }

  /** Reintento de la MISMA intención (misma clave y mismo comando). Sólo tras verificar. */
  function reintentar(): Promise<void> {
    if (fase.fase !== "desconocido" || !fase.reintentable || intencion === null) {
      return Promise.resolve();
    }
    return enviar(intencion);
  }

  /** Vuelve a leer el estado real cuando la verificación anterior no alcanzó. */
  function verificarEstado(): Promise<void> {
    if (fase.fase !== "desconocido" || intencion === null) return Promise.resolve();
    return verificarYDecidir(intencion);
  }

  /**
   * La lista se volvió a leer con éxito: un éxito previo deja de bloquear una
   * NUEVA intención (que tendrá otra clave). No relee ni toca otras fases.
   */
  function trasRelectura(): void {
    if (fase.fase === "exito" && fase.releida !== true) {
      emitir({ ...fase, releida: true });
    }
  }

  async function enviar(i: { datos: D; clave: string }): Promise<void> {
    const jornadaId = i.datos.jornadaId;
    emitir({ fase: "enviando", jornadaId });
    const r = await puerto.ejecutar(definicion.comando(i.datos), i.clave);
    if (!activo) return;
    if (r.ok) {
      intencion = null;
      emitir({ fase: "exito", jornadaId, mensaje: definicion.mensajeExito });
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
    // Rechazo definitivo: la transacción se revirtió y la clave no se consumió.
    intencion = null;
    emitir({ fase: "error", jornadaId, mensaje: r.error.mensaje });
    if (definicion.releerTrasRechazo(r.error.codigo)) alCambiarJornada();
  }

  async function verificarYDecidir(i: { datos: D; clave: string }): Promise<void> {
    const jornadaId = i.datos.jornadaId;
    emitir({ fase: "verificando", jornadaId });
    const v = await definicion.verificar(i.datos);
    if (!activo) return;
    switch (v.resultado) {
      case "registrada":
        intencion = null;
        emitir({ fase: "exito", jornadaId, mensaje: v.mensaje });
        alCambiarJornada();
        return;
      case "sin_efecto":
        emitir({ fase: "desconocido", jornadaId, mensaje: v.mensaje, reintentable: true });
        return;
      case "incierta":
        // Se conservan la clave y los datos: sólo un reintento con ellos (o
        // una verificación posterior) puede resolverla.
        emitir({ fase: "desconocido", jornadaId, mensaje: v.mensaje, reintentable: v.reintentable });
        return;
      case "sin_verificar":
        emitir({ fase: "desconocido", jornadaId, mensaje: v.mensaje, reintentable: false });
        return;
      case "descartada":
        intencion = null;
        emitir({ fase: "error", jornadaId, mensaje: v.mensaje });
        alCambiarJornada();
        return;
    }
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
    // Sólo para tests: los datos congelados de la intención en curso.
    datosEnCurso: () => intencion?.datos ?? null,
    solicitar,
    cancelar,
    confirmar,
    reintentar,
    verificarEstado,
    trasRelectura,
    iniciar,
    detener,
  };
}
