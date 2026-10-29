# BLUEPRINT — Sistema de Control para Distribuidora de Lácteos y Fiambres

**Proyecto:** VM Digital Studio
**Versión:** 2.4 (documento de trabajo controlado; propuestas no aprobadas identificadas)
**Fecha:** 29/10/2026 (hora local Argentina)
**Estado:** Apto para inventario técnico, planificación y validación controlada de ADR-001 exclusivamente en local/staging. No autoriza implementar decisiones pendientes ni ejecutar migraciones productivas. Entregas 1A/1B pendientes de aprobación comercial.

> Este documento es la fuente de referencia del proyecto. Todo agente (Claude Code, OpenCode, Codex) y toda persona que trabaje en el repositorio debe leerlo antes de escribir código. Si algo del código contradice este documento, el documento manda hasta que se registre una decisión que lo cambie (ver sección 13: ADR).

---

## 1. Objetivo del sistema

El dueño necesita **saber qué mercadería sale en cada camión, qué se vendió y qué volvió**, y detectar faltantes de mercadería y de dinero por camión, por jornada y por vendedor.

Todo lo que no sirva a ese objetivo queda fuera de la Fase 1.

### Pregunta que el sistema debe responder siempre

> "El camión X salió el día D con esta carga. Según las ventas y devoluciones, debería haber vuelto con A y entregado $B. Volvió con C y entregó $E. **La diferencia es esta, y estos son los responsables de cada paso.**"

---

## 2. Contexto y decisiones confirmadas

- Distribuidora de lácteos y fiambres; operación inicial de dos camiones (cantidad final por validar). Se estima **6 a 10 usuarios**.
- **Venta digital online-first:** el vendedor/piloto registra las operaciones desde Android cuando hay conexión. Si no hay Internet, utiliza **talonario numerado de papel**; debe cargar y confirmar todas las notas pendientes **antes de iniciar el conteo formal de regreso**. No se implementa sincronización offline automática.
- Los vendedores **pueden dar de alta clientes nuevos**, pero **no modificar fichas existentes**. El dueño/encargado valida y puede completar o corregir fichas. Reglas de duplicados y datos obligatorios pendientes de acordar.
- Un camión **no puede realizar más de una jornada en el mismo día**, incluyendo jornadas cerradas; excepción no prevista en Fase 1.
- Clientes pueden pagar con **medios combinados**. Se separan efectivo, transferencia y saldo a cuenta, según los medios que el cliente confirme en operación.
- El dueño o encargado puede **retirar efectivo en cualquier momento del recorrido**: queda fecha/hora de registro del servidor, hora declarada del hecho si difiere, quién entrega, quién recibe, importe, camión, jornada y confirmación de **ambas personas**.
- Gastos del recorrido con dinero recaudado: **solo con autorización** del dueño/encargado y comprobante/motivo registrados (detalle pendiente).
- El cierre con diferencias lo aprueba **dueño o encargado**, sin eliminar la diferencia registrada.
- **Unidades (decisión del cliente del 25/10/2026; ADR-005, aprobada):** los **lácteos** y productos por unidad se venden y controlan por **cantidad/unidad entera**. Los **fiambres** se venden y controlan **por peso**: comercialmente se expresan **en kg**, se ingresan con **hasta 3 decimales** y se muestran con **3 decimales fijos** (`28,680 kg`), el precio es **por kg** y la representación canónica es un **entero en gramos**. La pieza y la media pieza **dejaron de existir** como unidad de venta, stock o precio (reemplaza la regla vigente del 13/10 al 25/10/2026; histórico en ADR-002/ADR-003). Nunca se usa `float`. Decisiones humanas del 26/10/2026 (ADR-005 D-R1–D-R4): el importe de cada línea `peso` se redondea una sola vez al **peso entero** (0,50 hacia arriba) y el total suma el importe final de cada línea según la regla de su tipo (la de las líneas `unidad` y, con ella, los centavos de un documento mixto siguen pendientes); cada operación registra el **peso efectivamente medido**; Fase 1 **no aplica tolerancia** a diferencias de pesaje; el modelo anterior de pieza/media pieza se **reinicia limpio**, sin conversión. El prototipo demo todavía implementa pieza/media pieza y requiere un cambio posterior autorizado (ver §7.1).
- **Presupuestos (decisión del cliente del 25/10/2026):** el sistema debe generar **presupuestos** internos para clientes, con IVA 21% **sólo como etiqueta informativa** y **sin descuentos**. Un presupuesto **no** es venta ni factura, **no** mueve stock ni dinero y **no** integra ARCA (ver §7.10).
- Vencimientos: el cliente pidió **control de vencimientos asociado a productos, sin trazabilidad por lote**. **PROPUESTA TÉCNICA NO APROBADA:** anotar fecha de vencimiento en cada ingreso de mercadería, sin asignar ventas a ingresos ni prometer saldos disponibles por partida. Ver secciones 4, 5 y 8.
- Devoluciones: **tratamiento según producto**. No exigen aprobación humana general para retornar al stock vendible, pero **nunca** se reingresará automáticamente mercadería no apta: debe cumplir reglas verificables de aptitud, origen y conservación; criterios pendientes.
- **Fase 2:** preventa, pedidos programados, proveedores, compras, comprobantes de compra, pagos combinados a proveedores, cuotas y cuentas corrientes de proveedores. En Fase 2 se contemplará recepción distinta de la fecha de compra y almacenamiento privado de foto/PDF de comprobantes.
- No incluye emisión fiscal por ARCA. Los comprobantes de Fase 1, incluidos los presupuestos, son internos.

---

## 3. Principios

1. **El stock nunca se edita a mano.** Todo cambio de stock es un movimiento registrado (quién, cuándo, por qué, cuánto, desde dónde, hacia dónde).
2. **Separación de responsabilidades.** Quien cuenta el regreso no es el vendedor. El sistema registra quién hizo cada paso.
3. **Una jornada cerrada no se modifica.** Las correcciones posteriores se hacen con ajustes con motivo, auditados.
4. **Simple antes que completo.** Ante la duda, la versión más simple que cumpla el objetivo.
5. **Nada se da por terminado sin prueba.** Un error no está resuelto porque un agente diga que lo resolvió: necesita test o verificación documentada.

---

## 4. Alcance — Fase 1 (funcionalmente acordado; confirmar con la cotización comercial del proyecto)

| Módulo | Entrega propuesta | Incluye |
|---|---|---|
| Productos | 1A | Alta, edición y baja lógica por dueño/encargado. Categoría, forma de venta (`unidad` / `peso`), precio de venta (unitario en `unidad`; **por kg** en fiambres `peso`; ADR-005) y stock mínimo. Fiambres por peso (kg en pantalla, gramos enteros como canónico). Alertas orientativas de vencimiento por fecha de cada ingreso (**propuesta pendiente de aprobación**, sin FEFO). |
| Clientes | 1A; altas desde celular en 1B | Consultar y buscar; alta inicial por vendedor; dueño/encargado editan y validan. Historial básico. |
| Depósito y camiones | 1A | Stock por ubicación, carga por jornada, movimientos auditados, cuarentena y retornos. |
| Jornadas | 1A | Una jornada por camión y fecha, asignación de vendedor, preparación, salida, carga final de ventas, conteo por tercero, rendición, cierre. |
| Autoventa | 1A papel / 1B digital | Venta online en Android; talonario numerado como contingencia manual; carga de pendientes antes del conteo; control de duplicados y notas anuladas. |
| Pagos de ventas | 1A papel y pagos mixtos / 1B digital | Registro de múltiples medios por venta: efectivo, transferencia, importe a cuenta; suma de pagos = importe de la venta. Gestión completa de cuentas corrientes de clientes queda en Fase 2. |
| Retiros de efectivo | 1A registración diferida / 1B en vivo | En cualquier momento; autorización del dueño/encargado, doble confirmación del receptor y vendedor, auditoría y afectación a saldo de efectivo por rendir. |
| Gastos en ruta | 1A registración autorizada / 1B interfaz móvil | Registrados únicamente con autorización; reglas de desembolso, motivos y comprobantes pendientes de definición. |
| Devoluciones/mermas | 1A | Motivos, clasificación por aptitud, segregación de cuarentena y trazabilidad; aptitud según producto sin autorización genérica para todos los retornos. |
| Rendición | 1A | Mercadería esperada vs contada por estado, y efectivo/transferencias/a cuenta/retiros separados; diferencias aceptables solo con aprobación y motivo. |
| Reportes y usuarios | 1A; ampliaciones en 1B | Rendiciones, diferencias, stock, ventas, retiros de efectivo, exportación CSV, 3 roles (dueño, encargado, vendedor/piloto), RLS y auditoría. |
| Presupuestos | Fase 1; entrega (1A/1B) pendiente de acuerdo comercial | Generación y consulta de presupuestos internos por dueño/encargado (vendedor/piloto: pendiente), con número, fecha, hora, datos del cliente y detalle de productos `unidad` y `peso`; IVA 21% sólo informativo; sin descuentos. **No** mueve stock, **no** mueve dinero y **no** es factura ni comprobante fiscal (§7.10). |

**Extras no comprometidos** (sujetos a tiempo y aprobación): impresión de carga, comprobante interno, alertas básicas y búsquedas avanzadas. No confundir con el alcance de Fase 2.

---

## 5. Fuera de alcance — decisiones confirmadas

### Fase 2 (no incluida en la primera entrega; presupuestar/planificar)
- **Preventa y pedidos programados**, duplicación de pedidos.
- **Proveedores y compras:** alta, historial, fecha compra vs fecha de recepción, remito y factura sin duplicar ingresos, foto/PDF en almacenamiento privado, costo histórico y vencimientos de deuda.
- **Pagos a proveedores:** efectivo + transferencia + saldo a cuenta en una compra, cuotas, pagos parciales, fechas y cuenta corriente de proveedor.
- Gestión completa de **cuenta corriente de clientes** (aplicación de cobros a documentos, vencimientos y saldos históricos). En Fase 1 solo se registra el importe vendido a cuenta y se informa.
- Gestión por **lotes y FEFO**; la propuesta inicial solo genera alertas orientativas por fecha de ingreso, sin saldo por partida ni trazabilidad de salida.
- Listas de precios por cliente, exportaciones ampliadas y reportes avanzados.

### Fuera del alcance actual, sin fecha comprometida
- Facturación electrónica ARCA; los comprobantes internos, incluidos los presupuestos de §7.10, no son facturas fiscales. El presupuesto no calcula, discrimina ni liquida IVA.
- Aplicación Android nativa; modo offline automático/sincronización.
- GPS/seguimiento en vivo, optimización de rutas, integraciones bancarias.
- Funciones de IA en el producto, n8n, módulo sanitario regulatorio o plataforma SaaS completa.

---

## 6. Arquitectura

```
Frontend:  React + TypeScript + Vite — web responsive — deploy en Vercel
Backend:   Supabase — Auth · PostgreSQL · RLS · RPC (funciones SQL) · Storage
```

- **La lógica que mueve stock o dinero vive en funciones de la base (RPC)**, no en el frontend. El frontend nunca inserta movimientos de stock directamente.
- Cada operación crítica (cargar camión, registrar regreso, cerrar jornada) es **una transacción**: o se guarda todo, o nada.
- Las tablas de movimientos son **solo de inserción**: no se permite UPDATE ni DELETE sobre ellas.

---

## 7. Reglas de negocio

### 7.1 Unidades: unidad entera y peso

> **Vigente desde el 25/10/2026 — [ADR-005](docs/decisions/005-fiambres-por-peso-gramos.md), aprobada.** Reemplaza la regla anterior de pieza/media pieza (13/10–25/10/2026), que se conserva sólo como historial en ADR-002, ADR-003 y en `docs/requirements/migracion-unidades-prototipo.md`. ADR-005 **no autoriza** migraciones ni implementación: el cambio de modelo requiere una tarea posterior específica.

- Cada producto tiene una **forma de venta** (valores conceptuales; el nombre y el tipo SQL definitivos se fijan en la tarea de migración):
  - `unidad` — **lácteos** y productos por unidad: se venden y controlan por **cantidad/unidad entera** (ej. yogur, sachet de leche, caja). Nunca fracciones.
  - `peso` — **fiambres**: se venden, cargan, cuentan, retornan y rinden **por peso**.
- **No existen la pieza ni la media pieza** como unidad de venta, de stock ni de precio.
- **Productos `peso`:**
  - **Entrada:** kilogramos con **hasta 3 decimales** (son válidas, por ejemplo, `1`, `1,2`, `1,25` y `1,250`). Una cantidad con **más de 3 decimales de kg se rechaza**: no se redondea, no se trunca ni se normaliza.
  - **Presentación comercial:** kilogramos con **3 decimales fijos** (`1,000 kg`, `1,200 kg`, `1,250 kg`, `28,680 kg`).
  - **Representación canónica:** **entero en gramos** (`28,680 kg` → `28680`; `1,250 kg` → `1250`).
  - La conversión kg ↔ gramos se hace sobre la representación decimal exacta, **nunca con punto flotante** (en JavaScript, `1.005 * 1000` da `1004.9999999999999`).
- **Unidad mínima:** **unidad entera** para `unidad`; **gramo** para `peso`. **Todas las cantidades en la base son enteros en la unidad mínima**; nunca `float`, `double precision` ni `real`.
- **Consistencia categoría/forma de venta:** `Lácteos` ↔ `unidad`; `Fiambres` ↔ `peso`. **No** se admiten `Lácteos` + `peso` ni `Fiambres` + `unidad`. *(Ejemplo de coherencia, no una regla sobre nombres de producto: `Queso cremoso en bote` (untable) → `Lácteos` / `unidad`.)*
- **Precio:**
  - un producto `unidad` tiene un único **precio unitario**; un producto `peso` tiene un único **precio por kg**;
  - los precios admiten como máximo 2 decimales (más de 2 se rechaza, sin redondear ni truncar). Precio 0: se mantiene la validación mínima vigente (`>= 0`); exigir `> 0` sería otra decisión;
  - el dinero se guarda en `numeric(14,2)`, nunca `float`.
- **Importe de una línea (conceptual):**
  - `unidad`: `cantidad × precio_unitario`;
  - `peso`: `cantidad_kg × precio_por_kg` = `gramos × precio_por_kg / 1000`.

- **Redondeo monetario del importe por peso (ADR-005 D-R1, decisión humana del 26/10/2026):**
  - el **importe exacto** `gramos × precio_por_kg / 1000` se calcula con aritmética exacta (enteros o `numeric`), nunca con `float`, `real` ni `double precision`; puede tener más de 2 decimales (hasta 5 con gramos enteros y precios con 2 decimales);
  - **cada línea `peso` se redondea una sola vez** al **peso entero más cercano**, con **empate 0,50 hacia arriba**: para importes positivos, una fracción menor que 0,50 va al peso inferior y una fracción mayor o igual que 0,50 va al peso superior (`$1.543,20 → $1.543`; `$1.544,49 → $1.544`; `$1.544,50 → $1.545`; `$1.544,99 → $1.545`);
  - el **total del documento** es la **suma de los importes finales determinados para cada línea según la regla aplicable a su tipo de producto**: para líneas `peso` esa regla ya está definida por D-R1 (se suman sus importes ya redondeados, sin recalcularlos desde cantidades y precios exactos); para líneas `unidad` la regla monetaria final sigue **pendiente**; por lo tanto, el comportamiento final de centavos en documentos mixtos `peso` + `unidad` también sigue **pendiente**;
  - aplica conceptualmente a **ventas**, **presupuestos** y a cualquier otra valorización por peso cuyo importe dependa de esta regla; no se extiende a módulos todavía no definidos;
  - **tipo monetario:** `numeric(14,2)` sigue siendo el tipo monetario general y representa el importe redondeado con centavos `.00` (por ejemplo, `1545.00`). Esta decisión **no** cambia el tipo SQL del dinero a `integer`; un cambio de esquema requeriría una decisión posterior. El redondeo se aplica de forma explícita en la implementación, nunca confiando en el redondeo implícito al guardar en `numeric(14,2)`;
  - **líneas `unidad`:** la fórmula vigente es `cantidad × precio_unitario`; permanece **pendiente** (§15) decidir si el importe final de una línea `unidad` se conserva con centavos o se redondea al peso entero, y qué consecuencia tiene eso sobre el total de un documento mixto (`peso` + `unidad`). Ejemplo del problema, no decisión: `3 × $1.234,56 = $3.703,68`; qué importe comercial final corresponde a esa línea y si, por lo tanto, un documento mixto puede terminar con centavos sigue pendiente. D-R1 aplica únicamente a líneas `peso` y no lo resuelve.
- **Peso efectivamente medido (ADR-005 D-R2, decisión humana del 26/10/2026):** cada operación de mercadería por peso registra el **peso efectivamente medido para esa operación**, en gramos enteros (presentado en kg con 3 decimales fijos). Nunca se arrastra como verdad un peso teórico anterior:
  - **ingreso:** el peso realmente recibido, que entra al depósito;
  - **carga:** el peso realmente cargado al camión; el mismo valor en gramos es el débito del depósito y el crédito del camión de esa operación;
  - **venta:** el peso efectivamente entregado al cliente, que descuenta el stock del camión;
  - **devolución del cliente:** el peso efectivamente recibido de vuelta; su clasificación posterior sigue las reglas vigentes de aptitud y cuarentena (§7.7);
  - **conteo de regreso:** el peso físicamente pesado al regreso, que se compara contra el esperado (§7.8, §7.9.2).

  El sistema registra el peso informado o medido. **No** se definen modelo o marca de balanza, integración electrónica, Bluetooth, captura automática ni la obligación de pesar en un punto físico específico.
- **Diferencias de pesaje (ADR-005 D-R3, decisión humana del 26/10/2026):** Fase 1 **no aplica tolerancia automática**. Toda diferencia distinta de cero entre el peso real y el esperado, incluso de 1 gramo, se registra como diferencia (§7.8).
- **Historial:** cada ítem de venta o de presupuesto conserva la cantidad canónica, el precio aplicado (unitario o por kg) y el importe. Un documento histórico se reconstruye con esos valores, **sin volver a calcularlos** (ADR-005 §2.3).
- **Estado actual del código:**
  - **SQL (Slice A, `20261027001542_modelo_peso_gramos.sql`; validado sólo en local, staging pendiente de autorización):** `productos` admite `forma_venta in ('unidad','peso')` con `lacteos ↔ unidad` y `fiambres ↔ peso`; `precio numeric(14,2)` es unitario o por kg; `stock_minimo integer` está en unidades o gramos. `movimientos_stock.cantidad integer` y las RPC de stock (`p_cantidad integer`, firmas sin cambios) reciben el entero canónico: unidades o gramos según la `forma_venta` del producto. La migración falla cerrada si existe algún producto `pieza` (D-R4) y no convierte datos. D-R1 todavía no se implementa: no existen ventas ni presupuestos en SQL.
  - **Pantalla Productos (catálogo de Supabase), adaptada en Slice A:** acepta `unidad`/`peso` y rechaza `pieza`. Rotula el precio por unidad o por kg. El stock mínimo de los productos `peso` se ingresa y se muestra en kg con 3 decimales y se envía en gramos exactos, sin punto flotante.
  - **Prototipo demo (`apps/web/src/`, resto de las pantallas operativas; pendiente de Slice B, no cumple esta regla):** implementa pieza/media pieza con precio derivado (ADR-003) sobre las claves `_demo_v4` (`distribuidora_productos_demo_v4`, `distribuidora_jornadas_demo_v4`, `distribuidora_ventas_demo_v4`, `distribuidora_cobros_demo_v4`, `distribuidora_movimientos_demo_v4`, `distribuidora_retornos_demo_v4`, `distribuidora_camiones_demo_v4`; `clientes` en `distribuidora_clientes_demo_v2` y la sesión en `distribuidora_sesion_demo_v1`).
  - Al cambiarlo se aplica el criterio ya aprobado para cambios de semántica: **versión nueva de las claves operativas, inicialización limpia y sin leer, copiar, reinterpretar ni borrar automáticamente las anteriores**. Una media pieza guardada nunca se reinterpreta como gramo. La versión exacta se fija en esa tarea.
- **Datos del modelo anterior (ADR-005 D-R4, decisión humana del 26/10/2026): reinicio limpio.** No existe conversión automática ni reinterpretación: **una cantidad histórica expresada en medias piezas nunca se interpreta como gramos**. En local y staging, los datos operativos de prueba del modelo anterior no se migran semánticamente a gramos; la implementación futura aplica el modelo nuevo e inicializa fixtures compatibles, sin copiar saldos en medias piezas como si fueran gramos. Al cierre de la validación de la Etapa 2 (26/10/2026, `docs/progress-log.md`) staging quedó sin datos de negocio; eso es evidencia de ese momento y no garantiza que siga vacío. En el prototipo demo rige el criterio de versionado de claves del punto anterior. Producción no está autorizada y no hay autorización para migrar datos productivos.

### 7.2 Ubicaciones de stock

**Ubicaciones internas reales en Fase 1** (mercadería bajo control del sistema):

| Ubicación | Significado |
|---|---|
| `deposito` | Mercadería vendible en el depósito. |
| `cuarentena` | Mercadería devuelta o dudosa, pendiente de decisión (apta / merma). Sigue físicamente bajo control aunque no esté disponible para venta. No se puede cargar a un camión. |
| `camion:<id>` | Mercadería que está arriba de un camión en una jornada abierta. |

**La merma NO es una ubicación interna de stock en Fase 1.** Es una **salida terminal** del sistema, registrada con `tipo_movimiento = merma` (origen: camión o depósito; destino: exterior/null). Análogamente, una **venta** es `camión → exterior/null` con `tipo_movimiento = venta`.

**El cliente no es una ubicación interna de stock.** Es la contraparte comercial del documento `venta`; la mercadería entregada sale del inventario del sistema. No se modela al cliente como origen/destino de `movimientos_stock`.

La estructura exacta de `ubicaciones` (columnas, si una fila de cuarentena/depósito es por empresa, cómo se referencia el camión sin duplicar identidad) queda pendiente de diseño SQL/RPC. **APROBADA CONCEPTUALMENTE.**


### 7.3 Empresa única y aislamiento por `empresa_id`

**Decisión humana (23/10/2026): el producto es para UNA SOLA EMPRESA OPERATIVA.** No es multiempresa, multi-tenant ni SaaS. **Fase 1 tiene entidad `empresas`** (APROBADA CONCEPTUALMENTE) como soporte técnico de esa única empresa operativa:

- todas las tablas de negocio llevan `empresa_id` con FK a `empresas`, como clave técnica de pertenencia, frontera de aislamiento, soporte de RLS e integridad referencial (defensa en profundidad);
- las políticas RLS filtran por `empresa_id`;
- **empresa y rol se obtienen desde tablas protegidas**, nunca desde `user_metadata` ni desde datos modificables por el usuario.

Cada usuario pertenece a una única empresa: un perfil 1:1 con `auth.users`, con una empresa y un rol (decisión humana P5–P7, ADR-001 §18). No existen selector de empresa, membresías, workspaces, administración de empresas, registro ni onboarding de empresas, invitaciones, planes ni suscripciones, y no debe diseñarse ninguna funcionalidad SaaS. La presencia de `empresa_id` no autoriza ni implica funcionalidad multiempresa. Una segunda empresa en los tests es únicamente un fixture adversarial para comprobar el aislamiento por `empresa_id`.

### 7.4 Movimientos de stock

`movimientos_stock` es un **ledger append-only** y la **fuente de verdad del stock** (APROBADA CONCEPTUALMENTE). Todo cambio de stock genera un registro con estos conceptos:

- `empresa` (obligatorio);
- `operacion` — ejecución lógica que originó el movimiento (ver §7.9);
- `jornada` cuando aplique (opcional según tipo);
- `producto`;
- `cantidad` — entero positivo en unidad mínima: unidad entera para productos `unidad`, **gramos** para productos `peso` (§7.1, ADR-005); en productos `peso` es el **peso efectivamente medido en esa operación** (ADR-005 D-R2);
- `ubicacion_origen` (nullable) y `ubicacion_destino` (nullable) — al menos uno no nulo;
- `tipo_movimiento`;
- `actor` (usuario);
- `motivo` cuando corresponda;
- `creado_en`.

**No existe `saldo_actual` en el ledger.** El saldo se deriva de la suma de movimientos (§7.4 y §8).

Tipos de movimiento (conceptual; la lista exacta queda para diseño SQL):

| Tipo | Origen → Destino |
|---|---|
| `ingreso` | (exterior) → depósito |
| `carga` | depósito → camión |
| `venta` | camión → exterior/null; la contraparte queda en `ventas` |
| `retorno` | camión → depósito (fin de jornada) |
| `devolucion_cliente` | exterior → camión (recepción física); reclasificación posterior según aptitud |
| `a_cuarentena` | camión/depósito → cuarentena |
| `cuarentena_apta` | cuarentena → depósito |
| `merma` | camión/depósito → exterior/null (salida terminal) |
| `regularizacion_faltante` | ubicación → exterior/null (operación explícita autorizada) |
| `regularizacion_sobrante` | exterior/null → ubicación (operación explícita autorizada) |
| `ajuste` | cualquiera, con motivo obligatorio y permiso de administrador |

Los movimientos son **solo de inserción**: no se permite UPDATE ni DELETE. La rectificación se hace con movimientos compensatorios auditados.

El stock de cada ubicación es la **suma de sus movimientos**. **No se permiten saldos negativos silenciosos.** Si una venta en papel aún no registrada hace que una venta posterior exceda el saldo informático, registrar una incidencia de conciliación y exigir regularización trazable por dueño/encargado; la venta física realizada nunca se borra ni se inventa stock. El procedimiento excepcional de regularización requiere definición y prueba antes de producción. **PROPUESTA NO APROBADA:** permitir negativo transitorio exclusivamente en la ubicación del camión con jornada abierta, marcar la venta `excede_stock`, registrar incidencia y bloquear el cierre hasta regularización autorizada; depósitos y cuarentena nunca en negativo. Debe revisarse también con operaciones simultáneas.

### 7.5 Jornada y ventas (online-first + papel)

Flujo lógico: `abierta → cargada → en_reparto → ventas_finalizadas → regreso_contado → cerrada`. Los eventos se registran por separado y el cierre exige su validación; evitar transiciones implícitas. Puede registrarse un retiro de efectivo mientras la jornada esté en reparto.

- **Una sola jornada por (`empresa_id`, `camion_id`, `fecha`)**, aunque otra del mismo día esté cerrada; no habrá segunda salida por camión ese día.
- El vendedor registra ventas digitales con conexión. Sin conexión usa talonario numerado; **debe transcribir, guardar en servidor y declarar completas** las ventas en papel antes de que el encargado inicie el **conteo formal**. El camión puede ingresar físicamente al predio; el sistema solo bloquea el proceso administrativo.
- Identificar origen de venta (`digital`/`papel`), serie y número de nota (cuando aplique), usuario, instante de registro del servidor, jornada, cliente, ítems, precios históricos y pagos. Cada ítem guarda la cantidad en unidad mínima (unidades o gramos), el precio aplicado (unitario o por kg) y el importe (§7.1). En un ítem `peso`, la cantidad es el **peso efectivamente entregado** al cliente (ADR-005 D-R2) y el importe es el redondeado por línea según D-R1. El total de la venta es la suma de los importes finales de cada línea según la regla aplicable a su tipo de producto (§7.1): D-R1 para `peso`; para `unidad`, y por lo tanto para los centavos de una venta mixta, sigue pendiente. Conviene diseñar la venta por peso sobre el modelo por peso ya migrado; el orden de ejecución lo autoriza el humano según §14.
- **Una línea por producto ([ADR-006](docs/decisions/006-una-linea-por-producto-en-venta-nueva.md), aprobada el 29/10/2026):** en una venta **nueva**, `productoId` es único dentro de los ítems, cualquiera sea su unidad (`unidad` o `peso`, incluso con unidades distintas). Dos o más líneas del mismo producto **invalidan** la venta: se rechaza sin persistir y no se consolida automáticamente. La regla no se aplica retroactivamente: una venta histórica con líneas repetidas se sigue leyendo con sus valores almacenados, sin recalcularla ni migrarla, y su consumo de stock es la suma de sus líneas. Una nota de papel transcripta como venta nueva también debe cumplirla. D-R1 no cambia; la fragmentación en ventas distintas no queda resuelta por esta regla.
- La validación de duplicados se realiza por empresa, serie y número **en todo el histórico**, no solamente dentro de una jornada; también idempotencia por solicitud. Notas anuladas se preservan con motivo y sin efecto de stock/dinero. Registrar saltos de numeración y resolución.
- **Anulación — PROPUESTA NO APROBADA:** vendedor anula solo sus propias ventas antes de finalizar ventas (`ventas_finalizadas`) y con motivo obligatorio; luego solo dueño/encargado con operación compensatoria. Toda anulación aparece en rendición y auditoría. No implementar sin aprobación.
- **Precios/descuentos — PROPUESTA NO APROBADA:** el vendedor no puede modificar precios ni otorgar descuentos en Fase 1; utiliza el precio configurado. Registrar precio de lista y precio aplicado históricos; excepciones futuras requieren nueva decisión.
- **Disponible desde 1A en notas de papel:** las ventas de una jornada pueden usar varios medios: suma de componentes (efectivo, transferencia, a cuenta) debe igualar total; no usar `a_cuenta` como dinero ingresado. En 1B se habilita la captura digital móvil.
- El vendedor puede **crear** un cliente mínimo durante el reparto; nunca **editar** clientes existentes. Dueño/encargado pueden corregir y validar.
- Conteo realizado por dueño/encargado, **distinto de quien actuó como vendedor** en esa jornada. Si no existe otra persona disponible, queda pendiente, sin autobypass.
- Dueño/encargado aprueban y cierran rendiciones incluso con diferencias, guardando valores, motivo, identidad y fecha. Jornada cerrada es inmutable; rectificaciones con operaciones compensatorias auditadas.

### 7.6 Retiros de efectivo y gastos autorizados

- Retiro físico en cualquier momento durante el recorrido, iniciado por dueño/encargado; capturar `jornada_id`, `camion_id`, monto positivo, actor receptor, vendedor entregante, motivo y hora real declarada si difiere del registro.
- En **1A**, el retiro ocurrido en ruta se **registra diferidamente durante la rendición**, consignando hora declarada del hecho y hora de carga del servidor, y ambos participantes lo confirman entonces; en **1B**, se registra en vivo si hay conexión. Estado `pendiente_doble_confirmacion` hasta aceptación **de ambos**; retiro **solo afecta la rendición tras confirmación doble**, con timestamp del servidor de cada confirmación. Si falta Internet, registrar posteriormente y mantener pendiente hasta confirmar en línea; nunca considerar confirmado solo por una declaración unilateral.
- Prohibir retiro duplicado mediante `idempotency_key`. Si el monto supera el saldo registrado, **avisar y requerir explicación, sin bloquear automáticamente el retiro físico**, pues puede haber ventas en papel pendientes. Esta excepción es **PROPUESTA NO APROBADA**. Nunca aceptar importes negativos ni descontar dos veces.
- Correcciones de retiros confirmados: reversión trazable; sin borrado silencioso.
- Gastos en ruta se registran como categoría **separada de retiros**, sujetos a aprobación de dueño/encargado. El detalle de comprobantes y reintegros se valida con cliente.

---

### 7.7 Devoluciones y mermas

| Caso | Qué se registra | Destino del stock |
|---|---|---|
| Mercadería que vuelve sin vender, en buen estado | Se cuenta en el regreso | Depósito |
| Cliente devuelve o cambia mercadería | Registrar devolución por producto con motivo y criterios de aptitud | Depósito si aptitud verificable; si no, cuarentena |
| Cliente rechaza en la entrega | Rechazo, con motivo | Vuelve con el camión; se cuenta en el regreso |
| Mercadería dañada o no apta | Merma, con motivo | Merma |
| Cuarentena revisada | Registrar resultado de evaluación y responsable; aprobación genérica no exigida, pero sí comprobación de criterios | Depósito o merma |

Motivos predefinidos: vencido, roto/dañado, mal estado, error de pedido, cambio, otro (con texto).

### 7.8 Rendición: conciliación física y financiera

**Inventario**: usar los movimientos confirmados del libro mayor como fuente única. No sumar una devolución dos veces si ya revierte una venta. Los conteos de regreso deben estar clasificados por destino y aptitud.

```
esperado_fisico = carga + entradas_al_camion - salidas_del_camion
                  (ventas netas, mermas verificadas, transferencias, devoluciones a terceros)
diferencia_fisica = contado_total_de_todas_las_aptitudes - esperado_fisico
contado_total = contado_apto + contado_cuarentena + contado_no_apto
```

**Productos `peso` (ADR-005 D-R2, D-R3):** esperado, contado y diferencia se calculan en gramos enteros y el contado es el peso físicamente pesado al regreso. **Fase 1 no aplica tolerancia automática:** cualquier diferencia distinta de cero, incluso de 1 gramo, se registra como diferencia. No se descuenta automáticamente ningún porcentaje, cantidad de gramos permitida, merma natural ni error de balanza, y no se compensa ni normaliza. Registrar la diferencia no implica un faltante culpable: queda visible y auditable, y su responsabilidad o tratamiento se determinan con las reglas de cierre y regularización que correspondan (§7.9.3). No hay sanciones ni descuentos automáticos.

Las devoluciones de cliente efectivamente recibidas se registran como entradas al camión **una vez**; una devolución no implica stock vendible automáticamente. El resultado no debe cambiar por reclasificación entre apto/cuarentena si el total físico permanece constante. Se documenta destino y motivo de cada partida.

**Conciliación financiera por medio**:

```
efectivo_esperado_entrega = efectivo_efectivamente_cobrado
                            + otros_ingresos_efectivo_documentados
                            - retiros_con_doble_confirmacion
                            - gastos_efectivo_autorizados_y_comprobados
diferencia_efectivo = efectivo_contado_y_entregado - efectivo_esperado_entrega
```

- Transferencias: estados `declarada` y `verificada`; la verificación es **manual**, con identificador de quien verificó y fecha. Conciliar por separado; una transferencia declarada no se considera efectivo físico ni se presupone acreditada.
- A cuenta: importe pendiente, **no cobro**. Gestión de pagos posteriores, Fase 2.
- Conservar total original, componentes de pago, precios históricos, conteos y cálculo congelado al cerrar. Diferencias positivas o negativas requieren revisión, motivo y aprobación por dueño/encargado; no asignan automáticamente responsabilidad económica al vendedor.
- Finalización de jornada: retorno de stock apto a depósito, traslado de stock no apto a cuarentena/merma según regla, faltantes y sobrantes con movimientos explícitos y autorización, saldo final del camión en cero solo cuando la conciliación y regularización estén completas. **No crear stock ficticio ni esconder discrepancias para forzar el cierre**.
- El conteo físico se captura **antes** de registrar el retorno definitivo; clasificar `apto` / `cuarentena` / `no_apto`. El destino final de `no_apto` es merma/descartado por movimiento auditable; distinguirlo de cuarentena pendiente.

---

### 7.9 Correlación, conteo y conciliación

Esta sección fija las decisiones **APROBADAS CONCEPTUALMENTE** sobre operaciones, conteos y conciliación. La estructura SQL exacta queda pendiente de diseño SQL/RPC.

#### 7.9.1 Operaciones (ejecución lógica idempotente)

Fase 1 tiene una entidad conceptual **`operaciones`**. Una operación representa **UNA ejecución lógica e idempotente de un comando de negocio**; **no** representa toda la vida de un documento.

Ejemplos:
- *Registrar venta* → **operación A** → en esa ejecución se crean la venta, sus ítems, los `movimientos_stock` y los pagos.
- *Cobro posterior de cuenta corriente* → **operación B** → pago/cobro posterior, con referencia a la venta correspondiente.

Reglas:
- `operaciones.id` identifica una **ejecución lógica**.
- `operaciones.idempotency_key` protege **esa ejecución** contra reintentos.
- **Todos los efectos creados atómicamente por esa ejecución referencian `operaciones.id`.**
- Una acción posterior independiente crea **otra** operación.
- **No se duplica `idempotency_key` en los documentos hijos** salvo necesidad concreta que aparezca en el diseño SQL/RPC.

La operación aporta identidad, actor, fecha/hora e idempotencia. No lleva cantidades de producto ni importes por sí misma.

#### 7.9.2 Conteos (hecho observado)

`conteos` + `conteos_items` están **separados de `movimientos_stock`** (APROBADO). Un conteo:

- registra un **hecho observado** (cuánto hay, clasificado `apto` / `cuarentena` / `no_apto`);
- **no modifica stock**;
- deja auditables el esperado, el contado y la diferencia.

El **esperado** se deriva de `movimientos_stock`; el **contado** tiene su fuente en `conteos_items`; la **diferencia** es derivable (`contado − esperado`). Registrar un conteo es una escritura y por lo tanto **requiere protección contra duplicación** (idempotencia): "Conteo — No aplica" queda descartado.

#### 7.9.3 Regularización (acción explícita posterior)

La **regularización** es una **operación explícita posterior y autorizada**, distinta del conteo. **Solo la regularización genera `movimientos_stock`** compensatorios (`regularizacion_faltante` / `regularizacion_sobrante`, §7.4). Una diferencia de stock **no** modifica dinero automáticamente, ni a la inversa.

#### 7.9.4 Cierre de jornada (derivado, sin tabla propia)

En Fase 1 **no se crea una tabla `cierres` propia**. El cierre se modela con:

- **`jornada`** (estado y datos de cierre cuando corresponda);
- **`rendición`** (conciliación, totales, diferencias y aprobación);
- **una operación `tipo` cierre** (identidad, actor, fecha/hora, idempotencia).

El cierre **cambia el estado de la jornada** según las reglas aprobadas y **no crea implícitamente un movimiento "camión → 0"**: todo retorno de mercadería debe existir como movimiento explícito antes del cierre si corresponde. La **reapertura** está fuera del alcance actual y no se diseña ahora. Una tabla propia solo se reconsiderará si aparece un hecho de negocio que no pueda representarse con esas tres entidades.

#### 7.9.5 Mercadería y dinero: correcciones separadas

Una **diferencia de stock** no modifica dinero automáticamente; una **diferencia de dinero** no modifica stock automáticamente. Pueden estar correlacionadas por la misma jornada/rendición, pero cada corrección es explícita, autorizada y auditable en su ledger correspondiente. No se admite la operación implícita "regularización de stock → ajuste de caja".

#### 7.9.6 Idempotencia

Cada comando crítico debe ser idempotente: apertura (cuando sea una escritura reintentable), carga, venta, cobro/pago independiente, retorno, merma, conteo, regularización, retiro, rendición y cierre. Una restricción única (por ejemplo `empresa + camión + fecha`) puede **complementar** la idempotencia, pero **no la reemplaza**. Los constraints SQL exactos quedan para diseño SQL/RPC.

#### 7.9.7 Concurrencia (garantías funcionales)

Se mantiene el requisito de **atomicidad**. Garantías exigidas (sin fijar todavía implementación):

- no doble consumo de stock;
- no saldo negativo no permitido;
- no doble pago;
- no doble retorno;
- no doble regularización;
- no doble retiro;
- no doble cierre.

La estrategia concreta de bloqueo, isolation level o advisory locks se decide en el diseño SQL/RPC posterior.

---

### 7.10 Presupuestos

Requisito confirmado por el cliente el 25/10/2026. Pertenece a **Fase 1**; la entrega (1A/1B) y la etapa del plan quedan pendientes (§14, §15). Esta sección fija **reglas funcionales y un modelo conceptual**. **No** aprueba tablas, columnas, tipos, RPC ni migraciones.

#### 7.10.1 Qué es y qué no es

Un **presupuesto** es un **documento interno e informativo** que detalla productos, cantidades, precios e importes para un cliente.

- **No es una venta:** no se convierte automáticamente en venta y no la reemplaza. Si podrá convertirse más adelante está **pendiente**.
- **No es factura** ni comprobante fiscal, y **no integra ARCA** (§5).
- **No afecta stock:** no crea `movimientos_stock`, no descuenta, no reserva ni compromete mercadería y no cambia `stock_actual`.
- **No afecta dinero:** no registra pagos ni cobros, no crea deuda ni saldo a cuenta, no afecta cuentas corrientes y no interviene en la rendición.
- **No se asocia a jornadas:** no abre ni modifica jornadas, cargas ni camiones.

#### 7.10.2 Actores

- **Dueño y encargado** pueden generar y consultar presupuestos.
- **Vendedor/piloto: PENDIENTE.** No se asume que pueda generarlos ni consultarlos.

#### 7.10.3 Contenido (confirmado)

**Encabezado:** la palabra `PRESUPUESTO`, el **número de presupuesto**, la **fecha** y la **hora** (instante del servidor; la presentación en zona horaria operativa depende del pendiente «Fechas» de §15), el **nombre del cliente**, la **cuenta del cliente** si tiene y el **DNI del cliente**.

**Detalle (tabla):**

| Columna | Contenido |
|---|---|
| Cantidad | productos `peso`: kg con 3 decimales fijos (`28,680 kg`; se ingresa con hasta 3 decimales, §7.1); productos `unidad`: unidades enteras. Un presupuesto admite **ambas formas de venta** (decisión humana del 25/10/2026). |
| Código | código del producto |
| Descripción | descripción del producto |
| Precio | precio por kg (`peso`) o unitario (`unidad`) |
| % IVA | siempre `21%` (**etiqueta informativa**, ver §7.10.4) |
| Importe | `cantidad × precio` (§7.1) |

**Pie:** `TOTAL PRESUPUESTO: $ …` = **suma de los importes** de las líneas.

#### 7.10.4 IVA: sólo informativo

`21%` es **una etiqueta visual fija** en cada línea. **No** se calcula, suma, resta, discrimina ni desglosa IVA. No existen subtotal fiscal, neto gravado, IVA total, `importe × 1,21` ni `importe / 1,21`. Si hace falta persistir el dato, el nombre interno debe dejar claro que es informativo (por ejemplo, `iva_porcentaje_informativo`; nombre no decidido).

#### 7.10.5 Sin descuentos

Los presupuestos **no tienen descuentos**: ni por línea, ni global, ni porcentaje, ni monto. No existe columna de descuento ni mecanismo previsto «por si más adelante». La propuesta no aprobada sobre descuentos en **ventas** (§7.5) es una discusión separada y no cambia.

#### 7.10.6 Importe y total

- Importe de línea `unidad` = `cantidad × precio_unitario`.
- Importe de línea `peso`: el importe exacto `gramos × precio_por_kg / 1000`, redondeado **una sola vez al peso entero** con empate 0,50 hacia arriba (ADR-005 D-R1, §7.1). Resultado final en pesos enteros.
- Total = **suma de los importes finales determinados para cada línea según la regla aplicable a su tipo de producto** (requisito del cliente: total = suma de importes). Para líneas `peso` la regla es D-R1: se suman sus importes ya redondeados, sin recalcularlos desde cantidades y precios exactos. Para líneas `unidad` la regla monetaria final sigue pendiente y, por lo tanto, también el comportamiento final de centavos de un presupuesto mixto.
- Línea `unidad`: la fórmula vigente es `cantidad × precio_unitario`; está pendiente (§15) si su importe final se conserva con centavos o se redondea al peso entero y, por lo tanto, si el total de un presupuesto mixto (`peso` + `unidad`) puede terminar con centavos (ejemplo del problema: `3 × $1.234,56 = $3.703,68`).

Montos en `numeric(14,2)`, nunca `float`; un importe en pesos enteros se representa con centavos `.00`.

#### 7.10.7 Snapshot histórico

Un presupuesto guardado **no cambia** si después cambian el nombre, el código, la descripción o el precio del producto, ni los datos visibles del cliente.

- **Cliente:** el presupuesto guarda una **referencia** al cliente registrado (si se puede emitir a un cliente no registrado está **pendiente**) y un **snapshot** del nombre, de la cuenta (si existe) y del DNI tal como se imprimieron.
- **Producto:** cada línea guarda una **referencia** al producto y un **snapshot** del código, la descripción, la forma de venta, la cantidad canónica, el precio aplicado, el porcentaje de IVA informativo y el importe.
- **Reconstrucción:** se usan los valores guardados, sin recalcular.
- **Precio aplicado:** el presupuesto registra el precio aplicado a cada línea. El **origen** de ese precio (por ejemplo, si se toma automáticamente del catálogo), si es **editable** y **quién** puede modificarlo quedan **pendientes de definición** (§15). Sin descuentos en ningún caso.

#### 7.10.8 Datos del cliente: estado actual

`public.clientes` (`20261024180000_catalogo_clientes.sql`) tiene hoy nombre, comercio, dirección y teléfono, pero **no tiene DNI ni cuenta**: ese slice excluyó expresamente CUIT/DNI. Agregar esos campos a la ficha, su obligatoriedad, su formato, su unicidad y el significado exacto de «cuenta» son **decisiones pendientes** (§15). No se inventa ninguna migración. La ficha del cliente (dato maestro mutable) y el snapshot del presupuesto (dato histórico) son cosas distintas.

#### 7.10.9 Formato visual (referencia conceptual, sin UI aprobada)

```text
PRESUPUESTO
N.º <número>

Fecha: <dd/mm/aaaa>      Hora: <hh:mm>
Cliente: <nombre>
Cuenta: <cuenta, si tiene>
DNI: <dni>

Cantidad   | Código | Descripción | Precio   | % IVA | Importe
28,680 kg  | ...    | ...         | $ .../kg | 21%   | $ ...
3 u        | ...    | ...         | $ ...    | 21%   | $ ...

TOTAL PRESUPUESTO: $ ...
```

Sin descuento, sin IVA calculado y sin subtotal fiscal. En PC se muestra como tabla. En Android puede adaptarse a filas o tarjetas. Una impresión/PDF futura (no comprometida) mantendría el formato tabular. El número `N.º` es un marcador: su formato no está decidido (§15).

#### 7.10.10 Consideración técnica (PROPUESTA TÉCNICA NO APROBADA)

Como el número, la fecha/hora del servidor y los snapshots los debe fijar el servidor, la generación probablemente requiera una RPC idempotente con `empresa_id` derivado del perfil y RLS por empresa (Topología D). Implica security review. Aunque el presupuesto no mueve stock ni dinero, se diseñará en una tarea posterior.

---

## 8. Modelo de datos (propuesto)

> Nombres en español, snake_case. Todas las tablas llevan `id`, `empresa_id`, `created_at`, `created_by`. Las filas marcadas **[APROBADA]** son decisión conceptual ya aprobada (§7 y §9); las marcadas **[PROPUESTA]** aún requieren diseño/aprobación; **[F2]** es Fase 2.

| Tabla | Categoría | Campos principales |
|---|---|---|
| `empresas` | [APROBADA CONCEPTUALMENTE] | nombre; entidad dueña; `empresa_id` en todas las tablas de negocio |
| `perfiles` | [APROBADA CONCEPTUALMENTE] | usuario (auth), nombre, activo; empresa y rol leídos de tablas protegidas |
| `roles` | [PROPUESTA TÉCNICA] | sin tabla de membresías: un perfil 1:1 con `auth.users`, una empresa y un rol por usuario (decisión humana P5–P7, ADR-001 §18). Roles funcionales (dueño, encargado, vendedor/piloto) **aprobados**; **tabla `roles` NO aprobada** |
| `productos` | [APROBADA CONCEPTUALMENTE] | codigo, nombre, categoria, forma_venta (`unidad`/`peso`; ADR-005), precio (unitario en `unidad`, **por kg** en `peso`; `numeric(14,2)`), stock_minimo (entero en unidad mínima: unidades o gramos), activo. Sin precio de media pieza. *SQL: `unidad`/`peso` con `stock_minimo integer` en unidades o gramos desde `20261027001542_modelo_peso_gramos.sql` (Slice A, local; staging pendiente)* |
| `camiones` | [APROBADA CONCEPTUALMENTE] | patente, nombre, activo |
| `clientes` | [APROBADA CONCEPTUALMENTE] | nombre, comercio, direccion, telefono, activo, creado_por, validado_por, estado_validacion; contraparte comercial, **no** ubicación de stock. **DNI y cuenta:** requeridos para mostrar en presupuestos (§7.10), pero **no existen** en el modelo actual; agregarlos y definir su obligatoriedad, formato y unicidad son **decisiones pendientes** (§15) |
| `ubicaciones` | [APROBADA CONCEPTUALMENTE] | internas: `deposito`, `cuarentena`, `camion` (camion_id). **`merma` no es ubicación interna** (salida terminal) |
| `operaciones` | [APROBADA CONCEPTUALMENTE] | empresa_id, tipo, actor, jornada_id (opcional), idempotency_key, creado_en; ejecución lógica idempotente (§7.9) |
| `movimientos_stock` | [APROBADA CONCEPTUALMENTE] | operacion_id, tipo_movimiento, producto_id, cantidad (entero, unidad mínima), ubicacion_origen_id (nullable), ubicacion_destino_id (nullable), jornada_id, actor, motivo, creado_en. **Sin `saldo_actual`.** Append-only |
| `saldos_stock` | [DERIVADA] | **No es fuente de verdad en Fase 1.** El saldo se deriva de `movimientos_stock`. Caché/materialización = optimización futura |
| `jornadas` | [APROBADA CONCEPTUALMENTE] | fecha, camion_id, vendedor_id, estado, ventas_finalizadas_at, abierta_por, contada_por, cerrada_por, cerrada_at, observaciones |
| `conteos` | [APROBADA CONCEPTUALMENTE] | jornada_id, contado_por, contado_en, tipo; hecho observado, **no** modifica stock. Idempotente |
| `conteos_items` | [APROBADA CONCEPTUALMENTE] | conteo_id, producto_id, cantidad_apta, cantidad_cuarentena, cantidad_no_apta |
| `rendiciones` | [APROBADA CONCEPTUALMENTE] | jornada_id, totales históricos, diferencia_mercaderia_valorizada, diferencia_efectivo, diferencia_transferencias_declaradas_vs_verificadas, aprobado_por, aprobado_at, motivo_aprobacion, observaciones |
| `rendicion_items` | [PROPUESTA TÉCNICA] | rendicion_id, producto_id, cálculo congelado (cargado, vendido, devuelto, merma, esperado, contado, diferencia). **No es segunda fuente editable de contado**; el contado vive en `conteos_items` |
| `retornos` | [PROPUESTA TÉCNICA] | jornada_id, retorno de mercadería; detalle por producto y aptitud |
| `mermas` | [PROPUESTA TÉCNICA] | modelable como movimiento `tipo_movimiento = merma` bajo operación `tipo = merma`; tabla propia solo si el diseño lo justifica |
| `retiros_efectivo` | [APROBADA CONCEPTUALMENTE] | jornada_id, importe, entregado_por, recibido_por, motivo, ocurrido_at_declarado, confirmado_entrega_at, confirmado_recepcion_at, estado |
| `gastos_ruta` | [PROPUESTA TÉCNICA] | jornada_id, importe, motivo, comprobante, autorizado_por, estado, fecha |
| `talonarios` | [PROPUESTA TÉCNICA] | serie, numero_desde, numero_hasta, asignado_a, estado, fecha_asignacion |
| `notas_talonario` | [PROPUESTA TÉCNICA] | talonario_id, numero, jornada_id, estado (`utilizada`/`anulada`/`justificada`), venta_id nullable, motivo, registrado_por |
| `ventas` | [APROBADA CONCEPTUALMENTE] | operacion_id, jornada_id, cliente_id, origen (digital/papel), serie_talonario, numero_nota, total, estado |
| `venta_items` | [APROBADA CONCEPTUALMENTE] | venta_id, producto_id, cantidad (entero en unidad mínima: unidades o gramos), precio aplicado (unitario o por kg), importe. **Historial de precios aplicados** para reconstruir el cobro sin recalcular (ADR-005 §2.3): **PROPUESTA TÉCNICA pendiente** (forma SQL exacta no aprobada). El importe de un ítem `peso` es el redondeado por línea al peso entero (ADR-005 D-R1) y se guarda en `numeric(14,2)` con centavos `.00`. El prototipo todavía usa el snapshot pieza/media de ADR-002/ADR-003 |
| `presupuestos` | [PROPUESTA TÉCNICA] (requisito confirmado, §7.10) | empresa_id, número (formato y secuencia pendientes), creado_en (servidor), actor, cliente_id (referencia), snapshot de nombre, cuenta y DNI del cliente, total, estado (sólo si se aprueba un ciclo de vida, pendiente). **No** referencia jornada, operación de stock ni pagos |
| `presupuesto_items` | [PROPUESTA TÉCNICA] (requisito confirmado, §7.10) | presupuesto_id, producto_id (referencia), snapshot de código, descripción y forma de venta, cantidad (entero en unidad mínima), precio aplicado, IVA informativo (21%), importe. **Sin** columnas de descuento ni de IVA calculado |
| `venta_pagos` | [APROBADA CONCEPTUALMENTE] | operacion_id, venta_id, medio (efectivo/transferencia/a_cuenta; otros pendientes), importe, referencia, estado (`declarada`/`verificada` para transferencias), verificado_por, verificado_at |
| `partidas_ingreso` | [F2 / PROPUESTA NO APROBADA] | producto_id, fecha_ingreso, fecha_vencimiento (nullable), cantidad_inicial. **No se mantienen saldos por partida ni se atribuye cada venta a un ingreso.** No implementar sin aprobación |
| `auditoria` | [DERIVADA] | **No hay tabla genérica en Fase 1.** La trazabilidad surge de operaciones, ledgers, documentos, actor, timestamps, motivos, jornada y relaciones |
| ledger financiero | [DERIVADA] | **No hay ledger financiero separado en Fase 1.** Fuente documental: ventas, pagos/cobros, retiros, rendición. Saldo de caja: derivado |
| `cierres` | [DERIVADA] | **Sin tabla propia en Fase 1.** Cierre = jornada + rendición + operación `tipo` cierre (§7.9.4) |

Restricciones clave:
- `ventas`: único parcial (`empresa_id`, `serie_talonario`, `numero_nota`) cuando origen = papel; idempotencia en la operación para digital.
- `retiros_efectivo`: efecto contable solo después de ambas confirmaciones; importes positivos; idempotencia.
- `venta_pagos`: suma por venta = total confirmado; toda escritura en una transacción; importes `numeric(14,2)`, nunca float.
- `jornadas`: único (`empresa_id`, `camion_id`, `fecha`), incluso cerrada.
- `movimientos_stock`: append-only; sin UPDATE/DELETE; enteros positivos con dirección dada por origen/destino; rectificación por movimientos compensatorios.
- `presupuestos`: sin efecto sobre `movimientos_stock`, `stock_actual`, `venta_pagos`, jornadas ni rendiciones. Secuencia, formato, unicidad y reinicio del número: pendientes (§15).
- Cantidades registradas en documentos y movimientos: enteros positivos en unidad mínima (unidades o gramos). **Excepción no aprobada:** si se permitiera stock negativo transitorio, sería **solo** para ubicación camión en jornada abierta; depósito y cuarentena no podrán ser negativos. No activar sin decisión aprobada, implementación transaccional y pruebas de concurrencia.

---

## 9. Roles y permisos confirmados

**Roles funcionales APROBADOS:** dueño, encargado, vendedor/piloto. **La tabla `roles` como entidad NO está aprobada** (PROPUESTA TÉCNICA); no existe tabla de membresías: cada usuario tiene un único perfil 1:1 con `auth.users`, con una empresa y un rol (decisión humana P5–P7, ADR-001 §18). Regla aprobada: **empresa y rol se obtienen desde tablas protegidas**, nunca desde `user_metadata`.

| Rol | Puede | No puede |
|---|---|---|
| **Dueño** | Visión general; administrar usuarios, clientes, productos, stock, jornadas y rendiciones; autorizar gastos y retiros; confirmar recepción de retiros; generar y consultar presupuestos (§7.10). | Borrar movimientos confirmados sin reversión auditada. |
| **Encargado** | Operación general; editar y validar clientes; administrar cargas, conteos, cierre con diferencias, gastos y retiros de efectivo; generar y consultar presupuestos (§7.10). | Administrar roles globales ni borrar historial sin compensación. |
| **Vendedor / Piloto** | Ver su jornada y clientes necesarios; **crear cliente nuevo**; registrar ventas y pagos mixtos; transcribir papel; finalizar ventas (`ventas_finalizadas`); confirmar entrega de retiro de dinero. | Editar ficha de cliente existente, cambiar precios maestros, aprobar su propio conteo/rendición, registrar retiros como receptor autorizado. |

Si el vendedor/piloto puede generar o consultar presupuestos está **pendiente** (§15); hasta que se decida, no se le asigna ese permiso. No se crean roles independientes de depósito o administración en Fase 1; esas tareas corresponden al encargado/dueño. La separación vendedor/conteo aplica incluso si una persona posee permisos adicionales: se valida participación real en la jornada.

---

## 10. Seguridad y auditoría

- Supabase Auth con cuentas individuales; empresa y rol se leen del perfil (tabla protegida), no de `user_metadata` modificable por usuario.
- RLS en todas las tablas expuestas por la API, restringiendo consultas/escrituras simples por empresa, rol y estado. Nunca confiar en controles visuales como única defensa.
- `authenticated` y `anon` **no reciben INSERT, UPDATE ni DELETE directos** sobre libros de movimientos de stock/caja o registros confirmados; registros inmutables y rectificación por asientos compensatorios.
- **Auditoría (Fase 1):** **no se crea una tabla genérica `auditoria`**. La trazabilidad surge de `operaciones`, los ledgers (`movimientos_stock`), los documentos, el actor, los timestamps, los motivos, la jornada y las relaciones. Si más adelante se requiere auditoría técnica transversal (cambios de datos maestros, intentos bloqueados), se diseña explícitamente con su propia aprobación.
- **ADR-001 — APROBADA PARA VALIDACIÓN CONTROLADA (Topología D):** cada operación privilegiada se expone a la Data API mediante una fachada `SECURITY INVOKER`, que delega en una implementación `SECURITY DEFINER` ubicada en un esquema privado/no expuesto. La implementación privada constituye la frontera real de seguridad y debe hacer las validaciones completas antes de escribir: `auth.uid()`, perfil activo, `empresa_id` obtenida/verificada del servidor, rol, estado, cantidades y permisos sobre cada objeto. La cadena conceptual es: Data API → fachada expuesta `SECURITY INVOKER` → implementación privada `SECURITY DEFINER` → validaciones completas → transacción de negocio.
- **Importante:** la implementación `SECURITY DEFINER` ejecuta con privilegios del propietario y puede evitar RLS. Debe fijar `SET search_path = ''`, usar referencias totalmente calificadas y un propietario de privilegio mínimo, revisar grants y privilegios por defecto y probar desde `anon`, `authenticated` ajeno y roles válidos. La función privada no se expone por la Data API y no deben existir rutas alternativas con privilegios equivalentes. `anon` y `authenticated` no reciben DML directo sobre los ledgers.
- `SECURITY INVOKER` también se usa para lecturas y ediciones ordinarias con grants y RLS apropiados; Edge Functions quedan reservadas para lógica externa no conveniente en SQL. **Antes de la aprobación para validación controlada no se generan migraciones dependientes de ADR-001. Con el estado actual se permiten únicamente las migraciones necesarias para validar ADR-001 en local/staging; producción permanece prohibida hasta completar las pruebas requeridas, la auditoría independiente y la aceptación humana final.** P2–P7 están resueltas por decisión humana (ADR-001 §18) y P11 está resuelta para validación controlada (ADR-001 §18.2: `service_role` denegado por defecto sobre objetos de negocio; toda excepción, nominada y aprobada); P8–P10 y P12–P17 siguen pendientes y deben resolverse en el alcance que requiera la validación antes de implementar sus partes; P18 es una decisión futura separada.
- Idempotencia por clave única y transacciones atómicas para compras futuras, cargas, ventas, retiros y cierres; protección contra concurrencia/bloqueos adecuados.
- Timestamp del servidor UTC y zona horaria operativa explícita; distinguir hora declarada del hecho y hora efectiva de registro.
- Secretos fuera del frontend; entornos local/staging/producción separados, migraciones revisadas, restauración de backups probada, auditoría y monitoreo.

---

## 11. Reportes (Fase 1)

1. **Rendición de jornada** — detalle por producto (cargado, vendido, devuelto, esperado, contado, diferencia) y dinero. Imprimible.
2. **Diferencias por período** — por camión y por vendedor: cantidad de jornadas, faltantes en unidades y en pesos, diferencias de dinero.
3. **Ranking de faltantes por producto** — qué productos faltan más seguido.
4. **Stock actual** — por ubicación, con alerta bajo mínimo.
5. **Movimientos** — historial filtrable por producto, tipo, fecha, jornada, usuario.
6. **Ventas a cuenta** — por cliente y período.
7. **Notas faltantes** — saltos de numeración por jornada/vendedor.
8. **Retiros de efectivo** — importe, entregante, receptor, hora, estado de confirmación y saldo por entregar.
9. **Pagos combinados** — efectivo, transferencia y ventas a cuenta por jornada.

Exportación CSV y filtros de fecha donde corresponda.

**Cantidades en reportes (ADR-005):** las cantidades de productos `peso` (cargado, vendido, devuelto, esperado, contado, diferencia, stock y mínimo) se calculan en gramos enteros y se muestran **en kg con 3 decimales fijos**. Las de productos `unidad`, en unidades. «Faltantes en unidades» del reporte 2 significa «en la unidad comercial de cada producto» (unidades o kg). Una diferencia por peso de cualquier magnitud, incluso de 1 gramo, se informa como diferencia (sin tolerancia, ADR-005 D-R3). La base de valorización de los faltantes (precio de venta histórico, costo u otro) sigue pendiente (§15); cuando esa valorización dependa del importe por peso, su conversión a pesos sigue D-R1. Un listado o una consulta de presupuestos no es uno de estos reportes y no forma parte de la rendición.

---

## 12. Pruebas obligatorias

No se considera terminado un módulo sin estas pruebas (tests SQL sobre las RPC y/o tests de integración):

**Stock**
- [ ] Cargar un camión descuenta del depósito y suma al camión exactamente lo cargado.
- [ ] No se puede cargar más de lo disponible en depósito.
- [ ] No se puede cargar mercadería en cuarentena.
- [ ] Peso (ADR-005): `1,250 kg` se guarda como `1250` g; `28,680 kg` como `28680` g.
- [ ] Peso: cargar, vender y retornar un peso exacto en gramos conserva el valor exacto en cada ubicación; el stock derivado de un producto `peso` es la suma exacta de sus movimientos en gramos.
- [ ] Peso: una cantidad con más de 3 decimales de kg se rechaza (no se redondea ni se trunca); cantidad 0 o negativa se rechaza.
- [ ] Peso: la conversión kg → gramos no usa punto flotante (casos de borde como `1,005 kg` → `1005` g).
- [ ] Ningún cálculo de cantidades ni de dinero usa `float`/`double precision`/`real`.
- [ ] Un producto `unidad` sigue aceptando sólo enteros; `Lácteos` + `peso` y `Fiambres` + `unidad` se rechazan.
- [ ] Un precio con más de 2 decimales se rechaza; un documento histórico usa el precio aplicado y el importe guardados, sin recalcularlos.
- [ ] Importe por peso (ADR-005 D-R1): `1,250 kg × $1.234,56/kg` = `$1.543,20` exacto → importe `$1.543`.
- [ ] Importe por peso, empate: `1,250 kg × $1.235,60/kg` = `$1.544,50` exacto → importe `$1.545` (0,50 hacia arriba); `$1.544,49` → `$1.544`; `$1.544,99` → `$1.545`.
- [ ] Importe por peso: el redondeo se aplica una sola vez por línea; en un documento con líneas `peso`, el aporte de esas líneas al total es la suma de sus importes ya redondeados y no se recalcula desde cantidades y precios exactos (por ejemplo, dos líneas de `1,250 kg × $1.234,72/kg` = `$1.543,40` exactos cada una: total `$1.543 + $1.543 = $3.086`, no `$3.087`, que resultaría de redondear el total exacto `$3.086,80`).
- [ ] Importe por peso: el cálculo intermedio es exacto y no usa `float`; el redondeo es explícito y no depende del redondeo implícito de `numeric(14,2)`.
- [ ] Peso real (ADR-005 D-R2): el movimiento de cada operación (ingreso, carga, venta, devolución y conteo) usa el peso medido en esa operación, no un peso teórico anterior; en la carga, el débito del depósito y el crédito del camión son el mismo valor en gramos.
- [ ] Sin tolerancia (ADR-005 D-R3): una diferencia de 1 gramo entre contado y esperado se registra como diferencia.
- [ ] Datos anteriores (ADR-005 D-R4): ninguna cantidad en medias piezas (SQL local/staging o claves `localStorage` anteriores) se lee ni se interpreta como gramos; el modelo nuevo arranca con inicialización limpia.
- [ ] El saldo de cada ubicación coincide con la suma de sus movimientos.

**Jornada**
- [ ] No se pueden abrir dos jornadas para el mismo camión **en la misma fecha**, incluso si la primera ya cerró.
- [ ] El vendedor de la jornada no puede registrar el conteo de regreso.
- [ ] Las ventas de papel pendientes bloquean el conteo formal; la carga final se confirma en servidor.
- [ ] No se puede cerrar sin conteo de regreso.
- [ ] Una jornada cerrada rechaza cualquier modificación.

**Rendición**
- [ ] **1A:** nota de papel de $100.000 con $40.000 efectivo, $35.000 transferencia declarada y $25.000 a cuenta: efectivo esperado $40.000 antes de retiros.
- [ ] **1A:** retiro ocurrido en ruta y registrado al regresar: ninguna deducción hasta las dos confirmaciones, luego se deduce exactamente una vez.
- [ ] **1B:** retiro en vivo y retiro diferido tienen iguales controles e idempotencia.
- [ ] Caso sin diferencias: diferencia 0 en todo.
- [ ] Caso con faltante: se informa, se valoriza y se registra el movimiento de faltante.
- [ ] Caso con sobrante: se informa y se exige movimiento `sobrante_rendicion` autorizado; nunca se crea mercadería sin causa.
- [ ] Ventas `a_cuenta` no suman al efectivo esperado.
- [ ] Pago mixto: la suma de sus componentes coincide con total; transferencia y a cuenta no cuentan como efectivo.
- [ ] Retiro pendiente de confirmación de uno de los dos actores no descuenta caja; confirmado por ambos sí.
- [ ] Dos solicitudes del mismo retiro generan una sola operación.
- [ ] Gastos no autorizados no reducen la caja esperada.
- [ ] Devolución cargada como entrada una vez no se duplica al calcular stock.
- [ ] Notas anuladas no suman ni descuentan stock.
- [ ] Devoluciones a cuarentena no vuelven al stock vendible.
- [ ] Al cerrar, el stock del camión queda en 0.

**Ventas: una línea por producto (ADR-006)**
- [ ] Una venta nueva con una sola línea válida por producto se acepta (`1,000 kg × $499,99/kg` en una línea → total `$500`).
- [ ] Una venta nueva con dos o más líneas `peso` del mismo `productoId` se rechaza sin persistir, aunque el stock alcance.
- [ ] Una venta nueva con dos o más líneas `unidad` del mismo `productoId` se rechaza sin persistir, aunque el stock alcance.
- [ ] Una venta nueva con dos líneas del mismo `productoId` y unidades distintas se rechaza sin persistir.
- [ ] Una venta nueva con líneas de productos distintos, todo lo demás válido, se acepta.
- [ ] Una venta histórica con líneas repetidas, estructura e importes válidos, se lee sin recalcular y su consumo cuenta para el stock.

**Ventas en papel**
- [ ] Número de nota duplicado en **cualquier jornada de la misma empresa/serie** es rechazado.
- [ ] Salto en la numeración genera aviso.

**Presupuestos (§7.10)**
- [ ] Generar un presupuesto no crea `movimientos_stock` ni cambia `stock_actual`.
- [ ] Generar un presupuesto no crea pagos, deuda ni saldo a cuenta, y no afecta jornadas ni rendiciones.
- [ ] El importe de una línea `peso` es `gramos × precio_por_kg / 1000` redondeado una vez al peso entero (0,50 hacia arriba, ADR-005 D-R1). El total es la suma de los importes finales de cada línea según la regla de su tipo; la prueba del importe de líneas `unidad` y de los centavos de un presupuesto mixto se escribe cuando se resuelva ese pendiente (§15). No se suma, resta ni desglosa IVA.
- [ ] Cada línea muestra `21%` como IVA informativo; no existe ningún campo ni cálculo de descuento.
- [ ] Una línea `peso` muestra la cantidad en kg con 3 decimales fijos y una línea `unidad`, en unidades enteras.
- [ ] Cambiar después el nombre, el código, la descripción o el precio del producto, o los datos del cliente, no altera un presupuesto ya guardado (snapshot).
- [ ] Dueño y encargado pueden generarlo; usuario de otra `empresa_id`, `anon` y usuario sin perfil activo no pueden generarlo ni verlo. El caso del vendedor/piloto se prueba según la decisión pendiente.

**Seguridad**
- [ ] La fachada expuesta `SECURITY INVOKER` y la implementación privada `SECURITY DEFINER` rechazan `anon`, usuario sin perfil activo, usuario/perfil con `empresa_id` distinto y vendedor intentando cerrar jornada o realizar retiros.
- [ ] Revocación efectiva de escrituras directas en ledger; ninguna ruta alternativa puede escribir sin pasar validaciones y auditoría.
- [ ] Un usuario sin rol no ve datos.
- [ ] Ningún rol puede hacer UPDATE/DELETE en movimientos.
- [ ] Un usuario/perfil con `empresa_id` distinto no ve datos ni puede ejecutar operaciones (test de aislamiento por `empresa_id` con empresa ficticia).
- [ ] `authenticated` no puede insertar directamente movimientos ni asientos financieros por Data API.
- [ ] Una función privada privilegiada no es invocable directamente desde la Data API y el endpoint autorizado rechaza usuarios no habilitados.
- [ ] Dos solicitudes concurrentes/reintentadas no duplican movimiento, venta o retiro.
- [ ] La transferencia declarada no figura como verificada hasta intervención del usuario habilitado.
- [ ] La venta con stock informático insuficiente no crea saldo negativo silencioso: queda pendiente una regularización controlada.
- [ ] Vendedor puede crear cliente pero no editar clientes existentes, incluso usando directamente la API.
- [ ] Solo dueño/encargado pueden iniciar un retiro; solo ambos participantes lo confirman.

---

## 13. Organización del repositorio y documentación

```
/
├── BLUEPRINT.md            ← este documento: visión, alcance, reglas vigentes
├── AGENTS.md               ← instrucciones comunes a todos los agentes
├── CLAUDE.md               ← instrucciones específicas para Claude Code
├── opencode.json           ← configuración de OpenCode (permisos, plugins)
├── .agents/skills/         ← skills fijadas en el repositorio y compartidas por los agentes
├── .opencode/agents/       ← subagentes de OpenCode (auditor de solo lectura)
├── .claude/                ← configuración compartida de Claude Code
├── docs/
│   ├── decisions/          ← una decisión por archivo (ADR)
│   ├── incidents/          ← un error por archivo
│   ├── progress-log.md     ← bitácora por tarea
│   ├── changelog.md        ← historial de versiones entregadas
│   ├── research/           ← investigación de referencia (insumo, no decisión)
│   ├── architecture/       ← análisis de arquitectura y base de datos
│   └── quality/            ← procesos de revisión, seguridad, testing
├── supabase/
│   ├── migrations/
│   └── tests/
└── apps/web/               ← frontend React + TypeScript + Vite (deploy en Vercel)
```

### Reglas para agentes
1. Leer `BLUEPRINT.md` y `AGENTS.md` antes de empezar cualquier tarea.
2. No implementar nada de la sección 5 sin una decisión registrada y aprobada en `docs/decisions/`. **No implementar ninguna regla marcada `PROPUESTA NO APROBADA`, `PROPUESTA TÉCNICA NO APROBADA` ni ADR en estado `propuesta`. Si una tarea depende de alguna, detenerse, informar el bloqueo y pedir aprobación expresa.**
3. No mover stock ni dinero desde el frontend: siempre por RPC.
4. Toda migración nueva va en `supabase/migrations/`, nunca cambios manuales en la base.
5. Al terminar una tarea: actualizar `docs/progress-log.md` con qué se hizo, qué archivos cambiaron y cómo se probó.
6. Si una regla de este documento parece incorrecta, no cambiarla en el código: proponer una decisión.

### Plantilla de decisión (`docs/decisions/NNN-titulo.md`)
```
# NNN — Título
Fecha:
Estado: propuesta | aprobada para validación controlada | aprobada | reemplazada por NNN
Contexto: qué problema hay
Decisión: qué se decidió
Alternativas descartadas: y por qué
Consecuencias: qué cambia en el código / en el Blueprint
```

### Plantilla de incidente (`docs/incidents/AAAA-MM-DD-titulo.md`)
```
# Título del incidente
Fecha detectado:
Detectado por:
Qué falló:
Cómo se reproduce (pasos):
Causa raíz:
Archivos modificados:
Solución aplicada:
Pruebas que lo verifican (test o verificación manual documentada):
Cómo evitar que vuelva a pasar:
Estado: abierto | resuelto (solo con prueba)
```

---

## 14. Plan de trabajo — Fase 1

| Etapa | Contenido | Entregable verificable |
|---|---|---|
| 0. Inventario | Revisar el repositorio actual contra este Blueprint. Marcar qué existe, qué sirve y qué hay que rehacer. | `docs/progress-log.md` con el inventario |
| 1. Base | Esquema, RLS, roles, usuarios, productos, camiones, clientes, ubicaciones. | Alta de datos maestros funcionando + tests de seguridad |
| 2. Stock | Movimientos, saldos, ingresos, cuarentena, stock actual. | Tests de stock en verde |
| 3. Jornada y ventas 1A | Apertura, carga, talonarios, notas de papel, clientes y **venta_pagos desglosada (efectivo, transferencia, a cuenta)**. | Jornada lista para finalizar ventas; tests de numeración |
| 4. Conteo y rendición 1A | Finalización de ventas, conteo por tercero, clasificación física, **retiros físicos de ruta cargados diferidamente y confirmados por ambos**, gastos autorizados y conciliación por medio de pago. | Jornada 1A completa y tests de integridad |
| 5. Operación digital 1B | **Pantalla de autoventa online Android**, creación de clientes desde celular, **registro de retiros en vivo con doble confirmación** e interfaz de gastos (pagos mixtos ya en 1A). | Tests de ventas digitales, retiro e idempotencia |
| 6. Reportes | Reportes de la sección 11 + CSV. | Revisión con el dueño |
| 7. Prueba real | Una semana usando el sistema en paralelo con el papel. | Lista de ajustes acordada |
| Presupuestos | Módulo de §7.10 (Fase 1). **Etapa y entrega pendientes de acuerdo comercial.** Depende de productos con forma de venta `peso` (ADR-005), de los campos DNI/cuenta de clientes (pendientes) y del redondeo D-R1 (resuelto el 26/10/2026). No depende de jornadas, carga, ventas ni rendición, y no se agrega a ninguna de esas etapas. | Tests de §12 «Presupuestos» en verde |

**Cambio de modelo a peso (ADR-005).** Los slices ya implementados en local de las Etapas 1 y 2 (productos y stock) usan `pieza` y medias piezas. Una **tarea posterior específica y autorizada** (migración nueva, RPC, pruebas pgTAP/Vitest y prototipo) debe adaptarlos a `peso` y gramos. Como carga, ventas, retornos y conteos (Etapas 3–4) dependen de la unidad mínima, conviene ejecutarla antes de diseñarlos; el orden exacto lo autoriza el humano. Con D-R1–D-R4 resueltas (26/10/2026), esa migración al modelo por peso es el **siguiente bloque técnico**; no está autorizada por este documento.

---

## 15. Pendientes de definición (NO asumir confirmados)

> Nota (20/10/2026): las decisiones de arquitectura de §7.9 y §8 (operaciones, conteos, ubicaciones internas vs salida terminal, cierre derivado, idempotencia, concurrencia funcional y separación mercadería/dinero) están **aprobadas conceptualmente**. Los puntos listados a continuación **siguen pendientes**; la estructura SQL exacta y los constraints se definen en el diseño SQL/RPC.

### Prioridad alta — antes de diseñar tablas/RPC
- [ ] **Confirmación de alcance contractual:** entregas 1A + 1B están propuestas dentro de Fase 1; cliente debe aprobar alcance, precio y fechas revisadas, sin asumir que 30 días bastan.
- [ ] **Venta con stock insuficiente — propuesta:** negativo transitorio solo para camión en jornada abierta, venta marcada `excede_stock` y cierre bloqueado hasta regularización aprobada. Confirmar o corregir.
- [ ] **Anulaciones — propuesta:** vendedor anula sus ventas antes de finalizar, con motivo; luego solo dueño/encargado. Confirmar o corregir.
- [ ] **Descuentos — propuesta:** prohibidos para vendedor en Fase 1. Confirmar o corregir.
- [ ] **ADR-001 — APROBADA PARA VALIDACIÓN CONTROLADA:** P1 resolvió la Topología D (fachada expuesta `SECURITY INVOKER` + implementación `SECURITY DEFINER` en esquema privado/no expuesto) y P19/P20 resolvieron la gobernanza en dos etapas y las migraciones de validación sólo local/staging. P2–P7 están resueltas por decisión humana (ADR-001 §18) y P11 para validación controlada (ADR-001 §18.2); P8–P10 y P12–P17 siguen pendientes antes de una validación completa; P18 es una decisión futura separada. Producción exige pruebas, auditoría independiente y aceptación humana final.
- [ ] **Ventas con pagos combinados:** confirmar medios exactos (efectivo, transferencia, débito/QR y/o importe a cuenta); si una misma venta admite saldo impago y cómo se anota en papel.
- [ ] **Alta de clientes por vendedor:** campos mínimos, manejo de duplicados y cuándo el encargado valida ficha y límites de crédito. Confirmado solo que puede **crear**, nunca editar existente.
- [ ] **Talonarios:** por vendedor o camión, serie, numeración, modo de asignación y control de duplicados de venta digital transcripta en papel.
- [ ] **Confirmación doble de retiro con falta de Internet:** cómo documentan entrega física en ese momento y quién regulariza la confirmación digital; no deducir retiro antes de confirmación de ambos.
- [ ] **Gastos de ruta:** tipos, quién solicita, quién autoriza, comprobante, momento y cómo afectan rendición.
- [ ] **Devoluciones por producto:** criterios documentables para clasificación apto/no apto; no asumir que todo retorno está apto por no requerir autorización humana.
- [ ] **Vencimientos — propuesta:** fecha por ingreso con `cantidad_inicial` y alertas orientativas; sin FEFO. Requiere aprobación comercial.
- [x] ~~**Precio media pieza:** resuelto por ADR-003 (21/10/2026)~~ — **superado** por ADR-005 (25/10/2026): ya no existe la media pieza; los fiambres se venden por peso.
- [x] **Unidad de los fiambres:** resuelto por ADR-005 (25/10/2026): por peso, kg ingresado con hasta 3 decimales y mostrado con 3 decimales fijos, gramos enteros como canónico y precio por kg.
- [x] **Redondeo monetario por peso (ADR-005 D-R1):** resuelto por decisión humana del 26/10/2026: cálculo intermedio exacto, cada línea `peso` redondeada una sola vez al peso entero con empate 0,50 hacia arriba; el aporte de las líneas `peso` al total es la suma de esos importes redondeados (líneas `unidad` y documentos mixtos: pendiente, ítem siguiente); `numeric(14,2)` sigue siendo el tipo monetario general (§7.1).
- [ ] **Redondeo de líneas `unidad` y documentos mixtos:** la fórmula vigente es `cantidad × precio_unitario` (precio con hasta 2 decimales). Falta decidir (a) si el importe final de una línea `unidad` se conserva con centavos o se redondea al peso entero y (b) qué consecuencia tiene eso sobre el total de un documento mixto con líneas `peso` + `unidad`, es decir, si puede terminar con centavos. Ejemplo del problema, no decisión: `3 × $1.234,56 = $3.703,68`. D-R1 aplica únicamente a líneas `peso` y no lo resuelve (aclaración humana del 26/10/2026).
- [x] **Pesaje en la operación (ADR-005 D-R2):** resuelto por decisión humana del 26/10/2026: cada operación registra el peso efectivamente medido para esa operación (ingreso, carga, venta, devolución, conteo de regreso); sin balanza, integración ni punto de pesaje definidos (§7.1).
- [x] **Diferencias de pesaje (ADR-005 D-R3):** resuelto por decisión humana del 26/10/2026: sin tolerancia automática en Fase 1; toda diferencia distinta de cero se registra (§7.1, §7.8).
- [x] **Datos existentes con medias piezas en local/staging (ADR-005 D-R4):** resuelto por decisión humana del 26/10/2026: reinicio limpio, sin conversión ni reinterpretación; versionado limpio de claves en el prototipo (§7.1).
- [ ] **Presupuestos — numeración:** secuencia por empresa o no, formato visible, reinicio anual o no, unicidad y qué pasa con el número de un presupuesto anulado.
- [ ] **Presupuestos — ciclo de vida:** si tiene estados (no hay ningún estado definido; cualquier nombre es una decisión pendiente), si se puede editar o anular después de guardado y quién puede hacerlo.
- [ ] **Presupuestos — vigencia:** si tiene fecha de vencimiento o plazo de validez y si se muestra.
- [ ] **Presupuestos — conversión a venta:** si un presupuesto podrá convertirse en venta y con qué efecto. Hasta que se decida, no se convierte.
- [ ] **Presupuestos — vendedor/piloto:** si puede generarlos o consultarlos.
- [ ] **Presupuestos — cliente:** si se puede emitir a un cliente no registrado; significado exacto de «cuenta del cliente».
- [ ] **Presupuestos — precio:** origen del precio de cada línea (por ejemplo, si se toma automáticamente del catálogo), si es editable y quién puede modificarlo (sin descuentos en ningún caso).
- [ ] **Clientes — DNI y cuenta:** agregarlos a la ficha (hoy no existen), su obligatoriedad, formato, unicidad y quién los carga; impacto sobre el alta por vendedor.
- [ ] **Presupuestos — entrega:** en qué entrega (1A/1B) y etapa del plan entra el módulo.
- [ ] **Fechas:** día operativo y zona horaria del negocio (distinción de UTC para auditoría); corte de jornada.

### Prioridad media — antes de entrega
- [ ] ¿Cómo verificar transferencias en Fase 1: declaración del vendedor, comprobante, o verificación del dueño?
- [ ] ¿Quién maneja eventuales cobros de deudas anteriores y cómo se reflejan? Cuenta corriente integral queda en Fase 2.
- [ ] Cómo valuar faltantes (precio de venta histórico, costo, otro) y procedimiento para decidir responsabilidades sin descuento automático.
- [ ] Cantidad exacta de camiones, usuarios, catálogo y capacitación requerida; disponibilidad de conexión en depósito y rutas.
- [ ] Aclarar y aprobar por escrito la diferencia entre el alcance de la cotización comercial anterior del proyecto y este Fase 1 revisado (no confundir con el módulo Presupuestos de §7.10).

### Fase 2 — confirmado como postergado, detalle pendiente
- [ ] Proveedores/compras: fecha de compra distinta de recepción, documentos PDF/foto y pagos fraccionados en distintas fechas (confirmadas las necesidades, no la implementación Fase 1).
- [ ] Preventa y pedidos programados.
- [ ] Cuentas corrientes detalladas de clientes y proveedores.

---

## 16. Glosario

- **Jornada:** un día de reparto de un camión con un vendedor.
- **Carga:** mercadería que sube al camión al inicio de la jornada.
- **Conteo de regreso:** recuento físico de lo que vuelve en el camión.
- **Rendición:** comparación entre lo esperado y lo real (mercadería y dinero) al final de la jornada.
- **Faltante:** mercadería o dinero que debería haber vuelto y no volvió.
- **Cuarentena:** stock separado, no vendible, pendiente de decisión.
- **Merma:** mercadería descartada.
- **Unidad mínima:** unidad entera en que se guarda toda cantidad: la **unidad** para productos `unidad`; el **gramo** para productos `peso` (ADR-005). Antes del 25/10/2026 era la media pieza para fiambres (histórico).
- **Producto por peso (`peso`):** fiambre que se vende, carga, cuenta y rinde por peso. Comercialmente en kg (entrada con hasta 3 decimales; presentación con 3 decimales fijos), con precio por kg; se guarda en gramos enteros.
- **Gramo (unidad canónica):** representación entera de las cantidades de productos `peso` en la base y en el ledger (`28,680 kg` = `28680`).
- **Peso efectivamente medido:** peso real informado o medido en una operación concreta (ingreso, carga, venta, devolución o conteo); es la cantidad que registra esa operación (ADR-005 D-R2).
- **Importe de línea por peso:** importe exacto `gramos × precio_por_kg / 1000` redondeado una sola vez al peso entero, con empate 0,50 hacia arriba (ADR-005 D-R1).
- **Presupuesto:** documento interno e informativo con número, fecha, hora, datos del cliente y detalle de productos, precios e importes. IVA 21% sólo como etiqueta y sin descuentos. No es venta ni factura y no mueve stock ni dinero (§7.10). No confundir con la cotización comercial del proyecto (§4, §15).

---

## 17. Historial del documento

| Versión | Fecha | Cambio |
|---|---|---|
| 0.1 | — | Borrador inicial con alcance amplio. |
| 1.0 | 12/10/2026 | Borrador centrado en control de camiones y venta en papel. |
| 1.1 | 12/10/2026 | Relevamiento del cliente: venta digital con papel contingente; tres roles; alta limitada de clientes; una jornada/camión/día; pagos mixtos; retiros con doble confirmación; gastos autorizados; rendición revisada; proveedores/compras y preventa en Fase 2; dudas abiertas documentadas. |
| 1.2 | 13/10/2026 | Corrección de unidades: fiambres solo por pieza/media pieza, canónico en medias piezas; lácteos por unidad entera; `kg` fuera de Fase 1. |
| 1.3 | 14/10/2026 | Ajuste de roles: tres roles confirmados; tabla `roles` como propuesta; `empresas` aprobada conceptualmente. |
| 1.4 | 15/10/2026 | Integración de ADR-001 v1.1; regla de no generar migraciones hasta aprobar; P1–P20 pendientes. |
| 1.5 | 18/10/2026 | Decisión humana de unidades (lácteos por unidad entera; fiambres por pieza/media pieza, canónico en medias piezas; sin `kg`); prototipo legacy requiere migración. |
| 1.6 | 18/10/2026 | Ejemplo de consistencia categoría/unidad (`Queso cremoso en bote` → Lácteos/`unidad`; `Queso cremoso en pieza` → Fiambres/`pieza`); versionado `localStorage` v1→v2 (sin migración automática) decisión humana aprobada. |
| 1.7 | 20/10/2026 | **Decisiones arquitectónicas aprobadas conceptualmente (con ajustes)**: operaciones, ubicaciones (merma no es ubicación interna), cierres sin tabla propia, roles funcionales sin tabla roles, conteos separados, movimientos_stock ledger append-only, dinero sin ledger separado, saldos derivados, auditoría sin tabla genérica, idempotencia por operaciones, concurrencia funcional. Actualización de tabla de entidades (§8) y secciones 7.2, 7.9, 8, 9. |
| 1.8 | 20/10/2026 | **ADR-002 aprobada** (precios comerciales independientes de pieza y media pieza): §7.1 (precio, cantidad canónica vs presentación comercial, subtotal, decimales), §8 (`productos`, `venta_items`), criterios de aceptación y cierre del pendiente de §15; claves operativas del prototipo `localStorage` v2 → v3 con inicialización limpia. Sin cambios en ADR-001 ni en SQL. |
| 1.9 | 21/10/2026 | **ADR-003 aprobada — Precio derivado de media pieza** (supera a ADR-002 solo en la política de precio de media pieza; ADR-002 queda histórica): media no configurable, mitad del precio de pieza redondeada al peso entero (`.50` sube) calculada en centavos enteros; cantidad canónica en medias sin cambios; snapshot histórico conserva la media aplicada sin re-derivarla. §4, §7.1, §8 (`productos`, `venta_items`), §12 y §15; claves operativas del prototipo `localStorage` v3 → v4 con inicialización limpia. Sin cambios en ADR-001 ni SQL aprobado. |
| 2.0 | 22/10/2026 | **ADR-001 aprobada para validación controlada:** P1 selecciona Topología D; P19 adopta dos aprobaciones; P20 permite migraciones dependientes de ADR-001 sólo en local/staging. §10, §12, §13 y §15 alineados. P2–P17 siguen pendientes, P18 queda como decisión futura separada y producción continúa bloqueada hasta pruebas, auditoría independiente y aceptación humana final. Sin backend, SQL ni migraciones en este cambio. |
| 2.1 | 25/10/2026 | **Reunión con el cliente — ADR-005 aprobada (fiambres por peso):** los fiambres dejan de venderse por pieza/media pieza y pasan a venderse por peso (kg ingresado con hasta 3 decimales y mostrado con 3 fijos, gramos enteros como canónico, precio por kg, nunca `float`; redondeo monetario completamente pendiente, D-R1). ADR-003 queda REEMPLAZADA por ADR-005 y ADR-002 sigue histórica. Origen del precio del presupuesto y ciclo de vida: pendientes. **Nuevo módulo Presupuestos** (Fase 1, entrega pendiente): documento interno sin efecto de stock ni dinero, IVA 21% sólo informativo, sin descuentos, snapshot de cliente y producto, dueño/encargado (vendedor pendiente) y productos `unidad` y `peso`. §2, §4, §5, §7.1, §7.4, §7.5, §7.10 (nueva), §8, §9, §11, §12, §14, §15, §16. Desambiguación «presupuesto» ↔ «cotización comercial del proyecto». **Sin código, SQL, migraciones ni pruebas en este cambio**; la implementación requiere una tarea posterior autorizada. ADR-001 sin cambios. |
| 2.2 | 26/10/2026 | **Cierre humano de ADR-005 D-R1–D-R4:** D-R1 (sólo líneas `peso`), importe redondeado una vez por línea al peso entero (0,50 hacia arriba), sumado al total sin recálculo, `numeric(14,2)` como tipo monetario general; D-R2, peso efectivamente medido en cada operación; D-R3, sin tolerancia automática de pesaje en Fase 1; D-R4, reinicio limpio del modelo pieza/media pieza, sin reinterpretación. Nuevo pendiente: redondeo de líneas `unidad` y centavos de documentos mixtos. §2, §7.1, §7.4, §7.5, §7.8, §7.10, §8, §11, §12, §14, §15, §16. **Sin código, SQL, migraciones ni pruebas**; la migración al modelo por peso requiere una tarea posterior autorizada. |
| 2.3 | 26/10/2026 | **Estado de implementación, sin cambio de reglas:** Slice A del modelo por peso (`20261027001542_modelo_peso_gramos.sql`, validado sólo en local) deja el SQL en `unidad`/`peso` con enteros en unidad mínima (unidades o gramos), sin cambiar tipos ni firmas de RPC de stock y con falla cerrada ante datos `pieza` (D-R4). La pantalla Productos se adapta al contrato `unidad | peso` por compatibilidad inmediata. Se actualizan las notas de estado de §7.1 y §8; el resto del prototipo sigue pendiente (Slice B). |
| 2.4 | 29/10/2026 | **ADR-006 aprobada — Una línea por producto en cada venta nueva** (formaliza la decisión humana del 28/10/2026, hallazgo AUD-B3-01; complementa ADR-005 sin modificar D-R1): en una venta nueva, `productoId` es único dentro de los ítems, cualquiera sea su unidad, y las líneas repetidas invalidan la venta. Los históricos con líneas repetidas no se ven afectados: se leen sin recalcular ni migrar. §7.5 incorpora la regla y §12, sus 6 pruebas normativas. |

---

*Fin de BLUEPRINT.md v2.3*
