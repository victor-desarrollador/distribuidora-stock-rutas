import { useEffect, useState } from "react";

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
  leerCatalogo,
  persistirCatalogo,
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
    ["unidad", "pieza"].includes(p.unidadMedida ?? "") &&
    // Frontera de persistencia: la combinación categoría ↔ unidad
    // debe ser la canónica (Lácteos -> unidad; Fiambres -> pieza).
    // Nada se corrige aquí (no se cambia categoría ni unidad ni se
    // reinterpreta stock): un dato inválido invalida el payload
    // igual que cualquier otro campo inválido.
    validar_combinacion_categoria_unidad(
      p.categoria as Producto["categoria"],
      p.unidadMedida as Producto["unidadMedida"]
    ).valido &&
    // Precios (ADR-003): máximo 2 decimales; NO hay precioMediaPieza configurable.
    // pieza: solo precio; unidad: solo precio.
    precio_valido(p.precio as number) &&
    // Stock y stock mínimo: enteros seguros >= 0 (dominio compartido).
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
  const [productos, setProductos] = useState<Producto[]>(
    lectura.ok ? lectura.datos : productosIniciales
  );

  useEffect(() => {
    // Storage corrupto: no se pisa el raw con datos demo ni con ediciones.
    persistirCatalogo(STORAGE_KEY, productos, lectura);
  }, [productos, lectura]);

  return { productos, setProductos };
}
