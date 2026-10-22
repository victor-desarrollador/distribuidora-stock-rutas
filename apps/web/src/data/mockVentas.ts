export type MedioPago =
  | "efectivo"
  | "transferencia"
  | "cuenta_corriente";

export interface DetalleVenta {
  productoId: number;
  nombreProducto: string;
  unidadMedida: "unidad" | "pieza";
  cantidad: number;
  // Precios aplicados al vender (historial, ADR-003).
  // unidad: precio unitario. pieza: precio de pieza completa.
  precioUnitario: number;
  // Solo pieza: precio de media pieza APLICADO (snapshot histórico derivado al momento de la venta).
  // NO es precio configurable del producto; es el precio de media derivado vigente al momento de la venta.
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