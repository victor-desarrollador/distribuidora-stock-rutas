// Lógica pura de la preparación de cargas de la pantalla Jornadas (ADR-005,
// B2). Sin React ni persistencia: la frontera crearPreparacionPersistida
// sigue siendo la autoridad del stock; esto arma la UX con la misma
// semántica (calcularStockReservado de useJornadas, sin copia local).
//
// Cantidades canónicas: unidades enteras ("unidad") o gramos enteros
// ("peso"). La entrada de peso es kg con coma y hasta 3 decimales
// (kg_a_gramos), sin punto flotante.
import type { ItemCarga, Jornada } from "../data/mockJornadas";
import type { Producto, UnidadMedida } from "../data/mockProductos";
import type { RetornoDeposito } from "../data/mockRetornos";
import { cantidad_unidad_desde_texto } from "../domain/cantidades";
import { kg_a_gramos } from "../domain/peso";
import {
  precio_valido,
  subtotal_linea,
  sumar_importes,
} from "../domain/precios";
import { calcularStockReservado } from "../hooks/useJornadas";

/** Texto del input de un producto, interpretado en su unidad canónica. */
export type EntradaCarga =
  | { estado: "vacia" }
  | { estado: "valida"; cantidad: number }
  | { estado: "invalida" };

/**
 * Interpreta el texto de carga de un producto. Vacío no carga nada.
 *   - "unidad": entero >= 0; "0" no carga nada (como hasta ahora); decimales
 *     o texto → inválida.
 *   - "peso": kg con coma y hasta 3 decimales, a gramos con kg_a_gramos.
 *     Cero, punto decimal, más de 3 decimales, negativos o texto → inválida.
 * No redondea ni trunca.
 */
export function entrada_carga(
  unidad: UnidadMedida,
  texto: string
): EntradaCarga {
  if (texto.trim() === "") return { estado: "vacia" };

  if (unidad === "unidad") {
    const cantidad = cantidad_unidad_desde_texto(texto);
    if (cantidad === null) return { estado: "invalida" };
    return cantidad === 0
      ? { estado: "vacia" }
      : { estado: "valida", cantidad };
  }

  if (unidad === "peso") {
    const gramos = kg_a_gramos(texto);
    return gramos === null || gramos === 0
      ? { estado: "invalida" }
      : { estado: "valida", cantidad: gramos };
  }

  return { estado: "invalida" };
}

/**
 * Atributos del input de carga según la unidad. Sólo UX: la interpretación
 * del texto es siempre entrada_carga.
 *   - "unidad": input numérico como hasta ahora (type number, min 0, step 1,
 *     max = disponible).
 *   - "peso": texto en kg con coma decimal (type text, inputMode decimal,
 *     placeholder 0,000); un input number no admite la coma.
 * Si el disponible no se puede calcular o es negativo, el input se
 * deshabilita.
 */
export type AtributosInputCarga =
  | {
      type: "number";
      min: "0";
      max: number | undefined;
      step: "1";
      disabled: boolean;
      sufijo: "un.";
    }
  | {
      type: "text";
      inputMode: "decimal";
      placeholder: "0,000";
      disabled: boolean;
      sufijo: "kg";
    };

export function atributos_input_carga(
  unidad: UnidadMedida,
  disponible: number | null
): AtributosInputCarga {
  const disabled = disponible === null || disponible < 0;
  if (unidad === "peso") {
    return {
      type: "text",
      inputMode: "decimal",
      placeholder: "0,000",
      disabled,
      sufijo: "kg",
    };
  }
  return {
    type: "number",
    min: "0",
    max: disponible === null ? undefined : disponible,
    step: "1",
    disabled,
    sufijo: "un.",
  };
}

export type DisponibilidadCarga =
  | { ok: true; disponibles: Record<number, number> }
  | { ok: false };

/**
 * Disponible del depósito por producto (unidades o gramos): stock del
 * catálogo menos el reservado de calcularStockReservado. Sin Math.max: un
 * disponible negativo (catálogo por debajo de lo reservado) se informa como
 * tal. Si el reservado no se puede calcular (overflow o retorno
 * inconsistente), devuelve ok: false y la pantalla no habilita la carga.
 */
export function disponibilidad_carga(
  productos: ReadonlyArray<Producto>,
  jornadas: ReadonlyArray<Jornada>,
  retornos: ReadonlyArray<RetornoDeposito>
): DisponibilidadCarga {
  let reservado: Record<number, number>;
  try {
    reservado = calcularStockReservado(jornadas, retornos);
  } catch {
    return { ok: false };
  }

  const disponibles: Record<number, number> = {};
  for (const producto of productos) {
    disponibles[producto.id] = producto.stock - (reservado[producto.id] ?? 0);
  }
  return { ok: true, disponibles };
}

/**
 * Valor de referencia de una línea `unidad`. Lanza con `peso`: la
 * valorización por peso es D-R1 (B3) y nunca se aproxima.
 */
export function valor_item_unidad(item: ItemCarga): number {
  if (item.unidadMedida !== "unidad") {
    throw new Error("La valorización por peso (D-R1) no está habilitada.");
  }
  return subtotal_linea({
    unidad_medida: "unidad",
    cantidad: item.cantidad,
    precio: item.precioReferencia,
  });
}

/**
 * Total estimado de una carga (P-B2-1): null si hay cualquier línea `peso`;
 * nunca un subtotal parcial de las líneas `unidad`. Ninguna línea `peso` pasa
 * por valor_item_unidad.
 */
export function valor_estimado_carga(
  items: ReadonlyArray<ItemCarga>
): number | null {
  if (items.some((item) => item.unidadMedida !== "unidad")) return null;
  return sumar_importes(items.map(valor_item_unidad));
}

/**
 * Precio de referencia persistible: una línea `unidad` debe poder
 * valorizarse; una línea `peso` sólo exige un precio por kg válido (sin
 * calcular su importe).
 */
export function precio_item_valido(item: ItemCarga): boolean {
  if (item.unidadMedida === "unidad") {
    try {
      valor_item_unidad(item);
      return true;
    } catch {
      return false;
    }
  }
  return precio_valido(item.precioReferencia);
}
