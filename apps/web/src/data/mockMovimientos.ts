
import type { UnidadMedida } from "./mockProductos";

export type TipoMovimiento =
  | "merma"
  | "devolucion"
  | "cambio";

export interface ProductoMovimiento {
  productoId: number;
  nombreProducto: string;
  unidadMedida: UnidadMedida;
  cantidad: number;
}

interface MovimientoBase {
  id: string;
  jornadaId: string;
  camionId: number;
  fecha: string;
  motivo: string;
}

export type MovimientoReparto =
  | (MovimientoBase & {
      tipo: "merma";
      producto: ProductoMovimiento;
      clienteId: null;
      nombreCliente: null;
    })
  | (MovimientoBase & {
      tipo: "devolucion";
      producto: ProductoMovimiento;
      clienteId: number;
      nombreCliente: string;
    })
  | (MovimientoBase & {
      tipo: "cambio";
      clienteId: number;
      nombreCliente: string;
      productoDevuelto: ProductoMovimiento;
      productoEntregado: ProductoMovimiento;
    });

// Cantidad que deja de estar disponible para vender.
export function salidasPorMovimiento(
  movimiento: MovimientoReparto
): ProductoMovimiento[] {
  if (movimiento.tipo === "merma") {
    return [movimiento.producto];
  }

  if (movimiento.tipo === "cambio") {
    return [movimiento.productoEntregado];
  }

  // Una devolución no descuenta mercadería cargada.
  return [];
}
