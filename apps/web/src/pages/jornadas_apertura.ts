// Controlador de «Abrir jornada» (D-B2-1), sin React.
//
// Independiente del motor `jornadas_operacion.ts`: ese motor opera sobre una
// jornada que ya existe (fases y árbitro por `jornadaId`); la apertura no
// tiene jornada previa. S1 y S2 no se modifican.
//
// Contrato de la RPC (migración 20261031120000, cuerpo vigente en
// 20261105130000; ADR-007 §2.1–§2.3):
//   public.abrir_jornada(p_idempotency_key, p_camion_id, p_fecha, p_vendedor_id)
//   → uuid de la jornada creada.
// - Sólo dueño y encargado activos. Fecha >= día operativo de Tucumán; camión
//   activo de la empresa sin otra jornada sin cerrar; una jornada por camión y
//   fecha; vendedor = perfil activo de la empresa, con una jornada por fecha.
// - Idempotente por (empresa, actor, clave) con huella del payload: la MISMA
//   clave con el MISMO payload devuelve el uuid de la jornada original; con
//   OTRO payload, `jornada_conflicto_idempotencia`. El replay se resuelve antes
//   de las validaciones de negocio.
// La validación local es igual o más estricta en forma (fecha, camión y
// vendedor de las listas reales) y nunca reemplaza al servidor, que decide.
//
// Garantías:
// - Una clave por INTENCIÓN: nace al confirmar, se conserva en cada reintento
//   de esa intención (mismos datos, comando congelado) y se descarta sólo con
//   un resultado cierto. Sólo vive en memoria: nada se guarda en el navegador.
// - Envío único: durante un envío o una consulta cualquier acción se ignora.
// - ÉXITO sólo con el uuid que devuelve `abrir_jornada`, en el envío original
//   o en el reintento de la MISMA clave y el MISMO payload (criterio del
//   responsable, 07/11/2026). Ante una respuesta perdida se lee la lista de
//   jornadas de esa fecha SÓLO para informar: una coincidencia por camión,
//   fecha, vendedor o `abiertaPor` NO prueba que esta intención se ejecutó y
//   nunca pasa la fase a éxito ni descarta la intención.
// - Una intención con resultado desconocido no se descarta: hasta resolverla
//   (reintento con la misma clave) no se inicia otra.
// - Tras el desmontaje, las respuestas tardías no publican ni releen.

import {
  esFechaValida,
  esUuid,
  nuevaClaveIdempotencia,
  type ComandoJornada,
  type Jornada,
  type PuertoJornadas,
} from "../lib/jornadas";
import {
  MENSAJE_ERROR_VENDEDORES,
  type PuertoVendedoresJornada,
  type VendedorJornada,
} from "../lib/vendedores_jornada";
import {
  MENSAJE_CAMION_INVALIDO,
  MENSAJE_FECHA_INVALIDA,
  MENSAJE_FECHA_PASADA,
  fechaOperativaHoy,
} from "./jornadas_correccion";
import type { PuertoOperacion } from "./jornadas_operacion";
import { ETIQUETA_ESTADO_JORNADA } from "./jornadas_presentacion";

export interface EntradaApertura {
  camionId: string;
  fecha: string;
  vendedorId: string;
}

/** Ids que la pantalla ofreció en sus listas reales (camiones activos y vendedores). */
export interface OpcionesPermitidas {
  camiones: readonly string[];
  vendedores: readonly string[];
}

export type FaseApertura =
  | { fase: "inactiva" }
  // `error`: validación local (no se envió nada).
  | { fase: "editando"; error?: string }
  | { fase: "enviando"; datos: EntradaApertura }
  // Respuesta perdida: lectura SÓLO informativa en curso.
  | { fase: "verificando"; datos: EntradaApertura }
  // `releida`: la lista ya se volvió a leer después del éxito.
  | {
      fase: "exito";
      jornadaId: string;
      datos: EntradaApertura;
      mensaje: string;
      releida?: true;
    }
  // Rechazo definitivo del servidor: la transacción se revirtió.
  // `recuperacion` (T-2): sólo ante `jornada_duplicada` o
  // `jornada_vendedor_ocupado`, la fecha cuyas jornadas conviene revisar porque
  // pudo existir una apertura anterior. Es sólo orientación: no cambia la fase.
  | { fase: "error"; mensaje: string; recuperacion?: RecuperacionApertura }
  // Siempre reintentable: reenviar la MISMA clave y el MISMO payload devuelve
  // la jornada original o se evalúa desde cero; nunca crea una segunda.
  | {
      fase: "desconocido";
      datos: EntradaApertura;
      mensaje: string;
      // Lo observado en la lectura informativa (null si no hay nada que decir).
      informacion: string | null;
    };

export interface RecuperacionApertura {
  // Fecha operativa 'AAAA-MM-DD' de la apertura rechazada.
  fecha: string;
  mensaje: string;
}

export const APERTURA_INACTIVA: FaseApertura = { fase: "inactiva" };

/**
 * T-1: fases en las que recargar o cerrar la pantalla pierde la intención en
 * memoria (clave y datos) y con ella el reintento seguro. La pantalla pide al
 * navegador que confirme la salida sólo en estas fases; el navegador puede no
 * mostrar el aviso. No se guarda nada en el navegador.
 */
export function faseConRiesgoApertura(fase: FaseApertura): boolean {
  return fase.fase === "enviando" || fase.fase === "verificando" || fase.fase === "desconocido";
}

/** T-1: advertencia visible en `desconocido`; no promete el aviso del navegador. */
export const MENSAJE_RIESGO_RECARGA =
  "Si recargás o cerrás esta pantalla, se pierde el reintento seguro de esta apertura. El navegador puede pedirte confirmación antes de salir, pero no siempre lo hace.";

// T-2: orientación ante rechazos que pueden deberse a una apertura anterior
// (por ejemplo, una respuesta perdida seguida de una recarga, que cambia la
// clave) o a otra persona. Nunca afirman que esta apertura se registró.
export const MENSAJE_RECUPERACION_DUPLICADA =
  "Puede que esa jornada ya se haya abierto en un intento anterior (por ejemplo, si se perdió la conexión o recargaste la pantalla) o que la haya abierto otra persona. Revisá las jornadas de esa fecha antes de volver a intentar.";
export const MENSAJE_RECUPERACION_VENDEDOR_OCUPADO =
  "Puede que ese vendedor ya tenga asignada la jornada en un intento anterior (por ejemplo, si se perdió la conexión o recargaste la pantalla) o que se la haya asignado otra persona. Revisá las jornadas de esa fecha antes de volver a intentar.";
export const MENSAJE_RECUPERACION_NO_CONFIRMA =
  "Ver la lista no confirma que tu apertura se haya registrado.";

const MENSAJES_RECUPERACION: Readonly<Record<string, string>> = {
  jornada_duplicada: MENSAJE_RECUPERACION_DUPLICADA,
  jornada_vendedor_ocupado: MENSAJE_RECUPERACION_VENDEDOR_OCUPADO,
};

/** Orientación de recuperación para un rechazo; `undefined` si no corresponde. */
export function recuperacionPara(
  codigo: string | null,
  fecha: string
): RecuperacionApertura | undefined {
  if (codigo === null || !Object.hasOwn(MENSAJES_RECUPERACION, codigo)) return undefined;
  return { fecha, mensaje: MENSAJES_RECUPERACION[codigo] };
}

export const MENSAJE_APERTURA_OK = "Jornada abierta.";
export const MENSAJE_VENDEDOR_INVALIDO = "Elegí un vendedor de la lista.";
export const MENSAJE_CAMION_NO_OFRECIDO = "Elegí un camión activo de la lista.";
export const MENSAJE_APERTURA_DESCONOCIDA =
  "No se pudo confirmar si la jornada se abrió. Reintentá desde esta pantalla, sin recargarla: se reenvía la misma apertura con la misma clave; si ya se registró no se repite.";
export const MENSAJE_INFO_SIN_LECTURA =
  "Tampoco se pudo leer la lista de jornadas de esa fecha.";
export const MENSAJE_INFO_SIN_COINCIDENCIA =
  "En la lista actual no aparece ninguna jornada de ese camión en esa fecha. Esto no confirma que la apertura no se haya registrado.";

/** Texto informativo de una jornada observada; nunca afirma que la abrió esta solicitud. */
export function informacionCoincidencia(j: Jornada, datos: EntradaApertura): string {
  const conVendedor =
    j.vendedorId.toLowerCase() === datos.vendedorId.toLowerCase()
      ? " con el vendedor elegido"
      : " con otro vendedor";
  return `En la lista actual hay una jornada ${ETIQUETA_ESTADO_JORNADA[j.estado].toLowerCase()} de ese camión en esa fecha${conVendedor}. Esto no confirma que la haya abierto esta solicitud: sólo el reintento lo confirma.`;
}

// Rechazos definitivos que indican que las jornadas cambiaron: se relee la lista.
const CODIGOS_RELEER_JORNADAS: ReadonlySet<string> = new Set([
  "jornada_duplicada",
  "jornada_camion_con_jornada_abierta",
  "jornada_vendedor_ocupado",
]);

// Rechazos que indican que la lista de vendedores quedó vieja.
const CODIGOS_RELEER_VENDEDORES: ReadonlySet<string> = new Set([
  "jornada_vendedor_no_encontrado",
  "jornada_vendedor_invalido",
]);

// 40001/40P01 agotados: la transacción se revirtió; se trata como respuesta
// dudosa (se informa y se ofrece reintentar con la misma clave).
const CODIGOS_TRANSITORIOS: ReadonlySet<string> = new Set(["40001", "40P01"]);

const incluye = (lista: readonly string[], id: string) =>
  lista.some((x) => x.toLowerCase() === id.toLowerCase());

/** Validación local de la entrada; `null` si se puede enviar. */
export function validarApertura(
  entrada: EntradaApertura,
  hoy: string,
  permitidas: OpcionesPermitidas
): string | null {
  if (!esUuid(entrada.camionId)) return MENSAJE_CAMION_INVALIDO;
  if (!incluye(permitidas.camiones, entrada.camionId)) return MENSAJE_CAMION_NO_OFRECIDO;
  if (!esFechaValida(entrada.fecha)) return MENSAJE_FECHA_INVALIDA;
  // 'AAAA-MM-DD' se ordena lexicográficamente igual que cronológicamente.
  if (entrada.fecha < hoy) return MENSAJE_FECHA_PASADA;
  if (!esUuid(entrada.vendedorId) || !incluye(permitidas.vendedores, entrada.vendedorId)) {
    return MENSAJE_VENDEDOR_INVALIDO;
  }
  return null;
}

export type LeerJornadasFecha = Pick<PuertoJornadas, "leerTodasLasJornadas">;

interface Intencion {
  datos: EntradaApertura;
  comando: ComandoJornada;
  clave: string;
}

export function crearControladorApertura(
  puerto: PuertoOperacion,
  lectura: LeerJornadasFecha,
  alCambiarJornadas: () => void,
  publicar: (fase: FaseApertura) => void,
  opciones: {
    hoy?: () => string;
    generarClave?: () => string;
    alRechazoVendedor?: () => void;
  } = {}
) {
  const hoy = opciones.hoy ?? (() => fechaOperativaHoy());
  const generarClave = opciones.generarClave ?? nuevaClaveIdempotencia;
  let fase: FaseApertura = APERTURA_INACTIVA;
  let intencion: Intencion | null = null;
  let activo = true;

  function emitir(nueva: FaseApertura) {
    fase = nueva;
    if (activo) publicar(fase);
  }

  const ocupado = () => fase.fase === "enviando" || fase.fase === "verificando";
  const editable = () => fase.fase === "editando" || fase.fase === "error";

  /** Abre el formulario. Bloqueado con un envío, una duda o un éxito sin releer. */
  function solicitar(): void {
    if (ocupado() || fase.fase === "desconocido" || fase.fase === "editando") return;
    if (fase.fase === "exito" && fase.releida !== true) return;
    emitir({ fase: "editando" });
  }

  function cancelar(): void {
    if (!editable()) return;
    emitir(APERTURA_INACTIVA);
  }

  /** Confirmación explícita: si la entrada es válida, nace la intención y su clave. */
  function confirmar(entrada: EntradaApertura, permitidas: OpcionesPermitidas): Promise<void> {
    if (!editable()) return Promise.resolve();
    const error = validarApertura(entrada, hoy(), permitidas);
    if (error !== null) {
      emitir({ fase: "editando", error });
      return Promise.resolve();
    }
    const datos: EntradaApertura = Object.freeze({
      camionId: entrada.camionId,
      fecha: entrada.fecha,
      vendedorId: entrada.vendedorId,
    });
    intencion = {
      datos,
      comando: Object.freeze({ tipo: "abrir", ...datos }),
      clave: generarClave(),
    };
    return enviar(intencion);
  }

  /** Reintento de la MISMA intención (misma clave y mismo comando congelado). */
  function reintentar(): Promise<void> {
    if (fase.fase !== "desconocido" || intencion === null) return Promise.resolve();
    return enviar(intencion);
  }

  /** La lista se volvió a leer: un éxito deja de bloquear una NUEVA intención. */
  function trasRelectura(): void {
    if (fase.fase === "exito" && fase.releida !== true) {
      emitir({ ...fase, releida: true });
    }
  }

  async function enviar(i: Intencion): Promise<void> {
    emitir({ fase: "enviando", datos: i.datos });
    const r = await puerto.ejecutar(i.comando, i.clave);
    if (!activo) return;
    if (r.ok) {
      // Única confirmación válida: el uuid devuelto por abrir_jornada.
      intencion = null;
      emitir({ fase: "exito", jornadaId: r.datos, datos: i.datos, mensaje: MENSAJE_APERTURA_OK });
      alCambiarJornadas();
      return;
    }
    const dudoso =
      r.error.resultadoDesconocido ||
      (r.error.codigo !== null && CODIGOS_TRANSITORIOS.has(r.error.codigo));
    if (dudoso) {
      await informar(i);
      return;
    }
    // Rechazo definitivo: la transacción se revirtió y la clave no se consumió.
    intencion = null;
    const recuperacion = recuperacionPara(r.error.codigo, i.datos.fecha);
    emitir(
      recuperacion
        ? { fase: "error", mensaje: r.error.mensaje, recuperacion }
        : { fase: "error", mensaje: r.error.mensaje }
    );
    if (r.error.codigo !== null && CODIGOS_RELEER_JORNADAS.has(r.error.codigo)) {
      alCambiarJornadas();
    }
    if (r.error.codigo !== null && CODIGOS_RELEER_VENDEDORES.has(r.error.codigo)) {
      opciones.alRechazoVendedor?.();
    }
  }

  /** Lectura SÓLO informativa tras una respuesta perdida: nunca declara éxito. */
  async function informar(i: Intencion): Promise<void> {
    emitir({ fase: "verificando", datos: i.datos });
    let informacion: string;
    try {
      const r = await lectura.leerTodasLasJornadas({ fecha: i.datos.fecha });
      if (!r.ok) {
        informacion = MENSAJE_INFO_SIN_LECTURA;
      } else {
        const j = r.datos.find(
          (x) => x.camionId.toLowerCase() === i.datos.camionId.toLowerCase()
        );
        informacion = j ? informacionCoincidencia(j, i.datos) : MENSAJE_INFO_SIN_COINCIDENCIA;
      }
    } catch {
      informacion = MENSAJE_INFO_SIN_LECTURA;
    }
    if (!activo) return;
    // La intención (clave y datos) se conserva: sólo su reintento la resuelve.
    emitir({ fase: "desconocido", datos: i.datos, mensaje: MENSAJE_APERTURA_DESCONOCIDA, informacion });
  }

  function iniciar(): void {
    activo = true;
  }

  function detener(): void {
    activo = false;
  }

  return {
    obtener: () => fase,
    // Sólo para tests: la clave de la intención en curso (nunca se muestra).
    claveEnCurso: () => intencion?.clave ?? null,
    // Sólo para tests: el comando congelado de la intención en curso.
    comandoEnCurso: () => intencion?.comando ?? null,
    solicitar,
    cancelar,
    confirmar,
    reintentar,
    trasRelectura,
    iniciar,
    detener,
  };
}

export type ControladorApertura = ReturnType<typeof crearControladorApertura>;

// ---------------------------------------------------------------------------
// Lectura de vendedores para el formulario
// ---------------------------------------------------------------------------

export type EstadoVendedores =
  | { estado: "inactivo" }
  | { estado: "cargando" }
  | { estado: "error"; mensaje: string }
  | { estado: "listo"; vendedores: VendedorJornada[] };

export const VENDEDORES_INACTIVO: EstadoVendedores = { estado: "inactivo" };

/**
 * Lee la lista real de vendedores. Sólo publica la respuesta de la ÚLTIMA
 * lectura pedida; tras el desmontaje no publica nada.
 */
export function crearControladorVendedores(
  puerto: PuertoVendedoresJornada,
  publicar: (estado: EstadoVendedores) => void
) {
  let generacion = 0;
  let activo = true;
  let estado: EstadoVendedores = VENDEDORES_INACTIVO;

  function emitir(nuevo: EstadoVendedores) {
    estado = nuevo;
    if (activo) publicar(estado);
  }

  async function recargar(): Promise<void> {
    const propia = ++generacion;
    emitir({ estado: "cargando" });
    let nuevo: EstadoVendedores;
    try {
      const r = await puerto.listarVendedores();
      nuevo = r.ok
        ? { estado: "listo", vendedores: r.vendedores }
        : { estado: "error", mensaje: r.mensaje };
    } catch {
      nuevo = { estado: "error", mensaje: MENSAJE_ERROR_VENDEDORES };
    }
    if (!activo || propia !== generacion) return;
    emitir(nuevo);
  }

  return {
    obtener: () => estado,
    recargar,
    iniciar: () => {
      activo = true;
    },
    detener: () => {
      activo = false;
    },
  };
}
