# ADR-001 — Puerta de entrada SQL para operaciones privilegiadas

**Fecha:** 12/10/2026 · **Última revisión documental:** 23/10/2026
**Estado:** APROBADA PARA VALIDACIÓN CONTROLADA
**Versión:** 1.5 (registro de las decisiones humanas P2–P4; P5–P7 en v1.4)

> **Aviso de alcance.** La decisión humana resolvió P1, P19 y P20; el 22/10/2026, P5, P6 y P7; y el 23/10/2026, P2, P3 y P4 (§18). Esta ADR autoriza exclusivamente el diseño, las migraciones y las pruebas necesarias para validar la Topología D en local/staging, una vez resueltas las decisiones P8–P17 que requiera el alcance de la validación. **No autoriza producción**, no resuelve P8–P17 y no convierte P18 en requisito. La aceptación productiva exige pruebas, auditoría independiente y aceptación humana final (`AGENTS.md` §3 y §5; `BLUEPRINT.md` §10; `docs/decisions/README.md`).

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
| v1.5 (corrección terminológica) | Claude Code | Corrección terminológica: el producto es de empresa única; `empresa_id` es una frontera técnica de aislamiento y no una capacidad multiempresa. Renombra el encabezado de §8 a «Invariante de aislamiento por `empresa_id`» y alinea las referencias normativas de membresía (§3.1, §3.2, §8, §9, T2, T3 y la nota sobre inicio de sesión anónimo) al modelo aprobado de perfil 1:1, una empresa y un rol; sin cambio de comportamiento. Las garantías, T4/T5/T15 y el estado de la ADR (**APROBADA PARA VALIDACIÓN CONTROLADA**) no cambian. |

---

## 1. Contexto

El sistema nuevo **está previsto** sobre Supabase (Auth, PostgreSQL, RLS, RPC) con frontend React (`BLUEPRINT.md` §6). Hoy el repositorio contiene un prototipo frontend sin backend que persiste en `localStorage` (`INVENTARIO_ETAPA_0.md` §1); **todavía no existe** integración con Supabase ni con su Data API.

Cuando exista, la interfaz React **usará** la Data API de Supabase (PostgREST). Los usuarios `authenticated` no deberán poder escribir directamente en los libros de movimientos de stock y dinero (`BLUEPRINT.md` §3, §6, §10). Un enfoque `SECURITY INVOKER` puro sobre esas tablas exigiría conceder escritura directa a `authenticated`, lo que abriría rutas capaces de saltar las reglas de negocio y la auditoría. Esta ADR define la topología de la puerta de entrada para validación controlada; P2–P7 están resueltas (§18) y P8–P17 siguen pendientes.

---

## 2. Jerarquía normativa y alcance

- `BLUEPRINT.md` es la **fuente de mayor autoridad** del proyecto (`BLUEPRINT.md` línea 8; `AGENTS.md` §1). Mientras una ADR **aprobada** no la modifique, su regla **más estricta** permanece vinculante.
- `AGENTS.md` traslada esas reglas a instrucciones operativas para agentes; no las relaja. `INVENTARIO_ETAPA_0.md` está subordinado a ambos (su propia nota de precedencia).
- Una ADR en estado `APROBADA PARA VALIDACIÓN CONTROLADA`, como esta, modifica el Blueprint únicamente dentro de las decisiones resueltas y habilita sólo validación local/staging; no habilita producción ni completa decisiones pendientes.

**Alcance resuelto (P20).** Antes de la aprobación para validación controlada no podían generarse migraciones dependientes de ADR-001. Con el estado actual se permiten las migraciones necesarias para probar la ADR exclusivamente en local/staging. Producción permanece bloqueada hasta completar las pruebas requeridas, la auditoría independiente y la aceptación humana final. Esta autorización no alcanza a decisiones P8–P17 todavía pendientes ni a otras migraciones fuera del alcance de validación.

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
- **`service_role` no se asume** para operaciones de usuarios. Según Supabase, ese rol tiene `bypassrls` y elude RLS (*Row Level Security: Bypassing RLS*). Usarlo sería una **alternativa excepcional** que exige justificación documentada y aprobación humana, porque toda la validación quedaría a cargo del código. Además, `auth.uid()` no identificaría al usuario final salvo que se pase su token. **PENDIENTE DE APROBACIÓN HUMANA (P11).**
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
8. **`service_role` y roles operativos internos:** sin `EXECUTE` sobre las RPC de negocio salvo una necesidad operativa justificada y aprobada (sección 6, P11).

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
| P11 | Grants de `service_role` y roles internos (T16, sección 17.3) |
| P12, P15 | Contrato y ubicación de la idempotencia (T10–T12) |
| P13 | Aislamiento, bloqueos y reintentos (T12) |
| P14 | Sobrecargas (T16) |
| P16 | Contrato de errores (T15) |
| P17 | Auditoría de operaciones exitosas |

Si el dueño acota la validación a un subconjunto de operaciones, solo hacen falta las decisiones que ese subconjunto requiera. **P18 no es requisito previo:** es una decisión futura separada (sección 14). Esa aprobación **no** autoriza producción.

**Paso 2 — Implementación exclusivamente local o en staging.** Una vez resueltas las P2–P17 necesarias (P2–P7 ya lo están; quedan P8–P17) para el alcance elegido, se permiten migraciones, roles, schemas y grants sólo en entornos aislados (§10). Nada de `supabase db push`, `supabase migration up` ni comandos contra producción (`AGENTS.md` §5).

**Paso 3 — Pruebas.** Toda la matriz de la sección 16 y las verificaciones de la sección 17, con evidencia citada y auditoría independiente (`AGENTS.md` §2).

**Paso 4 — Segunda aceptación humana antes de producción.** El dueño acepta los resultados; recién entonces la ADR pasa a `aprobada` para producción.

**Producción permanece bloqueada.** El estado intermedio no equivale a aceptación productiva ni permite omitir decisiones pendientes.

---

## 16. Matriz de pruebas obligatorias

Base: `BLUEPRINT.md` §12, con pgTAP en `supabase/tests/` ejecutado por `supabase test db` en un entorno aislado, más pruebas HTTP contra la Data API local y un arnés concurrente. Su implementación depende de resolver las decisiones P8–P17 necesarias de la sección 15, paso 1 (P2–P7 ya están resueltas).

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
| P11 | Uso excepcional de `service_role` y de roles operativos internos | 6, 12 |
| P12 | Contrato de idempotencia I1–I8 | 10 |
| P13 | Aislamiento, orden de bloqueos, restricciones de respaldo y política de reintentos | 11 |
| P14 | Política de sobrecargas | 12 |
| P15 | Interpretación de `idempotency_key` en §7.6:171 (contenido aprobado vs. nombre de columna) | 3.2 |
| P16 | Contrato de errores | 13 |
| P17 | Mecanismo de auditoría de operaciones exitosas | 14 |
| P18 | Registro de intentos rechazados (**decisión futura separada**) | 14 |

**P8–P17 continúan pendientes. P18 continúa como decisión futura separada y no es requisito previo.**

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

---

## 19. Consecuencias sobre `BLUEPRINT.md`

La alineación documental aplica estos cambios:

- **D:** Blueprint §10 define la fachada expuesta `SECURITY INVOKER`, la implementación privada/no expuesta `SECURITY DEFINER` y la implementación privada como frontera real de seguridad; §12 prueba esa cadena; §15 registra el estado intermedio.
- **A, B y C:** A queda descartada, B reservada para lógica externa y C no elegida.
- **Gobernanza:** `docs/decisions/README.md` incorpora `APROBADA PARA VALIDACIÓN CONTROLADA`; las migraciones dependientes de ADR-001 quedan habilitadas sólo local/staging.
- **Modelo de datos y decisiones técnicas:** P8–P17 siguen pendientes; P18 permanece separada. P2–P4 fijan los esquemas `public`/`privado`, el rol `propietario_rpc` y el ownership/RLS sin `FORCE` global. P5–P7 fijan un perfil 1:1 con `auth.users`, una sola empresa y un único rol por usuario, sin membresías. `auditoria`, `idempotency_key` y restricciones no quedan aprobadas por P1/P19/P20.
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
