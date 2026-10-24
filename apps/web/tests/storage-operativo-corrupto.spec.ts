import { expect, test } from "@playwright/test";

const casos = [
  {
    // /productos ya no usa el catálogo demo (lee Supabase); el catálogo demo
    // dañado se sigue detectando en las pantallas operativas que lo usan.
    nombre: "productos",
    clave: "distribuidora_productos_demo_v4",
    ruta: "/jornadas",
    aviso: "Los datos de productos guardados están dañados.",
    accion: "Nueva jornada",
    semilla: null,
  },
  {
    // /camiones ya no usa el catálogo demo (lee Supabase); el catálogo demo
    // dañado se sigue detectando en las pantallas operativas que lo usan.
    nombre: "camiones",
    clave: "distribuidora_camiones_demo_v4",
    ruta: "/jornadas",
    aviso: "Los datos de camiones guardados están dañados.",
    accion: "Nueva jornada",
    semilla: null,
  },
  {
    // /clientes ya no usa el catálogo demo (lee Supabase); el catálogo demo
    // dañado se sigue detectando en las pantallas operativas que lo usan. En
    // Movimientos el botón de registro no se muestra sin una jornada abierta.
    nombre: "clientes",
    clave: "distribuidora_clientes_demo_v2",
    ruta: "/movimientos",
    aviso: "Los datos de clientes guardados están dañados.",
    accion: null,
    semilla: null,
  },
  {
    nombre: "jornadas",
    clave: "distribuidora_jornadas_demo_v4",
    ruta: "/jornadas",
    aviso: "Los datos de jornadas guardados están dañados.",
    accion: "Nueva jornada",
    semilla: null,
  },
] as const;

for (const caso of casos) {
  test(`${caso.nombre}: corrupción visible, acción bloqueada y raw intacto`, async ({
    page,
  }) => {
    const raw = `{${caso.nombre} dañados`;
    await page.addInitScript(
      ({ clave, rawCorrupto }) => {
        localStorage.setItem(clave, rawCorrupto);

        const originalSetItem = Storage.prototype.setItem;
        const originalRemoveItem = Storage.prototype.removeItem;
        const contadores = { setItem: 0, removeItem: 0 };
        Object.defineProperty(window, "__storageOperativo", {
          value: contadores,
          configurable: true,
        });
        Storage.prototype.setItem = function (key, value) {
          if (key === clave) contadores.setItem += 1;
          return originalSetItem.call(this, key, value);
        };
        Storage.prototype.removeItem = function (key) {
          if (key === clave) contadores.removeItem += 1;
          return originalRemoveItem.call(this, key);
        };
      },
      { clave: caso.clave, rawCorrupto: raw }
    );

    await page.goto(caso.ruta);

    await expect(page.getByText(caso.aviso, { exact: false })).toBeVisible();
    if (caso.accion) {
      await expect(page.getByRole("button", { name: caso.accion })).toBeDisabled();
    }
    if (caso.semilla) {
      await expect(page.getByText(caso.semilla, { exact: false })).toHaveCount(0);
    }

    const estado = await page.evaluate((clave) => {
      const contadores = (
        window as Window & {
          __storageOperativo: { setItem: number; removeItem: number };
        }
      ).__storageOperativo;
      return { raw: localStorage.getItem(clave), ...contadores };
    }, caso.clave);

    expect(estado).toEqual({ raw, setItem: 0, removeItem: 0 });
  });
}
