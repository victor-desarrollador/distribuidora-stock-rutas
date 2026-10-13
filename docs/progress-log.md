# Bitácora de progreso

Una entrada por tarea, la más reciente arriba. Cada entrada: qué se hizo, archivos modificados, cómo se verificó y riesgos pendientes.

---

## 12/10/2026 — Tarea 001: Preparación del repositorio

**Rama:** `chore/tarea-001-preparar-repo` · **Agente:** Claude Code · **Estado:** pendiente de aprobación humana para merge

### Qué se hizo

- Se incorporó `BLUEPRINT.md` v1.4 a la raíz del repositorio (sin cambios en su contenido).
- Se movió `ADR-001-rpc-privilegiadas_v1.1.md` a `docs/decisions/001-rpc-privilegiadas.md` (contenido sin cambios; estado: **propuesta, NO aprobada**).
- Se creó la estructura `docs/` según Blueprint sección 13: `decisions/` (índice + plantilla), `incidents/` (índice + plantilla), `progress-log.md`, `changelog.md`.
- Se creó `AGENTS.md` (común a Claude Code, OpenCode y Codex) con prohibición expresa de implementar propuestas no aprobadas y ADR en estado `propuesta`, con lista de las propuestas vigentes en v1.4.
- Se creó `CLAUDE.md` (importa `AGENTS.md` y agrega reglas específicas de Claude Code).
- Se creó `.gitignore` en la raíz. Antes, **`.env` no estaba ignorado** (solo `*.local` en `apps/web/.gitignore`). Ahora se ignoran `.env`, `.env.*` (excepto `.env.example`), `.vercel`, temporales locales de Supabase CLI, claves/certificados y JSON de credenciales. Se conservó `apps/web/.gitignore`.
- Se agregó Vitest `5.0.2` (versión exacta, publicada el 25/09/2026) como devDependency en `apps/web/`, y los scripts `typecheck`, `test` y `test:watch`.
- Se agregó una primera prueba de caracterización (`apps/web/src/data/mockData.test.ts`): unicidad de ids en datos demo y comportamiento actual de `salidasPorMovimiento`. Documenta el prototipo; **no** valida reglas del Blueprint.
- Se agregó CI en `.github/workflows/ci.yml`: job bloqueante `verificar` (typecheck → test → build) y job `lint` no bloqueante por errores preexistentes.
- Se registró el incidente `docs/incidents/2026-10-12-lint-falla-en-main.md`.

**No se modificó** lógica de stock, ventas, dinero, autenticación ni pantallas. No se borraron módulos ni datos demo. No se instaló Supabase, no se generaron migraciones, no se tocó producción ni Vercel.

### Archivos

| Archivo | Cambio |
|---|---|
| `BLUEPRINT.md` | agregado (v1.4, sin cambios) |
| `docs/decisions/001-rpc-privilegiadas.md` | movido desde la raíz (sin cambios) |
| `docs/decisions/README.md` | nuevo |
| `docs/incidents/README.md` | nuevo |
| `docs/incidents/2026-10-12-lint-falla-en-main.md` | nuevo |
| `docs/progress-log.md` | nuevo |
| `docs/changelog.md` | nuevo |
| `AGENTS.md` | nuevo |
| `CLAUDE.md` | nuevo |
| `.gitignore` | nuevo (raíz) |
| `README.md` | enlaces a Blueprint, agentes, docs y app (había 3 títulos duplicados) |
| `.github/workflows/ci.yml` | nuevo |
| `apps/web/package.json` | scripts `typecheck`, `test`, `test:watch`; devDependency `vitest` |
| `apps/web/package-lock.json` | actualizado por `npm install` |
| `apps/web/src/data/mockData.test.ts` | nuevo |

### Cómo se verificó

Ejecutado en local (Node 24.20.0, npm 11.19.0), desde `apps/web/` tras `rm -rf node_modules && npm ci`:

| Verificación | Antes (main) | Después |
|---|---|---|
| `npm run typecheck` | — (no existía; `tsc -b` pasaba dentro de `build`) | exit 0 |
| `npm test` | — (no existía) | 1 archivo, 4 pruebas, todas pasan |
| `npm run build` | exit 0, `index-E6w3GRy_.js` | exit 0, `index-E6w3GRy_.js` (**mismo hash**: el bundle de la app no cambió) |
| `npm run lint` | 10 errores, 1 advertencia | 10 errores, 1 advertencia (sin errores nuevos) |
| `.gitignore` | `.env` versionable | `git check-ignore`: `.env`, `.env.local`, `.env.production`, `apps/web/.env`, `apps/web/.env.development.local`, `supabase/.temp/*`, `*.pem` ignorados; `.env.example` versionable |
| `ci.yml` | — | YAML válido (`yaml valid`). **No ejecutado aún en GitHub Actions**: correrá al abrir el PR |

### Inventario técnico de Etapa 0

**No se encontró** en el repositorio (no existía `docs/` ni `progress-log.md`). Esta tarea no lo reemplaza. Observaciones hechas al pasar, sin análisis exhaustivo, para que el inventario las considere:

- El frontend persiste todo en `localStorage` (hooks en `apps/web/src/hooks/`); no hay backend ni Supabase. El stock se modifica desde el frontend, contrario a Blueprint secciones 3 y 6 (esperable en un prototipo).
- `UnidadMedida` incluye `"kg"` (`apps/web/src/data/mockProductos.ts`), pero el Blueprint excluye venta por kilogramo (sección 2) y define `unidad`/`pieza` con stock en medias piezas (7.1).
- `CondicionPago` usa `cuenta_corriente`; el Blueprint deja la gestión de cuenta corriente para Fase 2 y en Fase 1 solo registra importe `a_cuenta`.
- Los roles y el login son de demostración (`AuthContext.tsx`), no Supabase Auth.

### Riesgos pendientes

1. **Inventario de Etapa 0 ausente.** Debe hacerse antes de la Etapa 1.
2. **Lint falla en `main`** (incidente abierto). CI lo informa sin bloquear; mientras tanto, errores nuevos de lint podrían pasar desapercibidos si nadie mira el job.
3. **CI no probado en GitHub.** Puede requerir ajustes al primer run (p. ej. permisos de Actions en el repo).
4. **Las pruebas actuales son de caracterización del prototipo**, no cubren ninguna prueba obligatoria de la sección 12. Esas requieren Supabase + pgTAP, bloqueadas hasta aprobar ADR-001.
5. **Estructura del Blueprint vs repo:** el Blueprint muestra `src/` en la raíz; el código vive en `apps/web/src/`. Se documentó en `AGENTS.md`; conviene reflejarlo en una próxima versión del Blueprint.
6. **Vercel:** no se verificó si el proyecto de Vercel usa `apps/web` como root directory; los nuevos archivos en la raíz no deberían afectar el deploy, pero no se comprobó.
7. **ADR-001 sigue en `propuesta`.** Ninguna tarea de base de datos puede avanzar hasta su aprobación.
