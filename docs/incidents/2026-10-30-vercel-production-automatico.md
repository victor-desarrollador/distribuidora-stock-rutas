# Despliegue automático a Production de Vercel sin autorización de deploy

**Fecha detectado:** 30/10/2026 (UTC); 29/10/2026 en Argentina
**Detectado por:** el usuario, al revisar el cierre de D-2; los datos de GitHub los consultó Claude Code en modo sólo lectura
**Estado:** abierto. El usuario aplicó las medidas preventivas el 30/10/2026; faltan las verificaciones del «Criterio de cierre»
**Rama del registro:** `docs/d2-cierre-auditoria`, desde `4654a95fb478c7b118dca4f67368ccd6a9b331b7`; actualizado en `docs/vercel-incidente-remediacion`, desde `964496dace6a09f4ff719c21ca11b61e70cd0b0d`

## Qué pasó

Cada merge a `main` generó automáticamente, a través de la integración Git de Vercel, un despliegue en el entorno **Production**. Ocurrencias comprobadas en la API de GitHub (sólo lectura):

| PR | Merge a `main` (UTC) | Commit de merge | GitHub deployment | Creado (UTC) | Estado de commit `Vercel` |
|---|---|---|---|---|---|
| #32 (anexo §18.4 de ADR-001) | 29/10/2026 23:24:31 | `5e64f27aa50293555b1b0e08c523a1932dfe65ff` | `7426643059`, `Production`, `vercel[bot]` | 29/10/2026 23:24:50 | `pending` 23:24:35 → `success` 23:24:49 |
| #33 (D-2) | 30/10/2026 01:02:50 | `4654a95fb478c7b118dca4f67368ccd6a9b331b7` | `7428037655`, `Production`, `vercel[bot]` | 30/10/2026 01:03:06 | `pending` 01:02:54 → `success` 01:03:05 |
| #34 (cierre documental de D-2) | 30/10/2026 01:58:53 | `964496dace6a09f4ff719c21ca11b61e70cd0b0d` | `7428783658`, `Production`, `vercel[bot]` | 30/10/2026 01:59:20 | `pending` 01:58:57 → `success` 01:59:20 |

El usuario vio en Vercel como «Ready» el despliegue de `964496d`.

**Ninguno de estos tres despliegues productivos tuvo una autorización humana independiente de deploy.** Los merges se autorizaron como merges, nada más. Este registro no presenta ni admite una autorización retroactiva. `AGENTS.md` §2.2.1 y §2.3.8 exigen una autorización explícita e independiente para cada paso (push, merge y deploy), y §5 prohíbe desplegar en producción sin aprobación.

## Comportamiento observado

En la captura del usuario, la aplicación desplegada muestra el acceso bloqueado por falta de las variables `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY`.

Ese mensaje lo genera `leerConfigSupabase` (`apps/web/src/lib/supabase.ts:52-55`) cuando alguna de esas dos variables falta o está vacía. Es el comportamiento fail-closed vigente del frontend, que no se modificó. Este registro no verificó en el panel de Vercel qué variables tiene configuradas el entorno Production.

## Alcance del cambio desplegado

- D-2 no cambia el frontend: `git diff --stat 5e64f27 4654a95 -- apps/web` no muestra archivos. El merge sólo agrega o modifica `AGENTS.md`, `docs/progress-log.md`, una migración, un procedimiento de reversión manual y tests pgTAP en `supabase/`.
- El PR #34 sólo modifica documentación en `docs/`.
- `apps/web/vercel.json` sólo declara un `rewrite` hacia `/index.html`; no ejecuta migraciones ni comandos de Supabase. El script `build` de `apps/web/package.json` es `tsc -b && vite build`.

## Qué se verificó

- Los merges, los commits de merge y los deployments de los PR #32, #33 y #34, más los estados de commit de Vercel (API de GitHub, sólo lectura).
- CI (`Lint` y `Tipos, pruebas y build`) en verde sobre el PR #33 y sobre el push de su merge a `main` (run `40983457559`).
- Ausencia de cambios en `apps/web/` en el merge del PR #33.
- Al momento del primer registro, `main` no tenía protección de rama (404 «Branch not protected») y los entornos `Preview` y `Production` de GitHub no tenían reglas de protección.

## Qué permanece sin verificar

- **Supabase remoto:** no se consultó. No se sabe si la migración `20261029233000_lector_perfiles_rpc.sql` está o no aplicada en algún proyecto remoto, ni cómo está configurado. Según la configuración versionada, el despliegue de Vercel no ejecuta migraciones, pero eso no reemplaza una verificación.
- **Impacto real:** no se midió. No se sabe si alguien accedió a la URL productiva, ni desde cuándo esa URL muestra el acceso bloqueado.
- **Panel de Vercel:** Root Directory, asignación automática de dominios y variables del entorno Production. No se revisaron, y la configuración de Branch Tracking y de Vercel Authentication sólo consta por lo que informó el usuario (ver «Medidas preventivas»).
- **Historial de despliegues:** sólo se revisaron los deployments más recientes que lista la API de GitHub. No se revisó el historial completo anterior al PR #32.

## Causa

La única causa comprobada es que los pushes a `main` generaron despliegues de Production por la integración Git de Vercel, sin un paso de aprobación humana. Según informó el usuario al cambiar la configuración el 30/10/2026, Branch Tracking de Production seguía `main`.

## Medidas preventivas

El usuario aplicó las medidas propuestas (rama `production` separada, protección del sitio y aprobación humana del despliegue) el 30/10/2026, después del merge del PR #34. Claude Code no modificó ninguna configuración de Vercel, GitHub ni Supabase.

### Configuración aplicada (informada por el usuario)

| # | Medida | Configuración |
|---|---|---|
| 1 | Rama `production` separada de `main` | Rama `production` creada desde `main`, inicialmente 0 commits adelante y 0 detrás. A partir de ahí avanza por separado de `main` |
| 2 | Branch Tracking de Vercel | Production → Branch Tracking sigue `production` en lugar de `main`, con confirmación de guardado |
| 3 | Aprobación humana para actualizar `production` | Ruleset de GitHub `proteger-production` (ID `26177269`), activo, dirigido sólo a `production`: PR obligatorio; checks `Lint` y `Tipos, pruebas y build` obligatorios; bloqueo de eliminación y de force push. Required approvals = 0 |
| 4 | Protección del sitio | Vercel Authentication en «All Deployments», con «Require Log In» activado |

### Evidencia observada

- **API de GitHub (sólo lectura, Claude Code, 30/10/2026):**
  - `refs/heads/production` = `964496dace6a09f4ff719c21ca11b61e70cd0b0d`, igual que `main` (0 adelante, 0 detrás).
  - Ruleset `26177269`: `name = proteger-production`, `enforcement = active`, `target = branch`, `include = refs/heads/production`, sin `bypass_actors`. Reglas: `deletion`, `non_fast_forward`, `pull_request` (`required_approving_review_count = 0`) y `required_status_checks` (`Lint` y `Tipos, pruebas y build`, de GitHub Actions).
  - `main` sigue sin protección de rama ni rulesets (404 en branch protection; `rules/branches/main` vacío).
  - `.github/workflows/ci.yml` corre en `pull_request` sin filtro de rama, así que los checks exigidos también corren en los PR hacia `production`.
- **Prueba del usuario:** en una ventana de incógnito, el dominio productivo `distribuidora-stock-rutas.vercel.app` redirigió al inicio de sesión de Vercel.
- **Lo que esta evidencia no demuestra todavía:** que un cambio en `main` deje de generar un despliegue de Production, y que las URL de Preview también exijan inicio de sesión.

### Riesgos residuales

- **0 aprobaciones obligatorias en GitHub:** quien tenga permiso de escritura puede integrar su propio PR a `production` sin la aprobación de otra persona. La compuerta humana es el acto de integrar ese PR. Por `AGENTS.md` §2.3.8, ningún agente puede hacerlo por su cuenta.
- **`main` sin protección:** según la configuración informada ya no despliega a Production, pero admite push directo y merges sin checks obligatorios.
- **Supabase remoto:** su configuración y el estado de sus migraciones siguen pendientes de verificación.

## Criterio de cierre

El incidente pasa a `resuelto` sólo cuando se cumplan **todos** estos puntos, con la evidencia documentada en este archivo:

1. **`main` ya no despliega a Production:** el primer cambio normal integrado a `main` después del cambio de configuración, hecho por una tarea autorizada y no como prueba, tiene en la API de GitHub sólo deployments `Preview` y ningún `Production`. Se registran el SHA y el ID del deployment.
2. **Preview protegido:** una URL de Preview (por ejemplo, la del deployment `Preview` del punto 1) redirige al inicio de sesión de Vercel en una ventana de incógnito.
3. **Controles no verificados:** el usuario aporta evidencia (captura o descripción fechada) de Branch Tracking = `production` y de Vercel Authentication = «All Deployments», o acepta expresamente lo informado como evidencia suficiente.
4. **Supabase remoto:** hay una verificación de sólo lectura, hecha y documentada por el humano, de su configuración y del estado de la migración `20261029233000_lector_perfiles_rpc.sql`; o hay una decisión humana expresa de dejarlo fuera del cierre, con su motivo. Claude Code no ejecuta comandos contra Supabase remoto.
5. **Riesgos residuales:** decisión humana registrada sobre las 0 aprobaciones y `main` sin protección: se aceptan o se cambian.

**El cierre no exige un despliegue nuevo a Production.** El primer despliegue productivo futuro tendrá su propia autorización humana explícita y su propia verificación, fuera de este incidente.

Mientras falte alguno de los puntos 1 a 5, el estado sigue `abierto`. No se hacen pushes ni deployments de prueba para cumplirlos.
