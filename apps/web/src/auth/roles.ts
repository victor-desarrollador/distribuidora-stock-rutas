// Roles funcionales vigentes (Blueprint §9). Deben coincidir con el CHECK
// `perfiles_rol_valido` de la migración de Auth base.
export type RolUsuario = "dueno" | "encargado" | "vendedor_piloto";

export const ROLES: readonly RolUsuario[] = [
  "dueno",
  "encargado",
  "vendedor_piloto",
];

export function esRolUsuario(valor: unknown): valor is RolUsuario {
  return (
    typeof valor === "string" &&
    (ROLES as readonly string[]).includes(valor)
  );
}

export function nombreRol(rol: RolUsuario): string {
  if (rol === "dueno") return "Dueño";
  if (rol === "encargado") return "Encargado";
  return "Vendedor/Piloto";
}

// Pantalla inicial según el rol del perfil protegido.
export function inicioPorRol(rol: RolUsuario): string {
  return rol === "vendedor_piloto" ? "/autoventa" : "/";
}

// Conjuntos de acceso por ruta. Dueño y encargado reciben lo que tenía el
// administrador del prototipo; vendedor/piloto lo que tenía el vendedor.
export const ROLES_GESTION: RolUsuario[] = ["dueno", "encargado"];
export const ROLES_TODOS: RolUsuario[] = [...ROLES];
export const ROLES_SOLO_DUENO: RolUsuario[] = ["dueno"];
