
import {
  Navigate,
  useLocation,
} from "react-router-dom";

import {
  useAuth,
  type RolUsuario,
} from "../AuthContext";

import type { ReactNode } from "react";

interface Props {
  roles: RolUsuario[];
  children: ReactNode;
}

export default function ProtectedRoute({
  roles,
  children,
}: Props) {
  const { usuario } = useAuth();
  const location = useLocation();

  if (!usuario) {
    return (
      <Navigate
        to="/login"
        replace
        state={{ from: location.pathname }}
      />
    );
  }

  if (!roles.includes(usuario.rol)) {
    return (
      <div className="mx-auto max-w-2xl rounded-xl border border-red-200 bg-white p-8">
        <h1 className="text-2xl font-bold text-red-700">
          Acceso no permitido
        </h1>

        <p className="mt-3 text-slate-600">
          El perfil {usuario.rol} no tiene permiso
          para acceder a este módulo.
        </p>
      </div>
    );
  }

  return <>{children}</>;
}
