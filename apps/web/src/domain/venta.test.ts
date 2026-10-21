import { describe, it, expect } from "vitest";
import { construirDetalleVenta, construirItemsVenta } from "./venta";
import { item_valido, subtotal_coincide, venta_valida } from "./validacion";
import { sumar_importes } from "./precios";
import type { DetalleVenta, Venta } from "../data/mockVentas";

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
    // Mutar el snapshot para simular error
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
    // Mutar para agregar precioMediaPieza donde no debe estar
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
    // Mutar para quitar precioMediaPieza
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
    // Mutar subtotal
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
    // Mutar cantidad a 0
    const itemConError = { ...item, cantidad: 0 };
    expect(item_valido(itemConError)).toBe(false);
  });
});

describe("Snapshot histórico: validación usa snapshot guardado, NO recalcula ADR-003", () => {
  /**
   * Demuestra que la validación histórica usa el snapshot guardado en precioMediaPieza
   * y NO recalcula con precio_media_pieza(precioUnitario).
   */

  it("detalle pieza con snapshot histórico 21/12/3/33 → VÁLIDO (subtotal coincide con snapshot)", () => {
    // precioUnitario = 21 (pieza completa)
    // precioMediaPieza = 12 (snapshot histórico, PUEDE ser distinto al derivado actual 11)
    // cantidad = 3 (1 pieza + media)
    // subtotal = 33 (calculado con el snapshot 12: 21 + 12 = 33)
    const item: DetalleVenta = {
      productoId: 1,
      nombreProducto: "Jamón histórico",
      unidadMedida: "pieza",
      cantidad: 3,
      precioUnitario: 21,
      precioMediaPieza: 12, // Snapshot histórico (distinto al ADR-003 actual que daría 11)
      subtotal: 33, // 21 + 12 = 33 (con snapshot 12)
    };

    // Debe ser VÁLIDO porque usa el snapshot guardado, no recalcula ADR-003
    expect(item_valido(item)).toBe(true);
    expect(subtotal_coincide(item)).toBe(true);
  });

  it("mismo snapshot 21/12/3 pero subtotal 32 → INVÁLIDO (no coincide con snapshot)", () => {
    // precioUnitario = 21
    // precioMediaPieza = 12 (snapshot)
    // cantidad = 3
    // subtotal = 32 (INCORRECTO: con snapshot 12 debería ser 33; 32 sería el cálculo ADR-003 actual)
    const item: DetalleVenta = {
      productoId: 1,
      nombreProducto: "Jamón histórico",
      unidadMedida: "pieza",
      cantidad: 3,
      precioUnitario: 21,
      precioMediaPieza: 12,
      subtotal: 32, // ¡Error! Con snapshot 12 el subtotal debe ser 33
    };

    // Debe ser INVÁLIDO porque subtotal no coincide con el snapshot
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
          precioMediaPieza: 12, // Snapshot histórico
          subtotal: 33, // 21 + 12
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
      total: 233, // 33 + 200
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
    expect(total).toBe(11 + 300); // 311
  });
});
