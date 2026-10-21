// Pruebas del versionado de persistencia localStorage: v1 → v2
// (docs/requirements/migracion-unidades-prototipo.md §7-bis y §8) y claves
// operativas v3 del modelo de precios (docs/decisions/002-...md). Ninguna
// clave anterior se lee, copia, reinterpreta ni borra.
// Vitest corre en entorno node: se simula localStorage sobre globalThis.
import { describe, expect, it, beforeEach, afterEach, vi } from "vitest";

import { cargarProductos } from "./useProductos";
import {
  productosIniciales,
  type Producto,
  type UnidadMedida,
} from "../data/mockProductos";
import { leerJornadas } from "./useJornadas";
import { cargarVentas } from "./useVentas";
import { leerMovimientos } from "./useMovimientos";
import { leerRetornos } from "./useRetornos";
import { cargarCamiones } from "./useCamiones";
import { cargarClientes } from "./useClientes";
import { leerCobros } from "./useCobros";
import { CLAVES_STORAGE } from "../data/clavesStorage";

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

describe("Inicialización v3: sin datos v3 → usa mocks canónicos", () => {
  it("productos: sin clave v3 devuelve productosIniciales (sin kg)", () => {
    const productos = cargarProductos();
    expect(productos.length).toBe(6);
    expect(
      productos.every(
        (p) => p.unidadMedida === "unidad" || p.unidadMedida === "pieza"
      )
    ).toBe(true);
  });

  it("jornadas: sin clave v3 devuelve arreglo vacío", () => {
    expect(leerJornadas()).toEqual([]);
  });

  it("ventas: sin clave v3 devuelve arreglo vacío", () => {
    expect(cargarVentas()).toEqual([]);
  });

  it("movimientos: sin clave v3 devuelve arreglo vacío", () => {
    expect(leerMovimientos()).toEqual([]);
  });

  it("retornos: sin clave v3 devuelve arreglo vacío", () => {
    expect(leerRetornos()).toEqual([]);
  });

  it("camiones: sin clave v3 devuelve camionesIniciales", () => {
    const camiones = cargarCamiones();
    expect(camiones.length).toBeGreaterThan(0);
  });

  it("clientes (v2, sin cambios): sin clave devuelve clientesIniciales", () => {
    const clientes = cargarClientes();
    expect(clientes.length).toBeGreaterThan(0);
  });

  it("cobros: sin clave v3 devuelve arreglo vacío", () => {
    expect(leerCobros()).toEqual([]);
  });
});

describe("v1 NO se migra: datos v1 incompatibles no se leen como v3", () => {
  it("productos: clave v1 con 'kg' no contamina v3", () => {
    // Hay datos v1 pero no v2: se usan los mocks canónicos (v2), no el v1.
    mockLS._store.set(
      "distribuidora_productos_demo_v1",
      JSON.stringify(productoV1ConKg)
    );

    const productos = cargarProductos();

    // v3 se inicializa desde productosIniciales (sin kg)
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

    // Jamón cocido en v3 tiene 36 medias piezas (18 piezas × 2), no 18.
    const jamon = productos.find((p) => p.nombre === "Jamón cocido");
    expect(jamon?.stock).toBe(36);
    // El dato v1 con id 998 no aparece.
    expect(productos.some((p) => p.id === 998)).toBe(false);
  });
});

describe("v1 NO se elimina: la clave v1 sigue intacta tras inicializar v3", () => {
  it("productos: la clave v1 permanece después de leer v3", () => {
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

describe("v3 ya existe: se respeta y no se reinicializa", () => {
  it("productos: si existe clave v3, se usa ese dato y no productosIniciales", () => {
    const datosV3: Producto[] = [
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
      CLAVES_STORAGE.productos,
      JSON.stringify(datosV3)
    );

    const productos = cargarProductos();

    expect(productos).toEqual(datosV3);
    expect(productos[0].id).toBe(777);
    expect(productos).toHaveLength(1);
  });
});

describe("Frontera de persistencia: combinación categoría ↔ unidad", () => {
  it("Lácteos + pieza en v3 no se acepta como producto válido", () => {
    mockLS._store.set(
      CLAVES_STORAGE.productos,
      JSON.stringify([
        {
          id: 9001,
          nombre: "Producto inválido Lácteos + pieza",
          categoria: "Lácteos",
          unidadMedida: "pieza",
          stock: 4,
          precio: 1000,
          stockMinimo: 1,
        },
      ])
    );

    // Semántica vigente del hook: si un elemento del payload es
    // inválido, todo el payload se rechaza y se arranca desde los
    // mocks canónicos. El producto inválido no se incorpora al
    // estado válido de la app.
    expect(cargarProductos()).toEqual(productosIniciales);
  });

  it("Fiambres + unidad en v3 no se acepta como producto válido", () => {
    mockLS._store.set(
      CLAVES_STORAGE.productos,
      JSON.stringify([
        {
          id: 9002,
          nombre: "Producto inválido Fiambres + unidad",
          categoria: "Fiambres",
          unidadMedida: "unidad",
          stock: 4,
          precio: 1000,
          stockMinimo: 1,
        },
      ])
    );

    expect(cargarProductos()).toEqual(productosIniciales);
  });

  it("Lácteos + unidad en v3 sigue aceptándose", () => {
    const datosV3: Producto[] = [
      {
        id: 9003,
        nombre: "Producto válido Lácteos + unidad",
        categoria: "Lácteos",
        unidadMedida: "unidad",
        stock: 4,
        precio: 1000,
        stockMinimo: 1,
      },
    ];

    mockLS._store.set(
      CLAVES_STORAGE.productos,
      JSON.stringify(datosV3)
    );

    expect(cargarProductos()).toEqual(datosV3);
  });

  it("Fiambres + pieza en v3 sigue aceptándose", () => {
    const datosV3: Producto[] = [
      {
        id: 9004,
        nombre: "Producto válido Fiambres + pieza",
        categoria: "Fiambres",
        unidadMedida: "pieza",
        stock: 8,
        precio: 9900,
        precioMediaPieza: 5500,
        stockMinimo: 2,
      },
    ];

    mockLS._store.set(
      CLAVES_STORAGE.productos,
      JSON.stringify(datosV3)
    );

    expect(cargarProductos()).toEqual(datosV3);
  });
});

const CLAVES_V2_ANTERIORES = {
  productos: "distribuidora_productos_demo_v2",
  jornadas: "distribuidora_jornadas_demo_v2",
  ventas: "distribuidora_ventas_demo_v2",
  cobros: "distribuidora_cobros_demo_v2",
  movimientos: "distribuidora_movimientos_demo_v2",
  retornos: "distribuidora_retornos_demo_v2",
  camiones: "distribuidora_camiones_demo_v2",
} as const;

describe("v2 NO se lee, copia ni borra: las siete claves operativas pasan a v3", () => {
  it("las siete claves compartidas terminan en _v3 y difieren de v2", () => {
    const claves = Object.entries(CLAVES_STORAGE);
    expect(claves).toHaveLength(7);
    for (const [nombre, clave] of claves) {
      expect(clave).toMatch(/_demo_v3$/);
      expect(clave).not.toBe(
        CLAVES_V2_ANTERIORES[nombre as keyof typeof CLAVES_V2_ANTERIORES]
      );
    }
  });

  it("con datos v2 presentes y sin v3, cada hook arranca limpio", () => {
    for (const clave of Object.values(CLAVES_V2_ANTERIORES)) {
      mockLS._store.set(clave, JSON.stringify([{ id: 1, dato: "v2" }]));
    }

    expect(cargarProductos()).toEqual(productosIniciales);
    expect(leerJornadas()).toEqual([]);
    expect(cargarVentas()).toEqual([]);
    expect(leerCobros()).toEqual([]);
    expect(leerMovimientos()).toEqual([]);
    expect(leerRetornos()).toEqual([]);
    expect(cargarCamiones().length).toBeGreaterThan(0);
  });

  it("las claves v2 quedan intactas tras inicializar v3", () => {
    for (const clave of Object.values(CLAVES_V2_ANTERIORES)) {
      mockLS._store.set(clave, JSON.stringify([{ id: 1, dato: "v2" }]));
    }

    cargarProductos();
    leerJornadas();
    cargarVentas();
    leerCobros();
    leerMovimientos();
    leerRetornos();
    cargarCamiones();

    for (const clave of Object.values(CLAVES_V2_ANTERIORES)) {
      expect(mockLS.getItem(clave)).toBe(
        JSON.stringify([{ id: 1, dato: "v2" }])
      );
    }
    // Nada se copió a v3.
    for (const clave of Object.values(CLAVES_STORAGE)) {
      expect(mockLS.setItem).not.toHaveBeenCalledWith(clave, expect.anything());
    }
  });

  it("clientes conserva su clave v2", () => {
    mockLS._store.set(
      "distribuidora_clientes_demo_v2",
      JSON.stringify([{ id: 1 }])
    );
    cargarClientes();
    expect(mockLS.getItem("distribuidora_clientes_demo_v2")).toBe(
      JSON.stringify([{ id: 1 }])
    );
  });
});

describe("Frontera de persistencia: precios (ADR-002)", () => {
  const fiambre = {
    id: 9100,
    nombre: "Fiambre de prueba",
    categoria: "Fiambres",
    unidadMedida: "pieza",
    stock: 8,
    precio: 10000,
    precioMediaPieza: 6000,
    stockMinimo: 2,
  };
  const lacteo = {
    id: 9101,
    nombre: "Lácteo de prueba",
    categoria: "Lácteos",
    unidadMedida: "unidad",
    stock: 8,
    precio: 2300.5,
    stockMinimo: 2,
  };

  function guardarProductos(productos: unknown[]) {
    mockLS._store.set(CLAVES_STORAGE.productos, JSON.stringify(productos));
  }

  it("acepta fiambre con ambos precios y lácteo sin precio de media", () => {
    guardarProductos([fiambre, lacteo]);
    expect(cargarProductos()).toEqual([fiambre, lacteo]);
  });

  it("rechaza pieza sin precioMediaPieza", () => {
    const { precioMediaPieza: _omitido, ...sinMedia } = fiambre;
    void _omitido;
    guardarProductos([sinMedia]);
    expect(cargarProductos()).toEqual(productosIniciales);
  });

  it("rechaza unidad con precioMediaPieza", () => {
    guardarProductos([{ ...lacteo, precioMediaPieza: 100 }]);
    expect(cargarProductos()).toEqual(productosIniciales);
  });

  it("rechaza precios negativos y con más de 2 decimales", () => {
    for (const mala of [
      { ...fiambre, precio: -1 },
      { ...fiambre, precioMediaPieza: -1 },
      { ...fiambre, precio: 10000.001 },
      { ...fiambre, precioMediaPieza: 5999.999 },
      { ...lacteo, precio: 0.005 },
    ]) {
      guardarProductos([mala]);
      expect(cargarProductos()).toEqual(productosIniciales);
    }
  });

  it("acepta precio 0 (validación mínima vigente)", () => {
    guardarProductos([{ ...lacteo, precio: 0 }]);
    expect(cargarProductos()).toHaveLength(1);
  });

  const itemJornada = {
    productoId: 3,
    nombreProducto: "Queso cremoso en pieza",
    unidadMedida: "pieza",
    cantidad: 3,
    precioReferencia: 10000,
    precioMediaPieza: 6000,
  };
  const jornadaBase = {
    id: "j-1",
    camionId: 1,
    chofer: "A",
    zona: "Z",
    fechaCreacion: "2026-10-20T10:00:00.000Z",
    fechaSalida: null,
    estado: "preparacion",
  };

  it("jornadas: acepta ítem pieza con ambos precios y rechaza pieza sin media", () => {
    mockLS._store.set(
      CLAVES_STORAGE.jornadas,
      JSON.stringify([{ ...jornadaBase, items: [itemJornada] }])
    );
    expect(leerJornadas()).toHaveLength(1);

    const { precioMediaPieza: _omitido, ...sinMedia } = itemJornada;
    void _omitido;
    mockLS._store.set(
      CLAVES_STORAGE.jornadas,
      JSON.stringify([{ ...jornadaBase, items: [sinMedia] }])
    );
    expect(leerJornadas()).toEqual([]);
  });

  const itemVenta = {
    productoId: 3,
    nombreProducto: "Queso cremoso en pieza",
    unidadMedida: "pieza",
    cantidad: 3,
    precioUnitario: 10000,
    precioMediaPieza: 6000,
    subtotal: 16000,
  };
  const ventaBase = {
    id: "v-1",
    jornadaId: "j-1",
    camionId: 1,
    clienteId: 1,
    nombreCliente: "Cliente",
    fecha: "2026-10-20T10:00:00.000Z",
    medioPago: "efectivo",
    total: 16000,
  };

  it("ventas: conserva el historial de precios y exige subtotal consistente", () => {
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([{ ...ventaBase, items: [itemVenta] }])
    );
    expect(cargarVentas()).toHaveLength(1);

    // 3 medias cobradas como 3 × pieza (30000) no coincide con el dominio.
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([{ ...ventaBase, items: [{ ...itemVenta, subtotal: 30000 }] }])
    );
    expect(cargarVentas()).toEqual([]);

    // Pieza sin precio de media aplicado.
    const { precioMediaPieza: _omitido, ...sinMedia } = itemVenta;
    void _omitido;
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([{ ...ventaBase, items: [sinMedia] }])
    );
    expect(cargarVentas()).toEqual([]);
  });
});
