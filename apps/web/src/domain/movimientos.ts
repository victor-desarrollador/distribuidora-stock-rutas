// Dominio puro de movimientos de reparto (merma, devolución, cambio) del
// prototipo. Sin React, sin persistencia, sin Supabase ni RPC.
//
// Fuente: BLUEPRINT.md §7.1 y §7.4 (cantidades enteras en la unidad mínima;
// ADR-005).
//
// No reimplementa conversiones: usa domain/cantidades.ts. La cantidad
// persistida de un movimiento es siempre un entero canónico: unidades enteras
// para "unidad", gramos para "peso". En B1 la entrada de UI sólo admite
// "unidad": los movimientos `peso` se habilitan en B2.

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

/** Entrada de UI de una cantidad: texto del input entero ("unidad"). */
export interface EntradaCantidad {
  texto: string;
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
  // B1: `peso` no es operable todavía (B2); falla cerrado.
  if (unidad !== "unidad") return null;

  const canonica = cantidad_unidad_desde_texto(entrada.texto);
  if (canonica === null) return null;

  return canonica > 0 ? canonica : null;
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
 * Disponible por producto = cargado - salidas, nunca negativo. Lanza Error si
 * lo cargado no es una cantidad canónica válida.
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
 * Única cadena de cálculo de disponibilidad (UI y validación previa al
 * registro). Falla cerrado: ante cantidades inválidas o desbordamiento
 * devuelve ok:false y NO un saldo aproximado.
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
      error:
        "No se puede calcular el stock disponible: hay cantidades inválidas o fuera del rango seguro.",
    };
  }
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
  const disponibilidad = disponibilidad_de_jornada(
    movimiento.jornadaId,
    cargados,
    ventas,
    movimientos_actuales
  );
  if (!disponibilidad.ok) return disponibilidad.error;
  const { disponibles } = disponibilidad;

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
