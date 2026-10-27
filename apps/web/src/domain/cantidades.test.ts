// Tests del dominio puro de cantidades. Escriben el contrato ANTES de la
// implementación (TDD).
//
// Fuente: BLUEPRINT.md §7.1 y §7.4 (cantidades enteras en la unidad mínima:
// unidades o gramos, ADR-005; nunca decimales, nunca negativos).
//
// Regla vigente: una cantidad almacenable es un ENTERO SEGURO
// (Number.isSafeInteger), >= 0 y finito; nunca NaN ni Infinity.
//
// Nota: los identificadores van en snake_case por instrucción explícita de
// esta tarea; el resto del frontend usa camelCase.

import { describe, expect, it } from "vitest";
import {
  MEDIAS_POR_PIEZA,
  descomponer_medias,
  es_cantidad_valida,
  es_suma_segura,
  medias_a_piezas,
  piezas_a_medias,
  sumar_cantidades_seguras,
  validar_cantidad,
} from "./cantidades";

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

describe("M-1: enteros seguros y desbordamiento (Number.isSafeInteger)", () => {
  it("acepta Number.MAX_SAFE_INTEGER como cantidad válida", () => {
    expect(es_cantidad_valida(Number.MAX_SAFE_INTEGER)).toBe(true);
  });

  it("rechaza Number.MAX_SAFE_INTEGER + 1 (fuera de rango seguro)", () => {
    expect(es_cantidad_valida(Number.MAX_SAFE_INTEGER + 1)).toBe(false);
  });

  it("rechaza Number.MAX_SAFE_INTEGER + 2", () => {
    expect(es_cantidad_valida(Number.MAX_SAFE_INTEGER + 2)).toBe(false);
  });

  it("rechaza Number.MAX_SAFE_INTEGER * 2", () => {
    expect(es_cantidad_valida(Number.MAX_SAFE_INTEGER * 2)).toBe(false);
  });

  it("rechaza números grandes fuera de rango aunque sean enteros", () => {
    expect(es_cantidad_valida(1e20)).toBe(false);
    expect(es_cantidad_valida(Number.MAX_SAFE_INTEGER + 2)).toBe(false); // MAX_SAFE_INTEGER + 2
  });

  describe("es_suma_segura y sumar_cantidades_seguras", () => {
    it("acepta suma dentro del rango seguro", () => {
      expect(es_suma_segura(100, 200)).toBe(true);
      expect(sumar_cantidades_seguras(100, 200)).toBe(300);
    });

    it("acepta suma exacta al límite seguro", () => {
      const a = Number.MAX_SAFE_INTEGER - 100;
      const b = 100;
      expect(es_suma_segura(a, b)).toBe(true);
      expect(sumar_cantidades_seguras(a, b)).toBe(Number.MAX_SAFE_INTEGER);
    });

    it("rechaza suma que excede MAX_SAFE_INTEGER", () => {
      const a = Number.MAX_SAFE_INTEGER - 50;
      const b = 100;
      expect(es_suma_segura(a, b)).toBe(false);
      expect(() => sumar_cantidades_seguras(a, b)).toThrow(
        /Desbordamiento de cantidad canónica/
      );
    });

    it("rechaza suma de dos valores grandes", () => {
      expect(es_suma_segura(Number.MAX_SAFE_INTEGER, 1)).toBe(false);
      expect(es_suma_segura(Number.MAX_SAFE_INTEGER, Number.MAX_SAFE_INTEGER)).toBe(false);
    });

    it("rechaza si algún operando no es cantidad válida", () => {
      expect(es_suma_segura(-1, 100)).toBe(false);
      expect(es_suma_segura(1.5, 100)).toBe(false);
      expect(es_suma_segura(NaN, 100)).toBe(false);
    });
  });

  describe("validar_cantidad con enteros seguros", () => {
    it("acepta MAX_SAFE_INTEGER", () => {
      expect(() => validar_cantidad(Number.MAX_SAFE_INTEGER)).not.toThrow();
    });

    it("rechaza MAX_SAFE_INTEGER + 1", () => {
      expect(() => validar_cantidad(Number.MAX_SAFE_INTEGER + 1)).toThrow(
        /Cantidad inválida/
      );
    });
  });
});

// NO representa la regla vigente de cantidades (BLUEPRINT.md §7.1, ADR-005:
// la pieza y la media pieza no existen). Cubre APIs legacy de ADR-003 que
// todavía existen: MEDIAS_POR_PIEZA y descomponer_medias los usa
// domain/precios.ts (se revisa en B3); piezas_a_medias y medias_a_piezas no
// tienen consumidores productivos (limpieza final, B5).
describe("legacy ADR-003 — deuda de precios/B5", () => {
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
    expect(es_cantidad_valida(medias_a_piezas(9))).toBe(false);
    expect(es_cantidad_valida(9)).toBe(true);
  });

  it("la conversión de ida y vuelta preserva la cantidad exacta", () => {
    expect(medias_a_piezas(piezas_a_medias(3))).toBe(3);
    expect(piezas_a_medias(medias_a_piezas(6))).toBe(6);
  });

  it("convierte piezas enteras a medias piezas", () => {
    expect(piezas_a_medias(0)).toBe(0);
    expect(piezas_a_medias(1)).toBe(2);
    expect(piezas_a_medias(4)).toBe(8);
  });

  it("admite medias piezas exactas (múltiplos de 0.5)", () => {
    expect(piezas_a_medias(0)).toBe(0);
    expect(piezas_a_medias(0.5)).toBe(1);
    expect(piezas_a_medias(1)).toBe(2);
    expect(piezas_a_medias(1.5)).toBe(3);
    expect(piezas_a_medias(4.5)).toBe(9);
  });

  it("la conversión de piezas siempre termina en un entero válido en medias piezas", () => {
    expect(es_cantidad_valida(piezas_a_medias(7))).toBe(true);
    expect(piezas_a_medias(7)).toBe(14);
    expect(Number.isInteger(piezas_a_medias(7))).toBe(true);
  });

  it("rechaza piezas negativas, no múltiplos de 0.5 y no finitas", () => {
    expect(() => piezas_a_medias(-1)).toThrow(Error);
    expect(() => piezas_a_medias(-0.5)).toThrow(Error);
    expect(() => piezas_a_medias(0.25)).toThrow(Error);
    expect(() => piezas_a_medias(0.75)).toThrow(Error);
    expect(() => piezas_a_medias(1.25)).toThrow(Error);
    expect(() => piezas_a_medias(Number.NaN)).toThrow(Error);
    expect(() => piezas_a_medias(Number.POSITIVE_INFINITY)).toThrow(Error);
    expect(() => piezas_a_medias(Number.NEGATIVE_INFINITY)).toThrow(Error);
  });

  it("rechaza valores inválidos al convertir medias piezas a piezas", () => {
    expect(() => medias_a_piezas(-1)).toThrow(Error);
    expect(() => medias_a_piezas(1.5)).toThrow(Error);
    expect(() => medias_a_piezas(Number.NaN)).toThrow(Error);
    expect(() => medias_a_piezas(Number.NEGATIVE_INFINITY)).toThrow(Error);
  });

  it("descomponer_medias separa en piezas enteras + media", () => {
    expect(descomponer_medias(0)).toEqual({ piezas: 0, media: false });
    expect(descomponer_medias(1)).toEqual({ piezas: 0, media: true });
    expect(descomponer_medias(2)).toEqual({ piezas: 1, media: false });
    expect(descomponer_medias(3)).toEqual({ piezas: 1, media: true });
    expect(descomponer_medias(4)).toEqual({ piezas: 2, media: false });
    expect(descomponer_medias(9)).toEqual({ piezas: 4, media: true });
  });

  it("descomponer_medias rechaza valores no válidos", () => {
    expect(() => descomponer_medias(-1)).toThrow(Error);
    expect(() => descomponer_medias(1.5)).toThrow(Error);
    expect(() => descomponer_medias(Number.NaN)).toThrow(Error);
  });

  it("piezas_a_medias convierte MAX_SAFE_INTEGER / 2 piezas sin desbordamiento", () => {
    const piezas = Math.floor(Number.MAX_SAFE_INTEGER / 2);
    const resultado = piezas_a_medias(piezas);
    expect(resultado).toBe(piezas * 2);
    expect(es_cantidad_valida(resultado)).toBe(true);
  });

  it("piezas_a_medias rechaza conversión que desbordaría MAX_SAFE_INTEGER", () => {
    const piezas = Math.floor(Number.MAX_SAFE_INTEGER / 2) + 1;
    expect(() => piezas_a_medias(piezas)).toThrow(
      /Desbordamiento al convertir piezas a medias/
    );
  });
});
