import { AlertTriangle, Loader2, Send } from "lucide-react";

import type { Jornada } from "../lib/jornadas";
import type { FaseSalida } from "./jornadas_salida";
import { ETIQUETA_ESTADO_JORNADA } from "./jornadas_presentacion";

// Panel de «Confirmar salida» (B-02b.2 / S1) dentro del detalle de la jornada.
// Presentacional: todo llega por props. La pantalla lo monta sólo para dueño y
// encargado; quién puede confirmar lo decide el servidor.

export interface JornadaSalidaPanelProps {
  jornada: Jornada;
  fase: FaseSalida;
  // Otra operación (la corrección) retiene esta jornada (S2 M-02). Sólo
  // presentación: la exclusión efectiva la aplica el motor.
  bloqueadaPorOtra?: boolean;
  // FE-2B: qué operación la retiene. Sin valor, el texto de la corrección.
  motivoBloqueo?: string;
  nombreCamion: string;
  onSolicitar: (jornada: Jornada) => void;
  onCancelar: () => void;
  onConfirmar: () => void;
  onReintentar: () => void;
  onVerificar: () => void;
}

const BOTON =
  "flex min-h-12 items-center justify-center gap-2 rounded-lg px-5 font-semibold disabled:cursor-not-allowed disabled:opacity-60";

export function JornadaSalidaPanel({
  jornada,
  fase,
  bloqueadaPorOtra = false,
  motivoBloqueo,
  nombreCamion,
  onSolicitar,
  onCancelar,
  onConfirmar,
  onReintentar,
  onVerificar,
}: JornadaSalidaPanelProps) {
  // La fase sólo se aplica a la jornada sobre la que se operó.
  const propia = fase.fase !== "inactiva" && fase.jornadaId === jornada.id ? fase : null;
  const idAyuda = `salida-ayuda-${jornada.id}`;

  if (propia?.fase === "confirmando") {
    return (
      <div
        role="group"
        aria-labelledby={`salida-pregunta-${jornada.id}`}
        className="mt-4 space-y-3 rounded-xl border border-blue-200 bg-blue-50 p-4"
      >
        <p id={`salida-pregunta-${jornada.id}`} className="font-semibold text-slate-800">
          ¿Confirmás la salida de {nombreCamion}?
        </p>
        <p className="text-sm text-slate-600">
          La jornada pasará a «En reparto». Después ya no se admiten cargas,
          descargas ni cambios de vendedor.
        </p>
        <div className="flex flex-col gap-3 sm:flex-row">
          <button type="button" onClick={onConfirmar} className={`${BOTON} bg-blue-600 text-white`}>
            <Send size={18} />
            Sí, confirmar salida
          </button>
          <button type="button" onClick={onCancelar} className={`${BOTON} border border-slate-300 text-slate-700`}>
            Cancelar
          </button>
        </div>
      </div>
    );
  }

  if (propia?.fase === "enviando" || propia?.fase === "verificando") {
    return (
      <div className="mt-4 space-y-2">
        <button type="button" disabled aria-disabled="true" className={`${BOTON} bg-slate-200 text-slate-600`}>
          <Loader2 size={18} className="animate-spin" />
          {propia.fase === "enviando" ? "Confirmando salida…" : "Consultando estado…"}
        </button>
        <p role="status" className="text-sm text-slate-600">
          {propia.fase === "enviando"
            ? "Enviando la confirmación. No cierres ni recargues la pantalla."
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
              Reintentar confirmación
            </button>
          )}
          <button type="button" onClick={onVerificar} className={`${BOTON} border border-amber-400 text-amber-900`}>
            Verificar estado
          </button>
        </div>
      </div>
    );
  }

  // El resultado (éxito o rechazo definitivo) lo anuncia AvisoSalidaJornada,
  // fuera del detalle: la relectura desmonta este panel (corrección S1-C5).

  // Tras un éxito no se ofrece ninguna acción, aunque la jornada local todavía
  // figure `cargada` mientras llega la relectura (evita una segunda intención).
  if (propia?.fase === "exito") return null;

  if (bloqueadaPorOtra) {
    return (
      <div className="mt-4 space-y-1">
        <button
          type="button"
          disabled
          aria-describedby={idAyuda}
          className={`${BOTON} bg-slate-200 text-slate-500`}
        >
          Confirmar salida
        </button>
        <p id={idAyuda} className="text-xs text-slate-500">
          {motivoBloqueo ??
            "Hay una corrección de esta jornada en curso o sin resolver. Terminala o verificá su estado antes de confirmar la salida."}
        </p>
      </div>
    );
  }

  // Otra jornada tiene una confirmación con resultado desconocido: hasta
  // resolverla no se inicia otra (conserva la clave de esa intención).
  if (fase.fase === "desconocido" && fase.jornadaId !== jornada.id) {
    return (
      <div className="mt-4 space-y-1">
        <button
          type="button"
          disabled
          aria-describedby={idAyuda}
          className={`${BOTON} bg-slate-200 text-slate-500`}
        >
          Confirmar salida
        </button>
        <p id={idAyuda} className="text-xs text-slate-500">
          Hay una confirmación de salida de otra jornada sin resolver. Abrí esa
          jornada y verificá su estado antes de confirmar otra.
        </p>
      </div>
    );
  }

  // Sólo una jornada `cargada` admite la salida (ADR-007 §2.2).
  if (jornada.estado !== "cargada") {
    return (
      <div className="mt-4 space-y-1">
        <button
          type="button"
          disabled
          aria-describedby={idAyuda}
          className={`${BOTON} bg-slate-200 text-slate-500`}
        >
          Confirmar salida
        </button>
        <p id={idAyuda} className="text-xs text-slate-500">
          Sólo se puede confirmar la salida de una jornada cargada (estado actual:{" "}
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
        className={`${BOTON} bg-blue-600 text-white`}
      >
        <Send size={18} />
        Confirmar salida
      </button>
    </div>
  );
}
