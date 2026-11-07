// Historial de cargas y descargas (B-02b.2 / S3-0): capa de datos, sólo
// lectura. El cliente falso emula el subconjunto de PostgREST que usa el
// módulo (select con conteo exacto, eq, in, or, gt, order por id, limit y un
// tope `max_rows`) sobre tablas en memoria, y registra cada petición.
import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import {
  MAX_PAGINAS_HISTORIAL,
  MENSAJE_ERROR_HISTORIAL,
  MENSAJE_JORNADA_NO_VISIBLE,
  TAMANO_LOTE_PRODUCTOS,
  TAMANO_PAGINA_MOVIMIENTOS,
  TAMANO_PAGINA_OPERACIONES,
  crearPuertoHistorialJornada,
} from "./jornadas_historial";

type Fila = Record<string, unknown>;
type Tablas = Record<string, Fila[]>;

interface Peticion {
  tabla: string;
  operaciones: Array<{ operacion: string; args: unknown[] }>;
}

type Respuesta = { data: unknown; error: unknown; count: unknown };
type Responder = (p: Peticion, normal: Respuesta) => Respuesta | "lanzar";

const uuid = (prefijo: string, n: number) =>
  `${prefijo}-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;

const E = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const E_OTRA = "ffffffff-ffff-4fff-8fff-ffffffffffff";
const J = "11111111-1111-4111-8111-111111111111";
const J_OTRA = "11111111-1111-4111-8111-222222222222";
const CAMION = "22222222-2222-4222-8222-222222222222";
const CAMION_OTRO = "22222222-2222-4222-8222-333333333333";
const DEPOSITO = "dddddddd-0000-4000-8000-000000000001";
const CUARENTENA = "dddddddd-0000-4000-8000-000000000002";
const UB_CAMION = "dddddddd-0000-4000-8000-000000000003";
const UB_CAMION_OTRO = "dddddddd-0000-4000-8000-000000000004";
const DUENO = "00000000-0000-4000-8000-000000000001";
const ENCARGADO = "00000000-0000-4000-8000-000000000002";
const P1 = "aaaaaaaa-0000-4000-8000-000000000001";
const P2 = "aaaaaaaa-0000-4000-8000-000000000002";
const OP1 = "bbbbbbbb-0000-4000-8000-000000000001";
// La descarga tiene un id MENOR que la carga pero ocurrió después: el orden
// visible es cronológico, no por id.
const OP_DESCARGA = "bbbbbbbb-0000-4000-8000-000000000000";
const OP_SALIDA = "bbbbbbbb-0000-4000-8000-000000000003";
const OP_OTRA_JORNADA = "bbbbbbbb-0000-4000-8000-000000000004";

function op(id: string, tipo: string, actor: string, creado: string, extra: Fila = {}): Fila {
  return { id, empresa_id: E, tipo, actor_id: actor, jornada_id: J, creado_en: creado, ...extra };
}

function mov(
  id: string,
  operacion: string,
  tipo: "carga" | "descarga",
  producto: string,
  cantidad: unknown,
  actor: string,
  extra: Fila = {}
): Fila {
  const carga = tipo === "carga";
  return {
    id,
    empresa_id: E,
    operacion_id: operacion,
    tipo_movimiento: tipo,
    producto_id: producto,
    cantidad,
    ubicacion_origen_id: carga ? DEPOSITO : UB_CAMION,
    ubicacion_destino_id: carga ? UB_CAMION : DEPOSITO,
    actor_id: actor,
    jornada_id: J,
    motivo: carga ? null : "Sobró mercadería",
    ...extra,
  };
}

function producto(id: string, nombre: string, forma: "unidad" | "peso", extra: Fila = {}): Fila {
  return { id, empresa_id: E, codigo: null, nombre, forma_venta: forma, activo: true, ...extra };
}

/** Datos base: una carga de dos productos (dueño) y una descarga (encargado). */
function base(): Tablas {
  return {
    jornadas: [
      { id: J, empresa_id: E, camion_id: CAMION },
      { id: J_OTRA, empresa_id: E, camion_id: CAMION_OTRO },
    ],
    ubicaciones: [
      { id: DEPOSITO, empresa_id: E, tipo: "deposito", camion_id: null },
      { id: CUARENTENA, empresa_id: E, tipo: "cuarentena", camion_id: null },
      { id: UB_CAMION, empresa_id: E, tipo: "camion", camion_id: CAMION },
      { id: UB_CAMION_OTRO, empresa_id: E, tipo: "camion", camion_id: CAMION_OTRO },
    ],
    operaciones: [
      op(OP_DESCARGA, "descarga", ENCARGADO, "2026-11-10T12:30:00.123456+00:00"),
      op(OP1, "carga", DUENO, "2026-11-10T11:00:00+00:00"),
      op(OP_SALIDA, "salida_jornada", DUENO, "2026-11-10T13:00:00+00:00"),
      op(OP_OTRA_JORNADA, "carga", DUENO, "2026-11-10T09:00:00+00:00", { jornada_id: J_OTRA }),
    ],
    movimientos_stock: [],
    productos: [producto(P1, "Leche entera", "unidad", { codigo: "L-1" }), producto(P2, "Jamón cocido", "peso")],
  };
}

function conMovimientos(t: Tablas): Tablas {
  t.movimientos_stock = [
    mov(uuid("cccccccc", 1), OP1, "carga", P1, 12, DUENO),
    mov(uuid("cccccccc", 2), OP1, "carga", P2, 1250, DUENO),
    mov(uuid("cccccccc", 3), OP_DESCARGA, "descarga", P2, 250, ENCARGADO),
    // Movimiento de otra jornada: el filtro eq lo excluye.
    mov(uuid("cccccccc", 4), OP_OTRA_JORNADA, "carga", P1, 1, DUENO, { jornada_id: J_OTRA }),
  ];
  return t;
}

function datos(): Tablas {
  return conMovimientos(base());
}

function cliente(tablas: Tablas, opciones: { maxRows?: number; responder?: Responder } = {}) {
  const peticiones: Peticion[] = [];
  const maxRows = opciones.maxRows ?? 1000;

  const falso = {
    from(tabla: string) {
      const p: Peticion = { tabla, operaciones: [] };
      peticiones.push(p);
      const filtros: Array<(f: Fila) => boolean> = [];
      let limite = Infinity;
      let ascendente = true;
      const anotar = (operacion: string, args: unknown[]) => p.operaciones.push({ operacion, args });

      const consulta = {
        select(...args: unknown[]) {
          anotar("select", args);
          return consulta;
        },
        eq(col: string, valor: unknown) {
          anotar("eq", [col, valor]);
          filtros.push((f) => f[col] === valor);
          return consulta;
        },
        in(col: string, valores: unknown[]) {
          anotar("in", [col, valores]);
          filtros.push((f) => valores.includes(f[col]));
          return consulta;
        },
        gt(col: string, valor: string) {
          anotar("gt", [col, valor]);
          filtros.push((f) => String(f[col]) > valor);
          return consulta;
        },
        or(expresion: string) {
          anotar("or", [expresion]);
          const partes = expresion.split(",").map((s) => {
            const [col, operador, ...resto] = s.split(".");
            if (operador !== "eq") throw new Error(`operador no emulado: ${operador}`);
            return { col, valor: resto.join(".") };
          });
          filtros.push((f) => partes.some(({ col, valor }) => String(f[col]) === valor));
          return consulta;
        },
        order(col: string, o: { ascending: boolean }) {
          anotar("order", [col, o]);
          if (col !== "id") throw new Error("orden no emulado");
          ascendente = o.ascending;
          return consulta;
        },
        limit(n: number) {
          anotar("limit", [n]);
          limite = n;
          return consulta;
        },
        then(resolver: (r: Respuesta) => unknown, rechazar: (e: unknown) => unknown) {
          const coincide = (tablas[tabla] ?? [])
            .filter((f) => filtros.every((fn) => fn(f)))
            .sort((a, b) => (String(a.id) < String(b.id) ? -1 : 1) * (ascendente ? 1 : -1));
          const normal: Respuesta = {
            data: coincide.slice(0, Math.min(limite, maxRows)),
            error: null,
            count: coincide.length,
          };
          const r = opciones.responder ? opciones.responder(p, normal) : normal;
          if (r === "lanzar") return Promise.reject(new Error("fallo de red")).then(resolver, rechazar);
          return Promise.resolve(r).then(resolver, rechazar);
        },
      };
      return consulta;
    },
  };

  return {
    puerto: crearPuertoHistorialJornada(falso as unknown as SupabaseClient),
    peticiones,
  };
}

async function leer(tablas: Tablas, opciones?: Parameters<typeof cliente>[1], jornada = J) {
  const c = cliente(tablas, opciones);
  return { r: await c.puerto.leerHistorial(jornada), peticiones: c.peticiones };
}

async function esperarFalla(tablas: Tablas, opciones?: Parameters<typeof cliente>[1]) {
  const { r } = await leer(tablas, opciones);
  expect(r).toEqual({ ok: false, error: MENSAJE_ERROR_HISTORIAL });
}

describe("historial de jornada: lectura correcta", () => {
  it("arma las operaciones de la jornada en orden cronológico con sus líneas y productos", async () => {
    const { r } = await leer(datos());
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const h = r.datos;
    expect(h.jornadaId).toBe(J);
    expect(h.operaciones.map((o) => [o.id, o.tipo, o.actorId, o.motivo])).toEqual([
      [OP1, "carga", DUENO, null],
      [OP_DESCARGA, "descarga", ENCARGADO, "Sobró mercadería"],
    ]);
    // Líneas ordenadas por nombre de producto; cantidades en unidad mínima.
    expect(h.operaciones[0].lineas.map((l) => [l.productoId, l.cantidad])).toEqual([
      [P2, 1250],
      [P1, 12],
    ]);
    expect(h.operaciones[1].lineas.map((l) => [l.productoId, l.cantidad])).toEqual([[P2, 250]]);
    expect(Object.keys(h.productos).sort()).toEqual([P1, P2]);
    expect(h.productos[P2]).toEqual({ id: P2, codigo: null, nombre: "Jamón cocido", formaVenta: "peso", activo: true });
  });

  it("excluye operaciones de otros tipos y de otras jornadas (filtros en la consulta)", async () => {
    const { r, peticiones } = await leer(datos());
    expect(r.ok && r.datos.operaciones.map((o) => o.id)).not.toContain(OP_SALIDA);
    const ops = peticiones.find((p) => p.tabla === "operaciones")!;
    expect(ops.operaciones).toEqual([
      { operacion: "select", args: ["id, empresa_id, tipo, actor_id, jornada_id, creado_en", { count: "exact" }] },
      { operacion: "eq", args: ["jornada_id", J] },
      { operacion: "in", args: ["tipo", ["carga", "descarga"]] },
      { operacion: "order", args: ["id", { ascending: true }] },
      { operacion: "limit", args: [TAMANO_PAGINA_OPERACIONES + 1] },
    ]);
    const movs = peticiones.find((p) => p.tabla === "movimientos_stock")!;
    expect(movs.operaciones.slice(1, 3)).toEqual([
      { operacion: "eq", args: ["jornada_id", J] },
      { operacion: "in", args: ["tipo_movimiento", ["carga", "descarga"]] },
    ]);
  });

  it("sólo lee: jornadas, ubicaciones, operaciones, movimientos y productos (sin perfiles ni RPC)", async () => {
    const { peticiones } = await leer(datos());
    expect(peticiones.map((p) => p.tabla)).toEqual([
      "jornadas",
      "ubicaciones",
      "operaciones",
      "movimientos_stock",
      "productos",
    ]);
    for (const p of peticiones) {
      expect(p.operaciones.map((o) => o.operacion).every((o) => ["select", "eq", "in", "or", "gt", "order", "limit"].includes(o))).toBe(true);
    }
  });

  it("la jornada sin cargas ni descargas devuelve un historial vacío (sin leer productos)", async () => {
    // Sólo quedan la salida y la carga de otra jornada: el filtro las excluye.
    const t = base();
    t.operaciones = t.operaciones.filter((o) => o.id === OP_SALIDA || o.id === OP_OTRA_JORNADA);
    const { r, peticiones } = await leer(t);
    expect(r).toEqual({ ok: true, datos: { jornadaId: J, operaciones: [], productos: {} } });
    expect(peticiones.some((p) => p.tabla === "productos")).toBe(false);
  });

  it("producto dado de baja: se lee y se conserva su estado", async () => {
    const t = datos();
    t.productos[1] = { ...t.productos[1], activo: false };
    const { r } = await leer(t);
    expect(r.ok && r.datos.productos[P2].activo).toBe(false);
  });
});

describe("historial de jornada: paginación", () => {
  it("recorre varias páginas de operaciones por keyset de id y no repite ni omite", async () => {
    const t = base();
    const total = TAMANO_PAGINA_OPERACIONES * 2 + 50;
    t.operaciones = [];
    t.movimientos_stock = [];
    for (let i = 1; i <= total; i++) {
      const id = uuid("bbbbbbbb", i);
      t.operaciones.push(op(id, "carga", DUENO, `2026-11-10T10:00:${String(i % 60).padStart(2, "0")}Z`));
      t.movimientos_stock.push(mov(uuid("cccccccc", i), id, "carga", P1, 1, DUENO));
    }
    const { r, peticiones } = await leer(t);
    expect(r.ok && r.datos.operaciones.length).toBe(total);
    const paginas = peticiones.filter((p) => p.tabla === "operaciones");
    expect(paginas).toHaveLength(3);
    expect(paginas[0].operaciones.some((o) => o.operacion === "gt")).toBe(false);
    expect(paginas[1].operaciones).toContainEqual({ operacion: "gt", args: ["id", uuid("bbbbbbbb", TAMANO_PAGINA_OPERACIONES)] });
    expect(paginas[2].operaciones).toContainEqual({ operacion: "gt", args: ["id", uuid("bbbbbbbb", TAMANO_PAGINA_OPERACIONES * 2)] });
    const movs = peticiones.filter((p) => p.tabla === "movimientos_stock");
    expect(movs).toHaveLength(1); // 450 < TAMANO_PAGINA_MOVIMIENTOS + 1
    expect(TAMANO_PAGINA_MOVIMIENTOS).toBeGreaterThan(total);
  });

  it("lee los productos en lotes acotados y exige exactamente los pedidos", async () => {
    const t = base();
    const cantidad = TAMANO_LOTE_PRODUCTOS + 20;
    t.productos = [];
    t.movimientos_stock = [];
    t.operaciones = [op(OP1, "carga", DUENO, "2026-11-10T11:00:00Z")];
    for (let i = 1; i <= cantidad; i++) {
      const p = uuid("aaaaaaaa", i);
      t.productos.push(producto(p, `Producto ${i}`, "unidad"));
      t.movimientos_stock.push(mov(uuid("cccccccc", i), OP1, "carga", p, i, DUENO));
    }
    const { r, peticiones } = await leer(t);
    expect(r.ok && r.datos.operaciones[0].lineas.length).toBe(cantidad);
    const lotes = peticiones.filter((p) => p.tabla === "productos");
    expect(lotes).toHaveLength(2);
    const largo = (p: Peticion) => (p.operaciones.find((o) => o.operacion === "in")!.args[1] as unknown[]).length;
    expect(lotes.map(largo)).toEqual([TAMANO_LOTE_PRODUCTOS, 20]);
  });

  it("tope de páginas: falla cerrada en lugar de devolver un historial parcial", async () => {
    // Cada página devuelve tamaño + 1 filas nuevas, sin fin.
    let contador = 0;
    await esperarFalla(base(), {
      responder: (p, n) => {
        if (p.tabla !== "operaciones") return n;
        const data = Array.from({ length: TAMANO_PAGINA_OPERACIONES + 1 }, () =>
          op(uuid("bbbbbbbb", ++contador), "carga", DUENO, "2026-11-10T11:00:00Z")
        );
        return { data, error: null, count: TAMANO_PAGINA_OPERACIONES + 1 };
      },
    });
    expect(contador).toBe(MAX_PAGINAS_HISTORIAL * (TAMANO_PAGINA_OPERACIONES + 1));
  });
});

describe("historial de jornada: respuestas incompletas o truncadas", () => {
  it("truncamiento por max_rows (conteo mayor que las filas recibidas)", async () => {
    const t = base();
    t.operaciones = [];
    t.movimientos_stock = [];
    for (let i = 1; i <= 120; i++) {
      t.operaciones.push(op(uuid("bbbbbbbb", i), "carga", DUENO, "2026-11-10T11:00:00Z"));
      t.movimientos_stock.push(mov(uuid("cccccccc", i), uuid("bbbbbbbb", i), "carga", P1, 1, DUENO));
    }
    await esperarFalla(t, { maxRows: 100 });
  });

  const fallasDeTamano: Array<[string, Responder]> = [
    ["sin conteo", (p, n) => (p.tabla === "operaciones" ? { ...n, count: null } : n)],
    ["conteo menor que las filas", (p, n) => (p.tabla === "movimientos_stock" ? { ...n, count: 1 } : n)],
    ["conteo mayor que lo devuelto", (p, n) => (p.tabla === "operaciones" ? { ...n, count: 9999 } : n)],
    ["data no es un arreglo", (p, n) => (p.tabla === "productos" ? { ...n, data: {} } : n)],
    ["ubicaciones truncadas", (p, n) => (p.tabla === "ubicaciones" ? { ...n, data: (n.data as Fila[]).slice(0, 1) } : n)],
  ];
  it.each(fallasDeTamano)("%s → falla cerrada", async (_n, responder) => {
    await esperarFalla(datos(), { responder });
  });

  const fallasDeOrden: Array<[string, Responder]> = [
    ["operaciones fuera de orden", (p, n) => (p.tabla === "operaciones" ? { ...n, data: [...(n.data as Fila[])].reverse() } : n)],
    [
      "operación repetida",
      (p, n) => {
        if (p.tabla !== "operaciones") return n;
        const d = n.data as Fila[];
        return { data: [d[0], ...d], error: null, count: (n.count as number) + 1 };
      },
    ],
    ["movimientos fuera de orden", (p, n) => (p.tabla === "movimientos_stock" ? { ...n, data: [...(n.data as Fila[])].reverse() } : n)],
    [
      "producto repetido en la respuesta",
      (p, n) => {
        if (p.tabla !== "productos") return n;
        const d = n.data as Fila[];
        return { data: [d[0], d[0]], error: null, count: 2 };
      },
    ],
  ];
  it.each(fallasDeOrden)("%s → falla cerrada", async (_n, responder) => {
    await esperarFalla(datos(), { responder });
  });

  it.each(["jornadas", "ubicaciones", "operaciones", "movimientos_stock", "productos"])(
    "error de PostgREST en %s → mensaje seguro, sin detalle",
    async (tabla) => {
      const { r } = await leer(datos(), {
        responder: (p, n) =>
          p.tabla === tabla
            ? { data: null, error: { code: "42501", message: `permission denied for table ${tabla}` }, count: null }
            : n,
      });
      expect(r).toEqual({ ok: false, error: MENSAJE_ERROR_HISTORIAL });
      expect(JSON.stringify(r)).not.toMatch(/permission|42501|SQL|PGRST/);
    }
  );

  it("excepción de red → falla cerrada", async () => {
    await esperarFalla(datos(), { responder: (p, n) => (p.tabla === "movimientos_stock" ? "lanzar" : n) });
  });
});

describe("historial de jornada: pertenencia y permisos", () => {
  it("jornada no visible (inexistente, de otra empresa o sin permiso) → mensaje específico", async () => {
    const { r, peticiones } = await leer(datos(), undefined, "11111111-1111-4111-8111-999999999999");
    expect(r).toEqual({ ok: false, error: MENSAJE_JORNADA_NO_VISIBLE });
    expect(peticiones.map((p) => p.tabla)).toEqual(["jornadas"]);
  });

  it("id de jornada inválido → no consulta nada", async () => {
    const { r, peticiones } = await leer(datos(), undefined, "no-es-uuid");
    expect(r).toEqual({ ok: false, error: MENSAJE_ERROR_HISTORIAL });
    expect(peticiones).toHaveLength(0);
  });

  it("perfil sin acceso a ubicaciones (p. ej. inactivo) → falla cerrada, nunca vacío", async () => {
    const t = datos();
    t.ubicaciones = [];
    await esperarFalla(t);
  });

  it("RLS que no devuelve operaciones ni movimientos → historial vacío (límite conocido: sólo gestión ve el panel)", async () => {
    const t = datos();
    t.operaciones = [];
    t.movimientos_stock = [];
    const { r } = await leer(t);
    expect(r.ok && r.datos.operaciones).toEqual([]);
  });

  const filasAjenas: Array<[string, (t: Tablas) => void]> = [
    ["jornada con empresa_id inválido",(t) => (t.jornadas[0] = { ...t.jornadas[0], empresa_id: "x" })],
    ["ubicación de otra empresa", (t) => (t.ubicaciones[0] = { ...t.ubicaciones[0], empresa_id: E_OTRA })],
    ["dos depósitos", (t) => t.ubicaciones.push({ id: "dddddddd-0000-4000-8000-000000000009", empresa_id: E, tipo: "deposito", camion_id: null })],
    ["sin ubicación del camión", (t) => (t.ubicaciones = t.ubicaciones.filter((u) => u.id !== UB_CAMION))],
    ["operación de otra empresa", (t) => (t.operaciones[1] = { ...t.operaciones[1], empresa_id: E_OTRA })],
    ["movimiento de otra empresa", (t) => (t.movimientos_stock[0] = { ...t.movimientos_stock[0], empresa_id: E_OTRA })],
    ["producto de otra empresa", (t) => (t.productos[0] = { ...t.productos[0], empresa_id: E_OTRA })],
  ];
  it.each(filasAjenas)("%s → falla cerrada", async (_n, mutar) => {
    const t = datos();
    mutar(t);
    await esperarFalla(t);
  });

  it("una fila de otra jornada que llega pese al filtro → falla cerrada", async () => {
    await esperarFalla(datos(), {
      responder: (p, n) => {
        if (p.tabla !== "movimientos_stock") return n;
        const d = (n.data as Fila[]).map((f, i) => (i === 0 ? { ...f, jornada_id: J_OTRA } : f));
        return { ...n, data: d };
      },
    });
  });
});

describe("historial de jornada: coherencia entre operaciones y movimientos", () => {
  const incoherencias: Array<[string, (t: Tablas) => void]> = [
    ["movimiento de una operación no leída", (t) => (t.movimientos_stock[0] = { ...t.movimientos_stock[0], operacion_id: OP_SALIDA })],
    ["operación sin movimientos", (t) => (t.movimientos_stock = t.movimientos_stock.filter((m) => m.operacion_id !== OP_DESCARGA))],
    ["tipo del movimiento distinto del de su operación", (t) => (t.movimientos_stock[2] = { ...t.movimientos_stock[2], tipo_movimiento: "carga", ubicacion_origen_id: DEPOSITO, ubicacion_destino_id: UB_CAMION, motivo: null })],
    ["actor del movimiento distinto del de su operación", (t) => (t.movimientos_stock[0] = { ...t.movimientos_stock[0], actor_id: ENCARGADO })],
    ["producto repetido en una operación", (t) => (t.movimientos_stock[1] = { ...t.movimientos_stock[1], producto_id: P1 })],
    ["carga desde el camión (sentido invertido)", (t) => (t.movimientos_stock[0] = { ...t.movimientos_stock[0], ubicacion_origen_id: UB_CAMION, ubicacion_destino_id: DEPOSITO })],
    ["carga hacia otro camión", (t) => (t.movimientos_stock[0] = { ...t.movimientos_stock[0], ubicacion_destino_id: UB_CAMION_OTRO })],
    ["carga desde la cuarentena", (t) => (t.movimientos_stock[0] = { ...t.movimientos_stock[0], ubicacion_origen_id: CUARENTENA })],
    ["descarga hacia otro destino", (t) => (t.movimientos_stock[2] = { ...t.movimientos_stock[2], ubicacion_destino_id: CUARENTENA })],
    ["carga con motivo", (t) => (t.movimientos_stock[0] = { ...t.movimientos_stock[0], motivo: "x" })],
    ["descarga sin motivo", (t) => (t.movimientos_stock[2] = { ...t.movimientos_stock[2], motivo: null })],
    ["descarga con motivo en blanco", (t) => (t.movimientos_stock[2] = { ...t.movimientos_stock[2], motivo: "  " })],
    [
      "descarga con motivos distintos entre líneas",
      (t) => t.movimientos_stock.push(mov(uuid("cccccccc", 9), OP_DESCARGA, "descarga", P1, 1, ENCARGADO, { motivo: "Otro motivo" })),
    ],
    ["producto ausente", (t) => (t.productos = t.productos.filter((p) => p.id !== P2))],
    ["cantidad cero", (t) => (t.movimientos_stock[0] = { ...t.movimientos_stock[0], cantidad: 0 })],
    ["cantidad fraccionaria", (t) => (t.movimientos_stock[0] = { ...t.movimientos_stock[0], cantidad: 1.5 })],
    ["cantidad como texto", (t) => (t.movimientos_stock[0] = { ...t.movimientos_stock[0], cantidad: "12" })],
    ["cantidad mayor que integer", (t) => (t.movimientos_stock[0] = { ...t.movimientos_stock[0], cantidad: 2147483648 })],
    ["fecha de operación inválida", (t) => (t.operaciones[1] = { ...t.operaciones[1], creado_en: "ayer" })],
    ["forma de venta desconocida", (t) => (t.productos[0] = { ...t.productos[0], forma_venta: "pieza" })],
    ["producto sin nombre", (t) => (t.productos[0] = { ...t.productos[0], nombre: " " })],
  ];
  it.each(incoherencias)("%s → falla cerrada", async (_n, mutar) => {
    const t = datos();
    mutar(t);
    await esperarFalla(t);
  });

  it("cantidad límite 2147483647 y peso en gramos enteros se aceptan tal cual", async () => {
    const t = datos();
    t.movimientos_stock[0] = { ...t.movimientos_stock[0], cantidad: 2147483647 };
    const { r } = await leer(t);
    expect(r.ok && r.datos.operaciones[0].lineas.find((l) => l.productoId === P1)?.cantidad).toBe(2147483647);
  });
});
