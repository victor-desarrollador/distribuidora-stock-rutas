// Dominio puro de precios y subtotales. Sin dependencias de React ni de
// persistencia: no toca stock, localStorage, Supabase ni RPC.
//
// Fuente: ADR-002 y BLUEPRINT.md §7.1.
//
// Reglas:
//   - Un precio es finito, >= 0 y admite como máximo 2 decimales. Más de 2
//     decimales se rechaza: nunca se redondea ni se trunca.
//   - El cálculo interno se hace en centavos enteros.
//   - unidad: subtotal = cantidad * precio_unitario.
//   - pieza: la cantidad canónica `c` (medias piezas) se descompone en
//     floor(c / 2) piezas completas más, como máximo, una media pieza:
//       subtotal = piezas * precio_pieza + (media ? precio_media_pieza : 0)
//     No hay relación obligatoria entre precio_pieza y precio_media_pieza.
//   - `precio_media_pieza` es obligatorio en pieza y no aplica en unidad.
//
// Nota: los identificadores van en snake_case por la convención de dominio.

import { descomponer_medias, validar_cantidad } from "./cantidades";

export type UnidadMedidaPrecio = "unidad" | "pieza";

export interface EntradaPrecios {
  unidad_medida: UnidadMedidaPrecio;
  precio: number;
  precio_media_pieza?: number;
}

export interface EntradaSubtotal extends EntradaPrecios {
  cantidad: number;
}

/**
 * Convierte un precio en pesos a centavos enteros. Lanza Error si el precio
 * no es finito, es negativo o tiene más de 2 decimales.
 */
export function precio_a_centavos(precio: number): number {
  if (typeof precio !== "number" || !Number.isFinite(precio) || precio < 0) {
    throw new Error(
      `Precio inválido: ${String(precio)}. Se esperaba un número finito mayor o igual que cero.`
    );
  }
  const centavos = Math.round(precio * 100);
  // Un precio de hasta 2 decimales es exactamente el doble más cercano a
  // centavos / 100; cualquier otro (p. ej. 10.001) no lo es.
  if (!Number.isSafeInteger(centavos) || centavos / 100 !== precio) {
    throw new Error(
      `Precio inválido: ${String(precio)}. Se admiten como máximo 2 decimales.`
    );
  }
  return centavos;
}

/** Convierte centavos enteros a pesos. */
export function centavos_a_pesos(centavos: number): number {
  if (!Number.isSafeInteger(centavos)) {
    throw new Error(`Centavos inválidos: ${String(centavos)}.`);
  }
  return centavos / 100;
}

/**
 * Lanza Error si la combinación de precios no es válida para la forma de venta:
 * pieza exige precio y precio_media_pieza válidos; unidad exige precio válido y
 * ausencia de precio_media_pieza.
 */
export function validar_precios_producto({
  unidad_medida,
  precio,
  precio_media_pieza,
}: EntradaPrecios): void {
  precio_a_centavos(precio);
  if (unidad_medida === "pieza") {
    if (precio_media_pieza === undefined) {
      throw new Error("Un producto por pieza requiere precio de media pieza.");
    }
    precio_a_centavos(precio_media_pieza);
    return;
  }
  if (unidad_medida === "unidad") {
    if (precio_media_pieza !== undefined) {
      throw new Error(
        "Un producto por unidad no admite precio de media pieza."
      );
    }
    return;
  }
  throw new Error(`Forma de venta no reconocida: ${String(unidad_medida)}.`);
}

/** Versión booleana de `validar_precios_producto`. */
export function precios_producto_validos(entrada: EntradaPrecios): boolean {
  try {
    validar_precios_producto(entrada);
    return true;
  } catch {
    return false;
  }
}

function asegurar_entero_seguro(valor: number): number {
  if (!Number.isSafeInteger(valor)) {
    throw new Error("El importe excede el máximo entero seguro.");
  }
  return valor;
}

/**
 * Subtotal de una línea en centavos enteros. Única implementación de la
 * fórmula: las pantallas y los hooks la importan, no la copian.
 */
export function subtotal_linea_centavos({
  unidad_medida,
  cantidad,
  precio,
  precio_media_pieza,
}: EntradaSubtotal): number {
  validar_cantidad(cantidad);
  validar_precios_producto({ unidad_medida, precio, precio_media_pieza });
  const centavos_precio = precio_a_centavos(precio);

  if (unidad_medida === "unidad") {
    return asegurar_entero_seguro(cantidad * centavos_precio);
  }

  const centavos_media = precio_a_centavos(precio_media_pieza as number);
  const { piezas, media } = descomponer_medias(cantidad);
  return asegurar_entero_seguro(
    asegurar_entero_seguro(piezas * centavos_precio) +
      (media ? centavos_media : 0)
  );
}

/** Subtotal de una línea en pesos (múltiplo exacto de un centavo). */
export function subtotal_linea(entrada: EntradaSubtotal): number {
  return centavos_a_pesos(subtotal_linea_centavos(entrada));
}

/**
 * Suma importes en pesos pasando por centavos enteros. Cada importe debe ser
 * válido (finito, >= 0, hasta 2 decimales).
 */
export function sumar_importes(importes: readonly number[]): number {
  let total = 0;
  for (const importe of importes) {
    total = asegurar_entero_seguro(total + precio_a_centavos(importe));
  }
  return centavos_a_pesos(total);
}
