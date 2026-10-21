
import { useState } from "react";

import { CLAVES_STORAGE } from "../data/clavesStorage";

import {
  type MovimientoReparto,
  type ProductoMovimiento,
} from "../data/mockMovimientos";
import type { UnidadMedida } from "../data/mockProductos";

const STORAGE_KEY = CLAVES_STORAGE.movimientos;

export function leerMovimientos(): MovimientoReparto[] {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (!guardado) return [];

    const datos: unknown = JSON.parse(guardado);

    if (!Array.isArray(datos)) return [];

    const esProducto = (p: unknown): p is Partial<ProductoMovimiento> =>
      typeof p === "object" && p !== null;

    // Validador estructural equivalente al original (sin `any`):
    // chequea en runtime cada campo antes de leerlo.
    const productoValido = (p: unknown) => {
      if (!esProducto(p)) return false;

      const { productoId, nombreProducto, unidadMedida, cantidad } = p;

      return (
        Number.isSafeInteger(productoId) &&
        typeof nombreProducto === "string" &&
        ["unidad", "pieza"].includes(
          unidadMedida as UnidadMedida
        ) &&
        Number.isFinite(cantidad) &&
        (cantidad as number) > 0
      );
    };

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
