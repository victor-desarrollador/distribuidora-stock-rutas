// Catálogo de clientes en Supabase (slice clientes).
//
// Lectura: SELECT directo sobre `clientes`, acotado por RLS a la empresa del
// perfil activo (los tres roles leen). Escritura: sólo por las RPC
// crear_cliente, actualizar_cliente, validar_cliente y cambiar_estado_cliente;
// `authenticated` no tiene INSERT/UPDATE/DELETE sobre la tabla. `empresa_id`,
// el autor y el validador los deriva el servidor: nunca se envían.
//
// Permisos (Blueprint §2, §9): vendedor/piloto crea (queda pendiente) y
// consulta; dueño y encargado crean (quedan validados), editan, validan y
// activan/desactivan. Los permisos de esta capa sólo deciden qué acciones se
// muestran: la frontera real es la base (RPC + RLS).
//
// Errores: las RPC responden un `message` estable; aquí se traduce a un texto
// en español. Nunca se muestra el detalle de SQL ni de PostgREST: cualquier
// error desconocido da un mensaje genérico.

import type { SupabaseClient } from "@supabase/supabase-js";

import type { RolUsuario } from "../auth/roles";
import { obtenerClienteSupabase } from "./supabase";

export type EstadoValidacionCliente = "pendiente" | "validado";

export interface ClienteCatalogo {
  id: string;
  nombre: string;
  comercio: string | null;
  direccion: string | null;
  telefono: string;
  activo: boolean;
  estadoValidacion: EstadoValidacionCliente;
}

// Lo que se envía al alta y a la edición. Comercio y dirección vacíos viajan
// como null; nombre y teléfono ya recortados.
export interface DatosCliente {
  nombre: string;
  telefono: string;
  comercio: string | null;
  direccion: string | null;
}

// Valores del formulario, tal como se escriben.
export interface EntradaCliente {
  nombre: string;
  telefono: string;
  comercio: string;
  direccion: string;
}

export type ResultadoClientes<T> =
  | { ok: true; datos: T }
  | { ok: false; error: string };

export interface PuertoClientes {
  listar(): Promise<ResultadoClientes<ClienteCatalogo[]>>;
  crear(datos: DatosCliente): Promise<ResultadoClientes<string>>;
  actualizar(
    id: string,
    datos: DatosCliente
  ): Promise<ResultadoClientes<null>>;
  validar(id: string): Promise<ResultadoClientes<null>>;
  cambiarEstado(
    id: string,
    activo: boolean
  ): Promise<ResultadoClientes<null>>;
}

export const MENSAJE_ERROR_LECTURA =
  "No se pudo leer el catálogo de clientes. Intentá de nuevo.";
export const MENSAJE_ERROR_GENERICO =
  "No se pudo guardar el cliente. Intentá de nuevo.";

const MENSAJE_SIN_PERMISO = "No tenés permiso para realizar esta acción.";

export const MENSAJE_NOMBRE_REQUERIDO = "Ingresá el nombre del cliente.";
export const MENSAJE_TELEFONO_REQUERIDO = "Ingresá el teléfono del cliente.";

// Códigos estables de las RPC → texto para el usuario.
const MENSAJES_ERROR: Record<string, string> = {
  cliente_no_autenticado: "Tu sesión no es válida. Volvé a iniciar sesión.",
  cliente_no_autorizado: MENSAJE_SIN_PERMISO,
  cliente_no_encontrado: "El cliente ya no existe o no pertenece a tu empresa.",
  cliente_nombre_invalido: MENSAJE_NOMBRE_REQUERIDO,
  cliente_telefono_invalido: MENSAJE_TELEFONO_REQUERIDO,
  cliente_estado_invalido: "El estado del cliente no es válido.",
};

/**
 * Traduce un error de Supabase a un mensaje seguro. Sólo se usa el `message`
 * cuando es un código conocido; cualquier otra cosa (incluido el detalle de
 * SQL o PostgREST, y `cliente_error_interno`) se reemplaza por un mensaje
 * genérico.
 */
export function mensajeErrorClientes(error: unknown): string {
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
 * Normaliza lo que escribió el usuario: recorta los extremos y convierte
 * comercio/dirección vacíos en null. No impone formato de teléfono ni
 * deduplica: la base es la autoridad.
 */
export function normalizarDatosCliente(entrada: EntradaCliente): DatosCliente {
  const opcional = (valor: string) => {
    const recortado = valor.trim();
    return recortado === "" ? null : recortado;
  };

  return {
    nombre: entrada.nombre.trim(),
    telefono: entrada.telefono.trim(),
    comercio: opcional(entrada.comercio),
    direccion: opcional(entrada.direccion),
  };
}

// Validación previa al envío. La base vuelve a validar todo.
export function validarDatosCliente(datos: DatosCliente): string | null {
  if (datos.nombre === "") return MENSAJE_NOMBRE_REQUERIDO;
  if (datos.telefono === "") return MENSAJE_TELEFONO_REQUERIDO;
  return null;
}

export interface PermisosClientes {
  puedeCrear: boolean;
  puedeEditar: boolean;
  puedeValidar: boolean;
  puedeCambiarEstado: boolean;
}

/**
 * Qué acciones se muestran según el rol. Sólo UX: cada RPC vuelve a
 * autorizar en la base, y un rol desconocido no ve ninguna acción.
 */
export function permisosClientes(rol: RolUsuario | undefined): PermisosClientes {
  const gestion = rol === "dueno" || rol === "encargado";

  return {
    puedeCrear: gestion || rol === "vendedor_piloto",
    puedeEditar: gestion,
    puedeValidar: gestion,
    puedeCambiarEstado: gestion,
  };
}

const COLUMNAS = [
  "id",
  "nombre",
  "comercio",
  "direccion",
  "telefono",
  "activo",
  "estado_validacion",
];

/**
 * Convierte una fila de la base al modelo de la UI. Falla cerrado: cualquier
 * campo inesperado, incluida una columna de más, devuelve null.
 */
export function filaACliente(fila: unknown): ClienteCatalogo | null {
  if (fila === null || typeof fila !== "object") return null;

  const f = fila as Record<string, unknown>;
  const columnas = Object.keys(f);
  const textoOpcional = (v: unknown) =>
    v === null || (typeof v === "string" && v.trim() !== "");

  if (
    columnas.length !== COLUMNAS.length ||
    !COLUMNAS.every((c) => columnas.includes(c)) ||
    typeof f.id !== "string" ||
    f.id === "" ||
    typeof f.nombre !== "string" ||
    f.nombre.trim() === "" ||
    typeof f.telefono !== "string" ||
    f.telefono.trim() === "" ||
    !textoOpcional(f.comercio) ||
    !textoOpcional(f.direccion) ||
    typeof f.activo !== "boolean" ||
    (f.estado_validacion !== "pendiente" && f.estado_validacion !== "validado")
  ) {
    return null;
  }

  return {
    id: f.id,
    nombre: f.nombre,
    comercio: f.comercio as string | null,
    direccion: f.direccion as string | null,
    telefono: f.telefono,
    activo: f.activo,
    estadoValidacion: f.estado_validacion,
  };
}

export function crearPuertoClientes(cliente: SupabaseClient): PuertoClientes {
  async function ejecutarSinResultado(
    llamada: () => PromiseLike<{ error: unknown }>
  ): Promise<ResultadoClientes<null>> {
    try {
      const { error } = await llamada();
      if (error) return { ok: false, error: mensajeErrorClientes(error) };
      return { ok: true, datos: null };
    } catch {
      return { ok: false, error: MENSAJE_ERROR_GENERICO };
    }
  }

  return {
    async listar() {
      try {
        const { data, error } = await cliente
          .from("clientes")
          .select(COLUMNAS.join(", "))
          .order("nombre");

        if (error || !Array.isArray(data)) {
          return { ok: false, error: MENSAJE_ERROR_LECTURA };
        }

        const clientes = data.map(filaACliente);

        // Una sola fila inesperada invalida la lectura completa.
        if (clientes.some((c) => c === null)) {
          return { ok: false, error: MENSAJE_ERROR_LECTURA };
        }

        return { ok: true, datos: clientes as ClienteCatalogo[] };
      } catch {
        return { ok: false, error: MENSAJE_ERROR_LECTURA };
      }
    },

    async crear(datos) {
      try {
        const { data, error } = await cliente.rpc("crear_cliente", {
          p_nombre: datos.nombre,
          p_telefono: datos.telefono,
          p_comercio: datos.comercio,
          p_direccion: datos.direccion,
        });

        if (error) return { ok: false, error: mensajeErrorClientes(error) };
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
        cliente.rpc("actualizar_cliente", {
          p_cliente_id: id,
          p_nombre: datos.nombre,
          p_telefono: datos.telefono,
          p_comercio: datos.comercio,
          p_direccion: datos.direccion,
        })
      );
    },

    validar(id) {
      return ejecutarSinResultado(() =>
        cliente.rpc("validar_cliente", { p_cliente_id: id })
      );
    },

    cambiarEstado(id, activo) {
      return ejecutarSinResultado(() =>
        cliente.rpc("cambiar_estado_cliente", {
          p_cliente_id: id,
          p_activo: activo,
        })
      );
    },
  };
}

let puerto: PuertoClientes | null = null;

export function obtenerPuertoClientes(): PuertoClientes {
  if (!puerto) puerto = crearPuertoClientes(obtenerClienteSupabase());
  return puerto;
}
