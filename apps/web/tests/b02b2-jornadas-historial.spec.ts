// B-02b.2 / S3-0 — E2E del historial de cargas y descargas (SÓLO LECTURA) en
// la pantalla REAL de jornadas.
//
// PREPARADO, NO EJECUTADO: requiere un laboratorio aislado autorizado
// (Supabase local con supabase/seed.sql). Cada caso siembra su propia jornada
// por la Data API (camión nuevo, fecha futura aleatoria, ingreso, carga y
// descarga por RPC, como dueño) y verifica lo que muestra la interfaz contra la
// base. La interfaz NO escribe: ningún caso espera solicitudes mutadoras desde
// el navegador. Nada aquí toca staging ni producción.
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

const ID_VENDEDOR = "00000000-0000-4000-8000-000000000003";
const TITULO = "Cargas y descargas registradas";

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

async function primerProducto(request: APIRequestContext, api: DataApi, forma: "unidad" | "peso") {
  const r = await request.get(
    `${api.url}/rest/v1/productos?select=id,nombre&activo=eq.true&forma_venta=eq.${forma}&order=id&limit=1`,
    { headers: cabeceras(api, api.tokenDueno) }
  );
  expect(r.status()).toBe(200);
  const [p] = (await r.json()) as Array<{ id: string; nombre: string }>;
  expect(p).toBeDefined();
  return p;
}

interface JornadaSembrada {
  id: string;
  fecha: string;
  camion: string; // nombre visible y único
  unidad: { id: string; nombre: string } | null;
  peso: { id: string; nombre: string } | null;
}

/**
 * Jornada para el vendedor de prueba. Con `movimientos`, registra (como dueño)
 * una carga de 3 unidades y 1,250 kg y una descarga de 0,250 kg con motivo.
 */
async function sembrarJornada(
  request: APIRequestContext,
  api: DataApi,
  etiqueta: string,
  movimientos = true
): Promise<JornadaSembrada> {
  const t = api.tokenDueno;
  const camion = `S3-${etiqueta}-${randomUUID().slice(0, 8)}`;
  const rc = await rpc(request, api, t, "crear_camion", {
    p_patente: `S3-${randomUUID().slice(0, 12)}`,
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
  if (!movimientos) return { id, fecha, camion, unidad: null, peso: null };

  const unidad = await primerProducto(request, api, "unidad");
  const peso = await primerProducto(request, api, "peso");
  for (const [p, cantidad] of [[unidad, 3], [peso, 1250]] as const) {
    const ri = await rpc(request, api, t, "registrar_ingreso", {
      p_idempotency_key: randomUUID(), p_producto_id: p.id, p_cantidad: cantidad, p_motivo: "E2E S3-0",
    });
    expect(ri.status()).toBe(200);
  }
  const rg = await rpc(request, api, t, "registrar_carga", {
    p_idempotency_key: randomUUID(), p_jornada_id: id, p_productos: [unidad.id, peso.id], p_cantidades: [3, 1250],
  });
  expect(rg.status()).toBe(200);
  const rd = await rpc(request, api, t, "registrar_descarga", {
    p_idempotency_key: randomUUID(), p_jornada_id: id, p_productos: [peso.id], p_cantidades: [250], p_motivo: "Sobró E2E",
  });
  expect(rd.status()).toBe(200);
  return { id, fecha, camion, unidad, peso };
}

async function operacionesEnBase(request: APIRequestContext, api: DataApi, jornadaId: string) {
  const r = await request.get(
    `${api.url}/rest/v1/operaciones?select=id,tipo&jornada_id=eq.${jornadaId}&tipo=in.(carga,descarga)`,
    { headers: cabeceras(api, api.tokenDueno) }
  );
  expect(r.status()).toBe(200);
  return (await r.json()) as Array<{ id: string; tipo: string }>;
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

/** Abre /jornadas filtrado por la fecha y el detalle de la jornada sembrada (PC). */
async function abrirDetalle(page: Page, j: JornadaSembrada) {
  await page.goto("/jornadas");
  await page.getByLabel("Fecha operativa").fill(j.fecha);
  const fila = page.locator("table tbody tr").filter({ hasText: j.camion });
  await expect(fila).toHaveCount(1);
  await fila.getByRole("button", { name: "Ver detalle" }).click();
  const detalle = page.getByRole("region", { name: "Detalle de la jornada" });
  await expect(detalle).toContainText(j.camion);
  return { fila, detalle, historial: detalle.getByRole("region", { name: TITULO }) };
}

/** Solicitudes del navegador a la Data API (sin el login de Auth). */
function registrarSolicitudes(page: Page, api: DataApi) {
  const solicitudes: Request[] = [];
  page.on("request", (r) => {
    if (r.url().startsWith(api.url) && !r.url().includes("/auth/v1/")) solicitudes.push(r);
  });
  return {
    mutadoras: () => solicitudes.filter((r) => !["GET", "HEAD", "OPTIONS"].includes(r.method())),
    a: (tabla: string) => solicitudes.filter((r) => new URL(r.url()).pathname === `/rest/v1/${tabla}`),
  };
}

test.describe("historial de cargas y descargas (backend real, sólo lectura)", () => {
  test("el dueño ve la carga y la descarga con cantidades reales, persiste al recargar y no escribe nada", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "dueno");
    const ops = await operacionesEnBase(request, api, j.id);
    expect(ops.map((o) => o.tipo).sort()).toEqual(["carga", "descarga"]);

    const red = registrarSolicitudes(page, api);
    const { historial } = await abrirDetalle(page, j);
    const items = historial.getByRole("list", { name: "Historial de la jornada" }).locator(":scope > li");
    await expect(items).toHaveCount(2);
    // Orden cronológico: primero la carga, después la descarga.
    await expect(items.nth(0)).toContainText("Carga");
    await expect(items.nth(0)).toContainText("Registró: Vos");
    await expect(items.nth(0)).toContainText(j.unidad!.nombre);
    await expect(items.nth(0)).toContainText("3 un.");
    await expect(items.nth(0)).toContainText(j.peso!.nombre);
    await expect(items.nth(0)).toContainText("1,250 kg");
    await expect(items.nth(1)).toContainText("Descarga");
    await expect(items.nth(1)).toContainText("Motivo: Sobró E2E");
    await expect(items.nth(1)).toContainText("0,250 kg");

    // Sólo lecturas: ninguna solicitud mutadora y ninguna RPC desde el navegador.
    expect(red.mutadoras()).toEqual([]);
    expect(red.a("operaciones").length).toBeGreaterThan(0);
    expect(red.a("movimientos_stock").length).toBeGreaterThan(0);
    expect(red.a("perfiles").filter((r) => !r.url().includes("usuario_id=eq.00000000-0000-4000-8000-000000000001"))).toEqual([]);

    // La base no cambió por mirar el historial.
    expect((await operacionesEnBase(request, api, j.id)).length).toBe(2);

    await page.reload();
    const tras = await abrirDetalle(page, j);
    await expect(tras.historial.getByRole("list", { name: "Historial de la jornada" }).locator(":scope > li")).toHaveCount(2);
  });

  test("el encargado ve las operaciones del dueño identificadas sin leer perfiles ajenos", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "enc");
    const enc = await entrarComo(browser, baseURL, CUENTAS.encargado);
    const { historial } = await abrirDetalle(enc.page, j);
    await expect(historial).toContainText("Registró: Otro usuario (00000000)");
    await expect(historial).not.toContainText("Registró: Vos");
    await enc.contexto.close();
  });

  test("jornada sin cargas ni descargas: mensaje de historial vacío", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "vacia", false);
    const { historial } = await abrirDetalle(page, j);
    await expect(historial).toContainText("Esta jornada todavía no tiene cargas ni descargas registradas.");
  });

  test("error de lectura: alerta segura; «Actualizar historial» vuelve a leer y se recupera", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "error");
    let fallar = true;
    await page.route("**/rest/v1/movimientos_stock*", async (route) => {
      if (fallar) {
        await route.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ code: "XX000", message: "fallo simulado" }) });
      } else {
        await route.continue();
      }
    });
    const { historial } = await abrirDetalle(page, j);
    await expect(historial.getByRole("alert")).toContainText("No se pudo leer el historial de cargas y descargas.");
    await expect(historial).not.toContainText("fallo simulado");
    fallar = false;
    await historial.getByRole("button", { name: "Actualizar historial" }).click();
    await expect(historial.getByRole("list", { name: "Historial de la jornada" }).locator(":scope > li")).toHaveCount(2);
  });

  test("respuesta truncada (conteo mayor que las filas): falla cerrada, sin historial parcial", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "trunc");
    await page.route("**/rest/v1/movimientos_stock*", async (route) => {
      const r = await route.fetch();
      const filas = (await r.json()) as unknown[];
      await route.fulfill({
        response: r,
        body: JSON.stringify(filas.slice(0, 1)),
        headers: { ...r.headers(), "content-range": `0-0/${filas.length}` },
      });
    });
    const { historial } = await abrirDetalle(page, j);
    await expect(historial.getByRole("alert")).toContainText("No se pudo leer el historial");
    await expect(historial.getByRole("list", { name: "Historial de la jornada" })).toHaveCount(0);
  });

  test("Android (412×915): historial legible, sin scroll horizontal", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "movil");
    const m = await entrarComo(browser, baseURL, CUENTAS.dueno, {
      viewport: { width: 412, height: 915 }, hasTouch: true, isMobile: true,
    });
    await m.page.goto("/jornadas");
    await m.page.getByLabel("Fecha operativa").fill(j.fecha);
    const tarjeta = m.page.locator("ul.md\\:hidden > li").filter({ hasText: j.camion });
    await expect(tarjeta).toHaveCount(1);
    await tarjeta.getByRole("button", { name: "Ver detalle" }).click();
    const historial = m.page.getByRole("region", { name: "Detalle de la jornada" }).getByRole("region", { name: TITULO });
    await expect(historial).toContainText("1,250 kg");
    const boton = historial.getByRole("button", { name: "Actualizar historial" });
    expect((await boton.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
    expect(await m.page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
    await m.contexto.close();
  });
});

test.describe("roles sin acceso al historial (backend real)", () => {
  test("el vendedor asignado no ve el historial ni lo consulta; la Data API no le devuelve movimientos", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "vend");
    const v = await entrarComo(browser, baseURL, CUENTAS.vendedor);
    const red = registrarSolicitudes(v.page, api);
    await v.page.goto("/jornadas");
    await v.page.getByLabel("Fecha operativa").fill(j.fecha);
    const fila = v.page.locator("table tbody tr").filter({ hasText: j.camion });
    await expect(fila).toHaveCount(1);
    await fila.getByRole("button", { name: "Ver detalle" }).click();
    await expect(v.page.getByRole("region", { name: "Detalle de la jornada" })).toBeVisible();
    await expect(v.page.getByText(TITULO)).toHaveCount(0);
    expect(red.a("operaciones")).toEqual([]);
    expect(red.a("movimientos_stock")).toEqual([]);
    await v.contexto.close();

    // RLS vigente: aunque consulte por su cuenta, no recibe filas.
    const tokenVendedor = await tokenDe(request, api, CUENTAS.vendedor);
    for (const tabla of ["operaciones", "movimientos_stock"]) {
      const r = await request.get(`${api.url}/rest/v1/${tabla}?select=id&jornada_id=eq.${j.id}`, {
        headers: cabeceras(api, tokenVendedor),
      });
      expect(r.status()).toBe(200);
      expect(await r.json()).toEqual([]);
    }
  });
});
