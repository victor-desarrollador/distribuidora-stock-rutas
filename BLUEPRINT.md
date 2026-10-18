# BLUEPRINT — Sistema de Control para Distribuidora de Lácteos y Fiambres

**Proyecto:** VM Digital Studio
**Versión:** 1.6 (documento de trabajo controlado; propuestas no aprobadas identificadas)
**Fecha:** 18/10/2026 (hora local Argentina)
**Estado:** Apto para inventario técnico de solo lectura y planificación de tareas independientes. No autoriza implementar decisiones pendientes ni ejecutar migraciones productivas. Entregas 1A/1B pendientes de aprobación comercial.

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
- **Unidades (decisión humana confirmada):** los **lácteos** se venden y controlan por **cantidad/unidad entera**; los **fiambres**, **únicamente por pieza o media pieza** (1 pieza = 2 medias piezas; 1/2 pieza = 1 media pieza; la representación canónica es siempre un entero en medias piezas). **No existe `kg` en Fase 1.** El prototipo legacy todavía usa `kg` y expresa las piezas como piezas enteras, y requiere migración (ver §7.1 y `docs/requirements/migracion-unidades-prototipo.md`).
- Vencimientos: el cliente pidió **control de vencimientos asociado a productos, sin trazabilidad por lote**. **PROPUESTA TÉCNICA NO APROBADA:** anotar fecha de vencimiento en cada ingreso de mercadería, sin asignar ventas a ingresos ni prometer saldos disponibles por partida. Ver secciones 4, 5 y 8.
- Devoluciones: **tratamiento según producto**. No exigen aprobación humana general para retornar al stock vendible, pero **nunca** se reingresará automáticamente mercadería no apta: debe cumplir reglas verificables de aptitud, origen y conservación; criterios pendientes.
- **Fase 2:** preventa, pedidos programados, proveedores, compras, comprobantes de compra, pagos combinados a proveedores, cuotas y cuentas corrientes de proveedores. En Fase 2 se contemplará recepción distinta de la fecha de compra y almacenamiento privado de foto/PDF de comprobantes.
- No incluye emisión fiscal por ARCA. Los comprobantes de Fase 1 son internos.

---

## 3. Principios

1. **El stock nunca se edita a mano.** Todo cambio de stock es un movimiento registrado (quién, cuándo, por qué, cuánto, desde dónde, hacia dónde).
2. **Separación de responsabilidades.** Quien cuenta el regreso no es el vendedor. El sistema registra quién hizo cada paso.
3. **Una jornada cerrada no se modifica.** Las correcciones posteriores se hacen con ajustes con motivo, auditados.
4. **Simple antes que completo.** Ante la duda, la versión más simple que cumpla el objetivo.
5. **Nada se da por terminado sin prueba.** Un error no está resuelto porque un agente diga que lo resolvió: necesita test o verificación documentada.

---

## 4. Alcance — Fase 1 (funcionalmente acordado; confirmar con presupuesto)

| Módulo | Entrega propuesta | Incluye |
|---|---|---|
| Productos | 1A | Alta, edición y baja lógica por dueño/encargado. Categoría, forma de venta, precio de venta y stock mínimo. Fiambre por pieza/media pieza. Alertas orientativas de vencimiento por fecha de cada ingreso (**propuesta pendiente de aprobación**, sin FEFO). |
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
- Facturación electrónica ARCA; comprobantes internos no son facturas fiscales.
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

### 7.1 Unidades: unidad entera, pieza y media pieza

- Cada producto tiene una **forma de venta**:
  - `unidad` — **lácteos**: se venden y controlan por **cantidad/unidad entera** (ej. yogur, sachet de leche, queso, caja). Nunca fracciones.
  - `pieza` — **fiambres**: se venden y controlan **únicamente por pieza o media pieza**.
- **No existe `kg` en Fase 1.** Ningún producto se vende, carga, cuenta ni rinde por kilogramo.
- Para productos `pieza` (fiambres), **el stock se guarda en medias piezas** (número entero), que es la **representación canónica**.
  - 1 pieza = 2 medias piezas. 1/2 pieza = 1 media pieza.
  - En pantalla se muestra como "4 piezas + 1 media" (= 9 en la base).
- **Nunca se usan decimales para cantidades.** Todas las cantidades en la base son enteros en la unidad mínima: **unidad entera** para `unidad`, **medias piezas** para `pieza`.
- **Ejemplo de consistencia categoría/unidad** *(es solo un ejemplo de coherencia categoría↔unidad; **no** es una regla sobre nombres de producto)*: `Queso cremoso en bote` (untable) → `Lácteos` / `unidad` (cantidad canónica **entera**); `Queso cremoso en pieza` → `Fiambres` / `pieza` (cantidad canónica **entera en medias piezas**). **No** se admite la combinación `Lácteos` + `pieza` ni `Fiambres` + `unidad`.
- Precio: se define **precio por pieza**. El precio de la media pieza es la mitad, salvo que se defina un precio propio de media pieza. *(Confirmar con el cliente — ver sección 15.)*
- **Prototipo legacy (pendiente de migración).** El prototipo de demostración actual (`apps/web/src/`) **todavía contiene `kg`** y **expresa las piezas como piezas enteras** (no en medias piezas). Esa representación **no cumple esta regla** y **requiere migración** antes de reutilizar sus datos o su lógica. El requisito de migración está en `docs/requirements/migracion-unidades-prototipo.md`. El versionado de las claves demo de `localStorage` (v1 → v2, con **inicialización limpia** y **sin migración automática** de cantidades) es una **decisión humana aprobada** (18/10/2026); su **ejecución** queda pendiente de autorización.

### 7.2 Ubicaciones de stock

| Ubicación | Significado |
|---|---|
| `deposito` | Mercadería vendible en el depósito. |
| `cuarentena` | Mercadería devuelta o dudosa, pendiente de decisión (apta / merma). No se puede cargar a un camión. |
| `camion:<id>` | Mercadería que está arriba de un camión en una jornada abierta. |
| `merma` | Destino contable de descarte; no es stock vendible. |

### 7.3 Preparación para multiempresa

Todas las tablas de negocio llevan `empresa_id`, y las políticas RLS filtran por él. Hoy existe una sola empresa. No se construye registro de empresas, suscripciones ni panel de administración de plataforma.

### 7.4 Movimientos de stock

Todo cambio de stock genera un registro en `movimientos_stock` con:
tipo, producto, cantidad (entero, unidad mínima), ubicación origen, ubicación destino, jornada (si aplica), usuario, fecha y hora, motivo/observación.

Tipos de movimiento:

| Tipo | Origen → Destino |
|---|---|
| `ingreso` | (externo) → depósito |
| `carga_camion` | depósito → camión |
| `venta` | camión → (cliente) |
| `retorno_camion` | camión → depósito |
| `devolucion_cliente` | (cliente) → camión (recepción física); reclasificación posterior a depósito, cuarentena o merma según aptitud |
| `a_cuarentena` | camión/depósito → cuarentena |
| `cuarentena_apta` | cuarentena → depósito |
| `merma` | cualquier ubicación → merma |
| `faltante_rendicion` | camión → (faltante), con aprobación y causa registrada |
| `sobrante_rendicion` | (diferencia identificada) → camión, con autorización y explicación, antes de regularizar el destino físico |
| `ajuste` | cualquiera, con motivo obligatorio y permiso de administrador |

El stock de cada ubicación es la suma de sus movimientos (puede haber una vista o tabla de saldos mantenida por la misma transacción, pero el registro de movimientos es la verdad). **No se permiten saldos negativos silenciosos.** Si una venta en papel aún no registrada hace que una venta posterior exceda el saldo informático, registrar una incidencia de conciliación y exigir regularización trazable por dueño/encargado; la venta física realizada nunca se borra ni se inventa stock. El procedimiento excepcional de regularización requiere definición y prueba antes de producción. **PROPUESTA NO APROBADA:** permitir negativo transitorio exclusivamente en la ubicación del camión con jornada abierta, marcar la venta `excede_stock`, registrar incidencia y bloquear el cierre hasta regularización autorizada; depósitos y cuarentena nunca en negativo. Debe revisarse también con operaciones simultáneas.

### 7.5 Jornada y ventas (online-first + papel)

Flujo lógico: `abierta → cargada → en_reparto → ventas_finalizadas → regreso_contado → cerrada`. Los eventos se registran por separado y el cierre exige su validación; evitar transiciones implícitas. Puede registrarse un retiro de efectivo mientras la jornada esté en reparto.

- **Una sola jornada por (`empresa_id`, `camion_id`, `fecha`)**, aunque otra del mismo día esté cerrada; no habrá segunda salida por camión ese día.
- El vendedor registra ventas digitales con conexión. Sin conexión usa talonario numerado; **debe transcribir, guardar en servidor y declarar completas** las ventas en papel antes de que el encargado inicie el **conteo formal**. El camión puede ingresar físicamente al predio; el sistema solo bloquea el proceso administrativo.
- Identificar origen de venta (`digital`/`papel`), serie y número de nota (cuando aplique), usuario, instante de registro del servidor, jornada, cliente, ítems, precios históricos y pagos.
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

## 8. Modelo de datos (propuesto)

> Nombres en español, snake_case. Todas las tablas llevan `id`, `empresa_id`, `created_at`, `created_by`.

| Tabla | Campos principales |
|---|---|
| `empresas` | nombre |
| `perfiles` | usuario (auth), nombre, activo; roles permitidos: dueño, encargado, vendedor/piloto |
| `productos` | codigo, nombre, categoria, forma_venta (`unidad`/`pieza`), precio_pieza_o_unidad, precio_media_pieza (nullable), stock_minimo, activo; el vencimiento real se registrará **por ingreso/partida**, no como fecha única editable de producto |
| `partidas_ingreso` | producto_id, fecha_ingreso, fecha_vencimiento (nullable), cantidad_inicial, movimiento_ingreso_id. **No se mantienen saldos por partida ni se atribuye cada venta a un ingreso.** Propuesta pendiente de aprobación. |
| `camiones` | patente, nombre, activo |
| `clientes` | nombre, comercio, direccion, telefono, activo, creado_por, validado_por, estado_validacion |
| `ubicaciones` | tipo (`deposito`/`cuarentena`/`camion`/`merma`), camion_id (nullable) |
| `movimientos_stock` | tipo, producto_id, cantidad, origen_id, destino_id, jornada_id, motivo, observacion |
| `saldos_stock` | producto_id, ubicacion_id, cantidad (mantenido por las RPC) |
| `jornadas` | fecha, camion_id, vendedor_id, estado, ventas_finalizadas_at, abierta_por, contada_por, cerrada_por, cerrada_at, observaciones |
| `jornada_carga` | jornada_id, producto_id, cantidad |
| `jornada_conteo` | jornada_id, producto_id, cantidad_apta, cantidad_cuarentena, cantidad_no_apta, contado_por, contado_at |
| `jornada_caja_conteo` | jornada_id, efectivo_fisico_entregado, contado_por, contado_at, observaciones; un único conteo final versionado o con ajustes auditables |
| `talonarios` | serie, numero_desde, numero_hasta, asignado_a, estado, fecha_asignacion |
| `notas_talonario` | talonario_id, numero, jornada_id, estado (`utilizada`/`anulada`/`justificada`), venta_id nullable, motivo, registrado_por |
| `ventas` | jornada_id, cliente_id, origen (digital/papel), serie_talonario, numero_nota, total, estado, idempotency_key |
| `venta_pagos` | venta_id, medio (efectivo/transferencia/a_cuenta; otros pendientes), importe, referencia, estado (`declarada`/`verificada` para transferencias), verificado_por, verificado_at |
| `retiros_efectivo` | jornada_id, importe, entregado_por, recibido_por, motivo, ocurrido_at_declarado, confirmado_entrega_at, confirmado_recepcion_at, estado, idempotency_key |
| `gastos_ruta` | jornada_id, importe, motivo, comprobante, autorizado_por, estado, fecha |
| `venta_items` | venta_id, producto_id, cantidad, precio_unitario, subtotal |
| `devoluciones` | jornada_id, venta_id (nullable), cliente_id, producto_id, cantidad, tipo, motivo |
| `rendiciones` | jornada_id, totales históricos, diferencia_mercaderia_valorizada, diferencia_efectivo, diferencia_transferencias_declaradas_vs_verificadas, aprobado_por, aprobado_at, motivo_aprobacion, observaciones |
| `rendicion_items` | rendicion_id, producto_id, cargado, vendido, devuelto, merma, esperado, contado_apto, contado_cuarentena, contado_no_apto, diferencia |
| `auditoria` | usuario, accion, tabla, registro_id, datos_antes, datos_despues, fecha |

Restricciones clave:
- `ventas`: único parcial (`empresa_id`, `serie_talonario`, `numero_nota`) cuando origen = papel; identificador propio e idempotencia para digital.
- `retiros_efectivo`: efecto contable solo después de ambas confirmaciones; importes positivos; idempotencia.
- `venta_pagos`: suma por venta = total confirmado; toda escritura en una transacción.
- `jornadas`: único (`empresa_id`, `camion_id`, `fecha`), incluso cerrada.
- Cantidades registradas en documentos y movimientos: enteros positivos, con dirección representada mediante origen y destino (y operaciones compensatorias auditadas). **Excepción no aprobada:** si se permite stock negativo transitorio, `saldos_stock.cantidad` podrá ser negativa **solo** para ubicación camión en jornada abierta; depósito y cuarentena no podrán ser negativos. No activar esa excepción sin decisión aprobada, implementación transaccional y pruebas de concurrencia.

---

## 9. Roles y permisos confirmados

| Rol | Puede | No puede |
|---|---|---|
| **Dueño** | Visión general; administrar usuarios, clientes, productos, stock, jornadas y rendiciones; autorizar gastos y retiros; confirmar recepción de retiros. | Borrar movimientos confirmados sin reversión auditada. |
| **Encargado** | Operación general; editar y validar clientes; administrar cargas, conteos, cierre con diferencias, gastos y retiros de efectivo. | Administrar roles globales ni borrar historial sin compensación. |
| **Vendedor / Piloto** | Ver su jornada, clientes necesarios; **crear cliente nuevo**, registrar ventas y pagos mixtos; transcribir papel; finalizar ventas (`ventas_finalizadas`); confirmar entrega de retiro de dinero. | Editar ficha de cliente existente, cambiar precios maestros, aprobar su propio conteo/rendición, registrar retiros como receptor autorizado. |

No se crean roles independientes de depósito o administración en Fase 1; esas tareas corresponden al encargado/dueño. La separación vendedor/conteo aplica incluso si una persona posee permisos adicionales: se valida participación real en la jornada.

---

## 10. Seguridad y auditoría

- Supabase Auth con cuentas individuales; membresía, empresa y roles se leen de tablas protegidas, no de `user_metadata` modificable por usuario.
- RLS en todas las tablas expuestas por la API, restringiendo consultas/escrituras simples por empresa, rol y estado. Nunca confiar en controles visuales como única defensa.
- `authenticated` y `anon` **no reciben INSERT, UPDATE ni DELETE directos** sobre libros de movimientos de stock/caja o registros confirmados; registros inmutables y rectificación por asientos compensatorios.
- **ADR-001 — PROPUESTA TÉCNICA PARA APROBAR Y PROBAR:** exponer una RPC pública `SECURITY DEFINER` exclusivamente como puerta de entrada para cada operación privilegiada, con `SET search_path = ''`, referencias a objetos completamente calificadas, `REVOKE EXECUTE ON FUNCTION ... FROM PUBLIC, anon` y `GRANT EXECUTE ... TO authenticated`; invocar lógica interna en esquema privado. La función pública debe validar `auth.uid()`, membresía vigente, `empresa_id` obtenida/verificada del servidor, rol, estado de la jornada, cantidades y permisos sobre cada objeto antes de escribir. Evitar que existan otras rutas con privilegios equivalentes.
- **Importante:** `SECURITY DEFINER` ejecuta con privilegios del propietario y puede evitar RLS. Usar propietario de privilegio mínimo, controlar `search_path`, revisar grants por defecto y realizar pruebas reales desde `anon`, `authenticated` ajeno y roles válidos. No asumir que ubicar un wrapper en `public` lo vuelve seguro por sí solo. No poner la lógica privilegiada libremente ejecutable en un esquema expuesto.
- `SECURITY INVOKER` para lecturas y ediciones ordinarias con grants y RLS apropiados; Edge Functions solo si aparece lógica externa no conveniente en SQL. **No generar migraciones hasta aprobar ADR-001 y pasar pruebas de autorización.**
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

---

## 12. Pruebas obligatorias

No se considera terminado un módulo sin estas pruebas (tests SQL sobre las RPC y/o tests de integración):

**Stock**
- [ ] Cargar un camión descuenta del depósito y suma al camión exactamente lo cargado.
- [ ] No se puede cargar más de lo disponible en depósito.
- [ ] No se puede cargar mercadería en cuarentena.
- [ ] Media pieza: cargar "2 piezas + 1 media" guarda 5; vender 1 media deja 4.
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

**Ventas en papel**
- [ ] Número de nota duplicado en **cualquier jornada de la misma empresa/serie** es rechazado.
- [ ] Salto en la numeración genera aviso.

**Seguridad**
- [ ] Función wrapper `public` rechaza `anon`, usuario sin membresía, usuario de otra empresa y vendedor intentando cerrar jornada o realizar retiros.
- [ ] Revocación efectiva de escrituras directas en ledger; ninguna ruta alternativa puede escribir sin pasar validaciones y auditoría.
- [ ] Un usuario sin rol no ve datos.
- [ ] Ningún rol puede hacer UPDATE/DELETE en movimientos.
- [ ] Un usuario de otra `empresa_id` no ve datos ni puede ejecutar operaciones (test preparado para multiempresa).
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
├── docs/
│   ├── decisions/          ← una decisión por archivo (ADR)
│   ├── incidents/          ← un error por archivo
│   ├── progress-log.md     ← qué se hizo, qué falta, por fecha
│   └── changelog.md        ← historial de versiones entregadas
├── supabase/
│   ├── migrations/
│   └── tests/
└── src/
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
Estado: propuesta | aprobada | reemplazada por NNN
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

---

## 15. Pendientes de definición (NO asumir confirmados)

### Prioridad alta — antes de diseñar tablas/RPC
- [ ] **Confirmación de alcance contractual:** entregas 1A + 1B están propuestas dentro de Fase 1; cliente debe aprobar alcance, precio y fechas revisadas, sin asumir que 30 días bastan.
- [ ] **Venta con stock insuficiente — propuesta:** negativo transitorio solo para camión en jornada abierta, venta marcada `excede_stock` y cierre bloqueado hasta regularización aprobada. Confirmar o corregir.
- [ ] **Anulaciones — propuesta:** vendedor anula sus ventas antes de finalizar, con motivo; luego solo dueño/encargado. Confirmar o corregir.
- [ ] **Descuentos — propuesta:** prohibidos para vendedor en Fase 1. Confirmar o corregir.
- [ ] **ADR-001:** aprobar el patrón de wrapper público `SECURITY DEFINER` y lógica privada, probar revocaciones y permisos de ejecución desde roles reales; no asumir aprobación automática.
- [ ] **Ventas con pagos combinados:** confirmar medios exactos (efectivo, transferencia, débito/QR y/o importe a cuenta); si una misma venta admite saldo impago y cómo se anota en papel.
- [ ] **Alta de clientes por vendedor:** campos mínimos, manejo de duplicados y cuándo el encargado valida ficha y límites de crédito. Confirmado solo que puede **crear**, nunca editar existente.
- [ ] **Talonarios:** por vendedor o camión, serie, numeración, modo de asignación y control de duplicados de venta digital transcripta en papel.
- [ ] **Confirmación doble de retiro con falta de Internet:** cómo documentan entrega física en ese momento y quién regulariza la confirmación digital; no deducir retiro antes de confirmación de ambos.
- [ ] **Gastos de ruta:** tipos, quién solicita, quién autoriza, comprobante, momento y cómo afectan rendición.
- [ ] **Devoluciones por producto:** criterios documentables para clasificación apto/no apto; no asumir que todo retorno está apto por no requerir autorización humana.
- [ ] **Vencimientos — propuesta:** fecha por ingreso con `cantidad_inicial` y alertas orientativas; sin cantidad disponible por ingreso, asignación de salida a partida, FEFO ni trazabilidad. Requiere aprobación comercial.
- [ ] **Precio media pieza:** exactamente mitad o precio especial; reglas de redondeo en dinero.
- [ ] **Fechas:** día operativo y zona horaria del negocio (distinción de UTC para auditoría); corte de jornada.

### Prioridad media — antes de entrega
- [ ] ¿Cómo verificar transferencias en Fase 1: declaración del vendedor, comprobante, o verificación del dueño?
- [ ] ¿Quién maneja eventuales cobros de deudas anteriores y cómo se reflejan? Cuenta corriente integral queda en Fase 2.
- [ ] Cómo valuar faltantes (precio de venta histórico, costo, otro) y procedimiento para decidir responsabilidades sin descuento automático.
- [ ] Cantidad exacta de camiones, usuarios, catálogo y capacitación requerida; disponibilidad de conexión en depósito y rutas.
- [ ] Aclarar y aprobar por escrito la diferencia entre alcance del presupuesto anterior y este Fase 1 revisado.

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
- **Unidad mínima:** unidad en que se guarda el stock (unidad o media pieza).

---

*Historial del documento*
| Versión | Fecha | Cambio |
|---|---|---|
| 0.1 | — | Borrador inicial con alcance amplio. |
| 1.0 | 12/10/2026 | Borrador centrado en control de camiones y venta en papel. |
| 1.1 | 12/10/2026 | Relevamiento del cliente: venta digital con papel contingente; tres roles; alta limitada de clientes; una jornada/camión/día; pagos mixtos; retiros con doble confirmación; gastos autorizados; rendición revisada; proveedores/compras y preventa en Fase 2; dudas abiertas documentadas. |
| 1.2 | 12/10/2026 | Corrección de permisos SQL/RPC, orden 1A/1B, tipos de movimiento y modelo de conteos, talonarios, transferencias, vencimiento por partida recomendado y nuevas pruebas; decisiones de negocio aún pendientes. |
| 1.3 | 12/10/2026 | Correcciones de vencimientos sin saldos por partida; pagos mixtos y retiros diferidos incorporados en 1A; 1B conserva autoventa y retiros en vivo; propuesta ADR-001 para RPC privilegiadas; anulaciones, descuentos y stock negativo acotado pendientes de aprobación. |
| 1.4 | 12/10/2026 | Corrige tabla de alcance, estandariza `finalizar ventas`, prohíbe explícitamente implementar propuestas/ADR no aprobadas y señala la excepción condicional de stock negativo. Añade criterio de pgTAP al ADR-001, sin aprobarlo. |
| 1.5 | 18/10/2026 | **Decisión humana de unidades:** lácteos por **unidad entera**; fiambres por **pieza o media pieza** (canónico entero en medias piezas); **no existe `kg` en Fase 1**. Aclara §2 y §7.1 y marca que el **prototipo legacy** usa `kg` y piezas enteras y **requiere migración** (nuevo requisito en `docs/requirements/migracion-unidades-prototipo.md`). Sin cambios en propuestas no aprobadas; ADR-001 sigue sin aprobar. |
| 1.6 | 18/10/2026 | §7.1: agrega **ejemplo de consistencia categoría/unidad** (`Queso cremoso en bote` → Lácteos/unidad; `Queso cremoso en pieza` → Fiambres/pieza), aclarando que es solo un ejemplo y **no** una regla de nombres; no se admite `Lácteos` + `pieza`. Recoge la **decisión humana aprobada** de separar el producto demo. |
