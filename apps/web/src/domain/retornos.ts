// Dominio puro de Retornos del prototipo (recepción de sobrante vendible de
// una jornada cerrada). Sin React, sin persistencia, sin Supabase ni RPC.
//
// Fuente: BLUEPRINT.md §7.1 y §7.4 (cantidades enteras en la unidad mínima;
// ADR-005).
//
// Semántica conservada del prototipo:
//   - cantidadContada: vendible contado al cierre.
//   - cantidadAprobada: parte aprobada para volver al depósito.
//   - pendiente = contada - aprobada (sin clasificación sanitaria).
//
// Todas las cantidades son enteros seguros en la unidad mínima: unidades
// enteras para "unidad", gramos para "peso". Sin tolerancias, sin redondeo,
// sin truncado. Reutiliza domain/cantidades.ts. En B1 la entrada de UI sólo
// admite "unidad": los retornos `peso` se habilitan en B4.

import type {
  ItemRetorno,
  RetornoDeposito,
} from "../data/mockRetornos";
import {
  cantidad_unidad_desde_texto,
  es_cantidad_valida,
} from "./cantidades";

type Unidad = ItemRetorno["unidadMedida"];

/** Entrada de UI de una cantidad: texto del input entero ("unidad"). */
export interface EntradaRetorno {
  texto: string;
}

function unidad_soportada(u: unknown): u is Unidad {
  return u === "unidad" || u === "peso";
}

/**
 * Item válido en storage: `unidad` o `peso` (gramos), enteros seguros y
 * 0 <= aprobada <= contada. `pieza` y cualquier otra unidad se rechazan.
 */
export function item_retorno_valido(item: unknown): item is ItemRetorno {
  if (typeof item !== "object" || item === null) return false;
  const i = item as Partial<ItemRetorno>;

  return (
    Number.isSafeInteger(i.productoId) &&
    typeof i.nombreProducto === "string" &&
    unidad_soportada(i.unidadMedida) &&
    typeof i.cantidadContada === "number" &&
    typeof i.cantidadAprobada === "number" &&
    es_cantidad_valida(i.cantidadContada) &&
    es_cantidad_valida(i.cantidadAprobada) &&
    i.cantidadAprobada <= i.cantidadContada
  );
}

/**
 * Retorno válido. Misma regla para lectura y escritura. En escritura nueva se
 * exige `exigir_responsable` (la lectura de datos guardados no lo exige).
 */
export function retorno_valido(
  r: unknown,
  opciones: { exigir_responsable?: boolean } = {}
): r is RetornoDeposito {
  if (typeof r !== "object" || r === null) return false;
  const x = r as Record<string, unknown>;

  if (
    typeof x.id !== "string" ||
    x.id.trim() === "" ||
    typeof x.jornadaId !== "string" ||
    x.jornadaId.trim() === "" ||
    !Number.isSafeInteger(x.camionId) ||
    typeof x.fecha !== "string" ||
    typeof x.responsable !== "string" ||
    typeof x.observaciones !== "string" ||
    !Array.isArray(x.items)
  ) {
    return false;
  }

  if (opciones.exigir_responsable && x.responsable.trim() === "") return false;

  if (!x.items.every(item_retorno_valido)) return false;

  const ids = (x.items as ItemRetorno[]).map((i) => i.productoId);
  return new Set(ids).size === ids.length;
}

/**
 * Cantidad contada al cierre como cantidad canónica, o null si el dato del
 * cierre no es un entero seguro >= 0 (no se corrige ni reinterpreta).
 */
export function contado_desde_cierre(valor: unknown): number | null {
  return typeof valor === "number" && es_cantidad_valida(valor) ? valor : null;
}

/** pendiente = contado - aprobado, exacto. Lanza si algún dato es inválido. */
export function pendiente_retorno(contado: number, aprobado: number): number {
  if (
    !es_cantidad_valida(contado) ||
    !es_cantidad_valida(aprobado) ||
    aprobado > contado
  ) {
    throw new Error(
      `Retorno inválido: contado ${String(contado)}, aprobado ${String(aprobado)}.`
    );
  }
  return contado - aprobado;
}

/** La entrada está vacía. */
export function entrada_vacia(entrada: EntradaRetorno): boolean {
  return entrada.texto.trim() === "";
}

/**
 * Convierte la entrada de UI en cantidad aprobada canónica, o null si es
 * inválida o excede lo contado. 0 es válido. No lanza.
 */
export function cantidad_aprobada_desde_entrada(
  unidad: Unidad,
  entrada: EntradaRetorno,
  contado: number
): number | null {
  // B1: `peso` no es operable todavía (B4); falla cerrado.
  if (unidad !== "unidad") return null;
  if (!es_cantidad_valida(contado)) return null;

  const canonica = cantidad_unidad_desde_texto(entrada.texto);
  if (canonica === null) return null;

  return canonica <= contado ? canonica : null;
}

/**
 * Reconstruye la entrada de UI desde una cantidad canónica (completar con
 * contado, mostrar una recepción existente). null si la cantidad es inválida.
 */
export function entrada_desde_cantidad(
  unidad: Unidad,
  cantidad: number
): EntradaRetorno | null {
  // B1: `peso` no tiene entrada de UI todavía (B4).
  if (unidad !== "unidad") return null;
  if (!es_cantidad_valida(cantidad)) return null;
  return { texto: String(cantidad) };
}

/**
 * El conteo del cierre no cambió respecto de lo contado al preparar el
 * retorno. Ambos deben ser cantidades canónicas seguras; si no, falla cerrado.
 */
export function cierre_sin_cambios(
  cantidad_actual: unknown,
  contada: number
): boolean {
  const actual = contado_desde_cierre(cantidad_actual);
  return actual !== null && es_cantidad_valida(contada) && actual === contada;
}
