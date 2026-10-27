import type { UnidadMedida } from "./mockProductos";

export type MedioPago =
  | "efectivo"
  | "transferencia"
  | "cuenta_corriente";

export interface DetalleVenta {
  productoId: number;
  nombreProducto: string;
  unidadMedida: UnidadMedida;
  // Entero canónico: unidades (unidad) o gramos (peso).
  cantidad: number;
  // Precios aplicados al vender (historial, ADR-003).
  // unidad: precio unitario. pieza: precio de pieza completa.
  precioUnitario: number;
  // Solo pieza: precio de media pieza APLICADO (snapshot histórico derivado al momento de la venta).
  // NO es precio configurable del producto; es el precio de media derivado vigente al momento de la venta.
  // Legacy ADR-003, se revisa en B3. En el modelo v5 nunca está presente: las
  // líneas `peso` todavía no se venden (B3, D-R1) y `unidad` lo prohíbe.
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