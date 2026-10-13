# AGENTS.md — Instrucciones comunes para agentes

Aplica a **Claude Code, OpenCode, Codex** y cualquier otro agente o persona que trabaje en este repositorio.

## 1. Antes de empezar cualquier tarea

1. Leer `BLUEPRINT.md` completo. Es la fuente de referencia: si el código lo contradice, manda el Blueprint hasta que una decisión aprobada lo cambie.
2. Leer este archivo.
3. Revisar `docs/decisions/README.md` (estado de cada ADR) y las últimas entradas de `docs/progress-log.md`.

## 2. Prohibición expresa: propuestas no aprobadas

**Está prohibido implementar, total o parcialmente, cualquier regla marcada en el Blueprint como `PROPUESTA NO APROBADA` o `PROPUESTA TÉCNICA NO APROBADA`, y cualquier ADR cuyo estado no sea `aprobada`.**

Esto incluye, a la fecha (Blueprint v1.4):

- Stock negativo transitorio en camión / marca `excede_stock` (sección 7.4).
- Reglas de anulación de ventas por el vendedor (sección 7.5).
- Prohibición de descuentos / esquema de precio de lista vs aplicado (sección 7.5).
- Retiro de efectivo que supera el saldo registrado sin bloqueo (sección 7.6).
- Vencimientos por partida de ingreso / tabla `partidas_ingreso` (secciones 2, 4, 8).
- **ADR-001**: wrappers `SECURITY DEFINER` + esquema privado (`docs/decisions/001-rpc-privilegiadas.md`).

"Implementar" incluye: código de aplicación, migraciones SQL, funciones RPC, políticas RLS, tipos, pruebas que asuman la regla como vigente y cambios de UI que la reflejen.

Si una tarea depende de alguna de estas propuestas: **detenerse, informar el bloqueo y pedir aprobación expresa**. No elegir "la opción más razonable" por cuenta propia. Un agente no puede aprobar una propuesta ni cambiar el estado de una ADR.

Tampoco se implementa nada de la sección 5 del Blueprint (fuera de alcance / Fase 2) sin una decisión aprobada en `docs/decisions/`.

## 3. Reglas de trabajo

1. **Una rama por tarea.** Nunca commitear directo a `main`. El merge requiere aprobación humana.
2. **No tocar producción.** No ejecutar migraciones, no apuntar a la base de producción, no cambiar la configuración de Vercel productiva.
3. **No mover stock ni dinero desde el frontend.** En la versión final, todo cambio de stock o dinero pasa por RPC en la base (Blueprint secciones 3 y 6).
4. Toda migración nueva va en `supabase/migrations/`; nunca cambios manuales en la base. (Supabase todavía no está incorporado; no crearlo sin una tarea que lo pida.)
5. Si una regla del Blueprint parece incorrecta, **no cambiarla en el código**: proponer una decisión en `docs/decisions/` con estado `propuesta`.
6. No borrar módulos existentes ni los datos de demostración (`apps/web/src/data/`, pantalla `ConfiguracionDemo`) salvo que una tarea lo pida explícitamente.
7. No commitear secretos. Variables de entorno en `.env*` (ignorados); solo `.env.example` sin valores reales.
8. Nada se da por terminado sin prueba (Blueprint, principio 5): test automatizado o verificación manual documentada.

## 4. Estructura del repositorio

```
/
├── BLUEPRINT.md          visión, alcance y reglas vigentes
├── AGENTS.md             este archivo
├── CLAUDE.md             instrucciones específicas de Claude Code
├── docs/
│   ├── decisions/        ADR, una por archivo
│   ├── incidents/        incidentes, uno por archivo
│   ├── progress-log.md   bitácora por tarea
│   └── changelog.md      versiones entregadas
├── .github/workflows/    CI
└── apps/web/             frontend React + TypeScript + Vite (deploy en Vercel)
```

El Blueprint muestra `src/` en la raíz; en este repositorio el frontend vive en `apps/web/src/`. Se respeta la estructura existente.

## 5. Comandos (desde `apps/web/`)

| Comando | Qué hace |
|---|---|
| `npm ci` | Instala dependencias exactas del lockfile |
| `npm run dev` | Servidor de desarrollo |
| `npm run typecheck` | Verificación de tipos (`tsc -b`) |
| `npm test` | Pruebas unitarias (Vitest, una pasada) |
| `npm run lint` | ESLint (hoy falla por errores preexistentes; ver `docs/incidents/2026-10-12-lint-falla-en-main.md`) |
| `npm run build` | Build de producción |

Antes de pedir revisión: `typecheck`, `test` y `build` deben pasar, y no deben aparecer errores de lint nuevos.

## 6. Al terminar una tarea

1. Agregar una entrada en `docs/progress-log.md`: qué se hizo, archivos modificados, cómo se verificó, riesgos pendientes.
2. Si se encontró un error, registrarlo en `docs/incidents/`.
3. Presentar el resumen y **pedir aprobación humana antes del merge**.
