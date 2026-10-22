# Referencias open-source de inventario/stock — insumo de diseño

**Proyecto:** Sistema de Control para Distribuidora de Lácteos y Fiambres (VM Digital Studio)
**Fecha:** 20/10/2026 (hora local Argentina)
**Tipo de documento:** investigación (research) de solo lectura. **PROPUESTA / INSUMO.**
**Alcance:** relevamiento de sistemas open-source de inventario/stock usados como **referencia conceptual externa** para las decisiones de arquitectura del proyecto. Este documento **no es una decisión aprobada**, **no es fuente de verdad**, **no reemplaza ni modifica `BLUEPRINT.md`** y **no autoriza implementación** (ni SQL, ni migraciones, ni RLS, ni RPC). La fuente de referencia del proyecto sigue siendo `BLUEPRINT.md`.

---

## 0. Propósito y cómo leer este documento

Este documento releva cómo algunos sistemas open-source de inventario/stock modelan el stock, con el fin de **alimentar el diseño** de las reglas ya definidas para este proyecto: el ledger de movimientos como verdad del stock, las ubicaciones internas frente a las salidas terminales, los conteos como hecho observado, la correlación de documentos mediante una operación lógica con idempotencia, la separación entre stock y dinero, y un cierre derivado de estado + conciliación. Es material **de apoyo**, no una especificación: ninguna afirmación de acá obliga al proyecto.

Este documento distingue **tres categorías** y las marca en el texto:

| Categoría | Significado |
|---|---|
| **REFERENCIA EXTERNA** | Cómo funciona otro sistema (Odoo, ERPNext, InvenTree, OpenBoxes, Snipe-IT, o el patrón general de ledger/event sourcing). Es descriptivo y se cita con su URL. |
| **DECISIÓN DEL PROYECTO (Blueprint)** | Regla ya vigente y aprobada en `BLUEPRINT.md`. Es la que manda. |
| **PROPUESTA DEL PROYECTO (pendiente)** | Mecanismo propuesto en `docs/propuesta_v2_*` que **requiere aprobación humana** y **no** es vigente (AGENTS.md §3). |

> **Advertencia de estado.** Varios de los "patrones objetivo" del relevamiento están fijados en el `BLUEPRINT.md` (ledger, ubicaciones, conteos, idempotencia, dinero separado, cierre por estado). Otros detalles de diseño —en particular una tabla `operaciones` para correlación y una tabla `cierres` propia— figuran **solo como propuesta** en `docs/propuesta_v2_01_correlacion.md`, `docs/propuesta_v2_04_cierre.md`, `docs/propuesta_v2_08_idempotencia.md` y `docs/propuesta_v2_10_decisiones_pendientes.md`, **sin aprobación humana**. Este documento los trata como propuesta, nunca como decisión vigente.

**Método y límites.** Las afirmaciones sobre sistemas externos se verificaron contra documentación oficial con `webfetch` cuando fue posible; en cada caso se cita la URL. Lo que no pudo verificarse contra documentación oficial se marca **"sin verificar"**. En particular, los modelos **técnicos internos** (nombres de tablas/objetos como `stock.move`/`stock.quant` de Odoo o `Stock Ledger Entry` de ERPNext) aparecen en documentación de desarrollador que **no** se relevó acá: donde se mencionan, se hace a nivel conceptual y se aclara que el detalle técnico queda **sin verificar**.

---

## 1. Odoo — módulo Inventario/Stock

**Qué es (REFERENCIA EXTERNA).** Odoo *Inventory* es a la vez aplicación de inventario y sistema de gestión de depósitos ("inventory application and a warehouse management system"), con gestión de plazos, reposición y rutas. Fuente: <https://www.odoo.com/documentation/17.0/applications/inventory_and_mrp/inventory.html>

**Modelo de stock (REFERENCIA EXTERNA).**
- **Ubicaciones jerárquicas.** Una *location* es un espacio dentro de un depósito (estante, sala, pasillo) y se organiza en árbol con *parent location*. Fuente: <https://www.odoo.com/documentation/17.0/applications/inventory_and_mrp/inventory/warehouses_storage/inventory_management/use_locations.html>
- **Tipos de ubicación.** Odoo clasifica cada ubicación: *Vendor* ("Items here are not in stock"), *View* (organizativa; no debe contener productos), *Internal* (donde el stock se contabiliza en la valorización), *Customer* ("items here are no longer in stock"), *Inventory Loss* (contrapartida para consumir faltantes o crear stock; ejemplos: *Inventory Adjustment* y *Scrap*), *Production* y *Transit*. Fuente: <https://www.odoo.com/documentation/17.0/applications/inventory_and_mrp/inventory/warehouses_storage/inventory_management.html>
- **Movimientos ("stock moves") e historial.** Cada cambio de un producto se registra como un movimiento con fecha, referencia, producto, lote/serie, **origen**, **destino**, cantidad, unidad y estado (*Done / Available / Partially Available*). El reporte *Moves History* filtra por *Incoming* (desde ubicaciones de proveedor), *Outgoing* (hacia ubicaciones de cliente), *Internal* (entre ubicaciones internas) y *Manufacturing*. Fuente: <https://www.odoo.com/documentation/17.0/applications/inventory_and_mrp/inventory/warehouses_storage/reporting/moves_history.html>
- **Ajustes por conteo.** En *Inventory Adjustments* se registra la *Counted Quantity*; la diferencia contra *On Hand Quantity* se calcula y recién al presionar **Apply** (con una referencia/motivo, por defecto la fecha) el ajuste se aplica. "At this stage, the count (inventory adjustment) is recorded, but not yet applied." Aplicar el ajuste "simultaneously creates a stock move line (SML)". Odoo advierte además que, entre el conteo y su aplicación, pueden ocurrir movimientos y pide confirmación. Fuente: <https://www.odoo.com/documentation/17.0/applications/inventory_and_mrp/inventory/warehouses_storage/inventory_management/count_products.html>

**Patrón relevante (REFERENCIA EXTERNA).** Odoo separa limpiamente **(a)** ubicaciones internas (donde hay stock contabilizado) de **(b)** ubicaciones externas/terminales (proveedor y cliente: "not in stock" / "no longer in stock"), y usa **contrapartidas** (*Inventory Loss* / *Scrap*) para faltantes y descartes. Además, el **conteo se registra por separado y se aplica explícitamente**, generando recién ahí el movimiento.

**Similitud con este proyecto (REFERENCIA EXTERNA vs DECISIÓN DEL PROYECTO).**
- **Se parece** en el patrón de **movimiento con origen y destino** y en la idea de que mover stock *es* registrar un movimiento. Coincide con la **DECISIÓN DEL PROYECTO (Blueprint §7.4)**: todo cambio de stock genera un registro en `movimientos_stock` con origen y destino, y el stock de una ubicación es la suma de sus movimientos.
- **Se parece** en el patrón de **conteo observado ≠ movimiento**, que coincide con la **DECISIÓN DEL PROYECTO (Blueprint §7.8)**: el conteo se captura antes y la regularización es una operación explícita posterior con movimiento auditable.
- **Se parece** en la separación **interna vs. terminal**: en Odoo, cliente y proveedor son ubicaciones "externas" sin stock. Es compatible con la **DECISIÓN DEL PROYECTO (Blueprint §7.2, §7.4)**: la venta es `camión → (cliente)` y el cliente no es una ubicación interna. **Matiz:** el Blueprint lista `merma` como una ubicación destino; el proyecto **APROBÓ CONCEPTUALMENTE** que `merma` es una **salida terminal** (`tipo_movimiento = merma`), no una ubicación interna. Este punto queda como detalle de diseño resuelto en el Blueprint.
- **Se diferencia** en que Odoo integra la **valorización** del stock con la contabilidad (las ubicaciones internas se contabilizan en *inventory valuation*). La **DECISIÓN DEL PROYECTO (Blueprint §7.8)** mantiene el stock y el dinero **separados**: una diferencia de stock no corrige el dinero automáticamente.

**Lección (REFERENCIA EXTERNA).** Es el mejor ejemplo de dos cosas: (1) tratar "cliente"/"proveedor"/"pérdida" como **ubicaciones externas o contrapartidas** para que el sistema de movimientos cierre por partida doble, y (2) **separar el conteo de su aplicación**. El detalle técnico de `stock.move`/`stock.quant` (el modelo interno) no se relevó acá: **sin verificar**.

---

## 2. ERPNext — módulo Stock

**Qué es (REFERENCIA EXTERNA).** El módulo *Stock* de ERPNext gestiona inventario y cadena de suministro: seguimiento de stock, movimientos, depósitos, transacciones, reconciliación y reportes. Fuente: <https://docs.frappe.io/erpnext/stock>

**Modelo de stock (REFERENCIA EXTERNA).**
- **Depósitos jerárquicos.** Un *Warehouse* puede verse como "storage locations" y admite sub-depósitos en árbol (*Warehouse > Room > Row > Shelf > Bin*). Se puede clasificar por *Warehouse Type* (Supplier, Stock, WIP, Rooms, etc.). Fuente: <https://docs.frappe.io/erpnext/warehouse>
- **Stock Entry.** Un *Stock Entry* "lets you record Item movement between Warehouses" con **Source Warehouse** y **Target Warehouse**, y un *purpose* que distingue el tipo de movimiento: *Material Issue* (salida), *Material Receipt* (ingreso), *Material Transfer* (entre depósitos internos), *Repack*, *Manufacture*, *Send to Subcontractor*, etc. Fuente: <https://docs.frappe.io/erpnext/stock-entry>
- **Stock Ledger.** El *Stock Ledger Report* es "a detailed record that keeps track of stock movements"; registra cantidad y valor de lo "issued, received, or transferred". Se alimenta de documentos (Sales Invoice, Purchase Invoice, Delivery Note, Purchase Receipt, Stock Entry, Stock Reconciliation) y cada línea permite abrir el documento origen por **Voucher #**. Fuente: <https://docs.frappe.io/erpnext/stock-ledger>
- **Reconciliación.** *Stock Reconciliation* sirve para "Posting opening stock" y para "Reconciling the book and the actual stock": se cargan las cantidades contadas y se ajusta el saldo, con una *Difference Account* ("Stock Adjustment" o "Temporary Opening"). Fuente: <https://docs.frappe.io/erpnext/stock-reconciliation>
- **Inmutabilidad del documento.** "Once a stock entry is submitted, it can be updated by cancelling and amending the entry." Fuente: <https://docs.frappe.io/erpnext/stock-entry>

**Patrón relevante (REFERENCIA EXTERNA).**
- **Ledger como historial de movimientos** (cada operación deja una línea en el *Stock Ledger*, ligada a su documento origen por *Voucher #*).
- **Movimiento con origen y destino** y un *purpose* que tipifica la operación.
- **Conteo/reconciliación como operación explícita** separada de las transacciones normales.
- **Documento confirmado inmutable**, corregido por *cancel + amend* (no por edición in-place).

**Similitud con este proyecto (REFERENCIA EXTERNA vs DECISIÓN DEL PROYECTO).**
- **Se parece mucho** al patrón central: **DECISIÓN DEL PROYECTO (Blueprint §3.1, §6, §7.4)** — el stock es la suma de movimientos, las tablas de movimientos son **solo de inserción** (no UPDATE/DELETE) y todo cambio de stock es un movimiento registrado. El *Stock Ledger* es la referencia externa más cercana a `movimientos_stock`.
- **Correlación documento↔efecto:** el *Voucher #* de ERPNext enlaza cada línea del ledger con su documento. Es la misma necesidad que el proyecto resuelve con correlación entre venta, pago y movimiento. El proyecto fija la **idempotencia** como **DECISIÓN (Blueprint §10, §7.5)**; el **mecanismo** de correlación por una entidad `operaciones` (Alternativa B: tabla `operaciones` mínima) es **APROBADO CONCEPTUALMENTE** (Blueprint §7.9, §8).
- **Se parece** en **documento confirmado inmutable + corrección compensatoria**, que coincide con **DECISIÓN (Blueprint §3.3, §7.5)**: una jornada cerrada no se modifica; se corrige con ajustes compensatorios auditados. El *cancel + amend* de ERPNext no está explícitamente aprobado en el proyecto, pero el patrón conceptual es análogo.
- **Se diferencia** en que la reconciliación de ERPNext fija la **cantidad absoluta** y toca valorización/contabilidad (Difference Account). El proyecto trata la **regularización** como movimiento con motivo y **mantiene el dinero separado** (DECISIÓN, Blueprint §7.8).

**Lección (REFERENCIA EXTERNA).** Dos ideas para tomar como referencia: (1) tipificar el movimiento con un *purpose* que refleje la intención (issue/receipt/transfer/repack), análogo a los `tipo` de `movimientos_stock`; y (2) hacer que cada línea del ledger **apunte a su documento origen** para poder auditar "de dónde salió este movimiento", que es exactamente el problema de correlación del proyecto. El modelo técnico interno (*Stock Ledger Entry* como doctype) no se verificó en detalle: **sin verificar**.

---

## 3. InvenTree — inventario de componentes

**Qué es (REFERENCIA EXTERNA).** InvenTree es un sistema open-source de gestión de inventario orientado a partes/componentes, con foco en trazabilidad. Fuente: <https://docs.inventree.org/en/stable/stock/>

**Modelo de stock (REFERENCIA EXTERNA).**
- **Stock Item.** Un *Stock Item* es "an actual instance of a Part item. It represents a physical quantity of the Part in a specific location." Cada *Part* puede tener varios *Stock Items* en distintas cantidades y ubicaciones, cada uno con **Location**, **Quantity**, estado, lote/serie, etc. Fuente: <https://docs.inventree.org/en/stable/stock/>
- **Stock Locations.** "A stock location represents a physical real-world location where Stock Items are stored." Las ubicaciones son **cascada** (una ubicación puede contener sub-ubicaciones o stock, o ambas). Pueden ser **structural** (solo organizan, sin stock propio) o estar marcadas como **External**: "An external stock location can be used to indicate that items in there might not be available for immediate usage". Fuente: <https://docs.inventree.org/en/stable/stock/>
- **Stock Tracking.** "Every time a Stock Item is adjusted, a Stock Tracking entry is automatically created… a complete history." Los tipos de evento incluyen: *Stock counted* (10), *Stock manually added* (11), *Stock manually removed* (12), *Returned to stock* (15), *Location changed* (20), *Sent to customer* (100) y *Returned from customer* (105). Las entradas de tracking **se conservan aunque el Stock Item se borre**. Fuente: <https://docs.inventree.org/en/stable/stock/tracking/>

**Patrón relevante (REFERENCIA EXTERNA).** InvenTree mantiene un **historial de eventos por ajuste** (quién, cuándo, cuánto cambió) y una noción explícita de **ubicación externa** ("no disponible para uso inmediato"), además de distinguir la **transferencia entre ubicaciones** (*Location changed*) de la **salida/entrada externa** (*Sent to customer* / *Returned from customer*).

**Similitud con este proyecto (REFERENCIA EXTERNA vs DECISIÓN DEL PROYECTO).**
- **Se parece** en el **historial de ajustes**: InvenTree registra cada ajuste con usuario, fecha y cambio de cantidad. Es análogo a la **DECISIÓN DEL PROYECTO (Blueprint §7.4)**: todo cambio de stock es un movimiento con usuario, fecha/hora y motivo.
- **Se parece** en **interna vs. externa**: la marca *External* de InvenTree es conceptualmente la misma distinción que el proyecto necesita entre ubicaciones internas (depósito, camión, cuarentena) y **salidas terminales** (venta al cliente, merma). Coincide con **DECISIÓN (Blueprint §7.2, §7.4)**.
- **Se parece** en que conserva el historial aunque el objeto se borre, alineado con la idea del proyecto de **no borrar movimientos confirmados** (DECISIÓN, Blueprint §5, §10).
- **Se diferencia** en grano: InvenTree rastrea por **instancia de parte** (stock items individuales, con serial/lote), mientras el proyecto Fase 1 rastrea por **cantidad entera por producto y ubicación**, sin serialización ni trazabilidad por partida (DECISIÓN, Blueprint §7.1; vencimiento por partida es **fuera de alcance / propuesta no aprobada**).

**Lección (REFERENCIA EXTERNA).** La distinción **"externo = no disponible para uso inmediato"** es una forma sencilla y verificable de separar lo interno de lo terminal, y el tipo de evento *Location changed* vs *Sent to customer* muestra cómo un mismo ledger puede expresar tanto transferencias internas como salidas al exterior.

---

## 4. OpenBoxes — logística de depósitos

**Qué es (REFERENCIA EXTERNA).** OpenBoxes es un "open-source supply chain management system designed to manage supplies and medications for healthcare facilities and disaster response operations". Fuente: <https://docs.openboxes.com/en/latest/>

**Modelo de stock (REFERENCIA EXTERNA).** Según la página de funcionalidades: permite explorar el inventario ("browse your inventory"), ver el **historial de transacciones por producto** ("View transaction history for a product"), gestionar productos complejos, y **rastrear ítems de inventario por lote y vencimiento** ("Track inventory items by lot and expiry"). Fuente: <https://docs.openboxes.com/en/latest/about/features/>

**Patrón relevante (REFERENCIA EXTERNA).** OpenBoxes trabaja con **stock cards / historial de transacciones por producto** y con operaciones de depósito (recepciones y envíos entre ubicaciones). El detalle de su modelo interno de movimientos y de sus documentos de depósito no se relevó contra documentación oficial en esta investigación: **sin verificar**.

**Similitud con este proyecto (REFERENCIA EXTERNA vs DECISIÓN DEL PROYECTO).**
- **Se parece** en el enfoque de **historial por producto** como registro principal. Coincide con la **DECISIÓN DEL PROYECTO (Blueprint §11)**: el reporte de **Movimientos** es un historial filtrable por producto, tipo, fecha, jornada y usuario.
- **Se parece** en el manejo de **lotes y vencimiento**, pero acá hay que ser cuidadoso: en OpenBoxes el lote/vencimiento es **parte del modelo**. La **DECISIÓN DEL PROYECTO (Blueprint §7.1, §5)** es lo contrario para Fase 1: **sin trazabilidad por lote ni saldo por partida**; el vencimiento por partida es **PROPUESTA NO APROBADA**. Es un **contraste** útil: OpenBoxes muestra el costo de modelar lotes/vencimiento, que el proyecto decide **no** asumir en Fase 1.
- **Se diferencia** en dominio: OpenBoxes es logística de depósitos y salud; el proyecto es distribución en camión con rendición por jornada.

**Lección (REFERENCIA EXTERNA).** Confirma que un "historial de transacciones por producto" es un artefacto de primera clase en sistemas de stock serios, y sirve como advertencia de que los lotes/vencimientos agregan complejidad —lo que respalda la **decisión del proyecto de dejarlos fuera de Fase 1**—. Detalles internos de su modelo: **sin verificar**.

---

## 5. Snipe-IT — activos (contraste, no es stock por cantidad)

**Qué es (REFERENCIA EXTERNA).** Snipe-IT es un "free, open source IT asset management system… management of assets, users, licenses, accessories, consumables and components". Fuente: <https://snipe-it.readme.io/docs/introduction>

**Modelo de stock (REFERENCIA EXTERNA).** Es un sistema de **gestión de activos**: rastrea **activos individuales** asignables a usuarios y ubicaciones (`assigned_to`, `location`, `status_label`, `serial`), no cantidades fungibles. Fuente: <https://snipe-it.readme.io/docs/consumables> (la API de *consumables* expone campos como `qty` y `remaining`, es decir los consumibles sí llevan cantidad, pero los **activos** se modelan uno por uno). La propia documentación de Snipe-IT aclara la diferencia de categorías: *Inventory Management System* "keeps track of stock" frente a *Asset Management* que "manages many unique items… assignable to users / groups / locations". Fuente: <https://snipe-it.readme.io/docs/introduction>

**Patrón relevante (REFERENCIA EXTERNA / CONTRASTE).** Snipe-IT **no** es un ledger de cantidades: modela **un registro por activo**, con *checkout/checkin* (asignar/devolver) en lugar de movimientos de cantidad origen→destino. Su tracking es de **custodia** ("quién tiene qué"), no de saldo numérico por ubicación.

**Similitud / contraste con este proyecto (REFERENCIA EXTERNA vs DECISIÓN DEL PROYECTO).**
- **Contrasta** con el proyecto: este proyecto necesita **stock por cantidad** (enteros en unidad mínima, Blueprint §7.1) y un **ledger de movimientos**, no custodia de activos serializados. Snipe-IT es útil justamente como **contraejemplo**: muestra que "rastrear cosas" y "llevar stock por cantidad" son problemas distintos.
- **Se parece** solo en la parte de **ubicaciones y estados** (dónde está algo, en qué estado está), que el proyecto también maneja (ubicación + estado), pero con **saldos por suma de movimientos** y no con ítems individuales.

**Lección (REFERENCIA EXTERNA).** Sirve para **delimitar el problema**: el proyecto es un sistema de **stock por cantidad con ledger**, no un sistema de activos. Evita arrastrar conceptos de "activo asignable" que no corresponden a lácteos y fiambres. Detalles de su modelo de licencias/consumibles más allá de lo citado: **sin verificar**.

---

## 6. Referencias transversales: ledger append-only, doble entrada y event sourcing

**Qué es (REFERENCIA EXTERNA).** Más allá de un ERP concreto, existe un patrón general de diseño: guardar los cambios como una **secuencia de eventos/entradas inmutables** y **derivar** el estado actual reprocesándolos. Martin Fowler lo describe como *Event Sourcing*: "all changes to application state are stored as a sequence of events… we can also use the event log to reconstruct past states". Fuente: <https://martinfowler.com/eaaDev/EventSourcing.html> Fowler nota además que la contabilidad es un ejemplo natural: las *Accounting Entries* "are a log of all of the events that change the value of an Account, so that an Account is itself an example of Event Sourcing". En ERPNext, el enfoque equivalente es el *Stock Ledger* (ver §2), y Odoo expone los movimientos con *Inventory Loss* como contrapartida (ver §1).

**Patrón relevante (REFERENCIA EXTERNA).**
- **Log append-only como fuente de verdad**, con el estado actual **derivado** (por suma o replay).
- **Diferencia en lugar de valor absoluto** para permitir reversión: Fowler recomienda eventos en forma de diferencia ("add $10" y no "set balance to $110") porque son reversibles. Fuente: <https://martinfowler.com/eaaDev/EventSourcing.html>
- **Saldo materializado como caché opcional**, no como verdad, para eficiencia.

**Similitud con este proyecto (REFERENCIA EXTERNA vs DECISIÓN DEL PROYECTO).**
- **Se corresponde** con la **DECISIÓN DEL PROYECTO (Blueprint §3.1, §7.4)**: el stock nunca se edita a mano; el saldo es la suma de movimientos. El patrón de ledger/event log es la formulación general de esa decisión.
- **Se corresponde** con **DECISIÓN (Blueprint §8)**: `saldos_stock` es una tabla que "puede haber… mantenida por la misma transacción", pero "el registro de movimientos es la verdad". Es exactamente el patrón de **estado derivado / caché**. La `docs/propuesta_v2_07_datos_derivados.md` (PROPUESTA, pendiente) lo explicita.
- **Se corresponde** con el uso de **diferencias con dirección por origen/destino** (Blueprint §8) y operaciones compensatorias auditadas (Blueprint §3.3), en línea con la reversibilidad por diferencia de Fowler.
- **Se diferencia** en el alcance del "replay": el proyecto **no** replantea reconstruir todo el estado desde cero ni usar event sourcing completo; se limita a un ledger de stock y documentos financieros separados (DECISIÓN, Blueprint §6, §7.8).

**Lección (REFERENCIA EXTERNA).** Da el **fundamento conceptual** de varias decisiones ya vigentes: ledger append-only, saldo derivado (con caché opcional), diferencias reversibles y no borrado de asientos. Refuerza que el diseño del proyecto es una instancia acotada de un patrón maduro, no una invención local.

---

## 7. Matriz de correspondencia (patrón del proyecto × referencia externa)

La columna "Estado en el proyecto" distingue **DECISIÓN (Blueprint, vigente)** de **PROPUESTA (pendiente)**.

| # | Patrón | Estado en el proyecto | Referencias externas que lo ilustran |
|---|---|---|---|
| 1 | Ledger append-only como fuente de verdad del stock; saldo derivado | **DECISIÓN** (Blueprint §3.1, §6, §7.4, §8) | ERPNext *Stock Ledger*; Odoo *Moves History*; Fowler, *Event Sourcing* |
| 2 | Ubicaciones internas vs. salida terminal (venta, merma), cliente **no** es ubicación interna | **DECISIÓN** (Blueprint §7.2, §7.4) | Odoo *location types* (Internal / Customer / Vendor / Inventory Loss); InvenTree *External location* y eventos *Sent to customer* |
| 3 | Conteo = hecho observado separado; la regularización/ajuste es operación explícita posterior | **DECISIÓN** (Blueprint §7.8, §8) | Odoo *Inventory Adjustments* (registrar ≠ aplicar); ERPNext *Stock Reconciliation* |
| 4 | Correlación de documentos por "operación" lógica + idempotencia | **Idempotencia: DECISIÓN** (Blueprint §10, §7.5). **Tabla `operaciones`: APROBADA CONCEPTUALMENTE** (Blueprint §7.9, §8) | ERPNext *Voucher #* (línea de ledger → documento); InvenTree tracking ligado a orden/build |
| 5 | Registros financieros y de stock separados; una diferencia de stock no corrige dinero | **DECISIÓN** (Blueprint §7.8) | Odoo y ERPNext **integran** valorización/contabilidad (contraste); Fowler: *Accounting Entries* separadas |
| 6 | Cierre de período/jornada por **estado + conciliación + operación** | **Estado de jornada + rendición: DECISIÓN** (Blueprint §7.5, §7.8). **Tabla `cierres` propia: DERIVADA / SIN TABLA EN FASE 1** (Blueprint §7.9.4, §8) | ERPNext documento confirmado inmutable (*cancel + amend*); Odoo confirmación al aplicar ajustes |

---

## 8. Síntesis: qué patrones se adoptan como referencia

Esta sección **no** crea ni modifica reglas: resume los patrones que el relevamiento **respaldaría como referencia** para las decisiones ya tomadas. Cada punto indica su estado real en el proyecto.

1. **Ledger append-only como fuente de verdad del stock (REFERENCIA + DECISIÓN).** El stock se deriva de los movimientos; el saldo no se edita a mano. Confirmado como **DECISIÓN** en Blueprint §3.1, §6, §7.4 y §8. Referencia: ERPNext *Stock Ledger*, Odoo *Moves History*, Fowler *Event Sourcing*.
2. **Ubicaciones internas vs. salida terminal (REFERENCIA + DECISIÓN).** Lo interno mantiene saldo; la venta sale del sistema hacia el cliente (que **no** es ubicación interna) y la merma es descarte. **DECISIÓN** en Blueprint §7.2 y §7.4. Referencia: Odoo *location types*, InvenTree *external locations*. **Detalle resuelto:** `merma` es salida terminal, no ubicación interna (Blueprint §7.2).
3. **Conteos como hecho observado separado de los movimientos (REFERENCIA + DECISIÓN).** Contar no mueve stock; la regularización es una operación explícita posterior con movimiento auditable. **DECISIÓN** en Blueprint §7.8. Referencia: Odoo *Inventory Adjustments*, ERPNext *Stock Reconciliation*.
4. **Correlación de documentos y efectos mediante una operación lógica + idempotencia (REFERENCIA + DECISIÓN).** La **idempotencia** es **DECISIÓN** (Blueprint §10, §7.5); el **mecanismo** de una entidad `operaciones` que agrupe venta + pago + movimiento es **APROBADO CONCEPTUALMENTE** (Blueprint §7.9, §8). Referencia: ERPNext *Voucher #*.
5. **Registros financieros y de stock separados (REFERENCIA + DECISIÓN).** Una diferencia de stock no corrige dinero automáticamente; stock y caja se concilian por separado. **DECISIÓN** en Blueprint §7.8. Referencia (contraste): Odoo/ERPNext, que sí integran valorización con contabilidad.
6. **Cierre de período/jornada por estado + conciliación + operación (REFERENCIA + DECISIÓN).** El cierre se representa por la **transición de estado de la jornada** validada contra la **rendición** (conciliación), más una **operación tipo cierre** para identidad/idempotencia, **no por una tabla de cierre obligatoria**. **DECISIÓN** en Blueprint §7.5, §7.8, §7.9.4. La **tabla `cierres` propia** es **DERIVADA / SIN TABLA EN FASE 1** (Blueprint §7.9.4, §8).

---

## 9. Aclaración final

- Este documento es **material de investigación (research)**. Su estado es **PROPUESTA / INSUMO**: **no** es una decisión aprobada, **no** es fuente de verdad y **no** modifica el `BLUEPRINT.md` ni ninguna ADR.
- No se escribió SQL, ni migraciones, ni RLS, ni RPC, ni cambios de código. No se implementó ninguna regla marcada como `PROPUESTA NO APROBADA` ni ningún mecanismo de `docs/propuesta_v2_*` pendiente de aprobación.
- Toda afirmación sobre sistemas externos se basa en documentación oficial citada, consultada el 20/10/2026; lo no verificado se marcó **"sin verificar"**.
- Cualquier adopción concreta derivada de este relevamiento requiere pasar por el flujo del proyecto: propuesta en `docs/decisions/` con estado `propuesta` y **aprobación humana** explícita, conforme a `AGENTS.md` §3 y `BLUEPRINT.md` §13.