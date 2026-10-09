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
  { nombre: "Inicio", icono: LayoutDashboard },
  { nombre: "Productos", icono: Package },
  { nombre: "Clientes", icono: Users },
  { nombre: "Camiones", icono: Truck },
  { nombre: "Ventas", icono: ShoppingCart },
  { nombre: "Cuentas corrientes", icono: Wallet },
  { nombre: "Reportes", icono: BarChart3 },
];

export default function Sidebar() {
  return (
    <aside className="hidden min-h-screen w-64 shrink-0 bg-slate-900 p-5 text-white md:block">
      <div className="mb-10">
        <h1 className="text-xl font-bold">
          Distribuidora
        </h1>
        <p className="text-sm text-slate-400">
          Stock y Autoventa
        </p>
      </div>

      <nav className="space-y-2">
        {menu.map(({ nombre, icono: Icono }) => (
          <div
            key={nombre}
            className="flex items-center gap-3 rounded-lg px-4 py-3 text-slate-300"
          >
            <Icono size={20} />
            <span>{nombre}</span>
          </div>
        ))}
      </nav>
    </aside>
  );
}