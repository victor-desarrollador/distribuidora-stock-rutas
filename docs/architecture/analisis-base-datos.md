# Análisis de arquitectura de base de datos — Fase 1

**Proyecto:** Distribuidora de lácteos y fiambres (VM Digital Studio)
**Fecha:** 22/10/2026 (actualización de unidades: 25/10/2026)
**Versión:** 0.3
**Estado:** documento de arquitectura. Deriva de `BLUEPRINT.md` y `docs/PRD.md`. **No autoriza por sí solo implementación**; ADR-001 v1.5 habilita validación controlada local/staging únicamente después de resolver las decisiones técnicas necesarias.

---

## 0. Propósito

Este documento consolida el análisis de arquitectura de base de datos para la Fase 1, a partir de las decisiones **aprobadas conceptualmente** en el Blueprint §7.9, §8 y §9. Su objetivo es servir de insumo para el **diseño SQL/RPC** posterior (que requiere aprobación humana y pruebas de seguridad antes de generar migraciones).

> **Regla obligatoria:** ADR-001 está aprobada para validación controlada con Topología D. Las migraciones dependientes de esa ADR se permiten sólo en local/staging y una vez resueltas las P8–P17 necesarias (P2–P7 ya resueltas); producción sigue bloqueada hasta pruebas, auditoría independiente y aceptación humana final (Blueprint §10; AGENTS.md §3).

> **Unidades de cantidad ([ADR-005](../decisions/005-fiambres-por-peso-gramos.md), aprobada el 25/10/2026).** En este documento se distinguen tres estados:
>
> - **Arquitectura anterior (histórica):** fiambres por pieza/media pieza, con unidad mínima en medias piezas (Blueprint v1.2–v2.0; ADR-002/ADR-003). Ya no es regla vigente.
> - **Modelo objetivo vigente (ADR-005):** productos `unidad` en cantidad entera; productos `peso` (fiambres) en kg: se ingresan con hasta 3 decimales y se muestran con 3 decimales fijos; la representación canónica es en gramos enteros; precio por kg. Nunca `float` para cantidades ni para dinero. **Modelo objetivo aprobado por ADR-005; implementación pendiente.**
> - **Implementación SQL actual (local/staging, todavía no migrada):** `productos` admite `forma_venta in ('unidad','pieza')`, precio de pieza completa y `stock_minimo` en medias piezas (`20261023140000_catalogo_productos.sql`). **Estado actual desactualizado respecto del modelo objetivo.** El ledger `movimientos_stock.cantidad integer` no cambia de tipo (ADR-005 §6). El cambio requiere una tarea de migración posterior autorizada, con security review.
>
> Las columnas, tipos y restricciones SQL definitivos para `peso` no se fijan en este documento: los define esa tarea.

---

## 1. Principios rectores (del Blueprint)

| Principio | Sección Blueprint |
|---|---|
| Stock = suma de movimientos (`movimientos_stock` append-only) | §3.1, §7.4 |
| Ubicaciones internas reales: `deposito`, `cuarentena`, `camion:<id>`; `merma` y `cliente` = salidas terminales | §7.2 |
| Operación = ejecución lógica idempotente; agrupa efectos atómicos | §7.9.1 |
| Conteo = hecho observado (no modifica stock); regularización = operación posterior | §7.9.2, §7.9.3 |
| Cierre = jornada (estado) + rendición (conciliación) + operación tipo cierre | §7.9.4 |
| Dinero y stock separados; correcciones compensatorias, no automáticas | §7.9.5 |
| Idempotencia en cada comando crítico; `idempotency_key` en `operaciones` | §7.9.6 |
| Concurrencia: solo garantías funcionales; implementación en diseño SQL/RPC | §7.9.7 |
| Empresa única: `empresa_id` en las tablas de negocio como clave técnica de aislamiento y RLS | §7.3 |
| Roles funcionales: dueño, encargado, vendedor/piloto; tabla `roles` NO aprobada | §9 |
| Auditoría: sin tabla genérica; trazabilidad en ledgers/documentos | §10 |

---

## 2. Entidades — clasificación vigente (Blueprint §8 actualizada)

| Entidad | Categoría | Notas |
|---|---|---|
| `empresas` | **APROBADA CONCEPTUALMENTE** | Entidad dueña; FK `empresa_id` en tablas de negocio; RLS por empresa |
| `perfiles` | **APROBADA CONCEPTUALMENTE** | Usuario auth + nombre + activo; empresa y rol leídos de tablas protegidas |
| `roles` | **PROPUESTA TÉCNICA** | Sin tabla de membresías: un perfil 1:1 con `auth.users`, una empresa y un rol por usuario (decisión humana P5–P7, ADR-001 §18). **Roles funcionales (dueño, encargado, vendedor/piloto) APROBADOS**; tabla `roles` NO aprobada |
| `productos` | **APROBADA CONCEPTUALMENTE** | Código, nombre, categoría, forma_venta (`unidad`/`peso`; ADR-005), precio (unitario en `unidad`, por kg en `peso`), stock_mínimo (en unidad mínima: unidades o gramos), activo. Modelo objetivo aprobado por ADR-005; implementación pendiente. *Estado actual SQL local, desactualizado: `unidad`/`pieza` y medias piezas (§0)* |
| `camiones` | **APROBADA CONCEPTUALMENTE** | Patente, nombre, activo |
| `clientes` | **APROBADA CONCEPTUALMENTE** | Contraparte comercial; creable por vendedor, editable solo por encargado/dueño |
| `ubicaciones` | **APROBADA CONCEPTUALMENTE** | Internas: `deposito`, `cuarentena`, `camion` (camion_id). **`merma` no es ubicación interna** (salida terminal) |
| `operaciones` | **APROBADA CONCEPTUALMENTE** | empresa_id, tipo, actor, jornada_id (opcional), idempotency_key, creado_en; ejecución lógica idempotente |
| `movimientos_stock` | **APROBADA CONCEPTUALMENTE** | operacion_id, tipo_movimiento, producto_id, cantidad (entero, unidad mínima), ubicacion_origen_id (nullable), ubicacion_destino_id (nullable), jornada_id, actor, motivo, creado_en. **Sin `saldo_actual`.** Append-only |
| `saldos_stock` | **DERIVADA** | No es fuente de verdad en Fase 1. El saldo se deriva de `movimientos_stock`. Caché/materialización = optimización futura |
| `jornadas` | **APROBADA CONCEPTUALMENTE** | fecha, camion_id, vendedor_id, estado, ventas_finalizadas_at, abierta_por, contada_por, cerrada_por, cerrada_at, observaciones |
| `conteos` | **APROBADA CONCEPTUALMENTE** | jornada_id, contado_por, contado_en, tipo; hecho observado, **no** modifica stock. Idempotente |
| `conteos_items` | **APROBADA CONCEPTUALMENTE** | conteo_id, producto_id, cantidad_apta, cantidad_cuarentena, cantidad_no_apta |
| `rendiciones` | **APROBADA CONCEPTUALMENTE** | jornada_id, totales históricos, diferencia_mercaderia_valorizada, diferencia_efectivo, diferencia_transferencias_declaradas_vs_verificadas, aprobado_por, aprobado_at, motivo_aprobacion, observaciones |
| `rendicion_items` | **PROPUESTA TÉCNICA** | rendicion_id, producto_id, cálculo congelado (cargado, vendido, devuelto, merma, esperado, contado, diferencia). **No es segunda fuente editable de contado**; el contado vive en `conteos_items` |
| `retornos` | **PROPUESTA TÉCNICA** | jornada_id, retorno de mercadería; detalle por producto y aptitud |
| `mermas` | **PROPUESTA TÉCNICA** | Modelable como movimiento `tipo_movimiento = merma` bajo operación `tipo = merma`; tabla propia solo si el diseño lo justifica |
| `retiros_efectivo` | **APROBADA CONCEPTUALMENTE** | jornada_id, importe, entregado_por, recibido_por, motivo, ocurrido_at_declarado, confirmado_entrega_at, confirmado_recepcion_at, estado |
| `gastos_ruta` | **PROPUESTA TÉCNICA** | jornada_id, importe, motivo, comprobante, autorizado_por, estado, fecha |
| `talonarios` | **PROPUESTA TÉCNICA** | serie, numero_desde, numero_hasta, asignado_a, estado, fecha_asignacion |
| `notas_talonario` | **PROPUESTA TÉCNICA** | talonario_id, numero, jornada_id, estado (`utilizada`/`anulada`/`justificada`), venta_id nullable, motivo, registrado_por |
| `ventas` | **APROBADA CONCEPTUALMENTE** | operacion_id, jornada_id, cliente_id, origen (digital/papel), serie_talonario, numero_nota, total, estado |
| `venta_items` | **APROBADA CONCEPTUALMENTE** | venta_id, producto; cantidad en la unidad mínima del producto (unidades para `unidad`, gramos para `peso`); precio aplicado (unitario para `unidad`, por kg para `peso`); importe de la línea; snapshot histórico suficiente para reconstruir la venta sin recalcular. Modelo objetivo aprobado por ADR-005; implementación SQL pendiente (nombres y tipos de columnas no definidos; redondeo del importe por peso pendiente, ADR-005 D-R1) |
| `venta_pagos` | **APROBADA CONCEPTUALMENTE** | operacion_id, venta_id, medio (efectivo/transferencia/a_cuenta; otros pendientes), importe, referencia, estado (`declarada`/`verificada` para transferencias), verificado_por, verificado_at |
| `partidas_ingreso` | **F2 / PROPUESTA NO APROBADA** | producto_id, fecha_ingreso, fecha_vencimiento (nullable), cantidad_inicial. **No se mantienen saldos por partida ni se atribuye cada venta a un ingreso.** No implementar sin aprobación |
| `auditoria` | **DERIVADA** | **No hay tabla genérica en Fase 1.** La trazabilidad surge de operaciones, ledgers, documentos, actor, timestamps, motivos, jornada y relaciones |
| ledger financiero | **DERIVADA** | **No hay ledger financiero separado en Fase 1.** Fuente documental: ventas, pagos/cobros, retiros, rendición. Saldo de caja: derivado |
| `cierres` | **DERIVADA** | **Sin tabla propia en Fase 1.** Cierre = jornada + rendición + operación `tipo` cierre |

---

## 3. Relaciones conceptuales (resumen)

```
empresas (1) ──< (muchas) perfiles
empresas (1) ──< (muchas) productos
empresas (1) ──< (muchas) camiones
empresas (1) ──< (muchas) clientes
empresas (1) ──< (muchas) jornadas
empresas (1) ──< (muchas) ubicaciones (depósito, cuarentena)
empresas (1) ──< (muchas) operaciones
empresas (1) ──< (muchas) movimientos_stock
empresas (1) ──< (muchas) conteos
empresas (1) ──< (muchas) rendiciones
empresas (1) ──< (muchas) retiros_efectivo
empresas (1) ──< (muchas) gastos_ruta
empresas (1) ──< (muchas) talonarios
empresas (1) ──< (muchas) ventas

jornadas (1) ──< (muchas) operaciones (opcional)
jornadas (1) ──< (muchas) movimientos_stock (opcional)
jornadas (1) ──< (1) conteos
jornadas (1) ──< (1) rendiciones
jornadas (1) ──< (muchas) retiros_efectivo
jornadas (1) ──< (muchas) gastos_ruta
jornadas (1) ──< (muchas) ventas

operaciones (1) ──< (muchas) movimientos_stock
operaciones (1) ──< (1) ventas
operaciones (1) ──< (muchas) venta_pagos
operaciones (1) ──< (1) retiros_efectivo
operaciones (1) ──< (1) cierres (operación tipo cierre)

ventas (1) ──< (muchas) venta_items
ventas (1) ──< (muchas) venta_pagos

conteos (1) ──< (muchas) conteos_items

rendiciones (1) ──< (muchas) rendicion_items (si se aprueba)
```

---

## 4. Detalle de entidades clave

### 4.1 `operaciones` (APROBADA CONCEPTUALMENTE)

| Campo | Tipo | Comentario |
|---|---|---|
| `id` | uuid / bigint | PK |
| `empresa_id` | FK → empresas | Obligatorio |
| `tipo` | text / enum | venta, carga, movimiento_stock, pago, retorno, regularizacion, retiro, cierre, conteo |
| `actor` | uuid / FK → auth.users | Usuario que ejecuta |
| `jornada_id` | FK → jornadas | Nullable (no toda operación tiene jornada) |
| `idempotency_key` | text | Única por (empresa_id, tipo, clave); protege reintentos |
| `creado_en` | timestamptz | Servidor UTC |

**Reglas:**
- Una operación = UNA ejecución lógica/idempotente de un comando de negocio.
- Todos los efectos creados atómicamente por esa ejecución referencian `operaciones.id`.
- Una acción posterior independiente crea OTRA operación.
- **No se duplica `idempotency_key` en documentos hijos** salvo necesidad concreta en diseño SQL/RPC.

### 4.2 `movimientos_stock` (APROBADA CONCEPTUALMENTE)

| Campo | Tipo | Comentario |
|---|---|---|
| `id` | uuid / bigint | PK |
| `operacion_id` | FK → operaciones | Obligatorio: cada movimiento pertenece a una operación |
| `tipo_movimiento` | text / enum | ingreso, carga, venta, retorno, devolucion_cliente, a_cuarentena, cuarentena_apta, merma, regularizacion_faltante, regularizacion_sobrante, ajuste |
| `producto_id` | FK → productos | Obligatorio |
| `cantidad` | integer | **Entero positivo** en unidad mínima: unidad entera para `unidad`, gramos para `peso` (modelo objetivo aprobado por ADR-005; implementación pendiente). Antes de ADR-005: medias piezas para fiambres (histórico) |
| `ubicacion_origen_id` | FK → ubicaciones | Nullable (ej. ingreso desde exterior) |
| `ubicacion_destino_id` | FK → ubicaciones | Nullable (ej. venta/merma a exterior) |
| `jornada_id` | FK → jornadas | Nullable según tipo |
| `actor` | uuid / FK → auth.users | Quién ejecutó |
| `motivo` | text | Nullable; obligatorio para `ajuste`, `merma`, `regularizacion_*` |
| `creado_en` | timestamptz | Servidor UTC |

**Restricciones:**
- Append-only: **no UPDATE ni DELETE**.
- Al menos uno de `ubicacion_origen_id`, `ubicacion_destino_id` no nulo.
- `cantidad` > 0 siempre; la dirección la dan origen/destino.
- Rectificación = movimientos compensatorios nuevos (con motivo y operación propia).

### 4.3 `ubicaciones` (APROBADA CONCEPTUALMENTE)

| Campo | Tipo | Comentario |
|---|---|---|
| `id` | uuid / bigint | PK |
| `empresa_id` | FK → empresas | Obligatorio |
| `tipo` | text / enum | `deposito`, `cuarentena`, `camion` |
| `camion_id` | FK → camiones | Solo para tipo `camion`; nullable para otros |
| `nombre` | text | Descriptivo (ej. "Depósito principal", "Cuarta en planta") |
| `activo` | boolean | |

**Notas:**
- `merma` **no** es fila en `ubicaciones`; se usa `tipo_movimiento = merma` con `ubicacion_destino_id = NULL`.
- `cliente` **no** es fila en `ubicaciones`; la venta usa `ubicacion_destino_id = NULL` y la contraparte está en `ventas.cliente_id`.

### 4.4 `conteos` + `conteos_items` (APROBADA CONCEPTUALMENTE)

| Tabla | Campo | Tipo | Comentario |
|---|---|---|---|
| `conteos` | `id` | uuid / bigint | PK |
| | `jornada_id` | FK → jornadas | Obligatorio; único por jornada (un solo conteo formal) |
| | `contado_por` | FK → auth.users | Distinto del vendedor de la jornada |
| | `contado_en` | timestamptz | Servidor UTC |
| | `tipo` | text | `regreso` (principal); extensible |
| | `idempotency_key` | text | Protección contra duplicación por reintentos |

| `conteos_items` | `id` | uuid / bigint | PK |
|---|---|---|---|
| | `conteo_id` | FK → conteos | Obligatorio |
| | `producto_id` | FK → productos | Obligatorio |
| | `cantidad_apta` | integer | ≥ 0 (unidad mínima) |
| | `cantidad_cuarentena` | integer | ≥ 0 |
| | `cantidad_no_apta` | integer | ≥ 0 |

**Regla:** el conteo **no genera `movimientos_stock`**. El esperado se deriva de `movimientos_stock`; la diferencia = contado − esperado. La regularización posterior (operación explícita) sí genera movimientos.

### 4.5 `rendiciones` (APROBADA CONCEPTUALMENTE)

| Campo | Tipo | Comentario |
|---|---|---|
| `id` | uuid / bigint | PK |
| `jornada_id` | FK → jornadas | Único por jornada |
| `totales_historicos` | jsonb | Cargado, vendido, devuelto, merma, esperado, contado, diferencia por producto |
| `diferencia_mercaderia_valorizada` | numeric(14,2) | Diferencia física en pesos |
| `diferencia_efectivo` | numeric(14,2) | `efectivo_contado_entregado - efectivo_esperado` |
| `diferencia_transferencias_declaradas_vs_verificadas` | numeric(14,2) | |
| `aprobado_por` | FK → auth.users | Dueño/encargado |
| `aprobado_at` | timestamptz | Servidor UTC |
| `motivo_aprobacion` | text | Obligatorio si hay diferencias |
| `observaciones` | text | |

### 4.6 `jornadas` (APROBADA CONCEPTUALMENTE)

| Campo | Tipo | Comentario |
|---|---|---|
| `id` | uuid / bigint | PK |
| `empresa_id` | FK → empresas | |
| `fecha` | date | Día operativo |
| `camion_id` | FK → camiones | |
| `vendedor_id` | FK → auth.users / perfiles | |
| `estado` | text / enum | `abierta`, `cargada`, `en_reparto`, `ventas_finalizadas`, `regreso_contado`, `cerrada` |
| `ventas_finalizadas_at` | timestamptz | Nullable |
| `abierta_por` | FK → auth.users | |
| `contada_por` | FK → auth.users | Distinto de `vendedor_id` |
| `cerrada_por` | FK → auth.users | Dueño/encargado |
| `cerrada_at` | timestamptz | Servidor UTC |
| `observaciones` | text | |

**Restricción única:** (`empresa_id`, `camion_id`, `fecha`) — una jornada por camión por día, incluso cerrada.

### 4.7 `retiros_efectivo` (APROBADA CONCEPTUALMENTE)

| Campo | Tipo | Comentario |
|---|---|---|
| `id` | uuid / bigint | PK |
| `operacion_id` | FK → operaciones | Para idempotencia y correlación |
| `jornada_id` | FK → jornadas | |
| `importe` | numeric(14,2) | > 0 |
| `entregado_por` | FK → auth.users | Vendedor/piloto |
| `recibido_por` | FK → auth.users | Dueño/encargado |
| `motivo` | text | |
| `ocurrido_at_declarado` | timestamptz | Hora real del hecho (puede diferir de registro) |
| `confirmado_entrega_at` | timestamptz | Timestamp servidor de confirmación entrega |
| `confirmado_recepcion_at` | timestamptz | Timestamp servidor de confirmación recepción |
| `estado` | text / enum | `pendiente_doble_confirmacion`, `confirmado`, `rechazado` |

**Regla:** efecto contable **solo** tras `confirmado_entrega_at` Y `confirmado_recepcion_at` no nulos. `idempotency_key` en `operaciones` evita duplicados.

---

## 5. Flujo de datos — operaciones críticas (conceptual)

| Operación | Tablas afectadas (en una transacción) | Idempotencia |
|---|---|---|
| **Apertura jornada** | `jornadas` (insert), `operaciones` (tipo=apertura) | `idempotency_key` en operaciones |
| **Carga camión** | `movimientos_stock` (tipo=carga, depósito→camión), `operaciones` (tipo=carga) | `idempotency_key` en operaciones |
| **Venta (digital/papel)** | `ventas`, `venta_items`, `venta_pagos`, `movimientos_stock` (tipo=venta, camión→NULL), `operaciones` (tipo=venta) | `idempotency_key` en operaciones |
| **Cobro posterior (cuenta corriente)** | `venta_pagos` (nuevo pago), `operaciones` (tipo=pago) | `idempotency_key` en operaciones |
| **Retorno fin de jornada** | `movimientos_stock` (tipo=retorno, camión→depósito), `operaciones` (tipo=retorno) | `idempotency_key` en operaciones |
| **Merma** | `movimientos_stock` (tipo=merma, camión/depósito→NULL), `operaciones` (tipo=merma) | `idempotency_key` en operaciones |
| **Conteo regreso** | `conteos`, `conteos_items`, `operaciones` (tipo=conteo) | `idempotency_key` en operaciones |
| **Regularización** | `movimientos_stock` (tipo=regularizacion_*), `operaciones` (tipo=regularizacion) | `idempotency_key` en operaciones |
| **Retiro efectivo** | `retiros_efectivo`, `operaciones` (tipo=retiro) | `idempotency_key` en operaciones |
| **Rendición** | `rendiciones`, `rendicion_items` (si aprueba), `operaciones` (tipo=rendicion) | `idempotency_key` en operaciones |
| **Cierre** | `jornadas` (update estado→cerrada, cerrada_por, cerrada_at), `operaciones` (tipo=cierre) | `idempotency_key` en operaciones |

---

## 6. Consultas derivadas (no tablas)

| Derivado | Fuente | Fórmula conceptual |
|---|---|---|
| **Stock por ubicación** | `movimientos_stock` | `SUM(cantidad) FILTER (WHERE ubicacion_destino_id = X) - SUM(cantidad) FILTER (WHERE ubicacion_origen_id = X)` agrupado por `producto_id` |
| **Stock camión en jornada** | `movimientos_stock` | Mismos, filtrando `jornada_id` y `ubicacion_destino_id = camion:<id>` / `ubicacion_origen_id = camion:<id>` |
| **Esperado físico camión** | `movimientos_stock` | `carga + entradas - salidas` (ventas netas, mermas, devoluciones a terceros) |
| **Diferencia física** | `conteos_items` vs esperado | `contado_total - esperado_fisico` por producto |
| **Efectivo esperado** | `venta_pagos` + `retiros_efectivo` + `gastos_ruta` | `efectivo_cobrado + otros_ingresos - retiros_confirmados - gastos_autorizados` |
| **Diferencia dinero** | `rendiciones` | `efectivo_contado_entregado - efectivo_esperado` |
| **Saldo caja jornada** | `venta_pagos` + `retiros_efectivo` + `gastos_ruta` | Derivado al cerrar; no tabla propia |

---

## 7. Seguridad — Topología D aprobada para validación controlada

> **Recordatorio:** ADR-001 está **APROBADA PARA VALIDACIÓN CONTROLADA**. P1/P19/P20, P2–P4 y P5–P7 están resueltas; P8–P17 siguen pendientes y P18 es una decisión futura separada. No hay autorización productiva.

1. **Fachada expuesta `SECURITY INVOKER`** como entrada desde la Data API para escrituras críticas (stock, dinero, jornada, retiros, cierre).
2. **Implementación `SECURITY DEFINER` en esquema privado/no expuesto**, frontera real de seguridad, con `SET search_path = ''` y referencias totalmente calificadas.
3. Grants de privilegio mínimo; sin DML directo a ledgers y sin ejecución pública o anónima de la implementación privilegiada.
4. La función privada no es invocable directamente desde la Data API.
5. La implementación privada valida **antes de escribir**:
   - `auth.uid()` existe
   - Perfil activo (empresa y rol del perfil)
   - `empresa_id` obtenida/verificada del servidor (no del cliente)
   - Rol autorizado para la operación
   - Estado de la jornada compatible
   - Cantidades válidas (enteras, unidad mínima, positivas)
   - Permisos sobre cada objeto afectado
6. **No existen otras rutas** con privilegios equivalentes (ni Data API directa, ni funciones privadas expuestas).
7. `SECURITY INVOKER` para lecturas y ediciones ordinarias con grants y RLS apropiados.
8. Las migraciones necesarias para probar este patrón se permiten exclusivamente local/staging; producción requiere pruebas reales desde `anon`, `authenticated` ajeno y roles válidos, auditoría independiente y aceptación humana final.

---

## 8. Decisiones abiertas para diseño SQL/RPC (requieren aprobación)

| Tema | Qué falta decidir | Estado |
|---|---|---|
| Esquema de `perfiles` | Perfil 1:1 con `auth.users`, una empresa y un rol, sin membresías (P5–P7, ADR-001 §18); cómo se deriva `empresa_id` y `rol` | PROPUESTA TÉCNICA |
| `idempotency_key`: formato, unicidad compuesta, índice | `empresa_id + tipo + clave` vs. global; longitud; generar en cliente vs. servidor | PROPUESTA TÉCNICA |
| `ubicaciones`: una fila por camión vs. fila genérica + `camion_id` | Cómo modelar `camion:<id>` sin duplicar identidad | PROPUESTA TÉCNICA |
| `rendicion_items`: aprobar tabla propia vs. solo vista/derivado | Si se aprueba, columnas exactas; si no, vista materializada opcional | PROPUESTA TÉCNICA |
| `retornos` / `mermas`: tablas propias vs. solo `movimientos_stock` + `operaciones` | Justificación de tabla propia vs. consulta filtrada | PROPUESTA TÉCNICA |
| `gastos_ruta` / `talonarios` / `notas_talonario`: esquemas exactos | Campos, estados, FKs, restricciones | PROPUESTA TÉCNICA |
| Concurrencia: `SELECT FOR UPDATE` vs. advisory locks vs. optimista | Nivel de aislamiento; orden de locks; reintentos | PROPUESTA TÉCNICA |
| Particionado / índices para `movimientos_stock` | Por `empresa_id`, `jornada_id`, `producto_id`, `creado_en` | Optimización posterior |

---

## 9. Riesgos y observaciones

1. **ADR-001 no aprobada para producción**: la Topología D y la gobernanza están resueltas, pero P8–P17 bloquean las partes correspondientes de una validación completa; producción sigue bloqueada.
2. **`movimientos_stock` sin `saldo_actual`**: requiere consultas de suma frecuentes; evaluar vistas/materializadas en fase de optimización (no requisito Fase 1).
3. **Empresa única con RLS desde el día 1**: RLS debe implementarse desde el día 1 aunque solo haya un `empresa_id`; una segunda empresa ficticia se usa únicamente en tests de aislamiento.
4. **`idempotency_key` en `operaciones`**: centraliza protección pero exige que **toda** escritura crítica pase por creación de operación. Verificar que no quede ruta directa (ej. `INSERT` directo en `movimientos_stock` desde RPC sin operación).
5. **Cierre sin tabla propia**: la operación tipo `cierre` debe capturar estado previo (snapshot de totales) para auditoría, ya que `jornadas` solo guarda estado final.
6. **Dinero sin ledger propio**: `venta_pagos`, `retiros_efectivo`, `gastos_ruta`, `rendiciones` son la fuente. Confirmar que cubren todos los casos (ingresos varios, ajustes de caja).
7. **Conteo idempotente**: corregir "Conteo — No aplica" de propuestas anteriores; el conteo es escritura y necesita `idempotency_key`.

---

## 10. Próximos pasos (requieren autorización humana)

1. **Diseño SQL detallado** de las entidades APROBADAS CONCEPTUALMENTE (columnas exactas, tipos, constraints, FKs, índices).
2. **Definición de RPC** por operación crítica (firmas, validaciones, transacciones, manejo de errores).
3. Resolver las P8–P17 necesarias para el alcance de validación autorizado.
4. **Migraciones versionadas** en `supabase/migrations/` (una por cambio lógico), exclusivamente local/staging.
5. **Tests pgTAP** sobre las RPC (stock, dinero, jornada, seguridad).
6. **Revisión de seguridad** independiente (superficies §2.4 de AGENTS.md).
7. **Auditoría independiente** del commit final (OpenCode auditor + Codex).

---

*Fin de `docs/architecture/analisis-base-datos.md` v0.3*
