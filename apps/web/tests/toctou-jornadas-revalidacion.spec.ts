// Bloque E / M-2: TOCTOU de la Jornada vigente. Jornadas es una dependencia
// mutable: desde el montaje hasta el momento de persistir puede corromperse,
// desaparecer, cerrarse o cambiar su camión. Las acciones reales de
// Autoventa, Movimientos, Cobros y Retornos releen la Jornada justo antes de
// persistir y abortan; ningún ledger destino se altera y el raw queda intacto.
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

const rawCorrupto = "{jornadas dañadas después del montaje";

const producto = {
  id: 1,
  nombre: "Yogur Jornadas E",
  categoria: "Lácteos",
  unidadMedida: "unidad",
  stock: 120,
  precio: 2300,
  stockMinimo: 20,
};

const camion = {
  id: 1,
  nombre: "Camión Jornadas E",
  patente: "JR123AA",
  marca: "Iveco",
  modelo: "Daily",
  estado: "disponible",
  observaciones: "",
};

const cliente = {
  id: 1,
  nombreComercio: "Almacén Jornadas E",
  titular: "Titular de prueba",
  telefono: "3815550000",
  direccion: "Calle de prueba",
  zona: "Centro",
  condicionPago: "cuenta_corriente",
  limiteCredito: 200000,
  activo: true,
};

const itemJornada = {
  productoId: 1,
  nombreProducto: producto.nombre,
  unidadMedida: "unidad",
  cantidad: 10,
  precioReferencia: 2300,
};

const itemVenta = {
  productoId: 1,
  nombreProducto: producto.nombre,
  unidadMedida: "unidad",
  cantidad: 2,
  precioUnitario: 2300,
  subtotal: 4600,
};

const ventaACuenta = {
  id: "venta-e2e",
  jornadaId: "jornada-e2e",
  camionId: 1,
  clienteId: 1,
  nombreCliente: cliente.nombreComercio,
  fecha: "2026-10-22T10:00:00.000Z",
  medioPago: "cuenta_corriente",
  items: [itemVenta],
  total: 4600,
};

const jornadaAbierta = {
  id: "jornada-e2e",
  camionId: 1,
  chofer: "Chofer Jornadas E",
  zona: "Centro",
  fechaCreacion: "2026-10-22T08:00:00.000Z",
  fechaSalida: "2026-10-22T09:00:00.000Z",
  estado: "abierta",
  items: [itemJornada],
};

const jornadaCerrada = {
  ...jornadaAbierta,
  estado: "cerrada",
  cierre: {
    fecha: "2026-10-22T18:00:00.000Z",
    conteos: { "1": 10 },
    efectivoEntregado: 0,
    efectivoEsperado: 4600,
    transferenciasInformadas: 0,
    ventasCuentaCorriente: 4600,
    observaciones: "",
  },
};

type EstadoInicial = "abierta" | "cerrada" | "conVenta";

async function prepararStorage(page: Page, estado: EstadoInicial) {
  const datos = {
    producto,
    camion,
    cliente,
    venta: estado === "conVenta" ? ventaACuenta : null,
    jornada:
      estado === "cerrada"
        ? jornadaCerrada
        : jornadaAbierta,
  };

  await page.addInitScript(
    ({ clavesStorage, info }) => {
      localStorage.setItem("distribuidora_sesion_demo_v1", "admin-demo");
      localStorage.setItem(
        clavesStorage.productos,
        JSON.stringify([info.producto])
      );
      localStorage.setItem(
        clavesStorage.camiones,
        JSON.stringify([info.camion])
      );
      localStorage.setItem(
        clavesStorage.clientes,
        JSON.stringify([info.cliente])
      );
      localStorage.setItem(
        clavesStorage.jornadas,
        JSON.stringify([info.jornada])
      );
      localStorage.setItem(
        clavesStorage.ventas,
        JSON.stringify(info.venta ? [info.venta] : [])
      );
      localStorage.setItem(clavesStorage.cobros, "[]");
      localStorage.setItem(clavesStorage.movimientos, "[]");
      localStorage.setItem(clavesStorage.retornos, "[]");
    },
    { clavesStorage: claves, info: datos }
  );
}

async function reescribir(page: Page, clave: string, raw: string) {
  await page.evaluate(
    ({ storageKey, valor }) => localStorage.setItem(storageKey, valor),
    { storageKey: clave, valor: raw }
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

test("Autoventa: jornada sugerida cerrada después del montaje, la venta aborta", async ({
  page,
}) => {
  await prepararStorage(page, "abierta");
  await page.goto("/autoventa");
  await page.getByLabel("Seleccionar reparto").selectOption(jornadaAbierta.id);
  await page.locator("select").nth(1).selectOption("1");
  await page.getByLabel(`Cantidad de ${producto.nombre}`).fill("1");
  const registrar = page.getByRole("button", { name: "Registrar venta" });
  await expect(registrar).toBeEnabled();

  // La jornada se cierra después del montaje (el React render sigue viéndola abierta).
  await reescribir(page, claves.jornadas, JSON.stringify([jornadaCerrada]));

  await registrar.click();

  await expect(page.getByRole("alert")).toContainText(
    "ya no está abierta"
  );
  expect(await leerRaw(page, claves.ventas)).toBe("[]");
  expect(await leerRaw(page, claves.jornadas)).toBe(
    JSON.stringify([jornadaCerrada])
  );
});

test("Autoventa: jornadas corruptas después del montaje, la venta aborta", async ({
  page,
}) => {
  await prepararStorage(page, "abierta");
  await page.goto("/autoventa");
  await page.getByLabel("Seleccionar reparto").selectOption(jornadaAbierta.id);
  await page.locator("select").nth(1).selectOption("1");
  await page.getByLabel(`Cantidad de ${producto.nombre}`).fill("1");
  const registrar = page.getByRole("button", { name: "Registrar venta" });
  await expect(registrar).toBeEnabled();

  await reescribir(page, claves.jornadas, rawCorrupto);

  await registrar.click();

  await expect(page.getByRole("alert")).toContainText(
    "No se pueden verificar las jornadas"
  );
  expect(await leerRaw(page, claves.ventas)).toBe("[]");
  expect(await leerRaw(page, claves.jornadas)).toBe(rawCorrupto);
});

test("Movimientos: jornada cerrada después del montaje, el movimiento aborta", async ({
  page,
}) => {
  await prepararStorage(page, "abierta");
  await page.goto("/movimientos");
  await page.getByLabel("Jornada de reparto").selectOption(jornadaAbierta.id);
  await page.getByLabel("Producto dañado *").selectOption("1");
  await page.getByLabel("Cantidad *").fill("1");
  await page.getByLabel("Motivo *").selectOption("Producto vencido");

  await reescribir(page, claves.jornadas, JSON.stringify([jornadaCerrada]));

  await page.getByRole("button", { name: "Registrar merma" }).click();

  await expect(page.getByRole("alert").last()).toContainText(
    "ya no está abierta"
  );
  expect(await leerRaw(page, claves.movimientos)).toBe("[]");
  expect(await leerRaw(page, claves.jornadas)).toBe(
    JSON.stringify([jornadaCerrada])
  );
});

test("Movimientos: jornadas corruptas después del montaje, el movimiento aborta", async ({
  page,
}) => {
  await prepararStorage(page, "abierta");
  await page.goto("/movimientos");
  await page.getByLabel("Jornada de reparto").selectOption(jornadaAbierta.id);
  await page.getByLabel("Producto dañado *").selectOption("1");
  await page.getByLabel("Cantidad *").fill("1");
  await page.getByLabel("Motivo *").selectOption("Producto vencido");

  await reescribir(page, claves.jornadas, rawCorrupto);

  await page.getByRole("button", { name: "Registrar merma" }).click();

  await expect(page.getByRole("alert").last()).toContainText(
    "No se pueden verificar las jornadas"
  );
  expect(await leerRaw(page, claves.movimientos)).toBe("[]");
  expect(await leerRaw(page, claves.jornadas)).toBe(rawCorrupto);
});

test("Cobros: la jornada asociada desaparece después del montaje, el cobro no persiste", async ({
  page,
}) => {
  await prepararStorage(page, "conVenta");
  await page.goto("/cuentas");

  // Cliente con venta fiada y cobro con jornada asociada (opcional).
  await page.getByRole("button", { name: /Almacén Jornadas E/ }).click();
  await page.getByLabel("Importe a cobrar *").fill("100");
  await page
    .getByLabel("Jornada asociada (opcional)")
    .selectOption(jornadaAbierta.id);

  // La jornada desaparece después del montaje.
  await reescribir(page, claves.jornadas, "[]");

  const confirmar = page.getByRole("button", {
    name: "Confirmar cobro",
  });
  await expect(confirmar).toBeEnabled();
  aceptarConfirm(page);
  await confirmar.click();

  await expect(page.getByRole("alert").last()).toContainText(
    "La jornada asociada al cobro ya no existe"
  );
  expect(await leerRaw(page, claves.cobros)).toBe("[]");
});

// Corrompe una clave justo cuando la página llama a window.confirm: simula
// una manipulación en la ventana que abre el confirm, durante la cual la
// revalidación final debe ver el storage dañado y abortar.
function corromperEnConfirm(page: Page, storageKey: string, raw: string) {
  return page.addInitScript(
    ({ storageKeyIJ, rawIJ }) => {
      const originalConfirm = window.confirm;
      window.confirm = function (mensaje) {
        localStorage.setItem(storageKeyIJ, rawIJ);
        return originalConfirm.call(window, mensaje);
      };
    },
    { storageKeyIJ: storageKey, rawIJ: raw }
  );
}

test("Cobros: jornada cerrada en la ventana del confirm, el cobro no persiste", async ({
  page,
}) => {
  await prepararStorage(page, "conVenta");
  // La jornada se cierra en la ventana que abre el confirm. El script de
  // inicialización debe registrarse antes de la navegación: así se aplica al
  // documento de la página y parchea window.confirm.
  await corromperEnConfirm(
    page,
    claves.jornadas,
    JSON.stringify([jornadaCerrada])
  );
  await page.goto("/cuentas");

  await page.getByRole("button", { name: /Almacén Jornadas E/ }).click();
  await page.getByLabel("Importe a cobrar *").fill("100");
  await page
    .getByLabel("Jornada asociada (opcional)")
    .selectOption(jornadaAbierta.id);

  const confirmar = page.getByRole("button", {
    name: "Confirmar cobro",
  });
  await expect(confirmar).toBeEnabled();
  aceptarConfirm(page);
  await confirmar.click();

  await expect(page.getByRole("alert").last()).toContainText(
    "La jornada asociada al cobro ya no está abierta"
  );
  expect(await leerRaw(page, claves.cobros)).toBe("[]");
  expect(await leerRaw(page, claves.jornadas)).toBe(
    JSON.stringify([jornadaCerrada])
  );
});

test("Retornos: jornadas corruptas en la ventana del confirm, la revalidación final aborta", async ({
  page,
}) => {
  await prepararStorage(page, "cerrada");
  // Las jornadas se corrompen exactamente en la ventana del confirm; el
  // parche de window.confirm se aplica al documento si se registra antes de
  // la navegación.
  await corromperEnConfirm(page, claves.jornadas, rawCorrupto);
  await page.goto("/retornos");

  await page.locator("select").selectOption(jornadaCerrada.id);
  await page.getByLabel("Responsable *").fill("Encargado de prueba");
  await page
    .getByLabel("Cantidad aprobada para depósito *")
    .fill("10");

  const confirmar = page.getByRole("button", {
    name: "Confirmar recepción",
  });
  await expect(confirmar).toBeEnabled();

  aceptarConfirm(page);
  await confirmar.click();

  await expect(page.getByRole("alert").last()).toContainText(
    "No se pueden verificar las jornadas"
  );
  expect(await leerRaw(page, claves.retornos)).toBe("[]");
  expect(await leerRaw(page, claves.jornadas)).toBe(rawCorrupto);
});

test("Retornos: el camión de la jornada cambió en la ventana del confirm, la revalidación final aborta", async ({
  page,
}) => {
  await prepararStorage(page, "cerrada");
  // La identidad de la jornada cambia (otro camión) en la ventana del
  // confirm: la revalidación final debe detectar el camión distinto. El
  // parche de window.confirm se aplica al documento si se registra antes de
  // la navegación.
  const jornadaCerradaConOtroCamion = {
    ...jornadaCerrada,
    camionId: 99,
  };
  await corromperEnConfirm(
    page,
    claves.jornadas,
    JSON.stringify([jornadaCerradaConOtroCamion])
  );
  await page.goto("/retornos");

  await page.locator("select").selectOption(jornadaCerrada.id);
  await page.getByLabel("Responsable *").fill("Encargado de prueba");
  await page
    .getByLabel("Cantidad aprobada para depósito *")
    .fill("10");

  const confirmar = page.getByRole("button", {
    name: "Confirmar recepción",
  });
  await expect(confirmar).toBeEnabled();

  aceptarConfirm(page);
  await confirmar.click();

  await expect(page.getByRole("alert").last()).toContainText(
    "cambió de camión"
  );
  expect(await leerRaw(page, claves.retornos)).toBe("[]");
});

