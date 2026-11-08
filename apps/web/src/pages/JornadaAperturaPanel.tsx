import { useState, type ReactNode } from "react";
import { AlertTriangle, CalendarPlus, CheckCircle2, Loader2, RefreshCw } from "lucide-react";

import { nombreRol } from "../auth/roles";
import type { CamionCatalogo } from "../lib/camiones";
import type {
  EntradaApertura,
  EstadoVendedores,
  FaseApertura,
  OpcionesPermitidas,
} from "./jornadas_apertura";
import { formatearFechaOperativa, idCorto } from "./jornadas_presentacion";

// Panel «Nueva jornada» (D-B2-1). Presentacional: todo llega por props. La
// pantalla lo monta sólo para dueño y encargado; quién puede abrir y qué
// valores se aceptan lo decide el servidor.
//
// - Camión: sólo los activos del catálogo real.
// - Fecha: día operativo de Tucumán o posterior.
// - Vendedor: sólo la lista real de `listar_vendedores_jornada`. Sin campo de
//   texto para un uuid y sin opción de autoasignación: si la lista no está
//   disponible o está vacía, no se puede enviar.
// - El éxito se anuncia sólo con la jornada que devolvió el servidor; ante una
//   respuesta perdida, la información de la lista NO confirma nada.
// Vive fuera del listado: la relectura posterior al éxito no lo desmonta.

export interface JornadaAperturaPanelProps {
  fase: FaseApertura;
  // Camiones activos del catálogo, o null si el catálogo no está disponible.
  camionesActivos: CamionCatalogo[] | null;
  vendedores: EstadoVendedores;
  // Día operativo actual 'AAAA-MM-DD' (Tucumán): valor inicial y mínimo.
  hoy: string;
  nombreCamion: (camionId: string) => string;
  onSolicitar: () => void;
  onCancelar: () => void;
  onConfirmar: (entrada: EntradaApertura, permitidas: OpcionesPermitidas) => void;
  onReintentar: () => void;
  onRecargarVendedores: () => void;
  onVerFecha: (fecha: string) => void;
}

const BOTON =
  "flex min-h-12 items-center justify-center gap-2 rounded-lg px-5 font-semibold disabled:cursor-not-allowed disabled:opacity-60";
const CAMPO = "min-h-12 w-full rounded-lg border border-slate-300 bg-white px-3 text-base";
const BASE = "apertura";

function nombreVendedor(vendedores: EstadoVendedores, id: string): string {
  if (vendedores.estado === "listo") {
    const v = vendedores.vendedores.find((x) => x.usuarioId === id.toLowerCase());
    if (v) return `${v.nombre} (${nombreRol(v.rol)})`;
  }
  return `Vendedor ${idCorto(id)}`;
}

function Resumen({
  datos,
  nombreCamion,
  vendedores,
}: {
  datos: EntradaApertura;
  nombreCamion: (camionId: string) => string;
  vendedores: EstadoVendedores;
}) {
  return (
    <dl className="grid grid-cols-[auto,1fr] gap-x-3 gap-y-1 text-sm">
      <dt className="font-medium">Camión</dt>
      <dd>{nombreCamion(datos.camionId)}</dd>
      <dt className="font-medium">Fecha</dt>
      <dd>{formatearFechaOperativa(datos.fecha)}</dd>
      <dt className="font-medium">Vendedor</dt>
      <dd>{nombreVendedor(vendedores, datos.vendedorId)}</dd>
    </dl>
  );
}

export function JornadaAperturaPanel(props: JornadaAperturaPanelProps) {
  const { fase, hoy, nombreCamion, vendedores, onSolicitar, onReintentar, onVerFecha } = props;
  // Los valores sobreviven a un rechazo (para corregir y volver a enviar);
  // se reinician al empezar una apertura nueva después de un éxito.
  const [camionId, setCamionId] = useState("");
  const [fecha, setFecha] = useState(hoy);
  const [vendedorId, setVendedorId] = useState("");

  function solicitar() {
    if (fase.fase === "exito") {
      setCamionId("");
      setFecha(hoy);
      setVendedorId("");
    }
    onSolicitar();
  }

  let contenido: ReactNode;

  if (fase.fase === "editando" || fase.fase === "error") {
    contenido = (
      <Formulario
        {...props}
        error={fase.fase === "editando" ? fase.error : fase.mensaje}
        camionId={camionId}
        fecha={fecha}
        vendedorId={vendedorId}
        setCamionId={setCamionId}
        setFecha={setFecha}
        setVendedorId={setVendedorId}
      />
    );
  } else if (fase.fase === "enviando" || fase.fase === "verificando") {
    contenido = (
      <div className="space-y-3 rounded-xl border border-slate-200 bg-white p-4">
        <button type="button" disabled aria-disabled="true" className={`${BOTON} bg-slate-200 text-slate-600`}>
          <Loader2 size={18} className="animate-spin" />
          {fase.fase === "enviando" ? "Abriendo jornada…" : "Consultando la lista…"}
        </button>
        <p className="text-sm text-slate-600">
          {fase.fase === "enviando"
            ? "Enviando la apertura. No cierres ni recargues la pantalla."
            : "No se recibió la respuesta. Leyendo la lista de jornadas sólo para informarte…"}
        </p>
        <Resumen datos={fase.datos} nombreCamion={nombreCamion} vendedores={vendedores} />
      </div>
    );
  } else if (fase.fase === "desconocido") {
    contenido = (
      <div role="alert" className="space-y-3 rounded-xl bg-amber-50 p-4 text-amber-900">
        <p className="flex items-start gap-2">
          <AlertTriangle size={20} className="mt-0.5 shrink-0" />
          <span>{fase.mensaje}</span>
        </p>
        <Resumen datos={fase.datos} nombreCamion={nombreCamion} vendedores={vendedores} />
        {fase.informacion !== null && (
          <p className="text-sm">
            <span className="font-medium">Información (no confirma el resultado): </span>
            {fase.informacion}
          </p>
        )}
        <button type="button" onClick={onReintentar} className={`${BOTON} bg-amber-600 text-white`}>
          <RefreshCw size={18} />
          Reintentar apertura
        </button>
      </div>
    );
  } else if (fase.fase === "exito") {
    contenido = (
      <div className="space-y-3 rounded-xl bg-green-50 p-4 text-green-800">
        <p className="flex items-start gap-2 font-semibold">
          <CheckCircle2 size={20} className="mt-0.5 shrink-0" />
          <span>{fase.mensaje}</span>
        </p>
        <Resumen datos={fase.datos} nombreCamion={nombreCamion} vendedores={vendedores} />
        <div className="flex flex-col gap-3 sm:flex-row">
          <button
            type="button"
            onClick={() => onVerFecha(fase.datos.fecha)}
            className={`${BOTON} border border-green-600 text-green-800`}
          >
            Ver jornadas del {formatearFechaOperativa(fase.datos.fecha)}
          </button>
          {/* Otra apertura es otra intención, con otra clave: se ofrece
              recién cuando la lista ya se volvió a leer. */}
          {fase.releida === true && (
            <button type="button" onClick={solicitar} className={`${BOTON} bg-blue-600 text-white`}>
              <CalendarPlus size={18} />
              Nueva jornada
            </button>
          )}
        </div>
      </div>
    );
  } else {
    contenido = (
      <button type="button" onClick={solicitar} className={`${BOTON} bg-blue-600 text-white`}>
        <CalendarPlus size={18} />
        Nueva jornada
      </button>
    );
  }

  return (
    <section aria-label="Nueva jornada" className="space-y-2">
      {/* Siempre montada: un lector de pantalla anuncia el cambio de contenido. */}
      <div role="status" aria-live="polite" className="sr-only">
        {fase.fase === "exito" ? fase.mensaje : ""}
      </div>
      {contenido}
    </section>
  );
}

function Formulario({
  camionesActivos,
  vendedores,
  hoy,
  onCancelar,
  onConfirmar,
  onRecargarVendedores,
  error,
  camionId,
  fecha,
  vendedorId,
  setCamionId,
  setFecha,
  setVendedorId,
}: JornadaAperturaPanelProps & {
  error?: string;
  camionId: string;
  fecha: string;
  vendedorId: string;
  setCamionId: (v: string) => void;
  setFecha: (v: string) => void;
  setVendedorId: (v: string) => void;
}) {
  const camiones = camionesActivos ?? [];
  const listaVendedores = vendedores.estado === "listo" ? vendedores.vendedores : [];
  const puedeEnviar = camiones.length > 0 && listaVendedores.length > 0;

  let ayudaCamion: string | null = null;
  if (camionesActivos === null) ayudaCamion = "La lista de camiones activos no está disponible. Actualizá la pantalla.";
  else if (camiones.length === 0) ayudaCamion = "No hay camiones activos para asignar.";

  let ayudaVendedor: string | null = null;
  if (vendedores.estado === "inactivo" || vendedores.estado === "cargando") {
    ayudaVendedor = "Cargando vendedores…";
  } else if (vendedores.estado === "error") {
    ayudaVendedor = vendedores.mensaje;
  } else if (listaVendedores.length === 0) {
    ayudaVendedor = "No hay perfiles activos de la empresa para asignar.";
  }

  return (
    <form
      noValidate
      aria-labelledby={`${BASE}-titulo`}
      onSubmit={(e) => {
        e.preventDefault();
        if (!puedeEnviar) return;
        onConfirmar(
          { camionId, fecha, vendedorId },
          {
            camiones: camiones.map((c) => c.id),
            vendedores: listaVendedores.map((v) => v.usuarioId),
          }
        );
      }}
      className="space-y-4 rounded-xl border border-blue-200 bg-blue-50 p-4"
    >
      <p id={`${BASE}-titulo`} className="font-semibold text-slate-800">
        Abrir jornada
      </p>
      <p className="text-sm text-slate-600">
        La jornada nace abierta, sin mercadería. Un camión y un vendedor tienen
        como máximo una jornada por fecha.
      </p>

      <div className="space-y-1">
        <label htmlFor={`${BASE}-camion`} className="block text-sm font-medium text-slate-700">
          Camión
        </label>
        <select
          id={`${BASE}-camion`}
          value={camionId}
          onChange={(e) => setCamionId(e.target.value)}
          disabled={camiones.length === 0}
          aria-describedby={ayudaCamion ? `${BASE}-camion-ayuda` : undefined}
          className={CAMPO}
        >
          <option value="">Elegí un camión</option>
          {camiones.map((c) => (
            <option key={c.id} value={c.id}>
              {c.nombre} · {c.patente}
            </option>
          ))}
        </select>
        {ayudaCamion && (
          <p id={`${BASE}-camion-ayuda`} className="text-xs text-slate-600">
            {ayudaCamion}
          </p>
        )}
      </div>

      <div className="space-y-1">
        <label htmlFor={`${BASE}-fecha`} className="block text-sm font-medium text-slate-700">
          Fecha operativa
        </label>
        <input
          id={`${BASE}-fecha`}
          type="date"
          min={hoy}
          value={fecha}
          onChange={(e) => setFecha(e.target.value)}
          className={CAMPO}
        />
      </div>

      <div className="space-y-1">
        <label htmlFor={`${BASE}-vendedor`} className="block text-sm font-medium text-slate-700">
          Vendedor
        </label>
        <select
          id={`${BASE}-vendedor`}
          value={vendedorId}
          onChange={(e) => setVendedorId(e.target.value)}
          disabled={listaVendedores.length === 0}
          aria-describedby={ayudaVendedor ? `${BASE}-vendedor-ayuda` : undefined}
          className={CAMPO}
        >
          <option value="">Elegí un vendedor</option>
          {listaVendedores.map((v) => (
            <option key={v.usuarioId} value={v.usuarioId}>
              {v.nombre} — {nombreRol(v.rol)}
            </option>
          ))}
        </select>
        {ayudaVendedor && (
          <p
            id={`${BASE}-vendedor-ayuda`}
            role={vendedores.estado === "error" ? "alert" : undefined}
            className={`text-xs ${vendedores.estado === "error" ? "text-red-700" : "text-slate-600"}`}
          >
            {ayudaVendedor}
          </p>
        )}
        {vendedores.estado === "error" && (
          <button
            type="button"
            onClick={onRecargarVendedores}
            className={`${BOTON} border border-slate-300 text-slate-700`}
          >
            <RefreshCw size={18} />
            Reintentar lectura de vendedores
          </button>
        )}
      </div>

      {error && (
        <p id={`${BASE}-error`} role="alert" className="flex items-start gap-2 text-sm text-red-700">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" />
          <span>{error}</span>
        </p>
      )}

      <div className="flex flex-col gap-3 sm:flex-row">
        <button type="submit" disabled={!puedeEnviar} className={`${BOTON} bg-blue-600 text-white`}>
          <CalendarPlus size={18} />
          Abrir jornada
        </button>
        <button type="button" onClick={onCancelar} className={`${BOTON} border border-slate-300 text-slate-700`}>
          Cancelar
        </button>
      </div>
    </form>
  );
}
