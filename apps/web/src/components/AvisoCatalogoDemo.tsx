import { Info } from "lucide-react";

// DE-12: el catálogo real de productos ya vive en Supabase, pero las
// pantallas operativas siguen usando el catálogo demo de este navegador
// hasta que existan sus propios bloques de backend.
export default function AvisoCatalogoDemo() {
  return (
    <div
      role="note"
      className="flex items-start gap-2 rounded-xl bg-amber-50 p-4 text-sm text-amber-900"
    >
      <Info size={18} className="mt-0.5 shrink-0" />
      <span>
        <strong>Catálogo de demostración: </strong>
        esta pantalla usa los productos de prueba guardados en este
        navegador, no el catálogo real de la sección Productos.
      </span>
    </div>
  );
}
