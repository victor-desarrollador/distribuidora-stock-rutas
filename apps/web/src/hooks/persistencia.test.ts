// Pruebas del versionado de persistencia localStorage: v1 → v2
// (docs/requirements/migracion-unidades-prototipo.md §7-bis y §8) y claves
// operativas v4 del precio derivado de media pieza
// (docs/decisions/003-precio-derivado-media-pieza.md). Ninguna
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
import {
  leerMovimientos,
  registrarMovimientoOperacion,
} from "./useMovimientos";
import type {
  MovimientoReparto,
  ProductoMovimiento,
} from "../data/mockMovimientos";
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

describe("Inicialización v4: sin datos v4 → usa mocks canónicos", () => {
  it("productos: sin clave v4 devuelve productosIniciales (sin kg)", () => {
    const productos = cargarProductos();
    expect(productos.length).toBe(6);
    expect(
      productos.every(
        (p) => p.unidadMedida === "unidad" || p.unidadMedida === "pieza"
      )
    ).toBe(true);
  });

  it("jornadas: sin clave v4 devuelve arreglo vacío", () => {
    expect(leerJornadas()).toEqual([]);
  });

  it("ventas: sin clave v4 devuelve arreglo vacío", () => {
    expect(cargarVentas()).toEqual([]);
  });

  it("movimientos: sin clave v4 devuelve arreglo vacío", () => {
    expect(leerMovimientos()).toEqual([]);
  });

  it("retornos: sin clave v4 devuelve arreglo vacío", () => {
    expect(leerRetornos()).toEqual([]);
  });

  it("camiones: sin clave v4 devuelve camionesIniciales", () => {
    const camiones = cargarCamiones();
    expect(camiones.length).toBeGreaterThan(0);
  });

  it("clientes (v2, sin cambios): sin clave devuelve clientesIniciales", () => {
    const clientes = cargarClientes();
    expect(clientes.length).toBeGreaterThan(0);
  });

  it("cobros: sin clave v4 devuelve arreglo vacío", () => {
    expect(leerCobros()).toEqual([]);
  });
});

describe("v1 NO se migra: datos v1 incompatibles no se leen como v4", () => {
  it("productos: clave v1 con 'kg' no contamina v4", () => {
    // Hay datos v1 pero no v2: se usan los mocks canónicos (v2), no el v1.
    mockLS._store.set(
      "distribuidora_productos_demo_v1",
      JSON.stringify(productoV1ConKg)
    );

    const productos = cargarProductos();

    // v4 se inicializa desde productosIniciales (sin kg)
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

    // Jamón cocido en v4 tiene 36 medias piezas (18 piezas × 2), no 18.
    const jamon = productos.find((p) => p.nombre === "Jamón cocido");
    expect(jamon?.stock).toBe(36);
    // El dato v1 con id 998 no aparece.
    expect(productos.some((p) => p.id === 998)).toBe(false);
  });
});

describe("v1 NO se elimina: la clave v1 sigue intacta tras inicializar v4", () => {
  it("productos: la clave v1 permanece después de leer v4", () => {
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

describe("v4 ya existe: se respeta y no se reinicializa", () => {
  it("productos: si existe clave v4, se usa ese dato y no productosIniciales", () => {
    const datosV4: Producto[] = [
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
      JSON.stringify(datosV4)
    );

    const productos = cargarProductos();

    expect(productos).toEqual(datosV4);
    expect(productos[0].id).toBe(777);
    expect(productos).toHaveLength(1);
  });
});

describe("Frontera de persistencia: combinación categoría ↔ unidad", () => {
  it("Lácteos + pieza en v4 no se acepta como producto válido", () => {
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

  it("Fiambres + unidad en v4 no se acepta como producto válido", () => {
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

  it("Lácteos + unidad en v4 sigue aceptándose", () => {
    const datosV4: Producto[] = [
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
      JSON.stringify(datosV4)
    );

    expect(cargarProductos()).toEqual(datosV4);
  });

  it("Fiambres + pieza en v4 sigue aceptándose", () => {
    const datosV4: Producto[] = [
      {
        id: 9004,
        nombre: "Producto válido Fiambres + pieza",
        categoria: "Fiambres",
        unidadMedida: "pieza",
        stock: 8,
        precio: 9900,
        stockMinimo: 2,
      },
    ];

    mockLS._store.set(
      CLAVES_STORAGE.productos,
      JSON.stringify(datosV4)
    );

    expect(cargarProductos()).toEqual(datosV4);
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

// Claves v3 de ADR-002 (superada por ADR-003). Solo existen en esta prueba,
// para demostrar que los hooks no las leen, copian ni borran.
const CLAVES_V3_ANTERIORES = {
  productos: "distribuidora_productos_demo_v3",
  jornadas: "distribuidora_jornadas_demo_v3",
  ventas: "distribuidora_ventas_demo_v3",
  cobros: "distribuidora_cobros_demo_v3",
  movimientos: "distribuidora_movimientos_demo_v3",
  retornos: "distribuidora_retornos_demo_v3",
  camiones: "distribuidora_camiones_demo_v3",
} as const;

describe("v3 (ADR-002) NO se lee, copia ni borra", () => {
  const dato_v3 = JSON.stringify([{ id: 1, dato: "v3" }]);

  it("las siete claves compartidas difieren de v3", () => {
    for (const [nombre, clave] of Object.entries(CLAVES_STORAGE)) {
      expect(clave).not.toBe(
        CLAVES_V3_ANTERIORES[nombre as keyof typeof CLAVES_V3_ANTERIORES]
      );
    }
  });

  it("con datos v3 presentes y sin v4, cada hook arranca limpio y v3 queda intacta", () => {
    for (const clave of Object.values(CLAVES_V3_ANTERIORES)) {
      mockLS._store.set(clave, dato_v3);
    }

    expect(cargarProductos()).toEqual(productosIniciales);
    expect(leerJornadas()).toEqual([]);
    expect(cargarVentas()).toEqual([]);
    expect(leerCobros()).toEqual([]);
    expect(leerMovimientos()).toEqual([]);
    expect(leerRetornos()).toEqual([]);
    expect(cargarCamiones().length).toBeGreaterThan(0);

    for (const clave of Object.values(CLAVES_V3_ANTERIORES)) {
      expect(mockLS.getItem(clave)).toBe(dato_v3);
    }
    // Nada se copió a v4.
    for (const clave of Object.values(CLAVES_STORAGE)) {
      expect(mockLS.setItem).not.toHaveBeenCalledWith(clave, expect.anything());
    }
  });
});

describe("v2 NO se lee, copia ni borra: las siete claves operativas pasan a v4", () => {
  it("las siete claves compartidas terminan en _v4 y difieren de v2", () => {
    const claves = Object.entries(CLAVES_STORAGE);
    expect(claves).toHaveLength(7);
    for (const [nombre, clave] of claves) {
      expect(clave).toMatch(/_demo_v4$/);
      expect(clave).not.toBe(
        CLAVES_V2_ANTERIORES[nombre as keyof typeof CLAVES_V2_ANTERIORES]
      );
    }
  });

  it("las siete claves son exactamente las de ADR-003", () => {
    expect(CLAVES_STORAGE).toEqual({
      productos: "distribuidora_productos_demo_v4",
      jornadas: "distribuidora_jornadas_demo_v4",
      ventas: "distribuidora_ventas_demo_v4",
      cobros: "distribuidora_cobros_demo_v4",
      movimientos: "distribuidora_movimientos_demo_v4",
      retornos: "distribuidora_retornos_demo_v4",
      camiones: "distribuidora_camiones_demo_v4",
    });
  });

  it("con datos v2 presentes y sin v4, cada hook arranca limpio", () => {
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

  it("las claves v2 quedan intactas tras inicializar v4", () => {
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
    // Nada se copió a v4.
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

describe("Frontera de persistencia: precios (ADR-003)", () => {
  const fiambre = {
    id: 9100,
    nombre: "Fiambre de prueba",
    categoria: "Fiambres",
    unidadMedida: "pieza",
    stock: 8,
    precio: 10000,
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

  it("acepta fiambre con precio válido y lácteo con precio válido", () => {
    guardarProductos([fiambre, lacteo]);
    expect(cargarProductos()).toEqual([fiambre, lacteo]);
  });

  it("rechaza precios negativos y con más de 2 decimales", () => {
    for (const mala of [
      { ...fiambre, precio: -1 },
      { ...fiambre, precio: 10000.001 },
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

  it("jornadas: acepta ítem pieza con precio válido", () => {
    mockLS._store.set(
      CLAVES_STORAGE.jornadas,
      JSON.stringify([{ ...jornadaBase, items: [itemJornada] }])
    );
    expect(leerJornadas()).toHaveLength(1);
  });

  const itemVenta = {
    productoId: 3,
    nombreProducto: "Queso cremoso en pieza",
    unidadMedida: "pieza",
    cantidad: 3,
    precioUnitario: 10000,
    precioMediaPieza: 5000,
    subtotal: 15000,
  };
  const ventaBase = {
    id: "v-1",
    jornadaId: "j-1",
    camionId: 1,
    clienteId: 1,
    nombreCliente: "Cliente",
    fecha: "2026-10-20T10:00:00.000Z",
    medioPago: "efectivo",
    total: 15000,
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

    // Unidad con precio de media en el snapshot: no aplica, se rechaza.
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([
        {
          ...ventaBase,
          total: 4600,
          items: [
            {
              productoId: 1,
              nombreProducto: "Leche",
              unidadMedida: "unidad",
              cantidad: 2,
              precioUnitario: 2300,
              precioMediaPieza: 1150,
              subtotal: 4600,
            },
          ],
        },
      ])
    );
    expect(cargarVentas()).toEqual([]);
  });

  it("ventas: usa la media del snapshot aunque la regla vigente daría otra", () => {
    // Regla vigente para pieza 10000 → media 5000; el snapshot guardó 6000.
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([
        {
          ...ventaBase,
          total: 16000,
          items: [{ ...itemVenta, precioMediaPieza: 6000, subtotal: 16000 }],
        },
      ])
    );
    expect(cargarVentas()).toHaveLength(1);
  });
});

describe("L2A — Frontera de persistencia: useJornadas fail closed en cantidad", () => {
  const jornadaInvalidaBase = {
    id: "j-test",
    camionId: 1,
    chofer: "Chofer",
    zona: "Zona",
    fechaCreacion: "2026-10-20T10:00:00.000Z",
    fechaSalida: null,
    estado: "preparacion",
  };

  const itemValido = {
    productoId: 3,
    nombreProducto: "Queso cremoso en pieza",
    unidadMedida: "pieza",
    cantidad: 3,
    precioReferencia: 10000,
  };

  it("rechaza cantidad no entera (1.5)", () => {
    mockLS._store.set(
      CLAVES_STORAGE.jornadas,
      JSON.stringify([{ ...jornadaInvalidaBase, items: [{ ...itemValido, cantidad: 1.5 }] }])
    );
    expect(leerJornadas()).toEqual([]);
  });

  it("rechaza cantidad NaN", () => {
    mockLS._store.set(
      CLAVES_STORAGE.jornadas,
      JSON.stringify([{ ...jornadaInvalidaBase, items: [{ ...itemValido, cantidad: Number.NaN }] }])
    );
    expect(leerJornadas()).toEqual([]);
  });

  it("rechaza cantidad Infinity", () => {
    mockLS._store.set(
      CLAVES_STORAGE.jornadas,
      JSON.stringify([{ ...jornadaInvalidaBase, items: [{ ...itemValido, cantidad: Number.POSITIVE_INFINITY }] }])
    );
    expect(leerJornadas()).toEqual([]);
  });

  it("rechaza cantidad negativa", () => {
    mockLS._store.set(
      CLAVES_STORAGE.jornadas,
      JSON.stringify([{ ...jornadaInvalidaBase, items: [{ ...itemValido, cantidad: -1 }] }])
    );
    expect(leerJornadas()).toEqual([]);
  });
});

describe("L2B — Frontera de persistencia: useVentas total histórico", () => {
  const itemVenta = {
    productoId: 3,
    nombreProducto: "Queso cremoso en pieza",
    unidadMedida: "pieza",
    cantidad: 3,
    precioUnitario: 10000,
    precioMediaPieza: 5000,
    subtotal: 15000,
  };
  // cantidad=2 (2 medias = 1 pieza) → subtotal = 1 * 12500 = 12500
  const itemVenta2 = {
    productoId: 4,
    nombreProducto: "Jamón cocido",
    unidadMedida: "pieza",
    cantidad: 2,
    precioUnitario: 12500,
    precioMediaPieza: 6250,
    subtotal: 12500,
  };
  const ventaBase = {
    id: "v-test",
    jornadaId: "j-1",
    camionId: 1,
    clienteId: 1,
    nombreCliente: "Cliente Test",
    fecha: "2026-10-20T10:00:00.000Z",
    medioPago: "efectivo",
  };

  it("total histórico coincide con suma de subtotales (enteros)", () => {
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([
        {
          ...ventaBase,
          id: "v-1",
          items: [itemVenta, itemVenta2],
          total: 27500, // 15000 + 12500
        },
      ])
    );
    expect(cargarVentas()).toHaveLength(1);
  });

  it("total histórico .01 menos → inválido", () => {
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([
        {
          ...ventaBase,
          id: "v-1",
          items: [itemVenta, itemVenta2],
          total: 27499.99, // 27500 - 0.01
        },
      ])
    );
    expect(cargarVentas()).toEqual([]);
  });

  it("total histórico .01 más → inválido", () => {
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([
        {
          ...ventaBase,
          id: "v-1",
          items: [itemVenta, itemVenta2],
          total: 27500.01, // 27500 + 0.01
        },
      ])
    );
    expect(cargarVentas()).toEqual([]);
  });

  it("total con 3 decimales → inválido (más de 2 decimales)", () => {
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([
        {
          ...ventaBase,
          id: "v-1",
          items: [itemVenta, itemVenta2],
          total: 27500.001, // más de 2 decimales
        },
      ])
    );
    expect(cargarVentas()).toEqual([]);
  });

  it("total con centavos coincide usando aritmética compartida", () => {
    const itemConCentavos1 = {
      productoId: 1,
      nombreProducto: "Producto 1",
      unidadMedida: "unidad",
      cantidad: 3,
      precioUnitario: 100.5,
      subtotal: 301.5,
    };
    const itemVentaConCentavos2 = {
      productoId: 2,
      nombreProducto: "Producto 2",
      unidadMedida: "unidad",
      cantidad: 2,
      precioUnitario: 50.25,
      subtotal: 100.5,
    };
    const ventaConCentavos = {
      ...ventaBase,
      id: "v-centavos",
      items: [itemConCentavos1, itemVentaConCentavos2],
      total: 402.00, // 301.5 + 100.5
      medioPago: "transferencia",
      jornadaId: "j-1",
      camionId: 1,
      clienteId: 1,
      nombreCliente: "Cliente Test",
      fecha: "2026-10-20T10:00:00.000Z",
    };

    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([ventaConCentavos])
    );
    expect(cargarVentas()).toHaveLength(1);

    // Total .01 menos falla
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([{ ...ventaConCentavos, total: 401.99 }])
    );
    expect(cargarVentas()).toEqual([]);

    // Total .01 más falla
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([{ ...ventaConCentavos, total: 402.01 }])
    );
    expect(cargarVentas()).toEqual([]);

    // Total con 3 decimales falla
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([{ ...ventaConCentavos, total: 402.001 }])
    );
    expect(cargarVentas()).toEqual([]);
  });
});

describe("movimientos: persistencia falla cerrado ante cantidades inválidas", () => {
  const producto = (
    unidadMedida: string,
    cantidad: unknown
  ): Record<string, unknown> => ({
    productoId: 1,
    nombreProducto: "Producto",
    unidadMedida,
    cantidad,
  });

  const mermaGuardada = (p: Record<string, unknown>) => ({
    id: "m1",
    jornadaId: "j1",
    camionId: 1,
    fecha: "2026-10-21T10:00:00.000Z",
    motivo: "Otro motivo",
    tipo: "merma",
    producto: p,
    clienteId: null,
    nombreCliente: null,
  });

  const guardar = (p: Record<string, unknown>) => {
    mockLS._store.set(
      CLAVES_STORAGE.movimientos,
      JSON.stringify([mermaGuardada(p)])
    );
  };

  it("pieza canónica entera y unidad entera son válidas", () => {
    guardar(producto("pieza", 3));
    expect(leerMovimientos()).toHaveLength(1);
    guardar(producto("unidad", 2));
    expect(leerMovimientos()).toHaveLength(1);
  });

  it.each([1.5, 0, -1, "2"])("cantidad %j → lectura inválida (vacío)", (c) => {
    guardar(producto("pieza", c));
    expect(leerMovimientos()).toEqual([]);
    guardar(producto("unidad", c));
    expect(leerMovimientos()).toEqual([]);
  });

  it("NaN e Infinity (serializados como null) → inválido", () => {
    guardar(producto("unidad", NaN));
    expect(leerMovimientos()).toEqual([]);
    guardar(producto("pieza", Infinity));
    expect(leerMovimientos()).toEqual([]);
  });

  it("kg no es una unidad válida", () => {
    guardar(producto("kg", 1));
    expect(leerMovimientos()).toEqual([]);
  });

  it("un solo ítem inválido invalida todo el payload", () => {
    mockLS._store.set(
      CLAVES_STORAGE.movimientos,
      JSON.stringify([
        mermaGuardada(producto("unidad", 2)),
        { ...mermaGuardada(producto("unidad", 1.5)), id: "m2" },
      ])
    );
    expect(leerMovimientos()).toEqual([]);
  });

  describe("registrarMovimientoOperacion", () => {
    const mov = (p: ProductoMovimiento) =>
      mermaGuardada(p as unknown as Record<string, unknown>) as unknown as MovimientoReparto;

    it.each([0, 1.5, NaN, Infinity, -1])(
      "rechaza cantidad %s sin persistir ni llamar a validar",
      (c) => {
        const guardar_fn = vi.fn();
        const validar = vi.fn(() => null);
        const error = registrarMovimientoOperacion(
          mov({ productoId: 1, nombreProducto: "P", unidadMedida: "pieza", cantidad: c }),
          validar,
          () => [],
          guardar_fn
        );
        expect(error).toMatch(/no es válido/);
        expect(validar).not.toHaveBeenCalled();
        expect(guardar_fn).not.toHaveBeenCalled();
      }
    );

    it("persiste un movimiento válido y rechaza duplicados", () => {
      const guardar_fn = vi.fn();
      const m = mov({ productoId: 1, nombreProducto: "P", unidadMedida: "pieza", cantidad: 3 });
      expect(registrarMovimientoOperacion(m, () => null, () => [], guardar_fn)).toBeNull();
      expect(guardar_fn).toHaveBeenCalledWith([m]);
      expect(
        registrarMovimientoOperacion(m, () => null, () => [m], vi.fn())
      ).toMatch(/ya está registrado/);
    });
  });
});
