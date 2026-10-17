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

Archivos modificados (rama `chore/corregir-lint`, desde `4cdffb1`):
- `src/AuthContext.tsx` + nuevos `src/auth/AuthContextValue.ts`, `src/auth/useAuth.ts`, `src/auth/usuariosDemo.ts`: separación estructural; el archivo del componente ahora exporta solo `AuthProvider`. Imports de consumidores actualizados explícitamente (App, ProtectedRoute, Login, ConfiguracionDemo, Sidebar, AppLayout). Sin excepciones de ESLint.
- `src/components/layout/Sidebar.tsx`: eliminado el effect que cerraba el menú al cambiar de ruta; el cierre tras navegar ya existía en el `onClick` de cada `NavLink` y en el botón X/backdrop/Escape/salir. Comportamiento idéntico.
- `src/hooks/useMovimientos.ts`: validador `(p: any)` reemplazado por `(p: unknown)` con type guard propio y chequeos runtime equivalentes campo por campo.
- `src/pages/Autoventa.tsx`, `CuentasCorrientes.tsx`, `Movimientos.tsx`, `Retornos.tsx`: estabilización mínima de dependencias derivadas (`jornadasAbiertas/Cerradas`, `jornada`, `cliente(sCuenta)`, `movimientosJornada`) envolviendo los mismos `.filter()/.find()` preexistentes en `useMemo` con sus deps reales. Ningún cálculo, filtro, regla de stock/dinero ni selección de jornada cambió. En `Movimientos.tsx`, `salidas` pasó a depender de `movimientosJornada` (mismo array memorizado) y se resolvió la advertencia `exhaustive-deps` de `disponibles`.

Solución aplicada:
Correcciones mecánicas de lint únicamente (ver lista arriba). No se cambió comportamiento de negocio ni flujos demo.

Pruebas que lo verifican (test o verificación manual documentada):
Ejecutadas el 18/10/2026 sobre `chore/corregir-lint`: `npm run lint` → exit 0 (0 errores, 0 advertencias); `npm run typecheck` → exit 0; `npm test` (Vitest) → 5/5 pasan; `npm run build` → exit 0. Se quitó `continue-on-error: true` del job `lint` de `.github/workflows/ci.yml`, cumpliendo el criterio de cierre.

Cómo evitar que vuelva a pasar:
El job `lint` de CI ahora es bloqueante: cualquier fallo futuro rompe el pipeline.

Estado: cerrado (18/10/2026, rama `chore/corregir-lint`)
