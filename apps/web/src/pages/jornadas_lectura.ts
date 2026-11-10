// Controlador de la pantalla de jornadas (B-02b.1): SÓLO LECTURA, sin React.
//
// Usa únicamente la lectura de la capa B-02a (`leerPaginaJornadas` y
// `leerTodasLasJornadas`); el tipo del puerto no incluye `ejecutar`, así que
// esta pantalla no puede invocar RPC mutadoras ni escribir tablas.
//
// - La visibilidad (empresa, rol, vendedor asignado) la decide RLS en la base;
//   aquí no se filtra ni se asume nada sobre quién ve qué.
// - Una página NUNCA se presenta como el conjunto completo: la lista sólo es
//   completa cuando `siguiente === null`.
// - Sólo la lectura vigente puede publicar: un cambio de filtro, una
//   actualización manual o el desmontaje invalidan las respuestas tardías.
// - Ante un error en la primera lectura no se muestran datos viejos (falla
//   cerrado). Si falla una ampliación, se conserva lo ya leído y se informa.
// - Sin consistencia transaccional entre páginas (ver lib/jornadas.ts).
// - Nada se guarda en el navegador (sin localStorage, sessionStorage ni
//   IndexedDB).

import type {
  CursorJornadas,
  Jornada,
  PuertoJornadas,
} from "../lib/jornadas";

export type PuertoLecturaJornadas = Pick<
  PuertoJornadas,
  "leerPaginaJornadas" | "leerTodasLasJornadas"
>;

export type LecturaJornadas =
  | { estado: "cargando" }
  | { estado: "error"; error: string }
  | {
      estado: "listo";
      jornadas: Jornada[];
      // null = lista completa (fin comprobado por la capa de datos).
      siguiente: CursorJornadas | null;
      ampliando: "mas" | "todas" | null;
      errorAmpliacion: string | null;
    };

export interface EstadoPantallaJornadas {
  // Filtro aplicado en la consulta ('AAAA-MM-DD') o null = todas las fechas.
  fecha: string | null;
  lectura: LecturaJornadas;
  seleccionadaId: string | null;
}

export const ESTADO_INICIAL_JORNADAS: EstadoPantallaJornadas = {
  fecha: null,
  lectura: { estado: "cargando" },
  seleccionadaId: null,
};

export function crearControladorJornadas(
  puerto: PuertoLecturaJornadas,
  publicar: (estado: EstadoPantallaJornadas) => void
) {
  let estado: EstadoPantallaJornadas = ESTADO_INICIAL_JORNADAS;
  // Cada lectura nueva (o el desmontaje) incrementa la generación: una
  // respuesta de una generación anterior se descarta.
  let generacion = 0;
  let activo = true;

  function emitir(cambios: Partial<EstadoPantallaJornadas>) {
    estado = { ...estado, ...cambios };
    if (activo) publicar(estado);
  }

  async function leerPrimeraPagina(): Promise<void> {
    const mia = ++generacion;
    const fecha = estado.fecha;
    const r = await puerto.leerPaginaJornadas(
      fecha === null ? undefined : { fecha }
    );
    if (mia !== generacion) return;
    if (!r.ok) {
      emitir({ lectura: { estado: "error", error: r.error.mensaje } });
      return;
    }
    emitir({
      lectura: {
        estado: "listo",
        jornadas: r.datos.jornadas,
        siguiente: r.datos.siguiente,
        ampliando: null,
        errorAmpliacion: null,
      },
      // La selección sólo sobrevive si la fila sigue entre las leídas.
      seleccionadaId: r.datos.jornadas.some((j) => j.id === estado.seleccionadaId)
        ? estado.seleccionadaId
        : null,
    });
  }

  /** Arranque o re-arranque (p. ej. StrictMode): primera página del filtro actual. */
  function iniciar(): Promise<void> {
    activo = true;
    return leerPrimeraPagina();
  }

  /** Actualización manual: descarta lo leído y vuelve a la primera página. */
  function recargar(): Promise<void> {
    emitir({ lectura: { estado: "cargando" } });
    return leerPrimeraPagina();
  }

  function cambiarFecha(fecha: string | null): Promise<void> {
    if (fecha === estado.fecha) return Promise.resolve();
    emitir({ fecha, seleccionadaId: null, lectura: { estado: "cargando" } });
    return leerPrimeraPagina();
  }

  async function ampliar(modo: "mas" | "todas"): Promise<void> {
    const actual = estado.lectura;
    // Sin lista cargada, sin más filas o con otra ampliación en curso: nada.
    if (actual.estado !== "listo" || actual.siguiente === null) return;
    if (actual.ampliando !== null) return;
    const mia = generacion;
    const fecha = estado.fecha;
    const filtro = fecha === null ? undefined : { fecha };
    emitir({ lectura: { ...actual, ampliando: modo, errorAmpliacion: null } });

    if (modo === "mas") {
      const despues = actual.siguiente;
      const r = await puerto.leerPaginaJornadas({ ...filtro, despues });
      if (mia !== generacion) return;
      if (!r.ok) {
        emitir({
          lectura: { ...actual, ampliando: null, errorAmpliacion: r.error.mensaje },
        });
        return;
      }
      const vistos = new Set(actual.jornadas.map((j) => j.id));
      emitir({
        lectura: {
          estado: "listo",
          jornadas: [
            ...actual.jornadas,
            ...r.datos.jornadas.filter((j) => !vistos.has(j.id)),
          ],
          siguiente: r.datos.siguiente,
          ampliando: null,
          errorAmpliacion: null,
        },
      });
      return;
    }

    // "todas": relee desde el principio (o falla): nunca queda una lista parcial
    // presentada como completa.
    const r = await puerto.leerTodasLasJornadas(filtro);
    if (mia !== generacion) return;
    if (!r.ok) {
      emitir({
        lectura: { ...actual, ampliando: null, errorAmpliacion: r.error.mensaje },
      });
      return;
    }
    emitir({
      lectura: {
        estado: "listo",
        jornadas: r.datos,
        siguiente: null,
        ampliando: null,
        errorAmpliacion: null,
      },
      seleccionadaId: r.datos.some((j) => j.id === estado.seleccionadaId)
        ? estado.seleccionadaId
        : null,
    });
  }

  /** Sólo se puede seleccionar una jornada de las leídas, o limpiar con null. */
  function seleccionar(id: string | null): void {
    if (id === null) {
      emitir({ seleccionadaId: null });
      return;
    }
    const l = estado.lectura;
    if (l.estado === "listo" && l.jornadas.some((j) => j.id === id)) {
      emitir({ seleccionadaId: id });
    }
  }

  function detener(): void {
    activo = false;
    generacion += 1;
  }

  return {
    obtener: () => estado,
    iniciar,
    recargar,
    cambiarFecha,
    cargarMas: () => ampliar("mas"),
    cargarTodas: () => ampliar("todas"),
    seleccionar,
    detener,
  };
}

export type ControladorJornadas = ReturnType<typeof crearControladorJornadas>;
