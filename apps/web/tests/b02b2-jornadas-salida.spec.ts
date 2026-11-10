// B-02b.2 / S1 — E2E de «Confirmar salida» en la pantalla REAL de jornadas.
//
// Backend real (Supabase local con supabase/seed.sql): la base decide roles,
// estados y carga neta; RLS decide las filas. Cada caso siembra su propia
// jornada `cargada` por la Data API (camión nuevo, fecha futura aleatoria,
// ingreso y carga por RPC) y verifica el estado REAL en la base después de
// operar desde la interfaz. Nada aquí toca staging ni producción.
import { randomInt, randomUUID } from "node:crypto";

import {
  expect,
  test,
  type APIRequestContext,
  type Browser,
  type BrowserContextOptions,
  type Page,
  type Request,
} from "@playwright/test";

import { CUENTAS, PASSWORD_PRUEBA } from "./auth/cuentasPrueba";

// Los encabezados llevan tokens de sesión de prueba: sin trazas ni capturas.
test.use({ trace: "off", screenshot: "off", video: "off" });

const ID_DUENO = "00000000-0000-4000-8000-000000000001";
const ID_ENCARGADO = "00000000-0000-4000-8000-000000000002";
const ID_VENDEDOR = "00000000-0000-4000-8000-000000000003";

interface DataApi {
  url: string;
  apikey: string;
  tokenDueno: string;
}

async function dataApiDesdeApp(page: Page): Promise<DataApi> {
  const solicitud = page.waitForRequest((r) => r.url().includes("/rest/v1/productos"));
  await page.goto("/productos");
  const r = await solicitud;
  const h = await r.allHeaders();
  return {
    url: new URL(r.url()).origin,
    apikey: h["apikey"],
    tokenDueno: h["authorization"].replace(/^Bearer /, ""),
  };
}

async function tokenDe(request: APIRequestContext, api: DataApi, usuario: string) {
  const r = await request.post(`${api.url}/auth/v1/token?grant_type=password`, {
    headers: { apikey: api.apikey },
    data: { email: `${usuario}@usuarios.distribuidora.invalid`, password: PASSWORD_PRUEBA },
  });
  expect(r.ok()).toBe(true);
  return ((await r.json()) as { access_token: string }).access_token;
}

const cabeceras = (api: DataApi, token: string) => ({
  apikey: api.apikey,
  "content-type": "application/json",
  authorization: `Bearer ${token}`,
});

async function rpc(request: APIRequestContext, api: DataApi, token: string, nombre: string, data: object) {
  return request.post(`${api.url}/rest/v1/rpc/${nombre}`, { headers: cabeceras(api, token), data });
}

function fechaFutura() {
  const hoy = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Argentina/Tucuman" }).format(new Date());
  const d = new Date(`${hoy}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + randomInt(1, 2_000_000));
  return d.toISOString().slice(0, 10);
}

interface JornadaSembrada {
  id: string;
  fecha: string;
  camion: string; // nombre visible y único
  producto: string | null; // producto cargado (null si no se cargó)
}

/** Jornada `cargada` (o sólo `abierta` si `cargar` es false) para el vendedor de prueba. */
async function sembrarJornada(
  request: APIRequestContext,
  api: DataApi,
  etiqueta: string,
  cargar = true
): Promise<JornadaSembrada> {
  const t = api.tokenDueno;
  const camion = `S1-${etiqueta}-${randomUUID().slice(0, 8)}`;
  const rc = await rpc(request, api, t, "crear_camion", {
    p_patente: `S1-${randomUUID().slice(0, 12)}`,
    p_nombre: camion,
  });
  expect(rc.status()).toBe(200);
  const camionId = (await rc.json()) as string;
  const fecha = fechaFutura();
  const ra = await rpc(request, api, t, "abrir_jornada", {
    p_idempotency_key: randomUUID(), p_camion_id: camionId, p_fecha: fecha, p_vendedor_id: ID_VENDEDOR,
  });
  expect(ra.status()).toBe(200);
  const id = (await ra.json()) as string;
  let productoCargado: string | null = null;
  if (cargar) {
    const rp = await request.get(
      `${api.url}/rest/v1/productos?select=id&activo=eq.true&forma_venta=eq.unidad&order=id&limit=1`,
      { headers: cabeceras(api, t) }
    );
    const [{ id: producto }] = (await rp.json()) as Array<{ id: string }>;
    const ri = await rpc(request, api, t, "registrar_ingreso", {
      p_idempotency_key: randomUUID(), p_producto_id: producto, p_cantidad: 3, p_motivo: "E2E S1",
    });
    expect(ri.status()).toBe(200);
    const rg = await rpc(request, api, t, "registrar_carga", {
      p_idempotency_key: randomUUID(), p_jornada_id: id, p_productos: [producto], p_cantidades: [1],
    });
    expect(rg.status()).toBe(200);
    productoCargado = producto;
  }
  return { id, fecha, camion, producto: productoCargado };
}

async function estadoEnBase(request: APIRequestContext, api: DataApi, jornadaId: string) {
  const r = await request.get(`${api.url}/rest/v1/jornadas?select=estado&id=eq.${jornadaId}`, {
    headers: cabeceras(api, api.tokenDueno),
  });
  expect(r.status()).toBe(200);
  return ((await r.json()) as Array<{ estado: string }>)[0]?.estado;
}

/** Operaciones de salida de la jornada (leídas como dueño): actor incluido. */
async function salidasDe(request: APIRequestContext, api: DataApi, jornadaId: string) {
  const r = await request.get(
    `${api.url}/rest/v1/operaciones?select=id,actor_id&tipo=eq.salida_jornada&jornada_id=eq.${jornadaId}`,
    { headers: cabeceras(api, api.tokenDueno) }
  );
  expect(r.status()).toBe(200);
  return (await r.json()) as Array<{ id: string; actor_id: string }>;
}

async function salidasEnBase(request: APIRequestContext, api: DataApi, jornadaId: string) {
  return (await salidasDe(request, api, jornadaId)).length;
}

async function entrarComo(browser: Browser, baseURL: string | undefined, usuario: string, opciones: BrowserContextOptions = {}) {
  const contexto = await browser.newContext({ baseURL, storageState: { cookies: [], origins: [] }, ...opciones });
  const page = await contexto.newPage();
  await page.goto("/login");
  await page.getByLabel("Usuario").fill(usuario);
  await page.getByLabel("Contraseña").fill(PASSWORD_PRUEBA);
  await page.getByRole("button", { name: "Ingresar al sistema" }).click();
  await expect(page.locator("aside")).toBeVisible();
  return { page, contexto };
}

/** Abre /jornadas filtrado por la fecha y el detalle de la jornada sembrada. */
async function abrirDetalle(page: Page, j: JornadaSembrada) {
  await page.goto("/jornadas");
  await page.getByLabel("Fecha operativa").fill(j.fecha);
  const fila = page.locator("table tbody tr").filter({ hasText: j.camion });
  await expect(fila).toHaveCount(1);
  await fila.getByRole("button", { name: "Ver detalle" }).click();
  const detalle = page.getByRole("region", { name: "Detalle de la jornada" });
  await expect(detalle).toContainText(j.camion);
  return { fila, detalle };
}

/** Solicitudes del navegador a la Data API (sin el login de Auth). */
function registrarSolicitudes(page: Page, api: DataApi) {
  const solicitudes: Request[] = [];
  page.on("request", (r) => {
    if (r.url().startsWith(api.url) && !r.url().includes("/auth/v1/")) solicitudes.push(r);
  });
  const mutadoras = () => solicitudes.filter((r) => !["GET", "HEAD", "OPTIONS"].includes(r.method()));
  return { solicitudes, mutadoras };
}

test.describe("confirmar salida (backend real)", () => {
  test("el dueño confirma la salida: la base queda en reparto, persiste y sólo se llamó a confirmar_salida", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "dueno");
    expect(await estadoEnBase(request, api, j.id)).toBe("cargada");

    const red = registrarSolicitudes(page, api);
    const { fila, detalle } = await abrirDetalle(page, j);
    await detalle.getByRole("button", { name: "Confirmar salida" }).click();
    await expect(detalle.getByRole("group")).toContainText(`¿Confirmás la salida de ${j.camion}`);
    await detalle.getByRole("button", { name: "Sí, confirmar salida" }).click();
    await expect(page.getByRole("status").filter({ hasText: "Salida confirmada" })).toBeVisible();
    await expect(fila).toContainText("En reparto");

    // Estado REAL en la base y una sola operación de salida, registrada por el dueño.
    expect(await estadoEnBase(request, api, j.id)).toBe("en_reparto");
    const salidas = await salidasDe(request, api, j.id);
    expect(salidas.map((s) => s.actor_id)).toEqual([ID_DUENO]);

    // Ninguna escritura directa: la única solicitud mutadora es la RPC.
    const mutadoras = red.mutadoras();
    expect(mutadoras.map((r) => `${r.method()} ${new URL(r.url()).pathname}`)).toEqual([
      "POST /rest/v1/rpc/confirmar_salida",
    ]);
    expect(mutadoras[0].postDataJSON()).toEqual({
      p_idempotency_key: expect.stringMatching(/^[0-9a-f-]{36}$/),
      p_jornada_id: j.id,
    });

    // Persiste tras recargar; ya no se ofrece confirmar.
    await page.reload();
    const tras = await abrirDetalle(page, j);
    await expect(tras.fila).toContainText("En reparto");
    await expect(tras.detalle.getByRole("button", { name: "Confirmar salida" })).toBeDisabled();
  });

  test("el encargado también confirma la salida", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "enc");
    const enc = await entrarComo(browser, baseURL, CUENTAS.encargado);
    const { detalle } = await abrirDetalle(enc.page, j);
    await detalle.getByRole("button", { name: "Confirmar salida" }).click();
    await detalle.getByRole("button", { name: "Sí, confirmar salida" }).click();
    await expect(enc.page.getByRole("status").filter({ hasText: "Salida confirmada" })).toBeVisible();
    expect(await estadoEnBase(request, api, j.id)).toBe("en_reparto");
    // La operación la registró el encargado (actor de la sesión), no el dueño que sembró.
    expect((await salidasDe(request, api, j.id)).map((s) => s.actor_id)).toEqual([ID_ENCARGADO]);
    await enc.contexto.close();
  });

  test("doble clic con respuesta lenta: una sola solicitud y una sola operación", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "doble");
    // La respuesta real llega con 1,5 s de demora: tiempo de sobra para el doble clic.
    await page.route("**/rest/v1/rpc/confirmar_salida", async (route) => {
      const respuesta = await route.fetch();
      await new Promise((r) => setTimeout(r, 1500));
      await route.fulfill({ response: respuesta });
    });
    const red = registrarSolicitudes(page, api);
    const { detalle } = await abrirDetalle(page, j);
    await detalle.getByRole("button", { name: "Confirmar salida" }).click();
    await detalle.getByRole("button", { name: "Sí, confirmar salida" }).dblclick();
    await expect(detalle.getByRole("button", { name: /Confirmando salida/ })).toBeDisabled();
    await expect(page.getByRole("status").filter({ hasText: "Salida confirmada" })).toBeVisible();

    expect(red.mutadoras()).toHaveLength(1);
    expect(await salidasEnBase(request, api, j.id)).toBe(1);
    expect(await estadoEnBase(request, api, j.id)).toBe("en_reparto");
  });

  // S1-C3 (Codex, revisión 1): pérdida SIN efecto en la base. El navegador
  // nunca llega al servidor; la verificación devuelve `cargada`, se ofrece el
  // reintento visible y se completa con la MISMA clave: una sola operación.
  test("pérdida sin efecto: verifica «cargada», reintento visible con la misma clave y una sola operación", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "reint");
    let cortar = true;
    await page.route("**/rest/v1/rpc/confirmar_salida", async (route) => {
      if (cortar) await route.abort("failed"); // nunca llega a PostgreSQL
      else await route.continue();
    });
    const red = registrarSolicitudes(page, api);
    const { fila, detalle } = await abrirDetalle(page, j);
    await detalle.getByRole("button", { name: "Confirmar salida" }).click();
    await detalle.getByRole("button", { name: "Sí, confirmar salida" }).click();
    await expect(detalle.getByRole("alert")).toContainText("la jornada sigue cargada");
    const reintento = detalle.getByRole("button", { name: "Reintentar confirmación" });
    await expect(reintento).toBeVisible();

    // Sin efectos todavía: la base sigue igual.
    expect(await estadoEnBase(request, api, j.id)).toBe("cargada");
    expect(await salidasEnBase(request, api, j.id)).toBe(0);

    cortar = false;
    await reintento.click();
    await expect(page.getByRole("status").filter({ hasText: "Salida confirmada" })).toBeVisible();
    await expect(fila).toContainText("En reparto");

    const envios = red.mutadoras();
    expect(envios.length).toBeGreaterThanOrEqual(2); // los cortados + el reintento
    expect(new Set(envios.map((r) => new URL(r.url()).pathname))).toEqual(new Set(["/rest/v1/rpc/confirmar_salida"]));
    const claves = new Set(envios.map((r) => (r.postDataJSON() as { p_idempotency_key: string }).p_idempotency_key));
    expect(claves.size).toBe(1);
    expect(await salidasEnBase(request, api, j.id)).toBe(1);
    expect(await estadoEnBase(request, api, j.id)).toBe("en_reparto");
  });

  test("carga neta cero: rechazo seguro, sin efectos en la base", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "neta0");
    // Descarga todo lo cargado: la jornada sigue `cargada` pero sin carga neta.
    const rd = await rpc(request, api, api.tokenDueno, "registrar_descarga", {
      p_idempotency_key: randomUUID(), p_jornada_id: j.id,
      p_productos: [j.producto as string], p_cantidades: [1], p_motivo: "E2E S1 neta cero",
    });
    expect(rd.status()).toBe(200);
    expect(await estadoEnBase(request, api, j.id)).toBe("cargada");

    const { detalle } = await abrirDetalle(page, j);
    await detalle.getByRole("button", { name: "Confirmar salida" }).click();
    await detalle.getByRole("button", { name: "Sí, confirmar salida" }).click();
    // El rechazo se anuncia fuera del detalle (AvisoSalidaJornada, S1-C5).
    await expect(page.getByRole("alert").filter({ hasText: "carga neta" })).toHaveText(
      "El camión no tiene carga neta: no se puede confirmar la salida."
    );
    expect(await estadoEnBase(request, api, j.id)).toBe("cargada");
    expect(await salidasEnBase(request, api, j.id)).toBe(0);
  });

  test("vista móvil (393×851): tarjetas, control táctil, sin scroll horizontal y salida confirmada", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "movil");
    const m = await entrarComo(browser, baseURL, CUENTAS.dueno, {
      viewport: { width: 393, height: 851 }, hasTouch: true, isMobile: true,
    });
    await m.page.goto("/jornadas");
    await m.page.getByLabel("Fecha operativa").fill(j.fecha);
    await expect(m.page.locator("table")).toBeHidden();
    const tarjeta = m.page.locator("ul.md\\:hidden > li").filter({ hasText: j.camion });
    await expect(tarjeta).toHaveCount(1);
    await tarjeta.getByRole("button", { name: "Ver detalle" }).click();
    const detalle = m.page.getByRole("region", { name: "Detalle de la jornada" });
    const boton = detalle.getByRole("button", { name: "Confirmar salida" });
    expect((await boton.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
    await boton.click();
    const si = detalle.getByRole("button", { name: "Sí, confirmar salida" });
    expect((await si.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
    expect(await m.page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
    await si.click();
    await expect(m.page.getByRole("status").filter({ hasText: "Salida confirmada" })).toBeVisible();
    expect(await estadoEnBase(request, api, j.id)).toBe("en_reparto");
    expect(await salidasEnBase(request, api, j.id)).toBe(1);
    await m.contexto.close();
  });

  test("respuesta perdida: consulta el estado real, informa la salida registrada y no la duplica", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "perdida");
    // El servidor SÍ procesa cada solicitud, pero el navegador nunca recibe la respuesta.
    await page.route("**/rest/v1/rpc/confirmar_salida", async (route) => {
      await route.fetch();
      await route.abort("failed");
    });
    const red = registrarSolicitudes(page, api);
    const { fila, detalle } = await abrirDetalle(page, j);
    await detalle.getByRole("button", { name: "Confirmar salida" }).click();
    await detalle.getByRole("button", { name: "Sí, confirmar salida" }).click();
    await expect(page.getByRole("status").filter({ hasText: "La salida quedó registrada" })).toBeVisible();
    await expect(fila).toContainText("En reparto");

    // Los reintentos automáticos de la capa B-02a usan SIEMPRE la misma clave.
    const envios = red.mutadoras();
    expect(envios.length).toBeGreaterThanOrEqual(1);
    // Todos los envíos son la misma RPC (ninguna escritura directa ni otra operación).
    expect(new Set(envios.map((r) => `${r.method()} ${new URL(r.url()).pathname}`))).toEqual(
      new Set(["POST /rest/v1/rpc/confirmar_salida"])
    );
    const claves = new Set(envios.map((r) => (r.postDataJSON() as { p_idempotency_key: string }).p_idempotency_key));
    expect(claves.size).toBe(1);
    expect(await salidasEnBase(request, api, j.id)).toBe(1);
    expect(await estadoEnBase(request, api, j.id)).toBe("en_reparto");
  });
});

test.describe("roles no autorizados (backend real)", () => {
  test("el vendedor asignado no ve la acción y la base rechaza su intento directo", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "vend");
    const v = await entrarComo(browser, baseURL, CUENTAS.vendedor);
    await v.page.goto("/jornadas");
    await expect(v.page.getByRole("heading", { name: "Mi jornada" })).toBeVisible();
    await v.page.getByLabel("Fecha operativa").fill(j.fecha);
    const fila = v.page.locator("table tbody tr").filter({ hasText: j.camion });
    await expect(fila).toHaveCount(1);
    await fila.getByRole("button", { name: "Ver detalle" }).click();
    await expect(v.page.getByRole("region", { name: "Detalle de la jornada" })).toBeVisible();
    await expect(v.page.getByRole("button", { name: /Confirmar salida/ })).toHaveCount(0);
    await v.contexto.close();

    // Aunque llamara a la RPC por su cuenta, el servidor lo rechaza sin efectos.
    const tokenVendedor = await tokenDe(request, api, CUENTAS.vendedor);
    const r = await rpc(request, api, tokenVendedor, "confirmar_salida", {
      p_idempotency_key: randomUUID(), p_jornada_id: j.id,
    });
    expect(r.status()).toBe(403);
    expect(await r.json()).toMatchObject({ code: "PT403", message: "jornada_no_autorizado" });
    expect(await estadoEnBase(request, api, j.id)).toBe("cargada");
    expect(await salidasEnBase(request, api, j.id)).toBe(0);
  });

  test("otra empresa: la jornada no es visible para el dueño de B y su intento directo se rechaza sin efectos", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "otraemp");
    const otra = await entrarComo(browser, baseURL, CUENTAS.otraEmpresa);
    await otra.page.goto("/jornadas");
    await otra.page.getByLabel("Fecha operativa").fill(j.fecha);
    await expect(otra.page.locator('p[aria-live="polite"]')).toHaveText(/^No hay jornadas el /);
    await expect(otra.page.getByText(j.camion)).toHaveCount(0);
    await expect(otra.page.getByRole("button", { name: /Confirmar salida/ })).toHaveCount(0);
    await otra.contexto.close();

    const tokenOtra = await tokenDe(request, api, CUENTAS.otraEmpresa);
    const r = await rpc(request, api, tokenOtra, "confirmar_salida", {
      p_idempotency_key: randomUUID(), p_jornada_id: j.id,
    });
    expect(r.status()).toBe(404);
    expect(await r.json()).toMatchObject({ code: "PT404", message: "jornada_no_encontrada" });
    expect(await estadoEnBase(request, api, j.id)).toBe("cargada");
    expect(await salidasEnBase(request, api, j.id)).toBe(0);
  });

  test("una jornada abierta (sin carga) no ofrece confirmar la salida", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "abierta", false);
    const red = registrarSolicitudes(page, api);
    const { detalle } = await abrirDetalle(page, j);
    await expect(detalle.getByRole("button", { name: "Confirmar salida" })).toBeDisabled();
    await expect(detalle).toContainText("Sólo se puede confirmar la salida de una jornada cargada");
    expect(red.mutadoras()).toEqual([]);
    expect(await estadoEnBase(request, api, j.id)).toBe("abierta");
  });
});
