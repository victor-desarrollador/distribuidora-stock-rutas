# ADR-005 — Fiambres por peso y unidad mínima en gramos

**Fecha:** 25/10/2026
**Estado:** APROBADA (aprobación humana explícita del dueño del proyecto, 25/10/2026, a partir de una reunión con el cliente)
**Versión:** 1.0
**Reemplaza:** la política de unidades pieza/media pieza de `BLUEPRINT.md` §2 y §7.1 (decisión humana del 13/10 y del 18/10/2026) y, **en su totalidad**, a [ADR-003](003-precio-derivado-media-pieza.md) (ver §4). [ADR-002](002-precios-independientes-pieza-media.md) ya estaba superada y sigue siendo histórica.

> **Alcance.** Esta ADR fija la **regla de negocio** y la **representación canónica** de las cantidades de fiambres. **No autoriza** migraciones, cambios de SQL, RPC, RLS, grants, cambios en el frontend, pruebas ni cambios en el prototipo. Su implementación requiere una **tarea posterior específica** de cambio de modelo y de migración, con su propio preámbulo (`AGENTS.md` §1.3), su plan autorizado y su security review (toca `movimientos_stock`, ventas y precios: `AGENTS.md` §2.4). No modifica ADR-001 ni su estado (**APROBADA PARA VALIDACIÓN CONTROLADA**); producción sigue bloqueada.

---

## 1. Contexto

Desde el 13/10/2026 el Blueprint establecía que los fiambres se vendían y controlaban **únicamente por pieza o media pieza**, con representación canónica entera en **medias piezas**, y que **no existía `kg` en Fase 1** (Blueprint v1.2–v2.0, §2 y §7.1). ADR-002 y ADR-003 fijaron el precio de pieza y de media pieza dentro de ese modelo.

En una reunión con el cliente (registrada el 25/10/2026) se confirmó que esa regla no refleja la operación real:

- los fiambres **no** se venden por pieza ni por media pieza;
- se venden **por peso**, expresado comercialmente en **kilogramos**;
- las cantidades son **fraccionarias en kg** (en el flujo real del cliente aparecen cantidades como `28,680 kg` y `47,300 kg`; son evidencia de la precisión que usa el negocio, **no** son datos de prueba ni de configuración del sistema);
- el precio comercial de un fiambre es **por kg**.

Los lácteos y demás productos por unidad no cambian: se siguen vendiendo y controlando por **unidad entera**.

El sistema conserva una invariante que ya está implementada y probada en el ledger (`supabase/migrations/20261025021032_stock_operaciones_ingreso.sql`: `movimientos_stock.cantidad integer` con `check (cantidad > 0)`; vista `stock_actual` en `bigint`): **toda cantidad del ledger es un entero positivo en la unidad mínima del producto**. La decisión debe introducir el peso **sin romper esa invariante** y sin introducir aritmética de punto flotante.

## 2. Decisión

### 2.1 Regla de negocio (confirmada por el cliente)

1. Cada producto tiene una **forma de venta** con dos valores conceptuales:
   - **`unidad`** — lácteos y productos por unidad: cantidad **entera** de unidades. Sin cambios.
   - **`peso`** — fiambres: se venden, cargan, cuentan, retornan y rinden **por peso**. Reemplaza a `pieza`.
2. **No existen la pieza ni la media pieza** como unidad de venta, de stock ni de precio.
3. En los productos `peso`, el **precio comercial es por kg**. En los productos `unidad`, el precio es unitario (sin cambios).
4. Comercialmente (pantallas, comprobantes internos, presupuestos, reportes) la cantidad de un producto `peso` se expresa **en kg**: se **ingresa con hasta 3 decimales** (§2.2.5) y se **muestra con 3 decimales fijos** (`1,000 kg`, `1,200 kg`, `1,250 kg`, `28,680 kg`).
5. Se mantiene la consistencia categoría ↔ forma de venta: `Lácteos` ↔ `unidad` y `Fiambres` ↔ `peso`. `Lácteos` + `peso` y `Fiambres` + `unidad` siguen sin admitirse. (Ejemplo de coherencia, no regla de nombres: `Queso cremoso en bote` → Lácteos/`unidad`; un queso cremoso que se vende fraccionado por peso → Fiambres/`peso`.)

Los nombres `unidad` y `peso` son los **valores conceptuales**. El nombre y el tipo SQL definitivos (por ejemplo, si `forma_venta` conserva su nombre de columna) se fijan en la tarea de migración.

### 2.2 Representación canónica (aprobada)

1. **Unidad mínima de un producto `peso`: el gramo.** La cantidad canónica es un **entero de gramos**: `28,680 kg` → `28680`; `47,300 kg` → `47300`; `1,250 kg` → `1250`.
2. **Unidad mínima de un producto `unidad`: la unidad entera** (sin cambios).
3. **Invariante conservada:** todas las cantidades del ledger (`movimientos_stock.cantidad`) y de los documentos (carga, venta, retorno, conteo, merma, presupuesto) son **enteros positivos en la unidad mínima**. `stock_actual` sigue siendo la suma entera de movimientos.
4. **Nunca `float` / `double precision` / `real`** para cantidades ni para dinero, ni en la base ni como paso intermedio.
5. **Precisión de entrada:** una cantidad en kg admite **como máximo 3 decimales** (son válidas, por ejemplo, `1`, `1,2`, `1,25` y `1,250`). Una entrada con más de 3 decimales se **rechaza**; no se redondea, no se trunca y no se normaliza (mismo criterio que la regla vigente de precios con más de 2 decimales). Cantidad `0` o negativa se rechaza donde hoy se rechaza.
6. **Conversión kg ↔ gramos sin punto flotante.** La conversión de lo que escribe el usuario a gramos se hace sobre la representación decimal exacta (texto o `numeric`), nunca multiplicando un `Number` de JavaScript por 1000. Ejemplo del riesgo: en JavaScript, `1.005 * 1000` da `1004.9999999999999`. La presentación inversa (gramos → kg) es una división exacta por 1000 con 3 decimales fijos.

### 2.3 Dinero

1. Los importes y precios se siguen guardando en PostgreSQL como **`numeric(14,2)`**, nunca `float`. Los precios admiten como máximo 2 decimales; más de 2 se rechaza; se mantiene la validación mínima `>= 0`. La aritmética monetaria es exacta mediante enteros o `numeric`; nunca se usa punto flotante. Si un cálculo excede el rango representable o produce desbordamiento, la operación falla con error y nunca devuelve un valor aproximado. Un resultado exacto con más de 2 decimales **no** es por sí mismo un error: la conversión del valor monetario exacto al importe final se rige por D-R1 (§2.3.3, §5).
2. Conceptualmente, el importe de una línea `peso` es:

   ```text
   importe = cantidad_kg × precio_por_kg
           = gramos × precio_por_kg / 1000
   ```

   y el de una línea `unidad`, `cantidad × precio_unitario` (sin cambios).
3. Con gramos enteros y un precio con 2 decimales, el valor exacto del importe `peso` puede tener **hasta 5 decimales** (por ejemplo, `1 g × 0,01 $/kg = 0,00001`). Cómo se convierte ese valor exacto al importe monetario final es la **política de redondeo monetario pendiente (D-R1)**. Hasta que se decida:
   - no se fija fórmula SQL ni de dominio, ni el destino del redondeo, ni la regla de empate, ni el momento en que se aplica, ni la escala intermedia;
   - la implementación deberá definir explícitamente el momento y la regla de redondeo según la política que se apruebe. No se debe confiar en el redondeo implícito de la columna: PostgreSQL redondea en silencio un valor con más decimales que la escala declarada de un `numeric(p,s)`.
4. **Historial:** cada ítem de venta (y de presupuesto) conserva la cantidad canónica, el **precio por kg o unitario aplicado** y el **importe** calculado según la política de D-R1. Un documento histórico se reconstruye con esos valores guardados, **sin volver a calcularlos** con la regla vigente.

## 3. Alternativas descartadas

- **Mantener pieza/media pieza:** contradice la operación real confirmada por el cliente.
- **Guardar kg con decimales (`numeric(…,3)`) en el ledger:** representación exacta y válida en PostgreSQL. Se descarta porque rompe la invariante «el ledger son enteros en unidad mínima», que ya está implementada (`cantidad integer`, `check (cantidad > 0)`) y probada en Etapa 2; obligaría a mezclar escalas entre productos `unidad` y `peso` en la misma columna y a revisar todas las RPC y pruebas de stock. Gramos enteros dan la misma exactitud (3 decimales de kg) sin cambiar el tipo del ledger.
- **`float` / `double precision`:** inexacto. La documentación oficial de PostgreSQL indica que `real` y `double precision` son «inexact, variable-precision» y recomienda `numeric` cuando se requiere exactitud, como en importes monetarios.
- **Decigramos o miligramos:** más precisión que la que usa el negocio (3 decimales de kg) y reducen el rango útil de `integer` sin una necesidad concreta.
- **Mantener la media pieza para algunos fiambres:** el cliente confirmó que los fiambres se venden por peso. Si en el futuro hubiera productos por pieza, haría falta una decisión nueva.

## 4. Relación con ADR-002 y ADR-003

**ADR-003 queda REEMPLAZADA** por esta ADR, **en su totalidad**. Se conserva como **registro histórico**, no se borra y **no conserva autoridad normativa**.

**Semántica reemplazada.** Toda la semántica propia de ADR-003 dependía del modelo pieza/media pieza:

- §2.1: el producto `pieza` y su único precio de pieza completa. Ahora: producto `peso` con precio por kg.
- §2.2–§2.3: el precio de media pieza derivado (`floor((centavos_pieza + 100) / 200)`) y su tabla de ejemplos.
- §2.4: la cantidad canónica en medias piezas y la presentación «N piezas + 1 media».
- §2.5: el subtotal por piezas y media (`floor(c / 2) × precio_pieza + …`).
- §2.7: el snapshot del precio de media pieza aplicado y sus reglas de invalidez.

**Principios que siguen vigentes por otras fuentes, no por ADR-003:**

- precios con un máximo de 2 decimales (más de 2 se rechaza) y validación mínima `>= 0`: `BLUEPRINT.md` §7.1 y §2.3.1 de esta ADR;
- aritmética monetaria exacta, sin punto flotante: `BLUEPRINT.md` §7.1 y §2.2.4 y §2.3.1 de esta ADR;
- error ante desbordamiento o valor fuera del rango representable (nunca un valor aproximado): §2.3.1 de esta ADR. La conversión de un resultado exacto con más de 2 decimales al importe final no es un error y se rige por D-R1;
- subtotal `unidad` = `cantidad × precio_unitario`: `BLUEPRINT.md` §7.1 y §2.3.2 de esta ADR;
- snapshot histórico del precio aplicado y del importe: `BLUEPRINT.md` §7.1 y §2.3.4 de esta ADR.

**Estado actual del código (no es regla):** el prototipo demo todavía implementa ADR-003 sobre las claves `localStorage` `_demo_v4` hasta que se implemente esta ADR (`BLUEPRINT.md` §7.1; §6).

ADR-002 ya estaba **SUPERADA** por ADR-003 y sigue siendo histórica; su cantidad canónica en medias piezas y su presentación comercial también quedan reemplazadas por esta ADR.

## 5. Decisiones pendientes que esta ADR no resuelve

| ID | Pendiente | Por qué bloquea |
|---|---|---|
| D-R1 | **Política de redondeo monetario** del importe `gramos × precio_por_kg / 1000`: a centavos o a pesos enteros; regla de empate (por ejemplo, alejándose de cero, que es como redondea `round(numeric)` en PostgreSQL, o al par); momento en que se aplica (por línea, sobre el total u otro) y escala intermedia. Nada de esto está decidido. | Sin ella no se puede implementar el importe de venta, presupuesto, carga valorizada ni faltantes valorizados. |
| D-R2 | **Pesaje en la operación:** cómo y dónde se obtiene el peso en cada paso (ingreso, carga, venta en ruta, devolución, conteo de regreso); si el camión pesa en el momento de la venta o se vende por pieza pesada previamente. | Define la UX y qué cantidades se capturan en cada documento. |
| D-R3 | **Diferencias de pesaje:** si una diferencia de gramos por balanza o por pérdida natural de peso se trata como faltante/sobrante ordinario o si existe una tolerancia. No se asume ninguna tolerancia: hasta que se decida, toda diferencia es una diferencia. | Afecta a la rendición (§7.8) y a la regularización (§7.9.3). |
| D-R4 | **Datos existentes en local/staging:** cómo se tratan los productos `pieza` y sus movimientos en medias piezas ya creados en local o en staging (reinicio limpio o migración explícita). Nunca se reinterpreta en silencio una media pieza como gramo. | Lo resuelve la tarea de migración. Producción no tiene datos. |

## 6. Consecuencias (para la tarea posterior; nada se implementa ahora)

- **Productos (`public.productos`, migración `20261023140000_catalogo_productos.sql`):** hoy hay `check (forma_venta in ('unidad','pieza'))`, la consistencia `fiambres ↔ pieza`, el comentario «precio de pieza completa (pieza); media derivada» y `stock_minimo` «en unidades o medias piezas». Hará falta una migración nueva (no la edición de una migración ya aplicada) para `peso`, el precio por kg y el `stock_minimo` en gramos. También hay que actualizar `crear_producto`/`actualizar_producto` y sus pruebas pgTAP.
- **`movimientos_stock` / `stock_actual`:** el tipo entero se mantiene. Para productos `peso`, `cantidad` pasa a significar gramos. `integer` admite hasta 2.147.483.647, es decir unos 2.147 t por movimiento, y `stock_actual` suma en `bigint`. Las RPC vigentes (`registrar_ingreso`, `mover_a_cuarentena`, `registrar_merma`) reciben `p_cantidad integer` sin conocer la unidad, así que la tarea de migración tendrá que revisar si alcanza con eso o si hace falta una validación por forma de venta. Las huellas de idempotencia v1 no cambian de forma. Para el reinicio de datos rige D-R4.
- **Carga, ventas, retornos, conteos y rendición** (todavía no implementados en SQL): se diseñan directamente en unidad mínima (gramos para `peso`). El esperado, el contado y la diferencia de rendición quedan en gramos y se muestran en kg. Hasta que se resuelva D-R1, la valorización de diferencias no puede definirse.
- **Precios:** desaparece el precio de media pieza. `venta_items` conserva cantidad, precio aplicado (por kg o unitario) e importe (§2.3.4; política de redondeo pendiente, D-R1).
- **Pruebas:** dejan de ser requisito las pruebas de media pieza y de precio derivado (Blueprint §12). Las pruebas pgTAP y Vitest actuales que validan `pieza` y medias piezas (`productos_catalogo`, `apps/web/src/domain/cantidades.ts`, `precios.ts` y sus tests) se reemplazan en la tarea de implementación, no en esta.
- **Prototipo demo (`apps/web/src/`):** sigue con el modelo pieza/media pieza de ADR-003 hasta que se autorice su cambio. Hay un riesgo de reinterpretación silenciosa: un `9` guardado en medias piezas leído como gramos daría 9 g. Al implementarlo debe aplicarse el mismo criterio ya aprobado para cambios de semántica (v1 → v2 → v3 → v4): **versión nueva de las claves operativas, con inicialización limpia y sin leer, copiar, reinterpretar ni borrar las claves anteriores**. El número de versión y las claves exactas se fijan en esa tarea.
- **Documentación:** `BLUEPRINT.md` v2.1 y `docs/PRD.md` v0.11 reflejan esta decisión. `docs/requirements/migracion-unidades-prototipo.md` queda histórico en lo referido a pieza/media pieza.

## 7. Fuentes

- PostgreSQL, *Numeric Types* — `numeric` «is especially recommended for storing monetary amounts and other quantities where exactness is required»; `real` y `double precision` «are inexact»; rango de `integer` y `bigint`; «If the scale of a value to be stored is greater than the declared scale of the column, the system will round the value»; «the numeric type rounds ties away from zero»: https://www.postgresql.org/docs/current/datatype-numeric.html
- PostgreSQL, *Mathematical Functions* — `round(v numeric, s integer)`: «Ties are broken by rounding away from zero»: https://www.postgresql.org/docs/current/functions-math.html
- MDN, `Number.MAX_SAFE_INTEGER` (2^53 − 1; aritmética de doble precisión en JavaScript): https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/MAX_SAFE_INTEGER
