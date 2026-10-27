// Dominio puro de cantidades. Sin dependencias: no toca stock, dinero,
// persistencia, Supabase ni RPC.
//
// Fuente: BLUEPRINT.md §7.1 y §7.4 (cantidades enteras en la unidad mínima:
// unidades o gramos, ADR-005; nunca decimales, nunca negativos).
//
// Reglas:
//   - Una cantidad almacenable es un ENTERO SEGURO (Number.isSafeInteger),
//     >= 0 y finito; nunca NaN ni Infinity.
//
// Deuda legacy (ADR-003, histórica): MEDIAS_POR_PIEZA y descomponer_medias
// sólo los usa domain/precios.ts (se revisa en B3); piezas_a_medias y
// medias_a_piezas no tienen consumidores productivos (limpieza final, B5).
//
// Nota: los identificadores van en snake_case por instrucción explícita de la
// tarea; el resto del frontend usa camelCase.

export const MEDIAS_POR_PIEZA = 2;

/**
 * Una cantidad almacenable: ENTERO SEGURO, >= 0 y finito.
 * Usa Number.isSafeInteger para garantizar exactitud en todas las operaciones
 * aritméticas (sumas, restas, multiplicaciones) sin pérdida de precisión.
 * Rechaza enteros fuera del rango seguro (ej. Number.MAX_SAFE_INTEGER + 1).
 */
export function es_cantidad_valida(cantidad: number): boolean {
  return (
    Number.isFinite(cantidad) &&
    Number.isSafeInteger(cantidad) &&
    cantidad >= 0
  );
}

/**
 * Lanza Error si la cantidad no es almacenable. Se usa en todo punto de
 * entrada que reciba una cantidad, para no guardar jamás decimales, negativos,
 * NaN ni Infinity.
 */
export function validar_cantidad(cantidad: number): void {
  if (!es_cantidad_valida(cantidad)) {
    throw new Error(
      `Cantidad inválida: ${String(cantidad)}. Se esperaba un entero seguro finito mayor o igual que cero.`
    );
  }
}

/**
 * Verifica que la suma de dos cantidades canónicas no desborde el rango seguro.
 * Fallo cerrado: devuelve false si el resultado excede Number.MAX_SAFE_INTEGER.
 */
export function es_suma_segura(a: number, b: number): boolean {
  if (!es_cantidad_valida(a) || !es_cantidad_valida(b)) return false;
  return a + b <= Number.MAX_SAFE_INTEGER;
}

/**
 * Suma dos cantidades canónicas con verificación de desbordamiento.
 * Lanza Error si el resultado excede Number.MAX_SAFE_INTEGER.
 */
export function sumar_cantidades_seguras(a: number, b: number): number {
  if (!es_suma_segura(a, b)) {
    throw new Error(
      `Desbordamiento de cantidad canónica: ${a} + ${b} excede Number.MAX_SAFE_INTEGER.`
    );
  }
  return a + b;
}

/**
 * Convierte piezas a la unidad mínima (medias piezas). Admite medias piezas
 * exactas: 0.5 piezas = 1 media, 1.5 piezas = 3 medias. Rechaza negativos,
 * NaN, Infinity y cualquier valor que no sea un múltiplo exacto de 0.5. La
 * salida es siempre una cantidad canónica entera en medias piezas.
 *
 * No usa `validar_cantidad` porque el argumento admite 0.5, que no es una
 * cantidad canónica almacenable: la validación es local a piezas.
 */
export function piezas_a_medias(piezas: number): number {
  if (
    !Number.isFinite(piezas) ||
    piezas < 0 ||
    !Number.isInteger(piezas * MEDIAS_POR_PIEZA)
  ) {
    throw new Error(
      `Piezas inválidas: ${String(piezas)}. Se esperaba un múltiplo exacto de 0.5, finito y mayor o igual que cero.`
    );
  }
  const resultado = piezas * MEDIAS_POR_PIEZA;
  if (!es_cantidad_valida(resultado)) {
    throw new Error(
      `Desbordamiento al convertir piezas a medias: ${resultado} excede rango seguro.`
    );
  }
  return resultado;
}

/**
 * Convierte medias piezas a su representación exacta en piezas, sin truncar:
 * 2 medias = 1 pieza, 1 media = 0.5 piezas, 9 medias = 4.5 piezas.
 *
 * Es solo una conversión de representación: el stock canónico sigue siendo el
 * entero en medias piezas. Por eso el resultado puede ser fraccionario y no es,
 * en sí mismo, una cantidad almacenable.
 */
export function medias_a_piezas(medias: number): number {
  validar_cantidad(medias);
  return medias / MEDIAS_POR_PIEZA;
}

/**
 * Separa una cantidad canónica (entero en medias piezas) en sus dos
 * componentes para la UX: cantidad de piezas enteras y si tiene media pieza.
 *
 * Devuelve: { piezas: número de piezas enteras, media: boolean }
 *
 * Ejemplos:
 *   0 -> { piezas: 0, media: false }
 *   1 -> { piezas: 0, media: true }
 *   2 -> { piezas: 1, media: false }
 *   3 -> { piezas: 1, media: true }
 *   9 -> { piezas: 4, media: true }
 */
export function descomponer_medias(medias: number): {
  piezas: number;
  media: boolean;
} {
  validar_cantidad(medias);
  return {
    piezas: Math.floor(medias / MEDIAS_POR_PIEZA),
    media: medias % MEDIAS_POR_PIEZA === 1,
  };
}

/**
 * Interpreta el texto de un input de producto por "unidad".
 *   - vacío o solo espacios -> 0 (no seleccionado)
 *   - entero seguro finito >= 0     -> ese entero
 *   - cualquier otra cosa    -> null (inválido; no se redondea ni trunca)
 */
export function cantidad_unidad_desde_texto(texto: string): number | null {
  if (texto.trim() === "") return 0;
  const n = Number(texto);
  return es_cantidad_valida(n) ? n : null;
}
