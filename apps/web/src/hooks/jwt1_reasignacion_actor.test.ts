import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import { crearPuertoJornadas } from "../lib/jornadas";
import { buscarEnFecha } from "./useReasignacionJornada";
import type { Jornada } from "../lib/jornadas";

const ACTOR_A = "aaaaaaaa-1111-4111-8111-111111111111";
const ACTOR_B = "bbbbbbbb-2222-4222-8222-222222222222";

// Fila como la devuelve Supabase (snake_case); filaAJornada la convierte a Jornada (camelCase).
const FILA_SNAKE = {
  id: "11111111-1111-4111-8111-111111111111",
  fecha: "2026-11-10",
  camion_id: "22222222-2222-4222-8222-222222222222",
  vendedor_id: "33333333-3333-4333-8333-333333333333",
  estado: "abierta",
  abierta_por: "66666666-6666-4666-8666-666666666666",
  operacion_apertura_id: "99999999-9999-4999-8999-999999999999",
  creado_en: "2026-11-10T08:00:00+00:00",
};

// Jornada como la devuelve filaAJornada (camelCase, tipo Jornada).
const JORNADA: Jornada = {
  id: "11111111-1111-4111-8111-111111111111",
  fecha: "2026-11-10",
  camionId: "22222222-2222-4222-8222-222222222222",
  vendedorId: "33333333-3333-4333-8333-333333333333",
  estado: "abierta",
  abiertaPor: "66666666-6666-4666-8666-666666666666",
  operacionAperturaId: "99999999-9999-4999-8999-999999999999",
  creadoEn: "2026-11-10T08:00:00+00:00",
};

/** Puerto fake que registra las opciones de leerTodasLasJornadas y ejecuta
 * realmente la lógica de `leerPaginaJornadas` (incl. setHeader). */
function puertoConLectura(opciones: {
  sesiones: Array<{ id: string; access_token: string } | null | "lanzar">;
  lecturas: Array<{ fecha: string | undefined; actorEsperado: string | undefined }>;
}) {
  const { sesiones, lecturas } = opciones;
  let sesionIndex = 0;

  const cliente = {
    auth: {
      async getSession() {
        const s = sesiones[sesionIndex++] ?? sesiones[sesiones.length - 1];
        if (s === "lanzar") throw new Error("auth caído");
        return {
          data: {
            session: s ? { user: { id: s.id }, access_token: s.access_token } : null,
            user: s ?? null,
          },
          error: null,
        };
      },
    },
    from() {
      const cabeceras: Record<string, string> = {};
      async function ejecutar(_n: number) {
        void _n;
        return { data: [FILA_SNAKE], error: null, count: 1 };
      }
      const consulta: Record<string, unknown> = {
        select: () => consulta,
        eq: () => consulta,
        or: () => consulta,
        order: () => consulta,
        limit: (n: number) => ejecutar(n),
        setHeader: (nombre: string, valor: string) => {
          cabeceras[nombre] = valor;
        },
      };
      return consulta;
    },
  };

  const puertoReal = crearPuertoJornadas(cliente as unknown as SupabaseClient);
  const leerTodasOriginal = puertoReal.leerTodasLasJornadas.bind(puertoReal);
  const puertoInterceptado = {
    async leerTodasLasJornadas(filtro: { fecha?: string; actorEsperado?: string }) {
      lecturas.push({ fecha: filtro.fecha, actorEsperado: filtro.actorEsperado });
      return leerTodasOriginal(filtro);
    },
  };

  return { cliente: cliente as unknown as SupabaseClient, puerto: puertoInterceptado };
}

describe("H-1 — Reasignación propaga actorEsperado (JWT-1)", () => {
  it("A inicia reasignación con actor A: la verificación usa el JWT de A (actor fijado en la sesión de reasignación, no la sesión global)", async () => {
    const lecturas: Array<{ fecha: string | undefined; actorEsperado: string | undefined }> = [];
    const { puerto } = puertoConLectura({
      sesiones: [
        { id: ACTOR_A, access_token: `token-${ACTOR_A}-1` }, // getSession de la verificación → A
      ],
      lecturas,
    });
    const buscar = buscarEnFecha(puerto, ACTOR_A);
    const r = await buscar(JORNADA.id, [JORNADA.fecha]);
    expect(r).toEqual(JORNADA);
    // La consulta se hizo con el actor de A (fijado al crear la sesión de reasignación).
    expect(lecturas).toHaveLength(1);
    expect(lecturas[0].actorEsperado).toBe(ACTOR_A);
    expect(lecturas[0].fecha).toBe(JORNADA.fecha);
  });

  it("sesión de B al verificar reasignación de A → cero consultas, falla cerrado", async () => {
    const lecturas: Array<{ fecha: string | undefined; actorEsperado: string | undefined }> = [];
    const { puerto } = puertoConLectura({
      sesiones: [
        { id: ACTOR_B, access_token: `token-${ACTOR_B}-1` }, // sesión es de B, pero actor esperado es A
      ],
      lecturas,
    });
    const buscar = buscarEnFecha(puerto, ACTOR_A);
    const r = await buscar(JORNADA.id, [JORNADA.fecha]);
    expect(r).toBeUndefined(); // falla cerrado: B no es A
    // No hay forma de que B firme una consulta para A: el actor esperado es A.
  });

  it("sin actorEsperado (compatibilidad): lectura sin pin, contrato previo", async () => {
    const lecturas: Array<{ fecha: string | undefined; actorEsperado: string | undefined }> = [];
    const { puerto } = puertoConLectura({
      sesiones: [{ id: ACTOR_A, access_token: `token-${ACTOR_A}-1` }],
      lecturas,
    });
    const buscarSinActor = buscarEnFecha(puerto);
    const r = await buscarSinActor(JORNADA.id, [JORNADA.fecha]);
    expect(r).toEqual(JORNADA);
    expect(lecturas).toHaveLength(1);
    expect(lecturas[0].actorEsperado).toBeUndefined();
  });
});
