// Tests del dominio puro de rendición. Escriben el contrato ANTES de la
// implementación (TDD).
//
// Fuente: BLUEPRINT.md §7.4 (movimientos que entran y salen del camión) y §12
// (casos sin diferencia, con faltante y con sobrante).
//
// Reglas:
//   esperado   = cargado - vendido - merma - otras_salidas
//   diferencia = contado - esperado
//   diferencia = 0 → sin diferencia; < 0 → faltante; > 0 → sobrante
//
// Si los descuentos superan lo cargado, no se devuelve un esperado negativo en
// silencio: es una inconsistencia que debe regularizarse de forma trazable
// (§7.4).
//
// Solo lógica de dominio pura de mercadería: no toca Supabase, RPC, RLS, auth,
// persistencia ni dinero, y no mueve stock.
//
// Nota: los identificadores van en snake_case por instrucción explícita de
// esta tarea; el resto del frontend usa camelCase.

import { describe, expect, it } from "vitest";
import type { EntradaEsperado } from "./rendicion";
import { calcular_diferencia, calcular_esperado } from "./rendicion";

const base: EntradaEsperado = {
  cargado: 10,
  vendido: 1,
  merma: 1,
  otras_salidas: 1,
};

describe("calcular_esperado", () => {
  it("descuenta del cargado las ventas, la merma y las otras salidas", () => {
    expect(
      calcular_esperado({ cargado: 10, vendido: 6, merma: 1, otras_salidas: 3 })
    ).toBe(0);
  });

  it("sin movimientos el esperado es la carga completa", () => {
    expect(
      calcular_esperado({ cargado: 5, vendido: 0, merma: 0, otras_salidas: 0 })
    ).toBe(5);
  });

  it("descuenta las otras salidas del camión (§7.4)", () => {
    expect(
      calcular_esperado({ cargado: 5, vendido: 0, merma: 0, otras_salidas: 2 })
    ).toBe(3);
  });

  it("un camión que vendió todo lo cargado espera cero", () => {
    expect(
      calcular_esperado({ cargado: 4, vendido: 4, merma: 0, otras_salidas: 0 })
    ).toBe(0);
  });

  it("rechaza cantidades negativas en cualquier componente", () => {
    expect(() => calcular_esperado({ ...base, cargado: -1 })).toThrow(Error);
    expect(() => calcular_esperado({ ...base, vendido: -1 })).toThrow(Error);
    expect(() => calcular_esperado({ ...base, merma: -1 })).toThrow(Error);
    expect(() => calcular_esperado({ ...base, otras_salidas: -1 })).toThrow(
      Error
    );
  });

  it("rechaza cantidades decimales en cualquier componente", () => {
    expect(() => calcular_esperado({ ...base, cargado: 1.5 })).toThrow(Error);
    expect(() => calcular_esperado({ ...base, vendido: 0.5 })).toThrow(Error);
    expect(() => calcular_esperado({ ...base, merma: 2.5 })).toThrow(Error);
    expect(() => calcular_esperado({ ...base, otras_salidas: 0.5 })).toThrow(
      Error
    );
  });

  it("rechaza NaN e Infinity en cualquier componente", () => {
    expect(() => calcular_esperado({ ...base, cargado: Number.NaN })).toThrow(
      Error
    );
    expect(() =>
      calcular_esperado({ ...base, vendido: Number.POSITIVE_INFINITY })
    ).toThrow(Error);
    expect(() => calcular_esperado({ ...base, merma: Number.NaN })).toThrow(
      Error
    );
    expect(() =>
      calcular_esperado({ ...base, otras_salidas: Number.NEGATIVE_INFINITY })
    ).toThrow(Error);
  });

  it("no devuelve un esperado negativo si las salidas superan lo cargado (§7.4)", () => {
    expect(() =>
      calcular_esperado({ cargado: 3, vendido: 4, merma: 0, otras_salidas: 0 })
    ).toThrow(Error);
    expect(() =>
      calcular_esperado({ cargado: 5, vendido: 3, merma: 2, otras_salidas: 1 })
    ).toThrow(Error);
  });
});

describe("calcular_diferencia", () => {
  it("sin faltante ni sobrante la diferencia es cero", () => {
    expect(calcular_diferencia(3, 3)).toBe(0);
  });

  it("el resultado puede ser negativo porque representa un faltante", () => {
    expect(calcular_diferencia(2, 3)).toBe(-1);
  });

  it("un resultado positivo representa un sobrante", () => {
    expect(calcular_diferencia(4, 3)).toBe(1);
  });

  it("valida el contado como cantidad no negativa entera", () => {
    expect(() => calcular_diferencia(-1, 3)).toThrow(Error);
    expect(() => calcular_diferencia(1.5, 3)).toThrow(Error);
    expect(() => calcular_diferencia(Number.NaN, 3)).toThrow(Error);
    expect(() => calcular_diferencia(Number.POSITIVE_INFINITY, 3)).toThrow(
      Error
    );
  });

  it("valida el esperado como cantidad no negativa entera", () => {
    expect(() => calcular_diferencia(3, -1)).toThrow(Error);
    expect(() => calcular_diferencia(3, 1.5)).toThrow(Error);
    expect(() => calcular_diferencia(3, Number.NaN)).toThrow(Error);
    expect(() => calcular_diferencia(3, Number.POSITIVE_INFINITY)).toThrow(
      Error
    );
  });
});

describe("esperado y diferencia sobre medias piezas (§12)", () => {
  it("2 piezas + 1 media cargadas y 1 media vendida esperan 4 medias", () => {
    // 2 piezas + 1 media = 5 medias cargadas; 1 media vendida deja 4 esperadas.
    const esperado = calcular_esperado({
      cargado: 5,
      vendido: 1,
      merma: 0,
      otras_salidas: 0,
    });

    expect(esperado).toBe(4);
    expect(calcular_diferencia(4, esperado)).toBe(0);
  });
});

describe("overflow y rango seguro", () => {
  const MAX = Number.MAX_SAFE_INTEGER;

  it("salidas exactas al límite seguro son válidas", () => {
    expect(
      calcular_esperado({ cargado: MAX, vendido: MAX - 2, merma: 1, otras_salidas: 1 })
    ).toBe(0);
    expect(
      calcular_esperado({ cargado: MAX, vendido: 0, merma: 0, otras_salidas: 0 })
    ).toBe(MAX);
  });

  it("vendido + merma que desbordan fallan cerrado", () => {
    expect(() =>
      calcular_esperado({ cargado: MAX, vendido: MAX, merma: 1, otras_salidas: 0 })
    ).toThrow(/Desbordamiento/);
  });

  it("las salidas combinadas que desbordan fallan cerrado (no solo por > cargado)", () => {
    expect(() =>
      calcular_esperado({ cargado: MAX, vendido: MAX - 1, merma: 1, otras_salidas: 1 })
    ).toThrow(/Desbordamiento/);
  });

  it("un componente fuera del rango seguro se rechaza", () => {
    expect(() =>
      calcular_esperado({ cargado: MAX + 1, vendido: 0, merma: 0, otras_salidas: 0 })
    ).toThrow(Error);
  });

  it("salidas > cargado sigue rechazándose", () => {
    expect(() =>
      calcular_esperado({ cargado: 5, vendido: 3, merma: 2, otras_salidas: 1 })
    ).toThrow(/superan lo cargado/);
  });

  it("diferencia positiva, negativa y cero dentro del rango seguro", () => {
    expect(calcular_diferencia(MAX, 0)).toBe(MAX);
    expect(calcular_diferencia(0, MAX)).toBe(-MAX);
    expect(calcular_diferencia(MAX, MAX)).toBe(0);
    expect(calcular_diferencia(5, 3)).toBe(2);
    expect(calcular_diferencia(3, 5)).toBe(-2);
  });

  it("entradas fuera del rango seguro se rechazan (no hay diferencia aproximada)", () => {
    expect(() => calcular_diferencia(MAX + 1, 0)).toThrow(Error);
    expect(() => calcular_diferencia(0, MAX + 1)).toThrow(Error);
  });
});
