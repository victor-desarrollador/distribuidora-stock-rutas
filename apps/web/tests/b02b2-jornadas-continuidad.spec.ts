// B-02b.2 / S3-1 — E2E del panel «Estado de cierre» (SÓLO LECTURA) en la
// pantalla REAL de jornadas.
//
// Requiere un laboratorio aislado autorizado (Supabase local con
// supabase/seed.sql). Cada caso siembra su propia jornada por la Data API como
// dueño (camión nuevo, fecha futura aleatoria; ingresos, cargas, descarga y
// salida por RPC según el estado buscado) y compara lo que muestra el panel con
// lo sembrado. El panel NO escribe: ningún caso espera solicitudes mutadoras
// desde el navegador. Nada aquí toca staging ni producción.
import { randomInt, randomUUID } from "node:crypto";

import {
  expect,
  test,
  type APIRequestContext,
  type Browser,
  type BrowserContextOptions,
  type Locator,
  type Page,
  type Request,
} from "@playwright/test";

import { CUENTAS, PASSWORD_PRUEBA } from "./auth/cuentasPrueba";

// Los encabezados llevan tokens de sesión de prueba: sin trazas ni capturas.
test.use({ trace: "off", screenshot: "off", video: "off" });

const ID_VENDEDOR = "00000000-0000-4000-8000-000000000003";
const TITULO = "Estado de cierre";
const TITULO_CARGA_NETA = "Carga neta registrada de esta jornada";
const NO_CERRABLE = "Esta jornada todavía no puede cerrarse";
const SIN_CARGA_NETA = "Esta jornada no tiene carga neta registrada.";
const ACLARACION = "No es un conteo físico ni el saldo real del camión";

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

const cabeceras = (api: DataApi, token: string) => ({
  apikey: api.apikey,
  "content-type": "application/json",
  authorization: `Bearer ${token}`,
});

async function rpc(request: APIRequestContext, api: DataApi, nombre: string, data: object) {
  const r = await request.post(`${api.url}/rest/v1/rpc/${nombre}`, { headers: cabeceras(api, api.tokenDueno), data });
  expect(r.status(), nombre).toBe(200);
  return r.json();
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

type Objetivo = "abierta" | "cargada" | "en_reparto";

interface JornadaSembrada {
  id: string;
  fecha: string;
  camion: string;
  unidad: { id: string; nombre: string };
  peso: { id: string; nombre: string };
}

/**
 * Jornada en el estado pedido. Para «cargada» y «en_reparto» registra: carga 1
 * (3 un. + 1250 g), carga 2 (2 un.) y descarga (250 g) → carga neta esperada
 * 5 un. y 1,000 kg. «en_reparto» además confirma la salida.
 */
async function sembrarJornada(request: APIRequestContext, api: DataApi, etiqueta: string, objetivo: Objetivo): Promise<JornadaSembrada> {
  const camion = `S31-${etiqueta}-${randomUUID().slice(0, 8)}`;
  const camionId = (await rpc(request, api, "crear_camion", {
    p_patente: `S31-${randomUUID().slice(0, 12)}`,
    p_nombre: camion,
  })) as string;
  const fecha = fechaFutura();
  const id = (await rpc(request, api, "abrir_jornada", {
    p_idempotency_key: randomUUID(), p_camion_id: camionId, p_fecha: fecha, p_vendedor_id: ID_VENDEDOR,
  })) as string;
  const unidad = await primerProducto(request, api, "unidad");
  const peso = await primerProducto(request, api, "peso");
  if (objetivo === "abierta") return { id, fecha, camion, unidad, peso };

  for (const [p, cantidad] of [[unidad, 5], [peso, 1250]] as const) {
    await rpc(request, api, "registrar_ingreso", {
      p_idempotency_key: randomUUID(), p_producto_id: p.id, p_cantidad: cantidad, p_motivo: "E2E S3-1",
    });
  }
  await rpc(request, api, "registrar_carga", {
    p_idempotency_key: randomUUID(), p_jornada_id: id, p_productos: [unidad.id, peso.id], p_cantidades: [3, 1250],
  });
  await rpc(request, api, "registrar_carga", {
    p_idempotency_key: randomUUID(), p_jornada_id: id, p_productos: [unidad.id], p_cantidades: [2],
  });
  await rpc(request, api, "registrar_descarga", {
    p_idempotency_key: randomUUID(), p_jornada_id: id, p_productos: [peso.id], p_cantidades: [250], p_motivo: "Sobró E2E S3-1",
  });
  if (objetivo === "en_reparto") {
    await rpc(request, api, "confirmar_salida", { p_idempotency_key: randomUUID(), p_jornada_id: id });
  }
  return { id, fecha, camion, unidad, peso };
}

async function estadoEnBase(request: APIRequestContext, api: DataApi, jornadaId: string) {
  const r = await request.get(`${api.url}/rest/v1/jornadas?select=estado&id=eq.${jornadaId}`, {
    headers: cabeceras(api, api.tokenDueno),
  });
  expect(r.status()).toBe(200);
  return ((await r.json()) as Array<{ estado: string }>)[0]?.estado;
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

/** Abre /jornadas filtrado por la fecha y el detalle de la jornada (PC). */
async function abrirPanel(page: Page, j: JornadaSembrada) {
  await page.goto("/jornadas");
  await page.getByLabel("Fecha operativa").fill(j.fecha);
  const fila = page.locator("table tbody tr").filter({ hasText: j.camion });
  await expect(fila).toHaveCount(1);
  await fila.getByRole("button", { name: "Ver detalle" }).click();
  const detalle = page.getByRole("region", { name: "Detalle de la jornada" });
  await expect(detalle).toContainText(j.camion);
  return detalle.getByRole("region", { name: TITULO });
}

function registrarSolicitudes(page: Page, api: DataApi) {
  const solicitudes: Request[] = [];
  page.on("request", (r) => {
    if (r.url().startsWith(api.url) && !r.url().includes("/auth/v1/")) solicitudes.push(r);
  });
  return {
    mutadoras: () => solicitudes.filter((r) => !["GET", "HEAD", "OPTIONS"].includes(r.method())),
    rpc: () => solicitudes.filter((r) => new URL(r.url()).pathname.startsWith("/rest/v1/rpc/")),
  };
}

const paso = (panel: Locator, titulo: string) =>
  panel.getByRole("list", { name: "Pasos de la jornada" }).locator(":scope > li").filter({ hasText: `${titulo}:` });

async function esperarCargaNeta(panel: Locator, j: JornadaSembrada) {
  const lista = panel.getByRole("list", { name: "Carga neta de la jornada" });
  await expect(lista.locator(":scope > li")).toHaveCount(2);
  await expect(lista.locator(":scope > li").filter({ hasText: j.unidad.nombre })).toContainText("5 un.");
  await expect(lista.locator(":scope > li").filter({ hasText: j.peso.nombre })).toContainText("1,000 kg");
}

test.describe("estado de cierre (backend real, sólo lectura)", () => {
  test("jornada abierta: sin carga neta, carga y salida pendientes, no cerrable y camión bloqueado", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "abierta", "abierta");
    expect(await estadoEnBase(request, api, j.id)).toBe("abierta");
    const red = registrarSolicitudes(page, api);
    const panel = await abrirPanel(page, j);
    await expect(panel).toContainText(NO_CERRABLE);
    await expect(panel).toContainText(`Mientras esta jornada no se cierre, ${j.camion}`);
    await expect(paso(panel, "Carga del camión")).toContainText("Pendiente");
    await expect(paso(panel, "Salida")).toContainText("Requiere que la jornada esté cargada.");
    await expect(panel).toContainText(SIN_CARGA_NETA);
    expect(red.mutadoras()).toEqual([]);
    expect(red.rpc()).toEqual([]);
  });

  test("jornada cargada: carga neta exacta por producto (5 un. y 1,000 kg), salida pendiente, sin escrituras", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "cargada", "cargada");
    expect(await estadoEnBase(request, api, j.id)).toBe("cargada");
    const red = registrarSolicitudes(page, api);
    const panel = await abrirPanel(page, j);
    await expect(panel.getByRole("heading", { name: TITULO_CARGA_NETA })).toBeVisible();
    await expect(panel).toContainText(ACLARACION);
    await esperarCargaNeta(panel, j);
    await expect(paso(panel, "Carga del camión")).toContainText("Hecho");
    await expect(paso(panel, "Salida")).toContainText("Confirmar salida");
    await expect(panel).toContainText(NO_CERRABLE);
    await expect(panel).not.toContainText(/faltante|sobrante|diferencia/i);
    expect(red.mutadoras()).toEqual([]);
    expect(red.rpc()).toEqual([]);
    // El panel no cambió nada en la base.
    expect(await estadoEnBase(request, api, j.id)).toBe("cargada");
  });

  test("jornada en reparto: salida hecha, cuatro pasos no disponibles, carga neta y camión bloqueado", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "reparto", "en_reparto");
    expect(await estadoEnBase(request, api, j.id)).toBe("en_reparto");
    const red = registrarSolicitudes(page, api);
    const panel = await abrirPanel(page, j);
    await expect(paso(panel, "Salida")).toContainText("Hecho");
    for (const t of ["Ventas finalizadas", "Conteo formal de regreso", "Retorno y regularización", "Rendición y cierre"]) {
      await expect(paso(panel, t)).toContainText("No disponible todavía");
    }
    await esperarCargaNeta(panel, j);
    // El camión se identifica como «nombre · patente» (patente sembrada: S31- + 12 caracteres).
    const nombre = j.camion.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    await expect(panel).toContainText(
      new RegExp(`Mientras esta jornada no se cierre, ${nombre} · S31-[0-9a-f-]{12} no puede abrir otra jornada\\.`)
    );
    await expect(panel.getByRole("button")).toHaveCount(0);
    expect(red.mutadoras()).toEqual([]);
    expect(red.rpc()).toEqual([]);
  });

  test("Android (412×915): panel legible, sin scroll horizontal", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "movil", "en_reparto");
    const m = await entrarComo(browser, baseURL, CUENTAS.dueno, {
      viewport: { width: 412, height: 915 }, hasTouch: true, isMobile: true,
    });
    await m.page.goto("/jornadas");
    await m.page.getByLabel("Fecha operativa").fill(j.fecha);
    const tarjeta = m.page.locator("ul.md\\:hidden > li").filter({ hasText: j.camion });
    await expect(tarjeta).toHaveCount(1);
    await tarjeta.getByRole("button", { name: "Ver detalle" }).click();
    const panel = m.page.getByRole("region", { name: "Detalle de la jornada" }).getByRole("region", { name: TITULO });
    await esperarCargaNeta(panel, j);
    await panel.scrollIntoViewIfNeeded();
    expect(await m.page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
    await m.contexto.close();
  });
});

test.describe("roles sin acceso (backend real)", () => {
  test("el vendedor asignado no ve el panel «Estado de cierre»", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "vend", "cargada");
    const v = await entrarComo(browser, baseURL, CUENTAS.vendedor);
    const red = registrarSolicitudes(v.page, api);
    await v.page.goto("/jornadas");
    await v.page.getByLabel("Fecha operativa").fill(j.fecha);
    const fila = v.page.locator("table tbody tr").filter({ hasText: j.camion });
    await expect(fila).toHaveCount(1);
    await fila.getByRole("button", { name: "Ver detalle" }).click();
    await expect(v.page.getByRole("region", { name: "Detalle de la jornada" })).toBeVisible();
    await expect(v.page.getByText(TITULO)).toHaveCount(0);
    await expect(v.page.getByText(TITULO_CARGA_NETA)).toHaveCount(0);
    expect(red.mutadoras()).toEqual([]);
    await v.contexto.close();
  });
});
