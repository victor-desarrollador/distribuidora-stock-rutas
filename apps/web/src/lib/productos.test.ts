import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import {
  MENSAJE_ERROR_GENERICO,
  MENSAJE_ERROR_LECTURA,
  crearPuertoProductos,
  filaAProducto,
  mensajeErrorProductos,
} from "./productos";

const filaLacteo = {
  id: "11111111-1111-4111-8111-111111111111",
  codigo: "LAC-001",
  nombre: "Yogur bebible 1 L",
  categoria: "lacteos",
  forma_venta: "unidad",
  precio: 2300.5,
  stock_minimo: 20,
  activo: true,
};

const filaFiambre = {
  id: "22222222-2222-4222-8222-222222222222",
  codigo: null,
  nombre: "Jamón cocido",
  categoria: "fiambres",
  forma_venta: "pieza",
  precio: 21,
  stock_minimo: 9,
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
    puerto: crearPuertoProductos(cliente as unknown as SupabaseClient),
    llamadas,
  };
}

const lanzar = () => {
  throw new Error("fallo de red");
};

describe("filaAProducto", () => {
  it("convierte una fila de lácteo y una de fiambre", () => {
    expect(filaAProducto(filaLacteo)).toEqual({
      id: filaLacteo.id,
      codigo: "LAC-001",
      nombre: "Yogur bebible 1 L",
      categoria: "Lácteos",
      unidadMedida: "unidad",
      precio: 2300.5,
      stockMinimo: 20,
      activo: true,
    });
    expect(filaAProducto(filaFiambre)).toMatchObject({
      codigo: null,
      categoria: "Fiambres",
      unidadMedida: "pieza",
      activo: false,
    });
  });

  it.each([
    ["sin fila", null],
    ["categoría desconocida", { ...filaLacteo, categoria: "Lácteos" }],
    ["forma de venta kg", { ...filaLacteo, forma_venta: "kg" }],
    ["combinación inválida", { ...filaLacteo, forma_venta: "pieza" }],
    ["precio con 3 decimales", { ...filaLacteo, precio: 20.999 }],
    ["precio como texto", { ...filaLacteo, precio: "20.99" }],
    ["precio negativo", { ...filaLacteo, precio: -1 }],
    ["stock mínimo negativo", { ...filaLacteo, stock_minimo: -1 }],
    ["stock mínimo fraccionario", { ...filaLacteo, stock_minimo: 1.5 }],
    ["activo no booleano", { ...filaLacteo, activo: "true" }],
    ["código numérico", { ...filaLacteo, codigo: 7 }],
    ["id vacío", { ...filaLacteo, id: "" }],
  ])("falla cerrado ante %s", (_caso, fila) => {
    expect(filaAProducto(fila)).toBeNull();
  });
});

describe("mensajeErrorProductos", () => {
  it.each([
    ["producto_precio_invalido", "como máximo 2 decimales"],
    ["producto_no_autorizado", "No tenés permiso"],
    ["producto_no_encontrado", "ya no existe"],
    ["producto_codigo_duplicado", "Ya existe otro producto con ese código"],
    ["producto_combinacion_invalida", "por unidad"],
  ])("traduce el código estable %s", (codigo, texto) => {
    expect(
      mensajeErrorProductos({ code: "PT400", message: codigo })
    ).toContain(texto);
  });

  it("traduce la falta de permiso de ejecución (42501)", () => {
    expect(
      mensajeErrorProductos({
        code: "42501",
        message: "permission denied for function crear_producto",
      })
    ).toBe("No tenés permiso para modificar productos.");
  });

  it.each([
    [
      "detalle SQL crudo",
      {
        code: "23505",
        message:
          'duplicate key value violates unique constraint "productos_codigo_unico"',
        details: "Key (empresa_id, codigo)=(...) already exists.",
      },
    ],
    ["clave heredada del prototipo", { message: "toString" }],
    ["error sin forma", "boom"],
    ["nulo", null],
  ])("nunca expone %s: devuelve el mensaje genérico", (_caso, error) => {
    expect(mensajeErrorProductos(error)).toBe(MENSAJE_ERROR_GENERICO);
  });
});

describe("crearPuertoProductos.listar", () => {
  it("lee sólo las columnas del catálogo, ordenadas por nombre", async () => {
    const { puerto, llamadas } = clienteFalso({
      lectura: { data: [filaLacteo, filaFiambre], error: null },
    });

    const resultado = await puerto.listar();

    expect(resultado.ok).toBe(true);
    expect(resultado.ok && resultado.datos).toHaveLength(2);
    expect(llamadas.tabla).toBe("productos");
    expect(llamadas.columnas).toBe(
      "id, codigo, nombre, categoria, forma_venta, precio, stock_minimo, activo"
    );
    expect(llamadas.orden).toBe("nombre");
  });

  it.each([
    ["error de Supabase", { data: null, error: { message: "boom" } }],
    ["datos nulos", { data: null, error: null }],
    ["una fila inválida", { data: [filaLacteo, { ...filaFiambre, precio: 1.001 }], error: null }],
  ])("falla cerrado ante %s, sin devolver datos", async (_caso, respuesta) => {
    const { puerto } = clienteFalso({ lectura: respuesta });

    expect(await puerto.listar()).toEqual({
      ok: false,
      error: MENSAJE_ERROR_LECTURA,
    });
  });

  it("falla cerrado si la lectura lanza", async () => {
    const { puerto } = clienteFalso({ lectura: lanzar });

    expect(await puerto.listar()).toEqual({
      ok: false,
      error: MENSAJE_ERROR_LECTURA,
    });
  });
});

describe("crearPuertoProductos: escrituras por RPC", () => {
  it("crear envía los parámetros de la firma, sin empresa ni autor", async () => {
    const { puerto, llamadas } = clienteFalso({
      rpc: { data: filaLacteo.id, error: null },
    });

    const resultado = await puerto.crear({
      codigo: " FIA-9 ",
      nombre: "Salame",
      categoria: "Fiambres",
      unidadMedida: "pieza",
      precio: 9800.5,
      stockMinimo: 3,
    });

    expect(resultado).toEqual({ ok: true, datos: filaLacteo.id });
    expect(llamadas.rpc).toEqual({
      nombre: "crear_producto",
      argumentos: {
        p_codigo: " FIA-9 ",
        p_nombre: "Salame",
        p_categoria: "fiambres",
        p_forma_venta: "pieza",
        p_precio: 9800.5,
        p_stock_minimo: 3,
      },
    });
  });

  it("crear traduce el error estable de la base", async () => {
    const { puerto } = clienteFalso({
      rpc: {
        data: null,
        error: { code: "PT400", message: "producto_precio_invalido" },
      },
    });

    const resultado = await puerto.crear({
      codigo: "",
      nombre: "X",
      categoria: "Lácteos",
      unidadMedida: "unidad",
      precio: 1,
      stockMinimo: 0,
    });

    expect(resultado.ok).toBe(false);
    expect(!resultado.ok && resultado.error).toContain("2 decimales");
  });

  it("crear falla si la respuesta no trae un id", async () => {
    const { puerto } = clienteFalso({ rpc: { data: null, error: null } });

    expect(
      await puerto.crear({
        codigo: "",
        nombre: "X",
        categoria: "Lácteos",
        unidadMedida: "unidad",
        precio: 1,
        stockMinimo: 0,
      })
    ).toEqual({ ok: false, error: MENSAJE_ERROR_GENERICO });
  });

  it("actualizar no envía categoría ni forma de venta (DE-6)", async () => {
    const { puerto, llamadas } = clienteFalso({
      rpc: { data: null, error: null },
    });

    const resultado = await puerto.actualizar(filaLacteo.id, {
      codigo: "LAC-001",
      nombre: "Yogur",
      precio: 2400,
      stockMinimo: 10,
    });

    expect(resultado).toEqual({ ok: true, datos: null });
    expect(llamadas.rpc).toEqual({
      nombre: "actualizar_producto",
      argumentos: {
        p_producto_id: filaLacteo.id,
        p_codigo: "LAC-001",
        p_nombre: "Yogur",
        p_precio: 2400,
        p_stock_minimo: 10,
      },
    });
  });

  it("cambiarEstado envía sólo el id y el estado", async () => {
    const { puerto, llamadas } = clienteFalso({
      rpc: { data: null, error: null },
    });

    expect(await puerto.cambiarEstado(filaLacteo.id, false)).toEqual({
      ok: true,
      datos: null,
    });
    expect(llamadas.rpc).toEqual({
      nombre: "cambiar_estado_producto",
      argumentos: { p_producto_id: filaLacteo.id, p_activo: false },
    });
  });

  it("una escritura rechazada por otra empresa informa no encontrado", async () => {
    const { puerto } = clienteFalso({
      rpc: {
        data: null,
        error: { code: "PT404", message: "producto_no_encontrado" },
      },
    });

    const resultado = await puerto.cambiarEstado(filaLacteo.id, false);

    expect(!resultado.ok && resultado.error).toContain("ya no existe");
  });

  it("una escritura que lanza devuelve el mensaje genérico", async () => {
    const { puerto } = clienteFalso({ rpc: lanzar });

    expect(
      await puerto.actualizar(filaLacteo.id, {
        codigo: "",
        nombre: "X",
        precio: 1,
        stockMinimo: 0,
      })
    ).toEqual({ ok: false, error: MENSAJE_ERROR_GENERICO });
  });
});
