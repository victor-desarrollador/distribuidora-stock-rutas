// Historial de cargas y descargas de una jornada (B-02b.2 / S3-0), sin React.
//
// - Sólo lectura: el controlador nunca crea, modifica, cancela ni reintenta
//   operaciones; sólo vuelve a LEER cuando se le pide.
// - Sólo la última lectura iniciada publica su resultado (cambiar de jornada o
//   actualizar descarta respuestas viejas). Ante un error no se muestran datos
//   viejos: falla cerrada.
// - Tras `detener` (desmontaje), ninguna respuesta tardía publica.
// - Presentación pura: textos y cantidades en unidades o kg (ADR-005), sin
//   pasar por float. El actor se muestra como «Vos» o por un id corto: no se
//   leen perfiles ajenos (D-B2-1).

import { gramos_a_kg } from "../domain/peso";
import type {
  HistorialJornada,
  OperacionHistorial,
  ProductoHistorial,
  PuertoHistorialJornada,
} from "../lib/jornadas_historial";
import { formatearInstante, idCorto } from "./jornadas_presentacion";

export type EstadoHistorial =
  | { estado: "inactivo" }
  | { estado: "cargando"; jornadaId: string }
  | { estado: "listo"; jornadaId: string; historial: HistorialJornada }
  | { estado: "error"; jornadaId: string; error: string };

export const HISTORIAL_INACTIVO: EstadoHistorial = { estado: "inactivo" };

export function crearControladorHistorial(
  puerto: PuertoHistorialJornada,
  publicar: (estado: EstadoHistorial) => void
) {
  let vigente = 0;
  let jornadaActual: string | null = null;
  let activo = true;

  function emitir(estado: EstadoHistorial) {
    if (activo) publicar(estado);
  }

  async function leer(jornadaId: string): Promise<void> {
    const lectura = ++vigente;
    emitir({ estado: "cargando", jornadaId });
    const r = await puerto.leerHistorial(jornadaId);
    if (lectura !== vigente || !activo) return;
    emitir(
      r.ok
        ? { estado: "listo", jornadaId, historial: r.datos }
        : { estado: "error", jornadaId, error: r.error }
    );
  }

  return {
    /** Muestra el historial de la jornada (null: ninguna, sin lecturas). */
    mostrar(jornadaId: string | null): Promise<void> {
      jornadaActual = jornadaId;
      if (jornadaId === null) {
        vigente += 1;
        emitir(HISTORIAL_INACTIVO);
        return Promise.resolve();
      }
      return leer(jornadaId);
    },
    /** Vuelve a leer la jornada actual (botón «Actualizar historial»). */
    actualizar(): Promise<void> {
      return jornadaActual === null ? Promise.resolve() : leer(jornadaActual);
    },
    iniciar(): void {
      activo = true;
    },
    detener(): void {
      activo = false;
      vigente += 1;
    },
  };
}

export type ControladorHistorial = ReturnType<typeof crearControladorHistorial>;

// ---------------------------------------------------------------------------
// Presentación
// ---------------------------------------------------------------------------

export const ETIQUETA_TIPO_HISTORIAL: Record<OperacionHistorial["tipo"], string> = {
  carga: "Carga",
  descarga: "Descarga",
};

export const MENSAJE_HISTORIAL_VACIO =
  "Esta jornada todavía no tiene cargas ni descargas registradas.";

/** Cantidad en unidad mínima → «12 un.» o «1,250 kg» (sin float). */
export function formatearCantidadHistorial(
  cantidad: number,
  formaVenta: ProductoHistorial["formaVenta"]
): string {
  return formaVenta === "peso" ? `${gramos_a_kg(cantidad)} kg` : `${cantidad} un.`;
}

export function etiquetaProducto(p: ProductoHistorial): string {
  const base = p.codigo !== null && p.codigo.trim() !== "" ? `${p.nombre} (${p.codigo})` : p.nombre;
  return p.activo ? base : `${base} · dado de baja`;
}

/** «Vos» si el actor es el usuario actual; si no, un id corto (sin leer perfiles). */
export function etiquetaActor(actorId: string, usuarioId: string | null): string {
  return usuarioId !== null && actorId.toLowerCase() === usuarioId.toLowerCase()
    ? "Vos"
    : `Otro usuario (${idCorto(actorId)})`;
}

export interface LineaPresentada {
  clave: string;
  producto: string;
  cantidad: string;
}

export interface OperacionPresentada {
  id: string;
  tipo: string;
  instante: string;
  actor: string;
  motivo: string | null;
  lineas: LineaPresentada[];
}

export function presentarHistorial(
  historial: HistorialJornada,
  usuarioId: string | null
): OperacionPresentada[] {
  return historial.operaciones.map((o) => ({
    id: o.id,
    tipo: ETIQUETA_TIPO_HISTORIAL[o.tipo],
    instante: formatearInstante(o.creadoEn),
    actor: etiquetaActor(o.actorId, usuarioId),
    motivo: o.motivo,
    lineas: o.lineas.map((l) => {
      // armarHistorial garantiza que el producto existe.
      const p = historial.productos[l.productoId.toLowerCase()];
      return {
        clave: l.movimientoId,
        producto: etiquetaProducto(p),
        cantidad: formatearCantidadHistorial(l.cantidad, p.formaVenta),
      };
    }),
  }));
}
