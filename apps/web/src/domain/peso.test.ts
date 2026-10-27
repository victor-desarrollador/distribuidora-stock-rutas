import { describe, expect, it } from "vitest";

import { gramos_a_kg, kg_a_gramos } from "./peso";

describe("kg_a_gramos", () => {
  it.each([
    ["1", 1000],
    ["1,2", 1200],
    ["1,25", 1250],
    ["1,250", 1250],
    ["28,680", 28680],
    ["47,300", 47300],
    ["0", 0],
    ["0,001", 1],
    ["0,5", 500],
    ["  2,500  ", 2500],
    ["2147483,647", 2147483647],
  ])("%s kg son %i g", (texto, gramos) => {
    expect(kg_a_gramos(texto)).toBe(gramos);
  });

  // En punto flotante 1.005 * 1000 da 1004.9999999999999.
  it("1,005 kg son exactamente 1005 g (sin punto flotante)", () => {
    expect(kg_a_gramos("1,005")).toBe(1005);
  });

  it.each([
    ["más de 3 decimales", "1,2500"],
    ["una fracción de gramo", "0,0001"],
    ["un negativo", "-1"],
    ["texto", "abc"],
    ["vacío", ""],
    ["sólo espacios", "   "],
    ["punto decimal (ambiguo con miles en es-AR)", "1.250"],
    ["miles y decimales", "1.250,5"],
    ["coma sin decimales", "1,"],
    ["coma sin entero", ",5"],
    ["signo +", "+1"],
    ["notación exponencial", "1e3"],
    ["espacio interno", "1 250"],
    ["dos comas", "1,2,3"],
    ["fuera de los enteros seguros", "9007199254740,992"],
  ])("rechaza %s", (_caso, texto) => {
    expect(kg_a_gramos(texto)).toBeNull();
  });
});

describe("gramos_a_kg", () => {
  it.each([
    [1250, "1,250"],
    [1000, "1,000"],
    [28680, "28,680"],
    [0, "0,000"],
    [1, "0,001"],
    [999, "0,999"],
    [2147483647, "2147483,647"],
  ])("%i g se muestran como %s kg", (gramos, texto) => {
    expect(gramos_a_kg(gramos)).toBe(texto);
  });

  it("la presentación vuelve a la misma cantidad canónica", () => {
    for (const gramos of [0, 1, 999, 1000, 1250, 28680, 2147483647]) {
      expect(kg_a_gramos(gramos_a_kg(gramos))).toBe(gramos);
    }
  });

  it.each([
    ["negativo", -1],
    ["fraccionario", 1.5],
    ["NaN", Number.NaN],
    ["infinito", Number.POSITIVE_INFINITY],
    ["fuera de los enteros seguros", Number.MAX_SAFE_INTEGER + 1],
  ])("lanza ante gramos %s", (_caso, gramos) => {
    expect(() => gramos_a_kg(gramos)).toThrow();
  });
});
