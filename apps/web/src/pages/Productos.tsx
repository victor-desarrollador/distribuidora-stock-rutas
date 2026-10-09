import { useMemo, useState } from "react";
import { Package, Plus, Search } from "lucide-react";

import {
  productosIniciales,
  type Producto,
  type UnidadMedida,
} from "../data/mockProductos";

const formatoMoneda = (valor: number) =>
  new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 2,
  }).format(valor);

const unidades: Record<UnidadMedida, string> = {
  unidad: "un.",
  pieza: "pzas.",
  kg: "kg",
};

export default function Productos() {
  // Estado local: los datos se reinician al recargar la página.
  const [productos, setProductos] =
    useState<Producto[]>(productosIniciales);

  const [busqueda, setBusqueda] = useState("");
  const [mostrarFormulario, setMostrarFormulario] = useState(false);

  const [nuevoProducto, setNuevoProducto] = useState({
    nombre: "",
    categoria: "Lácteos" as Producto["categoria"],
    unidadMedida: "unidad" as UnidadMedida,
    precio: "",
    stock: "",
    stockMinimo: "",
  });

  // Filtramos sin modificar el catálogo original.
  const productosFiltrados = useMemo(() => {
    const termino = busqueda.trim().toLocaleLowerCase("es-AR");

    return productos.filter((producto) =>
      `${producto.nombre} ${producto.categoria}`
        .toLocaleLowerCase("es-AR")
        .includes(termino)
    );
  }, [productos, busqueda]);

  function agregarProducto(evento: React.SubmitEvent<HTMLFormElement>) {
    evento.preventDefault();

    const precio = Number(nuevoProducto.precio);
    const stock = Number(nuevoProducto.stock);
    const stockMinimo = Number(nuevoProducto.stockMinimo);

    if (
      !nuevoProducto.nombre.trim() ||
      !Number.isFinite(precio) ||
      !Number.isFinite(stock) ||
      !Number.isFinite(stockMinimo) ||
      precio < 0 ||
      stock < 0 ||
      stockMinimo < 0 ||
      (nuevoProducto.unidadMedida !== "kg" &&
        (!Number.isInteger(stock) || !Number.isInteger(stockMinimo)))
    ) {
      alert("Revisá los datos del producto.");
      return;
    }

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
    setMostrarFormulario(false);

    setNuevoProducto({
      nombre: "",
      categoria: "Lácteos",
      unidadMedida: "unidad",
      precio: "",
      stock: "",
      stockMinimo: "",
    });
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
          onClick={() => setMostrarFormulario((valor) => !valor)}
          className="flex min-h-11 items-center gap-2 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700"
        >
          <Plus size={20} />
          Nuevo producto
        </button>
      </div>

      {/* Formulario de alta */}
      {mostrarFormulario && (
        <form
          onSubmit={agregarProducto}
          className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
        >
          <h2 className="mb-5 text-lg font-semibold">
            Agregar producto
          </h2>

          <div className="grid gap-4 md:grid-cols-2">
            <label className="space-y-1 text-sm font-medium">
              <span>Nombre</span>
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

            <label className="space-y-1 text-sm font-medium">
              <span>Categoría</span>
              <select
                value={nuevoProducto.categoria}
                onChange={(e) =>
                  setNuevoProducto({
                    ...nuevoProducto,
                    categoria: e.target.value as Producto["categoria"],
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
              >
                <option>Lácteos</option>
                <option>Fiambres</option>
              </select>
            </label>

            <label className="space-y-1 text-sm font-medium">
              <span>Unidad de medida</span>
              <select
                value={nuevoProducto.unidadMedida}
                onChange={(e) =>
                  setNuevoProducto({
                    ...nuevoProducto,
                    unidadMedida: e.target.value as UnidadMedida,
                  })
                }
                className="w-full rounded-lg border border-slate-300 p-3"
              >
                <option value="unidad">Unidad</option>
                <option value="pieza">Pieza</option>
                <option value="kg">Kilogramo</option>
              </select>
            </label>

            <label className="space-y-1 text-sm font-medium">
              <span>Precio ($)</span>
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

            <label className="space-y-1 text-sm font-medium">
              <span>Stock inicial</span>
              <input
                required
                type="number"
                min="0"
                step={nuevoProducto.unidadMedida === "kg" ? "0.001" : "1"}
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

            <label className="space-y-1 text-sm font-medium">
              <span>Stock mínimo</span>
              <input
                required
                type="number"
                min="0"
                step={nuevoProducto.unidadMedida === "kg" ? "0.001" : "1"}
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

          <div className="mt-5 flex flex-wrap gap-3">
            <button
              type="submit"
              className="min-h-11 rounded-lg bg-blue-600 px-5 py-3 font-medium text-white"
            >
              Guardar producto
            </button>

            <button
              type="button"
              onClick={() => setMostrarFormulario(false)}
              className="min-h-11 rounded-lg border border-slate-300 px-5 py-3"
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
        <table className="w-full min-w-[650px] text-left">
          <thead className="bg-slate-50 text-sm text-slate-500">
            <tr>
              <th className="px-5 py-4">Producto</th>
              <th className="px-5 py-4">Categoría</th>
              <th className="px-5 py-4">Stock</th>
              <th className="px-5 py-4">Precio</th>
              <th className="px-5 py-4">Estado</th>
            </tr>
          </thead>

          <tbody className="divide-y divide-slate-100">
            {productosFiltrados.map((producto) => {
              const stockBajo =
                producto.stock <= producto.stockMinimo;

              return (
                <tr key={producto.id} className="hover:bg-slate-50">
                  <td className="px-5 py-4">
                    <div className="flex items-center gap-3">
                      <Package size={20} className="text-blue-600" />
                      <span className="font-medium text-slate-800">
                        {producto.nombre}
                      </span>
                    </div>
                  </td>

                  <td className="px-5 py-4">
                    {producto.categoria}
                  </td>

                  <td className="px-5 py-4">
                    {producto.stock} {unidades[producto.unidadMedida]}
                  </td>

                  <td className="px-5 py-4">
                    {formatoMoneda(producto.precio)}
                  </td>

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
      </div>

      <p className="text-sm text-slate-500">
        Prototipo: los cambios se guardan solo mientras la página
        permanece abierta. El stock mostrado es ficticio.
      </p>
    </div>
  );
}