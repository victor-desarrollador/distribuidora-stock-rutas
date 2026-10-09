import { Package, Truck, ShoppingCart } from "lucide-react";

function App() {
  return (
    <div className="min-h-screen bg-slate-100 p-6">
      <div className="mx-auto max-w-5xl">

        <h1 className="text-3xl font-bold text-slate-800">
          Sistema de Distribuidora
        </h1>

        <p className="mt-2 text-slate-500">
          Control de stock, ventas y reparto
        </p>

        <div className="mt-8 grid gap-6 md:grid-cols-3">

          <div className="rounded-xl bg-white p-6 shadow-sm">
            <Package className="mb-4 text-blue-600" size={32} />
            <h2 className="font-semibold">Stock</h2>
            <p className="text-sm text-slate-500">
              Control de mercadería
            </p>
          </div>

          <div className="rounded-xl bg-white p-6 shadow-sm">
            <Truck className="mb-4 text-emerald-600" size={32} />
            <h2 className="font-semibold">Camiones</h2>
            <p className="text-sm text-slate-500">
              Gestión de repartos
            </p>
          </div>

          <div className="rounded-xl bg-white p-6 shadow-sm">
            <ShoppingCart className="mb-4 text-orange-600" size={32} />
            <h2 className="font-semibold">Ventas</h2>
            <p className="text-sm text-slate-500">
              Registro de operaciones
            </p>
          </div>

        </div>
      </div>
    </div>
  );
}

export default App;