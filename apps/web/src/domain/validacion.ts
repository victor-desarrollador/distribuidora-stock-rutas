import { precio_valido, sumar_importes, precio_a_centavos } from "./precios";
import {
  es_venta_mixta,
  importe_linea_vigente,
  tiene_productos_repetidos,
} from "./venta";
import type { Venta, DetalleVenta } from "../data/mockVentas";

/**
 * Escritura de una venta NUEVA: el subtotal coincide con la regla vigente de
 * su tipo (`unidad`: cantidad × precio; `peso`: D-R1, ADR-005 §2.3.3).
 * No se usa en lectura: el histórico no se recalcula (ADR-005 §2.3.4).
 */
export function subtotal_coincide(item: DetalleVenta): boolean {
  if (item.unidadMedida !== "unidad" && item.unidadMedida !== "peso") return false;
  try {
    return (
      importe_linea_vigente({
        unidadMedida: item.unidadMedida,
        cantidad: item.cantidad,
        precio: item.precioUnitario,
      }) === item.subtotal
    );
  } catch {
    return false;
  }
}

/**
 * Valida que el total de una venta coincida con la suma exacta de los
 * subtotales ALMACENADOS de sus items. No recalcula ninguna línea.
 */
export function total_coincide(venta: Venta): boolean {
  try {
    const total_calculado = sumar_importes(venta.items.map((item) => item.subtotal));
    // Comparar EXACTAMENTE en centavos usando precio_a_centavos
    // Fallará cerrado si total o calculado tienen >2 decimales, NaN, Infinity o inválidos.
    return precio_a_centavos(total_calculado) === precio_a_centavos(venta.total);
  } catch {
    return false;
  }
}

/**
 * Valida la ESTRUCTURA de una línea de venta (lectura / histórico).
 * NO recalcula el subtotal con la regla vigente (ADR-005 §2.3.4).
 * - unidadMedida "unidad" o "peso" ("pieza" ya no existe)
 * - cantidad canónica: entero seguro > 0 (unidades o gramos)
 * - precioUnitario válido (unitario o por kg)
 * - precioMediaPieza ausente (legacy ADR-003)
 * - subtotal monetario válido; si es "peso", entero en pesos (forma D-R1)
 */
export function item_valido(item: DetalleVenta): boolean {
  return (
    item !== null &&
    Number.isSafeInteger(item.productoId) &&
    typeof item.nombreProducto === "string" &&
    (item.unidadMedida === "unidad" || item.unidadMedida === "peso") &&
    Number.isSafeInteger(item.cantidad) &&
    item.cantidad > 0 &&
    precio_valido(item.precioUnitario) &&
    item.precioMediaPieza === undefined &&
    precio_valido(item.subtotal) &&
    (item.unidadMedida !== "peso" || Number.isInteger(item.subtotal))
  );
}

/**
 * Valida una venta completa (lectura / histórico). Una venta mixta
 * `unidad` + `peso` es inválida (falla cerrado; regla pendiente, ADR-005 §5).
 */
export function venta_valida(venta: Venta): boolean {
  return (
    typeof venta.id === "string" &&
    typeof venta.jornadaId === "string" &&
    Number.isSafeInteger(venta.camionId) &&
    Number.isSafeInteger(venta.clienteId) &&
    typeof venta.nombreCliente === "string" &&
    typeof venta.fecha === "string" &&
    ["efectivo", "transferencia", "cuenta_corriente"].includes(
      venta.medioPago
    ) &&
    Array.isArray(venta.items) &&
    Number.isFinite(venta.total) &&
    venta.total >= 0 &&
    venta.items.every(item_valido) &&
    !es_venta_mixta(venta.items) &&
    // Validación de total histórico: el total de la venta debe coincidir
    // con la suma exacta de los subtotales almacenados de sus items.
    total_coincide(venta)
  );
}

/**
 * Frontera de escritura de una venta NUEVA: estructura e histórico válidos,
 * al menos un ítem (el histórico sí admite una venta vacía), una sola línea
 * por producto (AUD-B3-01; el histórico sí admite líneas repetidas), sin
 * mezcla `unidad` + `peso` (defensa en profundidad aunque `venta_valida` ya
 * la rechace) y cada subtotal igual a la regla vigente de su tipo.
 */
export function venta_nueva_valida(venta: Venta): boolean {
  return (
    venta_valida(venta) &&
    venta.items.length > 0 &&
    !tiene_productos_repetidos(venta.items) &&
    !es_venta_mixta(venta.items) &&
    venta.items.every(subtotal_coincide)
  );
}
