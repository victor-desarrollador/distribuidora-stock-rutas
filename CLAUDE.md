# Claude Code — Distribuidora

@AGENTS.md

Lo anterior (AGENTS.md) es obligatorio. Leé también `BLUEPRINT.md` completo en la sesión antes de trabajar, aunque sea largo: no trabajes con un resumen de memoria, porque el documento cambia de versión.

## Tu función

Implementador principal del sistema. **Claude sigue siendo implementador, no auditor final.** Codex y OpenCode auditan tu trabajo de forma independiente sobre el mismo commit; el usuario aprueba (AGENTS.md, §2).

## Procedimiento

1. Leé `BLUEPRINT.md` completo y las ADR aplicables (las `aprobada`; las `propuesta` solo para no contradecirlas) antes de implementar. No trabajes con un resumen de memoria.
2. Inspeccioná los archivos afectados.
3. Explicá el objetivo y los riesgos.
4. Proponé un plan breve.
5. Identificá decisiones pendientes. Si la tarea toca alguna regla marcada `PROPUESTA NO APROBADA` / `PROPUESTA TÉCNICA NO APROBADA` o una ADR en estado `propuesta`, detenete y preguntá con `AskUserQuestion` antes de hacer cualquier cambio. No asumas aprobación porque el usuario pidió "seguir".
6. Creá la rama de la tarea antes del primer cambio.
7. Implementá **solo lo autorizado**, respetando el alcance de la tarea.
8. Ejecutá las verificaciones aplicables: `lint`, `typecheck`, `tests` y `build` (AGENTS.md §9).
9. Usá Playwright cuando corresponda (AGENTS.md §2.5).
10. Presentá un resumen y el diff, y **solicitá/aceptá auditoría independiente**. No apruebes tu propio commit.
11. Si corregís un hallazgo, generá un **nuevo commit/hash** para la re-auditoría (AGENTS.md §2.3.4).
12. **No hagas merge ni deploy** (AGENTS.md §2.3.7 y §2.3.8).

## Superficies sensibles

Si la tarea toca alguna de las superficies de AGENTS.md §2.4 (Supabase, auth, `empresa_id`, roles, RLS, RPC, `SECURITY DEFINER`/`SECURITY INVOKER`, grants, `service_role`, `movimientos_stock`, ventas, pagos, retiros, cierres, idempotencia, concurrencia o secretos):

- señalá expresamente que corresponde **security review**;
- **no consideres la tarea cerrada** sin esa revisión.

Claude `/security-review` es **opcional/pendiente**: la obligación es la revisión de seguridad, no una herramienta específica. Tampoco cierra la revisión por sí solo.

## Decisiones y alcance

- No conviertas **ADR-001** en `aprobada` ni cambies su estado: sigue **PROPUESTA — NO APROBADA**.
- No resuelvas por cuenta propia los puntos **P1–P20** de ADR-001.
- **No introduzcas reglas funcionales nuevas**: si una regla del Blueprint parece incorrecta, se propone una decisión en `docs/decisions/` con estado `propuesta` (AGENTS.md §6.5).

## Permisos y acciones

- No hagas commits, push, merges ni despliegues sin aprobación.
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
- Compará la salida de `npm run lint` con la lista de errores preexistentes del incidente abierto; no introduzcas errores nuevos.

## Idioma

Documentación, commits y mensajes al usuario en español (Argentina). Identificadores de código según la convención existente (AGENTS.md, sección 7).

El usuario es quien aprueba las decisiones finales.
