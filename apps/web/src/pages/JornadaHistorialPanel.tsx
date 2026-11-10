import { AlertTriangle, History, Loader2, RefreshCw } from "lucide-react";

import type { Jornada } from "../lib/jornadas";
import {
  MENSAJE_HISTORIAL_VACIO,
  presentarHistorial,
  type EstadoHistorial,
} from "./jornadas_historial";

// Historial de cargas y descargas registradas (B-02b.2 / S3-0) dentro del
// detalle de la jornada. SÓLO LECTURA y presentacional: todo llega por props.
// La pantalla lo monta sólo para dueño y encargado; qué filas llegan lo decide
// RLS. El único botón vuelve a LEER el historial: no hay acciones de carga,
// descarga, cancelación ni reintento de operaciones.

export interface JornadaHistorialPanelProps {
  jornada: Jornada;
  estado: EstadoHistorial;
  // Usuario actual: su actor se muestra como «Vos».
  usuarioId: string | null;
  onActualizar: () => void;
}

const BOTON =
  "flex min-h-12 items-center justify-center gap-2 rounded-lg border border-slate-300 px-4 font-medium text-slate-700 disabled:cursor-not-allowed disabled:opacity-60";

export function JornadaHistorialPanel({
  jornada,
  estado,
  usuarioId,
  onActualizar,
}: JornadaHistorialPanelProps) {
  // El estado sólo se aplica a la jornada que se está mostrando.
  const propio = estado.estado !== "inactivo" && estado.jornadaId === jornada.id ? estado : null;
  const idTitulo = `historial-titulo-${jornada.id}`;
  const cargando = propio === null || propio.estado === "cargando";

  return (
    <section aria-labelledby={idTitulo} className="mt-6 border-t border-slate-200 pt-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h3 id={idTitulo} className="flex items-center gap-2 font-semibold text-slate-800">
          <History size={20} className="text-blue-600" />
          Cargas y descargas registradas
        </h3>
        <button type="button" onClick={onActualizar} disabled={cargando} className={BOTON}>
          <RefreshCw size={16} />
          Actualizar historial
        </button>
      </div>

      {cargando && (
        <p role="status" className="mt-3 flex items-center gap-2 text-sm text-slate-600">
          <Loader2 size={16} className="animate-spin" />
          Cargando historial…
        </p>
      )}

      {propio?.estado === "error" && (
        <div role="alert" className="mt-3 flex items-start gap-2 rounded-lg bg-red-50 p-3 text-sm text-red-800">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" />
          <span>{propio.error}</span>
        </div>
      )}

      {propio?.estado === "listo" && propio.historial.operaciones.length === 0 && (
        <p className="mt-3 text-sm text-slate-600">{MENSAJE_HISTORIAL_VACIO}</p>
      )}

      {propio?.estado === "listo" && propio.historial.operaciones.length > 0 && (
        <ol aria-label="Historial de la jornada" className="mt-3 space-y-3">
          {presentarHistorial(propio.historial, usuarioId).map((o) => (
            <li key={o.id} className="rounded-lg border border-slate-200 p-3">
              <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                <p className="font-semibold text-slate-800">{o.tipo}</p>
                <p className="text-sm text-slate-500">{o.instante}</p>
              </div>
              <p className="text-sm text-slate-600">Registró: {o.actor}</p>
              {o.motivo !== null && (
                <p className="break-words text-sm text-slate-600">Motivo: {o.motivo}</p>
              )}
              <ul className="mt-2 divide-y divide-slate-100 text-sm">
                {o.lineas.map((l) => (
                  <li key={l.clave} className="flex justify-between gap-3 py-1">
                    <span className="min-w-0 break-words text-slate-700">{l.producto}</span>
                    <span className="shrink-0 font-medium tabular-nums text-slate-800">{l.cantidad}</span>
                  </li>
                ))}
              </ul>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}
