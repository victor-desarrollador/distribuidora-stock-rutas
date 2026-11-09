import { describe, expect, it, vi } from "vitest";

import {
  MENSAJE_SIN_PERMISO,
  clasificarErrorJornada,
  llamadaRpcJornada,
  type ComandoJornada,
  type EstadoJornada,
  type Jornada,
  type ResultadoJornada,
} from "../lib/jornadas";
import {
  MENSAJE_CARGA_CANTIDAD_PESO,
  MENSAJE_CARGA_CANTIDAD_UNIDAD,
  MENSAJE_CARGA_INCIERTA,
  MENSAJE_CARGA_NO_VISIBLE,
  MENSAJE_CARGA_OK,
  MENSAJE_CARGA_PRODUCTO_DESCONOCIDO,
  MENSAJE_CARGA_PRODUCTO_INACTIVO,
  MENSAJE_CARGA_PRODUCTO_REPETIDO,
  MENSAJE_CARGA_SIN_CAMION,
  MENSAJE_CARGA_SIN_EFECTO,
  MENSAJE_CARGA_SIN_LINEAS,
  MENSAJE_CARGA_SIN_PRODUCTO,
  MENSAJE_CARGA_SIN_VERIFICAR,
  crearControladorCarga,
  jornadasCargables,
  resumenCarga,
  validarCarga,
  type EntradaCarga,
  type FaseCarga,
  type ProductoCarga,
} from "./jornadas_carga";
import { crearArbitroJornadas } from "./jornadas_operacion";
import { crearControladorSalida } from "./jornadas_salida";
import fuenteCarga from "./jornadas_carga.ts?raw";
import fuentePantalla from "./Jornadas.tsx?raw";

const OP = "99999999-9999-4999-8999-999999999999";
const CAMION = "22222222-2222-4222-8222-222222222222";
const LECHE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const JAMON = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const VIEJO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

const CATALOGO: ProductoCarga[] = [
  { id: LECHE, codigo: "L1", nombre: "Leche entera", formaVenta: "unidad", activo: true },
  { id: JAMON, codigo: null, nombre: "Jamón cocido", formaVenta: "peso", activo: true },
  { id: VIEJO, codigo: null, nombre: "Queso discontinuado", formaVenta: "unidad", activo: false },
];

function jornada(n: number, estado: EstadoJornada = "abierta", cambios: Partial<Jornada> = {}): Jornada {
  return {
    id: `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`,
    fecha: "2026-11-10",
    camionId: CAMION,
    vendedorId: "33333333-3333-4333-8333-333333333333",
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
    ...cambios,
  };
}

const entrada = (...lineas: Array<[string, string]>): EntradaCarga => ({
  lineas: lineas.map(([productoId, texto]) => ({ productoId, texto })),
});
const valida = () => entrada([LECHE, "24"], [JAMON, "3,250"]);

const exito = (): ResultadoJornada<string> => ({ ok: true, datos: OP, intentos: 1 });
/** Rechazo tal como lo clasifica la capa real a partir del error de PostgREST. */
const rechazoServidor = (message: string, code = "PT409"): ResultadoJornada<string> => {
  const c = clasificarErrorJornada({ code, message });
  return { ok: false, intentos: 1, error: { codigo: c.codigo, mensaje: c.mensaje, resultadoDesconocido: false } };
};
const sinRespuesta = (): ResultadoJornada<string> => {
  const c = clasificarErrorJornada({ code: "", message: "Failed to fetch" });
  return { ok: false, intentos: 3, error: { codigo: c.codigo, mensaje: c.mensaje, resultadoDesconocido: true } };
};

/** Puerto de escritura y verificación resueltos a mano. */
function armar(opciones: { arbitro?: ReturnType<typeof crearArbitroJornadas>; prefijo?: string } = {}) {
  const envios: Array<{ comando: ComandoJornada; clave: string; resolver: (r: ResultadoJornada<string>) => void }> = [];
  const lecturas: Array<{ id: string; fecha: string; resolver: (e: EstadoJornada | null | undefined) => void }> = [];
  const publicadas: FaseCarga[] = [];
  const releer = vi.fn();
  let n = 0;
  const ctrl = crearControladorCarga(
    {
      ejecutar: (comando, clave) =>
        new Promise((resolver) => envios.push({ comando, clave, resolver })),
    },
    () => CATALOGO,
    (j) => new Promise((resolver) => lecturas.push({ ...j, resolver })),
    releer,
    (f) => publicadas.push(f),
    { generarClave: () => `${opciones.prefijo ?? "clave"}-${++n}`, arbitro: opciones.arbitro }
  );
  return { ctrl, envios, lecturas, publicadas, releer };
}

const tick = () => new Promise((r) => setTimeout(r, 0));

describe("validarCarga: cantidades en unidad mínima, sin float", () => {
  it("convierte unidades enteras y kg con coma a gramos enteros", () => {
    const v = validarCarga(valida(), CATALOGO);
    expect(v).toEqual({
      ok: true,
      lineas: [
        { productoId: LECHE, cantidad: 24 },
        { productoId: JAMON, cantidad: 3250 },
      ],
    });
  });

  it.each(["0", "-1", "1,5", "1.5", "abc", "", " ", "2147483648", "1e3", "0x10", "+5", "12 un"])(
    "rechaza la cantidad de unidad %j",
    (texto) => {
      expect(validarCarga(entrada([LECHE, texto]), CATALOGO)).toEqual({
        ok: false,
        mensaje: MENSAJE_CARGA_CANTIDAD_UNIDAD(1),
      });
    }
  );

  it.each(["0", "0,000", "1,2345", "-1", "1.250", "abc", "", "2147484"])(
    "rechaza el peso %j",
    (texto) => {
      expect(validarCarga(entrada([LECHE, "1"], [JAMON, texto]), CATALOGO)).toEqual({
        ok: false,
        mensaje: MENSAJE_CARGA_CANTIDAD_PESO(2),
      });
    }
  );

  it("acepta el máximo de int4 y 1 gramo", () => {
    expect(validarCarga(entrada([LECHE, "2147483647"], [JAMON, "0,001"]), CATALOGO).ok).toBe(true);
  });
});

describe("validarCarga: productos", () => {
  it("exige al menos una línea", () => {
    expect(validarCarga(entrada(), CATALOGO)).toEqual({ ok: false, mensaje: MENSAJE_CARGA_SIN_LINEAS });
  });

  it("exige elegir producto en cada línea", () => {
    expect(validarCarga(entrada([LECHE, "1"], ["", "2"]), CATALOGO)).toEqual({
      ok: false,
      mensaje: MENSAJE_CARGA_SIN_PRODUCTO(2),
    });
  });

  it("rechaza productos repetidos, aunque cambie la capitalización del uuid", () => {
    expect(validarCarga(entrada([LECHE, "1"], [LECHE.toUpperCase(), "2"]), CATALOGO)).toEqual({
      ok: false,
      mensaje: MENSAJE_CARGA_PRODUCTO_REPETIDO(2),
    });
  });

  it("rechaza productos fuera del catálogo y dados de baja", () => {
    const ajeno = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
    expect(validarCarga(entrada([ajeno, "1"]), CATALOGO)).toEqual({
      ok: false,
      mensaje: MENSAJE_CARGA_PRODUCTO_DESCONOCIDO(1),
    });
    expect(validarCarga(entrada(["no-es-uuid", "1"]), CATALOGO)).toEqual({
      ok: false,
      mensaje: MENSAJE_CARGA_PRODUCTO_DESCONOCIDO(1),
    });
    expect(validarCarga(entrada([VIEJO, "1"]), CATALOGO)).toEqual({
      ok: false,
      mensaje: MENSAJE_CARGA_PRODUCTO_INACTIVO(1),
    });
  });
});

describe("resumen y jornadas cargables", () => {
  it("resume en unidades y kg con 3 decimales", () => {
    const v = validarCarga(valida(), CATALOGO);
    if (!v.ok) throw new Error("debía ser válida");
    expect(resumenCarga(v.lineas, CATALOGO)).toEqual([
      { productoId: LECHE, producto: "Leche entera (L1)", cantidad: "24 un." },
      { productoId: JAMON, producto: "Jamón cocido", cantidad: "3,250 kg" },
    ]);
  });

  it("sólo ofrece jornadas abiertas o cargadas (las que admite registrar_carga)", () => {
    const js = [jornada(1, "abierta"), jornada(2, "cargada"), jornada(3, "en_reparto"), jornada(4, "cerrada")];
    expect(jornadasCargables(js).map((j) => j.estado)).toEqual(["abierta", "cargada"]);
  });
});

describe("controlador: falta de jornada o camión", () => {
  it("no abre la confirmación para una jornada no cargable", () => {
    const { ctrl, envios } = armar();
    ctrl.solicitar(jornada(1, "en_reparto"));
    expect(ctrl.obtener()).toEqual({ fase: "inactiva" });
    void ctrl.confirmar(valida());
    expect(envios).toHaveLength(0);
  });

  it("confirmar sin jornada elegida no envía nada", async () => {
    const { ctrl, envios } = armar();
    await ctrl.confirmar(valida());
    expect(envios).toHaveLength(0);
  });

  it("una jornada sin camión válido no se envía", async () => {
    const { ctrl, envios } = armar();
    ctrl.solicitar(jornada(1, "abierta", { camionId: "" }));
    await ctrl.confirmar(valida());
    expect(envios).toHaveLength(0);
    expect(ctrl.obtener()).toMatchObject({ fase: "confirmando", error: MENSAJE_CARGA_SIN_CAMION });
  });

  it("un error de validación no genera clave y deja corregir", async () => {
    const { ctrl, envios } = armar();
    ctrl.solicitar(jornada(1));
    await ctrl.confirmar(entrada([LECHE, "0"]));
    expect(ctrl.claveEnCurso()).toBeNull();
    expect(envios).toHaveLength(0);
    void ctrl.confirmar(valida());
    expect(envios).toHaveLength(1);
    expect(envios[0].clave).toBe("clave-1");
  });
});

describe("controlador: envío", () => {
  it("envía registrar_carga con el payload exacto y éxito sólo con la respuesta del servidor", async () => {
    const { ctrl, envios, releer } = armar();
    const j = jornada(1);
    ctrl.solicitar(j);
    const p = ctrl.confirmar(valida());
    expect(llamadaRpcJornada(envios[0].comando, envios[0].clave)).toEqual({
      nombre: "registrar_carga",
      argumentos: {
        p_idempotency_key: "clave-1",
        p_jornada_id: j.id,
        p_productos: [LECHE, JAMON],
        p_cantidades: [24, 3250],
      },
    });
    envios[0].resolver(exito());
    await p;
    expect(ctrl.obtener()).toEqual({ fase: "exito", jornadaId: j.id, mensaje: MENSAJE_CARGA_OK });
    expect(releer).toHaveBeenCalledTimes(1);
    expect(ctrl.claveEnCurso()).toBeNull();
  });

  it("doble clic: el segundo confirmar y un reintento durante el envío se ignoran", async () => {
    const { ctrl, envios } = armar();
    ctrl.solicitar(jornada(1));
    const p1 = ctrl.confirmar(valida());
    const p2 = ctrl.confirmar(valida());
    void ctrl.reintentar();
    ctrl.solicitar(jornada(1));
    expect(envios).toHaveLength(1);
    envios[0].resolver(exito());
    await Promise.all([p1, p2]);
    expect(envios).toHaveLength(1);
  });

  it("los datos de la intención quedan congelados", () => {
    const { ctrl } = armar();
    ctrl.solicitar(jornada(1));
    const e = valida();
    void ctrl.confirmar(e);
    e.lineas[0].texto = "999";
    const datos = ctrl.datosEnCurso();
    expect(datos?.lineas[0].cantidad).toBe(24);
    expect(Object.isFrozen(datos)).toBe(true);
    expect(Object.isFrozen(datos?.lineas)).toBe(true);
  });
});

describe("controlador: rechazos del servidor", () => {
  it("permisos insuficientes: muestra el mensaje real, descarta la clave y no reintenta", async () => {
    const { ctrl, envios, releer } = armar();
    ctrl.solicitar(jornada(1));
    const p = ctrl.confirmar(valida());
    envios[0].resolver(rechazoServidor("jornada_no_autorizado", "PT403"));
    await p;
    expect(ctrl.obtener()).toMatchObject({ fase: "error", mensaje: MENSAJE_SIN_PERMISO });
    expect(ctrl.claveEnCurso()).toBeNull();
    expect(releer).not.toHaveBeenCalled();
    await ctrl.reintentar();
    expect(envios).toHaveLength(1);
  });

  it("42501 de PostgREST también es falta de permiso", async () => {
    const { ctrl, envios } = armar();
    ctrl.solicitar(jornada(1));
    const p = ctrl.confirmar(valida());
    envios[0].resolver(rechazoServidor("permission denied", "42501"));
    await p;
    expect(ctrl.obtener()).toMatchObject({ fase: "error", mensaje: MENSAJE_SIN_PERMISO });
  });

  it("sesión expirada (PT401): error definitivo con el mensaje de sesión, sin reintento", async () => {
    const { ctrl, envios } = armar();
    ctrl.solicitar(jornada(1));
    const p = ctrl.confirmar(valida());
    envios[0].resolver(rechazoServidor("jornada_no_autenticado", "PT401"));
    await p;
    expect(ctrl.obtener()).toMatchObject({
      fase: "error",
      mensaje: "Tu sesión no es válida. Volvé a iniciar sesión.",
    });
    expect(ctrl.claveEnCurso()).toBeNull();
  });

  it.each([
    ["jornada_stock_insuficiente", "No hay stock suficiente.", false],
    ["jornada_stock_residual", "El camión tiene stock que no corresponde a la jornada.", false],
    ["jornada_producto_inactivo", "El producto está dado de baja.", false],
    ["jornada_estado_invalido", undefined, true],
    ["jornada_camion_inactivo", "El camión está dado de baja.", true],
    ["jornada_no_encontrada", "La jornada no existe o no pertenece a tu empresa.", true],
  ])("rechazo %s: error definitivo; relee la lista: %s", async (codigo, mensaje, relee) => {
    const { ctrl, envios, releer } = armar();
    ctrl.solicitar(jornada(1));
    const p = ctrl.confirmar(valida());
    envios[0].resolver(rechazoServidor(codigo));
    await p;
    const fase = ctrl.obtener();
    expect(fase.fase).toBe("error");
    if (mensaje !== undefined) expect(fase).toMatchObject({ mensaje });
    expect(releer).toHaveBeenCalledTimes(relee ? 1 : 0);
  });

  it("tras un rechazo definitivo, una nueva confirmación lleva OTRA clave (E3)", async () => {
    const { ctrl, envios } = armar();
    ctrl.solicitar(jornada(1));
    const p = ctrl.confirmar(valida());
    envios[0].resolver(rechazoServidor("jornada_stock_insuficiente"));
    await p;
    ctrl.solicitar(jornada(1));
    void ctrl.confirmar(entrada([LECHE, "10"]));
    expect(envios.map((e) => e.clave)).toEqual(["clave-1", "clave-2"]);
  });
});

describe("controlador: resultado incierto y reintento (M-01)", () => {
  async function perdida(estadoInicial: EstadoJornada = "abierta") {
    const a = armar();
    const j = jornada(1, estadoInicial);
    a.ctrl.solicitar(j);
    const p = a.ctrl.confirmar(valida());
    a.envios[0].resolver(sinRespuesta());
    await tick();
    expect(a.ctrl.obtener()).toEqual({ fase: "verificando", jornadaId: j.id });
    expect(a.lecturas).toEqual([expect.objectContaining({ id: j.id, fecha: j.fecha })]);
    return { ...a, j, p };
  }

  it("sigue abierta: sin efecto todavía, reintentable con la MISMA clave y el MISMO payload", async () => {
    const { ctrl, envios, lecturas, p } = await perdida("abierta");
    lecturas[0].resolver("abierta");
    await p;
    expect(ctrl.obtener()).toMatchObject({ fase: "desconocido", mensaje: MENSAJE_CARGA_SIN_EFECTO, reintentable: true });
    const r = ctrl.reintentar();
    expect(envios).toHaveLength(2);
    expect(envios[1].clave).toBe(envios[0].clave);
    expect(llamadaRpcJornada(envios[1].comando, envios[1].clave)).toEqual(
      llamadaRpcJornada(envios[0].comando, envios[0].clave)
    );
    envios[1].resolver(exito());
    await r;
    expect(ctrl.obtener()).toMatchObject({ fase: "exito", mensaje: MENSAJE_CARGA_OK });
  });

  it("ver `cargada` tras la respuesta perdida NO declara éxito", async () => {
    const { ctrl, lecturas, releer, p } = await perdida("abierta");
    lecturas[0].resolver("cargada");
    await p;
    expect(ctrl.obtener()).toMatchObject({ fase: "desconocido", mensaje: MENSAJE_CARGA_INCIERTA, reintentable: true });
    expect(ctrl.claveEnCurso()).toBe("clave-1");
    expect(releer).not.toHaveBeenCalled();
  });

  it("carga incremental sobre `cargada`: siempre incierta, nunca éxito", async () => {
    const { ctrl, lecturas, p } = await perdida("cargada");
    lecturas[0].resolver("cargada");
    await p;
    expect(ctrl.obtener()).toMatchObject({ fase: "desconocido", reintentable: true });
  });

  it("jornada no visible: incierta, reintentable (el replay precede a la búsqueda)", async () => {
    const { ctrl, lecturas, p } = await perdida();
    lecturas[0].resolver(null);
    await p;
    expect(ctrl.obtener()).toMatchObject({ fase: "desconocido", mensaje: MENSAJE_CARGA_NO_VISIBLE, reintentable: true });
  });

  it("lectura fallida: sin reintento hasta verificar; la verificación posterior lo habilita", async () => {
    const { ctrl, envios, lecturas, p } = await perdida();
    lecturas[0].resolver(undefined);
    await p;
    expect(ctrl.obtener()).toMatchObject({ fase: "desconocido", mensaje: MENSAJE_CARGA_SIN_VERIFICAR, reintentable: false });
    await ctrl.reintentar();
    expect(envios).toHaveLength(1);
    const v = ctrl.verificarEstado();
    lecturas[1].resolver("abierta");
    await v;
    expect(ctrl.obtener()).toMatchObject({ reintentable: true });
    expect(ctrl.claveEnCurso()).toBe("clave-1");
  });

  it("con resultado desconocido no se inicia otra carga ni se cancela la intención", async () => {
    const { ctrl, envios, lecturas, j, p } = await perdida();
    lecturas[0].resolver("cargada");
    await p;
    ctrl.solicitar(j);
    ctrl.cancelar();
    await ctrl.confirmar(entrada([LECHE, "1"]));
    expect(envios).toHaveLength(1);
    expect(ctrl.obtener().fase).toBe("desconocido");
  });

  it("40001 agotado se verifica antes de ofrecer el reintento", async () => {
    const { ctrl, envios, lecturas } = armar();
    ctrl.solicitar(jornada(1));
    const p = ctrl.confirmar(valida());
    envios[0].resolver({
      ok: false,
      intentos: 3,
      error: { codigo: "40001", mensaje: "concurrencia", resultadoDesconocido: false },
    });
    await tick();
    expect(lecturas).toHaveLength(1);
    lecturas[0].resolver("abierta");
    await p;
    expect(ctrl.obtener()).toMatchObject({ fase: "desconocido", reintentable: true });
  });
});

describe("arbitraje con las otras operaciones de la jornada", () => {
  it("mientras la carga está en curso, la salida no puede tomar la misma jornada", () => {
    const arbitro = crearArbitroJornadas();
    const { ctrl } = armar({ arbitro });
    const salidas: unknown[] = [];
    const salida = crearControladorSalida(
      { ejecutar: () => new Promise(() => {}) },
      () => new Promise(() => {}),
      () => {},
      (f) => salidas.push(f),
      undefined,
      arbitro
    );
    const j = jornada(1, "cargada");
    ctrl.solicitar(j);
    void ctrl.confirmar(valida());
    salida.solicitar(j);
    expect(salida.obtener()).toEqual({ fase: "inactiva" });
  });
});

describe("navegación interna y desmontaje (E5/E6): límite DOCUMENTADO, no resuelto", () => {
  it("desmontado, una respuesta tardía no publica ni relee", async () => {
    const { ctrl, envios, publicadas, releer } = armar();
    ctrl.solicitar(jornada(1));
    const p = ctrl.confirmar(valida());
    const antes = publicadas.length;
    ctrl.detener();
    envios[0].resolver(exito());
    await p;
    expect(publicadas).toHaveLength(antes);
    expect(releer).not.toHaveBeenCalled();
  });

  it("DP-1: un controlador nuevo (pantalla re-montada) NO conoce la intención anterior y generaría otra clave", async () => {
    const primero = armar({ prefijo: "pestana-1" });
    primero.ctrl.solicitar(jornada(1));
    void primero.ctrl.confirmar(valida());
    primero.envios[0].resolver(sinRespuesta());
    primero.ctrl.detener(); // navegación por el menú o sesión revalidada: se desmonta

    const segundo = armar({ prefijo: "pestana-2" });
    expect(segundo.ctrl.claveEnCurso()).toBeNull();
    segundo.ctrl.solicitar(jornada(1));
    void segundo.ctrl.confirmar(valida());
    // Clave distinta de la intención perdida: el servidor la trataría como
    // otra carga. Este test fija el riesgo; no lo da por resuelto.
    expect(primero.ctrl.claveEnCurso()).toBe("pestana-1-1");
    expect(segundo.envios[0].clave).not.toBe(primero.envios[0].clave);
  });
});

describe("límites del parche", () => {
  const sinComentarios = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");

  it("no persiste nada en el navegador ni llama RPC directamente", () => {
    const codigo = sinComentarios(fuenteCarga);
    expect(codigo).not.toMatch(/localStorage|sessionStorage|indexedDB|\.rpc\(|\.(insert|update|upsert|delete)\(|randomUUID/);
  });

  it("la pantalla Jornadas monta sólo el borrador: sin el controlador de carga (DP-1 abierto)", () => {
    expect(sinComentarios(fuentePantalla)).not.toMatch(/jornadas_carga|ControladorCarga|definicionCarga|useCargaJornada/);
  });
});
