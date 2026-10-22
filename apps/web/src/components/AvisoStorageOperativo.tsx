import { AlertTriangle } from "lucide-react";

export default function AvisoStorageOperativo({ avisos }: { avisos: string[] }) {
  if (avisos.length === 0) return null;

  return (
    <div className="space-y-3">
      {avisos.map((aviso) => (
        <div
          key={aviso}
          role="alert"
          className="flex items-start gap-2 rounded-xl bg-red-50 p-4 text-sm font-medium text-red-800"
        >
          <AlertTriangle size={18} className="mt-0.5 shrink-0" />
          <span>
            <strong>Datos dañados: </strong>
            {aviso}
          </span>
        </div>
      ))}
    </div>
  );
}
