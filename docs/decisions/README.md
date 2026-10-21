# Decisiones (ADR)

Una decisión por archivo: `NNN-titulo.md`. Ver `BLUEPRINT.md`, sección 13.

**Solo se implementan decisiones en estado `aprobada`.** Una ADR en estado `propuesta` no autoriza escribir código, migraciones ni pruebas que dependan de ella como si estuviera vigente.

## Índice

| N.º | Título | Versión | Estado |
|---|---|---|---|
| [001](001-rpc-privilegiadas.md) | Puerta de entrada SQL para operaciones privilegiadas | 1.2 | PROPUESTA — NO APROBADA |
| [002](002-precios-independientes-pieza-media.md) | Precios comerciales independientes de pieza y media pieza | 1.0 | SUPERADA por ADR-003 (precio de media pieza y `localStorage` v3); histórica |
| [003](003-precio-derivado-media-pieza.md) | Precio derivado de media pieza | 1.0 | APROBADA |

ADR-001 (v1.2, ronda 3 de correcciones) detalla sus puntos **PENDIENTE DE APROBACIÓN HUMANA** (P1–P20) en su sección 18; las recomendaciones que incluye son **no vinculantes** y no son decisiones vigentes. No existe aprobación humana de ADR-001.

## Plantilla

```
# NNN — Título
Fecha:
Estado: propuesta | aprobada | reemplazada por NNN
Contexto: qué problema hay
Decisión: qué se decidió
Alternativas descartadas: y por qué
Consecuencias: qué cambia en el código / en el Blueprint
```

Cambiar el estado de una ADR a `aprobada` requiere aprobación humana explícita (dueño del proyecto). Un agente no puede aprobar una ADR.
