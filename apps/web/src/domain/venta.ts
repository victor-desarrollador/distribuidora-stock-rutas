import type { DetalleVenta } from "../data/mockVentas";
import type { UnidadMedida } from "../data/mockProductos";
import { importe_linea_peso, subtotal_linea } from "./precios";

export const MENSAJE_VENTA_MIXTA_NO_HABILITADA =
  "Una venta no puede mezclar productos por unidad y por peso. Registrá ventas separadas.";

export function es_venta_mixta(
  items: ReadonlyArray<{ unidadMedida: UnidadMedida }>
): boolean {
  return (
    items.some((item) => item?.unidadMedida === "unidad") &&
    items.some((item) => item?.unidadMedida === "peso")
  );
}

export const MENSAJE_VENTA_PRODUCTO_REPETIDO =
  "Una venta no puede tener más de una línea del mismo producto. Unificá la cantidad en una sola línea.";

/**
 * Una venta NUEVA admite una sola línea por producto, sea cual sea su unidad
 * (decisión humana, AUD-B3-01): D-R1 redondea por línea, así que fragmentar
 * un producto en varias líneas alteraría el total. Sólo cuenta ítems con
 * `productoId` entero seguro; los malformados los rechaza la validación
 * estructural. No se usa en la lectura histórica.
 */
export function tiene_productos_repetidos(
  items: ReadonlyArray<{ productoId: number }>
): boolean {
  const vistos = new Set<number>();
  for (const item of items) {
    const productoId = item?.productoId;
    if (!Number.isSafeInteger(productoId)) continue;
    if (vistos.has(productoId)) return true;
    vistos.add(productoId);
  }
  return false;
}

export function importe_linea_vigente(params: {
  unidadMedida: UnidadMedida;
  cantidad: number;
  precio: number;
}): number {
  const { unidadMedida, cantidad, precio } = params;

  if (unidadMedida === "peso") {
    return importe_linea_peso(cantidad, precio);
  }

  return subtotal_linea({
    unidad_medida: "unidad",
    cantidad,
    precio,
  });
}


/**
 * Construye un DetalleVenta válido a partir de los datos del producto y la cantidad canónica.
 * Centraliza el snapshot del precio aplicado y el cálculo del subtotal.
 *
 * - `unidad`: cantidad en unidades enteras; `precioUnitario` = precio por unidad.
 * - `peso`: cantidad en gramos enteros; `precioUnitario` = precio por kg;
 *   subtotal según D-R1 (ADR-005 §2.3.3).
 *
 * Ninguna venta nueva genera `precioMediaPieza` (legacy ADR-003).
 *
 * @param params - Parámetros para construir el detalle
 * @param params.productoId - ID del producto
 * @param params.nombreProducto - Nombre del producto
 * @param params.unidadMedida - "unidad" o "peso"
 * @param params.cantidadCanonica - Unidades enteras o gramos enteros (> 0)
 * @param params.precioReferencia - Precio unitario o por kg vigente del producto
 * @returns DetalleVenta con precioUnitario y subtotal correctos
 */
export function construirDetalleVenta(params: {
  productoId: number;
  nombreProducto: string;
  unidadMedida: UnidadMedida;
  cantidadCanonica: number;
  precioReferencia: number;
}): DetalleVenta {
  const { productoId, nombreProducto, unidadMedida, cantidadCanonica, precioReferencia } = params;

  // Validaciones básicas
  if (!Number.isSafeInteger(cantidadCanonica) || cantidadCanonica <= 0) {
    throw new Error(`Cantidad canónica inválida: ${cantidadCanonica}`);
  }
  if (!Number.isFinite(precioReferencia) || precioReferencia < 0) {
    throw new Error(`Precio de referencia inválido: ${precioReferencia}`);
  }

  const precioUnitario = precioReferencia;

  // Importe de la línea según la regla vigente de su tipo.
  const subtotal = importe_linea_vigente({
    unidadMedida,
    cantidad: cantidadCanonica,
    precio: precioUnitario,
  });

  return {
    productoId,
    nombreProducto,
    unidadMedida,
    cantidad: cantidadCanonica,
    precioUnitario,
    subtotal,
  };
}

/**
 * Construye múltiples DetalleVenta a partir de una lista de productos y cantidades.
 * Usado por Autoventa para armar el array de items de la venta.
 */
export function construirItemsVenta(params: {
  productos: Array<{
    productoId: number;
    nombreProducto: string;
    unidadMedida: UnidadMedida;
    precioReferencia: number;
  }>;
  obtenerCantidadCanonica: (productoId: number) => number;
}): DetalleVenta[] {
  const items = params.productos
    .map((producto) => {
      const cantidadCanonica = params.obtenerCantidadCanonica(producto.productoId);
      if (cantidadCanonica <= 0) return null;
      return construirDetalleVenta({
        productoId: producto.productoId,
        nombreProducto: producto.nombreProducto,
        unidadMedida: producto.unidadMedida,
        cantidadCanonica,
        precioReferencia: producto.precioReferencia,
      });
    })
    .filter((item): item is DetalleVenta => item !== null);

  if (es_venta_mixta(items)) {
    throw new Error(MENSAJE_VENTA_MIXTA_NO_HABILITADA);
  }

  return items;
}
