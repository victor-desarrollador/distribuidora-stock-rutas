import { useState } from "react";
import { AlertTriangle, Loader2, PencilLine } from "lucide-react";

import type { CamionCatalogo } from "../lib/camiones";
import type { Jornada } from "../lib/jornadas";
import type { EntradaCorreccion, FaseCorreccion } from "./jornadas_correccion";
import { ETIQUETA_ESTADO_JORNADA } from "./jornadas_presentacion";

// Panel de «Corregir jornada» (B-02b.2 / S2) dentro del detalle de la jornada.
// Presentacional: todo llega por props. La pantalla lo monta sólo para dueño y
// encargado; quién puede corregir y qué valores se aceptan lo decide el
// servidor. El resultado (éxito o rechazo) lo anuncia el aviso de la pantalla,
// fuera del detalle, porque la relectura desmonta este panel.

export interface JornadaCorreccionPanelProps {
  jornada: Jornada;
  fase: FaseCorreccion;
  // Otra operación (la salida) retiene esta jornada (M-02). Sólo presentación:
  // la exclusión efectiva la aplica el motor.
  bloqueadaPorOtra?: boolean;
  // Camiones activos del catálogo, o null si el catálogo no se pudo leer.
  camionesActivos: CamionCatalogo[] | null;
  nombreCamion: (camionId: string) => string;
  // Día operativo actual 'AAAA-MM-DD' (Tucumán): mínimo del selector de fecha.
  hoy: string;
  onSolicitar: (jornada: Jornada) => void;
  onCancelar: () => void;
  onConfirmar: (entrada: EntradaCorreccion) => void;
  onReintentar: () => void;
  onVerificar: () => void;
}

const BOTON =
  "flex min-h-12 items-center justify-center gap-2 rounded-lg px-5 font-semibold disabled:cursor-not-allowed disabled:opacity-60";
const CAMPO = "min-h-12 w-full rounded-lg border border-slate-300 bg-white px-3 text-base";

export function JornadaCorreccionPanel(props: JornadaCorreccionPanelProps) {
  const { jornada, fase, bloqueadaPorOtra = false, onSolicitar, onReintentar, onVerificar } = props;
  const propia = fase.fase !== "inactiva" && fase.jornadaId === jornada.id ? fase : null;
  const idAyuda = `correccion-ayuda-${jornada.id}`;

  if (propia?.fase === "confirmando") {
    return <FormularioCorreccion {...props} error={propia.error} />;
  }

  if (propia?.fase === "enviando" || propia?.fase === "verificando") {
    return (
      <div className="mt-4 space-y-2">
        <button type="button" disabled aria-disabled="true" className={`${BOTON} bg-slate-200 text-slate-600`}>
          <Loader2 size={18} className="animate-spin" />
          {propia.fase === "enviando" ? "Registrando corrección…" : "Consultando estado…"}
        </button>
        <p role="status" className="text-sm text-slate-600">
          {propia.fase === "enviando"
            ? "Enviando la corrección. No cierres ni recargues la pantalla."
            : "No se recibió la respuesta. Consultando el estado real de la jornada…"}
        </p>
      </div>
    );
  }

  if (propia?.fase === "desconocido") {
    return (
      <div role="alert" className="mt-4 space-y-3 rounded-xl bg-amber-50 p-4 text-amber-900">
        <p className="flex items-start gap-2">
          <AlertTriangle size={20} className="mt-0.5 shrink-0" />
          <span>{propia.mensaje}</span>
        </p>
        <div className="flex flex-col gap-3 sm:flex-row">
          {propia.reintentable && (
            <button type="button" onClick={onReintentar} className={`${BOTON} bg-amber-600 text-white`}>
              Reintentar corrección
            </button>
          )}
          <button type="button" onClick={onVerificar} className={`${BOTON} border border-amber-400 text-amber-900`}>
            Verificar estado
          </button>
        </div>
      </div>
    );
  }

  // Tras un éxito no se ofrece ninguna acción mientras llega la relectura
  // (los datos locales todavía son los anteriores). Releída la lista, se
  // ofrece de nuevo: otra corrección es otra intención, con otra clave (M-03).
  if (propia?.fase === "exito" && propia.releida !== true) return null;

  if (bloqueadaPorOtra) {
    return (
      <div className="mt-4 space-y-1">
        <button type="button" disabled aria-describedby={idAyuda} className={`${BOTON} bg-slate-200 text-slate-500`}>
          Corregir jornada
        </button>
        <p id={idAyuda} className="text-xs text-slate-500">
          Hay una confirmación de salida de esta jornada en curso o sin resolver.
          Terminala o verificá su estado antes de corregir la jornada.
        </p>
      </div>
    );
  }

  // Otra jornada tiene una corrección con resultado desconocido: hasta
  // resolverla no se inicia otra (conserva la clave de esa intención).
  if (fase.fase === "desconocido" && fase.jornadaId !== jornada.id) {
    return (
      <div className="mt-4 space-y-1">
        <button type="button" disabled aria-describedby={idAyuda} className={`${BOTON} bg-slate-200 text-slate-500`}>
          Corregir jornada
        </button>
        <p id={idAyuda} className="text-xs text-slate-500">
          Hay una corrección de otra jornada sin resolver. Abrí esa jornada y
          verificá su estado antes de corregir otra.
        </p>
      </div>
    );
  }

  // Sólo una jornada `abierta` (sin movimientos) admite la corrección (ADR-007 §2.4).
  if (jornada.estado !== "abierta") {
    return (
      <div className="mt-4 space-y-1">
        <button type="button" disabled aria-describedby={idAyuda} className={`${BOTON} bg-slate-200 text-slate-500`}>
          Corregir jornada
        </button>
        <p id={idAyuda} className="text-xs text-slate-500">
          Sólo se puede corregir una jornada abierta (estado actual:{" "}
          {ETIQUETA_ESTADO_JORNADA[jornada.estado]}).
        </p>
      </div>
    );
  }

  return (
    <div className="mt-4">
      <button
        type="button"
        onClick={() => onSolicitar(jornada)}
        className={`${BOTON} border border-blue-600 text-blue-700`}
      >
        <PencilLine size={18} />
        Corregir jornada
      </button>
    </div>
  );
}

function FormularioCorreccion({
  jornada,
  camionesActivos,
  nombreCamion,
  hoy,
  onCancelar,
  onConfirmar,
  error,
}: JornadaCorreccionPanelProps & { error?: string }) {
  // Se monta al abrir la corrección: arranca con los valores actuales.
  const [fecha, setFecha] = useState(jornada.fecha);
  const [camionId, setCamionId] = useState(jornada.camionId);
  const [motivo, setMotivo] = useState("");
  const base = `correccion-${jornada.id}`;

  // El camión actual siempre figura (aunque esté dado de baja: si no cambia,
  // el servidor lo revalida); los demás, sólo los activos.
  const otros = (camionesActivos ?? []).filter((c) => c.id !== jornada.camionId);

  return (
    <form
      noValidate
      aria-labelledby={`${base}-titulo`}
      onSubmit={(e) => {
        e.preventDefault();
        onConfirmar({ fecha, camionId, motivo });
      }}
      className="mt-4 space-y-4 rounded-xl border border-blue-200 bg-blue-50 p-4"
    >
      <p id={`${base}-titulo`} className="font-semibold text-slate-800">
        Corregir fecha o camión
      </p>
      <p className="text-sm text-slate-600">
        Sólo mientras la jornada está abierta y sin movimientos. El vendedor y
        el estado no cambian; queda registrado el motivo.
      </p>

      <div className="space-y-1">
        <label htmlFor={`${base}-fecha`} className="block text-sm font-medium text-slate-700">
          Fecha
        </label>
        <input
          id={`${base}-fecha`}
          type="date"
          min={hoy}
          value={fecha}
          onChange={(e) => setFecha(e.target.value)}
          className={CAMPO}
        />
      </div>

      <div className="space-y-1">
        <label htmlFor={`${base}-camion`} className="block text-sm font-medium text-slate-700">
          Camión
        </label>
        <select
          id={`${base}-camion`}
          value={camionId}
          onChange={(e) => setCamionId(e.target.value)}
          aria-describedby={camionesActivos === null ? `${base}-catalogo` : undefined}
          className={CAMPO}
        >
          <option value={jornada.camionId}>{nombreCamion(jornada.camionId)} (actual)</option>
          {otros.map((c) => (
            <option key={c.id} value={c.id}>
              {c.nombre} · {c.patente}
            </option>
          ))}
        </select>
        {camionesActivos === null && (
          <p id={`${base}-catalogo`} className="text-xs text-slate-500">
            No se pudo leer el catálogo de camiones: por ahora sólo se puede corregir la fecha.
          </p>
        )}
      </div>

      <div className="space-y-1">
        <label htmlFor={`${base}-motivo`} className="block text-sm font-medium text-slate-700">
          Motivo
        </label>
        <textarea
          id={`${base}-motivo`}
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
          rows={3}
          aria-describedby={error ? `${base}-error` : undefined}
          className="w-full rounded-lg border border-slate-300 bg-white p-3 text-base"
        />
      </div>

      {error && (
        <p id={`${base}-error`} role="alert" className="flex items-start gap-2 text-sm text-red-700">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" />
          <span>{error}</span>
        </p>
      )}

      <div className="flex flex-col gap-3 sm:flex-row">
        <button type="submit" className={`${BOTON} bg-blue-600 text-white`}>
          <PencilLine size={18} />
          Registrar corrección
        </button>
        <button type="button" onClick={onCancelar} className={`${BOTON} border border-slate-300 text-slate-700`}>
          Cancelar
        </button>
      </div>
    </form>
  );
}
