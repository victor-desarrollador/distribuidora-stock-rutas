# ADR-010 — Intenciones persistidas para recuperar operaciones con resultado desconocido (C-mínima)

**Fecha:** 06/11/2026
**Estado:** **APROBADA** — aprobación **normativa** por decisión humana del 06/11/2026 (§0.2). **No autoriza implementación**: la implementación requiere una autorización humana posterior, después del cierre de T3-01, y una aceptación técnica propia (§0.2).
**Versión:** 1.0
**Autor:** Claude Code (implementador; **no aprueba**). **Aprobó:** el responsable del proyecto (decisión humana del 06/11/2026).
**Relación:** **extiende**, sin modificarlos, P12-stock y P13-stock de [ADR-001](001-rpc-privilegiadas.md) §18.3 y precisa la aplicación práctica de `BLUEPRINT.md` §7.9.1 y §7.9.6 (operaciones e idempotencia) para el dominio **stock**. Usa la representación de cantidades de [ADR-005](005-fiambres-por-peso-gramos.md). Se rige por el procedimiento forward-only de [ADR-009](009-migraciones-hacia-adelante-y-rollbacks.md).
**No modifica:** ADR-005, ADR-007, ADR-009, las migraciones, las RPC `registrar_ingreso`, `mover_a_cuarentena`, `registrar_merma` ni las seis RPC de jornadas, los permisos vigentes, RLS, roles técnicos, el preflight T3-01 ni ningún test. **Con la aprobación** se registraron, de forma mínima: la excepción a P15 y la entidad `intenciones_operacion` en `BLUEPRINT.md` (v2.6, §7.9.1 y §8) y una nota de remisión en ADR-001 §18.3 (§0.2).
**Numeración:** 010 (**confirmada** por la decisión humana del 06/11/2026). El número 008 **no** está libre: ADR-009 lo cita como una propuesta de rollback (`ADR-008`, no aprobada, fuera del repositorio).

> **Alcance de la aprobación.** Esta ADR está **APROBADA como norma** (contrato, valores y excepción a P15). La aprobación es **exclusivamente normativa**: **no autoriza** implementar ni ejecutar tablas, migraciones, SQL, RPC, políticas RLS, grants, cambios del preflight ni cambios de frontend, ni staging ni producción. Nada de lo que describe existe todavía en el repositorio ni en ninguna base: donde el texto dice «la función hace…» o «la tabla tiene…» describe el **contrato aprobado** que una implementación futura deberá cumplir. La implementación se hará en una tarea propia, autorizada expresamente, **después del cierre de T3-01**, y quedará sujeta a pruebas, security review, auditoría independiente sobre un hash y **aceptación técnica humana** (§0.2). Un agente no puede ampliar esta aprobación.

**Historial**

| Versión | Fecha | Cambio |
|---|---|---|
| 0.1 | 06/11/2026 | Primera redacción, a partir del análisis D-IDEM (diagnóstico, alternativas y refinamiento de C1) realizado fuera del repositorio. |
| 0.2 | 06/11/2026 | Corrige los hallazgos del dictamen de Codex «APTA CON CORRECCIONES»: (1) el vencimiento es un límite de **admisión** comprobado con `clock_timestamp()` bajo `FOR UPDATE`; (2) FK compuesta `(empresa_id, operacion_id, tipo, actor_id)`; (3) la intención se reconoce como **segunda representación durable** de la `idempotency_key` y se propone una **excepción a P15**, sin afirmar compatibilidad plena; (4) validación exacta y reconstrucción del payload con `jsonb_build_object`; (6) impacto cuantificado sobre T3-01 (40→48, 20→24, 11→12, 33→36/37); (7) decisiones abiertas con valores **propuestos, no aprobados**; (8) pruebas separadas en premisas previas a la aprobación y pruebas posteriores a la implementación. La retención recomendada pasa de «purga perezosa» a «indefinida» (§5.13). Se conservan sin cambios de fondo: orden de locks intención → stock, transición atómica a `confirmada`, lista cerrada de rechazos, relanzamiento de errores de identidad y transitorios, prohibición de `WHEN OTHERS` y reutilización de las RPC de stock. |
| 0.3 | 06/11/2026 | (PROPUESTA) Incorpora los resultados del laboratorio de premisas PR-01 a PR-13 (13 PASS, 0 FAIL, 0 no concluyentes; evidencia externa, §10.A) y sus correcciones C-1 a C-8 (§0.1): (C-1) serialización obligatoria de `crear` con `pg_advisory_xact_lock` por empresa y actor antes de contar; (C-2) composición correcta del inventario `SECURITY DEFINER` (20 privadas hoy, 24 con la propuesta; `public.rls_auto_enable()` no integra la cifra); (C-3) inventario completo del cambio del preflight y **alternativa A propuesta** (sin `SELECT` directo de `authenticated`, con excepción exclusiva de la tabla nueva); (C-4) identidad solo por `privado.usuario_actual()`; (C-5 a C-8) contratos precisos de números JSON, `jsonb`, Unicode y respuestas HTTP. Se mantienen todos los contratos críticos de v0.2. **Sigue PROPUESTA — NO APROBADA.** |
| **1.0** | 06/11/2026 | **APROBADA (normativa)** por decisión humana del 06/11/2026 con el paquete completo de §0.2. Precisiones documentales señaladas por Codex: `WITH CHECK` explícito de la política de `UPDATE`, sin impedir la transición a estados terminales (§5.10), y límite de payload `octet_length(p_payload::text) <= 4096` (§5.4). §5.13 y §12 pasan de «propuesto» a «aprobado»; se agregan las obligaciones de implementación (§0.3). Se registran la excepción P15 y la entidad en `BLUEPRINT.md` v2.6 y una remisión en ADR-001 §18.3. Sin implementación. |

---

## 0.2 Registro de la aprobación (06/11/2026)

**Decisión humana.** El responsable del proyecto aprobó ADR-010 el 06/11/2026 con este paquete completo, sin modificaciones:

| # | Decisión aprobada | Id | Secciones |
|---|---|---|---|
| 1 | Arquitectura **C-mínima** | D-IDEM-1 | 3, 4, 5 |
| 2 | **Excepción acotada a P15** de ADR-001 (texto de §7.1) | D-IDEM-2 | 7.1 |
| 3 | **Alternativa A:** sin `SELECT` ni ningún otro acceso directo de `authenticated` a `intenciones_operacion` | D-IDEM-15 | 5.10, 8.2.1 f |
| 4 | Rechazos definitivos de negocio como estado `rechazada` con **HTTP 200**, **exclusivamente** para la lista cerrada de §5.7; `PT401`/`PT403`/`42501` siempre como error | D-IDEM-10 | 5.6, 5.7, 5.12 |
| 5 | Vencimiento de **24 horas** como límite de **admisión** | D-IDEM-5a | 5.6, 5.13 |
| 6 | Retención **indefinida**, sin purga | D-IDEM-3 | 5.10, 5.13 |
| 7 | Máximo **20** intenciones pendientes vigentes por actor | D-IDEM-5b | 5.5.1, 5.13 |
| 8 | Máximo **120** creaciones por actor por hora | D-IDEM-5d | 5.5.1, 5.13 |
| 9 | Listado máximo de **100** filas; **7 días** por defecto; **30 días** como ventana máxima | D-IDEM-5c | 5.5, 5.13 |
| 10 | `motivo` máximo de **500** caracteres (vía de intenciones) | D-IDEM-11 | 5.4, 5.13 |
| 11 | Visibilidad **exclusiva del actor creador** | D-IDEM-12 | 5.9, 5.10 |
| 12 | Aceptación **temporal** del bypass por RPC directas de stock durante la Fase 1 | D-IDEM-8 | 6, 11 (R-2) |
| 13 | Implementación **después del cierre de T3-01** | D-IDEM-7 | 8 |
| 14 | Numeración **ADR-010** | D-IDEM-14 | encabezado |
| 15 | **B-01 permanece abierta** hasta completar la recuperación | D-IDEM-0 | 1.4 |
| 16 | Límite de payload de **4096 bytes**, medido con `octet_length(p_payload::text)` | D-IDEM-16 | 5.4 |

**Fuera de la aprobación:** D-IDEM-13 (Fase 2 técnica: revocar `EXECUTE` directo de las RPC de stock) sigue como decisión futura; la variante de purga y la variante B quedan descartadas para esta versión; la extensión a ventas, cobros u otros dominios (§9.1) exige ADR propia.

**Aprobación normativa frente a aceptación técnica.**

| | Aprobación normativa (esta) | Aceptación técnica de la implementación (futura) |
|---|---|---|
| Qué fija | El contrato, los valores y la excepción a P15 | Que una implementación concreta cumple este contrato |
| Cuándo | 06/11/2026 | Después del cierre de T3-01, en una tarea autorizada |
| Requiere | Decisión humana (otorgada) | Autorización humana para implementar; rama propia y preámbulo (`AGENTS.md` §1.3); pruebas de §10.B en stack descartable; security review (`AGENTS.md` §2.4); auditoría independiente (Codex y OpenCode) sobre un hash; aprobación humana |
| Autoriza | Usar este texto como norma de diseño | Commit, merge y despliegue, cada uno con su autorización humana |
| Producción | No | Solo con aceptación humana final; rige además el estado de ADR-001 (**APROBADA PARA VALIDACIÓN CONTROLADA**) |

**Normas actualizadas con la aprobación (mínimas):** `BLUEPRINT.md` v2.6 (§7.9.1: excepción a P15; §8: entidad `intenciones_operacion`; §12: pruebas; §17: historial); ADR-001 §18.3 (nota de remisión a esta ADR, sin cambiar sus decisiones ni su estado); `docs/decisions/README.md`.

## 0.3 Obligaciones de implementación (pendientes; nada de esto existe todavía)

Toda implementación futura de esta ADR **debe** cumplir, como mínimo:

1. **Cuatro funciones privadas `SECURITY DEFINER`** en `privado`, propiedad de `propietario_rpc`, con `search_path = ''` y endurecimiento pg_temp, y **cuatro fachadas públicas `SECURITY INVOKER`** (`language sql`, owner `postgres`), `EXECUTE` solo para `authenticated`, sin sobrecargas (R-09, §5.5).
2. **Identidad solo por `privado.usuario_actual()`**; cero `auth.uid()` (R-10, R-12, §5.9).
3. **Orden de locks actor → intención → stock** (nivel 0 solo en `crear`; §5.8).
4. **Control concurrente de los límites por actor** con `pg_advisory_xact_lock` antes del replay y de los conteos, `READ COMMITTED` obligatorio (R-13, §5.5.1).
5. **Integridad transaccional** de la ejecución y la confirmación: la transición a `confirmada` es atómica con el efecto; rechazos solo de la lista cerrada; errores de identidad, autorización y transitorios relanzados; sin `WHEN OTHERS` ni SQL dinámico (§5.6, §5.7).
6. **FK compuesta** `(empresa_id, operacion_id, tipo, actor_id)` → `operaciones (empresa_id, id, tipo, actor_id)` (§5.2).
7. **Payload canónico validado y reconstruido en PostgreSQL**, `p_payload jsonb`, `octet_length(p_payload::text) <= 4096` (§5.4, R-11).
8. **Alternativa A** con la ACL exacta de §5.10 y la política de `UPDATE` con `WITH CHECK` explícito.
9. **Actualización integral del preflight T3-01** (§8.2.1) **sin debilitar las once tablas existentes**, incluida la excepción nominal de la tabla nueva y el **negativo N-COL** con `has_any_column_privilege(rol, 'public.intenciones_operacion', 'SELECT')` para `anon` y `authenticated`.
10. **Pruebas** de §10.B: pgTAP (estructura, ACL, políticas, funciones, preflight, identidad, `SECURITY DEFINER` real), **concurrencia** (CC-01 a CC-05, LM-05 a LM-07), **Vitest** (VT-01 a VT-07) y **Playwright** (PW-01 a PW-06), en stack descartable.
11. Sin almacenamiento del navegador; sin cambios en las RPC de stock ni de jornadas, en `operaciones` ni en `movimientos_stock`.

---

## 0.1 Incorporación de los resultados PR-01 a PR-13 (v0.3)

> **Fuente.** `../evidencias-entrega-b/d-idem-supabase/laboratorio-premisas/` (fuera del repositorio): `README.md`, `RESULTADOS_PR01_PR13.md`, `scripts/`, `logs/` y `MANIFIESTO.sha256` (74 archivos; `sha256sum -c` sin discrepancias al redactar v0.3). Stack Supabase completo y descartable `adr010-pr-lab` (PostgreSQL 17.11, PostgREST v16.4, GoTrue v2.197.0), creado con las 25 migraciones y el `seed.sql` idénticos a los del repositorio en el HEAD `358bb7c`. La copia del preflight usada como línea base es byte a byte la del repositorio (SHA-256 `e9d49e09…ed6b`). Es material **no normativo**: lo vinculante es el texto de esta ADR (aprobada el 06/11/2026).
>
> **Alcance de lo demostrado.** Las 13 premisas verifican **comportamientos de PostgreSQL y PostgREST** sobre los que descansa el diseño, usando las RPC de stock reales y funciones **de laboratorio**. **No equivalen a verificar una implementación `SECURITY DEFINER` completa** de esta ADR: el prototipo de `crear`/`ejecutar` (`lab_proto.sql`) usa funciones `SECURITY INVOKER` ejecutadas como `authenticated`, y los objetos de PR-13 solo reproducen la **forma** del contrato (owner, ACL, `proconfig`, políticas) para recontar el preflight. Los límites están en §10.A.1.

| Id | Corrección | Origen | Tratamiento en v0.3 | Secciones |
|---|---|---|---|---|
| **C-1** | Los topes por actor se exceden bajo concurrencia si `crear` «cuenta y luego inserta» | PR-11 / H-LM | Serialización obligatoria con `pg_advisory_xact_lock` por empresa y actor **antes** del replay y de los conteos; nivel 0 de bloqueo; análisis de deadlocks; pruebas LM-05 a LM-07. Los valores del tope siguen sin aprobar | 5.1, 5.5.1, 5.8, 5.13, 10.B, 12 |
| **C-2** | La composición de «20 `SECURITY DEFINER`» era inexacta | PR-13 | 20 funciones privadas en `privado` (19 implementaciones con fachada + `privado.empresa_gestion_actual()`); `public.rls_auto_enable()` no existe en el laboratorio y se trata aparte (O-4); +4 → 24 | 8.1 |
| **C-3** | El cambio del preflight no se reduce a cuatro cifras | PR-13 | Inventario completo: 8 listas de relaciones/nombres, manifiestos, conteos, `NOTICE`, hashes, ACL y pruebas negativas. **Alternativa A propuesta** con excepción exclusiva y verificable; brechas N12/N13 a cubrir con pgTAP | 5.10, 8 |
| **C-4** | Una función `SECURITY DEFINER` de `propietario_rpc` que llama `auth.uid()` falla (`permission denied for schema auth`) | PR-04 | Identidad solo por `privado.usuario_actual()`; validación de usuario, empresa, rol y actividad | 5.1, 5.5.1, 5.6, 5.9 |
| **C-5** | Enteros con exponente llegan normalizados por `jsonb` | PR-05 | Contrato numérico exacto, incluidos los errores previos a la función (`PGRST102`, `22003`) | 5.4 |
| **C-6** | Con `json` las claves duplicadas sobreviven | PR-06 | `p_payload` debe ser `jsonb` en la fachada y en la privada (R-11) | 5.1, 5.4 |
| **C-7** | No hay normalización Unicode | PR-10 | Documentado: NFC/NFD distintas; `22P05` y `PGRST102`; consecuencia para el replay | 5.4, 11 |
| **C-8** | Forma y estados HTTP reales de PostgREST | PR-04 | Tabla de mapeo SQLSTATE → HTTP observada; `RETURNS TABLE` → arreglo de un objeto | 5.12 |

**Contratos críticos que v0.3 conserva sin cambios de fondo:** payload canónico reconstruido y persistido (§5.4); FK compuesta `(empresa_id, operacion_id, tipo, actor_id)` (§5.2); idempotencia estable de `crear`, `ejecutar` y `cancelar`; atomicidad de la ejecución con la transición a `confirmada` (§5.6); orden de locks intención → stock, ahora precedido por el nivel 0 de `crear` (§5.8); rechazos de negocio con lista cerrada y sin `WHEN OTHERS` (§5.7); errores de autorización y transitorios relanzados (R-03); vencimiento como límite de admisión comprobado con `clock_timestamp()` (§5.6 paso 5); ningún almacenamiento del navegador (R-07); ninguna RPC vigente modificada (R-04); excepción a P15 **propuesta y no aprobada** (§7.1).

---

## 0. Tratamiento de los hallazgos del dictamen de Codex

> **Nota de trazabilidad.** El texto del dictamen «APTA CON CORRECCIONES» **no está en el repositorio ni en `~/Documentos`**; los hallazgos se tomaron del pedido de corrección (ocho puntos). Si el dictamen contiene un hallazgo adicional, debe cotejarse contra esta tabla.

| # | Hallazgo | Tratamiento en v0.2 | Sección |
|---|---|---|---|
| 1 | Vencimiento ambiguo: «nunca se ejecutará» tras vencer | El vencimiento es el **límite para admitir nuevas ejecuciones**. Tras `FOR UPDATE` se compara con `clock_timestamp()`; una ejecución admitida antes puede completar después. Se eliminaron las afirmaciones incompatibles | 5.3, 5.6, 5.8, 5.13, 6 |
| 2 | Referencia a `operaciones` incompleta | FK compuesta `(empresa_id, operacion_id, tipo, actor_id)` → `operaciones (empresa_id, id, tipo, actor_id)`. **La UNIQUE requerida ya existe** (`operaciones_referencia_apertura`) | 5.2, 5.11 |
| 3 | Compatibilidad con P15 afirmada de más | Se reconoce la segunda representación durable de la clave; **excepción propuesta a P15**, con justificación y cambios normativos; compatibilidad **condicionada a aprobación** | 7, 7.1 |
| 4 | Payload sin validación estricta | Conjunto exacto de campos, tipos PostgreSQL, rangos, normalización y **reconstrucción con `jsonb_build_object`**; nunca se almacena `p_payload` | 5.4 |
| 5 | Concurrencia y errores | Se conserva sin cambios de fondo | 5.6–5.8 |
| 6 | Impacto sobre T3-01 | Inventarios cuantificados con líneas del preflight | 8 |
| 7 | Decisiones abiertas | Tabla compacta con valores **propuestos, no aprobados** | 12 |
| 8 | Pruebas | Separadas: premisas previas a la aprobación / posteriores a la implementación | 10 |

---

## 1. Contexto y problema

### 1.1 Qué garantiza hoy el sistema

La base ya garantiza **a lo sumo una ejecución por clave de idempotencia**:

- `public.operaciones` tiene `UNIQUE (empresa_id, actor_id, idempotency_key)` (`20261025021032_stock_operaciones_ingreso.sql:55`) y una `huella` SHA-256 del payload (`:52, :59`).
- Las tres RPC de stock reservan la clave con `INSERT … ON CONFLICT DO NOTHING` **en la misma transacción que el efecto** (`…021032:341`; `…033454:259, 444`). Misma clave y misma huella → devuelven el `operaciones.id` original sin efectos nuevos; misma clave y otra huella u otro tipo → `PT409 stock_conflicto_idempotencia`; un rechazo de negocio revierte todo y **no deja reserva** (ADR-001 §18.3, P12-stock).
- `operaciones` solo contiene operaciones **confirmadas** y no guarda cantidades ni importes (Blueprint §7.9.1). No tiene columna de resultado: el resultado estable del replay es `operaciones.id`.

### 1.2 El problema

La clave de idempotencia la **genera el cliente** y hoy vive solo en memoria. Si la operación se confirma y la respuesta se pierde, y el usuario **recarga, cierra la pestaña o entra desde otro dispositivo**:

1. la clave original se pierde;
2. repetir "los mismos datos" genera **otra** clave;
3. la base la ejecuta como una operación nueva → **se duplica el movimiento de stock**.

El servidor aplica correctamente su contrato. Falta que **el identificador del intento sobreviva al cliente**. Tampoco puede resolverse por heurística (producto, cantidad, motivo, horario): **dos operaciones idénticas pueden ser legítimas**.

### 1.3 Imposibilidad sin un registro durable previo

Si el servidor no registra una intención antes de ejecutar y el cliente no conserva el identificador, desde la base **no existe forma** de saber que un reintento es "el mismo" que un intento que no dejó rastro (nunca llegó, fue revertido o sigue en curso). Ninguna regla de interfaz lo reemplaza. Las restricciones vigentes de este proyecto excluyen resolverlo con `localStorage`, `sessionStorage` o IndexedDB (`AGENTS.md` §5; decisión del dueño del proyecto para D-IDEM).

### 1.4 Estado de B-01

B-01 (pantalla real de stock) cuenta con mitigaciones sin persistencia (mensaje que no promete idempotencia tras recargar, aviso `beforeunload`). Reducen el riesgo; **no lo eliminan**. Esta ADR fija la solución de fondo (aprobada el 06/11/2026); no la implementa. **B-01 permanece abierta** hasta completar la recuperación (D-IDEM-0).

---

## 2. Alcance y no-alcance

**Dentro del alcance aprobado (Fase 1):** los tres comandos de stock existentes (`ingreso`, `a_cuarentena`, `merma`) ejecutados a través de intenciones persistidas.

**Fuera del alcance (no se diseña ni se autoriza):**
- Modificar `registrar_ingreso`, `mover_a_cuarentena`, `registrar_merma` o las RPC de jornadas.
- Revocar `EXECUTE` directo de esas RPC (Fase 2, ver §9.2).
- Ventas, cobros, retiros, rendiciones, conteos o cualquier funcionalidad de Fase 2 del producto (Blueprint §5).
- Servicios externos, colas, workers, `pg_cron` u otras extensiones, roles técnicos nuevos, `localStorage`, `sessionStorage`, IndexedDB.
- Cambios al Blueprint (se listan en §12 como consecuencia a decidir).

---

## 3. Alternativas analizadas y razones de descarte

| Alt. | Descripción | Resultado | Razón |
|---|---|---|---|
| **A0** | Reutilizar `operaciones` y RLS actuales: panel "Mis últimas operaciones" | **Descartada como solución** (válida como mitigación) | Solo muestra lo confirmado; no distingue "nunca llegó" de "rechazada" ni "en curso"; no impide el duplicado. El vendedor no puede leer `operaciones` |
| **B0** | RPC `consultar_operacion(clave)` | **Descartada** | La clave ya se perdió tras recargar. Para dueño/encargado ya se puede consultar por clave con RLS, y reintentar con la misma clave ya devuelve el replay |
| **D1** | Clave determinística derivada del contenido o con contador | **Descartada** | Colapsa operaciones legítimas idénticas; con contador, tras un éxito perdido el reintento obtiene la clave del número siguiente y duplica |
| **D2** | Reutilizar un ticket abierto por actor y tipo | **Descartada** | Con dos dispositivos del mismo actor y datos idénticos, se pierde una operación legítima |
| **A** | Ticket UUID server-side **sin** payload | **Descartada (alternativa de menor costo)** | Recupera el identificador, pero no permite mostrar ni reejecutar lo intentado, mezcla "nunca llegó / rechazada / en curso" en un único estado `sin_efecto`, y el servidor **no puede cerrar un intento viejo**: la RPC de negocio acepta cualquier `uuid` y no consulta tickets, por lo que una solicitud retrasada puede ejecutarse después |
| **B** | Ticket con payload **informativo** | **Descartada (dominada)** | Costo de almacenamiento de C sin sus garantías: el cliente reenvía su propio payload a la RPC y puede diferir del guardado |
| **C3** | Estado `pendiente/confirmada` dentro de `operaciones` | **Descartada** | Contradice P12-stock ("un rechazo de negocio no deja reserva"; sin columna de resultado) y la reserva atómica con el efecto; obliga a reescribir las 9 RPC con operaciones; altera la tabla de auditoría (P17) |
| **C-mínima** | Intención persistida con payload canónico y ejecución controlada por el servidor, sobre las RPC existentes sin modificarlas | **Aprobada (06/11/2026)** | Es la única que da estados conocidos por el servidor, payload inmutable y serialización de `ejecutar` y `cancelar` sin tocar los contratos aprobados en la Fase 1 |

**Fallback explícito.** Si el humano prioriza el costo, la alternativa **A** es la de menor complejidad, con la falla residual documentada en §11 (R-6).

---

## 4. Decisión aprobada (resumen)

1. Cada comando crítico de stock se ejecuta en **dos pasos persistidos en PostgreSQL**: **crear** una intención (con su payload canónico) y **ejecutarla**.
2. El `id` de la intención **es** la `idempotency_key` de la RPC de negocio. Lo genera el cliente (`crypto.randomUUID()`) para que `crear` sea idempotente dentro de la misma página; tras recargar o cambiar de dispositivo, el servidor devuelve lo pendiente del actor.
3. Las RPC de stock **no cambian**: una función privada de ejecución las invoca con una instrucción estática por tipo.
4. Estados persistidos: `pendiente`, `confirmada`, `rechazada`, `cancelada`. `vencida` se deriva del reloj y marca el **límite de admisión de nuevas ejecuciones** (§5.13), no un corte de las ya admitidas.
5. Todo acceso es por RPC; ninguna lectura ni escritura directa de `authenticated`; solo el actor creador ve su intención.
6. Retención **indefinida** en la primera versión (consistente con P12 y sin privilegio `DELETE`); sin purga (variante descartada, §5.13). Sin cron ni workers.

---

## 5. Contrato técnico aprobado (no implementado)

> Esta sección es el **contrato aprobado** (06/11/2026). **No está implementado.** Los bloques SQL son especificaciones ilustrativas, **no migraciones** y no deben ejecutarse. Nombres en español `snake_case` (`AGENTS.md` §7).

### 5.1 Reglas obligatorias de implementación (cuando se autorice su implementación)

| Id | Regla |
|---|---|
| R-01 | **Sin SQL dinámico.** El despachador usa un `CASE` estático con una rama y una llamada nombrada por `tipo`. Prohibidos `EXECUTE`, `format()` para armar sentencias y nombres de función derivados de datos |
| R-02 | **Sin `WHEN OTHERS`.** Solo se capturan condiciones **nombradas por SQLSTATE** y, dentro del manejador, solo los códigos de la lista cerrada de §5.7. Todo lo demás se **relanza** (`RAISE;`) |
| R-03 | **Errores de autenticación y autorización nunca se convierten en rechazos de negocio HTTP 200.** `PT401`, `PT403` y todo `42501` se propagan como error |
| R-04 | **Ninguna RPC de stock ni de jornadas se modifica** en la Fase 1 |
| R-05 | **Ningún permiso vigente cambia.** `service_role` sigue denegado (P11); sin roles técnicos nuevos (P3, D-2) |
| R-06 | **Sin acceso directo del frontend** a `intenciones_operacion`, `operaciones`, `movimientos_stock` para escribir. La lectura de la intención es solo por RPC |
| R-07 | **Sin `localStorage`, `sessionStorage` ni IndexedDB** para ninguna parte del mecanismo |
| R-08 | **Conjunto cerrado de tipos.** Agregar un tipo exige migración y ADR; nunca datos |
| R-09 | `SECURITY DEFINER` con `set search_path = ''`, propietaria `propietario_rpc`, endurecimiento pg_temp igual al de A1/A3/B1, fachada `SECURITY INVOKER`, sin sobrecargas (P14) |
| R-10 | Empresa y actor **se derivan de `perfiles`** vía `privado.usuario_actual()`; nunca del payload, del cuerpo del pedido ni de `user_metadata` |
| R-11 | **`p_payload` se declara `jsonb`**, en la fachada y en la privada; **nunca `json`** (con `json` las claves duplicadas sobreviven, PR-06) (C-6) |
| R-12 | **Cero llamadas a `auth.uid()`** (ni a ningún objeto del esquema `auth`) en el cuerpo de las funciones nuevas y en sus políticas: `propietario_rpc` no tiene `USAGE` sobre `auth` y la llamada falla con `42501` (PR-04). La identidad se obtiene solo con `privado.usuario_actual()` (C-4, §5.9) |
| R-13 | **`crear` serializa por actor:** toma `pg_catalog.pg_advisory_xact_lock` sobre la clave de empresa y actor **antes** de buscar el id (replay) y de contar pendientes o creaciones por hora; la función es `VOLATILE` para que cada sentencia posterior al lock tome una instantánea nueva en `READ COMMITTED`. Como las RPC de débito (`20261025033454…:205-207`), `crear` **falla cerrado** con `PT500` si `transaction_isolation` no es `read committed`: con `REPEATABLE READ` o `SERIALIZABLE` la instantánea sería la del inicio y el conteo posterior al lock quedaría atrasado (C-1, §5.5.1) |

### 5.2 Modelo de datos

```sql
-- ILUSTRATIVO. No es una migración.
create table public.intenciones_operacion (
  id             uuid        not null,            -- = idempotency_key de la RPC de negocio (ver §7.1)
  empresa_id     uuid        not null references public.empresas (id) on delete restrict,
  actor_id       uuid        not null,
  tipo           text        not null,
  payload        jsonb       not null,            -- reconstruido por el servidor (§5.4); nunca el p_payload del cliente
  estado         text        not null default 'pendiente',
  operacion_id   uuid,                            -- solo si 'confirmada'
  codigo_rechazo text,                            -- solo si 'rechazada' (código stock_*)
  creado_en      timestamptz not null default clock_timestamp(),
  vence_en       timestamptz not null,            -- fijado por el servidor: clock_timestamp() + plazo
  resuelto_en    timestamptz,
  primary key (empresa_id, actor_id, id),         -- espacio de ids por actor: sin colisión ni fuga
  foreign key (empresa_id, actor_id)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  -- Referencia compuesta (hallazgo 2): la operación enlazada debe ser de la misma empresa,
  -- del mismo actor y del MISMO tipo que la intención. MATCH SIMPLE (por defecto): mientras
  -- la intención está 'pendiente', operacion_id es NULL y la FK no se evalúa.
  foreign key (empresa_id, operacion_id, tipo, actor_id)
    references public.operaciones (empresa_id, id, tipo, actor_id) on delete restrict,
  constraint intenciones_tipo_valido    check (tipo in ('ingreso','a_cuarentena','merma')),
  constraint intenciones_estado_valido  check (estado in ('pendiente','confirmada','rechazada','cancelada')),
  constraint intenciones_payload_objeto check (jsonb_typeof(payload) = 'object'),
  constraint intenciones_vence_posterior check (vence_en > creado_en),
  constraint intenciones_coherencia check (
       (estado = 'pendiente'  and operacion_id is null     and codigo_rechazo is null     and resuelto_en is null)
    or (estado = 'confirmada' and operacion_id is not null and codigo_rechazo is null     and resuelto_en is not null)
    or (estado = 'rechazada'  and operacion_id is null     and codigo_rechazo is not null and resuelto_en is not null)
    or (estado = 'cancelada'  and operacion_id is null     and codigo_rechazo is null     and resuelto_en is not null))
);
create index intenciones_actor_idx on public.intenciones_operacion (empresa_id, actor_id, creado_en desc);
```

**Sobre la FK compuesta (hallazgo 2).**
- Requiere en `operaciones` una `UNIQUE (empresa_id, id, tipo, actor_id)`. **Esa restricción ya existe**: `operaciones_referencia_apertura`, creada en `supabase/migrations/20261030120000_jornadas_esquema.sql:447` e inventariada en `supabase/tests/stock_ingreso.test.sql:167`. Ya la usa una FK de jornadas (`:483`) con exactamente ese patrón. **Por lo tanto esta ADR no agrega ni modifica ninguna restricción de `operaciones`**, y el inventario de restricciones de esa tabla (`stock_ingreso.test.sql:155-170`) no cambia.
- Se descartó la UNIQUE de cinco columnas `operaciones_referencia_unica (empresa_id, id, tipo, actor_id, jornada_id)`: los tres tipos de stock tienen `jornada_id` nulo (`operaciones_jornada_por_tipo`) y una FK `MATCH SIMPLE` con una columna nula no se evaluaría.
- **Límite de la FK:** no puede expresar que `operaciones.idempotency_key = intenciones_operacion.id`, porque la clave no integra esa UNIQUE y no se propone modificar `operaciones`. Esa igualdad se garantiza porque `confirmada` solo la escribe `ejecutar`, que obtiene `operacion_id` de la RPC invocada con `p_idempotency_key = id`; se verifica con una consulta de invariante y una prueba (ver §10.B).

Notas:
- No es una tabla de libro mayor ni de auditoría. La auditoría de operaciones exitosas sigue siendo `operaciones` + `movimientos_stock` (P17).
- No hay tabla de estados ni de transiciones: son valores de una columna con `CHECK`.
- `creado_en` y `vence_en` usan `clock_timestamp()` y no `now()`: `now()` es el inicio de la transacción y no refleja una espera por bloqueos (ver §5.13).

### 5.3 Estados y transiciones atómicas

```
                 ejecutar (éxito)
  pendiente  ───────────────────────►  confirmada   (terminal)
      │       ejecutar (rechazo de negocio, lista cerrada §5.7)
      ├───────────────────────────────►  rechazada   (terminal)
      │       cancelar
      └───────────────────────────────►  cancelada   (terminal)

  vencida  = pendiente AND clock_timestamp() >= vence_en     (derivado; no se escribe)
```

- Los estados terminales **no cambian**. Se impone con RLS (`UPDATE … USING (estado = 'pendiente')`) y con las funciones, no con triggers.
- Cada transición ocurre **dentro de la transacción que la decide**, bajo `SELECT … FOR UPDATE` de la fila (§5.8). **La transición a `confirmada` es atómica con el efecto**: el `UPDATE` de la intención y la creación de `operaciones` + `movimientos_stock` confirman juntos o se revierten juntos. No existe un estado persistido "en curso": una ejecución es una sola transacción; si falla o el servidor cae, se revierte y la intención sigue `pendiente`.
- Una transición **no se escribe** si el error que la interrumpe no pertenece a la lista cerrada de §5.7.
- `vencida` **no es un estado terminal ni una transición**: es una lectura del reloj sobre una intención `pendiente` y cambia sola con el tiempo. Una intención `pendiente` con una ejecución ya admitida y todavía no confirmada seguirá apareciendo como `pendiente` (la transacción no es visible hasta confirmar).

**Qué es hecho y qué es inferencia**

| Estado | Carácter |
|---|---|
| `pendiente`, `confirmada`, `cancelada` | Hecho persistido |
| `rechazada` | Hecho persistido, **solo porque** la ejecución lo registra (§5.6) |
| `vencida` | Derivado de una regla determinista sobre el reloj; es una lectura instantánea |
| "en curso" | Hecho instantáneo y no persistido (visible solo para quien sonde el bloqueo); **no se expone** en la Fase 1 y no es necesario para la corrección |
| "resultado desconocido" | Estado **del cliente**, no del servidor. Desaparece al consultar: `listar`/`ejecutar` devuelven uno de los estados anteriores |

La única inferencia remanente es una **solicitud aún en tránsito por la red**: el servidor la ve como `pendiente`; al llegar ejecutará **esa misma intención una sola vez**, o será rechazada si ya fue cancelada, si ya venció (no se admiten nuevas ejecuciones, §5.13) o si ya fue resuelta (devuelve el resultado almacenado).

### 5.4 Payload canónico: validación exacta y reconstrucción (hallazgo 4)

**Regla central.** `p_payload` es **entrada no confiable**. Nunca se almacena tal como llega. `crear_intencion_operacion` (1) lo valida campo por campo, (2) extrae cada valor a una **variable con tipo PostgreSQL**, y (3) **reconstruye** el documento con `jsonb_build_object(...)` a partir de esas variables. Solo el documento reconstruido se almacena, se compara (replay) y se ejecuta.

La validación va **en línea** dentro de la función privada de `crear`, sin función auxiliar: un auxiliar `SECURITY DEFINER` ampliaría el inventario más allá de 4 privadas + 4 fachadas (24 y 48; ver §8). Si la implementación exigiera un auxiliar, el inventario cambia y debe decidirse expresamente.

**Conjunto exacto de campos por tipo** (la comparación es de conjuntos, no de contenido; ni sobran ni faltan claves):

| `tipo` | Claves exactas |
|---|---|
| `ingreso` | `producto_id`, `cantidad`, `motivo` |
| `a_cuarentena` | `producto_id`, `ubicacion_origen_id`, `cantidad`, `motivo` |
| `merma` | `producto_id`, `ubicacion_origen_id`, `cantidad`, `motivo_codigo`, `motivo` |

**Tipos PostgreSQL, rangos y normalización**

| Campo | Condición sobre el JSON | Variable | Notas |
|---|---|---|---|
| (documento) | `p_payload IS NOT NULL` y `jsonb_typeof(p_payload) = 'object'`; **`octet_length(p_payload::text) <= 4096`** (aprobado: 4096 bytes del texto UTF-8 de la representación `jsonb` recibida, comprobado **antes** de extraer campos) | — | Arreglo, cadena, número, `null` o documento de más de 4096 bytes → `PT400 intencion_payload_invalido` |
| claves | `ARRAY(SELECT k FROM jsonb_object_keys(p_payload) k ORDER BY k)` igual al arreglo esperado del tipo | — | Elimina claves extra y faltantes. Las claves duplicadas del texto JSON colapsan al parsear (última gana); la reconstrucción hace irrelevante cuál sobrevive |
| `producto_id`, `ubicacion_origen_id` | `jsonb_typeof = 'string'` **y** texto que cumple `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$` (minúsculas, sin llaves) | `uuid` | Se castea después de validar el formato: nunca un cast que pueda fallar con un error distinto |
| `cantidad` | `jsonb_typeof = 'number'` **y** `(p_payload->>'cantidad') ~ '^[1-9][0-9]{0,9}$'`; luego `::bigint BETWEEN 1 AND 2147483647` | `integer` | Entero estricto en **unidad mínima** (unidades enteras o **gramos**, ADR-005). Rechaza decimales con escala (`1.0`, `1.5`), signos, cadenas, booleanos y valores sobre el rango de `integer`. La regla se aplica sobre el texto **normalizado por `jsonb`**: ver «Contrato numérico verificado» (C-5, PR-05) |
| `motivo` | `jsonb_typeof IN ('string','null')`; la clave debe estar presente | `text` | Si es cadena: `nullif(btrim(valor), '')`; `char_length <= 500` (aprobado, D-IDEM-11); sin normalizar mayúsculas. Cadena vacía o de blancos → `NULL`. La obligatoriedad (cuarentena; merma con `otro`) la sigue decidiendo la RPC de negocio |
| `motivo_codigo` | `jsonb_typeof = 'string'`; `valor = btrim(valor)`; `char_length BETWEEN 1 AND 40` | `text` | La pertenencia al catálogo de Blueprint §7.7 la valida la RPC de negocio (un valor inválido produce `rechazada`); así el catálogo no se duplica en dos lugares |

**Qué NO valida `crear` (a propósito):** existencia, pertenencia a la empresa o estado activo de producto y ubicación; stock disponible; coherencia producto/unidad; obligatoriedad del motivo. Son reglas de negocio que decide la RPC al ejecutar y que, si fallan, dejan la intención en `rechazada`. Así no se duplican reglas y `crear` no puede usarse para sondear datos de otras empresas.

**Reconstrucción** (ilustrativo; las variables ya están validadas y tipadas):

```sql
v_payload := case p_tipo
  when 'ingreso' then jsonb_build_object(
      'producto_id', v_producto, 'cantidad', v_cantidad, 'motivo', v_motivo)
  when 'a_cuarentena' then jsonb_build_object(
      'producto_id', v_producto, 'ubicacion_origen_id', v_origen,
      'cantidad', v_cantidad, 'motivo', v_motivo)
  when 'merma' then jsonb_build_object(
      'producto_id', v_producto, 'ubicacion_origen_id', v_origen,
      'cantidad', v_cantidad, 'motivo_codigo', v_motivo_codigo, 'motivo', v_motivo)
end;
```

`jsonb_build_object` con un `text` nulo produce JSON `null` (la clave siempre está). `ejecutar` lee el documento almacenado con `->>` y casts explícitos, sin SQL dinámico.

**Garantías de esta construcción**
1. El `payload` almacenado tiene siempre el conjunto exacto de claves del tipo, con los tipos y la forma canónica indicados.
2. La comparación del replay de `crear` (mismo id) es `tipo = tipo AND payload_reconstruido = payload_almacenado`: dos pedidos equivalentes tras normalizar son iguales; dos distintos producen `PT409 intencion_conflicto`.
3. Lo que se ejecuta es siempre lo almacenado; el cliente no vuelve a enviar datos en `ejecutar`.
4. El payload no contiene `empresa_id`, `actor_id` ni `idempotency_key`.

**Contrato numérico verificado (C-5, PR-05: 26/26 casos, por SQL y por HTTP con cuerpo crudo, sin desviaciones).** `jsonb` almacena los números como `numeric` y **normaliza** su texto antes de que la función lo vea; la regla de `cantidad` se evalúa sobre ese texto normalizado:

| Literal JSON recibido | Lo que ve la función (`->>`) | Resultado |
|---|---|---|
| `1`, `2147483647` | `1`, `2147483647` | Aceptado |
| `1e3`, `1E+3` | `1000` | **Aceptado como `1000`** |
| `5e0`, `0.5e1` | `5` | **Aceptado como `5`** |
| `1.0`, `1.000` | `1.0`, `1.000` (la escala se conserva) | Rechazado `PT400 intencion_payload_invalido` |
| `10E-1` | `1.0` | Rechazado `PT400` |
| `1e10` | 11 dígitos | Rechazado `PT400` |
| `1.5`, `-1`, `0`, `-0`, `2147483648`, `"5"`, `true`, `null` | — | Rechazado `PT400` |
| `0001`, `01`, `+1` | — (no son JSON válido) | **Falla antes de la función:** HTTP 400 `PGRST102` |
| `1e999999999` | — | **Falla antes de la función:** HTTP 400 `22003` |

Regla resultante: se acepta **cualquier literal JSON cuyo valor sea un entero de 1 a 2147483647 sin escala decimal**, cualquiera sea su notación; se rechaza todo literal con escala decimal, aunque su valor sea entero. El valor reconstruido y almacenado es siempre el entero (`1000`, `5`). Los errores `PGRST102` y `22003` no son `PTxyz` de esta ADR: el cliente los trata como error genérico de datos, **nunca** como rechazo de negocio ni como motivo de reintento.

**`jsonb` obligatorio y claves duplicadas (C-6, PR-06).** Con el parámetro `jsonb`, una clave duplicada en el cuerpo (incluso escrita con un escape Unicode) colapsa y **gana la última**; `"cantidad "` (con espacio) es otra clave y la validación de conjunto la rechaza. Con un parámetro `json` los duplicados **se conservan**: por eso R-11 exige `jsonb`. La reconstrucción hace irrelevante cuál duplicado sobrevive.

**Texto, Unicode y caracteres no admitidos (C-7, PR-10: 19 casos de ida y vuelta por HTTP, sin desviaciones).**
- `jsonb_build_object('motivo', NULL::text)` produce `{"motivo": null}`: la clave siempre está presente.
- Acentos, `ñ`, raya, emoji (también por par sustituto escapado), comillas, barra invertida, saltos de línea, marcado HTML y texto hebreo (RTL) hacen ida y vuelta **íntegros**. `btrim` recorta espacios, **no tabulaciones**.
- **No hay normalización Unicode.** `e` + U+0301 (2 caracteres) y `é` (1) son cadenas **distintas** para la comparación, para `char_length` y para el replay. Esta ADR **no normaliza** (ni NFC ni NFD). Consecuencia: un replay de `crear` con el mismo id y un `motivo` visualmente igual pero con otra normalización produce `PT409 intencion_conflicto` (falla cerrado; no crea una segunda intención). El cliente evita el caso reenviando **el mismo objeto** en sus reintentos (§5.14).
- `"\u0000"` → HTTP 400 `22P05` (antes de la función). Sustituto huérfano `"\ud800"` → HTTP 400 `PGRST102`. El cliente los trata como error genérico de datos.

### 5.5 RPC del contrato

Patrón vigente: implementación en `privado` (`SECURITY DEFINER`, `set search_path = ''`, propietaria `propietario_rpc`); fachada en `public` (`SECURITY INVOKER`, `language sql`, `set search_path = ''`); `EXECUTE` solo a `authenticated`; `service_role` y `anon` sin `EXECUTE`; sin sobrecargas (P14).

| RPC pública | Parámetros | Devuelve | Semántica |
|---|---|---|---|
| `crear_intencion_operacion` | `p_intencion_id uuid, p_tipo text, p_payload jsonb` | `uuid` (el mismo id) | Algoritmo en §5.5.1. Valida identidad (`PT401`), perfil activo y rol del tipo (`PT403`), tipo (`PT400 intencion_tipo_invalido`) y payload (§5.4, `PT400 intencion_payload_invalido`). **Serializa por actor** (C-1) y luego aplica los topes por actor (`PT429`). Inserta `pendiente` con el payload **reconstruido** y `vence_en = clock_timestamp() + plazo`, ambos fijados por el servidor. **Idempotente:** mismo id + mismo tipo y mismo payload reconstruido → mismo id sin efectos; mismo id con otros datos → `PT409 intencion_conflicto` |
| `ejecutar_intencion_operacion` | `p_intencion_id uuid` | `table(estado text, operacion_id uuid, codigo_rechazo text)` | Ver §5.6. Idempotente por estado |
| `cancelar_intencion_operacion` | `p_intencion_id uuid` | `text` (estado final) | Bloquea la fila. `pendiente`→`cancelada` (también si ya está vencida); ya `cancelada` o `rechazada` → idempotente (devuelve su estado); `confirmada` → `PT409 intencion_ya_confirmada`. Sin efectos sobre stock |
| `listar_intenciones_operacion` | `p_desde timestamptz default null` | `setof` fila (`intencion_id, tipo, payload, estado, operacion_id, codigo_rechazo, creado_en, vence_en, resuelto_en, vencida`) | Solo las del actor; orden `creado_en desc`; **tope fijo de 100 filas**; `p_desde` nulo equivale a 7 días y no puede ser anterior a 30 días (se recorta); las `pendiente` vigentes se incluyen siempre. `vencida` se calcula con `clock_timestamp()`. Solo lectura |

Errores `PTxyz` nuevos (misma forma que P16; sin nombres de restricción ni datos de otra empresa): `PT401 intencion_no_autenticado`, `PT403 intencion_no_autorizado`, `PT400 intencion_tipo_invalido`, `PT400 intencion_payload_invalido`, `PT404 intencion_no_encontrada` (ajena e inexistente, indistinguibles), `PT409 intencion_conflicto`, `PT409 intencion_vencida`, `PT409 intencion_cancelada`, `PT409 intencion_ya_confirmada`, `PT429 intencion_limite_excedido` (topes aprobados en §5.13) y `PT500 intencion_error_interno`. Nunca `40001`/`40P01` para errores de negocio.

Las cuatro funciones privadas validan la identidad del mismo modo (§5.9): `privado.usuario_actual()` nulo → `PT401`; perfil inexistente, inactivo o con un rol que no habilita los tipos de stock (`dueno`, `encargado`) → `PT403`. `listar` y `cancelar` exigen lo mismo (falla cerrado: un usuario que perdió el rol no gestiona intenciones; las suyas pendientes vencen solas y no tienen efecto sobre stock).

### 5.5.1 Algoritmo de `crear_intencion_operacion` y serialización por actor (C-1)

**Defecto corregido.** En v0.2 los topes de §5.13 se comprobaban «contando y luego insertando». PR-11 (hallazgo H-LM) lo refutó bajo concurrencia: con 80 `crear` distintos y simultáneos del mismo actor y tope 20, **sin** lock por actor quedaron 22–27 pendientes (tope de pendientes) y 21–26 filas (tope por hora), con exceso en **10/10 rondas**; **con** `pg_advisory_xact_lock` por actor quedaron **exactamente 20** en 10/10 rondas de cada tope (`logs/PR11.log`). El lock por actor es, por lo tanto, **parte obligatoria del contrato de `crear`**; los **valores** aprobados son 20 pendientes vigentes y 120 creaciones por hora (D-IDEM-5b, D-IDEM-5d).

```text
0. transaction_isolation <> 'read committed' → PT500 intencion_error_interno          -- R-13
1. v_uid := privado.usuario_actual();  NULL → PT401 intencion_no_autenticado
2. SELECT empresa_id, rol, activo FROM public.perfiles WHERE usuario_id = v_uid;
     sin fila, inactivo o rol fuera de ('dueno','encargado') → PT403 intencion_no_autorizado
3. Validar p_tipo (lista cerrada) y p_payload (§5.4); reconstruir v_payload.   -- sin leer tablas de negocio
4. PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
       'intenciones:' || v_empresa::text || ':' || v_uid::text, 0));             -- NIVEL 0 (§5.8)
5. Replay: SELECT … WHERE empresa_id = v_empresa AND actor_id = v_uid AND id = p_intencion_id;
     existe y (tipo, payload) iguales → devolver p_intencion_id (sin contar, sin efectos)
     existe y distintos               → PT409 intencion_conflicto
6. Contar pendientes vigentes (estado = 'pendiente' AND vence_en > clock_timestamp())
   y creaciones de la última hora (creado_en > clock_timestamp() - interval '1 hour');
     tope alcanzado → PT429 intencion_limite_excedido
7. INSERT … (vence_en = clock_timestamp() + plazo) ON CONFLICT (empresa_id, actor_id, id) DO NOTHING;
     si no insertó (defensa en profundidad) → releer y aplicar la regla del paso 5
8. Devolver p_intencion_id
```

| Aspecto | Contrato aprobado |
|---|---|
| **Orden de adquisición** | Identidad y perfil (lectura de `perfiles`) → validación pura del payload → **lock de actor (nivel 0)** → replay → conteos → `INSERT`. El lock se toma **después** de validar (un pedido inválido no espera ni bloquea a otros) y **antes** de cualquier lectura de `intenciones_operacion` |
| **Derivación de la clave** | `hashtextextended('intenciones:' || empresa || ':' || actor, 0)`, con `empresa` y `actor` tomados de `perfiles` vía `privado.usuario_actual()`; **nunca** del payload ni de parámetros. Llamadas calificadas con `pg_catalog.` (endurecimiento pg_temp). El prefijo `intenciones:` separa el espacio de nombres del de stock (`stock:<empresa>:<origen>:<producto>`, P13-stock). Una colisión del hash de 64 bits solo causaría **serialización adicional**, nunca un resultado incorrecto |
| **Solicitudes concurrentes** | Las del **mismo actor** esperan en el paso 4 y se atienden de a una; cada una ve, en una instantánea nueva, lo confirmado por la anterior (`READ COMMITTED`, función `VOLATILE`). Dos `crear` con el mismo id: el segundo encuentra la fila en el paso 5 (replay o `PT409`). Actores distintos **no se esperan entre sí**. Sin `NOWAIT` ni `lock_timeout`: no se introduce `55P03` |
| **Liberación** | Lock **transaccional** (`_xact_`): se libera al confirmar o revertir la transacción, incluido el caso de error (`PT4xx`, `PT429`, fallo inesperado). Prohibido `pg_advisory_lock` de sesión |
| **Efecto de `ejecutar`/`cancelar` concurrentes sobre el conteo** | No toman el lock de actor. Solo pueden **reducir** el número de pendientes; mientras no confirman, el conteo las ve aún `pendiente`. El error posible es un `PT429` conservador, **nunca** un exceso del tope |
| **Replay en el tope** | El replay (paso 5) ocurre antes de contar: un reintento de un id existente **nunca** recibe `PT429` ni cuenta para los topes |

### 5.6 Algoritmo de `ejecutar_intencion_operacion` (especificación)

```text
1. v_uid := privado.usuario_actual();  si es NULL → PT401 intencion_no_autenticado
2. Resolver empresa y perfil activo del actor desde public.perfiles;  si falta o inactivo → PT403 intencion_no_autorizado
3. SELECT … FROM intenciones_operacion
     WHERE empresa_id = v_empresa AND actor_id = v_uid AND id = p_intencion_id
     FOR UPDATE;                                    -- nivel 1 de bloqueo (§5.8); puede esperar a otra transacción
   si no existe → PT404 intencion_no_encontrada
4. Según el estado almacenado (leído YA bajo el bloqueo):
     'confirmada' | 'rechazada' → devolver lo almacenado (idempotente), sin llamar a la RPC y sin mirar el plazo
     'cancelada'                → PT409 intencion_cancelada
     'pendiente'                → seguir
5. ADMISIÓN POR PLAZO — con la fila ya bloqueada:
     IF clock_timestamp() >= v_vence_en THEN  PT409 intencion_vencida  (sin escribir)  END IF;
   Es la única comprobación de plazo. Usa clock_timestamp() y no now(): now() es el inicio de la
   transacción y queda atrasado si la sesión esperó el FOR UPDATE del paso 3.
6. Bloque protegido, ALCANCE MÍNIMO (solo la llamada a la RPC de negocio):
     BEGIN
       CASE v_tipo                                            -- estático, R-01
         WHEN 'ingreso'      THEN v_op := privado.registrar_ingreso     (v_id, <producto>, <cantidad>, <motivo>);
         WHEN 'a_cuarentena' THEN v_op := privado.mover_a_cuarentena    (v_id, <producto>, <origen>, <cantidad>, <motivo>);
         WHEN 'merma'        THEN v_op := privado.registrar_merma       (v_id, <producto>, <origen>, <cantidad>, <motivo_codigo>, <motivo>);
       END CASE;
     EXCEPTION
       WHEN SQLSTATE 'PT400' OR SQLSTATE 'PT404' OR SQLSTATE 'PT409' THEN   -- nombradas; NUNCA WHEN OTHERS (R-02)
         GET STACKED DIAGNOSTICS v_codigo = MESSAGE_TEXT;
         IF v_codigo NOT IN (<lista cerrada de §5.7>) THEN
           RAISE;                                                    -- relanza el error original, intacto
         END IF;
         v_rechazo := v_codigo;
     END;
7. Fuera del bloque protegido, en la misma transacción (transición atómica con el efecto):
     si v_rechazo IS NULL → UPDATE a 'confirmada' (operacion_id = v_op, resuelto_en = clock_timestamp())
     si no               → UPDATE a 'rechazada'  (codigo_rechazo = v_rechazo, resuelto_en = clock_timestamp())
   devolver (estado, operacion_id, codigo_rechazo)
```

**Semántica del vencimiento (hallazgo 1).**
- `vence_en` es el **límite para admitir nuevas ejecuciones**, no un plazo máximo de finalización.
- La admisión se decide **una sola vez**, en el paso 5, **después de obtener el bloqueo** y antes de invocar la RPC de negocio. Toda sesión que obtenga el bloqueo con `clock_timestamp() >= vence_en` recibe `PT409 intencion_vencida`, sin efectos.
- Una ejecución **admitida antes del vencimiento puede completar después**: por ejemplo, si el paso 6 espera el advisory lock de stock de otra transacción. En ese caso `resuelto_en` puede ser posterior a `vence_en`. Es válido y no se revierte.
- Una sesión que esperó el bloqueo del paso 3 mientras otra ejecutaba **no** admite una segunda ejecución: al despertar encuentra `confirmada` o `rechazada` y devuelve lo almacenado (paso 4), aunque ya haya pasado `vence_en`.
- No se promete que una `confirmada` ocurra antes de `vence_en`; se promete que ninguna ejecución se **admite** después.

Propiedades:
- El rechazo **revierte la subtransacción** del paso 6: no queda reserva en `operaciones` ni movimiento (coherente con P12-stock). Solo después se registra el estado.
- Cualquier error **no listado** o de otra clase (`40001`, `40P01`, `PT401`, `PT403`, `PT500`, `42501`, violaciones de restricción, errores internos) atraviesa el bloque sin ser capturado o es relanzado: la transacción completa se revierte y la intención **sigue `pendiente`**.
- La RPC de negocio revalida perfil activo, rol, pertenencia de producto y ubicación al ejecutar; la intención **no otorga autoridad**, solo secuencia.
- Las llamadas pasan los campos del payload ya reconstruido con conversiones explícitas (`(payload->>'cantidad')::integer`, etc.); no se interpola texto en sentencias.

### 5.7 Errores de negocio frente a errores transitorios o de identidad

| Clase | SQLSTATE / código | Tratamiento en `ejecutar` | Respuesta al cliente |
|---|---|---|---|
| **Negocio — se registra `rechazada` (lista cerrada)** | `PT400 stock_cantidad_invalida`, `PT400 stock_motivo_invalido`, `PT400 stock_origen_invalido`, `PT404 stock_producto_no_encontrado`, `PT404 stock_ubicacion_no_encontrada`, `PT409 stock_producto_inactivo`, `PT409 stock_insuficiente`, `PT409 stock_conflicto_idempotencia` | Subtransacción revertida; `UPDATE` a `rechazada` con el código; la función **retorna** | 200 con `estado = 'rechazada'` y `codigo_rechazo` |
| **Identidad / autorización** | `PT401`, `PT403`, `42501` | **Se relanza.** La intención sigue `pendiente` | Error HTTP (401/403); **nunca 200** (R-03) |
| **Transitorio de concurrencia** | `40001`, `40P01` | **Se relanza** (no se captura). Sigue `pendiente` | Error 500 con `code`; el cliente reintenta (§5.12) |
| **Interno / configuración** | `PT500` (`stock_error_interno`, `stock_ubicacion_no_configurada`) y cualquier SQLSTATE inesperado, incluidas violaciones de restricción | **Se relanza** | Error; sigue `pendiente` |
| **Intención** | `PT404 intencion_no_encontrada`, `PT409 intencion_vencida/cancelada` | Se lanza antes del bloque protegido | Error |

Notas:
- `stock_clave_invalida` (`PT400`) no puede ocurrir (el id es un `uuid` no nulo) y **no** está en la lista: si apareciera es inesperado y se relanza.
- `stock_conflicto_idempotencia` solo puede darse si el mismo actor invoca directamente la RPC de negocio con el id de la intención y otro payload; la intención queda `rechazada` con ese código. No afecta a otros actores.
- Un rechazo de negocio es **terminal**: reintentar es una **intención nueva**.
- **Diferencia deliberada con P16:** los rechazos de negocio de `ejecutar` se devuelven como **estado** (200) y no como `PTxyz`. Es lo que permite persistir `rechazada`. **Aprobada** el 06/11/2026 (D-IDEM-10), solo para la lista cerrada.

### 5.8 Orden de bloqueos y concurrencia entre `ejecutar` y `cancelar`

P13-stock fija `READ COMMITTED` y `pg_advisory_xact_lock` por empresa + ubicación + producto, solo en las RPC que debitan stock. Esta ADR **agrega una clase anterior**:

| Nivel | Recurso | Quién lo toma |
|---|---|---|
| **0** | `pg_advisory_xact_lock(hashtextextended('intenciones:<empresa>:<actor>', 0))` (C-1, §5.5.1) | **Solo** `crear` |
| **1** | Fila de la intención (`SELECT … FOR UPDATE`) | `ejecutar`, `cancelar` |
| **2** | `pg_advisory_xact_lock(hashtextextended('stock:<empresa>:<origen>:<producto>', 0))` | `mover_a_cuarentena`, `registrar_merma` (sin cambios) |

- **Orden global único: actor → intención → stock.** `crear` toma el nivel 0 y ningún otro lock explícito (no hace `FOR UPDATE` ni llama a RPC de stock); su `INSERT` solo puede esperar a otra inserción del mismo `(empresa_id, actor_id, id)`, que ya está serializada por el mismo nivel 0. `ejecutar` y `cancelar` **nunca** toman el nivel 0. `cancelar` solo toma el nivel 1. `listar` no toma locks. `registrar_ingreso` no toma el nivel 2 (solo acredita).
- **Ausencia de deadlocks (argumento).** Un ciclo exige dos transacciones que retengan cada una un recurso que la otra espera. El nivel 0 solo lo retiene `crear`, que no espera ningún recurso de nivel 1 o 2 mientras lo tiene; los niveles 1 y 2 se toman siempre en ese orden y ninguna función toma el 2 y luego el 1. Las verificaciones de FK del `INSERT` (`FOR KEY SHARE` sobre `perfiles` y `empresas`) pueden esperar a una actualización de esas filas, pero esa actualización no toma el nivel 0: no cierra un ciclo. **Es un argumento de diseño; se exige prueba** (LM-05, CC-02, CC-03).
- Si una ADR futura agrega tipos con otros locks (por ejemplo los de jornadas, ADR-001 §18.4.5), el de la intención **siempre va primero**.
- Garantías de PostgreSQL que esta ADR exige **probar** cuando se autorice su implementación (no se afirman sin prueba):
  1. Dos `ejecutar` simultáneos de la misma intención: uno ejecuta, el otro espera y devuelve el mismo resultado; un único movimiento.
  2. `ejecutar` y `cancelar` simultáneos: **gana exactamente uno**; nunca "ejecutada y cancelada".
  3. Tras un `cancelar` exitoso, la intención **no se ejecutará**: `cancelar` y `ejecutar` se serializan por el mismo `FOR UPDATE`. Tras `vence_en` **no se admiten ejecuciones nuevas** (§5.6, paso 5); una ejecución ya admitida antes del vencimiento puede completar después.
  4. `ejecutar` ejecuta **el payload almacenado**, no otro.
  5. Dos intenciones distintas sobre el mismo producto y ubicación se serializan por el nivel 2 existente: sin sobreventa, sin `40P01`.
  6. Muchos `crear` simultáneos del mismo actor nunca superan los topes de pendientes ni de creaciones por hora (nivel 0). **Comprobado en laboratorio con un prototipo invoker (PR-11/H-LM); se exige repetirlo sobre la implementación `SECURITY DEFINER` real (LM-05).**

### 5.9 Validación de empresa, actor, rol y sesión

- **Sesión.** El JWT lo valida PostgREST antes de llegar a la base. Un token vencido, alterado o mal formado falla en el borde con HTTP 401 `PGRST301` (PR-04), no reintentable. Dentro de la base, **`privado.usuario_actual()` nulo → `PT401`** (C-4; v0.2 decía «`auth.uid()` nulo»).
- **Por qué `privado.usuario_actual()` y no `auth.uid()` (C-4, PR-04).** Las funciones nuevas son `SECURITY DEFINER` propiedad de `propietario_rpc`, que **no tiene `USAGE` sobre el esquema `auth`**: en el laboratorio, una función con esa topología que llama `auth.uid()` falló con `permission denied for schema auth` (`42501`). El patrón vigente del repositorio es `privado.usuario_actual()` (`20261023140000_catalogo_productos.sql:146-160`, cuerpo endurecido por A1 en `20261105120000_pg_temp_auxiliar_usuario_actual.sql`): función `language sql`, `STABLE`, `SECURITY INVOKER`, `set search_path = ''`, propiedad de `propietario_rpc`, **sin `EXECUTE`** para `PUBLIC`, `anon`, `authenticated` ni `service_role`; dentro de la función privada se ejecuta como `propietario_rpc` y lee el claim `sub` que fija PostgREST (`request.jwt.claim.sub` o `request.jwt.claims`), con la misma expresión que `auth.uid()` (equivalencia cubierta por `supabase/tests/productos_catalogo.test.sql:352-373`). PR-04 verificó la cadena real fachada invoker → privada definer de `propietario_rpc` → `privado.usuario_actual()`: dueño → su id, vendedor → su id, sin sesión → `NULL`. Las políticas de §5.10 usan `(select privado.usuario_actual())`, como las de stock (`20261025033454_stock_cuarentena_merma.sql:112, 130`).
- **Validación de usuario, empresa, rol y actividad** (mismo patrón que `privado.mover_a_cuarentena`, `20261025033454…:209-222`): (1) `v_uid := privado.usuario_actual()`; nulo → `PT401`. (2) `SELECT empresa_id, rol, activo FROM public.perfiles WHERE usuario_id = v_uid` (un perfil 1:1, P5–P7). (3) Sin fila, `activo IS NOT TRUE`, rol nulo o fuera de `('dueno','encargado')` → `PT403`, sin revelar cuál de las condiciones falló. (4) `empresa_id` y `actor_id` de las sentencias y de la clave del lock salen **solo** de (1) y (2).
- **Actor y empresa.** `privado.usuario_actual()` y `perfiles` (un perfil 1:1 por usuario, una empresa, un rol; P5–P7). Nunca del payload.
- **Rol.** Al **crear**: el rol exigido por el tipo (stock: `dueno` o `encargado`). Al **ejecutar**: se revalida por la RPC de negocio vigente. Un cambio de rol o la inactivación entre ambos momentos produce `PT403` y la intención queda `pendiente` hasta vencer.
- **Cambio de usuario.** Una intención pertenece al actor creador; otro usuario, de la misma empresa o de otra, recibe `PT404` indistinguible de un id inexistente (como P16).

### 5.10 Permisos y RLS

**Alternativa A — APROBADA (D-IDEM-15, 06/11/2026).** Sin `SELECT` ni ningún otro acceso directo de `authenticated` a `intenciones_operacion`. La aprobación es normativa: **no autoriza** a crear la tabla, otorgar o revocar privilegios ni modificar el preflight hasta la tarea de implementación autorizada.

- `revoke all` sobre `public.intenciones_operacion` (tabla **y columnas**) a `PUBLIC`, `anon`, `authenticated`, `service_role`. **`authenticated` no recibe `SELECT` de tabla ni de columna.** `service_role` sin privilegio alguno (P11; no es una excepción nueva). Acceso solo por las cuatro fachadas.
- `propietario_rpc`, **exactamente**: `SELECT` de tabla; `INSERT (empresa_id, actor_id, id, tipo, payload, vence_en)` y `UPDATE (estado, operacion_id, codigo_rechazo, resuelto_en)` **solo por columna** (sin `INSERT`/`UPDATE` de tabla); **sin** `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER` ni `MAINTAIN` (retención indefinida, §5.13). `lector_perfiles_rpc`: ningún privilegio (D-2).
- Owner de la tabla: el owner de migraciones (`postgres`), como las 11 tablas inventariadas (P4). `ALTER DEFAULT PRIVILEGES` no debe dejar grants implícitos: lo verifican el preflight y `grants_default_privileges.test.sql` (§8.3).
- RLS **habilitada, sin `FORCE`** (P4). **Tres políticas** para `propietario_rpc` (`SELECT`, `INSERT`, `UPDATE`), todas acotadas a `actor_id = (select privado.usuario_actual())`; las de `SELECT` e `INSERT` exigen además perfil activo de la misma empresa. **Ninguna política para `authenticated`.** Sin política ni privilegio `DELETE` (retención indefinida aprobada).
- **Política de `UPDATE` con `WITH CHECK` explícito (precisión de Codex).** En PostgreSQL, si una política `UPDATE` no declara `WITH CHECK`, su expresión `USING` se aplica también a la **fila nueva**: con `USING (estado = 'pendiente')` implícito en el `WITH CHECK`, ninguna transición a un estado terminal pasaría. Por eso el contrato exige ambas cláusulas, distintas:
  - `USING`: `estado = 'pendiente' AND actor_id = (select privado.usuario_actual())` — solo se actualizan intenciones pendientes del propio actor (los terminales no cambian).
  - `WITH CHECK`: `actor_id = (select privado.usuario_actual()) AND estado IN ('confirmada', 'rechazada', 'cancelada')` — la fila resultante sigue siendo del actor y queda en un estado **terminal**. No impide ninguna transición válida de §5.3 y prohíbe volver a `pendiente` o reasignar el actor. La coherencia de los campos (operación, código, `resuelto_en`) la impone el `CHECK intenciones_coherencia` de §5.2.
  - El texto final de ambas expresiones fija los hashes `h_using`/`h_check` del preflight (§8.2.1 d).
- Por qué A: la tabla contiene payloads de operaciones que el actor puede consultar por `listar` (con tope, ventana y `vencida` calculada); una lectura directa por la Data API no agrega una capacidad necesaria y ampliaría la superficie (filtros arbitrarios, paginación sin tope, conteos). Con A, `NG-05` es un rechazo de privilegio y no depende de que la política esté bien escrita.
- **Costo de A:** el bloque 1.7 del preflight exige hoy `authenticated SELECT` en **toda** tabla inventariada. A requiere una **excepción explícita, nominada y exclusiva de `public.intenciones_operacion`** (§8.2), verificada en el laboratorio (variante A36 pasa `[ESTADO_A]`). La excepción **no** debilita el control de las otras 11 tablas: para ellas el contrato esperado sigue siendo idéntico.

**Variante B — descartada** (no aprobada; se conserva como registro). `authenticated SELECT` + una política `SELECT` por actor para `authenticated` (el patrón de las 11 tablas actuales). No necesita excepción en el preflight, pero cambia los conteos (**37** políticas sin `DELETE`, **38** con la purga) y expone la tabla a la Data API. Verificada en laboratorio (B37 pasa `[ESTADO_A]`) solo como experimento.
- Sin roles técnicos nuevos (P3, D-2). `service_role` sin `EXECUTE` ni privilegios de tabla.
- El esquema `privado` y `propietario_rpc` ya existen; no se crean objetos vacíos por anticipado.

### 5.11 Relación con `operaciones` e `idempotency_key`

- `intenciones_operacion.id` **es** la `idempotency_key` que la RPC de negocio reserva en `operaciones`. El `UNIQUE (empresa_id, actor_id, idempotency_key)` y la huella v1 siguen siendo la barrera de unicidad e idempotencia (P12-stock). `operaciones` conserva su contrato y **no recibe columnas ni restricciones nuevas** (la UNIQUE que usa la FK ya existe, §5.2).
- Esto implica una **segunda representación durable de la clave**, que P15-stock no prevé: ver §7.1.
- Una intención `confirmada` guarda el `operacion_id` devuelto, enlazado por la **FK compuesta** `(empresa_id, operacion_id, tipo, actor_id)`: la operación debe ser de la misma empresa, del mismo actor y del mismo tipo.
- **Invariante** (no expresable en la FK): para toda intención `confirmada`, `operaciones.idempotency_key = intenciones_operacion.id`. La mantiene `ejecutar` (única escritora de `confirmada`) y la comprueba una consulta de invariante en pgTAP y en las pruebas de integración.
- Si el mismo actor llamó antes, directamente, a la RPC de negocio con el mismo uuid y el mismo payload, `ejecutar` recibe el replay y la intención pasa a `confirmada` con esa operación; con otro payload, a `rechazada` por `stock_conflicto_idempotencia`. No hay efecto sobre otros actores.
- La verificación de "el stock se movió exactamente una vez" se hace en la base: para cada intención `confirmada`, una fila en `operaciones` con esa clave, un `movimientos_stock` con su `operacion_id` (índice `movimientos_stock_operacion_unitaria_unica`) y un saldo `S0 ± q` en `stock_actual`.

### 5.12 Política de reintentos P13 (cliente)

Se aplica P13-stock sin cambios: **máximo 3**, **misma clave y mismo payload**, solo ante `40001`, `40P01`, conexión perdida o timeout con resultado desconocido; `55P03` solo si proviene de la política explícita de locks; `57014` solo si es un timeout o cancelación recuperable; `PTxxx` **nunca**.

- Se interpreta "máximo 3" como **3 intentos en total** (cumple las dos lecturas posibles).
- Aplica a `crear`, `ejecutar` y `cancelar` (los tres son idempotentes). `listar` es lectura y no entra en P13.
- `55P03` y `57014`: las RPC de stock usan `pg_advisory_xact_lock` sin `lock_timeout`/`NOWAIT`, y el cliente no puede distinguir una cancelación "recuperable"; por lo tanto **no se reintentan automáticamente**.
- Un error sin código (fallo de red) tras 3 intentos **no** se presenta como fallo: la web consulta con `listar` y muestra el estado real.
- Esperas entre intentos: la ADR-001 no las define y esta ADR no las agrega.

**Respuestas HTTP observadas (C-8, PR-04: PostgREST `v16.4`, JWT real de GoTrue).** El cliente decide por el **`code` del cuerpo**, no solo por el estado HTTP:

| Situación | HTTP | Cuerpo | Tratamiento en el cliente |
|---|---|---|---|
| `RETURNS TABLE` con una fila (`confirmada` o `rechazada`) | **200** | **Arreglo de un objeto**: `[{"estado":"rechazada","operacion_id":null,"codigo_rechazo":"stock_insuficiente"}]` | Leer el primer elemento. Con `Accept: application/vnd.pgrst.object+json` llega **un solo objeto** |
| `RETURNS TABLE` sin filas | 200 | `[]` | No debería ocurrir en `ejecutar`; tratar como error inesperado |
| `PT401` / `PT403` / `PT404` / `PT409` / `PT429` / `PT500` | **401 / 403 / 404 / 409 / 429 / 500** | `{"code":"PTxyz","message":"…"}` | Sin reintento (P13). `PT401`/`PT403`: error de sesión/permiso, **nunca** rechazo de negocio |
| `40001` / `40P01` | **500** | `{"code":"40001"…}` / `{"code":"40P01"…}` | Reintento P13 (el estado 500 no basta: hay que leer `code`) |
| `42501` | **403** autenticado · **401** `anon` | `{"code":"42501"…}` | Sin reintento |
| JWT alterado o mal formado | **401** | `PGRST301` | Sin reintento; reingreso |
| Literal JSON inválido (`01`, `+1`, sustituto huérfano) | 400 | `PGRST102` | Error genérico de datos (§5.4) |
| Número fuera de rango (`1e999999999`) / `\u0000` | 400 | `22003` / `22P05` | Error genérico de datos (§5.4) |

`40001` y `40P01` se **simularon** con `RAISE` (no se provocó un deadlock real): lo verificado es su propagación y su mapeo HTTP.

### 5.13 Vencimiento, retención y límites

Valores **aprobados** por la decisión humana del 06/11/2026 (§0.2); se resumen en §12. Ninguno está implementado.

| Elemento | Aprobado |
|---|---|
| **Vencimiento** | `vence_en = clock_timestamp() + 24 h`, fijado por el servidor al crear. Es el **límite para admitir nuevas ejecuciones** (§5.6, paso 5), comprobado con `clock_timestamp()` bajo `FOR UPDATE`. No es un corte de las ejecuciones ya admitidas |
| Estado "vencida" | Derivado (`pendiente` y `clock_timestamp() >= vence_en`); no se escribe. `cancelar` puede cerrarla |
| **Retención** | **Indefinida, sin purga** (aprobada, D-IDEM-3): coherente con la retención indefinida de P12, una fila por operación, sin privilegio `DELETE`, **36 políticas** en el inventario de T3-01 (§8). Cambia respecto de v0.1 (que proponía purga perezosa) para reducir superficie privilegiada y no introducir el primer `DELETE` de la aplicación sin necesidad |
| Variante con purga | **Descartada** por la decisión humana del 06/11/2026 (retención indefinida, sin purga). Cualquier purga futura exige una nueva decisión, una migración hacia adelante (ADR-009) y pruebas propias |
| **Límite de pendientes por actor** | Máximo 20 intenciones `pendiente` vigentes (no vencidas); excederlo → `PT429 intencion_limite_excedido`. Valor **aprobado** (D-IDEM-5b); el **mecanismo** de serialización por actor (§5.5.1, C-1) es obligatorio para cualquier valor que se apruebe |
| **Límite de creación por actor** | Máximo 120 creaciones en la última hora; excederlo → `PT429`. El replay idempotente de un id existente **no** cuenta. Valor **aprobado** (D-IDEM-5d); mismo mecanismo obligatorio |
| **Listado** | `LIMIT 100`; `p_desde` nulo = 7 días; ventana máxima de 30 días; los valores anteriores se recortan al límite permitido; las `pendiente` vigentes siempre incluidas |
| **`motivo`** | Máximo 500 caracteres en la vía de intenciones. La RPC de negocio llamada directamente sigue sin tope (decisión aparte) |
| Efecto sobre la auditoría | Ninguno: la auditoría es `operaciones` + `movimientos_stock` (P17) |

### 5.14 Flujo del cliente y restricción de interfaz

```text
ENVIAR
  id = crypto.randomUUID()
  crear_intencion_operacion(id, tipo, payload)        -- ≤3 intentos P13; idempotente por id
  ejecutar_intencion_operacion(id)                    -- ≤3 intentos P13
     confirmada → éxito; refrescar stock desde la base
     rechazada  → mostrar el motivo; el intento queda cerrado
     sin respuesta tras 3 intentos → NO es "fallo": listar y mostrar el estado real

RECUPERAR (recarga, cierre, otro dispositivo, otra sesión del mismo usuario)
  listar_intenciones_operacion()
     pendiente  → contenido + [Confirmar] (ejecutar) / [Descartar] (cancelar)
     confirmada → "ya se registró"; refrescar stock
     rechazada  → mostrar el motivo
     cancelada / vencida → informativo
```

**Restricción de interfaz (obligatoria, pero no es una garantía del servidor):** antes de crear otra intención del mismo tipo, la web muestra las pendientes del actor y exige resolverlas (Confirmar/Descartar) o una confirmación explícita "crear otra igual".

---

## 6. Garantías reales y límites de deduplicación

| Garantía | Quién la impone |
|---|---|
| Una intención se ejecuta a lo sumo una vez | **PostgreSQL** (`FOR UPDATE` + `UNIQUE` de `operaciones`) |
| `ejecutar` y `cancelar` se serializan; tras `cancelar` no se ejecuta | **PostgreSQL** |
| Tras `vence_en` no se admiten ejecuciones **nuevas**; una ya admitida puede completar después | **PostgreSQL** (comprobación con `clock_timestamp()` bajo bloqueo) |
| `ejecutar` usa el payload almacenado, reconstruido e inmutable | **PostgreSQL** |
| Una intención es recuperable por su actor desde cualquier dispositivo | **PostgreSQL** (datos en la base, anclados al actor) |
| Ninguna lectura cruza actor ni empresa | **PostgreSQL** (RLS + predicado de actor + `PT404` indistinguible) |
| Una operación confirmada con respuesta perdida se detecta tras recargar | **PostgreSQL** (`listar`) |
| El usuario no crea una segunda intención sin ver la pendiente | **Interfaz** (§5.14); no es garantía del servidor |
| Dos operaciones idénticas legítimas siguen siendo posibles | **Diseño**: cada acción crea su propia intención |

**Lo que el servidor NO puede identificar ni prometer:**
- Que dos intenciones distintas expresen "la misma idea" del usuario. Dos ingresos idénticos pueden ser legítimos: el servidor **no los deduplica ni debe**.
- Impedir que un cliente llame directamente a la RPC de negocio con una clave nueva (bypass), mientras no exista la Fase 2.
- Distinguir en vivo una solicitud retrasada en la red de una que nunca llegará: solo garantiza que, si llega, ejecutará esa intención una vez, o será rechazada si ya fue cancelada, si ya venció (no se admiten ejecuciones nuevas) o devolverá el resultado si ya fue resuelta.
- Que una ejecución confirme antes de `vence_en`: solo que se **admita** antes.

## 7. Compatibilidad con ADR-001, ADR-005, ADR-009 y el Blueprint

> Las filas «Excepción aprobada» y «Se amplía» quedaron **resueltas por la decisión humana del 06/11/2026** (§0.2) para la vía de intenciones de stock; no alteran ninguna otra regla de ADR-001.

| Regla | Efecto de esta ADR |
|---|---|
| P2–P4 (`public`/`privado`, `propietario_rpc`, RLS sin `FORCE`) | Se respeta. Funciones privadas en `privado`; tabla en `public` con RLS |
| P5–P7 (un perfil, una empresa, un rol) | Sin cambios. Empresa y rol salen de `perfiles` |
| P11 (`service_role` denegado por defecto) | Sin cambios. Ni tabla ni `EXECUTE` para `service_role` |
| P12-stock (idempotencia en `operaciones`, huella v1) | **Sin cambios.** La clave es el id de la intención |
| P13-stock (`READ COMMITTED`, advisory locks en orden) | **Se amplía, solo en la vía de intenciones** (aprobado el 06/11/2026; remisión en ADR-001 §18.3): nivel 0 (lock de actor en `crear`) y nivel 1 (fila de la intención) anteriores al lock de stock; las RPC de stock no cambian |
| P14 (sin sobrecargas) | Se respeta |
| **P15-stock** («`idempotency_key` vive sólo en `operaciones`») | **Excepción aprobada (§7.1)**, registrada por remisión en ADR-001 §18.3 y en `BLUEPRINT.md` §7.9.1. La clave tiene dos representaciones durables, acotadas a los tipos aprobados |
| P16 (errores `PTxyz` estables) | Se amplía con `intencion_*`. **Diferencia deliberada:** rechazos de negocio como estado (D-IDEM-10) |
| P17 (auditoría = `operaciones` + `movimientos_stock`) | Sin cambios; las intenciones no son auditoría |
| ADR-005 (unidad mínima entera; gramos) | Cantidades enteras en unidad mínima; sin float; conversión en el cliente |
| ADR-009 (forward-only) | Una migración nueva; sin rollback ejecutable |
| Blueprint §7.9.1, §7.9.6 | La operación sigue siendo la ejecución lógica idempotente; la intención la **precede** y no la reemplaza. `BLUEPRINT.md` v2.6 §7.9.1 **ya incorpora** la excepción aprobada a P15 (§7.1) |
| Blueprint §8 | `BLUEPRINT.md` v2.6 §8 **ya incorpora** la entidad `intenciones_operacion` (aprobada, no implementada) |
| Blueprint §3/§6 («no mover stock ni dinero desde el frontend») | Se respeta: todo cambio de stock sigue por RPC |

**Contratos aprobados que esta ADR NO cambia en la Fase 1:** firmas, ACL, errores y huellas de `registrar_ingreso`, `mover_a_cuarentena` y `registrar_merma`, sus fachadas; las seis RPC de jornadas; `operaciones` (columnas, restricciones y políticas); `movimientos_stock`; `stock_actual`.

### 7.1 Excepción aprobada a P15 (hallazgo 3; aprobada el 06/11/2026)

**Texto vigente.** P15-stock (ADR-001 §18.3): «`idempotency_key` vive sólo en `operaciones`; no se duplica en `movimientos_stock` (§7.9.1)». Blueprint §7.9.1: «No se duplica `idempotency_key` en los documentos hijos **salvo necesidad concreta** que aparezca en el diseño SQL/RPC».

**Reconocimiento.** Con esta ADR, para toda operación confirmada la clave tiene **dos representaciones durables**: `operaciones.idempotency_key` y `intenciones_operacion.id`, con el mismo valor. La intención no es un «documento hijo» (precede a la operación y puede no llegar a tener ninguna), pero contradice la letra de «sólo en `operaciones`». **No se afirma que sea compatible con P15 sin una decisión humana.**

**Justificación (necesidad concreta).** La recuperación tras recarga, cierre o cambio de dispositivo exige un identificador que exista en el servidor **antes** de que la operación se confirme (§1.3). Las alternativas que no duplican la clave no lo logran: consultar `operaciones` no sirve antes de la confirmación (A0, B0) y derivar la clave del contenido colapsa operaciones legítimas idénticas (D1, D2).

**Extensión aprobada (texto vigente desde el 06/11/2026).**
> *P15-stock, extensión:* la `idempotency_key` de una operación de stock puede persistirse además como identificador (`id`) de su intención en `public.intenciones_operacion`, únicamente para los tipos aprobados. `operaciones.idempotency_key` sigue siendo la única barrera de unicidad e idempotencia de la ejecución; la intención no la reemplaza y su unicidad se limita a `(empresa_id, actor_id, id)`. Sigue prohibido copiar la clave a `movimientos_stock` y a cualquier documento hijo.

**Controles que acotan la duplicación.** (1) PK compuesta por actor; (2) la FK compuesta y la invariante `operaciones.idempotency_key = intenciones_operacion.id` comprobada por pgTAP; (3) ninguna copia en `movimientos_stock` ni en otros documentos; (4) no se usa para decidir la unicidad de la operación.

**Cambios normativos realizados con la aprobación (06/11/2026):**
1. Esta ADR, aprobada, declara la extensión.
2. ADR-001 §18.3 recibe una **nota de remisión** a ADR-010 (autorizada por la decisión humana); P15-stock sigue vigente para todo lo demás.
3. `BLUEPRINT.md` v2.6: nota de excepción en §7.9.1 y entidad `intenciones_operacion` en §8.
4. **Obligación de implementación:** los tests que verifican que la clave no aparece en `movimientos_stock` ni en documentos hijos deben seguir pasando (RF-04).

## 8. Consecuencias sobre T3-01 e inventarios privilegiados (hallazgo 6)

El preflight `supabase/scripts/validar_topologia_propietario_rpc.sql` (SHA-256 `e9d49e09…ed6b` en el HEAD `358bb7c`) es un inventario **cerrado**: cualquier función, relación o política fuera del manifiesto lo hace fallar. **No se modificó el preflight** y no se modificará hasta que se autorice la implementación; esta sección fija el impacto que tendrá con esta ADR implementada. La secuencia quedó decidida (D-IDEM-7: después del cierre de T3-01). Las cifras y la lista de cambios se **verificaron en laboratorio** (PR-13) sobre una **copia** del preflight fuera del repositorio; esa copia no es un cambio aprobado de T3-01.

### 8.1 Cifras que cambiarían (verificadas en PR-13)

| Inventario | Hoy | Con esta ADR implementada (alternativa A, retención indefinida) | Línea del preflight | Origen del cambio |
|---|---|---|---|---|
| Firmas del manifiesto de funciones | **40** | **48** | `:879-880` | +4 privadas + 4 fachadas públicas |
| Funciones `SECURITY DEFINER` aprobadas (inventario 3.7) | **20** | **24** | `:1018-1043`, `:1050` | +4 privadas |
| Relaciones con RLS del manifiesto (T3P-05/T3P-06) | **11** | **12** | `:1410-1412` | + `public.intenciones_operacion` |
| Políticas RLS del manifiesto | **33** | **36** | `:1406-1407` | 3 políticas de `propietario_rpc` (`SELECT`, `INSERT`, `UPDATE`) |

**Composición correcta de «20» (C-2; v0.2 decía «19 + `public.rls_auto_enable()`», que era inexacto).** El inventario 3.7 lista **20 funciones `SECURITY DEFINER`, todas en `privado`**: las 19 implementaciones privadas que tienen fachada en `public` (6 de jornadas, 3 de productos, 3 de camiones, 4 de clientes, 3 de stock) **más** el auxiliar `privado.empresa_gestion_actual()`, que no tiene fachada. `privado.usuario_actual()` es `SECURITY INVOKER` y no cuenta. **`public.rls_auto_enable()` no integra la cifra:** es la excepción O-4, que el preflight trata por separado (`:1072-1157`) y que solo existe en el proyecto alojado; en el laboratorio (stack local) **no existe**, y el preflight original igual pasó con 20. Con esta ADR implementada: 20 + 4 privadas = **24**. Las 40 firmas son 19 × 2 (implementación + fachada) + los 2 auxiliares (`usuario_actual`, `empresa_gestion_actual`); con esta ADR implementada, 40 + 8 = **48**.

**Otras variantes medidas en PR-13 (no aprobadas):** retención con purga (`DELETE`): **37** políticas. Variante B (§5.10): **37** sin purga, **38** con purga. En todas: 48 / 24 / 12.

**Este documento no modifica el inventario real**: las cifras de la columna «Hoy» siguen vigentes hasta que una implementación aprobada las cambie.

### 8.2 Qué más exige el manifiesto, función por función y política por política

| Elemento | Detalle a incorporar |
|---|---|
| **Funciones (8)** | Firma exacta; esquema (`privado`/`public`); **owner** (`propietario_rpc` las privadas, `postgres` las fachadas); lenguaje (`plpgsql` / `sql`); marca `SECURITY DEFINER` solo en las privadas; volatilidad; **`proconfig`** (`search_path` vacío y el endurecimiento pg_temp de A1/A3/B1); **ACL** (`authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc` privadas; `authenticated=X/postgres,postgres=X/postgres` públicas); `EXECUTE` solo `authenticated`; sin sobrecargas ni homónimos entre `privado` y `public` (control 3.4) |
| **Tabla** | Owner; RLS habilitada sin `FORCE`; ACL de tabla y de columnas (`INSERT` y `UPDATE` por columna para `propietario_rpc`; nada para `anon`, `authenticated`, `service_role`, `PUBLIC`); sin `DELETE` (retención indefinida aprobada) |
| **Políticas (3)** | Nombre, comando, permisiva/restrictiva, rol y los **hashes SHA-256 de las expresiones `USING` y `WITH CHECK`** (`h_using`, `h_check`), que solo pueden calcularse con el texto final de las políticas. Toda política fuera del manifiesto sobre una relación manifestada se rechaza (B11-02) |
| **Grants por defecto** | `ALTER DEFAULT PRIVILEGES` y `service_role`: la tabla y las funciones nuevas no deben recibir privilegios implícitos |
| **Tests negativos de inventario** | Que el preflight falle si falta alguna de las 8 funciones, si hay una novena, si cambia un owner o una ACL, si aparece una política extra o si `service_role`/`anon`/`authenticated` obtienen algún privilegio sobre la tabla |
| **`operaciones`** | **Sin cambios**: su inventario de restricciones (`stock_ingreso.test.sql:155-170`) y sus políticas no se alteran, porque la FK reutiliza `operaciones_referencia_apertura` |
| **O-4** | `public.rls_auto_enable()` y `ensure_rls` no cambian |

### 8.2.1 Inventario completo de cambios del preflight (C-3)

El cambio **no es solo de cuatro cifras**. Lugares verificados en el preflight actual y en la copia de laboratorio (`stack-config/preflight_diff_original_vs_36pol.diff`):

**(a) Listas literales de las 11 relaciones — siete bloques**, a los que se agrega `('public.intenciones_operacion')`:

| # | Línea | Bloque | Qué verifica |
|---|---|---|---|
| 1 | `:288-298` | 1.7 privilegios de tabla de la Data API | `anon` y `authenticated`, 8 privilegios. **Lleva la excepción A** (abajo) |
| 2 | `:303-313` | 1.7 privilegios por columna | `INSERT/UPDATE/REFERENCES` de `anon`/`authenticated`; `SELECT` de `anon`. **Lleva el complemento de la excepción A** (abajo) |
| 3 | `:338-342` | 1.7 privilegios de `lector_perfiles_rpc` | Ninguno sobre la tabla (D-2) |
| 4 | `:382-386` | 2 T3P-05: owner `postgres`, RLS sin `FORCE` | Las relaciones inventariadas |
| 5 | `:443-447` | 2 exclusión de «tablas adicionales» de `public` | Sin la tabla en la lista, se la trataría como adicional (sin contrato de owner) |
| 6 | `:1207-1211` | 4.1 T3P-08 privilegios de tabla de `service_role` | Ninguno (P11; sin excepción nueva) |
| 7 | `:1256-1260` | 4.3 T3P-08 privilegios por columna de `service_role` | Ninguno |

**(b) Manifiestos y listas de nombres:**
- **Manifiesto de funciones** (`:647` y siguientes): 8 filas con firma, nombre, esquema, owner, lenguaje, `SECURITY DEFINER`, volatilidad (`v`), ACL y `EXECUTE`.
- **Lista 3.4 de sobrecargas y homónimos** (`:896-922`): 4 nombres con esquemas esperados `privado,public`. **Si se olvida esta lista, una sobrecarga de las funciones nuevas no se detecta** (PR-13).
- **Inventario 3.7 `SECURITY DEFINER`** (`:1018-1040`): 4 firmas privadas.
- **Manifiesto de políticas** (`:1326-1360`): 3 filas con tabla, nombre, comando, permisiva, rol, `h_using`, `h_check`.

**(c) Conteos:** `:879-880` (40 → 48), `:1041-1043` y `:1050` (20 → 24), `:1406-1407` (33 → 36), `:1410-1412` (11 → 12).

**(d) Hashes de políticas.** `h_using` y `h_check` son SHA-256 de `pg_get_expr(...)`, que el preflight evalúa con `search_path = pg_catalog, pg_temp`. **Deben calcularse con ese mismo `search_path`**: calculados con otro, la deparsificación cambia (calificación de nombres) y el preflight falla con `[POLITICA_CHECK]`/`[POLITICA_USING]` (comprobado en PR-13). Solo pueden fijarse con el **texto final** de las políticas; los hashes del laboratorio corresponden a políticas de prueba y **no** son los de una implementación.

**(e) Mensajes `NOTICE` con cifras literales:** `:13` (comentario de cabecera, «40 firmas»), `:607` y `:1468` («11 tablas»), `:1187` y `:1469` («40 firmas», «20 firmas»), `:1449` y `:1471` («33 políticas», «11 relaciones»). Comentarios con cifras: `:1202` («11 tablas x 8 privilegios»), `:1307` («33 políticas»), `:1410` («11 relaciones»). No afectan el resultado, pero quedarían falsos.

**(f) Excepción de la alternativa A — exacta, exclusiva y verificable (APROBADA como contrato; el preflight no se modificó).**
1. **Tabla (bloque 1):** la expectativa pasa de `(rol = 'authenticated' AND priv = 'SELECT')` a `(rol = 'authenticated' AND priv = 'SELECT' AND tabla <> 'public.intenciones_operacion')`. Para `intenciones_operacion` el contrato esperado es **ningún privilegio** de `anon` ni de `authenticated`; para las otras 11 tablas el contrato **no cambia**. Verificada en PR-13 (A36 → `[ESTADO_A]`; con `authenticated SELECT` sobre la tabla → `[ACCESO_DATA_API]`).
2. **Columnas (bloque 2) — complemento no probado en laboratorio.** `has_table_privilege(…, 'SELECT')` **no** detecta un `GRANT SELECT (columna)`, y el bloque 2 solo controla `SELECT` por columna para `anon`. Con A, un `SELECT` por columna de `authenticated` sobre la tabla nueva **pasaría inadvertido**. **Obligación normativa (N-COL):** el preflight actualizado **debe** rechazar, **solo para `public.intenciones_operacion`**, todo `SELECT` por columna de `anon` y de `authenticated`, detectado con `has_any_column_privilege(rol, 'public.intenciones_operacion', 'SELECT')`. Esto **no** cambia el control de las otras tablas (donde `authenticated` tiene `SELECT` legítimo). **Todavía no está implementado ni probado:** se dedujo de la lectura del preflight y su verificación es obligatoria en la implementación (ES-06, negativo N-COL).
3. La excepción se escribe con el **nombre literal** de la tabla, nunca con un patrón, una lista configurable ni una condición genérica («tablas sin política para `authenticated`»).

**(g) Brechas del preflight actual detectadas por PR-13 (no corregidas):** el preflight **no detecta** que `propietario_rpc` reciba `DELETE` sobre la tabla (N12) ni `UPDATE` de **todas** las columnas (N13), porque no verifica las ACL de `propietario_rpc` sobre tablas. Se cubren con pgTAP (ES-02) y no con el preflight. No se evaluó si la misma brecha afecta a las 11 tablas existentes: queda informado fuera del alcance de esta ADR.

**(h) Pruebas negativas que PR-13 sí demostró detectadas** (cada DDL en `BEGIN … ROLLBACK`): fachada faltante `[FIRMA]`; `SECURITY DEFINER` extra `[OWNERSHIP_PROPIETARIO_RPC]`; `EXECUTE` para `anon`/`PUBLIC`/`service_role` sobre una privada `[EXECUTE_ANON]`/`[EXECUTE_PUBLIC]`/`[EXECUTE_SERVICE_ROLE]`; `SELECT` de `authenticated`/`anon`/`service_role` sobre la tabla `[ACCESO_DATA_API]`/`[P11_TABLA]`; política extra `[POLITICA_ADICIONAL]`; política ausente `[POLITICA_AUSENTE]`; `WITH CHECK` alterado `[POLITICA_CHECK]`; `FORCE` `[RLS_FORCE]`; RLS deshabilitada `[RLS_DESHABILITADA]`; `proconfig` alterado `[PROCONFIG]`; sobrecarga `[SOBRECARGA]`.

### 8.3 Otros artefactos a actualizar (en la tarea de implementación)

| Artefacto | Cambio |
|---|---|
| `supabase/tests/hardening_adr001.test.sql`, `grants_default_privileges.test.sql` | Incluir tabla y funciones nuevas en los inventarios de ACL y de `service_role` |
| `supabase/tests/pg_temp_*.test.sql` | Endurecimiento pg_temp equivalente para las 4 funciones privadas |
| pgTAP nuevos | Ver §10.B |
| `docs/decisions/README.md`, `BLUEPRINT.md` §8 y §7.9.1 | **Ya actualizados** con la aprobación del 06/11/2026 (README: ADR-010 APROBADA; Blueprint v2.6: entidad y excepción a P15). La implementación **no** vuelve a aprobar estas decisiones: actualiza migraciones, RPC, preflight, tests y código, y solo ajusta el estado de implementación en la documentación |

**Estado de T3-01.** Su Fase 1 **no está aprobada** y esta ADR **no la modifica**. Mientras siga abierta, el preflight debe tratarse como congelado. Implementar esta ADR antes de cerrarla haría fallar el preflight (`[SD_NO_AUTORIZADA]` en PR-13) hasta aplicar todos los cambios de §8.2.1. **Decisión humana del 06/11/2026 (D-IDEM-7): la implementación se hará después del cierre de T3-01.**

## 9. Compatibilidad futura (sin implementarla)

### 9.1 Ventas y cobros

El patrón es reutilizable, pero esta ADR **no lo habilita** para ellos. Condiciones para una extensión futura, cada una con su propia ADR:

| Riesgo al ampliar | Control exigido |
|---|---|
| El despachador se convierte en puerta de escalada de privilegios | `CASE` estático (R-01); agregar un tipo = migración + ADR (R-08); la RPC de negocio revalida rol y empresa |
| Un vendedor ejecuta tipos de dueño/encargado | Validar el rol del tipo al crear **y** al ejecutar. La intención no otorga autoridad |
| `operaciones_insert_propietario_rpc` limita **todos** los tipos a dueño/encargado (`20261030120000…:847-860`) | Una venta digital por vendedor exige modificar esa política **por tipo**, en el diseño de ventas; fuera de esta ADR |
| Lectura cruzada | Solo el actor creador; sin acceso del dueño a pendientes ajenas salvo decisión (D-IDEM-12) |
| Dinero | Importes como **cadena decimal** con escala validada (`numeric`), nunca `float` ni número JSON; ADR-004 (cobros en jornada cerrada) sigue vigente |
| Payloads grandes (ventas con ítems) | Revisar tamaño y validación por tipo antes de aprobar el tipo |
| Retiros con doble confirmación | La doble confirmación es un flujo de negocio propio; no se reemplaza por una intención |

### 9.2 Fase 2 técnica: obligar a usar intenciones

Cerrar el bypass exige revocar `EXECUTE` a `authenticated` sobre las fachadas públicas de stock (y, si se extiende, de jornadas). **Cambia contratos aprobados** y obliga a actualizar: ADR-001 §18.3 (y §18.4), el manifiesto/ACL del preflight T3-01, los pgTAP que llaman las RPC como `authenticated` (`stock_ingreso`, `stock_cuarentena_merma`, `stock_aislamiento_*`, `stock_peso_gramos`, `pg_temp_stock*`, `grants_default_privileges` y los de jornadas), `supabase/tests/concurrencia/casos.sh`, los E2E/HTTP y los tests de `lib/stock`. **No se propone ahora** (D-IDEM-13).

---

## 10. Pruebas y criterios de aceptación (hallazgo 8)

> **Estado de las pruebas (v0.3).** Las premisas de §10.A **se ejecutaron** en un laboratorio descartable fuera del repositorio (13 PASS, 0 FAIL, 0 no concluyentes; §0.1). **Ninguna prueba de §10.B se escribió ni se ejecutó:** dependen de una implementación que no está autorizada. Todo se correría en un **stack Supabase aislado y descartable** (copia fuera del repositorio, `project_id` y puertos propios), sin tocar stacks existentes, staging ni producción.
>
> **Nota:** la lista de «casos adicionales señalados por Codex» no está disponible en el repositorio (ver §0). Los casos de vencimiento, FK compuesta, payload, topes, P15 e inventarios se derivaron de los ocho puntos de corrección; deben cotejarse con el dictamen.

### 10.A Pruebas de premisas — ANTES de la aprobación (ejecutadas)

Experimentos con scripts **fuera del repositorio**, sin migraciones ni objetos de la aplicación, sobre el stack descartable `adr010-pr-lab` (§0.1). Evidencia: `../evidencias-entrega-b/d-idem-supabase/laboratorio-premisas/` (`RESULTADOS_PR01_PR13.md`, `logs/`, `scripts/`, `MANIFIESTO.sha256`). El aislamiento se verificó con inventario Docker previo y posterior idéntico; el stack del proyecto (puerto 54321) no se tocó.

| Id | Premisa | Resultado observado | Veredicto | Consecuencia en v0.3 |
|---|---|---|---|---|
| PR-01 | Advisory locks dentro de `BEGIN … EXCEPTION` con error capturado se liberan | Débito real rechazado (`PT409 stock_insuficiente`) y capturado: 0 locks retenidos; otra sesión obtiene el lock. Control positivo: con débito exitoso, 1 lock y la otra sesión no lo obtiene | **PASS** | Confirma §5.6/§5.8 |
| PR-02 | `RAISE;` conserva SQLSTATE, mensaje, detalle y pista | Idénticos (error real y sintético con los cuatro campos) | **PASS** | Confirma §5.6 paso 6 |
| PR-03 | `WHEN SQLSTATE 'PT400' OR 'PT404' OR 'PT409'` es selectivo | 15/15: solo esos tres capturados; pasan `PT401`, `PT403`, `PT500`, `40001`, `40P01`, `55P03`, `P0001`, `42501` real, `57014` real, `22003` real, `23505` real, `XX000` | **PASS** | Confirma R-02/R-03 y §5.7 |
| PR-04 | PostgREST real: `RETURNS TABLE`, estados HTTP, identidad invoker/definer | Arreglo de un objeto; `PTxyz` → HTTP del mismo número; `40001`/`40P01` → 500; `42501` → 403/401; `auth.uid()` directo en definer de `propietario_rpc` **falla**; `privado.usuario_actual()` funciona | **PASS** | **C-4** (§5.9) y **C-8** (§5.12) |
| PR-05 | Números JSON en `jsonb` | 26/26 sin desviaciones; `1e3`/`0.5e1` normalizados; `1.0` conserva la escala; `01`/`+1` → `PGRST102`; `1e999999999` → `22003` | **PASS** | **C-5** (§5.4) |
| PR-06 | Claves duplicadas | Gana la última con `jsonb`; con `json` se conservan | **PASS** | **C-6** (R-11) |
| PR-07 | FK compuesta | 8/8: apoyada en la UNIQUE existente; rechaza otro actor, otro tipo, otra empresa (`23503`); `CHECK` de coherencia (`23514`) | **PASS** | Confirma §5.2 |
| PR-08 | `now()` frente a `clock_timestamp()` tras esperar `FOR UPDATE` | Diferencia de 4,00 s; `now()` admitiría, `clock_timestamp()` rechaza | **PASS** | Confirma §5.6 paso 5 |
| PR-09 | Admitida antes de `vence_en`, completa después; segundo ejecutor; atomicidad | Completa 3,16 s después de `vence_en` con 1 operación y 1 movimiento; el segundo ejecutor devuelve lo almacenado; falla forzada tras el movimiento → 0 efectos y sigue `pendiente`; vencida antes o durante la espera → `PT409 intencion_vencida` | **PASS** (2 corridas) | Confirma §5.6 |
| PR-10 | `jsonb_build_object` con `NULL`; Unicode | 19 casos íntegros; sin normalización Unicode; `\u0000` → `22P05`; sustituto huérfano → `PGRST102` | **PASS** | **C-7** (§5.4) |
| PR-11 | Dos `crear` simultáneos con el mismo id | 24 hilos: 1 fila, 1 id; con dos contenidos: 12 × 200 y 12 × 409, 1 fila. **Hallazgo H-LM:** sin lock por actor los topes se exceden en 10/10 rondas | **PASS** + defecto de diseño | **C-1** (§5.5.1) |
| PR-12 | Costo de la subtransacción | ≈ 0 a +3 %; extremo a extremo +0,2 ms | **PASS** (informativa) | Ninguna |
| PR-13 | Recuento del preflight | 48 / 24 / 12 / 36 pasan `[ESTADO_A]`; el original falla con los objetos nuevos; brechas N12/N13 | **PASS** en los conteos | **C-2** y **C-3** (§8) |

#### 10.A.1 Límites de lo probado

1. **No es una verificación de la implementación.** El prototipo de `crear`/`ejecutar` es `SECURITY INVOKER` y corre como `authenticated` sobre una tabla de laboratorio (`lab_int`); los objetos de PR-13 son funciones con la **forma** del contrato para el recuento del preflight. No se ejercitaron las políticas RLS reales de `propietario_rpc` ni sus privilegios de columna dentro de una función `SECURITY DEFINER` (pruebas SD-01, ES-02, ES-03).
2. **No se probaron:** `ejecutar` frente a `cancelar` simultáneos (CC-02); intenciones distintas sobre el mismo stock por la vía de intenciones (CC-03); replay de `crear` con payloads equivalentes tras normalizar (PL-11); sesión vencida durante la operación (PW-05); aislamiento por actor y empresa de las RPC nuevas (NG-04); `SELECT` por columna de `authenticated` frente a la excepción A (ES-06/N-COL); recuperación tras respuesta perdida por la vía real (RC-01, PW-01).
3. `40001` y `40P01` se **simularon** con `RAISE`; no se provocó un deadlock real. Se verificó su propagación y su mapeo HTTP.
4. Una corrida por premisa, salvo PR-09 (2), PR-11 (10 rondas por modo) y PR-12 (3 repeticiones). Las mediciones de tiempo dependen del reloj y de la máquina local.
5. Versiones concretas: PostgreSQL 17.11, PostgREST v16.4, GoTrue v2.197.0. No se promete el mismo comportamiento en versiones futuras; un cambio de versión exige repetir PR-04, PR-05, PR-06 y PR-10.
6. La copia modificada del preflight y la variante B son experimentos; no son un cambio aprobado de T3-01.

### 10.B Pruebas — DESPUÉS de la implementación (obligatorias para la aceptación técnica)

**Estructura, permisos e inventarios (pgTAP)**

| Id | Caso |
|---|---|
| ES-01 | Tabla: columnas, tipos, `NOT NULL`, PK por `(empresa, actor, id)`, FK a `perfiles`, **FK compuesta `(empresa_id, operacion_id, tipo, actor_id)`**, `CHECK` de tipo, estado, payload objeto, `vence_en > creado_en` y coherencia estado/campos |
| ES-02 | ACL **exacta** de tabla y de columnas: `PUBLIC`, `anon`, `authenticated`, `service_role` y `lector_perfiles_rpc` sin ningún privilegio de tabla **ni de columna (incluido `SELECT` por columna)**; `propietario_rpc` con `SELECT` de tabla, `INSERT` en exactamente 6 columnas y `UPDATE` en exactamente 4, **sin** `INSERT`/`UPDATE` de tabla, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER` ni `MAINTAIN` (cubre las brechas **N12** y **N13** del preflight, §8.2.1 g); owner `postgres`; RLS habilitada sin `FORCE` |
| ES-03 | Las 3 políticas: nombre, comando, rol, hashes de `USING`/`WITH CHECK`; ninguna política extra; ninguna para `authenticated` |
| ES-04 | Las 8 funciones: owner, lenguaje, `SECURITY DEFINER`/`INVOKER`, `proconfig`, ACL, `EXECUTE` solo `authenticated`, sin sobrecargas; endurecimiento pg_temp |
| ES-05 | **Revisión estática del cuerpo de las funciones privadas y de las políticas:** cero `WHEN OTHERS`; cero `EXECUTE` dinámico y cero `format()` que arme sentencias; cero referencias a `now()` en la comprobación de admisión; **cero referencias a `auth.uid()` o al esquema `auth`** (R-12); `p_payload` declarado `jsonb` en fachada y privada (R-11); `crear` contiene `pg_advisory_xact_lock` antes de la primera lectura de `intenciones_operacion` y ningún `pg_advisory_lock` de sesión (R-13) |
| ES-06 | **Preflight T3-01 actualizado** pasa con 48 firmas, 24 `SECURITY DEFINER`, 12 relaciones y **36** políticas, con la **excepción A exacta** de §8.2.1 f, y **falla** (pruebas negativas, cada DDL en `BEGIN … ROLLBACK`) si: falta o sobra una función; aparece una sobrecarga de un nombre nuevo (lista 3.4); cambia un owner, una ACL o un `proconfig`; aparece o falta una política; cambia un hash; `anon` o `authenticated` obtienen **cualquier** privilegio de tabla sobre `intenciones_operacion`; **N-COL:** `authenticated` obtiene `SELECT` **por columna** sobre `intenciones_operacion`; `service_role` obtiene cualquier privilegio; **y** si se le quita `SELECT` a `authenticated` en **otra** de las 11 tablas (la excepción no se generaliza) |
| ES-09 | **Identidad:** `privado.usuario_actual()` sin cambios (cuerpo, owner, ACL); las 4 privadas devuelven `PT401` sin claims y `PT403` con perfil inexistente, inactivo o vendedor/piloto; la empresa y el actor almacenados son los de `perfiles`, aunque el payload intente incluir otros (rechazado por la validación de claves) |
| SD-01 | **Interacción con `SECURITY DEFINER` real:** las 4 privadas, ejecutadas como `propietario_rpc` vía las fachadas, leen y escriben `intenciones_operacion` solo a través de las 3 políticas (con la política de `UPDATE` ausente, el `UPDATE` no afecta filas; con `actor_id` ajeno, `INSERT` viola `WITH CHECK`); `ejecutar` llama a las RPC de stock privadas con su propio control de identidad; ninguna escritura posible fuera de las columnas otorgadas |
| ES-07 | `operaciones` **sin cambios**: su inventario de restricciones y políticas sigue idéntico (`stock_ingreso.test.sql:155-170`) |
| ES-08 | Las RPC de stock y de jornadas sin cambios: la suite vigente pasa sin regresiones |

**`crear`: validación exacta del payload (hallazgo 4)**

| Id | Caso | Esperado |
|---|---|---|
| PL-01 | Payload válido por cada tipo | 1 fila `pendiente`; el `payload` almacenado **es el reconstruido** |
| PL-02 | Payload con claves extra, faltantes, de otro tipo, o mezcla de claves de dos tipos | `PT400 intencion_payload_invalido`; sin fila |
| PL-03 | Payload que no es objeto: arreglo, cadena, número, `null`, `{}` | `PT400`; sin fila |
| PL-04 | `cantidad`: `0`, `-1`, `1.5`, `1.0`, `"5"`, `true`, `null`, `2147483648`, enteros de más de 10 dígitos, ceros a la izquierda | `PT400`; sin fila |
| PL-05 | `cantidad` `2147483647` y `1` | Aceptadas; almacenadas como `integer` exacto |
| PL-06 | `producto_id`/`ubicacion_origen_id`: no UUID, mayúsculas, con llaves, vacío, número, `null` | `PT400` |
| PL-07 | `motivo`: espacios alrededor, solo blancos, `null`, 500 y 501 caracteres, Unicode | Normalizado por `btrim`; blancos → `null`; 501 → `PT400` |
| PL-08 | `motivo_codigo` con espacios o vacío o de más de 40 caracteres | `PT400`; un valor fuera del catálogo con forma válida se acepta aquí y produce `rechazada` al ejecutar |
| PL-09 | Un payload con datos extra **nunca** queda almacenado (se compara lo almacenado con la entrada) | Lo almacenado contiene solo las claves del tipo |
| PL-10 | Payload mayor al tamaño máximo | `PT400` |
| PL-11 | `crear` repetido con el mismo id y un payload **equivalente tras normalizar** | Mismo id, 1 fila |
| PL-12 | `crear` repetido con el mismo id y otro tipo o payload | `PT409 intencion_conflicto`; fila intacta |
| PL-13 | `crear` no revela la existencia de productos ni ubicaciones (no los consulta) | Mismo resultado para ids existentes, ajenos e inexistentes |

**`ejecutar`, `cancelar`, errores**

| Id | Caso | Esperado |
|---|---|---|
| EJ-01 | Éxito por tipo | `confirmada`; 1 `operaciones` con `idempotency_key = id`; 1 movimiento; saldo `S0 ± q` |
| EJ-02 | `ejecutar` repetido | Mismo resultado; 1 movimiento |
| EJ-03 | Rechazo de negocio de cada código de la lista cerrada | `rechazada` + código; **sin** fila en `operaciones` ni `movimientos_stock` |
| EJ-04 | `40001`, `40P01`, `PT401`, `PT403`, `PT500`, `42501` y un SQLSTATE inesperado dentro de la ejecución | Se relanza; la intención sigue `pendiente`; **nunca** HTTP 200 |
| EJ-05 | Un código `PT409` **fuera** de la lista cerrada | Se relanza; sigue `pendiente` |
| EJ-06 | `cancelar` pendiente; luego `ejecutar` | `cancelada`; `PT409 intencion_cancelada`; 0 movimientos |
| EJ-07 | `cancelar` una `confirmada` | `PT409 intencion_ya_confirmada`; operación intacta |
| EJ-08 | Cambio de rol o inactivación entre crear y ejecutar | `PT403`; sigue `pendiente` |

**Vencimiento (hallazgo 1)**

| Id | Caso | Esperado |
|---|---|---|
| VE-01 | `ejecutar` con `clock_timestamp() >= vence_en` | `PT409 intencion_vencida`; 0 efectos; la fila no cambia |
| VE-02 | Ejecución **admitida** antes de `vence_en` que espera un lock de stock y completa **después** | `confirmada`; `resuelto_en > vence_en`; 1 movimiento |
| VE-03 | Sesión que esperó el `FOR UPDATE` y despierta tras `vence_en` encontrando la intención `confirmada` por la primera | Devuelve lo almacenado; no ejecuta otra vez |
| VE-04 | Sesión que esperó el `FOR UPDATE` y despierta tras `vence_en` encontrándola aún `pendiente` | `PT409 intencion_vencida` |
| VE-05 | `now()` atrasado frente a `clock_timestamp()` en una transacción larga | La admisión usa `clock_timestamp()` |
| VE-06 | `listar` calcula `vencida` con el reloj; `cancelar` de una vencida pendiente | `vencida = true`; pasa a `cancelada` |

**Referencia, P15 y límites**

| Id | Caso | Esperado |
|---|---|---|
| RF-01 | La FK compuesta rechaza enlazar una operación de **otro actor**, de **otro tipo** o de **otra empresa** | Violación de FK |
| RF-02 | Intención `pendiente` con `operacion_id` nulo | Permitido |
| RF-03 | **Invariante P15:** para toda intención `confirmada`, `operaciones.idempotency_key = intenciones_operacion.id` (consulta global) | 0 violaciones |
| RF-04 | `idempotency_key` no aparece en `movimientos_stock` ni en documentos hijos | Cumple |
| LM-01 | Más de 20 pendientes vigentes por actor | `PT429` |
| LM-02 | Más de 120 creaciones en una hora; el replay de un id existente no cuenta | `PT429`; el replay no cuenta |
| LM-03 | `listar`: tope de 100 filas; `p_desde` nulo = 7 días; `p_desde` anterior a 30 días se recorta; las pendientes vigentes siempre incluidas | Cumple |
| LM-04 | Retención indefinida: no existe `DELETE` ni política de `DELETE` | Cumple |
| LM-05 | **Concurrencia del tope de pendientes** (C-1): N ≫ tope `crear` distintos y simultáneos del mismo actor por HTTP real, al menos 10 rondas | Exactamente `tope` filas `pendiente` en **todas** las rondas; el resto `429 PT429`; ningún `40P01` |
| LM-06 | **Concurrencia del tope por hora** (C-1), mismo arnés | Exactamente `tope` creaciones en la última hora en todas las rondas |
| LM-07 | Serialización acotada: `crear` concurrentes de **actores distintos** no se esperan entre sí; replay de un id existente con el tope alcanzado; `crear` dentro de una transacción `REPEATABLE READ` | Sin espera cruzada; el replay devuelve el id (sin `PT429`); `PT500` por aislamiento distinto de `READ COMMITTED` |

**Concurrencia (arnés, stack aislado)**

| Id | Caso | Esperado |
|---|---|---|
| CC-01 | Dos `ejecutar` simultáneos de la misma intención | Uno ejecuta; el otro espera y devuelve lo mismo; 1 movimiento |
| CC-02 | `ejecutar` y `cancelar` simultáneos, en ambos órdenes, con barrera y varias rondas (no probado en el laboratorio de premisas) | Gana exactamente uno; nunca «ejecutada y cancelada»; si gana `cancelar`, 0 movimientos y `ejecutar` → `PT409 intencion_cancelada`; si gana `ejecutar`, 1 movimiento y `cancelar` → `PT409 intencion_ya_confirmada` |
| CC-03 | Intenciones distintas sobre el mismo producto y ubicación | Sin sobreventa ni `40P01`; orden intención → stock |
| CC-04 | Dos `crear` simultáneos con el mismo id | 1 fila |
| CC-05 | Aislamiento: `READ COMMITTED` declarado; con otro nivel, las RPC de débito siguen fallando cerradas como hoy (P13-stock) | Sin cambios |
| RC-01 | **Recuperación tras respuesta perdida** (base, sin interfaz): `ejecutar` confirma y la conexión del cliente se corta antes de leer la respuesta; nueva sesión del mismo usuario → `listar` y `ejecutar` del mismo id. Lo mismo con `crear` | `listar` muestra `confirmada` con su `operacion_id`; `ejecutar` repetido devuelve lo almacenado; 1 operación y 1 movimiento en total. Para `crear`: el replay devuelve el id y hay 1 fila |

**Seguridad negativa (Data API, sin la interfaz)**

| Id | Caso | Esperado |
|---|---|---|
| NG-01 | `anon` en las 4 RPC | `42501` |
| NG-02 | Vendedor/piloto en `crear` de tipos de stock | `403 PT403` |
| NG-03 | Usuario inactivo | `403 PT403` |
| NG-04 | Otra empresa / otro actor de la misma empresa: `ejecutar`, `cancelar`, `listar` | `404 PT404`, indistinguible de un id inexistente |
| NG-05 | **Acceso directo** a `/rest/v1/intenciones_operacion` (`GET`, `POST`, `PATCH`, `DELETE`, también con `select=` de columnas) como `anon` y como `authenticated` (dueño, encargado, vendedor) | `42501` (401 `anon` / 403 autenticado) en todos los casos; nunca filas ni un `200 []` (alternativa A: la denegación es por privilegio, no por política) |
| NG-09 | **Acceso por las fachadas:** las 4 RPC funcionan para dueño y encargado sin ningún privilegio de tabla de `authenticated`; las privadas no son invocables directamente por `anon` ni `service_role` | Funcionan por fachada; `42501` en las demás vías |
| NG-10 | **Conservación de errores por HTTP:** un error no listado dentro de `ejecutar` (p. ej. `PT500 stock_error_interno`, `PT409` fuera de la lista) llega al cliente con el **mismo** `code`, `message`, `details` y `hint` que produce la RPC de negocio llamada directamente | Idénticos; la intención sigue `pendiente` |
| NG-06 | `service_role` | Sin `EXECUTE` ni privilegios |
| NG-07 | Payload alterado entre `crear` y `ejecutar` (no hay vía: `ejecutar` solo recibe el id) y replay de `crear` con otro payload | `PT409 intencion_conflicto` |
| NG-08 | Llamada directa a la RPC de negocio con el id de la intención, mismo payload / distinto | Replay → `confirmada`; distinto → `rechazada` (conflicto); sin duplicar |

**Vitest y Playwright**

| Id | Caso |
|---|---|
| VT-01 | Protocolo crear → ejecutar → recuperar; `ejecutar` envía solo el id |
| VT-02 | P13 en `crear`, `ejecutar` y `cancelar`: máximo 3 intentos, mismo id y payload; `PTxxx` nunca; `55P03` y `57014` no reintentan |
| VT-03 | `rechazada` se muestra por código y no se reintenta; `PT401`/`PT403` se muestran como errores de sesión/permiso, nunca como rechazo de negocio |
| VT-04 | Sin respuesta tras 3 intentos → se consulta con `listar` y se muestra el estado real |
| VT-05 | Restricción de interfaz ante pendientes; dos acciones idénticas → dos ids |
| VT-06 | Cambio de usuario descarta el controlador y su id en memoria |
| VT-07 | **Ninguna** referencia a `localStorage`, `sessionStorage` o `indexedDB` en el código nuevo |
| PW-01 | Pérdida de respuesta de `ejecutar` y de `crear` → recarga / cierre / otro contexto del mismo usuario → un solo movimiento, lecturas reales a la base |
| PW-02 | `cancelar` con solicitud retrasada → 0 movimientos |
| PW-03 | Solicitud retrasada tras `vence_en` → `PT409`; ejecución admitida antes que completa después → un movimiento |
| PW-04 | Otro usuario en el mismo dispositivo no ve intenciones ajenas |
| PW-05 | Sesión vencida y reingreso: `listar` recupera el estado real |
| PW-06 | PC y Android (412×915); `peso` con `1,250 kg` → un movimiento de 1250 g |

### 10.C Criterios de aceptación globales

1. **Antes de aprobar:** las premisas PR-01 a PR-13 se verificaron (**cumplido**: 13 PASS, §10.A), la ADR se corrigió (**cumplido en v0.3**: C-1 a C-8) y el humano resolvió las decisiones (**cumplido**: aprobación del 06/11/2026, §0.2). Los criterios 2 a 10 son de la **aceptación técnica** futura.
2. **Después de implementar:** todos los casos de §10.B pasan en un stack aislado, con códigos de salida y resultados guardados fuera del repositorio.
3. En ningún caso de pérdida de respuesta con recarga, cierre o cambio de dispositivo el stock se mueve más de una vez **cuando el usuario sigue el flujo de resolución**; los casos fuera de ese flujo (R-1, R-6) quedan documentados con su comportamiento real.
4. Ninguna lectura ni ejecución cruza actor o empresa.
5. Las RPC de stock y de jornadas, `operaciones`, `movimientos_stock` y los permisos vigentes **no cambian**, y su suite pasa sin regresiones.
6. Cero uso de almacenamiento del navegador; cero SQL dinámico; cero `WHEN OTHERS`; cero conversión de `PT401`/`PT403`/`42501` en HTTP 200.
7. Ninguna ejecución se admite después de `vence_en`; ninguna ejecución admitida se interrumpe por el vencimiento.
8. El preflight T3-01 actualizado pasa (48/24/12/36) con la excepción A exacta y falla ante las pruebas negativas, incluida N-COL; las otras 11 tablas conservan su contrato; `service_role` no recibe privilegios nuevos.
10. Los topes por actor son exactos bajo concurrencia (LM-05, LM-06) y ninguna función nueva llama a `auth.uid()` (ES-05).
9. Security review formal favorable y auditoría independiente (Codex y OpenCode) sobre el hash, con aprobación humana.

## 11. Riesgos residuales

| Id | Riesgo | Mitigación / estado |
|---|---|---|
| R-1 | **Dos intenciones idénticas creadas a propósito** se ejecutan ambas | No evitable (son legítimas e indistinguibles). Visibles y con restricción de interfaz |
| R-2 | **Bypass:** llamada directa a la RPC de negocio con una clave nueva | **Aceptado temporalmente** en la Fase 1 (D-IDEM-8, aprobado el 06/11/2026); se cierra solo con la Fase 2 técnica (D-IDEM-13, decisión futura) |
| R-3 | **Mayor superficie `SECURITY DEFINER`** (4 funciones privadas + 4 fachadas) | Security review obligatoria (`AGENTS.md` §2.4) |
| R-4 | **Dos viajes de red por operación** (más latencia con señal débil) | Aceptado; `crear` y `ejecutar` son idempotentes |
| R-5 | **Cambio de forma de respuesta** de `ejecutar` ante rechazos de negocio | **Aprobado** (D-IDEM-10), solo lista cerrada. `PT401`/`PT403`/`42501` no cambian |
| R-6 | Solicitud retrasada de una intención aún pendiente que el usuario **no canceló**, junto con una intención nueva idéntica | Ambas pueden ejecutarse. Visibles; restricción de interfaz; no es garantía del servidor |
| R-7 | Premisas PR-01 a PR-13 | **Verificadas** (13 PASS, §10.A) con los límites de §10.A.1; lo no probado pasa a §10.B |
| R-8 | Dependencia de T3-01 (inventario cerrado: 40→48, 20→24, 11→12, 33→36/37) | D-IDEM-7 |
| R-9 | Una ejecución **admitida** antes de `vence_en` confirma después de `vence_en` | Es el comportamiento definido (§5.6); el plazo limita la admisión, no la finalización. La RPC de negocio revalida stock y estado |
| R-10 | Crecimiento de la tabla (retención indefinida) | Una fila por operación; retención indefinida aprobada (D-IDEM-3). Una purga futura exige nueva decisión y migración hacia adelante |
| R-11 | `motivo` sin tope en la RPC de negocio llamada directamente | Fuera de esta ADR (D-IDEM-11) |
| R-12 | Extender el mecanismo a ventas/cobros abre permisos indebidos | §9.1: requiere ADR propia por dominio |
| R-13 | **Segunda representación de la clave (P15)** | Excepción **aprobada** y acotada (§7.1); controles de §7.1 e invariante RF-03 obligatorios en la implementación |
| R-14 | La invariante `operaciones.idempotency_key = intenciones_operacion.id` no la expresa una FK | Garantizada por `ejecutar` (única escritora de `confirmada`) y comprobada por pruebas (RF-03) |
| R-15 | Un auxiliar de validación ampliaría el inventario más allá de 24/48 | La validación va en línea; si fuera inevitable, el inventario cambia y se decide expresamente |
| R-16 | `1e3` llega a `jsonb` ya normalizado como `1000` y se acepta | Comportamiento declarado (PR-05, C-5); la cantidad almacenada es un entero |
| R-17 | **Topes por actor bajo concurrencia** | Corregido en diseño con el lock de nivel 0 (C-1); comprobado solo con un prototipo invoker; LM-05/LM-06 sobre la implementación real |
| R-18 | El lock por actor **serializa** los `crear` del mismo actor (varios dispositivos a la vez) | Aceptado: `crear` es corto y no toma otros locks; actores distintos no se esperan |
| R-19 | Sin normalización Unicode: un replay con otra normalización del `motivo` da `PT409 intencion_conflicto` | Falla cerrado, sin duplicar; el cliente reenvía el mismo objeto (C-7) |
| R-20 | **Excepción A en el preflight** mal escrita podría debilitar el control de las otras tablas o dejar pasar un `SELECT` por columna | Excepción por nombre literal, complemento de columnas (§8.2.1 f) y negativos ES-06 (incluidos N-COL y «la excepción no se generaliza»). El complemento de columnas **no se probó** en laboratorio |
| R-21 | **Brechas N12/N13 del preflight** (ACL de `propietario_rpc` sobre tablas no verificada) | Para esta tabla, pgTAP ES-02. Para las 11 tablas existentes no se evaluó: se informa al humano, fuera del alcance de esta ADR |
| R-22 | Cambio de versión de PostgREST/PostgreSQL altera la forma de respuesta o la normalización de `jsonb` | Repetir PR-04, PR-05, PR-06 y PR-10 al actualizar versiones |

## 12. Decisiones humanas (resueltas el 06/11/2026)

> Todas las decisiones de la tabla, salvo D-IDEM-13, fueron **aprobadas por el responsable del proyecto el 06/11/2026** como paquete (§0.2). La aprobación es **normativa**: ninguna está implementada. Un agente no puede modificarlas.

| # | Id | Decisión | Valor aprobado | Estado |
|---|---|---|---|---|
| 1 | **D-IDEM-1** | Arquitectura | **C-mínima** (con C-1 a C-8 de v0.3) | **Aprobada** |
| 2 | **D-IDEM-2** | Excepción a P15 e instrumento normativo | Extensión de §7.1; remisión en ADR-001 §18.3; nota en `BLUEPRINT.md` §7.9.1 y entidad en §8 | **Aprobada** |
| 3 | **D-IDEM-15** | Permisos de `authenticated` | **Alternativa A**: sin `SELECT` ni otro acceso directo; excepción nominal en el preflight + N-COL | **Aprobada** |
| 4 | **D-IDEM-10** | Rechazos definitivos de negocio | Estado `rechazada` con **HTTP 200**, solo lista cerrada de §5.7; `PT401`/`PT403`/`42501` siempre como error | **Aprobada** |
| 5 | **D-IDEM-5a** | Vencimiento | **24 h** desde la creación, límite de **admisión**, con `clock_timestamp()` | **Aprobada** |
| 6 | **D-IDEM-3** | Retención | **Indefinida, sin purga** | **Aprobada** |
| 7 | **D-IDEM-5b** | Pendientes vigentes por actor | **≤ 20**; `PT429`; el replay no cuenta | **Aprobada** |
| 8 | **D-IDEM-5d** | Creaciones por actor | **≤ 120 por hora**; `PT429`; el replay no cuenta | **Aprobada** |
| 9 | **D-IDEM-5c** | Listado | **100 filas**; `p_desde` nulo = **7 días**; ventana máxima **30 días**; pendientes vigentes siempre incluidas | **Aprobada** |
| 10 | **D-IDEM-11** | `motivo` | **≤ 500 caracteres** en la vía de intenciones (la RPC directa queda sin tope; fuera de esta ADR) | **Aprobada** |
| 11 | **D-IDEM-12** | Visibilidad | **Solo el actor creador** | **Aprobada** |
| 12 | **D-IDEM-8** | Bypass por RPC directas de stock | **Aceptado temporalmente** durante la Fase 1 (R-2) | **Aprobada** |
| 13 | **D-IDEM-7** | Secuencia | Implementación **después del cierre de T3-01** | **Aprobada** |
| 14 | **D-IDEM-14** | Numeración | **010** | **Aprobada** |
| 15 | **D-IDEM-0** | B-01 | **Permanece abierta** hasta completar la recuperación | **Aprobada** |
| 16 | **D-IDEM-16** | Tamaño del payload | **`octet_length(p_payload::text) <= 4096`** | **Aprobada** |
| 17 | **D-IDEM-13** | Fase 2 técnica: revocar `EXECUTE` directo de las RPC de stock | — | **Pendiente** (decisión futura, ADR o enmienda propia) |

**Condiciones previas a escribir una sola línea de SQL:** cierre de T3-01; autorización humana expresa de la tarea de implementación; rama propia, preámbulo completo (`AGENTS.md` §1.3) y stack descartable para las pruebas. Las premisas PR-01 a PR-13 ya están verificadas (con los límites de §10.A.1) y las decisiones de esta tabla, salvo D-IDEM-13, están aprobadas.

## 13. Qué esta ADR no hace

- No implementa nada ni autoriza implementar: su aprobación es normativa (§0.2).
- No cambia el estado de ADR-001 ni de ninguna otra ADR; en ADR-001 solo agrega una nota de remisión en §18.3.
- No modifica las migraciones, las RPC, los permisos, RLS ni T3-01; en el Blueprint solo registra la excepción a P15 y la entidad (v2.6).
- No autoriza staging ni producción.
- No resuelve el límite de longitud del `motivo` en la RPC de negocio llamada directamente (solo en la vía de intenciones).
- No introduce Fase 2 del producto (ventas, cobros, retiros, rendiciones).

## 14. Referencias

- `BLUEPRINT.md` v2.5: §3, §6, §7.4, §7.9.1, §7.9.6, §7.9.7, §8, §13.
- ADR-001 §18.3 (P12/P13/P14/P16/P17-stock), §18.4 (jornadas); ADR-004, ADR-005, ADR-007, ADR-009.
- `supabase/migrations/20261025021032_stock_operaciones_ingreso.sql`, `20261025033454_stock_cuarentena_merma.sql`, `20261030120000_jornadas_esquema.sql`.
- `supabase/scripts/validar_topologia_propietario_rpc.sql` (preflight T3-01).
- Análisis D-IDEM (fuera del repositorio): `../evidencias-entrega-b/d-idem-supabase/` (`INFORME_D_IDEM.md`, `ALTERNATIVAS.md`, `PROPUESTA_RECOMENDADA.md`, `REFINAMIENTO_C1.md`, `MATRIZ_PRUEBAS.md`, `DECISIONES_PENDIENTES.md`). Laboratorio de premisas: `../evidencias-entrega-b/d-idem-supabase/laboratorio-premisas/` (`README.md`, `RESULTADOS_PR01_PR13.md`, `scripts/`, `logs/`, `MANIFIESTO.sha256`). Estos documentos son material de trabajo no normativo; lo vinculante es el texto de esta ADR (aprobada el 06/11/2026).
