// Pruebas del versionado de persistencia localStorage del prototipo y de sus
// fronteras de lectura/escritura fail-closed.
//
// Modelo vigente (ADR-005): claves operativas `_demo_v5`, productos `unidad`
// (unidades enteras) o `peso` (gramos enteros). D-R4: reinicio limpio. Las
// claves operativas anteriores (v4 en medias piezas, v3, v2, v1) no se leen,
// copian, migran, reinterpretan ni borran: una cantidad legacy en medias
// piezas nunca aparece como gramos.
// Vitest corre en entorno node: se simula localStorage sobre globalThis.
import { describe, expect, it, beforeEach, afterEach, vi } from "vitest";

import { cargarProductos, leerProductos } from "./useProductos";
import { persistirCatalogo, type ResultadoLectura } from "./catalogoStorage";
import { camionesIniciales } from "../data/mockCamiones";
import { clientesIniciales } from "../data/mockClientes";
import {
  productosIniciales,
  type Producto,
  type UnidadMedida,
} from "../data/mockProductos";
import {
  cerrarJornadaPersistida,
  confirmarSalidaPersistida,
  crearPreparacionPersistida,
  leerJornadas,
  leerJornadasDiscriminado,
  MENSAJE_PREPARACION_INVALIDA,
} from "./useJornadas";
import type { ItemCarga, Jornada } from "../data/mockJornadas";
import {
  cargarVentas,
  registrarVentaOperacion,
  registrarVentaPersistida,
} from "./useVentas";
import type { Venta } from "../data/mockVentas";
import type { Cobro } from "../data/mockCobros";
import {
  leerMovimientos,
  registrarMovimientoOperacion,
  registrarMovimientoPersistido,
} from "./useMovimientos";
import type {
  MovimientoReparto,
  ProductoMovimiento,
} from "../data/mockMovimientos";
import {
  leerRetornos,
  leerRetornosDiscriminado,
  registrarRetornoOperacion,
  registrarRetornoPersistido,
} from "./useRetornos";
import type { RetornoDeposito } from "../data/mockRetornos";
import { cargarCamiones, leerCamiones } from "./useCamiones";
import { cargarClientes, leerClientes } from "./useClientes";
import {
  leerCobros,
  registrarCobroOperacion,
  registrarCobroPersistido,
} from "./useCobros";
import { CLAVE_CLIENTES, CLAVES_STORAGE } from "../data/clavesStorage";
import { cantidad_a_texto, MENSAJE_PESO_NO_OPERABLE } from "../domain/productos";

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

// Lee todos los hooks operativos y de catálogo del demo.
function leerTodo() {
  cargarProductos();
  leerJornadas();
  cargarVentas();
  leerCobros();
  leerMovimientos();
  leerRetornos();
  cargarCamiones();
}

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

const productoV1PiezasEnteras = [
  {
    id: 998,
    nombre: "Jamón legacy piezas enteras",
    categoria: "Fiambres",
    unidadMedida: "pieza",
    stock: 18, // 18 piezas enteras
    precio: 12500,
    stockMinimo: 5,
  },
];

describe("Inicialización v5: sin datos v5 → fixtures nuevos", () => {
  it("productos: sin clave v5 devuelve productosIniciales (unidad | peso)", () => {
    const productos = cargarProductos();
    expect(productos).toEqual(productosIniciales);
    expect(
      productos.every(
        (p) => p.unidadMedida === "unidad" || p.unidadMedida === "peso"
      )
    ).toBe(true);
  });

  it("los fiambres iniciales están en gramos enteros", () => {
    const fiambres = cargarProductos().filter((p) => p.categoria === "Fiambres");
    expect(fiambres.length).toBeGreaterThan(0);
    fiambres.forEach((p) => {
      expect(p.unidadMedida).toBe("peso");
      expect(Number.isSafeInteger(p.stock)).toBe(true);
      expect(Number.isSafeInteger(p.stockMinimo)).toBe(true);
    });
  });

  it("jornadas: sin clave v5 devuelve arreglo vacío", () => {
    expect(leerJornadas()).toEqual([]);
  });

  it("ventas: sin clave v5 devuelve arreglo vacío", () => {
    expect(cargarVentas()).toEqual([]);
  });

  it("movimientos: sin clave v5 devuelve arreglo vacío", () => {
    expect(leerMovimientos()).toEqual([]);
  });

  it("retornos: sin clave v5 devuelve arreglo vacío", () => {
    expect(leerRetornos()).toEqual([]);
  });

  it("camiones: sin clave v5 devuelve camionesIniciales", () => {
    expect(cargarCamiones()).toEqual(camionesIniciales);
  });

  it("clientes (v2, sin cambios): sin clave devuelve clientesIniciales", () => {
    expect(cargarClientes()).toEqual(clientesIniciales);
  });

  it("cobros: sin clave v5 devuelve arreglo vacío", () => {
    expect(leerCobros()).toEqual([]);
  });

  it("inicializar no persiste nada", () => {
    leerTodo();
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });
});

describe("Claves operativas: las siete rotan juntas a v5", () => {
  it("las siete claves son exactamente las del modelo por peso", () => {
    expect(CLAVES_STORAGE).toEqual({
      productos: "distribuidora_productos_demo_v5",
      jornadas: "distribuidora_jornadas_demo_v5",
      ventas: "distribuidora_ventas_demo_v5",
      cobros: "distribuidora_cobros_demo_v5",
      movimientos: "distribuidora_movimientos_demo_v5",
      retornos: "distribuidora_retornos_demo_v5",
      camiones: "distribuidora_camiones_demo_v5",
    });
  });

  it("clientes conserva su clave v2", () => {
    expect(CLAVE_CLIENTES).toBe("distribuidora_clientes_demo_v2");
  });
});

// --- D-R4: claves v4 (modelo pieza/media pieza) ---

const CLAVES_V4_ANTERIORES = {
  productos: "distribuidora_productos_demo_v4",
  jornadas: "distribuidora_jornadas_demo_v4",
  ventas: "distribuidora_ventas_demo_v4",
  cobros: "distribuidora_cobros_demo_v4",
  movimientos: "distribuidora_movimientos_demo_v4",
  retornos: "distribuidora_retornos_demo_v4",
  camiones: "distribuidora_camiones_demo_v4",
} as const;

// Payloads v4 legacy realistas: el 9 significa 9 medias piezas (4 piezas y
// media). Nunca puede aparecer como 9 g ni como 0,009 kg.
const LEGACY_V4: Record<keyof typeof CLAVES_V4_ANTERIORES, string> = {
  productos: JSON.stringify([
    {
      id: 4,
      nombre: "Jamón cocido",
      categoria: "Fiambres",
      unidadMedida: "pieza",
      stock: 9,
      precio: 12500,
      stockMinimo: 9,
    },
  ]),
  jornadas: JSON.stringify([
    {
      id: "j-legacy",
      camionId: 1,
      chofer: "Luis",
      zona: "Norte",
      fechaCreacion: "2026-10-20T08:00:00.000Z",
      fechaSalida: null,
      estado: "preparacion",
      items: [
        {
          productoId: 4,
          nombreProducto: "Jamón cocido",
          unidadMedida: "pieza",
          cantidad: 9,
          precioReferencia: 12500,
        },
      ],
    },
  ]),
  ventas: JSON.stringify([
    {
      id: "v-legacy",
      jornadaId: "j-legacy",
      camionId: 1,
      clienteId: 1,
      nombreCliente: "Cliente",
      fecha: "2026-10-20T10:00:00.000Z",
      medioPago: "efectivo",
      items: [
        {
          productoId: 4,
          nombreProducto: "Jamón cocido",
          unidadMedida: "pieza",
          cantidad: 9,
          precioUnitario: 12500,
          precioMediaPieza: 6250,
          subtotal: 56250,
        },
      ],
      total: 56250,
    },
  ]),
  cobros: JSON.stringify([
    {
      id: "c-legacy",
      clienteId: 1,
      nombreCliente: "Cliente",
      jornadaId: null,
      fecha: "2026-10-20T10:00:00.000Z",
      importe: 9,
      medio: "efectivo",
      referencia: "",
      observaciones: "",
    },
  ]),
  movimientos: JSON.stringify([
    {
      id: "m-legacy",
      jornadaId: "j-legacy",
      camionId: 1,
      fecha: "2026-10-20T10:00:00.000Z",
      motivo: "Otro",
      tipo: "merma",
      producto: {
        productoId: 4,
        nombreProducto: "Jamón cocido",
        unidadMedida: "pieza",
        cantidad: 9,
      },
      clienteId: null,
      nombreCliente: null,
    },
  ]),
  retornos: JSON.stringify([
    {
      id: "r-legacy",
      jornadaId: "j-legacy",
      camionId: 1,
      fecha: "2026-10-20T18:00:00.000Z",
      responsable: "Ana",
      observaciones: "",
      items: [
        {
          productoId: 4,
          nombreProducto: "Jamón cocido",
          unidadMedida: "pieza",
          cantidadContada: 9,
          cantidadAprobada: 9,
        },
      ],
    },
  ]),
  camiones: JSON.stringify([{ id: 9, nombre: "Camión legacy" }]),
};

function sembrarV4() {
  for (const [nombre, clave] of Object.entries(CLAVES_V4_ANTERIORES)) {
    mockLS._store.set(clave, LEGACY_V4[nombre as keyof typeof LEGACY_V4]);
  }
}

describe("D-R4: las claves v4 (medias piezas) no se leen, copian, migran ni borran", () => {
  it("las siete claves vigentes difieren de las v4", () => {
    for (const [nombre, clave] of Object.entries(CLAVES_STORAGE)) {
      expect(clave).not.toBe(
        CLAVES_V4_ANTERIORES[nombre as keyof typeof CLAVES_V4_ANTERIORES]
      );
    }
  });

  it("con v4 presente y sin v5, cada hook arranca limpio con los fixtures nuevos", () => {
    sembrarV4();

    expect(cargarProductos()).toEqual(productosIniciales);
    expect(leerJornadas()).toEqual([]);
    expect(cargarVentas()).toEqual([]);
    expect(leerCobros()).toEqual([]);
    expect(leerMovimientos()).toEqual([]);
    expect(leerRetornos()).toEqual([]);
    expect(cargarCamiones()).toEqual(camionesIniciales);
  });

  it("v4 no se lee: ningún getItem apunta a una clave v4", () => {
    sembrarV4();
    leerTodo();

    for (const clave of Object.values(CLAVES_V4_ANTERIORES)) {
      expect(mockLS.getItem).not.toHaveBeenCalledWith(clave);
    }
    expect(mockLS.key).not.toHaveBeenCalled();
  });

  it("v4 no se copia ni se migra: no se escribe ninguna clave v5", () => {
    sembrarV4();
    leerTodo();

    expect(mockLS.setItem).not.toHaveBeenCalled();
    for (const clave of Object.values(CLAVES_STORAGE)) {
      expect(mockLS._store.has(clave)).toBe(false);
    }
  });

  it("v4 no se borra: queda byte a byte intacta", () => {
    sembrarV4();
    leerTodo();

    expect(mockLS.removeItem).not.toHaveBeenCalled();
    expect(mockLS.clear).not.toHaveBeenCalled();
    for (const [nombre, clave] of Object.entries(CLAVES_V4_ANTERIORES)) {
      expect(mockLS._store.get(clave)).toBe(
        LEGACY_V4[nombre as keyof typeof LEGACY_V4]
      );
    }
  });

  it("el 9 legacy (4 piezas y media) nunca aparece como 9 g ni 0,009 kg", () => {
    sembrarV4();

    const productos = cargarProductos();
    const jamon = productos.find((p) => p.id === 4);
    expect(jamon).toMatchObject({ unidadMedida: "peso", stock: 18000, stockMinimo: 5000 });
    expect(productos.some((p) => p.unidadMedida === "peso" && p.stock === 9)).toBe(false);
    expect(productos.some((p) => p.stockMinimo === 9)).toBe(false);
    expect(
      productos
        .filter((p) => p.unidadMedida === "peso")
        .map((p) => cantidad_a_texto("peso", p.stock))
    ).not.toContain("0,009 kg");

    expect(leerJornadas()).toEqual([]);
    expect(leerMovimientos()).toEqual([]);
    expect(leerRetornos()).toEqual([]);
  });
});

describe("Payload v5 con datos del modelo anterior: falla cerrado", () => {
  it("un producto v5 con 'pieza' invalida el payload (fixtures, sin persistir)", () => {
    const crudo = JSON.stringify([
      {
        id: 4,
        nombre: "Jamón cocido",
        categoria: "Fiambres",
        unidadMedida: "pieza",
        stock: 9,
        precio: 12500,
        stockMinimo: 9,
      },
    ]);
    mockLS._store.set(CLAVES_STORAGE.productos, crudo);

    expect(leerProductos().ok).toBe(false);
    expect(cargarProductos()).toEqual(productosIniciales);
    expect(mockLS._store.get(CLAVES_STORAGE.productos)).toBe(crudo);
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });

  it("{ unidadMedida: 'pieza', cantidad: 9 } en v5 nunca se carga como { peso, 9 }", () => {
    const jornada = JSON.parse(LEGACY_V4.jornadas) as unknown[];
    mockLS._store.set(CLAVES_STORAGE.jornadas, JSON.stringify(jornada));

    const lectura = leerJornadasDiscriminado();
    expect(lectura.ok).toBe(false);
    expect(leerJornadas()).toEqual([]);
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });

  it("un movimiento y un retorno v5 con 'pieza' invalidan su payload", () => {
    mockLS._store.set(CLAVES_STORAGE.movimientos, LEGACY_V4.movimientos);
    mockLS._store.set(CLAVES_STORAGE.retornos, LEGACY_V4.retornos);
    mockLS._store.set(CLAVES_STORAGE.ventas, LEGACY_V4.ventas);

    expect(leerMovimientos()).toEqual([]);
    expect(leerRetornos()).toEqual([]);
    expect(cargarVentas()).toEqual([]);
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });
});

describe("Payload v5 válido con peso en gramos enteros", () => {
  it("productos: Fiambres + peso en gramos se acepta", () => {
    const datos: Producto[] = [
      {
        id: 4,
        nombre: "Jamón cocido",
        categoria: "Fiambres",
        unidadMedida: "peso",
        stock: 28680,
        precio: 12500,
        stockMinimo: 5000,
      },
    ];
    mockLS._store.set(CLAVES_STORAGE.productos, JSON.stringify(datos));
    expect(cargarProductos()).toEqual(datos);
  });

  it("productos: gramos fraccionarios invalidan el payload", () => {
    mockLS._store.set(
      CLAVES_STORAGE.productos,
      JSON.stringify([
        {
          id: 4,
          nombre: "Jamón cocido",
          categoria: "Fiambres",
          unidadMedida: "peso",
          stock: 1250.5,
          precio: 12500,
          stockMinimo: 0,
        },
      ])
    );
    expect(cargarProductos()).toEqual(productosIniciales);
  });

  it("jornadas, movimientos y retornos: peso en gramos es estructuralmente válido", () => {
    const jornada = {
      id: "j-peso",
      camionId: 1,
      chofer: "Luis",
      zona: "Norte",
      fechaCreacion: "2026-10-27T08:00:00.000Z",
      fechaSalida: null,
      estado: "preparacion",
      items: [
        {
          productoId: 4,
          nombreProducto: "Jamón cocido",
          unidadMedida: "peso",
          cantidad: 18000,
          precioReferencia: 12500,
        },
      ],
    };
    const movimiento = {
      id: "m-peso",
      jornadaId: "j-peso",
      camionId: 1,
      fecha: "2026-10-27T10:00:00.000Z",
      motivo: "Otro",
      tipo: "merma",
      producto: {
        productoId: 4,
        nombreProducto: "Jamón cocido",
        unidadMedida: "peso",
        cantidad: 1250,
      },
      clienteId: null,
      nombreCliente: null,
    };
    const retorno = {
      id: "r-peso",
      jornadaId: "j-peso",
      camionId: 1,
      fecha: "2026-10-27T18:00:00.000Z",
      responsable: "Ana",
      observaciones: "",
      items: [
        {
          productoId: 4,
          nombreProducto: "Jamón cocido",
          unidadMedida: "peso",
          cantidadContada: 16750,
          cantidadAprobada: 16750,
        },
      ],
    };
    mockLS._store.set(CLAVES_STORAGE.jornadas, JSON.stringify([jornada]));
    mockLS._store.set(CLAVES_STORAGE.movimientos, JSON.stringify([movimiento]));
    mockLS._store.set(CLAVES_STORAGE.retornos, JSON.stringify([retorno]));

    expect(leerJornadas()).toEqual([jornada]);
    expect(leerMovimientos()).toEqual([movimiento]);
    expect(leerRetornos()).toEqual([retorno]);
  });
});

describe("v1 NO se migra: datos v1 incompatibles no se leen como v5", () => {
  it("productos: clave v1 con 'kg' no contamina v5", () => {
    mockLS._store.set(
      "distribuidora_productos_demo_v1",
      JSON.stringify(productoV1ConKg)
    );

    const productos = cargarProductos();

    expect(productos).toEqual(productosIniciales);
    expect(productos.some((p) => p.id === 999)).toBe(false);
  });

  it("productos: clave v1 con piezas enteras no se reinterpreta", () => {
    mockLS._store.set(
      "distribuidora_productos_demo_v1",
      JSON.stringify(productoV1PiezasEnteras)
    );

    const productos = cargarProductos();

    // Jamón cocido v5 usa el fixture nuevo en gramos: ni 18 ni 36.
    const jamon = productos.find((p) => p.nombre === "Jamón cocido");
    expect(jamon?.stock).toBe(18000);
    expect(productos.some((p) => p.id === 998)).toBe(false);
  });
});

describe("v1 NO se elimina: la clave v1 sigue intacta tras inicializar v5", () => {
  it("productos: la clave v1 permanece después de leer v5", () => {
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

describe("v5 ya existe: se respeta y no se reinicializa", () => {
  it("productos: si existe clave v5, se usa ese dato y no productosIniciales", () => {
    const datosV5: Producto[] = [
      {
        id: 777,
        nombre: "Producto ya guardado en v5",
        categoria: "Lácteos",
        unidadMedida: "unidad",
        stock: 5,
        precio: 500,
        stockMinimo: 1,
      },
    ];

    mockLS._store.set(
      CLAVES_STORAGE.productos,
      JSON.stringify(datosV5)
    );

    const productos = cargarProductos();

    expect(productos).toEqual(datosV5);
    expect(productos[0].id).toBe(777);
    expect(productos).toHaveLength(1);
  });
});

describe("Frontera de persistencia: combinación categoría ↔ forma de venta", () => {
  const producto = (categoria: string, unidadMedida: string) => ({
    id: 9001,
    nombre: `Producto ${categoria} + ${unidadMedida}`,
    categoria,
    unidadMedida,
    stock: 4,
    precio: 1000,
    stockMinimo: 1,
  });

  it.each([
    ["Lácteos", "pieza"],
    ["Lácteos", "peso"],
    ["Fiambres", "unidad"],
    ["Fiambres", "pieza"],
    ["Fiambres", "media_pieza"],
    ["Fiambres", "kg"],
  ])("%s + %s en v5 invalida el payload", (categoria, unidad) => {
    mockLS._store.set(
      CLAVES_STORAGE.productos,
      JSON.stringify([producto(categoria, unidad)])
    );
    // Semántica vigente del hook: un elemento inválido rechaza todo el
    // payload y se arranca desde los fixtures. Nada se corrige.
    expect(cargarProductos()).toEqual(productosIniciales);
  });

  it.each([
    ["Lácteos", "unidad"],
    ["Fiambres", "peso"],
  ])("%s + %s en v5 se acepta", (categoria, unidad) => {
    const datos = [producto(categoria, unidad)];
    mockLS._store.set(CLAVES_STORAGE.productos, JSON.stringify(datos));
    expect(cargarProductos()).toEqual(datos);
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

// Claves v3 de ADR-002 (histórica). Solo existen en esta prueba, para
// demostrar que los hooks no las leen, copian ni borran.
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

  it("con datos v3 presentes y sin v5, cada hook arranca limpio y v3 queda intacta", () => {
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
    // Nada se copió a v5.
    for (const clave of Object.values(CLAVES_STORAGE)) {
      expect(mockLS.setItem).not.toHaveBeenCalledWith(clave, expect.anything());
    }
  });
});

describe("v2 NO se lee, copia ni borra", () => {
  it("las siete claves compartidas difieren de v2", () => {
    for (const [nombre, clave] of Object.entries(CLAVES_STORAGE)) {
      expect(clave).not.toBe(
        CLAVES_V2_ANTERIORES[nombre as keyof typeof CLAVES_V2_ANTERIORES]
      );
    }
  });

  it("con datos v2 presentes y sin v5, cada hook arranca limpio", () => {
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

  it("las claves v2 quedan intactas tras inicializar v5", () => {
    for (const clave of Object.values(CLAVES_V2_ANTERIORES)) {
      mockLS._store.set(clave, JSON.stringify([{ id: 1, dato: "v2" }]));
    }

    leerTodo();

    for (const clave of Object.values(CLAVES_V2_ANTERIORES)) {
      expect(mockLS.getItem(clave)).toBe(
        JSON.stringify([{ id: 1, dato: "v2" }])
      );
    }
    // Nada se copió a v5.
    for (const clave of Object.values(CLAVES_STORAGE)) {
      expect(mockLS.setItem).not.toHaveBeenCalledWith(clave, expect.anything());
    }
  });

  it("clientes conserva su clave v2", () => {
    mockLS._store.set(CLAVE_CLIENTES, JSON.stringify([{ id: 1 }]));
    cargarClientes();
    expect(mockLS.getItem(CLAVE_CLIENTES)).toBe(JSON.stringify([{ id: 1 }]));
  });
});

describe("Frontera de persistencia: precios y snapshot de ventas (B1)", () => {
  // Precio por kg del fiambre (ADR-005); precio unitario del lácteo.
  const fiambre = {
    id: 9100,
    nombre: "Fiambre de prueba",
    categoria: "Fiambres",
    unidadMedida: "peso",
    stock: 8000,
    precio: 10000,
    stockMinimo: 2000,
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

  it("acepta fiambre (precio por kg) y lácteo (precio unitario) con precios válidos", () => {
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
    productoId: 1,
    nombreProducto: "Leche",
    unidadMedida: "unidad",
    cantidad: 3,
    precioReferencia: 2300,
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

  it("jornadas: acepta ítem unidad con precio válido", () => {
    mockLS._store.set(
      CLAVES_STORAGE.jornadas,
      JSON.stringify([{ ...jornadaBase, items: [itemJornada] }])
    );
    expect(leerJornadas()).toHaveLength(1);
  });

  it("jornadas: rechaza ítem con precio inválido", () => {
    mockLS._store.set(
      CLAVES_STORAGE.jornadas,
      JSON.stringify([{ ...jornadaBase, items: [{ ...itemJornada, precioReferencia: -1 }] }])
    );
    expect(leerJornadas()).toEqual([]);
  });

  const itemVenta = {
    productoId: 1,
    nombreProducto: "Leche",
    unidadMedida: "unidad",
    cantidad: 3,
    precioUnitario: 2300,
    subtotal: 6900,
  };
  const ventaBase = {
    id: "v-1",
    jornadaId: "j-1",
    camionId: 1,
    clienteId: 1,
    nombreCliente: "Cliente",
    fecha: "2026-10-20T10:00:00.000Z",
    medioPago: "efectivo",
    total: 6900,
  };

  it("ventas: conserva el precio aplicado y exige subtotal consistente", () => {
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([{ ...ventaBase, items: [itemVenta] }])
    );
    expect(cargarVentas()).toHaveLength(1);

    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([{ ...ventaBase, items: [{ ...itemVenta, subtotal: 6901 }], total: 6901 }])
    );
    expect(cargarVentas()).toEqual([]);
  });

  it("ventas: una línea unidad con precioMediaPieza (legacy ADR-003) se rechaza", () => {
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([
        { ...ventaBase, items: [{ ...itemVenta, precioMediaPieza: 1150 }] },
      ])
    );
    expect(cargarVentas()).toEqual([]);
  });

  it("ventas: una línea peso se rechaza hasta B3 (subtotal arbitrario, sin D-R1)", () => {
    mockLS._store.set(
      CLAVES_STORAGE.ventas,
      JSON.stringify([
        {
          ...ventaBase,
          total: 123,
          items: [
            {
              productoId: 4,
              nombreProducto: "Jamón cocido",
              unidadMedida: "peso",
              cantidad: 1250,
              precioUnitario: 12500,
              subtotal: 123,
            },
          ],
        },
      ])
    );
    expect(cargarVentas()).toEqual([]);
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
    productoId: 1,
    nombreProducto: "Leche",
    unidadMedida: "unidad",
    cantidad: 3,
    precioReferencia: 2300,
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
  // Líneas unidad: subtotal = cantidad × precio unitario (comportamiento
  // vigente; no resuelve el pendiente de líneas unidad de BLUEPRINT §15).
  const itemVenta = {
    productoId: 1,
    nombreProducto: "Leche",
    unidadMedida: "unidad",
    cantidad: 3,
    precioUnitario: 5000,
    subtotal: 15000,
  };
  const itemVenta2 = {
    productoId: 2,
    nombreProducto: "Yogur",
    unidadMedida: "unidad",
    cantidad: 2,
    precioUnitario: 6250,
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

  it("unidad entera y peso en gramos enteros son válidos (storage v5)", () => {
    guardar(producto("unidad", 2));
    expect(leerMovimientos()).toHaveLength(1);
    guardar(producto("peso", 1250));
    expect(leerMovimientos()).toHaveLength(1);
  });

  it.each([1.5, 0, -1, "2"])("cantidad %j → lectura inválida (vacío)", (c) => {
    guardar(producto("peso", c));
    expect(leerMovimientos()).toEqual([]);
    guardar(producto("unidad", c));
    expect(leerMovimientos()).toEqual([]);
  });

  it("NaN e Infinity (serializados como null) → inválido", () => {
    guardar(producto("unidad", NaN));
    expect(leerMovimientos()).toEqual([]);
    guardar(producto("peso", Infinity));
    expect(leerMovimientos()).toEqual([]);
  });

  it.each(["kg", "pieza", "media_pieza"])("'%s' no es una unidad válida", (unidad) => {
    guardar(producto(unidad, 1));
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
      "rechaza cantidad %s sin leer ni llamar a validar",
      (c) => {
        const cargar = vi.fn(() => ({ ok: true as const, movimientos: [], estado: 'inicial' as const }));
        const validar = vi.fn(() => null);
        const resultado = registrarMovimientoOperacion(
          mov({ productoId: 1, nombreProducto: "P", unidadMedida: "unidad", cantidad: c }),
          validar,
          cargar
        );
        expect(resultado).toEqual({
          ok: false,
          error: "El movimiento no es válido: las cantidades deben ser enteros positivos y seguros.",
        });
        expect(cargar).not.toHaveBeenCalled();
        expect(validar).not.toHaveBeenCalled();
      }
    );

    it("devuelve el ledger con un movimiento válido y rechaza duplicados", () => {
      const m = mov({ productoId: 1, nombreProducto: "P", unidadMedida: "unidad", cantidad: 3 });
      expect(
        registrarMovimientoOperacion(m, () => null, () => ({ ok: true, movimientos: [], estado: 'inicial' }))
      ).toEqual({ ok: true, movimientos: [m] });
      expect(
        registrarMovimientoOperacion(m, () => null, () => ({ ok: true, movimientos: [m], estado: 'valido' }))
      ).toEqual({ ok: false, error: "Este movimiento ya está registrado." });
    });
  });
});

describe("movimientos: frontera REAL de escritura ante storage corrupto", () => {
  const CLAVE = CLAVES_STORAGE.movimientos;

  type MermaDePrueba = Extract<MovimientoReparto, { tipo: "merma" }>;

  const nuevo = (id: string, cantidad = 3): MermaDePrueba => ({
    id,
    jornadaId: "j1",
    camionId: 1,
    fecha: "2026-10-21T10:00:00.000Z",
    motivo: "Otro motivo",
    tipo: "merma",
    producto: {
      productoId: 1,
      nombreProducto: "Leche",
      unidadMedida: "unidad",
      cantidad,
    },
    clienteId: null,
    nombreCliente: null,
  });

  // Jornada abierta j1 (camión 1, 100 u de Leche) contra la que la frontera
  // valida siempre: se siembra en storage y se pasa como snapshot del render.
  const jornadaJ1: Jornada = {
    id: "j1",
    camionId: 1,
    chofer: "Luis",
    zona: "Norte",
    fechaCreacion: "2026-10-21T08:00:00.000Z",
    fechaSalida: "2026-10-21T09:00:00.000Z",
    estado: "abierta",
    items: [
      { productoId: 1, nombreProducto: "Leche", unidadMedida: "unidad", cantidad: 100, precioReferencia: 100 },
    ],
  };

  beforeEach(() => {
    mockLS._store.set(CLAVES_STORAGE.jornadas, JSON.stringify([jornadaJ1]));
  });

  // Registra contra el localStorage simulado y devuelve lo observado.
  const intentar = (movimiento: MovimientoReparto) => {
    const antes = mockLS.getItem(CLAVE);
    mockLS.setItem.mockClear();
    const resultado = registrarMovimientoPersistido(movimiento, jornadaJ1);
    const error = resultado.ok ? null : resultado.error;
    return { error, antes };
  };

  const quedaIntacto = (antes: string | null) => {
    expect(mockLS.getItem(CLAVE)).toBe(antes);
    expect(mockLS.setItem).not.toHaveBeenCalled();
  };

  it("A. storage ausente: ledger vacío válido, se registra y se persiste", () => {
    expect(mockLS.getItem(CLAVE)).toBeNull();
    const m = nuevo("a1");
    const { error } = intentar(m);
    expect(error).toBeNull();
    expect(mockLS.setItem).toHaveBeenCalledTimes(1);
    expect(JSON.parse(mockLS.getItem(CLAVE) as string)).toEqual([m]);
  });

  it.each([
    ["B. JSON inválido", "{no es json"],
    ["C. JSON válido pero no array", JSON.stringify({ movimientos: [] })],
    ["C. JSON válido: null", "null"],
    [
      "D. array con un movimiento inválido",
      JSON.stringify([{ id: "x", tipo: "merma" }]),
    ],
    [
      "D. array con cantidad decimal",
      JSON.stringify([{ ...nuevo("d1"), producto: { ...nuevo("d1").producto, cantidad: 1.5 } }]),
    ],
  ])("%s: error, sin guardar y contenido intacto", (_n, crudo) => {
    mockLS._store.set(CLAVE, crudo);
    const { error, antes } = intentar(nuevo("n1"));
    expect(error).toMatch(/No se puede registrar/);
    expect(antes).toBe(crudo);
    quedaIntacto(crudo);
  });

  it("E. historial válido + registro corrupto: no se reinterpreta como [] ni se guarda solo el nuevo", () => {
    const crudo = JSON.stringify([
      nuevo("h1"),
      nuevo("h2"),
      { ...nuevo("h3"), producto: { ...nuevo("h3").producto, cantidad: -4 } },
    ]);
    mockLS._store.set(CLAVE, crudo);
    const { error } = intentar(nuevo("e1"));
    expect(error).toMatch(/No se puede registrar/);
    quedaIntacto(crudo);
    // La lectura de UI sigue siendo fail-closed (vacía) pero sin escribir.
    expect(leerMovimientos()).toEqual([]);
    quedaIntacto(crudo);
  });

  it("historial válido: agrega al final conservando lo previo", () => {
    const previo = nuevo("p1");
    mockLS._store.set(CLAVE, JSON.stringify([previo]));
    const m = nuevo("p2");
    expect(intentar(m).error).toBeNull();
    expect(JSON.parse(mockLS.getItem(CLAVE) as string)).toEqual([previo, m]);
  });

  it("movimiento inválido con storage corrupto: rechaza sin tocar el storage", () => {
    mockLS._store.set(CLAVE, "{roto");
    const { error, antes } = intentar(nuevo("i1", 1.5));
    expect(error).toMatch(/no es válido/);
    quedaIntacto(antes);
  });
});

describe("productos: stock y stockMinimo son enteros seguros (frontera de lectura)", () => {
  const producto = (stock: number, stockMinimo: number): Producto => ({
    ...productosIniciales[0],
    stock,
    stockMinimo,
  });

  const cargarCon = (p: Producto) => {
    mockLS._store.set(CLAVES_STORAGE.productos, JSON.stringify([p]));
    return cargarProductos();
  };

  it("MAX_SAFE_INTEGER es válido", () => {
    const p = producto(Number.MAX_SAFE_INTEGER, Number.MAX_SAFE_INTEGER);
    expect(cargarCon(p)).toEqual([p]);
  });

  it("stock > MAX_SAFE_INTEGER invalida el payload", () => {
    expect(cargarCon(producto(Number.MAX_SAFE_INTEGER + 1, 1))).toEqual(
      productosIniciales
    );
  });

  it("stockMinimo > MAX_SAFE_INTEGER invalida el payload", () => {
    expect(cargarCon(producto(1, Number.MAX_SAFE_INTEGER + 1))).toEqual(
      productosIniciales
    );
  });

  it("decimales y negativos invalidan el payload", () => {
    expect(cargarCon(producto(1.5, 1))).toEqual(productosIniciales);
    expect(cargarCon(producto(1, 0.5))).toEqual(productosIniciales);
    expect(cargarCon(producto(-1, 1))).toEqual(productosIniciales);
  });
});

describe("retornos: frontera REAL de escritura", () => {
  const CLAVE = CLAVES_STORAGE.retornos;

  const item = (
    unidadMedida: string,
    contada: unknown,
    aprobada: unknown,
    productoId = 1
  ) => ({
    productoId,
    nombreProducto: "Jamón",
    unidadMedida,
    cantidadContada: contada,
    cantidadAprobada: aprobada,
  });

  const retorno = (
    jornadaId: string,
    items: unknown[] = [item("unidad", 5, 3)]
  ) =>
    ({
      id: `r-${jornadaId}`,
      jornadaId,
      camionId: 1,
      fecha: "2026-10-21T10:00:00.000Z",
      responsable: "Ana",
      observaciones: "",
      items,
    }) as unknown as RetornoDeposito;

  const intentar = (r: RetornoDeposito) => {
    const guardar = vi.fn();
    const antes = mockLS.getItem(CLAVE);
    mockLS.setItem.mockClear();
    const error = registrarRetornoPersistido(r, guardar);
    return { error, guardar, antes };
  };

  const intacto = (antes: string | null) => {
    expect(mockLS.getItem(CLAVE)).toBe(antes);
    expect(mockLS.setItem).not.toHaveBeenCalled();
  };

  it("lectura discriminada: distingue ausencia, válido y corrupto sin escribir", () => {
    expect(leerRetornosDiscriminado()).toEqual({
      ok: true,
      retornos: [],
      estado: "inicial",
    });

    const valido = [retorno("j1")];
    mockLS._store.set(CLAVE, JSON.stringify(valido));
    expect(leerRetornosDiscriminado()).toEqual({
      ok: true,
      retornos: valido,
      estado: "valido",
    });

    mockLS._store.set(CLAVE, "null");
    const lecturaCorrupta = leerRetornosDiscriminado();
    expect(lecturaCorrupta.ok).toBe(false);
    expect(lecturaCorrupta.estado).toBe("corrupto");
    expect(mockLS.getItem(CLAVE)).toBe("null");
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS.removeItem).not.toHaveBeenCalled();
  });

  it("A. storage ausente: se registra y se persiste", () => {
    expect(mockLS.getItem(CLAVE)).toBeNull();
    const r = retorno("j1");
    const { error, guardar } = intentar(r);
    expect(error).toBeNull();
    expect(guardar).toHaveBeenCalledWith([r]);
    expect(JSON.parse(mockLS.getItem(CLAVE) as string)).toEqual([r]);
  });

  it.each([
    ["B. JSON inválido", "{no es json"],
    ["B. cadena vacía", ""],
    ["C. no array", JSON.stringify({ retornos: [] })],
    ["C. null", "null"],
    ["D. array con retorno inválido", JSON.stringify([{ id: "x" }])],
    [
      "D. array con aprobado > contado",
      JSON.stringify([retorno("j0", [item("unidad", 1, 2)])]),
    ],
  ])("%s: aborta, no guarda y el string crudo queda idéntico", (_n, crudo) => {
    mockLS._store.set(CLAVE, crudo);
    const { error, guardar, antes } = intentar(retorno("j1"));
    expect(error).toMatch(/No se puede registrar/);
    expect(guardar).not.toHaveBeenCalled();
    expect(antes).toBe(crudo);
    intacto(crudo);
    // La lectura de UI sigue siendo vacía pero no escribe.
    expect(leerRetornos()).toEqual([]);
    intacto(crudo);
  });

  it("E. jornada duplicada contra el storage actual: rechaza y no guarda", () => {
    const crudo = JSON.stringify([retorno("j1")]);
    mockLS._store.set(CLAVE, crudo);
    const { error, guardar } = intentar({ ...retorno("j1"), id: "otro" });
    expect(error).toMatch(/ya tiene un retorno/);
    expect(guardar).not.toHaveBeenCalled();
    intacto(crudo);
  });

  it.each([
    ["decimal", item("unidad", 5, 1.5)],
    ["NaN", item("unidad", 5, NaN)],
    ["Infinity", item("unidad", Infinity, 0)],
    ["negativo", item("unidad", 5, -1)],
    ["aprobado > contado", item("unidad", 5, 6)],
    ["kg", item("kg", 5, 1)],
    ["no seguro", item("unidad", Number.MAX_SAFE_INTEGER + 1, 0)],
  ])("F. %s: rechaza sin tocar el storage", (_n, it_) => {
    mockLS._store.set(CLAVE, JSON.stringify([retorno("j0")]));
    const { error, guardar, antes } = intentar(retorno("j1", [it_]));
    expect(error).toMatch(/no es válido/);
    expect(guardar).not.toHaveBeenCalled();
    intacto(antes);
  });

  it("F. productos duplicados y responsable vacío se rechazan", () => {
    const dup = intentar(
      retorno("j1", [item("unidad", 5, 1), item("unidad", 5, 1)])
    );
    expect(dup.error).toMatch(/no es válido/);
    const sinResp = intentar({ ...retorno("j2"), responsable: " " });
    expect(sinResp.error).toMatch(/no es válido/);
    expect(mockLS.getItem(CLAVE)).toBeNull();
  });

  it("G. historial válido + nuevo válido: conserva y agrega al final", () => {
    const previo = retorno("j0", [item("unidad", 5, 5)]);
    mockLS._store.set(CLAVE, JSON.stringify([previo]));
    const nuevo = retorno("j1");
    expect(intentar(nuevo).error).toBeNull();
    expect(JSON.parse(mockLS.getItem(CLAVE) as string)).toEqual([previo, nuevo]);
  });

  it("registrarRetornoOperacion: retorno inválido no lee ni guarda ni valida", () => {
    const cargar = vi.fn();
    const guardar = vi.fn();
    const validar = vi.fn(() => null);
    const error = registrarRetornoOperacion(
      retorno("j1", [item("unidad", 5, 1.5)]),
      validar,
      cargar,
      guardar
    );
    expect(error).toMatch(/no es válido/);
    expect(cargar).not.toHaveBeenCalled();
    expect(validar).not.toHaveBeenCalled();
    expect(guardar).not.toHaveBeenCalled();
  });

  it("lectura: kg, pieza y decimales invalidan el payload; peso en gramos es válido", () => {
    mockLS._store.set(CLAVE, JSON.stringify([retorno("j1", [item("kg", 5, 1)])]));
    expect(leerRetornos()).toEqual([]);
    mockLS._store.set(CLAVE, JSON.stringify([retorno("j1", [item("unidad", 5, 2.5)])]));
    expect(leerRetornos()).toEqual([]);
    mockLS._store.set(CLAVE, JSON.stringify([retorno("j1", [item("pieza", 5, 3)])]));
    expect(leerRetornos()).toEqual([]);
    mockLS._store.set(CLAVE, JSON.stringify([retorno("j1", [item("peso", 1250, 1250.5)])]));
    expect(leerRetornos()).toEqual([]);
    const valido = [retorno("j1", [item("unidad", 5, 3), item("peso", 18000, 17500, 4)])];
    mockLS._store.set(CLAVE, JSON.stringify(valido));
    expect(leerRetornos()).toEqual(valido);
  });
});

describe("jornadas: conteos del cierre son enteros seguros", () => {
  const CLAVE = CLAVES_STORAGE.jornadas;
  const MAX = Number.MAX_SAFE_INTEGER;

  const jornada = (estado: string, cierre?: unknown) => ({
    id: "j1",
    camionId: 1,
    chofer: "Luis",
    zona: "Norte",
    fechaCreacion: "2026-10-21T08:00:00.000Z",
    fechaSalida: "2026-10-21T09:00:00.000Z",
    estado,
    items: [
      { productoId: 1, nombreProducto: "Yogur", unidadMedida: "unidad", cantidad: 10, precioReferencia: 100 },
      { productoId: 2, nombreProducto: "Leche", unidadMedida: "unidad", cantidad: 5, precioReferencia: 1000 },
    ],
    ...(cierre === undefined ? {} : { cierre }),
  });

  const cierre = (conteos: Record<string, unknown>) => ({
    fecha: "2026-10-21T18:00:00.000Z",
    conteos,
    efectivoEntregado: 0,
    efectivoEsperado: 0,
    transferenciasInformadas: 0,
    ventasCuentaCorriente: 0,
    observaciones: "",
  });

  const abierta = () => {
    const crudo = JSON.stringify([jornada("abierta")]);
    mockLS._store.set(CLAVE, crudo);
    return crudo;
  };

  it("válidos (unidades enteras): cierra y persiste", () => {
    abierta();
    const r = cerrarJornadaPersistida("j1", cierre({ "1": 3, "2": 5 }) as never);
    expect(r).not.toBeNull();
    expect(leerJornadas()[0].estado).toBe("cerrada");
    expect(leerJornadas()[0].cierre?.conteos).toEqual({ "1": 3, "2": 5 });
  });

  it("MAX_SAFE_INTEGER es un conteo válido", () => {
    abierta();
    expect(cerrarJornadaPersistida("j1", cierre({ "1": MAX, "2": 0 }) as never)).not.toBeNull();
  });

  it.each([1.5, NaN, Infinity, -1, MAX + 1, "3"])(
    "conteo %j: rechaza sin escribir (string crudo idéntico)",
    (invalido) => {
      const crudo = abierta();
      mockLS.setItem.mockClear();
      expect(cerrarJornadaPersistida("j1", cierre({ "1": invalido, "2": 1 }) as never)).toBeNull();
      expect(cerrarJornadaPersistida("j1", cierre({ "1": 1, "2": invalido }) as never)).toBeNull();
      expect(mockLS.getItem(CLAVE)).toBe(crudo);
      expect(mockLS.setItem).not.toHaveBeenCalled();
    }
  );

  it("exige un conteo por cada producto cargado", () => {
    const crudo = abierta();
    expect(cerrarJornadaPersistida("j1", cierre({ "1": 3 }) as never)).toBeNull();
    expect(mockLS.getItem(CLAVE)).toBe(crudo);
  });

  it("lectura: una jornada cerrada con conteo inválido invalida el payload", () => {
    for (const invalido of [1.5, MAX + 1, -1]) {
      mockLS._store.set(CLAVE, JSON.stringify([jornada("cerrada", cierre({ "1": invalido, "2": 1 }))]));
      expect(leerJornadas()).toEqual([]);
    }
    mockLS._store.set(CLAVE, JSON.stringify([jornada("cerrada", cierre({ "1": 3, "2": 5 }))]));
    expect(leerJornadas()).toHaveLength(1);
  });

  it("lectura: cantidad de ítem de carga fuera del rango seguro invalida el payload", () => {
    const j = jornada("abierta");
    j.items[0].cantidad = MAX + 1;
    mockLS._store.set(CLAVE, JSON.stringify([j]));
    expect(leerJornadas()).toEqual([]);
  });

  it("storage corrupto: cerrar no escribe ni sobrescribe", () => {
    mockLS._store.set(CLAVE, "{roto");
    mockLS.setItem.mockClear();
    expect(cerrarJornadaPersistida("j1", cierre({ "1": 1, "2": 1 }) as never)).toBeNull();
    expect(mockLS.getItem(CLAVE)).toBe("{roto");
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });
});

describe("jornadas: escrituras fail-closed ante storage corrupto", () => {
  const CLAVE = CLAVES_STORAGE.jornadas;

  const jornada = (
    id: string,
    camionId: number,
    estado: Jornada["estado"] = "preparacion"
  ): Jornada => ({
    id,
    camionId,
    chofer: "Luis",
    zona: "Norte",
    fechaCreacion: "2026-10-21T08:00:00.000Z",
    fechaSalida: estado === "preparacion" ? null : "2026-10-21T09:00:00.000Z",
    estado,
    items: [
      { productoId: 1, nombreProducto: "Yogur", unidadMedida: "unidad", cantidad: 10, precioReferencia: 100 },
    ],
  });

  const cierre = {
    fecha: "2026-10-21T18:00:00.000Z",
    conteos: { "1": 3 },
    efectivoEntregado: 0,
    efectivoEsperado: 0,
    transferenciasInformadas: 0,
    ventasCuentaCorriente: 0,
    observaciones: "",
  };

  const nueva = () => jornada("nueva", 9);

  const CORRUPTOS: Array<[string, string]> = [
    ["JSON inválido", "{no es json"],
    ["string vacío presente", ""],
    ["null", "null"],
    ["objeto no array", JSON.stringify({ jornadas: [] })],
    ["array con jornada inválida", JSON.stringify([{ id: "x" }])],
    [
      "array con jornada de ítem inválido",
      JSON.stringify([{ ...jornada("a", 1), items: [{ productoId: 1, cantidad: 1.5 }] }]),
    ],
    [
      "array con cierre inválido",
      JSON.stringify([{ ...jornada("a", 1, "cerrada"), cierre: { fecha: "x" } }]),
    ],
  ];

  const sinEscribir = (crudo: string) => {
    expect(mockLS.getItem(CLAVE)).toBe(crudo);
    expect(mockLS.setItem).not.toHaveBeenCalled();
  };

  it("getItem null (ausente) es un ledger inicial válido; \"\" (presente) se prueba en la matriz de corruptos", () => {
    expect(mockLS.getItem(CLAVE)).toBeNull();
    expect(crearPreparacionPersistida(nueva()).ok).toBe(true);
  });

  describe.each(CORRUPTOS)("storage corrupto — %s", (_n, crudo) => {
    beforeEach(() => {
      mockLS._store.set(CLAVE, crudo);
      mockLS.setItem.mockClear();
    });

    it("crearPreparacion: falla, sin setItem y con el string crudo intacto", () => {
      const antes = mockLS.getItem(CLAVE);
      expect(crearPreparacionPersistida(nueva()).ok).toBe(false);
      expect(antes).toBe(crudo);
      sinEscribir(crudo);
    });

    it("confirmarSalida: falla, sin setItem y con el string crudo intacto", () => {
      expect(confirmarSalidaPersistida("a")).toEqual({
        ok: false,
        error: "No se pudo confirmar la salida.",
      });
      sinEscribir(crudo);
    });

    it("cerrarJornada: falla, sin setItem y con el string crudo intacto", () => {
      expect(cerrarJornadaPersistida("a", cierre as never)).toBeNull();
      sinEscribir(crudo);
    });

    it("leerJornadas pública sigue siendo [] sin escribir", () => {
      expect(leerJornadas()).toEqual([]);
      sinEscribir(crudo);
    });
  });

  it("A. storage ausente: crearPreparacion guarda una sola jornada", () => {
    const j = nueva();
    expect(crearPreparacionPersistida(j)).toEqual({ ok: true, jornadas: [j] });
    expect(JSON.parse(mockLS.getItem(CLAVE) as string)).toEqual([j]);
  });

  it("B. confirmarSalida con storage válido conserva el comportamiento", () => {
    mockLS._store.set(CLAVE, JSON.stringify([jornada("a", 1), jornada("b", 2)]));
    const resultado = confirmarSalidaPersistida("a");
    if (!resultado.ok) throw new Error(resultado.error);
    const r = resultado.jornadas;
    expect(r.find((j) => j.id === "a")?.estado).toBe("abierta");
    expect(r.find((j) => j.id === "a")?.fechaSalida).not.toBeNull();
    expect(r.find((j) => j.id === "b")?.estado).toBe("preparacion");
    expect(leerJornadas()).toEqual(r);
    // No se puede confirmar dos veces ni una inexistente.
    const rechazo = { ok: false, error: "No se pudo confirmar la salida." };
    expect(confirmarSalidaPersistida("a")).toEqual(rechazo);
    expect(confirmarSalidaPersistida("zzz")).toEqual(rechazo);
  });

  it("C. cerrarJornada con storage válido conserva el comportamiento", () => {
    mockLS._store.set(CLAVE, JSON.stringify([jornada("a", 1, "abierta")]));
    const r = cerrarJornadaPersistida("a", cierre as never)!;
    expect(r[0].estado).toBe("cerrada");
    expect(leerJornadas()[0].cierre?.conteos).toEqual({ "1": 3 });
    expect(cerrarJornadaPersistida("a", cierre as never)).toBeNull();
  });

  it("historial válido: crearPreparacion conserva las anteriores y agrega al final", () => {
    const previas = [{ ...jornada("a", 1, "cerrada"), cierre }, jornada("b", 2)];
    mockLS._store.set(CLAVE, JSON.stringify(previas));
    const j = nueva();
    expect(crearPreparacionPersistida(j)).toEqual({ ok: true, jornadas: [...previas, j] });
    expect(JSON.parse(mockLS.getItem(CLAVE) as string)).toEqual([...previas, j]);
  });

  it("duplicados: mismo id y camión con jornada no cerrada se rechazan sin escribir", () => {
    const crudo = JSON.stringify([jornada("a", 1), jornada("c", 3, "cerrada")].map((j) =>
      j.estado === "cerrada" ? { ...j, cierre } : j
    ));
    mockLS._store.set(CLAVE, crudo);
    mockLS.setItem.mockClear();
    const duplicada = { ok: false, error: "Ya existe una jornada activa para ese camión." };
    expect(crearPreparacionPersistida(jornada("a", 7))).toEqual(duplicada);
    expect(crearPreparacionPersistida(jornada("n", 1))).toEqual(duplicada);
    sinEscribir(crudo);
    // Un camión con jornada cerrada sí puede crear otra.
    expect(crearPreparacionPersistida(jornada("n", 3)).ok).toBe(true);
  });

  it("corrupción tiene prioridad sobre las reglas de duplicado", () => {
    mockLS._store.set(CLAVE, "{roto");
    mockLS.setItem.mockClear();
    expect(crearPreparacionPersistida(jornada("a", 1))).toEqual({
      ok: false,
      error: expect.stringContaining("No se puede guardar la preparación"),
    });
    sinEscribir("{roto");
  });

  // H-1 (auditoría de 8ff5bef) invertido por B2 (decisión humana): una jornada
  // v5 válida con ítems `peso` ahora se crea y sale (`preparacion` →
  // `abierta`). Se conservan la validación de existencia y estado y el
  // bloqueo del cierre hasta B4.
  const itemPeso: ItemCarga = {
    productoId: 4,
    nombreProducto: "Jamón cocido",
    unidadMedida: "peso",
    cantidad: 18000,
    precioReferencia: 12500,
  };
  const conPeso = (
    id: string,
    camionId: number,
    estado: Jornada["estado"] = "preparacion"
  ): Jornada => {
    const j = jornada(id, camionId, estado);
    return { ...j, items: [...j.items, itemPeso] };
  };

  // Antes (H-1): «una jornada con ítem peso devuelve null sin leer ni escribir».
  // Catálogo inicial (clave de productos ausente): jamón 18000 g, así que
  // 18000 g es el stock exacto.
  it("B2 crearPreparacion: una jornada peso con stock exacto se agrega con sus gramos intactos", () => {
    const j = conPeso("p", 5);
    expect(crearPreparacionPersistida(j)).toEqual({ ok: true, jornadas: [j] });
    expect(JSON.parse(mockLS.getItem(CLAVE) as string)).toEqual([j]);
  });

  it("B2 crearPreparacion: una jornada peso con stock + 1 g se rechaza sin escribir", () => {
    const j = { ...conPeso("p", 5), items: [{ ...itemPeso, cantidad: 18001 }] };
    expect(crearPreparacionPersistida(j)).toEqual({
      ok: false,
      error: expect.stringContaining("No hay stock suficiente"),
    });
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS.getItem(CLAVE)).toBeNull();
  });

  // Antes (H-1): «con historial válido, una jornada peso no altera el raw».
  it("B2 crearPreparacion: con historial válido, la jornada peso se agrega al final", () => {
    const previa = jornada("a", 1);
    mockLS._store.set(CLAVE, JSON.stringify([previa]));
    const j = conPeso("p", 5);
    expect(crearPreparacionPersistida(j)).toEqual({ ok: true, jornadas: [previa, j] });
  });

  it("B2 crearPreparacion: las reglas de duplicado siguen aplicando a una jornada peso", () => {
    const crudo = JSON.stringify([jornada("a", 1)]);
    mockLS._store.set(CLAVE, crudo);
    mockLS.setItem.mockClear();
    const duplicada = { ok: false, error: "Ya existe una jornada activa para ese camión." };
    expect(crearPreparacionPersistida(conPeso("a", 7))).toEqual(duplicada);
    expect(crearPreparacionPersistida(conPeso("n", 1))).toEqual(duplicada);
    sinEscribir(crudo);
  });

  // Security review B2 (ALTO-1): el alta sólo admite una preparación nueva;
  // una jornada `peso` no puede nacer abierta ni cerrada (el cierre con peso
  // sigue bloqueado hasta B4).
  it.each([
    ["abierta", () => conPeso("p", 5, "abierta")],
    ["cerrada", () => ({ ...conPeso("p", 5, "cerrada"), cierre: { ...cierre, conteos: { "1": 10, "4": 18000 } } })],
    ["en preparación con fechaSalida", () => ({ ...conPeso("p", 5), fechaSalida: "2026-10-21T09:00:00.000Z" })],
    ["en preparación con cierre", () => ({ ...conPeso("p", 5), cierre: { ...cierre, conteos: { "1": 10, "4": 18000 } } })],
  ])("security review B2 crearPreparacion: una jornada peso %s se rechaza sin escribir", (_n, crear) => {
    const crudo = JSON.stringify([jornada("a", 1)]);
    mockLS._store.set(CLAVE, crudo);
    mockLS.setItem.mockClear();

    expect(crearPreparacionPersistida(crear())).toEqual({
      ok: false,
      error: MENSAJE_PREPARACION_INVALIDA,
    });
    sinEscribir(crudo);

    // Con storage ausente tampoco crea la clave.
    mockLS._store.delete(CLAVE);
    expect(crearPreparacionPersistida(crear())).toEqual({
      ok: false,
      error: MENSAJE_PREPARACION_INVALIDA,
    });
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS.getItem(CLAVE)).toBeNull();
  });

  // Antes (H-1): «una jornada v5 válida en preparación con ítem peso se
  // rechaza con el mensaje B1, sin escribir».
  it("B2 confirmarSalida: una jornada v5 válida en preparación con ítem peso pasa a abierta", () => {
    mockLS._store.set(CLAVE, JSON.stringify([conPeso("p", 1), jornada("b", 2)]));

    const resultado = confirmarSalidaPersistida("p");
    if (!resultado.ok) throw new Error(resultado.error);

    const guardada = leerJornadas().find((j) => j.id === "p");
    expect(guardada?.estado).toBe("abierta");
    expect(typeof guardada?.fechaSalida).toBe("string");
    expect(guardada?.items).toEqual(conPeso("p", 1).items);
    expect(leerJornadas().find((j) => j.id === "b")?.estado).toBe("preparacion");
    expect(resultado.jornadas).toEqual(leerJornadas());
  });

  // Antes (H-1): «el rechazo peso no bloquea otra jornada unidad».
  it("B2 confirmarSalida: jornadas peso y unidad del mismo storage salen por separado", () => {
    mockLS._store.set(CLAVE, JSON.stringify([conPeso("p", 1), jornada("b", 2)]));
    expect(confirmarSalidaPersistida("p").ok).toBe(true);
    expect(confirmarSalidaPersistida("b").ok).toBe(true);
    const guardadas = leerJornadas();
    expect(guardadas.find((j) => j.id === "b")?.estado).toBe("abierta");
    expect(guardadas.find((j) => j.id === "p")?.estado).toBe("abierta");
  });

  // Se conserva sin cambios de expectativa: la validación de estado sigue.
  it("B2 confirmarSalida: una jornada peso ya abierta no se confirma dos veces (rechazo genérico)", () => {
    const crudo = JSON.stringify([conPeso("p", 1, "abierta")]);
    mockLS._store.set(CLAVE, crudo);
    mockLS.setItem.mockClear();
    expect(confirmarSalidaPersistida("p")).toEqual({
      ok: false,
      error: "No se pudo confirmar la salida.",
    });
    sinEscribir(crudo);
  });

  it("B2 cerrarJornada: una jornada peso abierta se rechaza (B4), sin escritura y sigue abierta", () => {
    const crudo = JSON.stringify([conPeso("p", 1, "abierta")]);
    mockLS._store.set(CLAVE, crudo);
    mockLS.setItem.mockClear();
    const cierrePeso = { ...cierre, conteos: { "1": 3, "4": 18000 } };

    expect(cerrarJornadaPersistida("p", cierrePeso as never)).toBeNull();

    sinEscribir(crudo);
    const guardada = leerJornadas().find((j) => j.id === "p");
    expect(guardada?.estado).toBe("abierta");
    expect(guardada?.cierre).toBeUndefined();
  });

  it("la clave de jornadas es v5", () => {
    expect(CLAVE).toBe("distribuidora_jornadas_demo_v5");
  });
});

describe("catálogos (productos, camiones, clientes): storage corrupto fail-closed", () => {
  const MAX = Number.MAX_SAFE_INTEGER;

  const producto = {
    id: 1, nombre: "Yogur", categoria: "Lácteos", unidadMedida: "unidad",
    stock: 5, precio: 100, stockMinimo: 1,
  };
  const camion = {
    id: 1, nombre: "Camión 1", patente: "AA123BB", marca: "M", modelo: "X",
    observaciones: "", estado: "disponible",
  };
  const cliente = {
    id: 1, nombreComercio: "Almacén", titular: "Ana", telefono: "1", direccion: "d",
    zona: "z", condicionPago: "contado", limiteCredito: 0, activo: true,
  };

  const catalogos: Array<{
    nombre: string;
    clave: string;
    leer: () => ResultadoLectura<unknown>;
    valido: unknown;
    invalido: unknown;
    iniciales: unknown[];
  }> = [
    {
      nombre: "productos",
      clave: CLAVES_STORAGE.productos,
      leer: leerProductos,
      valido: producto,
      invalido: { ...producto, stock: MAX + 1 },
      iniciales: productosIniciales,
    },
    {
      nombre: "camiones",
      clave: CLAVES_STORAGE.camiones,
      leer: leerCamiones,
      valido: camion,
      invalido: { ...camion, estado: "roto" },
      iniciales: camionesIniciales,
    },
    {
      nombre: "clientes",
      clave: "distribuidora_clientes_demo_v2",
      leer: leerClientes,
      valido: cliente,
      invalido: { ...cliente, limiteCredito: -1 },
      iniciales: clientesIniciales,
    },
  ];

  const CORRUPTOS: Array<[string, string]> = [
    ["JSON inválido", "{no es json"],
    ["string vacío presente", ""],
    ["null", "null"],
    ["objeto no array", JSON.stringify({ datos: [] })],
  ];

  describe.each(catalogos)("$nombre", (c) => {
    // Misma frontera que el efecto del hook: lectura inicial + persistirCatalogo.
    const montar = () => {
      const lectura = c.leer();
      const estadoInicial: unknown[] = lectura.ok ? lectura.datos : c.iniciales;
      return { lectura, estadoInicial };
    };

    it("A. storage ausente: estado inicial legítimo y se inicializa (persiste los demo)", () => {
      const { lectura, estadoInicial } = montar();
      expect(lectura.ok).toBe(true);
      if (lectura.ok) expect(lectura.estado).toBe("inicial");
      expect(persistirCatalogo(c.clave, estadoInicial, lectura)).toBe(true);
      expect(mockLS.getItem(c.clave)).toBe(JSON.stringify(estadoInicial));
    });

    it("B. storage válido: usa los datos guardados", () => {
      mockLS._store.set(c.clave, JSON.stringify([c.valido]));
      const { lectura } = montar();
      expect(lectura.ok).toBe(true);
      if (lectura.ok) {
        expect(lectura.estado).toBe("valido");
        expect(lectura.datos).toEqual([c.valido]);
      }
    });

    it.each(CORRUPTOS)("%s: raw intacto y sin setItem al montar ni al editar", (_n, crudo) => {
      mockLS._store.set(c.clave, crudo);
      mockLS.setItem.mockClear();
      const antes = mockLS.getItem(c.clave);
      const { lectura, estadoInicial } = montar();

      expect(lectura.ok).toBe(false);
      // Efecto de montaje con los datos demo: no escribe.
      expect(persistirCatalogo(c.clave, estadoInicial, lectura)).toBe(false);
      // Edición posterior del usuario en la sesión: tampoco escribe.
      expect(
        persistirCatalogo(c.clave, [...estadoInicial, c.valido], lectura)
      ).toBe(false);
      expect(mockLS.getItem(c.clave)).toBe(antes);
      expect(mockLS.setItem).not.toHaveBeenCalled();
    });

    it("G. array con un elemento inválido: raw intacto y sin setItem", () => {
      const crudo = JSON.stringify([c.valido, c.invalido]);
      mockLS._store.set(c.clave, crudo);
      mockLS.setItem.mockClear();
      const { lectura, estadoInicial } = montar();

      expect(lectura.ok).toBe(false);
      // Efecto de montaje con los datos demo: no escribe.
      expect(persistirCatalogo(c.clave, estadoInicial, lectura)).toBe(false);
      // Edición posterior del usuario en la sesión: tampoco escribe.
      expect(
        persistirCatalogo(c.clave, [...estadoInicial, c.valido], lectura)
      ).toBe(false);
      expect(mockLS.getItem(c.clave)).toBe(crudo);
      expect(mockLS.setItem).not.toHaveBeenCalled();
    });
  });

  it("las funciones públicas cargarX siguen devolviendo datos demo ante corrupción, sin escribir", () => {
    mockLS._store.set(CLAVES_STORAGE.productos, "{roto");
    mockLS._store.set(CLAVES_STORAGE.camiones, "");
    mockLS._store.set(CLAVE_CLIENTES, "null");
    expect(cargarProductos()).toEqual(productosIniciales);
    expect(cargarCamiones()).toEqual(camionesIniciales);
    expect(cargarClientes()).toEqual(clientesIniciales);
    expect(mockLS.setItem).not.toHaveBeenCalled();
  });

  it("claves vigentes v5", () => {
    expect(CLAVES_STORAGE.productos).toBe("distribuidora_productos_demo_v5");
    expect(CLAVES_STORAGE.camiones).toBe("distribuidora_camiones_demo_v5");
  });
});

describe("ventas y cobros: escritura fail-closed ante storage corrupto", () => {
  const CV = CLAVES_STORAGE.ventas;
  const CC = CLAVES_STORAGE.cobros;

  const venta = (id: string, total = 200): Venta => ({
    id,
    jornadaId: "j1",
    camionId: 1,
    clienteId: 1,
    nombreCliente: "Almacén",
    fecha: "2026-10-21T10:00:00.000Z",
    medioPago: "cuenta_corriente",
    items: [
      {
        productoId: 1,
        nombreProducto: "Yogur",
        unidadMedida: "unidad",
        cantidad: total / 100,
        precioUnitario: 100,
        subtotal: total,
      },
    ],
    total,
  });

  const cobro = (id: string, importe = 50, extra: Partial<Cobro> = {}): Cobro => ({
    id,
    clienteId: 1,
    nombreCliente: "Almacén",
    jornadaId: null,
    fecha: "2026-10-21T12:00:00.000Z",
    importe,
    medio: "efectivo",
    referencia: "",
    observaciones: "",
    ...extra,
  });

  const CORRUPTOS_VENTAS: Array<[string, string]> = [
    ["JSON inválido", "{no es json"],
    ["string vacío presente", ""],
    ["null", "null"],
    ["objeto no array", JSON.stringify({ ventas: [] })],
    [
      "array con venta inválida (total inconsistente)",
      JSON.stringify([{ ...venta("x"), total: 999 }]),
    ],
  ];

  const CORRUPTOS_COBROS: Array<[string, string]> = [
    ["JSON inválido", "{no es json"],
    ["string vacío presente", ""],
    ["null", "null"],
    ["objeto no array", JSON.stringify({ cobros: [] })],
    [
      "array con cobro inválido (importe negativo)",
      JSON.stringify([cobro("x", -5)]),
    ],
  ];

  describe("ventas", () => {
    it("A. storage ausente: la venta válida se registra y se persiste", () => {
      const validar = vi.fn(() => null);
      const v = venta("v1");
      expect(mockLS.getItem(CV)).toBeNull();
      expect(registrarVentaPersistida(v, validar)).toBeNull();
      expect(validar).toHaveBeenCalledWith([]);
      expect(JSON.parse(mockLS.getItem(CV) as string)).toEqual([v]);
    });

    it("B. storage válido: conserva el historial y agrega al final", () => {
      const previa = venta("v0");
      mockLS._store.set(CV, JSON.stringify([previa]));
      const v = venta("v1");
      expect(registrarVentaPersistida(v, () => null)).toBeNull();
      expect(JSON.parse(mockLS.getItem(CV) as string)).toEqual([previa, v]);
    });

    it("C. venta duplicada: rechazo sin escribir ni llamar a validar", () => {
      const crudo = JSON.stringify([venta("v1")]);
      mockLS._store.set(CV, crudo);
      mockLS.setItem.mockClear();
      const validar = vi.fn(() => null);
      expect(registrarVentaPersistida(venta("v1"), validar)).toMatch(/ya fue registrada/);
      expect(validar).not.toHaveBeenCalled();
      expect(mockLS.getItem(CV)).toBe(crudo);
      expect(mockLS.setItem).not.toHaveBeenCalled();
    });

    it("D. venta inválida: rechazo antes de leer, validar o escribir", () => {
      const cargar = vi.fn();
      const validar = vi.fn(() => null);
      const guardar = vi.fn();
      const error = registrarVentaOperacion({ ...venta("v1"), total: 1 }, validar, cargar, guardar);
      expect(error).toMatch(/validación/);
      expect(cargar).not.toHaveBeenCalled();
      expect(validar).not.toHaveBeenCalled();
      expect(guardar).not.toHaveBeenCalled();
    });

    it.each(CORRUPTOS_VENTAS)("storage corrupto — %s: falla, sin validar de stock, sin setItem, raw intacto", (_n, crudo) => {
      mockLS._store.set(CV, crudo);
      mockLS.setItem.mockClear();
      const antes = mockLS.getItem(CV);
      const validar = vi.fn(() => null);
      const alGuardar = vi.fn();
      const error = registrarVentaPersistida(venta("v1"), validar, alGuardar);
      expect(error).toMatch(/No se puede registrar/);
      expect(validar).not.toHaveBeenCalled();
      expect(alGuardar).not.toHaveBeenCalled();
      expect(mockLS.setItem).not.toHaveBeenCalled();
      expect(mockLS.getItem(CV)).toBe(antes);
      expect(mockLS.getItem(CV)).toBe(crudo);
      // La lectura pública para la UI sigue siendo [] y tampoco escribe.
      expect(cargarVentas()).toEqual([]);
      expect(mockLS.setItem).not.toHaveBeenCalled();
    });
  });

  describe("cobros", () => {
    const conVentas = () =>
      mockLS._store.set(CV, JSON.stringify([venta("v1", 200)]));

    it("A. cobros ausentes + ventas con deuda: el cobro válido se registra", () => {
      conVentas();
      expect(mockLS.getItem(CC)).toBeNull();
      const c = cobro("c1", 50);
      expect(registrarCobroPersistido(c)).toBeNull();
      expect(JSON.parse(mockLS.getItem(CC) as string)).toEqual([c]);
    });

    it("B. cobros válidos: conserva el historial y agrega", () => {
      conVentas();
      const previo = cobro("c0", 50);
      mockLS._store.set(CC, JSON.stringify([previo]));
      const c = cobro("c1", 100);
      expect(registrarCobroPersistido(c)).toBeNull();
      expect(JSON.parse(mockLS.getItem(CC) as string)).toEqual([previo, c]);
    });

    it("C. cobro duplicado: rechazo sin escribir", () => {
      conVentas();
      const crudo = JSON.stringify([cobro("c1", 50)]);
      mockLS._store.set(CC, crudo);
      mockLS.setItem.mockClear();
      expect(registrarCobroPersistido(cobro("c1", 50))).toMatch(/ya fue registrado/);
      expect(mockLS.getItem(CC)).toBe(crudo);
      expect(mockLS.setItem).not.toHaveBeenCalled();
    });

    it("D. transferencia sin referencia: rechazo", () => {
      conVentas();
      const error = registrarCobroPersistido(cobro("c1", 50, { medio: "transferencia", referencia: "  " }));
      expect(error).toMatch(/referencia/);
      expect(mockLS.getItem(CC)).toBeNull();
    });

    it("E. cobro mayor al saldo: rechazo", () => {
      conVentas();
      expect(registrarCobroPersistido(cobro("c1", 250))).toMatch(/supera el saldo/);
      expect(mockLS.getItem(CC)).toBeNull();
    });

    it.each(CORRUPTOS_COBROS)("cobros corruptos — %s: falla, sin setItem, raw de cobros intacto", (_n, crudo) => {
      conVentas();
      mockLS._store.set(CC, crudo);
      mockLS.setItem.mockClear();
      const alGuardar = vi.fn();
      const error = registrarCobroPersistido(cobro("c1", 50), alGuardar);
      expect(error).toMatch(/No se puede registrar/);
      expect(alGuardar).not.toHaveBeenCalled();
      expect(mockLS.setItem).not.toHaveBeenCalled();
      expect(mockLS.getItem(CC)).toBe(crudo);
      expect(leerCobros()).toEqual([]);
    });

    it.each(CORRUPTOS_VENTAS)("ventas corruptas desde cobros — %s: no persiste ni calcula saldo sobre []", (_n, crudoVentas) => {
      for (const crudoCobros of [null, JSON.stringify([cobro("c0", 10)])]) {
        mockLS._store.clear();
        mockLS._store.set(CV, crudoVentas);
        if (crudoCobros !== null) mockLS._store.set(CC, crudoCobros);
        mockLS.setItem.mockClear();
        const alGuardar = vi.fn();
        // Importe que excedería el saldo si se calculara sobre [] (saldo 0).
        const error = registrarCobroPersistido(cobro("c1", 5000), alGuardar);
        expect(error).toMatch(/No se pudieron verificar las ventas/);
        expect(alGuardar).not.toHaveBeenCalled();
        expect(mockLS.setItem).not.toHaveBeenCalled();
        expect(mockLS.getItem(CV)).toBe(crudoVentas);
        expect(mockLS.getItem(CC)).toBe(crudoCobros);
      }
    });

    it("prioridad A: cobros corruptos + cobro duplicado → corrupción, sin escribir", () => {
      conVentas();
      mockLS._store.set(CC, "{roto");
      mockLS.setItem.mockClear();
      expect(registrarCobroPersistido(cobro("c1", 50))).toMatch(/No se puede registrar/);
      expect(mockLS.setItem).not.toHaveBeenCalled();
    });

    it("prioridad B: cobros válidos + ventas corruptas → falla por ventas", () => {
      mockLS._store.set(CC, JSON.stringify([cobro("c0", 10)]));
      mockLS._store.set(CV, "");
      mockLS.setItem.mockClear();
      expect(registrarCobroPersistido(cobro("c1", 5))).toMatch(/ventas/);
      expect(mockLS.setItem).not.toHaveBeenCalled();
    });

    it("prioridad C: cobros corruptos no consultan ventas (guardar/ventas no se invocan)", () => {
      const cargarVentasActuales = vi.fn();
      const guardar = vi.fn();
      const error = registrarCobroOperacion(
        cobro("c1", 50),
        () => ({ ok: false, estado: "corrupto", error: "roto" }),
        cargarVentasActuales,
        guardar
      );
      expect(error).toMatch(/No se puede registrar/);
      expect(cargarVentasActuales).not.toHaveBeenCalled();
      expect(guardar).not.toHaveBeenCalled();
    });

    it("las claves de ventas y cobros son v5", () => {
      expect(CV).toBe("distribuidora_ventas_demo_v5");
      expect(CC).toBe("distribuidora_cobros_demo_v5");
    });
  });
});

describe("Guards de peso en las fronteras REALES de escritura (B2 levanta movimientos; retornos sigue en B4)", () => {
  const jamon = (gramos: number) => ({
    productoId: 4,
    nombreProducto: "Jamón cocido",
    unidadMedida: "peso" as const,
    cantidad: gramos,
  });

  // Antes (B1): «movimientos: una merma peso se rechaza y el storage queda
  // intacto». B2 habilita los movimientos `peso`.
  it("movimientos (B2): una merma peso se persiste con los gramos exactos", () => {
    mockLS._store.set(CLAVES_STORAGE.movimientos, JSON.stringify([]));
    const jornada: Jornada = {
      id: "j1",
      camionId: 1,
      chofer: "Luis",
      zona: "Norte",
      fechaCreacion: "2026-10-27T08:00:00.000Z",
      fechaSalida: "2026-10-27T09:00:00.000Z",
      estado: "abierta",
      items: [{ ...jamon(1250), precioReferencia: 12500 }],
    };
    mockLS._store.set(CLAVES_STORAGE.jornadas, JSON.stringify([jornada]));
    const merma = {
      id: "m-peso",
      jornadaId: "j1",
      camionId: 1,
      fecha: "2026-10-27T10:00:00.000Z",
      motivo: "Otro",
      tipo: "merma" as const,
      producto: jamon(1250),
      clienteId: null,
      nombreCliente: null,
    };

    expect(registrarMovimientoPersistido(merma, jornada)).toEqual({ ok: true, movimientos: [merma] });

    expect(JSON.parse(mockLS._store.get(CLAVES_STORAGE.movimientos) as string)).toEqual([merma]);
  });

  it("retornos: un retorno con ítem peso se rechaza y no se escribe", () => {
    mockLS.setItem.mockClear();

    const error = registrarRetornoPersistido({
      id: "r-peso",
      jornadaId: "j1",
      camionId: 1,
      fecha: "2026-10-27T18:00:00.000Z",
      responsable: "Ana",
      observaciones: "",
      items: [
        {
          productoId: 4,
          nombreProducto: "Jamón cocido",
          unidadMedida: "peso",
          cantidadContada: 18000,
          cantidadAprobada: 18000,
        },
      ],
    });

    expect(error).toBe(MENSAJE_PESO_NO_OPERABLE);
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS._store.has(CLAVES_STORAGE.retornos)).toBe(false);
  });

  it("jornadas: cerrar una jornada con ítem peso devuelve null y no escribe", () => {
    const crudo = JSON.stringify([
      {
        id: "j-peso",
        camionId: 1,
        chofer: "Luis",
        zona: "Norte",
        fechaCreacion: "2026-10-27T08:00:00.000Z",
        fechaSalida: "2026-10-27T09:00:00.000Z",
        estado: "abierta",
        items: [
          { productoId: 4, nombreProducto: "Jamón cocido", unidadMedida: "peso", cantidad: 18000, precioReferencia: 12500 },
        ],
      },
    ]);
    mockLS._store.set(CLAVES_STORAGE.jornadas, crudo);
    mockLS.setItem.mockClear();

    const r = cerrarJornadaPersistida("j-peso", {
      fecha: "2026-10-27T18:00:00.000Z",
      conteos: { "4": 18000 },
      efectivoEntregado: 0,
      efectivoEsperado: 0,
      transferenciasInformadas: 0,
      ventasCuentaCorriente: 0,
      observaciones: "",
    });

    expect(r).toBeNull();
    expect(mockLS.setItem).not.toHaveBeenCalled();
    expect(mockLS._store.get(CLAVES_STORAGE.jornadas)).toBe(crudo);
  });
});
