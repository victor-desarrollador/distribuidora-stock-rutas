// B-02b.2 / S2 — E2E de «Corregir jornada» en la pantalla REAL de jornadas.
//
// Backend real (Supabase local con supabase/seed.sql): la base decide roles,
// estados, fechas, pares (camión, fecha) y vendedor; RLS decide las filas. Cada
// caso siembra su propia jornada `abierta` por la Data API (camión nuevo, fecha
// futura aleatoria) y verifica el estado REAL en la base y el historial
// (`correcciones_jornada`) después de operar desde la interfaz. Nada aquí toca
// staging ni producción.
//
// Los ayudantes de siembra y sesión siguen el patrón de
// b02b2-jornadas-salida.spec.ts (S1), que no se modifica.
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

function hoyTucuman() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Argentina/Tucuman" }).format(new Date());
}

function sumarDias(fecha: string, dias: number) {
  const d = new Date(`${fecha}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

// Fecha futura aleatoria (< año 9999): evita choques entre casos y corridas.
const fechaFutura = () => sumarDias(hoyTucuman(), randomInt(1, 2_000_000));

interface Camion {
  id: string;
  nombre: string;
  etiqueta: string; // como lo muestra el selector: «nombre · patente»
}

async function crearCamion(request: APIRequestContext, api: DataApi, etiqueta: string): Promise<Camion> {
  const nombre = `S2-${etiqueta}-${randomUUID().slice(0, 8)}`;
  const patente = `S2-${randomUUID().slice(0, 12)}`;
  const r = await rpc(request, api, api.tokenDueno, "crear_camion", { p_patente: patente, p_nombre: nombre });
  expect(r.status()).toBe(200);
  return { id: (await r.json()) as string, nombre, etiqueta: `${nombre} · ${patente}` };
}

interface JornadaSembrada {
  id: string;
  fecha: string;
  camion: Camion;
}

/** Jornada `abierta` (sin movimientos) para el vendedor de prueba. */
async function sembrarJornada(
  request: APIRequestContext,
  api: DataApi,
  etiqueta: string,
  opciones: { fecha?: string; camion?: Camion } = {}
): Promise<JornadaSembrada> {
  const camion = opciones.camion ?? (await crearCamion(request, api, etiqueta));
  const fecha = opciones.fecha ?? fechaFutura();
  const r = await rpc(request, api, api.tokenDueno, "abrir_jornada", {
    p_idempotency_key: randomUUID(), p_camion_id: camion.id, p_fecha: fecha, p_vendedor_id: ID_VENDEDOR,
  });
  expect(r.status()).toBe(200);
  return { id: (await r.json()) as string, fecha, camion };
}

interface JornadaEnBase {
  estado: string;
  fecha: string;
  camion_id: string;
  vendedor_id: string;
}

async function jornadaEnBase(request: APIRequestContext, api: DataApi, jornadaId: string) {
  const r = await request.get(
    `${api.url}/rest/v1/jornadas?select=estado,fecha,camion_id,vendedor_id&id=eq.${jornadaId}`,
    { headers: cabeceras(api, api.tokenDueno) }
  );
  expect(r.status()).toBe(200);
  return ((await r.json()) as JornadaEnBase[])[0];
}

interface Correccion {
  operacion_id: string;
  fecha_anterior: string;
  fecha_nueva: string;
  camion_anterior_id: string;
  camion_nuevo_id: string;
  motivo: string;
  actor_id: string;
}

/** Historial de correcciones de la jornada (leído como dueño, por la Data API). */
async function correccionesDe(request: APIRequestContext, api: DataApi, jornadaId: string) {
  const r = await request.get(
    `${api.url}/rest/v1/correcciones_jornada?select=operacion_id,fecha_anterior,fecha_nueva,camion_anterior_id,camion_nuevo_id,motivo,actor_id&jornada_id=eq.${jornadaId}&order=creado_en`,
    { headers: cabeceras(api, api.tokenDueno) }
  );
  expect(r.status()).toBe(200);
  return (await r.json()) as Correccion[];
}

/** Operaciones `correccion_jornada` de la jornada: una por corrección registrada. */
async function operacionesCorreccion(request: APIRequestContext, api: DataApi, jornadaId: string) {
  const r = await request.get(
    `${api.url}/rest/v1/operaciones?select=id,actor_id&tipo=eq.correccion_jornada&jornada_id=eq.${jornadaId}`,
    { headers: cabeceras(api, api.tokenDueno) }
  );
  expect(r.status()).toBe(200);
  return (await r.json()) as Array<{ id: string; actor_id: string }>;
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
  const fila = page.locator("table tbody tr").filter({ hasText: j.camion.nombre });
  await expect(fila).toHaveCount(1);
  await fila.getByRole("button", { name: "Ver detalle" }).click();
  const detalle = page.getByRole("region", { name: "Detalle de la jornada" });
  await expect(detalle).toContainText(j.camion.nombre);
  return { fila, detalle };
}

/** Completa y envía el formulario de corrección dentro del detalle. */
async function corregir(
  detalle: ReturnType<Page["getByRole"]>,
  valores: { fecha?: string; camion?: Camion; motivo: string },
  enviar: "click" | "dblclick" = "click"
) {
  await detalle.getByRole("button", { name: "Corregir jornada" }).click();
  if (valores.fecha) await detalle.getByLabel("Fecha", { exact: true }).fill(valores.fecha);
  if (valores.camion) await detalle.getByLabel("Camión", { exact: true }).selectOption({ label: valores.camion.etiqueta });
  await detalle.getByLabel("Motivo", { exact: true }).fill(valores.motivo);
  await detalle.getByRole("button", { name: "Registrar corrección" })[enviar]();
}

/** Solicitudes del navegador a la Data API (sin el login de Auth). */
function registrarSolicitudes(page: Page, api: DataApi) {
  const solicitudes: Request[] = [];
  page.on("request", (r) => {
    if (r.url().startsWith(api.url) && !r.url().includes("/auth/v1/")) solicitudes.push(r);
  });
  const mutadoras = () => solicitudes.filter((r) => !["GET", "HEAD", "OPTIONS"].includes(r.method()));
  return { mutadoras };
}

const exitoCorreccion = (page: Page) =>
  page.getByRole("status").filter({ hasText: "Corrección registrada" });

test.describe("corregir jornada (backend real)", () => {
  test("el dueño corrige la fecha: persiste, historial con motivo recortado y sólo se llamó a corregir_jornada", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "fecha");
    const nueva = sumarDias(j.fecha, 1);
    const red = registrarSolicitudes(page, api);
    const { detalle } = await abrirDetalle(page, j);
    await corregir(detalle, { fecha: nueva, motivo: "  Fecha mal cargada  " });
    await expect(exitoCorreccion(page)).toBeVisible();

    const enBase = await jornadaEnBase(request, api, j.id);
    expect(enBase).toMatchObject({ estado: "abierta", fecha: nueva, camion_id: j.camion.id, vendedor_id: ID_VENDEDOR });
    const historial = await correccionesDe(request, api, j.id);
    expect(historial).toEqual([
      expect.objectContaining({
        fecha_anterior: j.fecha, fecha_nueva: nueva,
        camion_anterior_id: j.camion.id, camion_nuevo_id: j.camion.id,
        motivo: "Fecha mal cargada", actor_id: ID_DUENO,
      }),
    ]);
    expect((await operacionesCorreccion(request, api, j.id)).map((o) => o.id)).toEqual([historial[0].operacion_id]);

    // Ninguna escritura directa: la única solicitud mutadora es la RPC.
    const mutadoras = red.mutadoras();
    expect(mutadoras.map((r) => `${r.method()} ${new URL(r.url()).pathname}`)).toEqual([
      "POST /rest/v1/rpc/corregir_jornada",
    ]);
    expect(mutadoras[0].postDataJSON()).toEqual({
      p_idempotency_key: expect.stringMatching(/^[0-9a-f-]{36}$/),
      p_jornada_id: j.id, p_fecha: nueva, p_camion_id: j.camion.id, p_motivo: "Fecha mal cargada",
    });

    // Persiste tras recargar: la jornada aparece en la fecha nueva.
    await page.reload();
    await abrirDetalle(page, { ...j, fecha: nueva });
  });

  test("el encargado corrige el camión", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "camion");
    const otro = await crearCamion(request, api, "destino");
    const enc = await entrarComo(browser, baseURL, CUENTAS.encargado);
    const { fila, detalle } = await abrirDetalle(enc.page, j);
    await corregir(detalle, { camion: otro, motivo: "Camión en taller" });
    await expect(exitoCorreccion(enc.page)).toBeVisible();
    await expect(fila).toContainText(otro.nombre);
    expect(await jornadaEnBase(request, api, j.id)).toMatchObject({ fecha: j.fecha, camion_id: otro.id });
    const historial = await correccionesDe(request, api, j.id);
    expect(historial.map((c) => [c.camion_anterior_id, c.camion_nuevo_id, c.actor_id])).toEqual([
      [j.camion.id, otro.id, ID_ENCARGADO],
    ]);
    await enc.contexto.close();
  });

  test("corrige fecha y camión a la vez", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "ambos");
    const otro = await crearCamion(request, api, "ambos-dest");
    const nueva = sumarDias(j.fecha, 2);
    const { detalle } = await abrirDetalle(page, j);
    await corregir(detalle, { fecha: nueva, camion: otro, motivo: "Reprogramación" });
    await expect(exitoCorreccion(page)).toBeVisible();
    expect(await jornadaEnBase(request, api, j.id)).toMatchObject({ estado: "abierta", fecha: nueva, camion_id: otro.id });
    expect(await correccionesDe(request, api, j.id)).toHaveLength(1);
  });

  test("validación local: fecha pasada, sin motivo o sin cambios no envían nada", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "valid");
    const red = registrarSolicitudes(page, api);
    const { detalle } = await abrirDetalle(page, j);
    await corregir(detalle, { fecha: sumarDias(hoyTucuman(), -1), motivo: "x" });
    await expect(detalle.getByRole("alert")).toHaveText("La fecha no puede ser anterior al día operativo actual.");
    await detalle.getByLabel("Fecha", { exact: true }).fill(sumarDias(j.fecha, 1));
    await detalle.getByLabel("Motivo", { exact: true }).fill("   ");
    await detalle.getByRole("button", { name: "Registrar corrección" }).click();
    await expect(detalle.getByRole("alert")).toHaveText("El motivo es obligatorio.");
    await detalle.getByLabel("Fecha", { exact: true }).fill(j.fecha);
    await detalle.getByLabel("Motivo", { exact: true }).fill("sin cambios");
    await detalle.getByRole("button", { name: "Registrar corrección" }).click();
    await expect(detalle.getByRole("alert")).toContainText("No hay cambios para registrar");
    expect(red.mutadoras()).toEqual([]);
    expect(await correccionesDe(request, api, j.id)).toEqual([]);
  });

  test("la base rechaza una fecha pasada aunque se llame a la RPC directamente", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "pasada");
    const r = await rpc(request, api, api.tokenDueno, "corregir_jornada", {
      p_idempotency_key: randomUUID(), p_jornada_id: j.id,
      p_fecha: sumarDias(hoyTucuman(), -1), p_camion_id: j.camion.id, p_motivo: "E2E S2",
    });
    expect(r.status()).toBe(400);
    expect(await r.json()).toMatchObject({ code: "PT400", message: "jornada_fecha_invalida" });
    expect(await jornadaEnBase(request, api, j.id)).toMatchObject({ fecha: j.fecha });
    expect(await correccionesDe(request, api, j.id)).toEqual([]);
  });

  test("par (camión, fecha) ocupado: rechazo seguro, sin efectos", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "par");
    // Otra jornada ya ocupa el par (camión, fecha) de destino. Por la precedencia
    // de la RPC, jornada_duplicada se informa antes que jornada_vendedor_ocupado.
    const ocupante = await crearCamion(request, api, "ocupante");
    const fechaOcupada = sumarDias(j.fecha, 3);
    await sembrarJornada(request, api, "ocupada", { fecha: fechaOcupada, camion: ocupante });

    const { detalle } = await abrirDetalle(page, j);
    await corregir(detalle, { fecha: fechaOcupada, camion: ocupante, motivo: "Par ocupado" });
    await expect(page.getByRole("alert").filter({ hasText: "Ese camión ya tiene una jornada en esa fecha." })).toBeVisible();
    expect(await jornadaEnBase(request, api, j.id)).toMatchObject({ fecha: j.fecha, camion_id: j.camion.id });
    expect(await correccionesDe(request, api, j.id)).toEqual([]);
    expect(await operacionesCorreccion(request, api, j.id)).toEqual([]);
  });

  test("doble clic con respuesta lenta: una sola solicitud y una sola corrección", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "doble");
    await page.route("**/rest/v1/rpc/corregir_jornada", async (route) => {
      const respuesta = await route.fetch();
      await new Promise((r) => setTimeout(r, 1500));
      await route.fulfill({ response: respuesta });
    });
    const red = registrarSolicitudes(page, api);
    const { detalle } = await abrirDetalle(page, j);
    await corregir(detalle, { fecha: sumarDias(j.fecha, 1), motivo: "Doble clic" }, "dblclick");
    await expect(detalle.getByRole("button", { name: /Registrando corrección/ })).toBeDisabled();
    await expect(exitoCorreccion(page)).toBeVisible();
    expect(red.mutadoras()).toHaveLength(1);
    expect(await operacionesCorreccion(request, api, j.id)).toHaveLength(1);
    expect(await correccionesDe(request, api, j.id)).toHaveLength(1);
  });

  test("pérdida sin efecto: la jornada sigue igual, reintento visible con la MISMA clave y una sola corrección", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "reint");
    const nueva = sumarDias(j.fecha, 1);
    let cortar = true;
    await page.route("**/rest/v1/rpc/corregir_jornada", async (route) => {
      if (cortar) await route.abort("failed"); // nunca llega a PostgreSQL
      else await route.continue();
    });
    const red = registrarSolicitudes(page, api);
    const { detalle } = await abrirDetalle(page, j);
    await corregir(detalle, { fecha: nueva, motivo: "Reintento seguro" });
    await expect(detalle.getByRole("alert")).toContainText("la jornada sigue sin cambios");
    const reintento = detalle.getByRole("button", { name: "Reintentar corrección" });
    await expect(reintento).toBeVisible();
    expect(await jornadaEnBase(request, api, j.id)).toMatchObject({ fecha: j.fecha });
    expect(await correccionesDe(request, api, j.id)).toEqual([]);

    cortar = false;
    await reintento.click();
    await expect(exitoCorreccion(page)).toBeVisible();
    const envios = red.mutadoras();
    expect(envios.length).toBeGreaterThanOrEqual(2);
    expect(new Set(envios.map((r) => new URL(r.url()).pathname))).toEqual(new Set(["/rest/v1/rpc/corregir_jornada"]));
    // Misma clave y mismo payload en todos los envíos (la huella del servidor no cambia).
    expect(new Set(envios.map((r) => JSON.stringify(r.postDataJSON()))).size).toBe(1);
    expect(await jornadaEnBase(request, api, j.id)).toMatchObject({ fecha: nueva });
    expect(await correccionesDe(request, api, j.id)).toHaveLength(1);
  });

  test("pérdida con efecto (M-01): la coincidencia NO es éxito; el reintento con la MISMA clave lo confirma y no duplica", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "perdida");
    const nueva = sumarDias(j.fecha, 1);
    // Primero el servidor SÍ procesa cada solicitud, pero el navegador nunca
    // recibe la respuesta; después las respuestas vuelven a llegar.
    let perder = true;
    await page.route("**/rest/v1/rpc/corregir_jornada", async (route) => {
      if (!perder) return route.continue();
      await route.fetch();
      await route.abort("failed");
    });
    const red = registrarSolicitudes(page, api);
    const { detalle } = await abrirDetalle(page, j);
    await corregir(detalle, { fecha: nueva, motivo: "Respuesta perdida" });
    await expect(detalle.getByRole("alert")).toContainText("no se puede asegurar que sea por esta corrección");
    await expect(exitoCorreccion(page)).toHaveCount(0);
    expect(await correccionesDe(request, api, j.id)).toHaveLength(1);

    perder = false;
    await detalle.getByRole("button", { name: "Reintentar corrección" }).click();
    await expect(exitoCorreccion(page)).toBeVisible();
    const envios = red.mutadoras();
    expect(new Set(envios.map((r) => `${r.method()} ${new URL(r.url()).pathname}`))).toEqual(
      new Set(["POST /rest/v1/rpc/corregir_jornada"])
    );
    expect(new Set(envios.map((r) => (r.postDataJSON() as { p_idempotency_key: string }).p_idempotency_key)).size).toBe(1);
    expect(await operacionesCorreccion(request, api, j.id)).toHaveLength(1);
    expect(await correccionesDe(request, api, j.id)).toHaveLength(1);
    expect(await jornadaEnBase(request, api, j.id)).toMatchObject({ fecha: nueva });
  });

  test("dos correcciones consecutivas (M-03): tras el éxito y la relectura se puede corregir de nuevo, con otra clave", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "doscorr");
    const primero = await crearCamion(request, api, "doscorr-1");
    const segundo = await crearCamion(request, api, "doscorr-2");
    const red = registrarSolicitudes(page, api);
    const { detalle } = await abrirDetalle(page, j);
    await corregir(detalle, { camion: primero, motivo: "Primer ajuste" });
    await expect(exitoCorreccion(page)).toBeVisible();
    await expect(detalle).toContainText(primero.nombre);
    await corregir(detalle, { camion: segundo, motivo: "Segundo ajuste" });
    await expect(detalle).toContainText(segundo.nombre);
    await expect(exitoCorreccion(page)).toBeVisible();

    const envios = red.mutadoras();
    expect(envios).toHaveLength(2);
    const claves = envios.map((r) => (r.postDataJSON() as { p_idempotency_key: string }).p_idempotency_key);
    expect(new Set(claves).size).toBe(2);
    expect(await jornadaEnBase(request, api, j.id)).toMatchObject({ fecha: j.fecha, camion_id: segundo.id });
    const historial = await correccionesDe(request, api, j.id);
    expect(historial.map((c) => [c.camion_anterior_id, c.camion_nuevo_id, c.motivo])).toEqual(
      expect.arrayContaining([
        [j.camion.id, primero.id, "Primer ajuste"],
        [primero.id, segundo.id, "Segundo ajuste"],
      ])
    );
    expect(historial).toHaveLength(2);
    expect(await operacionesCorreccion(request, api, j.id)).toHaveLength(2);
  });

  test("vista móvil (393×851): controles táctiles, sin scroll horizontal y corrección registrada", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "movil");
    const m = await entrarComo(browser, baseURL, CUENTAS.dueno, {
      viewport: { width: 393, height: 851 }, hasTouch: true, isMobile: true,
    });
    await m.page.goto("/jornadas");
    await m.page.getByLabel("Fecha operativa").fill(j.fecha);
    const tarjeta = m.page.locator("ul.md\\:hidden > li").filter({ hasText: j.camion.nombre });
    await expect(tarjeta).toHaveCount(1);
    await tarjeta.getByRole("button", { name: "Ver detalle" }).click();
    const detalle = m.page.getByRole("region", { name: "Detalle de la jornada" });
    const abrir = detalle.getByRole("button", { name: "Corregir jornada" });
    expect((await abrir.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
    await abrir.click();
    for (const etiqueta of ["Fecha", "Camión"]) {
      expect((await detalle.getByLabel(etiqueta, { exact: true }).boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
    }
    await detalle.getByLabel("Fecha", { exact: true }).fill(sumarDias(j.fecha, 1));
    await detalle.getByLabel("Motivo", { exact: true }).fill("Desde el celular");
    expect(await m.page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
    const registrar = detalle.getByRole("button", { name: "Registrar corrección" });
    expect((await registrar.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
    await registrar.click();
    await expect(exitoCorreccion(m.page)).toBeVisible();
    expect(await correccionesDe(request, api, j.id)).toHaveLength(1);
    await m.contexto.close();
  });
});

test.describe("corregir jornada: roles y empresa (backend real)", () => {
  test("el vendedor asignado no ve la acción y la base rechaza su intento directo", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "vend");
    const v = await entrarComo(browser, baseURL, CUENTAS.vendedor);
    await v.page.goto("/jornadas");
    await expect(v.page.getByRole("heading", { name: "Mi jornada" })).toBeVisible();
    await v.page.getByLabel("Fecha operativa").fill(j.fecha);
    const fila = v.page.locator("table tbody tr").filter({ hasText: j.camion.nombre });
    await expect(fila).toHaveCount(1);
    await fila.getByRole("button", { name: "Ver detalle" }).click();
    await expect(v.page.getByRole("region", { name: "Detalle de la jornada" })).toBeVisible();
    await expect(v.page.getByRole("button", { name: /Corregir jornada/ })).toHaveCount(0);
    await v.contexto.close();

    const tokenVendedor = await tokenDe(request, api, CUENTAS.vendedor);
    const r = await rpc(request, api, tokenVendedor, "corregir_jornada", {
      p_idempotency_key: randomUUID(), p_jornada_id: j.id,
      p_fecha: sumarDias(j.fecha, 1), p_camion_id: j.camion.id, p_motivo: "intento del vendedor",
    });
    expect(r.status()).toBe(403);
    expect(await r.json()).toMatchObject({ code: "PT403", message: "jornada_no_autorizado" });
    expect(await jornadaEnBase(request, api, j.id)).toMatchObject({ fecha: j.fecha });
    expect(await correccionesDe(request, api, j.id)).toEqual([]);
  });

  test("otra empresa: la jornada no es visible y su intento directo se rechaza sin efectos", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "otraemp");
    const otra = await entrarComo(browser, baseURL, CUENTAS.otraEmpresa);
    await otra.page.goto("/jornadas");
    await otra.page.getByLabel("Fecha operativa").fill(j.fecha);
    await expect(otra.page.locator('p[aria-live="polite"]')).toHaveText(/^No hay jornadas el /);
    await expect(otra.page.getByText(j.camion.nombre)).toHaveCount(0);
    await expect(otra.page.getByRole("button", { name: /Corregir jornada/ })).toHaveCount(0);
    await otra.contexto.close();

    const tokenOtra = await tokenDe(request, api, CUENTAS.otraEmpresa);
    const r = await rpc(request, api, tokenOtra, "corregir_jornada", {
      p_idempotency_key: randomUUID(), p_jornada_id: j.id,
      p_fecha: sumarDias(j.fecha, 1), p_camion_id: j.camion.id, p_motivo: "intento de otra empresa",
    });
    expect(r.status()).toBe(404);
    expect(await r.json()).toMatchObject({ code: "PT404", message: "jornada_no_encontrada" });
    expect(await jornadaEnBase(request, api, j.id)).toMatchObject({ fecha: j.fecha });
    expect(await correccionesDe(request, api, j.id)).toEqual([]);
  });

  test("una jornada cargada no ofrece corregir", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const j = await sembrarJornada(request, api, "cargada");
    const rp = await request.get(
      `${api.url}/rest/v1/productos?select=id&activo=eq.true&forma_venta=eq.unidad&order=id&limit=1`,
      { headers: cabeceras(api, api.tokenDueno) }
    );
    const [{ id: producto }] = (await rp.json()) as Array<{ id: string }>;
    expect((await rpc(request, api, api.tokenDueno, "registrar_ingreso", {
      p_idempotency_key: randomUUID(), p_producto_id: producto, p_cantidad: 2, p_motivo: "E2E S2",
    })).status()).toBe(200);
    expect((await rpc(request, api, api.tokenDueno, "registrar_carga", {
      p_idempotency_key: randomUUID(), p_jornada_id: j.id, p_productos: [producto], p_cantidades: [1],
    })).status()).toBe(200);

    const red = registrarSolicitudes(page, api);
    const { detalle } = await abrirDetalle(page, j);
    await expect(detalle.getByRole("button", { name: "Corregir jornada" })).toBeDisabled();
    await expect(detalle).toContainText("Sólo se puede corregir una jornada abierta");
    expect(red.mutadoras()).toEqual([]);
  });
});
