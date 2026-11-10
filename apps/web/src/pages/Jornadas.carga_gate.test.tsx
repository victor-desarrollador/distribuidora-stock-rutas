// FE-1D — compuerta de escritura de la carga montada en la pantalla real.
//
// No alcanza con un grep: `lib/jornadas.ts` contiene el wrapper de
// `registrar_carga` (comando `cargar` de `ejecutar`). Aquí se renderiza la
// pantalla `Jornadas` real con un cliente Supabase simulado y espías en las
// fábricas de puertos y del controlador de carga, se capturan las props que
// recibe el panel y se disparan TODOS sus manejadores: ninguno llega a una RPC
// ni construye el puerto de ejecución.

import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { AuthContext, type AuthContextType } from "../auth/AuthContextValue";
import type { ConfirmarDescarteBorradorProps } from "../components/ConfirmarDescarteBorrador";
import type { RolUsuario } from "../auth/roles";
import {
  BorradorCargaContexto,
  type ContextoBorradorCarga,
} from "../hooks/borradorCargaContexto";
import { BorradorCargaProvider } from "../hooks/BorradorCargaProvider";
import { useBorradorCarga } from "../hooks/borradorCargaContexto";
import { crearLecturaProductos, type CatalogoCarga } from "../hooks/useCatalogoCargaLectura";
import type { EstadoJornada, Jornada } from "../lib/jornadas";
import {
  borradorVacio,
  contextoAutorizacionCarga,
  crearAccionesBorrador,
  editarBorrador,
  estadoDeContexto,
  iniciarBorrador,
  type BorradorCarga,
  type EstadoBorrador,
  type SolicitudDescarte,
} from "./carga_borrador";
import type { EdicionCarga } from "./carga_edicion";
import type { JornadaCargaPanelProps } from "./JornadaCargaPanel";
import type { ProductoCarga } from "./jornadas_carga";
import Jornadas from "./Jornadas";

const s = vi.hoisted(() => {
  const llamadasCliente: string[] = [];
  const builder = (tabla: string) => {
    const b: Record<string, unknown> = {};
    for (const m of ["insert", "update", "upsert", "delete"]) {
      b[m] = () => {
        llamadasCliente.push(`${tabla}.${m}`);
        return b;
      };
    }
    b.select = () => {
      llamadasCliente.push(`${tabla}.select`);
      return b;
    };
    b.order = () =>
      Promise.resolve({
        data: [
          { id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", codigo: "L1", nombre: "Leche", categoria: "lacteos", forma_venta: "unidad", precio: 100, stock_minimo: 0, activo: true },
          { id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", codigo: null, nombre: "Jamón", categoria: "fiambres", forma_venta: "peso", precio: 9000, stock_minimo: 0, activo: false },
        ],
        error: null,
      });
    return b;
  };
  const cliente = {
    rpc: vi.fn((nombre: string) => {
      llamadasCliente.push(`rpc:${nombre}`);
      return Promise.resolve({ data: null, error: null });
    }),
    from: vi.fn((tabla: string) => {
      llamadasCliente.push(`from:${tabla}`);
      return builder(tabla);
    }),
  };
  return {
    llamadasCliente,
    cliente,
    obtenerPuertoJornadas: vi.fn(),
    crearPuertoJornadas: vi.fn(),
    crearControladorCarga: vi.fn(),
    definicionCarga: vi.fn(),
    capturas: [] as JornadaCargaPanelProps[],
    confirmaciones: [] as ConfirmarDescarteBorradorProps[],
    lecturaCatalogoContexto: [] as (string | null)[],
    catalogoForzado: undefined as CatalogoCarga | undefined,
    recargarCatalogo: vi.fn(),
    jornadas: [] as Jornada[],
    seleccionadaId: null as string | null,
  };
});

vi.mock("../lib/supabase", async (orig) => ({
  ...(await orig<typeof import("../lib/supabase")>()),
  obtenerClienteSupabase: () => s.cliente,
}));
vi.mock("../lib/jornadas", async (orig) => ({
  ...(await orig<typeof import("../lib/jornadas")>()),
  obtenerPuertoJornadas: s.obtenerPuertoJornadas,
  crearPuertoJornadas: s.crearPuertoJornadas,
}));
vi.mock("./jornadas_carga", async (orig) => ({
  ...(await orig<typeof import("./jornadas_carga")>()),
  crearControladorCarga: s.crearControladorCarga,
  definicionCarga: s.definicionCarga,
}));
vi.mock("./JornadaCargaPanel", async (orig) => {
  const m = await orig<typeof import("./JornadaCargaPanel")>();
  return {
    ...m,
    JornadaCargaPanel: (p: JornadaCargaPanelProps) => {
      s.capturas.push(p);
      return m.JornadaCargaPanel(p);
    },
  };
});

vi.mock("../components/ConfirmarDescarteBorrador", async (orig) => {
  const m = await orig<typeof import("../components/ConfirmarDescarteBorrador")>();
  return {
    ...m,
    ConfirmarDescarteBorrador: (p: ConfirmarDescarteBorradorProps) => {
      s.confirmaciones.push(p);
      return m.ConfirmarDescarteBorrador(p);
    },
  };
});

// Operaciones existentes (CV-1) en reposo: fuera de esta compuerta.
const inactiva = { fase: "inactiva" } as const;
vi.mock("../hooks/useJornadasLectura", () => ({
  useJornadasLectura: () => ({
    estado: {
      fecha: null,
      seleccionadaId: s.seleccionadaId,
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
  useCatalogoCargaLectura: (contexto: string | null) => {
    s.lecturaCatalogoContexto.push(contexto);
    const catalogo = s.catalogoForzado !== undefined ? s.catalogoForzado : contexto !== null ? CATALOGO : null;
    return { catalogo, recargar: s.recargarCatalogo };
  },
}));

const USUARIO = "11111111-1111-4111-8111-111111111111";
const LECHE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const JAMON = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const VIEJO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const CATALOGO: ProductoCarga[] = [
  { id: LECHE, codigo: "L1", nombre: "Leche entera", formaVenta: "unidad", activo: true },
  { id: JAMON, codigo: null, nombre: "Jamón cocido", formaVenta: "peso", activo: true },
  { id: VIEJO, codigo: null, nombre: "Queso discontinuado", formaVenta: "unidad", activo: false },
];

function jornada(estado: EstadoJornada): Jornada {
  return {
    id: "00000000-0000-4000-8000-000000000001",
    fecha: "2026-11-10",
    camionId: "22222222-2222-4222-8222-222222222222",
    vendedorId: "33333333-3333-4333-8333-333333333333",
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

const CTX_DUENO = contextoAutorizacionCarga(auth("dueno").sesion)!;

const REVISANDO: EdicionCarga = {
  lineas: [
    { productoId: LECHE, texto: "24" },
    { productoId: JAMON, texto: "1,250" },
  ],
  revisando: true,
  mostrarErrores: true,
};

function contexto(
  borrador: BorradorCarga,
  pendiente: SolicitudDescarte | null = null,
  iniciarProcede = true
): ContextoBorradorCarga {
  return {
    borrador,
    pendiente,
    iniciar: vi.fn(() => iniciarProcede),
    editar: vi.fn(),
    descartar: vi.fn(),
    pedirCancelacion: vi.fn(() => true),
    pedirCierreSesion: vi.fn(() => true),
    aceptarDescarte: vi.fn(() => pendiente),
    cancelarDescarte: vi.fn(),
  };
}

function pantalla(rol: RolUsuario, ctx: ContextoBorradorCarga, a: AuthContextType = auth(rol)): string {
  return renderToStaticMarkup(
    <AuthContext.Provider value={a}>
      <BorradorCargaContexto.Provider value={ctx}>
        <Jornadas />
      </BorradorCargaContexto.Provider>
    </AuthContext.Provider>
  );
}

function sinEscrituras() {
  expect(s.cliente.rpc).not.toHaveBeenCalled();
  expect(s.llamadasCliente.filter((l) => /rpc:|\.(insert|update|upsert|delete)$/.test(l))).toEqual([]);
  expect(s.obtenerPuertoJornadas).not.toHaveBeenCalled();
  expect(s.crearPuertoJornadas).not.toHaveBeenCalled();
  expect(s.crearControladorCarga).not.toHaveBeenCalled();
  expect(s.definicionCarga).not.toHaveBeenCalled();
}

const botonesConfirmar = (h: string) =>
  [...h.matchAll(/<button([^>]*)>(?:(?!<\/button>)[\s\S])*Confirmar carga<\/button>/g)].map((m) => m[1]);

beforeEach(() => {
  vi.clearAllMocks();
  s.llamadasCliente.length = 0;
  s.capturas.length = 0;
  s.confirmaciones.length = 0;
  s.lecturaCatalogoContexto.length = 0;
  s.catalogoForzado = undefined;
  s.jornadas = [jornada("abierta")];
  s.seleccionadaId = s.jornadas[0].id;
});

describe("FE-1D: pantalla Jornadas con el borrador de carga montado", () => {
  const J = jornada("abierta");
  const enRevision = (): BorradorCarga => ({ contexto: CTX_DUENO, jornadaId: J.id, edicion: REVISANDO });

  it("gestión: el panel recibe SÓLO props de preparación (sin confirmar, reintentar, verificar ni puertos)", () => {
    pantalla("dueno", contexto(enRevision()));
    expect(s.capturas.length).toBeGreaterThan(0);
    for (const p of s.capturas) {
      expect(Object.keys(p).sort()).toEqual([
        "bloqueadaPorOtra",
        "catalogo",
        "edicion",
        "fase",
        "jornada",
        "nombreCamion",
        "onCancelar",
        "onEdicion",
        "onSolicitar",
      ]);
      expect(p.onConfirmar).toBeUndefined();
      expect(p.onReintentar).toBeUndefined();
      expect(p.onVerificar).toBeUndefined();
      for (const v of Object.values(p)) {
        if (v !== null && typeof v === "object") expect(v).not.toHaveProperty("ejecutar");
      }
    }
    sinEscrituras();
  });

  it("resumen visible con «Confirmar carga» deshabilitado y el aviso explícito", () => {
    const h = pantalla("encargado", contexto(enRevision()));
    expect(h).toContain("24 un.");
    expect(h).toContain("1,250 kg");
    const confirmar = botonesConfirmar(h);
    expect(confirmar).toHaveLength(1);
    expect(confirmar[0]).toMatch(/\sdisabled=""/);
    expect(confirmar[0]).toContain('aria-disabled="true"');
    expect(h).toContain("La confirmación de carga está temporalmente deshabilitada");
    expect(h).toContain("todavía no se registra ninguna carga ni se mueve stock");
    sinEscrituras();
  });

  it("disparar todos los manejadores del panel sólo toca el borrador y relee el catálogo", () => {
    const ctx = contexto(enRevision());
    pantalla("dueno", ctx);
    const p = s.capturas.at(-1)!;
    p.onSolicitar(J);
    p.onEdicion({ ...REVISANDO, revisando: false });
    p.onCancelar();
    expect(ctx.iniciar).toHaveBeenCalledWith(J.id);
    expect(ctx.editar).toHaveBeenCalledTimes(1);
    // FE-1F (H-02): «Cancelar» pasa por la confirmación, nunca descarta directo.
    expect(ctx.pedirCancelacion).toHaveBeenCalledTimes(1);
    expect(ctx.descartar).not.toHaveBeenCalled();
    expect(s.recargarCatalogo).toHaveBeenCalledTimes(1);
    sinEscrituras();
  });

  it("navegación: el borrador retenido vuelve a mostrarse con la confirmación deshabilitada", () => {
    // El provider vive sobre el router: al volver a la pantalla, el mismo
    // borrador llega por contexto. Se renderiza dos veces (salir y volver).
    const ctx = contexto(enRevision());
    pantalla("dueno", ctx);
    const h = pantalla("dueno", ctx);
    expect(botonesConfirmar(h)[0]).toMatch(/\sdisabled=""/);
    sinEscrituras();
  });

  it("el borrador de una jornada que dejó de ser cargable no abre el formulario", () => {
    s.jornadas = [jornada("en_reparto")];
    const h = pantalla("dueno", contexto({ ...enRevision() }));
    expect(h).not.toContain("Confirmar carga");
    expect(h).not.toContain("<form");
    sinEscrituras();
  });

  it("producto inactivo: no se ofrece en el formulario", () => {
    const b = iniciarBorrador(borradorVacio(CTX_DUENO), J.id);
    const h = pantalla("dueno", contexto(b));
    expect(h).toContain("<form");
    const opciones = [...h.matchAll(/<option value="([^"]*)"/g)].map((m) => m[1]);
    expect(opciones).toEqual(["", JAMON, LECHE]);
    expect(h).not.toContain(VIEJO);
    sinEscrituras();
  });

  it("vendedor/piloto: sin panel de carga y sin lectura del catálogo", () => {
    const h = pantalla("vendedor_piloto", contexto(enRevision()));
    expect(s.capturas).toHaveLength(0);
    expect(s.lecturaCatalogoContexto.every((c) => c === null)).toBe(true);
    expect(h).not.toContain("Cargar mercadería");
    sinEscrituras();
  });
});

describe("FE-1E: cambiar de jornada con un borrador escrito", () => {
  const J = jornada("abierta");
  const OTRA = "00000000-0000-4000-8000-000000000009";

  // Estado real del borrador (lógica pura del provider) en memoria: cada
  // `ctx()` equivale a un nuevo render con el estado vigente.
  function memoria(inicial: EstadoBorrador) {
    let e = inicial;
    return {
      estado: () => e,
      ctx: (): ContextoBorradorCarga => ({
        borrador: e.borrador,
        pendiente: e.pendiente,
        ...crearAccionesBorrador(
          e,
          (f) => {
            e = f(estadoDeContexto(e, CTX_DUENO));
          },
          () => true
        ),
      }),
    };
  }
  const escritoEnOtra = (): EstadoBorrador => ({
    borrador: editarBorrador(iniciarBorrador(borradorVacio(CTX_DUENO), OTRA), REVISANDO),
    pendiente: null,
  });

  it("pedir la carga de esta jornada queda pendiente: no abre el formulario ni relee el catálogo", () => {
    const m = memoria(escritoEnOtra());
    pantalla("dueno", m.ctx());
    s.capturas.at(-1)!.onSolicitar(J);
    expect(m.estado().pendiente).toEqual({ tipo: "cambiar_jornada", jornadaId: J.id });
    expect(m.estado().borrador.jornadaId).toBe(OTRA);
    expect(m.estado().borrador.edicion).toBe(REVISANDO);
    expect(s.recargarCatalogo).not.toHaveBeenCalled();

    s.capturas.length = 0;
    const h = pantalla("dueno", m.ctx());
    expect(h).toContain('role="alertdialog"');
    expect(h).toContain("ese borrador se descarta y no se puede recuperar");
    expect(h).toContain("Conservar el borrador");
    expect(h).toContain("Descartar y cargar esta jornada");
    expect(h).not.toContain("<form");
    expect(s.capturas).toHaveLength(0);
    sinEscrituras();
  });

  it("cancelar conserva el borrador de la otra jornada y no abre esta", () => {
    const m = memoria(escritoEnOtra());
    pantalla("dueno", m.ctx());
    s.capturas.at(-1)!.onSolicitar(J);
    pantalla("dueno", m.ctx());
    s.confirmaciones.at(-1)!.onCancelar();
    expect(m.estado()).toEqual(escritoEnOtra());
    expect(s.recargarCatalogo).not.toHaveBeenCalled();

    s.confirmaciones.length = 0;
    const h = pantalla("dueno", m.ctx());
    expect(s.confirmaciones).toHaveLength(0);
    expect(h).toContain("Cargar mercadería");
    expect(h).not.toContain("<form");
    sinEscrituras();
  });

  it("confirmar descarta el borrador anterior, abre esta jornada vacía y relee el catálogo", () => {
    const m = memoria(escritoEnOtra());
    pantalla("dueno", m.ctx());
    s.capturas.at(-1)!.onSolicitar(J);
    pantalla("dueno", m.ctx());
    s.confirmaciones.at(-1)!.onAceptar();
    expect(m.estado()).toEqual({
      borrador: iniciarBorrador(borradorVacio(CTX_DUENO), J.id),
      pendiente: null,
    });
    expect(s.recargarCatalogo).toHaveBeenCalledTimes(1);

    const h = pantalla("dueno", m.ctx());
    expect(h).toContain("<form");
    // «Confirmar carga» sigue sin manejador: el formulario recién abierto no
    // llega a revisión, pero nunca se ofrece un botón habilitado.
    for (const b of botonesConfirmar(h)) expect(b).toMatch(/\sdisabled=""/);
    expect(s.capturas.at(-1)!.onConfirmar).toBeUndefined();
    sinEscrituras();
  });

  it("sin nada escrito, pedir la carga abre directo (sin pregunta)", () => {
    const m = memoria({ borrador: iniciarBorrador(borradorVacio(CTX_DUENO), OTRA), pendiente: null });
    pantalla("dueno", m.ctx());
    s.capturas.at(-1)!.onSolicitar(J);
    expect(m.estado()).toEqual({ borrador: iniciarBorrador(borradorVacio(CTX_DUENO), J.id), pendiente: null });
    expect(s.recargarCatalogo).toHaveBeenCalledTimes(1);
    expect(s.confirmaciones).toHaveLength(0);
    sinEscrituras();
  });

  it("reabrir la MISMA jornada escrita no pregunta y conserva lo escrito", () => {
    const m = memoria({
      borrador: editarBorrador(iniciarBorrador(borradorVacio(CTX_DUENO), J.id), REVISANDO),
      pendiente: null,
    });
    pantalla("dueno", m.ctx());
    s.capturas.at(-1)!.onSolicitar(J);
    expect(m.estado().pendiente).toBeNull();
    expect(m.estado().borrador.edicion).toBe(REVISANDO);
    sinEscrituras();
  });
});

describe("FE-1D: provider del borrador", () => {
  function Sonda() {
    const c = useBorradorCarga();
    return <pre>{JSON.stringify({ claves: Object.keys(c).sort(), borrador: c.borrador, pendiente: c.pendiente })}</pre>;
  }
  const leer = (a: AuthContextType) =>
    JSON.parse(
      renderToStaticMarkup(
        <AuthContext.Provider value={a}>
          <BorradorCargaProvider>
            <Sonda />
          </BorradorCargaProvider>
        </AuthContext.Provider>
      )
        .replace(/^<pre>|<\/pre>$/g, "")
        .replace(/&quot;/g, '"')
    );

  it("expone sólo acciones del borrador: ninguna de confirmar carga, enviar ni verificar", () => {
    const r = leer(auth("dueno"));
    expect(r.claves).toEqual([
      "aceptarDescarte",
      "borrador",
      "cancelarDescarte",
      "descartar",
      "editar",
      "iniciar",
      "pedirCancelacion",
      "pedirCierreSesion",
      "pendiente",
    ]);
    expect(r.pendiente).toBeNull();
    expect(r.borrador).toEqual({ contexto: CTX_DUENO, jornadaId: null, edicion: { lineas: [{ productoId: "", texto: "" }], revisando: false, mostrarErrores: false } });
    sinEscrituras();
  });

  it("sin sesión autenticada el borrador es de nadie (null)", () => {
    const a = { ...auth("dueno"), usuario: null, sesion: { estado: "no_autenticado" } } as AuthContextType;
    expect(leer(a).borrador.contexto).toBeNull();
  });

  it.each<[string, AuthContextType]>([
    ["autorización pendiente", { ...auth("dueno"), usuario: null, sesion: { estado: "cargando" } }],
    ["usuario desactivado", { ...auth("dueno"), usuario: null, sesion: { estado: "bloqueado", motivo: "perfil_inactivo" } }],
    ["perfil no verificable", { ...auth("dueno"), usuario: null, sesion: { estado: "error", mensaje: "x" } }],
    ["vendedor/piloto", auth("vendedor_piloto")],
  ])("FE-1F: %s: el provider no tiene contexto para el borrador (falla cerrado)", (_n, a) => {
    expect(leer(a).borrador).toEqual({ contexto: null, jornadaId: null, edicion: { lineas: [{ productoId: "", texto: "" }], revisando: false, mostrarErrores: false } });
  });

  it("FE-1F: el contexto del provider sale de la sesión protegida (empresa y rol), no sólo del usuario", () => {
    expect(leer(auth("dueno")).borrador.contexto).toBe(CTX_DUENO);
    expect(leer(auth("dueno", "otra")).borrador.contexto).toBe(contextoAutorizacionCarga(auth("dueno", "otra").sesion));
    expect(leer(auth("dueno", "otra")).borrador.contexto).not.toBe(CTX_DUENO);
    expect(leer(auth("encargado")).borrador.contexto).not.toBe(CTX_DUENO);
  });
});

describe("FE-1D: el catálogo se usa sólo para leer", () => {
  it("el puerto de lectura expone únicamente `listar`", () => {
    expect(Object.keys(crearLecturaProductos())).toEqual(["listar"]);
  });

  it("listar hace un SELECT sobre `productos` y nada más (RLS acota la empresa)", async () => {
    const r = await crearLecturaProductos().listar();
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.datos.map((p) => [p.formaVenta, p.activo])).toEqual([["unidad", true], ["peso", false]]);
    expect(s.llamadasCliente).toEqual(["from:productos", "productos.select"]);
    sinEscrituras();
  });
});

describe("FE-1F: «Cancelar» del formulario con un borrador escrito (H-02)", () => {
  const J = jornada("abierta");
  const EDITANDO: EdicionCarga = { lineas: [{ productoId: LECHE, texto: "24" }], revisando: false, mostrarErrores: false };

  function memoria(inicial: EstadoBorrador) {
    let e = inicial;
    return {
      estado: () => e,
      ctx: (): ContextoBorradorCarga => ({
        borrador: e.borrador,
        pendiente: e.pendiente,
        ...crearAccionesBorrador(e, (f) => (e = f(e)), () => true),
      }),
    };
  }
  const con = (edicion: EdicionCarga): EstadoBorrador => ({
    borrador: editarBorrador(iniciarBorrador(borradorVacio(CTX_DUENO), J.id), edicion),
    pendiente: null,
  });

  it.each<[string, EdicionCarga, CatalogoCarga | undefined]>([
    ["en edición", EDITANDO, undefined],
    ["en el resumen", REVISANDO, undefined],
    ["con el catálogo cargando", EDITANDO, "cargando"],
    ["con error de catálogo", EDITANDO, null],
  ])("%s: pide confirmación y no toca lo escrito", (_n, edicion, catalogo) => {
    s.catalogoForzado = catalogo;
    const m = memoria(con(edicion));
    pantalla("dueno", m.ctx());
    s.capturas.at(-1)!.onCancelar();
    expect(m.estado()).toEqual({ borrador: con(edicion).borrador, pendiente: { tipo: "cancelar_carga" } });

    s.capturas.length = 0;
    const h = pantalla("dueno", m.ctx());
    expect(h).toContain('role="alertdialog"');
    expect(h).toContain("Si cancelás, el borrador se descarta y no se puede recuperar");
    expect(h).toContain("Conservar el borrador");
    expect(h).toContain("Descartar el borrador");
    expect(h).not.toContain("<form");
    expect(s.capturas).toHaveLength(0);
    for (const b of botonesConfirmar(h)) expect(b).toMatch(/\sdisabled=""/);
    sinEscrituras();
  });

  it("elegir conservar: mantiene líneas y jornada y vuelve el formulario", () => {
    const m = memoria(con(EDITANDO));
    pantalla("dueno", m.ctx());
    s.capturas.at(-1)!.onCancelar();
    pantalla("dueno", m.ctx());
    s.confirmaciones.at(-1)!.onCancelar();
    expect(m.estado()).toEqual(con(EDITANDO));

    s.confirmaciones.length = 0;
    const h = pantalla("dueno", m.ctx());
    expect(s.confirmaciones).toHaveLength(0);
    expect(h).toContain("<form");
    expect(h).toContain('value="24"');
    sinEscrituras();
  });

  it("elegir descartar: elimina el borrador y cierra la edición", () => {
    const m = memoria(con(REVISANDO));
    pantalla("dueno", m.ctx());
    s.capturas.at(-1)!.onCancelar();
    pantalla("dueno", m.ctx());
    s.confirmaciones.at(-1)!.onAceptar();
    expect(m.estado()).toEqual({ borrador: borradorVacio(CTX_DUENO), pendiente: null });

    const h = pantalla("dueno", m.ctx());
    expect(h).not.toContain("<form");
    expect(h).not.toContain('role="alertdialog"');
    expect(h).toContain("Cargar mercadería");
    expect(botonesConfirmar(h)).toHaveLength(0);
    sinEscrituras();
  });

  it("sin nada escrito: cancela normalmente, sin pregunta", () => {
    const m = memoria({ borrador: iniciarBorrador(borradorVacio(CTX_DUENO), J.id), pendiente: null });
    pantalla("dueno", m.ctx());
    s.capturas.at(-1)!.onCancelar();
    expect(m.estado()).toEqual({ borrador: borradorVacio(CTX_DUENO), pendiente: null });
    const h = pantalla("dueno", m.ctx());
    expect(s.confirmaciones).toHaveLength(0);
    expect(h).not.toContain("<form");
    sinEscrituras();
  });
});

describe("FE-1F: el catálogo de carga se pide con el contexto de autorización (H-01)", () => {
  const vacio = () => contexto(borradorVacio(CTX_DUENO));

  it("gestión: el hook recibe usuario + empresa + rol, no un booleano", () => {
    pantalla("dueno", vacio());
    expect(s.lecturaCatalogoContexto.at(-1)).toBe(CTX_DUENO);
  });

  it("mismo usuario en otra empresa u otro rol: otro contexto (el hook borra y relee)", () => {
    pantalla("dueno", vacio(), auth("dueno", "otra"));
    const otraEmpresa = s.lecturaCatalogoContexto.at(-1);
    pantalla("encargado", vacio());
    const otroRol = s.lecturaCatalogoContexto.at(-1);
    expect(otraEmpresa).not.toBeNull();
    expect(otraEmpresa).not.toBe(CTX_DUENO);
    expect(otroRol).not.toBeNull();
    expect(otroRol).not.toBe(CTX_DUENO);
    expect(otroRol).not.toBe(otraEmpresa);
  });

  it("empresa inactiva en la sesión: sin contexto ni catálogo (falla cerrado)", () => {
    const a = auth("dueno");
    if (a.sesion.estado === "autenticado") a.sesion = { ...a.sesion, empresa: { ...a.sesion.empresa, activo: false } };
    pantalla("dueno", vacio(), a);
    expect(s.lecturaCatalogoContexto.every((c) => c === null)).toBe(true);
    sinEscrituras();
  });
});
