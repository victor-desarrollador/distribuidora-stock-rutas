import { useEffect, useRef, useState, type ReactNode } from "react";

import { AuthContext } from "./auth/AuthContextValue";
import {
  crearControladorSesion,
  iniciarSesion as iniciarSesionConPuerto,
  type ControladorSesion,
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

  const controlador = useRef<ControladorSesion | null>(null);

  // La sesión se restaura desde Supabase (que valida el token) y el perfil
  // se vuelve a leer del servidor en cada evento de Auth: nada de
  // autorización se toma de localStorage ni del JWT. El controlador se crea
  // por suscripción para que un desmontaje (p. ej. StrictMode) no deje uno
  // detenido en uso.
  useEffect(() => {
    if (!puerto) return;

    const actual = crearControladorSesion(puerto, setSesion);
    controlador.current = actual;

    const desuscribir = puerto.alCambiarUsuario(actual.notificarUsuario);

    return () => {
      actual.detener();
      desuscribir();
      if (controlador.current === actual) controlador.current = null;
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

    // Se invalida antes de esperar a Supabase: ninguna lectura de perfil en
    // curso puede volver a dejar la sesión autorizada.
    if (controlador.current) controlador.current.invalidar();
    else setSesion({ estado: "no_autenticado" });

    await puerto.cerrarSesion();
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
