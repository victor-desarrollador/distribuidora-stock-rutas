// Pruebas del dominio de movimientos de reparto en B1 (ADR-005).
//
// Estado B1:
//   - `unidad` funciona igual que antes (entrada, stock, merma, cambio,
//     devolución y acumulación segura).
//   - El storage v5 acepta estructuralmente `peso` con gramos enteros, pero
//     la entrada de UI y la frontera de escritura lo rechazan hasta B2.
//   - `pieza` se rechaza. No hay entrada en kg.
import { describe, expect, it, vi } from "vitest";

import type {
  MovimientoReparto,
  ProductoMovimiento,
} from "../data/mockMovimientos";
import {
  cantidad_movimiento_desde_entrada,
  disponibilidad_de_jornada,
  disponibles_de_jornada,
  movimiento_valido,
  salidas_de_jornada,
  validar_stock_movimiento,
} from "./movimientos";
import { MENSAJE_PESO_NO_OPERABLE } from "./productos";
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

// Ítem `peso` estructural (gramos enteros); en B1 no es operable.
const jamon = (gramos: number): ProductoMovimiento => ({
  productoId: 4,
  nombreProducto: "Jamón cocido",
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

  it.each(["1", "1250", "1,250", "0,5"])(
    "peso devuelve null en B1 (sin entrada en kg) para %j",
    (texto) => {
      expect(cantidad_movimiento_desde_entrada("peso", { texto })).toBeNull();
    }
  );

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

  it("peso con gramos enteros es estructuralmente válido", () => {
    expect(movimiento_valido(merma(jamon(1250)))).toBe(true);
    expect(movimiento_valido(devolucion(jamon(9)))).toBe(true);
    expect(movimiento_valido(cambio(jamon(1250), yogur(2)))).toBe(true);
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
    const cargados = [{ productoId: 1, cantidad: 5 }];

    expect(validar_stock_movimiento(m, cargados, [], [])).toBeNull();

    const salidas = salidas_de_jornada("j1", [], [m]);
    expect(salidas[1]).toBe(1);
    expect(disponibles_de_jornada(cargados, salidas)[1]).toBe(4);
  });

  it("rechaza stock insuficiente con enteros exactos", () => {
    const cargados = [{ productoId: 1, cantidad: 5 }];
    expect(
      validar_stock_movimiento(merma(yogur(6)), cargados, [], [])
    ).toMatch(/Stock insuficiente/);
    expect(
      validar_stock_movimiento(merma(yogur(5)), cargados, [], [])
    ).toBeNull();
  });

  it("descuenta ventas y movimientos previos de la misma jornada", () => {
    const cargados = [{ productoId: 1, cantidad: 5 }];
    const ventas = [{ jornadaId: "j1", items: [{ productoId: 1, cantidad: 2 }] }];
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
      validar_stock_movimiento(m, [{ productoId: 1, cantidad: 1 }], [], [])
    ).toMatch(/Stock insuficiente/);
  });
});

describe("devolución (unidad)", () => {
  it("no descuenta ni reincorpora stock", () => {
    const m = devolucion(yogur(1));
    expect(movimiento_valido(m)).toBe(true);

    const cargados = [{ productoId: 1, cantidad: 5 }];
    const salidas = salidas_de_jornada("j1", [], [m]);
    expect(salidas).toEqual({});
    expect(disponibles_de_jornada(cargados, salidas)[1]).toBe(5);
  });
});

describe("registrarMovimientoOperacion: guard de peso en B1 (B2)", () => {
  function registrar(movimiento: MovimientoReparto) {
    const cargar = vi.fn(() => ({
      ok: true as const,
      movimientos: [] as MovimientoReparto[],
      estado: "valido" as const,
    }));
    const guardar = vi.fn();
    const validar = vi.fn().mockReturnValue(null);
    const error = registrarMovimientoOperacion(movimiento, validar, cargar, guardar);
    return { error, cargar, guardar, validar };
  }

  it.each([
    ["merma", merma(jamon(1250))],
    ["devolución", devolucion(jamon(1250))],
    ["cambio con peso devuelto", cambio(jamon(1250), yogur(1))],
    ["cambio con peso entregado", cambio(yogur(1), jamon(1250))],
  ])("%s peso se rechaza sin leer, validar ni persistir", (_nombre, movimiento) => {
    const { error, cargar, guardar, validar } = registrar(movimiento);

    expect(error).toBe(MENSAJE_PESO_NO_OPERABLE);
    expect(cargar).not.toHaveBeenCalled();
    expect(validar).not.toHaveBeenCalled();
    expect(guardar).not.toHaveBeenCalled();
  });

  it("un movimiento unidad válido se persiste", () => {
    const m = merma(yogur(1));
    const { error, guardar } = registrar(m);

    expect(error).toBeNull();
    expect(guardar).toHaveBeenCalledWith([m]);
  });
});

const MAX = Number.MAX_SAFE_INTEGER;

describe("M-1: acumulación segura en la ruta real de disponibilidad", () => {
  const venta = (cantidad: number, jornadaId = "j1") => ({
    jornadaId,
    items: [{ productoId: 1, cantidad }],
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
    const cargados = [{ productoId: 1, cantidad: MAX }];
    const error = validar_stock_movimiento(
      merma(yogur(1)),
      cargados,
      [venta(MAX), venta(1)],
      []
    );
    expect(error).toMatch(/No se puede calcular/);
  });

  it("con acumulado seguro en el límite exacto: disponible 0 y rechaza otra salida", () => {
    const cargados = [{ productoId: 1, cantidad: MAX }];
    expect(
      validar_stock_movimiento(merma(yogur(1)), cargados, [venta(MAX)], [])
    ).toMatch(/Stock insuficiente/);
    expect(
      validar_stock_movimiento(merma(yogur(1)), cargados, [venta(MAX - 1)], [])
    ).toBeNull();
  });
});
