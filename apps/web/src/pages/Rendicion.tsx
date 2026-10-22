
import { useMemo, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  ClipboardCheck,
  Truck,
} from "lucide-react";

import { useJornadas } from "../hooks/useJornadas";
import { useCamiones } from "../hooks/useCamiones";
import { leerVentas, useVentas } from "../hooks/useVentas";
import {
  leerMovimientosDiscriminado,
  useMovimientos,
} from "../hooks/useMovimientos";
import {
  leerCobrosDiscriminado,
  useCobros,
} from "../hooks/useCobros";
import {
  acumularCuarentena,
  bloqueaRendicion,
  calcularFilasMercaderia,
  calcularResumenCaja,
  conteoDesdeEntrada,
  leerCantidad,
  type EntradaConteo,
} from "./rendicion_calculos";
import { entrada_desde_cantidad, cantidad_a_texto } from "../domain/retornos";
import {
  NO_DISPONIBLE,
  disponibilidadRendicion,
} from "./avisosStorage";
import AvisoStorageOperativo from "../components/AvisoStorageOperativo";
import { estadoStorageOperativo } from "./estadoStorageOperativo";

const conteoInicial: EntradaConteo = { texto: "", media: false };

// Presentación de una cantidad canónica; "—" si no pudo calcularse.
const textoCantidad = (
  unidad: "unidad" | "pieza",
  cantidad: number | null
) => (cantidad === null ? "—" : cantidad_a_texto(unidad, cantidad));

const moneda = (cantidad: number) =>
  new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
  }).format(cantidad);

// Aviso cuando la mercadería no se puede conciliar por alguno de los dos
// motivos reales del estado `inconsistente`: las salidas superan lo cargado o
// hay cantidades fuera del dominio canónico (no enteras / negativas). El bloqueo
// lo decide `bloqueaRendicion`; esto es solo el texto que ve el usuario.
const MENSAJE_INCONSISTENCIA_MERCADERIA =
  "Hay una inconsistencia de mercadería: las salidas superan lo cargado o existen cantidades inválidas. Revisá los datos antes de cerrar.";

export default function Rendicion() {
  const {
    jornadas,
    cerrarJornada,
    estadoLectura: estadoJornadas,
  } = useJornadas();
  const { camiones, estadoLectura: estadoCamiones } = useCamiones();
  const { ventas, estadoLectura: estadoVentas } = useVentas();
  const { movimientos, estadoLectura: estadoMovimientos } = useMovimientos();
  const { cobros, estadoLectura: estadoCobros } = useCobros();

  // Un ledger corrupto NO equivale a ausencia: cada cálculo dependiente se
  // marca no disponible y la rendición no se cierra.
  const disponibilidad = disponibilidadRendicion(
    estadoVentas,
    estadoCobros,
    estadoMovimientos
  );
  const estadoOperacion = estadoStorageOperativo({
    jornadas: estadoJornadas,
    camiones: estadoCamiones,
  });

  const [jornadaId, setJornadaId] = useState("");
  // Entrada de UI por producto; solo se persiste la cantidad canónica.
  const [conteos, setConteos] = useState<
    Record<string, EntradaConteo>
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
  const resumenCaja = useMemo(
    () => calcularResumenCaja(jornadaId, ventas, cobros),
    [ventas, cobros, jornadaId]
  );

  const filasMercaderia = useMemo(() => {
    return calcularFilasMercaderia(
      jornada,
      ventas,
      movimientos,
      conteos,
      {
        mercaderiaDisponible: disponibilidad.mercaderiaDisponible,
        ventasDisponibles: disponibilidad.ventasDisponibles,
        movimientosDisponibles: disponibilidad.movimientosDisponibles,
      }
    );
  }, [
    jornada,
    ventas,
    movimientos,
    conteos,
    disponibilidad.mercaderiaDisponible,
    disponibilidad.movimientosDisponibles,
    disponibilidad.ventasDisponibles,
  ]);

  const productosCuarentena = useMemo(
    () => acumularCuarentena(jornadaId, movimientos),
    [movimientos, jornadaId]
  );

  const efectivoContado = leerCantidad(
    efectivoEntregado
  );

  const diferenciaEfectivo =
    efectivoContado === null || !disponibilidad.cajaDisponible
      ? null
      : Math.round(
          (efectivoContado - resumenCaja.efectivo) *
            100
        ) / 100;

  const stockInconsistente = filasMercaderia.some(
    (fila) => fila.estado === "inconsistente"
  );

  const hayUnidadNoSoportada = filasMercaderia.some(
    (fila) => fila.estado === "no_soportada"
  );

  const rendicionBloqueada =
    bloqueaRendicion(filasMercaderia);

  const tieneDiferencias =
    filasMercaderia.some(
      (fila) =>
        fila.diferencia !== null && fila.diferencia !== 0
    ) ||
    (diferenciaEfectivo !== null &&
      Math.abs(diferenciaEfectivo) > 0.009);

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
      // Los conteos guardados ya son canónicos: se reconstruye piezas + media.
      setConteos(
        Object.fromEntries(
          elegida.items.flatMap((item) => {
            const entrada = entrada_desde_cantidad(
              item.unidadMedida,
              elegida.cierre!.conteos[String(item.productoId)]
            );
            return entrada
              ? [[String(item.productoId), entrada] as const]
              : [];
          })
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
      rendicionBloqueada ||
      !disponibilidad.mercaderiaDisponible
    ) {
      return;
    }

    setConteos(
      Object.fromEntries(
        filasMercaderia.flatMap((fila) => {
          const entrada =
            fila.esperado === null
              ? null
              : entrada_desde_cantidad(fila.unidadMedida, fila.esperado);
          return entrada
            ? [[String(fila.productoId), entrada] as const]
            : [];
        })
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
    if (estadoOperacion.bloqueado) return;

    if (
      !jornada ||
      jornada.estado !== "abierta"
    ) {
      setError(
        "Seleccioná una jornada abierta."
      );
      return;
    }

    if (!disponibilidad.cierreDisponible) {
      setError(disponibilidad.avisos.join(" "));
      return;
    }

    const lecturaVentas = leerVentas();
    if (!lecturaVentas.ok) {
      setError(`No se puede cerrar: ${lecturaVentas.error}`);
      return;
    }

    const lecturaCobros = leerCobrosDiscriminado();
    if (!lecturaCobros.ok) {
      setError(`No se puede cerrar: ${lecturaCobros.error}`);
      return;
    }

    const lecturaMovimientos = leerMovimientosDiscriminado();
    if (!lecturaMovimientos.ok) {
      setError(`No se puede cerrar: ${lecturaMovimientos.error}`);
      return;
    }

    const disponibilidadActual = disponibilidadRendicion(
      lecturaVentas.estado,
      lecturaCobros.estado,
      lecturaMovimientos.estado
    );
    const filasMercaderiaActuales = calcularFilasMercaderia(
      jornada,
      lecturaVentas.ventas,
      lecturaMovimientos.movimientos,
      conteos,
      disponibilidadActual
    );
    const resumenCajaActual = calcularResumenCaja(
      jornada.id,
      lecturaVentas.ventas,
      lecturaCobros.cobros
    );

    const stockInconsistenteActual = filasMercaderiaActuales.some(
      (fila) => fila.estado === "inconsistente"
    );
    const hayUnidadNoSoportadaActual = filasMercaderiaActuales.some(
      (fila) => fila.estado === "no_soportada"
    );

    if (stockInconsistenteActual) {
      setError(MENSAJE_INCONSISTENCIA_MERCADERIA);
      return;
    }

    if (hayUnidadNoSoportadaActual) {
      setError(
        "Hay productos con una unidad no soportada. Revisá la unidad de esos productos antes de cerrar."
      );
      return;
    }

    const conteosFinales: Record<
      string,
      number
    > = {};

    for (const fila of filasMercaderiaActuales) {
      const valor = conteoDesdeEntrada(
        fila.unidadMedida,
        conteos[String(fila.productoId)]
      );

      if (valor === null) {
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

    const diferenciaEfectivoActual = Math.round(
      (efectivoContado - resumenCajaActual.efectivo) * 100
    ) / 100;
    const tieneDiferenciasActuales =
      filasMercaderiaActuales.some(
        (fila) => fila.diferencia !== null && fila.diferencia !== 0
      ) || Math.abs(diferenciaEfectivoActual) > 0.009;

    if (tieneDiferenciasActuales && !observaciones.trim()) {
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
      efectivoEsperado: resumenCajaActual.efectivo,
      transferenciasInformadas:
        resumenCajaActual.transferencias,
      ventasCuentaCorriente:
        resumenCajaActual.cuentaCorriente,
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

      <AvisoStorageOperativo avisos={estadoOperacion.avisos} />

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
          {disponibilidad.avisos.map((aviso) => (
            <div
              key={aviso}
              role="alert"
              className="flex items-start gap-2 rounded-xl bg-red-50 p-4 text-sm font-medium text-red-800"
            >
              <AlertTriangle size={18} className="mt-0.5 shrink-0" />
              <span>
                <strong>Datos dañados: </strong>
                {aviso}
              </span>
            </div>
          ))}

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
                  disabled={
                    rendicionBloqueada ||
                    !disponibilidad.mercaderiaDisponible
                  }
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

            {stockInconsistente && !disponibilidad.avisos.length && (
              <p
                role="alert"
                className="mb-4 rounded-xl bg-red-50 p-4 text-sm text-red-800"
              >
                {MENSAJE_INCONSISTENCIA_MERCADERIA}
              </p>
            )}

            {hayUnidadNoSoportada && (
              <p
                role="alert"
                className="mb-4 rounded-xl bg-red-50 p-4 text-sm text-red-800"
              >
                Hay productos con una unidad que el
                sistema no soporta. El dominio
                aprobado solo admite unidades y
                piezas (media pieza): no existe venta
                por kilogramo. Revisá esos productos
                antes de rendir.
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

                    {fila.estado ===
                    "no_soportada" ? (
                      <p className="mt-2 rounded-lg bg-red-50 p-3 text-sm text-red-800">
                        Unidad no soportada por el
                        sistema. Esta fila no se
                        puede conciliar ni cerrar.
                      </p>
                    ) : (
                      <>
                        <div className="mt-3 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
                          <div>
                            <p className="text-slate-500">
                              Cargado
                            </p>
                            <strong>
                              {textoCantidad(
                                fila.unidadMedida,
                                fila.cargado
                              )}
                            </strong>
                          </div>

                          <div>
                            <p className="text-slate-500">
                              Vendido
                            </p>
                            <strong>
                              {fila.vendidoDisponible
                                ? textoCantidad(
                                    fila.unidadMedida,
                                    fila.vendido
                                  )
                                : NO_DISPONIBLE}
                            </strong>
                          </div>

                          <div>
                            <p className="text-slate-500">
                              Mermas / cambios
                            </p>
                            <strong>
                              {fila.movimientosDisponibles
                                ? textoCantidad(
                                    fila.unidadMedida,
                                    fila.mermaYCambios
                                  )
                                : NO_DISPONIBLE}
                            </strong>
                          </div>

                          <div>
                            <p className="text-slate-500">
                              Esperado
                            </p>
                            <strong>
                              {disponibilidad.mercaderiaDisponible
                                ? textoCantidad(
                                    fila.unidadMedida,
                                    fila.esperado
                                  )
                                : NO_DISPONIBLE}
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
                              step="1"
                              value={
                                (
                                  conteos[
                                    String(fila.productoId)
                                  ] ?? conteoInicial
                                ).texto
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
                                    )]: {
                                      texto:
                                        e.target.value,
                                      media: (
                                        actual[
                                          String(
                                            fila.productoId
                                          )
                                        ] ?? conteoInicial
                                      ).media,
                                    },
                                  })
                                )
                              }
                              className="block min-h-12 w-36 rounded-lg border border-slate-300 p-3 disabled:bg-slate-100"
                              placeholder={
                                fila.unidadMedida === "pieza"
                                  ? "Piezas enteras"
                                  : "Ej: 45"
                              }
                              aria-label={`Stock físico contado de ${fila.nombreProducto}`}
                            />

                            {fila.unidadMedida ===
                              "pieza" && (
                              <span className="mt-2 flex items-center gap-2 text-sm font-normal">
                                <input
                                  type="checkbox"
                                  checked={
                                    (
                                      conteos[
                                        String(
                                          fila.productoId
                                        )
                                      ] ?? conteoInicial
                                    ).media
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
                                        )]: {
                                          texto: (
                                            actual[
                                              String(
                                                fila.productoId
                                              )
                                            ] ??
                                            conteoInicial
                                          ).texto,
                                          media:
                                            e.target
                                              .checked,
                                        },
                                      })
                                    )
                                  }
                                  className="h-4 w-4 rounded border-slate-300"
                                  aria-label={`Media pieza contada de ${fila.nombreProducto}`}
                                />
                                <span>Media pieza</span>
                                {fila.contado !== null && (
                                  <span className="text-slate-600">
                                    ={" "}
                                    {textoCantidad(
                                      "pieza",
                                      fila.contado
                                    )}
                                  </span>
                                )}
                              </span>
                            )}
                          </label>

                          <div
                            className="text-right text-sm"
                            aria-live="polite"
                          >
                            <p className="text-slate-500">
                              Diferencia
                            </p>

                            {!disponibilidad.mercaderiaDisponible ? (
                              <span className="text-slate-500">
                                {NO_DISPONIBLE}
                              </span>
                            ) : fila.diferencia === null ? (
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
                                  : fila.diferencia < 0
                                    ? "−"
                                    : ""}
                                {textoCantidad(
                                  fila.unidadMedida,
                                  Math.abs(fila.diferencia)
                                )}{" "}
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

                        {disponibilidad.mercaderiaDisponible &&
                          fila.contado !==
                          null &&
                          fila.diferencia !==
                            null && (
                          <p className="mt-3 rounded-lg bg-slate-50 p-2 text-xs text-slate-600">
                            Cálculo:{" "}
                            {textoCantidad(
                              fila.unidadMedida,
                              fila.contado
                            )}{" "}
                            contados −{" "}
                            {textoCantidad(
                              fila.unidadMedida,
                              fila.esperado
                            )}{" "}
                            esperados ={" "}
                            <strong>
                              {fila.diferencia}{" "}
                              {fila.unidadMedida === "pieza"
                                ? "medias piezas"
                                : "un."}
                            </strong>
                          </p>
                        )}
                      </>
                    )}
                  </div>
                )
              )}
            </div>

            <div className="mt-5 rounded-xl bg-amber-50 p-4">
              <h3 className="font-semibold text-amber-900">
                Productos devueltos en cuarentena
              </h3>

              {!disponibilidad.movimientosDisponibles ? (
                <p className="mt-2 text-sm font-semibold text-amber-900">
                  {NO_DISPONIBLE}
                </p>
              ) : productosCuarentena.length ===
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
                          {producto.cantidad === null
                            ? "No calculable"
                            : cantidad_a_texto(
                                producto.unidadMedida,
                                producto.cantidad
                              )}
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
                {estadoVentas === "corrupto"
                  ? NO_DISPONIBLE
                  : resumenCaja.cantidadVentas}
              </strong>
              {" · "}
              Cobros de deuda registrados
              en la jornada:{" "}
              <strong>
                {estadoCobros === "corrupto"
                  ? NO_DISPONIBLE
                  : resumenCaja.cantidadCobros}
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
                    {disponibilidad.cajaDisponible
                      ? moneda(dato.valor)
                      : NO_DISPONIBLE}
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
                  rendicionBloqueada ||
                  !disponibilidad.cierreDisponible ||
                  estadoOperacion.bloqueado
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
