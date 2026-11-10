import {
  Boxes,
  ClipboardList,
  LayoutDashboard,
  Package,
  Truck,
  Users,
} from "lucide-react";
import type { ComponentType } from "react";

import type { RolUsuario } from "../../auth/roles";

export interface ItemMenu {
  nombre: string;
  icono: ComponentType<{ size?: number; className?: string }>;
  ruta: string;
}

const MENU: ItemMenu[] = [
  { nombre: "Inicio", icono: LayoutDashboard, ruta: "/" },
  { nombre: "Productos", icono: Package, ruta: "/productos" },
  { nombre: "Stock", icono: Boxes, ruta: "/stock" },
  { nombre: "Clientes", icono: Users, ruta: "/clientes" },
  { nombre: "Camiones", icono: Truck, ruta: "/camiones" },
  { nombre: "Jornadas", icono: ClipboardList, ruta: "/jornadas" },
];

// Rutas del vendedor/piloto (Blueprint §9: ve su jornada y clientes).
const RUTAS_VENDEDOR = ["/clientes", "/jornadas"];

/**
 * Entradas del menú visibles para un rol. El menú es sólo comodidad: la
 * protección real son ProtectedRoute y la RLS de la base.
 *
 * `extrasGestion` se agrega después de «Jornadas» y sólo para dueño y
 * encargado. Lo decide el llamador.
 */
export function itemsMenuPorRol(
  rol: RolUsuario | null | undefined,
  extrasGestion: ItemMenu[] = []
): ItemMenu[] {
  if (rol === "dueno" || rol === "encargado") {
    return MENU.flatMap((item) =>
      item.ruta === "/jornadas" ? [item, ...extrasGestion] : [item]
    );
  }

  if (rol === "vendedor_piloto") {
    return MENU.filter((item) => RUTAS_VENDEDOR.includes(item.ruta)).map(
      (item) =>
        item.ruta === "/jornadas" ? { ...item, nombre: "Mi jornada" } : item
    );
  }

  return [];
}
