// Lógica pura de validación de combinación categoría ↔ forma de venta.
// No toca persistencia, localStorage, stock ni dinero.
// Reglas vigentes (BLUEPRINT.md §7.1, ADR-005):
//   - Lácteos  -> "unidad"
//   - Fiambres -> "peso"
// Toda otra combinación es inválida (incluida la histórica "pieza").
// Los tipos se reutilizan del modelo canónico (sin unions duplicadas).
import { es_cantidad_valida } from "./cantidades";
import { gramos_a_kg } from "./peso";
import type {
  Producto,
  UnidadMedida,
} from "../data/mockProductos";

type Categoria = Producto["categoria"];

/**
 * Bloqueo temporal de B1: los flujos operativos del demo (Jornadas,
 * Autoventa, Movimientos, Retornos y Rendición) todavía no operan productos
 * `peso`. Se habilitan en B2/B3/B4, con entrada en kg y conversión exacta.
 */
export const MENSAJE_PESO_NO_OPERABLE =
  "Producto por peso: disponible a partir de la migración del flujo correspondiente.";

export function unidad_para_categoria(
  categoria: Categoria
): UnidadMedida {
  if (categoria === "Lácteos") return "unidad";
  if (categoria === "Fiambres") return "peso";
  throw new Error(`Categoría no reconocida: ${categoria}`);
}

export function validar_combinacion_categoria_unidad(
  categoria: Categoria,
  unidad_medida: UnidadMedida
): { valido: boolean; mensaje?: string } {
  const esperado = unidad_para_categoria(categoria);

  if (unidad_medida === esperado) {
    return { valido: true };
  }

  return {
    valido: false,
    mensaje: `La categoría "${categoria}" solo permite la unidad "${esperado}".`,
  };
}

/**
 * Stock y stock mínimo de un producto: enteros seguros >= 0 en la unidad
 * mínima del producto (unidades o gramos). No redondea ni trunca.
 */
export function stock_producto_valido(
  stock: number,
  stock_minimo: number
): boolean {
  return es_cantidad_valida(stock) && es_cantidad_valida(stock_minimo);
}

/**
 * Presentación de una cantidad canónica. `peso` pasa siempre por
 * gramos_a_kg (18000 → «18,000 kg»): los gramos nunca se muestran como kg.
 */
export function cantidad_a_texto(
  unidad: UnidadMedida,
  cantidad: number
): string {
  if (unidad === "peso") return `${gramos_a_kg(cantidad)} kg`;
  return `${cantidad} un.`;
}
