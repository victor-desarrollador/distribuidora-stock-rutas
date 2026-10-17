import { test, expect } from '@playwright/test'

test('la aplicación de distribuidora carga', async ({ page }) => {
  await page.goto('http://127.0.0.1:4173/')

  await expect(page.locator('body')).toBeVisible()
})
