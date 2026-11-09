import { isValidElement, type ReactElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

import type { EstadoJornada, Jornada } from "../lib/jornadas";
import {
  JornadaCargaPanel,
  MENSAJE_BORRADOR_VOLATIL,
  MENSAJE_CONFIRMACION_DESHABILITADA,
  type JornadaCargaPanelProps,
} from "./JornadaCargaPanel";
import { EDICION_INICIAL, type EdicionCarga } from "./carga_edicion";
import {
  MENSAJE_CARGA_CANTIDAD_PESO,
  MENSAJE_CARGA_INCIERTA,
  MENSAJE_CARGA_SIN_VERIFICAR,
  type FaseCarga,
  type ProductoCarga,
} from "./jornadas_carga";
import fuentePanel from "./JornadaCargaPanel.tsx?raw";
import fuentePantalla from "./Jornadas.tsx?raw";
import fuenteApp from "../App.tsx?raw";

const CAMION = "22222222-2222-4222-8222-222222222222";
const LECHE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const JAMON = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const VIEJO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const CATALOGO: ProductoCarga[] = [
  { id: LECHE, codigo: "L1", nombre: "Leche entera", formaVenta: "unidad", activo: true },
  { id: JAMON, codigo: null, nombre: "Jamón cocido", formaVenta: "peso", activo: true },
  { id: VIEJO, codigo: null, nombre: "Queso discontinuado", formaVenta: "unidad", activo: false },
];

function jornada(n: number, estado: EstadoJornada = "abierta"): Jornada {
  return {
    id: `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`,
    fecha: "2026-11-10",
    camionId: CAMION,
    vendedorId: "33333333-3333-4333-8333-333333333333",
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
  };
}

const J = jornada(1);
const confirmando = (error?: string): FaseCarga => ({ fase: "confirmando", jornadaId: J.id, error });
const edicion = (lineas: Array<[string, string]>, extra: Partial<EdicionCarga> = {}): EdicionCarga => ({
  lineas: lineas.map(([productoId, texto]) => ({ productoId, texto })),
  revisando: false,
  mostrarErrores: false,
  ...extra,
});

function props(cambios: Partial<JornadaCargaPanelProps> = {}): JornadaCargaPanelProps {
  return {
    jornada: J,
    fase: { fase: "inactiva" },
    catalogo: CATALOGO,
    nombreCamion: () => "Camión Norte · AB123CD",
    edicion: EDICION_INICIAL,
    onEdicion: vi.fn(),
    onSolicitar: vi.fn(),
    onCancelar: vi.fn(),
    onConfirmar: vi.fn(),
    onReintentar: vi.fn(),
    onVerificar: vi.fn(),
    ...cambios,
  };
}

const html = (p: JornadaCargaPanelProps) => renderToStaticMarkup(<JornadaCargaPanel {...p} />);

function botones(h: string) {
  return [...h.matchAll(/<button([^>]*)>([\s\S]*?)<\/button>/g)].map((m) => ({
    texto: (m[1].match(/aria-label="([^"]+)"/)?.[1] ?? m[2].replace(/<[^>]+>/g, "")).trim(),
    deshabilitado: /\sdisabled(=|\s|>|$)/.test(m[1]),
  }));
}

// ---- Árbol de elementos: los componentes del panel no usan hooks, así que se
// pueden resolver llamándolos y disparar los manejadores reales. ----
type Nodo = ReactElement<Record<string, unknown>>;
function resolver(n: ReactNode): Nodo[] {
  if (Array.isArray(n)) return n.flatMap(resolver);
  if (!isValidElement(n)) return [];
  const el = n as Nodo;
  if (typeof el.type === "function") return resolver((el.type as (p: unknown) => ReactNode)(el.props));
  return [el, ...resolver(el.props.children as ReactNode)];
}
const texto = (n: ReactNode): string =>
  Array.isArray(n) ? n.map(texto).join("") : isValidElement(n) ? texto((n as Nodo).props.children as ReactNode) : n == null || typeof n === "boolean" ? "" : String(n);
function arbol(p: JornadaCargaPanelProps) {
  return resolver(<JornadaCargaPanel {...p} />);
}
function boton(p: JornadaCargaPanelProps, nombre: string): Nodo {
  const b = arbol(p).find(
    (e) => e.type === "button" && ((e.props["aria-label"] as string | undefined) ?? texto(e.props.children as ReactNode)).trim() === nombre
  );
  if (!b) throw new Error(`sin botón «${nombre}»`);
  return b;
}
const click = (b: Nodo) => (b.props.onClick as () => void)();
const campo = (p: JornadaCargaPanelProps, id: string) => arbol(p).find((e) => e.props.id === id)!;

// ---- Accesibilidad estructural sobre el HTML. ----
function auditarA11y(h: string) {
  const ids = [...h.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]);
  expect(new Set(ids).size).toBe(ids.length); // ids únicos
  for (const m of h.matchAll(/aria-(?:describedby|labelledby)="([^"]+)"/g)) {
    for (const ref of m[1].split(" ")) expect(ids).toContain(ref);
  }
  for (const m of h.matchAll(/<(select|input|textarea)[^>]*\sid="([^"]+)"/g)) {
    expect(h).toMatch(new RegExp(`<label[^>]*for="${m[2]}"`));
  }
  expect(h).not.toMatch(/tabindex="[1-9]/i);
  for (const b of botones(h)) expect(b.texto).not.toBe("");
  for (const m of h.matchAll(/<button([^>]*)>/g)) expect(m[1]).toContain("min-h-12");
  for (const m of h.matchAll(/<svg([^>]*)>/g)) expect(m[1]).toContain('aria-hidden="true"');
}

describe("botón de inicio", () => {
  it.each<EstadoJornada>(["abierta", "cargada"])("jornada %s: «Cargar mercadería» habilitado", (estado) => {
    const p = props({ jornada: jornada(1, estado) });
    expect(botones(html(p))).toEqual([{ texto: "Cargar mercadería", deshabilitado: false }]);
    click(boton(p, "Cargar mercadería"));
    expect(p.onSolicitar).toHaveBeenCalledWith(p.jornada);
  });

  it.each<EstadoJornada>(["en_reparto", "ventas_finalizadas", "regreso_contado", "cerrada"])(
    "jornada %s: deshabilitado con la razón asociada",
    (estado) => {
      const h = html(props({ jornada: jornada(1, estado) }));
      expect(botones(h)).toEqual([{ texto: "Cargar mercadería", deshabilitado: true }]);
      expect(h).toContain("Sólo se puede cargar una jornada abierta o cargada");
      auditarA11y(h);
    }
  );

  it("retenida por otra operación: deshabilitado con la razón", () => {
    const h = html(props({ bloqueadaPorOtra: true }));
    expect(botones(h)[0].deshabilitado).toBe(true);
    expect(h).toContain("Hay otra operación de esta jornada en curso o sin resolver");
  });

  it("otra jornada con carga sin resolver: deshabilitado", () => {
    const h = html(props({ fase: { fase: "desconocido", jornadaId: jornada(2).id, mensaje: "x", reintentable: true } }));
    expect(botones(h)[0].deshabilitado).toBe(true);
    expect(h).toContain("Hay una carga de otra jornada sin resolver");
  });

  it("la fase de OTRA jornada no abre el formulario en ésta", () => {
    const h = html(props({ fase: { fase: "confirmando", jornadaId: jornada(2).id } }));
    expect(h).not.toContain("<form");
  });
});

describe("formulario: productos por unidad y por peso", () => {
  it("una línea vacía: selector con sólo productos activos, cantidad deshabilitada hasta elegir", () => {
    const h = html(props({ fase: confirmando() }));
    expect(h).toContain("<form");
    expect(h).toContain("Camión: <span");
    const opciones = [...h.matchAll(/<option value="([^"]*)"/g)].map((m) => m[1]);
    expect(opciones).toEqual(["", JAMON, LECHE]);
    expect(h).not.toContain(VIEJO);
    expect(h).toMatch(/<input[^>]*disabled=""[^>]*id="carga-[^"]+-cantidad-0"|<input[^>]*id="carga-[^"]+-cantidad-0"[^>]*disabled=""/);
    expect(h).toContain("Elegí primero el producto.");
    expect(botones(h).map((b) => b.texto)).toEqual(["Quitar producto 1", "Agregar producto", "Revisar carga", "Cancelar"]);
    expect(h).not.toContain('role="alert"');
    auditarA11y(h);
  });

  it("unidad: teclado numérico y ayuda de enteros; peso: teclado decimal y kg con coma", () => {
    const h = html(props({ fase: confirmando(), edicion: edicion([[LECHE, "24"], [JAMON, "1,250"]]) }));
    expect(h).toMatch(/<label[^>]*for="carga-[^"]+-cantidad-0"[^>]*>Cantidad 1<\/label>/);
    expect(h).toMatch(/inputMode="numeric"[^>]*value="24"|value="24"[^>]*inputMode="numeric"/i);
    expect(h).toContain("Unidades enteras.");
    expect(h).toMatch(/<label[^>]*for="carga-[^"]+-cantidad-1"[^>]*>Peso en kg 2<\/label>/);
    expect(h).toMatch(/inputMode="decimal"/i);
    expect(h).toContain("Kilogramos con coma, hasta 3 decimales.");
    // Una línea no ofrece el producto elegido en la otra.
    const selects = [...h.matchAll(/<select[\s\S]*?<\/select>/g)].map((m) => m[0]);
    expect(selects[0]).not.toContain(`value="${JAMON}"`);
    expect(selects[1]).not.toContain(`value="${LECHE}"`);
    auditarA11y(h);
  });

  it("las interacciones devuelven la edición nueva (sin estado propio en el panel)", () => {
    const p = props({ fase: confirmando(), edicion: edicion([[LECHE, "24"]]) });
    click(boton(p, "Agregar producto"));
    expect(p.onEdicion).toHaveBeenLastCalledWith(expect.objectContaining({ lineas: [{ productoId: LECHE, texto: "24" }, { productoId: "", texto: "" }] }));
    (campo(p, `carga-${J.id}-cantidad-0`).props.onChange as (e: unknown) => void)({ target: { value: "30" } });
    expect(p.onEdicion).toHaveBeenLastCalledWith(expect.objectContaining({ lineas: [{ productoId: LECHE, texto: "30" }] }));
    (campo(p, `carga-${J.id}-producto-0`).props.onChange as (e: unknown) => void)({ target: { value: JAMON } });
    expect(p.onEdicion).toHaveBeenLastCalledWith(expect.objectContaining({ lineas: [{ productoId: JAMON, texto: "" }] }));
    click(boton(p, "Quitar producto 1"));
    expect(p.onEdicion).toHaveBeenLastCalledWith(expect.objectContaining({ lineas: [{ productoId: "", texto: "" }] }));
    click(boton(p, "Cancelar"));
    expect(p.onCancelar).toHaveBeenCalledTimes(1);
    expect(p.onConfirmar).not.toHaveBeenCalled();
  });

  it("«Revisar carga» no envía nada: sólo pide el resumen", () => {
    const p = props({ fase: confirmando(), edicion: edicion([[LECHE, "24"]]) });
    const form = arbol(p).find((e) => e.type === "form")!;
    (form.props.onSubmit as (e: unknown) => void)({ preventDefault: () => undefined });
    expect(p.onEdicion).toHaveBeenCalledWith({ lineas: [{ productoId: LECHE, texto: "24" }], revisando: true, mostrarErrores: true });
    expect(p.onConfirmar).not.toHaveBeenCalled();
  });
});

describe("validaciones visibles y accesibles", () => {
  it("antes de intentar revisar no se muestran errores", () => {
    const h = html(props({ fase: confirmando(), edicion: edicion([[JAMON, "1,2345"]]) }));
    expect(h).not.toContain('role="alert"');
    expect(h).not.toContain("aria-invalid");
  });

  it("tras intentar: alerta con el mensaje del controlador y la línea marcada como inválida", () => {
    const h = html(props({ fase: confirmando(), edicion: edicion([[LECHE, "2"], [JAMON, "1,2345"]], { mostrarErrores: true }) }));
    expect(h).toMatch(new RegExp(`role="alert"[^>]*>[\\s\\S]*${MENSAJE_CARGA_CANTIDAD_PESO(2).replace(/[()]/g, "\\$&")}`));
    expect(h).toMatch(/id="carga-[^"]+-cantidad-1"[^>]*aria-invalid="true"|aria-invalid="true"[^>]*id="carga-[^"]+-cantidad-1"/);
    expect(h).toMatch(/aria-describedby="carga-[^"]+-unidad-1 carga-[^"]+-error"/);
    expect(h).not.toMatch(/id="carga-[^"]+-cantidad-0"[^>]*aria-invalid/);
    expect(h).toContain("border-red-500");
    auditarA11y(h);
  });

  it("error de preparación del controlador (fase.error): se muestra en el formulario", () => {
    const h = html(props({ fase: confirmando("La jornada no tiene un camión válido."), edicion: edicion([[LECHE, "2"]]) }));
    expect(h).toMatch(/role="alert"[^>]*>[\s\S]*La jornada no tiene un camión válido\./);
    auditarA11y(h);
  });

  it("catálogo no disponible: alerta y sólo «Cancelar»", () => {
    const h = html(props({ fase: confirmando(), catalogo: null }));
    expect(h).toContain('role="alert"');
    expect(h).toContain("No se pudo leer el catálogo de productos");
    expect(botones(h).map((b) => b.texto)).toEqual(["Cancelar"]);
  });
});

describe("resumen antes de confirmar", () => {
  const enRevision = edicion([[LECHE, "24"], [JAMON, "3,250"]], { revisando: true, mostrarErrores: true });

  it("tabla con encabezados, unidades y kg con 3 decimales; confirmación explícita", () => {
    const h = html(props({ fase: confirmando(), edicion: enRevision }));
    expect(h).not.toContain("<form");
    expect(h).toContain("<caption");
    expect(h).toContain("(2 productos)");
    expect(h).toMatch(/<th scope="col"[^>]*>Producto<\/th>/);
    expect(h).toContain("Leche entera (L1)");
    expect(h).toContain("24 un.");
    expect(h).toContain("3,250 kg");
    expect(botones(h).map((b) => b.texto)).toEqual(["Confirmar carga", "Volver a editar", "Cancelar"]);
    auditarA11y(h);
  });

  it("«Confirmar carga» entrega exactamente lo revisado; «Volver a editar» no envía", () => {
    const p = props({ fase: confirmando(), edicion: enRevision });
    click(boton(p, "Volver a editar"));
    expect(p.onConfirmar).not.toHaveBeenCalled();
    expect(p.onEdicion).toHaveBeenCalledWith({ ...enRevision, revisando: false });
    click(boton(p, "Confirmar carga"));
    expect(p.onConfirmar).toHaveBeenCalledWith({
      lineas: [
        { productoId: LECHE, texto: "24" },
        { productoId: JAMON, texto: "3,250" },
      ],
    });
  });

  it("si lo revisado deja de ser válido (catálogo cambiado), vuelve al formulario con el error", () => {
    const sinJamon = CATALOGO.map((p) => (p.id === JAMON ? { ...p, activo: false } : p));
    const h = html(props({ fase: confirmando(), edicion: enRevision, catalogo: sinJamon }));
    expect(h).toContain("<form");
    expect(h).toContain("el producto está dado de baja");
  });
});

describe("estados de envío, error e incierto", () => {
  it.each(["enviando", "verificando"] as const)("%s: un solo botón deshabilitado y estado anunciado", (f) => {
    const h = html(props({ fase: { fase: f, jornadaId: J.id } }));
    const b = botones(h);
    expect(b).toHaveLength(1);
    expect(b[0].deshabilitado).toBe(true);
    expect(h).toContain('role="status"');
    expect(h).not.toContain("Confirmar carga");
    if (f === "enviando") expect(h).toContain("no cambies de sección");
  });

  it("incierta reintentable: alerta con el mensaje y «Reintentar la misma carga» / «Verificar estado»", () => {
    const p = props({ fase: { fase: "desconocido", jornadaId: J.id, mensaje: MENSAJE_CARGA_INCIERTA, reintentable: true } });
    const h = html(p);
    expect(h).toContain('role="alert"');
    expect(h).toContain("sin recargarla ni cambiar de sección");
    expect(botones(h).map((b) => b.texto)).toEqual(["Reintentar la misma carga", "Verificar estado"]);
    click(boton(p, "Reintentar la misma carga"));
    click(boton(p, "Verificar estado"));
    expect(p.onReintentar).toHaveBeenCalledTimes(1);
    expect(p.onVerificar).toHaveBeenCalledTimes(1);
    expect(p.onConfirmar).not.toHaveBeenCalled();
    expect(p.onSolicitar).not.toHaveBeenCalled();
    auditarA11y(h);
  });

  it("sin verificar: sólo «Verificar estado», sin nueva carga", () => {
    const h = html(props({ fase: { fase: "desconocido", jornadaId: J.id, mensaje: MENSAJE_CARGA_SIN_VERIFICAR, reintentable: false } }));
    expect(botones(h).map((b) => b.texto)).toEqual(["Verificar estado"]);
  });

  it("éxito sin relectura: no se ofrece nada ni se afirma que el stock cambió", () => {
    expect(html(props({ fase: { fase: "exito", jornadaId: J.id, mensaje: "ok" } }))).toBe("");
  });

  it("éxito con la lista releída: se puede iniciar OTRA carga (otra intención)", () => {
    const h = html(props({ fase: { fase: "exito", jornadaId: J.id, mensaje: "ok", releida: true } }));
    expect(botones(h)).toEqual([{ texto: "Cargar mercadería", deshabilitado: false }]);
  });

  it("error definitivo: vuelve el botón; el mensaje lo anuncia el aviso de la pantalla", () => {
    const h = html(props({ fase: { fase: "error", jornadaId: J.id, mensaje: "No hay stock suficiente." } }));
    expect(h).not.toContain('role="alert"');
    expect(botones(h)).toEqual([{ texto: "Cargar mercadería", deshabilitado: false }]);
  });
});

describe("responsive Android/PC", () => {
  it("una columna en móvil y grilla desde sm; botones a lo ancho que pasan a fila", () => {
    const h = html(props({ fase: confirmando(), edicion: edicion([[LECHE, "1"]]) }));
    expect(h).toContain("grid-cols-1");
    expect(h).toContain("sm:grid-cols-[minmax(0,1fr)_11rem_auto]");
    expect(h).toContain("flex-col gap-3 sm:flex-row");
    expect(h).toContain("text-base"); // evita el zoom automático de Android/iOS en campos
  });
});

describe("seguridad operativa del parche", () => {
  const sinComentarios = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");

  it("el panel no llama RPC, no genera claves ni usa almacenamiento del navegador", () => {
    expect(sinComentarios(fuentePanel)).not.toMatch(
      /localStorage|sessionStorage|indexedDB|\.rpc\(|registrar_carga|randomUUID|nuevaClaveIdempotencia|ejecutar|crearControladorCarga/
    );
  });

  it("FE-1D: Jornadas monta el panel sin confirmación ni controlador de carga", () => {
    const pantalla = sinComentarios(fuentePantalla);
    const elemento = pantalla.match(/<JornadaCargaPanel[\s\S]*?\/>/)?.[0] ?? "";
    expect(elemento).not.toBe("");
    expect(elemento).not.toMatch(/onConfirmar|onReintentar|onVerificar|puerto|ejecutar/);
    expect(pantalla).not.toMatch(/crearControladorCarga|definicionCarga|useCargaJornada|registrar_carga|\.rpc\(/);
    // App sólo aloja el borrador sobre el router; nunca el controlador.
    expect(sinComentarios(fuenteApp)).toMatch(/<BorradorCargaProvider>\s*<BrowserRouter>/);
    expect(sinComentarios(fuenteApp)).not.toMatch(/JornadaCargaPanel|jornadas_carga|ControladorCarga/);
  });
});

describe("FE-1D: modo borrador (sin onConfirmar)", () => {
  const enRevision = edicion([[LECHE, "24"], [JAMON, "3,250"]], { revisando: true, mostrarErrores: true });
  const borrador = (cambios: Partial<JornadaCargaPanelProps> = {}) => {
    const p = props({ fase: confirmando(), ...cambios });
    delete p.onConfirmar;
    delete p.onReintentar;
    delete p.onVerificar;
    return p;
  };

  it("resumen: «Confirmar carga» deshabilitado, SIN manejador y con el motivo asociado", () => {
    const p = borrador({ edicion: enRevision });
    const h = html(p);
    expect(botones(h)).toEqual([
      { texto: "Confirmar carga", deshabilitado: true },
      { texto: "Volver a editar", deshabilitado: false },
      { texto: "Cancelar", deshabilitado: false },
    ]);
    const b = boton(p, "Confirmar carga");
    expect(b.props.disabled).toBe(true);
    expect(b.props.onClick).toBeUndefined();
    expect(h).toMatch(/aria-describedby="carga-[^"]+-deshabilitada"/);
    expect(h).toContain(MENSAJE_CONFIRMACION_DESHABILITADA);
    expect(h).toContain(MENSAJE_BORRADOR_VOLATIL);
    auditarA11y(h);
  });

  it("formulario: el aviso de confirmación deshabilitada se ve desde el inicio", () => {
    const h = html(borrador({ edicion: edicion([[LECHE, "1"]]) }));
    expect(h).toContain("<form");
    expect(h).toContain(MENSAJE_CONFIRMACION_DESHABILITADA);
    auditarA11y(h);
  });

  it("con onConfirmar (modo controlador) no se muestra el aviso", () => {
    expect(html(props({ fase: confirmando(), edicion: enRevision }))).not.toContain(MENSAJE_CONFIRMACION_DESHABILITADA);
  });

  it("catálogo leyéndose: estado anunciado y sólo «Cancelar»", () => {
    const h = html(borrador({ catalogo: "cargando" }));
    expect(h).toContain('role="status"');
    expect(h).toContain("Leyendo el catálogo de productos");
    expect(botones(h).map((b) => b.texto)).toEqual(["Cancelar"]);
    auditarA11y(h);
  });

  it("incierta sin manejadores: no ofrece reintentar ni verificar", () => {
    const p = borrador({ fase: { fase: "desconocido", jornadaId: J.id, mensaje: "m", reintentable: true } });
    expect(botones(html(p))).toEqual([]);
  });
});
