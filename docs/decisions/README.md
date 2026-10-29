# Decisiones (ADR)

Una decisión por archivo: `NNN-titulo.md`. Ver `BLUEPRINT.md`, sección 13.

**Cada ADR se implementa sólo dentro del alcance que autoriza su estado.** Una ADR en estado `propuesta` no autoriza escribir código, migraciones ni pruebas que dependan de ella como si estuviera vigente. El estado `aprobada para validación controlada` habilita exclusivamente diseño, migraciones y pruebas en local/staging; no habilita producción ni resuelve decisiones técnicas todavía pendientes.

## Índice

| N.º | Título | Versión | Estado |
|---|---|---|---|
| [001](001-rpc-privilegiadas.md) | Puerta de entrada SQL para operaciones privilegiadas | 1.5 | APROBADA PARA VALIDACIÓN CONTROLADA (anexo §18.4, jornadas y carga de camiones, aprobado el 29/10/2026 para validación controlada) |
| [002](002-precios-independientes-pieza-media.md) | Precios comerciales independientes de pieza y media pieza | 1.0 | SUPERADA por ADR-003 (precio de media pieza y `localStorage` v3); histórica |
| [003](003-precio-derivado-media-pieza.md) | Precio derivado de media pieza | 1.0 | REEMPLAZADA por ADR-005 (25/10/2026); histórica, sin autoridad normativa |
| [004](004-cobros-jornada-cerrada.md) | Cobros asociados a jornadas cerradas | 1.0 | PROPUESTA — NO APROBADA |
| [005](005-fiambres-por-peso-gramos.md) | Fiambres por peso y unidad mínima en gramos | 1.1 | APROBADA (no autoriza migraciones ni implementación; D-R1–D-R4 cerradas el 26/10/2026, v1.1) |
| [006](006-una-linea-por-producto-en-venta-nueva.md) | Una línea por producto en cada venta nueva | 1.0 | APROBADA (29/10/2026; formaliza la decisión humana del 28/10/2026, AUD-B3-01; complementa ADR-005 sin modificar D-R1) |
| [007](007-jornadas-y-carga-de-camiones.md) | Jornadas y carga de camiones | 1.0 | APROBADA (29/10/2026; reglas de negocio de apertura, vendedor, corrección, carga, descarga y salida; el anexo §18.4 de ADR-001 fue aprobado el 29/10/2026 para validación controlada, lo que levanta P-3; no autoriza SQL hasta que se autoricen D-1, D-2, el arnés y la tarea de implementación) |

ADR-001 (v1.5) tiene resueltos P1 (Topología D), P19 (gobernanza en dos etapas), P20 (migraciones dependientes de ADR-001 sólo en local/staging), P5–P7 (un perfil 1:1, una sola empresa y un único rol por usuario; decisión humana del 22/10/2026) y P2–P4 (`public` expuesto y `privado` no expuesto; rol técnico `propietario_rpc`; tablas del owner de migraciones con RLS obligatoria y sin `FORCE` global; decisión humana del 23/10/2026). El 24/10/2026 se resolvieron, para validación controlada, P11 global (`service_role` denegado por defecto sobre objetos de negocio; única excepción vigente, SELECT sobre `public.productos`) y las observaciones O-3 y O-4 (§18.2). P8–P10 y P12–P17 siguen **PENDIENTES DE APROBACIÓN HUMANA** como decisiones globales (para Stock rigen las de §18.3 y, para jornadas y carga de camiones, las de §18.4, aprobadas el 29/10/2026 para validación controlada; P8 y P9 siguen pendientes también allí) y P18 continúa como decisión futura separada. Su estado intermedio no equivale a aprobación productiva; producción sigue bloqueada.

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
