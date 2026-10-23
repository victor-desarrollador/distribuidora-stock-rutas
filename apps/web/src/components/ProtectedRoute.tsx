
import {
  Navigate,
  useLocation,
} from "react-router-dom";

import { useAuth } from "../auth/useAuth";
import { nombreRol, type RolUsuario } from "../auth/roles";
import { decidirAcceso } from "../auth/sesion";
import {
  PantallaAccesoBloqueado,
  PantallaCargandoSesion,
} from "./EstadoAcceso";

import type { ReactNode } from "react";

interface Props {
  roles: RolUsuario[];
  children: ReactNode;
}

// La decisión se toma sobre el perfil leído del servidor (RLS). Es una guarda
// de interfaz: la defensa real son las políticas de la base.
export default function ProtectedRoute({
  roles,
  children,
}: Props) {
  const { sesion, usuario } = useAuth();
  const location = useLocation();

  const decision = decidirAcceso(sesion, roles);

  if (decision === "cargando") {
    return <PantallaCargandoSesion />;
  }

  if (decision === "redirigir_login") {
    return (
      <Navigate
        to="/login"
        replace
        state={{ from: location.pathname }}
      />
    );
  }

  if (decision === "bloqueado") {
    return <PantallaAccesoBloqueado />;
  }

  if (decision === "rol_no_permitido") {
    return (
      <div className="mx-auto max-w-2xl rounded-xl border border-red-200 bg-white p-8">
        <h1 className="text-2xl font-bold text-red-700">
          Acceso no permitido
        </h1>

        <p className="mt-3 text-slate-600">
          El perfil {usuario ? nombreRol(usuario.rol) : ""} no tiene permiso
          para acceder a este módulo.
        </p>
      </div>
    );
  }

  return <>{children}</>;
}
