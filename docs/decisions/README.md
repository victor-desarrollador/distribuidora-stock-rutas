# Decisiones (ADR)

Una decisión por archivo: `NNN-titulo.md`. Ver `BLUEPRINT.md`, sección 13.

**Solo se implementan decisiones en estado `aprobada`.** Una ADR en estado `propuesta` no autoriza escribir código, migraciones ni pruebas que dependan de ella como si estuviera vigente.

## Índice

| N.º | Título | Versión | Estado |
|---|---|---|---|
| [001](001-rpc-privilegiadas.md) | Puerta de entrada SQL para operaciones privilegiadas | 1.1 | propuesta (NO aprobada) |

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
