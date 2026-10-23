import { ShieldAlert } from "lucide-react";

import { useAuth } from "../auth/useAuth";
import { mensajeBloqueo } from "../auth/sesion";

export function PantallaCargandoSesion() {
  return (
    <div
      role="status"
      className="flex min-h-screen items-center justify-center bg-slate-100 p-4 text-slate-600"
    >
      Verificando sesión…
    </div>
  );
}

// Usuario autenticado en Supabase pero sin autorización: sin perfil, perfil
// inactivo, empresa no disponible o error al verificar.
export function PantallaAccesoBloqueado() {
  const { sesion, cerrarSesion } = useAuth();

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-100 p-4">
      <div className="w-full max-w-md rounded-2xl border border-red-200 bg-white p-8 shadow-lg">
        <div className="flex items-center gap-3 text-red-700">
          <ShieldAlert size={28} className="shrink-0" />
          <h1 className="text-2xl font-bold">Acceso bloqueado</h1>
        </div>

        <p role="alert" className="mt-4 text-slate-700">
          {mensajeBloqueo(sesion)}
        </p>

        <button
          type="button"
          onClick={() => void cerrarSesion()}
          className="mt-6 min-h-12 w-full rounded-xl bg-slate-800 font-semibold text-white hover:bg-slate-900"
        >
          Cerrar sesión
        </button>
      </div>
    </div>
  );
}
