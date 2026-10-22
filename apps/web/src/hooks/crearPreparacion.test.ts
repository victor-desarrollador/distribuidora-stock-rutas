// Bloque E / M-3: pruebas unitarias de la frontera `crearPreparacionPersistida`.
// Verifica que la creación de una preparación relea Jornadas y Retornos
// discriminadamente justo antes de persistir, que calcule el stock con esas
// lecturas frescas (no con el snapshot del montaje), que rechaze duplicados y
// storage corrupto sin escribir nada (raw intacto), y que las claves ausentes
// se tratan como ledgers iniciales.
// Vitest corre en entorno node: se simula localStorage sobre globalThis.
import { describe, expect, it, beforeEach, vi } from "vitest";

import {
  crearPreparacionPersistida,
} from "./useJornadas";
import type { Jornada } from "../data/mockJornadas";
import type { RetornoDeposito } from "../data/mockRetornos";
import { CLAVES_STORAGE } from "../data/clavesStorage";

// --- Simulación de localStorage para entorno node ---

const crearMockLocalStorage = () => {
  const store = new Map<string, string>();
  return {
    getItem: vi.fn((key: string) => store.get(key) ?? null),
    setItem: vi.fn((key: string, value: string) => {
      store.set(key, value);
    }),
    get length() {
      return store.size;
    },
    _store: store,
  };
};

let mockLS: ReturnType<typeof crearMockLocalStorage>;

beforeEach(() => {
  mockLS = crearMockLocalStorage();
  Object.defineProperty(globalThis, "localStorage", {
    value: mockLS,
    writable: true,
  });
});

// --- Datos de prueba ---

const itemCargaDe = (cantidad: number) => ({
  productoId: 1,
  nombreProducto: "Yogur de prueba",
  unidadMedida: "unidad" as const,
  cantidad,
  precioReferencia: 2300,
});

const jornadaPreparacion = (cantidad: number): Jornada => ({
  id: "jornada-previa",
  camionId: 1,
  chofer: "Chofer de prueba",
  zona: "Centro",
  fechaCreacion: "2026-10-22T08:00:00.000Z",
  fechaSalida: null,
  estado: "preparacion",
  items: [itemCargaDe(cantidad)],
});

const jornadaCerrada = (cantidad: number): Jornada => ({
  id: "jornada-previa",
  camionId: 1,
  chofer: "Chofer de prueba",
  zona: "Centro",
  fechaCreacion: "2026-10-22T08:00:00.000Z",
  fechaSalida: "2026-10-22T09:00:00.000Z",
  estado: "cerrada",
  items: [itemCargaDe(cantidad)],
  cierre: {
    fecha: "2026-10-22T18:00:00.000Z",
    conteos: { "1": cantidad },
    efectivoEntregado: 0,
    efectivoEsperado: 0,
    transferenciasInformadas: 0,
    ventasCuentaCorriente: 0,
    observaciones: "",
  },
});

const retornoAprobado = (cantidadAprobada: number): RetornoDeposito => ({
  id: "retorno-de-prueba",
  jornadaId: "jornada-previa",
  camionId: 1,
  fecha: "2026-10-22T19:00:00.000Z",
  responsable: "Encargado de prueba",
  observaciones: "",
  items: [
    {
      productoId: 1,
      nombreProducto: "Yogur de prueba",
      unidadMedida: "unidad",
      cantidadContada: 110,
      cantidadAprobada,
    },
  ],
});

const jornadaNueva: Jornada = {
  id: "jornada-nueva",
  camionId: 2,
  chofer: "Chofer nuevo",
  zona: "Sur",
  fechaCreacion: "2026-10-22T10:00:00.000Z",
  fechaSalida: null,
  estado: "preparacion",
  items: [itemCargaDe(100)],
};

const rawJornadasDe = (jornadas: Jornada[]) =>
  JSON.stringify(jornadas);

/**
 * clear callback de stock de prueba (misma semántica que la de la pantalla
 * Jornadas): reserva lo cargado en jornadas en curso, libera lo aprobado de
 * los retornos del mismo camión sobre jornadas cerradas.
 */
const validarStockDePrueba = (cantidadNueva: number) => (
  jornadasActuales: Jornada[],
  retornosActuales: RetornoDeposito[]
): string | null => {
  let reservado = 0;

  for (const j of jornadasActuales) {
    for (const item of j.items) {
      if (item.productoId === 1) reservado += item.cantidad;
    }
  }

  for (const r of retornosActuales) {
    const origen = jornadasActuales.find(
      (j) => j.id === r.jornadaId
    );
    if (
      !origen ||
      origen.estado !== "cerrada" ||
      origen.camionId !== r.camionId
    ) {
      continue;
    }
    for (const item of r.items) {
      if (item.productoId === 1) {
        reservado -= item.cantidadAprobada;
      }
    }
  }

  if (cantidadNueva + reservado > 120) {
    return "No hay stock suficiente de Yogur de prueba.";
  }

  return null;
};

describe("crearPreparacionPersistida — frontera M-3", () => {
  it("claves ausentes: ledgers iniciales, crea y persiste", () => {
    const resultado = crearPreparacionPersistida(
      jornadaNueva,
      validarStockDePrueba(100)
    );

    expect(resultado.ok).toBe(true);

    const raw = mockLS.getItem(CLAVES_STORAGE.jornadas);
    const jornadas = JSON.parse(String(raw)) as Jornada[];
    expect(jornadas).toHaveLength(1);
    expect(jornadas[0].id).toBe("jornada-nueva");
  });

  it("stock insuficiente reservado por jornadas leídas AHORA: aborta y no escribe", () => {
    const previa = jornadaPreparacion(110);
    mockLS.setItem(CLAVES_STORAGE.jornadas, rawJornadasDe([previa]));
    mockLS.setItem(CLAVES_STORAGE.retornos, "[]");

    const resultado = crearPreparacionPersistida(
      jornadaNueva,
      validarStockDePrueba(100)
    );

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("stock suficiente");
    }

    // Raw intacto: la nueva jornada NO se agregó.
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe(
      rawJornadasDe([previa])
    );
  });

  it("retorno aprobado libera stock: jornadas cerradas + retornos leídos AHORA alcanzan", () => {
    mockLS.setItem(
      CLAVES_STORAGE.jornadas,
      rawJornadasDe([jornadaCerrada(110)])
    );
    mockLS.setItem(
      CLAVES_STORAGE.retornos,
      JSON.stringify([retornoAprobado(100)])
    );

    const resultado = crearPreparacionPersistida(
      jornadaNueva,
      validarStockDePrueba(100)
    );

    expect(resultado.ok).toBe(true);

    const jornadas = JSON.parse(
      String(mockLS.getItem(CLAVES_STORAGE.jornadas))
    ) as Jornada[];
    expect(jornadas).toHaveLength(2);
    expect(jornadas.map((j) => j.id)).toContain("jornada-nueva");
  });

  it("jornadas corruptas: aborta con error concreto y raw intacto", () => {
    const rawCorrupto = "{jornadas dañadas";
    mockLS.setItem(CLAVES_STORAGE.jornadas, rawCorrupto);

    const resultado = crearPreparacionPersistida(
      jornadaNueva,
      validarStockDePrueba(100)
    );

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("No se puede guardar la preparación");
    }
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe(rawCorrupto);
  });

  it("retornos corruptos: aborta con error concreto y raw intacto", () => {
    mockLS.setItem(CLAVES_STORAGE.jornadas, "[]");
    const rawCorrupto = "{retornos dañados";
    mockLS.setItem(CLAVES_STORAGE.retornos, rawCorrupto);

    const resultado = crearPreparacionPersistida(
      jornadaNueva,
      validarStockDePrueba(100)
    );

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("No se puede guardar la preparación");
    }
    expect(mockLS.getItem(CLAVES_STORAGE.retornos)).toBe(rawCorrupto);
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe("[]");
  });

  it("camión con jornada activa (id distinto): duplicado rechazado, raw intacto", () => {
    const previa = jornadaPreparacion(10);
    const rawPrevias = rawJornadasDe([previa]);
    mockLS.setItem(CLAVES_STORAGE.jornadas, rawPrevias);

    // Mismo camión que la jornada previa, id distinto: el camión ya tiene
    // una jornada en curso.
    const duplicada: Jornada = {
      ...jornadaNueva,
      camionId: 1,
    };

    const resultado = crearPreparacionPersistida(
      duplicada,
      validarStockDePrueba(100)
    );

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("Ya existe una jornada activa");
    }
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe(rawPrevias);
  });

  it("id duplicado: rechazado sin escribir", () => {
    const previa = jornadaPreparacion(10);
    const rawPrevias = rawJornadasDe([previa]);
    mockLS.setItem(CLAVES_STORAGE.jornadas, rawPrevias);

    // Otro camión, mismo id: el id ya está registrado.
    const duplicadaId: Jornada = {
      ...previa,
      camionId: 2,
    };

    const resultado = crearPreparacionPersistida(
      duplicadaId,
      validarStockDePrueba(100)
    );

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error).toContain("Ya existe una jornada activa");
    }
    expect(mockLS.getItem(CLAVES_STORAGE.jornadas)).toBe(rawPrevias);
  });

  it("validarStock recibe las lecturas frescas (jornadas y retornos reídos)", () => {
    const previa = jornadaCerrada(110);
    mockLS.setItem(CLAVES_STORAGE.jornadas, rawJornadasDe([previa]));
    mockLS.setItem(
      CLAVES_STORAGE.retornos,
      JSON.stringify([retornoAprobado(100)])
    );

    const validar = vi.fn(() => null);

    const resultado = crearPreparacionPersistida(
      jornadaNueva,
      validar
    );

    expect(resultado.ok).toBe(true);
    expect(validar).toHaveBeenCalledTimes(1);
    // Validar recibió las lecturas frescas: la jornada cerrada leída AHORA y
    // el retorno aprobado leído AHORA (no del snapshot del montaje).
    expect(validar).toHaveBeenCalledWith(
      expect.arrayContaining([
        expect.objectContaining({ id: "jornada-previa" }),
      ]),
      expect.arrayContaining([
        expect.objectContaining({ jornadaId: "jornada-previa" }),
      ])
    );
  });
});
