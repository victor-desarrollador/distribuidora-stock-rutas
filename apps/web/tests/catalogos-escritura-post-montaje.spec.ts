// Bloque E / M-1: la frontera de escritura de catálogos relee la clave en el
// momento de la operación. La edición debe persistir con storage válido (o
// ausente), abortar si la clave se corrompe después del montaje y fallar sin
// alterar el estado React si setItem lanza. Raw corrupto nunca se sobrescribe.
import { expect, test, type Page } from "@playwright/test";

const claves = {
  productos: "distribuidora_productos_demo_v4",
  camiones: "distribuidora_camiones_demo_v4",
  clientes: "distribuidora_clientes_demo_v2",
} as const;

const productoEdicion = {
  id: 7,
  nombre: "Yogur Edición E",
  categoria: "Lácteos",
  unidadMedida: "unidad",
  stock: 40,
  precio: 2300,
  stockMinimo: 5,
};

const camionEdicion = {
  id: 7,
  nombre: "Camión Edición E",
  patente: "ED999BB",
  marca: "Iveco",
  modelo: "Daily",
  estado: "disponible",
  observaciones: "",
};

const clienteEdicion = {
  id: 7,
  nombreComercio: "Almacén Edición E",
  titular: "Titular de prueba",
  telefono: "3815559999",
  direccion: "Calle de prueba",
  zona: "Centro",
  condicionPago: "contado",
  limiteCredito: 0,
  activo: true,
};

async function iniciar(
  page: Page,
  semillas: Record<string, string | null>
) {
  await page.addInitScript((datos) => {
    localStorage.setItem("distribuidora_sesion_demo_v1", "admin-demo");
    for (const [clave, valor] of Object.entries(datos.semillas)) {
      if (valor !== null) localStorage.setItem(clave, valor);
    }
  }, { semillas });
}

// Registra todos los diálogos nativos que abre la página (los guarda en Node
// y los cierra). El registro es del lado Node: durante un alert activo las
// evaluaciones en la página quedan bloqueadas hasta cerrar el diálogo.
function registrarDialogos(page: Page) {
  const mensajes: string[] = [];
  page.on("dialog", (dialogo) => {
    mensajes.push(dialogo.message());
    void dialogo.dismiss();
  });
  return mensajes;
}

const rawCorrupto = "{catalogo dañado después del montaje";

for (const caso of [
  {
    nombre: "Productos",
    clave: claves.productos,
    ruta: "/productos",
    semilla: productoEdicion,
    semillaClave: "distribuidora_productos_demo_v4",
    abrirEdicion: async (page: Page) => {
      await page
        .getByRole("button", { name: `Editar ${productoEdicion.nombre}` })
        .click();
    },
    textoExito: "Producto actualizado correctamente.",
    textoFallo: "No se pudo guardar el producto en este navegador.",
  },
  {
    nombre: "Camiones",
    clave: claves.camiones,
    ruta: "/camiones",
    semilla: camionEdicion,
    semillaClave: "distribuidora_camiones_demo_v4",
    abrirEdicion: async (page: Page) => {
      await page.getByRole("button", { name: "Editar" }).first().click();
    },
    textoExito: "Camión actualizado correctamente.",
    textoFallo: "No se pudo guardar el camión en este navegador.",
  },
  {
    nombre: "Clientes",
    clave: claves.clientes,
    ruta: "/clientes",
    semilla: clienteEdicion,
    semillaClave: "distribuidora_clientes_demo_v2",
    abrirEdicion: async (page: Page) => {
      await page.getByRole("button", { name: "Editar" }).first().click();
    },
    textoExito: "Cliente actualizado correctamente.",
    textoFallo: "No se pudo guardar el cliente en este navegador.",
  },
] as const) {
  test(`${caso.nombre}: edición válida persiste y corrupción posterior al montaje aborta con raw intacto`, async ({
    page,
  }) => {
    await iniciar(page, {
      [caso.semillaClave]: JSON.stringify([caso.semilla]),
    });
    const mensajes = registrarDialogos(page);
    await page.goto(caso.ruta);

    // Primera edición con storage válido: persiste y la UI muestra éxito.
    await caso.abrirEdicion(page);
    await page
      .getByRole("button", { name: "Guardar cambios", exact: true })
      .click();

    await expect(page.getByText(caso.textoExito, { exact: false })).toBeVisible();
    const rawValido = await page.evaluate(
      (clave) => localStorage.getItem(clave),
      caso.clave
    );
    expect(rawValido).toBe(JSON.stringify([caso.semilla]));

    // Corrupción aparecida después del montaje: la edición debe abortar.
    await page.evaluate(
      ({ clave, raw }) => localStorage.setItem(clave, raw),
      { clave: caso.clave, raw: rawCorrupto }
    );

    await caso.abrirEdicion(page);
    await page
      .getByRole("button", { name: "Guardar cambios", exact: true })
      .click();

    expect(
      mensajes.some((m) => m.includes(caso.textoFallo))
    ).toBe(true);

    // El raw corrupto queda intacto y la UI no informa éxito.
    const rawDespues = await page.evaluate(
      (clave) => localStorage.getItem(clave),
      caso.clave
    );
    expect(rawDespues).toBe(rawCorrupto);
    await expect(
      page.getByText(caso.textoExito, { exact: false })
    ).toHaveCount(0);
  });
}

test("Productos con storage ausente: el primer cambio se persiste", async ({
  page,
}) => {
  await iniciar(page, {});
  registrarDialogos(page);
  await page.goto("/productos");

  // Sin storage el catálogo parte de las semillas demo legítimas.
  await page.getByRole("button", { name: `Editar Yogur bebible 1 L` }).click();
  await page.getByRole("button", { name: "Guardar cambios", exact: true }).click();

  await expect(
    page.getByText("Producto actualizado correctamente.", { exact: false })
  ).toBeVisible();

  const raw = await page.evaluate(
    (clave) => localStorage.getItem(clave),
    claves.productos
  );
  expect(raw).not.toBeNull();

  const datos = JSON.parse(raw as string) as Array<{ nombre: string }>;
  expect(datos).toHaveLength(6);
});

test("Productos: si setItem lanza, el estado React no cambia ni se informa éxito", async ({
  page,
}) => {
  await page.addInitScript(
    ({ clave, producto }) => {
      localStorage.setItem("distribuidora_sesion_demo_v1", "admin-demo");
      localStorage.setItem(clave, JSON.stringify([producto]));
      const originalSetItem = Storage.prototype.setItem;
      Storage.prototype.setItem = function (key, value) {
        if (key === clave) {
          throw new Error("QuotaExceededError simulado");
        }
        return originalSetItem.call(this, key, value);
      };
    },
    { clave: claves.productos, producto: productoEdicion }
  );
  const mensajes = registrarDialogos(page);
  await page.goto("/productos");

  await page
    .getByRole("button", { name: `Editar ${productoEdicion.nombre}` })
    .click();
  await page
    .getByRole("button", { name: "Guardar cambios", exact: true })
    .click();

  // Damos un margen para que el diálogo se registre.
  await page.waitForTimeout(300);
  expect(
    mensajes.some((m) =>
      m.includes("No se pudo guardar el producto en este navegador.")
    )
  ).toBe(true);

  // La operación falló: la UI sigue mostrando el nombre original (el estado
  // no cambió) y ningún mensaje de éxito.
  await expect(
    page.getByText("Producto actualizado correctamente.", { exact: false })
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: `Editar ${productoEdicion.nombre}` })
  ).toBeVisible();
});
