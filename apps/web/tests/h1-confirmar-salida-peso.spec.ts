// H-1 (auditoría de 8ff5bef): una jornada v5 estructuralmente válida con
// ítems `peso` no puede pasar de `preparacion` a `abierta` antes de B2. La UI
// bloquea «Confirmar salida» y la frontera persistida rechaza igual, con la
// jornada leída al momento de persistir (no con el snapshot del render).
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

test("H-1: una jornada v5 en preparación con ítem peso no puede confirmar la salida", async ({
  page,
}) => {
  await sembrar(page, [jornadaConPeso]);
  const rawSembrado = JSON.stringify([jornadaConPeso]);

  await page.goto("/jornadas");

  const card = tarjeta(page);
  await expect(card).toContainText("En preparación");
  await expect(card.getByText(MENSAJE_PESO_NO_OPERABLE)).toBeVisible();
  await expect(
    card.getByRole("button", { name: "Confirmar salida" })
  ).toBeDisabled();
  // No es storage corrupto: no hay aviso de datos dañados.
  await expect(page.getByText(/dañad/i)).toHaveCount(0);

  const final = await estado(page);
  expect(final).toEqual({ raw: rawSembrado, setItemJornadas: 0 });
  const [guardada] = JSON.parse(final.raw as string);
  expect(guardada.estado).toBe("preparacion");
  expect(guardada.fechaSalida).toBeNull();
});

test("H-1: si la jornada pasa a tener peso después del montaje, la frontera rechaza la salida", async ({
  page,
}) => {
  await sembrar(page, [jornadaUnidad]);
  await page.goto("/jornadas");

  const card = tarjeta(page);
  const boton = card.getByRole("button", { name: "Confirmar salida" });
  // El snapshot del render es sólo `unidad`: el botón está habilitado.
  await expect(boton).toBeEnabled();

  // Mutación entre el montaje y el clic, con el setItem original.
  const rawMutado = JSON.stringify([jornadaConPeso]);
  await page.evaluate(
    ({ clave, raw }) => {
      const h1 = (
        window as Window & {
          __h1: { setItemOriginal: (k: string, v: string) => void };
        }
      ).__h1;
      h1.setItemOriginal.call(localStorage, clave, raw);
    },
    { clave: claves.jornadas, raw: rawMutado }
  );

  await boton.click();

  await expect(page.getByRole("alert")).toHaveText(MENSAJE_PESO_NO_OPERABLE);
  await expect(page.getByText(/Salida confirmada/)).toHaveCount(0);
  // El estado de React no avanzó: la tarjeta sigue en preparación.
  await expect(card).toContainText("En preparación");
  await expect(card).not.toContainText("Reparto iniciado");
  await expect(boton).toBeVisible();

  expect(await estado(page)).toEqual({ raw: rawMutado, setItemJornadas: 0 });
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
