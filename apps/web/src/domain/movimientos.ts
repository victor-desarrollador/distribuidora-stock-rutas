// Dominio puro de movimientos de reparto (merma, devolución, cambio) del
// prototipo. Sin React, sin persistencia, sin Supabase ni RPC.
//
// Fuente: BLUEPRINT.md §7.1 y §7.4 (cantidades enteras en la unidad mínima;
// ADR-005).
//
// No reimplementa conversiones: usa domain/cantidades.ts (unidad) y
// domain/peso.ts (kg → gramos). La cantidad persistida de un movimiento es
// siempre un entero canónico: unidades enteras para "unidad", gramos para
// "peso" (B2). Un cambio entre unidades canónicas distintas (unidad ↔ peso)
// no tiene semántica aprobada y es inválido.

import type {
  MovimientoReparto,
  ProductoMovimiento,
} from "../data/mockMovimientos";
import { salidasPorMovimiento } from "../data/mockMovimientos";
import type { UnidadMedida } from "../data/mockProductos";
import {
  cantidad_unidad_desde_texto,
  es_cantidad_valida,
  sumar_cantidades_seguras,
  validar_cantidad,
} from "./cantidades";
import { kg_a_gramos } from "./peso";

/**
 * Entrada de UI de una cantidad: texto del input. "unidad": entero.
 * "peso": kg con coma decimal y hasta 3 decimales.
 */
export interface EntradaCantidad {
  texto: string;
}

/**
 * Convierte la entrada de UI en la cantidad canónica de un movimiento, o null
 * si es inválida. Un movimiento exige una cantidad estrictamente positiva:
 * vacío, 0, negativos, NaN e Infinity devuelven null (no se redondea ni
 * trunca).
 *   - "unidad": entero (decimales → null).
 *   - "peso": kg con coma y hasta 3 decimales, a gramos con kg_a_gramos (sin
 *     punto flotante). Más de 3 decimales, punto decimal o fuera del rango
 *     seguro → null.
 */
export function cantidad_movimiento_desde_entrada(
  unidad: UnidadMedida,
  entrada: EntradaCantidad
): number | null {
  let canonica: number | null;
  if (unidad === "unidad") {
    canonica = cantidad_unidad_desde_texto(entrada.texto);
  } else if (unidad === "peso") {
    canonica = kg_a_gramos(entrada.texto);
  } else {
    return null;
  }

  if (canonica === null) return null;

  return canonica > 0 ? canonica : null;
}

export const MENSAJE_CAMBIO_MIXTO_NO_HABILITADO =
  "Un cambio entre un producto por unidad y uno por peso no está habilitado.";

/**
 * Cambio entre productos de distinta unidad canónica (unidad ↔ peso). No tiene
 * semántica aprobada (B2): falla cerrado. No se convierte entre unidades.
 */
export function es_cambio_mixto(
  devuelto: Pick<ProductoMovimiento, "unidadMedida">,
  entregado: Pick<ProductoMovimiento, "unidadMedida">
): boolean {
  return devuelto.unidadMedida !== entregado.unidadMedida;
}

/**
 * Item de movimiento válido en storage: `unidad` o `peso` (gramos) y cantidad
 * entera > 0. `pieza` y cualquier otra unidad se rechazan.
 */
export function producto_movimiento_valido(
  p: unknown
): p is ProductoMovimiento {
  if (typeof p !== "object" || p === null) return false;
  const { productoId, nombreProducto, unidadMedida, cantidad } =
    p as Partial<ProductoMovimiento>;

  return (
    Number.isSafeInteger(productoId) &&
    typeof nombreProducto === "string" &&
    (unidadMedida === "unidad" || unidadMedida === "peso") &&
    typeof cantidad === "number" &&
    es_cantidad_valida(cantidad) &&
    cantidad > 0
  );
}

/**
 * Validación estructural y de cantidades de un movimiento. La usan la lectura
 * de localStorage y la escritura (misma regla en ambos bordes: falla cerrado).
 */
export function movimiento_valido(m: unknown): m is MovimientoReparto {
  if (typeof m !== "object" || m === null) return false;
  const mov = m as Record<string, unknown>;

  const baseValida =
    typeof mov.id === "string" &&
    typeof mov.jornadaId === "string" &&
    Number.isSafeInteger(mov.camionId) &&
    typeof mov.fecha === "string" &&
    typeof mov.motivo === "string";

  if (!baseValida) return false;

  if (mov.tipo === "merma") {
    return (
      mov.clienteId === null &&
      mov.nombreCliente === null &&
      producto_movimiento_valido(mov.producto)
    );
  }

  const clienteValido =
    Number.isSafeInteger(mov.clienteId) &&
    typeof mov.nombreCliente === "string";

  if (!clienteValido) return false;

  if (mov.tipo === "devolucion") {
    return producto_movimiento_valido(mov.producto);
  }

  if (mov.tipo === "cambio") {
    // Cada lado con su propia cantidad canónica; ambos de la misma unidad.
    return (
      producto_movimiento_valido(mov.productoDevuelto) &&
      producto_movimiento_valido(mov.productoEntregado) &&
      !es_cambio_mixto(mov.productoDevuelto, mov.productoEntregado)
    );
  }

  return false;
}

interface VentaConItems {
  jornadaId: string;
  items: ReadonlyArray<{ productoId: number; cantidad: number }>;
}

interface ItemCargado {
  productoId: number;
  cantidad: number;
}

/** Ítem cargado con su unidad: lo exige la validación de una operación nueva. */
interface ItemCargadoConUnidad extends ItemCargado {
  unidadMedida: UnidadMedida;
}

/** Venta con la unidad de cada ítem: la exige la validación de una operación nueva. */
interface VentaConItemsConUnidad {
  jornadaId: string;
  items: ReadonlyArray<{
    productoId: number;
    unidadMedida: UnidadMedida;
    cantidad: number;
  }>;
}

export const MENSAJE_STOCK_JORNADA_NO_CALCULABLE =
  "No se puede calcular el stock disponible: hay cantidades inválidas o fuera del rango seguro.";

export const MENSAJE_SALIDAS_SUPERAN_CARGA =
  "Las salidas registradas en la jornada superan lo cargado: hay datos inconsistentes. No se puede registrar el movimiento.";

function acumular(
  resultado: Record<number, number>,
  producto_id: number,
  cantidad: number
): void {
  // Suma exacta o error: nunca satura, redondea ni aproxima.
  resultado[producto_id] = sumar_cantidades_seguras(
    resultado[producto_id] ?? 0,
    cantidad
  );
}

/**
 * Cantidades de la jornada que dejaron de estar disponibles: ventas más
 * salidas de movimientos (merma y producto entregado en un cambio; la
 * devolución no descuenta). Todo en cantidades canónicas.
 *
 * Lanza Error si alguna cantidad es inválida o si una acumulación supera
 * Number.MAX_SAFE_INTEGER. Los consumidores de UI y de escritura deben usar
 * `disponibilidad_de_jornada`, que convierte ese error en un resultado.
 */
export function salidas_de_jornada(
  jornada_id: string,
  ventas: ReadonlyArray<VentaConItems>,
  movimientos: ReadonlyArray<MovimientoReparto>
): Record<number, number> {
  const resultado: Record<number, number> = {};

  for (const venta of ventas) {
    if (venta.jornadaId !== jornada_id) continue;
    for (const item of venta.items) {
      acumular(resultado, item.productoId, item.cantidad);
    }
  }

  for (const movimiento of movimientos) {
    if (movimiento.jornadaId !== jornada_id) continue;
    for (const item of salidasPorMovimiento(movimiento)) {
      acumular(resultado, item.productoId, item.cantidad);
    }
  }

  return resultado;
}

/**
 * Disponible por producto = cargado - salidas, nunca negativo. Sólo para
 * PRESENTACIÓN: el Math.max no se usa para autorizar operaciones (ver
 * validar_stock_movimiento, que falla cerrado si las salidas superan lo
 * cargado). Lanza Error si lo cargado no es una cantidad canónica válida.
 */
export function disponibles_de_jornada(
  cargados: ReadonlyArray<ItemCargado>,
  salidas: Readonly<Record<number, number>>
): Record<number, number> {
  const resultado: Record<number, number> = {};
  for (const item of cargados) {
    validar_cantidad(item.cantidad);
    const salida = salidas[item.productoId] ?? 0;
    validar_cantidad(salida);
    resultado[item.productoId] = Math.max(0, item.cantidad - salida);
  }
  return resultado;
}

export type DisponibilidadJornada =
  | { ok: true; disponibles: Record<number, number> }
  | { ok: false; error: string };

/**
 * Disponibilidad para la UI. Falla cerrado ante cantidades inválidas o
 * desbordamiento (ok:false, NO un saldo aproximado). La autorización de una
 * operación nueva la hace validar_stock_movimiento.
 */
export function disponibilidad_de_jornada(
  jornada_id: string,
  cargados: ReadonlyArray<ItemCargado>,
  ventas: ReadonlyArray<VentaConItems>,
  movimientos: ReadonlyArray<MovimientoReparto>
): DisponibilidadJornada {
  try {
    const salidas = salidas_de_jornada(jornada_id, ventas, movimientos);
    return { ok: true, disponibles: disponibles_de_jornada(cargados, salidas) };
  } catch {
    return {
      ok: false,
      error: MENSAJE_STOCK_JORNADA_NO_CALCULABLE,
    };
  }
}

/**
 * Validación AUTORITATIVA de una operación nueva (la usa la frontera, con
 * lecturas frescas). Devuelve el mensaje de error o null. No usa la
 * disponibilidad visual (disponibilidad_de_jornada, con Math.max): falla
 * cerrado ante cualquier inconsistencia, sin convertir ni aproximar.
 *   1. Unidad: todo producto del movimiento (merma, devolución, ambos lados
 *      de un cambio) que figure en la carga debe tener su misma unidad.
 *   2. Unidad de las salidas ya registradas en la jornada (ventas, mermas y
 *      entregados de cambios): si un producto cargado salió con otra unidad,
 *      sus cantidades no son sumables (no se convierte) y el ledger es
 *      inconsistente: no se acepta ninguna operación nueva.
 *   3. Cargado y salidas exactos por producto (sumas seguras; overflow o
 *      cantidad no canónica → no calculable).
 *   4. Si las salidas ya registradas de algún producto superan lo cargado
 *      (o salió un producto no cargado), el ledger es inconsistente y no se
 *      acepta ninguna operación nueva en la jornada.
 *   5. Cada salida del movimiento nuevo contra cargado − salidas, exacto y
 *      sin tolerancia (1 g de más se rechaza).
 */
export function validar_stock_movimiento(
  movimiento: MovimientoReparto,
  cargados: ReadonlyArray<ItemCargadoConUnidad>,
  ventas: ReadonlyArray<VentaConItemsConUnidad>,
  movimientos_actuales: ReadonlyArray<MovimientoReparto>
): string | null {
  const productos =
    movimiento.tipo === "cambio"
      ? [movimiento.productoDevuelto, movimiento.productoEntregado]
      : [movimiento.producto];

  for (const producto of productos) {
    if (
      cargados.some(
        (c) =>
          c.productoId === producto.productoId &&
          c.unidadMedida !== producto.unidadMedida
      )
    ) {
      return `La forma de venta de ${producto.nombreProducto} no coincide con la cargada en la jornada.`;
    }
  }

  const salidas_registradas = [
    ...ventas
      .filter((venta) => venta.jornadaId === movimiento.jornadaId)
      .flatMap((venta) => venta.items),
    ...movimientos_actuales
      .filter((m) => m.jornadaId === movimiento.jornadaId)
      .flatMap(salidasPorMovimiento),
  ];

  if (
    salidas_registradas.some((salida) =>
      cargados.some(
        (c) =>
          c.productoId === salida.productoId &&
          c.unidadMedida !== salida.unidadMedida
      )
    )
  ) {
    return MENSAJE_SALIDAS_SUPERAN_CARGA;
  }

  const cargado: Record<number, number> = {};
  let salidas: Record<number, number>;
  try {
    for (const item of cargados) {
      validar_cantidad(item.cantidad);
      acumular(cargado, item.productoId, item.cantidad);
    }
    salidas = salidas_de_jornada(
      movimiento.jornadaId,
      ventas,
      movimientos_actuales
    );
  } catch {
    return MENSAJE_STOCK_JORNADA_NO_CALCULABLE;
  }

  for (const [productoId, salida] of Object.entries(salidas)) {
    if (salida > (cargado[Number(productoId)] ?? 0)) {
      return MENSAJE_SALIDAS_SUPERAN_CARGA;
    }
  }

  for (const item of salidasPorMovimiento(movimiento)) {
    if (!(item.productoId in cargado)) {
      return `${item.nombreProducto} no está cargado en el camión.`;
    }
    // Entero seguro >= 0: el paso anterior garantiza salidas <= cargado.
    const disponible =
      cargado[item.productoId] - (salidas[item.productoId] ?? 0);
    if (item.cantidad > disponible) {
      return `Stock insuficiente de ${item.nombreProducto}.`;
    }
  }

  return null;
}
