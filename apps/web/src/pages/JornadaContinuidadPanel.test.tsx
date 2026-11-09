import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import type { EstadoJornada, Jornada } from "../lib/jornadas";
import type { HistorialJornada } from "../lib/jornadas_historial";
import { JornadaContinuidadPanel } from "./JornadaContinuidadPanel";
import {
  ACLARACION_REGISTRADO,
  MENSAJE_CARGA_NETA_ERROR,
  MENSAJE_NO_CERRABLE,
  MENSAJE_SIN_CARGA_NETA,
} from "./jornadas_continuidad";
import type { EstadoHistorial } from "./jornadas_historial";

const J = "00000000-0000-4000-8000-000000000001";
const P1 = "aaaaaaaa-0000-4000-8000-000000000001";
const P2 = "aaaaaaaa-0000-4000-8000-000000000002";
const CAMION = "Camión Norte · AB123CD";

function jornada(estado: EstadoJornada): Jornada {
  return {
    id: J,
    fecha: "2026-11-10",
    camionId: "22222222-2222-4222-8222-222222222222",
    vendedorId: "33333333-3333-4333-8333-333333333333",
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
  };
}

function historialCon(lineas: Array<[string, number]>, vacio = false): HistorialJornada {
  return {
    jornadaId: J,
    operaciones: vacio
      ? []
      : [
          {
            id: "bbbbbbbb-0000-4000-8000-000000000001",
            tipo: "carga",
            actorId: "66666666-6666-4666-8666-666666666666",
            creadoEn: "2026-11-10T11:00:00+00:00",
            motivo: null,
            lineas: lineas.map(([productoId, cantidad], i) => ({
              movimientoId: `cccccccc-0000-4000-8000-00000000000${i}`,
              productoId,
              cantidad,
            })),
          },
        ],
    productos: {
      [P1]: { id: P1, codigo: null, nombre: "Leche entera", formaVenta: "unidad", activo: true },
      [P2]: { id: P2, codigo: null, nombre: "Jamón <cocido>", formaVenta: "peso", activo: true },
    },
  };
}

const panel = (estado: EstadoJornada, historial: EstadoHistorial) =>
  renderToStaticMarkup(<JornadaContinuidadPanel jornada={jornada(estado)} historial={historial} nombreCamion={CAMION} />);

const listo = (h: HistorialJornada): EstadoHistorial => ({ estado: "listo", jornadaId: J, historial: h });

describe("JornadaContinuidadPanel", () => {
  it("en reparto: no cerrable, camión bloqueado, pasos y carga neta de la jornada con aclaración", () => {
    const html = panel("en_reparto", listo(historialCon([[P1, 12], [P2, 1250]])));
    expect(html).toContain("Estado de cierre");
    expect(html).toContain(MENSAJE_NO_CERRABLE);
    expect(html).toContain(`Mientras esta jornada no se cierre, ${CAMION} no puede abrir otra jornada.`);
    for (const t of ["Carga del camión", "Salida", "Ventas finalizadas", "Conteo formal de regreso", "Retorno y regularización", "Rendición y cierre"]) {
      expect(html).toContain(t);
    }
    expect(html.match(/No disponible todavía/g)).toHaveLength(4);
    expect(html).toContain(ACLARACION_REGISTRADO);
    // Semántica: carga neta de ESTA jornada, no saldo real del camión ni conteo.
    expect(html).toContain("Carga neta registrada de esta jornada");
    expect(html).toContain('aria-label="Carga neta de la jornada"');
    expect(html).toContain("No es un conteo físico ni el saldo real del camión");
    expect(html).not.toMatch(/Mercadería registrada|registrada en el camión/);
    expect(html).toContain("12 un.");
    expect(html).toContain("1,250 kg");
    expect(html).toContain("Jamón &lt;cocido&gt;");
  });

  it("sin carga neta registrada: mensaje claro", () => {
    expect(panel("abierta", listo(historialCon([], true)))).toContain(MENSAJE_SIN_CARGA_NETA);
  });

  it("historial cargando o con error: estado visible, sin datos", () => {
    expect(panel("cargada", { estado: "cargando", jornadaId: J })).toContain("Calculando");
    const html = panel("cargada", { estado: "error", jornadaId: J, error: "x" });
    expect(html).toMatch(new RegExp(`role="alert"[^>]*>${MENSAJE_CARGA_NETA_ERROR.slice(0, 20)}`));
  });

  it("jornada cerrada: sin aviso de no cerrable ni de camión bloqueado", () => {
    const html = panel("cerrada", listo(historialCon([], true)));
    expect(html).not.toContain(MENSAJE_NO_CERRABLE);
    expect(html).not.toContain("no puede abrir otra jornada");
  });

  it("sólo lectura: sin botones, formularios ni términos de faltante o diferencia", () => {
    for (const e of ["abierta", "cargada", "en_reparto"] as const) {
      const html = panel(e, listo(historialCon([[P1, 1]])));
      expect(html).not.toMatch(/<button|<input|<form/);
      expect(html).not.toMatch(/faltante|sobrante|diferencia/i);
      expect(html).not.toMatch(/SQL|PGRST|permission denied/i);
    }
  });
});
