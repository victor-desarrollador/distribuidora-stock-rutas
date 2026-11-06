// Stock real (B-01) contra un Supabase LOCAL aislado.
//
// Requiere VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY del stack local
// (las mismas variables con las que arranca la app; este spec también las usa
// para leer la base). Cada prueba crea su propio producto por la RPC
// `crear_producto`, así los saldos se comparan por diferencia y las pruebas
// pueden repetirse. Los resultados se comprueban con lecturas reales a la Data
// API (`stock_actual`, `movimientos_stock`), no con mocks.
import {
  expect,
  test,
  type APIRequestContext,
  type Browser,
  type Page,
} from "@playwright/test";

import { CUENTAS, PASSWORD_PRUEBA } from "./auth/cuentasPrueba";

const URL_API = process.env.VITE_SUPABASE_URL ?? "";
const CLAVE = process.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? "";

function sufijo() {
  return `${Date.now().toString(36)}${Math.floor(Math.random() * 1e6).toString(36)}`;
}

async function token(request: APIRequestContext, usuario: string) {
  const r = await request.post(`${URL_API}/auth/v1/token?grant_type=password`, {
    headers: { apikey: CLAVE },
    data: {
      email: `${usuario}@usuarios.distribuidora.invalid`,
      password: PASSWORD_PRUEBA,
    },
  });
  expect(r.ok()).toBe(true);
  return ((await r.json()) as { access_token: string }).access_token;
}

const cab = (t: string) => ({
  apikey: CLAVE,
  authorization: `Bearer ${t}`,
  "content-type": "application/json",
});

async function crearProducto(
  request: APIRequestContext,
  forma: "unidad" | "peso"
) {
  const t = await token(request, CUENTAS.dueno);
  const nombre = `B01 ${forma} ${sufijo()}`;
  const r = await request.post(`${URL_API}/rest/v1/rpc/crear_producto`, {
    headers: cab(t),
    data: {
      p_codigo: null,
      p_nombre: nombre,
      p_categoria: forma === "unidad" ? "lacteos" : "fiambres",
      p_forma_venta: forma,
      p_precio: 100,
      p_stock_minimo: 0,
    },
  });
  expect(r.ok(), await r.text()).toBe(true);
  return { id: (await r.json()) as string, nombre };
}

async function ubicaciones(request: APIRequestContext, t: string) {
  const r = await request.get(
    `${URL_API}/rest/v1/ubicaciones?select=id,tipo&camion_id=is.null`,
    { headers: cab(t) }
  );
  const filas = (await r.json()) as { id: string; tipo: string }[];
  return {
    deposito: filas.find((f) => f.tipo === "deposito")!.id,
    cuarentena: filas.find((f) => f.tipo === "cuarentena")!.id,
  };
}

// Saldos reales del producto por tipo de ubicación (en unidad mínima).
async function saldos(request: APIRequestContext, productoId: string) {
  const t = await token(request, CUENTAS.dueno);
  const u = await ubicaciones(request, t);
  const r = await request.get(
    `${URL_API}/rest/v1/stock_actual?select=ubicacion_id,cantidad&producto_id=eq.${productoId}`,
    { headers: cab(t) }
  );
  const filas = (await r.json()) as { ubicacion_id: string; cantidad: number }[];
  const de = (id: string) =>
    filas.find((f) => f.ubicacion_id === id)?.cantidad ?? 0;
  return { deposito: de(u.deposito), cuarentena: de(u.cuarentena) };
}

async function movimientos(request: APIRequestContext, productoId: string) {
  const t = await token(request, CUENTAS.dueno);
  const r = await request.get(
    `${URL_API}/rest/v1/movimientos_stock?select=tipo_movimiento,cantidad,motivo_codigo&producto_id=eq.${productoId}&order=creado_en`,
    { headers: cab(t) }
  );
  expect(r.ok(), await r.text()).toBe(true);
  return (await r.json()) as {
    tipo_movimiento: string;
    cantidad: number;
    motivo_codigo: string | null;
  }[];
}

async function ingresoApi(
  request: APIRequestContext,
  productoId: string,
  cantidad: number
) {
  const t = await token(request, CUENTAS.dueno);
  const r = await request.post(`${URL_API}/rest/v1/rpc/registrar_ingreso`, {
    headers: cab(t),
    data: {
      p_idempotency_key: crypto.randomUUID(),
      p_producto_id: productoId,
      p_cantidad: cantidad,
      p_motivo: null,
    },
  });
  expect(r.ok(), await r.text()).toBe(true);
}

// Sesión nueva (sin el storageState del dueño) con el usuario indicado.
async function paginaComo(browser: Browser, usuario: string) {
  const contexto = await browser.newContext({
    storageState: { cookies: [], origins: [] },
  });
  const page = await contexto.newPage();
  await page.goto("/login");
  await page.getByLabel("Usuario").fill(usuario);
  await page.getByLabel("Contraseña").fill(PASSWORD_PRUEBA);
  await page.getByRole("button", { name: "Ingresar al sistema" }).click();
  await expect(page.getByRole("button", { name: /salir|cerrar sesión/i }).first()).toBeVisible();
  return { page, contexto };
}

async function operar(
  page: Page,
  o: {
    tipo: "Ingreso" | "A cuarentena" | "Merma";
    producto: string;
    cantidad: string;
    motivo?: string;
    motivoMerma?: string;
  }
) {
  await page.getByRole("button", { name: o.tipo, exact: true }).click();
  await page.getByLabel("Producto").selectOption({ label: o.producto });
  await page.getByLabel(/^Cantidad/).fill(o.cantidad);
  if (o.motivoMerma) {
    await page.getByLabel("Motivo de la merma").selectOption({ label: o.motivoMerma });
  }
  if (o.motivo) await page.getByLabel(/^(Motivo|Detalle)/).last().fill(o.motivo);
}

const enviar = (page: Page) =>
  page.getByRole("button", { name: /^Registrar |^Registrando/ });

function fila(page: Page, nombre: string) {
  return page.getByRole("row").filter({ hasText: nombre });
}

test.beforeAll(() => {
  if (!URL_API || !CLAVE) {
    throw new Error(
      "Faltan VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY del stack local."
    );
  }
});

test.describe("Dueño", () => {
  test("consulta el stock persistido de la base", async ({ page, request }) => {
    const p = await crearProducto(request, "unidad");
    await ingresoApi(request, p.id, 37);

    await page.goto("/stock");
    await expect(page.getByRole("heading", { name: "Stock" })).toBeVisible();
    await expect(fila(page, p.nombre)).toContainText("37 un.");
  });

  test("ingreso: el saldo cambia en la base y persiste al recargar", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    await page.goto("/stock");
    await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: "12" });
    await enviar(page).click();

    await expect(page.getByText("Ingreso registrado.")).toBeVisible();
    await expect(fila(page, p.nombre)).toContainText("12 un.");
    expect(await saldos(request, p.id)).toEqual({ deposito: 12, cuarentena: 0 });

    await page.reload();
    await expect(fila(page, p.nombre)).toContainText("12 un.");
  });

  test("peso: 1,250 kg se guarda como 1250 gramos enteros", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "peso");
    await page.goto("/stock");
    await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: "1,250" });
    await enviar(page).click();

    await expect(page.getByText("Ingreso registrado.")).toBeVisible();
    await expect(fila(page, p.nombre)).toContainText("1,250 kg");

    const movs = await movimientos(request, p.id);
    expect(movs).toHaveLength(1);
    expect(movs[0].cantidad).toBe(1250);
    expect(Number.isInteger(movs[0].cantidad)).toBe(true);
    expect((await saldos(request, p.id)).deposito).toBe(1250);

    await page.reload();
    await expect(fila(page, p.nombre)).toContainText("1,250 kg");
  });

  test("cuarentena y merma salen del depósito y descuentan lo esperado", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    await ingresoApi(request, p.id, 20);
    await page.goto("/stock");

    await operar(page, {
      tipo: "A cuarentena",
      producto: p.nombre,
      cantidad: "5",
      motivo: "revisión de calidad",
    });
    await enviar(page).click();
    await expect(page.getByText("A cuarentena registrado.")).toBeVisible();
    expect(await saldos(request, p.id)).toEqual({ deposito: 15, cuarentena: 5 });

    await operar(page, {
      tipo: "Merma",
      producto: p.nombre,
      cantidad: "3",
      motivoMerma: "Vencido",
    });
    await enviar(page).click();
    await expect(page.getByText("Merma registrado.")).toBeVisible();
    expect(await saldos(request, p.id)).toEqual({ deposito: 12, cuarentena: 5 });

    const movs = await movimientos(request, p.id);
    expect(movs.map((m) => [m.tipo_movimiento, m.cantidad])).toHaveLength(3);
    expect(movs.some((m) => m.motivo_codigo === "vencido" && m.cantidad === 3)).toBe(true);

    await page.reload();
    await expect(fila(page, p.nombre)).toContainText("12 un.");
  });

  test("cuarentena por más del depósito: error de negocio y sin efectos", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    await ingresoApi(request, p.id, 4);
    await page.goto("/stock");
    await operar(page, {
      tipo: "A cuarentena",
      producto: p.nombre,
      cantidad: "9",
      motivo: "x",
    });
    await enviar(page).click();

    await expect(page.getByRole("alert")).toContainText(
      "No hay stock suficiente en el depósito."
    );
    expect(await saldos(request, p.id)).toEqual({ deposito: 4, cuarentena: 0 });
    expect(await movimientos(request, p.id)).toHaveLength(1);
  });
});

test.describe("Validaciones y envío", () => {
  test("unidad: rechaza fraccionarias, cero y negativas sin llamar a la RPC", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    let llamadas = 0;
    await page.route("**/rest/v1/rpc/registrar_ingreso", (r) => {
      llamadas++;
      return r.continue();
    });
    await page.goto("/stock");

    for (const valor of ["1,5", "1.5", "0", "-3", ""]) {
      await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: valor });
      await enviar(page).click();
      await expect(page.getByRole("alert")).toContainText(
        "cantidad entera de unidades mayor que cero"
      );
    }
    expect(llamadas).toBe(0);
    expect(await movimientos(request, p.id)).toHaveLength(0);
  });

  test("peso: rechaza más de 3 decimales y punto decimal", async ({ page, request }) => {
    const p = await crearProducto(request, "peso");
    await page.goto("/stock");
    for (const valor of ["1,2345", "1.250", "0,000"]) {
      await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: valor });
      await enviar(page).click();
      await expect(page.getByRole("alert")).toContainText("hasta 3 decimales");
    }
    expect(await movimientos(request, p.id)).toHaveLength(0);
  });

  test("cuarentena sin motivo y merma «Otro» sin detalle se rechazan", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    await ingresoApi(request, p.id, 10);
    await page.goto("/stock");

    await operar(page, { tipo: "A cuarentena", producto: p.nombre, cantidad: "1" });
    await enviar(page).click();
    await expect(page.getByRole("alert")).toContainText("Indicá el motivo");

    await operar(page, { tipo: "Merma", producto: p.nombre, cantidad: "1", motivoMerma: "Otro" });
    await enviar(page).click();
    await expect(page.getByRole("alert")).toContainText("Describí el motivo");
    expect(await saldos(request, p.id)).toEqual({ deposito: 10, cuarentena: 0 });
  });

  test("doble clic con respuesta lenta: una sola operación en la base", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    let llamadas = 0;
    await page.route("**/rest/v1/rpc/registrar_ingreso", async (r) => {
      llamadas++;
      await new Promise((res) => setTimeout(res, 800));
      await r.continue();
    });
    await page.goto("/stock");
    await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: "7" });
    await enviar(page).dblclick();

    await expect(page.getByText("Ingreso registrado.")).toBeVisible();
    expect(llamadas).toBe(1);
    expect(await movimientos(request, p.id)).toHaveLength(1);
    expect((await saldos(request, p.id)).deposito).toBe(7);
  });

  test("reintento tras perder la respuesta no duplica (misma clave)", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    let primera = true;
    await page.route("**/rest/v1/rpc/registrar_ingreso", async (r) => {
      if (primera) {
        primera = false;
        // El servidor ejecuta la operación, pero el cliente no recibe respuesta.
        await r.fetch();
        await r.abort("failed");
        return;
      }
      await r.continue();
    });
    await page.goto("/stock");
    await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: "6" });
    await enviar(page).click();
    await expect(page.getByRole("alert")).toContainText("No se pudo confirmar la operación");

    // Mismos datos: reutiliza la clave, la base devuelve la operación original.
    await enviar(page).click();
    await expect(page.getByText("Ingreso registrado.")).toBeVisible();
    expect(await movimientos(request, p.id)).toHaveLength(1);
    expect((await saldos(request, p.id)).deposito).toBe(6);
  });
});

test.describe("Roles", () => {
  test("encargado consulta y registra ingreso, cuarentena y merma", async ({
    browser,
    request,
  }) => {
    const p = await crearProducto(request, "peso");
    const { page, contexto } = await paginaComo(browser, CUENTAS.encargado);
    try {
      await page.goto("/stock");
      await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: "10" });
      await enviar(page).click();
      await expect(page.getByText("Ingreso registrado.")).toBeVisible();

      await operar(page, { tipo: "A cuarentena", producto: p.nombre, cantidad: "2,500", motivo: "control" });
      await enviar(page).click();
      await expect(page.getByText("A cuarentena registrado.")).toBeVisible();

      await operar(page, { tipo: "Merma", producto: p.nombre, cantidad: "0,250", motivoMerma: "Roto o dañado" });
      await enviar(page).click();
      await expect(page.getByText("Merma registrado.")).toBeVisible();

      expect(await saldos(request, p.id)).toEqual({ deposito: 7250, cuarentena: 2500 });
      await page.reload();
      await expect(fila(page, p.nombre)).toContainText("7,250 kg");
    } finally {
      await contexto.close();
    }
  });

  test("vendedor: sin acceso a la pantalla, sin menú y sin poder usar las RPC", async ({
    browser,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    const { page, contexto } = await paginaComo(browser, CUENTAS.vendedor);
    try {
      await page.goto("/stock");
      await expect(page.getByText("Acceso no permitido")).toBeVisible();
      await expect(page.getByRole("heading", { name: "Stock" })).toHaveCount(0);
      await expect(page.getByRole("link", { name: "Stock" })).toHaveCount(0);
    } finally {
      await contexto.close();
    }

    // La UI no es la frontera: la RPC también rechaza al vendedor.
    const t = await token(request, CUENTAS.vendedor);
    const r = await request.post(`${URL_API}/rest/v1/rpc/registrar_ingreso`, {
      headers: cab(t),
      data: { p_idempotency_key: crypto.randomUUID(), p_producto_id: p.id, p_cantidad: 5, p_motivo: null },
    });
    expect(r.ok()).toBe(false);
    expect(await movimientos(request, p.id)).toHaveLength(0);
  });

  test("aislamiento: el dueño de otra empresa no ve ni mueve este stock", async ({
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    await ingresoApi(request, p.id, 9);
    const t = await token(request, CUENTAS.otraEmpresa);

    const lectura = await request.get(
      `${URL_API}/rest/v1/stock_actual?select=cantidad&producto_id=eq.${p.id}`,
      { headers: cab(t) }
    );
    expect(await lectura.json()).toEqual([]);

    const escritura = await request.post(`${URL_API}/rest/v1/rpc/registrar_ingreso`, {
      headers: cab(t),
      data: { p_idempotency_key: crypto.randomUUID(), p_producto_id: p.id, p_cantidad: 1, p_motivo: null },
    });
    expect(escritura.ok()).toBe(false);
    expect((await saldos(request, p.id)).deposito).toBe(9);
  });
});

test.describe("Viewports", () => {
  test("PC: tabla visible, tarjetas ocultas, sin scroll horizontal", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    await ingresoApi(request, p.id, 3);
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("/stock");
    await expect(page.getByRole("table")).toBeVisible();
    await expect(fila(page, p.nombre)).toBeVisible();
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)
    ).toBe(true);
  });

  test("Android (412×915): tarjetas, sin scroll horizontal y operación completa", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "peso");
    await page.setViewportSize({ width: 412, height: 915 });
    await page.goto("/stock");

    await expect(page.getByRole("table")).toBeHidden();
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)
    ).toBe(true);

    await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: "2,125" });
    const boton = enviar(page);
    expect((await boton.boundingBox())!.height).toBeGreaterThanOrEqual(44);
    await boton.click();
    await expect(page.getByText("Ingreso registrado.")).toBeVisible();
    await expect(page.getByRole("listitem").filter({ hasText: p.nombre })).toContainText("2,125 kg");
    expect((await saldos(request, p.id)).deposito).toBe(2125);
  });
});
