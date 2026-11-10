# ADR-010 — Aclaración C1.2b-D1/D2: identificador nulo en `reconocer` y `p_desde` posterior al instante de la consulta en `listar`

**Fecha de aprobación:** 09/11/2026 (decisión humana del responsable del proyecto).
**Estado:** **APROBADA (normativa)**, recomendaciones D1 y D2 de la revisión final `REVISION_FINAL_PROPUESTAS_C1_2B.md` (evidencia externa, SHA-256 `9e574aebbadb2ce21401e837abd181f876c3e5c68c1c396406e746d3c46f8e5d`) sobre las propuestas `PROPUESTAS_NORMATIVAS_C1_2B_D1_D2.md` (evidencia externa, SHA-256 `5b4c31cbe6776fbf21e9a71ac8cd51b0264be2747d1ddf835b9255451ca1fa24`). Alcance de la aprobación: **exclusivamente normativa y de incorporación documental**. **No autoriza implementación** de `reconocer_intencion_operacion` ni de `listar_intenciones_operacion`, migraciones, SQL, RPC, tests, laboratorios, staging, producción, commit, push, merge ni deploy.
**Relación:** aclaración de [ADR-010](010-intenciones-persistidas-de-operacion.md) (v1.0, enmienda v1.1 y adenda A-1 a A-4). Los anexos `010-anexo-v1.1-*` **no se editan** y siguen byte a byte como están registrados en [`010-anexo-v1.1.sha256`](010-anexo-v1.1.sha256). Complementa, sin modificarla ni extenderla, la [aclaración C1.2a-D1](010-aclaracion-c1-2a-clave-nula.md) (identificador nulo en `crear`, `ejecutar` y `cancelar`), que dejó expresamente pendiente el caso de `reconocer` (su §4 y §7).
**Estado del corte:** C1.2a está cerrada y auditada en el commit `1fb75e7ae1184c96461e7b670473fc12cc3fd2e4`. **C1.2b (`reconocer`, `listar`) no está implementada.** **D-IDEM-0 sigue abierto.** D-IDEM-13 sigue pendiente y separado.

## 1. Problemas normativos resueltos

1. **D1.** El anexo v1.1 §6.4 define el algoritmo de `reconocer` (identidad → lectura con autorización en la misma sentencia → `PT404` si no hay fila → `PT409` si no está confirmada → `INSERT`), pero ningún texto aprobado nombra el caso en que el parámetro `p_intencion_id` es nulo; la aclaración C1.2a-D1 lo excluyó expresamente.
2. **D2.** La adenda A-2 (2) fija `ventana_desde` como el mayor entre `p_desde` y el instante de la consulta menos 30 días, y A-2 (8) y el encabezado de ADR-010 dejan **sin definir** el comportamiento ante un `p_desde` posterior al instante de la consulta.

## 2. D1 — `reconocer_intencion_operacion` con `p_intencion_id` nulo

**Firma** (anexo v1.1 §6.4; sin cambios): `reconocer_intencion_operacion(p_intencion_id uuid) returns text`; devuelve `'reconocida'` (también al repetir).

### 2.1 Reglas aprobadas

| Orden | Situación | Resultado |
|---|---|---|
| 1 | Sin autenticación (`privado.usuario_actual()` nulo) | `PT401` conforme al contrato |
| 2 | Perfil ausente, inactivo o rol no habilitado (determinado en la misma sentencia que la lectura) | `PT403` conforme al contrato |
| 3 | Actor autorizado y `p_intencion_id IS NULL` | SQLSTATE **`PT404`**, mensaje **`intencion_no_encontrada`** |

- **Precedencia obligatoria:** `PT401` → `PT403` → `PT404`. La validez del identificador se resuelve **después** de la autenticación y la autorización.
- **Cero efectos persistentes:** el rechazo no escribe en `intenciones_reconocimientos`, no modifica `intenciones_operacion`, `operaciones` ni `movimientos_stock`, y no toma locks explícitos.
- El resultado es **indistinguible** de una intención inexistente, ajena o de otra empresa (anexo §6.4).
- **No se traslada a `reconocer` el `PT400 intencion_clave_invalida`** aprobado exclusivamente para `crear`. **No se incorporan mensajes, SQLSTATE ni estados nuevos.**
- Es coherente con lo ya aprobado para `ejecutar` y `cancelar` (C1.2a-D1 §3.2): las tres operaciones sobre una intención existente responden `PT404` al identificador nulo.

### 2.2 Fundamento
(i) Es el resultado literal del algoritmo aprobado: actor autorizado y sin fila de intención visible (anexo §6.4, paso 2); (ii) en `reconocer` el identificador es una **referencia** a una intención existente y no una clave de creación, igual que en `ejecutar` y `cancelar`; (iii) coincide con el precedente de ADR-001 §18.4.3 (una referencia nula a un objeto existente recibe el mismo `PT404` que la inexistente); (iv) no amplía el catálogo de errores.

## 3. D2 — `listar_intenciones_operacion` con `p_desde` posterior al instante de la consulta

**Firma** (anexo v1.1 §7.1; sin cambios): `listar_intenciones_operacion(p_desde timestamptz default null)` → `TABLE (sin_resolver jsonb, sin_resolver_truncado boolean, historial jsonb, historial_truncado boolean, hay_anteriores boolean, ventana_desde timestamptz)`.

### 3.1 Reglas aprobadas

1. **`p_desde` en el futuro** (posterior al instante de la consulta): `listar` **no rechaza** el pedido y **no recorta** `p_desde` al instante actual. Se aplica la fórmula de A-2 (2), de modo que **`ventana_desde = p_desde`**.
2. **`historial` de esa ventana es vacío** (ninguna intención resuelta tiene `creado_en >= ventana_desde`) y `historial_truncado = false`. `hay_anteriores` se determina por A-2 (3) con la ventana resultante; esta aclaración no lo redefine.
3. **`sin_resolver` permanece completo y sin filtro temporal** (anexo v1.1 §7.2 (2)–(3), adenda A-3): su contenido, orden, tope de 50 (51 consultados) y `sin_resolver_truncado` son idénticos a los de una llamada con `p_desde` nulo.
4. **Una sola fila** con perfil autorizado (también sin intenciones). `PT401` y `PT403` conservan su precedencia y **nunca** se convierten en lista vacía.
5. **El instante de la consulta** se toma una sola vez, en la misma sentencia e instantánea que el resto de la respuesta (A-2 (2)); la regla no agrega una rama especial para el futuro: es la aplicación de la fórmula aprobada.
6. **No se modifican** las reglas de truncamiento, los límites de 50 (`sin_resolver`) y 100 (`historial`), la ventana de 7 y 30 días ni la evaluación sobre `creado_en`.

### 3.2 Casos límite (tipo `timestamptz`)

| `p_desde` | Tratamiento |
|---|---|
| Nulo, pasado dentro de 30 días, anterior a 30 días | Sin cambios (A-2 (2) y ADR-010 v1.0 §5.13: los valores anteriores al límite se recortan a instante − 30 días) |
| Futuro finito | `ventana_desde = p_desde`; `historial` vacío; `sin_resolver` completo |
| **`-infinity`** | Es anterior al límite de 30 días: se aplica el **recorte de 30 días ya aprobado** (`ventana_desde` = instante − 30 días). Sin regla nueva |
| **`infinity`** | **Caso residual documentado.** Por la fórmula de A-2 (2), `ventana_desde` queda igual a `infinity`, valor que **no es una marca de tiempo ISO-8601 interpretable**; el parser A-2 del cliente (A-2 (5)(a)) lo considera **fuera de contrato** y debe **fallar cerrado** (recuperación incompleta o requerida; no ofrece crear ninguna operación; vuelve a consultar; el bloqueo cesa con la primera respuesta válida, A-2 (6)). No hay efecto de seguridad: nada de seguridad depende del historial (anexo §7.2 (4)) y `sin_resolver` no se altera |

### 3.3 Verificación pendiente (no se afirma nada aquí)
**La serialización real de `infinity` por PostgREST está pendiente de comprobación en C1.4.** Esta aclaración **no afirma** ningún formato HTTP, SQLSTATE ni error de PostgREST para ese valor; solo fija el contrato a nivel de la función SQL y el comportamiento exigido al parser (fallo cerrado ante un `ventana_desde` no interpretable).

### 3.4 Fundamento
(i) Es la lectura literal de A-2 (2), que no limita `p_desde` por arriba; (ii) es compatible con las tres condiciones de respuesta fuera de contrato de A-2 (5): con un futuro finito, `ventana_desde = p_desde` satisface (c) y el historial vacío satisface (b); recortar al instante habría devuelto `ventana_desde < p_desde` y habría violado (c); (iii) no agrega códigos de error ni rechaza un parámetro que solo afecta información no crítica; (iv) A-2 (7): una respuesta coherente pero atípica no se rechaza.

## 4. Alcance preciso

Esta aclaración fija **únicamente**: (D1) el tratamiento del identificador nulo en `reconocer_intencion_operacion`; (D2) el tratamiento de `p_desde` posterior al instante de la consulta —incluidos `-infinity` e `infinity`— en `listar_intenciones_operacion`. **No modifica:** las firmas; el algoritmo de `reconocer` ni de `listar`; la aclaración C1.2a-D1 (que sigue limitada a `crear`, `ejecutar` y `cancelar`); la semántica de reconocimiento explícito de la adenda A-4; las reglas de idempotencia y recuperación; el modelo de datos, las políticas RLS ni los permisos; los topes ni DT-1; D-IDEM-13; el parser y la UX del cliente (paquete frontend, fuera de C1).

## 5. Referencias y precedencia limitada

- Referencias: ADR-010 v1.0 §5.5 y §5.13; anexo v1.1 §6.4, §7.1–7.3, §13.3–13.4; adenda A-2 (1)(2)(3)(5)(6)(7)(8), A-3, A-4 y su acta definitiva; aclaración C1.2a-D1; ADR-001 §18.4.3; Blueprint v2.7 §12.
- **Precedencia.** Esta aclaración prevalece **únicamente** sobre el tratamiento del identificador nulo de `reconocer` y de `p_desde` posterior al instante de la consulta en `listar`. **Reemplaza**, solo respecto de ese punto, las menciones de que el caso «sigue sin especificarse» o «sigue pendiente» en el encabezado de ADR-010 (bloque «Enmienda v1.1 y precedencia»), en la adenda A-2 (8) y en la viñeta de la adenda A-2 de `BLUEPRINT.md` §12; esos textos no se editan. En todo lo demás rigen ADR-010 v1.0, el anexo v1.1 y la adenda conforme a su tabla de precedencia.

## 6. Pruebas futuras (no ejecutadas; condición de la aceptación técnica de C1.2b)

| Id | Clase | Caso | Esperado |
|---|---|---|---|
| RN-01 | D | `reconocer(NULL)` con actor autorizado | `PT404 intencion_no_encontrada`; cero filas nuevas en `intenciones_reconocimientos`; `intenciones_operacion`, `operaciones` y `movimientos_stock` sin cambios |
| RN-02 | D | `reconocer(NULL)` con perfil inactivo, `vendedor_piloto` y usuario sin perfil | `PT403` |
| RN-03 | D | `reconocer(NULL)` sin identidad / como `anon` | `PT401` / `42501` (sin `EXECUTE`) |
| RN-04 | D | Confirmada ya reconocida; `reconocer(id)`, luego `reconocer(NULL)`, luego `reconocer(id)` | `'reconocida'`, `PT404`, `'reconocida'`; la marca original no cambia |
| RN-05 | D | `reconocer(NULL)` frente a `ejecutar(NULL)` y `cancelar(NULL)` en los mismos escenarios | Mismo SQLSTATE en cada escenario |
| RN-06 | S | Inspección estática de `reconocer` | Sin `auth.uid()`, SQL dinámico ni `WHEN OTHERS`; el nulo se resuelve en la lectura con autorización, antes del `INSERT` |
| LF-01 | D | `listar(futuro finito)` con resueltas recientes y antiguas | Una fila; `ventana_desde = p_desde`; `historial = []`; `historial_truncado = false` |
| LF-02 | D | Pendiente de 400 días, vencida y confirmada sin reconocer; `listar(futuro)`, `listar(NULL)`, `listar(−365 d)` | El mismo `sin_resolver` en las tres |
| LF-03 | D | 50 y 51 sin resolver con `p_desde` futuro | 50 y `false`; 50 y `true` (A-3) |
| LF-04 | D | `p_desde = '-infinity'` | `ventana_desde` = instante − 30 días |
| LF-05 | D | `p_desde = 'infinity'` (nivel SQL) | `ventana_desde = infinity`; `historial = []`; `sin_resolver` intacto |
| LF-06 | D | Perfil inactivo / `vendedor_piloto` / sin perfil / sin identidad con `p_desde` futuro | `PT403` / `PT403` / `PT403` / `PT401`; nunca una fila vacía |
| LF-07 | D | `creado_en = T` fijo; `p_desde = T`, `T + 1 µs` y un futuro holgado (+1 h) | Frontera inclusiva `>=`; el futuro holgado da `historial = []` |
| LF-08 | S | Inspección estática de `listar` | Un único instante de consulta; sin rama especial para el futuro; sin locks ni `WHEN OTHERS` |
| C1.4 | D | PostgREST local: `reconocer(null)`, `listar` con futuro finito, `+infinity` y `-infinity` | **Verificar** la respuesta real (estado HTTP, cuerpo y serialización de `infinity`) y documentarla; no se asume hasta entonces |
| M (C1.3) | M | Variante que recorta el futuro al instante, o que devuelve otro error ante el nulo de `reconocer` | Debe fallar LF-01 / RN-01 |

## 7. Restricciones y asuntos pendientes

- **No autoriza implementación ni commit.** C1.2b requiere su propia autorización humana y, hasta contar con el corte completo, se valida solo en un entorno local descartable.
- **Pendiente:** implementación y pruebas de `reconocer` y `listar` (C1.2b); verificación de la serialización de `infinity` por PostgREST y del comportamiento HTTP (C1.4); regla de cliente sobre los valores de `p_desde` que envía (paquete frontend); aserción de inventario de funciones de `intenciones_esquema.test.sql` (de seis a diez funciones) al implementar C1.2b.
- Compuertas posteriores: C1.3 (clase I, concurrencia estadística, mutantes) y C1.4 (PostgREST, preflight final 50 / 25 / 13 / 38, `supabase test db`).
- D-IDEM-13, DT-1 y D-IDEM-0: sin cambios; **D-IDEM-0 permanece abierto**.
