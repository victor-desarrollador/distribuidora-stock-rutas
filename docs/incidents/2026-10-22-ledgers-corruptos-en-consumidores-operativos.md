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
- La auditoría de C detectó que Jornadas seguía usando el snapshot de Retornos al preparar una carga, Rendición seguía usando snapshots de Ventas/Cobros/Movimientos al cerrar y faltaban pruebas automáticas de esas defensas productivas (C-1/C-2/C-3).
- El Bloque D agregó la relectura de Retornos dentro de `guardarPreparacion` y reconstruye disponibilidad con esa lectura actual.
- El Bloque D agregó las relecturas discriminadas de Ventas, Cobros y Movimientos dentro de `confirmarCierre`; las filas de mercadería, caja, diferencias y valores de cierre se reconstruyen con esos datos actuales.
- Se agregaron seis E2E TOCTOU que corrompen cada dependencia después del montaje y ejercitan las acciones reales de Autoventa, Movimientos, Jornadas y Rendición. Verifican que no haya persistencia y que el raw corrupto permanezca intacto.
- No se agregó recuperación, borrado, migración, backend ni una nueva key. Las correcciones quedan pendientes de auditoría independiente sobre el hash concreto de D.

## Prevención

El inventario de storage y las verificaciones quedan registrados en `docs/progress-log.md`. La revisión transversal de seguridad y la auditoría independiente deberán evaluar el hash concreto del Bloque D. **ADR-001 continúa PROPUESTA — NO APROBADA**; el backend no se inició y no hubo push, merge ni deploy.
