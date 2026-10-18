// Tests del dominio puro de cantidades. Escriben el contrato ANTES de la
// implementación (TDD).
//
// Fuente: BLUEPRINT.md §7.1 (unidades pieza / media pieza) y §7.4 (cantidades
// enteras, nunca decimales, nunca negativos).
//
// Reglas:
//   1. Cantidad almacenable: entero, >= 0, finito; nunca NaN ni Infinity.
//   2. 1 pieza = 2 medias piezas; 1/2 pieza = 1 media pieza. La representación
//      persistible siempre es un entero en medias piezas.
//
// Nota: los identificadores van en snake_case por instrucción explícita de
// esta tarea; el resto del frontend usa camelCase.

import { describe, expect, it } from "vitest";
import {
  MEDIAS_POR_PIEZA,
  es_cantidad_valida,
  medias_a_piezas,
  piezas_a_medias,
  validar_cantidad,
} from "./cantidades";

describe("conversión pieza / media pieza (§7.1)", () => {
  it("una pieza equivale a dos medias piezas", () => {
    expect(MEDIAS_POR_PIEZA).toBe(2);
    expect(piezas_a_medias(1)).toBe(2);
  });

  it("convierte medias piezas a piezas de forma exacta, sin truncar", () => {
    expect(medias_a_piezas(MEDIAS_POR_PIEZA)).toBe(1);
    expect(medias_a_piezas(1)).toBe(0.5);
    expect(medias_a_piezas(5)).toBe(2.5);
    expect(medias_a_piezas(8)).toBe(4);
    expect(medias_a_piezas(9)).toBe(4.5);
  });

  it("el resultado fraccionario no es una cantidad almacenable", () => {
    // medias_a_piezas es solo una conversión de representación: el stock
    // canónico sigue siendo el entero en medias piezas (9), no 4.5 piezas.
    expect(es_cantidad_valida(medias_a_piezas(9))).toBe(false);
    expect(es_cantidad_valida(9)).toBe(true);
  });

  it("la conversión de ida y vuelta preserva la cantidad exacta", () => {
    expect(medias_a_piezas(piezas_a_medias(3))).toBe(3);
    expect(piezas_a_medias(medias_a_piezas(6))).toBe(6);
  });

  it("convierte cantidades enteras de piezas a medias piezas", () => {
    expect(piezas_a_medias(0)).toBe(0);
    expect(piezas_a_medias(4)).toBe(8);
  });

  it("la conversión de piezas siempre termina en un entero válido en medias piezas", () => {
    expect(es_cantidad_valida(piezas_a_medias(7))).toBe(true);
    expect(piezas_a_medias(7)).toBe(14);
    expect(Number.isInteger(piezas_a_medias(7))).toBe(true);
  });

  it("compone la carga '2 piezas + 1 media' como 5 medias (§12)", () => {
    expect(piezas_a_medias(2) + 1).toBe(5);
  });

  it("rechaza valores inválidos al convertir", () => {
    expect(() => piezas_a_medias(-1)).toThrow(Error);
    expect(() => piezas_a_medias(1.5)).toThrow(Error);
    expect(() => piezas_a_medias(Number.NaN)).toThrow(Error);
    expect(() => piezas_a_medias(Number.POSITIVE_INFINITY)).toThrow(Error);
    expect(() => medias_a_piezas(-1)).toThrow(Error);
    expect(() => medias_a_piezas(1.5)).toThrow(Error);
    expect(() => medias_a_piezas(Number.NaN)).toThrow(Error);
    expect(() => medias_a_piezas(Number.NEGATIVE_INFINITY)).toThrow(Error);
  });
});

describe("validación de cantidades (§7.4)", () => {
  it("acepta enteros no negativos, incluido el cero", () => {
    expect(es_cantidad_valida(0)).toBe(true);
    expect(es_cantidad_valida(1)).toBe(true);
    expect(es_cantidad_valida(25)).toBe(true);
  });

  it("rechaza negativos", () => {
    expect(es_cantidad_valida(-1)).toBe(false);
    expect(es_cantidad_valida(-0.5)).toBe(false);
  });

  it("rechaza decimales", () => {
    expect(es_cantidad_valida(0.5)).toBe(false);
    expect(es_cantidad_valida(1.5)).toBe(false);
  });

  it("rechaza NaN", () => {
    expect(es_cantidad_valida(Number.NaN)).toBe(false);
  });

  it("rechaza Infinity", () => {
    expect(es_cantidad_valida(Number.POSITIVE_INFINITY)).toBe(false);
    expect(es_cantidad_valida(Number.NEGATIVE_INFINITY)).toBe(false);
  });

  it("validar_cantidad no lanza con una cantidad válida", () => {
    expect(() => validar_cantidad(0)).not.toThrow();
    expect(() => validar_cantidad(3)).not.toThrow();
  });

  it("validar_cantidad rechaza negativos", () => {
    expect(() => validar_cantidad(-1)).toThrow(Error);
  });

  it("validar_cantidad rechaza decimales", () => {
    expect(() => validar_cantidad(2.5)).toThrow(Error);
  });

  it("validar_cantidad rechaza NaN", () => {
    expect(() => validar_cantidad(Number.NaN)).toThrow(Error);
  });

  it("validar_cantidad rechaza Infinity", () => {
    expect(() => validar_cantidad(Number.POSITIVE_INFINITY)).toThrow(Error);
  });
});
