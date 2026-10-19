// Lógica pura de validación de combinación categoría ↔ unidad de medida.
// No toca persistencia, localStorage, stock ni dinero.
// Reglas vigentes (BLUEPRINT.md v1.6 §7.1):
//   - Lácteos  -> "unidad"
//   - Fiambres -> "pieza"
// Toda otra combinación es inválida.
// Los tipos se reutilizan del modelo canónico (sin unions duplicadas).
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
