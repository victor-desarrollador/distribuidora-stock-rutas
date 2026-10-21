import { precio_valido, subtotal_linea_historica, sumar_importes, precio_a_centavos } from "./precios";
import type { Venta, DetalleVenta } from "../data/mockVentas";

/**
 * Valida que el subtotal de un item coincida con el cálculo histórico
 * usando el snapshot de precioMediaPieza (ADR-003).
 */
export function subtotal_coincide(item: DetalleVenta): boolean {
  try {
    return (
      subtotal_linea_historica({
        unidad_medida: item.unidadMedida,
        cantidad: item.cantidad,
        precio: item.precioUnitario,
        precio_media_pieza: item.precioMediaPieza,
      }) === item.subtotal
    );
  } catch {
    return false;
  }
}

/**
 * Valida que el total de una venta coincida con la suma exacta
 * de los subtotales históricos de sus items.
 */
export function total_coincide(venta: Venta): boolean {
  try {
    const subtotales = venta.items.map((item) =>
      subtotal_linea_historica({
        unidad_medida: item.unidadMedida,
        cantidad: item.cantidad,
        precio: item.precioUnitario,
        precio_media_pieza: item.precioMediaPieza,
      })
    );
    const total_calculado = sumar_importes(subtotales);
    // Comparar EXACTAMENTE en centavos usando precio_a_centavos
    // Fallará cerrado si total o calculado tienen >2 decimales, NaN, Infinity o inválidos.
    return precio_a_centavos(total_calculado) === precio_a_centavos(venta.total);
  } catch {
    return false;
  }
}

/**
 * Valida un item de venta individual (línea de detalle).
 * Reglas ADR-003:
 * - unidadMedida válida
 * - cantidad canónica > 0 (entera, finita)
 * - precioUnitario válido
 * - precioMediaPieza: obligatorio en "pieza", prohibido en "unidad"
 * - subtotal coincide con cálculo histórico usando snapshot
 */
export function item_valido(item: DetalleVenta): boolean {
  return (
    item !== null &&
    Number.isSafeInteger(item.productoId) &&
    typeof item.nombreProducto === "string" &&
    ["unidad", "pieza"].includes(item.unidadMedida) &&
    Number.isFinite(item.cantidad) &&
    item.cantidad > 0 &&
    Number.isInteger(item.cantidad) &&
    // Historial de precios aplicados (ADR-003): snapshot histórico.
    precio_valido(item.precioUnitario) &&
    (item.unidadMedida === "pieza"
      ? item.precioMediaPieza !== undefined
      : item.precioMediaPieza === undefined) &&
    // Validación de subtotal usando snapshot histórico
    subtotal_coincide(item)
  );
}

/**
 * Valida una venta completa.
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
    // Validación de total histórico: el total de la venta debe coincidir
    // con la suma exacta de los subtotales de sus items (ADR-003).
    total_coincide(venta)
  );
}
