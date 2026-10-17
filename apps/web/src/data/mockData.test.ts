// Pruebas de caracterización del prototipo: documentan el comportamiento
// actual de los datos demo, no las reglas del BLUEPRINT.
import { describe, expect, it } from "vitest";
import { camionesIniciales } from "./mockCamiones";
import { clientesIniciales } from "./mockClientes";
import {
  salidasPorMovimiento,
  type MovimientoReparto,
  type ProductoMovimiento,
} from "./mockMovimientos";
import { productosIniciales } from "./mockProductos";

function idsUnicos(items: { id: number }[]) {
  return new Set(items.map((item) => item.id)).size === items.length;
}

describe("datos demo", () => {
  it("productos, clientes y camiones tienen ids únicos", () => {
    expect(idsUnicos(productosIniciales)).toBe(true);
    expect(idsUnicos(clientesIniciales)).toBe(true);
    expect(idsUnicos(camionesIniciales)).toBe(true);
  });
});

describe("salidasPorMovimiento", () => {
  const yogur: ProductoMovimiento = {
    productoId: 1,
    nombreProducto: "Yogur bebible 1 L",
    unidadMedida: "unidad",
    cantidad: 3,
  };
  const queso: ProductoMovimiento = {
    productoId: 2,
    nombreProducto: "Queso cremoso",
    unidadMedida: "pieza",
    cantidad: 1,
  };
  const base = {
    id: "m1",
    jornadaId: "j1",
    camionId: 1,
    fecha: "2026-10-12",
    motivo: "prueba",
  };

  it("una merma descuenta el producto mermado", () => {
    const movimiento: MovimientoReparto = {
      ...base,
      tipo: "merma",
      producto: yogur,
      clienteId: null,
      nombreCliente: null,
    };
    expect(salidasPorMovimiento(movimiento)).toEqual([yogur]);
  });

  it("un cambio descuenta solo el producto entregado", () => {
    const movimiento: MovimientoReparto = {
      ...base,
      tipo: "cambio",
      clienteId: 1,
      nombreCliente: "Cliente",
      productoDevuelto: yogur,
      productoEntregado: queso,
    };
    expect(salidasPorMovimiento(movimiento)).toEqual([queso]);
  });

  it("una devolución no descuenta mercadería cargada", () => {
    const movimiento: MovimientoReparto = {
      ...base,
      tipo: "devolucion",
      producto: yogur,
      clienteId: 1,
      nombreCliente: "Cliente",
    };
    expect(salidasPorMovimiento(movimiento)).toEqual([]);
  });
});
