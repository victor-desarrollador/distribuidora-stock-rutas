import { describe, expect, it } from "vitest";

import type {
  CursorJornadas,
  EstadoJornada,
  Jornada,
  OpcionesLecturaJornadas,
  PaginaJornadas,
  ResultadoJornada,
} from "../lib/jornadas";
import {
  crearControladorJornadas,
  type EstadoPantallaJornadas,
  type PuertoLecturaJornadas,
} from "./jornadas_lectura";
import fuenteControlador from "./jornadas_lectura.ts?raw";
import fuenteHook from "../hooks/useJornadasLectura.ts?raw";
import fuentePantalla from "./Jornadas.tsx?raw";
import fuentePresentacion from "./jornadas_presentacion.ts?raw";
import fuenteVista from "./JornadasVista.tsx?raw";

const CAMION = "22222222-2222-4222-8222-222222222222";
const VEND = "33333333-3333-4333-8333-333333333333";
const DUENO = "66666666-6666-4666-8666-666666666666";
const OP = "99999999-9999-4999-8999-999999999999";

function jornada(n: number, fecha = "2026-11-10", estado: EstadoJornada = "abierta"): Jornada {
  return {
    id: `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`,
    fecha, camionId: CAMION, vendedorId: VEND, estado,
    abiertaPor: DUENO, operacionAperturaId: OP, creadoEn: "2026-11-10T08:00:00+00:00",
  };
}

const ok = <T,>(datos: T, intentos = 1): ResultadoJornada<T> => ({ ok: true, datos, intentos });
const mal = (mensaje = "No se pudieron leer las jornadas. Intentá de nuevo."): ResultadoJornada<never> => ({
  ok: false, intentos: 1, error: { codigo: null, mensaje, resultadoDesconocido: false },
});
const pagina = (jornadas: Jornada[], siguiente: CursorJornadas | null): ResultadoJornada<PaginaJornadas> =>
  ok({ jornadas, siguiente });
const cursorDe = (j: Jornada): CursorJornadas => ({ fecha: j.fecha, id: j.id });

interface Pendiente<T> { resolver: (r: ResultadoJornada<T>) => void }

/** Puerto falso cuyas respuestas se resuelven a mano (para controlar el orden). */
function puertoManual() {
  const paginas: Array<{ opciones: OpcionesLecturaJornadas | undefined } & Pendiente<PaginaJornadas>> = [];
  const todas: Array<{ filtro: { fecha?: string } | undefined } & Pendiente<Jornada[]>> = [];
  let ejecutadas = 0;
  const puerto = {
    leerPaginaJornadas(opciones?: OpcionesLecturaJornadas) {
      return new Promise<ResultadoJornada<PaginaJornadas>>((resolver) => paginas.push({ opciones, resolver }));
    },
    leerTodasLasJornadas(filtro?: { fecha?: string }) {
      return new Promise<ResultadoJornada<Jornada[]>>((resolver) => todas.push({ filtro, resolver }));
    },
    // No forma parte del tipo de la pantalla: si alguien lo llamara, se cuenta.
    ejecutar() {
      ejecutadas += 1;
      throw new Error("la pantalla de lectura no debe mutar");
    },
  };
  return { puerto: puerto as PuertoLecturaJornadas, paginas, todas, ejecutadas: () => ejecutadas };
}

function armar(puerto: PuertoLecturaJornadas) {
  const publicados: EstadoPantallaJornadas[] = [];
  const c = crearControladorJornadas(puerto, (e) => publicados.push(e));
  return { c, publicados, ultimo: () => publicados[publicados.length - 1] ?? c.obtener() };
}

const tick = () => new Promise((r) => setTimeout(r, 0));

function listo(e: EstadoPantallaJornadas) {
  if (e.lectura.estado !== "listo") throw new Error(`se esperaba listo, hay ${e.lectura.estado}`);
  return e.lectura;
}

describe("carga de jornadas", () => {
  it("la primera lectura pide la primera página sin filtro y publica la lista", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    expect(c.obtener().lectura.estado).toBe("cargando");
    const p = c.iniciar();
    expect(m.paginas).toHaveLength(1);
    expect(m.paginas[0].opciones).toBeUndefined();
    m.paginas[0].resolver(pagina([jornada(2), jornada(1)], null));
    await p;
    const l = listo(ultimo());
    expect(l.jornadas.map((j) => j.estado)).toEqual(["abierta", "abierta"]);
    expect(l.siguiente).toBeNull();
  });

  it("muestra cada estado real del backend sin alterarlo", async () => {
    const estados: EstadoJornada[] = ["abierta", "cargada", "en_reparto", "ventas_finalizadas", "regreso_contado", "cerrada"];
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const p = c.iniciar();
    m.paginas[0].resolver(pagina(estados.map((e, i) => jornada(i + 1, "2026-11-10", e)), null));
    await p;
    expect(listo(ultimo()).jornadas.map((j) => j.estado)).toEqual(estados);
  });

  it("lista vacía: estado listo sin filas ni continuación", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const p = c.iniciar();
    m.paginas[0].resolver(pagina([], null));
    await p;
    expect(listo(ultimo())).toMatchObject({ jornadas: [], siguiente: null });
  });

  it("error de lectura: mensaje seguro, sin datos, y recargar se recupera", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const p = c.iniciar();
    m.paginas[0].resolver(mal());
    await p;
    expect(ultimo().lectura).toEqual({ estado: "error", error: "No se pudieron leer las jornadas. Intentá de nuevo." });

    const r = c.recargar();
    expect(ultimo().lectura.estado).toBe("cargando");
    m.paginas[1].resolver(pagina([jornada(1)], null));
    await r;
    expect(listo(ultimo()).jornadas).toHaveLength(1);
  });

  it("la actualización manual descarta la lista anterior (no muestra datos viejos mientras lee)", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const p = c.iniciar();
    m.paginas[0].resolver(pagina([jornada(1)], null));
    await p;
    const r = c.recargar();
    expect(ultimo().lectura.estado).toBe("cargando");
    m.paginas[1].resolver(mal());
    await r;
    expect(ultimo().lectura.estado).toBe("error");
  });
});

describe("paginación y continuación", () => {
  async function conPrimeraPagina() {
    const m = puertoManual();
    const a = armar(m.puerto);
    const primera = [jornada(4), jornada(3)];
    const p = a.c.iniciar();
    m.paginas[0].resolver(pagina(primera, cursorDe(primera[1])));
    await p;
    return { m, ...a, primera };
  }

  it("una página con continuación no se presenta como completa", async () => {
    const { ultimo, primera } = await conPrimeraPagina();
    expect(listo(ultimo()).siguiente).toEqual(cursorDe(primera[1]));
  });

  it("cargar más agrega la página siguiente con el cursor y mantiene el filtro", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const p0 = c.cambiarFecha("2026-11-10");
    const primera = [jornada(4), jornada(3)];
    m.paginas[0].resolver(pagina(primera, cursorDe(primera[1])));
    await p0;

    const p = c.cargarMas();
    expect(listo(ultimo()).ampliando).toBe("mas");
    expect(m.paginas[1].opciones).toEqual({ fecha: "2026-11-10", despues: cursorDe(primera[1]) });
    m.paginas[1].resolver(pagina([jornada(2), jornada(1)], null));
    await p;
    const l = listo(ultimo());
    expect(l.jornadas.map((j) => j.id)).toEqual([4, 3, 2, 1].map((n) => jornada(n).id));
    expect(l.siguiente).toBeNull();
    expect(l.ampliando).toBeNull();
  });

  it("descarta repetidos por id al ampliar", async () => {
    const { m, c, ultimo, primera } = await conPrimeraPagina();
    const p = c.cargarMas();
    m.paginas[1].resolver(pagina([primera[1], jornada(2)], null));
    await p;
    expect(listo(ultimo()).jornadas).toHaveLength(3);
  });

  it("no lanza una segunda ampliación mientras hay una en curso, ni sin continuación", async () => {
    const { m, c } = await conPrimeraPagina();
    const p1 = c.cargarMas();
    void c.cargarMas();
    void c.cargarTodas();
    expect(m.paginas).toHaveLength(2);
    expect(m.todas).toHaveLength(0);
    m.paginas[1].resolver(pagina([jornada(1)], null));
    await p1;
    await c.cargarMas();
    await c.cargarTodas();
    expect(m.paginas).toHaveLength(2);
    expect(m.todas).toHaveLength(0);
  });

  it("cargar todas relee todo con el filtro y deja la lista completa", async () => {
    const { m, c, ultimo } = await conPrimeraPagina();
    const p = c.cargarTodas();
    expect(listo(ultimo()).ampliando).toBe("todas");
    expect(m.todas[0].filtro).toBeUndefined();
    const todas = [4, 3, 2, 1].map((n) => jornada(n));
    m.todas[0].resolver(ok(todas));
    await p;
    const l = listo(ultimo());
    expect(l.jornadas).toHaveLength(4);
    expect(l.siguiente).toBeNull();
  });

  it("error al cargar más: conserva lo leído, informa y permite reintentar", async () => {
    const { m, c, ultimo, primera } = await conPrimeraPagina();
    const p = c.cargarMas();
    m.paginas[1].resolver(mal());
    await p;
    let l = listo(ultimo());
    expect(l.jornadas).toHaveLength(primera.length);
    expect(l.siguiente).not.toBeNull();
    expect(l.errorAmpliacion).toBe("No se pudieron leer las jornadas. Intentá de nuevo.");
    expect(l.ampliando).toBeNull();

    const r = c.cargarMas();
    expect(listo(ultimo()).errorAmpliacion).toBeNull();
    m.paginas[2].resolver(pagina([jornada(1)], null));
    await r;
    l = listo(ultimo());
    expect(l.jornadas).toHaveLength(3);
    expect(l.errorAmpliacion).toBeNull();
  });

  it("error al cargar todas: conserva lo leído, sin marcarla completa", async () => {
    const { m, c, ultimo } = await conPrimeraPagina();
    const p = c.cargarTodas();
    m.todas[0].resolver(mal());
    await p;
    const l = listo(ultimo());
    expect(l.jornadas).toHaveLength(2);
    expect(l.siguiente).not.toBeNull();
    expect(l.errorAmpliacion).not.toBeNull();
  });
});

describe("filtros", () => {
  it("cambiar la fecha consulta con el filtro y reinicia lista y selección", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const p0 = c.iniciar();
    m.paginas[0].resolver(pagina([jornada(1)], null));
    await p0;
    c.seleccionar(jornada(1).id);

    const p = c.cambiarFecha("2026-11-11");
    expect(ultimo()).toMatchObject({ fecha: "2026-11-11", seleccionadaId: null, lectura: { estado: "cargando" } });
    expect(m.paginas[1].opciones).toEqual({ fecha: "2026-11-11" });
    m.paginas[1].resolver(pagina([jornada(5, "2026-11-11")], null));
    await p;
    expect(listo(ultimo()).jornadas.map((j) => j.fecha)).toEqual(["2026-11-11"]);
  });

  it("volver a «todas las fechas» consulta sin filtro; repetir la misma fecha no consulta", async () => {
    const m = puertoManual();
    const { c } = armar(m.puerto);
    const p = c.cambiarFecha("2026-11-11");
    m.paginas[0].resolver(pagina([], null));
    await p;
    await c.cambiarFecha("2026-11-11");
    expect(m.paginas).toHaveLength(1);
    const q = c.cambiarFecha(null);
    expect(m.paginas[1].opciones).toBeUndefined();
    m.paginas[1].resolver(pagina([], null));
    await q;
  });

  it("fecha vacía sin resultados: lista vacía con el filtro aplicado", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const p = c.cambiarFecha("2026-12-31");
    m.paginas[0].resolver(pagina([], null));
    await p;
    expect(ultimo().fecha).toBe("2026-12-31");
    expect(listo(ultimo()).jornadas).toEqual([]);
  });
});

describe("selección y detalle", () => {
  async function conLista() {
    const m = puertoManual();
    const a = armar(m.puerto);
    const p = a.c.iniciar();
    m.paginas[0].resolver(pagina([jornada(2), jornada(1)], null));
    await p;
    return { m, ...a };
  }

  it("selecciona una jornada leída, cambia y limpia", async () => {
    const { c, ultimo } = await conLista();
    c.seleccionar(jornada(2).id);
    expect(ultimo().seleccionadaId).toBe(jornada(2).id);
    c.seleccionar(jornada(1).id);
    expect(ultimo().seleccionadaId).toBe(jornada(1).id);
    c.seleccionar(null);
    expect(ultimo().seleccionadaId).toBeNull();
  });

  it("ignora una jornada que no está entre las leídas", async () => {
    const { c, ultimo } = await conLista();
    c.seleccionar(jornada(99).id);
    expect(ultimo().seleccionadaId).toBeNull();
  });

  it("al actualizar, la selección sobrevive si la fila sigue y se limpia si ya no está", async () => {
    const { m, c, ultimo } = await conLista();
    c.seleccionar(jornada(2).id);
    const r1 = c.recargar();
    m.paginas[1].resolver(pagina([jornada(2), jornada(1)], null));
    await r1;
    expect(ultimo().seleccionadaId).toBe(jornada(2).id);
    const r2 = c.recargar();
    m.paginas[2].resolver(pagina([jornada(1)], null));
    await r2;
    expect(ultimo().seleccionadaId).toBeNull();
  });
});

describe("respuestas tardías y cambios de filtro", () => {
  it("una respuesta vieja que llega DESPUÉS de la nueva no la pisa", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const a = c.cambiarFecha("2026-11-10");
    const b = c.cambiarFecha("2026-11-11");
    m.paginas[1].resolver(pagina([jornada(5, "2026-11-11")], null));
    await b;
    m.paginas[0].resolver(pagina([jornada(1, "2026-11-10")], null));
    await a;
    expect(ultimo().fecha).toBe("2026-11-11");
    expect(listo(ultimo()).jornadas.map((j) => j.fecha)).toEqual(["2026-11-11"]);
  });

  it("una respuesta vieja que llega ANTES tampoco queda publicada", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const a = c.cambiarFecha("2026-11-10");
    const b = c.cambiarFecha("2026-11-11");
    m.paginas[0].resolver(pagina([jornada(1, "2026-11-10")], null));
    await a;
    expect(ultimo().lectura.estado).toBe("cargando");
    m.paginas[1].resolver(pagina([jornada(5, "2026-11-11")], null));
    await b;
    expect(listo(ultimo()).jornadas[0].fecha).toBe("2026-11-11");
  });

  it("un error tardío de una consulta vieja no pisa la lista vigente", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const a = c.cambiarFecha("2026-11-10");
    const b = c.cambiarFecha("2026-11-11");
    m.paginas[1].resolver(pagina([jornada(5, "2026-11-11")], null));
    await b;
    m.paginas[0].resolver(mal());
    await a;
    expect(ultimo().lectura.estado).toBe("listo");
  });

  it("«cargar más» pendiente se descarta si cambia el filtro", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const p0 = c.iniciar();
    const primera = [jornada(4), jornada(3)];
    m.paginas[0].resolver(pagina(primera, cursorDe(primera[1])));
    await p0;
    const mas = c.cargarMas();
    const f = c.cambiarFecha("2026-11-11");
    m.paginas[2].resolver(pagina([jornada(7, "2026-11-11")], null));
    await f;
    m.paginas[1].resolver(pagina([jornada(2)], null));
    await mas;
    expect(listo(ultimo()).jornadas.map((j) => j.fecha)).toEqual(["2026-11-11"]);
  });

  it("«cargar todas» pendiente se descarta si se actualiza", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const p0 = c.iniciar();
    m.paginas[0].resolver(pagina([jornada(2)], cursorDe(jornada(2))));
    await p0;
    const todas = c.cargarTodas();
    const r = c.recargar();
    m.paginas[1].resolver(pagina([jornada(9)], null));
    await r;
    m.todas[0].resolver(ok([jornada(1), jornada(2)]));
    await todas;
    expect(listo(ultimo()).jornadas.map((j) => j.id)).toEqual([jornada(9).id]);
  });

  it("después de detener (desmontaje) ninguna respuesta publica", async () => {
    const m = puertoManual();
    const { c, publicados } = armar(m.puerto);
    const p = c.iniciar();
    c.detener();
    m.paginas[0].resolver(pagina([jornada(1)], null));
    await p;
    expect(publicados).toHaveLength(0);
  });

  it("un reinicio (StrictMode) vuelve a leer y sólo cuenta la última lectura", async () => {
    const m = puertoManual();
    const { c, ultimo } = armar(m.puerto);
    const a = c.iniciar();
    c.detener();
    const b = c.iniciar();
    m.paginas[1].resolver(pagina([jornada(2)], null));
    await b;
    m.paginas[0].resolver(pagina([jornada(1)], null));
    await a;
    expect(listo(ultimo()).jornadas.map((j) => j.id)).toEqual([jornada(2).id]);
    await tick();
  });
});

describe("prevención de acciones mutadoras y ausencia de persistencia", () => {
  it("ninguna acción del controlador llama a ejecutar", async () => {
    const m = puertoManual();
    const { c } = armar(m.puerto);
    const p = c.iniciar();
    m.paginas[0].resolver(pagina([jornada(2)], cursorDe(jornada(2))));
    await p;
    c.seleccionar(jornada(2).id);
    const mas = c.cargarMas();
    m.paginas[1].resolver(pagina([], null));
    await mas;
    const f = c.cambiarFecha("2026-11-11");
    m.paginas[2].resolver(pagina([], null));
    await f;
    const r = c.recargar();
    m.paginas[3].resolver(mal());
    await r;
    expect(m.ejecutadas()).toBe(0);
  });

  const SOURCES: Array<[string, string]> = [
    ["jornadas_lectura.ts", fuenteControlador],
    ["useJornadasLectura.ts", fuenteHook],
    ["Jornadas.tsx", fuentePantalla],
    ["jornadas_presentacion.ts", fuentePresentacion],
    ["JornadasVista.tsx", fuenteVista],
  ];
  const sinComentarios = (s: string) =>
    s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/([^:])\/\/.*$/gm, "$1");

  it.each(SOURCES)("%s: sin localStorage, sessionStorage ni IndexedDB", (_n, fuente) => {
    expect(/localStorage|sessionStorage|indexedDB/i.test(sinComentarios(fuente))).toBe(false);
  });

  it.each(SOURCES)("%s: sin RPC, escrituras de tablas ni capa demo", (_n, fuente) => {
    const codigo = sinComentarios(fuente);
    expect(/\.rpc\(|\.(insert|update|upsert|delete)\(|ejecutar|useJornadas\b|hooks\/useJornadas"|mockJornadas|crearPreparacion|confirmarSalida/.test(codigo)).toBe(false);
  });
});
