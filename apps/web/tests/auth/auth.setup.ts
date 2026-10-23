import { expect, test as setup } from '@playwright/test'

import { CUENTAS, PASSWORD_PRUEBA } from './cuentasPrueba'

setup('iniciar sesión como dueño de prueba', async ({ page }) => {
  await page.goto('/login')
  await page.getByLabel('Usuario').fill(CUENTAS.dueno)
  await page.getByLabel('Contraseña').fill(PASSWORD_PRUEBA)
  await page.getByRole('button', { name: 'Ingresar al sistema' }).click()

  await expect(page.getByText('Dueño de prueba')).toBeVisible()

  await page.context().storageState({ path: 'playwright/.auth/dueno.json' })
})
