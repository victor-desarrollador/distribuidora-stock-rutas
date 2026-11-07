import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import {
  MENSAJE_ERROR_GENERICO,
  MAX_INTENTOS,
  MENSAJE_CONCURRENCIA_AGOTADA,
  MENSAJE_ERROR_LECTURA,
  MENSAJE_RESULTADO_DESCONOCIDO,
  MENSAJE_SIN_UBICACIONES,
  armarDatosStock,
  clasificarErrorStock,
  crearPuertoStock,
  mensajeErrorStock,
} from "./stock";

const DEP = "d0000000-0000-4000-8000-000000000001";
const CUA = "c0000000-0000-4000-8000-000000000002";
const CAM = "a0000000-0000-4000-8000-000000000003";
const CAMION = "b0000000-0000-4000-8000-000000000004";
const P1 = "11111111-1111-4111-8111-111111111111";
const P2 = "22222222-2222-4222-8222-222222222222";
const OP = "99999999-9999-4999-8999-999999999999";

const ubicaciones = [
  { id: DEP, tipo: "deposito", camion_id: null },
  { id: CUA, tipo: "cuarentena", camion_id: null },
  { id: CAM, tipo: "camion", camion_id: CAMION },
];
const productos = [
  { id: P1, codigo: null, nombre: "Yogur", forma_venta: "unidad", stock_minimo: 10, activo: true },
  { id: P2, codigo: "F-1", nombre: "Jamón", forma_venta: "peso", stock_minimo: 2500, activo: true },
];
const saldos = [
  { ubicacion_id: DEP, producto_id: P1, cantidad: 40 },
  { ubicacion_id: DEP, producto_id: P2, cantidad: 12500 },
];

type Respuesta = { data: unknown; error: unknown };

function clienteFalso(opciones: {
  tablas?: Record<string, Respuesta>;
  rpc?: Respuesta | (() => never);
  // Respuestas sucesivas de la RPC (la última se repite). "lanzar" simula una excepción de red.
  secuencia?: (Respuesta | "lanzar")[];
}) {
  const consultas: { tabla: string; columnas: string }[] = [];
  const rpcs: { nombre: string; argumentos: Record<string, unknown> }[] = [];
  const tablas = opciones.tablas ?? {};
  const cliente = {
    from(tabla: string) {
      return {
        select(columnas: string) {
          consultas.push({ tabla, columnas });
          return Promise.resolve(tablas[tabla] ?? { data: [], error: null });
        },
      };
    },
    rpc(nombre: string, argumentos: Record<string, unknown>) {
      rpcs.push({ nombre, argumentos });
      if (opciones.secuencia) {
        const x = opciones.secuencia[Math.min(rpcs.length - 1, opciones.secuencia.length - 1)];
        if (x === "lanzar") throw new Error("fallo de red");
        return Promise.resolve(x);
      }
      const r = opciones.rpc;
      return typeof r === "function" ? r() : Promise.resolve(r ?? { data: OP, error: null });
    },
  };
  return { puerto: crearPuertoStock(cliente as unknown as SupabaseClient), consultas, rpcs };
}

const tablasOk = {
  ubicaciones: { data: ubicaciones, error: null },
  productos: { data: productos, error: null },
  stock_actual: { data: saldos, error: null },
};

describe("consulta de stock", () => {
  it("lee las cuatro fuentes y arma los datos", async () => {
    const { puerto, consultas } = clienteFalso({ tablas: tablasOk });
    const r = await puerto.leer();

    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.datos.depositoId).toBe(DEP);
    expect(r.datos.cuarentenaId).toBe(CUA);
    expect(r.datos.saldos).toHaveLength(2);
    expect(r.datos.productos[1].formaVenta).toBe("peso");
    expect(consultas.map((c) => c.tabla).sort()).toEqual(
      ["productos", "stock_actual", "ubicaciones"]
    );
  });

  it("falla cerrado si una consulta devuelve error (sin detalle de SQL)", async () => {
    const { puerto } = clienteFalso({
      tablas: { ...tablasOk, stock_actual: { data: null, error: { message: "permission denied for view" } } },
    });
    const r = await puerto.leer();
    expect(r).toEqual({ ok: false, error: MENSAJE_ERROR_LECTURA });
  });

  it("falla cerrado si la consulta lanza (red)", async () => {
    const cliente = {
      from() {
        throw new Error("fallo de red");
      },
    };
    const r = await crearPuertoStock(cliente as unknown as SupabaseClient).leer();
    expect(r).toEqual({ ok: false, error: MENSAJE_ERROR_LECTURA });
  });
});

describe("armarDatosStock", () => {
  const base = { ubicaciones, productos, saldos };

  it("rechaza una fila inválida (cantidad fraccionaria, forma de venta desconocida)", () => {
    expect(armarDatosStock({ ...base, saldos: [{ ubicacion_id: DEP, producto_id: P1, cantidad: 1.5 }] }).ok).toBe(false);
    expect(armarDatosStock({ ...base, saldos: [{ ubicacion_id: DEP, producto_id: P1, cantidad: "5" }] }).ok).toBe(false);
    expect(
      armarDatosStock({ ...base, productos: [{ ...productos[0], forma_venta: "pieza" }] }).ok
    ).toBe(false);
    expect(
      armarDatosStock({ ...base, productos: [{ ...productos[0], stock_minimo: 2.5 }] }).ok
    ).toBe(false);
  });

  it("rechaza ubicación camión sin camion_id y depósito con camion_id", () => {
    expect(armarDatosStock({ ...base, ubicaciones: [...ubicaciones.slice(0, 2), { id: CAM, tipo: "camion", camion_id: null }] }).ok).toBe(false);
    expect(armarDatosStock({ ...base, ubicaciones: [{ ...ubicaciones[0], camion_id: CAMION }, ubicaciones[1]] }).ok).toBe(false);
  });

  it("exige exactamente un depósito y una cuarentena", () => {
    expect(armarDatosStock({ ...base, ubicaciones: [ubicaciones[0]] })).toEqual({ ok: false, error: MENSAJE_SIN_UBICACIONES });
    expect(
      armarDatosStock({ ...base, ubicaciones: [...ubicaciones, { id: "e0000000-0000-4000-8000-000000000009", tipo: "deposito", camion_id: null }] })
    ).toEqual({ ok: false, error: MENSAJE_SIN_UBICACIONES });
  });

  it("rechaza saldos de ubicaciones o productos desconocidos (aislamiento)", () => {
    expect(armarDatosStock({ ...base, saldos: [{ ubicacion_id: "x-ajena", producto_id: P1, cantidad: 1 }] }).ok).toBe(false);
    expect(armarDatosStock({ ...base, saldos: [{ ubicacion_id: DEP, producto_id: "p-ajeno", cantidad: 1 }] }).ok).toBe(false);
  });

  it("rechaza respuestas que no son arreglos", () => {
    expect(armarDatosStock({ ...base, saldos: null }).ok).toBe(false);
  });
});

describe("operaciones por RPC", () => {
  it("registrar_ingreso envía los parámetros del contrato, sin empresa ni actor", async () => {
    const { puerto, rpcs } = clienteFalso({});
    const r = await puerto.ejecutar(
      { tipo: "ingreso", productoId: P1, cantidad: 12, motivo: null },
      "k-1"
    );
    expect(r).toEqual({ ok: true, datos: OP });
    expect(rpcs).toEqual([
      {
        nombre: "registrar_ingreso",
        argumentos: { p_idempotency_key: "k-1", p_producto_id: P1, p_cantidad: 12, p_motivo: null },
      },
    ]);
  });

  it("mover_a_cuarentena y registrar_merma usan sus parámetros", async () => {
    const { puerto, rpcs } = clienteFalso({});
    await puerto.ejecutar(
      { tipo: "cuarentena", productoId: P1, origenId: DEP, cantidad: 3, motivo: "revisión" },
      "k-2"
    );
    await puerto.ejecutar(
      { tipo: "merma", productoId: P2, origenId: DEP, cantidad: 1250, motivoCodigo: "vencido", motivo: null },
      "k-3"
    );
    expect(rpcs[0]).toEqual({
      nombre: "mover_a_cuarentena",
      argumentos: { p_idempotency_key: "k-2", p_producto_id: P1, p_ubicacion_origen_id: DEP, p_cantidad: 3, p_motivo: "revisión" },
    });
    expect(rpcs[1]).toEqual({
      nombre: "registrar_merma",
      argumentos: {
        p_idempotency_key: "k-3", p_producto_id: P2, p_ubicacion_origen_id: DEP,
        p_cantidad: 1250, p_motivo_codigo: "vencido", p_motivo: null,
      },
    });
  });

  it.each([
    ["stock_insuficiente", "No hay stock suficiente en el depósito."],
    ["stock_no_autorizado", "No tenés permiso para registrar movimientos de stock."],
    ["stock_conflicto_idempotencia", "Esta operación ya se registró con otros datos. Revisá el stock antes de volver a cargarla."],
    ["stock_producto_inactivo", "El producto está dado de baja."],
  ])("traduce el error de negocio %s", async (codigo, texto) => {
    const { puerto } = clienteFalso({ rpc: { data: null, error: { message: codigo, code: "PT409" } } });
    const r = await puerto.ejecutar({ tipo: "ingreso", productoId: P1, cantidad: 1, motivo: null }, "k");
    expect(r).toEqual({ ok: false, error: texto });
  });

  it("sin permiso de ejecución (42501) informa permisos insuficientes", async () => {
    const { puerto } = clienteFalso({ rpc: { data: null, error: { message: "permission denied for function registrar_ingreso", code: "42501" } } });
    const r = await puerto.ejecutar({ tipo: "ingreso", productoId: P1, cantidad: 1, motivo: null }, "k");
    expect(r).toEqual({ ok: false, error: "No tenés permiso para registrar movimientos de stock." });
  });

  it("nunca muestra el detalle de SQL de un error desconocido", async () => {
    const detalle = 'duplicate key value violates unique constraint "movimientos_stock_pkey"';
    expect(mensajeErrorStock({ message: detalle, code: "23505" })).toBe(MENSAJE_ERROR_GENERICO);
    expect(mensajeErrorStock({ message: "toString", code: "x" })).toBe(MENSAJE_ERROR_GENERICO);
    expect(mensajeErrorStock(null)).toBe(MENSAJE_ERROR_GENERICO);
  });

  it("error sin código (fallo de red devuelto por supabase-js): resultado desconocido, no «reintentá»", async () => {
    const red = { message: "TypeError: Failed to fetch", details: "", hint: "", code: "" };
    expect(mensajeErrorStock(red)).toBe(MENSAJE_RESULTADO_DESCONOCIDO);
    const { puerto } = clienteFalso({ rpc: { data: null, error: red } });
    const r = await puerto.ejecutar({ tipo: "ingreso", productoId: P1, cantidad: 1, motivo: null }, "k");
    expect(r).toEqual({ ok: false, error: MENSAJE_RESULTADO_DESCONOCIDO, incierto: true });
    // Con código de PostgREST (error del servidor) sigue siendo genérico.
    expect(mensajeErrorStock({ message: "boom", code: "PT500" })).toBe(MENSAJE_ERROR_GENERICO);
  });

  it("fallo de red o respuesta sin id: resultado desconocido (no se asume éxito)", async () => {
    const lanzar = () => {
      throw new Error("fallo de red");
    };
    const a = await clienteFalso({ rpc: lanzar }).puerto.ejecutar({ tipo: "ingreso", productoId: P1, cantidad: 1, motivo: null }, "k");
    const b = await clienteFalso({ rpc: { data: null, error: null } }).puerto.ejecutar({ tipo: "ingreso", productoId: P1, cantidad: 1, motivo: null }, "k");
    expect(a).toEqual({ ok: false, error: MENSAJE_RESULTADO_DESCONOCIDO, incierto: true });
    expect(b).toEqual({ ok: false, error: MENSAJE_RESULTADO_DESCONOCIDO, incierto: true });
  });
});


const INGRESO = { tipo: "ingreso", productoId: P1, cantidad: 4, motivo: null } as const;
const deadlock = { message: "deadlock detected", code: "40P01", details: "", hint: "" };
const serializacion = { message: "could not serialize access", code: "40001", details: "", hint: "" };
const OK: Respuesta = { data: OP, error: null };
const falla = (error: unknown): Respuesta => ({ data: null, error });

describe("clasificación de errores (P13-stock)", () => {
  it.each([
    [{ code: "40001", message: "x" }, "concurrencia"],
    [{ code: "40P01", message: "x" }, "concurrencia"],
    [{ code: "", message: "TypeError: Failed to fetch" }, "desconocido"],
    [{ message: "sin código" }, "desconocido"],
    [null, "otro"],
    [{ code: "PT409", message: "stock_insuficiente" }, "negocio"],
    [{ code: "PT400", message: "otro_texto" }, "negocio"],
    [{ code: "PT500", message: "stock_error_interno" }, "negocio"],
    [{ code: "PT403", message: "stock_no_autorizado" }, "sin_permiso"],
    [{ code: "42501", message: "permission denied" }, "sin_permiso"],
    // 55P03 y 57014 NO se reintentan solos: la ADR los admite sólo bajo condiciones que no se cumplen.
    [{ code: "55P03", message: "lock not available" }, "otro"],
    [{ code: "57014", message: "canceling statement" }, "otro"],
    [{ code: "23505", message: "duplicate key" }, "otro"],
    [{ code: "PGRST301", message: "JWT expired" }, "otro"],
  ])("%j → %s", (error, clase) => {
    expect(clasificarErrorStock(error)).toBe(clase);
  });

  it("un código stock_* gana sobre un código reintentable aparente", () => {
    expect(clasificarErrorStock({ code: "40001", message: "stock_insuficiente" })).toBe("negocio");
  });
});

describe("reintentos (P13-stock: máximo 3, misma clave y mismo payload)", () => {
  it("el máximo es 3 intentos", () => {
    expect(MAX_INTENTOS).toBe(3);
  });

  it.each([
    ["40001", serializacion],
    ["40P01", deadlock],
  ])("%s: reintenta y tiene éxito en el 2.º intento con la misma clave y payload", async (_c, error) => {
    const { puerto, rpcs } = clienteFalso({ secuencia: [falla(error), OK] });
    const r = await puerto.ejecutar(INGRESO, "clave-fija");
    expect(r).toEqual({ ok: true, datos: OP });
    expect(rpcs).toHaveLength(2);
    expect(rpcs[1]).toEqual(rpcs[0]);
    expect(rpcs[0].argumentos.p_idempotency_key).toBe("clave-fija");
  });

  it("éxito en el 3.er intento (límite)", async () => {
    const { puerto, rpcs } = clienteFalso({ secuencia: [falla(deadlock), falla(serializacion), OK] });
    expect(await puerto.ejecutar(INGRESO, "k")).toEqual({ ok: true, datos: OP });
    expect(rpcs).toHaveLength(3);
    expect(new Set(rpcs.map((x) => JSON.stringify(x))).size).toBe(1);
  });

  it("agotados los 3 intentos ante 40P01: se detiene, mensaje claro y sin incierto", async () => {
    const { puerto, rpcs } = clienteFalso({ secuencia: [falla(deadlock)] });
    const r = await puerto.ejecutar(INGRESO, "k");
    expect(rpcs).toHaveLength(3);
    expect(r).toEqual({ ok: false, error: MENSAJE_CONCURRENCIA_AGOTADA });
  });

  it("agotados los 3 intentos por fallo de red: resultado incierto", async () => {
    const red = { message: "TypeError: Failed to fetch", code: "" };
    const { puerto, rpcs } = clienteFalso({ secuencia: [falla(red)] });
    const r = await puerto.ejecutar(INGRESO, "k");
    expect(rpcs).toHaveLength(3);
    expect(r).toEqual({ ok: false, error: MENSAJE_RESULTADO_DESCONOCIDO, incierto: true });
  });

  it("una excepción lanzada también se reintenta y agota en 3", async () => {
    const { puerto, rpcs } = clienteFalso({ secuencia: ["lanzar"] });
    const r = await puerto.ejecutar(INGRESO, "k");
    expect(rpcs).toHaveLength(3);
    expect(r).toMatchObject({ ok: false, incierto: true });
  });

  it("red y luego éxito: un solo efecto lógico (misma clave en ambos intentos)", async () => {
    const { puerto, rpcs } = clienteFalso({ secuencia: ["lanzar", OK] });
    expect(await puerto.ejecutar(INGRESO, "k9")).toEqual({ ok: true, datos: OP });
    expect(rpcs.map((x) => x.argumentos.p_idempotency_key)).toEqual(["k9", "k9"]);
  });

  it.each([
    ["stock_insuficiente", "PT409"],
    ["stock_conflicto_idempotencia", "PT409"],
    ["stock_no_autorizado", "PT403"],
    ["stock_error_interno", "PT500"],
    ["stock_cantidad_invalida", "PT400"],
  ])("%s (%s) nunca se reintenta", async (message, code) => {
    const { puerto, rpcs } = clienteFalso({ secuencia: [falla({ message, code })] });
    const r = await puerto.ejecutar(INGRESO, "k");
    expect(rpcs).toHaveLength(1);
    expect(r.ok).toBe(false);
    expect(r).not.toHaveProperty("incierto");
  });

  it.each(["55P03", "57014", "23505", "PGRST301", "42501"])("%s no se reintenta automáticamente", async (code) => {
    const { puerto, rpcs } = clienteFalso({ secuencia: [falla({ message: "x", code })] });
    await puerto.ejecutar(INGRESO, "k");
    expect(rpcs).toHaveLength(1);
  });

  it("un error de negocio después de un reintento corta el bucle", async () => {
    const { puerto, rpcs } = clienteFalso({
      secuencia: [falla(deadlock), falla({ message: "stock_insuficiente", code: "PT409" })],
    });
    const r = await puerto.ejecutar(
      { tipo: "cuarentena", productoId: P1, origenId: DEP, cantidad: 9, motivo: "m" },
      "k"
    );
    expect(rpcs).toHaveLength(2);
    expect(r).toEqual({ ok: false, error: "No hay stock suficiente en el depósito." });
  });

  it("aplica a las tres RPC", async () => {
    for (const intento of [
      INGRESO,
      { tipo: "cuarentena", productoId: P1, origenId: DEP, cantidad: 1, motivo: "m" },
      { tipo: "merma", productoId: P1, origenId: DEP, cantidad: 1, motivoCodigo: "vencido", motivo: null },
    ] as const) {
      const { puerto, rpcs } = clienteFalso({ secuencia: [falla(serializacion), OK] });
      expect((await puerto.ejecutar(intento, "k")).ok).toBe(true);
      expect(rpcs).toHaveLength(2);
    }
  });

  it("éxito sin id devuelto: incierto, sin bucle", async () => {
    const { puerto, rpcs } = clienteFalso({ secuencia: [{ data: null, error: null }] });
    const r = await puerto.ejecutar(INGRESO, "k");
    expect(rpcs).toHaveLength(1);
    expect(r).toMatchObject({ ok: false, incierto: true });
  });

  it("el mensaje de resultado desconocido no promete idempotencia después de recargar", () => {
    expect(MENSAJE_RESULTADO_DESCONOCIDO).toContain("sin recargar");
    expect(MENSAJE_RESULTADO_DESCONOCIDO).toContain("revisá el stock");
  });
});
