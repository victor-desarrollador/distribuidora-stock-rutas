import { useState } from "react";
import { CLAVES_STORAGE } from "../data/clavesStorage";
import {
  precio_valido,
  subtotal_linea_historica,
  sumar_importes,
  precio_a_centavos,
} from "../domain/precios";
import type { Venta } from "../data/mockVentas";

const STORAGE_KEY = CLAVES_STORAGE.ventas;

function subtotal_coincide(item: Venta["items"][number]): boolean {
  try {
    return (
      subtotal_linea_historica({
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

function total_coincide(venta: Venta): boolean {
  try {
    const subtotales = venta.items.map((item) =>
      subtotal_linea_historica({
        unidad_medida: item.unidadMedida,
        cantidad: item.cantidad,
        precio: item.precioUnitario,
        precio_media_pieza: item.precioMediaPieza,
      })
    );
    const total_calculado = sumar_importes(subtotales);
    // Comparar EXACTAMENTE en centavos usando precio_a_centavos
    // Fallará cerrado si total o calculado tienen >2 decimales, NaN, Infinity o inválidos.
    return precio_a_centavos(total_calculado) === precio_a_centavos(venta.total);
  } catch {
    return false;
  }
}

function item_valido(item: Venta["items"][number]): boolean {
  return (
    item !== null &&
    Number.isSafeInteger(item.productoId) &&
    typeof item.nombreProducto === "string" &&
    ["unidad", "pieza"].includes(item.unidadMedida) &&
    Number.isFinite(item.cantidad) &&
    item.cantidad > 0 &&
    // Historial de precios aplicados (ADR-003): snapshot histórico.
    precio_valido(item.precioUnitario) &&
    (item.unidadMedida === "pieza"
      ? item.precioMediaPieza !== undefined
      : item.precioMediaPieza === undefined) &&
    // Validación de subtotal usando snapshot histórico
    subtotal_coincide(item)
  );
}

function venta_valida(venta: Venta): boolean {
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
    venta.items.every(item_valido) &&
    // Validación de total histórico: el total de la venta debe coincidir
    // con la suma exacta de los subtotales de sus items (ADR-003).
    total_coincide(venta)
  );
}

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