# AUDITORÍA INDEPENDIENTE — Hardening de grants / default privileges

**Repositorio:** victor-desarrollador/distribuidora-stock-rutas
**Rama:** `feat/hardening-grants-default-privileges`
**Commit auditado:** `5abdc57023513afeb79424193b53cd7b16b3f03e`
**Autor del commit:** victor-desarrollador (implementador)
**Auditor:** independiente (read-only) — sin modificar archivos, sin commits, sin aplicar migraciones, sin tocar staging ni producción
**Fecha de auditoría:** 23/10/2026

---

## Fuentes de verdad revisadas (obligatorias, completas)

- `BLUEPRINT.md` v2.0 (completo)
- `AGENTS.md` (completo)
- `CLAUDE.md` (completo)
- `docs/PRD.md` v0.10 (completo)
- `docs/decisions/README.md`
- `docs/decisions/001-rpc-privilegiadas.md` ADR-001 v1.5 (APROBADA PARA VALIDACIÓN CONTROLADA), completo
- `docs/progress-log.md` (entradas relevantes: hardening 23/10, staging read-only 23/10, slice productos, Auth base)
- `docs/quality/security-review.md`
- `docs/quality/review-process.md` (especialmente §4 formato de hallazgo)

## Archivos del commit auditados (diff vs. padre `33bd6722`)

El commit toca exactamente 4 archivos, 513 inserciones, 0 borrados:
1. `docs/progress-log.md` (documentación del cambio, 105 líneas)
2. `supabase/migrations/20261024010921_hardening_grants_default_privileges.sql` (nueva, 96 líneas)
3. `supabase/tests/grants_default_privileges.test.sql` (nueva, 306 líneas, plan(32))
4. `supabase/tests/productos_catalogo.test.sql` (modificada, +6 líneas: dos `GRANT EXECUTE ... TO PUBLIC` sobre helpers `pg_temp`)

Árbol de trabajo limpio en ese commit; `HEAD == commit auditado`. No hay cambios no commiteados.

Migraciones previas relevantes revisadas y comparadas:
- `20261022120000_auth_base_empresas_perfiles.sql`
- `20261023120000_perfiles_usuario_formato_estricto.sql`
- `20261023140000_catalogo_productos.sql`

Entorno local: no hay CLI de Supabase instalada, no hay base local corriendo ni Docker con Supabase, por lo que **no se re-ejecutaron** `supabase test db`, `supabase db lint`, `supabase db advisors`, `npm test`, `npx playwright test`, ni `npm run build`. Los resultados reportados por el implementador (pgTAP 212/212, 17/17 mutaciones, lint/typecheck/build OK, Vitest 716, Playwright 60) se citan como **evidencia alegada por el implementador**, no como ejecutada por este auditor. El veredicto se fundamenta en la revisión estática de los archivos commiteados.

---

## A. VERDICT

**APPROVED**

No hay hallazgos de seguridad (ningún BLOCKER, HIGH ni MEDIUM). O-1 y O-2 quedan correctamente resueltos dentro del alcance autorizado. Los privilegios por defecto son mínimos y correctos. No hay regresión de Topología D ni de RLS. No se implementó ninguna decisión pendiente no aprobada. Los tests cubren los invariantes materiales.

Hay observaciones de nivel INFO (no bloqueantes) documentadas en la sección B y en C/D, relacionadas con la aplicación a staging y con el alcance deliberadamente limitado de P11 global.

---

## B. FINDINGS

**BLOCKERS: 0**
**SECURITY FINDINGS: 0**

Observaciones (nivel INFO, no bloqueantes):

| # | Severidad | Archivo/línea | Evidencia | Regla afectada | Riesgo | Corrección propuesta | Bloqueo |
|---|-----------|---------------|-----------|----------------|--------|----------------------|---------|
| INFO-1 | INFO | `supabase/migrations/20261024010921_hardening_grants_default_privileges.sql:41-48` | El guard `if current_user <> 'postgres'` aborta la migración si no corre como `postgres`. | ADR-001 §12.6 (defaults por rol creador) | Si en staging las migraciones no corren como `postgres`, la migración aborta y O-1/O-2 no se aplican allí (falla cerrado, no inseguro). | Antes de aplicar a staging, confirmar que el rol que ejecuta migraciones es `postgres`; si no es así, ajustar el rol del guard o la forma de aplicar. No es defecto del commit. | No |
| INFO-2 | INFO | `supabase/migrations/20261024010921_hardening_grants_default_privileges.sql:71-72` | `ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` (forma global, sin `IN SCHEMA`) afecta funciones futuras creadas por `postgres` en **todos** los esquemas, incluidas funciones de extensiones instaladas por migración. | ADR-001 §12.6 | Toda función futura creada por `postgres` no será ejecutable por defecto hasta `GRANT EXECUTE` explícito en su migración. Es el endurecimiento intencional (fail-closed); efectos colaterales solo operativos, no de seguridad sobre el código actual. | Cada migración futura debe conceder `EXECUTE` explícitamente a las funciones que la Data API/la app deban invocar. Documentado en `docs/progress-log.md`. | No |
| INFO-3 | INFO | `docs/progress-log.md` (riesgos y pendientes) | `P11 global` (SELECT/INSERT/UPDATE/DELETE de `service_role` sobre `empresas` y `perfiles`) sigue sin normalizar: difiere entre local (`arwd`) y staging (ninguno). | ADR-001 §18.1 P11-productos | No es un agujero de seguridad del cambio; es una decisión pendiente fuera del alcance de esta tarea. | Resolver P11 global en una tarea separada con decisión humana aprobada. | No |
| INFO-4 | INFO | `supabase/migrations/20261024010921_hardening_grants_default_privileges.sql` | No se tocan los default privileges de `supabase_admin` ni del esquema `storage`, ni `MAINTAIN`, ni `rls_auto_enable()`. | AGENTS.md §4.4 / progreso-log | Alcance deliberadamente limitado al rol `postgres` y objetos de la app. | Queda fuera de este cambio; no es requisito de O-1/O-2. | No |

Ninguno de estos es un finding de seguridad ni bloquea la aprobación del commit.

---

## C. MIGRATION REVIEW

Archivo: `supabase/migrations/20261024010921_hardening_grants_default_privileges.sql` (96 líneas)

### Guard de `current_user` (líneas 41-48)
Bloque `DO $$ ... IF current_user <> 'postgres' THEN RAISE EXCEPTION ... END IF; $$`. Correcto y seguro: los `ALTER DEFAULT PRIVILEGES` se definen por rol creador (ADR-001 §12.6), y si la migración no corre como `postgres` aborta en lugar de aplicar defaults sobre el rol equivocado. Falla cerrado.

### Alcance correcto
- Solo afecta default privileges de `postgres` en `public` (tablas, secuencias, funciones) y la entrada global de funciones (`FROM PUBLIC`, sin `IN SCHEMA`).
- No modifica objetos administrados de Supabase: no toca `auth`, `storage`, `pg_graphql`, `supabase_admin`, `rls_auto_enable()`, ni escalas/grants de Auth.
- No crea ni elimina objetos; solo `GRANT`/`REVOKE`/`ALTER DEFAULT PRIVILEGES`.

### `ALTER DEFAULT PRIVILEGES` con owner correcto
`FOR ROLE postgres` en todo. Coincide con el rol que ejecuta las migraciones en este proyecto y con ADR-001 §12.6.

### Schema correcto
- Tablas/secuencias/funciones: `IN SCHEMA public`.
- Funciones/PUBLIC: forma global (sin `IN SCHEMA`), que cubre también `privado`. Correcto, porque un `REVOKE` por esquema no elimina el privilegio global implícito de `PUBLIC` (ADR-001 §12.6; verificado en local).

### GRANT/REVOKE mínimos
- `anon`: `REVOKE ALL` sobre las 3 tablas (quedó sin nada). ✓
- `authenticated`: solo `SELECT` sobre `empresas`, `perfiles`, `productos`. ✓ (escrituras van por RPC, Topología D)
- `service_role` sobre `empresas`/`perfiles`: solo se revoca `TRUNCATE, REFERENCES, TRIGGER` (O-2, explícitamente autorizado). Se deja intacto el resto porque P11 global está pendiente y ADR-001 §18.1 prohíbe tocar sus privilegios sobre `perfiles`. ✓ (alcance mínimo, no resuelve P11 global)
- `service_role` sobre `productos`: `GRANT SELECT` (O-1) + `REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER`. ✓

### Idempotencia razonable
Todo `GRANT`/`REVOKE`/`ALTER DEFAULT PRIVILEGES` es repetible. El progreso-log reporta aplicación dos veces sobre base local sin errores, convergiendo al mismo resultado. ✓

### No dependencia frágil del entorno local
No asume datos de seed ni secuencias existentes. El guard aborta si no es `postgres` (falla cerrado). No depende del estado accidental de staging. ✓

**Conclusión C: MIGRACIÓN CORRECTA, MÍNIMA Y SEGURA.** No introduce dependencia frágil ni modifica objetos Supabase administrados.

---

## D. DEFAULT PRIVILEGES REVIEW

Razonamiento PostgreSQL sobre `ALTER DEFAULT PRIVILEGES`:

| Objeto | Owner afectado | Schema afectado | Efecto exacto | Comportamiento PUBLIC |
|--------|---------------|-----------------|---------------|----------------------|
| Tablas futuras | `postgres` | `public` | `REVOKE ALL ON TABLES FROM anon, authenticated, service_role` | ninguna entrada para `PUBLIC` ni los tres roles (verificado: `pg_default_acl`, `defaclobjtype='r'`, `defaclnamespace='public'`) |
| Secuencias futuras | `postgres` | `public` | `REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role` | idem, `defaclobjtype='S'` |
| Funciones futuras | `postgres` | `public` | `REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated, service_role` | idem, `defaclobjtype='f'`, schema `public` |
| Funciones futuras (todos los esquemas) | `postgres` | global (`defaclnamespace=0`) | `REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` | **forma global**, elimina el `EXECUTE` implícito de `PUBLIC` en cualquier schema (incluye `privado`). Un `REVOKE ... IN SCHEMA privado` **no** lo eliminaría (ADR-001 §12.6). |

### A. REVOKE global de EXECUTE por default para funciones creadas por postgres
Correcto y seguro. Es el endurecimiento intencional: las funciones futuras creadas por `postgres` (incluidas las instaladas por migraciones de extensiones y los helpers `pg_temp` de tests) no son ejecutables por otros roles hasta que cada migración conceda `EXECUTE` explícito. Es un fail-closed que elimina la superficie de "función ejecutable por omisión". No hay efecto colateral de seguridad sobre el código actual: las 6 RPC de productos ya tienen `GRANT EXECUTE` explícito a `authenticated` (migración de productos), y el test lo verifica.

### B. Default privileges de secuencias
Endurecerlas es correcto aunque hoy no existan secuencias de aplicación: es un default fail-closed para secuencias futuras. El progreso-log aclara que es revertible sin efecto porque no hay secuencias en el esquema. ✓

### C. service_role / productos
- `SELECT` existe: concedido explícito (línea 93), resuelve O-1. ✓
- Sin `INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER`: revocado explícito (líneas 95-96 y default de tablas). ✓
- Sin `EXECUTE` sobre RPC: default de funciones revoca `EXECUTE` a `service_role`, y el pgTAP de productos confirma que `service_role` no ejecuta ninguna fachada ni implementación de productos. ✓

### Posible falsa sensación de seguridad por otro owner
Revisado: la migración solo define defaults para `postgres`. No hay `ALTER DEFAULT PRIVILEGES` para `supabase_admin`, `propietario_rpc` ni otro rol de aplicación. `propietario_rpc` (P3/P4) posee solo funciones y no crea tablas de negocio, por lo que no genera defaults relevantes aquí. No se declara ninguna entrada de default ACL específica para `privado` (test línea 216: count = 0), porque la forma global ya cubre `privado`. No hay otro owner que cree objetos de aplicación en este alcance. ✓

**Conclusión D: DEFAULT PRIVILEGES MÍNIMOS Y CORRECTOS.** PASS.

---

## E. O-1

**O-1: `service_role` perdió SELECT sobre `public.productos` (debe conservarlo, ADR-001 §18.1 P11-productos).**

**PASS.**

Evidencia en la migración (líneas 92-93): `grant select on table public.productos to service_role;` (concedido de forma explícita, no dependiente del default de la plataforma). Evidencia en el pgTAP de productos (línea 257-259): `service_role puede leer productos`. Evidencia en el pgTAP de hardening (línea 60-62): `has_table_privilege('service_role', 'public.productos', 'select')` = OK. Causa raíz corregida: en local el default de plataforma lo daba; en staging faltaba; ahora es explícito. Sin `EXECUTE` sobre RPC (sin cambios).

---

## F. O-2

**O-2: `service_role` conservaba TRUNCATE, REFERENCES y TRIGGER sobre `empresas`/`perfiles`, y los defaults de `postgres` eran demasiado amplios.**

**PASS.**

Evidencia en la migración (líneas 89-90): `revoke truncate, references, trigger on table public.empresas, public.perfiles from service_role;`. Evidencia en el pgTAP de hardening (líneas 64-68): `service_role no tiene TRUNCATE/REFERENCES/TRIGGER sobre empresas ni perfiles` (OK), y las pruebas genéricas de tabla (líneas 106-111) verifican que ninguna tabla de `public` concede esos tres privilegios a `anon`/`authenticated`/`service_role`. Los default de tablas/secuencias/funciones de `postgres` se endurecen para los tres roles de la Data API y `PUBLIC` (funciones). Sin cambios en RLS, Topología D ni `propietario_rpc`.

Nota (de progreso-log, no es un hallazgo): los demás privilegios de `service_role` sobre `empresas`/`perfiles` (P11 global) se dejan intactos porque difieren entre entornos y no están aprobados para normalizar aquí; el cambio solo elimina los privilegios de escritura indebidos (O-2), que es exactamente lo autorizado.

---

## G. TEST REVIEW

### `supabase/tests/grants_default_privileges.test.sql` — plan(32), 32 pruebas

Todas las 32 aserciones se revisaron estáticamente. Cubren:

- **Permisos efectivos:** matriz `has_table_privilege` / `has_function_privilege` por rol y tabla (líneas 42-68).
- **Permisos de columna:** `has_any_column_privilege` y `has_column_privilege` (líneas 71-85).
- **PUBLIC sobre tablas existentes:** `aclexplode(relacl)` grantee=0 ausente (línea 87).
- **Defaults futuros (pg_default_acl):** tablas (`r`), secuencias (`S`), funciones (`f`) de `postgres` en `public` sin `PUBLIC`/`anon`/`authenticated`/`service_role` (líneas 173-198); entrada global de funciones (`defaclnamespace=0`) sin `PUBLIC` (líneas 202-214); sin default ACL específico de `privado` (línea 216).
- **Funciones futuras:** `pg_proc.proacl` sin `PUBLIC` (línea 135); `anon` no ejecuta función alguna de `public` ni `privado` (línea 143); `service_role` idem (línea 150).
- **Topología D intacta:** `authenticated` ejecuta exactamente las 6 firmas aprobadas (línea 157-168); `anon` y `service_role` no ejecutan ninguna RPC de productos (línea 249-254); ninguna RPC de productos conserva EXECUTE para PUBLIC (línea 288-286); auxiliares de `privado` solo ejecutables por `propietario_rpc` (línea 288-297).
- **Comportamiento:** objetos nuevos creados como `postgres` (tabla, secuencia, función en `public` y función en `privado`) no heredan privilegios para los 3 roles ni para `PUBLIC` (líneas 230-278); `authenticated` con `USAGE` sobre `privado` **no** puede ejecutar una función privada nueva (líneas 282-300). Prueba real de fail-closed.
- **Guard de rol:** verifica `current_user = 'postgres'` antes de crear objetos nuevos (línea 227).

Todo dentro de `BEGIN ... ROLLBACK` (no contamina la base). Se dejan sin evaluar, a propósito, `service_role` sobre `empresas`/`perfiles` (P11 global pendiente) y `MAINTAIN` (líneas 7-9). ✓ No hay falsos positivos: las `is_empty` excluyen `esperado IS NULL`; `has_table_privilege(role, ...)` consulta los privilegios del rol indicado, no los del usuario actual (que corre como `postgres`), así que no hay falso positivo por superusuario.

### `supabase/tests/productos_catalogo.test.sql` — cambio de +6 líneas

Añadido (líneas 87-88):
```sql
grant execute on function pg_temp.como_usuario(uuid, jsonb) to public;
grant execute on function pg_temp.como_anon() to public;
```
Justificación (comentario, líneas 84-86): con el hardening, postgres ya no concede `EXECUTE` a `PUBLIC` en funciones nuevas; estos helpers `pg_temp` se invocan desde roles simulados (`authenticated`/`anon`) en el test, por lo que necesitan `GRANT EXECUTE` explícito.

**Es exclusivamente infraestructura del test:** los helpers viven en `pg_temp` (esquema temporal de sesión, revertido con la transacción), no son funciones del producto, no tocan `public` ni `privado`, y no cambian ninguna aserción ni el plan (se mantiene plan(125)). No es una regresión del producto; es la adaptación del scaffolding de prueba al nuevo default fail-closed. ✓

**Conclusión G: TESTS CORRECTOS, CUBREN INVARIANTES MATERIALES, SIN FALSOS POSITIVOS.** PASS.

---

## H. MUTATION REVIEW

El implementador reporta 17 mutaciones detectadas (arnés ad hoc, no versionado, transacción revertida, base intacta verificada por catálogo), cada una detectada por ≥1 prueba fallante (52 aserciones fallantes en total entre todas las mutaciones; control sin mutación: 0 `not ok`).

Mutaciones reportadas y mapeadas a riesgos materiales:
- restaurar `TRUNCATE` a `service_role` en `empresas` (2 fallas) ✓
- restaurar `REFERENCES` en `perfiles` (2) ✓
- restaurar `TRIGGER` en `productos` (2) ✓
- quitar `SELECT` a `service_role` en `productos` (2) — detecta regresión de O-1 ✓
- agregar `INSERT` (2), `UPDATE(precio)` por columna (1), `DELETE` (1) a `service_role` en `productos` — detecta regresión de O-2 / escrituras no autorizadas ✓
- `INSERT` a `authenticated` en `productos` (3) ✓
- `TRUNCATE` a `authenticated` en `empresas` (2) ✓
- `SELECT` a `anon` (3) ✓
- default de tablas `ALL` a `authenticated` (3) y a `service_role` (3) ✓
- default de funciones `EXECUTE` a `authenticated` (3) ✓
- default global `EXECUTE` a `PUBLIC` (7) — detecta que la forma global de revocación se mantiene ✓
- default de secuencias `USAGE` a `anon` (2) ✓
- `EXECUTE` de `authenticated` sobre un auxiliar privado (1) ✓
- restauración completa del estado previo (13) ✓

**Mutaciones importantes cubiertas:** todas las listadas en el encargo (TRUNCATE, REFERENCES, TRIGGER, quitar SELECT service_role/productos, agregar writes, default ACL amplio, EXECUTE en auxiliares privados).

**Observación (INFO):** el arnés de mutaciones es ad hoc y no está versionado (misma práctica que el slice productos, per progress-log). No es un hallazgo de seguridad, pero se recomienda versionarlo si este endurecimiento pasa a ser un gate recurrente. No hay mutación explícita que re-conceda `EXECUTE` a `PUBLIC` sobre las 6 RPC de productos existentes, pero eso está cubierto estáticamente por las pruebas `ninguna función ... conserva EXECUTE para PUBLIC` (línea 135) y `ninguna RPC de productos conserva EXECUTE para PUBLIC` (línea 288).

**Conclusión H: MUTACIONES CUBIEREN LOS RIESGOS MATERIALES.** PASS (con observación INFO sobre versionado del arnés).

---

## I. TOPOLOGÍA D

**TOPOLOGÍA D: PASS (sin regresión).**

La migración **no toca**:
- Data API → fachadas `public` `SECURITY INVOKER` (sin cambios);
- implementaciones `privado` `SECURITY DEFINER` (sin cambios, owner `propietario_rpc`, `search_path=''`);
- validaciones dentro de las implementaciones privadas (sin cambios);
- operación atómica (sin cambios);
- `propietario_rpc` (sin cambios, P3);
- ownership (tablas siguen del owner de migraciones; funciones de `propietario_rpc`, P4);
- `search_path=''` (sin cambios);
- `EXECUTE` (la migración solo revoca defaults, no concede EXECUTE nuevo; las 6 RPC ya lo tienen explícito a `authenticated`);
- RLS (sin cambios);
- `empresa_id` (sin cambios).

La cadena Topología D queda intacta: Data API → fachada INVOKER en `public` → implementación DEFINER en `privado` → validaciones completas → transacción. Los grants de la migración son consistentes con ella (`authenticated` solo SELECT en tablas, EXECUTE solo en las 6 firmas; `service_role` sin EXECUTE sobre RPC de productos; `anon` sin nada).

---

## J. RLS

**RLS: PASS (sin regresión).**

La migración no modifica políticas RLS ni habilita/deshabilita RLS en ninguna tabla. El progreso-log (entrada de seguridad por catálogo) confirma: RLS activa en `empresas`, `perfiles`, `productos`; `FORCE` desactivado (conforme a P4); 7 policies; sin policies de INSERT/UPDATE/DELETE para `anon`/`authenticated`/`service_role`; `productos_select_empresa` aísla por `empresa_id`/perfil activo. No hay cambio de RLS en este commit. ✓

---

## K. PENDING DECISIONS

El commit **no implementa** ninguna decisión pendiente:
- P11 global (privilegios de `service_role` sobre `empresas`/`perfiles`): explícitamente no tocado (solo `TRUNCATE/REFERENCES/TRIGGER`, O-2); se deja pendiente por decisión humana.
- P8–P17: no tocados.
- Topología D: ya implementada en el slice productos, no cambiada aquí.
- Ninguna regla `PROPUESTA NO APROBADA` ni `PROPUESTA TÉCNICA NO APROBADA` del Blueprint se implementa (stock negativo, anulación de vendedor, descuentos, retiro sin bloqueo, `partidas_ingreso`).
- No se crea `privado`, `propietario_rpc`, `FORCE RLS`, ni selector multiempresa (todos fuera de alcance o ya resueltos anteriormente).
- Producción permanece bloqueada (ADR-001 no es `aprobada` productivamente; `AGENTS.md` §5).

**Conclusión K: NO SE IMPLEMENTÓ DECISIÓN PENDIENTE NO APROBADA.** ✓

---

## L. STAGING READINESS

**LISTO PARA STAGING: SÍ (con la condición de que se aplique bajo autorización humana y se repita la verificación de privilegios en staging).**

- El commit no se aplicó a staging ni a producción (progress-log: "Staging NO tocado por este cambio", "Producción NO tocada").
- Aplicar a staging requiere `supabase db push` bajo autorización humana expresa (prohibido sin ella, AGENTS.md §5).
- Observación INFO-1: confirmar que las migraciones en staging corren como `postgres` (si no, el guard aborta y O-1/O-2 no se aplican allí).
- Repetir verificación de `pg_default_acl` y privilegios efectivos en staging tras la aplicación (per progress-log).
- Security review (esta auditoría) y auditoría independiente del hash: hechas/pendientes de aceptación humana final.
- M-04 (pruebas negativas vía Data API en staging, incl. `pg_graphql`) sigue pendiente de staging (documentado como pendiente, no bloquea este commit).

**PRODUCCIÓN: NO TOCADA.** (Bloqueada por ADR-001; requiere aceptación humana final.)

---

## Resumen final

```
COMMIT AUDITADO:
5abdc57023513afeb79424193b53cd7b16b3f03e

VERDICT:
APPROVED

BLOCKERS:
0

SECURITY FINDINGS:
0

O-1:
PASS

O-2:
PASS

DEFAULT PRIVILEGES:
PASS

TOPOLOGÍA D:
PASS

RLS:
PASS

LISTO PARA STAGING:
SÍ (pendiente aplicación con autorización humana y verificación en staging; ver INFO-1)

PRODUCCIÓN:
NO TOCADA
```

Hallazgos de seguridad: ninguno. Observaciones de nivel INFO documentadas (INFO-1 a INFO-4), ninguna bloqueante.

El cambio es **seguro, mínimo y compatible con Blueprint + ADR-001** para avanzar a staging, sujeto a la aprobación humana para aplicar la migración en staging y repetir allí la verificación de privilegios.

---
*Nota: este informe es una auditoría estática de solo lectura sobre el commit indicado. Los resultados de ejecución (pgTAP 212/212, 17/17 mutaciones, lint/typecheck/build, Vitest, Playwright) se citan según el reporte del implementador y no fueron re-ejecutados por este auditor (no hay CLI de Supabase ni base local disponible en este entorno).*
