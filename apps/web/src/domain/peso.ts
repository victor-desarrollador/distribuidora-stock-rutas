// Conversión exacta entre kg (texto comercial) y gramos enteros (canónico)
// para productos `peso` (ADR-005 §2.2). No toca persistencia, stock ni dinero.
//
// Nunca se usa aritmética de punto flotante: en JavaScript `1.005 * 1000` da
// `1004.9999999999999` (ADR-005 §2.2.6). La entrada se parsea como texto y se
// arma con BigInt; la salida se arma cortando el texto de los gramos.
//
// Formato aceptado (convención es-AR, la misma con la que se muestran los kg):
// dígitos y, opcionalmente, coma decimal con 1 a 3 dígitos. El punto se
// rechaza: en es-AR «1.250» se lee como mil doscientos cincuenta y no hay
// forma segura de distinguirlo de 1,250 kg. Más de 3 decimales se rechaza; no
// se redondea, no se trunca y no se normaliza.

const GRAMOS_POR_KG = 1000n;
const FORMATO_KG = /^(\d+)(?:,(\d{1,3}))?$/;

/**
 * Convierte un texto en kg (por ejemplo «1,250») a gramos enteros (1250).
 * Devuelve null si el texto no es un número >= 0 con hasta 3 decimales y coma
 * decimal, o si el resultado no es un entero seguro de JavaScript.
 */
export function kg_a_gramos(texto: string): number | null {
  const coincidencia = FORMATO_KG.exec(texto.trim());
  if (coincidencia === null) return null;

  const [, entero, decimales = ""] = coincidencia;
  const gramos =
    BigInt(entero) * GRAMOS_POR_KG + BigInt(decimales.padEnd(3, "0"));

  if (gramos > BigInt(Number.MAX_SAFE_INTEGER)) return null;
  return Number(gramos);
}

/**
 * Presenta gramos enteros como kg con 3 decimales fijos y coma decimal
 * (1250 → «1,250»). Sin separador de miles: el texto vuelve a ser una entrada
 * válida de kg_a_gramos. Lanza si los gramos no son un entero seguro >= 0.
 */
export function gramos_a_kg(gramos: number): string {
  if (!Number.isSafeInteger(gramos) || gramos < 0) {
    throw new Error(`Cantidad en gramos inválida: ${gramos}`);
  }

  const digitos = String(gramos).padStart(4, "0");
  return `${digitos.slice(0, -3)},${digitos.slice(-3)}`;
}
