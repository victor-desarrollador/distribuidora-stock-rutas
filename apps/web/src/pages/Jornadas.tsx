import { useCallback, useMemo, useState } from "react";
import {
  Truck,
  Plus,
  Package,
  CheckCircle2,
  AlertTriangle,
  ClipboardList,
} from "lucide-react";
import { useCamiones } from "../hooks/useCamiones";
import { useProductos } from "../hooks/useProductos";
import { useJornadas } from "../hooks/useJornadas";
import { useRetornos } from "../hooks/useRetornos";
import { cantidad_a_texto } from "../domain/productos";
import {
  type Jornada,
  type ItemCarga,
} from "../data/mockJornadas";
import {
  atributos_input_carga,
  disponibilidad_carga,
  entrada_carga,
  precio_item_valido,
  valor_estimado_carga,
} from "./jornadas_preparacion";
import AvisoStorageOperativo from "../components/AvisoStorageOperativo";
import AvisoCatalogoDemo from "../components/AvisoCatalogoDemo";
import { estadoStorageOperativo } from "./estadoStorageOperativo";
const moneda = (valor: number) =>
  new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 2,
  }).format(valor);
// Stock, entrada y valor estimado: jornadas_preparacion.ts (misma semántica
// que la frontera de useJornadas; sin copia local).
export default function Jornadas() {
  const { camiones, estadoLectura: estadoCamiones } = useCamiones();
  const { productos, estadoLectura: estadoProductos } = useProductos();
  const { retornos, estadoLectura: estadoRetornos } = useRetornos();
  const {
    jornadas,
    crearPreparacion,
    confirmarSalida,
    estadoLectura: estadoJornadas,
  } = useJornadas();
  const estadoOperacion = estadoStorageOperativo({
    jornadas: estadoJornadas,
    productos: estadoProductos,
    camiones: estadoCamiones,
    retornos: estadoRetornos,
  });
  const [mostrarFormulario, setMostrarFormulario] = useState(false);
  const [camionId, setCamionId] = useState("");
  const [chofer, setChofer] = useState("");
  const [zona, setZona] = useState("");
  // Texto del input de cada producto: entero ("unidad") o kg con coma y
  // hasta 3 decimales ("peso").
  const [cantidades, setCantidades] = useState<Record<number, string>>({});
  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");
  // Disponible = stock − (cargas − retornos aprobados), con la misma función
  // que la frontera. ok: false si el reservado es incalculable: la carga no
  // se habilita.
  const disponibilidad = useMemo(
    () => disponibilidad_carga(productos, jornadas, retornos),
    [productos, jornadas, retornos]
  );
  // Camiones sin otra jornada activa y fuera de mantenimiento.
  const camionesDisponibles = camiones.filter((camion) => {
    if (camion.estado !== "disponible") return false;
    return !jornadas.some(
      (jornada) =>
        jornada.camionId === camion.id &&
        jornada.estado !== "cerrada"
    );
  });
  const entradaDe = useCallback(
    (producto: { id: number; unidadMedida: ItemCarga["unidadMedida"] }) =>
      entrada_carga(producto.unidadMedida, cantidades[producto.id] ?? ""),
    [cantidades]
  );

  // Cantidad canónica: unidades enteras o gramos enteros.
  const itemsSeleccionados = useMemo(() => {
    const items: ItemCarga[] = [];
    for (const producto of productos) {
      const entrada = entradaDe(producto);
      if (entrada.estado !== "valida") continue;
      items.push({
        productoId: producto.id,
        nombreProducto: producto.nombre,
        unidadMedida: producto.unidadMedida,
        cantidad: entrada.cantidad,
        precioReferencia: producto.precio,
      });
    }
    return items;
  }, [productos, entradaDe]);
  // P-B2-1: null con cualquier línea `peso` (sin subtotal parcial).
  const valorCarga = valor_estimado_carga(itemsSeleccionados);
  const jornadasOrdenadas = [...jornadas].sort((a, b) =>
    b.fechaCreacion.localeCompare(a.fechaCreacion)
  );
  const jornadasAbiertas = jornadas.filter(
    (j) => j.estado === "abierta"
  ).length;
  const jornadasPreparacion = jornadas.filter(
    (j) => j.estado === "preparacion"
  ).length;
  function limpiarFormulario() {
    setMostrarFormulario(false);
    setCamionId("");
    setChofer("");
    setZona("");
    setCantidades({});
  }
  function abrirFormulario() {
    if (estadoOperacion.bloqueado) return;
    setError("");
    setMensaje("");
    setMostrarFormulario(true);
  }
  function guardarPreparacion() {
    setError("");
    setMensaje("");
    if (estadoOperacion.bloqueado || !disponibilidad.ok) return;
    const idCamion = Number(camionId);
    if (
      !camionId ||
      !camionesDisponibles.some((c) => c.id === idCamion)
    ) {
      setError("Seleccioná un camión disponible.");
      return;
    }
    if (!chofer.trim() || !zona.trim()) {
      setError("Completá el chofer y la zona de reparto.");
      return;
    }
    // M-3 (bloque E): el stock NO se comprueba aquí con el snapshot del
    // render. Las cantidades de la UX sí; el stock se valida dentro de la
    // frontera, con Productos, Jornadas y Retornos releídos al persistir.
    for (const producto of productos) {
      if (entradaDe(producto).estado === "invalida") {
        setError(
          producto.unidadMedida === "peso"
            ? `Cantidad inválida: ${producto.nombre}. Ingresá kg con coma y hasta 3 decimales (ej. 1,250).`
            : `Cantidad inválida: ${producto.nombre}`
        );
        return;
      }
    }
    if (itemsSeleccionados.length === 0) {
      setError("Agregá al menos un producto a la carga.");
      return;
    }

    // Validación defensiva de precios: una línea `unidad` debe poder
    // valorizarse; una `peso` sólo exige precio por kg válido (sin D-R1).
    for (const item of itemsSeleccionados) {
      if (!precio_item_valido(item)) {
        setError(`Precio inválido: ${item.nombreProducto}`);
        return;
      }
    }

    const jornada: Jornada = {
      id: crypto.randomUUID(),
      camionId: idCamion,
      chofer: chofer.trim(),
      zona: zona.trim(),
      fechaCreacion: new Date().toISOString(),
      fechaSalida: null,
      estado: "preparacion",
      items: itemsSeleccionados,
    };

    // El stock se valida en la frontera, con Productos, Jornadas y Retornos
    // releídos justo antes de persistir.
    const errorPreparacion = crearPreparacion(jornada);

    if (errorPreparacion) {
      setError(errorPreparacion);
      return;
    }

    limpiarFormulario();
    setMensaje("Carga preparada correctamente.");
  }
  function iniciarReparto(jornada: Jornada) {
    setError("");
    setMensaje("");
    if (estadoOperacion.bloqueado) return;
    if (jornada.estado !== "preparacion") return;
    const camion = camiones.find(
      (c) => c.id === jornada.camionId
    );
    if (!camion || camion.estado !== "disponible") {
      setError("El camión ya no está disponible.");
      return;
    }
    // El error concreto de la frontera persistida se muestra tal cual.
    const errorSalida = confirmarSalida(jornada.id);
    if (errorSalida) {
      setError(errorSalida);
      return;
    }
    setMensaje(
      `Salida confirmada: ${camion.nombre}.`
    );
  }
  return (
    <div className="space-y-6">
      {/* Encabezado */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-slate-800">
            Jornadas de reparto
          </h1>
          <p className="mt-1 text-slate-500">
            Preparación de cargas y salidas de camiones
          </p>
        </div>
        <button
          type="button"
          onClick={abrirFormulario}
          disabled={estadoOperacion.bloqueado}
          className="flex min-h-12 items-center gap-2 rounded-lg bg-blue-600 px-5 font-medium text-white hover:bg-blue-700"
        >
          <Plus size={20} />
          Nueva jornada
        </button>
      </div>
      <AvisoStorageOperativo avisos={estadoOperacion.avisos} />
      <AvisoCatalogoDemo />
      {/* Estadísticas */}
      <div className="grid gap-4 sm:grid-cols-3">
        {[
          {
            titulo: "Total jornadas",
            valor: jornadas.length,
          },
          {
            titulo: "En preparación",
            valor: jornadasPreparacion,
          },
          {
            titulo: "En reparto",
            valor: jornadasAbiertas,
          },
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
      {/* Mensajes */}
      {mensaje && (
        <div
          role="status"
          className="flex items-center gap-2 rounded-lg bg-green-50 p-4 text-green-800"
        >
          <CheckCircle2 size={20} />
          {mensaje}
        </div>
      )}
      {error && (
        <div
          role="alert"
          className="flex items-center gap-2 rounded-lg bg-red-50 p-4 text-red-800"
        >
          <AlertTriangle size={20} />
          {error}
        </div>
      )}
      {/* Nueva jornada */}
      {mostrarFormulario && (
        <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm md:p-6">
          <h2 className="mb-5 text-xl font-bold text-slate-800">
            Preparar carga del camión
          </h2>
          <div className="grid gap-4 md:grid-cols-3">
            <label className="space-y-2 text-sm font-medium">
              <span>Camión *</span>
              <select
                value={camionId}
                onChange={(e) => setCamionId(e.target.value)}
                className="min-h-12 w-full rounded-lg border border-slate-300 p-3"
              >
                <option value="">Seleccionar camión</option>
                {camionesDisponibles.map((camion) => (
                  <option
                    key={camion.id}
                    value={camion.id}
                  >
                    {camion.nombre} · {camion.patente}
                  </option>
                ))}
              </select>
            </label>
            <label className="space-y-2 text-sm font-medium">
              <span>Chofer *</span>
              <input
                value={chofer}
                onChange={(e) => setChofer(e.target.value)}
                placeholder="Ej: Carlos Gómez"
                className="min-h-12 w-full rounded-lg border border-slate-300 p-3"
              />
            </label>
            <label className="space-y-2 text-sm font-medium">
              <span>Zona *</span>
              <input
                value={zona}
                onChange={(e) => setZona(e.target.value)}
                placeholder="Ej: Zona Centro"
                className="min-h-12 w-full rounded-lg border border-slate-300 p-3"
              />
            </label>
          </div>
          <h3 className="mb-3 mt-8 text-lg font-semibold">
            Mercadería para cargar
          </h3>
          <p className="mb-4 text-sm text-slate-500">
            Las cantidades disponibles contemplan las cargas
            y los retornos aprobados al depósito en esta demo.
          </p>
          {!disponibilidad.ok && (
            <p
              role="alert"
              className="mb-4 rounded-lg bg-red-50 p-3 text-sm text-red-800"
            >
              No se puede calcular el stock disponible: hay cargas o retornos
              inconsistentes. No se puede preparar una carga.
            </p>
          )}
          <div className="space-y-3">
            {productos.map((producto) => {
              const disponible = disponibilidad.ok
                ? disponibilidad.disponibles[producto.id]
                : null;
              const esPeso = producto.unidadMedida === "peso";
              const { sufijo, ...atributos } = atributos_input_carga(
                producto.unidadMedida,
                disponible
              );
              return (
                <div
                  key={producto.id}
                  className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-slate-200 p-4"
                >
                  <div className="flex min-w-0 items-center gap-3">
                    <Package
                      className="shrink-0 text-blue-600"
                      size={23}
                    />
                    <div>
                      <p className="font-medium text-slate-800">
                        {producto.nombre}
                      </p>
                      <p className="text-sm text-slate-500">
                        {disponible === null
                          ? "Disponible: no calculable"
                          : disponible < 0
                          ? `Disponible: sin stock (lo cargado supera el stock en ${cantidad_a_texto(producto.unidadMedida, -disponible)})`
                          : `Disponible: ${cantidad_a_texto(producto.unidadMedida, disponible)}`}
                      </p>
                      <p className="text-xs text-slate-400">
                        {moneda(producto.precio)} por{" "}
                        {esPeso ? "kg" : "unidad"}
                      </p>
                    </div>
                  </div>
                  <label className="flex items-center gap-2 text-sm">
                    <span>Cargar:</span>
                    {/* unidad: type number (como antes); peso: texto en kg
                        con coma. La interpretación es siempre entrada_carga. */}
                    <input
                      {...atributos}
                      value={cantidades[producto.id] ?? ""}
                      onChange={(e) =>
                        setCantidades((actuales) => ({
                          ...actuales,
                          [producto.id]: e.target.value,
                        }))
                      }
                      className={`min-h-12 ${esPeso ? "w-28" : "w-24"} rounded-lg border border-slate-300 p-3 text-right`}
                      aria-label={`Cantidad de ${producto.nombre}${esPeso ? " en kg" : ""}`}
                    />
                    <span className="w-10 text-slate-500">
                      {sufijo}
                    </span>
                  </label>
                </div>
              );
            })}
          </div>
          {/* Resumen */}
          <div className="mt-6 rounded-xl bg-blue-50 p-5">
            <p className="text-sm font-medium text-blue-700">
              Valor estimado de la carga
            </p>
            <p className="mt-1 text-3xl font-bold text-blue-900">
              {valorCarga === null ? "Sin valorizar" : moneda(valorCarga)}
            </p>
            <p className="mt-1 text-xs text-blue-700">
              {valorCarga === null
                ? "Las cargas con productos por peso no se valorizan todavía."
                : "Calculado con precios de venta de referencia."}
            </p>
          </div>
          <div className="mt-6 flex flex-wrap gap-3">
            <button
              type="button"
              onClick={guardarPreparacion}
              disabled={estadoOperacion.bloqueado || !disponibilidad.ok}
              className="min-h-12 rounded-lg bg-blue-600 px-5 font-semibold text-white"
            >
              Guardar preparación
            </button>
            <button
              type="button"
              onClick={limpiarFormulario}
              className="min-h-12 rounded-lg border border-slate-300 px-5"
            >
              Cancelar
            </button>
          </div>
        </section>
      )}
      {/* Listado de jornadas */}
      <section className="space-y-4">
        <h2 className="text-xl font-bold text-slate-800">
          Jornadas registradas
        </h2>
        {jornadasOrdenadas.length === 0 && (
          <div className="rounded-xl bg-white p-10 text-center text-slate-500">
            <ClipboardList
              className="mx-auto mb-3"
              size={36}
            />
            Todavía no hay jornadas registradas.
          </div>
        )}
        {jornadasOrdenadas.map((jornada) => {
          const camion = camiones.find(
            (c) => c.id === jornada.camionId
          );
          // P-B2-1: una jornada con ítems `peso` no se valoriza (D-R1, B3).
          const total = valor_estimado_carga(jornada.items);
          return (
            <article
              key={jornada.id}
              className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm md:p-6"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="flex items-center gap-3">
                  <Truck
                    size={28}
                    className="text-blue-600"
                  />
                  <div>
                    <h3 className="text-lg font-bold text-slate-800">
                      {camion?.nombre ?? "Camión no encontrado"}
                    </h3>
                    <p className="text-sm text-slate-500">
                      {jornada.chofer} · {jornada.zona}
                    </p>
                  </div>
                </div>
                <span
                  className={`rounded-full px-3 py-1 text-xs font-semibold ${
                    jornada.estado === "abierta"
                      ? "bg-green-100 text-green-700"
                      : jornada.estado === "preparacion"
                      ? "bg-amber-100 text-amber-800"
                      : "bg-slate-100 text-slate-600"
                  }`}
                >
                  {jornada.estado === "preparacion"
                    ? "En preparación"
                    : jornada.estado === "abierta"
                    ? "En reparto"
                    : "Cerrada"}
                </span>
              </div>
              <p className="mt-3 text-xs text-slate-500">
                Preparada:{" "}
                {new Date(
                  jornada.fechaCreacion
                ).toLocaleString("es-AR")}
              </p>
              <div className="mt-4 overflow-x-auto">
                <table className="w-full min-w-[360px] text-left text-sm">
                  <thead className="border-b text-slate-500">
                    <tr>
                      <th className="py-3">Producto</th>
                      <th className="py-3 text-right">
                        Cantidad
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {jornada.items.map((item) => (
                      <tr
                        key={item.productoId}
                        className="border-b border-slate-100"
                      >
                        <td className="py-3">
                          {item.nombreProducto}
                        </td>
                        <td className="py-3 text-right">
                          {cantidad_a_texto(item.unidadMedida, item.cantidad)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p className="text-xs text-slate-500">
                    Valor de referencia
                  </p>
                  <p className="text-xl font-bold text-slate-800">
                    {total === null ? "Sin valorizar" : moneda(total)}
                  </p>
                </div>
                {jornada.estado === "preparacion" && (
                  <button
                    type="button"
                    onClick={() => iniciarReparto(jornada)}
                    disabled={estadoOperacion.bloqueado}
                    className="min-h-12 rounded-lg bg-green-600 px-5 font-semibold text-white hover:bg-green-700"
                  >
                    Confirmar salida
                  </button>
                )}
                {jornada.estado === "abierta" && (
                  <span className="flex items-center gap-2 font-medium text-green-700">
                    <CheckCircle2 size={20} />
                    Reparto iniciado
                  </span>
                )}
              </div>
            </article>
          );
        })}
      </section>
      <p className="text-sm text-slate-500">
        Modo demostración: las cargas no descuentan
        inventario real. La disponibilidad para nuevas cargas
        se calcula con datos de este navegador.
      </p>
    </div>
  );
}
