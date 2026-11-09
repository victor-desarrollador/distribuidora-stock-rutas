// Estado de jornada y bloqueos de continuidad (B-02b.2 / S3-1): lógica pura,
// sin React ni Supabase, y guardas del código nuevo (sin lecturas propias, RPC,
// escrituras ni almacenamiento del navegador).
import { describe, expect, it } from "vitest";

import { ESTADOS_JORNADA, type EstadoJornada, type Jornada } from "../lib/jornadas";
import type { HistorialJornada } from "../lib/jornadas_historial";
import fuentePanel from "./JornadaContinuidadPanel.tsx?raw";
import fuenteLogica from "./jornadas_continuidad.ts?raw";
import {
  MENSAJE_CARGA_NETA_ERROR,
  armarContinuidad,
  formatearCantidadExacta,
  mensajeCamionBloqueado,
  cargaNetaJornada,
  pasosContinuidad,
} from "./jornadas_continuidad";

const J = "00000000-0000-4000-8000-000000000001";
const J_OTRA = "00000000-0000-4000-8000-000000000002";
const DUENO = "00000000-0000-4000-8000-0000000000aa";
const P1 = "aaaaaaaa-0000-4000-8000-000000000001";
const P2 = "aaaaaaaa-0000-4000-8000-000000000002";
const P3 = "aaaaaaaa-0000-4000-8000-000000000003";

function jornada(estado: EstadoJornada, id = J): Jornada {
  return {
    id,
    fecha: "2026-11-10",
    camionId: "22222222-2222-4222-8222-222222222222",
    vendedorId: "33333333-3333-4333-8333-333333333333",
    estado,
    abiertaPor: DUENO,
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
  };
}

let mov = 0;
function op(tipo: "carga" | "descarga", lineas: Array<[string, number]>) {
  return {
    id: `bbbbbbbb-0000-4000-8000-${String(++mov).padStart(12, "0")}`,
    tipo,
    actorId: DUENO,
    creadoEn: "2026-11-10T11:00:00+00:00",
    motivo: tipo === "descarga" ? "Sobró" : null,
    lineas: lineas.map(([productoId, cantidad]) => ({
      movimientoId: `cccccccc-0000-4000-8000-${String(++mov).padStart(12, "0")}`,
      productoId,
      cantidad,
    })),
  };
}

function historial(operaciones: HistorialJornada["operaciones"], jornadaId = J): HistorialJornada {
  return {
    jornadaId,
    operaciones,
    productos: {
      [P1]: { id: P1, codigo: null, nombre: "Leche entera", formaVenta: "unidad", activo: true },
      [P2]: { id: P2, codigo: "J-9", nombre: "Jamón cocido", formaVenta: "peso", activo: true },
      [P3]: { id: P3, codigo: null, nombre: "Queso", formaVenta: "peso", activo: false },
    },
  };
}

describe("pasos de continuidad según el estado real", () => {
  const resumen = (e: EstadoJornada) => pasosContinuidad(e).map((p) => [p.clave, p.estado]);

  it("abierta: carga y salida pendientes; el resto no disponible", () => {
    expect(resumen("abierta")).toEqual([
      ["carga", "pendiente"],
      ["salida", "pendiente"],
      ["ventas", "no_disponible"],
      ["conteo", "no_disponible"],
      ["retorno", "no_disponible"],
      ["cierre", "no_disponible"],
    ]);
    expect(pasosContinuidad("abierta")[1].detalle).toBe("Requiere que la jornada esté cargada.");
  });

  it("cargada: carga hecha; salida pendiente y se confirma desde esta pantalla", () => {
    expect(resumen("cargada").slice(0, 2)).toEqual([["carga", "hecho"], ["salida", "pendiente"]]);
    expect(pasosContinuidad("cargada")[1].detalle).toContain("Confirmar salida");
  });

  it("en reparto: carga y salida hechas; ventas, conteo, retorno y cierre no disponibles", () => {
    expect(resumen("en_reparto")).toEqual([
      ["carga", "hecho"],
      ["salida", "hecho"],
      ["ventas", "no_disponible"],
      ["conteo", "no_disponible"],
      ["retorno", "no_disponible"],
      ["cierre", "no_disponible"],
    ]);
  });

  it("estados posteriores (si existieran) marcan hecho sólo lo alcanzado", () => {
    expect(resumen("ventas_finalizadas").map((x) => x[1])).toEqual(["hecho", "hecho", "hecho", "no_disponible", "no_disponible", "no_disponible"]);
    expect(resumen("regreso_contado").map((x) => x[1])).toEqual(["hecho", "hecho", "hecho", "hecho", "no_disponible", "no_disponible"]);
    expect(resumen("cerrada").every((x) => x[1] === "hecho")).toBe(true);
  });

  it("ningún paso no disponible ofrece una acción ni promete habilitarla en una fecha", () => {
    for (const e of ESTADOS_JORNADA) {
      for (const p of pasosContinuidad(e).filter((x) => x.estado === "no_disponible")) {
        expect(p.detalle).toMatch(/todavía no registra/);
      }
    }
  });
});

describe("bloqueo del camión y cierre", () => {
  it("toda jornada no cerrada bloquea al camión; la cerrada no", () => {
    for (const e of ESTADOS_JORNADA) {
      const c = armarContinuidad(jornada(e), { estado: "inactivo" });
      expect(c.cerrada).toBe(e === "cerrada");
      expect(c.bloqueaCamion).toBe(e !== "cerrada");
    }
    expect(mensajeCamionBloqueado("Camión Norte · AB123CD")).toBe(
      "Mientras esta jornada no se cierre, Camión Norte · AB123CD no puede abrir otra jornada."
    );
  });
});

describe("carga neta registrada de la jornada (cargas − descargas)", () => {
  it("suma cargas, resta descargas, omite netos en cero y ordena por producto", () => {
    const h = historial([
      op("carga", [[P1, 12], [P2, 1250]]),
      op("carga", [[P1, 3], [P3, 500]]),
      op("descarga", [[P2, 250], [P3, 500]]),
    ]);
    expect(cargaNetaJornada(h)).toEqual([
      { productoId: P2, producto: "Jamón cocido (J-9)", cantidad: "1,000 kg" },
      { productoId: P1, producto: "Leche entera", cantidad: "15 un." },
    ]);
  });

  it("sin operaciones o todo descargado: lista vacía", () => {
    expect(cargaNetaJornada(historial([]))).toEqual([]);
    expect(cargaNetaJornada(historial([op("carga", [[P1, 2]]), op("descarga", [[P1, 2]])]))).toEqual([]);
  });

  it("neto negativo (imposible por ADR-007 §2.6) → falla cerrada, nunca un faltante", () => {
    expect(cargaNetaJornada(historial([op("descarga", [[P1, 1]])]))).toBeNull();
  });

  it("producto sin datos → falla cerrada", () => {
    const h = historial([op("carga", [["aaaaaaaa-0000-4000-8000-000000000099", 1]])]);
    expect(cargaNetaJornada(h)).toBeNull();
  });

  it("formato exacto en BigInt, también por encima de Number.MAX_SAFE_INTEGER", () => {
    expect(formatearCantidadExacta(5n, "peso")).toBe("0,005 kg");
    expect(formatearCantidadExacta(1250n, "peso")).toBe("1,250 kg");
    expect(formatearCantidadExacta(12n, "unidad")).toBe("12 un.");
    expect(formatearCantidadExacta(9007199254740993n, "peso")).toBe("9007199254740,993 kg");
    const muchas = Array.from({ length: 5 }, () => op("carga", [[P1, 2147483647]]));
    expect(cargaNetaJornada(historial(muchas))?.[0].cantidad).toBe("10737418235 un.");
  });
});

describe("armarContinuidad: usa sólo el historial de ESTA jornada", () => {
  it("historial listo de la jornada → carga neta lista", () => {
    const c = armarContinuidad(jornada("cargada"), { estado: "listo", jornadaId: J, historial: historial([op("carga", [[P1, 1]])]) });
    expect(c.cargaNeta).toEqual({ estado: "listo", lineas: [{ productoId: P1, producto: "Leche entera", cantidad: "1 un." }] });
  });

  it("historial de otra jornada, inactivo o cargando → «cargando», sin datos ajenos", () => {
    for (const h of [
      { estado: "listo", jornadaId: J_OTRA, historial: historial([op("carga", [[P1, 9]])], J_OTRA) } as const,
      { estado: "inactivo" } as const,
      { estado: "cargando", jornadaId: J } as const,
      { estado: "error", jornadaId: J_OTRA, error: "x" } as const,
    ]) {
      expect(armarContinuidad(jornada("cargada"), h).cargaNeta).toEqual({ estado: "cargando" });
    }
  });

  it("error del historial o neto inconsistente → mensaje de error seguro", () => {
    expect(armarContinuidad(jornada("cargada"), { estado: "error", jornadaId: J, error: "x" }).cargaNeta).toEqual({
      estado: "error",
      mensaje: MENSAJE_CARGA_NETA_ERROR,
    });
    const inconsistente = { estado: "listo", jornadaId: J, historial: historial([op("descarga", [[P1, 1]])]) } as const;
    expect(armarContinuidad(jornada("cargada"), inconsistente).cargaNeta.estado).toBe("error");
  });
});

describe("guardas del código nuevo de S3-1 (sólo lectura, sin lecturas propias)", () => {
  const sinComentarios = (s: string) =>
    s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/([^:])\/\/.*$/gm, "$1");

  it.each([
    ["pages/jornadas_continuidad.ts", fuenteLogica],
    ["pages/JornadaContinuidadPanel.tsx", fuentePanel],
  ])("%s: sin Supabase, consultas, RPC, escrituras, ejecución ni almacenamiento", (_n, fuente) => {
    const codigo = sinComentarios(fuente);
    expect(
      /supabase|\.from\(|\.rpc\(|\.(insert|update|upsert|delete)\(|ejecutar|idempotency|randomUUID|localStorage|sessionStorage|indexedDB|<button|<input|<form/i.test(codigo)
    ).toBe(false);
  });

  it("no presenta diferencias ni faltantes", () => {
    for (const fuente of [fuenteLogica, fuentePanel]) {
      const codigo = sinComentarios(fuente);
      expect(/faltante|sobrante|diferencia/i.test(codigo)).toBe(false);
    }
  });
});
