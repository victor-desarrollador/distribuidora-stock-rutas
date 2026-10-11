
import { useMemo, useState } from "react";
import {
  Truck,
  ShoppingCart,
  Plus,
  Minus,
  CheckCircle2,
  AlertTriangle,
  Package,
  Receipt,
} from "lucide-react";

import { useJornadas } from "../hooks/useJornadas";
import { useClientes } from "../hooks/useClientes";
import { useCamiones } from "../hooks/useCamiones";
import { useVentas } from "../hooks/useVentas";

import type { Venta, MedioPago } from "../data/mockVentas";

const moneda = (valor: number) =>
  new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 2,
  }).format(valor);

const unidades = {
  unidad: "un.",
  pieza: "pzas.",
  kg: "kg",
};

export default function Autoventa() {
  const { jornadas } = useJornadas();
  const { clientes } = useClientes();
  const { camiones } = useCamiones();
  const { ventas, registrarVenta } = useVentas();

  const [jornadaId, setJornadaId] = useState("");
  const [clienteId, setClienteId] = useState("");

  const [cantidades, setCantidades] = useState<
    Record<number, number>
  >({});

  const [medioPago, setMedioPago] =
    useState<MedioPago>("efectivo");

  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");

  // Una venta solo se realiza sobre una jornada abierta.
  const jornadasAbiertas = jornadas.filter(
    (jornada) => jornada.estado === "abierta"
  );

  const jornada = jornadasAbiertas.find(
    (j) => j.id === jornadaId
  );

  const camion = camiones.find(
    (c) => c.id === jornada?.camionId
  );

  const cliente = clientes.find(
    (c) => c.id === Number(clienteId) && c.activo
  );

  // Mercadería vendida por jornada y producto.
  const cantidadesVendidas = useMemo(() => {
    const cantidadesPorProducto: Record<number, number> = {};

    for (const venta of ventas) {
      if (venta.jornadaId !== jornadaId) continue;

      for (const item of venta.items) {
        cantidadesPorProducto[item.productoId] =
          (cantidadesPorProducto[item.productoId] ?? 0) +
          item.cantidad;
      }
    }

    return cantidadesPorProducto;
  }, [ventas, jornadaId]);

  // Calculamos existencias restantes del camión.
  const productosCamion = useMemo(() => {
    if (!jornada) return [];

    return jornada.items.map((item) => ({
      ...item,
      disponible: Math.max(
        0,
        item.cantidad -
          (cantidadesVendidas[item.productoId] ?? 0)
      ),
    }));
  }, [jornada, cantidadesVendidas]);

  // Preparar el detalle de la venta.
  const itemsVenta = useMemo(() => {
    return productosCamion
      .filter(
        (item) => (cantidades[item.productoId] ?? 0) > 0
      )
      .map((item) => {
        const cantidad = cantidades[item.productoId] ?? 0;

        return {
          productoId: item.productoId,
          nombreProducto: item.nombreProducto,
          unidadMedida: item.unidadMedida,
          cantidad,
          precioUnitario: item.precioReferencia,
          subtotal: Math.round(
            cantidad * item.precioReferencia * 100
          ) / 100,
        };
      });
  }, [productosCamion, cantidades]);

  const total = Math.round(
    itemsVenta.reduce(
      (acumulado, item) => acumulado + item.subtotal,
      0
    ) * 100
  ) / 100;

  const ventasJornada = ventas
    .filter((venta) => venta.jornadaId === jornadaId)
    .sort((a, b) => b.fecha.localeCompare(a.fecha));

  function seleccionarJornada(id: string) {
    setJornadaId(id);
    setClienteId("");
    setCantidades({});
    setMedioPago("efectivo");
    setMensaje("");
    setError("");
  }

  function cambiarCantidad(
    productoId: number,
    nuevaCantidad: number
  ) {
    const producto = productosCamion.find(
      (p) => p.productoId === productoId
    );

    if (!producto) return;

    // Nunca permitir cantidades negativas ni superiores al stock.
    const cantidad = Math.max(
      0,
      Math.min(nuevaCantidad, producto.disponible)
    );

    // Piezas y unidades enteras. Kg admiten decimales.
    const cantidadFinal =
      producto.unidadMedida === "kg"
        ? Math.round(cantidad * 1000) / 1000
        : Math.floor(cantidad);

    setCantidades((actuales) => ({
      ...actuales,
      [productoId]: cantidadFinal,
    }));
  }

  function guardarVenta() {
    setError("");
    setMensaje("");

    if (!jornada || !camion) {
      setError("Seleccioná una jornada abierta.");
      return;
    }

    if (!cliente) {
      setError("Seleccioná un cliente activo.");
      return;
    }

    if (itemsVenta.length === 0) {
      setError("Agregá al menos un producto.");
      return;
    }

    if (
      medioPago === "cuenta_corriente" &&
      cliente.condicionPago !== "cuenta_corriente"
    ) {
      setError("Este cliente no tiene cuenta corriente habilitada.");
      return;
    }

    const venta: Venta = {
      id: crypto.randomUUID(),
      jornadaId: jornada.id,
      camionId: jornada.camionId,
      clienteId: cliente.id,
      nombreCliente: cliente.nombreComercio,
      fecha: new Date().toISOString(),
      medioPago,
      items: itemsVenta,
      total,
    };

    const resultado = registrarVenta(venta, (ventasActuales) => {
      // Revalidación al momento de guardar.
      for (const item of itemsVenta) {
        const cargado = jornada.items.find(
          (producto) => producto.productoId === item.productoId
        );

        if (!cargado) {
          return `El producto ${item.nombreProducto} no está cargado.`;
        }

        const vendido = ventasActuales
          .filter((v) => v.jornadaId === jornada.id)
          .flatMap((v) => v.items)
          .filter((p) => p.productoId === item.productoId)
          .reduce((suma, p) => suma + p.cantidad, 0);

        const restante = Math.max(0, cargado.cantidad - vendido);

        if (
          !Number.isFinite(item.cantidad) ||
          item.cantidad <= 0 ||
          item.cantidad > restante + 0.000001
        ) {
          return `Stock insuficiente de ${item.nombreProducto}.`;
        }
      }

      return null;
    });

    if (resultado) {
      setError(resultado);
      return;
    }

    setCantidades({});
    setClienteId("");
    setMedioPago("efectivo");

    setMensaje(
      `Venta registrada correctamente por ${moneda(total)}.`
    );
  }

  return (
    <div className="mx-auto max-w-4xl space-y-5 pb-10">
      {/* Encabezado */}
      <div>
        <p className="text-xs font-bold uppercase tracking-wider text-blue-600">
          Autoventa · Repartidor
        </p>

        <h1 className="mt-1 text-3xl font-bold text-slate-900">
          Ventas en ruta
        </h1>

        <p className="mt-1 text-sm text-slate-500">
          Registro de ventas desde el camión
        </p>
      </div>

      {/* Mensajes */}
      {mensaje && (
        <div
          role="status"
          className="flex items-center gap-2 rounded-xl bg-green-50 p-4 text-green-800"
        >
          <CheckCircle2 size={22} />
          {mensaje}
        </div>
      )}

      {error && (
        <div
          role="alert"
          className="flex items-center gap-2 rounded-xl bg-red-50 p-4 text-red-800"
        >
          <AlertTriangle size={22} />
          {error}
        </div>
      )}

      {/* Jornada */}
      <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <div className="mb-4 flex items-center gap-2">
          <Truck size={23} className="text-blue-600" />
          <h2 className="text-lg font-bold">Jornada activa</h2>
        </div>

        <label className="block space-y-2">
          <span className="text-sm font-medium">
            Seleccionar reparto
          </span>

          <select
            value={jornadaId}
            onChange={(e) => seleccionarJornada(e.target.value)}
            className="min-h-14 w-full rounded-xl border border-slate-300 bg-white p-3 text-base"
          >
            <option value="">Seleccionar jornada</option>

            {jornadasAbiertas.map((j) => {
              const c = camiones.find(
                (camion) => camion.id === j.camionId
              );

              return (
                <option key={j.id} value={j.id}>
                  {c?.nombre ?? "Camión"} · {j.chofer} · {j.zona}
                </option>
              );
            })}
          </select>
        </label>

        {jornadasAbiertas.length === 0 && (
          <p className="mt-3 rounded-lg bg-amber-50 p-3 text-sm text-amber-800">
            No hay jornadas abiertas. Primero prepará una carga
            desde Jornadas y confirmá la salida.
          </p>
        )}

        {jornada && (
          <div className="mt-4 rounded-lg bg-blue-50 p-4">
            <p className="font-semibold text-blue-900">
              {camion?.nombre} · {jornada.chofer}
            </p>
            <p className="text-sm text-blue-700">
              Zona: {jornada.zona}
            </p>
          </div>
        )}
      </section>

      {jornada && (
        <>
          {/* Cliente */}
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <h2 className="mb-4 text-lg font-bold">
              1. Seleccionar cliente
            </h2>

            <select
              value={clienteId}
              onChange={(e) => {
                setClienteId(e.target.value);
                setMedioPago("efectivo");
              }}
              className="min-h-14 w-full rounded-xl border border-slate-300 p-3 text-base"
            >
              <option value="">Elegir comercio</option>

              {clientes
                .filter((c) => c.activo)
                .map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.nombreComercio} · {c.zona}
                  </option>
                ))}
            </select>

            {cliente && (
              <p className="mt-3 text-sm text-slate-500">
                {cliente.direccion} ·{" "}
                {cliente.condicionPago === "cuenta_corriente"
                  ? "Cuenta corriente habilitada"
                  : "Pago contado"}
              </p>
            )}
          </section>

          {/* Productos */}
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="mb-4 flex items-center gap-2">
              <Package size={22} className="text-blue-600" />
              <h2 className="text-lg font-bold">
                2. Agregar productos
              </h2>
            </div>

            <div className="space-y-3">
              {productosCamion.map((producto) => {
                const cantidad =
                  cantidades[producto.productoId] ?? 0;

                const incremento =
                  producto.unidadMedida === "kg" ? 0.5 : 1;

                return (
                  <div
                    key={producto.productoId}
                    className="rounded-xl border border-slate-200 p-4"
                  >
                    <p className="font-semibold text-slate-900">
                      {producto.nombreProducto}
                    </p>

                    <p className="mt-1 text-sm text-slate-500">
                      {moneda(producto.precioReferencia)} por{" "}
                      {producto.unidadMedida}
                    </p>

                    <p className="mt-1 text-xs text-blue-700">
                      Disponible: {producto.disponible}{" "}
                      {unidades[producto.unidadMedida]}
                    </p>

                    <div className="mt-4 flex items-center justify-between gap-3">
                      <span className="text-sm font-medium text-slate-600">
                        Cantidad
                      </span>

                      <div className="flex items-center gap-3">
                        <button
                          type="button"
                          aria-label={`Quitar ${producto.nombreProducto}`}
                          onClick={() =>
                            cambiarCantidad(
                              producto.productoId,
                              cantidad - incremento
                            )
                          }
                          disabled={cantidad === 0}
                          className="flex h-12 w-12 items-center justify-center rounded-xl border border-slate-300 disabled:opacity-40"
                        >
                          <Minus size={22} />
                        </button>

                        <input
                          type="number"
                          min="0"
                          max={producto.disponible}
                          step={
                            producto.unidadMedida === "kg"
                              ? "0.001"
                              : "1"
                          }
                          value={cantidad}
                          aria-label={`Cantidad de ${producto.nombreProducto}`}
                          onChange={(e) =>
                            cambiarCantidad(
                              producto.productoId,
                              e.target.value === ""
                                ? 0
                                : Number(e.target.value)
                            )
                          }
                          className="h-12 w-20 rounded-lg border border-slate-300 text-center text-lg font-bold"
                        />

                        <button
                          type="button"
                          aria-label={`Agregar ${producto.nombreProducto}`}
                          onClick={() =>
                            cambiarCantidad(
                              producto.productoId,
                              cantidad + incremento
                            )
                          }
                          disabled={
                            cantidad + incremento >
                            producto.disponible + 0.000001
                          }
                          className="flex h-12 w-12 items-center justify-center rounded-xl bg-blue-600 text-white disabled:opacity-40"
                        >
                          <Plus size={22} />
                        </button>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>

            {productosCamion.length === 0 && (
              <p className="py-5 text-center text-slate-500">
                Esta jornada no tiene productos cargados.
              </p>
            )}
          </section>

          {/* Cobro */}
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="mb-4 flex items-center gap-2">
              <ShoppingCart size={22} className="text-blue-600" />
              <h2 className="text-lg font-bold">
                3. Resumen y cobro
              </h2>
            </div>

            {itemsVenta.length === 0 ? (
              <p className="text-sm text-slate-500">
                Seleccioná productos para preparar la venta.
              </p>
            ) : (
              <div className="space-y-3">
                {itemsVenta.map((item) => (
                  <div
                    key={item.productoId}
                    className="flex items-start justify-between gap-3 border-b border-slate-100 pb-3 text-sm"
                  >
                    <div>
                      <p className="font-medium">
                        {item.nombreProducto}
                      </p>
                      <p className="text-slate-500">
                        {item.cantidad} × {moneda(item.precioUnitario)}
                      </p>
                    </div>

                    <strong>{moneda(item.subtotal)}</strong>
                  </div>
                ))}
              </div>
            )}

            <div className="my-5 flex items-center justify-between border-t border-slate-200 pt-4">
              <span className="font-semibold">
                Total de venta
              </span>
              <span className="text-3xl font-bold text-slate-900">
                {moneda(total)}
              </span>
            </div>

            <p className="mb-3 text-sm font-semibold">
              Forma de pago
            </p>

            <div className="grid gap-3 sm:grid-cols-3">
              {(
                [
                  ["efectivo", "Efectivo"],
                  ["transferencia", "Transferencia"],
                  ["cuenta_corriente", "Cuenta corriente"],
                ] as const
              ).map(([valor, etiqueta]) => {
                const deshabilitado =
                  valor === "cuenta_corriente" &&
                  cliente?.condicionPago !== "cuenta_corriente";

                return (
                  <button
                    key={valor}
                    type="button"
                    disabled={deshabilitado}
                    onClick={() => setMedioPago(valor)}
                    className={`min-h-14 rounded-xl border-2 px-3 py-3 font-medium transition-colors ${
                      medioPago === valor
                        ? "border-blue-600 bg-blue-50 text-blue-700"
                        : "border-slate-200 bg-white text-slate-700"
                    } disabled:cursor-not-allowed disabled:opacity-40`}
                  >
                    {etiqueta}
                  </button>
                );
              })}
            </div>

            <button
              type="button"
              onClick={guardarVenta}
              disabled={!cliente || itemsVenta.length === 0}
              className="mt-6 flex min-h-14 w-full items-center justify-center gap-2 rounded-xl bg-green-600 px-5 text-lg font-bold text-white hover:bg-green-700 disabled:cursor-not-allowed disabled:opacity-40"
            >
              <CheckCircle2 size={24} />
              Registrar venta
            </button>
          </section>

          {/* Historial de la jornada */}
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="mb-4 flex items-center gap-2">
              <Receipt size={22} className="text-blue-600" />
              <h2 className="text-lg font-bold">
                Ventas registradas
              </h2>
            </div>

            {ventasJornada.length === 0 && (
              <p className="text-sm text-slate-500">
                Todavía no hay ventas en esta jornada.
              </p>
            )}

            <div className="space-y-3">
              {ventasJornada.map((venta) => (
                <div
                  key={venta.id}
                  className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-slate-50 p-4"
                >
                  <div>
                    <p className="font-semibold text-slate-800">
                      {venta.nombreCliente}
                    </p>

                    <p className="text-xs text-slate-500">
                      {new Date(venta.fecha).toLocaleString("es-AR")}
                    </p>

                    <p className="mt-1 text-xs text-blue-700">
                      {venta.medioPago === "cuenta_corriente"
                        ? "Cuenta corriente"
                        : venta.medioPago === "transferencia"
                        ? "Transferencia"
                        : "Efectivo"}
                    </p>
                  </div>

                  <span className="font-bold text-slate-900">
                    {moneda(venta.total)}
                  </span>
                </div>
              ))}
            </div>
          </section>
        </>
      )}

      <p className="text-center text-xs text-slate-500">
        Prototipo de demostración. Sin cobros reales,
        facturación ni sincronización entre dispositivos.
      </p>
    </div>
  );
}
