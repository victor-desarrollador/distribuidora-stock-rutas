// Lectura discriminada del ledger de ventas. Módulo hoja: no importa otros
// hooks, para que la frontera de escritura pueda leer Jornadas y Movimientos
// sin ciclos de importación (AUD-001).
import { CLAVES_STORAGE } from "../data/clavesStorage";
import type { Venta } from "../data/mockVentas";
import { venta_valida } from "../domain/validacion";

const STORAGE_KEY = CLAVES_STORAGE.ventas;

/** Resultado discriminado de la lectura del ledger de ventas. */
export type ResultadoLecturaVentas =
  | { ok: true; ventas: Venta[]; estado: "inicial" | "valido" }
  | { ok: false; estado: "corrupto"; error: string };

/**
 * Lectura discriminada: clave ausente (getItem === null → ledger inicial []),
 * válida, o presente pero corrupta ("", "null", JSON inválido, no array o
 * venta inválida según `venta_valida`). Es la autoridad de toda escritura
 * (también la usa useCobros para calcular saldos).
 */
export function leerVentas(): ResultadoLecturaVentas {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (guardado === null) {
      return { ok: true, ventas: [], estado: "inicial" };
    }

    let datos: unknown;
    try {
      datos = JSON.parse(guardado);
    } catch {
      return {
        ok: false,
        estado: "corrupto",
        error: "JSON inválido en almacenamiento de ventas.",
      };
    }

    if (!Array.isArray(datos)) {
      return {
        ok: false,
        estado: "corrupto",
        error: "Estructura inválida: se esperaba un array de ventas.",
      };
    }

    // Validación histórica (ADR-005 §2.3.4): estructura y total = suma de
    // subtotales almacenados, sin recalcular. La escritura de una venta nueva
    // exige además la regla vigente (`venta_nueva_valida`).
    if (!datos.every(venta_valida)) {
      return {
        ok: false,
        estado: "corrupto",
        error: "Una o más ventas no pasan la validación.",
      };
    }

    return { ok: true, ventas: datos as Venta[], estado: "valido" };
  } catch (e) {
    return {
      ok: false,
      estado: "corrupto",
      error: `Error inesperado al leer ventas: ${String(e)}`,
    };
  }
}

/**
 * Lectura para UI: fail-closed visual ([] si está ausente o corrupto).
 * NO usar como autoridad en una escritura.
 */
export function cargarVentas(): Venta[] {
  const lectura = leerVentas();
  return lectura.ok ? lectura.ventas : [];
}
