import {
  AlertTriangle,
  ClipboardList,
  Info,
  Plus,
  RefreshCw,
  Truck,
  X,
} from "lucide-react";
import type { ReactNode } from "react";

import type { EstadoJornada, Jornada } from "../lib/jornadas";
import {
  ETIQUETA_ESTADO_JORNADA,
  MENSAJE_NO_DISPONIBLE,
  formatearFechaOperativa,
  formatearInstante,
  idCorto,
} from "./jornadas_presentacion";
import type { EstadoPantallaJornadas } from "./jornadas_lectura";

// Vista presentacional de la pantalla de jornadas reales (B-02b.1). Sin estado
// ni efectos: todo llega por props, así se prueba con renderToStaticMarkup.
// Esta vista no muta nada. Las acciones del detalle (en B-02b.2 / S1, sólo la
// confirmación de salida) llegan ya armadas por `accionesDetalle` y viven en
// sus propios módulos; abrir, cargar y descargar siguen sin existir.

const CLASE_ESTADO: Record<EstadoJornada, string> = {
  abierta: "bg-amber-100 text-amber-800",
  cargada: "bg-blue-100 text-blue-800",
  en_reparto: "bg-green-100 text-green-700",
  ventas_finalizadas: "bg-violet-100 text-violet-800",
  regreso_contado: "bg-cyan-100 text-cyan-800",
  cerrada: "bg-slate-100 text-slate-600",
};

export interface JornadasVistaProps {
  estado: EstadoPantallaJornadas;
  // true: dueño o encargado. false: vendedor/piloto (ve sólo su jornada, sin
  // controles de gestión ni identificadores administrativos de apertura). Es
  // sólo presentación: qué filas llegan lo decide RLS.
  puedeAdministrar: boolean;
  nombreCamion: (camionId: string) => string;
  onCambiarFecha: (fecha: string | null) => void;
  onRecargar: () => void;
  onCargarMas: () => void;
  onCargarTodas: () => void;
  onSeleccionar: (id: string | null) => void;
  // Acciones de gestión del detalle (sólo dueño y encargado; la pantalla
  // decide si las pasa). Sin ellas, el detalle no ofrece ninguna acción.
  accionesDetalle?: (jornada: Jornada) => ReactNode;
  // Anuncios del resultado de una operación (p. ej. la salida confirmada).
  // Se muestran fuera del listado y del detalle, así sobreviven a la
  // relectura que pone la lista en «cargando» (corrección S1-C5).
  avisos?: ReactNode;
}

function InsigniaEstado({ estado }: { estado: EstadoJornada }) {
  return (
    <span
      className={`inline-block rounded-full px-3 py-1 text-xs font-semibold ${CLASE_ESTADO[estado]}`}
    >
      {ETIQUETA_ESTADO_JORNADA[estado]}
    </span>
  );
}

function Detalle({
  jornada,
  nombreCamion,
  puedeAdministrar,
  onCerrar,
  acciones,
}: {
  jornada: Jornada;
  nombreCamion: (id: string) => string;
  puedeAdministrar: boolean;
  onCerrar: () => void;
  acciones?: (jornada: Jornada) => ReactNode;
}) {
  const campos: Array<[string, string]> = [
    ["Fecha operativa", formatearFechaOperativa(jornada.fecha)],
    ["Camión", nombreCamion(jornada.camionId)],
    ["Creada", formatearInstante(jornada.creadoEn)],
  ];
  if (puedeAdministrar) {
    campos.push(
      ["Vendedor asignado (id)", idCorto(jornada.vendedorId)],
      ["Abierta por (id)", idCorto(jornada.abiertaPor)],
      ["Operación de apertura (id)", idCorto(jornada.operacionAperturaId)]
    );
  }
  return (
    <section
      aria-label="Detalle de la jornada"
      className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm md:p-6"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-3">
          <Truck size={28} className="text-blue-600" />
          <div>
            <h2 className="text-lg font-bold text-slate-800">
              Jornada del {formatearFechaOperativa(jornada.fecha)}
            </h2>
            <InsigniaEstado estado={jornada.estado} />
          </div>
        </div>
        <button
          type="button"
          onClick={onCerrar}
          aria-label="Cerrar detalle"
          className="flex min-h-12 min-w-12 items-center justify-center rounded-lg border border-slate-300"
        >
          <X size={18} />
        </button>
      </div>
      <dl className="mt-4 grid gap-3 sm:grid-cols-2">
        {campos.map(([nombre, valor]) => (
          <div key={nombre}>
            <dt className="text-xs text-slate-500">{nombre}</dt>
            <dd className="text-sm font-medium text-slate-800">{valor}</dd>
          </div>
        ))}
      </dl>
      <p className="mt-4 text-xs text-slate-500">
        La carga, las ventas y los retornos de la jornada todavía no se
        muestran en esta pantalla.
      </p>
      {puedeAdministrar && acciones?.(jornada)}
    </section>
  );
}

function textoVacio(puedeAdministrar: boolean, fecha: string | null): string {
  if (!puedeAdministrar) {
    return fecha === null
      ? "No tenés una jornada asignada."
      : `No tenés una jornada asignada el ${formatearFechaOperativa(fecha)}.`;
  }
  return fecha === null
    ? "Todavía no hay jornadas registradas."
    : `No hay jornadas el ${formatearFechaOperativa(fecha)}.`;
}

export function JornadasVista({
  estado,
  puedeAdministrar,
  nombreCamion,
  onCambiarFecha,
  onRecargar,
  onCargarMas,
  onCargarTodas,
  onSeleccionar,
  accionesDetalle,
  avisos,
}: JornadasVistaProps) {
  const { lectura, fecha, seleccionadaId } = estado;
  const seleccionada =
    lectura.estado === "listo"
      ? lectura.jornadas.find((j) => j.id === seleccionadaId) ?? null
      : null;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-slate-800">
            {puedeAdministrar ? "Jornadas" : "Mi jornada"}
          </h1>
          <p className="mt-1 text-slate-500">
            {puedeAdministrar
              ? "Consulta de jornadas por camión y fecha operativa"
              : "Tu jornada de reparto asignada"}
          </p>
        </div>
        <div className="flex flex-wrap gap-3">
          <button
            type="button"
            onClick={onRecargar}
            disabled={lectura.estado === "cargando"}
            className="flex min-h-12 items-center gap-2 rounded-lg border border-slate-300 px-5 font-medium disabled:opacity-50"
          >
            <RefreshCw size={18} />
            Actualizar
          </button>
          {puedeAdministrar && (
            <button
              type="button"
              disabled
              title={MENSAJE_NO_DISPONIBLE}
              className="flex min-h-12 cursor-not-allowed items-center gap-2 rounded-lg bg-slate-200 px-5 font-medium text-slate-500"
            >
              <Plus size={20} />
              Nueva jornada (no disponible todavía)
            </button>
          )}
        </div>
      </div>

      {puedeAdministrar && (
        <div
          role="note"
          className="flex items-start gap-2 rounded-xl bg-amber-50 p-4 text-sm text-amber-900"
        >
          <Info size={18} className="mt-0.5 shrink-0" />
          <span>{MENSAJE_NO_DISPONIBLE}</span>
        </div>
      )}

      <div className="flex flex-wrap items-end gap-3 rounded-xl border border-slate-200 bg-white p-4">
        <label className="space-y-1 text-sm font-medium">
          <span>Fecha operativa</span>
          <input
            type="date"
            value={fecha ?? ""}
            onChange={(e) =>
              onCambiarFecha(e.target.value === "" ? null : e.target.value)
            }
            className="block min-h-12 rounded-lg border border-slate-300 p-3"
          />
        </label>
        <button
          type="button"
          onClick={() => onCambiarFecha(null)}
          disabled={fecha === null}
          className="min-h-12 rounded-lg border border-slate-300 px-5 disabled:opacity-50"
        >
          Ver todas las fechas
        </button>
        <p className="text-xs text-slate-500">
          Sólo ves las jornadas que tu usuario puede consultar.
        </p>
      </div>

      {avisos}

      {lectura.estado === "cargando" && (
        <p role="status" className="rounded-xl bg-white p-10 text-center text-slate-500">
          Cargando jornadas…
        </p>
      )}

      {lectura.estado === "error" && (
        <div
          role="alert"
          className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-red-50 p-4 text-red-800"
        >
          <span className="flex items-center gap-2">
            <AlertTriangle size={20} />
            {lectura.error}
          </span>
          <button
            type="button"
            onClick={onRecargar}
            className="min-h-12 rounded-lg border border-red-300 px-5 font-medium"
          >
            Reintentar
          </button>
        </div>
      )}

      {lectura.estado === "listo" && (
        <>
          <p className="text-sm text-slate-600" aria-live="polite">
            {lectura.jornadas.length === 0
              ? textoVacio(puedeAdministrar, fecha)
              : lectura.siguiente === null
              ? `${lectura.jornadas.length} ${
                  lectura.jornadas.length === 1 ? "jornada" : "jornadas"
                } (lista completa).`
              : `${lectura.jornadas.length} jornadas cargadas. Hay más: la lista todavía no está completa.`}
          </p>

          {lectura.jornadas.length === 0 && (
            <div className="rounded-xl bg-white p-10 text-center text-slate-500">
              <ClipboardList className="mx-auto mb-3" size={36} />
              {textoVacio(puedeAdministrar, fecha)}
              {fecha !== null && " Probá con otra fecha o elegí ver todas."}
            </div>
          )}

          {lectura.jornadas.length > 0 && (
            <>
              {/* PC: tabla */}
              <div className="hidden overflow-x-auto rounded-xl border border-slate-200 bg-white md:block">
                <table className="w-full text-left text-sm">
                  <thead className="border-b text-slate-500">
                    <tr>
                      <th className="p-3">Fecha</th>
                      <th className="p-3">Camión</th>
                      <th className="p-3">Estado</th>
                      <th className="p-3">Creada</th>
                      <th className="p-3" />
                    </tr>
                  </thead>
                  <tbody>
                    {lectura.jornadas.map((j) => (
                      <tr
                        key={j.id}
                        className={`border-b border-slate-100 ${
                          j.id === seleccionadaId ? "bg-blue-50" : ""
                        }`}
                      >
                        <td className="p-3">{formatearFechaOperativa(j.fecha)}</td>
                        <td className="p-3">{nombreCamion(j.camionId)}</td>
                        <td className="p-3">
                          <InsigniaEstado estado={j.estado} />
                        </td>
                        <td className="p-3">{formatearInstante(j.creadoEn)}</td>
                        <td className="p-3 text-right">
                          <button
                            type="button"
                            onClick={() => onSeleccionar(j.id)}
                            aria-pressed={j.id === seleccionadaId}
                            className="min-h-12 rounded-lg border border-slate-300 px-4"
                          >
                            Ver detalle
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Celulares: tarjetas */}
              <ul className="space-y-3 md:hidden">
                {lectura.jornadas.map((j) => (
                  <li
                    key={j.id}
                    className={`rounded-xl border p-4 ${
                      j.id === seleccionadaId
                        ? "border-blue-300 bg-blue-50"
                        : "border-slate-200 bg-white"
                    }`}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="font-semibold text-slate-800">
                          {nombreCamion(j.camionId)}
                        </p>
                        <p className="text-sm text-slate-500">
                          {formatearFechaOperativa(j.fecha)}
                        </p>
                      </div>
                      <InsigniaEstado estado={j.estado} />
                    </div>
                    <button
                      type="button"
                      onClick={() => onSeleccionar(j.id)}
                      aria-pressed={j.id === seleccionadaId}
                      className="mt-3 min-h-12 w-full rounded-lg border border-slate-300"
                    >
                      Ver detalle
                    </button>
                  </li>
                ))}
              </ul>
            </>
          )}

          {lectura.errorAmpliacion !== null && (
            <p role="alert" className="rounded-xl bg-red-50 p-4 text-red-800">
              {lectura.errorAmpliacion}
            </p>
          )}

          {lectura.siguiente !== null && (
            <div className="flex flex-wrap gap-3">
              <button
                type="button"
                onClick={onCargarMas}
                disabled={lectura.ampliando !== null}
                className="min-h-12 rounded-lg bg-blue-600 px-5 font-semibold text-white disabled:opacity-50"
              >
                {lectura.ampliando === "mas" ? "Cargando…" : "Cargar más"}
              </button>
              <button
                type="button"
                onClick={onCargarTodas}
                disabled={lectura.ampliando !== null}
                className="min-h-12 rounded-lg border border-slate-300 px-5 disabled:opacity-50"
              >
                {lectura.ampliando === "todas" ? "Cargando todas…" : "Cargar todas"}
              </button>
            </div>
          )}

          {seleccionada !== null && (
            <Detalle
              jornada={seleccionada}
              nombreCamion={nombreCamion}
              puedeAdministrar={puedeAdministrar}
              onCerrar={() => onSeleccionar(null)}
              acciones={accionesDetalle}
            />
          )}
        </>
      )}
    </div>
  );
}
