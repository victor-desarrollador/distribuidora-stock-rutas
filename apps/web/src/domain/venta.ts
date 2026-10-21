import type { DetalleVenta } from "../data/mockVentas";
import { precio_media_pieza, subtotal_linea } from "./precios";


/**
 * Construye un DetalleVenta válido a partir de los datos del producto y la cantidad canónica.
 * Centraliza la lógica de snapshot histórico (ADR-003) y cálculo de subtotal.
 *
 * @param params - Parámetros para construir el detalle
 * @param params.productoId - ID del producto
 * @param params.nombreProducto - Nombre del producto
 * @param params.unidadMedida - "unidad" | "pieza"
 * @param params.cantidadCanonica - Cantidad en unidad canónica (unidades enteras para "unidad", medias piezas para "pieza")
 * @param params.precioReferencia - Precio vigente del producto (precio unitario para "unidad", precio por pieza completa para "pieza")
 * @returns DetalleVenta con precioUnitario, precioMediaPieza (snapshot) y subtotal correctos
 */
export function construirDetalleVenta(params: {
  productoId: number;
  nombreProducto: string;
  unidadMedida: "unidad" | "pieza";
  cantidadCanonica: number;
  precioReferencia: number;
}): DetalleVenta {
  const { productoId, nombreProducto, unidadMedida, cantidadCanonica, precioReferencia } = params;

  // Validaciones básicas
  if (!Number.isFinite(cantidadCanonica) || cantidadCanonica <= 0 || !Number.isInteger(cantidadCanonica)) {
    throw new Error(`Cantidad canónica inválida: ${cantidadCanonica}`);
  }
  if (!Number.isFinite(precioReferencia) || precioReferencia < 0) {
    throw new Error(`Precio de referencia inválido: ${precioReferencia}`);
  }

  const precioUnitario = precioReferencia;

  // Snapshot histórico del precio de media pieza (ADR-003)
  const precioMediaPieza =
    unidadMedida === "pieza" ? precio_media_pieza(precioUnitario) : undefined;

  // Subtotal usando la función de dominio (maneja unidad/pieza correctamente)
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
    precioMediaPieza,
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
    unidadMedida: "unidad" | "pieza";
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
