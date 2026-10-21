import { useState } from "react";
import { CLAVES_STORAGE } from "../data/clavesStorage";
import type { Venta } from "../data/mockVentas";
import { venta_valida } from "../domain/validacion";

const STORAGE_KEY = CLAVES_STORAGE.ventas;

export function cargarVentas(): Venta[] {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (!guardado) return [];

    const datos: unknown = JSON.parse(guardado);

    if (!Array.isArray(datos)) return [];

    // Validación básica para el prototipo.
    const validos = datos.every(venta_valida);

    return validos ? (datos as Venta[]) : [];
  } catch {
    return [];
  }
}

/**
 * Operación pura de registro de venta: valida, persiste y devuelve resultado.
 * Separada del hook para ser testeable sin React.
 * NO usa useState ni efectos de React.
 */
export function registrarVentaOperacion(
  venta: Venta,
  validar: (ventasActuales: Venta[]) => string | null,
  cargarActuales: () => Venta[],
  guardarActualizadas: (ventas: Venta[]) => void
): string | null {
  // 1. Validación monetaria y estructural ANTES de cualquier efecto lateral (M-1).
  // Usa la MISMA validación compartida que cargarVentas (domain/validacion.ts).
  if (!venta_valida(venta)) {
    return "La venta no pasa la validación monetaria/estructural (ADR-003).";
  }

  // 2. Leer ventas actuales.
  const actuales = cargarActuales();

  if (actuales.some((v) => v.id === venta.id)) {
    return "La venta ya fue registrada.";
  }

  // 3. Validación externa de disponibilidad/stock.
  const error = validar(actuales);

  if (error) return error;

  // 4. Persistencia SOLO si ambas validaciones pasan.
  const actualizadas = [...actuales, venta];
  guardarActualizadas(actualizadas);

  return null;
}

export function useVentas() {
  const [ventas, setVentas] = useState<Venta[]>(cargarVentas);

  function registrarVenta(
    venta: Venta,
    validar: (ventasActuales: Venta[]) => string | null
  ): string | null {
    try {
      return registrarVentaOperacion(
        venta,
        validar,
        cargarVentas,
        (nuevas) => {
          localStorage.setItem(STORAGE_KEY, JSON.stringify(nuevas));
          setVentas(nuevas);
        }
      );
    } catch {
      return "No se pudo guardar la venta en este navegador.";
    }
  }

  return {
    ventas,
    registrarVenta,
  };
}
