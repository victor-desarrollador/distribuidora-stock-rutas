
import { useState } from "react";

import {
  type MovimientoReparto,
} from "../data/mockMovimientos";

const STORAGE_KEY = "distribuidora_movimientos_demo_v1";

export function leerMovimientos(): MovimientoReparto[] {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (!guardado) return [];

    const datos: unknown = JSON.parse(guardado);

    if (!Array.isArray(datos)) return [];

    const productoValido = (p: any) =>
      p !== null &&
      typeof p === "object" &&
      Number.isSafeInteger(p.productoId) &&
      typeof p.nombreProducto === "string" &&
      ["unidad", "pieza", "kg"].includes(p.unidadMedida) &&
      Number.isFinite(p.cantidad) &&
      p.cantidad > 0;

    const valido = datos.every((m) => {
      if (!m || typeof m !== "object") return false;

      const baseValida =
        typeof m.id === "string" &&
        typeof m.jornadaId === "string" &&
        Number.isSafeInteger(m.camionId) &&
        typeof m.fecha === "string" &&
        typeof m.motivo === "string";

      if (!baseValida) return false;

      if (m.tipo === "merma") {
        return (
          m.clienteId === null &&
          m.nombreCliente === null &&
          productoValido(m.producto)
        );
      }

      const clienteValido =
        Number.isSafeInteger(m.clienteId) &&
        typeof m.nombreCliente === "string";

      if (!clienteValido) return false;

      if (m.tipo === "devolucion") {
        return productoValido(m.producto);
      }

      if (m.tipo === "cambio") {
        return (
          productoValido(m.productoDevuelto) &&
          productoValido(m.productoEntregado)
        );
      }

      return false;
    });

    return valido ? datos as MovimientoReparto[] : [];
  } catch {
    return [];
  }
}

export function useMovimientos() {
  const [movimientos, setMovimientos] =
    useState<MovimientoReparto[]>(leerMovimientos);

  function registrarMovimiento(
    movimiento: MovimientoReparto,
    validar: (actuales: MovimientoReparto[]) => string | null
  ): string | null {
    try {
      const actuales = leerMovimientos();

      if (actuales.some((m) => m.id === movimiento.id)) {
        return "Este movimiento ya está registrado.";
      }

      const error = validar(actuales);

      if (error) return error;

      const actualizados = [...actuales, movimiento];

      localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify(actualizados)
      );

      setMovimientos(actualizados);

      return null;
    } catch {
      return "No se pudo guardar el movimiento.";
    }
  }

  return {
    movimientos,
    registrarMovimiento,
  };
}
