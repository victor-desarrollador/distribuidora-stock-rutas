import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import type { EstadoJornada, Jornada } from "../lib/jornadas";
import type { HistorialJornada } from "../lib/jornadas_historial";
import { JornadaHistorialPanel } from "./JornadaHistorialPanel";
import { MENSAJE_HISTORIAL_VACIO, type EstadoHistorial } from "./jornadas_historial";

const DUENO = "00000000-0000-4000-8000-000000000001";
const ENCARGADO = "00000000-0000-4000-8000-000000000002";
const P1 = "aaaaaaaa-0000-4000-8000-000000000001";
const P2 = "aaaaaaaa-0000-4000-8000-000000000002";

function jornada(n: number, estado: EstadoJornada = "cargada"): Jornada {
  return {
    id: `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`,
    fecha: "2026-11-10",
    camionId: "22222222-2222-4222-8222-222222222222",
    vendedorId: "33333333-3333-4333-8333-333333333333",
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
  };
}

function historial(jornadaId: string, vacio = false): HistorialJornada {
  return {
    jornadaId,
    operaciones: vacio
      ? []
      : [
          {
            id: "bbbbbbbb-0000-4000-8000-000000000001",
            tipo: "carga",
            actorId: DUENO,
            creadoEn: "2026-11-10T11:00:00+00:00",
            motivo: null,
            lineas: [
              { movimientoId: "cccccccc-0000-4000-8000-000000000001", productoId: P1, cantidad: 12 },
              { movimientoId: "cccccccc-0000-4000-8000-000000000002", productoId: P2, cantidad: 1250 },
            ],
          },
          {
            id: "bbbbbbbb-0000-4000-8000-000000000002",
            tipo: "descarga",
            actorId: ENCARGADO,
            creadoEn: "2026-11-10T12:30:00+00:00",
            motivo: "Sobró <b>mercadería</b>",
            lineas: [{ movimientoId: "cccccccc-0000-4000-8000-000000000003", productoId: P2, cantidad: 250 }],
          },
        ],
    productos: {
      [P1]: { id: P1, codigo: null, nombre: "Leche entera", formaVenta: "unidad", activo: true },
      [P2]: { id: P2, codigo: "J-9", nombre: "Jamón cocido", formaVenta: "peso", activo: true },
    },
  };
}

const noop = () => undefined;
const panel = (j: Jornada, estado: EstadoHistorial, usuarioId: string | null = DUENO) =>
  renderToStaticMarkup(
    <JornadaHistorialPanel jornada={j} estado={estado} usuarioId={usuarioId} onActualizar={noop} />
  );

function botones(html: string) {
  return [...html.matchAll(/<button([^>]*)>([\s\S]*?)<\/button>/g)].map((m) => ({
    texto: m[2].replace(/<[^>]+>/g, "").trim(),
    deshabilitado: /\sdisabled(=|\s|>|$)/.test(m[1]),
  }));
}

describe("JornadaHistorialPanel", () => {
  it("cargando: estado visible y botón de actualizar deshabilitado", () => {
    const j = jornada(1);
    const html = panel(j, { estado: "cargando", jornadaId: j.id });
    expect(html).toContain("Cargas y descargas registradas");
    expect(html).toContain("Cargando historial");
    expect(botones(html)).toEqual([{ texto: "Actualizar historial", deshabilitado: true }]);
  });

  it("un estado de otra jornada (o inactivo) se trata como «cargando», sin datos ajenos", () => {
    const j = jornada(1);
    const otra = jornada(2);
    for (const estado of [
      { estado: "listo", jornadaId: otra.id, historial: historial(otra.id) } as EstadoHistorial,
      { estado: "inactivo" } as EstadoHistorial,
    ]) {
      const html = panel(j, estado);
      expect(html).toContain("Cargando historial");
      expect(html).not.toContain("Leche entera");
    }
  });

  it("vacío: mensaje claro", () => {
    const j = jornada(1, "abierta");
    const html = panel(j, { estado: "listo", jornadaId: j.id, historial: historial(j.id, true) });
    expect(html).toContain(MENSAJE_HISTORIAL_VACIO);
    expect(botones(html)).toEqual([{ texto: "Actualizar historial", deshabilitado: false }]);
  });

  it("error: alerta con el mensaje seguro y actualizar habilitado", () => {
    const j = jornada(1);
    const html = panel(j, { estado: "error", jornadaId: j.id, error: "No se pudo leer el historial." });
    expect(html).toMatch(/role="alert"[\s\S]*No se pudo leer el historial\./);
    expect(botones(html)).toEqual([{ texto: "Actualizar historial", deshabilitado: false }]);
  });

  it("listo: tipo, actor, motivo (escapado) y líneas con unidades y kg", () => {
    const j = jornada(1);
    const html = panel(j, { estado: "listo", jornadaId: j.id, historial: historial(j.id) });
    expect(html).toContain("Carga");
    expect(html).toContain("Descarga");
    expect(html).toContain("Registró: Vos");
    expect(html).toContain("Registró: Otro usuario (00000000)");
    expect(html).toContain("Motivo: Sobró &lt;b&gt;mercadería&lt;/b&gt;");
    expect(html).toContain("Leche entera");
    expect(html).toContain("12 un.");
    expect(html).toContain("Jamón cocido (J-9)");
    expect(html).toContain("1,250 kg");
    expect(html).toContain("0,250 kg");
    // Orden recibido (cronológico): la carga antes que la descarga.
    expect(html.indexOf("Registró: Vos")).toBeLessThan(html.indexOf("Registró: Otro usuario"));
  });

  it("sólo lectura: el único botón es «Actualizar historial» en todos los estados", () => {
    const j = jornada(1);
    const estados: EstadoHistorial[] = [
      { estado: "cargando", jornadaId: j.id },
      { estado: "error", jornadaId: j.id, error: "x" },
      { estado: "listo", jornadaId: j.id, historial: historial(j.id) },
      { estado: "listo", jornadaId: j.id, historial: historial(j.id, true) },
    ];
    for (const e of estados) {
      const html = panel(j, e);
      expect(botones(html).map((b) => b.texto)).toEqual(["Actualizar historial"]);
      expect(html).not.toMatch(/Cargar mercader|Descargar|Reintentar|Cancelar|Confirmar|<input|<form/i);
    }
  });

  it("sin detalle técnico en la salida", () => {
    const j = jornada(1);
    const html = panel(j, { estado: "listo", jornadaId: j.id, historial: historial(j.id) });
    expect(html).not.toMatch(/SQL|PGRST|permission denied|violates|bbbbbbbb|cccccccc/i);
  });
});
