// Textos y formatos de la pantalla de jornadas (B-02b.1). Sin React.

import type { EstadoJornada } from "../lib/jornadas";
import { jornadaRetenida, type FaseOperacion } from "./jornadas_operacion";

export const ETIQUETA_ESTADO_JORNADA: Record<EstadoJornada, string> = {
  abierta: "Abierta",
  cargada: "Cargada",
  en_reparto: "En reparto",
  ventas_finalizadas: "Ventas finalizadas",
  regreso_contado: "Regreso contado",
  cerrada: "Cerrada",
};

export const MENSAJE_NO_DISPONIBLE =
  "Todavía no disponible: cargar y descargar mercadería de una jornada se habilitarán en una próxima etapa. Ya se puede abrir una jornada nueva, confirmar la salida de una jornada cargada, corregir la fecha o el camión de una jornada abierta y cambiar el vendedor de una jornada abierta o cargada desde su detalle.";

// FE-2B: qué operación retiene una jornada, para explicar por qué las demás
// están deshabilitadas (la exclusión efectiva la aplica el árbitro del motor).
export const MOTIVO_BLOQUEO_SALIDA =
  "Hay una confirmación de salida de esta jornada en curso o sin resolver. Terminala o verificá su estado antes de iniciar otra operación.";
export const MOTIVO_BLOQUEO_CORRECCION =
  "Hay una corrección de esta jornada en curso o sin resolver. Terminala o verificá su estado antes de iniciar otra operación.";
export const MOTIVO_BLOQUEO_REASIGNACION =
  "Hay un cambio de vendedor de esta jornada en curso o sin resolver. Terminalo o verificá su estado antes de iniciar otra operación.";

/** El motivo de la primera operación que retiene la jornada, o undefined. */
export function motivoBloqueo(
  jornadaId: string,
  otras: readonly { fase: FaseOperacion; motivo: string }[]
): string | undefined {
  return otras.find((o) => jornadaRetenida(o.fase) === jornadaId)?.motivo;
}

/** 'AAAA-MM-DD' → 'DD/MM/AAAA' sin pasar por Date (sin corrimientos de zona). */
export function formatearFechaOperativa(fecha: string): string {
  const [a, m, d] = fecha.split("-");
  return `${d}/${m}/${a}`;
}

export function formatearInstante(iso: string): string {
  const t = new Date(iso);
  if (Number.isNaN(t.getTime())) return "—";
  return new Intl.DateTimeFormat("es-AR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
    timeZone: "America/Argentina/Tucuman",
  }).format(t);
}

/** Identificador corto para mostrar cuando no hay un nombre confiable. */
export function idCorto(id: string): string {
  return id.slice(0, 8);
}
