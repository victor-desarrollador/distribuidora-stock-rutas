import { describe, expect, it, vi } from "vitest";

import { ROLES_GESTION, ROLES_SOLO_DUENO, ROLES_TODOS } from "./roles";

import {
  MENSAJE_CREDENCIALES,
  MENSAJE_ERROR_PERFIL,
  crearControladorSesion,
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

// ---------------------------------------------------------------------------
// MEDIUM-01: perfil obsoleto y respuestas asincrónicas viejas
// ---------------------------------------------------------------------------

function diferido<T>() {
  let resolver!: (valor: T) => void;
  const promesa = new Promise<T>((r) => {
    resolver = r;
  });
  return { promesa, resolver };
}

// Deja correr todas las promesas pendientes ya resueltas.
const drenar = () => new Promise((r) => setTimeout(r, 0));

const EMPRESA_B = { id: "emp-2", nombre: "Otra", activo: true };

// Base simulada y mutable: cada lectura devuelve el valor vigente en ese
// momento, como haría el servidor.
function baseMutable() {
  const base = {
    perfiles: new Map<string, Record<string, unknown>>([
      ["u-1", filaPerfil({ rol: "dueno" })],
      ["u-2", filaPerfil({ usuario_id: "u-2", usuario: "ana", nombre: "Ana", rol: "encargado" })],
    ]),
    empresas: new Map<string, unknown>([
      ["emp-1", EMPRESA],
      ["emp-2", EMPRESA_B],
    ]),
  };

  const puerto = puertoFalso({
    leerPerfil: vi.fn(async (id: string) => base.perfiles.get(id) ?? null),
    leerEmpresa: vi.fn(async (id: string) => base.empresas.get(id) ?? null),
  });

  return { base, puerto };
}

function observar(puerto: PuertoAuth) {
  const publicados: EstadoSesion[] = [];
  const controlador = crearControladorSesion(puerto, (e) => publicados.push(e));

  return {
    controlador,
    publicados,
    ultimo: () => publicados[publicados.length - 1],
  };
}

function cambiarPerfil(
  base: ReturnType<typeof baseMutable>["base"],
  id: string,
  cambios: Record<string, unknown>
) {
  base.perfiles.set(id, { ...base.perfiles.get(id), ...cambios });
}

describe("crearControladorSesion", () => {
  it("1. activo=true -> activo=false con el mismo usuario: acceso bloqueado", async () => {
    const { base, puerto } = baseMutable();
    const o = observar(puerto);

    o.controlador.notificarUsuario("u-1");
    await drenar();
    expect(decidirAcceso(o.ultimo(), ROLES_TODOS)).toBe("permitido");

    cambiarPerfil(base, "u-1", { activo: false });
    o.controlador.notificarUsuario("u-1"); // p. ej. TOKEN_REFRESHED
    await drenar();

    expect(o.ultimo()).toEqual({ estado: "bloqueado", motivo: "perfil_inactivo" });
    expect(decidirAcceso(o.ultimo(), ROLES_TODOS)).toBe("bloqueado");
  });

  it("2. dueno -> vendedor_piloto con el mismo usuario: rutas y permisos se actualizan", async () => {
    const { base, puerto } = baseMutable();
    const o = observar(puerto);

    o.controlador.notificarUsuario("u-1");
    await drenar();
    expect(decidirAcceso(o.ultimo(), ROLES_SOLO_DUENO)).toBe("permitido");
    expect(decidirAcceso(o.ultimo(), ROLES_GESTION)).toBe("permitido");

    cambiarPerfil(base, "u-1", { rol: "vendedor_piloto" });
    o.controlador.notificarUsuario("u-1"); // p. ej. USER_UPDATED
    await drenar();

    const ultimo = o.ultimo();
    expect(ultimo.estado === "autenticado" && ultimo.perfil.rol).toBe("vendedor_piloto");
    expect(decidirAcceso(ultimo, ROLES_SOLO_DUENO)).toBe("rol_no_permitido");
    expect(decidirAcceso(ultimo, ROLES_GESTION)).toBe("rol_no_permitido");
    expect(decidirAcceso(ultimo, ROLES_TODOS)).toBe("permitido");
  });

  it("3. empresa A -> empresa B con el mismo usuario: el estado no conserva A", async () => {
    const { base, puerto } = baseMutable();
    const o = observar(puerto);

    o.controlador.notificarUsuario("u-1");
    await drenar();
    const antes = o.ultimo();
    expect(antes.estado === "autenticado" && antes.empresa.id).toBe("emp-1");

    cambiarPerfil(base, "u-1", { empresa_id: "emp-2" });
    o.controlador.notificarUsuario("u-1"); // p. ej. SIGNED_IN con el mismo usuario
    await drenar();

    const despues = o.ultimo();
    expect(despues.estado).toBe("autenticado");
    expect(despues.estado === "autenticado" && despues.perfil.empresaId).toBe("emp-2");
    expect(despues.estado === "autenticado" && despues.empresa).toEqual(EMPRESA_B);
    expect(JSON.stringify(despues)).not.toContain("emp-1");
  });

  it.each([
    ["invalidar() (cerrarSesion)", (c: ReturnType<typeof crearControladorSesion>) => c.invalidar()],
    ["evento SIGNED_OUT (null)", (c: ReturnType<typeof crearControladorSesion>) => c.notificarUsuario(null)],
  ])(
    "4. logout por %s con leerPerfil pendiente: la respuesta vieja no vuelve a autenticar",
    async (_nombre, cerrar) => {
      const pendiente = diferido<unknown>();
      const puerto = puertoFalso({ leerPerfil: vi.fn(() => pendiente.promesa) });
      const o = observar(puerto);

      o.controlador.notificarUsuario("u-1");
      cerrar(o.controlador);
      expect(o.ultimo()).toEqual({ estado: "no_autenticado" });

      pendiente.resolver(filaPerfil());
      await drenar();

      expect(o.ultimo()).toEqual({ estado: "no_autenticado" });
      expect(o.publicados.some((e) => e.estado === "autenticado")).toBe(false);
    }
  );

  it("5. leerPerfil(A) pendiente -> cambio a B -> A responde después: queda B", async () => {
    const perfilA = diferido<unknown>();
    const { base } = baseMutable();
    const puerto = puertoFalso({
      leerPerfil: vi.fn((id: string) =>
        id === "u-1" ? perfilA.promesa : Promise.resolve(base.perfiles.get(id) ?? null)
      ),
      leerEmpresa: vi.fn(async (id: string) => base.empresas.get(id) ?? null),
    });
    const o = observar(puerto);

    o.controlador.notificarUsuario("u-1");
    o.controlador.notificarUsuario("u-2");
    await drenar();
    const conB = o.ultimo();
    expect(conB.estado === "autenticado" && conB.perfil.usuarioId).toBe("u-2");

    perfilA.resolver(filaPerfil({ rol: "dueno" }));
    await drenar();

    const final = o.ultimo();
    expect(final.estado === "autenticado" && final.perfil.usuarioId).toBe("u-2");
    expect(
      o.publicados.some((e) => e.estado === "autenticado" && e.perfil.usuarioId === "u-1")
    ).toBe(false);
  });

  it("5b. A responde antes que B: tampoco se publica A, se espera a B", async () => {
    const perfilA = diferido<unknown>();
    const perfilB = diferido<unknown>();
    const puerto = puertoFalso({
      leerPerfil: vi.fn((id: string) => (id === "u-1" ? perfilA.promesa : perfilB.promesa)),
    });
    const o = observar(puerto);

    o.controlador.notificarUsuario("u-1");
    o.controlador.notificarUsuario("u-2");
    perfilA.resolver(filaPerfil());
    await drenar();
    expect(o.ultimo()).toEqual({ estado: "cargando" });

    perfilB.resolver(filaPerfil({ usuario_id: "u-2", usuario: "ana" }));
    await drenar();
    const final = o.ultimo();
    expect(final.estado === "autenticado" && final.perfil.usuarioId).toBe("u-2");
  });

  it("6. eventos repetidos del mismo usuario releen el perfil cada vez", async () => {
    const { base, puerto } = baseMutable();
    const o = observar(puerto);

    o.controlador.notificarUsuario("u-1");
    await drenar();
    cambiarPerfil(base, "u-1", { nombre: "Juan v2" });
    o.controlador.notificarUsuario("u-1");
    await drenar();
    cambiarPerfil(base, "u-1", { nombre: "Juan v3" });
    o.controlador.notificarUsuario("u-1");
    await drenar();

    expect(puerto.leerPerfil).toHaveBeenCalledTimes(3);
    const final = o.ultimo();
    expect(final.estado === "autenticado" && final.perfil.nombre).toBe("Juan v3");
    // La revalidación del mismo usuario no vuelve a `cargando`.
    expect(o.publicados.filter((e) => e.estado === "cargando")).toHaveLength(1);
  });

  it("6b. dos revalidaciones del mismo usuario fuera de orden: gana la más nueva", async () => {
    const vieja = diferido<unknown>();
    const nueva = diferido<unknown>();
    const respuestas = [vieja.promesa, nueva.promesa];
    const puerto = puertoFalso({ leerPerfil: vi.fn(() => respuestas.shift()!) });
    const o = observar(puerto);

    o.controlador.notificarUsuario("u-1");
    o.controlador.notificarUsuario("u-1");
    nueva.resolver(filaPerfil({ activo: false }));
    await drenar();
    vieja.resolver(filaPerfil({ activo: true }));
    await drenar();

    expect(o.ultimo()).toEqual({ estado: "bloqueado", motivo: "perfil_inactivo" });
  });

  it("fail-closed: si la revalidación falla, se pierde el acceso autorizado", async () => {
    const { puerto } = baseMutable();
    const o = observar(puerto);

    o.controlador.notificarUsuario("u-1");
    await drenar();
    expect(o.ultimo().estado).toBe("autenticado");

    vi.mocked(puerto.leerPerfil).mockRejectedValueOnce(new Error("red"));
    o.controlador.notificarUsuario("u-1");
    await drenar();

    expect(o.ultimo()).toEqual({ estado: "error", mensaje: MENSAJE_ERROR_PERFIL });
    expect(decidirAcceso(o.ultimo(), ROLES_TODOS)).toBe("bloqueado");
  });

  it("detener() descarta las lecturas en curso", async () => {
    const pendiente = diferido<unknown>();
    const o = observar(puertoFalso({ leerPerfil: vi.fn(() => pendiente.promesa) }));

    o.controlador.notificarUsuario("u-1");
    o.controlador.detener();
    pendiente.resolver(filaPerfil());
    await drenar();

    expect(o.publicados).toEqual([{ estado: "cargando" }]);
  });
});
