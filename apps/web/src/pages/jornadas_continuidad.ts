// Estado de jornada y bloqueos de continuidad (B-02b.2 / S3-1), SÓLO LECTURA y
// sin lecturas propias: deriva todo de la jornada ya leída y del historial de
// cargas y descargas de S3-0 (pages/jornadas_historial.ts). Sin React.
//
// Blueprint §7.5 (flujo abierta → cargada → en_reparto → ventas_finalizadas →
// regreso_contado → cerrada, sin transiciones implícitas), §7.8 y §7.9 (conteo,
// regularización y cierre explícitos) y ADR-007 (el camión no admite otra
// jornada mientras tenga una sin cerrar).
//
// Reglas de presentación:
// - La «carga neta registrada» es cargas − descargas de ESTA jornada según el
//   sistema. NO es un conteo, ni el saldo real del camión, ni una diferencia:
//   la mercadería física puede diferir (por ejemplo, ventas en papel todavía no
//   registradas). Nunca se muestra como faltante ni sobrante.
// - Los pasos que el sistema todavía no registra (ventas finalizadas, conteo
//   formal, retorno, regularización, rendición y cierre) se informan como «no
//   disponible»: no se ofrecen acciones.

import type { EstadoJornada, Jornada } from "../lib/jornadas";
import type { HistorialJornada, ProductoHistorial } from "../lib/jornadas_historial";
import { etiquetaProducto, type EstadoHistorial } from "./jornadas_historial";

export type EstadoPaso = "hecho" | "pendiente" | "no_disponible";

export interface PasoContinuidad {
  clave: string;
  titulo: string;
  estado: EstadoPaso;
  detalle: string;
}

export interface LineaCargaNeta {
  productoId: string;
  producto: string;
  cantidad: string;
}

export type CargaNetaJornada =
  | { estado: "cargando" }
  | { estado: "error"; mensaje: string }
  | { estado: "listo"; lineas: LineaCargaNeta[] };

export interface Continuidad {
  pasos: PasoContinuidad[];
  cerrada: boolean;
  // true mientras la jornada no esté cerrada: el camión no puede abrir otra.
  bloqueaCamion: boolean;
  cargaNeta: CargaNetaJornada;
}

export const ETIQUETA_ESTADO_PASO: Record<EstadoPaso, string> = {
  hecho: "Hecho",
  pendiente: "Pendiente",
  no_disponible: "No disponible todavía",
};

export const MENSAJE_NO_CERRABLE =
  "Esta jornada todavía no puede cerrarse: el sistema aún no registra ventas finalizadas, conteo formal de regreso, retorno, regularización, rendición ni cierre.";
export const MENSAJE_SIN_CARGA_NETA =
  "Esta jornada no tiene carga neta registrada.";
export const MENSAJE_CARGA_NETA_ERROR =
  "No se pudo calcular la carga neta registrada de esta jornada. Actualizá el historial.";
export const ACLARACION_REGISTRADO =
  "Es lo registrado en el sistema para esta jornada (cargas menos descargas). No es un conteo físico ni el saldo real del camión: la mercadería física puede diferir, por ejemplo por ventas en papel todavía no registradas.";

export function mensajeCamionBloqueado(nombreCamion: string): string {
  return `Mientras esta jornada no se cierre, ${nombreCamion} no puede abrir otra jornada.`;
}

const ORDEN: Record<EstadoJornada, number> = {
  abierta: 0,
  cargada: 1,
  en_reparto: 2,
  ventas_finalizadas: 3,
  regreso_contado: 4,
  cerrada: 5,
};

const alcanzado = (estado: EstadoJornada, minimo: EstadoJornada) => ORDEN[estado] >= ORDEN[minimo];

/** Pasos del circuito de la jornada según su estado real. */
export function pasosContinuidad(estado: EstadoJornada): PasoContinuidad[] {
  const noDisponible = (clave: string, titulo: string, minimo: EstadoJornada, detalle: string): PasoContinuidad =>
    alcanzado(estado, minimo)
      ? { clave, titulo, estado: "hecho", detalle: "Registrado." }
      : { clave, titulo, estado: "no_disponible", detalle };

  return [
    alcanzado(estado, "cargada")
      ? { clave: "carga", titulo: "Carga del camión", estado: "hecho", detalle: "Hay al menos una carga registrada." }
      : {
          clave: "carga",
          titulo: "Carga del camión",
          estado: "pendiente",
          detalle: "Todavía no hay cargas registradas. La carga desde esta pantalla aún no está habilitada.",
        },
    alcanzado(estado, "en_reparto")
      ? { clave: "salida", titulo: "Salida", estado: "hecho", detalle: "Salida confirmada." }
      : {
          clave: "salida",
          titulo: "Salida",
          estado: "pendiente",
          detalle:
            estado === "cargada"
              ? "Se confirma desde esta pantalla («Confirmar salida»)."
              : "Requiere que la jornada esté cargada.",
        },
    noDisponible("ventas", "Ventas finalizadas", "ventas_finalizadas", "El sistema todavía no registra ventas ni su finalización."),
    noDisponible("conteo", "Conteo formal de regreso", "regreso_contado", "El sistema todavía no registra el conteo de regreso."),
    noDisponible(
      "retorno",
      "Retorno y regularización",
      "cerrada",
      "El sistema todavía no registra el retorno al depósito ni la regularización."
    ),
    noDisponible("cierre", "Rendición y cierre", "cerrada", "El sistema todavía no registra la rendición ni el cierre."),
  ];
}

/** Gramos o unidades exactos (BigInt) → «12 un.» o «1,250 kg». */
export function formatearCantidadExacta(
  cantidad: bigint,
  formaVenta: ProductoHistorial["formaVenta"]
): string {
  if (formaVenta === "peso") {
    const digitos = cantidad.toString().padStart(4, "0");
    return `${digitos.slice(0, -3)},${digitos.slice(-3)} kg`;
  }
  return `${cantidad} un.`;
}

/**
 * Cargas − descargas por producto de la jornada (exacto, BigInt). Se omiten
 * los productos en cero. Un neto negativo no puede ocurrir (la descarga no
 * supera la carga neta, ADR-007 §2.6): si aparece, devuelve null (falla
 * cerrada, nunca se muestra como faltante).
 */
export function cargaNetaJornada(historial: HistorialJornada): LineaCargaNeta[] | null {
  const netos = new Map<string, bigint>();
  for (const o of historial.operaciones) {
    for (const l of o.lineas) {
      const clave = l.productoId.toLowerCase();
      const signo = o.tipo === "carga" ? 1n : -1n;
      netos.set(clave, (netos.get(clave) ?? 0n) + signo * BigInt(l.cantidad));
    }
  }
  const lineas: LineaCargaNeta[] = [];
  for (const [clave, neto] of netos) {
    if (neto < 0n) return null;
    if (neto === 0n) continue;
    const p = historial.productos[clave];
    if (!p) return null;
    lineas.push({ productoId: p.id, producto: etiquetaProducto(p), cantidad: formatearCantidadExacta(neto, p.formaVenta) });
  }
  return lineas.sort((a, b) => a.producto.localeCompare(b.producto, "es-AR") || a.productoId.localeCompare(b.productoId));
}

export function armarContinuidad(jornada: Jornada, historial: EstadoHistorial): Continuidad {
  const cerrada = jornada.estado === "cerrada";
  let cargaNeta: CargaNetaJornada;
  // El historial sólo vale si es de ESTA jornada.
  if (historial.estado === "listo" && historial.jornadaId === jornada.id) {
    const lineas = cargaNetaJornada(historial.historial);
    cargaNeta = lineas === null ? { estado: "error", mensaje: MENSAJE_CARGA_NETA_ERROR } : { estado: "listo", lineas };
  } else if (historial.estado === "error" && historial.jornadaId === jornada.id) {
    cargaNeta = { estado: "error", mensaje: MENSAJE_CARGA_NETA_ERROR };
  } else {
    cargaNeta = { estado: "cargando" };
  }
  return { pasos: pasosContinuidad(jornada.estado), cerrada, bloqueaCamion: !cerrada, cargaNeta };
}
