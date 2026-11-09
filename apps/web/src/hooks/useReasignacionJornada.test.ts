import { describe, expect, it, vi } from "vitest";

import type {
  ComandoJornada,
  EstadoJornada,
  Jornada,
  OpcionesEjecucion,
  ResultadoJornada,
} from "../lib/jornadas";
import type { ResultadoVendedores } from "../lib/vendedores_jornada";
import type { EstadoVendedores } from "../pages/jornadas_apertura";
import { crearArbitroJornadas } from "../pages/jornadas_operacion";
import type { FaseReasignacion } from "../pages/jornadas_reasignacion";
import {
  crearSesionReasignacion,
  usuarioDeContexto,
  type DependenciasReasignacion,
} from "./useReasignacionJornada";
import fuenteHook from "./useReasignacionJornada.ts?raw";

const ORIGINAL = "33333333-3333-4333-8333-333333333333";
const NUEVO = "44444444-4444-4444-8444-444444444444";
const OP = "99999999-9999-4999-8999-999999999999";

function jornada(estado: EstadoJornada = "abierta", cambios: Partial<Jornada> = {}): Jornada {
  return {
    id: "00000000-0000-4000-8000-000000000001",
    fecha: "2026-11-10",
    camionId: "22222222-2222-4222-8222-222222222222",
    vendedorId: ORIGINAL,
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
    ...cambios,
  };
}

const tick = () => new Promise((r) => setTimeout(r, 0));

function armar(usuarioId?: string, arbitro = crearArbitroJornadas()) {
  const envios: Array<{
    comando: ComandoJornada;
    clave: string;
    opciones?: OpcionesEjecucion;
    resolver: (r: ResultadoJornada<string>) => void;
  }> = [];
  const lecturas: Array<{ fecha?: string; resolver: (r: ResultadoJornada<Jornada[]>) => void }> = [];
  const listados: Array<(r: ResultadoVendedores) => void> = [];
  const puertoJornadas = vi.fn(() => ({
    ejecutar: (comando: ComandoJornada, clave: string, opciones?: OpcionesEjecucion) =>
      new Promise<ResultadoJornada<string>>((resolver) => envios.push({ comando, clave, opciones, resolver })),
    leerTodasLasJornadas: (filtro?: { fecha?: string }) =>
      new Promise<ResultadoJornada<Jornada[]>>((resolver) => lecturas.push({ fecha: filtro?.fecha, resolver })),
  }));
  const puertoVendedores = vi.fn(() => ({
    listarVendedores: () => new Promise<ResultadoVendedores>((r) => listados.push(r)),
  }));
  const deps: DependenciasReasignacion = { puertoJornadas, puertoVendedores };
  const fases: FaseReasignacion[] = [];
  const vendedores: EstadoVendedores[] = [];
  const releer = vi.fn();
  const sesion = crearSesionReasignacion(
    releer,
    arbitro,
    (f) => fases.push(f),
    (e) => vendedores.push(e),
    deps,
    usuarioId
  );
  return { sesion, envios, lecturas, listados, puertoJornadas, puertoVendedores, fases, vendedores, releer, arbitro };
}

describe("sesión de reasignación", () => {
  it("crearla no construye puertos ni lee nada (montar la pantalla no toca la red)", () => {
    const m = armar();
    m.sesion.iniciar();
    expect(m.puertoJornadas).not.toHaveBeenCalled();
    expect(m.puertoVendedores).not.toHaveBeenCalled();
  });

  it("abrir el formulario sobre una jornada abierta lee la lista de vendedores una vez", () => {
    const m = armar();
    m.sesion.solicitar(jornada("abierta"));
    expect(m.listados).toHaveLength(1);
    expect(m.vendedores).toEqual([{ estado: "cargando" }]);
  });

  it("sobre una jornada en reparto no abre nada ni lee vendedores", () => {
    const m = armar();
    m.sesion.solicitar(jornada("en_reparto"));
    expect(m.listados).toHaveLength(0);
    expect(m.fases).toHaveLength(0);
  });

  it("respuesta perdida: lee la jornada de su fecha y no declara éxito", async () => {
    const m = armar();
    m.sesion.solicitar(jornada("cargada"));
    const p = m.sesion.controlador.confirmar({ vendedorId: NUEVO, permitidos: [NUEVO] });
    await tick();
    m.envios[0].resolver({
      ok: false, intentos: 3, error: { codigo: null, mensaje: "x", resultadoDesconocido: true },
    });
    await tick();
    expect(m.lecturas).toEqual([expect.objectContaining({ fecha: "2026-11-10" })]);
    m.lecturas[0].resolver({ ok: true, datos: [jornada("cargada", { vendedorId: NUEVO })], intentos: 1 });
    await p;
    expect(m.sesion.controlador.obtener()).toMatchObject({ fase: "desconocido", reintentable: true });
    expect(m.fases.some((f) => f.fase === "exito")).toBe(false);
  });

  it("cambio de sesión: detener descarta la intención, libera el árbitro y nada tardío se publica", async () => {
    const m = armar();
    m.sesion.iniciar();
    m.sesion.solicitar(jornada("abierta"));
    const p = m.sesion.controlador.confirmar({ vendedorId: NUEVO, permitidos: [NUEVO] });
    await tick();
    const otro = Symbol("salida");
    expect(m.arbitro.retenidaPorOtra(otro, jornada().id)).toBe(true);
    const fasesAntes = m.fases.length;
    const vendedoresAntes = m.vendedores.length;

    m.sesion.detener();
    expect(m.arbitro.retenidaPorOtra(otro, jornada().id)).toBe(false);

    m.envios[0].resolver({ ok: true, datos: OP, intentos: 1 });
    m.listados[0]({ ok: true, vendedores: [] });
    await p;
    await tick();
    expect(m.fases).toHaveLength(fasesAntes);
    expect(m.vendedores).toHaveLength(vendedoresAntes);
    expect(m.releer).not.toHaveBeenCalled();
    // La retención no vuelve aunque el controlador viejo haya emitido.
    expect(m.arbitro.retenidaPorOtra(otro, jornada().id)).toBe(false);
  });

  it("el hook descarta la sesión al cambiar el contexto y no crea nada sin contexto", () => {
    // Guardas estructurales del hook (sin renderizador de React en el proyecto).
    expect(fuenteHook).toMatch(/if \(ctx === null\) return null;/);
    expect(fuenteHook).toMatch(/actual\.contexto !== ctx/);
    expect(fuenteHook).toMatch(/return \(\) => sesion\.detener\(\);/);
    expect(fuenteHook).toMatch(/fase\.contexto === contexto \? fase\.fase : REASIGNACION_INACTIVA/);
    expect(fuenteHook).toMatch(/vendedores\.contexto === contexto \? vendedores\.estado : VENDEDORES_INACTIVO/);
  });
});

// FE-2D (H-2): contexto válido → null → mismo contexto, sin desmontar. La
// sesión del mismo contexto se reutiliza (conserva una intención desconocida
// del mismo actor), pero nunca queda congelada en «enviando».
describe("FE-2D H-2: ctx → null → ctx con un envío en vuelo", () => {
  const USUARIO = "11111111-1111-4111-8111-111111111111";
  const OTRO = "55555555-5555-4555-8555-555555555555";
  const otro = Symbol("salida");

  async function enviarEnVuelo(m: ReturnType<typeof armar>) {
    m.sesion.iniciar();
    m.sesion.solicitar(jornada("abierta"));
    const p = m.sesion.controlador.confirmar({ vendedorId: NUEVO, permitidos: [NUEVO] });
    await tick();
    expect(m.fases.at(-1)?.fase).toBe("enviando");
    // Envuelta: devolverla desde una función async esperaría su resolución.
    return { p };
  }

  it("S1: el éxito llega con el contexto en null → al volver se publica, relee una vez y se puede operar de nuevo", async () => {
    const m = armar(USUARIO);
    const { p } = await enviarEnVuelo(m);
    m.sesion.detener(); // contexto → null
    m.envios[0].resolver({ ok: true, datos: OP, intentos: 1 });
    await p;
    expect(m.fases.at(-1)?.fase).toBe("enviando");
    expect(m.releer).not.toHaveBeenCalled();

    m.sesion.iniciar(); // vuelve el MISMO contexto
    expect(m.fases.at(-1)).toMatchObject({ fase: "exito" });
    expect(m.releer).toHaveBeenCalledTimes(1);
    expect(m.arbitro.retenidaPorOtra(otro, jornada().id)).toBe(false);

    // Tras la relectura, la pantalla vuelve a ofrecer el cambio.
    m.sesion.controlador.trasRelectura();
    m.sesion.solicitar(jornada("abierta", { vendedorId: NUEVO }));
    expect(m.sesion.controlador.obtener().fase).toBe("confirmando");
  });

  it("S2: sin respuesta con el contexto en null → desconocido (sin verificar ni releer); al volver, reintento con la MISMA clave", async () => {
    const m = armar(USUARIO);
    const { p } = await enviarEnVuelo(m);
    m.sesion.detener();
    expect(m.envios[0].opciones?.continuar?.()).toBe(false);
    m.envios[0].resolver({ ok: false, intentos: 1, error: { codigo: null, mensaje: "x", resultadoDesconocido: true } });
    await p;
    expect(m.lecturas).toHaveLength(0);

    m.sesion.iniciar();
    expect(m.fases.at(-1)).toMatchObject({ fase: "desconocido", reintentable: false });
    // Sigue retenida frente a salida/corrección.
    expect(m.arbitro.retenidaPorOtra(otro, jornada().id)).toBe(true);

    const v = m.sesion.controlador.verificarEstado();
    await tick();
    m.lecturas[0].resolver({ ok: true, datos: [jornada("abierta")], intentos: 1 });
    await v;
    expect(m.sesion.controlador.obtener()).toMatchObject({ fase: "desconocido", reintentable: true });
    const r = m.sesion.controlador.reintentar();
    await tick();
    expect(m.envios).toHaveLength(2);
    expect(m.envios[1].clave).toBe(m.envios[0].clave);
    expect(m.envios[1].opciones?.usuarioEsperado).toBe(USUARIO);
    m.envios[1].resolver({ ok: true, datos: OP, intentos: 1 });
    await r;
    expect(m.fases.at(-1)?.fase).toBe("exito");
  });

  it("S3: ctxA → null → ctxB → sesión nueva sin la clave de A; la respuesta tardía de A no publica ni retiene", async () => {
    const arbitro = crearArbitroJornadas();
    const a = armar(USUARIO, arbitro);
    const { p } = await enviarEnVuelo(a);
    a.sesion.detener();
    const b = armar(OTRO, arbitro);
    b.sesion.iniciar();
    expect(b.sesion.controlador.claveEnCurso()).toBeNull();
    expect(arbitro.retenidaPorOtra(otro, jornada().id)).toBe(false);

    const fasesA = a.fases.length;
    a.envios[0].resolver({ ok: false, intentos: 1, error: { codigo: null, mensaje: "x", resultadoDesconocido: true } });
    await p;
    expect(a.fases).toHaveLength(fasesA);
    expect(arbitro.retenidaPorOtra(otro, jornada().id)).toBe(false);
    // B puede operar sobre la jornada; sus envíos llevan su propio usuario.
    b.sesion.solicitar(jornada("abierta"));
    const pb = b.sesion.controlador.confirmar({ vendedorId: NUEVO, permitidos: [NUEVO] });
    await tick();
    expect(b.envios[0].opciones?.usuarioEsperado).toBe(OTRO);
    expect(b.envios[0].clave).not.toBe(a.envios[0].clave);
    b.envios[0].resolver({ ok: true, datos: OP, intentos: 1 });
    await pb;
  });

  it("S4: el usuario se toma del contexto; un contexto sin usuario válido no crea sesión", () => {
    expect(usuarioDeContexto(JSON.stringify([USUARIO, "e", "dueno"]))).toBe(USUARIO);
    expect(usuarioDeContexto(JSON.stringify(["no-uuid", "e", "dueno"]))).toBeNull();
    expect(usuarioDeContexto(JSON.stringify({ usuario: USUARIO }))).toBeNull();
    expect(usuarioDeContexto("no es json")).toBeNull();
    // Guardas estructurales del hook: falla cerrada y el usuario llega a la sesión.
    expect(fuenteHook).toMatch(/if \(usuarioId === null\) return null;/);
    expect(fuenteHook).toMatch(/DEPENDENCIAS_REALES,\s*usuarioId\s*\)/);
  });
});
