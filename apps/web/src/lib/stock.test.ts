import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import {
  MENSAJE_ERROR_GENERICO,
  MENSAJE_ERROR_LECTURA,
  MENSAJE_RESULTADO_DESCONOCIDO,
  MENSAJE_SIN_UBICACIONES,
  armarDatosStock,
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
const camiones = [{ id: CAMION, patente: "AB123CD", nombre: "Camión 1" }];
const saldos = [
  { ubicacion_id: DEP, producto_id: P1, cantidad: 40 },
  { ubicacion_id: DEP, producto_id: P2, cantidad: 12500 },
];

type Respuesta = { data: unknown; error: unknown };

function clienteFalso(opciones: {
  tablas?: Record<string, Respuesta>;
  rpc?: Respuesta | (() => never);
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
      const r = opciones.rpc;
      return typeof r === "function" ? r() : Promise.resolve(r ?? { data: OP, error: null });
    },
  };
  return { puerto: crearPuertoStock(cliente as unknown as SupabaseClient), consultas, rpcs };
}

const tablasOk = {
  ubicaciones: { data: ubicaciones, error: null },
  productos: { data: productos, error: null },
  camiones: { data: camiones, error: null },
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
      ["camiones", "productos", "stock_actual", "ubicaciones"]
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
  const base = { ubicaciones, productos, camiones, saldos };

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
    expect(r).toEqual({ ok: false, error: MENSAJE_RESULTADO_DESCONOCIDO });
    // Con código de PostgREST (error del servidor) sigue siendo genérico.
    expect(mensajeErrorStock({ message: "boom", code: "PT500" })).toBe(MENSAJE_ERROR_GENERICO);
  });

  it("fallo de red o respuesta sin id: resultado desconocido (no se asume éxito)", async () => {
    const lanzar = () => {
      throw new Error("fallo de red");
    };
    const a = await clienteFalso({ rpc: lanzar }).puerto.ejecutar({ tipo: "ingreso", productoId: P1, cantidad: 1, motivo: null }, "k");
    const b = await clienteFalso({ rpc: { data: null, error: null } }).puerto.ejecutar({ tipo: "ingreso", productoId: P1, cantidad: 1, motivo: null }, "k");
    expect(a).toEqual({ ok: false, error: MENSAJE_RESULTADO_DESCONOCIDO });
    expect(b).toEqual({ ok: false, error: MENSAJE_RESULTADO_DESCONOCIDO });
  });
});
