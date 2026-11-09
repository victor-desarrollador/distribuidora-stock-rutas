import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import type { CamionCatalogo } from "../lib/camiones";
import { JornadaAperturaPanel } from "./JornadaAperturaPanel";
import {
  MENSAJE_APERTURA_DESCONOCIDA,
  MENSAJE_APERTURA_OK,
  MENSAJE_RECUPERACION_DUPLICADA,
  MENSAJE_RECUPERACION_NO_CONFIRMA,
  MENSAJE_RECUPERACION_VENDEDOR_OCUPADO,
  MENSAJE_RIESGO_RECARGA,
  type EntradaApertura,
  type EstadoVendedores,
  type FaseApertura,
} from "./jornadas_apertura";

const CAMION_A = "22222222-2222-4222-8222-222222222222";
const CAMION_B = "44444444-4444-4444-8444-444444444444";
const VENDEDOR = "33333333-3333-4333-8333-333333333333";
const DUENO = "55555555-5555-4555-8555-555555555555";
const JORNADA = "00000000-0000-4000-8000-000000000001";
const HOY = "2026-11-10";

const ACTIVOS: CamionCatalogo[] = [
  { id: CAMION_A, nombre: "Camión Norte", patente: "AB123CD", activo: true },
  { id: CAMION_B, nombre: "Camión Sur", patente: "EF456GH", activo: true },
];
const LISTA: EstadoVendedores = {
  estado: "listo",
  vendedores: [
    { usuarioId: VENDEDOR, nombre: "Ana Pérez", rol: "vendedor_piloto" },
    { usuarioId: DUENO, nombre: "Bruno Gómez", rol: "dueno" },
  ],
};
const DATOS: EntradaApertura = { camionId: CAMION_A, fecha: "2026-11-12", vendedorId: VENDEDOR };

const noop = () => undefined;
function panel(
  fase: FaseApertura,
  vendedores: EstadoVendedores = LISTA,
  camionesActivos: CamionCatalogo[] | null = ACTIVOS
) {
  return renderToStaticMarkup(
    <JornadaAperturaPanel
      fase={fase}
      camionesActivos={camionesActivos}
      vendedores={vendedores}
      hoy={HOY}
      nombreCamion={(id) => (id === CAMION_A ? "Camión Norte · AB123CD" : `Camión ${id.slice(0, 8)}`)}
      onSolicitar={noop}
      onCancelar={noop}
      onConfirmar={noop}
      onReintentar={noop}
      onRecargarVendedores={noop}
      onVerFecha={noop}
    />
  );
}

function botones(html: string) {
  return [...html.matchAll(/<button([^>]*)>([\s\S]*?)<\/button>/g)].map((m) => ({
    texto: m[2].replace(/<[^>]+>/g, "").trim(),
    deshabilitado: /\sdisabled(=|\s|>|$)/.test(m[1]),
  }));
}
const boton = (html: string, texto: string) => botones(html).find((b) => b.texto === texto);
const opciones = (html: string, id: string) => {
  const select = new RegExp(`<select[^>]*id="${id}"[^>]*>([\\s\\S]*?)</select>`).exec(html)?.[1] ?? "";
  return [...select.matchAll(/<option value="([^"]*)"[^>]*>([\s\S]*?)<\/option>/g)].map((m) => ({
    valor: m[1],
    texto: m[2].replace(/<!-- -->/g, ""),
  }));
};

describe("JornadaAperturaPanel: reposo", () => {
  it("ofrece «Nueva jornada» habilitada, sin formulario", () => {
    const html = panel({ fase: "inactiva" });
    expect(boton(html, "Nueva jornada")).toEqual({ texto: "Nueva jornada", deshabilitado: false });
    expect(html).not.toContain("<form");
  });

  it("la región de estado está siempre montada", () => {
    expect(panel({ fase: "inactiva" })).toContain('role="status"');
    expect(panel({ fase: "editando" })).toContain('role="status"');
  });
});

describe("JornadaAperturaPanel: formulario", () => {
  it("camiones activos, fecha desde hoy y vendedores de la lista real con su rol", () => {
    const html = panel({ fase: "editando" });
    expect(html).toContain("<form");
    expect(opciones(html, "apertura-camion")).toEqual([
      { valor: "", texto: "Elegí un camión" },
      { valor: CAMION_A, texto: "Camión Norte · AB123CD" },
      { valor: CAMION_B, texto: "Camión Sur · EF456GH" },
    ]);
    expect(opciones(html, "apertura-vendedor")).toEqual([
      { valor: "", texto: "Elegí un vendedor" },
      { valor: VENDEDOR, texto: "Ana Pérez — Vendedor/Piloto" },
      { valor: DUENO, texto: "Bruno Gómez — Dueño" },
    ]);
    expect(html).toMatch(/<input[^>]*type="date"[^>]*min="2026-11-10"[^>]*value="2026-11-10"/);
    expect(boton(html, "Abrir jornada")?.deshabilitado).toBe(false);
    expect(boton(html, "Cancelar")).toBeDefined();
  });

  it("no hay campo de texto para un uuid ni opción de autoasignación", () => {
    const html = panel({ fase: "editando" });
    expect([...html.matchAll(/<input/g)]).toHaveLength(1);
    expect(html).not.toContain("<textarea");
    expect(html).not.toMatch(/Asignarme|>Yo</);
  });

  it.each<[string, EstadoVendedores, string]>([
    ["inactiva", { estado: "inactivo" }, "Cargando vendedores…"],
    ["cargando", { estado: "cargando" }, "Cargando vendedores…"],
    ["vacía", { estado: "listo", vendedores: [] }, "No hay perfiles activos de la empresa para asignar."],
  ])("lista de vendedores %s: no se puede enviar", (_d, vendedores, ayuda) => {
    const html = panel({ fase: "editando" }, vendedores);
    expect(html).toContain(ayuda);
    expect(boton(html, "Abrir jornada")?.deshabilitado).toBe(true);
    expect(opciones(html, "apertura-vendedor")).toEqual([{ valor: "", texto: "Elegí un vendedor" }]);
  });

  it("error de la lista: alerta, reintento de lectura y envío bloqueado", () => {
    const html = panel({ fase: "editando" }, { estado: "error", mensaje: "No tenés permiso para ver los vendedores de la empresa." });
    expect(html).toMatch(/role="alert"[^>]*>No tenés permiso para ver los vendedores/);
    expect(boton(html, "Reintentar lectura de vendedores")?.deshabilitado).toBe(false);
    expect(boton(html, "Abrir jornada")?.deshabilitado).toBe(true);
  });

  it("sin catálogo de camiones o sin activos: no se puede enviar", () => {
    const sinCatalogo = panel({ fase: "editando" }, LISTA, null);
    expect(sinCatalogo).toContain("La lista de camiones activos no está disponible");
    expect(boton(sinCatalogo, "Abrir jornada")?.deshabilitado).toBe(true);
    const sinActivos = panel({ fase: "editando" }, LISTA, []);
    expect(sinActivos).toContain("No hay camiones activos para asignar.");
    expect(boton(sinActivos, "Abrir jornada")?.deshabilitado).toBe(true);
  });

  it("muestra el error de validación local", () => {
    const html = panel({ fase: "editando", error: "Elegí un vendedor de la lista." });
    expect(html).toMatch(/role="alert"[\s\S]*Elegí un vendedor de la lista\./);
  });

  it("tras un rechazo del servidor el formulario sigue abierto con el mensaje", () => {
    const html = panel({ fase: "error", mensaje: "El vendedor ya tiene una jornada en esa fecha." });
    expect(html).toContain("<form");
    expect(html).toMatch(/role="alert"[\s\S]*El vendedor ya tiene una jornada en esa fecha\./);
    expect(boton(html, "Abrir jornada")?.deshabilitado).toBe(false);
  });
});

describe("JornadaAperturaPanel: envío y respuesta", () => {
  it("enviando: botón deshabilitado, aviso de no recargar y resumen", () => {
    const html = panel({ fase: "enviando", datos: DATOS });
    expect(boton(html, "Abriendo jornada…")?.deshabilitado).toBe(true);
    expect(html).toContain("No cierres ni recargues la pantalla.");
    expect(html).toContain("Camión Norte · AB123CD");
    expect(html).toContain("12/11/2026");
    expect(html).toContain("Ana Pérez (Vendedor/Piloto)");
    expect(html).not.toContain("<form");
  });

  it("verificando: la lectura es sólo informativa", () => {
    const html = panel({ fase: "verificando", datos: DATOS });
    expect(boton(html, "Consultando la lista…")?.deshabilitado).toBe(true);
    expect(html).toContain("sólo para informarte");
  });

  it("desconocido: alerta, información que no confirma y reintento; nunca éxito", () => {
    const html = panel({
      fase: "desconocido",
      datos: DATOS,
      mensaje: MENSAJE_APERTURA_DESCONOCIDA,
      informacion: "En la lista actual hay una jornada abierta de ese camión en esa fecha con el vendedor elegido.",
    });
    expect(html).toMatch(/role="alert"/);
    expect(html).toContain(MENSAJE_APERTURA_DESCONOCIDA);
    expect(html).toContain("Información (no confirma el resultado):");
    expect(boton(html, "Reintentar apertura")?.deshabilitado).toBe(false);
    expect(html).not.toContain(MENSAJE_APERTURA_OK);
    expect(boton(html, "Nueva jornada")).toBeUndefined();
    expect(html).not.toContain("<form");
  });

  it("desconocido sin información: no muestra el bloque informativo", () => {
    const html = panel({ fase: "desconocido", datos: DATOS, mensaje: MENSAJE_APERTURA_DESCONOCIDA, informacion: null });
    expect(html).not.toContain("Información (no confirma");
  });

  it("éxito: anuncia la jornada devuelta y ofrece ver su fecha; «Nueva jornada» recién tras releer", () => {
    const exito: FaseApertura = { fase: "exito", jornadaId: JORNADA, datos: DATOS, mensaje: MENSAJE_APERTURA_OK };
    const html = panel(exito);
    expect(html).toMatch(/role="status"[^>]*>Jornada abierta\./);
    expect(html).toContain("Ana Pérez (Vendedor/Piloto)");
    expect(boton(html, "Ver jornadas del 12/11/2026")?.deshabilitado).toBe(false);
    expect(boton(html, "Nueva jornada")).toBeUndefined();
    expect(boton(panel({ ...exito, releida: true }), "Nueva jornada")?.deshabilitado).toBe(false);
  });

  it("si el vendedor ya no figura en la lista, el resumen usa un id corto (nunca un nombre inventado)", () => {
    const html = panel({ fase: "enviando", datos: DATOS }, { estado: "listo", vendedores: [] });
    expect(html).toContain("Vendedor 33333333");
  });
});

describe("JornadaAperturaPanel: T-1 advertencia de recarga", () => {
  it("en `desconocido` advierte que recargar pierde el reintento seguro, sin prometer el aviso del navegador", () => {
    const html = panel({ fase: "desconocido", datos: DATOS, mensaje: MENSAJE_APERTURA_DESCONOCIDA, informacion: null });
    expect(html).toContain(MENSAJE_RIESGO_RECARGA);
  });

  it("en reposo, formulario, envío y éxito no muestra esa advertencia", () => {
    for (const f of [
      { fase: "inactiva" },
      { fase: "editando" },
      { fase: "enviando", datos: DATOS },
      { fase: "exito", jornadaId: JORNADA, datos: DATOS, mensaje: MENSAJE_APERTURA_OK },
    ] as FaseApertura[]) {
      expect(panel(f)).not.toContain(MENSAJE_RIESGO_RECARGA);
    }
  });
});

describe("JornadaAperturaPanel: T-2 orientación ante una posible apertura anterior", () => {
  it.each([
    ["jornada_duplicada", "Ese camión ya tiene una jornada en esa fecha.", MENSAJE_RECUPERACION_DUPLICADA],
    ["jornada_vendedor_ocupado", "El vendedor ya tiene una jornada en esa fecha.", MENSAJE_RECUPERACION_VENDEDOR_OCUPADO],
  ])("%s: mensaje del servidor, orientación, aclaración y acción para ver la fecha", (_c, mensaje, orientacion) => {
    const html = panel({ fase: "error", mensaje, recuperacion: { fecha: "2026-11-12", mensaje: orientacion } });
    expect(html).toContain("<form");
    expect(html).toContain(mensaje);
    expect(html).toContain(orientacion);
    expect(html).toContain(MENSAJE_RECUPERACION_NO_CONFIRMA);
    expect(boton(html, "Ver jornadas del 12/11/2026")?.deshabilitado).toBe(false);
    // Sigue siendo un error: no hay anuncio de éxito ni se ofrece «Nueva jornada».
    expect(html).not.toContain(MENSAJE_APERTURA_OK);
    expect(boton(html, "Abrir jornada")?.deshabilitado).toBe(false);
  });

  it("sin orientación (otros rechazos) no ofrece la acción ni la aclaración", () => {
    const html = panel({ fase: "error", mensaje: "El camión tiene otra jornada sin cerrar." });
    expect(html).not.toContain(MENSAJE_RECUPERACION_NO_CONFIRMA);
    expect(botones(html).some((b) => b.texto.startsWith("Ver jornadas del"))).toBe(false);
  });
});
