// ADR-005 D-R4 (Slice B1): las siete claves operativas `_demo_v4` (modelo de
// medias piezas) quedan fuera del modelo nuevo. Con sólo datos v4 en el
// navegador, la demo arranca con los fixtures nuevos (gramos enteros), no lee
// ni reinterpreta v4 (un `9` legacy en medias piezas nunca aparece como 9 g,
// 0,009 kg, stock 9 ni mínimo 9), deja las siete v4 byte a byte iguales y no
// crea claves v5 sin una acción del usuario que guarde datos.
import { expect, test, type Page } from "@playwright/test";

const clavesV4 = {
  productos: "distribuidora_productos_demo_v4",
  jornadas: "distribuidora_jornadas_demo_v4",
  ventas: "distribuidora_ventas_demo_v4",
  cobros: "distribuidora_cobros_demo_v4",
  movimientos: "distribuidora_movimientos_demo_v4",
  retornos: "distribuidora_retornos_demo_v4",
  camiones: "distribuidora_camiones_demo_v4",
} as const;

const clavesV5 = Object.values(clavesV4).map((clave) =>
  clave.replace(/_demo_v4$/, "_demo_v5")
);

// Payloads válidos en el modelo v4: el fiambre en medias piezas con stock 9,
// mínimo 9 y cantidades 9. Si algo los leyera, aparecerían en pantalla (o
// como «dañados», porque `pieza` no es válida en v5).
const legado = {
  productos: [
    {
      id: 3,
      nombre: "Jamón legado v4",
      categoria: "Fiambres",
      unidadMedida: "pieza",
      stock: 9,
      precio: 12500,
      stockMinimo: 9,
    },
  ],
  camiones: [
    {
      id: 1,
      nombre: "Camión legado v4",
      patente: "LG999VV",
      marca: "Iveco",
      modelo: "Daily",
      estado: "disponible",
      observaciones: "",
    },
  ],
  jornadas: [
    {
      id: "jornada-legado-v4",
      camionId: 1,
      chofer: "Chofer legado v4",
      zona: "Zona legado v4",
      fechaCreacion: "2026-10-20T08:00:00.000Z",
      fechaSalida: "2026-10-20T09:00:00.000Z",
      estado: "abierta",
      items: [
        {
          productoId: 3,
          nombreProducto: "Jamón legado v4",
          unidadMedida: "pieza",
          cantidad: 9,
          precioReferencia: 12500,
        },
      ],
    },
  ],
  ventas: [
    {
      id: "venta-legado-v4",
      jornadaId: "jornada-legado-v4",
      clienteId: 1,
      fecha: "2026-10-20T10:00:00.000Z",
      items: [
        {
          productoId: 3,
          nombreProducto: "Jamón legado v4",
          unidadMedida: "pieza",
          cantidad: 9,
          precioUnitario: 12500,
          precioMediaPieza: 6250,
          subtotal: 56250,
        },
      ],
      total: 56250,
    },
  ],
  cobros: [
    {
      id: "cobro-legado-v4",
      ventaId: "venta-legado-v4",
      jornadaId: "jornada-legado-v4",
      medio: "efectivo",
      importe: 56250,
    },
  ],
  movimientos: [
    {
      id: "movimiento-legado-v4",
      jornadaId: "jornada-legado-v4",
      tipo: "devolucion",
      producto: {
        productoId: 3,
        nombreProducto: "Jamón legado v4",
        unidadMedida: "pieza",
        cantidad: 9,
      },
    },
  ],
  retornos: [
    {
      id: "retorno-legado-v4",
      jornadaId: "jornada-legado-v4",
      items: [
        {
          productoId: 3,
          nombreProducto: "Jamón legado v4",
          unidadMedida: "pieza",
          cantidadContada: 9,
          cantidadAprobada: 9,
        },
      ],
    },
  ],
} as const;

const rawV4: Record<string, string> = Object.fromEntries(
  (Object.keys(clavesV4) as (keyof typeof clavesV4)[]).map((nombre) => [
    clavesV4[nombre],
    JSON.stringify(legado[nombre]),
  ])
);

async function sembrarSoloV4(page: Page) {
  await page.addInitScript(
    ({ raw, vigiladas }) => {
      // Siembra única por pestaña: las navegaciones siguientes no reescriben.
      if (sessionStorage.getItem("__d_r4_sembrado") === null) {
        for (const [clave, valor] of Object.entries(raw)) {
          localStorage.setItem(clave, valor);
        }
        sessionStorage.setItem("__d_r4_sembrado", "1");
      }

      // Cuenta escrituras y borrados de la app sobre v4 y v5.
      const previos = sessionStorage.getItem("__d_r4_contadores");
      const contadores: { setItem: string[]; removeItem: string[] } = previos
        ? JSON.parse(previos)
        : { setItem: [], removeItem: [] };
      const guardar = () =>
        sessionStorage.setItem("__d_r4_contadores", JSON.stringify(contadores));
      const originalSetItem = Storage.prototype.setItem;
      const originalRemoveItem = Storage.prototype.removeItem;
      Storage.prototype.setItem = function (key, value) {
        const resultado = originalSetItem.call(this, key, value);
        if (vigiladas.includes(key)) {
          contadores.setItem.push(key);
          guardar();
        }
        return resultado;
      };
      Storage.prototype.removeItem = function (key) {
        const resultado = originalRemoveItem.call(this, key);
        if (vigiladas.includes(key)) {
          contadores.removeItem.push(key);
          guardar();
        }
        return resultado;
      };
      Storage.prototype.clear = function () {
        contadores.removeItem.push("__clear__");
        guardar();
        throw new Error("clear() no permitido en D-R4");
      };
    },
    { raw: rawV4, vigiladas: [...Object.keys(rawV4), ...clavesV5] }
  );
}

async function estadoStorage(page: Page) {
  return page.evaluate(
    ({ v4, v5 }) => ({
      v4: Object.fromEntries(v4.map((c) => [c, localStorage.getItem(c)])),
      v5: Object.fromEntries(v5.map((c) => [c, localStorage.getItem(c)])),
      contadores: JSON.parse(
        sessionStorage.getItem("__d_r4_contadores") ??
          '{"setItem":[],"removeItem":[]}'
      ),
    }),
    { v4: Object.keys(rawV4), v5: clavesV5 }
  );
}

async function sinRastrosLegacy(page: Page) {
  const main = page.locator("body");
  await expect(main).not.toContainText(/legado v4/i);
  await expect(main).not.toContainText(/\bpieza/i);
  await expect(main).not.toContainText(/\b9 g\b/);
  await expect(main).not.toContainText("0,009 kg");
  await expect(main).not.toContainText(/Disponible: 9\b/);
  await expect(main).not.toContainText(/\b9 un\./);
  await expect(main).not.toContainText(/dañad/i);
}

const rutas = [
  "/jornadas",
  "/autoventa",
  "/movimientos",
  "/retornos",
  "/rendicion",
  "/cuentas",
  "/configuracion-demo",
] as const;

test("D-R4: con sólo claves v4, ninguna pantalla lee ni reinterpreta el legado", async ({
  page,
}) => {
  await sembrarSoloV4(page);

  for (const ruta of rutas) {
    await page.goto(ruta);
    await expect(page.locator("main, body").first()).toBeVisible();
    await sinRastrosLegacy(page);
  }

  const estado = await estadoStorage(page);
  expect(estado.v4).toEqual(rawV4);
  for (const clave of clavesV5) expect(estado.v5[clave]).toBeNull();
  expect(estado.contadores).toEqual({ setItem: [], removeItem: [] });
});

test("D-R4: la preparación muestra los fixtures nuevos en kg y unidades, no el 9 legacy", async ({
  page,
}) => {
  await sembrarSoloV4(page);
  await page.goto("/jornadas");

  // Abrir el formulario no guarda nada.
  await page.getByRole("button", { name: "Nueva jornada" }).click();
  await expect(page.getByText("Preparar carga del camión")).toBeVisible();

  // Fixtures nuevos en gramos enteros, presentados en kg con 3 decimales.
  await expect(page.getByText("Disponible: 7,680 kg")).toBeVisible();
  await expect(page.getByText("Disponible: 18,000 kg")).toBeVisible();
  await expect(page.getByText("Disponible: 2,500 kg")).toBeVisible();
  // Lácteos en unidades enteras.
  await expect(page.getByText("Disponible: 120 un")).toBeVisible();
  // Camiones de los fixtures, no el legado.
  await expect(
    page.getByRole("option", { name: /Camión 01/ })
  ).toHaveCount(1);
  await expect(page.getByRole("option", { name: /legado v4/ })).toHaveCount(0);

  await sinRastrosLegacy(page);

  const estado = await estadoStorage(page);
  expect(estado.v4).toEqual(rawV4);
  for (const clave of clavesV5) expect(estado.v5[clave]).toBeNull();
  expect(estado.contadores).toEqual({ setItem: [], removeItem: [] });
});

test("D-R4: el respaldo de la demo no copia las claves v4", async ({ page }) => {
  await sembrarSoloV4(page);
  await page.goto("/configuracion-demo");

  const descarga = page.waitForEvent("download");
  await page.getByRole("button", { name: /respaldo/i }).first().click();
  const archivo = await descarga;
  const contenido = await (await archivo.createReadStream()).toArray();
  const texto = Buffer.concat(contenido).toString("utf8");

  expect(texto).not.toContain("_demo_v4");
  expect(texto).not.toContain("legado v4");

  const estado = await estadoStorage(page);
  expect(estado.v4).toEqual(rawV4);
  for (const clave of clavesV5) expect(estado.v5[clave]).toBeNull();
  expect(estado.contadores).toEqual({ setItem: [], removeItem: [] });
});
