import {
  AlertTriangle,
  Truck,
  Users,
  ShoppingCart,
  Banknote,
} from "lucide-react";

import {
  dashboardStats,
  alertasVencimiento,
  camiones,
} from "../data/mockDashboard";

const formatoMoneda = (valor: number) =>
  new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 0,
  }).format(valor);

export default function Dashboard() {
  const estadisticas = [
    {
      titulo: "Ventas del día",
      valor: formatoMoneda(dashboardStats.ventasHoy),
      icono: ShoppingCart,
    },
    {
      titulo: "Cobros recibidos",
      valor: formatoMoneda(dashboardStats.cobrosHoy),
      icono: Banknote,
    },
    {
      titulo: "Clientes atendidos",
      valor: dashboardStats.clientesAtendidos,
      icono: Users,
    },
    {
      titulo: "Camiones activos",
      valor: dashboardStats.camionesActivos,
      icono: Truck,
    },
  ];

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-slate-800 md:text-3xl">
          Panel de control
        </h1>
        <p className="mt-1 text-slate-500">
          Resumen general de la distribuidora
        </p>
      </div>

      {/* Tarjetas de estadísticas */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {estadisticas.map(({ titulo, valor, icono: Icono }) => (
          <div
            key={titulo}
            className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
          >
            <div className="mb-4 flex items-center justify-between">
              <p className="text-sm text-slate-500">{titulo}</p>
              <Icono className="text-blue-600" size={24} />
            </div>

            <p className="text-2xl font-bold text-slate-900">
              {valor}
            </p>
          </div>
        ))}
      </section>

      <div className="grid gap-6 xl:grid-cols-2">
        {/* Alertas */}
        <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <div className="mb-5 flex items-center gap-2">
            <AlertTriangle className="text-amber-500" />
            <h2 className="text-lg font-bold">
              Próximos vencimientos
            </h2>
          </div>

          <div className="space-y-3">
            {alertasVencimiento.map((alerta) => (
              <div
                key={alerta.id}
                className="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-amber-50 p-4"
              >
                <div>
                  <p className="font-semibold text-slate-800">
                    {alerta.producto}
                  </p>
                  <p className="text-sm text-slate-500">
                    Lote {alerta.lote} · {alerta.cantidad} unidades
                  </p>
                </div>

                <span className="rounded-full bg-amber-100 px-3 py-1 text-sm font-medium text-amber-800">
                  {alerta.diasRestantes} días
                </span>
              </div>
            ))}
          </div>
        </section>

        {/* Estado de camiones */}
        <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <div className="mb-5 flex items-center gap-2">
            <Truck className="text-blue-600" />
            <h2 className="text-lg font-bold">
              Camiones en reparto
            </h2>
          </div>

          <div className="space-y-3">
            {camiones.map((camion) => (
              <div
                key={camion.id}
                className="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-slate-50 p-4"
              >
                <div>
                  <p className="font-semibold">
                    {camion.nombre}
                  </p>
                  <p className="text-sm text-slate-500">
                    {camion.ruta} · {camion.ventas} ventas
                  </p>
                </div>

                <span className="rounded-full bg-green-100 px-3 py-1 text-sm font-medium text-green-700">
                  {camion.estado}
                </span>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}