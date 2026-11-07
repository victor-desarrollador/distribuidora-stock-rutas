// Stock real en Supabase (B-01): consulta del saldo y operaciones de stock de
// la Etapa 2 (Blueprint §7.2, §7.4, §7.7; ADR-001 §18.3).
//
// Lectura: SELECT con RLS sobre `ubicaciones`, `productos` y la
// vista `stock_actual` (security_invoker: sólo dueño y encargado de la empresa
// obtienen filas). El saldo es la suma de `movimientos_stock`; nunca se edita.
//
// Escritura: sólo por las RPC aprobadas (fachadas SECURITY INVOKER →
// implementaciones privadas SECURITY DEFINER):
//   - registrar_ingreso(p_idempotency_key, p_producto_id, p_cantidad, p_motivo)
//   - mover_a_cuarentena(p_idempotency_key, p_producto_id, p_ubicacion_origen_id,
//                        p_cantidad, p_motivo)
//   - registrar_merma(p_idempotency_key, p_producto_id, p_ubicacion_origen_id,
//                     p_cantidad, p_motivo_codigo, p_motivo)
// Todas devuelven el id de la operación (uuid). `empresa_id` y el actor los
// deriva el servidor del perfil: nunca se envían. Las cantidades van en unidad
// mínima: unidades enteras o gramos enteros (ADR-005).
//
// Errores (P16-stock): `message` estable `stock_*`; aquí se traduce a español.
// Nunca se muestra el detalle de SQL ni de PostgREST.

import type { SupabaseClient } from "@supabase/supabase-js";

import { es_cantidad_valida } from "../domain/cantidades";
import { obtenerClienteSupabase } from "./supabase";

export type FormaVentaStock = "unidad" | "peso";
export type TipoUbicacion = "deposito" | "cuarentena" | "camion";

export interface UbicacionStock {
  id: string;
  tipo: TipoUbicacion;
  camionId: string | null;
}

export interface ProductoStock {
  id: string;
  codigo: string | null;
  nombre: string;
  formaVenta: FormaVentaStock;
  // En unidad mínima: unidades enteras o gramos enteros.
  stockMinimo: number;
  activo: boolean;
}

export interface SaldoStock {
  ubicacionId: string;
  productoId: string;
  // Suma de movimientos en unidad mínima (entero seguro).
  cantidad: number;
}

export interface DatosStock {
  depositoId: string;
  cuarentenaId: string;
  ubicaciones: UbicacionStock[];
  productos: ProductoStock[];
  saldos: SaldoStock[];
}

// Códigos de merma: lista literal de Blueprint §7.7 (constraint
// movimientos_stock_motivo_codigo_valido).
export const MOTIVOS_MERMA = [
  "vencido",
  "roto_danado",
  "mal_estado",
  "error_pedido",
  "cambio",
  "otro",
] as const;
export type MotivoMerma = (typeof MOTIVOS_MERMA)[number];

export type IntentoStock =
  | {
      tipo: "ingreso";
      productoId: string;
      cantidad: number;
      motivo: string | null;
    }
  | {
      tipo: "cuarentena";
      productoId: string;
      origenId: string;
      cantidad: number;
      motivo: string;
    }
  | {
      tipo: "merma";
      productoId: string;
      origenId: string;
      cantidad: number;
      motivoCodigo: MotivoMerma;
      motivo: string | null;
    };

// `incierto`: el servidor pudo haber registrado la operación aunque no se
// recibió la respuesta (red, timeout). Se reintenta con la misma clave.
export type ResultadoStock<T> =
  | { ok: true; datos: T }
  | { ok: false; error: string; incierto?: true };

export interface PuertoStock {
  leer(): Promise<ResultadoStock<DatosStock>>;
  ejecutar(
    intento: IntentoStock,
    claveIdempotencia: string
  ): Promise<ResultadoStock<string>>;
}

// Máximo de `p_cantidad integer` (PostgreSQL).
export const CANTIDAD_MAXIMA = 2147483647;

export const MENSAJE_ERROR_LECTURA =
  "No se pudo leer el stock. Intentá de nuevo.";
export const MENSAJE_ERROR_GENERICO =
  "No se pudo registrar la operación. Intentá de nuevo.";
// Fallo de red o respuesta inesperada: el resultado es desconocido. Reintentar
// con los mismos datos reutiliza la misma clave y no duplica (P12) SÓLO mientras
// no se recargue ni se cierre la página: la clave vive en memoria. Después de
// recargar hay que revisar el stock antes de volver a cargar la operación.
export const MENSAJE_RESULTADO_DESCONOCIDO =
  "No se pudo confirmar la operación: puede haberse registrado. Reintentá con los mismos datos sin recargar la página (no se registra dos veces). Si ya recargaste, revisá el stock antes de volver a cargarla.";
export const MENSAJE_SIN_UBICACIONES =
  "La empresa no tiene configurados el depósito y la cuarentena.";

// P13-stock: agotados los intentos ante 40001/40P01. PostgreSQL revierte toda
// la transacción en esos casos: no quedó ningún efecto.
export const MENSAJE_CONCURRENCIA_AGOTADA =
  "El sistema estaba ocupado y la operación no se registró después de varios intentos. Esperá un momento y reintentá.";

const MENSAJE_SIN_PERMISO =
  "No tenés permiso para registrar movimientos de stock.";

const MENSAJES_ERROR: Record<string, string> = {
  stock_no_autenticado: "Tu sesión no es válida. Volvé a iniciar sesión.",
  stock_no_autorizado: MENSAJE_SIN_PERMISO,
  stock_clave_invalida: MENSAJE_ERROR_GENERICO,
  stock_cantidad_invalida: "La cantidad debe ser mayor que cero.",
  stock_motivo_invalido: "El motivo no es válido.",
  stock_origen_invalido:
    "El origen no es válido: sólo se puede mover desde el depósito.",
  stock_producto_no_encontrado:
    "El producto ya no existe o no pertenece a tu empresa.",
  stock_ubicacion_no_encontrada:
    "La ubicación no existe o no pertenece a tu empresa.",
  stock_conflicto_idempotencia:
    "Esta operación ya se registró con otros datos. Revisá el stock antes de volver a cargarla.",
  stock_insuficiente: "No hay stock suficiente en el depósito.",
  stock_producto_inactivo: "El producto está dado de baja.",
  stock_ubicacion_no_configurada: MENSAJE_SIN_UBICACIONES,
  stock_error_interno: MENSAJE_ERROR_GENERICO,
};

// Máximo de intentos de una operación (ADR-001 §18.3, P13-stock: «máximo 3»).
// Se toma como 3 intentos en total (1 inicial + 2 reintentos): cumple la regla
// con cualquiera de sus dos lecturas. La ADR no define espera entre intentos y
// no se agrega una.
export const MAX_INTENTOS = 3;

export type ClaseErrorStock =
  // 40001 / 40P01: PostgreSQL revirtió la transacción; sin efectos. Reintentable.
  | "concurrencia"
  // Sin respuesta del servidor (red, timeout, respuesta que no es de PostgREST):
  // resultado desconocido. Reintentable con la misma clave y el mismo payload.
  | "desconocido"
  // PTxyz / códigos `stock_*`: error de negocio. Nunca se reintenta.
  | "negocio"
  | "sin_permiso"
  // Todo lo demás, incluidos 55P03 y 57014: la ADR sólo los admite bajo
  // condiciones que este contrato no cumple (ver abajo). No se reintentan solos.
  | "otro";

/**
 * Clasifica un error de supabase-js según P13-stock.
 *  - `40001`, `40P01`: reintentables.
 *  - sin `code` (supabase-js devuelve `code` vacío ante un fallo de red): conexión
 *    perdida o timeout con resultado desconocido, reintentable.
 *  - `55P03`: sólo «si proviene de la política explícita de locks». Las RPC de
 *    stock usan `pg_advisory_xact_lock` sin `lock_timeout`/`NOWAIT`: no hay tal
 *    política, así que no se reintenta.
 *  - `57014`: sólo «si es un timeout o cancelación recuperable». El cliente no
 *    puede distinguirlo con el contrato vigente: no se reintenta.
 *  - `PTxyz` y los códigos `stock_*`: nunca.
 */
export function clasificarErrorStock(error: unknown): ClaseErrorStock {
  if (error === null || typeof error !== "object") return "otro";
  const { code, message } = error as { code?: unknown; message?: unknown };

  if (typeof message === "string" && Object.hasOwn(MENSAJES_ERROR, message)) {
    return message === "stock_no_autorizado" || message === "stock_no_autenticado"
      ? "sin_permiso"
      : "negocio";
  }
  if (typeof code === "string" && /^PT\d{3}$/.test(code)) return "negocio";
  if (code === "42501") return "sin_permiso";
  if (code === "40001" || code === "40P01") return "concurrencia";
  if (code === "" || code === undefined || code === null) return "desconocido";
  return "otro";
}

export const esReintentable = (clase: ClaseErrorStock): boolean =>
  clase === "concurrencia" || clase === "desconocido";

/**
 * Traduce un error de Supabase a un mensaje seguro. Sólo se usa el `message`
 * cuando es un código conocido; cualquier otra cosa se reemplaza por un
 * mensaje genérico.
 */
export function mensajeErrorStock(error: unknown): string {
  if (error !== null && typeof error === "object") {
    const { message } = error as { message?: unknown };
    if (typeof message === "string" && Object.hasOwn(MENSAJES_ERROR, message)) {
      return MENSAJES_ERROR[message];
    }
  }

  switch (clasificarErrorStock(error)) {
    case "sin_permiso":
      return MENSAJE_SIN_PERMISO;
    case "concurrencia":
      return MENSAJE_CONCURRENCIA_AGOTADA;
    case "desconocido":
      return MENSAJE_RESULTADO_DESCONOCIDO;
    default:
      return MENSAJE_ERROR_GENERICO;
  }
}

function textoNoVacio(valor: unknown): valor is string {
  return typeof valor === "string" && valor !== "";
}

export function filaAUbicacion(fila: unknown): UbicacionStock | null {
  if (fila === null || typeof fila !== "object") return null;
  const f = fila as Record<string, unknown>;
  const tipo =
    f.tipo === "deposito" || f.tipo === "cuarentena" || f.tipo === "camion"
      ? f.tipo
      : undefined;

  if (!textoNoVacio(f.id) || tipo === undefined) return null;
  // camion ↔ camion_id (constraint ubicaciones_camion_coherente).
  if (tipo === "camion" ? !textoNoVacio(f.camion_id) : f.camion_id !== null) {
    return null;
  }

  return { id: f.id, tipo, camionId: tipo === "camion" ? (f.camion_id as string) : null };
}

export function filaAProductoStock(fila: unknown): ProductoStock | null {
  if (fila === null || typeof fila !== "object") return null;
  const f = fila as Record<string, unknown>;
  const formaVenta =
    f.forma_venta === "unidad" || f.forma_venta === "peso"
      ? f.forma_venta
      : undefined;

  if (
    !textoNoVacio(f.id) ||
    !(f.codigo === null || typeof f.codigo === "string") ||
    typeof f.nombre !== "string" ||
    formaVenta === undefined ||
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
    formaVenta,
    stockMinimo: f.stock_minimo,
    activo: f.activo,
  };
}

export function filaASaldo(fila: unknown): SaldoStock | null {
  if (fila === null || typeof fila !== "object") return null;
  const f = fila as Record<string, unknown>;

  // `cantidad` es bigint: se exige un entero seguro. Un saldo negativo no
  // debería existir (las RPC lo impiden); si apareciera se muestra tal cual,
  // sin corregirlo en el frontend.
  if (
    !textoNoVacio(f.ubicacion_id) ||
    !textoNoVacio(f.producto_id) ||
    typeof f.cantidad !== "number" ||
    !Number.isSafeInteger(f.cantidad)
  ) {
    return null;
  }

  return {
    ubicacionId: f.ubicacion_id,
    productoId: f.producto_id,
    cantidad: f.cantidad,
  };
}

function convertirTodas<T>(
  filas: unknown,
  convertir: (fila: unknown) => T | null
): T[] | null {
  if (!Array.isArray(filas)) return null;
  const resultado = filas.map(convertir);
  // Una sola fila inesperada invalida la lectura completa (falla cerrado).
  return resultado.some((r) => r === null) ? null : (resultado as T[]);
}

/**
 * Arma los datos de stock. Falla cerrado: filas inválidas, ubicaciones
 * internas faltantes o duplicadas, o saldos que referencian ubicaciones o
 * productos desconocidos invalidan toda la lectura.
 */
export function armarDatosStock(entrada: {
  ubicaciones: unknown;
  productos: unknown;
  saldos: unknown;
}): ResultadoStock<DatosStock> {
  const ubicaciones = convertirTodas(entrada.ubicaciones, filaAUbicacion);
  const productos = convertirTodas(entrada.productos, filaAProductoStock);
  const saldos = convertirTodas(entrada.saldos, filaASaldo);

  if (!ubicaciones || !productos || !saldos) {
    return { ok: false, error: MENSAJE_ERROR_LECTURA };
  }

  const depositos = ubicaciones.filter((u) => u.tipo === "deposito");
  const cuarentenas = ubicaciones.filter((u) => u.tipo === "cuarentena");
  if (depositos.length !== 1 || cuarentenas.length !== 1) {
    return { ok: false, error: MENSAJE_SIN_UBICACIONES };
  }

  const idsUbicacion = new Set(ubicaciones.map((u) => u.id));
  const idsProducto = new Set(productos.map((p) => p.id));
  if (
    saldos.some(
      (s) => !idsUbicacion.has(s.ubicacionId) || !idsProducto.has(s.productoId)
    )
  ) {
    return { ok: false, error: MENSAJE_ERROR_LECTURA };
  }

  return {
    ok: true,
    datos: {
      depositoId: depositos[0].id,
      cuarentenaId: cuarentenas[0].id,
      ubicaciones,
      productos,
      saldos,
    },
  };
}

export function crearPuertoStock(cliente: SupabaseClient): PuertoStock {
  return {
    async leer() {
      try {
        const [u, p, s] = await Promise.all([
          cliente.from("ubicaciones").select("id, tipo, camion_id"),
          cliente
            .from("productos")
            .select("id, codigo, nombre, forma_venta, stock_minimo, activo"),
          cliente
            .from("stock_actual")
            .select("ubicacion_id, producto_id, cantidad"),
        ]);

        if (u.error || p.error || s.error) {
          return { ok: false, error: MENSAJE_ERROR_LECTURA };
        }

        return armarDatosStock({
          ubicaciones: u.data,
          productos: p.data,
          saldos: s.data,
        });
      } catch {
        return { ok: false, error: MENSAJE_ERROR_LECTURA };
      }
    },

    async ejecutar(intento, claveIdempotencia) {
      // Una sola clave y un solo payload para todos los intentos (P12/P13).
      const llamar = () =>
        intento.tipo === "ingreso"
          ? cliente.rpc("registrar_ingreso", {
              p_idempotency_key: claveIdempotencia,
              p_producto_id: intento.productoId,
              p_cantidad: intento.cantidad,
              p_motivo: intento.motivo,
            })
          : intento.tipo === "cuarentena"
            ? cliente.rpc("mover_a_cuarentena", {
                p_idempotency_key: claveIdempotencia,
                p_producto_id: intento.productoId,
                p_ubicacion_origen_id: intento.origenId,
                p_cantidad: intento.cantidad,
                p_motivo: intento.motivo,
              })
            : cliente.rpc("registrar_merma", {
                p_idempotency_key: claveIdempotencia,
                p_producto_id: intento.productoId,
                p_ubicacion_origen_id: intento.origenId,
                p_cantidad: intento.cantidad,
                p_motivo_codigo: intento.motivoCodigo,
                p_motivo: intento.motivo,
              });

      let ultimoError: unknown = null;

      for (let n = 1; n <= MAX_INTENTOS; n++) {
        let respuesta: { data: unknown; error: unknown };
        try {
          respuesta = await llamar();
        } catch (e) {
          // Excepción de red: se trata como error sin código.
          respuesta = { data: null, error: { message: String(e), code: "" } };
        }

        if (!respuesta.error) {
          if (!textoNoVacio(respuesta.data)) {
            return { ok: false, error: MENSAJE_RESULTADO_DESCONOCIDO, incierto: true };
          }
          return { ok: true, datos: respuesta.data };
        }

        ultimoError = respuesta.error;
        if (!esReintentable(clasificarErrorStock(ultimoError))) break;
      }

      const clase = clasificarErrorStock(ultimoError);
      return {
        ok: false,
        error: mensajeErrorStock(ultimoError),
        ...(clase === "desconocido" ? { incierto: true as const } : {}),
      };
    },
  };
}

let puerto: PuertoStock | null = null;

export function obtenerPuertoStock(): PuertoStock {
  if (!puerto) puerto = crearPuertoStock(obtenerClienteSupabase());
  return puerto;
}
