// Avisos de UI ante storage corrupto de Ventas y Cobros (fail-closed).
//
// Funciones puras que deciden qué mostrar y qué calcular a partir del estado
// de la lectura discriminada que ya usan las fronteras de escritura
// (`leerVentas()` / `leerCobrosDiscriminado()`):
//   - "inicial" (clave ausente) y "valido": comportamiento normal, sin aviso.
//   - "corrupto": aviso explícito y los valores derivados NO se calculan.
//
// Sin React, sin storage, sin recuperación: no repara, borra ni escribe nada.

import type { Cobro } from "../data/mockCobros";
import type { Venta } from "../data/mockVentas";
import { calcularSaldoCliente } from "../hooks/useCobros";

export type EstadoLectura = "inicial" | "valido" | "corrupto";

export const AVISO_VENTAS_RENDICION =
  "Los datos de ventas guardados están dañados. No se puede calcular la rendición con seguridad.";

export const AVISO_COBROS_RENDICION =
  "Los datos de cobros guardados están dañados. No se puede calcular el efectivo esperado con seguridad.";

export const AVISO_VENTAS_CUENTAS =
  "Los datos de ventas guardados están dañados. No se puede calcular el saldo de cuentas corrientes.";

export const AVISO_COBROS_CUENTAS =
  "Los datos de cobros guardados están dañados. No se puede calcular el saldo de cuentas corrientes.";

export const AVISO_AMBOS_CUENTAS =
  "Los datos de ventas y cobros guardados están dañados. No se puede calcular el saldo de cuentas corrientes.";

export const NO_DISPONIBLE = "No disponible";

export interface DisponibilidadRendicion {
  /** Avisos a mostrar (vacío si no hay corrupción). */
  avisos: string[];
  /** Ventas legibles: vendido por producto y esperado de mercadería. */
  mercaderiaDisponible: boolean;
  /** Ventas y cobros legibles: efectivo, transferencias y totales de caja. */
  cajaDisponible: boolean;
}

/** Rendición: qué se puede calcular según el estado de ventas y cobros. */
export function disponibilidadRendicion(
  ventas: EstadoLectura,
  cobros: EstadoLectura
): DisponibilidadRendicion {
  const avisos: string[] = [];

  if (ventas === "corrupto") avisos.push(AVISO_VENTAS_RENDICION);
  if (cobros === "corrupto") avisos.push(AVISO_COBROS_RENDICION);

  return {
    avisos,
    mercaderiaDisponible: ventas !== "corrupto",
    cajaDisponible: ventas !== "corrupto" && cobros !== "corrupto",
  };
}

export interface DisponibilidadCuentas {
  aviso: string | null;
  ventasDisponibles: boolean;
  cobrosDisponibles: boolean;
  /** El saldo requiere AMBOS ledgers legibles. */
  saldoDisponible: boolean;
}

/** Cuentas corrientes: qué se puede calcular según ventas y cobros. */
export function disponibilidadCuentas(
  ventas: EstadoLectura,
  cobros: EstadoLectura
): DisponibilidadCuentas {
  const ventasMal = ventas === "corrupto";
  const cobrosMal = cobros === "corrupto";

  return {
    aviso:
      ventasMal && cobrosMal
        ? AVISO_AMBOS_CUENTAS
        : ventasMal
          ? AVISO_VENTAS_CUENTAS
          : cobrosMal
            ? AVISO_COBROS_CUENTAS
            : null,
    ventasDisponibles: !ventasMal,
    cobrosDisponibles: !cobrosMal,
    saldoDisponible: !ventasMal && !cobrosMal,
  };
}

/**
 * Saldo de un cliente o null si no puede calcularse con seguridad. Nunca
 * devuelve 0 como respaldo ante corrupción.
 */
export function saldoSiDisponible(
  disponible: boolean,
  clienteId: number,
  ventas: Venta[],
  cobros: Cobro[]
): number | null {
  return disponible ? calcularSaldoCliente(clienteId, ventas, cobros) : null;
}
