# Despliegue automático a Production de Vercel sin autorización de deploy

**Fecha detectado:** 30/10/2026 (UTC); 29/10/2026 en Argentina
**Detectado por:** el usuario, al revisar el cierre de D-2; los datos de GitHub los consultó Claude Code en modo sólo lectura
**Estado:** resuelto el 30/10/2026, por aprobación expresa del usuario. Alcance del cierre en «Resolución»
**Fecha de resolución:** 30/10/2026
**Rama del registro:** `docs/d2-cierre-auditoria`, desde `4654a95fb478c7b118dca4f67368ccd6a9b331b7`; actualizado en `docs/vercel-incidente-remediacion`, desde `964496dace6a09f4ff719c21ca11b61e70cd0b0d`, y en `docs/vercel-incidente-post-merge`, desde `03d41db9268b8ea9f666ea1444f123960a66fa45`

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

- **Supabase remoto:** no se consultó (por la decisión B1, queda fuera del cierre de este incidente). No se sabe si la migración `20261029233000_lector_perfiles_rpc.sql` está o no aplicada en algún proyecto remoto, ni cómo está configurado. Según la configuración versionada, el despliegue de Vercel no ejecuta migraciones, pero eso no reemplaza una verificación.
- **Impacto real:** no se midió. No se sabe si alguien accedió a la URL productiva, ni desde cuándo esa URL muestra el acceso bloqueado.
- **Panel de Vercel:** Root Directory, asignación automática de dominios y variables del entorno Production. No se revisaron. Branch Tracking y Vercel Authentication sí los comprobó el usuario (ver «Estado posterior al merge del PR #35»); Claude Code no tiene acceso al panel.
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
  - En ese momento, `main` no tenía protección de rama ni rulesets (404 en branch protection; `rules/branches/main` vacío). Después se protegió: ver «Configuración observada».
  - `.github/workflows/ci.yml` corre en `pull_request` sin filtro de rama, así que los checks exigidos también corren en los PR hacia `production`.
- **Prueba del usuario:** en una ventana de incógnito, el dominio productivo `distribuidora-stock-rutas.vercel.app` redirigió al inicio de sesión de Vercel.
- **Lo que esta evidencia no demostraba en ese momento:** que un cambio en `main` dejara de generar un despliegue de Production, y que las URL de Preview también exigieran inicio de sesión. Las dos cosas se comprobaron después (ver «Estado posterior al merge del PR #35»).

## Estado posterior al merge del PR #35

Esta sección separa cuatro cosas: la configuración que se observó, el comportamiento que efectivamente se comprobó, los riesgos aceptados temporalmente y las verificaciones que quedan para más adelante. **Que una configuración se haya observado no prueba que funcione.**

### Configuración observada

| Control | Valor | Cómo se observó |
|---|---|---|
| Branch Tracking de Production en Vercel | `production` | El usuario lo vio en el panel (captura y confirmación de guardado), antes del merge del PR #35 |
| Vercel Authentication | «All Deployments», con «Require Log In» | El usuario lo vio en el panel |
| Ruleset `proteger-production` (`26177269`) | Activo, sólo `refs/heads/production`, sin bypass. Exige PR (0 aprobaciones) y los checks `Lint` y `Tipos, pruebas y build`; bloquea la eliminación y el force push | API de GitHub, sólo lectura (ver «Evidencia observada») |
| Ruleset `proteger-main` (`26207383`) | `enforcement = active`, `target = branch`, sólo `refs/heads/main`, `bypass_actors` vacío. Reglas: `deletion`, `non_fast_forward`, `pull_request` (`required_approving_review_count = 0`) y `required_status_checks` (`Lint` y `Tipos, pruebas y build`, `integration_id = 15368`, GitHub Actions; `strict_required_status_checks_policy = false`) | El usuario lo vio en GitHub, y Claude Code lo leyó por API en sólo lectura el 30/10/2026. `rules/branches/main` devuelve sólo las cuatro reglas de este ruleset |

### Comportamiento comprobado

**Merge a `main` sin despliegue de Production.** El primer merge normal a `main` después del cambio de configuración fue una tarea autorizada, no una prueba. Datos de la API de GitHub, consultados por Claude Code en sólo lectura el 30/10/2026:

| PR | Merge a `main` (UTC) | Commit de merge | GitHub deployment | Estado |
|---|---|---|---|---|
| #35 (remediación documental de este incidente) | 30/10/2026 02:52:36 | `03d41db9268b8ea9f666ea1444f123960a66fa45` | `7429513466`, `Preview`, `vercel[bot]`, creado 02:52:58 | `success` |

- `03d41db` no tiene ningún deployment en `Production`. El último deployment `Production` que lista la API sigue siendo `7428783658` (`964496d`, 30/10/2026 01:59:20).
- `refs/heads/production` permaneció en `964496dace6a09f4ff719c21ca11b61e70cd0b0d`.
- El merge sólo tocó los tres archivos documentales del PR (padres `964496d` y `ad05520`).

**Bloqueo de acceso.** En una ventana de incógnito, el usuario comprobó que tanto Production como Preview redirigen al inicio de sesión de Vercel.

**Qué no se comprobó.** Ninguno de los dos rulesets se puso a prueba en la práctica. `proteger-main` se creó después del merge del PR #35, y hacia `production` todavía no hubo ningún PR ni push. Lo que consta de ellos es su configuración, no su comportamiento.

### Riesgos aceptados temporalmente

- **0 aprobaciones obligatorias en `main` y en `production` (decisión B2).** El usuario lo aceptó temporalmente para los dos rulesets porque es el único responsable del repositorio. Consecuencia: quien tenga permiso de escritura puede integrar su propio PR sin la aprobación de otra persona. Siguen siendo obligatorios: el PR, los checks de CI y una autorización humana explícita e independiente para cada despliegue a Production (`AGENTS.md` §2.2.1 y §2.3.8; ningún agente integra a `production` por su cuenta). **Se revisa cuando se incorpore otro colaborador.**

### Verificaciones futuras (diferidas)

- **Efectividad del ruleset `proteger-production` (decisión B4):** se comprueba en el primer PR real hacia `production`, sin pushes ni deployments de prueba. Hay que registrar que ese PR exigió los checks y que no hubo forma de integrarlo sin ellos. Si ese PR termina desplegando a Production, ese deploy necesita su propia autorización humana, fuera de este incidente.
- **Efectividad del ruleset `proteger-main` (decisión B3):** se comprueba en el próximo PR real hacia `main`, con el mismo método.
- **Supabase remoto (decisión B1):** queda excluido del cierre de este incidente y su verificación sigue pendiente en `docs/progress-log.md`. **No se verificó**: no se sabe si la migración `20261029233000_lector_perfiles_rpc.sql` (D-2) está aplicada en algún proyecto remoto, ni cómo está configurado.

## Criterio de cierre

El incidente pasa a `resuelto` sólo cuando estén cumplidos **todos** los controles de la sección A, registradas **todas** las decisiones humanas de la sección B y **aprobado el cierre por el usuario** (sección C), con la evidencia en este archivo. Las tres condiciones se cumplieron el 30/10/2026.

### A. Controles verificados

| # | Control | Tipo | Evidencia |
|---|---|---|---|
| A1 | `main` ya no despliega a Production | Comportamiento comprobado | El merge del PR #35 (`03d41db`) generó sólo el deployment `7429513466` (`Preview`, `success`) y ningún `Production` (API de GitHub, sólo lectura) |
| A2 | Preview y Production protegidos | Comportamiento comprobado por el usuario | En incógnito, ambos redirigen al inicio de sesión de Vercel |
| A3 | Branch Tracking = `production` | Configuración observada por el usuario | Captura del panel y confirmación de guardado, antes del merge del PR #35 |
| A4 | Vercel Authentication = «All Deployments» | Configuración observada por el usuario | Comprobación del panel |
| A5 | `production` intacta | Comportamiento comprobado | `refs/heads/production` = `964496d` antes y después del merge del PR #35 |

### B. Decisiones humanas (registradas el 30/10/2026)

| # | Tema | Decisión del usuario | Seguimiento |
|---|---|---|---|
| B1 | Supabase remoto | Se excluye del criterio de cierre de este incidente. No se afirma que esté verificado ni que la migración de D-2 esté aplicada en remoto | Pendiente en `docs/progress-log.md` |
| B2 | 0 aprobaciones en `main` y en `production` | Se acepta temporalmente porque el usuario es el único responsable del repositorio. Se mantienen PR, CI y la autorización humana independiente de cada despliegue productivo | Revisar cuando se incorpore otro colaborador |
| B3 | Protección de `main` | Aplicada: ruleset `proteger-main` (`26207383`), observado por el usuario y leído por API | Probar su efectividad en el próximo PR real hacia `main` |
| B4 | Efectividad del ruleset de `production` | Se comprueba en el primer PR real hacia `production`, sin pushes ni deployments de prueba | Verificación operativa diferida; **no** es un control ya probado |

### C. Propuesta de cierre (aprobada por el usuario el 30/10/2026)

Claude Code propuso considerar satisfecho el criterio de cierre por estos motivos, y el usuario aprobó la propuesta expresamente:

- **La causa del incidente quedó neutralizada y se comprobó.** Los pushes a `main` disparaban Production. A1 lo demuestra con un merge real, y A3, A4 y A5 sostienen esa configuración.
- **Todas las decisiones de la sección B están registradas.** Ninguna queda abierta como pregunta.
- **Los pendientes diferidos no impiden el cierre, y hay motivos para diferirlos:**
  - **B4 y la efectividad de `proteger-main`:** se pueden comprobar sólo con un PR real. Generar uno de prueba violaría la regla de no hacer pushes ni deployments de prueba. Además, el ruleset no interviene en la causa del incidente, que ya se comprobó en A1: su función es reforzar la compuerta.
  - **B1:** Supabase remoto no forma parte de la causa, que fue la integración Git de Vercel. Según la configuración versionada, el despliegue no ejecuta migraciones. Su verificación sigue pendiente en `docs/progress-log.md`, sin afirmaciones no comprobadas.

**El cierre no exige un despliegue nuevo a Production.** No se hicieron pushes ni deployments de prueba para cumplir ningún punto.

## Resolución

**Fecha:** 30/10/2026. **Estado:** `resuelto`, por aprobación expresa del usuario de la propuesta C.

**Prueba del cierre:** el merge real del PR #35 (commit `03d41db9268b8ea9f666ea1444f123960a66fa45`) generó sólo el deployment `7429513466` (`Preview`, `success`, `vercel[bot]`) y ningún deployment en `Production`. Es una verificación manual documentada (control A1).

### Qué cierra

- **La causa:** el despliegue automático a Production con cada push o merge a `main`. Quedó mitigada separando la rama `production` y fijando Branch Tracking en `production`, y se comprobó con el merge real del PR #35.
- **La protección de acceso:** Production y Preview exigen inicio de sesión de Vercel. Lo comprobó el usuario en incógnito.
- **Los rulesets:** `proteger-main` (`26207383`) y `proteger-production` (`26177269`) quedan registrados como **configuración observada**.

### Qué no cierra ni afirma

- **No cambia lo ocurrido.** Las tres ocurrencias anteriores (deployments `7426643059`, `7428037655` y `7428783658`) siguen registradas como despliegues productivos sin autorización humana de deploy, y **no se autorizan retroactivamente**.
- **No prueba los rulesets.** La efectividad de `proteger-main` y de `proteger-production` todavía no se probó y queda como verificación operativa diferida: se comprueba en el primer PR real hacia cada rama (ver «Verificaciones futuras (diferidas)»).
- **No verifica Supabase remoto.** Por la decisión B1, no se afirma que Supabase remoto esté verificado ni que la migración `20261029233000_lector_perfiles_rpc.sql` (D-2) esté aplicada en remoto. Esa verificación sigue pendiente en `docs/progress-log.md`.
- **No revisa el resto del panel de Vercel.** Root Directory, la asignación de dominios y las variables de Production siguen sin revisar (ver «Qué permanece sin verificar»).
- **No autoriza deployments productivos.** Cada despliegue a Production, incluido cualquier PR o push hacia `production`, sigue necesitando su propia autorización humana explícita e independiente (`AGENTS.md` §2.2.1 y §2.3.8).
- **No cierra el riesgo de las 0 aprobaciones.** Se acepta temporalmente y debe revisarse cuando se incorpore otro colaborador (decisión B2).
