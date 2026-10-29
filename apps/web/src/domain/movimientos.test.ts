// Pruebas del dominio de movimientos de reparto (ADR-005).
//
// Estado B2 (dominio):
//   - `unidad` funciona igual que antes (entrada, stock, merma, cambio,
//     devolución y acumulación segura).
//   - `peso`: entrada en kg con coma y hasta 3 decimales, a gramos enteros
//     con kg_a_gramos (sin punto flotante).
//   - Cambio: unidad ↔ unidad y peso ↔ peso; unidad ↔ peso es inválido.
//   - `pieza` se rechaza.
import { describe, expect, it, vi } from "vitest";

import type {
  MovimientoReparto,
  ProductoMovimiento,
} from "../data/mockMovimientos";
import {
  cantidad_movimiento_desde_entrada,
  disponibilidad_de_jornada,
  disponibles_de_jornada,
  es_cambio_mixto,
  MENSAJE_CAMBIO_MIXTO_NO_HABILITADO,
  MENSAJE_SALIDAS_SUPERAN_CARGA,
  MENSAJE_STOCK_JORNADA_NO_CALCULABLE,
  MENSAJE_VENTA_CARGA_INCONSISTENTE,
  MENSAJE_VENTA_SALIDAS_SUPERAN_CARGA,
  movimiento_valido,
  salidas_de_jornada,
  validar_stock_movimiento,
  validar_stock_venta,
} from "./movimientos";
import { registrarMovimientoOperacion } from "../hooks/useMovimientos";

const yogur = (cantidad: number): ProductoMovimiento => ({
  productoId: 1,
  nombreProducto: "Yogur",
  unidadMedida: "unidad",
  cantidad,
});

const leche = (cantidad: number): ProductoMovimiento => ({
  productoId: 2,
  nombreProducto: "Leche",
  unidadMedida: "unidad",
  cantidad,
});

// Ítems `peso` (gramos enteros).
const jamon = (gramos: number): ProductoMovimiento => ({
  productoId: 4,
  nombreProducto: "Jamón cocido",
  unidadMedida: "peso",
  cantidad: gramos,
});

const salame = (gramos: number): ProductoMovimiento => ({
  productoId: 5,
  nombreProducto: "Salame milán",
  unidadMedida: "peso",
  cantidad: gramos,
});

const base = {
  id: "m1",
  jornadaId: "j1",
  camionId: 1,
  fecha: "2026-10-21T10:00:00.000Z",
  motivo: "Envase roto o dañado",
};

const merma = (producto: ProductoMovimiento): MovimientoReparto => ({
  ...base,
  tipo: "merma",
  producto,
  clienteId: null,
  nombreCliente: null,
});

const cambio = (
  devuelto: ProductoMovimiento,
  entregado: ProductoMovimiento
): MovimientoReparto => ({
  ...base,
  tipo: "cambio",
  clienteId: 7,
  nombreCliente: "Almacén",
  productoDevuelto: devuelto,
  productoEntregado: entregado,
});

const devolucion = (producto: ProductoMovimiento): MovimientoReparto => ({
  ...base,
  tipo: "devolucion",
  clienteId: 7,
  nombreCliente: "Almacén",
  producto,
});

describe("cantidad_movimiento_desde_entrada", () => {
  it("unidad: cantidad entera positiva es válida", () => {
    expect(cantidad_movimiento_desde_entrada("unidad", { texto: "2" })).toBe(2);
  });

  it.each(["", "0", "1.5", "NaN", "Infinity", "-1", "-0.5", "abc"])(
    "unidad rechaza %j",
    (texto) => {
      expect(cantidad_movimiento_desde_entrada("unidad", { texto })).toBeNull();
    }
  );

  it.each([
    ["1,250", 1250],
    ["28,680", 28680],
    ["1,005", 1005],
    ["1", 1000],
    ["1,2", 1200],
    ["0,5", 500],
    ["0,001", 1],
    [" 1,250 ", 1250],
  ])("peso: %j kg → %i g (exacto, sin punto flotante)", (texto, gramos) => {
    expect(cantidad_movimiento_desde_entrada("peso", { texto })).toBe(gramos);
  });

  it.each([
    "",
    " ",
    "0",
    "0,000",
    "1,2345",
    "1.250",
    "1.5",
    "-1",
    "-0,5",
    "1,",
    ",5",
    "abc",
    "NaN",
    "Infinity",
  ])("peso rechaza %j", (texto) => {
    expect(cantidad_movimiento_desde_entrada("peso", { texto })).toBeNull();
  });

  it("peso en el límite seguro: MAX_SAFE_INTEGER g es válido; 1 g más → null, sin throw", () => {
    expect(
      cantidad_movimiento_desde_entrada("peso", { texto: "9007199254740,991" })
    ).toBe(Number.MAX_SAFE_INTEGER);
    expect(() =>
      cantidad_movimiento_desde_entrada("peso", { texto: "9007199254740,992" })
    ).not.toThrow();
    expect(
      cantidad_movimiento_desde_entrada("peso", { texto: "9007199254740,992" })
    ).toBeNull();
  });

  it.each(["pieza", "kg"])("'%s' no es una unidad válida", (unidad) => {
    expect(
      cantidad_movimiento_desde_entrada(unidad as never, { texto: "1" })
    ).toBeNull();
  });

  it("unidad fuera del rango seguro → null, sin throw", () => {
    const texto = String(Number.MAX_SAFE_INTEGER + 1);
    expect(() =>
      cantidad_movimiento_desde_entrada("unidad", { texto })
    ).not.toThrow();
    expect(cantidad_movimiento_desde_entrada("unidad", { texto })).toBeNull();
  });
});

describe("movimiento_valido: storage v5", () => {
  it("unidad con cantidad entera es válido", () => {
    expect(movimiento_valido(merma(yogur(2)))).toBe(true);
  });

  it("peso con gramos enteros es válido en merma, devolución y cambio peso ↔ peso", () => {
    expect(movimiento_valido(merma(jamon(1250)))).toBe(true);
    expect(movimiento_valido(devolucion(jamon(9)))).toBe(true);
    // Cada lado con su propia cantidad canónica, sin relación entre ambas.
    expect(movimiento_valido(cambio(jamon(1250), salame(980)))).toBe(true);
    expect(movimiento_valido(cambio(jamon(1250), jamon(1250)))).toBe(true);
  });

  it("cambio unidad ↔ unidad sigue siendo válido", () => {
    expect(movimiento_valido(cambio(yogur(2), leche(3)))).toBe(true);
  });

  it.each([
    ["unidad ↔ peso", cambio(yogur(2), jamon(1250))],
    ["peso ↔ unidad", cambio(jamon(1250), yogur(2))],
  ])("cambio %s es inválido (sin semántica aprobada)", (_n, movimiento) => {
    expect(movimiento_valido(movimiento)).toBe(false);
  });

  it("es_cambio_mixto compara sólo la unidad canónica de cada lado", () => {
    expect(es_cambio_mixto(yogur(1), jamon(1))).toBe(true);
    expect(es_cambio_mixto(jamon(1), yogur(1))).toBe(true);
    expect(es_cambio_mixto(jamon(1), salame(1))).toBe(false);
    expect(es_cambio_mixto(yogur(1), leche(1))).toBe(false);
  });

  it("peso con gramos fraccionarios es inválido", () => {
    expect(movimiento_valido(merma(jamon(1250.5)))).toBe(false);
  });

  it.each(["pieza", "media_pieza", "kg"])("rechaza la unidad '%s'", (unidad) => {
    const producto = { ...yogur(1), unidadMedida: unidad } as unknown;
    expect(movimiento_valido({ ...merma(yogur(1)), producto })).toBe(false);
  });

  it.each([0, 1.5, NaN, Infinity, -Infinity, -1])("rechaza cantidad %s", (c) => {
    expect(movimiento_valido(merma(yogur(c)))).toBe(false);
    expect(movimiento_valido(merma(jamon(c)))).toBe(false);
  });

  it("una cantidad inválida en cualquiera de los dos lados invalida el cambio", () => {
    expect(movimiento_valido(cambio(yogur(2), leche(1.5)))).toBe(false);
    expect(movimiento_valido(cambio(yogur(0.5), leche(3)))).toBe(false);
  });
});

describe("merma (unidad)", () => {
  it("disponible 5, merma de 1: salida 1, restante 4", () => {
    const m = merma(yogur(1));
    const cargados = [{ productoId: 1, unidadMedida: "unidad" as const, cantidad: 5 }];

    expect(validar_stock_movimiento(m, cargados, [], [])).toBeNull();

    const salidas = salidas_de_jornada("j1", [], [m]);
    expect(salidas[1]).toBe(1);
    expect(disponibles_de_jornada(cargados, salidas)[1]).toBe(4);
  });

  it("rechaza stock insuficiente con enteros exactos", () => {
    const cargados = [{ productoId: 1, unidadMedida: "unidad" as const, cantidad: 5 }];
    expect(
      validar_stock_movimiento(merma(yogur(6)), cargados, [], [])
    ).toMatch(/Stock insuficiente/);
    expect(
      validar_stock_movimiento(merma(yogur(5)), cargados, [], [])
    ).toBeNull();
  });

  it("descuenta ventas y movimientos previos de la misma jornada", () => {
    const cargados = [{ productoId: 1, unidadMedida: "unidad" as const, cantidad: 5 }];
    const ventas = [
      { jornadaId: "j1", items: [{ productoId: 1, unidadMedida: "unidad" as const, cantidad: 2 }] },
    ];
    const previo = { ...merma(yogur(2)), id: "m0" };

    expect(
      validar_stock_movimiento(merma(yogur(1)), cargados, ventas, [previo])
    ).toBeNull();
    expect(
      validar_stock_movimiento(merma(yogur(2)), cargados, ventas, [previo])
    ).toMatch(/Stock insuficiente/);
  });

  it("rechaza producto no cargado", () => {
    expect(validar_stock_movimiento(merma(leche(1)), [], [], [])).toMatch(
      /no está cargado/
    );
  });
});

describe("cambio (unidad)", () => {
  it("sólo el entregado descuenta mercadería del camión", () => {
    const m = cambio(yogur(2), leche(3));
    expect(movimiento_valido(m)).toBe(true);
    expect(salidas_de_jornada("j1", [], [m])).toEqual({ 2: 3 });
  });

  it("el entregado se valida contra su disponible", () => {
    const m = cambio(leche(3), yogur(2));
    expect(
      validar_stock_movimiento(
        m,
        [{ productoId: 1, unidadMedida: "unidad", cantidad: 1 }],
        [],
        []
      )
    ).toMatch(/Stock insuficiente/);
  });
});

describe("devolución (unidad)", () => {
  it("no descuenta ni reincorpora stock", () => {
    const m = devolucion(yogur(1));
    expect(movimiento_valido(m)).toBe(true);

    const cargados = [{ productoId: 1, unidadMedida: "unidad" as const, cantidad: 5 }];
    const salidas = salidas_de_jornada("j1", [], [m]);
    expect(salidas).toEqual({});
    expect(disponibles_de_jornada(cargados, salidas)[1]).toBe(5);
  });
});

describe("registrarMovimientoOperacion: peso habilitado en B2; cambio mixto rechazado", () => {
  function registrar(movimiento: MovimientoReparto) {
    const cargar = vi.fn(() => ({
      ok: true as const,
      movimientos: [] as MovimientoReparto[],
      estado: "valido" as const,
    }));
    const validar = vi.fn().mockReturnValue(null);
    const resultado = registrarMovimientoOperacion(movimiento, validar, cargar);
    return { resultado, cargar, validar };
  }

  // Antes (B1): «%s peso se rechaza sin leer, validar ni persistir».
  it.each([
    ["merma", merma(jamon(1250))],
    ["devolución", devolucion(jamon(1250))],
    ["cambio peso ↔ peso", cambio(jamon(1250), salame(980))],
  ])("%s peso: lee, valida y devuelve el ledger con los gramos exactos", (_nombre, movimiento) => {
    const { resultado, cargar, validar } = registrar(movimiento);

    expect(resultado).toEqual({ ok: true, movimientos: [movimiento] });
    expect(cargar).toHaveBeenCalledTimes(1);
    expect(validar).toHaveBeenCalledTimes(1);
  });

  // Antes (paso 2): el rechazo usaba el mensaje genérico de validación.
  it.each([
    ["unidad ↔ peso", cambio(yogur(1), jamon(1250))],
    ["peso ↔ unidad", cambio(jamon(1250), yogur(1))],
  ])("cambio %s se rechaza con el mensaje específico, sin leer ni validar", (_n, movimiento) => {
    const { resultado, cargar, validar } = registrar(movimiento);

    expect(resultado).toEqual({ ok: false, error: MENSAJE_CAMBIO_MIXTO_NO_HABILITADO });
    expect(cargar).not.toHaveBeenCalled();
    expect(validar).not.toHaveBeenCalled();
  });

  it("un cambio mixto con una cantidad inválida recibe el mensaje genérico", () => {
    const { resultado, cargar, validar } = registrar(cambio(yogur(1.5), jamon(1250)));
    expect(resultado).toEqual({
      ok: false,
      error: "El movimiento no es válido: las cantidades deben ser enteros positivos y seguros.",
    });
    expect(cargar).not.toHaveBeenCalled();
    expect(validar).not.toHaveBeenCalled();
  });

  it("un movimiento unidad válido devuelve el ledger con el movimiento", () => {
    const m = merma(yogur(1));
    const { resultado } = registrar(m);

    expect(resultado).toEqual({ ok: true, movimientos: [m] });
  });
});

const MAX = Number.MAX_SAFE_INTEGER;

describe("M-1: acumulación segura en la ruta real de disponibilidad", () => {
  const venta = (cantidad: number, jornadaId = "j1") => ({
    jornadaId,
    items: [{ productoId: 1, unidadMedida: "unidad" as const, cantidad }],
  });

  it("suma exacta a MAX_SAFE_INTEGER está permitida", () => {
    const salidas = salidas_de_jornada(
      "j1",
      [venta(MAX - 1), venta(1)],
      []
    );
    expect(salidas[1]).toBe(MAX);
  });

  it("una suma que excede MAX_SAFE_INTEGER lanza", () => {
    expect(() =>
      salidas_de_jornada("j1", [venta(MAX), venta(1)], [])
    ).toThrow(/Desbordamiento/);
  });

  it("overflow por varias ventas", () => {
    const mitad = Math.floor(MAX / 2);
    expect(() =>
      salidas_de_jornada("j1", [venta(mitad), venta(mitad), venta(2)], [])
    ).toThrow(/Desbordamiento/);
  });

  it("overflow por ventas + movimientos", () => {
    expect(() =>
      salidas_de_jornada("j1", [venta(MAX - 1)], [merma(yogur(2))])
    ).toThrow(/Desbordamiento/);
  });

  it("ventas de otra jornada no cuentan para el desbordamiento", () => {
    expect(() =>
      salidas_de_jornada("j1", [venta(MAX), venta(MAX, "j2")], [])
    ).not.toThrow();
  });

  it("una cantidad inválida en una venta falla cerrado", () => {
    expect(() => salidas_de_jornada("j1", [venta(1.5)], [])).toThrow();
    expect(() => salidas_de_jornada("j1", [venta(-1)], [])).toThrow();
  });

  it("disponibles_de_jornada falla si lo cargado no es canónico", () => {
    expect(() =>
      disponibles_de_jornada([{ productoId: 1, cantidad: MAX + 1 }], {})
    ).toThrow();
  });

  it("disponibilidad_de_jornada devuelve ok:false (sin saldo aproximado)", () => {
    const r = disponibilidad_de_jornada(
      "j1",
      [{ productoId: 1, cantidad: MAX }],
      [venta(MAX), venta(1)],
      []
    );
    expect(r.ok).toBe(false);
    expect("disponibles" in r).toBe(false);
  });

  it("validar_stock_movimiento NO autoriza si el acumulado es inseguro", () => {
    const cargados = [{ productoId: 1, unidadMedida: "unidad" as const, cantidad: MAX }];
    const error = validar_stock_movimiento(
      merma(yogur(1)),
      cargados,
      [venta(MAX), venta(1)],
      []
    );
    expect(error).toMatch(/No se puede calcular/);
  });

  it("con acumulado seguro en el límite exacto: disponible 0 y rechaza otra salida", () => {
    const cargados = [{ productoId: 1, unidadMedida: "unidad" as const, cantidad: MAX }];
    expect(
      validar_stock_movimiento(merma(yogur(1)), cargados, [venta(MAX)], [])
    ).toMatch(/Stock insuficiente/);
    expect(
      validar_stock_movimiento(merma(yogur(1)), cargados, [venta(MAX - 1)], [])
    ).toBeNull();
  });
});

describe("validar_stock_movimiento: unidad del movimiento vs carga (sin conversión)", () => {
  const cargaJamon = [{ productoId: 4, unidadMedida: "peso" as const, cantidad: 1250 }];
  const cargaYogur = [{ productoId: 1, unidadMedida: "unidad" as const, cantidad: 10 }];
  const jamonComoUnidad: ProductoMovimiento = { ...jamon(5), unidadMedida: "unidad" };
  const yogurComoPeso: ProductoMovimiento = { ...yogur(1000), unidadMedida: "peso" };

  it.each([
    ["merma: carga peso + movimiento unidad", merma(jamonComoUnidad), cargaJamon],
    ["merma: carga unidad + movimiento peso", merma(yogurComoPeso), cargaYogur],
    ["devolución: carga peso + movimiento unidad", devolucion(jamonComoUnidad), cargaJamon],
    ["cambio: lado devuelto con otra unidad", cambio(yogurComoPeso, salame(1)), [...cargaYogur, { productoId: 5, unidadMedida: "peso" as const, cantidad: 980 }]],
    ["cambio: lado entregado con otra unidad", cambio(leche(1), { ...yogur(1), unidadMedida: "peso" }), cargaYogur],
  ])("%s → rechaza", (_n, movimiento, cargados) => {
    expect(validar_stock_movimiento(movimiento, cargados, [], [])).toMatch(
      /no coincide con la cargada/
    );
  });

  it("la misma unidad en ambos lados se acepta", () => {
    expect(validar_stock_movimiento(merma(jamon(5)), cargaJamon, [], [])).toBeNull();
    expect(validar_stock_movimiento(merma(yogur(1)), cargaYogur, [], [])).toBeNull();
  });
});

describe("validar_stock_movimiento: salidas existentes mayores que lo cargado", () => {
  const cargaJamon = [{ productoId: 4, unidadMedida: "peso" as const, cantidad: 1250 }];

  it("carga 1250 g y salidas previas de 1300 g: un movimiento nuevo, incluso de 1 g, se rechaza", () => {
    const previos = [{ ...merma(jamon(1000)), id: "p1" }, { ...merma(jamon(300)), id: "p2" }];
    expect(validar_stock_movimiento(merma(jamon(1)), cargaJamon, [], previos)).toBe(
      MENSAJE_SALIDAS_SUPERAN_CARGA
    );
    // La inconsistencia bloquea cualquier operación nueva de la jornada.
    expect(validar_stock_movimiento(devolucion(jamon(1)), cargaJamon, [], previos)).toBe(
      MENSAJE_SALIDAS_SUPERAN_CARGA
    );
  });

  it("ventas previas mayores que lo cargado también bloquean", () => {
    // Las ventas son siempre `unidad` hasta B3 (D-R1).
    const cargaYogur = [{ productoId: 1, unidadMedida: "unidad" as const, cantidad: 10 }];
    const ventas = [
      { jornadaId: "j1", items: [{ productoId: 1, unidadMedida: "unidad" as const, cantidad: 11 }] },
    ];
    expect(validar_stock_movimiento(merma(yogur(1)), cargaYogur, ventas, [])).toBe(
      MENSAJE_SALIDAS_SUPERAN_CARGA
    );
  });

  it("salidas de un producto no cargado son inconsistentes", () => {
    const previos = [{ ...merma(salame(1)), id: "p1" }];
    expect(validar_stock_movimiento(merma(jamon(1)), cargaJamon, [], previos)).toBe(
      MENSAJE_SALIDAS_SUPERAN_CARGA
    );
  });

  it("salidas iguales a lo cargado no son inconsistentes: disponible 0 y rechaza por stock", () => {
    const previos = [{ ...merma(jamon(1250)), id: "p1" }];
    expect(validar_stock_movimiento(merma(jamon(1)), cargaJamon, [], previos)).toBe(
      "Stock insuficiente de Jamón cocido."
    );
  });

  it("overflow acumulando lo cargado (líneas repetidas) no es calculable", () => {
    const repetida = [
      { productoId: 4, unidadMedida: "peso" as const, cantidad: MAX },
      { productoId: 4, unidadMedida: "peso" as const, cantidad: 1 },
    ];
    expect(validar_stock_movimiento(merma(jamon(1)), repetida, [], [])).toBe(
      MENSAJE_STOCK_JORNADA_NO_CALCULABLE
    );
  });

  it("overflow acumulando salidas en gramos no es calculable", () => {
    const enorme = [{ productoId: 4, unidadMedida: "peso" as const, cantidad: MAX }];
    const previos = [{ ...merma(jamon(MAX)), id: "p1" }, { ...merma(jamon(1)), id: "p2" }];
    expect(validar_stock_movimiento(merma(jamon(1)), enorme, [], previos)).toBe(
      MENSAJE_STOCK_JORNADA_NO_CALCULABLE
    );
  });
});

describe("security review B2: unidad de las salidas históricas vs carga (sin sumar unidades distintas)", () => {
  const cargaJamon = [{ productoId: 4, unidadMedida: "peso" as const, cantidad: 1250 }];
  const cargaYogur = [{ productoId: 1, unidadMedida: "unidad" as const, cantidad: 10 }];

  it.each([
    [
      "carga peso + merma histórica unidad",
      cargaJamon,
      [{ ...merma({ ...jamon(5), unidadMedida: "unidad" }), id: "p1" }],
      [],
      merma(jamon(1)),
    ],
    [
      "carga unidad + merma histórica peso",
      cargaYogur,
      [{ ...merma({ ...yogur(5), unidadMedida: "peso" }), id: "p1" }],
      [],
      merma(yogur(1)),
    ],
    [
      "carga unidad + entregado histórico de un cambio en peso",
      cargaYogur,
      [{ ...cambio(jamon(1), { ...yogur(5), unidadMedida: "peso" }), id: "p1" }],
      [],
      merma(yogur(1)),
    ],
    [
      "carga peso + venta histórica unidad",
      cargaJamon,
      [],
      [{ jornadaId: "j1", items: [{ productoId: 4, unidadMedida: "unidad" as const, cantidad: 5 }] }],
      merma(jamon(1)),
    ],
  ])("%s: bloquea la operación nueva", (_n, cargados, previos, ventas, nuevo) => {
    expect(validar_stock_movimiento(nuevo, cargados, ventas, previos)).toBe(
      MENSAJE_SALIDAS_SUPERAN_CARGA
    );
  });

  it("bloquea aunque la suma mezclada todavía entraría en lo cargado (5 + 995 ≤ 1250)", () => {
    const previos = [{ ...merma({ ...jamon(5), unidadMedida: "unidad" }), id: "p1" }];
    expect(validar_stock_movimiento(merma(jamon(995)), cargaJamon, [], previos)).toBe(
      MENSAJE_SALIDAS_SUPERAN_CARGA
    );
  });

  it("salidas históricas de otra jornada no se consideran", () => {
    const ajena = { ...merma({ ...jamon(5), unidadMedida: "unidad" }), id: "p1", jornadaId: "j2" };
    expect(validar_stock_movimiento(merma(jamon(1)), cargaJamon, [], [ajena])).toBeNull();
  });

  it("control: salidas históricas con la misma unidad se descuentan normalmente", () => {
    const previos = [{ ...merma(jamon(1000)), id: "p1" }];
    expect(validar_stock_movimiento(merma(jamon(250)), cargaJamon, [], previos)).toBeNull();
    expect(validar_stock_movimiento(merma(jamon(251)), cargaJamon, [], previos)).toBe(
      "Stock insuficiente de Jamón cocido."
    );
  });
});

describe("validar_stock_venta (AUD-001)", () => {
  const MAX = Number.MAX_SAFE_INTEGER;
  // Carga de j1: Leche 3 unidades, Jamón 1250 g.
  const cargados = [
    { productoId: 2, unidadMedida: "unidad" as const, cantidad: 3 },
    { productoId: 4, unidadMedida: "peso" as const, cantidad: 1250 },
  ];
  const nueva = (...items: ProductoMovimiento[]) => ({ jornadaId: "j1", items });
  const previa = (jornadaId: string, ...items: ProductoMovimiento[]) => ({
    jornadaId,
    items,
  });

  it("unidad: exacto se acepta; +1 se rechaza", () => {
    expect(validar_stock_venta(nueva(leche(3)), cargados, [], [])).toBeNull();
    expect(validar_stock_venta(nueva(leche(4)), cargados, [], [])).toBe(
      "Stock insuficiente de Leche."
    );
  });

  it("unidad: descuenta lo ya vendido en la jornada", () => {
    const ventas = [previa("j1", leche(1))];
    expect(validar_stock_venta(nueva(leche(2)), cargados, ventas, [])).toBeNull();
    expect(validar_stock_venta(nueva(leche(3)), cargados, ventas, [])).toBe(
      "Stock insuficiente de Leche."
    );
  });

  it("peso: exacto (1250 g) se acepta; +1 g se rechaza", () => {
    expect(validar_stock_venta(nueva(jamon(1250)), cargados, [], [])).toBeNull();
    expect(validar_stock_venta(nueva(jamon(1251)), cargados, [], [])).toBe(
      "Stock insuficiente de Jamón cocido."
    );
  });

  it("dos líneas del mismo producto unidad: suma exacta se acepta; excedida se rechaza", () => {
    expect(
      validar_stock_venta(nueva(leche(1), leche(2)), cargados, [], [])
    ).toBeNull();
    expect(validar_stock_venta(nueva(leche(2), leche(2)), cargados, [], [])).toBe(
      "Stock insuficiente de Leche."
    );
  });

  it("dos líneas del mismo producto peso: suma exacta se acepta; 1 g de más se rechaza", () => {
    expect(
      validar_stock_venta(nueva(jamon(1000), jamon(250)), cargados, [], [])
    ).toBeNull();
    expect(
      validar_stock_venta(nueva(jamon(1000), jamon(251)), cargados, [], [])
    ).toBe("Stock insuficiente de Jamón cocido.");
  });

  it("carga contradictoria se rechaza aunque el producto no se venda", () => {
    const contradictoria = [
      ...cargados,
      { productoId: 4, unidadMedida: "unidad" as const, cantidad: 5 },
    ];
    expect(validar_stock_venta(nueva(leche(1)), contradictoria, [], [])).toBe(
      MENSAJE_VENTA_CARGA_INCONSISTENTE
    );
  });

  it("unidad nueva incompatible con la cargada se rechaza", () => {
    const lechePorPeso: ProductoMovimiento = { ...leche(1), unidadMedida: "peso" };
    expect(validar_stock_venta(nueva(lechePorPeso), cargados, [], [])).toBe(
      "La forma de venta de Leche no coincide con la cargada en la jornada."
    );
  });

  it("unidad histórica incompatible con la cargada se rechaza", () => {
    const jamonComoUnidad: ProductoMovimiento = { ...jamon(1), unidadMedida: "unidad" };
    expect(
      validar_stock_venta(nueva(leche(1)), cargados, [previa("j1", jamonComoUnidad)], [])
    ).toBe(MENSAJE_VENTA_SALIDAS_SUPERAN_CARGA);
  });

  it("producto no cargado se rechaza", () => {
    expect(validar_stock_venta(nueva(yogur(1)), cargados, [], [])).toBe(
      "Yogur no está cargado en el camión."
    );
  });

  it("salida histórica de un producto no cargado se rechaza", () => {
    expect(
      validar_stock_venta(nueva(leche(1)), cargados, [previa("j1", yogur(1))], [])
    ).toBe(MENSAJE_VENTA_SALIDAS_SUPERAN_CARGA);
  });

  it("saldo histórico negativo de OTRO producto se rechaza (sin Math.max)", () => {
    expect(
      validar_stock_venta(nueva(leche(1)), cargados, [previa("j1", jamon(1300))], [])
    ).toBe(MENSAJE_VENTA_SALIDAS_SUPERAN_CARGA);
  });

  it("overflow al acumular la carga → no calculable", () => {
    const cargaDesbordada = [
      { productoId: 2, unidadMedida: "unidad" as const, cantidad: MAX },
      { productoId: 2, unidadMedida: "unidad" as const, cantidad: 1 },
    ];
    expect(validar_stock_venta(nueva(leche(1)), cargaDesbordada, [], [])).toBe(
      MENSAJE_STOCK_JORNADA_NO_CALCULABLE
    );
  });

  it("overflow al acumular ventas previas → no calculable", () => {
    const ventas = [previa("j1", leche(MAX)), previa("j1", leche(1))];
    expect(validar_stock_venta(nueva(leche(1)), cargados, ventas, [])).toBe(
      MENSAJE_STOCK_JORNADA_NO_CALCULABLE
    );
  });

  it("overflow al agrupar el pedido nuevo → no calculable", () => {
    expect(validar_stock_venta(nueva(leche(MAX), leche(1)), cargados, [], [])).toBe(
      MENSAJE_STOCK_JORNADA_NO_CALCULABLE
    );
  });

  it("merma resta del disponible", () => {
    const movimientos = [merma(leche(1))];
    expect(validar_stock_venta(nueva(leche(2)), cargados, [], movimientos)).toBeNull();
    expect(validar_stock_venta(nueva(leche(3)), cargados, [], movimientos)).toBe(
      "Stock insuficiente de Leche."
    );
  });

  it("cambio: el entregado resta y el devuelto no suma", () => {
    const movimientos = [cambio(leche(1), leche(1))];
    expect(validar_stock_venta(nueva(leche(2)), cargados, [], movimientos)).toBeNull();
    expect(validar_stock_venta(nueva(leche(3)), cargados, [], movimientos)).toBe(
      "Stock insuficiente de Leche."
    );
  });

  it("devolución no resta del disponible", () => {
    expect(
      validar_stock_venta(nueva(leche(3)), cargados, [], [devolucion(leche(2))])
    ).toBeNull();
  });

  it("ventas y movimientos de otra jornada no afectan el stock", () => {
    const ventas = [previa("j2", leche(3))];
    const movimientos: MovimientoReparto[] = [{ ...merma(leche(3)), jornadaId: "j2" }];
    expect(
      validar_stock_venta(nueva(leche(3)), cargados, ventas, movimientos)
    ).toBeNull();
  });
});
