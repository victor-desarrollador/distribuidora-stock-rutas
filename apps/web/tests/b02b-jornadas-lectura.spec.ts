// B-02b.1 — E2E de la pantalla REAL de jornadas (/jornadas, sólo lectura).
//
// ESTADO: ejecutados sobre a59de2e en un laboratorio Supabase local aislado
// (07/11/2026): la suite Playwright completa dio 135/135 PASS, incluidos estos
// casos. Requieren el stack local con supabase/seed.sql (ver
// playwright.config.ts); cada corrida necesita autorización. Nada aquí toca
// staging ni producción.
//
// Qué valida cada bloque (para no confundir mocks con RLS):
//  - «roles y aislamiento» (BACKEND REAL): la base devuelve las filas; prueba la
//    RLS real (dueño/encargado ven la empresa, el vendedor sólo la suya, la otra
//    empresa no se cruza). Es la única parte que valida RLS.
//  - «sin llamadas mutadoras» (BACKEND REAL): observa las solicitudes del
//    navegador.
//  - «UI con PostgREST simulado» (page.route, NO valida RLS ni la base): sólo
//    prueba el contrato de paginación y de errores de la interfaz con
//    respuestas controladas. El login y el catálogo de camiones siguen siendo
//    reales.
//  - «vista móvil» (BACKEND REAL).
import { randomInt, randomUUID } from "node:crypto";

import {
  expect,
  test,
  type APIRequestContext,
  type Browser,
  type BrowserContextOptions,
  type Page,
} from "@playwright/test";

import { CUENTAS, PASSWORD_PRUEBA } from "./auth/cuentasPrueba";

// Los encabezados de las solicitudes llevan tokens de sesión de prueba: sin
// trazas, capturas ni videos (igual que jornadas-rpc-http.spec.ts).
test.use({ trace: "off", screenshot: "off", video: "off" });

const ID_ENCARGADO = "00000000-0000-4000-8000-000000000002";
const ID_VENDEDOR = "00000000-0000-4000-8000-000000000003";
const ID_DUENO_OTRA_EMPRESA = "00000000-0000-4000-8000-000000000006";

interface DataApi {
  url: string;
  apikey: string;
  tokenDueno: string;
}

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

async function tokenDe(request: APIRequestContext, api: DataApi, usuario: string) {
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

const cabeceras = (api: DataApi, token: string) => ({
  apikey: api.apikey,
  "content-type": "application/json",
  authorization: `Bearer ${token}`,
});

// Fecha futura aleatoria y única por prueba (par vendedor+fecha y camión+fecha).
function fechaFutura() {
  const hoy = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Argentina/Tucuman",
  }).format(new Date());
  const d = new Date(`${hoy}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + randomInt(1, 2_000_000));
  return d.toISOString().slice(0, 10);
}

// Fecha calendario real 'AAAA-MM-DD' desplazada `dias` días. Determinística:
// sólo depende de sus argumentos (no de la hora actual). Falla si el resultado
// no es una fecha válida de año <= 9999.
function sumarDias(fecha: string, dias: number) {
  const d = new Date(`${fecha}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  const resultado = d.toISOString().slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(resultado) || Number(resultado.slice(0, 4)) > 9999) {
    throw new Error(`fecha fuera de rango: ${resultado}`);
  }
  return resultado;
}

interface CamionPrueba {
  id: string;
  // Nombre único y distinguible: es lo que muestra la interfaz en la fila.
  nombre: string;
}

// Cada camión de cada escenario lleva un nombre único (etiqueta + azar), que la
// interfaz muestra como «nombre · patente». Así las aserciones identifican la
// jornada por un dato visible e inequívoco, no por un conteo de filas.
async function crearCamion(
  request: APIRequestContext,
  api: DataApi,
  token: string,
  etiqueta: string
): Promise<CamionPrueba> {
  const sufijo = randomUUID().slice(0, 8);
  const nombre = `B02B-${etiqueta}-${sufijo}`;
  const r = await request.post(`${api.url}/rest/v1/rpc/crear_camion`, {
    headers: cabeceras(api, token),
    data: { p_patente: `B02B-${randomUUID().slice(0, 12)}`, p_nombre: nombre },
  });
  expect(r.status()).toBe(200);
  return { id: (await r.json()) as string, nombre };
}

// Ids EXACTOS de las jornadas que la base (RLS) deja leer a `token` en `fecha`.
async function idsVisibles(
  request: APIRequestContext,
  api: DataApi,
  token: string,
  fecha: string
) {
  const r = await request.get(
    `${api.url}/rest/v1/jornadas?select=id&fecha=eq.${fecha}&order=id`,
    { headers: cabeceras(api, token) }
  );
  expect(r.status()).toBe(200);
  return ((await r.json()) as { id: string }[]).map((x) => x.id).sort();
}

async function abrirJornada(
  request: APIRequestContext,
  api: DataApi,
  token: string,
  camion: string,
  fecha: string,
  vendedor: string
) {
  const r = await request.post(`${api.url}/rest/v1/rpc/abrir_jornada`, {
    headers: cabeceras(api, token),
    data: {
      p_idempotency_key: randomUUID(),
      p_camion_id: camion,
      p_fecha: fecha,
      p_vendedor_id: vendedor,
    },
  });
  expect(r.status()).toBe(200);
  return (await r.json()) as string;
}

// Inicia sesión por la interfaz en un contexto nuevo y SIN sesión previa.
async function entrarComo(
  browser: Browser,
  baseURL: string | undefined,
  usuario: string,
  opciones: BrowserContextOptions = {}
) {
  const contexto = await browser.newContext({
    baseURL,
    storageState: { cookies: [], origins: [] },
    ...opciones,
  });
  const page = await contexto.newPage();
  await page.goto("/login");
  await page.getByLabel("Usuario").fill(usuario);
  await page.getByLabel("Contraseña").fill(PASSWORD_PRUEBA);
  await page.getByRole("button", { name: "Ingresar al sistema" }).click();
  await expect(page.locator("aside")).toBeVisible();
  return { page, contexto };
}

const filas = (page: Page) => page.locator("table tbody tr");
// Fila de la tabla (escritorio) que muestra exactamente ese camión.
const filaDe = (page: Page, camion: CamionPrueba) =>
  filas(page).filter({ hasText: camion.nombre });

async function filtrarPorFecha(page: Page, fecha: string) {
  await page.getByLabel("Fecha operativa").fill(fecha);
}

test.describe("roles y aislamiento (backend real, RLS real)", () => {
  test("dueño y encargado ven las jornadas de su empresa; el detalle y los botones mutadores deshabilitados", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const fecha = fechaFutura();
    const c1 = await crearCamion(request, api, api.tokenDueno, "dv");
    const c2 = await crearCamion(request, api, api.tokenDueno, "de");
    const j1 = await abrirJornada(request, api, api.tokenDueno, c1.id, fecha, ID_VENDEDOR);
    const j2 = await abrirJornada(request, api, api.tokenDueno, c2.id, fecha, ID_ENCARGADO);

    // Dueño (sesión por defecto del proyecto): ve AMBAS jornadas, identificadas
    // por su camión; y la base le devuelve exactamente esos dos ids.
    expect(await idsVisibles(request, api, api.tokenDueno, fecha)).toEqual([j1, j2].sort());
    await page.goto("/jornadas");
    await expect(page.getByRole("heading", { name: "Jornadas", exact: true })).toBeVisible();
    await filtrarPorFecha(page, fecha);
    await expect(filaDe(page, c1)).toHaveCount(1);
    await expect(filaDe(page, c2)).toHaveCount(1);
    await expect(filas(page)).toHaveCount(2);
    await expect(page.getByText("2 jornadas (lista completa)")).toBeVisible();
    await filaDe(page, c1).getByRole("button", { name: "Ver detalle" }).click();
    const detalle = page.getByRole("region", { name: "Detalle de la jornada" });
    await expect(detalle).toContainText(c1.nombre);
    await expect(detalle).toContainText("Abierta por");
    await expect(page.getByRole("button", { name: /Nueva jornada/ })).toBeDisabled();
    await expect(page.getByRole("button", { name: /Confirmar salida/ })).toBeDisabled();

    // Encargado: también ve las dos (la del vendedor y la suya).
    const tokenEncargado = await tokenDe(request, api, CUENTAS.encargado);
    expect(await idsVisibles(request, api, tokenEncargado, fecha)).toEqual([j1, j2].sort());
    const enc = await entrarComo(browser, baseURL, CUENTAS.encargado);
    await enc.page.goto("/jornadas");
    await expect(enc.page.getByRole("heading", { name: "Jornadas", exact: true })).toBeVisible();
    await filtrarPorFecha(enc.page, fecha);
    await expect(filaDe(enc.page, c1)).toHaveCount(1);
    await expect(filaDe(enc.page, c2)).toHaveCount(1);
    await expect(filas(enc.page)).toHaveCount(2);
    await enc.contexto.close();
  });

  test("el vendedor asignado ve «Mi jornada» con sólo la suya, sin controles ni identificadores administrativos", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const fecha = fechaFutura();
    const otraFecha = sumarDias(fecha, 1);
    const propia = await crearCamion(request, api, api.tokenDueno, "vend");
    const ajena = await crearCamion(request, api, api.tokenDueno, "ajena");
    const jPropia = await abrirJornada(request, api, api.tokenDueno, propia.id, fecha, ID_VENDEDOR);
    // Jornada de OTRO vendedor (el encargado) en la MISMA fecha: no debe verla.
    const jAjena = await abrirJornada(request, api, api.tokenDueno, ajena.id, fecha, ID_ENCARGADO);

    // RLS real, ids exactos: el vendedor lee sólo la suya; no la del encargado.
    const tokenVendedor = await tokenDe(request, api, CUENTAS.vendedor);
    expect(await idsVisibles(request, api, tokenVendedor, fecha)).toEqual([jPropia]);
    expect(await idsVisibles(request, api, tokenVendedor, fecha)).not.toContain(jAjena);
    // Precondición de la fecha vacía: el vendedor no tiene jornada en `otraFecha`.
    expect(await idsVisibles(request, api, tokenVendedor, otraFecha)).toEqual([]);

    const v = await entrarComo(browser, baseURL, CUENTAS.vendedor);
    // Acceso desde el menú (escritorio).
    await v.page.getByRole("link", { name: "Mi jornada" }).click();
    await expect(v.page).toHaveURL("/jornadas");
    await expect(v.page.getByRole("heading", { name: "Mi jornada" })).toBeVisible();

    await filtrarPorFecha(v.page, fecha);
    await expect(filaDe(v.page, propia)).toHaveCount(1);
    await expect(filas(v.page)).toHaveCount(1);
    // La jornada ajena no aparece en ninguna parte de la página (tabla ni tarjetas).
    await expect(v.page.getByText(ajena.nombre)).toHaveCount(0);
    await filaDe(v.page, propia).getByRole("button", { name: "Ver detalle" }).click();
    const detalle = v.page.getByRole("region", { name: "Detalle de la jornada" });
    await expect(detalle).toBeVisible();
    await expect(detalle).toContainText(propia.nombre);
    await expect(detalle).not.toContainText(/Abierta por|Operación de apertura|Vendedor asignado/);
    await expect(v.page.getByText(/Nueva jornada|Confirmar salida/)).toHaveCount(0);

    // Sin jornada asignada en la fecha siguiente. El resumen accesible
    // (aria-live) es único en la pantalla y se verifica con su texto exacto.
    await filtrarPorFecha(v.page, otraFecha);
    const [anio, mes, dia] = otraFecha.split("-");
    const resumen = v.page.locator('p[aria-live="polite"]');
    await expect(resumen).toHaveCount(1);
    await expect(resumen).toHaveText(`No tenés una jornada asignada el ${dia}/${mes}/${anio}.`);
    await expect(filas(v.page)).toHaveCount(0);
    await expect(v.page.getByText(propia.nombre)).toHaveCount(0);

    // Las rutas de gestión y la demo siguen vedadas para el vendedor.
    for (const ruta of ["/camiones", "/demo/jornadas", "/rendicion"]) {
      await v.page.goto(ruta);
      await expect(v.page.getByRole("heading", { name: "Acceso no permitido" })).toBeVisible();
    }
    await v.contexto.close();
  });

  test("aislamiento por empresa: cada dueño ve su jornada y NO la de la otra empresa", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const fecha = fechaFutura();
    const tokenOtra = await tokenDe(request, api, CUENTAS.otraEmpresa);
    const cA = await crearCamion(request, api, api.tokenDueno, "empA");
    const cB = await crearCamion(request, api, tokenOtra, "empB");
    const jA = await abrirJornada(request, api, api.tokenDueno, cA.id, fecha, ID_VENDEDOR);
    const jB = await abrirJornada(request, api, tokenOtra, cB.id, fecha, ID_DUENO_OTRA_EMPRESA);

    // RLS real, ids exactos en ambos sentidos.
    expect(await idsVisibles(request, api, api.tokenDueno, fecha)).toEqual([jA]);
    expect(await idsVisibles(request, api, tokenOtra, fecha)).toEqual([jB]);

    // Empresa A (sesión por defecto): su camión sí, el de B no.
    await page.goto("/jornadas");
    await filtrarPorFecha(page, fecha);
    await expect(filaDe(page, cA)).toHaveCount(1);
    await expect(page.getByText(cB.nombre)).toHaveCount(0);
    await expect(filas(page)).toHaveCount(1);

    // Empresa B: su camión sí, el de A no.
    const otra = await entrarComo(browser, baseURL, CUENTAS.otraEmpresa);
    await otra.page.goto("/jornadas");
    await filtrarPorFecha(otra.page, fecha);
    await expect(filaDe(otra.page, cB)).toHaveCount(1);
    await expect(otra.page.getByText(cA.nombre)).toHaveCount(0);
    await expect(filas(otra.page)).toHaveCount(1);
    await otra.contexto.close();
  });
});

test.describe("sin llamadas mutadoras desde /jornadas (backend real)", () => {
  test("listar, filtrar, abrir el detalle y actualizar sólo hacen lecturas y no tocan el demo local", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const fecha = fechaFutura();
    const c = await crearCamion(request, api, api.tokenDueno, "lect");
    await abrirJornada(request, api, api.tokenDueno, c.id, fecha, ID_VENDEDOR);

    const solicitudes: Array<{ metodo: string; url: string }> = [];
    page.on("request", (r) => {
      if (r.url().startsWith(api.url)) solicitudes.push({ metodo: r.method(), url: r.url() });
    });

    await page.goto("/jornadas");
    await filtrarPorFecha(page, fecha);
    await expect(filaDe(page, c)).toHaveCount(1);
    await filaDe(page, c).getByRole("button", { name: "Ver detalle" }).click();
    await page.getByRole("button", { name: "Actualizar", exact: true }).click();
    await expect(filaDe(page, c)).toHaveCount(1);

    expect(solicitudes.length).toBeGreaterThan(0);
    const mutadoras = solicitudes.filter(
      (s) => !["GET", "HEAD", "OPTIONS"].includes(s.metodo) && !s.url.includes("/auth/v1/")
    );
    expect(mutadoras).toEqual([]);
    expect(solicitudes.filter((s) => s.url.includes("/rpc/"))).toEqual([]);

    // La pantalla real no usa el almacenamiento demo.
    const demo = await page.evaluate(() => localStorage.getItem("distribuidora_jornadas_demo_v5"));
    expect(demo).toBeNull();
  });
});

test.describe("UI con PostgREST simulado (page.route): NO valida RLS ni la base", () => {
  const TOTAL = 1250;
  const hex = (n: number) => n.toString(16).padStart(12, "0");
  const idDe = (n: number) => `00000000-0000-4000-8000-${hex(n)}`;
  const FECHA = "2026-11-10";
  const CORS = {
    "access-control-allow-origin": "*",
    "access-control-allow-headers": "*",
    "access-control-expose-headers": "content-range",
  };

  const fila = (n: number) => ({
    id: idDe(n), fecha: FECHA,
    camion_id: "22222222-2222-4222-8222-222222222222",
    vendedor_id: ID_VENDEDOR,
    estado: "abierta",
    abierta_por: "66666666-6666-4666-8666-666666666666",
    operacion_apertura_id: idDe(n + 100000),
    creado_en: "2026-11-10T08:00:00+00:00",
  });

  // Responde como PostgREST para un único día con TOTAL filas, ids descendentes.
  async function simular(page: Page, opciones: { maxRows?: number; fallarDesdeSegunda?: boolean } = {}) {
    const maxRows = opciones.maxRows ?? 1000;
    await page.route("**/rest/v1/jornadas?*", async (route) => {
      const req = route.request();
      if (req.method() === "OPTIONS") {
        await route.fulfill({ status: 204, headers: CORS });
        return;
      }
      const u = new URL(req.url());
      const limite = Number(u.searchParams.get("limit") ?? "1000");
      const cursor = /id\.lt\.([0-9a-f-]+)\)/.exec(u.searchParams.get("or") ?? "");
      const tope = cursor ? parseInt(cursor[1].slice(-12), 16) - 1 : TOTAL;
      if (opciones.fallarDesdeSegunda && cursor) {
        await route.fulfill({
          status: 500,
          headers: CORS,
          contentType: "application/json",
          body: JSON.stringify({ code: "XX000", message: "relation \"public.jornadas\" internal detail" }),
        });
        return;
      }
      const n = Math.min(limite, maxRows, tope);
      const datos = Array.from({ length: n }, (_, i) => fila(tope - i));
      await route.fulfill({
        status: 200,
        headers: { ...CORS, "content-range": `0-${Math.max(n - 1, 0)}/${tope}` },
        contentType: "application/json",
        body: JSON.stringify(datos),
      });
    });
  }

  test("paginación: 1250 jornadas en 3 páginas, «hay más» hasta la última y recién ahí «lista completa»", async ({ page }) => {
    await simular(page);
    await page.goto("/jornadas");
    await expect(page.getByText("500 jornadas cargadas. Hay más: la lista todavía no está completa.")).toBeVisible();
    await expect(filas(page)).toHaveCount(500);
    await page.getByRole("button", { name: "Cargar más" }).click();
    await expect(page.getByText("1000 jornadas cargadas. Hay más")).toBeVisible();
    await page.getByRole("button", { name: "Cargar más" }).click();
    await expect(page.getByText("1250 jornadas (lista completa)")).toBeVisible();
    await expect(page.getByRole("button", { name: "Cargar más" })).toHaveCount(0);
    await expect(filas(page)).toHaveCount(1250);
  });

  test("error en una página posterior: mensaje seguro, sin detalle interno, y se conserva lo ya leído", async ({ page }) => {
    await simular(page, { fallarDesdeSegunda: true });
    await page.goto("/jornadas");
    await expect(filas(page)).toHaveCount(500);
    await page.getByRole("button", { name: "Cargar más" }).click();
    const alerta = page.getByRole("alert");
    await expect(alerta).toHaveText("No se pudieron leer las jornadas. Intentá de nuevo.");
    await expect(alerta).not.toContainText(/relation|public\.jornadas|XX000/);
    await expect(filas(page)).toHaveCount(500);
  });

  test("si el servidor devuelve menos filas que las pedidas (tope de filas) la pantalla falla cerrado", async ({ page }) => {
    await simular(page, { maxRows: 100 });
    await page.goto("/jornadas");
    // El alerta de error de lectura contiene el mensaje seguro y, aparte, el
    // botón «Reintentar»: se verifican por separado.
    const alerta = page.getByRole("alert");
    await expect(alerta).toContainText("No se pudieron leer las jornadas. Intentá de nuevo.");
    await expect(alerta.getByRole("button", { name: "Reintentar" })).toBeVisible();
    // Falla cerrada: ninguna fila parcial a la vista.
    await expect(filas(page)).toHaveCount(0);
  });
});

test.describe("vista móvil (backend real)", () => {
  test.use({ viewport: { width: 393, height: 851 }, hasTouch: true, isMobile: true });

  test("tarjetas en lugar de tabla, sin scroll horizontal, controles táctiles y acceso por el menú del vendedor", async ({ page, request, browser, baseURL }) => {
    // La semilla usa el dueño (sesión por defecto) sólo para obtener la API y sembrar.
    const api = await dataApiDesdeApp(page);
    const fecha = fechaFutura();
    const c = await crearCamion(request, api, api.tokenDueno, "movil");
    await abrirJornada(request, api, api.tokenDueno, c.id, fecha, ID_VENDEDOR);

    const v = await entrarComo(browser, baseURL, CUENTAS.vendedor, {
      viewport: { width: 393, height: 851 },
      hasTouch: true,
      isMobile: true,
    });
    const movil = v.page;
    await movil.goto("/");
    await movil.getByRole("button", { name: "Abrir menú de navegación" }).click();
    await movil.getByRole("link", { name: "Mi jornada" }).click();
    await expect(movil.getByRole("heading", { name: "Mi jornada" })).toBeVisible();
    await movil.getByLabel("Fecha operativa").fill(fecha);

    await expect(movil.locator("table")).toBeHidden();
    const tarjetas = movil.locator("ul.md\\:hidden > li");
    await expect(tarjetas.filter({ hasText: c.nombre })).toHaveCount(1);
    await expect(tarjetas).toHaveCount(1);
    const boton = tarjetas.first().getByRole("button", { name: "Ver detalle" });
    const caja = await boton.boundingBox();
    expect(caja?.height ?? 0).toBeGreaterThanOrEqual(44);
    const sinDesborde = await movil.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth);
    expect(sinDesborde).toBe(true);
    await v.contexto.close();
  });
});
