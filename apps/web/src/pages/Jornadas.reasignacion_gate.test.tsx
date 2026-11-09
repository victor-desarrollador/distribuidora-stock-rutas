// FE-2B — compuerta de la reasignación montada en la pantalla real.
//
// Se renderiza `Jornadas` con un cliente Supabase simulado (sin mockear el
// hook de reasignación ni la capa de datos), se capturan las props del panel
// y se disparan sus manejadores: la única escritura que puede salir es la RPC
// `reasignar_vendedor` (vía el wrapper `ejecutar`), y la única lectura nueva
// es `listar_vendedores_jornada`. Nunca `registrar_carga` ni
// `registrar_descarga`, ni escrituras directas a tablas.

import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { AuthContext, type AuthContextType } from "../auth/AuthContextValue";
import type { RolUsuario } from "../auth/roles";
import { BorradorCargaContexto, type ContextoBorradorCarga } from "../hooks/borradorCargaContexto";
import type { EstadoJornada, Jornada } from "../lib/jornadas";
import { borradorVacio, contextoAutorizacionCarga } from "./carga_borrador";
import type { JornadaCargaPanelProps } from "./JornadaCargaPanel";
import type { JornadaReasignacionPanelProps } from "./JornadaReasignacionPanel";
import Jornadas from "./Jornadas";
import fuentePantalla from "./Jornadas.tsx?raw";

const OP = "99999999-9999-4999-8999-999999999999";
const ORIGINAL = "33333333-3333-4333-8333-333333333333";
const NUEVO = "44444444-4444-4444-8444-444444444444";

const s = vi.hoisted(() => {
  const llamadas: string[] = [];
  const argumentos: Array<{ nombre: string; args: unknown }> = [];
  const respuestas: Record<string, () => Promise<unknown>> = {};
  const builder = (tabla: string) => {
    const b: Record<string, unknown> = {};
    for (const m of ["insert", "update", "upsert", "delete"]) {
      b[m] = () => {
        llamadas.push(`${tabla}.${m}`);
        return b;
      };
    }
    b.select = () => {
      llamadas.push(`${tabla}.select`);
      return b;
    };
    return b;
  };
  const cliente = {
    rpc: vi.fn((nombre: string, args: unknown) => {
      llamadas.push(`rpc:${nombre}`);
      argumentos.push({ nombre, args });
      const r = respuestas[nombre];
      return r ? r() : Promise.resolve({ data: null, error: { code: "PGRST202", message: "no" } });
    }),
    from: vi.fn((tabla: string) => {
      llamadas.push(`from:${tabla}`);
      return builder(tabla);
    }),
  };
  return {
    llamadas,
    argumentos,
    respuestas,
    cliente,
    capturas: [] as JornadaReasignacionPanelProps[],
    capturasCarga: [] as JornadaCargaPanelProps[],
    jornadas: [] as Jornada[],
  };
});

vi.mock("../lib/supabase", async (orig) => ({
  ...(await orig<typeof import("../lib/supabase")>()),
  obtenerClienteSupabase: () => s.cliente,
}));
vi.mock("./JornadaReasignacionPanel", async (orig) => {
  const m = await orig<typeof import("./JornadaReasignacionPanel")>();
  return {
    ...m,
    JornadaReasignacionPanel: (p: JornadaReasignacionPanelProps) => {
      s.capturas.push(p);
      return m.JornadaReasignacionPanel(p);
    },
  };
});
vi.mock("./JornadaCargaPanel", async (orig) => {
  const m = await orig<typeof import("./JornadaCargaPanel")>();
  return {
    ...m,
    JornadaCargaPanel: (p: JornadaCargaPanelProps) => {
      s.capturasCarga.push(p);
      return m.JornadaCargaPanel(p);
    },
  };
});

// Lectura y demás operaciones (CV-1, FE-1) en reposo: fuera de esta compuerta.
const inactiva = { fase: "inactiva" } as const;
vi.mock("../hooks/useJornadasLectura", () => ({
  useJornadasLectura: () => ({
    estado: {
      fecha: null,
      seleccionadaId: s.jornadas[0]?.id ?? null,
      lectura: { estado: "listo", jornadas: s.jornadas, siguiente: null, ampliando: null, errorAmpliacion: null },
    },
    recargar: vi.fn(),
    cambiarFecha: vi.fn(),
    cargarMas: vi.fn(),
    cargarTodas: vi.fn(),
    seleccionar: vi.fn(),
  }),
}));
const operacion = () => ({
  fase: inactiva,
  solicitar: vi.fn(),
  cancelar: vi.fn(),
  confirmar: vi.fn(),
  reintentar: vi.fn(),
  verificarEstado: vi.fn(),
  trasRelectura: vi.fn(),
});
vi.mock("../hooks/useSalidaJornada", () => ({ useSalidaJornada: () => operacion() }));
vi.mock("../hooks/useCorreccionJornada", () => ({ useCorreccionJornada: () => operacion() }));
vi.mock("../hooks/useAperturaJornada", () => ({ useAperturaJornada: () => operacion() }));
vi.mock("../hooks/useVendedoresJornada", () => ({
  useVendedoresJornada: () => ({ estado: { estado: "inactivo" }, recargar: vi.fn() }),
}));
vi.mock("../hooks/useCatalogoCamiones", () => ({
  useCatalogoCamiones: () => ({ catalogo: { estado: "cargando" } }),
}));
vi.mock("../hooks/useHistorialJornada", () => ({
  useHistorialJornada: () => ({ estado: { estado: "inactivo" }, actualizar: vi.fn() }),
}));
vi.mock("../hooks/useCatalogoCargaLectura", async (orig) => ({
  ...(await orig<typeof import("../hooks/useCatalogoCargaLectura")>()),
  useCatalogoCargaLectura: () => ({ catalogo: null, recargar: vi.fn() }),
}));

const USUARIO = "11111111-1111-4111-8111-111111111111";

function jornada(estado: EstadoJornada): Jornada {
  return {
    id: "00000000-0000-4000-8000-000000000001",
    fecha: "2026-11-10",
    camionId: "22222222-2222-4222-8222-222222222222",
    vendedorId: ORIGINAL,
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
  };
}

function auth(rol: RolUsuario, empresaId = "e"): AuthContextType {
  const perfil = { usuarioId: USUARIO, empresaId, usuario: "u", nombre: "N", rol, activo: true };
  return {
    sesion: { estado: "autenticado", perfil, empresa: { id: empresaId, nombre: "E", activo: true } },
    usuario: perfil,
    iniciarSesion: vi.fn(),
    cerrarSesion: vi.fn(),
  };
}

function borrador(a: AuthContextType): ContextoBorradorCarga {
  return {
    borrador: borradorVacio(contextoAutorizacionCarga(a.sesion)),
    pendiente: null,
    iniciar: vi.fn(() => true),
    editar: vi.fn(),
    descartar: vi.fn(),
    pedirCancelacion: vi.fn(() => true),
    pedirCierreSesion: vi.fn(() => true),
    aceptarDescarte: vi.fn(() => null),
    cancelarDescarte: vi.fn(),
  };
}

function pantalla(rol: RolUsuario): string {
  const a = auth(rol);
  return renderToStaticMarkup(
    <AuthContext.Provider value={a}>
      <BorradorCargaContexto.Provider value={borrador(a)}>
        <Jornadas />
      </BorradorCargaContexto.Provider>
    </AuthContext.Provider>
  );
}

const tick = () => new Promise((r) => setTimeout(r, 0));

function sinEscriturasDirectas() {
  expect(s.llamadas.filter((l) => /\.(insert|update|upsert|delete)$/.test(l))).toEqual([]);
  expect(s.llamadas.filter((l) => /registrar_carga|registrar_descarga/.test(l))).toEqual([]);
}

beforeEach(() => {
  vi.clearAllMocks();
  s.llamadas.length = 0;
  s.argumentos.length = 0;
  s.capturas.length = 0;
  s.capturasCarga.length = 0;
  for (const k of Object.keys(s.respuestas)) delete s.respuestas[k];
  s.respuestas.listar_vendedores_jornada = () =>
    Promise.resolve({
      data: [
        { usuario_id: NUEVO, nombre: "Ana", rol: "vendedor_piloto" },
        { usuario_id: ORIGINAL, nombre: "Juan", rol: "encargado" },
      ],
      error: null,
      count: 2,
    });
  s.respuestas.reasignar_vendedor = () => Promise.resolve({ data: OP, error: null });
  s.jornadas = [jornada("abierta")];
});

describe("FE-2B: reasignación en la pantalla Jornadas", () => {
  it.each(["dueno", "encargado"] as const)("%s: el panel se monta y montar no llama a ninguna RPC", (rol) => {
    const h = pantalla(rol);
    expect(s.capturas.length).toBeGreaterThan(0);
    expect(h).toContain("Cambiar vendedor");
    expect(s.cliente.rpc).not.toHaveBeenCalled();
    sinEscriturasDirectas();
  });

  it.each(["dueno", "encargado"] as const)(
    "%s autorizado: elegir y confirmar sólo invoca listar_vendedores_jornada y reasignar_vendedor",
    async (rol) => {
      pantalla(rol);
      const p = s.capturas[s.capturas.length - 1];
      p.onSolicitar(p.jornada);
      await tick();
      expect(s.llamadas).toEqual(["rpc:listar_vendedores_jornada"]);
      p.onConfirmar({ vendedorId: NUEVO, permitidos: [NUEVO] });
      await tick();
      await tick();
      expect(s.llamadas).toEqual(["rpc:listar_vendedores_jornada", "rpc:reasignar_vendedor"]);
      const envio = s.argumentos.find((x) => x.nombre === "reasignar_vendedor");
      expect(envio?.args).toEqual({
        p_idempotency_key: expect.stringMatching(/^[0-9a-f-]{36}$/),
        p_jornada_id: jornada("abierta").id,
        p_vendedor_id: NUEVO,
      });
      // Los demás manejadores tampoco escriben nada más.
      p.onReintentar();
      p.onVerificar();
      p.onCancelar();
      p.onRecargarVendedores();
      await tick();
      expect(s.llamadas.filter((l) => l === "rpc:reasignar_vendedor")).toHaveLength(1);
      sinEscriturasDirectas();
    }
  );

  it("vendedor/piloto no autorizado: sin panel, sin lectura de vendedores ni RPC", () => {
    const h = pantalla("vendedor_piloto");
    expect(s.capturas).toHaveLength(0);
    expect(h).not.toContain("Cambiar vendedor");
    expect(s.cliente.rpc).not.toHaveBeenCalled();
    sinEscriturasDirectas();
  });

  it("jornada en reparto (salida confirmada): el panel no ofrece el cambio y no se envía nada", async () => {
    s.jornadas = [jornada("en_reparto")];
    const h = pantalla("dueno");
    expect(h).not.toContain("Cambiar vendedor");
    const p = s.capturas[s.capturas.length - 1];
    p.onSolicitar(p.jornada);
    p.onConfirmar({ vendedorId: NUEVO, permitidos: [NUEVO] });
    await tick();
    expect(s.cliente.rpc).not.toHaveBeenCalled();
  });

  it("al mismo vendedor: no se envía", async () => {
    pantalla("dueno");
    const p = s.capturas[s.capturas.length - 1];
    p.onSolicitar(p.jornada);
    await tick();
    p.onConfirmar({ vendedorId: ORIGINAL, permitidos: [ORIGINAL] });
    await tick();
    expect(s.llamadas).not.toContain("rpc:reasignar_vendedor");
  });

  it("fallo de red: el wrapper reenvía con la MISMA clave, luego verifica leyendo y no afirma éxito", async () => {
    s.respuestas.reasignar_vendedor = () => Promise.reject(new Error("red"));
    pantalla("encargado");
    const p = s.capturas[s.capturas.length - 1];
    p.onSolicitar(p.jornada);
    await tick();
    p.onConfirmar({ vendedorId: NUEVO, permitidos: [NUEVO] });
    for (let i = 0; i < 10; i++) await tick();
    const envios = s.argumentos.filter((x) => x.nombre === "reasignar_vendedor");
    expect(envios.length).toBeGreaterThan(0);
    const claves = new Set(envios.map((x) => (x.args as { p_idempotency_key: string }).p_idempotency_key));
    expect(claves.size).toBe(1);
    // La verificación lee la tabla jornadas (lectura autorizada por RLS), sin escribir.
    expect(s.llamadas).toContain("from:jornadas");
    sinEscriturasDirectas();
  });

  it("FE-1 intacto: el panel de carga sigue sin onConfirmar ni puertos", () => {
    pantalla("dueno");
    expect(s.capturasCarga.length).toBeGreaterThan(0);
    for (const p of s.capturasCarga) {
      expect(p.onConfirmar).toBeUndefined();
      expect(p.onReintentar).toBeUndefined();
      expect(p.onVerificar).toBeUndefined();
    }
  });

  it("la pantalla no construye comandos de carga ni descarga", () => {
    expect(fuentePantalla).not.toMatch(/registrar_carga|registrar_descarga/);
    expect(fuentePantalla).not.toMatch(/tipo:\s*"(cargar|descargar)"/);
    expect(fuentePantalla).not.toMatch(/crearControladorCarga|definicionCarga/);
  });
});
