
export type EstadoJornada =
  | "preparacion"
  | "abierta"
  | "cerrada";

export interface ItemCarga {
  productoId: number;
  nombreProducto: string;
  unidadMedida: "unidad" | "pieza" | "kg";
  cantidad: number;
  precioReferencia: number;
}

export interface Jornada {
  id: string;
  camionId: number;
  chofer: string;
  zona: string;
  fechaCreacion: string;
  fechaSalida: string | null;
  estado: EstadoJornada;
  items: ItemCarga[];
}
