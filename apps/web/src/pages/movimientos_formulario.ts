// Atributos de UX del input de cantidad de la pantalla Movimientos (B2).
// No interpretan el texto: eso lo hace siempre
// cantidad_movimiento_desde_entrada (domain/movimientos.ts).
import type { UnidadMedida } from "../data/mockProductos";

export type AtributosInputMovimiento =
  | { type: "number"; min: "0"; step: "1"; placeholder: "0" }
  | { type: "text"; inputMode: "decimal"; placeholder: "0,000" };

/**
 * "unidad": input numérico entero, como antes de B2. "peso": texto en kg
 * con coma decimal (un input number no admite la coma).
 */
export function atributos_input_movimiento(
  unidad: UnidadMedida
): AtributosInputMovimiento {
  if (unidad === "peso") {
    return { type: "text", inputMode: "decimal", placeholder: "0,000" };
  }
  return { type: "number", min: "0", step: "1", placeholder: "0" };
}
