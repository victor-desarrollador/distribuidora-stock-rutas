# ADR-002 — Precios comerciales independientes de pieza y media pieza

**Fecha:** 20/10/2026
**Estado:** SUPERADA por [ADR-003](003-precio-derivado-media-pieza.md) (21/10/2026) en la política de precio de media pieza y en el versionado `localStorage` v3. Fue APROBADA el 20/10/2026 (aprobación humana explícita del dueño del proyecto).
**Versión:** 1.0

> **Documento histórico.** Se conserva sin cambios de contenido. El precio de media pieza ya **no** es configurable: se deriva del precio de pieza (ADR-003). Las claves operativas vigentes son `_demo_v4`. Lo no reemplazado (cantidad canónica, presentación comercial, decimales, centavos enteros, implementación única del subtotal, historial de precios aplicados) sigue vigente y está reiterado en ADR-003.

> **Nota posterior (25/10/2026).** [ADR-005](005-fiambres-por-peso-gramos.md) reemplaza el modelo pieza/media pieza: la cantidad canónica en medias piezas y la presentación comercial «N piezas + 1 media» tampoco siguen vigentes. Esta ADR es histórica en su totalidad y no conserva autoridad normativa; ADR-003 también quedó REEMPLAZADA por ADR-005. Los principios generales que siguen vigentes rigen por `BLUEPRINT.md` §7.1 y ADR-005 §2.

> **Alcance.** Esta ADR autoriza el modelo de precios del **prototipo frontend** (`apps/web/`). **No aprueba** tablas, columnas, tipos ni restricciones SQL definitivas, ni migraciones, ni Supabase.

---

## 1. Contexto

Los fiambres se venden por pieza o media pieza (`BLUEPRINT.md` §7.1) y el stock se guarda como entero en medias piezas (cantidad canónica). El Blueprint v1.7 suponía que el precio de la media pieza era la mitad del de la pieza "salvo que se defina un precio propio" y dejaba abierto, en §15, "exactamente mitad o precio especial; reglas de redondeo en dinero".

El prototipo calculaba `subtotal = cantidad * precio`. Para fiambres eso es incorrecto: `cantidad` está en medias piezas y `precio` es el de la pieza completa. El valor de carga de Jornadas (commit `c188b8230029166c508dfb801b0a92c68b789263`, ya publicado en `origin/feat/jornadas-medias-piezas`) quedaba inflado por dos para fiambres.

## 2. Decisión

1. Un fiambre vendido por pieza tiene **dos precios comerciales independientes**, definidos por el propietario del sistema: **precio de pieza completa** y **precio de media pieza**. **No existe** la regla `precio_media = precio_pieza / 2`.
2. **No existe relación matemática obligatoria** entre ambos precios: no se impone la mitad, ni que la media sea menor o igual que la pieza, ni descuentos automáticos, ni redondeos derivados.
3. **Cantidad canónica y presentación comercial son cosas distintas.**
   - Canónica (stock y persistencia): entero `c` en medias piezas.
   - Comercial: siempre se descompone en `piezas = floor(c / 2)` más como máximo una media (`c mod 2 = 1`). Nunca "N medias".
4. Subtotal de una línea:
   - pieza: `floor(c / 2) * precio_pieza + (c mod 2 = 1 ? precio_media_pieza : 0)`;
   - unidad: `cantidad * precio_unitario`.

   Con pieza = 10.000 y media = 6.000: `c=0 → 0`, `c=1 → 6.000`, `c=2 → 10.000`, `c=3 → 16.000`, `c=4 → 20.000`, `c=5 → 26.000`, `c=8 → 40.000`, `c=9 → 46.000`. `c=2` vale **una pieza**, no dos medias.
5. Existe **una única implementación de dominio** del subtotal. Ninguna pantalla copia la fórmula.
6. **Decimales:** los precios admiten **como máximo 2 decimales**. Un precio con más de 2 decimales se **rechaza**: no se redondea, no se trunca y no se normaliza. El prototipo calcula internamente en **centavos enteros**; la base futura usará `numeric(14,2)`, nunca `float`.
7. **Precio 0:** esta ADR no crea una regla nueva. Se mantiene la validación mínima vigente (`>= 0`). Exigir `> 0` sería otra decisión.
8. **Forma de venta:** `unidad` tiene un único precio (unitario) y no admite precio de media pieza. `pieza` exige precio de pieza completa y precio de media pieza.
9. **Historial de venta (prototipo, Opción A):** cada ítem de venta conserva la cantidad canónica, el precio aplicado de pieza o unidad, el precio de media pieza cuando la forma de venta es pieza, y el subtotal, para reconstruir el cobro aunque el producto cambie de precio después. **No** se aprueban columnas SQL definitivas.
10. **Persistencia del prototipo (`localStorage`):** las claves operativas afectadas pasan de `v2` a `v3` con **inicialización limpia**: `distribuidora_productos_demo_v3`, `distribuidora_jornadas_demo_v3`, `distribuidora_ventas_demo_v3`, `distribuidora_cobros_demo_v3`, `distribuidora_movimientos_demo_v3`, `distribuidora_retornos_demo_v3` y `distribuidora_camiones_demo_v3`. Se mantienen `distribuidora_clientes_demo_v2` y `distribuidora_sesion_demo_v1`. **No** se lee, copia, reinterpreta ni borra `v2`. Las claves viven en una única definición compartida.

## 3. Alternativas descartadas

- **Derivar la media como `precio / 2`** (con o sin precio propio opcional): el negocio fija dos precios; el redondeo derivado deja de existir.
- **Cobrar `c` como "c medias":** contradice la decisión (`c=2` vale una pieza).
- **Reutilizar las claves `v2`:** provocaría un reinicio silencioso de datos operativos.
- **Migrar `v2 → v3`:** no hay precio de media pieza que derivar sin inventarlo.
- **Subir solo productos, jornadas y ventas a `v3`:** dejaría cobros, movimientos, retornos y camiones apuntando a registros inexistentes.
- **Unión discriminada `ProductoUnidad | ProductoPieza`:** descartada para este bloque; se usa `precioMediaPieza?` con validación de dominio y de frontera de persistencia.

## 4. Consecuencias

- `BLUEPRINT.md` v1.8 y `docs/PRD.md` v0.7 reflejan la decisión (§7.1, §8, criterios de aceptación y pendientes).
- Un producto de forma `pieza` requiere ambos precios; uno de forma `unidad` no tiene precio de media pieza.
- El prototipo falla cerrado ante cantidades inválidas, precios negativos, `NaN`, `Infinity`, más de 2 decimales, pieza sin precio de media, unidad con precio de media o resultados fuera del entero seguro.
- Los datos demo operativos `v2` quedan sin uso y sin borrarse; el respaldo de `ConfiguracionDemo` exporta todas las claves de la aplicación, también las `v2` viejas.
- Los productos demo reciben precios de media pieza **solo como datos de demostración** (queso cremoso en pieza 12.500/7.000; jamón cocido 12.500/7.500; salame milán 9.800/6.000). Esos valores no implican fórmula ni porcentaje entre precios.

## 5. Fuera de esta decisión

- Esquema SQL definitivo de `productos` y `venta_items` (forma exacta del historial de precios).
- Exigir precio `> 0`.
- Precio de lista contra precio aplicado y descuentos del vendedor (`PROPUESTA NO APROBADA`, `BLUEPRINT.md` §7.5).
- Cualquier ADR en estado `propuesta`, incluida ADR-001.
