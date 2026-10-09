
export type CondicionPago = "contado" | "cuenta_corriente";

export interface Cliente {
  id: number;
  nombreComercio: string;
  titular: string;
  telefono: string;
  direccion: string;
  zona: string;
  condicionPago: CondicionPago;
  limiteCredito: number;
  activo: boolean;
}

export const clientesIniciales: Cliente[] = [
  {
    id: 1,
    nombreComercio: "Almacén Don Pedro",
    titular: "Pedro González",
    telefono: "3815551234",
    direccion: "Av. Belgrano 1250",
    zona: "Centro",
    condicionPago: "cuenta_corriente",
    limiteCredito: 200000,
    activo: true,
  },
  {
    id: 2,
    nombreComercio: "Despensa La Esquina",
    titular: "María López",
    telefono: "3815559876",
    direccion: "Av. Mate de Luna 850",
    zona: "Norte",
    condicionPago: "contado",
    limiteCredito: 0,
    activo: true,
  },
  {
    id: 3,
    nombreComercio: "Kiosco El Sol",
    titular: "Juan Pérez",
    telefono: "3815554567",
    direccion: "San Martín 450",
    zona: "Sur",
    condicionPago: "cuenta_corriente",
    limiteCredito: 100000,
    activo: false,
  },
];
