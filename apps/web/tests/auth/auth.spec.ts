import { expect, test, type Page } from '@playwright/test'

import { CUENTAS, PASSWORD_PRUEBA } from './cuentasPrueba'

// Estos casos parten siempre sin sesión.
test.use({ storageState: { cookies: [], origins: [] } })

async function ingresar(page: Page, usuario: string, password = PASSWORD_PRUEBA) {
  await page.goto('/login')
  await page.getByLabel('Usuario').fill(usuario)
  await page.getByLabel('Contraseña').fill(password)
  await page.getByRole('button', { name: 'Ingresar al sistema' }).click()
}

test('el login pide usuario y contraseña, sin email ni selector demo', async ({ page }) => {
  await page.goto('/login')

  await expect(page.getByLabel('Usuario')).toBeVisible()
  await expect(page.getByLabel('Contraseña')).toHaveAttribute('type', 'password')
  await expect(page.getByRole('combobox')).toHaveCount(0)
  await expect(page.getByText(/email|correo/i)).toHaveCount(0)
})

test('login correcto (usuario con mayúsculas y espacios) entra con el rol del perfil', async ({ page }) => {
  await ingresar(page, '  Encargado.Prueba ')

  await expect(page).toHaveURL('/')
  await expect(page.getByText('Encargado de prueba')).toBeVisible()

  // La contraseña nunca queda en el almacenamiento del navegador.
  const almacenado = await page.evaluate(() =>
    JSON.stringify({ ...localStorage }) + JSON.stringify({ ...sessionStorage })
  )
  expect(almacenado).not.toContain(PASSWORD_PRUEBA)
})

test('credenciales incorrectas muestran error y no inician sesión', async ({ page }) => {
  await ingresar(page, CUENTAS.dueno, 'contraseña-incorrecta')

  await expect(page.getByRole('alert')).toHaveText('Usuario o contraseña incorrectos.')
  await expect(page).toHaveURL('/login')

  await page.goto('/productos')
  await expect(page).toHaveURL('/login')
})

test('usuario inexistente recibe el mismo mensaje genérico', async ({ page }) => {
  await ingresar(page, 'no.existe')

  await expect(page.getByRole('alert')).toHaveText('Usuario o contraseña incorrectos.')
})

for (const usuario of ['abc.', 'a..b', '.aabc']) {
  test(`usuario con formato inválido "${usuario}" no llega a Auth`, async ({ page }) => {
    const pedidosAuth: string[] = []
    page.on('request', (req) => {
      if (req.url().includes('/auth/v1/token')) pedidosAuth.push(req.url())
    })

    await ingresar(page, usuario)

    await expect(page.getByRole('alert')).toContainText('Usuario inválido')
    await expect(page).toHaveURL('/login')
    expect(pedidosAuth).toEqual([])
  })
}

test('ruta protegida sin sesión redirige a login', async ({ page }) => {
  await page.goto('/productos')

  await expect(page).toHaveURL('/login')
})

test('la sesión se restaura al recargar y logout la elimina', async ({ page }) => {
  await ingresar(page, CUENTAS.dueno)
  await expect(page.getByText('Dueño de prueba')).toBeVisible()

  await page.reload()
  await expect(page.getByText('Dueño de prueba')).toBeVisible()

  await page.getByRole('button', { name: 'Cerrar sesión' }).click()
  await expect(page).toHaveURL('/login')

  await page.goto('/productos')
  await expect(page).toHaveURL('/login')
})

test('vendedor/piloto no accede a rutas de dueño/encargado (su user_metadata dice dueño)', async ({ page }) => {
  await ingresar(page, CUENTAS.vendedor)

  await expect(page).toHaveURL('/')
  await expect(page.getByText('Vendedor/Piloto').first()).toBeVisible()

  // B-02b.1 (Blueprint §9, ADR-007 §2.8): /jornadas ya es accesible al vendedor
  // (sólo lee su jornada; la RLS decide las filas). Las rutas de gestión
  // (/productos, /stock, /camiones) siguen vedadas al vendedor. Las rutas
  // retiradas (/demo/jornadas, /autoventa, /movimientos, /rendicion,
  // /retornos, /cuentas, /configuracion-demo) ya no existen en el router.
  for (const ruta of ['/productos', '/stock', '/camiones']) {
    await page.goto(ruta)
    await expect(page.getByRole('heading', { name: 'Acceso no permitido' })).toBeVisible()
  }

  await page.goto('/jornadas')
  await expect(page.getByRole('heading', { name: 'Mi jornada' })).toBeVisible()
})

test('encargado accede a rutas de gestión (productos, stock, camiones)', async ({ page }) => {
  await ingresar(page, CUENTAS.encargado)
  await expect(page.getByText('Encargado de prueba')).toBeVisible()

  for (const ruta of ['/productos', '/stock', '/camiones']) {
    await page.goto(ruta)
    await expect(page).not.toHaveURL('/login')
    await expect(page.getByRole('heading', { name: 'Acceso no permitido' })).not.toBeVisible()
  }
})

test('usuario con perfil inactivo queda bloqueado', async ({ page }) => {
  await ingresar(page, CUENTAS.inactivo)

  await expect(page.getByRole('heading', { name: 'Acceso bloqueado' })).toBeVisible()
  await expect(page.getByRole('alert')).toContainText('desactivada')

  await page.goto('/productos')
  await expect(page.getByRole('heading', { name: 'Acceso bloqueado' })).toBeVisible()

  await page.getByRole('button', { name: 'Cerrar sesión' }).click()
  await expect(page).toHaveURL('/login')
})

test('cuenta Auth sin perfil queda bloqueada', async ({ page }) => {
  await ingresar(page, CUENTAS.sinPerfil)

  await expect(page.getByRole('heading', { name: 'Acceso bloqueado' })).toBeVisible()
  await expect(page.getByRole('alert')).toContainText('no tiene un perfil')
})
