# ADR-010 — Aclaración C1.2a-D1: identificador de intención nulo

**Fecha de aprobación:** 08/11/2026 (decisión humana del responsable del proyecto).
**Estado:** **APROBADA (normativa)**, alternativa B de la propuesta `DECISION_C1_2A_D1_INTENCION_NULA.md` (evidencia externa, SHA-256 `327c003f76efed7e206765246dcf6fe38618297265a34216cd1ccf7db02714b3`). Alcance de la aprobación: **exclusivamente normativa y de incorporación documental**. **No autoriza implementación**, migraciones, SQL, RPC, tests, laboratorios, staging, producción, commit, push, merge ni deploy.
**Relación:** aclaración de [ADR-010](010-intenciones-persistidas-de-operacion.md) (v1.0, enmienda v1.1 y adenda A-1 a A-4). Los anexos `010-anexo-v1.1-*` **no se editan** y siguen byte a byte como están registrados en [`010-anexo-v1.1.sha256`](010-anexo-v1.1.sha256).
**Contexto de preparación:** alcance `ALCANCE_C1_2A_ADR010_v1.1.md` (evidencia externa, SHA-256 `40dfdff28196971a927240f0755d0a3f3e28f25a867be516c238933c39526a30`). **D-IDEM-0 sigue abierto.** D-IDEM-13 sigue pendiente y separado. `p_desde` futuro sigue sin especificarse.

## 1. Problema normativo resuelto

La normativa aprobada no define qué ocurre cuando el parámetro `p_intencion_id` de `crear_intencion_operacion` es nulo. ADR-010 §5.5 (catálogo de errores nuevos: `intencion_tipo_invalido`, `intencion_payload_invalido`) y §5.5.1 (pasos 0-8) no lo nombran; la nota de §5.7 supone un id "no nulo" sin imponerlo en el borde de la RPC; el procedimiento O2 del anexo v1.1 §4.2 habla de la fila de la intención (`i.id` nulo), no del parámetro. Sin una regla, un id nulo llegaría al `INSERT` y fallaría con `23502`, un SQLSTATE ajeno al catálogo aprobado. El repositorio ya trata la clave nula como defecto de estructura en otros dominios (`PT400 stock_clave_invalida`, ADR-001 §18.3 P16-stock; `PT400 jornada_clave_invalida`, ADR-001 §18.4.3 y caso I14).

## 2. Firma

`crear_intencion_operacion(p_intencion_id uuid, p_tipo text, p_payload jsonb)` devuelve `uuid` (el mismo id). Fuente: ADR-010 v1.0 §5.5. La firma **no cambia**.

## 3. Reglas aprobadas

### 3.1 `crear_intencion_operacion`

| Situación | Resultado |
|---|---|
| Sin autenticación (`privado.usuario_actual()` nulo) | `PT401` conforme al contrato (`intencion_no_autenticado`) |
| Sin autorización (perfil ausente, inactivo o rol no habilitado) | `PT403` conforme al contrato (`intencion_no_autorizado`) |
| Actor autorizado y `p_intencion_id IS NULL` | SQLSTATE **`PT400`**, mensaje **`intencion_clave_invalida`** |

**Orden obligatorio de validación de `crear_intencion_operacion`** (precisión aprobada el 08/11/2026):

1. Verificar la autenticación; sin identidad → `PT401` según contrato.
2. Verificar empresa, perfil y autorización; sin autorización → `PT403` según contrato.
3. Si `p_intencion_id IS NULL` → SQLSTATE `PT400`, mensaje `intencion_clave_invalida`.
4. **Solo después**, validar `p_tipo` y `p_payload` con sus reglas existentes (ADR-010 v1.0 §5.4 y §5.5.1 paso 3).
5. Continuar con lock de nivel 0, replay, compuerta, topes e `INSERT` conforme a ADR-010 y al anexo v1.1 §5.2.

La validación del identificador nulo **precede siempre** a todo lock, al replay y al `INSERT`. Por lo tanto el rechazo no escribe, no cuenta para los topes y no se ve afectado por ellos. Si el actor está autorizado, `p_intencion_id` es nulo y además `p_tipo` y/o `p_payload` son inválidos, **prevalece `PT400 intencion_clave_invalida`**.

**Catálogo de errores.** El mensaje `intencion_clave_invalida` **amplía el catálogo de errores de ADR-010 §5.5 exclusivamente para este caso**. El SQLSTATE `PT400` ya integra el catálogo; no se agrega ningún SQLSTATE nuevo. Se aplican sin cambios las reglas existentes de ADR-010: `PTxyz` no se reintenta (§5.12, P13) y los errores de identidad y autorización no se convierten en rechazos de negocio (R-03).

### 3.2 `ejecutar_intencion_operacion` y `cancelar_intencion_operacion`

| Situación | Resultado |
|---|---|
| Identificador de intención nulo y autorización válida | `PT404` (`intencion_no_encontrada`) |
| Rechazo de autorización | `PT403` conforme al contrato |
| Sin autenticación | `PT401` conforme al contrato |

El rechazo **no crea una intención ni modifica ningún estado** (coherente con el procedimiento O1-O3b del anexo v1.1 §4.2: no hay fila de intención, no se toma bloqueo y no se escribe).

### 3.3 `p_tipo` y `p_payload` nulos

Se **conserva literalmente** el comportamiento de los contratos aprobados (ADR-010 v1.0 §5.4, §5.5 y §5.5.1 paso 3). Esta aclaración **no introduce decisiones nuevas** sobre ellos ni modifica sus códigos (`PT400 intencion_tipo_invalido`, `PT400 intencion_payload_invalido`). Con un identificador **válido**, el comportamiento de `p_tipo` y `p_payload` **no cambia**; la única interacción es de orden: con identificador nulo, §3.1 prevalece sobre sus rechazos.

## 4. Alcance preciso

Esta aclaración fija **únicamente** el tratamiento de un **identificador de intención nulo** en `crear`, `ejecutar` y `cancelar`. No modifica: la firma de ninguna RPC; el algoritmo de `crear` (replay → compuerta → topes), de `ejecutar` o de `cancelar`; el modelo de datos; las políticas RLS ni los permisos; la lista cerrada de rechazos de negocio (§5.7); las demás validaciones de payload; `reconocer` ni `listar`; las RPC de stock y de jornadas; D-IDEM-13; `p_desde` futuro; los topes ni DT-1.

`reconocer_intencion_operacion` (C1.2b) con identificador nulo **no** se resuelve aquí: queda como asunto pendiente (§7).

## 5. Referencias y precedencia limitada

- Referencias: ADR-010 v1.0 §5.5, §5.5.1, §5.7, §5.12; anexo v1.1 §4.2 (O1-O3b), §5.2 y adenda (sin cambios); ADR-001 §18.3 (P16-stock) y §18.4.3 (precedente de jornadas).
- **Precedencia.** Esta aclaración prevalece **únicamente** sobre el tratamiento de identificadores de intención nulos en las tres RPC indicadas. En todo lo demás rigen ADR-010 v1.0, el anexo v1.1 y la adenda A-1 a A-4 conforme a su tabla de precedencia. No reinterpreta ni reemplaza ninguna otra cláusula.
- La nota de §5.7 ("`stock_clave_invalida` no puede ocurrir (el id es un `uuid` no nulo)") sigue vigente para la RPC de negocio invocada por `ejecutar`: la comprobación de esta aclaración ocurre antes, en el borde de `crear`.

## 6. Pruebas futuras (no ejecutadas; condición de la aceptación técnica de C1.2a)

| Id | Clase | Caso | Esperado |
|---|---|---|---|
| CR-ID-01 | D | Actor autorizado, `p_intencion_id` nulo, tipo y payload válidos | `PT400 intencion_clave_invalida`; 0 filas nuevas en `intenciones_operacion`; `operaciones` y `movimientos_stock` sin cambios; nunca `23502` |
| CR-ID-02 | D | Id nulo con perfil inactivo y con rol `vendedor_piloto` | `PT403` (la autorización precede) |
| CR-ID-03 | D | Id nulo sin identidad (sin `sub`) | `PT401` |
| CR-ID-04 | D | Id nulo como `anon` | `42501` (sin `EXECUTE`) |
| CR-ID-05 | D | **Actor autorizado** (perfil activo, `dueno` o `encargado`), `p_intencion_id` **NULL** y `p_tipo` y/o `p_payload` **inválidos simultáneamente** (casos: tipo inválido con payload válido; tipo válido con payload inválido; ambos inválidos) | **Exactamente** `PT400` con mensaje `intencion_clave_invalida` (nunca `intencion_tipo_invalido` ni `intencion_payload_invalido`); **cero efectos persistentes**: 0 filas nuevas en `intenciones_operacion`, `operaciones` y `movimientos_stock` sin cambios |
| CR-ID-06 | D | Id nulo con tope de 20 sin resolver o 120 en la hora alcanzado (fixture) y con compuerta bloqueada | `PT400 intencion_clave_invalida`; ni `PT429` ni `PT409`; no cuenta para los topes |
| CR-ID-07 | S | Estático (ES-05): la comprobación del nulo precede a `pg_advisory_xact_lock` y a toda lectura de `intenciones_operacion` | Cumple |
| CR-ID-08 | D | `ejecutar` y `cancelar` con id nulo: autorizado; no autorizado; `anon` | `PT404`; `PT403`; `42501`; sin filas creadas ni estados modificados |
| (mutante, C1.3) | M | Quitar la comprobación del nulo en `crear` | Debe fallar CR-ID-01 |

Se aplica además el criterio general de negativos (`anon`, otro rol, otra empresa) de la matriz de pruebas de ADR-010.

## 7. Restricciones y asuntos pendientes

- **No autoriza implementación ni commit.** C1.2a requiere su propia autorización humana (migración, archivos, entorno descartable) y, hasta contar con `reconocer` en C1.2b, solo se valida en un **entorno local descartable**.
- **Pendiente de decisión humana:** tratamiento de identificador nulo en `reconocer_intencion_operacion` (C1.2b). El orden de validación de `crear` quedó cerrado en §3.1 (precisión aprobada el 08/11/2026).
- Se actualizará la aserción de inventario de funciones de `supabase/tests/intenciones_esquema.test.sql` cuando exista la autorización de C1.2a (no en esta incorporación documental).
- `p_desde` futuro, D-IDEM-13, DT-1 y D-IDEM-0: sin cambios; **D-IDEM-0 permanece abierto**.
