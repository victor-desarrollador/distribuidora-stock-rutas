
export type MedioPago =
  | "efectivo"
  | "transferencia"
  | "cuenta_corriente";

export interface DetalleVenta {
  productoId: number;
  nombreProducto: string;
  unidadMedida: "unidad" | "pieza";
  cantidad: number;
  precioUnitario: number;
  subtotal: number;
}

export interface Venta {
  id: string;
  jornadaId: string;
  camionId: number;
  clienteId: number;

  // Copia del comercio al momento de vender.
  nombreCliente: string;

  fecha: string;
  medioPago: MedioPago;
  items: DetalleVenta[];
  total: number;
}
