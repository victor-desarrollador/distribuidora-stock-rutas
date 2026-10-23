// Bloque E / L-1: TOCTOU de la rendición en la ventana del confirm. El armado
// del cierre releía Ventas, Cobros y Movimientos solo ANTES del confirm; si
// algún ledger se corrompe exactamente mientras el usuario confirma, el cierre
// previo (obsoleto) igual se persistía. Ahora el cierre se "arma" dos veces
// (antes y después del confirm) y lo que se persiste es el armado final, con
// lecturas frescas: si algo falla, no se escribe nada.
import { expect, test, type Page } from "@playwright/test";

const claves = {
  productos: "distribuidora_productos_demo_v4",
  camiones: "distribuidora_camiones_demo_v4",
  clientes: "distribuidora_clientes_demo_v2",
  jornadas: "distribuidora_jornadas_demo_v4",
  ventas: "distribuidora_ventas_demo_v4",
  cobros: "distribuidora_cobros_demo_v4",
  movimientos: "distribuidora_movimientos_demo_v4",
  retornos: "distribuidora_retornos_demo_v4",
} as const;

const rawCorrupto = "{ventas dañadas en la ventana del confirm";

const producto = {
  id: 1,
  nombre: "Yogur bebible 1 L",
  categoria: "Lácteos",
  unidadMedida: "unidad",
  stock: 120,
  precio: 2300,
  stockMinimo: 20,
};

const camion = {
  id: 1,
  nombre: "Camión Rendición E",
  patente: "RE123AA",
  marca: "Iveco",
  modelo: "Daily",
  estado: "disponible",
  observaciones: "",
};

const cliente = {
  id: 1,
  nombreComercio: "Almacén Rendición E",
  titular: "Cliente de prueba",
  telefono: "3815550000",
  direccion: "Calle de prueba",
  zona: "Centro",
  condicionPago: "cuenta_corriente",
  limiteCredito: 200000,
  activo: true,
};

const jornadaAbierta = {
  id: "jornada-rendicion-e",
  camionId: 1,
  chofer: "Chofer Rendición E",
  zona: "Centro",
  fechaCreacion: "2026-10-22T08:00:00.000Z",
  fechaSalida: "2026-10-22T09:00:00.000Z",
  estado: "abierta",
  items: [
    {
      productoId: 1,
      nombreProducto: producto.nombre,
      unidadMedida: "unidad",
      cantidad: 10,
      precioReferencia: 2300,
    },
  ],
};

async function prepararStorage(page: Page) {
  await page.addInitScript(
    ({ clavesStorage, datos }) => {
      localStorage.setItem(
        clavesStorage.productos,
        JSON.stringify(datos.productos)
      );
      localStorage.setItem(
        clavesStorage.camiones,
        JSON.stringify(datos.camiones)
      );
      localStorage.setItem(
        clavesStorage.clientes,
        JSON.stringify(datos.clientes)
      );
      localStorage.setItem(
        clavesStorage.jornadas,
        JSON.stringify(datos.jornadas)
      );
      localStorage.setItem(clavesStorage.ventas, "[]");
      localStorage.setItem(clavesStorage.cobros, "[]");
      localStorage.setItem(clavesStorage.movimientos, "[]");
      localStorage.setItem(clavesStorage.retornos, "[]");
    },
    {
      clavesStorage: claves,
      datos: {
        productos: [producto],
        camiones: [camion],
        clientes: [cliente],
        jornadas: [jornadaAbierta],
      },
    }
  );
}

// Corrompe Ventas exactamente cuando la página llama a window.confirm: la
// revalidación final debe ver el storage dañado y abortar el cierre.
function corromperVentasEnConfirm(page: Page) {
  return page.addInitScript(
    ({ storageKey, raw }) => {
      const originalConfirm = window.confirm;
      window.confirm = function (mensaje) {
        localStorage.setItem(storageKey, raw);
        return originalConfirm.call(window, mensaje);
      };
    },
    { storageKey: claves.ventas, raw: rawCorrupto }
  );
}

async function leerRaw(page: Page, clave: string) {
  return page.evaluate(
    (storageKey) => localStorage.getItem(storageKey),
    clave
  );
}

// Acepta el siguiente window.confirm que la página abra.
function aceptarConfirm(page: Page) {
  page.once("dialog", (dialogo) => dialogo.accept());
}

test("Rendición: ventas corruptas en la ventana del confirm, el cierre no persiste", async ({
  page,
}) => {
  await prepararStorage(page);
  // El parche de window.confirm debe estar en el documento al montar: se
  // registra antes de la navegación.
  await corromperVentasEnConfirm(page);
  await page.goto("/rendicion");

  await page
    .getByLabel("Seleccionar jornada para rendición")
    .selectOption(jornadaAbierta.id);
  await page.getByRole("button", { name: "Completar con esperados" }).click();
  await page
    .getByLabel("Efectivo entregado por el repartidor *")
    .fill("0");

  const jornadasAntes = await leerRaw(page, claves.jornadas);

  const confirmar = page.getByRole("button", {
    name: "Confirmar cierre de jornada",
  });
  await expect(confirmar).toBeEnabled();

  aceptarConfirm(page);
  await confirmar.click();

  await expect(page.getByRole("alert")).toContainText(
    "No se puede cerrar"
  );

  // Raw intacto: la jornada sigue abierta y la corrupción queda tal cual.
  expect(await leerRaw(page, claves.jornadas)).toBe(jornadasAntes);
  expect(await leerRaw(page, claves.ventas)).toBe(rawCorrupto);
});

test("Rendición: cierre exitoso con el armado final (sin corrupción)", async ({
  page,
}) => {
  await prepararStorage(page);
  await page.goto("/rendicion");

  await page
    .getByLabel("Seleccionar jornada para rendición")
    .selectOption(jornadaAbierta.id);
  await page.getByRole("button", { name: "Completar con esperados" }).click();
  await page
    .getByLabel("Efectivo entregado por el repartidor *")
    .fill("0");

  const confirmar = page.getByRole("button", {
    name: "Confirmar cierre de jornada",
  });
  await expect(confirmar).toBeEnabled();

  aceptarConfirm(page);
  await confirmar.click();

  await expect(page.getByRole("status")).toContainText(
    "Jornada cerrada correctamente."
  );

  const jornadas = JSON.parse(
    String(await leerRaw(page, claves.jornadas))
  ) as Array<{
    id: string;
    estado: string;
    cierre: {
      efectivoEntregado: number;
      conteos: Record<string, number>;
    };
  }>;

  expect(jornadas).toHaveLength(1);
  expect(jornadas[0].estado).toBe("cerrada");
  expect(jornadas[0].cierre.efectivoEntregado).toBe(0);
  expect(jornadas[0].cierre.conteos).toEqual({ "1": 10 });
});
