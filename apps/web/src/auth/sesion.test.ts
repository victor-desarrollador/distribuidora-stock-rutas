import { describe, expect, it, vi } from "vitest";

import {
  MENSAJE_CREDENCIALES,
  MENSAJE_ERROR_PERFIL,
  decidirAcceso,
  iniciarSesion,
  parsearPerfil,
  resolverEstadoSesion,
  type EstadoSesion,
  type PuertoAuth,
} from "./sesion";

const EMPRESA = { id: "emp-1", nombre: "Distribuidora", activo: true };

function filaPerfil(extra: Record<string, unknown> = {}) {
  return {
    usuario_id: "u-1",
    empresa_id: "emp-1",
    usuario: "juan",
    nombre: "Juan",
    rol: "vendedor_piloto",
    activo: true,
    ...extra,
  };
}

function puertoFalso(over: Partial<PuertoAuth> = {}): PuertoAuth {
  return {
    iniciarConPassword: vi.fn(async () => ({ error: null })),
    cerrarSesion: vi.fn(async () => undefined),
    alCambiarUsuario: vi.fn(() => () => undefined),
    leerPerfil: vi.fn(async () => filaPerfil()),
    leerEmpresa: vi.fn(async () => EMPRESA),
    ...over,
  };
}

describe("iniciarSesion", () => {
  it("llama a Auth con el identificador interno normalizado", async () => {
    const puerto = puertoFalso();

    const r = await iniciarSesion(puerto, "  Juan ", "secreta");

    expect(r).toEqual({ ok: true });
    expect(puerto.iniciarConPassword).toHaveBeenCalledExactlyOnceWith(
      "juan@usuarios.distribuidora.invalid",
      "secreta"
    );
  });

  it("credenciales incorrectas: mensaje genérico sin revelar si existe el usuario", async () => {
    const puerto = puertoFalso({
      iniciarConPassword: vi.fn(async () => ({ error: "credenciales" as const })),
    });

    const r = await iniciarSesion(puerto, "juan", "mala");

    expect(r).toEqual({ ok: false, mensaje: MENSAJE_CREDENCIALES });
  });

  it("error de red: mensaje distinto, sin éxito", async () => {
    const puerto = puertoFalso({
      iniciarConPassword: vi.fn(async () => {
        throw new Error("network");
      }),
    });

    const r = await iniciarSesion(puerto, "juan", "x");

    expect(r.ok).toBe(false);
  });

  it("usuario con formato inválido no llega a Auth", async () => {
    const puerto = puertoFalso();

    const r = await iniciarSesion(puerto, "juan@evil.com", "x");

    expect(r.ok).toBe(false);
    expect(puerto.iniciarConPassword).not.toHaveBeenCalled();
  });

  it("contraseña vacía no llega a Auth", async () => {
    const puerto = puertoFalso();

    const r = await iniciarSesion(puerto, "juan", "");

    expect(r.ok).toBe(false);
    expect(puerto.iniciarConPassword).not.toHaveBeenCalled();
  });
});

describe("resolverEstadoSesion", () => {
  it("sin usuario autenticado: no_autenticado, sin leer perfiles", async () => {
    const puerto = puertoFalso();

    expect(await resolverEstadoSesion(puerto, null)).toEqual({
      estado: "no_autenticado",
    });
    expect(puerto.leerPerfil).not.toHaveBeenCalled();
  });

  it("restaura la sesión: perfil activo y empresa visible => autenticado", async () => {
    const puerto = puertoFalso();

    const estado = await resolverEstadoSesion(puerto, "u-1");

    expect(estado).toEqual({
      estado: "autenticado",
      perfil: {
        usuarioId: "u-1",
        empresaId: "emp-1",
        usuario: "juan",
        nombre: "Juan",
        rol: "vendedor_piloto",
        activo: true,
      },
      empresa: EMPRESA,
    });
    expect(puerto.leerPerfil).toHaveBeenCalledWith("u-1");
    expect(puerto.leerEmpresa).toHaveBeenCalledWith("emp-1");
  });

  it("usuario sin perfil queda bloqueado", async () => {
    const puerto = puertoFalso({ leerPerfil: vi.fn(async () => null) });

    expect(await resolverEstadoSesion(puerto, "u-1")).toEqual({
      estado: "bloqueado",
      motivo: "sin_perfil",
    });
    expect(puerto.leerEmpresa).not.toHaveBeenCalled();
  });

  it("perfil inactivo queda bloqueado", async () => {
    const puerto = puertoFalso({
      leerPerfil: vi.fn(async () => filaPerfil({ activo: false })),
    });

    expect(await resolverEstadoSesion(puerto, "u-1")).toEqual({
      estado: "bloqueado",
      motivo: "perfil_inactivo",
    });
  });

  it("empresa no visible o inactiva bloquea", async () => {
    for (const empresa of [null, { ...EMPRESA, activo: false }, { ...EMPRESA, id: "otra" }]) {
      const puerto = puertoFalso({ leerEmpresa: vi.fn(async () => empresa) });

      expect(await resolverEstadoSesion(puerto, "u-1")).toEqual({
        estado: "bloqueado",
        motivo: "empresa_no_disponible",
      });
    }
  });

  it("rol desconocido (p. ej. el 'administrador' del demo) bloquea", async () => {
    const puerto = puertoFalso({
      leerPerfil: vi.fn(async () => filaPerfil({ rol: "administrador" })),
    });

    expect(await resolverEstadoSesion(puerto, "u-1")).toEqual({
      estado: "bloqueado",
      motivo: "perfil_invalido",
    });
  });

  it("perfil de otro usuario no se acepta", async () => {
    const puerto = puertoFalso({
      leerPerfil: vi.fn(async () => filaPerfil({ usuario_id: "u-2" })),
    });

    expect((await resolverEstadoSesion(puerto, "u-1")).estado).toBe("bloqueado");
  });

  it("error al leer el perfil: estado error, nunca autenticado", async () => {
    const puerto = puertoFalso({
      leerPerfil: vi.fn(async () => {
        throw new Error("500");
      }),
    });

    expect(await resolverEstadoSesion(puerto, "u-1")).toEqual({
      estado: "error",
      mensaje: MENSAJE_ERROR_PERFIL,
    });
  });
});

describe("parsearPerfil", () => {
  it("ignora campos ajenos como user_metadata: el rol sale sólo de la fila", () => {
    const perfil = parsearPerfil({
      ...filaPerfil(),
      user_metadata: { rol: "dueno" },
      raw_user_meta_data: { rol: "dueno" },
    });

    expect(perfil?.rol).toBe("vendedor_piloto");
    expect(perfil).not.toHaveProperty("user_metadata");
  });

  it.each([
    [null],
    ["texto"],
    [filaPerfil({ activo: "true" })],
    [filaPerfil({ rol: undefined })],
    [filaPerfil({ empresa_id: "" })],
  ])("rechaza filas inválidas %#", (fila) => {
    expect(parsearPerfil(fila)).toBeNull();
  });
});

describe("decidirAcceso", () => {
  const autenticado = (rol: "dueno" | "encargado" | "vendedor_piloto", activo = true): EstadoSesion => ({
    estado: "autenticado",
    perfil: {
      usuarioId: "u",
      empresaId: "e",
      usuario: "u",
      nombre: "U",
      rol,
      activo,
    },
    empresa: EMPRESA,
  });

  it("espera la resolución de la sesión", () => {
    expect(decidirAcceso({ estado: "cargando" }, ["dueno"])).toBe("cargando");
  });

  it("sin sesión redirige a login", () => {
    expect(decidirAcceso({ estado: "no_autenticado" }, ["dueno"])).toBe(
      "redirigir_login"
    );
  });

  it("bloqueado y error no acceden", () => {
    expect(
      decidirAcceso({ estado: "bloqueado", motivo: "sin_perfil" }, ["dueno"])
    ).toBe("bloqueado");
    expect(
      decidirAcceso({ estado: "bloqueado", motivo: "perfil_inactivo" }, ["dueno"])
    ).toBe("bloqueado");
    expect(decidirAcceso({ estado: "error", mensaje: "x" }, ["dueno"])).toBe(
      "bloqueado"
    );
  });

  it("perfil inactivo nunca pasa, aunque el rol coincida", () => {
    expect(decidirAcceso(autenticado("dueno", false), ["dueno"])).toBe(
      "bloqueado"
    );
  });

  it("controla el rol del perfil protegido", () => {
    expect(decidirAcceso(autenticado("dueno"), ["dueno", "encargado"])).toBe(
      "permitido"
    );
    expect(decidirAcceso(autenticado("encargado"), ["dueno"])).toBe(
      "rol_no_permitido"
    );
    expect(
      decidirAcceso(autenticado("vendedor_piloto"), ["dueno", "encargado"])
    ).toBe("rol_no_permitido");
  });
});
