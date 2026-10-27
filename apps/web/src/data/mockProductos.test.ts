// Pruebas del modelo demo de productos por forma de venta (BLUEPRINT.md §7.1,
// ADR-005): `unidad` en unidades enteras con precio unitario y `peso` en
// gramos enteros con precio por kg.
//
// Los gramos de los fiambres demo son fixtures NUEVOS elegidos para el modelo
// por peso (ADR-005 D-R4): no son conversiones de los fixtures anteriores en
// medias piezas.
import { describe, expect, it } from "vitest";
import { productosIniciales } from "./mockProductos";
import { precio_valido } from "../domain/precios";
import { validar_combinacion_categoria_unidad } from "../domain/productos";

function porNombre(nombre: string) {
  const producto = productosIniciales.find((p) => p.nombre === nombre);
  if (!producto) throw new Error(`Fixture inexistente: ${nombre}`);
  return producto;
}

describe("UnidadMedida vigente: unidad | peso", () => {
  it("los productos demo sólo usan 'unidad' o 'peso'", () => {
    const unidades = new Set<string>(productosIniciales.map((p) => p.unidadMedida));
    expect([...unidades].sort()).toEqual(["peso", "unidad"]);
  });

  it("ningún producto demo usa 'pieza', 'media_pieza' ni 'kg'", () => {
    const unidades = new Set<string>(productosIniciales.map((p) => p.unidadMedida));
    for (const legacy of ["pieza", "media_pieza", "kg"]) {
      expect(unidades.has(legacy)).toBe(false);
    }
  });
});

describe("Consistencia categoría ↔ forma de venta (productos demo)", () => {
  it("todos los Lácteos usan 'unidad'", () => {
    const lacteos = productosIniciales.filter((p) => p.categoria === "Lácteos");
    expect(lacteos.length).toBeGreaterThan(0);
    lacteos.forEach((p) => expect(p.unidadMedida).toBe("unidad"));
  });

  it("todos los Fiambres usan 'peso'", () => {
    const fiambres = productosIniciales.filter((p) => p.categoria === "Fiambres");
    expect(fiambres.length).toBeGreaterThan(0);
    fiambres.forEach((p) => expect(p.unidadMedida).toBe("peso"));
  });

  it("cada producto demo pasa la validación de combinación", () => {
    productosIniciales.forEach((p) => {
      expect(
        validar_combinacion_categoria_unidad(p.categoria, p.unidadMedida).valido
      ).toBe(true);
    });
  });
});

describe("Cantidades canónicas enteras >= 0", () => {
  it("todos los stocks son enteros seguros >= 0", () => {
    productosIniciales.forEach((p) => {
      expect(Number.isSafeInteger(p.stock)).toBe(true);
      expect(p.stock).toBeGreaterThanOrEqual(0);
    });
  });

  it("todos los stockMinimo son enteros seguros >= 0", () => {
    productosIniciales.forEach((p) => {
      expect(Number.isSafeInteger(p.stockMinimo)).toBe(true);
      expect(p.stockMinimo).toBeGreaterThanOrEqual(0);
    });
  });
});

describe("Fiambres por peso en gramos (fixtures nuevos, ADR-005 D-R4)", () => {
  it("stock y stockMinimo de cada fiambre en gramos enteros", () => {
    expect(porNombre("Queso cremoso fraccionado")).toMatchObject({
      id: 3, categoria: "Fiambres", unidadMedida: "peso", stock: 7680, stockMinimo: 2000,
    });
    expect(porNombre("Jamón cocido")).toMatchObject({
      id: 4, categoria: "Fiambres", unidadMedida: "peso", stock: 18000, stockMinimo: 5000,
    });
    expect(porNombre("Salame milán")).toMatchObject({
      id: 5, categoria: "Fiambres", unidadMedida: "peso", stock: 2500, stockMinimo: 3000,
    });
  });

  it("ningún producto demo conserva un nombre de pieza", () => {
    expect(productosIniciales.some((p) => /pieza/i.test(p.nombre))).toBe(false);
  });

  it("Salame milán queda bajo mínimo a propósito", () => {
    const salame = porNombre("Salame milán");
    expect(salame.stock).toBeLessThan(salame.stockMinimo);
  });

  it("Queso cremoso en bote sigue siendo Lácteos/unidad", () => {
    expect(porNombre("Queso cremoso en bote")).toMatchObject({
      categoria: "Lácteos", unidadMedida: "unidad",
    });
  });
});

describe("Precios de los productos demo", () => {
  it("todos los precios son válidos (>= 0, máximo 2 decimales)", () => {
    productosIniciales.forEach((p) => expect(precio_valido(p.precio)).toBe(true));
  });

  it("unidad: precio unitario", () => {
    expect(porNombre("Yogur bebible 1 L").precio).toBe(2300);
    expect(porNombre("Queso cremoso en bote").precio).toBe(8500);
    expect(porNombre("Leche entera 1 L").precio).toBe(1600);
  });

  it("peso: precio por kg", () => {
    expect(porNombre("Queso cremoso fraccionado").precio).toBe(11200);
    expect(porNombre("Jamón cocido").precio).toBe(12500);
    expect(porNombre("Salame milán").precio).toBe(9800);
  });
});
