// D-B2-1 — E2E de «Abrir jornada» en la pantalla REAL de jornadas.
//
// Backend real (Supabase local con supabase/seed.sql y la migración E-PL1
// `listar_vendedores_jornada`): GoTrue y PostgREST reales; la base decide roles,
// empresa, fechas, unicidades e idempotencia. Cada caso siembra sus propios
// camiones y usa una fecha futura aleatoria. La «respuesta perdida» se provoca
// dejando que la solicitud REAL llegue a PostgreSQL y descartando su respuesta
// en el navegador: no se simulan datos. Nada aquí toca staging ni producción.
//
// Los ayudantes de siembra y sesión siguen el patrón de
// b02b2-jornadas-correccion.spec.ts (S2), que no se modifica.
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

const ID_DUENO = "00000000-0000-4000-8000-000000000001";
const ID_ENCARGADO = "00000000-0000-4000-8000-000000000002";
const ID_VENDEDOR = "00000000-0000-4000-8000-000000000003";
const ID_OTRA_EMPRESA = "00000000-0000-4000-8000-000000000006";

// Como los muestra el selector: «nombre — rol» (seed.sql).
const OPCION_DUENO = "Dueño de prueba — Dueño";
const OPCION_ENCARGADO = "Encargado de prueba — Encargado";
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

async function textosOpciones(select: Locator) {
  return (await select.locator("option").allTextContents()).map((t) => t.trim());
}

// El recuadro visible de éxito (la región `status` es sólo para lectores de pantalla).
const exito = (page: Page) => panelApertura(page).locator("p").filter({ hasText: /^Jornada abierta\.$/ });

test.describe("abrir jornada (backend real)", () => {
  test("dueño: lista protegida con conteo exacto, apertura con el id devuelto, persistencia y sólo RPC", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "dueno");
    const fecha = fechaFutura();
    const red = registrarSolicitudes(page, api);

    const { panel, respuestaLista } = await abrirFormulario(page);

    // Conteo exacto de PostgREST sobre la RPC protegida (POST, Prefer: count=exact).
    const pedido = respuestaLista.request();
    expect(pedido.method()).toBe("POST");
    expect((await pedido.allHeaders())["prefer"] ?? "").toContain("count=exact");
    expect(pedido.postDataJSON()).toEqual({});
    expect(respuestaLista.status()).toBe(200);
    const filas = (await respuestaLista.json()) as Array<Record<string, unknown>>;
    expect(respuestaLista.headers()["content-range"]).toBe(`0-${filas.length - 1}/${filas.length}`);
    // Sólo activos de la empresa, los tres roles, orden nombre COLLATE "C"; sin login ni correo.
    expect(filas).toEqual([
      { usuario_id: ID_DUENO, nombre: "Dueño de prueba", rol: "dueno" },
      { usuario_id: ID_ENCARGADO, nombre: "Encargado de prueba", rol: "encargado" },
      { usuario_id: ID_VENDEDOR, nombre: "Vendedor de prueba", rol: "vendedor_piloto" },
    ]);
    expect(await textosOpciones(panel.getByLabel("Vendedor", { exact: true }))).toEqual([
      "Elegí un vendedor", OPCION_DUENO, OPCION_ENCARGADO, OPCION_VENDEDOR,
    ]);
    // Sin campo libre para un uuid.
    await expect(panel.locator("input")).toHaveCount(1);
    await expect(panel.locator('input[type="date"]')).toHaveAttribute("min", hoyTucuman());

    await completar(panel, { camion, fecha, vendedor: OPCION_VENDEDOR });
    const respuestaAbrir = page.waitForResponse((r) => r.url().includes("/rest/v1/rpc/abrir_jornada"));
    await panel.getByRole("button", { name: "Abrir jornada" }).click();
    const abrir = await respuestaAbrir;
    expect(abrir.status()).toBe(200);
    const idDevuelto = (await abrir.json()) as string;
    await expect(exito(page)).toBeVisible();
    await expect(panel).toContainText(camion.etiqueta);
    await expect(panel).toContainText("Vendedor de prueba (Vendedor/Piloto)");

    // Estado real: una sola jornada, abierta, con el id devuelto.
    const enBase = await jornadasDelCamion(request, api, camion.id);
    expect(enBase).toEqual([
      expect.objectContaining({
        id: idDevuelto, estado: "abierta", fecha, vendedor_id: ID_VENDEDOR, abierta_por: ID_DUENO,
      }),
    ]);

    // Sólo RPC: la lectura protegida y una apertura con la clave y el payload exactos.
    expect(red.noLectura().map((r) => `${r.method()} ${new URL(r.url()).pathname}`)).toEqual([
      "POST /rest/v1/rpc/listar_vendedores_jornada",
      "POST /rest/v1/rpc/abrir_jornada",
    ]);
    const cuerpo = red.de("/rest/v1/rpc/abrir_jornada")[0].postDataJSON() as Record<string, string>;
    expect(cuerpo).toEqual({
      p_idempotency_key: expect.stringMatching(/^[0-9a-f-]{36}$/),
      p_camion_id: camion.id, p_fecha: fecha, p_vendedor_id: ID_VENDEDOR,
    });
    const ops = await operacionesDeClave(request, api, cuerpo.p_idempotency_key);
    expect(ops).toEqual([{ id: enBase[0].operacion_apertura_id, tipo: "apertura_jornada", actor_id: ID_DUENO }]);

    // Se ve en la lista y persiste tras recargar.
    await panel.getByRole("button", { name: `Ver jornadas del ${ddmmaaaa(fecha)}` }).click();
    await expect(page.locator("table tbody tr").filter({ hasText: camion.nombre })).toHaveCount(1);
    await page.reload();
    await page.getByLabel("Fecha operativa").first().fill(fecha);
    await expect(page.locator("table tbody tr").filter({ hasText: camion.nombre })).toHaveCount(1);
  });

  test("encargado: abre asignando al dueño como vendedor", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "encargado");
    const fecha = fechaFutura();
    const enc = await entrarComo(browser, baseURL, CUENTAS.encargado);
    const { panel } = await abrirFormulario(enc.page);
    await completar(panel, { camion, fecha, vendedor: OPCION_DUENO });
    await panel.getByRole("button", { name: "Abrir jornada" }).click();
    await expect(exito(enc.page)).toBeVisible();
    expect(await jornadasDelCamion(request, api, camion.id)).toEqual([
      expect.objectContaining({ estado: "abierta", fecha, vendedor_id: ID_DUENO, abierta_por: ID_ENCARGADO }),
    ]);
    await enc.contexto.close();
  });

  test("jornada_duplicada: se informa, no se crea nada y se corrige como intención nueva", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "dup");
    const otro = await crearCamion(request, api, "dup-otro");
    const fecha = fechaFutura();
    const existente = await abrirPorApi(request, api, camion, fecha, ID_VENDEDOR);
    const red = registrarSolicitudes(page, api);

    const { panel } = await abrirFormulario(page);
    await completar(panel, { camion, fecha, vendedor: OPCION_DUENO });
    await panel.getByRole("button", { name: "Abrir jornada" }).click();
    await expect(panel.getByRole("alert")).toContainText("Ese camión ya tiene una jornada en esa fecha.");
    await expect(exito(page)).toHaveCount(0);
    expect((await jornadasDelCamion(request, api, camion.id)).map((j) => j.id)).toEqual([existente]);

    // El formulario sigue abierto: se cambia el camión y se reenvía con OTRA clave.
    await panel.getByLabel("Camión", { exact: true }).selectOption({ label: otro.etiqueta });
    await panel.getByRole("button", { name: "Abrir jornada" }).click();
    await expect(exito(page)).toBeVisible();
    const claves = red.de("/rest/v1/rpc/abrir_jornada").map((r) => (r.postDataJSON() as Record<string, string>).p_idempotency_key);
    expect(claves).toHaveLength(2);
    expect(claves[0]).not.toBe(claves[1]);
    expect(await jornadasDelCamion(request, api, otro.id)).toEqual([
      expect.objectContaining({ fecha, vendedor_id: ID_DUENO }),
    ]);
  });

  test("jornada_camion_con_jornada_abierta: se informa y no se crea nada", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "abierta");
    const fecha = fechaFutura();
    const existente = await abrirPorApi(request, api, camion, fecha, ID_VENDEDOR);
    const { panel } = await abrirFormulario(page);
    await completar(panel, { camion, fecha: sumarDias(fecha, 1), vendedor: OPCION_DUENO });
    await panel.getByRole("button", { name: "Abrir jornada" }).click();
    await expect(panel.getByRole("alert")).toContainText("El camión tiene otra jornada sin cerrar.");
    expect((await jornadasDelCamion(request, api, camion.id)).map((j) => j.id)).toEqual([existente]);
  });

  test("jornada_vendedor_ocupado: se informa y no se crea nada", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const ocupado = await crearCamion(request, api, "ocupado");
    const libre = await crearCamion(request, api, "libre");
    const fecha = fechaFutura();
    await abrirPorApi(request, api, ocupado, fecha, ID_ENCARGADO);
    const { panel } = await abrirFormulario(page);
    await completar(panel, { camion: libre, fecha, vendedor: OPCION_ENCARGADO });
    await panel.getByRole("button", { name: "Abrir jornada" }).click();
    await expect(panel.getByRole("alert")).toContainText("El vendedor ya tiene una jornada en esa fecha.");
    expect(await jornadasDelCamion(request, api, libre.id)).toEqual([]);
  });

  test("respuesta perdida: una lectura coincidente NO declara éxito; sólo el replay con la misma clave confirma", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "perdida");
    const fecha = fechaFutura();
    const red = registrarSolicitudes(page, api);
    let perder = true;
    // La solicitud REAL llega a PostgreSQL; sólo se descarta su respuesta.
    await page.route("**/rest/v1/rpc/abrir_jornada", async (route) => {
      if (!perder) return route.continue();
      await route.fetch();
      await route.abort("failed");
    });

    const { panel } = await abrirFormulario(page);
    await completar(panel, { camion, fecha, vendedor: OPCION_VENDEDOR });
    await panel.getByRole("button", { name: "Abrir jornada" }).click();

    const alerta = panel.getByRole("alert");
    await expect(alerta).toContainText(MENSAJE_DESCONOCIDO);
    await expect(alerta).toContainText("Información (no confirma el resultado):");
    // La lectura informativa encontró la jornada creada por esta misma solicitud...
    await expect(alerta).toContainText("hay una jornada abierta de ese camión en esa fecha con el vendedor elegido");
    // ...y aun así no se declara éxito.
    await expect(exito(page)).toHaveCount(0);
    await expect(panel.getByRole("button", { name: "Reintentar apertura" })).toBeEnabled();

    const enBase = await jornadasDelCamion(request, api, camion.id);
    expect(enBase).toHaveLength(1);
    // Los intentos automáticos de la capa de datos repiten exactamente el mismo cuerpo.
    const cuerposPerdidos = red.de("/rest/v1/rpc/abrir_jornada").map((r) => r.postData());
    expect(cuerposPerdidos.length).toBeGreaterThanOrEqual(1);
    expect(new Set(cuerposPerdidos).size).toBe(1);

    // Replay con la MISMA clave y el MISMO payload: el servidor devuelve la jornada original.
    perder = false;
    const respuestaReplay = page.waitForResponse((r) => r.url().includes("/rest/v1/rpc/abrir_jornada"));
    await panel.getByRole("button", { name: "Reintentar apertura" }).click();
    const replay = await respuestaReplay;
    expect(replay.status()).toBe(200);
    expect(await replay.json()).toBe(enBase[0].id);
    await expect(exito(page)).toBeVisible();

    const cuerpos = red.de("/rest/v1/rpc/abrir_jornada").map((r) => r.postData());
    expect(cuerpos.length).toBe(cuerposPerdidos.length + 1);
    expect(new Set(cuerpos).size).toBe(1);
    const clave = (JSON.parse(cuerpos[0]!) as Record<string, string>).p_idempotency_key;
    expect(await operacionesDeClave(request, api, clave)).toHaveLength(1);
    expect(await jornadasDelCamion(request, api, camion.id)).toHaveLength(1);
  });

  test("replay HTTP: misma clave y payload → mismo id; misma clave con otro payload → conflicto", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "replay");
    const fecha = fechaFutura();
    const datos = { p_idempotency_key: randomUUID(), p_camion_id: camion.id, p_fecha: fecha, p_vendedor_id: ID_VENDEDOR };
    const r1 = await rpc(request, api, api.tokenDueno, "abrir_jornada", datos);
    const r2 = await rpc(request, api, api.tokenDueno, "abrir_jornada", datos);
    expect(r1.status()).toBe(200);
    expect(r2.status()).toBe(200);
    expect(await r2.json()).toBe(await r1.json());
    const r3 = await rpc(request, api, api.tokenDueno, "abrir_jornada", { ...datos, p_vendedor_id: ID_ENCARGADO });
    expect(r3.status()).toBe(409);
    expect(((await r3.json()) as { message: string }).message).toBe("jornada_conflicto_idempotencia");
    expect(await jornadasDelCamion(request, api, camion.id)).toHaveLength(1);
  });

  test("vendedor/piloto: sin panel de apertura y la base le rechaza la lista y la apertura", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "vend");
    const vend = await entrarComo(browser, baseURL, CUENTAS.vendedor);
    const red = registrarSolicitudes(vend.page, api);
    await vend.page.goto("/jornadas");
    await expect(vend.page.getByRole("heading", { name: "Mi jornada" })).toBeVisible();
    await expect(vend.page.getByRole("button", { name: "Nueva jornada" })).toHaveCount(0);
    await expect(panelApertura(vend.page)).toHaveCount(0);
    expect(red.de("/rest/v1/rpc/listar_vendedores_jornada")).toHaveLength(0);
    await vend.contexto.close();

    const token = await tokenDe(request, api, CUENTAS.vendedor);
    const lista = await rpc(request, api, token, "listar_vendedores_jornada", {});
    expect(lista.status()).toBe(403);
    expect(((await lista.json()) as { message: string }).message).toBe("jornada_no_autorizado");
    const abrir = await rpc(request, api, token, "abrir_jornada", {
      p_idempotency_key: randomUUID(), p_camion_id: camion.id, p_fecha: fechaFutura(), p_vendedor_id: ID_VENDEDOR,
    });
    expect(abrir.status()).toBe(403);
    expect(await jornadasDelCamion(request, api, camion.id)).toEqual([]);
  });

  test("perfil inactivo: acceso bloqueado y la base le rechaza la lista", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const contexto = await browser.newContext({ baseURL, storageState: { cookies: [], origins: [] } });
    const p = await contexto.newPage();
    await p.goto("/login");
    await p.getByLabel("Usuario").fill(CUENTAS.inactivo);
    await p.getByLabel("Contraseña").fill(PASSWORD_PRUEBA);
    await p.getByRole("button", { name: "Ingresar al sistema" }).click();
    await expect(p.getByRole("heading", { name: "Acceso bloqueado" })).toBeVisible();
    await p.goto("/jornadas");
    await expect(p.getByRole("heading", { name: "Acceso bloqueado" })).toBeVisible();
    await expect(panelApertura(p)).toHaveCount(0);
    await contexto.close();

    const token = await tokenDe(request, api, CUENTAS.inactivo);
    const lista = await rpc(request, api, token, "listar_vendedores_jornada", {});
    expect(lista.status()).toBe(403);
    expect(((await lista.json()) as { message: string }).message).toBe("jornada_no_autorizado");
  });

  test("aislamiento: la otra empresa sólo ve su perfil y sus camiones, y no puede asignar un vendedor ajeno", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const camionPropio = await crearCamion(request, api, "empresa-a");
    const tokenOtra = await tokenDe(request, api, CUENTAS.otraEmpresa);
    const camionOtra = await crearCamion(request, api, "empresa-b", tokenOtra);

    const lista = await request.post(`${api.url}/rest/v1/rpc/listar_vendedores_jornada`, {
      headers: { ...cabeceras(api, tokenOtra), prefer: "count=exact" }, data: {},
    });
    expect(lista.status()).toBe(200);
    expect(lista.headers()["content-range"]).toBe("0-0/1");
    expect(await lista.json()).toEqual([{ usuario_id: ID_OTRA_EMPRESA, nombre: "Dueño de otra empresa", rol: "dueno" }]);

    const ajeno = await rpc(request, api, tokenOtra, "abrir_jornada", {
      p_idempotency_key: randomUUID(), p_camion_id: camionOtra.id, p_fecha: fechaFutura(), p_vendedor_id: ID_VENDEDOR,
    });
    expect(ajeno.status()).toBe(404);
    expect(((await ajeno.json()) as { message: string }).message).toBe("jornada_vendedor_no_encontrado");

    const otra = await entrarComo(browser, baseURL, CUENTAS.otraEmpresa);
    const { panel } = await abrirFormulario(otra.page);
    expect(await textosOpciones(panel.getByLabel("Vendedor", { exact: true }))).toEqual([
      "Elegí un vendedor", "Dueño de otra empresa — Dueño",
    ]);
    const camiones = await textosOpciones(panel.getByLabel("Camión", { exact: true }));
    expect(camiones).toContain(camionOtra.etiqueta);
    expect(camiones).not.toContain(camionPropio.etiqueta);
    await otra.contexto.close();
  });

  test("Android 412×915: formulario usable, sin scroll horizontal y apertura exitosa", async ({ page, request, browser, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const camion = await crearCamion(request, api, "android");
    const fecha = fechaFutura();
    const movil = await entrarComo(browser, baseURL, CUENTAS.dueno, {
      viewport: { width: 412, height: 915 }, isMobile: true, hasTouch: true,
    });
    const { panel } = await abrirFormulario(movil.page);
    const sinScroll = () =>
      movil.page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth);
    expect(await sinScroll()).toBe(true);
    await completar(panel, { camion, fecha, vendedor: OPCION_VENDEDOR });
    const boton = panel.getByRole("button", { name: "Abrir jornada" });
    const caja = await boton.boundingBox();
    expect(caja && caja.height >= 44 && caja.x >= 0 && caja.x + caja.width <= 412).toBe(true);
    await boton.tap();
    await expect(exito(movil.page)).toBeVisible();
    expect(await sinScroll()).toBe(true);
    expect(await jornadasDelCamion(request, api, camion.id)).toHaveLength(1);
    await movil.contexto.close();
  });

  test("superficie: `privado` no está expuesto y el navegador sólo usa la clave pública del stack local", async ({ page, request, baseURL }) => {
    const api = await dataApiDesdeApp(page);
    const red = registrarSolicitudes(page, api);
    const claves = new Set<string>();
    page.on("request", (r) => {
      if (r.url().startsWith(api.url)) {
        const k = r.headers()["apikey"];
        if (k) claves.add(k);
      }
    });
    await abrirFormulario(page);
    expect(red.de("/rest/v1/rpc/listar_vendedores_jornada")).toHaveLength(1);

    // `privado` no es un esquema de la Data API (PGRST106 → 406).
    for (const perfil of ["privado"]) {
      const lectura = await request.post(`${api.url}/rest/v1/rpc/listar_vendedores_jornada`, {
        headers: { ...cabeceras(api, api.tokenDueno), "content-profile": perfil }, data: {},
      });
      expect(lectura.status()).toBe(406);
      expect(((await lectura.json()) as { code: string }).code).toBe("PGRST106");
      const vista = await request.get(`${api.url}/rest/v1/perfiles_empresa_gestion?select=*`, {
        headers: { ...cabeceras(api, api.tokenDueno), "accept-profile": perfil },
      });
      expect(vista.status()).toBe(406);
    }

    // Una sola clave en el navegador: la publicable del stack local, nunca la secreta.
    const publicable = process.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? "";
    const secreta = process.env.E2E_SUPABASE_SECRET_KEY ?? "";
    expect(publicable.length > 0 && secreta.length > 0).toBe(true);
    expect(claves.size).toBe(1);
    const [usada] = [...claves];
    expect(usada === publicable).toBe(true);
    expect(usada === secreta).toBe(false);
    expect(api.url).toMatch(/^http:\/\/127\.0\.0\.1:\d+$/);

    // El módulo servido al navegador no contiene la clave secreta.
    const modulo = await request.get(`${baseURL}/src/lib/supabase.ts`);
    expect(modulo.status()).toBe(200);
    const fuente = await modulo.text();
    expect(fuente.includes(secreta)).toBe(false);
  });
});
