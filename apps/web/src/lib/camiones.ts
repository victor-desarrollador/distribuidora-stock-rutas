// Catálogo de camiones en Supabase (slice camiones).
//
// Lectura: SELECT directo sobre `camiones`, acotado por RLS a la empresa del
// perfil activo (los tres roles leen). Escritura: sólo por las RPC
// crear_camion, actualizar_camion y cambiar_estado_camion, que sólo ejecuta el
// dueño; `authenticated` no tiene INSERT/UPDATE sobre la tabla. `empresa_id` y
// el autor los deriva el servidor del perfil: nunca se envían.
//
// Modelo mínimo (Blueprint §8): patente, nombre y activo. Sin estado
// operativo (`en_reparto` depende de la jornada) ni stock.
//
// Errores: las RPC responden un `message` estable; aquí se traduce a un texto
// en español. Nunca se muestra el detalle de SQL ni de PostgREST: cualquier
// error desconocido da un mensaje genérico.

import type { SupabaseClient } from "@supabase/supabase-js";

import { obtenerClienteSupabase } from "./supabase";

export interface CamionCatalogo {
  id: string;
  patente: string;
  nombre: string;
  activo: boolean;
}

export interface DatosCamion {
  patente: string;
  nombre: string;
}

export type ResultadoCamiones<T> =
  | { ok: true; datos: T }
  | { ok: false; error: string };

export interface PuertoCamiones {
  listar(): Promise<ResultadoCamiones<CamionCatalogo[]>>;
  crear(datos: DatosCamion): Promise<ResultadoCamiones<string>>;
  actualizar(
    id: string,
    datos: DatosCamion
  ): Promise<ResultadoCamiones<null>>;
  cambiarEstado(
    id: string,
    activo: boolean
  ): Promise<ResultadoCamiones<null>>;
}

export const MENSAJE_ERROR_LECTURA =
  "No se pudo leer el catálogo de camiones. Intentá de nuevo.";
export const MENSAJE_ERROR_GENERICO =
  "No se pudo guardar el camión. Intentá de nuevo.";

const MENSAJE_SIN_PERMISO = "No tenés permiso para modificar camiones.";

// Códigos estables de las RPC → texto para el usuario.
const MENSAJES_ERROR: Record<string, string> = {
  camion_no_autenticado: "Tu sesión no es válida. Volvé a iniciar sesión.",
  camion_no_autorizado: MENSAJE_SIN_PERMISO,
  camion_no_encontrado: "El camión ya no existe o no pertenece a tu empresa.",
  camion_patente_invalida: "Ingresá la patente del camión.",
  camion_nombre_invalido: "Ingresá el nombre del camión.",
  camion_estado_invalido: "El estado del camión no es válido.",
  camion_patente_duplicada: "Ya existe otro camión con esa patente.",
};

/**
 * Traduce un error de Supabase a un mensaje seguro. Sólo se usa el `message`
 * cuando es un código conocido; cualquier otra cosa (incluido el detalle de
 * SQL o PostgREST, y `camion_error_interno`) se reemplaza por un mensaje
 * genérico.
 */
export function mensajeErrorCamiones(error: unknown): string {
  if (error !== null && typeof error === "object") {
    const { code, message } = error as { code?: unknown; message?: unknown };

    if (typeof message === "string" && Object.hasOwn(MENSAJES_ERROR, message)) {
      return MENSAJES_ERROR[message];
    }

    // Sin permiso de ejecución (p. ej. sin sesión: rol anon).
    if (code === "42501") return MENSAJE_SIN_PERMISO;
  }

  return MENSAJE_ERROR_GENERICO;
}

/**
 * Convierte una fila de la base al modelo de la UI. Falla cerrado: cualquier
 * campo inesperado, incluida una columna de más, devuelve null.
 */
export function filaACamion(fila: unknown): CamionCatalogo | null {
  if (fila === null || typeof fila !== "object") return null;

  const f = fila as Record<string, unknown>;
  const columnas = Object.keys(f);

  if (
    columnas.length !== 4 ||
    !["id", "patente", "nombre", "activo"].every((c) => columnas.includes(c)) ||
    typeof f.id !== "string" ||
    f.id === "" ||
    typeof f.patente !== "string" ||
    f.patente.trim() === "" ||
    typeof f.nombre !== "string" ||
    f.nombre.trim() === "" ||
    typeof f.activo !== "boolean"
  ) {
    return null;
  }

  return {
    id: f.id,
    patente: f.patente,
    nombre: f.nombre,
    activo: f.activo,
  };
}

export function crearPuertoCamiones(cliente: SupabaseClient): PuertoCamiones {
  async function ejecutarSinResultado(
    llamada: () => PromiseLike<{ error: unknown }>
  ): Promise<ResultadoCamiones<null>> {
    try {
      const { error } = await llamada();
      if (error) return { ok: false, error: mensajeErrorCamiones(error) };
      return { ok: true, datos: null };
    } catch {
      return { ok: false, error: MENSAJE_ERROR_GENERICO };
    }
  }

  return {
    async listar() {
      try {
        const { data, error } = await cliente
          .from("camiones")
          .select("id, patente, nombre, activo")
          .order("nombre");

        if (error || !Array.isArray(data)) {
          return { ok: false, error: MENSAJE_ERROR_LECTURA };
        }

        const camiones = data.map(filaACamion);

        // Una sola fila inesperada invalida la lectura completa.
        if (camiones.some((c) => c === null)) {
          return { ok: false, error: MENSAJE_ERROR_LECTURA };
        }

        return { ok: true, datos: camiones as CamionCatalogo[] };
      } catch {
        return { ok: false, error: MENSAJE_ERROR_LECTURA };
      }
    },

    async crear(datos) {
      try {
        const { data, error } = await cliente.rpc("crear_camion", {
          p_patente: datos.patente,
          p_nombre: datos.nombre,
        });

        if (error) return { ok: false, error: mensajeErrorCamiones(error) };
        if (typeof data !== "string" || data === "") {
          return { ok: false, error: MENSAJE_ERROR_GENERICO };
        }

        return { ok: true, datos: data };
      } catch {
        return { ok: false, error: MENSAJE_ERROR_GENERICO };
      }
    },

    actualizar(id, datos) {
      return ejecutarSinResultado(() =>
        cliente.rpc("actualizar_camion", {
          p_camion_id: id,
          p_patente: datos.patente,
          p_nombre: datos.nombre,
        })
      );
    },

    cambiarEstado(id, activo) {
      return ejecutarSinResultado(() =>
        cliente.rpc("cambiar_estado_camion", {
          p_camion_id: id,
          p_activo: activo,
        })
      );
    },
  };
}

let puerto: PuertoCamiones | null = null;

export function obtenerPuertoCamiones(): PuertoCamiones {
  if (!puerto) puerto = crearPuertoCamiones(obtenerClienteSupabase());
  return puerto;
}
