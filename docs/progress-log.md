---
## 29/10/2026 — ADR-007 aprobada: jornadas y carga de camiones (documental, sin commit)

**Rama:** `docs/adr-007-jornadas-carga` desde `feat/slice-b3-ventas-peso` = `abe38f2240e771b119ac451b64d0c967f089b2b9` (checkpoint B3 parcial, que incluye `BLUEPRINT.md` 2.4). Tarea **sólo documental**: sin cambios de SQL, migraciones, frontend, tests ni configuración de Supabase. ADR-001 no se modificó. Sin commit, push, merge ni deploy.

### Contexto
Cambio de estrategia autorizado: no se desarrollan funcionalidades nuevas en el prototipo `localStorage`; el foco pasa al sistema definitivo con Supabase. Primer bloque operativo: jornadas y carga de camiones.

### Decisiones humanas (29/10/2026)
- Primera carga válida como evento explícito de `abierta → cargada`; cargas incrementales; descarga compensatoria antes de la salida; salida con carga neta positiva.
- No abrir otra jornada para un camión que tenga una sin cerrar; camión activo para abrir y cargar; stock del camión en cero antes de la primera carga.
- **F1:** fecha operativa elegida por dueño o encargado; sólo el día actual o futuras. **Zona horaria operativa: `America/Argentina/Tucuman`.**
- **F2:** vendedor con perfil activo de la misma empresa y rol `dueno`, `encargado` o `vendedor_piloto`; como máximo una jornada por persona y fecha, sin liberarse al cerrar; validado también en reasignaciones. Verificado contra el Blueprint 2.4 y el PRD 0.12: sin contradicción (`BLUEPRINT.md` §9 y `docs/PRD.md` §5 prevén que una persona acumule permisos).
- **F4:** corrección de fecha o camión sólo en `abierta` y sin movimientos, con motivo, idempotente, revalidando todas las condiciones de apertura sobre los valores nuevos y con un historial append-only separado del de reasignaciones. Verificado que no permite eludir la unicidad por camión y fecha.
- Reasignaciones de vendedor con historial append-only propio; una línea por producto activo en cada carga; en este bloque el vendedor sólo lee su jornada.
- **F3** (participación y separación de funciones para el conteo): pendiente para su bloque.

### Cambios
- `docs/decisions/007-jornadas-y-carga-de-camiones.md` (nuevo): ADR-007 v1.0, **APROBADA**, con 24 pruebas normativas.
- `docs/decisions/README.md`: fila de ADR-007 en el índice.
- `BLUEPRINT.md`: §7.4 (tipo `descarga` y nota de `carga`), §7.5 (reglas de apertura, carga y salida), §8 (los dos historiales y la unicidad por vendedor y fecha), §12 (bloque «Jornada: apertura, carga y salida») y §15 («Fechas»: zona horaria resuelta; corte de jornada pendiente).

### Ajustes documentales autorizados (29/10/2026)
- **ADR-007** (sigue v1.0 APROBADA): §2.1.3 deja constancia de la confirmación humana de «día operativo actual» (fecha calendario del negocio calculada en `America/Argentina/Tucuman` a partir de la hora del servidor; el corte especial de jornada sigue pendiente); §5 actualiza las referencias a Blueprint 2.5 y PRD 0.13; §8 agrega que el Blueprint 2.4 se sincronizó en la 2.5 y conserva el PRD 0.12 como fuente de la decisión.
- **`BLUEPRINT.md` 2.4 → 2.5**, fecha 29/10/2026, y fila 2.5 en §17 con el alcance de ADR-007: apertura, vendedor, correcciones, carga incremental, descarga, salida y pruebas normativas.
- **`docs/PRD.md` 0.12 → 0.13** (versión aprobada por el dueño): referencia a Blueprint v2.5 en el encabezado y en §0, pendiente «Fechas» con la zona horaria definida y el corte de jornada pendiente, y fila 0.13 en su historial. Sin cambios de requisitos funcionales.
- ADR-001 sin cambios.

### Pendientes
- **Anexo §18.4 de ADR-001** (P10, P12–P17 para jornadas): sigue **PROPUESTA TÉCNICA NO APROBADA**; requiere revisión independiente y aprobación humana antes de escribir SQL. Debe incluir la RPC de corrección, el bloqueo del vendedor y el de los dos camiones en una corrección.
- F3 / P8 para el bloque de conteo; corte de jornada (§15).

---
## 29/10/2026 — Slice B3 (parcial): GOV-B3-01 resuelto, ADR-006 aprobada y Blueprint sincronizado (sin commit)

**Rama:** `feat/slice-b3-ventas-peso` desde `main` = `e21fe321045fa7f4232477b0bf5b3d24d7b6b3d3`. **Base del cambio:** freeze con patch `1a1bc204171202e5bf043f4465d48e173180ec474c32e131132aaf8ae67e22dd` y manifest `c7c694c1065d4f3f1d1f049ec3e29b1371cacbe460f7dcdee79a5774d703d3bb`. Tarea documental: **sin cambios de código productivo**, SQL, migraciones, Supabase, RPC ni producción. **Se agregó un test normativo en `registroVentas.test.ts`** (caso 4 de ADR-006; ver «Ajustes autorizados»). Sin commit, push, merge ni deploy.

### Hallazgo de gobernanza
**GOV-B3-01:** la regla «una línea por `productoId` en cada venta nueva» (corrección de AUD-B3-01) era una decisión humana registrada sólo en esta bitácora. El freeze ya la implementaba sin una ADR que la respaldara (`AGENTS.md` §3 y §6.5).

### Decisión humana (29/10/2026)
- **ADR-006 — Una línea por producto en cada venta nueva:** **APROBADA** el 29/10/2026. Formaliza la decisión funcional tomada el 28/10/2026 durante AUD-B3-01.
- La regla aplica a `unidad` y `peso`, y también al mismo `productoId` con unidades distintas. No se consolida automáticamente y D-R1 no cambia.
- No se aplica a la lectura histórica: no se migra ni se recalcula nada, y los históricos válidos con líneas repetidas siguen legibles y consumen stock por la suma de sus líneas.
- **Notas de papel:** una nota transcripta como venta nueva también debe cumplir la regla. No se implementa el flujo de notas de papel.
- **Presupuestos:** fuera del alcance; una regla equivalente requiere una decisión separada.
- **ADR-005:** no se modifica. ADR-006 aclara que sus ejemplos con varias líneas no autorizan líneas repetidas del mismo `productoId` en una venta nueva.

### Cambios
- `docs/decisions/006-una-linea-por-producto-en-venta-nueva.md` (nuevo): contexto, decisión, históricos, stock, notas de papel, alternativas descartadas, consecuencias, fuera de alcance y 6 pruebas normativas.
- `docs/decisions/README.md`: fila de ADR-006 en el índice.
- `BLUEPRINT.md` §7.5: viñeta «Una línea por producto (ADR-006)».
- `BLUEPRINT.md` §12: bloque «Ventas: una línea por producto (ADR-006)» con los 6 casos normativos.
- La versión, la fecha y el historial (§17) del Blueprint se actualizaron después, por ajuste autorizado (ver «Ajustes autorizados»).

### Estado
- **GOV-B3-01:** resuelto.
- **AUD-B3-01:** mitigado dentro de una venta. Cobertura de los casos normativos de ADR-006 §6: los casos 1, 2, 3, 5 y 6 con tests existentes, sin cambios; para el caso 4 se agregó un test en la frontera:
  - casos 1, 2, 3, 5 y 6: en la frontera real (`registroVentas.test.ts`, bloque «unicidad de producto por venta nueva»), con 0 escrituras en los rechazos;
  - caso 4 (mismo `productoId` con unidades distintas): cubierto a nivel de predicado (`venta.test.ts`, `tiene_productos_repetidos`, se conserva) y, por ajuste autorizado, también en la frontera (ver «Ajustes autorizados»).
- **Fragmentación entre ventas distintas:** sigue como riesgo y decisión de negocio o de proceso pendiente (ADR-006 §4).
- Siguen abiertos SEC-B3-02 (cliente, antes del cierre de B3), SEC-B3-01 (precio, BLUEPRINT §7.5 sin aprobar) y la deuda conocida SEC-B3-03 a SEC-B3-06.

### Ajustes autorizados (29/10/2026)
- **`BLUEPRINT.md` 2.4 sincronizado:** versión 2.3 → 2.4, fecha 29/10/2026 y fila 2.4 en §17 (ADR-006 aprobada, unicidad de `productoId` en ventas nuevas, históricos no afectados y pruebas normativas en §12). No cambió ninguna otra sección.
- **ADR-006, caso normativo 4, cubierto en la frontera:** test nuevo en `registroVentas.test.ts` (bloque «unicidad de producto por venta nueva»). Una venta con dos líneas del mismo `productoId` (una `peso`, otra `unidad`) se rechaza con `MENSAJE_VENTA_MIXTA_NO_HABILITADA`, sin `getItem` ni `setItem`, con el storage crudo intacto y sin llamar a `alGuardar`. La ADR exige el rechazo, no un mensaje concreto. **No se cambió el orden de los guards ni ningún código productivo.**
- **GOV-B3-01: completamente resuelto.**

### Pendientes
- Freeze nuevo y reauditoría acotada de Codex y OpenCode sobre su hash, con foco en la coherencia ADR-006 ↔ Blueprint ↔ código ↔ tests.
- Commit sólo con autorización humana. Sin push, PR, merge ni deploy.

---
## 28/10/2026 — Slice B3 (parcial): corrección de AUD-B3-01, una línea por producto en cada venta nueva (sin commit)

**Rama:** `feat/slice-b3-ventas-peso` desde `main` = `e21fe321045fa7f4232477b0bf5b3d24d7b6b3d3`. **Base del cambio:** freeze `4f63f4c0cd86e27e809e5a1409b706d06e388c6e7a67e7ab5abc862b7ae27e19`; antes de modificar nada se verificó que el árbol coincidiera con ese freeze. Sin SQL, sin migraciones, sin Supabase, sin RPC, sin RLS y sin producción. Sin commit, push, merge ni deploy.

### Hallazgo
**AUD-B3-01 (HIGH, reproducido)** en la revisión adversarial del freeze anterior. D-R1 redondea **por línea** y la frontera aceptaba varias líneas del mismo producto. Partiendo una venta, el total se podía manipular sin que ninguna validación lo detectara, con el stock descontado completo:

| Venta | Total aceptado |
|---|---|
| 1 kg a $499,99/kg en una línea | $500 |
| la misma venta en 1000 líneas de 1 g | **$0** |
| 1 kg a $500/kg en 1000 líneas de 1 g | **$1000** |

La UI no lo producía, pero sí una llamada directa a la frontera.

### Decisión humana
Una venta **nueva** no puede tener más de una línea con el mismo `productoId`, sea cual sea su unidad de medida. La fórmula D-R1 no cambia.

### Corrección
- **`domain/venta.ts`:**
  - `tiene_productos_repetidos(items)`: no lanza error con ítems malformados, porque sólo cuenta los `productoId` que son enteros seguros;
  - `MENSAJE_VENTA_PRODUCTO_REPETIDO`: «Una venta no puede tener más de una línea del mismo producto. Unificá la cantidad en una sola línea.».
- **`domain/validacion.ts`:** `venta_nueva_valida` exige `!tiene_productos_repetidos(venta.items)`. `venta_valida` e `item_valido`, que es la lectura histórica, **no** cambian: una venta histórica con líneas repetidas sigue siendo legible.
- **`hooks/registroVentas.ts`:** el guard corre después del rechazo de venta mixta y **antes de cualquier lectura**, y devuelve el mensaje específico. `venta_nueva_valida` lo vuelve a exigir como defensa en profundidad.
- **Sin cambios:** `validar_stock_venta` conserva la agrupación segura por producto, porque también se defiende de entradas directas. D-R1 y los mensajes ajenos al hallazgo tampoco cambiaron.

### Tests
- **`venta.test.ts`:**
  - `tiene_productos_repetidos`, 5 casos: unidad, peso, mismo `productoId` con distinta unidad, productos distintos e ítems malformados;
  - histórico con líneas repetidas: `venta_valida` lo acepta y `venta_nueva_valida` lo rechaza;
  - frontera L: dos líneas del mismo producto devuelven el mensaje específico sin leer ningún ledger.
- **`registroVentas.test.ts`:** el bloque «líneas duplicadas» pasó a ser «unicidad de producto por venta nueva». Cubre:
  - 1000 g a $499,99/kg en una línea: se acepta con total $500;
  - 1000 líneas de 1 g: se rechazan con 0 lecturas y 0 escrituras;
  - dos líneas `peso` y dos líneas `unidad` con stock suficiente: se rechazan;
  - dos productos distintos: se aceptan;
  - venta histórica con líneas repetidas: sigue legible y su consumo cuenta para el stock (el exacto se acepta y +1 se rechaza).

  El test de overflow del pedido nuevo usa ahora una sola línea, porque dos líneas del mismo producto ya se rechazan antes.
- **Se mantienen:** los 18 casos de `validar_stock_venta` de `movimientos.test.ts`, incluidas las sumas seguras con líneas repetidas y el overflow del pedido; los casos de D-R1 de `precios.test.ts`; y la regresión de AUD-001.
- **Sondeo de auditoría** sobre el código real, ejecutado fuera del repo: la venta de 1000 × 1 g, que antes guardaba $0 o $1000, ahora se rechaza sin escribir.

### Verificación (repo real, desde `apps/web/`)
| Verificación | Resultado |
|---|---|
| Focalizados (`registroVentas`, `venta`, `movimientos`, `precios`, `persistencia`) | 5 archivos, **499/499** |
| `npm test` | **31 archivos, 1167/1167** |
| `npx tsc -b` | 0 |
| `npm run lint` | 0 |
| `npx playwright test` | **96/96** |
| Detector de ciclos de importación | sin ciclos |
| `git diff --check` | 0 |

- Búsquedas en `src`: 0 llamadas a `registrarVenta*` con validador o `() => null`; 0 apariciones de `ventasActuales`; una única `registrarVentaPersistida`.

### Riesgos residuales
- **Fragmentación entre ventas:** partir la mercadería en muchas **ventas** de 1 g sigue siendo posible. Es una consecuencia del redondeo por documento de D-R1 y corresponde a una decisión de negocio o de proceso, no a esta corrección.
- **Hallazgos que siguen abiertos:**
  - AUD-B3-02 / SEC-B3-02 (cliente): tarea separada antes del cierre de B3;
  - AUD-B3-03 / SEC-B3-01 (precio): BLUEPRINT §7.5 sin aprobar;
  - AUD-B3-04 (campos desconocidos persistidos, reproducido);
  - AUD-B3-05 (concurrencia entre pestañas: venta de más y pérdida de ventas; el comentario del código no nombra la pérdida);
  - AUD-B3-06 (carga contradictoria en `validar_stock_movimiento`);
  - AUD-B3-07 (debilidades de tests);
  - AUD-B3-08 a AUD-B3-10 (INFO).
- La revisión adversarial del freeze anterior la hizo el implementador. **No reemplaza** la auditoría independiente de Codex y OpenCode, que debe hacerse sobre el freeze nuevo.

---
## 28/10/2026 — Slice B3 (parcial): ventas por peso con D-R1, separación lectura histórica / escritura nueva y corrección de AUD-001 (sin commit)

**Rama:** `feat/slice-b3-ventas-peso` desde `main` = `e21fe321045fa7f4232477b0bf5b3d24d7b6b3d3`. **Alcance:** dominio de precios y ventas, frontera de persistencia frontend/localStorage de Ventas, Autoventa y sus tests. Sin SQL, sin migraciones, sin Supabase, sin RPC, sin RLS y sin producción. No se tocaron Blueprint, PRD, ADR ni `AGENTS.md`. Sin commit, push, merge ni deploy.

**Estado:** AUD-001 **corregido**, con revisión de seguridad completada. **B3 todavía no está cerrado**: queda SEC-B3-02 como tarea separada y el resto del trabajo funcional (por ejemplo, la UI de venta por peso en Autoventa).

### D-R1 y separación lectura histórica / escritura nueva (ADR-005 §2.3.3 y §2.3.4)
- **`precios.ts`:** `importe_linea_peso_centavos` e `importe_linea_peso` calculan el importe `peso` con BigInt, con un único redondeo al peso entero y empate 0,50 hacia arriba (D-R1).
- **`venta.ts`:**
  - `importe_linea_vigente` aplica D-R1 a `peso` y `cantidad × precio` a `unidad`;
  - `construirDetalleVenta` ya no bloquea `peso`;
  - `construirItemsVenta` rechaza la venta mixta `unidad` + `peso` con `MENSAJE_VENTA_MIXTA_NO_HABILITADA`;
  - `es_venta_mixta` no lanza error con elementos `null`.
- **`validacion.ts`:**
  - **Lectura e histórico** (`item_valido`, `total_coincide`, `venta_valida`): valida la estructura y que `total` sea igual a la suma de los subtotales **almacenados**, **sin recalcular** `cantidad × precio`. Un subtotal `peso` debe ser entero en pesos. La venta mixta se rechaza.
  - **Escritura nueva** (`venta_nueva_valida`): exige además al menos un ítem, que no sea mixta y que cada subtotal coincida con la regla vigente (`subtotal_coincide` → `importe_linea_vigente`).

### AUD-001: reproducido y corregido
- **Hallazgo:** `registrarVentaPersistida(venta, validar)` delegaba toda la validación de stock en un callback que aportaba quien la llamaba. La lógica real vivía en una closure de `Autoventa.tsx`.
- **Reproducción:** un PoC temporal sobre la frontera real persistió una venta de 2 unidades con 1 cargada usando `validar = () => null`, incluso sin jornadas ni movimientos en storage. Resultado: 2/2 tests pasados, o sea, bypass confirmado.
- **Segundo bypass encontrado en el diseño:** la closure comparaba cada línea por separado, así que dos líneas del mismo producto podían superar lo cargado.
- **Corrección** (en 4 pasos chicos, cada uno verificado):
  1. `hooks/ventasStorage.ts` (nuevo): la lectura de ventas se movió sin cambios funcionales, a un módulo hoja que rompe el ciclo `useVentas ↔ useMovimientos`. `useVentas` la re-exporta y `useMovimientos` la importa desde ahí.
  2. `domain/movimientos.ts`: `validar_stock_venta`, con mensajes propios de Ventas (`MENSAJE_VENTA_CARGA_INCONSISTENTE`, `MENSAJE_VENTA_SALIDAS_SUPERAN_CARGA`). Reutiliza `salidas_de_jornada` y la suma segura, y hace esto:
     - rechaza una carga contradictoria en **toda** la carga;
     - exige que el producto esté cargado y con la misma unidad;
     - rechaza unidades históricas incompatibles, salidas históricas de productos no cargados y saldos históricos negativos;
     - **agrupa las líneas nuevas por producto** antes de comparar, en unidades o gramos exactos, sin `Math.max`, tolerancias ni redondeos.

     `revalidar_jornada_para_operacion` acepta `Pick<Jornada, "id" | "camionId">`. `validar_stock_movimiento` no se modificó.
  3. `hooks/registroVentas.ts` (nuevo): es la frontera autoritativa. Usa lectoras reales fijas y privadas y no acepta ningún callback de validación. Hace, en orden:
     1. snapshot plano de la venta (`JSON.parse(JSON.stringify(...))`);
     2. rechazo de venta mixta;
     3. `venta_nueva_valida`;
     4. relectura de Ventas y control de ID duplicado;
     5. relectura de la jornada de `venta.jornadaId` (debe existir, ser del mismo camión y estar abierta);
     6. relectura de Movimientos;
     7. `validar_stock_venta`;
     8. **una sola** escritura.

     `alGuardar` se invoca sólo después de una escritura exitosa y no participa en ninguna decisión.
  4. `useVentas.registrarVenta(venta)` usa la frontera nueva. Se eliminaron las implementaciones viejas, y `Autoventa.tsx` ya no tiene la closure de stock: llama sólo `registrarVenta(venta)`.

  El PoC temporal se eliminó después de convertir sus dos escenarios en regresiones con expectativa segura en `registroVentas.test.ts`.

### Tests
- `registroVentas.test.ts` (nuevo, 33 casos contra la frontera real sobre `localStorage` simulado). En todo rechazo verifica 0 escrituras y el contenido crudo intacto; en todo éxito, exactamente 1 escritura. Cubre:
  - regresión de AUD-001;
  - stock exacto y +1 unidad / +1 g;
  - líneas duplicadas;
  - venta y merma registradas después del render;
  - saldo histórico negativo y carga contradictoria;
  - overflow;
  - jornada inexistente, cerrada o de otro camión;
  - storage corrupto;
  - venta duplicada, mixta y vacía;
  - snapshot con un getter cambiante;
  - `alGuardar` y `setItem` que fallan.
- `movimientos.test.ts`: 18 casos de `validar_stock_venta`.
- `venta.test.ts` y `persistencia.test.ts`: adaptados a la separación histórico / nuevo y a la frontera sin callback. No se debilitó ninguna expectativa negativa.
- `tests/autoventa-venta-unidad.spec.ts` (nuevo): E2E positivo. Registra 2 Yogur desde la UI, verifica 1 venta persistida, Jornadas y Movimientos intactos, la venta visible en el historial y que sigue persistida después de recargar.

### Verificación (repo real, desde `apps/web/`)
| Verificación | Resultado |
|---|---|
| `npm test` | **31 archivos, 1157/1157** |
| `npx tsc -b` | 0 |
| `npm run lint` | 0 |
| `npx playwright test` | **96/96** |
| Detector de ciclos de importación (script de solo lectura) | sin ciclos |
| `git diff --check` | 0 |

- Búsquedas en `src`: 0 llamadas a `registrarVenta*` con validador o `() => null`; 0 apariciones de `ventasActuales`; una única implementación de `registrarVentaPersistida` (`registroVentas.ts`). La única otra escritura de la clave de ventas es el reinicio de demo de `ConfiguracionDemo`, sólo para el dueño.

### Revisión de seguridad focalizada (B3/AUD-001)
Sin hallazgos CRITICAL ni HIGH. Hallazgos registrados según la decisión humana:
- **SEC-B3-01 (MEDIUM, REQUIERE DECISIÓN):** la frontera no compara `precioUnitario` con el `precioReferencia` de la jornada. Depende de BLUEPRINT §7.5, que es una PROPUESTA NO APROBADA. No se implementa en B3/AUD-001.
- **SEC-B3-02 (MEDIUM, tarea separada):** las reglas del cliente (que exista y esté activo, y que una venta a cuenta corriente exija `condicionPago === "cuenta_corriente"`) se validan sólo en la UI de Autoventa. **Pendiente antes de declarar B3 cerrado.**
- **SEC-B3-03 (LOW):** limitación de concurrencia de `localStorage`. Entre la relectura y el `setItem`, otra pestaña puede intercalarse: puede haber venta de más o **pérdida** de una venta de otra pestaña al reescribir el ledger. La atomicidad real queda para la futura RPC o transacción.
- **SEC-B3-04 (LOW):** el snapshot conserva campos desconocidos de la venta y se persisten sin validar. Hoy ningún consumidor los lee.
- **SEC-B3-05 (LOW, hallazgo lateral):** `validar_stock_movimiento` no detecta una carga contradictoria en productos que no participan del movimiento. No se corrigió.
- **SEC-B3-06 (LOW):** huecos menores de cobertura:
  - Proxy, BigInt y referencias cíclicas del snapshot sin probar en la frontera;
  - cantidad mayor que `MAX_SAFE_INTEGER` y salida histórica de un producto no cargado sin probar en la frontera;
  - aserciones genéricas en los tests de storage corrupto;
  - selector débil en el E2E positivo;
  - sin E2E de stock consumido después del montaje.
- **INFO-07 a INFO-10:** sólo registrados:
  - reinicio de demo sólo para el dueño;
  - texto visible `MENSAJE_VENTA_INVALIDA` que menciona ADR-003;
  - `fecha` e `id` sin restricción adicional;
  - Rendición bloquea las filas `peso` hasta B4.

### Pendientes
- Freeze y hash del diff exacto, y revisión independiente de Codex y OpenCode sobre ese hash.
- Commit sólo con autorización humana. Sin push, PR, merge ni deploy.
- SEC-B3-02 como tarea propia antes del cierre de B3; SEC-B3-01 sigue en espera de decisión del Blueprint; SEC-B3-03 a SEC-B3-06 quedan como deuda conocida.
- Mensajes visibles que cambiaron con la frontera nueva, sin cambio de reglas:
  - «El producto X no está cargado en el camión.» → «X no está cargado en el camión.»;
  - «Stock insuficiente de X» → «Stock insuficiente de X.»;
  - desaparece «Cantidad inválida de X», porque esos casos los rechaza antes `venta_nueva_valida`.

---
## 28/10/2026 — Slice B2: auditoría Codex del freeze, fixes M-1/M-2 y security re-review (sin commit)

**Rama:** `feat/slice-b2-jornadas-movimientos-peso` desde `main` = `e698d4e66dcf3c53fcd2d71bf11e4312143fdecc`. **Alcance:** fronteras de persistencia frontend/localStorage de Jornadas y Movimientos y sus tests. Sin SQL, sin migraciones, sin Supabase, sin RPC, sin RLS y sin producción. No se tocaron Blueprint, PRD, ADR ni `AGENTS.md`. Sin commit hasta la autorización humana.

### Freeze anterior rechazado
El freeze `3150a58a54820a286975727b9d8ec192a75caecc52f11804f1c10893546407ea` quedó **rechazado** por la auditoría de Codex. Se conserva sólo como referencia histórica y no identifica el artefacto final de B2.

### Hallazgos de Codex
- **M-1:** `crearJornadaPersistida`, expuesta por el hook como `crearJornada`, era una segunda ruta de alta de jornadas que no validaba stock. Persistía una preparación que `crearPreparacionPersistida` rechazaba, por ejemplo con stock + 1 g.
- **M-2:** `registrarMovimientoPersistido(movimiento, validar, alGuardar?)` recibía la validación como callback. Con `registrarMovimientoPersistido(m, () => null)` se persistía un movimiento con jornada inexistente, camión ajeno y una cantidad muy superior a la carga.

Ambos bypasses se reprodujeron sobre el código previo al fix con un PoC temporal en una copia aislada: **2/2** tests pasados, es decir, los dos bypasses confirmados. El PoC no forma parte del cambio.

### Fixes
- **M-1, `useJornadas.ts`:** se eliminaron `crearJornadaPersistida` y `crearJornada`, del hook y de su objeto retornado. `crearPreparacionPersistida` queda como única frontera de alta, con la validación de stock en gramos exactos. `esPreparacionNueva` conserva su cuerpo y `confirmarSalidaPersistida` y `cerrarJornadaPersistida` no cambiaron.
- **M-2, `useMovimientos.ts`:**
  - `registrarMovimientoPersistido(movimiento, jornada)` ejecuta internamente `validarMovimientoConLecturas`: no acepta validador ni callback de escritura, y escribe una sola vez y sólo si todo pasa;
  - `registrarMovimientoOperacion` quedó pura: valida y devuelve `{ ok, movimientos } | { ok: false, error }`, sin escrituras;
  - el hook expone `registrarMovimiento(movimiento, jornada)`.
- **`Movimientos.tsx`:** ya no importa `validarMovimientoConLecturas` ni construye un callback; llama `registrarMovimiento(movimiento, jornada)`.

### Tests
- `domain/movimientos.test.ts` y `persistencia.test.ts`: los tests de `registrarMovimientoOperacion` verifican el resultado explícito, sin mock de guardado.
- `persistencia.test.ts`: los tests de alta pasaron a `crearPreparacionPersistida`. Cubren:
  - stock exacto, que persiste;
  - **+1 g**, que se rechaza con 0 escrituras;
  - `abierta`, `cerrada`, preparación con `fechaSalida` y preparación con `cierre`, que se rechazan;
  - duplicados;
  - 7 variantes de storage corrupto;
  - historial que agrega al final.

  La frontera de movimientos se prueba contra una jornada sembrada en storage.
- `registrarMovimiento.test.ts`: el helper llama directo a la frontera. Regresivos nuevos:
  - **jornada del render inexistente** en storage;
  - escenario del PoC (**`jornadaId="no-existe"`, `camionId=999`, `9_000_000` g**);
  - control positivo con exactamente 1 `setItem`.

  Los negativos verifican 0 `setItem` y raw intacto.
- Afectados: 391 → 397. Global: 1060 → 1066.

### Verificación (repo real, desde `apps/web/`)
| Verificación | Resultado |
|---|---|
| Vitest de los 4 archivos afectados | 4 archivos, **397/397** |
| `npx vitest run` | **30 archivos, 1066/1066** |
| `npx tsc -b` | 0 |
| `npx eslint .` | 0 |
| `npx playwright test` | **95/95** |
| `npm run build` | 0; sólo el aviso que ya existía de chunk > 500 kB |
| `git diff --check` (raíz) | 0 |

- Greps en `src`: 0 resultados para `crearJornadaPersistida` o `crearJornada`; 0 llamadas a `registrarMovimientoPersistido` con un callback.
- Los fixes se validaron primero en una copia aislada de `apps/web` en el scratchpad y se copiaron al repo byte a byte. Los 6 archivos se verificaron con `cmp` y SHA256 contra las previews aprobadas.

### Checkpoint pre-security y revisiones
- **Checkpoint pre-security** (manifest SHA256 de los 18 paths B2): `f7a0fc850514e23b5566264b53209744bbd10a9759f1f2e74be9320fddc8c835`. No es el freeze final.
- **Security re-review independiente** sobre ese checkpoint: **APPROVED**, sin hallazgos.
- **Segunda revisión independiente (OpenCode)** sobre ese checkpoint: **APPROVED**, sin hallazgos.
- Ninguna de las dos revisiones modificó archivos.

### Pendientes
- Generar el freeze y el hash final después de esta actualización documental. Esta entrada cambia `docs/progress-log.md`, así que el checkpoint pre-security ya no identifica el artefacto final.
- Auditoría final de Codex y OpenCode sobre ese hash.
- Commit sólo con autorización humana.
- Sin push, PR, merge ni deploy todavía.
- Se mantienen las deudas de las entradas anteriores de B2 (BAJO-2, BAJO-3, B3, B4 y B5). La deuda «`crearJornadaPersistida` no valida stock» queda **resuelta** por M-1.

---
## 27/10/2026 — Slice B2: security review de las fronteras de Jornadas y Movimientos y fixes (sin commit)

**Rama:** `feat/slice-b2-jornadas-movimientos-peso` desde `main` = `e698d4e66dcf3c53fcd2d71bf11e4312143fdecc`. **Alcance:** fronteras de persistencia frontend/localStorage de Jornadas y Movimientos y sus tests. Sin SQL, sin migraciones, sin Supabase, sin RPC, sin RLS y sin producción. No se tocaron Blueprint, PRD, ADR ni `AGENTS.md`. Sin commit hasta la revisión humana.

### Security review B2: resultado inicial `BLOQUEADO`
La review cubrió todo el diff B2, con foco en `crearPreparacionPersistida`, `crearJornadaPersistida`, `confirmarSalidaPersistida`, `cerrarJornadaPersistida`, `calcularStockReservado`, `validarStockPreparacion`, `registrarMovimientoOperacion`, `validarMovimientoConLecturas`, `validar_stock_movimiento` y `movimiento_valido`. Cada hallazgo se reprodujo con un test de sondeo en una copia aislada.

### Hallazgos corregidos
- **ALTO-1:** `crearJornadaPersistida` y `crearPreparacionPersistida` permitían altas fuera de `preparacion`, incluida una jornada `cerrada` con peso. Eso salteaba el bloqueo del cierre con peso hasta B4. Es una regresión del guard de H-1 de B1.
- **MEDIO-1:** `crearPreparacionPersistida` podía escribir una jornada que su propio lector rechazaba, por ejemplo con cantidad `0` o un precio inválido. El storage de Jornadas quedaba corrupto y bloqueaba toda la operación.
- **MEDIO-2:** las salidas históricas con una unidad distinta de la carga se sumaban como si fueran compatibles. Por ejemplo, una merma histórica `unidad` de 5 sobre una carga `peso` contaba como 5 g.
- **BAJO-1:** el movimiento no estaba atado explícitamente al `jornadaId` y al `camionId` de la jornada revalidada. Podía persistirse un movimiento huérfano validado contra otra carga.

### Fixes
- `useJornadas.ts`:
  - nuevo `esPreparacionNueva`: exige `jornadaValida`, estado `preparacion`, `fechaSalida === null` y que no haya cierre;
  - `crearPreparacionPersistida` lo aplica antes de cualquier lectura o escritura y devuelve `MENSAJE_PREPARACION_INVALIDA`;
  - `crearJornadaPersistida` aplica el mismo guard y devuelve `null`.
- `domain/movimientos.ts`: `validar_stock_movimiento` bloquea con `MENSAJE_SALIDAS_SUPERAN_CARGA` cualquier salida histórica de la jornada con una unidad incompatible, antes de sumar. Revisa ventas, mermas y entregados de cambios. Las ventas ahora llevan `unidadMedida` (`VentaConItemsConUnidad`).
- `useMovimientos.ts`: `validarMovimientoConLecturas` exige el mismo `jornadaId` y `camionId` que la jornada revalidada. Si no coinciden, devuelve `MENSAJE_MOVIMIENTO_OTRA_JORNADA`.

### Tests y evidencia
- **+28 tests** en `crearPreparacion.test.ts` (+9), `persistencia.test.ts` (+2), `movimientos.test.ts` (+7) y `registrarMovimiento.test.ts` (+10). Los negativos verifican 0 `setItem` y raw intacto.
- En `movimientos.test.ts` se agregó `unidadMedida: "unidad"` a dos fixtures de ventas. El test «ventas previas mayores que lo cargado» pasó a un producto `unidad`, porque las ventas por peso son de B3; la expectativa no cambió.
- **Prueba de mutación:** contra el código sin fix, los 23 tests negativos fallan y los 5 controles pasan.

| Verificación (desde `apps/web/`) | Resultado |
|---|---|
| Vitest de los 4 archivos afectados | 4 archivos, **391/391** |
| `npx vitest run` | **30 archivos, 1060/1060** (antes 1032) |
| `npx playwright test` | **95/95**, `retries=0` en local |
| `npx tsc -b` | 0 |
| `npx eslint .` | 0 |
| `npm run build` | 0; sólo el aviso que ya existía de chunk > 500 kB |
| `git diff --check` | 0 |

### Integridad
Los 7 archivos aplicados (`useJornadas.ts`, `useMovimientos.ts`, `domain/movimientos.ts` y los 4 archivos de tests) se verificaron con SHA256 y `cmp` contra las previews aprobadas, antes y después de la copia.

### Deudas
- **BAJO-2:** la unidad de una devolución, o del lado devuelto de un cambio, sale del catálogo del render y no se relee en la frontera. Queda para B4.
- **BAJO-3:** el estado del camión no se relee en la frontera de preparación ni en la confirmación de salida. Queda para B4.
- `crearJornadaPersistida` sigue sin validar stock y no tiene caller productivo.
- La security review cubre esta capa local. La review de seguridad de backend (SQL, RPC, RLS) sigue pendiente para la fase en la que se implemente.

---
## 27/10/2026 — Modelo por peso, Slice B2: Jornadas y Movimientos con peso en la capa frontend/localStorage transitoria (sin commit)

**Rama:** `feat/slice-b2-jornadas-movimientos-peso` desde `main` = `e698d4e66dcf3c53fcd2d71bf11e4312143fdecc` (merge del PR #28, B1). **Alcance:** capa frontend/localStorage transitoria y sus tests. Sin migraciones, sin SQL, sin Supabase, sin staging y sin producción. Las claves siguen en `_demo_v5` (sin rotación) y D-R4 queda intacta. Sin commit hasta la revisión humana.

### Decisiones humanas aplicadas
- **P-B2-1:** no se valoriza ninguna carga con `peso`. Si la selección o la jornada tiene cualquier ítem `peso`, el total estimado es `null` y se muestra «Sin valorizar», sin subtotal parcial de las líneas `unidad`. Ninguna línea `peso` pasa por la valorización y D-R1 queda para B3.
- **P-B2-2:** una jornada con `peso` se prepara y se confirma (`preparacion` → `abierta`). El cierre, la rendición y los retornos con `peso` siguen bloqueados hasta B4 (`cerrarJornadaPersistida` conserva el guard). Una jornada con peso puede quedar abierta hasta B4; no se agregó ninguna transición para liberar el camión.
- **P-B2-3:** se habilitan merma y devolución `peso` y el cambio `peso ↔ peso`, con una cantidad propia en cada lado y sin conversión. Los cambios `unidad ↔ peso` y `peso ↔ unidad` **no están aprobados** y fallan cerrado con `MENSAJE_CAMBIO_MIXTO_NO_HABILITADO`.
- **Inversión de H-1:** la protección de B1 (auditoría de `8ff5bef`) se invierte deliberadamente sólo en creación, preparación y salida. Los tests de H-1 se reescribieron con la expectativa de B2, no se borraron.

### Qué se hizo (por paso)
- **Paso 2, dominio de movimientos:**
  - `cantidad_movimiento_desde_entrada` acepta `peso` con `kg_a_gramos` (coma decimal, hasta 3 decimales, punto rechazado, BigInt, sin float);
  - `es_cambio_mixto` y `movimiento_valido` rechazan el cambio mixto también al leer el storage.
- **Paso 3, persistencia de jornadas (`useJornadas.ts`):**
  - se levanta el guard `peso` en `crearPreparacionPersistida`, `crearJornadaPersistida` y `confirmarSalidaPersistida`;
  - el cálculo de stock se movió desde la página a funciones puras exportadas: `calcularStockReservado` y `validarStockPreparacion`;
  - la frontera relee Jornadas, Retornos y **Productos** al persistir (TOCTOU de catálogo, decisión humana);
  - las sumas usan `sumar_cantidades_seguras`;
  - el descuento de retornos falla cerrado si un ítem es inconsistente o si lo aprobado de una jornada supera lo cargado: nunca queda un reservado negativo;
  - se eliminó el `Math.max` que ocultaba inconsistencias.
- **Paso 4, UI de Jornadas:**
  - `pages/jornadas_preparacion.ts` es un módulo puro nuevo: `entrada_carga`, `disponibilidad_carga`, `valor_estimado_carga`, `precio_item_valido` y `atributos_input_carga`;
  - input `peso` con `type="text"`, `inputMode="decimal"` y `0,000`; `unidad` conserva su input numérico anterior;
  - «Disponible» en kg con 3 decimales; si el disponible es negativo o no se puede calcular, la carga se deshabilita;
  - «Sin valorizar» según P-B2-1, y «Confirmar salida» se habilita con peso.
- **Paso 5, Movimientos:**
  - se levanta el guard de B1 en la frontera y en la UI;
  - el cambio mixto se rechaza antes de cualquier efecto, con el mensaje específico;
  - el callback de validación con lecturas frescas se movió a `validarMovimientoConLecturas`;
  - `validar_stock_movimiento` exige la misma `unidadMedida` que la carga en todos los lados y falla cerrado si las salidas existentes superan lo cargado. `disponibilidad_de_jornada` conserva su `Math.max` sólo para presentación;
  - `pages/movimientos_formulario.ts` agrupa los atributos de UX del input.
- **Paso 6, E2E:**
  - `h1-confirmar-salida-peso.spec.ts` reescrito: invertido para B2 y con la regresión `unidad`;
  - nuevos `b2-jornadas-peso.spec.ts` (3 tests) y `b2-movimientos-peso.spec.ts` (6 tests).

### Archivos
- **Modificados:** `src/domain/movimientos.ts`, `src/domain/movimientos.test.ts`, `src/hooks/useJornadas.ts`, `src/hooks/crearPreparacion.test.ts`, `src/hooks/persistencia.test.ts`, `src/hooks/useMovimientos.ts`, `src/pages/Jornadas.tsx`, `src/pages/Jornadas.test.ts`, `src/pages/Movimientos.tsx`, `tests/h1-confirmar-salida-peso.spec.ts` y `docs/progress-log.md`.
- **Nuevos:** `src/pages/jornadas_preparacion.ts`, `src/pages/jornadas_preparacion.test.ts`, `src/pages/movimientos_formulario.ts`, `src/pages/movimientos_formulario.test.ts`, `src/hooks/registrarMovimiento.test.ts`, `tests/b2-jornadas-peso.spec.ts` y `tests/b2-movimientos-peso.spec.ts`.

### Verificación (local, desde `apps/web/`)
| Comando | Resultado |
|---|---|
| `npx playwright test` | `PLAYWRIGHT_EXIT=0`; **95/95** (1 setup + 94; antes de B2: 86); 0 retries, sin flaky |
| `npx vitest run` | `VITEST_EXIT=0`; **30 archivos, 1032/1032** (B1: 27 / 891) |
| `npx tsc -b` | `TYPECHECK_EXIT=0` |
| `npx eslint .` | `LINT_EXIT=0` |
| `npm run build` | `BUILD_EXIT=0`; sólo el aviso preexistente de chunk > 500 kB (`index-Ct-Znq6l.js`, 652,74 kB) |
| `git diff --check` (raíz) | exit 0, sin salida |

- Cada paso se validó primero en una copia aislada de `apps/web` en el scratchpad y se aplicó al repo byte a byte, verificado con `cmp` y SHA256. Los 3 specs E2E se corrieron antes de aplicarlos con una config de Playwright aislada: 13/13 en dos corridas con `retries: 0`.
- Casos clave cubiertos:
  - `1,250` → 1250 g, `28,680` → 28680 g, `1,005` → 1005 g y `0,001` → 1 g;
  - se rechazan punto decimal, más de 3 decimales, cero, negativos y texto;
  - 1 g de más se rechaza en Jornadas y en Movimientos;
  - TOCTOU de productos, jornadas, ventas y movimientos;
  - corrupción y overflow fallan cerrado, sin escritura y con el raw intacto;
  - el cierre con peso sigue bloqueado.

### Riesgos y deudas
- **Pendiente de decisión:** la semántica del cambio mixto `unidad ↔ peso` requiere una decisión humana o una ADR. Hasta entonces falla cerrado.
- **B3:** ventas `peso` con D-R1, valorización de cargas con peso, redondeo de líneas `unidad` y documentos mixtos (sin decidir) y retiro de `precioMediaPieza`.
- **B4:** retornos, rendición y cierre con peso. Las jornadas con peso quedan `abierta` y ocupan el camión. **La pantalla Retornos todavía permite aprobar más de lo cargado:** con un retorno así, la preparación de jornadas queda bloqueada con `MENSAJE_STOCK_NO_CALCULABLE` hasta limpiar las operaciones. Hay que cerrar ese origen.
- **B5:** limpieza de `piezas_a_medias`/`medias_a_piezas`. `disponibles_de_jornada` conserva el `Math.max` sólo para presentación. La UI de Movimientos no avisa por adelantado si el ledger es inconsistente, sólo al registrar.
- **Deuda:** `crearJornadaPersistida` no valida stock (no tiene caller productivo; la cubren sus invariantes estructurales).
- **Documentación:** hay notas de estado de Blueprint §2/§7.1, del PRD y de `AGENTS.md` §10 que todavía dicen que el prototipo usa pieza/`_demo_v4`. No son reglas y no se editaron por avance; se actualizan en una tarea documental aparte si se autoriza.
- **Seguridad:** sin cambios de DB, RLS, RPC, Auth, grants ni `SECURITY DEFINER`. Toca fronteras de persistencia de jornadas y movimientos, así que corresponde una security review antes de la auditoría independiente del hash.
- **Sin migración DB y sin cambios en Supabase, staging ni producción.**

---
## 27/10/2026 — Slice B1, ciclo 2: auditoría de `8ff5bef`, corrección H-1 y security review H-2 (sin commit)

**Rama:** `feat/slice-b1-modelo-demo-peso`. **Base del ciclo:** `8ff5bef2257c81d442cba489aeeb9465a66db21b`, el commit de B1, auditado y **no aprobado** para cierre. Es el ciclo 2 de 3 (AGENTS.md §2.3.5). Sin migraciones, sin SQL, sin Supabase remoto, sin staging y sin producción. Sin commit hasta la revisión humana.

### Auditoría independiente de `8ff5bef`
Las dos auditorías revisaron exactamente `8ff5bef2257c81d442cba489aeeb9465a66db21b`, en modo sólo lectura y sin modificar archivos. HEAD y árbol limpio se verificaron antes y después.
- **Codex** (`codex exec --sandbox read-only`): **CAMBIOS REQUERIDOS**.
  - **H-1 (alta, bloqueante):** `confirmarSalidaPersistida` sólo exigía `estado === "preparacion"` y no tenía guard `peso`. Una jornada v5 estructuralmente válida con ítems `peso` podía pasar a `abierta` antes de B2. La UI no bloqueaba el botón y no había un test negativo.
  - **H-2 (media, bloqueante):** faltaba la security review obligatoria de AGENTS.md §2.4. B1 toca ventas y cierres en la capa frontend/localStorage transitoria, aunque no haya SQL.
- **OpenCode** (subagente `auditor`, con `edit: deny` y `bash: deny`, y el patch adjunto): **APROBADO**, sin hallazgos. **No detectó H-1.** Esa aprobación no se reutiliza: el hash nuevo se audita desde cero.
- **Decisión humana:** H-1 y H-2 se aceptan como bloqueantes, y `8ff5bef` queda auditado pero no aprobado.

### Corrección H-1
- **Traza de transiciones** (`hooks/useJornadas.ts`):

  | Función | Transición | Guard `peso` |
  |---|---|---|
  | `crearPreparacionPersistida` | alta en `preparacion` | ya existía |
  | `crearJornadaPersistida` | alta en cualquier estado; sin caller en la UI, sólo el hook y los tests | **faltaba** |
  | `confirmarSalidaPersistida` | `preparacion` → `abierta` | **faltaba (H-1)** |
  | `cerrarJornadaPersistida` | `abierta` → `cerrada` | ya existía |

- **Contrato elegido por el humano:** sólo `confirmarSalidaPersistida` pasa a devolver un resultado discriminado.
- **`confirmarSalidaPersistida`:** devuelve `ResultadoConfirmacionSalida = { ok: true; jornadas } | { ok: false; error }`. Valida dentro de `escribirJornadas`, sobre la jornada recién leída del storage (protección TOCTOU), en este orden:
  1. Si la jornada no existe o no está en `preparacion`: rechazo genérico («No se pudo confirmar la salida.»).
  2. Si algún ítem tiene `unidadMedida !== "unidad"`: `MENSAJE_PESO_NO_OPERABLE`.
  3. Recién después, la transición a `abierta`.

  Si rechaza, no hay `setItem` y el raw queda intacto.
- **`crearJornadaPersistida`:** guard `peso` antes de leer o escribir. Mantiene `Jornada[] | null`.
- **Hook `confirmarSalida`:** devuelve `string | null`. Si la confirmación sale bien, actualiza el estado de React y devuelve `null`. Si se rechaza, no toca el estado y devuelve el error.
- **`pages/Jornadas.tsx`:**
  - `iniciarReparto` muestra el error que devuelve la frontera y no asume éxito.
  - Con una jornada en `preparacion` que tiene `peso`, «Confirmar salida» queda deshabilitado y se muestra `MENSAJE_PESO_NO_OPERABLE` (la constante central).
  - `total` reutiliza el mismo `tienePeso`, sin cambio de comportamiento.

  El guard de persistencia sigue siendo la defensa real; la UI sólo suma una capa.
- No se implementa B2, la entrada en kg, conversiones ni D-R1, y no cambia la semántica de `unidad`.

### Tests H-1
- **`hooks/persistencia.test.ts`:** se adaptan 2 tests existentes al resultado discriminado: la matriz de storage corrupto y «B. confirmarSalida con storage válido». Se agregan 5 tests `H-1`:
  - `crearJornada` con `peso` devuelve `null`, sin `getItem` ni `setItem`;
  - `crearJornada` con historial válido no altera el raw;
  - `confirmarSalida` de una jornada v5 válida en `preparacion` con `peso` devuelve `{ ok: false, error: MENSAJE_PESO_NO_OPERABLE }`, sin `setItem`, con el raw byte a byte igual, todavía en `preparacion` y con `fechaSalida` en `null`;
  - el rechazo de `peso` no bloquea otra jornada `unidad`;
  - una jornada `peso` ya abierta recibe el rechazo genérico, sin escritura.
- **Nuevo `tests/h1-confirmar-salida-peso.spec.ts`** (3 tests, sólo `_demo_v5`, separado de D-R4):
  1. Jornada `peso` en preparación: mensaje visible, botón deshabilitado, raw intacto, 0 escrituras, sigue en `preparacion` y sin `fechaSalida`.
  2. TOCTOU del hook: el botón arranca habilitado (el snapshot es `unidad`); el storage se reescribe con `peso` antes del clic; la frontera rechaza y `role=alert` muestra `MENSAJE_PESO_NO_OPERABLE`; la tarjeta sigue «En preparación», o sea que React no avanzó; el raw mutado queda intacto y hay 0 escrituras.
  3. Regresión `unidad`: «Salida confirmada: Camión H1.», 1 escritura, `abierta` y `fechaSalida` con una fecha ISO válida.
- **Corridas aisladas:** `npx vitest run src/hooks/persistencia.test.ts` → 1 archivo, **215/215**. `npx playwright test tests/h1-confirmar-salida-peso.spec.ts` → **4/4** (setup + 3 de H-1), sin retries.

### Security review H-2
- **Revisor independiente:** Codex (`codex exec --sandbox read-only --ephemeral`). Revisó la base `8ff5bef` más el working tree con H-1 sin commit, a partir del patch con sha256 `328e9e50c995a8b7638c119a45e6eb24245cf4c1a0a9f7c2f9f696b289b90a47`, que incluye el spec todavía sin trackear.
- **Veredicto: APROBADO.** Sin hallazgos de severidad crítica, alta, media ni baja.
- **Superficies confirmadas:**
  - Jornadas: creación, preparación, confirmación, cierre, TOCTOU y corrupción.
  - Ventas/Autoventa: ninguna venta `peso`, D-R1 sin implementar y `precioMediaPieza` sin vía válida.
  - Movimientos y Retornos/Rendición: `peso` bloqueado, sin escrituras y sin cierre alternativo.
  - Persistencia: siete claves `_demo_v5`, clientes en `_demo_v2`, claves v4 intactas, sin escrituras al montar, respaldo por whitelist y fail-closed.
  - H-1: el E2E de TOCTOU no es vacuo.
- **Backend:** sin cambios de DB, RLS, RPC, Auth, grants, `SECURITY DEFINER`, `service_role`, secretos ni dependencias (`package.json` y lockfile sin cambios). Los controles de `unidad` no se relajaron.
- Las huellas sha256 de los 4 archivos coinciden antes y después de la revisión, y el árbol quedó igual.

### Validación global, posterior a H-1 (local, desde `apps/web/`, con `set -o pipefail`)
| Comando | Resultado |
|---|---|
| `npm run typecheck` | `TYPECHECK_EXIT=0`, sin errores |
| `npm run lint` | `LINT_EXIT=0`, sin errores ni avisos |
| `npm test` | `VITEST_EXIT=0`; **27 archivos, 891/891** (ciclo 1: 886; +5 tests H-1) |
| `npx playwright test` | `PLAYWRIGHT_EXIT=0`; **86/86** (1 setup + 85; ciclo 1: 83; +3 de H-1); sin fallos, flaky ni retries |
| `npm run build` | `BUILD_EXIT=0`; único aviso, el preexistente de chunk > 500 kB (`index-y_KEH2zf.js`, 650,32 kB) |
| `git diff --check` (raíz) | `DIFFCHECK_EXIT=0`, sin salida |

### Archivos del ciclo 2
- `apps/web/src/hooks/useJornadas.ts`
- `apps/web/src/pages/Jornadas.tsx`
- `apps/web/src/hooks/persistencia.test.ts`
- `apps/web/tests/h1-confirmar-salida-peso.spec.ts` (nuevo)
- `docs/progress-log.md`

### Pendientes
- Revisión humana del diff final y autorización del commit nuevo.
- **Auditoría independiente desde cero** de Codex y OpenCode sobre el hash nuevo exacto. No se reutiliza ninguna auditoría de `8ff5bef`.
- B2, B3, B4 y B5 siguen igual que en la entrada de B1.
- **Sin migración DB y sin cambios en Supabase, staging ni producción.**

---
## 27/10/2026 — Modelo por peso, Slice B1: modelo `unidad | peso` en la capa frontend/localStorage transitoria y rotación de claves `_demo_v4` → `_demo_v5` (sin commit)

**Rama:** `feat/slice-b1-modelo-demo-peso` desde `main` = `7558f01eb3ab0b7c69b3e5dbd2c107ea8bbef450`. **Alcance: capa frontend/localStorage transitoria y sus tests.** Sin migraciones, sin SQL, sin seed, sin Supabase remoto, sin staging y sin producción. Sin commit hasta la revisión humana.

### Qué se hizo
- **Modelo:** `UnidadMedida` pasa a `"unidad" | "peso"` (se conserva el nombre legacy). Stock, stock mínimo y cantidades son enteros canónicos: unidades o gramos. Los fixtures de fiambres son nuevos, en gramos (7680, 18000 y 2500 g), y no derivan de los fixtures en medias piezas.
- **Fronteras de persistencia** (`useProductos`, `useJornadas`, `domain/movimientos`, `domain/retornos`, `domain/validacion`): aceptan `unidad`/`peso` con la combinación canónica. `pieza`, `media_pieza` y `kg` invalidan el payload, sin conversión (D-R4).
- **Bloqueo fail-closed de `peso` en los flujos operativos** (`MENSAJE_PESO_NO_OPERABLE`), en la UI y en las fronteras de persistencia:
  - preparación/carga y movimientos: B2;
  - ventas: B3, D-R1;
  - retornos y rendición: B4.

  Los productos `peso` se muestran en kg con 3 decimales (`cantidad_a_texto` → `gramos_a_kg`), sin input.
- **Ventas:** una línea `peso` es inválida hasta B3. `precioMediaPieza` sigue en el tipo sólo como deuda legacy: ninguna venta v5 lo genera, y una línea `unidad` con ese campo se rechaza.
- **Claves `localStorage` (D-R4):** las siete claves operativas rotan juntas de `_demo_v4` a `_demo_v5` (`data/clavesStorage.ts`). `distribuidora_clientes_demo_v2` no cambia y se centraliza como `CLAVE_CLIENTES`. Las v4 no se leen, copian, migran, reinterpretan ni borran.
- **Respaldo de ConfiguracionDemo** (`pages/respaldoDemo.ts`, nuevo): usa una whitelist explícita de las claves vigentes en lugar del filtro por prefijo `distribuidora_`. Las v4 no entran al respaldo.
- **`lib/productos.ts`:** se corrigió un comentario desactualizado que decía que esta capa seguía en pieza/media pieza. Sólo documentación, sin cambio de lógica.
- **E2E:** los 7 specs que sembraban claves v4 pasan a v5, sin otros cambios (sus fixtures ya eran `unidad`): `storage-operativo-corrupto`, `toctou-storage-operativo`, `toctou-preparacion-stock`, `toctou-rendicion-post-confirm`, `ledgers-criticos-corruptos`, `toctou-jornadas-revalidacion` y `rendicion-storage-corrupto`.
- **Nuevo `tests/d-r4-claves-v4-legacy.spec.ts` (3 tests):** siembra sólo las 7 claves v4 legacy (fiambre `pieza` con stock 9, mínimo 9 y cantidades 9, y una venta con `precioMediaPieza`). No siembra v5.
  1. Recorre `/jornadas`, `/autoventa`, `/movimientos`, `/retornos`, `/rendicion`, `/cuentas` y `/configuracion-demo`. Ninguna pantalla muestra los datos legacy, `pieza`, `9 g`, `0,009 kg`, `Disponible: 9`, `9 un.` ni avisos de datos dañados.
  2. La preparación muestra los fixtures nuevos (`7,680 kg`, `18,000 kg`, `2,500 kg`, `120 un`) y los camiones de los fixtures, no el legado.
  3. El respaldo descargado no contiene `_demo_v4` ni datos legacy.

  En los tres casos, las 7 claves v4 quedan byte a byte iguales y las v5 siguen ausentes. Tampoco hay `setItem`/`removeItem` sobre v4 ni v5, y `clear()` queda prohibido.
- **Vitest:** se actualizaron los tests de dominio, hooks, páginas y datos al modelo `unidad | peso`. Se agregaron los casos D-R4 en `persistencia.test.ts` y el nuevo `respaldoDemo.test.ts`.

### Verificación (local, desde `apps/web/`)
| Comando | Resultado |
|---|---|
| `npm run typecheck` | exit 0 |
| `npm run lint` | exit 0 |
| `npm test` | **27 archivos, 886/886** (antes 26 / 853) |
| `npx playwright test` (completo) | **83/83** (1 setup + 82; antes 80) |
| Playwright: 7 specs rotados + D-R4 | **33/33** (1 setup + 29 de los specs rotados + 3 de D-R4) |
| `npm run build` | exit 0 (aviso preexistente de chunk > 500 kB) |
| `git diff --check` | exit 0, sin salida |
| Tras corregir el comentario de `lib/productos.ts`: `typecheck`, `lint`, `vitest run src/lib/productos.test.ts` y `git diff --check` | exit 0 / exit 0 / 43/43 / exit 0 |

- No se ejecutó mutation testing sobre `src/data/clavesStorage.ts`: por decisión humana no se modifica temporalmente código productivo. Si hace falta, se hará sobre una copia aislada.
- `supabase status` imprimió en la terminal las credenciales de desarrollo local. No se persistieron en ningún archivo.

### Grep final de legado
`grep -RniE 'media[_ ]?pieza|pieza|_demo_v4|precioMediaPieza|recomponer_medias|medias_a_texto|maximo_piezas_segun_disponible|puede_agregar_media' src tests` → **298 líneas en 29 archivos**. No hay ninguna coincidencia de `recomponer_medias`, `medias_a_texto`, `maximo_piezas_segun_disponible` ni `puede_agregar_media`.
- **D-R4/adversarial intencional:**
  - specs y tests: `tests/d-r4-claves-v4-legacy.spec.ts`, `hooks/persistencia.test.ts` y `pages/respaldoDemo.test.ts`;
  - comentarios D-R4: `pages/respaldoDemo.ts`, `data/clavesStorage.ts`, `data/mockProductos.ts`, `hooks/useProductos.ts` y `lib/productos.ts:15`;
  - rechazos de `pieza`/`media_pieza` en tests: `domain/{productos,movimientos,retornos,venta}.test.ts`, `data/mockProductos.test.ts`, `pages/rendicion_calculos.test.ts`, `lib/productos.test.ts` y `tests/productos-catalogo.spec.ts`;
  - comentarios de rechazo en código: `domain/{productos,movimientos,retornos,validacion}.ts` y `lib/productos.ts:163`.
- **Deuda B3 (ventas/precios, D-R1):**
  - `domain/precios.ts` y `precios.test.ts` (precio de media pieza y subtotal histórico);
  - `MEDIAS_POR_PIEZA` y `descomponer_medias` en `domain/cantidades.ts`;
  - `precioMediaPieza` en `data/mockVentas.ts` (tipo y comentarios), `domain/validacion.ts` y `domain/venta.ts`.
- **Deuda B4 (rendición):** `domain/rendicion.test.ts:133-135`, el caso §12 descrito en medias piezas.
- **Deuda B5 (limpieza final):** `piezas_a_medias` y `medias_a_piezas` en `domain/cantidades.ts`, sin consumidores productivos, y sus tests en `cantidades.test.ts`.
- **Accidental:** `domain/usuario_auth.ts:14` y `usuario_auth.test.ts` (4 líneas). Es un falso positivo por la palabra «empieza», no deuda de código. El comentario desactualizado de `lib/productos.ts` ya se corrigió.

### Riesgos y pendientes
- **B2:** carga de jornadas y movimientos de productos `peso`, con entrada en kg y conversión exacta a gramos. Hoy fallan cerrado.
- **B3:** ventas `peso` con D-R1 (redondeo por línea) y retiro de `precioMediaPieza` y de la lógica de media pieza en `precios.ts`. El redondeo de líneas `unidad` sigue sin decidir.
- **B4:** retornos y rendición de productos `peso`, y reescritura de `rendicion.test.ts` en gramos.
- **B5:** borrar `piezas_a_medias`/`medias_a_piezas` y reevaluar el nombre legacy `UnidadMedida`.
- Las claves v4 siguen en los navegadores que ya las tenían. La aplicación arranca con los fixtures nuevos y los datos v4 dejan de verse. Es el comportamiento buscado por D-R4.
- **Seguridad:** no hubo cambios de DB, RLS, RPC, Auth, grants ni SECURITY DEFINER, por lo que la revisión de seguridad de backend no aplica a B1. Se revisaron las fronteras de persistencia frontend y el comportamiento fail-closed de los flujos afectados.
- **Sin migración DB y sin cambios en Supabase, staging ni producción.**

---
## 27/10/2026 — pgTAP portable local/staging: listas SECURITY DEFINER sin falsos negativos por `public.rls_auto_enable()` (sin commit)

**Rama:** `fix/pgtap-listas-definer-portables` desde `main` = `979375d0d67d043f753a8a8194ac190b0e1b85f1`. **Sólo tests:** sin migraciones, sin SQL productivo, sin seed y sin frontend. **Autorización humana:** ejecutar en staging (`rtsncntppghdynzhezzg`) sólo pgTAP en transacciones revertidas, lint, advisors y la consulta de cleanup. **Producción no tocada.** Sin commit hasta la revisión humana.

### Problema
- En staging había **3 `not ok` de 996**: `auth_base_rls` #5, `camiones_catalogo` #10 y `productos_catalogo` #15 (registrados en la entrada «Cierre de staging: Modelo por peso, Slice A»).
- **Causa:** las listas cerradas de funciones SECURITY DEFINER de `public` no contemplaban `public.rls_auto_enable()` (SECURITY DEFINER, owner `postgres`, event trigger `ensure_rls`). Esa función es de infraestructura del proyecto alojado, está conservada por O-4 (ADR-001 §18.2) y no existe en local. No era un defecto del esquema.

### Solución (sólo expectativas de test; la postura de seguridad no cambia)
- Nuevo auxiliar de sesión `pg_temp.sd_publicas_no_autorizadas()`, idéntico en los tres archivos. Devuelve toda función SECURITY DEFINER de `public` **salvo** la firma exacta `public.rls_auto_enable()`. Una sobrecarga u otro nombre no quedan exentos.
- `auth_base_rls` #5: `sd_publicas_no_autorizadas() = '{}'`. Equivale a «conjunto SD de `public` ⊆ {`rls_auto_enable()`}»: vale tanto en local (ninguna) como en staging (sólo esa).
- `camiones_catalogo` y `productos_catalogo`: la aserción mixta se divide en dos:
  1. Las SECURITY DEFINER de `privado` son **exactamente** las 13 implementaciones de negocio. La lista no cambia.
  2. `sd_publicas_no_autorizadas() = '{}'`.
- Los atributos de `rls_auto_enable()` cuando existe (SECURITY DEFINER, owner `postgres`, `search_path=pg_catalog`, sin EXECUTE para PUBLIC/`anon`/`authenticated`/`service_role`, `ensure_rls` habilitado) **siguen cubiertos por `hardening_adr001`** y no se duplican.
- **Mutación versionada** en `auth_base_rls` (+2 aserciones, revertida por el `rollback`):
  - con `rls_auto_enable()` presente (real en staging; en local se simula como `event_trigger` SECURITY DEFINER y se borra después), se crean `public.funcion_sd_no_autorizada()` y `public.rls_auto_enable(integer)`, ambas SECURITY DEFINER;
  - resultado: las dos se reportan y `rls_auto_enable()` no;
  - en staging la función real no se toca.
- Planes: `auth_base_rls` 55 → **57**, `camiones_catalogo` 113 → **114** y `productos_catalogo` 146 → **147**. Total: 996 → **1000**.

### Verificación
- **Local:** `npx supabase db reset` OK. `npx supabase test db` → **Files=12, Tests=1000, Result: PASS** (0 `not ok`). `db lint --local --fail-on warning` → sin errores, exit 0. `db advisors --local` → «No issues found».
- **Mutaciones ad hoc** (no versionadas, locales y en la transacción de cada test):
  - **A.** `public.zz_sd_mut()` SECURITY DEFINER al inicio del archivo: `auth_base_rls` falla en #5 y #7; `camiones` en #11; `productos` en #16.
  - **B.** `public.rls_auto_enable()` simulada (forma de staging): PASS en los tres.
  - **C.** `privado.zz_sd_mut()` SECURITY DEFINER extra: `camiones` falla en #10 y #14; `productos` en #15 y #17.
- **Staging** (`--linked`, ref verificado `rtsncntppghdynzhezzg`): `npx supabase test db --linked` → **Files=12, Tests=1000, All tests successful, Result: PASS** (0 `not ok`). `db lint --linked --fail-on warning` → sin errores, exit 0. `db advisors --linked` → «No issues found».
- **Cleanup staging:**
  - `productos` = 0, `movimientos_stock` = 0 y `operaciones` = 0;
  - SECURITY DEFINER en `public`: sólo `rls_auto_enable()`, owner `postgres`, sin cambios;
  - 0 funciones residuales de las mutaciones.

### Archivos
- `supabase/tests/auth_base_rls.test.sql`
- `supabase/tests/camiones_catalogo.test.sql`
- `supabase/tests/productos_catalogo.test.sql`
- `docs/progress-log.md`

### Riesgos / pendientes
- La exención depende del nombre y la firma exactos. Si la plataforma renombrara o cambiara la función, las pruebas fallarían de forma cerrada (fail-closed) y habría que revisarla.
- La mutación versionada vive en `auth_base_rls`. En `camiones` y `productos`, el auxiliar es una copia idéntica, validada por las mutaciones ad hoc A y C.
- Toca la superficie «SECURITY DEFINER» (AGENTS.md §2.4), aunque sólo en tests: corresponde **security review** antes de la auditoría.
- Producción: no tocada ni autorizada.

---
## 27/10/2026 — Cierre de staging: Modelo por peso, Slice A — PASS

**Entorno:** staging. **Código:** `main` = `bd82d6c4ac0ddab5f9a10f62b6920d9270dc0d82`, merge del **PR #25**. **Commit auditado del slice:** `c6b228f78d010acb05adffe07d4ef07518824a07`. **Rama de esta entrada:** `docs/cierre-staging-modelo-peso`, sólo documental, sin commit hasta la revisión humana.

La evidencia de staging corresponde a la validación informada por el humano. Esta tarea no ejecutó ningún comando contra staging ni producción y no cambia Blueprint, SQL, tests ni frontend. Esta entrada complementa la de Slice A (más abajo): sus menciones a «staging pendiente de autorización» quedan superadas **sólo en cuanto al estado de staging**.

**Slice A — Modelo por peso: VALIDADO EN STAGING · Producción: NO AUTORIZADA · Slice B: pendiente.**

### Migración
- Estado previo: `productos` = 0, `movimientos_stock` = 0 y `operaciones` = 0. No había ninguna `forma_venta` del modelo anterior, así que la guarda D-R4 no tenía datos que bloquear y no hubo conversión.
- El dry-run mostró **sólo** `20261027001542_modelo_peso_gramos.sql`, y esa migración quedó aplicada en staging.
- Restricciones finales: `forma_venta` ∈ `unidad | peso`, con `lacteos ↔ unidad` y `fiambres ↔ peso`.

### Seguridad
- Topología D verificada: fachada `public` SECURITY INVOKER → implementación `privado` SECURITY DEFINER, con owner `propietario_rpc` y `search_path` vacío.
- RLS, grants y `service_role` verificados: deny-by-default, con la única excepción vigente de `SELECT` sobre `productos`.

### Pruebas
- **pgTAP remoto: 996 assertions, 993 ok y 3 not ok.** Los 3 fallos son exactamente los falsos negativos de portabilidad ya conocidos de la validación de Etapa 2:
  - `auth_base_rls` #5;
  - `camiones_catalogo` #10;
  - `productos_catalogo` #15.

  La causa es que `public.rls_auto_enable()`, una función SECURITY DEFINER de la plataforma, existe en staging pero no figura en las listas cerradas de esas pruebas. No son defectos de Slice A.
- `stock_peso_gramos.test.sql`: **PASS completo**.
- `db lint` remoto: PASS. `db advisors` remoto: PASS.
- **0 fallos nuevos atribuibles a Slice A.**

### Cleanup
- Estado final: `productos` = 0, `movimientos_stock` = 0 y `operaciones` = 0.

### Pendientes
- **Producción: NO autorizada.**
- Pendiente técnico separado: `fix/pgtap-listas-definer-portables`, para que las tres pruebas toleren `public.rls_auto_enable()` sin debilitar las listas cerradas.
- Pendiente funcional: **Slice B del modelo por peso** (resto del demo y del flujo operativo; claves `localStorage`), además de D-R1 en ventas y el redondeo de líneas `unidad`, que siguen sin decidir ni implementar.

---
## 26/10/2026 — Modelo por peso, Slice A: base de datos, RPC de catálogo y compatibilidad de Productos (sólo local; sin commit)

**Rama:** `feat/modelo-peso-gramos` desde `main` = `476f22741d650c98f03b5dc95269d91b430424cd`. Implementación autorizada por el humano (aprobación de esquema/seguridad otorgada). **Alcance inicial: sólo base de datos.** Sin demo, sin Jornada/Ventas/Rendición/Presupuestos, sin staging, sin producción. Sin commit hasta la revisión humana.

**Ampliación autorizada (decisión humana, «autorización de desbloqueo»):** no mergear Slice A con Playwright rojo. Se adapta **sólo el consumidor frontend inmediato del catálogo** (pantalla Productos) al contrato `unidad | peso`. Esto **no** es Slice B.

- **Frontend Productos: adaptado.**
- **Resto del demo y del flujo operativo: pendiente** (Slice B): Autoventa, Jornadas, Movimientos, Retornos, Rendición, claves `localStorage` y `UnidadMedida`/`domain/productos.ts` del prototipo siguen en pieza/media pieza.

### Qué se hizo
- **Migración nueva `supabase/migrations/20261027001542_modelo_peso_gramos.sql`** (creada con `npx supabase migration new`; no se editaron migraciones históricas):
  - **Guarda fail-closed D-R4:** toma `ACCESS EXCLUSIVE` sobre `productos` y, si existe algún producto que no sea `unidad` (antes sólo podía ser `pieza`), aborta con `modelo_peso_gramos: N producto(s) del modelo pieza/media pieza y M movimiento(s) asociados` y un hint que cita D-R4. No hay `UPDATE`, conversión, borrado ni normalización.
  - `productos_forma_venta_valida` pasa a `unidad | peso` y `productos_combinacion_valida` a `lacteos ↔ unidad`, `fiambres ↔ peso`. Se conservan los nombres de las restricciones, así que el mapeo de errores no cambia.
  - `privado.crear_producto` se redefine con `CREATE OR REPLACE`, con la misma firma, owner y ACL (O-3: `SET ROLE propietario_rpc` con `CREATE` temporal sobre `privado`, revocado al final). La fachada `public.crear_producto` no cambia; sólo recibe un `COMMENT`.
  - Comentarios: `productos.forma_venta`, `precio` (unitario o por kg), `stock_minimo` (unidades o gramos), `movimientos_stock.cantidad` (unidades o gramos según la `forma_venta`) y la vista `stock_actual`.
  - **Verificación fail-closed final:** restricciones validadas y sin `pieza`; tipos `numeric(14,2)`/`integer`/`integer`; `crear_producto` `SECURITY DEFINER`, owner `propietario_rpc`, `search_path=''`, ACL exacta y sin sobrecargas; sin `CREATE` residual; `categoria`/`forma_venta` no actualizables; P11 (`service_role` sólo con `SELECT` sobre `productos`); RLS activa y sin `FORCE`.
- **Sin cambios** en tipos (`precio numeric(14,2)`, `stock_minimo integer`, `movimientos_stock.cantidad integer`), en las RPC de stock (`registrar_ingreso`, `mover_a_cuarentena`, `registrar_merma`, con `p_cantidad integer`), en `actualizar_producto`/`cambiar_estado_producto`, ni en grants, RLS, concurrencia (READ COMMITTED + advisory lock + fallo cerrado PT500 con RR/SERIALIZABLE) o idempotencia. La base recibe siempre el entero canónico; la conversión kg → g es de la UI (Slice B).
- `supabase/seed.sql` (sólo local): los dos fiambres del seed pasan a `peso`, con precio por kg y stock mínimo nuevo en gramos (5000 y 3000). Son fixtures nuevos, no una conversión.
- **pgTAP:**
  - `productos_catalogo` 125 → **146**: combinaciones válidas e inválidas (`lacteos+peso`, `fiambres+unidad`, `pieza`, `media_pieza`, `kg`, también por la implementación privada y por la tabla como owner); precio por kg (0, 2 decimales, más de 2 y negativo); stock mínimo en gramos (entero, negativo, fracción `1250.5` y `1,250` rechazados); inmutabilidad `unidad → peso` y `peso → unidad`; definición exacta de las restricciones; comentarios.
  - `stock_ingreso`: el fixture fiambre pasa a `peso`, con los mismos 119 casos.
  - **Nuevo `stock_peso_gramos` (33):** ledger entero sin columnas numeric, float, kg ni unidad; firmas de stock sin cambios; unidad `7` = 7 u; peso: ingreso 1250 → cuarentena 250 → depósito 1000 / cuarentena 250 → merma 300 → 700 → merma 701 y cuarentena 701 rechazadas (1 g de más) → merma 700 → 0; idempotencia (1 g distinto es conflicto); `1.25` y `1250.5` rechazados (22P02); 0 y negativos; vendedor, otra empresa y aislamiento de lectura.
- **Arnés D-R4 versionado `supabase/scripts/verificar_legado_pieza.sh`** (sólo local: `db reset --version 20261025033454 --no-seed` + `docker exec psql` por socket, sin credenciales). Fase A: con un producto `pieza` (precio 12500.00, stock mínimo 9) y un ingreso de 9 medias piezas, la migración falla con el error de D-R4 y la huella de filas, restricciones, comentarios y `crear_producto` queda idéntica. Fase B: con sólo productos `unidad`, la migración se aplica y no toca sus datos. Al final restaura la base completa.
- **Compatibilidad de Productos (frontend, ampliación autorizada):**
  - `apps/web/src/domain/peso.ts` (nuevo, puro): `kg_a_gramos(texto)` parsea el texto con coma decimal y hasta 3 decimales, y arma los gramos con BigInt: `"1,250"` → 1250, `"28,680"` → 28680. Rechaza más de 3 decimales, el punto (ambiguo con miles en es-AR), los negativos, texto y vacío, y no redondea ni trunca. `gramos_a_kg(g)` arma el texto con 3 decimales fijos cortando la cadena: 1250 → `"1,250"`. Ninguna de las dos usa punto flotante.
  - `apps/web/src/lib/productos.ts`: contrato propio del catálogo `FormaVenta = "unidad" | "peso"` y `formaVentaParaCategoria` (Lácteos ↔ unidad, Fiambres ↔ peso); el campo pasa de `unidadMedida` a `formaVenta`. `filaAProducto` acepta `unidad`/`peso` con su combinación, y una fila `pieza`, `media_pieza`, nula, desconocida o con combinación cruzada sigue invalidando la lectura completa (fail-closed). Una fila `pieza` nunca se convierte a `peso` (D-R4). El mensaje de `producto_combinacion_invalida` dice «por peso». **No** se tocaron `UnidadMedida` (`data/mockProductos.ts`) ni `domain/productos.ts`, que también usa el demo.
  - `apps/web/src/pages/Productos.tsx`: la forma de venta se muestra derivada de la categoría, en un campo de sólo lectura, sin opción de cambiarla. El precio se rotula «por unidad» o «por kg» en el formulario y en la tabla. El stock mínimo es en unidades enteras para `unidad` y en kg para `peso` (texto con coma y hasta 3 decimales, enviado a la RPC en gramos exactos; en edición se precarga en kg). La tabla muestra `N,NNN kg`. Se quitaron el precio y el texto de media pieza. La edición no envía categoría ni forma de venta.
  - Pruebas: nuevo `domain/peso.test.ts` (40); `lib/productos.test.ts` actualizado (fiambre `peso`; rechazo de `pieza`, `media_pieza`, nulo y combinaciones cruzadas; catálogo mixto aceptado). `tests/productos-catalogo.spec.ts` pasa de 15 a 19: el catálogo muestra fiambres por peso (`5,000 kg`, «por kg») y no muestra `pieza`; se crea un fiambre (la RPC recibe `p_forma_venta: "peso"` y `p_stock_minimo: 2500` por `2,5` kg); se rechazan `2,5001`, `0,0001`, `2.500` y `-1` sin llamar a la RPC; la edición de un fiambre no permite cambiar categoría ni forma de venta, precarga `28,680` y envía 1250 g por `1,25`; por HTTP, `pieza` → `producto_forma_venta_invalida`, las combinaciones cruzadas → `producto_combinacion_invalida` y el alta `peso` guarda 1250 g. Se conservan todos los casos de permisos y de la Data API.
  - D-R1 no se implementa (no se calculan importes) y no se decide el redondeo de líneas `unidad`.
- Documentación (notas de estado, sin cambio de reglas): `BLUEPRINT.md` 2.2 → 2.3 (§7.1 y §8, fila de historial), `AGENTS.md` §10 y `docs/architecture/analisis-base-datos.md` 0.3 → 0.4 (§0 y fila `productos`).

### Decisiones respetadas
- **D-R1:** no se implementa; el catálogo guarda el precio, no importes de línea. No existen ventas ni presupuestos en SQL. El redondeo de líneas `unidad` sigue pendiente.
- **D-R2/D-R3:** sin impacto en este slice: las RPC de stock registran el entero recibido, sin tolerancia ni normalización.
- **D-R4:** la migración falla cerrada ante datos `pieza` y nunca los reinterpreta, como prueban el arnés y su mutación.

### Verificación (local)
- `npx supabase db reset --local`: 11 migraciones y seed, sin errores.
- `npx supabase test db --local`: **12 archivos, 996 planes / 996 assertions, 996 ok, 0 not ok** (antes 942; +21 en productos y +33 en el archivo nuevo).
- Arnés D-R4: **8/8 PASS**. **Mutación:** con la guarda desactivada y un `UPDATE … set forma_venta = 'peso'`, el arnés da 5 FAIL (detecta `peso/12500.00/9`, la reinterpretación prohibida); se restauró el archivo byte a byte.
- Concurrencia (arnés ad hoc no versionado, dos conexiones reales sobre el seed): C1, dos mermas de 600 g sobre 1000 g del mismo producto `peso`: S2 espera el lock, ve 400 g y recibe `stock_insuficiente`; C3, producto distinto: sin espera (7 ms); sin saldos negativos. Los dos archivos pgTAP de aislamiento RR/SERIALIZABLE pasan.
- `npx supabase db lint --local --fail-on warning`: sin errores. `npx supabase db advisors --local`: seguridad 0; 7 avisos INFO de performance preexistentes (FKs sin índice e índice sin uso; la migración no agrega FKs ni índices).
- Primera corrida, antes de la ampliación: Playwright 70/76, con 6 fallas en `productos-catalogo.spec.ts`, porque `filaAProducto` descartaba todo el catálogo ante filas `peso`. Línea base en `main`: 15/15. Eso motivó la ampliación autorizada.
- **Gate final, después de adaptar Productos:** arnés D-R4 8/8; `db reset` y pgTAP **996/996** (12 archivos, 0 not ok); `db lint` sin errores; advisors de seguridad 0 y sólo los 7 INFO de performance preexistentes; concurrencia ad hoc repetida (C1: S2 espera el lock ~1,5 s y recibe `stock_insuficiente`; C3: 7 ms; sin negativos); `typecheck` y `lint` exit 0; Vitest **853/853** (26 archivos); `build` OK; **Playwright 80/80**.

### Riesgos y pendientes
- **Resuelto por la ampliación autorizada:** la pantalla Productos y su spec E2E ya son compatibles con el SQL nuevo. El resto del demo sigue pendiente (Slice B).
- La entrada de kg acepta sólo coma decimal (convención es-AR con la que también se muestran los kg). El punto se rechaza con un mensaje explícito. El precio conserva su campo numérico actual.
- Staging: no se aplicó (`db push` no autorizado). Si staging tuviera productos `pieza`, la migración fallará cerrada por diseño (D-R4): hace falta un reinicio limpio autorizado.
- Producción: **NO autorizada**.
- El arnés de concurrencia sigue sin versionar (riesgo MEDIUM ya registrado); el CI no ejecuta Supabase.
- Corresponde **security review** (Supabase, RLS, RPC `SECURITY DEFINER`, grants, `movimientos_stock`) y auditoría independiente del hash, cuando exista.

---
## 26/10/2026 — Documental: cierre humano de ADR-005 D-R1–D-R4 (sin implementación; sin commit)

**Rama:** `docs/cerrar-decisiones-peso` desde `main` = `ce4e8700b166b524e2da5eb290066f96e2b4ef8b`. **Tarea sólo documental:** sin código, SQL, migraciones, pruebas, frontend, Supabase, staging ni producción. Sin commit hasta la revisión humana.

### Decisiones humanas registradas (26/10/2026)
- **D-R1, redondeo monetario por peso:**
  - el importe exacto `gramos × precio_por_kg / 1000` se calcula sin `float` y puede tener más de 2 decimales;
  - **cada línea `peso` se redondea una sola vez al peso entero** con **empate 0,50 hacia arriba** (`$1.543,20 → $1.543`; `$1.544,50 → $1.545`);
  - el aporte de las líneas `peso` al total es la **suma de sus importes ya redondeados**, nunca recalculada desde valores exactos; el total de un documento es la suma de los importes finales de cada línea según la regla de su tipo;
  - aplica **sólo a líneas `peso`** de ventas, presupuestos y valorizaciones por peso que dependan de la regla;
  - `numeric(14,2)` sigue siendo el tipo monetario general (`1545.00`); no se cambia a `integer`.
- **D-R2, peso efectivamente medido:** cada operación (ingreso, carga, venta, devolución del cliente y conteo de regreso) registra el peso medido en esa operación; en la carga, el mismo valor en gramos es débito del depósito y crédito del camión. Sin balanza, integración, Bluetooth, captura automática ni punto físico de pesaje definidos.
- **D-R3, diferencias de pesaje:** sin tolerancia automática en Fase 1; toda diferencia distinta de cero, incluso de 1 gramo, se registra. No implica faltante culpable ni sanciones o descuentos automáticos.
- **D-R4, datos del modelo anterior:** reinicio limpio; una cantidad en medias piezas nunca se interpreta como gramos. Local/staging sin migración semántica; prototipo con claves `localStorage` nuevas, sin leer, copiar, reinterpretar ni borrar automáticamente las anteriores. Producción sin autorización.
- **Aclaración humana (AskUserQuestion):** D-R1 rige sólo para líneas `peso`. Queda **pendiente nuevo** si el importe final de las líneas `unidad` (precio con hasta 2 decimales) conserva centavos o se redondea al peso entero y, por lo tanto, si un documento mixto `peso` + `unidad` puede terminar con centavos.

### Qué se hizo
- `docs/decisions/005-fiambres-por-peso-gramos.md` v1.0 → **v1.1**: §2.3.3 con D-R1; §2.4 (D-R2), §2.5 (D-R3) y §2.6 (D-R4) nuevas. §5 pasa a «decisiones cerradas», con la pregunta original y la decisión, el pendiente derivado de `unidad` y la tabla original conservada como historial. También se tocaron §6 (consecuencias y pruebas futuras) y §7 (fuente MDN `Math.round`). Estado sin cambios: **APROBADA**, sin autorizar migraciones, implementación ni producción.
- `docs/decisions/README.md`: fila de ADR-005 (v1.1, D-R1–D-R4 cerradas).
- `BLUEPRINT.md` v2.1 → **v2.2**:
  - §2, §7.1 (D-R1, D-R2, D-R3, D-R4 y coexistencia con `numeric(14,2)`), §7.4, §7.5, §7.8 (sin tolerancia) y §7.10.6;
  - §8 (`venta_items`) y §11;
  - §12 (casos de redondeo, empate, total, peso medido, diferencia de 1 g y datos anteriores, como requisitos futuros);
  - §14 (la migración a peso es el siguiente bloque técnico) y §15 (D-R1–D-R4 tachadas como resueltas; pendiente nuevo de `unidad`);
  - §16 y §17.
- `docs/PRD.md` 0.11 → **0.12**: §0, §7.1 (flujo de presupuesto), §9, criterios de aceptación, §21 y §22.
- `docs/architecture/analisis-base-datos.md`: en la fila `venta_items`, la mención «D-R1 pendiente» pasa a la regla cerrada (única línea afectada).
- **Correcciones de la revisión documental, sin cambiar decisiones:**
  - LOW-1: Blueprint §7.5 pasa a ser una recomendación («conviene diseñar la venta por peso sobre el modelo ya migrado; el orden lo autoriza el humano según §14»).
  - LOW-2: para líneas `unidad`, «la fórmula vigente es `cantidad × precio_unitario`; permanece pendiente si el importe final conserva centavos o se redondea al peso entero». Se quitó «exacto» del Blueprint y de ADR-005.
  - LOW-3: el pendiente nombra explícitamente el efecto sobre documentos mixtos `peso` + `unidad`, con el ejemplo del problema `3 × $1.234,56 = $3.703,68` (no es una decisión).
  - INFO: en ADR-005 §6, «no se borran automáticamente las claves anteriores», igual que D-R4; no autoriza borrado manual ni migración de claves.
- **Corrección post-auditoría (commit rechazado `2e4c754`):** se eliminaron las frases que generalizaban a todas las líneas el «importe ya redondeado según D-R1» o el «total = suma de líneas redondeadas» (ADR-005 §2.3.3, §2.3.4, §5 y §6; Blueprint §2, §7.1, §7.5, §7.10.6, §12, §15 y §17; PRD §7.1, §9, criterios de aceptación, §21 y historial). Queda así: D-R1 aplica sólo a líneas `peso`; el total es la suma de los importes finales de cada línea según la regla de su tipo; las líneas `unidad` y los centavos de documentos mixtos siguen pendientes. No se resolvió ninguna decisión adicional.

### Pendientes que siguen abiertos (no se resolvió ninguno)
- **Presupuestos:** numeración, ciclo de vida, vigencia, conversión a venta, vendedor/piloto, cliente no registrado, cuenta, origen y edición del precio, y entrega.
- **Otros:** DNI y cuenta de clientes; base de valorización de faltantes (`BLUEPRINT.md` §15, prioridad media); redondeo de líneas `unidad`. IVA 21% sigue siendo sólo visual y no hay descuentos.

### Skills usadas
- **source-driven-development:** documentación oficial de PostgreSQL 17:
  - `numeric` es exacto y recomendado para importes;
  - «the numeric type rounds ties away from zero», que para importes positivos equivale a 0,50 hacia arriba;
  - redondeo implícito al guardar con más escala que la declarada.

  MDN `Math.round` redondea los empates hacia +∞ sobre `Number` de doble precisión, por eso la regla se formula sobre el decimal exacto. Ejemplos verificados con aritmética entera exacta (BigInt) en Node: `1250 g × $1.234,56` = `1543,2` → `1543`; `1250 g × $1.235,60` = `1544,5` → `1545`; dos líneas de `1543,4` → `3086` (no `3087`).
- **api-and-interface-design:** el importe final de cada línea (para `peso`, el redondeado por D-R1) es el valor guardado y el total se deriva de esos valores (snapshot, sin recálculo); no se diseñaron RPC ni columnas.
- **grilling:** se mapeó el árbol de decisiones. La única rama abierta (las líneas `unidad`) se planteó al humano, que eligió registrarla como pendiente.

### Cómo se verificó
`rg` de D-R1–D-R4 en `BLUEPRINT.md` y `docs/`, `git diff --check`, `git status --short`, `git diff --stat` y `git diff --name-status`. No se corrió la suite técnica: la tarea es documental y no toca código.

### Siguiente bloque técnico
**Migración al modelo por peso** (productos, ledger en gramos, RPC, pgTAP/Vitest y prototipo), con su propio preámbulo, plan autorizado y security review. No está autorizada por esta entrada.

**CODE/SQL/MIGRATIONS/TESTS: NOT MODIFIED · STAGING: NOT TOUCHED · PRODUCTION: NOT TOUCHED · COMMIT: NOT CREATED.**

---
## 26/10/2026 — Cierre de staging: Etapa 2 — Stock (stock-ingreso + stock-cuarentena-merma) — PASS

**Entorno:** staging, project ref `rtsncntppghdynzhezzg` (ref verificado por el runner antes de cada conexión) · **Código:** `main` = `0458f21544b0ed82a2bc7f57f6807d2a72d0d97e` · **Commit funcional del slice:** `f0b02abe27c5a479e2c6c0a5fae292114f576b31` · **Autorización humana explícita:** aplicar la migración en staging (hecho por el humano) y validar con fixtures temporales, transacciones revertidas y cleanup. **Producción no tocada.** Sin `db push` por parte de Claude, cambios de código/SQL/tests, merge ni deploy. Esta entrada complementa las de los slices 1 y 2 de la Etapa 2, cuyas líneas «STAGING: NOT TOUCHED» reflejan el momento de aquellas entradas y quedan superadas por ésta **sólo en cuanto al estado de staging**.

**Etapa 2 — Stock: VALIDADA EN STAGING · Producción: NO AUTORIZADA · ADR-005: todavía NO implementada** (la validación corresponde al modelo de cantidades vigente en el SQL, anterior al cambio a gramos).

### Migración
- Estado previo, verificado por SQL de sólo lectura: 9 migraciones aplicadas, hasta `20261025021032_stock_operaciones_ingreso`; `20261025033454` no aplicada; todos los conteos de negocio y de Auth en 0.
- El humano aplicó `20261025033454_stock_cuarentena_merma.sql` el 26/10/2026: el dry-run listó sólo esa migración, `supabase db push --linked` terminó OK y un segundo push respondió «Remote database is up to date.».
- Catálogo: la versión `20261025033454 stock_cuarentena_merma` figura **exactamente una vez** en `supabase_migrations.schema_migrations`; `migration list --linked` muestra **10/10 alineadas**; ninguna versión posterior inesperada.

### Validación funcional (Data API con JWT reales + SQL administrativo)
- Método: dos empresas temporales `stgcm-9b967f-*` (B sólo como fixture adversarial de aislamiento) y seis usuarios temporales:
  - dueño A;
  - encargado A;
  - vendedor/piloto A con `user_metadata.rol = "dueno"` engañoso;
  - encargado A inactivo;
  - usuario sin perfil;
  - dueño B.

  La contraseña fue aleatoria por corrida y no se imprimió. Las credenciales se pasaron sólo por variables `PG*` del proceso hijo y el SQL por stdin; no se imprimieron DSN, JWT ni keys.
- **Regresión de `registrar_ingreso`:** 12/12.
- **`mover_a_cuarentena`: PASS.**
  - Dueño y encargado OK, con una operación y un movimiento depósito → cuarentena, cuyo destino resuelve el servidor.
  - Motivo con trim, huella v1 igual al literal canónico, saldos derivados correctos y stock exacto a 0 permitido.
  - 24/24 negativos sin efectos en el ledger ni reserva de la clave:
    - anon y `service_role`: `42501`;
    - vendedor, inactivo y sin perfil: `PT403`;
    - cruces de empresa: `PT404`;
    - cantidad 0, negativa o NULL, motivo vacío, en blanco o NULL, y clave NULL: `PT400`;
    - origen cuarentena o camión: `PT400 stock_origen_invalido`;
    - origen o producto inexistente: `PT404`;
    - producto inactivo: `PT409`;
    - stock insuficiente: `PT409`.
- **`registrar_merma`: PASS.**
  - Dueño y encargado OK con los seis códigos de Blueprint §7.7, `otro` con texto (trim) y código con `btrim`.
  - Movimiento depósito → NULL y huellas con y sin texto correctas.
  - 24/24 negativos: los mismos que en cuarentena más código fuera del catálogo, en mayúsculas o NULL, `otro` sin texto o en blanco y origen cuarentena bloqueado (D4).
  - Una aserción del runner dio falso negativo por un índice de columnas mal tomado; la fila impresa mostraba los datos correctos (`motivo_codigo = otro`, texto con trim, actor encargado).
- **Idempotencia: PASS (10/10).**
  - El replay con la misma clave y el mismo payload normalizado devuelve el mismo id, sin efectos.
  - Responden `PT409 stock_conflicto_idempotencia` los conflictos por cantidad, motivo, código, texto, producto y tipo (clave de cuarentena reutilizada en merma).
  - La misma UUID usada por otro actor crea una operación nueva.
- **RLS, grants y Topología D: PASS (30/30 por HTTP, además del catálogo).**
  - Las fachadas `public` son SECURITY INVOKER de `postgres`; las implementaciones `privado` son SECURITY DEFINER de `propietario_rpc`; todas con `search_path=''`.
  - La ACL de EXECUTE es `{owner, authenticated}`; PUBLIC, anon y `service_role` no tienen EXECUTE.
  - Dueño y encargado leen sólo filas de su empresa; vendedor, inactivo y sin perfil leen 0 filas (no depende de `user_metadata`); anon y `service_role` reciben `42501`.
  - UPDATE, DELETE e INSERT directos sobre `operaciones` y `movimientos_stock` se rechazan para dueño, encargado, vendedor, anon y `service_role`, y el ledger queda sin cambios.
  - `privado` no está expuesto por la Data API.
- **Aislamiento transaccional: PASS (21/21).**
  - `READ COMMITTED` acepta la operación.
  - `REPEATABLE READ` y `SERIALIZABLE` se rechazan con `PT500 stock_error_interno`, tanto en `privado.*` como en las fachadas, sin operación, sin movimiento, con stock intacto y sin reservar la clave.
  - La misma clave reutilizada después en `READ COMMITTED` funciona, con una operación y un movimiento.

### Concurrencia (dos conexiones reales; S1 retiene el lock 3 s)
| Caso | Resultado |
|---|---|
| C1 cuarentena 7 ‖ merma 7 sobre 10 | una OK, la otra `stock_insuficiente`; saldo 3 |
| C2 cuarentena 4 ‖ merma 5 sobre 10 | ambas OK (S2 esperó ~3,95 s); saldo 1 |
| C3 productos distintos | sin bloqueo cruzado: S2 terminó 1,5–1,8 s antes de que S1 liberara el lock (3/3) |
| C4 misma clave y mismo payload | mismo `operaciones.id`, una operación, un movimiento; saldo 7 |
| C5 cuarentena 6 ‖ 6 sobre 10 | una OK, la otra `stock_insuficiente`; depósito 4, cuarentena 6 |
| S2 en `REPEATABLE READ`/`SERIALIZABLE` con el lock retenido | `PT500` sin esperar; clave no reservada |

- Ningún saldo negativo; al final había 47 operaciones con 47 movimientos.
- C3 se repitió con la tolerancia documentada del arnés local (< 1,0 s), porque una RPC sin contención tarda en staging 0,47–1,13 s medidos en el servidor. La evidencia determinante es que S2 terminó mientras S1 todavía retenía el lock.

### pgTAP (suite completa ejecutada en staging, cada archivo en su transacción revertida)
- **942 aserciones / 939 ok / 3 not ok** en 11 archivos:
  - `stock_cuarentena_merma` 150/150, `stock_ingreso` 119/119, `ubicaciones` 82/82;
  - los dos archivos de aislamiento, 16/16 cada uno;
  - `clientes_catalogo` 183/183, `grants_default_privileges` 32/32;
  - `hardening_adr001` 51/51: las aserciones O-4, que en local salen SKIP, corrieron contra el objeto real.
- Las 3 fallas (`auth_base_rls #5`, `camiones_catalogo #10`, `productos_catalogo #15`) **no son defectos del producto**. Son listas cerradas de funciones SECURITY DEFINER armadas para local, donde no existe `public.rls_auto_enable()`. En staging ese objeto existe y se conserva por O-4, sin EXECUTE para PUBLIC, anon, `authenticated` ni `service_role`.
- **Propuesta separada, no implementada en esta rama:** `fix/pgtap-listas-definer-portables`.
- La huella de catálogo (roles, extensiones, funciones, relaciones, policies, default ACL y conteos) es idéntica antes y después de la suite.

### Advisors
- `supabase db advisors --linked`: «No issues found».
- `supabase db lint --linked`: «No schema errors found».

### Cleanup
- Se eliminaron sólo los fixtures del run (por id y prefijo): ledger, productos, ubicaciones, camión, perfiles, usuarios Auth, identities, sesiones, tokens y entradas de `audit_log_entries`.
- Conteos finales iguales a los iniciales (todos en 0); huella de catálogo idéntica a la inicial; sin datos residuales; el archivo temporal de contraseña se borró.
- Los runners quedaron fuera del repositorio.

### Security review (solo lectura, 26/10/2026)
- Revisión de `f0b02ab` con `/security-review` como insumo.
- **Sin hallazgos Critical, High ni Medium.** Se verificaron:
  - Topología D, `search_path` y owner;
  - ACL de EXECUTE, grants por columna y ledger append-only;
  - policies de INSERT por tipo y FK compuestas por `empresa_id`;
  - identidad desde el `sub` del JWT y rol/empresa desde `perfiles`;
  - idempotencia (reserva antes de las validaciones mutables, huella con tipo);
  - lock con saldo leído después, guard de aislamiento, `service_role` y no exposición de `privado`.
- La security review humana e independiente que exige `AGENTS.md` §2.3 sigue siendo competencia del humano y de los auditores.

### Riesgos conocidos (no bloquean la Etapa 2)
1. El arnés de concurrencia no está versionado (se reconstruyó ad hoc fuera del repositorio para esta validación).
2. El CI no ejecuta Supabase (ni pgTAP ni el arnés).
3. Las listas cerradas de pgTAP no son totalmente portables entre local y staging (ver propuesta `fix/pgtap-listas-definer-portables`).

**STAGING: VALIDADO · PRODUCCIÓN: NO TOCADA / NO AUTORIZADA · CODE/SQL/TESTS: NOT MODIFIED · ADR-005: NO IMPLEMENTADA · SECRETS EXPOSED: NO.**

---
## 25/10/2026 — Documental (cierre): ADR-005 §2.3.1 limitada al desbordamiento (M-3 / L-1)

**Rama:** `docs/fiambres-peso-presupuestos` (base `b60a6d1`). **Sólo documental**, autorizada por decisión humana tras la segunda revisión documental completa.

- **ADR-005 §2.3.1:** la regla de error queda limitada a **desbordamiento o valor fuera del rango representable** (falla con error; nunca devuelve un valor aproximado). Un resultado monetario exacto con más de 2 decimales **no** es un error automático: su conversión al importe final se rige por **D-R1**, que sigue **completamente pendiente**.
- **ADR-005 §4:** la regla de desbordamiento se atribuye sólo a ADR-005 §2.3.1 (no a `BLUEPRINT.md` §7.1). El Blueprint no cambió en esta corrección.

**CODE/SQL/MIGRATIONS/TESTS: NOT MODIFIED · STAGING: NOT TOUCHED · PRODUCTION: NOT TOUCHED.**

---
## 25/10/2026 — Documental (tercera pasada): bloqueos M-1/M-2 y observaciones L-1–L-3 de la revisión completa (sin commit)

**Rama:** `docs/fiambres-peso-presupuestos` (base `b60a6d1`). **Sólo documental**, con decisiones humanas explícitas del 25/10/2026 sobre los hallazgos de la revisión documental completa. Esta entrada deja superado lo que las dos entradas anteriores de este día dicen sobre ADR-003 «reemplazada parcialmente» y sobre la presentación «hasta 3 decimales».

### Decisiones humanas aplicadas
- **M-1:** ADR-003 pasa a **REEMPLAZADA por ADR-005**, en su totalidad y sin autoridad normativa. Los principios generales que siguen vigentes (2 decimales en precios, `>= 0`, aritmética exacta sin `float`, snapshot) rigen por `BLUEPRINT.md` §7.1 y ADR-005 §2. Se actualizaron el encabezado y la nota de ADR-003, la nota de ADR-002, el índice `docs/decisions/README.md`, ADR-005 (encabezado y §4) y las menciones en Blueprint y PRD. El principio de «fallar cerrado» que antes sólo estaba en ADR-003 §2.3 quedó explícito en ADR-005 §2.3.1.
- **M-2:** **D-R1 queda completamente pendiente** (destino, regla de empate, momento y escala intermedia). Se quitaron «redondeo a centavos», «una sola vez por línea» y «único redondeo final por línea» de ADR-005, Blueprint y PRD. Siguen vigentes: nunca `float`, aritmética exacta y la fórmula conceptual `gramos × precio_por_kg / 1000`.
- **L-1:** se separa la **entrada** en kg (hasta 3 decimales; más de 3 se rechaza sin redondear) de la **presentación** (3 decimales fijos). Los gramos enteros siguen siendo el canónico.
- **L-2:** el **origen del precio** de cada línea del presupuesto queda pendiente (automático desde el catálogo, editable o no, quién lo modifica). Se quitó «se toma el precio vigente del catálogo».
- **L-3:** «presupuesto emitido» pasa a «presupuesto guardado». No se introduce ningún ciclo de vida ni estado.

### Cómo se verificó
`git diff --check`, `git status --short`, `git diff --stat` y búsquedas `rg` de las frases eliminadas, de ADR-003/media pieza y de D-R1/redondeo, con las apariciones residuales clasificadas.

**CODE/SQL/MIGRATIONS/TESTS: NOT MODIFIED · STAGING: NOT TOUCHED · PRODUCTION: NOT TOUCHED · COMMIT: NOT CREATED.**

---
## 25/10/2026 — Documental (segunda pasada): AGENTS y análisis de base de datos alineados con ADR-005 (sin commit)

**Rama:** `docs/fiambres-peso-presupuestos` (misma tarea que la entrada siguiente; base `b60a6d1`). **Sólo documental**, autorizada por el humano en dos correcciones puntuales.

### Qué se hizo
- `AGENTS.md` §10: la regla «Los fiambres se venden por pieza y media pieza» se reemplazó por una regla breve alineada con ADR-005 (`unidad` en cantidad entera; `peso` en kg con hasta 3 decimales y gramos enteros como canónico; nunca `float` para cantidades ni dinero) con enlace a ADR-005. En §7 se aclaró que `piezas_a_medias`/`medias_a_piezas` son identificadores existentes del prototipo cuya semántica revisa la tarea de migración.
- `docs/architecture/analisis-base-datos.md` v0.2 → **v0.3**: bloque en §0 que separa el **modelo histórico** pieza/media pieza, el **modelo objetivo** de ADR-005 («implementación pendiente») y el **SQL/prototipo actual** pendiente de migración; filas de `productos`, `movimientos_stock.cantidad` y `venta_items` alineadas sin fijar columnas ni tipos SQL definitivos.

### Cómo se verificó
`git diff --check` (exit 0), `git status --short`, `git diff --stat` y `rg` global de `fiambres.*pieza|pieza.*fiambre|media pieza|medias piezas|precio_media|precio_pieza|no existe.*kg` sobre `AGENTS.md`, `BLUEPRINT.md` y `docs/`. **Sin contradicciones reales restantes:** las apariciones son históricas (ADR-002/003, historial de versiones, requisito de migración, bitácora), estado actual pendiente de migración (SQL local, prototipo, D-R4) o referencias explícitas a la regla reemplazada.

**CODE/SQL/MIGRATIONS/TESTS: NOT MODIFIED · STAGING: NOT TOUCHED · PRODUCTION: NOT TOUCHED · COMMIT: NOT CREATED.**

---
## 25/10/2026 — Documental: fiambres por peso (ADR-005) y módulo Presupuestos (sin implementación; sin commit)

**Rama:** `docs/fiambres-peso-presupuestos` desde `main` = `b60a6d1ef23189649dc67bee22059eea2859e5e4` (merge del PR #21, stock-cuarentena-merma). **Tarea sólo documental:** sin código, SQL, migraciones, pruebas, Supabase, frontend, Vercel, staging ni producción. Sin commit hasta la revisión humana.

### Origen
Reunión con el cliente, registrada el 25/10/2026. Decisiones confirmadas:
- **Fiambres por peso:** ya no se venden por pieza ni media pieza; se venden por peso, expresado en kg con cantidades fraccionarias (por ejemplo, `28,680 kg`, `47,300 kg`; son evidencia de precisión, no fixtures) y con precio por kg.
- **Presupuestos:** nuevo requisito. Encabezado con `PRESUPUESTO`, número, fecha, hora, nombre del cliente, cuenta (si tiene) y DNI. Tabla con Cantidad (kg), Código, Descripción, Precio, % IVA e Importe. **Sin descuentos.** **IVA 21% sólo visual** (no se calcula, suma, resta ni desglosa). Importe = cantidad × precio y total = suma de importes. No es factura y no integra ARCA.

Decisiones humanas tomadas en esta tarea (AskUserQuestion, 25/10/2026):
- **ADR-005 APROBADA**, incluida la representación canónica en gramos enteros. No autoriza migraciones ni implementación.
- **Presupuestos en Fase 1**, con entrega (1A/1B) pendiente.
- Generan presupuestos **dueño y encargado**; el **vendedor/piloto queda pendiente**.
- Un presupuesto admite productos **`peso` y `unidad`**.

### Qué se hizo
- **Nueva** `docs/decisions/005-fiambres-por-peso-gramos.md`:
  - forma de venta `unidad`/`peso`, kg con hasta 3 decimales en pantalla, gramos enteros como canónico, más de 3 decimales rechazado y conversión sin punto flotante;
  - dinero en `numeric(14,2)` e importe conceptual `gramos × precio_por_kg / 1000`;
  - ADR-003 reemplazada parcialmente; consecuencias sobre productos, ledger, carga, ventas, retornos, rendición, precios, pruebas y prototipo/`localStorage`;
  - pendientes D-R1–D-R4 y fuentes oficiales.
- `BLUEPRINT.md` v2.0 → **v2.1**:
  - §2 (unidades y presupuestos), §4 (productos y fila Presupuestos), §5 (presupuesto ≠ factura);
  - §7.1 reescrita, §7.4 (gramos), §7.5 (ítems de venta), **§7.10 Presupuestos (nueva)**;
  - §8 (`productos`, `clientes`, `venta_items`, `presupuestos`, `presupuesto_items` y restricciones), §9 (roles), §11 (kg en reportes), §12 (pruebas de peso y de presupuestos; se quitan las de media pieza);
  - §14 (Presupuestos y cambio de modelo a peso), §15 (pendientes nuevos), §16 (glosario), §17;
  - desambiguación «presupuesto» (módulo) ↔ «cotización comercial del proyecto».
- `docs/PRD.md` 0.10 → **0.11**: §0, RF-01, **RF-12 y §7.1 Presupuestos**, roles, §9, §13, §17, §21 (pendientes 15–19), §22.
- `docs/decisions/README.md`: índice con ADR-005 y estado de ADR-003.
- Notas de supersesión **sin cambiar el contenido histórico**: `003-precio-derivado-media-pieza.md`, `002-precios-independientes-pieza-media.md` y `docs/requirements/migracion-unidades-prototipo.md`.

### Skills usadas
- **source-driven-development:** se verificaron en la documentación oficial de PostgreSQL:
  - `numeric` es exacto y es el recomendado para importes;
  - `real`/`double precision` son inexactos;
  - rangos de `integer`/`bigint`;
  - redondeo implícito al guardar con más escala que la declarada;
  - `round(numeric)` rompe los empates alejándose de cero.

  Además, en MDN, `Number.MAX_SAFE_INTEGER`. Se comprobó en Node que `1.005 * 1000` da `1004.9999999999999`. No se encontró razón para preferir otra representación exacta: kg en `numeric(…,3)` también es exacto, pero rompe la invariante entera del ledger ya implementado (ADR-005 §3).
- **api-and-interface-design:** modelo conceptual de presupuesto separado de venta (sin operación de stock, pagos ni jornada); snapshot de cliente y producto frente a referencias mutables; IVA como dato informativo nombrado sin ambigüedad; sin campos de descuento «por si acaso»; número, hora y snapshot asignados por el servidor (consideración técnica marcada PROPUESTA TÉCNICA NO APROBADA). Sin API ni SQL definitivos.
- **grilling:** una ronda de cuatro preguntas (estado de la ADR, fase, roles y tipos de producto). El resto de las ramas abiertas se registró como pendiente, sin asumir respuestas.

### Pendientes registrados (no resueltos)
- D-R1, redondeo monetario por peso.
- D-R2, pesaje en la operación.
- D-R3, tolerancia de diferencias de pesaje.
- D-R4, datos locales/staging en medias piezas.
- Presupuestos: numeración (secuencia, formato, reinicio, unicidad, anulación), ciclo de vida, vigencia, conversión a venta, vendedor/piloto, cliente no registrado, edición manual del precio y entrega.
- Clientes: DNI y cuenta (hoy no existen en `public.clientes`) y significado de «cuenta».

### Contradicciones detectadas fuera del alcance editado (no modificadas)
- `AGENTS.md` §10: «Los fiambres se venden por pieza y media pieza.» Contradice ADR-005; el Blueprint prevalece (`AGENTS.md` §1.1). Su corrección requiere autorización.
- `docs/architecture/analisis-base-datos.md` (v0.2, líneas 43 y 141): `forma_venta (unidad/pieza)` y «medias piezas». Es un análisis derivado y queda desactualizado.
- `INVENTARIO_ETAPA_0.md`: referencias a `kg` y a la media pieza como evidencia del estado del 16/10/2026. Histórico, no se toca.
- Código y SQL locales (`productos`, `cantidades.ts`, `precios.ts` y sus pruebas): siguen con pieza/media pieza. Esperado: lo cambia la tarea de implementación de ADR-005.

### Cómo se verificó
`git diff --check`, `git status --short`, `git diff --stat`, y una búsqueda global con `rg` de pieza/media/kg/presupuesto/descuento/IVA/factura clasificada por vigencia. No se corrió la suite técnica: la tarea es docs-only y no toca código.

### Riesgos
- Hasta implementar ADR-005, el SQL local y el prototipo contradicen el Blueprint.
- Las Etapas 3–4 (carga, ventas, conteos) no deben diseñarse sobre medias piezas.
- La implementación toca `movimientos_stock`, productos y precios, así que **corresponde security review**.

**STAGING: NOT TOUCHED · PRODUCTION: NOT TOUCHED · CODE/SQL/TESTS: NOT MODIFIED · COMMIT: NOT CREATED.**

---
## 25/10/2026 — Etapa 2 — Stock, slice 2: stock-cuarentena-merma (local; sin commit)

**Rama:** `feat/stock-cuarentena-merma-etapa-2` desde `main` = `d1ce951cf82984a403606e452ce0064de3773ef2` (merge del PR #20, stock-ingreso) · **Autorización humana explícita:** implementar el slice 2 de la Etapa 2 en local con las decisiones D1–D9. **No autorizado y no realizado:** staging, producción, push, PR, merge, deploy ni commit. El preámbulo de `AGENTS.md` §1.3 se presentó antes del primer cambio.

### Objetivo
Dos operaciones que debitan el depósito sobre el ledger del slice 1 (Blueprint §7.4, §7.7, §7.9.1): `mover_a_cuarentena` (depósito → cuarentena) y `registrar_merma` (depósito → exterior), con idempotencia, saldo nunca negativo y serialización por advisory lock.

**Fuera de alcance (no implementado):** `cuarentena_apta`, merma desde cuarentena, camión como origen, carga, jornadas, ventas, devoluciones, conteos, regularizaciones, `ajuste`, negativo transitorio, frontend y Fase 2.

### Decisiones humanas aprobadas (dominio Stock; registradas en ADR-001 §18.3, slice 2)
- **D1:** ambas RPC para dueño y encargado, sin diferencias; vendedor → `PT403`. **D2:** motivo de cuarentena obligatorio (`btrim`; vacío → `PT400 stock_motivo_invalido`). **D3:** origen sólo depósito (cuarentena/camión → `PT400 stock_origen_invalido`). **D4:** sin merma desde cuarentena. **D5/D6:** `motivo_codigo` con el catálogo literal de Blueprint §7.7; `otro` exige texto; NULL para ingreso y cuarentena. **D7:** índice único parcial de operaciones unitarias. **D8:** la policy exige destino depósito para el ingreso. **D9:** una migración y un archivo de tests (precisión humana posterior: D9 no limita los archivos de prueba; los de aislamiento van aparte, ver más abajo).
- **Huellas v1:** `v1|a_cuarentena|<producto>|<origen>|<cantidad>|<m>` y `v1|merma|<producto>|<origen>|<cantidad>|<codigo>|<m>`.
- **Lock:** `pg_advisory_xact_lock(hashtextextended('stock:'||empresa||':'||origen||':'||producto, 0))`, uno por RPC, después de idempotencia + producto + origen y antes de leer el saldo.
- **Aislamiento (corrección pre-commit autorizada):** las dos RPC exigen `READ COMMITTED` (P13-stock) y, con cualquier otro nivel, fallan cerradas con `PT500 stock_error_interno` como primera comprobación, sin cambiar el aislamiento del caller.

### Migración `20261025033454_stock_cuarentena_merma.sql`
- Guardia `current_user = postgres` y verificación previa de que los datos existentes (sólo ingresos, un movimiento por operación) cumplen el modelo nuevo.
- `operaciones_tipo_valido` y `movimientos_stock_tipo_valido`: `ingreso`, `a_cuarentena`, `merma`. `movimientos_stock_forma_por_tipo` con la forma de cada tipo. Columna `motivo_codigo text` + `movimientos_stock_motivo_codigo_valido` (catálogo) + `movimientos_stock_motivo_por_tipo`. Índice `movimientos_stock_operacion_unitaria_unica`.
- `propietario_rpc`: `INSERT (motivo_codigo)` agregado; sin UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN. Sin excepción nueva para `service_role` (P11).
- Policies de INSERT de `propietario_rpc` endurecidas: operaciones con los 3 tipos; ledger con tipo igual al de la operación (misma empresa y actor) y forma por tipo contra `public.ubicaciones` de la empresa (ingreso → depósito; `a_cuarentena` depósito → cuarentena; merma depósito → NULL).
- `privado.mover_a_cuarentena` / `privado.registrar_merma` (SECURITY DEFINER de `propietario_rpc`, `search_path=''`) y fachadas `public` SECURITY INVOKER de `postgres` (EXECUTE sólo `authenticated`, sin sobrecargas). Orden: `transaction_isolation = 'read committed'` (si no, `PT500 stock_error_interno`; `privado.usuario_actual()` se evalúa después, no en el `DECLARE`) → identidad/perfil/rol → clave, cantidad, motivo/código, producto y origen no NULL → huella → reserva `ON CONFLICT DO NOTHING` / replay → producto de la empresa y activo → origen de la empresa y de tipo depósito → (cuarentena) destino único resuelto en el servidor → lock → saldo bigint → `stock_insuficiente` → un movimiento → `operaciones.id`. Sin `WHEN OTHERS`, sin COMMIT, sin dblink; sólo violaciones de restricción/privilegio en los inserts → `PT500 stock_error_interno`.
- ACL fijada antes del `ALTER … OWNER` (O-3), CREATE temporal sobre `privado` revocado y bloque final fail-closed (seguridad, owner, `search_path`, ACL exacta, sobrecargas, grants de tablas, CREATE residual).

### Tests
- **Nuevo** `supabase/tests/stock_cuarentena_merma.test.sql` (150): catálogo (columna, constraints con su definición exacta, índice parcial, policies, fachadas e implementaciones, sin sobrecargas, sin parámetros de empresa/actor/tipo/destino/huella, grants de `propietario_rpc`, anon/`service_role` sin EXECUTE); cuarentena de dueño y encargado (1 operación + 1 movimiento, destino del servidor, motivo con trim, huella contra el literal canónico, `stock_actual` 15/5, stock exacto a 0, insuficiente sin efectos y sin reserva); orígenes cuarentena/camión/otra empresa/inexistente/NULL, producto de otra empresa/inactivo, motivo NULL/espacios, cantidades, clave NULL, empresa sin cuarentena; idempotencia (replay con stock ya insuficiente, conflicto por cantidad/origen/producto/motivo/tipo); merma con los seis códigos, texto opcional, `otro` con texto, código con `btrim`, huellas con y sin texto, código fuera del catálogo / mayúsculas / NULL / `otro` sin texto, desde cuarentena/camión/otra empresa, insuficiente, replay y conflictos; aislamiento B; autorización de ambas RPC (vendedor con metadata de dueño, privado por SQL, inactivo, sin perfil, sin `sub`, anon, `service_role`) sin efectos; replay con estado mutable (producto inactivo → mismo id; actor inactivo o degradado a vendedor → `PT403`, también en `registrar_ingreso`: cierra L-2 del slice 1); DML directo de dueño/encargado/vendedor/anon/`service_role` sobre ambas tablas sin cambios; `propietario_rpc` sin UPDATE/DELETE y policies endurecidas (D8 ingreso a cuarentena o camión, cuarentena hacia camión, desde camión, merma desde cuarentena, tipo distinto al de la operación, control positivo, D7 segundo movimiento); restricciones del ledger; atomicidad con reutilización de la clave; ningún saldo negativo.
- **Nuevos** `supabase/tests/stock_aislamiento_repeatable_read.test.sql` y `stock_aislamiento_serializable.test.sql` (16 cada uno): cada archivo abre su transacción con `begin isolation level …` antes de cualquier consulta (el nivel se fija al abrirla; por eso no comparten archivo) y verifica el nivel efectivo. Ambas RPC, por fachada y por la implementación privada, devuelven `PT500 stock_error_interno` con un pedido válido de dueño y también con entradas que sin el guard darían otro resultado: clave NULL (PT400), replay legítimo (devolvería el id), vendedor (PT403), sin `sub` (PT401). Sin efectos: operaciones y ledger idénticos (md5), ninguna clave rechazada reservada y `stock_actual` sin cambios. La reutilización de la misma clave en `READ COMMITTED` después del rechazo no cabe en un solo archivo pgTAP (`plan()`/`finish()` viven en la transacción del archivo); se verificó con el arnés de concurrencia.
- **Actualizados sin debilitar:** `stock_ingreso` (columnas con `motivo_codigo`, constraints exactas, columnas INSERT de `propietario_rpc`; la FK compuesta de producto se prueba con una operación sin movimiento para que no intervenga D7; el movimiento hacia una ubicación de B ahora lo rechaza la RLS de D8; la merma con destino se rechaza por forma), `productos_catalogo` y `camiones_catalogo` (DEFINER 11 → 13; auxiliares), `grants_default_privileges` (firmas de `authenticated` 22 → 26). `hardening_adr001` sin cambios (no hay tablas nuevas).

### Hallazgo de la autorrevisión: aislamiento transaccional (corregido antes del commit)
- Bajo `READ COMMITTED` el advisory lock serializa el débito correctamente: cada sentencia toma una instantánea nueva y el saldo se lee después de obtener el lock.
- Bajo `REPEATABLE READ` o `SERIALIZABLE` la instantánea queda fija desde la primera consulta de la transacción: S2 esperaba el lock (~1,5 s) y después leía el saldo previo al commit de S1. Con 10 unidades, 7 ‖ 7 confirmaban ambas y el saldo quedaba en **−4** (en `SERIALIZABLE` no hubo `40001`: hay un único conflicto lectura-escritura). No es un defecto de esos niveles de PostgreSQL, sino la combinación de una instantánea fija con un algoritmo diseñado para `READ COMMITTED`. Por la API no era alcanzable (PostgREST usa `read committed` y el cliente no puede cambiarlo), pero el código no lo exigía.
- Corrección: guard al comienzo de `privado.mover_a_cuarentena` y `privado.registrar_merma` (`pg_catalog.current_setting('transaction_isolation') <> 'read committed'` → `PT500 stock_error_interno`, sin `DETAIL`/`HINT`), antes de `privado.usuario_actual()`, perfiles, idempotencia, producto, ubicación, lock y saldo. Error público reutilizado (no amplía P16-stock). No cambia el aislamiento del caller. El `DECLARE` sólo conserva `btrim` de los parámetros.
- Manejo de errores sin cambios: el guard no está dentro de ningún bloque `EXCEPTION`; los únicos handlers siguen envolviendo los dos `INSERT` (4 clases de restricción/privilegio). Sin `WHEN OTHERS`; `40001`, `40P01`, `55P03` y `57014` se propagan.

### Concurrencia (arnés ad hoc no versionado, dos conexiones reales, base local)
No hay directorio `scripts/` y `supabase/tests/` sólo contiene `*.test.sql`; el arnés quedó fuera del repositorio. S1 retiene el lock 2 s; S2 arranca 0,5 s después. Resultados con el guard:
| Caso | Resultado |
|---|---|
| C1a cuarentena 7 ‖ merma 7 sobre 10 (`READ COMMITTED`) | una OK, la otra `stock_insuficiente` tras esperar ~1,52 s; saldo 3 |
| C1b merma 7 ‖ cuarentena 7 sobre 10 (`READ COMMITTED`) | ídem; saldo 3 |
| C2 cuarentena 4 ‖ merma 5 sobre 10 | ambas OK (la segunda espera ~1,53 s); saldo 1 |
| C1a/C1b con S2 en `REPEATABLE READ` | S2 `PT500 stock_error_interno` sin esperar el lock (0,00 s); saldo 3 |
| C1a/C1b con S2 en `SERIALIZABLE` | ídem; saldo 3 |
| Misma clave: rechazo en `REPEATABLE READ`/`SERIALIZABLE` y reintento en `READ COMMITTED` (ambas RPC) | 1º `PT500`, clave no reservada; 2º OK con la misma clave, 1 movimiento |
| C3 otro producto (clave de lock independiente) | sin esperar el lock ajeno: ~0,01 s (tolerancia < 1,0 s con S1 reteniendo 2 s); PASS |
| C4 misma clave y mismo payload | S2 espera ~1,53 s y devuelve el mismo `operaciones.id`; exactamente 1 movimiento; saldo final 7; PASS |

### Mutaciones (arnés ad hoc no versionado)
pgTAP sobre `stock_cuarentena_merma`, `stock_ingreso`, `ubicaciones` y los dos archivos de aislamiento, en transacción revertida; control 383 `ok` (150 + 119 + 82 + 16 + 16), 0 `not ok`, 0 errores SQL. Las de lock (1, 2 y 10) se aplicaron de forma persistente y se corrió el arnés de concurrencia en `READ COMMITTED`; se restauró y la base se reinició con `db reset`. Ninguna detección proviene de SQL roto ni de errores de setup; las fallas en cascada se indican.
| # | Mutación | Resultado |
|---|---|---|
| 1 | sin lock (cuarentena) | **detectada:** C1a, C1b y cuarentena ‖ cuarentena sin espera (0,01 s), ambas OK, saldo −4 |
| 2 | saldo leído antes del lock (cuarentena) | **detectada:** C1b y cuarentena ‖ cuarentena: S2 espera ~1,53 s y aun así confirma, saldo −4 (lectura vieja, no falta de lock). C1a no la detecta por el orden |
| 3 | sin chequeo de suficiencia (ambas) | **detectada:** 5 aserciones (`stock_insuficiente`, sin efectos, saldo nunca negativo) |
| 4 | cuarentena permitida como origen | **detectada:** «origen cuarentena: PT400» |
| 5 | vendedor permitido (ambas) | **detectada:** 4 aserciones de PT403 del vendedor |
| 6 | sólo se quita el filtro de empresa del origen en la RPC (ambas) | **equivalente funcional bajo la RLS actual:** 0 fallas y 0 diferencias en 14 casos (7 × 2 RPC: mismo SQLSTATE y mensaje, sin efectos). La policy SELECT de `propietario_rpc` sobre `ubicaciones` (sin BYPASSRLS; perfil 1:1 cuya empresa queda fijada por el `KEY SHARE` de `operaciones_actor_fk` desde la reserva) ya oculta las filas de otra empresa. Canal temporal residual medido en local: ~48 µs más para un UUID existente en otra empresa que para uno inexistente (6 rondas × 5000 llamadas; en el control la diferencia es ruido). El filtro se conserva como defensa en profundidad y para homogeneizar el comportamiento; no se agregó un test de tiempo |
| 6p | sólo se abre la policy SELECT de `propietario_rpc` sobre `ubicaciones` (filtro de la RPC intacto) | **equivalente funcional bajo el filtro de la RPC:** 0 fallas |
| 6b | filtro de la RPC quitado + policy abierta | **detectada** por el aislamiento entre empresas: «origen de otra empresa: PT404» y «merma desde un depósito de otra empresa» |
| 7 | huella sin origen (cuarentena) | **detectada:** «conflicto por origen» y literal canónico |
| 8 | merma con destino (CHECK) | **detectada:** «una merma con destino se rechaza (forma)» y constraints exactas en ambos archivos; en cascada, 145 (23505 por D7) y 146/147/149 (PT409: la merma del 139 consumió 1 unidad) |
| 9 | policy `a_cuarentena` sin exigir destino cuarentena | **detectada:** «a_cuarentena de depósito hacia un camión: rechazado por RLS»; en cascada, el control positivo (D7) |
| 10 | clave de lock distinta en cuarentena | **detectada:** C1a y C1b sin espera, saldo −4; cuarentena ‖ cuarentena sigue serializada (es la clave distinta, no la falta de lock) |
| 11 | sin guard de `transaction_isolation` (ambas) | **detectada:** 15/16 aserciones en cada archivo de aislamiento (todas menos la del nivel efectivo) |

**Resumen:** 10/10 mutaciones no equivalentes detectadas (1–5 y 7–11); 6 y 6p son funcionalmente equivalentes entre sí (cada capa cubre a la otra) y quedan fuera del denominador; 6b, defensa en profundidad, detectada. Las mutaciones 1, 2 y 10 no las detecta pgTAP: sólo el arnés de concurrencia.

### Verificación (local)
| Verificación | Resultado |
|---|---|
| `git diff --check` | exit 0 |
| `npx supabase db reset` | OK, 10 migraciones + seed |
| `npx supabase test db` | **PASS, 942/942** en 11 archivos (+150 de `stock_cuarentena_merma`, +16 + 16 de aislamiento) |
| `npx supabase db lint` | «No schema errors found» |
| `npx supabase db advisors --local` | «No issues found» |
| typecheck / lint / build | exit 0 / exit 0 / exit 0 (gate previo a la corrección de aislamiento; la corrección no toca frontend) |
| Vitest | 25 archivos / 805 tests (ídem) |
| Playwright | 76/76 (ídem) |

### Riesgos y pendientes
- El filtro de empresa del origen en la RPC y la RLS de `ubicaciones` se cubren mutuamente; quitar sólo uno de los dos no cambia el resultado funcional (mutaciones 6 y 6p). Quitar el filtro de la RPC agregaría el canal temporal de ~48 µs.
- Las fixtures de cuarentena dependen de la cuarentena única por empresa (`ubicaciones_fija_unica`); sin cuarentena la RPC falla cerrado (`PT500`).
- **MEDIUM conocido:** las mutaciones 1, 2 y 10 sólo las detecta el arnés de concurrencia, que no está versionado. Además el CI no ejecuta Supabase (ni pgTAP ni el arnés). La tolerancia de C3 depende del tiempo.
- Superficie sensible (ledger, RLS, grants, SECURITY DEFINER, idempotencia, concurrencia): **corresponde security review** y auditoría independiente del hash que se commitee. Staging de ubicaciones + stock-ingreso sigue pendiente de autorización.

**STAGING: NOT TOUCHED · PRODUCTION: NOT TOUCHED · REMOTE ACTIONS: NONE · SECRETS EXPOSED: NO.**

---
## 25/10/2026 — Etapa 2 — Stock, slice 1: stock-ingreso (local; sin commit)

**Rama:** `feat/stock-ingreso-etapa-2` desde `main` = `30451f4d090a8d824df23d939b087b4b313e91ec` (merge del PR #19, ubicaciones) · **Autorización humana explícita:** implementar el slice 1 de la Etapa 2 en local con las decisiones E1–E18 y la huella v1. **No autorizado y no realizado:** staging, producción, push, PR, merge, deploy ni commit. El preámbulo de `AGENTS.md` §1.3 se presentó antes del primer cambio.

### Objetivo
Primer slice de la Etapa 2 (Blueprint §14): el ledger `movimientos_stock` como única fuente de verdad del stock (§7.4), `operaciones` como ejecución lógica idempotente (§7.9.1), el saldo derivado `stock_actual` (§8, `saldos_stock` [DERIVADA]) y la primera operación real, `registrar_ingreso` (exterior → depósito).

**Fuera de alcance (no implementado):** carga, jornadas, ventas, retornos, conteos, rendiciones, devoluciones, `cuarentena_apta`, `mover_a_cuarentena`, merma, regularizaciones, `ajuste`, retiros, gastos, vencimientos, negativo transitorio, frontend y Fase 2.

### Decisiones humanas aprobadas (dominio Stock; registradas en ADR-001 §18.3)
- **E1/P10:** sólo `registrar_ingreso`. **E2:** dueño y encargado; el vendedor no. **E3:** motivo opcional, `btrim`, vacío → NULL. **E4:** leen `operaciones`, `movimientos_stock` y `stock_actual` sólo dueño y encargado de la empresa con perfil activo.
- **P12 (E5–E8):** `UNIQUE (empresa_id, actor_id, idempotency_key)`, clave `uuid`, el tipo fuera del UNIQUE y dentro de la huella, retención indefinida, sin columna de resultado (el resultado del replay es `operaciones.id`).
- **Huella v1:** SHA-256 hex en minúsculas de `v1|ingreso|<producto uuid>|<cantidad>|<motivo>` con `<motivo>` = `-` si es NULL y `+` + motivo normalizado si no; un cambio de semántica crea `v2`.
- **P13 (E9, E10):** `READ COMMITTED` + advisory locks por empresa + ubicación + producto sólo para RPC que debitan; `registrar_ingreso` acredita y no toma locks. Contrato de reintento del cliente registrado (no implementado en este slice).
- **P16 (E11):** errores `stock_*`. **P17 (E12):** `operaciones` + `movimientos_stock` son la auditoría exitosa; sin tabla `auditoria`. **E13:** sin `jornada_id` (Etapa 3). **E14:** append-only por grants y RLS, sin trigger. **P14 (E15):** sin sobrecargas. **P15 (E16):** `idempotency_key` sólo en `operaciones`. **E18:** decisiones acotadas al dominio Stock.

### Migración `20261025021032_stock_operaciones_ingreso.sql`
- **`public.operaciones`** (`id`, `empresa_id`, `actor_id`, `tipo`, `idempotency_key`, `huella`, `creado_en`): FK a `empresas`, `UNIQUE (empresa_id, id)`, FK compuesta `(empresa_id, actor_id) → perfiles`, `UNIQUE (empresa_id, actor_id, idempotency_key)`, CHECK `tipo in ('ingreso')` y huella `^[0-9a-f]{64}$`.
- **`public.movimientos_stock`** (`id`, `empresa_id`, `operacion_id`, `tipo_movimiento`, `producto_id`, `cantidad`, `ubicacion_origen_id`, `ubicacion_destino_id`, `actor_id`, `motivo`, `creado_en`): FK compuestas a operación, producto, ubicaciones de origen y destino y actor, todas de la misma `empresa_id`; CHECK de cantidad positiva, al menos un extremo, extremos distintos, tipo `ingreso`, forma del ingreso (origen NULL, destino no NULL) y motivo normalizado; índices por `(empresa_id, destino, producto)` y `(empresa_id, origen, producto)`. Sin `saldo_actual` ni `jornada_id`.
- **`public.stock_actual`:** vista `security_invoker = true`, entradas − salidas por empresa, ubicación y producto, `cantidad bigint`. Respeta la RLS del ledger.
- **`registrar_ingreso`:** fachada `public` SECURITY INVOKER (EXECUTE sólo `authenticated`) → implementación `privado` SECURITY DEFINER de `propietario_rpc`, `search_path=''`. Orden: identidad/perfil/rol → estructura (clave, cantidad, producto no NULL) → motivo normalizado → huella v1 → reserva `ON CONFLICT DO NOTHING` / replay → producto de la empresa y activo → depósito único resuelto en el servidor (fail-closed) → un movimiento → `operaciones.id`. Las violaciones de restricción y de privilegio en los inserts se traducen a `PT500 stock_error_interno`.
- **Seguridad:** RLS sin FORCE; owner `postgres`. `authenticated` sólo SELECT (y la RLS sólo le da filas a dueño/encargado); `propietario_rpc` SELECT + INSERT por columna; nadie UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ni MAINTAIN; `anon`, `service_role` y PUBLIC sin privilegios (P11, sin excepción nueva). Policies de INSERT de `propietario_rpc`: actor = usuario actual con rol dueño/encargado activo; el movimiento cuelga de una operación de la misma empresa, del mismo actor y de tipo compatible. Grants de la implementación fijados antes del `ALTER … OWNER` (O-3); CREATE temporal sobre `privado` revocado.
- **Verificación fail-closed** al final: owner, RLS, grants de tablas y vista, `security_invoker`, atributos y ACL de fachada e implementación, sin sobrecargas y sin CREATE residual.

### Tests
- **Nuevo** `supabase/tests/stock_ingreso.test.sql` (119): catálogo exacto (columnas, tipos, defaults, constraints con su definición, índices, owner, RLS sin FORCE, policies, grants por rol y por columna, PUBLIC, vista `security_invoker`, fachada INVOKER e implementación DEFINER con owner, `search_path` y ACL, sin sobrecargas, sin parámetros de empresa/ubicación/actor/tipo/huella); ingreso de dueño y encargado (1 operación + 1 movimiento, actor, empresa y depósito del servidor, origen NULL, motivo con trim o NULL); huella v1 contra el literal canónico, NULL vs `-`, cambio por cantidad/producto/motivo; saldo 10 + 5 = 15 igual a la suma del ledger; lectura (vendedor con metadata falsa, dueño de B, perfil inactivo y sin perfil en 0; anon 42501); rechazos sin efectos (vendedor, privado llamado por SQL, inactivo, sin perfil, sin `sub`, anon, producto de otra empresa / inexistente / NULL, inactivo, cantidad 0 / negativa / NULL, clave NULL, empresa sin depósito); el rechazo no deja reserva; idempotencia (mismo id, normalización previa, conflicto por cantidad/producto/motivo/NULL, replay válido con el producto desactivado, otro actor con la misma UUID); append-only y escritura directa para dueño, encargado, anon, `service_role` y `propietario_rpc`; cruces de empresa (operación A→B, producto B, ubicación B, operación de otro actor, operación de B, vendedor) rechazados por RLS o FK compuesta; restricciones del ledger; atomicidad (si falla el movimiento no queda la operación ni cambia el saldo); otra empresa en su propio depósito.
- **Listas cerradas actualizadas (sin debilitar):** `productos_catalogo` y `camiones_catalogo` (funciones DEFINER: +`privado.registrar_ingreso`; auxiliares), `grants_default_privileges` (firmas ejecutables por `authenticated`: 20 → 22; matriz con `operaciones` y `movimientos_stock`; PUBLIC también sobre `stock_actual`), `hardening_adr001` (P11 sobre las tablas nuevas; +1 aserción de comportamiento).
- **Concurrencia (arnés ad hoc, dos sesiones reales):** misma clave y mismo payload → la segunda espera ~2 s en el `ON CONFLICT` y devuelve el mismo `operaciones.id` (1 operación, 1 movimiento); misma clave con otra cantidad en paralelo → `stock_conflicto_idempotencia`.

### Verificación (local)
| Verificación | Resultado |
|---|---|
| `git diff --check` | exit 0 |
| `npx supabase db reset` | OK, 9 migraciones + seed |
| `npx supabase test db` | **PASS, 760/760** en 8 archivos (stock 119, ubicaciones 82, clientes 183, productos 125, camiones 113, auth 55, hardening 51 con 8 SKIP, grants 32) |
| `npx supabase db lint` | «No schema errors found» |
| `npx supabase db advisors --local` | «No issues found» |
| typecheck / lint / build | exit 0 / exit 0 / exit 0 |
| Vitest | 25 archivos / 805 tests |
| Playwright | 76/76 |

**Mutaciones** (arnés ad hoc no versionado, en transacción revertida, sobre `stock_ingreso` + `grants_default_privileges` + `hardening_adr001`). Control: 202 `ok`, 0 `not ok`. **7/7 detectadas:** FK compuesta de producto → simple: 3; sin `UNIQUE` de idempotencia: 15 (más errores SQL: el `ON CONFLICT` de la RPC deja de tener destino); INSERT a `authenticated`: 3; policy de SELECT sin rol: 2; vista no `security_invoker`: 5; sin chequeo de producto activo: 6; huella sin cantidad: 4. Después, `supabase test db` 760/760.

### Riesgos y pendientes
- El destino «depósito» del ingreso lo garantiza la RPC y la policy, no un constraint (forzarlo exigiría una FK que incluya `tipo`).
- Un replay exige el rol vigente: si el actor deja de ser dueño/encargado o se desactiva, su replay recibe `PT403` (prioriza autorización sobre devolver el resultado).
- La suma sobre el ledger crece con el tiempo; los índices compuestos alcanzan para la escala de Fase 1; materialización = optimización futura (§8).
- Las RPC que debiten (slice 2) deben tomar el advisory lock; requieren su propio test de concurrencia.
- Bootstrap de empresas: sin depósito, el ingreso falla cerrado (`PT500 stock_ubicacion_no_configurada`).
- Superficie sensible (ledger de stock, RLS, grants, SECURITY DEFINER, idempotencia, concurrencia): **corresponde security review** y auditoría independiente del hash que se commitee.

**STAGING: NOT TOUCHED · PRODUCTION: NOT TOUCHED · REMOTE ACTIONS: NONE · SECRETS EXPOSED: NO.**

---
## 25/10/2026 — Slice Etapa 1: ubicaciones (local; sin commit)

**Rama:** `feat/ubicaciones-etapa-1` desde `main` = `282c85c5df1e15147148e2538cc69b806bac4e92` · **Autorización humana explícita:** implementar el slice `ubicaciones` (cambio de esquema y seguridad) exclusivamente en local, con las decisiones D1–D6. **No autorizado y no realizado:** staging, producción, push, PR, merge, deploy ni commit. El preámbulo de `AGENTS.md` §1.3 se presentó antes del primer cambio.

### Objetivo
Último componente de la Etapa 1 (Blueprint §14): las ubicaciones internas de stock de Fase 1 — `deposito`, `cuarentena` y `camion` — con aislamiento por `empresa_id` (Blueprint §7.2, §7.3, §8) y preparadas para que `movimientos_stock` (Etapa 2) las referencie por `(empresa_id, id)`. Merma y cliente **no** son ubicaciones.

**Fuera de alcance (no implementado):** `movimientos_stock`, operaciones, saldos, ingresos, carga, jornadas, ventas, conteos, rendiciones, devoluciones, mermas, retiros, gastos, vencimientos y frontend.

### Decisiones humanas aprobadas (D1–D6)
- **D1:** depósito y cuarentena (uno de cada uno por empresa) por backfill + seed/bootstrap explícito; **sin trigger**.
- **D2:** `privado.crear_camion(text,text)` crea la ubicación del camión en la **misma transacción**; backfill para camiones existentes.
- **D3:** `creado_en`, **sin `creado_por`**.
- **D4:** dueño, encargado y vendedor/piloto con perfil activo leen todas las ubicaciones de su empresa (sin filtro por rol ni por jornada).
- **D5:** inmutables: sin `activo`, sin UPDATE ni DELETE.
- **D6:** `tipo text` con CHECK, no enum.

### Migración `20261025010315_catalogo_ubicaciones.sql`
- `public.ubicaciones (id, empresa_id, tipo, camion_id, creado_en)`; FK a `empresas` y FK compuesta `(empresa_id, camion_id) → camiones (empresa_id, id)`, ambas `ON DELETE RESTRICT`; `UNIQUE (empresa_id, id)` y `UNIQUE (empresa_id, camion_id)`; CHECK de tipo y de coherencia `(tipo = 'camion') = (camion_id IS NOT NULL)`; índice único parcial `(empresa_id, tipo) WHERE camion_id IS NULL`. Sin `nombre`, `activo`, `saldo_actual` ni `creado_por`.
- **Seguridad:** RLS habilitada sin FORCE; owner `postgres`. `revoke all` a PUBLIC, `anon`, `authenticated` y `service_role`; `authenticated` sólo SELECT; `propietario_rpc` SELECT + INSERT de `(empresa_id, tipo, camion_id)`; nadie tiene UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ni MAINTAIN. `service_role` sin privilegios (P11, sin excepción nueva). Policies: `ubicaciones_select_empresa` (authenticated, perfil activo de la misma empresa), `ubicaciones_select_propietario_rpc` y `ubicaciones_insert_propietario_rpc` (sólo `tipo = 'camion'` con camión de la misma empresa y actor dueño activo: depósito y cuarentena nunca se crean por RPC).
- **Backfill** idempotente (`ON CONFLICT … DO NOTHING` dirigido al índice parcial y a `(empresa_id, camion_id)`).
- **`crear_camion`:** redefinida con el patrón O-3 (CREATE temporal sobre `privado`, `SET ROLE propietario_rpc`, `CREATE OR REPLACE`, `RESET ROLE`, revoke inmediato). Misma firma, contrato, errores, validaciones, owner, SECURITY DEFINER, `search_path=''` y ACL; después del alta del camión inserta su ubicación dentro del mismo bloque (una violación de restricción de ubicaciones se informa como `camion_error_interno`). La fachada no cambia.
- **Verificación fail-closed** al final: exactamente un depósito y una cuarentena por empresa, exactamente una ubicación por camión, sin cruces de empresa, sin tipos ni combinaciones inválidas, owner/RLS/grants y atributos/ACL de `crear_camion`.
- **Seed:** depósito y cuarentena de las dos empresas locales, idempotente (`ON CONFLICT` dirigido); repetir el bloque no agrega filas.

### Tests
- **Nuevo** `supabase/tests/ubicaciones.test.sql` (82): backfill (conteos y repetición sin duplicar; toda empresa con un depósito y una cuarentena); catálogo exacto (columnas, ausencia de `nombre`/`activo`/`saldo_actual`/`creado_por`, constraints con su definición, índice parcial, sin otras unicidades, owner, RLS sin FORCE, policies, grants por rol y por columna, PUBLIC); constraints negativos (camion sin `camion_id`, depósito/cuarentena con `camion_id`, `merma`, `cliente`, depósito y cuarentena duplicados, segunda ubicación del mismo camión, A → camión de B); lectura de dueño, encargado, vendedor con metadata falsa, dueño de B, perfil inactivo, sin perfil y anon; escritura directa de dueño, encargado, vendedor, anon y `service_role` sin efectos; `propietario_rpc` (no depósito, no cuarentena, no vendedor, no otra empresa, no UPDATE/DELETE; control positivo); `crear_camion` (una ubicación de la misma empresa, comportamiento vigente, PT409/PT400/PT403 sin efectos, atomicidad si falla la ubicación, cambios de estado sin borrar ni duplicar, otra empresa, atributos y ACL de la función y de la fachada).
- **Actualizados (sin debilitar):** `grants_default_privileges` (la matriz y los chequeos de columnas/PUBLIC incluyen `ubicaciones`), `hardening_adr001` (P11 sobre `ubicaciones`; +1 aserción de comportamiento), `camiones_catalogo` (+1: el alta crea su ubicación).

### Verificación (local)
| Verificación | Resultado |
|---|---|
| `git diff --check` | exit 0 |
| `npx supabase db reset` | OK, 8 migraciones + seed |
| `npx supabase test db` | **PASS, 640/640** en 7 archivos (ubicaciones 82, clientes 183, productos 125, camiones 113, auth 55, hardening 50 con 8 SKIP, grants 32) |
| `npx supabase db lint` | «No schema errors found» |
| `npx supabase db advisors --local` | «No issues found» |
| `npm run typecheck` / `npm run lint` | exit 0 / exit 0 |
| `npm test` | 25 archivos / 805 tests |
| `npx playwright test` | 76/76 |
| `npm run build` | exit 0 |

**Mutaciones** (arnés ad hoc no versionado, en transacción revertida, sobre `ubicaciones` + `camiones_catalogo` + `grants_default_privileges` + `hardening_adr001`). Control: 277 `ok`, 0 `not ok`. **7/7 detectadas:** FK simple en lugar de compuesta → 5; sin índice parcial → la suite aborta con error (el `ON CONFLICT` del backfill requiere el índice) antes de las aserciones de duplicados; INSERT directo a `authenticated` → 4; policy INSERT que permite depósito → 3; SELECT a `service_role` → 7; SELECT sin aislamiento por empresa → 5; `crear_camion` sin la ubicación → 6. Después, `supabase test db` 640/640.

### Riesgos y pendientes
- **Bootstrap de empresas:** una empresa creada después de esta migración necesita su depósito y su cuarentena por el bootstrap administrativo (D1); el modelo no lo fuerza. Las RPC de la Etapa 2 deberán fallar cerrado si faltan.
- **Acoplamiento de reglas:** la policy de INSERT exige dueño, igual que `exigir_dueno_camiones`; si cambia el permiso de alta de camiones, hay que cambiar ambas. Un rechazo por RLS dentro de `crear_camion` no se traduciría a un código estable (hoy no puede ocurrir).
- **Runner de staging de camiones:** borra camiones antes que sus ubicaciones; con la FK `restrict` hay que ajustarlo antes de la validación en staging.
- El backfill está replicado en `ubicaciones.test.sql`; si cambia en la migración, hay que actualizar el test.
- «No cargar desde cuarentena» queda para las RPC de la Etapa 2.
- Superficie sensible (esquema, RLS, grants, `propietario_rpc`, SECURITY DEFINER): **corresponde security review** y auditoría independiente del hash que se commitee.

**STAGING: NOT TOUCHED · PRODUCTION: NOT TOUCHED · REMOTE ACTIONS: NONE · SECRETS EXPOSED: NO.**

---
## 24/10/2026 — Cierre de staging: hardening ADR-001 P11/O-3/O-4 (validación controlada) — PASS

**Entorno:** staging, project ref `rtsncntppghdynzhezzg` · **Código:** `main` = `90bdaef1c8622c141add495a08b26cd42e067ff9` (merge del PR #17) · **Commit funcional auditado:** `f5d1f30c887a63602590f694a446cda318145a79` · **Autorización humana explícita:** aplicar la migración en staging (hecho por el humano) y ejecutar esta validación con fixtures controlados, transacciones revertidas y cleanup. **Producción no tocada.** Sin `db push` por parte de Claude, migraciones nuevas, cambios de código, commit, push, PR, merge ni deploy en la validación. Esta entrada complementa la del hardening («Hardening transversal ADR-001: P11 global, O-3 y O-4»), cuyas líneas «migración de hardening en staging: NO REALIZADA» y «validación post-migración: PENDIENTE» reflejan el momento de aquella entrada y quedan superadas por ésta **sólo en cuanto al estado de staging**.

**HARDENING ADR-001 VALIDADO EN STAGING.**

### Preflight y aplicación
- Verificado por el humano: el dry-run previo (`supabase db push --linked --dry-run`) mostró únicamente `20261024232059_hardening_adr001_p11_o3_o4.sql`, y `supabase db push --linked` la aplicó correctamente.
- `supabase migration list --linked`: **7/7 migraciones alineadas** local/remoto después de aplicar.
- `supabase db lint --linked`: «No schema errors found».
- `supabase db advisors --linked`: «No issues found». Los WARN **0028/0029** sobre `public.rls_auto_enable()` (O-4) **ya no aparecen**.

### Método
- Estado inicial de staging: **0** en productos, camiones, clientes, perfiles, empresas, usuarios Auth, identities, sessions, refresh tokens y `auth.audit_log_entries`. Fixtures temporales de dos empresas (B sólo como fixture adversarial) y usuarios controlados por runner (dueño, encargado, vendedor/piloto con `user_metadata` engañosa, perfil inactivo, sin perfil, dueño de B); ids y contraseñas aleatorios por corrida, no impresos.
- Permisos probados con la publishable key + JWT reales contra la Data API; la secret key sólo para probar que `service_role` no tiene acceso (salvo la excepción aprobada). SQL administrativo para catálogo, huellas y cleanup; la prueba funcional de O-4 en una transacción terminada en `ROLLBACK`.
- Runners temporales fuera del repo: uno nuevo para el hardening (incluye la regresión de productos) y los de camiones y clientes ya usados en sus cierres de staging (con la única modificación de higiene descrita abajo).

### Resultado final (segunda corrida completa): 403/403 PASS
| Runner | Resultado |
|---|---|
| Hardening (incluye productos) | **100/100 PASS** |
| Camiones | **94/94 PASS** |
| Clientes | **209/209 PASS** |

**Hardening, por gate:** PRECHECK 2/2 · P11 13/13 · O-3 16/16 · O-4 11/11 · O4_RUNTIME 2/2 · PRODUCTOS 48/48 · P11_HTTP 6/6 · CLEANUP 2/2.

### Hechos comprobados
- **P11:** `service_role` sólo conserva **SELECT sobre `public.productos`** (ACL exactamente `SELECT`, permitido también por HTTP). Sin SELECT sobre `empresas`, `perfiles`, `camiones` ni `clientes` (también rechazado por HTTP); sin INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ni MAINTAIN en las cinco tablas; sin grants por columna; sin EXECUTE sobre las 10 fachadas, las 10 implementaciones ni ningún auxiliar de `privado` (también rechazado por HTTP). Sin vías indirectas: no es miembro de ningún rol, no es owner de objetos de `public`/`privado`, sin USAGE sobre `privado` y PUBLIC sin privilegios sobre tablas ni funciones de negocio.
- **O-3:** membresía `postgres` → `propietario_rpc` con grantor `postgres`: **SET true, INHERIT false**, sin ADMIN (la fila ADMIN de `supabase_admin` sin SET ni INHERIT); ninguna fila con INHERIT; `pg_has_role(…, SET) = true` y `(…, USAGE) = false`. `anon`, `authenticated`, `authenticator` y `service_role` no pueden SET ni heredar `propietario_rpc`. `propietario_rpc` sigue NOLOGIN/NOSUPERUSER/NOBYPASSRLS/NOCREATEDB/NOCREATEROLE/NOREPLICATION, sin CREATE en `public`/`privado` y sin tablas propias. Toda función de `privado` es de `propietario_rpc` con `search_path=""`; las 10 implementaciones son SECURITY DEFINER y las 10 fachadas SECURITY INVOKER; las 5 tablas siguen siendo de `postgres`.
- **O-4:** `public.rls_auto_enable()` existe, owner `postgres`, SECURITY DEFINER, retorno `event_trigger`, `search_path=pg_catalog`; ACL `{postgres=X/postgres}`: **sin EXECUTE para PUBLIC, `anon`, `authenticated` ni `service_role`**, y la llamada explícita como `anon`/`authenticated` falla con «permission denied». `ensure_rls`: owner `postgres`, habilitado, `ddl_command_end`, tags exactos `CREATE TABLE` / `CREATE TABLE AS` / `SELECT INTO`, apunta a `rls_auto_enable()` y es su único event trigger. Ninguna función SECURITY DEFINER de `public` es ejecutable por PUBLIC ni por roles de la Data API.
- **O-4 en runtime real:** dentro de una transacción revertida, `CREATE TABLE`, `CREATE TABLE AS` y `SELECT INTO` en `public` quedaron con **RLS habilitada automáticamente**; revocar EXECUTE no afectó el event trigger. Tras el `ROLLBACK`, ninguna tabla de prueba persistió.
- **Regresiones:** productos (48/48), camiones (94/94) y clientes (209/209) mantienen el comportamiento validado antes del hardening: aislamiento cross-company (PT404 indistinguible de inexistente), perfil inactivo y usuario sin perfil sin acceso, `anon` sin acceso, `user_metadata` y headers manipulados sin efecto, escrituras directas rechazadas para todos los actores, `service_role` sin acceso (salvo SELECT de productos), `privado` no expuesto (`PGRST106`), atomicidad (huellas idénticas) y validaciones de negocio (`PT400`/`PT401`/`PT403`/`PT404`/`PT409`). `pg_graphql` sigue deshabilitado.

### Cleanup
- Conteos finales **iguales a los iniciales** (todos en 0) en los tres runners.
- Sin fixtures residuales (clientes, productos, camiones, perfiles, empresas, `auth.users`, `auth.identities`, `auth.sessions`, `auth.refresh_tokens`, `auth.audit_log_entries`); sin tablas `zz_hard_o4_*`; los runners no crean roles; sin datos persistidos por los runners.

### Incidente del runner (no es un fallo del producto)
- Primera corrida del hardening: **99/100**. El único FAIL fue un **falso negativo** de la aserción O4_RUNTIME: el producto ya había devuelto `relrowsecurity=true` para las tres tablas.
- Causa: el parser tomaba la última línea de la salida de psql (`ROLLBACK`) en lugar de la fila de resultado. Se corrigió el runner temporal fuera del repo; el resultado real de la primera corrida, reprocesado, da PASS.
- Segunda corrida completa: **100/100** (camiones y clientes, 94/94 y 209/209 en ambas corridas).

### Higiene de credenciales
- Durante el diagnóstico operativo se detectó que los runners temporales pasaban `TEST_DATABASE_URL` como argumento del proceso `psql`, visible en la lista de procesos.
- Los runners temporales se corrigieron para usar variables `PG*` del proceso hijo (la segunda corrida ya las usó). La salida de ambas corridas no contiene credenciales.
- **Acción operativa separada:** rotar la credencial de la base de staging.

### Estado y pendientes
- **HARDENING ADR-001 VALIDADO EN STAGING.** ADR-001 sigue **APROBADA PARA VALIDACIÓN CONTROLADA**; P8–P10 y P12–P17 siguen pendientes y P18 separada.
- **Producción NO validada y NO autorizada.** No hubo deploy productivo.
- Pendientes que se mantienen: rotación de la credencial de staging; M-1 (atomicidad de la migración bajo el CLI, no verificada empíricamente; la aplicación en staging fue exitosa); L-1 (las aserciones pgTAP de O-4 sólo corren contra el objeto real si existe: repetir advisors y catálogo de `rls_auto_enable` tras cambios de configuración del proyecto).

**PRODUCTION: NOT TOUCHED · VERCEL: NOT TOUCHED · CODE CHANGES: NONE · SECRETS EXPOSED IN RUNNER OUTPUT: NO.**

---
## 24/10/2026 — Hardening transversal ADR-001: P11 global, O-3 y O-4 (local; sin commit)

**Rama:** `chore/hardening-adr-001` desde `main` = `f01bad12dc253de94b4be305075a85f1b3d38cd2` · **Autorización humana explícita:** implementar sólo el hardening aprobado, con una migración local, pgTAP, mutation tests y verificaciones locales; por separado, una lectura read-only de catálogo en staging para O-4. **No autorizado y no realizado:** escrituras en staging (la migración no se aplicó allí), producción, push, PR, merge, deploy ni commit.

### Decisiones humanas aplicadas
- **P11 global:** `service_role` queda **denegado por defecto** en los objetos de negocio. Las excepciones son explícitas y nominadas; la única vigente es **SELECT sobre `public.productos`** (P11-productos). Sin EXECUTE sobre las RPC de negocio y sin MAINTAIN.
- **O-3:** `postgres` conserva **SET ROLE `propietario_rpc`** pero **no hereda** sus privilegios (`INHERIT = false`).
- **O-4:** se conservan `public.rls_auto_enable()` y el event trigger `ensure_rls`; se revoca EXECUTE a PUBLIC, `anon`, `authenticated` y `service_role`. Sin cambiar el comportamiento del trigger.
- **Registro en ADR-001:** las tres decisiones quedaron registradas en ADR-001 §18.2 (y P11 en la tabla de decisiones resueltas de §18), con la evidencia de staging de O-4. P8–P10 y P12–P17 siguen pendientes; ADR-001 sigue **APROBADA PARA VALIDACIÓN CONTROLADA**; no autoriza producción.

### Estado de staging (distinguir)
- **Lectura read-only de staging para O-4: YA REALIZADA** (24/10/2026, ver abajo).
- **Migración de hardening en staging: NO REALIZADA.**
- **Validación post-migración en staging: PENDIENTE** (requiere autorización humana).

### Evidencia read-only de staging que fundamentó O-4 (24/10/2026)
Inspección de catálogo ejecutada por el humano con un script temporal fuera del repo (`BEGIN TRANSACTION READ ONLY … ROLLBACK`; el wrapper abortaba si la conexión no correspondía al ref). Salida revisada: sin URL, credenciales ni tokens.
- Proyecto `rtsncntppghdynzhezzg`; PostgreSQL 17.11; `transaction_read_only = on` (el `default_transaction_read_only` de la sesión quedó en `off` porque la opción de conexión no se aplicó; la transacción sí fue read-only); terminada con `ROLLBACK`; exit 0; **cero escrituras**. 6 migraciones, incluida `20261024180000`.
- `public.rls_auto_enable()`: owner `postgres`, `SECURITY DEFINER`, `search_path=pg_catalog`, retorno `event_trigger`; ACL `{=X/postgres, postgres=X/postgres, anon=X/postgres, authenticated=X/postgres, service_role=X/postgres}`: EXECUTE **explícito** (entradas directas) para PUBLIC, `anon`, `authenticated` y `service_role`; `propietario_rpc` lo obtiene vía PUBLIC. El cuerpo habilita RLS en tablas nuevas de `public` (`CREATE TABLE`, `CREATE TABLE AS`, `SELECT INTO`) y registra en LOG.
- `ensure_rls`: owner `postgres`, habilitado (`O`), `ddl_command_end`, tags `CREATE TABLE` / `CREATE TABLE AS` / `SELECT INTO`, función `rls_auto_enable()`; es la única dependencia de event trigger y ningún trigger de tabla la usa.
- Default privileges de funciones: `postgres` (global y `public`) sólo `postgres=X`; `supabase_admin` en `public` da X a `anon`, `authenticated` y `service_role` (no explica esta ACL, cuyo grantor es `postgres`). `anon` y `authenticated` tienen USAGE sobre `public`: condición de los lints 0028/0029.
- **Producción no tocada.**

### Migración `20261024232059_hardening_adr001_p11_o3_o4.sql`
- **P11:** `revoke all` (incluye MAINTAIN) a `service_role` sobre `empresas`, `perfiles`, `productos`, `camiones` y `clientes`; `grant select` sobre `productos`; `revoke all` a `service_role` sobre las 20 firmas de negocio (las 10 de `privado` con `set role propietario_rpc`: sin INHERIT, un REVOKE de `postgres` sobre funciones de `propietario_rpc` no revoca nada y sólo emite WARNING).
- **O-3:** `grant propietario_rpc to postgres with inherit false, set true` (modifica la fila con grantor `postgres` de `20261023140000`; la fila ADMIN que crea PostgreSQL, grantor `supabase_admin`, no se toca).
- **O-4:** si `public.rls_auto_enable()` existe, `revoke execute … from public, anon, authenticated, service_role`; si no existe (local), no hace nada. No borra ni modifica la función ni el trigger.
- **Fail-closed:** bloques finales que abortan la migración si O-3, P11 u O-4 no quedaron en el estado aprobado (por ejemplo, si `rls_auto_enable()` tuviera otro owner y el REVOKE no surtiera efecto). La verificación de funciones de `public` se limita a las 10 fachadas nombradas, para no fallar por funciones de plataforma.
- Idempotente; exige `current_user = postgres`.

### Evidencia técnica obtenida en local (transacciones revertidas)
- `postgres` puede pasar su membresía a SET/sin INHERIT; después `pg_has_role(…, USAGE) = f`, `SET = t`, y `ALTER FUNCTION … OWNER TO propietario_rpc` sigue funcionando (con CREATE temporal sobre `privado`).
- `postgres` conserva EXECUTE efectivo sobre las implementaciones privadas, pero **vía su membresía en `authenticated`** (gestionada por la plataforma), no vía `propietario_rpc`.
- **Event triggers:** un rol sin EXECUTE sobre la función dispara igual el event trigger y la función corre como su owner (SECURITY DEFINER): el disparo no chequea EXECUTE. Una función `event_trigger` no puede invocarse directamente (`0A000`, «trigger functions can only be called as triggers»).

### Tests
- **Nuevo** `supabase/tests/hardening_adr001.test.sql` (49 aserciones): P11 por catálogo y por comportamiento (`set local role service_role`: 42501 en `empresas`/`perfiles`/`camiones`/`clientes`, SELECT de `productos` permitido, sin INSERT/UPDATE ni RPC); O-3 (fila SET/sin INHERIT, `pg_has_role`, sin EXECUTE heredado sobre un auxiliar, sin actuar como owner sin SET ROLE, owners de `privado`, SET ROLE y ALTER OWNER posibles, ningún rol de la Data API alcanza `propietario_rpc`); runtime de las tres fachadas y PT403 del vendedor; O-4: 8 aserciones condicionales (en local salen como **SKIP** explícito, no como PASS), coherencia función/trigger, invariante «ninguna DEFINER de `public` ejecutable por PUBLIC/anon/authenticated/service_role» y una réplica local que prueba que el trigger se dispara sin EXECUTE.
- **`grants_default_privileges.test.sql`:** la matriz deja de dejar sin evaluar a `service_role` sobre `empresas`/`perfiles` y suma MAINTAIN (plan sin cambios, 32).
- **`productos_catalogo.test.sql`:** la comparación `privado.usuario_actual()` vs `auth.uid()` llamaba a `usuario_actual()` como `postgres` y dependía del EXECUTE heredado (consecuencia directa de O-3). Ahora `auth.uid()` se evalúa como `postgres` y `usuario_actual()` como `propietario_rpc` (su owner); mismos cuatro casos (plan sin cambios, 125).

### Verificación (local)
| Verificación | Resultado |
|---|---|
| `git diff --check` | exit 0 |
| `npx supabase db reset` | OK, 7 migraciones + seed |
| `npx supabase test db` | **PASS, 556/556** en 6 archivos (hardening 49 con 8 SKIP, clientes 183, productos 125, camiones 112, auth 55, grants 32) |
| `npx supabase db lint` | «No schema errors found» |
| `npx supabase db advisors --local` | «No issues found» |
| `npm run typecheck` / `npm run lint` | exit 0 / exit 0 |
| `npm test` | 25 archivos / 805 tests |
| `npx playwright test` | 76/76 |
| `npm run build` | exit 0 |

**Mutation tests** (arnés ad hoc no versionado; cada mutación dentro de la transacción del test y revertida; sobre `hardening_adr001` + `grants_default_privileges`). Control: 81 `ok`, 0 `not ok`, 8 SKIP. Detectadas: INSERT de `service_role` en `empresas` → 4; MAINTAIN en `clientes` → 3; SELECT en `camiones` → 5; EXECUTE sobre `crear_cliente` → 4; INHERIT = true → 5; réplica de `rls_auto_enable` con EXECUTE a `anon` → 3; owner de `privado.crear_cliente` cambiado a `postgres` → 7. Sin falsos positivos: réplica endurecida → 0 `not ok` y 0 SKIP; réplica sin endurecer + el bloque O-4 tomado textualmente de la migración → 0 `not ok`. Después, `supabase test db` 556/556.

### Riesgos y pendientes
- **Migraciones futuras:** sin INHERIT, `postgres` no puede `CREATE OR REPLACE`, `ALTER` ni `DROP` funciones de `propietario_rpc` sin `set role propietario_rpc` (y CREATE temporal sobre `privado`). Las migraciones que modifiquen implementaciones existentes deben usar ese patrón.
- **O-4 en staging:** las aserciones condicionales no corren en staging (pgTAP es local); sus valores esperados (owner `postgres`, `search_path=pg_catalog`, `ensure_rls` habilitado) coinciden con la lectura read-only del 24/10. Si al aplicar el estado difiriera y el REVOKE no surtiera efecto, la migración aborta (fail-closed). La plataforma podría volver a conceder EXECUTE si se reconfigura la opción: repetir advisors después de aplicar.
- **Staging:** al aplicar, verificar por catálogo P11/O-3/O-4, advisors sin 0028/0029 y repetir los runners Data API de productos, camiones y clientes.
- **Producción bloqueada.** Superficie sensible (grants, `service_role`, roles, membresía, SECURITY DEFINER, RLS): **corresponde security review** y auditoría independiente del hash que se commitee.

### Desviación de proceso
El preámbulo formal de `AGENTS.md` §1.3 no se presentó antes de modificar archivos en esta tarea; el diagnóstico read-only previo contenía la información equivalente (objetivo, Blueprint, ADR-001, estado, fuera de alcance, decisiones y plan). Se detectó antes del commit y no afectó permisos, staging ni producción. En el siguiente slice el preámbulo se presenta antes del primer cambio.

**STAGING WRITES: NONE (sólo la lectura read-only de O-4) · PRODUCTION: NOT TOUCHED · REMOTE ACTIONS: NONE (de Claude) · SECRETS EXPOSED: NO.**

---
## 24/10/2026 — Cierre de staging: catálogo de clientes (validación controlada) — PASS

**Entorno:** staging, project ref `rtsncntppghdynzhezzg` · **Código:** `main` = `06ff42309d95a59ca306fe796df1e012c062ee19` (merge del PR #15) · **Commit funcional auditado:** `c8e6e770753b4907fa9dbcf52e3f4aa70990b847` · **Autorización humana explícita:** aplicar la migración en staging (hecho por el humano) y ejecutar esta validación con fixtures controlados y cleanup. **Producción no tocada.** Sin `db push` por parte de Claude, migraciones nuevas, cambios de código, commit, push, PR, merge ni deploy en la validación. Esta entrada complementa la del slice («Slice Etapa 1: catálogo de clientes»), cuya línea «STAGING: NOT TOUCHED» refleja el momento de aquella entrada y queda superada por ésta **sólo en cuanto al estado de staging**.

**STAGING VALIDATION: PASS.**

### Migración e historial
- Migración aplicada: `20261024180000_catalogo_clientes.sql`. `supabase migration list --linked`: **6/6 migraciones alineadas** local/remoto (`20261022120000`, `20261023120000`, `20261023140000`, `20261024010921`, `20261024144459`, `20261024180000`). No se volvió a aplicar nada.
- Verificado por el humano: `supabase db lint --linked` → «No schema errors found»; `supabase db push --linked --dry-run` → «Remote database is up to date.».

### Método
- Estado inicial de staging: **0** clientes, perfiles, empresas, usuarios Auth, identities, sessions, refresh tokens y filas de `auth.audit_log_entries`. Sólo se usaron fixtures controlados de esta corrida: dos empresas temporales (A y B; B sólo como fixture adversarial de aislamiento) y seis usuarios Auth temporales (dueño A, encargado A, vendedor/piloto A, perfil inactivo A con rol dueño, usuario A sin perfil, dueño B), identificables como temporales (`clientes_staging_<run>_*`, `cli-stg-<run>-*`). Ids y contraseña aleatorios por corrida, no impresos. El vendedor A tenía `user_metadata` engañosa (`rol = dueno`, `empresa_id` = empresa B). Los clientes de prueba (activo validado, inactivo validado, pendiente creado por el vendedor y cliente de B) se crearon por las propias RPC, sin depender de datos preexistentes.
- Permisos probados con `STAGING_PUBLISHABLE_KEY` + JWT reales de los usuarios fixture contra la Data API (REST/RPC). La secret key no se usó para afirmar RLS; sólo para probar que `service_role` no tiene acceso. SQL administrativo por `TEST_DATABASE_URL` (estructura, ACL, huellas de atomicidad y cleanup). El runner aborta si la URL de la API o la conexión SQL no corresponden al ref de staging; no imprime claves, JWT, contraseñas ni URLs (salida revisada: sin secretos).
- Runner temporal fuera del repo (no versionado). El cleanup corre en `finally` y borra sólo los fixtures de la corrida.

### Corridas
- **Ensayo local previo (no cuenta como validación de staging):** tres corridas contra el Supabase local para depurar el runner. Las dos primeras fallaron por **errores del runner** (tipo `"char"` sin `::text` en una consulta de catálogo; una expectativa que no contaba el alta creada por la ronda anterior de metadata), no del producto; la tercera dio 209/209.
- **Staging: una única corrida, 209/209 PASS.**

### Resultado por gate
| Gate | Aserciones | Resultado |
|---|---|---|
| TABLE | 14 | PASS |
| RLS | 3 | PASS |
| GRANTS | 5 | PASS |
| RPC TOPOLOGY | 10 | PASS |
| OWNER (propiedad de objetos) | 4 | PASS |
| DUEÑO (alta, lectura, edición) | 14 | PASS |
| ENCARGADO | 9 | PASS |
| VENDEDOR ACTIVE-ONLY | 5 | PASS |
| VENDEDOR CREATE PENDING | 2 | PASS |
| VENDEDOR MANAGEMENT DENIED | 6 | PASS |
| METADATA SPOOF | 17 | PASS |
| VALIDATION IDEMPOTENCY | 7 | PASS |
| ACTIVE/INACTIVE | 11 | PASS |
| DUPLICATES | 7 | PASS |
| CROSS-COMPANY | 17 | PASS |
| INACTIVE PROFILE | 7 | PASS |
| NO PROFILE | 5 | PASS |
| ANON | 7 | PASS |
| SERVICE_ROLE | 6 | PASS |
| DIRECT WRITES | 16 | PASS |
| PRIVATE SCHEMA | 5 | PASS |
| VALIDATIONS | 23 | PASS |
| ATOMICITY | 3 | PASS |
| GRAPHQL | 4 | PASS (deshabilitado) |
| CLEANUP | 2 | PASS |
| **Total** | **209** | **209/209** |

### Hechos relevantes comprobados
- **Estructura:** `public.clientes` con las 12 columnas del modelo (`id`, `empresa_id`, `nombre`, `comercio`, `direccion`, `telefono`, `activo`, `estado_validacion`, `creado_en`, `creado_por`, `validado_en`, `validado_por`), PK `id`, FK a `empresas`, FK compuestas `(empresa_id, creado_por)` y `(empresa_id, validado_por)` a `perfiles`, CHECK de normalización (`btrim`) de nombre/teléfono/comercio/dirección, CHECK de estado (`pendiente`/`validado`) y de coherencia pendiente/validado. El único UNIQUE además de la PK es `(empresa_id, id)`: sin unicidad comercial. Nadie operativo (`anon`, `authenticated`, `service_role`, `propietario_rpc`) tiene DELETE ni TRUNCATE. RLS habilitada sin `FORCE`, con 4 policies; la policy `clientes_select_empresa` exige empresa, `auth.uid()`, perfil activo y (`dueno`/`encargado` o `clientes.activo`). Tabla del owner de migraciones, no de `propietario_rpc`.
- **Topología RPC:** las cuatro fachadas `public` (`crear_cliente`, `actualizar_cliente`, `validar_cliente`, `cambiar_estado_cliente`) son SECURITY INVOKER, `search_path=''`, no son de `propietario_rpc` y sólo las ejecuta `authenticated`; las cuatro implementaciones `privado` son SECURITY DEFINER, de `propietario_rpc`, con `search_path=''` y sin EXECUTE para PUBLIC/anon/`service_role`; sin sobrecargas; los cuatro auxiliares privados sólo los ejecuta `propietario_rpc`. `propietario_rpc` es NOLOGIN/NOSUPERUSER/NOBYPASSRLS, sin CREATE sobre `privado` y sin tablas propias. `Accept-Profile`/`Content-Profile: privado` rechazados (`PGRST106`); `anon` sin USAGE sobre `privado`.
- **Lectura:** dueño y encargado leen exactamente los clientes de su empresa, **activos e inactivos**; el vendedor/piloto lee **sólo los activos**: el inactivo no aparece en el listado, pedido por id devuelve `[]` y el filtro `activo=eq.false` devuelve `[]`.
- **Altas:** dueño y encargado crean clientes `validado` con `creado_por = validado_por = auth.uid()`, `validado_en` del servidor y empresa derivada del perfil (con `btrim`; comercio/dirección omitidos → NULL). El vendedor/piloto crea `pendiente` con `validado_por`/`validado_en` NULL y lo puede leer.
- **Vendedor sin gestión:** `actualizar_cliente` (ficha ajena y su propia alta), `validar_cliente` y `cambiar_estado_cliente` → `PT403 cliente_no_autorizado`; huella antes/después idéntica.
- **Edición:** dueño y encargado editan los cuatro campos con `btrim`; comercio/dirección vacíos, de espacios o null → NULL; editar un pendiente no lo valida. La edición no altera `empresa_id`, `creado_por`, `creado_en`, `validado_por`, `validado_en`, `estado_validacion` ni `activo`; los parámetros protegidos extra se rechazan (`PGRST202`) sin tocar la fila.
- **Validación idempotente:** el encargado valida un pendiente del vendedor (`validado_por` = encargado, `validado_en` del servidor, autor intacto); revalidar (dueño y encargado) no falla y **conserva el primer validador y el timestamp**. Validar un inactivo no lo reactiva.
- **Activo/inactivo:** al desactivar, dueño y encargado lo siguen viendo y el vendedor deja de verlo (listado y por id); al reactivar, el vendedor vuelve a verlo.
- **Duplicados permitidos:** mismo nombre, mismo teléfono, duplicado completo (también repetido y por el vendedor) y mismos datos en otra empresa: 200, sin `PT409`.
- **Aislamiento cross-company:** dueño, encargado y vendedor de A no leen el cliente de B; B no lee A. Las operaciones de gestión de A sobre un id de B devuelven `PT404 cliente_no_encontrado` con respuesta **idéntica** a la de un id inexistente; el vendedor sobre B recibe `PT403` (sin gestión). Filas de A y B intactas.
- **`user_metadata` falso no otorga privilegios:** con la metadata engañosa en el JWT, y también tras editarla por Auth (`rol=dueno`, `empresa_id`=B, `role=service_role`) y renovar el token, el vendedor sigue siendo vendedor/piloto de A según `perfiles`: sólo activos de A, sin acceso a B, `PT403` en gestión y sus altas quedan `pendiente` en A. Headers inventados (`x-empresa-id`, `x-user-id`, `x-rol`, `request.jwt.claims`, etc.) no alteran identidad ni empresa.
- **Perfil inactivo y sin perfil:** lectura vacía; las cuatro RPC → `PT403`; sin escrituras.
- **`anon`:** sin lectura (HTTP y SQL) ni ejecución de las cuatro RPC; sin acceso a `privado`.
- **`service_role` sin acceso** (HTTP y ACL): sin SELECT, INSERT, UPDATE, DELETE (ni por columna) ni EXECUTE de las ocho firmas, coherente con la decisión del slice. P11 global sigue pendiente.
- **Escrituras directas** (INSERT/PATCH/DELETE por REST) rechazadas para dueño, encargado, vendedor, anon y `service_role`; huella idéntica.
- **Validaciones:** `PT400` (nombre/teléfono null, vacíos o de espacios en alta y edición; estado null), `PT401 cliente_no_autenticado` (JWT sin `sub`, probado por SQL con rol `authenticated`), `PT403`, `PT404` (inexistente y otra empresa). Parámetros extra (`p_empresa_id`, `p_creado_por`, `p_validado_por`, `p_estado_validacion`) rechazados (`PGRST202`); id con formato inválido → 4xx.
- **Atomicidad:** ningún intento inválido o rechazado dejó escrituras parciales (huella de A y B idéntica); nada escapó de las empresas fixture.
- **GraphQL:** `pg_graphql` **no está habilitado** (`/graphql/v1` → «pg_graphql extension is not enabled.»); sin mutación GraphQL sobre `clientes`.
- **Cleanup:** **0 residuos** de los fixtures de la corrida (clientes, perfiles, empresas, `auth.users`, `auth.identities`, `auth.sessions`, `auth.refresh_tokens` y `auth.audit_log_entries`) y **conteos finales iguales a los iniciales** (todos en 0).

### Advisors de seguridad (`supabase db advisors --linked --type security`)
- **NO BLOQUEANTE / PREEXISTENTE:** 2 WARN, ambos sobre `public.rls_auto_enable()`: **0028** (`anon_security_definer_function_executable`) y **0029** (`authenticated_security_definer_function_executable`). Corresponde al pendiente **O-4** ya registrado. **No se modificó.**
- Sin hallazgos sobre `public.clientes`, sus RPC, `privado.*`, grants ni RLS.

### Riesgos y pendientes (se mantienen)
- **ADR-001** sigue **APROBADA PARA VALIDACIÓN CONTROLADA**; P8–P17 sin resolver.
- **P11 global** (privilegios de `service_role`), **O-3** (membresía `postgres` → `propietario_rpc`) y **O-4** (`public.rls_auto_enable()`) siguen abiertos.
- **Política de duplicados** pendiente de decisión humana (hoy se permiten todos).
- `Autoventa`, `Cuentas corrientes` y `Movimientos` siguen con el catálogo demo de clientes; un cliente real no aparece ahí.
- **Producción bloqueada.** Esta validación no la habilita. La security review del commit se hizo por separado; esta validación de staging no la reemplaza ni la sustituye.

**PRODUCTION: NOT TOUCHED · VERCEL: NOT TOUCHED · CODE CHANGES: NONE · RUNNER OUTPUT: NO SECRETS PRINTED.**

---
## 24/10/2026 — Slice Etapa 1: catálogo de clientes (local; sin commit)

**Rama:** `feat/catalogo-clientes` desde `origin/main` = `5ec2ada240a15f24307e0cb078f705ef78e907c6` (merge del PR #14) · **Autorización humana explícita:** diseñar e implementar el slice en rama, con migración local, RLS, RPC, pgTAP, frontend, Vitest, Playwright, documentación y ejecución local de las verificaciones. **No autorizado y no realizado:** staging, producción, push, PR, merge, deploy ni commit. Las operaciones remotas las hace el humano.

### Objetivo y alcance
Catálogo real de clientes de Etapa 1 (Blueprint §8: `clientes` = nombre, comercio, direccion, telefono, activo, creado_por, validado_por, estado_validacion; aprobada conceptualmente; §2/§9: el vendedor/piloto crea clientes pero nunca edita fichas existentes; dueño y encargado corrigen y validan), con la Topología D de ADR-001 (fachada `public` SECURITY INVOKER → implementación `privado` SECURITY DEFINER de `propietario_rpc` → tabla con RLS). `/clientes` pasa del catálogo demo (`localStorage`) a Supabase.

**Fuera de alcance (no implementado):** cuenta corriente real, límites de crédito, historial de ventas, cobranzas, CUIT/DNI, email, GPS/geocoding, archivos, listas de precios, descuentos, ventas, pagos, jornadas, stock, ubicaciones, Fase 2, deduplicación automática, fuzzy matching, normalización o regex de teléfonos, P11 global, producción.

### Decisiones humanas de este slice
- **Campos:** `nombre` y `telefono` obligatorios; `comercio` y `direccion` opcionales. Todo texto con `btrim`; `nombre`/`telefono` no pueden quedar vacíos; `comercio`/`direccion` vacíos o de espacios → `NULL`. Sin regex ni normalización de teléfono, sin unicidad de nombre/teléfono/comercio/dirección, sin CUIT/DNI/email/crédito.
- **Duplicados:** no se bloquea ninguno (homónimos, teléfonos repetidos, duplicado completo, ni entre empresas). La política inteligente de duplicados **sigue PENDIENTE**. Por eso no existe `PT409`.
- **Validación:** estados `pendiente` | `validado`. Alta de vendedor/piloto → `pendiente`, `validado_por`/`validado_en` `NULL`. Alta de dueño o encargado → `validado`, `validado_por = auth.uid()`, `validado_en = now()` del servidor. Dueño y encargado validan un pendiente por RPC específica; vendedor/piloto no valida, no edita, no activa/desactiva.
- **Edición:** dueño y encargado editan `nombre`, `telefono`, `comercio`, `direccion`. Nunca directamente `empresa_id`, `creado_por`, `creado_en`, `validado_por`, `validado_en`, `estado_validacion`.
- **Baja:** sólo lógica por `activo`; dueño y encargado activan/desactivan; sin DELETE.
- **Lectura:** dueño y encargado leen activos e inactivos de su empresa; el vendedor/piloto lee **sólo los clientes activos** de su empresa (decisión humana posterior a la revisión independiente; ver «Corrección pre-commit»; sin restricción por jornada: las jornadas reales aún no existen). Perfil inactivo, sin perfil, anon y otra empresa: nada.
- **`service_role`:** sin privilegios sobre `clientes` ni sus RPC (P11 global pendiente; no se generaliza el SELECT de productos), igual que camiones.

### Decisiones técnicas aplicadas (no son reglas de negocio nuevas)
- `validar_cliente` es **idempotente**: validar un cliente ya validado no falla ni cambia `validado_por`/`validado_en` (conserva al primer validador). Editar un cliente no altera su validación. Validar no altera `activo`. Un cliente inactivo se puede editar y validar.
- `actualizar_cliente` reemplaza los cuatro campos editables (un `comercio`/`direccion` nulo o vacío los borra); no recibe defaults a propósito para que un borrado sea explícito.
- CHECK `clientes_validacion_coherente`: `pendiente` ⇒ sin validador ni fecha; `validado` ⇒ ambos presentes. FK compuestas `(empresa_id, creado_por)` y `(empresa_id, validado_por)` a `perfiles`: autor y validador son de la misma empresa.
- Errores estables (`cliente_*`): `PT401` no autenticado, `PT403` no autorizado, `PT404` inexistente/otra empresa (indistinguibles), `PT400` campos/estado inválido, `PT500` interno (violación de CHECK inesperada).
- RLS en tres capas: SELECT para `authenticated`; para `propietario_rpc`, SELECT por empresa, INSERT que exige rol/estado coherente (gestión → `validado` por sí mismo; vendedor → `pendiente`) y UPDATE sólo para dueño/encargado activos de la misma empresa. `propietario_rpc` inserta/actualiza sólo columnas concretas (sin `id`, `activo`, `creado_en` en INSERT; sin `empresa_id`, `creado_por`, `creado_en` en UPDATE); sin DELETE.
- Se actualizaron las listas cerradas de `camiones_catalogo`, `productos_catalogo` y `grants_default_privileges` (implementaciones SECURITY DEFINER y firmas ejecutables por `authenticated`: ahora 20, productos + camiones + clientes). No se debilitó ningún grant ni default privilege.

### Archivos
**Nuevos:** `supabase/migrations/20261024180000_catalogo_clientes.sql`; `supabase/tests/clientes_catalogo.test.sql`; `apps/web/src/lib/clientes.ts`; `apps/web/src/lib/clientes.test.ts`; `apps/web/src/hooks/useCatalogoClientes.ts`; `apps/web/tests/clientes-catalogo.spec.ts`.
**Modificados:** `apps/web/src/pages/Clientes.tsx` (reescrita sobre Supabase); `supabase/seed.sql` (fixture adversarial local: empresa `…e2`, `otraempresa.prueba` y un cliente propio, para probar aislamiento en Playwright; sólo local); `apps/web/tests/auth/cuentasPrueba.ts`; `apps/web/tests/storage-operativo-corrupto.spec.ts` (el caso `clientes` apunta a `/movimientos`, que sigue usando el demo; sin botón que bloquear, se verifica el aviso y el raw intacto); `supabase/tests/{camiones_catalogo,productos_catalogo,grants_default_privileges}.test.sql` (listas cerradas); `docs/progress-log.md`.
**Eliminado:** `apps/web/tests/catalogos-escritura-post-montaje.spec.ts` (su único caso era la edición de clientes en `localStorage`, que `/clientes` ya no hace; la frontera de escritura es ahora la RPC).

### Seguridad
Superficie sensible (RLS, RPC, roles, `SECURITY DEFINER`, grants): **corresponde security review** y auditoría independiente del hash que se commitee; no se considera cerrada sin ellas. No se tocó ADR-001 (sigue APROBADA PARA VALIDACIÓN CONTROLADA; P8–P17 sin resolver). `privado` sigue sin exponerse; `anon` y `service_role` sin EXECUTE ni privilegios; fachadas INVOKER con `search_path` vacío; sin `FORCE RLS`. Frontend: sólo `select` de lectura y `rpc`; nunca `insert`/`update`/`delete` sobre la tabla; sin secret/service key. Los botones sólo son UX: Playwright fuerza las RPC como vendedor por HTTP y verifica `PT403` y datos intactos.

### Verificación (local, desde `apps/web/` o la raíz según corresponda)
| Verificación | Resultado |
|---|---|
| `git diff --check` | exit 0 (sin espacios finales tampoco en archivos nuevos) |
| `npx supabase db reset` | OK, 6 migraciones + seed |
| `npx supabase test db` | **PASS, 500/500** en 5 archivos (clientes 176, productos 125, camiones 112, auth 55, grants 32) |
| `npx supabase db lint` | PASS, «No schema errors found» |
| `npx supabase db advisors --local` | «No issues found» |
| `npm run typecheck` | PASS |
| `npm run lint` | PASS, exit 0 |
| `npm test` (Vitest 5.0.2) | **PASS, 25 archivos / 805 tests** (37 nuevos en `clientes.test.ts`) |
| `npx playwright test` | **PASS, 75/75** (12 del spec de clientes, repetido sobre base «sucia»: pasa) |
| `npm run build` | PASS (aviso conocido de chunk > 500 kB) |

*(La tabla anterior y el párrafo siguiente corresponden a la entrega previa a la corrección pre-commit; los resultados vigentes están en «Corrección pre-commit».)*

**Mutaciones pgTAP** (arnés ad hoc no versionado, en transacción revertida; control sin mutación: 0 `not ok` / 176 `ok`; base verificada intacta después con `supabase test db` 500/500). **8/8 detectadas:** (1) `INSERT`/`UPDATE` directo a `authenticated` → 4 `not ok`; (2) `EXECUTE` a `anon` en `crear_cliente` → 1; (3) vendedor admitido por el chequeo de gestión (edita) → 7; (4) vendedor valida (chequeo de gestión omitido en `validar_cliente` + policy UPDATE abierta) → 7; (5) aislamiento por `empresa_id` eliminado en funciones y en las tres policies → 18 (la corrida aborta más adelante por errores SQL derivados de la mutación); (6) RLS deshabilitada → 15 (ídem); (7) fachada `crear_cliente` como SECURITY DEFINER → 2; (8) `service_role` con SELECT/INSERT/UPDATE → 5. Nota: igual que en camiones, quitar sólo una de las tres capas de aislamiento no altera el comportamiento observable (defensa en profundidad); la mutación (5) las quita todas.

### Convivencia con el demo (legacy)
`Autoventa`, `Cuentas corrientes` y `Movimientos` siguen leyendo el catálogo demo de clientes (`distribuidora_clientes_demo_v2`, `useClientes`/`mockClientes`) y **no ven los clientes reales**: un cliente creado en `/clientes` no aparece ahí y viceversa. La pantalla `/clientes` lo advierte al pie. No se migró cuenta corriente, ventas ni jornadas. `useClientes` y `mockClientes` se conservan para esos consumidores.

### Riesgos y pendientes
- **Política de duplicados:** pendiente de decisión humana; hoy se permiten todos los duplicados, incluidos los del vendedor (que quedan pendientes y los resuelve el encargado/dueño a ojo).
- **Datos obligatorios definitivos y límites de crédito** (Blueprint §15 punto 7): sólo se fijaron nombre y teléfono obligatorios; el crédito queda fuera.
- El vendedor/piloto lee **sólo los clientes activos** de su empresa; la restricción por jornada se decide cuando existan jornadas reales.
- Editar una ficha **validada** no la vuelve a `pendiente`.
- **P11 global**, **O-3** y **O-4** siguen abiertos; producción bloqueada; ADR-001 no cambia de estado.
- La migración **no se aplicó** en staging: queda para la validación controlada que decida el humano, con su gate funcional y `pg_graphql` verificado.

### Corrección pre-commit (revisión independiente de OpenCode: CHANGES REQUIRED)
**Hallazgo:** el vendedor/piloto podía leer clientes inactivos de su empresa. **Decisión humana aprobada:** dueño y encargado ven activos e inactivos; el vendedor/piloto ve sólo `activo = true`. No cambia ninguna otra decisión del slice.
- `20261024180000_catalogo_clientes.sql`: la policy `clientes_select_empresa` agrega `and (p.rol in ('dueno', 'encargado') or clientes.activo)`; se mantienen el perfil activo y la empresa. Sólo se actualizaron además los comentarios que describían la regla anterior. Las policies de `propietario_rpc`, las RPC, los grants y `service_role` no cambian.
- `clientes_catalogo.test.sql` (176 → 183): el vendedor ya no ve `c003` (inactivo); aserciones explícitas vendedor + activo → visible, vendedor + inactivo → invisible (también con metadata de dueño), dueño + inactivo → visible, encargado + inactivo → visible; y el vendedor deja de ver un cliente al desactivarlo y lo vuelve a ver al reactivarlo.
- `clientes-catalogo.spec.ts`: el dueño crea dos clientes, el encargado desactiva uno, el vendedor no lo ve (ni buscando ni con el filtro «Inactivos», ni por la Data API pidiéndolo por id) y sí ve el activo; el dueño lo sigue leyendo. Con la mutación 9 aplicada a la base local, esta prueba falla; restaurada con `db reset`, pasa.
- La pantalla conserva la opción de filtro «Inactivos» también para el vendedor (queda vacía); no se tocó el frontend.

| Verificación | Resultado |
|---|---|
| `git diff --check` | exit 0 |
| `npx supabase db reset` | OK |
| `npx supabase test db` | **PASS, 507/507** (clientes 183) |
| `npx supabase db lint` | PASS, «No schema errors found» |
| `npx supabase db advisors --local` | «No issues found» |
| `npm run typecheck` / `npm run lint` | exit 0 / exit 0 |
| `npm test` | **PASS, 25 archivos / 805 tests** |
| `npx playwright test` | **PASS, 76/76** |
| `npm run build` | exit 0 (aviso conocido de chunk > 500 kB) |

**Mutaciones pgTAP** (arnés ad hoc reconstruido, no versionado; cada mutación dentro de la transacción del test y revertida por su `rollback`; después, `supabase test db` 507/507). Control: 183 `ok` / 0 `not ok`. **9/9 detectadas:** (1) INSERT/UPDATE a `authenticated` → 4; (2) EXECUTE a `anon` en `crear_cliente` → 1; (3) vendedor admitido por el chequeo de gestión → 7; (4) vendedor valida → 7; (5) sin aislamiento por `empresa_id` (funciones y tres policies) → 17; (6) RLS deshabilitada → 20; (7) fachada SECURITY DEFINER → 2; (8) `service_role` con SELECT/INSERT/UPDATE → 5; **(9) vendedor lee inactivos (policy SELECT anterior) → 4**. Los conteos de (5) y (6) difieren de la corrida anterior porque el arnés se reconstruyó, la batería tiene 7 aserciones más y estas corridas no abortan.

**STAGING: NOT TOUCHED · PRODUCTION: NOT TOUCHED · REMOTE ACTIONS: NONE · SECRETS EXPOSED: NO.**

---
## 24/10/2026 — Cierre de staging: catálogo de camiones (validación controlada) — PASS

**Entorno:** staging, project ref `rtsncntppghdynzhezzg` · **Código:** `main` = `37250de56c73f82aca5a6db3f7cbdbcffdc571ab` (merge del PR #13) · **Autorización humana explícita:** aplicar la migración en staging (hecho por el humano) y ejecutar esta validación con fixtures controlados y cleanup. **Producción no tocada.** Sin `db push` por parte de Claude, migraciones nuevas, cambios de código, commit, push, PR, merge ni deploy en la validación. Esta entrada complementa la del slice («Slice Etapa 1: catálogo de camiones»), cuya línea «STAGING: NO TOCADO» refleja el momento de aquella entrada y queda superada por esta.

**STAGING VALIDATION: PASS.**

### Migración e historial
- Migración aplicada: `20261024144459_catalogo_camiones.sql`. `supabase migration list --linked`: **5/5 migraciones alineadas** local/remoto (`20261022120000`, `20261023120000`, `20261023140000`, `20261024010921`, `20261024144459`). No se volvió a aplicar nada.

### Método
- Estado inicial de staging: **0** empresas, perfiles, camiones y usuarios Auth (y 0 filas de `auth.audit_log_entries`). Sólo se usaron fixtures controlados: dos empresas temporales (A y B, B sólo como fixture adversarial de aislamiento) y seis usuarios Auth temporales (dueño A, encargado A, vendedor/piloto A con `user_metadata` engañosa, perfil inactivo A, sin perfil, dueño B), identificables como temporales (`camiones_staging_*`, `cams-stg-*`). Contraseña aleatoria por corrida, no impresa.
- Permisos probados con `STAGING_PUBLISHABLE_KEY` + JWT reales de los usuarios fixture contra la Data API (REST/RPC). La secret key no se usó para afirmar RLS; sólo para probar que `service_role` no tiene acceso. SQL administrativo por `TEST_DATABASE_URL` (estructura, estado y cleanup). Ni credenciales ni JWT se imprimieron.
- Script temporal fuera del repo (no versionado).

### Corridas
- **Primera corrida: 93/94.** El único fallo fue un **error de aserción del script de prueba** (comparaba `true` con `t` al concatenar un booleano), no un defecto del producto.
- **Segunda corrida (tras corregir la aserción, corrida completa repetida): 94/94 PASS.**

### Resultado por gate
| Gate | Resultado |
|---|---|
| TABLE | PASS |
| RLS | PASS |
| GRANTS | PASS |
| RPC TOPOLOGY | PASS |
| OWNER WRITE | PASS |
| ENCARGADO READ-ONLY | PASS |
| VENDEDOR READ-ONLY | PASS |
| INACTIVE PROFILE | PASS |
| NO PROFILE | PASS |
| ANON | PASS |
| SERVICE_ROLE | PASS |
| CROSS-COMPANY | PASS |
| METADATA SPOOF | PASS |
| HEADER SPOOF | PASS |
| VALIDATIONS | PASS |
| ATOMICITY | PASS |
| CLEANUP | PASS |

### Hechos relevantes comprobados
- **Estructura:** `public.camiones` con 7 columnas (`patente`, `nombre`, `activo` del Blueprint §8, más `id`, `empresa_id` y auditoría mínima `creado_en`/`creado_por`), claves únicas `(empresa_id, id)` y `(empresa_id, patente)`, FK compuesta `(empresa_id, creado_por)` a `perfiles` y CHECK de normalización de patente y nombre. RLS habilitada sin `FORCE`, con 4 policies. `authenticated` sólo SELECT; `propietario_rpc` SELECT, INSERT y UPDATE por columna. Fachadas `public` SECURITY INVOKER (dueño `postgres`) e implementaciones `privado` SECURITY DEFINER (dueño `propietario_rpc`), todas con `search_path` vacío; EXECUTE sólo a `authenticated`.
- **Escrituras directas** (INSERT/PATCH/DELETE por REST) denegadas a dueño, encargado, vendedor, anon y `service_role`. Dueño crea, edita y activa/desactiva sólo por RPC; `empresa_id` y `creado_por` los deriva el servidor.
- **Encargado y vendedor/piloto:** leen los camiones de su empresa; las tres RPC de escritura devuelven `PT403`; datos sin cambios (hash antes/después). **Perfil inactivo** (aun con rol dueño) y **usuario sin perfil:** lectura vacía y `PT403`.
- **`service_role` no tiene privilegios sobre la tabla ni sobre las RPC de camiones** (HTTP y ACL), coherente con la decisión del slice.
- **Aislamiento cross-company:** cada dueño ve sólo su empresa; actualizar o cambiar el estado de un camión de otra empresa devuelve `PT404`, **indistinguible** de un id inexistente. Misma patente permitida en empresas distintas.
- **`user_metadata` falso no otorga privilegios** (rol `dueno`/`empresa_id` de otra empresa, también tras editarla por Auth y reiniciar sesión). **Headers falsos** (`x-empresa-id`, `x-user-id`, `x-rol`, `request.jwt.claims`, etc.) **no alteran empresa ni identidad.** `Accept-Profile`/`Content-Profile: privado` rechazados (`PGRST106`).
- **Validaciones:** `PT400` (patente/nombre vacíos, con espacios o null; estado null), `PT401` (JWT sin `sub`, probado por SQL con rol `authenticated`), `PT403`, `PT404`, `PT409` (patente duplicada, también tras `btrim` y al actualizar). Un parámetro `empresa_id` extra en la firma es rechazado.
- **Atomicidad y concurrencia:** los 8 alta fallidos no dejaron filas parciales y la actualización fallida no alteró la fila. **6 altas simultáneas con la misma patente → 1 éxito + 5 `PT409`**, 1 sola fila.
- **GraphQL:** `pg_graphql` **no está habilitado**; no hay mutaciones GraphQL sobre `camiones`.
- **Cleanup:** al terminar, **0 fixtures y 0 residuos Auth relacionados** (camiones, perfiles, empresas, `auth.users`, `auth.identities`, `auth.sessions`, `auth.refresh_tokens` y `auth.audit_log_entries`: todos en 0, igual que al inicio). Verificado de nuevo en una consulta independiente posterior.

### Advisors de seguridad (`supabase db advisors --linked --type security`)
- **NO BLOQUEANTE / PREEXISTENTE:** 2 WARN, ambos sobre `public.rls_auto_enable()`: **0028** (`anon_security_definer_function_executable`) y **0029** (`authenticated_security_definer_function_executable`). La función es `SECURITY DEFINER`, owner `postgres`, ejecutable por `anon` y `authenticated`, asociada al event trigger `ensure_rls` y **no está definida en las migraciones del repo**. Corresponde al pendiente **O-4** ya registrado. **No se modificó.**
- Sin hallazgos sobre `public.camiones` ni sobre `privado.*`.

### Riesgos y pendientes (se mantienen)
- La patente es **sensible a mayúsculas y formato** (`cs-001` y `CS-001` conviven; confirmado en staging). Requiere decisión humana si el negocio quiere unicidad insensible a formato.
- **P11 global** (privilegios de `service_role`) sigue pendiente.
- **O-3** (membresía `postgres` → `propietario_rpc`) y **O-4** (`public.rls_auto_enable()`) siguen abiertas.
- **Producción bloqueada.** Esta validación no la habilita.
- Jornadas, movimientos y demás pantallas operativas **siguen usando el catálogo demo de camiones** (`localStorage`); un camión creado en la base no aparece ahí (M-03).
- Superficie sensible (RLS, RPC, roles, `SECURITY DEFINER`): **corresponde security review** y auditoría independiente del hash que se commitee; esta validación de staging no las reemplaza.

**PRODUCTION: NOT TOUCHED · VERCEL: NOT TOUCHED · CODE CHANGES: NONE · SECRETS EXPOSED: NO.**

---
## 24/10/2026 — Slice Etapa 1: catálogo de camiones (local; sin commit)

**Rama:** `feat/catalogo-camiones` desde `main` = `3d57fb18fc31127ab923aa964e86c3dd4d7e54a3` · **Autorización humana explícita:** diseñar e implementar el slice en rama, con migración local, RLS, RPC, pgTAP, frontend, Vitest, documentación y ejecución local de tests. **No autorizado y no realizado:** staging, producción, push, PR, merge, deploy ni commit. Las operaciones remotas las hace el humano.

### Objetivo y alcance
Catálogo real de camiones como dato maestro de Etapa 1 (Blueprint §8: `camiones` = patente, nombre, activo, aprobada conceptualmente), con la Topología D ya auditada de productos (fachada `public` SECURITY INVOKER → implementación `privado` SECURITY DEFINER de `propietario_rpc` → tabla con RLS).

**Fuera de alcance (no implementado):** ubicaciones, stock por camión, `movimientos_stock`, jornadas, asignación de vendedor, estado `en_reparto`, mantenimiento, marca, modelo, observaciones, chofer, rutas, GPS, P11 global / `service_role` global, producción. Marca, modelo, estado y observaciones del prototipo **no** pasan a `public.camiones`; `en_reparto` se resolverá con la jornada.

### Decisión humana (matriz de permisos, 24/10/2026)
Dueño: SELECT, crear, editar, activar/desactivar. Encargado: SELECT únicamente. Vendedor/piloto: SELECT únicamente (uso futuro). Anon y otra empresa: nada. No se amplió la matriz.

### Decisiones técnicas aplicadas (no son reglas de negocio nuevas)
- `UNIQUE (empresa_id, patente)` **sensible a mayúsculas**, patente sólo con `btrim`; sin regex, sin normalizar mayúsculas/espacios/guiones, sin formato Mercosur/legacy, sin `citext` (indicado en el pedido).
- `empresa_id` y `creado_por` los deriva el servidor del perfil; ninguna firma recibe `empresa_id`. Rol, empresa y `activo` salen de `perfiles`, nunca de `user_metadata`.
- Sin `idempotency_key` ni locks explícitos (CRUD maestro simple, igual que productos).
- Errores: `PT401 camion_no_autenticado`, `PT403 camion_no_autorizado`, `PT404 camion_no_encontrado` (otra empresa e id inexistente, indistinguibles), `PT400 camion_patente_invalida | camion_nombre_invalido | camion_estado_invalido`, `PT409 camion_patente_duplicada`, `PT500 camion_error_interno`. Sin nombre de restricción, SQL ni UUID ajeno.
- **`service_role` sin ningún privilegio sobre `camiones`**: no hay fuente aprobada que defina su comportamiento para esta tabla y P11 global sigue pendiente. No se generaliza P11-productos.

### Archivos
- Migración nueva `supabase/migrations/20261024144459_catalogo_camiones.sql` (generada con `npx supabase migration new catalogo_camiones`; no se tocaron migraciones históricas).
- `supabase/tests/camiones_catalogo.test.sql` (nuevo, 112 aserciones).
- `supabase/tests/grants_default_privileges.test.sql`: la matriz y los chequeos por columna/PUBLIC incluyen `public.camiones` (sin `service_role`, decisión pendiente) y la lista de funciones ejecutables por `authenticated` pasa de 6 a 12 firmas. Sin debilitar aserciones; el plan sigue en 32.
- `supabase/tests/productos_catalogo.test.sql`: dos aserciones genéricas se adaptan a que ahora existen seis implementaciones `SECURITY DEFINER` (productos + camiones) y a excluir las implementaciones de camiones del chequeo de auxiliares (las cubre el test de camiones). Sin cambios de plan (125).
- `apps/web/src/lib/camiones.ts` y `camiones.test.ts` (nuevos), `apps/web/src/hooks/useCatalogoCamiones.ts` (nuevo), `apps/web/src/pages/Camiones.tsx` (reescrita sobre Supabase).
- Playwright: `tests/camiones-catalogo.spec.ts` (nuevo, 6 pruebas); `tests/storage-operativo-corrupto.spec.ts` (el caso «camiones» pasa a `/jornadas`, igual que se hizo con productos) y `tests/catalogos-escritura-post-montaje.spec.ts` (se retira el caso demo de camiones; queda clientes).
- `App.tsx` **sin cambios**: `/camiones` sigue para `ROLES_GESTION` (dueño + encargado); no se amplió al vendedor. La base igualmente permite su SELECT. La UI sólo muestra/oculta acciones por rol y no es frontera de seguridad.

### Seguridad (superficie sensible → corresponde **security review**; no queda cerrada por este log)
- Tabla con RLS habilitada y sin FORCE. `authenticated`: sólo SELECT; `anon` y `service_role`: nada; `propietario_rpc`: SELECT, INSERT de `empresa_id, patente, nombre, creado_por` y UPDATE de `patente, nombre, activo`.
- Policies de `propietario_rpc` exigen perfil activo de la empresa y, para escribir, rol `dueno` e identidad del llamador. FK compuesta `(empresa_id, creado_por)` → `perfiles`.
- Fachadas: SECURITY INVOKER, `search_path=''`, EXECUTE sólo a `authenticated`. Implementaciones y auxiliares en `privado`: SECURITY DEFINER sólo las tres implementaciones, owner `propietario_rpc`, sin EXECUTE para PUBLIC/anon/service_role (las implementaciones sí para `authenticated`, necesario para que la fachada INVOKER delegue, igual que productos).

### Pruebas (resultados reales, ejecutados sobre el árbol final tras `db reset`)
- `git diff --check`: PASS.
- `npx supabase db reset`: PASS (5 migraciones). `npx supabase test db`: **324/324 PASS** (4 archivos: auth 55, camiones 112, grants 32, productos 125). `db lint`: sin errores de esquema. `db advisors --local`: sin hallazgos.
- `typecheck`: PASS. `lint`: exit 0. Vitest: **768/768** (24 archivos; +52 de `camiones.test.ts` sobre 716). `build`: PASS. Playwright: **65/65** (60 previos −1 caso demo de camiones +6 nuevos).

### Mutation tests de seguridad (temporales, sobre la base local, revertidos; no commiteados)
Se aplicó cada mutación, se corrió `supabase test db` y se revirtió; tras revertir, 324/324 PASS. **8/8 detectadas:** (1) INSERT directo a `authenticated` (4 aserciones fallidas); (2) EXECUTE a `anon` en una RPC (2); (3) encargado permitido en `exigir_dueno_camiones` (4); (4) quitar el aislamiento por `empresa_id` (7, ver nota); (5) lectura de otra empresa (6); (6) EXECUTE a `service_role` en una RPC (2); (7) sin RLS (15); (8) fachada `public` en SECURITY DEFINER (4).
Nota sobre (4): quitar sólo el filtro `empresa_id` de la función, o ese filtro más la condición de empresa de la policy UPDATE, **no** altera el comportamiento observable porque la policy SELECT de `propietario_rpc` (que UPDATE también aplica) sigue aislando: son tres capas independientes. La mutación se detecta cuando se quitan las tres. Es defensa en profundidad, no un hueco; queda registrado para que el auditor no lo lea como una mutación no cubierta.

### Riesgos
- La patente distingue mayúsculas y no se normaliza: `abc123` y `ABC123` (o `AB 123 CD` y `AB123CD`) conviven como patentes distintas. Requiere decisión humana si el negocio quiere unicidad insensible a formato.
- `Jornadas`, `Movimientos` y las demás pantallas operativas siguen con el catálogo demo de camiones de `localStorage` (convivencia temporal, igual que productos); un camión creado en la base no aparece ahí. La pantalla lo avisa. Bloquea producción (M-03).
- El vendedor/piloto lee camiones por la base pero no tiene la pantalla `/camiones` (sin cambios de rutas).
- Los residuos de camiones creados por Playwright quedan en la base local, no en los tests de pgTAP (usan su propia empresa y rollback).

### Pendientes (no resueltos acá)
- Decisión humana sobre unicidad/normalización de patente y sobre privilegios de `service_role` en `camiones` (P11 global).
- Security review y auditoría independiente del hash que se commitee.
- Aplicar la migración en staging y validarla (O-3, O-4, advisors remotos y demás pendientes anteriores siguen abiertos).
- Reemplazar el consumo demo de camiones en jornadas cuando exista el módulo.

**STAGING: NO TOCADO · PRODUCCIÓN: NO TOCADA · COMMIT: NO CREADO · PUSH/PR/MERGE/DEPLOY: NO REALIZADOS.**

---
## 24/10/2026 — Desviación de proceso: PR #11 mergeado antes del gate humano de merge

**Clasificación:** PROCESS DEVIATION: YES · TECHNICAL DEFECT: NO · SECURITY DEFECT: NO · CORRECTNESS DEFECT: NO · **DECISIÓN: ACCEPT MERGE.**

- **Qué pasó:** el gate humano autorizado cubría únicamente push y apertura del PR #11, explícitamente sin merge (AGENTS.md §2.2.1, §2.3.7 y §2.3.8). GitHub registra igualmente el merge del PR #11 con el merge commit `a6bc6ff2ec90918c3bfcd225bdc80024cdd9732a`.
- **Revisión posterior (solo lectura):** el merge contiene únicamente `5abdc57023513afeb79424193b53cd7b16b3f03e` y `2741a8c98073b4d1f8df1efab6f9a6eea0608633`; `git diff` entre la rama auditada y el merge commit es vacío; 0 cambios inesperados; migración y tests idénticos a lo auditado; sin secretos; recomendación independiente: ACCEPT MERGE.
- **Validación sobre `main` post-merge:** typecheck PASS · lint PASS · Vitest 716/716 PASS · build PASS · `supabase db reset` PASS · pgTAP 212/212 PASS · `supabase db lint` PASS. M-04 continúa en PASS; staging validado.
- **Decisión:** no existe motivo técnico para revertir. Se acepta el merge como estado integrado de `main`.
- **Trazabilidad:** la desviación se registra para no repetirla; el merge y el deploy requieren cada uno autorización humana explícita previa y la autorización de un paso no se extiende al siguiente.
- **Esto NO autoriza:** deploy, producción, nuevas migraciones ni nuevos cambios funcionales.

**Producción: NO TOCADA · DEPLOY: NO REALIZADO.** Cambios funcionales de esta entrada: 0 (sólo documentación).

---
## 23/10/2026 — Gate final de staging, retoma: pruebas funcionales de M-04 (Gates 3–18) — ENTRADA DEFINITIVA VIGENTE

> **Estado vigente de la validación de staging: M-04 DEFINITIVO = PASS.** Esta es la entrada definitiva. La entrada «Gate final de staging: default privileges + M-04 funcional (PARCIAL)» que sigue más abajo es **histórica y supersedida** por esta.

### Resumen final M-04 (commit funcional `5abdc57023513afeb79424193b53cd7b16b3f03e`)

| Criterio | Resultado |
|---|---|
| DEFAULT PRIVILEGES BEHAVIOR (Gate 2, entrada histórica) | PASS |
| DIRECT REST WRITES (Gate 7) | PASS |
| RPC ROLE MATRIX (Gate 8) | PASS |
| AISLAMIENTO `empresa_id` (Gate 9) | PASS |
| PRODUCT VALIDATIONS (Gate 10) | PASS |
| IDENTIDAD `auth.uid` / `usuario_actual` (Gate 11) | PASS |
| PRIVATE SCHEMA (Gate 12) | PASS |
| GRAPHQL BYPASS (Gate 13) | PASS, condicionado a `pg_graphql` deshabilitada |
| SERVICE_ROLE HTTP (Gate 14) | PASS |
| ATOMICIDAD (Gate 15) | PASS |
| CLEANUP (Gate 16) | PASS |
| POST-CLEANUP (Gate 17) | PASS |
| **M-04 DEFINITIVO** | **PASS** |

**STAGING: VALIDADO · PRODUCCIÓN: NO TOCADA · MERGE: NO REALIZADO · DEPLOY: NO REALIZADO.**

**Default privileges:** la prueba material en staging se ejecutó con autorización humana (tabla, secuencia y función en `public`, función en `privado`, creadas por `postgres`; sin privilegios inesperados para `anon`/`authenticated`/`service_role`; funciones sin EXECUTE para PUBLIC y los tres roles; `ensure_rls` activó RLS en la tabla nueva; los cuatro objetos se eliminaron y quedaron 0 objetos temporales). Detalle en el Gate 2 de la entrada histórica. **No queda ninguna prueba de default privileges pendiente.**

**Security review independiente del commit `5abdc57`:** OpenCode: APPROVED (0 BLOCKERS, 0 SECURITY, 0 CORRECTNESS). Codex: APPROVED (0 BLOCKERS, 0 SECURITY, 0 CORRECTNESS). El detalle vive en `AUDITORIA_5abdc57.md` (sin trackear); no se copia acá.

**Riesgos residuales (pendientes, no bloqueantes; no se resuelven en esta tarea):** O-3 (membresía `postgres` → `propietario_rpc`); O-4 (`public.rls_auto_enable()`); P11 global (privilegios de `service_role` sobre `empresas`/`perfiles`, distintos entre local y staging); `MAINTAIN` de `service_role`; `PT401`/`PT500` cubiertos sólo por pgTAP; el `22P02` de PostgREST refleja el input; `pg_graphql` hoy deshabilitada (repetir Gate 13 si se habilita); advisors de Supabase pendientes.

La secret key temporal `m04-validation` fue sólo un instrumento de validación y no forma parte del sistema; ningún valor de key se registra en este log.

**Entorno:** staging, project ref `rtsn…hezzg` (URL verificada exacta; `TEST_DATABASE_URL` por pooler con usuario `postgres.<ref>` del mismo proyecto) · **HEAD:** `5abdc57023513afeb79424193b53cd7b16b3f03e` · **Autorización humana explícita:** fixtures, usuarios Auth de prueba, pruebas REST/RPC/Auth/GraphQL reales, una segunda empresa sólo como fixture adversarial de aislamiento por `empresa_id`, cleanup y esta documentación. **Producción no tocada.** Sin `db push`, migraciones, migration repair, cambios de configuración de Data API/Auth/GraphQL, commit, merge ni deploy. Gates 1 y 2 y el cleanup de `__m04_tmp_*` ya estaban en PASS y no se repitieron.

### Gate 3–4 — Fixtures y usuarios Auth: PASS

- Previo: 0 empresas, perfiles, productos, usuarios, identities, sesiones y filas de `audit_log_entries`; 0 fixtures `m04_staging_`; sin triggers sobre `auth.users`.
- Creados (SQL administrativo en una transacción, con la misma forma que `supabase/seed.sql`: `auth.users` + `auth.identities` con hash `crypt`/`gen_salt('bf')` de `extensions`; las 19 columnas existían en el esquema real): empresas `m04_staging_empresa_a` y `m04_staging_empresa_b` (B sólo como fixture adversarial de aislamiento); usuarios `m04_staging_dueno_a`, `_encargado_a`, `_vendedor_a` (con `user_metadata.rol = "dueno"` deliberadamente engañoso), `_inactivo_a` (perfil `activo = false`), `_sinperfil` (cuenta Auth sin perfil) y `_dueno_b`. Roles reales del CHECK: `dueno`, `encargado`, `vendedor_piloto`. Contraseña aleatoria por corrida, nunca impresa y borrada al final. No se usó `user_metadata` para autorizar.
- Gate 6: los 6 logins por `/auth/v1/token` dieron HTTP 200 y `sub` del JWT = `auth.users.id` en los 6.

### Gate 5 — Productos base sólo por RPC: PASS

`crear_producto` por JWT real: A1 (dueño A, código `m04_staging_A1`), A2 (encargado A, sin código) y B1 (dueño B). `empresa_id` correcto en los tres y `creado_por` = `sub` del llamador. **Ninguna firma recibe `empresa_id`**: lo deriva el servidor del perfil (evidencia positiva de DE-11 modificada).

### Gate 7 — Escrituras REST directas a `/rest/v1/productos`: PASS

`anon`: POST/PATCH/DELETE → HTTP 401 `42501`. `authenticated` (dueño A): POST/PATCH (precio y activo)/DELETE → HTTP 403 `42501`. `anon` SELECT → 401 `42501`. Hash de la tabla (md5 de todas las filas) idéntico antes y después. Dueño A lee sólo productos y empresa de A.

### Gate 8 — Matriz RPC por rol: PASS

| Actor | crear | actualizar | cambiar_estado |
|---|---|---|---|
| dueño A | 200 | 204 | 204 |
| encargado A | 200 | 204 | 204 |
| vendedor/piloto A (metadata `rol=dueno`) | 403 `PT403` | 403 `PT403` | 403 `PT403` |
| perfil inactivo A | 403 `PT403` | 403 `PT403` | 403 `PT403` |
| Auth sin perfil | 403 `PT403` | 403 `PT403` | 403 `PT403` |
| anon | 401 `42501` | 401 `42501` | 401 `42501` |

Los denegados no modificaron la tabla (hash idéntico). Lectura por Data API: dueño, encargado y vendedor ven los 4 productos de A; inactivo y sin perfil ven 0. `PT401` (sin `sub`) no es alcanzable por HTTP con JWT válido y no se probó; `PT500` tampoco se provocó.

### Gate 9 — Aislamiento por `empresa_id` (B es sólo fixture adversarial): PASS

Con JWT de A sobre B1: `actualizar_producto` y `cambiar_estado_producto` → 404 `PT404` (dueño y encargado); lectura por id y por `empresa_id=B` → 200 con 0 filas; PATCH directo → 403. Parámetro extra `p_empresa_id` (B) → 404 `PGRST202` (la firma no lo admite); header `X-Empresa-Id: B` ignorado (el producto quedó en A). Inverso (dueño B sobre A1) → 404 `PT404`. Por SQL: B1 y A1 idénticos fila a fila y B1 sigue en B. Mismo código de A1 creado en B: 200 (consistente con `unique (empresa_id, codigo)` ya existente; no se derivó ninguna regla nueva).

### Gate 10 — Validaciones de producto por RPC: PASS (con una corrección de mi script)

- Precio: 20, 20.90, 20.990 (persistido 20.99, DE-15) → 200; 20.999, -1, `"NaN"`, `"Infinity"`, `"-Infinity"`, `null` y 10^12 → 400 `PT400 producto_precio_invalido`.
- Código: se normaliza con `btrim`; `""`, `"   "` y `null` se guardan como NULL; duplicado (también con espacios) → 409 `PT409`.
- Nombre vacío/espacios, categoría, forma y combinaciones inválidas → 400 `PT400` con mensaje estable. Stock mínimo -1 y `null` → `PT400`; 1.5 → 400 `22P02` generado por PostgREST al castear el parámetro (no por nuestra función; el mensaje repite el valor enviado por el cliente).
- Actualizar: seis fallos (precio, nombre, stock, código duplicado) dejaron A2 intacto; 20.990 válido → 204. `categoria`/`forma_venta` no son editables (`p_categoria` → `PGRST202`; PATCH directo → 403).
- **Corrección:** en la primera pasada, 5 casos de éxito dieron `409` porque mi script reutilizó el código `V1` (el contador no avanzaba en un subshell). Fue un error de la prueba, no del sistema. Se repitieron con códigos únicos y dieron 200 con delta de +5 filas y valores correctos.
- Cada caso fallido verificó por SQL que el conteo de filas no cambió (atomicidad).

### Gate 11 — Identidad: PASS

Con JWT reales: `sub` = `auth.users.id` en los 6. Con los claims reales del JWT en la sesión SQL: `auth.uid() = privado.usuario_actual()` → `true` (dueño, vendedor, sin perfil). Empresa, rol y `activo` salen de `perfiles`. `creado_por` de A1, A2 y B1 coincide con el `sub` de cada llamador. El JWT del vendedor lleva `user_metadata.rol = "dueno"` y aun así las tres RPC le dieron `PT403`: `user_metadata` no participa en la autorización. `privado.usuario_actual()` no es invocable por HTTP, así que la comparación directa se hizo por SQL.

### Gate 12 — Esquema `privado` por Data API: PASS

`anon` y `authenticated`: `Accept-Profile: privado` y `Content-Profile: privado` (GET productos y RPC `usuario_actual`, `crear_producto`, `exigir_gestor_productos`) → 406 `PGRST106 Invalid schema: privado`. Sin perfil, `usuario_actual`, `exigir_gestor_productos` y `validar_campos_producto` → 404 `PGRST202` en `public`. `pg_catalog` también 406. La raíz OpenAPI responde 401 con la publishable key, por lo que no sirvió para listar esquemas.

### Gate 13 — GraphQL: PASS (condicionado a que `pg_graphql` siga sin habilitar)

`pg_graphql` no está instalada; `graphql_public.graphql` es el placeholder. `/graphql/v1` (anon y authenticated): introspección y una mutación inventada → HTTP 200 con `pg_graphql extension is not enabled.`; GET → 404 `PGRST202`. 0 productos creados. **Si en el futuro se habilita `pg_graphql`, este gate debe repetirse.**

### Gate 14 — `service_role` HTTP: PASS

Precondiciones verificadas sin imprimir secretos: `STAGING_SUPABASE_URL` exacta (`rtsn…hezzg`), `STAGING_SECRET_KEY` definida con formato `sb_secret_*` y `TEST_DATABASE_URL` del mismo project ref. La key se envió **sólo** como `apikey: <key>` (sin `Authorization: Bearer`). No se recrearon fixtures: staging empezó y terminó con 0 empresas, 0 perfiles, 0 productos y 0 usuarios Auth.

| Prueba | Resultado |
|---|---|
| `GET /rest/v1/productos` | 200 `[]` (SELECT funciona) |
| `POST` / `PATCH` / `DELETE /rest/v1/productos` | 403 `42501 permission denied for table productos` (los tres) |
| RPC `crear_producto`, `actualizar_producto`, `cambiar_estado_producto` | 403 `42501 permission denied for function …` (las tres) |
| `Accept-Profile: privado` | 406 `PGRST106 Invalid schema: privado` |

Semántica observada: una secret key `sb_secret_*` mapea al rol Postgres `service_role`, que **no** tiene BYPASSRLS efectivo sobre privilegios de tabla/función: se rige por los grants (sólo SELECT en `productos`, sin EXECUTE en las fachadas). Verificación SQL con `TEST_DATABASE_URL` antes/después: `public.productos` sigue con 0 filas (md5 `vacio`), y los hashes de ACL de tablas, ACL de funciones (`public` y `privado`) y `pg_default_acl` son **idénticos** (`diff` vacío); `service_role` sigue con sólo `SELECT` sobre `productos`. La key no se imprimió ni se guardó en archivos.

### Gate 15 — Atomicidad y efectos: PASS

Todo caso exitoso creó exactamente la fila esperada (17 productos al final: 15 en A, 2 en B) y todo caso fallido no dejó filas parciales. Sin códigos duplicados por empresa, sin precios con más de 2 decimales o negativos, sin combinaciones inválidas, sin productos con nombres de pruebas fallidas y sin productos fuera de las empresas fixture. No se tocaron stock ni libros.

### Gate 16 — Cleanup: PASS

`cleanup.sh` borró 17 productos, 5 perfiles, 6 usuarios Auth (cascada a identities, sesiones y refresh tokens) y 2 empresas. Verificado: 0 empresas, perfiles, productos, usuarios, identities, sesiones, refresh tokens y filas de `audit_log_entries` `m04_staging_`; 0 objetos temporales `m04`; los totales vuelven al baseline (0/0/0/0). Credenciales y JWT borrados del scratchpad.

### Gate 17 — Post-cleanup: PASS

Foto estructural read-only antes y después: **idéntica** (`diff` vacío). Cubre migration history (exactamente 4), 12 funciones de `public`/`privado` con owner, `SECURITY DEFINER`, `search_path`, ACL y `md5(prosrc)`, las 7 policies (hash), RLS activa sin FORCE, ACL de tablas (grants O-1/O-2), `pg_default_acl`, ACL de `privado` (0 relaciones), atributos de `propietario_rpc`, 0 triggers/rules en `public` y `pg_graphql` sin instalar.

### Gate 18 — M-04 DEFINITIVO: **PASS**

Con el Gate 14 en PASS (SELECT permitido; POST/PATCH/DELETE y las 3 RPC rechazados para `service_role` por HTTP) y todos los demás gates en PASS, la lista original de pruebas de M-04 queda cubierta con evidencia material. No hay bypass. La decisión (a)/(b) que había quedado pendiente se resolvió por la opción (b) (prueba con la secret key de staging).

### Observaciones

- El 22P02 de `stock_minimo` no entero repite el valor enviado; es un mensaje de PostgREST, no de nuestras funciones. No se cambia nada.
- `PT401` y `PT500` no se alcanzan por HTTP con JWT válido; siguen cubiertos sólo por pgTAP local.
- La verificación de Auth no habilitó signup ni cambió configuración; `/auth/v1/settings` indica `disable_signup = false`, que es el estado preexistente.
- La superficie sigue siendo sensible (Supabase, RLS, RPC, `SECURITY DEFINER`, grants, `service_role`): estas pruebas fueron evidencia para el **security review**, ya resuelto por OpenCode y Codex (APPROVED, ver resumen arriba). Sigue pendiente la decisión humana de commit documental, merge y deploy.

---
## 23/10/2026 — [HISTÓRICA / SUPERSEDIDA] Gate final de staging: default privileges + M-04 funcional (PARCIAL)

> **SUPERSEDIDA.** Esta entrada se conserva sólo por trazabilidad. Su estado «M-04 INCONCLUSO» y «Gates 3–16 no ejecutados» **ya no rige**: los Gates 3–18 se ejecutaron después y están en la entrada definitiva inmediatamente anterior («Gates 3–18 — ENTRADA DEFINITIVA VIGENTE»), con **M-04 DEFINITIVO = PASS**. Los Gates 1, 2 y 17 parcial de esta entrada siguen siendo válidos y son parte de la evidencia final.

**Entorno:** staging, project ref `rtsn…hezzg` · **HEAD:** `5abdc57023513afeb79424193b53cd7b16b3f03e` (sólo cambia localmente este archivo; `AUDITORIA_5abdc57.md` sin trackear) · **Autorización humana explícita:** objetos temporales para default privileges y fixtures/pruebas funcionales de M-04 en staging, con limpieza posterior. **Producción no tocada.** Sin `db push`, migration repair, commit, merge ni deploy.

### Gate 1 — Identidad y baseline: PASS

- `TEST_DATABASE_URL` apunta al pooler con usuario `postgres.<ref>` igual a `SUPABASE_PROJECT_REF`. `current_database = postgres` y `current_user = postgres`.
- Migration history: exactamente las 4 migraciones, en orden.
- **Baseline de datos:** 0 usuarios en `auth.users`, 0 empresas, 0 perfiles, 0 productos, 0 filas en `auth.audit_log_entries` y 0 objetos `__m04_tmp_*`. Staging no contiene datos reales.

### Gate 2 — Comportamiento real de default privileges: PASS

Se crearon como `postgres`, en una transacción confirmada: `public.__m04_tmp_tabla`, `public.__m04_tmp_seq`, `public.__m04_tmp_fn()` y `privado.__m04_tmp_fn()`. Se verificaron desde otra sesión:

- **Tabla:** `relacl` NULL, que equivale al default de owner: sólo `postgres`. `anon`, `authenticated` y `service_role` no tienen SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ni MAINTAIN, y no hay privilegios por columna. `postgres` tiene todos.
- **Secuencia:** `relacl` NULL. Los tres roles no tienen USAGE, SELECT ni UPDATE; `postgres` sí.
- **Funciones en `public` y `privado`:** `proacl = {postgres=X/postgres}`. PUBLIC, `anon`, `authenticated` y `service_role` no tienen EXECUTE; `postgres` sí.
- Dato observado: el event trigger de plataforma `ensure_rls` (`rls_auto_enable`) activó RLS en la tabla nueva.
- Los cuatro objetos se borraron con `DROP` explícito. Verificado: 0 relaciones y 0 funciones `__m04_tmp_*`.

### Gate 17 parcial — integridad después del Gate 2: PASS

Se repitió toda la consulta de la validación post-hardening (migraciones, grants O-1/O-2, `pg_default_acl`, Topología D, RLS, `privado`, bypass): salida idéntica. Los hashes de `prosrc` de las 11 funciones y de las 7 policies son idénticos al baseline. Siguen 0 usuarios, empresas, perfiles, productos y objetos temporales.

### [Histórico] Gates 3–16 — no ejecutados en esta tanda (bloqueo de credencial; ejecutados después)

Las pruebas HTTP necesitan la publishable/anon key de staging, para obtener JWT reales por `/auth/v1/token` y llamar a `/rest/v1` y `/graphql/v1`.
- La key no está en el entorno de la sesión, y `.env*` no se lee por regla.
- El humano indicó que había creado un archivo con la key, pero no existe en el filesystem visible para la sesión: no está ni en el scratchpad, ni en `/home/tuculandia/m04_staging_keys.sh`, ni en una búsqueda por nombre en todo el disco.
- Por eso **no se crearon fixtures, usuarios Auth ni productos**. Sin JWT reales no habría prueba funcional, y crear datos sin poder probarlos sólo agregaba riesgo de residuos.
- **Cleanup:** no hubo nada que limpiar además de los objetos temporales del Gate 2, que ya están eliminados.

### Estado (histórico, supersedido: M-04 DEFINITIVO = PASS en la entrada definitiva)

- ~~M-04 DEFINITIVO: INCONCLUSO~~ — al cierre de esta tanda faltaban las pruebas materiales con JWT reales y la Data API: escrituras REST directas, matriz de roles por RPC, aislamiento por `empresa_id`, validaciones de producto, `usuario_actual()`/`auth.uid()`, `Accept-Profile: privado`, GraphQL y `service_role` HTTP (luego ejecutadas y en PASS).
- **Para retomar (ya cumplido):** la publishable key en un archivo legible por la sesión, o en una variable de entorno del perfil de shell. La service_role key es opcional y sólo se usa para el Gate 14.

---
## 23/10/2026 — Validación post-hardening en staging (solo lectura)

**Entorno:** staging, project ref `rtsn…hezzg` · **Commit auditado:** `5abdc57023513afeb79424193b53cd7b16b3f03e` (OpenCode y Codex: APPROVED) · **Alcance:** verificación **read-only** de la migración `20261024010921_hardening_grants_default_privileges.sql`, aplicada manualmente en staging por el humano con autorización explícita. Claude **no** ejecutó `db push` ni ninguna escritura. **Producción no tocada.** Sin commit, merge ni deploy.

### Cómo se obtuvo la evidencia

`psql` contra el pooler de staging (modo sesión, usuario `postgres`), todo dentro de `BEGIN TRANSACTION READ ONLY … ROLLBACK`, con `transaction_read_only = on` comprobado en cada tanda. Sólo `SELECT` sobre catálogo. No se crearon objetos de prueba.

### Resultados

- **Migration history: PASS.** `supabase_migrations.schema_migrations` tiene exactamente cuatro filas y en orden: `20261022120000`, `20261023120000`, `20261023140000` y `20261024010921 hardening_grants_default_privileges`.
- **O-1: PASS.** `service_role` sobre `public.productos`: SELECT `t`; INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES y TRIGGER `f`. ACL `service_role=rm/postgres`. **MAINTAIN** (`m`) presente: está en la ACL de la tabla con grantor `postgres` (viene del default de creación), no de `pg_maintain` (`service_role` no es miembro de ningún rol). Queda fuera del alcance del hardening, como estaba documentado.
- **O-2: PASS.** `service_role` sobre `empresas` y `perfiles`: TRUNCATE, REFERENCES y TRIGGER `f`. **Estado observado, sin decidir P11 global:** `service_role` tampoco tiene SELECT, INSERT, UPDATE ni DELETE sobre `empresas` ni `perfiles` (ACL `service_role=m/postgres`, sólo MAINTAIN). Sigue siendo distinto de local (`arwd`).
- **Grants del resto de roles:** `anon` no tiene ningún privilegio sobre las tres tablas; `authenticated` sólo tiene SELECT; no hay privilegios por columna para `anon`, `authenticated`, `service_role` ni PUBLIC.
- **Privilegios por defecto (`pg_default_acl`, rol creador `postgres`): PASS.**
  - `public`, tablas: `{postgres=arwdDxtm/postgres}`. Ni `anon`, ni `authenticated`, ni `service_role`.
  - `public`, secuencias: `{postgres=rwU/postgres}`. Ninguno de los tres.
  - `public`, funciones: `{postgres=X/postgres}`. Ninguno de los tres.
  - **Global** (sin esquema), funciones: `{postgres=X/postgres}`. Cuando existe la entrada global, reemplaza el default de fábrica (que incluye `=X` a PUBLIC): las funciones nuevas que cree `postgres` en cualquier esquema sin entrada propia (incluido `privado`) no dan EXECUTE a PUBLIC. En `public` la ACL efectiva es la global más la del esquema, y ninguna incluye PUBLIC, `anon`, `authenticated` ni `service_role`.
  - **Alcance exacto:** estas entradas aplican sólo a objetos **creados por `postgres`**. Fuera del alcance de la migración y sin cambios: (a) `postgres` en `storage` sigue dando `arwdDxtm`, `rwU` y `X` a `anon`, `authenticated` y `service_role`; (b) `supabase_admin` en `public` sigue dando `arwdDxtm`, `rwU` y `X` a los tres roles para los objetos que cree `supabase_admin` (no las migraciones); (c) las entradas de `supabase_admin` en `extensions`, `graphql`, `graphql_public` y `realtime`, y las de `supabase_auth_admin` en `auth`.
- *(Supersedido: ejecutada y en PASS, ver Gate 2.)* **Prueba de comportamiento de los defaults: PENDIENTE** al momento de esta entrada. No se crearon tabla, secuencia ni función de prueba porque la ronda era read-only. El catálogo es consistente con el resultado esperado, y el comportamiento se probó en local (pgTAP `grants_default_privileges`), pero en staging no se demostró con objetos reales.
- **Topología D: PASS, sin regresión.**
  - Las 3 fachadas de `public` son `SECURITY INVOKER`, tienen owner `postgres` y `search_path=""`, y sólo `authenticated` tiene EXECUTE.
  - Las 3 implementaciones de `privado` son `SECURITY DEFINER`, tienen owner `propietario_rpc` y `search_path=""`, y EXECUTE sólo para `authenticated` y `propietario_rpc`.
  - Los 5 auxiliares son `SECURITY INVOKER` y sólo los ejecuta `propietario_rpc`.
  - `md5(prosrc)` de las 11 funciones es **idéntico** al de la base local construida desde `5abdc57`.
  - `propietario_rpc` sigue sin cambios: `NOLOGIN`, sin superuser, `CREATEROLE`, `CREATEDB`, `REPLICATION` ni `BYPASSRLS`. Membresía de `postgres`: SET + INHERIT (grantor `postgres`) y ADMIN (grantor `supabase_admin`). Es la observación O-3, sin cambios.
- **RLS: PASS.** RLS activa en `empresas`, `perfiles` y `productos`, con `FORCE` desactivado en las tres. Siguen las mismas 7 policies, y el hash de nombre, comando, roles, `qual` y `with_check` es **idéntico** al de local.
- **Esquema privado: PASS.** `privado` existe, tiene owner `postgres` y no contiene relaciones.
  - ACL: `{postgres=UC, authenticated=U, propietario_rpc=U}`.
  - `anon` y `service_role` no tienen USAGE. `authenticated` tiene sólo USAGE, sin CREATE, como requiere Topología D.
  - Ninguna función privada es ejecutable por `anon`, `service_role` ni PUBLIC.
- **Direct write bypass: PASS (estructural).** `anon`, `authenticated` y `service_role` no tienen privilegios de escritura, ni por tabla ni por columna, sobre las tres tablas. No hay triggers, rules, vistas ni secuencias en `public`/`privado`. No hay policies de escritura para los roles de la Data API. `pg_graphql` no está instalada y el esquema `graphql` no tiene objetos.

### Observaciones (sin cambios; no resueltas acá)

- **O-4 sigue abierta.** `public.rls_auto_enable()` es `SECURITY DEFINER`, tiene `search_path=pg_catalog` y da EXECUTE a PUBLIC, `anon`, `authenticated` y `service_role`. Es del proyecto, no de nuestras migraciones, y es anterior al hardening (los defaults sólo afectan objetos futuros). Devuelve `event_trigger`, así que no es invocable como RPC. Conviene revisarla con advisors.
- MAINTAIN de `service_role` en las tres tablas (ver O-1/O-2).

### Pendiente (histórico: la prueba de defaults y M-04 quedaron en PASS en la entrada definitiva; advisors siguen pendientes)

- **Advisors de Supabase: PENDIENTE.** La Management API vuelve a responder 401 («JWT could not be decoded») con el token de la sesión.
- *(Supersedido: ejecutada y en PASS, ver Gate 2.)* Prueba de comportamiento de los defaults en staging (crear y eliminar una tabla, una secuencia y una función de prueba). Es escritura y requiere autorización explícita.
- *(Supersedido: M-04 DEFINITIVO = PASS.)* **M-04 DEFINITIVO: INCONCLUSO** al momento de esta entrada. La estructura es correcta, pero siguían pendientes las pruebas negativas con fixtures, JWT reales y la Data API de staging (lista de 10 casos en la entrada «Validación post-migración en staging»). **Fixtures remotos: PENDIENTES.**
- Security review: la revisión por catálogo está hecha. El cierre formal sigue sujeto a la revisión humana.

---
## 23/10/2026 — Hardening de grants y privilegios por defecto (O-1 / O-2)

**Rama:** `feat/hardening-grants-default-privileges` · **Base:** `main` en `33bd6722c499082d9826f99a38f2cbc3d5774dd6` · **Estado:** commit local autorizado por decisión humana; sin push, merge ni deploy. **Staging NO tocado por este cambio** (la migración nueva no se aplicó fuera de la base local). **Producción NO tocada.** Requiere **security review** (grants, `ALTER DEFAULT PRIVILEGES`, `service_role`) y **auditoría independiente** del hash del commit.

### Objetivo

Corregir los hallazgos O-1 y O-2 de la validación de staging (entrada siguiente) y fijar los privilegios por defecto de `postgres` para objetos futuros, de modo que el modelo RPC + mínimo privilegio (Blueprint §10; ADR-001 §12) no dependa de lo que cada entorno conceda por defecto.

### Decisión O-1 — CONFIRMADO

`service_role` **debe** conservar `SELECT` sobre `public.productos`: lo dice ADR-001 §18.1 (P11-productos, «Conserva `SELECT`»), el pgTAP de productos (`service_role puede leer productos`) y la entrada de H-01 de este log. En local lo daba el privilegio por defecto de la plataforma; la migración `20261023140000` sólo revocó la escritura y nunca concedió el `SELECT`, por eso en staging (donde el default de `postgres` ya no incluye `arwd`) faltaba. Ahora se concede de forma explícita. Sin `EXECUTE` sobre las RPC (sin cambios).

### Causa común de O-1 y O-2: local ≠ staging

Defaults de `postgres` en `public`, medidos antes del cambio:

| Objeto futuro | Local | Staging |
|---|---|---|
| Tablas (anon, authenticated, service_role) | `arwdDxtm` | `Dxtm` |
| Secuencias | `rwU` | `w` |
| Funciones | `X` a los tres roles | sin `X` para los roles |
| Funciones en `privado` | `PUBLIC` implícito | `PUBLIC` implícito |

### Migración nueva

`supabase/migrations/20261024010921_hardening_grants_default_privileges.sql` (creada con `supabase migration new`; las tres migraciones aplicadas no se editaron):

- Guarda: aborta si `current_user <> 'postgres'` (los defaults se definen por rol creador, ADR-001 §12.6).
- `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES / ON SEQUENCES FROM anon, authenticated, service_role` y `REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated, service_role`.
- `ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` en **forma global** (sin `IN SCHEMA`): verificado en local que con `IN SCHEMA privado` la ACL de una función nueva sigue siendo `NULL` (PUBLIC implícito), tal como anticipa ADR-001 §12.6.
- Tablas existentes, explícito: `anon` sin nada; `authenticated` sólo `SELECT` en `empresas`, `perfiles` y `productos`; `service_role` sin `TRUNCATE`/`REFERENCES`/`TRIGGER` en `empresas` y `perfiles`; `service_role` con `SELECT` (y sin `INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`/`REFERENCES`/`TRIGGER`) en `productos`.
- Idempotente: aplicada dos veces sobre una base local con el estado de staging reproducido (ACL `Dxtm` y `m`), sin errores; converge al mismo resultado.

### Fuera de alcance / sin cambios

RLS, Topología D, fachadas e implementaciones, `propietario_rpc` y su membresía (O-3), `rls_auto_enable()` (O-4), `MAINTAIN`, defaults de `supabase_admin` y del esquema `storage`, frontend, auth.

### Decisiones pendientes que esta tarea NO resuelve

- **P11 global:** el `SELECT/INSERT/UPDATE/DELETE` de `service_role` sobre `empresas` y `perfiles` sigue **distinto entre entornos** (local `arwd`, staging ninguno). No se normalizó porque ADR-001 §18.1 dice que no cambia sus privilegios sobre `perfiles` y la política global no está aprobada. Las pruebas no lo evalúan.
- **Secuencias:** los defaults de secuencias (`anon`/`authenticated` podían hacer `nextval`) quedaron incluidos por consistencia con tablas y funciones; no estaban nombrados en la autorización. Revertible sin efecto: no existe ninguna secuencia en el esquema.
- **Efecto del `REVOKE` global de `EXECUTE` a PUBLIC:** toda función que cree `postgres` desde ahora (incluidas las de extensiones instaladas por migración o funciones temporales de tests) no es ejecutable por otros roles hasta concederlo. Cada migración futura debe conceder `EXECUTE` de forma explícita.

### Tests

- Nuevo `supabase/tests/grants_default_privileges.test.sql` (**32 pruebas**): matriz exacta por rol y tabla (los 7 privilegios y los de columna), `service_role` con `SELECT` y nada más en `productos`, sin `TRUNCATE`/`REFERENCES`/`TRIGGER` en ninguna tabla de `public`, sin `INSERT`/`UPDATE`/`DELETE` de `authenticated`, `anon` sin nada, secuencias, funciones sin `EXECUTE` para PUBLIC/`anon`/`service_role`, `authenticated` ejecuta exactamente las seis firmas aprobadas, inspección de `pg_default_acl` (tablas, secuencias, funciones en `public` y entrada global) y prueba de comportamiento: una tabla, secuencia y función nuevas (en `public` y `privado`) creadas como `postgres` no heredan privilegios, y `authenticated` no ejecuta una función privada nueva aunque tenga `USAGE`.
- Modificado `supabase/tests/productos_catalogo.test.sql`: `grant execute … to public` sobre los helpers `pg_temp.como_usuario` y `pg_temp.como_anon`. Antes de este cambio heredaban `EXECUTE` de PUBLIC; con el hardening el test fallaba (`permission denied for function como_usuario`) al invocarlos con rol `authenticated`. Es un efecto del test, no del producto. Sin cambio de aserciones ni de plan (125).

### Mutation tests (transacción revertida contra la base local; la base quedó intacta, verificado por catálogo)

Control sin mutación: 0 `not ok`. Cada mutación fue detectada: `TRUNCATE` a `service_role` en `empresas` (2 fallas) y `REFERENCES` en `perfiles` (2); `TRIGGER` en `productos` (2); quitar `SELECT` a `service_role` en `productos` (2); `INSERT` (2), `UPDATE(precio)` por columna (1) y `DELETE` (1) a `service_role` en `productos`; `INSERT` a `authenticated` en `productos` (3); `TRUNCATE` a `authenticated` en `empresas` (2); `SELECT` a `anon` (3); default de tablas `ALL` a `authenticated` (3) y a `service_role` (3); default de funciones `EXECUTE` a `authenticated` (3); default global `EXECUTE` a PUBLIC (7); default de secuencias `USAGE` a `anon` (2); `EXECUTE` de `authenticated` sobre un auxiliar privado (1); restauración completa del estado previo (13). Arnés ad hoc, no versionado (misma práctica que el slice productos).

### Cómo se verificó (desde `apps/web`, Supabase CLI 2.120.0, Docker local, PostgreSQL 17)

- `supabase db reset --workdir ../..`: aplica las cuatro migraciones y el seed sin errores.
- `supabase test db --workdir ../..`: `Files=3, Tests=212, Result: PASS` (55 Auth + 32 nuevos + 125 productos; antes 180).
- `supabase db lint --local`: `No schema errors found`. `supabase db advisors --local`: `No issues found`.
- `npm run typecheck` exit 0 · `npm run lint` exit 0 · `npm test` 23 archivos / **716** pruebas · `npx playwright test` **60** passed (incluye las pruebas HTTP del catálogo contra la Data API local) · `npm run build` exit 0.
- Security review por catálogo (`information_schema.role_table_grants`, `has_table_privilege`, `has_function_privilege`, `pg_default_acl`): `anon` sin privilegios; `authenticated` sólo `SELECT`; `service_role` sin `TRUNCATE`/`REFERENCES`/`TRIGGER`, y en `productos` sólo `SELECT`; RLS activa en las tres tablas, 7 policies, sin `FORCE`; exactamente 3 funciones `SECURITY DEFINER` (las implementaciones de `privado`, owner `propietario_rpc`, `search_path` vacío); fachadas `SECURITY INVOKER` ejecutables sólo por `authenticated`; ninguna función de `public`/`privado` con `EXECUTE` para PUBLIC, `anon` ni `service_role`. **Topología D sin regresión.**

### Riesgos y pendientes

1. **Aplicar a staging** requiere autorización humana expresa (`supabase db push`); no se hizo. Tras aplicarlo, repetir la verificación de privilegios y el estado de `pg_default_acl` en staging.
2. *(Supersedido: M-04 DEFINITIVO = PASS, ver entrada definitiva.)* M-04 DEFINITIVO seguía INCONCLUSO hasta ejecutar las pruebas negativas con fixtures contra la Data API de staging (entrada siguiente, «Pendiente»).
3. Security review obligatoria (grants, defaults, `service_role`) y auditoría independiente del hash.
4. Producción y migraciones remotas siguen bloqueadas.

---
## 23/10/2026 — Validación post-migración en staging (solo lectura)

**Entorno:** staging, project ref `rtsn…hezzg` · **Alcance:** verificación **read-only** de las tres migraciones ya aplicadas por el humano con `supabase db push` (no se volvió a ejecutar). **Producción no tocada.** Sin commit, merge ni deploy. Las migraciones no se modificaron.

### Evidencia manual del humano (no verificada por Claude)

- Dashboard → Data API → Exposed schemas: `public`, `graphql_public`. `privado` **no** expuesto.

### Evidencia obtenida por Claude (SQL de solo lectura contra staging)

- **Migration history:** `supabase_migrations.schema_migrations` existe y contiene `20261022120000 auth_base_empresas_perfiles`, `20261023120000 perfiles_usuario_formato_estricto`, `20261023140000 catalogo_productos`. Sin otras filas.
- **Objetos:** schemas `public` y `privado` (owner `postgres`); tablas `empresas`, `perfiles`, `productos` (owner `postgres`); rol `propietario_rpc`; 11 funciones (8 en `privado`, 3 fachadas en `public`). El cuerpo (`prosrc`) de las 11 es **idéntico** al de la migración. Constraints y tipos de las tres tablas coinciden con la migración (`precio numeric(14,2)`, formato estricto de `usuario`, `perfiles_empresa_usuario_unico`).
- **`propietario_rpc`:** `NOLOGIN`, no superuser, sin `CREATEDB`, sin `CREATEROLE`, sin `BYPASSRLS`, sin `REPLICATION`; no es dueño de ninguna tabla ni de relaciones. Único miembro: `postgres` (SET e INHERIT por el `grant … to current_user` de la migración; ADMIN OPTION otorgado automáticamente por `supabase_admin`). ADR-001 no regula las opciones de membresía: **no hay desviación respecto de ADR-001**, queda como observación (O-3).
- **Funciones privadas:** las 8 con `search_path=""` y owner `propietario_rpc`. Las 3 implementaciones (`crear_producto`, `actualizar_producto`, `cambiar_estado_producto`) son `SECURITY DEFINER`; EXECUTE sólo para `authenticated` (requerido por Topología D) y `propietario_rpc`. Los 5 auxiliares son `SECURITY INVOKER` y sólo `propietario_rpc` los ejecuta. `PUBLIC`, `anon` y `service_role`: sin EXECUTE en ninguna. (`postgres` figura con EXECUTE efectivo por heredar `propietario_rpc`.)
- **Fachadas públicas:** `SECURITY INVOKER`, owner `postgres`, `search_path=""`, EXECUTE sólo `authenticated` (y `postgres`). **Topología D: PASS estructural** (Data API → fachada INVOKER → implementación DEFINER en `privado`).
- **RLS:** activada en las tres tablas, `FORCE` desactivado (conforme a ADR-001 P4). 7 policies: `empresas_select_propia`, `perfiles_select_propio`, `productos_select_empresa` (`authenticated`, aislan por `empresa_id`/perfil activo propio) y cuatro para `propietario_rpc` (select de perfil propio; select/insert/update de productos con perfil activo `dueno`/`encargado` y misma `empresa_id`). No hay policies de INSERT/UPDATE/DELETE para `anon`, `authenticated` ni `service_role`.
- **Grants efectivos sobre `public.productos`:** `anon` ninguno; `authenticated` sólo SELECT; `service_role` ningún privilegio de lectura/escritura (sólo `MAINTAIN`, PG17); `propietario_rpc` SELECT + INSERT/UPDATE por columnas. `empresas` y `perfiles`: `anon` ninguno, `authenticated` sólo SELECT.
- **Direct write bypass (metadata, grants, RLS):** no existe camino directo de escritura sobre `public.productos` para `anon`, `authenticated` ni `service_role`; sin triggers, rules ni vistas. `postgres` (owner, `BYPASSRLS`) sí escribe, pero no es un rol de la Data API. **PASS estructural.**
- **Data API / GraphQL:** `privado` existe sin tablas; `anon` y `service_role` sin USAGE sobre `privado`; `authenticated` con USAGE (requerido por Topología D). `pg_graphql` **no está habilitada** en staging: `graphql_public.graphql` es el placeholder que responde «pg_graphql extension is not enabled» y no hay objetos en el schema `graphql`. No se observa bypass GraphQL estructural.

### Observaciones para decisión humana (no resueltas ni modificadas)

- **O-1.** `service_role` **no** tiene SELECT sobre `productos` (el comentario de la migración dice «Conserva SELECT»); queda sólo `MAINTAIN`. Más restrictivo de lo documentado, no inseguro. Aclarar si es intencional.
- **O-2.** `service_role` conserva `TRUNCATE`, `REFERENCES` y `TRIGGER` sobre `empresas` y `perfiles` (la migración base sólo revocó a `public`, `anon` y `authenticated`). El default ACL de `postgres` en `public` otorga `Dxtm` a `anon`, `authenticated` y `service_role` en toda tabla futura: cada migración debe revocar explícitamente. Relacionado con P11 global (pendiente; no se resolvió acá). Un `TRUNCATE … CASCADE` quedaría bloqueado por la falta de TRUNCATE sobre `productos`; es razonamiento, **no se probó**.
- **O-3.** `postgres` sigue siendo miembro de `propietario_rpc` con SET e INHERIT. Es lo que habilita ALTER OWNER y queda tras la migración.
- **O-4.** `public.rls_auto_enable()` (`SECURITY DEFINER`, event trigger `ensure_rls`, owner `postgres`) es del proyecto, no de nuestras migraciones. Devuelve `event_trigger`, por lo que no es invocable como RPC; igual conviene revisarla con advisors.

### Pendiente (histórico: los 10 casos de M-04 se ejecutaron después y están en PASS en la entrada definitiva; advisors siguen pendientes)

- **Advisors de Supabase: PENDIENTE.** La Management API respondió 401 («JWT could not be decoded») con el token del entorno de la sesión; no se obtuvieron resultados.
- *(Supersedido: M-04 DEFINITIVO = PASS.)* **M-04 DEFINITIVO: INCONCLUSO** al momento de esta entrada. La estructura es correcta, pero faltaban pruebas negativas con fixtures que ejecuten mutaciones reales vía Data API: (1) `POST/PATCH/DELETE /rest/v1/productos` como `anon`, `authenticated` y `service_role` rechazados por permisos; (2) `/rest/v1/rpc/*` como `anon` rechazado; (3) acceso con `Accept-Profile`/`Content-Profile: privado` rechazado; (4) `/graphql/v1` sin mutaciones; (5) fachadas con dueño y encargado OK, con vendedor/piloto, perfil inactivo y sin perfil → `PT403`/`PT401`; (6) `actualizar_producto` y `cambiar_estado_producto` sobre producto de otra `empresa_id` → `PT404`; (7) precio con más de 2 decimales, negativo, NaN e Infinity → `producto_precio_invalido`; (8) código duplicado → `PT409`; categoría/forma de venta inválida o combinación incorrecta; (9) `empresa_id` nunca tomado del cliente; (10) con un JWT real de PostgREST, `privado.usuario_actual()` = `auth.uid()`. Requieren crear fixtures en staging, lo cual es escritura y necesita autorización explícita.

### Deuda de proceso

- La primera tanda de consultas se ejecutó **sin** forzar solo lectura (`transaction_read_only = off`, pues el pooler ignora `PGOPTIONS`); todas fueron `SELECT` y el catálogo no cambió. El resto se ejecutó dentro de `BEGIN READ ONLY … ROLLBACK`.

---
## 23/10/2026 — Aclaración documental: empresa única y aislamiento por `empresa_id`

**Rama:** `chore/aclarar-empresa-unica` · **Base:** `main` en `12707516fd6a861efd02e0280f9c7ee1fd9fae4e` · **Estado:** cambio documental local, sin push, merge ni deploy; pendiente de commit autorizado. Sin cambios de código, SQL, migraciones ni tests.

### Decisión humana (23/10/2026)

- El producto opera para **UNA SOLA EMPRESA OPERATIVA**. No es multiempresa, multi-tenant ni SaaS.
- `empresa_id` es una **clave técnica de pertenencia, frontera de aislamiento, soporte de RLS e integridad referencial** (defensa en profundidad). Su presencia no implica ni autoriza funcionalidad multiempresa.
- No existen membresías, workspaces, selector de empresa, administración de empresas ni onboarding/registro de organizaciones, invitaciones, planes ni suscripciones.
- Las empresas adicionales de los tests son **fixtures adversariales** para comprobar el aislamiento por `empresa_id`; no son una funcionalidad. Se llaman «aislamiento por `empresa_id`» o «aislamiento de pertenencia».

### Documentos alineados

- `BLUEPRINT.md` §7.3 («Empresa única y aislamiento por `empresa_id`»; se elimina «inicialmente exista una sola empresa»), referencias a membresías en §8, §9 y §10, y criterios de aceptación de §12. Sin cambio de versión.
- `docs/PRD.md` §12, RNF-06, autenticación y criterio de seguridad de §17 (membresía → perfil/empresa/rol del perfil).
- `AGENTS.md` (§2.4, superficies sensibles) y `docs/quality/security-review.md` («filtrado/aislamiento multiempresa» → «aislamiento por `empresa_id`»; membresía → perfil).
- `docs/architecture/analisis-base-datos.md` (resumen de decisiones, `perfiles`/`roles`, validación de la implementación privada y riesgo de RLS con una sola empresa).
- `docs/decisions/001-rpc-privilegiadas.md`: encabezado de §8 («Invariante de aislamiento por `empresa_id`») y fila nueva de historial. Corrección terminológica sin cambio de comportamiento: las garantías, T4/T5/T15 y el estado (**APROBADA PARA VALIDACIÓN CONTROLADA**) no cambian. Se alinearon al modelo vigente (perfil 1:1, una empresa, un rol) las referencias normativas de «membresía» (§3.1, §8, §9, T2, T3 y la nota de inicio de sesión anónimo), sin cambio de comportamiento. Las apariciones históricas en el cuerpo anterior (historial, preguntas abiertas P5–P7 con texto conservado como registro, alternativas y la resolución de §18) no se reescribieron; la resolución vigente sigue en §18 (perfil 1:1, una empresa, un rol, sin tabla de membresías).

### No modificado

- `INVENTARIO_ETAPA_0.md` y las entradas históricas de este archivo (registro histórico).
- `supabase/migrations/*`, `supabase/tests/*`, `apps/web/*` y los comentarios SQL/tests del slice productos que aún dicen «multiempresa»: cambiarlos alteraría el hash auditado de `feat/catalogo-productos-supabase`. Pueden corregirse después de cerrar y mergear productos, en un cambio mecánico separado.
- El slice productos (`935bfcd5d693fb6404aaf32c806a09743d8431d8`) permanece intacto.

### Verificación

Cambio sólo Markdown: `git diff --check` y `git diff --name-only` (únicamente `.md`). No se ejecutaron Supabase, pgTAP, Vitest ni Playwright.

### Riesgos y pendientes

1. **Producción y migraciones remotas siguen bloqueadas** (ADR-001 sin aceptación final; `AGENTS.md` §5).
2. Al mergear el slice productos habrá un conflicto trivial en el historial de ADR-001 y en la parte superior de este archivo: se resuelve conservando ambas entradas.
3. Pendiente (fuera de esta tarea): comentarios «multiempresa» del slice productos, tras su merge.

## 23/10/2026 — Corrección post-Architect del slice productos (H-01 `service_role`)

**Rama:** `feat/catalogo-productos-supabase` · **Base:** checkpoint local `ecbfe94494a6d18cc7dc4f8f3600319b1959d9bb` (no pusheado) · **Estado:** corrección en commit local propio (sin amend del checkpoint; sin push), pendiente de **security review** (grants, `service_role`, RLS, `SECURITY DEFINER`) y de auditoría independiente del hash que se cree después. Sin push, merge, deploy ni Supabase remoto.

### Hallazgo de The Architect (veredicto APPROVED WITH CORRECTIONS)

- **H-01 (HIGH):** `service_role` conservaba por los privilegios por defecto de Supabase `INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER` sobre `public.productos`, además de `BYPASSRLS`. Con la service key se podía insertar un precio con fracción de centavo (redondeo silencioso a `numeric(14,2)`) o mutar `categoria`/`forma_venta`, salteando la validación de las RPC. La migración revocaba a `public`, `anon` y `authenticated`, pero no a `service_role`, y el pgTAP sólo cubría su `EXECUTE`.

### Corrección aplicada (decisión humana: complemento de P11-productos)

- `supabase/migrations/20261023140000_catalogo_productos.sql`: `revoke insert, update, delete, truncate, references, trigger on table public.productos from service_role`. Conserva `SELECT`. Se editó la migración existente porque el checkpoint no fue pusheado; no se creó otra.
- Sin cambios en `authenticated` (sólo `SELECT`), `anon`/`PUBLIC`, `propietario_rpc`, Topología D ni `EXECUTE` de `service_role` (ya revocado).
- **No se tocó** `service_role` sobre `perfiles`, Auth ni la administración de cuentas. **P11 global sigue pendiente.**
- `docs/decisions/001-rpc-privilegiadas.md`: P11-productos en §18.1 y fila de historial. El estado de ADR-001 no cambia (**APROBADA PARA VALIDACIÓN CONTROLADA**); no autoriza producción.

### Pruebas

- pgTAP (`supabase/tests/productos_catalogo.test.sql`, plan 114 → 125): `service_role` puede `SELECT`; no tiene ninguno de los seis privilegios de escritura (tabla ni columna); no ejecuta ninguna fachada ni implementación de productos. Prueba real: `set local role service_role` y se intenta `INSERT` directo (20.999), `UPDATE` de precio, `UPDATE` de categoría/forma de venta, `DELETE` y `TRUNCATE`; los cinco fallan con `42501` y una huella (cantidad de filas + md5) demuestra que la tabla no cambió.
- Mutaciones (en la base local, revertidas): conceder `INSERT` → fallan 4 pruebas; conceder `UPDATE (precio)` → fallan 3; conceder `ALL` (el estado anterior) → fallan 8; control sin mutación → 0 fallas.
- Playwright (`apps/web/tests/productos-catalogo.spec.ts`): 2 pruebas nuevas verifican el aviso de catálogo demo en `/jornadas` y `/movimientos`.

### M-02, M-03 y M-04

- **M-02 (aceptado):** `categoria`, `forma_venta`, `empresa_id` y `creado_por` son inmutables para **todas las rutas operativas** (`authenticated`, `anon`, `service_role` y `propietario_rpc` no tienen `UPDATE` sobre ellas; lo prueba el pgTAP). El owner de migraciones conserva capacidad administrativa por ser owner: no es una ruta de aplicación y **no se protege la tabla contra su propio owner con triggers**. Sin cambio de modelo.
- **M-03 (verificado):** `AvisoCatalogoDemo` ya se renderiza siempre en `Jornadas.tsx` y `Movimientos.tsx`. No se cambió código; faltaba cobertura y se agregó (Playwright).
- **M-04 (pendiente de staging):** `pg_graphql` no está habilitado en local, así que no se resuelve acá. **Gate obligatorio de staging:** `privado` no expuesto por GraphQL y `productos` sin mutaciones GraphQL que salteen las RPC. Producción sigue bloqueada hasta verificarlo.

### Cómo se verificó

`npx supabase db reset` OK; `npx supabase test db`: 180/180 PASS (55 de Auth + 125 de productos); `npm run typecheck`, `npm run lint` (exit 0), `npm test` (716), `npx playwright test` (60) y `npm run build` PASS. `supabase db advisors --local`: sólo 2 avisos INFO de rendimiento (FK `productos_creado_por_fk` sin índice; índice `perfiles_empresa_id_idx` sin uso); `supabase db lint --local`: sin errores.

### Riesgos pendientes

- Security review y auditoría independiente del nuevo hash.
- M-04 (GraphQL) como gate de staging; P11 global; convivencia con el catálogo demo (M-03) sigue bloqueando producción.
- Sin índice sobre `productos(empresa_id, creado_por)`: irrelevante con el volumen actual, a reevaluar.

## 23/10/2026 — Catálogo de productos en Supabase (slice productos)

**Rama:** `feat/catalogo-productos-supabase` · **Base:** `main` en `e5ce8aedd0b5d4dcb424a431187e9bd937e07fe6` (no depende del PR #7, todavía abierto) · **Estado:** implementación local completa; checkpoint local autorizado por decisión humana (commit «feat: implementar catalogo de productos en supabase»). Pendiente de **security review** (Supabase, RLS, `empresa_id`, roles, grants, `SECURITY DEFINER`) y auditoría independiente de ese hash. Sin push, merge, deploy ni migraciones remotas. Validación de base **sólo local**.

### Objetivo

Primer bloque backend operativo después de Auth: el catálogo de productos pasa de `localStorage` a Supabase, **sin stock** (el stock sólo saldrá de `movimientos_stock`, Blueprint §3.1 y §7.4) y sin mover dinero.

### Decisiones humanas usadas (23/10/2026, sólo para este slice)

- **DE-1** tabla `public.productos`; **DE-3** `codigo` opcional, único por empresa, normalizado con trim, vacío→NULL y mayúsculas intactas; **DE-4** nombre sin unicidad; **DE-5** `categoria`/`forma_venta` como texto con CHECK; **DE-6** categoría y forma de venta inmutables; **DE-7** sólo `creado_en`/`creado_por`; **DE-8** FK compuesta multiempresa para `creado_por`; **DE-9** los tres roles leen los productos de su empresa; **DE-10** `stock_minimo integer >= 0`; **DE-11 (modificada)** `empresa_id` se deriva del perfil en el servidor, no la envía el cliente; **DE-12** `/productos` pasa a Supabase y las pantallas operativas siguen con el catálogo demo; **DE-13** `/productos` no muestra ni carga stock; **DE-14** gana la última edición.
- **DE-2:** `precio numeric(14,2)`. Toda asignación a esa columna redondea antes de CHECK, trigger o RLS, así que el rechazo de más de 2 decimales se hace sobre un parámetro `numeric` sin escala, en una RPC. Con `SECURITY INVOKER` el usuario conservaría un INSERT/UPDATE directo que saltea la validación; por eso se usa **Topología D** (ADR-001 P1): fachada `SECURITY INVOKER` en `public` + implementación `SECURITY DEFINER` en `privado`, propiedad de `propietario_rpc`. `authenticated` sólo tiene SELECT sobre `productos`.
- **DE-15:** control de decimales por valor, `round(p, 2) = p` (`20.990` se acepta, `20.999` se rechaza).
- **P10-productos:** dueño y encargado crean, editan y cambian el estado; vendedor/piloto sólo lee. Operaciones: `crear_producto`, `actualizar_producto`, `cambiar_estado_producto`. **P14-productos:** sin sobrecargas en `public` ni en `privado`. **P16-productos:** códigos estables `producto_*` y mensajes seguros, nunca detalle SQL/PostgREST.
- **Aprobadas después de la implementación (mismo día), también acotadas al slice:** **P11-productos** `service_role` sin `EXECUTE` sobre estas RPC; **P12/P15-productos** el ABM no usa idempotencia; **P13-productos** sin bloqueos explícitos, gana la última escritura; **P17-productos** trazabilidad sólo con `creado_en`/`creado_por`, auditoría adicional futura.
- **Registro:** todas quedan en ADR-001 §18.1 («Decisiones de validación acotadas al slice productos»). **No resuelven P10–P17 globalmente**, no cambian el estado de ADR-001 (**APROBADA PARA VALIDACIÓN CONTROLADA**) y no autorizan producción.
- **Identidad dentro de `propietario_rpc` (decisión humana tras verificación local):** el rol de migraciones (`postgres`) **no puede** conceder `USAGE` sobre el esquema `auth` (propiedad de `supabase_admin`; el `GRANT` no tiene efecto). Por eso `privado.usuario_actual()` copia exactamente la expresión de `auth.uid()` (claim `sub` de `request.jwt.claims`). Mismo modelo de confianza; una prueba pgTAP verifica que coincidan.

### Implementación

- **Migración** `supabase/migrations/20261023140000_catalogo_productos.sql`:
  - `perfiles`: nueva unicidad `(empresa_id, usuario_id)` para la FK compuesta.
  - Rol `propietario_rpc` (`NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION`; si ya existe con otros atributos, la migración falla) y esquema `privado` (no expuesto). Se crean ahora porque son el primer objeto que los necesita (AGENTS §4.4). `CREATE` sobre `privado` se concede sólo para transferir la propiedad y se revoca al final.
  - Tabla `productos` (sin stock), con CHECK de normalización, categoría, forma de venta, combinación, precio `>= 0` y stock mínimo `>= 0`; unicidades `(empresa_id, codigo)` y `(empresa_id, id)`; FK compuesta `(empresa_id, creado_por)` → `perfiles`.
  - Grants: `authenticated` sólo SELECT; `propietario_rpc` SELECT, INSERT por columnas y UPDATE sólo de `codigo`, `nombre`, `precio`, `stock_minimo` y `activo`; nadie DELETE ni TRUNCATE.
  - RLS: lectura para `authenticated` por empresa del perfil activo; políticas propias de `propietario_rpc` (lectura, alta y edición acotadas a perfil activo, rol de gestión y misma empresa) y lectura de su propio perfil. Sin `FORCE`.
  - Funciones: 3 fachadas `SECURITY INVOKER` en `public` y 3 implementaciones `SECURITY DEFINER` en `privado` (`search_path = ''`, `VOLATILE`), más auxiliares `INVOKER` que sólo ejecuta `propietario_rpc`. `EXECUTE` sólo para `authenticated` en las 6 firmas exactas; revocado a `PUBLIC`, `anon` y `service_role`.
  - Errores: SQLSTATE `PT401/PT403/PT404/PT400/PT409` (PostgREST responde ese HTTP) con `message` estable (`producto_no_autenticado`, `producto_no_autorizado`, `producto_no_encontrado`, `producto_*_invalido`, `producto_codigo_duplicado`). Las violaciones de restricción se capturan y se traducen.
- **Seed local:** 4 productos de ejemplo (uno inactivo).
- **Frontend:**
  - `src/lib/supabase.ts`: el cliente pasa a un singleton compartido (`obtenerClienteSupabase`) para usar la misma sesión que Auth.
  - `src/lib/productos.ts` (nuevo): lectura fail-closed (una fila inválida invalida todo), escritura sólo por RPC sin enviar `empresa_id`, traducción de códigos estables y mensaje genérico para todo lo demás.
  - `src/hooks/useCatalogoProductos.ts` (nuevo): estados cargando/listo/error y relectura después de cada escritura.
  - `src/pages/Productos.tsx`: catálogo de Supabase con código, estado activo/inactivo, baja y reactivación; sin stock ni «stock inicial»; stock mínimo en unidad mínima (medias piezas para fiambres); errores en la página en lugar de `alert()`; botones deshabilitados durante el envío.
  - `src/components/AvisoCatalogoDemo.tsx` (nuevo), mostrado en Jornadas y Movimientos: aclara que esas pantallas usan el catálogo de demostración.
  - Hooks y datos demo (`useProductos`, `distribuidora_productos_demo_v4`) **sin cambios** (AGENTS §6.6).

### Verificación (desde `apps/web`, Supabase CLI v2.120.0, Docker local, PostgreSQL 17.11)

- `npx supabase db reset --workdir ../..`: aplica las tres migraciones y el seed sin errores.
- `npx supabase test db --workdir ../..` → `auth_base_rls.test.sql .. ok`, `productos_catalogo.test.sql .. ok`, `All tests successful.`, `Files=2, Tests=169`, `Result: PASS` (55 previas + 114 nuevas).
- **Mutaciones pgTAP** (en transacción revertida contra la base local; la base quedó intacta, verificado por catálogo): sin mutación → 0 `not ok`; conceder INSERT/UPDATE a `authenticated` → 3 `not ok`; quitar el control de decimales → 7; poner la implementación privada como `INVOKER` → 41; crear una sobrecarga expuesta → 1.
- `npm run typecheck` → exit 0 · `npm run lint` → exit 0 · `npm test` → 23 archivos / **716 tests passed** (antes 681) · `npx playwright test` → **58 passed** · `npm run build` → exit 0 (aviso preexistente de chunk > 500 kB) · `git diff --check` → exit 0.
- **Pruebas HTTP contra la Data API local** (Playwright): RPC con `20.999` (número o string) → 400 `{"code":"PT400","message":"producto_precio_invalido","details":null,"hint":null}`; RPC con `20.99` → se guarda exacto; INSERT/PATCH/DELETE directos → 403 `42501` y el producto queda igual; GET sobre RPC de escritura → 405; `Content-Profile: privado` → 406 `PGRST106`; vendedor → 403 `producto_no_autorizado` (pero lee el catálogo); sin sesión → 401 `42501`.
- Búsqueda de seguridad sobre las líneas agregadas (`service_role`, `sb_secret_`, `sb_publishable_`, JWT `eyJ…`, `SUPABASE_`, `user_metadata`, `password`): sin secretos; sólo la credencial de prueba local ya documentada, las revocaciones a `service_role` y la metadata falsa de los tests.

### Tests modificados

- `tests/storage-operativo-corrupto.spec.ts`: el caso de productos corruptos se verifica en `/jornadas`, que sigue usando el catálogo demo.
- `tests/catalogos-escritura-post-montaje.spec.ts`: se quitan los 3 casos de escritura demo de `/productos` (esa pantalla ya no escribe en `localStorage`); camiones y clientes no cambian.

### Riesgos y pendientes

1. **Security review obligatoria** antes de cerrar: primera función `SECURITY DEFINER`, primer rol técnico, grants por columna y políticas para `propietario_rpc`.
2. `privado.usuario_actual()` replica la implementación actual de `auth.uid()`. Si Supabase la cambia, la prueba de equivalencia lo detecta, pero la copia habría que actualizarla.
3. **`pg_graphql` no está habilitado en local**, así que no se pudo verificar si GraphQL alcanza `privado` (ADR-001 §17.1). Queda pendiente para staging.
4. El rol `propietario_rpc` y su membresía para el rol de migraciones dependen del entorno alojado: verificar en staging que `postgres` pueda crearlo, transferirle la propiedad de funciones y que no exista con otros atributos (ADR-001 §17.2).
5. No verifiqué si la CLI aplica cada archivo de migración en una única transacción (ADR-001 §12.5 pide crear y revocar sin ventana). Localmente no hay otros usuarios durante la migración; en staging/producción conviene confirmarlo.
6. Ediciones simultáneas: gana la última (DE-14). Un doble envío de un alta sin código podría duplicar el producto; la UI deshabilita el botón mientras envía.
7. Dos catálogos conviven (DE-12): los productos reales no aparecen en Jornadas/Movimientos hasta sus bloques de backend.
8. Los productos que crean las pruebas Playwright quedan en la base local (nombres únicos); `db reset` los limpia.
9. Producción y migraciones remotas permanecen bloqueadas.

## 23/10/2026 — Sincronización documental post-Auth

**Rama:** `chore/sincronizar-documentacion-post-auth` · **Base:** `main` en `e5ce8aedd0b5d4dcb424a431187e9bd937e07fe6` · **Estado:** implementado sin commit; pendiente de revisión humana. Sin push, merge, deploy ni migraciones remotas. Sólo Markdown.

### Contexto

- **PR #6** (`fix/auth-backend-auditoria`) mergeado en `main` con el merge commit `e5ce8aedd0b5d4dcb424a431187e9bd937e07fe6` (padres `e75560b` y `a76b52d`). Incorpora el bloque Auth (`d7c3664`) y su corrección post-auditoría (`a76b52d`).

### Cambios

- `docs/PRD.md`: encabezado sincronizado con la fila 0.10 del historial ya existente: **Fecha** 23/10/2026 y **Versión** 0.10. Sin cambios de requisitos.
- `BLUEPRINT.md` §10 y §15 (referencias operativas): «P2–P17 siguen pendientes» pasa a «P2–P7 están resueltas por decisión humana (ADR-001 §18); P8–P17 siguen pendientes». Cierra el riesgo 1 de la entrada «Corrección post-auditoría de Auth backend base». La fila 2.0 del historial del Blueprint queda intacta (describe correctamente el estado de ese momento).
- Sin cambios en el estado de ADR-001 (**APROBADA PARA VALIDACIÓN CONTROLADA**) ni en decisiones: P8–P17 siguen pendientes y P18 es una decisión futura separada.

### No modificado (registro histórico)

- `supabase/migrations/20261022120000_auth_base_empresas_perfiles.sql`: su comentario sobre P2–P4 pendientes refleja el estado al crearse la migración.
- Historiales/changelogs: fila 2.0 de `BLUEPRINT.md`, fila 0.9 de `docs/PRD.md`, filas v1.3–v1.5 y nota P1 (§5) de ADR-001, entradas anteriores de este archivo y la evidencia histórica de `INVENTARIO_ETAPA_0.md` (cuya errata E-13 ya refleja P2–P7 resueltas).

### Verificación

- `git diff --check` → exit 0.
- No se ejecutan Supabase local, pgTAP, Playwright ni build: el cambio sólo toca Markdown.

### Riesgos y pendientes

1. **Producción y migraciones remotas siguen bloqueadas** hasta pruebas, auditoría independiente y aceptación humana final (ADR-001; `AGENTS.md` §5).

---
## 23/10/2026 — Corrección post-auditoría de Auth backend base (`d7c3664`)

**Rama:** `fix/auth-backend-auditoria` · **Base:** `d7c3664266c6c57e074661fef4beb23771fdd661` (commit auditado y rechazado; no se modifica ni se reescribe) · **Estado:** implementado sin commit; pendiente de revisión humana, security review y auditoría independiente del nuevo hash. Sin push, merge, deploy ni migraciones remotas. Validación de base **sólo local**.

### Decisiones humanas aprobadas (23/10/2026)

- **P2:** `public` es el esquema expuesto para las tablas que la aplicación necesita; `privado` será el esquema no expuesto para futuras implementaciones privilegiadas.
- **P3:** rol técnico `propietario_rpc` (`NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS`), propietario únicamente de las funciones privilegiadas privadas necesarias y nunca de tablas de negocio. No se crea en SQL hasta que exista el primer objeto que dependa de él.
- **P4:** tablas de negocio bajo el owner de migraciones/Supabase; RLS obligatoria en toda tabla expuesta; sin `FORCE ROW LEVEL SECURITY` global (cualquier uso futuro se justifica y se prueba específicamente); futuras funciones `SECURITY DEFINER` en esquema privado, sin ser propietarias de tablas y validando explícitamente `auth.uid()`, empresa, rol, permisos, estado e integridad.

### Hallazgos y resolución

| Hallazgo | Resolución |
|---|---|
| **BLOCKER-01** (Codex): la base usaba `public`/owner de migraciones/RLS sin `FORCE` con P2–P4 pendientes | **Resuelto por decisión humana** P2–P4. Registrado en ADR-001 v1.5 (§7, §15, §16, §17.3, §18, §19), `docs/decisions/README.md`, `AGENTS.md` (§3 y nueva §4.4) y `CLAUDE.md`. Sin cambios en tablas, grants ni RLS de `empresas`/`perfiles`; no se crean `privado`, `propietario_rpc`, `SECURITY DEFINER` ni `FORCE`. Estado de ADR-001 sin cambios: **APROBADA PARA VALIDACIÓN CONTROLADA**; producción bloqueada. |
| **MEDIUM-01**: perfil obsoleto en memoria (eventos de Auth del mismo `user.id` ignorados) | **Corregido** (ver detalle). |
| **LOW-02**: el contrato de usuario aceptaba `abc.` y `a..b` | **Corregido** en TypeScript y SQL con el mismo contrato. |
| **LOW-03**: cobertura de `anon` limitada a SELECT | **Corregido** en pgTAP (catálogo y CRUD efectivo). |
| **LOW-01**: coherencia `perfiles.usuario` ↔ `auth.users.email` | **Diferido conscientemente a P11** (ver abajo). |

### MEDIUM-01 — solución técnica

- `apps/web/src/lib/supabase.ts` (`alCambiarUsuario`): se elimina la deduplicación por `user.id`. Cada evento de Auth (`INITIAL_SESSION`, `SIGNED_IN`, `TOKEN_REFRESHED`, `USER_UPDATED`, etc.) notifica al usuario vigente aunque no cambie, para volver a leer el perfil. Sin sesión (`SIGNED_OUT`) se notifica **en el acto**, sin `setTimeout`. Cada evento cancela el aviso diferido anterior todavía no entregado (y desuscribirse también lo cancela), así un aviso viejo no puede llegar después del logout ni de un cambio de usuario.
- `apps/web/src/auth/sesion.ts` — nuevo `crearControladorSesion(puerto, publicar)`, sin React ni Supabase:
  - **Generaciones:** cada evento, `invalidar()` y `detener()` incrementan un contador; sólo se publica el resultado de `resolverEstadoSesion` cuya generación sigue vigente. Una respuesta vieja de `leerPerfil(A)` no puede sobrescribir el estado de B ni volver a autenticar después del logout.
  - Cambio de usuario (o desde sin sesión): se publica `cargando` antes de leer, para no mostrar el perfil anterior.
  - Mismo usuario: se conserva el estado mientras se revalida y se reemplaza por el resultado (rol, empresa o `activo` nuevos). Un error de lectura publica `error` (fail-closed: se pierde el acceso).
  - El rol y la empresa siguen saliendo sólo de `perfiles`/`empresas`; no se usa el JWT.
- `apps/web/src/AuthContext.tsx`: el provider crea un controlador por suscripción (robusto ante el doble montaje de `StrictMode`) y `cerrarSesion` llama a `invalidar()` **antes** de esperar a `signOut`.
- Límite conocido: un cambio de perfil en la base no emite eventos de Auth; el frontend lo refleja en el siguiente evento (refresco del token, `SIGNED_IN` al volver a la pestaña, recarga). La autoridad efectiva sigue siendo RLS en el servidor: `empresas_select_propia` deja de devolver la empresa a un perfil inactivo en la siguiente consulta.

### LOW-02 — contrato de usuario

- Contrato único: `trim()` + minúsculas; 3–32 caracteres; empieza y termina con `a-z`/`0-9`; interiores `a-z 0-9 . _ -`; sin puntos consecutivos. Rechaza `abc.`, `.aabc`, `a..b`, `juan-`, `_juan`.
- TypeScript: `PATRON_USUARIO = /^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$/` + `es_usuario_valido` (sin `..`) en `apps/web/src/domain/usuario_auth.ts`; mensaje del login actualizado.
- SQL: **migración nueva** `supabase/migrations/20261023120000_perfiles_usuario_formato_estricto.sql` que reemplaza el CHECK `perfiles_usuario_formato` por `usuario ~ '^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$' and position('..' in usuario) = 0`. La migración auditada `20261022120000` no se edita (su comentario de cabecera sobre P2–P4 pendientes queda como registro histórico).
- Seed: los usuarios actuales ya cumplían el contrato; se documenta en la cabecera de `supabase/seed.sql`.
- **Alta futura documentada:** el procedimiento de «Creación de cuentas reales» de la entrada del 22/10/2026 sigue vigente, con este contrato para `perfiles.usuario` (el email de Auth es `<usuario>@usuarios.distribuidora.invalid`).

### LOW-03 — nuevas pruebas de `anon` (pgTAP)

- Catálogo: `anon` no tiene **ningún** privilegio (`SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER`) sobre `empresas` ni `perfiles`, incluido lo heredado de `PUBLIC`.
- Intentos efectivos como `anon` (`set local role anon`, nunca un rol que eluda RLS): INSERT, UPDATE y DELETE sobre ambas tablas → `42501`. UPDATE/DELETE van sin `WHERE` para que un grant accidental (que no fallaría por RLS) haga fallar la prueba; un INSERT concedido seguiría fallando por RLS y lo detecta el catálogo.
- Huella `md5` del contenido completo de ambas tablas antes y después de los intentos: sin cambios.

### LOW-01 — diferido a P11 (decisión consciente)

- No se agrega CHECK con subconsulta ni trigger privilegiado.
- Hoy la autorización usa exclusivamente `usuario_id = auth.uid()`; `perfiles.usuario` no participa de ninguna política ni decisión de acceso. No hay escalada directa conocida.
- Antes de implementar el alta administrativa real hay que diseñar, junto con P11, la creación coherente de la cuenta Auth y su perfil (mismo `usuario` y email derivado) y el reset de credenciales.

### Archivos

- Documentación: `docs/decisions/001-rpc-privilegiadas.md` (v1.5), `docs/decisions/README.md`, `AGENTS.md`, `CLAUDE.md`, `docs/PRD.md` (v0.10, sólo referencias a ADR-001), `docs/quality/{security-review,review-process,browser-testing}.md`, `docs/architecture/analisis-base-datos.md`, `docs/requirements/migracion-unidades-prototipo.md`, `docs/decisions/003-precio-derivado-media-pieza.md` y `004-cobros-jornada-cerrada.md` (sólo la nota de estado de ADR-001), `INVENTARIO_ETAPA_0.md` (actualización en la errata E-13), este archivo.
- Supabase: `supabase/migrations/20261023120000_perfiles_usuario_formato_estricto.sql` (nueva), `supabase/tests/auth_base_rls.test.sql`, `supabase/seed.sql` (comentario).
- Frontend: `apps/web/src/lib/supabase.ts`, `apps/web/src/auth/sesion.ts`, `apps/web/src/AuthContext.tsx`, `apps/web/src/domain/usuario_auth.ts`.
- Tests: `apps/web/src/auth/sesion.test.ts`, `apps/web/src/lib/supabase.test.ts` (se reemplaza el test que fijaba la deduplicación), `apps/web/src/domain/usuario_auth.test.ts`, `apps/web/tests/auth/auth.spec.ts`.

### Verificación (desde `apps/web`, Supabase CLI v2.120.0, Docker local)

- `npx supabase stop --workdir ../..` / `start` / `db reset`: aplica `20261022120000_auth_base_empresas_perfiles.sql` y `20261023120000_perfiles_usuario_formato_estricto.sql`, luego `seed.sql`, sin errores. Auth: `GOTRUE_EXTERNAL_EMAIL_ENABLED=true`, `GOTRUE_DISABLE_SIGNUP=true`.
- `npx supabase test db --workdir ../..` → `auth_base_rls.test.sql .. ok` · `All tests successful.` · `Files=1, Tests=55` · `Result: PASS` (antes 37).
- **Mutaciones pgTAP** (en transacción revertida contra la base local; la base quedó intacta): conceder INSERT/UPDATE/DELETE a `anon` → **6 `not ok`**; volver al CHECK anterior del usuario → **5 `not ok`**.
- `npx playwright test` → **49 passed** (1 setup + 13 auth, incluidos 3 nuevos de formato inválido que verifican que no se llama a `/auth/v1/token`, + 35 operativos).
- `npm run typecheck` → exit 0 · `npm run lint` → exit 0 · `npm test` → 22 archivos / **681 tests passed** (antes 649) · `npm run build` → exit 0 (aviso preexistente de chunk > 500 kB) · `git diff --check` → exit 0.
- **Mutaciones Vitest** (aplicadas y revertidas; archivos restaurados byte a byte): puerto con deduplicación y logout diferido → 3 fallas; controlador que ignora el mismo usuario → 6 fallas; controlador sin generaciones → 5 fallas.
- Búsqueda de seguridad (`service_role`, `sb_secret_`, `user_metadata`, `raw_user_meta_data`, `password`, `SUPABASE_`, JWT `eyJ…` y claves `sb_*` literales): sin secretos reales. Las líneas nuevas sólo contienen la mención documental de `propietario_rpc`; el resto de las coincidencias del árbol son las ya clasificadas (credencial de prueba local explícita, nombres de variables `VITE_SUPABASE_*`, parámetros `password` del login y tests de rechazo). `apps/web/.env.local`, `apps/web/playwright/.auth/`, `supabase/.temp/` y `apps/web/dist/` están ignorados y no versionados; `dist/` no contiene `sb_secret_` ni JWT.

### Riesgos y pendientes

1. `BLUEPRINT.md` §10 (línea 391) y §15 (línea 555) todavía dicen «P2–P17 siguen pendientes». No se modificó el Blueprint por instrucción: ADR-001 §2 establece que la ADR aprobada para validación controlada lo modifica dentro de las decisiones resueltas, de modo que no hay contradicción normativa que bloquee, pero conviene una sincronización explícita con decisión humana.
2. El esquema `public` está expuesto: toda tabla futura necesita RLS y grants explícitos (P4). La prueba de catálogo «todas las tablas de `public` tienen RLS» lo vigila.
3. `.invalid` es deliberado y válido como identidad técnica; no se cambia por un email real, no se habilitan confirmaciones de email ni recuperación por email. La recuperación/reset administrativo de contraseña queda ligada a P11.
4. LOW-01 diferido a P11 (ver arriba).
5. El seed que inserta directamente en `auth.users`/`auth.identities` es **sólo local/test**.
6. El CI todavía no ejecuta Supabase ni Playwright; la evidencia es la ejecución local citada.
7. Un cambio de perfil en la base se refleja en el frontend en el siguiente evento de Auth, no en tiempo real; RLS sigue siendo la autoridad.
8. Producción permanece bloqueada. Requiere security review (superficies auth, RLS, roles, `empresa_id`) y auditoría independiente del nuevo hash.

---
## 22/10/2026 — Auth backend base: Supabase Auth, empresas, perfiles y RLS

**Rama:** `feat/auth-backend-base` · **Base:** `main` en `e75560b6d2a2a49c9fc6029efaa14e8f23292468` · **Estado:** implementado sin commit; pendiente de revisión humana, security review independiente y auditoría independiente. Sin push, merge, deploy ni migraciones remotas. Validación de base **sólo local**.

### Objetivo

Reemplazar la autenticación demo (selector de usuarios + sesión en `localStorage`) por Supabase Auth real con usuario y contraseña, leyendo empresa y rol de la tabla protegida `perfiles`.

### Decisiones usadas

- Decisiones humanas de la tarea: Supabase Auth con cuentas individuales; login visible usuario + contraseña; sin registro público; cuentas creadas administrativamente; `perfiles` 1:1 con `auth.users`; una empresa y un rol por usuario; sin perfil o perfil inactivo ⇒ acceso denegado; nunca `user_metadata`; RLS desde el primer bloque; `service_role` prohibido en frontend.
- **ADR-001 P5/P6/P7 resueltas por decisión humana (22/10/2026)** y registradas en ADR-001 v1.4 §18, `AGENTS.md` §3/§4.3, `CLAUDE.md` y `docs/decisions/README.md`. El estado de ADR-001 no cambió. P2–P4 y P8–P17 siguen pendientes; P18 separada.
- Reparto de rutas (decisión humana): dueño y encargado acceden a lo que tenía el administrador del prototipo; vendedor/piloto a lo que tenía el vendedor; `/configuracion-demo` sólo dueño. El rol «depósito» desaparece.
- No se usó `SECURITY DEFINER`, RPC ni esquemas privados: las políticas RLS se resuelven con `auth.uid()` y una subconsulta sobre `perfiles` sujeta a su propia RLS.

### Estrategia usuario → Auth (detalle técnico de Auth, no email de negocio)

- Supabase Auth autentica con contraseña sólo por email o teléfono (documentación oficial de *Password-based Auth*, `signInWithPassword`); no ofrece login por username.
- `usuario` visible → `trim()` + minúsculas → debe cumplir `^[a-z0-9][a-z0-9._-]{2,31}$` → identidad interna `<usuario>@usuarios.distribuidora.invalid` (`.invalid` reservado por RFC 2606; no recibe correo).
- La columna `perfiles.usuario` guarda el valor normalizado con el mismo CHECK y `UNIQUE`, equivalente a unicidad case-insensitive.
- Las contraseñas sólo existen en Supabase Auth; el formulario descarta la contraseña después de cada intento.

### Creación de cuentas reales (pendiente, documentado)

Sin pantalla de administración ni Edge Function en este bloque. Procedimiento previsto, a ejecutar por una persona autorizada desde el panel o CLI de Supabase del entorno correspondiente (nunca desde el navegador de la aplicación):

1. Crear el usuario en Auth con email `<usuario>@usuarios.distribuidora.invalid`, contraseña inicial y email confirmado.
2. Insertar su fila en `public.perfiles` (`usuario_id`, `empresa_id`, `usuario`, `nombre`, `rol`, `activo`) con un rol administrativo de base.
3. Bajas: `activo = false` (la FK `ON DELETE RESTRICT` impide borrar cuentas con perfil).

Una herramienta de administración de usuarios requiere decisión aparte (P11, Edge Function o RPC privilegiada).

### Archivos

- Supabase: `supabase/config.toml` (`[auth] enable_signup = false`, `[auth.email] enable_signup = true`, password mínimo 8, URLs locales), `supabase/.gitignore`, `supabase/migrations/20261022120000_auth_base_empresas_perfiles.sql`, `supabase/seed.sql` (sólo local), `supabase/tests/auth_base_rls.test.sql`.
- Frontend: `apps/web/src/lib/supabase.ts`, `apps/web/src/auth/{sesion,roles,AuthContextValue}.ts`, `apps/web/src/domain/usuario_auth.ts`, `apps/web/src/AuthContext.tsx`, `apps/web/src/App.tsx`, `apps/web/src/pages/Login.tsx`, `apps/web/src/components/{ProtectedRoute,EstadoAcceso}.tsx`, `apps/web/src/components/layout/{AppLayout,Sidebar}.tsx`, `apps/web/src/pages/ConfiguracionDemo.tsx`; se elimina `apps/web/src/auth/usuariosDemo.ts`.
- Tests: `src/domain/usuario_auth.test.ts`, `src/auth/sesion.test.ts`, `src/lib/supabase.test.ts`, `src/components/ProtectedRoute.test.tsx`, `tests/auth/{auth.setup.ts,auth.spec.ts,cuentasPrueba.ts}`; los 8 specs operativos dejan de escribir la sesión demo y usan la sesión real del dueño de prueba (`storageState`).
- Configuración: `apps/web/playwright.config.ts` (proyecto `setup`), `apps/web/.env.example`, `apps/web/package.json` / `package-lock.json` (`@supabase/supabase-js@2.117.3`, `supabase@2.120.0` como devDependency, versiones exactas publicadas hace más de dos semanas).
- Documentación: `docs/decisions/001-rpc-privilegiadas.md`, `docs/decisions/README.md`, `AGENTS.md`, `CLAUDE.md`, este archivo.

### Modelo

- `empresas(id uuid PK, nombre text NOT NULL, activo boolean, creado_en timestamptz)`.
- `perfiles(usuario_id uuid PK FK auth.users ON DELETE RESTRICT, empresa_id uuid FK empresas, usuario text UNIQUE + CHECK formato, nombre text, rol text CHECK (dueno|encargado|vendedor_piloto), activo boolean, creado_en timestamptz)`.
- `rol` con CHECK sobre `text` y no enum: igual de restrictivo, legible en el DDL y modificable sin `ALTER TYPE`. Sin tabla `roles` ni membresías.
- Sin `actualizado_en`: en este bloque no existe ningún camino de modificación desde la aplicación; se agregará cuando exista uno.

### RLS y grants

- `REVOKE ALL` sobre ambas tablas a `public`, `anon` y `authenticated`; `GRANT SELECT` sólo a `authenticated`.
- `perfiles_select_propio`: `usuario_id = auth.uid()` (el usuario inactivo ve su fila para que la interfaz informe el bloqueo).
- `empresas_select_propia`: sólo la empresa de un perfil propio **activo**.
- Sin políticas ni grants de INSERT/UPDATE/DELETE.

### Verificación

- `npm run typecheck` → exit 0.
- `npm run lint` → exit 0.
- `npm test` → 22 archivos / 649 tests passed.
- `npm run build` → exit 0 (aviso preexistente de chunk > 500 kB).
- Búsqueda de seguridad de §13 (`service_role|secret|user_metadata|raw_user_meta_data|password|SUPABASE`) → sólo falsos positivos: comentarios, plantillas `env()` de `config.toml`, la credencial de prueba explícita del seed/E2E y los tests que verifican el rechazo de `user_metadata` y de claves secretas.
- **Validación SQL parcial sin Docker (no reemplaza `supabase test db`):** cluster PostgreSQL 17.11 descartable + stub mínimo de Supabase (roles `anon`/`authenticated`/`service_role`, `auth.users`, `auth.identities`, `auth.uid()` con la definición de Supabase y privilegios por defecto permisivos `GRANT ALL` a los tres roles) + pgTAP v1.3.3 cargado como SQL. Resultado: migración OK, seed OK, **37/37 aserciones `ok`**. Prueba de mutación (RLS de perfiles `using (true)`, empresas sin `p.activo` y `UPDATE` concedido): **13 `not ok`**, lo que confirma que la batería detecta regresiones.
- ~~**NO EJECUTADO:** `supabase start`, `supabase test db` y `npx playwright test`~~ → ejecutados con Docker; ver «Corrección de configuración Auth y workdir» más abajo.

### Corrección de configuración Auth y workdir (22/10/2026)

**Error de workdir encontrado.** Los comandos de la CLI se documentaron y ejecutaron desde `apps/web` con `--workdir ..`, que apunta a `apps/` y no a la raíz del repositorio. La CLI generó el directorio accidental `apps/supabase/` (sin `config.toml`, migraciones, seed ni tests: sólo `.branches/_current_branch`, `.temp/cli-latest` y los directorios vacíos `snippets/`, `tests/` y `.temp/start-secrets/`).

**Corrección.**
- `apps/web/playwright.config.ts` y `apps/web/.env.example`: `--workdir ..` → `--workdir ../..`. Búsqueda en todo el repo (excluyendo `node_modules`): no quedan otras ocurrencias de `--workdir`.
- Se verificó que `apps/supabase/` no tenía cambios manuales útiles y que el Supabase real sigue en `supabase/`; se eliminó sólo `apps/supabase/`. `supabase/` no se tocó salvo `config.toml`.
- `supabase/config.toml`: `[auth.email] enable_signup` pasó de `false` a `true`. En la CLI ese flag habilita el **proveedor email** (incluido el login con contraseña); con `false` el login de las cuentas existentes no estaba habilitado. El registro público sigue cerrado por `[auth] enable_signup = false`. No se agregó registro en el frontend.

**Configuración final de Auth (verificada en el contenedor `supabase_auth`):** `GOTRUE_EXTERNAL_EMAIL_ENABLED=true`, `GOTRUE_DISABLE_SIGNUP=true`. Comprobación directa contra la API local con la publishable key:
- `POST /auth/v1/token?grant_type=password` con `dueno.prueba@usuarios.distribuidora.invalid` y la contraseña de prueba → **HTTP 200**, `user.email` = `dueno.prueba@usuarios.distribuidora.invalid`, `access_token` presente. **Supabase Auth acepta el dominio `.invalid`.**
- Misma cuenta con contraseña incorrecta → **HTTP 400** `invalid_credentials`.
- `POST /auth/v1/signup` con `intruso@usuarios.distribuidora.invalid` → **HTTP 422** `signup_disabled` («Signups not allowed for this instance»).

**Stack real** (`npx supabase stop/start/db reset --workdir ../..`, CLI v2.120.0): migración `20261022120000_auth_base_empresas_perfiles.sql` y `seed.sql` aplicados sin errores.

**Resultados reales:**
- `npx supabase test db --workdir ../..` → `auth_base_rls.test.sql .. ok` · `All tests successful.` · `Files=1, Tests=37` · `Result: PASS`.
- `npx playwright test tests/auth/auth.setup.ts` → 1 passed (login real de `dueno.prueba`, «Dueño de prueba» visible).
- `npx playwright test` → **46 passed** (1 setup + 10 auth + 35 operativos previos).
- `npm run typecheck` → exit 0 · `npm run lint` → exit 0 · `npm test` → 22 archivos / 649 tests passed · `npm run build` → exit 0 (aviso preexistente de chunk > 500 kB) · `git diff --check` → exit 0.
- Búsqueda de seguridad repetida (`service_role`, `sb_secret_`, `user_metadata`, `raw_user_meta_data`, `password`, `SUPABASE`, más patrones de JWT `eyJ…` y claves `sb_*` literales): sin secretos reales en archivos versionables. Coincidencias = documentación, comentarios, plantillas `env()` de `config.toml`, la credencial de prueba local explícita (`seed.sql`, `tests/auth/cuentasPrueba.ts`) y tests que verifican el rechazo de `user_metadata`, `sb_secret_` y JWT de `service_role`. El bundle `dist/` no contiene `sb_secret_` ni JWT. `supabase/.temp/` (incluye `start-secrets`), `apps/web/.env.local` y `apps/web/playwright/.auth/` están ignorados por git.

### Riesgos

1. ~~Sin ejecución de pgTAP ni E2E~~ → resuelto en local: pgTAP 37/37 y Playwright 46/46. Sigue sin haber evidencia en staging ni en CI.
2. ~~Aceptación del dominio `.invalid`~~ → confirmada en el Auth local (HTTP 200). Debe reconfirmarse en el proyecto Supabase remoto cuando exista, junto con que `[auth.email]` quede habilitado y el signup cerrado (la config local no se propaga sola).
3. La coherencia entre `perfiles.usuario` y el email interno de `auth.users` depende del procedimiento administrativo; no hay constraint que la imponga.
4. El CI no ejecuta Supabase ni Playwright; los E2E dependen ahora de Supabase local.
5. `npm audit` informa 2 vulnerabilidades moderadas preexistentes en `vitest@5.0.2` / `@vitest/mocker` (no introducidas por este bloque).
6. Los módulos operativos siguen siendo demo sobre `localStorage`; este bloque sólo cambia autenticación y autorización de rutas.

### Pendientes

- ~~Ejecutar `supabase start`, `supabase test db` y la suite Playwright con Docker disponible.~~ Hecho en local (ver corrección de configuración Auth y workdir).
- Security review independiente y auditoría independiente del hash.
- Decidir la herramienta de alta de cuentas reales (P11) y la incorporación de Supabase/Playwright al CI.
- Alinear las menciones genéricas a «P2–P17» que quedan en `BLUEPRINT.md`, `docs/PRD.md`, `INVENTARIO_ETAPA_0.md`, `docs/quality/*`, `docs/architecture/analisis-base-datos.md`, `docs/requirements/migracion-unidades-prototipo.md` y ADR-003/ADR-004 (no modificados en este bloque; la fuente vigente de P5–P7 es ADR-001 §18).

---
## 22/10/2026 — Refuerzo de fuentes de verdad y contexto de negocio

**Rama:** `chore/reforzar-fuentes-proyecto` · **Estado:** bloque exclusivamente documental implementado; sin código, SQL, migraciones, Supabase, backend ni deploy.

### Qué se hizo

- Se explicitó la jerarquía documental: Blueprint → ADR aprobadas → PRD → AGENTS → CLAUDE → inventario.
- Se incorporó la lectura obligatoria previa para cambios de comportamiento, UI, frontend, backend, arquitectura, datos o seguridad, con verificación de versión documental y `HEAD`.
- Se estableció que `CLAUDE.md` es lectura obligatoria general para todos los agentes, aunque contenga instrucciones especialmente relevantes para Claude.
- Se definió el preámbulo obligatorio de cada tarea: objetivo de negocio, fuentes aplicables, estado actual, fuera de alcance, decisiones pendientes y plan corto. Los tests deben identificar los casos aplicables de Blueprint §12, los tests existentes a actualizar, los casos negativos y los comandos de verificación.
- Se reforzó el objetivo operativo de Fase 1 y los tres roles vigentes.
- Se agregó una prohibición explícita de sobrearquitectura y se aclaró que `empresa_id` no autoriza construir una plataforma SaaS.
- Se dejó asentado que ADR-001 P5–P7 siguen pendientes, que empresa y rol deben provenir de tablas protegidas y que una tabla separada de membresías no es un requisito aprobado.

### Archivos

- `AGENTS.md`
- `CLAUDE.md`
- `docs/progress-log.md`

### Verificación

- Verificación documental solicitada: `git diff --check`, `git diff --stat`, `git diff --name-only`, `git status --short` y búsqueda focalizada con `rg`.
- `git diff --check HEAD^ HEAD` → exit 0 sobre el commit `f95d5acb9fc19dc6d0e5cc24437043c76074c179`.
- `rg` solicitado sobre `AGENTS.md`, `CLAUDE.md` y `docs/progress-log.md` → exit 0.
- Alcance exclusivamente documental; no se ejecutaron tests de aplicación porque no hubo cambios de comportamiento ni de código.
- Revisión manual: el Blueprint conserva máxima autoridad; el PRD aporta contexto subordinado; el requisito se expresa como RLS y aislamiento por `empresa_id`, sin selector ni plataforma SaaS; P5–P7 continúan sin resolver; ADR-001 no fue modificada.
- Sin push, merge ni deploy.

### Riesgos pendientes

1. ADR-001 P5–P7 continúan pendientes de aprobación humana.
2. Este bloque no autoriza ni inicia ninguna implementación funcional, de frontend o de backend.
3. El nuevo commit de corrección requiere una nueva auditoría independiente; no se afirma que haya sido auditado.

---
## 22/10/2026 — Corrección documental post-auditoría · Bloque G / ADR-001

**Rama:** `chore/adr-001-gobernanza` · **Base obligatoria:** `c1190851de68e18b56edf10f56c701f9addb20c3` · **Estado:** H-1/H-2 corregidos; pendiente de nuevo commit y auditoría independiente del nuevo hash. Sin push, merge, deploy, backend, SQL ni migraciones.

### Correcciones

- **H-1:** ADR-003 deja de presentar ADR-001 como propuesta vigente y refleja su estado `APROBADA PARA VALIDACIÓN CONTROLADA`, con P1/P19/P20 resueltas, P2–P17 pendientes, P18 separada y producción bloqueada. ADR-003 no modifica ADR-001.
- **H-2:** ADR-004 conserva su propio estado `PROPUESTA — NO APROBADA`, refleja el estado intermedio vigente de ADR-001 y aclara que no la modifica ni amplía la autorización local/staging; P2–P17 y el bloqueo productivo se mantienen.

### Archivos

- `docs/decisions/003-precio-derivado-media-pieza.md`
- `docs/decisions/004-cobros-jornada-cerrada.md`
- `docs/progress-log.md` (trazabilidad obligatoria de `AGENTS.md`)

### Verificación

- Cambio exclusivamente documental; sin cambios de diseño ni resolución adicional de decisiones.
- `npm run lint` → exit 0.
- `npm run typecheck` → exit 0.
- `npm test -- --run` → 18 archivos / 591 tests passed.
- `npm run build` → exit 0.
- `npx playwright test` → 35 tests passed.
- `git diff --check` → sin errores.
- La búsqueda solicitada deja las referencias vigentes de ADR-003/ADR-004 alineadas; las coincidencias anteriores del progress log pertenecen a entradas cronológicas históricas.
- `git status --short` → sólo los tres archivos documentales enumerados, antes del commit.

### Riesgos pendientes

1. P2–P17 siguen pendientes y P18 continúa como decisión futura separada.
2. Producción continúa bloqueada.
3. El nuevo hash requiere auditoría independiente; no hubo push, merge ni deploy.

---
## 22/10/2026 — Alineación de gobernanza y Topología D · Bloque G / ADR-001

**Rama:** `chore/adr-001-gobernanza` · **Base:** `main` posterior al merge del PR #3 · **Estado:** cambio documental implementado; commit autorizado pendiente de auditoría independiente. **Sin backend, SQL, migraciones, Supabase, RPC, RLS, roles ni deploy.**

### Decisiones humanas registradas

- **P1 RESUELTO:** Topología D — Data API → fachada expuesta `SECURITY INVOKER` → implementación `SECURITY DEFINER` en esquema privado/no expuesto → validaciones completas → transacción de negocio. La implementación privada es la frontera real de seguridad.
- **P19 RESUELTO:** gobernanza en dos etapas — aprobación para validación controlada local/staging y aceptación humana final antes de producción.
- **P20 RESUELTO:** las migraciones dependientes de ADR-001 se permiten sólo para validación local/staging; producción permanece bloqueada.
- **P2–P17 continúan pendientes.** P18 continúa como decisión futura separada y no es requisito previo.

### Qué se hizo

- ADR-001 pasó a **APROBADA PARA VALIDACIÓN CONTROLADA** (v1.3), sin aprobación productiva.
- `BLUEPRINT.md` v2.0 reemplazó el wrapper público `SECURITY DEFINER` por Topología D, actualizó las pruebas de seguridad y registró el estado intermedio.
- El índice de ADR incorporó la semántica formal de `APROBADA PARA VALIDACIÓN CONTROLADA`: habilita exclusivamente diseño, migraciones y pruebas local/staging; no autoriza producción ni decisiones pendientes; exige pruebas, auditoría independiente y aceptación humana final.
- Se alinearon las instrucciones y documentos operativos que todavía trataban P1/P19/P20 como pendientes. Las referencias históricas previas se conservaron.
- El cierre frontend pre-backend ya fue mergeado en la base indicada. Este bloque no implementa backend.

### Archivos

- `BLUEPRINT.md`
- `AGENTS.md`
- `CLAUDE.md`
- `INVENTARIO_ETAPA_0.md`
- `docs/decisions/001-rpc-privilegiadas.md`
- `docs/decisions/README.md`
- `docs/PRD.md`
- `docs/architecture/analisis-base-datos.md`
- `docs/quality/review-process.md`
- `docs/quality/security-review.md`
- `docs/quality/browser-testing.md`
- `docs/requirements/migracion-unidades-prototipo.md`
- `docs/progress-log.md`

### Verificación

- Cambio exclusivamente documental. La suite completa se ejecutó por la compuerta general de `AGENTS.md`/proceso de calidad.
- `npm run lint` → exit 0.
- `npm run typecheck` → exit 0.
- `npm test -- --run` → 18 archivos / 591 tests passed.
- `npm run build` → exit 0.
- `npx playwright test` → 35 tests passed. El primer intento dentro del sandbox no pudo iniciar el `webServer`; la repetición con permiso para abrir el puerto local terminó con exit 0.
- `git diff --check` → sin errores.
- Búsqueda de `SECURITY DEFINER`, `SECURITY INVOKER`, P1/P19/P20, `validación controlada` y la prohibición histórica de migraciones → referencias normativas alineadas; referencias históricas preservadas y la E-13 del inventario deja explícita su supersesión.
- `git status --short` → sólo los archivos documentales enumerados en esta entrada, antes del commit.

### Riesgos pendientes

1. P2–P17 deben resolverse antes de implementar las partes que dependan de ellas y antes de una validación completa.
2. P18 sigue como decisión futura separada.
3. Producción continúa bloqueada hasta pruebas, auditoría independiente y aceptación humana final.
4. Por tocar RPC, `SECURITY DEFINER`/`SECURITY INVOKER`, permisos y gobernanza Supabase, corresponde revisión de seguridad independiente previa a la auditoría final.
5. El commit de este bloque requiere auditoría independiente sobre su hash; no hubo push, merge ni deploy.

---
## 22/10/2026 — Limpieza final pre-push · Bloque F

**Rama:** `feat/cierre-frontend-pre-backend` · **Base obligatoria / COMMIT_E:** `b8f7f067a6c48e27dd2ed04d838e1ca92f2a3f64` · **Estado:** limpieza y trazabilidad implementadas; pendiente de auditoría independiente sobre el hash de F. **ADR-001 continúa PROPUESTA — NO APROBADA**; backend no iniciado; sin push, merge ni deploy.

### Secuencia y alcance

- La auditoría del Bloque E concluyó `APPROVED WITH CORRECTIONS`.
- La security re-review de E concluyó `SECURITY APPROVED WITH CORRECTIONS`.
- M-1/M-2/M-3 quedaron cerrados en E.
- E-A1: se eliminó exclusivamente la línea vacía adicional al EOF de `apps/web/tests/toctou-jornadas-revalidacion.spec.ts`; no cambiaron assertions, tests ni lógica.
- E-A2: se actualizó el encabezado y la trazabilidad del incidente de ledgers corruptos con la secuencia real de B, C, D, security review de D, E, security re-review de E y F. F no se declara aprobado.
- Se registró ADR-004, `PROPUESTA — NO APROBADA`, sobre si un cobro puede asociarse a una jornada cerrada. El comportamiento actual exige jornada abierta cuando existe `jornadaId`; es preexistente y fue reforzado por E, pero el Blueprint no formaliza la regla. No se resolvió ni implementó la decisión.
- E-A3 queda como deuda conocida no bloqueante, clasificación L: preparación usa `producto.stock` del snapshot React. No existe un flujo intra-app que modifique el stock de un producto existente y el Blueprint no exige una relectura actual en esta etapa. No bloquea push ni merge.
- E-A4 queda como deuda conocida no bloqueante, clasificación INFO/L: preparación no revalida el estado actual del camión. El Blueprint no define esa precondición en preparación y la salida sí tiene una compuerta específica. No bloquea push.

### Archivos

| Archivo | Cambio |
|---|---|
| `apps/web/tests/toctou-jornadas-revalidacion.spec.ts` | eliminación de blank line al EOF (E-A1) |
| `docs/incidents/2026-10-22-ledgers-corruptos-en-consumidores-operativos.md` | encabezado, secuencia y deudas E-A3/E-A4 (E-A2) |
| `docs/decisions/004-cobros-jornada-cerrada.md` | nueva decisión propuesta, no aprobada |
| `docs/decisions/README.md` | índice de ADR-004 |
| `docs/progress-log.md` | esta entrada |

### Verificación

- `npm run typecheck` → exit 0.
- `npm test -- --run` → **18 archivos / 591 tests passed**.
- `npm run lint` → exit 0.
- `npm run build` → exit 0.
- `npx playwright test` → **35 tests passed**. El primer intento dentro del sandbox no inició Vite (`listen EPERM` sobre `127.0.0.1:4173`); el mismo comando ejecutado con permiso para abrir el puerto terminó con exit 0.
- `git diff --check` → sin errores.
- Alcance del diff verificado: solo el whitespace E-A1 del spec y documentación.

### Riesgos pendientes

1. E-A3 y E-A4 permanecen como deuda no bloqueante, sin implementación en F.
2. ADR-004 requiere decisión humana futura; no autoriza cambios de comportamiento.
3. F permanece pendiente de auditoría independiente sobre su hash.
4. Backend no iniciado. Sin push, merge ni deploy.

---
## 22/10/2026 — Cierre final de integridad pre-backend · Bloque E

**Rama:** `feat/cierre-frontend-pre-backend` · **Base obligatoria / COMMIT_D:** `9959f173b33577899172f1f9d5ebe9a64a27ddfc` · **Estado:** corrección implementada y verificada; pendiente de revisión humana previa al commit, auditoría independiente del nuevo hash y aprobación. **ADR-001 continúa PROPUESTA — NO APROBADA**; sin backend, sin push, merge ni deploy.

### Alcance

Security review del Bloque D quedó `BLOCKED` por M-1/M-2/M-3 (+ L-1 y L-2 triviales). Este bloque los corrige:

- **M-1 (catálogos):** Productos, Camiones y Clientes persistían con la lectura capturada al montar (un effect seguía pisando el storage con `lecturaInicial.ok === true` aunque la clave se hubiera corrompido después del montaje). Nueva frontera `catalogoStorage.actualizarCatalogoPersistido(clave, validar, iniciales, transformar)`: relee la clave discriminadamente en el momento de la operación, aborta (sin escribir y sin pisar el raw) ante corrupción, y solo actualiza React después de un `setItem` exitoso. Los hooks `useProductos`/`useCamiones`/`useClientes` dejaron de hablar con localStorage por effect: exponen `actualizarProductos`/`actualizarCamiones`/`actualizarClientes(transformar) => boolean`; las páginas muestran `No se pudo guardar el X en este navegador.` si el guardado falló. `persistirCatalogo` se conserva.
- **M-2 (jornada como dependencia mutable):** Autoventa (ventas) y Movimientos revalidan la Jornada vigente dentro del callback `validar` (última compuerta antes de persistir), usando la jornada fresca para armar ítems y stock. Cobros y Retornos revalidan después del `window.confirm` (Retornos además antes). Helpers puros en `domain/jornadas.ts` (`revalidar_jornada_para_operacion`, `revalidar_jornada_para_cobro`) sobre el lector discriminatorio `leerJornadasDiscriminado` (export de `useJornadas.ts`, sin parser paralelo). Cobros: la revalidación exige jornada existente y abierta (espejo del contrato vigente de la UI); si un cobro puede asociarse a una jornada cerrada es una decisión pendiente del Blueprint, no se inventó.
- **M-3 (preparación):** nueva frontera `crearPreparacionPersistida(jornada, validarStock)` en `useJornadas.ts` (devuelve `{ok,jornadas}|{ok,error}`): relee Jornadas y Retornos discriminadamente, comprueba unicidad (id / camión activo) contra lo leído AHORA, calcula el stock reservado con esas lecturas frescas y persiste al final. Hook `crearPreparacion(jornada, validarStock) => error|null`; `guardarPreparacion` ya no usa el snapshot del render para calcular stock de persistencia (el render mantiene el aviso de disponibilidad para la UI).
- **L-1 (rendición post-confirm):** `confirmarCierre` extrae `armarCierre()` (lecturas frescas de Ventas/Cobros/Movimientos + filas + resumen + conteos + diferencias) y lo ejecuta antes Y después del `window.confirm`; lo que se persiste es el armado final. Sin corrupción en la ventana, el cierre es idéntico (E2E de cierre exitoso).
- **L-2:** el incidente `docs/incidents/2026-10-22-ledgers-corruptos-en-consumidores-operativos.md` quedó actualizado: B y C como `BLOCKED` históricos, D `APPROVED`, E pendiente de auditoría del hash propio.

### Pruebas y sensibilidad

- Unit: +11 (`hooks/actualizarCatalogo.test.ts`), +14 (`domain/jornadas.test.ts`), +8 (`hooks/crearPreparacion.test.ts`) — fronteras M-1/M-2/M-3: lecturas frescas, raw intacto ante rechazo, claves ausentes como ledgers iniciales, duplicados, callback con lecturas frescas.
- E2E: +5 (`tests/catalogos-escritura-post-montaje.spec.ts`), +8 (`tests/toctou-jornadas-revalidacion.spec.ts`), +3 (`tests/toctou-preparacion-stock.spec.ts`), +2 (`tests/toctou-rendicion-post-confirm.spec.ts`) — corrupción/cierre/cambio de camión después del montaje y en la ventana del confirm; verifican aborto sin persistencia y raw intacto.
- Mutaciones temporales (todas revertidas antes de la verificación final; `grep` sin restos):
  - M-1: `useProductos` volvió a persistir con la lectura inicial por effect → 2 E2E de catálogos fallaron.
  - M-2: Autoventa y Movimientos sin revalidar Jornada (snapshot del render) → 2 E2E (jornada cerrada) fallaron.
  - M-3: `validarStockConLecturas` con las Jornadas del render → 1 E2E de stock fresco falló.
  - L-1: persistir con el armado previo (sin re-armado post-confirm) → 1 E2E post-confirm falló.

### Verificación final

- `npm run typecheck` → exit 0.
- `npm test -- --run` → **18 archivos / 591 tests passed**.
- `npm run lint` → exit 0.
- `npm run build` → exit 0.
- `npx playwright test` → **35 tests passed**.
- `git diff --check` → sin errores.

### Alcance y estado

- No se cambiaron precios, ADR-003, unidades, piezas/medias piezas, reglas de stock, dinero, saldos, tolerancias, medios de pago ni claves de storage. No se borraron ni debilitaron tests existentes (baseline 15 archivos / 558 tests y 17 E2E se mantienen).
- Sin recuperación, migraciones, Supabase, SQL, RPC, RLS, Auth ni service_role. Backend no iniciado.
- Confirmación definitiva sujeta a revisión humana del diff, auditoría independiente del hash del commit E y aprobación.

---
## 22/10/2026 — Cierre de hallazgos post-auditoría · Bloque D

**Rama:** `feat/cierre-frontend-pre-backend` · **Base obligatoria / COMMIT_C:** `a32c68abb542e5ca8c84c6f5f85baa1e7ac2b6fc` · **Estado:** corrección implementada y verificada; pendiente de auditoría independiente del nuevo hash. El Bloque B permanece históricamente `BLOCKED`; aprobar D no lo aprueba retroactivamente. **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Hallazgos cerrados

- **C-1:** se agregaron seis E2E TOCTOU sobre acciones productivas reales. Autoventa relee Movimientos después del montaje; Movimientos relee Ventas; Jornadas relee Retornos; y Rendición relee, por separado, Ventas, Cobros y Movimientos. En todos los casos se corrompe el storage después de montar, la acción aborta, el ledger destino queda intacto y el raw corrupto no se modifica.
- **C-2:** `guardarPreparacion` relee Retornos mediante `leerRetornosDiscriminado()`, aborta ante corrupción y recalcula el stock reservado con la lectura actual antes de validar disponibilidad y crear la jornada.
- **C-3:** `confirmarCierre` relee Ventas, Cobros y Movimientos con sus lectores discriminados. Con las lecturas actuales reconstruye las filas de mercadería, el resumen de caja, las diferencias y los valores persistidos en el cierre; recién después permite confirmar y delegar en `cerrarJornada`.
- **A-1:** queda cubierto incidentalmente por tres E2E que ejercitan directamente la guarda de `confirmarCierre` ante corrupción posterior al montaje.
- **A-2:** `completarConEsperados` incorpora una guarda productiva explícita de `disponibilidad.mercaderiaDisponible`, además del `disabled` ya existente.

### Pruebas y sensibilidad

- Nuevo `tests/toctou-storage-operativo.spec.ts`: 6 escenarios, sin sleeps, con storage aislado y acciones reales. Verifica ausencia de persistencia y conservación exacta del raw.
- Mutación temporal de Jornadas para volver al snapshot de Retornos: falló el E2E correspondiente (1/1), como se esperaba.
- Mutación temporal de Rendición para volver a snapshots de Ventas/Cobros/Movimientos: fallaron los tres E2E (3/3), como se esperaba.
- Mutación temporal de Autoventa y Movimientos para volver a sus snapshots: fallaron ambos E2E (2/2), como se esperaba.
- Todas las mutaciones fueron revertidas antes de la verificación final.

### Verificación final

- `npm run typecheck` → exit 0.
- `npm test -- --run` → **15 archivos / 558 tests passed**.
- `npm run lint` → exit 0, sin warnings.
- `npm run build` → exit 0.
- `npx playwright test` → **17 tests passed**.
- `git diff --check` → sin errores.

### Alcance y estado

- No se cambiaron precios, ADR-003, cantidades, piezas/medias piezas, reglas de stock, dinero, tolerancias, medios de pago ni claves.
- Sin recuperación, migraciones, Supabase, SQL, RPC, RLS ni Auth. Backend no iniciado.
- El Bloque C corrigió H-1/H-2/H-3, pero su auditoría encontró las brechas TOCTOU C-2/C-3 y la falta de pruebas C-1; este Bloque D las corrige. La confirmación definitiva queda sujeta a la auditoría independiente del hash de D.
- Sin push, merge ni deploy.

---
## 22/10/2026 — CIERRE FRONTEND PRE-BACKEND · Bloque C

**Rama:** `feat/cierre-frontend-pre-backend` · **Base original:** `42620e6ca5c061640aa1b58a5c42dd2939a3f02c` · **COMMIT_A:** `9f9d4c5d021f2f0969b6374474b533258f3a6661` · **COMMIT_B:** `1818ed27d43a9829c316be60edadf6063623fec0` · **Alcance de COMMIT_C:** integración, regresión, inventario y cierre documental; pendiente de crear el commit atómico autorizado. **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Alcance y correcciones de integración

- Se agregaron pruebas E2E sobre Rendición (Ventas corruptas, Cobros corruptos, Movimientos corruptos y estado inicial legítimo) y Cuentas Corrientes (Ventas o Cobros corruptos), verificando avisos, valores no disponibles, bloqueo de acciones y raw intacto.
- La integración detectó y corrigió tres dependencias que todavía podían consumir un `[]` visual como autoridad: Jornadas y Retornos ahora bloquean ante Retornos corruptos; Movimientos bloquea y relee Ventas discriminadamente antes de escribir; Autoventa bloquea ante Ventas o Movimientos corruptos y relee Movimientos discriminadamente dentro de la validación de stock.
- Rendición ahora muestra explícitamente `No disponible` también en “Vendido” cuando Ventas está corrupto; ya no presenta un guion ambiguo para ese cálculo.
- `useRetornos` expone su lectura discriminada y `estadoLectura` sin cambiar la escritura existente. No se agregó parser paralelo, recuperación, borrado, migración ni reescritura del raw.

### Inventario final de storage operativo

| Superficie | Key | Lector / ausencia / corrupción | Escritura | Fail-closed | UI avisa / bloquea | Deuda restante |
|---|---|---|---|---|---|---|
| Productos | `distribuidora_productos_demo_v4` | `leerProductos` vía `leerCatalogo`; ausente = semillas demo iniciales; corrupto discriminado, hook `[]` | `persistirCatalogo` | Sí | Sí / sí en operaciones consumidoras | Datos demo locales; sin recuperación |
| Camiones | `distribuidora_camiones_demo_v4` | `leerCamiones` vía `leerCatalogo`; ausente = semillas demo iniciales; corrupto discriminado, hook `[]` | `persistirCatalogo` | Sí | Sí / sí | Datos demo locales; sin recuperación |
| Clientes | `distribuidora_clientes_demo_v2` | `leerClientes` vía `leerCatalogo`; ausente = semillas demo iniciales; corrupto discriminado, hook `[]` | `persistirCatalogo` | Sí | Sí / sí | Key histórica fuera de `CLAVES_STORAGE`; sin recuperación |
| Jornadas | `distribuidora_jornadas_demo_v4` | lector discriminado interno; ausente = `inicial []`; corrupto = error y hook `[]` | `escribirJornadas` | Sí | Sí / sí | Persistencia local, sin concurrencia real |
| Ventas | `distribuidora_ventas_demo_v4` | `leerVentas`; ausente = `inicial []`; corrupto = error | `registrarVentaPersistida` | Sí | Sí / sí en Rendición, Cuentas, Autoventa y Movimientos | Dinero en floats; backend pendiente |
| Cobros | `distribuidora_cobros_demo_v4` | `leerCobrosDiscriminado`; ausente = `inicial []`; corrupto = error | `registrarCobroPersistido` | Sí | Sí / sí en Rendición y Cuentas | Dinero en floats; backend pendiente |
| Movimientos | `distribuidora_movimientos_demo_v4` | `leerMovimientosDiscriminado`; ausente = `inicial []`; corrupto = error | `registrarMovimientoPersistido` | Sí | Sí / sí en Rendición, Autoventa y Movimientos | Sin transacción ni concurrencia backend |
| Retornos | `distribuidora_retornos_demo_v4` | `leerRetornosDiscriminado`; ausente = `inicial []`; corrupto = error | `registrarRetornoPersistido` | Sí | Sí / sí en Jornadas y Retornos | Sin recuperación aprobada |
| Sesión demo | `distribuidora_sesion_demo_v1` | `AuthContext`; ausente o id desconocido = sin sesión | `AuthContext` login/logout | Sí para acceso demo | Login / rutas privadas bloqueadas | No es Auth real; backend no iniciado |

### Auditoría global

- No quedan `if (!guardado)` ni `if (!texto)` ejecutables sobre claves operativas; la única coincidencia es un comentario explicativo.
- No hay `JSON.parse(...)` directo en páginas o componentes.
- Las escrituras operativas están concentradas en los hooks/fronteras autorizados. `ConfiguracionDemo` conserva su reset explícito con rollback y `AuthContext` administra solamente la sesión demo; no se agregó ninguna escritura.
- Clasificación: los tres cruces de ledger corregidos eran bugs reales de Etapa 0. La persistencia local, floats monetarios, Auth/Supabase/RLS/RPC, idempotencia y concurrencia reales son deuda aceptada o fuera de alcance de este cierre.

### Verificación final

- `npm run typecheck` → exit 0.
- `npm test -- --run` → **15 archivos / 558 tests passed**.
- `npm run lint` → exit 0.
- `npm run build` → exit 0.
- `npx playwright test` → **11 tests passed**.
- `git diff --check` → sin errores.

### Estado y riesgos pendientes

- Productos, Camiones, Clientes, Jornadas, Ventas, Cobros, Movimientos y Retornos quedan fail-closed en escritura; sus consumidores operativos críticos muestran corrupción y bloquean la acción dependiente.
- No se implementó recuperación automática, import/export, offline, ARCA, app nativa ni cambios monetarios estructurales. El raw corrupto permanece intacto.
- **ADR-001 sigue PROPUESTA — NO APROBADA. Backend todavía no iniciado. Sin push, merge ni deploy.**
- Por tocar ventas, cobros, movimientos y cierres, corresponde revisión de seguridad y auditoría independiente posterior sobre cada hash concreto.

---
## 22/10/2026 — Plan maestro pre-backend · Bloque B: corrupción operativa visible en Jornadas y catálogos

**Rama:** `feat/cierre-frontend-pre-backend` · **Base del bloque:** `9f9d4c5d021f2f0969b6374474b533258f3a6661` (COMMIT_A) · **Estado:** Bloque B implementado y verificado, pendiente del commit atómico autorizado; sin push, merge ni deploy; **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Qué se hizo

- `useJornadas`, `useProductos`, `useCamiones` y `useClientes` exponen `estadoLectura` desde sus lectores discriminados existentes; no se agregó ningún parser paralelo ni se cambiaron las fronteras de escritura.
- Cuando un catálogo está corrupto, el hook ya no entrega semillas demo como datos operativos: expone una lista vacía acompañada por `estadoLectura: "corrupto"`. La ausencia legítima conserva la inicialización demo vigente.
- Aviso común y focalizado en las pantallas que dependen operativamente de esas fuentes: Productos, Camiones, Clientes, Jornadas, Autoventa, Movimientos, Retornos, Rendición y Cuentas Corrientes. Cada pantalla declara solo sus dependencias reales y bloquea su acción crítica principal si alguna está corrupta.
- El Dashboard, Login y Configuración Demo no reciben avisos nuevos: no consumen estas fuentes para una operación crítica de este bloque.
- No hay recuperación automática: raw intacto, sin borrar, reparar, migrar, resetear ni crear claves. Sin backend, Supabase, SQL, RPC, RLS ni Auth.

### Verificación

- `npm run typecheck` → exit 0.
- `npm test -- --run` → **15 archivos / 554 tests passed** (546 previos; +8).
- `npm run lint` → exit 0.
- `npx playwright test` → **6 tests passed**; los cuatro casos nuevos prueban Productos, Camiones, Clientes y Jornadas corruptos: aviso visible, semillas no usadas como catálogo, acción principal bloqueada, raw intacto y cero escrituras/borrados sobre la clave afectada.
- `npm run build` y verificaciones Git: se registran al cerrar el bloque antes del commit.

### Riesgos pendientes

- Las listas vacías durante corrupción no se presentan como un estado operativo válido porque siempre van acompañadas de aviso y bloqueo en las pantallas consumidoras; no se implementó recuperación.
- Retornos conserva su propio lector fail-closed previo, sin cambio de visibilidad en este bloque porque el inventario solicitado abarcó Jornadas, Productos, Camiones y Clientes.
- Por tocar ventas, cobros y cierre solo en sus dependencias visuales, corresponde revisión de seguridad y auditoría independiente posterior sobre el hash concreto.

---
## 22/10/2026 — Plan maestro pre-backend · Bloque A: Rendición fail-closed ante Movimientos corruptos

**Rama:** `feat/cierre-frontend-pre-backend` · **Base:** `42620e6ca5c061640aa1b58a5c42dd2939a3f02c` · **Estado:** Bloque A implementado y verificado, pendiente del commit atómico autorizado; sin push, merge ni deploy; **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Qué se hizo

- `useMovimientos` expone la misma lectura discriminada que ya protegía las escrituras: clave ausente → `inicial` con `[]`; array válido → `valido`; `""`, `"null"`, JSON inválido, no-array o movimiento inválido → `corrupto`. La lectura pública visual conserva su contrato previo y la escritura sigue fail-closed.
- Rendición consume `estadoLectura` de Movimientos. Si está corrupto, muestra un aviso explícito, deja mermas/cambios, esperado, diferencia y cuarentena como `No disponible`, conserva visibles los cálculos independientes confiables y bloquea completar esperados y confirmar el cierre.
- Ventas, Cobros y Movimientos mantienen avisos separados, sin duplicación accidental. La disponibilidad de caja no se pierde por corrupción exclusiva de Movimientos, pero el cierre sí queda bloqueado por consistencia de mercadería.
- No se agregó recuperación: no se borra, repara, migra ni reescribe el raw corrupto. Sin cambios de claves, reglas monetarias, backend, Supabase, SQL, RPC, RLS ni Auth.

### Verificación

- `npm run typecheck` → exit 0.
- `npm test -- --run` → **14 archivos / 546 tests passed** (535 previos; +11).
- `npm run lint` → exit 0.
- `npx playwright test` → **2 tests passed**; el nuevo E2E verifica aviso, valores `No disponible`, cierre bloqueado, raw intacto y cero `setItem`/`removeItem` sobre Movimientos.
- `npm run build` y verificaciones Git: se registran al cerrar el bloque antes del commit.

### Riesgos pendientes

- Sigue siendo un prototipo localStorage sin las garantías de backend del Blueprint; este bloque solo evita presentar corrupción como ausencia válida.
- Los estados discriminados de Jornadas y catálogos todavía no son visibles en sus consumidores operativos; se abordan en el Bloque B.
- Por tocar rendición/cierre, corresponde revisión de seguridad y auditoría independiente posterior sobre el hash concreto.

---
## 21/10/2026 — Avisos de storage corrupto en Rendición y Cuentas Corrientes

**Rama:** `feat/avisos-storage-corrupto` · **Base:** `2daad2a2e687148bcf0dfb83591b53c6b18b4a38` · **Estado:** implementado **sin commit**, pendiente de revisión humana; sin push, merge ni deploy; claves `distribuidora_ventas_demo_v4` y `distribuidora_cobros_demo_v4` sin cambios; **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Deuda cerrada

Las escrituras de Ventas y Cobros ya eran fail-closed, pero las pantallas consumidoras leían con las lecturas públicas (`[]` ante corrupción) y mostraban un ledger dañado como "cero ventas / cobros / saldo $0".

### Qué se hizo (solo UX/UI; sin escrituras ni recuperación)

- `useVentas` y `useCobros` leen una vez con `leerVentas()` / `leerCobrosDiscriminado()` (las mismas lecturas de las fronteras de escritura) y exponen `estadoLectura: "inicial" | "valido" | "corrupto"`. Contrato previo intacto (campos agregados, nada eliminado).
- Nuevo `pages/avisosStorage.ts` (funciones puras): `disponibilidadRendicion`, `disponibilidadCuentas`, `saldoSiDisponible` y los textos de aviso. Ausente (`getItem === null`) NO dispara aviso.
- **Rendición:** ventas corruptas → aviso, el vendido/esperado de mercadería se marca inconsistente (bloquea el cierre) y la caja no se calcula; cobros corruptos → aviso y la caja (efectivo, transferencias, totales, diferencia de efectivo) no se calcula. Los valores se muestran como "No disponible"; `confirmarCierre` se rechaza con el aviso. Las partes independientes siguen visibles.
- **Cuentas Corrientes:** el saldo exige ambos ledgers legibles; con ventas, cobros o ambos corruptos se muestra el aviso correspondiente, saldos/deuda total/estado de cuenta como "No disponible" (nunca $0), y el cobro queda deshabilitado. "Ventas fiadas" y "Cobrado" por cliente solo se muestran si su propio ledger es legible.
- Accesibilidad: `role="alert"`, ícono más texto "Datos dañados:" (no depende solo del color). Sin modal, sin librerías, sin botones de reparar/borrar, sin `setItem`/`removeItem` desde los avisos.
- Sin cambios en cálculos monetarios, tolerancias, escrituras, claves ni otras pantallas.

### Verificación

Tests (ejecutados desde `apps/web/`): **14 archivos / 535 tests** (493 antes: +42, todos en `pages/avisosStorage.test.ts`): estado de lectura real (ausente/válido/5 variantes corruptas por ledger), matrices de Rendición y Cuentas, textos exactos y ausencia de escrituras. Mutaciones temporales (saldo con un solo ledger / caja siempre disponible) hicieron fallar 6 / 10 tests y se revirtieron. Revisión manual en navegador (Playwright con storage aislado; ver entrega).

### Riesgos pendientes

- `Rendición` también depende de Movimientos (mermas/cambios), cuyo storage corrupto sigue leyéndose como `[]` sin aviso.
- Falta una acción de recuperación aprobada; el aviso es solo informativo.
- Sin tests de componente; la decisión de qué mostrar está en funciones puras y la integración en JSX se verificó manualmente.

---
## 21/10/2026 — Hardening de Ventas y Cobros: storage corrupto fail-closed

**Rama:** `fix/ventas-cobros-storage-fail-closed` · **Base:** `fbe2c96ad54bec759ca3296ec0e25d8e6986b141` · **Estado:** implementado **sin commit**, pendiente de revisión humana; sin push, merge ni deploy; claves `distribuidora_ventas_demo_v4` y `distribuidora_cobros_demo_v4` sin cambios; **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Riesgo cerrado

- **Ventas:** `cargarVentas()` usaba `if (!guardado)` y devolvía `[]` ante ausente, `""`, JSON inválido, no array o venta inválida; `registrarVentaOperacion` lo recibía como ledger actual, por lo que una venta nueva válida podía persistirse sobre un raw corrupto.
- **Cobros:** `leerCobros()` (`if (!texto)`) devolvía `[]` ante corrupción y `registrarCobro` lo usaba como cobros actuales; además `leerVentasActuales()` trataba `""` como ventas vacías y usaba un validador débil (sin `venta_valida`), divergente del contrato de Ventas.

### Qué se hizo

- `useVentas.ts`: `leerVentas()` discriminada (`getItem === null` → `inicial []`; válida; corrupta) con `venta_valida` como único contrato; `cargarVentas()` pública sigue fail-closed visual. `registrarVentaOperacion` recibe la lectura discriminada: 1) `venta_valida`, 2) lectura (corrupto → abortar **sin** llamar al callback de stock), 3) duplicado, 4) stock, 5) persistir. `registrarVentaPersistida` es la frontera real sin React; el hook delega en ella.
- `useCobros.ts`: `cobroValido` único, `leerCobrosDiscriminado()` y `leerCobros()` pública. `registrarCobroOperacion`/`registrarCobroPersistido`: 1) cobro válido, 2) cobros (corrupto → abortar), 3) duplicado, 4) ventas vía `leerVentas()` (corrupto → abortar; el saldo nunca se calcula sobre un `[]` artificial), 5) saldo, 6) persistir. Se eliminó `leerVentasActuales()`.
- Cobros ahora exige que TODAS las ventas guardadas pasen `venta_valida` (antes, un validador parcial).
- `domain/venta.test.ts`: el helper `crearCargarActuales` devuelve la lectura discriminada (único ajuste, por el cambio de firma).
- Política monetaria sin cambios (`redondearDinero`, tolerancias `0.000001`/`0.009`, medios, saldo máximo).

### Verificación

Tests (ejecutados desde `apps/web/`): **13 archivos / 493 tests** (465 antes: +28). Matrices de corrupción (JSON inválido, `""`, `"null"`, objeto, elemento inválido) para ventas, cobros y ventas vistas desde cobros, con raw idéntico, `setItem` no llamado y callbacks de stock/guardado no invocados; prioridades de corrupción. Mutaciones temporales (ignorar corrupción en ventas / en ventas desde cobros / en cobros) hicieron fallar 5 / 6 / 7 tests y se revirtieron. Resultado de typecheck, lint, build y Playwright: ver entrega.

### Riesgos pendientes

- Deuda monetaria NO tocada: el dinero sigue en floats con `Math.round`/tolerancias (`0.000001`, `0.009`); migrar a centavos enteros es otro bloque.
- `Rendicion` y `CuentasCorrientes` siguen leyendo con las lecturas públicas (`[]` ante corrupción) y no avisan; falta un aviso visible y una acción de recuperación aprobada.
- Sin tests de componente ni de los hooks React; la frontera probada es la función persistida que usa cada hook.

---
## 21/10/2026 — Hardening de catálogos (Productos, Camiones, Clientes): storage corrupto fail-closed

**Rama:** `fix/catalogos-storage-fail-closed` · **Base:** `ca34192a90f4809c3b9033ed9c9e95d44e5bc3f1` · **Estado:** implementado **sin commit**, pendiente de revisión humana; sin push, merge ni deploy; **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Riesgo cerrado

`cargarProductos/Camiones/Clientes` devolvían los datos demo ante cualquier storage inválido (y trataban `""` como ausente por `if (!guardado)`). Luego `useState(cargarX)` los dejaba como estado y el `useEffect` los escribía con `localStorage.setItem` al montar: un raw corrupto se pisaba automáticamente con datos demo, y también con cualquier edición posterior.

### Qué se hizo

- Nuevo `hooks/catalogoStorage.ts`: `leerCatalogo` distingue ausente (`getItem === null` → `inicial`, datos demo), válido y corrupto (`""`, `"null"`, JSON inválido, no array, elemento inválido, error de lectura); `persistirCatalogo` está atado al resultado de la lectura y **nunca escribe si fue corrupta**, ni al montar ni tras ediciones en la sesión.
- `useProductos`, `useCamiones`, `useClientes`: cada uno conserva su validador (extraído a `productoValido`, `camionValido`, `clienteValido`, sin cambios de reglas), expone `leerX()` discriminada y mantiene `cargarX()` (datos demo para la UI). El efecto llama a `persistirCatalogo(clave, datos, lectura)`. Contrato público sin cambios: `{ productos, setProductos }`, `{ camiones, setCamiones }`, `{ clientes, setClientes }`.
- Storage ausente conserva la inicialización demo existente. No hay acción de recuperación ni borrado del raw.
- Claves sin cambios: `distribuidora_productos_demo_v4`, `distribuidora_camiones_demo_v4`, `distribuidora_clientes_demo_v2`. No se tocaron ventas, cobros, jornadas, movimientos, retornos ni pantallas.

### Verificación

Tests (ejecutados desde `apps/web/`): **13 archivos / 465 tests** (442 antes: +23). Matriz por catálogo (ausente, válido, 4 variantes corruptas, elemento inválido) con raw idéntico y `setItem` no llamado al montar ni al editar. Mutaciones temporales: tratar `""`/`"null"` como ausente hizo fallar 6 tests; hacer que `persistirCatalogo` ignore la lectura hizo fallar 15; ambas revertidas. Resultado de typecheck, lint, build y Playwright: ver entrega.

### Riesgos pendientes

- Con storage corrupto la UI muestra los datos demo sin avisar y las ediciones de la sesión no se persisten (se pierden al recargar); falta un aviso visible y una acción de recuperación aprobada.
- `useVentas`, `useCobros` y `useJornadas` (ya endurecido) no se revisaron en esta tarea para el patrón del efecto.
- Sin tests de componente ni del hook React; la frontera probada es la función usada por el efecto.

---
## 21/10/2026 — Hardening Jornadas: storage corrupto fail-closed

**Rama:** `fix/jornadas-storage-fail-closed` · **Base:** `5cfe3bbbe5c3e27db954d98dd7c957ef66ec6207` · **Estado:** implementado **sin commit**, pendiente de revisión humana; sin push, merge ni deploy; storage sigue v4 (`distribuidora_jornadas_demo_v4`); **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Riesgo preexistente cerrado

`crearJornada()` leía con `leerJornadas()`, que devolvía `[]` tanto ante storage ausente como corrupto, y guardaba `[nueva]`: un storage de jornadas corrupto se sobrescribía en silencio (deuda registrada en el Bloque 7). `confirmarSalida` y `cerrarJornada` no lo hacían solo porque `[]` no contenía la jornada buscada.

### Qué se hizo (solo `apps/web/src/hooks/useJornadas.ts` y tests)

- Lectura interna discriminada `ResultadoLecturaJornadas`: `getItem === null` → `ok:true, estado:"inicial"` (`[]`); válido → `ok:true, estado:"valido"`; presente pero corrupto → `ok:false, estado:"corrupto"` (JSON inválido, `""`, `"null"`, no array, jornada/ítem/cierre inválido). Ya no se usa `if (!guardado)`.
- `jornadaValida` extraída de `leerJornadas` (misma validación, una sola fuente).
- `leerJornadas()` pública se mantiene fail-closed para la UI (`[]` si la lectura falla); ninguna escritura la usa como autoridad.
- Frontera única `escribirJornadas`: lee con discriminación, aborta sin escribir si está corrupto, aplica la transformación y persiste solo si esta la acepta.
- Rutas protegidas y testeables sin React: `crearJornadaPersistida`, `confirmarSalidaPersistida`, `cerrarJornadaPersistida`; el hook solo delega y actualiza el estado si se guardó. Las reglas de negocio (estados, un camión con una jornada no cerrada, conteos, cierre) no cambiaron.
- Sin cambios en otros hooks, Retornos, Rendición, Autoventa, precios, dinero ni claves de storage.

### Verificación

Tests (ejecutados desde `apps/web/`): **13 archivos / 442 tests** (406 antes: +36). Incluyen matriz de storage corrupto (7 variantes) × crear / confirmar / cerrar con comparación del string crudo antes/después y `setItem` no llamado, historial válido, duplicados y prioridad de la corrupción. Una mutación de prueba (tratar corrupto como `[]`) hizo fallar 8 tests y se revirtió. Resultado de typecheck, lint, build y Playwright: ver entrega.

### Riesgos pendientes

- Otros hooks (`useVentas`, `useProductos`, `useCobros`, `useCamiones`, `useClientes`) no se auditaron en esta tarea para el mismo patrón ausente/corrupto.
- Sin test de componente de las pantallas que usan `useJornadas`.

---
## 21/10/2026 — Bloque 7: corrección post-auditoría M-1

**Rama:** `feat/rendicion-medias-piezas` · **Commit auditado:** `75d0f57f4a2432cbd819923a99c80c45a9d449b7` · **Corrección funcional:** `74f9145b16d50b225d3b2b0be8d601cd5d1e718c` · **Auditoría:** `BLOCKED` por M-1 · **Estado:** corrección funcional commiteada; sin push, merge ni deploy; storage sigue v4; **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Hallazgo y corrección

- **M-1 — saldo falso en presentación de rendición:** cuando `acumularSalidasProducto` fallaba por cantidad inválida u overflow devolvía sentinels numéricos `vendido: 0`, `merma: 0`, `reemplazos: 0` junto con `valido: false`. `calcularFilaMercaderia` podía sumar esos ceros y producir `mermaYCambios = 0`, mostrando una cantidad falsa aunque la fila quedara `inconsistente`.
- **Corrección:** si `acumulacionInvalida === true`, `mermaYCambios` queda en `null`; también queda en `null` si la suma segura de merma y reemplazos falla.
- **Presentación:** `null` se muestra como `—`; nunca se presenta `0` como valor calculado cuando la acumulación falló.
- **Regresión:** se agregaron 4 tests específicos: suma válida, acumulación inválida, overflow directo y caso crítico `0 + 0` con acumulación inválida.

### Verificación

Ejecutado desde `apps/web/`:

- `npm run typecheck` → exit 0
- `npm test -- --run` → **13 archivos / 406 tests passed** (402 en el commit auditado; +4)
- `npm run lint` → exit 0
- `npm run build` → exit 0
- `npx playwright test` → 1 passed
- `git diff --check` → limpio

### Riesgos pendientes

- **Integridad de jornadas:** `crearJornada()` sigue leyendo con `leerJornadas()`, que colapsa storage corrupto a `[]`; una creación posterior podría sobrescribirlo. Es deuda preexistente fuera del alcance de esta corrección y requiere hardening específico.
- Permanecen validaciones `Number.isInteger` preexistentes fuera de este fix.
- La Rendición de este prototipo todavía no implementa conteos separados `apto` / `cuarentena` / `no_apto`, regularizaciones ni saldo final real del camión.

---
## 21/10/2026 — Bloque 7: Rendición compatible con medias piezas

**Rama:** `feat/rendicion-medias-piezas` · **Base:** `5fae38f28c5021b2d1047caebe99e650efa0cdfd` · **Estado:** implementado **sin commit**, pendiente de revisión humana; sin push, merge ni deploy; storage sigue v4; **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Qué se hizo

- Se eliminó `pieza_legacy` y `MENSAJE_PIEZA_LEGACY`: `unidad` y `pieza` se concilian con el mismo algoritmo en cantidades canónicas (enteros seguros; medias piezas para pieza). Estados: `ok | inconsistente | no_soportada` (este último, defensivo ante unidades runtime inválidas; sin camino kg).
- `domain/rendicion.ts`: `calcular_esperado` suma las salidas con `sumar_cantidades_seguras` (falla cerrado ante desbordamiento); `calcular_diferencia` verifica el rango seguro del resultado.
- `rendicion_calculos.ts`: `calcularFilaMercaderia` recibe el conteo ya canónico; nuevos helpers puros `conteoDesdeEntrada`, `acumularSalidasProducto` (vendido/merma/reemplazos con suma exacta) y `acumularCuarentena` (informativa; sin saldo aproximado ante overflow).
- `Rendicion.tsx`: conteo de pieza = piezas enteras + media con preview; "Completar con esperados" y la reconstrucción de cierres existentes usan `entrada_desde_cantidad`; diferencia de mercadería `!== 0` (sin epsilon); se quitaron `hayPiezaLegacy` y sus alertas. La lógica monetaria (`Math.round`, tolerancia de centavos) NO se tocó.
- `useJornadas.ts`: conteos del cierre y cantidades de ítems de carga usan `es_cantidad_valida` (enteros seguros); el cierre se extrajo a `cerrarJornadaPersistida` (testeable sin React).
- Fuera de alcance, sin cambios: apto/cuarentena/no_apto, regularizaciones, saldo final, dinero, SQL/RPC, Retornos, Movimientos, Autoventa, Jornadas UI, Productos, precios, venta, claves de storage.

### Verificación

Tests (ejecutados desde `apps/web/`): **13 archivos / 402 tests** (367 antes: +35). Cifra del commit auditado `75d0f57`; tras la corrección M-1 el total vigente es 406 (ver entrada superior). Resultado de typecheck, lint, build y Playwright: ver entrega del bloque.

### Riesgos pendientes

- **Integridad de jornadas:** `crearJornada` lee con `leerJornadas()`, que devuelve `[]` ante storage corrupto, y luego guarda `[nueva]`: sobrescribiría un storage de jornadas corrupto (análogo a H-1). `cerrarJornada` y `confirmarSalida` no lo hacen (no encuentran la jornada). Pendiente para un bloque propio.
- Siguen `Number.isInteger` preexistentes en `Autoventa.tsx`, `domain/venta.ts` y `domain/validacion.ts`.
- Sin test de componente de `Rendicion.tsx`.

---
## 21/10/2026 — Bloque 6: Retornos compatibles con medias piezas

**Rama:** `feat/retornos-medias-piezas` · **Base:** `6b24d6efbd087553e5423272fbb60544a8ec0832` · **Estado:** implementado **sin commit**, pendiente de revisión humana; sin push, merge ni deploy; storage sigue v4; **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Qué se hizo

- Nuevo dominio `apps/web/src/domain/retornos.ts`: validación única de ítem y retorno (enteros seguros, `0 <= aprobada <= contada`, sin `kg`, sin `productoId` duplicado), conversión de entrada de UI (piezas + media) a cantidad canónica, reconstrucción de la entrada desde la cantidad (completar con contado), `pendiente = contado - aprobado` exacto y comparación exacta del cierre. Reutiliza `domain/cantidades.ts`.
- `useRetornos.ts`: lectura interna discriminada (ausente = ledger inicial `[]`; válido; corrupto = error). `registrarRetornoOperacion` valida el retorno, lee el storage, aborta si está corrupto, rechaza jornada duplicada contra el storage leído en el momento y recién ahí persiste. `registrarRetornoPersistido` es la frontera real sin React. `leerRetornos()` sigue devolviendo `[]` para la UI.
- `Retornos.tsx`: pieza = piezas enteras + checkbox de media con preview; unidad = entero. Se eliminaron `cantidadValida` local, `esCantidadValida`, `Math.round(... * 1000)` y toda tolerancia `0.000001`. Un conteo de cierre que no es entero seguro bloquea la fila (fail closed).
- Semántica conservada: lo no aprobado queda pendiente; no se crea cuarentena, merma, movimiento ni incidencia (Blueprint §7.7 requiere otro diseño).
- No se tocaron Rendición, Movimientos, Autoventa, Jornadas, precios, venta, claves de storage ni backend.

### Verificación

Ver entrega del bloque para la salida de `typecheck`, `lint`, `build` y Playwright. Tests (ejecutados desde `apps/web/`): **13 archivos / 367 tests** (311 antes: +56).

### Riesgos pendientes

- Rendición sigue pendiente (`pieza_legacy`): los conteos de cierre de piezas aún pueden venir de una semántica anterior; Retornos solo los lee y los valida como cantidades canónicas.
- Siguen `Number.isInteger` preexistentes en `useJornadas.ts`, `Autoventa.tsx`, `domain/venta.ts` y `domain/validacion.ts` (otros bloques).
- Sin test de componente de `Retornos.tsx`; la UX queda cubierta por helpers de dominio y verificación manual pendiente.

---
## 21/10/2026 — Bloque 5: corrección post-auditoría (SIN COMMIT)

**Rama:** `feat/movimientos-medias-piezas` · **Commit auditado:** `fe255048d1caca8575704978775efa7e2ce85ce9` · **Auditoría:** BLOCKED · **Estado:** correcciones en el working tree **sin commit**; push, merge y deploy: **NO**; **ADR-001 continúa PROPUESTA — NO APROBADA**; storage sigue v4; Retornos y Rendición no se tocan.

### Hallazgos de la auditoría y corrección

- **H-1 (storage corrupto):** la escritura distingue clave ausente (ledger vacío) de storage corrupto (JSON inválido, no array, item inválido) y aborta sin llamar al callback de stock ni guardar. Faltaban tests de la frontera de escritura: se agregó `registrarMovimientoPersistido` (misma ruta que el hook, sin React) y tests contra un `localStorage` simulado que comparan el contenido antes/después y verifican `validar`/`guardar` no llamados.
- **M-1 (acumulación):** `salidas_de_jornada` acumula con `sumar_cantidades_seguras`; `disponibles_de_jornada` valida lo cargado y las salidas; `disponibilidad_de_jornada` es la única cadena (UI y validación previa al registro) y devuelve `ok:false` ante cantidades inválidas o desbordamiento, sin saldo aproximado, saturación ni redondeo.
- **M-2 (contrato):** `cantidad_movimiento_desde_entrada` captura en el dominio el desbordamiento de `recomponer_medias` y devuelve `null`; `Movimientos.tsx` la consume sin try/catch.
- **M-3 (Productos):** nuevo `stock_producto_valido` (basado en `es_cantidad_valida`, enteros seguros >= 0) usado por `Productos.tsx` y por la lectura de `useProductos.ts`.
- **L-1:** esta entrada.

### Verificación

Baseline auditado: 261 tests. La evidencia intermedia anterior de 278 tests correspondía a +17 en `cantidades` (no +23). Total tras estas correcciones (ejecutado desde `apps/web/`): **12 archivos / 311 tests** (+50 sobre 261); typecheck, lint, build y Playwright: ver entrega.

### Riesgos pendientes

- Quedan validaciones `Number.isInteger` (no `isSafeInteger`) en `Retornos.tsx`, `useRetornos.ts`, `useJornadas.ts`, `Autoventa.tsx:353`, `domain/venta.ts` y `domain/validacion.ts`; fuera del alcance de este bloque.
- Sin test de componente de `Movimientos.tsx`.

---
## 21/10/2026 — Bloque 5: Movimientos compatibles con medias piezas

**Rama:** `feat/movimientos-medias-piezas` · **Base:** `b48ce2c0c69ee6200e314af5727295e855228576` · **Estado:** implementado **sin commit**, pendiente de revisión humana; sin push, merge ni deploy; **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Qué se hizo

- Nuevo dominio puro `apps/web/src/domain/movimientos.ts`: entrada de UI (piezas enteras + media) a cantidad canónica, validador único de movimiento (`movimiento_valido`), salidas/disponibles de jornada y validación de stock con enteros exactos (se eliminó la tolerancia `+ 0.000001`). Reutiliza `domain/cantidades.ts`; no duplica conversiones.
- `useMovimientos.ts`: lectura y escritura comparten `movimiento_valido` (cantidad entera > 0, unidad `unidad|pieza`, sin kg). Nueva `registrarMovimientoOperacion` valida antes de llamar al callback de stock y de persistir (falla cerrado; no corrige, trunca ni redondea).
- `Movimientos.tsx`: producto `pieza` = piezas enteras + checkbox de media con preview (`medias_a_texto`); `unidad` = entero. Merma/devolución/cambio conservan su semántica; en cambio cada cantidad respeta la unidad de su producto. Historial y disponible legibles según unidad.
- `mockMovimientos.ts` sin cambios: no contiene datos demo ni `kg`.
- Storage sigue v4. No se tocaron `Retornos.tsx`, `Rendicion.tsx`, Supabase, SQL, RLS, RPC ni ADR-001.

### Verificación

Desde `apps/web/`: `typecheck` exit 0; `npm test -- --run` 12 archivos / 261 tests (217 antes); `lint` exit 0; `build` exit 0; `npx playwright test` 1 passed.

### Riesgos pendientes

- La duplicación estructural de stock del prototipo (Movimientos/Autoventa/Retornos) no se resolvió.
- No hay test de componente de `Movimientos.tsx`; la UX queda cubierta por helpers de dominio y verificación manual pendiente.
- Retornos y Rendición (`pieza_legacy`) siguen para bloques posteriores.

---
## 21/10/2026 — Bloque 4: Autoventa compatible con ADR-003 (precio derivado de media pieza) — CIERRE POST-AUDITORÍA

**Rama:** `feat/autoventa-medias-piezas` · **Código funcional auditado y pusheado:** `0fb6287640b9a0593544f2061a246ef1a3054411` · **Estado:** corrección funcional M-1 commiteada y pusheada a `origin/feat/autoventa-medias-piezas`; working tree limpio; pendiente únicamente de cierre documental y aprobación humana para merge; **sin deploy**; **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Secuencia de commits y auditoría

1. **Bloque 3b — precios/presentaciones:** `4060a1f79646b291f7913b504c0db218cf035b70`
   - Rama `feat/precios-presentaciones`.
   - Auditorías completadas.
   - Push realizado.

2. **Bloque 4 — implementación inicial de Autoventa:** `794efcdc5ed84527e7ebd394b8b3fac35cfd7754`
   - Adaptó Autoventa a cantidades canónicas en medias piezas.
   - Introdujo `construirDetalleVenta`, `construirItemsVenta` y validación compartida.
   - Auditoría detectó **M-1**: la frontera de escritura podía persistir una venta sin aplicar `venta_valida`.

3. **Corrección post-auditoría M-1:** `0fb6287640b9a0593544f2061a246ef1a3054411`
   - `registrarVenta` delega en `registrarVentaOperacion`.
   - `venta_valida(venta)` se ejecuta antes de callback de stock, persistencia y actualización de estado.
   - Lectura y escritura comparten el mismo validador monetario/estructural.
   - Agregados 13 tests específicos de frontera de escritura.
   - Suite vigente: **11 archivos / 217 tests passed**.
   - Auditoría posterior: **APPROVED WITH CORRECTIONS**, sin hallazgos H/M; M-1 cerrado.
   - Push realizado a `origin/feat/autoventa-medias-piezas`.

### Estado funcional actual

- **M-1 cerrado:** una venta monetariamente inválida no puede llegar al callback de stock ni persistirse.
- **L-1 PRD cerrado:** el precio de media pieza figura como derivado según ADR-003.
- **L-2 trazabilidad:** cerrado mediante esta actualización.
- Storage continúa en v4.
- No se tocó backend, SQL, Supabase, Auth, RLS, RPC ni ADR-001.
- No quedan bloqueos funcionales conocidos del Bloque 4.
- **Merge:** pendiente de aprobación humana final.
- **Deploy:** no autorizado.

### Verificación vigente

Ejecutado desde `apps/web/` antes del commit `0fb6287640b9a0593544f2061a246ef1a3054411`:

- `npm run typecheck` → exit 0
- `npm test -- --run` → **11 archivos / 217 tests passed**
- `npm run lint` → exit 0
- `npm run build` → exit 0
- `npx playwright test` → 1 passed
- `git diff --check` → limpio

### Qué se hizo (commit original 4060a1f + correcciones post-auditoría)

- **Autoventa.tsx** reescrito para usar exclusivamente las funciones del dominio compartido (`domain/precios.ts`, `domain/cantidades.ts`):
  - **Eliminado** cualquier cálculo manual `cantidad * precioReferencia` para productos por pieza.
  - **Importadas** y usadas: `precio_media_pieza`, `subtotal_linea`, `sumar_importes`.
  - **Cantidad canónica** para fiambres (`pieza`): internas en medias piezas enteras (1 = media, 2 = pieza, 3 = pieza + media, etc.).
  - **Snapshot histórico** en `DetalleVenta`:
    - `unidad`: `precioUnitario` = precio vigente; `precioMediaPieza` ausente.
    - `pieza`: `precioUnitario` = precio de pieza completa; `precioMediaPieza` = `precio_media_pieza(precioUnitario)` (snapshot derivado al momento de la venta).
  - **Subtotal** calculado con `subtotal_linea({ unidad_medida, cantidad, precio })` (maneja pieza/unidad correctamente).
  - **Total** derivado con `sumar_importes` (política monetaria existente, evita suma float ingenua).
  - **Validación antes de persistir**: cantidad válida, precio válido, snapshot de media correcto para pieza, subtotal válido, total válido, estructura compatible con `useVentas`.

- **UX actualizada** para fiambres (pieza):
  - Piezas enteras (input numérico) + media pieza (checkbox) — mismo patrón que Jornadas.
  - Preview legible: `= 1 pieza y media` / `= 2 piezas` / etc.
  - Lácteos (`unidad`): input numérico entero simple.

- **Frontera de escritura (M-1 corregido post-auditoría)**:
  - `useVentas.registrarVenta` ahora valida con `venta_valida` (domain/validacion.ts) **ANTES** de callback de stock, persistencia y actualización de estado.
  - Extraída función pura `registrarVentaOperacion` para testabilidad sin React.
  - Venta inválida monetariamente falla antes de cualquier efecto lateral.

- **No se tocó**: storage (sigue v4), backend, SQL, Supabase, Auth, RLS, RPC, migraciones, ADR-001 (sigue NO APROBADA).

### Archivos modificados (7 archivos en commit auditado 794efcd)

- `apps/web/src/pages/Autoventa.tsx`
- `apps/web/src/hooks/useVentas.ts`
- `apps/web/src/domain/venta.ts` (nuevo)
- `apps/web/src/domain/validacion.ts` (nuevo)
- `apps/web/src/domain/venta.test.ts` (nuevo)
- `docs/PRD.md`
- `docs/progress-log.md`

### Cómo se verificó

Ejecutado desde `apps/web/`:
- `npm run typecheck` → exit 0
- `npm test -- --run` → 11 archivos, **217 tests passed** (+13 tests frontera de escritura)
- `npm run lint` → exit 0
- `npm run build` → exit 0
- `npx playwright test` → 1 passed

### Auditoría (commit 794efcd) — Hallazgos cerrados en esta corrección

- **M-1 (bloqueante para merge):** `registrarVenta` permitía persistir venta sin aplicar `venta_valida`. **CORREGIDO**: validación compartida ejecutada ANTES de callback/persistencia/estado.
- **L-1 (PRD):** referencia a "precio de media queda pendiente". **CORREGIDO**: refleja ADR-003 aprobado.
- **L-2 (progress-log):** no reflejaba commit 794efcd, 7 archivos, 217 tests. **CORREGIDO** en esta entrada.

### Riesgos y pendientes

1. **Merge/deploy bloqueados** hasta revisión humana y auditoría independiente del hash (AGENTS.md §2.2).
2. **Superficies sensibles (AGENTS.md §2.4):** ventas y dinero (cálculo monetario local). Corresponde revisión de seguridad/humana y auditoría independiente.
3. ADR-001 sigue PROPUESTA — NO APROBADA; no se tocó backend/SQL/Supabase.

### Archivos nuevos

- `apps/web/src/domain/venta.ts` — función pura `construirDetalleVenta` / `construirItemsVenta`
- `apps/web/src/domain/validacion.ts` — validador compartido `venta_valida`, `item_valido`, `subtotal_coincide`, `total_coincide`
- `apps/web/src/domain/venta.test.ts` — **217 tests totales** (13 frontera de escritura M-1 + regresión M-1 original)

### Verificación completa POST-corrección

- `npm run typecheck` → exit 0
- `npm test -- --run` → 11 archivos, **217 tests passed**
- `npm run lint` → exit 0
- `npm run build` → exit 0
- `npx playwright test` → 1 passed
- `git diff --check` → limpio


---

Una entrada por tarea, la más reciente arriba. Cada entrada: qué se hizo, archivos modificados, cómo se verificó y riesgos pendientes.


---
## 21/10/2026 — ADR-003: precio derivado de media pieza, storage v4 y snapshot fail closed

**Rama:** `feat/precios-presentaciones` · **HEAD:** `a1ff9f9baf4c393113e14d0c923e1a3fdc38fdae` · **Estado:** cambios **sin commit**, sin push, sin merge, sin deploy; pendiente de revisión humana, revisión de seguridad del cálculo monetario y auditoría independiente del hash que se cree; **ADR-001 continúa PROPUESTA — NO APROBADA**.

### Decisión humana (21/10/2026)

ADR-003 — Precio derivado de media pieza, **APROBADA** por el dueño del proyecto. Supera a ADR-002 solo en la política de precio de media pieza (ADR-002 queda histórica y SUPERADA): media no configurable; mitad del precio de pieza redondeada al peso entero (`.50` sube, `< .50` baja), calculada en centavos enteros; cantidad canónica sigue en medias; snapshot de venta conserva la media aplicada; storage operativo v4; sin SQL aprobado.

### Qué se hizo

- **Documentación:** se crea `docs/decisions/003-precio-derivado-media-pieza.md` (el archivo **no existía** pese a que el código ya lo citaba); ADR-002 marcada SUPERADA (contenido histórico intacto); `docs/decisions/README.md`; `BLUEPRINT.md` v1.9 (§4, §7.1, §8 `productos`/`venta_items`, §12, §15, historial); `docs/PRD.md` v0.8 (RF-01, criterio de Stock, pregunta 13, historial); `docs/requirements/migracion-unidades-prototipo.md` (viñeta v4; la de v3 marcada histórica).
- **Dominio (`precios.ts`):** `precio_media_pieza` parte de `precio_a_centavos` y calcula `floor((centavos + 100) / 200)` restando el resto (sin división flotante), con `asegurar_entero_seguro`. Reemplaza `Math.round(precio_pieza / 2)`. `subtotal_linea_historica` rechaza `unidad` con `precio_media_pieza` (antes lo ignoraba) y sigue exigiéndolo en `pieza`; no re-deriva.
- **Tests:** `precios.test.ts` — un único `describe("subtotal de unidad")`; pieza 21 → `c=1 → 11`, `c=2 → 21` (y `not.toBe(22)`), `c=3 → 32`; media 20,98/20,99/21,00/21,01/21,02/20/21/25 → 10/10/11/11/11/10/11/13; equivalencia con `BigInt` para 0–100.000 centavos; desborde fail closed; snapshot unidad±media / pieza±media. `persistencia.test.ts` — v3 presente no se lee, copia ni borra; las 7 claves exactas v4; venta `unidad` con media rechazada; venta con media de snapshot distinta de la regla vigente aceptada; descripciones "v3" que se referían a la clave vigente pasan a "v4"; **corrige L2B**: los totales ±0,01 / 3 decimales se calculaban sobre 28.500 en lugar del total real 27.500 (pasaban por el motivo equivocado).
- **UI (`Productos.tsx`):** la vista previa de la media derivada ya no rompe el render si el precio tipeado es inválido (p. ej. `10.001`): muestra vacío.
- **Storage:** sin cambios de claves: las siete ya eran `_demo_v4` completas en disco; la truncación reportada era de visualización.
- **No se tocó `Autoventa.tsx`**, ni Auth, SQL, Supabase ni migraciones.

### Cómo se verificó

Ejecutado desde `apps/web/`: `npm run typecheck` exit 0 · `npm test -- --run` 10 archivos, **179 tests** passed · `npm run lint` exit 0 · `npm run build` exit 0 · `npx playwright test` 1 passed. `grep -Rni "_demo_v" apps/web/src` revisado línea por línea (sin claves truncadas ni lectura de v3 en hooks).

### Riesgos y pendientes

1. **Autoventa sigue sin adaptar** (Bloque 4): debe construir el snapshot con `precio_media_pieza` derivado; bloquea merge/deploy.
2. La vista previa de `Productos.tsx` no tiene test de componente (no hay infraestructura de render React en Vitest); verificado por lectura de código.
3. **Superficies sensibles (AGENTS.md §2.4):** ventas y dinero (cálculo monetario local). Corresponde revisión de seguridad/humana y auditoría independiente del hash.
4. Forma SQL de `venta_items` y precio `> 0`: siguen pendientes.

---
## 20/10/2026 — ADR-002 y Bloque 3b: precios independientes de pieza y media pieza

**Rama:** `feat/precios-presentaciones` · **Base:** `c188b8230029166c508dfb801b0a92c68b789263` · **Estado:** commit inicial del Bloque 3b `a1ff9f9baf4c393113e14d0c923e1a3fdc38fdae` **creado**; correcciones L1/L2A/L2B/L3 **pendientes de commit** (sin commit, sin push, sin merge, sin deploy); pendiente de revisión humana y auditoría; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Decisión humana (20/10/2026)

Los fiambres vendidos por pieza tienen **dos precios comerciales independientes** (pieza completa y media pieza), sin relación matemática obligatoria. La cantidad canónica sigue siendo un entero en medias piezas; comercialmente se descompone en `floor(c / 2)` piezas más como máximo una media (`c = 2` vale una pieza). Máximo 2 decimales (más de 2 se rechaza, sin redondear ni truncar); cálculo en centavos enteros; precio 0 no se resuelve como regla nueva (se mantiene `>= 0`). Claves operativas del prototipo `v2 → v3` por inicialización limpia; `clientes` queda en `v2` y la sesión en `v1`. Historial de venta del prototipo: Opción A. Forma SQL del historial: pendiente.

### Qué se hizo

- **Documentación:** `docs/decisions/002-precios-independientes-pieza-media.md` (APROBADA) y su fila en `docs/decisions/README.md`; `BLUEPRINT.md` v1.8 (§7.1, §8 `productos` y `venta_items`, criterios de aceptación, §15, changelog); `docs/PRD.md` v0.7 (RF-01, criterio de stock, pregunta 13, changelog); `docs/requirements/migracion-unidades-prototipo.md` (nota de v3).
- **Dominio:** `apps/web/src/domain/precios.ts` (única implementación: `precio_a_centavos`, `centavos_a_pesos`, `validar_precios_producto`, `precios_producto_validos`, `subtotal_linea_centavos`, `subtotal_linea`, `sumar_importes`), en centavos enteros y fail closed.
- **Modelo:** `Producto.precioMediaPieza?`, `ItemCarga.precioMediaPieza?` y `DetalleVenta.precioMediaPieza?` (historial Opción A); `Producto.precio` conserva su nombre.
- **Mocks demo:** queso cremoso en pieza 12.500 / 7.000; jamón cocido 12.500 / 7.500; salame milán 9.800 / 6.000 (valores de demostración, sin fórmula entre precios).
- **Storage v3:** `apps/web/src/data/clavesStorage.ts` (única definición). `useProductos`, `useJornadas`, `useVentas`, `useCobros`, `useMovimientos`, `useRetornos` y `useCamiones` usan las claves v3; `useJornadas`, `useVentas` y `useProductos` validan precios en la frontera de persistencia (en ventas, además, el subtotal debe coincidir con el dominio). `ConfiguracionDemo.tsx` usa las mismas claves.
- **Pantallas:** `Productos.tsx` (precio de pieza completa y precio de media pieza solo en fiambres; validación de dominio); `Jornadas.tsx` (valor de carga y total por jornada con `subtotal_linea`/`sumar_importes`, snapshot de `precioMediaPieza` y validación defensiva al guardar). **Corrige el bug de `c188b82`** (`medias × precio de pieza`).
- **No se tocó `Autoventa.tsx`** (Bloque 4), ni Movimientos, Retornos, Rendición, Auth, backend, SQL, Supabase ni migraciones.

### Cómo se verificó

Ejecutado desde `apps/web/`: `npm run typecheck` exit 0 · `npm test -- --run` 10 archivos, **151 tests** (107 → 151, +44: `precios.test.ts` 20, `persistencia.test.ts` +17, `mockProductos.test.ts` +3, `Jornadas.test.ts` +2) · `npm run lint` exit 0 · `npm run build` exit 0 · `npx playwright test` 1 passed. `persistencia-v2.test.ts` se renombró a `persistencia.test.ts`.

### Riesgos y pendientes

1. **Autoventa sigue sin adaptar** (Bloque 4): su subtotal `cantidad × precioReferencia` es incorrecto para fiambres cargados en medias hasta que use `domain/precios.ts`. No integrar ni desplegar el Bloque 3 sin el Bloque 4.
2. **Deuda de cobertura:** no existe test React → usuario → `localStorage` v3 → recarga; los tests son unitarios (dominio, hooks de lectura y lógica aplicada). `Jornadas.test.ts` no monta React ni verifica `valorItem` del componente, solo el dominio que usa.
3. Los datos demo operativos `v2` quedan sin uso y sin borrarse; el respaldo de `ConfiguracionDemo` también los exporta.
4. Los importes del prototipo se persisten como números en pesos (con 2 decimales exactos); la base futura usará `numeric(14,2)`.
5. Forma SQL exacta de `venta_items` y exigir precio `> 0`: decisiones pendientes.
6. **Superficies sensibles (AGENTS.md §2.4):** toca ventas, dinero e idempotencia de datos locales (sin auth, RLS, RPC ni Supabase). Corresponde revisión de seguridad/humana del cálculo monetario y auditoría independiente del hash; no se considera cerrado sin ellas.
7. **Autoventa (M1) diferido al Bloque 4** y bloquea merge/deploy hasta entonces.
8. **L1/L2A/L2B/L3 pendientes de commit** (sin commit, sin push, sin merge, sin deploy): validación de cantidad en `useJornadas`, validación de total histórico en `useVentas`, tests explícitos de `precio_a_centavos` para 0.01, 0.1, 0.2, 0.29, 1.01, 12.34 y rechazos. Requieren commit separado y nueva auditoría.

---
## 20/10/2026 — Bloque 3: UX canónica de pieza / media pieza en Jornadas

**Rama:** `feat/jornadas-medias-piezas` · **Base:** `9367b59e007838382503bbbb4914a7494d72fb22` · **Estado:** **cerrado en `c188b8230029166c508dfb801b0a92c68b789263`** (corrige M1/M2/L1/L2 del commit `9b4892202318dd878f3d35a27b3a9769f49beec0`); publicado en `origin/feat/jornadas-medias-piezas`; sin merge, sin deploy; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Qué se hizo (commit 9b48922)

Adaptación de la pantalla **Jornadas** al dominio canónico (Blueprint §7.1, §7.4):

- **Lácteos (`unidad`):** input numérico entero (`min=0`, `step=1`); se muestra "N un.".
- **Fiambres (`pieza`):** dos controles, piezas enteras (input) y media pieza (checkbox), con preview legible. Se persiste únicamente el entero canónico en medias piezas.
- **Dominio (`cantidades.ts`):** `medias_a_texto`, `descomponer_medias`, `recomponer_medias`.
- **Tests:** `cantidades.test.ts` 20 → 27 (+7) y `Jornadas.test.ts` nuevo.
- Baseline 89 tests → 107 (+18: +7 cantidades, +11 Jornadas).

### Auditoría del commit 9b48922

Resultado: **APPROVED WITH CORRECTIONS**. Hallazgos:

- **M1:** `Jornadas.test.ts` replicaba a mano la lógica de `Jornadas.tsx` (tests tautológicos) y su encabezado lo llamaba "integración".
- **M2:** este log contenía afirmaciones inexactas (ver abajo).
- **L1:** el input de piezas podía lanzar una excepción no capturada con decimales o `Infinity`.
- **L2:** en productos `unidad`, una cantidad inválida (p. ej. 0.5) participaba de la selección y del valor de carga hasta que `guardarPreparacion` la rechazaba.

### Correcciones post-auditoría (nuevo hash; requiere nueva auditoría)

- **M1:** lógica pura extraída a `apps/web/src/domain/cantidades.ts`: `maximo_piezas_segun_disponible`, `puede_agregar_media` y `cantidad_unidad_desde_texto`. `Jornadas.tsx` y `Jornadas.test.ts` importan **las mismas funciones**; el test ya no copia implementaciones. Regla de stock: `piezas * 2 + (media ? 1 : 0) <= disponible`.
- **L1:** el input de piezas valida con `es_cantidad_valida` (finito, entero, ≥ 0) antes de recomponer; si es inválido no actualiza el estado y muestra el error con el `setError` existente. Sin redondeo ni truncado.
- **L2:** una cantidad `unidad` inválida (0.5, negativo, NaN, Infinity) cuenta como 0 para selección, valor de carga y persistencia; `guardarPreparacion` la reporta como "Cantidad inválida" y mantiene su validación defensiva contra el stock.
- **M2:** este log corregido (ver siguiente sección).
- `Jornadas.test.ts` se clasifica como **test unitario de lógica aplicada a Jornadas**: no monta React, no usa `localStorage`, no es integración ni E2E.

### Correcciones al registro anterior (M2)

- Se retira "al recargar jornada existente → UX": **no existe** en `Jornadas.tsx` un flujo que cargue una jornada persistida al formulario; `descomponer_medias` solo está probada como función pura.
- Se retira "test de integración" y "lee/escribe correctamente `localStorage` v2" como hecho verificado: no hay prueba de eso.
- Se retira "usables en Android" (no verificado) y "rechaza en el input": en `unidad` el rechazo ocurre al guardar.
- Se corrige "sin commit": 9b48922 existe (sin push). Se retira la atribución "Agente: OpenCode".

### Verificación de las correcciones

Ejecutadas desde `apps/web/`: `npm run typecheck` exit 0 · `npm test -- --run` 9 archivos, **107 tests** (`cantidades.test.ts` 27, `Jornadas.test.ts` 11; el total no cambia respecto del commit auditado) · `npm run lint` exit 0 · `npm run build` exit 0 · `npx playwright test` 1 passed.

### Riesgos y pendientes

1. Alcance estricto: no se tocó Autoventa, Movimientos, Retornos, Rendición, Productos, Auth, backend, Supabase, SQL ni migraciones (esas pantallas requerirán la misma adaptación en otros bloques).
2. **Deuda conocida:** **NO existe** test React → interacción → guardar → `localStorage` v2 → recarga → reconstrucción de la UX.
3. Pendiente: nueva auditoría independiente del nuevo hash (§2.3.4).
4. ADR-001 sigue PROPUESTA — NO APROBADA; esta tarea no la toca.

### Cierre histórico del Bloque 3

- Bloque 3 cerrado en `c188b8230029166c508dfb801b0a92c68b789263`. Auditoría final acumulativa (`9367b59e…c188b823`): **APPROVED WITH CORRECTIONS**.
- Hallazgos restantes: L no bloqueantes, **aceptados por decisión humana** (entre ellos, que este registro mencionara «sin commit» para las correcciones y no nombrara `c188b82`; sin feedback de stock excedido en piezas; `Number()` acepta `1e1`; cast `as string` cosmético).
- Hallazgo posterior (Bloque 3b): el valor de carga de Jornadas de `c188b82` calculaba `cantidad canónica (medias) × precio de pieza`, inflando ×2 los fiambres. Se corrige en el Bloque 3b.
- La deuda E2E del Bloque 3 se mantiene: no existe test React → `localStorage` → recarga → UX.

---
## 20/10/2026 — Actualización documental: Blueprint v1.7, PRD v0.6, research, arquitectura y bitácora

**Rama:** `docs/actualizar-blueprint-v17-prd-v06` · **Base:** `86e58b36d252b5c1b8e31d5bd7d3e9910f94186a` · **Agente:** OpenCode · **Estado:** cambios **solo documentales** preparados **sin commit**, pendientes de revisión humana; **sin push, sin merge, sin deploy**; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Qué se hizo

Actualización de la documentación del proyecto para reflejar las **decisiones arquitectónicas aprobadas conceptualmente con ajustes** (autorización humana del 20/10/2026). No se tocó código, ni configuración de agentes, ni CI, ni skills.

Principales actualizaciones:

1. **`BLUEPRINT.md` → v1.7** (sección 17: historial):
   - §7.2: `merma` confirmada como **salida terminal** (`tipo_movimiento = merma`), NO ubicación interna. `cliente` confirmado como contraparte comercial, no ubicación.
   - §7.9: Sección nueva completa con decisiones aprobadas: operaciones (Alternativa B: tabla `operaciones` mínima), conteos separados, regularización explícita, **cierre derivado sin tabla propia** (jornada + rendición + operación tipo cierre), idempotencia centralizada en `operaciones`, concurrencia solo garantías funcionales, separación mercadería/dinero.
   - §8 (Modelo de datos): tabla de entidades actualizada con categorías corregidas:
     - `operaciones`: **APROBADA CONCEPTUALMENTE**
     - `ubicaciones`: **APROBADA CONCEPTUALMENTE** (merma NO interna)
     - `conteos`/`conteos_items`: **APROBADA CONCEPTUALMENTE**
     - `movimientos_stock`: **APROBADA CONCEPTUALMENTE** (ledger append-only, sin `saldo_actual`)
     - `cierres`: **DERIVADA / SIN TABLA EN FASE 1**
     - `roles` funcionales: **APROBADOS**; tabla `roles`: **PROPUESTA TÉCNICA**
     - `auditoria`: **DERIVADA / SIN TABLA**
     - `saldos_stock`: **DERIVADA**
     - `ledger financiero`: **DERIVADA / SIN TABLA EN FASE 1**
     - `rendicion_items`: **PROPUESTA TÉCNICA**
   - §9: Roles funcionales aprobados; tabla `roles` = PROPUESTA TÉCNICA.
   - §10: Auditoría sin tabla genérica; ADR-001 sigue PROPUESTA.
   - §13: Estructura de repositorio actualizada (apps/web en lugar de src/).
   - §15: Pendientes actualizados; nota de que decisiones §7.9 y §8 están aprobadas conceptualmente.

2. **`docs/PRD.md` → v0.6** (historial actualizado):
   - Acompaña a Blueprint v1.7; refleja mismas decisiones arquitectónicas.
   - §7: RF-03 y RF-04 actualizados con ubicaciones y cierre derivado.
   - §9: Ubicaciones actualizadas; merma = salida terminal.
   - §10: Dinero sin ledger financiero separado; `numeric(14,2)`.
   - §11: Auditoría sin tabla genérica; contradicción ADR-001/guía Supabase documentada como P1 pendiente.
   - §16: Auditoría actualizada (sin tabla `auditoria`).
   - §21/§22: Dependencias ADR actualizadas.

3. **`docs/research/referencias-open-source-stock.md`** (actualizado):
   - Matriz de correspondencia (§7) y síntesis (§8) actualizadas para reflejar decisiones aprobadas: tabla `operaciones` = APROBADA CONCEPTUALMENTE, tabla `cierres` = DERIVADA/SIN TABLA, merma = salida terminal (resuelto), auditoría sin tabla propia.
   - Categorías clarificadas: REFERENCIA EXTERNA vs DECISIÓN DEL PROYECTO vs PROPUESTA DEL PROYECTO.

4. **`docs/architecture/analisis-base-datos.md`** (nuevo, v0.1):
   - Consolidación del análisis de arquitectura de BD para Fase 1.
   - Clasificación de entidades (§2) con categorías vigentes.
   - Relaciones conceptuales (§3).
   - Detalle de entidades clave: `operaciones`, `movimientos_stock`, `ubicaciones`, `conteos`/`conteos_items`, `rendiciones`, `jornadas`, `retiros_efectivo` (§4).
   - Flujo de datos por operación crítica (§5).
   - Consultas derivadas (§6).
   - Reglas de seguridad pendientes ADR-001 (§7).
   - Decisiones abiertas para diseño SQL/RPC (§8).
   - Riesgos y próximos pasos (§9-10).

5. **`docs/progress-log.md`**: esta entrada.

### Archivos modificados/creados

- `BLUEPRINT.md` (v1.6 → v1.7)
- `docs/PRD.md` (v0.5 → v0.6)
- `docs/research/referencias-open-source-stock.md` (actualizado)
- `docs/architecture/analisis-base-datos.md` (nuevo)
- `docs/progress-log.md` (esta entrada)

### Cómo se verificó

Cambio **exclusivamente documental**. Verificación previa al commit:
- `git diff --check` — sin espacios en blanco problemáticos.
- `git diff --stat` y `git status --short` — solo los 5 archivos previstos.
- Lectura cruzada: BLUEPRINT §7.2, §7.9, §8, §9, §10, §13, §15, §17 coherentes con PRD §7, §9, §10, §11, §16, §21, §22 y research §7, §8.
- No se ejecutaron pruebas de aplicación porque no hubo cambios de código.

### Riesgos y pendientes

1. **Implementación bloqueada:** ADR-001 sigue **PROPUESTA — NO APROBADA** (v1.2, ronda 3); P1–P20 pendientes. No se generan migraciones ni RPC hasta aprobación y pruebas de autorización.
2. **Decisiones PROPUESTA TÉCNICA pendientes** (requieren diseño SQL/RPC y aprobación): esquema exacto de `perfiles`/membresías/rol, `idempotency_key`, `ubicaciones` (fila por camión vs. genérica), `rendicion_items`, `retornos`/`mermas`, `gastos_ruta`/`talonarios`/`notas_talonario`, estrategia de concurrencia.
3. **Propuestas NO APROBADADAS que NO se implementan:** stock negativo transitorio, anulación por vendedor, prohibición descuentos, retiro sin bloqueo, vencimientos por partida/`partidas_ingreso`.
4. **Fase 2 confirmada fuera de alcance:** proveedores/compras, preventa, cuentas corrientes, lotes/FEFO.
5. **Commit pendiente:** requiere revisión humana, autorización de commit, auditoría independiente del hash, aprobación humana final, push/merge/deploy con autorizaciones explícitas por paso.
6. Los 10 archivos `docs/propuesta_v2_*.md` siguen siendo **BORRADORES DE TRABAJO**; no se comitean como documentación final. Al terminar la documentación definitiva, se propondrá su eliminación antes del commit final.

---

## 20/10/2026 — Saneamiento documental del proceso (previo a Blueprint v1.7)

**Rama:** `refactor/migrar-unidades-prototipo` · **Base:** `86e58b36d252b5c1b8e31d5bd7d3e9910f94186a` · **Agente:** Claude Code · **Estado:** cambios **solo documentales** preparados **sin commit**, pendientes de revisión humana; **sin push, sin merge, sin deploy**; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Qué se hizo

Corrección de las inconsistencias documentales detectadas por la auditoría integral del 20/10/2026. No se tocó código, `BLUEPRINT.md`, `.claude/settings.json`, `opencode.json`, CI, skills ni worktrees.

- **Lint:** `docs/incidents/2026-10-12-lint-falla-en-main.md` pasa a `resuelto` (se conserva como histórico); `docs/incidents/README.md`, `AGENTS.md` §9, `CLAUDE.md`, `docs/quality/review-process.md` §2.5 y `docs/PRD.md` §18 dejan de hablar de «errores preexistentes» / «incidente abierto»; regla vigente: `npm run lint` debe terminar con exit 0.
- **Blueprint sin versión hardcodeada:** `AGENTS.md` §3 ya no cita «Blueprint v1.4»; remite a Blueprint §15 y a las secciones citadas.
- **Referencias por línea:** `docs/quality/security-review.md` (§3 y §4) reemplaza `§10:279`, `§10:277`, `§10:274-276` y `§6:97` por referencias a sección y viñeta. La regla de seguridad no cambia.
- **Auditor de OpenCode:** `AGENTS.md` §2.3.2 y `docs/quality/review-process.md` §2.9 documentan que es auditoría estática de solo lectura y que no puede verificar por sí mismo hash, diff, estado del árbol, tests, typecheck, lint, build ni Playwright; esa evidencia viene de CI o de ejecución humana reproducible. Permisos sin cambios.
- **Flujo de commit/auditoría:** `AGENTS.md` nuevo §2.2.1 formaliza la secuencia (implementación sin commit → revisión humana → autorización de commit → verificación reproducible → auditoría del hash → corrección + nuevo hash → aprobación humana → push/merge/deploy con autorización). Se eliminó «cuando sea posible» en `AGENTS.md` §2.3.3 y `review-process.md` §3.5.
- **Bitácora:** entradas del 18 y 19/10 que decían «sin commit ni push» ahora indican que en ese momento aún no había commit y el hash en que se consolidaron; la entrada de Bloque 2 suma «Estado posterior» con commit, parent, auditoría APPROVED, verificación y ausencia de push/merge/deploy.
- **Convención de nombres (decisión humana aprobada el 20/10/2026):** `AGENTS.md` §7 pasa a «Idioma y convención de nombres»: dominio TypeScript nuevo y SQL en español `snake_case`; tipos, interfaces y componentes React en `PascalCase`; código React/UI existente sin renombre masivo. Decisión documental: no se modificó código fuente.
- **Referencias por línea en `docs/PRD.md`:** `§10:279`, `§10:277`, `§10:274-276` y `§6:97` reemplazadas por referencias a sección y viñeta, sin cambiar requisitos, alcance ni estado de ADR-001 ni versión del PRD.
- **`CLAUDE.md`:** alineado con `AGENTS.md` (implementación sin commit, autorización humana por paso, lint exit 0, alcance del auditor). Se corrigió además la referencia cruzada de `review-process.md` a «Procedimiento 5».

### Archivos modificados

`AGENTS.md`, `CLAUDE.md`, `docs/PRD.md`, `docs/progress-log.md`, `docs/incidents/README.md`, `docs/incidents/2026-10-12-lint-falla-en-main.md`, `docs/quality/review-process.md`, `docs/quality/security-review.md`, `docs/PRD.md`.

### Cómo se verificó

Cambio exclusivamente documental. `git diff --check`, `git diff --stat` y `git status --short` revisados antes de pedir revisión; búsqueda de las expresiones eliminadas sin resultados en los archivos autorizados.

### Pendiente (no se tocó)

1. ~~Convención de nombres~~ y ~~citas por línea en `PRD.md`~~: resueltas con aprobación humana en esta misma tarea (ver arriba).
2. Auditoría independiente del bloque 1+1B (`91078a5`): no hay registro versionado.
3. Push de la rama e integración de las ramas pendientes a `main`.
4. `.claude/settings.json` (reglas `deny`), CI (Playwright, `timeout-minutes`, `.nvmrc`), notas de uso en skills, archivo de `INVENTARIO_ETAPA_0.md` y retiro del worktree `-skills`.

---

## 19/10/2026 — Bloque 2: consistencia categoría ↔ unidad en la pantalla Productos

**Rama:** `refactor/migrar-unidades-prototipo` · **Base:** `91078a5331db54684f2d83be4d32067e7dea7d69` · **Agente:** OpenCode · **Estado:** implementación parcial con validación defensiva también en la frontera de persistencia (localStorage v2); **en el momento de redactar esta entrada aún sin commit; luego consolidada en el commit `86e58b36d252b5c1b8e31d5bd7d3e9910f94186a`** (parent `91078a5331db54684f2d83be4d32067e7dea7d69`; ver «Estado posterior» abajo); **sin push, sin merge, sin deploy**; **la migración del prototipo todavía no está completa**; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Qué se hizo

Regla vigente (BLUEPRINT.md v1.6 §7.1): la categoría determina la unidad de venta. `Lácteos` → `"unidad"`; `Fiambres` → `"pieza"`. Toda otra combinación es inválida.

- `apps/web/src/domain/productos.ts` (nuevo, lógica pura sin React; creado originalmente como `apps/web/src/pages/productos_validacion.ts` y movido a `domain/` antes del commit, sin dejar duplicados):
  - `unidad_para_categoria(categoria)`: devuelve `"unidad"` para Lácteos y `"pieza"` para Fiambres.
  - `validar_combinacion_categoria_unidad(categoria, unidad_medida)`: devuelve `{ valido, mensaje? }`; rechaza `Lácteos + pieza` y `Fiambres + unidad` con mensaje visible.
  - Los tipos se reutilizan de `../data/mockProductos` (sin unions duplicadas).
- `apps/web/src/hooks/useProductos.ts` (ajuste mínimo autorizado, en la frontera de persistencia):
  - Al sanear/leer localStorage v2, también valida la combinación categoría ↔ unidad con `validar_combinacion_categoria_unidad`; un producto con combinación inválida **no** se incorpora al estado válido de la app.
  - Semántica previa sin cambiar: como ya ocurría con cualquier campo inválido, un elemento inválido **rechaza todo el payload** y el hook arranca desde los mocks canónicos. No se corrige categoría, no se cambia unidad, no se multiplica/divide stock y no se reinterpretan cantidades. No se inventó ninguna estrategia de recuperación nueva.
- `apps/web/src/pages/Productos.tsx`:
  - **Alta:** al cambiar la categoría, `unidadMedida` se deriva automáticamente (`unidad_para_categoria`); no queda ningún estado intermedio inválido.
  - **Selector de unidad:** ahora presenta la unidad derivada de la categoría como **valor no editable** (única opción, siempre deshabilitado). Ya no se elige unidad manualmente ni se ofrecen opciones incompatibles; no se agregaron opciones nuevas.
  - **Validación defensiva antes de guardar:** se revalida la combinación aunque la UI la restrinja; una combinación inválida falla cerrado con alerta visible y **no se persiste**.
  - **Edición:** la categoría ya no es editable durante la edición (además de la unidad, que tampoco lo era), con explicación visible de que cambiarlas alteraría la interpretación de las cantidades existentes. El guardado de edición actualiza solo `nombre`, `precio` y `stockMinimo`; **no** se toca `categoria`, **no** se convierte o multiplica stock, **no** se reinterpreta unidad ↔ medias piezas.
  - Cantidades: `stock` y `stockMinimo` siguen exigiéndose enteros ≥ 0 (en Fiambres ya representan medias piezas canónicas). No se agregó UX "pieza + media pieza".
- `apps/web/src/domain/productos.test.ts` (nuevo, 8 pruebas; creado originalmente como `apps/web/src/pages/productos_validacion.test.ts` y movido a `domain/`): `unidad_para_categoria` por categoría; combinaciones válidas (Lácteos+unidad, Fiambres+pieza) e inválidas (Lácteos+pieza, Fiambres+unidad); `kg` no es unidad aceptada.
- `apps/web/src/hooks/persistencia-v2.test.ts` (+4 pruebas de frontera de persistencia): `Lácteos + pieza` y `Fiambres + unidad` en v2 **no** se aceptan (el payload íntegro se rechaza y se vuelve a los mocks canónicos); `Lácteos + unidad` y `Fiambres + pieza` siguen aceptándose.
- `docs/progress-log.md`: esta entrada.

### Limitación de testing

No existe infraestructura de component testing (Vitest corre en node, sin jsdom/@testing-library) y no `se agregaron dependencias`. Por eso los tests cubren la lógica pura (`productos_validacion.ts`); la derivación en el handler de categoría y el bloqueo en la UI se verifican por typecheck + revisión manual del flujo del formulario (mismo enfoque que los bloques anteriores del prototipo).

### Cómo se verificó

| Verificación | Resultado |
|--------------|-----------|
| `npm test -- --run` | exit 0; 8 archivos, 89 pruebas (77 previas + 8 de dominio + 4 de frontera de persistencia) |
| `npm run typecheck` | exit 0 |
| `npm run lint` | exit 0; 0 errores, 0 advertencias |
| `npm run build` | exit 0 (`index-D4-8Jzna.js`) |
| `npx playwright test` | exit 0; 1 prueba pasa |
| `git diff --check` | sin espacios en blanco problemáticos |

### Riesgos y pendientes

1. **Cerrada la defensa en la frontera de persistencia:** `useProductos.ts` también valida la combinación categoría ↔ unidad al leer localStorage v2, con la semántica previa intacta (elemento inválido invalida todo el payload → mocks canónicos). No se corrigen datos ni se reinterpreta stock.
2. **Jornadas:** queda pendiente implementar la UX de pieza/media pieza.
3. **Autoventa:** queda pendiente implementar la UX de pieza/media pieza.
4. **Movimientos:** queda pendiente implementar la UX de pieza/media pieza.
5. **Retornos:** queda pendiente implementar la UX de pieza/media pieza.
6. **Rendición:** queda pendiente retirar el bloqueo `pieza_legacy` cuando toda la cadena use la representación canónica en medias piezas.
7. **`v1` preservada:** las claves `*_demo_v1` siguen intactas y no son leídas por v2.
8. **ADR-001** continúa **PROPUESTA — NO APROBADA**; esta tarea no la toca.
9. *(Estado al redactar la entrada; ver «Estado posterior».)* Pendiente de auditoría independiente y aprobación humana antes de commit, push, merge y deploy.

Por estos pendientes, el Bloque 2 es una **implementación parcial** y **no completa la migración de unidades del prototipo**.

### Estado posterior (actualizado el 20/10/2026)

| Dato | Valor |
|---|---|
| Commit | `86e58b36d252b5c1b8e31d5bd7d3e9910f94186a` (`feat: validar unidades por categoria en productos`) |
| Parent | `91078a5331db54684f2d83be4d32067e7dea7d69` |
| Auditoría independiente | **APPROVED** sobre ese hash (dato informado por el usuario; el informe de la auditoría no está versionado en el repositorio) |
| Findings | Ninguno (sin hallazgos H/M/L) |
| Verificación asociada | Vitest 89/89 · typecheck OK · lint OK · build OK · Playwright 1/1 |
| Push | **No realizado.** La rama no existe en `origin` |
| Merge / deploy | **No realizados** |
| Aprobación humana final | Pendiente |

Nota: `lint` (exit 0) y Vitest (89/89) fueron re-ejecutados el 20/10/2026 sobre este hash durante la auditoría integral del proceso; typecheck, build y Playwright se toman de la verificación asociada informada arriba.

---

## 19/10/2026 — Bloques 1 + 1B: base demo canónica y eliminación técnica de `kg`

**Rama:** `refactor/migrar-unidades-prototipo` · **Base:** `187a8d38c76746f4686f3a41647d3eb3292edd36` · **Agente:** OpenCode · **Estado:** bloque intermedio 1 + 1B; **la migración del prototipo todavía no está completa**; **en ese momento aún sin commit; luego consolidado en el commit `91078a5331db54684f2d83be4d32067e7dea7d69`**; **sin push**; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Qué se hizo (Bloque 1 — TIPOS + MOCKS + LOCALSTORAGE V2)

**Tipo canónico (`UnidadMedida`):**
- `apps/web/src/data/mockProductos.ts:1`: `UnidadMedida = "unidad" | "pieza"` (se eliminó `"kg"`).
- Los tipos duplicados inline en `mockJornadas.ts:10`, `mockVentas.ts:10` y `mockRetornos.ts:5` ahora usan `"unidad" | "pieza"`.
- `mockMovimientos.ts` reusa `UnidadMedida` desde `mockProductos` (se actualiza automáticamente).

**Mock productos (`mockProductos.ts`):**
- Separado `Queso cremoso` (inválido: Lácteos + pieza) en dos productos por decisión humana:
  - `Queso cremoso en bote` → Lácteos / `unidad`, stock 20 (entero).
  - `Queso cremoso en pieza` → Fiambres / `pieza`, stock 36 (18 piezas × 2 medias).
- `Jamón cocido`: Fiambres / `pieza`, stock 36 (era 18 piezas enteras → ahora 36 medias piezas).
- `Salame milán`: Fiambres / `pieza`, stock 12 (era 6 piezas enteras → ahora 12 medias piezas).
- `stockMinimo` de fiambres expresado en medias piezas.
- Sin `"kg"` en ningún producto demo.

**localStorage v2 (claves `_demo_v1` → `_demo_v2`):**
- `useProductos.ts`, `useJornadas.ts`, `useVentas.ts`, `useMovimientos.ts`, `useRetornos.ts`, `useCamiones.ts`, `useClientes.ts`, `useCobros.ts`: STORAGE_KEY actualizada a `*_demo_v2`.
- `ConfiguracionDemo.tsx:16-20`: CLAVES_OPERACIONES actualizadas a `*_demo_v2`.
- Todas las validaciones de `["unidad", "pieza", "kg"]` cambiadas a `["unidad", "pieza"]`.
- Ramas de `=== "kg"` eliminadas de `useJornadas.ts` y `useRetornos.ts` (incluida `esCantidadValida` simplificada).
- Funciones de carga exportadas (`cargarProductos`, `cargarVentas`, `cargarCamiones`, `cargarClientes`) para permitir tests de inicialización.
- Las claves `*_demo_v1` **no se borran ni se reinterpretan**: v2 arranca desde mocks canónicos; si v2 ya existe, se respeta.

### Tests agregados

- `apps/web/src/data/mockProductos.test.ts`: verifica que ningún producto usa `kg`; Lácteos→unidad, Fiambres→pieza; stocks enteros >= 0; fiambres en medias piezas (casos concretos: 18→36, 6→12).
- `apps/web/src/hooks/persistencia-v2.test.ts`: verifica inicialización v2 sin datos v2 (mocks canónicos); v1 no se migra (dato v1 con `kg` no contamina v2); v1 no se elimina; v2 existente se respeta.

### Qué se hizo (Bloque 1B — eliminación técnica de `kg`)

- `Productos.tsx`, `Jornadas.tsx`, `Autoventa.tsx`, `Movimientos.tsx` y `Retornos.tsx`: se eliminaron las ramas, etiquetas, validaciones y formatos específicos de `kg` que habían quedado incompatibles con el tipo canónico.
- `rendicion_calculos.test.ts`: el fixture que caracteriza una unidad legacy no soportada usa un valor fuera del tipo canónico sin reintroducir `kg` en `UnidadMedida`.
- Este bloque sólo cierra la eliminación técnica necesaria para que la base canónica compile. No incorpora todavía la UX funcional de pieza/media pieza ni declara terminada la migración.

### Cómo se verificó

| Verificación | Resultado |
|--------------|-----------|
| `npm test -- --run` | exit 0; 7 archivos, 77 pruebas pasan |
| `npm run lint` | exit 0; 0 errores, 0 advertencias |
| `npm run typecheck` | exit 0 |
| `npm run build` | exit 0 |
| `npx playwright test` | exit 0; 1 prueba pasa |
| `git diff --check` | exit 0 (sin problemas de whitespace) |
| Alcance | revisado mediante `git diff --stat`, `git diff --name-status` y `git status --short` |

### Riesgos y pendientes

1. **Productos:** queda pendiente implementar la validación categoría ↔ unidad.
2. **Jornadas:** queda pendiente implementar la UX de pieza/media pieza.
3. **Autoventa:** queda pendiente implementar la UX de pieza/media pieza.
4. **Movimientos:** queda pendiente implementar la UX de pieza/media pieza.
5. **Retornos:** queda pendiente implementar la UX de pieza/media pieza.
6. **Rendición:** queda pendiente eliminar el bloqueo `pieza_legacy` una vez que el flujo use la representación canónica en medias piezas.
7. **`v1` preservada:** las claves `*_demo_v1` siguen intactas y no son leídas por v2.
8. **ADR-001** continúa **PROPUESTA — NO APROBADA**; esta tarea no la toca.

Por estos pendientes, los Bloques 1 + 1B son un **bloque intermedio** y **no completan la migración de unidades del prototipo**.

---

**Rama:** `refactor/migrar-unidades-prototipo` · **Agente:** OpenCode · **Estado:** documentación actualizada; **en ese momento aún sin commit; luego consolidada en la rama (commit `187a8d3`, `docs: definir migracion canonica de unidades`, junto con la definición del 18/10)**; **sin push**; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Decisiones humanas aprobadas

1. **Producto demo `Queso cremoso`:** separarlo en dos productos coherentes con la categoría. `Queso cremoso en bote` (untable) → **Lácteos** / `unidad` (entero); `Queso cremoso en pieza` → **Fiambres** / `pieza` (entero en medias piezas). **No** se mantiene la combinación `Lácteos` + `pieza`. Es un ejemplo de consistencia categoría/unidad; **no** una regla sobre nombres de producto.
2. **`localStorage` demo:** versionar las claves demo de **v1 → v2** y **reinicializar** los datos demo. **Sin migración automática** de cantidades v1 → v2, porque los valores legacy de `pieza` están en piezas enteras y reutilizar el mismo número lo reinterpretaría como medias piezas (legacy `18` = 18 piezas; v2 `18` = 9 piezas). v1 no se reinterpreta ni se elimina en esta tarea.

### Qué se hizo (solo documentación)

- `BLUEPRINT.md` → **v1.6**: §7.1 agrega el **ejemplo de consistencia categoría/unidad** (`Queso cremoso en bote` → Lácteos/`unidad`; `Queso cremoso en pieza` → Fiambres/`pieza`); fila de historial 1.6.
- `docs/PRD.md` → historial **0.5**: ejemplo en §9; §13 registra que el versionado `v1 → v2` (sin migración automática) es **decisión humana aprobada**; referencias a `BLUEPRINT.md` v1.6.
- `docs/requirements/migracion-unidades-prototipo.md`: nueva §4-bis (productos demo de referencia); §7-bis pasa de «DECISIÓN PENDIENTE» a **DECISIÓN HUMANA APROBADA** con estrategia (claves v2, inicialización limpia, datos normalizados, sin migración desde v1, v1 intacto); criterios de aceptación ampliados (sin `Lácteos`+`pieza`, sin `Fiambres`+`unidad`, sin `kg`, fiambres en medias piezas, `localStorage` v2 coherente, ningún valor v1 reutilizado); tests y bloqueos actualizados.
- `docs/progress-log.md`: esta entrada.

### Cómo se verificó

Cambio **exclusivamente documental**; no se modificó código. `git diff --check` sin espacios problemáticos; `git status --short` muestra solo los documentos previstos.

### Riesgos y pendientes

1. **Implementación pendiente de autorización**: la migración del prototipo no está autorizada; requiere el plan humano correspondiente.
2. **v1 no se borra**: el borrado de las claves `_demo_v1` es una decisión separada, no incluida aquí.
3. **ADR-001** sigue **PROPUESTA — NO APROBADA** y **P1–P20** siguen pendientes; esta tarea no los toca.

---

## 18/10/2026 — Definición documental de unidades (lácteos por unidad entera; fiambres por pieza/media; sin `kg`) y requisito de migración del prototipo

**Rama:** `refactor/migrar-unidades-prototipo` (base `3c0c005c785e8b163493f46b74f0938774d1b7a4`) · **Agente:** OpenCode · **Estado:** definición documental; **en ese momento aún sin commit; luego consolidada en el commit `187a8d3` (`docs: definir migracion canonica de unidades`)**; **sin push**; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Contexto

Decisión humana confirmada: los **lácteos** se venden y controlan por **cantidad/unidad entera**; los **fiambres**, **únicamente por pieza o media pieza**, con representación canónica **entera en medias piezas** (1 pieza = 2 medias piezas; 1/2 pieza = 1 media pieza); **no existe `kg` en Fase 1**. El prototipo legacy todavía contiene `kg` y piezas expresadas como piezas enteras, y requiere migración. Tarea **solo documental**: preparar el requisito antes de modificar código.

### Qué se hizo

- `BLUEPRINT.md` → **v1.5** (fecha 18/10/2026): §2 y §7.1 aclarados con la decisión; se indica que el prototipo legacy usa `kg`/piezas enteras y requiere migración; fila de historial 1.5. Sin cambios en propuestas no aprobadas.
- `docs/PRD.md` → historial **0.4**: referencia a `BLUEPRINT.md` v1.5; la regla queda como **requisito aprobado** en RF-01 y §9; nota del prototipo legacy en §13. No se crea un segundo PRD.
- `docs/requirements/migracion-unidades-prototipo.md` (**nuevo**): objetivo, estado actual, estado objetivo, matriz de unidades, eliminación de `kg`, archivos afectados, riesgo de reinterpretar datos de `localStorage`, propuesta de versionar claves demo `v1 → v2` (**decisión técnica pendiente de aprobación humana, no implementada**), criterio de aceptación, tests requeridos y fuera de alcance (Supabase, SQL, RLS, RPC, ADR-001).
- `docs/progress-log.md`: esta entrada.

### Cómo se verificó

Cambio **exclusivamente documental**; no se modificó código. `git diff --check` sin espacios problemáticos; `git status --short` muestra solo los documentos previstos. No se ejecutaron pruebas de aplicación porque no hubo cambios de código.

### Riesgos pendientes

1. **Implementación pendiente**: la migración del prototipo no está autorizada; requiere plan humano y su propio ciclo de verificación.
2. **`localStorage` v1 → v2**: propuesta técnica **pendiente de aprobación humana**; mientras tanto, riesgo de reinterpretar datos demo si se cambia la semántica sin migrar (documentado en §7 del requisito).
3. **Dato demo inconsistente**: `Queso cremoso` figura como `Lácteos` con `unidadMedida: "pieza"`; debe alinearse a `unidad` al migrar.
4. **ADR-001** sigue **PROPUESTA — NO APROBADA** y **P1–P20** siguen pendientes; esta tarea no los toca.

---

## 17/10/2026 — Integrar el dominio de rendición en `Rendicion.tsx` (ejecución estricta) y quitar `kg` de esa pantalla

**Rama:** `refactor/integrar-dominio-rendicion` (base `edbbef5`) · **Agente:** OpenCode · **Estado:** implementado con TDD (RED → GREEN) y verificado en local; commiteado en `48d2f0bd21a72802abf945a85920f7519e1b2a36` (commit principal) y `6e8aa795ae134ee6156d42664f603437fe0db4b1` (commit correctivo); **sin push y sin merge**; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Contexto

Tarea autorizada: integrar en la pantalla `Rendicion` el dominio aprobado de cantidades/rendición (`calcular_esperado`, `calcular_diferencia`, `es_cantidad_valida`) y eliminar de **esa** pantalla el soporte legacy de `kg`. Fuente: `BLUEPRINT.md` §2 y §7.1 (unidad / pieza / media pieza; nunca kilogramo), §7.4 y §12.

Ajustes de la **decisión humana** sobre la primera iteración: (1) tratar `pieza` con criterio estricto (no conciliable) y (2) eliminar la supresión de `react-refresh` moviendo la lógica pura fuera del componente.

**Trazabilidad de esa primera iteración (aclaración de auditoría).** Esa «primera iteración» existió **solo en el espacio de trabajo local y nunca se commiteó**. Incluía un `apps/web/src/pages/Rendicion.test.ts` temporal y una supresión de `react-refresh` en `Rendicion.tsx`. Ambos se descartaron **antes** del commit `48d2f0b`. Por eso, el diff de `48d2f0b` (parent `edbbef5`) **no elimina ningún archivo** ni **remueve una supresión preexistente del parent**: `Rendicion.test.ts` no figura en ningún commit del historial y `edbbef5:apps/web/src/pages/Rendicion.tsx` no tenía ninguna supresión de lint. No se reescribe historia ni se borra evidencia: esta aclaración solo deja la trazabilidad explícita.

### Hallazgo determinante: cómo representa HOY el prototipo la unidad `pieza`

**`pieza` todavía está representada en PIEZAS ENTERAS, no en medias piezas.** Verificado en el código, no inferido:

- `apps/web/src/data/mockJornadas.ts` (`ItemCarga.unidadMedida`, `cantidad`), `mockVentas.ts` (`DetalleVenta.cantidad`) y `mockMovimientos.ts` (`ProductoMovimiento.cantidad`): las cantidades son `number` sin conversión; demo con `Queso cremoso` = 35 piezas, `Jamón cocido` = 18, `Salame milán` = 6.
- `apps/web/src/pages/Jornadas.tsx` (líneas 174-175 y 377-380), `Autoventa.tsx` (238-241), `Movimientos.tsx` (171-173) y `Retornos.tsx` (37-42): para `pieza` exigen entero (`Number.isInteger`) y `step="1"`; **no admiten `0.5`**. Solo `kg` admitía 3 decimales.
- `Rendicion.tsx` (previo): su `cantidadValida` también exigía entero para `pieza`; **nunca aceptó medias piezas**.

### Decisión humana (estricta)

La representación legacy de `pieza` (piezas enteras) **no se considera conciliable** contra el dominio, que exige medias piezas como unidad mínima. Por eso, para `unidadMedida === "pieza"`:

- la fila se marca **`pieza_legacy`** (no conciliable);
- **no** se llama a `calcular_esperado` ni a `calcular_diferencia`;
- **no** se convierte piezas a medias piezas (nada silencioso);
- se **bloquean** «Completar con esperados» y «Confirmar cierre»;
- se muestra el aviso: *"Los productos por pieza todavía usan la representación legacy. Deben migrarse a medias piezas antes de poder cerrar la rendición."*

**No se modificaron datos ni se migró `localStorage`.** El cierre de una jornada con productos por `pieza` queda bloqueado hasta la migración a medias piezas (fuera de esta tarea). Para `unidad` se usa el dominio aprobado; el kilogramo sigue tratado como no soportado en `Rendicion` (sin reintroducir su lógica).

### Cambios

- `apps/web/src/pages/rendicion_calculos.ts` (**nuevo**, módulo puro, sin React):
  - `calcularFilaMercaderia` + tipos `EntradaFilaMercaderia` / `FilaMercaderia` / `EstadoFilaMercaderia`; `bloqueaRendicion(filas)`; `conteoValido(texto)`; `leerCantidad(texto)`; constante `MENSAJE_PIEZA_LEGACY`.
  - `unidad`: dominio canónico (entero ≥ 0); `salidas > cargado` ⇒ `inconsistente` sin lanzar hacia React.
  - `pieza`: `pieza_legacy`, sin dominio, sin esperado ni diferencia.
  - kilogramo u otra unidad: `no_soportada`, sin dominio ni camino funcional.
- `apps/web/src/pages/Rendicion.tsx`:
  - Importa el módulo puro; **no exporta helpers puros** (la lógica pura vive en `rendicion_calculos.ts`) y **no hay ninguna supresión de lint**.
  - Eliminado el soporte de `kg` (mapa de unidades, validación especial `cantidadValida`, `step` decimal).
  - Eliminados los redondeos decimales de mercadería (`redondear`). **No se tocó el redondeo de dinero ni la lógica de caja.**
  - Bloqueo de «Completar con esperados» y del cierre ante filas `inconsistente`, `pieza_legacy` o `no_soportada`, con avisos específicos.
- `apps/web/src/pages/rendicion_calculos.test.ts` (**nuevo**). El `Rendicion.test.ts` temporal perteneció **solo** a la primera iteración local no commiteada y se descartó antes de este commit (ver «Trazabilidad» en Contexto); el diff de `48d2f0b` **no elimina ningún archivo**.
- `docs/progress-log.md`: esta entrada.

### Tests obligatorios cubiertos (16 pruebas nuevas)

- **unidad**: esperado correcto; sin diferencia; faltante; sobrante; conteo decimal inválido; `salidas > cargado` ⇒ inconsistencia sin excepción hacia React.
- **pieza legacy**: fila `pieza_legacy`; sin esperado canónico; sin diferencia canónica; bloquea el cierre (sola y junto a una fila válida); mensaje que exige migración a medias piezas.
- **kg legacy**: `no_soportada`; no usa el dominio canónico; bloquea el cierre.
- **`bloqueaRendicion`**: no bloquea filas conciliables; bloquea ante cualquier fila no conciliable.

### Fuera de alcance (no se tocó)

Limpiar `kg` de Autoventa/Jornadas/Movimientos/Retornos/Productos; el tipo compartido `UnidadMedida = "unidad" | "pieza" | "kg"` (`apps/web/src/data/mockProductos.ts`), usado por muchas pantallas; modelos mock; hooks; migrar datos demo; `localStorage`; Supabase; SQL; migraciones; RLS; RPC; ADR-001.

### Verificación (desde `apps/web/`)

| Verificación | Resultado |
|---|---|
| `npm test -- --run` | exit 0; `Test Files 5 passed (5)`; `Tests 55 passed (55)` (39 previos + 16 nuevos) |
| `npm run typecheck` | exit 0 |
| `npm run lint` | exit 0 (**sin ninguna supresión**; no quedan `eslint-disable`) |
| `npm run build` | exit 0 (`index-GW6Mg1y8.js`) |
| `npx playwright test` | exit 0; `1 passed` |
| raíz: `git diff --check` | exit 0 (sin espacios en blanco problemáticos) |

### Corrección posterior a la auditoría (`fix: precisar bloqueo de rendicion`)

Segundo commit de la misma rama, `6e8aa795ae134ee6156d42664f603437fe0db4b1` (`fix: precisar bloqueo de rendicion`), posterior a la auditoría independiente de `48d2f0bd21a72802abf945a85920f7519e1b2a36`. Atiende dos hallazgos no bloqueantes (L1 y L2) y **no cambia ninguna lógica**:

- **L1 (documentación):** se aclaró la trazabilidad de la primera iteración local **no commiteada** (`Rendicion.test.ts` temporal y supresión de `react-refresh`) y se explicitó que el diff de `48d2f0b` **no elimina archivos** ni **remueve supresiones preexistentes del parent**.
- **L2 (texto de UI):** el aviso visible y el error de «Confirmar cierre» ya no dicen solo "stock esperado negativo"; ahora describen las dos causas reales del estado `inconsistente` (salidas > cargado y cantidades inválidas/no canónicas). Mismo estado interno `stockInconsistente` y mismo bloqueo.

Sin cambios en `rendicion_calculos.ts`, dominio, hooks, `localStorage`, SQL, migraciones, RLS, RPC ni dinero. Sin tests nuevos: el proyecto no tiene infraestructura de tests de componentes (no hay `@testing-library`/jsdom) y ningún test afirmaba el texto anterior.

### Riesgos y deuda pendiente

1. **`pieza` no está integrada al dominio canónico**: sigue en piezas enteras y **su cierre está bloqueado** en `Rendicion` hasta una migración de representación a medias piezas (fuera de esta tarea). No se migraron datos.
2. **`UnidadMedida` sigue incluyendo `"kg"`** (`mockProductos.ts`), compartido por muchas pantallas; eliminarlo del tipo y limpiar `kg` del resto del prototipo es una tarea aparte (en `Rendicion` ya no existe camino de `kg`).
3. **Estado de integración pendiente**: la tarea quedó commiteada en esta rama —commit principal `48d2f0bd21a72802abf945a85920f7519e1b2a36` (`refactor: integrar dominio en rendicion`) y commit correctivo `6e8aa795ae134ee6156d42664f603437fe0db4b1` (`fix: precisar bloqueo de rendicion`)—. Esta corrección documental (solo `docs/progress-log.md`) produce un **hash nuevo, todavía sin calcular**. Quedan pendientes: la **auditoría del nuevo hash** resultante de esta corrección documental, la **aprobación humana**, el **push** y el **merge**. No hubo push ni merge.

---

## 17/10/2026 — Corrección M1: `piezas_a_medias` admite medias piezas exactas

**Rama:** `feat/dominio-cantidades-rendicion` (base `1001fadc4809bd4b63510dd3604603767760130c`) · **Agente:** OpenCode · **Estado:** corrección de auditoría implementada y verificada en local; **sin push y sin merge**; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Contexto

La auditoría de solo lectura del commit `f14c4c97337c2278df7efb8ca5e25845e96e75b1` resultó **APPROVED WITH CORRECTIONS**, con un único hallazgo que afecta el contrato: **M1 — `piezas_a_medias` rechazaba `0.5`** lanzando `Error`, en vez de devolver `1` media pieza (caso "1/2 pieza = 1 media pieza").

### Decisión humana

`piezas_a_medias` debe aceptar cantidades en **múltiplos exactos de 0.5**:

```
0 -> 0   0.5 -> 1   1 -> 2   1.5 -> 3   2 -> 4   4.5 -> 9
```

Debe rechazar negativos, valores que no sean múltiplos de 0.5 (`0.25`, `0.75`, `1.25`), `NaN`, `Infinity` y `-Infinity`. La salida de `piezas_a_medias` sigue siendo siempre una cantidad canónica entera en medias piezas.

### Cambios

- `apps/web/src/domain/cantidades.ts`: `piezas_a_medias` valida localmente (finito, `>= 0` y `piezas * MEDIAS_POR_PIEZA` entero) en lugar de reutilizar `validar_cantidad`, que representa una cantidad canónica y por eso no admite `0.5`. `medias_a_piezas`, `es_cantidad_valida` y `validar_cantidad` no cambian.
- `apps/web/src/domain/cantidades.test.ts`: se agrega "admite medias piezas exactas (múltiplos de 0.5)" y se corrigen los casos negativos de `piezas_a_medias`: el rechazo erróneo de `1.5` se reemplaza por `-0.5`, `0.25`, `0.75` y `1.25`. Los tests de `medias_a_piezas` y de `rendicion` no se tocan.
- Sin cambios en `rendicion.ts`, `rendicion.test.ts`, pantallas, Supabase, migraciones, RLS ni RPC.

### Fuera de esta corrección

Los hallazgos **L1** (`snake_case` vs `AGENTS.md` §7), **L2** (`validar_cantidad` no nombra el campo que falló) y **L3** (duplicación con los validadores locales de las pantallas) quedan **no bloqueantes** y fuera de esta corrección; siguen como riesgos pendientes de la entrada anterior.

### Verificación (desde `apps/web/`)

| Verificación | Resultado |
|---|---|
| `npm test -- --run` | exit 0; `Test Files 4 passed (4)`; `Tests 39 passed (39)` (34 de dominio + 5 preexistentes) |
| `npm run typecheck` | exit 0 |
| `npm run lint` | exit 0 |
| `npm run build` | exit 0; `dist/assets/index-BKH7CK6R.js 394.04 kB │ gzip: 110.55 kB` |
| `git diff --check` | exit 0 |

### Reauditoría

Esta corrección genera un **commit nuevo** (no `amend` del anterior). **Todo hash nuevo requiere reauditoría independiente completa** (AGENTS.md §2.3.4): la auditoría de `f14c4c9` no se reutiliza para el nuevo commit.

---

## 17/10/2026 — Dominio puro de cantidades (unidad mínima) y cálculo básico de rendición

**Rama:** `feat/dominio-cantidades-rendicion` (base `1001fadc4809bd4b63510dd3604603767760130c`) · **Agente:** OpenCode · **Estado:** implementado con TDD (RED → GREEN) y verificado en local; **sin push y sin merge**, pendiente de auditoría independiente sobre su propio hash; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Objetivo

Extraer lógica de dominio pura para cantidades en unidad mínima y cálculo básico de rendición, con los tests escritos antes que la implementación (TDD), sin integrarla todavía a ninguna pantalla.

### Blueprint aplicable

- §3: el stock no se edita a mano; simple antes que completo; nada se da por terminado sin prueba.
- §7.1: cantidades enteras en la unidad mínima; 1 pieza = 2 medias piezas.
- §7.4: no permitir inconsistencias de stock silenciosas.
- §7.5: rendición / jornada.
- §12: pruebas.

### Implementación

`apps/web/src/domain/cantidades.ts`
- `MEDIAS_POR_PIEZA = 2`
- `piezas_a_medias`
- `medias_a_piezas`
- `es_cantidad_valida`
- `validar_cantidad`

`apps/web/src/domain/rendicion.ts`
- `EntradaEsperado`
- `calcular_esperado`
- `calcular_diferencia`

### Contrato

```
1 pieza   = 2 medias piezas
1/2 pieza = 1 media pieza
```

La cantidad canónica/almacenable es siempre un entero `>= 0` expresado en unidad mínima.

`medias_a_piezas` es solo una conversión de representación y puede devolver fracciones: `1 -> 0.5`, `9 -> 4.5`. Su salida no es una cantidad almacenable.

```
esperado   = cargado - vendido - merma - otras_salidas
diferencia = contado - esperado
```

Si `vendido + merma + otras_salidas > cargado`, `calcular_esperado` lanza `Error` y no devuelve un negativo silencioso: representa una inconsistencia que debe regularizarse de forma trazable (§7.4).

La diferencia sí puede ser negativa: `< 0` faltante, `0` sin diferencia, `> 0` sobrante. No se agregó enum ni clasificación explícita porque no es necesario para esta tarea: el signo alcanza.

### TDD

**Fase RED (observada antes de implementar):**

- Primera iteración: faltaban los módulos `apps/web/src/domain/cantidades.ts` y `rendicion.ts`; las dos suites fallaban con `Cannot find module './cantidades'` y `Cannot find module './rendicion'` (0 tests ejecutados).
- Segunda iteración, al cambiar `medias_a_piezas` para que conserve la cantidad exacta: los tests nuevos fallaron antes de corregir la implementación (`AssertionError: expected +0 to be 0.5` y `AssertionError: expected true to be false`).

**Fase GREEN final** (resultados exactos, desde `apps/web/`):

| Verificación | Resultado |
|---|---|
| `npm test -- --run` | exit 0; `Test Files 4 passed (4)`; `Tests 37 passed (37)` (32 de dominio + 5 preexistentes) |
| `npm run typecheck` | exit 0 |
| `npm run lint` | exit 0 |
| `npm run build` | exit 0; `dist/assets/index-BKH7CK6R.js 394.04 kB │ gzip: 110.55 kB` |
| `git diff --check` | exit 0; sin problemas de whitespace |

Evidencia adicional: se comprobó por mutación que los tests detectan errores reales (quitar el guard de §7.4 en `calcular_esperado` → falla 1 prueba; `Math.floor` → `Math.round` en `medias_a_piezas` → fallan 2 pruebas), restaurando la implementación con hash idéntico al original.

### Archivos

| Archivo | Cambio |
|---|---|
| `apps/web/src/domain/cantidades.ts` | nuevo; cantidades y unidad mínima |
| `apps/web/src/domain/cantidades.test.ts` | nuevo; 18 pruebas |
| `apps/web/src/domain/rendicion.ts` | nuevo; esperado y diferencia |
| `apps/web/src/domain/rendicion.test.ts` | nuevo; 14 pruebas |
| `docs/progress-log.md` | esta entrada |

### Fuera de alcance

- Integración con pantallas; `localStorage`; `movimientos_stock` reales; dinero; Supabase; migraciones; RLS; RPC; `SECURITY DEFINER` / `SECURITY INVOKER`; cualquier decisión P1–P20; cualquier PROPUESTA NO APROBADA.
- **ADR-001 continúa PROPUESTA — NO APROBADA.**
- **No existe persistencia ni seguridad de backend asociada a este dominio:** son funciones puras, sin efectos y sin escrituras. No se afirma que haya persistencia ni control de acceso.

### Riesgos pendientes

1. El dominio todavía no está integrado a pantallas ni a RPC, y no reemplaza la lógica demo existente (por ejemplo `cantidadValida` en `apps/web/src/pages/Rendicion.tsx`).
2. Los identificadores nuevos están en **snake_case** por instrucción explícita de la tarea; `AGENTS.md` §7 fija camelCase en TypeScript (snake_case queda para SQL, Blueprint §8). Divergencia registrada y sin decisión formal todavía.
3. `validar_cantidad(cantidad: number): void` no recibe el nombre del campo, así que el error no indica qué componente falló.
4. `medias_a_piezas` devuelve fracciones: su salida nunca debe usarse como cantidad almacenable ni pasarse a `calcular_esperado` / `calcular_diferencia`.
5. No se registra el hash del commit en esta entrada: el documento forma parte de ese mismo commit, así que el hash se reporta al cerrar la tarea y es el que debe auditarse.
6. `npm run lint` pasa con 0 errores, mientras el incidente `docs/incidents/2026-10-12-lint-falla-en-main.md` registra 10 errores en `main`. No se reprodujo en esta base porque incluye la corrección de lint ya integrada (`chore/corregir-lint`); el incidente no se tocó (fuera de alcance).

---

## 17/10/2026 — Integración de la corrección de lint con la línea documental, tooling y proceso de agentes

**Rama:** `chore/integrar-base-desarrollo` · **Agente:** OpenCode · **Estado:** conflicto resuelto; merge pendiente de commit y auditoría; **ADR-001 continúa PROPUESTA — NO APROBADA**

### Objetivo

Integrar la rama de corrección de lint (`chore/corregir-lint`) con la línea documental, de tooling de calidad y de proceso de agentes (`chore/formalizar-proceso-agentes`).

### Qué se hizo

- Origen: `chore/corregir-lint@28952871793363744d047fa28294c59b586f6e94` y `chore/formalizar-proceso-agentes@d80a09f1fdec220b01eabe92bbcc29317b6cf521`.
- Único conflicto: `docs/progress-log.md`.
- Resolución: unión semántica de ambas bitácoras, sin descartar historial.

### Cómo se verificó

Verificación ya ejecutada durante el merge:

| Verificación | Resultado |
|---|---|
| `npm run lint` | OK |
| `npm run typecheck` | OK |
| Vitest | 5/5 |
| `npm run build` | OK |
| `npx playwright test` | 1/1 |

### Riesgos pendientes

1. La resolución del conflicto está **preparada**; el merge queda **pendiente de commit y auditoría**. No se registra el hash del merge porque todavía no existe.
2. **ADR-001 continúa PROPUESTA — NO APROBADA.**
3. No se autorizan migraciones ni cambios de seguridad funcional.

---

## 17/10/2026 — Cierre del incidente de lint (`chore/corregir-lint`)

**Rama:** `chore/corregir-lint` (creada desde `4cdffb1c159cd17159ff2d0fe0180d391938d973`) · **Agente:** agente de implementación · **Estado:** incidente **resuelto localmente** en esta rama; la rama queda **pendiente de revisión independiente por Codex/OpenCode**; **no hay aprobación de merge a main** — el merge queda reservado a decisión humana posterior a esa revisión.

### Qué se hizo

- Se resolvieron exactamente los 10 errores y 1 advertencia de ESLint del incidente `docs/incidents/2026-10-12-lint-falla-en-main.md`, sin cambios de comportamiento de negocio, stock, dinero, roles ni flujos demo.
- `AuthContext.tsx`: separación estructural sin excepciones ESLint. `usuariosDemo` y tipos demo moved a `src/auth/usuariosDemo.ts`; contexto y tipo a `src/auth/AuthContextValue.ts`; hook `useAuth` a `src/auth/useAuth.ts`. `AuthContext.tsx` exporta solo `AuthProvider`. Los consumidores (`App.tsx`, `ProtectedRoute.tsx`, `AppLayout.tsx`, `Sidebar.tsx`, `Login.tsx`, `ConfiguracionDemo.tsx`) actualizan sus imports explícitamente. No hay re-exportaciones no-componente desde `AuthContext.tsx`.
- `Sidebar.tsx`: eliminado el effect que hacía `setMenuAbierto(false)` al cambiar de ruta (error `react-hooks/set-state-in-effect`). El cierre tras navegar ya lo proveen los handlers `onClick` existentes de cada `NavLink`, más botón X, backdrop y Escape. Sin efecto nuevo ni remount por key. Comportamiento desktop idéntico.
- `hooks/useMovimientos.ts`: `any` reemplazado por predicado `(p: unknown)` con narrowing justificado por la forma runtime de los productos demo (sin aserciones para silenciar el linter).
- Páginas `Autoventa.tsx`, `CuentasCorrientes.tsx`, `Movimientos.tsx`, `Retornos.tsx`: estabilización mínima de dependencias derivadas envolviendo los `.find()`/`.filter()` preexistentes en `useMemo` con sus deps reales. Mismos cálculos, filtros, jornada seleccionada y reglas de aprobación/retorno. En `Movimientos.tsx` la dep correcta de `disponibles` resultó ser `[jornada, salidas]` (agregar `movimientosJornada` fue marcado como innecesario porque `salidas` ya lo porta transitivamente); resultado numérico idéntico y advertencia `exhaustive-deps` resuelta.
- CI: verificado que lint, typecheck, tests y build pasaban localmente, se quitó `continue-on-error: true` del job `lint` de `.github/workflows/ci.yml`; el lint de CI es ahora bloqueante.
- El incidente fue marcado como **cerrado** en su documento, con evidencia de verificación.

### Archivos afectados

| Archivo | Cambio |
|---|---|
| `apps/web/src/auth/usuariosDemo.ts` | nuevo; datos y tipos demo de autenticación |
| `apps/web/src/auth/AuthContextValue.ts` | nuevo; contexto y tipo |
| `apps/web/src/auth/useAuth.ts` | nuevo; hook de acceso al contexto |
| `apps/web/src/AuthContext.tsx` | modificado; exporta solo `AuthProvider` |
| `apps/web/src/App.tsx`, `components/ProtectedRoute.tsx`, `components/layout/AppLayout.tsx`, `components/layout/Sidebar.tsx`, `pages/Login.tsx`, `pages/ConfiguracionDemo.tsx` | modificados; imports actualizados |
| `apps/web/src/components/layout/Sidebar.tsx` | modificado; cierre de menú por handler, sin effect |
| `apps/web/src/hooks/useMovimientos.ts` | modificado; type guard en lugar de `any` |
| `apps/web/src/pages/Autoventa.tsx`, `CuentasCorrientes.tsx`, `Movimientos.tsx`, `Retornos.tsx` | modificados; estabilización de deps vía `useMemo` |
| `.github/workflows/ci.yml` | modificado; job `lint` bloqueante |
| `docs/incidents/2026-10-12-lint-falla-en-main.md` | modificado; estado cerrado con evidencia |
| `docs/progress-log.md` | esta entrada |

### Cómo se verificó y resultados exactos

- `npm run lint` → exit 0; 0 errores, 0 advertencias (baseline del incidente: 10 errores + 1 advertencia).
- `npm run typecheck` (`tsc -b`) → exit 0.
- `npm test` (Vitest) → exit 0; 2 archivos de prueba, 5/5 pruebas pasan.
- `npm run build` (`tsc -b && vite build`) → exit 0; bundle generado sin errores.
- `git diff --check` → sin problemas de whitespace.
- Playwright no se ejecutó: fuera del área afectada (los cambios son mecánicos de linting sobre componentes/páginas existentes sin nuevos flujos E2E); no se amplió el scope para instalar browsers.

### Riesgos conocidos

1. No hay tests E2E que cubran específicamente el flujo "cerrar menú móvil al navegar"; verificación fue estática + smoke de build/tests. Riesgo bajo porque los handlers `onClick` preexistentes ya hacían el cierre.
2. El hash del bundle cambia respecto del baseline (esperable al editar código).
3. El job `lint` bloqueante de CI no ha corrido aún en GitHub Actions; se ejercitará en el primer PR desde esta rama.
4. `aprobados` en `Retornos.tsx` sigue siendo objeto de estado mutado con spread; sus deps `[jornada, aprobados]` ahora son estables en la parte de `jornada` — semántica inalterada.

### Fuera de alcance confirmado

- ADR-001 permanece en estado `propuesta` y no fue tocada: sin migraciones, SQL, RLS, RPC, grants ni arquitectura de base de datos.
- Sin nuevas dependencias; sin refactor de archivos no relacionados; sin cambios en reglas de negocio, roles ni lógica de stock/dinero.

---

## 17/10/2026 — Formalización del proceso de agentes en `AGENTS.md` y `CLAUDE.md`

**Rama:** `chore/formalizar-proceso-agentes` (base `30b831650cf7108584052b13cc6c32b71a1b31b9`) · **Agente:** OpenCode · **Estado:** cambios preparados, pendientes de commit y auditoría; **ADR-001 sigue PROPUESTA — NO APROBADA**

### Objetivo

Formalizar en `AGENTS.md` y `CLAUDE.md` las convenciones operativas ya documentadas y auditadas en `docs/quality/` (ciclo de trabajo, reglas de auditoría, superficies de security review y tooling), **sin crear reglas funcionales nuevas**.

### Qué se hizo

- `AGENTS.md` §2 se amplía con el ciclo de trabajo, las reglas obligatorias del ciclo, las superficies que disparan security review y el tooling. Se conserva el flujo entre agentes y todas las reglas previas.
- `CLAUDE.md`: se explicita que Claude es implementador y no auditor final, se ordena el procedimiento (Blueprint/ADR antes de implementar, rama propia, alcance autorizado, lint/typecheck/tests/build, Playwright, auditoría independiente, no autoaprobar, no merge/deploy, nuevo hash tras corregir), y se agregan las advertencias de superficies sensibles y de no aprobar ADR-001 ni resolver P1–P20.
- `docs/quality/review-process.md`: corrección mínima en §3.7 para reflejar que el máximo de 3 ciclos y la security review obligatoria, nacidas como convenciones operativas, quedan además **formalizadas en `AGENTS.md`**; el documento sigue describiendo el proceso y no reemplaza `AGENTS.md`.
- `docs/progress-log.md`: esta entrada.

### Archivos

| Archivo | Cambio |
|---|---|
| `AGENTS.md` | §2 ampliada (ciclo, reglas del ciclo, superficies de security review y tooling) |
| `CLAUDE.md` | procedimiento, superficies sensibles y límites del implementador |
| `docs/quality/review-process.md` | §3.7: formalización de las dos convenciones operativas en `AGENTS.md` |
| `docs/progress-log.md` | esta entrada |

### Alcance: lo que esta tarea NO cambia

- No se modifica `BLUEPRINT.md` (sigue v1.4).
- **ADR-001 sigue PROPUESTA — NO APROBADA**; **P1–P20 siguen pendientes de aprobación humana**.
- No se aprueba ni se implementa ninguna propuesta pendiente.
- No se tocan ADR, `docs/PRD.md`, el resto de `docs/quality/**` (`security-review.md`, `browser-testing.md`), código, `package.json`/lockfiles, SQL, `supabase/migrations`, RLS, RPC, auth, grants ni workflows de CI.

### Cómo se verificó

- `git diff --check` (sin errores de whitespace), `git diff --stat` y `git status --short`: solo cambian las cuatro rutas autorizadas. No se ejecutaron typecheck, tests, Playwright ni build porque no hay cambios de código.

### Riesgos pendientes

1. Los cambios están **preparados y sin commitear**; el commit deberá auditarse sobre su propio hash antes de push y merge (`docs/quality/review-process.md` §3.3).
2. **No se registra hash nuevo** porque el commit todavía no existe.
3. **ADR-001 sigue PROPUESTA — NO APROBADA** y **P1–P20 siguen pendientes**.
4. Claude `/code-review` y `/security-review` siguen **pendientes/opcionales por disponibilidad actual**: se documentan como tales, no como herramientas obligatoriamente disponibles.

---

## 17/10/2026 — Tooling de calidad ya auditado y corrección documental del proceso de revisión

**Rama:** `chore/herramientas-calidad` · **Agente:** Claude Code · **Estado:** correcciones documentales **preparadas y pendientes de commit**; ADR-001 sigue **PROPUESTA — NO APROBADA**

### Herramientas de calidad incorporadas (commit ya auditado y aprobado)

Commit de tooling: `54f393490471a45214577d618034f3ea05a99518`

Resultado de la auditoría del tooling: **APPROVED**.

- Herramientas incorporadas: skill `grilling` y Playwright CLI `0.1.22`.
- Observaciones de la auditoría del tooling `54f3934…`, todas **no bloqueantes** (no confundir con los `L-1…L-7` de la auditoría final, que figuran más abajo):
  - **L-1:** preaprobación de comandos Playwright.
  - **L-2:** `run-code` puede ejecutar JavaScript en el contexto del navegador.
  - **L-3:** trazabilidad upstream/npm de `0.1.22` verificada, sin riesgo.

### Documentación creada y auditoría final

Commit documental: `9e589264fdd427ebe21d174d61b37c4c86e173cc`

- `docs/PRD.md`
- `docs/quality/review-process.md`
- `docs/quality/security-review.md`
- `docs/quality/browser-testing.md`

Commit de corrección documental: `bec986e695e27dec6f0c1892c21a45061ce624a9`

**Auditoría final de `bec986e…`: APPROVED WITH CORRECTIONS.** El conjunto documental no modificó `BLUEPRINT.md`, `AGENTS.md`, `CLAUDE.md`, ADR-001, código, SQL, migraciones, RLS, RPC, grants ni workflows.

### Qué se hizo en esta tarea

Corrección documental mínima en `docs/quality/review-process.md`, §2.1: «ADR vigente a la fecha» pasa a «Versión documental actual de ADR-001»; se conserva el resto de la oración (v1.2, ronda 3, estado `propuesta` — NO APROBADA, P1–P20 pendientes, P19 y P20 primero según la propuesta, y P18 como decisión separada que no es requisito previo). Se agrega esta entrada de bitácora.

**Correcciones de la auditoría final (preparadas, pendientes de commit).** El commit `bec986e695e27dec6f0c1892c21a45061ce624a9` fue auditado con veredicto **APPROVED WITH CORRECTIONS**. Sus hallazgos no bloqueantes **M-1, M-2 y L-1 a L-7 de la auditoría final** originan este commit documental de seguimiento:

| Hallazgo | Corrección aplicada |
|---|---|
| **M-1** | `browser-testing.md` §2: se documenta `npm run dev -- --host 127.0.0.1 --port 4173 --strictPort` para usar 4173, y se aclara que `npm run dev` a secas sirve el puerto de Vite (5173 por defecto), que 4173 proviene del `webServer` del E2E y que en ese caso hay que reemplazar la URL en todos los comandos. |
| **M-2** | `browser-testing.md` §7: la tabla deja de afirmar cobertura en CI. Dice «reproducible en cada corrida local» y que **hoy el CI no ejecuta Playwright**; se agrega nota: agregar Playwright al CI es una tarea separada y requiere autorización. |
| **L-1** | `review-process.md`: el máximo de 3 ciclos y la obligatoriedad de la security review quedan identificados como **convenciones operativas de este proceso, aprobadas por el humano en esta tarea**, no heredadas de `AGENTS.md`/Blueprint (§2.8, §3.4 y nueva regla §3.7). `AGENTS.md` no se modifica. |
| **L-2** | `PRD.md`: los identificadores tomados de Blueprint §8 (`movimientos_stock`, `auditoria`, `idempotency_key`, estados de nota) se marcan como **modelo de datos propuesto** con remisión a ADR-001 §3.2; no se presentan como DDL aprobado. |
| **L-3** | `PRD.md` §17: el criterio «el wrapper rechaza `anon`…» se conserva como criterio heredado del Blueprint, con nota de que depende de **P1**, no implica aprobación de la topología wrapper y no autoriza implementación ni migraciones. |
| **L-4** | `review-process.md` §2.7 y la cadena de §1: «code review (disponible)» pasa a «humana / independiente»; se aclara que `/code-review` de Claude está pendiente/opcional y que no existe una compuerta automática garantizada. |
| **L-5** | `browser-testing.md`: el ignore de `.playwright-cli/` se cita por su fuente directa (`.gitignore:57-58`); `AGENTS.md` §5 se menciona solo por el principio de no versionar secretos/estado sensible. |
| **L-6** | `PRD.md` RNF-11: cita corregida a `Blueprint §13, regla 4` + `AGENTS.md §6.4`, con la salvedad «aplicable cuando exista autorización de migraciones»; no insinúa que hoy corresponda migrar. |
| **L-7** | Esta entrada: registra el hash auditado `bec986e…`, el veredicto y el origen de las correcciones de seguimiento. |

Estas correcciones son **solo documentales**: no cambian reglas de negocio, no aprueban ADR-001 ni ninguna P1–P20 y no modifican el perfil de seguridad. No se registra el hash del commit de seguimiento porque **todavía no existe**.

### Alcance: lo que esta tarea NO autoriza

- no autoriza migraciones;
- no aprueba RLS;
- no aprueba RPC privilegiadas;
- no cambia grants;
- no cambia auth;
- no cambia reglas de stock ni de dinero;
- no modifica código de aplicación.

### Revisiones de Claude pendientes

- Claude `/code-review`: **pendiente/opcional** por falta de disponibilidad actual.
- Claude `/security-review`: **pendiente/opcional** por falta de disponibilidad actual.

### Archivos

| Archivo | Cambio |
|---|---|
| `docs/quality/review-process.md` | corrección de redacción en §2.1; §1, §2.7, §2.8, §3.4 y nueva §3.7 (convenciones operativas y code review sin ambigüedad) |
| `docs/quality/browser-testing.md` | §2 (procedimiento de puerto), §7 (cobertura en CI) y cita del ignore de `.playwright-cli/` |
| `docs/PRD.md` | RNF-11; marca de modelo de datos propuesto (§10, §14, §16); nota de dependencia P1 en §17; historial 0.3 |
| `docs/progress-log.md` | esta entrada |

Sin otros archivos modificados: no se tocaron `BLUEPRINT.md`, `AGENTS.md`, `CLAUDE.md`, ADR-001, `docs/quality/security-review.md`, código, SQL, migraciones, workflows, `package.json` ni lockfiles.

### Cómo se verificó

- `git diff --check` (sin errores de whitespace), `git diff --stat` y `git status --short`: solo cambian las rutas documentales autorizadas. No se ejecutaron typecheck, tests, Playwright ni build porque no hay cambios de código.

### Riesgos pendientes

1. Las correcciones de este seguimiento están **preparadas y sin commitear**; el nuevo commit deberá auditarse sobre su propio hash antes de push y merge (`review-process.md` §3.3).
2. **ADR-001 sigue PROPUESTA — NO APROBADA.** Esta tarea no cambia su estado.
3. **P1–P20 siguen pendientes de aprobación humana.**
4. **No se autoriza ningún cambio de base de datos ni de seguridad funcional**: migraciones, RLS, RPC, grants, auth, `empresa_id`, stock y dinero quedan fuera del alcance de esta tarea.
5. No existe una compuerta automática de code/security review garantizada: `/code-review` y `/security-review` de Claude continúan **pendientes/opcionales** por falta de disponibilidad actual.

---

## 17/10/2026 — ADR-001, ronda 3: correcciones de la segunda revisión de Codex (sigue PROPUESTA — NO APROBADA)

**Rama:** `docs/adr-001-revision` (base `4cdffb1c159cd17159ff2d0fe0180d391938d973`) · **Agente:** Claude Code · **Estado:** commiteado inicialmente como `405bf94810d8640059e7d50ea142e299138db2a4`; auditoría final realizada; pendiente de push y merge; **no existe aprobación humana de ADR-001**

### Revisión de Codex sobre la ronda 2

Veredicto: **CHANGES REQUIRED**, con 4 hallazgos (transmitidos por el usuario; el informe no está en el repositorio):

1. La redacción podía leerse como si Supabase admitiera, con condiciones, una función `SECURITY DEFINER` en un esquema expuesto.
2. La secuencia de gobernanza exigía P2–P18 antes de la validación controlada: incluía P18 (decisión futura separada) y omitía P19 y P20.
3. `auth.uid()` dentro de `SECURITY DEFINER` y el rol `authenticated` de los usuarios anónimos figuraban como incertidumbres de la documentación, aunque Supabase los documenta.
4. La ADR decía que Supabase no había confirmado la fecha del cambio de exposición automática.

### Correcciones aplicadas (solo en `docs/decisions/001-rpc-privilegiadas.md`)

1. **Secciones 4, 5 y 19:** la topología C coincide con el texto literal de `BLUEPRINT.md` §10:277, pero la guía vigente de Supabase (*Row Level Security*, "Never create one in a schema listed under 'Exposed schemas'") prohíbe explícitamente crear funciones `SECURITY DEFINER` en un esquema expuesto. C **no es un diseño recomendado por el proveedor**; sigue en la comparación solo porque el Blueprint apunta en esa dirección. Aceptar las advertencias 0028/0029 no implica aval de Supabase. El conflicto requiere decisión humana explícita (P1).
2. **Secciones 15 y 18:** la secuencia empieza con un paso 0 de gobernanza (decidir P19, resolver P20 y alinear los documentos rectores). Solo después se enumeran las decisiones técnicas necesarias para una validación controlada local o en staging (P1–P17, según el alcance que se ensaye). P18 queda excluida como requisito previo. Se aclara que hoy no está autorizada ninguna implementación, ni siquiera controlada.
3. **Sección 17.1:** `auth.uid()` en `SECURITY DEFINER` y el rol `authenticated` de los usuarios anónimos (claim `is_anonymous`) pasan a "comportamiento documentado por Supabase que igualmente debe probarse como regresión en nuestro entorno". `pg_graphql` queda como dependiente de la configuración del proyecto.
4. **Sección 17.2:** fecha oficial del proveedor según el anuncio de Supabase (discusión n.º 45329): default en proyectos nuevos desde el 30/05/2026 y aplicación a todos los proyectos existentes el **30/10/2026**. Se separa de la verificación propia de esquemas expuestos, grants y comportamiento en cada entorno.

También se actualizaron el encabezado (revisión 17/10/2026, ronda 3), el historial (sección 0) y las fuentes (sección 21). En `docs/decisions/README.md` solo cambió la referencia "ronda 2" → "ronda 3"; el estado sigue siendo PROPUESTA — NO APROBADA.

### Archivos

| Archivo | Cambio |
|---|---|
| `docs/decisions/001-rpc-privilegiadas.md` | ronda 3 de correcciones documentales |
| `docs/decisions/README.md` | referencia de ronda |
| `docs/progress-log.md` | esta entrada |

Sin SQL, migraciones, schemas, roles, grants, RLS, RPC ni cambios de seguridad. No se modificaron `BLUEPRINT.md`, `AGENTS.md`, `CLAUDE.md` ni código de aplicación.

### Cómo se verificó

- Las cuatro afirmaciones se contrastaron el 17/10/2026 con las fuentes oficiales: *Row Level Security*, *Database Functions*, *Securing your API*, *Hardening the Data API*, *Anonymous Sign-Ins* y la discusión oficial n.º 45329 de Supabase. Las páginas de documentación no indican la fecha; esta surge del anuncio oficial.
- `git diff --check`, `git status --short` y `git diff --stat`: solo cambian las tres rutas autorizadas. No se ejecutaron typecheck, tests, Playwright ni build porque no hay cambios de código.

### Riesgos pendientes

1. **ADR-001 sigue NO aprobada.** Esta ronda no autoriza ninguna implementación, ni siquiera local o en staging.
2. Siguen pendientes las veinte decisiones P1–P20, con P19 y P20 primero.
3. Hay que elegir entre el texto literal del Blueprint (C) y la guía explícita de Supabase (D u otra). Es una decisión humana.
4. La ronda 3 necesita una nueva revisión independiente sobre el commit que se cree (`AGENTS.md` §2).


### Auditoría final del commit documental

Commit auditado: `405bf94810d8640059e7d50ea142e299138db2a4`

Veredicto: **APPROVED WITH CORRECTIONS**.

La auditoría confirmó que el commit contiene únicamente los tres archivos
documentales autorizados, que ADR-001 continúa en estado
**PROPUESTA — NO APROBADA**, y que no incorpora SQL, migraciones, RLS, RPC
ni código de aplicación.

Se detectaron dos observaciones menores y no bloqueantes:

1. La bitácora todavía indicaba que la ronda 3 estaba “sin commitear”.
   Esta entrada actualiza el estado real del trabajo.
2. El historial de la ADR omitía la sección 18 en la enumeración de secciones
   modificadas por la ronda 3. Se agregó esa referencia.

Estas correcciones son exclusivamente documentales y no aprueban ninguna de
las decisiones P1–P20 ni modifican el perfil de seguridad de la propuesta.

---

## 16/10/2026 — Revisión documental de ADR-001 (sigue PROPUESTA — NO APROBADA)

**Rama:** `docs/adr-001-revision` (creada desde `4cdffb1c159cd17159ff2d0fe0180d391938d973`) · **Agentes:** OpenCode (ronda 1), Claude Code (ronda 2) · **Estado:** sin commitear; ronda 2 pendiente de nueva revisión independiente; **no existe aprobación humana de ADR-001**

### Secuencia de la tarea

1. **Ronda 1 (OpenCode):** ampliación documental de ADR-001 a v1.2 (detalle abajo, conservado como registro).
2. **Revisión independiente de Codex** sobre la ronda 1: veredicto **CHANGES REQUIRED**, con 12 correcciones obligatorias (las transmitió el usuario; el informe de Codex no está en el repositorio).
3. **Ronda 2 (Claude Code, actual):** aplica las 12 correcciones (detalle abajo).

### Ronda 2 — correcciones aplicadas

1. **Topología:** se reconoce el conflicto entre el wrapper `SECURITY DEFINER` expuesto de `BLUEPRINT.md` §10:277 y la guía vigente de Supabase (preferir `SECURITY INVOKER`; lints 0028/0029). Se comparan neutralmente A/B/C y una nueva alternativa D (fachada `SECURITY INVOKER` expuesta + implementación privilegiada en esquema no expuesto). C deja de figurar como recomendada; la única preferencia queda marcada **RECOMENDACIÓN NO VINCULANTE**.
2. **Transacciones y Edge Functions:** varias llamadas independientes a la Data API no forman una transacción; con una única RPC, esa RPC es la unidad atómica; `service_role` solo como excepción justificada, porque elude RLS.
3. **Gobernanza:** se documenta como propuesta la secuencia aprobación para prueba controlada → implementación local/staging → pruebas → segunda aceptación antes de producción. Requeriría alinear `BLUEPRINT.md` §10:279, §15:433 y la plantilla de estados de ADR si se aprueba.
4. **Jerarquía:** se retira la "contradicción" Blueprint/AGENTS de la ronda 1. Rige la regla estricta del Blueprint; el alcance de §10:279 se registra como ambigüedad (P20).
5. **Ownership y RLS:** se incorpora que el propietario de una tabla normalmente elude RLS aunque no tenga `BYPASSRLS`; ownership, `FORCE RLS` y RLS como defensa en profundidad o elusión deliberada quedan pendientes (P4).
6. **Multiempresa:** invariante de que ninguna relación cruza empresas, restricciones verificables y pruebas con IDs mezclados entre empresas; sin DDL.
7. **Auditoría e idempotencia:** la tabla `auditoria` y las columnas `idempotency_key` pasan a "modelo propuesto" (§8 se titula "Modelo de datos (propuesto)"); solo la trazabilidad y la idempotencia como propiedades quedan como aprobadas.
8. **Contrato de idempotencia:** I1–I8 enumerados como pendientes.
9. **Grants:** requisitos de diseño (USAGE, firma exacta, sobrecargas, PUBLIC, misma transacción, rol creador real). Se corrige el error técnico de v1.1: un `REVOKE` de privilegios por defecto hecho por esquema no elimina el `EXECUTE` global de `PUBLIC` (PostgreSQL 18, ALTER DEFAULT PRIVILEGES).
10. **Verificación:** separada en comportamiento documentado a probar (incluye `search_path = ''`, ya no presentado como incógnita), propiedades dependientes del entorno y regresión; la concurrencia puede probarse primero en local.
11. **Contexto:** la frase "La interfaz React usa la Supabase Data API" pasa a futuro ("usará").
12. **Bitácora:** esta sección.

Fuentes oficiales consultadas y citadas en la sección 21 de la ADR (PostgreSQL 18, Supabase y PostgREST v14).

### Ronda 1 — qué se hizo (registro histórico)

- Se revisó y amplió **solo la documentación** de ADR-001, que permanece en estado **PROPUESTA — NO APROBADA**.
- Se incorporaron de forma explícita: requisitos ya aprobados por el Blueprint; alternativas A/B/C; propietario y relación con RLS; aislamiento multiempresa; autorización; idempotencia; concurrencia y locks; grants y default privileges; contrato de errores; auditoría; matriz de pruebas; verificaciones pendientes de staging; y consecuencias sobre `BLUEPRINT.md` si se aprobara una alternativa incompatible.
- Toda decisión no definida por `BLUEPRINT.md` ni por una ADR aprobada quedó marcada **PENDIENTE DE APROBACIÓN HUMANA** (sección 5 de la ADR, puntos P1–P11), con recomendación **no vinculante**.
- Lo no verificable documentalmente quedó como **A VERIFICAR EN STAGING** (sección 15 de la ADR).
- **No se aprobó ADR-001** ni se implementó nada: sin código, SQL, migraciones, schemas, roles, grants, Supabase ni configuración de agentes.

### Archivos

| Archivo | Cambio |
|---|---|
| `docs/decisions/001-rpc-privilegiadas.md` | revisión documental (v1.2, rondas 1 y 2); estado PROPUESTA — NO APROBADA |
| `docs/decisions/README.md` | índice: versión 1.2, etiqueta de estado y referencia a P1–P20 (sección 18) |
| `docs/progress-log.md` | esta entrada |

No se modificó `BLUEPRINT.md`, `AGENTS.md`, `CLAUDE.md`, código de aplicación, SQL, migraciones, schemas, roles, grants ni Supabase.

### Cómo se verificó

- Ronda 1: cotejo de la ADR contra `BLUEPRINT.md` §3, §6, §7.3, §7.4, §7.5, §7.6, §8, §9, §10, §12, §13 y §15, y contra `AGENTS.md` §3 y §5; `git diff --check`.
- Ronda 2: citas de línea del Blueprint revisadas contra `BLUEPRINT.md` v1.4; afirmaciones de PostgreSQL, Supabase y PostgREST contrastadas con la documentación oficial (sección 21 de la ADR); `git diff --check` sin observaciones; `git status` confirma que solo cambiaron las tres rutas autorizadas. No se ejecutaron typecheck, tests ni build: no hay cambios de código.

### Riesgos pendientes

1. **ADR-001 sigue NO aprobada** y no existe aprobación humana en ninguna de sus formas. Rige la lectura estricta de `BLUEPRINT.md` §10:279: ninguna migración hasta aprobar ADR-001 y pasar las pruebas de autorización.
2. *(Retirado en la ronda 2.)* La ronda 1 registraba una "contradicción" entre `BLUEPRINT.md` §10:279 y `AGENTS.md` §3. Se reclasifica como **ambigüedad de alcance** del texto del Blueprint (P20 de la ADR); el Blueprint, de mayor jerarquía, rige.
3. Veinte decisiones quedan **PENDIENTE DE APROBACIÓN HUMANA** (P1–P20, sección 18 de la ADR), entre ellas la topología (P1) y la propuesta de gobernanza (P19).
4. Fuentes oficiales que difieren: la guía *Hardening the Data API* de Supabase muestra un `REVOKE ... FROM PUBLIC` por esquema que, según PostgreSQL 18, no tiene efecto. Hay que resolverlo con una prueba de catálogo cuando se autorice.
5. El informe de Codex (CHANGES REQUIRED) no está archivado en el repositorio; la ronda 2 se basó en las 12 correcciones transmitidas por el usuario.
6. La ronda 2 requiere una nueva revisión independiente sobre el commit que se cree (`AGENTS.md` §2).

---

## 16/10/2026 — Instalación reproducible de dos Agent Skills compartidas

**Rama:** `chore/skills-agentes` (creada desde `607394c87ec62150da6bed9c90f3749c575612e8`) · **Agente:** Codex · **Estado:** sin commitear; correcciones documentales de auditoría aplicadas; pendiente de nueva revisión independiente y aprobación humana

### Qué se hizo

- Se incorporaron únicamente `source-driven-development` y `api-and-interface-design` desde `addyosmani/agent-skills`, tag `0.6.13`, commit inmutable `aeac41d4d005999432bb7312f7ff06383a91d59d`.
- La copia canónica del repositorio quedó en `.agents/skills/`; Claude Code accede mediante dos enlaces simbólicos relativos desde `.claude/skills/`.
- Se agregó `.agents/skills/UPSTREAM.md` con fuente, versión, commit, hashes, método de instalación, precedencia de instrucciones y la excepción de estabilidad aprobada para `0.6.13`.
- La versión upstream `0.6.13` tenía menos de las dos semanas preferidas por `AGENTS.md` §6.8 al instalarse. El usuario aprobó expresamente esta excepción limitada porque corrige el ejemplo JavaScript inválido de una versión anterior (`throw;` → `throw e;`).
- No se eliminaron ni modificaron skills o plugins globales. No se actualizó Superpowers ni se instalaron paquetes.

### Resultado de la auditoría independiente de OpenCode

- La auditoría no requirió cambios en las dos skills instaladas, sus hashes ni sus enlaces; identificó correcciones documentales menores.
- Se documentó `.agents/skills/` y su propósito en `AGENTS.md` §8.
- Se aclaró en `UPSTREAM.md` que las referencias a `security-and-hardening` y `deprecation-and-migration` son opcionales y no son dependencias de ejecución; que `source-driven-development` puede consultar documentación oficial externa; que las copias del repositorio prevalecen sobre copias globales divergentes; y que los symlinks pueden fallar en entornos sin soporte, incluidos ciertos checkouts de Windows.
- `AGENTS.md` §6.9 exige registrar decisiones e incidentes relevantes, pero no exige un documento de decisión separado para esta excepción de tooling; no se creó una ADR.

### Archivos

| Archivo | Cambio |
|---|---|
| `.agents/skills/source-driven-development/SKILL.md` | nuevo; copia exacta del upstream fijado |
| `.agents/skills/api-and-interface-design/SKILL.md` | nuevo; copia exacta del upstream fijado |
| `.agents/skills/UPSTREAM.md` | nuevo; procedencia y verificación reproducible |
| `.claude/skills/source-driven-development` | nuevo; enlace relativo a `../../.agents/skills/source-driven-development` |
| `.claude/skills/api-and-interface-design` | nuevo; enlace relativo a `../../.agents/skills/api-and-interface-design` |
| `AGENTS.md` | documenta el directorio compartido `.agents/skills/` en §8 |
| `docs/progress-log.md` | esta entrada |

### Cómo se verificó

- Descarga previa a un directorio temporal mediante el helper de `skill-installer`; contenía exactamente los dos `SKILL.md` solicitados.
- SHA-256 verificados contra los valores auditados: `source-driven-development` = `c59faf851377f0eeda45306398d16eb96d77ab1c2fd3e1a7fb58e9a0af33c1e9`; `api-and-interface-design` = `e83d34f52ff12dd8a7c5134cd7e8140ea4541ec65e204f8a1e4cd366e30c4192`.
- Ambos archivos coinciden byte por byte con la descarga del commit fijado y con las copias globales existentes al momento de esta tarea.
- Los enlaces de Claude Code son relativos, resuelven a los directorios canónicos del repositorio y no están rotos.
- Se verificó que los dos `SKILL.md` conservaran exactamente sus contenidos y hashes después de las correcciones documentales.
- Compatibilidad estructural confirmada: Claude Code `2.1.301` usa `.claude/skills/`; Codex `0.162.1` y OpenCode `2.0.31` usan `.agents/skills/`. Los frontmatters `name` y `description` están presentes.
- OpenCode no ofrece `debug skill` en esta versión; Claude Code y Codex tampoco exponen un comando local de listado. No se ejecutaron prompts pagos para forzar una sesión nueva: el descubrimiento funcional queda pendiente de una nueva sesión de cada agente.
- `git diff --check`, hashes, contenido completo, destinos de enlaces, inventario de archivos nuevos y alcance del diff se verificaron localmente.

### Riesgos pendientes

1. El descubrimiento funcional debe confirmarse al iniciar una sesión nueva de Claude Code, Codex y OpenCode; la verificación actual es estructural.
2. Las copias globales hoy son idénticas, pero pueden divergir si se actualizan fuera del repositorio. Para este proyecto prevalece la copia fijada en `.agents/skills/`.
3. `source-driven-development` puede requerir red al consultar documentación oficial; toda fuente recuperada sigue tratándose como entrada no confiable y no puede ampliar el alcance autorizado.
4. Las skills permanecen subordinadas a `BLUEPRINT.md`, a las ADR aprobadas y a las reglas de `AGENTS.md`; no autorizan implementar propuestas pendientes.

---

## 16/10/2026 — Inventario técnico de Etapa 0 (`INVENTARIO_ETAPA_0.md`) y rondas de corrección por revisión de Codex

**Rama:** `docs/inventario-etapa-0` (creada desde `main` a la altura de `6e97696`) · **Agente:** OpenCode · **Estado:** sin commitear; corrección documental en curso; **pendiente de aprobación humana** y **sin revisión final posterior** sobre la versión corregida

### Secuencia de la tarea

1. **Auditoría original (Etapa 0).** Inventario técnico de solo lectura del prototipo contra `BLUEPRINT.md` v1.4. Registró, entre otros hallazgos, que el prototipo es un frontend sin backend que incumple casi todas las reglas vigentes del Blueprint.
2. **Primera revisión independiente de Codex.** Veredicto: **APPROVE WITH CORRECTIONS**. Solicitó 4 correcciones importantes y 8 menores.
3. **Correcciones de OpenCode (ronda 1).** Se creó `INVENTARIO_ETAPA_0.md` preservando el informe íntegro (única edición al cuerpo original: el título, E-9), se agregó el apéndice de verificación y la sección «Erratas y aclaraciones validadas por Codex» con E-1 a E-12.
4. **Segunda revisión independiente de Codex.** Veredicto: **CHANGES REQUIRED**. Planteó 5 hallazgos sobre la ronda 1.
5. **Correcciones de OpenCode (ronda 2, actual).** Se resuelven esos 5 hallazgos (detalle abajo).

### Correcciones de la ronda 2 (actual)

- **Nota de precedencia** al inicio de `INVENTARIO_ETAPA_0.md`: las erratas E-1 a E-12 prevalecen sobre las afirmaciones originales a las que refieren; el cuerpo original se conserva solo como registro histórico; en caso de contradicción manda la errata, subordinada a `BLUEPRINT.md` y a las ADR aprobadas.
- **E-1 ampliada:** se preserva la afirmación histórica «ninguna tarea de base de datos puede avanzar» y se **supersede**. Documentación, análisis arquitectónico, pruebas independientes y diseño no dependiente **pueden continuar**; las **migraciones** y la implementación dependientes de la arquitectura propuesta de **RPC privilegiadas** **siguen bloqueadas** hasta la aprobación correspondiente.
- **E-3 ampliada** a §19 paso 5: reemplazar los ocho hooks por RPC **no es** un requisito arquitectónico aprobado; las RPC son exigibles para las escrituras críticas de stock y dinero, mientras las lecturas ordinarias y el CRUD permitido pueden usar RLS y `SECURITY INVOKER`.
- **E-4 ampliada** a §19 paso 2: cantidades enteras en la unidad mínima y conversión pieza/media pieza **ya definidas**; solo quedan pendientes el precio de la media pieza y el redondeo.
- **Consistencia en la bitácora:** la afirmación amplia de una entrada anterior («Ninguna tarea de base de datos puede avanzar hasta su aprobación», en los riesgos de la tarea «Inventario de Etapa 0 ausente») queda **igualmente superada** por E-1. Se conserva como registro histórico de esa tarea y **no se reescribe**.
- **Apéndice actualizado:** la subsección pasa a «Revisiones independientes (Codex)» y registra ambas revisiones, la ronda 2 en curso y el hecho de que la versión corregida **no pasó aún una revisión final**.

### Qué se hizo (acumulado)

- `INVENTARIO_ETAPA_0.md` (nuevo): informe preservado + apéndice de verificación + erratas E-1 a E-12 + nota de precedencia.
- `docs/progress-log.md`: esta entrada.
- **No se implementó ninguna recomendación del informe.** Sin cambios en código de aplicación, SQL, migraciones, dependencias ni configuración de agentes.

### Archivos

| Archivo | Cambio |
|---|---|
| `INVENTARIO_ETAPA_0.md` | nuevo (informe preservado + verificación + erratas E-1 a E-12 + precedencia) |
| `docs/progress-log.md` | esta entrada |

Sin otros archivos creados, modificados ni borrados. `informe_temporal.txt` no existe en el repositorio (no fue creado ni eliminado por esta tarea); la fuente usada fue el informe recibido en la conversación.

### Cómo se verificó

- Referencias del informe cotejadas contra el estado real del repositorio: `git rev-parse HEAD` = `6e97696…`, `git ls-files` = 73, `git tag` = 0, rutas, rangos de línea y citas de `BLUEPRINT.md`.
- `git diff --check` sin problemas; diff final inspeccionado (archivo nuevo incluido vía `git add -N`, revertido después para no dejar nada preparado).
- Confirmado que solo se crearon/modificaron `INVENTARIO_ETAPA_0.md` y `docs/progress-log.md`.

### Riesgos pendientes

1. **La versión corregida NO pasó aún una revisión final.** La segunda revisión de Codex terminó en **CHANGES REQUIRED**; la ronda 2 está sin revisar. No debe interpretarse como aprobada.
2. **Aprobación humana pendiente** para commit, push, merge o deploy.
3. **Fuente del informe:** `informe_temporal.txt` no estaba disponible; el texto se tomó de la conversación y no pudo cotejarse contra un archivo.
4. **Discrepancias DC-1 a DC-4:** quedan documentadas pero **sin corregir** en el cuerpo del informe (preservación histórica).
5. **ADR-001 sigue en `propuesta`** y 5 reglas siguen `PROPUESTA NO APROBADA` en `BLUEPRINT.md` v1.4. Según la interpretación vigente (errata E-1), las **migraciones** y la implementación dependientes de la arquitectura propuesta de RPC privilegiadas siguen bloqueadas; el resto del trabajo documental, de análisis, de pruebas independientes y de diseño no dependiente puede continuar.
6. **Ítems §18.19, §18.21 y §18.22** (root de Vercel, ejecución real del CI en GitHub y versiones en el registro npm) siguen sin verificar por quedar fuera del repositorio.

---

## 12/10/2026 — Cierre de configuración de herramientas (Claude Code, OpenCode, Vitest, Playwright)

**Rama:** `chore/configuracion-agentes` (creada desde `eae777f`, mismo commit que `chore/tarea-001-preparar-repo`; 1 commit por delante de `main`) · **Agente:** Claude Code · **Estado:** sin commitear, pendiente de aprobación humana para commit y posterior auditoría (Codex / OpenCode)

### Qué se hizo

Cambios preparados por el usuario (en stage) y verificados en esta sesión; Claude Code solo agregó esta entrada de bitácora.

- `.claude/settings.json`: `permissions.defaultMode: "default"`.
- `opencode.json` + `.opencode/agents/auditor.md`: permisos `ask` para edit/bash/external_directory; subagente auditor de solo lectura (`edit: deny`, `bash: deny`).
- Vitest: `apps/web/vitest.config.ts` (solo `src/**/*.test.ts(x)`, excluye `tests/`) y prueba de humo `src/tests/smoke.test.ts`.
- Playwright `1.64.0`: `apps/web/playwright.config.ts` (chromium, levanta `vite` dev en `127.0.0.1:4173`) y `tests/example.spec.ts`.
- `.gitignore` raíz y `apps/web/.gitignore`: `.env*` (excepto `*.example`), `*.pem`, `*.key`, reportes de Playwright, `*.backup`.
- `AGENTS.md` y `CLAUDE.md` reescritos (ver riesgos).

**No se modificó** lógica de stock, ventas, caja ni clientes. Sin migraciones ni acceso a producción.

### Cómo se verificó

Local, Node 24.20.0, npm 11.19.0, desde `apps/web/`:

| Verificación | Resultado |
|---|---|
| `npm run typecheck` | exit 0 |
| `npm test` (Vitest 5.0.2) | 2 archivos, 5 pruebas, todas pasan |
| `npx playwright test` | 1 prueba (chromium), pasa |
| `npm run build` | exit 0, `index-E6w3GRy_.js` (mismo hash que en Tarea 001: bundle sin cambios) |
| `npm run lint` | exit 1: 10 errores + 1 advertencia, **idénticos** a `docs/incidents/2026-10-12-lint-falla-en-main.md` (sin errores nuevos) |
| Workflows | único archivo `.github/workflows/ci.yml`; sin duplicados |
| Secretos | no hay `.env*`, `*.pem` ni `*.key` en el árbol ni trackeados; `git check-ignore` confirma que `*.backup`, `playwright-report/`, `test-results/`, `dist/` y `.claude/settings.local.json` están ignorados |

### Correcciones aprobadas (13/10/2026)

En la primera revisión se detectaron tres puntos; el usuario autorizó corregirlos así:

1. **OpenCode / Superpowers.** Se conserva la clave `plugins` (plural): es la correcta para OpenCode V2 según `obra/superpowers/.opencode/INSTALL.md`. La observación inicial de que debía ser `plugin` era incorrecta: esa clave corresponde a V1. El plugin queda fijado en `#v6.4.2` (commit `8ca22db`, publicado el 25/09/2026). INSTALL.md exige `v6.4.1` o posterior para V2, y las notas de la versión 6.4.2 confirman soporte para OpenCode 2.0.4+. Se descartó `v7.0.0` (publicado el 09/10/2026) por tener menos de dos semanas.
2. **`AGENTS.md` / `CLAUDE.md`** combinados: se conserva el contenido nuevo y se recupera de `eae777f` la lista de propuestas no aprobadas, las restricciones de producción y seguridad, los comandos, las versiones exactas, el idioma y el cierre de tarea. Se agrega el flujo oficial: Claude Code implementa; Codex y OpenCode auditan de forma independiente el mismo commit; el usuario aprueba. `CLAUDE.md` vuelve a importar `@AGENTS.md`.
3. **Dependencias exactas:** `vitest` `5.0.2` y `@playwright/test` `1.64.0` (`npm install -E`). El lockfile solo cambió los especificadores raíz; las versiones resueltas no cambiaron.

### Verificación posterior a las correcciones

Instalación limpia (`rm -rf node_modules && npm ci`, 0 vulnerabilidades):

| Verificación | Resultado |
|---|---|
| `npm run typecheck` | exit 0 |
| `npm test` | 2 archivos, 5 pruebas, todas pasan |
| `npx playwright test` | 1 prueba (chromium), pasa |
| `npm run build` | exit 0, `index-E6w3GRy_.js` (sin cambios) |
| `npm run lint` | exit 1, mismos 10 errores + 1 advertencia del incidente (comparación línea por línea: idéntica) |
| OpenCode 2.0.27 | `opencode plugin list` muestra `superpowers 8ca22db …#v6.4.2`; `opencode debug agents` muestra el subagente `auditor`. No se ejecutó un prompt contra el modelo |
| Workflows | solo `.github/workflows/ci.yml` |
| Secretos | sin `.env*`, `*.pem`, `*.key` ni credenciales en el árbol, en el stage ni en el diff |

### Riesgos pendientes

1. **La configuración global de OpenCode** (`~/.config/opencode/opencode.jsonc`, fuera del repo) también declara `superpowers` sin versión fija. Hoy resuelve al mismo commit, pero quedan dos specs registrados para el mismo plugin, que podría cargarse dos veces. No se modificó porque es configuración personal.
2. **`@playwright/test` 1.64.0** se publicó el 07/10/2026, hace menos de las dos semanas recomendadas. Se mantuvo para no cambiar de versión.
3. **Playwright no corre en CI** ni tiene script npm (`test:e2e`); los navegadores se instalan con `npx playwright install chromium`.
4. **`tsc -b` no cubre** `vitest.config.ts`, `playwright.config.ts` ni `tests/*.spec.ts` (solo `src/` y `vite.config.ts`).
5. `tests/example.spec.ts` usa URL absoluta en lugar de `baseURL`; la prueba solo verifica que `body` sea visible.
6. Falta la verificación funcional de Superpowers dentro de una sesión de OpenCode ("Tell me about your superpowers"): la debe hacer el usuario, porque consume el proveedor de modelos.

---

## 12/10/2026 — Tarea 001: Preparación del repositorio

**Rama:** `chore/tarea-001-preparar-repo` · **Agente:** Claude Code · **Estado:** pendiente de aprobación humana para merge

### Qué se hizo

- Se incorporó `BLUEPRINT.md` v1.4 a la raíz del repositorio (sin cambios en su contenido).
- Se movió `ADR-001-rpc-privilegiadas_v1.1.md` a `docs/decisions/001-rpc-privilegiadas.md` (contenido sin cambios; estado: **propuesta, NO aprobada**).
- Se creó la estructura `docs/` según Blueprint sección 13: `decisions/` (índice + plantilla), `incidents/` (índice + plantilla), `progress-log.md`, `changelog.md`.
- Se creó `AGENTS.md` (común a Claude Code, OpenCode y Codex) con prohibición expresa de implementar propuestas no aprobadas y ADR en estado `propuesta`, con lista de las propuestas vigentes en v1.4.
- Se creó `CLAUDE.md` (importa `AGENTS.md` y agrega reglas específicas de Claude Code).
- Se creó `.gitignore` en la raíz. Antes, **`.env` no estaba ignorado** (solo `*.local` en `apps/web/.gitignore`). Ahora se ignoran `.env`, `.env.*` (excepto `.env.example`), `.vercel`, temporales locales de Supabase CLI, claves/certificados y JSON de credenciales. Se conservó `apps/web/.gitignore`.
- Se agregó Vitest `5.0.2` (versión exacta, publicada el 25/09/2026) como devDependency en `apps/web/`, y los scripts `typecheck`, `test` y `test:watch`.
- Se agregó una primera prueba de caracterización (`apps/web/src/data/mockData.test.ts`): unicidad de ids en datos demo y comportamiento actual de `salidasPorMovimiento`. Documenta el prototipo; **no** valida reglas del Blueprint.
- Se agregó CI en `.github/workflows/ci.yml`: job bloqueante `verificar` (typecheck → test → build) y job `lint` no bloqueante por errores preexistentes.
- Se registró el incidente `docs/incidents/2026-10-12-lint-falla-en-main.md`.

**No se modificó** lógica de stock, ventas, dinero, autenticación ni pantallas. No se borraron módulos ni datos demo. No se instaló Supabase, no se generaron migraciones, no se tocó producción ni Vercel.

### Archivos

| Archivo | Cambio |
|---|---|
| `BLUEPRINT.md` | agregado (v1.4, sin cambios) |
| `docs/decisions/001-rpc-privilegiadas.md` | movido desde la raíz (sin cambios) |
| `docs/decisions/README.md` | nuevo |
| `docs/incidents/README.md` | nuevo |
| `docs/incidents/2026-10-12-lint-falla-en-main.md` | nuevo |
| `docs/progress-log.md` | nuevo |
| `docs/changelog.md` | nuevo |
| `AGENTS.md` | nuevo |
| `CLAUDE.md` | nuevo |
| `.gitignore` | nuevo (raíz) |
| `README.md` | enlaces a Blueprint, agentes, docs y app (había 3 títulos duplicados) |
| `.github/workflows/ci.yml` | nuevo |
| `apps/web/package.json` | scripts `typecheck`, `test`, `test:watch`; devDependency `vitest` |
| `apps/web/package-lock.json` | actualizado por `npm install` |
| `apps/web/src/data/mockData.test.ts` | nuevo |

### Cómo se verificó

Ejecutado en local (Node 24.20.0, npm 11.19.0), desde `apps/web/` tras `rm -rf node_modules && npm ci`:

| Verificación | Antes (main) | Después |
|---|---|---|
| `npm run typecheck` | — (no existía; `tsc -b` pasaba dentro de `build`) | exit 0 |
| `npm test` | — (no existía) | 1 archivo, 4 pruebas, todas pasan |
| `npm run build` | exit 0, `index-E6w3GRy_.js` | exit 0, `index-E6w3GRy_.js` (**mismo hash**: el bundle de la app no cambió) |
| `npm run lint` | 10 errores, 1 advertencia | 10 errores, 1 advertencia (sin errores nuevos) |
| `.gitignore` | `.env` versionable | `git check-ignore`: `.env`, `.env.local`, `.env.production`, `apps/web/.env`, `apps/web/.env.development.local`, `supabase/.temp/*`, `*.pem` ignorados; `.env.example` versionable |
| `ci.yml` | — | YAML válido (`yaml valid`). **No ejecutado aún en GitHub Actions**: correrá al abrir el PR |

### Inventario técnico de Etapa 0

**No se encontró** en el repositorio (no existía `docs/` ni `progress-log.md`). Esta tarea no lo reemplaza. Observaciones hechas al pasar, sin análisis exhaustivo, para que el inventario las considere:

- El frontend persiste todo en `localStorage` (hooks en `apps/web/src/hooks/`); no hay backend ni Supabase. El stock se modifica desde el frontend, contrario a Blueprint secciones 3 y 6 (esperable en un prototipo).
- `UnidadMedida` incluye `"kg"` (`apps/web/src/data/mockProductos.ts`), pero el Blueprint excluye venta por kilogramo (sección 2) y define `unidad`/`pieza` con stock en medias piezas (7.1).
- `CondicionPago` usa `cuenta_corriente`; el Blueprint deja la gestión de cuenta corriente para Fase 2 y en Fase 1 solo registra importe `a_cuenta`.
- Los roles y el login son de demostración (`AuthContext.tsx`), no Supabase Auth.

### Riesgos pendientes

1. **Inventario de Etapa 0 ausente.** Debe hacerse antes de la Etapa 1.
2. **Lint falla en `main`** (incidente abierto). CI lo informa sin bloquear; mientras tanto, errores nuevos de lint podrían pasar desapercibidos si nadie mira el job.
3. **CI no probado en GitHub.** Puede requerir ajustes al primer run (p. ej. permisos de Actions en el repo).
4. **Las pruebas actuales son de caracterización del prototipo**, no cubren ninguna prueba obligatoria de la sección 12. Esas requieren Supabase + pgTAP, bloqueadas hasta aprobar ADR-001.
5. **Estructura del Blueprint vs repo:** el Blueprint muestra `src/` en la raíz; el código vive en `apps/web/src/`. Se documentó en `AGENTS.md`; conviene reflejarlo en una próxima versión del Blueprint.
6. **Vercel:** no se verificó si el proyecto de Vercel usa `apps/web` como root directory; los nuevos archivos en la raíz no deberían afectar el deploy, pero no se comprobó.
7. **ADR-001 sigue en `propuesta`.** Ninguna tarea de base de datos puede avanzar hasta su aprobación.
