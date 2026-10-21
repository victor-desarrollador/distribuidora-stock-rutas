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

/**
 * Convierte una cantidad canónica (entero en medias piezas) a su
 * representación legible para el usuario.
 *
 * Ejemplos:
 *   0 -> "0 piezas"
 *   1 -> "media pieza"
 *   2 -> "1 pieza"
 *   3 -> "1 pieza y media"
 *   4 -> "2 piezas"
 *   9 -> "4 piezas y media"
 *
 * Es solo para presentación: la cantidad canónica sigue siendo el entero.
 */
export function medias_a_texto(medias: number): string {
  validar_cantidad(medias);
  if (medias === 0) return "0 piezas";
  if (medias === 1) return "media pieza";
  const piezas = Math.floor(medias / MEDIAS_POR_PIEZA);
  const tieneMedia = medias % MEDIAS_POR_PIEZA === 1;
  if (piezas === 0) {
    return tieneMedia ? "media pieza" : "0 piezas";
  }
  const piezaTexto = piezas === 1 ? "1 pieza" : `${piezas} piezas`;
  return tieneMedia ? `${piezaTexto} y media` : piezaTexto;
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
 * Recompone la cantidad canónica a partir de los componentes de la UX:
 * piezas enteras + media opcional.
 *
 * Ejemplos:
 *   { piezas: 0, media: false } -> 0
 *   { piezas: 0, media: true }  -> 1
 *   { piezas: 1, media: false } -> 2
 *   { piezas: 4, media: true }  -> 9
 *
 * Lanza Error si las entradas son inválidas.
 */
export function recomponer_medias({ piezas, media }: {
  piezas: number;
  media: boolean;
}): number {
  if (!Number.isFinite(piezas) || !Number.isInteger(piezas) || piezas < 0) {
    throw new Error(
      `Piezas inválidas: ${String(piezas)}. Se esperaba un entero finito mayor o igual que cero.`
    );
  }
  if (typeof media !== "boolean") {
    throw new Error("El campo 'media' debe ser booleano.");
  }
  return piezas * MEDIAS_POR_PIEZA + (media ? 1 : 0);
}

/**
 * Máximo de piezas enteras que se pueden pedir sin superar el disponible
 * (en medias piezas), dado si ya hay una media pieza marcada.
 * Invariante: piezas * 2 + (tiene_media ? 1 : 0) <= disponible_medias.
 */
export function maximo_piezas_segun_disponible(
  disponible_medias: number,
  tiene_media: boolean
): number {
  const libre = disponible_medias - (tiene_media ? 1 : 0);
  return Math.max(0, Math.floor(libre / MEDIAS_POR_PIEZA));
}

/**
 * Indica si, con `piezas` enteras ya elegidas, todavía entra una media pieza
 * más sin superar el disponible (en medias piezas).
 */
export function puede_agregar_media(
  disponible_medias: number,
  piezas: number
): boolean {
  return piezas * MEDIAS_POR_PIEZA + 1 <= disponible_medias;
}

/**
 * Interpreta el texto de un input de producto por "unidad".
 *   - vacío o solo espacios -> 0 (no seleccionado)
 *   - entero finito >= 0     -> ese entero
 *   - cualquier otra cosa    -> null (inválido; no se redondea ni trunca)
 */
export function cantidad_unidad_desde_texto(texto: string): number | null {
  if (texto.trim() === "") return 0;
  const n = Number(texto);
  return es_cantidad_valida(n) ? n : null;
}
