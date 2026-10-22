
import { useState } from "react";
import { CLAVES_STORAGE } from "../data/clavesStorage";
import type { Cobro } from "../data/mockCobros";
import type { Venta } from "../data/mockVentas";
import { leerVentas, type ResultadoLecturaVentas } from "./useVentas";

const CLAVE_COBROS = CLAVES_STORAGE.cobros;

function redondearDinero(valor: number) {
  return Math.round(valor * 100) / 100;
}

/** Cobro válido (estructura y política monetaria vigente). */
export function cobroValido(c: unknown): c is Cobro {
  if (c === null || typeof c !== "object") return false;

  const x = c as Partial<Cobro>;

  return (
    typeof x.id === "string" &&
    Number.isSafeInteger(x.clienteId) &&
    typeof x.nombreCliente === "string" &&
    (x.jornadaId === null || typeof x.jornadaId === "string") &&
    typeof x.fecha === "string" &&
    Number.isFinite(x.importe) &&
    (x.importe as number) > 0 &&
    Math.abs(
      (x.importe as number) * 100 -
        Math.round((x.importe as number) * 100)
    ) < 0.000001 &&
    ["efectivo", "transferencia"].includes(x.medio ?? "") &&
    typeof x.referencia === "string" &&
    typeof x.observaciones === "string"
  );
}

/** Resultado discriminado de la lectura del ledger de cobros. */
export type ResultadoLecturaCobros =
  | { ok: true; cobros: Cobro[]; estado: "inicial" | "valido" }
  | { ok: false; estado: "corrupto"; error: string };

/**
 * Lectura discriminada: ausente (getItem === null → []), válida, o presente
 * pero corrupta ("", "null", JSON inválido, no array o cobro inválido).
 */
export function leerCobrosDiscriminado(): ResultadoLecturaCobros {
  try {
    const texto = localStorage.getItem(CLAVE_COBROS);

    if (texto === null) {
      return { ok: true, cobros: [], estado: "inicial" };
    }

    let datos: unknown;
    try {
      datos = JSON.parse(texto);
    } catch {
      return {
        ok: false,
        estado: "corrupto",
        error: "JSON inválido en almacenamiento de cobros.",
      };
    }

    if (!Array.isArray(datos)) {
      return {
        ok: false,
        estado: "corrupto",
        error: "Estructura inválida: se esperaba un array de cobros.",
      };
    }

    if (!datos.every(cobroValido)) {
      return {
        ok: false,
        estado: "corrupto",
        error: "Uno o más cobros no pasan la validación.",
      };
    }

    return { ok: true, cobros: datos as Cobro[], estado: "valido" };
  } catch (e) {
    return {
      ok: false,
      estado: "corrupto",
      error: `Error inesperado al leer cobros: ${String(e)}`,
    };
  }
}

/**
 * Lectura para UI: fail-closed visual ([] si está ausente o corrupto).
 * NO usar como autoridad en una escritura.
 */
export function leerCobros(): Cobro[] {
  const lectura = leerCobrosDiscriminado();
  return lectura.ok ? lectura.cobros : [];
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

/**
 * Operación de registro de cobro, testeable sin React. Orden: 1) cobro válido,
 * 2) cobros discriminados (corrupto → abortar), 3) duplicado, 4) ventas
 * discriminadas (corrupto → abortar; nunca se calcula un saldo sobre un []
 * artificial), 5) saldo, 6) persistir.
 */
export function registrarCobroOperacion(
  cobro: Cobro,
  cargarCobros: () => ResultadoLecturaCobros,
  cargarVentasActuales: () => ResultadoLecturaVentas,
  guardarCobros: (cobros: Cobro[]) => void
): string | null {
  if (
    !Number.isSafeInteger(cobro.clienteId) ||
    !Number.isFinite(cobro.importe) ||
    cobro.importe <= 0 ||
    Math.abs(
      cobro.importe * 100 -
      Math.round(cobro.importe * 100)
    ) > 0.000001 ||
    !["efectivo", "transferencia"].includes(cobro.medio) ||
    !cobroValido(cobro)
  ) {
    return "Los datos del cobro no son válidos.";
  }

  if (
    cobro.medio === "transferencia" &&
    !cobro.referencia.trim()
  ) {
    return "Ingresá la referencia de la transferencia.";
  }

  const lecturaCobros = cargarCobros();

  if (!lecturaCobros.ok) {
    return `No se puede registrar: ${lecturaCobros.error}`;
  }

  const actuales = lecturaCobros.cobros;

  if (actuales.some((c) => c.id === cobro.id)) {
    return "El cobro ya fue registrado.";
  }

  const lecturaVentas = cargarVentasActuales();

  if (!lecturaVentas.ok) {
    return `No se pudieron verificar las ventas guardadas: ${lecturaVentas.error}`;
  }

  const saldo = calcularSaldoCliente(
    cobro.clienteId,
    lecturaVentas.ventas,
    actuales
  );

  if (cobro.importe > saldo + 0.009) {
    return `El cobro supera el saldo deudor disponible.`;
  }

  guardarCobros([...actuales, cobro]);

  return null;
}

/**
 * Frontera REAL de escritura sin React: es lo que ejecuta el hook. Con cobros
 * o ventas corruptos no escribe nada.
 */
export function registrarCobroPersistido(
  cobro: Cobro,
  alGuardar?: (cobros: Cobro[]) => void
): string | null {
  try {
    return registrarCobroOperacion(
      cobro,
      leerCobrosDiscriminado,
      leerVentas,
      (nuevos) => {
        localStorage.setItem(CLAVE_COBROS, JSON.stringify(nuevos));
        alGuardar?.(nuevos);
      }
    );
  } catch {
    return "No se pudo guardar el cobro.";
  }
}

export function useCobros() {
  // Una sola lectura discriminada al montar (ver useVentas).
  const [lectura] = useState(leerCobrosDiscriminado);
  const [cobros, setCobros] = useState<Cobro[]>(
    lectura.ok ? lectura.cobros : []
  );

  function registrarCobro(cobro: Cobro): string | null {
    return registrarCobroPersistido(cobro, setCobros);
  }

  return {
    cobros,
    registrarCobro,
    estadoLectura: lectura.estado,
  };
}
