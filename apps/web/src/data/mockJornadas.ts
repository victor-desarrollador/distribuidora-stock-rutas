import type { UnidadMedida } from "./mockProductos";

export type EstadoJornada =
  | "preparacion"
  | "abierta"
  | "cerrada";

export interface ItemCarga {
  productoId: number;
  nombreProducto: string;
  unidadMedida: UnidadMedida;
  // Entero canónico: unidades (unidad) o gramos (peso).
  cantidad: number;
  // unidad: precio unitario snapshot. peso: precio por kg snapshot.
  precioReferencia: number;
}

// Rendición registrada cuando el camión regresa.
export interface CierreJornada {
  fecha: string;

  // Cantidad vendible físicamente contada al regresar.
  // Clave: ID del producto convertido a texto.
  conteos: Record<string, number>;

  // Dinero en efectivo que entregó el repartidor.
  efectivoEntregado: number;

  // Valores calculados al momento del cierre.
  efectivoEsperado: number;
  transferenciasInformadas: number;
  ventasCuentaCorriente: number;

  // Justificación de posibles diferencias.
  observaciones: string;
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

  // Las jornadas anteriores no tienen este campo.
  cierre?: CierreJornada;
}