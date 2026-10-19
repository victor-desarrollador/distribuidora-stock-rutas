
import { useMemo, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  PackageX,
  RotateCcw,
  RefreshCw,
} from "lucide-react";

import { useJornadas } from "../hooks/useJornadas";
import { useCamiones } from "../hooks/useCamiones";
import { useClientes } from "../hooks/useClientes";
import { useProductos } from "../hooks/useProductos";
import { useVentas } from "../hooks/useVentas";
import { useMovimientos} from "../hooks/useMovimientos";
import {
  type TipoMovimiento,
  type MovimientoReparto,
  type ProductoMovimiento,
  salidasPorMovimiento,
} from "../data/mockMovimientos";

// Eliminar ", type," de la importación anterior:
// import { useMovimientos } from "../hooks/useMovimientos";

type DatosFormulario = {
  tipo: TipoMovimiento;
  jornadaId: string;
  clienteId: string;
  productoId: string;
  cantidad: string;
  entregadoId: string;
  cantidadEntregada: string;
  motivo: string;
};

const inicial: DatosFormulario = {
  tipo: "merma",
  jornadaId: "",
  clienteId: "",
  productoId: "",
  cantidad: "",
  entregadoId: "",
  cantidadEntregada: "",
  motivo: "",
};

const etiquetas = {
  merma: "Merma",
  devolucion: "Devolución",
  cambio: "Cambio",
};

const unidades = {
  unidad: "un.",
  pieza: "pzas.",
};

export default function Movimientos() {
  const { jornadas } = useJornadas();
  const { camiones } = useCamiones();
  const { clientes } = useClientes();
  const { productos } = useProductos();
  const { ventas } = useVentas();

  const { movimientos, registrarMovimiento } =
    useMovimientos();

  const [formulario, setFormulario] =
    useState<DatosFormulario>(inicial);

  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");

  const jornadasAbiertas = useMemo(
    () => jornadas.filter((j) => j.estado === "abierta"),
    [jornadas]
  );

  // Referencia estable: evita invalidar en cada render los
  // useMemo que dependen de `jornada`.
  const jornada = useMemo(
    () => jornadasAbiertas.find((j) => j.id === formulario.jornadaId),
    [jornadasAbiertas, formulario.jornadaId]
  );

  const cliente = clientes.find(
    (c) => c.id === Number(formulario.clienteId) && c.activo
  );

  const productoDevuelto = productos.find(
    (p) => p.id === Number(formulario.productoId)
  );

  const productoEntregado = productos.find(
    (p) => p.id === Number(formulario.entregadoId)
  );

  // Devoluciones y cambios solo usan clientes activos.
  const requiereCliente = formulario.tipo !== "merma";

  const movimientosJornada = useMemo(
    () =>
      movimientos.filter(
        (m) => m.jornadaId === formulario.jornadaId
      ),
    [movimientos, formulario.jornadaId]
  );

  // Cantidades que dejaron de estar disponibles.
  const salidas = useMemo(() => {
    const resultado: Record<number, number> = {};

    for (const venta of ventas) {
      if (venta.jornadaId !== formulario.jornadaId) continue;

      for (const item of venta.items) {
        resultado[item.productoId] =
          (resultado[item.productoId] ?? 0) +
          item.cantidad;
      }
    }

    for (const movimiento of movimientosJornada) {
      for (const item of salidasPorMovimiento(movimiento)) {
        resultado[item.productoId] =
          (resultado[item.productoId] ?? 0) +
          item.cantidad;
      }
    }

    return resultado;
  }, [ventas, movimientosJornada, formulario.jornadaId]);

  const disponibles = useMemo(() => {
    const resultado: Record<number, number> = {};

    for (const item of jornada?.items ?? []) {
      resultado[item.productoId] = Math.max(
        0,
        item.cantidad - (salidas[item.productoId] ?? 0)
      );
    }

    return resultado;
  }, [jornada, salidas]);

  function seleccionarTipo(tipo: TipoMovimiento) {
    setFormulario((actual) => ({
      ...inicial,
      jornadaId: actual.jornadaId,
      tipo,
    }));
    setError("");
    setMensaje("");
  }

  function cantidadValida(texto: string) {
    if (!texto.trim()) return false;

    const cantidad = Number(texto);

    return (
      Number.isFinite(cantidad) &&
      cantidad > 0 &&
      Number.isInteger(cantidad)
    );
  }

  function guardarMovimiento() {
    setMensaje("");
    setError("");

    if (!jornada) {
      setError("Seleccioná una jornada abierta.");
      return;
    }

    if (requiereCliente && !cliente) {
      setError("Seleccioná un cliente activo.");
      return;
    }

    if (!productoDevuelto) {
      setError("Seleccioná el producto.");
      return;
    }

    if (!formulario.motivo.trim()) {
      setError("Ingresá el motivo del movimiento.");
      return;
    }

    if (
      !cantidadValida(formulario.cantidad)
    ) {
      setError("La cantidad del producto no es válida.");
      return;
    }

    if (
      formulario.tipo === "cambio" &&
      (!productoEntregado ||
        !cantidadValida(formulario.cantidadEntregada))
    ) {
      setError("Completá el producto de reemplazo y su cantidad.");
      return;
    }

    const cantidad = Number(formulario.cantidad);

    const crearItem = (
      producto: typeof productoDevuelto,
      cantidad: number
    ): ProductoMovimiento => {
      if (!producto) throw new Error("Producto no encontrado");

      return {
        productoId: producto.id,
        nombreProducto: producto.nombre,
        unidadMedida: producto.unidadMedida,
        cantidad,
      };
    };

    const base = {
      id: crypto.randomUUID(),
      jornadaId: jornada.id,
      camionId: jornada.camionId,
      fecha: new Date().toISOString(),
      motivo: formulario.motivo.trim(),
    };

    let movimiento: MovimientoReparto;

    if (formulario.tipo === "merma") {
      movimiento = {
        ...base,
        tipo: "merma",
        producto: crearItem(productoDevuelto, cantidad),
        clienteId: null,
        nombreCliente: null,
      };
    } else if (formulario.tipo === "devolucion") {
      if (!cliente) return;

      movimiento = {
        ...base,
        tipo: "devolucion",
        clienteId: cliente.id,
        nombreCliente: cliente.nombreComercio,
        producto: crearItem(productoDevuelto, cantidad),
      };
    } else {
      if (!cliente || !productoEntregado) return;

      movimiento = {
        ...base,
        tipo: "cambio",
        clienteId: cliente.id,
        nombreCliente: cliente.nombreComercio,
        productoDevuelto: crearItem(productoDevuelto, cantidad),
        productoEntregado: crearItem(
          productoEntregado,
          Number(formulario.cantidadEntregada)
        ),
      };
    }

    // Volvemos a calcular el stock al registrar.
    const resultado = registrarMovimiento(
      movimiento,
      (actuales) => {
        const salidasNuevas = salidasPorMovimiento(movimiento);

        for (const item of salidasNuevas) {
          const cargado = jornada.items.find(
            (p) => p.productoId === item.productoId
          );

          if (!cargado) {
            return `${item.nombreProducto} no está cargado en el camión.`;
          }

          const vendido = ventas
            .filter((v) => v.jornadaId === jornada.id)
            .flatMap((v) => v.items)
            .filter((p) => p.productoId === item.productoId)
            .reduce((suma, p) => suma + p.cantidad, 0);

          const descartado = actuales
            .filter((m) => m.jornadaId === jornada.id)
            .flatMap(salidasPorMovimiento)
            .filter((p) => p.productoId === item.productoId)
            .reduce((suma, p) => suma + p.cantidad, 0);

          if (
            item.cantidad >
            cargado.cantidad - vendido - descartado + 0.000001
          ) {
            return `Stock insuficiente de ${item.nombreProducto}.`;
          }
        }

        return null;
      }
    );

    if (resultado) {
      setError(resultado);
      return;
    }

    setMensaje(`${etiquetas[movimiento.tipo]} registrada correctamente.`);

    setFormulario({
      ...inicial,
      jornadaId: jornada.id,
      tipo: movimiento.tipo,
    });
  }

  return (
    <div className="mx-auto max-w-5xl space-y-6 pb-12">
      <div>
        <p className="text-xs font-semibold uppercase tracking-wide text-blue-600">
          Reparto · Control de mercadería
        </p>
        <h1 className="mt-1 text-3xl font-bold text-slate-900">
          Movimientos de reparto
        </h1>
        <p className="mt-1 text-slate-500">
          Mermas, devoluciones y cambios de productos
        </p>
      </div>

      {mensaje && (
        <div role="status" className="flex items-center gap-2 rounded-xl bg-green-50 p-4 text-green-800">
          <CheckCircle2 size={22} />
          {mensaje}
        </div>
      )}

      {error && (
        <div role="alert" className="flex items-center gap-2 rounded-xl bg-red-50 p-4 text-red-800">
          <AlertTriangle size={22} />
          {error}
        </div>
      )}

      <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <label className="block space-y-2">
          <span className="text-sm font-semibold">Jornada de reparto</span>
          <select
            value={formulario.jornadaId}
            onChange={(e) => {
              setFormulario({
                ...inicial,
                jornadaId: e.target.value,
              });
              setError("");
            }}
            className="min-h-14 w-full rounded-xl border border-slate-300 p-3"
          >
            <option value="">Seleccionar jornada</option>
            {jornadasAbiertas.map((j) => {
              const camion = camiones.find(c => c.id === j.camionId);
              return (
                <option key={j.id} value={j.id}>
                  {camion?.nombre} · {j.chofer} · {j.zona}
                </option>
              );
            })}
          </select>
        </label>
        {jornadasAbiertas.length === 0 && (
          <p className="mt-3 text-sm text-amber-700">
            Primero abrí una jornada desde el módulo Jornadas.
          </p>
        )}
      </section>

      {jornada && (
        <>
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <h2 className="mb-4 text-lg font-bold">
              1. Tipo de movimiento
            </h2>

            <div className="grid grid-cols-3 gap-2">
              {([
                ["merma", PackageX],
                ["devolucion", RotateCcw],
                ["cambio", RefreshCw],
              ] as const).map(([tipo, Icono]) => (
                <button
                  key={tipo}
                  type="button"
                  onClick={() => seleccionarTipo(tipo)}
                  className={`flex min-h-24 flex-col items-center justify-center gap-2 rounded-xl border-2 p-2 text-sm font-semibold ${
                    formulario.tipo === tipo
                      ? "border-blue-600 bg-blue-50 text-blue-700"
                      : "border-slate-200 text-slate-600"
                  }`}
                >
                  <Icono size={25} />
                  {etiquetas[tipo]}
                </button>
              ))}
            </div>

            <div className="mt-4 rounded-lg bg-slate-50 p-3 text-sm text-slate-600">
              {formulario.tipo === "merma"
                ? "Retira del stock vendible mercadería rota, vencida o dañada que está en el camión."
                : formulario.tipo === "devolucion"
                ? "Recibe un producto del cliente y lo deja registrado en cuarentena, sin aumentar el stock vendible."
                : "Recibe un producto del cliente y entrega otro del stock disponible del camión."}
            </div>
          </section>

          <section className="space-y-5 rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <h2 className="text-lg font-bold">
              2. Datos del movimiento
            </h2>

            {requiereCliente && (
              <label className="block space-y-2">
                <span className="text-sm font-medium">Cliente *</span>
                <select
                  value={formulario.clienteId}
                  onChange={(e) =>
                    setFormulario({
                      ...formulario,
                      clienteId: e.target.value,
                    })
                  }
                  className="min-h-14 w-full rounded-xl border border-slate-300 p-3"
                >
                  <option value="">Seleccionar cliente</option>
                  {clientes.filter(c => c.activo).map(c => (
                    <option key={c.id} value={c.id}>
                      {c.nombreComercio}
                    </option>
                  ))}
                </select>
              </label>
            )}

            <div className="grid gap-4 md:grid-cols-2">
              <label className="block space-y-2">
                <span className="text-sm font-medium">
                  {formulario.tipo === "merma"
                    ? "Producto dañado *"
                    : "Producto devuelto por el cliente *"}
                </span>

                <select
                  value={formulario.productoId}
                  onChange={(e) =>
                    setFormulario({
                      ...formulario,
                      productoId: e.target.value,
                      cantidad: "",
                    })
                  }
                  className="min-h-14 w-full rounded-xl border border-slate-300 p-3"
                >
                  <option value="">Seleccionar producto</option>
                  {(formulario.tipo === "merma"
                    ? productos.filter(p =>
                        jornada.items.some(i => i.productoId === p.id)
                      )
                    : productos
                  ).map(p => (
                    <option key={p.id} value={p.id}>
                      {p.nombre}
                    </option>
                  ))}
                </select>
              </label>

              <label className="block space-y-2">
                <span className="text-sm font-medium">
                  Cantidad *
                </span>
                <input
                  type="number"
                  min="0"
                  step="1"
                  value={formulario.cantidad}
                  onChange={(e) =>
                    setFormulario({
                      ...formulario,
                      cantidad: e.target.value,
                    })
                  }
                  placeholder="0"
                  className="min-h-14 w-full rounded-xl border border-slate-300 p-3"
                />
                {formulario.tipo === "merma" && productoDevuelto && (
                  <p className="text-xs text-blue-700">
                    Disponible: {disponibles[productoDevuelto.id] ?? 0}{" "}
                    {unidades[productoDevuelto.unidadMedida]}
                  </p>
                )}
              </label>
            </div>

            {formulario.tipo === "cambio" && (
              <div className="rounded-xl bg-blue-50 p-4">
                <h3 className="mb-3 font-bold text-blue-900">
                  Producto que entregamos de reemplazo
                </h3>

                <div className="grid gap-4 md:grid-cols-2">
                  <label className="block space-y-2">
                    <span className="text-sm font-medium">
                      Producto entregado *
                    </span>
                    <select
                      value={formulario.entregadoId}
                      onChange={(e) =>
                        setFormulario({
                          ...formulario,
                          entregadoId: e.target.value,
                          cantidadEntregada: "",
                        })
                      }
                      className="min-h-14 w-full rounded-xl border border-slate-300 bg-white p-3"
                    >
                      <option value="">Seleccionar producto</option>
                      {jornada.items.map(item => (
                        <option
                          key={item.productoId}
                          value={item.productoId}
                        >
                          {item.nombreProducto}
                        </option>
                      ))}
                    </select>
                  </label>

                  <label className="block space-y-2">
                    <span className="text-sm font-medium">
                      Cantidad entregada *
                    </span>
                    <input
                      type="number"
                      min="0"
                      step="1"
                      value={formulario.cantidadEntregada}
                      onChange={(e) =>
                        setFormulario({
                          ...formulario,
                          cantidadEntregada: e.target.value,
                        })
                      }
                      className="min-h-14 w-full rounded-xl border border-slate-300 bg-white p-3"
                    />
                    {productoEntregado && (
                      <p className="text-xs text-blue-700">
                        Disponible: {disponibles[productoEntregado.id] ?? 0}{" "}
                        {unidades[productoEntregado.unidadMedida]}
                      </p>
                    )}
                  </label>
                </div>
              </div>
            )}

            <label className="block space-y-2">
              <span className="text-sm font-medium">
                Motivo *
              </span>

              <select
                value={formulario.motivo}
                onChange={(e) =>
                  setFormulario({
                    ...formulario,
                    motivo: e.target.value,
                  })
                }
                className="min-h-14 w-full rounded-xl border border-slate-300 p-3"
              >
                <option value="">Seleccionar motivo</option>
                <option value="Producto vencido">Producto vencido</option>
                <option value="Envase roto o dañado">Envase roto o dañado</option>
                <option value="Problema de calidad">Problema de calidad</option>
                <option value="Error en la entrega">Error en la entrega</option>
                <option value="Reclamo del cliente">Reclamo del cliente</option>
                <option value="Otro motivo">Otro motivo</option>
              </select>
            </label>

            <button
              type="button"
              onClick={guardarMovimiento}
              className="min-h-14 w-full rounded-xl bg-blue-600 px-5 text-base font-bold text-white hover:bg-blue-700"
            >
              Registrar {etiquetas[formulario.tipo].toLowerCase()}
            </button>
          </section>

          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <h2 className="mb-4 text-lg font-bold">
              Historial de movimientos
            </h2>

            {movimientosJornada.length === 0 && (
              <p className="text-sm text-slate-500">
                Todavía no se registraron movimientos en esta jornada.
              </p>
            )}

            <div className="space-y-3">
              {[...movimientosJornada].reverse().map(m => (
                <article
                  key={m.id}
                  className="rounded-xl border border-slate-200 p-4"
                >
                  <div className="mb-2 flex items-center justify-between gap-2">
                    <strong>{etiquetas[m.tipo]}</strong>
                    <span className="text-xs text-slate-500">
                      {new Date(m.fecha).toLocaleString("es-AR")}
                    </span>
                  </div>

                  {m.tipo === "cambio" ? (
                    <>
                      <p className="text-sm">
                        Devuelto: {m.productoDevuelto.nombreProducto} ·{" "}
                        {m.productoDevuelto.cantidad}
                      </p>
                      <p className="text-sm">
                        Entregado: {m.productoEntregado.nombreProducto} ·{" "}
                        {m.productoEntregado.cantidad}
                      </p>
                    </>
                  ) : (
                    <p className="text-sm">
                      {m.producto.nombreProducto} · {m.producto.cantidad}{" "}
                      {unidades[m.producto.unidadMedida]}
                    </p>
                  )}

                  {m.nombreCliente && (
                    <p className="mt-1 text-sm text-slate-600">
                      Cliente: {m.nombreCliente}
                    </p>
                  )}

                  <p className="mt-1 text-xs text-slate-500">
                    Motivo: {m.motivo}
                  </p>

                  {m.tipo !== "merma" && (
                    <p className="mt-2 text-xs font-medium text-amber-700">
                      Producto devuelto en cuarentena
                    </p>
                  )}
                </article>
              ))}
            </div>
          </section>
        </>
      )}

      <p className="text-xs text-slate-500">
        Prototipo local. Los productos devueltos quedan registrados
        en cuarentena y no regresan automáticamente al stock vendible.
      </p>
    </div>
  );
}
