// Lógica pura de validación de combinación categoría ↔ unidad de medida.
// No toca persistencia, localStorage, stock ni dinero.
// Reglas vigentes (BLUEPRINT.md v1.6 §7.1):
//   - Lácteos  -> "unidad"
//   - Fiambres -> "pieza"
// Toda otra combinación es inválida.
// Los tipos se reutilizan del modelo canónico (sin unions duplicadas).
import { es_cantidad_valida } from "./cantidades";
import type {
  Producto,
  UnidadMedida,
} from "../data/mockProductos";

type Categoria = Producto["categoria"];

export function unidad_para_categoria(
  categoria: Categoria
): UnidadMedida {
  if (categoria === "Lácteos") return "unidad";
  if (categoria === "Fiambres") return "pieza";
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
 * mínima del producto (unidad entera o medias piezas). No redondea ni trunca.
 */
export function stock_producto_valido(
  stock: number,
  stock_minimo: number
): boolean {
  return es_cantidad_valida(stock) && es_cantidad_valida(stock_minimo);
}
