import { useState } from "react";
import { AlertTriangle, Loader2, UserRoundCog } from "lucide-react";

import { nombreRol } from "../auth/roles";
import type { Jornada } from "../lib/jornadas";
import type { VendedorJornada } from "../lib/vendedores_jornada";
import type { EstadoVendedores } from "./jornadas_apertura";
import {
  admiteReasignacion,
  etiquetaVendedor,
  type EntradaReasignacion,
  type FaseReasignacion,
} from "./jornadas_reasignacion";
import { formatearFechaOperativa } from "./jornadas_presentacion";

// Panel de «Cambiar vendedor» (FE-2B) dentro del detalle de la jornada.
// Presentacional: todo llega por props. La pantalla lo monta sólo para dueño y
// encargado; quién puede reasignar y a quién lo decide el servidor. Se ofrece
// sólo en `abierta` y `cargada` (ADR-007 §2.3.3). El resultado (éxito o
// rechazo) lo anuncia el aviso de la pantalla, porque la relectura desmonta
// este panel. Cambiar el vendedor exige dos pasos: elegir y confirmar.

export interface JornadaReasignacionPanelProps {
  jornada: Jornada;
  fase: FaseReasignacion;
  // Otra operación retiene esta jornada. Sólo presentación: la exclusión
  // efectiva la aplica el motor.
  bloqueadaPorOtra?: boolean;
  motivoBloqueo?: string;
  vendedores: EstadoVendedores;
  onSolicitar: (jornada: Jornada) => void;
  onCancelar: () => void;
  onConfirmar: (entrada: EntradaReasignacion) => void;
  onReintentar: () => void;
  onVerificar: () => void;
  onRecargarVendedores: () => void;
}

export const MOTIVO_BLOQUEO_REASIGNACION_POR_DEFECTO =
  "Hay otra operación de esta jornada en curso o sin resolver. Terminala o verificá su estado antes de cambiar el vendedor.";

const BOTON =
  "flex min-h-12 items-center justify-center gap-2 rounded-lg px-5 font-semibold disabled:cursor-not-allowed disabled:opacity-60";
const CAMPO = "min-h-12 w-full rounded-lg border border-slate-300 bg-white px-3 text-base";

function BotonDeshabilitado({ idAyuda, texto }: { idAyuda: string; texto: string }) {
  return (
    <div className="mt-4 space-y-1">
      <button type="button" disabled aria-describedby={idAyuda} className={`${BOTON} bg-slate-200 text-slate-500`}>
        Cambiar vendedor
      </button>
      <p id={idAyuda} className="text-xs text-slate-500">
        {texto}
      </p>
    </div>
  );
}

export function JornadaReasignacionPanel(props: JornadaReasignacionPanelProps) {
  const { jornada, fase, bloqueadaPorOtra = false, onSolicitar, onReintentar, onVerificar } = props;
  const propia = fase.fase !== "inactiva" && fase.jornadaId === jornada.id ? fase : null;
  const idAyuda = `reasignacion-ayuda-${jornada.id}`;

  if (propia?.fase === "confirmando") {
    return <FormularioReasignacion {...props} error={propia.error} />;
  }

  if (propia?.fase === "enviando" || propia?.fase === "verificando") {
    return (
      <div className="mt-4 space-y-2">
        <button type="button" disabled aria-disabled="true" className={`${BOTON} bg-slate-200 text-slate-600`}>
          <Loader2 size={18} className="animate-spin" />
          {propia.fase === "enviando" ? "Cambiando vendedor…" : "Consultando estado…"}
        </button>
        <p role="status" className="text-sm text-slate-600">
          {propia.fase === "enviando"
            ? "Enviando el cambio de vendedor. No cierres ni recargues la pantalla."
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
              Reintentar cambio de vendedor
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
  // (los datos locales todavía muestran el vendedor anterior).
  if (propia?.fase === "exito" && propia.releida !== true) return null;

  // Sólo `abierta` y `cargada` admiten la reasignación: en otro estado no se ofrece.
  if (!admiteReasignacion(jornada)) return null;

  if (bloqueadaPorOtra) {
    return (
      <BotonDeshabilitado
        idAyuda={idAyuda}
        texto={props.motivoBloqueo ?? MOTIVO_BLOQUEO_REASIGNACION_POR_DEFECTO}
      />
    );
  }

  // Otra jornada tiene un cambio de vendedor con resultado desconocido: hasta
  // resolverlo no se inicia otro (conserva la clave de esa intención).
  if (fase.fase === "desconocido" && fase.jornadaId !== jornada.id) {
    return (
      <BotonDeshabilitado
        idAyuda={idAyuda}
        texto="Hay un cambio de vendedor de otra jornada sin resolver. Abrí esa jornada y verificá su estado antes de cambiar otro."
      />
    );
  }

  return (
    <div className="mt-4">
      <button
        type="button"
        onClick={() => onSolicitar(jornada)}
        className={`${BOTON} border border-blue-600 text-blue-700`}
      >
        <UserRoundCog size={18} />
        Cambiar vendedor
      </button>
    </div>
  );
}

function FormularioReasignacion({
  jornada,
  vendedores,
  onCancelar,
  onConfirmar,
  onRecargarVendedores,
  error,
}: JornadaReasignacionPanelProps & { error?: string }) {
  const [vendedorId, setVendedorId] = useState("");
  const [revisando, setRevisando] = useState(false);
  const base = `reasignacion-${jornada.id}`;
  const lista: VendedorJornada[] = vendedores.estado === "listo" ? vendedores.vendedores : [];
  // El vigente nunca se ofrece: elegirlo no es un cambio.
  const candidatos = lista.filter((v) => v.usuarioId !== jornada.vendedorId.toLowerCase());
  const elegido = candidatos.find((v) => v.usuarioId === vendedorId) ?? null;
  const permitidos = candidatos.map((v) => v.usuarioId);

  if (revisando && elegido !== null) {
    return (
      <ConfirmacionReasignacion
        jornada={jornada}
        actual={etiquetaVendedor(vendedores, jornada.vendedorId)}
        nuevo={`${elegido.nombre} (${nombreRol(elegido.rol)})`}
        error={error}
        onConfirmar={() => onConfirmar({ vendedorId: elegido.usuarioId, permitidos })}
        onVolver={() => setRevisando(false)}
      />
    );
  }

  let ayuda: string | null = null;
  if (vendedores.estado === "inactivo" || vendedores.estado === "cargando") {
    ayuda = "Leyendo la lista de vendedores…";
  } else if (vendedores.estado === "error") {
    ayuda = vendedores.mensaje;
  } else if (candidatos.length === 0) {
    ayuda = "No hay otro vendedor activo para asignar.";
  }

  return (
    <form
      noValidate
      aria-labelledby={`${base}-titulo`}
      onSubmit={(e) => {
        e.preventDefault();
        if (elegido !== null) setRevisando(true);
      }}
      className="mt-4 space-y-4 rounded-xl border border-blue-200 bg-blue-50 p-4"
    >
      <p id={`${base}-titulo`} className="font-semibold text-slate-800">
        Cambiar vendedor
      </p>
      <p className="text-sm text-slate-600">
        Vendedor actual: <strong>{etiquetaVendedor(vendedores, jornada.vendedorId)}</strong>
      </p>

      <div className="space-y-1">
        <label htmlFor={`${base}-vendedor`} className="block text-sm font-medium text-slate-700">
          Nuevo vendedor
        </label>
        <select
          id={`${base}-vendedor`}
          value={vendedorId}
          onChange={(e) => setVendedorId(e.target.value)}
          disabled={candidatos.length === 0}
          aria-describedby={ayuda !== null ? `${base}-ayuda` : undefined}
          className={CAMPO}
        >
          <option value="">Elegí un vendedor</option>
          {candidatos.map((v) => (
            <option key={v.usuarioId} value={v.usuarioId}>
              {v.nombre} — {nombreRol(v.rol)}
            </option>
          ))}
        </select>
        {ayuda !== null && (
          <p
            id={`${base}-ayuda`}
            role={vendedores.estado === "error" ? "alert" : undefined}
            className={`text-xs ${vendedores.estado === "error" ? "text-red-700" : "text-slate-600"}`}
          >
            {ayuda}
          </p>
        )}
        {vendedores.estado === "error" && (
          <button
            type="button"
            onClick={onRecargarVendedores}
            className={`${BOTON} border border-slate-300 text-slate-700`}
          >
            Reintentar lectura de vendedores
          </button>
        )}
      </div>

      {error && (
        <p id={`${base}-error`} role="alert" className="flex items-start gap-2 text-sm text-red-700">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" />
          <span>{error}</span>
        </p>
      )}

      <div className="flex flex-col gap-3 sm:flex-row">
        <button type="submit" disabled={elegido === null} className={`${BOTON} bg-blue-600 text-white`}>
          Revisar cambio
        </button>
        <button type="button" onClick={onCancelar} className={`${BOTON} border border-slate-300 text-slate-700`}>
          Cancelar
        </button>
      </div>
    </form>
  );
}

export interface ConfirmacionReasignacionProps {
  jornada: Jornada;
  actual: string;
  nuevo: string;
  error?: string;
  onConfirmar: () => void;
  onVolver: () => void;
}

/** Segundo paso: nada se envía hasta «Confirmar cambio». */
export function ConfirmacionReasignacion({
  jornada,
  actual,
  nuevo,
  error,
  onConfirmar,
  onVolver,
}: ConfirmacionReasignacionProps) {
  return (
    <div
      role="group"
      aria-labelledby={`reasignacion-confirmar-${jornada.id}`}
      className="mt-4 space-y-4 rounded-xl border border-amber-300 bg-amber-50 p-4"
    >
      <p id={`reasignacion-confirmar-${jornada.id}`} className="font-semibold text-slate-800">
        Confirmá el cambio de vendedor
      </p>
      <p className="text-sm text-slate-700">
        Jornada del {formatearFechaOperativa(jornada.fecha)}: el vendedor pasa de{" "}
        <strong>{actual}</strong> a <strong>{nuevo}</strong>. Queda registrado en el
        historial de la jornada.
      </p>
      {error && (
        <p role="alert" className="flex items-start gap-2 text-sm text-red-700">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" />
          <span>{error}</span>
        </p>
      )}
      <div className="flex flex-col gap-3 sm:flex-row">
        <button type="button" onClick={onConfirmar} className={`${BOTON} bg-blue-600 text-white`}>
          <UserRoundCog size={18} />
          Confirmar cambio
        </button>
        <button type="button" onClick={onVolver} className={`${BOTON} border border-slate-300 text-slate-700`}>
          Volver
        </button>
      </div>
    </div>
  );
}
