// Test UNITARIO de lógica aplicada a Jornadas.
// Prueba las funciones puras compartidas de src/domain/cantidades.ts que
// Jornadas.tsx importa y usa (no hay copias locales). NO monta React, NO usa
// localStorage y NO es un test de integración ni E2E: no verifica el cableado
// del componente.
//
// Fuente: BLUEPRINT.md §7.1 y §7.4 (cantidades enteras en la unidad mínima,
// ADR-005). La carga de productos `peso` (B2) se prueba en
// jornadas_preparacion.test.ts y en la frontera de escritura
// (crearPreparacion.test.ts).

import { describe, expect, it } from "vitest";
import { subtotal_linea, sumar_importes } from "../domain/precios";
import { cantidad_unidad_desde_texto } from "../domain/cantidades";

describe("Jornadas — producto por unidad (§7.4)", () => {
  it("acepta enteros finitos >= 0 y vacío como 0", () => {
    expect(cantidad_unidad_desde_texto("5")).toBe(5);
    expect(cantidad_unidad_desde_texto("0")).toBe(0);
    expect(cantidad_unidad_desde_texto("")).toBe(0);
    expect(cantidad_unidad_desde_texto("   ")).toBe(0);
  });

  it("0.5, negativos, NaN e Infinity son inválidos (null), sin redondear", () => {
    expect(cantidad_unidad_desde_texto("0.5")).toBeNull();
    expect(cantidad_unidad_desde_texto("1.5")).toBeNull();
    expect(cantidad_unidad_desde_texto("-1")).toBeNull();
    expect(cantidad_unidad_desde_texto("abc")).toBeNull();
    expect(cantidad_unidad_desde_texto("Infinity")).toBeNull();
    expect(cantidad_unidad_desde_texto("1e999")).toBeNull();
  });
});

describe("Jornadas — valor de carga de productos unidad", () => {
  // Comportamiento actual de subtotal_linea/sumar_importes para `unidad` (el
  // que ya usa Jornadas.tsx). No es una regla monetaria nueva ni resuelve el
  // pendiente de líneas `unidad` y documentos mixtos (BLUEPRINT.md §15).
  it("el total de la carga suma líneas unidad sin error binario", () => {
    const lacteo = subtotal_linea({ unidad_medida: "unidad", cantidad: 3, precio: 0.1 });
    expect(lacteo).toBe(0.3);
    expect(sumar_importes([lacteo, lacteo])).toBe(0.6);
  });
});
