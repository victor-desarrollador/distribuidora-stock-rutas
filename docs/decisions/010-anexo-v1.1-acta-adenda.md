# Acta externa de APROBACIÓN DEFINITIVA — Adenda consolidada de ADR-010 v1.1

Fecha de registro: 2026-11-08. Registrada por Claude-Worf (implementador; **no aprueba**) por instrucción del responsable del proyecto. La sesión no puede verificar criptográficamente la identidad del emisor; se registra la decisión tal como fue comunicada. Esta acta **sustituye**, en lo que respecta a la aprobación de A-2 y de la adenda consolidada, al acta de decisión parcial (SHA-256 `37d5f3c8555a88a814c9cfcf57ab64a29df7aaf57779a1fc9b8650e896d9a6d0`), que se conserva intacta como registro histórico.

## 1. Documentos vinculados (identidad verificada)
| Documento | Ruta | SHA-256 | Verificación al registrar |
|---|---|---|---|
| **Adenda consolidada aprobada** | `/home/tuculandia/Documentos/web/proyectos/tienda virtual/informes-adr010-v1.1/ADENDA_ADR010_v1.1_CONSOLIDADA_PARA_APROBACION.md` | `f359213e71f77e687656dfc01685a338dfdc414efb076d34c7f4f01264aead78` | **coincide exactamente** |
| Anexo ADR-010 v1.1 (borrador v0.2), aprobado previamente | `…/BORRADOR_ADR010_v1.1_PARA_APROBACION_v0.2.md` | `bd3db99336c0efe317255cca883357bb11e99d51102621a7eb9aba3a00894b41` | **coincide** (también la copia sin commit `docs/decisions/010-anexo-v1.1-texto-aprobado.md`) |
| Acta de aprobación normativa de v1.1 | `…/ACTA_APROBACION_NORMATIVA_ADR010_v1.1.md` | `5a17108faea6d8a589059c4c6e82bde1aa6760e8bd297dd0cbc80d31f5809f68` | **coincide** (también la copia sin commit) |
| Propuesta de adenda original (A-1, A-3, A-4 aprobados antes) | `…/PROPUESTA_ADENDA_ADR010_v1.1.md` | `22443ffc54e7ce3c926989367c12f7353a509a2351ea9bff4e58065a522ff093` | **coincide**, sin cambios |

## 2. Decisión humana (reproducción literal)

> "Apruebo normativamente DA-2': la redacción de A-2 sobre creado_en, ventana_desde calculada por el servidor y fallo cerrado ante respuestas incoherentes. Apruebo DA-7: la adenda consolidada ADR-010 v1.1 identificada por SHA-256 f359213e71f77e687656dfc01685a338dfdc414efb076d34c7f4f01264aead78, con sus cláusulas A-1 a A-4 y sin modificar el anexo v1.1 previamente aprobado. Autorizo únicamente registrar esta aprobación en un acta externa. Mantengo pendiente la especificación de p_desde futuro. No autorizo todavía incorporar la adenda al repositorio, modificar los siete archivos preparados de AP-A, crear commits, ejecutar pruebas o laboratorios, implementar, push, merge ni deploy."

## 3. Cláusulas aprobadas (individualmente)
| Cláusula | Contenido | Estado |
|---|---|---|
| **A-1** | Interpretación y precedencia de D-IDEM-17 (aprobado por el acta de v1.1; D-IDEM-13 separado y pendiente; sin alterar permisos de las RPC directas) | **APROBADA** (normativa). Ya aprobada en la decisión parcial; ratificada con la adenda consolidada |
| **A-2** | `ventana_desde` calculada por el servidor con su reloj; la ventana de `historial` se evalúa sobre `creado_en`; el reloj del cliente no es autoridad; respuestas fuera de contrato definidas; fallo cerrado (sin ofrecer crear) | **APROBADA** (normativa) — **redacción definitiva aprobada ahora (DA-2')** |
| **A-3** | La completitud de `sin_resolver` la determina el servidor (51 consultados, 50 devueltos); 50 elementos con `sin_resolver_truncado = false` es un conjunto completo y válido; fallo cerrado ante truncamiento o datos inválidos | **APROBADA** (normativa). Ya aprobada en la decisión parcial; ratificada |
| **A-4** | Confirmada recuperada tras `desconocido` o por `listar`: reconocimiento explícito antes de habilitar otra operación del mismo tipo; reconocimiento de interfaz distinto de confirmación de stock; `reconocer` no produce `movimientos_stock` | **APROBADA** (normativa). Ya aprobada en la decisión parcial; ratificada |
| **Adenda consolidada (DA-7)** | Conjunto A-1 a A-4, tabla de precedencia, impacto futuro sobre Blueprint y pruebas | **APROBADA** (normativa) |

**Sobre el encabezado de la adenda.** El documento aprobado conserva, sin edición, su encabezado original («PROPUESTA CONSOLIDADA, NO APROBADA ÍNTEGRAMENTE»); esa calificación corresponde a su redacción previa y la aprobación consta en esta acta. El documento no se modifica.

## 4. Precedencia (solo sobre lo que la adenda modifica)
La adenda **prevalece exclusivamente** sobre las siguientes cláusulas del anexo v1.1 aprobado, que el anexo **no pierde** en lo demás:
| Cláusula | Prevalece sobre (anexo v1.1) |
|---|---|
| A-1 | Las calificaciones de estado de D-IDEM-17 como «propuesta» (§0.1 fila 9, §10, §13.6, §15.1 n.º 24, §16.3 DH-08); para el estado de D-IDEM-17 rige el acta de v1.1 |
| A-2 | §7.3 punto 9, **segunda cláusula** (`ventana_desde` «fuera de [30 días, ahora]»), y la precisión de §7.1 sobre `historial`, `ventana_desde` y los indicadores |
| A-3 | §7.3 punto 3 y la precisión de §7.1 sobre `sin_resolver_truncado` |
| A-4 | §5.4, reglas del cliente (i) y (ii) |

Todo lo demás del anexo v1.1, de ADR-010 v1.0 (en lo no modificado por v1.1), de ADR-001 y del Blueprint **continúa vigente sin cambios**. El anexo v1.1 aprobado y su acta **no se editan**. La adenda no agrega RPC, tablas, columnas, estados, permisos ni tipos, y no toca D-IDEM-13.

## 5. Pendiente expresamente
- **Especificación de `p_desde` futuro:** el responsable la **mantiene pendiente**. A-2(8) establece que la adenda **no** define el comportamiento ante un `p_desde` posterior al instante de la consulta; sigue sin definirse ni restringirse y queda como decisión normativa futura.
- **D-IDEM-17 en Blueprint v2.7:** la decisión de incluirlo antes del commit documental sigue vigente, **pendiente de reflejar** (los archivos de AP-A no se modificaron).

## 6. Alcance de esta aprobación
La aprobación es **exclusivamente normativa**. **No constituye aceptación técnica ni autorización de implementación.** No autoriza: incorporar la adenda al repositorio (anexo adicional `010-anexo-v1.1-adenda.md`); modificar los siete archivos preparados de AP-A; crear commits ni ramas; ejecutar pruebas ni laboratorios; implementar; push, merge ni deploy; acceder a staging ni producción. Las pruebas que la adenda adapta o agrega (`VT-09`, `VT-09a/b`, `VT-08c/d/e`, `VT-10`, `LM-11a/b/c`, `LM-03'`, `LM-03a/b`, `LS-01`, `PW-01`, `PW-08`, `ES-05`) siguen **sin ejecutarse**. **D-IDEM-0 sigue abierto**; D-IDEM-13 sigue pendiente.

## 7. Autorizaciones que aún se necesitan
1. Incorporar la adenda al repositorio como anexo adicional (copia byte a byte, hash de registro y acta) — DA-8.
2. Modificar los archivos de AP-A (puntero a la adenda en ADR-010, `progress-log.md`, `README.md`, `BLUEPRINT.md` v2.7 con D-IDEM-17 y las precisiones de la adenda) — DA-8 y DA-9.
3. Crear el commit documental de AP-A y, después, la auditoría documental independiente.
4. Decidir `p_desde` futuro (pendiente).
5. Fases B (laboratorio) y C (implementación), Playwright, y cualquier push, merge o deploy: autorizaciones propias.
