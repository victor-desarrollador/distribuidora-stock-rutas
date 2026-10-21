
export type MedioPago =
  | "efectivo"
  | "transferencia"
  | "cuenta_corriente";

export interface DetalleVenta {
  productoId: number;
  nombreProducto: string;
  unidadMedida: "unidad" | "pieza";
  cantidad: number;
  // Precios aplicados al vender (historial, ADR-002).
  // unidad: precio unitario. pieza: precio de pieza completa.
  precioUnitario: number;
  // Solo pieza: precio de media pieza aplicado.
  precioMediaPieza?: number;
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
