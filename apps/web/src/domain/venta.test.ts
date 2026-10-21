import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { construirDetalleVenta, construirItemsVenta } from "./venta";
import { item_valido, subtotal_coincide, venta_valida } from "./validacion";
import { sumar_importes } from "./precios";
import { registrarVentaOperacion } from "../hooks/useVentas";
import type { DetalleVenta, Venta } from "../data/mockVentas";

// --- Simulación de localStorage para entorno node (igual que persistencia.test.ts) ---
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
    configurable: true,
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});


// Helper para crear ventas actuales simuladas
const crearCargarActuales = (inicial: Venta[] = []) => {
  const store = [...inicial];
  return () => [...store];
};

const crearGuardarActualizadas = () => {
  let store: Venta[] = [];
  return {
    fn: vi.fn((nuevas: Venta[]) => {
      store = nuevas;
    }),
    getStore: () => [...store],
  };
};

describe("construirDetalleVenta — ADR-003 snapshot y subtotal", () => {
  // Caso A: pieza, precio = 21, cantidad = 1 (media pieza)
  it("pieza precio 21, cantidad 1 → precioUnitario=21, precioMediaPieza=11, subtotal=11", () => {
    const item = construirDetalleVenta({
      productoId: 1,
      nombreProducto: "Jamón",
      unidadMedida: "pieza",
      cantidadCanonica: 1,
      precioReferencia: 21,
    });

    expect(item.precioUnitario).toBe(21);
    expect(item.precioMediaPieza).toBe(11);
    expect(item.subtotal).toBe(11);
    expect(item.unidadMedida).toBe("pieza");
    expect(item.cantidad).toBe(1);
  });

  // Caso B: pieza, precio = 21, cantidad = 2 (1 pieza)
  it("pieza precio 21, cantidad 2 → precioUnitario=21, precioMediaPieza=11, subtotal=21", () => {
    const item = construirDetalleVenta({
      productoId: 1,
      nombreProducto: "Jamón",
      unidadMedida: "pieza",
      cantidadCanonica: 2,
      precioReferencia: 21,
    });

    expect(item.precioUnitario).toBe(21);
    expect(item.precioMediaPieza).toBe(11);
    expect(item.subtotal).toBe(21);
    expect(item.cantidad).toBe(2);
  });

  // Caso C: pieza, precio = 21, cantidad = 3 (1 pieza + media)
  it("pieza precio 21, cantidad 3 → precioUnitario=21, precioMediaPieza=11, subtotal=32", () => {
    const item = construirDetalleVenta({
      productoId: 1,
      nombreProducto: "Jamón",
      unidadMedida: "pieza",
      cantidadCanonica: 3,
      precioReferencia: 21,
    });

    expect(item.precioUnitario).toBe(21);
    expect(item.precioMediaPieza).toBe(11);
    expect(item.subtotal).toBe(32);
    expect(item.cantidad).toBe(3);
  });

  // Caso D: unidad, precio = 100, cantidad = 3
  it("unidad precio 100, cantidad 3 → precioUnitario=100, precioMediaPieza AUSENTE, subtotal=300", () => {
    const item = construirDetalleVenta({
      productoId: 2,
      nombreProducto: "Leche",
      unidadMedida: "unidad",
      cantidadCanonica: 3,
      precioReferencia: 100,
    });

    expect(item.precioUnitario).toBe(100);
    expect(item.precioMediaPieza).toBeUndefined();
    expect(item.subtotal).toBe(300);
    expect(item.unidadMedida).toBe("unidad");
    expect(item.cantidad).toBe(3);
  });

  // Validaciones de entrada
  it("rechaza cantidad 1.5 (no entera)", () => {
    expect(() =>
      construirDetalleVenta({
        productoId: 1,
        nombreProducto: "Test",
        unidadMedida: "pieza",
        cantidadCanonica: 1.5,
        precioReferencia: 21,
      })
    ).toThrow("Cantidad canónica inválida");
  });

  it("rechaza NaN", () => {
    expect(() =>
      construirDetalleVenta({
        productoId: 1,
        nombreProducto: "Test",
        unidadMedida: "pieza",
        cantidadCanonica: NaN,
        precioReferencia: 21,
      })
    ).toThrow("Cantidad canónica inválida");
  });

  it("rechaza Infinity", () => {
    expect(() =>
      construirDetalleVenta({
        productoId: 1,
        nombreProducto: "Test",
        unidadMedida: "pieza",
        cantidadCanonica: Infinity,
        precioReferencia: 21,
      })
    ).toThrow("Cantidad canónica inválida");
  });

  it("rechaza cantidad negativa", () => {
    expect(() =>
      construirDetalleVenta({
        productoId: 1,
        nombreProducto: "Test",
        unidadMedida: "pieza",
        cantidadCanonica: -1,
        precioReferencia: 21,
      })
    ).toThrow("Cantidad canónica inválida");
  });

  it("rechaza cantidad 0 (una venta no debe tener línea de cantidad cero)", () => {
    expect(() =>
      construirDetalleVenta({
        productoId: 1,
        nombreProducto: "Test",
        unidadMedida: "pieza",
        cantidadCanonica: 0,
        precioReferencia: 21,
      })
    ).toThrow("Cantidad canónica inválida");
  });

  it("rechaza precio negativo", () => {
    expect(() =>
      construirDetalleVenta({
        productoId: 1,
        nombreProducto: "Test",
        unidadMedida: "pieza",
        cantidadCanonica: 1,
        precioReferencia: -10,
      })
    ).toThrow("Precio de referencia inválido");
  });
});

describe("construirItemsVenta — múltiples productos", () => {
  it("construye items para pieza y unidad correctamente", () => {
    const productos = [
      { productoId: 1, nombreProducto: "Jamón", unidadMedida: "pieza" as const, precioReferencia: 21 },
      { productoId: 2, nombreProducto: "Leche", unidadMedida: "unidad" as const, precioReferencia: 100 },
    ];

    const obtenerCantidadCanonica = (id: number) => (id === 1 ? 3 : 2);

    const items = construirItemsVenta({ productos, obtenerCantidadCanonica });

    expect(items).toHaveLength(2);
    expect(items[0].productoId).toBe(1);
    expect(items[0].cantidad).toBe(3);
    expect(items[0].precioMediaPieza).toBe(11);
    expect(items[1].productoId).toBe(2);
    expect(items[1].cantidad).toBe(2);
    expect(items[1].precioMediaPieza).toBeUndefined();
  });

  it("filtra productos con cantidad 0", () => {
    const productos = [
      { productoId: 1, nombreProducto: "Jamón", unidadMedida: "pieza" as const, precioReferencia: 21 },
    ];

    const obtenerCantidadCanonica = () => 0;

    const items = construirItemsVenta({ productos, obtenerCantidadCanonica });

    expect(items).toHaveLength(0);
  });
});

describe("Regresión M-1: venta de pieza sobrevive a recarga (usa validador real de useVentas)", () => {
  /**
   * El test usa EXACTAMENTE LA MISMA FUNCIÓN que importa useVentas:
   * item_valido de domain/validacion.ts
   * Esto prueba el contrato productor/consumidor real:
   * Autoventa → construirDetalleVenta → payload → item_valido (shared) → aceptado
   */

  it("venta de pieza (caso A) pasa validación item_valido (shared con useVentas)", () => {
    const item = construirDetalleVenta({
      productoId: 1,
      nombreProducto: "Jamón",
      unidadMedida: "pieza",
      cantidadCanonica: 1,
      precioReferencia: 21,
    });

    expect(item_valido(item)).toBe(true);
  });

  it("venta de pieza (caso B) pasa validación item_valido", () => {
    const item = construirDetalleVenta({
      productoId: 1,
      nombreProducto: "Jamón",
      unidadMedida: "pieza",
      cantidadCanonica: 2,
      precioReferencia: 21,
    });

    expect(item_valido(item)).toBe(true);
  });

  it("venta de pieza (caso C) pasa validación item_valido", () => {
    const item = construirDetalleVenta({
      productoId: 1,
      nombreProducto: "Jamón",
      unidadMedida: "pieza",
      cantidadCanonica: 3,
      precioReferencia: 21,
    });

    expect(item_valido(item)).toBe(true);
  });

  it("venta de unidad (caso D) pasa validación item_valido", () => {
    const item = construirDetalleVenta({
      productoId: 2,
      nombreProducto: "Leche",
      unidadMedida: "unidad",
      cantidadCanonica: 3,
      precioReferencia: 100,
    });

    expect(item_valido(item)).toBe(true);
  });

  it("venta de pieza CON precioMediaPieza incorrecto FALLA validación", () => {
    const item = construirDetalleVenta({
      productoId: 1,
      nombreProducto: "Jamón",
      unidadMedida: "pieza",
      cantidadCanonica: 1,
      precioReferencia: 21,
    });
    const itemConError = { ...item, precioMediaPieza: 999 };
    expect(item_valido(itemConError)).toBe(false);
  });

  it("venta de unidad CON precioMediaPieza FALLA validación", () => {
    const item = construirDetalleVenta({
      productoId: 2,
      nombreProducto: "Leche",
      unidadMedida: "unidad",
      cantidadCanonica: 3,
      precioReferencia: 100,
    });
    const itemConError = { ...item, precioMediaPieza: 50 };
    expect(item_valido(itemConError)).toBe(false);
  });

  it("venta de pieza SIN precioMediaPieza FALLA validación", () => {
    const item = construirDetalleVenta({
      productoId: 1,
      nombreProducto: "Jamón",
      unidadMedida: "pieza",
      cantidadCanonica: 1,
      precioReferencia: 21,
    });
    const itemConError = { ...item, precioMediaPieza: undefined };
    expect(item_valido(itemConError)).toBe(false);
  });

  it("subtotal incorrecto FALLA validación", () => {
    const item = construirDetalleVenta({
      productoId: 1,
      nombreProducto: "Jamón",
      unidadMedida: "pieza",
      cantidadCanonica: 1,
      precioReferencia: 21,
    });
    const itemConError = { ...item, subtotal: 999 };
    expect(item_valido(itemConError)).toBe(false);
  });

  it("cantidad cero FALLA validación (item_valido rechaza cantidad <= 0)", () => {
    const item = construirDetalleVenta({
      productoId: 1,
      nombreProducto: "Jamón",
      unidadMedida: "pieza",
      cantidadCanonica: 1,
      precioReferencia: 21,
    });
    const itemConError = { ...item, cantidad: 0 };
    expect(item_valido(itemConError)).toBe(false);
  });
});

describe("Snapshot histórico: validación usa snapshot guardado, NO recalcula ADR-003", () => {
  it("detalle pieza con snapshot histórico 21/12/3/33 → VÁLIDO (subtotal coincide con snapshot)", () => {
    const item: DetalleVenta = {
      productoId: 1,
      nombreProducto: "Jamón histórico",
      unidadMedida: "pieza",
      cantidad: 3,
      precioUnitario: 21,
      precioMediaPieza: 12,
      subtotal: 33,
    };

    expect(item_valido(item)).toBe(true);
    expect(subtotal_coincide(item)).toBe(true);
  });

  it("mismo snapshot 21/12/3 pero subtotal 32 → INVÁLIDO (no coincide con snapshot)", () => {
    const item: DetalleVenta = {
      productoId: 1,
      nombreProducto: "Jamón histórico",
      unidadMedida: "pieza",
      cantidad: 3,
      precioUnitario: 21,
      precioMediaPieza: 12,
      subtotal: 32,
    };

    expect(item_valido(item)).toBe(false);
    expect(subtotal_coincide(item)).toBe(false);
  });

  it("venta completa con items históricos válidos pasa venta_valida", () => {
    const venta: Venta = {
      id: "test-venta-1",
      jornadaId: "jornada-1",
      camionId: 1,
      clienteId: 1,
      nombreCliente: "Cliente Test",
      fecha: new Date().toISOString(),
      medioPago: "efectivo",
      items: [
        {
          productoId: 1,
          nombreProducto: "Jamón histórico",
          unidadMedida: "pieza",
          cantidad: 3,
          precioUnitario: 21,
          precioMediaPieza: 12,
          subtotal: 33,
        },
        {
          productoId: 2,
          nombreProducto: "Leche",
          unidadMedida: "unidad",
          cantidad: 2,
          precioUnitario: 100,
          subtotal: 200,
        },
      ],
      total: 233,
    };

    expect(venta_valida(venta)).toBe(true);
  });
});

describe("Total de venta usa sumar_importes (política monetaria)", () => {
  it("total coincide con suma de subtotales via sumar_importes", () => {
    const items = [
      construirDetalleVenta({ productoId: 1, nombreProducto: "Jamón", unidadMedida: "pieza", cantidadCanonica: 1, precioReferencia: 21 }),
      construirDetalleVenta({ productoId: 2, nombreProducto: "Leche", unidadMedida: "unidad", cantidadCanonica: 3, precioReferencia: 100 }),
    ];

    const total = sumar_importes(items.map((i) => i.subtotal));
    expect(total).toBe(11 + 300);
  });
});

/**
 * Test de frontera de escritura (M-1): registrarVentaOperacion debe rechazar ventas inválidas
 * ANTES de persistir, modificar estado o ejecutar callback de stock.
 * Usa la función pura extraída, no el hook.
 */
describe("Frontera de escritura: registrarVentaOperacion rechaza inválidos antes de persistir", () => {
  // Helper para crear una venta válida base
  const ventaBaseValida: Venta = {
    id: "test-venta-valida",
    jornadaId: "jornada-1",
    camionId: 1,
    clienteId: 1,
    nombreCliente: "Cliente Test",
    fecha: new Date().toISOString(),
    medioPago: "efectivo",
    items: [
      {
        productoId: 1,
        nombreProducto: "Jamón",
        unidadMedida: "pieza",
        cantidad: 3,
        precioUnitario: 21,
        precioMediaPieza: 12,
        subtotal: 33,
      },
    ],
    total: 33,
  };

  it("A. Venta válida: venta_valida=true → persiste y actualiza", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const error = registrarVentaOperacion(ventaBaseValida, validarStock, cargar, guardar.fn);

    expect(error).toBeNull();
    expect(validarStock).toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(1);
    expect(guardar.getStore()[0].id).toBe(ventaBaseValida.id);
  });

  it("B. Pieza con snapshot adulterado (subtotal 32 vs 33) → rechazo, NO persistencia, NO callback", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const ventaInvalida: Venta = {
      ...ventaBaseValida,
      id: "test-venta-invalida-snapshot",
      items: [{ ...ventaBaseValida.items[0], subtotal: 32 }],
      total: 32,
    };

    const error = registrarVentaOperacion(ventaInvalida, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta no pasa la validación monetaria/estructural (ADR-003).");
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(0);
  });

  it("C. Total adulterado (item válido subtotal 33, venta.total = 32) → rechazo, NO persistencia, NO callback", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const ventaTotalMal: Venta = {
      ...ventaBaseValida,
      id: "test-venta-total-mal",
      total: 32,
    };

    const error = registrarVentaOperacion(ventaTotalMal, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta no pasa la validación monetaria/estructural (ADR-003).");
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(0);
  });

  it("D. Unidad con precioMediaPieza presente → rechazo antes de persistir", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const ventaUnidadConMedia: Venta = {
      ...ventaBaseValida,
      id: "test-venta-unidad-con-media",
      items: [
        {
          productoId: 2,
          nombreProducto: "Leche",
          unidadMedida: "unidad",
          cantidad: 3,
          precioUnitario: 100,
          precioMediaPieza: 50,
          subtotal: 300,
        },
      ],
      total: 300,
    };

    const error = registrarVentaOperacion(ventaUnidadConMedia, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta no pasa la validación monetaria/estructural (ADR-003).");
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(0);
  });

  it("E. Cantidad 0 → rechazo antes de persistir", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const ventaCantCero: Venta = {
      ...ventaBaseValida,
      id: "test-venta-cant-cero",
      items: [{ ...ventaBaseValida.items[0], cantidad: 0 }],
      total: 0,
    };

    const error = registrarVentaOperacion(ventaCantCero, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta no pasa la validación monetaria/estructural (ADR-003).");
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(0);
  });

  it("F. Cantidad decimal (1.5) → rechazo antes de persistir", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const ventaDecimal: Venta = {
      ...ventaBaseValida,
      id: "test-venta-decimal",
      items: [{ ...ventaBaseValida.items[0], cantidad: 1.5 }],
      total: 33,
    };

    const error = registrarVentaOperacion(ventaDecimal, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta no pasa la validación monetaria/estructural (ADR-003).");
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(0);
  });

  it("G. NaN en cantidad → rechazo antes de persistir", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const ventaNaN: Venta = {
      ...ventaBaseValida,
      id: "test-venta-nan",
      items: [{ ...ventaBaseValida.items[0], cantidad: NaN }],
      total: 33,
    };

    const error = registrarVentaOperacion(ventaNaN, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta no pasa la validación monetaria/estructural (ADR-003).");
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(0);
  });

  it("H. Infinity en cantidad → rechazo antes de persistir", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const ventaInf: Venta = {
      ...ventaBaseValida,
      id: "test-venta-inf",
      items: [{ ...ventaBaseValida.items[0], cantidad: Infinity }],
      total: 33,
    };

    const error = registrarVentaOperacion(ventaInf, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta no pasa la validación monetaria/estructural (ADR-003).");
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(0);
  });

  it("I. Cantidad negativa → rechazo antes de persistir", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const ventaNeg: Venta = {
      ...ventaBaseValida,
      id: "test-venta-neg",
      items: [{ ...ventaBaseValida.items[0], cantidad: -1 }],
      total: 33,
    };

    const error = registrarVentaOperacion(ventaNeg, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta no pasa la validación monetaria/estructural (ADR-003).");
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(0);
  });

  it("J. Pieza SIN precioMediaPieza → rechazo antes de persistir", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const ventaSinMedia: Venta = {
      ...ventaBaseValida,
      id: "test-venta-sin-media",
      items: [{ ...ventaBaseValida.items[0], precioMediaPieza: undefined }],
      total: 33,
    };

    const error = registrarVentaOperacion(ventaSinMedia, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta no pasa la validación monetaria/estructural (ADR-003).");
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(0);
  });

  it("K. Precio monetariamente inválido (negativo) → rechazo antes de persistir", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const ventaPrecioNeg: Venta = {
      ...ventaBaseValida,
      id: "test-venta-precio-neg",
      items: [{ ...ventaBaseValida.items[0], precioUnitario: -10 }],
      total: 33,
    };

    const error = registrarVentaOperacion(ventaPrecioNeg, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta no pasa la validación monetaria/estructural (ADR-003).");
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(0);
  });

  it("L. Duplicado de ID → rechazo antes de callback", () => {
    const cargar = crearCargarActuales([ventaBaseValida]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const error = registrarVentaOperacion(ventaBaseValida, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta ya fue registrada.");
    expect(validarStock).not.toHaveBeenCalled();
    // El store de cargar no debe modificarse
    expect(cargar().length).toBe(1);
  });

  it("M. Validación de stock falla → rechazo, NO persistencia", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue("Stock insuficiente");

    const error = registrarVentaOperacion(ventaBaseValida, validarStock, cargar, guardar.fn);

    expect(error).toBe("Stock insuficiente");
    expect(validarStock).toHaveBeenCalled();
    expect(guardar.getStore().length).toBe(0);
  });
});
