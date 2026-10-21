// Dominio puro de precios y subtotales. Sin dependencias de React ni de
// persistencia: no toca stock, localStorage, Supabase ni RPC.
//
// Fuente: ADR-003 y BLUEPRINT.md §7.1.
//
// Reglas:
//   - Un precio es finito, >= 0 y admite como máximo 2 decimales. Más de 2
//     decimales se rechaza: nunca se redondea ni se trunca.
//   - El cálculo interno se hace en centavos enteros.
//   - unidad: subtotal = cantidad * precio_unitario.
//   - pieza: la cantidad canónica `c` (medias piezas) se descompone en
//     floor(c / 2) piezas completas más, como máximo, una media pieza.
//       subtotal = piezas * precio_pieza + (media ? precio_media_pieza(precio_pieza) : 0)
//     El precio de media pieza se deriva: mitad del precio de pieza, redondeado
//     al peso entero más cercano (.50 hacia arriba).
//   - Precio admite hasta 2 decimales; precio de media queda expresado en
//     pesos enteros (sin decimales).
//
// Nota: los identificadores van en snake_case por la convención de dominio.

import { descomponer_medias, validar_cantidad } from "./cantidades";

export type UnidadMedidaPrecio = "unidad" | "pieza";

export interface EntradaPrecios {
  unidad_medida: UnidadMedidaPrecio;
  precio: number;
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

/**
 * Convierte centavos enteros a pesos.
 */
export function centavos_a_pesos(centavos: number): number {
  if (!Number.isSafeInteger(centavos)) {
    throw new Error(`Centavos inválidos: ${String(centavos)}.`);
  }
  return centavos / 100;
}

/**
 * Calcula el precio de media pieza a partir del precio de la pieza completa
 * (ADR-003). Resultado en pesos enteros.
 *
 * Regla: mitad del precio de pieza, redondeada al peso entero.
 * - fracción >= 0.50 → entero superior
 * - fracción < 0.50 → entero inferior
 *
 * Toda la aritmética se hace sobre centavos enteros:
 *   pesos = floor((centavos_pieza + 100) / 200)
 * La división entera se resuelve restando el resto (exacto en enteros
 * seguros), sin pasar por una división de punto flotante.
 *
 * Ejemplos:
 *   pieza 20    → 10
 *   pieza 21    → 11
 *   pieza 20.98 → 10 (mitad 10.49 → baja)
 *   pieza 21.00 → 11 (mitad 10.50 → sube)
 *   pieza 21.02 → 11 (mitad 10.51 → sube)
 *
 * Lanza Error si precio_pieza no es válido según política monetaria o si el
 * cálculo excede el entero seguro.
 */
export function precio_media_pieza(precio_pieza: number): number {
  const centavos_pieza = precio_a_centavos(precio_pieza);
  const dividendo = asegurar_entero_seguro(centavos_pieza + 100);
  return (dividendo - (dividendo % 200)) / 200;
}

/**
 * Lanza Error si el precio no es válido:
 * - precio debe ser finito, >= 0, máx 2 decimales.
 */
export function validar_precio(precio: number): void {
  precio_a_centavos(precio);
}

/**
 * Versión booleana de `validar_precio`.
 */
export function precio_valido(precio: number): boolean {
  try {
    validar_precio(precio);
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
 *
 * Para pieza: usa precio_media_pieza derivado del precio de pieza.
 */
export function subtotal_linea_centavos({
  unidad_medida,
  cantidad,
  precio,
}: EntradaSubtotal): number {
  validar_cantidad(cantidad);
  validar_precio(precio);
  const centavos_precio = precio_a_centavos(precio);

  if (unidad_medida === "unidad") {
    return asegurar_entero_seguro(cantidad * centavos_precio);
  }

  // pieza: descomponer cantidad en piezas enteras + media
  const { piezas, media } = descomponer_medias(cantidad);
  const centavos_media = precio_a_centavos(precio_media_pieza(precio));

  return asegurar_entero_seguro(
    asegurar_entero_seguro(piezas * centavos_precio) +
      (media ? centavos_media : 0)
  );
}

/**
 * Subtotal de una línea en pesos (múltiplo exacto de un centavo).
 * Para operaciones actuales (usando precios vigentes).
 */
export function subtotal_linea(entrada: EntradaSubtotal): number {
  return centavos_a_pesos(subtotal_linea_centavos(entrada));
}

/**
 * Calcula el subtotal de una línea de venta usando precios históricos
 * (snapshot de venta). Única implementación para historial de ventas.
 *
 * No deriva el precio de media; usa el snapshot guardado, para que la venta
 * siga siendo reproducible aunque cambie la regla futura. Falla cerrado:
 * pieza exige precio_media_pieza; unidad lo rechaza si está presente.
 */
export function subtotal_linea_historica_centavos({
  unidad_medida,
  cantidad,
  precio,
  precio_media_pieza,
}: {
  unidad_medida: UnidadMedidaPrecio;
  cantidad: number;
  precio: number;
  precio_media_pieza?: number;
}): number {
  validar_cantidad(cantidad);
  const centavos_precio = precio_a_centavos(precio);

  if (unidad_medida === "unidad") {
    if (precio_media_pieza !== undefined) {
      throw new Error(
        "Venta histórica de unidad no admite precio de media pieza en snapshot."
      );
    }
    return asegurar_entero_seguro(cantidad * centavos_precio);
  }

  if (precio_media_pieza === undefined) {
    throw new Error(
      "Venta histórica de pieza requiere precio de media pieza en snapshot."
    );
  }
  const centavos_media = precio_a_centavos(precio_media_pieza);

  const { piezas, media } = descomponer_medias(cantidad);
  return asegurar_entero_seguro(
    asegurar_entero_seguro(piezas * centavos_precio) +
      (media ? centavos_media : 0)
  );
}

/**
 * Subtotal histórico en pesos.
 */
export function subtotal_linea_historica(entrada: {
  unidad_medida: UnidadMedidaPrecio;
  cantidad: number;
  precio: number;
  precio_media_pieza?: number;
}): number {
  return centavos_a_pesos(subtotal_linea_historica_centavos(entrada));
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