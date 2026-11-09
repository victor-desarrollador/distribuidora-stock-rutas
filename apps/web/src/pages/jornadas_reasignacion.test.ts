import { describe, expect, it, vi } from "vitest";

import {
  MENSAJE_REINTENTO_NO_ENVIADO,
  MENSAJE_RESULTADO_DESCONOCIDO,
  MENSAJE_SIN_PERMISO,
  llamadaRpcJornada,
  type ComandoJornada,
  type EstadoJornada,
  type Jornada,
  type OpcionesEjecucion,
  type ResultadoJornada,
} from "../lib/jornadas";
import type { BuscarJornada } from "./jornadas_correccion";
import { crearControladorCorreccion } from "./jornadas_correccion";
import {
  MENSAJE_PENDIENTE_VERIFICAR,
  crearArbitroJornadas,
  jornadaRetenida,
  type ArbitroJornadas,
} from "./jornadas_operacion";
import {
  ESTADOS_REASIGNABLES,
  MENSAJE_MISMO_VENDEDOR,
  MENSAJE_REASIGNACION_COINCIDE,
  MENSAJE_REASIGNACION_NO_VISIBLE,
  MENSAJE_REASIGNACION_OK,
  MENSAJE_REASIGNACION_OTRO_ESTADO,
  MENSAJE_REASIGNACION_OTRO_VENDEDOR,
  MENSAJE_REASIGNACION_SIN_EFECTO,
  MENSAJE_REASIGNACION_SIN_VERIFICAR,
  MENSAJE_VENDEDOR_NO_OFRECIDO,
  admiteReasignacion,
  arbitroRevocable,
  crearControladorReasignacion,
  etiquetaVendedor,
  validarReasignacion,
  type EntradaReasignacion,
  type FaseReasignacion,
} from "./jornadas_reasignacion";
import { crearControladorSalida } from "./jornadas_salida";
import fuenteControlador from "./jornadas_reasignacion.ts?raw";
import fuenteHook from "../hooks/useReasignacionJornada.ts?raw";
import fuentePanel from "./JornadaReasignacionPanel.tsx?raw";

const OP = "99999999-9999-4999-8999-999999999999";
const ORIGINAL = "33333333-3333-4333-8333-333333333333";
const NUEVO = "44444444-4444-4444-8444-444444444444";
const TERCERO = "55555555-5555-4555-8555-555555555555";
// Usuario de otra empresa: nunca llega en la lista (la RPC filtra por empresa).
const AJENO = "88888888-8888-4888-8888-888888888888";
const FECHA = "2026-11-10";

function jornada(n: number, estado: EstadoJornada = "abierta", cambios: Partial<Jornada> = {}): Jornada {
  return {
    id: `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`,
    fecha: FECHA,
    camionId: "22222222-2222-4222-8222-222222222222",
    vendedorId: ORIGINAL,
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
    ...cambios,
  };
}

const entrada = (cambios: Partial<EntradaReasignacion> = {}): EntradaReasignacion => ({
  vendedorId: NUEVO,
  permitidos: [NUEVO, TERCERO],
  ...cambios,
});

const exito = (): ResultadoJornada<string> => ({ ok: true, datos: OP, intentos: 1 });
const rechazo = (codigo: string, mensaje = "rechazo seguro"): ResultadoJornada<string> => ({
  ok: false, intentos: 1, error: { codigo, mensaje, resultadoDesconocido: false },
});
const sinRespuesta = (): ResultadoJornada<string> => ({
  ok: false, intentos: 3, error: { codigo: null, mensaje: MENSAJE_RESULTADO_DESCONOCIDO, resultadoDesconocido: true },
});
const transitorio = (): ResultadoJornada<string> => ({
  ok: false, intentos: 3, error: { codigo: "40001", mensaje: "concurrencia", resultadoDesconocido: false },
});

/** Puerto y búsqueda con respuestas resueltas a mano. */
function armar(arbitro?: ArbitroJornadas, usuarioEsperado?: string) {
  const envios: Array<{
    comando: ComandoJornada;
    clave: string;
    opciones?: OpcionesEjecucion;
    resolver: (r: ResultadoJornada<string>) => void;
  }> = [];
  const busquedas: Array<{ id: string; fechas: string[]; resolver: (j: Jornada | null | undefined) => void }> = [];
  const publicadas: FaseReasignacion[] = [];
  const releer = vi.fn();
  let n = 0;
  const claves = () => `aaaaaaaa-0000-4000-8000-${(++n).toString(16).padStart(12, "0")}`;
  const puerto = {
    ejecutar(comando: ComandoJornada, clave: string, opciones?: OpcionesEjecucion) {
      return new Promise<ResultadoJornada<string>>((resolver) => envios.push({ comando, clave, opciones, resolver }));
    },
  };
  const buscar: BuscarJornada = (id, fechas) =>
    new Promise((resolver) => busquedas.push({ id, fechas, resolver }));
  const c = crearControladorReasignacion(puerto, buscar, releer, (f) => publicadas.push(f), {
    generarClave: claves,
    arbitro,
    usuarioEsperado,
  });
  return { c, envios, busquedas, publicadas, releer, ultima: () => c.obtener() };
}

const tick = () => new Promise((r) => setTimeout(r, 0));

/** Confirma y deja la respuesta pendiente. */
async function enviar(m: ReturnType<typeof armar>, j = jornada(1)) {
  m.c.solicitar(j);
  const p = m.c.confirmar(entrada());
  await tick();
  // Envuelta: devolverla desde una función async esperaría su resolución.
  return { p };
}

/** Envía, pierde la respuesta y deja la verificación pendiente. */
async function perderRespuesta(m: ReturnType<typeof armar>, j = jornada(1)) {
  const { p } = await enviar(m, j);
  m.envios[0].resolver(sinRespuesta());
  await tick();
  return { p };
}

describe("reasignación: estados", () => {
  it("sólo abierta y cargada la admiten", () => {
    expect(ESTADOS_REASIGNABLES).toEqual(["abierta", "cargada"]);
    for (const e of ["abierta", "cargada"] as const) expect(admiteReasignacion(jornada(1, e))).toBe(true);
    for (const e of ["en_reparto", "ventas_finalizadas", "regreso_contado", "cerrada"] as const) {
      expect(admiteReasignacion(jornada(1, e))).toBe(false);
    }
  });

  it("jornada abierta: abre la confirmación", () => {
    const m = armar();
    m.c.solicitar(jornada(1, "abierta"));
    expect(m.ultima()).toEqual({ fase: "confirmando", jornadaId: jornada(1).id });
  });

  it("jornada cargada: abre la confirmación", () => {
    const m = armar();
    m.c.solicitar(jornada(1, "cargada"));
    expect(m.ultima().fase).toBe("confirmando");
  });

  it("salida confirmada (en_reparto) o posterior: no se abre ni se envía nada", async () => {
    for (const e of ["en_reparto", "ventas_finalizadas", "regreso_contado", "cerrada"] as const) {
      const m = armar();
      m.c.solicitar(jornada(1, e));
      await m.c.confirmar(entrada());
      expect(m.ultima().fase).toBe("inactiva");
      expect(m.envios).toHaveLength(0);
    }
  });
});

describe("reasignación: validación local", () => {
  it("el mismo vendedor se rechaza sin enviar", async () => {
    expect(validarReasignacion(jornada(1), entrada({ vendedorId: ORIGINAL, permitidos: [ORIGINAL] }))).toBe(
      MENSAJE_MISMO_VENDEDOR
    );
    // También con otra capitalización del uuid.
    expect(
      validarReasignacion(jornada(1), entrada({ vendedorId: ORIGINAL.toUpperCase(), permitidos: [ORIGINAL] }))
    ).toBe(MENSAJE_MISMO_VENDEDOR);
    const m = armar();
    m.c.solicitar(jornada(1));
    await m.c.confirmar(entrada({ vendedorId: ORIGINAL, permitidos: [ORIGINAL] }));
    expect(m.ultima()).toEqual({ fase: "confirmando", jornadaId: jornada(1).id, error: MENSAJE_MISMO_VENDEDOR });
    expect(m.envios).toHaveLength(0);
  });

  it("un vendedor que no vino de la lista (por ejemplo, de otra empresa) se rechaza sin enviar", async () => {
    expect(validarReasignacion(jornada(1), entrada({ vendedorId: AJENO }))).toBe(MENSAJE_VENDEDOR_NO_OFRECIDO);
    expect(validarReasignacion(jornada(1), entrada({ vendedorId: "no-uuid", permitidos: ["no-uuid"] }))).toBe(
      MENSAJE_VENDEDOR_NO_OFRECIDO
    );
    expect(validarReasignacion(jornada(1), entrada({ permitidos: [] }))).toBe(MENSAJE_VENDEDOR_NO_OFRECIDO);
    const m = armar();
    m.c.solicitar(jornada(1));
    await m.c.confirmar(entrada({ vendedorId: AJENO }));
    expect(m.envios).toHaveLength(0);
  });

  it("un vendedor válido y distinto pasa", () => {
    expect(validarReasignacion(jornada(1), entrada())).toBeNull();
  });
});

describe("reasignación: envío", () => {
  it("envía exactamente reasignar_vendedor con la jornada y el vendedor (wrapper existente)", async () => {
    const m = armar();
    const { p } = await enviar(m);
    expect(m.ultima()).toEqual({ fase: "enviando", jornadaId: jornada(1).id });
    expect(m.envios).toHaveLength(1);
    expect(m.envios[0].comando).toEqual({ tipo: "reasignar", jornadaId: jornada(1).id, vendedorId: NUEVO });
    const llamada = llamadaRpcJornada(m.envios[0].comando, m.envios[0].clave);
    expect(llamada.nombre).toBe("reasignar_vendedor");
    expect(llamada.argumentos).toEqual({
      p_idempotency_key: m.envios[0].clave,
      p_jornada_id: jornada(1).id,
      p_vendedor_id: NUEVO,
    });
    m.envios[0].resolver(exito());
    await p;
  });

  it("éxito confirmado sólo con la respuesta del servidor: publica éxito y relee", async () => {
    const m = armar();
    const { p } = await enviar(m);
    expect(m.publicadas.some((f) => f.fase === "exito")).toBe(false);
    m.envios[0].resolver(exito());
    await p;
    expect(m.ultima()).toEqual({ fase: "exito", jornadaId: jornada(1).id, mensaje: MENSAJE_REASIGNACION_OK });
    expect(m.releer).toHaveBeenCalledTimes(1);
    expect(m.c.claveEnCurso()).toBeNull();
  });

  it("doble clic: un solo envío", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const a = m.c.confirmar(entrada());
    const b = m.c.confirmar(entrada());
    m.c.solicitar(jornada(1));
    await tick();
    expect(m.envios).toHaveLength(1);
    m.envios[0].resolver(exito());
    await Promise.all([a, b]);
  });

  it("los datos de la intención quedan congelados", async () => {
    const m = armar();
    const { p } = await enviar(m);
    const datos = m.c.datosEnCurso();
    expect(Object.isFrozen(datos)).toBe(true);
    expect(datos).toEqual({ jornadaId: jornada(1).id, fecha: FECHA, original: ORIGINAL, vendedorId: NUEVO });
    m.envios[0].resolver(exito());
    await p;
  });
});

describe("reasignación: rechazos definitivos", () => {
  it("error de permisos (jornada_no_autorizado): muestra el mensaje, no relee, descarta la intención", async () => {
    const m = armar();
    const { p } = await enviar(m);
    m.envios[0].resolver(rechazo("jornada_no_autorizado", MENSAJE_SIN_PERMISO));
    await p;
    expect(m.ultima()).toEqual({ fase: "error", jornadaId: jornada(1).id, mensaje: MENSAJE_SIN_PERMISO });
    expect(m.releer).not.toHaveBeenCalled();
    expect(m.c.claveEnCurso()).toBeNull();
  });

  it("42501 (sin EXECUTE): error de permisos", async () => {
    const m = armar();
    const { p } = await enviar(m);
    m.envios[0].resolver(rechazo("42501", MENSAJE_SIN_PERMISO));
    await p;
    expect(m.ultima().fase).toBe("error");
    expect(m.releer).not.toHaveBeenCalled();
  });

  it.each([
    "jornada_estado_invalido",
    "jornada_no_encontrada",
    "jornada_sin_cambios",
    "jornada_vendedor_ocupado",
    "jornada_vendedor_no_encontrado",
    "jornada_vendedor_invalido",
  ])("%s: error y relectura de la lista", async (codigo) => {
    const m = armar();
    const { p } = await enviar(m);
    m.envios[0].resolver(rechazo(codigo));
    await p;
    expect(m.ultima().fase).toBe("error");
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  it("tras un rechazo se puede iniciar otra intención con OTRA clave", async () => {
    const m = armar();
    const { p } = await enviar(m);
    m.envios[0].resolver(rechazo("jornada_vendedor_ocupado"));
    await p;
    m.c.solicitar(jornada(1));
    const q = m.c.confirmar(entrada({ vendedorId: TERCERO }));
    await tick();
    expect(m.envios).toHaveLength(2);
    expect(m.envios[1].clave).not.toBe(m.envios[0].clave);
    m.envios[1].resolver(exito());
    await q;
  });
});

describe("reasignación: respuesta perdida o incierta (nunca se afirma éxito por lectura)", () => {
  it("fallo de red: verifica leyendo la jornada en su fecha, sin reenviar por cuenta propia", async () => {
    const m = armar();
    await perderRespuesta(m);
    expect(m.ultima()).toEqual({ fase: "verificando", jornadaId: jornada(1).id });
    expect(m.busquedas).toEqual([expect.objectContaining({ id: jornada(1).id, fechas: [FECHA] })]);
    expect(m.envios).toHaveLength(1);
  });

  it("40001/40P01 agotados: también verifica antes de ofrecer el reintento", async () => {
    const m = armar();
    const { p } = await enviar(m);
    m.envios[0].resolver(transitorio());
    await tick();
    expect(m.ultima().fase).toBe("verificando");
    m.busquedas[0].resolver(jornada(1));
    await p;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true });
  });

  it("la jornada ya tiene el vendedor pedido: incierta (NO éxito), reintentable", async () => {
    const m = armar();
    const { p } = await perderRespuesta(m);
    m.busquedas[0].resolver(jornada(1, "abierta", { vendedorId: NUEVO }));
    await p;
    expect(m.ultima()).toEqual({
      fase: "desconocido", jornadaId: jornada(1).id, mensaje: MENSAJE_REASIGNACION_COINCIDE, reintentable: true,
    });
    expect(m.publicadas.some((f) => f.fase === "exito")).toBe(false);
    expect(m.releer).not.toHaveBeenCalled();
  });

  it("sigue el vendedor original en abierta/cargada: sin efecto, reintentable", async () => {
    for (const e of ["abierta", "cargada"] as const) {
      const m = armar();
      const { p } = await perderRespuesta(m, jornada(1, e));
      m.busquedas[0].resolver(jornada(1, e));
      await p;
      expect(m.ultima()).toEqual({
        fase: "desconocido", jornadaId: jornada(1).id, mensaje: MENSAJE_REASIGNACION_SIN_EFECTO, reintentable: true,
      });
    }
  });

  it("vendedor original pero la jornada ya salió: incierta reintentable (el servidor sólo confirma o rechaza)", async () => {
    const m = armar();
    const { p } = await perderRespuesta(m);
    m.busquedas[0].resolver(jornada(1, "en_reparto"));
    await p;
    expect(m.ultima()).toMatchObject({ mensaje: MENSAJE_REASIGNACION_OTRO_ESTADO, reintentable: true });
  });

  it("un tercer vendedor: incierta SIN reintento (no se pisa el cambio de otra persona)", async () => {
    const m = armar();
    const { p } = await perderRespuesta(m);
    m.busquedas[0].resolver(jornada(1, "cargada", { vendedorId: TERCERO }));
    await p;
    expect(m.ultima()).toMatchObject({ mensaje: MENSAJE_REASIGNACION_OTRO_VENDEDOR, reintentable: false });
    await m.c.reintentar();
    expect(m.envios).toHaveLength(1);
  });

  it("la jornada no aparece en su fecha: incierta sin reintento", async () => {
    const m = armar();
    const { p } = await perderRespuesta(m);
    m.busquedas[0].resolver(null);
    await p;
    expect(m.ultima()).toMatchObject({ mensaje: MENSAJE_REASIGNACION_NO_VISIBLE, reintentable: false });
  });

  it("la lectura de verificación falla: sin verificar, sin reintento; «Verificar estado» vuelve a leer", async () => {
    const m = armar();
    const { p } = await perderRespuesta(m);
    m.busquedas[0].resolver(undefined);
    await p;
    expect(m.ultima()).toMatchObject({ mensaje: MENSAJE_REASIGNACION_SIN_VERIFICAR, reintentable: false });
    await m.c.reintentar();
    expect(m.envios).toHaveLength(1);
    const v = m.c.verificarEstado();
    await tick();
    expect(m.busquedas).toHaveLength(2);
    m.busquedas[1].resolver(jornada(1));
    await v;
    expect(m.ultima()).toMatchObject({ mensaje: MENSAJE_REASIGNACION_SIN_EFECTO, reintentable: true });
  });

  it("la búsqueda lanza: sin verificar", async () => {
    const releer = vi.fn();
    const fases: FaseReasignacion[] = [];
    let resolverEnvio: (r: ResultadoJornada<string>) => void = () => undefined;
    const c = crearControladorReasignacion(
      { ejecutar: () => new Promise((r) => (resolverEnvio = r)) },
      () => Promise.reject(new Error("red")),
      releer,
      (f) => fases.push(f)
    );
    c.solicitar(jornada(1));
    const p = c.confirmar(entrada());
    await tick();
    resolverEnvio(sinRespuesta());
    await p;
    expect(c.obtener()).toMatchObject({ fase: "desconocido", mensaje: MENSAJE_REASIGNACION_SIN_VERIFICAR });
  });

  it("reintento manual: MISMA clave y MISMO comando; el éxito llega sólo de la respuesta del servidor", async () => {
    const m = armar();
    const { p } = await perderRespuesta(m);
    m.busquedas[0].resolver(jornada(1, "abierta", { vendedorId: NUEVO }));
    await p;
    const r = m.c.reintentar();
    await tick();
    expect(m.envios).toHaveLength(2);
    expect(m.envios[1].clave).toBe(m.envios[0].clave);
    expect(m.envios[1].comando).toEqual(m.envios[0].comando);
    m.envios[1].resolver(exito());
    await r;
    expect(m.ultima()).toMatchObject({ fase: "exito", mensaje: MENSAJE_REASIGNACION_OK });
  });

  it("con resultado desconocido no se inicia otra intención (ni en otra jornada)", async () => {
    const m = armar();
    const { p } = await perderRespuesta(m);
    m.busquedas[0].resolver(jornada(1));
    await p;
    m.c.solicitar(jornada(2));
    expect(m.ultima().fase).toBe("desconocido");
    expect(m.ultima().fase === "desconocido" && m.ultima()).toMatchObject({ jornadaId: jornada(1).id });
  });

  it("sin reintentos automáticos: tras verificar no hay más envíos que el original", async () => {
    const m = armar();
    const { p } = await perderRespuesta(m);
    m.busquedas[0].resolver(jornada(1));
    await p;
    await tick();
    expect(m.envios).toHaveLength(1);
  });
});

describe("reasignación: árbitro con salida y corrección", () => {
  it("mientras la reasignación retiene la jornada, salida y corrección no se inician sobre ella", async () => {
    const arbitro = crearArbitroJornadas();
    const m = armar(arbitro);
    const salida = crearControladorSalida({ ejecutar: vi.fn() }, vi.fn(), vi.fn(), vi.fn(), undefined, arbitro);
    const correccion = crearControladorCorreccion({ ejecutar: vi.fn() }, vi.fn(), vi.fn(), vi.fn(), { arbitro });
    m.c.solicitar(jornada(1, "cargada"));
    salida.solicitar(jornada(1, "cargada"));
    expect(salida.obtener().fase).toBe("inactiva");
    m.c.cancelar();
    m.c.solicitar(jornada(1, "abierta"));
    correccion.solicitar(jornada(1, "abierta"));
    expect(correccion.obtener().fase).toBe("inactiva");
    // Otra jornada no queda retenida.
    correccion.solicitar(jornada(2, "abierta"));
    expect(correccion.obtener().fase).toBe("confirmando");
  });

  it("si otra operación retiene la jornada, la reasignación no se abre", () => {
    const arbitro = crearArbitroJornadas();
    const m = armar(arbitro);
    const correccion = crearControladorCorreccion({ ejecutar: vi.fn() }, vi.fn(), vi.fn(), vi.fn(), { arbitro });
    correccion.solicitar(jornada(1, "abierta"));
    m.c.solicitar(jornada(1, "abierta"));
    expect(m.ultima().fase).toBe("inactiva");
    expect(jornadaRetenida(correccion.obtener())).toBe(jornada(1).id);
  });
});

describe("reasignación: participación revocable (cambio de sesión)", () => {
  it("revocar libera la retención y las actualizaciones tardías no la vuelven a tomar", () => {
    const base = crearArbitroJornadas();
    const otro = Symbol("otro");
    const r = arbitroRevocable(base);
    const yo = Symbol("yo");
    r.arbitro.actualizar(yo, "J1");
    expect(base.retenidaPorOtra(otro, "J1")).toBe(true);
    r.revocar();
    expect(base.retenidaPorOtra(otro, "J1")).toBe(false);
    r.arbitro.actualizar(yo, "J1");
    expect(base.retenidaPorOtra(otro, "J1")).toBe(false);
  });

  it("reactivar (remontaje del mismo contexto) vuelve a aplicar la última retención", () => {
    const base = crearArbitroJornadas();
    const otro = Symbol("otro");
    const r = arbitroRevocable(base);
    r.arbitro.actualizar(Symbol("yo"), "J1");
    r.revocar();
    r.reactivar();
    expect(base.retenidaPorOtra(otro, "J1")).toBe(true);
  });

  it("tras detener el controlador, una respuesta tardía no publica ni relee", async () => {
    const m = armar();
    const { p } = await enviar(m);
    const publicadasAntes = m.publicadas.length;
    m.c.detener();
    m.envios[0].resolver(exito());
    await p;
    expect(m.publicadas).toHaveLength(publicadasAntes);
    expect(m.releer).not.toHaveBeenCalled();
  });
});

// FE-2D (H-2): una respuesta tardía con el controlador detenido se resuelve en
// el estado interno (sin publicar, verificar ni releer) y `iniciar` la publica.
describe("FE-2D H-2: detener → respuesta tardía → iniciar", () => {
  const USUARIO = "66666666-6666-4666-8666-666666666666";
  const otro = Symbol("otra operación");

  it("O1: éxito del servidor mientras está detenido → no queda «enviando»; al reanudar publica y relee UNA vez", async () => {
    const m = armar();
    const { p } = await enviar(m);
    m.c.detener();
    m.envios[0].resolver(exito());
    await p;
    expect(m.ultima()).toMatchObject({ fase: "exito", mensaje: MENSAJE_REASIGNACION_OK });
    expect(m.publicadas.at(-1)?.fase).toBe("enviando");
    expect(m.releer).not.toHaveBeenCalled();
    m.c.iniciar();
    expect(m.publicadas.at(-1)).toMatchObject({ fase: "exito" });
    expect(m.releer).toHaveBeenCalledTimes(1);
    // Otra reanudación sin cambios no republica ni relee.
    const n = m.publicadas.length;
    m.c.detener();
    m.c.iniciar();
    expect(m.publicadas).toHaveLength(n);
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  it("O2: sin respuesta mientras está detenido → desconocido sin verificar; al reanudar se verifica y reintenta con la MISMA clave", async () => {
    const m = armar();
    const { p } = await enviar(m);
    m.c.detener();
    m.envios[0].resolver(sinRespuesta());
    await p;
    expect(m.busquedas).toHaveLength(0);
    expect(m.ultima()).toMatchObject({ fase: "desconocido", mensaje: MENSAJE_PENDIENTE_VERIFICAR, reintentable: false });
    expect(m.c.claveEnCurso()).toBe(m.envios[0].clave);
    m.c.iniciar();
    expect(m.publicadas.at(-1)).toMatchObject({ fase: "desconocido", reintentable: false });
    expect(m.releer).not.toHaveBeenCalled();
    // Sin verificar no se reintenta.
    await m.c.reintentar();
    expect(m.envios).toHaveLength(1);
    const v = m.c.verificarEstado();
    await tick();
    m.busquedas[0].resolver(jornada(1));
    await v;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true });
    const r = m.c.reintentar();
    await tick();
    expect(m.envios).toHaveLength(2);
    expect(m.envios[1].clave).toBe(m.envios[0].clave);
    m.envios[1].resolver(exito());
    await r;
    expect(m.ultima().fase).toBe("exito");
  });

  it("O2b: 40001 agotado mientras está detenido → también queda desconocido (no se afirma fracaso)", async () => {
    const m = armar();
    const { p } = await enviar(m);
    m.c.detener();
    m.envios[0].resolver(transitorio());
    await p;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: false });
    expect(m.busquedas).toHaveLength(0);
  });

  it("O3: rechazo definitivo mientras está detenido → error, intención descartada, sin releer", async () => {
    const m = armar();
    const { p } = await enviar(m);
    m.c.detener();
    m.envios[0].resolver(rechazo("jornada_estado_invalido"));
    await p;
    expect(m.ultima()).toMatchObject({ fase: "error" });
    expect(m.c.claveEnCurso()).toBeNull();
    expect(m.releer).not.toHaveBeenCalled();
    m.c.iniciar();
    expect(m.publicadas.at(-1)).toMatchObject({ fase: "error" });
  });

  it("O4: detenido durante la verificación → no usa la lectura (ni «registrada» ni «sin efecto»); queda pendiente de verificar", async () => {
    const m = armar();
    const { p } = await perderRespuesta(m);
    m.c.detener();
    m.busquedas[0].resolver(jornada(1, "abierta", { vendedorId: NUEVO }));
    await p;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", mensaje: MENSAJE_PENDIENTE_VERIFICAR, reintentable: false });
    expect(m.releer).not.toHaveBeenCalled();
  });

  it("O5: iniciar sin cambios no publica nada", () => {
    const m = armar();
    m.c.iniciar();
    m.c.detener();
    m.c.iniciar();
    expect(m.publicadas).toHaveLength(0);
  });

  it("O6: árbitro — el desconocido sigue reteniendo; éxito y error liberan", async () => {
    const a1 = crearArbitroJornadas();
    const m1 = armar(a1);
    const e1 = await enviar(m1);
    m1.c.detener();
    m1.envios[0].resolver(sinRespuesta());
    await e1.p;
    expect(a1.retenidaPorOtra(otro, jornada(1).id)).toBe(true);

    const a2 = crearArbitroJornadas();
    const m2 = armar(a2);
    const e2 = await enviar(m2);
    m2.c.detener();
    m2.envios[0].resolver(exito());
    await e2.p;
    expect(a2.retenidaPorOtra(otro, jornada(1).id)).toBe(false);
  });

  it("O7: el envío pasa `continuar` (sigue a iniciar/detener) y el usuario esperado", async () => {
    const m = armar(undefined, USUARIO);
    await enviar(m);
    const o = m.envios[0].opciones!;
    expect(o.usuarioEsperado).toBe(USUARIO);
    expect(o.continuar!()).toBe(true);
    m.c.detener();
    expect(o.continuar!()).toBe(false);
    m.c.iniciar();
    expect(o.continuar!()).toBe(true);
  });
});

// FE-2E (H-1 por intención) en el motor, vía reasignación.
describe("FE-2E: reintento manual sin envío (motor)", () => {
  const nadaEnviado = (): ResultadoJornada<string> => ({
    ok: false, intentos: 0, error: { codigo: null, mensaje: "sesión cambiada", resultadoDesconocido: false },
  });

  /** Envía, pierde la respuesta, verifica «sin efecto» y queda reintentable. */
  async function desconocidaReintentable(m: ReturnType<typeof armar>) {
    const { p } = await perderRespuesta(m);
    m.busquedas[0].resolver(jornada(1));
    await p;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true });
  }

  it("M1: el reintento manual no envía nada → la intención (clave y datos) se conserva en desconocido", async () => {
    const arbitro = crearArbitroJornadas();
    const m = armar(arbitro);
    await desconocidaReintentable(m);
    const clave = m.c.claveEnCurso();
    const datos = m.c.datosEnCurso();
    const r = m.c.reintentar();
    await tick();
    m.envios[1].resolver(nadaEnviado());
    await r;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true, mensaje: MENSAJE_REINTENTO_NO_ENVIADO });
    expect(m.c.claveEnCurso()).toBe(clave);
    expect(m.c.datosEnCurso()).toBe(datos);
    // Sigue reteniendo la jornada y no se puede iniciar otra intención.
    expect(arbitro.retenidaPorOtra(Symbol("salida"), jornada(1).id)).toBe(true);
    m.c.solicitar(jornada(2));
    expect(m.ultima().fase).toBe("desconocido");
    expect(m.releer).not.toHaveBeenCalled();
    expect(m.busquedas).toHaveLength(1);
  });

  it("M2: el reintento manual exige el usuario que hizo el primer envío (identidad por intención)", async () => {
    const m = armar();
    const { p } = await enviar(m);
    // El wrapper informa el actor justo antes de despachar el primer envío.
    m.envios[0].opciones?.alFijarActor?.(USUARIO_A_E2E);
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.busquedas[0].resolver(jornada(1));
    await p;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true });
    const r = m.c.reintentar();
    await tick();
    expect(m.envios[1].opciones?.usuarioEsperado).toBe(USUARIO_A_E2E);
    expect(m.envios[1].clave).toBe(m.envios[0].clave);
    m.envios[1].resolver(exito());
    await r;
  });

  it("M3: el actor del primer envío prevalece sobre el del controlador y no se reemplaza en llamadas posteriores", async () => {
    const m = armar(undefined, USUARIO_A_E2E);
    const { p } = await enviar(m);
    expect(m.envios[0].opciones?.usuarioEsperado).toBe(USUARIO_A_E2E);
    m.envios[0].opciones?.alFijarActor?.(USUARIO_A_E2E);
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.busquedas[0].resolver(jornada(1));
    await p;
    const r = m.c.reintentar();
    await tick();
    // Un aviso posterior con otro usuario no reemplaza el actor de la intención.
    m.envios[1].opciones?.alFijarActor?.("bbbbbbbb-2222-4222-8222-222222222222");
    m.envios[1].resolver(nadaEnviado());
    await r;
    const r2 = m.c.reintentar();
    await tick();
    expect(m.envios[2].opciones?.usuarioEsperado).toBe(USUARIO_A_E2E);
    m.envios[2].resolver(exito());
    await r2;
  });

  it("M4: una intención NUEVA cuyo primer envío no sale (nada enviado nunca) → error y se descarta (sin cambios)", async () => {
    const arbitro = crearArbitroJornadas();
    const m = armar(arbitro);
    const { p } = await enviar(m);
    m.envios[0].resolver(nadaEnviado());
    await p;
    expect(m.ultima()).toMatchObject({ fase: "error", mensaje: "sesión cambiada" });
    expect(m.c.claveEnCurso()).toBeNull();
    expect(arbitro.retenidaPorOtra(Symbol("salida"), jornada(1).id)).toBe(false);
    expect(m.busquedas).toHaveLength(0);
  });

  it("M5: detenido, un reintento que no envía nada conserva la intención sin publicar; al reanudar se publica", async () => {
    const m = armar();
    await desconocidaReintentable(m);
    const clave = m.c.claveEnCurso();
    const r = m.c.reintentar();
    await tick();
    m.c.detener();
    const n = m.publicadas.length;
    m.envios[1].resolver(nadaEnviado());
    await r;
    expect(m.publicadas).toHaveLength(n);
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true });
    expect(m.c.claveEnCurso()).toBe(clave);
    expect(m.busquedas).toHaveLength(1);
    m.c.iniciar();
    expect(m.publicadas.at(-1)).toMatchObject({ fase: "desconocido", mensaje: MENSAJE_REINTENTO_NO_ENVIADO });
    expect(m.releer).not.toHaveBeenCalled();
  });

  it("M6: una intención nueva tras un éxito no hereda el actor de la anterior", async () => {
    const m = armar();
    const { p } = await enviar(m);
    m.envios[0].opciones?.alFijarActor?.(USUARIO_A_E2E);
    m.envios[0].resolver(exito());
    await p;
    m.c.trasRelectura();
    m.c.solicitar(jornada(2));
    const p2 = m.c.confirmar(entrada());
    await tick();
    expect(m.envios[1].opciones?.usuarioEsperado).toBeUndefined();
    expect(m.envios[1].clave).not.toBe(m.envios[0].clave);
    m.envios[1].resolver(exito());
    await p2;
  });
});

const USUARIO_A_E2E = "aaaaaaaa-1111-4111-8111-111111111111";

describe("reasignación: etiqueta del vendedor", () => {
  it("usa nombre y rol de la lista; si no está, un id corto", () => {
    const lista = { estado: "listo" as const, vendedores: [{ usuarioId: NUEVO, nombre: "Ana", rol: "vendedor_piloto" as const }] };
    expect(etiquetaVendedor(lista, NUEVO.toUpperCase())).toMatch(/^Ana \(/);
    expect(etiquetaVendedor(lista, ORIGINAL)).toBe(`Vendedor ${ORIGINAL.slice(0, 8)}`);
    expect(etiquetaVendedor({ estado: "cargando" }, NUEVO)).toBe(`Vendedor ${NUEVO.slice(0, 8)}`);
  });
});

describe("reasignación: guardas estáticas", () => {
  const fuentes = { fuenteControlador, fuenteHook, fuentePanel };
  it.each(Object.entries(fuentes))("%s no escribe tablas ni usa otras RPC de escritura", (_n, fuente) => {
    expect(fuente).not.toMatch(/\.from\(/);
    expect(fuente).not.toMatch(/\.(insert|update|upsert|delete)\(/);
    expect(fuente).not.toMatch(/\.rpc\(/);
    expect(fuente).not.toMatch(/registrar_carga|registrar_descarga|"cargar"|"descargar"/);
    expect(fuente).not.toMatch(/localStorage|sessionStorage|indexedDB/);
  });

  it("el controlador sólo construye el comando `reasignar`", () => {
    expect(fuenteControlador.match(/tipo:\s*"(\w+)"/g)).toEqual(['tipo: "reasignar"']);
  });
});
