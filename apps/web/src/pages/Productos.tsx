import { useMemo, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  Package,
  Pencil,
  Plus,
  Power,
  Search,
} from "lucide-react";

import { type UnidadMedida } from "../data/mockProductos";
import { useCatalogoProductos } from "../hooks/useCatalogoProductos";
import {
  STOCK_MINIMO_MAXIMO,
  type CategoriaProducto,
  type ProductoCatalogo,
} from "../lib/productos";
import { es_cantidad_valida, medias_a_texto } from "../domain/cantidades";
import {
  unidad_para_categoria,
  validar_combinacion_categoria_unidad,
} from "../domain/productos";
import { precio_media_pieza, validar_precio } from "../domain/precios";

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

// Stock mínimo en unidad mínima (Blueprint §7.1): unidades enteras o medias
// piezas.
function textoStockMinimo(producto: ProductoCatalogo): string {
  return producto.unidadMedida === "pieza"
    ? medias_a_texto(producto.stockMinimo)
    : `${producto.stockMinimo} un.`;
}

type FormularioProducto = {
  codigo: string;
  nombre: string;
  categoria: CategoriaProducto;
  unidadMedida: UnidadMedida;
  precio: string;
  stockMinimo: string;
};

function formularioVacio(): FormularioProducto {
  return {
    codigo: "",
    nombre: "",
    categoria: "Lácteos",
    unidadMedida: "unidad",
    precio: "",
    stockMinimo: "",
  };
}

type ValidacionFormulario =
  | { ok: true; precio: number; stockMinimo: number }
  | { ok: false; error: string };

// Validación previa al envío. La base vuelve a validar todo: es la autoridad.
function validarFormulario(formulario: FormularioProducto): ValidacionFormulario {
  if (formulario.nombre.trim() === "") {
    return { ok: false, error: "Ingresá el nombre del producto." };
  }

  const combinacion = validar_combinacion_categoria_unidad(
    formulario.categoria,
    formulario.unidadMedida
  );
  if (!combinacion.valido) {
    return { ok: false, error: combinacion.mensaje ?? "Combinación inválida." };
  }

  // ADR-003: como máximo 2 decimales; nunca se redondea ni se trunca.
  const precio = Number(formulario.precio.trim());
  if (formulario.precio.trim() === "") {
    return { ok: false, error: "Ingresá el precio." };
  }
  try {
    validar_precio(precio);
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "Precio inválido.",
    };
  }

  const stockMinimo = Number(formulario.stockMinimo.trim());
  if (
    formulario.stockMinimo.trim() === "" ||
    !es_cantidad_valida(stockMinimo) ||
    stockMinimo > STOCK_MINIMO_MAXIMO
  ) {
    return {
      ok: false,
      error: "El stock mínimo debe ser un número entero mayor o igual a 0.",
    };
  }

  return { ok: true, precio, stockMinimo };
}

export default function Productos() {
  const { catalogo, recargar, crear, actualizar, cambiarEstado } =
    useCatalogoProductos();
  const disponible = catalogo.estado === "listo";
  const productos = useMemo(
    () => (catalogo.estado === "listo" ? catalogo.productos : []),
    [catalogo]
  );

  const [busqueda, setBusqueda] = useState("");
  const [mostrarFormulario, setMostrarFormulario] = useState(false);
  const [productoEditando, setProductoEditando] =
    useState<ProductoCatalogo | null>(null);
  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");
  // Evita envíos dobles mientras una escritura está en curso.
  const [enviando, setEnviando] = useState(false);

  const [formulario, setFormulario] = useState<FormularioProducto>(
    formularioVacio
  );

  // Filtrar productos sin modificar el catálogo.
  const productosFiltrados = useMemo(() => {
    const termino = busqueda.trim().toLocaleLowerCase("es-AR");

    return productos.filter((producto) =>
      `${producto.codigo ?? ""} ${producto.nombre} ${producto.categoria}`
        .toLocaleLowerCase("es-AR")
        .includes(termino)
    );
  }, [productos, busqueda]);

  // Limpiar el formulario y cerrar el panel.
  function cancelarFormulario() {
    setMostrarFormulario(false);
    setProductoEditando(null);
    setFormulario(formularioVacio());
  }

  // Abrir un formulario vacío.
  function abrirNuevoProducto() {
    if (!disponible) return;
    cancelarFormulario();
    setMensaje("");
    setError("");
    setMostrarFormulario(true);
  }

  // Cargar los datos del producto para editarlo.
  function editarProducto(producto: ProductoCatalogo) {
    setProductoEditando(producto);

    setFormulario({
      codigo: producto.codigo ?? "",
      nombre: producto.nombre,
      categoria: producto.categoria,
      unidadMedida: producto.unidadMedida,
      precio: String(producto.precio),
      stockMinimo: String(producto.stockMinimo),
    });

    setMensaje("");
    setError("");
    setMostrarFormulario(true);

    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  // Guardar un producto nuevo o actualizar uno existente.
  async function guardarProducto(evento: React.SubmitEvent<HTMLFormElement>) {
    evento.preventDefault();
    if (!disponible || enviando) return;

    setMensaje("");
    setError("");

    const validacion = validarFormulario(formulario);
    if (!validacion.ok) {
      setError(validacion.error);
      return;
    }

    setEnviando(true);

    const resultado =
      productoEditando !== null
        ? // Categoría y unidad no se envían: no se editan (DE-6).
          await actualizar(productoEditando.id, {
            codigo: formulario.codigo,
            nombre: formulario.nombre,
            precio: validacion.precio,
            stockMinimo: validacion.stockMinimo,
          })
        : await crear({
            codigo: formulario.codigo,
            nombre: formulario.nombre,
            categoria: formulario.categoria,
            unidadMedida: formulario.unidadMedida,
            precio: validacion.precio,
            stockMinimo: validacion.stockMinimo,
          });

    setEnviando(false);

    if (!resultado.ok) {
      setError(resultado.error);
      return;
    }

    setMensaje(
      productoEditando !== null
        ? "Producto actualizado correctamente."
        : "Producto agregado correctamente."
    );
    cancelarFormulario();
  }

  // Baja lógica o reactivación.
  async function alternarEstado(producto: ProductoCatalogo) {
    if (!disponible || enviando) return;

    setMensaje("");
    setError("");
    setEnviando(true);

    const resultado = await cambiarEstado(producto.id, !producto.activo);

    setEnviando(false);

    if (!resultado.ok) {
      setError(resultado.error);
      return;
    }

    setMensaje(
      producto.activo
        ? `${producto.nombre} quedó dado de baja.`
        : `${producto.nombre} quedó reactivado.`
    );
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
          disabled={!disponible || enviando}
          className="flex min-h-11 items-center gap-2 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700 disabled:opacity-60"
        >
          <Plus size={20} />
          Nuevo producto
        </button>
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
            {/* Código */}
            <label className="space-y-1 text-sm font-medium">
              <span>Código (opcional)</span>

              <input
                value={formulario.codigo}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    codigo: e.target.value,
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
                placeholder="Ej: FIA-001"
              />
            </label>

            {/* Nombre */}
            <label className="space-y-1 text-sm font-medium">
              <span>Nombre del producto</span>

              <input
                required
                value={formulario.nombre}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
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
                value={formulario.categoria}
                disabled={productoEditando !== null}
                onChange={(e) => {
                  const categoria = e.target.value as CategoriaProducto;

                  setFormulario({
                    ...formulario,
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
                  La categoría no puede cambiarse después del alta:
                  alteraría la interpretación de las cantidades.
                </p>
              )}
            </label>

            {/* Unidad de medida: derivada de la categoría */}
            <label className="space-y-1 text-sm font-medium">
              <span>Unidad de medida</span>

              <select
                value={formulario.unidadMedida}
                onChange={() => {
                  // La unidad siempre es la derivada de la categoría;
                  // no hay otra opción válida que elegir.
                }}
                className="w-full rounded-lg border border-slate-300 p-3 bg-slate-100 text-slate-500"
              >
                <option value={formulario.unidadMedida}>
                  {formulario.unidadMedida === "unidad"
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
                {formulario.unidadMedida === "pieza"
                  ? "Precio de pieza completa ($)"
                  : "Precio de venta ($)"}
              </span>

              <input
                required
                type="number"
                min="0"
                step="0.01"
                value={formulario.precio}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    precio: e.target.value,
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
              />
            </label>

            {/* Precio de media pieza: derivado, solo lectura para fiambres */}
            {formulario.unidadMedida === "pieza" && (
              <label className="space-y-1 text-sm font-medium">
                <span>Precio de media pieza (derivado, $)</span>

                <input
                  type="number"
                  min="0"
                  step="1"
                  value={vistaPreviaMedia(formulario.precio)}
                  readOnly
                  className="w-full rounded-lg border border-slate-300 p-3 bg-slate-50 text-slate-700"
                />

                <p className="text-xs font-normal text-slate-500">
                  Se deriva automáticamente: mitad del precio de pieza,
                  redondeado al peso entero (.50 hacia arriba).
                </p>
              </label>
            )}

            {/* Stock mínimo, en unidad mínima */}
            <label className="space-y-1 text-sm font-medium">
              <span>
                {formulario.unidadMedida === "pieza"
                  ? "Stock mínimo (en medias piezas)"
                  : "Stock mínimo (unidades)"}
              </span>

              <input
                required
                type="number"
                min="0"
                step="1"
                value={formulario.stockMinimo}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
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
              disabled={!disponible || enviando}
              className="min-h-11 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700 disabled:opacity-60"
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
        <table className="w-full min-w-[860px] text-left">
          <thead className="bg-slate-50 text-sm text-slate-500">
            <tr>
              <th className="px-5 py-4">Código</th>
              <th className="px-5 py-4">Producto</th>
              <th className="px-5 py-4">Categoría</th>
              <th className="px-5 py-4">Precio</th>
              <th className="px-5 py-4">Stock mínimo</th>
              <th className="px-5 py-4">Estado</th>
              <th className="px-5 py-4">Acciones</th>
            </tr>
          </thead>

          <tbody className="divide-y divide-slate-100">
            {productosFiltrados.map((producto) => (
              <tr
                key={producto.id}
                className="hover:bg-slate-50"
              >
                {/* Código */}
                <td className="px-5 py-4 text-slate-500">
                  {producto.codigo ?? "—"}
                </td>

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

                {/* Stock mínimo */}
                <td className="px-5 py-4">
                  {textoStockMinimo(producto)}
                </td>

                {/* Estado */}
                <td className="px-5 py-4">
                  <span
                    className={`rounded-full px-3 py-1 text-sm font-medium ${
                      producto.activo
                        ? "bg-green-100 text-green-700"
                        : "bg-slate-200 text-slate-600"
                    }`}
                  >
                    {producto.activo ? "Activo" : "Inactivo"}
                  </span>
                </td>

                {/* Acciones */}
                <td className="px-5 py-4">
                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      onClick={() => editarProducto(producto)}
                      disabled={enviando}
                      aria-label={`Editar ${producto.nombre}`}
                      className="flex min-h-11 items-center gap-2 rounded-lg border border-slate-200 px-3 text-blue-600 hover:bg-blue-50 disabled:opacity-60"
                    >
                      <Pencil size={16} />
                      Editar
                    </button>

                    <button
                      type="button"
                      onClick={() => void alternarEstado(producto)}
                      disabled={enviando}
                      aria-label={`${
                        producto.activo ? "Dar de baja" : "Reactivar"
                      } ${producto.nombre}`}
                      className="flex min-h-11 items-center gap-2 rounded-lg border border-slate-200 px-3 text-slate-700 hover:bg-slate-100 disabled:opacity-60"
                    >
                      <Power size={16} />
                      {producto.activo ? "Dar de baja" : "Reactivar"}
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {catalogo.estado === "cargando" && (
          <p role="status" className="p-8 text-center text-slate-500">
            Cargando productos…
          </p>
        )}

        {disponible && productosFiltrados.length === 0 && (
          <p className="p-8 text-center text-slate-500">
            No se encontraron productos.
          </p>
        )}
      </div>

      {/* Alcance del catálogo real */}
      <p className="text-sm text-slate-500">
        Catálogo guardado en la base de datos. El stock no se carga ni se
        edita aquí: se calculará a partir de los movimientos de mercadería.
        Jornadas, movimientos y el resto de las pantallas operativas todavía
        usan el catálogo de demostración de este navegador.
      </p>
    </div>
  );
}
