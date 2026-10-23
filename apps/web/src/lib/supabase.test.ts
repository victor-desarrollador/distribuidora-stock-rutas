import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";

import { resolverEstadoSesion } from "../auth/sesion";
import { crearPuertoSupabase, leerConfigSupabase } from "./supabase";

type Callback = (evento: string, sesion: unknown) => void;

function clienteFalso(opciones: {
  perfil?: unknown;
  empresa?: unknown;
  errorLogin?: { code?: string; status?: number } | null;
  errorSignOut?: boolean;
}) {
  let callback: Callback | null = null;
  const consultas: { tabla: string; columna: string; valor: string }[] = [];

  const cliente = {
    auth: {
      signInWithPassword: vi.fn(async () => ({
        data: {},
        error: opciones.errorLogin ?? null,
      })),
      signOut: vi.fn(async () => ({
        error: opciones.errorSignOut ? new Error("offline") : null,
      })),
      onAuthStateChange: vi.fn((cb: Callback) => {
        callback = cb;
        return { data: { subscription: { unsubscribe: vi.fn() } } };
      }),
    },
    from: vi.fn((tabla: string) => ({
      select: () => ({
        eq: (columna: string, valor: string) => {
          consultas.push({ tabla, columna, valor });
          return {
            maybeSingle: async () => ({
              data: tabla === "perfiles" ? opciones.perfil ?? null : opciones.empresa ?? null,
              error: null,
            }),
          };
        },
      }),
    })),
  };

  return {
    cliente: cliente as unknown as SupabaseClient,
    raw: cliente,
    consultas,
    emitir: (evento: string, sesion: unknown) => callback?.(evento, sesion),
  };
}

const SESION_CON_METADATA_FALSA = {
  user: {
    id: "u-1",
    user_metadata: { rol: "dueno", empresa_id: "emp-otra" },
    app_metadata: { rol: "dueno" },
  },
};

describe("leerConfigSupabase", () => {
  it("exige URL y publishable key con un error claro", () => {
    expect(() => leerConfigSupabase({})).toThrow(
      /VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY/
    );
    expect(() =>
      leerConfigSupabase({ VITE_SUPABASE_URL: "http://x" })
    ).toThrow(/VITE_SUPABASE_PUBLISHABLE_KEY/);
  });

  it("rechaza secret keys y JWT de service_role en el navegador", () => {
    expect(() =>
      leerConfigSupabase({
        VITE_SUPABASE_URL: "http://x",
        VITE_SUPABASE_PUBLISHABLE_KEY: "sb_secret_abc",
      })
    ).toThrow(/clave secreta/);

    const payload = btoa(JSON.stringify({ role: "service_role" }));
    expect(() =>
      leerConfigSupabase({
        VITE_SUPABASE_URL: "http://x",
        VITE_SUPABASE_PUBLISHABLE_KEY: `h.${payload}.f`,
      })
    ).toThrow(/clave secreta/);
  });

  it("acepta una publishable key", () => {
    expect(
      leerConfigSupabase({
        VITE_SUPABASE_URL: " http://127.0.0.1:54321 ",
        VITE_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_xyz",
      })
    ).toEqual({
      url: "http://127.0.0.1:54321",
      clavePublica: "sb_publishable_xyz",
    });
  });
});

describe("crearPuertoSupabase", () => {
  it("login usa signInWithPassword con el identificador interno", async () => {
    const f = clienteFalso({});
    const puerto = crearPuertoSupabase(f.cliente);

    await puerto.iniciarConPassword("juan@usuarios.distribuidora.invalid", "x");

    expect(f.raw.auth.signInWithPassword).toHaveBeenCalledWith({
      email: "juan@usuarios.distribuidora.invalid",
      password: "x",
    });
  });

  it("clasifica credenciales inválidas", async () => {
    const puerto = crearPuertoSupabase(
      clienteFalso({ errorLogin: { code: "invalid_credentials", status: 400 } }).cliente
    );

    expect(await puerto.iniciarConPassword("a", "b")).toEqual({
      error: "credenciales",
    });
  });

  it("notifica cada evento de Auth aunque el usuario no cambie", async () => {
    vi.useFakeTimers();
    const f = clienteFalso({});
    const puerto = crearPuertoSupabase(f.cliente);
    const cb = vi.fn();

    puerto.alCambiarUsuario(cb);
    for (const evento of ["INITIAL_SESSION", "TOKEN_REFRESHED", "USER_UPDATED", "SIGNED_IN"]) {
      f.emitir(evento, SESION_CON_METADATA_FALSA);
      await vi.runAllTimersAsync();
    }
    f.emitir("SIGNED_OUT", null);

    expect(cb.mock.calls).toEqual([["u-1"], ["u-1"], ["u-1"], ["u-1"], [null]]);
    vi.useRealTimers();
  });

  it("SIGNED_OUT se notifica en el acto y cancela el aviso pendiente del usuario", async () => {
    vi.useFakeTimers();
    const f = clienteFalso({});
    const puerto = crearPuertoSupabase(f.cliente);
    const cb = vi.fn();

    puerto.alCambiarUsuario(cb);
    f.emitir("SIGNED_IN", SESION_CON_METADATA_FALSA);
    f.emitir("SIGNED_OUT", null);

    // Sin correr timers: la invalidación ya ocurrió.
    expect(cb.mock.calls).toEqual([[null]]);

    await vi.runAllTimersAsync();
    expect(cb.mock.calls).toEqual([[null]]);
    vi.useRealTimers();
  });

  it("un cambio de usuario antes de entregar el aviso anterior sólo entrega el último", async () => {
    vi.useFakeTimers();
    const f = clienteFalso({});
    const puerto = crearPuertoSupabase(f.cliente);
    const cb = vi.fn();

    puerto.alCambiarUsuario(cb);
    f.emitir("SIGNED_IN", SESION_CON_METADATA_FALSA);
    f.emitir("SIGNED_IN", { user: { id: "u-2" } });
    await vi.runAllTimersAsync();

    expect(cb.mock.calls).toEqual([["u-2"]]);
    vi.useRealTimers();
  });

  it("desuscribirse cancela el aviso pendiente", async () => {
    vi.useFakeTimers();
    const f = clienteFalso({});
    const puerto = crearPuertoSupabase(f.cliente);
    const cb = vi.fn();

    const desuscribir = puerto.alCambiarUsuario(cb);
    f.emitir("SIGNED_IN", SESION_CON_METADATA_FALSA);
    desuscribir();
    await vi.runAllTimersAsync();

    expect(cb).not.toHaveBeenCalled();
    vi.useRealTimers();
  });

  it("logout cierra la sesión y, si falla la revocación remota, la local", async () => {
    const f = clienteFalso({ errorSignOut: true });
    const puerto = crearPuertoSupabase(f.cliente);

    await puerto.cerrarSesion();

    expect(f.raw.auth.signOut).toHaveBeenNthCalledWith(1);
    expect(f.raw.auth.signOut).toHaveBeenNthCalledWith(2, { scope: "local" });
  });

  it("user_metadata falso no concede rol: manda la fila de perfiles", async () => {
    const f = clienteFalso({
      perfil: {
        usuario_id: "u-1",
        empresa_id: "emp-1",
        usuario: "juan",
        nombre: "Juan",
        rol: "vendedor_piloto",
        activo: true,
      },
      empresa: { id: "emp-1", nombre: "Distribuidora", activo: true },
    });

    const estado = await resolverEstadoSesion(crearPuertoSupabase(f.cliente), "u-1");

    expect(estado.estado).toBe("autenticado");
    expect(estado.estado === "autenticado" && estado.perfil.rol).toBe(
      "vendedor_piloto"
    );
    expect(f.consultas).toEqual([
      { tabla: "perfiles", columna: "usuario_id", valor: "u-1" },
      { tabla: "empresas", columna: "id", valor: "emp-1" },
    ]);
  });

  it("user_metadata falso sin perfil: bloqueado", async () => {
    const f = clienteFalso({ perfil: null });

    expect(
      await resolverEstadoSesion(crearPuertoSupabase(f.cliente), "u-1")
    ).toEqual({ estado: "bloqueado", motivo: "sin_perfil" });
  });
});

describe("autorización sin user_metadata", () => {
  it("ningún archivo de la aplicación lee user_metadata ni app_metadata", () => {
    const fuentes = import.meta.glob<string>(
      ["../**/*.{ts,tsx}", "!../**/*.test.{ts,tsx}"],
      { query: "?raw", import: "default", eager: true }
    );

    // Se ignoran los comentarios: documentar la prohibición no es usarla.
    const sinComentarios = (codigo: string) =>
      codigo.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");

    const usos = Object.entries(fuentes)
      .filter(([, codigo]) =>
        /user_metadata|app_metadata|raw_user_meta_data|raw_app_meta_data/.test(
          sinComentarios(codigo)
        )
      )
      .map(([ruta]) => ruta);

    expect(Object.keys(fuentes).length).toBeGreaterThan(20);
    expect(usos).toEqual([]);
  });
});
