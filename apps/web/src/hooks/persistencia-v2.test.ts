// Pruebas del versionado de persistencia localStorage v1 → v2
// (docs/requirements/migracion-unidades-prototipo.md §7-bis y §8).
// Vitest corre en entorno node: se simula localStorage sobre globalThis.
import { describe, expect, it, beforeEach, afterEach, vi } from "vitest";

import { cargarProductos } from "./useProductos";
import type { Producto, UnidadMedida } from "../data/mockProductos";
import { leerJornadas } from "./useJornadas";
import { cargarVentas } from "./useVentas";
import { leerMovimientos } from "./useMovimientos";
import { leerRetornos } from "./useRetornos";
import { cargarCamiones } from "./useCamiones";
import { cargarClientes } from "./useClientes";
import { leerCobros } from "./useCobros";

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

// --- Datos v1 incompatibles (para demostrar que no se reinterpretan) ---

const productoV1ConKg: Producto[] = [
  {
    id: 999,
    nombre: "Producto legacy kg",
    categoria: "Lácteos",
    unidadMedida: "kg" as unknown as UnidadMedida,
    stock: 10,
    precio: 100,
    stockMinimo: 1,
  },
];

const productoV1PiezasEnteras: Producto[] = [
  {
    id: 998,
    nombre: "Jamón legacy piezas enteras",
    categoria: "Fiambres",
    unidadMedida: "pieza",
    stock: 18, // 18 piezas enteras, no 18 medias piezas
    precio: 12500,
    stockMinimo: 5,
  },
];

describe("Inicialización v2: sin datos v2 → usa mocks canónicos", () => {
  it("productos: sin clave v2 devuelve productosIniciales (sin kg)", () => {
    const productos = cargarProductos();
    expect(productos.length).toBe(6);
    expect(
      productos.every(
        (p) => p.unidadMedida === "unidad" || p.unidadMedida === "pieza"
      )
    ).toBe(true);
  });

  it("jornadas: sin clave v2 devuelve arreglo vacío", () => {
    expect(leerJornadas()).toEqual([]);
  });

  it("ventas: sin clave v2 devuelve arreglo vacío", () => {
    expect(cargarVentas()).toEqual([]);
  });

  it("movimientos: sin clave v2 devuelve arreglo vacío", () => {
    expect(leerMovimientos()).toEqual([]);
  });

  it("retornos: sin clave v2 devuelve arreglo vacío", () => {
    expect(leerRetornos()).toEqual([]);
  });

  it("camiones: sin clave v2 devuelve camionesIniciales", () => {
    const camiones = cargarCamiones();
    expect(camiones.length).toBeGreaterThan(0);
  });

  it("clientes: sin clave v2 devuelve clientesIniciales", () => {
    const clientes = cargarClientes();
    expect(clientes.length).toBeGreaterThan(0);
  });

  it("cobros: sin clave v2 devuelve arreglo vacío", () => {
    expect(leerCobros()).toEqual([]);
  });
});

describe("v1 NO se migra: datos v1 incompatibles no se leen como v2", () => {
  it("productos: clave v1 con 'kg' no contamina v2", () => {
    // Hay datos v1 pero no v2: se usan los mocks canónicos (v2), no el v1.
    mockLS._store.set(
      "distribuidora_productos_demo_v1",
      JSON.stringify(productoV1ConKg)
    );

    const productos = cargarProductos();

    // v2 se inicializa desde productosIniciales (sin kg)
    expect(productos.length).toBe(6);
    expect(
      productos.every(
        (p) => p.unidadMedida === "unidad" || p.unidadMedida === "pieza"
      )
    ).toBe(true);
    expect(productos.some((p) => p.id === 999)).toBe(false);
  });

  it("productos: clave v1 con piezas enteras no se reinterpretan como medias piezas", () => {
    mockLS._store.set(
      "distribuidora_productos_demo_v1",
      JSON.stringify(productoV1PiezasEnteras)
    );

    const productos = cargarProductos();

    // Jamón cocido en v2 tiene 36 medias piezas (18 piezas × 2), no 18.
    const jamon = productos.find((p) => p.nombre === "Jamón cocido");
    expect(jamon?.stock).toBe(36);
    // El dato v1 con id 998 no aparece.
    expect(productos.some((p) => p.id === 998)).toBe(false);
  });
});

describe("v1 NO se elimina: la clave v1 sigue intacta tras inicializar v2", () => {
  it("productos: la clave v1 permanece después de leer v2", () => {
    mockLS._store.set(
      "distribuidora_productos_demo_v1",
      JSON.stringify(productoV1ConKg)
    );

    cargarProductos();

    expect(mockLS.getItem("distribuidora_productos_demo_v1")).toBe(
      JSON.stringify(productoV1ConKg)
    );
  });
});

describe("v2 ya existe: se respeta y no se reinicializa", () => {
  it("productos: si existe clave v2, se usa ese dato y no productosIniciales", () => {
    const datosV2: Producto[] = [
      {
        id: 777,
        nombre: "Producto ya guardado en v2",
        categoria: "Lácteos",
        unidadMedida: "unidad",
        stock: 5,
        precio: 500,
        stockMinimo: 1,
      },
    ];

    mockLS._store.set(
      "distribuidora_productos_demo_v2",
      JSON.stringify(datosV2)
    );

    const productos = cargarProductos();

    expect(productos).toEqual(datosV2);
    expect(productos[0].id).toBe(777);
    expect(productos).toHaveLength(1);
  });
});
