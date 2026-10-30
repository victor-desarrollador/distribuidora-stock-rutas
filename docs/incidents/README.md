# Incidentes

Un error por archivo: `AAAA-MM-DD-titulo.md`. Ver `BLUEPRINT.md`, sección 13.

Un incidente solo pasa a `resuelto` con una prueba (test automatizado o verificación manual documentada).

## Índice

| Fecha | Incidente | Estado |
|---|---|---|
| 2026-10-12 | [Lint falla en `main` (errores preexistentes)](2026-10-12-lint-falla-en-main.md) | resuelto |
| 2026-10-22 | [Ledgers corruptos tratados como vacíos por consumidores operativos](2026-10-22-ledgers-corruptos-en-consumidores-operativos.md) | no figura como `resuelto`; estado por bloques registrado en el archivo (F pendiente de auditoría) |
| 2026-10-30 | [Despliegue automático a Production de Vercel sin autorización de deploy](2026-10-30-vercel-production-automatico.md) | abierto (seguimiento hasta definir y verificar las medidas preventivas) |

## Plantilla

```
# Título del incidente
Fecha detectado:
Detectado por:
Qué falló:
Cómo se reproduce (pasos):
Causa raíz:
Archivos modificados:
Solución aplicada:
Pruebas que lo verifican (test o verificación manual documentada):
Cómo evitar que vuelva a pasar:
Estado: abierto | resuelto (solo con prueba)
```
