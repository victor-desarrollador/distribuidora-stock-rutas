import { expect, test, type Page } from "@playwright/test";

const claves = {
  productos: "distribuidora_productos_demo_v4",
  camiones: "distribuidora_camiones_demo_v4",
  clientes: "distribuidora_clientes_demo_v2",
  jornadas: "distribuidora_jornadas_demo_v4",
  ventas: "distribuidora_ventas_demo_v4",
  cobros: "distribuidora_cobros_demo_v4",
  movimientos: "distribuidora_movimientos_demo_v4",
  retornos: "distribuidora_retornos_demo_v4",
} as const;

const rawCorrupto = "{ledger dañado después del montaje";

const producto = {
  id: 1,
  nombre: "Yogur bebible 1 L",
  categoria: "Lácteos",
  unidadMedida: "unidad",
  stock: 120,
  precio: 2300,
  stockMinimo: 20,
};

const camion = {
  id: 1,
  nombre: "Camión TOCTOU",
  patente: "AE123BC",
  marca: "Iveco",
  modelo: "Daily",
  estado: "disponible",
  observaciones: "",
};

const cliente = {
  id: 1,
  nombreComercio: "Almacén TOCTOU",
  titular: "Cliente de prueba",
  telefono: "3815551234",
  direccion: "Calle 1",
  zona: "Centro",
  condicionPago: "cuenta_corriente",
  limiteCredito: 200000,
  activo: true,
};

const jornadaAbierta = {
  id: "jornada-toctou",
  camionId: 1,
  chofer: "Chofer TOCTOU",
  zona: "Centro",
  fechaCreacion: "2026-10-22T08:00:00.000Z",
  fechaSalida: "2026-10-22T09:00:00.000Z",
  estado: "abierta",
  items: [
    {
      productoId: 1,
      nombreProducto: producto.nombre,
      unidadMedida: "unidad",
      cantidad: 10,
      precioReferencia: 2300,
    },
  ],
};

async function prepararStorage(page: Page, jornadas = [jornadaAbierta]) {
  await page.addInitScript(
    ({ storage, datos }) => {
      localStorage.setItem(storage.productos, JSON.stringify(datos.productos));
      localStorage.setItem(storage.camiones, JSON.stringify(datos.camiones));
      localStorage.setItem(storage.clientes, JSON.stringify(datos.clientes));
      localStorage.setItem(storage.jornadas, JSON.stringify(datos.jornadas));
      localStorage.setItem(storage.ventas, "[]");
      localStorage.setItem(storage.cobros, "[]");
      localStorage.setItem(storage.movimientos, "[]");
      localStorage.setItem(storage.retornos, "[]");
    },
    {
      storage: claves,
      datos: {
        productos: [producto],
        camiones: [camion],
        clientes: [cliente],
        jornadas,
      },
    }
  );
}

async function corromper(page: Page, clave: string) {
  await page.evaluate(
    ({ storageKey, raw }) => localStorage.setItem(storageKey, raw),
    { storageKey: clave, raw: rawCorrupto }
  );
}

async function leerRaw(page: Page, clave: string) {
  return page.evaluate((storageKey) => localStorage.getItem(storageKey), clave);
}

test("Autoventa aborta si Movimientos se corrompe después del montaje", async ({
  page,
}) => {
  await prepararStorage(page);
  await page.goto("/autoventa");
  await page.getByLabel("Seleccionar reparto").selectOption(jornadaAbierta.id);
  await page.locator("select").nth(1).selectOption("1");
  await page.getByLabel(`Cantidad de ${producto.nombre}`).fill("1");
  const registrar = page.getByRole("button", { name: "Registrar venta" });
  await expect(registrar).toBeEnabled();

  await corromper(page, claves.movimientos);
  await registrar.click();

  await expect(page.getByRole("alert")).toContainText("No se puede registrar");
  expect(await leerRaw(page, claves.ventas)).toBe("[]");
  expect(await leerRaw(page, claves.movimientos)).toBe(rawCorrupto);
});

test("Movimientos aborta si Ventas se corrompe después del montaje", async ({
  page,
}) => {
  await prepararStorage(page);
  await page.goto("/movimientos");
  await page.getByLabel("Jornada de reparto").selectOption(jornadaAbierta.id);
  await page.getByLabel("Producto dañado *").selectOption("1");
  await page.getByLabel("Cantidad *").fill("1");
  await page.getByLabel("Motivo *").selectOption("Producto vencido");

  await corromper(page, claves.ventas);
  await page.getByRole("button", { name: "Registrar merma" }).click();

  await expect(page.getByRole("alert")).toContainText("No se puede registrar");
  expect(await leerRaw(page, claves.ventas)).toBe(rawCorrupto);
  expect(await leerRaw(page, claves.movimientos)).toBe("[]");
});

test("Jornadas aborta si Retornos se corrompe después del montaje", async ({
  page,
}) => {
  await prepararStorage(page, []);
  await page.goto("/jornadas");
  await page.getByRole("button", { name: "Nueva jornada" }).click();
  await page.getByLabel("Camión *").selectOption("1");
  await page.getByLabel("Chofer *").fill("Chofer de prueba");
  await page.getByLabel("Zona *").fill("Centro");
  await page.getByLabel(`Cantidad de ${producto.nombre}`).fill("1");

  await corromper(page, claves.retornos);
  await page.getByRole("button", { name: "Guardar preparación" }).click();

  await expect(page.getByRole("alert")).toContainText(
    "No se puede guardar la preparación"
  );
  expect(await leerRaw(page, claves.retornos)).toBe(rawCorrupto);
  expect(await leerRaw(page, claves.jornadas)).toBe("[]");
});

for (const ledger of ["ventas", "cobros", "movimientos"] as const) {
  test(`Rendición aborta si ${ledger} se corrompe después del montaje`, async ({
    page,
  }) => {
    await prepararStorage(page);
    await page.goto("/rendicion");
    await page
      .getByLabel("Seleccionar jornada para rendición")
      .selectOption(jornadaAbierta.id);
    await page.getByRole("button", { name: "Completar con esperados" }).click();
    await page.getByLabel("Efectivo entregado por el repartidor *").fill("0");
    const jornadasAntes = await leerRaw(page, claves.jornadas);
    const confirmar = page.getByRole("button", {
      name: "Confirmar cierre de jornada",
    });
    await expect(confirmar).toBeEnabled();

    await corromper(page, claves[ledger]);
    await confirmar.click();

    await expect(page.getByRole("alert")).toContainText("No se puede cerrar");
    expect(await leerRaw(page, claves[ledger])).toBe(rawCorrupto);
    expect(await leerRaw(page, claves.jornadas)).toBe(jornadasAntes);
  });
}
