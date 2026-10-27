// Pruebas del armado y la validación de ventas del demo en B1 (ADR-005).
//
// Estado B1:
//   - Las ventas de productos `unidad` funcionan igual que antes.
//   - Las ventas de productos `peso` están bloqueadas hasta B3: su importe
//     depende de D-R1 y Autoventa por peso todavía no está migrada. Una línea
//     `peso` es inválida independientemente del subtotal provisto; este
//     archivo NO calcula ni verifica ningún importe por peso.
//   - `precioMediaPieza` sigue en el tipo DetalleVenta como deuda legacy de
//     ADR-003 (B3), pero ninguna venta nueva lo genera y una línea que lo
//     traiga es inválida.
//   - No se fija ninguna regla monetaria nueva para líneas `unidad` ni para
//     documentos mixtos (pendiente de BLUEPRINT.md §15).
import { describe, it, expect, vi } from "vitest";
import { construirDetalleVenta, construirItemsVenta } from "./venta";
import { item_valido, subtotal_coincide, venta_valida } from "./validacion";
import { MENSAJE_PESO_NO_OPERABLE } from "./productos";
import { registrarVentaOperacion } from "../hooks/useVentas";
import type { DetalleVenta, Venta } from "../data/mockVentas";

const ERROR_VALIDACION =
  "La venta no pasa la validación monetaria/estructural (ADR-003).";

// Helper para crear ventas actuales simuladas
const crearCargarActuales = (inicial: Venta[] = []) => {
  const store = [...inicial];
  return (): { ok: true; ventas: Venta[]; estado: "valido" } => ({
    ok: true,
    ventas: [...store],
    estado: "valido",
  });
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

const lecheParams = {
  productoId: 2,
  nombreProducto: "Leche",
  unidadMedida: "unidad" as const,
  cantidadCanonica: 3,
  precioReferencia: 100,
};

// Línea `peso` sólo estructural (gramos enteros). El subtotal es un valor
// ARBITRARIO sin significado monetario: en B1 la línea se rechaza antes de
// cualquier cálculo, así que no se valida ni se calcula D-R1.
const lineaPeso = (subtotal_arbitrario: number): DetalleVenta => ({
  productoId: 4,
  nombreProducto: "Jamón cocido",
  unidadMedida: "peso",
  cantidad: 1250,
  precioUnitario: 12500,
  subtotal: subtotal_arbitrario,
});

describe("construirDetalleVenta — unidad", () => {
  it("unidad precio 100, cantidad 3 → precioUnitario=100, subtotal=300", () => {
    const item = construirDetalleVenta(lecheParams);

    expect(item.precioUnitario).toBe(100);
    expect(item.subtotal).toBe(300);
    expect(item.unidadMedida).toBe("unidad");
    expect(item.cantidad).toBe(3);
  });

  it("una venta nueva no genera precioMediaPieza", () => {
    const item = construirDetalleVenta(lecheParams);
    expect("precioMediaPieza" in item).toBe(false);
  });

  it.each([1.5, NaN, Infinity, -1, 0])("rechaza cantidad %s", (cantidad) => {
    expect(() =>
      construirDetalleVenta({ ...lecheParams, cantidadCanonica: cantidad })
    ).toThrow("Cantidad canónica inválida");
  });

  it("rechaza precio negativo", () => {
    expect(() =>
      construirDetalleVenta({ ...lecheParams, precioReferencia: -10 })
    ).toThrow("Precio de referencia inválido");
  });
});

describe("construirDetalleVenta — peso bloqueado en B1 (B3)", () => {
  it("rechaza un producto peso con el guard de B1", () => {
    expect(() =>
      construirDetalleVenta({
        productoId: 4,
        nombreProducto: "Jamón cocido",
        unidadMedida: "peso",
        cantidadCanonica: 1250,
        precioReferencia: 12500,
      })
    ).toThrow(MENSAJE_PESO_NO_OPERABLE);
  });
});

describe("construirItemsVenta — múltiples productos", () => {
  it("construye items unidad sin precioMediaPieza", () => {
    const productos = [
      { productoId: 1, nombreProducto: "Yogur", unidadMedida: "unidad" as const, precioReferencia: 2300 },
      { productoId: 2, nombreProducto: "Leche", unidadMedida: "unidad" as const, precioReferencia: 100 },
    ];

    const items = construirItemsVenta({
      productos,
      obtenerCantidadCanonica: (id) => (id === 1 ? 1 : 2),
    });

    expect(items).toHaveLength(2);
    expect(items.map((i) => [i.productoId, i.cantidad])).toEqual([[1, 1], [2, 2]]);
    items.forEach((i) => expect("precioMediaPieza" in i).toBe(false));
  });

  it("filtra productos con cantidad 0 (también un peso sin cantidad)", () => {
    const productos = [
      { productoId: 2, nombreProducto: "Leche", unidadMedida: "unidad" as const, precioReferencia: 100 },
      { productoId: 4, nombreProducto: "Jamón cocido", unidadMedida: "peso" as const, precioReferencia: 12500 },
    ];

    const items = construirItemsVenta({ productos, obtenerCantidadCanonica: () => 0 });

    expect(items).toHaveLength(0);
  });

  it("un producto peso con cantidad > 0 se rechaza con el guard de B1", () => {
    const productos = [
      { productoId: 4, nombreProducto: "Jamón cocido", unidadMedida: "peso" as const, precioReferencia: 12500 },
    ];

    expect(() =>
      construirItemsVenta({ productos, obtenerCantidadCanonica: () => 1250 })
    ).toThrow(MENSAJE_PESO_NO_OPERABLE);
  });
});

describe("item_valido (validador compartido con useVentas)", () => {
  it("una línea unidad construida pasa la validación", () => {
    expect(item_valido(construirDetalleVenta(lecheParams))).toBe(true);
  });

  it("una línea unidad CON precioMediaPieza es inválida", () => {
    const item = { ...construirDetalleVenta(lecheParams), precioMediaPieza: 50 };
    expect(item_valido(item)).toBe(false);
  });

  it("subtotal incorrecto es inválido", () => {
    const item = { ...construirDetalleVenta(lecheParams), subtotal: 999 };
    expect(item_valido(item)).toBe(false);
    expect(subtotal_coincide(item)).toBe(false);
  });

  it("cantidad cero es inválida", () => {
    const item = { ...construirDetalleVenta(lecheParams), cantidad: 0 };
    expect(item_valido(item)).toBe(false);
  });

  it("'pieza' es inválida", () => {
    const item = {
      ...construirDetalleVenta(lecheParams),
      unidadMedida: "pieza",
      precioMediaPieza: 50,
    } as unknown as DetalleVenta;
    expect(item_valido(item)).toBe(false);
  });

  it.each([0, 123])(
    "una línea peso es inválida en B1 independientemente del subtotal (%s)",
    (subtotal_arbitrario) => {
      expect(item_valido(lineaPeso(subtotal_arbitrario))).toBe(false);
      expect(subtotal_coincide(lineaPeso(subtotal_arbitrario))).toBe(false);
    }
  );
});

describe("Snapshot histórico de una línea unidad", () => {
  it("snapshot precio 21 × 3 = 63 → válido; 62 → inválido", () => {
    const item: DetalleVenta = {
      productoId: 2,
      nombreProducto: "Leche histórica",
      unidadMedida: "unidad",
      cantidad: 3,
      precioUnitario: 21,
      subtotal: 63,
    };

    expect(item_valido(item)).toBe(true);
    expect(item_valido({ ...item, subtotal: 62 })).toBe(false);
  });
});

describe("venta_valida", () => {
  const ventaBase: Venta = {
    id: "test-venta-1",
    jornadaId: "jornada-1",
    camionId: 1,
    clienteId: 1,
    nombreCliente: "Cliente Test",
    fecha: new Date().toISOString(),
    medioPago: "efectivo",
    items: [
      {
        productoId: 2,
        nombreProducto: "Leche",
        unidadMedida: "unidad",
        cantidad: 3,
        precioUnitario: 100,
        subtotal: 300,
      },
      {
        productoId: 1,
        nombreProducto: "Yogur",
        unidadMedida: "unidad",
        cantidad: 2,
        precioUnitario: 100,
        subtotal: 200,
      },
    ],
    total: 500,
  };

  it("una venta unidad con total = suma de subtotales es válida", () => {
    expect(venta_valida(ventaBase)).toBe(true);
  });

  it("una venta con una línea peso es inválida en B1 (no se calcula D-R1)", () => {
    // total coherente sólo con el objeto armado (500 + 123 arbitrario).
    const venta: Venta = {
      ...ventaBase,
      items: [...ventaBase.items, lineaPeso(123)],
      total: 623,
    };
    expect(venta_valida(venta)).toBe(false);
  });
});

/**
 * Frontera de escritura (M-1): registrarVentaOperacion debe rechazar ventas
 * inválidas ANTES de leer, ejecutar el callback de stock o persistir.
 */
describe("Frontera de escritura: registrarVentaOperacion", () => {
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
        productoId: 2,
        nombreProducto: "Leche",
        unidadMedida: "unidad",
        cantidad: 3,
        precioUnitario: 100,
        subtotal: 300,
      },
    ],
    total: 300,
  };

  function rechazaSinEfectos(venta: Venta) {
    const cargar = vi.fn(crearCargarActuales([]));
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const error = registrarVentaOperacion(venta, validarStock, cargar, guardar.fn);

    expect(error).toBe(ERROR_VALIDACION);
    expect(cargar).not.toHaveBeenCalled();
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.fn).not.toHaveBeenCalled();
  }

  it("A. Venta unidad válida → persiste", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const error = registrarVentaOperacion(ventaBaseValida, validarStock, cargar, guardar.fn);

    expect(error).toBeNull();
    expect(validarStock).toHaveBeenCalled();
    expect(guardar.getStore().map((v) => v.id)).toEqual([ventaBaseValida.id]);
  });

  it("B. Subtotal adulterado → rechazo sin efectos", () => {
    rechazaSinEfectos({
      ...ventaBaseValida,
      items: [{ ...ventaBaseValida.items[0], subtotal: 299 }],
      total: 299,
    });
  });

  it("C. Total adulterado → rechazo sin efectos", () => {
    rechazaSinEfectos({ ...ventaBaseValida, total: 299 });
  });

  it("D. Unidad con precioMediaPieza → rechazo sin efectos", () => {
    rechazaSinEfectos({
      ...ventaBaseValida,
      items: [{ ...ventaBaseValida.items[0], precioMediaPieza: 50 }],
    });
  });

  it.each([0, 1.5, NaN, Infinity, -1])("E. Cantidad %s → rechazo sin efectos", (cantidad) => {
    rechazaSinEfectos({
      ...ventaBaseValida,
      items: [{ ...ventaBaseValida.items[0], cantidad }],
    });
  });

  it("F. Precio negativo → rechazo sin efectos", () => {
    rechazaSinEfectos({
      ...ventaBaseValida,
      items: [{ ...ventaBaseValida.items[0], precioUnitario: -10 }],
    });
  });

  it("G. Línea peso → rechazo sin efectos, sin calcular D-R1 (B3)", () => {
    rechazaSinEfectos({
      ...ventaBaseValida,
      items: [lineaPeso(123)],
      total: 123,
    });
  });

  it("H. Duplicado de ID → rechazo antes del callback", () => {
    const cargar = crearCargarActuales([ventaBaseValida]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue(null);

    const error = registrarVentaOperacion(ventaBaseValida, validarStock, cargar, guardar.fn);

    expect(error).toBe("La venta ya fue registrada.");
    expect(validarStock).not.toHaveBeenCalled();
    expect(guardar.fn).not.toHaveBeenCalled();
  });

  it("I. Validación de stock falla → no persiste", () => {
    const cargar = crearCargarActuales([]);
    const guardar = crearGuardarActualizadas();
    const validarStock = vi.fn().mockReturnValue("Stock insuficiente");

    const error = registrarVentaOperacion(ventaBaseValida, validarStock, cargar, guardar.fn);

    expect(error).toBe("Stock insuficiente");
    expect(guardar.fn).not.toHaveBeenCalled();
  });
});
