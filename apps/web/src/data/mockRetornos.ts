import type { UnidadMedida } from "./mockProductos";

export interface ItemRetorno {
  productoId: number;
  nombreProducto: string;
  unidadMedida: UnidadMedida;

  // Cantidad vendible contada en el cierre (entero canónico: unidades o gramos).
  cantidadContada: number;

  // Cantidad revisada y aprobada para el depósito.
  cantidadAprobada: number;
}

export interface RetornoDeposito {
  id: string;
  jornadaId: string;
  camionId: number;
  fecha: string;
  responsable: string;
  observaciones: string;
  items: ItemRetorno[];
}
