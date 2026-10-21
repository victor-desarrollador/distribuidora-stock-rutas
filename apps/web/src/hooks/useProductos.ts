
import { useEffect, useState } from "react";

import {
  productosIniciales,
  type Producto,
} from "../data/mockProductos";
import { CLAVES_STORAGE } from "../data/clavesStorage";
import { validar_combinacion_categoria_unidad } from "../domain/productos";
import { precios_producto_validos } from "../domain/precios";

const STORAGE_KEY = CLAVES_STORAGE.productos;

export function cargarProductos(): Producto[] {
  try {
    const guardados = localStorage.getItem(STORAGE_KEY);

    if (!guardados) return productosIniciales;

    const datos: unknown = JSON.parse(guardados);

    if (!Array.isArray(datos)) return productosIniciales;

    const validos = datos.every(
      (producto) =>
        producto !== null &&
        typeof producto === "object" &&
        Number.isSafeInteger(producto.id) &&
        typeof producto.nombre === "string" &&
        ["Lácteos", "Fiambres"].includes(producto.categoria) &&
        ["unidad", "pieza"].includes(producto.unidadMedida) &&
        // Frontera de persistencia: la combinación categoría ↔ unidad
        // debe ser la canónica (Lácteos -> unidad; Fiambres -> pieza).
        // Nada se corrige aquí (no se cambia categoría ni unidad ni se
        // reinterpreta stock): un dato inválido invalida el payload
        // igual que cualquier otro campo inválido.
        validar_combinacion_categoria_unidad(
          producto.categoria,
          producto.unidadMedida
        ).valido &&
        // Precios (ADR-002): máximo 2 decimales; pieza exige precio de media
        // pieza y unidad no lo admite. Nada se completa ni se deriva.
        precios_producto_validos({
          unidad_medida: producto.unidadMedida,
          precio: producto.precio,
          precio_media_pieza: producto.precioMediaPieza,
        }) &&
        Number.isFinite(producto.stock) &&
        producto.stock >= 0 &&
        Number.isFinite(producto.stockMinimo) &&
        producto.stockMinimo >= 0
    );

    return validos ? (datos as Producto[]) : productosIniciales;
  } catch {
    return productosIniciales;
  }
}

export function useProductos() {
  const [productos, setProductos] = useState<Producto[]>(cargarProductos);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(productos));
    } catch (error) {
      console.error("No se pudieron guardar los productos:", error);
    }
  }, [productos]);

  return { productos, setProductos };
}
