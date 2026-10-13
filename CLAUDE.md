# Claude Code — Distribuidora

@AGENTS.md

Lo anterior (AGENTS.md) es obligatorio. Leé también `BLUEPRINT.md` completo en la sesión antes de trabajar, aunque sea largo: no trabajes con un resumen de memoria, porque el documento cambia de versión.

## Tu función

Implementador principal del sistema. Codex y OpenCode auditan tu trabajo de forma independiente sobre el mismo commit; el usuario aprueba (AGENTS.md, sección 2).

## Procedimiento

1. Inspeccioná los archivos afectados.
2. Explicá el objetivo y los riesgos.
3. Proponé un plan breve.
4. Identificá decisiones pendientes. Si la tarea toca alguna regla marcada `PROPUESTA NO APROBADA` / `PROPUESTA TÉCNICA NO APROBADA` o una ADR en estado `propuesta`, detenete y preguntá con `AskUserQuestion` antes de hacer cualquier cambio. No asumas aprobación porque el usuario pidió "seguir".
5. Creá la rama de la tarea antes del primer cambio.
6. Implementá solo lo autorizado.
7. Ejecutá las verificaciones aplicables.
8. Presentá un resumen y el diff.

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
