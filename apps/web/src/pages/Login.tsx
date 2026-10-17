
import { useState } from "react";
import {
  Truck,
  ShieldCheck,
  LogIn,
} from "lucide-react";
import { Navigate, useNavigate } from "react-router-dom";

import { useAuth } from "../auth/useAuth";
import {
  usuariosDemo,
  type RolUsuario,
} from "../auth/usuariosDemo";

function inicioPorRol(rol: RolUsuario) {
  if (rol === "vendedor") return "/autoventa";
  if (rol === "deposito") return "/jornadas";
  return "/";
}

export default function Login() {
  const { usuario, iniciarSesion } = useAuth();
  const navigate = useNavigate();

  const [usuarioId, setUsuarioId] = useState(
    usuariosDemo[0].id
  );
  const [error, setError] = useState("");

  if (usuario) {
    return (
      <Navigate
        to={inicioPorRol(usuario.rol)}
        replace
      />
    );
  }

  function ingresar() {
    setError("");

    const elegido = usuariosDemo.find(
      (u) => u.id === usuarioId
    );

    if (!elegido || !iniciarSesion(usuarioId)) {
      setError("No se pudo iniciar la sesión de prueba.");
      return;
    }

    navigate(inicioPorRol(elegido.rol), {
      replace: true,
    });
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-100 p-4">
      <div className="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-8 shadow-lg">
        <div className="mb-6 flex justify-center">
          <div className="rounded-2xl bg-blue-600 p-4 text-white">
            <Truck size={38} />
          </div>
        </div>

        <h1 className="text-center text-3xl font-bold text-slate-900">
          Distribuidora
        </h1>

        <p className="mt-2 text-center text-slate-500">
          Stock, reparto y autoventa
        </p>

        <div className="mt-6 flex items-center gap-2 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">
          <ShieldCheck size={20} className="shrink-0" />
          Acceso de demostración. No es un sistema
          de autenticación seguro.
        </div>

        <label className="mt-6 block space-y-2">
          <span className="text-sm font-semibold text-slate-700">
            Usuario de prueba
          </span>

          <select
            value={usuarioId}
            onChange={(e) => setUsuarioId(e.target.value)}
            className="min-h-14 w-full rounded-xl border border-slate-300 bg-white p-3"
          >
            {usuariosDemo.map((u) => (
              <option key={u.id} value={u.id}>
                {u.nombre}
              </option>
            ))}
          </select>
        </label>

        {error && (
          <p role="alert" className="mt-4 text-sm text-red-700">
            {error}
          </p>
        )}

        <button
          type="button"
          onClick={ingresar}
          className="mt-6 flex min-h-14 w-full items-center justify-center gap-2 rounded-xl bg-blue-600 font-semibold text-white hover:bg-blue-700"
        >
          <LogIn size={21} />
          Ingresar al sistema
        </button>

        <p className="mt-5 text-center text-xs text-slate-500">
          Etapa 13 · Simulación de roles y permisos
        </p>
      </div>
    </div>
  );
}
