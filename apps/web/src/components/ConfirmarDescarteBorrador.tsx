import { AlertTriangle } from "lucide-react";

// FE-1E: pregunta explícita antes de descartar un borrador de carga con algo
// escrito por una acción voluntaria (abrir otra jornada, cerrar sesión o,
// desde FE-1F, «Cancelar» en el formulario).
// Presentacional: no guarda nada, no llama RPC y no registra cargas. El borrador
// nunca se guardó: aceptar lo pierde definitivamente.

export interface ConfirmarDescarteBorradorProps {
  id: string;
  mensaje: string;
  textoAceptar: string;
  textoCancelar: string;
  onAceptar: () => void;
  onCancelar: () => void;
}

const BOTON =
  "flex min-h-12 items-center justify-center gap-2 rounded-lg px-4 text-sm font-semibold";

export function ConfirmarDescarteBorrador(props: ConfirmarDescarteBorradorProps) {
  const { id, mensaje, textoAceptar, textoCancelar, onAceptar, onCancelar } = props;
  return (
    <div
      role="alertdialog"
      aria-labelledby={`${id}-titulo`}
      aria-describedby={`${id}-mensaje`}
      className="mt-4 space-y-3 rounded-xl border border-amber-300 bg-amber-50 p-4 text-amber-900"
    >
      <p id={`${id}-titulo`} className="flex items-start gap-2 font-semibold">
        <AlertTriangle size={20} className="mt-0.5 shrink-0" aria-hidden="true" />
        <span>Borrador de carga sin registrar</span>
      </p>
      <p id={`${id}-mensaje`} className="text-sm">
        {mensaje}
      </p>
      <div className="flex flex-col gap-2 sm:flex-row">
        <button type="button" onClick={onCancelar} className={`${BOTON} bg-amber-600 text-white`}>
          {textoCancelar}
        </button>
        <button type="button" onClick={onAceptar} className={`${BOTON} border border-amber-400 text-amber-900`}>
          {textoAceptar}
        </button>
      </div>
    </div>
  );
}

export const MENSAJE_DESCARTE_CAMBIO_JORNADA =
  "Tenés un borrador de carga de otra jornada con datos escritos. Si abrís la carga de esta jornada, ese borrador se descarta y no se puede recuperar. No se registró ninguna carga.";
export const MENSAJE_DESCARTE_CANCELAR =
  "Tenés un borrador de carga con datos escritos. Si cancelás, el borrador se descarta y no se puede recuperar. No se registró ninguna carga.";
export const MENSAJE_DESCARTE_CIERRE_SESION =
  "Tenés un borrador de carga con datos escritos. Si cerrás sesión, el borrador se descarta y no se puede recuperar. No se registró ninguna carga.";
