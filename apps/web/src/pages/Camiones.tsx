
import { useMemo, useState } from "react";

import {
  Truck,
  Plus,
  Search,
  Pencil,
  Wrench,
  CheckCircle2,
} from "lucide-react";

import {
  type Camion,
  type EstadoCamion,
} from "../data/mockCamiones";

import { useCamiones } from "../hooks/useCamiones";

type FormularioCamion = {
  nombre: string;
  patente: string;
  marca: string;
  modelo: string;
  estado: "disponible" | "mantenimiento";
  observaciones: string;
};

function formularioVacio(): FormularioCamion {
  return {
    nombre: "",
    patente: "",
    marca: "",
    modelo: "",
    estado: "disponible",
    observaciones: "",
  };
}

const etiquetasEstado: Record<EstadoCamion, string> = {
  disponible: "Disponible",
  en_reparto: "En reparto",
  mantenimiento: "Mantenimiento",
};

export default function Camiones() {
  const { camiones, setCamiones } = useCamiones();

  const [busqueda, setBusqueda] = useState("");
  const [mostrarFormulario, setMostrarFormulario] = useState(false);
  const [camionEditando, setCamionEditando] = useState<number | null>(null);
  const [mensaje, setMensaje] = useState("");

  const [formulario, setFormulario] =
    useState<FormularioCamion>(formularioVacio);

  const camionesFiltrados = useMemo(() => {
    const termino = busqueda.trim().toLocaleLowerCase("es-AR");

    return camiones.filter((camion) =>
      `${camion.nombre} ${camion.patente} ${camion.marca} ${camion.modelo}`
        .toLocaleLowerCase("es-AR")
        .includes(termino)
    );
  }, [camiones, busqueda]);

  const disponibles = camiones.filter(
    (camion) => camion.estado === "disponible"
  ).length;

  const enReparto = camiones.filter(
    (camion) => camion.estado === "en_reparto"
  ).length;

  const enMantenimiento = camiones.filter(
    (camion) => camion.estado === "mantenimiento"
  ).length;

  function cancelarFormulario() {
    setMostrarFormulario(false);
    setCamionEditando(null);
    setFormulario(formularioVacio());
  }

  function abrirNuevoCamion() {
    cancelarFormulario();
    setMensaje("");
    setMostrarFormulario(true);
  }

  function editarCamion(camion: Camion) {
    setCamionEditando(camion.id);

    setFormulario({
      nombre: camion.nombre,
      patente: camion.patente,
      marca: camion.marca,
      modelo: camion.modelo,
      estado:
        camion.estado === "mantenimiento"
          ? "mantenimiento"
          : "disponible",
      observaciones: camion.observaciones,
    });

    setMensaje("");
    setMostrarFormulario(true);

    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function guardarCamion(evento: React.SubmitEvent<HTMLFormElement>) {
    evento.preventDefault();

    const nombre = formulario.nombre.trim();
    const patente = formulario.patente
      .replace(/\s|-/g, "")
      .toUpperCase();

    if (!nombre || !patente) {
      alert("Completá el nombre y la patente.");
      return;
    }

    const patenteDuplicada = camiones.some(
      (camion) =>
        camion.patente.replace(/\s|-/g, "").toUpperCase() ===
          patente && camion.id !== camionEditando
    );

    if (patenteDuplicada) {
      alert("Ya existe un camión con esa patente.");
      return;
    }

    const datos = {
      nombre,
      patente,
      marca: formulario.marca.trim(),
      modelo: formulario.modelo.trim(),
      observaciones: formulario.observaciones.trim(),
    };

    if (camionEditando !== null) {
      const actual = camiones.find(
        (camion) => camion.id === camionEditando
      );

      if (!actual) return;

      // El estado de un camión en reparto no se edita aquí.
      if (actual.estado === "en_reparto") {
        alert("Cerrá la jornada antes de modificar este camión.");
        return;
      }

      setCamiones((anteriores) =>
        anteriores.map((camion) =>
          camion.id === camionEditando
            ? { ...camion, ...datos, estado: formulario.estado }
            : camion
        )
      );

      setMensaje("Camión actualizado correctamente.");
    } else {
      setCamiones((anteriores) => [
        ...anteriores,
        {
          id: Math.max(0, ...anteriores.map((c) => c.id)) + 1,
          ...datos,
          estado: formulario.estado,
        },
      ]);

      setMensaje("Camión registrado correctamente.");
    }

    cancelarFormulario();
  }

  return (
    <div className="space-y-6">
      {/* Encabezado */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-slate-800">
            Camiones
          </h1>
          <p className="mt-1 text-slate-500">
            Administración de vehículos de reparto
          </p>
        </div>

        <button
          type="button"
          onClick={abrirNuevoCamion}
          className="flex min-h-11 items-center gap-2 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700"
        >
          <Plus size={20} />
          Nuevo camión
        </button>
      </div>

      {/* Estadísticas */}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {[
          { titulo: "Total camiones", valor: camiones.length },
          { titulo: "Disponibles", valor: disponibles },
          { titulo: "En reparto", valor: enReparto },
          { titulo: "Mantenimiento", valor: enMantenimiento },
        ].map((tarjeta) => (
          <div
            key={tarjeta.titulo}
            className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
          >
            <p className="text-sm text-slate-500">
              {tarjeta.titulo}
            </p>
            <p className="mt-2 text-3xl font-bold text-slate-900">
              {tarjeta.valor}
            </p>
          </div>
        ))}
      </div>

      {/* Mensaje */}
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
          onSubmit={guardarCamion}
          className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
        >
          <h2 className="mb-5 text-xl font-semibold">
            {camionEditando === null
              ? "Registrar camión"
              : "Editar camión"}
          </h2>

          <div className="grid gap-4 md:grid-cols-2">
            <label className="space-y-1 text-sm font-medium">
              <span>Nombre *</span>
              <input
                required
                value={formulario.nombre}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    nombre: e.target.value,
                  })
                }
                placeholder="Ej: Camión 04"
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            <label className="space-y-1 text-sm font-medium">
              <span>Patente *</span>
              <input
                required
                value={formulario.patente}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    patente: e.target.value,
                  })
                }
                placeholder="Ej: AH123IJ"
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            <label className="space-y-1 text-sm font-medium">
              <span>Marca</span>
              <input
                value={formulario.marca}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    marca: e.target.value,
                  })
                }
                placeholder="Ej: Iveco"
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            <label className="space-y-1 text-sm font-medium">
              <span>Modelo</span>
              <input
                value={formulario.modelo}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    modelo: e.target.value,
                  })
                }
                placeholder="Ej: Daily"
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            <label className="space-y-1 text-sm font-medium">
              <span>Estado</span>
              <select
                value={formulario.estado}
                disabled={
                  camionEditando !== null &&
                  camiones.some(
                    (c) =>
                      c.id === camionEditando &&
                      c.estado === "en_reparto"
                  )
                }
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    estado: e.target.value as FormularioCamion["estado"],
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3 disabled:bg-slate-100"
              >
                <option value="disponible">Disponible</option>
                <option value="mantenimiento">Mantenimiento</option>
              </select>
            </label>

            <label className="space-y-1 text-sm font-medium md:col-span-2">
              <span>Observaciones</span>
              <textarea
                value={formulario.observaciones}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    observaciones: e.target.value,
                  })
                }
                rows={3}
                placeholder="Ej: Vehículo refrigerado"
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>
          </div>

          <div className="mt-6 flex flex-wrap gap-3">
            <button
              type="submit"
              className="min-h-11 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white"
            >
              {camionEditando === null
                ? "Guardar camión"
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

      {/* Buscador */}
      <div className="flex items-center gap-3 rounded-xl border border-slate-200 bg-white p-4">
        <Search size={20} className="text-slate-400" />

        <input
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
          placeholder="Buscar por camión, patente o marca..."
          aria-label="Buscar camiones"
          className="w-full outline-none"
        />
      </div>

      {/* Tarjetas de camiones */}
      <div className="grid gap-4 lg:grid-cols-2">
        {camionesFiltrados.map((camion) => (
          <div
            key={camion.id}
            className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
          >
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="flex items-center gap-3">
                <div className="rounded-xl bg-blue-50 p-3">
                  <Truck size={26} className="text-blue-600" />
                </div>

                <div>
                  <h3 className="text-lg font-semibold text-slate-900">
                    {camion.nombre}
                  </h3>
                  <p className="text-sm text-slate-500">
                    {camion.patente}
                  </p>
                </div>
              </div>

              <span
                className={`rounded-full px-3 py-1 text-xs font-medium ${
                  camion.estado === "disponible"
                    ? "bg-green-100 text-green-700"
                    : camion.estado === "en_reparto"
                    ? "bg-blue-100 text-blue-700"
                    : "bg-amber-100 text-amber-800"
                }`}
              >
                {etiquetasEstado[camion.estado]}
              </span>
            </div>

            <div className="mt-5 space-y-2 text-sm text-slate-600">
              <p>
                <strong>Marca y modelo:</strong>{" "}
                {[camion.marca, camion.modelo].filter(Boolean).join(" ") ||
                  "No especificado"}
              </p>

              <p>
                <strong>Observaciones:</strong>{" "}
                {camion.observaciones || "Sin observaciones"}
              </p>
            </div>

            <div className="mt-5 flex flex-wrap gap-2 border-t border-slate-100 pt-4">
              <button
                type="button"
                onClick={() => editarCamion(camion)}
                disabled={camion.estado === "en_reparto"}
                className="flex min-h-11 items-center gap-2 rounded-lg border border-slate-200 px-4 text-blue-600 hover:bg-blue-50 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <Pencil size={17} />
                Editar
              </button>

              {camion.estado === "mantenimiento" && (
                <span className="flex items-center gap-2 text-sm text-amber-700">
                  <Wrench size={17} />
                  Vehículo en mantenimiento
                </span>
              )}
            </div>
          </div>
        ))}
      </div>

      {camionesFiltrados.length === 0 && (
        <p className="rounded-xl bg-white p-8 text-center text-slate-500">
          No se encontraron camiones.
        </p>
      )}

      <p className="text-sm text-slate-500">
        Prototipo: los camiones se guardan solamente en este navegador.
        Los choferes, las rutas y la mercadería se asignarán a las
        jornadas de reparto en el siguiente módulo.
      </p>
    </div>
  );
}
