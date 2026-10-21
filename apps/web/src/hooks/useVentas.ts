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

export function useVentas() {
  const [ventas, setVentas] = useState<Venta[]>(cargarVentas);

  function registrarVenta(
    venta: Venta,
    validar: (ventasActuales: Venta[]) => string | null
  ): string | null {
    try {
      // Volvemos a leer las ventas antes de registrar.
      const actuales = cargarVentas();

      if (actuales.some((v) => v.id === venta.id)) {
        return "La venta ya fue registrada.";
      }

      const error = validar(actuales);

      if (error) return error;

      const actualizadas = [...actuales, venta];

      localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify(actualizadas)
      );

      setVentas(actualizadas);

      return null;
    } catch {
      return "No se pudo guardar la venta en este navegador.";
    }
  }

  return {
    ventas,
    registrarVenta,
  };
}