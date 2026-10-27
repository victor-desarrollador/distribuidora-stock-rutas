// Bloque E / M-3: TOCTOU del stock en la preparación de cargas. Jornadas y
// Retornos son dependencias mutables: el snapshot que ve el render de
// /jornadas en el montaje puede quedar desactualizado. Al guardar la
// preparación, la frontera relee AMBOS ledgers discriminadamente, calcula el
// stock reservado con esas lecturas frescas y aborta sin escribir si el
// storage está corrupto o no alcanza el stock; el raw queda intacto.
import { expect, test, type Page } from "@playwright/test";

const claves = {
  productos: "distribuidora_productos_demo_v5",
  camiones: "distribuidora_camiones_demo_v5",
  clientes: "distribuidora_clientes_demo_v2",
  jornadas: "distribuidora_jornadas_demo_v5",
  retornos: "distribuidora_retornos_demo_v5",
} as const;

const rawCorrupto = "{jornadas dañadas después del montaje";

const producto = {
  id: 1,
  nombre: "Yogur Preparación E",
  categoria: "Lácteos",
  unidadMedida: "unidad",
  stock: 120,
  precio: 2300,
  stockMinimo: 20,
};

const camionA = {
  id: 1,
  nombre: "Camión Preparación A",
  patente: "PR01AA",
  marca: "Iveco",
  modelo: "Daily",
  estado: "disponible",
  observaciones: "",
};

const camionB = {
  id: 2,
  nombre: "Camión Preparación B",
  patente: "PR02BB",
  marca: "Mercedes-Benz",
  modelo: "Sprinter",
  estado: "disponible",
  observaciones: "",
};

const itemCargaDe = (cantidad: number) => ({
  productoId: 1,
  nombreProducto: producto.nombre,
  unidadMedida: "unidad",
  cantidad,
  precioReferencia: producto.precio,
});

// Jornada previa del camión A en preparación (reserva las cantidades que
// dice el storage en ese momento).
const jornadaPreviaDe = (cantidad: number) => ({
  id: "jornada-previa",
  camionId: 1,
  chofer: "Chofer Preparación E",
  zona: "Centro",
  fechaCreacion: "2026-10-22T08:00:00.000Z",
  fechaSalida: null,
  estado: "preparacion",
  items: [itemCargaDe(cantidad)],
});

async function prepararStorage(page: Page, cantidadPrevia: number) {
  await page.addInitScript(
    ({ clavesStorage, productoIJ, camionesIJ, jornadaIJ }) => {
      localStorage.setItem(
        clavesStorage.productos,
        JSON.stringify([productoIJ])
      );
      localStorage.setItem(
        clavesStorage.camiones,
        JSON.stringify(camionesIJ)
      );
      localStorage.setItem(clavesStorage.clientes, "[]");
      localStorage.setItem(
        clavesStorage.jornadas,
        JSON.stringify([jornadaIJ])
      );
      localStorage.setItem(clavesStorage.retornos, "[]");
    },
    {
      clavesStorage: claves,
      productoIJ: producto,
      camionesIJ: [camionA, camionB],
      jornadaIJ: jornadaPreviaDe(cantidadPrevia),
    }
  );
}

// Completa el formulario de preparación del camión B con la carga indicada.
async function completarFormulario(
  page: Page,
  cantidad: number
) {
  await page.getByRole("button", { name: "Nueva jornada" }).click();
  await page.getByLabel("Camión *").selectOption("2");
  await page.getByLabel("Chofer *").fill("Chofer Nuevo E");
  await page.getByLabel("Zona *").fill("Sur");
  await page
    .getByLabel(`Cantidad de ${producto.nombre}`)
    .fill(String(cantidad));
}

// Reescribe una clave de storage desde la ventana de la página (el render de
// React no se entera: su estado sigue viendo el seed del montaje).
async function reescribir(page: Page, clave: string, raw: string) {
  await page.evaluate(
    ({ storageKey, valor }) => localStorage.setItem(storageKey, valor),
    { storageKey: clave, valor: raw }
  );
}

test("Preparación: la carga respeta lo reservado leído en el momento del guardado", async ({
  page,
}) => {
  await prepararStorage(page, 10);
  await page.goto("/jornadas");
  await completarFormulario(page, 100);

  await page
    .getByRole("button", { name: "Guardar preparación" })
    .click();

  await expect(page.getByRole("status")).toContainText(
    "Carga preparada correctamente."
  );

  const jornadas = JSON.parse(
    String(
      await page.evaluate((c) => localStorage.getItem(c), claves.jornadas)
    )
  ) as Array<{ id: string; estado: string; items: Array<{ cantidad: number }> }>;

  expect(jornadas).toHaveLength(2);
  const nueva = jornadas.find((j) => j.id !== "jornada-previa");
  expect(nueva?.estado).toBe("preparacion");
  expect(nueva?.items[0].cantidad).toBe(100);
});

test("Preparación: una jornada previa con más carga (reída al guardar) agota el stock, la preparación aborta", async ({
  page,
}) => {
  await prepararStorage(page, 10);
  await page.goto("/jornadas");
  await completarFormulario(page, 100);

  // La jornada previa ahora reserva 110 (el render sigue viendo 10). Con la
  // lectura fresca: 120 - 110 = 10 disponibles < 100 pedidos.
  const rawConMasCarga = JSON.stringify([jornadaPreviaDe(110)]);
  await reescribir(page, claves.jornadas, rawConMasCarga);

  await page
    .getByRole("button", { name: "Guardar preparación" })
    .click();

  await expect(page.getByRole("alert")).toContainText(
    "No hay stock suficiente de Yogur Preparación E."
  );

  // Raw intacto: la preparación abortada no agregó nada.
  expect(
    await page.evaluate(
      (c) => localStorage.getItem(c),
      claves.jornadas
    )
  ).toBe(rawConMasCarga);
});

test("Preparación: jornadas corruptas al guardar, la frontera aborta sin escribir", async ({
  page,
}) => {
  await prepararStorage(page, 10);
  await page.goto("/jornadas");
  await completarFormulario(page, 100);

  // El ledger de jornadas se corrompe mientras la carga está en el
  // formulario: el guardado no debe reinterpretarlo como vacío ni escribir.
  await reescribir(page, claves.jornadas, rawCorrupto);

  await page
    .getByRole("button", { name: "Guardar preparación" })
    .click();

  await expect(page.getByRole("alert")).toContainText(
    "No se puede guardar la preparación"
  );

  expect(
    await page.evaluate(
      (c) => localStorage.getItem(c),
      claves.jornadas
    )
  ).toBe(rawCorrupto);
});
