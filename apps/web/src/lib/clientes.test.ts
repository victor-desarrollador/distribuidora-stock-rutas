import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import { ROLES } from "../auth/roles";
import {
  MENSAJE_ERROR_GENERICO,
  MENSAJE_ERROR_LECTURA,
  MENSAJE_NOMBRE_REQUERIDO,
  MENSAJE_TELEFONO_REQUERIDO,
  crearPuertoClientes,
  filaACliente,
  mensajeErrorClientes,
  normalizarDatosCliente,
  permisosClientes,
  validarDatosCliente,
} from "./clientes";

const filaValidada = {
  id: "11111111-1111-4111-8111-111111111111",
  nombre: "Pedro Gómez",
  comercio: "Almacén Don Pedro",
  direccion: "Belgrano 1250",
  telefono: "3815551234",
  activo: true,
  estado_validacion: "validado",
};

const filaPendienteMinima = {
  id: "22222222-2222-4222-8222-222222222222",
  nombre: "Marta Díaz",
  comercio: null,
  direccion: null,
  telefono: "llamar a la tarde",
  activo: false,
  estado_validacion: "pendiente",
};

type Respuesta = { data: unknown; error: unknown };

// Cliente falso: registra las llamadas y responde lo configurado. `from` sólo
// ofrece `select`: cualquier insert/update/delete directo lanzaría.
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
    puerto: crearPuertoClientes(cliente as unknown as SupabaseClient),
    llamadas,
  };
}

const lanzar = () => {
  throw new Error("fallo de red");
};

describe("normalizarDatosCliente", () => {
  it("recorta todos los textos", () => {
    expect(
      normalizarDatosCliente({
        nombre: "  Juan  ",
        telefono: " 3815551111 ",
        comercio: "  Kiosco ",
        direccion: " Mitre 100  ",
      })
    ).toEqual({
      nombre: "Juan",
      telefono: "3815551111",
      comercio: "Kiosco",
      direccion: "Mitre 100",
    });
  });

  it("convierte comercio y dirección vacíos o de espacios en null", () => {
    expect(
      normalizarDatosCliente({
        nombre: "Juan",
        telefono: "1",
        comercio: "   ",
        direccion: "",
      })
    ).toEqual({ nombre: "Juan", telefono: "1", comercio: null, direccion: null });
  });

  it("no impone formato de teléfono ni toca los espacios internos", () => {
    expect(
      normalizarDatosCliente({
        nombre: "A  B",
        telefono: "+54 (381) 555-1234 int. 2",
        comercio: "",
        direccion: "",
      })
    ).toMatchObject({ nombre: "A  B", telefono: "+54 (381) 555-1234 int. 2" });
  });
});

describe("validarDatosCliente", () => {
  const base = { nombre: "Juan", telefono: "1", comercio: null, direccion: null };

  it("acepta nombre y teléfono, con comercio y dirección opcionales", () => {
    expect(validarDatosCliente(base)).toBeNull();
  });

  it("exige el nombre", () => {
    expect(validarDatosCliente({ ...base, nombre: "" })).toBe(
      MENSAJE_NOMBRE_REQUERIDO
    );
  });

  it("exige el teléfono", () => {
    expect(validarDatosCliente({ ...base, telefono: "" })).toBe(
      MENSAJE_TELEFONO_REQUERIDO
    );
  });
});

describe("permisosClientes", () => {
  it("dueño y encargado crean, editan, validan y activan/desactivan", () => {
    for (const rol of ["dueno", "encargado"] as const) {
      expect(permisosClientes(rol)).toEqual({
        puedeCrear: true,
        puedeEditar: true,
        puedeValidar: true,
        puedeCambiarEstado: true,
      });
    }
  });

  it("el vendedor/piloto sólo puede crear", () => {
    expect(permisosClientes("vendedor_piloto")).toEqual({
      puedeCrear: true,
      puedeEditar: false,
      puedeValidar: false,
      puedeCambiarEstado: false,
    });
  });

  it("sin rol no hay ninguna acción", () => {
    expect(permisosClientes(undefined)).toEqual({
      puedeCrear: false,
      puedeEditar: false,
      puedeValidar: false,
      puedeCambiarEstado: false,
    });
  });

  it("ningún rol vigente fuera de dueño/encargado edita o valida", () => {
    const conEdicion = ROLES.filter((r) => permisosClientes(r).puedeEditar);
    expect(conEdicion).toEqual(["dueno", "encargado"]);
    const conValidacion = ROLES.filter((r) => permisosClientes(r).puedeValidar);
    expect(conValidacion).toEqual(["dueno", "encargado"]);
  });
});

describe("filaACliente", () => {
  it("convierte una fila validada completa", () => {
    expect(filaACliente(filaValidada)).toEqual({
      id: filaValidada.id,
      nombre: "Pedro Gómez",
      comercio: "Almacén Don Pedro",
      direccion: "Belgrano 1250",
      telefono: "3815551234",
      activo: true,
      estadoValidacion: "validado",
    });
  });

  it("conserva los opcionales nulos y el estado pendiente", () => {
    expect(filaACliente(filaPendienteMinima)).toEqual({
      id: filaPendienteMinima.id,
      nombre: "Marta Díaz",
      comercio: null,
      direccion: null,
      telefono: "llamar a la tarde",
      activo: false,
      estadoValidacion: "pendiente",
    });
  });

  it("falla cerrado ante filas inesperadas", () => {
    const invalidas: unknown[] = [
      null,
      "texto",
      42,
      { ...filaValidada, id: "" },
      { ...filaValidada, nombre: "  " },
      { ...filaValidada, telefono: "" },
      { ...filaValidada, telefono: null },
      { ...filaValidada, comercio: "" },
      { ...filaValidada, direccion: 5 },
      { ...filaValidada, activo: "si" },
      { ...filaValidada, estado_validacion: "aprobado" },
      { ...filaValidada, estado_validacion: null },
      { ...filaValidada, empresa_id: "x" },
      { id: filaValidada.id },
    ];
    for (const fila of invalidas) {
      expect(filaACliente(fila)).toBeNull();
    }
  });
});

describe("mensajeErrorClientes", () => {
  it("traduce cada código estable de las RPC", () => {
    const casos: Array<[string, string]> = [
      ["cliente_no_autenticado", "Tu sesión no es válida. Volvé a iniciar sesión."],
      ["cliente_no_autorizado", "No tenés permiso para realizar esta acción."],
      ["cliente_no_encontrado", "El cliente ya no existe o no pertenece a tu empresa."],
      ["cliente_nombre_invalido", MENSAJE_NOMBRE_REQUERIDO],
      ["cliente_telefono_invalido", MENSAJE_TELEFONO_REQUERIDO],
      ["cliente_estado_invalido", "El estado del cliente no es válido."],
    ];
    for (const [message, esperado] of casos) {
      expect(mensajeErrorClientes({ code: "PT400", message })).toBe(esperado);
    }
  });

  it("traduce 42501 a un mensaje seguro de permisos", () => {
    expect(
      mensajeErrorClientes({ code: "42501", message: "permission denied for table clientes" })
    ).toBe("No tenés permiso para realizar esta acción.");
  });

  it("no inventa un duplicado: cualquier otro código da el mensaje genérico", () => {
    expect(mensajeErrorClientes({ code: "PT409", message: "cliente_duplicado" })).toBe(
      MENSAJE_ERROR_GENERICO
    );
    expect(mensajeErrorClientes({ code: "PT500", message: "cliente_error_interno" })).toBe(
      MENSAJE_ERROR_GENERICO
    );
  });

  it("no usa propiedades heredadas del prototipo como código", () => {
    expect(mensajeErrorClientes({ message: "toString" })).toBe(MENSAJE_ERROR_GENERICO);
    expect(mensajeErrorClientes({ message: "constructor" })).toBe(MENSAJE_ERROR_GENERICO);
  });

  it("nunca expone SQL, nombre de restricción ni detalle de PostgREST", () => {
    const filtrados = [
      { code: "23514", message: 'violates check constraint "clientes_nombre_normalizado"' },
      { code: "PGRST202", message: "Could not find the function public.crear_cliente" },
      "texto suelto",
      null,
      undefined,
    ];
    for (const error of filtrados) {
      expect(mensajeErrorClientes(error)).toBe(MENSAJE_ERROR_GENERICO);
    }
  });
});

describe("crearPuertoClientes.listar", () => {
  it("lee las columnas exactas ordenadas por nombre", async () => {
    const { puerto, llamadas } = clienteFalso({
      lectura: { data: [filaValidada, filaPendienteMinima], error: null },
    });

    const resultado = await puerto.listar();

    expect(llamadas.tabla).toBe("clientes");
    expect(llamadas.columnas).toBe(
      "id, nombre, comercio, direccion, telefono, activo, estado_validacion"
    );
    expect(llamadas.orden).toBe("nombre");
    expect(resultado.ok).toBe(true);
    if (resultado.ok) {
      expect(resultado.datos.map((c) => c.estadoValidacion)).toEqual([
        "validado",
        "pendiente",
      ]);
    }
  });

  it("devuelve una lista vacía cuando no hay clientes", async () => {
    const { puerto } = clienteFalso({ lectura: { data: [], error: null } });
    expect(await puerto.listar()).toEqual({ ok: true, datos: [] });
  });

  it("falla con el mensaje de lectura ante un error de la base", async () => {
    const { puerto } = clienteFalso({
      lectura: { data: null, error: { code: "42501", message: "permission denied" } },
    });
    expect(await puerto.listar()).toEqual({ ok: false, error: MENSAJE_ERROR_LECTURA });
  });

  it("una fila inesperada invalida la lectura completa", async () => {
    const { puerto } = clienteFalso({
      lectura: { data: [filaValidada, { ...filaValidada, empresa_id: "x" }], error: null },
    });
    expect(await puerto.listar()).toEqual({ ok: false, error: MENSAJE_ERROR_LECTURA });
  });

  it("falla cerrado si la lectura lanza una excepción", async () => {
    const { puerto } = clienteFalso({ lectura: lanzar });
    expect(await puerto.listar()).toEqual({ ok: false, error: MENSAJE_ERROR_LECTURA });
  });
});

describe("crearPuertoClientes.crear", () => {
  it("llama crear_cliente con los cuatro campos y nada más", async () => {
    const { puerto, llamadas } = clienteFalso({
      rpc: { data: "33333333-3333-4333-8333-333333333333", error: null },
    });

    const resultado = await puerto.crear({
      nombre: "Juan",
      telefono: "1",
      comercio: null,
      direccion: "Mitre 100",
    });

    expect(resultado).toEqual({ ok: true, datos: "33333333-3333-4333-8333-333333333333" });
    expect(llamadas.rpc).toEqual({
      nombre: "crear_cliente",
      argumentos: {
        p_nombre: "Juan",
        p_telefono: "1",
        p_comercio: null,
        p_direccion: "Mitre 100",
      },
    });
    expect(Object.keys(llamadas.rpc?.argumentos ?? {})).not.toContain("p_empresa_id");
    expect(Object.keys(llamadas.rpc?.argumentos ?? {})).not.toContain("p_creado_por");
  });

  it("traduce un error estable de la RPC", async () => {
    const { puerto } = clienteFalso({
      rpc: { data: null, error: { code: "PT403", message: "cliente_no_autorizado" } },
    });
    expect(
      await puerto.crear({ nombre: "A", telefono: "1", comercio: null, direccion: null })
    ).toEqual({ ok: false, error: "No tenés permiso para realizar esta acción." });
  });

  it("falla si la RPC no devuelve un id", async () => {
    const { puerto } = clienteFalso({ rpc: { data: null, error: null } });
    expect(
      await puerto.crear({ nombre: "A", telefono: "1", comercio: null, direccion: null })
    ).toEqual({ ok: false, error: MENSAJE_ERROR_GENERICO });
  });

  it("falla con mensaje genérico si la llamada lanza", async () => {
    const { puerto } = clienteFalso({ rpc: lanzar });
    expect(
      await puerto.crear({ nombre: "A", telefono: "1", comercio: null, direccion: null })
    ).toEqual({ ok: false, error: MENSAJE_ERROR_GENERICO });
  });
});

describe("crearPuertoClientes.actualizar", () => {
  it("llama actualizar_cliente con id y los cuatro campos, sin empresa_id", async () => {
    const { puerto, llamadas } = clienteFalso({ rpc: { data: null, error: null } });

    const resultado = await puerto.actualizar("id-1", {
      nombre: "Juan",
      telefono: "1",
      comercio: null,
      direccion: null,
    });

    expect(resultado).toEqual({ ok: true, datos: null });
    expect(llamadas.rpc).toEqual({
      nombre: "actualizar_cliente",
      argumentos: {
        p_cliente_id: "id-1",
        p_nombre: "Juan",
        p_telefono: "1",
        p_comercio: null,
        p_direccion: null,
      },
    });
  });

  it("traduce PT404 y un error desconocido da el mensaje genérico", async () => {
    const datos = { nombre: "A", telefono: "1", comercio: null, direccion: null };

    const noEncontrado = clienteFalso({
      rpc: { data: null, error: { code: "PT404", message: "cliente_no_encontrado" } },
    });
    expect(await noEncontrado.puerto.actualizar("x", datos)).toEqual({
      ok: false,
      error: "El cliente ya no existe o no pertenece a tu empresa.",
    });

    const desconocido = clienteFalso({
      rpc: { data: null, error: { code: "XX000", message: "boom" } },
    });
    expect(await desconocido.puerto.actualizar("x", datos)).toEqual({
      ok: false,
      error: MENSAJE_ERROR_GENERICO,
    });
  });

  it("falla con mensaje genérico si la llamada lanza", async () => {
    const { puerto } = clienteFalso({ rpc: lanzar });
    expect(
      await puerto.actualizar("x", { nombre: "A", telefono: "1", comercio: null, direccion: null })
    ).toEqual({ ok: false, error: MENSAJE_ERROR_GENERICO });
  });
});

describe("crearPuertoClientes.validar", () => {
  it("llama validar_cliente sólo con el id", async () => {
    const { puerto, llamadas } = clienteFalso({ rpc: { data: null, error: null } });

    expect(await puerto.validar("id-1")).toEqual({ ok: true, datos: null });
    expect(llamadas.rpc).toEqual({
      nombre: "validar_cliente",
      argumentos: { p_cliente_id: "id-1" },
    });
  });

  it("traduce PT403 a un mensaje de permisos", async () => {
    const { puerto } = clienteFalso({
      rpc: { data: null, error: { code: "PT403", message: "cliente_no_autorizado" } },
    });
    expect(await puerto.validar("id-1")).toEqual({
      ok: false,
      error: "No tenés permiso para realizar esta acción.",
    });
  });

  it("falla con mensaje genérico si la llamada lanza", async () => {
    const { puerto } = clienteFalso({ rpc: lanzar });
    expect(await puerto.validar("id-1")).toEqual({ ok: false, error: MENSAJE_ERROR_GENERICO });
  });
});

describe("crearPuertoClientes.cambiarEstado", () => {
  it("llama cambiar_estado_cliente con los argumentos exactos", async () => {
    const { puerto, llamadas } = clienteFalso({ rpc: { data: null, error: null } });

    expect(await puerto.cambiarEstado("id-1", false)).toEqual({ ok: true, datos: null });
    expect(llamadas.rpc).toEqual({
      nombre: "cambiar_estado_cliente",
      argumentos: { p_cliente_id: "id-1", p_activo: false },
    });
  });

  it("traduce 42501 de forma segura", async () => {
    const { puerto } = clienteFalso({
      rpc: { data: null, error: { code: "42501", message: "permission denied for function" } },
    });
    expect(await puerto.cambiarEstado("id-1", true)).toEqual({
      ok: false,
      error: "No tenés permiso para realizar esta acción.",
    });
  });

  it("falla con mensaje genérico si la llamada lanza", async () => {
    const { puerto } = clienteFalso({ rpc: lanzar });
    expect(await puerto.cambiarEstado("id-1", true)).toEqual({
      ok: false,
      error: MENSAJE_ERROR_GENERICO,
    });
  });
});

describe("escrituras sólo por RPC", () => {
  it("ninguna mutación toca la tabla directamente", async () => {
    const { puerto, llamadas } = clienteFalso({
      rpc: { data: "33333333-3333-4333-8333-333333333333", error: null },
    });
    const datos = { nombre: "A", telefono: "1", comercio: null, direccion: null };

    await puerto.crear(datos);
    await puerto.actualizar("id-1", datos);
    await puerto.validar("id-1");
    await puerto.cambiarEstado("id-1", false);

    // `from` no se usó para escribir: sólo la lectura lo invoca.
    expect(llamadas.tabla).toBeUndefined();
    expect(llamadas.rpc?.nombre).toBe("cambiar_estado_cliente");
  });
});
