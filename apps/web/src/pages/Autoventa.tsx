
import { useCallback, useMemo, useState } from "react";
import {
  Truck,
  ShoppingCart,
  CheckCircle2,
  AlertTriangle,
  Package,
  Receipt,
} from "lucide-react";

import { useJornadas } from "../hooks/useJornadas";
import { useClientes } from "../hooks/useClientes";
import { useCamiones } from "../hooks/useCamiones";
import { useVentas } from "../hooks/useVentas";

import {
  useMovimientos,
  leerMovimientosDiscriminado,
} from "../hooks/useMovimientos";

import {
  salidasPorMovimiento,
} from "../data/mockMovimientos";

import type {
  Venta,
  MedioPago,
} from "../data/mockVentas";



import {
  cantidad_unidad_desde_texto,
  descomponer_medias,
  es_cantidad_valida,
  maximo_piezas_segun_disponible,
  medias_a_texto,
  puede_agregar_media,
  recomponer_medias,
} from "../domain/cantidades";
import {
  sumar_importes,
} from "../domain/precios";
import { construirItemsVenta } from "../domain/venta";
import AvisoStorageOperativo from "../components/AvisoStorageOperativo";
import { estadoStorageOperativo } from "./estadoStorageOperativo";

// --------------------------------------------------
// FUNCIONES AUXILIARES
// --------------------------------------------------

const moneda = (valor: number) =>
  new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 2,
  }).format(valor);

const unidades = {
  unidad: "un.",
  pieza: "pzas.",
};

// --------------------------------------------------
// COMPONENTE PRINCIPAL
// --------------------------------------------------

export default function Autoventa() {
  // Datos de los módulos existentes.
  const { jornadas, estadoLectura: estadoJornadas } = useJornadas();
  const { clientes, estadoLectura: estadoClientes } = useClientes();
  const { camiones, estadoLectura: estadoCamiones } = useCamiones();
  const { ventas, registrarVenta, estadoLectura: estadoVentas } = useVentas();

  // Movimientos: mermas, devoluciones y cambios.
  const { movimientos, estadoLectura: estadoMovimientos } = useMovimientos();
  const estadoOperacion = estadoStorageOperativo({
    jornadas: estadoJornadas,
    clientes: estadoClientes,
    camiones: estadoCamiones,
    ventas: estadoVentas,
    movimientos: estadoMovimientos,
  });

  // Formulario de venta.
  const [jornadaId, setJornadaId] = useState("");
  const [clienteId, setClienteId] = useState("");

  const [cantidades, setCantidades] = useState<
    Record<number, string | { piezas: number; media: boolean }>
  >({});

  const [medioPago, setMedioPago] =
    useState<MedioPago>("efectivo");

  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");

  // --------------------------------------------------
  // JORNADAS Y CLIENTES
  // --------------------------------------------------

  // Solo se puede vender en jornadas abiertas.
  const jornadasAbiertas = useMemo(
    () =>
      jornadas.filter(
        (jornada) => jornada.estado === "abierta"
      ),
    [jornadas]
  );

  // Referencia estable: evita recrear el objeto en cada render
  // y así invalidar los useMemo que dependen de `jornada`.
  const jornada = useMemo(
    () => jornadasAbiertas.find((j) => j.id === jornadaId),
    [jornadasAbiertas, jornadaId]
  );

  const camion = camiones.find(
    (c) => c.id === jornada?.camionId
  );

  const cliente = clientes.find(
    (c) => c.id === Number(clienteId) && c.activo
  );

  // --------------------------------------------------
  // CÁLCULO DEL STOCK DEL CAMIÓN
  // --------------------------------------------------

  // Sumamos todas las salidas de mercadería vendible:
  // 1. Ventas.
  // 2. Mermas.
  // 3. Productos entregados en cambios.
  //
  // Las devoluciones NO aumentan el stock vendible:
  // quedan registradas en cuarentena.

  const cantidadesDescontadas = useMemo(() => {
    const resultado: Record<number, number> = {};

    // Descontar productos vendidos.
    for (const venta of ventas) {
      if (venta.jornadaId !== jornadaId) continue;

      for (const item of venta.items) {
        resultado[item.productoId] =
          (resultado[item.productoId] ?? 0) +
          item.cantidad;
      }
    }

    // Descontar mermas y reemplazos entregados.
    for (const movimiento of movimientos) {
      if (movimiento.jornadaId !== jornadaId) continue;

      for (const item of salidasPorMovimiento(movimiento)) {
        resultado[item.productoId] =
          (resultado[item.productoId] ?? 0) +
          item.cantidad;
      }
    }

    return resultado;
  }, [ventas, movimientos, jornadaId]);

  // Mercadería disponible en el camión.
  const productosCamion = useMemo(() => {
    if (!jornada) return [];

    return jornada.items.map((item) => ({
      ...item,
      disponible: Math.max(
        0,
        item.cantidad -
          (cantidadesDescontadas[item.productoId] ?? 0)
      ),
    }));
  }, [jornada, cantidadesDescontadas]);

  // --------------------------------------------------
  // HELPERS PARA CANTIDADES CANÓNICAS
  // --------------------------------------------------

  // Helper para obtener la cantidad canónica (medias piezas) desde el estado
  const obtenerCantidadCanonica = useCallback(
    (productoId: number): number => {
      const valor = cantidades[productoId];
      if (!valor) return 0;
      const producto = productosCamion.find((p) => p.productoId === productoId);
      if (!producto) return 0;
      if (producto.unidadMedida === "unidad") {
        return typeof valor === "string"
          ? (cantidad_unidad_desde_texto(valor) ?? 0)
          : 0;
      }
      // producto.unidadMedida === "pieza": el estado es { piezas, media }.
      if (typeof valor === "object") {
        try {
          return recomponer_medias(valor);
        } catch {
          return 0;
        }
      }
      return 0;
    },
    [cantidades, productosCamion]
  );



  // --------------------------------------------------
  // ARMAR EL DETALLE DE VENTA
  // --------------------------------------------------

  const itemsVenta = useMemo(() => {
    return construirItemsVenta({
      productos: productosCamion.map((p) => ({
        productoId: p.productoId,
        nombreProducto: p.nombreProducto,
        unidadMedida: p.unidadMedida,
        precioReferencia: p.precioReferencia,
      })),
      obtenerCantidadCanonica,
    });
  }, [productosCamion, obtenerCantidadCanonica]);

  // Importe total de la venta.
  const total = sumar_importes(itemsVenta.map((item) => item.subtotal));

  // Historial de ventas de la jornada seleccionada.
  const ventasJornada = ventas
    .filter((venta) => venta.jornadaId === jornadaId)
    .sort((a, b) => b.fecha.localeCompare(a.fecha));

  // --------------------------------------------------
  // CAMBIAR DE JORNADA
  // --------------------------------------------------

  function seleccionarJornada(id: string) {
    setJornadaId(id);
    setClienteId("");
    setCantidades({});
    setMedioPago("efectivo");
    setMensaje("");
    setError("");
  }

  // --------------------------------------------------
  // CAMBIAR CANTIDAD DE UN PRODUCTO (solo para "unidad")


  // --------------------------------------------------
  // REGISTRAR LA VENTA
  // --------------------------------------------------

  function guardarVenta() {
    setError("");
    setMensaje("");
    if (estadoOperacion.bloqueado) return;

    if (!jornada || !camion) {
      setError("Seleccioná una jornada abierta.");
      return;
    }

    if (!cliente) {
      setError("Seleccioná un cliente activo.");
      return;
    }

    if (itemsVenta.length === 0) {
      setError("Agregá al menos un producto.");
      return;
    }

    if (
      medioPago === "cuenta_corriente" &&
      cliente.condicionPago !== "cuenta_corriente"
    ) {
      setError(
        "Este cliente no tiene cuenta corriente habilitada."
      );
      return;
    }

    // Crear la venta con los precios y cantidades actuales.
    const venta: Venta = {
      id: crypto.randomUUID(),
      jornadaId: jornada.id,
      camionId: jornada.camionId,
      clienteId: cliente.id,
      nombreCliente: cliente.nombreComercio,
      fecha: new Date().toISOString(),
      medioPago,
      items: itemsVenta,
      total,
    };

    // ------------------------------------------------
    // REVALIDACIÓN DEL STOCK
    // ------------------------------------------------

    const resultado = registrarVenta(
      venta,
      (ventasActuales) => {
        // Leemos los movimientos más recientes de la demo.
        const lecturaMovimientos = leerMovimientosDiscriminado();
        if (!lecturaMovimientos.ok) {
          return `No se puede registrar: ${lecturaMovimientos.error}`;
        }
        const movimientosActuales = lecturaMovimientos.movimientos;

        for (const item of itemsVenta) {
          // Cantidad que salió cargada en el camión.
          const cargado = jornada.items.find(
            (producto) =>
              producto.productoId === item.productoId
          );

          if (!cargado) {
            return (
              `El producto ${item.nombreProducto} ` +
              "no está cargado en el camión."
            );
          }

          // Cantidad ya vendida en esta jornada.
          const vendido = ventasActuales
            .filter(
              (v) => v.jornadaId === jornada.id
            )
            .flatMap((v) => v.items)
            .filter(
              (p) => p.productoId === item.productoId
            )
            .reduce(
              (suma, p) => suma + p.cantidad,
              0
            );

          // Cantidad retirada por mermas y reemplazos.
          const retirado = movimientosActuales
            .filter(
              (m) => m.jornadaId === jornada.id
            )
            .flatMap(salidasPorMovimiento)
            .filter(
              (p) => p.productoId === item.productoId
            )
            .reduce(
              (suma, p) => suma + p.cantidad,
              0
            );

          // Cantidad que realmente queda disponible.
          const restante = Math.max(
            0,
            cargado.cantidad - vendido - retirado
          );

          // Validar cantidades y unidad de medida.
          const cantidadValida =
            Number.isFinite(item.cantidad) &&
            item.cantidad > 0 &&
            Number.isInteger(item.cantidad);

          if (!cantidadValida) {
            return (
              `Cantidad inválida de ` +
              item.nombreProducto
            );
          }

          // Usar cantidad canónica para validar stock
          const cantidadCanonica = item.cantidad;
          if (cantidadCanonica > restante + 0.000001) {
            return (
              `Stock insuficiente de ` +
              item.nombreProducto
            );
          }
        }

        return null;
      }
    );

    // Mostrar error si no se pudo registrar.
    if (resultado) {
      setError(resultado);
      return;
    }

    // Limpiar los datos de la venta.
    setCantidades({});
    setClienteId("");
    setMedioPago("efectivo");

    setMensaje(
      `Venta registrada correctamente por ${moneda(total)}.`
    );
  }

  // --------------------------------------------------
  // INTERFAZ
  // --------------------------------------------------

  return (
    <div className="mx-auto max-w-4xl space-y-5 pb-10">
      {/* ENCABEZADO */}
      <div>
        <p className="text-xs font-bold uppercase tracking-wider text-blue-600">
          Autoventa · Repartidor
        </p>

        <h1 className="mt-1 text-3xl font-bold text-slate-900">
          Ventas en ruta
        </h1>

        <p className="mt-1 text-sm text-slate-500">
          Registro de ventas desde el camión
        </p>
      </div>

      <AvisoStorageOperativo avisos={estadoOperacion.avisos} />

      {/* MENSAJES */}
      {mensaje && (
        <div
          role="status"
          className="flex items-center gap-2 rounded-xl bg-green-50 p-4 text-green-800"
        >
          <CheckCircle2 size={22} />
          {mensaje}
        </div>
      )}

      {error && (
        <div
          role="alert"
          className="flex items-center gap-2 rounded-xl bg-red-50 p-4 text-red-800"
        >
          <AlertTriangle size={22} />
          {error}
        </div>
      )}

      {/* SELECCIÓN DE JORNADA */}
      <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <div className="mb-4 flex items-center gap-2">
          <Truck
            size={23}
            className="text-blue-600"
          />

          <h2 className="text-lg font-bold">
            Jornada activa
          </h2>
        </div>

        <label className="block space-y-2">
          <span className="text-sm font-medium">
            Seleccionar reparto
          </span>

          <select
            value={jornadaId}
            onChange={(e) =>
              seleccionarJornada(e.target.value)
            }
            className="min-h-14 w-full rounded-xl border border-slate-300 bg-white p-3 text-base"
          >
            <option value="">
              Seleccionar jornada
            </option>

            {jornadasAbiertas.map((j) => {
              const c = camiones.find(
                (camion) =>
                  camion.id === j.camionId
              );

              return (
                <option
                  key={j.id}
                  value={j.id}
                >
                  {c?.nombre ?? "Camión"} ·{" "}
                  {j.chofer} · {j.zona}
                </option>
              );
            })}
          </select>
        </label>

        {jornadasAbiertas.length === 0 && (
          <p className="mt-3 rounded-lg bg-amber-50 p-3 text-sm text-amber-800">
            No hay jornadas abiertas.
            Primero prepará una carga desde
            Jornadas y confirmá la salida.
          </p>
        )}

        {jornada && (
          <div className="mt-4 rounded-lg bg-blue-50 p-4">
            <p className="font-semibold text-blue-900">
              {camion?.nombre ??
                "Camión no encontrado"}{" "}
              · {jornada.chofer}
            </p>

            <p className="text-sm text-blue-700">
              Zona: {jornada.zona}
            </p>
          </div>
        )}
      </section>

      {jornada && (
        <>
          {/* CLIENTE */}
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <h2 className="mb-4 text-lg font-bold">
              1. Seleccionar cliente
            </h2>

            <select
              value={clienteId}
              onChange={(e) => {
                setClienteId(e.target.value);
                setMedioPago("efectivo");
              }}
              className="min-h-14 w-full rounded-xl border border-slate-300 p-3 text-base"
            >
              <option value="">
                Elegir comercio
              </option>

              {clientes
                .filter((c) => c.activo)
                .map((c) => (
                  <option
                    key={c.id}
                    value={c.id}
                  >
                    {c.nombreComercio} · {c.zona}
                  </option>
                ))}
            </select>

            {cliente && (
              <p className="mt-3 text-sm text-slate-500">
                {cliente.direccion} ·{" "}
                {cliente.condicionPago ===
                "cuenta_corriente"
                  ? "Cuenta corriente habilitada"
                  : "Pago contado"}
              </p>
            )}
          </section>

          {/* PRODUCTOS DEL CAMIÓN */}
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="mb-4 flex items-center gap-2">
              <Package
                size={22}
                className="text-blue-600"
              />

              <h2 className="text-lg font-bold">
                2. Agregar productos
              </h2>
            </div>

            <div className="space-y-3">
              {productosCamion.map((producto) => {
                const disponible = producto.disponible;
                const esPieza = producto.unidadMedida === "pieza";
                const valorActual = cantidades[producto.productoId];
                const disponibleTexto = esPieza
                  ? medias_a_texto(disponible)
                  : `${disponible} ${unidades[producto.unidadMedida]}`;

                if (esPieza) {
                  // UX para fiambres: piezas enteras + media pieza opcional
                  const { piezas, media } = valorActual
                    ? (typeof valorActual === "object"
                        ? valorActual
                        : descomponer_medias(Number(valorActual)))
                    : { piezas: 0, media: false };

                  // Calcula la cantidad canónica actual de la UX
                  const cantidadCanonicaActual = recomponer_medias({ piezas, media });

                  // Máximo de piezas enteras permitidas, considerando si media ya está marcada.
                  // Si media=true, restamos 1 del disponible antes de dividir por 2.
                  const maxPiezas = maximo_piezas_segun_disponible(
                    disponible,
                    media
                  );

                  // Media está deshabilitada si:
                  // - no hay stock disponible (disponible < 1), o
                  // - las piezas actuales * 2 ya consumen todo el stock disponible (no queda espacio para media)
                  const mediaDisabled = !puede_agregar_media(disponible, piezas);

                  // Helper para actualizar estado validando contra stock total
                  const actualizarCantidades = (nuevasPiezas: number, nuevaMedia: boolean) => {
                    const canonica = recomponer_medias({ piezas: nuevasPiezas, media: nuevaMedia });
                    if (canonica > disponible) {
                      // No permitir transición que exceda el stock
                      return;
                    }
                    setCantidades((actuales: Record<number, string | { piezas: number; media: boolean }>) => ({
                      ...actuales,
                      [producto.productoId]: { piezas: nuevasPiezas, media: nuevaMedia },
                    }));
                  };

                  return (
                    <div
                      key={producto.productoId}
                      className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-slate-200 p-4"
                    >
                      <div className="flex min-w-0 items-center gap-3">
                        <Package
                          className="shrink-0 text-blue-600"
                          size={23}
                        />
                        <div>
                          <p className="font-medium text-slate-800">
                            {producto.nombreProducto}
                          </p>
                          <p className="text-sm text-slate-500">
                            Disponible: {disponibleTexto}
                          </p>
                          <p className="text-xs text-slate-400">
                            {moneda(producto.precioReferencia)} por pieza
                          </p>
                        </div>
                      </div>
                      <div className="flex items-center gap-3">
                        <label className="flex items-center gap-2 text-sm">
                          <span>Piezas:</span>
                          <input
                            type="number"
                            min="0"
                            max={maxPiezas}
                            step="1"
                            value={piezas}
                            onChange={(e) => {
                              const nuevasPiezas = Math.max(0, Number(e.target.value));
                              if (!es_cantidad_valida(nuevasPiezas)) {
                                setError(
                                  `Piezas inválidas de ${producto.nombreProducto}: se esperaba un entero mayor o igual que cero.`
                                );
                                return;
                              }
                              setError("");
                              actualizarCantidades(nuevasPiezas, media);
                            }}
                            className="min-h-12 w-20 rounded-lg border border-slate-300 p-3 text-right"
                            aria-label={`Piezas enteras de ${producto.nombreProducto}`}
                          />
                        </label>
                        <label className="flex items-center gap-2 text-sm">
                          <input
                            type="checkbox"
                            checked={media}
                            disabled={mediaDisabled}
                            onChange={(e) => {
                              const nuevaMedia = e.target.checked;
                              actualizarCantidades(piezas, nuevaMedia);
                            }}
                            className="w-4 h-4 rounded border-slate-300"
                            aria-label={`Media pieza de ${producto.nombreProducto}`}
                          />
                          <span>Media pieza</span>
                        </label>
                        <span className="text-slate-500 text-sm">
                          = {medias_a_texto(cantidadCanonicaActual)}
                        </span>
                      </div>
                    </div>
                  );
                }

                // UX para lácteos: solo entero
                return (
                  <div
                    key={producto.productoId}
                    className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-slate-200 p-4"
                  >
                    <div className="flex min-w-0 items-center gap-3">
                      <Package
                        className="shrink-0 text-blue-600"
                        size={23}
                      />
                      <div>
                        <p className="font-medium text-slate-800">
                          {producto.nombreProducto}
                        </p>
                        <p className="text-sm text-slate-500">
                          Disponible: {disponible} {unidades[producto.unidadMedida]}
                        </p>
                        <p className="text-xs text-slate-400">
                          {moneda(producto.precioReferencia)} por{" "}
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
                        value={(cantidades[producto.productoId] as string) ?? ""}
                        onChange={(e) =>
                          setCantidades((actuales: Record<number, string | { piezas: number; media: boolean }>) => ({
                            ...actuales,
                            [producto.productoId]: e.target.value,
                          }))
                        }
                        className="min-h-12 w-24 rounded-lg border border-slate-300 p-3 text-right"
                        aria-label={`Cantidad de ${producto.nombreProducto}`}
                      />
                    <span className="w-10 text-slate-500">
                      {unidades[producto.unidadMedida]}
                    </span>
                  </label>
                </div>
                );
              })}
            </div>

            {productosCamion.length === 0 && (
              <p className="py-5 text-center text-slate-500">
                Esta jornada no tiene productos cargados.
              </p>
            )}
          </section>

          {/* RESUMEN Y COBRO */}
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="mb-4 flex items-center gap-2">
              <ShoppingCart
                size={22}
                className="text-blue-600"
              />

              <h2 className="text-lg font-bold">
                3. Resumen y cobro
              </h2>
            </div>

            {itemsVenta.length === 0 ? (
              <p className="text-sm text-slate-500">
                Seleccioná productos para preparar la venta.
              </p>
            ) : (
              <div className="space-y-3">
                {itemsVenta.map((item) => (
                  <div
                    key={item.productoId}
                    className="flex items-start justify-between gap-3 border-b border-slate-100 pb-3 text-sm"
                  >
                    <div>
                      <p className="font-medium">
                        {item.nombreProducto}
                      </p>

                      <p className="text-slate-500">
                        {item.unidadMedida === "pieza" ? medias_a_texto(item.cantidad) : item.cantidad} ×{" "}
                        {moneda(item.precioUnitario)}
                      </p>
                    </div>

                    <strong>
                      {moneda(item.subtotal)}
                    </strong>
                  </div>
                ))}
              </div>
            )}

            {/* TOTAL */}
            <div className="my-5 flex items-center justify-between gap-3 border-t border-slate-200 pt-4">
              <span className="font-semibold">
                Total de venta
              </span>

              <span className="text-2xl font-bold text-slate-900 sm:text-3xl">
                {moneda(total)}
              </span>
            </div>

            {/* MEDIOS DE PAGO */}
            <p className="mb-3 text-sm font-semibold">
              Forma de pago
            </p>

            <div className="grid gap-3 sm:grid-cols-3">
              {(
                [
                  ["efectivo", "Efectivo"],
                  ["transferencia", "Transferencia"],
                  ["cuenta_corriente", "Cuenta corriente"],
                ] as const
              ).map(([valor, etiqueta]) => {
                const deshabilitado =
                  valor === "cuenta_corriente" &&
                  cliente?.condicionPago !==
                    "cuenta_corriente";

                return (
                  <button
                    key={valor}
                    type="button"
                    disabled={deshabilitado}
                    onClick={() =>
                      setMedioPago(valor)
                    }
                    className={`min-h-14 rounded-xl border-2 px-3 py-3 font-medium transition-colors ${
                      medioPago === valor
                        ? "border-blue-600 bg-blue-50 text-blue-700"
                        : "border-slate-200 bg-white text-slate-700"
                    } disabled:cursor-not-allowed disabled:opacity-40`}
                  >
                    {etiqueta}
                  </button>
                );
              })}
            </div>

            {/* GUARDAR VENTA */}
            <button
              type="button"
              onClick={guardarVenta}
              disabled={
                estadoOperacion.bloqueado ||
                !cliente ||
                itemsVenta.length === 0 ||
                !camion
              }
              className="mt-6 flex min-h-14 w-full items-center justify-center gap-2 rounded-xl bg-green-600 px-5 text-lg font-bold text-white hover:bg-green-700 disabled:cursor-not-allowed disabled:opacity-40"
            >
              <CheckCircle2 size={24} />
              Registrar venta
            </button>
          </section>

          {/* HISTORIAL DE VENTAS */}
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="mb-4 flex items-center gap-2">
              <Receipt
                size={22}
                className="text-blue-600"
              />

              <h2 className="text-lg font-bold">
                Ventas registradas
              </h2>
            </div>

            {ventasJornada.length === 0 && (
              <p className="text-sm text-slate-500">
                Todavía no hay ventas en esta jornada.
              </p>
            )}

            <div className="space-y-3">
              {ventasJornada.map((venta) => (
                <div
                  key={venta.id}
                  className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-slate-50 p-4"
                >
                  <div>
                    <p className="font-semibold text-slate-800">
                      {venta.nombreCliente}
                    </p>

                    <p className="text-xs text-slate-500">
                      {new Date(
                        venta.fecha
                      ).toLocaleString("es-AR")}
                    </p>

                    <p className="mt-1 text-xs text-blue-700">
                      {venta.medioPago ===
                      "cuenta_corriente"
                        ? "Cuenta corriente"
                        : venta.medioPago ===
                          "transferencia"
                        ? "Transferencia"
                        : "Efectivo"}
                    </p>
                  </div>

                  <span className="font-bold text-slate-900">
                    {moneda(venta.total)}
                  </span>
                </div>
              ))}
            </div>
          </section>
        </>
      )}

      {/* AVISO DE PROTOTIPO */}
      <p className="text-center text-xs text-slate-500">
        Prototipo de demostración.
        Sin cobros reales, facturación
        ni sincronización entre dispositivos.
      </p>
    </div>
  );
}
