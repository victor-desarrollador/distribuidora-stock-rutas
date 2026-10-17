import { createContext } from "react";

import type { UsuarioDemo } from "./usuariosDemo";

export interface AuthContextType {
  usuario: UsuarioDemo | null;
  iniciarSesion: (usuarioId: string) => boolean;
  cerrarSesion: () => void;
}

export const AuthContext = createContext<
  AuthContextType | undefined
>(undefined);
