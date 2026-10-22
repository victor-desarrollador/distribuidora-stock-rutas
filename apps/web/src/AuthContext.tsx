
import { useState, type ReactNode } from "react";

import {
  CLAVE_SESION,
  usuariosDemo,
  type UsuarioDemo,
} from "./auth/usuariosDemo";
import { AuthContext } from "./auth/AuthContextValue";

function recuperarSesion(): UsuarioDemo | null {
  try {
    const id = localStorage.getItem(CLAVE_SESION);

    return (
      usuariosDemo.find((u) => u.id === id) ?? null
    );
  } catch {
    return null;
  }
}

export function AuthProvider({
  children,
}: {
  children: ReactNode;
}) {
  const [usuario, setUsuario] =
    useState<UsuarioDemo | null>(recuperarSesion);

  function iniciarSesion(usuarioId: string): boolean {
    const encontrado = usuariosDemo.find(
      (u) => u.id === usuarioId
    );

    if (!encontrado) return false;

    try {
      localStorage.setItem(
        CLAVE_SESION,
        encontrado.id
      );
      setUsuario(encontrado);
      return true;
    } catch {
      return false;
    }
  }

  function cerrarSesion() {
    try {
      localStorage.removeItem(CLAVE_SESION);
    } catch {
      // La sesión visible también se cierra
      // si localStorage no está disponible.
    }

    setUsuario(null);
  }

  return (
    <AuthContext.Provider
      value={{
        usuario,
        iniciarSesion,
        cerrarSesion,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
