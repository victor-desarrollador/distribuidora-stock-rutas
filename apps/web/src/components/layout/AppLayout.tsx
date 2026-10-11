
import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { ShoppingCart } from "lucide-react";

import Sidebar from "./Sidebar";
import { useAuth } from "../../AuthContext";

type Props = {
  children: ReactNode;
};

export default function AppLayout({ children }: Props) {
  const { usuario } = useAuth();

  const nombreRol =
    usuario?.rol === "administrador"
      ? "Administrador"
      : usuario?.rol === "vendedor"
        ? "Vendedor"
        : usuario?.rol === "deposito"
          ? "Depósito"
          : "Sin sesión";

  const puedeVender =
    usuario?.rol === "administrador" ||
    usuario?.rol === "vendedor";

  return (
    <div className="min-h-screen bg-slate-100 md:flex">
      <Sidebar />

      <div className="min-w-0 flex-1">
        {/* ENCABEZADO ADAPTADO A CELULAR */}
        <header className="flex min-h-16 items-center justify-between gap-2 border-b border-slate-200 bg-white py-3 pl-20 pr-3 sm:pr-5 md:pl-6 md:pr-8">
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-slate-800 sm:text-base">
              <span className="md:hidden">
                Distribuidora
              </span>

              <span className="hidden md:inline">
                Panel administrativo
              </span>
            </p>

            <p className="text-xs text-slate-500 md:hidden">
              Stock y Autoventa
            </p>
          </div>

          <div className="flex shrink-0 items-center gap-2">
            {/* ACCESO RÁPIDO A VENTAS EN CELULAR */}
            {puedeVender && (
              <Link
                to="/autoventa"
                aria-label="Ir a Autoventa"
                title="Ir a Autoventa"
                className="flex h-10 w-10 items-center justify-center rounded-lg bg-blue-600 text-white hover:bg-blue-700 md:hidden"
              >
                <ShoppingCart size={20} />
              </Link>
            )}

            {/* ROL DEL USUARIO CONECTADO */}
            <span className="rounded-full bg-blue-100 px-3 py-2 text-xs font-semibold text-blue-700 sm:text-sm">
              {nombreRol}
            </span>
          </div>
        </header>

        {/* CONTENIDO PRINCIPAL */}
        <main className="min-w-0 p-4 md:p-8">
          {children}
        </main>
      </div>
    </div>
  );
}
