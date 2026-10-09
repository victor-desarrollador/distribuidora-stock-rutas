
import { useMemo, useState } from "react";
import {
  Users,
  Plus,
  Search,
  Pencil,
  CheckCircle2,
  MapPin,
  Phone,
} from "lucide-react";

import {
  type Cliente,
  type CondicionPago,
} from "../data/mockClientes";

import { useClientes } from "../hooks/useClientes";

type FormularioCliente = {
  nombreComercio: string;
  titular: string;
  telefono: string;
  direccion: string;
  zona: string;
  condicionPago: CondicionPago;
  limiteCredito: string;
  activo: boolean;
};

function formularioVacio(): FormularioCliente {
  return {
    nombreComercio: "",
    titular: "",
    telefono: "",
    direccion: "",
    zona: "",
    condicionPago: "contado",
    limiteCredito: "0",
    activo: true,
  };
}

const formatoMoneda = (valor: number) =>
  new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 2,
  }).format(valor);

export default function Clientes() {
  const { clientes, setClientes } = useClientes();

  const [busqueda, setBusqueda] = useState("");
  const [filtro, setFiltro] = useState("todos");
  const [mostrarFormulario, setMostrarFormulario] = useState(false);
  const [clienteEditando, setClienteEditando] = useState<number | null>(null);
  const [mensaje, setMensaje] = useState("");

  const [formulario, setFormulario] =
    useState<FormularioCliente>(formularioVacio);

  const clientesFiltrados = useMemo(() => {
    const termino = busqueda.trim().toLocaleLowerCase("es-AR");

    return clientes.filter((cliente) => {
      const coincideBusqueda = [
        cliente.nombreComercio,
        cliente.titular,
        cliente.telefono,
        cliente.direccion,
        cliente.zona,
      ].some((valor) =>
        valor.toLocaleLowerCase("es-AR").includes(termino)
      );

      const coincideEstado =
        filtro === "todos" ||
        (filtro === "activos" && cliente.activo) ||
        (filtro === "inactivos" && !cliente.activo) ||
        (filtro === "cuenta_corriente" &&
          cliente.condicionPago === "cuenta_corriente");

      return coincideBusqueda && coincideEstado;
    });
  }, [clientes, busqueda, filtro]);

  const totalActivos = clientes.filter((cliente) => cliente.activo).length;

  const totalCuentaCorriente = clientes.filter(
    (cliente) => cliente.condicionPago === "cuenta_corriente"
  ).length;

  function cancelarFormulario() {
    setMostrarFormulario(false);
    setClienteEditando(null);
    setFormulario(formularioVacio());
  }

  function abrirNuevoCliente() {
    cancelarFormulario();
    setMensaje("");
    setMostrarFormulario(true);
  }

  function editarCliente(cliente: Cliente) {
    setClienteEditando(cliente.id);

    setFormulario({
      nombreComercio: cliente.nombreComercio,
      titular: cliente.titular,
      telefono: cliente.telefono,
      direccion: cliente.direccion,
      zona: cliente.zona,
      condicionPago: cliente.condicionPago,
      limiteCredito: String(cliente.limiteCredito),
      activo: cliente.activo,
    });

    setMostrarFormulario(true);
    setMensaje("");
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function guardarCliente(evento: React.SubmitEvent<HTMLFormElement>) {
    evento.preventDefault();

    const limiteCredito = Number(formulario.limiteCredito);

    if (
      !formulario.nombreComercio.trim() ||
      !formulario.titular.trim() ||
      !formulario.direccion.trim() ||
      !formulario.zona.trim() ||
      formulario.limiteCredito.trim() === "" ||
      !Number.isFinite(limiteCredito) ||
      limiteCredito < 0
    ) {
      alert("Completá correctamente los datos del cliente.");
      return;
    }

    const datos = {
      nombreComercio: formulario.nombreComercio.trim(),
      titular: formulario.titular.trim(),
      telefono: formulario.telefono.trim(),
      direccion: formulario.direccion.trim(),
      zona: formulario.zona.trim(),
      condicionPago: formulario.condicionPago,
      limiteCredito:
        formulario.condicionPago === "contado" ? 0 : limiteCredito,
      activo: formulario.activo,
    };

    if (clienteEditando !== null) {
      setClientes((actuales) =>
        actuales.map((cliente) =>
          cliente.id === clienteEditando
            ? { ...cliente, ...datos }
            : cliente
        )
      );

      setMensaje("Cliente actualizado correctamente.");
    } else {
      setClientes((actuales) => [
        ...actuales,
        {
          id: Math.max(0, ...actuales.map((c) => c.id)) + 1,
          ...datos,
        },
      ]);

      setMensaje("Cliente registrado correctamente.");
    }

    cancelarFormulario();
  }

  return (
    <div className="space-y-6">
      {/* Encabezado */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-slate-800">
            Clientes
          </h1>
          <p className="mt-1 text-slate-500">
            Gestión de comercios y condiciones comerciales
          </p>
        </div>

        <button
          type="button"
          onClick={abrirNuevoCliente}
          className="flex min-h-11 items-center gap-2 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700"
        >
          <Plus size={20} />
          Nuevo cliente
        </button>
      </div>

      {/* Tarjetas de resumen */}
      <div className="grid gap-4 sm:grid-cols-3">
        {[
          { titulo: "Total de clientes", valor: clientes.length },
          { titulo: "Clientes activos", valor: totalActivos },
          {
            titulo: "Con cuenta corriente",
            valor: totalCuentaCorriente,
          },
        ].map((tarjeta) => (
          <div
            key={tarjeta.titulo}
            className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
          >
            <div className="mb-3 flex items-center gap-2 text-slate-500">
              <Users size={18} />
              <span className="text-sm">{tarjeta.titulo}</span>
            </div>
            <p className="text-3xl font-bold text-slate-800">
              {tarjeta.valor}
            </p>
          </div>
        ))}
      </div>

      {/* Mensaje de confirmación */}
      {mensaje && (
        <div
          role="status"
          className="flex items-center gap-2 rounded-lg border border-green-200 bg-green-50 p-4 text-green-800"
        >
          <CheckCircle2 size={20} />
          {mensaje}
        </div>
      )}

      {/* Formulario */}
      {mostrarFormulario && (
        <form
          onSubmit={guardarCliente}
          className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
        >
          <h2 className="mb-5 text-xl font-bold text-slate-800">
            {clienteEditando === null
              ? "Registrar cliente"
              : "Editar cliente"}
          </h2>

          <div className="grid gap-4 md:grid-cols-2">
            <label className="space-y-1 text-sm font-medium">
              <span>Nombre del comercio *</span>
              <input
                required
                value={formulario.nombreComercio}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    nombreComercio: e.target.value,
                  })
                }
                placeholder="Ej: Almacén Don Pedro"
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            <label className="space-y-1 text-sm font-medium">
              <span>Nombre del titular *</span>
              <input
                required
                value={formulario.titular}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    titular: e.target.value,
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            <label className="space-y-1 text-sm font-medium">
              <span>Teléfono</span>
              <input
                type="tel"
                value={formulario.telefono}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    telefono: e.target.value,
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            <label className="space-y-1 text-sm font-medium">
              <span>Dirección *</span>
              <input
                required
                value={formulario.direccion}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    direccion: e.target.value,
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            <label className="space-y-1 text-sm font-medium">
              <span>Zona de reparto *</span>
              <input
                required
                value={formulario.zona}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    zona: e.target.value,
                  })
                }
                placeholder="Ej: Centro"
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            <label className="space-y-1 text-sm font-medium">
              <span>Condición de pago</span>
              <select
                value={formulario.condicionPago}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    condicionPago: e.target.value as CondicionPago,
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
              >
                <option value="contado">Contado</option>
                <option value="cuenta_corriente">Cuenta corriente</option>
              </select>
            </label>

            {formulario.condicionPago === "cuenta_corriente" && (
              <label className="space-y-1 text-sm font-medium">
                <span>Límite de crédito ($)</span>
                <input
                  required
                  type="number"
                  min="0"
                  step="0.01"
                  value={formulario.limiteCredito}
                  onChange={(e) =>
                    setFormulario({
                      ...formulario,
                      limiteCredito: e.target.value,
                    })
                  }
                  className="w-full rounded-lg border border-slate-300 p-3"
                />
              </label>
            )}

            <label className="flex items-center gap-3 self-end rounded-lg border border-slate-200 p-3">
              <input
                type="checkbox"
                checked={formulario.activo}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    activo: e.target.checked,
                  })
                }
                className="h-5 w-5"
              />
              <span className="text-sm font-medium">
                Cliente activo
              </span>
            </label>
          </div>

          <div className="mt-6 flex flex-wrap gap-3">
            <button
              type="submit"
              className="min-h-11 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white"
            >
              {clienteEditando === null
                ? "Guardar cliente"
                : "Guardar cambios"}
            </button>

            <button
              type="button"
              onClick={cancelarFormulario}
              className="min-h-11 rounded-lg border border-slate-300 px-5 py-3"
            >
              Cancelar
            </button>
          </div>
        </form>
      )}

      {/* Buscador y filtro */}
      <div className="flex flex-col gap-3 sm:flex-row">
        <div className="flex flex-1 items-center gap-3 rounded-xl border border-slate-200 bg-white p-4">
          <Search size={20} className="text-slate-400" />
          <input
            value={busqueda}
            onChange={(e) => setBusqueda(e.target.value)}
            placeholder="Buscar comercio, titular o zona..."
            aria-label="Buscar clientes"
            className="w-full outline-none"
          />
        </div>

        <select
          value={filtro}
          onChange={(e) => setFiltro(e.target.value)}
          aria-label="Filtrar clientes"
          className="min-h-12 rounded-xl border border-slate-200 bg-white px-4"
        >
          <option value="todos">Todos</option>
          <option value="activos">Activos</option>
          <option value="inactivos">Inactivos</option>
          <option value="cuenta_corriente">Cuenta corriente</option>
        </select>
      </div>

      {/* Tabla */}
      <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-sm">
        <table className="w-full min-w-[900px] text-left">
          <thead className="bg-slate-50 text-sm text-slate-500">
            <tr>
              <th className="px-5 py-4">Comercio</th>
              <th className="px-5 py-4">Contacto</th>
              <th className="px-5 py-4">Zona</th>
              <th className="px-5 py-4">Condición</th>
              <th className="px-5 py-4">Estado</th>
              <th className="px-5 py-4">Acciones</th>
            </tr>
          </thead>

          <tbody className="divide-y divide-slate-100">
            {clientesFiltrados.map((cliente) => (
              <tr key={cliente.id} className="hover:bg-slate-50">
                <td className="px-5 py-4">
                  <p className="font-semibold text-slate-800">
                    {cliente.nombreComercio}
                  </p>
                  <p className="flex items-center gap-1 text-xs text-slate-500">
                    <MapPin size={13} />
                    {cliente.direccion}
                  </p>
                </td>

                <td className="px-5 py-4">
                  <p>{cliente.titular}</p>
                  <p className="flex items-center gap-1 text-xs text-slate-500">
                    <Phone size={13} />
                    {cliente.telefono || "Sin teléfono"}
                  </p>
                </td>

                <td className="px-5 py-4">{cliente.zona}</td>

                <td className="px-5 py-4">
                  <p className="text-sm">
                    {cliente.condicionPago === "contado"
                      ? "Contado"
                      : "Cuenta corriente"}
                  </p>
                  {cliente.condicionPago === "cuenta_corriente" && (
                    <p className="text-xs text-slate-500">
                      Límite: {formatoMoneda(cliente.limiteCredito)}
                    </p>
                  )}
                </td>

                <td className="px-5 py-4">
                  <span
                    className={`rounded-full px-3 py-1 text-xs font-medium ${
                      cliente.activo
                        ? "bg-green-100 text-green-700"
                        : "bg-slate-200 text-slate-600"
                    }`}
                  >
                    {cliente.activo ? "Activo" : "Inactivo"}
                  </span>
                </td>

                <td className="px-5 py-4">
                  <button
                    type="button"
                    onClick={() => editarCliente(cliente)}
                    className="flex min-h-11 items-center gap-2 rounded-lg border border-slate-200 px-3 text-blue-600 hover:bg-blue-50"
                  >
                    <Pencil size={16} />
                    Editar
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {clientesFiltrados.length === 0 && (
          <p className="p-8 text-center text-slate-500">
            No se encontraron clientes.
          </p>
        )}
      </div>

      <p className="text-sm text-slate-500">
        Datos de demostración guardados solamente en este navegador.
        Las ventas, los saldos y las cuentas corrientes se incorporarán
        en próximos módulos.
      </p>
    </div>
  );
}
