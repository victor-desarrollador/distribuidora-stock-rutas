# ADR-010 v1.1 — ADENDA CONSOLIDADA PARA APROBACIÓN (A-1 a A-4)

**Estado: PROPUESTA CONSOLIDADA, NO APROBADA ÍNTEGRAMENTE.** A-1, A-3 y A-4 están **aprobadas normativamente** (contenido idéntico al de la propuesta original, SHA-256 `22443ffc54e7ce3c926989367c12f7353a509a2351ea9bff4e58065a522ff093`, que se reproduce **sin cambios**). **A-2 está aprobada solo como dirección normativa; su redacción definitiva (sección 2) está PENDIENTE de aprobación.** La adenda consolidada **no** está aprobada como conjunto. No modifica el texto aprobado de ADR-010 v1.1 ni su acta, ni ADR-010 v1.0, ADR-001, `BLUEPRINT.md` ni el `progress-log`; no autoriza implementación, pruebas, laboratorios, migraciones ni RPC; **D-IDEM-0 sigue abierto**.
**Autor:** Claude-Worf (implementador; **no aprueba**). **Fecha:** 08/11/2026.

| Cláusula | Estado | Fuente del texto |
|---|---|---|
| A-1 (interpretación y precedencia de D-IDEM-17) | **APROBADA** (normativa) | Idéntico a la propuesta original |
| A-2 (`ventana_desde`) | **Dirección aprobada; redacción PENDIENTE de aprobación** | Redacción nueva de esta consolidación (sección 2) |
| A-3 (límite de 50 y truncamiento) | **APROBADA** (normativa) | Idéntico a la propuesta original |
| A-4 (confirmada recuperada tras `desconocido`) | **APROBADA** (normativa) | Idéntico a la propuesta original |

**Forma de incorporación decidida:** como **anexo adicional** de ADR-010 (propuesto: `docs/decisions/010-anexo-v1.1-adenda.md`, copia byte a byte, con hash de registro), **sin alterar** el anexo v1.1 aprobado. **Decidido también:** incluir D-IDEM-17 en el Blueprint v2.7 antes del futuro commit documental (**aún no reflejado**: los archivos de AP-A no se modificaron).

**Base normativa.** `BLUEPRINT.md` vigente; ADR-001 aprobada; ADR-010 v1.0; ADR-010 v1.1 aprobada según el borrador v0.2, SHA-256 `bd3db99336c0efe317255cca883357bb11e99d51102621a7eb9aba3a00894b41`; acta de aprobación, SHA-256 `5a17108faea6d8a589059c4c6e82bde1aa6760e8bd297dd0cbc80d31f5809f68`. Las citas «anexo §n» se refieren al borrador aprobado. **Contexto Git (solo lectura):** rama `feat/adr010-convergencia`, HEAD `5fdfe3f232d6436f3ab6942d27303ba4c3ee8b84`; los 7 archivos de AP-A siguen sin commit y no se modificaron.

---

## 1. Dictamen de compatibilidad de A-2

**Dictamen: COMPATIBLE.** No hay incompatibilidad normativa material. Hallazgos, con referencias:

| Concepto | Qué dice el contrato aprobado | Referencia |
|---|---|---|
| `creado_en` | Columna `timestamptz not null default clock_timestamp()`: marca **del servidor** fijada al crear. Es la única columna temporal con índice (`(empresa_id, actor_id, creado_en desc)`) y la que usa el orden de `listar` (`creado_en desc`) y el tope de creaciones por hora | ADR-010 v1.0 §5.2 (modelo e índice; nota sobre `clock_timestamp()`), §5.5.1 paso 6; §5.5 (`listar`) |
| `p_desde` | `timestamptz default null`; «nulo equivale a 7 días y no puede ser anterior a 30 días (se recorta)» | v1.0 §5.5; §5.13; D-IDEM-5c (§0.2 #9); anexo §7.1 (firma y fila `historial`) |
| `historial` | «Hasta 100 intenciones resueltas, excluyendo las de `sin_resolver`; orden `creado_en desc, id`; ventana: `p_desde` nulo = 7 días, máximo 30 (los anteriores se recortan)» | Anexo §7.1 |
| `ventana_desde` | «Límite efectivo aplicado»; informativo; «nada de seguridad depende del historial» | Anexo §7.1; §7.2.4 |
| `hay_anteriores` / `historial_truncado` | «Existen resueltas anteriores a la ventana» / «Había más de 100 dentro de la ventana» | Anexo §7.1 |
| Ámbito de la ventana | `p_desde` y la ventana afectan **solo** a `historial`; `sin_resolver` no tiene límite temporal | Anexo §7.2.2 y §7.2.3 |
| Reloj del cliente | «Sin resolver» no depende del reloj del navegador; `vencida` se calcula con el reloj del servidor | Anexo §5.1; v1.0 §5.5 |

**Conclusión sobre `creado_en`.** El contrato aprobado **ya usa `creado_en` como referencia temporal** para ordenar `historial`, para indexar y para el tope por hora, pero **ninguna cláusula nombra expresamente la columna sobre la que se evalúa la ventana** («desde» se aplica a un instante no especificado). No se asume: A-2 lo **explicita** eligiendo `creado_en`, y esa elección **no contradice** ninguna cláusula (ninguna otra columna se menciona como criterio de ventana; `resuelto_en`, `vence_en` y `reconocida_en` aparecen solo como campos de los elementos y en las restricciones de coherencia). La elección tiene una consecuencia aceptable y ya cubierta por el contrato: una intención creada hace más de 7 días y resuelta hoy no aparece en `historial` por defecto; como `historial` es informativo y todo lo relevante está en `sin_resolver` (anexo §7.2.4; una `confirmada` sin reconocer nunca sale de `sin_resolver`), no hay efecto de seguridad ni de recuperación. La pérdida de la notificación de `rechazada` y `cancelada` ya está aceptada (anexo §7.2.6).
**Qué sigue siendo decisión humana:** aprobar el texto de A-2, incluida la elección de `creado_en` (DA-2').

---

## 2. Cláusulas

## A-1 — D-IDEM-17: interpretación y precedencia

**Cláusula actual (anexo).** §0.1 fila 9: «Ruta única de B-01 como condición de cierre de D-IDEM-0 (D-IDEM-17) … **PROPUESTA**»; §10: título «**PROPUESTA, sin aprobar**» y «**No se presenta como aprobada**»; §13.6: «`VT-10` … solo si se aprueba D-IDEM-17»; §15.1 #24: «`D-IDEM-17` (ruta única; **propuesta**)»; §16.3 DH-08: «*propuesta*». **Acta:** la aprobación comprende expresamente «D-IDEM-17».

**Contradicción.** El texto aprobado fue redactado antes de la decisión; sus marcas de estado dicen «propuesta» mientras el acta, que registra la decisión humana, lo incluye entre lo aprobado. Un lector que solo vea el anexo concluiría que D-IDEM-17 no rige y que `VT-10` es condicional.

**Redacción normativa propuesta.**
> **A-1.** (1) **D-IDEM-17 está APROBADO (normativo)** por la decisión humana registrada en el acta de aprobación de ADR-010 v1.1 (SHA-256 `5a17108f…9f68`), que lo incluye expresamente entre las disposiciones aprobadas. (2) Toda calificación de D-IDEM-17 como «propuesta», «**PROPUESTA**», «sin aprobar», «no se presenta como aprobada» o «solo si se aprueba» en el texto aprobado (anexo, encabezado de §10 y su texto, §0.1 fila 9, §13.6, §15.1 n.º 24 y §16.3 DH-08) corresponde a la redacción previa a la decisión y **queda superada por el acta**; para determinar el estado de D-IDEM-17 rige el acta. (3) El **contenido** de D-IDEM-17 es el de la sección 10 del anexo, sin cambios: la interfaz de B-01 muta stock **solo** por `crear → ejecutar` (y `reconocer`), con prueba estática sobre las fuentes de producción y comprobación de que los nombres de `registrar_ingreso`, `mover_a_cuarentena` y `registrar_merma` no figuran en la ruta de la interfaz ni en `dist/`. (4) D-IDEM-17 es **una de las condiciones** para cerrar D-IDEM-0; su cumplimiento no declara cerrada D-IDEM-0, cuyo cierre sigue siendo una decisión humana posterior. (5) **D-IDEM-13 permanece separado y pendiente**, fuera de v1.1: esta cláusula **no altera ningún permiso** de las RPC directas, que conservan `EXECUTE` para `authenticated`; R-2 sigue aceptado solo para la Fase 1. (6) D-IDEM-17 **no amplía** el alcance: no cubre jornadas ni `registrar_carga`/`registrar_descarga`.

**Naturaleza:** interpretación y precedencia (no cambia contrato). **Pruebas a adaptar:** `VT-10` pasa de condicional a **obligatoria**; las verificaciones de red de Playwright (`PW-01`, `PW-08`) deben afirmar que ninguna mutación de stock de la interfaz llama a las tres RPC directas. **Blueprint:** §12 (agregar el requisito; **AP-A no lo incluyó**, ver §6) y §17 (mención); §8 no.

---

## A-2 — `ventana_desde`: validación sin reloj del navegador — **REDACCIÓN PENDIENTE DE APROBACIÓN**

> **Estado de A-2: dirección normativa aprobada; redacción NO aprobada.** La aprobación estuvo condicionada a confirmar que la ventana de `historial` se evalúa sobre `creado_en` y que ello es compatible con el contrato aprobado. La verificación está en la sección 1 (compatible). El texto siguiente es la redacción propuesta y **requiere aprobación humana textual**.

**Cláusulas actuales (citas).** Anexo §7.1: `ventana_desde` = «Límite efectivo aplicado»; `historial`: «orden `creado_en desc, id`; ventana: `p_desde` nulo = 7 días, máximo 30 (los anteriores se recortan)»; `historial_truncado`: «Había más de 100 dentro de la ventana»; `hay_anteriores`: «Existen resueltas anteriores a la ventana». Anexo §7.2.3: «`p_desde` y la ventana afectan **solo** a `historial`»; §7.2.4: `historial_truncado`, `hay_anteriores` y `ventana_desde` son informativos. Anexo §5.1: «sin resolver» «no depende del reloj del navegador». Anexo §7.3 punto 9: «`ventana_desde` ausente o **fuera de [30 días, ahora]**». ADR-010 v1.0 §5.2: `creado_en timestamptz not null default clock_timestamp()` (fijado por el servidor); índice `(empresa_id, actor_id, creado_en desc)`; v1.0 §5.5 (`listar`): «orden `creado_en desc` … `p_desde` nulo equivale a 7 días y no puede ser anterior a 30 días (se recorta)»; v1.0 §5.13 y D-IDEM-5c (§0.2 #9): «`p_desde` nulo = 7 días; ventana máxima de 30 días; los valores anteriores se recortan».

**Contradicción.** La segunda cláusula del punto 9 de §7.3 hace depender la validez de la respuesta de una comparación con «ahora» y «hace 30 días» **según el reloj del cliente**, contra §5.1 y contra el carácter informativo de `ventana_desde` (§7.2.4). Con un reloj desajustado, una respuesta correcta del servidor se declararía inválida y bloquearía operaciones sin razón de seguridad.

**Redacción normativa propuesta (definitiva, pendiente de aprobación).**
> **A-2.** (1) **Referencia temporal.** La ventana de `historial` se evalúa **sobre `creado_en`** (la marca fijada por el servidor al crear la intención, ADR-010 v1.0 §5.2): una intención resuelta pertenece a la ventana si y solo si `creado_en >= ventana_desde`. `resuelto_en`, `vence_en` y `reconocida_en` **no** se usan como criterio de ventana. `sin_resolver` queda fuera de la ventana (anexo §7.2.2). (2) **Cálculo de `ventana_desde` por el servidor.** `ventana_desde` se calcula **con el reloj del servidor**, en la misma sentencia e instantánea que el resto de la respuesta: si `p_desde` es nulo, es el instante de la consulta menos 7 días; si no es nulo, es el mayor entre `p_desde` y el instante de la consulta menos 30 días. (3) **Indicadores.** `hay_anteriores` es verdadero si y solo si existe una intención resuelta del actor, no incluida en `sin_resolver`, con `creado_en < ventana_desde`; `historial_truncado` es verdadero si y solo si hay más de 100 intenciones resueltas con `creado_en >= ventana_desde`. (4) **El reloj del cliente no es autoridad.** El cliente no usa su reloj (ni el del navegador ni el del dispositivo) para validar `ventana_desde`, para decidir si ofrece crear, ni para clasificar vencimientos (`vencida` proviene del servidor). (5) **Respuesta inválida por ventana.** **Reemplaza** la segunda cláusula del punto 9 de §7.3. Una respuesta es **fuera de contrato** por `ventana_desde` únicamente si ocurre alguno de estos casos, que emplean solo datos de la propia respuesta y del pedido, nunca el reloj del cliente: (a) `ventana_desde` ausente, nulo o que no es una marca de tiempo ISO-8601 con zona horaria interpretable; (b) algún elemento de `historial` con `creado_en` ausente, no interpretable o **anterior a `ventana_desde`**; (c) el cliente envió `p_desde` y `ventana_desde` es **anterior** a `p_desde`. (6) **Fallo cerrado.** Una respuesta fuera de contrato según (5) se trata como cualquier otra (anexo §7.3): el cliente considera la recuperación incompleta o requerida, **no ofrece crear ninguna operación** (de ningún tipo), no la interpreta como lista vacía y vuelve a consultar; el bloqueo cesa con la primera respuesta válida. (7) **Respuesta coherente pero atípica.** Una `ventana_desde` coherente según (5) **no se rechaza** aunque difiera de lo que el cliente esperaría según su reloj; el cliente puede mostrar una advertencia informativa, que no bloquea ni condiciona ninguna acción. (8) **Alcance.** Esta cláusula no agrega parámetros, columnas, estados ni permisos, no cambia `p_desde` ni los límites de 7 y 30 días, y no define el comportamiento ante un `p_desde` posterior al instante de la consulta (el contrato aprobado no lo define).

**Naturaleza.** Doble: (i) *precisión* de un predicado que el contrato aprobado no nombra (la columna de la ventana), que se fija en `creado_en`, coherente con todo el contrato (sección 1); (ii) **cambio de contrato menor** de la validación del cliente (sustituye una regla de §7.3.9). El contrato del servidor no cambia: solo se explicita cómo calcula `ventana_desde` y qué significan los indicadores.

**Pruebas a adaptar o agregar (todas [NO EJECUTADO]).** `VT-09` (reemplaza la regla 9; casos a, b, c); `VT-09a` (reloj del navegador desfasado ±1 año con respuesta coherente: **no** bloquea); `VT-09b` (incoherencias a/b/c: **bloquea** y no ofrece crear); `LM-03'` y `LS-01` (el servidor devuelve `ventana_desde` según su reloj; todo `historial` con `creado_en >= ventana_desde`; `ventana_desde >= p_desde`); nuevo `LM-03a` (frontera: `creado_en` igual a `ventana_desde` **se incluye**; un instante anterior **se excluye**; una intención creada hace más de 7 días y resuelta hoy **no** figura en `historial` ni afecta `sin_resolver`); `LM-03b` (`hay_anteriores` e `historial_truncado` calculados sobre `creado_en`). **Blueprint:** §8 no cambia; §12 y §17 solo por mención.

## A-3 — Límite de 50 y semántica del truncamiento

**Cláusulas actuales.** Anexo §7.1: `sin_resolver_truncado` «`true` si hay más de 50 (se consultan 51 y se devuelven 50)». §7.3 punto 3: «`sin_resolver` con más de 50 elementos; `sin_resolver_truncado = true` con menos de 50; **`sin_resolver_truncado = false` con exactamente 50 y más pendientes conocidas es indecidible → se trata como truncado**».

**Contradicción.** Según §7.1, el servidor determina la completitud y, con `false`, el conjunto de 50 es **completo**; la tercera cláusula del punto 3 lo trata como «indecidible» y «truncado» apelando a «pendientes conocidas» que el cliente no puede conocer (solo ve lo que se le devuelve). Además, §7.1 implica que `true` ocurre solo con **exactamente 50** devueltos, no «con menos de 50» únicamente.

**Redacción normativa propuesta.**
> **A-3.** (1) **La completitud de `sin_resolver` la determina el servidor**, no el cliente: el servidor consulta hasta **51** elementos en la **misma sentencia e instantánea** que el resto de la respuesta, devuelve como máximo 50 y fija `sin_resolver_truncado = true` **si y solo si** existía al menos un elemento más allá de los 50 devueltos. (2) **Semántica de la respuesta:** (a) menos de 50 elementos y `false`: conjunto **completo**; (b) **exactamente 50 elementos y `false`: conjunto completo de 50 — respuesta válida, no truncada**; (c) exactamente 50 elementos y `true`: **hay más** resultados; la recuperación es incompleta; (d) cualquier otra combinación es **fuera de contrato**: más de 50 elementos; `true` con un número de elementos distinto de 50; `sin_resolver_truncado` ausente, nulo o no booleano. (3) **Reemplaza** el punto 3 de §7.3 por: «`sin_resolver` con más de 50 elementos; `sin_resolver_truncado = true` con un número de elementos distinto de 50; `sin_resolver_truncado` ausente o no booleano». (4) **Fallo cerrado:** ante (c) o (d), o ante cualquier otra respuesta fuera de contrato, el cliente trata la recuperación como incompleta o requerida, **no ofrece crear**, no la interpreta como lista vacía y relista tras resolver cada elemento (§7.3, vaciado garantizado). (5) En el caso (b), 50 elementos superan el tope defensivo de 20 (§5.13 y §8 del anexo) y por tanto indican una anomalía del invariante de §5.2: el cliente **muestra los 50 sin ocultar ni corregir**, y **no ofrece crear** hasta resolverlos; el servidor rechazaría igualmente `crear` (`PT409` o `PT429`). (6) «Completitud no demostrada» significa: bandera ausente, no booleana o inconsistente con el recuento (casos (d)); el cliente no infiere completitud por ningún otro medio.

**Naturaleza:** **interpretación de §7.1** y **cambio menor** del parser (se elimina una cláusula de §7.3.3 y se corrige la otra). El servidor ya la cumple si implementa §7.1. **Pruebas:** `VT-09` (casos a–d); `LM-11` se divide en `LM-11a` (49 → `false`), `LM-11b` (exactamente 50 → `false`, completo), `LM-11c` (51 → 50 devueltos y `true`) y se agrega verificación estática de que la bandera se calcula en la misma sentencia que el recuento (`ES-05`); `LM-03'`. **Blueprint:** no cambia §8; §12 y §17 solo por mención.

---

## A-4 — Confirmada recuperada después de estado `desconocido`

**Cláusulas actuales.** Anexo §5.4, reglas del cliente: «(i) tras una `confirmada` obtenida **en la misma página**, `reconocer` se invoca **después** de pintar el resultado; si no llega, se reintenta antes del próximo `crear`, **sin clic**; (ii) una `confirmada` **recuperada por `listar`** exige un **clic explícito**». §6.1: el reconocimiento no valida stock y **nunca mueve stock**.

**Contradicción (ambigüedad).** Si `ejecutar` agota los reintentos (estado `desconocido`) y el cliente consulta `listar` **en la misma página** y encuentra la intención `confirmada`, es «obtenida en la misma página» (i) y a la vez «recuperada por `listar`» (ii). Con (i) el cliente reconocería automáticamente algo que el usuario **nunca vio como resultado de su acción**.

**Redacción normativa propuesta.**
> **A-4.** (1) Las reglas (i) y (ii) se distinguen por el **origen** de la información, no por la página. (2) Regla (i), **reconocimiento automático**: solo cuando la `confirmada` es **la respuesta directa de `ejecutar`** (la original o la de un reintento P13 de esa misma llamada) y el resultado ya se **pintó** con la pestaña visible; el cliente invoca `reconocer` después de pintar y, si no llega, lo reintenta antes del próximo `crear`, sin clic. (3) Regla (ii), **reconocimiento explícito**: toda `confirmada` que el cliente obtenga **por cualquier otra vía** —`listar` tras recarga, cierre, otro dispositivo, **o tras haber pasado la intención por el estado `desconocido`**, aunque sea en la misma página— exige una **acción explícita del usuario** (botón «Entendido») antes de invocar `reconocer`. El cliente **no** invoca `reconocer` automáticamente sobre una intención que haya pasado por `desconocido`; esa marca vive solo en memoria (R-07) y, tras una recarga, toda confirmada recuperada es (ii). (4) **Habilitación:** el cliente **no ofrece otra operación del mismo tipo** mientras la confirmada recuperada no tenga su reconocimiento registrado (respuesta `'reconocida'` o reaparición en `listar` con `reconocida_en`); el servidor ya lo impone por la compuerta (§5.2). Si la respuesta de `reconocer` se pierde, la acción del usuario se reintenta con P13 y, si persiste la incertidumbre, la intención permanece sin resolver y no se habilita crear. (5) **Reconocimiento de interfaz ≠ confirmación de stock:** la acción explícita **solo** registra que el usuario vio que la operación **ya quedó registrada**; la confirmación de stock es la transición de `ejecutar` a `confirmada`, que ya ocurrió. La interfaz muestra el resultado y la leyenda de que el stock **ya fue movido**, y rotula el control «Entendido» (no «Confirmar» ni «Aceptar operación»). (6) **`reconocer` no produce `movimientos_stock`:** no invoca RPC de negocio, no escribe en `operaciones`, `movimientos_stock` ni `stock_actual` y su única escritura es una fila en `intenciones_reconocimientos` (§6.1 y §6.4 del anexo; sin cambios).

**Naturaleza:** **interpretación y precisión** del cliente; agrega un clic solo en la ruta posterior a `desconocido`; no cambia el contrato del servidor ni de `reconocer`. **Pruebas a adaptar:** `VT-08` se amplía con `VT-08c` (`ejecutar` agota reintentos → `desconocido` → `listar` encuentra `confirmada` → **no** hay `reconocer` automático, aparece «Entendido», no se ofrece crear), `VT-08d` (`ejecutar` devuelve `confirmada` directo, incluso tras un reintento P13 → reconocimiento automático después de pintar) y `VT-08e` (respuesta de `reconocer` perdida tras el clic); `PW-01` (variante con aborto de la respuesta, recarga y clic explícito: un solo movimiento y recuento de `movimientos_stock` igual antes y después de `reconocer`); `RC-03` y el mutante `M-15` se mantienen. **Blueprint:** §12 (mención del requisito) y §17; §8 no.

---


---

## 3. Tabla de precedencia

Orden general (`AGENTS.md` §1.1): Blueprint → ADR aprobadas → PRD → AGENTS → CLAUDE → inventario. Dentro de ADR-010:

| Nivel | Documento | Rige sobre |
|---|---|---|
| 1 | `BLUEPRINT.md` vigente | Todo lo que no modifica una ADR aprobada |
| 2 | ADR-001 aprobada | Sin cambios por v1.1 ni por la adenda |
| 3 | Acta de aprobación v1.1 (`5a17108f…9f68`) | El **estado** de las decisiones aprobadas (A-1) |
| 4 | **Adenda consolidada** (cuando esté aprobada íntegramente; hoy A-1, A-3 y A-4 aprobadas y A-2 pendiente) | Solo las cláusulas del anexo que nombra |
| 5 | ADR-010 v1.1 (anexo, `bd3db993…4b41`) | Las cláusulas de v1.0 que modifica (anexo §15.1) |
| 6 | ADR-010 v1.0 | Lo que v1.1 no modifica (anexo §15.3) |

| Cláusula | Texto del anexo que prevalece sobre | Texto de v1.0 afectado | Estado |
|---|---|---|---|
| A-1 | Calificaciones de estado de D-IDEM-17 (§0.1 f.9, §10, §13.6, §15.1 n.º 24, §16.3 DH-08) | Ninguno | Aprobada |
| A-2 | §7.3 punto 9, segunda cláusula; precisión de §7.1 (`historial`, `ventana_desde`, indicadores) | Ninguno (la ventana ya existe en v1.0 §5.5/§5.13; A-2 nombra su columna) | **Pendiente** |
| A-3 | §7.3 punto 3; precisión de §7.1 (`sin_resolver_truncado`) | §5.13 «Listado» ya modificado por v1.1 | Aprobada |
| A-4 | §5.4, reglas del cliente (i) y (ii) | §5.14 ya reemplazado por v1.1 | Aprobada |

Mientras A-2 no esté aprobada, **rige el texto aprobado del anexo** para `ventana_desde` (incluida la regla de §7.3.9), con la contradicción conocida registrada en la bitácora.

## 4. Impacto futuro sobre Blueprint y pruebas

**Blueprint (propuesto, sin editarlo).** §8 sin cambios. §12: agregar el requisito de **D-IDEM-17** (ruta única; decidido incluirlo, **pendiente de reflejar**) y precisar los ítems de `listar` (completitud determinada por el servidor; validación sin reloj del cliente; ventana sobre `creado_en`, si se aprueba A-2) y de reconocimiento (explícito tras `desconocido`). §17: mención de la adenda en la fila de la versión que la incorpore.
**Pruebas a adaptar o agregar (todas [NO EJECUTADO]):** `VT-09` (reglas 3 y 9), `VT-09a`, `VT-09b`, `VT-08c/d/e`, `VT-10` (obligatoria), `LM-11a/b/c`, `LM-03'`, `LM-03a`, `LM-03b`, `LS-01`, `PW-01` y `PW-08` (red y reconocimiento explícito), `ES-05` (bandera en la misma sentencia), `RC-03` y `M-15` (sin cambios). F1/F2 no se tocan; su adaptación tendrá en cuenta A-2 a A-4.

## 5. Decisiones humanas pendientes

| Id | Decisión |
|---|---|
| **DA-2'** | Aprobar la **redacción definitiva de A-2** (sección 2), incluida la elección de `creado_en` como referencia de la ventana y la regla de fallo cerrado ante `ventana_desde` incoherente |
| **DA-7** | Aprobar la **adenda consolidada como conjunto** y emitir su acta definitiva (hasta entonces rige el acta parcial) |
| **DA-8** | Autorizar la incorporación del anexo adicional `010-anexo-v1.1-adenda.md` (byte a byte, con su hash y acta) y la actualización de los archivos de AP-A (puntero en ADR-010, progress-log, README) **antes del commit de AP-A** o en un commit posterior |
| **DA-9** | Autorizar la edición del Blueprint v2.7 para incluir D-IDEM-17 (§12 y §17) y las precisiones de la adenda; hoy **no** está autorizada la modificación de los archivos de AP-A |

## 6. Hallazgo y estado
- El Blueprint v2.7 preparado en AP-A **no menciona D-IDEM-17**; se decidió incluirlo antes del commit, pero no se modificó ningún archivo de AP-A (se requiere DA-9).
- **PROPUESTA CONSOLIDADA, NO APROBADA ÍNTEGRAMENTE.** No se modificaron los documentos anteriores (propuesta original, borrador y acta de v1.1, los 7 archivos de AP-A); sin commits ni ramas; sin pruebas, laboratorios, migraciones ni RPC; sin push, merge ni deploy; sin acceso a staging ni producción. D-IDEM-0 sigue abierto.
