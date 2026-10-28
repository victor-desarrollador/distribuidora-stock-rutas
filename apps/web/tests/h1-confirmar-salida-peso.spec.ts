// H-1 (auditoría de 8ff5bef) fue una protección de B1: una jornada v5 con
// ítems `peso` no podía pasar de `preparacion` a `abierta`. B2 la INVIERTE
// deliberadamente (decisión humana P-B2-2): la salida con peso está
// permitida y el cierre sigue bloqueado hasta B4. Los casos de B1 se
// conservan reescritos con la expectativa de B2, no se borran.
// No es un caso D-R4: sólo se usan claves `_demo_v5`.
import { expect, test, type Page } from "@playwright/test";

import { MENSAJE_PESO_NO_OPERABLE } from "../src/domain/productos";

const claves = {
  productos: "distribuidora_productos_demo_v5",
  camiones: "distribuidora_camiones_demo_v5",
  jornadas: "distribuidora_jornadas_demo_v5",
} as const;

const productos = [
  {
    id: 1,
    nombre: "Yogur H1",
    categoria: "Lácteos",
    unidadMedida: "unidad",
    stock: 120,
    precio: 2300,
    stockMinimo: 20,
  },
  {
    id: 4,
    nombre: "Jamón H1",
    categoria: "Fiambres",
    unidadMedida: "peso",
    stock: 18000,
    precio: 12500,
    stockMinimo: 5000,
  },
];

const camiones = [
  {
    id: 1,
    nombre: "Camión H1",
    patente: "HU111AA",
    marca: "Iveco",
    modelo: "Daily",
    estado: "disponible",
    observaciones: "",
  },
];

const itemUnidad = {
  productoId: 1,
  nombreProducto: "Yogur H1",
  unidadMedida: "unidad",
  cantidad: 10,
  precioReferencia: 2300,
};

const itemPeso = {
  productoId: 4,
  nombreProducto: "Jamón H1",
  unidadMedida: "peso",
  cantidad: 18000,
  precioReferencia: 12500,
};

const jornadaUnidad = {
  id: "jornada-h1",
  camionId: 1,
  chofer: "Chofer H1",
  zona: "Centro",
  fechaCreacion: "2026-10-27T08:00:00.000Z",
  fechaSalida: null,
  estado: "preparacion",
  items: [itemUnidad],
};

const jornadaConPeso = { ...jornadaUnidad, items: [itemUnidad, itemPeso] };

type Contadores = { setItemJornadas: number };

// Siembra al cargar la página (cada test navega una sola vez) y cuenta las
// escrituras de la app sobre jornadas. La reescritura del test usa el setItem
// original y no se cuenta.
async function sembrar(page: Page, jornadas: unknown[]) {
  await page.addInitScript(
    ({ c, datos }) => {
      localStorage.setItem(c.productos, JSON.stringify(datos.productos));
      localStorage.setItem(c.camiones, JSON.stringify(datos.camiones));
      localStorage.setItem(c.jornadas, JSON.stringify(datos.jornadas));

      const original = Storage.prototype.setItem;
      const contadores = { setItemJornadas: 0 };
      Object.defineProperty(window, "__h1", {
        value: { contadores, setItemOriginal: original },
        configurable: true,
      });
      Storage.prototype.setItem = function (key, value) {
        if (key === c.jornadas) contadores.setItemJornadas += 1;
        return original.call(this, key, value);
      };
    },
    { c: claves, datos: { productos, camiones, jornadas } }
  );
}

async function estado(page: Page) {
  return page.evaluate((clave) => {
    const h1 = (window as Window & { __h1: { contadores: Contadores } }).__h1;
    return { raw: localStorage.getItem(clave), ...h1.contadores };
  }, claves.jornadas);
}

function tarjeta(page: Page) {
  return page.locator("article").filter({ hasText: "Chofer H1" });
}

// Antes (B1): «una jornada v5 en preparación con ítem peso no puede confirmar
// la salida» (mensaje visible y botón deshabilitado).
test("H-1 invertido (B2): una jornada v5 en preparación con ítem peso confirma la salida", async ({
  page,
}) => {
  await sembrar(page, [jornadaConPeso]);
  await page.goto("/jornadas");

  const card = tarjeta(page);
  const boton = card.getByRole("button", { name: "Confirmar salida" });
  await expect(card).toContainText("En preparación");
  await expect(card).toContainText("18,000 kg");
  await expect(page.getByText(MENSAJE_PESO_NO_OPERABLE)).toHaveCount(0);
  await expect(boton).toBeEnabled();

  await boton.click();

  await expect(page.getByRole("status")).toHaveText(
    "Salida confirmada: Camión H1."
  );
  await expect(card).toContainText("Reparto iniciado");

  const final = await estado(page);
  expect(final.setItemJornadas).toBe(1);
  const [guardada] = JSON.parse(final.raw as string);
  expect(guardada.estado).toBe("abierta");
  expect(typeof guardada.fechaSalida).toBe("string");
  // Los gramos de los ítems se conservan exactos.
  expect(guardada.items).toEqual(jornadaConPeso.items);
});

// Antes (B1): «si la jornada pasa a tener peso después del montaje, la
// frontera rechaza la salida».
test("H-1 invertido (B2): si después del montaje la jornada vigente pasa a tener peso válido, la frontera acepta la salida", async ({
  page,
}) => {
  await sembrar(page, [jornadaUnidad]);
  await page.goto("/jornadas");

  const card = tarjeta(page);
  const boton = card.getByRole("button", { name: "Confirmar salida" });
  await expect(boton).toBeEnabled();

  // Mutación entre el montaje y el clic, con el setItem original: la jornada
  // sigue en `preparacion` y ahora carga además 18000 g de jamón.
  await page.evaluate(
    ({ clave, raw }) => {
      const h1 = (
        window as Window & {
          __h1: { setItemOriginal: (k: string, v: string) => void };
        }
      ).__h1;
      h1.setItemOriginal.call(localStorage, clave, raw);
    },
    { clave: claves.jornadas, raw: JSON.stringify([jornadaConPeso]) }
  );

  await boton.click();

  await expect(page.getByRole("status")).toHaveText(
    "Salida confirmada: Camión H1."
  );
  await expect(page.getByRole("alert")).toHaveCount(0);
  await expect(page.getByText(MENSAJE_PESO_NO_OPERABLE)).toHaveCount(0);
  // React refleja la jornada vigente persistida: abierta y con el peso.
  await expect(card).toContainText("Reparto iniciado");
  await expect(card).toContainText("18,000 kg");

  const final = await estado(page);
  expect(final.setItemJornadas).toBe(1);
  const [guardada] = JSON.parse(final.raw as string);
  expect(guardada.estado).toBe("abierta");
  expect(guardada.items).toEqual(jornadaConPeso.items);
});

test("H-1 regresión: una jornada sólo unidad confirma la salida como antes", async ({
  page,
}) => {
  await sembrar(page, [jornadaUnidad]);
  await page.goto("/jornadas");

  const card = tarjeta(page);
  const boton = card.getByRole("button", { name: "Confirmar salida" });
  await expect(card.getByText(MENSAJE_PESO_NO_OPERABLE)).toHaveCount(0);
  await expect(boton).toBeEnabled();

  await boton.click();

  await expect(page.getByRole("status")).toHaveText(
    "Salida confirmada: Camión H1."
  );
  await expect(card).toContainText("Reparto iniciado");

  const final = await estado(page);
  expect(final.setItemJornadas).toBe(1);
  const [guardada] = JSON.parse(final.raw as string);
  expect(guardada.estado).toBe("abierta");
  expect(typeof guardada.fechaSalida).toBe("string");
  expect(Number.isNaN(Date.parse(guardada.fechaSalida))).toBe(false);
});
