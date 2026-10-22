import { useState } from "react";
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

    // Misma validación estructural/monetaria que la escritura (ADR-003).
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

/**
 * Operación pura de registro de venta: valida, persiste y devuelve resultado.
 * Separada del hook para ser testeable sin React.
 * NO usa useState ni efectos de React.
 *
 * Orden: 1) venta_valida, 2) lectura discriminada (corrupto → abortar sin
 * llamar a `validar`), 3) duplicado, 4) callback de stock, 5) persistir.
 */
export function registrarVentaOperacion(
  venta: Venta,
  validar: (ventasActuales: Venta[]) => string | null,
  cargarActuales: () => ResultadoLecturaVentas,
  guardarActualizadas: (ventas: Venta[]) => void
): string | null {
  // 1. Validación monetaria y estructural ANTES de cualquier efecto lateral (M-1).
  // Usa la MISMA validación compartida que la lectura (domain/validacion.ts).
  if (!venta_valida(venta)) {
    return "La venta no pasa la validación monetaria/estructural (ADR-003).";
  }

  // 2. Leer ventas actuales; un storage corrupto NO es un ledger vacío.
  const lectura = cargarActuales();

  if (!lectura.ok) {
    return `No se puede registrar: ${lectura.error}`;
  }

  const actuales = lectura.ventas;

  if (actuales.some((v) => v.id === venta.id)) {
    return "La venta ya fue registrada.";
  }

  // 3. Validación externa de disponibilidad/stock.
  const error = validar(actuales);

  if (error) return error;

  // 4. Persistencia SOLO si todo pasa.
  const actualizadas = [...actuales, venta];
  guardarActualizadas(actualizadas);

  return null;
}

/**
 * Frontera REAL de escritura sin React: es lo que ejecuta el hook. Con el
 * storage corrupto no escribe nada ni llama a `validar`.
 */
export function registrarVentaPersistida(
  venta: Venta,
  validar: (ventasActuales: Venta[]) => string | null,
  alGuardar?: (ventas: Venta[]) => void
): string | null {
  try {
    return registrarVentaOperacion(venta, validar, leerVentas, (nuevas) => {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(nuevas));
      alGuardar?.(nuevas);
    });
  } catch {
    return "No se pudo guardar la venta en este navegador.";
  }
}

export function useVentas() {
  // Una sola lectura discriminada al montar: de ahí salen el estado y, solo si
  // no está corrupto, los datos. La UI usa `estadoLectura` para avisar.
  const [lectura] = useState(leerVentas);
  const [ventas, setVentas] = useState<Venta[]>(
    lectura.ok ? lectura.ventas : []
  );

  function registrarVenta(
    venta: Venta,
    validar: (ventasActuales: Venta[]) => string | null
  ): string | null {
    return registrarVentaPersistida(venta, validar, setVentas);
  }

  return {
    ventas,
    registrarVenta,
    estadoLectura: lectura.estado,
  };
}
