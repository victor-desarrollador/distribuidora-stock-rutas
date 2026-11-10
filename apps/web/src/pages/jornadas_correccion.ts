// Controlador de «Corregir jornada» (B-02b.2 / S2), sin React.
//
// Usa sólo `ejecutar` de la capa B-02a con el comando `corregir` (RPC
// `corregir_jornada`) sobre el motor común `jornadas_operacion.ts` (clave por
// intención, envío único, verificación ante respuesta perdida, reintento con la
// misma clave y el mismo comando congelado, intención incierta conservada,
// arbitraje con la salida sobre la misma jornada).
//
// Contrato de la RPC (migración 20261109120000; ADR-007 §2.4 y §2.7):
// - Sólo dueño y encargado activos; sólo una jornada `abierta` sin movimientos.
// - Cambia la fecha, el camión o ambos; motivo obligatorio (el servidor lo
//   recorta). No cambia el estado ni el vendedor ni mueve stock ni dinero.
// - Revalida siempre la fecha (>= día operativo de Tucumán) y el camión final
//   (de la empresa y activo), el par (camión, fecha) y el vendedor vigente.
// - Idempotente por (empresa, actor, clave) con huella del payload: reenviar
//   la MISMA clave con OTRO payload da `jornada_conflicto_idempotencia`; por eso
//   el reintento reutiliza los datos congelados de la intención.
// - El replay por clave (paso 5) ocurre ANTES de las validaciones de negocio
//   (paso 10): reenviar la misma clave con el mismo payload devuelve la
//   operación original si se registró y, si no, revalida todo desde cero.
// La validación local es igual o más laxa que la del servidor, que decide.
//
// Respuesta perdida (corrección M-01 de la auditoría de S2): leer la jornada
// NUNCA prueba que ESTA corrección se registró (otro actor puede haber llegado
// a los mismos valores, o la primera solicitud puede seguir en curso). Por eso
// la verificación no declara éxito: sólo distingue si reenviar la MISMA
// intención es seguro. Sólo la respuesta del servidor a ese reenvío (uuid de la
// operación, o un rechazo definitivo) resuelve la intención. No se usan
// lecturas nuevas: `operaciones` y `correcciones_jornada` son legibles por
// gestión, pero consultarlas por clave sería un contrato de datos nuevo fuera
// del alcance de S2.

import { esFechaValida, esUuid, type Jornada } from "../lib/jornadas";
import {
  OPERACION_INACTIVA,
  crearControladorOperacion,
  type ArbitroJornadas,
  type DefinicionOperacion,
  type FaseOperacion,
  type PuertoOperacion,
  type Verificacion,
} from "./jornadas_operacion";

export type FaseCorreccion = FaseOperacion;
export const CORRECCION_INACTIVA: FaseCorreccion = OPERACION_INACTIVA;

export interface EntradaCorreccion {
  fecha: string;
  camionId: string;
  motivo: string;
}

export interface DatosCorreccion {
  jornadaId: string;
  // Valores de la jornada al confirmar: permiten saber, tras una respuesta
  // perdida, si la corrección tuvo efecto.
  original: { fecha: string; camionId: string };
  fecha: string;
  camionId: string;
  motivo: string;
}

/**
 * Busca la jornada en la base entre las fechas indicadas: la jornada, `null`
 * si no es visible en ninguna o `undefined` si alguna lectura falló.
 */
export type BuscarJornada = (
  id: string,
  fechas: string[],
  actorEsperado?: string
) => Promise<Jornada | null | undefined>;

export const MENSAJE_CORRECCION_OK = "Corrección registrada. La jornada se actualizó.";
export const MENSAJE_CORRECCION_SIN_EFECTO =
  "No se pudo confirmar si la corrección se registró y la jornada sigue sin cambios. Podés reintentar: se reenvía la misma corrección y no se registra dos veces.";
export const MENSAJE_CORRECCION_SIN_VERIFICAR =
  "No se pudo confirmar si la corrección se registró ni leer la jornada. Verificá el estado antes de reintentar.";
export const MENSAJE_CORRECCION_COINCIDE =
  "La jornada ya tiene la fecha y el camión indicados, pero no se puede asegurar que sea por esta corrección (pudo registrarla otra persona). Reintentá para confirmarlo: se reenvía la misma corrección; si ya se registró no se repite y, si no, se rechaza sin cambios.";
export const MENSAJE_CORRECCION_OTRO_ESTADO =
  "No se pudo confirmar si la corrección se registró y la jornada ya no está abierta. Reintentá para confirmarlo: se reenvía la misma corrección; si ya se registró no se repite y, si no, se rechaza sin cambios.";
export const MENSAJE_CORRECCION_OTROS_VALORES =
  "No se pudo confirmar si la corrección se registró y la jornada tiene otra fecha o camión (pudo cambiarla otra persona). No se ofrece reintentar para no pisar ese cambio: verificá el estado o revisá la jornada.";
export const MENSAJE_CORRECCION_NO_VISIBLE =
  "No se pudo confirmar si la corrección se registró y la jornada no aparece en la fecha original ni en la nueva. Verificá el estado o revisá la lista.";

export const MENSAJE_MOTIVO_OBLIGATORIO = "El motivo es obligatorio.";
export const MENSAJE_FECHA_INVALIDA = "Ingresá una fecha válida.";
export const MENSAJE_FECHA_PASADA =
  "La fecha no puede ser anterior al día operativo actual.";
export const MENSAJE_CAMION_INVALIDO = "Elegí un camión.";
export const MENSAJE_SIN_CAMBIOS =
  "No hay cambios para registrar: cambiá la fecha, el camión o ambos.";

// Rechazos definitivos que indican que la jornada cambió en la base.
// `jornada_sin_cambios` sólo puede llegar si la jornada cambió después de
// leerla (la validación local impide enviar los mismos valores), p. ej. al
// reintentar cuando otra persona ya registró esos valores.
const CODIGOS_RELEER: ReadonlySet<string> = new Set([
  "jornada_estado_invalido",
  "jornada_con_movimientos",
  "jornada_no_encontrada",
  "jornada_sin_cambios",
]);

/** Día operativo actual 'AAAA-MM-DD' en America/Argentina/Tucuman (ADR-007). */
export function fechaOperativaHoy(ahora: Date = new Date()): string {
  const partes = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Argentina/Tucuman",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(ahora);
  const valor = (tipo: string) => partes.find((p) => p.type === tipo)?.value ?? "";
  return `${valor("year")}-${valor("month")}-${valor("day")}`;
}

/** Validación local de la entrada; `null` si se puede enviar. */
export function validarCorreccion(
  jornada: Pick<Jornada, "fecha" | "camionId">,
  entrada: EntradaCorreccion,
  hoy: string
): string | null {
  if (!esFechaValida(entrada.fecha)) return MENSAJE_FECHA_INVALIDA;
  // 'AAAA-MM-DD' se ordena lexicográficamente igual que cronológicamente.
  if (entrada.fecha < hoy) return MENSAJE_FECHA_PASADA;
  if (!esUuid(entrada.camionId)) return MENSAJE_CAMION_INVALIDO;
  if (entrada.motivo.trim() === "") return MENSAJE_MOTIVO_OBLIGATORIO;
  if (entrada.fecha === jornada.fecha && entrada.camionId === jornada.camionId) {
    return MENSAJE_SIN_CAMBIOS;
  }
  return null;
}

export function definicionCorreccion(
  buscar: BuscarJornada,
  hoy: () => string
): DefinicionOperacion<EntradaCorreccion, DatosCorreccion> {
  return {
    admite: (jornada) => jornada.estado === "abierta",
    preparar(jornada, entrada) {
      const error = validarCorreccion(jornada, entrada, hoy());
      if (error !== null) return { ok: false, mensaje: error };
      return {
        ok: true,
        datos: {
          jornadaId: jornada.id,
          original: { fecha: jornada.fecha, camionId: jornada.camionId },
          fecha: entrada.fecha,
          camionId: entrada.camionId,
          motivo: entrada.motivo.trim(),
        },
      };
    },
    comando: (d) => ({
      tipo: "corregir",
      jornadaId: d.jornadaId,
      fecha: d.fecha,
      camionId: d.camionId,
      motivo: d.motivo,
    }),
    mensajeExito: MENSAJE_CORRECCION_OK,
    async verificar(d, actorEsperado?: string): Promise<Verificacion> {
      const fechas = d.original.fecha === d.fecha ? [d.fecha] : [d.original.fecha, d.fecha];
      const j = await buscar(d.jornadaId, fechas, actorEsperado);
      if (j === undefined) {
        return { resultado: "sin_verificar", mensaje: MENSAJE_CORRECCION_SIN_VERIFICAR };
      }
      if (j === null) {
        // Pudo moverse a otra fecha (por esta u otra corrección): no se sabe.
        return { resultado: "incierta", mensaje: MENSAJE_CORRECCION_NO_VISIBLE, reintentable: false };
      }
      // Coincidir con lo pedido NO prueba que se haya registrado ESTA
      // corrección. Reenviar es seguro: si fue ésta, el replay devuelve la
      // operación original; si no, el servidor da `jornada_sin_cambios` (o
      // `jornada_estado_invalido`) y no cambia nada.
      if (j.fecha === d.fecha && j.camionId === d.camionId) {
        return { resultado: "incierta", mensaje: MENSAJE_CORRECCION_COINCIDE, reintentable: true };
      }
      // La RPC escribe operación, historial y jornada en UNA transacción: si la
      // jornada sigue abierta con los valores originales, esta corrección no
      // tuvo efecto TODAVÍA (la primera solicitud podría seguir en curso; el
      // reenvío con la misma clave espera esa reserva y devuelve su resultado).
      if (
        j.estado === "abierta" &&
        j.fecha === d.original.fecha &&
        j.camionId === d.original.camionId
      ) {
        return { resultado: "sin_efecto", mensaje: MENSAJE_CORRECCION_SIN_EFECTO };
      }
      // Ya no abierta: el servidor no puede aplicar la corrección de nuevo; el
      // reenvío sólo confirma (replay) o rechaza sin efecto.
      if (j.estado !== "abierta") {
        return { resultado: "incierta", mensaje: MENSAJE_CORRECCION_OTRO_ESTADO, reintentable: true };
      }
      // Abierta con otros valores: reenviar podría aplicar esta corrección
      // sobre el cambio de otra persona. Se conserva la intención sin reintento.
      return { resultado: "incierta", mensaje: MENSAJE_CORRECCION_OTROS_VALORES, reintentable: false };
    },
    releerTrasRechazo: (codigo) => codigo !== null && CODIGOS_RELEER.has(codigo),
  };
}

export function crearControladorCorreccion(
  puerto: PuertoOperacion,
  buscar: BuscarJornada,
  alCambiarJornada: () => void,
  publicar: (fase: FaseCorreccion) => void,
  opciones: { hoy?: () => string; generarClave?: () => string; arbitro?: ArbitroJornadas } = {}
) {
  return crearControladorOperacion(
    definicionCorreccion(buscar, opciones.hoy ?? (() => fechaOperativaHoy())),
    puerto,
    alCambiarJornada,
    publicar,
    opciones.generarClave,
    opciones.arbitro
  );
}

export type ControladorCorreccion = ReturnType<typeof crearControladorCorreccion>;
