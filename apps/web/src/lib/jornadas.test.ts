import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import {
  CANTIDAD_MAXIMA,
  MAX_INTENTOS,
  MAX_PAGINAS_JORNADAS,
  TAMANO_PAGINA_JORNADAS,
  MENSAJE_CONCURRENCIA,
  MENSAJE_DATOS_INVALIDOS,
  MENSAJE_ERROR_GENERICO,
  MENSAJE_ERROR_LECTURA,
  MENSAJE_RESULTADO_DESCONOCIDO,
  MENSAJE_SESION_CAMBIADA,
  MENSAJE_SIN_PERMISO,
  cantidadDesdeTexto,
  clasificarErrorJornada,
  crearPuertoJornadas,
  esCantidadJornada,
  esFechaValida,
  esUuid,
  filaAJornada,
  llamadaRpcJornada,
  nuevaClaveIdempotencia,
  validarComandoJornada,
  type ComandoJornada,
} from "./jornadas";
// Fuentes leídas como texto con `?raw` de Vite (sin APIs de Node).
import fuenteJornadas from "./jornadas.ts?raw";
import sqlAbrir from "../../../../supabase/migrations/20261031120000_rpc_abrir_jornada.sql?raw";
import sqlReasignar from "../../../../supabase/migrations/20261101120000_rpc_reasignar_vendedor.sql?raw";
import sqlCorregir from "../../../../supabase/migrations/20261109120000_rpc_corregir_jornada.sql?raw";
import sqlCarga from "../../../../supabase/migrations/20261106120000_rpc_registrar_carga.sql?raw";
import sqlDescarga from "../../../../supabase/migrations/20261107120000_rpc_registrar_descarga.sql?raw";
import sqlSalida from "../../../../supabase/migrations/20261108120000_rpc_confirmar_salida.sql?raw";

const CLAVE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const J = "11111111-1111-4111-8111-111111111111";
const CAMION = "22222222-2222-4222-8222-222222222222";
const VEND = "33333333-3333-4333-8333-333333333333";
const P1 = "44444444-4444-4444-8444-444444444444";
const P2 = "55555555-5555-4555-8555-555555555555";
const OP = "99999999-9999-4999-8999-999999999999";
const DUENO = "66666666-6666-4666-8666-666666666666";

type Respuesta = { data: unknown; error: unknown };
type Llamada = { nombre: string; argumentos: unknown };
// Usuario de la sesión en cada getSession (null: sin sesión; "lanzar": falla).
type SesionFalsa = string | null | "lanzar";

/**
 * Cliente falso: registra cada RPC y cada acceso a tablas. Las tablas sólo
 * exponen `select` (y la cadena eq/order). Cualquier método de escritura queda
 * registrado como violación. `sesiones` fija el usuario de cada `getSession`
 * (por defecto, siempre DUENO); el token es `token-<usuario>-<n>`.
 */
function clienteFalso(opciones: { rpc?: Array<Respuesta | "lanzar">; sesiones?: SesionFalsa[] }) {
  const llamadas: Llamada[] = [];
  const tablas: Array<{ tabla: string; operacion: string; args: unknown[] }> = [];
  const cabeceras: string[] = [];
  const respuestas = [...(opciones.rpc ?? [])];
  const sesiones = [...(opciones.sesiones ?? [])];
  let lecturasSesion = 0;
  const alLeerSesion: Array<() => void> = [];

  const cliente = {
    auth: {
      async getSession() {
        lecturasSesion += 1;
        for (const f of alLeerSesion) f();
        const u = sesiones.length > 0 ? sesiones.shift()! : DUENO;
        if (u === "lanzar") throw new Error("auth caído");
        return {
          data: { session: u === null ? null : { user: { id: u }, access_token: `token-${u}-${lecturasSesion}` } },
          error: null,
        };
      },
    },
    rpc(nombre: string, argumentos: unknown) {
      llamadas.push({ nombre, argumentos });
      const r = respuestas.shift() ?? { data: null, error: { code: "", message: "" } };
      return {
        setHeader(nombreCabecera: string, valor: string) {
          cabeceras.push(`${nombreCabecera}: ${valor}`);
          return r === "lanzar" ? Promise.reject(new Error("red caída")) : Promise.resolve(r);
        },
      };
    },
    from(tabla: string) {
      const registrar = (operacion: string) => (...args: unknown[]) => {
        tablas.push({ tabla, operacion, args });
        return consulta;
      };
      const consulta: Record<string, unknown> = {
        select: registrar("select"),
        eq: registrar("eq"),
        order: registrar("order"),
        limit: registrar("limit"),
        or: registrar("or"),
        insert: registrar("insert"),
        update: registrar("update"),
        upsert: registrar("upsert"),
        delete: registrar("delete"),
      };
      return consulta;
    },
  };

  return { cliente: cliente as unknown as SupabaseClient, llamadas, tablas, cabeceras, alLeerSesion };
}

const COMANDOS: Array<{ comando: ComandoJornada; rpc: string; args: Record<string, unknown> }> = [
  {
    comando: { tipo: "abrir", camionId: CAMION, fecha: "2026-11-10", vendedorId: VEND },
    rpc: "abrir_jornada",
    args: { p_idempotency_key: CLAVE, p_camion_id: CAMION, p_fecha: "2026-11-10", p_vendedor_id: VEND },
  },
  {
    comando: { tipo: "reasignar", jornadaId: J, vendedorId: VEND },
    rpc: "reasignar_vendedor",
    args: { p_idempotency_key: CLAVE, p_jornada_id: J, p_vendedor_id: VEND },
  },
  {
    comando: { tipo: "corregir", jornadaId: J, fecha: "2026-11-11", camionId: CAMION, motivo: "error de carga" },
    rpc: "corregir_jornada",
    args: { p_idempotency_key: CLAVE, p_jornada_id: J, p_fecha: "2026-11-11", p_camion_id: CAMION, p_motivo: "error de carga" },
  },
  {
    comando: { tipo: "cargar", jornadaId: J, lineas: [{ productoId: P1, cantidad: 12 }, { productoId: P2, cantidad: 1250 }] },
    rpc: "registrar_carga",
    args: { p_idempotency_key: CLAVE, p_jornada_id: J, p_productos: [P1, P2], p_cantidades: [12, 1250] },
  },
  {
    comando: { tipo: "descargar", jornadaId: J, lineas: [{ productoId: P2, cantidad: 250 }], motivo: "sobró" },
    rpc: "registrar_descarga",
    args: { p_idempotency_key: CLAVE, p_jornada_id: J, p_productos: [P2], p_cantidades: [250], p_motivo: "sobró" },
  },
  {
    comando: { tipo: "salir", jornadaId: J },
    rpc: "confirmar_salida",
    args: { p_idempotency_key: CLAVE, p_jornada_id: J },
  },
];

describe("llamadaRpcJornada: nombre y argumentos de las seis RPC", () => {
  it.each(COMANDOS)("$rpc", ({ comando, rpc, args }) => {
    const llamada = llamadaRpcJornada(comando, CLAVE);
    expect(llamada.nombre).toBe(rpc);
    expect(llamada.argumentos).toEqual(args);
    expect(Object.isFrozen(llamada)).toBe(true);
    expect(Object.isFrozen(llamada.argumentos)).toBe(true);
  });
});

// Contrato de las fachadas públicas leído del TEXTO de las migraciones (no se
// ejecuta SQL: no prueba el comportamiento en una base ni que las migraciones
// se hayan aplicado). Sólo parsea la cabecera `create function public.x(...)`
// y las sentencias revoke/grant de la propia fachada; las migraciones
// posteriores sólo verifican (no alteran) estas fachadas.
const TIPO_ESPERADO: Record<string, string> = {
  p_idempotency_key: "uuid",
  p_camion_id: "uuid",
  p_fecha: "date",
  p_vendedor_id: "uuid",
  p_jornada_id: "uuid",
  p_motivo: "text",
  p_productos: "uuid[]",
  p_cantidades: "int4[]",
};

function validaTipoSql(tipo: string, valor: unknown): boolean {
  switch (tipo) {
    case "uuid":
      return esUuid(valor);
    case "date":
      return esFechaValida(valor);
    case "text":
      return typeof valor === "string" && valor.trim() !== "";
    case "uuid[]":
      return Array.isArray(valor) && valor.length > 0 && valor.every(esUuid);
    case "int4[]":
      return Array.isArray(valor) && valor.length > 0 && valor.every(esCantidadJornada);
    default:
      return false;
  }
}

function fachada(sql: string, nombre: string) {
  const m = new RegExp(
    `create function public\\.${nombre}\\(([^)]*)\\)\\s*returns\\s+([\\w.]+)([\\s\\S]*?)\\$\\$`
  ).exec(sql.replaceAll("pg_catalog.", ""));
  if (m === null) return null;
  const parametros = m[1]
    .split(",")
    .map((p) => p.trim().split(/\s+/))
    .map(([n, t]) => ({ nombre: n, tipo: t }));
  return { parametros, retorno: m[2], atributos: m[3] };
}

// Cuerpo SQL de UNA fachada: el texto entre el primer par de `$$` que sigue a
// `create function public.<nombre>(`. Depende del formato de estas migraciones
// (cuerpo `language sql` delimitado por `$$`); si el formato cambia, la prueba
// falla en lugar de pasar en falso.
function cuerpoFachada(sql: string, nombre: string): string | null {
  const inicio = sql.indexOf(`create function public.${nombre}(`);
  if (inicio < 0) return null;
  const abre = sql.indexOf("$$", inicio);
  const cierra = abre < 0 ? -1 : sql.indexOf("$$", abre + 2);
  return abre < 0 || cierra < 0 ? null : sql.slice(abre + 2, cierra);
}

describe("fachadas públicas contra el texto de las migraciones", () => {
  const MIGRACIONES: Record<string, string> = {
    abrir_jornada: sqlAbrir,
    reasignar_vendedor: sqlReasignar,
    corregir_jornada: sqlCorregir,
    registrar_carga: sqlCarga,
    registrar_descarga: sqlDescarga,
    confirmar_salida: sqlSalida,
  };

  it("hay una migración por cada comando", () => {
    expect(Object.keys(MIGRACIONES).sort()).toEqual(COMANDOS.map((c) => c.rpc).sort());
  });

  it.each(COMANDOS)(
    "$rpc: nombre, orden y tipo de parámetros, retorno uuid, SECURITY INVOKER y search_path vacío",
    ({ rpc, args }) => {
      const sql = MIGRACIONES[rpc];
      const f = fachada(sql, rpc);
      expect(f).not.toBeNull();
      const { parametros, retorno, atributos } = f as NonNullable<typeof f>;
      expect(parametros.map((p) => p.nombre)).toEqual(Object.keys(args));
      expect(parametros.map((p) => p.tipo)).toEqual(parametros.map((p) => TIPO_ESPERADO[p.nombre]));
      expect(retorno).toBe("uuid");
      expect(atributos).toMatch(/security invoker/);
      expect(atributos).toMatch(/set search_path = ''/);
      expect(atributos).not.toMatch(/security definer/);
      // El cuerpo de ESTA fachada (entre sus `$$`) es exactamente una llamada a
      // la función privada homónima con los mismos parámetros, en orden. No
      // busca en el resto del archivo (comentarios ni la implementación privada).
      const cuerpo = cuerpoFachada(sql, rpc);
      expect(cuerpo).not.toBeNull();
      const nombres = parametros.map((p) => p.nombre).join(", ");
      expect((cuerpo as string).replace(/\s+/g, " ").trim()).toBe(`select privado.${rpc}(${nombres})`);
    }
  );

  it.each(COMANDOS)("$rpc: los argumentos que envía el cliente cumplen el tipo SQL de cada parámetro", ({ comando, rpc }) => {
    const f = fachada(MIGRACIONES[rpc], rpc) as NonNullable<ReturnType<typeof fachada>>;
    const enviados = llamadaRpcJornada(comando, CLAVE).argumentos;
    expect(Object.keys(enviados)).toEqual(f.parametros.map((p) => p.nombre));
    for (const p of f.parametros) {
      expect(validaTipoSql(p.tipo, enviados[p.nombre]), `${rpc}.${p.nombre} (${p.tipo})`).toBe(true);
    }
  });

  it.each(COMANDOS)("$rpc: permisos de la fachada (sólo authenticated; sin PUBLIC, anon ni service_role)", ({ rpc }) => {
    const sql = MIGRACIONES[rpc].replaceAll("pg_catalog.", "").replace(/\s+/g, " ");
    const f = fachada(MIGRACIONES[rpc], rpc) as NonNullable<ReturnType<typeof fachada>>;
    const firma = `public.${rpc}(${f.parametros.map((p) => p.tipo).join(", ")})`;
    expect(sql).toContain(`revoke all on function ${firma} from public, anon, authenticated, service_role;`);
    expect(sql).toContain(`grant execute on function ${firma} to authenticated;`);
    // Ninguna otra concesión sobre la fachada.
    const concesiones = sql.match(new RegExp(`grant [^;]*on function public\\.${rpc}\\([^;]*;`, "g"));
    expect(concesiones).toHaveLength(1);
  });
});

describe("validarComandoJornada", () => {
  it("acepta los comandos válidos", () => {
    for (const { comando } of COMANDOS) expect(validarComandoJornada(comando)).toBeNull();
  });

  it.each<[string, ComandoJornada]>([
    ["uuid inválido", { tipo: "salir", jornadaId: "no-uuid" }],
    ["fecha inexistente", { tipo: "abrir", camionId: CAMION, fecha: "2026-02-30", vendedorId: VEND }],
    ["fecha con hora", { tipo: "abrir", camionId: CAMION, fecha: "2026-11-10T00:00", vendedorId: VEND }],
    ["año 0", { tipo: "abrir", camionId: CAMION, fecha: "0000-01-01", vendedorId: VEND }],
    ["motivo vacío en corrección", { tipo: "corregir", jornadaId: J, fecha: "2026-11-11", camionId: CAMION, motivo: "   " }],
    ["motivo vacío en descarga", { tipo: "descargar", jornadaId: J, lineas: [{ productoId: P1, cantidad: 1 }], motivo: "" }],
    ["sin líneas", { tipo: "cargar", jornadaId: J, lineas: [] }],
    ["cantidad cero", { tipo: "cargar", jornadaId: J, lineas: [{ productoId: P1, cantidad: 0 }] }],
    ["cantidad decimal", { tipo: "cargar", jornadaId: J, lineas: [{ productoId: P1, cantidad: 1.5 }] }],
    ["cantidad sobre int4", { tipo: "cargar", jornadaId: J, lineas: [{ productoId: P1, cantidad: CANTIDAD_MAXIMA + 1 }] }],
    ["producto repetido (mayúsculas)", { tipo: "cargar", jornadaId: J, lineas: [{ productoId: P1, cantidad: 1 }, { productoId: P1.toUpperCase(), cantidad: 2 }] }],
  ])("rechaza: %s", (_n, comando) => {
    expect(validarComandoJornada(comando)).toBe(MENSAJE_DATOS_INVALIDOS);
  });

  it("acepta la cantidad máxima de int4 y fechas bisiestas", () => {
    expect(validarComandoJornada({ tipo: "cargar", jornadaId: J, lineas: [{ productoId: P1, cantidad: CANTIDAD_MAXIMA }] })).toBeNull();
    expect(esFechaValida("2028-02-29")).toBe(true);
    expect(esFechaValida("2100-02-29")).toBe(false);
    expect(esFechaValida("2000-02-29")).toBe(true);
  });
});

describe("cantidadDesdeTexto (ADR-005: kg con hasta 3 decimales → gramos enteros)", () => {
  it.each<["unidad" | "peso", string, number | null]>([
    ["peso", "1,250", 1250],
    ["peso", "1,005", 1005],
    ["peso", "0,001", 1],
    ["peso", "2", 2000],
    ["peso", "2147483,647", CANTIDAD_MAXIMA],
    ["peso", "2147483,648", null],
    ["peso", "1,2345", null],
    ["peso", "1.250", null],
    ["peso", "0", null],
    ["peso", "-1", null],
    ["unidad", "12", 12],
    ["unidad", "0", null],
    ["unidad", "1.5", null],
    ["unidad", "", null],
  ])("%s «%s» → %s", (forma, texto, esperado) => {
    expect(cantidadDesdeTexto(forma, texto)).toBe(esperado);
  });
});

describe("clasificarErrorJornada", () => {
  it.each([
    ["PT403", "jornada_no_autorizado", MENSAJE_SIN_PERMISO],
    ["PT409", "jornada_conflicto_idempotencia", "Esta operación ya se registró con otros datos. Revisá la jornada antes de volver a cargarla."],
    ["PT409", "jornada_estado_invalido", "La jornada cambió o no está en el estado que permite esta operación. Revisala e intentá de nuevo."],
    ["PT404", "jornada_no_encontrada", "La jornada no existe o no pertenece a tu empresa."],
    ["PT500", "jornada_error_interno", MENSAJE_ERROR_GENERICO],
    ["25006", "jornada_metodo_no_permitido", MENSAJE_ERROR_GENERICO],
  ])("%s %s es definitivo con mensaje propio", (code, message, mensaje) => {
    expect(clasificarErrorJornada({ code, message })).toEqual({ clase: "definitivo", codigo: message, mensaje });
  });

  it("42501 → sin permiso, definitivo; código desconocido → genérico, sin filtrar el detalle", () => {
    expect(clasificarErrorJornada({ code: "42501", message: "permission denied for function abrir_jornada" }))
      .toEqual({ clase: "definitivo", codigo: "42501", mensaje: MENSAJE_SIN_PERMISO });
    expect(clasificarErrorJornada({ code: "23505", message: "duplicate key value violates unique constraint x" }))
      .toEqual({ clase: "definitivo", codigo: "23505", mensaje: MENSAJE_ERROR_GENERICO });
  });

  it("40001/40P01 → transitorios; sin código → sin respuesta", () => {
    expect(clasificarErrorJornada({ code: "40001", message: "x" }).clase).toBe("transitorio");
    expect(clasificarErrorJornada({ code: "40P01", message: "x" }).clase).toBe("transitorio");
    expect(clasificarErrorJornada({ code: "", message: "TypeError: Failed to fetch" }).clase).toBe("sin_respuesta");
    expect(clasificarErrorJornada(null).clase).toBe("sin_respuesta");
  });
});

describe("crearPuertoJornadas.ejecutar (P13: ≤3 intentos, misma clave y payload)", () => {
  it.each(COMANDOS)("$rpc: éxito en el primer intento", async ({ comando, rpc, args }) => {
    const { cliente, llamadas } = clienteFalso({ rpc: [{ data: OP, error: null }] });
    const r = await crearPuertoJornadas(cliente).ejecutar(comando, CLAVE);
    expect(r).toEqual({ ok: true, datos: OP, intentos: 1 });
    expect(llamadas).toEqual([{ nombre: rpc, argumentos: args }]);
  });

  it("reintenta 40001, 40P01 y fallos de red con la MISMA clave y el MISMO payload", async () => {
    const { cliente, llamadas } = clienteFalso({
      rpc: [{ data: null, error: { code: "40001", message: "x" } }, "lanzar", { data: OP, error: null }],
    });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[3].comando, CLAVE);
    expect(r).toEqual({ ok: true, datos: OP, intentos: 3 });
    expect(llamadas).toHaveLength(3);
    expect(llamadas[1]).toEqual(llamadas[0]);
    expect(llamadas[2].argumentos).toBe(llamadas[0].argumentos);
  });

  it("agota 3 intentos de 40P01: sin efectos (concurrencia), no resultado desconocido", async () => {
    const e = { data: null, error: { code: "40P01", message: "deadlock" } };
    const { cliente, llamadas } = clienteFalso({ rpc: [e, e, e, e] });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[0].comando, CLAVE);
    expect(llamadas).toHaveLength(MAX_INTENTOS);
    expect(r).toEqual({ ok: false, intentos: 3, error: { codigo: "40P01", mensaje: MENSAJE_CONCURRENCIA, resultadoDesconocido: false } });
  });

  it("agota 3 intentos sin respuesta: resultado desconocido", async () => {
    const { cliente, llamadas } = clienteFalso({ rpc: ["lanzar", { data: null, error: { code: "", message: "" } }, { data: "no-uuid", error: null }] });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[5].comando, CLAVE);
    expect(llamadas).toHaveLength(3);
    expect(r).toEqual({ ok: false, intentos: 3, error: { codigo: null, mensaje: MENSAJE_RESULTADO_DESCONOCIDO, resultadoDesconocido: true } });
  });

  it.each([
    ["PT403", "jornada_no_autorizado"],
    ["PT401", "jornada_no_autenticado"],
    ["PT409", "jornada_estado_invalido"],
    ["PT409", "jornada_conflicto_idempotencia"],
    ["PT400", "jornada_fecha_invalida"],
    ["42501", "permission denied"],
    ["55P03", "lock not available"],
    ["57014", "canceling statement"],
    ["PT500", "jornada_error_interno"],
  ])("no reintenta %s %s", async (code, message) => {
    const { cliente, llamadas } = clienteFalso({ rpc: [{ data: null, error: { code, message } }, { data: OP, error: null }] });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[4].comando, CLAVE);
    expect(llamadas).toHaveLength(1);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.resultadoDesconocido).toBe(false);
  });

  it("datos inválidos o clave inválida: no llama al servidor", async () => {
    const { cliente, llamadas } = clienteFalso({ rpc: [{ data: OP, error: null }] });
    const puerto = crearPuertoJornadas(cliente);
    expect((await puerto.ejecutar({ tipo: "salir", jornadaId: "x" }, CLAVE)).ok).toBe(false);
    expect((await puerto.ejecutar(COMANDOS[5].comando, "no-es-uuid")).ok).toBe(false);
    expect(llamadas).toHaveLength(0);
  });

  it("nunca escribe tablas: sólo usa rpc", async () => {
    const { cliente, tablas } = clienteFalso({ rpc: COMANDOS.map(() => ({ data: OP, error: null })) });
    const puerto = crearPuertoJornadas(cliente);
    for (const { comando } of COMANDOS) await puerto.ejecutar(comando, CLAVE);
    expect(tablas).toHaveLength(0);
  });
});

// FE-2D (H-1): cada intento sale con la identidad del primero o no sale. Un
// intento ya enviado no se cancela ni se da por fallido.
describe("FE-2D H-1: ejecutar fija la identidad y no emite intentos tras detenerse", () => {
  const OTRO = "77777777-7777-4777-8777-777777777777";
  const SIN_RESPUESTA = "lanzar" as const;
  const DESCONOCIDO_1 = {
    ok: false,
    intentos: 1,
    error: { codigo: null, mensaje: MENSAJE_RESULTADO_DESCONOCIDO, resultadoDesconocido: true },
  };
  const NADA_ENVIADO = {
    ok: false,
    intentos: 0,
    error: { codigo: null, mensaje: MENSAJE_SESION_CAMBIADA, resultadoDesconocido: false },
  };

  it("U1: la sesión pasa a otro usuario tras un intento sin respuesta → no reenvía; desconocido", async () => {
    const { cliente, llamadas } = clienteFalso({
      rpc: [SIN_RESPUESTA, { data: OP, error: null }, { data: OP, error: null }],
      sesiones: [DUENO, OTRO, OTRO],
    });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[1].comando, CLAVE);
    expect(llamadas).toHaveLength(1);
    expect(r).toEqual(DESCONOCIDO_1);
  });

  it("U2: mismo usuario con token renovado → reintenta con el token verificado en cada intento", async () => {
    const { cliente, llamadas, cabeceras } = clienteFalso({
      rpc: [SIN_RESPUESTA, SIN_RESPUESTA, { data: OP, error: null }],
    });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[1].comando, CLAVE);
    expect(r).toEqual({ ok: true, datos: OP, intentos: 3 });
    expect(llamadas).toHaveLength(3);
    expect(cabeceras).toEqual([
      `Authorization: Bearer token-${DUENO}-1`,
      `Authorization: Bearer token-${DUENO}-2`,
      `Authorization: Bearer token-${DUENO}-3`,
    ]);
  });

  it("U3: sin sesión antes del primer intento → nada enviado, no desconocido", async () => {
    const { cliente, llamadas } = clienteFalso({ rpc: [{ data: OP, error: null }], sesiones: [null] });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[1].comando, CLAVE);
    expect(llamadas).toHaveLength(0);
    expect(r).toEqual(NADA_ENVIADO);
  });

  it("U4: la sesión se cierra antes del segundo intento → no reenvía; desconocido", async () => {
    const { cliente, llamadas } = clienteFalso({ rpc: [SIN_RESPUESTA, { data: OP, error: null }], sesiones: [DUENO, null] });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[1].comando, CLAVE);
    expect(llamadas).toHaveLength(1);
    expect(r).toEqual(DESCONOCIDO_1);
  });

  it("U5: usuarioEsperado distinto de la sesión → nada enviado", async () => {
    const { cliente, llamadas } = clienteFalso({ rpc: [{ data: OP, error: null }] });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[1].comando, CLAVE, { usuarioEsperado: OTRO });
    expect(llamadas).toHaveLength(0);
    expect(r).toEqual(NADA_ENVIADO);
  });

  it("U5b: usuarioEsperado igual a la sesión → envía normalmente", async () => {
    const { cliente, llamadas } = clienteFalso({ rpc: [{ data: OP, error: null }] });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[1].comando, CLAVE, { usuarioEsperado: DUENO });
    expect(llamadas).toHaveLength(1);
    expect(r).toEqual({ ok: true, datos: OP, intentos: 1 });
  });

  it("U6: detenido tras un intento sin respuesta → no reenvía; desconocido (lo enviado no se niega)", async () => {
    let activo = true;
    const { cliente, llamadas, alLeerSesion } = clienteFalso({ rpc: [SIN_RESPUESTA, { data: OP, error: null }] });
    // Se detiene cuando el primer intento ya salió (antes de preparar el segundo).
    alLeerSesion.push(() => {
      if (llamadas.length === 1) activo = false;
    });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[1].comando, CLAVE, { continuar: () => activo });
    expect(r).toEqual(DESCONOCIDO_1);
    expect(llamadas).toHaveLength(1);
  });

  it("U6b: detenido antes del primer intento (o mientras se lee la sesión) → nada enviado", async () => {
    const a = clienteFalso({ rpc: [{ data: OP, error: null }] });
    expect(await crearPuertoJornadas(a.cliente).ejecutar(COMANDOS[1].comando, CLAVE, { continuar: () => false }))
      .toEqual(NADA_ENVIADO);
    expect(a.llamadas).toHaveLength(0);

    let activo = true;
    const b = clienteFalso({ rpc: [{ data: OP, error: null }] });
    b.alLeerSesion.push(() => (activo = false));
    expect(await crearPuertoJornadas(b.cliente).ejecutar(COMANDOS[1].comando, CLAVE, { continuar: () => activo }))
      .toEqual(NADA_ENVIADO);
    expect(b.llamadas).toHaveLength(0);
  });

  it("U7: getSession falla → nada enviado en el primer intento; desconocido en el segundo", async () => {
    const a = clienteFalso({ rpc: [{ data: OP, error: null }], sesiones: ["lanzar"] });
    expect(await crearPuertoJornadas(a.cliente).ejecutar(COMANDOS[1].comando, CLAVE)).toEqual(NADA_ENVIADO);
    expect(a.llamadas).toHaveLength(0);

    const b = clienteFalso({ rpc: [SIN_RESPUESTA, { data: OP, error: null }], sesiones: [DUENO, "lanzar"] });
    expect(await crearPuertoJornadas(b.cliente).ejecutar(COMANDOS[1].comando, CLAVE)).toEqual(DESCONOCIDO_1);
    expect(b.llamadas).toHaveLength(1);
  });

  it("U8: corta tras un 40001 con otra sesión → sin efectos (no desconocido), como al agotar intentos", async () => {
    const { cliente, llamadas } = clienteFalso({
      rpc: [{ data: null, error: { code: "40001", message: "x" } }, { data: OP, error: null }],
      sesiones: [DUENO, OTRO],
    });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[1].comando, CLAVE);
    expect(llamadas).toHaveLength(1);
    expect(r).toEqual({ ok: false, intentos: 1, error: { codigo: "40001", mensaje: MENSAJE_CONCURRENCIA, resultadoDesconocido: false } });
  });

  it("no cambia la política de reintentos (P13 pendiente): 3 intentos máximos con la misma identidad", async () => {
    expect(MAX_INTENTOS).toBe(3);
    const { cliente, llamadas } = clienteFalso({ rpc: [SIN_RESPUESTA, SIN_RESPUESTA, SIN_RESPUESTA, { data: OP, error: null }] });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[1].comando, CLAVE, { continuar: () => true });
    expect(llamadas).toHaveLength(3);
    expect(r.ok).toBe(false);
  });
});

// FE-2E (D-2): `alFijarActor` permite fijar la identidad de la intención lógica.
describe("FE-2E: alFijarActor (identidad por intención)", () => {
  const OTRO = "77777777-7777-4777-8777-777777777777";

  it("U9: se invoca UNA vez, con el usuario, antes del primer despacho (aunque haya reintentos)", async () => {
    const avisos: Array<{ usuario: string; enviadosAntes: number }> = [];
    const { cliente, llamadas } = clienteFalso({ rpc: ["lanzar", "lanzar", { data: OP, error: null }] });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[1].comando, CLAVE, {
      alFijarActor: (usuario) => avisos.push({ usuario, enviadosAntes: llamadas.length }),
    });
    expect(r.ok).toBe(true);
    expect(llamadas).toHaveLength(3);
    expect(avisos).toEqual([{ usuario: DUENO, enviadosAntes: 0 }]);
  });

  it.each([
    ["sin sesión", { sesiones: [null] }, {}],
    ["otro usuario que el esperado", {}, { usuarioEsperado: OTRO }],
    ["getSession falla", { sesiones: ["lanzar" as const] }, {}],
    ["detenido", {}, { continuar: () => false }],
  ])("U10: no se invoca si no sale ningún intento (%s)", async (_caso, cli, opciones) => {
    const avisos: string[] = [];
    const { cliente, llamadas } = clienteFalso({ rpc: [{ data: OP, error: null }], ...cli });
    const r = await crearPuertoJornadas(cliente).ejecutar(COMANDOS[1].comando, CLAVE, {
      ...opciones,
      alFijarActor: (u) => avisos.push(u),
    });
    expect(llamadas).toHaveLength(0);
    expect(avisos).toEqual([]);
    expect(r).toMatchObject({ ok: false, intentos: 0 });
  });

  it("U11: el token sale sólo en la cabecera de la petición; no se guarda en el navegador ni en encabezados globales", () => {
    const codigo = fuenteJornadas.replace(/\/\/.*$/gm, "");
    expect(codigo).toMatch(/\.setHeader\("Authorization", `Bearer \$\{token\}`\)/);
    expect(codigo).not.toMatch(/localStorage|sessionStorage|indexedDB|console\./);
    expect(codigo).not.toMatch(/global\.headers|\.headers\s*=|setSession|setAuth/);
  });
});

// FE-2F (O-1): identidad vigente para atar la verificación a la intención.
describe("FE-2F: usuarioActual", () => {
  it("devuelve sólo el id del usuario de la sesión vigente", async () => {
    const { cliente } = clienteFalso({});
    expect(await crearPuertoJornadas(cliente).usuarioActual()).toBe(DUENO);
  });

  it("sin sesión o si getSession falla → null (falla cerrada), sin llamar a ninguna RPC ni tabla", async () => {
    const a = clienteFalso({ sesiones: [null] });
    expect(await crearPuertoJornadas(a.cliente).usuarioActual()).toBeNull();
    const b = clienteFalso({ sesiones: ["lanzar"] });
    expect(await crearPuertoJornadas(b.cliente).usuarioActual()).toBeNull();
    expect([...a.llamadas, ...b.llamadas, ...a.tablas, ...b.tablas]).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Lectura paginada. Base falsa en memoria que interpreta la cadena de consultas
// (select/eq/or/order/order/limit), aplica un tope `max_rows` como PostgREST y
// devuelve el conteo exacto. Cubre el contrato del cliente; no prueba RLS ni
// PostgREST reales (eso requiere un stack local autorizado).
// ---------------------------------------------------------------------------
type FilaBase = Record<string, unknown>;

const COLUMNAS =
  "id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id, creado_en";

function filaSintetica(n: number, fecha: string): FilaBase {
  const id = `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
  return {
    id, fecha, camion_id: CAMION, vendedor_id: VEND, estado: "abierta",
    abierta_por: DUENO, operacion_apertura_id: OP, creado_en: "2026-11-10T08:00:00+00:00",
  };
}

const FECHAS = ["2026-11-10", "2026-11-11", "2026-11-12"];

/** `total` filas repartidas en las fechas dadas (varias por fecha, ids únicos). */
function conjunto(total: number, fechas: string[] = FECHAS): FilaBase[] {
  return Array.from({ length: total }, (_, i) => filaSintetica(i + 1, fechas[i % fechas.length]));
}

function ordenEsperado(filas: FilaBase[]): FilaBase[] {
  return [...filas].sort((a, b) =>
    a.fecha !== b.fecha
      ? (a.fecha as string) < (b.fecha as string) ? 1 : -1
      : (a.id as string) < (b.id as string) ? 1 : -1
  );
}

interface Peticion {
  n: number;
  operaciones: Array<{ operacion: string; args: unknown[] }>;
  eq: string | null;
  cursor: { fecha: string; id: string } | null;
  limite: number;
}
type Responder = (p: Peticion, normal: { data: unknown; error: unknown; count: unknown }) =>
  { data: unknown; error: unknown; count: unknown } | "lanzar";

function clienteLectura(filas: FilaBase[], opciones: { maxRows?: number; responder?: Responder } = {}) {
  const peticiones: Peticion[] = [];
  const maxRows = opciones.maxRows ?? 1000;
  const cliente = {
    from(tabla: string) {
      expect(tabla).toBe("jornadas");
      const p: Peticion = { n: peticiones.length + 1, operaciones: [], eq: null, cursor: null, limite: -1 };
      const consulta: Record<string, unknown> = {};
      const anotar = (operacion: string, args: unknown[]) => p.operaciones.push({ operacion, args });
      consulta.select = (...args: unknown[]) => (anotar("select", args), consulta);
      consulta.eq = (...args: unknown[]) => {
        anotar("eq", args);
        p.eq = args[1] as string;
        return consulta;
      };
      consulta.or = (...args: unknown[]) => {
        anotar("or", args);
        const m = /^fecha\.lt\.([\d-]+),and\(fecha\.eq\.\1,id\.lt\.([0-9a-f-]+)\)$/i.exec(args[0] as string);
        if (m === null) throw new Error(`filtro or inesperado: ${String(args[0])}`);
        p.cursor = { fecha: m[1], id: m[2] };
        return consulta;
      };
      consulta.order = (...args: unknown[]) => (anotar("order", args), consulta);
      consulta.limit = (n: number) => {
        anotar("limit", [n]);
        p.limite = n;
        peticiones.push(p);
        const c = p.cursor;
        const coincide = filas.filter(
          (f) =>
            (p.eq === null || f.fecha === p.eq) &&
            (c === null || (f.fecha as string) < c.fecha || (f.fecha === c.fecha && (f.id as string) < c.id))
        );
        const normal = {
          data: ordenEsperado(coincide).slice(0, Math.min(n, maxRows)).map((f) => ({ ...f })),
          error: null,
          count: coincide.length,
        };
        const r = opciones.responder ? opciones.responder(p, normal) : normal;
        return r === "lanzar" ? Promise.reject(new Error("red")) : Promise.resolve(r);
      };
      return consulta;
    },
  };
  return { cliente: cliente as unknown as SupabaseClient, peticiones };
}

const ids = (xs: Array<FilaBase | { id: string }>) => xs.map((x) => x.id);

describe("crearPuertoJornadas.leerPaginaJornadas / leerTodasLasJornadas", () => {
  it("fecha y cursor coincidentes: la consulta se ejecuta con ambos filtros", async () => {
    const filas = conjunto(TAMANO_PAGINA_JORNADAS + 5, ["2026-11-10"]);
    const { cliente, peticiones } = clienteLectura(filas);
    const puerto = crearPuertoJornadas(cliente);
    const p1 = await puerto.leerPaginaJornadas({ fecha: "2026-11-10" });
    if (!p1.ok || p1.datos.siguiente === null) throw new Error("se esperaba continuación");
    const p2 = await puerto.leerPaginaJornadas({ fecha: "2026-11-10", despues: p1.datos.siguiente });
    expect(p2.ok).toBe(true);
    expect(peticiones).toHaveLength(2);
    expect(peticiones[1].eq).toBe("2026-11-10");
    expect(peticiones[1].cursor).toEqual(p1.datos.siguiente);
  });

  it("fecha y cursor distintos: rechaza con datos inválidos y SIN llamar a Supabase", async () => {
    const { cliente, peticiones } = clienteLectura(conjunto(5));
    const r = await crearPuertoJornadas(cliente).leerPaginaJornadas({
      fecha: "2026-11-10",
      despues: { fecha: "2026-11-11", id: filaSintetica(1, "x").id as string },
    });
    expect(r).toEqual({
      ok: false,
      intentos: 0,
      error: { codigo: null, mensaje: MENSAJE_DATOS_INVALIDOS, resultadoDesconocido: false },
    });
    expect(peticiones).toHaveLength(0);
  });

  it("cursor sin filtro de fecha: conserva el comportamiento (sin eq, con keyset)", async () => {
    const filas = conjunto(TAMANO_PAGINA_JORNADAS + 5);
    const { cliente, peticiones } = clienteLectura(filas);
    const puerto = crearPuertoJornadas(cliente);
    const p1 = await puerto.leerPaginaJornadas();
    if (!p1.ok || p1.datos.siguiente === null) throw new Error("se esperaba continuación");
    const p2 = await puerto.leerPaginaJornadas({ despues: p1.datos.siguiente });
    expect(p2.ok).toBe(true);
    expect(peticiones[1].eq).toBeNull();
    expect(peticiones[1].cursor).toEqual(p1.datos.siguiente);
  });

  it("leerTodasLasJornadas con filtro de fecha sigue paginando con fecha y cursor coincidentes", async () => {
    const filas = conjunto(1300, ["2026-11-10"]);
    const { cliente, peticiones } = clienteLectura(filas);
    const r = await crearPuertoJornadas(cliente).leerTodasLasJornadas({ fecha: "2026-11-10" });
    if (!r.ok) throw new Error("se esperaba éxito");
    expect(ids(r.datos)).toEqual(ids(ordenEsperado(filas)));
    expect(peticiones).toHaveLength(3);
    expect(peticiones.slice(1).every((p) => p.eq === "2026-11-10" && p.cursor?.fecha === "2026-11-10")).toBe(true);
  });

  it("el tamaño de página + 1 queda por debajo del tope de PostgREST (max_rows = 1000)", () => {
    expect(TAMANO_PAGINA_JORNADAS + 1).toBeLessThan(1000);
  });

  it("consulta con SELECT, conteo exacto, orden total (fecha desc, id desc) y límite de página + 1; sin escrituras", async () => {
    const { cliente, peticiones } = clienteLectura(conjunto(3));
    const r = await crearPuertoJornadas(cliente).leerPaginaJornadas({ fecha: "2026-11-10" });
    expect(r.ok).toBe(true);
    expect(peticiones).toHaveLength(1);
    expect(peticiones[0].operaciones).toEqual([
      { operacion: "select", args: [COLUMNAS, { count: "exact" }] },
      { operacion: "eq", args: ["fecha", "2026-11-10"] },
      { operacion: "order", args: ["fecha", { ascending: false }] },
      { operacion: "order", args: ["id", { ascending: false }] },
      { operacion: "limit", args: [TAMANO_PAGINA_JORNADAS + 1] },
    ]);
  });

  it("la continuación usa un filtro keyset por (fecha, id) del último elemento", async () => {
    const filas = conjunto(TAMANO_PAGINA_JORNADAS + 5);
    const { cliente, peticiones } = clienteLectura(filas);
    const puerto = crearPuertoJornadas(cliente);
    const p1 = await puerto.leerPaginaJornadas();
    if (!p1.ok || p1.datos.siguiente === null) throw new Error("se esperaba una continuación");
    const { fecha, id } = p1.datos.siguiente;
    expect({ fecha, id }).toEqual({
      fecha: p1.datos.jornadas.at(-1)?.fecha,
      id: p1.datos.jornadas.at(-1)?.id,
    });
    await puerto.leerPaginaJornadas({ despues: p1.datos.siguiente });
    expect(peticiones[1].operaciones.find((o) => o.operacion === "or")?.args).toEqual([
      `fecha.lt.${fecha},and(fecha.eq.${fecha},id.lt.${id})`,
    ]);
  });

  it("más de 1.000 jornadas: lee todas en 3 solicitudes, en orden, sin truncar ni repetir", async () => {
    const filas = conjunto(1250);
    const { cliente, peticiones } = clienteLectura(filas, { maxRows: 1000 });
    const r = await crearPuertoJornadas(cliente).leerTodasLasJornadas();
    if (!r.ok) throw new Error("se esperaba éxito");
    expect(r.datos).toHaveLength(1250);
    expect(ids(r.datos)).toEqual(ids(ordenEsperado(filas)));
    expect(new Set(ids(r.datos)).size).toBe(1250);
    expect(r.intentos).toBe(3);
    expect(peticiones).toHaveLength(3);
  });

  it("una página con continuación NO se presenta como el conjunto completo", async () => {
    const { cliente } = clienteLectura(conjunto(1250));
    const r = await crearPuertoJornadas(cliente).leerPaginaJornadas();
    if (!r.ok) throw new Error("se esperaba éxito");
    expect(r.datos.jornadas).toHaveLength(TAMANO_PAGINA_JORNADAS);
    expect(r.datos.siguiente).not.toBeNull();
  });

  it("varias jornadas con la misma fecha: el corte de página cae dentro de una fecha y no pierde ni repite filas", async () => {
    const filas = conjunto(1200, ["2026-11-10"]);
    const { cliente } = clienteLectura(filas);
    const puerto = crearPuertoJornadas(cliente);
    const p1 = await puerto.leerPaginaJornadas();
    if (!p1.ok || p1.datos.siguiente === null) throw new Error("se esperaba continuación");
    expect(p1.datos.siguiente.fecha).toBe("2026-11-10");
    const todas = await puerto.leerTodasLasJornadas();
    if (!todas.ok) throw new Error("se esperaba éxito");
    expect(ids(todas.datos)).toEqual(ids(ordenEsperado(filas)));
  });

  it("orden estable: fecha descendente y, dentro de la fecha, id descendente", async () => {
    const filas = conjunto(30);
    const { cliente } = clienteLectura(filas);
    const r = await crearPuertoJornadas(cliente).leerTodasLasJornadas();
    if (!r.ok) throw new Error("se esperaba éxito");
    for (let i = 1; i < r.datos.length; i++) {
      const a = r.datos[i - 1];
      const b = r.datos[i];
      expect(a.fecha > b.fecha || (a.fecha === b.fecha && a.id > b.id)).toBe(true);
    }
  });

  it("filtro por fecha + paginación: sólo esa fecha, completa", async () => {
    const filas = conjunto(1500);
    const { cliente } = clienteLectura(filas);
    const r = await crearPuertoJornadas(cliente).leerTodasLasJornadas({ fecha: "2026-11-11" });
    if (!r.ok) throw new Error("se esperaba éxito");
    expect(ids(r.datos)).toEqual(ids(ordenEsperado(filas.filter((f) => f.fecha === "2026-11-11"))));
  });

  it("página vacía: ok, sin filas y sin continuación", async () => {
    const { cliente } = clienteLectura([]);
    const puerto = crearPuertoJornadas(cliente);
    expect(await puerto.leerPaginaJornadas()).toEqual({ ok: true, intentos: 1, datos: { jornadas: [], siguiente: null } });
    expect(await puerto.leerTodasLasJornadas()).toEqual({ ok: true, intentos: 1, datos: [] });
  });

  it("última página: exactamente una página completa no genera continuación; una fila más sí y la siguiente cierra", async () => {
    const puertoDe = (n: number) => crearPuertoJornadas(clienteLectura(conjunto(n)).cliente);
    const exacta = await puertoDe(TAMANO_PAGINA_JORNADAS).leerPaginaJornadas();
    if (!exacta.ok) throw new Error("se esperaba éxito");
    expect(exacta.datos.jornadas).toHaveLength(TAMANO_PAGINA_JORNADAS);
    expect(exacta.datos.siguiente).toBeNull();

    const filas = conjunto(TAMANO_PAGINA_JORNADAS + 1);
    const puerto = crearPuertoJornadas(clienteLectura(filas).cliente);
    const p1 = await puerto.leerPaginaJornadas();
    if (!p1.ok || p1.datos.siguiente === null) throw new Error("se esperaba continuación");
    const p2 = await puerto.leerPaginaJornadas({ despues: p1.datos.siguiente });
    if (!p2.ok) throw new Error("se esperaba éxito");
    expect(p2.datos.jornadas).toHaveLength(1);
    expect(p2.datos.siguiente).toBeNull();
  });

  it("error en una página posterior: leerTodas falla sin devolver datos parciales", async () => {
    for (const falla of [
      { data: null, error: { code: "42501", message: "x" }, count: null },
      "lanzar" as const,
    ]) {
      const { cliente, peticiones } = clienteLectura(conjunto(1250), {
        responder: (p, normal) => (p.n === 2 ? falla : normal),
      });
      const r = await crearPuertoJornadas(cliente).leerTodasLasJornadas();
      expect(r.ok).toBe(false);
      if (r.ok) continue;
      expect(r.error.mensaje).toBe(MENSAJE_ERROR_LECTURA);
      expect(r.intentos).toBe(2);
      expect(peticiones).toHaveLength(2);
      expect("datos" in r).toBe(false);
    }
  });

  it("falla cerrado si el servidor devuelve menos filas que las pedidas (tope de max_rows menor al esperado)", async () => {
    const { cliente } = clienteLectura(conjunto(1250), { maxRows: 100 });
    const puerto = crearPuertoJornadas(cliente);
    expect((await puerto.leerPaginaJornadas()).ok).toBe(false);
    expect((await puerto.leerTodasLasJornadas()).ok).toBe(false);
  });

  it.each<[string, Responder]>([
    ["sin conteo", (_p, n) => ({ ...n, count: null })],
    ["conteo menor a las filas", (_p, n) => ({ ...n, count: 1 })],
    ["conteo mayor al devuelto", (_p, n) => ({ ...n, count: 9999 })],
    ["más filas que las pedidas", (p) => {
      const filas = ordenEsperado(conjunto(TAMANO_PAGINA_JORNADAS + 2));
      return { data: filas.slice(0, p.limite + 1), error: null, count: TAMANO_PAGINA_JORNADAS + 2 };
    }],
    ["filas fuera de orden", (_p, n) => ({ ...n, data: [...(n.data as FilaBase[])].reverse() })],
    ["fila repetida", (_p, n) => ({ ...n, data: [(n.data as FilaBase[])[0], (n.data as FilaBase[])[0], ...(n.data as FilaBase[]).slice(1)], count: (n.count as number) + 1 })],
    ["fila de otra fecha que el filtro", (_p, n) => ({ ...n, data: [filaSintetica(999, "2026-11-12"), ...(n.data as FilaBase[]).slice(1)] })],
    ["fila con estado inventado", (_p, n) => ({ ...n, data: [{ ...(n.data as FilaBase[])[0], estado: "inventado" }] })],
    ["data no es arreglo", (_p, n) => ({ ...n, data: { ...n } })],
  ])("respuesta inesperada (%s): falla cerrado", async (_nombre, responder) => {
    const { cliente } = clienteLectura(conjunto(8, ["2026-11-10"]), { responder });
    const r = await crearPuertoJornadas(cliente).leerPaginaJornadas({ fecha: "2026-11-10" });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.mensaje).toBe(MENSAJE_ERROR_LECTURA);
  });

  it("fila que no está después del cursor (fuera del rango pedido): falla cerrado", async () => {
    const filas = conjunto(5);
    const { cliente } = clienteLectura(filas, { responder: (_p, n) => ({ ...n, data: ordenEsperado(filas), count: 5 }) });
    const cursor = { fecha: "2026-11-10", id: filaSintetica(1, "x").id as string };
    const r = await crearPuertoJornadas(cliente).leerPaginaJornadas({ despues: cursor });
    expect(r.ok).toBe(false);
  });

  it("error en la primera página y excepciones: mensaje de lectura, sin detalle SQL", async () => {
    for (const falla of [{ data: null, error: { code: "42501", message: "permission denied for table jornadas" }, count: null }, "lanzar" as const]) {
      const { cliente } = clienteLectura([], { responder: () => falla });
      const r = await crearPuertoJornadas(cliente).leerPaginaJornadas();
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.error.mensaje).toBe(MENSAJE_ERROR_LECTURA);
    }
  });

  it("filtro o cursor inválido: rechaza sin consultar", async () => {
    const { cliente, peticiones } = clienteLectura([]);
    const puerto = crearPuertoJornadas(cliente);
    const idOk = filaSintetica(1, "x").id as string;
    for (const opciones of [
      { fecha: "10/11/2026" },
      { despues: { fecha: "2026-13-01", id: idOk } },
      { despues: { fecha: "2026-11-10", id: "x),id.gt.(" } },
      { despues: null as unknown as { fecha: string; id: string } },
    ]) {
      const r = await puerto.leerPaginaJornadas(opciones);
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.error.mensaje).toBe(MENSAJE_DATOS_INVALIDOS);
    }
    expect((await puerto.leerTodasLasJornadas({ fecha: "mañana" })).ok).toBe(false);
    expect(peticiones).toHaveLength(0);
  });

  it("modificación concurrente: una fila cuya fecha se corrige entre páginas se lee dos veces y se descarta el repetido por id", async () => {
    const filas = conjunto(TAMANO_PAGINA_JORNADAS + 3);
    const movida = ordenEsperado(filas)[0];
    const fechaOriginal = movida.fecha;
    const { cliente } = clienteLectura(filas, {
      // Tras responder la primera página, otra sesión corrige la fecha de la fila ya leída.
      responder: (p, normal) => {
        if (p.n === 1) queueMicrotask(() => { movida.fecha = "2026-11-01"; });
        return normal;
      },
    });
    const r = await crearPuertoJornadas(cliente).leerTodasLasJornadas();
    if (!r.ok) throw new Error("se esperaba éxito");
    expect(r.datos).toHaveLength(filas.length);
    expect(new Set(ids(r.datos)).size).toBe(filas.length);
    expect(r.datos.find((j) => j.id === movida.id)?.fecha).toBe(fechaOriginal);
  });

  it(`si se supera el tope de ${MAX_PAGINAS_JORNADAS} páginas, falla en lugar de devolver un listado parcial`, async () => {
    let contador = 1_000_000;
    const { cliente, peticiones } = clienteLectura([], {
      responder: () => {
        // Siempre una página llena y descendente (con una fila más: hay más datos).
        const data = Array.from({ length: TAMANO_PAGINA_JORNADAS + 1 }, () => filaSintetica(contador--, "2026-11-10"));
        return { data, error: null, count: TAMANO_PAGINA_JORNADAS + 1 };
      },
    });
    const r = await crearPuertoJornadas(cliente).leerTodasLasJornadas();
    expect(r.ok).toBe(false);
    expect(peticiones).toHaveLength(MAX_PAGINAS_JORNADAS);
  });
});

describe("filaAJornada", () => {
  it("convierte una fila válida y rechaza una fila con campos inválidos", () => {
    const fila = filaSintetica(1, "2026-11-10");
    expect(filaAJornada(fila)).toMatchObject({ id: fila.id, fecha: "2026-11-10", camionId: CAMION, estado: "abierta" });
    expect(filaAJornada({ ...fila, estado: "inventado" })).toBeNull();
    expect(filaAJornada({ ...fila, id: "x" })).toBeNull();
    expect(filaAJornada(null)).toBeNull();
  });
});

describe("nuevaClaveIdempotencia y ausencia de almacenamiento del navegador", () => {
  it("genera uuid distintos por intento lógico", () => {
    const a = nuevaClaveIdempotencia();
    const b = nuevaClaveIdempotencia();
    expect(a).not.toBe(b);
    expect(/^[0-9a-f-]{36}$/.test(a)).toBe(true);
  });

  it("el módulo no usa localStorage, sessionStorage ni IndexedDB", () => {
    const codigo = fuenteJornadas.replace(/\/\/.*$/gm, "");
    expect(/localStorage|sessionStorage|indexedDB/i.test(codigo)).toBe(false);
    expect(/\.(insert|update|upsert|delete)\(/.test(codigo)).toBe(false);
  });
});
