
import { useState } from "react";

import { CLAVES_STORAGE } from "../data/clavesStorage";

import { type MovimientoReparto } from "../data/mockMovimientos";
import { movimiento_valido } from "../domain/movimientos";
import { MENSAJE_PESO_NO_OPERABLE } from "../domain/productos";

const STORAGE_KEY = CLAVES_STORAGE.movimientos;

/** Resultado discriminado de la lectura del ledger de movimientos. */
export type ResultadoLecturaMovimientos =
  | { ok: true; movimientos: MovimientoReparto[]; estado: "valido" | "inicial" }
  | { ok: false; error: string; estado: "corrupto" };

/**
 * Lectura que distingue explícitamente:
 * - clave ausente: ledger inicial válido ([])
 * - clave presente y válida: movimientos cargados
 * - clave presente pero corrupta: error explícito
 * Es la única autoridad tanto para la frontera de escritura como para el
 * estado que la UI usa para advertir corrupción.
 */
export function leerMovimientosDiscriminado(): ResultadoLecturaMovimientos {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (guardado === null) {
      return { ok: true, movimientos: [], estado: "inicial" };
    }

    let datos: unknown;
    try {
      datos = JSON.parse(guardado);
    } catch {
      return {
        ok: false,
        error: "JSON inválido en almacenamiento de movimientos.",
        estado: "corrupto",
      };
    }

    if (!Array.isArray(datos)) {
      return {
        ok: false,
        error: "Estructura inválida: se esperaba un array de movimientos.",
        estado: "corrupto",
      };
    }

    const valido = datos.every(movimiento_valido);

    if (!valido) {
      return {
        ok: false,
        error: "Uno o más movimientos no pasan la validación estructural.",
        estado: "corrupto",
      };
    }

    return { ok: true, movimientos: datos as MovimientoReparto[], estado: "valido" };
  } catch (e) {
    return {
      ok: false,
      error: `Error inesperado al leer movimientos: ${String(e)}`,
      estado: "corrupto",
    };
  }
}

/**
 * Lectura para UI: comportamiento visual fail-closed.
 * Devuelve [] tanto para ausente como para corrupto (semántica existente).
 * NO usar en la frontera de escritura.
 */
export function leerMovimientos(): MovimientoReparto[] {
  const lectura = leerMovimientosDiscriminado();
  return lectura.ok ? lectura.movimientos : [];
}

/**
 * Operación pura de registro de movimiento: valida, persiste y devuelve el
 * resultado. Separada del hook para ser testeable sin React.
 *
 * @param cargarActuales - Función que devuelve el estado actual con discriminación de corrupción.
 *   En producción usa `leerMovimientosDiscriminado()`. En tests puede inyectarse un mock.
 */
export function registrarMovimientoOperacion(
  movimiento: MovimientoReparto,
  validar: (actuales: MovimientoReparto[]) => string | null,
  cargarActuales: () => ResultadoLecturaMovimientos,
  guardarActualizados: (movimientos: MovimientoReparto[]) => void
): string | null {
  // 1. Validación estructural y de cantidades ANTES de cualquier efecto.
  if (!movimiento_valido(movimiento)) {
    return "El movimiento no es válido: las cantidades deben ser enteros positivos y seguros.";
  }

  // 1b. B1: los movimientos de productos `peso` no están migrados (B2).
  const productos =
    movimiento.tipo === "cambio"
      ? [movimiento.productoDevuelto, movimiento.productoEntregado]
      : [movimiento.producto];
  if (productos.some((p) => p.unidadMedida !== "unidad")) {
    return MENSAJE_PESO_NO_OPERABLE;
  }

  // 2. Cargar estado previo con discriminación de corrupción (usa función inyectada).
  const lectura = cargarActuales();

  // 2b. Si el almacenamiento está corrupto, ABORTAR antes de cualquier efecto lateral.
  if (!lectura.ok) {
    return `No se puede registrar: ${lectura.error}`;
  }

  const actuales = lectura.movimientos;

  // 3. Duplicado por ID.
  if (actuales.some((m) => m.id === movimiento.id)) {
    return "Este movimiento ya está registrado.";
  }

  // 4. Validación externa de stock/disponibilidad.
  const error = validar(actuales);

  if (error) return error;

  // 5. Persistencia SOLO si todo pasa.
  guardarActualizados([...actuales, movimiento]);

  return null;
}

/**
 * Frontera REAL de escritura sin React: lee el ledger de localStorage con
 * discriminación de corrupción, valida y persiste. Es lo que ejecuta el hook.
 * Si el almacenamiento está corrupto no escribe nada (no lo reinterpreta
 * como vacío ni lo pisa con solo el movimiento nuevo).
 */
export function registrarMovimientoPersistido(
  movimiento: MovimientoReparto,
  validar: (actuales: MovimientoReparto[]) => string | null,
  alGuardar?: (nuevos: MovimientoReparto[]) => void
): string | null {
  try {
    return registrarMovimientoOperacion(
      movimiento,
      validar,
      leerMovimientosDiscriminado,
      (nuevos) => {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(nuevos));
        alGuardar?.(nuevos);
      }
    );
  } catch {
    return "No se pudo guardar el movimiento.";
  }
}

export function useMovimientos() {
  const [lectura] = useState(leerMovimientosDiscriminado);
  const [movimientos, setMovimientos] = useState<MovimientoReparto[]>(
    lectura.ok ? lectura.movimientos : []
  );

  function registrarMovimiento(
    movimiento: MovimientoReparto,
    validar: (actuales: MovimientoReparto[]) => string | null
  ): string | null {
    return registrarMovimientoPersistido(movimiento, validar, setMovimientos);
  }

  return {
    movimientos,
    registrarMovimiento,
    estadoLectura: lectura.estado,
  };
}
