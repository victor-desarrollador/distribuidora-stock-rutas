// Frontera de escritura de catálogos (M-1): actualizarCatalogoPersistido
// relee la clave en el momento de la operación, aborta ante corrupción
// aparecida después del montaje, persiste solo con la relectura confiable y
// devuelve el conjunto nuevo únicamente si setItem tuvo éxito.
import { describe, expect, it, beforeEach, afterEach, vi } from "vitest";

import {
  actualizarCatalogoPersistido,
  leerCatalogo,
} from "./catalogoStorage";

const CLAVE = "distribuidora_test_catalogo_frontend_bloque_e";

type Dato = { id: number; etiqueta: string };

const datoValido = (dato: unknown): boolean =>
  dato !== null &&
  typeof dato === "object" &&
  Number.isSafeInteger((dato as Partial<Dato>).id) &&
  typeof (dato as Partial<Dato>).etiqueta === "string" &&
  (dato as Partial<Dato>).etiqueta !== "";

const dato1: Dato = { id: 1, etiqueta: "uno" };
const dato2: Dato = { id: 2, etiqueta: "dos" };

// Semillas demo equivalentes a las iniciales de cada catálogo.
const INICIALES: Dato[] = [dato1];

// --- Simulación de localStorage para entorno node ---

const crearMockLocalStorage = () => {
  const store = new Map<string, string>();
  return {
    getItem: vi.fn((key: string) => store.get(key) ?? null),
    setItem: vi.fn((key: string, value: string) => {
      store.set(key, value);
    }),
    removeItem: vi.fn((key: string) => {
      store.delete(key);
    }),
    clear: vi.fn(() => {
      store.clear();
    }),
    get length() {
      return store.size;
    },
    key: vi.fn((index: number) => {
      const arr = Array.from(store.keys());
      return arr[index] ?? null;
    }),
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

afterEach(() => {
  vi.restoreAllMocks();
});

describe("actualizarCatalogoPersistido", () => {
  it("clave ausente: el primer cambio se persiste (estado inicial legítimo)", () => {
    const resultado = actualizarCatalogoPersistido<Dato>(
      CLAVE,
      datoValido,
      INICIALES,
      (actuales) => [...actuales, dato2]
    );

    expect(resultado).toEqual([dato1, dato2]);
    expect(mockLS.getItem(CLAVE)).toBe(JSON.stringify([dato1, dato2]));
  });

  it("clave válida: el cambio se persiste sobre los datos actuales", () => {
    mockLS.setItem(CLAVE, JSON.stringify([dato1]));

    const resultado = actualizarCatalogoPersistido<Dato>(
      CLAVE,
      datoValido,
      INICIALES,
      (actuales) => [...actuales, dato2]
    );

    expect(resultado).toEqual([dato1, dato2]);
    expect(mockLS.getItem(CLAVE)).toBe(JSON.stringify([dato1, dato2]));
  });

  for (const [variante, raw] of [
    ["cadena vacía", ""],
    ["null textual", "null"],
    ["JSON inválido", "{corrupto"],
    ["no array", JSON.stringify({ tres: 3 })],
    ["elemento inválido", JSON.stringify([{ id: 3, etiqueta: "" }])],
  ] as const) {
    it(`clave corrupta (${variante}): aborta sin escribir y deja el raw intacto`, () => {
      mockLS.setItem(CLAVE, raw);

      const resultado = actualizarCatalogoPersistido<Dato>(
        CLAVE,
        datoValido,
        INICIALES,
        (actuales) => [...actuales, dato2]
      );

      expect(resultado).toBeNull();
      expect(mockLS.getItem(CLAVE)).toBe(raw);
    });
  }

  it("corrupción aparecida después del montaje: la lectura inicial válida NO autoriza la escritura", () => {
    // Simula el requisito M-1: el set es válido cuando la página montó
    // (el hook conserva su snapshot ok) y la clave se corrompe antes de
    // escribir. La frontera relee AHORA: aunque el llamador quiera persistir
    // el snapshot del montaje más su cambio, la escritura se aborta.
    mockLS.setItem(CLAVE, JSON.stringify([dato1]));

    const lecturaMontaje = leerCatalogo<Dato>(CLAVE, datoValido, []);
    if (lecturaMontaje.ok) {
      expect(lecturaMontaje.datos).toEqual([dato1]);
    }
    expect(lecturaMontaje.ok).toBe(true);

    mockLS.setItem(CLAVE, "{corrupción posterior al montaje");

    const setItemSpy = vi.spyOn(mockLS, "setItem");
    setItemSpy.mockClear();

    const resultado = actualizarCatalogoPersistido<Dato>(
      CLAVE,
      datoValido,
      INICIALES,
      (actuales) => {
        // El llamador ignora lo releyído (quiere el snapshot del montaje):
        // la frontera igualmente tiene que haber abortado antes de aplicar.
        void actuales;
        return [...(lecturaMontaje.ok ? lecturaMontaje.datos : []), dato2];
      }
    );

    expect(resultado).toBeNull();
    expect(setItemSpy).not.toHaveBeenCalled();
    expect(mockLS.getItem(CLAVE)).toBe("{corrupción posterior al montaje");
  });

  it("conjunto nuevo inválido: aborta sin escribir", () => {
    mockLS.setItem(CLAVE, JSON.stringify([dato1]));

    const setItemSpy = vi.spyOn(mockLS, "setItem");
    setItemSpy.mockClear();

    const resultado = actualizarCatalogoPersistido<Dato>(
      CLAVE,
      datoValido,
      INICIALES,
      (actuales) => [...actuales, { id: 2, etiqueta: "" }]
    );

    expect(resultado).toBeNull();
    expect(setItemSpy).not.toHaveBeenCalled();
    expect(mockLS.getItem(CLAVE)).toBe(JSON.stringify([dato1]));
  });

  it("setItem lanza: la operación falla, el raw queda como estaba y no hay éxito", () => {
    mockLS.setItem(CLAVE, JSON.stringify([dato1]));
    const rawAntes = mockLS.getItem(CLAVE);

    vi.spyOn(mockLS, "setItem").mockImplementation(() => {
      throw new Error("QuotaExceededError simulado");
    });

    const resultado = actualizarCatalogoPersistido<Dato>(
      CLAVE,
      datoValido,
      INICIALES,
      (actuales) => [...actuales, dato2]
    );

    expect(resultado).toBeNull();
    expect(mockLS.getItem(CLAVE)).toBe(rawAntes);
  });

  it("la relectura y la escritura usan la misma clave y validador que la lectura pública", () => {
    mockLS.setItem(CLAVE, JSON.stringify([dato1]));

    const relectura = leerCatalogo<Dato>(CLAVE, datoValido, []);
    expect(relectura.ok).toBe(true);

    expect(
      actualizarCatalogoPersistido<Dato>(CLAVE, datoValido, INICIALES, (a) => a)
    ).toEqual([dato1]);
  });
});
