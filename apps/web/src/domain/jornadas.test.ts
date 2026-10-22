// Bloque E / M-2: revalidación de la Jornada vigente justo antes de
// persistir. La Jornada que la página montó es un snapshot: al momento de
// escribir hay que comprobar, contra el conjunto que informa el lector
// discriminado, que el storage es legible, que la jornada existe, que su
// identidad de camión no cambió y que está en el estado requerido.
import { describe, expect, it } from "vitest";

import {
  revalidar_jornada_para_cobro,
  revalidar_jornada_para_operacion,
  type LecturaOperativaJornadas,
} from "./jornadas";
import { type Jornada } from "../data/mockJornadas";

const jornadaValida: Jornada = {
  id: "jornada-e",
  camionId: 1,
  chofer: "Chofer E",
  zona: "Centro",
  fechaCreacion: "2026-10-22T08:00:00.000Z",
  fechaSalida: null,
  estado: "preparacion",
  items: [],
};

const jornadaActualizada: Jornada = {
  ...jornadaValida,
  estado: "abierta",
  fechaSalida: "2026-10-22T09:00:00.000Z",
};

const jornadaCerrada: Jornada = {
  ...jornadaActualizada,
  estado: "cerrada",
  cierre: {
    fecha: "2026-10-22T18:00:00.000Z",
    conteos: {},
    efectivoEntregado: 0,
    efectivoEsperado: 0,
    transferenciasInformadas: 0,
    ventasCuentaCorriente: 0,
    observaciones: "",
  },
};

const lecturaValida = (jornadas: Jornada[]): LecturaOperativaJornadas => ({
  ok: true,
  jornadas,
});

const lecturaCorrupta: LecturaOperativaJornadas = {
  ok: false,
  error: "JSON inválido en almacenamiento de jornadas.",
};

describe("revalidar_jornada_para_operacion", () => {
  for (const estadoRequerido of ["abierta", "cerrada"] as const) {
    it(`storage corrupto (${estadoRequerido}): aborta con el error del lector`, () => {
      const resultado = revalidar_jornada_para_operacion(
        lecturaCorrupta,
        jornadaValida,
        estadoRequerido
      );

      expect(resultado.ok).toBe(false);
      if (!resultado.ok) {
        expect(resultado.error).toContain("No se pueden verificar las jornadas");
        expect(resultado.error).toContain(lecturaCorrupta.error);
      }
    });

    it(`jornada desaparecida (${estadoRequerido}): aborta`, () => {
      const resultado = revalidar_jornada_para_operacion(
        lecturaValida([]),
        jornadaValida,
        estadoRequerido
      );

      expect(resultado.ok).toBe(false);
      if (!resultado.ok) {
        expect(resultado.error).toContain("ya no existe");
      }
    });

    it(`identidad: camión cambiado (${estadoRequerido}): aborta`, () => {
      const resultado = revalidar_jornada_para_operacion(
        lecturaValida([{ ...jornadaActualizada, camionId: 99 }]),
        jornadaActualizada,
        estadoRequerido
      );

      expect(resultado.ok).toBe(false);
      if (!resultado.ok) {
        expect(resultado.error).toContain("cambió de camión");
      }
    });

    it(`estado distinto al requerido (${estadoRequerido}): aborta`, () => {
      const jornada =
        estadoRequerido === "abierta" ? jornadaCerrada : jornadaActualizada;

      const resultado = revalidar_jornada_para_operacion(
        lecturaValida([jornada]),
        jornada,
        estadoRequerido
      );

      expect(resultado.ok).toBe(false);
      if (!resultado.ok) {
        expect(resultado.error.length).toBeGreaterThan(0);
      }
    });

    it(`jornada vigente en el estado requerido (${estadoRequerido}): revalida con el estado actual`, () => {
      const jornada =
        estadoRequerido === "abierta" ? jornadaActualizada : jornadaCerrada;

      const resultado = revalidar_jornada_para_operacion(
        lecturaValida([jornada]),
        jornadaValida,
        estadoRequerido
      );

      expect(resultado.ok).toBe(true);
      if (resultado.ok) {
        expect(resultado.jornada).toEqual(jornada);
      }
    });
  }
});

describe("revalidar_jornada_para_cobro", () => {
  it("storage corrupto: aborta con el error del lector", () => {
    const resultado = revalidar_jornada_para_cobro(
      lecturaCorrupta,
      "jornada-e"
    );

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain(lecturaCorrupta.error);
    }
  });

  it("jornada desaparecida: aborta", () => {
    const resultado = revalidar_jornada_para_cobro(
      lecturaValida([]),
      "jornada-e"
    );

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("ya no existe");
    }
  });

  it("jornada cerrada después del montaje: aborta", () => {
    const resultado = revalidar_jornada_para_cobro(
      lecturaValida([jornadaCerrada]),
      "jornada-e"
    );

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("ya no está abierta");
    }
  });

  it("jornada abierta: revalida", () => {
    const resultado = revalidar_jornada_para_cobro(
      lecturaValida([jornadaActualizada]),
      "jornada-e"
    );

    expect(resultado.ok).toBe(true);
  });
});
