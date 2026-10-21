import { describe, expect, it } from "vitest";
import {
  centavos_a_pesos,
  precio_a_centavos,
  precios_producto_validos,
  subtotal_linea,
  subtotal_linea_centavos,
  sumar_importes,
  validar_precios_producto,
} from "./precios";

const fiambre = { unidad_medida: "pieza", precio: 10000, precio_media_pieza: 6000 } as const;

describe("subtotal de pieza (ADR-002)", () => {
  it.each([
    [0, 0],
    [1, 6000],
    [2, 10000],
    [3, 16000],
    [4, 20000],
    [5, 26000],
    [8, 40000],
    [9, 46000],
  ])("c=%i → %i", (cantidad, esperado) => {
    expect(subtotal_linea({ ...fiambre, cantidad })).toBe(esperado);
  });

  it("c=2 vale una pieza, no dos medias", () => {
    expect(subtotal_linea({ ...fiambre, cantidad: 2 })).not.toBe(2 * 6000);
  });

  it("los precios son independientes: media mayor que pieza o igual a la mitad", () => {
    expect(
      subtotal_linea({ unidad_medida: "pieza", precio: 100, precio_media_pieza: 150, cantidad: 1 })
    ).toBe(150);
    expect(
      subtotal_linea({ unidad_medida: "pieza", precio: 100, precio_media_pieza: 50, cantidad: 3 })
    ).toBe(150);
  });
});

describe("subtotal de unidad", () => {
  const base = { unidad_medida: "unidad", precio: 2300 } as const;
  it.each([
    [0, 0],
    [1, 2300],
    [10, 23000],
  ])("cantidad %i → %i", (cantidad, esperado) => {
    expect(subtotal_linea({ ...base, cantidad })).toBe(esperado);
  });
});

describe("centavos exactos", () => {
  it("hasta 2 decimales, sin error binario", () => {
    expect(precio_a_centavos(0.01)).toBe(1);
    expect(precio_a_centavos(0.1)).toBe(10);
    expect(precio_a_centavos(0.2)).toBe(20);
    expect(precio_a_centavos(0.29)).toBe(29);
    expect(precio_a_centavos(1.01)).toBe(101);
    expect(precio_a_centavos(1234.56)).toBe(123456);
    expect(subtotal_linea({ unidad_medida: "unidad", precio: 0.1, cantidad: 3 })).toBe(0.3);
    expect(
      subtotal_linea_centavos({ unidad_medida: "pieza", precio: 10.1, precio_media_pieza: 5.05, cantidad: 3 })
    ).toBe(1515);
    expect(sumar_importes([0.1, 0.2])).toBe(0.3);
    expect(centavos_a_pesos(123456)).toBe(1234.56);
  });
});

describe("fail closed", () => {
  it("rechaza más de 2 decimales sin redondear ni truncar", () => {
    expect(() => precio_a_centavos(10.001)).toThrow(Error);
    expect(() => precio_a_centavos(1.005)).toThrow(Error);
    expect(() => precio_a_centavos(0.001)).toThrow(Error);
    expect(() =>
      subtotal_linea({ unidad_medida: "unidad", precio: 10.5, cantidad: 1.5 })
    ).toThrow(Error);
    expect(() =>
      subtotal_linea({ unidad_medida: "pieza", precio: 10, precio_media_pieza: 5.555, cantidad: 1 })
    ).toThrow(Error);
  });

  it("rechaza precios negativos, NaN e Infinity", () => {
    for (const precio of [-1, Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
      expect(() => precio_a_centavos(precio)).toThrow(Error);
    }
  });

  it("acepta precio 0 (validación mínima vigente)", () => {
    expect(precio_a_centavos(0)).toBe(0);
  });

  it("rechaza cantidades no canónicas", () => {
    for (const cantidad of [-1, 0.5, 1.5, Number.NaN, Number.POSITIVE_INFINITY]) {
      expect(() => subtotal_linea({ ...fiambre, cantidad })).toThrow(Error);
      expect(() =>
        subtotal_linea({ unidad_medida: "unidad", precio: 100, cantidad })
      ).toThrow(Error);
    }
  });

  it("pieza sin precio de media pieza y unidad con precio de media pieza", () => {
    expect(() =>
      subtotal_linea({ unidad_medida: "pieza", precio: 100, cantidad: 1 })
    ).toThrow(Error);
    expect(() =>
      subtotal_linea({ unidad_medida: "unidad", precio: 100, precio_media_pieza: 50, cantidad: 1 })
    ).toThrow(Error);
    expect(precios_producto_validos({ unidad_medida: "pieza", precio: 100 })).toBe(false);
    expect(precios_producto_validos({ unidad_medida: "unidad", precio: 100, precio_media_pieza: 50 })).toBe(false);
    expect(precios_producto_validos({ unidad_medida: "pieza", precio: 100, precio_media_pieza: 50 })).toBe(true);
    expect(precios_producto_validos({ unidad_medida: "unidad", precio: 100 })).toBe(true);
    expect(() => validar_precios_producto({ unidad_medida: "pieza", precio: 100, precio_media_pieza: -1 })).toThrow(Error);
  });

  it("rechaza resultados fuera del entero seguro", () => {
    expect(() =>
      subtotal_linea({ unidad_medida: "unidad", precio: 1e12, cantidad: 1e12 })
    ).toThrow(Error);
    expect(() => sumar_importes([0.1, -0.1])).toThrow(Error);
  });
});
