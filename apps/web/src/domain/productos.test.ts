// Pruebas de la validación de combinación categoría ↔ unidad de medida.
// Vitest corre en node: pruebas puras, sin DOM ni Testing Library.
import { describe, expect, it } from "vitest";

import {
  unidad_para_categoria,
  validar_combinacion_categoria_unidad,
} from "./productos";
import type { UnidadMedida } from "../data/mockProductos";

describe("unidad_para_categoria", () => {
  it("Lácteos devuelve 'unidad'", () => {
    expect(unidad_para_categoria("Lácteos")).toBe("unidad");
  });

  it("Fiambres devuelve 'pieza'", () => {
    expect(unidad_para_categoria("Fiambres")).toBe("pieza");
  });

  it("nunca devuelve 'kg'", () => {
    const resultado = unidad_para_categoria("Lácteos");
    expect(["unidad", "pieza"]).toContain(resultado);
    expect(resultado).not.toBe("kg");
  });
});

describe("validar_combinacion_categoria_unidad", () => {
  it("Lácteos + unidad es válido", () => {
    const resultado = validar_combinacion_categoria_unidad(
      "Lácteos",
      "unidad"
    );
    expect(resultado.valido).toBe(true);
  });

  it("Lácteos + pieza es inválido", () => {
    const resultado = validar_combinacion_categoria_unidad(
      "Lácteos",
      "pieza"
    );
    expect(resultado.valido).toBe(false);
    expect(resultado.mensaje).toBeDefined();
  });

  it("Fiambres + pieza es válido", () => {
    const resultado = validar_combinacion_categoria_unidad(
      "Fiambres",
      "pieza"
    );
    expect(resultado.valido).toBe(true);
  });

  it("Fiambres + unidad es inválido", () => {
    const resultado = validar_combinacion_categoria_unidad(
      "Fiambres",
      "unidad"
    );
    expect(resultado.valido).toBe(false);
    expect(resultado.mensaje).toBeDefined();
  });

  it("no existe soporte para kg: ninguna categoría acepta kg", () => {
    const conKg = validar_combinacion_categoria_unidad(
      "Lácteos",
      "kg" as unknown as UnidadMedida
    );
    expect(conKg.valido).toBe(false);
    expect(conKg.mensaje).toContain("unidad");
  });
});
