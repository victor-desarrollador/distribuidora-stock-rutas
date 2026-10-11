
export interface ItemRetorno {
  productoId: number;
  nombreProducto: string;
  unidadMedida: "unidad" | "pieza" | "kg";

  // Cantidad vendible contada en el cierre.
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
