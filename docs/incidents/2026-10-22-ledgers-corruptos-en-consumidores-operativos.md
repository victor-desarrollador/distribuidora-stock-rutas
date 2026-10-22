# Ledgers corruptos tratados como vacíos por consumidores operativos

**Fecha:** 22/10/2026
**Estado:** corregido en el Bloque D; pendiente de auditoría independiente
**Rama:** `feat/cierre-frontend-pre-backend`

## Descripción

Durante las pruebas de integración se detectó que algunos consumidores usaban lectores públicos que colapsaban corrupción a `[]` como si ese valor fuera una fuente confiable:

- Jornadas calculaba disponibilidad sin distinguir Retornos corruptos.
- Retornos podía presentar su propio ledger corrupto como vacío.
- Movimientos calculaba stock usando Ventas colapsadas a `[]`.
- Autoventa podía calcular o validar stock con Ventas o Movimientos corruptos.
- Rendición mostraba un guion, en lugar de `No disponible`, para “Vendido” con Ventas corruptas.

## Riesgo

Una operación crítica podía quedar habilitada o presentar disponibilidad falsa a partir de un ledger dañado. El raw no se sobrescribía gracias a las fronteras de escritura ya endurecidas, pero la decisión visual/operativa no era completamente fail-closed.

## Detección y correcciones

- El Bloque B quedó históricamente `BLOCKED`: no cubría todas las dependencias operativas y su documentación sobredeclaraba el cierre.
- El Bloque C corrigió H-1 (Autoventa/Movimientos), H-2 (Movimientos/Ventas) y H-3 (Jornadas/Retornos) en la integración visible y en las dos primeras relecturas productivas. También expuso el estado discriminado existente de Retornos y mostró `No disponible` en Rendición.
- La auditoría de C detectó que Jornadas seguía usando el snapshot de Retornos al preparar una carga, Rendición seguía usando snapshots de Ventas/Cobros/Movimientos al cerrar y faltaban pruebas automáticas de esas defensas productivas (C-1/C-2/C-3). **El Bloque C queda registrado como `BLOCKED` histórico**; su alcance declarado en su momento quedó ampliamente superado por los bloques D y E. Ver `docs/progress-log.md`.
- El Bloque D agregó la relectura de Retornos dentro de `guardarPreparacion` y reconstruye disponibilidad con esa lectura actual.
- El Bloque D agregó las relecturas discriminadas de Ventas, Cobros y Movimientos dentro de `confirmarCierre`; las filas de mercadería, caja, diferencias y valores de cierre se reconstruyen con esos datos actuales.
- Se agregaron seis E2E TOCTOU que corrompen cada dependencia después del montaje y ejercitan las acciones reales de Autoventa, Movimientos, Jornadas y Rendición. Verifican que no haya persistencia y que el raw corrupto permanezca intacto.
- No se agregó recuperación, borrado, migración, backend ni una nueva key. Las correcciones quedan pendientes de auditoría independiente sobre el hash concreto de D.

## Correcciones del Bloque E (security review sobre el hash de D)

El security review del Bloque D quedó `BLOCKED` por tres hallazgos M (M-1/M-2/M-3). En el Bloque E se cerraron así:

- **M-1 (catálogos):** Productos, Camiones y Clientes persistían con la lectura capturada al montar: una corrupción aparecida después del montaje podía ser pisada por `persistirCatalogo` porque el effect seguía usando `lecturaInicial.ok === true`. La escritura por effect se reemplazó por una frontera explícita (`actualizarCatalogoPersistido`) que revalida, relee la clave en el momento de la operación y solo escribe si la relectura es confiable; React se actualiza recién después de un `setItem` exitoso.
- **M-2 (jornada como dependencia mutable):** Autoventa (ventas), Movimientos, Cobros con jornada asociada y Retornos ahora revalidan la Jornada vigente contra el lector discriminado de Jornadas justo antes de persistir (corrupto / inexistente / identidad de camión / estado requerido). El lector discriminado de Jornadas se exporta y no se creó ningún parser paralelo. **Decisión pendiente del Blueprint:** si un cobro puede registrarse contra una jornada cerrada; la revalidación de Cobros solo exige que la jornada exista y esté abierta (espejo del contrato vigente de la UI), no se inventó una regla nueva.
- **M-3 (preparación):** `guardarPreparacion` relee Retornos pero calculaba el stock reservado con las Jornadas del render. Nueva frontera `crearPreparacionPersistida`: relee Jornadas y Retornos discriminadamente, recalcula el stock reservado con ambos datos actuales y solo entonces valida y escribe la Jornada.
- **L-1:** `confirmarCierre` de Rendición ahora relee Ventas, Cobros y Movimientos nuevamente después del `window.confirm` y reconstruye el cierre con esa segunda lectura (helper `armarCierre`). Si la ventana cambia entre el confirm y la persistencia, el cierre aborta.
- **L-2:** el Bloque C queda documentado como `BLOCKED` histórico (C-1/C-2/C-3); B sigue `BLOCKED` histórico; D `APPROVED`; E pendiente de auditoría del hash propio.

## Prevención

El inventario de storage y las verificaciones quedan registrados en `docs/progress-log.md`. La revisión transversal de seguridad y la auditoría independiente deberán evaluar el hash concreto correspondiente a cada bloque. **ADR-001 continúa PROPUESTA — NO APROBADA**; el backend no se inició y no hubo push, merge ni deploy.
