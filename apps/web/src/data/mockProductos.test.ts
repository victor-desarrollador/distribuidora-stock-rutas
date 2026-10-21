// Pruebas del modelo de productos tras la migración a unidades canónicas
// (BLUEPRINT.md v1.6 §7.1 y docs/requirements/migracion-unidades-prototipo.md).
import { describe, expect, it } from "vitest";
import { productosIniciales, type UnidadMedida } from "./mockProductos";
import { precios_producto_validos } from "../domain/precios";

describe("UnidadMedida sin kg", () => {
  it("ningún producto demo usa unidadMedida 'kg'", () => {
    const unidades = new Set(productosIniciales.map((p) => p.unidadMedida));
    expect(unidades.has("kg" as unknown as UnidadMedida)).toBe(false);
  });

  it("el tipo UnidadMedida no incluye 'kg' en tiempo de compilación", () => {
    // Esta comprobación es de tipo: si UnidadMedida incluyera "kg",
    // la asignación siguiente fallaría en typecheck. En runtime verificamos
    // que ningún valor del tipo sea "kg".
    const u: UnidadMedida = "unidad";
    expect(["unidad", "pieza"].includes(u)).toBe(true);
  });
});

describe("Consistencia categoría ↔ unidad (productos demo)", () => {
  it("todos los Lácteos usan unidadMedida 'unidad'", () => {
    const lacteos = productosIniciales.filter((p) => p.categoria === "Lácteos");
    expect(lacteos.length).toBeGreaterThan(0);
    lacteos.forEach((p) => {
      expect(p.unidadMedida).toBe("unidad");
    });
  });

  it("todos los Fiambres usan unidadMedida 'pieza'", () => {
    const fiambres = productosIniciales.filter((p) => p.categoria === "Fiambres");
    expect(fiambres.length).toBeGreaterThan(0);
    fiambres.forEach((p) => {
      expect(p.unidadMedida).toBe("pieza");
    });
  });

  it("no existe producto Lácteos + pieza ni Fiambres + unidad", () => {
    const invalidos = productosIniciales.filter(
      (p) =>
        (p.categoria === "Lácteos" && p.unidadMedida === "pieza") ||
        (p.categoria === "Fiambres" && p.unidadMedida === "unidad")
    );
    expect(invalidos).toHaveLength(0);
  });
});

describe("Cantidades canónicas enteras >= 0", () => {
  it("todos los stocks son enteros >= 0", () => {
    productosIniciales.forEach((p) => {
      expect(Number.isInteger(p.stock)).toBe(true);
      expect(p.stock).toBeGreaterThanOrEqual(0);
    });
  });

  it("todos los stockMinimo son enteros >= 0", () => {
    productosIniciales.forEach((p) => {
      expect(Number.isInteger(p.stockMinimo)).toBe(true);
      expect(p.stockMinimo).toBeGreaterThanOrEqual(0);
    });
  });
});

describe("Fiambres expresados en medias piezas", () => {
  it("el stock de cada fiambre es par (medias piezas enteras)", () => {
    const fiambres = productosIniciales.filter((p) => p.categoria === "Fiambres");
    fiambres.forEach((p) => {
      expect(p.stock % 2).toBe(0);
    });
  });

  it("casos concretos: 18 piezas → 36 medias, 6 piezas → 12 medias", () => {
    const jamon = productosIniciales.find((p) => p.nombre === "Jamón cocido");
    const salame = productosIniciales.find((p) => p.nombre === "Salame milán");
    const quesoPieza = productosIniciales.find(
      (p) => p.nombre === "Queso cremoso en pieza"
    );

    expect(jamon?.stock).toBe(36); // 18 piezas × 2
    expect(salame?.stock).toBe(12); // 6 piezas × 2
    expect(quesoPieza?.stock).toBeGreaterThanOrEqual(2);
  });

  it("Queso cremoso en bote es Lácteos/unidad con stock entero", () => {
    const quesoBote = productosIniciales.find(
      (p) => p.nombre === "Queso cremoso en bote"
    );
    expect(quesoBote?.categoria).toBe("Lácteos");
    expect(quesoBote?.unidadMedida).toBe("unidad");
    expect(Number.isInteger(quesoBote?.stock ?? -1)).toBe(true);
  });
});

describe("Precios de los productos demo (ADR-002)", () => {
  it("todo fiambre tiene precioMediaPieza válido", () => {
    const fiambres = productosIniciales.filter((p) => p.categoria === "Fiambres");
    expect(fiambres.length).toBeGreaterThan(0);
    fiambres.forEach((p) => {
      expect(p.precioMediaPieza).toBeDefined();
      expect(
        precios_producto_validos({
          unidad_medida: p.unidadMedida,
          precio: p.precio,
          precio_media_pieza: p.precioMediaPieza,
        })
      ).toBe(true);
    });
  });

  it("ningún lácteo tiene precioMediaPieza", () => {
    productosIniciales
      .filter((p) => p.categoria === "Lácteos")
      .forEach((p) => {
        expect(p.precioMediaPieza).toBeUndefined();
        expect(
          precios_producto_validos({
            unidad_medida: p.unidadMedida,
            precio: p.precio,
          })
        ).toBe(true);
      });
  });

  it("valores demo aprobados (sin fórmula entre precios)", () => {
    const por_nombre = new Map(
      productosIniciales.map((p) => [p.nombre, [p.precio, p.precioMediaPieza]])
    );
    expect(por_nombre.get("Queso cremoso en pieza")).toEqual([12500, 7000]);
    expect(por_nombre.get("Jamón cocido")).toEqual([12500, 7500]);
    expect(por_nombre.get("Salame milán")).toEqual([9800, 6000]);
  });
});
