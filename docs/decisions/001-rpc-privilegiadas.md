# ADR-001 — Puerta de entrada SQL para operaciones privilegiadas

**Fecha:** 12/10/2026 · **Última revisión documental:** 25/10/2026
**Estado:** APROBADA PARA VALIDACIÓN CONTROLADA
**Versión:** 1.5 (registro de las decisiones humanas P2–P4; P5–P7 en v1.4) + anexo §18.1 (decisiones acotadas al slice productos, 23/10/2026) + anexo §18.2 (decisiones transversales P11 global, O-3 y O-4, 24/10/2026) + anexo §18.3 (decisiones acotadas al dominio Stock, 25/10/2026; ampliado con el slice `stock-cuarentena-merma`) + anexo §18.4 (jornadas y carga: v0.4 con fe de erratas E1–E3, **PROPUESTA TÉCNICA NO APROBADA**, candidato a revisión independiente)

> **Aviso de alcance.** La decisión humana resolvió P1, P19 y P20; el 22/10/2026, P5, P6 y P7; el 23/10/2026, P2, P3 y P4 (§18); y el 24/10/2026, P11 global y las observaciones O-3 y O-4, para validación controlada (§18.2). Esta ADR autoriza exclusivamente el diseño, las migraciones y las pruebas necesarias para validar la Topología D en local/staging, una vez resueltas las decisiones P8–P10 y P12–P17 que requiera el alcance de la validación. **No autoriza producción**, no resuelve P8–P10 ni P12–P17 y no convierte P18 en requisito. La aceptación productiva exige pruebas, auditoría independiente y aceptación humana final (`AGENTS.md` §3 y §5; `BLUEPRINT.md` §10; `docs/decisions/README.md`).

---

## 0. Historial de esta revisión

| Ronda | Autor | Resultado |
|---|---|---|
| v1.1 | — | Texto original (wrapper `SECURITY DEFINER` expuesto). |
| v1.2, ronda 1 | OpenCode | Ampliación documental (requisitos, alternativas, pendientes P1–P11). |
| Revisión independiente | Codex | **CHANGES REQUIRED** (12 correcciones). |
| v1.2, ronda 2 | Claude Code | Aplica las 12 correcciones. |
| Segunda revisión independiente | Codex | **CHANGES REQUIRED** (4 correcciones sobre la ronda 2). |
| v1.2, ronda 3 | Claude Code | Esta versión: aplica las 4 correcciones (secciones 4, 5, 15, 17, 18, 19 y 21). Pendiente de nueva revisión independiente y de aprobación humana. |
| v1.3 | Codex | Alinea la decisión humana: P1 = Topología D, P19 = gobernanza en dos etapas y P20 = migraciones de validación sólo local/staging. Estado intermedio, sin aprobación productiva; P2–P17 pendientes y P18 separada. |
| v1.4 | Claude Code | Registra la decisión humana del 22/10/2026 sobre P5, P6 y P7 (un perfil 1:1 con `auth.users`, una sola empresa y un único rol por usuario; sin membresías). El estado de la ADR no cambia; P2–P4 y P8–P17 siguen pendientes. |
| v1.5 | Claude Code | Registra la decisión humana del 23/10/2026 sobre P2, P3 y P4 (esquemas `public`/`privado`, rol técnico `propietario_rpc`, ownership de tablas y RLS sin `FORCE` global), que cierra el hallazgo BLOCKER-01 de la auditoría de `d7c3664`. El estado de la ADR no cambia; P8–P17 siguen pendientes y P18 separada. |
| v1.5 + anexo | Claude Code | Agrega §18.1: decisiones humanas del 23/10/2026 **acotadas al slice productos** (P10/P11/P12/P13/P14/P15/P16/P17-productos, DE-2, DE-3, DE-11, DE-15 y el helper `privado.usuario_actual()`). No resuelve P10–P17 globalmente, no cambia el estado de la ADR ni autoriza producción. |
| v1.5 + anexo (complemento P11-productos) | Claude Code | Amplía P11-productos en §18.1: `service_role` tampoco escribe directamente `public.productos` (hallazgo H-01 de The Architect). Acotado al slice productos; P11 global sigue pendiente. El estado de la ADR no cambia y no autoriza producción. |
| v1.5 (corrección terminológica) | Claude Code | Corrección terminológica: el producto es de empresa única; `empresa_id` es una frontera técnica de aislamiento y no una capacidad multiempresa. Renombra el encabezado de §8 a «Invariante de aislamiento por `empresa_id`» y alinea las referencias normativas de membresía (§3.1, §3.2, §8, §9, T2, T3 y la nota sobre inicio de sesión anónimo) al modelo aprobado de perfil 1:1, una empresa y un rol; sin cambio de comportamiento. Las garantías, T4/T5/T15 y el estado de la ADR (**APROBADA PARA VALIDACIÓN CONTROLADA**) no cambian. |
| v1.5 + anexo §18.2 | Claude Code | Registra las decisiones humanas del 24/10/2026, para validación controlada: **P11 global** (`service_role` denegado por defecto en objetos de negocio; única excepción vigente, SELECT sobre `public.productos`), **O-3** (`postgres` → `propietario_rpc` con SET true e INHERIT false) y **O-4** (`public.rls_auto_enable()` y `ensure_rls` se conservan, sin EXECUTE para PUBLIC/`anon`/`authenticated`/`service_role`), con la evidencia read-only de staging que fundamentó O-4. El estado de la ADR no cambia; P8–P10 y P12–P17 siguen pendientes y P18 separada; no autoriza producción. |
| v1.5 + anexo §18.3 | Claude Code | Registra las decisiones humanas del 25/10/2026 **acotadas al dominio Stock** (slice `stock-ingreso`): P10, P12, P13, P14, P15, P16 y P17 para Stock, más la huella de idempotencia v1. No resuelve esos puntos para jornadas, ventas ni dinero, no cambia el estado de la ADR ni autoriza producción. |
| v1.5 + anexo §18.3 (slice 2) | Claude Code | Amplía §18.3 con las decisiones humanas del 25/10/2026 del slice `stock-cuarentena-merma` (D1–D9, huellas v1 de cuarentena y merma, lock concreto de débito y errores nuevos), **acotadas al dominio Stock**. No resuelve P10–P17 globalmente, no habilita la Etapa 3, `cuarentena_apta` ni el negativo transitorio, no cambia el estado de la ADR ni autoriza producción. |
| v1.5 + anexo §18.4 (candidato) | Claude Code | Incorpora §18.4 v0.4 (contrato técnico de las seis RPC de ADR-007) con la fe de erratas E1–E3, como **PROPUESTA TÉCNICA NO APROBADA**. No aprueba el anexo, no cambia el estado de la ADR, no modifica ADR-007, no autoriza SQL ni producción; D-1, D-2, arnés, CI y security review siguen pendientes. |

---

## 1. Contexto

El sistema nuevo **está previsto** sobre Supabase (Auth, PostgreSQL, RLS, RPC) con frontend React (`BLUEPRINT.md` §6). Hoy el repositorio contiene un prototipo frontend sin backend que persiste en `localStorage` (`INVENTARIO_ETAPA_0.md` §1); **todavía no existe** integración con Supabase ni con su Data API.

Cuando exista, la interfaz React **usará** la Data API de Supabase (PostgREST). Los usuarios `authenticated` no deberán poder escribir directamente en los libros de movimientos de stock y dinero (`BLUEPRINT.md` §3, §6, §10). Un enfoque `SECURITY INVOKER` puro sobre esas tablas exigiría conceder escritura directa a `authenticated`, lo que abriría rutas capaces de saltar las reglas de negocio y la auditoría. Esta ADR define la topología de la puerta de entrada para validación controlada; P2–P7 y P11 están resueltas (§18 y §18.2) y P8–P10 y P12–P17 siguen pendientes.

---

## 2. Jerarquía normativa y alcance

- `BLUEPRINT.md` es la **fuente de mayor autoridad** del proyecto (`BLUEPRINT.md` línea 8; `AGENTS.md` §1). Mientras una ADR **aprobada** no la modifique, su regla **más estricta** permanece vinculante.
- `AGENTS.md` traslada esas reglas a instrucciones operativas para agentes; no las relaja. `INVENTARIO_ETAPA_0.md` está subordinado a ambos (su propia nota de precedencia).
- Una ADR en estado `APROBADA PARA VALIDACIÓN CONTROLADA`, como esta, modifica el Blueprint únicamente dentro de las decisiones resueltas y habilita sólo validación local/staging; no habilita producción ni completa decisiones pendientes.

**Alcance resuelto (P20).** Antes de la aprobación para validación controlada no podían generarse migraciones dependientes de ADR-001. Con el estado actual se permiten las migraciones necesarias para probar la ADR exclusivamente en local/staging. Producción permanece bloqueada hasta completar las pruebas requeridas, la auditoría independiente y la aceptación humana final. Esta autorización no alcanza a decisiones P8–P10 y P12–P17 todavía pendientes ni a otras migraciones fuera del alcance de validación.

---

## 3. Requisitos aprobados y elementos del modelo propuesto

### 3.1 Requisitos aprobados (no se reabren en esta ADR)

1. La lógica que mueve stock o dinero vive en funciones de la base (RPC); el frontend nunca inserta movimientos directamente (`BLUEPRINT.md` §6:97; §13, regla 3).
2. Cada operación crítica es **una transacción**: o se guarda todo, o nada (§6:98).
3. Los libros de movimientos son solo de inserción; `authenticated` y `anon` no reciben INSERT, UPDATE ni DELETE directos sobre libros ni registros confirmados; las rectificaciones son asientos compensatorios (§6:99, §10:276).
4. RLS en todas las tablas expuestas por la API, filtrando por empresa, rol y estado; los controles visuales nunca son la única defensa (§10:275).
5. Todas las tablas de negocio llevan `empresa_id` y las políticas RLS filtran por él; hoy existe una sola empresa (§7.3:127).
6. Empresa y rol se leen de **tablas protegidas** (el perfil), nunca de `user_metadata` (§10:274).
7. Roles confirmados: dueño, encargado y vendedor/piloto, con los permisos y prohibiciones de §9.
8. Separación de responsabilidades: quien cuenta el regreso no es el vendedor de la jornada, sin autobypass (§3:45, §7.5:164, §9:268).
9. **Trazabilidad y auditabilidad** como propiedad general: cada cambio de stock registra quién, cuándo, por qué, cuánto, desde dónde y hacia dónde; el sistema registra quién hizo cada paso; los registros son inmutables (§1:20, §3:44-45, §10:276, §10:282).
10. **Idempotencia** como propiedad general: idempotencia por solicitud, clave única y protección contra concurrencia para cargas, ventas, retiros y cierres; dos solicitudes concurrentes o reintentadas no duplican efectos (§7.5:159, §7.6:171, §10:280, §12:349).
11. Hora del servidor en UTC, zona horaria operativa explícita y distinción entre hora declarada y hora de registro (§10:281).
12. Para `SECURITY DEFINER`: `SET search_path = ''`, objetos completamente calificados, propietario de privilegio mínimo, revisión de grants por defecto y pruebas reales desde `anon`, `authenticated` de otra empresa y roles válidos; no poner lógica privilegiada libremente ejecutable en un esquema expuesto (§10:277-278).
13. Entornos local, staging y producción separados (§10:282).

### 3.2 Elementos del modelo propuesto (NO son requisitos aprobados)

`BLUEPRINT.md` §8 se titula **"Modelo de datos (propuesto)"**. Por lo tanto, sus tablas y columnas concretas son diseño propuesto, no reglas aprobadas. En particular:

- la tabla concreta `auditoria` y sus columnas (§8:249);
- las columnas concretas `ventas.idempotency_key` y `retiros_efectivo.idempotency_key` (§8:242-243);
- la forma SQL exacta de `perfiles` y del rol (§8:227), respetando el perfil 1:1 con `auth.users`, una empresa y un rol por usuario, sin tabla de membresías (P5–P7, §18);
- `saldos_stock` como tabla mantenida por las RPC (§8:234) y las "restricciones clave" (§8:251-256), salvo las que también son reglas de negocio aprobadas (por ejemplo, una jornada por `empresa_id`, `camion_id` y `fecha`, §7.5:156).

Esta ADR usa esos nombres solo como referencia. Su forma final queda **PENDIENTE DE APROBACIÓN HUMANA** junto con el modelo de datos.

> **Observación:** §7.6:171 nombra `idempotency_key` dentro de una regla de negocio ("Prohibir retiro duplicado mediante `idempotency_key`"). Esta ADR interpreta como aprobado el **contenido** (impedir el retiro duplicado mediante una clave de idempotencia) y como propuesto el **nombre y la ubicación** de la columna. Se pide confirmación humana (P15).

---

## 4. Conflicto entre el Blueprint y la guía vigente de Supabase

Se reconoce explícitamente:

- **Blueprint histórico (v1.9).** §10 proponía "exponer una RPC pública `SECURITY DEFINER` exclusivamente como puerta de entrada" y también advertía no poner lógica privilegiada libremente ejecutable en un esquema expuesto. Blueprint v2.0 reemplaza esa formulación por Topología D.
- **Supabase (documentación vigente consultada el 16/10/2026 y el 17/10/2026).**
  - *Row Level Security*, apartado "Use security definer functions" (advertencia): las funciones `security definer` **no deben crearse nunca** en un esquema expuesto: "Never create one in a schema listed under 'Exposed schemas'" de la configuración de la API. Sus ejemplos las ubican en un esquema `private`.
  - *Database Functions*: "Prefer `security invoker`, which is also the default". Agrega que una función `security definer` "can return rows the caller isn't allowed to read" y que las funciones creadas por migración son de `postgres`, "which bypasses Row Level Security".
  - *Database Advisors*, lints `0028` y `0029`: marcan como advertencia (WARN) toda función `SECURITY DEFINER` ejecutable por `anon` o `authenticated`. Entre las remediaciones figura mantenerla como decisión intencional; eso describe cómo tratar la advertencia, **no** constituye una recomendación del diseño.
  - *Securing your API* y *Hardening the Data API*: los objetos internos se mantienen "in schemas that aren't exposed".

**Conclusión documental (conflicto resuelto por P1):**

1. La topología C (sección 5) coincidía con el requisito literal histórico de Blueprint §10:277: una RPC pública `SECURITY DEFINER` como puerta de entrada.
2. La guía de seguridad vigente de Supabase dice **explícitamente** que las funciones `SECURITY DEFINER` no deben crearse en un esquema expuesto.
3. Por lo tanto, **la topología C no es un diseño recomendado por el proveedor**: contradice su guía.
4. C se mantiene en la comparación como alternativa histórica descartada; el Blueprint fue alineado con D.
5. Que las advertencias 0028/0029 se registren como entendidas o aceptadas **no significa** que Supabase avale el diseño: solo deja constancia de que el proyecto asumió un riesgo contra la guía del proveedor.
6. La decisión humana explícita P1 seleccionó la **Topología D** para validación controlada.

---

## 5. Alternativas de topología

Para facilitar la trazabilidad con la ronda 1 se conservan las letras A, B y C, y se agrega D. **El orden no implica preferencia.**

### A — `SECURITY INVOKER` con grants directos de escritura a `authenticated`
- **Descripción:** funciones `SECURITY INVOKER` y `GRANT INSERT/UPDATE/DELETE` a `authenticated` sobre las tablas del libro, protegidas solo por RLS.
- **Compatibilidad con requisitos aprobados:** **incompatible** con §6:99 y §10:276. Solo sería posible si una ADR aprobada modificara el Blueprint.
- **Decisión:** descartada por incompatibilidad con los requisitos.

### B — Edge Function como puerta de entrada
- **Descripción:** la operación entra por una Edge Function, que valida y luego llama a la base.
- **Compatibilidad:** §10:279 la admite **solo** "si aparece lógica externa no conveniente en SQL".
- **Límite transaccional:** ver sección 6. La atomicidad solo existe si la Edge Function llama a **una única** RPC transaccional; en ese caso la puerta de entrada real de stock y dinero sigue siendo esa RPC, con una de las topologías C o D.
- **Decisión:** reservada para lógica externa; no es la puerta de entrada normal.

### C — Wrapper `SECURITY DEFINER` en esquema expuesto + lógica interna en esquema privado
- **Descripción:** la propuesta literal histórica de `BLUEPRINT.md` v1.9. El wrapper expuesto valida todo y llama a funciones internas de un esquema no expuesto, que sólo puede ejecutar el propietario.
- **A favor histórico:** coincidía con el texto de Blueprint v1.9; las funciones internas no necesitaban `EXECUTE` para `authenticated`.
- **En contra:** la función expuesta corre con los privilegios del propietario. Contradice la guía explícita de Supabase de no crear funciones `SECURITY DEFINER` en un esquema expuesto (sección 4): **no es un diseño recomendado por el proveedor**. Genera advertencias 0028/0029; aceptarlas no implica aval de Supabase.
- **Decisión:** no elegida porque contradice la guía explícita de Supabase sobre `SECURITY DEFINER` en esquemas expuestos.

### D — Fachada `SECURITY INVOKER` expuesta + implementación privilegiada en esquema no expuesto
- **Descripción:** la función expuesta es `SECURITY INVOKER` y no tiene privilegios propios. Delega en una función `SECURITY DEFINER` ubicada en un esquema que la Data API no expone, y esa función hace **todas** las validaciones.
- **A favor:** sigue la recomendación de Supabase de preferir `SECURITY INVOKER` en lo expuesto y de mantener lo interno fuera de los esquemas expuestos; también es coherente con §10:278.
- **Riesgos que deben validarse:**
  - para que la fachada pueda delegar, `authenticated` necesita `USAGE` sobre el esquema privado y `EXECUTE` sobre la implementación. Esa función no es accesible por la Data API, pero **sí** es ejecutable por `authenticated` desde cualquier contexto SQL que la alcance. El límite de seguridad real es la implementación privilegiada, no la fachada;
  - la implementación privada es la frontera real de seguridad y debe concentrar todas las validaciones.
- **A VERIFICAR:** si otras interfaces habilitadas (por ejemplo, `pg_graphql`) pueden alcanzar el esquema privado, y si el advisor de Supabase marca igual la implementación.
- **Decisión:** **APROBADA PARA VALIDACIÓN CONTROLADA**. Contrato conceptual: Data API → fachada expuesta `SECURITY INVOKER` → implementación privada `SECURITY DEFINER` → validaciones completas → transacción de negocio.

### Comparación neutral

| Criterio | A | B | C | D |
|---|---|---|---|---|
| Compatible con §6 y §10:276 (sin DML directo) | No | Sí, si llama a una RPC | Sí | Sí |
| Coincide con Blueprint §10 vigente | No | No (reservada para lógica externa) | No | Sí |
| Sigue la guía de seguridad de Supabase | — | Depende de la RPC que llame | **No**: contradice la guía explícita (sin `SECURITY DEFINER` en esquema expuesto) | Sí |
| Función ejecutable por `authenticated` que corre con privilegios | Ninguna | La RPC subyacente | El wrapper expuesto | La implementación privada (no expuesta) |
| Componentes extra | — | Edge Function + salto de red | — | Fachada adicional por operación |
| Atomicidad dentro de Postgres | Sí | Solo con una única RPC | Sí | Sí |

**DECISIÓN VIGENTE (P1):** A queda descartada por incompatibilidad; B queda reservada para lógica externa; C no se elige por contradecir la guía de Supabase; D se aprueba para validación controlada. Esto no resuelve P2–P17 ni autoriza producción.

---

## 6. Transacciones, Edge Functions y `service_role`

- PostgREST ejecuta **cada solicitud HTTP en su propia transacción** (`START TRANSACTION; … END;`, *PostgREST v14, Transactions*). Por eso **varias llamadas independientes a la Data API**, ya sea desde el navegador o desde una Edge Function, **no forman una sola transacción**: si falla la segunda, la primera ya quedó confirmada.
- Si una Edge Function llama a **una única RPC transaccional**, esa RPC sigue siendo la **unidad atómica**. La Edge Function no agrega atomicidad ni la reemplaza.
- Una Edge Function para operaciones de usuario debería llamar a la base **con el JWT del usuario** (`Authorization`), de modo que se apliquen su rol y sus políticas RLS (*Supabase, Securing Edge Functions*).
- **`service_role` no se asume** para operaciones de usuarios. Según Supabase, ese rol tiene `bypassrls` y elude RLS (*Row Level Security: Bypassing RLS*). Usarlo sería una **alternativa excepcional** que exige justificación documentada y aprobación humana, porque toda la validación quedaría a cargo del código. Además, `auth.uid()` no identificaría al usuario final salvo que se pase su token. **RESUELTO PARA VALIDACIÓN CONTROLADA (P11 global, 24/10/2026, §18.2):** `service_role` queda denegado por defecto sobre los objetos de negocio; toda excepción es explícita, nominada y aprobada.
- Las RPC de escritura deben ser `VOLATILE` y llamarse por POST: PostgREST ejecuta GET/HEAD en una transacción READ ONLY y una escritura falla con 405 (*PostgREST v14, Transactions → Access Mode on Functions*).

---

## 7. Propietarios, ownership y RLS

Hechos documentados (PostgreSQL 18, *Row Security Policies*):

- "Superusers and roles with the `BYPASSRLS` attribute always bypass the row security system".
- "Table owners normally bypass row security as well, though a table owner can choose to be subject to row security with `ALTER TABLE ... FORCE ROW LEVEL SECURITY`". **El propietario de una tabla normalmente elude RLS aunque no tenga `BYPASSRLS`.**
- Con RLS habilitada y sin políticas aplicables rige una política de denegación por defecto.
- Los controles de integridad referencial (UNIQUE, PK, FK) siempre eluden RLS.

Hechos documentados (PostgreSQL 18, *CREATE ROLE* y *ALTER FUNCTION*):

- Los atributos por defecto de un rol nuevo son `NOLOGIN`, `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE` y `NOBYPASSRLS`. Solo un superusuario o un rol con `BYPASSRLS` puede otorgar `BYPASSRLS`.
- Para cambiar el propietario de una función hay que poder hacer `SET ROLE` al nuevo propietario, y ese rol necesita `CREATE` sobre el esquema de la función.

Requisito aprobado: propietario de **privilegio mínimo** (§10:278). **RESUELTO POR DECISIÓN HUMANA (P3, 23/10/2026):** el rol técnico se llama `propietario_rpc` (antes nombre provisorio `rpc_owner`) y tiene `NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS`, distinto de `postgres` y de `service_role`. Es propietario **únicamente** de las funciones privilegiadas privadas que realmente se necesiten y **nunca** de tablas de negocio. **No se crea en SQL** hasta que exista el primer objeto que dependa de él.

**RESUELTO POR DECISIÓN HUMANA (P4, 23/10/2026):**

- Las tablas de negocio permanecen bajo el **owner de migraciones/Supabase**; `propietario_rpc` no es propietario de tablas (pregunta 1: no).
- Toda tabla expuesta tiene **RLS obligatoria**.
- **No se impone `FORCE ROW LEVEL SECURITY` globalmente** en esta etapa (pregunta 2: no). Cualquier uso futuro de `FORCE` debe justificarse y probarse específicamente para esa tabla.
- Las futuras funciones `SECURITY DEFINER` viven en el esquema privado/no expuesto (P2), no son propietarias de tablas y **validan explícitamente** `auth.uid()`, empresa, rol, permisos, estado y la integridad aplicable (§9) antes de escribir: esas validaciones internas son la frontera de seguridad (pregunta 4), en línea con la Topología D.
- Como `propietario_rpc` es `NOBYPASSRLS` y no es propietario de las tablas, RLS se le aplica (pregunta 3): las políticas que necesite para operar se diseñan y prueban junto con la primera función privilegiada.

Texto original de las opciones, conservado como registro:

1. **¿`rpc_owner` puede ser propietario de tablas de negocio?** Si lo es, elude RLS sobre ellas como propietario, salvo que se aplique `FORCE`.
2. **¿Se aplica `FORCE ROW LEVEL SECURITY`?** Solo tiene efecto sobre un propietario sin `BYPASSRLS`; sobre `postgres` (que según Supabase elude RLS) no protege.
3. **¿RLS como defensa en profundidad para el rol técnico?** Si `rpc_owner` no es propietario y es `NOBYPASSRLS`, RLS se le aplica y necesita políticas propias que vuelvan a acotar por empresa.
4. **¿O la función privilegiada elude RLS deliberadamente** y depende de validaciones internas completas, aceptando que RLS no la protege?

Relaciones de propiedad: tablas de negocio y esquemas, del rol que ejecuta las migraciones (§12.6 y §17.2 siguen exigiendo confirmar ese rol en cada entorno); funciones privilegiadas privadas, de `propietario_rpc` (P3).

**Membresía del rol de migraciones en `propietario_rpc` (O-3, decisión humana del 24/10/2026, §18.2):** `postgres` conserva SET ROLE `propietario_rpc` (`set_option = true`), necesario para `ALTER FUNCTION … OWNER TO propietario_rpc`, pero no hereda sus privilegios (`inherit_option = false`).

---

## 8. Invariante de aislamiento por `empresa_id`

Requisito de diseño propuesto, que se deriva de §7.3 y §10:277 y queda sujeto a la aprobación de esta ADR:

1. **Ninguna relación entre objetos de negocio puede cruzar empresas.** Toda referencia, sea FK o referencia lógica (por ejemplo, de una venta a su jornada, de un movimiento a sus ubicaciones o de un pago a su venta), debe unir objetos con la misma `empresa_id`. "Filtrar por empresa" en consultas y RLS **no alcanza**.
2. El invariante debe garantizarse con **restricciones de integridad verificables** en la base, no solo con código de funciones ni con RLS. Esto es relevante porque PostgreSQL aplica las restricciones de integridad aunque eluda RLS. El mecanismo concreto (por ejemplo, claves compuestas que incluyan `empresa_id`) se define en el diseño del esquema; **todavía no se escribe DDL**.
3. Las unicidades de negocio deben estar acotadas por empresa (por ejemplo, la numeración de notas de papel por empresa y serie, §7.5:159). Así se evita que una restricción global filtre la existencia de datos de otra empresa (PostgreSQL advierte sobre estos *covert channels*).
4. `empresa_id` nunca se toma solo de lo que envía el cliente. Se deriva del perfil activo del actor y, si la operación recibe un id de objeto, también de ese objeto, y ambas deben coincidir.
5. Un objeto de otra empresa se trata **igual que uno inexistente** (sección 13).
6. **Pruebas obligatorias:** la batería debe incluir datos de **al menos dos empresas** e intentar cada relación con IDs mezclados (venta de A sobre jornada de B, movimiento de A con ubicación de B, pago de A sobre venta de B, etc.), tanto por las RPC como por escritura directa. Todas deben fallar. Esto no construye un registro de empresas (§7.3): las dos empresas son datos de prueba.

**RESUELTO POR DECISIÓN HUMANA (22/10/2026)** — ver §18. Texto original de las opciones, conservado como registro:

- **P5.** Cómo se resuelve la membresía activa:
  - (a) Fase 1 con una sola membresía activa por usuario, rechazando si hay 0 o más de 1;
  - (b) el cliente indica la empresa y el servidor verifica la membresía;
  - (c) un claim del JWT generado por hook (Supabase advierte que el JWT puede quedar desactualizado hasta refrescarse).
- **P6.** Si un usuario puede pertenecer a varias empresas. El Blueprint no lo define.
- **P7.** ¿Un rol o varios por membresía? (§8:227 dice "roles permitidos"; §9:268 dice "aunque una persona posea permisos adicionales").

---

## 9. Autorización

Cadena mínima de validaciones (requisitos de §10:274-277 y §9):

1. `auth.uid()` no nulo. Supabase documenta que es nulo en solicitudes sin sesión.
2. Perfil activo.
3. Empresa del actor resuelta desde su perfil (P5).
4. Rol vigente leído de tablas protegidas, nunca de `user_metadata`.
5. Permiso específico de la operación según §9.
6. Estado válido del objeto (por ejemplo, el estado de la jornada, §7.5:154).
7. Misma empresa para todos los objetos involucrados (sección 8).
8. Separación de funciones, cuando corresponda.

Separación de funciones aprobada: el conteo lo hace dueño o encargado, distinto de quien actuó como vendedor (§7.5:164); el vendedor no aprueba su propio conteo ni su rendición (§9); el retiro lo inicia dueño o encargado y queda confirmado solo con la confirmación de ambos participantes (§7.6:170, §12:353).

**PENDIENTE DE APROBACIÓN HUMANA:**

- **P8.** Qué es "participación real en la jornada" (§9:268): ¿solo el `vendedor_id` asignado o también quien registró o transcribió ventas?
- **P9.** Huecos de separación de funciones que el Blueprint no define: ¿quien contó puede aprobar la rendición? ¿Quien inicia el retiro puede ser también el receptor? ¿Quién verifica transferencias? (§15, prioridad media)
- **P10.** Catálogo exacto de operaciones y permisos por RPC.

---

## 10. Contrato de idempotencia

Aprobado: la **propiedad** de idempotencia (sección 3.1, ítem 10). **Todo el contrato concreto queda PENDIENTE DE APROBACIÓN HUMANA (P12)**:

| # | Aspecto | Pendiente de definir |
|---|---|---|
| I1 | **Reserva atómica** | Cómo se reserva la clave con una restricción de unicidad de la base, dentro de la **misma** transacción que el efecto, para que un rollback no deje reservas huérfanas. |
| I2 | **Alcance de la clave** | Por ejemplo, empresa + usuario + operación + clave, o empresa + operación + clave; y qué pasa si otro usuario reutiliza la misma clave. |
| I3 | **Huella del payload** | Qué parámetros entran, cómo se canonicalizan (preferentemente los parámetros ya tipados y validados, no el JSON crudo) y con qué algoritmo. |
| I4 | **Misma clave + mismo payload** | Devolver el **mismo resultado** guardado, sin efectos nuevos. |
| I5 | **Misma clave + payload diferente** | **Conflicto** no reintentable, sin efectos. |
| I6 | **Timeout con resultado desconocido** | El cliente reintenta con la **misma** clave y el mismo payload, nunca con una clave nueva. También hay que definir cómo se trata un rechazo de negocio, que no deja reserva porque la transacción se revierte. |
| I7 | **Concurrencia** | Qué observa la segunda solicitud simultánea con la misma clave (espera, repetición del resultado o conflicto), con prueba concurrente. |
| I8 | **Retención y caducidad** | Cuánto tiempo se conservan las claves y los resultados, y si caducan. |

Dónde se guarda (columna por tabla o tabla genérica de solicitudes) es parte del modelo propuesto (sección 3.2). La idempotencia (repetir una solicitud) es distinta de la **unicidad de negocio** (por ejemplo, que no se repita la nota de papel por empresa y serie, §7.5:159): ambas se requieren.

---

## 11. Concurrencia y bloqueos

Aprobado: transacciones atómicas y "protección contra concurrencia/bloqueos adecuados" (§10:280); las operaciones simultáneas deben revisarse (§7.4:150).

Hechos documentados (PostgreSQL 18): la mejor defensa contra deadlocks es tomar los bloqueos "in a consistent order" (*Explicit Locking*). Ante `40001` (serialization_failure) y `40P01` (deadlock_detected) se recomienda reintentar **la transacción completa** (*Serialization Failure Handling*).

**PENDIENTE DE APROBACIÓN HUMANA (P13):**

- nivel de aislamiento (READ COMMITTED con bloqueos explícitos o SERIALIZABLE);
- filas a bloquear y **orden estable** global (por ejemplo, jornada → documento → saldos ordenados por ubicación y producto);
- restricciones UNIQUE y CHECK de respaldo (cantidades e importes positivos; saldo no negativo sin activar la excepción de §7.4:150, que es una PROPUESTA NO APROBADA);
- política de reintentos del cliente: códigos, cantidad máxima de intentos y espera, siempre con la misma clave de idempotencia.

---

## 12. Grants y privilegios — requisitos de diseño

Requisitos de diseño propuestos (concretan §10:277-278; ninguno se ejecuta todavía):

1. **`USAGE` por esquema:** concedido explícitamente y solo a los roles que lo necesitan; nada por defecto a `PUBLIC` sobre el esquema privado.
2. **`EXECUTE` sobre la firma exacta:** cada grant y cada revocación nombra la firma completa (nombre y tipos de entrada). En PostgreSQL la identidad de una función es su nombre más sus tipos de entrada (*CREATE FUNCTION*).
3. **Política de sobrecargas:** las funciones expuestas no se sobrecargan, porque una sobrecarga es otra función con sus propios privilegios. PostgREST tampoco admite sobrecargas con los mismos nombres de argumento y distintos tipos. **PENDIENTE (P14):** si se prohíben del todo o solo en lo expuesto.
4. **Revocación de `PUBLIC`:** PostgreSQL concede `EXECUTE` a `PUBLIC` por defecto en toda función nueva. Hay que revocarlo de `PUBLIC` **y** de cada rol con grant directo (`anon`, `authenticated`, `service_role`, según la configuración del proyecto).
5. **Creación y revocación en la misma transacción:** crear la función y fijar sus privilegios dentro de una sola transacción, para que no exista una ventana en la que quede accesible para todos (*CREATE FUNCTION, Writing SECURITY DEFINER Functions Safely*).
6. **`ALTER DEFAULT PRIVILEGES` sobre el rol creador real:** los privilegios por defecto se definen por rol creador (`FOR ROLE`). Hay que aplicarlos al rol que **realmente** ejecuta las migraciones; según Supabase, las funciones creadas por migración son de `postgres`, pero se confirma en el entorno (sección 17.2).
   - **Corrección técnica respecto de v1.1:** en PostgreSQL un `REVOKE` por esquema (`IN SCHEMA ...`) **no elimina** un privilegio concedido globalmente, como el `EXECUTE` de `PUBLIC`. Solo deshace un `GRANT` previo hecho por esquema (*ALTER DEFAULT PRIVILEGES*: "This command has no effect, unless it is undoing a matching GRANT"). Para `PUBLIC` corresponde la forma **global**, sin `IN SCHEMA`. La guía *Hardening the Data API* de Supabase muestra la forma por esquema para `PUBLIC`; **las dos fuentes difieren** y se resuelve con una prueba de catálogo (sección 17.1).
7. **Sin DML directo** de `anon` ni `authenticated` sobre los libros (§10:276).
8. **`service_role` y roles operativos internos:** sin `EXECUTE` sobre las RPC de negocio salvo una necesidad operativa justificada y aprobada (sección 6, P11). P11 global resuelto para validación controlada el 24/10/2026 (§18.2).

---

## 13. Contrato de errores

**PENDIENTE DE APROBACIÓN HUMANA (P16)** en cuanto a códigos y forma exactos. Requisitos propuestos:

- **Categorías de negocio estables** (borrador): no autenticado, no autorizado, no encontrado, estado inválido, validación, stock insuficiente (según la regla vigente), duplicado de negocio, conflicto de idempotencia y error interno.
- **Sin filtración de información de otras empresas:** un objeto de otra empresa responde igual que uno inexistente. Las violaciones de restricciones (por ejemplo, `23505` o `23503`) no deben llegar en crudo al cliente, porque su detalle puede incluir valores de la clave; se traducen a la categoría de negocio.
- **No usar `40001` para errores de negocio.** `40001` y `40P01` quedan reservados para fallas reales de concurrencia de PostgreSQL.
- **Reintentables:** `40001`, `40P01`, fallas de conexión y timeouts con resultado desconocido, siempre con la misma clave de idempotencia. **No reintentables:** todas las categorías de negocio, el conflicto de idempotencia y la falta de privilegios.
- Hecho documentado (*PostgREST v14, Errors*): PostgREST traduce los SQLSTATE `40*` a **HTTP 500**, `23505` y `23503` a 409 y `P0001` a 400, y admite códigos `PTxyz` para fijar el estado HTTP. Por eso el cliente no puede decidir si reintenta mirando solo el estado HTTP: tiene que leer el código del cuerpo.

---

## 14. Auditoría

- **Aprobado:** la trazabilidad y auditabilidad como propiedad (sección 3.1, ítem 9).
- **Propuesto, no aprobado:** la tabla concreta `auditoria` y sus columnas (sección 3.2).
- **Operaciones exitosas.** RECOMENDACIÓN NO VINCULANTE: registrar la auditoría dentro de la **misma transacción** que el cambio (actor, empresa, operación, objeto, datos antes y después, clave y huella de idempotencia, hora del servidor y hora declarada). Así la operación y su registro se confirman o se revierten juntos (§6:98). Mecanismo exacto: **PENDIENTE (P17)**.
- **Operaciones rechazadas.** Si la transacción se revierte, **nada de lo escrito en ella persiste**, incluido cualquier registro de rechazo. Esta ADR no propone guardar intentos rechazados en la base. Cualquier registro externo o fuera de la transacción queda como **decisión futura separada** (P18), fuera de esta ADR.

---

## 15. Gobernanza aprobada: aprobación para validación → prueba → aceptación final

**Problema histórico.** Las reglas anteriores formaban un ciclo imposible de cumplir:

- el Blueprint pedía aprobar el patrón y probar revocaciones y permisos "desde roles reales";
- no permitía generar migraciones hasta aprobar ADR-001 y pasar pruebas de autorización;
- la ronda 1 de esta ADR pedía verificar en staging "antes de cualquier aprobación".

Las pruebas necesitan un esquema; el esquema necesita migraciones; y las migraciones necesitan la aprobación y las pruebas ya aprobadas.

**Decisión vigente (P19/P20).** Se adopta un proceso de dos aprobaciones. La primera habilita sólo la validación controlada local/staging; la segunda es la aceptación humana final previa a producción.

**Paso 0 — Gobernanza (resuelto):**

1. **P19 RESUELTO:** aprobación para validación controlada → evidencia y auditoría → aceptación humana final antes de producción.
2. **P20 RESUELTO:** antes del estado intermedio no se generan migraciones dependientes de ADR-001; después se permiten sólo las necesarias para validar en local/staging. Producción sigue prohibida.
3. **Documentos rectores alineados:** `BLUEPRINT.md`, este ADR y `docs/decisions/README.md` usan el estado único `APROBADA PARA VALIDACIÓN CONTROLADA`.

**Paso 1 — Recién después del paso 0: decisiones técnicas necesarias para una validación controlada local o en staging.** El dueño del proyecto aprueba explícitamente:

| Decisión | Por qué la necesita la validación |
|---|---|
| P2, P3, P4 | Esquemas, rol propietario, ownership y RLS: sin ellos no se puede crear ningún objeto. **Resueltas el 23/10/2026 (§18).** |
| P5, P6, P7 | Modelo de membresía y roles para los datos de prueba (T2–T6). **Resueltas el 22/10/2026 (§18).** |
| P8, P9 | Separación de funciones (T13) |
| P10 | Catálogo de operaciones a ensayar (puede acotarse a un subconjunto representativo) |
| P11 | Grants de `service_role` y roles internos (T16, sección 17.3). **Resuelta el 24/10/2026 (§18.2).** |
| P12, P15 | Contrato y ubicación de la idempotencia (T10–T12) |
| P13 | Aislamiento, bloqueos y reintentos (T12) |
| P14 | Sobrecargas (T16) |
| P16 | Contrato de errores (T15) |
| P17 | Auditoría de operaciones exitosas |

Si el dueño acota la validación a un subconjunto de operaciones, solo hacen falta las decisiones que ese subconjunto requiera. **P18 no es requisito previo:** es una decisión futura separada (sección 14). Esa aprobación **no** autoriza producción.

**Paso 2 — Implementación exclusivamente local o en staging.** Una vez resueltas las P2–P17 necesarias (P2–P7 y P11 ya lo están; quedan P8–P10 y P12–P17) para el alcance elegido, se permiten migraciones, roles, schemas y grants sólo en entornos aislados (§10). Nada de `supabase db push`, `supabase migration up` ni comandos contra producción (`AGENTS.md` §5).

**Paso 3 — Pruebas.** Toda la matriz de la sección 16 y las verificaciones de la sección 17, con evidencia citada y auditoría independiente (`AGENTS.md` §2).

**Paso 4 — Segunda aceptación humana antes de producción.** El dueño acepta los resultados; recién entonces la ADR pasa a `aprobada` para producción.

**Producción permanece bloqueada.** El estado intermedio no equivale a aceptación productiva ni permite omitir decisiones pendientes.

---

## 16. Matriz de pruebas obligatorias

Base: `BLUEPRINT.md` §12, con pgTAP en `supabase/tests/` ejecutado por `supabase test db` en un entorno aislado, más pruebas HTTP contra la Data API local y un arnés concurrente. Su implementación depende de resolver las decisiones P8–P10 y P12–P17 necesarias de la sección 15, paso 1 (P2–P7 y P11 ya están resueltas).

| # | Caso | Resultado esperado |
|---|---|---|
| T1 | `anon` llama a cada RPC expuesta | Rechazo; sin efectos |
| T2 | `authenticated` sin perfil | Rechazo; sin efectos ni datos visibles |
| T3 | Perfil inactivo | Rechazo |
| T4 | Usuario de otra empresa sobre objetos ajenos | Igual que inexistente; sin efectos |
| T5 | IDs mezclados entre dos empresas, por cada relación (sección 8) | Falla por restricción de integridad, por RPC y por escritura directa |
| T6 | Cada rol de negocio (dueño, encargado, vendedor/piloto) en cada operación | Solo lo que permite §9 |
| T7 | DML directo (INSERT/UPDATE/DELETE) de `anon` y `authenticated` sobre libros y registros confirmados, por Data API y por SQL | Rechazo |
| T8 | Llamada directa a funciones internas o privadas, por Data API | No accesible |
| T9 | Objeto en estado inválido (por ejemplo, jornada cerrada) | Rechazo; jornada inmutable |
| T10 | Misma clave + mismo payload | Mismo resultado; un solo efecto |
| T11 | Misma clave + payload diferente | Conflicto; sin efectos |
| T12 | Solicitudes concurrentes con la misma clave y sobre el mismo stock o la misma jornada | Un solo efecto; saldos correctos; sin deadlock no manejado |
| T13 | Separación de funciones: el vendedor intenta contar o aprobar su propia jornada; retiro con una sola confirmación | Rechazo / sin efecto en caja |
| T14 | GET sobre una RPC de escritura | 405 (READ ONLY) |
| T15 | Contrato de errores: un error no revela datos de otra empresa ni detalles de restricciones | Solo códigos de negocio |
| T16 | Catálogo (regresión, sección 17.3) | Todas las aserciones en verde |

---

## 17. Verificación: qué se prueba y dónde

### 17.1 Comportamiento documentado que igualmente debe probarse

Está documentado y **no es una incógnita del entorno**. Se prueba para detectar errores de implementación; puede probarse **localmente**.

- `SET search_path = ''`: con search path vacío todo objeto debe estar calificado con su esquema (PostgreSQL *CREATE FUNCTION*; Supabase lint 0011). Se prueba que cada función lo tenga fijado y que funcione con nombres calificados.
- `EXECUTE` a `PUBLIC` por defecto en funciones nuevas, y su revocación efectiva.
- Que un `REVOKE` de privilegios por defecto hecho por esquema no elimina un grant global (sección 12.6).
- Que el propietario de una tabla elude RLS salvo `FORCE`, y que `BYPASSRLS` o superusuario la eluden siempre.
- Que las restricciones de integridad se aplican aunque RLS esté eludida.
- Que GET corre en READ ONLY; la traducción de SQLSTATE a HTTP de PostgREST.
- Comportamiento de unicidad ante inserciones concurrentes.
- **Concurrencia (T12):** se verifica primero **localmente** con varias conexiones simultáneas; no requiere staging necesariamente.

**Comportamiento documentado por Supabase que igualmente debe probarse como regresión en nuestro entorno.** No es una incógnita sobre el proveedor. Se prueba en local y staging porque el proyecto tiene que verificar sus propios grants, políticas, propietarios y configuración:

- **`auth.uid()` dentro de funciones `SECURITY DEFINER`.** Supabase lo documenta en sus ejemplos de *Row Level Security* (`private.has_good_role()` y `private.user_list_ids()`, que usan `(select auth.uid())` dentro de funciones `security definer`). Se prueba que, con nuestros propietarios, grants y `search_path = ''`, cada función privilegiada identifique al llamador y rechace cuando `auth.uid()` es nulo.
- **Usuarios de inicio de sesión anónimo.** Supabase documenta que el usuario anónimo usa el rol de PostgreSQL `authenticated`, igual que un usuario permanente, y que su JWT lleva el claim `is_anonymous` (*Anonymous Sign-Ins*). Por lo tanto, `authenticated` no equivale a "usuario con cuenta". Si el inicio anónimo está habilitado, se prueba que ese usuario quede rechazado por falta de perfil (T2) y que ningún grant ni política le dé acceso solo por tener el rol `authenticated`.

**Dependiente de la configuración del proyecto** (se prueba en local y staging):

- si `pg_graphql` u otra interfaz habilitada alcanza el esquema privado.

### 17.2 Propiedades que dependen del entorno (local vs. staging vs. alojado)

- Rol que realmente ejecuta las migraciones en el proyecto alojado y sus atributos (`rolsuper`, `rolbypassrls`, `rolcreaterole`).
- Privilegios por defecto que la plataforma concede al crear el proyecto. Supabase cambia ese default "so that exposure becomes opt-in" (*Securing your API*).
  - **Fecha confirmada por el proveedor:** según el anuncio oficial de Supabase (*Breaking Change: Tables not exposed to Data and GraphQL API automatically*, discusión n.º 45329), el nuevo comportamiento es el default de los proyectos nuevos desde el 30/05/2026 y se aplica a **todos los proyectos existentes el 30/10/2026**.
  - **Verificación propia del proyecto (aparte de esa fecha):** en cada entorno hay que comprobar qué esquemas quedan efectivamente expuestos, qué grants existen sobre tablas y funciones y cómo responde la Data API (secciones 16 y 17.3). La fecha de despliegue del proveedor no reemplaza esa verificación.
- Esquemas expuestos configurados en la Data API.
- Extensiones habilitadas (por ejemplo, `pg_graphql`) y configuración de Auth (inicio de sesión anónimo, tipo de claves).
- Versión mayor de PostgreSQL del proyecto, que afecta detalles de pertenencia a roles necesarios para `ALTER ... OWNER TO`.

### 17.3 Pruebas de regresión (en cada migración futura)

Aserciones de catálogo que se repiten siempre:

- ninguna función `SECURITY DEFINER` fuera de la lista aprobada;
- cada función privilegiada con `search_path` vacío y con el propietario aprobado;
- sin `EXECUTE` para `PUBLIC` ni `anon`, y `EXECUTE` de `authenticated` solo en las firmas aprobadas;
- sin sobrecargas en las funciones expuestas;
- sin DML directo de `anon` ni `authenticated` sobre los libros;
- RLS habilitada en todas las tablas expuestas; `FORCE` sólo donde una decisión específica lo justifique y lo pruebe (P4).

---

## 18. Estado de las decisiones

| # | Decisión | Sección |
|---|---|---|
| P8 | Definición de "participación real en la jornada" | 9 |
| P9 | Huecos de separación de funciones (aprobación por quien contó, receptor = iniciador, verificación de transferencias) | 9 |
| P10 | Catálogo de operaciones y permisos por RPC | 9 |
| P12 | Contrato de idempotencia I1–I8 | 10 |
| P13 | Aislamiento, orden de bloqueos, restricciones de respaldo y política de reintentos | 11 |
| P14 | Política de sobrecargas | 12 |
| P15 | Interpretación de `idempotency_key` en §7.6:171 (contenido aprobado vs. nombre de columna) | 3.2 |
| P16 | Contrato de errores | 13 |
| P17 | Mecanismo de auditoría de operaciones exitosas | 14 |
| P18 | Registro de intentos rechazados (**decisión futura separada**) | 14 |

**P8–P10 y P12–P17 continúan pendientes como decisiones globales** (para el dominio Stock rigen las decisiones acotadas de §18.3). **P18 continúa como decisión futura separada y no es requisito previo.** P11 global quedó resuelta el 24/10/2026 para validación controlada (§18.2). Para el slice productos rigen además las decisiones acotadas de §18.1, que no cambian este estado global.

| # | Decisión resuelta | Resultado | Sección |
|---|---|---|---|
| P1 | Topología | **Topología D:** fachada expuesta `SECURITY INVOKER` + implementación privada/no expuesta `SECURITY DEFINER` | 4, 5 |
| P19 | Gobernanza | Dos etapas: aprobación para validación controlada y aceptación humana final antes de producción | 15 |
| P20 | Migraciones | Permitidas sólo para validación local/staging; producción bloqueada | 2, 15 |
| P5 | Resolución de la membresía activa | Variante de la opción (a) sin tabla de membresías: cada usuario tiene **un único perfil** en `perfiles`, 1:1 con `auth.users`, que fija su empresa. Sin perfil o con perfil inactivo, acceso denegado. La empresa nunca la indica el cliente (decisión humana, 22/10/2026) | 8 |
| P6 | Usuarios con varias empresas | **No.** En Fase 1 un usuario pertenece a una sola empresa; sin selector de empresa ni múltiples empresas por usuario (decisión humana, 22/10/2026) | 8 |
| P7 | Uno o varios roles | **Un único rol por perfil:** `dueno`, `encargado` o `vendedor_piloto`. Sin tabla `roles` (decisión humana, 22/10/2026) | 8 |
| P2 | Esquemas expuesto y privado | **`public`** es el esquema expuesto para las tablas que la aplicación necesita; **`privado`** será el esquema no expuesto para las futuras implementaciones privilegiadas. `privado` no se crea hasta que exista la primera implementación que viva allí (decisión humana, 23/10/2026) | 5 |
| P3 | Rol propietario técnico | **`propietario_rpc`**: `NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS`; propietario sólo de las funciones privilegiadas privadas necesarias, nunca de tablas de negocio. Se crea junto con el primer objeto que dependa de él (decisión humana, 23/10/2026) | 7 |
| P4 | Ownership, `FORCE RLS` y frontera de seguridad | Tablas de negocio del owner de migraciones/Supabase; RLS obligatoria en toda tabla expuesta; **sin `FORCE ROW LEVEL SECURITY` global** (todo uso futuro, justificado y probado); funciones `SECURITY DEFINER` en `privado`, sin ser propietarias de tablas y con validación explícita de `auth.uid()`, empresa, rol, permisos, estado e integridad (decisión humana, 23/10/2026) | 7 |
| P11 | Uso excepcional de `service_role` y de roles operativos internos | **Denegado por defecto** sobre objetos de negocio; excepciones explícitas, nominadas y aprobadas; única vigente: SELECT sobre `public.productos` (decisión humana, 24/10/2026; **aprobada para validación controlada**, no productiva) | 6, 12, 18.2 |

### 18.1 Decisiones de validación acotadas al slice productos (23/10/2026)

> **Alcance estricto.** Estas decisiones humanas aplican **únicamente** al slice «catálogo de productos» (`public.productos` y sus RPC). **No resuelven P10–P17 globalmente**: para cualquier otra operación siguen pendientes (P11 global se resolvió después, el 24/10/2026, en §18.2). **No cambian el estado de esta ADR**, que sigue siendo **APROBADA PARA VALIDACIÓN CONTROLADA**, y **no autorizan producción**. Se registran como ensayo de la Topología D dentro del alcance local/staging que permite P20.

| # | Decisión acotada a productos | Estado global |
|---|---|---|
| P10-productos | `dueno` y `encargado` pueden crear, actualizar y cambiar el estado (baja lógica/reactivación) de productos; `vendedor_piloto` sólo lee. RPC: `crear_producto`, `actualizar_producto`, `cambiar_estado_producto`. | P10 global pendiente |
| P11-productos | `service_role` no recibe `EXECUTE` sobre estas RPC (ni sobre sus fachadas ni sobre sus implementaciones privadas) y **no escribe directamente `public.productos`**: sin `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES` ni `TRIGGER`. Conserva `SELECT`. Complemento del 23/10/2026 tras el hallazgo H-01 de The Architect (por defecto Supabase le concedía todos los privilegios y `BYPASSRLS` habría permitido saltear la validación del precio). No cambia los privilegios de `service_role` sobre `perfiles` ni sobre Auth. | P11 global resuelta (§18.2); este SELECT es su única excepción vigente |
| P12/P15-productos | El ABM de productos no usa idempotencia ni `idempotency_key`: no figura entre los comandos críticos de `BLUEPRINT.md` §7.9.6. | P12/P15 globales pendientes |
| P13-productos | Sin bloqueos explícitos; la actualización de un solo producto se resuelve con «gana la última escritura». | P13 global pendiente |
| P14-productos | Sin sobrecargas de estas funciones, ni en `public` ni en `privado`. | P14 global pendiente |
| P16-productos | Errores con códigos estables `producto_*` en `message` y SQLSTATE `PTxyz` (PostgREST responde HTTP `xyz`); el frontend nunca expone el detalle SQL/PostgREST crudo. | P16 global pendiente |
| P17-productos | La trazabilidad del dato maestro se limita a `creado_en` y `creado_por`; cualquier auditoría adicional de datos maestros es una decisión futura (`BLUEPRINT.md` §10). | P17 global pendiente |

**Decisiones de diseño del slice, también aprobadas por decisión humana:**

- **DE-2 — precio exacto.** `productos.precio` se persiste como `numeric(14,2)`. Como toda asignación a esa columna redondea antes de cualquier CHECK, trigger o política, el rechazo de más de 2 decimales se hace sobre un parámetro `numeric` sin escala, **antes** del CAST, dentro de la RPC. Con `SECURITY INVOKER` el usuario conservaría un INSERT/UPDATE directo que saltea esa validación; por eso la escritura usa la **Topología D**: fachada `SECURITY INVOKER` en `public` e implementación `SECURITY DEFINER` en `privado`, propiedad de `propietario_rpc`. `authenticated` sólo tiene `SELECT` sobre `productos`.
- **DE-11 — empresa derivada en el servidor.** `empresa_id` no es parámetro de ninguna RPC: la implementación privada la deriva del perfil activo del llamador (coherente con §8.4).
- **DE-15 — control de decimales por valor.** `round(p_precio, 2) = p_precio`, evaluado junto con `p_precio >= 0` y `p_precio < 10^12` en forma fail-closed: `20.990` se acepta y `20.999` se rechaza.
- **DE-3 — código.** Opcional; se normaliza con trim, un vacío pasa a `NULL` y se conservan mayúsculas y minúsculas; único por empresa.
- **Identidad dentro de `propietario_rpc`.** Verificado en local: el rol de migraciones no puede conceder `USAGE` sobre el esquema `auth` (propiedad de `supabase_admin`), así que `propietario_rpc` no puede invocar `auth.uid()`. El helper `privado.usuario_actual()` lee el claim `sub` del JWT con la misma expresión que `auth.uid()`. **No usa `user_metadata`** y **no deriva empresa ni rol del JWT**: empresa y rol se siguen leyendo de `perfiles`. Una prueba pgTAP verifica que el helper y `auth.uid()` coincidan.

Implementación y evidencia: `supabase/migrations/20261023140000_catalogo_productos.sql`, `supabase/tests/productos_catalogo.test.sql` y la entrada «Catálogo de productos en Supabase (slice productos)» de `docs/progress-log.md`.

### 18.2 Decisiones transversales: P11 global, O-3 y O-4 (24/10/2026)

> **Alcance.** Decisiones humanas **aprobadas para validación controlada** (local/staging). **No cambian el estado de esta ADR**, que sigue siendo **APROBADA PARA VALIDACIÓN CONTROLADA**, **no autorizan producción** y no resuelven P8–P10 ni P12–P17. O-3 y O-4 son observaciones de las validaciones de staging del 23–24/10/2026 (`docs/progress-log.md`).

**P11 global — `service_role` y roles internos.**

- `service_role` queda **denegado por defecto** sobre los objetos de negocio: no recibe privilegios de tabla ni `EXECUTE` sobre las RPC de negocio (fachadas de `public` ni implementaciones de `privado`) salvo una excepción **explícita, nominada y aprobada**.
- **Excepción vigente:** `SELECT` sobre `public.productos` (P11-productos, §18.1). No autoriza `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER`, `MAINTAIN` ni `EXECUTE`.
- Toda decisión futura que necesite `service_role` debe documentar y aprobar su excepción.
- Esta decisión global reemplaza el estado «P11 global pendiente», sin invalidar la excepción específica aprobada para productos.

**O-3 — membresía `postgres` → `propietario_rpc`.**

- `postgres` conserva la capacidad de `SET ROLE propietario_rpc` (`set_option = true`), necesaria para `ALTER FUNCTION … OWNER TO propietario_rpc`.
- `inherit_option = false`: no se requiere la herencia permanente de los privilegios de `propietario_rpc`.
- Las migraciones futuras que necesiten actuar como owner técnico (por ejemplo, redefinir, alterar o revocar privilegios sobre funciones de `privado`) usan `SET ROLE propietario_rpc` explícitamente cuando corresponda.
- El runtime de las RPC no depende de esta membresía: la implementación `SECURITY DEFINER` corre como su owner.
- La fila de membresía con ADMIN OPTION que PostgreSQL crea automáticamente al crear el rol (grantor `supabase_admin`, sin SET ni INHERIT) no forma parte de esta decisión.

**O-4 — `public.rls_auto_enable()`.**

- Se conservan `public.rls_auto_enable()` y el event trigger `ensure_rls` (objetos del proyecto alojado, no definidos en las migraciones del repositorio).
- Se revoca `EXECUTE` sobre `public.rls_auto_enable()` a PUBLIC, `anon`, `authenticated` y `service_role`.
- No se modifica el comportamiento funcional del event trigger. Verificado en local con una réplica: el disparo de un event trigger no chequea `EXECUTE` del rol que ejecuta el DDL y la función `SECURITY DEFINER` corre como su owner; una función `event_trigger` no puede invocarse directamente.

**Evidencia read-only de staging que fundamentó O-4 (24/10/2026).**

- Proyecto de staging `rtsncntppghdynzhezzg`; PostgreSQL 17.11; sesión en `BEGIN TRANSACTION READ ONLY` con `transaction_read_only = on`, terminada con `ROLLBACK`; cero escrituras. 6 migraciones presentes, incluida `20261024180000`.
- `public.rls_auto_enable()`: owner `postgres`; `SECURITY DEFINER`; `search_path=pg_catalog`; retorno `event_trigger`; ACL `{=X/postgres, postgres=X/postgres, anon=X/postgres, authenticated=X/postgres, service_role=X/postgres}`: EXECUTE **explícito** para PUBLIC, `anon`, `authenticated` y `service_role` (entradas directas en la ACL, no heredadas). Su cuerpo habilita RLS en las tablas nuevas de `public` creadas con `CREATE TABLE`, `CREATE TABLE AS` o `SELECT INTO`.
- `ensure_rls`: owner `postgres`; habilitado; evento `ddl_command_end`; tags `CREATE TABLE`, `CREATE TABLE AS`, `SELECT INTO`; es la **única** dependencia de event trigger sobre esa función (ningún trigger de tabla la usa).
- Causa de los lints 0028/0029: función `SECURITY DEFINER` en `public` (esquema expuesto, con USAGE para `anon` y `authenticated`) y EXECUTE explícito para esos roles.

Implementación y evidencia local: `supabase/migrations/20261024232059_hardening_adr001_p11_o3_o4.sql`, `supabase/tests/hardening_adr001.test.sql`, `supabase/tests/grants_default_privileges.test.sql` y la entrada «Hardening transversal ADR-001: P11 global, O-3 y O-4» de `docs/progress-log.md`. La aplicación de la migración en staging y su validación posterior quedan pendientes de autorización humana.

### 18.3 Decisiones acotadas al dominio Stock (25/10/2026)

> **Alcance estricto.** Decisiones humanas **aprobadas para validación controlada** que aplican **únicamente al dominio Stock** (`public.operaciones`, `public.movimientos_stock`, `public.stock_actual` y sus RPC; slices `stock-ingreso` y `stock-cuarentena-merma`). **No resuelven P10–P17 globalmente**: jornadas, ventas, dinero, retiros, conteos, rendiciones y cierres siguen pendientes. **No cambian el estado de esta ADR**, que sigue siendo **APROBADA PARA VALIDACIÓN CONTROLADA**, y **no autorizan producción**.

| # | Decisión acotada a Stock | Estado global |
|---|---|---|
| P10-stock | Catálogo del slice 1: sólo `registrar_ingreso` (exterior → depósito), permitido a `dueno` y `encargado`; el vendedor/piloto no. `mover_a_cuarentena` y `registrar_merma` requieren una decisión previa (roles y motivo); `cuarentena_apta`, regularizaciones y `ajuste` quedan **BLOCKED** (criterios de aptitud pendientes, dependencia de conteos y permiso de administrador no definido). Lectura de `operaciones`, `movimientos_stock` y `stock_actual`: sólo `dueno` y `encargado` de la misma empresa con perfil activo. | P10 global pendiente |
| P12-stock | Idempotencia en `operaciones`: `UNIQUE (empresa_id, actor_id, idempotency_key)` con `idempotency_key uuid`; el tipo no integra la unicidad y va dentro de la huella; retención indefinida en Fase 1; sin columna de resultado: el resultado estable del replay es `operaciones.id`. Misma clave + misma huella → mismo id sin efectos; misma clave + otra huella u otro tipo → `PT409 stock_conflicto_idempotencia`; un rechazo de negocio no deja reserva. **Huella v1:** SHA-256 hex en minúsculas de `v1\|ingreso\|<producto uuid>\|<cantidad>\|<motivo>`, con `<motivo>` = `-` si es NULL y `+` + motivo normalizado si no; un cambio de semántica crea `v2` y nunca se reinterpretan operaciones existentes. | P12 global pendiente |
| P13-stock | `READ COMMITTED` + `pg_advisory_xact_lock` por empresa + ubicación + producto, tomados en orden global, **sólo en las RPC que debitan stock**; el saldo se calcula después del lock. `registrar_ingreso` sólo acredita y no toma locks. Depósito y cuarentena nunca negativos; el negativo transitorio en camión sigue **PROPUESTA NO APROBADA**. Reintento del cliente: máximo 3, misma clave y mismo payload, ante `40001`, `40P01`, conexión perdida o timeout con resultado desconocido; `55P03` sólo si proviene de la política explícita de locks; `57014` sólo si es un timeout o cancelación recuperable; `PTxxx` nunca. | P13 global pendiente |
| P14-stock | Sin sobrecargas de las RPC de Stock, ni en `public` ni en `privado`. | P14 global pendiente |
| P15-stock | `idempotency_key` vive sólo en `operaciones`; no se duplica en `movimientos_stock` (§7.9.1). | P15 global pendiente |
| P16-stock | Errores `stock_*` con SQLSTATE `PTxyz`: `PT401 stock_no_autenticado`, `PT403 stock_no_autorizado`, `PT400 stock_clave_invalida`, `PT400 stock_cantidad_invalida`, `PT404 stock_producto_no_encontrado` (otra empresa e inexistente, indistinguibles), `PT409 stock_producto_inactivo`, `PT409 stock_conflicto_idempotencia`, `PT500 stock_ubicacion_no_configurada`, `PT500 stock_error_interno`. Sin nombres de restricción ni datos de otra empresa; `40001` nunca para errores de negocio. | P16 global pendiente |
| P17-stock | La auditoría de operaciones exitosas de Stock es `operaciones` (actor, empresa, tipo, clave, huella, `creado_en`) + `movimientos_stock` (operación, actor, motivo, producto, cantidad, origen, destino, `creado_en`); sin tabla genérica `auditoria` (Blueprint §10). `jornada_id` se agrega en la Etapa 3 con FK real. Append-only por grants y RLS, sin trigger. | P17 global pendiente |

Implementación y evidencia: `supabase/migrations/20261025021032_stock_operaciones_ingreso.sql`, `supabase/tests/stock_ingreso.test.sql` y la entrada «Etapa 2 — Stock, slice 1: stock-ingreso» de `docs/progress-log.md`.

#### Slice 2 `stock-cuarentena-merma` (25/10/2026)

Mismo alcance estricto: **sólo dominio Stock**. Estas decisiones **no resuelven P10–P17 globalmente**, **no habilitan la Etapa 3** (carga, jornadas, camión como origen), **ni `cuarentena_apta`**, **ni el negativo transitorio en camión** (sigue **PROPUESTA NO APROBADA**), no cambian el estado de la ADR (**APROBADA PARA VALIDACIÓN CONTROLADA**) y **no autorizan producción**.

| # | Decisión acotada a Stock | Estado global |
|---|---|---|
| D1 (P10-stock) | `mover_a_cuarentena` y `registrar_merma`: `dueno` y `encargado`, sin diferencias entre ellos; el vendedor/piloto recibe `PT403`. | P10 global pendiente |
| D2 | Motivo de cuarentena: texto obligatorio, `btrim`, vacío → NULL → `PT400 stock_motivo_invalido`. Sin catálogo. | — |
| D3 | Origen sólo depósito; cuarentena o camión → `PT400 stock_origen_invalido`. Sin error `stock_camion_inactivo`. | — |
| D4 | Sin merma desde cuarentena (queda para la revisión de cuarentena). | — |
| D5 | `motivo_codigo` de merma: catálogo literal de Blueprint §7.7 (`vencido`, `roto_danado`, `mal_estado`, `error_pedido`, `cambio`, `otro`), comparación exacta después de `btrim` (sin pasar a minúsculas). | — |
| D6 | Columna `movimientos_stock.motivo_codigo text`: obligatoria y del catálogo para merma; `otro` exige `motivo`; NULL para ingreso y `a_cuarentena`. | — |
| D7 | Índice único parcial `movimientos_stock_operacion_unitaria_unica (empresa_id, operacion_id) WHERE tipo_movimiento IN ('ingreso','a_cuarentena','merma')`: una operación unitaria, un movimiento. | — |
| D8 | La policy de INSERT del ledger exige que el ingreso vaya a una ubicación propia de tipo depósito; `a_cuarentena` depósito propio → cuarentena propia; merma depósito propio → NULL; el tipo del movimiento debe coincidir con el de la operación. | — |
| D9 | Un solo slice y una sola migración para ambas RPC. La cantidad de archivos de tests no está restringida: pueden separarse cuando sea técnicamente necesario (p. ej., un archivo por nivel de aislamiento, REPEATABLE READ y SERIALIZABLE). | — |
| P12-stock (huellas v1) | `v1\|a_cuarentena\|<producto>\|<origen>\|<cantidad>\|<m>` y `v1\|merma\|<producto>\|<origen>\|<cantidad>\|<motivo_codigo>\|<m>`, con `<m>` = `-` si el motivo es NULL y `+` + motivo normalizado si no; el destino de la cuarentena se resuelve en el servidor y no integra la huella. Replay: se verifica la autorización vigente antes; con la misma huella devuelve el id original sin revalidar estado mutable. | P12 global pendiente |
| P13-stock (lock concreto) | Un único `pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('stock:' \|\| empresa \|\| ':' \|\| origen \|\| ':' \|\| producto, 0))` por RPC, tomado después de la idempotencia y de validar producto y origen, y antes de leer el saldo; sin lock del destino. El saldo (bigint) se lee después del lock; si no alcanza → `PT409 stock_insuficiente`, sin revelar saldo. El modelo aprobado es `READ COMMITTED`: estas dos RPC de débito lo verifican explícitamente como primera comprobación y, con otro aislamiento, fallan cerradas con `PT500 stock_error_interno`, sin cambiar el aislamiento del caller (con una instantánea fija, el saldo leído después del lock sería el previo). Sus pruebas viven en archivos propios por nivel de aislamiento. | P13 global pendiente |
| P16-stock (errores nuevos) | `PT400 stock_motivo_invalido`, `PT400 stock_origen_invalido`, `PT404 stock_ubicacion_no_encontrada` (otra empresa e inexistente, indistinguibles), `PT409 stock_insuficiente`; `PT500 stock_ubicacion_no_configurada` también si no hay exactamente una cuarentena. | P16 global pendiente |

Implementación y evidencia: `supabase/migrations/20261025033454_stock_cuarentena_merma.sql`, `supabase/tests/stock_cuarentena_merma.test.sql` y la entrada «Etapa 2 — Stock, slice 2: stock-cuarentena-merma» de `docs/progress-log.md`.

### 18.4 Decisiones acotadas a Jornadas y carga (versión 0.4 con fe de erratas E1–E3 y correcciones H-01, H-02, H2-R1 y H2-R2 de la auditoría de Codex — PROPUESTA TÉCNICA NO APROBADA; candidata a revisión independiente y aprobación humana)

> **Alcance estricto.** Aplica únicamente a las seis RPC de ADR-007 (`abrir_jornada`, `reasignar_vendedor`, `corregir_jornada`, `registrar_carga`, `registrar_descarga`, `confirmar_salida`), a `public.jornadas`, a sus dos historiales, a la extensión mínima de `operaciones` y `movimientos_stock`, a la lectura acotada de perfiles de la propia empresa (18.4.2.1) y al arnés de concurrencia (18.4.11). No resuelve P8–P10 ni P12–P17 globalmente, **no resuelve P8/F3**, **no modifica P11** (§18.2: `service_role` denegado, sin excepción nueva), no cambia el estado de esta ADR (APROBADA PARA VALIDACIÓN CONTROLADA) y no autoriza producción. Las reglas de negocio están en ADR-007, que prevalece ante conflicto. `propietario_rpc` sigue sin `UPDATE` ni `DELETE` sobre `operaciones` y `movimientos_stock`, y sin ningún privilegio ni política de escritura sobre `perfiles`. No resuelve el corte de jornada (Blueprint §15, «Fechas»), que sigue pendiente.

**Cambios respecto de v0.3** (sólo los observados en el laboratorio de 18.4.12):

| # | Cambio | Sección |
|---|---|---|
| 1 | `GRANT CREATE` temporal sobre `privado` para `lector_perfiles_rpc` al transferirle la vista, con `REVOKE` inmediato y verificación fail-closed | 18.4.2.1 |
| 2 | Membresía de `lector_perfiles_rpc` según el patrón real O-3: fila ADMIN automática, sin SET ni INHERIT, más fila SET sin INHERIT; tests equivalentes a los de `propietario_rpc` | 18.4.2.1, 18.4.9 |
| 3 | Vendedor inactivo unificado como `PT400 jornada_vendedor_invalido` | 18.4.3, 18.4.7, 18.4.9 |
| 4 | Rechazos de `anon` y `service_role` verificados sólo por SQLSTATE `42501`, sin depender del texto | 18.4.9 |
| 5 | El arnés de concurrencia pasa a ser requisito, en `supabase/tests/concurrencia/` | 18.4.11 |
| 6 | Límites del laboratorio explícitos | 18.4.12 |

Sin cambios: las seis RPC, I-CAMION, D6/D8, el contrato funcional de idempotencia y el inventario de tests de v0.3. La estrategia de bloqueos cambia **únicamente** en `corregir_jornada` (H-01).

> **Estado: PROPUESTA TÉCNICA NO APROBADA.** Este anexo no está aprobado, no autoriza SQL, migraciones, RPC, RLS, roles, grants ni producción, y no cambia el estado de ADR-001 ni modifica ADR-007. D-1, D-2, el arnés, su ejecución en CI y la security review siguen **pendientes de autorización humana** (18.4.13). Texto base: §18.4 v0.4 original (SHA-256 `85260b1a275b8483f28aa3d8056880e185c592215a478d8358a90678ca1a7039`), con la fe de erratas y las correcciones H-01, H-02, H2-R1 y H2-R2 siguientes. **H-01 cambia el conjunto de bloqueos de `corregir_jornada`** y **H2-R1 agrega una segunda consulta de la clave idempotente (paso 8a) sin agregar bloqueos**; E2, E3, H-02 y H2-R2 no cambian decisiones de diseño. Ninguna corrección modifica el contrato funcional de idempotencia: misma clave, tipo y huella devuelve la respuesta original; otro tipo u otra huella es conflicto.

**Fe de erratas y correcciones sobre v0.4** (candidata; detalle en `docs/progress-log.md`):

| # | Corrección | Sección |
|---|---|---|
| E1 / H-01 | ADR-007 §5 exige el bloqueo del vendedor y de los dos camiones en una corrección. `corregir_jornada` toma **siempre** el advisory del vendedor vigente (nivel 2), además de los dos camiones (nivel 1) y la jornada (nivel 3). Reemplaza la «equivalencia» de la primera candidata, que sólo bloqueaba al vendedor cuando cambiaba la fecha. Se documentan los bloqueos por RPC y el caso I-3c; K6, K7 y K9 se amplían y se agrega K12 | 18.4.3, 18.4.5, 18.4.9, 18.4.12 |
| E2 | Se elimina la referencia a «auxiliares de error de jornadas», que el contrato no define; se declara que no hay funciones auxiliares fuera del inventario | 18.4.6, 18.4.10 |
| E3 | Se agregan K10 (aperturas concurrentes) y K11 (salida contra cambios de carga neta), con resultados esperados e invariantes | 18.4.9, 18.4.11 |
| H2-R1 | Segunda consulta de la clave idempotente (paso 8a) después de los bloqueos y antes de la reverificación (8b): una solicitud repetida y concurrente recibe la respuesta original y no `jornada_estado_invalido`. I10, I11 y K9 se alinean | 18.4.3, 18.4.5, 18.4.9 |
| A-01 / A-02 / A-03 | Auditoría de Codex sobre `e17d8b9f`: A-01 identidad del texto (receta única de extracción, en `docs/progress-log.md`; no cambia el texto); A-02 mecanismo de cola del arnés para I10 e I11 por RPC, con evidencia de espera y evaluación de deadlock; A-03 I13 se separa en I13 (parámetros inválidos con clave válida) e I14 (clave nula) | 18.4.9, 18.4.11 |
| H2-R2b | Tabla de `uuid` obligatorios por RPC en 18.4.3 (nulo frente a inexistente o de otra empresa), caso I13 (el rechazo estructural no reserva la clave) y **decisión D-N1** (camión nulo y jornada nula → `PT404` existentes, opción A) resuelta, sin códigos nuevos | 18.4.3, 18.4.9, 18.4.13 |
| H2-R2 | I5 sólo se ejecuta donde existe un parámetro estructural validable; tabla de aplicabilidad por RPC (`confirmar_salida`, no aplicable). El paso 3 precisa que el vendedor nulo en `abrir_jornada` y `reasignar_vendedor` se rechaza ahí con `jornada_vendedor_invalido`, código ya definido en 18.4.7 | 18.4.3, 18.4.7, 18.4.9 |
| H-02 | Matriz normativa de idempotencia para las seis RPC (grupo I): primera ejecución, replay idéntico, replay tras cambio de estado, autorización perdida, estructura inválida, conflicto por payload y por tipo, aislamiento por actor, rechazo sin reserva de clave, concurrencia y canonicalización. No modifica el contrato funcional de 18.4.3 y 18.4.4 | 18.4.4, 18.4.9, 18.4.11 |

#### 18.4.1 Modelo mínimo

**Nulabilidad.** Toda columna de `jornadas` y de los dos historiales es `NOT NULL` explícito. Las FK compuestas son `MATCH SIMPLE`: una columna nula desactivaría la verificación, y `NOT NULL` lo impide. Sólo admiten NULL `operaciones.jornada_id` y `movimientos_stock.jornada_id`, y su presencia por tipo la fija el `CHECK` `jornada_por_tipo`.

| Objeto | Contenido |
|---|---|
| `public.operaciones` (extensión) | Columna `jornada_id uuid` nullable, FK `(empresa_id, jornada_id) → jornadas (empresa_id, id)`. `operaciones_tipo_valido` ampliado con `apertura_jornada`, `reasignacion_vendedor`, `correccion_jornada`, `carga`, `descarga`, `salida_jornada`. **CHECK `operaciones_jornada_por_tipo`:** `(tipo in ('ingreso','a_cuarentena','merma','apertura_jornada') and jornada_id is null) or (tipo in ('reasignacion_vendedor','correccion_jornada','carga','descarga','salida_jornada') and jornada_id is not null)`. **UNIQUE `operaciones_referencia_apertura (empresa_id, id, tipo, actor_id)`** y **UNIQUE `operaciones_referencia_unica (empresa_id, id, tipo, actor_id, jornada_id)`**, destinos de las FK de 18.4.8. `empresa_id`, `id`, `tipo` y `actor_id` ya son `NOT NULL`. |
| `public.movimientos_stock` (extensión) | Columna `jornada_id uuid` nullable, FK `(empresa_id, jornada_id) → jornadas (empresa_id, id)`. `movimientos_stock_tipo_valido` ampliado con `carga` y `descarga`. `forma_por_tipo`: `carga` y `descarga` con origen y destino no nulos. `motivo_por_tipo`: `carga` con `motivo_codigo` y `motivo` nulos; `descarga` con `motivo_codigo` nulo y `motivo` no nulo. **CHECK `movimientos_stock_jornada_por_tipo`:** `(tipo_movimiento in ('ingreso','a_cuarentena','merma') and jornada_id is null) or (tipo_movimiento in ('carga','descarga') and jornada_id is not null)`. **FK `movimientos_stock_operacion_referencia_fk (empresa_id, operacion_id, tipo_movimiento, actor_id, jornada_id) → operaciones_referencia_unica`**. Para `carga` y `descarga` todas sus columnas son no nulas (`NOT NULL` existente + `CHECK`), así que la FK se evalúa siempre; para los tipos de Stock no se evalúa y siguen cubiertos por D8. Índice único parcial `(empresa_id, operacion_id, producto_id) WHERE tipo_movimiento in ('carga','descarga')`. Índice `(empresa_id, jornada_id) WHERE jornada_id is not null`. D7 sin cambios. Las definiciones de `ingreso`, `a_cuarentena` y `merma` se conservan textualmente. |
| `public.jornadas` | Todas `NOT NULL`: `id uuid` (PK, default `gen_random_uuid()`), `empresa_id uuid`, `fecha date`, `camion_id uuid`, `vendedor_id uuid`, `estado text`, `abierta_por uuid`, `operacion_apertura_id uuid`, `tipo_operacion_apertura text default 'apertura_jornada' check (tipo_operacion_apertura = 'apertura_jornada')`, `creado_en timestamptz default now()`. FK `(empresa_id, camion_id) → camiones (empresa_id, id)`; `(empresa_id, vendedor_id) → perfiles (empresa_id, usuario_id)`; `(empresa_id, abierta_por) → perfiles (empresa_id, usuario_id)`; **`(empresa_id, operacion_apertura_id, tipo_operacion_apertura, abierta_por) → operaciones_referencia_apertura`**. `CHECK estado in` (los seis estados de §7.5). `UNIQUE (empresa_id, camion_id, fecha)`, `UNIQUE (empresa_id, vendedor_id, fecha)`, `UNIQUE (operacion_apertura_id)`, `UNIQUE (empresa_id, id)`. RLS habilitada, sin `FORCE`. |
| historial de reasignaciones | Todas `NOT NULL`: `id uuid` (PK, default), `empresa_id uuid`, `jornada_id uuid`, `operacion_id uuid`, `tipo_operacion text default 'reasignacion_vendedor' check (tipo_operacion = 'reasignacion_vendedor')`, `vendedor_anterior_id uuid`, `vendedor_nuevo_id uuid`, `actor_id uuid`, `creado_en timestamptz default now()`. FK `(empresa_id, jornada_id) → jornadas (empresa_id, id)`; `(empresa_id, vendedor_anterior_id)`, `(empresa_id, vendedor_nuevo_id)` y `(empresa_id, actor_id) → perfiles (empresa_id, usuario_id)`; **`(empresa_id, operacion_id, tipo_operacion, actor_id, jornada_id) → operaciones_referencia_unica`**. `CHECK (vendedor_anterior_id <> vendedor_nuevo_id)`. `UNIQUE (empresa_id, operacion_id)`. RLS habilitada, sin `FORCE`. Append-only. |
| historial de correcciones | Todas `NOT NULL`: `id uuid` (PK, default), `empresa_id uuid`, `jornada_id uuid`, `operacion_id uuid`, `tipo_operacion text default 'correccion_jornada' check (tipo_operacion = 'correccion_jornada')`, `fecha_anterior date`, `fecha_nueva date`, `camion_anterior_id uuid`, `camion_nuevo_id uuid`, `motivo text`, `actor_id uuid`, `creado_en timestamptz default now()`. FK a `jornadas`; `(empresa_id, camion_anterior_id)` y `(empresa_id, camion_nuevo_id) → camiones (empresa_id, id)`; `(empresa_id, actor_id) → perfiles`; **FK de referencia de 5 columnas** a `operaciones_referencia_unica`. `CHECK (fecha_anterior <> fecha_nueva or camion_anterior_id <> camion_nuevo_id)`; `CHECK (motivo = btrim(motivo) and length(motivo) > 0)`. `UNIQUE (empresa_id, operacion_id)`. RLS habilitada, sin `FORCE`. Append-only. |

#### 18.4.2 P10-jornadas — catálogo, permisos, grants y RLS

**Topología D.**
- Fachada `public.<rpc>`: `SECURITY INVOKER`, `search_path = ''`, owner `postgres`, sólo delega.
- Implementación `privado.<rpc>`: `SECURITY DEFINER`, `search_path = ''`, owner `propietario_rpc`.
- `EXECUTE` sólo para `authenticated` sobre ambas, con firma exacta; revocado a `PUBLIC`, `anon` y `service_role`.
- Propiedad transferida con el `GRANT CREATE` temporal sobre `privado` (patrón O-3 de Stock) y verificación fail-closed al final de la migración.
- Sin sobrecargas.

| RPC (firma exacta) | Respuesta (también en replay) | Roles | Estado |
|---|---|---|---|
| `abrir_jornada(uuid, uuid, date, uuid)` — clave, camión, fecha, vendedor | `uuid` jornada | `dueno`, `encargado` | — |
| `reasignar_vendedor(uuid, uuid, uuid)` — clave, jornada, vendedor | `uuid` operación | `dueno`, `encargado` | `abierta`, `cargada` |
| `corregir_jornada(uuid, uuid, date, uuid, text)` — clave, jornada, fecha final, camión final, motivo | `uuid` operación | `dueno`, `encargado` | `abierta` sin movimientos |
| `registrar_carga(uuid, uuid, uuid[], integer[])` | `uuid` operación | `dueno`, `encargado` | `abierta`, `cargada` |
| `registrar_descarga(uuid, uuid, uuid[], integer[], text)` | `uuid` operación | `dueno`, `encargado` | `cargada` |
| `confirmar_salida(uuid, uuid)` | `uuid` operación | `dueno`, `encargado` | `cargada`, carga neta > 0 |

**Grants.** En ninguno de estos objetos reciben privilegios `service_role` ni `anon`; `authenticated` no recibe DML.

| Objeto | `authenticated` | `propietario_rpc` | `lector_perfiles_rpc` |
|---|---|---|---|
| `jornadas` | `SELECT` | `SELECT`; `INSERT (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)`; `UPDATE (estado, vendedor_id, fecha, camion_id)`. Sin `DELETE`. | — |
| Historiales | `SELECT` | `INSERT` por columna (todas salvo `id`, `tipo_operacion` y `creado_en`). Sin `SELECT`. | — |
| `operaciones` | sin cambios | se agrega `INSERT (jornada_id)` | — |
| `movimientos_stock` | sin cambios | se agrega `INSERT (jornada_id)` | — |
| `perfiles` | sin cambios | **sin cambios** (sólo `SELECT`; sus políticas no cambian) | `SELECT (usuario_id, empresa_id, rol, activo)` |
| `privado.perfiles_empresa_gestion` (vista) | — | `SELECT` | owner |
| `privado.empresa_gestion_actual()` | — | `EXECUTE` | — |
| esquema `privado` | `USAGE` (sin cambios) | `USAGE` (sin cambios) | **ninguno** en el estado final; `CREATE` sólo transitorio durante la migración (18.4.2.1) |

**Políticas.**
- `jornadas`:
  - `SELECT TO authenticated`: dueño o encargado activo de la empresa, o perfil activo con `vendedor_id = auth.uid()`.
  - `SELECT TO propietario_rpc`: llamador (`privado.usuario_actual()`) activo, de la misma empresa, con rol `dueno` o `encargado`.
  - `INSERT` y `UPDATE TO propietario_rpc`: misma condición en `USING` y `WITH CHECK`; `INSERT` exige además `abierta_por = privado.usuario_actual()`.
  - Sin política de `DELETE`.
- Historiales:
  - `SELECT TO authenticated`: dueño o encargado activo de la empresa.
  - `INSERT TO propietario_rpc`: llamador dueño o encargado activo de la empresa, `actor_id = privado.usuario_actual()` y jornada existente de la misma empresa.
- `operaciones` (`operaciones_insert_propietario_rpc` ampliada):
  - tipos de Stock y `apertura_jornada` ⇒ `jornada_id is null`;
  - los otros cinco ⇒ existe una jornada con ese id y la misma empresa.
- `movimientos_stock` (`movimientos_stock_insert_propietario_rpc` ampliada), para `carga` y `descarga` exige:
  - `o.tipo = tipo_movimiento` y `o.jornada_id = movimientos_stock.jornada_id`;
  - origen el depósito propio y destino la ubicación `camion` del `camion_id` de la jornada (`descarga`, al revés);
  - misma empresa en todo.
- `perfiles`: **las políticas de `authenticated` y de `propietario_rpc` no cambian.** Se agrega sólo `perfiles_select_empresa_lector` (18.4.2.1), `FOR SELECT TO lector_perfiles_rpc`.
- `operaciones`, `movimientos_stock` y `stock_actual` para `authenticated`: sin cambios (P10-stock).

##### 18.4.2.1 Lectura de perfiles de la propia empresa, sin recursión

**Problema.** Para validar el vendedor (`abrir_jornada`, `reasignar_vendedor`), `propietario_rpc` tiene que leer un perfil que no es el del llamador. Una política sobre `perfiles` cuyo `USING` consulte `perfiles` es recursiva: PostgreSQL la rechaza (`42P17`). Pasarla a un helper `SECURITY DEFINER` de `propietario_rpc` dentro de su propia política tampoco sirve: la recursión aparece en ejecución (`54001`). Las dos cosas se observaron en el laboratorio (18.4.12).

**Diseño en dos capas.**

| Pieza | Especificación |
|---|---|
| **Rol `lector_perfiles_rpc`** | `NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS`. No es miembro de ningún rol. Su único miembro es `postgres`, con las dos filas del patrón O-3 (ver «Membresía»). No es propietario de tablas ni de funciones. Su único privilegio es `SELECT (usuario_id, empresa_id, rol, activo)` sobre `public.perfiles`. En el estado final no tiene `USAGE` ni `CREATE` en ningún esquema: no los necesita para resolver la vista ni la política. Se crea en la misma migración que su único objeto (P2–P4: sin objetos anticipados). |
| **Capa 1: helper `privado.empresa_gestion_actual() returns uuid`** | `LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''`, owner `propietario_rpc`. Cuerpo: `select p.empresa_id from public.perfiles p where p.usuario_id = privado.usuario_actual() and p.activo and p.rol in ('dueno','encargado')`. Devuelve NULL si el llamador no es dueño o encargado activo. `REVOKE ALL` de `PUBLIC`, `anon`, `authenticated` y `service_role`; `GRANT EXECUTE` sólo a `propietario_rpc`. Corre como `propietario_rpc` y sólo lo alcanza la política vigente `perfiles_select_propio_propietario_rpc`, que no llama a ninguna función. Por ser `SECURITY DEFINER` y tener `proconfig`, no se inlinea. Sin parámetros: no deriva empresa ni rol del JWT, sólo de `perfiles` (P5–P7). |
| **Capa 2: vista `privado.perfiles_empresa_gestion`** | `WITH (security_invoker = false, security_barrier = true) AS select usuario_id, empresa_id, rol, activo from public.perfiles`. Owner `lector_perfiles_rpc`, así que la RLS de `perfiles` se le aplica a ese rol. `REVOKE ALL` de `PUBLIC`, `anon`, `authenticated` y `service_role`; `GRANT SELECT` sólo a `propietario_rpc`. Vive en `privado`, que no está expuesto. |
| **Política `perfiles_select_empresa_lector`** | `ON public.perfiles FOR SELECT TO lector_perfiles_rpc USING (empresa_id = (select privado.empresa_gestion_actual()))`. Llamador no gestor, inactivo, sin perfil o sin `sub` ⇒ 0 filas. Sólo perfiles de la empresa del llamador. |

**Por qué no hay recursión.**
- Al leer la vista se aplica la política de `lector_perfiles_rpc`, que llama a la capa 1.
- La capa 1 lee `perfiles` como `propietario_rpc`, y a ese rol sólo se le aplica la política propia, que no llama a ninguna función.
- `propietario_rpc` no es miembro de `lector_perfiles_rpc`, así que la política de la capa 2 no se le aplica. La profundidad queda en 1.

**Privilegio `EXECUTE`.** PostgreSQL verifica el `EXECUTE` de una función llamada desde una política contra el usuario que ejecuta la consulta (`propietario_rpc`), no contra el dueño de la vista (18.4.12). Por eso `lector_perfiles_rpc` no recibe `EXECUTE`. Si alguna vez se lee `perfiles` como `lector_perfiles_rpc`, la consulta falla cerrada con `42501` y no entra en recursión.

**Membresía (patrón O-3 real).** `CREATE ROLE`, ejecutado por `postgres` (que tiene `CREATEROLE`), genera automáticamente una fila con grantor el superusuario de arranque del clúster (`supabase_admin` en Supabase), con `admin_option = true`, `inherit_option = false` y `set_option = false`. La migración agrega `GRANT lector_perfiles_rpc TO postgres WITH INHERIT FALSE, SET TRUE`. Estado exigido:
- exactamente esas dos filas en `pg_auth_members` para `roleid = lector_perfiles_rpc`, ambas con `member = postgres`;
- ninguna fila con `inherit_option = true`;
- `lector_perfiles_rpc` no es miembro de ningún rol;
- `pg_has_role('postgres', 'lector_perfiles_rpc', 'SET') = true` y `pg_has_role('postgres', 'lector_perfiles_rpc', 'USAGE') = false`;
- `anon`, `authenticated`, `authenticator`, `service_role` y `propietario_rpc` no pueden hacer SET ni heredarlo.

No se introduce `INHERIT` ni ningún permiso para roles de la Data API.

**Procedimiento de migración (orden obligatorio).**
1. `CREATE ROLE lector_perfiles_rpc NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS` (si ya existe por ser global del clúster, se verifican sus atributos y se falla si difieren, como con `propietario_rpc`).
2. `GRANT lector_perfiles_rpc TO postgres WITH INHERIT FALSE, SET TRUE`.
3. `GRANT SELECT (usuario_id, empresa_id, rol, activo) ON public.perfiles TO lector_perfiles_rpc`.
4. Helper (patrón O-3): `CREATE FUNCTION` → `GRANT CREATE ON SCHEMA privado TO propietario_rpc` → `ALTER FUNCTION … OWNER TO propietario_rpc` → `REVOKE CREATE ON SCHEMA privado FROM propietario_rpc` → `SET ROLE propietario_rpc` → `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role` → `GRANT EXECUTE … TO propietario_rpc` → `RESET ROLE`.
5. Vista: `CREATE VIEW` → `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role` → `GRANT SELECT … TO propietario_rpc` → **`GRANT CREATE ON SCHEMA privado TO lector_perfiles_rpc`** → `ALTER VIEW … OWNER TO lector_perfiles_rpc` → **`REVOKE CREATE ON SCHEMA privado FROM lector_perfiles_rpc`**. Sin el `CREATE` temporal, el `ALTER … OWNER` falla con `42501` (18.4.12).
6. `CREATE POLICY perfiles_select_empresa_lector`.
7. **Verificación fail-closed** dentro de la misma migración, que aborta si no se cumple alguno de estos puntos:
   - ni `lector_perfiles_rpc` ni `propietario_rpc` tienen `CREATE` sobre `privado` ni sobre `public`, y `lector_perfiles_rpc` no tiene `USAGE` sobre `privado`;
   - el owner de la vista y sus `reloptions` son los indicados, y su ACL es exacta (owner + `SELECT` de `propietario_rpc`);
   - los atributos y la ACL del helper son exactos;
   - el estado de membresía es exactamente el descrito;
   - `lector_perfiles_rpc` no es dueño de ninguna función ni tabla, y es dueño de una sola relación;
   - las políticas de `perfiles` para `authenticated` y `propietario_rpc` no cambiaron.

**Compatibilidad con ADR-001.**
- P2: nada nuevo en `public`.
- P3: toda función de `privado` sigue siendo de `propietario_rpc`; `lector_perfiles_rpc` sólo es dueño de una vista.
- P4: RLS sin `BYPASSRLS` ni `FORCE`; las tablas siguen siendo del owner de migraciones.
- P11: `service_role` sin acceso.
- O-3: las membresías son SET sin INHERIT, y el `CREATE` se da sólo de forma transitoria.
- Sin funciones privilegiadas en `public`.

**Alternativas descartadas.**

| Alternativa | Motivo |
|---|---|
| Subconsulta en la política | `42P17` |
| Helper de `propietario_rpc` en su propia política | `54001` |
| Helper o vista propiedad de `postgres` | Saltea la RLS como owner de la tabla; contradice P3/P4 y `hardening_adr001.test.sql:205-210` |
| `USING (true)` | Permite lectura entre empresas |
| GUC de sesión | Lo puede fijar la propia sesión |
| FK con `activo` | Bloquea la baja posterior que ADR-007 §2.3 admite |

#### 18.4.3 Orden de ejecución de cada implementación

1. Aislamiento `READ COMMITTED`; si no, `PT500 jornada_error_interno`.
2. Identidad y rol: `privado.usuario_actual()` no nulo (si no, `PT401`); perfil propio activo con rol `dueno` o `encargado` (si no, `PT403`).
3. Estructura, sin leer estado mutable: clave, fecha, motivo, arreglos (no nulos, mismo largo, 1 elemento o más, sin nulos ni productos repetidos) y cantidades > 0; y el vendedor en `abrir_jornada` y `reasignar_vendedor` (vendedor destino), que no puede ser nulo: nulo → `PT400 jornada_vendedor_invalido`, el código que 18.4.7 ya define para «vendedor nulo»; y, por la decisión D-N1 (opción A), el camión (en `abrir_jornada`, y el camión final en `corregir_jornada`) y la jornada (en las otras cinco RPC), que no pueden ser nulos: camión nulo → `PT404 jornada_camion_no_encontrado`; jornada nula → `PT404 jornada_no_encontrada`, los códigos que 18.4.7 ya define. Todo esto se evalúa en este paso, antes de la huella (paso 4), de cualquier consulta de replay (pasos 5 y 8a) y de la reserva de la clave (paso 9). Que el vendedor, el camión o la jornada existan, sean de la empresa o estén activos depende de estado mutable y se resuelve en el paso 6 o en el 10; esos casos conservan el mismo `PT404`.
4. Huella (18.4.4).
5. **Replay previo, sin bloqueos:** `SELECT tipo, huella, … FROM operaciones WHERE (empresa_id, actor_id, idempotency_key) = …`. Esta lectura no toma bloqueos de FK.
   - Mismo tipo y misma huella → se devuelve la respuesta guardada (la jornada por `jornadas.operacion_apertura_id`, o el id de la operación), sin revalidar estado.
   - Otro tipo u otra huella → `PT409 jornada_conflicto_idempotencia`.
6. Lectura sin bloqueo de la jornada (salvo en `abrir_jornada`) para obtener las claves de los advisory: `camion_id`, `vendedor_id` (vigente) y `fecha`. Inexistente o de otra empresa → `PT404`.
7. Advisory locks de los niveles 1 y 2 (18.4.5), con el conjunto calculado en el paso 6 y los parámetros.
8. `SELECT … FROM jornadas WHERE id = … FOR UPDATE` (salvo en `abrir_jornada`, que no tiene fila previa). Con los bloqueos de los pasos 7 y 8 en poder de la transacción, en este orden:
   - **8a. Segunda consulta de la clave idempotente (H2-R1).** Sentencia nueva (en `READ COMMITTED` ve lo confirmado mientras esperaba los bloqueos), **antes** de la reverificación y de cualquier rechazo por valores desactualizados. Misma lectura que el paso 5: `SELECT tipo, huella, … FROM operaciones WHERE (empresa_id, actor_id, idempotency_key) = …`. Es una lectura sin bloqueos de fila ni de FK. Se aplica a las seis RPC; en `abrir_jornada` va inmediatamente después del paso 7.
     - Mismo tipo y misma huella → se devuelve **exactamente** la respuesta original (la del paso 5), sin revalidar estado y sin efectos nuevos.
     - Otro tipo u otra huella → `PT409 jornada_conflicto_idempotencia`.
     - La clave no existe → se continúa con 8b.
     - Por qué: dos solicitudes con la misma clave pueden leer el paso 6 antes de que la primera confirme; al obtener los bloqueos, los valores que leyó la segunda pueden haber sido cambiados por la propia operación de la primera (por ejemplo, el vendedor vigente tras `reasignar_vendedor`). Sin 8a, la reverificación respondería `PT409 jornada_estado_invalido` a un replay legítimo.
     - La autenticación, la empresa, el rol (paso 2) y la estructura (paso 3) se validan **antes** de cualquier replay, en el paso 5 y en 8a.
   - **8b. Reverificación** de los valores usados como clave:
     - `camion_id` (en `corregir_jornada`) y `vendedor_id` vigente (en `reasignar_vendedor` y en `corregir_jornada`, siempre), iguales a los del paso 6. Si cambiaron → `PT409 jornada_estado_invalido`, sin efectos y reintentable con la misma clave. No se toman bloqueos adicionales fuera de orden.
     - `estado` y `fecha` se releen en este paso; todas las validaciones siguientes usan los valores leídos bajo `FOR UPDATE`. La clave de nivel 2 no incluye la fecha, así que un cambio de fecha no invalida los bloqueos tomados.
9. **Reserva:** `INSERT INTO operaciones (…, jornada_id) … ON CONFLICT (empresa_id, actor_id, idempotency_key) DO NOTHING`.
   - Si no inserta porque otra transacción con la misma clave confirmó entre los pasos 8a y 9 → relectura y la misma regla del paso 5. Sólo es posible cuando esa transacción no comparte los bloqueos de los niveles 1 a 3 (por ejemplo, la misma clave sobre otra jornada); la UNIQUE y este `ON CONFLICT` siguen siendo el árbitro final.
   - El `FOR KEY SHARE` que la FK toma sobre la jornada es compatible con el `FOR UPDATE` propio.
10. Validaciones de negocio de ADR-007 sobre datos leídos después de los pasos 7 y 8. El vendedor (nuevo o de apertura) se lee en `privado.perfiles_empresa_gestion` bajo su advisory de nivel 2:
    - no visible (inexistente o de otra empresa) → `PT404 jornada_vendedor_no_encontrado`;
    - visible e inactivo → **`PT400 jornada_vendedor_invalido`**.

    Día operativo: `(now() at time zone 'America/Argentina/Tucuman')::date`.
11. Advisory locks de stock (nivel 4) y lectura de saldos del ledger.
12. Escrituras: jornada, historial, movimientos y `UPDATE` de `jornadas`. Una violación residual de restricción → `PT500 jornada_error_interno`, sin nombre de restricción.

**Parámetros `uuid` obligatorios y estructura (paso 3).** Un `uuid` **nulo** no es un `uuid` válido inexistente o de otra empresa: el nulo es un defecto de estructura y se rechaza en el paso 3, antes de la huella (paso 4), de cualquier replay (pasos 5 y 8a) y de la reserva (paso 9); el inexistente o de otra empresa depende de datos y se rechaza después (paso 6 o 10). Para el camión y la jornada, ambos casos usan el mismo `PT404` (D-N1, opción A); para el vendedor, el nulo es `PT400` y el inexistente o de otra empresa, `PT404`.

| RPC | `uuid` obligatorios | Si es nulo (paso 3) | Si es válido pero inexistente o de otra empresa |
|---|---|---|---|
| `abrir_jornada` | clave; camión; vendedor | clave → `PT400 jornada_clave_invalida`; vendedor → `PT400 jornada_vendedor_invalido`; camión → `PT404 jornada_camion_no_encontrado` | camión → `PT404 jornada_camion_no_encontrado`; vendedor → `PT404 jornada_vendedor_no_encontrado` (paso 10) |
| `reasignar_vendedor` | clave; jornada; vendedor | clave y vendedor, como arriba; jornada → `PT404 jornada_no_encontrada` | jornada → `PT404 jornada_no_encontrada` (paso 6); vendedor → `PT404 jornada_vendedor_no_encontrado` (paso 10) |
| `corregir_jornada` | clave; jornada; camión final | clave, como arriba; jornada → `PT404 jornada_no_encontrada`; camión final → `PT404 jornada_camion_no_encontrado` | jornada → `PT404 jornada_no_encontrada` (paso 6); camión → `PT404 jornada_camion_no_encontrado` |
| `registrar_carga` | clave; jornada; productos (arreglo) | clave, como arriba; elemento nulo del arreglo → `PT400 jornada_lineas_invalidas`; jornada → `PT404 jornada_no_encontrada` | jornada → `PT404 jornada_no_encontrada` (paso 6); producto → `PT404 jornada_producto_no_encontrado` |
| `registrar_descarga` | clave; jornada; productos (arreglo) | igual que `registrar_carga` | igual que `registrar_carga` |
| `confirmar_salida` | clave; jornada | clave, como arriba; jornada → `PT404 jornada_no_encontrada` | jornada → `PT404 jornada_no_encontrada` (paso 6) |

- **Sin código nuevo:** el catálogo de 18.4.7 alcanza para todos los casos. La clave, el vendedor y los elementos nulos del arreglo de productos usan `PT400`; el camión y la jornada nulos usan los `PT404` ya definidos (D-N1, resuelta por el humano para jornadas; no extiende esta regla a Stock).
- **Sin reserva de clave:** los rechazos de los pasos 1 a 8a ocurren antes de la reserva del paso 9, así que un rechazo estructural no deja fila en `operaciones` ni consume `idempotency_key`.

Un rechazo en los pasos 8b a 12 revierte la transacción completa, incluida la reserva del paso 9. Una respuesta de replay (paso 5 u 8a) no escribe nada.

#### 18.4.4 P12/P15-jornadas — idempotencia y huella

- Unicidad de Stock: `UNIQUE (empresa_id, actor_id, idempotency_key)`. La clave vive sólo en `operaciones` (P15) y se retiene indefinidamente. Es compartida con Stock: una clave ya usada en otro tipo, incluido uno de Stock, → `PT409 jornada_conflicto_idempotencia`.
- Huella `v1` = `encode(sha256(convert_to(<texto>, 'UTF8')), 'hex')`. Las fechas se escriben con `to_char(fecha, 'YYYY-MM-DD')`, los uuid en texto canónico, y `<m>` = `+` más el motivo con `btrim`.
- Las pruebas obligatorias de idempotencia de las seis RPC están en 18.4.9, grupo I. Esa matriz no modifica este contrato.

| Tipo | Texto |
|---|---|
| `apertura_jornada` | `v1\|apertura_jornada\|<camion>\|<fecha>\|<vendedor>` |
| `reasignacion_vendedor` | `v1\|reasignacion_vendedor\|<jornada>\|<vendedor>` |
| `correccion_jornada` | `v1\|correccion_jornada\|<jornada>\|<fecha>\|<camion>\|<m>` |
| `carga` | `v1\|carga\|<jornada>\|<producto>:<cantidad>,…`, con las líneas ordenadas por el texto del uuid del producto |
| `descarga` | `v1\|descarga\|<jornada>\|<líneas ordenadas>\|<m>` |
| `salida_jornada` | `v1\|salida_jornada\|<jornada>` |

#### 18.4.5 P13-jornadas — aislamiento, orden global e invariante

`READ COMMITTED`. Advisory locks con `pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(<clave>, 0))`.

**Orden global.** Cada RPC toma un subconjunto, siempre en orden ascendente de (nivel, uuid), sin repetir claves. Ninguna transacción toma un bloqueo de rango menor después de uno de rango mayor. Si después del bloqueo el conjunto correcto es otro, aborta con `PT409` (18.4.3, paso 8b, después de la segunda consulta de la clave, 8a) en lugar de completarlo fuera de orden.

| Nivel | Bloqueo | Clave o sentencia | RPC |
|---|---|---|---|
| 1 | Camión | `'jornadas:camion:' \|\| empresa \|\| ':' \|\| camion`, en orden de uuid | `abrir_jornada`; `corregir_jornada` (actual y final, sin duplicar) |
| 2 | Vendedor | `'jornadas:vendedor:' \|\| empresa \|\| ':' \|\| perfil`, en orden de uuid | `abrir_jornada` (el vendedor); `reasignar_vendedor` (vigente y nuevo; uno solo si coinciden); `corregir_jornada` (el vigente, **siempre**, cambie el camión, la fecha o ambos) |
| 3 | Jornada | `SELECT … FROM jornadas … FOR UPDATE` | todas salvo `abrir_jornada` |
| 4 | Stock | `'stock:' \|\| empresa \|\| ':' \|\| ubicacion \|\| ':' \|\| producto`, en orden de `(ubicacion, producto)` | `registrar_carga` (depósito); `registrar_descarga` (ubicación del camión) |

**Bloqueos que adquiere cada RPC** (siempre en este orden; `—` = no toma ninguno de ese nivel):

| RPC | Nivel 1: camión | Nivel 2: vendedor | Nivel 3: jornada | Nivel 4: stock |
|---|---|---|---|---|
| `abrir_jornada` | el del pedido | el del pedido | — (la fila aún no existe) | — |
| `reasignar_vendedor` | — | vigente y nuevo (uno si coinciden) | `FOR UPDATE` | — |
| `corregir_jornada` | actual y final (uno si coinciden) | el vigente | `FOR UPDATE` | — |
| `registrar_carga` | — | — | `FOR UPDATE` | depósito × producto, por `(ubicación, producto)` |
| `registrar_descarga` | — | — | `FOR UPDATE` | ubicación del camión × producto, por `(ubicación, producto)` |
| `confirmar_salida` | — | — | `FOR UPDATE` | — |

**Segunda consulta de la clave (paso 8a) y bloqueos (H2-R1).**
- Es una lectura MVCC de `operaciones`: no pide ningún bloqueo de fila, de FK ni advisory. No agrega esperas, no cambia el orden global y no puede formar parte de un ciclo.
- Se hace después de tener los bloqueos de los niveles 1 a 3. Una solicitud con la misma clave y los mismos bloqueos sólo la ve confirmada tras haber esperado a la primera.
- Las garantías de idempotencia no cambian: sólo se devuelve el resultado de una operación confirmada y visible, con el mismo tipo y la misma huella (si no, conflicto), y la UNIQUE y el `ON CONFLICT` del paso 9 siguen siendo el árbitro final.
- No cubre la misma clave sobre otra jornada, que no comparte bloqueos: ese caso sigue resolviéndose en el paso 9 (K8).

**Esperas fuera de los niveles.**
- **Índices únicos.** Toda transacción que escribe la clave `(empresa_id, vendedor_id, fecha)` para un vendedor V tiene el advisory de V: abre con V, reasigna hacia V o desde V, o corrige (camión, fecha o ambos) una jornada cuyo vigente es V. La clave `(empresa_id, camion_id, fecha)` la escribe quien tiene el advisory del camión, o la misma jornada en un `UPDATE` no HOT. Por eso dos transacciones no pueden esperarse por un índice único mientras compiten por la misma clave: el advisory las serializa antes.
- **FK.** Los `FOR KEY SHARE` de las FK sobre `productos`, `ubicaciones`, `perfiles` y `camiones` son compatibles con los `UPDATE` de baja, que no tocan claves (`FOR NO KEY UPDATE`).
- **Stock.** La clave de nivel 4 es la misma cadena que usan `mover_a_cuarentena` y `registrar_merma` (`20261025033454_stock_cuarentena_merma.sql:321` y `:494`). Esas RPC reservan antes de su único advisory y no bloquean filas; las jornadas reservan en el paso 9, antes del nivel 4.

**Sin bloqueos de fila sobre catálogos.** `camiones.activo`, `productos.activo` y el perfil del vendedor se leen después de los niveles 1 a 3, sin `FOR SHARE`. Una baja concurrente equivale a una baja inmediatamente posterior, y ADR-007 §2.3 y §2.7 lo admiten. El vendedor se relee bajo su advisory de nivel 2.

**Cumplimiento de ADR-007 §5 (`corregir_jornada`) — H-01.** ADR-007 §5 exige que este anexo incluya la RPC de corrección y el bloqueo del vendedor y de los dos camiones cuando una corrección cambia el camión. `corregir_jornada` los toma **siempre**, en el orden global, cualquiera sea el dato que cambie (camión, fecha o ambos). Una corrección que no cambia ninguno se rechaza en el paso 10 con `PT409 jornada_sin_cambios`, después de haber tomado los bloqueos.

| Nivel | Qué toma `corregir_jornada` | Qué serializa |
|---|---|---|
| 1 | Camión actual y camión final, en orden de uuid y sin duplicar si coinciden | Aperturas y correcciones que escriban o evalúen el par `(camión, fecha)` o «sin otra jornada sin cerrar» de cualquiera de los dos camiones (ADR-007 §2.1.4, §2.1.5 y §2.4.3) |
| 2 | Vendedor vigente de la jornada | Aperturas, reasignaciones y otras correcciones que escriban o evalúen `(vendedor, fecha)` del vigente (ADR-007 §2.3.2 y §2.4.3) |
| 3 | La jornada, `FOR UPDATE` | Cualquier otra RPC sobre la misma jornada (reasignación, carga, descarga, salida) |

- Los valores usados como clave (`camion_id` y `vendedor_id` vigente) se reverifican bajo `FOR UPDATE` (18.4.3, paso 8b, después de 8a). Si cambiaron, `PT409 jornada_estado_invalido`, sin efectos y reintentable con la misma clave.
- **Costo:** toda corrección, aunque sólo cambie el camión, se serializa con las aperturas, reasignaciones y correcciones del mismo vendedor. Es una operación excepcional (jornada `abierta` sin movimientos), así que no se busca evitarlo.
- **Evidencia:** este mecanismo **no** está cubierto por el laboratorio de 18.4.12, que lo ejecutó con el vendedor bloqueado sólo ante cambio de fecha. Se demuestra con K6, K7, K9 y K12 sobre la implementación real.

**Intercalación de CONC-18.4-01 (dos cargas de la misma J).**

| t | T1 | T2 |
|---|---|---|
| 1 | replay previo: no existe | replay previo: no existe |
| 2 | `FOR UPDATE` J: concedido | — |
| 3 | — | `FOR UPDATE` J: espera (sin bloqueos propios sobre J) |
| 4 | reserva (`KEY SHARE` propio), nivel 4, escribe y confirma | — |
| 5 | — | obtiene J actualizada, reserva y valida; confirma o rechaza |

Con la misma clave: en t5 T2 encuentra la operación de T1 en la segunda consulta (paso 8a) y devuelve la misma respuesta si la huella coincide, o `PT409 jornada_conflicto_idempotencia` si no. El `ON CONFLICT` del paso 9 queda como respaldo.

**I-1: reasignación contra reasignación (intercambio).** J1 (vendedor A, fecha f) y J2 (B, f), con A < B. T1 reasigna J1 → B y T2 reasigna J2 → A.

| t | Sin orden por UUID (vigente → nuevo) | v0.4 (orden por UUID) |
|---|---|---|
| 1 | T1 toma adv(A) | T1 toma adv(A) |
| 2 | T2 toma adv(B) | T2 pide adv(A): espera a T1 |
| 3 | T1 pide adv(B): espera a T2 | T1 toma adv(B) y `FOR UPDATE` J1; B está ocupado en f (J2) → `PT409 jornada_vendedor_ocupado`, rollback |
| 4 | T2 pide adv(A): espera a T1 → **`40P01`** | T2 toma adv(A), adv(B) y `FOR UPDATE` J2; A está ocupado (J1) → `PT409` |

Cero `40P01`. El intercambio directo se rechaza en cualquier orden serial por la unicidad vendedor-fecha. ADR-007 no define un intercambio atómico, y no se agrega acá.

**I-1b: cadena.** T1 reasigna J1 A → C y T2 reasigna J2 B → A. T2 espera adv(A) hasta que T1 confirma. Después lee J1 con C, A queda libre y T2 confirma. El resultado coincide con el orden serial T1; T2.

**I-2: apertura contra reasignación.** T1 reasigna J1 (A, f) → B y T2 abre (camión 2, f, A).
- Si T1 toma adv(A) primero, T2 (que ya tiene adv(camión 2)) espera adv(A). T1 confirma y deja a J1 con B. T2 obtiene adv(A), A está libre y abre. Equivale a T1; T2.
- Si T2 toma adv(A) primero, A está ocupado (J1) y T2 recibe `PT409`. Después T1 toma {A, B} y confirma. Equivale a T2; T1.
- Ciclos: T2 no toma el nivel 3 y T1 no toma el nivel 1. Cero `40P01`.

**I-3: corrección contra reasignación de la misma J.** T1 corrige J1 (A, f → g) y T2 reasigna J1 A → B.
- Si T1 va primero: toma adv(camión 1), adv(A) y J1. T2 espera adv(A). T1 confirma. T2 toma {A, B} y J1; el vigente sigue siendo A, la fecha releída es g y valida B en g.
- Si T2 va primero: toma {A, B} y J1. T1, que ya tiene adv(camión 1), espera adv(A). T2 confirma. T1 toma adv(A) y J1; el vigente ahora es B ≠ A → `PT409 jornada_estado_invalido`. Al reintentar, recalcula B.
- Cero `40P01`.

**I-3b: corrección de J1 contra reasignación de J2 hacia el vigente de J1.** T1 corrige J1 (A, f → g) y T2 reasigna J2 (X, g) → A. Los dos necesitan adv(A) y se serializan en el nivel 2. Cero `40P01`.

**I-3c: corrección sólo de camión contra reasignación de la misma J (H-01).** T1 corrige J1 (vendedor A, fecha f, camión C1 → C2, misma fecha) y T2 reasigna J1 A → B. Sea B mayor o menor que A: T2 toma {A, B} en orden de uuid.
- Si T1 va primero: toma adv(C1, C2), adv(A) y J1. T2 toma adv(B) si B < A y espera adv(A). T1 confirma con J1 en C2 y vendedor A. T2 completa sus bloqueos, toma J1, el vigente sigue siendo A y valida B en f. Equivale a T1; T2.
- Si T2 va primero: toma {A, B} y J1. T1, que ya tiene adv(C1, C2), espera adv(A). T2 confirma con J1 en B. T1 obtiene adv(A) y J1; el vigente ahora es B ≠ A → `PT409 jornada_estado_invalido`, sin efectos. Al reintentar con la misma clave toma adv(B) y confirma. Equivale a T2; T1.
- T1 espera por un bloqueo de nivel 2 sosteniendo uno de nivel 1; T2 nunca espera por el nivel 1 ni por los camiones, así que no hay ciclo. Esto se **deduce del orden global; no está medido**: lo mide K12.

**Invariante I-CAMION (vale para este bloque y para todo bloque futuro).**
- Toda escritura en `movimientos_stock` cuyo origen o destino sea la ubicación de un camión, y toda fila que referencie una jornada por FK, se hace dentro de una RPC que:
  - (a) tomó `FOR UPDATE` de esa jornada **antes** de cualquier `INSERT` o `UPDATE` que la referencie;
  - (b) verificó que la ubicación es la del `camion_id` vigente de esa jornada y que el estado de la jornada admite esa escritura;
  - (c) si debita la ubicación del camión, toma su advisory de nivel 4.
- Ninguna RPC escribe en la ubicación de un camión sin una jornada.
- `retorno`, `venta` y las regularizaciones no se diseñan acá. Cuando se diseñen, deben cumplir esta invariante o modificarla expresamente en su propio anexo.

#### 18.4.6 P14 — sin sobrecargas

Ninguna de las seis RPC ni `privado.empresa_gestion_actual()` tiene sobrecargas, ni en `public` ni en `privado`. El contrato no define otras funciones en `public` ni en `privado`: los errores de 18.4.7 se levantan en línea desde cada implementación, sin funciones auxiliares de error.

#### 18.4.7 P16-jornadas — errores estables

`message` = código; SQLSTATE `PTxyz`; sin nombres de restricción, saldos ni datos de otra empresa; nunca `40001` ni `40P01` para negocio. Los tests verifican el SQLSTATE y, en los errores de negocio, el código de `message`. Los rechazos de privilegio de PostgreSQL (`42501`) se verifican sólo por SQLSTATE.

| SQLSTATE | Códigos |
|---|---|
| `PT401` | `jornada_no_autenticado` |
| `PT403` | `jornada_no_autorizado` |
| `PT400` | `jornada_clave_invalida`, `jornada_fecha_invalida`, `jornada_cantidad_invalida`, `jornada_lineas_invalidas`, `jornada_producto_repetido`, `jornada_motivo_invalido`, `jornada_vendedor_invalido` (vendedor nulo, evaluado en 18.4.3, paso 3; o perfil de la empresa **inactivo**, en el paso 10) |
| `PT404` | `jornada_no_encontrada`, `jornada_camion_no_encontrado`, `jornada_vendedor_no_encontrado`, `jornada_producto_no_encontrado` (otra empresa = inexistente; un `uuid` nulo de camión o de jornada se rechaza con `jornada_camion_no_encontrado` o `jornada_no_encontrada` en 18.4.3, paso 3, por D-N1) |
| `PT409` | `jornada_duplicada`, `jornada_camion_con_jornada_abierta`, `jornada_camion_inactivo`, `jornada_vendedor_ocupado`, `jornada_estado_invalido`, `jornada_con_movimientos`, `jornada_sin_cambios`, `jornada_producto_inactivo`, `jornada_stock_residual`, `jornada_stock_insuficiente`, `jornada_descarga_excede_carga`, `jornada_carga_neta_cero`, `jornada_conflicto_idempotencia` |
| `PT500` | `jornada_error_interno`, `jornada_ubicacion_no_configurada` |

#### 18.4.8 P17-jornadas — trazabilidad y dónde se controla cada referencia

| Garantía | FK | CHECK / NOT NULL | RLS (`INSERT`/`UPDATE TO propietario_rpc`) | Validación transaccional |
|---|---|---|---|---|
| La apertura referencia una operación `apertura_jornada` de la misma empresa y del mismo actor (`abierta_por`) | ✔ compuesta de 4 columnas, con tipo constante | ✔ tipo constante; las 4 columnas `NOT NULL` | ✔ `abierta_por = usuario_actual()` | — |
| El historial referencia una operación del tipo correcto, del mismo actor, de la misma empresa y de la misma jornada | ✔ compuesta de 5 columnas | ✔ tipo constante; las 5 columnas `NOT NULL` | ✔ actor y empresa | — |
| Un movimiento `carga`/`descarga` referencia una operación del mismo tipo, actor, empresa y jornada | ✔ compuesta de 5 columnas | ✔ `jornada_por_tipo` + `NOT NULL` existentes | ✔ `o.tipo` y `o.jornada_id` | — |
| Los tipos de Stock no llevan jornada | — | ✔ `jornada_por_tipo` en ambas tablas | ✔ | — |
| El camión de la ubicación es el de la jornada | — | — | ✔ | ✔ (I-CAMION) |
| Vendedor anterior y valores anteriores de la corrección iguales a los de la jornada | — | — | — | ✔ (leídos bajo `FOR UPDATE`) |
| Vendedor activo, de la empresa y con rol admitido | ✔ existencia y empresa | — | ✔ vista acotada (18.4.2.1) | ✔ (bajo nivel 2) |
| Camión activo; fecha; stock residual; carga neta | — | — | — | ✔ |

Una FK no valida el tipo por sí misma: el tipo se garantiza con la columna constante incluida en la FK. Los registros son `operaciones` + `movimientos_stock` + `jornadas` + los dos historiales. Sin tabla genérica de auditoría. Append-only por grants y RLS (sin `UPDATE` ni `DELETE`), sin triggers.

#### 18.4.9 Pruebas obligatorias

Comprenden las 24 pruebas normativas de ADR-007 §7 y los grupos de abajo. Los rechazos de `anon` y `service_role` se verifican **sólo por SQLSTATE `42501`**, con el mensaje en `NULL` (por ejemplo, `throws_ok(<sql>, '42501', null, <descripción>)`). PostgreSQL puede rechazar en el esquema o en el objeto, y el texto no forma parte del contrato.

**S. Seguridad e integridad** (sin cambios respecto de v0.2/v0.3, salvo la forma de verificar `42501`):
- Políticas directas con `SET ROLE propietario_rpc` y el claim de un vendedor, de un perfil inactivo o de otra empresa:
  - `INSERT` y `UPDATE` sobre `jornadas` → rechazo por RLS;
  - `SELECT` de jornadas de otra empresa → 0 filas.
- `CHECK` (`23514`): `apertura_jornada` con `jornada_id`; `carga` sin `jornada_id`; `ingreso` con `jornada_id`; movimiento `carga` sin jornada; `merma` con jornada.
- FK de referencia (`23503`):
  - jornada que apunta a una operación de tipo `carga` o de otro actor;
  - historial que apunta a una operación de otra jornada o de otro tipo;
  - movimiento `carga` con una operación de tipo `descarga`.
- Políticas del ledger: `carga` hacia la ubicación de otro camión; `descarga` hacia una ubicación que no es depósito; `o.jornada_id` distinto de `m.jornada_id` → rechazo.
- Por cada una de las seis RPC:
  - `anon` → `42501`;
  - sin perfil, perfil inactivo o `vendedor_piloto` → `PT403`;
  - objeto de otra empresa → `PT404` idéntico al de inexistente;
  - `service_role` → `42501` en fachada e implementación, y `42501` en `SELECT` y DML sobre las 3 tablas nuevas;
  - DML directo de `authenticated` → `42501`.
- Catálogo: las 12 funciones con ACL exacta y sin sobrecargas; RLS sin `FORCE` en las 3 tablas; privilegios por columna exactos de `propietario_rpc`; `propietario_rpc` sin `UPDATE`/`DELETE` sobre `operaciones` y `movimientos_stock`.

**N. Nulabilidad.** Se insertan como owner de la tabla, para que el error sea la restricción y no la RLS.
- N1. Catálogo: columnas sin `attnotnull` en `jornadas` y en cada historial = `'{}'`.
- N2–N5. `operacion_id` NULL y `actor_id` NULL en cada historial → `23502`.
- N6. `empresa_id`, `jornada_id` y `tipo_operacion` NULL explícito → `23502`.
- N7. `jornadas` con `operacion_apertura_id`, `abierta_por` o `tipo_operacion_apertura` NULL → `23502`.
- N8. Control: fila válida e igual, salvo la operación de otro tipo o actor → `23503`.
- N9. Catálogo: definición exacta de las FK de 4 y 5 columnas.

**P. Lectura de perfiles sin recursión.**

| # | Caso | Esperado |
|---|---|---|
| P1 | **Membresía (patrón O-3)**, igual que para `propietario_rpc` en `hardening_adr001`: exactamente dos filas para `roleid = lector_perfiles_rpc`, ambas con `member = postgres`: (a) grantor con `rolsuper`, `admin = t`, `inherit = f`, `set = f`; (b) grantor `postgres`, `admin = f`, `inherit = f`, `set = t`. Ninguna fila con `inherit = t`. `lector_perfiles_rpc` no es miembro de ningún rol. `pg_has_role(postgres, …, 'SET') = t` y `'USAGE' = f`. `anon`, `authenticated`, `authenticator`, `service_role` y `propietario_rpc` sin SET ni USAGE | exacto |
| P2 | Atributos NOLOGIN/NOSUPERUSER/NOBYPASSRLS/NOCREATEDB/NOCREATEROLE/NOREPLICATION; privilegio de 4 columnas `SELECT` sobre `perfiles`; ningún otro privilegio de tabla; sin `USAGE` ni `CREATE` sobre `privado` ni `public`; dueño de exactamente una relación (la vista) y de ninguna función | exacto |
| P3 | Helper: `SECURITY DEFINER`, owner `propietario_rpc`, `search_path=""`, `STABLE`, sin parámetros, ACL exacta (sólo `propietario_rpc`) y sin sobrecargas; `has_function_privilege` falso para `lector_perfiles_rpc`, `authenticated`, `anon`, `service_role` y `postgres` | exacto |
| P4 | Vista: owner `lector_perfiles_rpc`, `security_invoker=false`, `security_barrier=true`, 4 columnas, ACL sólo con owner y `SELECT` de `propietario_rpc` | exacto |
| P5 | Políticas de `perfiles`: las de `authenticated` y de `propietario_rpc` iguales a hoy; una sola nueva, `SELECT TO lector_perfiles_rpc`; ninguna de escritura | exacto |
| P6 | Como `propietario_rpc`, con el claim de un dueño de A, se lee la vista | todos los perfiles de A, incluidos inactivos y vendedores; ninguno de B; sin `42P17` ni `54001` |
| P7 | Lo mismo con encargado de A, vendedor de A, dueño inactivo, sin perfil y sin `sub` | encargado: los de A; los otros cuatro: 0 filas |
| P8 | Dueño de B | sólo los de B |
| P9 | Como `propietario_rpc`, `SELECT` directo de `public.perfiles` con el claim de un dueño | sólo la fila propia |
| P10 | `authenticated`, `anon` y `service_role` sobre la vista y el helper; `service_role` sobre `public.perfiles` | `42501`, verificado sólo por SQLSTATE |
| P11 | `abrir_jornada` con vendedor de otra empresa, inexistente o inactivo | `PT404 jornada_vendedor_no_encontrado`, el mismo `PT404` idéntico y **`PT400 jornada_vendedor_invalido`**, en ese orden, sin efectos |
| P12 | `reasignar_vendedor` con los mismos tres casos | igual que P11 |
| P13 | `EXECUTE` dentro de la política: en una transacción revertida se revoca a `propietario_rpc` el `EXECUTE` del helper y se lee la vista | `42501`: el privilegio se verifica contra el llamador, no contra el dueño de la vista |
| P14 | `SET ROLE lector_perfiles_rpc` y `SELECT` directo de `public.perfiles` | `42501` (falla cerrado, sin recursión) |

**I. Idempotencia (H-02).** Fija qué se prueba; no modifica el contrato de 18.4.3 y 18.4.4. Todos los casos se ejecutan para **cada una de las seis RPC**. I1 a I9 e I12 a I14 son pgTAP; I10 e I11 usan dos sesiones y se ejecutan con el arnés de 18.4.11, con su criterio de aprobación.

| # | Caso | Esperado |
|---|---|---|
| I1 | Primera ejecución válida | Respuesta con la forma de 18.4.2; **efectos exactos** de la tabla «por RPC» (filas y columnas, ni una más); `operaciones.huella` igual a la fórmula de 18.4.4 recalculada en el test con un texto escrito aparte; `empresa_id`, `actor_id`, `idempotency_key` y `jornada_id` según 18.4.1 |
| I2 | Replay idéntico e inmediato (misma clave, mismo actor, mismos parámetros) | La **misma** respuesta (mismo uuid); cero filas nuevas en `operaciones`, `movimientos_stock`, `jornadas` y los dos historiales; las filas y los saldos existentes, byte a byte iguales (se comparan antes y después) |
| I3 | Replay después de que la jornada cambió a un estado donde el comando nuevo se rechazaría (columna «Estado de I3») | La misma respuesta que en I1, **sin revalidar estado ni fecha** (18.4.3, paso 5); cero filas nuevas; la jornada conserva el estado alcanzado |
| I4 | Replay con autorización perdida (perfil inactivo o rol `vendedor_piloto`) | `PT403`, sin efectos: la autorización vigente precede al replay (18.4.3, pasos 2 y 5) |
| I5 | Replay con estructura inválida, **sólo en las RPC con un parámetro estructural validable** (tabla «Aplicabilidad de I5»): misma clave y un parámetro de esa tabla inválido | El SQLSTATE y el código de la tabla (`PT400`, o `PT404` para el camión o la jornada nulos; 18.4.3, el paso 3 precede al paso 5 y a 8a); no `PT409` ni la respuesta guardada |
| I6 | **Conflicto por payload:** misma clave, payload válido distinto, un parámetro por vez (columna «Payload distinto») | `PT409 jornada_conflicto_idempotencia`; cero filas nuevas; la operación original y su huella, intactas |
| I7 | **Conflicto por tipo:** la clave de una operación de cada uno de los otros cinco tipos de jornadas y de `ingreso`, `a_cuarentena` y `merma` de Stock | `PT409 jornada_conflicto_idempotencia`; cero filas nuevas. Regresión de Stock: las RPC de Stock con una clave de jornadas siguen devolviendo su propio `stock_conflicto_idempotencia`, sin cambio |
| I8 | Misma clave usada por otro actor de la misma empresa y por un actor de otra empresa | No es replay: se ejecuta como operación nueva e independiente (`UNIQUE (empresa_id, actor_id, idempotency_key)`); la operación del primer actor no cambia |
| I9 | Un rechazo no reserva la clave: ejecución rechazada en los pasos 8b a 12 (por ejemplo `jornada_estado_invalido` o `jornada_stock_insuficiente`) y después la misma clave con un payload válido | La segunda se ejecuta como primera ejecución (I1); la rechazada no dejó fila en `operaciones` |
| I10 | Concurrentes, **misma clave y mismo payload**, en los dos órdenes de lanzamiento. En `reasignar_vendedor` y `corregir_jornada` incluye el caso en que la segunda sesión leyó en el paso 6 los valores previos a la confirmación de la primera (el arnés las encola según 18.4.11: sobre los mismos advisory o, en `registrar_carga`, `registrar_descarga` y `confirmar_salida`, sobre el `FOR UPDATE` de la jornada), de modo que sin el paso 8a fallaría la reverificación | Las dos confirman con la misma respuesta. En `reasignar_vendedor` y `corregir_jornada` la segunda la resuelve en 8a (es observable: 8b rechazaría). En `abrir_jornada`, `registrar_carga`, `registrar_descarga` y `confirmar_salida` no puede distinguirse 8a del `ON CONFLICT` del paso 9, y el caso sólo comprueba que ninguna sesión resolvió el replay en el paso 5. **Nunca** `jornada_estado_invalido` ni conflicto; exactamente una operación y un solo conjunto de efectos (los de I1), sin historial duplicado; cero `40P01` |
| I11 | Concurrentes, **misma clave y payload distinto**, en los dos órdenes; en `reasignar_vendedor` y `corregir_jornada` incluye el caso en que la primera cambia los valores usados como clave. El conflicto se detecta en 8a cuando las solicitudes comparten los bloqueos correspondientes; las variantes sin bloqueos compartidos (por ejemplo «otra jornada») se resuelven mediante el `ON CONFLICT` del paso 9 (K8). En `confirmar_salida`, cuyo único parámetro es la jornada, I11 no ejerce 8a | Una confirma y la otra `PT409 jornada_conflicto_idempotencia`, detectado en 8a antes de la reverificación 8b cuando comparten bloqueos, o en el `ON CONFLICT` del paso 9 cuando no los comparten (**nunca** `jornada_estado_invalido`); efectos sólo de la que confirmó; cero `40P01` |
| I12 | **Canonicalización:** los mismos datos escritos de otra forma (columna «Canonicalización») | Replay idéntico (como I2), no conflicto; los datos realmente distintos dan I6 |
| I13 | **Parámetro estructural inválido con clave `uuid` válida y nueva:** cada caso de la tabla de aplicabilidad (vendedor, camión, jornada, fecha, motivo, arreglos y cantidades) | El SQLSTATE y el código de la tabla (`PT400`, o `PT404` para el camión o la jornada nulos); **ninguna fila con esa clave** en `operaciones` ni filas nuevas en el resto de las tablas (el paso 3 precede a la reserva del paso 9); después, la **misma clave con el payload corregido** se ejecuta como primera ejecución (I1) |
| I14 | **Clave nula** (`idempotency_key` NULL), con un actor autorizado y el resto de los parámetros válidos | `PT400 jornada_clave_invalida`; cero efectos: ninguna fila nueva en `operaciones`, `jornadas`, `movimientos_stock` ni los historiales (no existe clave que reservar ni que reutilizar). Se ejecuta para las seis RPC |

**Aplicabilidad de I5 (H2-R2).** I5 sólo se ejecuta donde 18.4.3 (paso 3) y 18.4.7 definen un parámetro estructural validable. No se agregan parámetros ni códigos de error. La clave no cuenta: en un replay es la misma. El vendedor, el camión y la jornada nulos cuentan como parámetros estructurales por el paso 3, con los códigos que 18.4.7 ya define (D-N1, opción A).

| RPC | Parámetro estructural validable | Caso de I5 | Esperado |
|---|---|---|---|
| `abrir_jornada` | `fecha`; `vendedor`; `camion` | fecha nula; vendedor nulo; camión nulo | `PT400 jornada_fecha_invalida`; `PT400 jornada_vendedor_invalido`; `PT404 jornada_camion_no_encontrado` |
| `reasignar_vendedor` | `vendedor` (destino); `jornada` | vendedor nulo; jornada nula | `PT400 jornada_vendedor_invalido`; `PT404 jornada_no_encontrada` |
| `corregir_jornada` | `fecha`; `motivo`; `jornada`; `camion` (final) | fecha nula; motivo nulo o vacío después de `btrim`; jornada nula; camión final nulo | `PT400 jornada_fecha_invalida`; `PT400 jornada_motivo_invalido`; `PT404 jornada_no_encontrada`; `PT404 jornada_camion_no_encontrado` |
| `registrar_carga` | arreglos; cantidades; `jornada` | arreglos nulos, de largo distinto, vacíos o con elementos nulos; producto repetido; cantidad 0 o negativa; jornada nula | `PT400 jornada_lineas_invalidas`; `PT400 jornada_producto_repetido`; `PT400 jornada_cantidad_invalida`; `PT404 jornada_no_encontrada` |
| `registrar_descarga` | arreglos; cantidades; `motivo`; `jornada` | los de `registrar_carga` y motivo nulo o vacío después de `btrim` | los de `registrar_carga` y `PT400 jornada_motivo_invalido` |
| `confirmar_salida` | `jornada` | jornada nula (la clave no cuenta: en un replay es la misma) | `PT404 jornada_no_encontrada` |

**Decisión D-N1 (resuelta por el humano, opción A; exclusivamente para jornadas).** El camión nulo y la jornada nula se rechazan en el paso 3 con los `PT404` ya existentes, `jornada_camion_no_encontrado` y `jornada_no_encontrada`, antes de la huella, de cualquier consulta de replay y de la reserva de la clave. Un `uuid` válido pero inexistente o de otra empresa conserva el mismo `PT404`, validado después (paso 6 o 10). No se agregan códigos. Es la misma convención que hoy usan `registrar_ingreso`, `mover_a_cuarentena` y `registrar_merma` ante un producto o una ubicación nulos; la decisión rige sólo para las RPC de este anexo y no modifica Stock. La contrapartida es que el nulo y el inexistente comparten código; se distinguen por el paso en que se rechazan y por la prueba de I5.

**Datos por RPC.** `<m>` y las líneas ordenadas se definen en 18.4.4. «Efectos» es lo que I1 debe comprobar exactamente.

| RPC | Respuesta | Texto de la huella v1 | Efectos de I1 | Payload distinto (I6) | Estado de I3 | Canonicalización (I12) |
|---|---|---|---|---|---|---|
| `abrir_jornada` | uuid de la jornada (`jornadas.id`, la ligada por `operacion_apertura_id`) | `v1\|apertura_jornada\|<camión>\|<fecha>\|<vendedor>` | `operaciones` +1 (`apertura_jornada`, `jornada_id` NULL, actor = llamador); `jornadas` +1 (`abierta`, `abierta_por` = actor, `operacion_apertura_id` = esa operación, camión, fecha y vendedor del pedido); movimientos 0; historiales 0 | otro camión; otra fecha; otro vendedor | jornada ya `en_reparto` (tras carga y salida) | uuid escrito en mayúsculas = mismo valor; misma `date` |
| `reasignar_vendedor` | uuid de la operación | `v1\|reasignacion_vendedor\|<jornada>\|<vendedor>` | `operaciones` +1 (`reasignacion_vendedor`, `jornada_id` = J); historial de reasignaciones +1 (anterior = vigente previo, nuevo, operación, actor); `jornadas.vendedor_id` = nuevo y nada más; movimientos 0 | otro vendedor; otra jornada | jornada `en_reparto`; o vendedor reasignado después por otra operación (el replay devuelve la operación original, no el estado actual) | uuid en mayúsculas |
| `corregir_jornada` | uuid de la operación | `v1\|correccion_jornada\|<jornada>\|<fecha>\|<camión>\|<m>` | `operaciones` +1 (`correccion_jornada`); historial de correcciones +1 (fecha y camión anteriores y nuevos, motivo con `btrim`); `jornadas.fecha` y `camion_id` nuevos, vendedor y estado intactos; movimientos 0 | otra fecha; otro camión; otro motivo; otra jornada | jornada `cargada` (tras la primera carga) | motivo con espacios laterales = mismo motivo; mayúsculas o espacios internos distintos = conflicto |
| `registrar_carga` | uuid de la operación | `v1\|carga\|<jornada>\|<producto>:<cantidad>,…` con líneas ordenadas por el texto del uuid del producto | `operaciones` +1 (`carga`, `jornada_id` = J); `movimientos_stock` +n, una por línea (`carga`, depósito propio → ubicación del camión, producto, cantidad, `jornada_id`, `operacion_id`, motivo NULL); estado `cargada` si estaba `abierta`, igual si no; por producto, depósito −c y camión +c | otra cantidad; otro producto; línea agregada o quitada; otra jornada | jornada `en_reparto` (tras la salida) | las mismas líneas en otro orden de los arreglos = replay; producto repetido = `PT400 jornada_producto_repetido` antes del replay; arreglos de largo distinto = `PT400 jornada_lineas_invalidas` |
| `registrar_descarga` | uuid de la operación | `v1\|descarga\|<jornada>\|<líneas ordenadas>\|<m>` | `operaciones` +1 (`descarga`); `movimientos_stock` +n (`descarga`, ubicación del camión → depósito propio, motivo = `btrim`); estado igual; por producto, camión −c y depósito +c | otra cantidad; otro producto; otro motivo; línea agregada o quitada | jornada `en_reparto` | orden de líneas y `btrim` del motivo, como arriba |
| `confirmar_salida` | uuid de la operación | `v1\|salida_jornada\|<jornada>` | `operaciones` +1 (`salida_jornada`); `jornadas.estado` = `en_reparto`; movimientos 0; historiales 0 | otra jornada | ya `en_reparto` por esta misma operación (el replay devuelve la original; una salida nueva daría `jornada_estado_invalido`) | uuid en mayúsculas |

**K. Concurrencia.** Se ejecutan con el arnés de 18.4.11. Cero `40P01` en todos los casos. Para K10, K11 y K12 (y para I10 e I11) la ausencia de `40P01` no basta: se exigen también el resultado y las invariantes de la columna «Esperado», comprobadas con consultas sobre las tablas después de cada repetición.

| # | Caso | Esperado |
|---|---|---|
| K1 | I-1, intercambio en la misma fecha | las dos `PT409 jornada_vendedor_ocupado` |
| K2 | I-1b, cadena, en los dos órdenes | el resultado del orden serial correspondiente |
| K3 | I-2, apertura con el vigente contra reasignación, en los dos órdenes | el resultado del orden serial correspondiente |
| K4 | I-2 hacia el nuevo | una confirma y la otra `PT409 jornada_vendedor_ocupado` |
| K5 | I-3, corrección con cambio de fecha contra reasignación de la misma J, en los dos órdenes, incluida la variante en que la reasignación ya tiene un advisory y espera el segundo mientras la corrección tiene el camión | OK/OK, o OK y `PT409 jornada_estado_invalido`; reintentar con la misma clave confirma |
| K6 | I-3b, en los dos órdenes, para una corrección con cambio de fecha y para una corrección sólo de camión | se serializan en el nivel 2 |
| K7 | Correcciones cruzadas de camión (C1 → C2 y C2 → C1) sobre dos jornadas, ya con el bloqueo de vendedor de H-01: vendedores distintos; vendedores distintos con el orden de uuid inverso al de los camiones; el mismo vendedor en fechas distintas | cero `40P01`; el resultado de algún orden serial |
| K8 | Regresiones: dos cargas de la misma J (CONC-18.4-01); `registrar_merma` contra `registrar_carga` con la misma clave y el mismo advisory de stock; misma clave en dos jornadas distintas; carga contra reasignación de la misma J; corrección de camión contra `mover_a_cuarentena`; baja concurrente de camión, producto o perfil | el resultado de algún orden serial; conflicto de idempotencia donde corresponde |
| K9 | Se cambia el vigente entre los pasos 6 y 8b por **otra operación confirmada con distinta clave**, en `reasignar_vendedor` y en `corregir_jornada` (también la corrección sólo de camión). La sesión afectada aún no tiene su clave reservada, así que 8a no encuentra nada | `PT409 jornada_estado_invalido`, sin reserva ni historial; reintentar con la misma clave y los valores nuevos confirma. Contrapartida: con la **misma** clave (I10) el resultado es la respuesta original, no este error |
| K10 | **Aperturas concurrentes**, con claves distintas salvo en d) y e), en los dos órdenes de lanzamiento: a) mismo camión y misma fecha, vendedores distintos; b) mismo camión y fechas distintas; c) mismo vendedor y misma fecha, camiones distintos; d) misma clave y mismos parámetros; e) misma clave y distinto vendedor | a) una confirma y la otra `PT409` con `jornada_duplicada` o `jornada_camion_con_jornada_abierta` (el contrato no fija precedencia entre ambos códigos: el arnés acepta cualquiera de los dos); b) una confirma y la otra `PT409 jornada_camion_con_jornada_abierta`; c) una confirma y la otra `PT409 jornada_vendedor_ocupado`; d) las dos confirman con el **mismo** uuid de jornada; e) una confirma y la otra `PT409 jornada_conflicto_idempotencia`. **Invariantes:** I-J1 (a lo sumo una jornada por `(empresa, camión, fecha)` y por `(empresa, vendedor, fecha)`, y una sin cerrar por camión); en a) a d) queda exactamente **una** jornada y **una** operación `apertura_jornada` confirmada por clave (la rechazada revierte su reserva, sin historial ni fila huérfana) |
| K11 | **Salida contra cambios de carga neta** sobre la misma jornada `cargada` con carga neta positiva, en los dos órdenes: a) `confirmar_salida` contra `registrar_descarga` de toda la carga neta; b) `confirmar_salida` contra `registrar_carga`; c) dos `confirmar_salida`, con claves distintas y con la misma clave; d) dos `registrar_descarga` con claves distintas, cada una dentro de lo cargado neto pero con suma mayor | a) salida primero: salida confirma (`en_reparto`) y la descarga `PT409 jornada_estado_invalido`; descarga primero: descarga confirma y la salida `PT409 jornada_carga_neta_cero`; **nunca confirman las dos**. b) carga primero: confirman las dos; salida primero: salida confirma y la carga `PT409 jornada_estado_invalido`, sin movimientos. c) claves distintas: una confirma y la otra `PT409 jornada_estado_invalido`; misma clave: las dos confirman con el mismo uuid y queda **una** operación `salida_jornada`. d) una confirma y la otra `PT409 jornada_descarga_excede_carga`. **Invariantes:** I-J4 (jornada en `en_reparto` ⇒ carga neta de la jornada positiva en al menos un producto); I-J2 (por producto, saldo del camión = Σ cargas − Σ descargas de la jornada y nunca negativo; saldo del depósito + saldo del camión, constante); I-J3 (una operación rechazada no deja filas en `operaciones` ni en `movimientos_stock`); como máximo una `salida_jornada` por jornada |
| K12 | **Corrección sólo de camión contra reasignación de la misma J** (I-3c), en los dos órdenes de lanzamiento, con el vendedor nuevo mayor y menor que el vigente por uuid, incluida la variante en que la reasignación ya tiene sus advisory y la corrección tiene los camiones y espera al vendedor | Corrección primero: las dos confirman (equivale a corrección; reasignación). Reasignación primero: la reasignación confirma y la corrección `PT409 jornada_estado_invalido` por haber cambiado el vigente, sin reserva ni historial; reintentar con la misma clave confirma. **Invariantes:** I-J1; una fila de historial por operación confirmada y ninguna por la rechazada; camión y vendedor finales de la jornada consistentes con algún orden serial; cero `40P01` |

**Impacto de H-01 sobre K1–K11.** El cambio toca sólo el conjunto de bloqueos de `corregir_jornada` (el vendedor, siempre). Evaluación, sin atribuirle evidencia al laboratorio anterior:
- **Se amplían o repiten con el código final y son necesarios para aceptar H-01:** K6 (variante sólo de camión), K7 (con el bloqueo de vendedor presente y el caso del mismo vendedor), K9 (también `corregir_jornada`) y el nuevo K12. K5 se repite igual: el conjunto de bloqueos con cambio de fecha no cambia, pero el camino de código sí.
- **No cambian de diseño, pero se ejecutan igual con el código final:** K1 a K4 (sólo abren y reasignan), K10 y K11. Ninguno usa `corregir_jornada`.
- **K8** incluye «corrección de camión contra `mover_a_cuarentena`»: se repite, porque la corrección ahora también toma un advisory de vendedor, que las RPC de Stock no toman; no se forma ciclo, pero hay que medirlo.
- Los resultados de 18.4.12 **no** prueban el mecanismo nuevo. Hasta que K5 a K9 y K12 pasen sobre las migraciones reales, H-01 es un diseño razonado, no una propiedad demostrada.

**Impacto de H2-R1.** Sólo ordena una consulta de la clave: no agrega ni cambia bloqueos ni estados, y no modifica el contrato funcional de idempotencia.
- **Reescritos:** I10, I11 y K9, para que el orden 8a antes de 8b sea observable. I5 e I9 cambian sólo por H2-R2 y por la referencia al paso 8b.
- **Sin cambio de diseño, se ejecutan igual con el código final:** K1 a K8 y K10 a K12. K8 («misma clave en dos jornadas distintas») sigue ejerciendo el `ON CONFLICT` del paso 9, porque esas solicitudes no comparten bloqueos. K10 d) y e) y K11 c) (misma clave) no reverifican valores clave y no cambian.
- Nada de 18.4.12 prueba el paso 8a: queda demostrado sólo cuando I10, I11 y K9 pasen sobre las migraciones reales.

#### 18.4.10 Cambios sobre objetos y tests existentes

**Objetos existentes que se modifican.** Sólo se amplían; ninguna definición existente se debilita.
- `CHECK`: `operaciones_tipo_valido`, `movimientos_stock_tipo_valido`, `movimientos_stock_forma_por_tipo` y `movimientos_stock_motivo_por_tipo`.
- Políticas: `operaciones_insert_propietario_rpc` y `movimientos_stock_insert_propietario_rpc` (extensión de D6 y D8).
- Columnas, FK, `CHECK`, `UNIQUE` e índices nuevos de 18.4.1.
- `perfiles`: una política `SELECT TO lector_perfiles_rpc` y un grant `SELECT` por columna a ese rol. Sin cambios para `authenticated` ni para `propietario_rpc`.

**Inventario de aserciones pgTAP.** Nada se elimina ni se relaja: las listas se amplían.

| Archivo:línea | Qué fija | Cambio |
|---|---|---|
| `stock_ingreso.test.sql:100` | Columnas de `operaciones` | + `jornada_id` |
| `stock_ingreso.test.sql:111` | Columnas de `movimientos_stock` | + `jornada_id` |
| `stock_ingreso.test.sql:140-150` | Constraints exactas de `operaciones` | + FK de jornada, `jornada_por_tipo`, los dos UNIQUE de referencia y `tipo_valido` ampliado |
| `stock_ingreso.test.sql:152-171` | Constraints exactas de `movimientos_stock` | + FK de jornada, FK de referencia, `jornada_por_tipo`, `tipo`/`forma`/`motivo_por_tipo` ampliados |
| `stock_ingreso.test.sql:173-180` | Índices no únicos de `movimientos_stock` | + índice por jornada |
| `stock_ingreso.test.sql:194` | Nombres, comandos y roles de las políticas | sin cambio; debe seguir pasando |
| `stock_ingreso.test.sql:231` y `:239` | Columnas que `propietario_rpc` puede insertar | + `jornada_id` |
| `stock_ingreso.test.sql:701` | «operaciones rechaza tipos no aprobados (carga)» | pasa a un tipo no aprobado vigente (`venta`); se conserva la prueba negativa |
| `stock_cuarentena_merma.test.sql:129-141` | Definiciones exactas de tipo, forma y motivo | ampliadas con `carga` y `descarga`; las tres formas previas, textuales |
| `stock_cuarentena_merma.test.sql:143` (D7) | Índice de operación unitaria | sin cambio |
| `stock_cuarentena_merma.test.sql:160` | Regex de la política del ledger | sigue pasando; + aserción hermana para `carga` y `descarga` |
| `stock_cuarentena_merma.test.sql:205` | `propietario_rpc` sin `UPDATE`/`DELETE`/`TRUNCATE` | sin cambio |
| `productos_catalogo.test.sql:216-234` | Lista exacta de funciones `SECURITY DEFINER` de `privado` (13) | **20**: + `abrir_jornada(uuid,uuid,date,uuid)`, `confirmar_salida(uuid,uuid)`, `corregir_jornada(uuid,uuid,date,uuid,text)`, `empresa_gestion_actual()`, `reasignar_vendedor(uuid,uuid,uuid)`, `registrar_carga(uuid,uuid,uuid[],integer[])`, `registrar_descarga(uuid,uuid,uuid[],integer[],text)`, en el orden de `order by 1`. Etiqueta: «… exactamente las veinte: diecinueve implementaciones y el auxiliar `empresa_gestion_actual`». |
| `productos_catalogo.test.sql:321-337` | Auxiliares de `privado` sólo ejecutables por `propietario_rpc` (esperado 0) | Se excluyen **sólo** las seis implementaciones nuevas (las cubre el test de jornadas). `empresa_gestion_actual` **queda dentro**; el contrato no define otros auxiliares (18.4.6). El esperado sigue en 0. |
| `camiones_catalogo.test.sql:183-201` | La misma lista exacta (13) | **20**, idéntica a la de `productos_catalogo` |
| `hardening_adr001.test.sql:48-51` | Lista fija `tablas_negocio` (8) | + `jornadas` y los dos historiales (11) |
| `hardening_adr001.test.sql:55-…` | Lista fija `rpc_negocio` | + 12 firmas |
| `hardening_adr001.test.sql:205-210` | Toda función de `privado` es de `propietario_rpc` | **sin cambio** (0); la vista no es función |
| `hardening_adr001.test.sql:212-217` | Implementaciones de `rpc_negocio` `SECURITY DEFINER` de `propietario_rpc` (10) | 16 |
| `hardening_adr001.test.sql:219-229` | Membresías de `propietario_rpc` | sin cambio; + P1 para `lector_perfiles_rpc`, con la misma forma |
| `grants_default_privileges.test.sql` (`matriz`, `:43-92`) | Matriz fija de tablas y privilegios | + las 3 tablas nuevas con sus esperados |
| `grants_default_privileges.test.sql:165-196` | Firmas aprobadas para `authenticated` (26) | 38 (`empresa_gestion_actual` no entra: `authenticated` no la ejecuta) |
| `auth_base_rls.test.sql:76`, `:92-95`, `:116` y `productos_catalogo.test.sql:183-186` | RLS en todas las tablas; sin políticas de escritura en perfiles; sin `SECURITY DEFINER` en `public`; `propietario_rpc` sólo lee perfiles | **sin cambio**; deben seguir pasando |
| `stock_peso_gramos.test.sql:77` y `:99` | Ledger sin columnas `numeric`/kg; firmas de Stock | sin cambio |

#### 18.4.11 Arnés de concurrencia (requisito)

**Ubicación.** `supabase/tests/concurrencia/`:
- `arnes.sh`: orquestador;
- `00_bootstrap_descartable.sql`: roles y `auth` emulados;
- `casos.sh` (o equivalente): definición de K1–K12 y de los casos I10 e I11.

No reemplaza a pgTAP ni a Playwright. No se versiona ningún estado generado.

**Sin dependencias nuevas.** Usa sólo `bash`, `psql`, `initdb` y `pg_ctl` de PostgreSQL 17, que ya están disponibles localmente. No usa `dblink`, extensiones, paquetes npm ni imágenes nuevas.

**Sólo contra un clúster descartable.**
- El arnés crea su propio clúster efímero: `initdb` en un directorio temporal, `pg_ctl` con `listen_addresses=''`, socket Unix en un directorio temporal de ruta corta (el límite es 107 bytes), puerto propio y `deadlock_timeout` reducido.
- Aplica `00_bootstrap_descartable.sql` y después **todas** las migraciones de `supabase/migrations/` en orden lexicográfico, con `psql -v ON_ERROR_STOP=1`.
- Al final detiene y borra el clúster.
- Descarta (`unset`) toda variable `PG*` del entorno. No acepta host, puerto ni URL externos y sólo se conecta a su propio socket. Nunca se ejecuta contra Supabase local, staging ni producción.
- En CI corre igual, creando su propio clúster dentro del job.

**Bootstrap emulado** (debe documentarse como tal en el archivo):
- roles con los atributos observados en Supabase 17.11: `postgres` LOGIN NOSUPERUSER CREATEROLE BYPASSRLS, miembro con INHERIT de `anon`, `authenticated` y `service_role`; `service_role` BYPASSRLS; `anon` y `authenticated` NOBYPASSRLS;
- superusuario de arranque `supabase_admin`;
- esquema `auth` con `USAGE` para `anon`, `authenticated`, `service_role` y `postgres`;
- `auth.uid()` emulado con la misma expresión de claims que `privado.usuario_actual()`;
- tabla mínima `auth.users (id uuid primary key)` para que las FK de `perfiles` se puedan crear.

**Mecanismo.**
- Por caso: datos iniciales como `postgres`; una sesión de **control** retiene el recurso de cola que corresponde a cada RPC: un advisory a nivel de sesión (`pg_advisory_lock`) sobre las mismas claves que usan las RPC (18.4.5) o, en las RPC que no toman advisory de nivel 1 ni 2, el bloqueo de fila `FOR UPDATE` de la jornada (ver la tabla de «Cola previa de I10 e I11 según la RPC», más abajo); se lanza T1 y se espera, consultando `pg_stat_activity`, a que quede en `wait_event_type = 'Lock'`; se lanza T2 y se espera lo mismo (o, en los casos marcados, a que termine); la sesión de control libera el recurso según su tipo: `pg_advisory_unlock_all()` si es advisory, `ROLLBACK` de su transacción si es un bloqueo de fila.
- T1 y T2 son dos conexiones `psql` independientes. Cada una usa el claim de un dueño activo, `SET LOCAL ROLE authenticated` y llama a la **fachada `public` real**. No se agrega instrumentación al código bajo prueba.
- Se registran: el SQLSTATE de cada sesión (`\set VERBOSITY verbose`), el estado final de las filas y la diferencia de `pg_stat_database.deadlocks`, cruzada con `deadlock detected` en el log del clúster.
- Cada caso se repite R veces (10 por defecto, configurable) en los dos órdenes de lanzamiento.

**Cola previa de I10 e I11 según la RPC (A-02).** La sesión de control debe dejar a T1 y T2 esperando **antes** de que cualquiera reserve la clave, de modo que ambas hayan pasado el paso 5 sin operación visible y el replay se resuelva después, en 8a (o en el paso 9). El recurso que retiene el control depende de la RPC:

| RPC | Qué retiene la sesión de control | Dónde esperan T1 y T2 |
|---|---|---|
| `abrir_jornada` | `pg_advisory_lock` de la clave de camión y de la de vendedor (niveles 1 y 2), en el orden global | Paso 7 |
| `reasignar_vendedor` | Advisory del vendedor vigente y del nuevo, en orden de uuid | Paso 7 |
| `corregir_jornada` | Advisory del camión actual y final y del vendedor vigente, en orden de nivel y uuid | Paso 7 |
| `registrar_carga`, `registrar_descarga`, `confirmar_salida` | Estas RPC no toman advisory de nivel 1 ni 2. El control abre una transacción y ejecuta `SELECT 1 FROM public.jornadas WHERE id = <J> AND empresa_id = <E> FOR UPDATE` (nivel 3). Si el caso usa dos jornadas (variante «otra jornada» de I11), toma las dos filas en orden de uuid | Paso 8 (`FOR UPDATE` de la jornada) |

- **Reglas del control:** retiene sólo ese recurso (o el conjunto, en el orden global de 18.4.5); no espera ningún otro bloqueo; no escribe; usa un único mecanismo por caso; libera con `ROLLBACK` (fila) o `pg_advisory_unlock_all()` (advisory). No modifica datos.
- **Evidencia exigida antes de liberar.** Una conexión de **monitoreo** aparte, de sólo lectura, verifica con los `pid` de T1 y T2 (cada sesión ejecuta `SELECT pg_backend_pid()` antes de llamar a la RPC). Las cuatro condiciones valen **para ambas sesiones**:
  - (a) `pg_stat_activity`: `state = 'active'` y `wait_event_type = 'Lock'`;
  - (b) `pg_locks`: el `pid` tiene un bloqueo **no concedido** (`granted = false`) de tipo `advisory` (casos de advisory) o `tuple` o `transactionid` (caso de fila);
  - (c) `pg_locks`: el `pid` **no** tiene concedido ningún `RowExclusiveLock` sobre `operaciones`, `jornadas`, `movimientos_stock` ni los historiales (no reservó ni escribió);
  - (d) no existe ninguna fila de `operaciones` con la clave del caso (el paso 5 no encontró nada y la reserva no ocurrió).
  Si las cuatro no se cumplen para las dos sesiones dentro del tiempo límite, el caso **falla sin liberar** (el bloqueo se libera en la limpieza). Sólo entonces se libera y se espera a que terminen, registrando SQLSTATE y respuesta de cada una.
- **Qué demuestra y qué no.** Que ambas sesiones llegaron a la espera con el paso 5 ya cumplido, sin operación visible, y que el resultado final es el correcto. En `reasignar_vendedor` y `corregir_jornada`, 8a y el paso 9 son distinguibles por resultado, porque 8b rechazaría con `jornada_estado_invalido`: el caso prueba el paso 8a. En `abrir_jornada`, `registrar_carga`, `registrar_descarga` y `confirmar_salida` no hay valores clave que reverificar: con o sin 8a el resultado externo es el mismo, y el caso no distingue 8a del `ON CONFLICT` del paso 9. La variante «otra jornada» de I11 (la única de `confirmar_salida`) no comparte bloqueos y se resuelve en el paso 9 (K8).
- **Riesgo de deadlock del mecanismo de prueba** (evaluación; no medido hasta que el arnés exista):
  - El control retiene un único recurso, o el conjunto en el orden global, y no espera ninguno. El monitoreo sólo lee `pg_stat_activity` y `pg_locks`, sin tomar bloqueos que choquen con los de las RPC. Control y monitoreo no pueden cerrar un ciclo con T1 y T2.
  - Tras liberar, T1 y T2 compiten sólo por los bloqueos que usarían en producción, en el orden global: T2 espera a T1 y T1 no espera a T2.
  - El `FOR UPDATE` del control choca con un `FOR KEY SHARE` de FK. Un ciclo existiría sólo si una RPC tomara `KEY SHARE` sobre la jornada (al insertar `operaciones` con `jornada_id`) **antes** de su `FOR UPDATE`, el problema A de 18.4.5. En el orden de 18.4.3 la reserva es posterior al paso 8, así que ni T1 ni T2 lo poseen al esperar. La condición (c) detecta un orden indebido: el caso falla antes de liberar.
  - Cada sesión usa `lock_timeout` y `statement_timeout` (30 s por defecto, configurable) y el clúster `deadlock_timeout` reducido. Un deadlock real se reporta como `40P01` y se cuenta; el criterio de I10 e I11 es cero.
  - Riesgo residual: mezclar advisory y fila en un mismo caso podría violar el orden global; por eso el arnés usa un único mecanismo por caso.

**Autoverificación de sensibilidad.** Antes de los casos K, el arnés crea en el clúster efímero (nunca en una migración) una función de control `zz_` que toma los advisory de vendedor en orden ingenuo, y exige al menos un `40P01` en el intercambio de I-1. Si no lo detecta, el arnés falla: no mide nada.

**Criterio de aprobación (exit 0).**
- Cero `40P01` y cero `40001` en todos los casos K.
- La diferencia de `pg_stat_database.deadlocks` es igual a la que produjo sólo la autoverificación.
- Cada resultado coincide con alguno de los órdenes seriales esperados y, en K10, K11, K12, I10 e I11, se cumplen las invariantes y los efectos indicados.
- Ninguna espera supera el tiempo límite.
- Cualquier otra cosa termina con exit ≠ 0 y el detalle por caso.

#### 18.4.12 Evidencia de laboratorio y sus límites

**Entorno.** PostgreSQL 17.11 (Debian) en un clúster aislado creado con `initdb`, sin red, con roles emulados según los atributos leídos (sólo lectura) del contenedor Supabase local 17.11. Se reprodujeron en mínimo `perfiles`, sus políticas, `propietario_rpc` (O-3), `privado.usuario_actual()` y la solución de 18.4.2.1, sin privilegios adicionales.

**Observado.**
- Dueño y encargado de A leen los 6 perfiles de A y ninguno de B; el dueño de B, sólo los de B.
- Vendedor, dueño inactivo, sin perfil y sin `sub`: 0 filas.
- `propietario_rpc` sobre `perfiles` sigue viendo sólo su fila.
- `anon`, `authenticated` y `service_role` reciben `42501`.
- Sin `42P17`. El helper no se inlinea.
- El `EXECUTE` dentro de la política se verifica contra `propietario_rpc`: revocarlo produce `42501`, y `lector_perfiles_rpc` sin `EXECUTE` no impide la lectura.
- Controles negativos: la política recursiva da `42P17`, y el helper en la política del mismo rol da `54001`.
- El `ALTER VIEW … OWNER` sin `CREATE` temporal da `42501`.
- La membresía generó las dos filas descritas.
- Por la RPC `SECURITY DEFINER` invocada como `authenticated`: vendedor de otra empresa o inexistente → `jornada_vendedor_no_encontrado`; inactivo → `jornada_vendedor_invalido`; llamador vendedor o dueño inactivo → `jornada_no_autorizado`.
- Arnés de dos conexiones, 10 repeticiones por caso: cero `40P01` en todos los casos v0.4 (intercambio, cadena, apertura contra reasignación, corrección contra reasignación, la variante con un bloqueo retenido y otro en espera, y cruce de camiones). La variante de control con orden ingenuo produjo `40P01` en 10 de 10. El contador de deadlocks aumentó sólo en esas 10. La variante v0.2 reprodujo el rechazo espurio de la cadena.

**Límites (no cubiertos por el laboratorio).**
- `auth.uid()` emulado; no se usó GoTrue ni JWT reales.
- No se reprodujo la FK `perfiles.usuario_id → auth.users`.
- Clúster Debian, no la imagen de Supabase.
- Las RPC del laboratorio fueron reproducciones mínimas de los niveles 1 a 3: sin idempotencia, `operaciones`, historiales, camiones reales ni stock.
- El laboratorio ejecutó `corregir_jornada` bloqueando al vendedor sólo ante cambio de fecha. **No cubre** el bloqueo permanente de H-01 (18.4.5) ni el caso I-3c.
- No hubo pruebas completas de esperas por índices únicos, `FOR KEY SHARE` de FK, advisory de stock (nivel 4) ni reserva de idempotencia.

Esos puntos se cubren recién con los tests de 18.4.9 sobre las migraciones reales: pgTAP en Supabase local, y K8 con el arnés. Hasta que pasen, esta evidencia no sustituye a esos tests.

#### 18.4.13 Autorizaciones humanas pendientes (ninguna concedida) y decisiones normativas resueltas

Resumen del bloque B de la entrega original. Nada de lo siguiente está autorizado por la sola presencia de este anexo:

1. Aprobación de §18.4 como anexo de ADR-001 (P10 y P12–P17 sólo para jornadas), previa revisión independiente (ADR-007 §3, P-3). Levanta P-3.
2. **D-1.** Ampliar `operaciones` y `movimientos_stock` (CHECK, políticas D6/D8, columnas, FK, `UNIQUE`, índices) y actualizar las aserciones pgTAP de 18.4.10 sin relajar ninguna.
3. **D-2.** Crear `lector_perfiles_rpc`, su vista, `privado.empresa_gestion_actual()` y la política `perfiles_select_empresa_lector`, con la membresía O-3 y el `CREATE` transitorio sobre `privado`. Introduce un segundo rol técnico, lo que amplía P2–P4 (hoy un solo rol técnico, `propietario_rpc`); hay que confirmar que no cambia P11 ni P5–P7.
4. Catálogo de errores de 18.4.7, con el vendedor inactivo como `PT400 jornada_vendedor_invalido`.
5. Versionar el arnés en `supabase/tests/concurrencia/` (18.4.11), solo contra su propio clúster efímero, con la versión de PostgreSQL y las rutas de binarios declaradas.
6. Ejecutar el arnés en CI: autorización aparte (implica tocar `.github/workflows/ci.yml`).
7. La tarea de implementación: rama, preámbulo de `AGENTS.md` §1.3, migraciones sólo en local o staging, **security review obligatoria** (toca Supabase, RLS, grants, `SECURITY DEFINER`, roles, `movimientos_stock`, idempotencia y concurrencia) y auditoría independiente del hash.
8. El corte de jornada (Blueprint §15, «Fechas») sigue pendiente; según ADR-007 §3, P-1, no afecta a este bloque.

**Decisiones normativas ya resueltas por el humano para este anexo** (no son autorizaciones de implementación):
- **D-N1 (opción A, exclusivamente para jornadas):** camión nulo → `PT404 jornada_camion_no_encontrado`; jornada nula → `PT404 jornada_no_encontrada`; ambos en 18.4.3, paso 3, antes de la huella, del replay y de la reserva. Sin códigos nuevos.

---

## 19. Consecuencias sobre `BLUEPRINT.md`

La alineación documental aplica estos cambios:

- **D:** Blueprint §10 define la fachada expuesta `SECURITY INVOKER`, la implementación privada/no expuesta `SECURITY DEFINER` y la implementación privada como frontera real de seguridad; §12 prueba esa cadena; §15 registra el estado intermedio.
- **A, B y C:** A queda descartada, B reservada para lógica externa y C no elegida.
- **Gobernanza:** `docs/decisions/README.md` incorpora `APROBADA PARA VALIDACIÓN CONTROLADA`; las migraciones dependientes de ADR-001 quedan habilitadas sólo local/staging.
- **Modelo de datos y decisiones técnicas:** P8–P10 y P12–P17 siguen pendientes; P11 global quedó resuelta para validación controlada (§18.2); P18 permanece separada. P2–P4 fijan los esquemas `public`/`privado`, el rol `propietario_rpc` y el ownership/RLS sin `FORCE` global. P5–P7 fijan un perfil 1:1 con `auth.users`, una sola empresa y un único rol por usuario, sin membresías. `auditoria`, `idempotency_key` y restricciones no quedan aprobadas por P1/P19/P20.
- **Producción:** continúa bloqueada hasta pruebas, auditoría independiente y aceptación humana final.

---

## 20. Observaciones documentales

1. La ambigüedad histórica sobre migraciones queda resuelta por P20 y la alineación de los documentos rectores.
2. Terminología de estado: el índice, la ADR y el Blueprint usan `APROBADA PARA VALIDACIÓN CONTROLADA` para la etapa intermedia.
3. Fuentes que difieren: *Hardening the Data API* (Supabase) frente a *ALTER DEFAULT PRIVILEGES* (PostgreSQL) sobre el `REVOKE ... FROM PUBLIC` por esquema (sección 12.6).

---

## 21. Fuentes oficiales consultadas (16/10/2026 y 17/10/2026)

- PostgreSQL 18 — ALTER DEFAULT PRIVILEGES: https://www.postgresql.org/docs/current/sql-alterdefaultprivileges.html
- PostgreSQL 18 — CREATE FUNCTION (Writing SECURITY DEFINER Functions Safely; volatilidad; sobrecarga): https://www.postgresql.org/docs/current/sql-createfunction.html
- PostgreSQL 18 — Row Security Policies: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
- PostgreSQL 18 — CREATE ROLE: https://www.postgresql.org/docs/current/sql-createrole.html
- PostgreSQL 18 — ALTER FUNCTION: https://www.postgresql.org/docs/current/sql-alterfunction.html
- PostgreSQL 18 — INSERT (ON CONFLICT): https://www.postgresql.org/docs/current/sql-insert.html
- PostgreSQL 18 — Explicit Locking: https://www.postgresql.org/docs/current/explicit-locking.html
- PostgreSQL 18 — Serialization Failure Handling: https://www.postgresql.org/docs/current/mvcc-serialization-failure-handling.html
- Supabase — Database Functions: https://supabase.com/docs/guides/database/functions
- Supabase — Database Advisors (lints 0011, 0028, 0029): https://supabase.com/docs/guides/database/database-advisors
- Supabase — Securing your API: https://supabase.com/docs/guides/api/securing-your-api
- Supabase — Hardening the Data API: https://supabase.com/docs/guides/database/hardening-data-api
- Supabase — Postgres Roles: https://supabase.com/docs/guides/database/postgres/roles
- Supabase — Row Level Security (auth.uid(), user_metadata, bypass; "Use security definer functions"): https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase — Anonymous Sign-Ins (rol `authenticated`, claim `is_anonymous`): https://supabase.com/docs/guides/auth/auth-anonymous
- Supabase — Breaking Change: Tables not exposed to Data and GraphQL API automatically (anuncio oficial, discusión n.º 45329; fechas 30/05/2026 y 30/10/2026): https://github.com/orgs/supabase/discussions/45329
- Supabase — Securing Edge Functions: https://supabase.com/docs/guides/functions/auth
- PostgREST v14 — Transactions: https://docs.postgrest.org/en/v14/references/transactions.html
- PostgREST v14 — Errors: https://docs.postgrest.org/en/v14/references/errors.html
- PostgREST v14 — Functions: https://docs.postgrest.org/en/v14/references/api/functions.html

*`docs.postgrest.org` respondió HTTP 429 a la consulta directa; los pasajes de PostgREST se tomaron de su documentación oficial v14 a través de Context7, con las URL originales.*
