# Bitácora de progreso

Una entrada por tarea, la más reciente arriba. Cada entrada: qué se hizo, archivos modificados, cómo se verificó y riesgos pendientes.

---

## 17/10/2026 — Corrección M1: `piezas_a_medias` admite medias piezas exactas

**Rama:** `feat/dominio-cantidades-rendicion` (base `1001fadc4809bd4b63510dd3604603767760130c`) · **Agente:** OpenCode · **Estado:** corrección de auditoría implementada y verificada en local; **sin push y sin merge**; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Contexto

La auditoría de solo lectura del commit `f14c4c97337c2278df7efb8ca5e25845e96e75b1` resultó **APPROVED WITH CORRECTIONS**, con un único hallazgo que afecta el contrato: **M1 — `piezas_a_medias` rechazaba `0.5`** lanzando `Error`, en vez de devolver `1` media pieza (caso "1/2 pieza = 1 media pieza").

### Decisión humana

`piezas_a_medias` debe aceptar cantidades en **múltiplos exactos de 0.5**:

```
0 -> 0   0.5 -> 1   1 -> 2   1.5 -> 3   2 -> 4   4.5 -> 9
```

Debe rechazar negativos, valores que no sean múltiplos de 0.5 (`0.25`, `0.75`, `1.25`), `NaN`, `Infinity` y `-Infinity`. La salida de `piezas_a_medias` sigue siendo siempre una cantidad canónica entera en medias piezas.

### Cambios

- `apps/web/src/domain/cantidades.ts`: `piezas_a_medias` valida localmente (finito, `>= 0` y `piezas * MEDIAS_POR_PIEZA` entero) en lugar de reutilizar `validar_cantidad`, que representa una cantidad canónica y por eso no admite `0.5`. `medias_a_piezas`, `es_cantidad_valida` y `validar_cantidad` no cambian.
- `apps/web/src/domain/cantidades.test.ts`: se agrega "admite medias piezas exactas (múltiplos de 0.5)" y se corrigen los casos negativos de `piezas_a_medias`: el rechazo erróneo de `1.5` se reemplaza por `-0.5`, `0.25`, `0.75` y `1.25`. Los tests de `medias_a_piezas` y de `rendicion` no se tocan.
- Sin cambios en `rendicion.ts`, `rendicion.test.ts`, pantallas, Supabase, migraciones, RLS ni RPC.

### Fuera de esta corrección

Los hallazgos **L1** (`snake_case` vs `AGENTS.md` §7), **L2** (`validar_cantidad` no nombra el campo que falló) y **L3** (duplicación con los validadores locales de las pantallas) quedan **no bloqueantes** y fuera de esta corrección; siguen como riesgos pendientes de la entrada anterior.

### Verificación (desde `apps/web/`)

| Verificación | Resultado |
|---|---|
| `npm test -- --run` | exit 0; `Test Files 4 passed (4)`; `Tests 39 passed (39)` (34 de dominio + 5 preexistentes) |
| `npm run typecheck` | exit 0 |
| `npm run lint` | exit 0 |
| `npm run build` | exit 0; `dist/assets/index-BKH7CK6R.js 394.04 kB │ gzip: 110.55 kB` |
| `git diff --check` | exit 0 |

### Reauditoría

Esta corrección genera un **commit nuevo** (no `amend` del anterior). **Todo hash nuevo requiere reauditoría independiente completa** (AGENTS.md §2.3.4): la auditoría de `f14c4c9` no se reutiliza para el nuevo commit.

---

## 17/10/2026 — Dominio puro de cantidades (unidad mínima) y cálculo básico de rendición

**Rama:** `feat/dominio-cantidades-rendicion` (base `1001fadc4809bd4b63510dd3604603767760130c`) · **Agente:** OpenCode · **Estado:** implementado con TDD (RED → GREEN) y verificado en local; **sin push y sin merge**, pendiente de auditoría independiente sobre su propio hash; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Objetivo

Extraer lógica de dominio pura para cantidades en unidad mínima y cálculo básico de rendición, con los tests escritos antes que la implementación (TDD), sin integrarla todavía a ninguna pantalla.

### Blueprint aplicable

- §3: el stock no se edita a mano; simple antes que completo; nada se da por terminado sin prueba.
- §7.1: cantidades enteras en la unidad mínima; 1 pieza = 2 medias piezas.
- §7.4: no permitir inconsistencias de stock silenciosas.
- §7.5: rendición / jornada.
- §12: pruebas.

### Implementación

`apps/web/src/domain/cantidades.ts`
- `MEDIAS_POR_PIEZA = 2`
- `piezas_a_medias`
- `medias_a_piezas`
- `es_cantidad_valida`
- `validar_cantidad`

`apps/web/src/domain/rendicion.ts`
- `EntradaEsperado`
- `calcular_esperado`
- `calcular_diferencia`

### Contrato

```
1 pieza   = 2 medias piezas
1/2 pieza = 1 media pieza
```

La cantidad canónica/almacenable es siempre un entero `>= 0` expresado en unidad mínima.

`medias_a_piezas` es solo una conversión de representación y puede devolver fracciones: `1 -> 0.5`, `9 -> 4.5`. Su salida no es una cantidad almacenable.

```
esperado   = cargado - vendido - merma - otras_salidas
diferencia = contado - esperado
```

Si `vendido + merma + otras_salidas > cargado`, `calcular_esperado` lanza `Error` y no devuelve un negativo silencioso: representa una inconsistencia que debe regularizarse de forma trazable (§7.4).

La diferencia sí puede ser negativa: `< 0` faltante, `0` sin diferencia, `> 0` sobrante. No se agregó enum ni clasificación explícita porque no es necesario para esta tarea: el signo alcanza.

### TDD

**Fase RED (observada antes de implementar):**

- Primera iteración: faltaban los módulos `apps/web/src/domain/cantidades.ts` y `rendicion.ts`; las dos suites fallaban con `Cannot find module './cantidades'` y `Cannot find module './rendicion'` (0 tests ejecutados).
- Segunda iteración, al cambiar `medias_a_piezas` para que conserve la cantidad exacta: los tests nuevos fallaron antes de corregir la implementación (`AssertionError: expected +0 to be 0.5` y `AssertionError: expected true to be false`).

**Fase GREEN final** (resultados exactos, desde `apps/web/`):

| Verificación | Resultado |
|---|---|
| `npm test -- --run` | exit 0; `Test Files 4 passed (4)`; `Tests 37 passed (37)` (32 de dominio + 5 preexistentes) |
| `npm run typecheck` | exit 0 |
| `npm run lint` | exit 0 |
| `npm run build` | exit 0; `dist/assets/index-BKH7CK6R.js 394.04 kB │ gzip: 110.55 kB` |
| `git diff --check` | exit 0; sin problemas de whitespace |

Evidencia adicional: se comprobó por mutación que los tests detectan errores reales (quitar el guard de §7.4 en `calcular_esperado` → falla 1 prueba; `Math.floor` → `Math.round` en `medias_a_piezas` → fallan 2 pruebas), restaurando la implementación con hash idéntico al original.

### Archivos

| Archivo | Cambio |
|---|---|
| `apps/web/src/domain/cantidades.ts` | nuevo; cantidades y unidad mínima |
| `apps/web/src/domain/cantidades.test.ts` | nuevo; 18 pruebas |
| `apps/web/src/domain/rendicion.ts` | nuevo; esperado y diferencia |
| `apps/web/src/domain/rendicion.test.ts` | nuevo; 14 pruebas |
| `docs/progress-log.md` | esta entrada |

### Fuera de alcance

- Integración con pantallas; `localStorage`; `movimientos_stock` reales; dinero; Supabase; migraciones; RLS; RPC; `SECURITY DEFINER` / `SECURITY INVOKER`; cualquier decisión P1–P20; cualquier PROPUESTA NO APROBADA.
- **ADR-001 continúa PROPUESTA — NO APROBADA.**
- **No existe persistencia ni seguridad de backend asociada a este dominio:** son funciones puras, sin efectos y sin escrituras. No se afirma que haya persistencia ni control de acceso.

### Riesgos pendientes

1. El dominio todavía no está integrado a pantallas ni a RPC, y no reemplaza la lógica demo existente (por ejemplo `cantidadValida` en `apps/web/src/pages/Rendicion.tsx`).
2. Los identificadores nuevos están en **snake_case** por instrucción explícita de la tarea; `AGENTS.md` §7 fija camelCase en TypeScript (snake_case queda para SQL, Blueprint §8). Divergencia registrada y sin decisión formal todavía.
3. `validar_cantidad(cantidad: number): void` no recibe el nombre del campo, así que el error no indica qué componente falló.
4. `medias_a_piezas` devuelve fracciones: su salida nunca debe usarse como cantidad almacenable ni pasarse a `calcular_esperado` / `calcular_diferencia`.
5. No se registra el hash del commit en esta entrada: el documento forma parte de ese mismo commit, así que el hash se reporta al cerrar la tarea y es el que debe auditarse.
6. `npm run lint` pasa con 0 errores, mientras el incidente `docs/incidents/2026-10-12-lint-falla-en-main.md` registra 10 errores en `main`. No se reprodujo en esta base porque incluye la corrección de lint ya integrada (`chore/corregir-lint`); el incidente no se tocó (fuera de alcance).

---

## 17/10/2026 — Integración de la corrección de lint con la línea documental, tooling y proceso de agentes

**Rama:** `chore/integrar-base-desarrollo` · **Agente:** OpenCode · **Estado:** conflicto resuelto; merge pendiente de commit y auditoría; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Objetivo

Integrar la rama de corrección de lint (`chore/corregir-lint`) con la línea documental, de tooling de calidad y de proceso de agentes (`chore/formalizar-proceso-agentes`).

### Qué se hizo

- Origen: `chore/corregir-lint@28952871793363744d047fa28294c59b586f6e94` y `chore/formalizar-proceso-agentes@d80a09f1fdec220b01eabe92bbcc29317b6cf521`.
- Único conflicto: `docs/progress-log.md`.
- Resolución: unión semántica de ambas bitácoras, sin descartar historial.

### Cómo se verificó

Verificación ya ejecutada durante el merge:

| Verificación | Resultado |
|---|---|
| `npm run lint` | OK |
| `npm run typecheck` | OK |
| Vitest | 5/5 |
| `npm run build` | OK |
| `npx playwright test` | 1/1 |

### Riesgos pendientes

1. La resolución del conflicto está **preparada**; el merge queda **pendiente de commit y auditoría**. No se registra el hash del merge porque todavía no existe.
2. **ADR-001 continúa PROPUESTA — NO APROBADA.**
3. No se autorizan migraciones ni cambios de seguridad funcional.

---

## 17/10/2026 — Cierre del incidente de lint (`chore/corregir-lint`)

**Rama:** `chore/corregir-lint` (creada desde `4cdffb1c159cd17159ff2d0fe0180d391938d973`) · **Agente:** agente de implementación · **Estado:** incidente **resuelto localmente** en esta rama; la rama queda **pendiente de revisión independiente por Codex/OpenCode**; **no hay aprobación de merge a main** — el merge queda reservado a decisión humana posterior a esa revisión.

### Qué se hizo

- Se resolvieron exactamente los 10 errores y 1 advertencia de ESLint del incidente `docs/incidents/2026-10-12-lint-falla-en-main.md`, sin cambios de comportamiento de negocio, stock, dinero, roles ni flujos demo.
- `AuthContext.tsx`: separación estructural sin excepciones ESLint. `usuariosDemo` y tipos demo moved a `src/auth/usuariosDemo.ts`; contexto y tipo a `src/auth/AuthContextValue.ts`; hook `useAuth` a `src/auth/useAuth.ts`. `AuthContext.tsx` exporta solo `AuthProvider`. Los consumidores (`App.tsx`, `ProtectedRoute.tsx`, `AppLayout.tsx`, `Sidebar.tsx`, `Login.tsx`, `ConfiguracionDemo.tsx`) actualizan sus imports explícitamente. No hay re-exportaciones no-componente desde `AuthContext.tsx`.
- `Sidebar.tsx`: eliminado el effect que hacía `setMenuAbierto(false)` al cambiar de ruta (error `react-hooks/set-state-in-effect`). El cierre tras navegar ya lo proveen los handlers `onClick` existentes de cada `NavLink`, más botón X, backdrop y Escape. Sin efecto nuevo ni remount por key. Comportamiento desktop idéntico.
- `hooks/useMovimientos.ts`: `any` reemplazado por predicado `(p: unknown)` con narrowing justificado por la forma runtime de los productos demo (sin aserciones para silenciar el linter).
- Páginas `Autoventa.tsx`, `CuentasCorrientes.tsx`, `Movimientos.tsx`, `Retornos.tsx`: estabilización mínima de dependencias derivadas envolviendo los `.find()`/`.filter()` preexistentes en `useMemo` con sus deps reales. Mismos cálculos, filtros, jornada seleccionada y reglas de aprobación/retorno. En `Movimientos.tsx` la dep correcta de `disponibles` resultó ser `[jornada, salidas]` (agregar `movimientosJornada` fue marcado como innecesario porque `salidas` ya lo porta transitivamente); resultado numérico idéntico y advertencia `exhaustive-deps` resuelta.
- CI: verificado que lint, typecheck, tests y build pasaban localmente, se quitó `continue-on-error: true` del job `lint` de `.github/workflows/ci.yml`; el lint de CI es ahora bloqueante.
- El incidente fue marcado como **cerrado** en su documento, con evidencia de verificación.

### Archivos afectados

| Archivo | Cambio |
|---|---|
| `apps/web/src/auth/usuariosDemo.ts` | nuevo; datos y tipos demo de autenticación |
| `apps/web/src/auth/AuthContextValue.ts` | nuevo; contexto y tipo |
| `apps/web/src/auth/useAuth.ts` | nuevo; hook de acceso al contexto |
| `apps/web/src/AuthContext.tsx` | modificado; exporta solo `AuthProvider` |
| `apps/web/src/App.tsx`, `components/ProtectedRoute.tsx`, `components/layout/AppLayout.tsx`, `components/layout/Sidebar.tsx`, `pages/Login.tsx`, `pages/ConfiguracionDemo.tsx` | modificados; imports actualizados |
| `apps/web/src/components/layout/Sidebar.tsx` | modificado; cierre de menú por handler, sin effect |
| `apps/web/src/hooks/useMovimientos.ts` | modificado; type guard en lugar de `any` |
| `apps/web/src/pages/Autoventa.tsx`, `CuentasCorrientes.tsx`, `Movimientos.tsx`, `Retornos.tsx` | modificados; estabilización de deps vía `useMemo` |
| `.github/workflows/ci.yml` | modificado; job `lint` bloqueante |
| `docs/incidents/2026-10-12-lint-falla-en-main.md` | modificado; estado cerrado con evidencia |
| `docs/progress-log.md` | esta entrada |

### Cómo se verificó y resultados exactos

- `npm run lint` → exit 0; 0 errores, 0 advertencias (baseline del incidente: 10 errores + 1 advertencia).
- `npm run typecheck` (`tsc -b`) → exit 0.
- `npm test` (Vitest) → exit 0; 2 archivos de prueba, 5/5 pruebas pasan.
- `npm run build` (`tsc -b && vite build`) → exit 0; bundle generado sin errores.
- `git diff --check` → sin problemas de whitespace.
- Playwright no se ejecutó: fuera del área afectada (los cambios son mecánicos de linting sobre componentes/páginas existentes sin nuevos flujos E2E); no se amplió el scope para instalar browsers.

### Riesgos conocidos

1. No hay tests E2E que cubran específicamente el flujo "cerrar menú móvil al navegar"; verificación fue estática + smoke de build/tests. Riesgo bajo porque los handlers `onClick` preexistentes ya hacían el cierre.
2. El hash del bundle cambia respecto del baseline (esperable al editar código).
3. El job `lint` bloqueante de CI no ha corrido aún en GitHub Actions; se ejercitará en el primer PR desde esta rama.
4. `aprobados` en `Retornos.tsx` sigue siendo objeto de estado mutado con spread; sus deps `[jornada, aprobados]` ahora son estables en la parte de `jornada` — semántica inalterada.

### Fuera de alcance confirmado

- ADR-001 permanece en estado `propuesta` y no fue tocada: sin migraciones, SQL, RLS, RPC, grants ni arquitectura de base de datos.
- Sin nuevas dependencias; sin refactor de archivos no relacionados; sin cambios en reglas de negocio, roles ni lógica de stock/dinero.

---

## 17/10/2026 — Formalización del proceso de agentes en `AGENTS.md` y `CLAUDE.md`

**Rama:** `chore/formalizar-proceso-agentes` (base `30b831650cf7108584052b13cc6c32b71a1b31b9`) · **Agente:** OpenCode · **Estado:** cambios preparados, pendientes de commit y auditoría; **ADR-001 sigue PROPUESTA — NO APROBADA**

### Objetivo

Formalizar en `AGENTS.md` y `CLAUDE.md` las convenciones operativas ya documentadas y auditadas en `docs/quality/` (ciclo de trabajo, reglas de auditoría, superficies de security review y tooling), **sin crear reglas funcionales nuevas**.

### Qué se hizo

- `AGENTS.md` §2 se amplía con el ciclo de trabajo, las reglas obligatorias del ciclo, las superficies que disparan security review y el tooling. Se conserva el flujo entre agentes y todas las reglas previas.
- `CLAUDE.md`: se explicita que Claude es implementador y no auditor final, se ordena el procedimiento (Blueprint/ADR antes de implementar, rama propia, alcance autorizado, lint/typecheck/tests/build, Playwright, auditoría independiente, no autoaprobar, no merge/deploy, nuevo hash tras corregir), y se agregan las advertencias de superficies sensibles y de no aprobar ADR-001 ni resolver P1–P20.
- `docs/quality/review-process.md`: corrección mínima en §3.7 para reflejar que el máximo de 3 ciclos y la security review obligatoria, nacidas como convenciones operativas, quedan además **formalizadas en `AGENTS.md`**; el documento sigue describiendo el proceso y no reemplaza `AGENTS.md`.
- `docs/progress-log.md`: esta entrada.

### Archivos

| Archivo | Cambio |
|---|---|
| `AGENTS.md` | §2 ampliada (ciclo, reglas del ciclo, superficies de security review y tooling) |
| `CLAUDE.md` | procedimiento, superficies sensibles y límites del implementador |
| `docs/quality/review-process.md` | §3.7: formalización de las dos convenciones operativas en `AGENTS.md` |
| `docs/progress-log.md` | esta entrada |

### Alcance: lo que esta tarea NO cambia

- No se modifica `BLUEPRINT.md` (sigue v1.4).
- **ADR-001 sigue PROPUESTA — NO APROBADA**; **P1–P20 siguen pendientes de aprobación humana**.
- No se aprueba ni se implementa ninguna propuesta pendiente.
- No se tocan ADR, `docs/PRD.md`, el resto de `docs/quality/**` (`security-review.md`, `browser-testing.md`), código, `package.json`/lockfiles, SQL, `supabase/migrations`, RLS, RPC, auth, grants ni workflows de CI.

### Cómo se verificó

- `git diff --check` (sin errores de whitespace), `git diff --stat` y `git status --short`: solo cambian las cuatro rutas autorizadas. No se ejecutaron typecheck, tests, Playwright ni build porque no hay cambios de código.

### Riesgos pendientes

1. Los cambios están **preparados y sin commitear**; el commit deberá auditarse sobre su propio hash antes de push y merge (`docs/quality/review-process.md` §3.3).
2. **No se registra hash nuevo** porque el commit todavía no existe.
3. **ADR-001 sigue PROPUESTA — NO APROBADA** y **P1–P20 siguen pendientes**.
4. Claude `/code-review` y `/security-review` siguen **pendientes/opcionales por disponibilidad actual**: se documentan como tales, no como herramientas obligatoriamente disponibles.

---

## 17/10/2026 — Tooling de calidad ya auditado y corrección documental del proceso de revisión

**Rama:** `chore/herramientas-calidad` · **Agente:** Claude Code · **Estado:** correcciones documentales **preparadas y pendientes de commit**; ADR-001 sigue **PROPUESTA — NO APROBADA**

### Herramientas de calidad incorporadas (commit ya auditado y aprobado)

Commit de tooling: `54f393490471a45214577d618034f3ea05a99518`

Resultado de la auditoría del tooling: **APPROVED**.

- Herramientas incorporadas: skill `grilling` y Playwright CLI `0.1.22`.
- Observaciones de la auditoría del tooling `54f3934…`, todas **no bloqueantes** (no confundir con los `L-1…L-7` de la auditoría final, que figuran más abajo):
  - **L-1:** preaprobación de comandos Playwright.
  - **L-2:** `run-code` puede ejecutar JavaScript en el contexto del navegador.
  - **L-3:** trazabilidad upstream/npm de `0.1.22` verificada, sin riesgo.

### Documentación creada y auditoría final

Commit documental: `9e589264fdd427ebe21d174d61b37c4c86e173cc`

- `docs/PRD.md`
- `docs/quality/review-process.md`
- `docs/quality/security-review.md`
- `docs/quality/browser-testing.md`

Commit de corrección documental: `bec986e695e27dec6f0c1892c21a45061ce624a9`

**Auditoría final de `bec986e…`: APPROVED WITH CORRECTIONS.** El conjunto documental no modificó `BLUEPRINT.md`, `AGENTS.md`, `CLAUDE.md`, ADR-001, código, SQL, migraciones, RLS, RPC, grants ni workflows.

### Qué se hizo en esta tarea

Corrección documental mínima en `docs/quality/review-process.md`, §2.1: «ADR vigente a la fecha» pasa a «Versión documental actual de ADR-001»; se conserva el resto de la oración (v1.2, ronda 3, estado `propuesta` — NO APROBADA, P1–P20 pendientes, P19 y P20 primero según la propuesta, y P18 como decisión separada que no es requisito previo). Se agrega esta entrada de bitácora.

**Correcciones de la auditoría final (preparadas, pendientes de commit).** El commit `bec986e695e27dec6f0c1892c21a45061ce624a9` fue auditado con veredicto **APPROVED WITH CORRECTIONS**. Sus hallazgos no bloqueantes **M-1, M-2 y L-1 a L-7 de la auditoría final** originan este commit documental de seguimiento:

| Hallazgo | Corrección aplicada |
|---|---|
| **M-1** | `browser-testing.md` §2: se documenta `npm run dev -- --host 127.0.0.1 --port 4173 --strictPort` para usar 4173, y se aclara que `npm run dev` a secas sirve el puerto de Vite (5173 por defecto), que 4173 proviene del `webServer` del E2E y que en ese caso hay que reemplazar la URL en todos los comandos. |
| **M-2** | `browser-testing.md` §7: la tabla deja de afirmar cobertura en CI. Dice «reproducible en cada corrida local» y que **hoy el CI no ejecuta Playwright**; se agrega nota: agregar Playwright al CI es una tarea separada y requiere autorización. |
| **L-1** | `review-process.md`: el máximo de 3 ciclos y la obligatoriedad de la security review quedan identificados como **convenciones operativas de este proceso, aprobadas por el humano en esta tarea**, no heredadas de `AGENTS.md`/Blueprint (§2.8, §3.4 y nueva regla §3.7). `AGENTS.md` no se modifica. |
| **L-2** | `PRD.md`: los identificadores tomados de Blueprint §8 (`movimientos_stock`, `auditoria`, `idempotency_key`, estados de nota) se marcan como **modelo de datos propuesto** con remisión a ADR-001 §3.2; no se presentan como DDL aprobado. |
| **L-3** | `PRD.md` §17: el criterio «el wrapper rechaza `anon`…» se conserva como criterio heredado del Blueprint, con nota de que depende de **P1**, no implica aprobación de la topología wrapper y no autoriza implementación ni migraciones. |
| **L-4** | `review-process.md` §2.7 y la cadena de §1: «code review (disponible)» pasa a «humana / independiente»; se aclara que `/code-review` de Claude está pendiente/opcional y que no existe una compuerta automática garantizada. |
| **L-5** | `browser-testing.md`: el ignore de `.playwright-cli/` se cita por su fuente directa (`.gitignore:57-58`); `AGENTS.md` §5 se menciona solo por el principio de no versionar secretos/estado sensible. |
| **L-6** | `PRD.md` RNF-11: cita corregida a `Blueprint §13, regla 4` + `AGENTS.md §6.4`, con la salvedad «aplicable cuando exista autorización de migraciones»; no insinúa que hoy corresponda migrar. |
| **L-7** | Esta entrada: registra el hash auditado `bec986e…`, el veredicto y el origen de las correcciones de seguimiento. |

Estas correcciones son **solo documentales**: no cambian reglas de negocio, no aprueban ADR-001 ni ninguna P1–P20 y no modifican el perfil de seguridad. No se registra el hash del commit de seguimiento porque **todavía no existe**.

### Alcance: lo que esta tarea NO autoriza

- no autoriza migraciones;
- no aprueba RLS;
- no aprueba RPC privilegiadas;
- no cambia grants;
- no cambia auth;
- no cambia reglas de stock ni de dinero;
- no modifica código de aplicación.

### Revisiones de Claude pendientes

- Claude `/code-review`: **pendiente/opcional** por falta de disponibilidad actual.
- Claude `/security-review`: **pendiente/opcional** por falta de disponibilidad actual.

### Archivos

| Archivo | Cambio |
|---|---|
| `docs/quality/review-process.md` | corrección de redacción en §2.1; §1, §2.7, §2.8, §3.4 y nueva §3.7 (convenciones operativas y code review sin ambigüedad) |
| `docs/quality/browser-testing.md` | §2 (procedimiento de puerto), §7 (cobertura en CI) y cita del ignore de `.playwright-cli/` |
| `docs/PRD.md` | RNF-11; marca de modelo de datos propuesto (§10, §14, §16); nota de dependencia P1 en §17; historial 0.3 |
| `docs/progress-log.md` | esta entrada |

Sin otros archivos modificados: no se tocaron `BLUEPRINT.md`, `AGENTS.md`, `CLAUDE.md`, ADR-001, `docs/quality/security-review.md`, código, SQL, migraciones, workflows, `package.json` ni lockfiles.

### Cómo se verificó

- `git diff --check` (sin errores de whitespace), `git diff --stat` y `git status --short`: solo cambian las rutas documentales autorizadas. No se ejecutaron typecheck, tests, Playwright ni build porque no hay cambios de código.

### Riesgos pendientes

1. Las correcciones de este seguimiento están **preparadas y sin commitear**; el nuevo commit deberá auditarse sobre su propio hash antes de push y merge (`review-process.md` §3.3).
2. **ADR-001 sigue PROPUESTA — NO APROBADA.** Esta tarea no cambia su estado.
3. **P1–P20 siguen pendientes de aprobación humana.**
4. **No se autoriza ningún cambio de base de datos ni de seguridad funcional**: migraciones, RLS, RPC, grants, auth, `empresa_id`, stock y dinero quedan fuera del alcance de esta tarea.
5. No existe una compuerta automática de code/security review garantizada: `/code-review` y `/security-review` de Claude continúan **pendientes/opcionales** por falta de disponibilidad actual.

---

## 17/10/2026 — ADR-001, ronda 3: correcciones de la segunda revisión de Codex (sigue PROPUESTA — NO APROBADA)

**Rama:** `docs/adr-001-revision` (base `4cdffb1c159cd17159ff2d0fe0180d391938d973`) · **Agente:** Claude Code · **Estado:** commiteado inicialmente como `405bf94810d8640059e7d50ea142e299138db2a4`; auditoría final realizada; pendiente de push y merge; **no existe aprobación humana de ADR-001**

### Revisión de Codex sobre la ronda 2

Veredicto: **CHANGES REQUIRED**, con 4 hallazgos (transmitidos por el usuario; el informe no está en el repositorio):

1. La redacción podía leerse como si Supabase admitiera, con condiciones, una función `SECURITY DEFINER` en un esquema expuesto.
2. La secuencia de gobernanza exigía P2–P18 antes de la validación controlada: incluía P18 (decisión futura separada) y omitía P19 y P20.
3. `auth.uid()` dentro de `SECURITY DEFINER` y el rol `authenticated` de los usuarios anónimos figuraban como incertidumbres de la documentación, aunque Supabase los documenta.
4. La ADR decía que Supabase no había confirmado la fecha del cambio de exposición automática.

### Correcciones aplicadas (solo en `docs/decisions/001-rpc-privilegiadas.md`)

1. **Secciones 4, 5 y 19:** la topología C coincide con el texto literal de `BLUEPRINT.md` §10:277, pero la guía vigente de Supabase (*Row Level Security*, "Never create one in a schema listed under 'Exposed schemas'") prohíbe explícitamente crear funciones `SECURITY DEFINER` en un esquema expuesto. C **no es un diseño recomendado por el proveedor**; sigue en la comparación solo porque el Blueprint apunta en esa dirección. Aceptar las advertencias 0028/0029 no implica aval de Supabase. El conflicto requiere decisión humana explícita (P1).
2. **Secciones 15 y 18:** la secuencia empieza con un paso 0 de gobernanza (decidir P19, resolver P20 y alinear los documentos rectores). Solo después se enumeran las decisiones técnicas necesarias para una validación controlada local o en staging (P1–P17, según el alcance que se ensaye). P18 queda excluida como requisito previo. Se aclara que hoy no está autorizada ninguna implementación, ni siquiera controlada.
3. **Sección 17.1:** `auth.uid()` en `SECURITY DEFINER` y el rol `authenticated` de los usuarios anónimos (claim `is_anonymous`) pasan a "comportamiento documentado por Supabase que igualmente debe probarse como regresión en nuestro entorno". `pg_graphql` queda como dependiente de la configuración del proyecto.
4. **Sección 17.2:** fecha oficial del proveedor según el anuncio de Supabase (discusión n.º 45329): default en proyectos nuevos desde el 30/05/2026 y aplicación a todos los proyectos existentes el **30/10/2026**. Se separa de la verificación propia de esquemas expuestos, grants y comportamiento en cada entorno.

También se actualizaron el encabezado (revisión 17/10/2026, ronda 3), el historial (sección 0) y las fuentes (sección 21). En `docs/decisions/README.md` solo cambió la referencia "ronda 2" → "ronda 3"; el estado sigue siendo PROPUESTA — NO APROBADA.

### Archivos

| Archivo | Cambio |
|---|---|
| `docs/decisions/001-rpc-privilegiadas.md` | ronda 3 de correcciones documentales |
| `docs/decisions/README.md` | referencia de ronda |
| `docs/progress-log.md` | esta entrada |

Sin SQL, migraciones, schemas, roles, grants, RLS, RPC ni cambios de seguridad. No se modificaron `BLUEPRINT.md`, `AGENTS.md`, `CLAUDE.md` ni código de aplicación.

### Cómo se verificó

- Las cuatro afirmaciones se contrastaron el 17/10/2026 con las fuentes oficiales: *Row Level Security*, *Database Functions*, *Securing your API*, *Hardening the Data API*, *Anonymous Sign-Ins* y la discusión oficial n.º 45329 de Supabase. Las páginas de documentación no indican la fecha; esta surge del anuncio oficial.
- `git diff --check`, `git status --short` y `git diff --stat`: solo cambian las tres rutas autorizadas. No se ejecutaron typecheck, tests, Playwright ni build porque no hay cambios de código.

### Riesgos pendientes

1. **ADR-001 sigue NO aprobada.** Esta ronda no autoriza ninguna implementación, ni siquiera local o en staging.
2. Siguen pendientes las veinte decisiones P1–P20, con P19 y P20 primero.
3. Hay que elegir entre el texto literal del Blueprint (C) y la guía explícita de Supabase (D u otra). Es una decisión humana.
4. La ronda 3 necesita una nueva revisión independiente sobre el commit que se cree (`AGENTS.md` §2).


### Auditoría final del commit documental

Commit auditado: `405bf94810d8640059e7d50ea142e299138db2a4`

Veredicto: **APPROVED WITH CORRECTIONS**.

La auditoría confirmó que el commit contiene únicamente los tres archivos
documentales autorizados, que ADR-001 continúa en estado
**PROPUESTA — NO APROBADA**, y que no incorpora SQL, migraciones, RLS, RPC
ni código de aplicación.

Se detectaron dos observaciones menores y no bloqueantes:

1. La bitácora todavía indicaba que la ronda 3 estaba “sin commitear”.
   Esta entrada actualiza el estado real del trabajo.
2. El historial de la ADR omitía la sección 18 en la enumeración de secciones
   modificadas por la ronda 3. Se agregó esa referencia.

Estas correcciones son exclusivamente documentales y no aprueban ninguna de
las decisiones P1–P20 ni modifican el perfil de seguridad de la propuesta.

---

## 16/10/2026 — Revisión documental de ADR-001 (sigue PROPUESTA — NO APROBADA)

**Rama:** `docs/adr-001-revision` (creada desde `4cdffb1c159cd17159ff2d0fe0180d391938d973`) · **Agentes:** OpenCode (ronda 1), Claude Code (ronda 2) · **Estado:** sin commitear; ronda 2 pendiente de nueva revisión independiente; **no existe aprobación humana de ADR-001**

### Secuencia de la tarea

1. **Ronda 1 (OpenCode):** ampliación documental de ADR-001 a v1.2 (detalle abajo, conservado como registro).
2. **Revisión independiente de Codex** sobre la ronda 1: veredicto **CHANGES REQUIRED**, con 12 correcciones obligatorias (las transmitió el usuario; el informe de Codex no está en el repositorio).
3. **Ronda 2 (Claude Code, actual):** aplica las 12 correcciones (detalle abajo).

### Ronda 2 — correcciones aplicadas

1. **Topología:** se reconoce el conflicto entre el wrapper `SECURITY DEFINER` expuesto de `BLUEPRINT.md` §10:277 y la guía vigente de Supabase (preferir `SECURITY INVOKER`; lints 0028/0029). Se comparan neutralmente A/B/C y una nueva alternativa D (fachada `SECURITY INVOKER` expuesta + implementación privilegiada en esquema no expuesto). C deja de figurar como recomendada; la única preferencia queda marcada **RECOMENDACIÓN NO VINCULANTE**.
2. **Transacciones y Edge Functions:** varias llamadas independientes a la Data API no forman una transacción; con una única RPC, esa RPC es la unidad atómica; `service_role` solo como excepción justificada, porque elude RLS.
3. **Gobernanza:** se documenta como propuesta la secuencia aprobación para prueba controlada → implementación local/staging → pruebas → segunda aceptación antes de producción. Requeriría alinear `BLUEPRINT.md` §10:279, §15:433 y la plantilla de estados de ADR si se aprueba.
4. **Jerarquía:** se retira la "contradicción" Blueprint/AGENTS de la ronda 1. Rige la regla estricta del Blueprint; el alcance de §10:279 se registra como ambigüedad (P20).
5. **Ownership y RLS:** se incorpora que el propietario de una tabla normalmente elude RLS aunque no tenga `BYPASSRLS`; ownership, `FORCE RLS` y RLS como defensa en profundidad o elusión deliberada quedan pendientes (P4).
6. **Multiempresa:** invariante de que ninguna relación cruza empresas, restricciones verificables y pruebas con IDs mezclados entre empresas; sin DDL.
7. **Auditoría e idempotencia:** la tabla `auditoria` y las columnas `idempotency_key` pasan a "modelo propuesto" (§8 se titula "Modelo de datos (propuesto)"); solo la trazabilidad y la idempotencia como propiedades quedan como aprobadas.
8. **Contrato de idempotencia:** I1–I8 enumerados como pendientes.
9. **Grants:** requisitos de diseño (USAGE, firma exacta, sobrecargas, PUBLIC, misma transacción, rol creador real). Se corrige el error técnico de v1.1: un `REVOKE` de privilegios por defecto hecho por esquema no elimina el `EXECUTE` global de `PUBLIC` (PostgreSQL 18, ALTER DEFAULT PRIVILEGES).
10. **Verificación:** separada en comportamiento documentado a probar (incluye `search_path = ''`, ya no presentado como incógnita), propiedades dependientes del entorno y regresión; la concurrencia puede probarse primero en local.
11. **Contexto:** la frase "La interfaz React usa la Supabase Data API" pasa a futuro ("usará").
12. **Bitácora:** esta sección.

Fuentes oficiales consultadas y citadas en la sección 21 de la ADR (PostgreSQL 18, Supabase y PostgREST v14).

### Ronda 1 — qué se hizo (registro histórico)

- Se revisó y amplió **solo la documentación** de ADR-001, que permanece en estado **PROPUESTA — NO APROBADA**.
- Se incorporaron de forma explícita: requisitos ya aprobados por el Blueprint; alternativas A/B/C; propietario y relación con RLS; aislamiento multiempresa; autorización; idempotencia; concurrencia y locks; grants y default privileges; contrato de errores; auditoría; matriz de pruebas; verificaciones pendientes de staging; y consecuencias sobre `BLUEPRINT.md` si se aprobara una alternativa incompatible.
- Toda decisión no definida por `BLUEPRINT.md` ni por una ADR aprobada quedó marcada **PENDIENTE DE APROBACIÓN HUMANA** (sección 5 de la ADR, puntos P1–P11), con recomendación **no vinculante**.
- Lo no verificable documentalmente quedó como **A VERIFICAR EN STAGING** (sección 15 de la ADR).
- **No se aprobó ADR-001** ni se implementó nada: sin código, SQL, migraciones, schemas, roles, grants, Supabase ni configuración de agentes.

### Archivos

| Archivo | Cambio |
|---|---|
| `docs/decisions/001-rpc-privilegiadas.md` | revisión documental (v1.2, rondas 1 y 2); estado PROPUESTA — NO APROBADA |
| `docs/decisions/README.md` | índice: versión 1.2, etiqueta de estado y referencia a P1–P20 (sección 18) |
| `docs/progress-log.md` | esta entrada |

No se modificó `BLUEPRINT.md`, `AGENTS.md`, `CLAUDE.md`, código de aplicación, SQL, migraciones, schemas, roles, grants ni Supabase.

### Cómo se verificó

- Ronda 1: cotejo de la ADR contra `BLUEPRINT.md` §3, §6, §7.3, §7.4, §7.5, §7.6, §8, §9, §10, §12, §13 y §15, y contra `AGENTS.md` §3 y §5; `git diff --check`.
- Ronda 2: citas de línea del Blueprint revisadas contra `BLUEPRINT.md` v1.4; afirmaciones de PostgreSQL, Supabase y PostgREST contrastadas con la documentación oficial (sección 21 de la ADR); `git diff --check` sin observaciones; `git status` confirma que solo cambiaron las tres rutas autorizadas. No se ejecutaron typecheck, tests ni build: no hay cambios de código.

### Riesgos pendientes

1. **ADR-001 sigue NO aprobada** y no existe aprobación humana en ninguna de sus formas. Rige la lectura estricta de `BLUEPRINT.md` §10:279: ninguna migración hasta aprobar ADR-001 y pasar las pruebas de autorización.
2. *(Retirado en la ronda 2.)* La ronda 1 registraba una "contradicción" entre `BLUEPRINT.md` §10:279 y `AGENTS.md` §3. Se reclasifica como **ambigüedad de alcance** del texto del Blueprint (P20 de la ADR); el Blueprint, de mayor jerarquía, rige.
3. Veinte decisiones quedan **PENDIENTE DE APROBACIÓN HUMANA** (P1–P20, sección 18 de la ADR), entre ellas la topología (P1) y la propuesta de gobernanza (P19).
4. Fuentes oficiales que difieren: la guía *Hardening the Data API* de Supabase muestra un `REVOKE ... FROM PUBLIC` por esquema que, según PostgreSQL 18, no tiene efecto. Hay que resolverlo con una prueba de catálogo cuando se autorice.
5. El informe de Codex (CHANGES REQUIRED) no está archivado en el repositorio; la ronda 2 se basó en las 12 correcciones transmitidas por el usuario.
6. La ronda 2 requiere una nueva revisión independiente sobre el commit que se cree (`AGENTS.md` §2).

---

## 16/10/2026 — Instalación reproducible de dos Agent Skills compartidas

**Rama:** `chore/skills-agentes` (creada desde `607394c87ec62150da6bed9c90f3749c575612e8`) · **Agente:** Codex · **Estado:** sin commitear; correcciones documentales de auditoría aplicadas; pendiente de nueva revisión independiente y aprobación humana

### Qué se hizo

- Se incorporaron únicamente `source-driven-development` y `api-and-interface-design` desde `addyosmani/agent-skills`, tag `0.6.13`, commit inmutable `aeac41d4d005999432bb7312f7ff06383a91d59d`.
- La copia canónica del repositorio quedó en `.agents/skills/`; Claude Code accede mediante dos enlaces simbólicos relativos desde `.claude/skills/`.
- Se agregó `.agents/skills/UPSTREAM.md` con fuente, versión, commit, hashes, método de instalación, precedencia de instrucciones y la excepción de estabilidad aprobada para `0.6.13`.
- La versión upstream `0.6.13` tenía menos de las dos semanas preferidas por `AGENTS.md` §6.8 al instalarse. El usuario aprobó expresamente esta excepción limitada porque corrige el ejemplo JavaScript inválido de una versión anterior (`throw;` → `throw e;`).
- No se eliminaron ni modificaron skills o plugins globales. No se actualizó Superpowers ni se instalaron paquetes.

### Resultado de la auditoría independiente de OpenCode

- La auditoría no requirió cambios en las dos skills instaladas, sus hashes ni sus enlaces; identificó correcciones documentales menores.
- Se documentó `.agents/skills/` y su propósito en `AGENTS.md` §8.
- Se aclaró en `UPSTREAM.md` que las referencias a `security-and-hardening` y `deprecation-and-migration` son opcionales y no son dependencias de ejecución; que `source-driven-development` puede consultar documentación oficial externa; que las copias del repositorio prevalecen sobre copias globales divergentes; y que los symlinks pueden fallar en entornos sin soporte, incluidos ciertos checkouts de Windows.
- `AGENTS.md` §6.9 exige registrar decisiones e incidentes relevantes, pero no exige un documento de decisión separado para esta excepción de tooling; no se creó una ADR.

### Archivos

| Archivo | Cambio |
|---|---|
| `.agents/skills/source-driven-development/SKILL.md` | nuevo; copia exacta del upstream fijado |
| `.agents/skills/api-and-interface-design/SKILL.md` | nuevo; copia exacta del upstream fijado |
| `.agents/skills/UPSTREAM.md` | nuevo; procedencia y verificación reproducible |
| `.claude/skills/source-driven-development` | nuevo; enlace relativo a `../../.agents/skills/source-driven-development` |
| `.claude/skills/api-and-interface-design` | nuevo; enlace relativo a `../../.agents/skills/api-and-interface-design` |
| `AGENTS.md` | documenta el directorio compartido `.agents/skills/` en §8 |
| `docs/progress-log.md` | esta entrada |

### Cómo se verificó

- Descarga previa a un directorio temporal mediante el helper de `skill-installer`; contenía exactamente los dos `SKILL.md` solicitados.
- SHA-256 verificados contra los valores auditados: `source-driven-development` = `c59faf851377f0eeda45306398d16eb96d77ab1c2fd3e1a7fb58e9a0af33c1e9`; `api-and-interface-design` = `e83d34f52ff12dd8a7c5134cd7e8140ea4541ec65e204f8a1e4cd366e30c4192`.
- Ambos archivos coinciden byte por byte con la descarga del commit fijado y con las copias globales existentes al momento de esta tarea.
- Los enlaces de Claude Code son relativos, resuelven a los directorios canónicos del repositorio y no están rotos.
- Se verificó que los dos `SKILL.md` conservaran exactamente sus contenidos y hashes después de las correcciones documentales.
- Compatibilidad estructural confirmada: Claude Code `2.1.301` usa `.claude/skills/`; Codex `0.162.1` y OpenCode `2.0.31` usan `.agents/skills/`. Los frontmatters `name` y `description` están presentes.
- OpenCode no ofrece `debug skill` en esta versión; Claude Code y Codex tampoco exponen un comando local de listado. No se ejecutaron prompts pagos para forzar una sesión nueva: el descubrimiento funcional queda pendiente de una nueva sesión de cada agente.
- `git diff --check`, hashes, contenido completo, destinos de enlaces, inventario de archivos nuevos y alcance del diff se verificaron localmente.

### Riesgos pendientes

1. El descubrimiento funcional debe confirmarse al iniciar una sesión nueva de Claude Code, Codex y OpenCode; la verificación actual es estructural.
2. Las copias globales hoy son idénticas, pero pueden divergir si se actualizan fuera del repositorio. Para este proyecto prevalece la copia fijada en `.agents/skills/`.
3. `source-driven-development` puede requerir red al consultar documentación oficial; toda fuente recuperada sigue tratándose como entrada no confiable y no puede ampliar el alcance autorizado.
4. Las skills permanecen subordinadas a `BLUEPRINT.md`, a las ADR aprobadas y a las reglas de `AGENTS.md`; no autorizan implementar propuestas pendientes.

---

## 16/10/2026 — Inventario técnico de Etapa 0 (`INVENTARIO_ETAPA_0.md`) y rondas de corrección por revisión de Codex

**Rama:** `docs/inventario-etapa-0` (creada desde `main` a la altura de `6e97696`) · **Agente:** OpenCode · **Estado:** sin commitear; corrección documental en curso; **pendiente de aprobación humana** y **sin revisión final posterior** sobre la versión corregida

### Secuencia de la tarea

1. **Auditoría original (Etapa 0).** Inventario técnico de solo lectura del prototipo contra `BLUEPRINT.md` v1.4. Registró, entre otros hallazgos, que el prototipo es un frontend sin backend que incumple casi todas las reglas vigentes del Blueprint.
2. **Primera revisión independiente de Codex.** Veredicto: **APPROVE WITH CORRECTIONS**. Solicitó 4 correcciones importantes y 8 menores.
3. **Correcciones de OpenCode (ronda 1).** Se creó `INVENTARIO_ETAPA_0.md` preservando el informe íntegro (única edición al cuerpo original: el título, E-9), se agregó el apéndice de verificación y la sección «Erratas y aclaraciones validadas por Codex» con E-1 a E-12.
4. **Segunda revisión independiente de Codex.** Veredicto: **CHANGES REQUIRED**. Planteó 5 hallazgos sobre la ronda 1.
5. **Correcciones de OpenCode (ronda 2, actual).** Se resuelven esos 5 hallazgos (detalle abajo).

### Correcciones de la ronda 2 (actual)

- **Nota de precedencia** al inicio de `INVENTARIO_ETAPA_0.md`: las erratas E-1 a E-12 prevalecen sobre las afirmaciones originales a las que refieren; el cuerpo original se conserva solo como registro histórico; en caso de contradicción manda la errata, subordinada a `BLUEPRINT.md` y a las ADR aprobadas.
- **E-1 ampliada:** se preserva la afirmación histórica «ninguna tarea de base de datos puede avanzar» y se **supersede**. Documentación, análisis arquitectónico, pruebas independientes y diseño no dependiente **pueden continuar**; las **migraciones** y la implementación dependientes de la arquitectura propuesta de **RPC privilegiadas** **siguen bloqueadas** hasta la aprobación correspondiente.
- **E-3 ampliada** a §19 paso 5: reemplazar los ocho hooks por RPC **no es** un requisito arquitectónico aprobado; las RPC son exigibles para las escrituras críticas de stock y dinero, mientras las lecturas ordinarias y el CRUD permitido pueden usar RLS y `SECURITY INVOKER`.
- **E-4 ampliada** a §19 paso 2: cantidades enteras en la unidad mínima y conversión pieza/media pieza **ya definidas**; solo quedan pendientes el precio de la media pieza y el redondeo.
- **Consistencia en la bitácora:** la afirmación amplia de una entrada anterior («Ninguna tarea de base de datos puede avanzar hasta su aprobación», en los riesgos de la tarea «Inventario de Etapa 0 ausente») queda **igualmente superada** por E-1. Se conserva como registro histórico de esa tarea y **no se reescribe**.
- **Apéndice actualizado:** la subsección pasa a «Revisiones independientes (Codex)» y registra ambas revisiones, la ronda 2 en curso y el hecho de que la versión corregida **no pasó aún una revisión final**.

### Qué se hizo (acumulado)

- `INVENTARIO_ETAPA_0.md` (nuevo): informe preservado + apéndice de verificación + erratas E-1 a E-12 + nota de precedencia.
- `docs/progress-log.md`: esta entrada.
- **No se implementó ninguna recomendación del informe.** Sin cambios en código de aplicación, SQL, migraciones, dependencias ni configuración de agentes.

### Archivos

| Archivo | Cambio |
|---|---|
| `INVENTARIO_ETAPA_0.md` | nuevo (informe preservado + verificación + erratas E-1 a E-12 + precedencia) |
| `docs/progress-log.md` | esta entrada |

Sin otros archivos creados, modificados ni borrados. `informe_temporal.txt` no existe en el repositorio (no fue creado ni eliminado por esta tarea); la fuente usada fue el informe recibido en la conversación.

### Cómo se verificó

- Referencias del informe cotejadas contra el estado real del repositorio: `git rev-parse HEAD` = `6e97696…`, `git ls-files` = 73, `git tag` = 0, rutas, rangos de línea y citas de `BLUEPRINT.md`.
- `git diff --check` sin problemas; diff final inspeccionado (archivo nuevo incluido vía `git add -N`, revertido después para no dejar nada preparado).
- Confirmado que solo se crearon/modificaron `INVENTARIO_ETAPA_0.md` y `docs/progress-log.md`.

### Riesgos pendientes

1. **La versión corregida NO pasó aún una revisión final.** La segunda revisión de Codex terminó en **CHANGES REQUIRED**; la ronda 2 está sin revisar. No debe interpretarse como aprobada.
2. **Aprobación humana pendiente** para commit, push, merge o deploy.
3. **Fuente del informe:** `informe_temporal.txt` no estaba disponible; el texto se tomó de la conversación y no pudo cotejarse contra un archivo.
4. **Discrepancias DC-1 a DC-4:** quedan documentadas pero **sin corregir** en el cuerpo del informe (preservación histórica).
5. **ADR-001 sigue en `propuesta`** y 5 reglas siguen `PROPUESTA NO APROBADA` en `BLUEPRINT.md` v1.4. Según la interpretación vigente (errata E-1), las **migraciones** y la implementación dependientes de la arquitectura propuesta de RPC privilegiadas siguen bloqueadas; el resto del trabajo documental, de análisis, de pruebas independientes y de diseño no dependiente puede continuar.
6. **Ítems §18.19, §18.21 y §18.22** (root de Vercel, ejecución real del CI en GitHub y versiones en el registro npm) siguen sin verificar por quedar fuera del repositorio.

---

## 12/10/2026 — Cierre de configuración de herramientas (Claude Code, OpenCode, Vitest, Playwright)

**Rama:** `chore/configuracion-agentes` (creada desde `eae777f`, mismo commit que `chore/tarea-001-preparar-repo`; 1 commit por delante de `main`) · **Agente:** Claude Code · **Estado:** sin commitear, pendiente de aprobación humana para commit y posterior auditoría (Codex / OpenCode)

### Qué se hizo

Cambios preparados por el usuario (en stage) y verificados en esta sesión; Claude Code solo agregó esta entrada de bitácora.

- `.claude/settings.json`: `permissions.defaultMode: "default"`.
- `opencode.json` + `.opencode/agents/auditor.md`: permisos `ask` para edit/bash/external_directory; subagente auditor de solo lectura (`edit: deny`, `bash: deny`).
- Vitest: `apps/web/vitest.config.ts` (solo `src/**/*.test.ts(x)`, excluye `tests/`) y prueba de humo `src/tests/smoke.test.ts`.
- Playwright `1.64.0`: `apps/web/playwright.config.ts` (chromium, levanta `vite` dev en `127.0.0.1:4173`) y `tests/example.spec.ts`.
- `.gitignore` raíz y `apps/web/.gitignore`: `.env*` (excepto `*.example`), `*.pem`, `*.key`, reportes de Playwright, `*.backup`.
- `AGENTS.md` y `CLAUDE.md` reescritos (ver riesgos).

**No se modificó** lógica de stock, ventas, caja ni clientes. Sin migraciones ni acceso a producción.

### Cómo se verificó

Local, Node 24.20.0, npm 11.19.0, desde `apps/web/`:

| Verificación | Resultado |
|---|---|
| `npm run typecheck` | exit 0 |
| `npm test` (Vitest 5.0.2) | 2 archivos, 5 pruebas, todas pasan |
| `npx playwright test` | 1 prueba (chromium), pasa |
| `npm run build` | exit 0, `index-E6w3GRy_.js` (mismo hash que en Tarea 001: bundle sin cambios) |
| `npm run lint` | exit 1: 10 errores + 1 advertencia, **idénticos** a `docs/incidents/2026-10-12-lint-falla-en-main.md` (sin errores nuevos) |
| Workflows | único archivo `.github/workflows/ci.yml`; sin duplicados |
| Secretos | no hay `.env*`, `*.pem` ni `*.key` en el árbol ni trackeados; `git check-ignore` confirma que `*.backup`, `playwright-report/`, `test-results/`, `dist/` y `.claude/settings.local.json` están ignorados |

### Correcciones aprobadas (13/10/2026)

En la primera revisión se detectaron tres puntos; el usuario autorizó corregirlos así:

1. **OpenCode / Superpowers.** Se conserva la clave `plugins` (plural): es la correcta para OpenCode V2 según `obra/superpowers/.opencode/INSTALL.md`. La observación inicial de que debía ser `plugin` era incorrecta: esa clave corresponde a V1. El plugin queda fijado en `#v6.4.2` (commit `8ca22db`, publicado el 25/09/2026). INSTALL.md exige `v6.4.1` o posterior para V2, y las notas de la versión 6.4.2 confirman soporte para OpenCode 2.0.4+. Se descartó `v7.0.0` (publicado el 09/10/2026) por tener menos de dos semanas.
2. **`AGENTS.md` / `CLAUDE.md`** combinados: se conserva el contenido nuevo y se recupera de `eae777f` la lista de propuestas no aprobadas, las restricciones de producción y seguridad, los comandos, las versiones exactas, el idioma y el cierre de tarea. Se agrega el flujo oficial: Claude Code implementa; Codex y OpenCode auditan de forma independiente el mismo commit; el usuario aprueba. `CLAUDE.md` vuelve a importar `@AGENTS.md`.
3. **Dependencias exactas:** `vitest` `5.0.2` y `@playwright/test` `1.64.0` (`npm install -E`). El lockfile solo cambió los especificadores raíz; las versiones resueltas no cambiaron.

### Verificación posterior a las correcciones

Instalación limpia (`rm -rf node_modules && npm ci`, 0 vulnerabilidades):

| Verificación | Resultado |
|---|---|
| `npm run typecheck` | exit 0 |
| `npm test` | 2 archivos, 5 pruebas, todas pasan |
| `npx playwright test` | 1 prueba (chromium), pasa |
| `npm run build` | exit 0, `index-E6w3GRy_.js` (sin cambios) |
| `npm run lint` | exit 1, mismos 10 errores + 1 advertencia del incidente (comparación línea por línea: idéntica) |
| OpenCode 2.0.27 | `opencode plugin list` muestra `superpowers 8ca22db …#v6.4.2`; `opencode debug agents` muestra el subagente `auditor`. No se ejecutó un prompt contra el modelo |
| Workflows | solo `.github/workflows/ci.yml` |
| Secretos | sin `.env*`, `*.pem`, `*.key` ni credenciales en el árbol, en el stage ni en el diff |

### Riesgos pendientes

1. **La configuración global de OpenCode** (`~/.config/opencode/opencode.jsonc`, fuera del repo) también declara `superpowers` sin versión fija. Hoy resuelve al mismo commit, pero quedan dos specs registrados para el mismo plugin, que podría cargarse dos veces. No se modificó porque es configuración personal.
2. **`@playwright/test` 1.64.0** se publicó el 07/10/2026, hace menos de las dos semanas recomendadas. Se mantuvo para no cambiar de versión.
3. **Playwright no corre en CI** ni tiene script npm (`test:e2e`); los navegadores se instalan con `npx playwright install chromium`.
4. **`tsc -b` no cubre** `vitest.config.ts`, `playwright.config.ts` ni `tests/*.spec.ts` (solo `src/` y `vite.config.ts`).
5. `tests/example.spec.ts` usa URL absoluta en lugar de `baseURL`; la prueba solo verifica que `body` sea visible.
6. Falta la verificación funcional de Superpowers dentro de una sesión de OpenCode ("Tell me about your superpowers"): la debe hacer el usuario, porque consume el proveedor de modelos.

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
