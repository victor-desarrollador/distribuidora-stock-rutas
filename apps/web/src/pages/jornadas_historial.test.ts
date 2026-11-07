// Historial de cargas y descargas (B-02b.2 / S3-0): controlador y
// presentación, sin React ni Supabase. También guarda el código nuevo contra
// escrituras, RPC, claves de idempotencia y almacenamiento del navegador.
import { describe, expect, it } from "vitest";

import fuenteHook from "../hooks/useHistorialJornada.ts?raw";
import fuenteLib from "../lib/jornadas_historial.ts?raw";
import type {
  HistorialJornada,
  ProductoHistorial,
  PuertoHistorialJornada,
  ResultadoHistorial,
} from "../lib/jornadas_historial";
import fuentePanel from "./JornadaHistorialPanel.tsx?raw";
import fuenteControlador from "./jornadas_historial.ts?raw";
import {
  HISTORIAL_INACTIVO,
  crearControladorHistorial,
  etiquetaActor,
  etiquetaProducto,
  formatearCantidadHistorial,
  presentarHistorial,
  type EstadoHistorial,
} from "./jornadas_historial";
import { formatearInstante } from "./jornadas_presentacion";

const J1 = "11111111-1111-4111-8111-111111111111";
const J2 = "11111111-1111-4111-8111-222222222222";
const DUENO = "00000000-0000-4000-8000-000000000001";
const ENCARGADO = "00000000-0000-4000-8000-000000000002";
const P1 = "aaaaaaaa-0000-4000-8000-000000000001";
const P2 = "aaaaaaaa-0000-4000-8000-000000000002";

function prod(id: string, nombre: string, formaVenta: "unidad" | "peso", extra: Partial<ProductoHistorial> = {}): ProductoHistorial {
  return { id, codigo: null, nombre, formaVenta, activo: true, ...extra };
}

function historial(jornadaId = J1): HistorialJornada {
  return {
    jornadaId,
    operaciones: [
      {
        id: "bbbbbbbb-0000-4000-8000-000000000001",
        tipo: "carga",
        actorId: DUENO,
        creadoEn: "2026-11-10T11:00:00+00:00",
        motivo: null,
        lineas: [
          { movimientoId: "cccccccc-0000-4000-8000-000000000002", productoId: P2, cantidad: 1250 },
          { movimientoId: "cccccccc-0000-4000-8000-000000000001", productoId: P1, cantidad: 12 },
        ],
      },
      {
        id: "bbbbbbbb-0000-4000-8000-000000000000",
        tipo: "descarga",
        actorId: ENCARGADO,
        creadoEn: "2026-11-10T12:30:00+00:00",
        motivo: "Sobró mercadería",
        lineas: [{ movimientoId: "cccccccc-0000-4000-8000-000000000003", productoId: P2, cantidad: 5 }],
      },
    ],
    productos: {
      [P1]: prod(P1, "Leche entera", "unidad", { codigo: "L-1" }),
      [P2]: prod(P2, "Jamón cocido", "peso", { activo: false }),
    },
  };
}

/** Puerto manual: cada lectura queda pendiente hasta resolverla. */
function puertoManual() {
  const pendientes: Array<{ jornadaId: string; resolver: (r: ResultadoHistorial) => void }> = [];
  const puerto: PuertoHistorialJornada = {
    leerHistorial: (jornadaId) =>
      new Promise((resolver) => {
        pendientes.push({ jornadaId, resolver });
      }),
  };
  return { puerto, pendientes };
}

function armar() {
  const m = puertoManual();
  const publicados: EstadoHistorial[] = [];
  const c = crearControladorHistorial(m.puerto, (e) => publicados.push(e));
  return { ...m, c, publicados, ultimo: () => publicados[publicados.length - 1] };
}

describe("controlador del historial", () => {
  it("sin jornada (null): estado inactivo y ninguna lectura", async () => {
    const { c, pendientes, ultimo } = armar();
    await c.mostrar(null);
    expect(pendientes).toHaveLength(0);
    expect(ultimo()).toEqual(HISTORIAL_INACTIVO);
    await c.actualizar();
    expect(pendientes).toHaveLength(0);
  });

  it("muestra «cargando» y luego el historial leído", async () => {
    const { c, pendientes, publicados } = armar();
    const p = c.mostrar(J1);
    expect(publicados).toEqual([{ estado: "cargando", jornadaId: J1 }]);
    pendientes[0].resolver({ ok: true, datos: historial() });
    await p;
    expect(publicados[1]).toEqual({ estado: "listo", jornadaId: J1, historial: historial() });
  });

  it("error de lectura: estado de error con el mensaje seguro, sin datos viejos", async () => {
    const { c, pendientes, ultimo } = armar();
    const p1 = c.mostrar(J1);
    pendientes[0].resolver({ ok: true, datos: historial() });
    await p1;
    const p2 = c.actualizar();
    expect(ultimo()).toEqual({ estado: "cargando", jornadaId: J1 });
    pendientes[1].resolver({ ok: false, error: "No se pudo leer." });
    await p2;
    expect(ultimo()).toEqual({ estado: "error", jornadaId: J1, error: "No se pudo leer." });
  });

  it("cambiar de jornada descarta la respuesta tardía de la anterior", async () => {
    const { c, pendientes, ultimo } = armar();
    const p1 = c.mostrar(J1);
    const p2 = c.mostrar(J2);
    pendientes[1].resolver({ ok: true, datos: historial(J2) });
    await p2;
    pendientes[0].resolver({ ok: true, datos: historial(J1) });
    await p1;
    expect(ultimo()).toEqual({ estado: "listo", jornadaId: J2, historial: historial(J2) });
  });

  it("deseleccionar (null) descarta una lectura en curso", async () => {
    const { c, pendientes, ultimo } = armar();
    const p = c.mostrar(J1);
    await c.mostrar(null);
    pendientes[0].resolver({ ok: true, datos: historial() });
    await p;
    expect(ultimo()).toEqual(HISTORIAL_INACTIVO);
  });

  it("actualizar vuelve a leer la jornada actual", async () => {
    const { c, pendientes } = armar();
    const p = c.mostrar(J1);
    pendientes[0].resolver({ ok: true, datos: historial() });
    await p;
    void c.actualizar();
    expect(pendientes.map((x) => x.jornadaId)).toEqual([J1, J1]);
  });

  it("tras detener (desmontaje), una respuesta tardía no publica", async () => {
    const { c, pendientes, publicados } = armar();
    const p = c.mostrar(J1);
    c.detener();
    pendientes[0].resolver({ ok: true, datos: historial() });
    await p;
    expect(publicados).toEqual([{ estado: "cargando", jornadaId: J1 }]);
  });
});

describe("presentación del historial", () => {
  it("cantidades: unidades enteras y peso en kg con 3 decimales, sin float", () => {
    expect(formatearCantidadHistorial(12, "unidad")).toBe("12 un.");
    expect(formatearCantidadHistorial(1250, "peso")).toBe("1,250 kg");
    expect(formatearCantidadHistorial(5, "peso")).toBe("0,005 kg");
    expect(formatearCantidadHistorial(2147483647, "peso")).toBe("2147483,647 kg");
  });

  it("actor: «Vos» para el usuario actual (sin distinguir mayúsculas) y un id corto para otro", () => {
    expect(etiquetaActor(DUENO, DUENO)).toBe("Vos");
    expect(etiquetaActor(DUENO, DUENO.toUpperCase())).toBe("Vos");
    expect(etiquetaActor(ENCARGADO, DUENO)).toBe("Otro usuario (00000000)");
    expect(etiquetaActor(DUENO, null)).toBe("Otro usuario (00000000)");
  });

  it("producto: nombre, código si existe y aviso de baja", () => {
    expect(etiquetaProducto(prod(P1, "Leche", "unidad", { codigo: "L-1" }))).toBe("Leche (L-1)");
    expect(etiquetaProducto(prod(P1, "Leche", "unidad", { codigo: " " }))).toBe("Leche");
    expect(etiquetaProducto(prod(P1, "Jamón", "peso", { activo: false }))).toBe("Jamón · dado de baja");
  });

  it("arma cada operación con tipo, instante en Tucumán, actor, motivo y líneas", () => {
    const filas = presentarHistorial(historial(), DUENO);
    expect(filas[0].instante).toContain("08:00");
    expect(filas[1].instante).toContain("09:30");
    expect(filas).toEqual([
      {
        id: "bbbbbbbb-0000-4000-8000-000000000001",
        tipo: "Carga",
        instante: formatearInstante("2026-11-10T11:00:00+00:00"),
        actor: "Vos",
        motivo: null,
        lineas: [
          { clave: "cccccccc-0000-4000-8000-000000000002", producto: "Jamón cocido · dado de baja", cantidad: "1,250 kg" },
          { clave: "cccccccc-0000-4000-8000-000000000001", producto: "Leche entera (L-1)", cantidad: "12 un." },
        ],
      },
      {
        id: "bbbbbbbb-0000-4000-8000-000000000000",
        tipo: "Descarga",
        instante: formatearInstante("2026-11-10T12:30:00+00:00"),
        actor: "Otro usuario (00000000)",
        motivo: "Sobró mercadería",
        lineas: [{ clave: "cccccccc-0000-4000-8000-000000000003", producto: "Jamón cocido · dado de baja", cantidad: "0,005 kg" }],
      },
    ]);
  });
});

describe("guardas del código nuevo de S3-0 (sólo lectura)", () => {
  const SOURCES: Array<[string, string]> = [
    ["lib/jornadas_historial.ts", fuenteLib],
    ["pages/jornadas_historial.ts", fuenteControlador],
    ["hooks/useHistorialJornada.ts", fuenteHook],
    ["pages/JornadaHistorialPanel.tsx", fuentePanel],
  ];
  const sinComentarios = (s: string) =>
    s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/([^:])\/\/.*$/gm, "$1");

  it.each(SOURCES)("%s: sin localStorage, sessionStorage ni IndexedDB", (_n, fuente) => {
    expect(/localStorage|sessionStorage|indexedDB/i.test(sinComentarios(fuente))).toBe(false);
  });

  it.each(SOURCES)("%s: sin RPC, escrituras de tablas, ejecución ni claves de idempotencia", (_n, fuente) => {
    const codigo = sinComentarios(fuente);
    expect(
      /\.rpc\(|\.(insert|update|upsert|delete)\(|ejecutar|nuevaClaveIdempotencia|randomUUID|idempotency|registrar_carga|registrar_descarga/.test(codigo)
    ).toBe(false);
  });

  it("la capa de datos no lee perfiles (no amplía la lectura de usuarios)", () => {
    expect(/from\(\s*["']perfiles["']/.test(sinComentarios(fuenteLib))).toBe(false);
  });
});
