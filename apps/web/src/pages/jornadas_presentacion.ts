// Textos y formatos de la pantalla de jornadas (B-02b.1). Sin React.

import type { EstadoJornada } from "../lib/jornadas";

export const ETIQUETA_ESTADO_JORNADA: Record<EstadoJornada, string> = {
  abierta: "Abierta",
  cargada: "Cargada",
  en_reparto: "En reparto",
  ventas_finalizadas: "Ventas finalizadas",
  regreso_contado: "Regreso contado",
  cerrada: "Cerrada",
};

export const MENSAJE_NO_DISPONIBLE =
  "Todavía no disponible: abrir, cargar y descargar jornadas se habilitarán en una próxima etapa. Ya se puede confirmar la salida de una jornada cargada desde su detalle.";

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
