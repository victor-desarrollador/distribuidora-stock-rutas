import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import type { Jornada, PaginaJornadas, ResultadoJornada } from "../lib/jornadas";
import { AvisoSalidaJornada } from "./AvisoSalidaJornada";
import { JornadaSalidaPanel } from "./JornadaSalidaPanel";
import { JornadasVista } from "./JornadasVista";
import {
  crearControladorJornadas,
  type EstadoPantallaJornadas,
  type PuertoLecturaJornadas,
} from "./jornadas_lectura";
import {
  MENSAJE_SALIDA_OK,
  crearControladorSalida,
  type FaseSalida,
} from "./jornadas_salida";

const ID = "00000000-0000-4000-8000-000000000001";
const OP = "99999999-9999-4999-8999-999999999999";
const jornada = (estado: Jornada["estado"]): Jornada => ({
  id: ID, fecha: "2026-11-10",
  camionId: "22222222-2222-4222-8222-222222222222",
  vendedorId: "33333333-3333-4333-8333-333333333333",
  estado,
  abiertaPor: "66666666-6666-4666-8666-666666666666",
  operacionAperturaId: "77777777-7777-4777-8777-777777777777",
  creadoEn: "2026-11-10T08:00:00+00:00",
});

describe("AvisoSalidaJornada", () => {
  it("la región `status` está siempre montada (vacía si no hay resultado)", () => {
    for (const fase of [
      { fase: "inactiva" },
      { fase: "confirmando", jornadaId: ID },
      { fase: "enviando", jornadaId: ID },
    ] as FaseSalida[]) {
      const html = renderToStaticMarkup(<AvisoSalidaJornada fase={fase} />);
      expect(html).toBe('<div role="status" aria-live="polite"></div>');
    }
  });

  it("éxito: el mensaje se anuncia dentro de la región `status`", () => {
    const html = renderToStaticMarkup(
      <AvisoSalidaJornada fase={{ fase: "exito", jornadaId: ID, mensaje: MENSAJE_SALIDA_OK }} />
    );
    expect(html).toMatch(/^<div role="status" aria-live="polite"><p[^>]*>.*Salida confirmada\./);
    expect(html).not.toContain('role="alert"');
  });

  it("rechazo definitivo: se inserta un `alert` con el mensaje seguro (no queda un alert vacío montado)", () => {
    const html = renderToStaticMarkup(
      <AvisoSalidaJornada fase={{ fase: "error", jornadaId: ID, mensaje: "El camión no tiene carga neta" }} />
    );
    expect(html).toContain('role="alert"');
    expect(html).toContain("El camión no tiene carga neta");
    expect(html).not.toMatch(/SQL|PGRST|violates/i);
  });
});

// Regresión S1-C5 (Codex, revisión 2): el éxito sigue anunciado durante la
// relectura real `listo → cargando → listo`, aunque el detalle se desmonte.
describe("integración: salida + relectura real de la lista", () => {
  it("el anuncio de éxito permanece mientras la lista está «cargando» y después de releer", async () => {
    let jornadaEnBase = jornada("cargada");
    const lecturas: Array<(r: ResultadoJornada<PaginaJornadas>) => void> = [];
    const puertoLectura: PuertoLecturaJornadas = {
      leerPaginaJornadas: () => new Promise((r) => lecturas.push(r)),
      leerTodasLasJornadas: async () => ({ ok: true, intentos: 1, datos: [jornadaEnBase] }),
    };
    let estado: EstadoPantallaJornadas | null = null;
    const lectura = crearControladorJornadas(puertoLectura, (e) => (estado = e));
    const inicio = lectura.iniciar();
    lecturas[0]({ ok: true, intentos: 1, datos: { jornadas: [jornadaEnBase], siguiente: null } });
    await inicio;
    lectura.seleccionar(ID);

    let fase: FaseSalida = { fase: "inactiva" };
    const salida = crearControladorSalida(
      {
        ejecutar: async () => {
          jornadaEnBase = jornada("en_reparto"); // la base ya cambió
          return { ok: true, datos: OP, intentos: 1 };
        },
      },
      async () => "cargada",
      () => void lectura.recargar(), // lo que pasa la pantalla
      (f) => (fase = f)
    );

    const render = () =>
      renderToStaticMarkup(
        <JornadasVista
          estado={estado!}
          puedeAdministrar={true}
          nombreCamion={() => "Camión Norte · AB123CD"}
          onCambiarFecha={() => undefined}
          onRecargar={() => undefined}
          onCargarMas={() => undefined}
          onCargarTodas={() => undefined}
          onSeleccionar={() => undefined}
          accionesDetalle={(j) => (
            <JornadaSalidaPanel
              jornada={j} fase={fase} nombreCamion="Camión Norte · AB123CD"
              onSolicitar={() => undefined} onCancelar={() => undefined} onConfirmar={() => undefined}
              onReintentar={() => undefined} onVerificar={() => undefined}
            />
          )}
          avisos={<AvisoSalidaJornada fase={fase} />}
        />
      );

    salida.solicitar(jornadaEnBase);
    await salida.confirmar();

    // Durante la relectura: la lista está «cargando» y el detalle no existe…
    expect(estado!.lectura.estado).toBe("cargando");
    const durante = render();
    expect(durante).toContain("Cargando jornadas");
    expect(durante).not.toContain("Detalle de la jornada");
    // …pero el éxito sigue anunciado en la región `status` persistente.
    expect(durante).toMatch(/role="status" aria-live="polite"><p[^>]*>.*Salida confirmada/);

    // Termina la relectura: la jornada figura en reparto y el anuncio sigue.
    lecturas[1]({ ok: true, intentos: 1, datos: { jornadas: [jornadaEnBase], siguiente: null } });
    await new Promise((r) => setTimeout(r, 0));
    const despues = render();
    expect(despues).toContain("En reparto");
    expect(despues).toContain("Detalle de la jornada");
    expect(despues).toMatch(/role="status" aria-live="polite"><p[^>]*>.*Salida confirmada/);
    expect(despues).not.toContain("¿Confirmás la salida");
  });

  it("si la relectura falla, el éxito sigue anunciado junto al error de lectura", async () => {
    const lecturas: Array<(r: ResultadoJornada<PaginaJornadas>) => void> = [];
    let estado: EstadoPantallaJornadas | null = null;
    const lectura = crearControladorJornadas(
      { leerPaginaJornadas: () => new Promise((r) => lecturas.push(r)), leerTodasLasJornadas: async () => ({ ok: true, intentos: 1, datos: [] }) },
      (e) => (estado = e)
    );
    const inicio = lectura.iniciar();
    lecturas[0]({ ok: true, intentos: 1, datos: { jornadas: [jornada("cargada")], siguiente: null } });
    await inicio;
    let fase: FaseSalida = { fase: "inactiva" };
    const salida = crearControladorSalida(
      { ejecutar: async () => ({ ok: true, datos: OP, intentos: 1 }) },
      async () => "cargada",
      () => void lectura.recargar(),
      (f) => (fase = f)
    );
    salida.solicitar(jornada("cargada"));
    await salida.confirmar();
    lecturas[1]({ ok: false, intentos: 1, error: { codigo: null, mensaje: "No se pudieron leer las jornadas. Intentá de nuevo.", resultadoDesconocido: false } });
    await new Promise((r) => setTimeout(r, 0));
    expect(estado!.lectura.estado).toBe("error");
    const html = renderToStaticMarkup(
      <JornadasVista
        estado={estado!} puedeAdministrar={true} nombreCamion={() => "x"}
        onCambiarFecha={() => undefined} onRecargar={() => undefined} onCargarMas={() => undefined}
        onCargarTodas={() => undefined} onSeleccionar={() => undefined}
        avisos={<AvisoSalidaJornada fase={fase} />}
      />
    );
    expect(html).toContain("No se pudieron leer las jornadas");
    expect(html).toMatch(/role="status" aria-live="polite"><p[^>]*>.*Salida confirmada/);
  });
});
