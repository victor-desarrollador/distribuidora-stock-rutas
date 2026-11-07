import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import type { EstadoJornada, Jornada } from "../lib/jornadas";
import { JornadasVista, type JornadasVistaProps } from "./JornadasVista";
import type { EstadoPantallaJornadas, LecturaJornadas } from "./jornadas_lectura";
import {
  ETIQUETA_ESTADO_JORNADA,
  MENSAJE_NO_DISPONIBLE,
  formatearFechaOperativa,
  formatearInstante,
} from "./jornadas_presentacion";

const CAMION = "22222222-2222-4222-8222-222222222222";

function jornada(n: number, estado: EstadoJornada = "abierta", fecha = "2026-11-10"): Jornada {
  return {
    id: `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`,
    fecha, camionId: CAMION,
    vendedorId: "33333333-3333-4333-8333-333333333333",
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "99999999-9999-4999-8999-999999999999",
    creadoEn: "2026-11-10T11:30:00+00:00",
  };
}

const noop = () => undefined;
function vista(lectura: LecturaJornadas, extra: Partial<EstadoPantallaJornadas> = {}, props: Partial<JornadasVistaProps> = {}) {
  return renderToStaticMarkup(
    <JornadasVista
      estado={{ fecha: null, lectura, seleccionadaId: null, ...extra }}
      puedeAdministrar={true}
      nombreCamion={() => "Camión Norte · AB123CD"}
      onCambiarFecha={noop}
      onRecargar={noop}
      onCargarMas={noop}
      onCargarTodas={noop}
      onSeleccionar={noop}
      {...props}
    />
  );
}
const listo = (jornadas: Jornada[], siguiente: { fecha: string; id: string } | null = null, resto: object = {}): LecturaJornadas => ({
  estado: "listo", jornadas, siguiente, ampliando: null, errorAmpliacion: null, ...resto,
});

/** Todos los <button …>…</button> del HTML con su texto visible. */
function botones(html: string) {
  return [...html.matchAll(/<button([^>]*)>([\s\S]*?)<\/button>/g)].map((m) => ({
    atributos: m[1],
    texto: m[2].replace(/<[^>]+>/g, "").trim(),
    deshabilitado: /\sdisabled(=|\s|>|$)/.test(m[1]),
  }));
}

describe("JornadasVista", () => {
  it("cargando: estado visible y sin datos", () => {
    const html = vista({ estado: "cargando" });
    expect(html).toContain("Cargando jornadas");
    expect(html).not.toContain("Ver detalle");
  });

  it("error: alerta con el mensaje seguro, reintento y sin datos", () => {
    const html = vista({ estado: "error", error: "No se pudieron leer las jornadas. Intentá de nuevo." });
    expect(html).toContain('role="alert"');
    expect(html).toContain("No se pudieron leer las jornadas. Intentá de nuevo.");
    expect(html).toContain("Reintentar");
    expect(html).not.toContain("Ver detalle");
    expect(html).not.toMatch(/SQL|PGRST|permission denied|violates/i);
  });

  it("vacío sin filtro y con filtro", () => {
    expect(vista(listo([]))).toContain("Todavía no hay jornadas registradas.");
    expect(vista(listo([]))).toContain("<h1");
    const conFiltro = vista(listo([]), { fecha: "2026-12-31" });
    expect(conFiltro).toContain("No hay jornadas el 31/12/2026.");
    expect(conFiltro).toContain('value="2026-12-31"');
  });

  it("lista completa vs. parcial: sólo declara «completa» sin continuación", () => {
    const completa = vista(listo([jornada(2), jornada(1)]));
    expect(completa).toContain("2 jornadas (lista completa)");
    expect(completa).not.toContain("Cargar más");

    const parcial = vista(listo([jornada(2), jornada(1)], { fecha: "2026-11-10", id: jornada(1).id }));
    expect(parcial).toContain("2 jornadas cargadas. Hay más: la lista todavía no está completa.");
    expect(parcial).not.toContain("lista completa");
    expect(parcial).toContain("Cargar más");
    expect(parcial).toContain("Cargar todas");
  });

  it("mientras amplía, deshabilita las dos acciones de ampliación", () => {
    const html = vista(listo([jornada(1)], { fecha: "2026-11-10", id: jornada(1).id }, { ampliando: "mas" }));
    const b = botones(html).filter((x) => /^Cargando/.test(x.texto) || x.texto === "Cargar todas");
    expect(b).toHaveLength(2);
    expect(b.every((x) => x.deshabilitado)).toBe(true);
  });

  it("error al ampliar: alerta y se conservan las filas", () => {
    const html = vista(listo([jornada(1)], { fecha: "2026-11-10", id: jornada(1).id }, { errorAmpliacion: "No se pudieron leer las jornadas. Intentá de nuevo." }));
    expect(html).toContain('role="alert"');
    expect(html).toContain("Ver detalle");
  });

  it("muestra la etiqueta real de cada estado", () => {
    const estados = Object.keys(ETIQUETA_ESTADO_JORNADA) as EstadoJornada[];
    expect(estados).toHaveLength(6);
    const html = vista(listo(estados.map((e, i) => jornada(i + 1, e))));
    for (const e of estados) expect(html).toContain(ETIQUETA_ESTADO_JORNADA[e]);
  });

  it("es responsive: tabla en PC y tarjetas en celulares", () => {
    const html = vista(listo([jornada(1)]));
    expect(html).toMatch(/hidden overflow-x-auto[^"]*md:block/);
    expect(html).toContain("md:hidden");
    expect(html).toContain("min-h-12");
  });

  it("sin selección no hay detalle; con selección muestra los campos reales", () => {
    const j = jornada(1, "en_reparto");
    expect(vista(listo([j]))).not.toContain("Detalle de la jornada");
    const html = vista(listo([j]), { seleccionadaId: j.id });
    expect(html).toContain("Detalle de la jornada");
    expect(html).toContain("10/11/2026");
    expect(html).toContain("En reparto");
    expect(html).toContain("Camión Norte · AB123CD");
    expect(html).toContain("33333333");
    expect(html).toContain("66666666");
    expect(html).toContain('aria-pressed="true"');
  });

  it("una selección que ya no está en la lista no muestra detalle", () => {
    const html = vista(listo([jornada(1)]), { seleccionadaId: jornada(9).id });
    expect(html).not.toContain("Detalle de la jornada");
  });

  it("los botones mutadores están deshabilitados y explican por qué", () => {
    const j = jornada(1);
    const html = vista(listo([j]), { seleccionadaId: j.id });
    const mutadores = botones(html).filter((b) => /Nueva jornada|Confirmar salida|Cargar mercader|Descargar|Abrir jornada/i.test(b.texto));
    expect(mutadores.map((b) => b.texto.replace(/\s*\(.*$/, ""))).toEqual(["Nueva jornada", "Confirmar salida"]);
    expect(mutadores.every((b) => b.deshabilitado && b.atributos.includes("title="))).toBe(true);
    expect(mutadores.every((b) => /no disponible todavía/.test(b.texto))).toBe(true);
    expect(html).toContain("sólo lectura");
    expect(html).toContain(MENSAJE_NO_DISPONIBLE.slice(0, 30));
  });

  it("no hay formularios ni botones de envío", () => {
    const html = vista(listo([jornada(1)]));
    expect(html).not.toContain("<form");
    expect(html).not.toContain('type="submit"');
  });

  it("las acciones habilitadas son sólo de lectura", () => {
    const j = jornada(1);
    const habilitados = botones(vista(listo([j], { fecha: j.fecha, id: j.id }), { seleccionadaId: j.id, fecha: "2026-11-10" }))
      .filter((b) => !b.deshabilitado)
      .map((b) => b.texto);
    for (const t of habilitados) {
      expect(["Actualizar", "Ver todas las fechas", "Ver detalle", "Cargar más", "Cargar todas", ""]).toContain(t);
    }
  });
});

describe("formatos", () => {
  it("fecha operativa sin corrimientos de zona horaria", () => {
    expect(formatearFechaOperativa("2026-11-10")).toBe("10/11/2026");
    expect(formatearFechaOperativa("2026-01-01")).toBe("01/01/2026");
  });

  it("instante en hora de Tucumán; inválido → «—»", () => {
    const f = formatearInstante("2026-11-10T11:30:00+00:00");
    expect(f).toContain("10/11/2026");
    expect(f).toContain("08:30");
    expect(formatearInstante("no-es-fecha")).toBe("—");
  });
});

describe("JornadasVista para el vendedor/piloto (puedeAdministrar = false)", () => {
  const j = jornada(1, "cargada");
  const comoVendedor = (lectura: LecturaJornadas, extra: Partial<EstadoPantallaJornadas> = {}) =>
    vista(lectura, extra, { puedeAdministrar: false });

  it("se llama «Mi jornada» (dueño y encargado ven «Jornadas»)", () => {
    expect(comoVendedor(listo([j]))).toContain(">Mi jornada<");
    expect(comoVendedor(listo([j]))).not.toContain(">Jornadas<");
    expect(vista(listo([j]))).toContain(">Jornadas<");
    expect(vista(listo([j]))).not.toContain("Mi jornada");
  });

  it("no muestra ningún control de gestión ni la nota de operaciones no disponibles", () => {
    const html = comoVendedor(listo([j]), { seleccionadaId: j.id });
    expect(html).not.toMatch(/Nueva jornada|Confirmar salida/);
    expect(html).not.toContain("no disponible todavía");
    expect(html).not.toContain('role="note"');
    // El único botón deshabilitado posible es el filtro «Ver todas las fechas».
    expect(botones(html).filter((b) => b.deshabilitado).map((b) => b.texto)).toEqual(["Ver todas las fechas"]);
  });

  it("el detalle oculta quién abrió, la operación de apertura y el vendedor asignado", () => {
    const html = comoVendedor(listo([j]), { seleccionadaId: j.id });
    expect(html).toContain("Detalle de la jornada");
    expect(html).toContain("10/11/2026");
    expect(html).toContain("Cargada");
    expect(html).not.toMatch(/Abierta por|Operación de apertura|Vendedor asignado/);
    expect(html).not.toContain("66666666");
    expect(html).not.toContain("99999999");
    expect(html).not.toContain("33333333");
  });

  it("vacío específico cuando no tiene jornada asignada (con y sin fecha)", () => {
    expect(comoVendedor(listo([]))).toContain("No tenés una jornada asignada.");
    expect(comoVendedor(listo([]), { fecha: "2026-12-31" })).toContain("No tenés una jornada asignada el 31/12/2026.");
    expect(comoVendedor(listo([]))).not.toContain("Todavía no hay jornadas registradas");
  });

  it("mantiene el diseño responsive y los controles táctiles", () => {
    const html = comoVendedor(listo([j]));
    expect(html).toContain("md:hidden");
    expect(html).toContain("min-h-12");
  });

  it("las acciones habilitadas siguen siendo sólo de lectura", () => {
    const habilitados = botones(comoVendedor(listo([j], { fecha: j.fecha, id: j.id }), { seleccionadaId: j.id }))
      .filter((b) => !b.deshabilitado)
      .map((b) => b.texto);
    for (const t of habilitados) {
      expect(["Actualizar", "Ver todas las fechas", "Ver detalle", "Cargar más", "Cargar todas", ""]).toContain(t);
    }
  });
});
