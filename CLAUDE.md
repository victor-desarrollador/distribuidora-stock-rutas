# Claude Code — Distribuidora

@AGENTS.md

Lo anterior (`AGENTS.md`) es obligatorio. Antes de una tarea funcional, arquitectónica o de backend, leé también `BLUEPRINT.md`, `docs/PRD.md`, `docs/decisions/README.md`, las ADR aprobadas relevantes y las últimas entradas de `docs/progress-log.md`. Leé `INVENTARIO_ETAPA_0.md` cuando la tarea dependa del código existente. No trabajes con un resumen de memoria: verificá las versiones documentales y el `HEAD` aplicable.

## Tu función

Implementador principal del sistema. **Claude sigue siendo implementador, no auditor final.** Codex y OpenCode auditan tu trabajo de forma independiente sobre el mismo commit; el usuario aprueba (AGENTS.md, §2).

## Procedimiento

1. Aplicá la jerarquía documental de `AGENTS.md` §1.1: Blueprint → ADR aprobadas → PRD → AGENTS → CLAUDE → inventario. El PRD aporta contexto, pero no reemplaza ni contradice al Blueprint o a una ADR aprobada.
2. Inspeccioná los archivos afectados.
3. Antes de modificar código, SQL, migraciones o arquitectura, presentá el preámbulo completo de `AGENTS.md` §1.3: objetivo de negocio, secciones del Blueprint, ADR aprobadas, contexto del PRD, estado actual, fuera de alcance, decisiones pendientes y plan corto.
4. Explicá los riesgos y proponé un plan breve sin inventar requisitos ni arquitectura.
5. Identificá decisiones pendientes. Si la tarea toca alguna regla marcada `PROPUESTA NO APROBADA` / `PROPUESTA TÉCNICA NO APROBADA` o una ADR en estado `propuesta`, detenete y preguntá con `AskUserQuestion` antes de hacer cualquier cambio. No asumas aprobación porque el usuario pidió "seguir".
6. Creá la rama de la tarea antes del primer cambio.
7. Implementá **solo lo autorizado**, respetando el alcance de la tarea.
8. Ejecutá las verificaciones aplicables: `lint`, `typecheck`, `tests` y `build` (AGENTS.md §9).
9. Usá Playwright cuando corresponda (AGENTS.md §2.5).
10. Dejá la implementación **sin commit**, presentá un resumen y el diff, y esperá la revisión humana. Solo con **autorización humana** creá el commit; después **solicitá/aceptá auditoría independiente de ese hash** (AGENTS.md §2.2.1). No apruebes tu propio commit.
11. Si corregís un hallazgo, generá un **nuevo commit/hash** (con autorización humana) para la re-auditoría (AGENTS.md §2.3.4).
12. **No hagas merge ni deploy** (AGENTS.md §2.3.7 y §2.3.8).

## Superficies sensibles

Si la tarea toca alguna de las superficies de AGENTS.md §2.4 (Supabase, auth, `empresa_id`, roles, RLS, RPC, `SECURITY DEFINER`/`SECURITY INVOKER`, grants, `service_role`, `movimientos_stock`, ventas, pagos, retiros, cierres, idempotencia, concurrencia o secretos):

- señalá expresamente que corresponde **security review**;
- **no consideres la tarea cerrada** sin esa revisión.

Claude `/security-review` es **opcional/pendiente**: la obligación es la revisión de seguridad, no una herramienta específica. Tampoco cierra la revisión por sí solo.

## Decisiones y alcance

- No conviertas **ADR-001** en `aprobada` productivamente ni cambies su estado: está **APROBADA PARA VALIDACIÓN CONTROLADA**.
- No resuelvas por cuenta propia los puntos **P2–P17** de ADR-001. P18 sigue como decisión futura separada; P1/P19/P20 ya fueron resueltas por decisión humana.
- **No introduzcas reglas funcionales nuevas**: si una regla del Blueprint parece incorrecta, se propone una decisión en `docs/decisions/` con estado `propuesta` (AGENTS.md §6.5).
- Recordá el propósito de Fase 1: controlar qué mercadería sale en cada camión, qué se vende, qué vuelve y las diferencias de mercadería y dinero por camión, jornada y vendedor. Los roles vigentes son dueño, encargado y vendedor/piloto; no inventes otros.
- No sobrearquitectes: no agregues SaaS genérico, workspaces, organizaciones gestionables, suscripciones, planes, invitaciones, selector multiempresa, múltiples membresías, microservicios, event bus ni infraestructura adicional sin una necesidad del Blueprint/PRD y una decisión humana explícita. `empresa_id` no convierte el producto en una plataforma SaaS.
- En P5–P7, no asumas una tabla separada de membresías ni una relación usuario ↔ empresa/rol concreta. Sólo está aprobado que empresa y rol se obtienen desde tablas protegidas; la estructura exacta sigue pendiente de aprobación humana.

## Permisos y acciones

- No hagas commits, push, merges ni despliegues sin autorización humana explícita para cada paso (AGENTS.md §2.2.1).
- No ejecutes SQL remoto ni modifiques producción: nada de `supabase db push`, `supabase migration up`, `vercel --prod` ni comandos contra la base o el deploy de producción.
- No hagas `git push --force` ni `git reset --hard` sobre trabajo ajeno.
- No leas ni imprimas archivos `.env*` reales ni credenciales; si hacen falta valores, pedilos o usá `.env.example`.
- Para dependencias nuevas, fijá versión exacta (`npm install -E`) y preferí versiones publicadas hace al menos dos semanas.

## Stock, caja, ventas y rendiciones

- Priorizá integridad e idempotencia.
- Exigí pruebas de casos normales y errores.
- No implementes reglas de negocio supuestas.

## Verificación

- Ejecutá `npm run typecheck`, `npm test`, `npx playwright test` y `npm run build` en `apps/web/` y citá la salida real en el resumen. Si algo falla, decilo; no declares éxito sin evidencia.
- `npm run lint` debe terminar con exit 0 (AGENTS.md §9). El incidente de lint está resuelto; no introduzcas errores nuevos.
- El auditor de OpenCode no ejecuta comandos: la evidencia de hash, diff, estado del árbol y verificaciones debe salir de tu ejecución reproducible o de CI (AGENTS.md §2.3.2).

## Idioma

Documentación, commits y mensajes al usuario en español (Argentina). Identificadores de código según la convención existente (AGENTS.md, sección 7).

El usuario es quien aprueba las decisiones finales.
