
import { useMemo, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  ClipboardCheck,
  Truck,
} from "lucide-react";

import { useJornadas } from "../hooks/useJornadas";
import { useCamiones } from "../hooks/useCamiones";
import { useVentas } from "../hooks/useVentas";
import { useMovimientos } from "../hooks/useMovimientos";
import { useCobros } from "../hooks/useCobros";
import { salidasPorMovimiento } from "../data/mockMovimientos";

const moneda = (cantidad: number) =>
  new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
  }).format(cantidad);

const unidades = {
  unidad: "un.",
  pieza: "pzas.",
  kg: "kg",
} as const;

const redondear = (cantidad: number) =>
  Math.round((cantidad + Number.EPSILON) * 1000) / 1000;

function leerCantidad(
  texto: string | undefined
): number | null {
  if (texto === undefined || texto.trim() === "") {
    return null;
  }

  const cantidad = Number(texto);

  return Number.isFinite(cantidad) && cantidad >= 0
    ? cantidad
    : null;
}

function cantidadValida(
  cantidad: number,
  unidad: "unidad" | "pieza" | "kg"
): boolean {
  return (
    Number.isFinite(cantidad) &&
    cantidad >= 0 &&
    (unidad === "kg"
      ? Math.abs(
          cantidad * 1000 - Math.round(cantidad * 1000)
        ) < 0.000001
      : Number.isInteger(cantidad))
  );
}

export default function Rendicion() {
  const { jornadas, cerrarJornada } = useJornadas();
  const { camiones } = useCamiones();
  const { ventas } = useVentas();
  const { movimientos } = useMovimientos();
  const { cobros } = useCobros();

  const [jornadaId, setJornadaId] = useState("");
  const [conteos, setConteos] = useState<
    Record<string, string>
  >({});
  const [efectivoEntregado, setEfectivoEntregado] =
    useState("");
  const [observaciones, setObservaciones] = useState("");
  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");

  const jornada = jornadas.find(
    (j) => j.id === jornadaId
  );

  const camion = camiones.find(
    (c) => c.id === jornada?.camionId
  );

  const jornadasOrdenadas = [...jornadas].sort(
    (a, b) =>
      b.fechaCreacion.localeCompare(a.fechaCreacion)
  );

  // Las operaciones se vinculan por ID de jornada.
  // Una venta fiada genera deuda, NO efectivo.
  // Un cobro de deuda anterior suma a la caja
  // cuando se realizó durante esta jornada.
  const resumenCaja = useMemo(() => {
    let ventasEfectivo = 0;
    let ventasTransferencia = 0;
    let ventasCuentaCorriente = 0;
    let cobrosEfectivo = 0;
    let cobrosTransferencia = 0;
    let cantidadVentas = 0;
    let cantidadCobros = 0;

    for (const venta of ventas) {
      if (venta.jornadaId !== jornadaId) continue;

      cantidadVentas += 1;

      if (venta.medioPago === "efectivo") {
        ventasEfectivo += venta.total;
      } else if (venta.medioPago === "transferencia") {
        ventasTransferencia += venta.total;
      } else {
        ventasCuentaCorriente += venta.total;
      }
    }

    for (const cobro of cobros) {
      if (cobro.jornadaId !== jornadaId) continue;

      cantidadCobros += 1;

      if (cobro.medio === "efectivo") {
        cobrosEfectivo += cobro.importe;
      } else {
        cobrosTransferencia += cobro.importe;
      }
    }

    const dinero = (valor: number) =>
      Math.round(valor * 100) / 100;

    return {
      ventasEfectivo: dinero(ventasEfectivo),
      ventasTransferencia: dinero(ventasTransferencia),
      cuentaCorriente: dinero(ventasCuentaCorriente),
      cobrosEfectivo: dinero(cobrosEfectivo),
      cobrosTransferencia: dinero(cobrosTransferencia),

      efectivo: dinero(
        ventasEfectivo + cobrosEfectivo
      ),

      transferencias: dinero(
        ventasTransferencia + cobrosTransferencia
      ),

      totalVendido: dinero(
        ventasEfectivo +
          ventasTransferencia +
          ventasCuentaCorriente
      ),

      cantidadVentas,
      cantidadCobros,
    };
  }, [ventas, cobros, jornadaId]);

  const filasMercaderia = useMemo(() => {
    if (!jornada) return [];

    return jornada.items.map((item) => {
      let vendido = 0;
      let merma = 0;
      let reemplazos = 0;

      for (const venta of ventas) {
        if (venta.jornadaId !== jornada.id) continue;

        for (const detalle of venta.items) {
          if (detalle.productoId === item.productoId) {
            vendido += detalle.cantidad;
          }
        }
      }

      for (const movimiento of movimientos) {
        if (movimiento.jornadaId !== jornada.id) {
          continue;
        }

        if (
          movimiento.tipo === "merma" &&
          movimiento.producto.productoId ===
            item.productoId
        ) {
          merma += movimiento.producto.cantidad;
        }

        if (movimiento.tipo === "cambio") {
          for (const salida of salidasPorMovimiento(
            movimiento
          )) {
            if (salida.productoId === item.productoId) {
              reemplazos += salida.cantidad;
            }
          }
        }
      }

      const esperado = redondear(
        item.cantidad - vendido - merma - reemplazos
      );

      const contado = leerCantidad(
        conteos[String(item.productoId)]
      );

      const diferencia =
        contado === null
          ? null
          : redondear(contado - esperado);

      return {
        ...item,
        vendido: redondear(vendido),
        merma: redondear(merma),
        reemplazos: redondear(reemplazos),
        esperado,
        contado,
        diferencia,
      };
    });
  }, [jornada, ventas, movimientos, conteos]);

  const productosCuarentena = useMemo(() => {
    const acumulado = new Map<
      number,
      {
        productoId: number;
        nombre: string;
        cantidad: number;
        unidad: string;
      }
    >();

    for (const movimiento of movimientos) {
      if (
        movimiento.jornadaId !== jornadaId ||
        movimiento.tipo === "merma"
      ) {
        continue;
      }

      const producto =
        movimiento.tipo === "cambio"
          ? movimiento.productoDevuelto
          : movimiento.producto;

      const anterior = acumulado.get(
        producto.productoId
      );

      acumulado.set(producto.productoId, {
        productoId: producto.productoId,
        nombre: producto.nombreProducto,
        cantidad: redondear(
          (anterior?.cantidad ?? 0) +
            producto.cantidad
        ),
        unidad: unidades[producto.unidadMedida],
      });
    }

    return [...acumulado.values()];
  }, [movimientos, jornadaId]);

  const efectivoContado = leerCantidad(
    efectivoEntregado
  );

  const diferenciaEfectivo =
    efectivoContado === null
      ? null
      : Math.round(
          (efectivoContado - resumenCaja.efectivo) *
            100
        ) / 100;

  const tieneDiferencias =
    filasMercaderia.some(
      (fila) =>
        fila.diferencia !== null &&
        Math.abs(fila.diferencia) > 0.000001
    ) ||
    (diferenciaEfectivo !== null &&
      Math.abs(diferenciaEfectivo) > 0.009);

  const stockInconsistente =
    filasMercaderia.some(
      (fila) => fila.esperado < -0.000001
    );

  function seleccionarJornada(id: string) {
    setJornadaId(id);
    setConteos({});
    setEfectivoEntregado("");
    setObservaciones("");
    setMensaje("");
    setError("");

    const elegida = jornadas.find(
      (j) => j.id === id
    );

    if (elegida?.cierre) {
      setConteos(
        Object.fromEntries(
          Object.entries(
            elegida.cierre.conteos
          ).map(([clave, cantidad]) => [
            clave,
            String(cantidad),
          ])
        )
      );

      setEfectivoEntregado(
        String(elegida.cierre.efectivoEntregado)
      );

      setObservaciones(
        elegida.cierre.observaciones
      );
    }
  }

  function completarConEsperados() {
    if (
      !jornada ||
      jornada.estado !== "abierta" ||
      stockInconsistente
    ) {
      return;
    }

    setConteos(
      Object.fromEntries(
        filasMercaderia.map((fila) => [
          String(fila.productoId),
          String(fila.esperado),
        ])
      )
    );

    setError("");

    setMensaje(
      "Se completaron las cantidades esperadas como referencia. Verificá el conteo físico antes de confirmar."
    );
  }

  function confirmarCierre() {
    setError("");
    setMensaje("");

    if (
      !jornada ||
      jornada.estado !== "abierta"
    ) {
      setError(
        "Seleccioná una jornada abierta."
      );
      return;
    }

    if (stockInconsistente) {
      setError(
        "Hay productos con stock esperado negativo. Revisá las ventas y movimientos antes de cerrar."
      );
      return;
    }

    const conteosFinales: Record<
      string,
      number
    > = {};

    for (const fila of filasMercaderia) {
      const valor = leerCantidad(
        conteos[String(fila.productoId)]
      );

      if (
        valor === null ||
        !cantidadValida(
          valor,
          fila.unidadMedida
        )
      ) {
        setError(
          `Ingresá un conteo válido para ${fila.nombreProducto}.`
        );
        return;
      }

      conteosFinales[
        String(fila.productoId)
      ] = valor;
    }

    if (
      efectivoContado === null ||
      Math.abs(
        efectivoContado * 100 -
          Math.round(
            efectivoContado * 100
          )
      ) > 0.000001
    ) {
      setError(
        "Ingresá un importe válido de efectivo entregado (puede ser 0)."
      );
      return;
    }

    if (
      tieneDiferencias &&
      !observaciones.trim()
    ) {
      setError(
        "Hay diferencias de stock o de caja. Es obligatorio explicar el motivo."
      );
      return;
    }

    const confirmado = window.confirm(
      "¿Confirmás el cierre de esta jornada?\n\n" +
        "Después no se podrán registrar más ventas ni movimientos en ella."
    );

    if (!confirmado) return;

    const cierre = {
      fecha: new Date().toISOString(),
      conteos: conteosFinales,
      efectivoEntregado: efectivoContado,
      efectivoEsperado: resumenCaja.efectivo,
      transferenciasInformadas:
        resumenCaja.transferencias,
      ventasCuentaCorriente:
        resumenCaja.cuentaCorriente,
      observaciones: observaciones.trim(),
    };

    if (
      !cerrarJornada(
        jornada.id,
        cierre
      )
    ) {
      setError(
        "No se pudo guardar el cierre. Verificá que la jornada siga abierta."
      );
      return;
    }

    setMensaje(
      "Jornada cerrada correctamente."
    );
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6 pb-12">
      <header>
        <p className="text-xs font-bold uppercase text-blue-600">
          Administración · Reparto
        </p>

        <h1 className="mt-1 text-3xl font-bold text-slate-900">
          Rendición y cierre
        </h1>

        <p className="mt-1 text-slate-500">
          Conciliación de mercadería y dinero por jornada
        </p>
      </header>

      {mensaje && (
        <div
          role="status"
          className="flex gap-2 rounded-xl bg-green-50 p-4 text-green-800"
        >
          <CheckCircle2
            size={22}
            className="shrink-0"
          />
          <span>{mensaje}</span>
        </div>
      )}

      {error && (
        <div
          role="alert"
          className="flex gap-2 rounded-xl bg-red-50 p-4 text-red-800"
        >
          <AlertTriangle
            size={22}
            className="shrink-0"
          />
          <span>{error}</span>
        </div>
      )}

      <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <div className="mb-4 flex items-center gap-2">
          <Truck className="text-blue-600" />
          <h2 className="text-lg font-bold">
            Jornada para rendir
          </h2>
        </div>

        <select
          value={jornadaId}
          onChange={(e) =>
            seleccionarJornada(
              e.target.value
            )
          }
          className="min-h-14 w-full rounded-xl border border-slate-300 p-3"
          aria-label="Seleccionar jornada para rendición"
        >
          <option value="">
            Seleccionar jornada
          </option>

          {jornadasOrdenadas
            .filter(
              (j) =>
                j.estado !== "preparacion"
            )
            .map((j) => {
              const c = camiones.find(
                (camion) =>
                  camion.id ===
                  j.camionId
              );

              return (
                <option
                  key={j.id}
                  value={j.id}
                >
                  {c?.nombre ?? "Camión"} ·{" "}
                  {j.chofer} ·{" "}
                  {j.estado === "cerrada"
                    ? "Cerrada"
                    : "En reparto"}
                </option>
              );
            })}
        </select>

        {jornada && (
          <div className="mt-4 rounded-xl bg-blue-50 p-4 text-blue-900">
            <p className="font-semibold">
              {camion?.nombre ?? "Camión"} ·{" "}
              {jornada.chofer}
            </p>

            <p className="text-sm">
              Zona: {jornada.zona}
            </p>

            <p className="mt-1 text-sm font-medium">
              Estado:{" "}
              {jornada.estado === "cerrada"
                ? "Jornada cerrada"
                : "Pendiente de rendición"}
            </p>
          </div>
        )}
      </section>

      {jornada && (
        <>
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <ClipboardCheck className="text-blue-600" />
                <h2 className="text-xl font-bold">
                  1. Control de mercadería
                </h2>
              </div>

              {jornada.estado === "abierta" && (
                <button
                  type="button"
                  onClick={completarConEsperados}
                  disabled={stockInconsistente}
                  className="min-h-11 rounded-lg border border-blue-300 px-3 text-sm font-semibold text-blue-700 hover:bg-blue-50 disabled:opacity-40"
                >
                  Completar con esperados
                </button>
              )}
            </div>

            <p className="mb-4 text-sm text-slate-500">
              Contá únicamente el stock vendible
              que vuelve. Las devoluciones quedan
              en cuarentena. El botón de completar
              es una ayuda: no sustituye el recuento físico.
            </p>

            {stockInconsistente && (
              <p
                role="alert"
                className="mb-4 rounded-xl bg-red-50 p-4 text-sm text-red-800"
              >
                Se detectó stock esperado negativo.
                Revisá el historial de ventas y movimientos.
              </p>
            )}

            <div className="space-y-4">
              {filasMercaderia.map(
                (fila) => (
                  <div
                    key={fila.productoId}
                    className="rounded-xl border border-slate-200 p-4"
                  >
                    <h3 className="font-semibold text-slate-900">
                      {fila.nombreProducto}
                    </h3>

                    <div className="mt-3 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
                      <div>
                        <p className="text-slate-500">
                          Cargado
                        </p>
                        <strong>
                          {fila.cantidad}{" "}
                          {unidades[
                            fila.unidadMedida
                          ]}
                        </strong>
                      </div>

                      <div>
                        <p className="text-slate-500">
                          Vendido
                        </p>
                        <strong>
                          {fila.vendido}{" "}
                          {unidades[
                            fila.unidadMedida
                          ]}
                        </strong>
                      </div>

                      <div>
                        <p className="text-slate-500">
                          Mermas / cambios
                        </p>
                        <strong>
                          {redondear(
                            fila.merma +
                              fila.reemplazos
                          )}{" "}
                          {unidades[
                            fila.unidadMedida
                          ]}
                        </strong>
                      </div>

                      <div>
                        <p className="text-slate-500">
                          Esperado
                        </p>
                        <strong>
                          {fila.esperado}{" "}
                          {unidades[
                            fila.unidadMedida
                          ]}
                        </strong>
                      </div>
                    </div>

                    <div className="mt-4 flex flex-wrap items-end justify-between gap-3 border-t border-slate-100 pt-4">
                      <label className="space-y-1 text-sm font-medium">
                        <span>
                          Stock físico contado *
                        </span>

                        <input
                          type="number"
                          min="0"
                          step={
                            fila.unidadMedida ===
                            "kg"
                              ? "0.001"
                              : "1"
                          }
                          value={
                            conteos[
                              String(
                                fila.productoId
                              )
                            ] ?? ""
                          }
                          disabled={
                            jornada.estado ===
                            "cerrada"
                          }
                          onChange={(e) =>
                            setConteos(
                              (actual) => ({
                                ...actual,
                                [String(
                                  fila.productoId
                                )]:
                                  e.target.value,
                              })
                            )
                          }
                          className="block min-h-12 w-36 rounded-lg border border-slate-300 p-3 disabled:bg-slate-100"
                          placeholder="Ej: 45"
                        />
                      </label>

                      <div
                        className="text-right text-sm"
                        aria-live="polite"
                      >
                        <p className="text-slate-500">
                          Diferencia
                        </p>

                        {fila.diferencia ===
                        null ? (
                          <span className="text-slate-500">
                            Sin contar
                          </span>
                        ) : (
                          <strong
                            className={
                              fila.diferencia ===
                              0
                                ? "text-green-700"
                                : fila.diferencia >
                                    0
                                  ? "text-amber-700"
                                  : "text-red-700"
                            }
                          >
                            {fila.diferencia >
                            0
                              ? "+"
                              : ""}
                            {fila.diferencia}{" "}
                            {
                              unidades[
                                fila.unidadMedida
                              ]
                            }{" "}
                            ·{" "}
                            {fila.diferencia ===
                            0
                              ? "Exacto"
                              : fila.diferencia >
                                  0
                                ? "Sobrante"
                                : "Faltante"}
                          </strong>
                        )}
                      </div>
                    </div>

                    {fila.contado !==
                      null && (
                      <p className="mt-3 rounded-lg bg-slate-50 p-2 text-xs text-slate-600">
                        Cálculo:{" "}
                        {fila.contado}{" "}
                        contados −{" "}
                        {fila.esperado}{" "}
                        esperados ={" "}
                        <strong>
                          {fila.diferencia}{" "}
                          {
                            unidades[
                              fila.unidadMedida
                            ]
                          }
                        </strong>
                      </p>
                    )}
                  </div>
                )
              )}
            </div>

            <div className="mt-5 rounded-xl bg-amber-50 p-4">
              <h3 className="font-semibold text-amber-900">
                Productos devueltos en cuarentena
              </h3>

              {productosCuarentena.length ===
              0 ? (
                <p className="mt-2 text-sm text-amber-800">
                  No hay devoluciones registradas.
                </p>
              ) : (
                <div className="mt-3 space-y-2">
                  {productosCuarentena.map(
                    (producto) => (
                      <div
                        key={
                          producto.productoId
                        }
                        className="flex justify-between gap-3 text-sm text-amber-900"
                      >
                        <span>
                          {producto.nombre}
                        </span>
                        <strong>
                          {producto.cantidad}{" "}
                          {producto.unidad}
                        </strong>
                      </div>
                    )
                  )}
                </div>
              )}

              <p className="mt-3 text-xs text-amber-800">
                La mercadería devuelta no aumenta
                el stock vendible automáticamente.
              </p>
            </div>
          </section>

          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <h2 className="mb-5 text-xl font-bold">
              2. Rendición de caja
            </h2>

            <p className="mb-4 text-sm text-slate-500">
              Ventas registradas:{" "}
              <strong>
                {resumenCaja.cantidadVentas}
              </strong>
              {" · "}
              Cobros de deuda registrados
              en la jornada:{" "}
              <strong>
                {resumenCaja.cantidadCobros}
              </strong>
              .
            </p>

            <div className="grid gap-3 sm:grid-cols-2">
              {[
                {
                  titulo:
                    "Ventas en efectivo",
                  valor:
                    resumenCaja.ventasEfectivo,
                },
                {
                  titulo:
                    "Cobros de deuda en efectivo",
                  valor:
                    resumenCaja.cobrosEfectivo,
                },
                {
                  titulo:
                    "Efectivo esperado a rendir",
                  valor:
                    resumenCaja.efectivo,
                },
                {
                  titulo:
                    "Ventas por transferencia",
                  valor:
                    resumenCaja.ventasTransferencia,
                },
                {
                  titulo:
                    "Cobros de deuda por transferencia",
                  valor:
                    resumenCaja.cobrosTransferencia,
                },
                {
                  titulo:
                    "Transferencias informadas",
                  valor:
                    resumenCaja.transferencias,
                },
                {
                  titulo:
                    "Ventas a cuenta corriente",
                  valor:
                    resumenCaja.cuentaCorriente,
                },
                {
                  titulo:
                    "Total vendido (sin cobros anteriores)",
                  valor:
                    resumenCaja.totalVendido,
                },
              ].map((dato) => (
                <div
                  key={dato.titulo}
                  className="rounded-xl bg-slate-50 p-4"
                >
                  <p className="text-sm text-slate-500">
                    {dato.titulo}
                  </p>
                  <p className="mt-1 text-xl font-bold">
                    {moneda(dato.valor)}
                  </p>
                </div>
              ))}
            </div>

            <label className="mt-5 block space-y-2">
              <span className="text-sm font-semibold">
                Efectivo entregado por el repartidor *
              </span>

              <input
                type="number"
                min="0"
                step="0.01"
                value={efectivoEntregado}
                disabled={
                  jornada.estado === "cerrada"
                }
                onChange={(e) =>
                  setEfectivoEntregado(
                    e.target.value
                  )
                }
                className="min-h-14 w-full rounded-xl border border-slate-300 p-3 text-lg disabled:bg-slate-100"
                placeholder="0.00"
              />
            </label>

            {diferenciaEfectivo !==
              null && (
              <div className="mt-4 flex items-center justify-between rounded-xl bg-slate-50 p-4">
                <span className="font-medium">
                  Diferencia de efectivo
                </span>

                <strong
                  className={
                    diferenciaEfectivo ===
                    0
                      ? "text-green-700"
                      : diferenciaEfectivo >
                          0
                        ? "text-amber-700"
                        : "text-red-700"
                  }
                >
                  {diferenciaEfectivo >
                  0
                    ? "+"
                    : ""}
                  {moneda(
                    diferenciaEfectivo
                  )}
                  {diferenciaEfectivo >
                  0
                    ? " · Sobrante"
                    : diferenciaEfectivo <
                        0
                      ? " · Faltante"
                      : " · Exacto"}
                </strong>
              </div>
            )}

            <p className="mt-4 text-sm text-slate-500">
              El efectivo esperado suma ventas
              en efectivo y cobros de deuda en
              efectivo asociados a esta jornada.
              Las transferencias son importes
              informados, no operaciones bancarias
              conciliadas. Las ventas fiadas no
              se consideran efectivo.
            </p>
          </section>

          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <h2 className="mb-4 text-xl font-bold">
              3. Confirmación del cierre
            </h2>

            <label className="block space-y-2">
              <span className="text-sm font-semibold">
                Observaciones
                {tieneDiferencias
                  ? " *"
                  : ""}
              </span>

              <textarea
                rows={4}
                disabled={
                  jornada.estado === "cerrada"
                }
                value={observaciones}
                onChange={(e) =>
                  setObservaciones(
                    e.target.value
                  )
                }
                placeholder="Explicá cualquier diferencia de stock o dinero..."
                className="w-full rounded-xl border border-slate-300 p-3 disabled:bg-slate-100"
              />
            </label>

            {jornada.estado ===
            "cerrada" ? (
              <div className="mt-5 flex items-center gap-2 rounded-xl bg-green-50 p-4 text-green-800">
                <CheckCircle2 size={22} />
                Jornada cerrada. Rendición guardada.
              </div>
            ) : (
              <button
                type="button"
                onClick={
                  confirmarCierre
                }
                disabled={
                  stockInconsistente
                }
                className="mt-5 min-h-14 w-full rounded-xl bg-green-600 px-5 font-bold text-white hover:bg-green-700 disabled:cursor-not-allowed disabled:opacity-40"
              >
                Confirmar cierre de jornada
              </button>
            )}
          </section>
        </>
      )}

      <p className="text-xs text-slate-500">
        Prototipo local: el cierre no genera
        aún movimientos reales de depósito
        ni conciliación bancaria.
      </p>
    </div>
  );
}
