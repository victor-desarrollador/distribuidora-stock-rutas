import { AlertTriangle, CheckCircle2 } from "lucide-react";

import type { FaseSalida } from "./jornadas_salida";

// Anuncio del RESULTADO de «Confirmar salida» (B-02b.2 / S1, corrección
// S1-C5). Vive fuera del listado y del detalle: la relectura posterior pone
// la lista en «cargando» y desmonta el detalle, pero este anuncio sigue
// visible y se anuncia de forma accesible.
//
// - La región `role="status"` está SIEMPRE montada (vacía si no hay nada que
//   decir): un lector de pantalla anuncia el cambio de su contenido.
// - El rechazo definitivo se inserta como `role="alert"` sólo cuando existe
//   (no se deja un `alert` vacío montado).

export function AvisoSalidaJornada({ fase }: { fase: FaseSalida }) {
  return (
    <>
      <div role="status" aria-live="polite">
        {fase.fase === "exito" && (
          <p className="flex items-start gap-2 rounded-xl bg-green-50 p-4 text-green-800">
            <CheckCircle2 size={20} className="mt-0.5 shrink-0" />
            <span>{fase.mensaje}</span>
          </p>
        )}
      </div>
      {fase.fase === "error" && (
        <p role="alert" className="flex items-start gap-2 rounded-xl bg-red-50 p-4 text-red-800">
          <AlertTriangle size={20} className="mt-0.5 shrink-0" />
          <span>{fase.mensaje}</span>
        </p>
      )}
    </>
  );
}
