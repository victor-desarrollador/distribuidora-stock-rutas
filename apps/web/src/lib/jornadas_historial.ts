// Historial de cargas y descargas de una jornada (B-02b.2 / S3-0): SÓLO
// LECTURA. Blueprint §7.2 y §7.5 (movimientos `carga` y `descarga` con
// `jornada_id`), ADR-007 §2.5, §2.6 y §2.8, ADR-005 (unidad mínima: unidades o
// gramos enteros) y ADR-001 §18.4.1.
//
// Lecturas con RLS vigente, sin ampliar permisos:
//   - `jornadas` (la fila de la jornada, con su empresa y su camión);
//   - `ubicaciones` (el depósito y la ubicación del camión de la jornada);
//   - `operaciones` y `movimientos_stock` con `jornada_id` (políticas
//     `*_select_empresa`: sólo dueño o encargado activo de la empresa);
//   - `productos` de los movimientos (nombre y forma de venta).
// No se lee `perfiles`: sólo el perfil propio es legible (D-B2-1), así que el
// actor se identifica por su id y la pantalla dice «vos» cuando coincide.
//
// Este módulo no escribe: nunca usa RPC ni insert/update/upsert/delete, no
// genera claves de idempotencia y no guarda nada en el navegador.
//
// Falla cerrada: una respuesta con error, truncada (conteo exacto distinto de
// las filas recibidas), fuera de orden, repetida o inconsistente con las reglas
// de la jornada invalida TODO el historial. Nunca se muestra uno parcial.
//
// Paginación por keyset sobre `id` ascendente (clave primaria: orden total). Se
// piden tamaño + 1 filas con conteo exacto, como en lib/jornadas.ts. Sin
// consistencia transaccional entre páginas: una operación registrada mientras
// se lee puede no aparecer hasta la próxima lectura (foto aproximada); las
// garantías de stock las da la base, no esta lectura.

import type { SupabaseClient } from "@supabase/supabase-js";

import { CANTIDAD_MAXIMA, esUuid } from "./jornadas";
import { obtenerClienteSupabase } from "./supabase";

export type TipoOperacionHistorial = "carga" | "descarga";
export type FormaVentaHistorial = "unidad" | "peso";

export interface ProductoHistorial {
  id: string;
  codigo: string | null;
  nombre: string;
  formaVenta: FormaVentaHistorial;
  activo: boolean;
}

export interface LineaHistorial {
  movimientoId: string;
  productoId: string;
  // Unidad mínima: unidades enteras o gramos enteros (ADR-005).
  cantidad: number;
}

export interface OperacionHistorial {
  id: string;
  tipo: TipoOperacionHistorial;
  actorId: string;
  // Instante del servidor (ISO 8601).
  creadoEn: string;
  // Sólo descarga (obligatorio); null en carga.
  motivo: string | null;
  lineas: LineaHistorial[];
}

export interface HistorialJornada {
  jornadaId: string;
  // Orden cronológico (creado_en asc, id asc).
  operaciones: OperacionHistorial[];
  // Productos de todas las líneas, por id.
  productos: Readonly<Record<string, ProductoHistorial>>;
}

export type ResultadoHistorial =
  | { ok: true; datos: HistorialJornada }
  | { ok: false; error: string };

export interface PuertoHistorialJornada {
  leerHistorial(jornadaId: string): Promise<ResultadoHistorial>;
}

export const MENSAJE_ERROR_HISTORIAL =
  "No se pudo leer el historial de cargas y descargas. Intentá de nuevo.";
export const MENSAJE_JORNADA_NO_VISIBLE =
  "La jornada no existe o no pertenece a tu empresa.";

export const TAMANO_PAGINA_OPERACIONES = 200;
export const TAMANO_PAGINA_MOVIMIENTOS = 500;
// Tope de páginas por tabla: más allá, se falla cerrado en lugar de seguir.
export const MAX_PAGINAS_HISTORIAL = 50;
// Ids por consulta de productos (`in`): acota el largo de la URL.
export const TAMANO_LOTE_PRODUCTOS = 100;

const COLUMNAS_OPERACION = "id, empresa_id, tipo, actor_id, jornada_id, creado_en";
const COLUMNAS_MOVIMIENTO =
  "id, empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id, motivo";
const COLUMNAS_PRODUCTO = "id, empresa_id, codigo, nombre, forma_venta, activo";
const TIPOS: readonly TipoOperacionHistorial[] = ["carga", "descarga"];

// Señal interna de falla cerrada: nunca sale del módulo.
class LecturaInvalida extends Error {}

function invalida(): never {
  throw new LecturaInvalida();
}

const mismoId = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();

function esTipo(valor: unknown): valor is TipoOperacionHistorial {
  return valor === "carga" || valor === "descarga";
}

function esCantidad(valor: unknown): valor is number {
  return (
    typeof valor === "number" &&
    Number.isSafeInteger(valor) &&
    valor >= 1 &&
    valor <= CANTIDAD_MAXIMA
  );
}

function esInstante(valor: unknown): valor is string {
  return typeof valor === "string" && valor !== "" && !Number.isNaN(Date.parse(valor));
}

/**
 * Comprueba el tamaño de una respuesta con conteo exacto: deben venir
 * min(pedidas, conteo) filas. Menos filas indica truncamiento (max_rows).
 */
function filasConfiables(data: unknown, count: unknown, pedidas: number): unknown[] {
  if (!Array.isArray(data)) invalida();
  if (
    typeof count !== "number" ||
    !Number.isSafeInteger(count) ||
    count < data.length ||
    data.length !== Math.min(pedidas, count)
  ) {
    invalida();
  }
  return data;
}

interface Contexto {
  jornadaId: string;
  empresaId: string;
  depositoId: string;
  camionUbicacionId: string;
}

interface FilaOperacion {
  id: string;
  tipo: TipoOperacionHistorial;
  actorId: string;
  creadoEn: string;
}

interface FilaMovimiento {
  id: string;
  operacionId: string;
  tipo: TipoOperacionHistorial;
  productoId: string;
  cantidad: number;
  origenId: string;
  destinoId: string;
  actorId: string;
  motivo: string | null;
}

export function filaAOperacion(fila: unknown, ctx: Contexto): FilaOperacion | null {
  if (fila === null || typeof fila !== "object") return null;
  const f = fila as Record<string, unknown>;
  if (
    !esUuid(f.id) ||
    !esUuid(f.empresa_id) ||
    !mismoId(f.empresa_id, ctx.empresaId) ||
    !esTipo(f.tipo) ||
    !esUuid(f.actor_id) ||
    !esUuid(f.jornada_id) ||
    !mismoId(f.jornada_id, ctx.jornadaId) ||
    !esInstante(f.creado_en)
  ) {
    return null;
  }
  return { id: f.id, tipo: f.tipo, actorId: f.actor_id, creadoEn: f.creado_en };
}

export function filaAMovimiento(fila: unknown, ctx: Contexto): FilaMovimiento | null {
  if (fila === null || typeof fila !== "object") return null;
  const f = fila as Record<string, unknown>;
  if (
    !esUuid(f.id) ||
    !esUuid(f.empresa_id) ||
    !mismoId(f.empresa_id, ctx.empresaId) ||
    !esUuid(f.operacion_id) ||
    !esTipo(f.tipo_movimiento) ||
    !esUuid(f.producto_id) ||
    !esCantidad(f.cantidad) ||
    !esUuid(f.ubicacion_origen_id) ||
    !esUuid(f.ubicacion_destino_id) ||
    !esUuid(f.actor_id) ||
    !esUuid(f.jornada_id) ||
    !mismoId(f.jornada_id, ctx.jornadaId)
  ) {
    return null;
  }

  // Sentido del movimiento (ADR-007 §2.5 y §2.6): carga depósito → camión de
  // la jornada; descarga camión → depósito.
  const [origen, destino] =
    f.tipo_movimiento === "carga"
      ? [ctx.depositoId, ctx.camionUbicacionId]
      : [ctx.camionUbicacionId, ctx.depositoId];
  if (!mismoId(f.ubicacion_origen_id, origen) || !mismoId(f.ubicacion_destino_id, destino)) {
    return null;
  }

  // Motivo: la carga no lleva; la descarga lo exige (constraint
  // movimientos_stock_motivo_por_tipo; texto ya normalizado por la base).
  let motivo: string | null;
  if (f.tipo_movimiento === "carga") {
    if (f.motivo !== null) return null;
    motivo = null;
  } else {
    if (typeof f.motivo !== "string" || f.motivo.trim() === "") return null;
    motivo = f.motivo;
  }

  return {
    id: f.id,
    operacionId: f.operacion_id,
    tipo: f.tipo_movimiento,
    productoId: f.producto_id,
    cantidad: f.cantidad,
    origenId: f.ubicacion_origen_id,
    destinoId: f.ubicacion_destino_id,
    actorId: f.actor_id,
    motivo,
  };
}

export function filaAProductoHistorial(
  fila: unknown,
  empresaId: string
): ProductoHistorial | null {
  if (fila === null || typeof fila !== "object") return null;
  const f = fila as Record<string, unknown>;
  const formaVenta =
    f.forma_venta === "unidad" || f.forma_venta === "peso" ? f.forma_venta : undefined;
  if (
    !esUuid(f.id) ||
    !esUuid(f.empresa_id) ||
    !mismoId(f.empresa_id, empresaId) ||
    !(f.codigo === null || typeof f.codigo === "string") ||
    typeof f.nombre !== "string" ||
    f.nombre.trim() === "" ||
    formaVenta === undefined ||
    typeof f.activo !== "boolean"
  ) {
    return null;
  }
  return { id: f.id, codigo: f.codigo, nombre: f.nombre, formaVenta, activo: f.activo };
}

/**
 * Arma el historial a partir de filas ya validadas una por una. Exige
 * coherencia entre operaciones y movimientos (cada movimiento pertenece a una
 * operación leída, del mismo tipo y actor; cada operación tiene al menos una
 * línea; una línea por producto; motivo único por descarga) y que todos los
 * productos estén presentes. Cualquier incoherencia → null (falla cerrada).
 */
export function armarHistorial(
  jornadaId: string,
  operaciones: FilaOperacion[],
  movimientos: FilaMovimiento[],
  productos: ProductoHistorial[]
): HistorialJornada | null {
  const porId = new Map<string, OperacionHistorial>();
  for (const o of operaciones) {
    const clave = o.id.toLowerCase();
    if (porId.has(clave)) return null;
    porId.set(clave, {
      id: o.id,
      tipo: o.tipo,
      actorId: o.actorId,
      creadoEn: o.creadoEn,
      motivo: null,
      lineas: [],
    });
  }

  const movimientosVistos = new Set<string>();
  for (const m of movimientos) {
    const claveMov = m.id.toLowerCase();
    if (movimientosVistos.has(claveMov)) return null;
    movimientosVistos.add(claveMov);

    const op = porId.get(m.operacionId.toLowerCase());
    if (!op || op.tipo !== m.tipo || !mismoId(op.actorId, m.actorId)) return null;
    if (op.lineas.some((l) => mismoId(l.productoId, m.productoId))) return null;
    if (op.lineas.length === 0) {
      op.motivo = m.motivo;
    } else if (op.motivo !== m.motivo) {
      return null;
    }
    op.lineas.push({ movimientoId: m.id, productoId: m.productoId, cantidad: m.cantidad });
  }

  const resultado = [...porId.values()];
  if (resultado.some((o) => o.lineas.length === 0)) return null;

  const mapa: Record<string, ProductoHistorial> = {};
  for (const p of productos) {
    const clave = p.id.toLowerCase();
    if (Object.hasOwn(mapa, clave)) return null;
    mapa[clave] = p;
  }
  for (const o of resultado) {
    for (const l of o.lineas) {
      if (!Object.hasOwn(mapa, l.productoId.toLowerCase())) return null;
    }
    // Orden estable de las líneas: por nombre de producto y luego id.
    o.lineas.sort((a, b) => {
      const pa = mapa[a.productoId.toLowerCase()];
      const pb = mapa[b.productoId.toLowerCase()];
      return (
        pa.nombre.localeCompare(pb.nombre, "es-AR") ||
        a.productoId.toLowerCase().localeCompare(b.productoId.toLowerCase())
      );
    });
  }

  resultado.sort(
    (a, b) =>
      Date.parse(a.creadoEn) - Date.parse(b.creadoEn) ||
      (a.id.toLowerCase() < b.id.toLowerCase() ? -1 : a.id.toLowerCase() > b.id.toLowerCase() ? 1 : 0)
  );

  return { jornadaId, operaciones: resultado, productos: mapa };
}

export function crearPuertoHistorialJornada(cliente: SupabaseClient): PuertoHistorialJornada {
  async function leerContexto(jornadaId: string): Promise<Contexto | "no_visible"> {
    // La jornada: exactamente una fila visible por RLS.
    const rj = await cliente
      .from("jornadas")
      .select("id, empresa_id, camion_id", { count: "exact" })
      .eq("id", jornadaId)
      .limit(2);
    if (rj.error) invalida();
    const filasJ = filasConfiables(rj.data, rj.count, 2);
    if (filasJ.length === 0) return "no_visible";
    if (filasJ.length !== 1) invalida();
    const j = filasJ[0] as Record<string, unknown>;
    if (
      j === null ||
      typeof j !== "object" ||
      !esUuid(j.id) ||
      !mismoId(j.id, jornadaId) ||
      !esUuid(j.empresa_id) ||
      !esUuid(j.camion_id)
    ) {
      invalida();
    }
    const empresaId = j.empresa_id;
    const camionId = j.camion_id;

    // El depósito y la ubicación del camión de la jornada (camion_id ya
    // validado como uuid: sin inyección en el filtro).
    const ru = await cliente
      .from("ubicaciones")
      .select("id, empresa_id, tipo, camion_id", { count: "exact" })
      .or(`tipo.eq.deposito,camion_id.eq.${camionId}`)
      .order("id", { ascending: true })
      .limit(3);
    if (ru.error) invalida();
    const filasU = filasConfiables(ru.data, ru.count, 3);
    let depositoId: string | null = null;
    let camionUbicacionId: string | null = null;
    for (const fila of filasU) {
      const u = fila as Record<string, unknown>;
      if (
        u === null ||
        typeof u !== "object" ||
        !esUuid(u.id) ||
        !esUuid(u.empresa_id) ||
        !mismoId(u.empresa_id, empresaId)
      ) {
        invalida();
      }
      if (u.tipo === "deposito" && u.camion_id === null) {
        if (depositoId !== null) invalida();
        depositoId = u.id;
      } else if (u.tipo === "camion" && esUuid(u.camion_id) && mismoId(u.camion_id, camionId)) {
        if (camionUbicacionId !== null) invalida();
        camionUbicacionId = u.id;
      } else {
        invalida();
      }
    }
    if (depositoId === null || camionUbicacionId === null) invalida();
    return { jornadaId, empresaId, depositoId, camionUbicacionId };
  }

  /** Recorre todas las páginas de una tabla por keyset de `id` o falla. */
  async function leerPaginado<T>(
    tabla: "operaciones" | "movimientos_stock",
    columnas: string,
    columnaTipo: "tipo" | "tipo_movimiento",
    tamano: number,
    jornadaId: string,
    convertir: (fila: unknown) => T | null,
    idDe: (fila: T) => string
  ): Promise<T[]> {
    const acumuladas: T[] = [];
    let despues: string | null = null;
    for (let pagina = 0; pagina < MAX_PAGINAS_HISTORIAL; pagina++) {
      const pedidas = tamano + 1;
      let consulta = cliente
        .from(tabla)
        .select(columnas, { count: "exact" })
        .eq("jornada_id", jornadaId)
        .in(columnaTipo, [...TIPOS]);
      if (despues !== null) consulta = consulta.gt("id", despues);
      const r = await consulta.order("id", { ascending: true }).limit(pedidas);
      if (r.error) invalida();
      const filas = filasConfiables(r.data, r.count, pedidas).map(convertir);
      if (filas.some((f) => f === null)) invalida();

      // Orden estricto ascendente, posterior al cursor y sin repetidos.
      let previo = despues;
      for (const f of filas as T[]) {
        const id = idDe(f).toLowerCase();
        if (previo !== null && !(id > previo.toLowerCase())) invalida();
        previo = id;
      }

      const hayMas = filas.length > tamano;
      const propias = (hayMas ? filas.slice(0, tamano) : filas) as T[];
      acumuladas.push(...propias);
      if (!hayMas) return acumuladas;
      despues = idDe(propias[propias.length - 1]);
    }
    // Tope de páginas alcanzado: no se devuelve un historial parcial.
    return invalida();
  }

  async function leerProductos(ids: string[], empresaId: string): Promise<ProductoHistorial[]> {
    const resultado: ProductoHistorial[] = [];
    for (let i = 0; i < ids.length; i += TAMANO_LOTE_PRODUCTOS) {
      const lote = ids.slice(i, i + TAMANO_LOTE_PRODUCTOS);
      const pedidas = lote.length + 1;
      const r = await cliente
        .from("productos")
        .select(COLUMNAS_PRODUCTO, { count: "exact" })
        .in("id", lote)
        .order("id", { ascending: true })
        .limit(pedidas);
      if (r.error) invalida();
      const filas = filasConfiables(r.data, r.count, pedidas).map((f) =>
        filaAProductoHistorial(f, empresaId)
      );
      if (filas.some((p) => p === null)) invalida();
      const recibidos = filas as ProductoHistorial[];
      // Exactamente los productos pedidos, una vez cada uno.
      const pedidos = new Set(lote.map((x) => x.toLowerCase()));
      const vistos = new Set<string>();
      for (const p of recibidos) {
        const clave = p.id.toLowerCase();
        if (!pedidos.has(clave) || vistos.has(clave)) invalida();
        vistos.add(clave);
      }
      if (vistos.size !== pedidos.size) invalida();
      resultado.push(...recibidos);
    }
    return resultado;
  }

  return {
    async leerHistorial(jornadaId) {
      if (!esUuid(jornadaId)) return { ok: false, error: MENSAJE_ERROR_HISTORIAL };
      try {
        const ctx = await leerContexto(jornadaId);
        if (ctx === "no_visible") return { ok: false, error: MENSAJE_JORNADA_NO_VISIBLE };

        const operaciones = await leerPaginado(
          "operaciones",
          COLUMNAS_OPERACION,
          "tipo",
          TAMANO_PAGINA_OPERACIONES,
          jornadaId,
          (f) => filaAOperacion(f, ctx),
          (o) => o.id
        );
        const movimientos = await leerPaginado(
          "movimientos_stock",
          COLUMNAS_MOVIMIENTO,
          "tipo_movimiento",
          TAMANO_PAGINA_MOVIMIENTOS,
          jornadaId,
          (f) => filaAMovimiento(f, ctx),
          (m) => m.id
        );

        const ids = [...new Set(movimientos.map((m) => m.productoId.toLowerCase()))].sort();
        const productos = await leerProductos(ids, ctx.empresaId);

        const historial = armarHistorial(jornadaId, operaciones, movimientos, productos);
        return historial === null
          ? { ok: false, error: MENSAJE_ERROR_HISTORIAL }
          : { ok: true, datos: historial };
      } catch {
        // LecturaInvalida, error de red o excepción del cliente: falla cerrada
        // con un mensaje seguro (nunca el detalle de SQL ni de PostgREST).
        return { ok: false, error: MENSAJE_ERROR_HISTORIAL };
      }
    },
  };
}

let puerto: PuertoHistorialJornada | null = null;

export function obtenerPuertoHistorialJornada(): PuertoHistorialJornada {
  if (!puerto) puerto = crearPuertoHistorialJornada(obtenerClienteSupabase());
  return puerto;
}
