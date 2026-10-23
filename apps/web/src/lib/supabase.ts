// Cliente Supabase del navegador.
//
// Usa únicamente variables públicas: la URL del proyecto y la publishable key
// (o la anon key legacy). Nunca service_role ni secret keys: se rechazan si
// alguien las configura por error.

import {
  createClient,
  type AuthChangeEvent,
  type Session,
  type SupabaseClient,
} from "@supabase/supabase-js";

import type { PuertoAuth } from "../auth/sesion";

export interface ConfigSupabase {
  url: string;
  clavePublica: string;
}

function rolDeJwt(clave: string): string | null {
  const partes = clave.split(".");
  if (partes.length !== 3) return null;

  try {
    const base64 = partes[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload: unknown = JSON.parse(atob(base64));

    return typeof payload === "object" &&
      payload !== null &&
      typeof (payload as { role?: unknown }).role === "string"
      ? (payload as { role: string }).role
      : null;
  } catch {
    return null;
  }
}

export function leerConfigSupabase(
  env: Record<string, unknown>
): ConfigSupabase {
  const url = env.VITE_SUPABASE_URL;
  const clavePublica = env.VITE_SUPABASE_PUBLISHABLE_KEY;

  const faltantes = [
    typeof url === "string" && url.trim() ? null : "VITE_SUPABASE_URL",
    typeof clavePublica === "string" && clavePublica.trim()
      ? null
      : "VITE_SUPABASE_PUBLISHABLE_KEY",
  ].filter(Boolean);

  if (faltantes.length > 0) {
    throw new Error(
      `Falta configurar ${faltantes.join(" y ")} (ver apps/web/.env.example).`
    );
  }

  const clave = (clavePublica as string).trim();

  if (clave.startsWith("sb_secret_") || rolDeJwt(clave) === "service_role") {
    throw new Error(
      "VITE_SUPABASE_PUBLISHABLE_KEY contiene una clave secreta. En el navegador sólo se admite la publishable key."
    );
  }

  return { url: (url as string).trim(), clavePublica: clave };
}

export function crearPuertoSupabase(cliente: SupabaseClient): PuertoAuth {
  return {
    async iniciarConPassword(identificador, password) {
      const { error } = await cliente.auth.signInWithPassword({
        email: identificador,
        password,
      });

      if (!error) return { error: null };

      return {
        error:
          error.code === "invalid_credentials" || error.status === 400
            ? "credenciales"
            : "otro",
      };
    },

    async cerrarSesion() {
      const { error } = await cliente.auth.signOut();

      // Si la revocación remota falla (p. ej. sin conexión), igual se
      // elimina la sesión local para no dejar al usuario conectado.
      if (error) await cliente.auth.signOut({ scope: "local" });
    },

    alCambiarUsuario(callback) {
      let diferido: ReturnType<typeof setTimeout> | undefined;

      // Cada evento (SIGNED_IN, TOKEN_REFRESHED, USER_UPDATED, ...) se
      // notifica aunque el usuario sea el mismo, para volver a leer el
      // perfil: rol, empresa o `activo` pueden haber cambiado. Un evento
      // nuevo cancela el aviso anterior todavía no entregado.
      const { data } = cliente.auth.onAuthStateChange(
        (_evento: AuthChangeEvent, sesion: Session | null) => {
          const usuarioId = sesion?.user.id ?? null;

          clearTimeout(diferido);

          // Sin sesión: se invalida en el acto, sin ventana en la que un
          // aviso viejo pueda volver a autenticar.
          if (!usuarioId) return callback(null);

          // Supabase recomienda no llamar a otros métodos del cliente dentro
          // del callback: se difiere la lectura del perfil.
          diferido = setTimeout(() => callback(usuarioId), 0);
        }
      );

      return () => {
        clearTimeout(diferido);
        data.subscription.unsubscribe();
      };
    },

    async leerPerfil(usuarioId) {
      const { data, error } = await cliente
        .from("perfiles")
        .select("usuario_id, empresa_id, usuario, nombre, rol, activo")
        .eq("usuario_id", usuarioId)
        .maybeSingle();

      if (error) throw new Error("No se pudo leer el perfil.");

      return data;
    },

    async leerEmpresa(empresaId) {
      const { data, error } = await cliente
        .from("empresas")
        .select("id, nombre, activo")
        .eq("id", empresaId)
        .maybeSingle();

      if (error) throw new Error("No se pudo leer la empresa.");

      return data;
    },
  };
}

let cliente: SupabaseClient | null = null;
let puerto: PuertoAuth | null = null;

// Crea el cliente una sola vez y lo comparten Auth y los datos, para usar la
// misma sesión. Lanza un error claro si falta configuración.
export function obtenerClienteSupabase(): SupabaseClient {
  if (!cliente) {
    const config = leerConfigSupabase(import.meta.env);
    cliente = createClient(config.url, config.clavePublica);
  }

  return cliente;
}

export function obtenerPuertoAuth(): PuertoAuth {
  if (!puerto) {
    puerto = crearPuertoSupabase(obtenerClienteSupabase());
  }

  return puerto;
}
