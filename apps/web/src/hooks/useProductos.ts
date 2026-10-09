
import { useEffect, useState } from "react";

import {
  productosIniciales,
  type Producto,
} from "../data/mockProductos";

const STORAGE_KEY = "distribuidora_productos_demo_v1";

function cargarProductos(): Producto[] {
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
        ["unidad", "pieza", "kg"].includes(producto.unidadMedida) &&
        Number.isFinite(producto.precio) &&
        producto.precio >= 0 &&
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
