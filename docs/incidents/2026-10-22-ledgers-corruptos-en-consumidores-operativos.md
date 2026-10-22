# Ledgers corruptos tratados como vacíos por consumidores operativos

**Fecha:** 22/10/2026
**Estado:** resuelto en el Bloque C del cierre frontend pre-backend
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

## Corrección

- Se expuso el estado discriminado existente de Retornos.
- Los consumidores operativos declaran Ventas, Movimientos o Retornos como dependencias y bloquean su acción cuando corresponde.
- Las validaciones de escritura de Autoventa y Movimientos releen discriminadamente el ledger dependiente en el momento de la operación.
- Rendición presenta `No disponible` para el valor dependiente.
- Se agregaron pruebas unitarias y E2E; no se agregó recuperación, borrado, migración, backend ni una nueva key.

## Prevención

El inventario final de storage y los E2E de ledgers corruptos quedan registrados en `docs/progress-log.md`. La revisión de seguridad y la auditoría independiente deberán hacerse posteriormente sobre el hash concreto del Bloque C.
