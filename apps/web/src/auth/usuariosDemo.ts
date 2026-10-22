export type RolUsuario =
  | "administrador"
  | "vendedor"
  | "deposito";

export interface UsuarioDemo {
  id: string;
  nombre: string;
  rol: RolUsuario;
}

export const CLAVE_SESION = "distribuidora_sesion_demo_v1";

export const usuariosDemo: UsuarioDemo[] = [
  {
    id: "admin-demo",
    nombre: "Administrador",
    rol: "administrador",
  },
  {
    id: "vendedor-demo",
    nombre: "Vendedor de reparto",
    rol: "vendedor",
  },
  {
    id: "deposito-demo",
    nombre: "Encargado de depósito",
    rol: "deposito",
  },
];
