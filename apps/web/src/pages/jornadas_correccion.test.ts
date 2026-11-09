import { describe, expect, it, vi } from "vitest";

import { ROLES_GESTION } from "../auth/roles";
import {
  MENSAJE_RESULTADO_DESCONOCIDO,
  type ComandoJornada,
  type EstadoJornada,
  type Jornada,
  type ResultadoJornada,
} from "../lib/jornadas";
import { buscarConLectura } from "../hooks/useCorreccionJornada";
import {
  MENSAJE_CAMION_INVALIDO,
  MENSAJE_CORRECCION_COINCIDE,
  MENSAJE_CORRECCION_NO_VISIBLE,
  MENSAJE_CORRECCION_OK,
  MENSAJE_CORRECCION_OTRO_ESTADO,
  MENSAJE_CORRECCION_OTROS_VALORES,
  MENSAJE_CORRECCION_SIN_EFECTO,
  MENSAJE_CORRECCION_SIN_VERIFICAR,
  MENSAJE_FECHA_INVALIDA,
  MENSAJE_FECHA_PASADA,
  MENSAJE_MOTIVO_OBLIGATORIO,
  MENSAJE_SIN_CAMBIOS,
  crearControladorCorreccion,
  fechaOperativaHoy,
  validarCorreccion,
  type BuscarJornada,
  type EntradaCorreccion,
  type FaseCorreccion,
} from "./jornadas_correccion";
import { crearArbitroJornadas, jornadaRetenida, type ArbitroJornadas } from "./jornadas_operacion";
import { crearControladorSalida, type FaseSalida } from "./jornadas_salida";
import fuenteMotor from "./jornadas_operacion.ts?raw";
import fuenteControlador from "./jornadas_correccion.ts?raw";
import fuenteSalida from "./jornadas_salida.ts?raw";
import fuenteHook from "../hooks/useCorreccionJornada.ts?raw";
import fuentePanel from "./JornadaCorreccionPanel.tsx?raw";
import fuentePantalla from "./Jornadas.tsx?raw";

const OP = "99999999-9999-4999-8999-999999999999";
const CAMION_A = "22222222-2222-4222-8222-222222222222";
const CAMION_B = "44444444-4444-4444-8444-444444444444";
const HOY = "2026-11-10";

function jornada(n: number, estado: EstadoJornada = "abierta", cambios: Partial<Jornada> = {}): Jornada {
  return {
    id: `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`,
    fecha: HOY,
    camionId: CAMION_A,
    vendedorId: "33333333-3333-4333-8333-333333333333",
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
    ...cambios,
  };
}

const entrada = (cambios: Partial<EntradaCorreccion> = {}): EntradaCorreccion => ({
  fecha: "2026-11-11",
  camionId: CAMION_A,
  motivo: "Error de carga en la fecha",
  ...cambios,
});

const exito = (): ResultadoJornada<string> => ({ ok: true, datos: OP, intentos: 1 });
const rechazo = (codigo: string, mensaje = "rechazo seguro"): ResultadoJornada<string> => ({
  ok: false, intentos: 1, error: { codigo, mensaje, resultadoDesconocido: false },
});
const sinRespuesta = (): ResultadoJornada<string> => ({
  ok: false, intentos: 3, error: { codigo: null, mensaje: MENSAJE_RESULTADO_DESCONOCIDO, resultadoDesconocido: true },
});

/** Puerto de escritura y búsqueda cuyas respuestas se resuelven a mano; reloj fijo. */
function armar(arbitro?: ArbitroJornadas) {
  const envios: Array<{ comando: ComandoJornada; clave: string; resolver: (r: ResultadoJornada<string>) => void }> = [];
  const busquedas: Array<{ id: string; fechas: string[]; resolver: (j: Jornada | null | undefined) => void }> = [];
  const publicadas: FaseCorreccion[] = [];
  const releer = vi.fn();
  let n = 0;
  const claves = () => `aaaaaaaa-0000-4000-8000-${(++n).toString(16).padStart(12, "0")}`;
  const puerto = {
    ejecutar(comando: ComandoJornada, clave: string) {
      return new Promise<ResultadoJornada<string>>((resolver) => envios.push({ comando, clave, resolver }));
    },
  };
  const buscar: BuscarJornada = (id, fechas) =>
    new Promise((resolver) => busquedas.push({ id, fechas, resolver }));
  const c = crearControladorCorreccion(puerto, buscar, releer, (f) => publicadas.push(f), {
    hoy: () => HOY,
    generarClave: claves,
    arbitro,
  });
  return { c, envios, busquedas, publicadas, releer, ultima: () => c.obtener() };
}

const tick = () => new Promise((r) => setTimeout(r, 0));

describe("corregir jornada: roles", () => {
  it("dueño y encargado son roles de gestión; el vendedor/piloto no (la pantalla monta el panel sólo para gestión)", () => {
    expect(ROLES_GESTION).toEqual(expect.arrayContaining(["dueno", "encargado"]));
    expect(ROLES_GESTION).not.toContain("vendedor_piloto");
    expect(fuentePantalla).toMatch(/puedeAdministrar\s*\?\s*\(jornada\)/);
  });
});

describe("corregir jornada: estados", () => {
  it("sólo una jornada abierta abre la corrección", () => {
    const m = armar();
    m.c.solicitar(jornada(1, "abierta"));
    expect(m.ultima()).toEqual({ fase: "confirmando", jornadaId: jornada(1).id });
  });

  it.each<EstadoJornada>(["cargada", "en_reparto", "ventas_finalizadas", "regreso_contado", "cerrada"])(
    "una jornada %s no abre la corrección ni envía nada",
    async (estado) => {
      const m = armar();
      m.c.solicitar(jornada(1, estado));
      await m.c.confirmar(entrada());
      expect(m.ultima()).toEqual({ fase: "inactiva" });
      expect(m.envios).toHaveLength(0);
    }
  );

  it.each(["jornada_estado_invalido", "jornada_con_movimientos", "jornada_no_encontrada", "jornada_sin_cambios"])(
    "rechazo %s del servidor: error definitivo, sin reintento y relee",
    async (codigo) => {
      const m = armar();
      m.c.solicitar(jornada(1));
      const p = m.c.confirmar(entrada());
      m.envios[0].resolver(rechazo(codigo));
      await p;
      expect(m.ultima()).toEqual({ fase: "error", jornadaId: jornada(1).id, mensaje: "rechazo seguro" });
      expect(m.c.claveEnCurso()).toBeNull();
      expect(m.releer).toHaveBeenCalledTimes(1);
    }
  );

  it.each(["jornada_duplicada", "jornada_camion_con_jornada_abierta", "jornada_vendedor_ocupado", "jornada_camion_inactivo", "jornada_fecha_invalida", "jornada_no_autorizado"])(
    "rechazo %s: error definitivo con el mensaje seguro, sin releer y la intención termina",
    async (codigo) => {
      const m = armar();
      m.c.solicitar(jornada(1));
      const p = m.c.confirmar(entrada());
      m.envios[0].resolver(rechazo(codigo, "Mensaje seguro"));
      await p;
      expect(m.ultima()).toMatchObject({ fase: "error", mensaje: "Mensaje seguro" });
      expect(m.releer).not.toHaveBeenCalled();
      expect(m.c.claveEnCurso()).toBeNull();
    }
  );
});

describe("corregir jornada: validaciones locales (no se envía nada)", () => {
  const j = jornada(1);

  it("el motivo es obligatorio (sólo espacios no alcanza) y se envía recortado", async () => {
    expect(validarCorreccion(j, entrada({ motivo: "   " }), HOY)).toBe(MENSAJE_MOTIVO_OBLIGATORIO);
    const m = armar();
    m.c.solicitar(j);
    await m.c.confirmar(entrada({ motivo: "  \t " }));
    expect(m.ultima()).toEqual({ fase: "confirmando", jornadaId: j.id, error: MENSAJE_MOTIVO_OBLIGATORIO });
    expect(m.envios).toHaveLength(0);
    void m.c.confirmar(entrada({ motivo: "  Camión en taller  " }));
    expect(m.envios[0].comando).toEqual({
      tipo: "corregir", jornadaId: j.id, fecha: "2026-11-11", camionId: CAMION_A, motivo: "Camión en taller",
    });
  });

  it("fecha inválida o anterior al día operativo actual", () => {
    expect(validarCorreccion(j, entrada({ fecha: "" }), HOY)).toBe(MENSAJE_FECHA_INVALIDA);
    expect(validarCorreccion(j, entrada({ fecha: "2026-02-30" }), HOY)).toBe(MENSAJE_FECHA_INVALIDA);
    expect(validarCorreccion(j, entrada({ fecha: "2026-11-09" }), HOY)).toBe(MENSAJE_FECHA_PASADA);
    expect(validarCorreccion(j, entrada({ fecha: HOY, camionId: CAMION_B }), HOY)).toBeNull();
  });

  it("camión inválido", () => {
    expect(validarCorreccion(j, entrada({ camionId: "" }), HOY)).toBe(MENSAJE_CAMION_INVALIDO);
    expect(validarCorreccion(j, entrada({ camionId: "no-es-uuid" }), HOY)).toBe(MENSAJE_CAMION_INVALIDO);
  });

  it("sin cambios: la misma fecha y el mismo camión no se envían", () => {
    expect(validarCorreccion(j, entrada({ fecha: HOY, camionId: CAMION_A }), HOY)).toBe(MENSAJE_SIN_CAMBIOS);
  });

  it("corrección de fecha, de camión o de ambos es válida", () => {
    expect(validarCorreccion(j, entrada({ fecha: "2026-11-12" }), HOY)).toBeNull();
    expect(validarCorreccion(j, entrada({ fecha: HOY, camionId: CAMION_B }), HOY)).toBeNull();
    expect(validarCorreccion(j, entrada({ fecha: "2026-11-12", camionId: CAMION_B }), HOY)).toBeNull();
  });

  it("tras un error de validación se puede corregir la entrada y enviar", async () => {
    const m = armar();
    m.c.solicitar(j);
    await m.c.confirmar(entrada({ fecha: "2026-11-01" }));
    expect(m.ultima()).toMatchObject({ fase: "confirmando", error: MENSAJE_FECHA_PASADA });
    void m.c.confirmar(entrada());
    expect(m.ultima()).toEqual({ fase: "enviando", jornadaId: j.id });
    expect(m.envios).toHaveLength(1);
  });
});

describe("día operativo en Tucumán (reloj fijo)", () => {
  it("usa America/Argentina/Tucuman (UTC−3), no la hora UTC ni la del navegador", () => {
    expect(fechaOperativaHoy(new Date("2026-11-10T02:59:00Z"))).toBe("2026-11-09");
    expect(fechaOperativaHoy(new Date("2026-11-10T03:00:00Z"))).toBe("2026-11-10");
    expect(fechaOperativaHoy(new Date("2026-12-31T23:30:00Z"))).toBe("2026-12-31");
    expect(fechaOperativaHoy(new Date("2027-01-01T03:30:00Z"))).toBe("2027-01-01");
  });
});

describe("corregir jornada: flujo normal y relectura", () => {
  it("envía UNA vez el comando `corregir`, anuncia el éxito y relee", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada({ camionId: CAMION_B }));
    expect(m.ultima()).toEqual({ fase: "enviando", jornadaId: jornada(1).id });
    m.envios[0].resolver(exito());
    await p;
    expect(m.envios).toHaveLength(1);
    expect(m.envios[0].comando).toMatchObject({ tipo: "corregir", camionId: CAMION_B });
    expect(m.ultima()).toEqual({ fase: "exito", jornadaId: jornada(1).id, mensaje: MENSAJE_CORRECCION_OK });
    expect(m.releer).toHaveBeenCalledTimes(1);
    expect(m.c.claveEnCurso()).toBeNull();
  });

  it("cancelar cierra el formulario sin enviar", () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    m.c.cancelar();
    expect(m.ultima()).toEqual({ fase: "inactiva" });
    expect(m.envios).toHaveLength(0);
  });
});

describe("corregir jornada: doble clic y envío único", () => {
  it("un segundo confirmar o solicitar durante el envío se ignora", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada());
    void m.c.confirmar(entrada());
    m.c.solicitar(jornada(2));
    void m.c.confirmar(entrada());
    expect(m.envios).toHaveLength(1);
    m.envios[0].resolver(exito());
    await p;
    expect(m.envios).toHaveLength(1);
  });
});

describe("corregir jornada: respuesta perdida, verificación e idempotencia", () => {
  it("sin efecto: verifica en la fecha original y la nueva; ofrece reintentar con la MISMA clave y el MISMO comando", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada({ motivo: " Fecha mal cargada " }));
    const clave = m.c.claveEnCurso();
    m.envios[0].resolver(sinRespuesta());
    await tick();
    expect(m.ultima()).toEqual({ fase: "verificando", jornadaId: jornada(1).id });
    expect(m.busquedas[0]).toMatchObject({ id: jornada(1).id, fechas: [HOY, "2026-11-11"] });
    m.busquedas[0].resolver(jornada(1)); // sigue con los valores originales
    await p;
    expect(m.ultima()).toEqual({
      fase: "desconocido", jornadaId: jornada(1).id, mensaje: MENSAJE_CORRECCION_SIN_EFECTO, reintentable: true,
    });
    expect(m.envios).toHaveLength(1); // no reenvía por su cuenta
    expect(m.releer).not.toHaveBeenCalled();

    const r = m.c.reintentar();
    expect(m.envios).toHaveLength(2);
    expect(m.envios[1].clave).toBe(clave);
    expect(m.envios[1].comando).toEqual(m.envios[0].comando);
    m.envios[1].resolver(exito());
    await r;
    expect(m.ultima()).toMatchObject({ fase: "exito", mensaje: MENSAJE_CORRECCION_OK });
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  it("M-01: la jornada ya tiene los valores pedidos → NO es éxito: incierta, reintentable, conserva clave y datos, sin releer", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada({ fecha: "2026-11-12", camionId: CAMION_B, motivo: "  Fecha y camión  " }));
    const clave = m.c.claveEnCurso();
    const datos = m.c.datosEnCurso();
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.busquedas[0].resolver(jornada(1, "abierta", { fecha: "2026-11-12", camionId: CAMION_B }));
    await p;
    expect(m.ultima()).toEqual({
      fase: "desconocido", jornadaId: jornada(1).id, mensaje: MENSAJE_CORRECCION_COINCIDE, reintentable: true,
    });
    expect(m.publicadas.some((f) => f.fase === "exito")).toBe(false);
    expect(m.envios).toHaveLength(1);
    expect(m.releer).not.toHaveBeenCalled();
    expect(m.c.claveEnCurso()).toBe(clave);
    expect(m.c.datosEnCurso()).toEqual(datos);
    expect(m.c.datosEnCurso()).toMatchObject({ motivo: "Fecha y camión" });
  });

  it("si sólo cambia el camión, se busca sólo en la fecha de la jornada", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    void m.c.confirmar(entrada({ fecha: HOY, camionId: CAMION_B }));
    m.envios[0].resolver(sinRespuesta());
    await tick();
    expect(m.busquedas[0].fechas).toEqual([HOY]);
  });

  it("la lectura falla: no ofrece reintentar hasta poder verificar; «Verificar estado» vuelve a leer", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada());
    const clave = m.c.claveEnCurso();
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.busquedas[0].resolver(undefined);
    await p;
    expect(m.ultima()).toEqual({
      fase: "desconocido", jornadaId: jornada(1).id, mensaje: MENSAJE_CORRECCION_SIN_VERIFICAR, reintentable: false,
    });
    await m.c.reintentar();
    expect(m.envios).toHaveLength(1);
    const v = m.c.verificarEstado();
    m.busquedas[1].resolver(jornada(1));
    await v;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true });
    expect(m.c.claveEnCurso()).toBe(clave);
  });

  it.each<[string, Jornada | null, string, boolean]>([
    ["no visible", null, MENSAJE_CORRECCION_NO_VISIBLE, false],
    ["abierta con otros valores", jornada(1, "abierta", { fecha: "2026-11-20" }), MENSAJE_CORRECCION_OTROS_VALORES, false],
    ["en otro estado con los valores originales", jornada(1, "cargada"), MENSAJE_CORRECCION_OTRO_ESTADO, true],
    ["en otro estado con otros valores", jornada(1, "cargada", { fecha: "2026-11-20" }), MENSAJE_CORRECCION_OTRO_ESTADO, true],
  ])("M-01: la jornada %s → incierta (reintento seguro según el caso), la clave NO se descarta y no relee", async (_n, encontrada, mensaje, reintentable) => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada());
    const clave = m.c.claveEnCurso();
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.busquedas[0].resolver(encontrada);
    await p;
    expect(m.ultima()).toEqual({ fase: "desconocido", jornadaId: jornada(1).id, mensaje, reintentable });
    expect(m.c.claveEnCurso()).toBe(clave);
    expect(m.releer).not.toHaveBeenCalled();
    void m.c.reintentar();
    expect(m.envios).toHaveLength(reintentable ? 2 : 1);
    if (reintentable) expect(m.envios[1].clave).toBe(clave);
  });

  it("concurrencia agotada (40001): también verifica antes de ofrecer el reintento", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada());
    m.envios[0].resolver({ ok: false, intentos: 3, error: { codigo: "40001", mensaje: "x", resultadoDesconocido: false } });
    await tick();
    expect(m.ultima()).toMatchObject({ fase: "verificando" });
    m.busquedas[0].resolver(jornada(1));
    await p;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true });
  });

  it("una intención nueva (después de terminar la anterior) usa otra clave", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p1 = m.c.confirmar(entrada());
    m.envios[0].resolver(rechazo("jornada_duplicada"));
    await p1;
    m.c.solicitar(jornada(1));
    void m.c.confirmar(entrada({ fecha: "2026-11-13" }));
    expect(m.envios[1].clave).not.toBe(m.envios[0].clave);
  });
});

describe("corregir jornada: cambio de jornada con una intención incierta", () => {
  it.each([true, false])(
    "con resultado desconocido (reintentable=%s) no se abre otra corrección y la clave se conserva",
    async (reintentable) => {
      const m = armar();
      m.c.solicitar(jornada(1));
      const p = m.c.confirmar(entrada());
      const clave = m.c.claveEnCurso();
      m.envios[0].resolver(sinRespuesta());
      await tick();
      m.busquedas[0].resolver(reintentable ? jornada(1) : undefined);
      await p;
      m.c.solicitar(jornada(2));
      void m.c.confirmar(entrada());
      expect(m.ultima()).toMatchObject({ fase: "desconocido", jornadaId: jornada(1).id });
      expect(m.envios).toHaveLength(1);
      expect(m.c.claveEnCurso()).toBe(clave);
    }
  );
});

describe("corregir jornada: respuestas tardías y desmontaje", () => {
  it("tras detener, una respuesta tardía no publica ni relee", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada());
    const antes = m.publicadas.length;
    m.c.detener();
    m.envios[0].resolver(exito());
    await p;
    expect(m.publicadas).toHaveLength(antes);
    expect(m.releer).not.toHaveBeenCalled();
  });

  it("tras detener durante la verificación, no publica ni relee ni reenvía", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada());
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.c.detener();
    const antes = m.publicadas.length;
    m.busquedas[0].resolver(jornada(1, "abierta", { fecha: "2026-11-11" }));
    await p;
    expect(m.publicadas).toHaveLength(antes);
    expect(m.releer).not.toHaveBeenCalled();
    expect(m.envios).toHaveLength(1);
  });
});

describe("M-01: respuesta perdida sin falso éxito", () => {
  async function perdidaConValoresPedidos(m: ReturnType<typeof armar>) {
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada({ fecha: "2026-11-12", camionId: CAMION_B }));
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.busquedas[0].resolver(jornada(1, "abierta", { fecha: "2026-11-12", camionId: CAMION_B }));
    await p;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true, mensaje: MENSAJE_CORRECCION_COINCIDE });
  }

  it("otro actor alcanzó los valores pedidos: el reintento (misma clave) es rechazado sin cambios y NUNCA se anuncia éxito", async () => {
    const m = armar();
    await perdidaConValoresPedidos(m);
    const r = m.c.reintentar();
    expect(m.envios[1].clave).toBe(m.envios[0].clave);
    expect(m.envios[1].comando).toEqual(m.envios[0].comando);
    m.envios[1].resolver(rechazo("jornada_sin_cambios", "No hay cambios para registrar."));
    await r;
    expect(m.ultima()).toEqual({ fase: "error", jornadaId: jornada(1).id, mensaje: "No hay cambios para registrar." });
    expect(m.publicadas.some((f) => f.fase === "exito")).toBe(false);
    expect(m.c.claveEnCurso()).toBeNull();
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  it("si ESTA corrección se había registrado, el reintento recibe la operación original: recién entonces es éxito", async () => {
    const m = armar();
    await perdidaConValoresPedidos(m);
    const r = m.c.reintentar();
    m.envios[1].resolver(exito());
    await r;
    expect(m.ultima()).toEqual({ fase: "exito", jornadaId: jornada(1).id, mensaje: MENSAJE_CORRECCION_OK });
    expect(m.envios).toHaveLength(2);
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  it("la primera operación todavía está en curso: la jornada sigue igual, el reintento reutiliza clave y comando, y no se reenvía dos veces", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada());
    // El cliente agotó sus intentos sin respuesta; la base todavía no confirmó.
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.busquedas[0].resolver(jornada(1)); // aún sin efecto visible
    await p;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true, mensaje: MENSAJE_CORRECCION_SIN_EFECTO });
    const r = m.c.reintentar();
    void m.c.reintentar(); // doble clic durante el envío
    expect(m.envios).toHaveLength(2);
    expect(m.envios[1].clave).toBe(m.envios[0].clave);
    expect(m.envios[1].comando).toEqual(m.envios[0].comando);
    // El servidor espera la reserva en curso y devuelve la operación original.
    m.envios[1].resolver(exito());
    await r;
    expect(m.publicadas.filter((f) => f.fase === "exito")).toHaveLength(1);
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  it("el reintento no altera fecha, camión ni motivo aunque la jornada cambie y se intente otra entrada", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada({ fecha: "2026-11-12", camionId: CAMION_B, motivo: "  Motivo original  " }));
    const clave = m.c.claveEnCurso();
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.busquedas[0].resolver(jornada(1, "cargada"));
    await p;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true, mensaje: MENSAJE_CORRECCION_OTRO_ESTADO });
    // Otra solicitud u otra entrada no reemplazan la intención incierta.
    m.c.solicitar(jornada(1, "abierta", { fecha: "2026-11-15" }));
    await m.c.confirmar(entrada({ fecha: "2026-11-20", motivo: "otro motivo" }));
    expect(m.envios).toHaveLength(1);
    const esperado = {
      tipo: "corregir", jornadaId: jornada(1).id, fecha: "2026-11-12", camionId: CAMION_B, motivo: "Motivo original",
    };
    expect(m.envios[0].comando).toEqual(esperado);
    const r1 = m.c.reintentar();
    m.envios[1].resolver(sinRespuesta());
    await tick();
    m.busquedas[1].resolver(jornada(1, "cargada"));
    await r1;
    const r2 = m.c.reintentar();
    expect(m.envios.map((e) => e.clave)).toEqual([clave, clave, clave]);
    expect(m.envios.map((e) => e.comando)).toEqual([esperado, esperado, esperado]);
    m.envios[2].resolver(rechazo("jornada_estado_invalido"));
    await r2;
    expect(m.ultima()).toMatchObject({ fase: "error" });
  });
});

/** Controlador de salida real con puerto y verificación resueltos a mano. */
function armarSalida(arbitro: ArbitroJornadas) {
  const envios: Array<{ comando: ComandoJornada; clave: string; resolver: (r: ResultadoJornada<string>) => void }> = [];
  const verificaciones: Array<{ id: string; resolver: (e: EstadoJornada | null | undefined) => void }> = [];
  const publicadas: FaseSalida[] = [];
  const releer = vi.fn();
  let n = 0;
  const claves = () => `bbbbbbbb-0000-4000-8000-${(++n).toString(16).padStart(12, "0")}`;
  const s = crearControladorSalida(
    { ejecutar: (comando, clave) => new Promise((resolver) => envios.push({ comando, clave, resolver })) },
    ({ id }) => new Promise((resolver) => verificaciones.push({ id, resolver })),
    releer,
    (f) => publicadas.push(f),
    claves,
    arbitro
  );
  return { s, envios, verificaciones, publicadas, releer };
}

describe("M-02: arbitraje salida/corrección sobre la misma jornada", () => {
  it.each<[string, () => ResultadoJornada<string>, "error" | "exito"]>([
    ["rechazo definitivo", () => rechazo("jornada_estado_invalido"), "error"],
    ["operación original (replay)", exito, "exito"],
  ])(
    "corrección incierta → relectura con la jornada cargada → salida bloqueada → se resuelve por %s y la salida se recupera",
    async (_n, respuesta, final) => {
      const arbitro = crearArbitroJornadas();
      const m = armar(arbitro);
      const sal = armarSalida(arbitro);
      m.c.solicitar(jornada(1));
      const p = m.c.confirmar(entrada());
      const clave = m.c.claveEnCurso();
      m.envios[0].resolver(sinRespuesta());
      await tick();
      m.busquedas[0].resolver(jornada(1));
      await p;
      expect(m.ultima()).toMatchObject({ fase: "desconocido", jornadaId: jornada(1).id });

      // La lista se relee y la jornada aparece cargada: la salida la admitiría,
      // pero la corrección incierta la retiene.
      const cargada = jornada(1, "cargada");
      sal.s.solicitar(cargada);
      await sal.s.confirmar();
      expect(sal.s.obtener()).toEqual({ fase: "inactiva" });
      expect(sal.envios).toHaveLength(0);
      expect(m.c.claveEnCurso()).toBe(clave);

      // «Verificar estado»: ya no está abierta → reintento seguro, sigue retenida.
      const v = m.c.verificarEstado();
      m.busquedas[1].resolver(cargada);
      await v;
      expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true, mensaje: MENSAJE_CORRECCION_OTRO_ESTADO });
      sal.s.solicitar(cargada);
      expect(sal.s.obtener()).toEqual({ fase: "inactiva" });

      // Reintento con la misma clave: el servidor resuelve y libera la jornada.
      const r = m.c.reintentar();
      expect(m.envios[1].clave).toBe(clave);
      sal.s.solicitar(cargada); // durante el envío, también bloqueada
      expect(sal.s.obtener()).toEqual({ fase: "inactiva" });
      m.envios[1].resolver(respuesta());
      await r;
      expect(m.ultima()).toMatchObject({ fase: final });
      expect(m.c.claveEnCurso()).toBeNull();

      sal.s.solicitar(cargada);
      expect(sal.s.obtener()).toEqual({ fase: "confirmando", jornadaId: cargada.id });
      void sal.s.confirmar();
      expect(sal.envios).toHaveLength(1);
      expect(sal.envios[0].comando).toEqual({ tipo: "salir", jornadaId: cargada.id });
    }
  );

  it("la corrección retiene la jornada al confirmar, enviar y verificar; otra jornada no se bloquea; cancelar libera", async () => {
    const arbitro = crearArbitroJornadas();
    const m = armar(arbitro);
    const sal = armarSalida(arbitro);
    const cargada = jornada(1, "cargada");

    m.c.solicitar(jornada(1));
    expect(jornadaRetenida(m.ultima())).toBe(jornada(1).id);
    sal.s.solicitar(cargada);
    expect(sal.s.obtener()).toEqual({ fase: "inactiva" });
    m.c.cancelar();
    sal.s.solicitar(cargada);
    expect(sal.s.obtener()).toMatchObject({ fase: "confirmando" });
    sal.s.cancelar();

    m.c.solicitar(jornada(1));
    await m.c.confirmar(entrada({ motivo: " " })); // error de validación: sigue confirmando
    sal.s.solicitar(cargada);
    expect(sal.s.obtener()).toEqual({ fase: "inactiva" });

    const p = m.c.confirmar(entrada());
    sal.s.solicitar(cargada);
    expect(sal.s.obtener()).toEqual({ fase: "inactiva" });
    sal.s.solicitar(jornada(2, "cargada")); // otra jornada: libre
    expect(sal.s.obtener()).toEqual({ fase: "confirmando", jornadaId: jornada(2).id });
    sal.s.cancelar();

    m.envios[0].resolver(sinRespuesta());
    await tick();
    expect(m.ultima()).toMatchObject({ fase: "verificando" });
    sal.s.solicitar(cargada);
    expect(sal.s.obtener()).toEqual({ fase: "inactiva" });
    m.busquedas[0].resolver(undefined);
    await p;
    sal.s.solicitar(cargada);
    expect(sal.s.obtener()).toEqual({ fase: "inactiva" });

    // Desmontar no libera una intención incierta.
    m.c.detener();
    sal.s.solicitar(cargada);
    expect(sal.s.obtener()).toEqual({ fase: "inactiva" });
  });

  it("escenario inverso: una salida incierta bloquea la corrección de la misma jornada hasta resolverse", async () => {
    const arbitro = crearArbitroJornadas();
    const m = armar(arbitro);
    const sal = armarSalida(arbitro);
    const cargada = jornada(1, "cargada");

    sal.s.solicitar(cargada);
    m.c.solicitar(jornada(1)); // salida confirmando: corrección bloqueada
    expect(m.ultima()).toEqual({ fase: "inactiva" });

    const p = sal.s.confirmar();
    const claveSalida = sal.s.claveEnCurso();
    sal.envios[0].resolver(sinRespuesta());
    await tick();
    sal.verificaciones[0].resolver("cargada");
    await p;
    expect(sal.s.obtener()).toMatchObject({ fase: "desconocido", reintentable: true });

    // Aunque una relectura la mostrara abierta, la corrección no puede iniciarse.
    m.c.solicitar(jornada(1, "abierta"));
    await m.c.confirmar(entrada());
    expect(m.ultima()).toEqual({ fase: "inactiva" });
    expect(m.envios).toHaveLength(0);

    const r = sal.s.reintentar();
    expect(sal.envios[1].clave).toBe(claveSalida);
    sal.envios[1].resolver(rechazo("jornada_estado_invalido"));
    await r;
    expect(sal.s.obtener()).toMatchObject({ fase: "error" });

    m.c.solicitar(jornada(1, "abierta"));
    expect(m.ultima()).toEqual({ fase: "confirmando", jornadaId: jornada(1).id });
    void m.c.confirmar(entrada());
    expect(m.envios).toHaveLength(1);
  });
});

describe("M-03: nueva corrección tras un éxito y su relectura", () => {
  it("dos correcciones consecutivas de la misma jornada: claves distintas, la primera no se reutiliza ni se altera", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p1 = m.c.confirmar(entrada({ fecha: "2026-11-11" }));
    m.envios[0].resolver(exito());
    await p1;
    expect(m.ultima()).toEqual({ fase: "exito", jornadaId: jornada(1).id, mensaje: MENSAJE_CORRECCION_OK });
    expect(m.releer).toHaveBeenCalledTimes(1);

    m.c.trasRelectura(); // la lectura completó
    expect(m.ultima()).toEqual({ fase: "exito", jornadaId: jornada(1).id, mensaje: MENSAJE_CORRECCION_OK, releida: true });

    const releida = jornada(1, "abierta", { fecha: "2026-11-11" });
    m.c.solicitar(releida);
    expect(m.ultima()).toEqual({ fase: "confirmando", jornadaId: jornada(1).id });
    const p2 = m.c.confirmar(entrada({ fecha: "2026-11-11", camionId: CAMION_B, motivo: "Segundo ajuste" }));
    expect(m.envios).toHaveLength(2);
    expect(m.envios[1].clave).not.toBe(m.envios[0].clave);
    expect(m.c.datosEnCurso()).toMatchObject({ original: { fecha: "2026-11-11", camionId: CAMION_A } });
    expect(m.envios[0].comando).toEqual({
      tipo: "corregir", jornadaId: jornada(1).id, fecha: "2026-11-11", camionId: CAMION_A, motivo: "Error de carga en la fecha",
    });
    expect(m.envios[1].comando).toEqual({
      tipo: "corregir", jornadaId: jornada(1).id, fecha: "2026-11-11", camionId: CAMION_B, motivo: "Segundo ajuste",
    });
    m.envios[1].resolver(exito());
    await p2;
    expect(m.ultima()).toEqual({ fase: "exito", jornadaId: jornada(1).id, mensaje: MENSAJE_CORRECCION_OK });
    expect(m.releer).toHaveBeenCalledTimes(2);
  });

  it("trasRelectura no reinicia ni resuelve una intención incierta, y no relee", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada());
    const clave = m.c.claveEnCurso();
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.busquedas[0].resolver(jornada(1));
    await p;
    const antes = m.ultima();
    const publicadas = m.publicadas.length;
    m.c.trasRelectura();
    expect(m.ultima()).toBe(antes);
    expect(m.publicadas).toHaveLength(publicadas);
    expect(m.c.claveEnCurso()).toBe(clave);
    expect(m.envios).toHaveLength(1);
    expect(m.releer).not.toHaveBeenCalled();
  });

  it("trasRelectura publica una sola vez, no relee (sin bucle) y no afecta otras fases", async () => {
    const m = armar();
    m.c.trasRelectura();
    expect(m.publicadas).toHaveLength(0);
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar(entrada());
    m.envios[0].resolver(exito());
    await p;
    const publicadas = m.publicadas.length;
    m.c.trasRelectura();
    m.c.trasRelectura();
    expect(m.publicadas).toHaveLength(publicadas + 1);
    expect(m.releer).toHaveBeenCalledTimes(1);
  });
});

describe("búsqueda con la lectura de B-02a", () => {
  const leer = (porFecha: Record<string, Jornada[] | "falla">) => ({
    leerTodasLasJornadas: vi.fn(async ({ fecha }: { fecha?: string }) => {
      const r = porFecha[fecha ?? ""];
      return r === "falla" || r === undefined
        ? { ok: false as const, intentos: 1, error: { codigo: null, mensaje: "x", resultadoDesconocido: false } }
        : { ok: true as const, intentos: 1, datos: r };
    }),
  });

  it("busca en la fecha original y, si no está, en la nueva", async () => {
    const movida = jornada(1, "abierta", { fecha: "2026-11-11" });
    const p = leer({ [HOY]: [jornada(2)], "2026-11-11": [movida] });
    expect(await buscarConLectura(p)(jornada(1).id, [HOY, "2026-11-11"])).toEqual(movida);
    expect(p.leerTodasLasJornadas).toHaveBeenCalledTimes(2);
  });

  it("no visible en ninguna → null; una lectura fallida → undefined", async () => {
    expect(await buscarConLectura(leer({ [HOY]: [], "2026-11-11": [] }))(jornada(1).id, [HOY, "2026-11-11"])).toBeNull();
    expect(await buscarConLectura(leer({ [HOY]: "falla" }))(jornada(1).id, [HOY, "2026-11-11"])).toBeUndefined();
  });
});

describe("superficie de las operaciones", () => {
  const sinComentarios = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
  const FUENTES: Array<[string, string]> = [
    ["jornadas_operacion.ts", fuenteMotor],
    ["jornadas_correccion.ts", fuenteControlador],
    ["useCorreccionJornada.ts", fuenteHook],
    ["JornadaCorreccionPanel.tsx", fuentePanel],
  ];

  it.each(FUENTES)("%s: sin localStorage, sessionStorage ni IndexedDB", (_n, fuente) => {
    expect(/localStorage|sessionStorage|indexedDB/i.test(sinComentarios(fuente))).toBe(false);
  });

  it.each(FUENTES)("%s: sin RPC directas ni escrituras de tablas", (_n, fuente) => {
    expect(/\.rpc\(|\.from\(|\.(insert|update|upsert|delete)\(/.test(sinComentarios(fuente))).toBe(false);
  });

  it("el motor no conoce ningún comando; la corrección sólo `corregir`; la salida sólo `salir`", () => {
    const tipos = (s: string) => [...sinComentarios(s).matchAll(/tipo:\s*"([a-z]+)"/g)].map((m) => m[1]);
    expect(tipos(fuenteMotor)).toEqual([]);
    expect(tipos(fuenteControlador)).toEqual(["corregir"]);
    expect(tipos(fuenteSalida)).toEqual(["salir"]);
    expect(sinComentarios(fuenteHook)).not.toMatch(/ejecutar\(/);
    expect(sinComentarios(fuentePanel)).not.toMatch(/ejecutar/);
  });

  it("la pantalla conecta ambas operaciones con el `recargar` estable de la lectura y el MISMO árbitro", () => {
    expect(sinComentarios(fuentePantalla)).toMatch(/const \[arbitro\] = useState\(crearArbitroJornadas\)/);
    expect(sinComentarios(fuentePantalla)).toMatch(/useCorreccionJornada\(jornadas\.recargar, arbitro\)/);
    expect(sinComentarios(fuentePantalla)).toMatch(/useSalidaJornada\(jornadas\.recargar, arbitro\)/);
    expect(sinComentarios(fuenteHook)).toMatch(/const \[controlador\] = useState\(\(\) =>/);
  });
});
