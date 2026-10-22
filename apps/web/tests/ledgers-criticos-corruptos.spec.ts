import { expect, test, type Page } from "@playwright/test";

const claves = {
  jornadas: "distribuidora_jornadas_demo_v4",
  ventas: "distribuidora_ventas_demo_v4",
  cobros: "distribuidora_cobros_demo_v4",
} as const;

const jornadaAbierta = {
  id: "jornada-integracion",
  camionId: 1,
  chofer: "Vendedor Integración",
  zona: "Centro",
  fechaCreacion: "2026-10-22T08:00:00.000Z",
  fechaSalida: "2026-10-22T09:00:00.000Z",
  estado: "abierta",
  items: [
    {
      productoId: 1,
      nombreProducto: "Yogur bebible 1 L",
      unidadMedida: "unidad",
      cantidad: 10,
      precioReferencia: 2300,
    },
  ],
};

async function preparar(page: Page, corrupta?: "ventas" | "cobros") {
  await page.addInitScript(
    ({ claveJornadas, jornada, claveCorrupta }) => {
      localStorage.setItem("distribuidora_sesion_demo_v1", "admin-demo");
      localStorage.setItem(claveJornadas, JSON.stringify([jornada]));
      if (claveCorrupta) localStorage.setItem(claveCorrupta, "{ledger dañado");
    },
    {
      claveJornadas: claves.jornadas,
      jornada: jornadaAbierta,
      claveCorrupta: corrupta ? claves[corrupta] : null,
    }
  );
}

test("Rendición bloquea el cierre y no inventa vendido/caja ante Ventas corruptas", async ({
  page,
}) => {
  await preparar(page, "ventas");
  await page.goto("/rendicion");
  await page.getByLabel("Seleccionar jornada para rendición").selectOption(jornadaAbierta.id);

  await expect(
    page.getByText("Los datos de ventas guardados están dañados.", { exact: false })
  ).toBeVisible();
  const fila = page.getByRole("heading", { name: "Yogur bebible 1 L" }).locator("..");
  await expect(fila.getByText("Vendido").locator("..")).toContainText("No disponible");
  await expect(fila.getByText("Esperado").locator("..")).toContainText("No disponible");
  await expect(page.getByText("Efectivo esperado a rendir").locator("..")).toContainText(
    "No disponible"
  );
  await expect(page.getByRole("button", { name: "Confirmar cierre de jornada" })).toBeDisabled();
});

test("Rendición conserva mercadería confiable pero bloquea caja/cierre ante Cobros corruptos", async ({
  page,
}) => {
  await preparar(page, "cobros");
  await page.goto("/rendicion");
  await page.getByLabel("Seleccionar jornada para rendición").selectOption(jornadaAbierta.id);

  await expect(
    page.getByText("Los datos de cobros guardados están dañados.", { exact: false })
  ).toBeVisible();
  const fila = page.getByRole("heading", { name: "Yogur bebible 1 L" }).locator("..");
  await expect(fila).toContainText("10 un.");
  await expect(page.getByText("Efectivo esperado a rendir").locator("..")).toContainText(
    "No disponible"
  );
  await expect(page.getByRole("button", { name: "Confirmar cierre de jornada" })).toBeDisabled();
});

test("Rendición no bloquea falsamente el estado inicial legítimo", async ({ page }) => {
  await preparar(page);
  await page.goto("/rendicion");
  await page.getByLabel("Seleccionar jornada para rendición").selectOption(jornadaAbierta.id);

  await expect(page.getByText("Datos dañados:", { exact: false })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Confirmar cierre de jornada" })).toBeEnabled();
});

for (const ledger of ["ventas", "cobros"] as const) {
  test(`Cuentas Corrientes no muestra saldo $0 ni permite cobrar con ${ledger} corruptos`, async ({
    page,
  }) => {
    await preparar(page, ledger);
    await page.goto("/cuentas");

    await expect(
      page.getByText(`Los datos de ${ledger} guardados están dañados.`, { exact: false })
    ).toBeVisible();
    const cliente = page.getByRole("button", { name: /Almacén Don Pedro/ });
    const saldo = cliente.getByText("Saldo pendiente").locator("..");
    await expect(saldo).toContainText("No disponible");
    await expect(saldo).not.toContainText("$ 0");
    await cliente.click();
    await page.getByLabel("Importe a cobrar *").fill("10");
    await expect(page.getByRole("button", { name: "Confirmar cobro" })).toBeDisabled();
  });
}
