// Forma de venta del modelo demo (ADR-005). Se conserva el nombre legacy
// `UnidadMedida` para no hacer renombres cosméticos.
//   - unidad: unidades enteras; precio unitario.
//   - peso:   gramos enteros; precio por kg.
export type UnidadMedida = "unidad" | "peso";

export interface Producto {
  id: number;
  nombre: string;
  categoria: "Lácteos" | "Fiambres";
  unidadMedida: UnidadMedida;
  // Entero en la unidad mínima: unidades (unidad) o gramos (peso).
  stock: number;
  // unidad: precio unitario. peso: precio por kg.
  precio: number;
  // Entero en la unidad mínima: unidades (unidad) o gramos (peso).
  stockMinimo: number;
}

export const productosIniciales: Producto[] = [
  {
    id: 1,
    nombre: "Yogur bebible 1 L",
    categoria: "Lácteos",
    unidadMedida: "unidad",
    stock: 120,
    precio: 2300,
    stockMinimo: 20,
  },
  {
    id: 2,
    nombre: "Queso cremoso en bote",
    categoria: "Lácteos",
    unidadMedida: "unidad",
    stock: 20,
    precio: 8500,
    stockMinimo: 5,
  },
  // Fiambres por peso: fixtures nuevos en gramos (ADR-005 D-R4); no derivan
  // de los fixtures anteriores en medias piezas.
  {
    id: 3,
    nombre: "Queso cremoso fraccionado",
    categoria: "Fiambres",
    unidadMedida: "peso",
    stock: 7680,
    precio: 11200,
    stockMinimo: 2000,
  },
  {
    id: 4,
    nombre: "Jamón cocido",
    categoria: "Fiambres",
    unidadMedida: "peso",
    stock: 18000,
    precio: 12500,
    stockMinimo: 5000,
  },
  {
    // Bajo mínimo a propósito.
    id: 5,
    nombre: "Salame milán",
    categoria: "Fiambres",
    unidadMedida: "peso",
    stock: 2500,
    precio: 9800,
    stockMinimo: 3000,
  },
  {
    id: 6,
    nombre: "Leche entera 1 L",
    categoria: "Lácteos",
    unidadMedida: "unidad",
    stock: 80,
    precio: 1600,
    stockMinimo: 30,
  },
];