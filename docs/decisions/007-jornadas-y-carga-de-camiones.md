# ADR-007 — Jornadas y carga de camiones

**Fecha:** 29/10/2026
**Estado:** APROBADA (aprobación humana explícita del dueño del proyecto, 29/10/2026). Las decisiones comerciales de apertura, fecha operativa, zona horaria, vendedor, reasignación, corrección de jornadas abiertas por error, carga, descarga y salida se confirmaron el 29/10/2026.
**Versión:** 1.0
**Relación:** precisa `BLUEPRINT.md` §7.2, §7.4, §7.5, §7.9, §8 y §9 para la apertura de jornada, la asignación y reasignación de vendedor, la corrección de una jornada abierta por error, la carga, la descarga previa a la salida y la confirmación de salida. Complementa ADR-005 (unidad mínima, D-R2) y no modifica ADR-005 ni ADR-006. El contrato técnico de las RPC (P10, P12–P17) **no** forma parte de esta ADR: se propone por separado como anexo §18.4 de ADR-001, que sigue siendo **PROPUESTA TÉCNICA NO APROBADA**.

> **Alcance.** Reglas de negocio del primer bloque operativo del sistema definitivo (Supabase). No autoriza SQL, migraciones, RPC, RLS, permisos ni producción por sí misma: su implementación requiere además la aprobación del anexo §18.4 de ADR-001, una tarea autorizada con su preámbulo (`AGENTS.md` §1.3) y su security review (`AGENTS.md` §2.4). No modifica ADR-001 (APROBADA PARA VALIDACIÓN CONTROLADA). P11 sigue vigente: `service_role` no recibe privilegios sobre jornadas, sus historiales ni sus operaciones.

---

## 1. Contexto

El Blueprint aprueba la jornada (§8), su unicidad por `(empresa_id, camion_id, fecha)` incluso cerrada (§7.5), la secuencia de seis estados `abierta → cargada → en_reparto → ventas_finalizadas → regreso_contado → cerrada` sin transiciones implícitas (§7.5), el movimiento `carga` depósito → camión (§7.4) y los permisos de §9: el dueño administra jornadas, el encargado administra cargas y el vendedor ve su jornada. No define el evento de cada transición, si la carga es única o incremental, cómo se corrige una carga o una apertura errónea, las precondiciones del camión y del vendedor ni la trazabilidad de una reasignación.

La ubicación de stock de un camión es **una por camión, no por jornada**: el `jornada_id` de cada movimiento identifica a qué jornada pertenece.

## 2. Decisión

### 2.1 Apertura

1. Dueño o encargado abre la jornada indicando camión, fecha operativa y vendedor. La jornada nace en `abierta`. El instante real de creación se registra con hora del servidor (UTC).
2. **Fecha operativa:** la elige quien abre. Sólo se admite el **día operativo actual o una fecha futura**; una fecha pasada se rechaza.
3. **Zona horaria operativa: `America/Argentina/Tucuman`** (decisión humana, 29/10/2026). El **día operativo actual** es la fecha calendario del negocio calculada en esa zona a partir de la hora del servidor (confirmado por decisión humana, 29/10/2026). Un corte especial de jornada sigue pendiente (§3, P-1).
4. Unicidad `(empresa_id, camion_id, fecha)`, incluso si la jornada existente está cerrada (§7.5).
5. No se abre una jornada para un camión que tenga otra jornada, de cualquier fecha, en un estado distinto de `cerrada`.
6. El camión debe estar **activo**.
7. El vendedor cumple §2.3.1 y §2.3.2.

### 2.2 Estados de este tramo

| Transición | Evento explícito | Quién |
|---|---|---|
| (creación) → `abierta` | apertura | dueño, encargado |
| `abierta` → `cargada` | **la primera carga válida** de la jornada; no existe un comando separado de «confirmar carga» | dueño, encargado |
| `cargada` → `cargada` | cargas y descargas posteriores (sin cambio de estado) | dueño, encargado |
| `cargada` → `en_reparto` | confirmación expresa de salida | dueño, encargado |

- Ningún otro comando cambia el estado en este bloque. No hay transición hacia atrás: si las descargas dejan el camión vacío, la jornada sigue `cargada`.
- **La confirmación de salida exige carga neta positiva:** la suma, por producto, de las cargas menos las descargas **de esa jornada** debe ser mayor que cero en al menos un producto. Si las descargas dejaron el camión sin mercadería, la salida se rechaza.
- Después de `en_reparto` no se admiten cargas, descargas, reasignaciones ni correcciones ordinarias.

### 2.3 Vendedor y reasignación

1. Toda jornada tiene un vendedor asignado desde la apertura: un **perfil activo de la misma empresa**, con rol `dueno`, `encargado` o `vendedor_piloto`.
2. **Una persona tiene como máximo una jornada por fecha.** La restricción se aplica al vendedor asignado vigente y **no se libera al cerrar la jornada**.
3. La reasignación se permite sólo en `abierta` o `cargada`, por dueño o encargado, como comando propio, idempotente. El vendedor nuevo debe cumplir §2.3.1 y §2.3.2 para la fecha de la jornada. El vendedor anterior deja de ocupar esa fecha por esa jornada.
4. Cada reasignación queda en un **historial append-only de reasignaciones**: jornada, vendedor anterior, vendedor nuevo, operación, actor y hora del servidor. Sin UPDATE ni DELETE. Este historial **no** registra cambios de fecha ni de camión (§2.4).
5. El vendedor asignado al confirmar la salida queda fijado para la jornada. La definición de «participante» a efectos de P8 sigue pendiente (§3, P-2).

### 2.4 Corrección de una jornada abierta por error

1. Dueño o encargado puede corregir la **fecha**, el **camión** o ambos de una jornada, sólo si:
   - está en estado `abierta`; y
   - no tiene ningún movimiento de stock asociado (defensa en profundidad: en `abierta` no puede haberlo).
2. La corrección exige **motivo** obligatorio y es **idempotente**.
3. Sobre los valores nuevos se revalidan todas las condiciones de la apertura:
   - el par `(empresa_id, camion_id, fecha)` nuevo debe estar libre, incluso frente a jornadas cerradas;
   - la fecha nueva es el día operativo actual o futura (§2.1.2 y §2.1.3);
   - el camión nuevo está activo y no tiene otra jornada sin cerrar (§2.1.5 y §2.1.6);
   - el vendedor asignado no tiene otra jornada en la fecha nueva (§2.3.2).
4. Si se rechaza, la jornada queda sin cambios.
5. El par anterior queda libre: como la jornada nunca tuvo carga ni salida, esto no habilita una segunda salida del camión ese día (§7.5).
6. Cada corrección queda en un **historial append-only de correcciones de jornada**, **separado** del de reasignaciones: jornada, fecha y camión anteriores, fecha y camión nuevos, motivo, operación, actor y hora del servidor. Sin UPDATE ni DELETE.
7. La corrección no cambia el estado ni el vendedor. El vendedor se cambia sólo por reasignación (§2.3).

### 2.5 Carga

1. Movimiento `carga`: depósito propio → ubicación del camión de la jornada, con `jornada_id`. Lo registran dueño o encargado, en `abierta` o `cargada`.
2. Cada operación de carga es **atómica**: se registra completa o se rechaza sin efectos parciales.
3. **Una línea por producto** en cada operación. **Sólo productos activos** de la empresa. Cantidades enteras positivas en unidad mínima: unidades, o gramos con el peso efectivamente cargado (ADR-005 D-R2).
4. No se carga más que el saldo del depósito (el depósito nunca queda negativo) ni mercadería en cuarentena (§7.2).
5. **Stock residual:** antes de la **primera** carga de la jornada, el stock total del camión debe ser cero. Si no lo es, la carga se rechaza. Ningún saldo se manipula para habilitarla. Las cargas posteriores de la misma jornada no repiten esta comprobación.
6. Las cargas son incrementales: varias operaciones antes de la salida, cada una identificable y auditada.
7. El camión debe estar activo (§2.7).

### 2.6 Descarga antes de la salida

1. Movimiento nuevo `descarga`: ubicación del camión de la jornada → depósito propio, con `jornada_id`. Lo registran dueño o encargado, sólo en `cargada`, con **motivo obligatorio**.
2. Por producto, la cantidad descargada no puede superar lo cargado neto **de esa jornada** (cargas − descargas) ni el saldo del camión.
3. Una línea por producto en cada operación; atómica. Se admite descargar un producto que fue dado de baja después de cargarlo.
4. Es compensatoria: **no edita ni elimina** movimientos previos (§7.4) y no reemplaza al `retorno` de fin de jornada.

### 2.7 Camión dado de baja durante una jornada

La baja de un camión no se bloquea. Un camión inactivo no admite aperturas, cargas ni ser destino de una corrección. Una jornada ya abierta de ese camión puede descargarse, confirmar su salida y seguir su curso hasta el cierre.

### 2.8 Lectura

En este bloque, el vendedor lee **únicamente la fila de su jornada** (vendedor asignado vigente). No lee `movimientos_stock`, `stock_actual` ni los historiales: P10-stock no se modifica. La lectura de la mercadería que lleva el vendedor se decide en el bloque de ventas. Dueño y encargado leen las jornadas y los historiales de su empresa.

## 3. Pendientes

| # | Pendiente | Qué bloquea |
|---|---|---|
| P-1 | ~~Zona horaria del negocio~~ — **resuelto** el 29/10/2026: `America/Argentina/Tucuman` (§2.1.3). El **corte de jornada** de `BLUEPRINT.md` §15 «Fechas» sigue pendiente y no afecta a este bloque. | — |
| P-2 | **Participación y separación de funciones para el conteo** (F3): definición de participante a efectos de P8, incluido el vendedor anterior a una reasignación. | Nada en este bloque; se resuelve en el bloque de conteo. |
| P-3 | **Aprobación del anexo §18.4 de ADR-001** (P10, P12–P17 para jornadas), previa revisión independiente. | Toda la implementación SQL/RPC de esta ADR. |

## 4. Alternativas descartadas

| Alternativa | Motivo |
|---|---|
| Comando separado «confirmar carga» | Agrega un paso sin hecho de negocio propio; la carga ya es un evento explícito. |
| Comprobar stock cero en cada carga | Incompatible con la carga incremental. |
| Datos de reasignación o corrección en `operaciones` | `operaciones` no lleva datos de negocio (§7.9.1). |
| Un único historial para reasignaciones y correcciones | Son hechos distintos con datos distintos; se auditan por separado. |
| Corregir una carga con `retorno` | `retorno` es de fin de jornada (§7.4). |
| Editar o borrar movimientos de carga | El ledger es append-only (§7.4). |
| Cerrar una jornada vacía para anular una apertura errónea | Contradice §12 «No se puede cerrar sin conteo de regreso». |
| Corregir una jornada `cargada` | Ya tiene movimientos en la ubicación del camión; se corrige con descarga, no cambiando el camión. |
| Liberar la fecha del vendedor al cerrar su jornada | Decisión comercial: una persona, una jornada por fecha. |
| Ampliar P10-stock para que el vendedor lea el ledger | No es necesario en este bloque. |

## 5. Consecuencias

- **Modelo:** tabla `jornadas` (§8), dos historiales append-only (reasignaciones y correcciones; nombres definitivos en el diseño SQL), tipos de movimiento `carga` y `descarga`, y `jornada_id` con FK en `operaciones` y `movimientos_stock` (previsto en ADR-001 P17-stock). Ningún objeto se crea antes de la tarea de implementación autorizada.
- **Unicidades:** `(empresa_id, camion_id, fecha)` y `(empresa_id, vendedor_id, fecha)`, ambas vigentes incluso con la jornada cerrada.
- **ADR-001:** requiere el anexo §18.4 (P10, P12–P17 para jornadas), que debe incluir la RPC de corrección, el bloqueo del vendedor y el de los dos camiones cuando una corrección cambia el camión. P11 sin cambios.
- **Blueprint:** §7.4, §7.5, §8, §12 y §15 sincronizados con esta ADR en la versión 2.5. El PRD 0.13 acompaña a esa versión.
- **Prototipo:** las pantallas `localStorage` no se adaptan a esta ADR.

## 6. Fuera de alcance

Ventas, pagos, devoluciones, `retorno`, conteo, rendición, retiros, gastos, cierre, transiciones posteriores a `en_reparto`, reapertura, anulaciones, regularizaciones, lectura de mercadería por el vendedor, corte de jornada, producción.

## 7. Pruebas normativas

| # | Caso | Resultado |
|---|---|---|
| 1 | Segunda jornada del mismo camión y fecha, aunque la primera esté cerrada | Rechazo |
| 2 | Apertura con otra jornada del camión sin cerrar (otra fecha) | Rechazo |
| 3 | Apertura con fecha pasada; con el día operativo actual; con fecha futura (día operativo en `America/Argentina/Tucuman`) | Rechazo; aceptación; aceptación |
| 4 | Apertura o carga con camión inactivo | Rechazo |
| 5 | Vendedor con perfil inactivo, de otra empresa o inexistente | Rechazo |
| 6 | Vendedor `dueno`, `encargado` o `vendedor_piloto` activo de la empresa | Aceptación |
| 7 | Segunda jornada del mismo vendedor en la misma fecha, aunque la primera esté cerrada | Rechazo |
| 8 | Reasignación a un vendedor que ya tiene jornada esa fecha | Rechazo |
| 9 | Reasignación en `abierta` o `cargada` | Historial de reasignaciones con anterior y nuevo; el anterior queda libre para esa fecha |
| 10 | Corrección de fecha o camión en `abierta` sin movimientos, con motivo | Valores nuevos; historial de correcciones con anteriores y nuevos; historial de reasignaciones sin cambios |
| 11 | Corrección hacia un par `(camión, fecha)` ocupado (incluso por una jornada cerrada), hacia una fecha pasada, hacia un camión inactivo o con otra jornada sin cerrar, o con un vendedor ocupado en la fecha nueva | Rechazo sin cambios |
| 12 | Corrección en `cargada` o posterior, o sin motivo | Rechazo |
| 13 | Primera carga válida | Movimientos exactos depósito → camión; `abierta → cargada` |
| 14 | Carga posterior | Sin cambio de estado |
| 15 | Primera carga con stock residual en el camión | Rechazo sin efectos |
| 16 | Carga mayor que el depósito, de cuarentena, producto inactivo o repetido, cantidad 0, negativa o fraccionaria | Rechazo sin efectos |
| 17 | `1,250 kg` cargados | `1250` g en ambos lados |
| 18 | Descarga dentro de lo cargado neto de la jornada | Movimiento camión → depósito; la carga original intacta |
| 19 | Descarga mayor que lo cargado neto, sin motivo o en `abierta` | Rechazo |
| 20 | Salida desde `cargada` con carga neta positiva | `en_reparto` |
| 21 | Salida con carga neta cero después de descargas, o desde `abierta` | Rechazo |
| 22 | Carga, descarga, reasignación o corrección en `en_reparto` | Rechazo |
| 23 | Vendedor | Ve sólo su jornada; no ve el ledger, el stock ni los historiales |
| 24 | Baja del camión con jornada `cargada` | Descarga y salida permitidas; carga, apertura y corrección hacia ese camión rechazadas |

## 8. Fuentes

`BLUEPRINT.md` 2.4 (base de la decisión) §7.2, §7.4, §7.5, §7.9.1, §7.9.6, §7.9.7, §8, §9 (párrafo posterior a la tabla de roles, «incluso si una persona posee permisos adicionales»), §12 y §15, sincronizado en la 2.5; `docs/PRD.md` 0.12 §5, §6 y RF-04; ADR-001 §9–§14 y §18.3; ADR-005 §2.2 y D-R2; ADR-006. Decisiones humanas del 29/10/2026 (`docs/progress-log.md`).
