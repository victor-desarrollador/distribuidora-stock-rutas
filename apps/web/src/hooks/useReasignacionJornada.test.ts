import { describe, expect, it, vi } from "vitest";

import type { ComandoJornada, EstadoJornada, Jornada, ResultadoJornada } from "../lib/jornadas";
import type { ResultadoVendedores } from "../lib/vendedores_jornada";
import type { EstadoVendedores } from "../pages/jornadas_apertura";
import { crearArbitroJornadas } from "../pages/jornadas_operacion";
import type { FaseReasignacion } from "../pages/jornadas_reasignacion";
import { crearSesionReasignacion, type DependenciasReasignacion } from "./useReasignacionJornada";
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

function armar() {
  const envios: Array<{ comando: ComandoJornada; clave: string; resolver: (r: ResultadoJornada<string>) => void }> = [];
  const lecturas: Array<{ fecha?: string; resolver: (r: ResultadoJornada<Jornada[]>) => void }> = [];
  const listados: Array<(r: ResultadoVendedores) => void> = [];
  const puertoJornadas = vi.fn(() => ({
    ejecutar: (comando: ComandoJornada, clave: string) =>
      new Promise<ResultadoJornada<string>>((resolver) => envios.push({ comando, clave, resolver })),
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
  const arbitro = crearArbitroJornadas();
  const sesion = crearSesionReasignacion(releer, arbitro, (f) => fases.push(f), (e) => vendedores.push(e), deps);
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
