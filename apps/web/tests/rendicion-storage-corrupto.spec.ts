import { expect, test } from "@playwright/test";

const CLAVE_JORNADAS = "distribuidora_jornadas_demo_v5";
const CLAVE_MOVIMIENTOS = "distribuidora_movimientos_demo_v5";
const RAW_CORRUPTO = "{movimientos dañados";

test("Rendición avisa movimientos corruptos, no inventa ceros y bloquea el cierre", async ({
  page,
}) => {
  await page.addInitScript(
    ({ claveJornadas, claveMovimientos, rawCorrupto }) => {
      localStorage.setItem(
        claveJornadas,
        JSON.stringify([
          {
            id: "jornada-e2e",
            camionId: 1,
            chofer: "Vendedor E2E",
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
          },
        ])
      );
      localStorage.setItem(claveMovimientos, rawCorrupto);

      const originalSetItem = Storage.prototype.setItem;
      const originalRemoveItem = Storage.prototype.removeItem;
      const contadores = { setItem: 0, removeItem: 0 };
      Object.defineProperty(window, "__movimientosStorage", {
        value: contadores,
        configurable: true,
      });

      Storage.prototype.setItem = function (clave, valor) {
        if (clave === claveMovimientos) contadores.setItem += 1;
        return originalSetItem.call(this, clave, valor);
      };
      Storage.prototype.removeItem = function (clave) {
        if (clave === claveMovimientos) contadores.removeItem += 1;
        return originalRemoveItem.call(this, clave);
      };
    },
    {
      claveJornadas: CLAVE_JORNADAS,
      claveMovimientos: CLAVE_MOVIMIENTOS,
      rawCorrupto: RAW_CORRUPTO,
    }
  );

  await page.goto("/rendicion");
  await page.getByLabel("Seleccionar jornada para rendición").selectOption("jornada-e2e");

  await expect(
    page.getByText(
      "Los datos de movimientos guardados están dañados. No se puede calcular la rendición con seguridad."
    )
  ).toBeVisible();

  const fila = page.getByRole("heading", { name: "Yogur bebible 1 L" }).locator("..");
  await expect(fila.getByText("No disponible")).toHaveCount(3);
  await expect(page.getByText("Productos devueltos en cuarentena").locator("..")).toContainText(
    "No disponible"
  );
  await expect(page.getByRole("button", { name: "Completar con esperados" })).toBeDisabled();
  await expect(page.getByRole("button", { name: "Confirmar cierre de jornada" })).toBeDisabled();

  const estado = await page.evaluate((clave) => {
    const contadores = (
      window as Window & {
        __movimientosStorage: { setItem: number; removeItem: number };
      }
    ).__movimientosStorage;
    return {
      raw: localStorage.getItem(clave),
      ...contadores,
    };
  }, CLAVE_MOVIMIENTOS);

  expect(estado).toEqual({ raw: RAW_CORRUPTO, setItem: 0, removeItem: 0 });
});
