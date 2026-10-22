import { useMemo, useState } from "react";
import { Package, Plus, Search, Pencil, CheckCircle2 } from "lucide-react";

import { type Producto, type UnidadMedida } from "../data/mockProductos";
import { useProductos } from "../hooks/useProductos";
import {
  stock_producto_valido,
  unidad_para_categoria,
  validar_combinacion_categoria_unidad,
} from "../domain/productos";
import { precio_media_pieza, validar_precio } from "../domain/precios";
import AvisoStorageOperativo from "../components/AvisoStorageOperativo";
import { estadoStorageOperativo } from "./estadoStorageOperativo";

// Formato de moneda argentina.
const formatoMoneda = (valor: number) =>
  new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 2,
  }).format(valor);

// Vista previa de la media derivada mientras se tipea: un precio todavía
// inválido (p. ej. 10.001) no debe romper el render; se muestra vacío.
function vistaPreviaMedia(precioTexto: string): string {
  try {
    return String(precio_media_pieza(Number(precioTexto) || 0));
  } catch {
    return "";
  }
}

// Abreviaciones de unidades.
const unidades: Record<UnidadMedida, string> = {
  unidad: "un.",
  pieza: "pzas.",
};

type FormularioProducto = {
  nombre: string;
  categoria: Producto["categoria"];
  unidadMedida: UnidadMedida;
  precio: string;
  stock: string;
  stockMinimo: string;
};

function formularioVacio(): FormularioProducto {
  return {
    nombre: "",
    categoria: "Lácteos",
    unidadMedida: "unidad",
    precio: "",
    stock: "",
    stockMinimo: "",
  };
}

export default function Productos() {
  // El hook se encarga de guardar los productos localmente.
  const { productos, setProductos, estadoLectura } = useProductos();
  const estadoOperacion = estadoStorageOperativo({ productos: estadoLectura });

  const [busqueda, setBusqueda] = useState("");
  const [mostrarFormulario, setMostrarFormulario] = useState(false);
  const [productoEditando, setProductoEditando] = useState<number | null>(null);
  const [mensaje, setMensaje] = useState("");

  const [nuevoProducto, setNuevoProducto] = useState<FormularioProducto>(
    formularioVacio
  );

  // Filtrar productos sin modificar el catálogo.
  const productosFiltrados = useMemo(() => {
    const termino = busqueda.trim().toLocaleLowerCase("es-AR");

    return productos.filter((producto) =>
      `${producto.nombre} ${producto.categoria}`
        .toLocaleLowerCase("es-AR")
        .includes(termino)
    );
  }, [productos, busqueda]);

  // Limpiar el formulario y cerrar el panel.
  function cancelarFormulario() {
    setMostrarFormulario(false);
    setProductoEditando(null);
    setNuevoProducto(formularioVacio());
  }

  // Abrir un formulario vacío.
  function abrirNuevoProducto() {
    if (estadoOperacion.bloqueado) return;
    cancelarFormulario();
    setMensaje("");
    setMostrarFormulario(true);
  }

  // Cargar los datos del producto para editarlo.
  function editarProducto(producto: Producto) {
    setProductoEditando(producto.id);

    setNuevoProducto({
      nombre: producto.nombre,
      categoria: producto.categoria,
      unidadMedida: producto.unidadMedida,
      precio: String(producto.precio),
      stock: String(producto.stock),
      stockMinimo: String(producto.stockMinimo),
    });

    setMensaje("");
    setMostrarFormulario(true);

    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  // Guardar un producto nuevo o actualizar uno existente.
  function guardarProducto(evento: React.SubmitEvent<HTMLFormElement>) {
    evento.preventDefault();
    if (estadoOperacion.bloqueado) return;

    const precio = Number(nuevoProducto.precio);
    const stock = Number(nuevoProducto.stock);
    const stockMinimo = Number(nuevoProducto.stockMinimo);

    const camposCompletos =
      nuevoProducto.nombre.trim() !== "" &&
      nuevoProducto.precio.trim() !== "" &&
      nuevoProducto.stock.trim() !== "" &&
      nuevoProducto.stockMinimo.trim() !== "";

    const numerosValidos =
      Number.isFinite(stock) &&
      Number.isFinite(stockMinimo) &&
      stock >= 0 &&
      stockMinimo >= 0;

    // Para piezas y unidades solamente aceptamos enteros seguros (dominio).
    const cantidadesValidas = stock_producto_valido(stock, stockMinimo);

    // Validación defensiva: la combinación categoría ↔ unidad debe ser
    // canónica (Lácteos -> unidad; Fiambres -> pieza) aunque la UI ya
    // derive la unidad de la categoría. Si llega algo inválido, falla
    // cerrado y no se persiste.
    const combinacion = validar_combinacion_categoria_unidad(
      nuevoProducto.categoria,
      nuevoProducto.unidadMedida
    );

    // Validación de dominio de precios (ADR-003): máximo 2 decimales, sin
    // redondear; precio de media se deriva, NO es configurable.
    let errorPrecios: string | null = null;
    try {
      validar_precio(precio);
    } catch (error) {
      errorPrecios = error instanceof Error ? error.message : "Precio inválido.";
    }

    if (errorPrecios !== null) {
      alert(errorPrecios);
      return;
    }

    if (
      !camposCompletos ||
      !numerosValidos ||
      !cantidadesValidas ||
      !combinacion.valido
    ) {
      alert(combinacion.valido
        ? "Revisá los datos del producto."
        : combinacion.mensaje);
      return;
    }

    if (productoEditando !== null) {
      // Editar información comercial sin alterar el stock ni la
      // interpretación de las cantidades existentes: categoría y
      // unidadMedida se preservan tal como están.
      setProductos((actuales) =>
        actuales.map((producto) =>
          producto.id === productoEditando
            ? {
                ...producto,
                nombre: nuevoProducto.nombre.trim(),
                precio,
                stockMinimo,
              }
            : producto
        )
      );

      setMensaje("Producto actualizado correctamente.");
    } else {
      // Crear producto de demostración con stock inicial.
      const producto: Producto = {
        id: Math.max(0, ...productos.map((p) => p.id)) + 1,
        nombre: nuevoProducto.nombre.trim(),
        categoria: nuevoProducto.categoria,
        unidadMedida: nuevoProducto.unidadMedida,
        precio,
        stock,
        stockMinimo,
      };

      setProductos((actuales) => [...actuales, producto]);

      setMensaje("Producto agregado correctamente.");
    }

    cancelarFormulario();
  }

  return (
    <div className="space-y-6">
      {/* Encabezado */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-slate-800">
            Productos
          </h1>

          <p className="mt-1 text-slate-500">
            Catálogo de lácteos y fiambres
          </p>
        </div>

        <button
          type="button"
          onClick={abrirNuevoProducto}
          disabled={estadoOperacion.bloqueado}
          className="flex min-h-11 items-center gap-2 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700"
        >
          <Plus size={20} />
          Nuevo producto
        </button>
      </div>

      <AvisoStorageOperativo avisos={estadoOperacion.avisos} />

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

      {/* Formulario para agregar o editar */}
      {mostrarFormulario && (
        <form
          onSubmit={guardarProducto}
          className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
        >
          <h2 className="mb-5 text-lg font-semibold text-slate-800">
            {productoEditando !== null
              ? "Editar producto"
              : "Agregar producto"}
          </h2>

          <div className="grid gap-4 md:grid-cols-2">
            {/* Nombre */}
            <label className="space-y-1 text-sm font-medium">
              <span>Nombre del producto</span>

              <input
                required
                value={nuevoProducto.nombre}
                onChange={(e) =>
                  setNuevoProducto({
                    ...nuevoProducto,
                    nombre: e.target.value,
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
                placeholder="Ej: Jamón cocido"
              />
            </label>

            {/* Categoría */}
            <label className="space-y-1 text-sm font-medium">
              <span>Categoría</span>

              <select
                value={nuevoProducto.categoria}
                disabled={productoEditando !== null}
                onChange={(e) => {
                  const categoria =
                    e.target.value as Producto["categoria"];

                  setNuevoProducto({
                    ...nuevoProducto,
                    categoria,
                    // La unidad se deriva de la categoría: Lácteos ->
                    // unidad; Fiambres -> pieza. Nunca queda un estado
                    // intermedio inválido.
                    unidadMedida: unidad_para_categoria(categoria),
                  });
                }}
                className="w-full rounded-lg border border-slate-300 p-3 disabled:bg-slate-100 disabled:text-slate-500"
              >
                <option value="Lácteos">Lácteos</option>
                <option value="Fiambres">Fiambres</option>
              </select>

              {productoEditando !== null && (
                <p className="text-xs font-normal text-slate-500">
                  La categoría no puede cambiarse durante la edición:
                  alteraría la interpretación de las cantidades
                  existentes.
                </p>
              )}
            </label>

            {/* Unidad de medida: derivada de la categoría */}
            <label className="space-y-1 text-sm font-medium">
              <span>Unidad de medida</span>

              <select
                value={nuevoProducto.unidadMedida}
                onChange={() => {
                  // La unidad siempre es la derivada de la categoría;
                  // no hay otra opción válida que elegir.
                }}
                className="w-full rounded-lg border border-slate-300 p-3 bg-slate-100 text-slate-500"
              >
                <option value={nuevoProducto.unidadMedida}>
                  {nuevoProducto.unidadMedida === "unidad"
                    ? "Unidad"
                    : "Pieza"}
                </option>
              </select>

              <p className="text-xs font-normal text-slate-500">
                La unidad se determina por la categoría: Lácteos se
                controlan por unidad entera y fiambres por pieza. No
                se elige manualmente.
              </p>
            </label>

            {/* Precio */}
            <label className="space-y-1 text-sm font-medium">
              <span>
                {nuevoProducto.unidadMedida === "pieza"
                  ? "Precio de pieza completa ($)"
                  : "Precio de venta ($)"}
              </span>

              <input
                required
                type="number"
                min="0"
                step="0.01"
                value={nuevoProducto.precio}
                onChange={(e) =>
                  setNuevoProducto({
                    ...nuevoProducto,
                    precio: e.target.value,
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            {/* Precio de media pieza: derivado, solo lectura para fiambres */}
            {nuevoProducto.unidadMedida === "pieza" && (
              <label className="space-y-1 text-sm font-medium">
                <span>Precio de media pieza (derivado, $)</span>

                <input
                  type="number"
                  min="0"
                  step="1"
                  value={vistaPreviaMedia(nuevoProducto.precio)}
                  readOnly
                  className="w-full rounded-lg border border-slate-300 p-3 bg-slate-50 text-slate-700"
                />

                <p className="text-xs font-normal text-slate-500">
                  Se deriva automáticamente: mitad del precio de pieza,
                  redondeado al peso entero (.50 hacia arriba).
                </p>
              </label>
            )}

            {/* Stock inicial: solamente para productos nuevos */}
            {productoEditando === null && (
              <label className="space-y-1 text-sm font-medium">
                <span>Stock inicial</span>

                <input
                  required
                  type="number"
                  min="0"
                  step="1"
                  value={nuevoProducto.stock}
                  onChange={(e) =>
                    setNuevoProducto({
                      ...nuevoProducto,
                      stock: e.target.value,
                    })
                  }
                  className="w-full rounded-lg border border-slate-300 p-3"
                />
              </label>
            )}

            {/* Stock mínimo */}
            <label className="space-y-1 text-sm font-medium">
              <span>Stock mínimo</span>

              <input
                required
                type="number"
                min="0"
                step="1"
                value={nuevoProducto.stockMinimo}
                onChange={(e) =>
                  setNuevoProducto({
                    ...nuevoProducto,
                    stockMinimo: e.target.value,
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>
          </div>

          {/* Acciones del formulario */}
          <div className="mt-6 flex flex-wrap gap-3">
            <button
              type="submit"
              disabled={estadoOperacion.bloqueado}
              className="min-h-11 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700"
            >
              {productoEditando !== null
                ? "Guardar cambios"
                : "Guardar producto"}
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
          placeholder="Buscar productos..."
          aria-label="Buscar productos"
          className="w-full outline-none"
        />
      </div>

      {/* Tabla de productos */}
      <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-sm">
        <table className="w-full min-w-[760px] text-left">
          <thead className="bg-slate-50 text-sm text-slate-500">
            <tr>
              <th className="px-5 py-4">Producto</th>
              <th className="px-5 py-4">Categoría</th>
              <th className="px-5 py-4">Stock</th>
              <th className="px-5 py-4">Precio</th>
              <th className="px-5 py-4">Estado</th>
              <th className="px-5 py-4">Acciones</th>
            </tr>
          </thead>

          <tbody className="divide-y divide-slate-100">
            {productosFiltrados.map((producto) => {
              const stockBajo =
                producto.stock <= producto.stockMinimo;

              return (
                <tr
                  key={producto.id}
                  className="hover:bg-slate-50"
                >
                  {/* Nombre */}
                  <td className="px-5 py-4">
                    <div className="flex items-center gap-3">
                      <Package
                        size={20}
                        className="text-blue-600"
                      />

                      <span className="font-medium text-slate-800">
                        {producto.nombre}
                      </span>
                    </div>
                  </td>

                  {/* Categoría */}
                  <td className="px-5 py-4">
                    {producto.categoria}
                  </td>

                  {/* Stock */}
                  <td className="px-5 py-4">
                    {producto.stock}{" "}
                    {unidades[producto.unidadMedida]}
                  </td>

                  {/* Precio */}
                  <td className="px-5 py-4">
                    {producto.unidadMedida === "pieza" ? (
                      <>
                        {formatoMoneda(producto.precio)} pieza
                        <br />
                        {formatoMoneda(precio_media_pieza(producto.precio))} media
                      </>
                    ) : (
                      formatoMoneda(producto.precio)
                    )}
                  </td>

                  {/* Estado */}
                  <td className="px-5 py-4">
                    <span
                      className={`rounded-full px-3 py-1 text-sm font-medium ${
                        stockBajo
                          ? "bg-amber-100 text-amber-800"
                          : "bg-green-100 text-green-700"
                      }`}
                    >
                      {stockBajo ? "Stock bajo" : "Disponible"}
                    </span>
                  </td>

                  {/* Botón de editar */}
                  <td className="px-5 py-4">
                    <button
                      type="button"
                      onClick={() => editarProducto(producto)}
                      aria-label={`Editar ${producto.nombre}`}
                      className="flex min-h-11 items-center gap-2 rounded-lg border border-slate-200 px-3 text-blue-600 hover:bg-blue-50"
                    >
                      <Pencil size={16} />
                      Editar
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>

        {productosFiltrados.length === 0 && (
          <p className="p-8 text-center text-slate-500">
            No se encontraron productos.
          </p>
        )}

      {/* Advertencia de prototipo */}
      <p className="text-sm text-slate-500">
        Versión de demostración: los productos se guardan
        únicamente en este navegador. El stock es ficticio
        y todavía no está conectado con PostgreSQL.
      </p>
    </div>
  </div>
  );
}
