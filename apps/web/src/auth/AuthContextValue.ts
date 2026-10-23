import { createContext } from "react";

import type {
  EstadoSesion,
  Perfil,
  ResultadoInicioSesion,
} from "./sesion";

export interface AuthContextType {
  sesion: EstadoSesion;
  // Perfil protegido del usuario; sólo existe con sesión autorizada.
  usuario: Perfil | null;
  iniciarSesion: (
    usuario: string,
    password: string
  ) => Promise<ResultadoInicioSesion>;
  cerrarSesion: () => Promise<void>;
}

export const AuthContext = createContext<
  AuthContextType | undefined
>(undefined);
