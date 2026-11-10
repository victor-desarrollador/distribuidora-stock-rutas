// Pruebas de acceso directo a las 8 rutas retiradas (dependían de
// localStorage como fuente de verdad de negocio):
//   /demo/jornadas, /autoventa, /ventas, /movimientos, /rendicion,
//   /retornos, /cuentas, /configuracion-demo
//
// Ninguna de estas rutas existe ya en el router (App.tsx). Al acceder
// directamente por URL, el fallback `*` redirige a `/`. Las pruebas
// verifican:
//   - sin sesión: se redirige a /login (la sesión no se restaura);
//   - con sesión (dueño): no se muestra ninguna pantalla de negocio demo;
//     se aterriza en / o en la pantalla de acceso según corresponda.
//
// No toca Supabase Auth, contratos RPC ni RLS. Solo comprueba el router y el
// fallback.
import { expect, test } from "@playwright/test";

const RUTAS_RETIRADAS = [
  "/demo/jornadas",
  "/autoventa",
  "/ventas",
  "/movimientos",
  "/rendicion",
  "/retornos",
  "/cuentas",
  "/configuracion-demo",
] as const;

test.use({ storageState: { cookies: [], origins: [] } });

test.describe("rutas retiradas: sin sesión", () => {
  for (const ruta of RUTAS_RETIRADAS) {
    test(`${ruta} sin sesión redirige a /login`, async ({ page }) => {
      await page.goto(ruta);
      await expect(page).toHaveURL("/login");
    });
  }
});

test.describe("rutas retiradas: con sesión de dueño", () => {
  test.use({
    storageState: "playwright/.auth/dueno.json",
  });

  for (const ruta of RUTAS_RETIRADAS) {
    test(`${ruta} con sesión no muestra pantalla de negocio demo`, async ({
      page,
    }) => {
      await page.goto(ruta);

      // El fallback redirige a / (página de inicio). Nunca se monta
      // Autoventa, Movimientos, Rendición, Retornos, Cuentas ni Configuración.
      await expect(page).toHaveURL("/");

      // No debe aparecer el aviso operativo de ninguna pantalla retirada.
      await expect(
        page.getByRole("heading", { name: "Acceso no permitido" })
      ).not.toBeVisible();
      await expect(
        page.getByRole("heading", { name: "Acceso bloqueado" })
      ).not.toBeVisible();
    });
  }
});

test.describe("rutas reales de Supabase conservan sus permisos", () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test("sin sesión: /productos, /stock, /clientes, /camiones, /jornadas redirigen a /login", async ({
    page,
  }) => {
    for (const ruta of ["/productos", "/stock", "/clientes", "/camiones", "/jornadas"]) {
      await page.goto(ruta);
      await expect(page).toHaveURL("/login");
    }
  });
});
