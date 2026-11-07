import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import type { CamionCatalogo } from "../lib/camiones";
import type { EstadoJornada, Jornada } from "../lib/jornadas";
import { JornadaCorreccionPanel } from "./JornadaCorreccionPanel";
import type { FaseCorreccion } from "./jornadas_correccion";

const CAMION_A = "22222222-2222-4222-8222-222222222222";
const CAMION_B = "44444444-4444-4444-8444-444444444444";
const CAMION_INACTIVO = "55555555-5555-4555-8555-555555555555";

function jornada(n: number, estado: EstadoJornada = "abierta"): Jornada {
  return {
    id: `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`,
    fecha: "2026-11-10",
    camionId: CAMION_A,
    vendedorId: "33333333-3333-4333-8333-333333333333",
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
  };
}

const ACTIVOS: CamionCatalogo[] = [
  { id: CAMION_A, nombre: "Camión Norte", patente: "AB123CD", activo: true },
  { id: CAMION_B, nombre: "Camión Sur", patente: "EF456GH", activo: true },
];

const noop = () => undefined;
const panel = (
  j: Jornada,
  fase: FaseCorreccion = { fase: "inactiva" },
  camionesActivos: CamionCatalogo[] | null = ACTIVOS,
  bloqueadaPorOtra?: boolean
) =>
  renderToStaticMarkup(
    <JornadaCorreccionPanel
      jornada={j}
      fase={fase}
      bloqueadaPorOtra={bloqueadaPorOtra}
      camionesActivos={camionesActivos}
      nombreCamion={(id) => (id === CAMION_A ? "Camión Norte · AB123CD" : `Camión ${id.slice(0, 8)}`)}
      hoy="2026-11-10"
      onSolicitar={noop}
      onCancelar={noop}
      onConfirmar={noop}
      onReintentar={noop}
      onVerificar={noop}
    />
  );

function botones(html: string) {
  return [...html.matchAll(/<button([^>]*)>([\s\S]*?)<\/button>/g)].map((m) => ({
    texto: m[2].replace(/<[^>]+>/g, "").trim(),
    deshabilitado: /\sdisabled(=|\s|>|$)/.test(m[1]),
  }));
}

describe("JornadaCorreccionPanel", () => {
  it("jornada abierta: «Corregir jornada» habilitado y táctil (min-h-12)", () => {
    const html = panel(jornada(1));
    expect(botones(html)).toEqual([{ texto: "Corregir jornada", deshabilitado: false }]);
    expect(html).toContain("min-h-12");
  });

  it.each<EstadoJornada>(["cargada", "en_reparto", "ventas_finalizadas", "regreso_contado", "cerrada"])(
    "jornada %s: botón deshabilitado con la razón asociada (aria-describedby)",
    (estado) => {
      const html = panel(jornada(1, estado));
      expect(botones(html)).toEqual([{ texto: "Corregir jornada", deshabilitado: true }]);
      expect(html).toMatch(/aria-describedby="correccion-ayuda-[^"]+"/);
      expect(html).toContain("Sólo se puede corregir una jornada abierta");
    }
  );

  it("formulario: fecha (mínimo hoy en Tucumán), camión y motivo con etiquetas; registrar y cancelar", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "confirmando", jornadaId: j.id });
    expect(html).toContain("<form");
    expect(html).toMatch(/<label[^>]*for="correccion-[^"]+-fecha"[^>]*>Fecha<\/label>/);
    expect(html).toMatch(/<input[^>]*type="date"[^>]*min="2026-11-10"[^>]*value="2026-11-10"/);
    expect(html).toMatch(/<label[^>]*for="correccion-[^"]+-camion"[^>]*>Camión<\/label>/);
    expect(html).toMatch(/<label[^>]*for="correccion-[^"]+-motivo"[^>]*>Motivo<\/label>/);
    expect(botones(html).map((b) => b.texto)).toEqual(["Registrar corrección", "Cancelar"]);
    expect(html).not.toContain('role="alert"');
  });

  it("selector de camión: el actual primero y después sólo los activos (sin repetir el actual)", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "confirmando", jornadaId: j.id });
    const opciones = [...html.matchAll(/<option value="([^"]+)"[^>]*>([\s\S]*?)<\/option>/g)].map((m) => m[1]);
    expect(opciones).toEqual([CAMION_A, CAMION_B]);
    expect(html).toContain("Camión Norte · AB123CD (actual)");
    expect(html).not.toContain(CAMION_INACTIVO);
  });

  it("catálogo no disponible: sólo el camión actual y un aviso", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "confirmando", jornadaId: j.id }, null);
    const opciones = [...html.matchAll(/<option value="([^"]+)"/g)].map((m) => m[1]);
    expect(opciones).toEqual([CAMION_A]);
    expect(html).toContain("No se pudo leer el catálogo de camiones");
  });

  it("error de validación: alerta dentro del formulario, asociada al motivo", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "confirmando", jornadaId: j.id, error: "El motivo es obligatorio." });
    expect(html).toMatch(/role="alert"[^>]*>[\s\S]*El motivo es obligatorio\./);
    expect(html).toMatch(/aria-describedby="correccion-[^"]+-error"/);
  });

  it("enviando y verificando: un único botón deshabilitado y un estado anunciado", () => {
    const j = jornada(1);
    for (const fase of ["enviando", "verificando"] as const) {
      const html = panel(j, { fase, jornadaId: j.id });
      const b = botones(html);
      expect(b).toHaveLength(1);
      expect(b[0].deshabilitado).toBe(true);
      expect(html).toContain('role="status"');
    }
  });

  it("resultado desconocido verificado: «Reintentar corrección» y «Verificar estado»", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "desconocido", jornadaId: j.id, mensaje: "sigue igual", reintentable: true });
    expect(html).toContain('role="alert"');
    expect(botones(html).map((b) => b.texto)).toEqual(["Reintentar corrección", "Verificar estado"]);
  });

  it("resultado desconocido sin verificar: sólo «Verificar estado»", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "desconocido", jornadaId: j.id, mensaje: "x", reintentable: false });
    expect(botones(html).map((b) => b.texto)).toEqual(["Verificar estado"]);
  });

  it("éxito: ninguna acción mientras llega la relectura", () => {
    const j = jornada(1);
    expect(panel(j, { fase: "exito", jornadaId: j.id, mensaje: "ok" })).toBe("");
  });

  it("M-03: éxito con la lista ya releída: vuelve a ofrecer «Corregir jornada» (nueva intención)", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "exito", jornadaId: j.id, mensaje: "ok", releida: true });
    expect(botones(html)).toEqual([{ texto: "Corregir jornada", deshabilitado: false }]);
  });

  it("M-02: con la jornada retenida por la salida, «Corregir jornada» deshabilitado con la razón", () => {
    for (const fase of [{ fase: "inactiva" }, { fase: "exito", jornadaId: jornada(1).id, mensaje: "ok", releida: true }] as FaseCorreccion[]) {
      const html = panel(jornada(1), fase, ACTIVOS, true);
      expect(botones(html)).toEqual([{ texto: "Corregir jornada", deshabilitado: true }]);
      expect(html).toMatch(/aria-describedby="correccion-ayuda-[^"]+"/);
      expect(html).toContain("Hay una confirmación de salida de esta jornada en curso o sin resolver");
    }
  });

  it("M-02: la fase propia (resultado desconocido) se muestra aunque la salida figure retenida", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "desconocido", jornadaId: j.id, mensaje: "x", reintentable: true }, ACTIVOS, true);
    expect(botones(html).map((b) => b.texto)).toEqual(["Reintentar corrección", "Verificar estado"]);
  });

  it.each([true, false])(
    "otra jornada con resultado desconocido (reintentable=%s): deshabilitado con la razón",
    (reintentable) => {
      const html = panel(jornada(1), { fase: "desconocido", jornadaId: jornada(2).id, mensaje: "x", reintentable });
      expect(botones(html)).toEqual([{ texto: "Corregir jornada", deshabilitado: true }]);
      expect(html).toContain("Hay una corrección de otra jornada sin resolver");
      expect(html).not.toContain('role="alert"');
    }
  );

  it("error definitivo: el panel vuelve a ofrecer la corrección (el mensaje lo anuncia el aviso)", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "error", jornadaId: j.id, mensaje: "Ese camión ya tiene una jornada en esa fecha." });
    expect(html).not.toContain('role="alert"');
    expect(botones(html)).toEqual([{ texto: "Corregir jornada", deshabilitado: false }]);
  });

  it("la fase de OTRA jornada no se aplica a ésta", () => {
    const html = panel(jornada(1), { fase: "confirmando", jornadaId: jornada(2).id });
    expect(html).not.toContain("<form");
    expect(botones(html)).toEqual([{ texto: "Corregir jornada", deshabilitado: false }]);
  });
});
