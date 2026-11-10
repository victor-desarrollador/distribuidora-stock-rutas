// Controlador de «Confirmar salida» (B-02b.2 / S1), sin React.
//
// Usa sólo `ejecutar` de la capa B-02a con el comando `salir` (RPC
// `confirmar_salida`); la lectura sigue en jornadas_lectura.ts, que no puede
// mutar. Desde S2 las garantías comunes (clave por intención, envío único,
// verificación ante respuesta perdida, reintento con la misma clave, intención
// incierta conservada, respuestas tardías descartadas) viven en el motor
// `jornadas_operacion.ts`; aquí sólo se define la salida.
//
// Reglas (ADR-007 §2.2; ADR-001 §18.4.3–§18.4.7):
// - Quién y cuándo lo decide el servidor (dueño/encargado activo, jornada
//   `cargada`, carga neta > 0). Aquí sólo se ofrece la acción en `cargada`;
//   el control lo muestra la pantalla sólo a dueño y encargado.
// - Sin respuesta: se lee el estado real de la jornada; si ya salió, se
//   informa como registrada; si sigue `cargada`, se ofrece reintentar con la
//   MISMA clave (el servidor devuelve la respuesta original si ya se registró).
// - Tras un éxito se relee la lista desde Supabase.

import type { EstadoJornada } from "../lib/jornadas";
import {
  OPERACION_INACTIVA,
  crearControladorOperacion,
  type ArbitroJornadas,
  type DefinicionOperacion,
  type FaseOperacion,
  type PuertoOperacion,
  type Verificacion,
} from "./jornadas_operacion";

export type PuertoSalida = PuertoOperacion;

/**
 * Estado real de la jornada leído de la base: el estado, `null` si ya no es
 * visible (RLS) o `undefined` si la lectura falló.
 */
export type VerificarJornada = (
  jornada: { id: string; fecha: string },
  actorEsperado?: string
) => Promise<EstadoJornada | null | undefined>;

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

export type FaseSalida = FaseOperacion;

export const SALIDA_INACTIVA: FaseSalida = OPERACION_INACTIVA;

// Estados posteriores a la salida (ADR-007 §2.2 y Blueprint §7.5).
const ESTADOS_TRAS_SALIDA: ReadonlySet<EstadoJornada> = new Set([
  "en_reparto",
  "ventas_finalizadas",
  "regreso_contado",
  "cerrada",
]);

interface DatosSalida {
  jornadaId: string;
  fecha: string;
}

function definicionSalida(verificar: VerificarJornada): DefinicionOperacion<void, DatosSalida> {
  return {
    admite: (jornada) => jornada.estado === "cargada",
    preparar: (jornada) => ({ ok: true, datos: { jornadaId: jornada.id, fecha: jornada.fecha } }),
    comando: (d) => ({ tipo: "salir", jornadaId: d.jornadaId }),
    mensajeExito: MENSAJE_SALIDA_OK,
    async verificar(d, actorEsperado?: string): Promise<Verificacion> {
      const estado = await verificar({ id: d.jornadaId, fecha: d.fecha }, actorEsperado);
      if (estado !== undefined && estado !== null && ESTADOS_TRAS_SALIDA.has(estado)) {
        return { resultado: "registrada", mensaje: MENSAJE_SALIDA_YA_REGISTRADA };
      }
      if (estado === "cargada") {
        return { resultado: "sin_efecto", mensaje: MENSAJE_SALIDA_SIGUE_CARGADA };
      }
      if (estado === undefined) {
        return { resultado: "sin_verificar", mensaje: MENSAJE_SALIDA_SIN_VERIFICAR };
      }
      // No visible o en un estado que no admite la salida: sin reintento.
      return { resultado: "descartada", mensaje: MENSAJE_SALIDA_NO_VISIBLE };
    },
    releerTrasRechazo: (codigo) => codigo === "jornada_estado_invalido",
  };
}

export function crearControladorSalida(
  puerto: PuertoSalida,
  verificar: VerificarJornada,
  alCambiarJornada: () => void,
  publicar: (fase: FaseSalida) => void,
  generarClave?: () => string,
  // Árbitro de la pantalla: excluye la corrección sobre la misma jornada (S2 M-02).
  arbitro?: ArbitroJornadas
) {
  const motor = crearControladorOperacion(
    definicionSalida(verificar),
    puerto,
    alCambiarJornada,
    publicar,
    generarClave,
    arbitro
  );
  return {
    obtener: motor.obtener,
    // Sólo para tests: la clave de la intención en curso (nunca se muestra).
    claveEnCurso: motor.claveEnCurso,
    solicitar: motor.solicitar,
    cancelar: motor.cancelar,
    confirmar: () => motor.confirmar(),
    reintentar: motor.reintentar,
    verificarEstado: motor.verificarEstado,
    iniciar: motor.iniciar,
    detener: motor.detener,
  };
}

export type ControladorSalida = ReturnType<typeof crearControladorSalida>;
