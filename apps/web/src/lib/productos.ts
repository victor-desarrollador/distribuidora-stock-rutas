// Catálogo de productos en Supabase (slice productos).
//
// Lectura: SELECT directo sobre `productos`, acotado por RLS a la empresa del
// perfil activo. Escritura: sólo por las RPC crear_producto,
// actualizar_producto y cambiar_estado_producto; `authenticated` no tiene
// INSERT/UPDATE sobre la tabla. `empresa_id` y el autor los deriva el
// servidor del perfil: nunca se envían.
//
// Sin stock: el stock sólo sale de movimientos_stock (Blueprint §3.1, §7.4).
//
// Forma de venta (ADR-005): `unidad` (lácteos; unidades enteras, precio
// unitario) o `peso` (fiambres; gramos enteros, precio por kg). Este contrato
// es propio del catálogo de Supabase; la capa localStorage transitoria usa el
// mismo modelo `unidad | peso` en su `UnidadMedida`.
// Una fila `pieza` es un dato incompatible: no se convierte a `peso` (D-R4).
//
// Errores (P16-productos): las RPC responden un `message` estable; aquí se
// traduce a un texto en español. Nunca se muestra el detalle de SQL ni de
// PostgREST: cualquier error desconocido da un mensaje genérico.

import type { SupabaseClient } from "@supabase/supabase-js";

import type { Producto } from "../data/mockProductos";
import { es_cantidad_valida } from "../domain/cantidades";
import { precio_valido } from "../domain/precios";
import { obtenerClienteSupabase } from "./supabase";

export type CategoriaProducto = Producto["categoria"];
export type FormaVenta = "unidad" | "peso";

// Lácteos ↔ unidad, Fiambres ↔ peso; no hay otra combinación válida.
const FORMA_VENTA_POR_CATEGORIA: Record<CategoriaProducto, FormaVenta> = {
  Lácteos: "unidad",
  Fiambres: "peso",
};

export function formaVentaParaCategoria(
  categoria: CategoriaProducto
): FormaVenta {
  return FORMA_VENTA_POR_CATEGORIA[categoria];
}

export interface ProductoCatalogo {
  id: string;
  codigo: string | null;
  nombre: string;
  categoria: CategoriaProducto;
  formaVenta: FormaVenta;
  // unidad: precio unitario. peso: precio por kg (ADR-005 §2.1).
  precio: number;
  // En unidad mínima: unidades enteras o gramos enteros (ADR-005 §2.2).
  stockMinimo: number;
  activo: boolean;
}

export interface DatosAltaProducto {
  codigo: string;
  nombre: string;
  categoria: CategoriaProducto;
  formaVenta: FormaVenta;
  precio: number;
  stockMinimo: number;
}

// Categoría y forma de venta no se editan (DE-6): cambiarlas reinterpretaría las
// cantidades en unidad mínima.
export interface DatosEdicionProducto {
  codigo: string;
  nombre: string;
  precio: number;
  stockMinimo: number;
}

export type ResultadoProductos<T> =
  | { ok: true; datos: T }
  | { ok: false; error: string };

export interface PuertoProductos {
  listar(): Promise<ResultadoProductos<ProductoCatalogo[]>>;
  crear(datos: DatosAltaProducto): Promise<ResultadoProductos<string>>;
  actualizar(
    id: string,
    datos: DatosEdicionProducto
  ): Promise<ResultadoProductos<null>>;
  cambiarEstado(
    id: string,
    activo: boolean
  ): Promise<ResultadoProductos<null>>;
}

// Máximo de una columna `integer` de PostgreSQL.
export const STOCK_MINIMO_MAXIMO = 2147483647;

const CATEGORIA_A_BASE: Record<CategoriaProducto, string> = {
  Lácteos: "lacteos",
  Fiambres: "fiambres",
};

const CATEGORIA_DESDE_BASE: Record<string, CategoriaProducto> = {
  lacteos: "Lácteos",
  fiambres: "Fiambres",
};

export const MENSAJE_ERROR_LECTURA =
  "No se pudo leer el catálogo de productos. Intentá de nuevo.";
export const MENSAJE_ERROR_GENERICO =
  "No se pudo guardar el producto. Intentá de nuevo.";

const MENSAJE_SIN_PERMISO = "No tenés permiso para modificar productos.";

// Códigos estables de las RPC (P16-productos) → texto para el usuario.
const MENSAJES_ERROR: Record<string, string> = {
  producto_no_autenticado: "Tu sesión no es válida. Volvé a iniciar sesión.",
  producto_no_autorizado: MENSAJE_SIN_PERMISO,
  producto_no_encontrado:
    "El producto ya no existe o no pertenece a tu empresa.",
  producto_nombre_invalido: "Ingresá el nombre del producto.",
  producto_codigo_invalido: "El código del producto no es válido.",
  producto_categoria_invalida: "La categoría no es válida.",
  producto_forma_venta_invalida: "La forma de venta no es válida.",
  producto_combinacion_invalida:
    "Los lácteos se venden por unidad y los fiambres por peso.",
  producto_precio_invalido:
    "El precio debe ser mayor o igual a 0 y tener como máximo 2 decimales.",
  producto_stock_minimo_invalido:
    "El stock mínimo debe ser un número entero mayor o igual a 0.",
  producto_estado_invalido: "El estado del producto no es válido.",
  producto_codigo_duplicado: "Ya existe otro producto con ese código.",
};

/**
 * Traduce un error de Supabase a un mensaje seguro. Sólo se usa el `message`
 * cuando es un código conocido; cualquier otra cosa (incluido el detalle de
 * SQL o PostgREST) se reemplaza por un mensaje genérico.
 */
export function mensajeErrorProductos(error: unknown): string {
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
 * campo inesperado devuelve null.
 */
export function filaAProducto(fila: unknown): ProductoCatalogo | null {
  if (fila === null || typeof fila !== "object") return null;

  const f = fila as Record<string, unknown>;
  const categoria =
    typeof f.categoria === "string"
      ? CATEGORIA_DESDE_BASE[f.categoria]
      : undefined;
  // Sólo `unidad` y `peso`. `pieza` u otro valor invalida la fila.
  const formaVenta =
    f.forma_venta === "unidad" || f.forma_venta === "peso"
      ? f.forma_venta
      : undefined;

  if (
    typeof f.id !== "string" ||
    f.id === "" ||
    !(f.codigo === null || typeof f.codigo === "string") ||
    typeof f.nombre !== "string" ||
    categoria === undefined ||
    formaVenta === undefined ||
    formaVentaParaCategoria(categoria) !== formaVenta ||
    typeof f.precio !== "number" ||
    !precio_valido(f.precio) ||
    typeof f.stock_minimo !== "number" ||
    !es_cantidad_valida(f.stock_minimo) ||
    typeof f.activo !== "boolean"
  ) {
    return null;
  }

  return {
    id: f.id,
    codigo: f.codigo,
    nombre: f.nombre,
    categoria,
    formaVenta,
    precio: f.precio,
    stockMinimo: f.stock_minimo,
    activo: f.activo,
  };
}

export function crearPuertoProductos(
  cliente: SupabaseClient
): PuertoProductos {
  async function ejecutarSinResultado(
    llamada: () => PromiseLike<{ error: unknown }>
  ): Promise<ResultadoProductos<null>> {
    try {
      const { error } = await llamada();
      if (error) return { ok: false, error: mensajeErrorProductos(error) };
      return { ok: true, datos: null };
    } catch {
      return { ok: false, error: MENSAJE_ERROR_GENERICO };
    }
  }

  return {
    async listar() {
      try {
        const { data, error } = await cliente
          .from("productos")
          .select(
            "id, codigo, nombre, categoria, forma_venta, precio, stock_minimo, activo"
          )
          .order("nombre");

        if (error || !Array.isArray(data)) {
          return { ok: false, error: MENSAJE_ERROR_LECTURA };
        }

        const productos = data.map(filaAProducto);

        // Una sola fila inesperada invalida la lectura completa.
        if (productos.some((p) => p === null)) {
          return { ok: false, error: MENSAJE_ERROR_LECTURA };
        }

        return { ok: true, datos: productos as ProductoCatalogo[] };
      } catch {
        return { ok: false, error: MENSAJE_ERROR_LECTURA };
      }
    },

    async crear(datos) {
      try {
        const { data, error } = await cliente.rpc("crear_producto", {
          p_codigo: datos.codigo,
          p_nombre: datos.nombre,
          p_categoria: CATEGORIA_A_BASE[datos.categoria],
          p_forma_venta: datos.formaVenta,
          p_precio: datos.precio,
          p_stock_minimo: datos.stockMinimo,
        });

        if (error) return { ok: false, error: mensajeErrorProductos(error) };
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
        cliente.rpc("actualizar_producto", {
          p_producto_id: id,
          p_codigo: datos.codigo,
          p_nombre: datos.nombre,
          p_precio: datos.precio,
          p_stock_minimo: datos.stockMinimo,
        })
      );
    },

    cambiarEstado(id, activo) {
      return ejecutarSinResultado(() =>
        cliente.rpc("cambiar_estado_producto", {
          p_producto_id: id,
          p_activo: activo,
        })
      );
    },
  };
}

let puerto: PuertoProductos | null = null;

export function obtenerPuertoProductos(): PuertoProductos {
  if (!puerto) puerto = crearPuertoProductos(obtenerClienteSupabase());
  return puerto;
}
