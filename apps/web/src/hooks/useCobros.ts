
import { useState } from "react";
import type { Cobro } from "../data/mockCobros";
import type { Venta } from "../data/mockVentas";

const CLAVE_COBROS = "distribuidora_cobros_demo_v2";
const CLAVE_VENTAS = "distribuidora_ventas_demo_v2";

function redondearDinero(valor: number) {
  return Math.round(valor * 100) / 100;
}

export function leerCobros(): Cobro[] {
  try {
    const texto = localStorage.getItem(CLAVE_COBROS);
    if (!texto) return [];

    const datos: unknown = JSON.parse(texto);
    if (!Array.isArray(datos)) return [];

    const validos = datos.every((c) =>
      c !== null &&
      typeof c === "object" &&
      typeof c.id === "string" &&
      Number.isSafeInteger(c.clienteId) &&
      typeof c.nombreCliente === "string" &&
      (c.jornadaId === null ||
        typeof c.jornadaId === "string") &&
      typeof c.fecha === "string" &&
      Number.isFinite(c.importe) &&
      c.importe > 0 &&
      Math.abs(c.importe * 100 - Math.round(c.importe * 100)) <
        0.000001 &&
      ["efectivo", "transferencia"].includes(c.medio) &&
      typeof c.referencia === "string" &&
      typeof c.observaciones === "string"
    );

    return validos ? (datos as Cobro[]) : [];
  } catch {
    return [];
  }
}

function leerVentasActuales(): Venta[] | null {
  try {
    const texto = localStorage.getItem(CLAVE_VENTAS);
    if (!texto) return [];

    const datos: unknown = JSON.parse(texto);
    if (!Array.isArray(datos)) return null;

    const validas = datos.every((v) =>
      v !== null &&
      typeof v === "object" &&
      Number.isSafeInteger(v.clienteId) &&
      Number.isFinite(v.total) &&
      v.total >= 0 &&
      ["efectivo", "transferencia", "cuenta_corriente"].includes(
        v.medioPago
      )
    );

    return validas ? (datos as Venta[]) : null;
  } catch {
    return null;
  }
}

export function calcularSaldoCliente(
  clienteId: number,
  ventas: Venta[],
  cobros: Cobro[]
): number {
  const deuda = ventas
    .filter(
      (v) =>
        v.clienteId === clienteId &&
        v.medioPago === "cuenta_corriente"
    )
    .reduce((total, venta) => total + venta.total, 0);

  const pagado = cobros
    .filter((c) => c.clienteId === clienteId)
    .reduce((total, cobro) => total + cobro.importe, 0);

  return redondearDinero(deuda - pagado);
}

export function useCobros() {
  const [cobros, setCobros] = useState<Cobro[]>(leerCobros);

  function registrarCobro(cobro: Cobro): string | null {
    try {
      if (
        !Number.isSafeInteger(cobro.clienteId) ||
        !Number.isFinite(cobro.importe) ||
        cobro.importe <= 0 ||
        Math.abs(
          cobro.importe * 100 -
          Math.round(cobro.importe * 100)
        ) > 0.000001 ||
        !["efectivo", "transferencia"].includes(cobro.medio)
      ) {
        return "Los datos del cobro no son válidos.";
      }

      if (
        cobro.medio === "transferencia" &&
        !cobro.referencia.trim()
      ) {
        return "Ingresá la referencia de la transferencia.";
      }

      const actuales = leerCobros();

      if (actuales.some((c) => c.id === cobro.id)) {
        return "El cobro ya fue registrado.";
      }

      const ventasActuales = leerVentasActuales();

      if (!ventasActuales) {
        return "No se pudieron verificar las ventas guardadas.";
      }

      const saldo = calcularSaldoCliente(
        cobro.clienteId,
        ventasActuales,
        actuales
      );

      if (cobro.importe > saldo + 0.009) {
        return `El cobro supera el saldo deudor disponible.`;
      }

      const actualizados = [...actuales, cobro];

      localStorage.setItem(
        CLAVE_COBROS,
        JSON.stringify(actualizados)
      );

      setCobros(actualizados);
      return null;
    } catch {
      return "No se pudo guardar el cobro.";
    }
  }

  return {
    cobros,
    registrarCobro,
  };
}
