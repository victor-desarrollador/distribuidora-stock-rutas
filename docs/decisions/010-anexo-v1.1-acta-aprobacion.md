# Acta externa de aprobación normativa — ADR-010 v1.1

Fecha de registro: 2026-11-08. Registrada por Claude-Worf (implementador; **no aprueba**) por instrucción del responsable del proyecto. La sesión no puede verificar criptográficamente la identidad del emisor; se registra la decisión tal como fue comunicada.

## 1. Documento aprobado (vínculo)

| Dato | Valor |
|---|---|
| Nombre | `BORRADOR_ADR010_v1.1_PARA_APROBACION_v0.2.md` |
| Ruta | `/home/tuculandia/Documentos/web/proyectos/tienda virtual/informes-adr010-v1.1/BORRADOR_ADR010_v1.1_PARA_APROBACION_v0.2.md` |
| Versión | ADR-010 **v1.1**, revisión de borrador **v0.2** |
| SHA-256 aprobado | `bd3db99336c0efe317255cca883357bb11e99d51102621a7eb9aba3a00894b41` |
| SHA-256 verificado al registrar | `bd3db99336c0efe317255cca883357bb11e99d51102621a7eb9aba3a00894b41` — **coincide exactamente** |
| Tamaño | 74263 bytes (730 líneas) |
| Borrador anterior (conservado, no aprobado) | `BORRADOR_ADR010_v1.1_PARA_APROBACION.md`, SHA-256 `013daea4e7ef456dd0bbfb1c412148e7fcf1e68004e51d241f0936b57208fb4e` |

El borrador aprobado **no se modificó**: solo se le restringió el permiso a lectura (modo 400) para preservarlo.

## 2. Decisión humana (reproducción literal)

> El responsable del proyecto aprobó normativamente ADR-010 v1.1 según el borrador v0.2, SHA-256:
>
> bd3db99336c0efe317255cca883357bb11e99d51102621a7eb9aba3a00894b41
>
> La aprobación comprende:
> - Paquetes H y C.
> - D-IDEM-5b/5c.
> - Extensión limitada de D-IDEM-15.
> - D-IDEM-17.
> - Aceptación expresa de R-1, R-30, R-24, R-26 y R-29 dentro del alcance documentado.
> - R-2 aceptado solo para Fase 1.
> - Pruebas de seguridad y concurrencia obligatorias antes de integrar.
>
> NO AUTORIZADO
>
> Laboratorios, migraciones, RPC, cambios de esquema, permisos, frontend, integración de ramas, push, merge, staging ni producción.

## 3. Correspondencia con el borrador (referencia, no reescribe la decisión)

| Elemento aprobado | Dónde está en el borrador v0.2 |
|---|---|
| Paquete H | §4 (O1–O3b, O4, códigos, `READ COMMITTED`/`VOLATILE`, prohibición de UPDATE permisiva, alcance de la autorización §4.8) |
| Paquete C | §5 (compuerta, «sin resolver», sin «crear otra igual»), §6 (reconocimiento), §7 (listado) |
| D-IDEM-5b / 5c | §8; §15.1 #3 y #4 |
| Extensión limitada de D-IDEM-15 | §6.3 (excepción nominal A y N-COL por nombre literal a `intenciones_reconocimientos`); §15.1 #2 |
| D-IDEM-17 (ruta única de B-01) | §10; DH-08 |
| R-1, R-30, R-24, R-26, R-29 | §14.2; DH-06, DH-07, DH-13 |
| R-2 solo Fase 1 | §14.1; §9.6 (D-IDEM-8) |
| Pruebas obligatorias antes de integrar | §13 (clases D, S, E, I, F, M) |

## 4. Constancias

1. **Las pruebas propuestas NO se ejecutaron.** Todo lo de §13 del borrador (pgTAP, concurrencia, seguridad negativa, mutantes, Vitest, Playwright, preflight recalculado) permanece **[NO EJECUTADO]**. No se corrió ningún laboratorio.
2. **D-IDEM-0 sigue ABIERTO.** B-01 permanece abierta hasta completar la recuperación (ADR-010 v1.0 §1.4); esta aprobación es **normativa**, no una aceptación técnica ni una implementación.
3. **D-IDEM-13** (revocar `EXECUTE` directo de las RPC de stock) **no** forma parte de esta aprobación y sigue pendiente; no se alteró ningún permiso.
4. **Incorporación al repositorio y cualquier implementación requieren autorización humana separada.** Esta acta no incorpora el texto aprobado a `docs/decisions/`, ni actualiza `BLUEPRINT.md` (§8, §12, §17), `docs/decisions/README.md` ni ADR-001; esos cambios figuran en el borrador (§15.4) como **propuestos**, no realizados.
5. Siguen siendo necesarias, antes de integrar: las pruebas de seguridad y concurrencia de §13 sobre `SECURITY DEFINER` y RLS reales; el recuento del preflight sobre la futura línea de integración (§12 del borrador); security review; auditoría independiente de Codex y OpenCode sobre un hash; y aprobación humana. La decisión sobre D-IDEM-7 (línea de integración) y sobre el laboratorio mínimo (§13.8) no está comprendida en esta decisión.
6. T3-01-L está cerrado **solo localmente** para el commit `6c45cbd0…` (constancia aparte); T3-01-R, la integración de ramas, staging y producción **no** están autorizados.

## 5. Lo que este registro no hace

No modifica el borrador aprobado, ADR-010 v1.0, ADR-001, `BLUEPRINT.md`, F1/F2, código, SQL, tests ni migraciones. No ejecuta laboratorios, no crea commits, no hace push, merge ni deploy, no accede a staging ni producción, no inicia implementación y **no declara resuelta D-IDEM-0**.
