# Lint falla en `main` (errores preexistentes)

Fecha detectado: 12/10/2026
Detectado por: Claude Code, durante la Tarea 001 (verificación de línea base antes de modificar nada)

Qué falló:
`npm run lint` en `apps/web/` termina con código 1: 10 errores y 1 advertencia. El build (`tsc -b && vite build`) sí pasa.

| Archivo | Línea | Regla |
|---|---|---|
| `src/AuthContext.tsx` | 22, 113 | `react-refresh/only-export-components` |
| `src/components/layout/Sidebar.tsx` | 51 | `react-hooks/set-state-in-effect` |
| `src/hooks/useMovimientos.ts` | 20 | `@typescript-eslint/no-explicit-any` |
| `src/pages/Autoventa.tsx` | 151 | `react-hooks/preserve-manual-memoization` |
| `src/pages/CuentasCorrientes.tsx` | 102, 134 | `react-hooks/preserve-manual-memoization` |
| `src/pages/Movimientos.tsx` | 140 | `react-hooks/preserve-manual-memoization` |
| `src/pages/Movimientos.tsx` | 127 | `react-hooks/exhaustive-deps` (advertencia) |
| `src/pages/Retornos.tsx` | 79, 103 | `react-hooks/preserve-manual-memoization` |

Cómo se reproduce (pasos):
1. `cd apps/web && npm ci`
2. `npm run lint`

Causa raíz:
Código del prototipo escrito antes de que existiera CI; las reglas de `eslint-plugin-react-hooks` 7 (React Compiler) no se verificaban en cada commit. No se investigó cada caso en detalle.

Archivos modificados: ninguno (todavía).

Solución aplicada:
Ninguna. La Tarea 001 prohíbe cambiar la lógica de stock, ventas o dinero, y varios errores están en pantallas de autoventa, retornos, movimientos y cuentas corrientes. Mientras tanto, el job `lint` de CI corre con `continue-on-error: true` (informa, no bloquea).

Pruebas que lo verifican (test o verificación manual documentada):
Pendiente. Criterio de cierre: `npm run lint` termina con código 0 y se quita `continue-on-error` del job `lint` en `.github/workflows/ci.yml`.

Cómo evitar que vuelva a pasar:
Una vez corregido, volver bloqueante el job `lint` en CI.

Estado: abierto
