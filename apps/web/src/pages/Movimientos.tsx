
import { useMemo, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  PackageX,
  RotateCcw,
  RefreshCw,
} from "lucide-react";

import { useJornadas, leerJornadasDiscriminado } from "../hooks/useJornadas";
import { useCamiones } from "../hooks/useCamiones";
import { useClientes } from "../hooks/useClientes";
import { useProductos } from "../hooks/useProductos";
import { leerVentas, useVentas } from "../hooks/useVentas";
import { useMovimientos} from "../hooks/useMovimientos";
import {
  type TipoMovimiento,
  type MovimientoReparto,
  type ProductoMovimiento,
} from "../data/mockMovimientos";
import type { UnidadMedida } from "../data/mockProductos";
import {
  maximo_piezas_segun_disponible,
  medias_a_texto,
  puede_agregar_media,
} from "../domain/cantidades";
import {
  cantidad_movimiento_desde_entrada,
  disponibilidad_de_jornada,
  validar_stock_movimiento,
} from "../domain/movimientos";
import { revalidar_jornada_para_operacion } from "../domain/jornadas";
import AvisoStorageOperativo from "../components/AvisoStorageOperativo";
import { estadoStorageOperativo } from "./estadoStorageOperativo";

type DatosFormulario = {
  tipo: TipoMovimiento;
  jornadaId: string;
  clienteId: string;
  productoId: string;
  // unidad: cantidad entera. pieza: piezas completas (+ `media`).
  cantidad: string;
  media: boolean;
  entregadoId: string;
  cantidadEntregada: string;
  mediaEntregada: boolean;
  motivo: string;
};

const inicial: DatosFormulario = {
  tipo: "merma",
  jornadaId: "",
  clienteId: "",
  productoId: "",
  cantidad: "",
  media: false,
  entregadoId: "",
  cantidadEntregada: "",
  mediaEntregada: false,
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

interface CampoCantidadProps {
  etiqueta: string;
  unidad: UnidadMedida | undefined;
  texto: string;
  media: boolean;
  // Disponible canónico a mostrar (solo merma y producto entregado).
  disponible?: number;
  fondoBlanco?: boolean;
  onChange: (texto: string, media: boolean) => void;
}

// Unidad: input entero. Pieza: piezas completas + media opcional; se muestra
// el texto legible y se persiste solo el entero canónico (medias piezas).
function CampoCantidad({
  etiqueta,
  unidad,
  texto,
  media,
  disponible,
  fondoBlanco,
  onChange,
}: CampoCantidadProps) {
  const fondo = fondoBlanco ? " bg-white" : "";
  const esPieza = unidad === "pieza";
  const preview = unidad
    ? cantidad_movimiento_desde_entrada(unidad, { texto, media })
    : null;

  const maxPiezas =
    esPieza && disponible !== undefined
      ? maximo_piezas_segun_disponible(disponible, media)
      : undefined;
  const piezasActuales = Number(texto);
  const mediaBloqueada =
    esPieza &&
    disponible !== undefined &&
    !media &&
    Number.isInteger(piezasActuales) &&
    !puede_agregar_media(disponible, piezasActuales);

  return (
    <div className="block space-y-2">
      <label className="block space-y-2">
        <span className="text-sm font-medium">
          {etiqueta}
          {esPieza ? " (piezas enteras)" : ""}
        </span>
        <input
          type="number"
          min="0"
          max={maxPiezas}
          step="1"
          value={texto}
          onChange={(e) => onChange(e.target.value, media)}
          placeholder="0"
          className={`min-h-14 w-full rounded-xl border border-slate-300 p-3${fondo}`}
        />
      </label>

      {esPieza && (
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={media}
            disabled={mediaBloqueada}
            onChange={(e) => onChange(texto, e.target.checked)}
            className="h-4 w-4 rounded border-slate-300"
          />
          <span>Media pieza</span>
        </label>
      )}

      {esPieza && preview !== null && (
        <p className="text-xs text-slate-600">= {medias_a_texto(preview)}</p>
      )}

      {unidad && disponible !== undefined && (
        <p className="text-xs text-blue-700">
          Disponible: {textoCantidad(unidad, disponible)}
        </p>
      )}
    </div>
  );
}

// Disponible y preview legibles según la unidad del producto.
function textoCantidad(unidad: UnidadMedida, cantidad: number) {
  return unidad === "pieza"
    ? medias_a_texto(cantidad)
    : `${cantidad} ${unidades[unidad]}`;
}

export default function Movimientos() {
  const { jornadas, estadoLectura: estadoJornadas } = useJornadas();
  const { camiones, estadoLectura: estadoCamiones } = useCamiones();
  const { clientes, estadoLectura: estadoClientes } = useClientes();
  const { productos, estadoLectura: estadoProductos } = useProductos();
  const { ventas, estadoLectura: estadoVentas } = useVentas();

  const {
    movimientos,
    registrarMovimiento,
    estadoLectura: estadoMovimientos,
  } = useMovimientos();
  const estadoOperacion = estadoStorageOperativo({
    jornadas: estadoJornadas,
    camiones: estadoCamiones,
    clientes: estadoClientes,
    productos: estadoProductos,
    ventas: estadoVentas,
    movimientos: estadoMovimientos,
  });

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

  // Disponibilidad canónica: misma cadena de dominio que la validación previa
  // al registro. Si el cálculo es inseguro no se muestra un saldo aproximado.
  const disponibilidad = useMemo(
    () =>
      disponibilidad_de_jornada(
        formulario.jornadaId,
        jornada?.items ?? [],
        ventas,
        movimientosJornada
      ),
    [jornada, ventas, movimientosJornada, formulario.jornadaId]
  );

  const disponibles = useMemo(
    () => (disponibilidad.ok ? disponibilidad.disponibles : {}),
    [disponibilidad]
  );

  function seleccionarTipo(tipo: TipoMovimiento) {
    setFormulario((actual) => ({
      ...inicial,
      jornadaId: actual.jornadaId,
      tipo,
    }));
    setError("");
    setMensaje("");
  }

  function guardarMovimiento() {
    setMensaje("");
    setError("");
    if (estadoOperacion.bloqueado) return;

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

    const cantidad = cantidad_movimiento_desde_entrada(
      productoDevuelto.unidadMedida,
      { texto: formulario.cantidad, media: formulario.media }
    );

    if (cantidad === null) {
      setError("La cantidad del producto no es válida.");
      return;
    }

    const cantidadEntregada =
      formulario.tipo === "cambio" && productoEntregado
        ? cantidad_movimiento_desde_entrada(
            productoEntregado.unidadMedida,
            {
              texto: formulario.cantidadEntregada,
              media: formulario.mediaEntregada,
            }
          )
        : null;

    if (
      formulario.tipo === "cambio" &&
      (!productoEntregado || cantidadEntregada === null)
    ) {
      setError("Completá el producto de reemplazo y su cantidad.");
      return;
    }

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
      if (!cliente || !productoEntregado || cantidadEntregada === null) return;

      movimiento = {
        ...base,
        tipo: "cambio",
        clienteId: cliente.id,
        nombreCliente: cliente.nombreComercio,
        productoDevuelto: crearItem(productoDevuelto, cantidad),
        productoEntregado: crearItem(productoEntregado, cantidadEntregada),
      };
    }

    // Volvemos a calcular el stock al registrar.
    const resultado = registrarMovimiento(movimiento, (actuales) => {
      // M-2 (bloque E): revalidar la Jornada vigente justo antes de
      // persistir. La jornada del render es un snapshot: puede haberse
      // cerrado, desaparecido o cambiado de camión, y el storage de
      // Jornadas puede haberse corrompido, desde el montaje. Ningún
      // movimiento se persiste después del cierre.
      const revalidacionJornada = revalidar_jornada_para_operacion(
        leerJornadasDiscriminado(),
        jornada,
        "abierta"
      );

      if (!revalidacionJornada.ok) {
        return `No se puede registrar: ${revalidacionJornada.error}`;
      }

      const lecturaVentas = leerVentas();
      if (!lecturaVentas.ok) {
        return `No se puede registrar: ${lecturaVentas.error}`;
      }
      return validar_stock_movimiento(
        movimiento,
        revalidacionJornada.jornada.items,
        lecturaVentas.ventas,
        actuales
      );
    });

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

      <AvisoStorageOperativo avisos={estadoOperacion.avisos} />

      {mensaje && (
        <div role="status" className="flex items-center gap-2 rounded-xl bg-green-50 p-4 text-green-800">
          <CheckCircle2 size={22} />
          {mensaje}
        </div>
      )}

      {!disponibilidad.ok && (
        <div role="alert" className="flex items-center gap-2 rounded-xl bg-red-50 p-4 text-red-800">
          <AlertTriangle size={22} />
          {disponibilidad.error}
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
                      media: false,
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

              <CampoCantidad
                etiqueta="Cantidad *"
                unidad={productoDevuelto?.unidadMedida}
                texto={formulario.cantidad}
                media={formulario.media}
                disponible={
                  formulario.tipo === "merma" && productoDevuelto
                    ? disponibles[productoDevuelto.id] ?? 0
                    : undefined
                }
                onChange={(texto, media) =>
                  setFormulario({ ...formulario, cantidad: texto, media })
                }
              />
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
                          mediaEntregada: false,
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

                  <CampoCantidad
                    etiqueta="Cantidad entregada *"
                    unidad={productoEntregado?.unidadMedida}
                    texto={formulario.cantidadEntregada}
                    media={formulario.mediaEntregada}
                    disponible={
                      productoEntregado
                        ? disponibles[productoEntregado.id] ?? 0
                        : undefined
                    }
                    fondoBlanco
                    onChange={(texto, media) =>
                      setFormulario({
                        ...formulario,
                        cantidadEntregada: texto,
                        mediaEntregada: media,
                      })
                    }
                  />
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
              disabled={estadoOperacion.bloqueado}
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
                        {textoCantidad(
                          m.productoDevuelto.unidadMedida,
                          m.productoDevuelto.cantidad
                        )}
                      </p>
                      <p className="text-sm">
                        Entregado: {m.productoEntregado.nombreProducto} ·{" "}
                        {textoCantidad(
                          m.productoEntregado.unidadMedida,
                          m.productoEntregado.cantidad
                        )}
                      </p>
                    </>
                  ) : (
                    <p className="text-sm">
                      {m.producto.nombreProducto} ·{" "}
                      {textoCantidad(
                        m.producto.unidadMedida,
                        m.producto.cantidad
                      )}
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
