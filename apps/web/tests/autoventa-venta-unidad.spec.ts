// AUD-001: camino positivo de punta a punta. Autoventa ya no autoriza stock:
// llama a registrarVenta(venta) y la frontera persistente (registroVentas)
// relee Ventas, Jornada y Movimientos y valida el stock por sí misma. Este
// test prueba el cableado real desde la UI: una venta `unidad` con stock
// suficiente se registra, se persiste una vez y se muestra.
import { expect, test, type Page } from "@playwright/test";

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

const producto = {
  id: 1,
  nombre: "Yogur Autoventa E2E",
  categoria: "Lácteos",
  unidadMedida: "unidad",
  stock: 120,
  precio: 2300,
  stockMinimo: 20,
};

const camion = {
  id: 1,
  nombre: "Camión Autoventa E2E",
  patente: "AV123AA",
  marca: "Iveco",
  modelo: "Daily",
  estado: "disponible",
  observaciones: "",
};

const cliente = {
  id: 1,
  nombreComercio: "Almacén Autoventa E2E",
  titular: "Titular de prueba",
  telefono: "3815550000",
  direccion: "Calle de prueba",
  zona: "Centro",
  condicionPago: "contado",
  limiteCredito: 0,
  activo: true,
};

const jornadaAbierta = {
  id: "jornada-autoventa-e2e",
  camionId: 1,
  chofer: "Chofer Autoventa E2E",
  zona: "Centro",
  fechaCreacion: "2026-10-28T08:00:00.000Z",
  fechaSalida: "2026-10-28T09:00:00.000Z",
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

async function prepararStorage(page: Page) {
  await page.addInitScript(
    ({ clavesStorage, info }) => {
      // Sólo en la primera carga: no pisar lo que la app persista después.
      if (localStorage.getItem(clavesStorage.jornadas) !== null) return;
      localStorage.setItem(clavesStorage.productos, JSON.stringify([info.producto]));
      localStorage.setItem(clavesStorage.camiones, JSON.stringify([info.camion]));
      localStorage.setItem(clavesStorage.clientes, JSON.stringify([info.cliente]));
      localStorage.setItem(clavesStorage.jornadas, JSON.stringify([info.jornada]));
      localStorage.setItem(clavesStorage.ventas, "[]");
      localStorage.setItem(clavesStorage.cobros, "[]");
      localStorage.setItem(clavesStorage.movimientos, "[]");
      localStorage.setItem(clavesStorage.retornos, "[]");
    },
    {
      clavesStorage: claves,
      info: { producto, camion, cliente, jornada: jornadaAbierta },
    }
  );
}

async function leerRaw(page: Page, clave: string) {
  return page.evaluate((storageKey) => localStorage.getItem(storageKey), clave);
}

test("Autoventa: venta unidad con stock suficiente se registra, persiste y se muestra", async ({
  page,
}) => {
  await prepararStorage(page);
  await page.goto("/autoventa");

  const jornadasAntes = await leerRaw(page, claves.jornadas);
  const movimientosAntes = await leerRaw(page, claves.movimientos);

  await page.getByLabel("Seleccionar reparto").selectOption(jornadaAbierta.id);
  await page.locator("select").nth(1).selectOption(String(cliente.id));
  await page.getByLabel(`Cantidad de ${producto.nombre}`).fill("2");

  const registrar = page.getByRole("button", { name: "Registrar venta" });
  await expect(registrar).toBeEnabled();
  await registrar.click();

  // Sin error y con confirmación visible.
  await expect(page.getByRole("status")).toContainText(
    "Venta registrada correctamente"
  );
  await expect(page.getByRole("alert")).toHaveCount(0);

  // Persistida exactamente una venta, con los datos armados por la pantalla.
  const ventas = JSON.parse((await leerRaw(page, claves.ventas)) ?? "null");
  expect(ventas).toHaveLength(1);
  expect(ventas[0]).toMatchObject({
    jornadaId: jornadaAbierta.id,
    camionId: 1,
    clienteId: cliente.id,
    nombreCliente: cliente.nombreComercio,
    medioPago: "efectivo",
    total: 4600,
    items: [
      {
        productoId: 1,
        nombreProducto: producto.nombre,
        unidadMedida: "unidad",
        cantidad: 2,
        precioUnitario: 2300,
        subtotal: 4600,
      },
    ],
  });
  expect(typeof ventas[0].id).toBe("string");

  // La venta no altera Jornadas ni Movimientos.
  expect(await leerRaw(page, claves.jornadas)).toBe(jornadasAntes);
  expect(await leerRaw(page, claves.movimientos)).toBe(movimientosAntes);

  // Visible en el historial de la jornada (estado del hook vía alGuardar).
  await expect(page.getByText("Todavía no hay ventas en esta jornada.")).toHaveCount(0);
  await expect(page.getByText(cliente.nombreComercio).last()).toBeVisible();

  // Tras recargar, la venta sigue persistida y visible.
  await page.reload();
  await page.getByLabel("Seleccionar reparto").selectOption(jornadaAbierta.id);
  await expect(page.getByText("Todavía no hay ventas en esta jornada.")).toHaveCount(0);
  expect(JSON.parse((await leerRaw(page, claves.ventas)) ?? "null")).toHaveLength(1);
});
