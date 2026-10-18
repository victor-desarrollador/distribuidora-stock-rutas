// Cálculos puros de la pantalla de rendición de mercadería.
//
// Vive fuera de `Rendicion.tsx` a propósito: la pantalla es un componente y no
// debe exportar funciones puras (regla `react-refresh/only-export-components`),
// y así los cálculos se pueden probar sin montar React.
//
// Sin dependencias de infraestructura: no toca stock, dinero, persistencia,
// localStorage, Supabase, RPC, RLS ni migraciones. No modifica datos.
//
// Fuente: BLUEPRINT.md §2 y §7.1 (unidad / pieza / media pieza; nunca
// kilogramo) y §7.4 (salidas del camión).
//
// Reglas:
//   - `unidad`: se concilia con el dominio canónico (`calcular_esperado`,
//     `calcular_diferencia`); cantidades enteras >= 0.
//   - `pieza`: el prototipo legacy guarda PIEZAS ENTERAS, no medias piezas. El
//     dominio exige medias piezas como unidad mínima, así que esa
//     representación NO es conciliable: la fila se marca `pieza_legacy`, no se
//     llama al dominio y NO se convierte nada. Requiere migración a medias
//     piezas antes de poder cerrar (fuera de esta tarea).
//   - cualquier otra unidad (kilogramo): no soportada por el negocio; no tiene
//     camino funcional en la pantalla.

import type { ItemCarga } from "../data/mockJornadas";
import { es_cantidad_valida } from "../domain/cantidades";
import {
  calcular_diferencia,
  calcular_esperado,
} from "../domain/rendicion";

/** Aviso visible cuando la jornada tiene productos por pieza legacy. */
export const MENSAJE_PIEZA_LEGACY =
  "Los productos por pieza todavía usan la representación legacy. Deben migrarse a medias piezas antes de poder cerrar la rendición.";

export type EstadoFilaMercaderia =
  /** Conciliable con el dominio canónico. */
  | "ok"
  /** `unidad` inconsistente: componentes inválidos o salidas > cargado. */
  | "inconsistente"
  /** `pieza` en representación legacy; requiere migración a medias piezas. */
  | "pieza_legacy"
  /** Unidad fuera del dominio (por ejemplo kilogramo). */
  | "no_soportada";

export interface EntradaFilaMercaderia {
  item: ItemCarga;
  vendido: number;
  merma: number;
  reemplazos: number;
  contadoTexto: string | undefined;
}

export interface FilaMercaderia {
  productoId: number;
  nombreProducto: string;
  unidadMedida: ItemCarga["unidadMedida"];
  cargado: number;
  vendido: number;
  merma: number;
  reemplazos: number;
  esperado: number | null;
  contado: number | null;
  diferencia: number | null;
  estado: EstadoFilaMercaderia;
}

/** Lee un número finito >= 0 de un texto; `null` si está vacío o es inválido. */
export function leerCantidad(
  texto: string | undefined
): number | null {
  if (texto === undefined || texto.trim() === "") {
    return null;
  }

  const cantidad = Number(texto);

  return Number.isFinite(cantidad) && cantidad >= 0
    ? cantidad
    : null;
}

/**
 * Conteo almacenable: entero >= 0 (BLUEPRINT §7.4). Devuelve `null` si el texto
 * está vacío, no es numérico, es negativo o tiene decimales.
 */
export function conteoValido(
  texto: string | undefined
): number | null {
  const cantidad = leerCantidad(texto);

  return cantidad !== null && es_cantidad_valida(cantidad)
    ? cantidad
    : null;
}

/**
 * Calcula la fila de mercadería de una jornada.
 *
 * No lanza hacia React: si las salidas superan lo cargado o hay componentes
 * inválidos, devuelve la fila marcada como `inconsistente`.
 */
export function calcularFilaMercaderia(
  entrada: EntradaFilaMercaderia
): FilaMercaderia {
  const { item, vendido, merma, reemplazos, contadoTexto } =
    entrada;
  const contado = conteoValido(contadoTexto);

  const base = {
    productoId: item.productoId,
    nombreProducto: item.nombreProducto,
    unidadMedida: item.unidadMedida,
    cargado: item.cantidad,
    vendido,
    merma,
    reemplazos,
    contado,
  };

  if (item.unidadMedida === "pieza") {
    // Representación legacy (piezas enteras): NO es conciliable con el dominio
    // canónico y NO se convierte a medias piezas. No se llama al dominio.
    return {
      ...base,
      esperado: null,
      diferencia: null,
      estado: "pieza_legacy",
    };
  }

  if (item.unidadMedida !== "unidad") {
    // Kilogramo u otra unidad fuera del Blueprint: sin camino funcional.
    return {
      ...base,
      esperado: null,
      diferencia: null,
      estado: "no_soportada",
    };
  }

  // `unidad`: dominio canónico.
  const componentesValidos =
    es_cantidad_valida(item.cantidad) &&
    es_cantidad_valida(vendido) &&
    es_cantidad_valida(merma) &&
    es_cantidad_valida(reemplazos);

  if (!componentesValidos) {
    return {
      ...base,
      esperado: null,
      diferencia: null,
      estado: "inconsistente",
    };
  }

  let esperado: number;

  try {
    esperado = calcular_esperado({
      cargado: item.cantidad,
      vendido,
      merma,
      otras_salidas: reemplazos,
    });
  } catch {
    // Salidas > cargado: inconsistencia sin romper el render.
    return {
      ...base,
      esperado: null,
      diferencia: null,
      estado: "inconsistente",
    };
  }

  return {
    ...base,
    esperado,
    diferencia:
      contado === null
        ? null
        : calcular_diferencia(contado, esperado),
    estado: "ok",
  };
}

/**
 * Una jornada solo se puede rendir si todas sus filas quedaron conciliables.
 * Bloquea «Completar con esperados» y «Confirmar cierre» cuando hay filas
 * inconsistentes, por pieza legacy o con unidad no soportada.
 */
export function bloqueaRendicion(
  filas: FilaMercaderia[]
): boolean {
  return filas.some((fila) => fila.estado !== "ok");
}
