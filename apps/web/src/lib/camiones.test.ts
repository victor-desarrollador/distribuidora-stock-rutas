import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import {
  MENSAJE_ERROR_GENERICO,
  MENSAJE_ERROR_LECTURA,
  crearPuertoCamiones,
  filaACamion,
  mensajeErrorCamiones,
} from "./camiones";

const filaActiva = {
  id: "11111111-1111-4111-8111-111111111111",
  patente: "AA111AA",
  nombre: "Camión 1",
  activo: true,
};

const filaInactiva = {
  id: "22222222-2222-4222-8222-222222222222",
  patente: "ab 222 bb",
  nombre: "Camión 2",
  activo: false,
};

type Respuesta = { data: unknown; error: unknown };

// Cliente falso: registra las llamadas y responde lo configurado.
function clienteFalso(opciones: {
  lectura?: Respuesta | (() => never);
  rpc?: Respuesta | (() => never);
}) {
  const llamadas: {
    tabla?: string;
    columnas?: string;
    orden?: string;
    rpc?: { nombre: string; argumentos: Record<string, unknown> };
  } = {};

  const responder = (r: Respuesta | (() => never) | undefined) => {
    if (typeof r === "function") return r();
    return Promise.resolve(r ?? { data: null, error: null });
  };

  const cliente = {
    from(tabla: string) {
      llamadas.tabla = tabla;
      return {
        select(columnas: string) {
          llamadas.columnas = columnas;
          return {
            order(columna: string) {
              llamadas.orden = columna;
              return responder(opciones.lectura);
            },
          };
        },
      };
    },
    rpc(nombre: string, argumentos: Record<string, unknown>) {
      llamadas.rpc = { nombre, argumentos };
      return responder(opciones.rpc);
    },
  };

  return {
    puerto: crearPuertoCamiones(cliente as unknown as SupabaseClient),
    llamadas,
  };
}

const lanzar = () => {
  throw new Error("fallo de red");
};

describe("filaACamion", () => {
  it("convierte una fila válida y conserva la patente tal como viene", () => {
    expect(filaACamion(filaActiva)).toEqual({
      id: filaActiva.id,
      patente: "AA111AA",
      nombre: "Camión 1",
      activo: true,
    });
    expect(filaACamion(filaInactiva)).toMatchObject({
      patente: "ab 222 bb",
      activo: false,
    });
  });

  it.each([
    ["sin fila", null],
    ["fila no objeto", "camion"],
    ["id vacío", { ...filaActiva, id: "" }],
    ["id numérico", { ...filaActiva, id: 7 }],
    ["patente vacía", { ...filaActiva, patente: "" }],
    ["patente de espacios", { ...filaActiva, patente: "   " }],
    ["patente nula", { ...filaActiva, patente: null }],
    ["nombre vacío", { ...filaActiva, nombre: "" }],
    ["nombre numérico", { ...filaActiva, nombre: 5 }],
    ["activo como texto", { ...filaActiva, activo: "true" }],
    ["activo nulo", { ...filaActiva, activo: null }],
    ["columna faltante", { id: filaActiva.id, patente: "X1", nombre: "X" }],
    ["columna de más (empresa_id)", { ...filaActiva, empresa_id: "e" }],
    ["columna de más (marca)", { ...filaActiva, marca: "Iveco" }],
  ])("falla cerrado ante %s", (_caso, fila) => {
    expect(filaACamion(fila)).toBeNull();
  });
});

describe("mensajeErrorCamiones", () => {
  it.each([
    ["camion_no_autenticado", "sesión no es válida"],
    ["camion_no_autorizado", "No tenés permiso"],
    ["camion_no_encontrado", "ya no existe"],
    ["camion_patente_invalida", "la patente"],
    ["camion_nombre_invalido", "el nombre"],
    ["camion_estado_invalido", "estado del camión"],
    ["camion_patente_duplicada", "Ya existe otro camión con esa patente"],
  ])("traduce el código estable %s", (codigo, texto) => {
    expect(mensajeErrorCamiones({ code: "PT400", message: codigo })).toContain(
      texto
    );
  });

  it("traduce 42501 a un mensaje seguro de permisos", () => {
    expect(
      mensajeErrorCamiones({
        code: "42501",
        message: 'permission denied for function crear_camion',
      })
    ).toBe("No tenés permiso para modificar camiones.");
  });

  it.each([
    ["camion_error_interno", { code: "PT500", message: "camion_error_interno" }],
    [
      "error SQL crudo",
      {
        code: "23505",
        message:
          'duplicate key value violates unique constraint "camiones_patente_unica"',
        details: "Key (empresa_id, patente)=(e, AA111AA) already exists.",
      },
    ],
    ["objeto vacío", {}],
    ["null", null],
    ["texto", "boom"],
    ["code PT500 sin mensaje conocido", { code: "PT500", message: "otra cosa" }],
  ])("devuelve el mensaje genérico ante %s", (_caso, error) => {
    expect(mensajeErrorCamiones(error)).toBe(MENSAJE_ERROR_GENERICO);
  });

  it("no usa propiedades heredadas del prototipo como código", () => {
    expect(mensajeErrorCamiones({ message: "constructor" })).toBe(
      MENSAJE_ERROR_GENERICO
    );
    expect(mensajeErrorCamiones({ message: "toString" })).toBe(
      MENSAJE_ERROR_GENERICO
    );
  });

  it("nunca expone SQL, nombre de restricción ni detalle de PostgREST", () => {
    const crudo = {
      code: "23505",
      message:
        'duplicate key value violates unique constraint "camiones_patente_unica"',
      details: "Key (empresa_id, patente)=(abc, X) already exists.",
      hint: "revisar",
    };
    const texto = mensajeErrorCamiones(crudo);
    expect(texto).not.toMatch(/duplicate|constraint|camiones_|empresa_id|Key/i);
  });
});

describe("crearPuertoCamiones.listar", () => {
  it("lee las columnas exactas ordenadas por nombre", async () => {
    const { puerto, llamadas } = clienteFalso({
      lectura: { data: [filaActiva, filaInactiva], error: null },
    });

    const resultado = await puerto.listar();

    expect(llamadas.tabla).toBe("camiones");
    expect(llamadas.columnas).toBe("id, patente, nombre, activo");
    expect(llamadas.orden).toBe("nombre");
    expect(resultado).toEqual({
      ok: true,
      datos: [
        { id: filaActiva.id, patente: "AA111AA", nombre: "Camión 1", activo: true },
        {
          id: filaInactiva.id,
          patente: "ab 222 bb",
          nombre: "Camión 2",
          activo: false,
        },
      ],
    });
  });

  it("devuelve una lista vacía cuando no hay camiones", async () => {
    const { puerto } = clienteFalso({ lectura: { data: [], error: null } });
    expect(await puerto.listar()).toEqual({ ok: true, datos: [] });
  });

  it("falla con el mensaje de lectura ante un error de la base", async () => {
    const { puerto } = clienteFalso({
      lectura: {
        data: null,
        error: { code: "42501", message: "permission denied for table camiones" },
      },
    });
    expect(await puerto.listar()).toEqual({
      ok: false,
      error: MENSAJE_ERROR_LECTURA,
    });
  });

  it("falla si la respuesta no es una lista", async () => {
    const { puerto } = clienteFalso({ lectura: { data: null, error: null } });
    expect(await puerto.listar()).toEqual({
      ok: false,
      error: MENSAJE_ERROR_LECTURA,
    });
  });

  it("una fila inesperada invalida la lectura completa", async () => {
    const { puerto } = clienteFalso({
      lectura: {
        data: [filaActiva, { ...filaInactiva, activo: "no" }],
        error: null,
      },
    });
    expect(await puerto.listar()).toEqual({
      ok: false,
      error: MENSAJE_ERROR_LECTURA,
    });
  });

  it("falla cerrado si la lectura lanza una excepción", async () => {
    const { puerto } = clienteFalso({ lectura: lanzar });
    expect(await puerto.listar()).toEqual({
      ok: false,
      error: MENSAJE_ERROR_LECTURA,
    });
  });
});

describe("crearPuertoCamiones.crear", () => {
  it("llama crear_camion con patente y nombre, sin empresa_id", async () => {
    const { puerto, llamadas } = clienteFalso({
      rpc: { data: "33333333-3333-4333-8333-333333333333", error: null },
    });

    const resultado = await puerto.crear({ patente: "CD123EF", nombre: "Norte" });

    expect(llamadas.rpc).toEqual({
      nombre: "crear_camion",
      argumentos: { p_patente: "CD123EF", p_nombre: "Norte" },
    });
    expect(Object.keys(llamadas.rpc?.argumentos ?? {})).not.toContain(
      "p_empresa_id"
    );
    expect(resultado).toEqual({
      ok: true,
      datos: "33333333-3333-4333-8333-333333333333",
    });
  });

  it("traduce un error estable de la RPC", async () => {
    const { puerto } = clienteFalso({
      rpc: {
        data: null,
        error: { code: "PT409", message: "camion_patente_duplicada" },
      },
    });
    expect(await puerto.crear({ patente: "AA111AA", nombre: "X" })).toEqual({
      ok: false,
      error: "Ya existe otro camión con esa patente.",
    });
  });

  it("falla si la RPC no devuelve un id", async () => {
    const { puerto } = clienteFalso({ rpc: { data: null, error: null } });
    expect(await puerto.crear({ patente: "A", nombre: "B" })).toEqual({
      ok: false,
      error: MENSAJE_ERROR_GENERICO,
    });
  });

  it("falla con mensaje genérico si la llamada lanza", async () => {
    const { puerto } = clienteFalso({ rpc: lanzar });
    expect(await puerto.crear({ patente: "A", nombre: "B" })).toEqual({
      ok: false,
      error: MENSAJE_ERROR_GENERICO,
    });
  });
});

describe("crearPuertoCamiones.actualizar", () => {
  it("llama actualizar_camion con id, patente y nombre, sin empresa_id", async () => {
    const { puerto, llamadas } = clienteFalso({
      rpc: { data: null, error: null },
    });

    const resultado = await puerto.actualizar(filaActiva.id, {
      patente: "AA111AB",
      nombre: "Camión 1 bis",
    });

    expect(llamadas.rpc).toEqual({
      nombre: "actualizar_camion",
      argumentos: {
        p_camion_id: filaActiva.id,
        p_patente: "AA111AB",
        p_nombre: "Camión 1 bis",
      },
    });
    expect(resultado).toEqual({ ok: true, datos: null });
  });

  it.each([
    ["PT403", "camion_no_autorizado", "No tenés permiso para modificar camiones."],
    ["PT404", "camion_no_encontrado", "El camión ya no existe o no pertenece a tu empresa."],
    ["PT400", "camion_nombre_invalido", "Ingresá el nombre del camión."],
    ["PT409", "camion_patente_duplicada", "Ya existe otro camión con esa patente."],
  ])("traduce %s %s", async (code, message, esperado) => {
    const { puerto } = clienteFalso({
      rpc: { data: null, error: { code, message } },
    });
    expect(
      await puerto.actualizar(filaActiva.id, { patente: "X", nombre: "Y" })
    ).toEqual({ ok: false, error: esperado });
  });

  it("un error desconocido da el mensaje genérico", async () => {
    const { puerto } = clienteFalso({
      rpc: {
        data: null,
        error: { code: "XX000", message: "relation \"camiones\" exploded" },
      },
    });
    expect(
      await puerto.actualizar(filaActiva.id, { patente: "X", nombre: "Y" })
    ).toEqual({ ok: false, error: MENSAJE_ERROR_GENERICO });
  });

  it("falla con mensaje genérico si la llamada lanza", async () => {
    const { puerto } = clienteFalso({ rpc: lanzar });
    expect(
      await puerto.actualizar(filaActiva.id, { patente: "X", nombre: "Y" })
    ).toEqual({ ok: false, error: MENSAJE_ERROR_GENERICO });
  });
});

describe("crearPuertoCamiones.cambiarEstado", () => {
  it("llama cambiar_estado_camion con los argumentos exactos", async () => {
    const { puerto, llamadas } = clienteFalso({
      rpc: { data: null, error: null },
    });

    const resultado = await puerto.cambiarEstado(filaActiva.id, false);

    expect(llamadas.rpc).toEqual({
      nombre: "cambiar_estado_camion",
      argumentos: { p_camion_id: filaActiva.id, p_activo: false },
    });
    expect(resultado).toEqual({ ok: true, datos: null });
  });

  it("traduce PT403 a un mensaje de permisos", async () => {
    const { puerto } = clienteFalso({
      rpc: {
        data: null,
        error: { code: "PT403", message: "camion_no_autorizado" },
      },
    });
    expect(await puerto.cambiarEstado(filaActiva.id, true)).toEqual({
      ok: false,
      error: "No tenés permiso para modificar camiones.",
    });
  });

  it("traduce 42501 de forma segura", async () => {
    const { puerto } = clienteFalso({
      rpc: {
        data: null,
        error: { code: "42501", message: "permission denied for function x" },
      },
    });
    expect(await puerto.cambiarEstado(filaActiva.id, true)).toEqual({
      ok: false,
      error: "No tenés permiso para modificar camiones.",
    });
  });

  it("falla con mensaje genérico si la llamada lanza", async () => {
    const { puerto } = clienteFalso({ rpc: lanzar });
    expect(await puerto.cambiarEstado(filaActiva.id, true)).toEqual({
      ok: false,
      error: MENSAJE_ERROR_GENERICO,
    });
  });
});
