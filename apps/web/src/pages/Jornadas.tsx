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
import {
  cantidad_unidad_desde_texto,
  es_cantidad_valida,
} from "../domain/cantidades";
import { subtotal_linea, sumar_importes } from "../domain/precios";
import {
  cantidad_a_texto,
  MENSAJE_PESO_NO_OPERABLE,
} from "../domain/productos";
import {
  type Jornada,
  type ItemCarga,
} from "../data/mockJornadas";
import type { RetornoDeposito } from "../data/mockRetornos";
import AvisoStorageOperativo from "../components/AvisoStorageOperativo";
import AvisoCatalogoDemo from "../components/AvisoCatalogoDemo";
import { estadoStorageOperativo } from "./estadoStorageOperativo";
const moneda = (valor: number) =>
  new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 2,
  }).format(valor);
// Sólo `unidad`: las cantidades `peso` se muestran con cantidad_a_texto.
const unidades = {
  unidad: "un.",
};
// Valor de referencia de un ítem de carga `unidad`. B1: la valorización de
// `peso` (D-R1) no está migrada; lanza y nunca se aproxima.
function valorItem(item: ItemCarga): number {
  if (item.unidadMedida !== "unidad") {
    throw new Error(MENSAJE_PESO_NO_OPERABLE);
  }
  return subtotal_linea({
    unidad_medida: item.unidadMedida,
    cantidad: item.cantidad,
    precio: item.precioReferencia,
  });
}

function calcularStockReservado(
  jornadas: Jornada[],
  retornos: RetornoDeposito[]
): Record<number, number> {
  const reservado: Record<number, number> = {};

  for (const jornada of jornadas) {
    for (const item of jornada.items) {
      reservado[item.productoId] =
        (reservado[item.productoId] ?? 0) + item.cantidad;
    }
  }

  for (const retorno of retornos) {
    const jornadaOrigen = jornadas.find(
      (j) => j.id === retorno.jornadaId
    );
    if (
      !jornadaOrigen ||
      jornadaOrigen.estado !== "cerrada" ||
      jornadaOrigen.camionId !== retorno.camionId
    ) {
      continue;
    }
    for (const item of retorno.items) {
      const cargado = jornadaOrigen.items.find(
        (p) => p.productoId === item.productoId
      );
      if (
        !cargado ||
        cargado.unidadMedida !== item.unidadMedida ||
        !Number.isFinite(item.cantidadAprobada) ||
        item.cantidadAprobada < 0 ||
        item.cantidadAprobada > item.cantidadContada
      ) {
        continue;
      }
      reservado[item.productoId] =
        (reservado[item.productoId] ?? 0) - item.cantidadAprobada;
    }
  }

  return reservado;
}

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
  // Texto del input entero de cada producto "unidad". Los productos "peso"
  // no tienen input en B1 (B2).
  const [cantidades, setCantidades] = useState<Record<number, string>>({});
  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");
  // Stock comprometido en las cargas, menos los retornos aprobados.
  // Las jornadas cerradas siguen reservando lo que no regresó.
  const stockReservado = useMemo(
    () => calcularStockReservado(jornadas, retornos),
    [jornadas, retornos]
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
  function disponibilidad(productoId: number) {
    const producto = productos.find((p) => p.id === productoId);
    if (!producto) return 0;
    return Math.max(
      0,
      producto.stock - (stockReservado[productoId] ?? 0)
    );
  }
  // Convierte el texto de la UX a la cantidad canónica (entero) para persistir.
  // B1: un producto "peso" nunca aporta cantidad (no operable hasta B2).
  const obtenerCantidadCanonica = useCallback(
    (productoId: number): number => {
      const valor = cantidades[productoId];
      if (!valor) return 0;
      const producto = productos.find((p) => p.id === productoId);
      if (!producto) return 0;
      if (producto.unidadMedida === "unidad") {
        // Una cantidad de unidad inválida no cuenta como cantidad: devuelve 0
        // y guardarPreparacion la reporta como error.
        return cantidad_unidad_desde_texto(valor) ?? 0;
      }
      return 0;
    },
    [cantidades, productos]
  );

  // Texto de unidad no vacío que no es un entero finito >= 0.
  const hayCantidadUnidadInvalida = useCallback(
    (productoId: number): boolean => {
      const valor = cantidades[productoId];
      const producto = productos.find((p) => p.id === productoId);
      return (
        producto?.unidadMedida === "unidad" &&
        valor !== undefined &&
        cantidad_unidad_desde_texto(valor) === null
      );
    },
    [cantidades, productos]
  );

  const hayCantidadPositiva = useCallback(
    (productoId: number): boolean => {
      return obtenerCantidadCanonica(productoId) > 0;
    },
    [obtenerCantidadCanonica]
  );

  const itemsSeleccionados = useMemo(() => {
    return productos
      .filter((producto) => hayCantidadPositiva(producto.id))
      .map((producto): ItemCarga => ({
        productoId: producto.id,
        nombreProducto: producto.nombre,
        unidadMedida: producto.unidadMedida,
        cantidad: obtenerCantidadCanonica(producto.id),
        precioReferencia: producto.precio,
      }));
  }, [productos, hayCantidadPositiva, obtenerCantidadCanonica]);
  const valorCarga = sumar_importes(itemsSeleccionados.map(valorItem));
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
    if (estadoOperacion.bloqueado) return;
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
    if (itemsSeleccionados.length === 0) {
      setError("Agregá al menos un producto a la carga.");
      return;
    }

    // M-3 (bloque E): el stock NO se comprueba aquí con el snapshot del
    // render. Las cantidades de la UX sí; el stock se valida dentro de la
    // frontera, con Jornadas y Retornos reídos en el momento de persistir.
    for (const producto of productos) {
      if (hayCantidadUnidadInvalida(producto.id)) {
        setError(`Cantidad inválida: ${producto.nombre}`);
        return;
      }
      const canonica = obtenerCantidadCanonica(producto.id);
      if (canonica === 0) continue;
      const cantidadValida = es_cantidad_valida(canonica);
      if (!cantidadValida) {
        setError(`Cantidad inválida: ${producto.nombre}`);
        return;
      }
    }

    // Validación defensiva de precios: no se persiste un ítem cuyo valor no
    // se pueda calcular con el dominio de precios.
    for (const item of itemsSeleccionados) {
      try {
        valorItem(item);
      } catch {
        setError(`Precio inválido: ${item.nombreProducto}`);
        return;
      }
    }

    // Validación de stock sobre lecturas frescas: la frontera relee Jornadas
    // y Retornos justo antes de persistir y pasa esos conjuntos a esta
    // función pura. El snapshot del render no participa en la persistencia.
    const validarStockConLecturas = (
      jornadasActuales: Jornada[],
      retornosActuales: RetornoDeposito[]
    ): string | null => {
      const reservadoActual = calcularStockReservado(
        jornadasActuales,
        retornosActuales
      );

      for (const producto of productos) {
        const canonica = obtenerCantidadCanonica(producto.id);
        if (canonica === 0) continue;
        const disponible = Math.max(
          0,
          producto.stock - (reservadoActual[producto.id] ?? 0)
        );
        if (canonica > disponible) {
          return `No hay stock suficiente de ${producto.nombre}.`;
        }
      }

      return null;
    };

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

    const errorPreparacion = crearPreparacion(
      jornada,
      validarStockConLecturas
    );

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
    if (!confirmarSalida(jornada.id)) {
      setError("No se pudo confirmar la salida.");
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
          <div className="space-y-3">
            {productos.map((producto) => {
              const disponible = disponibilidad(producto.id);
              if (producto.unidadMedida === "peso") {
                // B1: sin input; la carga por peso se habilita en B2.
                return (
                  <div
                    key={producto.id}
                    className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-slate-200 p-4"
                  >
                    <div className="flex min-w-0 items-center gap-3">
                      <Package
                        className="shrink-0 text-slate-400"
                        size={23}
                      />
                      <div>
                        <p className="font-medium text-slate-800">
                          {producto.nombre}
                        </p>
                        <p className="text-sm text-slate-500">
                          Disponible: {cantidad_a_texto(producto.unidadMedida, disponible)}
                        </p>
                      </div>
                    </div>
                    <p className="text-sm text-amber-700">
                      {MENSAJE_PESO_NO_OPERABLE}
                    </p>
                  </div>
                );
              }

              // UX para lácteos: solo entero
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
                        Disponible: {disponible} {unidades[producto.unidadMedida]}
                      </p>
                      <p className="text-xs text-slate-400">
                        {moneda(producto.precio)} por{" "}
                        {producto.unidadMedida}
                      </p>
                    </div>
                  </div>
                  <label className="flex items-center gap-2 text-sm">
                    <span>Cargar:</span>
                    <input
                      type="number"
                      min="0"
                      max={disponible}
                      step="1"
                      value={cantidades[producto.id] ?? ""}
                      onChange={(e) =>
                        setCantidades((actuales) => ({
                          ...actuales,
                          [producto.id]: e.target.value,
                        }))
                      }
                      className="min-h-12 w-24 rounded-lg border border-slate-300 p-3 text-right"
                      aria-label={`Cantidad de ${producto.nombre}`}
                    />
                    <span className="w-10 text-slate-500">
                      {unidades[producto.unidadMedida]}
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
              {moneda(valorCarga)}
            </p>
            <p className="mt-1 text-xs text-blue-700">
              Calculado con precios de venta de referencia.
            </p>
          </div>
          <div className="mt-6 flex flex-wrap gap-3">
            <button
              type="button"
              onClick={guardarPreparacion}
              disabled={estadoOperacion.bloqueado}
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
          // B1: sin valorización si la jornada tiene ítems `peso` (D-R1, B3).
          const total = jornada.items.every(
            (item) => item.unidadMedida === "unidad"
          )
            ? sumar_importes(jornada.items.map(valorItem))
            : null;
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
                    {total === null ? "—" : moneda(total)}
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
