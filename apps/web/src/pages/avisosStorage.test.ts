// Pruebas de los avisos de storage corrupto (Rendición y Cuentas Corrientes).
//
// El estado sale de las MISMAS lecturas discriminadas que usan las fronteras
// de escritura (`leerVentas()` y `leerCobrosDiscriminado()`), no de un parseo
// paralelo. Vitest corre en node: se simula localStorage.

import { beforeEach, describe, expect, it, vi } from "vitest";

import type { Cobro } from "../data/mockCobros";
import type { Venta } from "../data/mockVentas";
import type { MovimientoReparto } from "../data/mockMovimientos";
import { CLAVES_STORAGE } from "../data/clavesStorage";
import { leerCobrosDiscriminado } from "../hooks/useCobros";
import { leerVentas } from "../hooks/useVentas";
import { leerMovimientosDiscriminado } from "../hooks/useMovimientos";
import {
  AVISO_AMBOS_CUENTAS,
  AVISO_COBROS_CUENTAS,
  AVISO_COBROS_RENDICION,
  AVISO_MOVIMIENTOS_RENDICION,
  AVISO_VENTAS_CUENTAS,
  AVISO_VENTAS_RENDICION,
  disponibilidadCuentas,
  disponibilidadRendicion,
  saldoSiDisponible,
} from "./avisosStorage";

const CV = CLAVES_STORAGE.ventas;
const CC = CLAVES_STORAGE.cobros;
const CM = CLAVES_STORAGE.movimientos;

let store: Map<string, string>;
let setItem: ReturnType<typeof vi.fn>;
let removeItem: ReturnType<typeof vi.fn>;

beforeEach(() => {
  store = new Map();
  setItem = vi.fn((k: string, v: string) => void store.set(k, v));
  removeItem = vi.fn((k: string) => void store.delete(k));
  Object.defineProperty(globalThis, "localStorage", {
    value: {
      getItem: (k: string) => store.get(k) ?? null,
      setItem,
      removeItem,
      clear: vi.fn(),
    },
    writable: true,
  });
});

const venta = (id: string, total = 200): Venta => ({
  id,
  jornadaId: "j1",
  camionId: 1,
  clienteId: 1,
  nombreCliente: "Almacén",
  fecha: "2026-10-21T10:00:00.000Z",
  medioPago: "cuenta_corriente",
  items: [
    {
      productoId: 1,
      nombreProducto: "Yogur",
      unidadMedida: "unidad",
      cantidad: total / 100,
      precioUnitario: 100,
      subtotal: total,
    },
  ],
  total,
});

const cobro = (id: string, importe = 50): Cobro => ({
  id,
  clienteId: 1,
  nombreCliente: "Almacén",
  jornadaId: null,
  fecha: "2026-10-21T12:00:00.000Z",
  importe,
  medio: "efectivo",
  referencia: "",
  observaciones: "",
});

const movimiento = (id: string): MovimientoReparto => ({
  id,
  jornadaId: "j1",
  camionId: 1,
  fecha: "2026-10-21T11:00:00.000Z",
  motivo: "Rotura",
  tipo: "merma",
  producto: {
    productoId: 1,
    nombreProducto: "Yogur",
    unidadMedida: "unidad",
    cantidad: 1,
  },
  clienteId: null,
  nombreCliente: null,
});

const CORRUPTOS_VENTAS: Array<[string, string]> = [
  ["JSON inválido", "{no es json"],
  ["string vacío", ""],
  ["null", "null"],
  ["no array", JSON.stringify({ ventas: [] })],
  ["venta inválida", JSON.stringify([{ ...venta("x"), total: 999 }])],
];

const CORRUPTOS_COBROS: Array<[string, string]> = [
  ["JSON inválido", "{no es json"],
  ["string vacío", ""],
  ["null", "null"],
  ["no array", JSON.stringify({ cobros: [] })],
  ["cobro inválido", JSON.stringify([cobro("x", -5)])],
];

const CORRUPTOS_MOVIMIENTOS: Array<[string, string]> = [
  ["JSON inválido", "{no es json"],
  ["string vacío", ""],
  ["null", "null"],
  ["no array", JSON.stringify({ movimientos: [] })],
  ["movimiento inválido", JSON.stringify([{ ...movimiento("x"), motivo: 3 }])],
];

// Misma cadena que usan los hooks: lectura discriminada → estado → aviso.
const estados = () => ({
  ventas: leerVentas(),
  cobros: leerCobrosDiscriminado(),
  movimientos: leerMovimientosDiscriminado(),
});

describe("estado de lectura que alimenta la UI", () => {
  it("ausente → inicial (sin aviso)", () => {
    const { ventas, cobros, movimientos } = estados();
    expect(ventas.estado).toBe("inicial");
    expect(cobros.estado).toBe("inicial");
    expect(movimientos.estado).toBe("inicial");
  });

  it("válido → valido", () => {
    store.set(CV, JSON.stringify([venta("v1")]));
    store.set(CC, JSON.stringify([cobro("c1")]));
    store.set(CM, JSON.stringify([movimiento("m1")]));
    const { ventas, cobros, movimientos } = estados();
    expect(ventas.estado).toBe("valido");
    expect(cobros.estado).toBe("valido");
    expect(movimientos.estado).toBe("valido");
  });

  it.each(CORRUPTOS_VENTAS)("ventas %s → corrupto", (_n, crudo) => {
    store.set(CV, crudo);
    expect(estados().ventas.estado).toBe("corrupto");
  });

  it.each(CORRUPTOS_COBROS)("cobros %s → corrupto", (_n, crudo) => {
    store.set(CC, crudo);
    expect(estados().cobros.estado).toBe("corrupto");
  });

  it.each(CORRUPTOS_MOVIMIENTOS)("movimientos %s → corrupto", (_n, crudo) => {
    store.set(CM, crudo);
    expect(estados().movimientos.estado).toBe("corrupto");
  });
});

describe("Rendición", () => {
  it("A. ventas ausentes: sin alerta y todo calculable", () => {
    const d = disponibilidadRendicion(estados().ventas.estado, estados().cobros.estado);
    expect(d.avisos).toEqual([]);
    expect(d.mercaderiaDisponible).toBe(true);
    expect(d.cajaDisponible).toBe(true);
    expect(d.cierreDisponible).toBe(true);
  });

  it("B. ventas y cobros válidos: sin alerta", () => {
    store.set(CV, JSON.stringify([venta("v1")]));
    store.set(CC, JSON.stringify([cobro("c1")]));
    const e = estados();
    const d = disponibilidadRendicion(e.ventas.estado, e.cobros.estado);
    expect(d.avisos).toEqual([]);
    expect(d.cajaDisponible).toBe(true);
  });

  it.each(CORRUPTOS_VENTAS)("C. ventas corruptas (%s): alerta y nada derivado de ventas", (_n, crudo) => {
    store.set(CV, crudo);
    const e = estados();
    const d = disponibilidadRendicion(e.ventas.estado, e.cobros.estado);
    expect(d.avisos).toEqual([AVISO_VENTAS_RENDICION]);
    expect(d.mercaderiaDisponible).toBe(false);
    expect(d.cajaDisponible).toBe(false);
  });

  it.each(CORRUPTOS_COBROS)("cobros corruptos (%s): alerta y la caja no se calcula; la mercadería sí", (_n, crudo) => {
    store.set(CC, crudo);
    const e = estados();
    const d = disponibilidadRendicion(e.ventas.estado, e.cobros.estado);
    expect(d.avisos).toEqual([AVISO_COBROS_RENDICION]);
    expect(d.cajaDisponible).toBe(false);
    expect(d.mercaderiaDisponible).toBe(true);
  });

  it("ambos corruptos: dos avisos", () => {
    const d = disponibilidadRendicion("corrupto", "corrupto");
    expect(d.avisos).toEqual([AVISO_VENTAS_RENDICION, AVISO_COBROS_RENDICION]);
  });

  it.each(CORRUPTOS_MOVIMIENTOS)(
    "movimientos corruptos (%s): aviso, mermas/cambios no disponibles y cierre bloqueado",
    (_n, crudo) => {
      store.set(CM, crudo);
      const e = estados();
      const d = disponibilidadRendicion(
        e.ventas.estado,
        e.cobros.estado,
        e.movimientos.estado
      );
      expect(d.avisos).toEqual([AVISO_MOVIMIENTOS_RENDICION]);
      expect(d.ventasDisponibles).toBe(true);
      expect(d.movimientosDisponibles).toBe(false);
      expect(d.mercaderiaDisponible).toBe(false);
      expect(d.cajaDisponible).toBe(true);
      expect(d.cierreDisponible).toBe(false);
    }
  );

  it("ventas, cobros y movimientos corruptos: tres avisos únicos y ordenados", () => {
    const d = disponibilidadRendicion("corrupto", "corrupto", "corrupto");
    expect(d.avisos).toEqual([
      AVISO_VENTAS_RENDICION,
      AVISO_COBROS_RENDICION,
      AVISO_MOVIMIENTOS_RENDICION,
    ]);
    expect(new Set(d.avisos).size).toBe(3);
  });

  it("el texto del aviso de ventas es el pedido", () => {
    expect(AVISO_VENTAS_RENDICION).toBe(
      "Los datos de ventas guardados están dañados. No se puede calcular la rendición con seguridad."
    );
    expect(AVISO_MOVIMIENTOS_RENDICION).toBe(
      "Los datos de movimientos guardados están dañados. No se puede calcular la rendición con seguridad."
    );
  });
});

describe("Cuentas corrientes", () => {
  const saldo = () => {
    const e = estados();
    const d = disponibilidadCuentas(e.ventas.estado, e.cobros.estado);
    const ventas = e.ventas.ok ? e.ventas.ventas : [];
    const cobros = e.cobros.ok ? e.cobros.cobros : [];
    return { d, saldo: saldoSiDisponible(d.saldoDisponible, 1, ventas, cobros) };
  };

  it("A. ambos ausentes: estado inicial válido, sin alerta, saldo 0 legítimo", () => {
    const r = saldo();
    expect(r.d.aviso).toBeNull();
    expect(r.d.saldoDisponible).toBe(true);
    expect(r.saldo).toBe(0);
  });

  it("B. ambos válidos: saldo actual correcto (200 - 50 = 150)", () => {
    store.set(CV, JSON.stringify([venta("v1", 200)]));
    store.set(CC, JSON.stringify([cobro("c1", 50)]));
    const r = saldo();
    expect(r.d.aviso).toBeNull();
    expect(r.saldo).toBe(150);
  });

  it.each(CORRUPTOS_VENTAS)("C. ventas corruptas (%s) + cobros válidos: aviso de ventas y saldo no disponible", (_n, crudo) => {
    store.set(CV, crudo);
    store.set(CC, JSON.stringify([cobro("c1", 50)]));
    const r = saldo();
    expect(r.d.aviso).toBe(AVISO_VENTAS_CUENTAS);
    expect(r.d.saldoDisponible).toBe(false);
    expect(r.saldo).toBeNull();
  });

  it.each(CORRUPTOS_COBROS)("D. ventas válidas + cobros corruptos (%s): aviso de cobros y saldo no disponible", (_n, crudo) => {
    store.set(CV, JSON.stringify([venta("v1", 200)]));
    store.set(CC, crudo);
    const r = saldo();
    expect(r.d.aviso).toBe(AVISO_COBROS_CUENTAS);
    expect(r.d.ventasDisponibles).toBe(true);
    expect(r.d.cobrosDisponibles).toBe(false);
    expect(r.saldo).toBeNull();
  });

  it("E. ambos corruptos: aviso combinado y saldo no disponible", () => {
    store.set(CV, "{roto");
    store.set(CC, "");
    const r = saldo();
    expect(r.d.aviso).toBe(AVISO_AMBOS_CUENTAS);
    expect(r.saldo).toBeNull();
  });

  it("F. nunca se muestra 0 como respaldo ante corrupción", () => {
    for (const [v, c] of [
      ["corrupto", "valido"],
      ["valido", "corrupto"],
      ["corrupto", "corrupto"],
    ] as const) {
      const d = disponibilidadCuentas(v, c);
      expect(saldoSiDisponible(d.saldoDisponible, 1, [], [])).toBeNull();
    }
  });

  it("los textos de aviso son los pedidos", () => {
    expect(AVISO_VENTAS_CUENTAS).toBe(
      "Los datos de ventas guardados están dañados. No se puede calcular el saldo de cuentas corrientes."
    );
    expect(AVISO_COBROS_CUENTAS).toBe(
      "Los datos de cobros guardados están dañados. No se puede calcular el saldo de cuentas corrientes."
    );
    expect(AVISO_AMBOS_CUENTAS).toBe(
      "Los datos de ventas y cobros guardados están dañados. No se puede calcular el saldo de cuentas corrientes."
    );
  });
});

describe("el aviso no escribe ni repara el storage", () => {
  it("leer y decidir avisos con storage corrupto no llama a setItem ni removeItem", () => {
    store.set(CV, "{roto");
    store.set(CC, "null");
    store.set(CM, "");
    const antes = [store.get(CV), store.get(CC), store.get(CM)];
    const e = estados();
    disponibilidadRendicion(
      e.ventas.estado,
      e.cobros.estado,
      e.movimientos.estado
    );
    disponibilidadCuentas(e.ventas.estado, e.cobros.estado);
    expect(setItem).not.toHaveBeenCalled();
    expect(removeItem).not.toHaveBeenCalled();
    expect([store.get(CV), store.get(CC), store.get(CM)]).toEqual(antes);
  });
});
