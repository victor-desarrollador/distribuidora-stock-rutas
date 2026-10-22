// Dominio puro de Retornos del prototipo (recepción de sobrante vendible de
// una jornada cerrada). Sin React, sin persistencia, sin Supabase ni RPC.
//
// Fuente: BLUEPRINT.md §7.1 (cantidades enteras; pieza en medias piezas) y
// docs/requirements/migracion-unidades-prototipo.md §5 y §8.
//
// Semántica conservada del prototipo:
//   - cantidadContada: vendible contado al cierre.
//   - cantidadAprobada: parte aprobada para volver al depósito.
//   - pendiente = contada - aprobada (sin clasificación sanitaria).
//
// Todas las cantidades son enteros seguros en la unidad mínima: unidades
// enteras para "unidad", medias piezas para "pieza". Sin tolerancias, sin
// redondeo, sin truncado. Reutiliza domain/cantidades.ts.

import type {
  ItemRetorno,
  RetornoDeposito,
} from "../data/mockRetornos";
import {
  cantidad_unidad_desde_texto,
  descomponer_medias,
  es_cantidad_valida,
  medias_a_texto,
  puede_agregar_media,
  recomponer_medias,
} from "./cantidades";

type Unidad = ItemRetorno["unidadMedida"];

/** Entrada de UI de una cantidad: texto del input entero + media opcional. */
export interface EntradaRetorno {
  /** "unidad": cantidad entera. "pieza": piezas completas. */
  texto: string;
  /** Solo "pieza". En "unidad" debe ser false. */
  media: boolean;
}

function unidad_soportada(u: unknown): u is Unidad {
  return u === "unidad" || u === "pieza";
}

/** Item válido: unidad soportada (sin kg), enteros seguros y 0 <= aprobada <= contada. */
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

/** La entrada está vacía: no se completó ni piezas ni media. */
export function entrada_vacia(entrada: EntradaRetorno): boolean {
  return entrada.texto.trim() === "" && !entrada.media;
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
  if (!es_cantidad_valida(contado)) return null;

  const base = cantidad_unidad_desde_texto(entrada.texto);
  if (base === null) return null;

  let canonica: number;
  if (unidad === "pieza") {
    try {
      canonica = recomponer_medias({ piezas: base, media: entrada.media });
    } catch {
      return null;
    }
  } else if (unidad === "unidad") {
    if (entrada.media) return null;
    canonica = base;
  } else {
    return null;
  }

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
  if (!es_cantidad_valida(cantidad)) return null;
  if (unidad === "pieza") {
    const { piezas, media } = descomponer_medias(cantidad);
    return { texto: String(piezas), media };
  }
  return { texto: String(cantidad), media: false };
}

/** ¿Todavía entra una media pieza más sin superar lo contado? */
export function media_aprobable(contado: number, texto_piezas: string): boolean {
  const piezas = cantidad_unidad_desde_texto(texto_piezas);
  return piezas !== null && puede_agregar_media(contado, piezas);
}

/** Presentación legible: unidad → "3 un."; pieza → medias_a_texto. */
export function cantidad_a_texto(unidad: Unidad, cantidad: number): string {
  return unidad === "pieza" ? medias_a_texto(cantidad) : `${cantidad} un.`;
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
