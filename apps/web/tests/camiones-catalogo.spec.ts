// Catálogo de camiones en Supabase local (slice camiones).
//
// UI: el dueño (sesión del proyecto `setup`) crea, edita y activa/desactiva
// camiones; el encargado sólo ve el catálogo, sin acciones de escritura.
// HTTP: la Data API sólo escribe por las RPC y sólo el dueño las ejecuta; los
// errores sólo traen códigos estables. La UI no es la frontera de seguridad.
//
// Los camiones creados quedan en la base local: cada prueba usa nombre y
// patente únicos para poder correr en paralelo y repetirse.
import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from "@playwright/test";

import { CUENTAS, PASSWORD_PRUEBA } from "./auth/cuentasPrueba";

function sufijoUnico() {
  return `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
}

function fila(page: Page, texto: string) {
  return page.getByRole("row").filter({ hasText: texto });
}

interface DataApi {
  url: string;
  apikey: string;
  tokenDueno: string;
}

// Toma la URL y la clave pública de la solicitud que hace la app al leer el
// catálogo (no se leen archivos .env).
async function dataApiDesdeApp(page: Page): Promise<DataApi> {
  const solicitud = page.waitForRequest((r) =>
    r.url().includes("/rest/v1/camiones")
  );
  await page.goto("/camiones");
  const r = await solicitud;
  const encabezados = await r.allHeaders();

  return {
    url: new URL(r.url()).origin,
    apikey: encabezados["apikey"],
    tokenDueno: encabezados["authorization"].replace(/^Bearer /, ""),
  };
}

async function tokenDe(
  request: APIRequestContext,
  api: DataApi,
  usuario: string
) {
  const respuesta = await request.post(
    `${api.url}/auth/v1/token?grant_type=password`,
    {
      headers: { apikey: api.apikey },
      data: {
        email: `${usuario}@usuarios.distribuidora.invalid`,
        password: PASSWORD_PRUEBA,
      },
    }
  );
  expect(respuesta.ok()).toBe(true);
  return ((await respuesta.json()) as { access_token: string }).access_token;
}

function encabezados(api: DataApi, token?: string) {
  return {
    apikey: api.apikey,
    "content-type": "application/json",
    ...(token ? { authorization: `Bearer ${token}` } : {}),
  };
}

test.describe("UI del catálogo (dueño)", () => {
  test("crea, edita, desactiva y reactiva un camión", async ({ page }) => {
    const sufijo = sufijoUnico();
    const nombre = `Camión UI ${sufijo}`;
    const patente = `UI ${sufijo}`;
    await page.goto("/camiones");

    await page.getByRole("button", { name: "Nuevo camión" }).click();
    await page.getByLabel("Nombre del camión").fill(nombre);
    await page.getByLabel("Patente").fill(patente);
    await page.getByRole("button", { name: "Guardar camión" }).click();

    await expect(page.getByText("Camión agregado correctamente.")).toBeVisible();
    await expect(fila(page, nombre)).toContainText(patente);
    await expect(fila(page, nombre)).toContainText("Activo");

    // La base es la autoridad: el camión sigue ahí después de recargar.
    await page.reload();
    await expect(fila(page, nombre)).toContainText("Activo");

    await page.getByRole("button", { name: `Editar ${nombre}` }).click();
    await page.getByLabel("Nombre del camión").fill(`${nombre} bis`);
    await page.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(page.getByText("Camión actualizado correctamente.")).toBeVisible();
    await expect(fila(page, `${nombre} bis`)).toBeVisible();

    await page.getByRole("button", { name: `Desactivar ${nombre} bis` }).click();
    await expect(fila(page, `${nombre} bis`)).toContainText("Inactivo");

    await page.getByRole("button", { name: `Activar ${nombre} bis` }).click();
    await expect(fila(page, `${nombre} bis`)).toContainText("Activo");
  });

  test("no ofrece marca, modelo, estado operativo ni observaciones", async ({
    page,
  }) => {
    await page.goto("/camiones");
    await page.getByRole("button", { name: "Nuevo camión" }).click();

    await expect(page.getByLabel("Marca")).toHaveCount(0);
    await expect(page.getByLabel("Modelo")).toHaveCount(0);
    await expect(page.getByLabel("Observaciones")).toHaveCount(0);
    await expect(page.getByText("En reparto")).toHaveCount(0);
    await expect(page.getByText("Mantenimiento")).toHaveCount(0);
  });

  test("una patente repetida muestra el mensaje de la base, sin detalle SQL", async ({
    page,
  }) => {
    const sufijo = sufijoUnico();
    const patente = `DUP ${sufijo}`;
    await page.goto("/camiones");

    for (const nombre of [`Original ${sufijo}`, `Repetido ${sufijo}`]) {
      await page.getByRole("button", { name: "Nuevo camión" }).click();
      await page.getByLabel("Nombre del camión").fill(nombre);
      await page.getByLabel("Patente").fill(patente);
      await page.getByRole("button", { name: "Guardar camión" }).click();
    }

    const alerta = page.getByRole("alert");
    await expect(alerta).toHaveText("Ya existe otro camión con esa patente.");
    await expect(alerta).not.toContainText("camiones_patente_unica");
  });
});

test.describe("UI del catálogo (encargado: sólo lectura)", () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test("el encargado ve el catálogo sin acciones de escritura", async ({
    page,
  }) => {
    await page.goto("/login");
    await page.getByLabel("Usuario").fill(CUENTAS.encargado);
    await page.getByLabel("Contraseña").fill(PASSWORD_PRUEBA);
    await page.getByRole("button", { name: "Ingresar al sistema" }).click();
    await expect(page.getByText("Encargado de prueba")).toBeVisible();

    await page.goto("/camiones");
    await expect(page.getByRole("heading", { name: "Camiones" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Nuevo camión" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: /^Editar/ })).toHaveCount(0);
    await expect(
      page.getByRole("button", { name: /^(Desactivar|Activar)/ })
    ).toHaveCount(0);
    await expect(page.getByRole("columnheader", { name: "Acciones" })).toHaveCount(0);
  });
});

test.describe("Data API: escritura sólo por RPC y sólo el dueño", () => {
  test("el encargado, el vendedor y anon no escriben; el dueño no escribe directo", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);
    const sufijo = sufijoUnico();
    const alta = { p_patente: `HTTP ${sufijo}`, p_nombre: `HTTP ${sufijo}` };

    for (const usuario of [CUENTAS.encargado, CUENTAS.vendedor]) {
      const token = await tokenDe(request, api, usuario);

      // Pueden leer el catálogo de su empresa...
      const lectura = await request.get(
        `${api.url}/rest/v1/camiones?select=id,patente,nombre,activo`,
        { headers: encabezados(api, token) }
      );
      expect(lectura.status()).toBe(200);

      // ...pero no escribir: la RPC responde PT403 con un código estable.
      const rpc = await request.post(`${api.url}/rest/v1/rpc/crear_camion`, {
        headers: encabezados(api, token),
        data: alta,
      });
      expect(rpc.status()).toBe(403);
      expect(await rpc.json()).toMatchObject({
        code: "PT403",
        message: "camion_no_autorizado",
      });
    }

    // anon: sin lectura ni RPC.
    const anonLectura = await request.get(`${api.url}/rest/v1/camiones`, {
      headers: encabezados(api),
    });
    expect(anonLectura.status()).toBe(401);
    const anonRpc = await request.post(`${api.url}/rest/v1/rpc/crear_camion`, {
      headers: encabezados(api),
      data: alta,
    });
    expect(anonRpc.status()).toBe(401);

    // El dueño tampoco escribe directo sobre la tabla.
    const directo = await request.post(`${api.url}/rest/v1/camiones`, {
      headers: encabezados(api, api.tokenDueno),
      data: { patente: `DIR ${sufijo}`, nombre: `DIR ${sufijo}` },
    });
    expect(directo.status()).toBe(403);
    expect(await directo.json()).toMatchObject({ code: "42501" });

    // Nada de lo anterior creó camiones.
    const busqueda = await request.get(
      `${api.url}/rest/v1/camiones?select=id&patente=like.*${sufijo}*`,
      { headers: encabezados(api, api.tokenDueno) }
    );
    expect(await busqueda.json()).toEqual([]);
  });

  test("el esquema privado y los parámetros extra no existen para la Data API", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);

    const privado = await request.post(`${api.url}/rest/v1/rpc/crear_camion`, {
      headers: {
        ...encabezados(api, api.tokenDueno),
        "content-profile": "privado",
      },
      data: { p_patente: "PRIV", p_nombre: "PRIV" },
    });
    expect(privado.status()).toBe(406);

    // empresa_id no es parámetro de la RPC.
    const conEmpresa = await request.post(`${api.url}/rest/v1/rpc/crear_camion`, {
      headers: encabezados(api, api.tokenDueno),
      data: {
        p_patente: `EMP ${sufijoUnico()}`,
        p_nombre: "EMP",
        p_empresa_id: "00000000-0000-4000-8000-0000000000b0",
      },
    });
    expect(conEmpresa.status()).toBe(404);
  });
});
