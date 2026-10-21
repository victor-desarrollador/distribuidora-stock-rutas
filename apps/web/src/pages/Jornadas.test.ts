// Test de integración del flujo de cantidades en Jornadas.
// Verifica la transformación UX ↔ canónico usada en la pantalla Jornadas.
//
// Fuente: BLUEPRINT.md §7.1 (unidades pieza / media pieza) y §7.4 (cantidades
// enteras, nunca decimales, nunca negativos).

import { describe, expect, it } from "vitest";
import {
  descomponer_medias,
  medias_a_texto,
  recomponer_medias,
  es_cantidad_valida,
} from "../domain/cantidades";

// Replica la lógica de transformación de Jornadas.tsx para testear el cableado real.
function obtenerCantidadCanonica(valor: string | { piezas: number; media: boolean }): number {
  if (!valor) return 0;
  if (typeof valor === "string") {
    const n = Number(valor);
    return Number.isFinite(n) && n >= 0 ? n : 0;
  }
  try {
    return recomponer_medias(valor);
  } catch {
    return 0;
  }
}

function descomponerParaUI(cantidadCanonica: number): { piezas: number; media: boolean } {
  return descomponer_medias(cantidadCanonica);
}

describe("Jornadas — transformación UX ↔ canónico (§7.1)", () => {
  it("4 piezas + media → canónico 9", () => {
    const ux = { piezas: 4, media: true };
    const canonica = recomponer_medias(ux);
    expect(canonica).toBe(9);
    expect(es_cantidad_valida(canonica)).toBe(true);
  });

  it("canónico 9 → rehidratación reconstruye 4 piezas + media", () => {
    const canonica = 9;
    const ux = descomponerParaUI(canonica);
    expect(ux).toEqual({ piezas: 4, media: true });
    expect(recomponer_medias(ux)).toBe(canonica);
  });

  it("presentación legible del canónico 9", () => {
    expect(medias_a_texto(9)).toBe("4 piezas y media");
  });

  it("round-trip: varios valores canónicos representativos", () => {
    const casos = [0, 1, 2, 3, 4, 5, 8, 9, 10, 15, 20];
    for (const canonica of casos) {
      const ux = descomponerParaUI(canonica);
      const vuelta = recomponer_medias(ux);
      expect(vuelta).toBe(canonica);
    }
  });

  it("obtenerCantidadCanonica: string para unidad, objeto para pieza", () => {
    expect(obtenerCantidadCanonica("5")).toBe(5); // unidad
    expect(obtenerCantidadCanonica({ piezas: 4, media: true })).toBe(9); // pieza
    expect(obtenerCantidadCanonica({ piezas: 0, media: true })).toBe(1);
    expect(obtenerCantidadCanonica({ piezas: 2, media: false })).toBe(4);
  });
});

describe("Jornadas — validación de stock contra disponibles (§7.4)", () => {
  // Simula la lógica de validación de maxPiezas y mediaDisabled
  // que evita construir combinaciones que excedan el disponible.
  function maxPiezasPermitidas(disponible: number, media: boolean): number {
    return media
      ? Math.max(0, Math.floor((disponible - 1) / 2))
      : Math.max(0, Math.floor(disponible / 2));
  }

  function mediaDisabled(disponible: number, piezas: number): boolean {
    return disponible < 1 || piezas * 2 >= disponible;
  }

  it("disponible=1: permite media, no permite 1 pieza", () => {
    expect(maxPiezasPermitidas(1, false)).toBe(0); // 1 pieza no permitida
    expect(maxPiezasPermitidas(1, true)).toBe(0);
    expect(mediaDisabled(1, 0)).toBe(false); // media sí permitida
    // 1 pieza + media = 3 > 1 → no permitido por guardarPreparacion
  });

  it("disponible=2: permite 1 pieza; media sola sí; 1 pieza + media NO", () => {
    expect(maxPiezasPermitidas(2, false)).toBe(1); // 1 pieza permitida
    expect(maxPiezasPermitidas(2, true)).toBe(0); // si media, 0 piezas
    expect(mediaDisabled(2, 0)).toBe(false); // media permitida si 0 piezas
    expect(mediaDisabled(2, 1)).toBe(true); // si 1 pieza, media NO
    // guardarPreparacion rechaza canónico > 2
  });

  it("disponible=3: permite 1 pieza + media", () => {
    expect(maxPiezasPermitidas(3, false)).toBe(1);
    expect(maxPiezasPermitidas(3, true)).toBe(1); // 1 pieza + media = 3
    expect(mediaDisabled(3, 1)).toBe(false); // media permitida si 1 pieza
  });

  it("disponible=8: permite 4 piezas; 4 piezas + media NO", () => {
    expect(maxPiezasPermitidas(8, false)).toBe(4);
    expect(maxPiezasPermitidas(8, true)).toBe(3); // si media, max 3 piezas
    expect(mediaDisabled(8, 4)).toBe(true); // si 4 piezas, media NO
  });

  it("disponible=9: permite 4 piezas + media", () => {
    expect(maxPiezasPermitidas(9, false)).toBe(4);
    expect(maxPiezasPermitidas(9, true)).toBe(4); // 4 piezas + media = 9
    expect(mediaDisabled(9, 4)).toBe(false); // media permitida si 4 piezas
  });

  it("validación final: canónico nunca supera disponible", () => {
    for (const disponible of [1, 2, 3, 4, 5, 8, 9, 10, 15, 20]) {
      for (let piezas = 0; piezas <= Math.floor(disponible / 2) + 1; piezas++) {
        for (const media of [false, true] as const) {
          const canonica = recomponer_medias({ piezas, media });
          if (canonica <= disponible) {
            // Combinación válida: maxPiezas debe permitirla
            expect(maxPiezasPermitidas(disponible, media)).toBeGreaterThanOrEqual(piezas);
            // mediaDisabled solo es relevante cuando media=true
            if (media) {
              expect(mediaDisabled(disponible, piezas)).toBe(false);
            }
          } else {
            // Combinación inválida: al menos un control debe bloquearla
            const maxP = maxPiezasPermitidas(disponible, media);
            const mediaD = media ? mediaDisabled(disponible, piezas) : false;
            const bloqueada = piezas > maxP || mediaD;
            expect(bloqueada).toBe(true);
          }
        }
      }
    }
  });
});