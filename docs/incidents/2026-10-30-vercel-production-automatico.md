# Despliegue automático a Production de Vercel sin autorización de deploy

**Fecha detectado:** 30/10/2026 (UTC); 29/10/2026 en Argentina
**Detectado por:** el usuario, al revisar el cierre de D-2; los datos de GitHub los consultó Claude Code en modo sólo lectura
**Estado:** abierto, en seguimiento hasta definir y verificar las medidas preventivas
**Rama del registro:** `docs/d2-cierre-auditoria`, desde `4654a95fb478c7b118dca4f67368ccd6a9b331b7`

## Qué pasó

1. El PR #33 (D-2, commit auditado `e826d308aab9a0b108ece17128c5c3448d7729ae`) se integró a `main` con autorización humana de merge el 30/10/2026 a las 01:02:50 UTC. El commit de merge es `4654a95fb478c7b118dca4f67368ccd6a9b331b7`.
2. El push a `main` disparó automáticamente un despliegue de Vercel en el entorno **Production**: GitHub deployment `7428037655`, creado por `vercel[bot]` el 30/10/2026 a las 01:03:06 UTC. El estado de commit `Vercel` de `4654a95` pasó de `pending` («Vercel is deploying your app», 01:02:54 UTC) a `success` («Deployment has completed», 01:03:05 UTC).
3. **No hubo una autorización humana específica para desplegar en producción.** La autorización fue sólo de merge. `AGENTS.md` §2.2.1 y §2.3.8 exigen una autorización explícita e independiente para cada paso (push, merge y deploy), y prohíben cambiar la configuración productiva de Vercel o desplegar en producción sin aprobación (§5).

## Comportamiento observado

En la captura del usuario, la aplicación desplegada muestra el acceso bloqueado por falta de las variables `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY`.

Ese mensaje lo genera `leerConfigSupabase` (`apps/web/src/lib/supabase.ts:52-55`) cuando alguna de esas dos variables falta o está vacía. Es el comportamiento fail-closed vigente del frontend, que no se modificó. Este registro no verificó en el panel de Vercel qué variables tiene configuradas el entorno Production.

## Alcance del cambio desplegado

- D-2 no cambia el frontend: `git diff --stat 5e64f27 4654a95 -- apps/web` no muestra archivos. El merge sólo agrega o modifica `AGENTS.md`, `docs/progress-log.md`, una migración, un procedimiento de reversión manual y tests pgTAP en `supabase/`.
- `apps/web/vercel.json` sólo declara un `rewrite` hacia `/index.html`; no ejecuta migraciones ni comandos de Supabase. El script `build` de `apps/web/package.json` es `tsc -b && vite build`.

## Qué se verificó

- Merge del PR #33, commit de merge y tree (GitHub, sólo lectura).
- Deployment `7428037655` en `Production`, creador `vercel[bot]`, y los estados de commit de Vercel sobre `4654a95` (API de GitHub, sólo lectura).
- CI (`Lint` y `Tipos, pruebas y build`) en verde sobre el PR y sobre el push a `main` (run `40983457559`).
- Ausencia de cambios en `apps/web/` en el merge.
- Rama `main` sin protección de rama (la API de GitHub responde 404 «Branch not protected»).
- Entornos `Preview` y `Production` de GitHub sin reglas de protección.

## Qué permanece sin verificar

- **Supabase remoto:** no se consultó. No se sabe si la migración `20261029233000_lector_perfiles_rpc.sql` está o no aplicada en algún proyecto remoto. Según la configuración versionada, el despliegue de Vercel no ejecuta migraciones, pero eso no reemplaza una verificación.
- **Impacto real:** no se midió. No se sabe si alguien accedió a la URL productiva, ni desde cuándo esa URL muestra el acceso bloqueado.
- **Configuración del panel de Vercel:** rama de producción, Root Directory, asignación automática de dominios, protección del sitio y variables del entorno Production. No se revisaron: no hay CLI de Vercel ni un proyecto vinculado en el repositorio.
- Si despliegues anteriores de `main` también fueron a Production automáticamente. No se revisó el historial.

## Causa

La única causa comprobada es que un push a `main` generó un despliegue de Production por la integración Git de Vercel, sin un paso de aprobación humana. La configuración concreta del panel que lo produce no se verificó.

## Medidas preventivas propuestas (sin aplicar)

1. **Rama `production` separada:** configurar en Vercel una rama de producción distinta de `main`. Así `main` genera sólo Previews, y desplegar en producción requiere actualizar esa rama con una autorización humana propia.
2. **Protección del sitio:** activar la protección de despliegues de Vercel, para que las URL de Preview y de Production no queden accesibles públicamente mientras producción siga bloqueada (ADR-001 §15 y §19).
3. **Aprobación humana del despliegue:** que ningún despliegue productivo ocurra sin una autorización explícita. Por ejemplo, desactivar la asignación automática de dominios y promover a mano, o desplegar sólo desde la rama `production`. Registrar cada autorización.

Complemento posible, también pendiente de decisión: proteger `main` (PR obligatorio y checks del CI). Esto evita merges sin autorización, pero no despliegues.

Ninguna de estas medidas se aplicó. Cambiar la configuración de Vercel o de GitHub requiere una decisión y una ejecución humanas.

## Cierre

El incidente pasa a `resuelto` sólo cuando las medidas elegidas estén aplicadas y verificadas con evidencia documentada, por ejemplo: un merge o push de prueba a `main` que no genere un despliegue en Production.
