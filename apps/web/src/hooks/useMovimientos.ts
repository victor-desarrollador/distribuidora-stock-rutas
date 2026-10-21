
import { useState } from "react";

import { CLAVES_STORAGE } from "../data/clavesStorage";

import { type MovimientoReparto } from "../data/mockMovimientos";
import { movimiento_valido } from "../domain/movimientos";

const STORAGE_KEY = CLAVES_STORAGE.movimientos;

export function leerMovimientos(): MovimientoReparto[] {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (!guardado) return [];

    const datos: unknown = JSON.parse(guardado);

    if (!Array.isArray(datos)) return [];

    // Misma validación que la escritura (domain/movimientos.ts): falla cerrado.
    const valido = datos.every(movimiento_valido);

    return valido ? datos as MovimientoReparto[] : [];
  } catch {
    return [];
  }
}

/**
 * Operación pura de registro de movimiento: valida, persiste y devuelve el
 * resultado. Separada del hook para ser testeable sin React.
 */
export function registrarMovimientoOperacion(
  movimiento: MovimientoReparto,
  validar: (actuales: MovimientoReparto[]) => string | null,
  cargarActuales: () => MovimientoReparto[],
  guardarActualizados: (movimientos: MovimientoReparto[]) => void
): string | null {
  // 1. Cantidades y estructura ANTES de cualquier efecto: no se corrige,
  // trunca ni redondea nada.
  if (!movimiento_valido(movimiento)) {
    return "El movimiento no es válido: las cantidades deben ser enteros positivos.";
  }

  const actuales = cargarActuales();

  if (actuales.some((m) => m.id === movimiento.id)) {
    return "Este movimiento ya está registrado.";
  }

  const error = validar(actuales);

  if (error) return error;

  guardarActualizados([...actuales, movimiento]);

  return null;
}

export function useMovimientos() {
  const [movimientos, setMovimientos] =
    useState<MovimientoReparto[]>(leerMovimientos);

  function registrarMovimiento(
    movimiento: MovimientoReparto,
    validar: (actuales: MovimientoReparto[]) => string | null
  ): string | null {
    try {
      return registrarMovimientoOperacion(
        movimiento,
        validar,
        leerMovimientos,
        (nuevos) => {
          localStorage.setItem(STORAGE_KEY, JSON.stringify(nuevos));
          setMovimientos(nuevos);
        }
      );
    } catch {
      return "No se pudo guardar el movimiento.";
    }
  }

  return {
    movimientos,
    registrarMovimiento,
  };
}
