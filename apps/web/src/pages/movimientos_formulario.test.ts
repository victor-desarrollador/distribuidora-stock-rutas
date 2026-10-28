// Test UNITARIO de los atributos de UX del input de Movimientos (B2) y de la
// presentación de cantidades. No monta React: la interpretación del texto se
// prueba en src/domain/movimientos.test.ts y la frontera en
// src/hooks/registrarMovimiento.test.ts.
import { describe, expect, it } from "vitest";

import { atributos_input_movimiento } from "./movimientos_formulario";
import {
  cantidad_movimiento_desde_entrada,
  es_cambio_mixto,
} from "../domain/movimientos";
import { cantidad_a_texto } from "../domain/productos";

describe("input de cantidad por unidad — regresión UX de unidad y kg para peso", () => {
  it("unidad conserva el input anterior (type number, min 0, step 1, placeholder 0)", () => {
    expect(atributos_input_movimiento("unidad")).toEqual({
      type: "number",
      min: "0",
      step: "1",
      placeholder: "0",
    });
  });

  it("peso usa texto en kg con coma (sin min ni step numéricos)", () => {
    expect(atributos_input_movimiento("peso")).toEqual({
      type: "text",
      inputMode: "decimal",
      placeholder: "0,000",
    });
  });

  it("la representación canónica no cambia: el mismo texto da unidades o gramos según el producto", () => {
    expect(cantidad_movimiento_desde_entrada("unidad", { texto: "3" })).toBe(3);
    expect(cantidad_movimiento_desde_entrada("peso", { texto: "3" })).toBe(3000);
    expect(cantidad_movimiento_desde_entrada("unidad", { texto: "1,250" })).toBeNull();
    expect(cantidad_movimiento_desde_entrada("peso", { texto: "1,250" })).toBe(1250);
  });
});

describe("cambio: peso ↔ peso habilitado; mixto bloqueado", () => {
  const jamon = { unidadMedida: "peso" as const };
  const salame = { unidadMedida: "peso" as const };
  const yogur = { unidadMedida: "unidad" as const };

  it("peso ↔ peso y unidad ↔ unidad no son mixtos", () => {
    expect(es_cambio_mixto(jamon, salame)).toBe(false);
    expect(es_cambio_mixto(yogur, yogur)).toBe(false);
  });

  it("unidad ↔ peso y peso ↔ unidad son mixtos (la pantalla los bloquea)", () => {
    expect(es_cambio_mixto(yogur, jamon)).toBe(true);
    expect(es_cambio_mixto(jamon, yogur)).toBe(true);
  });
});

describe("disponible peso con 3 decimales fijos en kg", () => {
  it.each([
    [1250, "1,250 kg"],
    [980, "0,980 kg"],
    [1, "0,001 kg"],
    [0, "0,000 kg"],
  ])("%i g → %j", (gramos, texto) => {
    expect(cantidad_a_texto("peso", gramos)).toBe(texto);
  });
});
