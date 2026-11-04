import { defineConfig, devices } from '@playwright/test'

// Los E2E requieren Supabase local (`npx supabase start --workdir ../..`) con el
// seed de supabase/seed.sql y las variables VITE_SUPABASE_URL y
// VITE_SUPABASE_PUBLISHABLE_KEY del stack local (ver .env.example).
//
// La prueba «service_role: sin EXECUTE…» de tests/jornadas-rpc-http.spec.ts
// necesita además E2E_SUPABASE_SECRET_KEY: la clave secreta del stack LOCAL
// (SECRET_KEY de `npx supabase status --workdir ../.. -o env`), pasada sólo como
// variable de entorno de la corrida. Sin ella esa prueba falla (no se omite).
// Nunca va en .env, .env.example ni en el repositorio, y no se imprime. Esa
// prueba envía la clave sólo por el fetch nativo de Node (fuera de las trazas de
// Playwright) y ese spec desactiva trace, screenshot y video a nivel de archivo;
// la política global de este archivo no cambia.
export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  reporter: 'list',

  use: {
    baseURL: 'http://127.0.0.1:4173',
    trace: 'on-first-retry',
  },

  projects: [
    {
      // Inicia sesión real una vez y guarda la sesión de Supabase del dueño
      // de prueba para los specs operativos.
      name: 'setup',
      testMatch: /auth\.setup\.ts/,
    },
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'playwright/.auth/dueno.json',
      },
      dependencies: ['setup'],
    },
  ],

  webServer: {
    command: 'npm run dev -- --host 127.0.0.1 --port 4173 --strictPort',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: !process.env.CI,
    timeout: 30000,
  },
})
