import { CheckCircle2, CircleDashed, Clock, Lock, Loader2 } from "lucide-react";

import type { Jornada } from "../lib/jornadas";
import {
  ACLARACION_REGISTRADO,
  ETIQUETA_ESTADO_PASO,
  MENSAJE_NO_CERRABLE,
  MENSAJE_SIN_CARGA_NETA,
  armarContinuidad,
  mensajeCamionBloqueado,
  type EstadoPaso,
} from "./jornadas_continuidad";
import type { EstadoHistorial } from "./jornadas_historial";

// Estado de jornada y bloqueos de continuidad (B-02b.2 / S3-1) dentro del
// detalle. SÓLO LECTURA y presentacional: no lee nada por su cuenta (usa el
// historial de S3-0 que ya leyó la pantalla) y no tiene botones.

export interface JornadaContinuidadPanelProps {
  jornada: Jornada;
  historial: EstadoHistorial;
  nombreCamion: string;
}

const ICONO: Record<EstadoPaso, typeof CheckCircle2> = {
  hecho: CheckCircle2,
  pendiente: Clock,
  no_disponible: CircleDashed,
};

const COLOR: Record<EstadoPaso, string> = {
  hecho: "text-green-700",
  pendiente: "text-amber-700",
  no_disponible: "text-slate-500",
};

export function JornadaContinuidadPanel({ jornada, historial, nombreCamion }: JornadaContinuidadPanelProps) {
  const c = armarContinuidad(jornada, historial);
  const idTitulo = `continuidad-titulo-${jornada.id}`;

  return (
    <section aria-labelledby={idTitulo} className="mt-6 border-t border-slate-200 pt-4">
      <h3 id={idTitulo} className="flex items-center gap-2 font-semibold text-slate-800">
        <Lock size={20} className="text-blue-600" />
        Estado de cierre
      </h3>

      {!c.cerrada && (
        <div className="mt-3 space-y-1 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">
          <p>{MENSAJE_NO_CERRABLE}</p>
          {c.bloqueaCamion && <p className="font-medium">{mensajeCamionBloqueado(nombreCamion)}</p>}
        </div>
      )}

      <ol aria-label="Pasos de la jornada" className="mt-3 space-y-2">
        {c.pasos.map((p) => {
          const Icono = ICONO[p.estado];
          return (
            <li key={p.clave} className="flex items-start gap-2 text-sm">
              <Icono size={18} className={`mt-0.5 shrink-0 ${COLOR[p.estado]}`} aria-hidden="true" />
              <div className="min-w-0">
                <p className="font-medium text-slate-800">
                  {p.titulo}: <span className={COLOR[p.estado]}>{ETIQUETA_ESTADO_PASO[p.estado]}</span>
                </p>
                <p className="break-words text-slate-600">{p.detalle}</p>
              </div>
            </li>
          );
        })}
      </ol>

      <div className="mt-4">
        <h4 className="text-sm font-semibold text-slate-800">Carga neta registrada de esta jornada</h4>
        <p className="mt-1 text-xs text-slate-500">{ACLARACION_REGISTRADO}</p>
        {c.cargaNeta.estado === "cargando" && (
          <p className="mt-2 flex items-center gap-2 text-sm text-slate-600">
            <Loader2 size={16} className="animate-spin" />
            Calculando…
          </p>
        )}
        {c.cargaNeta.estado === "error" && (
          <p role="alert" className="mt-2 rounded-lg bg-red-50 p-3 text-sm text-red-800">
            {c.cargaNeta.mensaje}
          </p>
        )}
        {c.cargaNeta.estado === "listo" && c.cargaNeta.lineas.length === 0 && (
          <p className="mt-2 text-sm text-slate-600">{MENSAJE_SIN_CARGA_NETA}</p>
        )}
        {c.cargaNeta.estado === "listo" && c.cargaNeta.lineas.length > 0 && (
          <ul aria-label="Carga neta de la jornada" className="mt-2 divide-y divide-slate-100 text-sm">
            {c.cargaNeta.lineas.map((l) => (
              <li key={l.productoId} className="flex justify-between gap-3 py-1">
                <span className="min-w-0 break-words text-slate-700">{l.producto}</span>
                <span className="shrink-0 font-medium tabular-nums text-slate-800">{l.cantidad}</span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
