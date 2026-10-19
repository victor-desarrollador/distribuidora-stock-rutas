export type UnidadMedida = "unidad" | "pieza";

export interface Producto {
  id: number;
  nombre: string;
  categoria: "Lácteos" | "Fiambres";
  unidadMedida: UnidadMedida;
  stock: number;
  precio: number;
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
  {
    id: 3,
    nombre: "Queso cremoso en pieza",
    categoria: "Fiambres",
    unidadMedida: "pieza",
    stock: 36,
    precio: 12500,
    stockMinimo: 10,
  },
  {
    id: 4,
    nombre: "Jamón cocido",
    categoria: "Fiambres",
    unidadMedida: "pieza",
    stock: 36,
    precio: 12500,
    stockMinimo: 10,
  },
  {
    id: 5,
    nombre: "Salame milán",
    categoria: "Fiambres",
    unidadMedida: "pieza",
    stock: 12,
    precio: 9800,
    stockMinimo: 16,
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