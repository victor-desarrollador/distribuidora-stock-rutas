import {
  Boxes,
  ClipboardCheck,
  ClipboardList,
  LayoutDashboard,
  Package,
  RefreshCw,
  Settings,
  ShoppingCart,
  Truck,
  Users,
  Wallet,
  Warehouse,
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
  { nombre: "Autoventa", icono: ShoppingCart, ruta: "/autoventa" },
  { nombre: "Movimientos", icono: RefreshCw, ruta: "/movimientos" },
  { nombre: "Rendición", icono: ClipboardCheck, ruta: "/rendicion" },
  { nombre: "Retornos", icono: Warehouse, ruta: "/retornos" },
  { nombre: "Cuentas corrientes", icono: Wallet, ruta: "/cuentas" },
  { nombre: "Configuración", icono: Settings, ruta: "/configuracion-demo" },
];

// Rutas del vendedor/piloto (Blueprint §9: ve su jornada, clientes y ventas).
const RUTAS_VENDEDOR = [
  "/clientes",
  "/jornadas",
  "/autoventa",
  "/movimientos",
  "/cuentas",
];

/**
 * Entradas del menú visibles para un rol. El menú es sólo comodidad: la
 * protección real son ProtectedRoute y la RLS de la base.
 *
 * `extrasGestion` (p. ej. el acceso a la pantalla demo en desarrollo) se
 * agregan después de «Jornadas» y SÓLO para dueño y encargado. Lo decide el
 * llamador con `import.meta.env.DEV` en línea, para que no entren al bundle de
 * producción.
 */
export function itemsMenuPorRol(
  rol: RolUsuario | null | undefined,
  extrasGestion: ItemMenu[] = []
): ItemMenu[] {
  if (rol === "dueno" || rol === "encargado") {
    const base =
      rol === "dueno"
        ? MENU
        : MENU.filter((item) => item.ruta !== "/configuracion-demo");
    return base.flatMap((item) =>
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
