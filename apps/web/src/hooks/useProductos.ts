import { useState } from "react";

import {
  productosIniciales,
  type Producto,
} from "../data/mockProductos";
import { CLAVES_STORAGE } from "../data/clavesStorage";
import {
  stock_producto_valido,
  validar_combinacion_categoria_unidad,
} from "../domain/productos";
import { precio_valido } from "../domain/precios";
import {
  actualizarCatalogoPersistido,
  leerCatalogo,
  type ResultadoLectura,
} from "./catalogoStorage";

const STORAGE_KEY = CLAVES_STORAGE.productos;

function productoValido(producto: unknown): boolean {
  if (producto === null || typeof producto !== "object") return false;

  const p = producto as Partial<Producto>;

  return (
    Number.isSafeInteger(p.id) &&
    typeof p.nombre === "string" &&
    ["Lácteos", "Fiambres"].includes(p.categoria ?? "") &&
    ["unidad", "peso"].includes(p.unidadMedida ?? "") &&
    // Frontera de persistencia: la combinación categoría ↔ unidad
    // debe ser la canónica (Lácteos -> unidad; Fiambres -> peso).
    // Un dato `pieza` invalida el payload: nunca se convierte (D-R4).
    // Nada se corrige aquí (no se cambia categoría ni unidad ni se
    // reinterpreta stock): un dato inválido invalida el payload
    // igual que cualquier otro campo inválido.
    validar_combinacion_categoria_unidad(
      p.categoria as Producto["categoria"],
      p.unidadMedida as Producto["unidadMedida"]
    ).valido &&
    // Precio (ADR-005): máximo 2 decimales; unitario (unidad) o por kg (peso).
    precio_valido(p.precio as number) &&
    // Stock y stock mínimo: enteros seguros >= 0 en unidades o gramos.
    stock_producto_valido(p.stock as number, p.stockMinimo as number)
  );
}

/** Lectura discriminada (ausente / válido / corrupto). */
export function leerProductos(): ResultadoLectura<Producto> {
  return leerCatalogo(STORAGE_KEY, productoValido, productosIniciales);
}

/** Datos para la UI: iniciales si está ausente o corrupto (nunca persiste). */
export function cargarProductos(): Producto[] {
  const lectura = leerProductos();
  return lectura.ok ? lectura.datos : productosIniciales;
}

export function useProductos() {
  const [lectura] = useState(leerProductos);
  const [productos, setProductosEstado] = useState<Producto[]>(
    lectura.ok ? lectura.datos : []
  );

  /**
   * Frontera explícita de edición (bloque E / M-1): relee la clave, aborta si
   * está corrupta (sin escribir ni cambiar React), persiste y solo si la
   * escritura tuvo éxito actualiza el estado. Devuelve false cuando la
   * operación no se guardó.
   */
  function actualizarProductos(
    transformar: (actuales: Producto[]) => Producto[]
  ): boolean {
    const nuevos = actualizarCatalogoPersistido(
      STORAGE_KEY,
      productoValido,
      productosIniciales,
      transformar
    );

    if (nuevos === null) return false;

    setProductosEstado(nuevos);
    return true;
  }

  return { productos, actualizarProductos, estadoLectura: lectura.estado };
}
