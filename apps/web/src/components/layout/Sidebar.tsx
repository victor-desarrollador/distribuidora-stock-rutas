
import { NavLink } from "react-router-dom";

import {
  LayoutDashboard,
  Package,
  Users,
  Truck,
  ShoppingCart,
  Wallet,
  ClipboardList,
  RefreshCw,
  ClipboardCheck,
  Warehouse,
  LogOut,
  UserCircle,
  Settings,
} from "lucide-react";

import { useAuth } from "../../AuthContext";

const menu = [
  { nombre: "Inicio", icono: LayoutDashboard, ruta: "/" },
  { nombre: "Productos", icono: Package, ruta: "/productos" },
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

export default function Sidebar() {
  const { usuario, cerrarSesion } = useAuth();

  // Cada rol ve únicamente los módulos autorizados.
  const menuVisible = menu.filter((item) => {
    if (usuario?.rol === "administrador") {
      return true;
    }

    if (usuario?.rol === "vendedor") {
      return [
        "/clientes",
        "/autoventa",
        "/movimientos",
        "/cuentas",
      ].includes(item.ruta);
    }

    if (usuario?.rol === "deposito") {
      return [
        "/productos",
        "/camiones",
        "/jornadas",
        "/movimientos",
        "/retornos",
      ].includes(item.ruta);
    }

    return false;
  });

  const nombreRol =
    usuario?.rol === "administrador"
      ? "Administrador"
      : usuario?.rol === "vendedor"
        ? "Vendedor"
        : usuario?.rol === "deposito"
          ? "Encargado de depósito"
          : "Sin sesión";

  return (
    <aside className="hidden min-h-screen w-64 shrink-0 flex-col bg-slate-900 p-5 text-white md:flex">
      {/* Nombre del sistema */}
      <div className="mb-8">
        <h1 className="text-xl font-bold">
          Distribuidora
        </h1>

        <p className="text-sm text-slate-400">
          Stock y Autoventa
        </p>
      </div>

      {/* Usuario conectado */}
      <div className="mb-6 flex items-center gap-3 rounded-xl bg-slate-800 p-3">
        <UserCircle
          size={30}
          className="shrink-0 text-blue-400"
        />

        <div className="min-w-0">
          <p className="truncate text-sm font-semibold">
            {usuario?.nombre ?? "Sin usuario"}
          </p>

          <p className="text-xs text-slate-400">
            {nombreRol}
          </p>
        </div>
      </div>

      {/* Menú filtrado por permisos */}
      <nav
        className="flex-1 space-y-2"
        aria-label="Menú principal"
      >
        {menuVisible.map(
          ({ nombre, icono: Icono, ruta }) => (
            <NavLink
              key={ruta}
              to={ruta}
              end={ruta === "/"}
              className={({ isActive }) =>
                `flex items-center gap-3 rounded-lg px-4 py-3 transition-colors ${
                  isActive
                    ? "bg-blue-600 text-white"
                    : "text-slate-300 hover:bg-slate-800 hover:text-white"
                }`
              }
            >
              <Icono size={20} className="shrink-0" />
              <span>{nombre}</span>
            </NavLink>
          )
        )}
      </nav>

      {/* Cerrar sesión */}
      <div className="mt-6 border-t border-slate-700 pt-4">
        <button
          type="button"
          onClick={cerrarSesion}
          className="flex min-h-12 w-full items-center gap-3 rounded-lg px-4 py-3 text-left text-sm font-medium text-slate-300 transition-colors hover:bg-red-900/30 hover:text-red-300"
        >
          <LogOut size={20} />
          <span>Cerrar sesión</span>
        </button>
      </div>
    </aside>
  );
}
