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
