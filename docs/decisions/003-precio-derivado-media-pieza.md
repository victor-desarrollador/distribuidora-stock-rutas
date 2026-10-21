# ADR-003 — Precio derivado de media pieza

**Fecha:** 21/10/2026
**Estado:** APROBADA (aprobación humana explícita del dueño del proyecto, 21/10/2026)
**Versión:** 1.0
**Supera a:** ADR-002, **únicamente** en la política de precio de media pieza (ver §4).

> **Alcance.** Esta ADR autoriza el modelo de precios del **prototipo frontend** (`apps/web/`). **No aprueba** tablas, columnas, tipos ni restricciones SQL definitivas, ni migraciones, ni Supabase. **No hay SQL aprobado.**

---

## 1. Contexto

ADR-002 (20/10/2026) fijó que un fiambre tenía dos precios comerciales independientes, pieza completa y media pieza, ambos configurables por el propietario. El dueño del proyecto decidió reemplazar esa política: el precio de la media pieza **no se configura**, se deriva del precio de la pieza completa.

El resto de ADR-002 (cantidad canónica en medias piezas, presentación comercial, máximo 2 decimales, cálculo en centavos enteros, implementación única del subtotal e historial de precios aplicados) **sigue vigente** y se reitera aquí para que esta ADR sea autosuficiente.

## 2. Decisión

1. **Precio de media pieza no configurable.** Un producto `pieza` tiene un único precio configurable: el de la pieza completa. No existe un campo editable de precio de media pieza. Un producto `unidad` tiene un único precio unitario.
2. **Media = mitad del precio de pieza, redondeada al peso entero:**
   - fracción de la mitad `>= .50` → sube al peso entero siguiente;
   - fracción de la mitad `< .50` → baja al peso entero anterior.

   El resultado es siempre un **peso entero** (sin centavos).
3. **Aritmética en centavos enteros.** La regla se calcula sobre enteros, sin división de punto flotante sobre pesos:

   ```
   centavos_pieza = precio_a_centavos(precio_pieza)
   precio_media_en_pesos = floor((centavos_pieza + 100) / 200)
   ```

   Si `centavos_pieza + 100` excede el entero seguro, el cálculo **falla cerrado** (error), nunca devuelve un valor aproximado.

   | Pieza | Mitad | Media |
   |---|---|---|
   | 20,98 | 10,49 | 10 |
   | 20,99 | 10,495 | 10 |
   | 21,00 | 10,50 | 11 |
   | 21,01 | 10,505 | 11 |
   | 21,02 | 10,51 | 11 |
   | 20 | 10 | 10 |
   | 21 | 10,5 | 11 |
   | 25 | 12,5 | 13 |

4. **Cantidad canónica sin cambios.** El stock y la persistencia usan el entero `c` en medias piezas. Comercialmente `c` se descompone en `floor(c / 2)` piezas completas más como máximo una media (`c mod 2 = 1`). `c = 2` vale **una pieza**, nunca dos medias.
5. **Subtotal:**
   - pieza: `floor(c / 2) * precio_pieza + (c mod 2 = 1 ? precio_media_pieza(precio_pieza) : 0)`;
   - unidad: `cantidad * precio_unitario`.

   Con pieza = 21 (media = 11): `c=1 → 11`, `c=2 → 21` (no 22), `c=3 → 32`. Con pieza = 10.000 (media = 5.000): `c=1 → 5.000`, `c=2 → 10.000`, `c=3 → 15.000`, `c=5 → 25.000`.
6. **Decimales y precio 0:** el precio de pieza o unidad admite como máximo 2 decimales; más de 2 se rechaza (sin redondear ni truncar). Se mantiene la validación mínima `>= 0`.
7. **Snapshot histórico de venta.** Cada ítem de venta `pieza` conserva el **precio de media pieza aplicado** al momento de la venta. Para reconstruir una venta histórica se usa ese valor guardado; **no** se vuelve a derivar con esta ADR, de modo que la venta sigue siendo reproducible aunque la regla cambie en el futuro. El snapshot falla cerrado:
   - ítem `pieza` sin precio de media aplicado → inválido;
   - ítem `unidad` con precio de media → inválido (el campo no aplica y no se ignora en silencio).
8. **Persistencia del prototipo (`localStorage` v4).** Las siete claves operativas pasan de `v3` a `v4` con **inicialización limpia**:
   - `distribuidora_productos_demo_v4`
   - `distribuidora_jornadas_demo_v4`
   - `distribuidora_ventas_demo_v4`
   - `distribuidora_cobros_demo_v4`
   - `distribuidora_movimientos_demo_v4`
   - `distribuidora_retornos_demo_v4`
   - `distribuidora_camiones_demo_v4`

   Se mantienen `distribuidora_clientes_demo_v2` y `distribuidora_sesion_demo_v1`. **No** se lee, copia, reinterpreta ni borra `v3` ni `v2`. Las claves viven en una única definición compartida (`apps/web/src/data/clavesStorage.ts`).

## 3. Alternativas descartadas

- **Mantener ADR-002 (dos precios independientes):** reemplazada por decisión del dueño.
- **`Math.round(precio_pieza / 2)` sobre pesos:** opera en punto flotante sobre un valor en pesos; la regla debe resolverse sobre centavos enteros.
- **Media con centavos (sin redondear al peso):** la decisión fija pesos enteros.
- **Re-derivar la media en ventas históricas:** rompe la reproducibilidad si la regla cambia.
- **Reutilizar o migrar `v3`:** los productos `v3` traen un precio de media configurado que esta decisión elimina; se inicializa limpio.

## 4. Relación con ADR-002

ADR-002 queda **SUPERADA** e **histórica**. Esta ADR la reemplaza **solo** en:

- los dos precios independientes (ADR-002 §2.1, §2.2 y §2.8, en lo que respecta a exigir precio de media pieza configurable);
- el versionado `localStorage` v3 (ADR-002 §2.10), reemplazado por v4.

Lo demás de ADR-002 (cantidad canónica, presentación comercial, decimales, centavos enteros, implementación única del subtotal, historial de precios aplicados) **sigue vigente** y está reiterado en §2.

## 5. Consecuencias

- `BLUEPRINT.md` v1.9 y `docs/PRD.md` v0.8 reflejan la decisión.
- `apps/web/src/domain/precios.ts`: `precio_media_pieza` deriva la media en centavos enteros; `subtotal_linea_historica` usa el snapshot y falla cerrado.
- La pantalla de productos muestra la media derivada en solo lectura.
- Los datos demo operativos `v3` quedan sin uso y sin borrarse.

## 6. Fuera de esta decisión

- Esquema SQL definitivo de `productos` y `venta_items` (forma exacta del historial de precios).
- Exigir precio `> 0`.
- Precio de lista contra precio aplicado y descuentos del vendedor (`PROPUESTA NO APROBADA`, `BLUEPRINT.md` §7.5).
- Autoventa (pantalla de registro de ventas): sin cambios en esta decisión.
- Cualquier ADR en estado `propuesta`, incluida ADR-001, que sigue **PROPUESTA — NO APROBADA**.
