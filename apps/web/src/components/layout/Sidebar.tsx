import { NavLink } from "react-router-dom";

import {
  LayoutDashboard,
  Package,
  Users,
  Truck,
  ShoppingCart,
  Wallet,
  BarChart3,
} from "lucide-react";

const menu = [
  { nombre: "Inicio", icono: LayoutDashboard, ruta: "/" },
  { nombre: "Productos", icono: Package, ruta: "/productos" },
  { nombre: "Clientes", icono: Users, ruta: "/clientes" },
  { nombre: "Camiones", icono: Truck, ruta: "/camiones" },
  { nombre: "Ventas", icono: ShoppingCart, ruta: "/ventas" },
  { nombre: "Cuentas corrientes", icono: Wallet, ruta: "/cuentas" },
  { nombre: "Reportes", icono: BarChart3, ruta: "/reportes" },
];

export default function Sidebar() {
  return (
    <aside className="hidden min-h-screen w-64 shrink-0 bg-slate-900 p-5 text-white md:block">
      <div className="mb-10">
        <h1 className="text-xl font-bold">Distribuidora</h1>

        <p className="text-sm text-slate-400">
          Stock y Autoventa
        </p>
      </div>

      <nav className="space-y-2">
        {menu.map(({ nombre, icono: Icono, ruta }) => (
          <NavLink
            key={ruta}
            to={ruta}
            className={({ isActive }) =>
              `flex items-center gap-3 rounded-lg px-4 py-3 transition-colors ${
                isActive
                  ? "bg-blue-600 text-white"
                  : "text-slate-300 hover:bg-slate-800 hover:text-white"
              }`
            }
          >
            <Icono size={20} />
            <span>{nombre}</span>
          </NavLink>
        ))}
      </nav>
    </aside>
  );
}