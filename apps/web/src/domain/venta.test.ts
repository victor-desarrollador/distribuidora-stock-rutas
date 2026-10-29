// Pruebas del armado y la validación de ventas del demo en B3 (ADR-005).
//
// Estado B3 (en curso):
//   - Las ventas de productos `unidad` funcionan igual que antes.
//   - Construcción: una línea `peso` se arma en gramos enteros con precio por
//     kg y subtotal según D-R1 (ADR-005 §2.3.3). Una venta mixta
//     `unidad` + `peso` se rechaza (falla cerrado).
//   - Lectura/histórico (`item_valido`, `venta_valida`): valida estructura y
//     total = suma de subtotales almacenados, SIN recalcular cantidad × precio
//     (ADR-005 §2.3.4). Un subtotal `peso` debe ser entero en pesos.
//   - Escritura nueva (`venta_nueva_valida`): además cada subtotal debe
//     coincidir con la regla vigente (`unidad`: cantidad × precio; `peso`: D-R1).
//   - Una venta mixta `unidad` + `peso` es inválida al leer y al escribir.
//   - `precioMediaPieza` sigue en el tipo DetalleVenta como deuda legacy de
//     ADR-003, pero ninguna venta nueva lo genera y una línea que lo traiga
//     es inválida.
//   - No se fija ninguna regla monetaria nueva para líneas `unidad` ni para
//     documentos mixtos (pendiente de BLUEPRINT.md §15).
import { describe, it, expect, vi } from "vitest";
import {
  construirDetalleVenta,
  construirItemsVenta,
  es_venta_mixta,
  MENSAJE_VENTA_MIXTA_NO_HABILITADA,
  MENSAJE_VENTA_PRODUCTO_REPETIDO,
  tiene_productos_repetidos,
} from "./venta";
import {
  item_valido,
  subtotal_coincide,
  venta_nueva_valida,
  venta_valida,
} from "./validacion";
import {
  registrarVentaOperacion,
  type LectorasVenta,
} from "../hooks/registroVentas";
import type { Jornada } from "../data/mockJornadas";
import type { DetalleVenta, Venta } from "../data/mockVentas";

const ERROR_VALIDACION =
  "La venta no pasa la validación monetaria/estructural (ADR-003).";

const lecheParams = {
  productoId: 2,
  nombreProducto: "Leche",
  unidadMedida: "unidad" as const,
  cantidadCanonica: 3,
  precioReferencia: 100,
};

// Línea `peso`: 1250 g a 12500/kg. Su subtotal D-R1 vigente es 15625; otros
// valores representan un histórico que no se recalcula o un subtotal adulterado.
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

describe("construirDetalleVenta — peso (D-R1)", () => {
  it("1250 g a 1234.56/kg → cantidad=1250, precioUnitario=1234.56, subtotal=1543", () => {
    const item = construirDetalleVenta({
      productoId: 4,
      nombreProducto: "Jamón cocido",
      unidadMedida: "peso",
      cantidadCanonica: 1250,
      precioReferencia: 1234.56,
    });

    expect(item.cantidad).toBe(1250);
    expect(item.unidadMedida).toBe("peso");
    expect(item.precioUnitario).toBe(1234.56);
    expect(item.subtotal).toBe(1543);
    expect("precioMediaPieza" in item).toBe(false);
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

  it("una lista sólo con producto peso construye la línea en gramos con subtotal D-R1", () => {
    const productos = [
      {
        productoId: 4,
        nombreProducto: "Jamón cocido",
        unidadMedida: "peso" as const,
        precioReferencia: 1234.56,
      },
    ];

    const items = construirItemsVenta({
      productos,
      obtenerCantidadCanonica: () => 1250,
    });

    expect(items).toHaveLength(1);
    expect(items[0].cantidad).toBe(1250);
    expect(items[0].unidadMedida).toBe("peso");
    expect(items[0].precioUnitario).toBe(1234.56);
    expect(items[0].subtotal).toBe(1543);
  });

  it("rechaza una venta mixta (unidad + peso con cantidad > 0)", () => {
    const productos = [
      {
        productoId: 2,
        nombreProducto: "Leche",
        unidadMedida: "unidad" as const,
        precioReferencia: 100,
      },
      {
        productoId: 4,
        nombreProducto: "Jamón cocido",
        unidadMedida: "peso" as const,
        precioReferencia: 1234.56,
      },
    ];

    expect(() =>
      construirItemsVenta({
        productos,
        obtenerCantidadCanonica: (id) => (id === 2 ? 3 : 1250),
      })
    ).toThrow(MENSAJE_VENTA_MIXTA_NO_HABILITADA);
  });
});

describe("tiene_productos_repetidos (AUD-B3-01)", () => {
  // Simula un array leído de JSON corrupto: el tipo productivo no admite null.
  const malformado = (items: unknown[]) =>
    items as unknown as Parameters<typeof tiene_productos_repetidos>[0];

  it("dos líneas del mismo producto unidad → true", () => {
    expect(tiene_productos_repetidos([{ productoId: 2 }, { productoId: 2 }])).toBe(true);
  });

  it("dos líneas del mismo producto peso → true", () => {
    expect(
      tiene_productos_repetidos([lineaPeso(15625), { ...lineaPeso(15625), cantidad: 1 }])
    ).toBe(true);
  });

  it("el mismo productoId con unidades distintas → true (independiente de la unidad)", () => {
    const mismoProductoPorUnidad: DetalleVenta = { ...lineaPeso(15625), unidadMedida: "unidad" };
    expect(tiene_productos_repetidos([lineaPeso(15625), mismoProductoPorUnidad])).toBe(true);
  });

  it("productos distintos → false", () => {
    expect(tiene_productos_repetidos([{ productoId: 1 }, { productoId: 2 }])).toBe(false);
  });

  it("ítems malformados no cuentan como repetidos y no lanza", () => {
    const items = malformado([null, null, { productoId: "x" }, { productoId: 1 }]);
    expect(() => tiene_productos_repetidos(items)).not.toThrow();
    expect(tiene_productos_repetidos(items)).toBe(false);
  });
});

describe("es_venta_mixta", () => {
  // Simula un array leído de JSON corrupto: el tipo productivo no admite null.
  const malformado = (items: unknown[]) =>
    items as unknown as Parameters<typeof es_venta_mixta>[0];

  it("unidad + peso → true", () => {
    expect(es_venta_mixta([{ unidadMedida: "unidad" }, { unidadMedida: "peso" }])).toBe(true);
  });

  it("sólo unidad → false", () => {
    expect(es_venta_mixta([{ unidadMedida: "unidad" }, { unidadMedida: "unidad" }])).toBe(false);
  });

  it("sólo peso → false", () => {
    expect(es_venta_mixta([{ unidadMedida: "peso" }])).toBe(false);
  });

  it("null junto a unidad → false, sin lanzar", () => {
    const items = malformado([null, { unidadMedida: "unidad" }]);
    expect(() => es_venta_mixta(items)).not.toThrow();
    expect(es_venta_mixta(items)).toBe(false);
  });

  it("null junto a unidad + peso → true, sin lanzar", () => {
    const items = malformado([{ unidadMedida: "unidad" }, null, { unidadMedida: "peso" }]);
    expect(() => es_venta_mixta(items)).not.toThrow();
    expect(es_venta_mixta(items)).toBe(true);
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

  it("subtotal ≠ cantidad × precio: válido como histórico, no coincide con la regla vigente", () => {
    const item = { ...construirDetalleVenta(lecheParams), subtotal: 999 };
    expect(item_valido(item)).toBe(true);
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

  it("línea peso con subtotal D-R1 (15625) es válida y coincide con la regla vigente", () => {
    expect(item_valido(lineaPeso(15625))).toBe(true);
    expect(subtotal_coincide(lineaPeso(15625))).toBe(true);
  });

  it("línea peso histórica con subtotal entero (123) es válida sin recalcular D-R1", () => {
    expect(item_valido(lineaPeso(123))).toBe(true);
    expect(subtotal_coincide(lineaPeso(123))).toBe(false);
  });

  it.each([1543.5, 1543.2, 0.01])(
    "línea peso con subtotal no entero (%s) es estructuralmente inválida",
    (subtotal) => {
      expect(item_valido(lineaPeso(subtotal))).toBe(false);
    }
  );
});

describe("Snapshot histórico de una línea unidad", () => {
  it("snapshot 21 × 3 = 63 → válido; 62 → válido como histórico, no coincide con la vigente", () => {
    const item: DetalleVenta = {
      productoId: 2,
      nombreProducto: "Leche histórica",
      unidadMedida: "unidad",
      cantidad: 3,
      precioUnitario: 21,
      subtotal: 63,
    };

    expect(item_valido(item)).toBe(true);
    expect(item_valido({ ...item, subtotal: 62 })).toBe(true);
    expect(subtotal_coincide({ ...item, subtotal: 62 })).toBe(false);
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

  it("una venta mixta unidad + peso es inválida al leer y al escribir", () => {
    const venta: Venta = {
      ...ventaBase,
      items: [...ventaBase.items, lineaPeso(15625)],
      total: 16125,
    };
    expect(venta_valida(venta)).toBe(false);
    expect(venta_nueva_valida(venta)).toBe(false);
  });

  it("venta unidad con subtotal almacenado ≠ cantidad × precio: válida como histórico, rechazada como nueva (ADR-005 §2.3.4)", () => {
    const venta: Venta = {
      ...ventaBase,
      items: [{ ...ventaBase.items[0], subtotal: 290 }], // vigente: 3 × 100 = 300
      total: 290,
    };
    expect(venta_valida(venta)).toBe(true);
    expect(venta_nueva_valida(venta)).toBe(false);
  });

  it("venta sólo peso histórica con total = suma de subtotales almacenados es válida", () => {
    expect(venta_valida({ ...ventaBase, items: [lineaPeso(123)], total: 123 })).toBe(true);
  });

  it("total ≠ suma de subtotales almacenados es inválido", () => {
    expect(venta_valida({ ...ventaBase, total: 501 })).toBe(false);
  });

  it("venta sin ítems (total 0): válida como histórico, rechazada como nueva", () => {
    const vacia: Venta = { ...ventaBase, items: [], total: 0 };
    expect(venta_valida(vacia)).toBe(true);
    expect(venta_nueva_valida(vacia)).toBe(false);
  });

  it("líneas repetidas del mismo producto: legibles como histórico, rechazadas como nueva", () => {
    const repetida: Venta = {
      ...ventaBase,
      items: [ventaBase.items[0], { ...ventaBase.items[0] }],
      total: 600,
    };
    expect(venta_valida(repetida)).toBe(true);
    expect(venta_nueva_valida(repetida)).toBe(false);
  });
});

/**
 * Frontera de escritura (M-1, AUD-001): registrarVentaOperacion valida con
 * lectoras de DATOS (nunca validadores del caller) y no escribe: devuelve el
 * ledger resultante. Una venta inválida se rechaza ANTES de leer ningún
 * ledger. La escritura real y sus adversariales están en
 * hooks/registroVentas.test.ts.
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

  // Jornada abierta del camión 1: Leche 10 unidades y Jamón 5000 g.
  const jornadaFrontera: Jornada = {
    id: "jornada-1",
    camionId: 1,
    chofer: "Chofer",
    zona: "Zona",
    fechaCreacion: "2026-10-28T08:00:00.000Z",
    fechaSalida: "2026-10-28T09:00:00.000Z",
    estado: "abierta",
    items: [
      {
        productoId: 2,
        nombreProducto: "Leche",
        unidadMedida: "unidad",
        cantidad: 10,
        precioReferencia: 100,
      },
      {
        productoId: 4,
        nombreProducto: "Jamón cocido",
        unidadMedida: "peso",
        cantidad: 5000,
        precioReferencia: 12500,
      },
    ],
  };

  function lectoras(datos: { ventas?: Venta[]; jornadas?: Jornada[] } = {}) {
    return {
      ventas: vi.fn<LectorasVenta["ventas"]>(() => ({
        ok: true,
        ventas: [...(datos.ventas ?? [])],
        estado: "valido",
      })),
      jornadas: vi.fn<LectorasVenta["jornadas"]>(() => ({
        ok: true,
        jornadas: datos.jornadas ?? [jornadaFrontera],
        estado: "valido",
      })),
      movimientos: vi.fn<LectorasVenta["movimientos"]>(() => ({
        ok: true,
        movimientos: [],
        estado: "valido",
      })),
    };
  }

  function rechazaSinEfectos(
    venta: Venta,
    mensaje: string = ERROR_VALIDACION
  ) {
    const leer = lectoras();

    expect(registrarVentaOperacion(venta, leer)).toEqual({
      ok: false,
      error: mensaje,
    });
    expect(leer.ventas).not.toHaveBeenCalled();
    expect(leer.jornadas).not.toHaveBeenCalled();
    expect(leer.movimientos).not.toHaveBeenCalled();
  }

  it("A. Venta unidad válida → ledger resultante, tras releer los tres ledgers", () => {
    const leer = lectoras();

    expect(registrarVentaOperacion(ventaBaseValida, leer)).toEqual({
      ok: true,
      ventas: [ventaBaseValida],
    });
    expect(leer.ventas).toHaveBeenCalledTimes(1);
    expect(leer.jornadas).toHaveBeenCalledTimes(1);
    expect(leer.movimientos).toHaveBeenCalledTimes(1);
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

  it("G. Línea peso con subtotal ≠ D-R1 → rechazo sin efectos", () => {
    rechazaSinEfectos({
      ...ventaBaseValida,
      items: [lineaPeso(123)],
      total: 123,
    });
  });

  it("G2. Venta sólo peso con subtotal D-R1 → ledger resultante", () => {
    const venta: Venta = { ...ventaBaseValida, items: [lineaPeso(15625)], total: 15625 };

    expect(registrarVentaOperacion(venta, lectoras())).toEqual({
      ok: true,
      ventas: [venta],
    });
  });

  it("J. Venta mixta unidad + peso → mensaje específico, sin efectos", () => {
    rechazaSinEfectos(
      {
        ...ventaBaseValida,
        items: [...ventaBaseValida.items, lineaPeso(15625)],
        total: 15925, // 300 + 15625
      },
      MENSAJE_VENTA_MIXTA_NO_HABILITADA
    );
  });

  it("K. Venta nueva sin ítems → rechazo sin efectos", () => {
    rechazaSinEfectos({ ...ventaBaseValida, items: [], total: 0 });
  });

  it("L. Dos líneas del mismo producto → mensaje específico, sin efectos", () => {
    rechazaSinEfectos(
      {
        ...ventaBaseValida,
        items: [ventaBaseValida.items[0], { ...ventaBaseValida.items[0] }],
        total: 600,
      },
      MENSAJE_VENTA_PRODUCTO_REPETIDO
    );
  });

  it("H. Duplicado de ID → rechazo sin leer jornadas ni movimientos", () => {
    const leer = lectoras({ ventas: [ventaBaseValida] });

    expect(registrarVentaOperacion(ventaBaseValida, leer)).toEqual({
      ok: false,
      error: "La venta ya fue registrada.",
    });
    expect(leer.jornadas).not.toHaveBeenCalled();
    expect(leer.movimientos).not.toHaveBeenCalled();
  });

  it("I. Stock insuficiente según la jornada releída → rechazo (sin callback)", () => {
    const leer = lectoras({
      jornadas: [
        {
          ...jornadaFrontera,
          items: [{ ...jornadaFrontera.items[0], cantidad: 2 }],
        },
      ],
    });

    expect(registrarVentaOperacion(ventaBaseValida, leer)).toEqual({
      ok: false,
      error: "Stock insuficiente de Leche.",
    });
  });
});
