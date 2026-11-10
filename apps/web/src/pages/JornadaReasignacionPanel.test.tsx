import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

import type { EstadoJornada, Jornada } from "../lib/jornadas";
import type { EstadoVendedores } from "./jornadas_apertura";
import {
  ConfirmacionReasignacion,
  JornadaReasignacionPanel,
  MOTIVO_BLOQUEO_REASIGNACION_POR_DEFECTO,
} from "./JornadaReasignacionPanel";
import { MENSAJE_MISMO_VENDEDOR, type FaseReasignacion } from "./jornadas_reasignacion";

const ACTUAL = "33333333-3333-4333-8333-333333333333";
const ANA = "44444444-4444-4444-8444-444444444444";
const BETO = "55555555-5555-4555-8555-555555555555";

function jornada(n: number, estado: EstadoJornada = "abierta"): Jornada {
  return {
    id: `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`,
    fecha: "2026-11-10",
    camionId: "22222222-2222-4222-8222-222222222222",
    vendedorId: ACTUAL,
    estado,
    abiertaPor: "66666666-6666-4666-8666-666666666666",
    operacionAperturaId: "77777777-7777-4777-8777-777777777777",
    creadoEn: "2026-11-10T08:00:00+00:00",
  };
}

const LISTA: EstadoVendedores = {
  estado: "listo",
  vendedores: [
    { usuarioId: ANA, nombre: "Ana Gómez", rol: "vendedor_piloto" },
    { usuarioId: ACTUAL, nombre: "Juan Pérez", rol: "encargado" },
    { usuarioId: BETO, nombre: "Beto Ruiz", rol: "dueno" },
  ],
};

const noop = () => undefined;
function panel(
  j: Jornada,
  fase: FaseReasignacion = { fase: "inactiva" },
  vendedores: EstadoVendedores = LISTA,
  extra: { bloqueadaPorOtra?: boolean; motivoBloqueo?: string } = {}
) {
  return renderToStaticMarkup(
    <JornadaReasignacionPanel
      jornada={j}
      fase={fase}
      vendedores={vendedores}
      {...extra}
      onSolicitar={noop}
      onCancelar={noop}
      onConfirmar={noop}
      onReintentar={noop}
      onVerificar={noop}
      onRecargarVendedores={noop}
    />
  );
}

function botones(html: string) {
  return [...html.matchAll(/<button([^>]*)>([\s\S]*?)<\/button>/g)].map((m) => ({
    texto: m[2].replace(/<[^>]+>/g, "").trim(),
    deshabilitado: /\sdisabled(=|\s|>|$)/.test(m[1]),
  }));
}

const J = jornada(1);
const confirmando: FaseReasignacion = { fase: "confirmando", jornadaId: J.id };

describe("panel de reasignación: estados de la jornada", () => {
  it("abierta y cargada ofrecen «Cambiar vendedor» habilitado", () => {
    for (const e of ["abierta", "cargada"] as const) {
      expect(botones(panel(jornada(1, e)))).toEqual([{ texto: "Cambiar vendedor", deshabilitado: false }]);
    }
  });

  it("en_reparto (salida confirmada) y posteriores: no se ofrece", () => {
    for (const e of ["en_reparto", "ventas_finalizadas", "regreso_contado", "cerrada"] as const) {
      expect(panel(jornada(1, e))).toBe("");
    }
  });
});

describe("panel de reasignación: formulario", () => {
  it("muestra el vendedor actual y ofrece sólo a los OTROS vendedores de la lista", () => {
    const html = panel(J, confirmando);
    expect(html).toContain("Vendedor actual: <strong>Juan Pérez (");
    expect(html).toContain(`value="${ANA}"`);
    expect(html).toContain(`value="${BETO}"`);
    expect(html).not.toContain(`value="${ACTUAL}"`);
    // No hay campo libre para escribir un uuid.
    expect(html).not.toMatch(/<input/);
  });

  it("sin vendedor elegido «Revisar cambio» está deshabilitado: nada se envía sin elegir y revisar", () => {
    const b = botones(panel(J, confirmando));
    expect(b).toContainEqual({ texto: "Revisar cambio", deshabilitado: true });
    expect(b).toContainEqual({ texto: "Cancelar", deshabilitado: false });
    expect(b.map((x) => x.texto)).not.toContain("Confirmar cambio");
  });

  it("cargando la lista: lo informa y no hay candidatos", () => {
    const html = panel(J, confirmando, { estado: "cargando" });
    expect(html).toContain("Leyendo la lista de vendedores");
    expect(html).not.toContain(`value="${ANA}"`);
  });

  it("error de permisos u otro error al leer la lista: alerta y reintento de lectura, sin poder confirmar", () => {
    const html = panel(J, confirmando, { estado: "error", mensaje: "No tenés permiso para ver los vendedores de la empresa." });
    expect(html).toMatch(/role="alert"[^>]*>No tenés permiso/);
    const b = botones(html);
    expect(b).toContainEqual({ texto: "Reintentar lectura de vendedores", deshabilitado: false });
    expect(b).toContainEqual({ texto: "Revisar cambio", deshabilitado: true });
  });

  it("sólo el vendedor actual en la lista: lo dice y no permite revisar", () => {
    const html = panel(J, confirmando, {
      estado: "listo",
      vendedores: [{ usuarioId: ACTUAL, nombre: "Juan Pérez", rol: "encargado" }],
    });
    expect(html).toContain("No hay otro vendedor activo para asignar.");
    expect(botones(html)).toContainEqual({ texto: "Revisar cambio", deshabilitado: true });
  });

  it("muestra el error de validación (mismo vendedor) como alerta", () => {
    const html = panel(J, { ...confirmando, error: MENSAJE_MISMO_VENDEDOR });
    expect(html).toContain(MENSAJE_MISMO_VENDEDOR);
    expect(html).toContain('role="alert"');
  });
});

describe("panel de reasignación: confirmación explícita", () => {
  it("resume el cambio y sólo «Confirmar cambio» envía", () => {
    const onConfirmar = vi.fn();
    const onVolver = vi.fn();
    const html = renderToStaticMarkup(
      <ConfirmacionReasignacion
        jornada={J}
        actual="Juan Pérez (Encargado)"
        nuevo="Ana Gómez (Vendedor/piloto)"
        onConfirmar={onConfirmar}
        onVolver={onVolver}
      />
    );
    expect(html).toContain("Confirmá el cambio de vendedor");
    expect(html).toContain("10/11/2026");
    expect(html).toContain("<strong>Juan Pérez (Encargado)</strong> a <strong>Ana Gómez (Vendedor/piloto)</strong>");
    expect(botones(html).map((b) => b.texto)).toEqual(["Confirmar cambio", "Volver"]);
    expect(onConfirmar).not.toHaveBeenCalled();
  });
});

describe("panel de reasignación: envío y resultado", () => {
  it("enviando: botón deshabilitado y estado accesible", () => {
    const html = panel(J, { fase: "enviando", jornadaId: J.id });
    expect(botones(html)).toEqual([{ texto: "Cambiando vendedor…", deshabilitado: true }]);
    expect(html).toContain('role="status"');
  });

  it("verificando: consulta el estado real", () => {
    const html = panel(J, { fase: "verificando", jornadaId: J.id });
    expect(html).toContain("Consultando el estado real");
  });

  it("desconocido reintentable: ofrece reintentar y verificar; nunca afirma éxito", () => {
    const html = panel(J, { fase: "desconocido", jornadaId: J.id, mensaje: "dudoso", reintentable: true });
    expect(botones(html).map((b) => b.texto)).toEqual(["Reintentar cambio de vendedor", "Verificar estado"]);
    expect(html).toContain('role="alert"');
    expect(html).not.toMatch(/cambiado|registrado/i);
  });

  it("desconocido no reintentable: sólo verificar", () => {
    const html = panel(J, { fase: "desconocido", jornadaId: J.id, mensaje: "dudoso", reintentable: false });
    expect(botones(html).map((b) => b.texto)).toEqual(["Verificar estado"]);
  });

  it("éxito sin releer: no ofrece ninguna acción; releída, vuelve a ofrecer el cambio", () => {
    expect(panel(J, { fase: "exito", jornadaId: J.id, mensaje: "ok" })).toBe("");
    expect(botones(panel(J, { fase: "exito", jornadaId: J.id, mensaje: "ok", releida: true }))).toEqual([
      { texto: "Cambiar vendedor", deshabilitado: false },
    ]);
  });

  it("un cambio desconocido de OTRA jornada bloquea iniciar otro", () => {
    const html = panel(J, { fase: "desconocido", jornadaId: jornada(2).id, mensaje: "x", reintentable: true });
    expect(botones(html)).toEqual([{ texto: "Cambiar vendedor", deshabilitado: true }]);
    expect(html).toContain("otra jornada sin resolver");
  });
});

describe("panel de reasignación: bloqueo por otra operación", () => {
  it("con motivo explícito lo muestra; sin motivo, uno genérico", () => {
    const con = panel(J, { fase: "inactiva" }, LISTA, { bloqueadaPorOtra: true, motivoBloqueo: "Salida en curso." });
    expect(botones(con)).toEqual([{ texto: "Cambiar vendedor", deshabilitado: true }]);
    expect(con).toContain("Salida en curso.");
    const sin = panel(J, { fase: "inactiva" }, LISTA, { bloqueadaPorOtra: true });
    expect(sin).toContain(MOTIVO_BLOQUEO_REASIGNACION_POR_DEFECTO);
  });
});
