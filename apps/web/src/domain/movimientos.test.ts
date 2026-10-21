import { describe, expect, it } from "vitest";

import type {
  MovimientoReparto,
  ProductoMovimiento,
} from "../data/mockMovimientos";
import {
  cantidad_movimiento_desde_entrada,
  disponibles_de_jornada,
  movimiento_valido,
  salidas_de_jornada,
  validar_stock_movimiento,
} from "./movimientos";
import { medias_a_texto } from "./cantidades";

const jamon = (cantidad: number): ProductoMovimiento => ({
  productoId: 1,
  nombreProducto: "Jamón cocido",
  unidadMedida: "pieza",
  cantidad,
});

const yogur = (cantidad: number): ProductoMovimiento => ({
  productoId: 2,
  nombreProducto: "Yogur",
  unidadMedida: "unidad",
  cantidad,
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

describe("cantidad_movimiento_desde_entrada", () => {
  it("pieza: piezas enteras + media se persisten como medias piezas", () => {
    expect(
      cantidad_movimiento_desde_entrada("pieza", { texto: "0", media: true })
    ).toBe(1);
    expect(
      cantidad_movimiento_desde_entrada("pieza", { texto: "1", media: false })
    ).toBe(2);
    expect(
      cantidad_movimiento_desde_entrada("pieza", { texto: "1", media: true })
    ).toBe(3);
    expect(
      cantidad_movimiento_desde_entrada("pieza", { texto: "2", media: true })
    ).toBe(5);
  });

  it("unidad: cantidad entera es válida", () => {
    expect(
      cantidad_movimiento_desde_entrada("unidad", { texto: "2", media: false })
    ).toBe(2);
  });

  it.each(["", "0", "1.5", "NaN", "Infinity", "-1", "-0.5", "abc"])(
    "rechaza %j en unidad y en pieza",
    (texto) => {
      expect(
        cantidad_movimiento_desde_entrada("unidad", { texto, media: false })
      ).toBeNull();
      expect(
        cantidad_movimiento_desde_entrada("pieza", { texto, media: false })
      ).toBeNull();
    }
  );

  it("pieza con 0 piezas sin media es inválida; con media vale 1", () => {
    expect(
      cantidad_movimiento_desde_entrada("pieza", { texto: "0", media: false })
    ).toBeNull();
  });

  it("unidad no admite media pieza", () => {
    expect(
      cantidad_movimiento_desde_entrada("unidad", { texto: "2", media: true })
    ).toBeNull();
  });

  it("kg no es una unidad válida", () => {
    expect(
      cantidad_movimiento_desde_entrada("kg" as never, {
        texto: "1",
        media: false,
      })
    ).toBeNull();
  });
});

describe("merma", () => {
  it("disponible 5 medias, merma de 1 media: salida 1, restante 4", () => {
    const m = merma(jamon(1));
    const cargados = [{ productoId: 1, cantidad: 5 }];

    expect(validar_stock_movimiento(m, cargados, [], [])).toBeNull();

    const salidas = salidas_de_jornada("j1", [], [m]);
    expect(salidas[1]).toBe(1);
    expect(disponibles_de_jornada(cargados, salidas)[1]).toBe(4);
  });

  it("cantidad 3 representa 1 pieza y media", () => {
    expect(movimiento_valido(merma(jamon(3)))).toBe(true);
    expect(medias_a_texto(3)).toBe("1 pieza y media");
  });

  it("rechaza stock insuficiente con enteros exactos", () => {
    const cargados = [{ productoId: 1, cantidad: 5 }];
    expect(
      validar_stock_movimiento(merma(jamon(6)), cargados, [], [])
    ).toMatch(/Stock insuficiente/);
    expect(
      validar_stock_movimiento(merma(jamon(5)), cargados, [], [])
    ).toBeNull();
  });

  it("descuenta ventas y movimientos previos de la misma jornada", () => {
    const cargados = [{ productoId: 1, cantidad: 5 }];
    const ventas = [{ jornadaId: "j1", items: [{ productoId: 1, cantidad: 2 }] }];
    const previo = { ...merma(jamon(2)), id: "m0" };

    expect(
      validar_stock_movimiento(merma(jamon(1)), cargados, ventas, [previo])
    ).toBeNull();
    expect(
      validar_stock_movimiento(merma(jamon(2)), cargados, ventas, [previo])
    ).toMatch(/Stock insuficiente/);
  });

  it("rechaza producto no cargado", () => {
    expect(validar_stock_movimiento(merma(yogur(1)), [], [], [])).toMatch(
      /no está cargado/
    );
  });
});

describe("unidad", () => {
  it("cantidad 2 es válida", () => {
    expect(movimiento_valido(merma(yogur(2)))).toBe(true);
  });
});

describe("cantidades inválidas en movimiento_valido", () => {
  it.each([0, 1.5, NaN, Infinity, -Infinity, -1])("rechaza %s", (c) => {
    expect(movimiento_valido(merma(yogur(c)))).toBe(false);
    expect(movimiento_valido(merma(jamon(c)))).toBe(false);
  });

  it("rechaza kg como unidad", () => {
    const kg = { ...yogur(1), unidadMedida: "kg" } as unknown;
    expect(movimiento_valido({ ...merma(yogur(1)), producto: kg })).toBe(false);
  });
});

describe("cambio", () => {
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

  it("entregado pieza c=3, recibido unidad c=2: cada uno en su representación", () => {
    const m = cambio(yogur(2), jamon(3));
    expect(movimiento_valido(m)).toBe(true);
    if (m.tipo !== "cambio") throw new Error("tipo");
    expect(medias_a_texto(m.productoEntregado.cantidad)).toBe("1 pieza y media");
    expect(m.productoDevuelto.cantidad).toBe(2);
    // Solo el entregado descuenta mercadería del camión.
    expect(salidas_de_jornada("j1", [], [m])).toEqual({ 1: 3 });
  });

  it("inverso: entregado unidad, recibido pieza se valida por separado", () => {
    const m = cambio(jamon(3), yogur(2));
    expect(movimiento_valido(m)).toBe(true);
    expect(salidas_de_jornada("j1", [], [m])).toEqual({ 2: 2 });
    expect(
      validar_stock_movimiento(m, [{ productoId: 2, cantidad: 1 }], [], [])
    ).toMatch(/Stock insuficiente/);
  });

  it("una cantidad inválida en cualquiera de los dos lados invalida el cambio", () => {
    expect(movimiento_valido(cambio(yogur(2), jamon(1.5)))).toBe(false);
    expect(movimiento_valido(cambio(yogur(0.5), jamon(3)))).toBe(false);
  });
});

describe("devolución", () => {
  it("pieza c=1 queda en 1 media canónica y no descuenta ni reincorpora stock", () => {
    const m: MovimientoReparto = {
      ...base,
      tipo: "devolucion",
      clienteId: 7,
      nombreCliente: "Almacén",
      producto: jamon(1),
    };
    expect(movimiento_valido(m)).toBe(true);
    if (m.tipo !== "devolucion") throw new Error("tipo");
    expect(m.producto.cantidad).toBe(1);
    expect(medias_a_texto(m.producto.cantidad)).toBe("media pieza");

    const cargados = [{ productoId: 1, cantidad: 5 }];
    const salidas = salidas_de_jornada("j1", [], [m]);
    expect(salidas).toEqual({});
    expect(disponibles_de_jornada(cargados, salidas)[1]).toBe(5);
  });
});
