import { describe, expect, it } from "vitest";

import { estadoStorageOperativo } from "./estadoStorageOperativo";

describe("estadoStorageOperativo", () => {
  it.each(["inicial", "valido"] as const)(
    "%s es un estado legítimo y no bloquea",
    (estado) => {
      expect(
        estadoStorageOperativo({
          jornadas: estado,
          productos: estado,
          camiones: estado,
          clientes: estado,
        })
      ).toEqual({ avisos: [], bloqueado: false });
    }
  );

  it.each([
    ["jornadas", "Los datos de jornadas guardados están dañados."],
    ["productos", "Los datos de productos guardados están dañados."],
    ["camiones", "Los datos de camiones guardados están dañados."],
    ["clientes", "Los datos de clientes guardados están dañados."],
  ] as const)("%s corrupto avisa y bloquea", (fuente, texto) => {
    const resultado = estadoStorageOperativo({ [fuente]: "corrupto" });
    expect(resultado.bloqueado).toBe(true);
    expect(resultado.avisos).toHaveLength(1);
    expect(resultado.avisos[0]).toContain(texto);
  });

  it("solo evalúa las fuentes que la pantalla declara", () => {
    expect(estadoStorageOperativo({ jornadas: "valido" })).toEqual({
      avisos: [],
      bloqueado: false,
    });
  });

  it("varias fuentes corruptas generan avisos únicos", () => {
    const resultado = estadoStorageOperativo({
      jornadas: "corrupto",
      productos: "corrupto",
      camiones: "corrupto",
    });
    expect(resultado.bloqueado).toBe(true);
    expect(resultado.avisos).toHaveLength(3);
    expect(new Set(resultado.avisos).size).toBe(3);
  });
});
