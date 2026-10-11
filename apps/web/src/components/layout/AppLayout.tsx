import type { ReactNode } from "react";
import Sidebar from "./Sidebar";
import { Link } from "react-router-dom";
import { ShoppingCart } from "lucide-react";

type Props = {
  children: ReactNode;
};

export default function AppLayout({ children }: Props) {
  return (
    <div className="min-h-screen bg-slate-100 md:flex">
      <Sidebar />

      <div className="min-w-0 flex-1">
        <header className="flex h-16 items-center justify-between border-b bg-white px-6">
          <span className="font-semibold text-slate-800">
            Panel administrativo
            <Link
              to="/autoventa"
              className="flex min-h-11 items-center gap-2 rounded-lg bg-blue-600 px-3 text-sm font-medium text-white md:hidden"
            >
              <ShoppingCart size={18} />
              Vender
            </Link>
          </span>

          <div className="rounded-full bg-blue-100 px-4 py-2 text-sm font-medium text-blue-700">
            Administrador
          </div>
        </header>

        <main className="p-4 md:p-8">
          {children}
        </main>
      </div>
    </div>
  );
}