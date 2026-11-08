import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import {
  MENSAJE_ERROR_VENDEDORES,
  MENSAJE_SIN_PERMISO_VENDEDORES,
  RPC_LISTAR_VENDEDORES,
  crearPuertoVendedoresJornada,
  filaAVendedor,
} from "./vendedores_jornada";
import fuente from "./vendedores_jornada.ts?raw";

const ID_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ID_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ID_C = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

type Respuesta = { data?: unknown; error?: unknown; count?: number | null } | "lanzar";

function clienteFalso(respuesta: Respuesta) {
  const llamadas: Array<{ nombre: string; argumentos: unknown; opciones: unknown }> = [];
  const cliente = {
    rpc(nombre: string, argumentos: unknown, opciones: unknown) {
      llamadas.push({ nombre, argumentos, opciones });
      if (respuesta === "lanzar") return Promise.reject(new Error("red caída"));
      return Promise.resolve({ data: null, error: null, count: null, ...respuesta });
    },
    from() {
      throw new Error("no debe leer tablas");
    },
  };
  return { cliente: cliente as unknown as SupabaseClient, llamadas };
}

const fila = (usuario_id: string, nombre: string, rol: string) => ({ usuario_id, nombre, rol });
const filas = [
  fila(ID_B, "Ana", "vendedor_piloto"),
  fila(ID_A, "Bruno", "dueno"),
  fila(ID_C, "Carla", "encargado"),
];

async function listar(respuesta: Respuesta) {
  const { cliente, llamadas } = clienteFalso(respuesta);
  const r = await crearPuertoVendedoresJornada(cliente).listarVendedores();
  return { r, llamadas };
}

describe("listar_vendedores_jornada: contrato", () => {
  it("invoca la RPC aprobada sin parámetros y con conteo exacto", async () => {
    const { llamadas } = await listar({ data: filas, count: 3 });
    expect(RPC_LISTAR_VENDEDORES).toBe("listar_vendedores_jornada");
    expect(llamadas).toEqual([
      { nombre: "listar_vendedores_jornada", argumentos: {}, opciones: { count: "exact" } },
    ]);
  });

  it("devuelve los tres roles aprobados en el orden del servidor", async () => {
    const { r } = await listar({ data: filas, count: 3 });
    expect(r).toEqual({
      ok: true,
      vendedores: [
        { usuarioId: ID_B, nombre: "Ana", rol: "vendedor_piloto" },
        { usuarioId: ID_A, nombre: "Bruno", rol: "dueno" },
        { usuarioId: ID_C, nombre: "Carla", rol: "encargado" },
      ],
    });
  });

  it("lista vacía: éxito sin vendedores (nunca se inventa uno)", async () => {
    expect((await listar({ data: [], count: 0 })).r).toEqual({ ok: true, vendedores: [] });
  });

  it("normaliza el uuid a minúsculas", async () => {
    const { r } = await listar({ data: [fila(ID_A.toUpperCase(), "Bruno", "dueno")], count: 1 });
    expect(r.ok && r.vendedores[0].usuarioId).toBe(ID_A);
  });
});

describe("listar_vendedores_jornada: falla cerrada (nunca una lista parcial)", () => {
  const casos: Array<[string, unknown]> = [
    ["expone el usuario de login", { ...fila(ID_A, "Bruno", "dueno"), usuario: "bruno" }],
    ["expone el correo", { ...fila(ID_A, "Bruno", "dueno"), email: "b@x.invalid" }],
    ["incluye `activo`", { ...fila(ID_A, "Bruno", "dueno"), activo: true }],
    ["le falta el rol", { usuario_id: ID_A, nombre: "Bruno" }],
    ["uuid inválido", fila("no-es-uuid", "Bruno", "dueno")],
    ["nombre vacío", fila(ID_A, "   ", "dueno")],
    ["nombre no texto", { usuario_id: ID_A, nombre: 7, rol: "dueno" }],
    ["rol no aprobado", fila(ID_A, "Bruno", "admin")],
    ["fila nula", null],
    ["fila arreglo", [ID_A, "Bruno", "dueno"]],
  ];

  it.each(casos)("fila que %s → error y ningún vendedor", async (_d, mala) => {
    expect(filaAVendedor(mala)).toBeNull();
    const { r } = await listar({ data: [filas[0], mala], count: 2 });
    expect(r).toEqual({ ok: false, mensaje: MENSAJE_ERROR_VENDEDORES });
  });

  it("usuario repetido → error", async () => {
    const { r } = await listar({ data: [filas[0], filas[0]], count: 2 });
    expect(r).toEqual({ ok: false, mensaje: MENSAJE_ERROR_VENDEDORES });
  });

  it("conteo ausente o distinto de las filas (truncamiento) → error", async () => {
    for (const count of [null, 2, 4, undefined]) {
      const { r } = await listar({ data: filas, count: count as number | null });
      expect(r).toEqual({ ok: false, mensaje: MENSAJE_ERROR_VENDEDORES });
    }
  });

  it("datos que no son un arreglo → error", async () => {
    expect((await listar({ data: { usuario_id: ID_A }, count: 1 })).r.ok).toBe(false);
    expect((await listar({ data: null, count: 0 })).r.ok).toBe(false);
  });
});

describe("listar_vendedores_jornada: errores", () => {
  it("rechazo de permisos (42501 o PT403) → mensaje de permiso", async () => {
    for (const code of ["42501", "PT403"]) {
      const { r } = await listar({ error: { code, message: "permission denied for function" } });
      expect(r).toEqual({ ok: false, mensaje: MENSAJE_SIN_PERMISO_VENDEDORES });
    }
  });

  it("cualquier otro error → mensaje genérico, sin filtrar el detalle del servidor", async () => {
    const { r } = await listar({ error: { code: "XX000", message: "relation privado.x does not exist" } });
    expect(r).toEqual({ ok: false, mensaje: MENSAJE_ERROR_VENDEDORES });
  });

  it("excepción de red → mensaje genérico, sin reintentos automáticos", async () => {
    const { r, llamadas } = await listar("lanzar");
    expect(r).toEqual({ ok: false, mensaje: MENSAJE_ERROR_VENDEDORES });
    expect(llamadas).toHaveLength(1);
  });
});

describe("listar_vendedores_jornada: evidencia estructural", () => {
  const codigo = fuente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");

  it("sin almacenamiento del navegador ni escrituras", () => {
    expect(/localStorage|sessionStorage|indexedDB/i.test(codigo)).toBe(false);
    expect(/\.(insert|update|upsert|delete)\(|\.from\(/.test(codigo)).toBe(false);
  });

  it("una sola RPC: la del contrato aprobado", () => {
    expect([...codigo.matchAll(/\.rpc\(/g)]).toHaveLength(1);
    expect(codigo).toMatch(/\.rpc\(\s*RPC_LISTAR_VENDEDORES,\s*\{\},/);
  });
});
