// Test UNITARIO de la lógica pura de preparación de la pantalla Jornadas
// (src/pages/jornadas_preparacion.ts, B2). No monta React ni usa
// localStorage: la frontera persistida se prueba en
// src/hooks/crearPreparacion.test.ts.
//
// Fuente: BLUEPRINT.md §7.1 y §12 (peso en kg con hasta 3 decimales, gramos
// enteros, sin punto flotante), ADR-005 y P-B2-1 (sin valorizar cargas con
// peso).
import { describe, expect, it, vi, beforeEach } from "vitest";

import type { ItemCarga, Jornada } from "../data/mockJornadas";
import type { Producto } from "../data/mockProductos";
import { cantidad_a_texto } from "../domain/productos";
import * as precios from "../domain/precios";
import {
  atributos_input_carga,
  disponibilidad_carga,
  entrada_carga,
  precio_item_valido,
  valor_estimado_carga,
  valor_item_unidad,
} from "./jornadas_preparacion";

// Espía sobre subtotal_linea para probar que ninguna línea `peso` se valoriza.
vi.mock("../domain/precios", async (importar) => {
  const real = await importar<typeof import("../domain/precios")>();
  return { ...real, subtotal_linea: vi.fn(real.subtotal_linea) };
});

const MAX = Number.MAX_SAFE_INTEGER;

const yogur: Producto = {
  id: 1,
  nombre: "Yogur",
  categoria: "Lácteos",
  unidadMedida: "unidad",
  stock: 120,
  precio: 2300,
  stockMinimo: 20,
};

const jamon: Producto = {
  id: 4,
  nombre: "Jamón",
  categoria: "Fiambres",
  unidadMedida: "peso",
  stock: 18000,
  precio: 12500,
  stockMinimo: 5000,
};

const itemYogur = (cantidad: number): ItemCarga => ({
  productoId: 1,
  nombreProducto: "Yogur",
  unidadMedida: "unidad",
  cantidad,
  precioReferencia: 2300,
});

const itemJamon = (gramos: number, precioReferencia = 12500): ItemCarga => ({
  productoId: 4,
  nombreProducto: "Jamón",
  unidadMedida: "peso",
  cantidad: gramos,
  precioReferencia,
});

const activa = (id: string, camionId: number, items: ItemCarga[]): Jornada => ({
  id,
  camionId,
  chofer: "Chofer",
  zona: "Centro",
  fechaCreacion: "2026-10-22T08:00:00.000Z",
  fechaSalida: null,
  estado: "preparacion",
  items,
});

describe("entrada_carga — peso en kg a gramos enteros", () => {
  it.each([
    ["1,250", 1250],
    ["28,680", 28680],
    ["1,005", 1005],
    ["0,001", 1],
    ["1", 1000],
    ["18", 18000],
  ])("%j kg → %i g (exacto, sin punto flotante)", (texto, gramos) => {
    expect(entrada_carga("peso", texto)).toEqual({ estado: "valida", cantidad: gramos });
  });

  it.each(["1.250", "1,2345", "0", "0,000", "-1", "-0,5", "abc", "1,", ",5", "NaN"])(
    "rechaza %j",
    (texto) => {
      expect(entrada_carga("peso", texto)).toEqual({ estado: "invalida" });
    }
  );

  it("vacío o sólo espacios no carga nada", () => {
    expect(entrada_carga("peso", "")).toEqual({ estado: "vacia" });
    expect(entrada_carga("peso", "   ")).toEqual({ estado: "vacia" });
  });

  it("fuera del rango seguro → inválida, sin throw", () => {
    expect(() => entrada_carga("peso", "9007199254740,992")).not.toThrow();
    expect(entrada_carga("peso", "9007199254740,992")).toEqual({ estado: "invalida" });
  });
});

describe("entrada_carga — unidad sin regresión", () => {
  it("entero positivo es válido; 0 y vacío no cargan nada", () => {
    expect(entrada_carga("unidad", "5")).toEqual({ estado: "valida", cantidad: 5 });
    expect(entrada_carga("unidad", "0")).toEqual({ estado: "vacia" });
    expect(entrada_carga("unidad", "")).toEqual({ estado: "vacia" });
  });

  it.each(["1.5", "1,5", "-1", "abc", "Infinity"])("rechaza %j", (texto) => {
    expect(entrada_carga("unidad", texto)).toEqual({ estado: "invalida" });
  });
});

describe("input de carga por unidad — regresión UX de unidad y kg para peso", () => {
  it("unidad conserva el input numérico anterior (type number, min 0, step 1, max = disponible)", () => {
    expect(atributos_input_carga("unidad", 120)).toEqual({
      type: "number",
      min: "0",
      max: 120,
      step: "1",
      disabled: false,
      sufijo: "un.",
    });
  });

  it("peso usa texto en kg con coma (sin min, max ni step numéricos)", () => {
    expect(atributos_input_carga("peso", 18000)).toEqual({
      type: "text",
      inputMode: "decimal",
      placeholder: "0,000",
      disabled: false,
      sufijo: "kg",
    });
  });

  it.each([
    ["unidad", null],
    ["unidad", -1],
    ["peso", null],
    ["peso", -250],
  ] as const)("%s con disponible %s: input deshabilitado", (unidad, disponible) => {
    expect(atributos_input_carga(unidad, disponible).disabled).toBe(true);
  });

  it("la representación canónica no cambia: el mismo texto da unidades o gramos según el producto", () => {
    expect(entrada_carga("unidad", "3")).toEqual({ estado: "valida", cantidad: 3 });
    expect(entrada_carga("peso", "3")).toEqual({ estado: "valida", cantidad: 3000 });
    // Un decimal es inválido para unidad y válido (en gramos) para peso.
    expect(entrada_carga("unidad", "1,250")).toEqual({ estado: "invalida" });
    expect(entrada_carga("peso", "1,250")).toEqual({ estado: "valida", cantidad: 1250 });
  });
});

describe("disponibilidad_carga — misma semántica que la frontera", () => {
  it("varias jornadas reservando gramos: disponible exacto", () => {
    const d = disponibilidad_carga(
      [yogur, jamon],
      [activa("a", 1, [itemJamon(10000)]), activa("b", 2, [itemJamon(5000), itemYogur(20)])],
      []
    );
    expect(d).toEqual({ ok: true, disponibles: { 1: 100, 4: 3000 } });
  });

  it("disponible negativo se informa (sin Math.max)", () => {
    const d = disponibilidad_carga([{ ...jamon, stock: 1000 }], [activa("a", 1, [itemJamon(1250)])], []);
    expect(d).toEqual({ ok: true, disponibles: { 4: -250 } });
  });

  it("reservado incalculable (overflow) → ok: false", () => {
    const d = disponibilidad_carga(
      [jamon],
      [activa("a", 1, [itemJamon(MAX)]), activa("b", 2, [itemJamon(1)])],
      []
    );
    expect(d).toEqual({ ok: false });
  });

  it("exceso por 1 g: el disponible deja de alcanzar exactamente en 1 g", () => {
    const d = disponibilidad_carga([jamon], [activa("a", 1, [itemJamon(17999)])], []);
    if (!d.ok) throw new Error("debía calcularse");
    expect(d.disponibles[4]).toBe(1);
    const pedido = entrada_carga("peso", "0,002");
    expect(pedido).toEqual({ estado: "valida", cantidad: 2 });
    if (pedido.estado === "valida") expect(pedido.cantidad > d.disponibles[4]).toBe(true);
  });
});

describe("valor estimado (P-B2-1) — ninguna línea peso se valoriza", () => {
  beforeEach(() => {
    vi.mocked(precios.subtotal_linea).mockClear();
  });

  it("sólo unidad: suma las líneas como hasta ahora", () => {
    expect(valor_estimado_carga([itemYogur(3), itemYogur(2)])).toBe(11500);
  });

  it("sólo peso: null, sin llamar a subtotal_linea", () => {
    expect(valor_estimado_carga([itemJamon(1250)])).toBeNull();
    expect(precios.subtotal_linea).not.toHaveBeenCalled();
  });

  it("mixta: null (sin subtotal parcial de las líneas unidad) y sin valorizar nada", () => {
    expect(valor_estimado_carga([itemYogur(3), itemJamon(1250)])).toBeNull();
    expect(precios.subtotal_linea).not.toHaveBeenCalled();
  });

  it("valor_item_unidad lanza con peso y nunca llama a subtotal_linea", () => {
    expect(() => valor_item_unidad(itemJamon(1250))).toThrow(/D-R1/);
    expect(precios.subtotal_linea).not.toHaveBeenCalled();
  });

  it("precio_item_valido: peso valida sólo el precio por kg, sin valorizar", () => {
    expect(precio_item_valido(itemJamon(1250))).toBe(true);
    expect(precio_item_valido(itemJamon(1250, 0.001))).toBe(false);
    expect(precios.subtotal_linea).not.toHaveBeenCalled();
    expect(precio_item_valido(itemYogur(1))).toBe(true);
    expect(precios.subtotal_linea).toHaveBeenCalledWith(
      expect.objectContaining({ unidad_medida: "unidad" })
    );
  });
});

describe("presentación: cantidades peso con 3 decimales fijos", () => {
  it.each([
    [1250, "1,250 kg"],
    [28680, "28,680 kg"],
    [1, "0,001 kg"],
    [18000, "18,000 kg"],
  ])("%i g → %j", (gramos, texto) => {
    expect(cantidad_a_texto("peso", gramos)).toBe(texto);
  });

  it("unidad se muestra en unidades enteras", () => {
    expect(cantidad_a_texto("unidad", 12)).toBe("12 un.");
  });
});
