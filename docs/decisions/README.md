# Decisiones (ADR)

Una decisión por archivo: `NNN-titulo.md`. Ver `BLUEPRINT.md`, sección 13.

**Cada ADR se implementa sólo dentro del alcance que autoriza su estado.** Una ADR en estado `propuesta` no autoriza escribir código, migraciones ni pruebas que dependan de ella como si estuviera vigente. El estado `aprobada para validación controlada` habilita exclusivamente diseño, migraciones y pruebas en local/staging; no habilita producción ni resuelve decisiones técnicas todavía pendientes.

## Índice

| N.º | Título | Versión | Estado |
|---|---|---|---|
| [001](001-rpc-privilegiadas.md) | Puerta de entrada SQL para operaciones privilegiadas | 1.4 | APROBADA PARA VALIDACIÓN CONTROLADA |
| [002](002-precios-independientes-pieza-media.md) | Precios comerciales independientes de pieza y media pieza | 1.0 | SUPERADA por ADR-003 (precio de media pieza y `localStorage` v3); histórica |
| [003](003-precio-derivado-media-pieza.md) | Precio derivado de media pieza | 1.0 | APROBADA |
| [004](004-cobros-jornada-cerrada.md) | Cobros asociados a jornadas cerradas | 1.0 | PROPUESTA — NO APROBADA |

ADR-001 (v1.4) tiene resueltos P1 (Topología D), P19 (gobernanza en dos etapas), P20 (migraciones dependientes de ADR-001 sólo en local/staging) y P5–P7 (un perfil 1:1, una sola empresa y un único rol por usuario; decisión humana del 22/10/2026). P2–P4 y P8–P17 siguen **PENDIENTES DE APROBACIÓN HUMANA** y P18 continúa como decisión futura separada. Su estado intermedio no equivale a aprobación productiva.

## Estados

- `PROPUESTA — NO APROBADA`: no autoriza implementación, migraciones ni pruebas que asuman la decisión como vigente.
- `APROBADA PARA VALIDACIÓN CONTROLADA`: habilita exclusivamente el diseño, las migraciones y las pruebas necesarias en local/staging, dentro de las decisiones ya resueltas. No habilita producción, no autoriza decisiones técnicas pendientes y no equivale a una ADR aprobada productivamente. Exige evidencia de las pruebas requeridas, auditoría independiente y aceptación humana final antes de producción.
- `APROBADA`: decisión aceptada para el alcance productivo indicado por la ADR.
- `REEMPLAZADA`: se conserva como registro histórico y remite a la decisión vigente.

## Plantilla

```
# NNN — Título
Fecha:
Estado: propuesta | aprobada para validación controlada | aprobada | reemplazada por NNN
Contexto: qué problema hay
Decisión: qué se decidió
Alternativas descartadas: y por qué
Consecuencias: qué cambia en el código / en el Blueprint
```

Cambiar el estado de una ADR a `aprobada para validación controlada` o `aprobada` requiere aprobación humana explícita (dueño del proyecto). Un agente no puede aprobar una ADR.
