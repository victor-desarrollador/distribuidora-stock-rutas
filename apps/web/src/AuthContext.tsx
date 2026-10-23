import { useEffect, useState, type ReactNode } from "react";

import { AuthContext } from "./auth/AuthContextValue";
import {
  iniciarSesion as iniciarSesionConPuerto,
  resolverEstadoSesion,
  type EstadoSesion,
  type PuertoAuth,
  type ResultadoInicioSesion,
} from "./auth/sesion";
import { obtenerPuertoAuth } from "./lib/supabase";

type Inicializacion =
  | { puerto: PuertoAuth; error: null }
  | { puerto: null; error: string };

function inicializar(): Inicializacion {
  try {
    return { puerto: obtenerPuertoAuth(), error: null };
  } catch (e) {
    return {
      puerto: null,
      error:
        e instanceof Error
          ? e.message
          : "No se pudo inicializar la autenticación.",
    };
  }
}

export function AuthProvider({
  children,
}: {
  children: ReactNode;
}) {
  const [{ puerto, error }] = useState(inicializar);

  const [sesion, setSesion] = useState<EstadoSesion>(() =>
    error
      ? { estado: "error", mensaje: error }
      : { estado: "cargando" }
  );

  // La sesión se restaura desde Supabase (que valida el token) y el perfil
  // se vuelve a leer del servidor en cada carga: nada de autorización se
  // toma de localStorage.
  useEffect(() => {
    if (!puerto) return;

    let vigente = true;
    let secuencia = 0;

    const desuscribir = puerto.alCambiarUsuario((usuarioId) => {
      const actual = ++secuencia;

      if (usuarioId) setSesion({ estado: "cargando" });

      void resolverEstadoSesion(puerto, usuarioId).then((estado) => {
        if (vigente && actual === secuencia) setSesion(estado);
      });
    });

    return () => {
      vigente = false;
      desuscribir();
    };
  }, [puerto]);

  async function iniciarSesion(
    usuario: string,
    password: string
  ): Promise<ResultadoInicioSesion> {
    if (!puerto) {
      return { ok: false, mensaje: error ?? "Autenticación no disponible." };
    }

    return iniciarSesionConPuerto(puerto, usuario, password);
  }

  async function cerrarSesion() {
    if (!puerto) return;

    try {
      await puerto.cerrarSesion();
    } finally {
      setSesion({ estado: "no_autenticado" });
    }
  }

  return (
    <AuthContext.Provider
      value={{
        sesion,
        usuario:
          sesion.estado === "autenticado" ? sesion.perfil : null,
        iniciarSesion,
        cerrarSesion,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
