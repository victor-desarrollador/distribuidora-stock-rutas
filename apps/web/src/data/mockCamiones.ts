
export type EstadoCamion =
  | "disponible"
  | "en_reparto"
  | "mantenimiento";

export interface Camion {
  id: number;
  nombre: string;
  patente: string;
  marca: string;
  modelo: string;
  estado: EstadoCamion;
  observaciones: string;
}

export const camionesIniciales: Camion[] = [
  {
    id: 1,
    nombre: "Camión 01",
    patente: "AE123BC",
    marca: "Iveco",
    modelo: "Daily",
    estado: "disponible",
    observaciones: "Vehículo refrigerado",
  },
  {
    id: 2,
    nombre: "Camión 02",
    patente: "AF456DE",
    marca: "Mercedes-Benz",
    modelo: "Sprinter",
    estado: "disponible",
    observaciones: "",
  },
  {
    id: 3,
    nombre: "Camión 03",
    patente: "AG789FG",
    marca: "Fiat",
    modelo: "Ducato",
    estado: "mantenimiento",
    observaciones: "Revisión del equipo de frío",
  },
];
