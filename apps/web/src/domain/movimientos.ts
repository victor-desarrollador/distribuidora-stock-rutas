// Dominio puro de movimientos de reparto (merma, devolución, cambio) del
// prototipo. Sin React, sin persistencia, sin Supabase ni RPC.
//
// Fuente: BLUEPRINT.md §7.1 (cantidades enteras; pieza en medias piezas) y
// docs/requirements/migracion-unidades-prototipo.md §5 y §8.
//
// No reimplementa conversiones: usa domain/cantidades.ts. La cantidad
// persistida de un movimiento es siempre un entero canónico: unidades enteras
// para "unidad", medias piezas para "pieza".

import type {
  MovimientoReparto,
  ProductoMovimiento,
} from "../data/mockMovimientos";
import { salidasPorMovimiento } from "../data/mockMovimientos";
import type { UnidadMedida } from "../data/mockProductos";
import {
  cantidad_unidad_desde_texto,
  es_cantidad_valida,
  recomponer_medias,
} from "./cantidades";

/** Entrada de UI de una cantidad: texto del input entero + media opcional. */
export interface EntradaCantidad {
  /** "unidad": cantidad entera. "pieza": piezas completas. */
  texto: string;
  /** Solo "pieza": checkbox de media pieza. En "unidad" debe ser false. */
  media: boolean;
}

/**
 * Convierte la entrada de UI en la cantidad canónica de un movimiento, o null
 * si es inválida. Un movimiento exige una cantidad estrictamente positiva:
 * vacío, 0, decimales, negativos, NaN e Infinity devuelven null (no se
 * redondea ni trunca).
 */
export function cantidad_movimiento_desde_entrada(
  unidad: UnidadMedida,
  entrada: EntradaCantidad
): number | null {
  const base = cantidad_unidad_desde_texto(entrada.texto);
  if (base === null) return null;

  let canonica: number;
  if (unidad === "pieza") {
    canonica = recomponer_medias({ piezas: base, media: entrada.media });
  } else if (unidad === "unidad") {
    if (entrada.media) return null;
    canonica = base;
  } else {
    return null;
  }

  return canonica > 0 ? canonica : null;
}

/** Item de movimiento válido: unidad soportada (sin kg) y cantidad entera > 0. */
export function producto_movimiento_valido(
  p: unknown
): p is ProductoMovimiento {
  if (typeof p !== "object" || p === null) return false;
  const { productoId, nombreProducto, unidadMedida, cantidad } =
    p as Partial<ProductoMovimiento>;

  return (
    Number.isSafeInteger(productoId) &&
    typeof nombreProducto === "string" &&
    (unidadMedida === "unidad" || unidadMedida === "pieza") &&
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
    return (
      producto_movimiento_valido(mov.productoDevuelto) &&
      producto_movimiento_valido(mov.productoEntregado)
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

/**
 * Cantidades de la jornada que dejaron de estar disponibles: ventas más
 * salidas de movimientos (merma y producto entregado en un cambio; la
 * devolución no descuenta). Todo en cantidades canónicas.
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
      resultado[item.productoId] =
        (resultado[item.productoId] ?? 0) + item.cantidad;
    }
  }

  for (const movimiento of movimientos) {
    if (movimiento.jornadaId !== jornada_id) continue;
    for (const item of salidasPorMovimiento(movimiento)) {
      resultado[item.productoId] =
        (resultado[item.productoId] ?? 0) + item.cantidad;
    }
  }

  return resultado;
}

/** Disponible por producto = cargado - salidas, nunca negativo. */
export function disponibles_de_jornada(
  cargados: ReadonlyArray<ItemCargado>,
  salidas: Readonly<Record<number, number>>
): Record<number, number> {
  const resultado: Record<number, number> = {};
  for (const item of cargados) {
    resultado[item.productoId] = Math.max(
      0,
      item.cantidad - (salidas[item.productoId] ?? 0)
    );
  }
  return resultado;
}

/**
 * Verifica que las salidas del movimiento nuevo no superen lo disponible en
 * la jornada. Devuelve el mensaje de error o null. Comparación exacta entre
 * enteros canónicos (sin tolerancia).
 */
export function validar_stock_movimiento(
  movimiento: MovimientoReparto,
  cargados: ReadonlyArray<ItemCargado>,
  ventas: ReadonlyArray<VentaConItems>,
  movimientos_actuales: ReadonlyArray<MovimientoReparto>
): string | null {
  const salidas = salidas_de_jornada(
    movimiento.jornadaId,
    ventas,
    movimientos_actuales
  );
  const disponibles = disponibles_de_jornada(cargados, salidas);

  for (const item of salidasPorMovimiento(movimiento)) {
    if (!(item.productoId in disponibles)) {
      return `${item.nombreProducto} no está cargado en el camión.`;
    }
    if (item.cantidad > disponibles[item.productoId]) {
      return `Stock insuficiente de ${item.nombreProducto}.`;
    }
  }

  return null;
}
