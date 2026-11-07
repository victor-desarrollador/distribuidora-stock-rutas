import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import type { EstadoJornada, Jornada } from "../lib/jornadas";
import { JornadaSalidaPanel } from "./JornadaSalidaPanel";
import type { FaseSalida } from "./jornadas_salida";

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

const noop = () => undefined;
const panel = (j: Jornada, fase: FaseSalida = { fase: "inactiva" }, bloqueadaPorOtra?: boolean) =>
  renderToStaticMarkup(
    <JornadaSalidaPanel
      jornada={j}
      fase={fase}
      bloqueadaPorOtra={bloqueadaPorOtra}
      nombreCamion="Camión Norte · AB123CD"
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

describe("JornadaSalidaPanel", () => {
  it("jornada cargada: «Confirmar salida» habilitado, táctil (min-h-12)", () => {
    const html = panel(jornada(1));
    expect(botones(html)).toEqual([{ texto: "Confirmar salida", deshabilitado: false }]);
    expect(html).toContain("min-h-12");
  });

  it.each<EstadoJornada>(["abierta", "en_reparto", "cerrada"])(
    "jornada %s: botón deshabilitado con la razón asociada (aria-describedby)",
    (estado) => {
      const html = panel(jornada(1, estado));
      expect(botones(html)).toEqual([{ texto: "Confirmar salida", deshabilitado: true }]);
      expect(html).toMatch(/aria-describedby="salida-ayuda-[^"]+"/);
      expect(html).toContain("Sólo se puede confirmar la salida de una jornada cargada");
    }
  );

  it("confirmando: pregunta explícita con el camión, confirmar y cancelar", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "confirmando", jornadaId: j.id });
    expect(html).toContain('role="group"');
    expect(html).toContain("¿Confirmás la salida de Camión Norte · AB123CD?");
    expect(botones(html).map((b) => b.texto)).toEqual(["Sí, confirmar salida", "Cancelar"]);
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

  it("resultado desconocido verificado: alerta con «Reintentar confirmación» y «Verificar estado»", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "desconocido", jornadaId: j.id, mensaje: "sigue cargada", reintentable: true });
    expect(html).toContain('role="alert"');
    expect(botones(html).map((b) => b.texto)).toEqual(["Reintentar confirmación", "Verificar estado"]);
  });

  it("resultado desconocido sin verificar: sólo «Verificar estado» (sin reintento a ciegas)", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "desconocido", jornadaId: j.id, mensaje: "no se pudo leer", reintentable: false });
    expect(botones(html).map((b) => b.texto)).toEqual(["Verificar estado"]);
  });

  // S1-C5: el resultado lo anuncia AvisoSalidaJornada (fuera del detalle);
  // el panel, en éxito, no ofrece ninguna acción.
  it("éxito: el panel no ofrece ninguna acción (el anuncio está fuera del detalle)", () => {
    const j = jornada(1, "en_reparto");
    const html = panel(j, { fase: "exito", jornadaId: j.id, mensaje: "Salida confirmada." });
    expect(botones(html)).toHaveLength(0);
    expect(html).toBe("");
  });

  // Regresión S1-C1 (Codex, revisión 1): tras el éxito no se ofrece una
  // segunda confirmación aunque la relectura todavía no haya llegado.
  it("éxito con la jornada local todavía «cargada»: sin ningún botón de acción", () => {
    const j = jornada(1, "cargada");
    const html = panel(j, { fase: "exito", jornadaId: j.id, mensaje: "Salida confirmada." });
    expect(botones(html)).toHaveLength(0);
  });

  // Regresión S1-C2: otra jornada con resultado desconocido bloquea iniciar una nueva.
  it.each([true, false])(
    "otra jornada con resultado desconocido (reintentable=%s): «Confirmar salida» deshabilitado con la razón",
    (reintentable) => {
      const html = panel(jornada(1), {
        fase: "desconocido", jornadaId: jornada(2).id, mensaje: "x", reintentable,
      });
      expect(botones(html)).toEqual([{ texto: "Confirmar salida", deshabilitado: true }]);
      expect(html).toMatch(/aria-describedby="salida-ayuda-[^"]+"/);
      expect(html).toContain("Hay una confirmación de salida de otra jornada sin resolver");
      expect(html).not.toContain('role="alert"'); // la alerta se muestra sólo en la jornada afectada
    }
  );

  it("error definitivo: si sigue cargada, una nueva confirmación posible (el mensaje lo anuncia AvisoSalidaJornada)", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "error", jornadaId: j.id, mensaje: "El camión no tiene carga neta" });
    expect(html).not.toContain('role="alert"');
    expect(botones(html)).toEqual([{ texto: "Confirmar salida", deshabilitado: false }]);
  });

  it("la fase de OTRA jornada no se aplica a ésta", () => {
    const html = panel(jornada(1), { fase: "enviando", jornadaId: jornada(2).id });
    expect(botones(html)).toEqual([{ texto: "Confirmar salida", deshabilitado: false }]);
    expect(html).not.toContain('role="status"');
  });

  it("no hay formularios ni botones de envío", () => {
    const j = jornada(1);
    const html = panel(j, { fase: "confirmando", jornadaId: j.id });
    expect(html).not.toContain("<form");
    expect(html).not.toContain('type="submit"');
  });

  it("S2 M-02: con la jornada retenida por una corrección, «Confirmar salida» deshabilitado con la razón", () => {
    const html = panel(jornada(1, "cargada"), { fase: "inactiva" }, true);
    expect(botones(html)).toEqual([{ texto: "Confirmar salida", deshabilitado: true }]);
    expect(html).toMatch(/aria-describedby="salida-ayuda-[^"]+"/);
    expect(html).toContain("Hay una corrección de esta jornada en curso o sin resolver");
  });

  it("S2 M-02: la fase propia (resultado desconocido) se muestra aunque la otra operación figure retenida", () => {
    const j = jornada(1, "cargada");
    const html = panel(j, { fase: "desconocido", jornadaId: j.id, mensaje: "x", reintentable: true }, true);
    expect(botones(html).map((b) => b.texto)).toEqual(["Reintentar confirmación", "Verificar estado"]);
  });
});
