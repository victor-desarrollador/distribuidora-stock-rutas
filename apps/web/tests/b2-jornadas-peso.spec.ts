// B2 (ADR-005): Jornadas con productos `peso` desde la UI real. La cantidad
// se ingresa en kg con coma y hasta 3 decimales y se persiste en gramos
// enteros. Una carga con peso no se valoriza (P-B2-1: «Sin valorizar», sin
// subtotal parcial). La salida está permitida y el cierre/rendición con peso
// sigue bloqueado hasta B4 (P-B2-2). Sólo claves `_demo_v5`.
import { expect, test, type Page } from "@playwright/test";

import { MENSAJE_PESO_NO_OPERABLE } from "../src/domain/productos";

const claves = {
  productos: "distribuidora_productos_demo_v5",
  camiones: "distribuidora_camiones_demo_v5",
  jornadas: "distribuidora_jornadas_demo_v5",
  retornos: "distribuidora_retornos_demo_v5",
  ventas: "distribuidora_ventas_demo_v5",
  cobros: "distribuidora_cobros_demo_v5",
  movimientos: "distribuidora_movimientos_demo_v5",
} as const;

const yogur = {
  id: 1,
  nombre: "Yogur B2",
  categoria: "Lácteos",
  unidadMedida: "unidad",
  stock: 120,
  precio: 2300,
  stockMinimo: 20,
};

const jamon = {
  id: 4,
  nombre: "Jamón B2",
  categoria: "Fiambres",
  unidadMedida: "peso",
  stock: 18000,
  precio: 12500,
  stockMinimo: 5000,
};

const camiones = [
  {
    id: 1,
    nombre: "Camión B2",
    patente: "BD222AA",
    marca: "Iveco",
    modelo: "Daily",
    estado: "disponible",
    observaciones: "",
  },
];

type Jornada = {
  id: string;
  estado: string;
  fechaSalida: string | null;
  items: Array<{ productoId: number; unidadMedida: string; cantidad: number }>;
};

// Siembra al cargar la página y cuenta las escrituras de la app sobre jornadas.
async function sembrar(page: Page) {
  await page.addInitScript(
    ({ c, datos }) => {
      if (sessionStorage.getItem("__b2_sembrado") === null) {
        localStorage.setItem(c.productos, JSON.stringify(datos.productos));
        localStorage.setItem(c.camiones, JSON.stringify(datos.camiones));
        localStorage.setItem(c.jornadas, "[]");
        localStorage.setItem(c.retornos, "[]");
        localStorage.setItem(c.ventas, "[]");
        localStorage.setItem(c.cobros, "[]");
        localStorage.setItem(c.movimientos, "[]");
        sessionStorage.setItem("__b2_sembrado", "1");
        sessionStorage.setItem("__b2_set_jornadas", "0");
      }
      const original = Storage.prototype.setItem;
      Storage.prototype.setItem = function (key, value) {
        if (key === c.jornadas) {
          const n = Number(sessionStorage.getItem("__b2_set_jornadas") ?? "0");
          original.call(sessionStorage, "__b2_set_jornadas", String(n + 1));
        }
        return original.call(this, key, value);
      };
    },
    { c: claves, datos: { productos: [yogur, jamon], camiones } }
  );
}

async function jornadasGuardadas(page: Page): Promise<Jornada[]> {
  return JSON.parse(
    String(await page.evaluate((c) => localStorage.getItem(c), claves.jornadas))
  );
}

async function escriturasJornadas(page: Page): Promise<number> {
  return Number(
    await page.evaluate(() => sessionStorage.getItem("__b2_set_jornadas"))
  );
}

async function abrirFormulario(page: Page) {
  await page.getByRole("button", { name: "Nueva jornada" }).click();
  await page.getByLabel("Camión *").selectOption("1");
  await page.getByLabel("Chofer *").fill("Chofer B2");
  await page.getByLabel("Zona *").fill("Centro");
}

const resumen = (page: Page) =>
  page.getByText("Valor estimado de la carga").locator("..");

test("B2 Jornadas: 1,250 kg se guarda como 1250 g, sale a reparto y la rendición con peso sigue bloqueada (B4)", async ({
  page,
}) => {
  await sembrar(page);
  await page.goto("/jornadas");
  await abrirFormulario(page);

  await expect(page.getByText("Disponible: 18,000 kg")).toBeVisible();
  await page.getByLabel("Cantidad de Jamón B2 en kg").fill("1,250");
  await expect(resumen(page)).toContainText("Sin valorizar");
  await page.getByRole("button", { name: "Guardar preparación" }).click();

  await expect(page.getByRole("status")).toHaveText(
    "Carga preparada correctamente."
  );
  const [preparada] = await jornadasGuardadas(page);
  expect(preparada.estado).toBe("preparacion");
  expect(preparada.items).toEqual([
    expect.objectContaining({ productoId: 4, unidadMedida: "peso", cantidad: 1250 }),
  ]);

  const card = page.locator("article").filter({ hasText: "Chofer B2" });
  await expect(card).toContainText("1,250 kg");
  await expect(card).toContainText("Sin valorizar");

  await card.getByRole("button", { name: "Confirmar salida" }).click();
  await expect(page.getByRole("status")).toHaveText(
    "Salida confirmada: Camión B2."
  );
  const [abierta] = await jornadasGuardadas(page);
  expect(abierta.estado).toBe("abierta");
  expect(abierta.items[0].cantidad).toBe(1250);

  // Cierre con peso: bloqueado hasta B4, sin escribir.
  const antes = await escriturasJornadas(page);
  await page.goto("/rendicion");
  await page
    .getByLabel("Seleccionar jornada para rendición")
    .selectOption(abierta.id);
  await expect(
    page.getByRole("alert").filter({ hasText: MENSAJE_PESO_NO_OPERABLE })
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Confirmar cierre de jornada" })
  ).toBeDisabled();
  expect(await escriturasJornadas(page)).toBe(antes);
  expect((await jornadasGuardadas(page))[0].estado).toBe("abierta");
});

test("B2 Jornadas: una jornada mixta guarda unidades y gramos y no muestra subtotal parcial", async ({
  page,
}) => {
  await sembrar(page);
  await page.goto("/jornadas");
  await abrirFormulario(page);

  // Sólo unidad: se valoriza como antes.
  await page.getByLabel("Cantidad de Yogur B2", { exact: true }).fill("3");
  await expect(resumen(page)).not.toContainText("Sin valorizar");

  // Con peso: «Sin valorizar», sin el subtotal del yogur.
  await page.getByLabel("Cantidad de Jamón B2 en kg").fill("2,680");
  await expect(resumen(page)).toContainText("Sin valorizar");
  await expect(resumen(page)).not.toContainText("$");

  await page.getByRole("button", { name: "Guardar preparación" }).click();
  await expect(page.getByRole("status")).toHaveText(
    "Carga preparada correctamente."
  );

  const [jornada] = await jornadasGuardadas(page);
  expect(jornada.items).toEqual([
    expect.objectContaining({ productoId: 1, unidadMedida: "unidad", cantidad: 3 }),
    expect.objectContaining({ productoId: 4, unidadMedida: "peso", cantidad: 2680 }),
  ]);

  const card = page.locator("article").filter({ hasText: "Chofer B2" });
  await expect(card).toContainText("3 un.");
  await expect(card).toContainText("2,680 kg");
  await expect(card).toContainText("Sin valorizar");
  await expect(card).not.toContainText("$");
});

test("B2 Jornadas: exceder el disponible por 1 g o usar punto decimal se rechaza sin escribir", async ({
  page,
}) => {
  await sembrar(page);
  await page.goto("/jornadas");
  await abrirFormulario(page);
  const escriturasIniciales = await escriturasJornadas(page);

  // 18000 g disponibles: 18,001 kg excede por 1 g.
  await page.getByLabel("Cantidad de Jamón B2 en kg").fill("18,001");
  await page.getByRole("button", { name: "Guardar preparación" }).click();
  await expect(page.getByRole("alert")).toHaveText(
    "No hay stock suficiente de Jamón B2."
  );

  // Punto decimal: rechazado antes de llegar a la frontera.
  await page.getByLabel("Cantidad de Jamón B2 en kg").fill("1.250");
  await page.getByRole("button", { name: "Guardar preparación" }).click();
  await expect(page.getByRole("alert")).toContainText(
    "Cantidad inválida: Jamón B2."
  );

  expect(await escriturasJornadas(page)).toBe(escriturasIniciales);
  expect(await jornadasGuardadas(page)).toEqual([]);

  // El límite exacto sí se acepta.
  await page.getByLabel("Cantidad de Jamón B2 en kg").fill("18,000");
  await page.getByRole("button", { name: "Guardar preparación" }).click();
  await expect(page.getByRole("status")).toHaveText(
    "Carga preparada correctamente."
  );
  expect((await jornadasGuardadas(page))[0].items[0].cantidad).toBe(18000);
});
