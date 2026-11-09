import { describe, expect, it, vi } from "vitest";

import { ROLES_GESTION } from "../auth/roles";
import {
  MENSAJE_RESULTADO_DESCONOCIDO,
  type ComandoJornada,
  type EstadoJornada,
  type Jornada,
  type ResultadoJornada,
} from "../lib/jornadas";
import { verificarConLectura } from "../hooks/useSalidaJornada";
import {
  MENSAJE_SALIDA_NO_VISIBLE,
  MENSAJE_SALIDA_OK,
  MENSAJE_SALIDA_SIGUE_CARGADA,
  MENSAJE_SALIDA_SIN_VERIFICAR,
  MENSAJE_SALIDA_YA_REGISTRADA,
  crearControladorSalida,
  type FaseSalida,
  type VerificarJornada,
} from "./jornadas_salida";
import { crearControladorJornadas, type PuertoLecturaJornadas } from "./jornadas_lectura";
import fuenteControlador from "./jornadas_salida.ts?raw";
import fuenteHook from "../hooks/useSalidaJornada.ts?raw";
import fuenteHookLectura from "../hooks/useJornadasLectura.ts?raw";
import fuentePantalla from "./Jornadas.tsx?raw";
import fuentePanel from "./JornadaSalidaPanel.tsx?raw";
import fuenteAviso from "./AvisoSalidaJornada.tsx?raw";

const OP = "99999999-9999-4999-8999-999999999999";

function jornada(n: number, estado: EstadoJornada = "cargada"): Jornada {
  return {
    id: `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`,
    fecha: "2026-11-10",
    camionId: "22222222-2222-4222-8222-222222222222",
    vendedorId: "33333333-3333-4333-8333-333333333333",
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
  };
}

const exito = (): ResultadoJornada<string> => ({ ok: true, datos: OP, intentos: 1 });
const rechazo = (codigo: string, mensaje = "rechazo seguro"): ResultadoJornada<string> => ({
  ok: false, intentos: 1, error: { codigo, mensaje, resultadoDesconocido: false },
});
const sinRespuesta = (): ResultadoJornada<string> => ({
  ok: false, intentos: 3, error: { codigo: null, mensaje: MENSAJE_RESULTADO_DESCONOCIDO, resultadoDesconocido: true },
});

/** Puerto de escritura y verificación cuyas respuestas se resuelven a mano. */
function armar() {
  const envios: Array<{ comando: ComandoJornada; clave: string; resolver: (r: ResultadoJornada<string>) => void }> = [];
  const verificaciones: Array<{ jornada: { id: string; fecha: string }; resolver: (e: EstadoJornada | null | undefined) => void }> = [];
  const publicadas: FaseSalida[] = [];
  const releer = vi.fn();
  let n = 0;
  const claves = () => `aaaaaaaa-0000-4000-8000-${(++n).toString(16).padStart(12, "0")}`;
  const puerto = {
    ejecutar(comando: ComandoJornada, clave: string) {
      return new Promise<ResultadoJornada<string>>((resolver) => envios.push({ comando, clave, resolver }));
    },
  };
  const verificar: VerificarJornada = (j) =>
    new Promise((resolver) => verificaciones.push({ jornada: j, resolver }));
  const c = crearControladorSalida(puerto, verificar, releer, (f) => publicadas.push(f), claves);
  return { c, envios, verificaciones, publicadas, releer, ultima: () => c.obtener() };
}

const tick = () => new Promise((r) => setTimeout(r, 0));

describe("confirmar salida: roles", () => {
  it("dueño y encargado son roles de gestión; el vendedor/piloto no", () => {
    // La pantalla monta el control sólo con ROLES_GESTION (Jornadas.tsx);
    // el servidor vuelve a decidir (PT403 para cualquier otro rol).
    expect(ROLES_GESTION).toContain("dueno");
    expect(ROLES_GESTION).toContain("encargado");
    expect(ROLES_GESTION).not.toContain("vendedor_piloto");
  });
});

describe("confirmar salida: flujo normal", () => {
  it("pide confirmación, envía UNA vez con el comando `salir` y relee tras el éxito", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    expect(m.ultima()).toEqual({ fase: "confirmando", jornadaId: jornada(1).id });
    expect(m.envios).toHaveLength(0); // solicitar no envía nada

    const p = m.c.confirmar();
    expect(m.ultima()).toEqual({ fase: "enviando", jornadaId: jornada(1).id });
    expect(m.envios).toHaveLength(1);
    expect(m.envios[0].comando).toEqual({ tipo: "salir", jornadaId: jornada(1).id });
    m.envios[0].resolver(exito());
    await p;

    expect(m.ultima()).toEqual({ fase: "exito", jornadaId: jornada(1).id, mensaje: MENSAJE_SALIDA_OK });
    expect(m.releer).toHaveBeenCalledTimes(1);
    expect(m.verificaciones).toHaveLength(0);
    expect(m.c.claveEnCurso()).toBeNull(); // la intención terminó
  });

  it("cancelar cierra la confirmación sin enviar", () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    m.c.cancelar();
    expect(m.ultima()).toEqual({ fase: "inactiva" });
    expect(m.envios).toHaveLength(0);
  });
});

describe("confirmar salida: estado inválido", () => {
  it.each<EstadoJornada>(["abierta", "en_reparto", "ventas_finalizadas", "regreso_contado", "cerrada"])(
    "una jornada %s no abre la confirmación ni envía",
    async (estado) => {
      const m = armar();
      m.c.solicitar(jornada(1, estado));
      await m.c.confirmar();
      expect(m.ultima()).toEqual({ fase: "inactiva" });
      expect(m.envios).toHaveLength(0);
    }
  );

  it("si el servidor responde jornada_estado_invalido: error definitivo, sin reintento y relee", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    m.envios[0].resolver(rechazo("jornada_estado_invalido", "La jornada cambió"));
    await p;
    expect(m.ultima()).toEqual({ fase: "error", jornadaId: jornada(1).id, mensaje: "La jornada cambió" });
    expect(m.releer).toHaveBeenCalledTimes(1);
    expect(m.c.claveEnCurso()).toBeNull();
    await m.c.reintentar(); // no aplica a un rechazo definitivo
    expect(m.envios).toHaveLength(1);
  });
});

describe("confirmar salida: doble clic y envío único", () => {
  it("un segundo confirmar o solicitar durante el envío se ignora", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p1 = m.c.confirmar();
    const p2 = m.c.confirmar(); // doble clic
    m.c.solicitar(jornada(2)); // otra acción durante el envío
    await m.c.reintentar();
    await m.c.verificarEstado();
    expect(m.envios).toHaveLength(1);
    m.envios[0].resolver(exito());
    await Promise.all([p1, p2]);
    expect(m.envios).toHaveLength(1);
    expect(m.ultima().fase).toBe("exito");
  });
});

describe("confirmar salida: respuesta perdida y reintento con la misma clave", () => {
  it("sin respuesta: NO reenvía; consulta el estado real y, si sigue cargada, ofrece reintentar con la MISMA clave", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    const clave = m.envios[0].clave;
    m.envios[0].resolver(sinRespuesta());
    await tick();
    expect(m.ultima()).toEqual({ fase: "verificando", jornadaId: jornada(1).id });
    expect(m.envios).toHaveLength(1); // ningún reenvío automático
    expect(m.verificaciones[0].jornada).toEqual({ id: jornada(1).id, fecha: "2026-11-10" });
    m.verificaciones[0].resolver("cargada");
    await p;
    expect(m.ultima()).toEqual({
      fase: "desconocido", jornadaId: jornada(1).id, mensaje: MENSAJE_SALIDA_SIGUE_CARGADA, reintentable: true,
    });
    expect(m.c.claveEnCurso()).toBe(clave);

    const r = m.c.reintentar();
    expect(m.envios).toHaveLength(2);
    expect(m.envios[1].clave).toBe(clave); // misma intención, misma clave
    expect(m.envios[1].comando).toEqual(m.envios[0].comando);
    m.envios[1].resolver(exito());
    await r;
    expect(m.ultima().fase).toBe("exito");
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  it("sin respuesta pero la jornada ya salió: se informa como registrada, sin reenviar", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.verificaciones[0].resolver("en_reparto");
    await p;
    expect(m.ultima()).toEqual({ fase: "exito", jornadaId: jornada(1).id, mensaje: MENSAJE_SALIDA_YA_REGISTRADA });
    expect(m.envios).toHaveLength(1);
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  it("si la verificación falla: no ofrece reintentar hasta poder leer el estado", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.verificaciones[0].resolver(undefined);
    await p;
    expect(m.ultima()).toEqual({
      fase: "desconocido", jornadaId: jornada(1).id, mensaje: MENSAJE_SALIDA_SIN_VERIFICAR, reintentable: false,
    });
    await m.c.reintentar(); // bloqueado: sin estado verificado
    expect(m.envios).toHaveLength(1);

    const v = m.c.verificarEstado();
    m.verificaciones[1].resolver("cargada");
    await v;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true });
  });

  it("si la jornada ya no es visible: error, sin reintento, y relee", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.verificaciones[0].resolver(null);
    await p;
    expect(m.ultima()).toEqual({ fase: "error", jornadaId: jornada(1).id, mensaje: MENSAJE_SALIDA_NO_VISIBLE });
    expect(m.c.claveEnCurso()).toBeNull();
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  it("concurrencia agotada (40001): también verifica antes de ofrecer el reintento", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    m.envios[0].resolver(rechazo("40001", "Otra operación estaba en curso"));
    await tick();
    expect(m.ultima().fase).toBe("verificando");
    m.verificaciones[0].resolver("cargada");
    await p;
    expect(m.ultima()).toMatchObject({ fase: "desconocido", reintentable: true });
  });
});

describe("confirmar salida: error definitivo", () => {
  it("carga neta cero: muestra el mensaje seguro, termina la intención y una nueva intención usa otra clave", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    const primera = m.envios[0].clave;
    m.envios[0].resolver(rechazo("jornada_carga_neta_cero", "El camión no tiene carga neta"));
    await p;
    expect(m.ultima()).toEqual({ fase: "error", jornadaId: jornada(1).id, mensaje: "El camión no tiene carga neta" });
    expect(m.releer).not.toHaveBeenCalled();
    expect(m.verificaciones).toHaveLength(0);

    m.c.solicitar(jornada(1));
    const q = m.c.confirmar();
    expect(m.envios[1].clave).not.toBe(primera);
    m.envios[1].resolver(exito());
    await q;
  });

  it("sin permiso (42501) es definitivo y no se reintenta", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    m.envios[0].resolver(rechazo("42501", "No tenés permiso"));
    await p;
    expect(m.ultima()).toMatchObject({ fase: "error", mensaje: "No tenés permiso" });
    await m.c.reintentar();
    expect(m.envios).toHaveLength(1);
  });
});

describe("confirmar salida: respuesta tardía y desmontaje", () => {
  it("tras detener, una respuesta tardía no publica ni relee", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    const antes = m.publicadas.length;
    m.c.detener();
    m.envios[0].resolver(exito());
    await p;
    expect(m.publicadas.length).toBe(antes);
    expect(m.releer).not.toHaveBeenCalled();
  });

  it("tras detener durante la verificación, no publica ni relee", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    m.envios[0].resolver(sinRespuesta());
    await tick();
    const antes = m.publicadas.length;
    m.c.detener();
    m.verificaciones[0].resolver("en_reparto");
    await p;
    expect(m.publicadas.length).toBe(antes);
    expect(m.releer).not.toHaveBeenCalled();
  });
});

describe("estabilidad de `releer` (capturado una sola vez por el hook)", () => {
  // useSalidaJornada toma `releer` al crear el controlador. En la pantalla es
  // `useJornadasLectura().recargar`, que delega en un controlador de lectura
  // creado una vez (useState). Estos casos usan el controlador de lectura
  // REAL para demostrar que la función capturada al principio relee con el
  // estado vigente, no con uno viejo.
  function lecturaReal() {
    const pedidas: Array<{ fecha?: string } | undefined> = [];
    const puerto: PuertoLecturaJornadas = {
      async leerPaginaJornadas(opciones) {
        pedidas.push(opciones?.fecha === undefined ? undefined : { fecha: opciones.fecha });
        return { ok: true, intentos: 1, datos: { jornadas: [], siguiente: null } };
      },
      async leerTodasLasJornadas() {
        return { ok: true, intentos: 1, datos: [] };
      },
    };
    const lectura = crearControladorJornadas(puerto, () => undefined);
    return { lectura, pedidas };
  }

  it("tras cambiar la fecha, el `releer` capturado al inicio relee con la fecha VIGENTE", async () => {
    const { lectura, pedidas } = lecturaReal();
    await lectura.iniciar();
    const releerCapturado = () => void lectura.recargar(); // lo que captura el hook en el primer render
    let n = 0;
    const s = crearControladorSalida(
      { ejecutar: async () => exito() },
      async () => "cargada",
      releerCapturado,
      () => undefined,
      () => `bbbbbbbb-0000-4000-8000-${(++n).toString(16).padStart(12, "0")}`
    );
    await lectura.cambiarFecha("2026-12-24"); // cambio posterior a la captura
    const antes = pedidas.length; // cambiarFecha ya leyó: no cuenta como relectura
    s.solicitar(jornada(1));
    await s.confirmar();
    await tick();
    // Exactamente UNA lectura nueva, provocada por el éxito, con la fecha vigente.
    expect(pedidas.slice(antes)).toEqual([{ fecha: "2026-12-24" }]);
  });

  it("detener + iniciar (StrictMode o remontaje del efecto) deja el controlador operativo", async () => {
    const m = armar();
    m.c.detener();
    m.c.iniciar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    m.envios[0].resolver(exito());
    await p;
    expect(m.ultima().fase).toBe("exito");
    expect(m.publicadas.at(-1)?.fase).toBe("exito");
    expect(m.releer).toHaveBeenCalledTimes(1);
  });

  // Regresión S1-C2 (Codex, revisión 1): navegar a otra jornada NO puede
  // descartar una intención con resultado desconocido ni su clave.
  it.each([true, false])(
    "con un resultado desconocido (reintentable=%s), solicitar otra jornada se ignora y la clave se conserva",
    async (reintentable) => {
      const m = armar();
      m.c.solicitar(jornada(1));
      const p = m.c.confirmar();
      const claveA = m.envios[0].clave;
      m.envios[0].resolver(sinRespuesta());
      await tick();
      m.verificaciones[0].resolver(reintentable ? "cargada" : undefined);
      await p;

      m.c.solicitar(jornada(2));
      m.c.solicitar(jornada(1));
      void m.c.confirmar(); // sin await: si enviara algo, la aserción falla en el acto
      expect(m.ultima()).toMatchObject({ fase: "desconocido", jornadaId: jornada(1).id, reintentable });
      expect(m.c.claveEnCurso()).toBe(claveA);
      expect(m.envios).toHaveLength(1);
    }
  );

  it("resuelta la intención desconocida, recién entonces otra jornada usa una clave nueva", async () => {
    const m = armar();
    m.c.solicitar(jornada(1));
    const p = m.c.confirmar();
    const claveA = m.envios[0].clave;
    m.envios[0].resolver(sinRespuesta());
    await tick();
    m.verificaciones[0].resolver("cargada");
    await p;
    const r = m.c.reintentar();
    expect(m.envios[1].clave).toBe(claveA);
    m.envios[1].resolver(exito());
    await r;

    m.c.solicitar(jornada(2));
    const q = m.c.confirmar();
    expect(m.envios[2].comando).toEqual({ tipo: "salir", jornadaId: jornada(2).id });
    expect(m.envios[2].clave).not.toBe(claveA);
    m.envios[2].resolver(exito());
    await q;
  });

  it("evidencia estructural: `recargar` delega en un controlador de lectura creado una vez y la pantalla lo pasa tal cual", () => {
    const sin = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
    const hookLectura = sin(fuenteHookLectura);
    expect(hookLectura).toMatch(/const \[controlador\] = useState\(\(\) =>\s*crearControladorJornadas\(/);
    expect(hookLectura).toMatch(/recargar: \(\) => void controlador\.recargar\(\)/);
    // Desde S2 (M-02) también recibe el árbitro compartido de la pantalla.
    expect(sin(fuentePantalla)).toMatch(/useSalidaJornada\(jornadas\.recargar, arbitro\)/);
    // El hook de salida no guarda claves ni estado fuera del controlador.
    expect(sin(fuenteHook)).toMatch(/const \[controlador\] = useState\(\(\) =>/);
  });
});

describe("verificación con la lectura de B-02a", () => {
  const leer = (r: ResultadoJornada<Jornada[]>) => {
    const leerTodasLasJornadas = vi.fn(async () => r);
    return { verificar: verificarConLectura({ leerTodasLasJornadas }), leerTodasLasJornadas };
  };

  it("lee todas las jornadas de la fecha y devuelve el estado real", async () => {
    const { verificar, leerTodasLasJornadas } = leer({ ok: true, datos: [jornada(2, "abierta"), jornada(1, "en_reparto")], intentos: 1 });
    expect(await verificar({ id: jornada(1).id, fecha: "2026-11-10" })).toBe("en_reparto");
    expect(leerTodasLasJornadas).toHaveBeenCalledWith({ fecha: "2026-11-10" });
  });

  it("no visible → null; lectura fallida → undefined", async () => {
    expect(await leer({ ok: true, datos: [], intentos: 1 }).verificar({ id: jornada(1).id, fecha: "2026-11-10" })).toBeNull();
    const error = { ok: false as const, intentos: 1, error: { codigo: null, mensaje: "x", resultadoDesconocido: false } };
    expect(await leer(error).verificar({ id: jornada(1).id, fecha: "2026-11-10" })).toBeUndefined();
  });
});

describe("superficie de la operación de salida", () => {
  const sinComentarios = (s: string) =>
    s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/([^:])\/\/.*$/gm, "$1");
  const FUENTES: Array<[string, string]> = [
    ["jornadas_salida.ts", fuenteControlador],
    ["useSalidaJornada.ts", fuenteHook],
    ["JornadaSalidaPanel.tsx", fuentePanel],
    ["AvisoSalidaJornada.tsx", fuenteAviso],
  ];

  it.each(FUENTES)("%s: sin localStorage, sessionStorage ni IndexedDB", (_n, fuente) => {
    expect(/localStorage|sessionStorage|indexedDB/i.test(sinComentarios(fuente))).toBe(false);
  });

  it.each(FUENTES)("%s: sin RPC directas ni escrituras de tablas", (_n, fuente) => {
    expect(/\.rpc\(|\.from\(|\.(insert|update|upsert|delete)\(/.test(sinComentarios(fuente))).toBe(false);
  });

  it("el único comando que se ejecuta es `salir` (ninguna otra operación habilitada)", () => {
    const codigo = sinComentarios(fuenteControlador);
    const tipos = [...codigo.matchAll(/tipo:\s*"([a-z]+)"/g)].map((m) => m[1]);
    expect(tipos).toEqual(["salir"]);
    expect(sinComentarios(fuenteHook)).not.toMatch(/ejecutar\(/);
    expect(sinComentarios(fuentePanel)).not.toMatch(/ejecutar/);
    expect(sinComentarios(fuenteAviso)).not.toMatch(/ejecutar/);
  });
});
