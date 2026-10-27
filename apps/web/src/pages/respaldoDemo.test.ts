// Pruebas del contenido del respaldo JSON de la demo (ADR-005 D-R4).
// El respaldo usa una whitelist explícita de claves vigentes: nunca lee,
// copia ni borra las claves operativas anteriores (`_demo_v4`) y no recorre
// localStorage por prefijo. No existe importación/restauración de respaldo.
// Vitest corre en entorno node: se simula localStorage sobre globalThis.
import { beforeEach, describe, expect, it, vi } from "vitest";

import { CLAVE_CLIENTES, CLAVES_STORAGE } from "../data/clavesStorage";
import { CLAVES_RESPALDO, datosRespaldo } from "./respaldoDemo";

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
    key: vi.fn((index: number) => Array.from(store.keys())[index] ?? null),
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

const CLAVES_V4 = [
  "distribuidora_productos_demo_v4",
  "distribuidora_jornadas_demo_v4",
  "distribuidora_ventas_demo_v4",
  "distribuidora_cobros_demo_v4",
  "distribuidora_movimientos_demo_v4",
  "distribuidora_retornos_demo_v4",
  "distribuidora_camiones_demo_v4",
];

const LEGACY_V4 = JSON.stringify([
  { id: 4, nombre: "Jamón cocido", categoria: "Fiambres", unidadMedida: "pieza", stock: 9 },
]);

describe("CLAVES_RESPALDO: whitelist explícita", () => {
  it("son exactamente las 7 claves operativas v5 más clientes v2", () => {
    expect([...CLAVES_RESPALDO].sort()).toEqual(
      [...Object.values(CLAVES_STORAGE), CLAVE_CLIENTES].sort()
    );
    expect(CLAVES_RESPALDO).toHaveLength(8);
  });

  it("no incluye ninguna clave _demo_v4", () => {
    expect(CLAVES_RESPALDO.some((clave) => clave.endsWith("_demo_v4"))).toBe(false);
  });
});

describe("datosRespaldo", () => {
  it("exporta las claves vigentes presentes y omite las ausentes", () => {
    mockLS._store.set(CLAVES_STORAGE.productos, "[1]");
    mockLS._store.set(CLAVE_CLIENTES, "[2]");

    expect(datosRespaldo()).toEqual({
      [CLAVES_STORAGE.productos]: "[1]",
      [CLAVE_CLIENTES]: "[2]",
    });
  });

  it("con v4 presente: no la exporta, no la lee y la deja intacta", () => {
    for (const clave of CLAVES_V4) mockLS._store.set(clave, LEGACY_V4);
    mockLS._store.set("distribuidora_otra_demo_v9", "x");
    mockLS._store.set(CLAVES_STORAGE.jornadas, "[]");

    const datos = datosRespaldo();

    expect(datos).toEqual({ [CLAVES_STORAGE.jornadas]: "[]" });
    for (const clave of CLAVES_V4) {
      expect(mockLS.getItem).not.toHaveBeenCalledWith(clave);
      expect(mockLS._store.get(clave)).toBe(LEGACY_V4);
    }
  });

  it("no recorre localStorage (sin key() ni length) ni escribe o borra", () => {
    for (const clave of CLAVES_V4) mockLS._store.set(clave, LEGACY_V4);
    const length = vi.spyOn(mockLS, "length", "get");

    datosRespaldo();

    expect(mockLS.key).not.toHaveBeenCalled();
    expect(length).not.toHaveBeenCalled();
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS.removeItem).not.toHaveBeenCalled();
    expect(mockLS.clear).not.toHaveBeenCalled();
  });

  it("sólo consulta getItem sobre la whitelist", () => {
    datosRespaldo();
    const consultadas = mockLS.getItem.mock.calls.map(([clave]) => clave);
    expect(consultadas.sort()).toEqual([...CLAVES_RESPALDO].sort());
  });
});
