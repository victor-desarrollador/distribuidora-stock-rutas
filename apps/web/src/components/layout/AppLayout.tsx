import type { ReactNode } from "react";
import Sidebar from "./Sidebar";

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