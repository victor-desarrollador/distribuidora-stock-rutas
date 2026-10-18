// Dominio puro de cantidades. Sin dependencias: no toca stock, dinero,
// persistencia, Supabase ni RPC.
//
// Fuente: BLUEPRINT.md §7.1 (unidades pieza / media pieza) y §7.4 (cantidades
// enteras, nunca decimales, nunca negativos).
//
// Reglas:
//   - Una cantidad almacenable es un entero, >= 0 y finito; nunca NaN ni
//     Infinity.
//   - 1 pieza = 2 medias piezas; 1/2 pieza = 1 media pieza. La representación
//     persistible siempre es un entero en medias piezas.
//
// Nota: los identificadores van en snake_case por instrucción explícita de la
// tarea; el resto del frontend usa camelCase.

export const MEDIAS_POR_PIEZA = 2;

/** Una cantidad almacenable: entero, >= 0 y finito. */
export function es_cantidad_valida(cantidad: number): boolean {
  return (
    Number.isFinite(cantidad) && Number.isInteger(cantidad) && cantidad >= 0
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
      `Cantidad inválida: ${String(cantidad)}. Se esperaba un entero finito mayor o igual que cero.`
    );
  }
}

/** Convierte piezas enteras a la unidad mínima (medias piezas). */
export function piezas_a_medias(piezas: number): number {
  validar_cantidad(piezas);
  return piezas * MEDIAS_POR_PIEZA;
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
