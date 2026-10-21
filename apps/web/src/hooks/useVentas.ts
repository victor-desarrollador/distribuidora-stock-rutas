
import { useState } from "react";
import { CLAVES_STORAGE } from "../data/clavesStorage";
import {
  precios_producto_validos,
  subtotal_linea,
} from "../domain/precios";
import type { Venta } from "../data/mockVentas";

const STORAGE_KEY = CLAVES_STORAGE.ventas;

function subtotal_coincide(item: Venta["items"][number]): boolean {
  try {
    return (
      subtotal_linea({
        unidad_medida: item.unidadMedida,
        cantidad: item.cantidad,
        precio: item.precioUnitario,
        precio_media_pieza: item.precioMediaPieza,
      }) === item.subtotal
    );
  } catch {
    return false;
  }
}

export function cargarVentas(): Venta[] {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (!guardado) return [];

    const datos: unknown = JSON.parse(guardado);

    if (!Array.isArray(datos)) return [];

    // Validación básica para el prototipo.
    const validos = datos.every((venta) => {
      if (!venta || typeof venta !== "object") {
        return false;
      }

      return (
        typeof venta.id === "string" &&
        typeof venta.jornadaId === "string" &&
        Number.isSafeInteger(venta.camionId) &&
        Number.isSafeInteger(venta.clienteId) &&
        typeof venta.nombreCliente === "string" &&
        typeof venta.fecha === "string" &&
        ["efectivo", "transferencia", "cuenta_corriente"].includes(
          venta.medioPago
        ) &&
        Array.isArray(venta.items) &&
        Number.isFinite(venta.total) &&
        venta.total >= 0 &&
        venta.items.every(
          (item: Venta["items"][number]) =>
            item !== null &&
            Number.isSafeInteger(item.productoId) &&
            typeof item.nombreProducto === "string" &&
            ["unidad", "pieza"].includes(item.unidadMedida) &&
            Number.isFinite(item.cantidad) &&
            item.cantidad > 0 &&
            // Historial de precios aplicados (ADR-002): el subtotal debe
            // coincidir con la función de dominio.
            precios_producto_validos({
              unidad_medida: item.unidadMedida,
              precio: item.precioUnitario,
              precio_media_pieza: item.precioMediaPieza,
            }) &&
            subtotal_coincide(item)
        )
      );
    });

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
