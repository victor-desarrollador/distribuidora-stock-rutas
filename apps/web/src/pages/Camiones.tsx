import { useMemo, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  Pencil,
  Plus,
  Power,
  Search,
  Truck,
} from "lucide-react";

import { useAuth } from "../auth/useAuth";
import { useCatalogoCamiones } from "../hooks/useCatalogoCamiones";
import { type CamionCatalogo } from "../lib/camiones";

type FormularioCamion = {
  patente: string;
  nombre: string;
};

function formularioVacio(): FormularioCamion {
  return { patente: "", nombre: "" };
}

// Validación previa al envío. La base vuelve a validar todo: es la autoridad.
// La patente se envía tal como se escribe (sólo se recortan los extremos en
// el servidor): no se asume ningún formato.
function validarFormulario(formulario: FormularioCamion): string | null {
  if (formulario.patente.trim() === "") return "Ingresá la patente del camión.";
  if (formulario.nombre.trim() === "") return "Ingresá el nombre del camión.";
  return null;
}

export default function Camiones() {
  const { usuario } = useAuth();
  // Sólo para mostrar u ocultar acciones: la frontera real es la base (RPC +
  // RLS). Dueño escribe; encargado y vendedor/piloto sólo leen.
  const puedeEscribir = usuario?.rol === "dueno";

  const { catalogo, recargar, crear, actualizar, cambiarEstado } =
    useCatalogoCamiones();
  const disponible = catalogo.estado === "listo";
  const camiones = useMemo(
    () => (catalogo.estado === "listo" ? catalogo.camiones : []),
    [catalogo]
  );

  const [busqueda, setBusqueda] = useState("");
  const [mostrarFormulario, setMostrarFormulario] = useState(false);
  const [camionEditando, setCamionEditando] = useState<CamionCatalogo | null>(
    null
  );
  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");
  // Evita envíos dobles mientras una escritura está en curso.
  const [enviando, setEnviando] = useState(false);

  const [formulario, setFormulario] =
    useState<FormularioCamion>(formularioVacio);

  // Filtrar camiones sin modificar el catálogo.
  const camionesFiltrados = useMemo(() => {
    const termino = busqueda.trim().toLocaleLowerCase("es-AR");

    return camiones.filter((camion) =>
      `${camion.nombre} ${camion.patente}`
        .toLocaleLowerCase("es-AR")
        .includes(termino)
    );
  }, [camiones, busqueda]);

  function cancelarFormulario() {
    setMostrarFormulario(false);
    setCamionEditando(null);
    setFormulario(formularioVacio());
  }

  function abrirNuevoCamion() {
    if (!puedeEscribir || !disponible) return;
    cancelarFormulario();
    setMensaje("");
    setError("");
    setMostrarFormulario(true);
  }

  function editarCamion(camion: CamionCatalogo) {
    if (!puedeEscribir) return;
    setCamionEditando(camion);
    setFormulario({ patente: camion.patente, nombre: camion.nombre });
    setMensaje("");
    setError("");
    setMostrarFormulario(true);

    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  // Guardar un camión nuevo o actualizar uno existente.
  async function guardarCamion(evento: React.SubmitEvent<HTMLFormElement>) {
    evento.preventDefault();
    if (!puedeEscribir || !disponible || enviando) return;

    setMensaje("");
    setError("");

    const errorValidacion = validarFormulario(formulario);
    if (errorValidacion) {
      setError(errorValidacion);
      return;
    }

    setEnviando(true);

    const datos = { patente: formulario.patente, nombre: formulario.nombre };
    const resultado =
      camionEditando !== null
        ? await actualizar(camionEditando.id, datos)
        : await crear(datos);

    setEnviando(false);

    if (!resultado.ok) {
      setError(resultado.error);
      return;
    }

    setMensaje(
      camionEditando !== null
        ? "Camión actualizado correctamente."
        : "Camión agregado correctamente."
    );
    cancelarFormulario();
  }

  // Activar o desactivar.
  async function alternarEstado(camion: CamionCatalogo) {
    if (!puedeEscribir || !disponible || enviando) return;

    setMensaje("");
    setError("");
    setEnviando(true);

    const resultado = await cambiarEstado(camion.id, !camion.activo);

    setEnviando(false);

    if (!resultado.ok) {
      setError(resultado.error);
      return;
    }

    setMensaje(
      camion.activo
        ? `${camion.nombre} quedó desactivado.`
        : `${camion.nombre} quedó activado.`
    );
  }

  return (
    <div className="space-y-6">
      {/* Encabezado */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-slate-800">Camiones</h1>

          <p className="mt-1 text-slate-500">Catálogo de camiones</p>
        </div>

        {puedeEscribir && (
          <button
            type="button"
            onClick={abrirNuevoCamion}
            disabled={!disponible || enviando}
            className="flex min-h-11 items-center gap-2 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700 disabled:opacity-60"
          >
            <Plus size={20} />
            Nuevo camión
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

      {/* Formulario para agregar o editar (sólo dueño) */}
      {puedeEscribir && mostrarFormulario && (
        <form
          onSubmit={guardarCamion}
          className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
        >
          <h2 className="mb-5 text-lg font-semibold text-slate-800">
            {camionEditando !== null ? "Editar camión" : "Agregar camión"}
          </h2>

          <div className="grid gap-4 md:grid-cols-2">
            {/* Nombre */}
            <label className="space-y-1 text-sm font-medium">
              <span>Nombre del camión</span>

              <input
                required
                value={formulario.nombre}
                onChange={(e) =>
                  setFormulario({ ...formulario, nombre: e.target.value })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
                placeholder="Ej: Camión 1"
              />
            </label>

            {/* Patente */}
            <label className="space-y-1 text-sm font-medium">
              <span>Patente</span>

              <input
                required
                value={formulario.patente}
                onChange={(e) =>
                  setFormulario({ ...formulario, patente: e.target.value })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
                placeholder="Ej: AA123BB"
              />

              <p className="text-xs font-normal text-slate-500">
                Se guarda tal como la escribís; no puede repetirse en la
                empresa.
              </p>
            </label>
          </div>

          {/* Acciones del formulario */}
          <div className="mt-6 flex flex-wrap gap-3">
            <button
              type="submit"
              disabled={!disponible || enviando}
              className="min-h-11 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700 disabled:opacity-60"
            >
              {camionEditando !== null ? "Guardar cambios" : "Guardar camión"}
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

      {/* Buscador */}
      <div className="flex items-center gap-3 rounded-xl border border-slate-200 bg-white p-4">
        <Search className="text-slate-400" size={22} />

        <input
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
          placeholder="Buscar por nombre o patente..."
          aria-label="Buscar camiones"
          className="w-full outline-none"
        />
      </div>

      {/* Tabla de camiones */}
      <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-sm">
        <table className="w-full min-w-[640px] text-left">
          <thead className="bg-slate-50 text-sm text-slate-500">
            <tr>
              <th className="px-5 py-4">Camión</th>
              <th className="px-5 py-4">Patente</th>
              <th className="px-5 py-4">Estado</th>
              {puedeEscribir && <th className="px-5 py-4">Acciones</th>}
            </tr>
          </thead>

          <tbody className="divide-y divide-slate-100">
            {camionesFiltrados.map((camion) => (
              <tr key={camion.id} className="hover:bg-slate-50">
                {/* Nombre */}
                <td className="px-5 py-4">
                  <div className="flex items-center gap-3">
                    <Truck size={20} className="text-blue-600" />

                    <span className="font-medium text-slate-800">
                      {camion.nombre}
                    </span>
                  </div>
                </td>

                {/* Patente */}
                <td className="px-5 py-4 text-slate-700">{camion.patente}</td>

                {/* Estado */}
                <td className="px-5 py-4">
                  <span
                    className={`rounded-full px-3 py-1 text-sm font-medium ${
                      camion.activo
                        ? "bg-green-100 text-green-700"
                        : "bg-slate-200 text-slate-600"
                    }`}
                  >
                    {camion.activo ? "Activo" : "Inactivo"}
                  </span>
                </td>

                {/* Acciones (sólo dueño) */}
                {puedeEscribir && (
                  <td className="px-5 py-4">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => editarCamion(camion)}
                        disabled={enviando}
                        aria-label={`Editar ${camion.nombre}`}
                        className="flex min-h-11 items-center gap-2 rounded-lg border border-slate-200 px-3 text-blue-600 hover:bg-blue-50 disabled:opacity-60"
                      >
                        <Pencil size={16} />
                        Editar
                      </button>

                      <button
                        type="button"
                        onClick={() => void alternarEstado(camion)}
                        disabled={enviando}
                        aria-label={`${
                          camion.activo ? "Desactivar" : "Activar"
                        } ${camion.nombre}`}
                        className="flex min-h-11 items-center gap-2 rounded-lg border border-slate-200 px-3 text-slate-700 hover:bg-slate-100 disabled:opacity-60"
                      >
                        <Power size={16} />
                        {camion.activo ? "Desactivar" : "Activar"}
                      </button>
                    </div>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>

        {catalogo.estado === "cargando" && (
          <p role="status" className="p-8 text-center text-slate-500">
            Cargando camiones…
          </p>
        )}

        {disponible && camionesFiltrados.length === 0 && (
          <p className="p-8 text-center text-slate-500">
            No se encontraron camiones.
          </p>
        )}
      </div>

      {/* Alcance del catálogo real */}
      <p className="text-sm text-slate-500">
        Catálogo guardado en la base de datos. La asignación a jornadas y el
        stock por camión se implementarán en los módulos correspondientes.
      </p>
    </div>
  );
}
