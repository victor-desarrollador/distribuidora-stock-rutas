
import {
  createContext,
  useContext,
  useState,
  type ReactNode,
} from "react";

export type RolUsuario =
  | "administrador"
  | "vendedor"
  | "deposito";

export interface UsuarioDemo {
  id: string;
  nombre: string;
  rol: RolUsuario;
}

const CLAVE_SESION = "distribuidora_sesion_demo_v1";

export const usuariosDemo: UsuarioDemo[] = [
  {
    id: "admin-demo",
    nombre: "Administrador",
    rol: "administrador",
  },
  {
    id: "vendedor-demo",
    nombre: "Vendedor de reparto",
    rol: "vendedor",
  },
  {
    id: "deposito-demo",
    nombre: "Encargado de depósito",
    rol: "deposito",
  },
];

interface AuthContextType {
  usuario: UsuarioDemo | null;
  iniciarSesion: (usuarioId: string) => boolean;
  cerrarSesion: () => void;
}

const AuthContext = createContext<
  AuthContextType | undefined
>(undefined);

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

export function useAuth() {
  const contexto = useContext(AuthContext);

  if (!contexto) {
    throw new Error(
      "useAuth debe utilizarse dentro de AuthProvider"
    );
  }

  return contexto;
}
