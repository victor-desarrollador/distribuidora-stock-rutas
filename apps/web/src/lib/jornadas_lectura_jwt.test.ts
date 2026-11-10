import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import {
  MENSAJE_DATOS_INVALIDOS,
  MENSAJE_RESULTADO_DESCONOCIDO,
  TAMANO_PAGINA_JORNADAS,
  crearPuertoJornadas,
  esUuid,
  type Jornada,
} from "./jornadas";

const ACTOR_A = "aaaaaaaa-1111-4111-8111-111111111111";
const ACTOR_B = "bbbbbbbb-2222-4222-8222-222222222222";

interface Peticion {
  autorizacion: string | null;
}

/** Cliente falso basado en el patrón probado de `clienteLectura` de
 * `jornadas.test.ts`, ejecutando realmente la lógica de `leerPaginaJornadas`
 * y capturando cada `setHeader`. Valida que el JWT se fije por petición. */
function clienteFalso(opciones: {
  filas: Jornada[];
  sesiones: Array<{ id: string; access_token: string } | null | "lanzar">;
  respuestasConsulta: Array<{ data: unknown[]; error: unknown; count: number } | "lanzar">;
  peticiones: Peticion[];
}) {
  const { filas, sesiones, respuestasConsulta, peticiones } = opciones;
  let sesionIndex = 0;
  let consultaIndex = 0;

  function esAnterior(a: { fecha: string; id: string }, b: { fecha: string; id: string }): boolean {
    if (a.fecha !== b.fecha) return a.fecha < b.fecha;
    return a.id.toLowerCase() < b.id.toLowerCase();
  }

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
      const p: {
        n: number;
        operaciones: Array<{ operacion: string; args: unknown[] }>;
        eq: string | null;
        cursor: { fecha: string; id: string } | null;
        limite: number;
      } = {
        n: 0,
        operaciones: [],
        eq: null,
        cursor: null,
        limite: -1,
      };
      const anotar = (operacion: string, args: unknown[]) => p.operaciones.push({ operacion, args });
      const consulta: Record<string, unknown> = {
        select: (...args: unknown[]) => (anotar("select", args), consulta),
        eq: (...args: unknown[]) => {
          anotar("eq", args);
          p.eq = args[1] as string;
          return consulta;
        },
        or: (...args: unknown[]) => {
          anotar("or", args);
          const m = /^fecha\.lt\.([\d-]+),and\(fecha\.eq\.\1,id\.lt\.([0-9a-f-]+)\)$/i.exec(args[0] as string);
          if (m) p.cursor = { fecha: m[1], id: m[2] };
          return consulta;
        },
        order: (...args: unknown[]) => (anotar("order", args), consulta),
        limit: (n: number) => {
          anotar("limit", [n]);
          p.limite = n;
          p.n += 1;
          const c = p.cursor;
          const coincide = filas
            .filter(
              (f) =>
                (p.eq === null || f.fecha === p.eq) &&
                (c === null ||
                  (f.fecha as string) < c.fecha ||
                  (f.fecha === c.fecha && (f.id as string) < c.id))
            )
            .sort((a, b) => (esAnterior(b, a) ? -1 : 1));
          const normal = {
            data: coincide.slice(0, Math.min(n, TAMANO_PAGINA_JORNADAS + 1)).map((f) => ({ ...f })),
            error: null,
            count: coincide.length,
          };
          const r = respuestasConsulta[consultaIndex++] ?? normal;
          if (r === "lanzar") throw new Error("red caída");
          return Promise.resolve(r);
        },
        setHeader: (_nombre: string, valor: string) => {
          peticiones.push({ autorizacion: valor });
        },
      };
      return consulta;
    },
  };

  return { cliente: cliente as unknown as SupabaseClient };
}

function filasJornada(n: number, fecha: string): Jornada[] {
  return Array.from({ length: n }, (_, i) => ({
    id: `00000000-0000-4000-8000-${i.toString(16).padStart(12, "0")}`,
    fecha,
    camion_id: "22222222-2222-4222-8222-222222222222",
    vendedor_id: "33333333-3333-4333-8333-333333333333",
    estado: "abierta",
    abierta_por: "66666666-6666-4666-8666-666666666666",
    operacion_apertura_id: "99999999-9999-4999-8999-999999999999",
    creado_en: "2026-11-10T08:00:00+00:00",
  })) as unknown as Jornada[];
}

describe("JWT-1: lecturas de verificación de jornadas con JWT por petición (setHeader por petición)", () => {
  describe("T1. Usuario A: la verificación envía el JWT de A", () => {
    it("fija Authorization con el token capturado de la sesión de A", async () => {
      const peticiones: Peticion[] = [];
      const { cliente } = clienteFalso({
        filas: filasJornada(3, "2026-11-10"),
        sesiones: [{ id: ACTOR_A, access_token: `token-${ACTOR_A}-1` }],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      const rpta = await puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: ACTOR_A });
      expect(rpta.ok).toBe(true);
      expect(peticiones.some((p) => p.autorizacion === `Bearer token-${ACTOR_A}-1`)).toBe(true);
    });
  });

  describe("T2. Cambio A→B antes del despacho: no se emite una lectura atribuida incorrectamente", () => {
    it("sesión de B al verificar intención de A → cero peticiones, falla cerrado", async () => {
      const peticiones: Peticion[] = [];
      const { cliente } = clienteFalso({
        filas: [],
        sesiones: [{ id: ACTOR_B, access_token: `token-${ACTOR_B}-1` }],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      const rpta = await puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: ACTOR_A });
      expect(rpta.ok).toBe(false);
      if (!rpta.ok) expect(rpta.error.mensaje).toBe(MENSAJE_RESULTADO_DESCONOCIDO);
      expect(peticiones).toHaveLength(0);
    });
  });

  describe("T3. JWT de A capturado antes del despacho: la lectura permanece vinculada a A", () => {
    it("una lectura de una página usa el JWT de A capturado en getSession (sin cambio de sesión durante el fetch)", async () => {
      const peticiones: Peticion[] = [];
      const { cliente } = clienteFalso({
        filas: filasJornada(3, "2026-11-10"),
        sesiones: [
          { id: ACTOR_A, access_token: `token-${ACTOR_A}-1` }, // getSession de la lectura → A
        ],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      const rpta = await puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: ACTOR_A });
      expect(rpta.ok).toBe(true);
      expect(peticiones.every((p) => p.autorizacion === `Bearer token-${ACTOR_A}-1`)).toBe(true);
      expect(peticiones.some((p) => p.autorizacion?.includes(ACTOR_B))).toBe(false);
    });

    it("cambio de sesión a B entre páginas: la segunda página falla cerrado (no usa B)", async () => {
      const peticiones: Peticion[] = [];
      const filas = filasJornada(TAMANO_PAGINA_JORNADAS + 5, "2026-11-10");
      const { cliente } = clienteFalso({
        filas,
        sesiones: [
          { id: ACTOR_A, access_token: `token-${ACTOR_A}-1` }, // página 1: A
          { id: ACTOR_B, access_token: `token-${ACTOR_B}-1` }, // página 2: B
        ],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      const rpta = await puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: ACTOR_A });
      expect(rpta.ok).toBe(false); // falla cerrado: B no es A
      if (!rpta.ok) expect(rpta.error.mensaje).toBe(MENSAJE_RESULTADO_DESCONOCIDO);
      expect(peticiones.some((p) => p.autorizacion?.includes(ACTOR_B))).toBe(false);
    });
  });

  describe("T4. Sesión nula o getSession fallida: no hay consulta de verificación", () => {
    it("sesión nula → cero peticiones, falla cerrado", async () => {
      const peticiones: Peticion[] = [];
      const { cliente } = clienteFalso({
        filas: [],
        sesiones: [null],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      const rpta = await puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: ACTOR_A });
      expect(rpta.ok).toBe(false);
      if (!rpta.ok) expect(rpta.error.mensaje).toBe(MENSAJE_RESULTADO_DESCONOCIDO);
      expect(peticiones).toHaveLength(0);
    });

    it("getSession falla → cero peticiones, falla cerrado", async () => {
      const peticiones: Peticion[] = [];
      const { cliente } = clienteFalso({
        filas: [],
        sesiones: ["lanzar"],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      const rpta = await puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: ACTOR_A });
      expect(rpta.ok).toBe(false);
      if (!rpta.ok) expect(rpta.error.mensaje).toBe(MENSAJE_RESULTADO_DESCONOCIDO);
      expect(peticiones).toHaveLength(0);
    });

    it("access_token vacío con identidad válida → falla cerrado, no cae al token global", async () => {
      const peticiones: Peticion[] = [];
      const { cliente } = clienteFalso({
        filas: [],
        sesiones: [{ id: ACTOR_A, access_token: "" }],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      const rpta = await puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: ACTOR_A });
      expect(rpta.ok).toBe(false);
      if (!rpta.ok) expect(rpta.error.mensaje).toBe(MENSAJE_RESULTADO_DESCONOCIDO);
      expect(peticiones).toHaveLength(0);
    });
  });

  describe("T5. Múltiples lecturas de la misma operación: todas se verifican bajo el mismo actor esperado", () => {
    it("dos llamadas independientes de lectura usan el mismo JWT de A (sin cambio de actor entre ellas)", async () => {
      const peticiones: Peticion[] = [];
      const filas = filasJornada(3, "2026-11-10");
      const { cliente } = clienteFalso({
        filas,
        sesiones: [
          { id: ACTOR_A, access_token: `token-${ACTOR_A}-1` }, // llamada 1
          { id: ACTOR_A, access_token: `token-${ACTOR_A}-1` }, // llamada 2
        ],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      // Dos lecturas independientes con el mismo actorEsperado.
      const r1 = await puerto.leerPaginaJornadas({ fecha: "2026-11-10", actorEsperado: ACTOR_A });
      const r2 = await puerto.leerPaginaJornadas({ fecha: "2026-11-10", actorEsperado: ACTOR_A });
      expect(r1.ok).toBe(true);
      expect(r2.ok).toBe(true);
      // Ambas peticiones llevan el mismo JWT de A.
      expect(peticiones.every((p) => p.autorizacion === `Bearer token-${ACTOR_A}-1`)).toBe(true);
      expect(peticiones.length).toBe(2);
      expect(peticiones.some((p) => p.autorizacion?.includes(ACTOR_B))).toBe(false);
    });

    it("lectura paginada: todas las páginas se verifican bajo el mismo actor esperado", async () => {
      const peticiones: Peticion[] = [];
      const filas = filasJornada(TAMANO_PAGINA_JORNADAS + 5, "2026-11-10");
      const { cliente } = clienteFalso({
        filas,
        sesiones: [
          { id: ACTOR_A, access_token: `token-${ACTOR_A}-1` }, // página 1
          { id: ACTOR_A, access_token: `token-${ACTOR_A}-1` }, // página 2
        ],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      const rpta = await puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: ACTOR_A });
      expect(rpta.ok).toBe(true);
      if (rpta.ok) expect(rpta.datos).toHaveLength(TAMANO_PAGINA_JORNADAS + 5);
      expect(peticiones.every((p) => p.autorizacion === `Bearer token-${ACTOR_A}-1`)).toBe(true);
      expect(peticiones.length).toBeGreaterThan(1);
    });
  });

  describe("T6. Regresión: contratos anteriores mantenidos", () => {
    it("lectura sin actorEsperado sigue funcionando (sin JWT explícito)", async () => {
      const peticiones: Peticion[] = [];
      const { cliente } = clienteFalso({
        filas: filasJornada(3, "2026-11-10"),
        sesiones: [{ id: ACTOR_A, access_token: `token-${ACTOR_A}-1` }],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      const rpta = await puerto.leerTodasLasJornadas({ fecha: "2026-11-10" });
      expect(rpta.ok).toBe(true);
      expect(peticiones).toHaveLength(0);
    });

    it("fecha inválida: rechaza sin consultar", async () => {
      const peticiones: Peticion[] = [];
      const { cliente } = clienteFalso({
        filas: [],
        sesiones: [{ id: ACTOR_A, access_token: "x" }],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      const rpta = await puerto.leerPaginaJornadas({ fecha: "10/11/2026" });
      expect(rpta.ok).toBe(false);
      if (!rpta.ok) expect(rpta.error.mensaje).toBe(MENSAJE_DATOS_INVALIDOS);
      expect(peticiones).toHaveLength(0);
    });

    it("fecha inválida en leerTodas: rechaza sin consultar", async () => {
      const peticiones: Peticion[] = [];
      const { cliente } = clienteFalso({
        filas: [],
        sesiones: [{ id: ACTOR_A, access_token: "x" }],
        respuestasConsulta: [],
        peticiones,
      });
      const puerto = crearPuertoJornadas(cliente);
      const rpta = await puerto.leerTodasLasJornadas({ fecha: "mañana" });
      expect(rpta.ok).toBe(false);
      expect(peticiones).toHaveLength(0);
    });

    it("esUuid valida ids", () => {
      expect(esUuid(ACTOR_A)).toBe(true);
      expect(esUuid("no-uuid")).toBe(false);
    });
  });
});
