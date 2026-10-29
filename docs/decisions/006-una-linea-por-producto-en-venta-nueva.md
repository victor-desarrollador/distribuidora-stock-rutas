# ADR-006 — Una línea por producto en cada venta nueva

**Fecha:** 29/10/2026
**Estado:** APROBADA (aprobación humana explícita del dueño del proyecto, 29/10/2026). La decisión funcional se tomó el 28/10/2026, durante la corrección del hallazgo AUD-B3-01; esta ADR la formaliza y la aprueba.
**Versión:** 1.0
**Relación:** complementa a [ADR-005](005-fiambres-por-peso-gramos.md) (§2.3.3, D-R1) sin modificarla.

> **Alcance.** Esta ADR fija una restricción estructural sobre los documentos de venta **nuevos**. No modifica D-R1 ni ninguna otra decisión de ADR-005, no reinterpreta ni migra datos históricos, no define política de precios ni descuentos y no autoriza SQL, migraciones, RPC, RLS, grants ni producción. No modifica ADR-001 ni su estado (**APROBADA PARA VALIDACIÓN CONTROLADA**).

---

## 1. Contexto

ADR-005 §2.3.3 (D-R1) fija que **cada línea `peso` se redondea una sola vez** al peso entero más cercano (empate 0,50 hacia arriba) y que el total del documento es la suma de los importes ya redondeados de cada línea, sin recalcularlos.

Como el redondeo ocurre **por línea**, un documento que admite varias líneas del mismo producto permite alterar el importe total partiendo la misma mercadería en líneas más chicas. El stock descontado es el mismo; el importe, no. Reproducción sobre la frontera de escritura del prototipo (hallazgo AUD-B3-01, 28/10/2026):

| Misma mercadería | Líneas | Total aceptado |
|---|---|---|
| 1 kg a $499,99/kg | 1 línea de 1000 g | **$500** |
| 1 kg a $499,99/kg | 1000 líneas de 1 g (cada una $0,49999 → $0) | **$0** |
| 1 kg a $500,00/kg | 1000 líneas de 1 g (cada una $0,50 → $1) | **$1000** |

Ninguna validación de importe lo detectaba: cada línea cumple D-R1 por separado y el total es exactamente la suma de esas líneas. La UI no producía esas ventas, pero una llamada directa a la frontera de escritura sí.

## 2. Decisión

Para **todo documento de venta nuevo**:

1. El `productoId` es **único** dentro de `items`.
2. Dos o más líneas con el mismo `productoId` **invalidan** la venta completa. La venta se rechaza antes de persistirse: no se consolida automáticamente, no se corrige y no se acepta parcialmente.
3. La regla aplica **cualquiera sea la unidad de medida** (`unidad` o `peso`), y también cuando dos líneas del mismo `productoId` declaran unidades distintas.
4. La cantidad de un producto en una venta se expresa en **una sola línea** (unidades enteras o gramos enteros, ADR-005 §2.2).

### 2.1 Relación con los ejemplos de ADR-005

Los ejemplos de ADR-005 y de `BLUEPRINT.md` con varias líneas `peso` en un mismo documento (por ejemplo, «dos líneas de $1.543,40 exactos dan $1.543 + $1.543 = $3.086») ilustran cómo se suman los importes redondeados por línea. **No autorizan** líneas repetidas del mismo `productoId` en una venta nueva: desde la aprobación de esta ADR, en una venta nueva esas líneas corresponden a productos distintos. D-R1 no cambia.

### 2.2 Históricos

- La regla **no** se aplica retroactivamente. La validación de lectura y reconstrucción de documentos históricos (`venta_valida` en el prototipo) no exige unicidad de `productoId`.
- Un documento histórico con líneas repetidas sigue siendo válido si su estructura y sus importes son válidos, y se reconstruye desde sus valores almacenados (cantidad, precio aplicado e importe por línea), **sin recalcularlos ni migrarlos** (ADR-005 §2.3.4; `BLUEPRINT.md` §7.1, «Historial»).
- Su consumo de stock sigue contando por producto, como la suma de todas sus líneas.

### 2.3 Stock

La validación de stock de una venta nueva (`validar_stock_venta` en el prototipo) **conserva la agregación de cantidades por `productoId`** como defensa en profundidad: suma por producto las líneas del pedido y las salidas registradas antes de comparar con lo cargado, aunque la regla de §2 ya impida líneas repetidas en el documento nuevo. Esta ADR no cambia esa validación.

### 2.4 Notas de papel

Cuando una nota de papel se transcriba al sistema como una **venta nueva** (`BLUEPRINT.md` §7.5), la venta resultante también debe cumplir esta regla. Esto **no** autoriza implementar el flujo de notas de papel, que sigue sujeto a su propia tarea.

## 3. Alternativas descartadas

| Alternativa | Motivo del descarte |
|---|---|
| Consolidar automáticamente las líneas repetidas (sumar cantidades) | Cambia en silencio el documento que se registra; la frontera acepta o rechaza, no reescribe. |
| Restringir sólo las líneas `peso` | La decisión humana fija una regla uniforme por `productoId`; además, el importe final de las líneas `unidad` sigue pendiente (ADR-005 §5) y la regla no debe depender de cómo se resuelva. |
| Redondear sobre la suma por producto en lugar de por línea | Modifica D-R1, que es una decisión aprobada; está fuera de esta ADR. |

## 4. Consecuencias

- **Elimina** la manipulación del importe por fragmentación **dentro de un mismo documento**.
- **No elimina** la fragmentación en **múltiples documentos**: la misma mercadería registrada como muchas ventas separadas (por ejemplo, 1000 ventas de 1 g a $499,99/kg, de $0 cada una) sigue cumpliendo D-R1 venta por venta. Su tratamiento requiere una **decisión comercial o de proceso aparte** y no se resuelve aquí.
- La UI de venta por peso, todavía no implementada, debe construir **como máximo una línea por producto** por venta.
- **Prototipo:** la regla se aplica en la frontera de escritura de ventas nuevas (`venta_nueva_valida` y el guard previo a cualquier lectura en `registroVentas`), con el mensaje «Una venta no puede tener más de una línea del mismo producto. Unificá la cantidad en una sola línea.».
- **SQL/RPC futura:** la regla deberá reflejarse en la RPC de registro de ventas. El diseño concreto queda para esa tarea, con su preámbulo, su plan autorizado y su security review (`AGENTS.md` §2.4).
- **Blueprint:** §7.5 y §12 reflejan esta ADR.

## 5. Fuera de alcance

- Política de precios y descuentos (`BLUEPRINT.md` §7.5, PROPUESTA NO APROBADA).
- Validación del cliente (existencia, estado activo, condición de pago).
- Concurrencia entre pestañas y atomicidad del prototipo `localStorage`.
- RPC, SQL, migraciones y PostgreSQL.
- Cualquier modificación de D-R1 o del resto de ADR-005.
- Fragmentación entre ventas distintas (§4).
- Implementación del flujo de notas de papel (§2.4).
- **Presupuestos** (`BLUEPRINT.md` §7.10): no están alcanzados. Una regla equivalente para presupuestos requiere una decisión separada.

## 6. Pruebas normativas

Casos obligatorios para toda implementación de la frontera de ventas nuevas:

| # | Caso | Resultado exigido |
|---|---|---|
| 1 | Venta nueva con una sola línea válida de un producto | Se acepta (por ejemplo, 1000 g a $499,99/kg → total $500) |
| 2 | Dos o más líneas `peso` del mismo `productoId`, aunque el stock alcance | Se rechaza sin persistir |
| 3 | Dos o más líneas `unidad` del mismo `productoId`, aunque el stock alcance | Se rechaza sin persistir |
| 4 | Dos líneas del mismo `productoId` con unidades distintas | Se rechaza sin persistir |
| 5 | Líneas de productos distintos, todo lo demás válido | Se acepta |
| 6 | Documento histórico con líneas repetidas, estructura e importes válidos | Se lee sin recalcular; su consumo cuenta para el stock |

En los casos 2 a 4 se exige el rechazo, no un mensaje concreto: el caso 4 puede rechazarse antes por la regla de venta mixta.

## 7. Fuentes

- ADR-005 §2.2 (unidad canónica), §2.3.3 (D-R1), §2.3.4 (historial sin recálculo) y §5 (redondeo `unidad` pendiente).
- `BLUEPRINT.md` §7.1 (importe por línea, total = suma, historial), §7.5 (ítems de venta y notas de papel) y §12.
- Hallazgo AUD-B3-01 y decisión humana del 28/10/2026 (`docs/progress-log.md`, entrada «corrección de AUD-B3-01»).
