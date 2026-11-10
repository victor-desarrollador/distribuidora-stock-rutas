// Pruebas H-01:
//   1. Dashboard identifica de forma visible que sus valores son
//      datos de demostración, no información operativa real.
//   2. El fallback del router (*) redirige explícitamente a /, respetando
//      autenticación y roles, sin bucles para vendedor_piloto.
//
// No conecta el Dashboard a RPC nueva ni inventa métricas.
import { expect, test, type Page, type BrowserContext } from "@playwright/test";

test.describe("Dashboard: aviso de datos demostrativos", () => {
  test("muestra un aviso visible de que los valores son de demostración", async ({
    page,
  }) => {
    // El proyecto chromium ya provee storageState de dueno (sesión activa,
    // generado por auth.setup.ts), por lo que no es necesario iniciar sesión
    // de nuevo. Ir directamente al Dashboard y verificar el aviso.
    await page.goto("/");

    await expect(
      page.getByText(
        /Datos de demostración: los valores de esta pantalla son ficticios/
      )
    ).toBeVisible();
  });
});

test.describe("Fallback del router (*) sin sesión", () => {
  test("ruta inexistente redirige a /login", async ({
    page,
    context,
  }: { page: Page; context: BrowserContext }) => {
    // El proyecto chromium inyecta storageState de dueno (sesión activa) en
    // todos los tests. Para este caso se requiere un contexto sin sesión:
    // se limpian las cookies de sesión y el almacenamiento del navegador
    // antes de navegar, sin modificar el router ni otros archivos de prueba.
    await context.clearCookies();
    // Navegar primero a la raíz (mismo origen) para poder acceder a
    // localStorage y limpiarlo antes de ir a la ruta inexistente.
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.clear();
      sessionStorage.clear();
    });
    await page.goto("/ruta-que-no-existe");
    await expect(page).toHaveURL("/login");
  });
});

test.describe("Fallback del router (*) con sesión de dueño", () => {
  test.use({ storageState: "playwright/.auth/dueno.json" });

  test("ruta inexistente redirige a /", async ({ page }) => {
    await page.goto("/ruta-que-no-existe");
    await expect(page).toHaveURL("/");
  });
});
