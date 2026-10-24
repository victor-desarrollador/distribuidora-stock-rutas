// Bloque E / M-1: la frontera de escritura de catálogos relee la clave en el
// momento de la operación. La edición debe persistir con storage válido (o
// ausente), abortar si la clave se corrompe después del montaje y fallar sin
// alterar el estado React si setItem lanza. Raw corrupto nunca se sobrescribe.
//
// Productos y camiones ya no se escriben en localStorage: /productos y
// /camiones usan el catálogo de Supabase (tests/productos-catalogo.spec.ts y
// tests/camiones-catalogo.spec.ts). Queda clientes.
import { expect, test, type Page } from "@playwright/test";

const claves = {
  clientes: "distribuidora_clientes_demo_v2",
} as const;

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
