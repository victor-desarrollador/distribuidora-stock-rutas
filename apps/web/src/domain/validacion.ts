import { precio_valido, subtotal_linea_historica, sumar_importes, precio_a_centavos } from "./precios";
import type { Venta, DetalleVenta } from "../data/mockVentas";

/**
 * Valida que el subtotal de un item coincida con el cálculo histórico.
 * B1: sólo líneas "unidad"; una línea "peso" es inválida hasta B3 (su importe
 * depende de D-R1).
 */
export function subtotal_coincide(item: DetalleVenta): boolean {
  if (item.unidadMedida !== "unidad") return false;
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
    const subtotales = venta.items.map((item) => {
      // B1: una línea "peso" invalida la venta hasta B3 (D-R1).
      if (item.unidadMedida !== "unidad") {
        throw new Error("Línea por peso no admitida todavía.");
      }
      return subtotal_linea_historica({
        unidad_medida: item.unidadMedida,
        cantidad: item.cantidad,
        precio: item.precioUnitario,
        precio_media_pieza: item.precioMediaPieza,
      });
    });
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
 * Reglas (B1):
 * - unidadMedida "unidad" ("peso" es inválida hasta B3; "pieza" ya no existe)
 * - cantidad canónica > 0 (entera, finita)
 * - precioUnitario válido
 * - precioMediaPieza ausente (legacy ADR-003; ninguna venta v5 lo tiene)
 * - subtotal coincide con cálculo histórico usando snapshot
 */
export function item_valido(item: DetalleVenta): boolean {
  return (
    item !== null &&
    Number.isSafeInteger(item.productoId) &&
    typeof item.nombreProducto === "string" &&
    item.unidadMedida === "unidad" &&
    Number.isFinite(item.cantidad) &&
    item.cantidad > 0 &&
    Number.isInteger(item.cantidad) &&
    // Historial del precio aplicado: snapshot histórico.
    precio_valido(item.precioUnitario) &&
    item.precioMediaPieza === undefined &&
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
    // con la suma exacta de los subtotales de sus items.
    total_coincide(venta)
  );
}
