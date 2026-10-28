// B2: frontera REAL de movimientos con productos `peso` (gramos enteros).
// Ejercita registrarMovimientoPersistido, que ejecuta siempre la validación
// con lecturas frescas (sin validador inyectable), sobre localStorage
// simulado: Jornadas, Ventas y Movimientos, rechazo sin escritura y raw intacto.
// Vitest corre en entorno node: se simula localStorage sobre globalThis.
import { describe, expect, it, beforeEach, vi } from "vitest";

import {
  MENSAJE_MOVIMIENTO_OTRA_JORNADA,
  registrarMovimientoPersistido,
} from "./useMovimientos";
import type { Jornada, ItemCarga } from "../data/mockJornadas";
import type { Venta } from "../data/mockVentas";
import type {
  MovimientoReparto,
  ProductoMovimiento,
} from "../data/mockMovimientos";
import { CLAVES_STORAGE } from "../data/clavesStorage";
import {
  MENSAJE_CAMBIO_MIXTO_NO_HABILITADO,
  MENSAJE_SALIDAS_SUPERAN_CARGA,
} from "../domain/movimientos";

const crearMockLocalStorage = () => {
  const store = new Map<string, string>();
  return {
    getItem: vi.fn((key: string) => store.get(key) ?? null),
    setItem: vi.fn((key: string, value: string) => {
      store.set(key, value);
    }),
    get length() {
      return store.size;
    },
    _store: store,
  };
};

let mockLS: ReturnType<typeof crearMockLocalStorage>;

beforeEach(() => {
  mockLS = crearMockLocalStorage();
  Object.defineProperty(globalThis, "localStorage", {
    value: mockLS,
    writable: true,
  });
});

const MAX = Number.MAX_SAFE_INTEGER;

const carga = (
  productoId: number,
  nombreProducto: string,
  unidadMedida: "unidad" | "peso",
  cantidad: number
): ItemCarga => ({
  productoId,
  nombreProducto,
  unidadMedida,
  cantidad,
  precioReferencia: 1000,
});

const jornadaAbierta = (items: ItemCarga[]): Jornada => ({
  id: "j1",
  camionId: 1,
  chofer: "Chofer",
  zona: "Centro",
  fechaCreacion: "2026-10-27T08:00:00.000Z",
  fechaSalida: "2026-10-27T09:00:00.000Z",
  estado: "abierta",
  items,
});

const cargaBase = [
  carga(1, "Yogur", "unidad", 10),
  carga(2, "Leche", "unidad", 10),
  carga(4, "Jamón", "peso", 1250),
  carga(5, "Salame", "peso", 980),
];

const yogur = (c: number): ProductoMovimiento => ({ productoId: 1, nombreProducto: "Yogur", unidadMedida: "unidad", cantidad: c });
const leche = (c: number): ProductoMovimiento => ({ productoId: 2, nombreProducto: "Leche", unidadMedida: "unidad", cantidad: c });
const jamon = (g: number): ProductoMovimiento => ({ productoId: 4, nombreProducto: "Jamón", unidadMedida: "peso", cantidad: g });
const salame = (g: number): ProductoMovimiento => ({ productoId: 5, nombreProducto: "Salame", unidadMedida: "peso", cantidad: g });

let secuencia = 0;
const base = () => ({
  id: `m${++secuencia}`,
  jornadaId: "j1",
  camionId: 1,
  fecha: "2026-10-27T10:00:00.000Z",
  motivo: "Otro motivo",
});

const merma = (producto: ProductoMovimiento): MovimientoReparto => ({
  ...base(),
  tipo: "merma",
  producto,
  clienteId: null,
  nombreCliente: null,
});

const devolucion = (producto: ProductoMovimiento): MovimientoReparto => ({
  ...base(),
  tipo: "devolucion",
  producto,
  clienteId: 7,
  nombreCliente: "Almacén",
});

const cambio = (
  devuelto: ProductoMovimiento,
  entregado: ProductoMovimiento
): MovimientoReparto => ({
  ...base(),
  tipo: "cambio",
  clienteId: 7,
  nombreCliente: "Almacén",
  productoDevuelto: devuelto,
  productoEntregado: entregado,
});

// La pantalla registra con la jornada del render como snapshot. Devuelve el
// error o null (como el hook) para conservar los asserts existentes.
const registrar = (movimiento: MovimientoReparto, render = jornadaAbierta(cargaBase)) => {
  const resultado = registrarMovimientoPersistido(movimiento, render);
  return resultado.ok ? null : resultado.error;
};

const sembrar = (
  jornadas: Jornada[] = [jornadaAbierta(cargaBase)],
  movimientos: MovimientoReparto[] = []
) => {
  mockLS._store.set(CLAVES_STORAGE.jornadas, JSON.stringify(jornadas));
  mockLS._store.set(CLAVES_STORAGE.movimientos, JSON.stringify(movimientos));
  mockLS.setItem.mockClear();
};

const guardados = () =>
  JSON.parse(String(mockLS._store.get(CLAVES_STORAGE.movimientos))) as MovimientoReparto[];

const sinEscribir = (rawMovimientos: string | undefined) => {
  expect(mockLS.setItem).not.toHaveBeenCalled();
  expect(mockLS._store.get(CLAVES_STORAGE.movimientos)).toBe(rawMovimientos);
};

describe("B2: movimientos peso persistidos en gramos exactos", () => {
  beforeEach(() => sembrar());

  it("merma peso: se persisten los gramos exactos", () => {
    const m = merma(jamon(1250));
    expect(registrar(m)).toBeNull();
    expect(guardados()).toEqual([m]);
  });

  it("devolución peso: se persisten los gramos exactos", () => {
    const m = devolucion(jamon(28680));
    expect(registrar(m)).toBeNull();
    expect(guardados()).toEqual([m]);
  });

  it("cambio peso ↔ peso: cada lado conserva su propia cantidad, sin relación entre ambas", () => {
    const m = cambio(jamon(1250), salame(980));
    expect(registrar(m)).toBeNull();
    const [guardado] = guardados();
    expect(guardado).toEqual(m);
    if (guardado.tipo !== "cambio") throw new Error("debía ser un cambio");
    expect(guardado.productoDevuelto.cantidad).toBe(1250);
    expect(guardado.productoEntregado.cantidad).toBe(980);
  });

  it("cambio unidad ↔ unidad sigue funcionando", () => {
    const m = cambio(yogur(2), leche(3));
    expect(registrar(m)).toBeNull();
    expect(guardados()).toEqual([m]);
  });
});

describe("B2: cambio mixto rechazado con mensaje específico y sin escritura", () => {
  it.each([
    ["unidad ↔ peso", () => cambio(yogur(1), jamon(1250))],
    ["peso ↔ unidad", () => cambio(jamon(1250), yogur(1))],
  ])("%s", (_n, crear) => {
    sembrar();
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);
    expect(registrar(crear())).toBe(MENSAJE_CAMBIO_MIXTO_NO_HABILITADO);
    sinEscribir(raw);
  });
});

describe("B2: disponibilidad en gramos con lecturas frescas", () => {
  it("exceder lo disponible por 1 g se rechaza sin escribir; el límite exacto pasa", () => {
    sembrar();
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);
    expect(registrar(merma(jamon(1251)))).toBe("Stock insuficiente de Jamón.");
    sinEscribir(raw);

    expect(registrar(merma(jamon(1250)))).toBeNull();
  });

  it("cambio peso ↔ peso: el entregado se valida contra su propio disponible (1 g de más)", () => {
    sembrar();
    expect(registrar(cambio(jamon(1), salame(981)))).toBe("Stock insuficiente de Salame.");
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });

  it("TOCTOU: un movimiento guardado después del render reduce el disponible y la frontera rechaza", () => {
    // El render vio 1250 g; en storage ya hay una merma de 1000 g.
    sembrar([jornadaAbierta(cargaBase)], [merma(jamon(1000))]);
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);

    expect(registrar(merma(jamon(251)))).toBe("Stock insuficiente de Jamón.");
    sinEscribir(raw);

    expect(registrar(merma(jamon(250)))).toBeNull();
  });

  it("TOCTOU: la carga vigente en storage manda sobre la del render", () => {
    // El render tenía 1250 g; la jornada guardada carga 1000 g.
    const vigente = jornadaAbierta([carga(4, "Jamón", "peso", 1000)]);
    sembrar([vigente]);
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);

    expect(registrar(merma(jamon(1001)))).toBe("Stock insuficiente de Jamón.");
    sinEscribir(raw);
  });

  it("TOCTOU: si la jornada se cerró después del render, no se registra", () => {
    const cerrada: Jornada = {
      ...jornadaAbierta(cargaBase),
      estado: "cerrada",
      cierre: {
        fecha: "2026-10-27T18:00:00.000Z",
        conteos: { "1": 10, "2": 10, "4": 1250, "5": 980 },
        efectivoEntregado: 0,
        efectivoEsperado: 0,
        transferenciasInformadas: 0,
        ventasCuentaCorriente: 0,
        observaciones: "",
      },
    };
    sembrar([cerrada]);
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);

    const error = registrar(merma(jamon(1)));
    expect(error).toContain("ya no está abierta");
    sinEscribir(raw);
  });
});

describe("B2: corrupción y overflow fallan cerrado, sin escritura", () => {
  it("movimientos corruptos: no se registra y el raw queda intacto", () => {
    sembrar();
    mockLS._store.set(CLAVES_STORAGE.movimientos, "{roto");
    expect(registrar(merma(jamon(1)))).toContain("No se puede registrar");
    sinEscribir("{roto");
  });

  it("jornadas corruptas: no se registra", () => {
    sembrar();
    mockLS._store.set(CLAVES_STORAGE.jornadas, "{roto");
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);
    expect(registrar(merma(jamon(1)))).toContain("No se puede registrar");
    sinEscribir(raw);
    expect(mockLS._store.get(CLAVES_STORAGE.jornadas)).toBe("{roto");
  });

  it("ventas corruptas: no se registra", () => {
    sembrar();
    mockLS._store.set(CLAVES_STORAGE.ventas, "{roto");
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);
    expect(registrar(merma(jamon(1)))).toContain("No se puede registrar");
    sinEscribir(raw);
  });

  it("overflow de salidas en gramos: no calcula un saldo aproximado y no escribe", () => {
    const enorme = jornadaAbierta([carga(4, "Jamón", "peso", MAX)]);
    sembrar([enorme], [merma(jamon(MAX)), merma(jamon(1))]);
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);

    expect(registrar(merma(jamon(1)), enorme)).toBe(
      "No se puede calcular el stock disponible: hay cantidades inválidas o fuera del rango seguro."
    );
    sinEscribir(raw);
  });
});

describe("B2: invariantes de la frontera (unidad vs carga; ledger inconsistente)", () => {
  it.each([
    ["carga peso + movimiento unidad", () => merma({ ...jamon(5), unidadMedida: "unidad" })],
    ["carga unidad + movimiento peso", () => merma({ ...yogur(1000), unidadMedida: "peso" })],
  ])("%s: rechazo sin convertir, 0 escrituras y raw intacto", (_n, crear) => {
    sembrar();
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);
    expect(registrar(crear())).toMatch(/no coincide con la cargada/);
    sinEscribir(raw);
  });

  it("salidas existentes de 1300 g sobre 1250 g cargados: un movimiento nuevo de 1 g se rechaza", () => {
    sembrar([jornadaAbierta(cargaBase)], [merma(jamon(1000)), merma(jamon(300))]);
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);

    expect(registrar(merma(jamon(1)))).toBe(MENSAJE_SALIDAS_SUPERAN_CARGA);
    sinEscribir(raw);
  });
});

describe("security review B2: salidas históricas con otra unidad bloquean, sin escritura", () => {
  // Venta histórica válida para el lector (las ventas son `unidad` hasta B3).
  const ventaUnidad = (productoId: number, cantidad: number): Venta => ({
    id: "v1",
    jornadaId: "j1",
    camionId: 1,
    clienteId: 7,
    nombreCliente: "Almacén",
    fecha: "2026-10-27T10:00:00.000Z",
    medioPago: "efectivo",
    items: [
      {
        productoId,
        nombreProducto: "Producto",
        unidadMedida: "unidad",
        cantidad,
        precioUnitario: 100,
        subtotal: cantidad * 100,
      },
    ],
    total: cantidad * 100,
  });

  it.each([
    ["carga peso + merma histórica unidad", () => [merma({ ...jamon(5), unidadMedida: "unidad" })], () => merma(jamon(1))],
    ["carga unidad + merma histórica peso", () => [merma({ ...yogur(5), unidadMedida: "peso" })], () => merma(yogur(1))],
    ["carga unidad + entregado histórico peso", () => [cambio(jamon(1), { ...yogur(5), unidadMedida: "peso" })], () => merma(yogur(1))],
  ])("%s: rechazo, 0 escrituras y raw intacto", (_n, previos, nuevo) => {
    sembrar([jornadaAbierta(cargaBase)], previos());
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);
    expect(registrar(nuevo())).toBe(MENSAJE_SALIDAS_SUPERAN_CARGA);
    sinEscribir(raw);
  });

  it("carga peso + venta histórica unidad: rechazo, 0 escrituras y raw intacto", () => {
    sembrar();
    const rawVentas = JSON.stringify([ventaUnidad(4, 5)]);
    mockLS._store.set(CLAVES_STORAGE.ventas, rawVentas);
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);

    expect(registrar(merma(jamon(1)))).toBe(MENSAJE_SALIDAS_SUPERAN_CARGA);
    sinEscribir(raw);
    expect(mockLS._store.get(CLAVES_STORAGE.ventas)).toBe(rawVentas);
  });

  it("control: venta histórica unidad de un producto cargado unidad se descuenta y el movimiento válido persiste", () => {
    sembrar();
    mockLS._store.set(CLAVES_STORAGE.ventas, JSON.stringify([ventaUnidad(1, 9)]));
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);

    expect(registrar(merma(yogur(2)))).toBe("Stock insuficiente de Yogur.");
    sinEscribir(raw);

    const m = merma(yogur(1));
    expect(registrar(m)).toBeNull();
    expect(guardados()).toEqual([m]);
  });
});

describe("security review B2: el movimiento pertenece a la jornada revalidada", () => {
  const otraJornada: Jornada = { ...jornadaAbierta(cargaBase), id: "j2", camionId: 2 };

  it.each([
    ["jornadaId de otra jornada abierta", () => ({ ...merma(jamon(1)), jornadaId: "j2" })],
    ["jornadaId inexistente", () => ({ ...merma(jamon(1)), jornadaId: "zzz" })],
    ["camionId de otro camión", () => ({ ...merma(jamon(1)), camionId: 2 })],
    ["camionId inexistente", () => ({ ...merma(jamon(1)), camionId: 123 })],
  ])("%s: rechazo, 0 escrituras y raw intacto", (_n, crear) => {
    sembrar([jornadaAbierta(cargaBase), otraJornada]);
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);
    const rawJornadas = mockLS._store.get(CLAVES_STORAGE.jornadas);

    expect(registrar(crear())).toBe(MENSAJE_MOVIMIENTO_OTRA_JORNADA);
    sinEscribir(raw);
    expect(mockLS._store.get(CLAVES_STORAGE.jornadas)).toBe(rawJornadas);
  });

  it("control: con jornada y camión correctos el movimiento persiste", () => {
    sembrar([jornadaAbierta(cargaBase), otraJornada]);
    const m = merma(jamon(1));
    expect(registrar(m)).toBeNull();
    expect(guardados()).toEqual([m]);
    expect(mockLS.setItem).toHaveBeenCalledTimes(1);
  });
});

describe("M-2: la frontera valida siempre; no existe validador inyectable", () => {
  it("jornada del render inexistente en storage: rechazo, 0 escrituras y raw intacto", () => {
    sembrar([{ ...jornadaAbierta(cargaBase), id: "j2", camionId: 2 }]);
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);

    expect(registrarMovimientoPersistido(merma(jamon(1)), jornadaAbierta(cargaBase))).toEqual({
      ok: false,
      error: "No se puede registrar: La jornada seleccionada ya no existe.",
    });
    sinEscribir(raw);
  });

  // Escenario del bypass previo (validar = () => null).
  it("PoC previo: jornadaId inexistente, camión 999 y 9.000.000 g se rechaza sin escribir", () => {
    sembrar();
    const raw = mockLS._store.get(CLAVES_STORAGE.movimientos);
    const m = { ...merma(jamon(9_000_000)), jornadaId: "no-existe", camionId: 999 };

    expect(registrarMovimientoPersistido(m, jornadaAbierta(cargaBase))).toEqual({
      ok: false,
      error: MENSAJE_MOVIMIENTO_OTRA_JORNADA,
    });
    sinEscribir(raw);
  });

  it("control positivo: ok, exactamente 1 setItem y el ledger esperado", () => {
    const previo = merma(jamon(250));
    sembrar([jornadaAbierta(cargaBase)], [previo]);
    const m = merma(jamon(1000));

    expect(registrarMovimientoPersistido(m, jornadaAbierta(cargaBase))).toEqual({
      ok: true,
      movimientos: [previo, m],
    });
    expect(mockLS.setItem).toHaveBeenCalledTimes(1);
    expect(mockLS.setItem).toHaveBeenCalledWith(
      CLAVES_STORAGE.movimientos,
      JSON.stringify([previo, m])
    );
    expect(guardados()).toEqual([previo, m]);
  });
});
