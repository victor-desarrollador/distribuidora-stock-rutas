# Requisito — Migración de unidades del prototipo (sin `kg`, piezas en medias piezas)

**Fecha:** 18/10/2026
**Rama:** `refactor/migrar-unidades-prototipo`
**Estado:** **requisito documental**. Define qué hay que migrar y cómo se aceptará. **No autoriza** todavía la modificación de código: la implementación queda **pendiente de autorización humana**. La estrategia de versionado de `localStorage` (`v1 → v2`, §7-bis) es una **decisión humana aprobada** (18/10/2026).
**Fuente de verdad:** `BLUEPRINT.md` v1.6 §2 y §7.1 (decisión humana de unidades), §7.4, §12; `AGENTS.md` §3 y §5; `docs/PRD.md` (RF-01, §9). Si algo de este documento contradice el Blueprint, manda el Blueprint.

> **Nota posterior (25/10/2026). Histórico en lo referido a pieza/media pieza y `kg`.** [ADR-005](../decisions/005-fiambres-por-peso-gramos.md) reemplaza la regla de unidades de este requisito: los fiambres se venden por peso (entrada en kg con hasta 3 decimales; visualización en kg con 3 decimales fijos; gramos enteros como representación canónica objetivo) y `kg` vuelve a ser una unidad comercial válida para fiambres. Los objetivos «sin `kg`» y «fiambres en medias piezas» de este documento **ya no son requisitos**. Sigue vigente, como principio, que un cambio de semántica de cantidades del prototipo no reinterpreta datos persistidos: versión nueva de las claves, inicialización limpia y ninguna migración automática (§7 y §7-bis). El nuevo requisito de migración del prototipo se define en la tarea que implemente ADR-005. El contenido de abajo se conserva sin cambios.

> **Aviso de alcance.** Este documento **no implementa** nada ni amplía otras decisiones. ADR-001 está **APROBADA PARA VALIDACIÓN CONTROLADA**, pero este requisito de unidades no habilita Supabase, SQL, migraciones, RLS, RPC ni cambios de seguridad (§10).

---

## 1. Objetivo

Alinear la representación de unidades del prototipo de demostración (`apps/web/src/`) con la **decisión humana de unidades** ya confirmada:

- **Lácteos** se venden y controlan por **cantidad/unidad entera**.
- **Fiambres** se venden y controlan **únicamente por pieza o media pieza**.
- La representación canónica de los fiambres es **siempre un entero en medias piezas**.
- **No existe `kg` en Fase 1.**

El prototipo legacy **no cumple** esta regla: todavía contiene `kg` y representa las piezas como **piezas enteras**. Este requisito deja definido **qué migrar, qué borrar, qué riesgo existe y cómo se verificará**, sin ejecutar la migración.

---

## 2. Estado actual (prototipo legacy)

Verificado en el código actual, no inferido:

- **Tipo de unidad con `kg`.** `apps/web/src/data/mockProductos.ts` define `export type UnidadMedida = "unidad" | "pieza" | "kg";`. El mismo literal `"unidad" | "pieza" | "kg"` está **duplicado** en `mockJornadas.ts`, `mockVentas.ts` y `mockRetornos.ts`.
- **`kg` con camino funcional.** Las pantallas `Jornadas.tsx`, `Autoventa.tsx`, `Movimientos.tsx`, `Retornos.tsx` y `Productos.tsx` tratan `kg` de forma especial (mapas de unidades, `step` decimal `0.001`, hasta 3 decimales). Los hooks `useProductos`, `useJornadas`, `useVentas`, `useMovimientos` y `useRetornos` también manejan el literal.
- **Piezas como enteros.** Los fiambres se guardan como **piezas enteras** (`Queso cremoso` = 35, `Jamón cocido` = 18, `Salame milán` = 6) y las pantallas exigen `Number.isInteger` con `step="1"`: **no admiten `0.5`**. La unidad mínima **no** es la media pieza.
- **Datos demo contradictorios con la categoría (resuelto por decisión humana).** El demo tiene un único `Queso cremoso` con `categoria: "Lácteos"` y `unidadMedida: "pieza"` — combinación **no admitida**. La decisión humana (18/10/2026) es **separar** el producto demo en dos (ver §4-bis): `Queso cremoso en bote` (Lácteos/`unidad`) y `Queso cremoso en pieza` (Fiambres/`pieza`). El dato demo actual debe reemplazarse al migrar.
- **`Rendicion.tsx` (estado intermedio ya iniciado).** En la línea base de esta rama, `Rendicion.tsx` **ya no maneja `kg`** (se quitó en el refactor de dominio de rendición). Sin embargo, sigue marcando los productos por pieza como **`pieza_legacy` no conciliable** y **bloquea el cierre** hasta migrar a medias piezas (`apps/web/src/pages/rendicion_calculos.ts`, constante que exige la migración). Es decir: `Rendicion` está **parcialmente migrada**; el resto del prototipo, no.
- **Claves demo de `localStorage` en `v1`.** Varias claves de datos demo terminan en `_v1`: `distribuidora_productos_demo_v1`, `distribuidora_jornadas_demo_v1`, `distribuidora_ventas_demo_v1`, `distribuidora_movimientos_demo_v1`, `distribuidora_retornos_demo_v1`, `distribuidora_cobros_demo_v1`, `distribuidora_camiones_demo_v1`, `distribuidora_clientes_demo_v1`. `ConfiguracionDemo.tsx` las enumera para el reinicio de datos demo.

---

## 3. Estado objetivo

1. `UnidadMedida` deja de incluir `"kg"`: queda `"unidad" | "pieza"`.
2. **Lácteos** (`categoria: "Lácteos"`) → `unidadMedida: "unidad"`, cantidades **enteras** (nunca fracciones).
3. **Fiambres** (`categoria: "Fiambres"`) → `unidadMedida: "pieza"`, cantidades **enteras en medias piezas** como representación canónica.
4. **Ningún producto** se carga, vende, cuenta ni rinde por kilogramo. Se elimina toda rama de código que trate `kg` como unidad válida.
5. Sin datos demo en `kg` y sin piezas expresadas como piezas enteras: los **datos demo de fiambres** quedan **expresados directamente en medias piezas**.
6. La equivalencia **no es silenciosa**: 1 pieza = 2 medias piezas y 1/2 pieza = 1 media pieza; los datos demo se escriben **ya** en la representación canónica y **no** se migran valores v1 (§7-bis).
7. **No existe** ningún producto demo que combine `Lácteos` + `pieza` ni `Fiambres` + `unidad`.

---

## 4. Matriz de unidades (objetivo)

| Categoría | Forma de venta (`unidadMedida`) | Unidad mínima / representación canónica | Ejemplo |
|---|---|---|---|
| **Lácteos** | `unidad` | **Entero** (unidad entera) | 3 yogures = `3`; 1 leche = `1` |
| **Fiambres** | `pieza` | **Entero en medias piezas** (1 pieza = 2 medias piezas; 1/2 pieza = 1 media pieza) | "4 piezas + 1 media" = `9` medias piezas |
| *(eliminado)* | ~~`kg`~~ | **No existe en Fase 1** | — |

Reglas derivadas:

- Toda cantidad es un **entero** en su unidad mínima. **Nunca decimales.**
- `0.5` en la interfaz de un fiambre se interpreta como **1 media pieza**, no como `0.5` interno.
- No se admite ninguna otra unidad de venta en Fase 1.

### 4-bis. Productos demo de referencia (decisión humana aprobada)

Productos demo de queso cremoso, separados por categoría y unidad. **No es una regla sobre nombres de producto**: es un ejemplo de **consistencia categoría ↔ unidad**.

| Producto demo | Categoría | `unidadMedida` | Cantidad canónica |
|---|---|---|---|
| `Queso cremoso en bote` (untable) | **Lácteos** | `unidad` | **Entero** |
| `Queso cremoso en pieza` | **Fiambres** | `pieza` | **Entero en medias piezas** |

- **Prohibido:** `Lácteos` + `pieza` y `Fiambres` + `unidad`.
- El resto de los productos demo (yogur, leche, jamón cocido, salame milán, etc.) se alinean a la misma regla: **Lácteos → `unidad` entera**; **Fiambres → `pieza` en medias piezas**.

---

## 5. Eliminación de `kg`

- **Tipo:** quitar `"kg"` de `UnidadMedida` (`mockProductos.ts`) y de los literales duplicados en `mockJornadas.ts`, `mockVentas.ts`, `mockRetornos.ts`.
- **Datos:** quitar todo producto/ítem demo con `unidadMedida: "kg"`.
- **UI:** eliminar el `<option value="kg">Kilogramo</option>` y las ramas de `step` decimal (`0.001`) de `Productos.tsx`, `Jornadas.tsx`, `Autoventa.tsx`, `Movimientos.tsx`, `Retornos.tsx`; eliminar los mapas de etiqueta `kg`.
- **Validación:** ninguna ruta de validación debe aceptar `kg` ni cantidades decimales.
- **Fuente de la regla:** `BLUEPRINT.md` §2 y §7.1 — «No existe `kg` en Fase 1».

---

## 6. Archivos afectados

Núcleo (los 10 del alcance de esta migración):

| # | Archivo | Qué cambia |
|---|---|---|
| 1 | `apps/web/src/data/mockProductos.ts` | `UnidadMedida` sin `kg`; datos demo alineados a categoría/unidad (fiambres en medias piezas). |
| 2 | `apps/web/src/data/mockJornadas.ts` | Tipo de unidad sin `kg`; cantidades de carga demo coherentes con la unidad mínima. |
| 3 | `apps/web/src/data/mockVentas.ts` | Tipo de unidad sin `kg`; cantidades de venta demo coherentes. |
| 4 | `apps/web/src/data/mockMovimientos.ts` | Tipo de unidad sin `kg`; cantidades de movimiento demo coherentes. |
| 5 | `apps/web/src/data/mockRetornos.ts` | Tipo de unidad sin `kg`; cantidades de retorno demo coherentes. |
| 6 | `apps/web/src/pages/Jornadas.tsx` | Quita ramas `kg`; valida enteros por unidad mínima. |
| 7 | `apps/web/src/pages/Autoventa.tsx` | Quita ramas/`step` de `kg`; medias piezas para fiambres. |
| 8 | `apps/web/src/pages/Movimientos.tsx` | Quita ramas `kg`; valida enteros/medias piezas. |
| 9 | `apps/web/src/pages/Retornos.tsx` | Quita ramas `kg`; valida enteros/medias piezas. |
| 10 | `apps/web/src/pages/Rendicion.tsx` | Cierra la migración: deja de usar `pieza_legacy` en cuanto la representación sea medias piezas. |

Archivos de apoyo que la migración arrastra (fuera del núcleo, pero deben quedar consistentes):

- Hooks: `apps/web/src/hooks/useProductos.ts`, `useJornadas.ts`, `useVentas.ts`, `useMovimientos.ts`, `useRetornos.ts`.
- `apps/web/src/pages/Productos.tsx` (alta/edición de productos: opción y `step` de `kg`).
- `apps/web/src/pages/ConfiguracionDemo.tsx` (claves demo; ver §7).
- `apps/web/src/pages/rendicion_calculos.ts` (dominio de rendición; estado `pieza_legacy`).

---

## 7. Riesgo de reinterpretar datos existentes de `localStorage`

**Riesgo central.** El prototipo persiste datos demo en `localStorage` (claves `distribuidora_*_demo_v1`). Si se cambia el **significado** de las cantidades **sin migrar los datos existentes**, un navegador con datos viejos reinterpretaría los números:

- Un fiambre guardado como **`35`** (piezas enteras) sería leído por el código nuevo como **`35` medias piezas** = **17,5 piezas**. Es una **reinterpretación silenciosa** de los datos: el número no cambia, el significado sí.
- Los productos que hoy tienen `unidadMedida: "kg"` quedarían con una unidad **inexistente** en el tipo nuevo.

**Impacto.** Diferencias de stock y rendición calculadas sobre datos reinterpretados; datos demo engañosos durante las pruebas. No afecta datos productivos (no hay backend todavía), pero **contamina la validación de la migración**.

**Mitigación aprobada (ver §7-bis):**

1. **No reutilizar los datos v1 como si fueran v2.** Se separan por versión de clave (`_demo_v1` ≠ `_demo_v2`).
2. **Inicialización limpia de v2**: al no existir la clave `_v2`, cada hook arranca desde los datos iniciales (`mock*`) **ya normalizados**; `ConfiguracionDemo` regenera v2 sin mezclar v1/v2.
3. **Sin migración automática (decisión humana aprobada):** no se aplica `medias = piezas_enteras * 2` sobre datos existentes ni se infiere nada por el número crudo. v1 queda **sin reinterpretar**.

### 7-bis. Estrategia aprobada: versionar las claves demo de `v1` a `v2` — **DECISIÓN HUMANA APROBADA (18/10/2026)**

> **ESTADO: DECISIÓN HUMANA APROBADA.** El versionado `v1 → v2` con **reinicialización** de los datos demo y **sin migración automática** está aprobado. **No se implementa todavía**: la ejecución requiere el plan humano autorizado correspondiente (`AGENTS.md` §2 y §6).

**Motivo.** Los valores legacy de `pieza` están expresados en **piezas enteras**; reutilizar el mismo número en el modelo nuevo lo **reinterpretaría como medias piezas**: legacy `18` = 18 piezas; nuevo `18` = 18 medias = **9 piezas**. Por eso **no** se reutiliza ningún valor de v1.

**Estrategia aprobada:**

1. **Nuevas claves demo `v2`:** cambiar el sufijo `_demo_v1` → `_demo_v2` en los hooks (`useProductos`, `useJornadas`, `useVentas`, `useMovimientos`, `useRetornos`, `useCobros`, `useCamiones`, `useClientes`) y en `ConfiguracionDemo.tsx`.
2. **Inicialización limpia:** al no existir la clave `_v2`, cada hook arranca desde los datos iniciales (`mock*`), que estarán **ya normalizados** al modelo canónico (medias piezas para fiambres; unidad entera para lácteos; sin `kg`).
3. **Datos demo ya en el modelo canónico:** los `mock*` se reescriben antes/junto con la implementación para que la carga inicial de v2 sea coherente, incluida la separación de `Queso cremoso` (§4-bis).
4. **Sin migración automática desde v1:** no se convierte ni se reinterpreta ningún dato v1.
5. **v1 no se elimina ni se reinterpreta durante esta tarea:** las claves `_v1` quedan **intactas** y **no son leídas** por el código v2.

**Efecto buscado:** **cero reinterpretación silenciosa** — un dato v1 nunca se lee con semántica v2; v2 siempre arranca de datos demo normalizados.

**Fuera de esta decisión (no se implementa ahora):** si en el futuro se borran las claves `_v1` y si `ConfiguracionDemo` debe exponer una acción explícita para limpiarlas.

---

## 8. Criterio de aceptación

La migración se considerará aceptada cuando, **sobre el código autorizado**:

1. `UnidadMedida` **no** contiene `"kg"`; **no queda ningún `"kg"`** en tipos, datos ni UI objetivo (ninguna pantalla, hook o dato demo ofrece, muestra, valida o persiste `kg`).
2. **No queda ningún producto demo `Lácteos` + `pieza`.**
3. **No queda ningún producto demo `Fiambres` + `unidad`.**
4. Los **datos de fiambres se expresan en medias piezas enteras** (1 pieza = 2); los **lácteos**, en **unidad entera**.
5. La interfaz permite ingresar **media pieza** para fiambres (`0.5` → `1` media pieza) y **rechaza** cantidades no enteras en `unidad` y no múltiplos de media pieza en `pieza`.
6. Al **cerrar la rendición**, un fiambre representado en medias piezas **no** se marca `pieza_legacy` y **no** bloquea el cierre por unidad; `Rendicion` deja de necesitar el bloqueo legacy.
7. **`localStorage` v2 se inicializa con datos coherentes** con el modelo canónico (claves `_demo_v2`, sin mezcla con v1).
8. **Ningún valor legacy v1 se reutiliza como cantidad v2**: no hay migración automática ni reinterpretación (§7-bis).
9. Se cumple el punto 5 del Blueprint: «nada se da por terminado sin prueba» — con los tests de §9 en verde.

---

## 9. Tests requeridos

**Unitarios (Vitest, `apps/web/src/**/*.test.ts`):**

- Conversión de fiambres: `1 pieza → 2 medias piezas`, `0.5 pieza → 1 media pieza`, `0 → 0`, `4 piezas + 1 media → 9`.
- Rechazo de cantidades no válidas: decimales en `unidad`, no múltiplos de media pieza en `pieza`, negativos, `NaN`, `Infinity`.
- `UnidadMedida` no incluye `kg` (verificación de tipos/compilación).
- Rendición: una fila de fiambre en medias piezas **no** produce estado `pieza_legacy` ni bloquea el cierre; `kg` y unidades no soportadas siguen bloqueando (sin camino funcional).
- Datos demo: ningún `mock*` contiene `unidadMedida: "kg"` ni cantidades fraccionarias donde no corresponda.
- Datos demo: ningún producto combina `Lácteos` + `pieza` ni `Fiambres` + `unidad`; los fiambres quedan en **medias piezas enteras**.

**De interfaz / E2E (Playwright, cuando el cambio de UI lo justifique):**

- Carga de camión con "4 piezas + 1 media" de un fiambre: se guarda `9` (medias piezas).
- Alta de producto: **no** existe la opción `kg`; los lácteos solo admiten enteros.
- Venta de media pieza de un fiambre descuenta exactamente `1` media pieza.

**Verificación del versionado de datos (estrategia aprobada, §7-bis):**

- Con datos v1 presentes, el código nuevo **no** los lee ni los reinterpreta; v2 arranca con datos demo normalizados.
- Ningún valor legacy v1 se reutiliza como cantidad v2.

---

## 10. Fuera de alcance

Este requisito **no** toca, y la migración **no debe** incluir:

- **Supabase**, backend, base de datos.
- **SQL**, funciones y **RPC**.
- **Migraciones** (de base de datos) ni `supabase/migrations/`.
- **RLS**, políticas, roles y **grants**.
- **ADR-001** (este requisito no la implementa ni cambia su estado vigente de **APROBADA PARA VALIDACIÓN CONTROLADA**).
- Reglas de negocio marcadas como propuestas no aprobadas (stock negativo, anulaciones, descuentos, retiro que excede el saldo, vencimientos por partida).
- El modelo de datos propuesto del Blueprint §8.

Tampoco autoriza, por sí solo, **modificar código**: la implementación requiere el plan humano autorizado correspondiente (`AGENTS.md` §2 y §6).

---

## 11. Bloqueos y estado

- **Implementación pendiente de autorización:** este documento es una definición; **no** autoriza escribir código todavía.
- **Versionado de datos:** la estrategia §7-bis (`localStorage` v1 → v2, con inicialización limpia y **sin migración automática**) es una **decisión humana aprobada** (18/10/2026); su ejecución queda pendiente del plan autorizado.
- **Producto demo:** la separación de `Queso cremoso` (§4-bis) es una **decisión humana aprobada**.
- **ADR-001:** sin cambios por este requisito; estado vigente **APROBADA PARA VALIDACIÓN CONTROLADA**. P1/P19/P20, P2–P4 y P5–P7 están resueltas, P8–P17 siguen pendientes y P18 es una decisión futura separada.
- **(Histórico, superado por la viñeta siguiente) Precios y `localStorage` v3 (ADR-002, aprobada 20/10/2026; hoy superada por ADR-003):** el modelo de precios independientes de pieza y media pieza lleva las claves operativas del prototipo (`productos`, `jornadas`, `ventas`, `cobros`, `movimientos`, `retornos`, `camiones`) de `_demo_v2` a `_demo_v3`, con inicialización limpia y sin leer, copiar, reinterpretar ni borrar `v2`. `clientes` queda en `_demo_v2` y la sesión en `_demo_v1`. Esto **no** modifica la estrategia §7-bis (v1 → v2), que se mantiene.
- **Precio derivado de media pieza y `localStorage` v4 (ADR-003, aprobada 21/10/2026; supera a ADR-002 en la política de precio de media):** el precio de media pieza deja de ser configurable (mitad del precio de pieza, redondeada al peso entero, `.50` sube, calculada en centavos enteros). Las siete claves operativas pasan de `_demo_v3` a `_demo_v4` con inicialización limpia, sin leer, copiar, reinterpretar ni borrar `v3` ni `v2`: `distribuidora_productos_demo_v4`, `distribuidora_jornadas_demo_v4`, `distribuidora_ventas_demo_v4`, `distribuidora_cobros_demo_v4`, `distribuidora_movimientos_demo_v4`, `distribuidora_retornos_demo_v4`, `distribuidora_camiones_demo_v4`. Se mantienen `distribuidora_clientes_demo_v2` y `distribuidora_sesion_demo_v1`. La cantidad canónica en medias piezas no cambia.
