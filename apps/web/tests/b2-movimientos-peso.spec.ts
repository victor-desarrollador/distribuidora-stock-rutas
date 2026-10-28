// B2 (ADR-005): Movimientos con productos `peso` desde la UI real, sobre una
// jornada abierta. Kg con coma y hasta 3 decimales → gramos enteros exactos.
// Cambio `peso ↔ peso` con cantidades independientes; cambio mixto
// (`unidad ↔ peso`) bloqueado (P-B2-3). Sólo claves `_demo_v5`.
import { expect, test, type Page } from "@playwright/test";

import { MENSAJE_CAMBIO_MIXTO_NO_HABILITADO } from "../src/domain/movimientos";

const claves = {
  productos: "distribuidora_productos_demo_v5",
  camiones: "distribuidora_camiones_demo_v5",
  clientes: "distribuidora_clientes_demo_v2",
  jornadas: "distribuidora_jornadas_demo_v5",
  ventas: "distribuidora_ventas_demo_v5",
  cobros: "distribuidora_cobros_demo_v5",
  movimientos: "distribuidora_movimientos_demo_v5",
  retornos: "distribuidora_retornos_demo_v5",
} as const;

const productos = [
  { id: 1, nombre: "Yogur MB2", categoria: "Lácteos", unidadMedida: "unidad", stock: 120, precio: 2300, stockMinimo: 20 },
  { id: 4, nombre: "Jamón MB2", categoria: "Fiambres", unidadMedida: "peso", stock: 18000, precio: 12500, stockMinimo: 5000 },
  { id: 5, nombre: "Salame MB2", categoria: "Fiambres", unidadMedida: "peso", stock: 9000, precio: 9800, stockMinimo: 3000 },
];

const camiones = [
  { id: 1, nombre: "Camión MB2", patente: "MB222AA", marca: "Iveco", modelo: "Daily", estado: "disponible", observaciones: "" },
];

const clientes = [
  {
    id: 1,
    nombreComercio: "Almacén MB2",
    titular: "Titular de prueba",
    telefono: "3815550000",
    direccion: "Calle de prueba",
    zona: "Centro",
    condicionPago: "contado",
    limiteCredito: 0,
    activo: true,
  },
];

const jornadaAbierta = {
  id: "jornada-mb2",
  camionId: 1,
  chofer: "Chofer MB2",
  zona: "Centro",
  fechaCreacion: "2026-10-27T08:00:00.000Z",
  fechaSalida: "2026-10-27T09:00:00.000Z",
  estado: "abierta",
  items: [
    { productoId: 1, nombreProducto: "Yogur MB2", unidadMedida: "unidad", cantidad: 10, precioReferencia: 2300 },
    { productoId: 4, nombreProducto: "Jamón MB2", unidadMedida: "peso", cantidad: 5000, precioReferencia: 12500 },
    { productoId: 5, nombreProducto: "Salame MB2", unidadMedida: "peso", cantidad: 2000, precioReferencia: 9800 },
  ],
};

type Producto = { productoId: number; unidadMedida: string; cantidad: number };
type Movimiento = {
  tipo: string;
  producto?: Producto;
  productoDevuelto?: Producto;
  productoEntregado?: Producto;
};

async function sembrar(page: Page) {
  await page.addInitScript(
    ({ c, datos }) => {
      if (sessionStorage.getItem("__mb2_sembrado") === null) {
        localStorage.setItem(c.productos, JSON.stringify(datos.productos));
        localStorage.setItem(c.camiones, JSON.stringify(datos.camiones));
        localStorage.setItem(c.clientes, JSON.stringify(datos.clientes));
        localStorage.setItem(c.jornadas, JSON.stringify([datos.jornada]));
        localStorage.setItem(c.ventas, "[]");
        localStorage.setItem(c.cobros, "[]");
        localStorage.setItem(c.movimientos, "[]");
        localStorage.setItem(c.retornos, "[]");
        sessionStorage.setItem("__mb2_sembrado", "1");
        sessionStorage.setItem("__mb2_set_mov", "0");
      }
      const original = Storage.prototype.setItem;
      Storage.prototype.setItem = function (key, value) {
        if (key === c.movimientos) {
          const n = Number(sessionStorage.getItem("__mb2_set_mov") ?? "0");
          original.call(sessionStorage, "__mb2_set_mov", String(n + 1));
        }
        return original.call(this, key, value);
      };
    },
    { c: claves, datos: { productos, camiones, clientes, jornada: jornadaAbierta } }
  );
}

async function movimientosGuardados(page: Page): Promise<Movimiento[]> {
  return JSON.parse(
    String(await page.evaluate((c) => localStorage.getItem(c), claves.movimientos))
  );
}

async function escriturasMovimientos(page: Page): Promise<number> {
  return Number(await page.evaluate(() => sessionStorage.getItem("__mb2_set_mov")));
}

async function iniciar(page: Page, tipo: "Merma" | "Devolución" | "Cambio") {
  await sembrar(page);
  await page.goto("/movimientos");
  await page.getByLabel("Jornada de reparto").selectOption(jornadaAbierta.id);
  await page.getByRole("button", { name: tipo, exact: true }).click();
}

const motivo = (page: Page) =>
  page.getByLabel("Motivo *").selectOption("Otro motivo");

test("B2 Movimientos: merma de 1,250 kg persiste 1250 g y el disponible se actualiza en kg", async ({
  page,
}) => {
  await iniciar(page, "Merma");
  await page.getByLabel("Producto dañado *").selectOption("4");
  await expect(page.getByText("Disponible: 5,000 kg")).toBeVisible();
  await page.getByLabel("Cantidad * (kg)").fill("1,250");
  await motivo(page);
  await page.getByRole("button", { name: "Registrar merma" }).click();

  await expect(page.getByRole("status")).toContainText("registrada correctamente");
  const [m] = await movimientosGuardados(page);
  expect(m.tipo).toBe("merma");
  expect(m.producto).toEqual(
    expect.objectContaining({ productoId: 4, unidadMedida: "peso", cantidad: 1250 })
  );

  await page.getByLabel("Producto dañado *").selectOption("4");
  await expect(page.getByText("Disponible: 3,750 kg")).toBeVisible();
});

test("B2 Movimientos: devolución de 1,005 kg persiste 1005 g (sin punto flotante)", async ({
  page,
}) => {
  await iniciar(page, "Devolución");
  await page.getByLabel(/^Cliente \*/).selectOption("1");
  await page.getByLabel("Producto devuelto por el cliente *").selectOption("4");
  await page.getByLabel("Cantidad * (kg)").fill("1,005");
  await motivo(page);
  await page.getByRole("button", { name: "Registrar devolución" }).click();

  await expect(page.getByRole("status")).toContainText("registrada correctamente");
  const [m] = await movimientosGuardados(page);
  expect(m.tipo).toBe("devolucion");
  expect(m.producto?.cantidad).toBe(1005);
});

test("B2 Movimientos: cambio peso ↔ peso persiste cada lado con su propia cantidad", async ({
  page,
}) => {
  await iniciar(page, "Cambio");
  await page.getByLabel(/^Cliente \*/).selectOption("1");
  await page.getByLabel("Producto devuelto por el cliente *").selectOption("4");
  await page.getByLabel("Cantidad * (kg)").fill("0,500");
  await page.getByLabel("Producto entregado *").selectOption("5");
  await page.getByLabel("Cantidad entregada * (kg)").fill("1,250");
  await expect(page.getByText(MENSAJE_CAMBIO_MIXTO_NO_HABILITADO)).toHaveCount(0);
  await motivo(page);
  await page.getByRole("button", { name: "Registrar cambio" }).click();

  await expect(page.getByRole("status")).toContainText("registrada correctamente");
  const [m] = await movimientosGuardados(page);
  expect(m.tipo).toBe("cambio");
  expect(m.productoDevuelto).toEqual(
    expect.objectContaining({ productoId: 4, unidadMedida: "peso", cantidad: 500 })
  );
  expect(m.productoEntregado).toEqual(
    expect.objectContaining({ productoId: 5, unidadMedida: "peso", cantidad: 1250 })
  );
});

for (const [nombre, devuelto, entregado] of [
  ["unidad ↔ peso", "1", "4"],
  ["peso ↔ unidad", "4", "1"],
] as const) {
  test(`B2 Movimientos: cambio mixto ${nombre} bloqueado con mensaje explícito y sin escritura`, async ({
    page,
  }) => {
    await iniciar(page, "Cambio");
    await page.getByLabel(/^Cliente \*/).selectOption("1");
    await page.getByLabel("Producto devuelto por el cliente *").selectOption(devuelto);
    await page.getByLabel("Producto entregado *").selectOption(entregado);
    await motivo(page);

    await expect(
      page.getByRole("alert").filter({ hasText: MENSAJE_CAMBIO_MIXTO_NO_HABILITADO })
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Registrar cambio" })).toBeDisabled();
    expect(await escriturasMovimientos(page)).toBe(0);
    expect(await movimientosGuardados(page)).toEqual([]);
  });
}

test("B2 Movimientos: exceder el disponible por 1 g se rechaza sin escribir", async ({
  page,
}) => {
  await iniciar(page, "Merma");
  await page.getByLabel("Producto dañado *").selectOption("5");
  await expect(page.getByText("Disponible: 2,000 kg")).toBeVisible();
  await page.getByLabel("Cantidad * (kg)").fill("2,001");
  await motivo(page);
  await page.getByRole("button", { name: "Registrar merma" }).click();

  await expect(
    page.getByRole("alert").filter({ hasText: "Stock insuficiente de Salame MB2." })
  ).toBeVisible();
  expect(await escriturasMovimientos(page)).toBe(0);
  expect(await movimientosGuardados(page)).toEqual([]);

  // El límite exacto sí se acepta.
  await page.getByLabel("Cantidad * (kg)").fill("2,000");
  await page.getByRole("button", { name: "Registrar merma" }).click();
  await expect(page.getByRole("status")).toContainText("registrada correctamente");
  expect((await movimientosGuardados(page))[0].producto?.cantidad).toBe(2000);
});
