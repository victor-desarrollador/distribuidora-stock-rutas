// Bloque E / M-3: pruebas unitarias de la frontera `crearPreparacionPersistida`.
// Verifica que la creación de una preparación relea Productos, Jornadas y
// Retornos discriminadamente justo antes de persistir, que calcule el stock
// con esas lecturas frescas (no con el snapshot del montaje), que rechaze
// duplicados y storage corrupto sin escribir nada (raw intacto), y que las
// claves ausentes se tratan como ledgers iniciales.
// B2 (ADR-005): las cargas `peso` se validan en gramos enteros exactos, con
// sumas seguras y sin tolerancia (1 g de más se rechaza).
// Vitest corre en entorno node: se simula localStorage sobre globalThis.
import { describe, expect, it, beforeEach, vi } from "vitest";

import {
  calcularStockReservado,
  cerrarJornadaPersistida,
  confirmarSalidaPersistida,
  crearPreparacionPersistida,
  leerJornadas,
  MENSAJE_PREPARACION_INVALIDA,
  MENSAJE_STOCK_NO_CALCULABLE,
  validarStockPreparacion,
} from "./useJornadas";
import type { Jornada, ItemCarga } from "../data/mockJornadas";
import type { Producto } from "../data/mockProductos";
import type { RetornoDeposito } from "../data/mockRetornos";
import { CLAVES_STORAGE } from "../data/clavesStorage";

// --- Simulación de localStorage para entorno node ---

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

// --- Datos de prueba ---

const MAX = Number.MAX_SAFE_INTEGER;

// Catálogo explícito: yogur (unidad, 120 u), jamón (peso, 18000 g) y salame
// (peso, 2500 g).
const yogur: Producto = {
  id: 1,
  nombre: "Yogur de prueba",
  categoria: "Lácteos",
  unidadMedida: "unidad",
  stock: 120,
  precio: 2300,
  stockMinimo: 20,
};

const jamon: Producto = {
  id: 4,
  nombre: "Jamón de prueba",
  categoria: "Fiambres",
  unidadMedida: "peso",
  stock: 18000,
  precio: 12500,
  stockMinimo: 5000,
};

const salame: Producto = {
  id: 5,
  nombre: "Salame de prueba",
  categoria: "Fiambres",
  unidadMedida: "peso",
  stock: 2500,
  precio: 9800,
  stockMinimo: 3000,
};

const sembrarCatalogo = (productos: Producto[] = [yogur, jamon, salame]) =>
  mockLS._store.set(CLAVES_STORAGE.productos, JSON.stringify(productos));

const itemCargaDe = (cantidad: number): ItemCarga => ({
  productoId: 1,
  nombreProducto: "Yogur de prueba",
  unidadMedida: "unidad",
  cantidad,
  precioReferencia: 2300,
});

const itemJamon = (gramos: number): ItemCarga => ({
  productoId: 4,
  nombreProducto: "Jamón de prueba",
  unidadMedida: "peso",
  cantidad: gramos,
  precioReferencia: 12500,
});

const itemSalame = (gramos: number): ItemCarga => ({
  productoId: 5,
  nombreProducto: "Salame de prueba",
  unidadMedida: "peso",
  cantidad: gramos,
  precioReferencia: 9800,
});

const jornadaPreparacion = (cantidad: number): Jornada => ({
  id: "jornada-previa",
  camionId: 1,
  chofer: "Chofer de prueba",
  zona: "Centro",
  fechaCreacion: "2026-10-22T08:00:00.000Z",
  fechaSalida: null,
  estado: "preparacion",
  items: [itemCargaDe(cantidad)],
});

const jornadaCerrada = (cantidad: number): Jornada => ({
  id: "jornada-previa",
  camionId: 1,
  chofer: "Chofer de prueba",
  zona: "Centro",
  fechaCreacion: "2026-10-22T08:00:00.000Z",
  fechaSalida: "2026-10-22T09:00:00.000Z",
  estado: "cerrada",
  items: [itemCargaDe(cantidad)],
  cierre: {
    fecha: "2026-10-22T18:00:00.000Z",
    conteos: { "1": cantidad },
    efectivoEntregado: 0,
    efectivoEsperado: 0,
    transferenciasInformadas: 0,
    ventasCuentaCorriente: 0,
    observaciones: "",
  },
});

const retornoAprobado = (cantidadAprobada: number): RetornoDeposito => ({
  id: "retorno-de-prueba",
  jornadaId: "jornada-previa",
  camionId: 1,
  fecha: "2026-10-22T19:00:00.000Z",
  responsable: "Encargado de prueba",
  observaciones: "",
  items: [
    {
      productoId: 1,
      nombreProducto: "Yogur de prueba",
      unidadMedida: "unidad",
      cantidadContada: 110,
      cantidadAprobada,
    },
  ],
});

const jornadaNueva: Jornada = {
  id: "jornada-nueva",
  camionId: 2,
  chofer: "Chofer nuevo",
  zona: "Sur",
  fechaCreacion: "2026-10-22T10:00:00.000Z",
  fechaSalida: null,
  estado: "preparacion",
  items: [itemCargaDe(100)],
};

// Jornada activa de otro camión que reserva lo indicado.
const jornadaActiva = (
  id: string,
  camionId: number,
  items: ItemCarga[],
  estado: "preparacion" | "abierta" = "preparacion"
): Jornada => ({
  id,
  camionId,
  chofer: `Chofer ${id}`,
  zona: "Norte",
  fechaCreacion: "2026-10-22T07:00:00.000Z",
  fechaSalida: estado === "abierta" ? "2026-10-22T08:00:00.000Z" : null,
  estado,
  items,
});

const nuevaCon = (items: ItemCarga[]): Jornada => ({ ...jornadaNueva, items });

const rawJornadasDe = (jornadas: Jornada[]) =>
  JSON.stringify(jornadas);

const jornadasGuardadas = () =>
  JSON.parse(String(mockLS.getItem(CLAVES_STORAGE.jornadas))) as Jornada[];

describe("crearPreparacionPersistida — frontera M-3", () => {
  it("claves ausentes: ledgers iniciales (catálogo de fixtures), crea y persiste", () => {
    const resultado = crearPreparacionPersistida(jornadaNueva);

    expect(resultado.ok).toBe(true);

    const jornadas = jornadasGuardadas();
    expect(jornadas).toHaveLength(1);
    expect(jornadas[0].id).toBe("jornada-nueva");
  });

  it("stock insuficiente reservado por jornadas leídas AHORA: aborta y no escribe", () => {
    sembrarCatalogo();
    const previa = jornadaPreparacion(110);
    mockLS.setItem(CLAVES_STORAGE.jornadas, rawJornadasDe([previa]));
    mockLS.setItem(CLAVES_STORAGE.retornos, "[]");
    mockLS.setItem.mockClear();

    const resultado = crearPreparacionPersistida(jornadaNueva);

    expect(resultado).toEqual({
      ok: false,
      error: "No hay stock suficiente de Yogur de prueba.",
    });

    // Raw intacto: la nueva jornada NO se agregó.
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe(
      rawJornadasDe([previa])
    );
  });

  it("retorno aprobado libera stock: jornadas cerradas + retornos leídos AHORA alcanzan", () => {
    sembrarCatalogo();
    mockLS.setItem(
      CLAVES_STORAGE.jornadas,
      rawJornadasDe([jornadaCerrada(110)])
    );
    mockLS.setItem(
      CLAVES_STORAGE.retornos,
      JSON.stringify([retornoAprobado(100)])
    );

    const resultado = crearPreparacionPersistida(jornadaNueva);

    expect(resultado.ok).toBe(true);

    const jornadas = jornadasGuardadas();
    expect(jornadas).toHaveLength(2);
    expect(jornadas.map((j) => j.id)).toContain("jornada-nueva");
  });

  it("jornadas corruptas: aborta con error concreto y raw intacto", () => {
    sembrarCatalogo();
    const rawCorrupto = "{jornadas dañadas";
    mockLS.setItem(CLAVES_STORAGE.jornadas, rawCorrupto);
    mockLS.setItem.mockClear();

    const resultado = crearPreparacionPersistida(jornadaNueva);

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("No se puede guardar la preparación");
    }
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe(rawCorrupto);
  });

  it("retornos corruptos: aborta con error concreto y raw intacto", () => {
    sembrarCatalogo();
    mockLS.setItem(CLAVES_STORAGE.jornadas, "[]");
    const rawCorrupto = "{retornos dañados";
    mockLS.setItem(CLAVES_STORAGE.retornos, rawCorrupto);
    mockLS.setItem.mockClear();

    const resultado = crearPreparacionPersistida(jornadaNueva);

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("No se puede guardar la preparación");
    }
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS.getItem(CLAVES_STORAGE.retornos)).toBe(rawCorrupto);
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe("[]");
  });

  it("productos corruptos: aborta con error concreto, sin escribir jornadas", () => {
    const rawCorrupto = "{productos dañados";
    mockLS.setItem(CLAVES_STORAGE.productos, rawCorrupto);
    mockLS.setItem(CLAVES_STORAGE.jornadas, "[]");
    mockLS.setItem.mockClear();

    const resultado = crearPreparacionPersistida(jornadaNueva);

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("No se puede guardar la preparación");
    }
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS.getItem(CLAVES_STORAGE.productos)).toBe(rawCorrupto);
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe("[]");
  });

  it("camión con jornada activa (id distinto): duplicado rechazado, raw intacto", () => {
    sembrarCatalogo();
    const previa = jornadaPreparacion(10);
    const rawPrevias = rawJornadasDe([previa]);
    mockLS.setItem(CLAVES_STORAGE.jornadas, rawPrevias);

    // Mismo camión que la jornada previa, id distinto: el camión ya tiene
    // una jornada en curso.
    const duplicada: Jornada = {
      ...jornadaNueva,
      camionId: 1,
    };

    const resultado = crearPreparacionPersistida(duplicada);

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("Ya existe una jornada activa");
    }
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe(rawPrevias);
  });

  it("id duplicado: rechazado sin escribir", () => {
    sembrarCatalogo();
    const previa = jornadaPreparacion(10);
    const rawPrevias = rawJornadasDe([previa]);
    mockLS.setItem(CLAVES_STORAGE.jornadas, rawPrevias);

    // Otro camión, mismo id: el id ya está registrado.
    const duplicadaId: Jornada = {
      ...previa,
      camionId: 2,
    };

    const resultado = crearPreparacionPersistida(duplicadaId);

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("Ya existe una jornada activa");
    }
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe(rawPrevias);
  });

  it("TOCTOU de productos: manda el stock del catálogo leído al persistir", () => {
    // El render pudo ver 120 u; al persistir el catálogo dice 50.
    sembrarCatalogo([{ ...yogur, stock: 50 }]);
    mockLS.setItem(CLAVES_STORAGE.jornadas, "[]");
    mockLS.setItem.mockClear();

    expect(crearPreparacionPersistida(jornadaNueva)).toEqual({
      ok: false,
      error: "No hay stock suficiente de Yogur de prueba.",
    });
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe("[]");

    // Si el catálogo leído AHORA alcanza, se persiste.
    sembrarCatalogo([{ ...yogur, stock: 100 }]);
    expect(crearPreparacionPersistida(jornadaNueva).ok).toBe(true);
  });

  it("orden de lectura: corrupción de jornadas tiene prioridad sobre el stock", () => {
    sembrarCatalogo([{ ...yogur, stock: 0 }]);
    mockLS.setItem(CLAVES_STORAGE.jornadas, "{roto");
    mockLS.setItem.mockClear();

    const resultado = crearPreparacionPersistida(jornadaNueva);

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("No se puede guardar la preparación");
    }
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });
});

describe("B2: preparación con productos peso (gramos enteros)", () => {
  beforeEach(() => {
    sembrarCatalogo();
    mockLS._store.set(CLAVES_STORAGE.jornadas, "[]");
    mockLS._store.set(CLAVES_STORAGE.retornos, "[]");
    mockLS.setItem.mockClear();
  });

  it("sólo peso: se persiste con los gramos exactos", () => {
    const resultado = crearPreparacionPersistida(nuevaCon([itemJamon(1250)]));

    expect(resultado.ok).toBe(true);
    const [guardada] = jornadasGuardadas();
    expect(guardada.estado).toBe("preparacion");
    expect(guardada.items).toEqual([itemJamon(1250)]);
  });

  it("mixta unidad + peso: se persiste con cada cantidad canónica intacta", () => {
    const items = [itemCargaDe(10), itemJamon(12345), itemSalame(1)];
    expect(crearPreparacionPersistida(nuevaCon(items)).ok).toBe(true);
    expect(jornadasGuardadas()[0].items).toEqual(items);
  });

  it("todo el stock (18000 g) alcanza; 1 g más se rechaza sin escribir", () => {
    expect(
      crearPreparacionPersistida(nuevaCon([itemJamon(18001)]))
    ).toEqual({ ok: false, error: "No hay stock suficiente de Jamón de prueba." });
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS._store.get(CLAVES_STORAGE.jornadas)).toBe("[]");

    expect(crearPreparacionPersistida(nuevaCon([itemJamon(18000)])).ok).toBe(true);
  });

  it("varias jornadas activas reservan gramos: el disponible es la resta exacta", () => {
    // 10000 g en preparación + 5000 g abierta = 15000 g reservados → 3000 g.
    const previas = rawJornadasDe([
      jornadaActiva("j-a", 1, [itemJamon(10000)]),
      jornadaActiva("j-b", 3, [itemJamon(5000), itemCargaDe(5)], "abierta"),
    ]);
    mockLS._store.set(CLAVES_STORAGE.jornadas, previas);

    expect(
      crearPreparacionPersistida(nuevaCon([itemJamon(3001)]))
    ).toEqual({ ok: false, error: "No hay stock suficiente de Jamón de prueba." });
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS._store.get(CLAVES_STORAGE.jornadas)).toBe(previas);

    expect(crearPreparacionPersistida(nuevaCon([itemJamon(3000)])).ok).toBe(true);
  });

  it("un producto peso sin stock suficiente rechaza toda la carga mixta", () => {
    // Yogur alcanza; salame (2500 g) no: no se guarda ninguna línea.
    expect(
      crearPreparacionPersistida(nuevaCon([itemCargaDe(10), itemSalame(2501)]))
    ).toEqual({ ok: false, error: "No hay stock suficiente de Salame de prueba." });
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });

  it("la misma línea repetida se suma antes de comparar con el disponible", () => {
    expect(
      crearPreparacionPersistida(nuevaCon([itemJamon(9000), itemJamon(9001)]))
    ).toEqual({ ok: false, error: "No hay stock suficiente de Jamón de prueba." });
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });

  it("forma de venta cambiada en el catálogo: rechaza sin convertir ni escribir", () => {
    const comoUnidad: ItemCarga = { ...itemJamon(5), unidadMedida: "unidad" };
    expect(crearPreparacionPersistida(nuevaCon([comoUnidad]))).toEqual({
      ok: false,
      error: "La forma de venta de Jamón de prueba cambió; revisá la carga.",
    });
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });

  it("producto ausente del catálogo leído AHORA: rechaza sin escribir", () => {
    sembrarCatalogo([yogur]);
    expect(crearPreparacionPersistida(nuevaCon([itemJamon(1)]))).toEqual({
      ok: false,
      error: "El producto Jamón de prueba ya no está en el catálogo.",
    });
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });

  it("overflow del reservado: falla cerrado sin escribir (nunca satura)", () => {
    const previas = rawJornadasDe([
      jornadaActiva("j-a", 1, [itemJamon(MAX)]),
      jornadaActiva("j-b", 3, [itemJamon(1)]),
    ]);
    mockLS._store.set(CLAVES_STORAGE.jornadas, previas);

    expect(crearPreparacionPersistida(nuevaCon([itemJamon(1)]))).toEqual({
      ok: false,
      error: MENSAJE_STOCK_NO_CALCULABLE,
    });
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS._store.get(CLAVES_STORAGE.jornadas)).toBe(previas);
  });

  it("overflow del pedido (líneas repetidas): falla cerrado sin escribir", () => {
    expect(
      crearPreparacionPersistida(nuevaCon([itemJamon(MAX), itemJamon(1)]))
    ).toEqual({ ok: false, error: MENSAJE_STOCK_NO_CALCULABLE });
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });
});

describe("calcularStockReservado / validarStockPreparacion (puras)", () => {
  it("suma en la unidad mínima de cada producto, sin mezclar unidades", () => {
    const reservado = calcularStockReservado(
      [
        jornadaActiva("j-a", 1, [itemJamon(1250), itemCargaDe(3)]),
        jornadaActiva("j-b", 2, [itemJamon(28680)], "abierta"),
      ],
      []
    );
    expect(reservado).toEqual({ 1: 3, 4: 29930 });
  });

  it("retorno aprobado de una jornada cerrada del mismo camión libera lo aprobado", () => {
    expect(
      calcularStockReservado([jornadaCerrada(110)], [retornoAprobado(100)])
    ).toEqual({ 1: 10 });
  });

  it("suma exacta hasta MAX_SAFE_INTEGER; un gramo más lanza", () => {
    expect(
      calcularStockReservado(
        [jornadaActiva("j-a", 1, [itemJamon(MAX - 1)]), jornadaActiva("j-b", 2, [itemJamon(1)])],
        []
      )
    ).toEqual({ 4: MAX });
    expect(() =>
      calcularStockReservado(
        [jornadaActiva("j-a", 1, [itemJamon(MAX)]), jornadaActiva("j-b", 2, [itemJamon(1)])],
        []
      )
    ).toThrow();
  });

  it("validarStockPreparacion: null si alcanza, error concreto si no", () => {
    expect(validarStockPreparacion([itemJamon(18000)], [jamon], [], [])).toBeNull();
    expect(validarStockPreparacion([itemJamon(18001)], [jamon], [], [])).toBe(
      "No hay stock suficiente de Jamón de prueba."
    );
  });
});

describe("calcularStockReservado: descuento de retornos sin resta ciega ni reservado negativo", () => {
  // Jornada cerrada del camión 1 con lo cargado indicado.
  const cerradaCon = (id: string, items: ItemCarga[]): Jornada => ({
    id,
    camionId: 1,
    chofer: `Chofer ${id}`,
    zona: "Centro",
    fechaCreacion: "2026-10-22T08:00:00.000Z",
    fechaSalida: "2026-10-22T09:00:00.000Z",
    estado: "cerrada",
    items,
    cierre: {
      fecha: "2026-10-22T18:00:00.000Z",
      conteos: Object.fromEntries(items.map((i) => [String(i.productoId), i.cantidad])),
      efectivoEntregado: 0,
      efectivoEsperado: 0,
      transferenciasInformadas: 0,
      ventasCuentaCorriente: 0,
      observaciones: "",
    },
  });

  const retornoDe = (
    id: string,
    jornadaId: string,
    items: Array<{
      productoId: number;
      unidadMedida: "unidad" | "peso";
      cantidadContada: number;
      cantidadAprobada: number;
    }>,
    camionId = 1
  ): RetornoDeposito => ({
    id,
    jornadaId,
    camionId,
    fecha: "2026-10-22T19:00:00.000Z",
    responsable: "Encargado de prueba",
    observaciones: "",
    items: items.map((i) => ({ nombreProducto: `P${i.productoId}`, ...i })),
  });

  it("aprobado igual a lo cargado deja el reservado exactamente en 0 (nunca negativo)", () => {
    const j = cerradaCon("c1", [itemCargaDe(110), itemJamon(1250)]);
    const r = retornoDe("r1", "c1", [
      { productoId: 1, unidadMedida: "unidad", cantidadContada: 110, cantidadAprobada: 110 },
      { productoId: 4, unidadMedida: "peso", cantidadContada: 1250, cantidadAprobada: 1250 },
    ]);
    expect(calcularStockReservado([j], [r])).toEqual({ 1: 0, 4: 0 });
  });

  it("aprobado mayor que lo cargado (contado con sobrante) lanza: no aumenta el disponible", () => {
    const j = cerradaCon("c1", [itemCargaDe(110)]);
    const r = retornoDe("r1", "c1", [
      { productoId: 1, unidadMedida: "unidad", cantidadContada: 200, cantidadAprobada: 150 },
    ]);
    expect(() => calcularStockReservado([j], [r])).toThrow(/supera lo cargado/);
  });

  it("peso: aprobar 1 g más que lo cargado lanza", () => {
    const j = cerradaCon("c1", [itemJamon(1250)]);
    const r = retornoDe("r1", "c1", [
      { productoId: 4, unidadMedida: "peso", cantidadContada: 1251, cantidadAprobada: 1251 },
    ]);
    expect(() => calcularStockReservado([j], [r])).toThrow(/supera lo cargado/);
  });

  it("dos retornos de la misma jornada que juntos superan lo cargado lanzan", () => {
    const j = cerradaCon("c1", [itemCargaDe(110)]);
    const r1 = retornoDe("r1", "c1", [
      { productoId: 1, unidadMedida: "unidad", cantidadContada: 60, cantidadAprobada: 60 },
    ]);
    const r2 = retornoDe("r2", "c1", [
      { productoId: 1, unidadMedida: "unidad", cantidadContada: 60, cantidadAprobada: 51 },
    ]);
    expect(() => calcularStockReservado([j], [r1, r2])).toThrow(/supera lo cargado/);
    // Si juntos no superan lo cargado, se descuentan exactos.
    const r3 = { ...r2, items: [{ ...r2.items[0], cantidadAprobada: 50 }] };
    expect(calcularStockReservado([j], [r1, r3])).toEqual({ 1: 0 });
  });

  it("lo aprobado de una jornada no puede compensar lo cargado en otra", () => {
    // 100 u cargadas en una jornada activa no habilitan aprobar 120 de una
    // cerrada que cargó 110.
    const activa = jornadaActiva("a1", 2, [itemCargaDe(100)]);
    const j = cerradaCon("c1", [itemCargaDe(110)]);
    const r = retornoDe("r1", "c1", [
      { productoId: 1, unidadMedida: "unidad", cantidadContada: 120, cantidadAprobada: 120 },
    ]);
    expect(() => calcularStockReservado([activa, j], [r])).toThrow(/supera lo cargado/);
  });

  it.each([
    [
      "producto no cargado en la jornada",
      { productoId: 5, unidadMedida: "peso" as const, cantidadContada: 1, cantidadAprobada: 1 },
    ],
    [
      "unidad distinta de la cargada",
      { productoId: 1, unidadMedida: "peso" as const, cantidadContada: 1, cantidadAprobada: 1 },
    ],
    [
      "aprobado no entero",
      { productoId: 1, unidadMedida: "unidad" as const, cantidadContada: 5, cantidadAprobada: 1.5 },
    ],
    [
      "aprobado negativo",
      { productoId: 1, unidadMedida: "unidad" as const, cantidadContada: 5, cantidadAprobada: -1 },
    ],
    [
      "aprobado mayor que contado",
      { productoId: 1, unidadMedida: "unidad" as const, cantidadContada: 5, cantidadAprobada: 6 },
    ],
  ])("ítem de retorno inconsistente (%s) lanza, no se ignora", (_n, item) => {
    const j = cerradaCon("c1", [itemCargaDe(110)]);
    expect(() =>
      calcularStockReservado([j], [retornoDe("r1", "c1", [item])])
    ).toThrow(/inconsistente/);
  });

  it.each([
    ["jornada inexistente", "no-existe", 1],
    ["otro camión", "c1", 9],
  ])("un retorno que no aplica (%s) no libera stock", (_n, jornadaId, camionId) => {
    const j = cerradaCon("c1", [itemCargaDe(110)]);
    const r = retornoDe(
      "r1",
      jornadaId,
      [{ productoId: 1, unidadMedida: "unidad", cantidadContada: 110, cantidadAprobada: 110 }],
      camionId
    );
    expect(calcularStockReservado([j], [r])).toEqual({ 1: 110 });
  });

  it("un retorno de una jornada no cerrada no libera stock", () => {
    const abierta = jornadaActiva("a1", 1, [itemCargaDe(110)], "abierta");
    const r = retornoDe("r1", "a1", [
      { productoId: 1, unidadMedida: "unidad", cantidadContada: 110, cantidadAprobada: 110 },
    ]);
    expect(calcularStockReservado([abierta], [r])).toEqual({ 1: 110 });
  });

  it("frontera: un retorno con aprobado mayor que lo cargado bloquea la preparación sin escribir", () => {
    sembrarCatalogo();
    const j = cerradaCon("c1", [itemCargaDe(110)]);
    const rawJornadas = rawJornadasDe([j]);
    const rawRetornos = JSON.stringify([
      retornoDe("r1", "c1", [
        { productoId: 1, unidadMedida: "unidad", cantidadContada: 200, cantidadAprobada: 150 },
      ]),
    ]);
    mockLS._store.set(CLAVES_STORAGE.jornadas, rawJornadas);
    mockLS._store.set(CLAVES_STORAGE.retornos, rawRetornos);
    mockLS.setItem.mockClear();

    // Sin el bloqueo, el reservado sería 110 - 150 = -40 y el disponible del
    // yogur pasaría de 120 a 160.
    expect(crearPreparacionPersistida(nuevaCon([itemCargaDe(130)]))).toEqual({
      ok: false,
      error: MENSAJE_STOCK_NO_CALCULABLE,
    });
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS._store.get(CLAVES_STORAGE.jornadas)).toBe(rawJornadas);
    expect(mockLS._store.get(CLAVES_STORAGE.retornos)).toBe(rawRetornos);
  });

  it("frontera: catálogo con menos stock que lo reservado rechaza cualquier pedido (sin Math.max)", () => {
    // 110 u reservadas en una jornada activa; el catálogo bajó a 100 u.
    sembrarCatalogo([{ ...yogur, stock: 100 }]);
    mockLS._store.set(
      CLAVES_STORAGE.jornadas,
      rawJornadasDe([jornadaActiva("a1", 1, [itemCargaDe(110)])])
    );
    mockLS.setItem.mockClear();

    expect(validarStockPreparacion([itemCargaDe(1)], [{ ...yogur, stock: 100 }], [jornadaActiva("a1", 1, [itemCargaDe(110)])], [])).toBe(
      "No hay stock suficiente de Yogur de prueba."
    );
    expect(crearPreparacionPersistida(nuevaCon([itemCargaDe(1)]))).toEqual({
      ok: false,
      error: "No hay stock suficiente de Yogur de prueba.",
    });
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });
});

describe("B2: ciclo de una jornada peso (preparación → abierta; cierre bloqueado hasta B4)", () => {
  const cierrePeso = {
    fecha: "2026-10-22T18:00:00.000Z",
    conteos: { "4": 1250 },
    efectivoEntregado: 0,
    efectivoEsperado: 0,
    transferenciasInformadas: 0,
    ventasCuentaCorriente: 0,
    observaciones: "",
  };

  it("preparar y confirmar están permitidos; cerrar se rechaza sin escribir", () => {
    sembrarCatalogo();

    // 1) Preparación peso: permitida.
    expect(crearPreparacionPersistida(nuevaCon([itemJamon(1250)])).ok).toBe(true);

    // 2) preparacion → abierta: permitida.
    const salida = confirmarSalidaPersistida("jornada-nueva");
    expect(salida.ok).toBe(true);
    const abierta = leerJornadas()[0];
    expect(abierta.estado).toBe("abierta");
    expect(abierta.fechaSalida).not.toBeNull();

    // 3) abierta → cerrada: rechazada mientras tenga peso, sin escritura.
    const rawAbierta = String(mockLS.getItem(CLAVES_STORAGE.jornadas));
    mockLS.setItem.mockClear();

    expect(cerrarJornadaPersistida("jornada-nueva", cierrePeso)).toBeNull();
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe(rawAbierta);
    expect(leerJornadas()[0].estado).toBe("abierta");
    expect(leerJornadas()[0].cierre).toBeUndefined();
  });
});

describe("security review B2: la frontera sólo crea preparaciones nuevas válidas", () => {
  const SALIDA = "2026-10-22T11:00:00.000Z";
  const cierrePeso = {
    fecha: "2026-10-22T18:00:00.000Z",
    conteos: { "4": 1250 },
    efectivoEntregado: 0,
    efectivoEsperado: 0,
    transferenciasInformadas: 0,
    ventasCuentaCorriente: 0,
    observaciones: "",
  };
  const conJamon = () => nuevaCon([itemJamon(1250)]);

  beforeEach(() => {
    sembrarCatalogo();
    mockLS._store.set(
      CLAVES_STORAGE.jornadas,
      rawJornadasDe([jornadaActiva("previa", 9, [itemCargaDe(1)])])
    );
    mockLS._store.set(CLAVES_STORAGE.retornos, "[]");
    mockLS.setItem.mockClear();
  });

  it.each([
    ["cantidad 0 (peso)", () => nuevaCon([itemJamon(0)])],
    ["cantidad 0 (unidad)", () => nuevaCon([itemCargaDe(0)])],
    ["estado abierta", () => ({ ...conJamon(), estado: "abierta", fechaSalida: SALIDA })],
    ["estado cerrada con cierre", () => ({ ...conJamon(), estado: "cerrada", fechaSalida: SALIDA, cierre: cierrePeso })],
    ["preparación con fechaSalida", () => ({ ...conJamon(), fechaSalida: SALIDA })],
    ["preparación con cierre", () => ({ ...conJamon(), cierre: cierrePeso })],
    ["precio de referencia inválido", () => nuevaCon([{ ...itemJamon(1250), precioReferencia: -1 }])],
  ])("%s: rechaza, 0 setItem y raw intacto", (_n, crear) => {
    const raw = mockLS._store.get(CLAVES_STORAGE.jornadas);

    expect(crearPreparacionPersistida(crear() as Jornada)).toEqual({
      ok: false,
      error: MENSAJE_PREPARACION_INVALIDA,
    });
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS._store.get(CLAVES_STORAGE.jornadas)).toBe(raw);
    // El ledger sigue siendo legible: nada quedó corrupto.
    expect(leerJornadas().map((j) => j.id)).toEqual(["previa"]);
  });

  it("con storage ausente tampoco crea la clave", () => {
    mockLS._store.delete(CLAVES_STORAGE.jornadas);
    expect(crearPreparacionPersistida(nuevaCon([itemJamon(0)])).ok).toBe(false);
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBeNull();
  });

  it("control: una preparación válida sigue persistiendo", () => {
    expect(crearPreparacionPersistida(conJamon()).ok).toBe(true);
    expect(mockLS.setItem).toHaveBeenCalledTimes(1);
    const guardadas = jornadasGuardadas();
    expect(guardadas.map((j) => j.id)).toEqual(["previa", "jornada-nueva"]);
    expect(guardadas[1]).toEqual(conJamon());
  });
});
