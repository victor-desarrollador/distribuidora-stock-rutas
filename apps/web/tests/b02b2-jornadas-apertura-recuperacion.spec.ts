// D-B2-1 / T-1 + T-2 — E2E de recuperación de la apertura de jornada.
//
// T-1: mientras la apertura envía, consulta o tiene resultado desconocido, la
// pantalla pide al navegador confirmar la salida (beforeunload); en los demás
// estados, no. T-2: ante `jornada_duplicada` o `jornada_vendedor_ocupado`, el
// panel orienta a revisar las jornadas de la fecha, sin declarar nunca el éxito.
//
// Backend real (Supabase local con supabase/seed.sql y E-PL1): GoTrue y
// PostgREST reales. La «respuesta perdida» deja llegar la solicitud REAL a
// PostgreSQL y descarta su respuesta en el navegador: no se simulan datos.
// Los ayudantes copian los de b02b2-jornadas-apertura.spec.ts (D-B2-1), que no
// se modifica. Nada aquí toca staging ni producción.
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

// Como los muestra el selector: «nombre — rol» (seed.sql).
const OPCION_VENDEDOR = "Vendedor de prueba — Vendedor/Piloto";

const MENSAJE_DESCONOCIDO = "No se pudo confirmar si la jornada se abrió.";

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
const ddmmaaaa = (f: string) => `${f.slice(8, 10)}/${f.slice(5, 7)}/${f.slice(0, 4)}`;

interface Camion {
  id: string;
  nombre: string;
  etiqueta: string; // como lo muestra el selector: «nombre · patente»
}

async function crearCamion(request: APIRequestContext, api: DataApi, etiqueta: string, token = api.tokenDueno): Promise<Camion> {
  const nombre = `AP-${etiqueta}-${randomUUID().slice(0, 8)}`;
  const patente = `AP-${randomUUID().slice(0, 12)}`;
  const r = await rpc(request, api, token, "crear_camion", { p_patente: patente, p_nombre: nombre });
  expect(r.status()).toBe(200);
  return { id: (await r.json()) as string, nombre, etiqueta: `${nombre} · ${patente}` };
}

async function abrirPorApi(request: APIRequestContext, api: DataApi, camion: Camion, fecha: string, vendedorId: string) {
  const r = await rpc(request, api, api.tokenDueno, "abrir_jornada", {
    p_idempotency_key: randomUUID(), p_camion_id: camion.id, p_fecha: fecha, p_vendedor_id: vendedorId,
  });
  expect(r.status()).toBe(200);
  return (await r.json()) as string;
}

interface JornadaEnBase {
  id: string;
  estado: string;
  fecha: string;
  camion_id: string;
  vendedor_id: string;
  abierta_por: string;
  operacion_apertura_id: string;
}

async function jornadasDelCamion(request: APIRequestContext, api: DataApi, camionId: string) {
  const r = await request.get(
    `${api.url}/rest/v1/jornadas?select=id,estado,fecha,camion_id,vendedor_id,abierta_por,operacion_apertura_id&camion_id=eq.${camionId}&order=fecha`,
    { headers: cabeceras(api, api.tokenDueno) }
  );
  expect(r.status()).toBe(200);
  return (await r.json()) as JornadaEnBase[];
}

async function operacionesDeClave(request: APIRequestContext, api: DataApi, clave: string) {
  const r = await request.get(
    `${api.url}/rest/v1/operaciones?select=id,tipo,actor_id&idempotency_key=eq.${clave}`,
    { headers: cabeceras(api, api.tokenDueno) }
  );
  expect(r.status()).toBe(200);
  return (await r.json()) as Array<{ id: string; tipo: string; actor_id: string }>;
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

/** Solicitudes del navegador a la Data API (sin el login de Auth). */
function registrarSolicitudes(page: Page, api: DataApi) {
  const solicitudes: Request[] = [];
  page.on("request", (r) => {
    if (r.url().startsWith(api.url) && !r.url().includes("/auth/v1/")) solicitudes.push(r);
  });
  const de = (ruta: string) => solicitudes.filter((r) => new URL(r.url()).pathname === ruta);
  const noLectura = () => solicitudes.filter((r) => !["GET", "HEAD", "OPTIONS"].includes(r.method()));
  return { todas: () => solicitudes, de, noLectura };
}

const panelApertura = (page: Page) => page.getByRole("region", { name: "Nueva jornada" });

/** Abre el formulario y espera la lista real de vendedores. */
async function abrirFormulario(page: Page) {
  await page.goto("/jornadas");
  const respuesta = page.waitForResponse((r) => r.url().includes("/rest/v1/rpc/listar_vendedores_jornada"));
  await panelApertura(page).getByRole("button", { name: "Nueva jornada", exact: true }).click();
  const r = await respuesta;
  const panel = panelApertura(page);
  await expect(panel.getByLabel("Vendedor", { exact: true })).toBeEnabled();
  return { panel, respuestaLista: r };
}

async function completar(panel: Locator, valores: { camion: Camion; fecha: string; vendedor: string }) {
  await panel.getByLabel("Camión", { exact: true }).selectOption({ label: valores.camion.etiqueta });
  await panel.getByLabel("Fecha operativa", { exact: true }).fill(valores.fecha);
  await panel.getByLabel("Vendedor", { exact: true }).selectOption({ label: valores.vendedor });
}

// El recuadro visible de éxito (la región `status` es sólo para lectores de pantalla).
const exito = (page: Page) => panelApertura(page).locator("p").filter({ hasText: /^Jornada abierta\.$/ });

const ORIENTACION_DUPLICADA = "Puede que esa jornada ya se haya abierto en un intento anterior";
const ORIENTACION_VENDEDOR = "Puede que ese vendedor ya tenga asignada la jornada en un intento anterior";
const NO_CONFIRMA = "Ver la lista no confirma que tu apertura se haya registrado.";
const RIESGO_RECARGA = "Si recargás o cerrás esta pantalla, se pierde el reintento seguro de esta apertura.";

/** Pierde las respuestas de abrir_jornada (la solicitud real sí llega a PostgreSQL) mientras `perder()` sea true. */
async function perderRespuestas(page: Page, perder: () => boolean) {
  await page.route("**/rest/v1/rpc/abrir_jornada", async (route) => {
    if (!perder()) return route.continue();
    await route.fetch();
    await route.abort("failed");
  });
}

const claveDe = (r: Request) => (r.postDataJSON() as Record<string, string>).p_idempotency_key;

test.describe("recuperación de la apertura (backend real)", () => {
  test("T-1: con resultado desconocido, cerrar pide confirmación; al rechazarla la intención sigue y sólo el replay confirma", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "t1");
    const fecha = fechaFutura();
    let perder = true;
    await perderRespuestas(page, () => perder);

    const { panel } = await abrirFormulario(page);
    await completar(panel, { camion, fecha, vendedor: OPCION_VENDEDOR });
    await panel.getByRole("button", { name: "Abrir jornada" }).click();
    await expect(panel.getByRole("alert")).toContainText(MENSAJE_DESCONOCIDO);
    await expect(panel).toContainText(RIESGO_RECARGA);

    const dialogos: string[] = [];
    page.on("dialog", (d) => {
      dialogos.push(d.type());
      void d.dismiss();
    });
    await page.close({ runBeforeUnload: true });
    await expect.poll(() => dialogos).toEqual(["beforeunload"]);
    expect(page.isClosed()).toBe(false);
    // Rechazado el aviso, la página y la intención siguen: el replay confirma.
    await expect(panel.getByRole("alert")).toContainText(MENSAJE_DESCONOCIDO);
    expect(await jornadasDelCamion(request, api, camion.id)).toHaveLength(1);
    perder = false;
    await panel.getByRole("button", { name: "Reintentar apertura" }).click();
    await expect(exito(page)).toBeVisible();

    // Resuelta la apertura, salir ya no pide confirmación.
    const cerrada = page.waitForEvent("close");
    await page.close({ runBeforeUnload: true });
    await cerrada;
    expect(dialogos).toEqual(["beforeunload"]);
  });

  test("T-1: en reposo, con el formulario abierto o tras un rechazo, salir no pide confirmación", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "t1-reposo");
    const fecha = fechaFutura();
    await abrirPorApi(request, api, camion, fecha, ID_VENDEDOR);

    for (const paso of ["reposo", "formulario", "rechazo"] as const) {
      const s = await entrarComo(browser, baseURL, CUENTAS.dueno);
      const dialogos: string[] = [];
      s.page.on("dialog", (d) => {
        dialogos.push(d.type());
        void d.dismiss();
      });
      await s.page.goto("/jornadas");
      if (paso !== "reposo") {
        const { panel } = await abrirFormulario(s.page);
        await panel.getByLabel("Camión", { exact: true }).click(); // interacción del usuario
        if (paso === "rechazo") {
          await completar(panel, { camion, fecha, vendedor: OPCION_VENDEDOR });
          await panel.getByRole("button", { name: "Abrir jornada" }).click();
          await expect(panel.getByRole("alert").first()).toContainText("Ese camión ya tiene una jornada en esa fecha.");
        }
      }
      const cerrada = s.page.waitForEvent("close");
      await s.page.close({ runBeforeUnload: true });
      await cerrada;
      expect(dialogos, paso).toEqual([]);
      await s.contexto.close();
    }
  });

  test("T-2: respuesta perdida + recarga + nuevo intento → jornada_duplicada con orientación; ver la fecha informa y nunca confirma", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "t2-dup");
    const fecha = fechaFutura();
    const red = registrarSolicitudes(page, api);
    let perder = true;
    await perderRespuestas(page, () => perder);

    const primero = await abrirFormulario(page);
    await completar(primero.panel, { camion, fecha, vendedor: OPCION_VENDEDOR });
    await primero.panel.getByRole("button", { name: "Abrir jornada" }).click();
    await expect(primero.panel.getByRole("alert")).toContainText(MENSAJE_DESCONOCIDO);

    // Recarga aceptando el aviso: la clave en memoria se pierde.
    const dialogos: string[] = [];
    page.on("dialog", (d) => {
      dialogos.push(d.type());
      void d.accept();
    });
    await page.reload();
    expect(dialogos).toEqual(["beforeunload"]);
    perder = false;
    await expect(panelApertura(page).getByRole("button", { name: "Nueva jornada", exact: true })).toBeVisible();

    // Mismo camión, fecha y vendedor: es otra intención (otra clave) y el servidor rechaza.
    const segundo = await abrirFormulario(page);
    await completar(segundo.panel, { camion, fecha, vendedor: OPCION_VENDEDOR });
    await segundo.panel.getByRole("button", { name: "Abrir jornada" }).click();
    await expect(segundo.panel.getByRole("alert").first()).toContainText("Ese camión ya tiene una jornada en esa fecha.");
    await expect(segundo.panel).toContainText(ORIENTACION_DUPLICADA);
    await expect(segundo.panel).toContainText(NO_CONFIRMA);
    await expect(exito(page)).toHaveCount(0);

    const claves = [...new Set(red.de("/rest/v1/rpc/abrir_jornada").map(claveDe))];
    expect(claves).toHaveLength(2);
    const enBase = await jornadasDelCamion(request, api, camion.id);
    expect(enBase).toHaveLength(1);
    expect(await operacionesDeClave(request, api, claves[0])).toHaveLength(1);
    expect(await operacionesDeClave(request, api, claves[1])).toHaveLength(0);

    // Ver la fecha muestra la jornada existente; la apertura sigue sin darse por registrada.
    await segundo.panel.getByRole("button", { name: `Ver jornadas del ${ddmmaaaa(fecha)}` }).click();
    await expect(page.locator("table tbody tr").filter({ hasText: camion.nombre })).toHaveCount(1);
    await expect(segundo.panel).toContainText(NO_CONFIRMA);
    await expect(exito(page)).toHaveCount(0);
    expect(red.de("/rest/v1/rpc/abrir_jornada").length).toBeGreaterThanOrEqual(2);
    expect(await jornadasDelCamion(request, api, camion.id)).toHaveLength(1);
  });

  test("T-2: jornada_vendedor_ocupado → orientación y ver la fecha; no se crea nada", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const ocupado = await crearCamion(request, api, "t2-ocupado");
    const libre = await crearCamion(request, api, "t2-libre");
    const fecha = fechaFutura();
    await abrirPorApi(request, api, ocupado, fecha, ID_VENDEDOR);

    const { panel } = await abrirFormulario(page);
    await completar(panel, { camion: libre, fecha, vendedor: OPCION_VENDEDOR });
    await panel.getByRole("button", { name: "Abrir jornada" }).click();
    await expect(panel.getByRole("alert").first()).toContainText("El vendedor ya tiene una jornada en esa fecha.");
    await expect(panel).toContainText(ORIENTACION_VENDEDOR);
    await expect(panel).toContainText(NO_CONFIRMA);
    await panel.getByRole("button", { name: `Ver jornadas del ${ddmmaaaa(fecha)}` }).click();
    await expect(page.locator("table tbody tr").filter({ hasText: ocupado.nombre })).toHaveCount(1);
    await expect(exito(page)).toHaveCount(0);
    expect(await jornadasDelCamion(request, api, libre.id)).toEqual([]);
  });

  test("T-2: otros rechazos no muestran la orientación", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "t2-otro");
    const fecha = fechaFutura();
    await abrirPorApi(request, api, camion, fecha, ID_VENDEDOR);
    const { panel } = await abrirFormulario(page);
    await completar(panel, { camion, fecha: sumarDias(fecha, 1), vendedor: OPCION_VENDEDOR });
    await panel.getByRole("button", { name: "Abrir jornada" }).click();
    await expect(panel.getByRole("alert").first()).toContainText("El camión tiene otra jornada sin cerrar.");
    await expect(panel).not.toContainText(NO_CONFIRMA);
    await expect(panel.getByRole("button", { name: /^Ver jornadas del/ })).toHaveCount(0);
  });
});
