# ADR-009 — Migraciones hacia adelante y estado de los rollbacks manuales

**Fecha:** 04/11/2026
**Versión:** 0.3
**Estado:** APROBADA PARA VALIDACIÓN CONTROLADA (ratificación humana del 04/11/2026, 23:29, `America/Argentina/Tucuman`; F-1 a F-9)
**Autor:** OpenCode (implementador; no aprueba)
**Alcance:** procedimiento de cambio de esquema para D-1, D-2, T1 y T2 y para las migraciones posteriores de ADR-001 §18.4; estado de todos los scripts de `supabase/rollback/`.
**No modifica:** el Blueprint, ADR-001, ADR-005, ADR-006, ADR-007, ADR-008, las migraciones, los scripts de `supabase/rollback/`, la seguridad, RLS, grants ni roles.
**No autoriza por sí misma:** commits, push, PR, merge, deploy ni ejecución de rollbacks. La aplicación en staging requiere además la autorización específica de §2.8 (P20). Producción sigue bloqueada por ADR-001 §15/§19.

> **Alcance de la aprobación.** Aprobada el 04/11/2026 a las 23:29 (`America/Argentina/Tucuman`) **para validación controlada**, con F-1 a F-9. Habilita el procedimiento forward-only y la declaración de estado de los rollbacks en local/staging. **No autoriza** ejecutar rollbacks, aplicar migraciones en staging ni producción, y **no cierra** T1-1 ni T1-2, que siguen abiertos (§6). `supabase/rollback/README.md` es normativo desde esta ratificación.

**Historial**

| Versión | Fecha | Cambio |
|---|---|---|
| 0.1 | 03/11/2026 | Primera propuesta: forward-only, rollbacks como artefactos experimentales, decisiones F-1 a F-4. |
| 0.2 | 03/11/2026 | Ajustes documentales; agrega F-5, F-6 y F-7; criterios de aceptación de D-1. |
| 0.3 | 04/11/2026 | Incorpora los hallazgos **T1-1** y **T1-2** de la auditoría integral de jornadas (Codex, sobre `05b9d8d`); fija **F-3** y **F-5** (ratificadas el 04/11/2026); agrega los controles operativos C-1 a C-7; **elimina la exclusión del rollback de la identificación de riesgos**: los defectos se conservan como hallazgos técnicos **abiertos**; separa «no bloquear la integración» de «cerrar el hallazgo» (F-8, F-9). |

**Ratificación:** 04/11/2026, 23:29 (`America/Argentina/Tucuman`): aprobada para validación controlada con F-1 a F-9. La ratificación no modificó el contenido normativo de la v0.3.

---

## 1. Contexto

1. **Ninguna fuente vigente exige un rollback manual seguro como condición para integrar D-1 o las RPC de jornadas.** Se revisaron BLUEPRINT v2.5, ADR-001 (§15, §17.3, §18.4.13–15, §19), ADR-007, `AGENTS.md` y `docs/quality/`. `AGENTS.md` §6.4 sólo exige que todo cambio de esquema vaya en una migración nueva; no define reversión.
2. **Los scripts de `supabase/rollback/` nacieron como práctica de implementación** (patrón de D-2), no como requisito normativo. Los ciclos de auditoría de D-1 posteriores a `af4e52a` corrigieron **sólo** el rollback: M-1, M-3, A5, M-4, N-1 y H-14. La migración de D-1 no cambió desde `af4e52a` (SHA-256 `9f876afd8ff490cc7397ef631cac5e06ab1820f33f51a59b55f098d7eafa5903`).
3. **La auditoría integral de jornadas confirmó el problema.** Codex, sobre `05b9d8dee490080c01972dcf801ea119433b6e63` (tramo 1, dictamen DESFAVORABLE), emitió dos hallazgos bloqueantes para un PR a `main`:
   - **T1-1 (ALTO):** el rollback de D-2 (`20261029233000_lector_perfiles_rpc.rollback.sql:30-50`) elimina la política, la vista `privado.perfiles_empresa_gestion`, el helper y el rol **sin comprobar consumidores**. `abrir_jornada` y `reasignar_vendedor` usan la vista (`20261105130000_pg_temp_jornadas.sql:298,551`); las referencias dentro de cuerpos PL/pgSQL no quedan en `pg_depend`, de modo que el `DROP VIEW` prospera y las RPC quedan rotas en tiempo de ejecución. La poscondición del script sólo verifica que D-2 desapareció.
   - **T1-2 (MEDIO):** el barrido textual de funciones del rollback de D-1 (`20261030120000_jornadas_esquema.rollback.sql:243-252`) se limita a los esquemas `public` y `privado`. Una función de otro esquema que consulte `public.jornadas` sobrevive al barrido y queda rota. El commit `476a84f8ae864b1b053fd46a26f5ee24031012a8` corrige ese filtro, pero **no está integrado** en la rama.
   - **T1-3 (informativo):** los manifiestos de los rollbacks de T1 y T2 derivaron; el conjunto no es una cadena ejecutable del HEAD y aborta fail-closed por diseño.
4. **Revisión estática de CI, deploy y documentación (04/11/2026).** No existe ninguna invocación automatizada de los scripts de rollback:
   - `.github/workflows/ci.yml` no los menciona ni ejecuta migraciones ni rollbacks;
   - `apps/web/package.json` no tiene scripts de base de datos;
   - `apps/web/vercel.json` sólo define un rewrite de SPA;
   - `supabase/config.toml` no tiene hooks ni rutas de rollback; `[db.migrations]` y `[db.seed]` sólo apuntan a migraciones y `./seed.sql`;
   - `supabase/scripts/verificar_legado_pieza.sh`, `supabase/tests/concurrencia/arnes.sh` y `casos.sh` no los invocan;
   - las únicas menciones son **comentarios** en los propios scripts, en las cabeceras de las migraciones D-2/D-1 y en ADR-001 §18.4.15 (C-3).
   Es decir: hoy el riesgo es **operativo manual**, no automatizado.

---

## 2. Decisión (aprobada para validación controlada)

### 2.1 Hacia adelante como procedimiento normal

Todo cambio de esquema se hace con una **migración nueva** en `supabase/migrations/` (`AGENTS.md` §6.4). No hay reversión de esquema en el procedimiento autorizado. `supabase db reset` en local no es un rollback: reconstruye desde cero.

### 2.2 Rollbacks prohibidos

Queda prohibido ejecutar cualquiera de los cuatro scripts de `supabase/rollback/` (D-2, D-1, T1, T2) en staging, en producción y en cualquier base con datos reales o cuya identidad no esté verificada. La prohibición es **normativa**: no depende de que el script funcione.

### 2.3 Scripts existentes: artefactos experimentales

- Se conservan **sin cambios** como registro auditado.
- Su estado se declara en `supabase/rollback/README.md`, con la advertencia, la lista de scripts, sus SHA-256 y los defectos conocidos.
- Sus comentarios («local o staging») **no prevalecen** sobre esta ADR (`AGENTS.md` §1.1).
- Ningún resultado suyo cuenta como garantía de recuperación.
- Se prohíbe editarlos para «arreglarlos» sin una tarea autorizada: cualquier cambio altera el hash auditado y obliga a re-auditar.

### 2.4 Una migración aplicada en un entorno compartido es inmutable

Se corrige con una migración nueva, nunca editándola. Una migración que no se aplicó en ningún entorno compartido sí puede corregirse en su rama: eso genera un hash nuevo y una auditoría nueva.

### 2.5 Recuperación ante errores de migración

| Caso | Qué pasa | Qué se hace |
|---|---|---|
| **a. La migración falla dentro de su transacción** | No quedan efectos ni queda registrada | Se diagnostica. Si nunca se confirmó en un entorno compartido, se corrige en la rama (hash nuevo, auditoría nueva). La atomicidad por archivo depende del ejecutor: **verificar** antes de staging (D-1 no tiene `BEGIN`/`COMMIT` propios). |
| **b. La migración se confirmó con un defecto de esquema o de seguridad** | Queda aplicada | **Migración correctiva hacia adelante**, con pgTAP que falle antes y pase después, security review si toca una superficie de `AGENTS.md` §2.4 y auditoría del hash. Si el defecto es de seguridad: **migración mínima de contención** (por ejemplo, revocar `EXECUTE` o un grant) por el mismo ciclo, con autorización humana expresa. |
| **c. Problemas de datos** | Datos incorrectos con esquema sano | **Nunca** se borran movimientos ni operaciones confirmados (`AGENTS.md` §5; Blueprint §7). Se corrige con operaciones compensatorias trazables (RPC). Los datos no operativos (catálogos) se corrigen con una migración de datos nueva, con precondiciones fail-closed y conteos antes y después. |
| **d. Último recurso** | Daño que no se puede corregir hacia adelante | **Restaurar un backup**, sólo con autorización humana expresa y evaluando la pérdida de datos posterior. La restauración debe haberse probado antes en una base descartable. |

### 2.6 Los defectos quedan como hallazgos técnicos abiertos

Esta ADR **no declara corregidos, ni técnicamente resueltos, ni excluidos de la identificación de riesgos** los defectos de los rollbacks. T1-1, T1-2, T1-3, M-4, N-1, B-1, H-14 y A5 permanecen abiertos y deben figurar:

- en el registro de hallazgos (§6);
- en la security review y en las auditorías del hash, como riesgos identificados del artefacto experimental;
- en el `README.md` de `supabase/rollback/`.

La ratificación de esta ADR no es una aceptación técnica del riesgo: es la decisión de **no usar** el procedimiento que lo contiene.

### 2.7 Efecto sobre el bloqueo de la integración

- Mientras los rollbacks sigan prohibidos y no se ejecuten, **T1-1 y T1-2 no bloquean** la integración de las migraciones y las RPC de jornadas, porque pertenecen a un procedimiento no autorizado.
- «No bloquear» **no** significa «cerrar». Los hallazgos siguen abiertos (§2.6) y vuelven a ser bloqueantes, sin necesidad de una nueva ADR, si se autoriza ejecutar cualquier rollback (F-9).
- Cualquier hallazgo nuevo sobre las **migraciones, RPC o pruebas** sigue bloqueando con las reglas ordinarias.

### 2.8 Backups, validación y autorización

Antes de aplicar cualquier migración en staging (producción sigue bloqueada por ADR-001 §15/§19):

1. autorización humana específica para ese entorno y ese hash (P20; `AGENTS.md` §5);
2. backup verificado del entorno, con restauración conocida y probada al menos una vez en una base descartable (Blueprint §10);
3. el mismo hash con `db reset`, `test db` y `db lint` en PASS en local;
4. lectura previa autorizada del estado de migraciones del entorno;
5. después de aplicar: lista de migraciones, aserciones de catálogo de sólo lectura (subconjunto de `hardening_adr001`) y registro en la bitácora.

### 2.9 Controles para impedir el uso operativo accidental

Ver §7. C-1, C-4 y C-7 quedan preparados o verificados con esta ratificación; C-2, C-5 y C-6 quedan propuestos y requieren una tarea autorizada.

---

## 3. Alternativas descartadas

| Alternativa | Motivo |
|---|---|
| Exigir un rollback seguro (ADR-008) antes de integrar | Requiere superusuario de laboratorio, deja residuos no eliminables y bloquea el desarrollo funcional sin que ninguna fuente lo exija. |
| Corregir el rollback indefinidamente | Ya agotó los ciclos de `AGENTS.md` §2.3.5 en varias tareas y no cierra SQL dinámico (B-1) ni las carreras de DDL (M-4, N-1, H-14). |
| Eliminar los scripts de rollback | Pierde el registro auditado y la trazabilidad de los hallazgos. Conservarlos declarados es más simple y verificable. |
| Integrar `476a84f` y cerrar T1-2 | Corrige un filtro, pero no T1-1, ni B-1, ni M-4/N-1/H-14; cambia un artefacto auditado y obliga a otro ciclo. Se conserva la rama como registro (F-5). |

---

## 4. Criterios de aceptación para la integración de D-1 y jornadas

D-1 y las RPC de jornadas son **aptas para integración** sólo si se cumplen **todos**:

1. **ADR-009 aprobada** por el humano, incluidas F-1 a F-9 y el registro expreso de que T1-1/T1-2 no bloquean bajo §2.7.
2. **Hash fijado** del PR. `20261030120000_jornadas_esquema.sql` idéntica a `af4e52a` (SHA-256 `9f876afd…5903`) o, si cambió, reauditada.
3. **CI verde** en el PR (`Lint` y `Tipos, pruebas y build`).
4. **Supabase local**, sobre ese hash: `db reset` PASS con todas las migraciones; `test db` PASS con la cifra real de la corrida y sin relajar aserciones; `db lint` sin errores.
5. **Suite web**: `lint`, `typecheck`, `test`, `build` y `npx playwright test` con exit 0 y salida citada.
6. **Security review** del hash: cubre migración, RLS, grants y policies. Debe **registrar** los defectos de rollback de §6 como riesgos abiertos del artefacto experimental; no puede declararlos cerrados.
7. **Auditorías independientes de Codex y OpenCode** sobre el mismo hash: sin hallazgos críticos, altos ni medios **abiertos sobre la migración, las RPC o las pruebas**. Los defectos de rollback se registran como abiertos y su no-bloqueo depende de F-1/F-8; no se presentan como corregidos.
8. Existe `supabase/rollback/README.md` con el estado de §2.3.
9. **Autorizaciones humanas separadas** para commit, push, PR y merge. **Sin** aplicar en staging en esta compuerta.

---

## 5. Decisiones humanas ratificadas (04/11/2026, 23:29, Tucumán)

| ID | Decisión | Contenido ratificado |
|---|---|---|
| F-1 | Aprobar el procedimiento hacia adelante (§2.1–§2.8) | — |
| F-2 | Cómo declarar el estado de los scripts | `supabase/rollback/README.md` nuevo, sin editar los scripts |
| F-3 | ¿Se extiende la prohibición a los rollbacks de D-2, T1 y T2? | **Sí** (además de D-1) |
| F-4 | Estado de ADR-008 | No implementada; estudio histórico |
| F-5 | ¿Se integra `476a84f`? | **No.** No es necesario: sólo cambia el rollback experimental. La rama se conserva como registro; no se reescribe |
| F-6 | Registrar que M-4, N-1, B-1, H-14, A5, T1-1, T1-2 y T1-3 siguen abiertos | Sí |
| F-7 | Forma de integración | Un PR por compuerta |
| F-8 | Ratificar que los defectos de rollback no bloquean la integración mientras el rollback esté prohibido (§2.6–§2.7) | Sí, con registro explícito de que no es una corrección técnica |
| F-9 | Si alguna vez se autoriza ejecutar un rollback | Vuelven a bloquear T1-1, T1-2, M-4, N-1, B-1 y H-14; se requiere ADR-008, autorización específica y auditoría nueva |

---

## 6. Registro de hallazgos técnicos abiertos

| ID | Severidad | Objeto | Defecto | Estado |
|---|---|---|---|---|
| **T1-1** | Alto | Rollback D-2 | Elimina vista/helper/rol usados por `abrir_jornada` y `reasignar_vendedor` sin comprobar consumidores | Abierto |
| **T1-2** | Medio | Rollback D-1 | Barrido de funciones limitado a `public`/`privado`; `476a84f` no integrado | Abierto |
| **T1-3** | Informativo | Rollbacks T1/T2 | Manifiestos derivados: no forman cadena ejecutable del HEAD | Abierto |
| **M-4** | Alto (proceso) | Rollback D-1 | Una función creada/reemplazada entre el barrido y el `COMMIT` pasa el control y queda rota | Abierto |
| **N-1** | Bajo | Rollback D-1 | `GRANT`/`REVOKE` concurrente posterior al precheck se pierde sin aviso | Abierto |
| **B-1** | Fuera de alcance técnico | Rollback D-1 | Referencias dinámicas construidas en ejecución no son detectables | Abierto, no detectable |
| **H-14** | Alto (proceso) | Rollback D-1 | Cambios concurrentes de roles, membresías, privilegios y ownership | Abierto |
| **A5** | Medio | Rollback D-1 en `e225fff` | Barrido sin cubrir otros esquemas (origen de T1-2); corregido sólo en `476a84f`, no integrado | Abierto en el HEAD |

Ninguno de estos hallazgos se declara aceptado técnicamente por esta ADR. La aceptación es **de proceso**: no se usa el artefacto.

---

## 7. Controles propuestos contra el uso operativo accidental

| ID | Control | Mecanismo | Verificación | Estado |
|---|---|---|---|---|
| C-1 | Declaración de estado | `supabase/rollback/README.md` con advertencia, lista, SHA-256 y defectos | Existencia y contenido en la revisión del PR | Preparado en esta entrega |
| C-2 | Guarda en CI | Job que falle si algún archivo versionado **fuera** de `supabase/rollback/` o de documentación contiene una invocación ejecutable (`psql … .rollback.sql`, `-f supabase/rollback/…`) | El job falla con una invocación de prueba en una rama descartable | Propuesto; requiere tarea autorizada |
| C-3 | Sin automatización | Verificado: CI, `package.json`, `vercel.json`, `config.toml` y scripts versionados no los invocan | Revisión estática (§1.4) y repetición en cada PR que toque CI o deploy | Verificado 04/11/2026 |
| C-4 | Ruta no ejecutable | Los scripts viven fuera de `supabase/migrations/` y de `seed.sql`; el CLI no los toma en `db reset` ni `db push` | `config.toml`: `[db.migrations]` y `[db.seed]` no los incluyen | Verificado |
| C-5 | Precondiciones de ejecución | Sólo base local descartable, autorización humana expresa, `ON_ERROR_STOP=1`, `current_user = postgres`, sin DDL concurrente, identidad verificada | Registro en la bitácora con hash, comando y resultado | Propuesto |
| C-6 | Trazabilidad | Toda ejecución (o intento) se registra en `docs/progress-log.md` con evidencia; sin registro se presume no ejecutada | Revisión de la bitácora | Propuesto |
| C-7 | Inmutabilidad | No se editan los scripts sin tarea autorizada, hash nuevo y auditoría nueva | SHA-256 del README contra el árbol | Preparado en esta entrega |

---

## 8. Consecuencias

- **Se desbloquea** la integración de jornadas en lo que respecta a T1-1 y T1-2, **sin corregirlos** (F-8).
- **Se conserva** el registro de los defectos; el proyecto no gana un mecanismo de reversión, pero tampoco finge tenerlo.
- **Se simplifica** el procedimiento: una migración aplicada se corrige hacia adelante.
- **Riesgo residual**: una ejecución manual pese a la prohibición. Se mitiga con C-1 a C-7, no se elimina.
- **Si se necesita un rollback real**, el camino es ADR-008 + autorización específica + auditoría nueva; los hallazgos vuelven a bloquear (F-9).

---

## 9. Fuentes

- `BLUEPRINT.md` §7, §10, §12, §15.
- `AGENTS.md` §2.2.1, §2.3.5, §2.4, §3, §5, §6.4.
- `docs/decisions/001-rpc-privilegiadas.md` §15, §17.3, §18.4.13–15, §19.
- `docs/decisions/007-jornadas-y-carga-de-camiones.md`.
- `evidencia-integracion-jornadas/auditoria/codex/INFORME-TRAMO-1.md` (HEAD `05b9d8d`).
- `evidencia-integracion-jornadas/auditoria/codex/INFORME-TRAMO-2.md` (HEAD `05b9d8d`).
- `~/Documentos/ADR-008-PROPUESTA-v0.3.md` (propuesta, no aprobada) y `ADR-009-PROPUESTA-v0.2.md` (origen de este texto).
