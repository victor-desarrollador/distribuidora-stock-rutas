import { describe, expect, it } from "vitest";

import type { DatosStock, IntentoStock, PuertoStock, ResultadoStock } from "../lib/stock";
import {
  MENSAJE_SIN_CLAVE,
  crearControladorStock,
  type EstadoLecturaStock,
} from "./stock_controlador";

const datos = (cantidad: number): DatosStock => ({
  depositoId: "dep",
  cuarentenaId: "cua",
  ubicaciones: [
    { id: "dep", tipo: "deposito", camionId: null },
    { id: "cua", tipo: "cuarentena", camionId: null },
  ],
  productos: [{ id: "p", codigo: null, nombre: "Yogur", formaVenta: "unidad", stockMinimo: 0, activo: true }],
  camiones: [],
  saldos: [{ ubicacionId: "dep", productoId: "p", cantidad }],
});

const intento: IntentoStock = { tipo: "ingreso", productoId: "p", cantidad: 5, motivo: null };

function escenario(opciones: {
  lecturas?: ResultadoStock<DatosStock>[];
  ejecuciones?: (() => Promise<ResultadoStock<string>>)[];
  claves?: (string | null)[];
}) {
  const publicados: EstadoLecturaStock[] = [];
  const clavesEnviadas: string[] = [];
  let lectura = 0;
  let ejecucion = 0;
  let clave = 0;
  const lecturas = opciones.lecturas ?? [{ ok: true, datos: datos(0) }];

  const puerto: PuertoStock = {
    async leer() {
      return lecturas[Math.min(lectura++, lecturas.length - 1)];
    },
    async ejecutar(_i, k) {
      clavesEnviadas.push(k);
      const f = opciones.ejecuciones?.[ejecucion++];
      return f ? f() : { ok: true, datos: "op" };
    },
  };
  const claves = opciones.claves;
  const controlador = crearControladorStock(
    puerto,
    (e) => publicados.push(e),
    () => (claves ? claves[clave++] ?? null : `k${++clave}`)
  );
  return { controlador, publicados, clavesEnviadas };
}

describe("controlador de stock", () => {
  it("lee y publica el stock", async () => {
    const { controlador, publicados } = escenario({});
    await controlador.leer();
    expect(publicados).toEqual([{ estado: "listo", datos: datos(0) }]);
  });

  it("un error de lectura se publica sin datos viejos", async () => {
    const { controlador, publicados } = escenario({
      lecturas: [{ ok: true, datos: datos(1) }, { ok: false, error: "No se pudo leer el stock. Intentá de nuevo." }],
    });
    await controlador.leer();
    await controlador.recargar();
    expect(publicados.at(-1)).toEqual({ estado: "error", error: "No se pudo leer el stock. Intentá de nuevo." });
  });

  it("después de un éxito vuelve a leer: el saldo sale de la base", async () => {
    const { controlador, publicados } = escenario({
      lecturas: [{ ok: true, datos: datos(0) }, { ok: true, datos: datos(5) }],
    });
    await controlador.leer();
    const r = await controlador.ejecutar(intento);
    expect(r).toEqual({ ok: true, datos: "op" });
    expect(publicados.map((p) => p.estado)).toEqual(["listo", "cargando", "listo"]);
    expect(publicados.at(-1)).toEqual({ estado: "listo", datos: datos(5) });
  });

  it("un error de la RPC no recarga ni toca el saldo", async () => {
    const { controlador, publicados } = escenario({
      ejecuciones: [async () => ({ ok: false, error: "No hay stock suficiente en el depósito." })],
    });
    await controlador.leer();
    const r = await controlador.ejecutar(intento);
    expect(r).toEqual({ ok: false, error: "No hay stock suficiente en el depósito." });
    expect(publicados).toHaveLength(1);
  });

  it("doble envío: la segunda llamada simultánea no ejecuta la RPC", async () => {
    let liberar!: () => void;
    const { controlador, clavesEnviadas } = escenario({
      ejecuciones: [() => new Promise((res) => { liberar = () => res({ ok: true, datos: "op" }); })],
    });
    const primera = controlador.ejecutar(intento);
    expect(controlador.ocupado).toBe(true);
    const segunda = await controlador.ejecutar(intento);
    expect(segunda).toEqual({ ok: false, enCurso: true });
    liberar();
    await primera;
    expect(clavesEnviadas).toHaveLength(1);
    expect(controlador.ocupado).toBe(false);
  });

  it("reintento tras un error reutiliza la clave; tras un éxito, usa otra", async () => {
    const { controlador, clavesEnviadas } = escenario({
      ejecuciones: [
        async () => ({ ok: false, error: "No se pudo confirmar la operación." }),
        async () => ({ ok: true, datos: "op" }),
        async () => ({ ok: true, datos: "op" }),
      ],
    });
    await controlador.ejecutar(intento);
    await controlador.ejecutar(intento);
    await controlador.ejecutar(intento);
    expect(clavesEnviadas[0]).toBe(clavesEnviadas[1]);
    expect(clavesEnviadas[2]).not.toBe(clavesEnviadas[1]);
  });

  it("un intento con otros datos no reutiliza la clave", async () => {
    const { controlador, clavesEnviadas } = escenario({
      ejecuciones: [async () => ({ ok: false, error: "x" }), async () => ({ ok: false, error: "x" })],
    });
    await controlador.ejecutar(intento);
    await controlador.ejecutar({ ...intento, cantidad: 6 });
    expect(clavesEnviadas[0]).not.toBe(clavesEnviadas[1]);
  });

  it("sin clave del navegador no envía nada", async () => {
    const { controlador, clavesEnviadas } = escenario({ claves: [null] });
    const r = await controlador.ejecutar(intento);
    expect(r).toEqual({ ok: false, error: MENSAJE_SIN_CLAVE });
    expect(clavesEnviadas).toHaveLength(0);
    expect(controlador.ocupado).toBe(false);
  });

  it("al desmontar, una lectura pendiente no publica", async () => {
    const { controlador, publicados } = escenario({});
    const pendiente = controlador.leer();
    controlador.detener();
    await pendiente;
    expect(publicados).toEqual([]);
  });

  it("sólo la última lectura publica", async () => {
    const respuestas: ((r: ResultadoStock<DatosStock>) => void)[] = [];
    const publicados: EstadoLecturaStock[] = [];
    const puerto: PuertoStock = {
      leer: () => new Promise((res) => respuestas.push(res)),
      ejecutar: async () => ({ ok: true, datos: "op" }),
    };
    const c = crearControladorStock(puerto, (e) => publicados.push(e), () => "k");
    const a = c.leer();
    const b = c.leer();
    respuestas[1]({ ok: true, datos: datos(2) });
    respuestas[0]({ ok: true, datos: datos(1) });
    await Promise.all([a, b]);
    expect(publicados).toEqual([{ estado: "listo", datos: datos(2) }]);
  });
});
