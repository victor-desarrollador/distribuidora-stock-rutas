// Catálogo de productos en Supabase local (slice productos).
//
// UI: el dueño (sesión del proyecto `setup`) y el encargado crean, editan y
// cambian el estado de productos; la pantalla no muestra ni carga stock.
// HTTP: la Data API sólo escribe por las RPC; el precio con más de 2
// decimales se rechaza sin redondear; los errores sólo traen códigos estables.
//
// Los productos creados quedan en la base local: cada prueba usa un nombre
// único para poder correr en paralelo y repetirse.
import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from "@playwright/test";

import { CUENTAS, PASSWORD_PRUEBA } from "./auth/cuentasPrueba";

// Producto del seed local (supabase/seed.sql).
const ID_YOGUR_SEED = "00000000-0000-4000-8000-0000000000a1";

function nombreUnico(base: string) {
  return `${base} ${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
}

function fila(page: Page, nombre: string) {
  return page.getByRole("row").filter({ hasText: nombre });
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
    r.url().includes("/rest/v1/productos")
  );
  await page.goto("/productos");
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

const altaValida = {
  p_codigo: null,
  p_nombre: "HTTP",
  p_categoria: "lacteos",
  p_forma_venta: "unidad",
  p_precio: 10,
  p_stock_minimo: 0,
};

test.describe("UI del catálogo (dueño)", () => {
  test("lista el catálogo de la base sin stock ni stock inicial", async ({
    page,
  }) => {
    await page.goto("/productos");

    await expect(fila(page, "Jamón cocido")).toContainText("FIA-001");
    await expect(fila(page, "Jamón cocido")).toContainText("Activo");
    await expect(fila(page, "Salame milán")).toContainText("Inactivo");
    await expect(page.getByRole("columnheader", { name: "Stock", exact: true }))
      .toHaveCount(0);

    await page.getByRole("button", { name: "Nuevo producto" }).click();
    await expect(page.getByText("Stock inicial")).toHaveCount(0);
  });

  test("crea, edita, da de baja y reactiva un producto", async ({ page }) => {
    const nombre = nombreUnico("Leche UI");
    await page.goto("/productos");

    await page.getByRole("button", { name: "Nuevo producto" }).click();
    await page.getByLabel("Nombre del producto").fill(nombre);
    await page.getByLabel("Precio de venta ($)").fill("1600.50");
    await page.getByLabel("Stock mínimo (unidades)").fill("12");
    await page.getByRole("button", { name: "Guardar producto" }).click();

    await expect(page.getByText("Producto agregado correctamente.")).toBeVisible();
    await expect(fila(page, nombre)).toContainText("12 un.");

    // La base es la autoridad: el producto sigue ahí después de recargar.
    await page.reload();
    await expect(fila(page, nombre)).toContainText("Activo");

    await page.getByRole("button", { name: `Editar ${nombre}` }).click();
    await expect(page.getByRole("combobox", { name: /^Categoría/ })).toBeDisabled();
    await page.getByLabel("Precio de venta ($)").fill("1700");
    await page.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(page.getByText("Producto actualizado correctamente.")).toBeVisible();
    await expect(fila(page, nombre)).toContainText("1.700");

    await page.getByRole("button", { name: `Dar de baja ${nombre}` }).click();
    await expect(fila(page, nombre)).toContainText("Inactivo");

    await page.getByRole("button", { name: `Reactivar ${nombre}` }).click();
    await expect(fila(page, nombre)).toContainText("Activo");
  });

  test("un fiambre guarda el precio de pieza y muestra la media derivada", async ({
    page,
  }) => {
    const nombre = nombreUnico("Mortadela UI");
    await page.goto("/productos");

    await page.getByRole("button", { name: "Nuevo producto" }).click();
    await page.getByLabel("Nombre del producto").fill(nombre);
    await page.getByRole("combobox", { name: /^Categoría/ }).selectOption("Fiambres");
    await page.getByLabel("Precio de pieza completa ($)").fill("21");
    await expect(page.getByLabel("Precio de media pieza (derivado, $)"))
      .toHaveValue("11");
    await page.getByLabel("Stock mínimo (en medias piezas)").fill("9");
    await page.getByRole("button", { name: "Guardar producto" }).click();

    await expect(fila(page, nombre)).toContainText("4 piezas y media");
    await expect(fila(page, nombre)).toContainText("media");
  });

  test("un precio con 3 decimales no se envía a la base", async ({
    page,
  }) => {
    const llamadasRpc: string[] = [];
    page.on("request", (r) => {
      if (r.url().includes("/rest/v1/rpc/")) llamadasRpc.push(r.url());
    });
    const nombre = nombreUnico("Precio inválido UI");
    await page.goto("/productos");

    await page.getByRole("button", { name: "Nuevo producto" }).click();
    await page.getByLabel("Nombre del producto").fill(nombre);
    await page.getByLabel("Precio de venta ($)").fill("20.999");
    await page.getByLabel("Stock mínimo (unidades)").fill("0");
    await page.getByRole("button", { name: "Guardar producto" }).click();

    // El navegador rechaza el valor (step 0.01) y el formulario no se envía.
    const precio = page.getByLabel("Precio de venta ($)");
    expect(
      await precio.evaluate((el) => (el as HTMLInputElement).validity.stepMismatch)
    ).toBe(true);
    await expect(page.getByText("Producto agregado correctamente.")).toHaveCount(0);
    expect(llamadasRpc).toEqual([]);
    await expect(fila(page, nombre)).toHaveCount(0);
  });

  test("un código repetido muestra el mensaje de la base, sin detalle SQL", async ({
    page,
  }) => {
    await page.goto("/productos");

    await page.getByRole("button", { name: "Nuevo producto" }).click();
    await page.getByLabel("Código (opcional)").fill("LAC-001");
    await page.getByLabel("Nombre del producto").fill(nombreUnico("Duplicado UI"));
    await page.getByLabel("Precio de venta ($)").fill("10");
    await page.getByLabel("Stock mínimo (unidades)").fill("0");
    await page.getByRole("button", { name: "Guardar producto" }).click();

    const alerta = page.getByRole("alert");
    await expect(alerta).toHaveText("Ya existe otro producto con ese código.");
    await expect(alerta).not.toContainText("productos_codigo_unico");
  });
});

test.describe("Convivencia temporal con el catálogo demo (DE-12)", () => {
  // Jornadas y Movimientos siguen con los productos de prueba del navegador:
  // el aviso evita creer que un cambio en /productos los afecta.
  for (const ruta of ["/jornadas", "/movimientos"]) {
    test(`${ruta} avisa que usa el catálogo de demostración`, async ({
      page,
    }) => {
      await page.goto(ruta);

      await expect(
        page.getByRole("note").filter({ hasText: "Catálogo de demostración" })
      ).toContainText("no el catálogo real de la sección Productos");
    });
  }
});

test.describe("UI del catálogo (encargado)", () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test("el encargado crea un producto", async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel("Usuario").fill(CUENTAS.encargado);
    await page.getByLabel("Contraseña").fill(PASSWORD_PRUEBA);
    await page.getByRole("button", { name: "Ingresar al sistema" }).click();
    await expect(page.getByText("Encargado de prueba")).toBeVisible();

    const nombre = nombreUnico("Yogur encargado");
    await page.goto("/productos");
    await page.getByRole("button", { name: "Nuevo producto" }).click();
    await page.getByLabel("Nombre del producto").fill(nombre);
    await page.getByLabel("Precio de venta ($)").fill("990");
    await page.getByLabel("Stock mínimo (unidades)").fill("1");
    await page.getByRole("button", { name: "Guardar producto" }).click();

    await expect(fila(page, nombre)).toContainText("Activo");
  });
});

test.describe("Data API: escritura sólo por RPC", () => {
  test("20.999 se rechaza en la base con un código estable y sin detalle", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);

    for (const precio of [20.999, "20.999"]) {
      const r = await request.post(`${api.url}/rest/v1/rpc/crear_producto`, {
        headers: encabezados(api, api.tokenDueno),
        data: { ...altaValida, p_nombre: nombreUnico("HTTP"), p_precio: precio },
      });

      expect(r.status()).toBe(400);
      expect(await r.json()).toEqual({
        code: "PT400",
        message: "producto_precio_invalido",
        details: null,
        hint: null,
      });
    }
  });

  test("el dueño crea por RPC con precio exacto y empresa derivada", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);
    const nombre = nombreUnico("HTTP exacto");

    const alta = await request.post(`${api.url}/rest/v1/rpc/crear_producto`, {
      headers: encabezados(api, api.tokenDueno),
      data: { ...altaValida, p_nombre: nombre, p_precio: 20.99 },
    });
    expect(alta.status()).toBe(200);
    const id = (await alta.json()) as string;

    const lectura = await request.get(
      `${api.url}/rest/v1/productos?id=eq.${id}&select=precio,nombre`,
      { headers: encabezados(api, api.tokenDueno) }
    );
    expect(await lectura.json()).toEqual([{ precio: 20.99, nombre }]);
  });

  test("INSERT, UPDATE y DELETE directos sobre productos se rechazan", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);
    const h = encabezados(api, api.tokenDueno);

    const insert = await request.post(`${api.url}/rest/v1/productos`, {
      headers: h,
      data: {
        empresa_id: "00000000-0000-4000-8000-0000000000e1",
        nombre: "Directo",
        categoria: "lacteos",
        forma_venta: "unidad",
        precio: 20.999,
        creado_por: "00000000-0000-4000-8000-000000000001",
      },
    });
    const update = await request.patch(
      `${api.url}/rest/v1/productos?id=eq.${ID_YOGUR_SEED}`,
      { headers: h, data: { precio: 20.999 } }
    );
    const borrado = await request.delete(
      `${api.url}/rest/v1/productos?id=eq.${ID_YOGUR_SEED}`,
      { headers: h }
    );

    for (const r of [insert, update, borrado]) {
      expect(r.status()).toBe(403);
      expect(((await r.json()) as { code: string }).code).toBe("42501");
    }

    const lectura = await request.get(
      `${api.url}/rest/v1/productos?id=eq.${ID_YOGUR_SEED}&select=precio`,
      { headers: h }
    );
    expect(await lectura.json()).toEqual([{ precio: 2300 }]);
  });

  test("GET sobre una RPC de escritura responde 405", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);

    const r = await request.get(
      `${api.url}/rest/v1/rpc/cambiar_estado_producto?p_producto_id=${ID_YOGUR_SEED}&p_activo=false`,
      { headers: encabezados(api, api.tokenDueno) }
    );

    expect(r.status()).toBe(405);
  });

  test("el esquema privado no está expuesto", async ({ page, request }) => {
    const api = await dataApiDesdeApp(page);

    const r = await request.post(`${api.url}/rest/v1/rpc/crear_producto`, {
      headers: {
        ...encabezados(api, api.tokenDueno),
        "content-profile": "privado",
      },
      data: { ...altaValida, p_nombre: nombreUnico("HTTP privado") },
    });

    expect(r.status()).toBe(406);
    expect(((await r.json()) as { code: string }).code).toBe("PGRST106");
  });

  test("el vendedor no puede crear ni editar; sin sesión no se ejecuta", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);
    const tokenVendedor = await tokenDe(request, api, CUENTAS.vendedor);

    const alta = await request.post(`${api.url}/rest/v1/rpc/crear_producto`, {
      headers: encabezados(api, tokenVendedor),
      data: { ...altaValida, p_nombre: nombreUnico("HTTP vendedor") },
    });
    expect(alta.status()).toBe(403);
    expect(await alta.json()).toMatchObject({
      code: "PT403",
      message: "producto_no_autorizado",
    });

    const edicion = await request.post(
      `${api.url}/rest/v1/rpc/actualizar_producto`,
      {
        headers: encabezados(api, tokenVendedor),
        data: {
          p_producto_id: ID_YOGUR_SEED,
          p_codigo: "LAC-001",
          p_nombre: "Yogur bebible 1 L",
          p_precio: 1,
          p_stock_minimo: 20,
        },
      }
    );
    expect(edicion.status()).toBe(403);

    // El vendedor sí lee el catálogo de su empresa.
    const lectura = await request.get(
      `${api.url}/rest/v1/productos?id=eq.${ID_YOGUR_SEED}&select=precio`,
      { headers: encabezados(api, tokenVendedor) }
    );
    expect(await lectura.json()).toEqual([{ precio: 2300 }]);

    const anonimo = await request.post(`${api.url}/rest/v1/rpc/crear_producto`, {
      headers: encabezados(api),
      data: { ...altaValida, p_nombre: nombreUnico("HTTP anon") },
    });
    expect(anonimo.status()).toBe(401);
    expect(((await anonimo.json()) as { code: string }).code).toBe("42501");
  });
});
