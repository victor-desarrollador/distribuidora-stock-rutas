
import { useMemo, useState } from "react";
import {
  Search,
  CheckCircle2,
  AlertTriangle,
  Receipt,
  Banknote,
} from "lucide-react";

import { useClientes } from "../hooks/useClientes";
import { useVentas } from "../hooks/useVentas";
import { useJornadas, leerJornadasDiscriminado } from "../hooks/useJornadas";
import { useCobros } from "../hooks/useCobros";

import type { Cobro, MedioCobro } from "../data/mockCobros";
import {
  NO_DISPONIBLE,
  disponibilidadCuentas,
  saldoSiDisponible,
} from "./avisosStorage";
import AvisoStorageOperativo from "../components/AvisoStorageOperativo";
import { estadoStorageOperativo } from "./estadoStorageOperativo";
import { revalidar_jornada_para_cobro } from "../domain/jornadas";

const moneda = (valor: number) =>
  new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 2,
  }).format(valor);

const redondear = (n: number) => Math.round(n * 100) / 100;

export default function CuentasCorrientes() {
  const { clientes, estadoLectura: estadoClientes } = useClientes();
  const { ventas, estadoLectura: estadoVentas } = useVentas();
  const { jornadas, estadoLectura: estadoJornadas } = useJornadas();
  const { cobros, registrarCobro, estadoLectura: estadoCobros } =
    useCobros();

  // Ledger corrupto ≠ ledger vacío: sin ambos ledgers legibles no hay saldo.
  const disponibilidad = disponibilidadCuentas(estadoVentas, estadoCobros);
  const estadoOperacion = estadoStorageOperativo({
    clientes: estadoClientes,
    jornadas: estadoJornadas,
  });

  const [busqueda, setBusqueda] = useState("");
  const [clienteId, setClienteId] = useState("");
  const [importe, setImporte] = useState("");
  const [medio, setMedio] = useState<MedioCobro>("efectivo");
  const [jornadaId, setJornadaId] = useState("");
  const [referencia, setReferencia] = useState("");
  const [observaciones, setObservaciones] = useState("");

  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");

  // Referencia estable: `clientes` solo cambia por reemplazo
  // inmutable del estado, así que el filtro produce el mismo resultado.
  const clientesCuenta = useMemo(
    () =>
      clientes.filter(
        (c) => c.condicionPago === "cuenta_corriente"
      ),
    [clientes]
  );

  const resumenClientes = useMemo(
    () =>
      clientesCuenta.map((cliente) => {
        const ventasFiadas = ventas.filter(
          (v) =>
            v.clienteId === cliente.id &&
            v.medioPago === "cuenta_corriente"
        );

        const pagos = cobros.filter(
          (c) => c.clienteId === cliente.id
        );

        return {
          cliente,
          vendido: disponibilidad.ventasDisponibles
            ? redondear(ventasFiadas.reduce((s, v) => s + v.total, 0))
            : null,
          cobrado: disponibilidad.cobrosDisponibles
            ? redondear(pagos.reduce((s, c) => s + c.importe, 0))
            : null,
          saldo: saldoSiDisponible(
            disponibilidad.saldoDisponible,
            cliente.id,
            ventas,
            cobros
          ),
        };
      }),
    [
      clientesCuenta,
      ventas,
      cobros,
      disponibilidad.ventasDisponibles,
      disponibilidad.cobrosDisponibles,
      disponibilidad.saldoDisponible,
    ]
  );

  const clientesFiltrados = resumenClientes.filter(
    ({ cliente }) =>
      `${cliente.nombreComercio} ${cliente.titular} ${cliente.zona}`
        .toLocaleLowerCase("es-AR")
        .includes(busqueda.trim().toLocaleLowerCase("es-AR"))
  );

  const totalDeuda = disponibilidad.saldoDisponible
    ? redondear(
        resumenClientes.reduce((s, c) => s + (c.saldo ?? 0), 0)
      )
    : null;

  // Referencia estable para la dependencia de los useMemo
  // que consumen `cliente` (mismo `.find()`, sin cambiar semantics).
  const cliente = useMemo(
    () => clientesCuenta.find((c) => c.id === Number(clienteId)),
    [clientesCuenta, clienteId]
  );

  // null: saldo no disponible (ledger corrupto). Nunca 0 como respaldo.
  const saldoCliente = cliente
    ? saldoSiDisponible(
        disponibilidad.saldoDisponible,
        cliente.id,
        ventas,
        cobros
      )
    : 0;

  const jornadasAbiertas = jornadas.filter(
    (j) => j.estado === "abierta"
  );

  const movimientosCliente = useMemo(() => {
    if (!cliente || !disponibilidad.saldoDisponible) return [];

    const movimientosVentas = ventas
      .filter(
        (v) =>
          v.clienteId === cliente.id &&
          v.medioPago === "cuenta_corriente"
      )
      .map((v) => ({
        id: `venta-${v.id}`,
        fecha: v.fecha,
        concepto: "Venta a cuenta corriente",
        importe: v.total,
        tipo: "deuda" as const,
      }));

    const movimientosCobros = cobros
      .filter((c) => c.clienteId === cliente.id)
      .map((c) => ({
        id: `cobro-${c.id}`,
        fecha: c.fecha,
        concepto:
          c.medio === "efectivo"
            ? "Cobro en efectivo"
            : "Cobro por transferencia",
        importe: c.importe,
        tipo: "cobro" as const,
      }));

    return [...movimientosVentas, ...movimientosCobros]
      .sort((a, b) => b.fecha.localeCompare(a.fecha));
  }, [cliente, ventas, cobros, disponibilidad.saldoDisponible]);

  function seleccionarCliente(id: string) {
    setClienteId(id);
    setImporte("");
    setMedio("efectivo");
    setJornadaId("");
    setReferencia("");
    setObservaciones("");
    setMensaje("");
    setError("");
  }

  function guardarCobro() {
    setError("");
    setMensaje("");
    if (estadoOperacion.bloqueado) return;

    if (!disponibilidad.saldoDisponible || saldoCliente === null) {
      setError(disponibilidad.aviso ?? "No se puede calcular el saldo.");
      return;
    }

    if (!cliente || !cliente.activo) {
      setError("Seleccioná un cliente activo.");
      return;
    }

    if (!importe.trim()) {
      setError("Ingresá el importe del cobro.");
      return;
    }

    const cantidad = Number(importe);

    if (
      !Number.isFinite(cantidad) ||
      cantidad <= 0 ||
      Math.abs(
        cantidad * 100 - Math.round(cantidad * 100)
      ) > 0.000001
    ) {
      setError("El importe debe ser positivo y tener hasta dos decimales.");
      return;
    }

    if (cantidad > saldoCliente + 0.009) {
      setError("El cobro no puede superar la deuda pendiente.");
      return;
    }

    if (medio === "transferencia" && !referencia.trim()) {
      setError("Ingresá el número o referencia de transferencia.");
      return;
    }

    if (
      jornadaId &&
      !jornadasAbiertas.some((j) => j.id === jornadaId)
    ) {
      setError("La jornada seleccionada ya no está abierta.");
      return;
    }

    const confirmado = window.confirm(
      `¿Registrar un cobro de ${moneda(cantidad)} ` +
      `para ${cliente.nombreComercio}?\n\n` +
      "Esta operación disminuirá la deuda del cliente."
    );

    if (!confirmado) return;

    // M-2 (bloque E): revalidar la Jornada asociada justo antes de persistir.
    // El confirm abre una ventana en la que el storage de Jornadas puede
    // haberse corrompido o la jornada puede haber desaparecido o cerrado.
    // Cobros sin jornada asociada no crea dependencia: la revalidación solo
    // aplica con jornadaId. Si un cobro puede asociarse a una jornada
    // cerrada es una decisión pendiente del Blueprint (no se inventa).
    if (jornadaId) {
      const revalidacionCobro = revalidar_jornada_para_cobro(
        leerJornadasDiscriminado(),
        jornadaId
      );

      if (!revalidacionCobro.ok) {
        setError(`No se puede registrar el cobro: ${revalidacionCobro.error}`);
        return;
      }
    }

    const cobro: Cobro = {
      id: crypto.randomUUID(),
      clienteId: cliente.id,
      nombreCliente: cliente.nombreComercio,
      jornadaId: jornadaId || null,
      fecha: new Date().toISOString(),
      importe: redondear(cantidad),
      medio,
      referencia: medio === "transferencia"
        ? referencia.trim()
        : "",
      observaciones: observaciones.trim(),
    };

    const resultado = registrarCobro(cobro);

    if (resultado) {
      setError(resultado);
      return;
    }

    setMensaje(
      `Cobro registrado correctamente: ${moneda(cobro.importe)}.`
    );

    setImporte("");
    setMedio("efectivo");
    setJornadaId("");
    setReferencia("");
    setObservaciones("");
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6 pb-12">
      <header>
        <p className="text-xs font-semibold uppercase tracking-wide text-blue-600">
          Administración · Clientes
        </p>
        <h1 className="mt-1 text-3xl font-bold text-slate-900">
          Cuentas corrientes
        </h1>
        <p className="mt-1 text-slate-500">
          Control de deudas y cobros de comercios
        </p>
      </header>

      <AvisoStorageOperativo avisos={estadoOperacion.avisos} />

      <div className="grid gap-4 sm:grid-cols-3">
        {[
          {
            nombre: "Clientes con cuenta",
            valor: String(clientesCuenta.length),
          },
          {
            nombre: "Deuda total",
            valor:
              totalDeuda === null ? NO_DISPONIBLE : moneda(totalDeuda),
          },
          {
            nombre: "Cobros registrados",
            valor: disponibilidad.cobrosDisponibles
              ? moneda(cobros.reduce((s, c) => s + c.importe, 0))
              : NO_DISPONIBLE,
          },
        ].map((dato) => (
          <div
            key={dato.nombre}
            className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
          >
            <p className="text-sm text-slate-500">
              {dato.nombre}
            </p>
            <p className="mt-2 text-2xl font-bold text-slate-900">
              {dato.valor}
            </p>
          </div>
        ))}
      </div>

      {disponibilidad.aviso && (
        <div
          role="alert"
          className="flex items-start gap-2 rounded-xl bg-red-50 p-4 font-medium text-red-800"
        >
          <AlertTriangle size={22} className="shrink-0" />
          <span>
            <strong>Datos dañados: </strong>
            {disponibilidad.aviso}
          </span>
        </div>
      )}

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

      <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <h2 className="mb-4 text-lg font-bold">
          Saldos por cliente
        </h2>

        <div className="mb-4 flex items-center gap-3 rounded-lg border border-slate-300 p-3">
          <Search className="text-slate-400" size={20} />
          <input
            aria-label="Buscar cliente"
            value={busqueda}
            onChange={(e) => setBusqueda(e.target.value)}
            placeholder="Buscar comercio, titular o zona"
            className="w-full outline-none"
          />
        </div>

        <div className="space-y-3">
          {clientesFiltrados.map(({ cliente: c, saldo, vendido, cobrado }) => (
            <button
              key={c.id}
              type="button"
              onClick={() => seleccionarCliente(String(c.id))}
              className={`w-full rounded-xl border p-4 text-left ${
                clienteId === String(c.id)
                  ? "border-blue-500 bg-blue-50"
                  : "border-slate-200 bg-white hover:bg-slate-50"
              }`}
            >
              <div className="flex flex-wrap justify-between gap-3">
                <div>
                  <p className="font-semibold text-slate-900">
                    {c.nombreComercio}
                  </p>
                  <p className="text-sm text-slate-500">
                    {c.titular} · {c.zona}
                  </p>
                  {!c.activo && (
                    <p className="text-xs text-amber-700">
                      Cliente inactivo
                    </p>
                  )}
                </div>
                <div className="text-right">
                  <p className="text-xs text-slate-500">
                    Saldo pendiente
                  </p>
                  <p className="text-xl font-bold text-slate-900">
                    {saldo === null ? NO_DISPONIBLE : moneda(saldo)}
                  </p>
                </div>
              </div>

              <div className="mt-3 flex flex-wrap gap-4 border-t border-slate-100 pt-3 text-xs text-slate-500">
                <span>
                  Ventas fiadas:{" "}
                  {vendido === null ? NO_DISPONIBLE : moneda(vendido)}
                </span>
                <span>
                  Cobrado:{" "}
                  {cobrado === null ? NO_DISPONIBLE : moneda(cobrado)}
                </span>
              </div>
            </button>
          ))}

          {clientesFiltrados.length === 0 && (
            <p className="py-5 text-center text-slate-500">
              No se encontraron clientes.
            </p>
          )}
        </div>
      </section>

      {cliente && (
        <>
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="mb-4 flex items-center gap-2">
              <Banknote className="text-blue-600" />
              <h2 className="text-lg font-bold">
                Registrar cobro
              </h2>
            </div>

            <p className="mb-5 text-sm text-slate-600">
              Cliente: <strong>{cliente.nombreComercio}</strong>
              <span className="ml-2">
                · Deuda:{" "}
                <strong>
                  {saldoCliente === null
                    ? NO_DISPONIBLE
                    : moneda(saldoCliente)}
                </strong>
              </span>
            </p>

            {!cliente.activo && (
              <p className="mb-4 rounded-lg bg-amber-50 p-3 text-sm text-amber-800">
                El cliente está inactivo. Podés consultar su
                historial, pero no registrar nuevos cobros
                desde esta pantalla.
              </p>
            )}

            <div className="grid gap-4 md:grid-cols-2">
              <label className="block space-y-2">
                <span className="text-sm font-medium">
                  Importe a cobrar *
                </span>
                <input
                  type="number"
                  min="0.01"
                  step="0.01"
                  value={importe}
                  onChange={(e) => setImporte(e.target.value)}
                  placeholder="0.00"
                  className="min-h-12 w-full rounded-lg border border-slate-300 p-3"
                />
              </label>

              <label className="block space-y-2">
                <span className="text-sm font-medium">
                  Medio de cobro
                </span>
                <select
                  value={medio}
                  onChange={(e) =>
                    setMedio(e.target.value as MedioCobro)
                  }
                  className="min-h-12 w-full rounded-lg border border-slate-300 p-3"
                >
                  <option value="efectivo">Efectivo</option>
                  <option value="transferencia">Transferencia</option>
                </select>
              </label>

              <label className="block space-y-2">
                <span className="text-sm font-medium">
                  Jornada asociada (opcional)
                </span>
                <select
                  value={jornadaId}
                  onChange={(e) => setJornadaId(e.target.value)}
                  className="min-h-12 w-full rounded-lg border border-slate-300 p-3"
                >
                  <option value="">Cobro administrativo</option>
                  {jornadasAbiertas.map((j) => (
                    <option key={j.id} value={j.id}>
                      {j.chofer} · {j.zona}
                    </option>
                  ))}
                </select>
                <p className="text-xs text-slate-500">
                  Elegí una jornada si el vendedor recibió
                  el dinero durante el reparto.
                </p>
              </label>

              {medio === "transferencia" && (
                <label className="block space-y-2">
                  <span className="text-sm font-medium">
                    Referencia de transferencia *
                  </span>
                  <input
                    value={referencia}
                    onChange={(e) =>
                      setReferencia(e.target.value)
                    }
                    placeholder="Número de operación"
                    className="min-h-12 w-full rounded-lg border border-slate-300 p-3"
                  />
                </label>
              )}
            </div>

            <label className="mt-4 block space-y-2">
              <span className="text-sm font-medium">
                Observaciones
              </span>
              <textarea
                value={observaciones}
                onChange={(e) =>
                  setObservaciones(e.target.value)
                }
                rows={3}
                placeholder="Ej: pago parcial de deuda anterior"
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            <button
              type="button"
              onClick={guardarCobro}
              disabled={
                estadoOperacion.bloqueado ||
                !cliente.activo ||
                saldoCliente === null ||
                saldoCliente <= 0 ||
                !importe.trim()
              }
              className="mt-5 flex min-h-14 w-full items-center justify-center gap-2 rounded-xl bg-green-600 px-5 font-semibold text-white disabled:opacity-40"
            >
              <CheckCircle2 size={21} />
              Confirmar cobro
            </button>
          </section>

          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="mb-4 flex items-center gap-2">
              <Receipt className="text-blue-600" />
              <h2 className="text-lg font-bold">
                Estado de cuenta
              </h2>
            </div>

            {!disponibilidad.saldoDisponible ? (
              <p className="text-sm text-slate-500">
                Estado de cuenta {NO_DISPONIBLE.toLowerCase()}: los
                datos guardados están dañados.
              </p>
            ) : movimientosCliente.length === 0 ? (
              <p className="text-sm text-slate-500">
                Este cliente todavía no tiene movimientos.
              </p>
            ) : (
              <div className="space-y-3">
                {movimientosCliente.map((m) => (
                  <div
                    key={m.id}
                    className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-slate-200 p-4"
                  >
                    <div>
                      <p className="font-medium">
                        {m.concepto}
                      </p>
                      <p className="text-xs text-slate-500">
                        {new Date(m.fecha).toLocaleString("es-AR")}
                      </p>
                    </div>

                    <strong
                      className={
                        m.tipo === "cobro"
                          ? "text-green-700"
                          : "text-red-700"
                      }
                    >
                      {m.tipo === "cobro" ? "−" : "+"}
                      {moneda(m.importe)}
                    </strong>
                  </div>
                ))}
              </div>
            )}
          </section>
        </>
      )}

      <p className="text-xs text-slate-500">
        Prototipo local: los saldos se calculan a partir
        de ventas fiadas y cobros. No se generan recibos
        fiscales ni asientos contables reales.
      </p>
    </div>
  );
}
