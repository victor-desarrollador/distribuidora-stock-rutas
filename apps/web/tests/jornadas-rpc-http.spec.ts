// abrir_jornada y reasignar_vendedor por la Data API real (PostgREST de
// Supabase local): método HTTP, idempotencia, permisos y concurrencia.
//
// Corrección extraordinaria T1/T2 (ADR-001 §6 y §16 T14; migración
// 20261104120000_jornadas_rpc_rechazo_solo_lectura.sql): PostgREST ejecuta GET
// y HEAD en una transacción READ ONLY, y la RPC la rechaza al comienzo con
// SQLSTATE 25006 `jornada_metodo_no_permitido`, que PostgREST traduce a 405.
// Antes, un GET/HEAD con una idempotency_key ya usada respondía 200 con el uuid
// guardado. POST conserva su comportamiento.
//
// Requisitos: Supabase local con el seed de supabase/seed.sql. La prueba de
// service_role necesita E2E_SUPABASE_SECRET_KEY (la clave secreta del stack
// LOCAL, de `supabase status -o env`); sin ella falla, no se omite. Ningún
// token, contraseña ni clave se imprime.
//
// Cada prueba crea su propio camión y usa fechas futuras aleatorias para que
// el par (vendedor, fecha) no choque entre pruebas paralelas ni entre corridas.
import { randomInt, randomUUID } from "node:crypto";

import {
  expect,
  test,
  type APIRequestContext,
  type APIResponse,
  type Page,
} from "@playwright/test";

import { CUENTAS, PASSWORD_PRUEBA } from "./auth/cuentasPrueba";

// H-03 (security review): sin artefactos de Playwright en este archivo (trazas,
// capturas ni videos). Son opciones por worker, así que van a nivel de archivo;
// no cambian la política global de playwright.config.ts. Además, la clave
// secreta de service_role viaja sólo por el fetch nativo (conClaveSecreta), que
// Playwright no registra aunque se fuerce `--trace on`.
test.use({ trace: "off", screenshot: "off", video: "off" });

// Perfiles del seed local (supabase/seed.sql), todos de la empresa principal.
const ID_DUENO = "00000000-0000-4000-8000-000000000001";
const ID_ENCARGADO = "00000000-0000-4000-8000-000000000002";
const ID_VENDEDOR = "00000000-0000-4000-8000-000000000003";

interface DataApi {
  url: string;
  apikey: string;
  tokenDueno: string;
}

// Toma la URL y la clave pública de la solicitud que hace la app al leer el
// catálogo (no se leen archivos .env).
async function dataApiDesdeApp(page: Page): Promise<DataApi> {
  const solicitud = page.waitForRequest((r) =>
    r.url().includes("/rest/v1/productos")
  );
  await page.goto("/productos");
  const r = await solicitud;
  const h = await r.allHeaders();
  return {
    url: new URL(r.url()).origin,
    apikey: h["apikey"],
    tokenDueno: h["authorization"].replace(/^Bearer /, ""),
  };
}

async function tokenDe(
  request: APIRequestContext,
  api: DataApi,
  usuario: string
) {
  const r = await request.post(`${api.url}/auth/v1/token?grant_type=password`, {
    headers: { apikey: api.apikey },
    data: {
      email: `${usuario}@usuarios.distribuidora.invalid`,
      password: PASSWORD_PRUEBA,
    },
  });
  expect(r.ok()).toBe(true);
  return ((await r.json()) as { access_token: string }).access_token;
}

function encabezados(api: DataApi, token?: string, extra = {}) {
  return {
    apikey: api.apikey,
    "content-type": "application/json",
    ...(token ? { authorization: `Bearer ${token}` } : {}),
    ...extra,
  };
}

// Fecha futura aleatoria (día operativo de Tucumán + 1 a ~2 000 000 días; el
// año queda por debajo de 9999).
function fechaFutura() {
  const hoy = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Argentina/Tucuman",
  }).format(new Date());
  const d = new Date(`${hoy}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + randomInt(1, 2_000_000));
  return d.toISOString().slice(0, 10);
}

async function crearCamion(request: APIRequestContext, api: DataApi) {
  const r = await request.post(`${api.url}/rest/v1/rpc/crear_camion`, {
    headers: encabezados(api, api.tokenDueno),
    data: { p_patente: `HTTP-${randomUUID().slice(0, 13)}`, p_nombre: "HTTP" },
  });
  expect(r.status()).toBe(200);
  return (await r.json()) as string;
}

type Params = Record<string, string>;

function aperturaParams(clave: string, camion: string, fecha: string, vendedor: string): Params {
  return {
    p_idempotency_key: clave,
    p_camion_id: camion,
    p_fecha: fecha,
    p_vendedor_id: vendedor,
  };
}

function reasignacionParams(clave: string, jornada: string, vendedor: string): Params {
  return { p_idempotency_key: clave, p_jornada_id: jornada, p_vendedor_id: vendedor };
}

function rpcUrl(api: DataApi, rpc: string, params?: Params) {
  const q = params ? `?${new URLSearchParams(params).toString()}` : "";
  return `${api.url}/rest/v1/rpc/${rpc}${q}`;
}

function post(request: APIRequestContext, api: DataApi, rpc: string, params: Params, token?: string) {
  return request.post(rpcUrl(api, rpc), {
    headers: encabezados(api, token),
    data: params,
  });
}

function get(request: APIRequestContext, api: DataApi, rpc: string, params: Params, token?: string) {
  return request.get(rpcUrl(api, rpc, params), { headers: encabezados(api, token) });
}

function head(request: APIRequestContext, api: DataApi, rpc: string, params: Params, token?: string) {
  return request.head(rpcUrl(api, rpc, params), { headers: encabezados(api, token) });
}

async function esperarError(r: APIResponse, status: number, code: string, message?: string) {
  expect(r.status()).toBe(status);
  const cuerpo = (await r.json()) as { code: string; message: string };
  expect(cuerpo.code).toBe(code);
  if (message !== undefined) expect(cuerpo.message).toBe(message);
  return cuerpo;
}

// El 405 del contrato: código estable y sin el texto interno de PostgreSQL.
async function esperar405(r: APIResponse) {
  await esperarError(r, 405, "25006", "jornada_metodo_no_permitido");
}

async function esperarUuid(r: APIResponse) {
  expect(r.status()).toBe(200);
  const v = (await r.json()) as string;
  expect(v).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  return v;
}

async function jornadasDelCamion(request: APIRequestContext, api: DataApi, camion: string) {
  const r = await request.get(
    `${api.url}/rest/v1/jornadas?select=id,vendedor_id,operacion_apertura_id&camion_id=eq.${camion}`,
    { headers: encabezados(api, api.tokenDueno) }
  );
  expect(r.status()).toBe(200);
  return (await r.json()) as { id: string; vendedor_id: string; operacion_apertura_id: string }[];
}

async function operacionesConClave(request: APIRequestContext, api: DataApi, clave: string) {
  const r = await request.get(
    `${api.url}/rest/v1/operaciones?select=id,tipo&idempotency_key=eq.${clave}`,
    { headers: encabezados(api, api.tokenDueno) }
  );
  expect(r.status()).toBe(200);
  return (await r.json()) as { id: string; tipo: string }[];
}

async function reasignacionesDe(request: APIRequestContext, api: DataApi, jornada: string) {
  const r = await request.get(
    `${api.url}/rest/v1/reasignaciones_vendedor?select=operacion_id,vendedor_nuevo_id&jornada_id=eq.${jornada}`,
    { headers: encabezados(api, api.tokenDueno) }
  );
  expect(r.status()).toBe(200);
  return (await r.json()) as { operacion_id: string; vendedor_nuevo_id: string }[];
}

// Abre una jornada por POST y devuelve su id.
async function abrir(request: APIRequestContext, api: DataApi, camion: string, fecha: string, vendedor = ID_VENDEDOR) {
  return esperarUuid(
    await post(request, api, "abrir_jornada", aperturaParams(randomUUID(), camion, fecha, vendedor), api.tokenDueno)
  );
}

test.describe("abrir_jornada por HTTP", () => {
  test("POST nuevo, repetido y con otra huella; GET/HEAD siempre 405", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api);
    const otroCamion = await crearCamion(request, api);
    const fecha = fechaFutura();
    const clave = randomUUID();
    const params = aperturaParams(clave, camion, fecha, ID_VENDEDOR);

    // GET y HEAD con clave nueva: 405 y la clave no queda reservada.
    await esperar405(await get(request, api, "abrir_jornada", params, api.tokenDueno));
    expect((await head(request, api, "abrir_jornada", params, api.tokenDueno)).status()).toBe(405);
    expect(await operacionesConClave(request, api, clave)).toEqual([]);
    expect(await jornadasDelCamion(request, api, camion)).toEqual([]);

    // POST nuevo: la jornada, ligada a su operación.
    const jornada = await esperarUuid(await post(request, api, "abrir_jornada", params, api.tokenDueno));
    const [fila] = await jornadasDelCamion(request, api, camion);
    expect(fila).toMatchObject({ id: jornada, vendedor_id: ID_VENDEDOR });
    const ops = await operacionesConClave(request, api, clave);
    expect(ops).toEqual([{ id: fila.operacion_apertura_id, tipo: "apertura_jornada" }]);

    // POST repetido: mismo uuid, sin efectos nuevos.
    expect(await esperarUuid(await post(request, api, "abrir_jornada", params, api.tokenDueno))).toBe(jornada);

    // POST con la misma clave y otros parámetros: 409.
    await esperarError(
      await post(request, api, "abrir_jornada", aperturaParams(clave, otroCamion, fecha, ID_VENDEDOR), api.tokenDueno),
      409, "PT409", "jornada_conflicto_idempotencia"
    );

    // GET/HEAD con la clave ya usada (misma huella y otra huella): 405.
    await esperar405(await get(request, api, "abrir_jornada", params, api.tokenDueno));
    await esperar405(
      await get(request, api, "abrir_jornada", aperturaParams(clave, otroCamion, fecha, ID_VENDEDOR), api.tokenDueno)
    );
    await esperar405(
      await get(request, api, "abrir_jornada", aperturaParams(clave, camion, fecha, ID_ENCARGADO), api.tokenDueno)
    );
    expect((await head(request, api, "abrir_jornada", params, api.tokenDueno)).status()).toBe(405);
    expect(
      (await head(request, api, "abrir_jornada", aperturaParams(clave, otroCamion, fecha, ID_VENDEDOR), api.tokenDueno)).status()
    ).toBe(405);

    // Nada cambió y el POST posterior sigue devolviendo el uuid original.
    expect(await jornadasDelCamion(request, api, camion)).toHaveLength(1);
    expect(await jornadasDelCamion(request, api, otroCamion)).toEqual([]);
    expect(await operacionesConClave(request, api, clave)).toHaveLength(1);
    expect(await esperarUuid(await post(request, api, "abrir_jornada", params, api.tokenDueno))).toBe(jornada);
  });

  test("roles y otra empresa: POST según permisos, GET/HEAD 405 para authenticated, anon 401", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api);
    const fecha = fechaFutura();
    const [tokenEncargado, tokenVendedor, tokenOtra] = await Promise.all([
      tokenDe(request, api, CUENTAS.encargado),
      tokenDe(request, api, CUENTAS.vendedor),
      tokenDe(request, api, CUENTAS.otraEmpresa),
    ]);

    // Encargado: GET 405 y POST correcto.
    const claveE = randomUUID();
    const paramsE = aperturaParams(claveE, camion, fecha, ID_VENDEDOR);
    await esperar405(await get(request, api, "abrir_jornada", paramsE, tokenEncargado));
    expect((await head(request, api, "abrir_jornada", paramsE, tokenEncargado)).status()).toBe(405);
    const jornada = await esperarUuid(await post(request, api, "abrir_jornada", paramsE, tokenEncargado));
    await esperar405(await get(request, api, "abrir_jornada", paramsE, tokenEncargado));

    // Vendedor: POST 403; GET 405 (la guarda precede a la autorización).
    const paramsV = aperturaParams(randomUUID(), camion, fecha, ID_VENDEDOR);
    await esperarError(await post(request, api, "abrir_jornada", paramsV, tokenVendedor), 403, "PT403", "jornada_no_autorizado");
    await esperar405(await get(request, api, "abrir_jornada", paramsV, tokenVendedor));
    expect((await head(request, api, "abrir_jornada", paramsV, tokenVendedor)).status()).toBe(405);

    // Otra empresa con el camión de la principal: POST 404; GET 405, también
    // con la clave del encargado.
    const paramsB = aperturaParams(randomUUID(), camion, fecha, ID_VENDEDOR);
    await esperarError(await post(request, api, "abrir_jornada", paramsB, tokenOtra), 404, "PT404", "jornada_camion_no_encontrado");
    await esperar405(await get(request, api, "abrir_jornada", paramsB, tokenOtra));
    await esperar405(await get(request, api, "abrir_jornada", paramsE, tokenOtra));

    // anon (sólo la clave pública): sin EXECUTE, 401 en POST, GET y HEAD.
    await esperarError(await post(request, api, "abrir_jornada", paramsE), 401, "42501");
    await esperarError(await get(request, api, "abrir_jornada", paramsE), 401, "42501");
    expect((await head(request, api, "abrir_jornada", paramsE)).status()).toBe(401);

    // Sin efectos ajenos: una sola jornada (la del encargado) y una operación.
    expect((await jornadasDelCamion(request, api, camion)).map((j) => j.id)).toEqual([jornada]);
    expect(await operacionesConClave(request, api, claveE)).toHaveLength(1);
    expect(await operacionesConClave(request, api, paramsV.p_idempotency_key)).toEqual([]);
  });

  test("reintentos concurrentes: misma clave, claves distintas y GET simultáneo con POST", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);

    // Misma clave y mismos parámetros, 6 POST simultáneos: un solo efecto.
    const camion1 = await crearCamion(request, api);
    const params1 = aperturaParams(randomUUID(), camion1, fechaFutura(), ID_VENDEDOR);
    const iguales = await Promise.all(
      Array.from({ length: 6 }, () => post(request, api, "abrir_jornada", params1, api.tokenDueno))
    );
    const uuids = await Promise.all(iguales.map(esperarUuid));
    expect(new Set(uuids).size).toBe(1);
    expect(await jornadasDelCamion(request, api, camion1)).toHaveLength(1);
    expect(await operacionesConClave(request, api, params1.p_idempotency_key)).toHaveLength(1);

    // Claves distintas, mismo camión y fecha, 6 POST simultáneos: una confirma.
    const camion2 = await crearCamion(request, api);
    const fecha2 = fechaFutura();
    const distintas = await Promise.all(
      Array.from({ length: 6 }, () =>
        post(request, api, "abrir_jornada", aperturaParams(randomUUID(), camion2, fecha2, ID_VENDEDOR), api.tokenDueno)
      )
    );
    const ok = distintas.filter((r) => r.status() === 200);
    expect(ok).toHaveLength(1);
    for (const r of distintas.filter((x) => x.status() !== 200)) {
      const cuerpo = await esperarError(r, 409, "PT409");
      // K10 a): el contrato no fija precedencia entre estos dos códigos.
      expect(["jornada_duplicada", "jornada_camion_con_jornada_abierta"]).toContain(cuerpo.message);
    }
    expect(await jornadasDelCamion(request, api, camion2)).toHaveLength(1);

    // GET y HEAD simultáneos con el POST de la misma clave: los GET/HEAD
    // siempre 405, el POST confirma y el reintento devuelve lo mismo.
    const camion3 = await crearCamion(request, api);
    const params3 = aperturaParams(randomUUID(), camion3, fechaFutura(), ID_VENDEDOR);
    const [rPost, rHead, ...rGets] = await Promise.all([
      post(request, api, "abrir_jornada", params3, api.tokenDueno),
      head(request, api, "abrir_jornada", params3, api.tokenDueno),
      get(request, api, "abrir_jornada", params3, api.tokenDueno),
      get(request, api, "abrir_jornada", params3, api.tokenDueno),
      get(request, api, "abrir_jornada", params3, api.tokenDueno),
    ]);
    const jornada3 = await esperarUuid(rPost);
    expect(rHead.status()).toBe(405);
    for (const r of rGets) await esperar405(r);
    await esperar405(await get(request, api, "abrir_jornada", params3, api.tokenDueno));
    expect(await esperarUuid(await post(request, api, "abrir_jornada", params3, api.tokenDueno))).toBe(jornada3);
    expect(await jornadasDelCamion(request, api, camion3)).toHaveLength(1);
  });
});

test.describe("reasignar_vendedor por HTTP", () => {
  test("POST nuevo, repetido y con otra huella; GET/HEAD siempre 405", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api);
    const jornada = await abrir(request, api, camion, fechaFutura());
    const otraJornada = await abrir(request, api, await crearCamion(request, api), fechaFutura());
    const clave = randomUUID();
    const params = reasignacionParams(clave, jornada, ID_ENCARGADO);

    await esperar405(await get(request, api, "reasignar_vendedor", params, api.tokenDueno));
    expect((await head(request, api, "reasignar_vendedor", params, api.tokenDueno)).status()).toBe(405);
    expect(await operacionesConClave(request, api, clave)).toEqual([]);
    expect(await reasignacionesDe(request, api, jornada)).toEqual([]);

    const operacion = await esperarUuid(await post(request, api, "reasignar_vendedor", params, api.tokenDueno));
    expect(await reasignacionesDe(request, api, jornada)).toEqual([
      { operacion_id: operacion, vendedor_nuevo_id: ID_ENCARGADO },
    ]);
    expect(await operacionesConClave(request, api, clave)).toEqual([{ id: operacion, tipo: "reasignacion_vendedor" }]);

    expect(await esperarUuid(await post(request, api, "reasignar_vendedor", params, api.tokenDueno))).toBe(operacion);
    await esperarError(
      await post(request, api, "reasignar_vendedor", reasignacionParams(clave, jornada, ID_DUENO), api.tokenDueno),
      409, "PT409", "jornada_conflicto_idempotencia"
    );
    await esperarError(
      await post(request, api, "reasignar_vendedor", reasignacionParams(clave, otraJornada, ID_ENCARGADO), api.tokenDueno),
      409, "PT409", "jornada_conflicto_idempotencia"
    );

    await esperar405(await get(request, api, "reasignar_vendedor", params, api.tokenDueno));
    await esperar405(await get(request, api, "reasignar_vendedor", reasignacionParams(clave, jornada, ID_DUENO), api.tokenDueno));
    await esperar405(await get(request, api, "reasignar_vendedor", reasignacionParams(clave, otraJornada, ID_ENCARGADO), api.tokenDueno));
    expect((await head(request, api, "reasignar_vendedor", params, api.tokenDueno)).status()).toBe(405);
    expect(
      (await head(request, api, "reasignar_vendedor", reasignacionParams(clave, jornada, ID_DUENO), api.tokenDueno)).status()
    ).toBe(405);

    // Nada cambió: la jornada conserva el vendedor de la única reasignación.
    const [ap] = await jornadasDelCamion(request, api, camion);
    expect(ap.vendedor_id).toBe(ID_ENCARGADO);

    expect(await reasignacionesDe(request, api, jornada)).toHaveLength(1);
    expect(await reasignacionesDe(request, api, otraJornada)).toEqual([]);
    expect(await esperarUuid(await post(request, api, "reasignar_vendedor", params, api.tokenDueno))).toBe(operacion);
  });

  test("roles y otra empresa: POST según permisos, GET/HEAD 405 para authenticated, anon 401", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const jornada = await abrir(request, api, await crearCamion(request, api), fechaFutura());
    const [tokenEncargado, tokenVendedor, tokenOtra] = await Promise.all([
      tokenDe(request, api, CUENTAS.encargado),
      tokenDe(request, api, CUENTAS.vendedor),
      tokenDe(request, api, CUENTAS.otraEmpresa),
    ]);

    const claveE = randomUUID();
    const paramsE = reasignacionParams(claveE, jornada, ID_ENCARGADO);
    await esperar405(await get(request, api, "reasignar_vendedor", paramsE, tokenEncargado));
    expect((await head(request, api, "reasignar_vendedor", paramsE, tokenEncargado)).status()).toBe(405);
    const operacion = await esperarUuid(await post(request, api, "reasignar_vendedor", paramsE, tokenEncargado));
    await esperar405(await get(request, api, "reasignar_vendedor", paramsE, tokenEncargado));

    const paramsV = reasignacionParams(randomUUID(), jornada, ID_VENDEDOR);
    await esperarError(await post(request, api, "reasignar_vendedor", paramsV, tokenVendedor), 403, "PT403", "jornada_no_autorizado");
    await esperar405(await get(request, api, "reasignar_vendedor", paramsV, tokenVendedor));
    expect((await head(request, api, "reasignar_vendedor", paramsV, tokenVendedor)).status()).toBe(405);

    const paramsB = reasignacionParams(randomUUID(), jornada, ID_VENDEDOR);
    await esperarError(await post(request, api, "reasignar_vendedor", paramsB, tokenOtra), 404, "PT404", "jornada_no_encontrada");
    await esperar405(await get(request, api, "reasignar_vendedor", paramsB, tokenOtra));
    await esperar405(await get(request, api, "reasignar_vendedor", paramsE, tokenOtra));

    await esperarError(await post(request, api, "reasignar_vendedor", paramsE), 401, "42501");
    await esperarError(await get(request, api, "reasignar_vendedor", paramsE), 401, "42501");
    expect((await head(request, api, "reasignar_vendedor", paramsE)).status()).toBe(401);

    expect(await reasignacionesDe(request, api, jornada)).toEqual([
      { operacion_id: operacion, vendedor_nuevo_id: ID_ENCARGADO },
    ]);
    expect(await operacionesConClave(request, api, paramsV.p_idempotency_key)).toEqual([]);
    expect(await operacionesConClave(request, api, paramsB.p_idempotency_key)).toEqual([]);
  });

  test("reintentos concurrentes: misma clave, claves distintas y GET simultáneo con POST", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);

    const j1 = await abrir(request, api, await crearCamion(request, api), fechaFutura());
    const params1 = reasignacionParams(randomUUID(), j1, ID_ENCARGADO);
    const iguales = await Promise.all(
      Array.from({ length: 6 }, () => post(request, api, "reasignar_vendedor", params1, api.tokenDueno))
    );
    const uuids = await Promise.all(iguales.map(esperarUuid));
    expect(new Set(uuids).size).toBe(1);
    expect(await reasignacionesDe(request, api, j1)).toHaveLength(1);
    expect(await operacionesConClave(request, api, params1.p_idempotency_key)).toHaveLength(1);

    // Claves distintas hacia el mismo vendedor nuevo: una confirma; el resto
    // ve el vendedor ya cambiado (sin cambios) o el valor de bloqueo cambiado.
    const j2 = await abrir(request, api, await crearCamion(request, api), fechaFutura());
    const distintas = await Promise.all(
      Array.from({ length: 6 }, () =>
        post(request, api, "reasignar_vendedor", reasignacionParams(randomUUID(), j2, ID_ENCARGADO), api.tokenDueno)
      )
    );
    expect(distintas.filter((r) => r.status() === 200)).toHaveLength(1);
    for (const r of distintas.filter((x) => x.status() !== 200)) {
      const cuerpo = await esperarError(r, 409, "PT409");
      expect(["jornada_sin_cambios", "jornada_estado_invalido"]).toContain(cuerpo.message);
    }
    expect(await reasignacionesDe(request, api, j2)).toHaveLength(1);

    const j3 = await abrir(request, api, await crearCamion(request, api), fechaFutura());
    const params3 = reasignacionParams(randomUUID(), j3, ID_ENCARGADO);
    const [rPost, rHead, ...rGets] = await Promise.all([
      post(request, api, "reasignar_vendedor", params3, api.tokenDueno),
      head(request, api, "reasignar_vendedor", params3, api.tokenDueno),
      get(request, api, "reasignar_vendedor", params3, api.tokenDueno),
      get(request, api, "reasignar_vendedor", params3, api.tokenDueno),
      get(request, api, "reasignar_vendedor", params3, api.tokenDueno),
    ]);
    const operacion3 = await esperarUuid(rPost);
    expect(rHead.status()).toBe(405);
    for (const r of rGets) await esperar405(r);
    await esperar405(await get(request, api, "reasignar_vendedor", params3, api.tokenDueno));
    expect(await esperarUuid(await post(request, api, "reasignar_vendedor", params3, api.tokenDueno))).toBe(operacion3);
    expect(await reasignacionesDe(request, api, j3)).toHaveLength(1);
  });
});

test.describe("superficie de la Data API de jornadas", () => {
  test("Content-Profile/Accept-Profile privado no alcanza las implementaciones", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api);
    const params = aperturaParams(randomUUID(), camion, fechaFutura(), ID_VENDEDOR);

    for (const [rpc, p] of [
      ["abrir_jornada", params],
      ["reasignar_vendedor", reasignacionParams(randomUUID(), randomUUID(), ID_VENDEDOR)],
    ] as const) {
      const rPost = await request.post(rpcUrl(api, rpc), {
        headers: encabezados(api, api.tokenDueno, { "content-profile": "privado" }),
        data: p,
      });
      await esperarError(rPost, 406, "PGRST106");
      const rGet = await request.get(rpcUrl(api, rpc, p), {
        headers: encabezados(api, api.tokenDueno, { "accept-profile": "privado" }),
      });
      await esperarError(rGet, 406, "PGRST106");
    }
    expect(await jornadasDelCamion(request, api, camion)).toEqual([]);
    expect(await operacionesConClave(request, api, params.p_idempotency_key)).toEqual([]);
  });
});

// Solicitud con la clave secreta LOCAL por el fetch nativo de Node, no por el
// `request` de Playwright: así la clave no entra en trazas, adjuntos ni en el
// contexto de error de Playwright, aunque se fuerce `--trace on`. Sólo se
// devuelven el estado y el cuerpo; nunca los encabezados.
async function conClaveSecreta(
  secreta: string,
  metodo: "GET" | "HEAD" | "POST",
  url: string,
  cuerpo?: Params
) {
  const r = await fetch(url, {
    method: metodo,
    headers: { apikey: secreta, "content-type": "application/json" },
    body: cuerpo ? JSON.stringify(cuerpo) : undefined,
  });
  const texto = metodo === "HEAD" ? "" : await r.text();
  return {
    status: r.status,
    cuerpo: texto ? (JSON.parse(texto) as { code?: string }) : null,
  };
}

test.describe("service_role sobre la Data API de jornadas", () => {
  test("service_role: sin EXECUTE en POST, GET y HEAD (P11)", async ({ page, request }) => {
    const secreta = process.env.E2E_SUPABASE_SECRET_KEY;
    expect(Boolean(secreta), "definí E2E_SUPABASE_SECRET_KEY con la clave secreta del stack local").toBe(true);
    const clave = secreta as string;
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api);
    const jornada = await abrir(request, api, camion, fechaFutura());

    // Control: la clave es la de service_role (única excepción P11: SELECT de productos).
    const control = await conClaveSecreta(clave, "GET", `${api.url}/rest/v1/productos?select=id&limit=1`);
    expect(control.status).toBe(200);

    const apertura = aperturaParams(randomUUID(), camion, fechaFutura(), ID_VENDEDOR);
    const reasignacion = reasignacionParams(randomUUID(), jornada, ID_ENCARGADO);
    for (const [rpc, p] of [
      ["abrir_jornada", apertura],
      ["reasignar_vendedor", reasignacion],
    ] as const) {
      const rPost = await conClaveSecreta(clave, "POST", rpcUrl(api, rpc), p);
      expect([rPost.status, rPost.cuerpo?.code]).toEqual([403, "42501"]);
      const rGet = await conClaveSecreta(clave, "GET", rpcUrl(api, rpc, p));
      expect([rGet.status, rGet.cuerpo?.code]).toEqual([403, "42501"]);
      const rHead = await conClaveSecreta(clave, "HEAD", rpcUrl(api, rpc, p));
      expect(rHead.status).toBe(403);
    }
    expect(await jornadasDelCamion(request, api, camion)).toHaveLength(1);
    expect(await reasignacionesDe(request, api, jornada)).toEqual([]);
  });
});
