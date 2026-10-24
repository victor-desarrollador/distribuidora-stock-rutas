import { useMemo, useState } from "react";
import {
  AlertTriangle,
  BadgeCheck,
  CheckCircle2,
  MapPin,
  Pencil,
  Phone,
  Plus,
  Power,
  Search,
  Users,
} from "lucide-react";

import { useAuth } from "../auth/useAuth";
import { useCatalogoClientes } from "../hooks/useCatalogoClientes";
import {
  normalizarDatosCliente,
  permisosClientes,
  validarDatosCliente,
  type ClienteCatalogo,
  type EntradaCliente,
} from "../lib/clientes";

function formularioVacio(): EntradaCliente {
  return { nombre: "", telefono: "", comercio: "", direccion: "" };
}

export default function Clientes() {
  const { usuario } = useAuth();
  // Sólo para mostrar u ocultar acciones: la frontera real es la base (RPC +
  // RLS). Dueño y encargado crean, editan, validan y activan/desactivan; el
  // vendedor/piloto sólo crea (queda pendiente) y consulta.
  const permisos = permisosClientes(usuario?.rol);

  const { catalogo, recargar, crear, actualizar, validar, cambiarEstado } =
    useCatalogoClientes();
  const disponible = catalogo.estado === "listo";
  const clientes = useMemo(
    () => (catalogo.estado === "listo" ? catalogo.clientes : []),
    [catalogo]
  );

  const [busqueda, setBusqueda] = useState("");
  const [filtro, setFiltro] = useState("todos");
  const [mostrarFormulario, setMostrarFormulario] = useState(false);
  const [clienteEditando, setClienteEditando] =
    useState<ClienteCatalogo | null>(null);
  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");
  // Evita envíos dobles mientras una escritura está en curso.
  const [enviando, setEnviando] = useState(false);

  const [formulario, setFormulario] =
    useState<EntradaCliente>(formularioVacio);

  const mostrarAcciones =
    permisos.puedeEditar || permisos.puedeValidar || permisos.puedeCambiarEstado;

  // Filtrar clientes sin modificar el catálogo.
  const clientesFiltrados = useMemo(() => {
    const termino = busqueda.trim().toLocaleLowerCase("es-AR");

    return clientes.filter((cliente) => {
      const coincideBusqueda = [
        cliente.nombre,
        cliente.comercio ?? "",
        cliente.telefono,
        cliente.direccion ?? "",
      ].some((valor) => valor.toLocaleLowerCase("es-AR").includes(termino));

      const coincideEstado =
        filtro === "todos" ||
        (filtro === "activos" && cliente.activo) ||
        (filtro === "inactivos" && !cliente.activo) ||
        (filtro === "pendientes" && cliente.estadoValidacion === "pendiente");

      return coincideBusqueda && coincideEstado;
    });
  }, [clientes, busqueda, filtro]);

  const totalActivos = clientes.filter((c) => c.activo).length;
  const totalPendientes = clientes.filter(
    (c) => c.estadoValidacion === "pendiente"
  ).length;

  function cancelarFormulario() {
    setMostrarFormulario(false);
    setClienteEditando(null);
    setFormulario(formularioVacio());
  }

  function abrirNuevoCliente() {
    if (!permisos.puedeCrear || !disponible) return;
    cancelarFormulario();
    setMensaje("");
    setError("");
    setMostrarFormulario(true);
  }

  function editarCliente(cliente: ClienteCatalogo) {
    if (!permisos.puedeEditar) return;
    setClienteEditando(cliente);
    setFormulario({
      nombre: cliente.nombre,
      telefono: cliente.telefono,
      comercio: cliente.comercio ?? "",
      direccion: cliente.direccion ?? "",
    });
    setMensaje("");
    setError("");
    setMostrarFormulario(true);

    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  // Guardar un cliente nuevo o actualizar uno existente.
  async function guardarCliente(evento: React.SubmitEvent<HTMLFormElement>) {
    evento.preventDefault();
    if (!disponible || enviando) return;

    const editando = clienteEditando !== null;
    if (editando ? !permisos.puedeEditar : !permisos.puedeCrear) return;

    setMensaje("");
    setError("");

    // Validación previa al envío. La base vuelve a validar todo: es la
    // autoridad.
    const datos = normalizarDatosCliente(formulario);
    const errorValidacion = validarDatosCliente(datos);
    if (errorValidacion) {
      setError(errorValidacion);
      return;
    }

    setEnviando(true);

    const resultado = editando
      ? await actualizar(clienteEditando.id, datos)
      : await crear(datos);

    setEnviando(false);

    if (!resultado.ok) {
      setError(resultado.error);
      return;
    }

    setMensaje(
      editando
        ? "Cliente actualizado correctamente."
        : permisos.puedeValidar
          ? "Cliente agregado correctamente."
          : "Cliente agregado correctamente. Queda pendiente de validación."
    );
    cancelarFormulario();
  }

  async function validarCliente(cliente: ClienteCatalogo) {
    if (!permisos.puedeValidar || !disponible || enviando) return;

    setMensaje("");
    setError("");
    setEnviando(true);

    const resultado = await validar(cliente.id);

    setEnviando(false);

    if (!resultado.ok) {
      setError(resultado.error);
      return;
    }

    setMensaje(`${cliente.nombre} quedó validado.`);
  }

  // Activar o desactivar (baja lógica: no hay borrado).
  async function alternarEstado(cliente: ClienteCatalogo) {
    if (!permisos.puedeCambiarEstado || !disponible || enviando) return;

    setMensaje("");
    setError("");
    setEnviando(true);

    const resultado = await cambiarEstado(cliente.id, !cliente.activo);

    setEnviando(false);

    if (!resultado.ok) {
      setError(resultado.error);
      return;
    }

    setMensaje(
      cliente.activo
        ? `${cliente.nombre} quedó desactivado.`
        : `${cliente.nombre} quedó activado.`
    );
  }

  return (
    <div className="space-y-6">
      {/* Encabezado */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-slate-800">Clientes</h1>

          <p className="mt-1 text-slate-500">Catálogo de clientes</p>
        </div>

        {permisos.puedeCrear && (
          <button
            type="button"
            onClick={abrirNuevoCliente}
            disabled={!disponible || enviando}
            className="flex min-h-11 items-center gap-2 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700 disabled:opacity-60"
          >
            <Plus size={20} />
            Nuevo cliente
          </button>
        )}
      </div>

      {/* Error de lectura: sin datos viejos */}
      {catalogo.estado === "error" && (
        <div
          role="alert"
          className="flex flex-wrap items-center gap-3 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800"
        >
          <AlertTriangle size={20} />
          <span>{catalogo.error}</span>
          <button
            type="button"
            onClick={() => void recargar()}
            className="min-h-11 rounded-lg border border-red-300 px-4 hover:bg-red-100"
          >
            Reintentar
          </button>
        </div>
      )}

      {/* Tarjetas de resumen */}
      {disponible && (
        <div className="grid gap-4 sm:grid-cols-3">
          {[
            { titulo: "Total de clientes", valor: clientes.length },
            { titulo: "Clientes activos", valor: totalActivos },
            { titulo: "Pendientes de validar", valor: totalPendientes },
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
      )}

      {/* Error de una operación */}
      {error && (
        <div
          role="alert"
          className="flex items-center gap-3 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800"
        >
          <AlertTriangle size={20} />
          {error}
        </div>
      )}

      {/* Mensaje de confirmación */}
      {mensaje && (
        <div
          role="status"
          className="flex items-center gap-3 rounded-lg border border-green-200 bg-green-50 p-4 text-sm text-green-800"
        >
          <CheckCircle2 size={20} />
          {mensaje}
        </div>
      )}

      {/* Formulario para agregar (todos los roles) o editar (dueño/encargado) */}
      {mostrarFormulario &&
        (clienteEditando !== null ? permisos.puedeEditar : permisos.puedeCrear) && (
          <form
            onSubmit={guardarCliente}
            className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
          >
            <h2 className="mb-5 text-lg font-semibold text-slate-800">
              {clienteEditando !== null ? "Editar cliente" : "Agregar cliente"}
            </h2>

            <div className="grid gap-4 md:grid-cols-2">
              <label className="space-y-1 text-sm font-medium">
                <span>Nombre del cliente *</span>
                <input
                  required
                  value={formulario.nombre}
                  onChange={(e) =>
                    setFormulario({ ...formulario, nombre: e.target.value })
                  }
                  className="w-full rounded-lg border border-slate-300 p-3"
                  placeholder="Ej: Pedro González"
                />
              </label>

              <label className="space-y-1 text-sm font-medium">
                <span>Teléfono *</span>
                <input
                  required
                  type="tel"
                  value={formulario.telefono}
                  onChange={(e) =>
                    setFormulario({ ...formulario, telefono: e.target.value })
                  }
                  className="w-full rounded-lg border border-slate-300 p-3"
                />
              </label>

              <label className="space-y-1 text-sm font-medium">
                <span>Comercio (opcional)</span>
                <input
                  value={formulario.comercio}
                  onChange={(e) =>
                    setFormulario({ ...formulario, comercio: e.target.value })
                  }
                  className="w-full rounded-lg border border-slate-300 p-3"
                  placeholder="Ej: Almacén Don Pedro"
                />
              </label>

              <label className="space-y-1 text-sm font-medium">
                <span>Dirección (opcional)</span>
                <input
                  value={formulario.direccion}
                  onChange={(e) =>
                    setFormulario({ ...formulario, direccion: e.target.value })
                  }
                  className="w-full rounded-lg border border-slate-300 p-3"
                />
              </label>
            </div>

            {clienteEditando === null && !permisos.puedeValidar && (
              <p className="mt-4 text-sm text-slate-500">
                El cliente queda pendiente hasta que el dueño o el encargado lo
                validen.
              </p>
            )}

            {/* Acciones del formulario */}
            <div className="mt-6 flex flex-wrap gap-3">
              <button
                type="submit"
                disabled={!disponible || enviando}
                className="min-h-11 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700 disabled:opacity-60"
              >
                {clienteEditando !== null
                  ? "Guardar cambios"
                  : "Guardar cliente"}
              </button>

              <button
                type="button"
                onClick={cancelarFormulario}
                className="min-h-11 rounded-lg border border-slate-300 px-5 py-3 hover:bg-slate-50"
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
            placeholder="Buscar por nombre, comercio, teléfono o dirección..."
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
          <option value="pendientes">Pendientes de validar</option>
        </select>
      </div>

      {/* Tabla de clientes */}
      <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-sm">
        <table className="w-full min-w-[820px] text-left">
          <thead className="bg-slate-50 text-sm text-slate-500">
            <tr>
              <th className="px-5 py-4">Cliente</th>
              <th className="px-5 py-4">Teléfono</th>
              <th className="px-5 py-4">Dirección</th>
              <th className="px-5 py-4">Validación</th>
              <th className="px-5 py-4">Estado</th>
              {mostrarAcciones && <th className="px-5 py-4">Acciones</th>}
            </tr>
          </thead>

          <tbody className="divide-y divide-slate-100">
            {clientesFiltrados.map((cliente) => (
              <tr key={cliente.id} className="hover:bg-slate-50">
                {/* Nombre y comercio */}
                <td className="px-5 py-4">
                  <p className="font-semibold text-slate-800">
                    {cliente.nombre}
                  </p>
                  {cliente.comercio && (
                    <p className="text-xs text-slate-500">{cliente.comercio}</p>
                  )}
                </td>

                {/* Teléfono */}
                <td className="px-5 py-4 text-slate-700">
                  <span className="flex items-center gap-1">
                    <Phone size={13} className="text-slate-400" />
                    {cliente.telefono}
                  </span>
                </td>

                {/* Dirección */}
                <td className="px-5 py-4 text-slate-700">
                  {cliente.direccion ? (
                    <span className="flex items-center gap-1">
                      <MapPin size={13} className="text-slate-400" />
                      {cliente.direccion}
                    </span>
                  ) : (
                    <span className="text-slate-400">Sin dirección</span>
                  )}
                </td>

                {/* Validación */}
                <td className="px-5 py-4">
                  <span
                    className={`rounded-full px-3 py-1 text-xs font-medium ${
                      cliente.estadoValidacion === "validado"
                        ? "bg-blue-100 text-blue-700"
                        : "bg-amber-100 text-amber-800"
                    }`}
                  >
                    {cliente.estadoValidacion === "validado"
                      ? "Validado"
                      : "Pendiente"}
                  </span>
                </td>

                {/* Estado */}
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

                {/* Acciones (según rol) */}
                {mostrarAcciones && (
                  <td className="px-5 py-4">
                    <div className="flex flex-wrap gap-2">
                      {permisos.puedeEditar && (
                        <button
                          type="button"
                          onClick={() => editarCliente(cliente)}
                          disabled={enviando}
                          aria-label={`Editar ${cliente.nombre}`}
                          className="flex min-h-11 items-center gap-2 rounded-lg border border-slate-200 px-3 text-blue-600 hover:bg-blue-50 disabled:opacity-60"
                        >
                          <Pencil size={16} />
                          Editar
                        </button>
                      )}

                      {permisos.puedeValidar &&
                        cliente.estadoValidacion === "pendiente" && (
                          <button
                            type="button"
                            onClick={() => void validarCliente(cliente)}
                            disabled={enviando}
                            aria-label={`Validar ${cliente.nombre}`}
                            className="flex min-h-11 items-center gap-2 rounded-lg border border-slate-200 px-3 text-green-700 hover:bg-green-50 disabled:opacity-60"
                          >
                            <BadgeCheck size={16} />
                            Validar
                          </button>
                        )}

                      {permisos.puedeCambiarEstado && (
                        <button
                          type="button"
                          onClick={() => void alternarEstado(cliente)}
                          disabled={enviando}
                          aria-label={`${
                            cliente.activo ? "Desactivar" : "Activar"
                          } ${cliente.nombre}`}
                          className="flex min-h-11 items-center gap-2 rounded-lg border border-slate-200 px-3 text-slate-700 hover:bg-slate-100 disabled:opacity-60"
                        >
                          <Power size={16} />
                          {cliente.activo ? "Desactivar" : "Activar"}
                        </button>
                      )}
                    </div>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>

        {catalogo.estado === "cargando" && (
          <p role="status" className="p-8 text-center text-slate-500">
            Cargando clientes…
          </p>
        )}

        {disponible && clientesFiltrados.length === 0 && (
          <p className="p-8 text-center text-slate-500">
            No se encontraron clientes.
          </p>
        )}
      </div>

      {/* Alcance del catálogo real */}
      <p className="text-sm text-slate-500">
        Catálogo guardado en la base de datos. Autoventa, cuentas corrientes y
        movimientos todavía usan clientes de demostración guardados en este
        navegador; no se actualizan con este catálogo. Las ventas, los saldos y
        las cuentas corrientes reales se incorporarán en módulos posteriores.
      </p>
    </div>
  );
}
