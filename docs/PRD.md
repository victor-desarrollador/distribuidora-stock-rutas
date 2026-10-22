# PRD — Sistema de Control de Stock y Rendición

**Proyecto:** Distribuidora de lácteos y fiambres (VM Digital Studio)
**Fecha:** 22/10/2026
**Versión:** 0.9
**Estado:** documento de producto. Complementa a `BLUEPRINT.md` v2.0; **no lo reemplaza**.
**Alcance de este documento:** describe el producto de Fase 1 y ordena los requisitos ya definidos en el Blueprint. No autoriza implementación.

---

## 0. Cómo leer este documento

- **Fuente de verdad:** `BLUEPRINT.md` v2.0, `AGENTS.md`, `CLAUDE.md`, `INVENTARIO_ETAPA_0.md`, las ADR vigentes y `docs/progress-log.md`. Si algo aquí contradice al Blueprint, manda el Blueprint hasta que una decisión aprobada lo cambie.
- **Referencias:** las citas del tipo «(Blueprint §7.4)» remiten a la sección correspondiente de `BLUEPRINT.md`.
- **Propuestas:** todo punto marcado como **PROPUESTA NO APROBADA** o **PROPUESTA TÉCNICA NO APROBADA** en el Blueprint se reproduce aquí **con esa misma marca** y **no es un requisito vigente**. No se implementa (AGENTS.md §3).
- **ADR:** **ADR-001 — Puerta de entrada SQL para operaciones privilegiadas** (versión 1.3, **APROBADA PARA VALIDACIÓN CONTROLADA**), **ADR-002 — Precios independientes de pieza y media pieza** (estado `superada` por ADR-003), **ADR-003 — Precio derivado de media pieza** (estado `aprobada`). ADR-001 resolvió P1/P19/P20; P2–P17 siguen pendientes y P18 es una decisión futura separada. Su estado permite validación sólo local/staging y no autoriza producción. ADR-002 es histórica y superada; ADR-003 establece que el precio de media pieza se deriva del de pieza completa (mitad, redondeada al peso entero, `.50` sube) y no es configurable.
- **Fase 2:** lo listado en Blueprint §5 permanece fuera de Fase 1.
- Este documento **no inventa** decisiones ausentes: donde falta definición, remite a «Decisiones pendientes» (§21), a «Dependencias de ADR» (§22) y al Blueprint §15.

### Categorías que este documento distingue

| Categoría | Significado | Dónde se marca |
|---|---|---|
| **Aprobado por el Blueprint** | Regla vigente de Fase 1. | Requisitos de §7 a §11 y §14. |
| **PROPUESTA NO APROBADA / PROPUESTA TÉCNICA NO APROBADA** | Regla del Blueprint marcada como propuesta; **no es requisito**. **No se implementa** (AGENTS.md §3). | Avisos en §7, §9, §10, §14 y §20. |
| **Decisión pendiente de ADR** | Punto **P2–P17** de ADR-001 v1.3; requiere **decisión humana**. P18 es futura y separada. | §11, §18, §21 y §22. |
| **Fase 2 / fuera de alcance** | Postergado por decisión confirmada; no integra la primera entrega. | §20. |

---

## 1. Producto y contexto

- Distribuidora de lácteos y fiambres. Operación inicial de **dos camiones** (cantidad final por validar). Se estiman **6 a 10 usuarios** (Blueprint §2).
- **Venta digital online-first:** el vendedor/piloto registra las operaciones desde Android cuando hay conexión. Sin Internet usa **talonario numerado de papel**. No se implementa sincronización offline automática (Blueprint §2).
- Una vez finalizada la jornada, el sistema compara lo que salió en el camión, lo vendido, lo devuelto y el dinero entregado, y expone las diferencias y los responsables de cada paso (Blueprint §1).
- **Arquitectura prevista:** frontend React + TypeScript + Vite, deploy en Vercel; backend Supabase (Auth, PostgreSQL, RLS, RPC, Storage). La lógica que mueve stock o dinero vive en la base, no en el frontend (Blueprint §6).
- Fase 1 se organiza en entregas **1A** (operación con papel + registro diferido) y **1B** (operación digital móvil), según Blueprint §4 y §14.

---

## 2. Problema

El dueño no tiene hoy una forma confiable de saber, por camión y por jornada, **qué mercadería salió, qué se vendió y qué volvió**, ni de detectar y atribuir **faltantes de mercadería y de dinero** (Blueprint §1). Sin un registro trazable y con separación de responsabilidades:

- la carga, las ventas, los retornos y el dinero dependen de lo que alguien recuerde o anote;
- no hay forma de distinguir un error honesto de un faltante, ni de saber quién hizo cada paso;
- un faltante o sobrante no deja rastro auditable.

El repositorio contiene hoy un **prototipo de demostración** de frontend, sin backend, que no cumple las reglas del Blueprint (ver `INVENTARIO_ETAPA_0.md`). El producto de Fase 1 es el sistema real definido en el Blueprint, no una evolución del prototipo.

---

## 3. Objetivo del producto

Que el dueño **sepa qué mercadería sale en cada camión, qué se vendió y qué volvió**, y que pueda **detectar faltantes de mercadería y de dinero por camión, por jornada y por vendedor** (Blueprint §1).

Todo lo que no sirva a ese objetivo queda fuera de Fase 1 (Blueprint §1, §3.4).

---

## 4. Pregunta principal que debe responder el sistema

El sistema debe poder responder siempre (Blueprint §1):

> «El camión X salió el día D con esta carga. Según las ventas y devoluciones, debería haber vuelto con A y entregado $B. Volvió con C y entregó $E. **La diferencia es esta, y estos son los responsables de cada paso.**»

---

## 5. Usuarios y roles

Tres roles, con las capacidades confirmadas en Blueprint §9. No se crean roles independientes de depósito o administración en Fase 1.

| Rol | Puede | No puede |
|---|---|---|
| **Dueño** | Visión general; administrar usuarios, clientes, productos, stock, jornadas y rendiciones; autorizar gastos y retiros; confirmar recepción de retiros. | Borrar movimientos confirmados sin reversión auditada. |
| **Encargado** | Operación general; editar y validar clientes; administrar cargas, conteos, cierre con diferencias, gastos y retiros de efectivo. | Administrar roles globales ni borrar historial sin compensación. |
| **Vendedor / Piloto** | Ver su jornada y clientes necesarios; **crear cliente nuevo**; registrar ventas y pagos mixtos; transcribir papel; finalizar ventas (`ventas_finalizadas`); confirmar entrega de retiro de dinero. | Editar ficha de cliente existente, cambiar precios maestros, aprobar su propio conteo/rendición, registrar retiros como receptor autorizado. |

Reglas transversales de rol (Blueprint §3.2, §7.5, §9):

- **Quien cuenta el regreso no es el vendedor** de esa jornada; si no hay otra persona disponible, el conteo queda pendiente, sin auto-bypass.
- La separación vendedor/conteo se valida **por participación real** en la jornada, incluso si una persona acumula permisos.
- El vendedor **puede crear** clientes nuevos pero **nunca editar** fichas existentes (Blueprint §2, §7.5).

---

## 6. Flujo operativo de una jornada

Estados (Blueprint §7.5): `abierta → cargada → en_reparto → ventas_finalizadas → regreso_contado → cerrada`. Los eventos se registran por separado y el cierre exige su validación; se evitan transiciones implícitas.

1. **Preparación / apertura.** Se crea la jornada del camión para la fecha, con vendedor asignado.
2. **Carga.** Se carga mercadería desde depósito al camión (`carga_camion`). El camión no se carga con mercadería en cuarentena.
3. **Salida / reparto.** El vendedor registra ventas digitales con conexión; si no hay Internet, usa talonario numerado de papel.
4. **Finalización de ventas (`ventas_finalizadas`).** El vendedor transcribe, guarda en el servidor y declara completas las notas de papel **antes** de que el encargado inicie el conteo formal.
5. **Conteo de regreso (`regreso_contado`).** Lo realiza dueño/encargado, distinto del vendedor, con clasificación física por aptitud (`apto` / `cuarentena` / `no_apto`). El conteo se captura **antes** de registrar el retorno definitivo.
6. **Retorno y merma.** El stock apto vuelve a depósito; el no apto pasa a cuarentena/merma según regla, con movimientos explícitos.
7. **Rendición y cierre (`cerrada`).** Se concilia mercadería y dinero por medio; las diferencias (positivas o negativas) requieren revisión, motivo y aprobación de dueño/encargado. Al cerrar, el saldo del camión queda en cero solo cuando la conciliación y la regularización están completas.

Reglas de la jornada (Blueprint §2, §7.5):

- **Una sola jornada por (`empresa_id`, `camion_id`, `fecha`)**, aunque otra del mismo camión y día ya esté cerrada.
- Un retiro de efectivo puede registrarse mientras la jornada está `en_reparto`.
- Una jornada **cerrada es inmutable**; las rectificaciones posteriores se hacen con operaciones compensatorias auditadas (Blueprint §3.3, §7.5).

---

## 7. Requisitos funcionales Fase 1

Derivados de la tabla de alcance (Blueprint §4) y de las reglas de negocio (Blueprint §7). Las entregas 1A/1B son las del Blueprint §4 y §14.

| ID | Requisito | Entrega | Fuente |
|---|---|---|---|
| RF-01 | **Productos:** alta, edición y baja lógica por dueño/encargado. Categoría, forma de venta (`unidad`/`pieza`), precio, stock mínimo. **Lácteos por unidad entera; fiambres por pieza/media pieza; sin `kg` en Fase 1.** **Fiambres: solo se configura el precio de pieza completa; el de media pieza se deriva (mitad, redondeada al peso entero, `.50` sube) y no es configurable (ADR-003 — Precio derivado de media pieza).** | 1A | Blueprint §4, §7.1 |
| RF-02 | **Clientes:** consultar y buscar; **alta por vendedor** desde celular; dueño/encargado editan y validan. Historial básico. | 1A; altas móviles 1B | Blueprint §4, §7.5 |
| RF-03 | **Depósito y camiones:** stock por ubicación, carga por jornada, movimientos auditados, cuarentena y retornos. | 1A | Blueprint §4, §7.2 |
| RF-04 | **Jornadas:** una por camión y fecha, asignación de vendedor, preparación, salida, carga final de ventas, conteo por tercero, rendición y cierre. | 1A | Blueprint §4, §7.5 |
| RF-05 | **Autoventa:** venta online en Android; talonario numerado como contingencia; carga de pendientes antes del conteo; control de duplicados y notas anuladas. | 1A papel / 1B digital | Blueprint §4, §7.5 |
| RF-06 | **Pagos de venta (mixtos):** múltiples medios por venta (efectivo, transferencia, importe a cuenta); la suma de componentes debe igualar el total. | 1A pagos; 1B captura móvil | Blueprint §4, §7.5, §7.8 |
| RF-07 | **Retiros de efectivo:** solicitud de dueño/encargado, **doble confirmación** (quien entrega y quien recibe), auditoría y afectación al saldo de efectivo por rendir. | 1A diferido / 1B en vivo | Blueprint §4, §7.6 |
| RF-08 | **Gastos en ruta:** registrados únicamente con autorización de dueño/encargado; afectan la conciliación como categoría separada de los retiros. | 1A registración autorizada / 1B móvil | Blueprint §4, §7.6 |
| RF-09 | **Devoluciones y mermas:** motivos, clasificación por aptitud, segregación de cuarentena y trazabilidad. La aptitud se evalúa por producto; no hay autorización genérica para todo retorno. | 1A | Blueprint §4, §7.7 |
| RF-10 | **Rendición:** mercadería esperada vs contada por estado; efectivo/transferencias/a cuenta/retiros separados; diferencias solo con aprobación y motivo. | 1A | Blueprint §4, §7.8 |
| RF-11 | **Reportes y usuarios:** los 9 reportes de Blueprint §11, exportación CSV, 3 roles, RLS y auditoría. | 1A; ampliaciones 1B | Blueprint §4, §11 |

**Sub-requisitos de integridad funcional** (reglas que atraviesan varios módulos):

- Toda venta identifica origen (`digital`/`papel`), serie y número de nota cuando aplica, usuario, instante de registro del servidor, jornada, cliente, ítems, precios históricos y pagos (Blueprint §7.5).
- La validación de duplicados de nota es por **empresa, serie y número en todo el histórico**, no solo dentro de una jornada; también hay idempotencia por solicitud. Las notas anuladas se preservan con motivo y sin efecto de stock/dinero (Blueprint §7.5, §8).
- Las devoluciones de cliente recibidas se registran como entrada al camión **una vez** y no suponen stock vendible automático (Blueprint §7.8).
- Faltantes y sobrantes generan **movimientos explícitos** (`faltante_rendicion` / `sobrante_rendicion`) con autorización; nunca se crea mercadería sin causa (Blueprint §7.4, §7.8).

**Puntos expresamente NO vigentes** (no son requisitos de Fase 1):

- **PROPUESTA NO APROBADA — Stock negativo transitorio** en la ubicación del camión con jornada abierta y marca `excede_stock` (Blueprint §7.4, §8, §15).
- **PROPUESTA NO APROBADA — Anulación de ventas por el vendedor** antes de `ventas_finalizadas` con motivo obligatorio (Blueprint §7.5, §15).
- **PROPUESTA NO APROBADA — Prohibición de descuentos** al vendedor y esquema de precio de lista vs aplicado (Blueprint §7.5, §15).
- **PROPUESTA NO APROBADA — Retiro que supera el saldo registrado sin bloqueo** (Blueprint §7.6, §15).
- **PROPUESTA TÉCNICA NO APROBADA — Vencimientos por partida de ingreso** (`partidas_ingreso`), sin saldo por partida ni FEFO (Blueprint §2, §4, §8, §15).

---

## 8. Requisitos no funcionales

| ID | Requisito | Fuente |
|---|---|---|
| RNF-01 | **Transaccionalidad.** Cada operación crítica (cargar camión, registrar regreso, cerrar jornada, mover dinero) es una transacción: o se guarda todo, o nada. | Blueprint §6 |
| RNF-02 | **Libros inmutables.** Las tablas de movimientos son solo de inserción: sin UPDATE ni DELETE. Los cambios de stock generan movimientos; los cambios de dinero, asientos auditables. | Blueprint §3.1, §6, §10 |
| RNF-03 | **Lógica en la base.** La lógica que mueve stock o dinero vive en RPC de la base; el frontend no inserta movimientos directamente. | Blueprint §6 |
| RNF-04 | **Idempotencia.** Clave única por operación (ventas, retiros, cargas, cierres y compras futuras) y protección frente a concurrencia/reintentos. | Blueprint §7.5, §10 |
| RNF-05 | **Tiempo.** Timestamp del servidor en UTC y zona horaria operativa explícita; distinguir hora declarada del hecho de la hora efectiva de registro. | Blueprint §10 |
| RNF-06 | **Seguridad.** Supabase Auth con cuentas individuales; roles y membresía desde tablas protegidas (no `user_metadata`); RLS y autorización real en servidor. | Blueprint §10 |
| RNF-07 | **Secretos.** Nunca en el frontend ni en el repositorio; entornos local/staging/producción separados. | Blueprint §10; AGENTS.md §5 |
| RNF-08 | **Probabilidad de prueba.** «Nada se da por terminado sin prueba»: test automatizado o verificación manual documentada. | Blueprint §3.5, §12 |
| RNF-09 | **Responsive.** Interfaz utilizable en escritorio (depósito/administración) y en Android (vendedor en ruta). | Blueprint §2, §4 |
| RNF-10 | **Dependencias.** Versión exacta, preferentemente publicadas hace al menos dos semanas. | AGENTS.md §6.8 |
| RNF-11 | **Una migración por cambio de base**, versionada en `supabase/migrations/`; nunca cambios manuales. Regla **aplicable cuando exista autorización de migraciones** (ver la nota de esta sección y §22); **no** implica que hoy corresponda generar migraciones. | Blueprint §13, regla 4; AGENTS.md §6.4 |

> **Dependencia de arquitectura:** ADR-001 v1.3 aprobó para validación controlada la Topología D y la gobernanza P19/P20. Las migraciones necesarias se permiten sólo local/staging, una vez resueltas las P2–P17 requeridas por el alcance; producción permanece bloqueada hasta pruebas, auditoría independiente y aceptación humana final. El detalle operativo está en `docs/quality/security-review.md`.

---

## 9. Integridad de stock

- **El stock nunca se edita a mano.** Todo cambio es un movimiento registrado: quién, cuándo, por qué, cuánto, desde dónde y hacia dónde (Blueprint §3.1, §7.4).
- **El stock de cada ubicación es la suma de sus movimientos.** Puede existir una tabla/vista de saldos mantenida por la misma transacción, pero el libro de movimientos es la verdad (Blueprint §7.4).
- **Ubicaciones** (Blueprint §7.2): `deposito`, `cuarentena` (no vendible, no se puede cargar a un camión), `camion:<id>` (jornada abierta). **`merma` no es ubicación interna**; es una salida terminal (`tipo_movimiento = merma`). El cliente tampoco es ubicación interna; es contraparte comercial.
- **Cantidades enteras en la unidad mínima.** **Lácteos** por **unidad entera**; **fiambres** por **pieza/media**, con representación canónica en **medias piezas** (entero); nunca decimales y **sin `kg` en Fase 1** (Blueprint §7.1). Ejemplo de consistencia categoría/unidad *(no es una regla de nombres)*: `Queso cremoso en bote` → Lácteos/`unidad`; `Queso cremoso en pieza` → Fiambres/`pieza`. Precio por pieza; el de media se deriva (mitad, redondeada al peso entero, `.50` sube) y no es configurable (ADR-003).
- **Tipos de movimiento** (Blueprint §7.4): `ingreso`, `carga_camion`, `venta`, `retorno_camion`, `devolucion_cliente`, `a_cuarentena`, `cuarentena_apta`, `merma`, `faltante_rendicion`, `sobrante_rendicion`, `ajuste`.
- **No se permiten saldos negativos silenciosos.** Si una venta en papel aún no registrada hace que una venta posterior exceda el saldo informático, se registra una **incidencia de conciliación** y se exige regularización trazable por dueño/encargado; la venta física nunca se borra ni se inventa stock (Blueprint §7.4).
- **Ajustes** con motivo obligatorio y permiso de administrador (Blueprint §7.4).

> **PROPUESTA NO APROBADA:** permitir **negativo transitorio** exclusivamente en la ubicación del camión con jornada abierta, marcar la venta `excede_stock`, registrar incidencia y bloquear el cierre hasta regularización autorizada; depósito y cuarentena nunca en negativo. Debe revisarse con operaciones simultáneas (Blueprint §7.4, §8, §15). **No implementar.**

---

## 10. Integridad financiera

Conciliación financiera por medio (Blueprint §7.8):

```
efectivo_esperado_entrega = efectivo_efectivamente_cobrado
                            + otros_ingresos_efectivo_documentados
                            - retiros_con_doble_confirmacion
                            - gastos_efectivo_autorizados_y_comprobados
diferencia_efectivo = efectivo_contado_y_entregado - efectivo_esperado_entrega
```

Reglas:

- **Pagos mixtos:** la suma de los componentes (efectivo, transferencia, a cuenta) debe igualar el total de la venta. `a_cuenta` **no** es dinero ingresado (Blueprint §7.5, §7.8).
- **Transferencias:** estados `declarada` y `verificada`, con **verificación manual** (identificador de quien verificó y fecha). Una transferencia declarada no es efectivo físico ni se presume acreditada (Blueprint §7.8).
- **Retiros de efectivo:** doble confirmación obligatoria (entrega y recepción); afectan la rendición **solo tras ambas confirmaciones**; prohibición de duplicados por `idempotency_key` *(nombre y ubicación de la columna: **modelo de datos propuesto**; ver ADR-001 §3.2 y P15)*; nunca importes negativos (Blueprint §7.6).
- **Gastos en ruta:** categoría separada de los retiros, con autorización y comprobante/motivo (Blueprint §7.6).
- **Diferencias:** requieren revisión, motivo y aprobación de dueño/encargado; no asignan automáticamente responsabilidad económica al vendedor (Blueprint §7.8).
- **Congelamiento de totales:** se conservan total original, componentes de pago, precios históricos, conteos y cálculo congelado al cerrar (Blueprint §7.8).
- **Dinero:** **NO se crea ledger financiero separado en Fase 1**. La fuente documental son: `ventas`, `pagos/cobros` (`venta_pagos`), `retiros_efectivo`, `rendiciones`. El saldo de caja se deriva. **Monto:** `numeric(14,2)`, nunca float. Registros financieros confirmados: sin UPDATE/DELETE destructivo; correcciones mediante operación compensatoria auditada cuando corresponda. Stock y dinero nunca se corrigen automáticamente entre sí (Blueprint §8).

> **PROPUESTA NO APROBADA:** que un retiro que supera el saldo registrado **avise y requiera explicación sin bloquear automáticamente el retiro físico** (puede haber notas de papel pendientes) (Blueprint §7.6, §15). **No implementar.**

---

## 11. Seguridad y autorización

- **Autenticación:** Supabase Auth con cuentas individuales. Membresía, empresa y roles se leen de tablas protegidas, no de `user_metadata` modificable por el usuario (Blueprint §10).
- **RLS en todas las tablas expuestas** por la API, restringiendo por empresa, rol y estado. Los controles visuales nunca son la única defensa (Blueprint §10).
- **`authenticated` y `anon` no reciben INSERT/UPDATE/DELETE directos** sobre libros de movimientos de stock/caja ni sobre registros confirmados; la rectificación es por asientos compensatorios (Blueprint §10).
- **Escrituras críticas por RPC en la base** con autorización comprobada en el servidor (Blueprint §6, primera viñeta sobre la lógica en RPC; Blueprint §10, viñetas de RLS, escrituras directas e idempotencia).
- **Lecturas y ediciones ordinarias** con grants y RLS apropiados; las Edge Functions solo si aparece lógica externa no conveniente en SQL (Blueprint §10, viñeta «SECURITY INVOKER…»).
- **El frontend nunca mueve stock ni dinero** y nunca usa credenciales administrativas en el navegador (Blueprint §6; AGENTS.md §5).
- **Auditoría (Fase 1):** **no se crea una tabla genérica `auditoria`**. La trazabilidad surge de `operaciones`, los ledgers (`movimientos_stock`), los documentos, el actor, los timestamps, los motivos, la jornada y las relaciones (Blueprint §8, §10).

> **DEPENDENCIA — ADR-001 v1.3, APROBADA PARA VALIDACIÓN CONTROLADA:** P1 seleccionó la Topología D: Data API → fachada expuesta `SECURITY INVOKER` → implementación privada/no expuesta `SECURITY DEFINER` → validaciones completas → transacción. La implementación privada es la frontera real de seguridad. P2–P17 continúan pendientes y P18 es futura/separada; sólo se permiten migraciones de validación local/staging y producción no está autorizada.

---

## 12. Multiempresa

- **Todas las tablas de negocio llevan `empresa_id`** y las políticas RLS filtran por él (Blueprint §7.3, §8).
- Hoy existe **una sola empresa**. No se construye registro de empresas, suscripciones ni panel de administración de plataforma (Blueprint §7.3).
- El diseño debe dejar preparado el filtrado por `empresa_id` para poder probar el aislamiento entre empresas sin construir la funcionalidad completa de alta de empresas (Blueprint §7.3, §12).

---

## 13. UX móvil y escritorio

- **Móvil (Android, vendedor/piloto en ruta):** registrar la jornada, crear clientes nuevos, registrar ventas y pagos mixtos, transcribir papel y finalizar ventas (`ventas_finalizadas`); en 1B, retiros en vivo y gastos (Blueprint §4, §7.5).
- **Escritorio (depósito/administración):** productos, clientes, camiones, cargas, conteos, rendición, cierre, reportes y administración de usuarios (Blueprint §4, §11).
- **Online-first:** la operación digital asume conexión; el talonario numerado de papel es la contingencia. No hay modo offline automático ni sincronización (Blueprint §2, §5).
- **Reutilización del prototipo:** el prototipo actual (`apps/web/`) es **referencia de UX**, no de reglas. Sus pantallas y layouts pueden servir como referencia visual, pero la lógica debe reimplementarse conforme al Blueprint (`INVENTARIO_ETAPA_0.md`, §16–§17). No hay decisión registrada sobre el destino del prototipo (Blueprint §15; `INVENTARIO_ETAPA_0.md`, §18.20). El prototipo usa además `kg` y piezas enteras, lo que **no cumple** la regla de unidades vigente (Blueprint §7.1) y **requiere migración** (`docs/requirements/migracion-unidades-prototipo.md`). El versionado de las claves demo de `localStorage` (**v1 → v2**, con inicialización limpia y **sin migración automática** de cantidades) es una **decisión humana aprobada**; su ejecución queda pendiente de autorización.

---

## 14. Estados y transiciones

**Jornada** (Blueprint §7.5): `abierta → cargada → en_reparto → ventas_finalizadas → regreso_contado → cerrada`. Cada transición es un evento registrado por separado; el cierre exige su validación y no se admiten transiciones implícitas. Una jornada `cerrada` es **inmutable** (Blueprint §3.3).

**Notas de talonario** (Blueprint §8): `utilizada`, `anulada`, `justificada` **[estados del modelo de datos propuesto; ADR-001 §3.2]**. Las anuladas se preservan con motivo y sin efecto de stock/dinero (Blueprint §7.5, §8).

**Transferencias** (Blueprint §7.8): `declarada` → `verificada` (verificación manual).

**Retiros de efectivo** (Blueprint §7.6): `pendiente_doble_confirmacion` hasta la aceptación de **ambos** participantes; solo entonces afecta la rendición.

> **PROPUESTA NO APROBADA:** la anulación de ventas por el vendedor antes de `ventas_finalizadas` (y luego solo con operación compensatoria de dueño/encargado) y la marca de venta `excede_stock` (Blueprint §7.5, §7.4). **No implementar.**

---

## 15. Casos de error y recuperación

| Caso | Comportamiento esperado | Fuente |
|---|---|---|
| Nota de papel con número duplicado en la misma empresa/serie | Rechazo; aviso de salto de numeración | Blueprint §7.5, §12 |
| Venta con stock informático insuficiente (papel pendiente) | Registrar incidencia de conciliación; regularización trazable; nunca saldo negativo silencioso | Blueprint §7.4, §12 |
| Retiro duplicado | Idempotencia: una sola operación | Blueprint §7.6, §12 |
| Retiro con confirmación pendiente de uno de los actores | No descuenta caja hasta que ambos confirmen | Blueprint §7.6, §12 |
| Intento de modificar una jornada cerrada | Rechazo; la corrección es por operación compensatoria auditada | Blueprint §3.3, §7.5 |
| Diferencia (faltante o sobrante) al cerrar | Se informa, se valoriza y se registra movimiento con autorización; nunca se crea mercadería sin causa | Blueprint §7.4, §7.8 |
| Devolución de mercadería no apta | No reingresa a stock vendible; va a cuarentena/merma según aptitud verificable | Blueprint §7.7 |
| Carga superior a lo disponible en depósito / carga de cuarentena | Rechazo | Blueprint §12 |
| Cierre sin conteo de regreso | Rechazo | Blueprint §12 |

Recuperación general: las correcciones sobre registros confirmados se hacen con **asientos/movimientos compensatorios auditados con motivo**; nunca con borrado silencioso ni reescritura (Blueprint §3.3, §7.5, §7.6).

---

## 16. Auditoría y trazabilidad

- **Libro de movimientos de stock** (`movimientos_stock`) y documentos (`ventas`, `rendiciones`, `conteos`, `retiros_efectivo`, `operaciones`) con usuario, acción, tabla, registro, datos antes/después y fecha (Blueprint §8). **[Modelo de datos propuesto]** Estos nombres de tabla y columna provienen de `BLUEPRINT.md` §8 («Modelo de datos (propuesto)»); su forma final está **pendiente de aprobación humana** junto con el modelo (ADR-001 §3.2). **No son DDL aprobado** y aquí se citan solo como referencia.
- **No hay tabla genérica `auditoria` en Fase 1** (Blueprint §10). La trazabilidad surge de los ledgers, documentos, actor, timestamps, motivos, jornada y relaciones.
- Toda operación crítica registra **quién hizo cada paso**, con timestamp del servidor UTC y zona horaria operativa explícita (Blueprint §3.2, §10).
- Los registros confirmados son inmutables; la rectificación es por compensación auditada (Blueprint §6, §10).
- La auditoría es central para el objetivo: «estos son los responsables de cada paso» (Blueprint §1).

---

## 17. Criterios de aceptación

Un módulo se considera terminado cuando cumple las **pruebas obligatorias** de Blueprint §12 y «nada se da por terminado sin prueba» (Blueprint §3.5). Criterios por área (no exhaustivos; el detalle está en Blueprint §12):

- **Stock:** cargar descuenta depósito y suma camión por el mismo importe; no se carga más que lo disponible; no se carga cuarentena; media pieza guarda y vende en medias y se cobra con su precio derivado (ADR-003: con pieza = 21, `c=1 → 11`, `c=2 → 21`, `c=3 → 32`); la venta histórica conserva la media aplicada; el saldo de cada ubicación coincide con la suma de movimientos.
- **Jornada:** no hay dos jornadas por camión y fecha (aunque una esté cerrada); el vendedor no registra el conteo de regreso; las notas de papel pendientes bloquean el conteo formal; no se cierra sin conteo; una jornada cerrada rechaza toda modificación.
- **Rendición:** pago mixto suma el total; `a_cuenta` no suma al efectivo esperado; retiro confirmado por ambos descuenta caja exactamente una vez; dos solicitudes del mismo retiro producen una sola operación; gastos no autorizados no reducen la caja; devoluciones no se duplican; al cerrar, el stock del camión queda en 0.
- **Ventas en papel:** número duplicado en cualquier jornada de la misma empresa/serie se rechaza; un salto de numeración genera aviso.
- **Seguridad:** la fachada expuesta `SECURITY INVOKER` y la implementación privada `SECURITY DEFINER` rechazan `anon`, usuario sin membresía, usuario de otra empresa y vendedor intentando cerrar jornada o retirar; sin escrituras directas en el ledger; un usuario sin rol no ve datos; ningún rol hace UPDATE/DELETE en movimientos; usuario de otra `empresa_id` no ve ni opera; transferencia declarada no figura verificada hasta intervención habilitada; vendedor crea cliente pero no edita existente; sólo dueño/encargado inician un retiro y sólo ambos participantes lo confirman.

> **Nota (P1 resuelta).** Los criterios de Seguridad prueban la Topología D aprobada para validación controlada. No resuelven P2–P17 ni autorizan producción (ver §11 y §22; ADR-001 §4 y §5).

---

## 18. Estrategia de testing

Niveles previstos (AGENTS.md §9; Blueprint §12):

| Nivel | Herramienta | Qué cubre |
|---|---|---|
| Unitario | Vitest (`npm test`) | Lógica de dominio pura. |
| Integración / base | pgTAP sobre las RPC (`supabase test db`) — local/staging, tras resolver P2–P17 necesarias | Reglas de stock, dinero, jornada y seguridad. |
| End-to-end | Playwright (E2E versionado) | Recorridos críticos de UI. |
| Exploración funcional | Playwright CLI | Apoyo manual para validar y depurar (ver `docs/quality/browser-testing.md`). |

- Las pruebas que dependan de **RPC privilegiadas** pueden prepararse y ejecutarse sólo en local/staging después de resolver las P2–P17 necesarias; no habilitan producción (`docs/quality/security-review.md`).
- Antes de pedir revisión: `lint`, `typecheck`, `test`, Playwright y `build` deben pasar; `npm run lint` debe terminar con exit 0 (AGENTS.md §9).
- El proceso de revisión y auditoría se documenta en `docs/quality/review-process.md`.

---

## 19. Métricas de éxito

El Blueprint **no define** métricas de éxito cuantitativas; esta sección **no las inventa**. Los siguientes son **candidatos a acordar con el dueño** (no aprobados), derivados del objetivo (Blueprint §1):

- Porcentaje de jornadas cerradas **sin diferencias** no explicadas (mercadería y dinero).
- Diferencias detectadas y valorizadas por camión y por vendedor, en unidades y en pesos (Blueprint §11, reporte 2).
- Tiempo entre el regreso del camión y el cierre de la jornada.
- Notas de papel pendientes al inicio del conteo (debe tender a cero).
- Productos con faltantes más frecuentes (Blueprint §11, reporte 3).

> Estas métricas quedan **pendientes de definición y aprobación** con el dueño. No son requisitos ni criterios de aceptación.

---

## 20. Fuera de alcance

Fuera de Fase 1 por decisión confirmada (Blueprint §5):

**Fase 2** (presupuestar/planificar; no incluida en la primera entrega):
- Preventa y pedidos programados.
- Proveedores y compras (alta, historial, recepción distinta de la fecha de compra, remito/factura sin duplicar ingresos, foto/PDF en almacenamiento privado, costo histórico, vencimientos de deuda).
- Pagos a proveedores (combinados, cuotas, pagos parciales, cuenta corriente de proveedor).
- Gestión completa de cuenta corriente de clientes (aplicación de cobros a documentos, vencimientos, saldos históricos). En Fase 1 solo se registra el importe vendido a cuenta y se informa.
- Gestión por lotes y FEFO.
- Listas de precios por cliente, exportaciones ampliadas y reportes avanzados.

**Sin fecha comprometida:**
- Facturación electrónica ARCA (los comprobantes de Fase 1 son internos, no fiscales).
- Aplicación Android nativa; modo offline automático/sincronización.
- GPS/seguimiento en vivo, optimización de rutas, integraciones bancarias.
- Funciones de IA en el producto, n8n, módulo sanitario regulatorio o plataforma SaaS completa.

**PROPUESTA TÉCNICA NO APROBADA —** control de vencimientos por partida de ingreso (`partidas_ingreso`) y alertas orientativas por fecha, sin saldo por partida, asignación de salida a partida, FEFO ni trazabilidad de salida (Blueprint §2, §4, §8, §15). **No implementar.**

---

## 21. Decisiones pendientes

Tomado de Blueprint §15 (no se inventan respuestas). **Prioridad alta — antes de diseñar tablas/RPC:**

1. **Alcance contractual** de 1A + 1B (precio y fechas); no asumir que 30 días bastan.
2. **Venta con stock insuficiente** — negativo transitorio solo camión en jornada abierta, venta `excede_stock`, cierre bloqueado hasta regularización. *(PROPUESTA NO APROBADA.)*
3. **Anulaciones** — vendedor anula sus ventas antes de finalizar, con motivo; luego solo dueño/encargado. *(PROPUESTA NO APROBADA.)*
4. **Descuentos** — prohibidos para el vendedor en Fase 1. *(PROPUESTA NO APROBADA.)*
5. **ADR-001** — Topología D y gobernanza aprobadas para validación controlada; resolver P2–P17 y probar revocaciones/permisos antes de la aceptación productiva. P18 queda separada.
6. **Ventas con pagos combinados** — confirmar medios exactos (efectivo, transferencia, débito/QR, a cuenta) y si una misma venta admite saldo impago.
7. **Alta de clientes por vendedor** — campos mínimos, manejo de duplicados y cuándo el encargado valida.
8. **Talonarios** — por vendedor o camión, serie, numeración, asignación y control de duplicados.
9. **Doble confirmación de retiro sin Internet** — cómo se documenta y quién regulariza.
10. **Gastos de ruta** — tipos, quién solicita/autoriza, comprobante, momento y efecto en la rendición.
11. **Devoluciones por producto** — criterios documentables de aptitud apto/no apto.
12. **Vencimientos** — fecha por ingreso con `cantidad_inicial` y alertas orientativas; sin FEFO. *(PROPUESTA NO APROBADA.)*
13. ~~**Precio media pieza**~~ — **resuelto por ADR-003 (21/10/2026)**, que supera a ADR-002 (dos precios independientes, hoy histórica): media no configurable, mitad del precio de pieza redondeada al peso entero (`.50` sube).
14. **Fechas** — día operativo, zona horaria del negocio y corte de jornada.

**Prioridad media — antes de entrega:** verificación de transferencias en Fase 1; manejo de cobros de deudas anteriores (cuenta corriente integral es Fase 2); valuación de faltantes y responsabilidades; cantidad exacta de camiones/usuarios/catálogo y conectividad.

**Decisiones de ADR-001 (v1.3).** P1, P19 y P20 están resueltas. **P2–P17 continúan PENDIENTES DE APROBACIÓN HUMANA** y deben resolverse según el alcance de validación; P18 es una decisión futura separada y no es requisito previo.

---

## 22. Dependencias de ADR

- **ADR-001 — Puerta de entrada SQL para operaciones privilegiadas** (`docs/decisions/001-rpc-privilegiadas.md`): **versión 1.3**, estado **APROBADA PARA VALIDACIÓN CONTROLADA** (`docs/decisions/README.md`). P1 seleccionó Topología D; P19/P20 fijaron dos etapas y migraciones sólo local/staging. P2–P17 siguen pendientes, P18 es futura/separada y producción continúa bloqueada.
- **Otras reglas con estado de propuesta** (no son ADR, pero bloquean implementación): stock negativo transitorio, anulación de ventas, prohibición de descuentos, retiro que excede el saldo y vencimientos por partida (Blueprint §7.4–§7.6, §15).
- **Regla de estado:** una ADR `aprobada para validación controlada` sólo se implementa en local/staging y dentro de sus decisiones resueltas; producción requiere estado `aprobada` tras aceptación humana final. Un agente no puede aprobar una ADR (`docs/decisions/README.md`; AGENTS.md §3).

---

*Historial del documento*

| Versión | Fecha | Cambio |
|---|---|---|
| 0.1 | 17/10/2026 | Versión inicial. Complementa `BLUEPRINT.md` v1.4; no autoriza implementación. Reproduce las propuestas no aprobadas con su marca y mantiene ADR-001 como dependencia pendiente. |
| 0.2 | 17/10/2026 | Corrección sobre la base documental actual: ADR-001 queda identificada como **v1.2, ronda 3** y sus **P1–P20** como decisiones pendientes de aprobación humana (con P19/P20 primero y P18 como decisión futura separada); se agrega el cuadro de categorías (§0) que separa regla aprobada, propuesta no aprobada, decisión pendiente de ADR y Fase 2/fuera de alcance; la cadena de validaciones de la RPC deja de figurar como requisito; se registra la contradicción viñeta ADR-001 de Blueprint §10 / guía de Supabase como decisión pendiente (P1), sin resolverla. |
| 0.3 | 17/10/2026 | Correcciones documentales de la auditoría final: se marca como **modelo de datos propuesto** todo identificador tomado de Blueprint §8 (`movimientos_stock`, `auditoria`, `idempotency_key`, estados de nota) con remisión a ADR-001 §3.2; nota en los criterios de Seguridad que dependen de P1 y no implican aprobación de la topología wrapper; RNF-11 cita `Blueprint §13, regla 4` y queda condicionada a autorización de migraciones. Sin cambios de reglas de negocio ni de seguridad. |
| 0.4 | 18/10/2026 | Acompaña a `BLUEPRINT.md` v1.5: refleja como **requisito aprobado** la decisión humana de unidades (lácteos por unidad entera; fiambres por pieza/media pieza, canónico en medias piezas; sin `kg` en Fase 1) en RF-01 y §9, y señala que el prototipo legacy requiere migración (`docs/requirements/migracion-unidades-prototipo.md`). Sin cambios de reglas no aprobadas; ADR-001 sigue `propuesta`. |
| 0.5 | 18/10/2026 | Acompaña a `BLUEPRINT.md` v1.6: agrega en §9 el **ejemplo de consistencia categoría/unidad** (`Queso cremoso en bote` → Lácteos/`unidad`; `Queso cremoso en pieza` → Fiambres/`pieza`) y registra en §13 que el versionado de `localStorage` **v1 → v2** (sin migración automática) es una **decisión humana aprobada**, pendiente de ejecución. ADR-001 sigue `propuesta`. |
| 0.6 | 20/10/2026 | **Acompaña a `BLUEPRINT.md` v1.7**: refleja decisiones arquitectónicas aprobadas conceptualmente — operaciones (Alternativa B: tabla `operaciones` mínima), ubicaciones (merma = salida terminal, no ubicación interna), cierres (derivado: jornada + rendición + operación tipo cierre), roles funcionales sin tabla `roles`, conteos separados de movimientos, `movimientos_stock` como ledger append-only sin `saldo_actual`, dinero sin ledger financiero separado, saldos derivados, auditoría sin tabla genérica, idempotencia centralizada en `operaciones`, concurrencia solo garantías funcionales. Actualiza modelo de datos (§8/§9), tabla de entidades, §7.2, §7.9, §10, §16. |
| 0.7 | 20/10/2026 | **Acompaña a `BLUEPRINT.md` v1.8**: refleja ADR-002 (aprobada) — fiambres con precio de pieza completa y precio de media pieza independientes, cantidad canónica vs presentación comercial, máximo 2 decimales y cierre de la pregunta abierta 13. Sin cambios en ADR-001. |
| 0.8 | 21/10/2026 | **Acompaña a `BLUEPRINT.md` v1.9**: refleja ADR-003 — Precio derivado de media pieza (aprobada; supera a ADR-002 solo en la política de precio de media): media no configurable, mitad del precio de pieza redondeada al peso entero (`.50` sube), cantidad canónica en medias sin cambios, snapshot histórico con la media aplicada. RF-01, criterios de Stock y pregunta 13. Sin cambios en ADR-001 ni SQL aprobado. |
| 0.9 | 22/10/2026 | Acompaña a `BLUEPRINT.md` v2.0 y ADR-001 v1.3: Topología D y gobernanza P19/P20 aprobadas para validación controlada local/staging. P2–P17 pendientes, P18 separada y producción bloqueada. Sin backend, SQL ni migraciones. |
