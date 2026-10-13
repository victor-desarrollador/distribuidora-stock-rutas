# AGENTS.md — Distribuidora de Lácteos y Fiambres

Aplica a **Claude Code, OpenCode, Codex** y cualquier otro agente o persona que trabaje en este repositorio.

## 1. Documentación obligatoria

Antes de modificar código:
1. Leer `BLUEPRINT.md` completo. Es la fuente de referencia: si el código lo contradice, manda el Blueprint hasta que una decisión aprobada lo cambie.
2. Leer este archivo.
3. Revisar las decisiones en `docs/decisions/` (estado de cada ADR en `docs/decisions/README.md`) y las últimas entradas de `docs/progress-log.md`.
4. Consultar el código existente.
5. Identificar qué reglas siguen pendientes de aprobación.

## 2. Flujo de trabajo entre agentes

1. **Claude Code implementa** la tarea autorizada en su propia rama.
2. **Codex y OpenCode auditan de forma independiente el mismo commit.** Cada auditoría se hace sobre un hash concreto, sin modificar archivos (en OpenCode, subagente `auditor`, `.opencode/agents/auditor.md`). Un auditor no corrige el código: reporta hallazgo, severidad, archivo y línea, regla del Blueprint afectada, riesgo y corrección propuesta.
3. **El usuario aprueba.** Decide sobre los hallazgos y autoriza commit, push, merge y deploy. Ningún agente aprueba su propio trabajo ni el de otro agente.

Si después de una auditoría se cambia el código, el nuevo commit vuelve a auditarse.

## 3. Prohibición expresa: propuestas no aprobadas

**Está prohibido implementar, total o parcialmente, cualquier regla marcada en el Blueprint como `PROPUESTA NO APROBADA` o `PROPUESTA TÉCNICA NO APROBADA`, y cualquier ADR cuyo estado no sea `aprobada`.**

Esto incluye, a la fecha (Blueprint v1.4):

- Stock negativo transitorio en camión / marca `excede_stock` (sección 7.4).
- Reglas de anulación de ventas por el vendedor (sección 7.5).
- Prohibición de descuentos / esquema de precio de lista vs aplicado (sección 7.5).
- Retiro de efectivo que supera el saldo registrado sin bloqueo (sección 7.6).
- Vencimientos por partida de ingreso / tabla `partidas_ingreso` (secciones 2, 4, 8).
- **ADR-001**: wrappers `SECURITY DEFINER` + esquema privado (`docs/decisions/001-rpc-privilegiadas.md`).

"Implementar" incluye: código de aplicación, migraciones SQL, funciones RPC, políticas RLS, tipos, pruebas que asuman la regla como vigente y cambios de UI que la reflejen.

Si una tarea depende de alguna de estas propuestas: **detener esa parte del trabajo, informar el bloqueo y pedir aprobación expresa**. No elegir "la opción más razonable" por cuenta propia. Un agente no puede aprobar una propuesta ni cambiar el estado de una ADR.

Tampoco se implementa nada de la sección 5 del Blueprint (fuera de alcance / Fase 2) sin una decisión aprobada en `docs/decisions/`.

## 4. Arquitectura

- Frontend: React + TypeScript + Vite.
- Aplicación web en `apps/web/`.
- Backend previsto: Supabase Auth y PostgreSQL.
- Deploy previsto: Vercel.
- Operaciones críticas de stock y dinero: transacciones PostgreSQL con autorización comprobada.

## 5. Reglas obligatorias

- No implementar reglas marcadas como PROPUESTA NO APROBADA ni ADR que no estén aprobadas (sección 3).
- No introducir Prisma ni un servidor Express sin aprobación.
- No incorporar un nuevo sistema de persistencia en localStorage.
- No trasladar reglas del prototipo a SQL sin validarlas.
- No mover stock ni dinero desde el frontend. En la versión final, todo cambio de stock o dinero pasa por RPC en la base (Blueprint secciones 3 y 6).
- No usar credenciales administrativas en el navegador.
- No borrar movimientos financieros ni de inventario confirmados.
- No introducir cambios de alcance sin autorización.

### Producción y seguridad

- **No tocar producción.** No ejecutar migraciones remotas, no apuntar a la base de producción, no cambiar la configuración de Vercel productiva.
- Prohibido sin aprobación explícita: `supabase db push`, `supabase migration up`, `vercel --prod` y cualquier comando contra la base o el deploy de producción.
- Prohibido: `git push --force`, `git reset --hard` sobre trabajo ajeno y merge a `main` sin aprobación humana.
- No commitear secretos. Variables de entorno en `.env*` (ignorados); solo `.env.example` sin valores reales.
- No leer ni imprimir archivos `.env*` reales ni credenciales; si hacen falta valores, pedirlos o usar `.env.example`.

## 6. Desarrollo

1. **Una rama por tarea.** Nunca commitear directo a `main`. El merge requiere aprobación humana.
2. Mantener la estructura `apps/web/`.
3. Hacer cambios pequeños y verificables.
4. Toda migración nueva va en `supabase/migrations/`; nunca cambios manuales en la base. (Supabase todavía no está incorporado; no crearlo sin una tarea que lo pida.)
5. Si una regla del Blueprint parece incorrecta, **no cambiarla en el código**: proponer una decisión en `docs/decisions/` con estado `propuesta`.
6. No borrar módulos existentes ni los datos de demostración (`apps/web/src/data/`, pantalla `ConfiguracionDemo`) salvo que una tarea lo pida explícitamente.
7. Agregar pruebas para las reglas nuevas. Nada se da por terminado sin prueba (Blueprint, principio 5): test automatizado o verificación manual documentada.
8. **Dependencias con versión exacta** (`npm install -E`, sin `^` ni `~` en lo que se agregue), preferentemente publicadas hace al menos dos semanas. Lo mismo para plugins de agentes referenciados por git: fijar un tag.
9. Registrar decisiones e incidentes relevantes.
10. Pedir aprobación antes de hacer merge o deploy.

## 7. Idioma

Documentación, commits y mensajes al usuario en español (Argentina). Identificadores de código siguiendo la convención existente (español, camelCase en TS; snake_case en SQL según Blueprint sección 8).

## 8. Estructura del repositorio

```
/
├── BLUEPRINT.md          visión, alcance y reglas vigentes
├── AGENTS.md             este archivo
├── CLAUDE.md             instrucciones específicas de Claude Code
├── opencode.json         configuración de OpenCode (permisos, plugins)
├── .opencode/agents/     subagentes de OpenCode (auditor de solo lectura)
├── .claude/              configuración compartida de Claude Code
├── docs/
│   ├── decisions/        ADR, una por archivo
│   ├── incidents/        incidentes, uno por archivo
│   ├── progress-log.md   bitácora por tarea
│   └── changelog.md      versiones entregadas
├── .github/workflows/    CI (único workflow: ci.yml)
└── apps/web/             frontend React + TypeScript + Vite (deploy en Vercel)
```

El Blueprint muestra `src/` en la raíz; en este repositorio el frontend vive en `apps/web/src/`. Se respeta la estructura existente.

## 9. Comandos (desde `apps/web/`)

| Comando | Qué hace |
|---|---|
| `npm ci` | Instala dependencias exactas del lockfile |
| `npm run dev` | Servidor de desarrollo |
| `npm run typecheck` | Verificación de tipos (`tsc -b`) |
| `npm test` | Pruebas unitarias (Vitest, una pasada; `src/**/*.test.ts(x)`) |
| `npx playwright test` | Pruebas end-to-end (Playwright, `tests/`; requiere `npx playwright install chromium` la primera vez) |
| `npm run lint` | ESLint (hoy falla por errores preexistentes; ver `docs/incidents/2026-10-12-lint-falla-en-main.md`) |
| `npm run build` | Build de producción |

Antes de pedir revisión: `typecheck`, `test`, Playwright y `build` deben pasar, y no deben aparecer errores de lint nuevos respecto del incidente abierto.

## 10. Reglas de negocio confirmadas

- Roles: dueño, encargado y vendedor/piloto.
- El vendedor puede crear clientes, pero no editar fichas existentes.
- Un camión tiene como máximo una jornada por día operativo.
- Los fiambres se venden por pieza y media pieza.
- Las ventas admiten pagos combinados.
- Los retiros de efectivo requieren doble confirmación.
- Dueño y encargado pueden aprobar rendiciones.
- Preventa, proveedores y compras corresponden a Fase 2.

El detalle y las excepciones siempre se consultan en `BLUEPRINT.md`.

## 11. Al terminar una tarea

1. Agregar una entrada en `docs/progress-log.md`: qué se hizo, archivos modificados, cómo se verificó, riesgos pendientes.
2. Si se encontró un error, registrarlo en `docs/incidents/`.
3. Presentar el resumen, el diff y el hash a auditar, y **pedir aprobación humana antes del commit, del merge y del deploy**.
