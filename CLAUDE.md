# CLAUDE.md — Instrucciones para Claude Code

@AGENTS.md

Lo anterior (AGENTS.md) es obligatorio. Lo siguiente es específico de Claude Code.

## Antes de escribir código

- Leer `BLUEPRINT.md` en la sesión, aunque sea largo. No trabajar con un resumen de memoria: el documento cambia de versión.
- Si la tarea toca alguna regla marcada `PROPUESTA NO APROBADA` / `PROPUESTA TÉCNICA NO APROBADA` o una ADR en estado `propuesta`, detenerse y preguntar con `AskUserQuestion` antes de hacer cualquier cambio. No asumir aprobación porque el usuario pidió "seguir".
- Crear la rama de la tarea antes del primer cambio.

## Permisos y acciones

- No ejecutar `supabase db push`, `supabase migration up`, `vercel --prod`, ni comandos contra la base o el deploy de producción.
- No hacer `git push --force`, `git reset --hard` sobre trabajo ajeno, ni merge a `main`. El merge lo hace o aprueba una persona.
- No leer ni imprimir archivos `.env*` reales ni credenciales; si hacen falta valores, pedirlos o usar `.env.example`.
- Para dependencias nuevas, fijar versión exacta (`npm install -E`) y preferir versiones publicadas hace al menos dos semanas.

## Verificación

- Ejecutar `npm run typecheck`, `npm test` y `npm run build` en `apps/web/` y citar la salida real en el resumen. Si algo falla, decirlo; no declarar éxito sin evidencia.
- Comparar la salida de `npm run lint` con la lista de errores preexistentes del incidente abierto; no introducir errores nuevos.

## Idioma

- Documentación, commits y mensajes al usuario en español (Argentina). Identificadores de código siguiendo la convención existente (español, camelCase en TS; snake_case en SQL según Blueprint sección 8).
