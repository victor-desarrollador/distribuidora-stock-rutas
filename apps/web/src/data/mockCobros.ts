
export type MedioCobro = "efectivo" | "transferencia";

export interface Cobro {
  id: string;
  clienteId: number;
  nombreCliente: string;

  // Puede ser null si el cobro fue realizado
  // directamente en administración.
  jornadaId: string | null;

  fecha: string;
  importe: number;
  medio: MedioCobro;
  referencia: string;
  observaciones: string;
}
