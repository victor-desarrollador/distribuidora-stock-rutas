// Pruebas de la validación de combinación categoría ↔ forma de venta
// (BLUEPRINT.md §7.1, ADR-005) y de la presentación de cantidades canónicas.
// Vitest corre en node: pruebas puras, sin DOM ni Testing Library.
import { describe, expect, it } from "vitest";

import {
  cantidad_a_texto,
  stock_producto_valido,
  unidad_para_categoria,
  validar_combinacion_categoria_unidad,
} from "./productos";
import type { UnidadMedida } from "../data/mockProductos";

const CATEGORIAS = ["Lácteos", "Fiambres"] as const;

describe("unidad_para_categoria", () => {
  it("Lácteos devuelve 'unidad'", () => {
    expect(unidad_para_categoria("Lácteos")).toBe("unidad");
  });

  it("Fiambres devuelve 'peso'", () => {
    expect(unidad_para_categoria("Fiambres")).toBe("peso");
  });

  it("nunca devuelve 'pieza' ni 'kg'", () => {
    for (const categoria of CATEGORIAS) {
      const resultado: string = unidad_para_categoria(categoria);
      expect(resultado).not.toBe("pieza");
      expect(resultado).not.toBe("kg");
    }
  });
});

describe("validar_combinacion_categoria_unidad", () => {
  it("Lácteos + unidad es válido", () => {
    expect(validar_combinacion_categoria_unidad("Lácteos", "unidad").valido).toBe(true);
  });

  it("Fiambres + peso es válido", () => {
    expect(validar_combinacion_categoria_unidad("Fiambres", "peso").valido).toBe(true);
  });

  it("Lácteos + peso es inválido", () => {
    const resultado = validar_combinacion_categoria_unidad("Lácteos", "peso");
    expect(resultado.valido).toBe(false);
    expect(resultado.mensaje).toBeDefined();
  });

  it("Fiambres + unidad es inválido", () => {
    const resultado = validar_combinacion_categoria_unidad("Fiambres", "unidad");
    expect(resultado.valido).toBe(false);
    expect(resultado.mensaje).toBeDefined();
  });

  it.each(["pieza", "media_pieza", "kg"])(
    "'%s' es inválido para cualquier categoría",
    (unidad) => {
      for (const categoria of CATEGORIAS) {
        const resultado = validar_combinacion_categoria_unidad(
          categoria,
          unidad as unknown as UnidadMedida
        );
        expect(resultado.valido).toBe(false);
      }
    }
  );
});

describe("stock_producto_valido", () => {
  const MAX = Number.MAX_SAFE_INTEGER;

  it("acepta enteros seguros >= 0, incluido el límite", () => {
    expect(stock_producto_valido(0, 0)).toBe(true);
    expect(stock_producto_valido(MAX, MAX)).toBe(true);
  });

  it("rechaza stock o stockMinimo fuera del rango seguro", () => {
    expect(stock_producto_valido(MAX + 1, 0)).toBe(false);
    expect(stock_producto_valido(0, MAX + 1)).toBe(false);
  });

  it.each([1.5, -1, NaN, Infinity])("rechaza %s en cualquiera de los dos", (v) => {
    expect(stock_producto_valido(v, 1)).toBe(false);
    expect(stock_producto_valido(1, v)).toBe(false);
  });

  it("rechaza gramos fraccionarios (1250.5)", () => {
    expect(stock_producto_valido(1250, 0)).toBe(true);
    expect(stock_producto_valido(1250.5, 0)).toBe(false);
    expect(stock_producto_valido(0, 1250.5)).toBe(false);
  });
});

describe("cantidad_a_texto: canónico vs presentación (ADR-005)", () => {
  it("peso: gramos → kg con 3 decimales fijos", () => {
    expect(cantidad_a_texto("peso", 18000)).toBe("18,000 kg");
    expect(cantidad_a_texto("peso", 2500)).toBe("2,500 kg");
    expect(cantidad_a_texto("peso", 9)).toBe("0,009 kg");
  });

  it("peso: 18000 g nunca se muestra como '18000 kg'", () => {
    const texto = cantidad_a_texto("peso", 18000);
    expect(texto).not.toBe("18000 kg");
    expect(texto).not.toContain("18000");
  });

  it("unidad: entero con 'un.'", () => {
    expect(cantidad_a_texto("unidad", 3)).toBe("3 un.");
  });
});
