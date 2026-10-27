import type { DetalleVenta } from "../data/mockVentas";
import type { UnidadMedida } from "../data/mockProductos";
import { subtotal_linea } from "./precios";
import { MENSAJE_PESO_NO_OPERABLE } from "./productos";


/**
 * Construye un DetalleVenta válido a partir de los datos del producto y la cantidad canónica.
 * Centraliza el snapshot del precio aplicado y el cálculo de subtotal.
 *
 * B1: sólo se venden productos "unidad". Un producto "peso" lanza: su importe
 * depende de D-R1 y Autoventa por peso es B3. Ninguna venta nueva genera
 * `precioMediaPieza` (legacy ADR-003).
 *
 * @param params - Parámetros para construir el detalle
 * @param params.productoId - ID del producto
 * @param params.nombreProducto - Nombre del producto
 * @param params.unidadMedida - "unidad" ("peso" se rechaza hasta B3)
 * @param params.cantidadCanonica - Cantidad en unidades enteras
 * @param params.precioReferencia - Precio unitario vigente del producto
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

  // B1: venta por peso pendiente de B3 (D-R1). Falla cerrado.
  if (unidadMedida !== "unidad") {
    throw new Error(MENSAJE_PESO_NO_OPERABLE);
  }

  // Validaciones básicas
  if (!Number.isFinite(cantidadCanonica) || cantidadCanonica <= 0 || !Number.isInteger(cantidadCanonica)) {
    throw new Error(`Cantidad canónica inválida: ${cantidadCanonica}`);
  }
  if (!Number.isFinite(precioReferencia) || precioReferencia < 0) {
    throw new Error(`Precio de referencia inválido: ${precioReferencia}`);
  }

  const precioUnitario = precioReferencia;

  // Subtotal de la línea `unidad` con la función de dominio vigente.
  const subtotal = subtotal_linea({
    unidad_medida: unidadMedida,
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
  return params.productos
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
}
