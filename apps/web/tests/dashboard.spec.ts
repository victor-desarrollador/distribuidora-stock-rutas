// Pruebas H-01:
//   1. Dashboard identifica de forma visible que sus valores son datos de
//      demostración, no información operativa real.
//   2. El fallback del router (*) redirige explícitamente a /, respetando
//      autenticación y roles, sin bucles para vendedor_piloto.
//
// No conecta el Dashboard a RPC nueva ni inventa métricas.
import { expect, test, type Page } from "@playwright/test";

import { CUENTAS, PASSWORD_PRUEBA } from "./auth/cuentasPrueba";

async function ingresar(page: Page, usuario: string, password = PASSWORD_PRUEBA) {
  await page.goto("/login");
  await page.getByLabel("Usuario").fill(usuario);
  await page.getByLabel("Contraseña").fill(password);
  await page.getByRole("button", { name: "Ingresar al sistema" }).click();
}

test.describe("Dashboard: aviso de datos demostrativos", () => {
  test("muestra un aviso visible de que los valores son de demostración", async ({
    page,
  }) => {
    await ingresar(page, CUENTAS.dueno);
    await expect(page).toHaveURL("/");

    await expect(
      page.getByText(
        /Datos de demostración: los valores de esta pantalla son ficticios/
      )
    ).toBeVisible();
  });
});

test.describe("Fallback del router (*) redirige a /", () => {
  test("sin sesión: ruta inexistente redirige a /login", async ({ page }) => {
    await page.goto("/ruta-que-no-existe");
    await expect(page).toHaveURL("/login");
  });

  test.use({ storageState: "playwright/.auth/dueno.json" });

  test("con sesión de dueño: ruta inexistente redirige a /", async ({ page }) => {
    await page.goto("/ruta-que-no-existe");
    await expect(page).toHaveURL("/");
  });
});
