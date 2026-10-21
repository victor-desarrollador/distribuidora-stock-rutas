// Test UNITARIO de lógica aplicada a Jornadas.
// Prueba las funciones puras compartidas de src/domain/cantidades.ts que
// Jornadas.tsx importa y usa (no hay copias locales). NO monta React, NO usa
// localStorage y NO es un test de integración ni E2E: no verifica el cableado
// del componente.
//
// Fuente: BLUEPRINT.md §7.1 (unidades pieza / media pieza) y §7.4 (cantidades
// enteras, nunca decimales, nunca negativos).

import { describe, expect, it } from "vitest";
import { subtotal_linea, sumar_importes } from "../domain/precios";
import {
  cantidad_unidad_desde_texto,
  descomponer_medias,
  es_cantidad_valida,
  maximo_piezas_segun_disponible,
  medias_a_texto,
  puede_agregar_media,
  recomponer_medias,
} from "../domain/cantidades";

describe("Jornadas — pieza / media ↔ canónico (§7.1)", () => {
  it("4 piezas + media → canónico 9", () => {
    const canonica = recomponer_medias({ piezas: 4, media: true });
    expect(canonica).toBe(9);
    expect(es_cantidad_valida(canonica)).toBe(true);
    expect(medias_a_texto(canonica)).toBe("4 piezas y media");
  });

  it("canónico 9 → 4 piezas + media", () => {
    expect(descomponer_medias(9)).toEqual({ piezas: 4, media: true });
  });

  it("entradas inválidas no se reinterpretan: lanzan Error", () => {
    expect(() => recomponer_medias({ piezas: 1.5, media: false })).toThrow(Error);
    expect(() => recomponer_medias({ piezas: Number.POSITIVE_INFINITY, media: false })).toThrow(Error);
    expect(() => recomponer_medias({ piezas: Number.NaN, media: true })).toThrow(Error);
    expect(() => descomponer_medias(1.5)).toThrow(Error);
  });
});

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

describe("Jornadas — límite de stock en pieza / media (§7.4)", () => {
  // Regla: piezas * 2 + (media ? 1 : 0) <= disponible
  function permitida(disponible: number, piezas: number, media: boolean): boolean {
    return (
      piezas <= maximo_piezas_segun_disponible(disponible, media) &&
      (!media || puede_agregar_media(disponible, piezas))
    );
  }

  it("disponible=1: media sí, 1 pieza no", () => {
    expect(permitida(1, 0, true)).toBe(true);
    expect(permitida(1, 1, false)).toBe(false);
  });

  it("disponible=2: 1 pieza sí, media sola sí, 1 pieza + media no", () => {
    expect(permitida(2, 1, false)).toBe(true);
    expect(permitida(2, 0, true)).toBe(true);
    expect(permitida(2, 1, true)).toBe(false);
    expect(puede_agregar_media(2, 1)).toBe(false); // A: con 1 pieza, media bloqueada
    expect(maximo_piezas_segun_disponible(2, true)).toBe(0); // B: con media, 1 pieza bloqueada
  });

  it("disponible=3: 1 pieza + media sí", () => {
    expect(permitida(3, 1, true)).toBe(true);
  });

  it("disponible=8: 4 piezas sí, 4 piezas + media no", () => {
    expect(permitida(8, 4, false)).toBe(true);
    expect(permitida(8, 4, true)).toBe(false);
  });

  it("disponible=9: 4 piezas + media sí", () => {
    expect(permitida(9, 4, true)).toBe(true);
  });

  it("disponible 0 no admite nada; nunca se supera el disponible", () => {
    expect(puede_agregar_media(0, 0)).toBe(false);
    expect(maximo_piezas_segun_disponible(0, false)).toBe(0);
    for (const disponible of [0, 1, 2, 3, 4, 5, 8, 9, 10, 15]) {
      for (let piezas = 0; piezas <= disponible; piezas++) {
        for (const media of [false, true]) {
          const canonica = recomponer_medias({ piezas, media });
          expect(permitida(disponible, piezas, media)).toBe(canonica <= disponible);
        }
      }
    }
  });
});

describe("Jornadas — valor de carga con precios independientes (ADR-002)", () => {
  // Misma forma de ítem que usa Jornadas.tsx (ItemCarga); el cálculo es la
  // función de dominio, no una fórmula local.
  const item = {
    unidad_medida: "pieza",
    cantidad: 9,
    precio: 12500,
    precio_media_pieza: 7000,
  } as const;

  it("4 piezas + media (c=9) no se infla ×2", () => {
    const valor = subtotal_linea(item);
    expect(valor).toBe(4 * 12500 + 7000);
    expect(valor).not.toBe(9 * 12500);
  });

  it("el total de la carga suma lácteos y fiambres sin error binario", () => {
    const fiambre = subtotal_linea(item);
    const lacteo = subtotal_linea({ unidad_medida: "unidad", cantidad: 3, precio: 0.1 });
    expect(sumar_importes([fiambre, lacteo])).toBe(57000.3);
  });
});
