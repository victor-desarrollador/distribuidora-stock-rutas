// Catálogo de clientes en Supabase local (slice clientes).
//
// UI: el dueño y el encargado crean (quedan validados), editan, validan y
// activan/desactivan; el vendedor/piloto sólo crea (queda pendiente) y
// consulta. HTTP: la Data API sólo escribe por las RPC; un vendedor que fuerza
// la llamada recibe PT403; anon y la escritura directa se rechazan. La UI no
// es la frontera de seguridad: la base sí.
//
// Los clientes creados quedan en la base local: cada prueba usa nombres
// únicos para poder correr en paralelo y repetirse.
import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from "@playwright/test";

import { CUENTAS, PASSWORD_PRUEBA } from "./auth/cuentasPrueba";

const CLIENTE_OTRA_EMPRESA = "00000000-0000-4000-8000-0000000000c1";

function sufijoUnico() {
  return `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
}

function fila(page: Page, texto: string) {
  return page.getByRole("row").filter({ hasText: texto });
}

interface DataApi {
  url: string;
  apikey: string;
  tokenDueno: string;
}

// Toma la URL y la clave pública de la solicitud que hace la app al leer el
// catálogo (no se leen archivos .env).
async function dataApiDesdeApp(page: Page): Promise<DataApi> {
  const solicitud = page.waitForRequest((r) =>
    r.url().includes("/rest/v1/clientes")
  );
  await page.goto("/clientes");
  const r = await solicitud;
  const encabezados = await r.allHeaders();

  return {
    url: new URL(r.url()).origin,
    apikey: encabezados["apikey"],
    tokenDueno: encabezados["authorization"].replace(/^Bearer /, ""),
  };
}

async function tokenDe(
  request: APIRequestContext,
  api: DataApi,
  usuario: string
) {
  const respuesta = await request.post(
    `${api.url}/auth/v1/token?grant_type=password`,
    {
      headers: { apikey: api.apikey },
      data: {
        email: `${usuario}@usuarios.distribuidora.invalid`,
        password: PASSWORD_PRUEBA,
      },
    }
  );
  expect(respuesta.ok()).toBe(true);
  return ((await respuesta.json()) as { access_token: string }).access_token;
}

function encabezados(api: DataApi, token?: string) {
  return {
    apikey: api.apikey,
    "content-type": "application/json",
    ...(token ? { authorization: `Bearer ${token}` } : {}),
  };
}

// Crea un cliente por la RPC con la sesión de `usuario` (alta pendiente si es
// vendedor). Devuelve su id.
async function crearPorRpc(
  request: APIRequestContext,
  api: DataApi,
  usuario: string,
  nombre: string
) {
  const token = await tokenDe(request, api, usuario);
  const respuesta = await request.post(`${api.url}/rest/v1/rpc/crear_cliente`, {
    headers: encabezados(api, token),
    data: { p_nombre: nombre, p_telefono: "3815550000" },
  });
  expect(respuesta.status()).toBe(200);
  return (await respuesta.json()) as string;
}

async function ingresarComo(page: Page, usuario: string, nombreVisible: string) {
  await page.goto("/login");
  await page.getByLabel("Usuario").fill(usuario);
  await page.getByLabel("Contraseña").fill(PASSWORD_PRUEBA);
  await page.getByRole("button", { name: "Ingresar al sistema" }).click();
  await expect(page.getByText(nombreVisible)).toBeVisible();
}

test.describe("UI del catálogo (dueño)", () => {
  test("crea validado, edita, desactiva y reactiva un cliente", async ({
    page,
  }) => {
    const sufijo = sufijoUnico();
    const nombre = `Cliente UI ${sufijo}`;
    await page.goto("/clientes");

    await page.getByRole("button", { name: "Nuevo cliente" }).click();
    await page.getByLabel("Nombre del cliente").fill(`  ${nombre}  `);
    await page.getByLabel("Teléfono").fill("3815551111");
    await page.getByLabel("Comercio").fill("Kiosco UI");
    await page.getByRole("button", { name: "Guardar cliente" }).click();

    await expect(page.getByText("Cliente agregado correctamente.")).toBeVisible();
    await expect(fila(page, nombre)).toContainText("Kiosco UI");
    await expect(fila(page, nombre)).toContainText("Validado");
    await expect(fila(page, nombre)).toContainText("Activo");
    await expect(fila(page, nombre)).toContainText("Sin dirección");

    // La base es la autoridad: el cliente sigue ahí después de recargar.
    await page.reload();
    await expect(fila(page, nombre)).toContainText("Validado");

    await page.getByRole("button", { name: `Editar ${nombre}` }).click();
    await page.getByLabel("Nombre del cliente").fill(`${nombre} bis`);
    await page.getByLabel("Comercio").fill("");
    await page.getByLabel("Dirección").fill("Mitre 100");
    await page.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(page.getByText("Cliente actualizado correctamente.")).toBeVisible();
    await expect(fila(page, `${nombre} bis`)).toContainText("Mitre 100");
    await expect(fila(page, `${nombre} bis`)).not.toContainText("Kiosco UI");

    await page.getByRole("button", { name: `Desactivar ${nombre} bis` }).click();
    await expect(fila(page, `${nombre} bis`)).toContainText("Inactivo");

    await page.getByRole("button", { name: `Activar ${nombre} bis` }).click();
    await expect(fila(page, `${nombre} bis`)).toContainText("Activo");
  });

  test("valida un cliente pendiente creado por un vendedor", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);
    const nombre = `Pendiente ${sufijoUnico()}`;
    await crearPorRpc(request, api, CUENTAS.vendedor, nombre);

    await page.reload();
    await expect(fila(page, nombre)).toContainText("Pendiente");

    await page.getByRole("button", { name: `Validar ${nombre}` }).click();
    await expect(page.getByText(`${nombre} quedó validado.`)).toBeVisible();
    await expect(fila(page, nombre)).toContainText("Validado");
    await expect(
      page.getByRole("button", { name: `Validar ${nombre}` })
    ).toHaveCount(0);
  });

  test("exige nombre y teléfono, y permite homónimos y teléfonos repetidos", async ({
    page,
  }) => {
    const sufijo = sufijoUnico();
    const nombre = `Homónimo ${sufijo}`;
    await page.goto("/clientes");

    // Nombre en blanco: la UI lo frena antes de enviar.
    await page.getByRole("button", { name: "Nuevo cliente" }).click();
    await page.getByLabel("Nombre del cliente").fill("   ");
    await page.getByLabel("Teléfono").fill("3815552222");
    await page.getByRole("button", { name: "Guardar cliente" }).click();
    await expect(page.getByRole("alert")).toHaveText("Ingresá el nombre del cliente.");

    // Dos clientes con el mismo nombre y teléfono: la base no los bloquea.
    for (let i = 0; i < 2; i += 1) {
      if (i > 0) await page.getByRole("button", { name: "Nuevo cliente" }).click();
      await page.getByLabel("Nombre del cliente").fill(nombre);
      await page.getByLabel("Teléfono").fill("3815552222");
      await page.getByRole("button", { name: "Guardar cliente" }).click();
      await expect(page.getByText("Cliente agregado correctamente.")).toBeVisible();
    }
    await expect(fila(page, nombre)).toHaveCount(2);
  });

  test("no ofrece CUIT, email, zona, crédito ni condición de pago", async ({
    page,
  }) => {
    await page.goto("/clientes");
    await page.getByRole("button", { name: "Nuevo cliente" }).click();

    for (const etiqueta of ["CUIT", "DNI", "Email", "Zona", "Límite", "Condición"]) {
      await expect(page.getByLabel(etiqueta)).toHaveCount(0);
    }
  });

  test("no muestra clientes de otra empresa", async ({ page }) => {
    await page.goto("/clientes");
    await expect(page.getByRole("heading", { name: "Clientes" })).toBeVisible();
    await expect(page.getByText("Cargando clientes…")).toHaveCount(0);
    await expect(page.getByText("Cliente de otra empresa (seed)")).toHaveCount(0);
  });
});

test.describe("UI del catálogo (encargado)", () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test("crea validado, edita y valida un pendiente", async ({
    page,
    request,
  }) => {
    await ingresarComo(page, CUENTAS.encargado, "Encargado de prueba");
    const api = await dataApiDesdeApp(page);
    const sufijo = sufijoUnico();
    const nombre = `Cliente Enc ${sufijo}`;
    const pendiente = `Pendiente Enc ${sufijo}`;
    await crearPorRpc(request, api, CUENTAS.vendedor, pendiente);

    await page.reload();
    await page.getByRole("button", { name: "Nuevo cliente" }).click();
    await page.getByLabel("Nombre del cliente").fill(nombre);
    await page.getByLabel("Teléfono").fill("3815553333");
    await page.getByRole("button", { name: "Guardar cliente" }).click();
    await expect(fila(page, nombre)).toContainText("Validado");

    await page.getByRole("button", { name: `Editar ${nombre}` }).click();
    await page.getByLabel("Dirección").fill("San Martín 5");
    await page.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(fila(page, nombre)).toContainText("San Martín 5");

    await expect(fila(page, pendiente)).toContainText("Pendiente");
    await page.getByRole("button", { name: `Validar ${pendiente}` }).click();
    await expect(fila(page, pendiente)).toContainText("Validado");
  });
});

test.describe("UI del catálogo (vendedor/piloto)", () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test("crea un cliente pendiente y no ve acciones de edición ni validación", async ({
    page,
  }) => {
    await ingresarComo(page, CUENTAS.vendedor, "Vendedor de prueba");
    const nombre = `Cliente Vend ${sufijoUnico()}`;

    await page.goto("/clientes");
    await expect(page.getByRole("heading", { name: "Clientes" })).toBeVisible();

    await page.getByRole("button", { name: "Nuevo cliente" }).click();
    await expect(page.getByText(/queda pendiente hasta que el dueño/i)).toBeVisible();
    await page.getByLabel("Nombre del cliente").fill(nombre);
    await page.getByLabel("Teléfono").fill("3815554444");
    await page.getByRole("button", { name: "Guardar cliente" }).click();

    await expect(page.getByText(/Queda pendiente de validación\./)).toBeVisible();
    await expect(fila(page, nombre)).toContainText("Pendiente");

    // Sin acciones sobre fichas existentes.
    await expect(page.getByRole("button", { name: /^Editar/ })).toHaveCount(0);
    await expect(page.getByRole("button", { name: /^Validar/ })).toHaveCount(0);
    await expect(
      page.getByRole("button", { name: /^(Desactivar|Activar)/ })
    ).toHaveCount(0);
    await expect(page.getByRole("columnheader", { name: "Acciones" })).toHaveCount(0);

    // Puede consultar y buscar.
    await page.getByLabel("Buscar clientes").fill(nombre);
    await expect(fila(page, nombre)).toBeVisible();
  });

  // Decisión humana: el vendedor/piloto sólo ve clientes activos. La frontera
  // es la policy SELECT (pgTAP); esto verifica la integración y la UX.
  test("no ve clientes inactivos y sí los activos", async ({ page, request }) => {
    await ingresarComo(page, CUENTAS.vendedor, "Vendedor de prueba");
    const api = await dataApiDesdeApp(page);
    const sufijo = sufijoUnico();
    // Nombres que no se contienen entre sí (hasText busca subcadenas).
    const activo = `Visible Vend ${sufijo}`;
    const inactivo = `Dado de baja Vend ${sufijo}`;
    await crearPorRpc(request, api, CUENTAS.dueno, activo);
    const idInactivo = await crearPorRpc(request, api, CUENTAS.dueno, inactivo);

    const tokenEncargado = await tokenDe(request, api, CUENTAS.encargado);
    const baja = await request.post(`${api.url}/rest/v1/rpc/cambiar_estado_cliente`, {
      headers: encabezados(api, tokenEncargado),
      data: { p_cliente_id: idInactivo, p_activo: false },
    });
    expect(baja.status()).toBe(204);

    await page.reload();
    await page.getByLabel("Buscar clientes").fill(sufijo);
    await expect(fila(page, activo)).toContainText("Activo");
    await expect(fila(page, inactivo)).toHaveCount(0);

    await page.getByLabel("Filtrar clientes").selectOption("inactivos");
    await expect(fila(page, inactivo)).toHaveCount(0);

    // Data API: el vendedor no lo lee ni pidiéndolo por id; el dueño sí.
    const tokenVendedor = await tokenDe(request, api, CUENTAS.vendedor);
    const lecturaVendedor = await request.get(
      `${api.url}/rest/v1/clientes?select=id&id=eq.${idInactivo}`,
      { headers: encabezados(api, tokenVendedor) }
    );
    expect(await lecturaVendedor.json()).toEqual([]);

    const tokenDueno = await tokenDe(request, api, CUENTAS.dueno);
    const lecturaDueno = await request.get(
      `${api.url}/rest/v1/clientes?select=id,activo&id=eq.${idInactivo}`,
      { headers: encabezados(api, tokenDueno) }
    );
    expect(await lecturaDueno.json()).toEqual([{ id: idInactivo, activo: false }]);
  });
});

test.describe("Data API: escritura sólo por RPC y por rol", () => {
  test("el vendedor crea pero no edita, valida ni cambia el estado aunque fuerce la llamada", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);
    const sufijo = sufijoUnico();
    const existente = await crearPorRpc(
      request,
      api,
      CUENTAS.dueno,
      `Existente ${sufijo}`
    );
    const pendiente = await crearPorRpc(
      request,
      api,
      CUENTAS.vendedor,
      `Pendiente API ${sufijo}`
    );
    const token = await tokenDe(request, api, CUENTAS.vendedor);

    const intentos: Array<[string, Record<string, unknown>]> = [
      [
        "actualizar_cliente",
        {
          p_cliente_id: existente,
          p_nombre: "Pisado",
          p_telefono: "1",
          p_comercio: null,
          p_direccion: null,
        },
      ],
      ["validar_cliente", { p_cliente_id: pendiente }],
      ["cambiar_estado_cliente", { p_cliente_id: existente, p_activo: false }],
    ];

    for (const [rpc, data] of intentos) {
      const respuesta = await request.post(`${api.url}/rest/v1/rpc/${rpc}`, {
        headers: encabezados(api, token),
        data,
      });
      expect(respuesta.status(), rpc).toBe(403);
      expect(await respuesta.json()).toMatchObject({
        code: "PT403",
        message: "cliente_no_autorizado",
      });
    }

    // Nada cambió: la ficha existente sigue igual y el pendiente sigue pendiente.
    const lectura = await request.get(
      `${api.url}/rest/v1/clientes?select=id,nombre,activo,estado_validacion&id=in.(${existente},${pendiente})&order=nombre`,
      { headers: encabezados(api, api.tokenDueno) }
    );
    const filas = (await lectura.json()) as Array<{
      id: string;
      nombre: string;
      activo: boolean;
      estado_validacion: string;
    }>;
    expect(filas.find((f) => f.id === existente)).toMatchObject({
      nombre: `Existente ${sufijo}`,
      activo: true,
      estado_validacion: "validado",
    });
    expect(filas.find((f) => f.id === pendiente)).toMatchObject({
      estado_validacion: "pendiente",
    });
  });

  test("nadie escribe directo sobre la tabla y anon no accede", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);
    const sufijo = sufijoUnico();
    const existente = await crearPorRpc(
      request,
      api,
      CUENTAS.dueno,
      `Directo ${sufijo}`
    );

    for (const usuario of [CUENTAS.dueno, CUENTAS.encargado, CUENTAS.vendedor]) {
      const token = await tokenDe(request, api, usuario);

      const insertar = await request.post(`${api.url}/rest/v1/clientes`, {
        headers: encabezados(api, token),
        data: { nombre: `X ${sufijo}`, telefono: "1" },
      });
      expect(insertar.status(), `INSERT ${usuario}`).toBe(403);
      expect(await insertar.json()).toMatchObject({ code: "42501" });

      const actualizar = await request.patch(
        `${api.url}/rest/v1/clientes?id=eq.${existente}`,
        { headers: encabezados(api, token), data: { nombre: "Pisado" } }
      );
      expect(actualizar.status(), `PATCH ${usuario}`).toBe(403);

      const borrar = await request.delete(
        `${api.url}/rest/v1/clientes?id=eq.${existente}`,
        { headers: encabezados(api, token) }
      );
      expect(borrar.status(), `DELETE ${usuario}`).toBe(403);
    }

    // anon: sin lectura, escritura ni RPC.
    expect(
      (await request.get(`${api.url}/rest/v1/clientes`, { headers: encabezados(api) }))
        .status()
    ).toBe(401);
    expect(
      (
        await request.post(`${api.url}/rest/v1/clientes`, {
          headers: encabezados(api),
          data: { nombre: "X", telefono: "1" },
        })
      ).status()
    ).toBe(401);
    // Cuerpos con la firma exacta: PostgREST resuelve la función antes de
    // chequear permisos, así que un cuerpo vacío daría 404 y no 401.
    const rpcAnon: Array<[string, Record<string, unknown>]> = [
      ["crear_cliente", { p_nombre: "X", p_telefono: "1" }],
      [
        "actualizar_cliente",
        {
          p_cliente_id: existente,
          p_nombre: "X",
          p_telefono: "1",
          p_comercio: null,
          p_direccion: null,
        },
      ],
      ["validar_cliente", { p_cliente_id: existente }],
      ["cambiar_estado_cliente", { p_cliente_id: existente, p_activo: false }],
    ];
    for (const [rpc, data] of rpcAnon) {
      const respuesta = await request.post(`${api.url}/rest/v1/rpc/${rpc}`, {
        headers: encabezados(api),
        data,
      });
      expect(respuesta.status(), `anon ${rpc}`).toBe(401);
    }

    // La ficha intacta.
    const lectura = await request.get(
      `${api.url}/rest/v1/clientes?select=nombre&id=eq.${existente}`,
      { headers: encabezados(api, api.tokenDueno) }
    );
    expect(await lectura.json()).toEqual([{ nombre: `Directo ${sufijo}` }]);
  });

  test("otra empresa es invisible e indistinguible de un cliente inexistente", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);

    // El dueño de la empresa principal no lee el cliente de la otra.
    const lectura = await request.get(
      `${api.url}/rest/v1/clientes?select=id&id=eq.${CLIENTE_OTRA_EMPRESA}`,
      { headers: encabezados(api, api.tokenDueno) }
    );
    expect(await lectura.json()).toEqual([]);

    // Ni lo modifica: responde igual que un id inexistente.
    for (const id of [CLIENTE_OTRA_EMPRESA, "11111111-1111-4111-8111-111111111111"]) {
      for (const [rpc, data] of [
        [
          "actualizar_cliente",
          { p_cliente_id: id, p_nombre: "Robado", p_telefono: "1", p_comercio: null, p_direccion: null },
        ],
        ["validar_cliente", { p_cliente_id: id }],
        ["cambiar_estado_cliente", { p_cliente_id: id, p_activo: false }],
      ] as const) {
        const respuesta = await request.post(`${api.url}/rest/v1/rpc/${rpc}`, {
          headers: encabezados(api, api.tokenDueno),
          data,
        });
        expect(respuesta.status(), `${rpc} ${id}`).toBe(404);
        expect(await respuesta.json()).toMatchObject({
          code: "PT404",
          message: "cliente_no_encontrado",
        });
      }
    }

    // El dueño de la otra empresa sólo ve lo suyo.
    const tokenOtra = await tokenDe(request, api, CUENTAS.otraEmpresa);
    const propia = await request.get(`${api.url}/rest/v1/clientes?select=id,nombre`, {
      headers: encabezados(api, tokenOtra),
    });
    const filas = (await propia.json()) as Array<{ id: string }>;
    expect(filas.map((f) => f.id)).toContain(CLIENTE_OTRA_EMPRESA);
    expect(filas.every((f) => f.id === CLIENTE_OTRA_EMPRESA)).toBe(true);
  });

  test("el esquema privado y los parámetros de empresa, autor o validador no existen para la Data API", async ({
    page,
    request,
  }) => {
    const api = await dataApiDesdeApp(page);
    const sufijo = sufijoUnico();

    const privado = await request.post(`${api.url}/rest/v1/rpc/crear_cliente`, {
      headers: {
        ...encabezados(api, api.tokenDueno),
        "content-profile": "privado",
      },
      data: { p_nombre: "PRIV", p_telefono: "1" },
    });
    expect(privado.status()).toBe(406);

    for (const extra of [
      { p_empresa_id: "00000000-0000-4000-8000-0000000000e2" },
      { p_creado_por: "00000000-0000-4000-8000-000000000002" },
      { p_validado_por: "00000000-0000-4000-8000-000000000002" },
      { p_estado_validacion: "validado" },
    ]) {
      const respuesta = await request.post(`${api.url}/rest/v1/rpc/crear_cliente`, {
        headers: encabezados(api, api.tokenDueno),
        data: { p_nombre: `EXTRA ${sufijo}`, p_telefono: "1", ...extra },
      });
      expect(respuesta.status(), JSON.stringify(extra)).toBe(404);
    }

    // Ningún intento anterior creó clientes.
    const busqueda = await request.get(
      `${api.url}/rest/v1/clientes?select=id&nombre=like.*${sufijo}*`,
      { headers: encabezados(api, api.tokenDueno) }
    );
    expect(await busqueda.json()).toEqual([]);
  });
});
