import { createClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import { crearPuertoJornadas } from "./jornadas";

/** Codifica a base64url sin `Buffer` (sin nuevas dependencias, sin credenciales reales). */
function b64url(obj: unknown): string {
  const json = JSON.stringify(obj);
  const base64 = btoa(json);
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Construye un JWT falso válido (header.payload.sig, base64url) sin red ni credenciales reales. */
function jwt(sub: string): string {
  return `${b64url({ alg: "none" })}.${b64url({
    sub,
    exp: Math.floor(Date.now() / 1000) + 3600,
    role: "authenticated",
  })}.sig`;
}

const A = "aaaaaaaa-1111-4111-8111-111111111111";
const B = "bbbbbbbb-2222-4222-8222-222222222222";

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

/** Extrae el `sub` del token `Authorization: Bearer <jwt>` (sin validar firma). */
function subDeToken(autorizacion: string | null): string {
  if (!autorizacion || !autorizacion.startsWith("Bearer ")) return "ANON";
  const payloadB64 = autorizacion.split(".")[1] ?? "";
  try {
    const payload = JSON.parse(atob(payloadB64));
    return typeof payload.sub === "string" ? payload.sub : "ANON";
  } catch {
    return "ANON";
  }
}

/** Monta un cliente Supabase real con `global.fetch` interceptado, storage en memoria y cero red. */
function montarClienteReal(
  onFetch: (n: number, sub: string) => Response | null
) {
  const mem: Record<string, string> = {};
  const K = "sb-localhost-auth-token";
  const vistos: Array<string> = [];
  let n = 0;

  const cli = createClient("http://localhost:9", "sb_publishable_xxxxxxxxxxxxxxxxxxxxxx", {
    auth: {
      persistSession: true,
      autoRefreshToken: false,
      storage: {
        getItem: (k: string) => mem[k] ?? null,
        setItem: (k: string, v: string) => {
          mem[k] = v;
        },
        removeItem: (k: string) => {
          delete mem[k];
        },
      },
    },
    global: {
      fetch: async (_u: RequestInfo | URL, init?: RequestInit) => {
        const h = new Headers(init?.headers ?? {});
        const sub = subDeToken(h.get("authorization") || "");
        const etiqueta = h.get("x-retry-count") ? `${sub}(retry)` : sub;
        vistos.push(etiqueta);
        const r = onFetch(n++, sub);
        return (
          r ??
          new Response(JSON.stringify([FILA_SNAKE]), {
            status: 200,
            headers: {
              "content-type": "application/json",
              "content-range": "0-0/1",
            },
          })
        );
      },
    },
  });

  return {
    cli,
    set: (sub: string) => {
      mem[K] = JSON.stringify({
        access_token: jwt(sub),
        refresh_token: "r",
        token_type: "bearer",
        expires_in: 3600,
        expires_at: Math.floor(Date.now() / 1000) + 3600,
        user: { id: sub },
      });
    },
    mem,
    vistos,
    puerto: crearPuertoJornadas(cli as never),
  };
}

describe("JWT-1: lecturas de verificación con cliente Supabase real y fetch interceptado", () => {
  describe("R1. Capturar JWT de A, cambiar sesión a B antes del fetch → Authorization = A", () => {
    it("E1: A antes/después del fetch: el transporte recibe A, nunca B", async () => {
      const m = montarClienteReal(() => null);
      m.set(A);
      const orig = m.cli.auth.getSession.bind(m.cli.auth);
      void orig;
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (m.cli.auth as any).getSession = async () => {
        const r = await orig();
        queueMicrotask(() => m.set(B)); // sesión global pasa a B justo antes del fetch
        return r;
      };
      const r = await m.puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: A });
      expect(r.ok).toBe(true);
      expect(m.vistos).toEqual([A]);
    });
  });

  describe("R2. HTTP 503 → el reintento transmite el mismo JWT de A", () => {
    it("E2: respuesta 503 con Retry-After: 0; ambos intentos llevan A", async () => {
      const m = montarClienteReal((n) =>
        n === 0 ? new Response("", { status: 503, headers: { "Retry-After": "0" } }) : null
      );
      m.set(A);
      const orig = m.cli.auth.getSession.bind(m.cli.auth);
      void orig;
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (m.cli.auth as any).getSession = async () => {
        const r = await orig();
        queueMicrotask(() => m.set(B));
        return r;
      };
      const r = await m.puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: A });
      expect(r.ok).toBe(true);
      expect(m.vistos).toEqual([A, `${A}(retry)`]);
    });
  });

  describe("R3. Sesión de B con actor esperado A → cero peticiones de verificación", () => {
    it("E3: actorEsperado=A pero sesión vigente es B ⇒ no hay fetch", async () => {
      const m = montarClienteReal(() => null);
      m.set(B);
      const r = await m.puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: A });
      expect(r.ok).toBe(false);
      expect(m.vistos).toHaveLength(0);
    });
  });

  describe("R4. Sesión nula / getSession falla / token vacío → cero peticiones", () => {
    it("sesión nula ⇒ cero fetch", async () => {
      const m = montarClienteReal(() => null);
      // Sin m.set → sesión nula
      const r = await m.puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: A });
      expect(r.ok).toBe(false);
      expect(m.vistos).toHaveLength(0);
    });

    it("getSession lanza ⇒ cero fetch", async () => {
      const m = montarClienteReal(() => null);
      m.set(A);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (m.cli.auth as any).getSession = async () => {
        throw new Error("auth caído");
      };
      const r = await m.puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: A });
      expect(r.ok).toBe(false);
      expect(m.vistos).toHaveLength(0);
    });

    it("token vacío con identidad válida ⇒ cero fetch", async () => {
      const m = montarClienteReal(() => null);
      m.mem["sb-localhost-auth-token"] = JSON.stringify({
        access_token: "",
        refresh_token: "r",
        token_type: "bearer",
        expires_in: 3600,
        expires_at: Math.floor(Date.now() / 1000) + 3600,
        user: { id: A },
      });
      const r = await m.puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: A });
      expect(r.ok).toBe(false);
      expect(m.vistos).toHaveLength(0);
    });
  });

  describe("R5. HTTP 401 → error, sin inferir éxito ni descartar intención desconocida", () => {
    it("E6: JWT rechazado con 401 ⇒ ok:false, sin éxito", async () => {
      const m = montarClienteReal(
        () =>
          new Response(JSON.stringify({ message: "JWT expired", code: "PGRST303" }), {
            status: 401,
            headers: { "content-type": "application/json" },
          })
      );
      m.set(A);
      const r = await m.puerto.leerTodasLasJornadas({ fecha: "2026-11-10", actorEsperado: A });
      expect(r.ok).toBe(false);
      expect(m.vistos).toEqual([A]);
    });
  });

  describe("R6. Lectura ordinaria sin actor esperado → contrato anterior intacto", () => {
    it("E5: sin actorEsperado usa el token global vigente (B), contrato previo", async () => {
      const m = montarClienteReal(() => null);
      m.set(B);
      const r = await m.puerto.leerTodasLasJornadas({ fecha: "2026-11-10" });
      expect(r.ok).toBe(true);
      expect(m.vistos).toEqual([B]);
    });
  });
});
