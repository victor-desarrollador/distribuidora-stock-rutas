import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";

import {
  MENSAJE_REINTENTO_NO_ENVIADO,
  MENSAJE_RESULTADO_DESCONOCIDO,
  crearPuertoJornadas,
  type ComandoJornada,
  type EstadoJornada,
  type Jornada,
  type OpcionesEjecucion,
  type ResultadoJornada,
} from "../lib/jornadas";
import type { ResultadoVendedores } from "../lib/vendedores_jornada";
import {
  APERTURA_INACTIVA,
  MENSAJE_APERTURA_DESCONOCIDA,
  MENSAJE_APERTURA_OK,
  MENSAJE_CAMION_NO_OFRECIDO,
  MENSAJE_INFO_NO_CONSULTADA,
  MENSAJE_INFO_SIN_COINCIDENCIA,
  MENSAJE_INFO_SIN_LECTURA,
  MENSAJE_RECUPERACION_DUPLICADA,
  MENSAJE_RECUPERACION_VENDEDOR_OCUPADO,
  MENSAJE_RIESGO_RECARGA,
  MENSAJE_VENDEDOR_INVALIDO,
  crearControladorApertura,
  crearControladorVendedores,
  faseConRiesgoApertura,
  recuperacionPara,
  validarApertura,
  type EntradaApertura,
  type EstadoVendedores,
  type FaseApertura,
  type OpcionesPermitidas,
} from "./jornadas_apertura";
import {
  MENSAJE_CAMION_INVALIDO,
  MENSAJE_FECHA_INVALIDA,
  MENSAJE_FECHA_PASADA,
} from "./jornadas_correccion";
import fuenteControlador from "./jornadas_apertura.ts?raw";
import fuenteHook from "../hooks/useAperturaJornada.ts?raw";
import fuenteHookVendedores from "../hooks/useVendedoresJornada.ts?raw";
import fuentePanel from "./JornadaAperturaPanel.tsx?raw";
import fuentePantalla from "./Jornadas.tsx?raw";
import { instalarAvisoSalida } from "../hooks/useAvisoSalidaPagina";
import fuenteAviso from "../hooks/useAvisoSalidaPagina.ts?raw";

// T-2: orientación esperada por código (sólo estos dos la llevan).
const RECUPERACION_ESPERADA: Readonly<Record<string, string>> = {
  jornada_duplicada: MENSAJE_RECUPERACION_DUPLICADA,
  jornada_vendedor_ocupado: MENSAJE_RECUPERACION_VENDEDOR_OCUPADO,
};

const CAMION = "22222222-2222-4222-8222-222222222222";
const CAMION_2 = "44444444-4444-4444-8444-444444444444";
const VENDEDOR = "33333333-3333-4333-8333-333333333333";
const VENDEDOR_2 = "55555555-5555-4555-8555-555555555555";
const YO = "66666666-6666-4666-8666-666666666666";
const JORNADA = "00000000-0000-4000-8000-000000000001";
const HOY = "2026-11-10";

const PERMITIDAS: OpcionesPermitidas = {
  camiones: [CAMION, CAMION_2],
  vendedores: [VENDEDOR, VENDEDOR_2],
};
const ENTRADA: EntradaApertura = { camionId: CAMION, fecha: HOY, vendedorId: VENDEDOR };

function jornada(extra: Partial<Jornada> = {}, estado: EstadoJornada = "abierta"): Jornada {
  return {
    id: JORNADA,
    fecha: HOY,
    camionId: CAMION,
    vendedorId: VENDEDOR,
    estado,
    abiertaPor: YO,
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
    ...extra,
  };
}

const ok = (id = JORNADA): ResultadoJornada<string> => ({ ok: true, datos: id, intentos: 1 });
const rechazo = (codigo: string | null, mensaje = `msg:${codigo}`): ResultadoJornada<string> => ({
  ok: false,
  error: { codigo, mensaje, resultadoDesconocido: false },
  intentos: 1,
});
const perdida: ResultadoJornada<string> = {
  ok: false,
  error: { codigo: null, mensaje: MENSAJE_RESULTADO_DESCONOCIDO, resultadoDesconocido: true },
  intentos: 3,
};

function diferido<T>() {
  let resolver!: (v: T) => void;
  const promesa = new Promise<T>((r) => (resolver = r));
  return { promesa, resolver };
}

function armar(
  opciones: {
    respuestas?: Array<ResultadoJornada<string>>;
    lectura?: ResultadoJornada<Jornada[]> | "lanzar";
  } = {}
) {
  const respuestas = [...(opciones.respuestas ?? [])];
  const envios: Array<{ comando: ComandoJornada; clave: string }> = [];
  const lecturas: Array<{ fecha?: string } | undefined> = [];
  const publicadas: FaseApertura[] = [];
  const releer = vi.fn();
  const alRechazoVendedor = vi.fn();
  let n = 0;
  const c = crearControladorApertura(
    {
      ejecutar: async (comando, clave) => {
        envios.push({ comando, clave });
        return respuestas.shift() ?? perdida;
      },
    },
    {
      leerTodasLasJornadas: async (filtro) => {
        lecturas.push(filtro);
        if (opciones.lectura === "lanzar") throw new Error("red");
        return opciones.lectura ?? { ok: true, datos: [], intentos: 1 };
      },
    },
    releer,
    (f) => publicadas.push(f),
    {
      hoy: () => HOY,
      generarClave: () => `aaaaaaaa-aaaa-4aaa-8aaa-${(++n).toString().padStart(12, "0")}`,
      alRechazoVendedor,
    }
  );
  return { c, envios, lecturas, publicadas, releer, alRechazoVendedor, fase: () => c.obtener() };
}

describe("validarApertura", () => {
  it("acepta camión y vendedor de las listas reales con fecha de hoy o futura", () => {
    expect(validarApertura(ENTRADA, HOY, PERMITIDAS)).toBeNull();
    expect(validarApertura({ ...ENTRADA, fecha: "2026-11-11" }, HOY, PERMITIDAS)).toBeNull();
  });

  it("rechaza fecha inválida o anterior al día operativo", () => {
    expect(validarApertura({ ...ENTRADA, fecha: "" }, HOY, PERMITIDAS)).toBe(MENSAJE_FECHA_INVALIDA);
    expect(validarApertura({ ...ENTRADA, fecha: "2026-02-30" }, HOY, PERMITIDAS)).toBe(MENSAJE_FECHA_INVALIDA);
    expect(validarApertura({ ...ENTRADA, fecha: "2026-11-09" }, HOY, PERMITIDAS)).toBe(MENSAJE_FECHA_PASADA);
  });

  it("rechaza camión vacío o fuera de los activos ofrecidos", () => {
    expect(validarApertura({ ...ENTRADA, camionId: "" }, HOY, PERMITIDAS)).toBe(MENSAJE_CAMION_INVALIDO);
    expect(
      validarApertura({ ...ENTRADA, camionId: "99999999-9999-4999-8999-999999999999" }, HOY, PERMITIDAS)
    ).toBe(MENSAJE_CAMION_NO_OFRECIDO);
  });

  it("rechaza vendedor vacío o un uuid que no vino de la lista real (sin uuid manual ni autoasignación)", () => {
    expect(validarApertura({ ...ENTRADA, vendedorId: "" }, HOY, PERMITIDAS)).toBe(MENSAJE_VENDEDOR_INVALIDO);
    expect(validarApertura({ ...ENTRADA, vendedorId: YO }, HOY, PERMITIDAS)).toBe(MENSAJE_VENDEDOR_INVALIDO);
    expect(validarApertura(ENTRADA, HOY, { ...PERMITIDAS, vendedores: [] })).toBe(MENSAJE_VENDEDOR_INVALIDO);
  });
});

describe("abrir jornada: flujo normal", () => {
  it("solicitar abre el formulario y cancelar lo cierra sin enviar", () => {
    const m = armar();
    m.c.solicitar();
    expect(m.fase()).toEqual({ fase: "editando" });
    m.c.cancelar();
    expect(m.fase()).toEqual(APERTURA_INACTIVA);
    expect(m.envios).toHaveLength(0);
  });

  it("una entrada inválida no envía nada y deja el error en el formulario", async () => {
    const m = armar();
    m.c.solicitar();
    await m.c.confirmar({ ...ENTRADA, vendedorId: YO }, PERMITIDAS);
    expect(m.fase()).toEqual({ fase: "editando", error: MENSAJE_VENDEDOR_INVALIDO });
    expect(m.envios).toHaveLength(0);
  });

  it("envía el comando `abrir` exacto con una clave nueva; éxito con el uuid devuelto y relee la lista", async () => {
    const m = armar({ respuestas: [ok()] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    expect(m.envios).toEqual([
      {
        comando: { tipo: "abrir", camionId: CAMION, fecha: HOY, vendedorId: VENDEDOR },
        clave: "aaaaaaaa-aaaa-4aaa-8aaa-000000000001",
      },
    ]);
    expect(m.publicadas.map((f) => f.fase)).toEqual(["editando", "enviando", "exito"]);
    expect(m.fase()).toEqual({ fase: "exito", jornadaId: JORNADA, datos: ENTRADA, mensaje: MENSAJE_APERTURA_OK });
    expect(m.releer).toHaveBeenCalledTimes(1);
    expect(m.c.claveEnCurso()).toBeNull();
  });

  it("el comando de la intención queda congelado", async () => {
    const d = diferido<ResultadoJornada<string>>();
    const m = armar();
    const c = crearControladorApertura(
      { ejecutar: () => d.promesa },
      { leerTodasLasJornadas: async () => ({ ok: true, datos: [], intentos: 1 }) },
      m.releer,
      () => undefined,
      { hoy: () => HOY }
    );
    c.solicitar();
    const p = c.confirmar(ENTRADA, PERMITIDAS);
    expect(Object.isFrozen(c.comandoEnCurso())).toBe(true);
    d.resolver(ok());
    await p;
  });
});

describe("abrir jornada: envío único", () => {
  it("un segundo confirmar, solicitar o cancelar durante el envío se ignora", async () => {
    const d = diferido<ResultadoJornada<string>>();
    const envios: string[] = [];
    const c = crearControladorApertura(
      { ejecutar: (_c, clave) => (envios.push(clave), d.promesa) },
      { leerTodasLasJornadas: async () => ({ ok: true, datos: [], intentos: 1 }) },
      () => undefined,
      () => undefined,
      { hoy: () => HOY }
    );
    c.solicitar();
    const p = c.confirmar(ENTRADA, PERMITIDAS);
    await c.confirmar(ENTRADA, PERMITIDAS);
    c.solicitar();
    c.cancelar();
    expect(c.obtener().fase).toBe("enviando");
    expect(envios).toHaveLength(1);
    d.resolver(ok());
    await p;
    expect(c.obtener().fase).toBe("exito");
  });

  it("tras un éxito no se abre otra intención hasta releer la lista; la nueva usa otra clave", async () => {
    const m = armar({ respuestas: [ok(), ok("00000000-0000-4000-8000-000000000002")] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    m.c.solicitar();
    expect(m.fase().fase).toBe("exito");
    m.c.trasRelectura();
    expect(m.fase()).toMatchObject({ fase: "exito", releida: true });
    m.c.solicitar();
    expect(m.fase()).toEqual({ fase: "editando" });
    await m.c.confirmar({ ...ENTRADA, camionId: CAMION_2, vendedorId: VENDEDOR_2 }, PERMITIDAS);
    expect(m.envios.map((e) => e.clave)).toEqual([
      "aaaaaaaa-aaaa-4aaa-8aaa-000000000001",
      "aaaaaaaa-aaaa-4aaa-8aaa-000000000002",
    ]);
  });
});

describe("abrir jornada: rechazos definitivos del servidor", () => {
  const CODIGOS = [
    "jornada_no_autorizado",
    "jornada_fecha_invalida",
    "jornada_camion_no_encontrado",
    "jornada_camion_inactivo",
    "jornada_vendedor_no_encontrado",
    "jornada_vendedor_invalido",
    "jornada_duplicada",
    "jornada_camion_con_jornada_abierta",
    "jornada_vendedor_ocupado",
    "jornada_conflicto_idempotencia",
    "jornada_error_interno",
    "42501",
  ];

  it.each(CODIGOS)("%s: error con el mensaje de la capa de datos, sin reintento ni éxito", async (codigo) => {
    const m = armar({ respuestas: [rechazo(codigo)] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    const orientacion = RECUPERACION_ESPERADA[codigo];
    expect(m.fase()).toEqual(
      orientacion
        ? { fase: "error", mensaje: `msg:${codigo}`, recuperacion: { fecha: HOY, mensaje: orientacion } }
        : { fase: "error", mensaje: `msg:${codigo}` }
    );
    expect(m.envios).toHaveLength(1);
    expect(m.lecturas).toHaveLength(0);
    expect(m.c.claveEnCurso()).toBeNull();
  });

  it("los rechazos por jornadas existentes releen la lista; los demás no", async () => {
    for (const codigo of ["jornada_duplicada", "jornada_camion_con_jornada_abierta", "jornada_vendedor_ocupado"]) {
      const m = armar({ respuestas: [rechazo(codigo)] });
      m.c.solicitar();
      await m.c.confirmar(ENTRADA, PERMITIDAS);
      expect(m.releer).toHaveBeenCalledTimes(1);
    }
    const m = armar({ respuestas: [rechazo("jornada_fecha_invalida")] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    expect(m.releer).not.toHaveBeenCalled();
  });

  it("un vendedor inexistente o inactivo vuelve a pedir la lista de vendedores", async () => {
    for (const codigo of ["jornada_vendedor_no_encontrado", "jornada_vendedor_invalido"]) {
      const m = armar({ respuestas: [rechazo(codigo)] });
      m.c.solicitar();
      await m.c.confirmar(ENTRADA, PERMITIDAS);
      expect(m.alRechazoVendedor).toHaveBeenCalledTimes(1);
    }
  });

  it("desde el error se corrige y se reenvía como intención nueva (otra clave)", async () => {
    const m = armar({ respuestas: [rechazo("jornada_vendedor_ocupado"), ok()] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    await m.c.confirmar({ ...ENTRADA, vendedorId: VENDEDOR_2 }, PERMITIDAS);
    expect(m.envios.map((e) => e.clave)).toEqual([
      "aaaaaaaa-aaaa-4aaa-8aaa-000000000001",
      "aaaaaaaa-aaaa-4aaa-8aaa-000000000002",
    ]);
    expect(m.fase().fase).toBe("exito");
  });

  it("cancelar desde el error vuelve a inactiva", async () => {
    const m = armar({ respuestas: [rechazo("jornada_duplicada")] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    m.c.cancelar();
    expect(m.fase()).toEqual(APERTURA_INACTIVA);
  });
});

describe("abrir jornada: respuesta desconocida (sólo el replay confirma)", () => {
  it("una lectura que coincide en camión, fecha, vendedor y abiertaPor NO declara éxito", async () => {
    const m = armar({ respuestas: [perdida], lectura: { ok: true, datos: [jornada()], intentos: 1 } });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    expect(m.lecturas).toEqual([{ fecha: HOY }]);
    expect(m.publicadas.map((f) => f.fase)).toEqual(["editando", "enviando", "verificando", "desconocido"]);
    const f = m.fase();
    expect(f.fase).toBe("desconocido");
    if (f.fase !== "desconocido") return;
    expect(f.mensaje).toBe(MENSAJE_APERTURA_DESCONOCIDA);
    expect(f.datos).toEqual(ENTRADA);
    expect(f.informacion).toMatch(/hay una jornada abierta de ese camión en esa fecha con el vendedor elegido/);
    expect(f.informacion).toMatch(/no confirma/);
    expect(m.publicadas.some((p) => p.fase === "exito")).toBe(false);
    expect(m.releer).not.toHaveBeenCalled();
    // La intención se conserva para el replay.
    expect(m.c.claveEnCurso()).toBe("aaaaaaaa-aaaa-4aaa-8aaa-000000000001");
  });

  it("sin coincidencia o con otro vendedor: sólo informa", async () => {
    const sin = armar({ respuestas: [perdida] });
    sin.c.solicitar();
    await sin.c.confirmar(ENTRADA, PERMITIDAS);
    expect(sin.fase()).toMatchObject({ fase: "desconocido", informacion: MENSAJE_INFO_SIN_COINCIDENCIA });

    const otro = armar({
      respuestas: [perdida],
      lectura: { ok: true, datos: [jornada({ vendedorId: VENDEDOR_2 }, "cargada")], intentos: 1 },
    });
    otro.c.solicitar();
    await otro.c.confirmar(ENTRADA, PERMITIDAS);
    const f = otro.fase();
    expect(f.fase === "desconocido" && f.informacion).toMatch(/jornada cargada .* con otro vendedor/);
  });

  it("si la lectura informativa falla o lanza, la intención sigue intacta", async () => {
    for (const lectura of [
      { ok: false as const, error: { codigo: null, mensaje: "x", resultadoDesconocido: false }, intentos: 1 },
      "lanzar" as const,
    ]) {
      const m = armar({ respuestas: [perdida], lectura });
      m.c.solicitar();
      await m.c.confirmar(ENTRADA, PERMITIDAS);
      expect(m.fase()).toMatchObject({ fase: "desconocido", informacion: MENSAJE_INFO_SIN_LECTURA });
      expect(m.c.claveEnCurso()).not.toBeNull();
    }
  });

  it("40001/40P01 agotados se tratan como respuesta dudosa (reintentable con la misma clave)", async () => {
    for (const codigo of ["40001", "40P01"]) {
      const m = armar({ respuestas: [rechazo(codigo)] });
      m.c.solicitar();
      await m.c.confirmar(ENTRADA, PERMITIDAS);
      expect(m.fase().fase).toBe("desconocido");
    }
  });

  it("el replay usa la MISMA clave y el MISMO comando; sólo su uuid confirma el éxito", async () => {
    const m = armar({ respuestas: [perdida, ok()], lectura: { ok: true, datos: [jornada()], intentos: 1 } });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    const comando = m.c.comandoEnCurso();
    await m.c.reintentar();
    expect(m.envios).toHaveLength(2);
    expect(m.envios[1].clave).toBe(m.envios[0].clave);
    expect(m.envios[1].comando).toBe(m.envios[0].comando);
    expect(m.envios[1].comando).toBe(comando);
    expect(m.fase()).toEqual({ fase: "exito", jornadaId: JORNADA, datos: ENTRADA, mensaje: MENSAJE_APERTURA_OK });
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  it("si el replay se rechaza, queda en error (nunca éxito), aunque la lectura coincidiera", async () => {
    const m = armar({
      respuestas: [perdida, rechazo("jornada_duplicada")],
      lectura: { ok: true, datos: [jornada()], intentos: 1 },
    });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    await m.c.reintentar();
    expect(m.fase()).toEqual({
      fase: "error",
      mensaje: "msg:jornada_duplicada",
      recuperacion: { fecha: HOY, mensaje: MENSAJE_RECUPERACION_DUPLICADA },
    });
    expect(m.publicadas.some((p) => p.fase === "exito")).toBe(false);
  });

  it("un replay sin respuesta vuelve a informar y conserva la misma clave", async () => {
    const m = armar({ respuestas: [perdida, perdida, ok()] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    await m.c.reintentar();
    expect(m.fase().fase).toBe("desconocido");
    await m.c.reintentar();
    expect(new Set(m.envios.map((e) => e.clave)).size).toBe(1);
    expect(m.fase().fase).toBe("exito");
  });

  it("con una intención sin resolver no se inicia otra ni se cancela", async () => {
    const m = armar({ respuestas: [perdida] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    m.c.solicitar();
    m.c.cancelar();
    await m.c.confirmar({ ...ENTRADA, vendedorId: VENDEDOR_2 }, PERMITIDAS);
    expect(m.fase().fase).toBe("desconocido");
    expect(m.envios).toHaveLength(1);
  });

  it("reintentar fuera de `desconocido` no hace nada", async () => {
    const m = armar();
    await m.c.reintentar();
    m.c.solicitar();
    await m.c.reintentar();
    expect(m.envios).toHaveLength(0);
  });
});

describe("abrir jornada: desmontaje", () => {
  it("una respuesta tardía no publica ni relee", async () => {
    const d = diferido<ResultadoJornada<string>>();
    const publicadas: FaseApertura[] = [];
    const releer = vi.fn();
    const c = crearControladorApertura(
      { ejecutar: () => d.promesa },
      { leerTodasLasJornadas: async () => ({ ok: true, datos: [], intentos: 1 }) },
      releer,
      (f) => publicadas.push(f),
      { hoy: () => HOY }
    );
    c.solicitar();
    const p = c.confirmar(ENTRADA, PERMITIDAS);
    c.detener();
    d.resolver(ok());
    await p;
    expect(publicadas.map((f) => f.fase)).toEqual(["editando", "enviando"]);
    expect(releer).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// FE-2E (D-1): apertura con la misma protección por intención que el motor.
// ---------------------------------------------------------------------------
const NADA_ENVIADO: ResultadoJornada<string> = {
  ok: false,
  intentos: 0,
  error: { codigo: null, mensaje: "sesión cambiada", resultadoDesconocido: false },
};

describe("FE-2E: reintento manual sin envío (apertura)", () => {
  it("A1: primer envío desconocido → reintento que no envía nada → se conservan intención, clave y datos", async () => {
    const m = armar({ respuestas: [perdida, NADA_ENVIADO, ok()] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    expect(m.fase().fase).toBe("desconocido");
    const clave = m.c.claveEnCurso();
    const comando = m.c.comandoEnCurso();
    await m.c.reintentar();
    expect(m.fase()).toMatchObject({ fase: "desconocido", datos: ENTRADA });
    expect(m.c.claveEnCurso()).toBe(clave);
    expect(m.c.comandoEnCurso()).toBe(comando);
    expect(m.alRechazoVendedor).not.toHaveBeenCalled();
    // Con sesión disponible, el siguiente reintento sale con la MISMA clave.
    await m.c.reintentar();
    expect(m.envios.map((e) => e.clave)).toEqual([clave, clave, clave]);
    expect(m.fase().fase).toBe("exito");
  });

  it("A2: la sesión pasó a otro usuario → el reintento manual no sale; intención conservada (wrapper real)", async () => {
    const USUARIO_A = "aaaaaaaa-1111-4111-8111-111111111111";
    const USUARIO_B = "bbbbbbbb-2222-4222-8222-222222222222";
    const estado = { usuario: USUARIO_A };
    const rpcs: string[] = [];
    const cliente = {
      auth: {
        getSession: async () => ({
          data: { session: { user: { id: estado.usuario }, access_token: `token-${estado.usuario}` } },
          error: null,
        }),
      },
      rpc: () => ({
        setHeader: (_c: string, valor: string) => {
          rpcs.push(valor);
          return Promise.reject(new Error("red"));
        },
      }),
    } as unknown as SupabaseClient;
    const c = crearControladorApertura(
      crearPuertoJornadas(cliente),
      { leerTodasLasJornadas: async () => ({ ok: true, datos: [], intentos: 1 }) },
      vi.fn(),
      vi.fn(),
      { hoy: () => HOY }
    );
    c.solicitar();
    await c.confirmar(ENTRADA, PERMITIDAS);
    expect(c.obtener().fase).toBe("desconocido");
    expect(rpcs).toHaveLength(3);
    const clave = c.claveEnCurso();
    estado.usuario = USUARIO_B;
    await c.reintentar();
    expect(rpcs).toHaveLength(3);
    expect(rpcs.some((r) => r.includes(USUARIO_B))).toBe(false);
    expect(c.obtener().fase).toBe("desconocido");
    expect(c.claveEnCurso()).toBe(clave);
    // Vuelve el usuario original: el reintento sale con la MISMA clave y su token.
    estado.usuario = USUARIO_A;
    await c.reintentar();
    expect(rpcs).toHaveLength(6);
    expect(rpcs.slice(3).every((r) => r.includes(USUARIO_A))).toBe(true);
    expect(c.claveEnCurso()).toBe(clave);
  });

  it("A2b: getSession falla en el reintento manual → 0 envíos nuevos; intención conservada (wrapper real)", async () => {
    let falla = false;
    const rpcs: string[] = [];
    const cliente = {
      auth: {
        getSession: async () => {
          if (falla) throw new Error("auth caído");
          return { data: { session: { user: { id: YO }, access_token: "token" } }, error: null };
        },
      },
      rpc: () => ({
        setHeader: (_c: string, valor: string) => {
          rpcs.push(valor);
          return Promise.reject(new Error("red"));
        },
      }),
    } as unknown as SupabaseClient;
    const c = crearControladorApertura(
      crearPuertoJornadas(cliente),
      { leerTodasLasJornadas: async () => ({ ok: true, datos: [], intentos: 1 }) },
      vi.fn(),
      vi.fn(),
      { hoy: () => HOY }
    );
    c.solicitar();
    await c.confirmar(ENTRADA, PERMITIDAS);
    const clave = c.claveEnCurso();
    falla = true;
    await c.reintentar();
    expect(rpcs).toHaveLength(3);
    expect(c.obtener()).toMatchObject({ fase: "desconocido", mensaje: MENSAJE_REINTENTO_NO_ENVIADO });
    expect(c.claveEnCurso()).toBe(clave);
  });

  it("A3: identidad por intención — el reintento manual exige el usuario del primer envío; sin `continuar` (G-2)", async () => {
    const opciones: Array<OpcionesEjecucion | undefined> = [];
    const respuestas = [perdida, ok()];
    const c = crearControladorApertura(
      {
        ejecutar: async (_comando, _clave, o) => {
          opciones.push(o);
          o?.alFijarActor?.(YO);
          return respuestas.shift()!;
        },
      },
      { leerTodasLasJornadas: async () => ({ ok: true, datos: [], intentos: 1 }) },
      vi.fn(),
      vi.fn(),
      { hoy: () => HOY }
    );
    c.solicitar();
    await c.confirmar(ENTRADA, PERMITIDAS);
    await c.reintentar();
    expect(opciones[0]?.usuarioEsperado).toBeUndefined();
    expect(opciones[1]?.usuarioEsperado).toBe(YO);
    // A4 (G-2): apertura nunca pasa `continuar`.
    expect(opciones.every((o) => o !== undefined && !("continuar" in o))).toBe(true);
    expect(c.obtener().fase).toBe("exito");
  });

  it("A4: guarda estructural — el controlador de apertura no usa `continuar`", () => {
    expect(fuenteControlador.replace(/\/\/.*$/gm, "")).not.toMatch(/continuar\s*:/);
  });

  it("A4b: una intención NUEVA cuyo primer envío no sale → error y se descarta (sin cambios)", async () => {
    const m = armar({ respuestas: [NADA_ENVIADO] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    expect(m.fase()).toMatchObject({ fase: "error", mensaje: "sesión cambiada" });
    expect(m.c.claveEnCurso()).toBeNull();
    expect(m.alRechazoVendedor).not.toHaveBeenCalled();
  });
});

describe("FE-2E: respuesta tardía con la apertura detenida (H-2)", () => {
  function armarDiferido() {
    const d = diferido<ResultadoJornada<string>>();
    const publicadas: FaseApertura[] = [];
    const lecturas: number[] = [];
    const releer = vi.fn();
    const alRechazoVendedor = vi.fn();
    const c = crearControladorApertura(
      { ejecutar: () => d.promesa },
      {
        leerTodasLasJornadas: async () => {
          lecturas.push(1);
          return { ok: true, datos: [], intentos: 1 };
        },
      },
      releer,
      (f) => publicadas.push(f),
      { hoy: () => HOY, alRechazoVendedor }
    );
    c.solicitar();
    const p = c.confirmar(ENTRADA, PERMITIDAS);
    return { c, d, p, publicadas, lecturas, releer, alRechazoVendedor };
  }

  it("A5: éxito con la pantalla detenida → no queda «enviando»; al reanudar publica y relee UNA vez", async () => {
    const m = armarDiferido();
    m.c.detener();
    m.d.resolver(ok());
    await m.p;
    expect(m.c.obtener().fase).toBe("exito");
    expect(m.publicadas.map((f) => f.fase)).toEqual(["editando", "enviando"]);
    expect(m.releer).not.toHaveBeenCalled();
    m.c.iniciar();
    expect(m.publicadas.at(-1)?.fase).toBe("exito");
    expect(m.releer).toHaveBeenCalledTimes(1);
    m.c.detener();
    m.c.iniciar();
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  it("A5b: rechazo definitivo detenido → error sin releer ni avisar al selector de vendedores", async () => {
    const m = armarDiferido();
    m.c.detener();
    m.d.resolver(rechazo("jornada_vendedor_ocupado"));
    await m.p;
    expect(m.c.obtener().fase).toBe("error");
    expect(m.c.claveEnCurso()).toBeNull();
    expect(m.releer).not.toHaveBeenCalled();
    expect(m.alRechazoVendedor).not.toHaveBeenCalled();
  });

  it("A5c: respuesta perdida detenida → desconocido SIN la lectura informativa; intención conservada", async () => {
    const m = armarDiferido();
    const clave = m.c.claveEnCurso();
    m.c.detener();
    m.d.resolver(perdida);
    await m.p;
    expect(m.lecturas).toHaveLength(0);
    expect(m.c.obtener()).toMatchObject({ fase: "desconocido", informacion: MENSAJE_INFO_NO_CONSULTADA });
    expect(m.c.claveEnCurso()).toBe(clave);
    m.c.iniciar();
    expect(m.publicadas.at(-1)?.fase).toBe("desconocido");
  });

  it("A5d: detenida durante la lectura informativa → no usa esa lectura", async () => {
    const lectura = diferido<ResultadoJornada<Jornada[]>>();
    const c = crearControladorApertura(
      { ejecutar: async () => perdida },
      { leerTodasLasJornadas: () => lectura.promesa },
      vi.fn(),
      vi.fn(),
      { hoy: () => HOY }
    );
    c.solicitar();
    const p = c.confirmar(ENTRADA, PERMITIDAS);
    await Promise.resolve();
    await Promise.resolve();
    c.detener();
    lectura.resolver({ ok: true, datos: [jornada()], intentos: 1 });
    await p;
    expect(c.obtener()).toMatchObject({ fase: "desconocido", informacion: MENSAJE_INFO_NO_CONSULTADA });
  });

  it("A6: iniciar sin cambios no publica nada", () => {
    const m = armar();
    m.c.iniciar();
    m.c.detener();
    m.c.iniciar();
    expect(m.publicadas).toHaveLength(0);
  });
});

describe("lectura de vendedores para el formulario", () => {
  it("cargando → listo con la lista del puerto", async () => {
    const estados: EstadoVendedores[] = [];
    const vendedores = [{ usuarioId: VENDEDOR, nombre: "Ana", rol: "vendedor_piloto" as const }];
    const c = crearControladorVendedores(
      { listarVendedores: async () => ({ ok: true, vendedores }) },
      (e) => estados.push(e)
    );
    await c.recargar();
    expect(estados).toEqual([{ estado: "cargando" }, { estado: "listo", vendedores }]);
  });

  it("error del puerto o excepción → error con mensaje", async () => {
    const e1: EstadoVendedores[] = [];
    await crearControladorVendedores(
      { listarVendedores: async () => ({ ok: false, mensaje: "sin permiso" }) },
      (e) => e1.push(e)
    ).recargar();
    expect(e1.at(-1)).toEqual({ estado: "error", mensaje: "sin permiso" });

    const e2: EstadoVendedores[] = [];
    await crearControladorVendedores(
      { listarVendedores: () => Promise.reject(new Error("x")) },
      (e) => e2.push(e)
    ).recargar();
    expect(e2.at(-1)?.estado).toBe("error");
  });

  it("sólo publica la respuesta de la última lectura y nada tras el desmontaje", async () => {
    const d1 = diferido<ResultadoVendedores>();
    const d2 = diferido<ResultadoVendedores>();
    const cola = [d1, d2];
    const estados: EstadoVendedores[] = [];
    const c = crearControladorVendedores(
      { listarVendedores: () => cola.shift()!.promesa },
      (e) => estados.push(e)
    );
    const p1 = c.recargar();
    const p2 = c.recargar();
    d2.resolver({ ok: true, vendedores: [] });
    await p2;
    d1.resolver({ ok: false, mensaje: "vieja" });
    await p1;
    expect(estados.at(-1)).toEqual({ estado: "listo", vendedores: [] });

    const tarde = diferido<ResultadoVendedores>();
    const publicadas: EstadoVendedores[] = [];
    const c2 = crearControladorVendedores({ listarVendedores: () => tarde.promesa }, (e) => publicadas.push(e));
    const p3 = c2.recargar();
    c2.detener();
    tarde.resolver({ ok: true, vendedores: [] });
    await p3;
    expect(publicadas).toEqual([{ estado: "cargando" }]);
  });
});

describe("abrir jornada: evidencia estructural", () => {
  const sin = (s: string) =>
    s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/\{\/\*[\s\S]*?\*\/\}/g, "");
  const FUENTES: Array<[string, string]> = [
    ["jornadas_apertura.ts", fuenteControlador],
    ["useAperturaJornada.ts", fuenteHook],
    ["useVendedoresJornada.ts", fuenteHookVendedores],
    ["JornadaAperturaPanel.tsx", fuentePanel],
    ["Jornadas.tsx", fuentePantalla],
  ];

  it.each(FUENTES)("%s: sin almacenamiento del navegador", (_n, f) => {
    expect(/localStorage|sessionStorage|indexedDB/i.test(sin(f))).toBe(false);
  });

  it("el controlador no usa el motor de S1/S2 ni llama RPC directamente", () => {
    const c = sin(fuenteControlador);
    expect(c).not.toMatch(/crearControladorOperacion|crearArbitroJornadas/);
    expect(c).not.toMatch(/\.rpc\(/);
  });

  it("el éxito sólo se emite desde la respuesta del servidor (un único punto)", () => {
    const c = sin(fuenteControlador);
    // Una emisión de éxito; `trasRelectura` sólo marca `releida` sobre un éxito ya emitido.
    expect([...c.matchAll(/emitir\(\{ fase: "exito"/g)]).toHaveLength(1);
    expect([...c.matchAll(/emitir\(\{ \.\.\.fase, releida: true \}\)/g)]).toHaveLength(1);
    expect(c).toMatch(/if \(r\.ok\) \{[\s\S]*?fase: "exito", jornadaId: r\.datos/);
  });

  it("el panel no ofrece un campo de texto para el uuid ni autoasignación", () => {
    const p = sin(fuentePanel);
    expect(p).not.toMatch(/type="text"|<textarea/);
    expect([...p.matchAll(/<input/g)]).toHaveLength(1);
    expect(p).toMatch(/type="date"/);
    expect(p).not.toMatch(/usuarioId \?\?|usuario\.usuarioId|Asignarme|\bYo\b/);
  });

  it("la pantalla monta el panel sólo para gestión y pide la lista al abrir el formulario", () => {
    const p = sin(fuentePantalla);
    expect(p).toMatch(/apertura=\{\s*puedeAdministrar \? \(\s*<JornadaAperturaPanel/);
    expect(p).toMatch(/apertura\.solicitar\(\);\s*vendedores\.recargar\(\);/);
    expect(p).toMatch(/useAperturaJornada\(jornadas\.recargar, vendedores\.recargar\)/);
  });
});

describe("T-1: aviso al recargar o cerrar durante una apertura con riesgo", () => {
  const FASES: Array<[FaseApertura, boolean]> = [
    [{ fase: "inactiva" }, false],
    [{ fase: "editando" }, false],
    [{ fase: "editando", error: "x" }, false],
    [{ fase: "enviando", datos: ENTRADA }, true],
    [{ fase: "verificando", datos: ENTRADA }, true],
    [{ fase: "desconocido", datos: ENTRADA, mensaje: "m", informacion: null }, true],
    [{ fase: "exito", jornadaId: JORNADA, datos: ENTRADA, mensaje: "ok" }, false],
    [{ fase: "exito", jornadaId: JORNADA, datos: ENTRADA, mensaje: "ok", releida: true }, false],
    [{ fase: "error", mensaje: "e" }, false],
    [{ fase: "error", mensaje: "e", recuperacion: { fecha: HOY, mensaje: "r" } }, false],
  ];

  it.each(FASES)("%o → aviso %s", (fase, esperado) => {
    expect(faseConRiesgoApertura(fase)).toBe(esperado);
  });

  it("el controlador recorre fases con y sin riesgo: activo al enviar y en la duda; inactivo al resolverse", async () => {
    const m = armar({ respuestas: [perdida, ok()] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    await m.c.reintentar();
    expect(m.publicadas.map((f) => [f.fase, faseConRiesgoApertura(f)])).toEqual([
      ["editando", false],
      ["enviando", true],
      ["verificando", true],
      ["desconocido", true],
      ["enviando", true],
      ["exito", false],
    ]);
  });

  it("instalarAvisoSalida pide confirmación con beforeunload y la quita al limpiar", () => {
    const destino = new EventTarget();
    const quitar = instalarAvisoSalida(destino);
    const conAviso = new Event("beforeunload", { cancelable: true });
    destino.dispatchEvent(conAviso);
    expect(conAviso.defaultPrevented).toBe(true);
    // `returnValue` depende del entorno (en Node es el indicador booleano heredado):
    // el aviso real del navegador se comprueba en el E2E.
    quitar();
    const sinAviso = new Event("beforeunload", { cancelable: true });
    destino.dispatchEvent(sinAviso);
    expect(sinAviso.defaultPrevented).toBe(false);
  });

  it("sólo escucha beforeunload: otros eventos no se cancelan", () => {
    const destino = new EventTarget();
    instalarAvisoSalida(destino);
    const otro = new Event("unload", { cancelable: true });
    destino.dispatchEvent(otro);
    expect(otro.defaultPrevented).toBe(false);
  });

  it("la advertencia visible no promete que el navegador muestre su aviso", () => {
    expect(MENSAJE_RIESGO_RECARGA).toMatch(/puede pedirte confirmación/);
    expect(MENSAJE_RIESGO_RECARGA).toMatch(/no siempre/);
  });

  it("evidencia estructural: la pantalla activa el aviso según la fase de la apertura; sin almacenamiento", () => {
    const sin = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
    expect(sin(fuentePantalla)).toMatch(/useAvisoSalidaPagina\(faseConRiesgoApertura\(apertura\.fase\)\)/);
    expect(/localStorage|sessionStorage|indexedDB/i.test(sin(fuenteAviso))).toBe(false);
    expect([...sin(fuenteAviso).matchAll(/addEventListener\("beforeunload"/g)]).toHaveLength(1);
    expect(sin(fuenteAviso)).toMatch(/removeEventListener\("beforeunload"/);
  });
});

describe("T-2: orientación ante una posible apertura anterior", () => {
  it("sólo jornada_duplicada y jornada_vendedor_ocupado la llevan, con la fecha de la apertura rechazada", () => {
    expect(recuperacionPara("jornada_duplicada", "2026-11-12")).toEqual({
      fecha: "2026-11-12", mensaje: MENSAJE_RECUPERACION_DUPLICADA,
    });
    expect(recuperacionPara("jornada_vendedor_ocupado", "2026-11-12")).toEqual({
      fecha: "2026-11-12", mensaje: MENSAJE_RECUPERACION_VENDEDOR_OCUPADO,
    });
    for (const codigo of [
      null, "jornada_camion_con_jornada_abierta", "jornada_conflicto_idempotencia",
      "jornada_fecha_invalida", "jornada_no_autorizado", "42501", "toString", "__proto__",
    ]) {
      expect(recuperacionPara(codigo, HOY)).toBeUndefined();
    }
  });

  it("los mensajes plantean una posibilidad, nunca afirman que la apertura se registró", () => {
    for (const m of [MENSAJE_RECUPERACION_DUPLICADA, MENSAJE_RECUPERACION_VENDEDOR_OCUPADO]) {
      expect(m).toMatch(/^Puede que/);
      expect(m).toMatch(/Revisá las jornadas de esa fecha/);
      expect(m).not.toMatch(/se abrió correctamente|registrada|confirmad/i);
    }
  });

  it("la orientación usa la fecha de la intención (no hoy) y no lee jornadas ni declara éxito", async () => {
    const futura = { ...ENTRADA, fecha: "2026-11-20" };
    const m = armar({
      respuestas: [rechazo("jornada_duplicada")],
      lectura: { ok: true, datos: [jornada({ fecha: "2026-11-20" })], intentos: 1 },
    });
    m.c.solicitar();
    await m.c.confirmar(futura, PERMITIDAS);
    expect(m.fase()).toEqual({
      fase: "error",
      mensaje: "msg:jornada_duplicada",
      recuperacion: { fecha: "2026-11-20", mensaje: MENSAJE_RECUPERACION_DUPLICADA },
    });
    expect(m.lecturas).toHaveLength(0);
    expect(m.publicadas.some((f) => f.fase === "exito")).toBe(false);
    expect(m.c.claveEnCurso()).toBeNull();
  });

  it("no cambia la idempotencia: tras la orientación, un nuevo envío es otra intención con otra clave y el mismo contrato", async () => {
    const m = armar({ respuestas: [rechazo("jornada_vendedor_ocupado"), ok()] });
    m.c.solicitar();
    await m.c.confirmar(ENTRADA, PERMITIDAS);
    await m.c.confirmar({ ...ENTRADA, vendedorId: VENDEDOR_2 }, PERMITIDAS);
    expect(m.envios.map((e) => e.clave)).toEqual([
      "aaaaaaaa-aaaa-4aaa-8aaa-000000000001",
      "aaaaaaaa-aaaa-4aaa-8aaa-000000000002",
    ]);
    expect(m.envios.map((e) => Object.keys(e.comando).sort())).toEqual([
      ["camionId", "fecha", "tipo", "vendedorId"],
      ["camionId", "fecha", "tipo", "vendedorId"],
    ]);
    expect(m.fase().fase).toBe("exito");
  });
});
