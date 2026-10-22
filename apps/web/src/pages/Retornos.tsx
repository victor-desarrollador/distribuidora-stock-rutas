
import { useMemo, useState } from "react";
import {
  Warehouse,
  Truck,
  CheckCircle2,
  AlertTriangle,
  PackageCheck,
} from "lucide-react";

import { useJornadas, leerJornadas } from "../hooks/useJornadas";
import { useCamiones } from "../hooks/useCamiones";
import { useRetornos } from "../hooks/useRetornos";

import type {
  ItemRetorno,
  RetornoDeposito,
} from "../data/mockRetornos";
import { maximo_piezas_segun_disponible } from "../domain/cantidades";
import {
  cantidad_a_texto,
  cantidad_aprobada_desde_entrada,
  cierre_sin_cambios,
  contado_desde_cierre,
  entrada_desde_cantidad,
  entrada_vacia,
  media_aprobable,
  pendiente_retorno,
  type EntradaRetorno,
} from "../domain/retornos";
import AvisoStorageOperativo from "../components/AvisoStorageOperativo";
import { estadoStorageOperativo } from "./estadoStorageOperativo";

const entradaInicial: EntradaRetorno = { texto: "", media: false };

export default function Retornos() {
  const { jornadas, estadoLectura: estadoJornadas } = useJornadas();
  const { camiones, estadoLectura: estadoCamiones } = useCamiones();
  const {
    retornos,
    registrarRetorno,
    estadoLectura: estadoRetornos,
  } = useRetornos();
  const estadoOperacion = estadoStorageOperativo({
    jornadas: estadoJornadas,
    camiones: estadoCamiones,
    retornos: estadoRetornos,
  });

  const [jornadaId, setJornadaId] = useState("");
  const [responsable, setResponsable] = useState("");
  const [observaciones, setObservaciones] = useState("");

  // Entrada de UI por producto. Solo se persiste la cantidad canónica.
  const [aprobados, setAprobados] = useState<
    Record<string, EntradaRetorno>
  >({});

  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");

  const jornadasCerradas = useMemo(
    () =>
      jornadas.filter((j) => j.estado === "cerrada" && j.cierre),
    [jornadas]
  );

  // Referencia estable: evita invalidar en cada render el
  // useMemo `filas` que depende de `jornada`.
  const jornada = useMemo(
    () => jornadasCerradas.find((j) => j.id === jornadaId),
    [jornadasCerradas, jornadaId]
  );

  const retornoExistente = retornos.find(
    (r) => r.jornadaId === jornadaId
  );

  const camion = camiones.find(
    (c) => c.id === jornada?.camionId
  );

  const filas = useMemo(() => {
    if (!jornada?.cierre) return [];

    return jornada.items.map((item) => {
      // null: el conteo del cierre no es una cantidad canónica segura.
      const contado = contado_desde_cierre(
        jornada.cierre!.conteos[String(item.productoId)] ?? 0
      );

      const entrada =
        aprobados[String(item.productoId)] ?? entradaInicial;

      const aprobado =
        contado === null || entrada_vacia(entrada)
          ? null
          : cantidad_aprobada_desde_entrada(
              item.unidadMedida,
              entrada,
              contado
            );

      const pendiente =
        contado === null || aprobado === null
          ? null
          : pendiente_retorno(contado, aprobado);

      return {
        ...item,
        contado,
        entrada,
        aprobado,
        pendiente,
      };
    });
  }, [jornada, aprobados]);

  function seleccionarJornada(id: string) {
    setJornadaId(id);
    setResponsable("");
    setObservaciones("");
    setAprobados({});
    setMensaje("");
    setError("");

    // Si ya existe un retorno, mostramos
    // las cantidades que fueron aprobadas.
    const existente = retornos.find(
      (r) => r.jornadaId === id
    );

    if (existente) {
      setResponsable(existente.responsable);
      setObservaciones(existente.observaciones);

      setAprobados(
        Object.fromEntries(
          existente.items.flatMap((item) => {
            const entrada = entrada_desde_cantidad(
              item.unidadMedida,
              item.cantidadAprobada
            );
            return entrada
              ? [[String(item.productoId), entrada] as const]
              : [];
          })
        )
      );
    }
  }

  function completarConContado() {
    if (!jornada?.cierre || retornoExistente) return;

    // Reconstruye piezas + media desde la cantidad canónica contada.
    setAprobados(
      Object.fromEntries(
        jornada.items.flatMap((item) => {
          const contado = contado_desde_cierre(
            jornada.cierre!.conteos[String(item.productoId)] ?? 0
          );
          const entrada =
            contado === null
              ? null
              : entrada_desde_cantidad(item.unidadMedida, contado);
          return entrada
            ? [[String(item.productoId), entrada] as const]
            : [];
        })
      )
    );
  }

  function guardarRetorno() {
    setError("");
    setMensaje("");
    if (estadoOperacion.bloqueado) return;

    if (!jornada?.cierre) {
      setError("Seleccioná una jornada cerrada.");
      return;
    }

    if (retornoExistente) {
      setError("Esta jornada ya tiene un retorno.");
      return;
    }

    if (!responsable.trim()) {
      setError("Ingresá el responsable de la recepción.");
      return;
    }

    const items: ItemRetorno[] = [];

    for (const fila of filas) {
      if (fila.contado === null) {
        setError(
          `El conteo de ${fila.nombreProducto} no es una cantidad válida.`
        );
        return;
      }

      if (entrada_vacia(fila.entrada)) {
        setError(
          `Falta completar ${fila.nombreProducto}.`
        );
        return;
      }

      if (fila.aprobado === null) {
        setError(
          `Cantidad aprobada inválida: ${fila.nombreProducto}.`
        );
        return;
      }

      items.push({
        productoId: fila.productoId,
        nombreProducto: fila.nombreProducto,
        unidadMedida: fila.unidadMedida,
        cantidadContada: fila.contado,
        cantidadAprobada: fila.aprobado,
      });
    }

    const hayPendientes = items.some(
      (item) => item.cantidadAprobada < item.cantidadContada
    );

    if (hayPendientes && !observaciones.trim()) {
      setError(
        "Hay mercadería pendiente. Explicá el motivo en observaciones."
      );
      return;
    }

    // Consultamos nuevamente los datos guardados.
    const jornadaActual = leerJornadas().find(
      (j) => j.id === jornada.id
    );

    if (
      jornadaActual?.estado !== "cerrada" ||
      !jornadaActual.cierre
    ) {
      setError("La jornada ya no está disponible para retorno.");
      return;
    }

    for (const item of items) {
      const cantidadActual =
        jornadaActual.cierre.conteos[String(item.productoId)];

      if (!cierre_sin_cambios(cantidadActual, item.cantidadContada)) {
        setError(
          "El cierre cambió. Actualizá la pantalla antes de continuar."
        );
        return;
      }
    }

    const confirmado = window.confirm(
      "¿Confirmás la recepción de mercadería?\n\n" +
      "Solo las cantidades aprobadas volverán a estar " +
      "disponibles en el depósito simulado.\n\n" +
      "Esta recepción no podrá editarse desde esta pantalla."
    );

    if (!confirmado) return;

    const retorno: RetornoDeposito = {
      id: crypto.randomUUID(),
      jornadaId: jornada.id,
      camionId: jornada.camionId,
      fecha: new Date().toISOString(),
      responsable: responsable.trim(),
      observaciones: observaciones.trim(),
      items,
    };

    const resultado = registrarRetorno(retorno);

    if (resultado) {
      setError(resultado);
      return;
    }

    setMensaje("Retorno registrado correctamente.");
  }

  return (
    <div className="mx-auto max-w-5xl space-y-6 pb-12">
      <header>
        <p className="text-xs font-semibold uppercase text-blue-600">
          Administración · Depósito
        </p>

        <h1 className="mt-1 text-3xl font-bold text-slate-900">
          Retorno de mercadería
        </h1>

        <p className="mt-1 text-slate-500">
          Recepción de sobrantes de jornadas cerradas
        </p>
      </header>

      <AvisoStorageOperativo avisos={estadoOperacion.avisos} />

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

      <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <div className="mb-4 flex items-center gap-2">
          <Truck className="text-blue-600" />
          <h2 className="text-lg font-bold">
            Seleccionar jornada cerrada
          </h2>
        </div>

        <select
          value={jornadaId}
          onChange={(e) => seleccionarJornada(e.target.value)}
          className="min-h-14 w-full rounded-xl border border-slate-300 p-3"
        >
          <option value="">Seleccionar jornada</option>

          {jornadasCerradas.map((j) => {
            const c = camiones.find(
              (camion) => camion.id === j.camionId
            );

            const recibido = retornos.some(
              (r) => r.jornadaId === j.id
            );

            return (
              <option key={j.id} value={j.id}>
                {c?.nombre ?? "Camión"} · {j.chofer} ·{" "}
                {recibido ? "Recibida" : "Pendiente de recepción"}
              </option>
            );
          })}
        </select>

        {jornadasCerradas.length === 0 && (
          <p className="mt-3 text-sm text-amber-700">
            Todavía no hay jornadas cerradas.
            Primero realizá la rendición.
          </p>
        )}

        {jornada && (
          <div className="mt-4 rounded-xl bg-blue-50 p-4 text-sm text-blue-900">
            <strong>
              {camion?.nombre ?? "Camión"} · {jornada.chofer}
            </strong>
            <p className="mt-1">Zona: {jornada.zona}</p>
            <p>
              Estado:{" "}
              {retornoExistente
                ? "Recepción registrada"
                : "Pendiente de recepción"}
            </p>
          </div>
        )}
      </section>

      {jornada && (
        <>
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <Warehouse className="text-blue-600" />
                <h2 className="text-lg font-bold">
                  Mercadería recibida
                </h2>
              </div>

              {!retornoExistente && (
                <button
                  type="button"
                  onClick={completarConContado}
                  className="min-h-11 rounded-lg border border-blue-300 px-3 text-sm font-medium text-blue-700"
                >
                  Completar con conteos
                </button>
              )}
            </div>

            <p className="mb-4 text-sm text-slate-500">
              Indicá cuánto stock vendible fue recibido
              y aprobado para regresar al depósito.
              Las cantidades no aprobadas quedarán pendientes.
            </p>

            <div className="space-y-4">
              {filas.map((fila) => (
                <div
                  key={fila.productoId}
                  className="rounded-xl border border-slate-200 p-4"
                >
                  <h3 className="font-semibold">
                    {fila.nombreProducto}
                  </h3>

                  <div className="mt-3 grid grid-cols-2 gap-3 text-sm">
                    <div>
                      <p className="text-slate-500">
                        Vendible contado al cierre
                      </p>
                      <strong>
                        {fila.contado === null
                          ? "Conteo inválido"
                          : cantidad_a_texto(
                              fila.unidadMedida,
                              fila.contado
                            )}
                      </strong>
                    </div>

                    <div>
                      <p className="text-slate-500">
                        Pendiente de recepción
                      </p>
                      <strong className="text-amber-700">
                        {fila.pendiente === null
                          ? "—"
                          : cantidad_a_texto(
                              fila.unidadMedida,
                              fila.pendiente
                            )}
                      </strong>
                    </div>
                  </div>

                  <div className="mt-4 space-y-2">
                    <label className="block space-y-2">
                      <span className="text-sm font-medium">
                        Cantidad aprobada para depósito *
                        {fila.unidadMedida === "pieza"
                          ? " (piezas enteras)"
                          : ""}
                      </span>

                      <input
                        type="number"
                        min="0"
                        max={
                          fila.unidadMedida === "pieza"
                            ? maximo_piezas_segun_disponible(
                                fila.contado ?? 0,
                                fila.entrada.media
                              )
                            : (fila.contado ?? 0)
                        }
                        step="1"
                        disabled={
                          Boolean(retornoExistente) ||
                          fila.contado === null
                        }
                        value={fila.entrada.texto}
                        onChange={(e) =>
                          setAprobados((prev) => ({
                            ...prev,
                            [String(fila.productoId)]: {
                              texto: e.target.value,
                              media: fila.entrada.media,
                            },
                          }))
                        }
                        className="min-h-12 w-40 rounded-lg border border-slate-300 p-3 disabled:bg-slate-100"
                        placeholder="0"
                      />
                    </label>

                    {fila.unidadMedida === "pieza" && (
                      <label className="flex items-center gap-2 text-sm">
                        <input
                          type="checkbox"
                          checked={fila.entrada.media}
                          disabled={
                            Boolean(retornoExistente) ||
                            fila.contado === null ||
                            (!fila.entrada.media &&
                              !media_aprobable(
                                fila.contado,
                                fila.entrada.texto
                              ))
                          }
                          onChange={(e) =>
                            setAprobados((prev) => ({
                              ...prev,
                              [String(fila.productoId)]: {
                                texto: fila.entrada.texto,
                                media: e.target.checked,
                              },
                            }))
                          }
                          className="h-4 w-4 rounded border-slate-300"
                        />
                        <span>Media pieza</span>
                      </label>
                    )}

                    {fila.unidadMedida === "pieza" &&
                      fila.aprobado !== null && (
                        <p className="text-xs text-slate-600">
                          ={" "}
                          {cantidad_a_texto("pieza", fila.aprobado)}
                        </p>
                      )}
                  </div>
                </div>
              ))}
            </div>

            <div className="mt-5 rounded-xl bg-amber-50 p-4 text-sm text-amber-900">
              <strong>Mercadería en cuarentena:</strong>{" "}
              los productos devueltos por clientes y
              registrados en Movimientos no están incluidos
              en esta recepción de stock vendible.
            </div>
          </section>

          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <h2 className="mb-4 text-lg font-bold">
              Confirmación de recepción
            </h2>

            <label className="block space-y-2">
              <span className="text-sm font-medium">
                Responsable *
              </span>
              <input
                value={responsable}
                disabled={Boolean(retornoExistente)}
                onChange={(e) =>
                  setResponsable(e.target.value)
                }
                placeholder="Nombre del encargado"
                className="min-h-12 w-full rounded-lg border border-slate-300 p-3 disabled:bg-slate-100"
              />
            </label>

            <label className="mt-4 block space-y-2">
              <span className="text-sm font-medium">
                Observaciones
              </span>
              <textarea
                rows={3}
                value={observaciones}
                disabled={Boolean(retornoExistente)}
                onChange={(e) =>
                  setObservaciones(e.target.value)
                }
                placeholder="Mercadería pendiente, condiciones de recepción..."
                className="w-full rounded-lg border border-slate-300 p-3 disabled:bg-slate-100"
              />
            </label>

            {retornoExistente ? (
              <div className="mt-5 flex items-center gap-2 rounded-xl bg-green-50 p-4 font-medium text-green-800">
                <PackageCheck size={22} />
                Recepción registrada el{" "}
                {new Date(
                  retornoExistente.fecha
                ).toLocaleString("es-AR")}
              </div>
            ) : (
              <button
                type="button"
                onClick={guardarRetorno}
                disabled={estadoOperacion.bloqueado}
                className="mt-5 flex min-h-14 w-full items-center justify-center gap-2 rounded-xl bg-green-600 px-5 font-bold text-white hover:bg-green-700"
              >
                <PackageCheck size={22} />
                Confirmar recepción
              </button>
            )}
          </section>
        </>
      )}

      <p className="text-xs text-slate-500">
        Prototipo local: la recepción aprobada ajusta
        la disponibilidad simulada para futuras cargas.
        No genera movimientos de lotes ni validaciones
        sanitarias reales.
      </p>
    </div>
  );
}
