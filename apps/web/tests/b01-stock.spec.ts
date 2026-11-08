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

interface Movimiento {
  tipo_movimiento: string;
  cantidad: number;
  motivo_codigo: string | null;
  motivo: string | null;
  ubicacion_origen_id: string | null;
  ubicacion_destino_id: string | null;
}

async function movimientos(request: APIRequestContext, productoId: string) {
  const t = await token(request, CUENTAS.dueno);
  const r = await request.get(
    `${URL_API}/rest/v1/movimientos_stock?select=tipo_movimiento,cantidad,motivo_codigo,motivo,ubicacion_origen_id,ubicacion_destino_id&producto_id=eq.${productoId}&order=creado_en`,
    { headers: cab(t) }
  );
  expect(r.ok(), await r.text()).toBe(true);
  return (await r.json()) as Movimiento[];
}

// Llama a una RPC de stock por la Data API (sin pasar por la interfaz) y
// devuelve estado HTTP y cuerpo. `t = null`: sin sesión (sólo `apikey`).
async function rpc(
  request: APIRequestContext,
  t: string | null,
  nombre: string,
  data: Record<string, unknown>
) {
  const r = await request.post(`${URL_API}/rest/v1/rpc/${nombre}`, {
    headers: t ? cab(t) : { apikey: CLAVE, "content-type": "application/json" },
    data,
  });
  const texto = await r.text();
  let cuerpo: { code?: string; message?: string } | string = texto;
  try {
    cuerpo = JSON.parse(texto);
  } catch {
    /* se deja el texto */
  }
  return { estado: r.status(), cuerpo };
}

const ingresoArgs = (producto: string, cantidad: number, clave = crypto.randomUUID()) => ({
  p_idempotency_key: clave,
  p_producto_id: producto,
  p_cantidad: cantidad,
  p_motivo: null,
});
const cuarentenaArgs = (producto: string, origen: string, cantidad: number, clave = crypto.randomUUID()) => ({
  p_idempotency_key: clave,
  p_producto_id: producto,
  p_ubicacion_origen_id: origen,
  p_cantidad: cantidad,
  p_motivo: "prueba",
});
const mermaArgs = (producto: string, origen: string, cantidad: number, clave = crypto.randomUUID()) => ({
  p_idempotency_key: clave,
  p_producto_id: producto,
  p_ubicacion_origen_id: origen,
  p_cantidad: cantidad,
  p_motivo_codigo: "vencido",
  p_motivo: null,
});

// Respuestas de error con la forma de PostgREST, para simular fallos del servidor.
const errorPostgrest = (code: string, message: string, estado = 500) => ({
  status: estado,
  contentType: "application/json",
  body: JSON.stringify({ code, message, details: null, hint: null }),
});

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

    // Origen y destino reales del ledger.
    const t = await token(request, CUENTAS.dueno);
    const u = await ubicaciones(request, t);
    const movs = await movimientos(request, p.id);
    expect(movs).toHaveLength(3);
    const ing = movs.find((m) => m.tipo_movimiento === "ingreso")!;
    const cua = movs.find((m) => m.tipo_movimiento === "a_cuarentena")!;
    const mer = movs.find((m) => m.tipo_movimiento === "merma")!;
    expect([ing.ubicacion_origen_id, ing.ubicacion_destino_id, ing.cantidad]).toEqual([null, u.deposito, 20]);
    expect([cua.ubicacion_origen_id, cua.ubicacion_destino_id, cua.cantidad, cua.motivo]).toEqual([
      u.deposito, u.cuarentena, 5, "revisión de calidad",
    ]);
    expect([mer.ubicacion_origen_id, mer.ubicacion_destino_id, mer.cantidad, mer.motivo_codigo]).toEqual([
      u.deposito, null, 3, "vencido",
    ]);

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

  test("P13: pérdida de respuesta → reintento automático con la misma clave, un solo efecto", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    const claves: string[] = [];
    let llamadas = 0;
    await page.route("**/rest/v1/rpc/registrar_ingreso", async (r) => {
      llamadas++;
      claves.push(r.request().postDataJSON().p_idempotency_key);
      if (llamadas === 1) {
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

    await expect(page.getByText("Ingreso registrado.")).toBeVisible();
    expect(llamadas).toBe(2);
    expect(new Set(claves).size).toBe(1);
    expect(await movimientos(request, p.id)).toHaveLength(1);
    expect((await saldos(request, p.id)).deposito).toBe(6);
  });

  test("P13: 3 intentos sin respuesta → resultado incierto; reintento manual no duplica", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    const claves: string[] = [];
    let llamadas = 0;
    let cortar = true;
    await page.route("**/rest/v1/rpc/registrar_ingreso", async (r) => {
      if (!cortar) return r.continue();
      llamadas++;
      claves.push(r.request().postDataJSON().p_idempotency_key);
      if (llamadas === 1) await r.fetch(); // sólo el primero llega al servidor
      await r.abort("failed");
    });
    await page.goto("/stock");
    await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: "8" });
    await enviar(page).click();

    await expect(page.getByRole("alert")).toContainText("No se pudo confirmar la operación");
    expect(llamadas).toBe(3);
    expect(new Set(claves).size).toBe(1);
    expect(await movimientos(request, p.id)).toHaveLength(1); // el servidor la registró

    // Sin recargar: mismos datos → misma clave → replay, sin efectos nuevos.
    cortar = false;
    await enviar(page).click();
    await expect(page.getByText("Ingreso registrado.")).toBeVisible();
    expect(await movimientos(request, p.id)).toHaveLength(1);
    expect((await saldos(request, p.id)).deposito).toBe(8);
  });

  test("P13: 40001 y 40P01 se reintentan hasta 3 veces con la misma clave y payload", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    const cuerpos: string[] = [];
    let llamadas = 0;
    await page.route("**/rest/v1/rpc/registrar_ingreso", async (r) => {
      llamadas++;
      cuerpos.push(r.request().postData() ?? "");
      if (llamadas === 1) return r.fulfill(errorPostgrest("40001", "could not serialize access"));
      if (llamadas === 2) return r.fulfill(errorPostgrest("40P01", "deadlock detected"));
      return r.continue();
    });
    await page.goto("/stock");
    await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: "5" });
    await enviar(page).click();

    await expect(page.getByText("Ingreso registrado.")).toBeVisible();
    expect(llamadas).toBe(3);
    expect(new Set(cuerpos).size).toBe(1); // misma clave y mismo payload
    expect(await movimientos(request, p.id)).toHaveLength(1);
  });

  test("P13: 40P01 persistente se detiene en 3 intentos con mensaje claro y sin efectos", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    let llamadas = 0;
    await page.route("**/rest/v1/rpc/registrar_ingreso", (r) => {
      llamadas++;
      return r.fulfill(errorPostgrest("40P01", "deadlock detected"));
    });
    await page.goto("/stock");
    await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: "5" });
    await enviar(page).click();

    await expect(page.getByRole("alert")).toContainText("El sistema estaba ocupado");
    expect(llamadas).toBe(3);
    expect(await movimientos(request, p.id)).toHaveLength(0);
  });

  test("P13: errores de negocio (PTxxx) y 55P03/57014 no se reintentan", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    const casos: [string, string, number][] = [
      ["PT409", "stock_insuficiente", 409],
      ["55P03", "lock not available", 500],
      ["57014", "canceling statement due to statement timeout", 500],
    ];
    await page.goto("/stock");
    for (const [code, message, estado] of casos) {
      let llamadas = 0;
      await page.unroute("**/rest/v1/rpc/registrar_ingreso");
      await page.route("**/rest/v1/rpc/registrar_ingreso", (r) => {
        llamadas++;
        return r.fulfill(errorPostgrest(code, message, estado));
      });
      await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: "2" });
      await enviar(page).click();
      await expect(page.getByRole("alert")).toBeVisible();
      expect(llamadas, code).toBe(1);
    }
    expect(await movimientos(request, p.id)).toHaveLength(0);
  });

  test("resultado incierto: el aviso de cierre/recarga está activo sólo mientras corresponde", async ({
    page,
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    let cortar = true;
    await page.route("**/rest/v1/rpc/registrar_ingreso", (r) =>
      cortar ? r.abort("failed") : r.continue()
    );
    // Despacha un beforeunload cancelable: el manejador de la página lo cancela
    // (defaultPrevented) sólo si hay una operación en vuelo o de resultado incierto.
    const avisaAlCerrar = () =>
      page.evaluate(() => {
        const e = new Event("beforeunload", { cancelable: true });
        window.dispatchEvent(e);
        return e.defaultPrevented;
      });

    await page.goto("/stock");
    await expect(page.getByRole("heading", { name: "Stock" })).toBeVisible();
    expect(await avisaAlCerrar()).toBe(false);

    await operar(page, { tipo: "Ingreso", producto: p.nombre, cantidad: "3" });
    await enviar(page).click();
    await expect(page.getByRole("alert")).toContainText("No se pudo confirmar la operación");
    expect(await avisaAlCerrar()).toBe(true);

    // Reintento exitoso con los mismos datos: el aviso se retira.
    cortar = false;
    await enviar(page).click();
    await expect(page.getByText("Ingreso registrado.")).toBeVisible();
    expect(await avisaAlCerrar()).toBe(false);
    expect(await movimientos(request, p.id)).toHaveLength(1);
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

  test("vendedor: sin acceso a la pantalla ni al menú", async ({ browser }) => {
    const { page, contexto } = await paginaComo(browser, CUENTAS.vendedor);
    try {
      await page.goto("/stock");
      await expect(page.getByText("Acceso no permitido")).toBeVisible();
      await expect(page.getByRole("heading", { name: "Stock" })).toHaveCount(0);
      await expect(page.getByRole("link", { name: "Stock" })).toHaveCount(0);
    } finally {
      await contexto.close();
    }
  });
});

test.describe("Seguridad de las RPC (Data API, sin la interfaz)", () => {
  test("vendedor: ingreso, cuarentena y merma → PT403 stock_no_autorizado y sin efectos", async ({
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    await ingresoApi(request, p.id, 10);
    const dueno = await token(request, CUENTAS.dueno);
    const { deposito } = await ubicaciones(request, dueno);
    const t = await token(request, CUENTAS.vendedor);

    const casos: [string, Record<string, unknown>][] = [
      ["registrar_ingreso", ingresoArgs(p.id, 5)],
      ["mover_a_cuarentena", cuarentenaArgs(p.id, deposito, 1)],
      ["registrar_merma", mermaArgs(p.id, deposito, 1)],
    ];
    for (const [nombre, args] of casos) {
      const r = await rpc(request, t, nombre, args);
      expect([nombre, r.estado, r.cuerpo]).toEqual([
        nombre, 403, expect.objectContaining({ code: "PT403", message: "stock_no_autorizado" }),
      ]);
    }
    expect(await saldos(request, p.id)).toEqual({ deposito: 10, cuarentena: 0 });
    expect(await movimientos(request, p.id)).toHaveLength(1);
  });

  test("usuario inactivo (fixture del seed) → PT403 en las tres RPC", async ({ request }) => {
    const p = await crearProducto(request, "unidad");
    await ingresoApi(request, p.id, 10);
    const dueno = await token(request, CUENTAS.dueno);
    const { deposito } = await ubicaciones(request, dueno);
    const t = await token(request, CUENTAS.inactivo);

    for (const [nombre, args] of [
      ["registrar_ingreso", ingresoArgs(p.id, 5)],
      ["mover_a_cuarentena", cuarentenaArgs(p.id, deposito, 1)],
      ["registrar_merma", mermaArgs(p.id, deposito, 1)],
    ] as [string, Record<string, unknown>][]) {
      const r = await rpc(request, t, nombre, args);
      expect([nombre, r.estado, (r.cuerpo as { message?: string }).message]).toEqual([
        nombre, 403, "stock_no_autorizado",
      ]);
    }
    expect(await movimientos(request, p.id)).toHaveLength(1);
    // Limitación: el seed no tiene un dueño/encargado inactivo; este caso usa un
    // vendedor inactivo, que también falla por rol. No aísla el control de `activo`.
  });

  test("sin sesión (rol anon) → 42501 en las tres RPC", async ({ request }) => {
    const p = await crearProducto(request, "unidad");
    const dueno = await token(request, CUENTAS.dueno);
    const { deposito } = await ubicaciones(request, dueno);

    for (const [nombre, args] of [
      ["registrar_ingreso", ingresoArgs(p.id, 5)],
      ["mover_a_cuarentena", cuarentenaArgs(p.id, deposito, 1)],
      ["registrar_merma", mermaArgs(p.id, deposito, 1)],
    ] as [string, Record<string, unknown>][]) {
      const r = await rpc(request, null, nombre, args);
      expect([nombre, [401, 403].includes(r.estado), (r.cuerpo as { code?: string }).code]).toEqual([
        nombre, true, "42501",
      ]);
    }
    expect(await movimientos(request, p.id)).toHaveLength(0);
  });

  test("otra empresa: producto y ubicaciones ajenos → 404 con el código exacto, sin efectos", async ({
    request,
  }) => {
    // Producto de la empresa 1 con stock, y producto propio de la empresa 2.
    const p1 = await crearProducto(request, "unidad");
    await ingresoApi(request, p1.id, 10);
    const dueno1 = await token(request, CUENTAS.dueno);
    const dep1 = (await ubicaciones(request, dueno1)).deposito;

    const dueno2 = await token(request, CUENTAS.otraEmpresa);
    const creado = await request.post(`${URL_API}/rest/v1/rpc/crear_producto`, {
      headers: cab(dueno2),
      data: { p_codigo: null, p_nombre: `B01 e2 ${sufijo()}`, p_categoria: "lacteos", p_forma_venta: "unidad", p_precio: 10, p_stock_minimo: 0 },
    });
    expect(creado.ok(), await creado.text()).toBe(true);
    const p2 = (await creado.json()) as string;
    const dep2 = (await ubicaciones(request, dueno2)).deposito;
    expect(dep2).not.toBe(dep1);

    const codigo = async (nombre: string, args: Record<string, unknown>, t: string) => {
      const r = await rpc(request, t, nombre, args);
      return [r.estado, (r.cuerpo as { message?: string }).message];
    };
    // Empresa 2 sobre el producto de la empresa 1: indistinguible de inexistente.
    expect(await codigo("registrar_ingreso", ingresoArgs(p1.id, 1), dueno2)).toEqual([404, "stock_producto_no_encontrado"]);
    expect(await codigo("mover_a_cuarentena", cuarentenaArgs(p1.id, dep2, 1), dueno2)).toEqual([404, "stock_producto_no_encontrado"]);
    expect(await codigo("registrar_merma", mermaArgs(p1.id, dep2, 1), dueno2)).toEqual([404, "stock_producto_no_encontrado"]);
    // Producto propio pero depósito ajeno como origen.
    expect(await codigo("mover_a_cuarentena", cuarentenaArgs(p2, dep1, 1), dueno2)).toEqual([404, "stock_ubicacion_no_encontrada"]);
    expect(await codigo("registrar_merma", mermaArgs(p2, dep1, 1), dueno2)).toEqual([404, "stock_ubicacion_no_encontrada"]);
    // Y al revés: empresa 1 sobre producto de empresa 2.
    expect(await codigo("registrar_ingreso", ingresoArgs(p2, 1), dueno1)).toEqual([404, "stock_producto_no_encontrado"]);

    // Lectura: cada empresa ve sólo lo suyo.
    const lect = async (ruta: string, t: string) =>
      (await (await request.get(`${URL_API}/rest/v1/${ruta}`, { headers: cab(t) })).json()) as unknown[];
    expect(await lect(`stock_actual?select=cantidad&producto_id=eq.${p1.id}`, dueno2)).toEqual([]);
    expect(await lect(`productos?select=id&id=eq.${p1.id}`, dueno2)).toEqual([]);
    expect(await lect(`ubicaciones?select=id&id=eq.${dep1}`, dueno2)).toEqual([]);
    expect(await lect(`productos?select=id&id=eq.${p2}`, dueno1)).toEqual([]);

    expect((await saldos(request, p1.id)).deposito).toBe(10);
    expect(await movimientos(request, p1.id)).toHaveLength(1);
  });

  test("idempotencia: misma clave y payload distinto → PT409; mismo payload → mismo id", async ({
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    const dueno = await token(request, CUENTAS.dueno);
    const { deposito } = await ubicaciones(request, dueno);
    const clave = crypto.randomUUID();

    const a = await rpc(request, dueno, "registrar_ingreso", ingresoArgs(p.id, 5, clave));
    expect(a.estado).toBe(200);
    // Replay con el mismo payload: mismo id, sin efectos nuevos.
    const b = await rpc(request, dueno, "registrar_ingreso", ingresoArgs(p.id, 5, clave));
    expect([b.estado, b.cuerpo]).toEqual([200, a.cuerpo]);
    // Otro payload con la misma clave: conflicto exacto.
    const c = await rpc(request, dueno, "registrar_ingreso", ingresoArgs(p.id, 6, clave));
    expect([c.estado, c.cuerpo]).toEqual([409, expect.objectContaining({ code: "PT409", message: "stock_conflicto_idempotencia" })]);
    // Otro tipo de operación con la misma clave: también conflicto.
    const d = await rpc(request, dueno, "mover_a_cuarentena", cuarentenaArgs(p.id, deposito, 1, clave));
    expect([d.estado, (d.cuerpo as { message?: string }).message]).toEqual([409, "stock_conflicto_idempotencia"]);

    expect(await movimientos(request, p.id)).toHaveLength(1);
    expect(await saldos(request, p.id)).toEqual({ deposito: 5, cuarentena: 0 });
  });

  test("idempotencia: la clave es por usuario (el encargado no choca con la del dueño)", async ({
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    const dueno = await token(request, CUENTAS.dueno);
    const encargado = await token(request, CUENTAS.encargado);
    const clave = crypto.randomUUID();

    const a = await rpc(request, dueno, "registrar_ingreso", ingresoArgs(p.id, 5, clave));
    const b = await rpc(request, encargado, "registrar_ingreso", ingresoArgs(p.id, 7, clave));
    expect([a.estado, b.estado]).toEqual([200, 200]);
    expect(a.cuerpo).not.toEqual(b.cuerpo); // operaciones distintas
    expect((await saldos(request, p.id)).deposito).toBe(12);
  });

  test("cantidades inválidas por API → PT400 stock_cantidad_invalida o 400 de PostgREST; sin efectos", async ({
    request,
  }) => {
    const p = await crearProducto(request, "unidad");
    const dueno = await token(request, CUENTAS.dueno);
    for (const cantidad of [0, -1]) {
      const r = await rpc(request, dueno, "registrar_ingreso", ingresoArgs(p.id, cantidad));
      expect([cantidad, r.estado, (r.cuerpo as { message?: string }).message]).toEqual([
        cantidad, 400, "stock_cantidad_invalida",
      ]);
    }
    // Fraccionaria y fuera del rango de integer: las rechaza PostgREST antes de la RPC.
    for (const cantidad of [1.5, 2147483648]) {
      const r = await rpc(request, dueno, "registrar_ingreso", ingresoArgs(p.id, cantidad));
      expect([cantidad, r.estado]).toEqual([cantidad, 400]);
    }
    expect(await movimientos(request, p.id)).toHaveLength(0);
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
