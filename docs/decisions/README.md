# Decisiones (ADR)

Una decisión por archivo: `NNN-titulo.md`. Ver `BLUEPRINT.md`, sección 13.

**Cada ADR se implementa sólo dentro del alcance que autoriza su estado.** Una ADR en estado `propuesta` no autoriza escribir código, migraciones ni pruebas que dependan de ella como si estuviera vigente. El estado `aprobada para validación controlada` habilita exclusivamente diseño, migraciones y pruebas en local/staging; no habilita producción ni resuelve decisiones técnicas todavía pendientes.

## Índice

| N.º | Título | Versión | Estado |
|---|---|---|---|
| [001](001-rpc-privilegiadas.md) | Puerta de entrada SQL para operaciones privilegiadas | 1.5 | APROBADA PARA VALIDACIÓN CONTROLADA (anexo §18.4, jornadas y carga de camiones, aprobado el 29/10/2026 para validación controlada; D-2 implementada e integrada a `main` el 29/10/2026, cierre en §18.4.15) |
| [002](002-precios-independientes-pieza-media.md) | Precios comerciales independientes de pieza y media pieza | 1.0 | SUPERADA por ADR-003 (precio de media pieza y `localStorage` v3); histórica |
| [003](003-precio-derivado-media-pieza.md) | Precio derivado de media pieza | 1.0 | REEMPLAZADA por ADR-005 (25/10/2026); histórica, sin autoridad normativa |
| [004](004-cobros-jornada-cerrada.md) | Cobros asociados a jornadas cerradas | 1.0 | PROPUESTA — NO APROBADA |
| [005](005-fiambres-por-peso-gramos.md) | Fiambres por peso y unidad mínima en gramos | 1.1 | APROBADA (no autoriza migraciones ni implementación; D-R1–D-R4 cerradas el 26/10/2026, v1.1) |
| [006](006-una-linea-por-producto-en-venta-nueva.md) | Una línea por producto en cada venta nueva | 1.0 | APROBADA (29/10/2026; formaliza la decisión humana del 28/10/2026, AUD-B3-01; complementa ADR-005 sin modificar D-R1) |
| [007](007-jornadas-y-carga-de-camiones.md) | Jornadas y carga de camiones | 1.0 | APROBADA (29/10/2026; reglas de negocio de apertura, vendedor, corrección, carga, descarga y salida; el anexo §18.4 de ADR-001 fue aprobado el 29/10/2026 para validación controlada, lo que levanta P-3; D-2 está integrada a `main` para validación controlada (ADR-001 §18.4.15); no autoriza más SQL hasta que se autoricen D-1, el arnés y la tarea de implementación) |
| [009](009-migraciones-hacia-adelante-y-rollbacks.md) | Migraciones hacia adelante y estado de los rollbacks manuales | 0.3 | APROBADA PARA VALIDACIÓN CONTROLADA (ratificación humana del 04/11/2026, 23:29 Tucumán; forward-only; prohíbe los rollbacks D-1, D-2, T1 y T2; T1-1, T1-2, T1-3, M-4, N-1, B-1, H-14 y A5 siguen abiertos; no autoriza ejecutar rollbacks, staging ni producción) |
| [010](010-intenciones-persistidas-de-operacion.md) | Intenciones persistidas para recuperar operaciones con resultado desconocido (C-mínima) | 1.0 · enmienda 1.1 | **APROBADA** (v1.0: decisión humana del 06/11/2026; **v1.1: aprobación normativa del 08/11/2026** según los anexos `010-anexo-v1.1-*` — texto aprobado SHA-256 `bd3db993…4b41`, acta `5a17108f…9f68`; prevalece sobre v1.0 solo en lo que modifica expresamente; **adenda A-1 a A-4** (SHA-256 `f359213e…ead78`; acta definitiva `5d569df3…fb27`) aprobada normativamente: prevalece solo sobre los puntos que identifica y aprueba D-IDEM-17; `p_desde` futuro pendiente; **no implementada**; **aprobación exclusivamente normativa**: fija el contrato, los valores y la excepción acotada a P15-stock, registrada en ADR-001 §18.3 y en `BLUEPRINT.md` v2.6. **No autoriza** migraciones, SQL, RPC, permisos, RLS ni frontend; la implementación requiere autorización propia después del cierre de T3-01 y aceptación técnica humana. D-IDEM-13 sigue pendiente. B-01 sigue abierta) |

ADR-001 (v1.5) tiene resueltos P1 (Topología D), P19 (gobernanza en dos etapas), P20 (migraciones dependientes de ADR-001 sólo en local/staging), P5–P7 (un perfil 1:1, una sola empresa y un único rol por usuario; decisión humana del 22/10/2026) y P2–P4 (`public` expuesto y `privado` no expuesto; rol técnico `propietario_rpc`; tablas del owner de migraciones con RLS obligatoria y sin `FORCE` global; decisión humana del 23/10/2026). El 24/10/2026 se resolvieron, para validación controlada, P11 global (`service_role` denegado por defecto sobre objetos de negocio; única excepción vigente, SELECT sobre `public.productos`) y las observaciones O-3 y O-4 (§18.2). P8–P10 y P12–P17 siguen **PENDIENTES DE APROBACIÓN HUMANA** como decisiones globales (para Stock rigen las de §18.3 y, para jornadas y carga de camiones, las de §18.4, aprobadas el 29/10/2026 para validación controlada; P8 y P9 siguen pendientes también allí) y P18 continúa como decisión futura separada. Su estado intermedio no equivale a aprobación productiva; producción sigue bloqueada.

**ADR-009 (v0.3, migraciones hacia adelante y estado de los rollbacks) está APROBADA PARA VALIDACIÓN CONTROLADA desde el 04/11/2026 (23:29, Tucumán).** No modifica ninguna decisión anterior ni autoriza ejecutar rollbacks, staging ni producción. Conserva T1-1, T1-2, T1-3, M-4, N-1, B-1, H-14 y A5 como hallazgos técnicos abiertos (§6 de la ADR) y declara los scripts de `supabase/rollback/` como artefactos experimentales no aptos para staging ni producción.

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
