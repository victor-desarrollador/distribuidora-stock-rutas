# ADR-010 — Intenciones persistidas para recuperar operaciones con resultado desconocido (C-mínima) — **BORRADOR v1.1, revisión v0.2**

**Estado: PROPUESTA NO APROBADA.** Borrador normativo para revisión. No es una ADR vigente, no modifica ADR-010 v1.0, ADR-001 ni `BLUEPRINT.md`, no autoriza implementación, migraciones, RPC, laboratorios, staging ni producción, y no declara resuelta D-IDEM-0.
**Versión propuesta:** 1.1 (enmienda de la v1.0 **APROBADA**, normativa, del 06/11/2026). **Revisión del borrador:** v0.2 (corrige el borrador v0.1, SHA-256 `013daea4…b4e`, que se conserva intacto).
**Fecha:** 08/11/2026. **Autor:** Claude-Worf (implementador; **no aprueba**). Insumos de Claude-VM. La decisión es humana.
**Alcance:** Paso 2 de 7, **exclusivamente redacción y revisión normativa**. Implementación y laboratorios requieren autorizaciones humanas posteriores y separadas.
**Relación con ADR-010 v1.0:** enmienda. Todo lo que este borrador no menciona expresamente **permanece vigente** (§15.3). No cambia el estado de ADR-001 (APROBADA PARA VALIDACIÓN CONTROLADA).

> **Marcas de estado.** **[v1.0-VIGENTE]** aprobada el 06/11/2026, no cambia. **[DIRECCIÓN APROBADA]** el responsable aprobó la *dirección* (paquetes H y C y sus condiciones) y autorizó el borrador; el **texto concreto sigue pendiente de aprobación definitiva**. **[PROPUESTA]** no cubierta por la dirección aprobada. **[NO EJECUTADO]** prueba o verificación que **no** se hizo.
> **Convención de identificadores.** *Reglas* de v1.0: `R-01…R-13` (§5.1). *Riesgos* de v1.0: `R-1…R-22` (§11); los nuevos son `R-23…R-31`. *Decisiones humanas de este borrador*: `DH-01…DH-13`. *Decisiones de v1.0*: `D-IDEM-n`; las propuestas nuevas llevan los números provisorios `D-IDEM-17/18/19`. *Pruebas*: los ids de v1.0 (§10.B) se conservan y los nuevos se definen en §13.

**Fuentes leídas:** ADR-010 v1.0 (`6d725c8c…ce75`); `BLUEPRINT.md` v2.6 (§7.9.1, §8, §12); ADR-001 §18.3 (P12–P17-stock y remisión); `AGENTS.md`; `PROPUESTA_NORMATIVA_FINAL_ADR010_v1.1_VM.md` (`b6c83560…a980`); `REVISION_DIFERENCIAL_ADR010_v1.1_PASO2.md` (`7be66c53…6d4a`); `VALIDACION_DOS_CONTRATOS_ADR010_v1.1.md` (`d97036db…f811`); esquema de la línea `6c45cbd0`; revisión de Claude-VM del borrador v0.1.

**Evidencia y sus límites.** Lo único **medido** es un laboratorio mínimo de Claude-VM (evidencia externa `EVIDENCIA_H1_H2.md`, `fc60990e…b372`; tabla de 5 filas, PostgreSQL 17.11, una corrida): bajo RLS, `FOR UPDATE`/`FOR SHARE` filtran las filas que no cumplen el `USING` de `UPDATE`, también tras esperar (resultado «0 filas» sobre terminales); una política `UPDATE` permisiva adicional permitió `confirmada → cancelada`; una tabla aparte solo-`INSERT` fue idempotente y rechazó pendientes. **Nada se probó bajo `SECURITY DEFINER`, con las políticas reales, con PostgREST ni con el frontend.** Todo lo demás es **argumento de diseño**.

---

## 0. Resumen

### 0.1 Qué cambia respecto de v1.0

| # | Cambio | Paquete | Estado |
|---|---|---|---|
| 1 | `ejecutar` y `cancelar`: lectura inicial **con autorización en la misma sentencia** → `FOR UPDATE` solo para `pendiente` → relectura con autorización; `PT403`/`PT404`/`PT500` definidos; `READ COMMITTED` y `VOLATILE` exigidos; tratamiento simétrico | **H** | DIRECCIÓN APROBADA |
| 2 | Prohibición de políticas UPDATE permisivas adicionales sobre `intenciones_operacion` | **H** | DIRECCIÓN APROBADA |
| 3 | Alcance honesto de la validación de autorización bajo `READ COMMITTED` (§4.8) | **H** | DIRECCIÓN APROBADA (texto por aprobar) |
| 4 | Compuerta en `crear` por actor y tipo, con autorización en la misma sentencia; orden replay → compuerta → topes | **C** | DIRECCIÓN APROBADA |
| 5 | Desaparece «crear otra igual» mientras haya una intención sin resolver del mismo tipo | **C** | DIRECCIÓN APROBADA |
| 6 | Quinta RPC `reconocer_intencion_operacion` y tabla `intenciones_reconocimientos` por `operacion_id`; `UNIQUE` nueva en `intenciones_operacion`; `reconocer` nunca mueve stock | **C** | DIRECCIÓN APROBADA |
| 7 | `listar_intenciones_operacion`: una fila; `sin_resolver` (≤ 50, sin ventana) e `historial` separados; no autorizado ⇒ error, nunca lista vacía | **C** | DIRECCIÓN APROBADA |
| 8 | Topes: el de pendientes pasa a «sin resolver, todos los tipos y vigencias» como defensa | **C** | DIRECCIÓN APROBADA (valores y redacción por aprobar) |
| 9 | Ruta única de B-01 como condición de cierre de D-IDEM-0 (D-IDEM-17) | — | **PROPUESTA** |
| 10 | D-IDEM-13 (revocar `EXECUTE` directo de las RPC de stock) | — | **Fuera de la aprobación de v1.1; pendiente; no altera permisos** |

### 0.2 Correcciones de esta revisión respecto del borrador v0.1

| Corrección | Qué se resolvió | Dónde |
|---|---|---|
| **B-1** Autorización | Perfil y visibilidad en la **misma sentencia** en lectura inicial, relectura, replay, compuerta, `listar` y `reconocer`; `PT403` / `PT404` / `PT500` redefinidos; carrera residual documentada; sin garantía falsa; espejo `ejecutar`/`cancelar` | §4.2, §4.3, §4.4, §4.8, §5.2, §6.4, §7.2 |
| **B-2** Pruebas | `LM-01`, `LM-05`, `LM-06` redefinidas para la compuerta; nuevas pruebas; mutantes de sensibilidad; pruebas imposibles retiradas; referencias de §10.C, §15.1 y Blueprint §12 como cambios **propuestos** | §13, §15.1, §15.4 |
| **B-3** Integridad referencial | La FK y la `UNIQUE` garantizan coherencia estructural y correspondencia con una intención confirmada; la identidad del actor y el aislamiento de empresa se imponen por las validaciones de la RPC y las políticas RLS | §6.2 (2)–(3), §9.2–9.3 |
| Otras | «cinco» funciones; pasos del algoritmo H1; riesgos R-3/R-4/R-6/R-9/R-17/R-18/R-20 actualizados; respuestas fuera de contrato de `listar` completadas; `reconocer` nunca mueve stock; D-IDEM-17 y D-IDEM-13 como corresponde; identificadores sin duplicados; sin referencias a documentos de trabajo; Blueprint no presentado como modificado | §6.1, §7.3, §9, §10, §14, §16 |

---

## 1. Contexto y problema

**[v1.0-VIGENTE]** §1 de v1.0 (contexto, imposibilidad sin registro durable, estado de B-01) no cambia.

Hallazgos posteriores a la aprobación de v1.0:
- **H1.** El `SELECT … FOR UPDATE` de `ejecutar` y `cancelar`, con la política de `UPDATE` de §5.10 (`USING estado = 'pendiente'`), devuelve **0 filas** sobre intenciones terminales (medido en el laboratorio mínimo). Con el texto de v1.0, `ejecutar` repetido sobre una `confirmada` daría `PT404` en lugar de lo almacenado.
- **H2.** Una política `UPDATE` permisiva adicional, pensada para salvar H1, se combinaría por OR y permitiría transiciones entre estados terminales (medido).
- **Recuperación incompleta.** Con C-mínima, una confirmada con respuesta perdida, o una resuelta fuera de las 100 filas o de la ventana del listado, no genera señal que impida repetir la operación. El responsable decidió que esos casos no se aceptan como residuales sin decisión normativa.

---

## 2. Alcance y no-alcance

**Dentro:** los tres tipos de stock de v1.0 (`ingreso`, `a_cuarentena`, `merma`), por un mismo actor.
**Fuera [v1.0-VIGENTE]:** ventas, cobros, retiros, RPC de jornadas, `registrar_ingreso`/`mover_a_cuarentena`/`registrar_merma`, `operaciones`, `movimientos_stock`, deduplicar entre actores (D-IDEM-12), almacenamiento del navegador (R-07).
**Fuera, adicionalmente:** validar la exactitud del stock; cualquier cambio de permisos de las RPC directas (D-IDEM-13).

---

## 3. Nomenclatura

| Término | Significado | Estado |
|---|---|---|
| **C-mínima** | Arquitectura de v1.0 (D-IDEM-1) | Aprobada |
| **C-VM** | C-mínima + compuerta + reconocimiento persistente (esta enmienda) | Dirección aprobada; texto por aprobar |
| **Paquete H** | Corrección de H1/H2 y alcance de la autorización (§4) | Dirección aprobada |
| **Paquete C** | Recuperación durable (§5 a §7) | Dirección aprobada |
| **Sin resolver** | Concepto **derivado** (§5.1); no es un estado | Propuesto |

---

## 4. PAQUETE H — Corrección de H1

### 4.1 Reglas generales

**H-R1.** `ejecutar` y `cancelar` **leen primero sin bloqueo** y toman `SELECT … FOR UPDATE` **únicamente** cuando esa lectura encontró la intención `pendiente`.
**H-R2.** Una fila **terminal** (`confirmada`, `rechazada`, `cancelada`) puede leerse sin bloqueo porque **no cambia** (§5.3 de v1.0; sin `DELETE`; política `UPDATE` de §5.10).
**H-R3.** Cada transición a un estado terminal ocurre sobre una fila **obtenida con `FOR UPDATE`** (nivel 1 de §5.8 de v1.0).
**H-R4.** Bajo RLS, `FOR UPDATE` aplica el `USING` de las políticas `SELECT` **y** `UPDATE`. Sobre una intención que dejó de estar `pendiente` devuelve **0 filas**, también tras haber esperado a otra transacción. **0 filas no significa inexistencia**: se resuelve con la relectura.
**H-R5.** Las lecturas planas no toman locks y no alteran el orden global **actor → intención → stock**.
**H-R6 (autorización en la misma sentencia).** Toda lectura que decide un código de error de acceso (lectura inicial, relectura, replay, compuerta, `listar`, `reconocer`) obtiene **en la misma sentencia** (a) el estado de autorización del perfil (activo y rol habilitado) y (b) la fila de la intención, mediante un `LEFT JOIN` desde `perfiles`. Así `PT403` y `PT404` se distinguen sobre **una misma instantánea** y no hay ventana entre «validar el perfil» y «leer la fila». La única sentencia que no puede incluir `perfiles` es el `FOR UPDATE` (no admite el lado anulable de un `LEFT JOIN`); su RLS ya exige perfil activo y la relectura posterior cubre el caso (§4.2).

### 4.2 Procedimiento común de obtención (`ejecutar` y `cancelar`; reemplaza los pasos 2, 3 y 4 de §5.6 de v1.0)

Ambas RPC ejecutan **exactamente el mismo procedimiento** O1–O3b; solo difiere O4 (§4.3). Los pasos 5 a 7 de §5.6 de v1.0 (admisión por plazo, bloque protegido, transición) siguen aplicando a `ejecutar` sin cambios.

```text
O1. v_uid := privado.usuario_actual();  NULL → PT401 intencion_no_autenticado
O2. LECTURA INICIAL (sin bloqueo), UNA SOLA SENTENCIA con autorización:        -- ilustrativo
      SELECT p.empresa_id,
             (p.activo AND p.rol IN ('dueno','encargado'))      AS autorizado,
             i.id, i.estado, i.operacion_id, i.codigo_rechazo, i.vence_en, ...
      FROM public.perfiles p
      LEFT JOIN public.intenciones_operacion i
             ON i.empresa_id = p.empresa_id AND i.actor_id = p.usuario_id AND i.id = p_intencion_id
      WHERE p.usuario_id = v_uid;
      sin fila de perfil, o autorizado no verdadero          → PT403 intencion_no_autorizado
      autorizado y sin fila de intención (i.id nulo)         → PT404 intencion_no_encontrada
      terminal                                               → O4 con esta fila
      'pendiente'                                            → O3
O3. BLOQUEO: SELECT … FROM intenciones_operacion WHERE (empresa, actor, id) FOR UPDATE  (nivel 1; puede esperar)
      devuelve fila → debe estar 'pendiente' (si no → PT500); continuar según la RPC (O4 'pendiente')
      0 filas       → O3b
O3b. RELECTURA con la MISMA sentencia que O2 (instantánea nueva):
      perfil ausente o no autorizado                         → PT403 intencion_no_autorizado
      terminal                                               → O4 con esta fila
      cualquier otro resultado (sin fila de intención, o pendiente)  → PT500 intencion_error_interno
                                                               (revertir; sin efectos parciales; sin reintento P13)
```

### 4.3 O4 — ramas por estado (único paso distinto)

| Estado de la fila | `ejecutar` | `cancelar` |
|---|---|---|
| `confirmada` / `rechazada` | Devuelve lo almacenado (idempotente), sin llamar a la RPC de negocio y sin mirar el plazo | `rechazada` → devuelve `rechazada` (idempotente); `confirmada` → `PT409 intencion_ya_confirmada` |
| `cancelada` | `PT409 intencion_cancelada` | Devuelve `cancelada` (idempotente) |
| `pendiente` (solo desde O3, bajo bloqueo) | Pasos 5 a 7 de §5.6 de v1.0 (admisión con `clock_timestamp()`, RPC de negocio, `UPDATE`) | `UPDATE` a `cancelada` (también si está vencida); devuelve `cancelada` |

**Espejo exacto.** O1–O3b, los códigos y la numeración son los mismos en ambas RPC; una prueba parametrizada ejecuta la misma matriz estado × escenario contra ambas y exige resultados equivalentes salvo las columnas de O4 (§13, `SIM-01`).

### 4.4 Cuándo corresponde cada código

| Código | Corresponde | No corresponde |
|---|---|---|
| **`PT403`** | Perfil ausente, inactivo o con rol no habilitado, determinado **en la misma sentencia** que la lectura de la intención (O2 u O3b) | Nunca se convierte en `PT404`, en lista vacía ni en rechazo de negocio (R-03) |
| **`PT404`** | **Solo** en O2, con el perfil **ya validado como autorizado** en esa misma sentencia y sin fila de intención visible: inexistente, ajena, de otra empresa, o `crear` aún sin confirmar. «No visible para este actor en esta lectura»; **no prueba ausencia de efecto** | Nunca después de haber visto la fila; nunca para un perfil no autorizado |
| **`PT500`** | Inconsistencia interna real: O3b con perfil autorizado y sin terminal tras un `FOR UPDATE` en 0 filas (política `UPDATE` ausente o mal configurada, estado imposible); fila bajo `FOR UPDATE` con estado ≠ `pendiente`; aislamiento ≠ `read committed`. La transacción se revierte: **sin efectos parciales** | Cualquier carrera concurrente legítima |

**Ausencia de falsos positivos conocidos de `PT500`.** Los estados avanzan solo de `pendiente` a terminal (sin vuelta atrás, sin `DELETE`). Tras ver la fila `pendiente`, un `FOR UPDATE` en 0 filas solo tiene una causa válida: la fila dejó de ser `pendiente` o el perfil dejó de estar activo. O3b distingue ambas en una sola instantánea (terminal → rama de estado; perfil no autorizado → `PT403`). Si el perfil está autorizado y no hay terminal, nada de lo legítimo lo explica. Este es un **argumento**, no una prueba [NO EJECUTADO].
**Con esto desaparece el residual del borrador v0.1** (perfil inactivado entre «validar perfil» y «leer la fila»): ambas cosas se hacen en O2. Lo que queda es la carrera posterior a la última validación (§4.8).

### 4.5 Aislamiento y volatilidad (agrega a R-13 de §5.1)

- `ejecutar` y `cancelar` **fallan cerrado con `PT500`** si `transaction_isolation` no es `read committed`, como ya hace `crear`.
- Las **cinco funciones privadas y las cinco fachadas** son `VOLATILE`: la relectura necesita una instantánea nueva por sentencia. (Hoy las fachadas de stock son `language sql … volatile`.)

### 4.6 Prohibición de políticas UPDATE permisivas adicionales (agrega a §5.10)

`intenciones_operacion` tiene **exactamente tres** políticas (`SELECT`, `INSERT`, `UPDATE`, todas para `propietario_rpc`). **Se prohíbe toda política `UPDATE` permisiva adicional**: las permisivas se combinan con OR en `USING` y en `WITH CHECK`, y una nueva permitiría transiciones entre terminales. Ningún cambio de estado o de datos sobre una intención terminal se admite por vía alguna. El preflight, con su manifiesto cerrado, debe **rechazar** una cuarta política (`[POLITICA_ADICIONAL]`) y una prueba negativa lo comprueba.

### 4.7 Significado de `PT404` en el cliente (agrega a §5.5)

El cliente **no** interpreta `PT404` de `ejecutar` o `cancelar` como «no creada» ni habilita por él otra operación: un `PT404` a un id que el propio cliente creó es *resultado desconocido* (`desconocido`).

### 4.8 Alcance de la validación de autorización (no se promete más de lo que `READ COMMITTED` permite)

1. **Qué se garantiza.** Cada validación de autorización describe el perfil **en la instantánea de la sentencia que la realiza**. En ese instante el perfil estaba activo y con rol habilitado.
2. **Qué NO se garantiza.** Que el perfil siga activo en una sentencia posterior ni al confirmar la transacción. Bajo `READ COMMITTED`, otra transacción puede confirmar la inactivación del perfil o el cambio de rol **en cualquier momento posterior a la última validación**; no se detecta ni se impide.
3. **Efectos acotados.** (a) En `ejecutar`, la RPC de negocio revalida perfil y rol en su propia sentencia y todo el efecto es atómico con la transición; el resultado equivale a una operación ejecutada un instante antes de la inactivación. (b) En `cancelar`, la política `UPDATE` no exige perfil activo; el peor caso es que un actor recién inactivado descarte una intención propia, **sin efecto sobre stock**. (c) En `crear`, la política `INSERT` exige perfil activo en la instantánea del `INSERT`: si falla, el error `42501` se **propaga** (HTTP 403), sin convertirse en rechazo de negocio ni en lista vacía. (d) En `reconocer`, igual que `crear`.
4. **Alternativa no adoptada.** Fijar la fila de `perfiles` con `FOR SHARE` hasta el commit cerraría esa ventana, a costa de un lock nuevo entre dominios y de contención con la administración de perfiles. **No se adopta**; no está en la dirección aprobada. Si el humano quisiera cerrar la ventana, sería una decisión aparte.
5. Esta limitación se registra como **R-29** y requiere aceptación humana expresa (DH-07, DH-13).

---

## 5. PAQUETE C — Recuperación durable

### 5.1 «Sin resolver» (derivado; agrega a §5.3)

Para un actor y un tipo, una intención está **sin resolver** si:

| Condición | Salida del usuario |
|---|---|
| `estado = 'pendiente'` y vigente | Confirmar (`ejecutar`) o Descartar (`cancelar`) |
| `estado = 'pendiente'` y `clock_timestamp() >= vence_en` (**vencida incluida**) | Descartar (`cancelar`), que espera una ejecución admitida y devuelve el estado real |
| `estado = 'confirmada'` **sin** fila en `intenciones_reconocimientos` | Reconocer (`reconocer`) |

**No** están sin resolver: `rechazada` y `cancelada` (no movieron stock) ni una `confirmada` reconocida. «Sin resolver» **no es un estado ni una transición**: no agrega valores a `estado` ni cambia el diagrama de §5.3; no depende del reloj del navegador.

### 5.2 `crear` con compuerta y autorización (agrega paso 5b y cambia el paso 6 de §5.5.1)

**Lock [v1.0-VIGENTE].** Se mantiene el *lock de nivel 0 por empresa y actor* (`pg_advisory_xact_lock`, §5.5.1/§5.8); el lock **no** es por tipo. Lo «por actor y tipo» es la **compuerta funcional**, evaluada *dentro* de ese lock. Razón: los topes aprobados son por actor, agregados sobre todos los tipos; un lock por tipo reabriría el exceso de topes medido en v1.0 (PR-11).

```text
0.  transaction_isolation <> 'read committed' → PT500                                  -- R-13
1.  v_uid := privado.usuario_actual();  NULL → PT401
2.  Perfil y rol (sentencia sobre perfiles):  no autorizado → PT403                     -- antes de tomar el lock
3.  Validación y reconstrucción del payload (§5.4, sin cambios)
4.  Lock de nivel 0 (empresa, actor)                                                    -- sin cambios
5.  REPLAY — UNA SOLA SENTENCIA con autorización (perfiles LEFT JOIN intenciones por id):
      no autorizado                         → PT403
      existe, mismo tipo y payload          → devolver el id (sin contar)
      existe, tipo o payload distintos      → PT409 intencion_conflicto
5b. COMPUERTA Y DATOS DE TOPES — UNA SOLA SENTENCIA con autorización, instantánea posterior al lock:
      autorizado (perfil activo y rol habilitado)                                   AS autorizado,
      EXISTS(fila de (empresa, actor, p_tipo) con estado = 'pendiente'
             OR (estado = 'confirmada' AND NOT EXISTS reconocimiento de su operacion_id)) AS bloqueado,
      cantidad de intenciones sin resolver del actor (todos los tipos y vigencias)  AS n_sin_resolver,
      cantidad de creaciones de la última hora                                      AS n_hora
    Decisiones, en este orden:   no autorizado → PT403;   bloqueado → PT409 intencion_sin_resolver;
                                 n_sin_resolver ≥ 20 → PT429;   n_hora ≥ 120 → PT429
7.  INSERT … ON CONFLICT DO NOTHING (la política INSERT exige actor y perfil activo en su instantánea;
    si la rechaza, 42501 se propaga como error);  si no insertó → releer y aplicar el paso 5
8.  Devolver el id
```

- **Orden obligatorio de decisiones: replay → compuerta → topes.** Un reintento de un id existente nunca recibe `PT409 intencion_sin_resolver` ni `PT429`, y no cuenta para los topes.
- **La compuerta es una sola sentencia y contiene la autorización.** Partirla (una lectura de pendientes y otra de confirmadas sin reconocer, o una de autorización y otra de bloqueo) está **prohibido**: una fila que pasa de `pendiente` a `confirmada` entre ambas no se vería en ninguna, y un perfil inactivado entre ambas quedaría sin detectar. Un chequeo estático y un mutante lo comprueban (§13).
- **Por qué no hay falso negativo (argumento):** los `crear` del mismo actor se serializan por el nivel 0 y cada uno toma una instantánea posterior al lock; una fila progresa de forma monótona `pendiente → confirmada → reconocida` (o termina en `rechazada`/`cancelada`); una sola instantánea ve exactamente una etapa, y las dos primeras bloquean. [NO EJECUTADO]
- **Cardinalidad:** la compuerta limita a **una** sin resolver por tipo, es decir **tres** como máximo por actor. El tope de 20 es una **defensa** que no debería alcanzarse (solo por datos corregidos a mano o un defecto).
- **Locks de las demás operaciones:** `ejecutar`, `cancelar`, `reconocer` y `listar` no toman el nivel 0; `crear` no espera niveles 1 ni 2 mientras lo retiene. Orden global **actor → intención → stock**. `reconocer` no toma locks explícitos; su `INSERT` puede esperar el `FOR KEY SHARE` de la FK.

### 5.3 Eliminación de «crear otra igual»; operaciones independientes (reemplaza la «Restricción de interfaz» de §5.14 de v1.0)

> **Restricción (impuesta por `crear` en el servidor):** mientras el actor tenga una intención **sin resolver** de un tipo, no se crea otra de **ese tipo**. **No existe «crear otra igual».**

- Una vez **resuelta** la anterior (confirmada y reconocida, rechazada o cancelada), el actor puede crear nuevas intenciones de ese tipo, **incluso idénticas en contenido**: son operaciones independientes y legítimas, ejecutadas **en secuencia**.
- Intenciones de **otro tipo** nunca se bloquean entre sí.
- Actores distintos (p. ej. dueño y encargado) no se ven ni se bloquean entre sí (D-IDEM-12; R-1).
- La compuerta **no** usa producto ni ubicación: no deduplica por contenido.
- El servidor impide la segunda intención; **no** puede garantizar que el actor «vio» lo pendiente. Que la interfaz se lo muestre es una obligación del cliente, verificada por Playwright, no una garantía del servidor.

### 5.4 Flujo del cliente (reemplaza el diagrama de §5.14 de v1.0)

```text
ENVIAR
  id = crypto.randomUUID()
  crear(id, tipo, payload)      -- ≤3 intentos P13; PT409 intencion_sin_resolver → listar y pedir resolución
  ejecutar(id)                  -- ≤3 intentos P13
     confirmada → pintar el resultado con la pestaña visible → reconocer(id)
     rechazada  → mostrar el motivo (no requiere reconocimiento)
     sin respuesta tras 3 intentos → NO es fallo: listar y mostrar el estado real
RECUPERAR (recarga, cierre, otro dispositivo, misma sesión)
  listar()
     sin_resolver:
        pendiente vigente      → [Confirmar] ejecutar / [Descartar] cancelar
        pendiente vencida      → [Descartar] cancelar
        confirmada sin marcar  → mostrar + [Entendido] reconocer
     historial → informativo
```
Reglas del cliente: (i) tras una `confirmada` obtenida en la misma página, `reconocer` se invoca **después** de pintar el resultado; si no llega, **se reintenta antes del próximo `crear`**, sin clic; (ii) una `confirmada` recuperada por `listar` exige un **clic explícito**; (iii) si `listar` falla, responde `PT401`/`PT403`/`PT500`, responde fuera de contrato o `sin_resolver_truncado = true`, el cliente trata la recuperación como **incompleta y no ofrece crear** (§7.3); (iv) `PT403` de cualquier RPC se muestra como error de permiso, nunca como lista vacía.

---

## 6. RECONOCIMIENTO PERSISTENTE

### 6.1 Significado y límites

El reconocimiento registra que **la interfaz mostró al actor que la operación confirmada quedó registrada**. **`reconocer` nunca mueve stock:** no invoca ninguna RPC de negocio, no escribe en `operaciones`, `movimientos_stock` ni `stock_actual`, no modifica `intenciones_operacion`, y su **única escritura** es una fila en `intenciones_reconocimientos`. No valida la exactitud del stock, no aprueba, no es auditoría (P17 sin cambios) y no es un comando crítico de Blueprint §7.9.6. **No prueba lectura humana**: un cliente defectuoso puede reconocer sin mostrar (R-24).

### 6.2 Esquema (ilustrativo; no es una migración)

```sql
-- ILUSTRATIVO. No es una migración. No se ejecutó.
-- (1) Única adición a intenciones_operacion (v1.0 §5.2):
alter table public.intenciones_operacion
  add constraint intenciones_operacion_operacion_unica
  unique (empresa_id, actor_id, operacion_id);
-- operacion_id es anulable (NULL en las pendientes): con NULLS DISTINCT las pendientes no chocan.

-- (2) Tabla nueva:
create table public.intenciones_reconocimientos (
  empresa_id    uuid        not null,
  actor_id      uuid        not null,
  operacion_id  uuid        not null,
  reconocido_en timestamptz not null default clock_timestamp(),
  primary key (empresa_id, actor_id, operacion_id),
  constraint intenciones_reconocimientos_intencion_fk
    foreign key (empresa_id, actor_id, operacion_id)
    references public.intenciones_operacion (empresa_id, actor_id, operacion_id)
    on delete restrict
);
```

**Por qué `operacion_id` y no `intencion_id`.** `intencion_id` tiene el valor de `idempotency_key`; guardarlo en una tabla nueva sería una tercera representación durable de la clave y chocaría con la letra de P15 (ADR-001 §18.3), Blueprint §7.9.1 y la extensión de §7.1 de v1.0 («únicamente… `intenciones_operacion.id`»). `operaciones.id` es **otro uuid** (`default gen_random_uuid()`, nunca asignado desde la clave en los nueve `INSERT` de las RPC de la línea `6c45cbd0`). **§7.1 de v1.0 no se modifica y no se amplía ninguna excepción.**

**Qué garantiza cada capa (corrige el borrador v0.1).**
1. **FK y `UNIQUE` — coherencia estructural.** La FK apunta a la `UNIQUE` de `intenciones_operacion`, **no** a `operaciones` (una FK directa a `operaciones` probaría solo que existe una operación del actor, que podría provenir de una llamada directa o de jornadas). Como `intenciones_coherencia` (v1.0 §5.2) deja `operacion_id` no nulo **solo** en `confirmada` y la columna es `NOT NULL` en la tabla hija, el esquema garantiza que **toda fila de reconocimiento corresponde a una intención `confirmada`** y que sus `empresa_id`/`actor_id` **coinciden con los de esa intención**. La `UNIQUE` vuelve estructural la relación 1:1 operación ↔ intención.
2. **Qué la FK NO garantiza.** No decide **quién** es el que llama ni a qué empresa pertenece: una fila bien formada de otro actor o de otra empresa también satisface la FK. La FK no sustituye a la autenticación ni al aislamiento.
3. **Identidad del actor y aislamiento de empresa — RPC y RLS.** Se imponen por (a) las validaciones de la RPC: `empresa_id` y `actor_id` salen **solo** de `perfiles`/`privado.usuario_actual()` (R-10), nunca del cliente, y la intención se lee filtrando por esos valores (§6.4); y (b) las políticas RLS de la tabla (§6.3): `SELECT` e `INSERT` acotadas a `actor_id = (select privado.usuario_actual())` y perfil activo de la misma empresa. Cada capa se prueba por separado (§13, `RX-01`).
4. `operaciones` y `movimientos_stock` **no reciben nada**: ni FK, ni privilegio, ni política, ni columna. Los libros mayores siguen append-only por grants y RLS, sin triggers. La FK de v1.0 intención → operación sigue `ON DELETE RESTRICT`.
5. **Propiedad de implementación, no de esquema:** que `operaciones.id ≠ idempotency_key`. Nada lo impide estructuralmente (un `CHECK` tocaría `operaciones`; ES-07 y R-04). Se verifica por pruebas (§13, `RF-06b/c`), no por restricción (R-28).

### 6.3 Permisos y RLS de la tabla nueva [DIRECCIÓN APROBADA]

| Elemento | Contrato |
|---|---|
| `PUBLIC`, `anon`, `authenticated`, `service_role`, `lector_perfiles_rpc` | **Ningún** privilegio de tabla ni de columna (incluido `SELECT` por columna). `service_role` sin excepción nueva (P11) |
| `propietario_rpc` | `SELECT` de tabla; `INSERT (empresa_id, actor_id, operacion_id)` solo por columna (así `reconocido_en` no se fija desde afuera); sin `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER`, `MAINTAIN` |
| Owner / RLS | `postgres`; RLS habilitada **sin `FORCE`** (P4) |
| Política `SELECT` | Para `propietario_rpc`: `actor_id = (select privado.usuario_actual())` y perfil activo de la misma empresa |
| Política `INSERT` | `WITH CHECK`: lo mismo (actor y perfil activo de la misma empresa). **Sin `EXISTS`**: «correspondencia con una confirmada» lo impone el esquema (§6.2 (1)); el aislamiento de actor y empresa lo imponen esta política y la RPC (§6.2 (3)) |
| Retención | Indefinida, sin purga ni `DELETE` (D-IDEM-3) |
| Excepción del preflight | Se extiende la **excepción nominal A y N-COL** (D-IDEM-15) a esta tabla **por nombre literal**, nunca por patrón; las demás tablas conservan su contrato |

### 6.4 RPC `reconocer_intencion_operacion` (quinta función)

Topología como las demás: privada `SECURITY DEFINER` de `propietario_rpc` en `privado`, `search_path = ''` y endurecimiento pg_temp; fachada `SECURITY INVOKER`, `language sql`, owner `postgres`; `EXECUTE` solo para `authenticated`; sin sobrecargas (P14); `VOLATILE`.

| Aspecto | Contrato |
|---|---|
| Firma | `reconocer_intencion_operacion(p_intencion_id uuid) returns text` |
| Devuelve | `'reconocida'`, también al repetir |
| Quién | Solo el actor creador, perfil activo, rol `dueno` o `encargado`; identidad solo por `privado.usuario_actual()` (R-10, R-12) |
| Errores | `PT401`; `PT403` (determinado en la misma sentencia que la lectura); `PT404` (autorizado y sin fila visible: ajena, de otra empresa e inexistente, indistinguibles); `PT409 intencion_no_confirmada` para `pendiente`, `rechazada` y `cancelada`; `42501` propagado si la política `INSERT` rechaza (perfil inactivado después de la lectura) |
| Idempotencia | Por la PK; **se conserva la primera marca**; sin clave adicional |
| P13 | ≤ 3 intentos con el mismo id; `PT409` no se reintenta |
| Stock | **Nunca mueve stock** (§6.1) |
| Locks | Ninguno explícito; sin `FOR UPDATE`; no necesita `READ COMMITTED` (un snapshot atrasado solo produce un `PT409` conservador) |

```text
1. v_uid := privado.usuario_actual();  NULL → PT401
2. LECTURA — UNA SOLA SENTENCIA con autorización (perfiles LEFT JOIN intenciones por (empresa, actor, id)):
     no autorizado                          → PT403
     autorizado y sin fila de intención     → PT404
     estado <> 'confirmada'                 → PT409 intencion_no_confirmada
3. INSERT INTO intenciones_reconocimientos (empresa_id, actor_id, operacion_id)
     VALUES (v_empresa, v_uid, v_operacion) ON CONFLICT DO NOTHING;     -- v_operacion: de la fila leída
4. devolver 'reconocida'
```
`empresa_id` y `actor_id` salen **solo** de `perfiles`/`usuario_actual()`; `operacion_id` sale **de la fila leída**, nunca del cliente.

### 6.5 Respuesta perdida

Si el servidor registró el reconocimiento y el cliente no lo supo, el reintento (P13, mismo id) devuelve `'reconocida'` sin cambiar la marca. Si el reintento no llega, la intención **reaparece en `sin_resolver`**: **falso positivo seguro** (avisa de más, nunca de menos); cuesta un clic o un reintento automático, nunca un duplicado de stock.

### 6.6 Garantías demostradas e hipótesis

**Demostrado (laboratorio mínimo, una corrida):** el `INSERT` repetido es idempotente (1 fila), una pendiente es rechazada por RLS, `UPDATE`/`DELETE` quedan denegados por privilegio. **Hipótesis [NO EJECUTADO]:** conservación de la primera marca; FK a una `UNIQUE` con columna anulable; `ON CONFLICT DO NOTHING` bajo RLS real y privilegio por columna; todo bajo `SECURITY DEFINER`.

---

## 7. LISTADO

### 7.1 Respuesta exacta de `listar_intenciones_operacion`

```text
listar_intenciones_operacion(p_desde timestamptz default null)
returns table (
  sin_resolver           jsonb,         -- arreglo, nunca NULL
  sin_resolver_truncado  boolean,
  historial              jsonb,         -- arreglo, nunca NULL
  historial_truncado     boolean,
  hay_anteriores         boolean,
  ventana_desde          timestamptz
)
-- Con perfil autorizado: EXACTAMENTE UNA fila, siempre (también sin intenciones).
-- Sin perfil autorizado: NO devuelve fila; la privada lanza PT403 (PT401 sin identidad).
```

| Columna | Contenido |
|---|---|
| `sin_resolver` | Conjunto de §5.1 del actor, **sin filtro de fecha**, de cualquier tipo, orden **`creado_en asc, id`**, **máximo 50** |
| `sin_resolver_truncado` | `true` si hay más de 50 (se consultan 51 y se devuelven 50) |
| `historial` | Hasta **100** intenciones resueltas, **excluyendo** las de `sin_resolver`; orden `creado_en desc, id`; ventana: `p_desde` nulo = 7 días, máximo 30 (los anteriores se recortan) |
| `historial_truncado` | Había más de 100 dentro de la ventana |
| `hay_anteriores` | Existen resueltas anteriores a la ventana |
| `ventana_desde` | Límite efectivo aplicado |

Cada elemento lleva: `intencion_id`, `tipo`, `payload`, `estado`, `operacion_id`, `codigo_rechazo`, `creado_en`, `vence_en`, `resuelto_en`, `vencida` y **`reconocida_en`** (nulo si no hay reconocimiento). `vencida` solo puede ser `true` en una `pendiente`.

### 7.2 Reglas

1. **Una sola sentencia e instantánea**, **dirigida desde el perfil autorizado**: la consulta parte de `perfiles` filtrado por usuario, `activo` y rol habilitado, y todas las partes cuelgan de esa fila. Sin perfil autorizado la sentencia no produce ninguna fila, y la función lo traduce a **`PT403`**; **nunca** a una lista vacía. Ninguna intención puede aparecer a la vez en `sin_resolver` y en `historial`.
2. **`sin_resolver` no tiene límite temporal** (retención indefinida, D-IDEM-3) y no comparte el tope de 100.
3. `p_desde` y la ventana afectan **solo** a `historial`.
4. `historial_truncado`, `hay_anteriores` y `ventana_desde` son **informativos**: no hay cursor y lo anterior a la ventana no se alcanza; **nada de seguridad depende del historial** porque todo lo que importa está en `sin_resolver`.
5. Solo las del actor creador (D-IDEM-12); sin locks; solo lectura.
6. `rechazada` y `cancelada` fuera de `sin_resolver` pueden perder la notificación si se pierde la respuesta, sin efecto sobre stock.

### 7.3 Bloqueo seguro ante lectura incompleta, fallida o fuera de contrato

| Situación | Servidor | Cliente |
|---|---|---|
| `sin_resolver_truncado = true` | **Más de 50 implica ≥ 20**, así que `crear` responde `PT409` (mismo tipo) o `PT429` (otro tipo); el replay devuelve su id | Recuperación **incompleta**: muestra las 50, **no ofrece crear**, relista tras resolver cada una |
| `listar` falla (red, timeout, `PT401`, `PT403`, `PT500`, `42501`, respuesta no parseable) | — | «Recuperación requerida»: **no ofrece crear**; `PT401`/`PT403` se muestran como error de sesión/permiso |
| **Fuera de contrato** (cualquiera de las siguientes) | — | Igual: recuperación requerida; **nunca** se trata como lista vacía |

Respuestas **fuera de contrato** (lista cerrada; el cliente falla cerrado ante cualquiera):
1. Cuerpo que no es un arreglo de exactamente **una** fila (cero filas, más de una, objeto en lugar de arreglo).
2. Falta alguna de las seis columnas, tipo incorrecto, o `sin_resolver`/`historial` nulos o no arreglos.
3. `sin_resolver` con más de 50 elementos; `sin_resolver_truncado = true` con menos de 50; `sin_resolver_truncado = false` con exactamente 50 y más pendientes conocidas es indecidible → se trata como truncado.
4. `historial` con más de 100 elementos; `historial_truncado = true` con menos de 100.
5. Un `intencion_id` repetido dentro de una parte, o presente en ambas partes.
6. Un elemento sin alguno de los campos obligatorios, con `tipo` o `estado` fuera de los conjuntos cerrados, o con `payload` que no es objeto.
7. Incoherencias estado ↔ campos: `confirmada` sin `operacion_id` o sin `resuelto_en`; `pendiente` con `operacion_id`, `codigo_rechazo`, `resuelto_en` o `reconocida_en`; `rechazada` sin `codigo_rechazo`; `cancelada` con `operacion_id`; `reconocida_en` en una no confirmada.
8. `sin_resolver` que contiene `rechazada`, `cancelada` o una `confirmada` con `reconocida_en`; `historial` que contiene una `pendiente` o una `confirmada` sin `reconocida_en`.
9. `vencida = true` en una intención no `pendiente`; `ventana_desde` ausente o fuera de [30 días, ahora].
10. `hay_anteriores`/`historial_truncado` no booleanos.

**Vaciado garantizado:** resolver no requiere el listado completo; cada resolución saca una fila y no pueden entrar nuevas porque `crear` está rechazando.
**Acoplamiento normativo:** el tope de `sin_resolver` en `listar` (**50**) debe ser **mayor** que el tope de `crear` (**20**); subir el segundo por encima del primero rompe la implicación de la fila 1.
**Tamaño máximo de respuesta:** 50 × 4096 bytes de payload (~205 KB) más metadatos.

---

## 8. TOPES Y VENCIMIENTO (cambios sobre §5.13 y §0.2 de v1.0)

| Elemento | v1.0 [VIGENTE] | v1.1 [DIRECCIÓN APROBADA; valores por aprobar] |
|---|---|---|
| Vencimiento | 24 h, límite de **admisión**, `clock_timestamp()` bajo `FOR UPDATE` (D-IDEM-5a) | **Sin cambio.** Una vencida sigue siendo `pendiente` derivada y **ahora cuenta como sin resolver** |
| Pendientes por actor (D-IDEM-5b) | ≤ 20 **vigentes** | ≤ 20 **sin resolver**, todos los tipos y vigencias; **defensa** (máximo normal: 3). `PT429`; el replay no cuenta |
| Creaciones por hora (D-IDEM-5d) | ≤ 120 | Sin cambio |
| Listado (D-IDEM-5c) | 100 filas totales; 7/30 días; pendientes vigentes siempre | `sin_resolver` ≤ 50 sin ventana; `historial` ≤ 100 con 7/30 días (§7) |
| Orden en `crear` | replay → topes | **replay → compuerta → topes** |

---

## 9. SEGURIDAD

**9.1 SECURITY DEFINER (ADR-001 §18.3, P4, P14).** **Cinco** funciones privadas `SECURITY DEFINER` en `privado` (las cuatro de v1.0 más `reconocer`), propiedad de `propietario_rpc`, con `search_path = ''` y endurecimiento pg_temp; **cinco** fachadas `SECURITY INVOKER` en `public`, `language sql`, owner `postgres`; `EXECUTE` solo `authenticated`; sin sobrecargas; todas `VOLATILE`. Sin `auth.uid()` (R-12). Sin SQL dinámico (R-01). Sin `WHEN OTHERS` (R-02). `PT401`/`PT403`/`42501` nunca se convierten en rechazo de negocio (R-03) ni en resultado vacío.
**9.2 Roles y aislamiento por empresa.** Empresa y actor se derivan de `perfiles` vía `privado.usuario_actual()` (R-10); un perfil 1:1, una empresa, un rol (P5–P7). Sin roles técnicos nuevos (P3, D-2). `service_role` denegado (P11). **El aislamiento de actor y de empresa lo imponen las validaciones de las RPC y las políticas RLS** (no las FK): toda lectura filtra por `(empresa, actor)` derivados del contexto autenticado; intención ajena o de otra empresa → `PT404` indistinguible de un id inexistente.
**9.3 RLS.** `intenciones_operacion`: exactamente 3 políticas; **prohibida** toda política UPDATE permisiva adicional (§4.6). `intenciones_reconocimientos`: 2 políticas (`SELECT`, `INSERT`). Ambas con RLS habilitada sin `FORCE`. Alternativa A (D-IDEM-15): ningún acceso directo de `authenticated` a ninguna de las dos tablas; **sin permisos directos del frontend para modificar libros mayores** (regla R-06).
**9.4 Permisos denegados.** Acceso directo a cualquiera de las dos tablas por la Data API: `42501` (nunca `200 []`). Falta de privilegio de columna `UPDATE` para `propietario_rpc`: `42501` propagado, **no** 0 filas ni `PT404`. Rechazo de la política `INSERT`: `42501` propagado.
**9.5 Preflight T3-01.** Manifiesto cerrado actualizado (§12). Excepción nominal y N-COL por nombre literal para las dos tablas. Los hashes `h_using`/`h_check` se calculan con el texto final y `search_path = pg_catalog, pg_temp`.
**9.6 D-IDEM-13 y RPC directas — decisión separada y fuera de la aprobación de v1.1.** Las tres fachadas directas (`registrar_ingreso`, `mover_a_cuarentena`, `registrar_merma`) **conservan `EXECUTE` para `authenticated`**; esta enmienda **no altera ningún permiso**. El bypass (R-2) está aceptado temporalmente durante la Fase 1 (D-IDEM-8) y se cierra solo con D-IDEM-13, que sigue **pendiente** como ADR o enmienda propia (cambiaría ADR-001 §18.3, la ACL del preflight, la regla R-05 y suites). `registrar_carga` y `registrar_descarga` (jornadas) están fuera de ADR-010; su riesgo equivalente **no se evaluó**.
**9.7 Security review.** Obligatoria (`AGENTS.md` §2.4): toca Supabase, RLS, RPC, `SECURITY DEFINER`, grants, idempotencia y concurrencia. Aumenta la superficie privilegiada (R-3).

---

## 10. RUTA ÚNICA DE B-01 (D-IDEM-17) — **PROPUESTA, sin aprobar**

Condición **propuesta** para cerrar D-IDEM-0: la interfaz de B-01 muta stock **solo** por `crear → ejecutar` (y `reconocer`). Verificación: prueba estática sobre las fuentes de producción y comprobación de que los tres nombres de las RPC directas no están en `dist/`. **No cambia permisos ni contratos.** Las pruebas E2E y pgTAP pueden seguir llamando a esas RPC. Residuales: R-2 y pestañas con versión vieja hasta recargar. **No se presenta como aprobada.**

---

## 11. COMPATIBILIDAD CON P15, D-IDEM-2 Y LOS LIBROS MAYORES

- `intenciones_reconocimientos` referencia `operaciones.id` **a través** de `intenciones_operacion`; **no almacena `idempotency_key`**. P15 (ADR-001 §18.3), Blueprint §7.9.1 y §7.1 de v1.0 permanecen **sin cambios**; no se amplía D-IDEM-2.
- Control agregado a §7.1 de v1.0: «`intenciones_reconocimientos` referencia `operaciones.id`, no la clave».
- RF-04 (la clave no aparece en `movimientos_stock` ni en documentos hijos) sigue vigente tal cual.
- Libros mayores: `operaciones` y `movimientos_stock` sin cambios (regla R-04, ES-07).

---

## 12. PREFLIGHT E INVENTARIOS (recálculo pendiente)

| Inventario | Base verificada en la línea `6c45cbd0` | v1.0 implementada | **v1.1 propuesto** | Estado |
|---|---|---|---|---|
| Firmas del manifiesto de funciones | 40 | 48 | **50** | **A RECONTAR** |
| Funciones `SECURITY DEFINER` (inventario 3.7) | 20 | 24 | **25** | **A RECONTAR** |
| Relaciones con RLS del manifiesto | 11 | 12 | **13** | **A RECONTAR** |
| Políticas RLS del manifiesto | 33 | 36 | **38** | **A RECONTAR** |

Las cifras 48/24/12/36 (v1.0) y 50/25/13/38 (este borrador) son aritmética sobre la base 40/20/11/33 (confirmada en la línea `6c45cbd0` por la evidencia de su preflight), **no** un recuento con el preflight real [NO EJECUTADO]. La línea de integración **no es** la del worktree de ADR-010 (`873d23e` no es ancestro de `6c45cbd0`; los preflights difieren). **Deben recalcularse sobre la futura línea de integración** y reaplicarse todos los puntos de §8.2.1 de v1.0 (siete bloques de relaciones, manifiestos, lista 3.4 de sobrecargas +1 nombre, inventario 3.7 +1 firma, conteos, hashes, `NOTICE`, excepción A y N-COL) con la tabla nueva.

---

## 13. PRUEBAS OBLIGATORIAS FUTURAS — **todas [NO EJECUTADO]**

> Nada de esta sección se ejecutó. Son condiciones de la **aceptación técnica**, no resultados.

### 13.0 Reglas para que cada prueba sea un requisito vigente

**Clases.** **D** = determinista (sesiones externas con locks, barreras y esperas verificables con `pg_stat_activity`, `wait_event_type = 'Lock'`). **S** = estática (inspección del cuerpo/definición). **E** = estadística (≥ 10 rondas; evidencia de sensibilidad, no prueba de ausencia). **I** = laboratorio instrumentado (barrera o `pg_sleep` entre sentencias de una función de prueba; **no** forzable desde sesiones externas). **F** = frontend (Vitest/Playwright). **M** = mutante de sensibilidad (§13.9).
**Regla:** una prueba solo es requisito vigente si su disparador es controlable con la clase declarada. Las carreras *entre dos sentencias de la misma función* son **solo I**; las sesiones externas **no** las prueban. Las clases E e I exigen declarar el arnés; no se presentan como deterministas.
**Arnés.** Stack descartable con las migraciones reales de la línea que se integre; funciones reales; `propietario_rpc` real sin bypass (verificar `current_user` y `rolbypassrls` dentro de la función); JWT real por PostgREST para forma de respuesta y permisos; sesiones `psql` con `SET LOCAL ROLE authenticated` y claims; invariantes tras cada ronda (1 `operaciones`, 1 movimiento, saldo exacto).

**Depuración respecto del borrador v0.1 (pruebas imposibles o mal formuladas retiradas):**

| Prueba del v0.1 / de v1.0 | Problema | Tratamiento en v0.2 |
|---|---|---|
| `LM-05`, `LM-06` (N `crear` simultáneos hasta alcanzar 20 / 120) | Con la compuerta no se llega a 20 pendientes por `crear` concurrente (máximo 1 por tipo) | Redefinidas como `LM-05'` y `LM-06'` (abajo) |
| `LM-01` («más de 20 pendientes vigentes → `PT429`») | No alcanzable por `crear` | Redefinida como `LM-01'` (fixture) |
| `H1-P7` (locks de filas filtradas con `pg_locks`) | Los locks de fila no aparecen en `pg_locks` | Reemplazada por `LK-01` (otra sesión intenta un `UPDATE` y no espera) |
| `CC-12` (L-I) «crear confirma entre lecturas» | Con lectura primero no existe esa ventana; y no es forzable desde fuera | Dividida: `CC-12a` (D) y `TT-01/TT-02` (I) |
| `G-M` «detecta compuerta en dos sentencias» como determinista | Una carrera entre sentencias no es determinista externa | `ES-05` (S) + `LM-05'` (E) + mutante `M-01` |
| `H1-P1` «perfil inactivado entre lecturas» como D | Requiere interponerse entre sentencias | Pasa a `AU-03` (I); la variante D es `AU-01` (perfil ya inactivo) |
| Mutante «orden `FOR UPDATE`-primero» | Sin diferencia observable externa | Solo detectable por revisión estática (`ES-05`); no se promete detección dinámica |

### 13.1 Paquete H

| Id | Clase | Caso | Esperado |
|---|---|---|---|
| `SD-02` | D | `ejecutar` y `cancelar` sobre cada estado, por la vía real | Ramas de §4.3; nunca `PT404` sobre una fila existente |
| `SIM-01` | D | **Simetría:** la misma matriz estado × escenario contra `ejecutar` y `cancelar` | Mismos códigos en O1–O3b; difieren solo en O4 |
| `SD-03` | D | Sin política `UPDATE` (`BEGIN … ROLLBACK`) | `PT500`; sin efecto |
| `H1-P2` | D | Revocar `UPDATE` de columnas a `propietario_rpc` (`BEGIN … ROLLBACK`) | `42501` propagado; no 0 filas ni `PT404` |
| `AU-01` | D | Perfil inactivo (ya inactivo al llamar) en `ejecutar`/`cancelar`, para cada estado | `PT403`; nunca `PT404` ni resultado |
| `AU-02` | D | Rol incorrecto (`vendedor_piloto`) en `ejecutar`/`cancelar` | `PT403` |
| `AU-03` | I | Perfil inactivado entre O2 y O3 (barrera) | O3 devuelve 0 filas → O3b → `PT403` |
| `TT-01` | I | Transición `pendiente → confirmada` entre O2 y O3 (barrera tras O2) | O3 en 0 filas → O3b terminal → devuelve lo almacenado; un efecto |
| `TT-02` | I | Ídem con `cancelar` concurrente (`pendiente → cancelada`) | `ejecutar` → `PT409 intencion_cancelada`; `cancelar` → `cancelada`; 0 movimientos |
| `CC-09` | D | A: `ejecutar` abierto; B: `ejecutar` espera; A confirma | B devuelve lo almacenado; espera verificada |
| `CC-10` | D | A: `cancelar` abierto; B: `ejecutar`; y el orden inverso | `PT409 intencion_cancelada` o `PT409 intencion_ya_confirmada` |
| `CC-11` | D | A: `ejecutar` abierto que revierte; B esperaba | B bloquea la pendiente y ejecuta: 1 efecto |
| `CC-12a` | D | `crear` sin confirmar; B: `ejecutar` | `PT404` sin espera; luego de confirmar, ejecuta |
| **`CL-01`** | D | **Cancelación con respuesta perdida y primer intento todavía en curso:** A: `cancelar` abierto (con `FOR UPDATE` tomado); el cliente reintenta B: `cancelar` (mismo id) | B espera (verificado); al confirmar A, B devuelve `cancelada` idempotente; 0 movimientos. Variantes: el primer intento es un `ejecutar` en curso (B → `PT409 intencion_ya_confirmada`); el primer intento revierte (B cancela) |
| `R13-E` | D | `ejecutar` y `cancelar` en `REPEATABLE READ` y `SERIALIZABLE` | `PT500` |
| `VE-07` | D | `cancelar` de una vencida con ejecución admitida abierta | Espera; `PT409 intencion_ya_confirmada` |
| `LK-01` | D | Un `FOR UPDATE` filtrado por RLS no retiene lock: otra sesión (owner) intenta `UPDATE` de esa fila terminal | No espera |
| `H1-P3` | S/D | `provolatile = 'v'` de las 5 fachadas y 5 privadas | Cumple |
| `ES-03b` | D | Como `propietario_rpc` (`SET ROLE`), `UPDATE` de terminal con cada combinación (`confirmada→cancelada`, `rechazada→confirmada`, terminal→`pendiente`, cambio de actor o empresa) | 0 filas |
| `ES-06a` | D | El preflight falla con una 4.ª política `UPDATE` | `[POLITICA_ADICIONAL]` |
| Reescritas sobre SD y RLS reales | D | `EJ-02`, `EJ-06`, `EJ-07`, `CC-01`, `CC-02`, `VE-03`, `RC-01`, `SD-01` | Pasan |

### 13.2 Paquete C — compuerta, lock y autorización

| Id | Clase | Caso | Esperado |
|---|---|---|---|
| **`LM-01'`** | D | Redefine `LM-01`. **Fixture SQL** (no alcanzable por `crear`) con 20 sin resolver del actor; luego `crear` del mismo tipo y de otro tipo; replay | Mismo tipo `PT409 intencion_sin_resolver`; otro tipo `PT429`; el replay devuelve su id; `listar`, `ejecutar`, `cancelar`, `reconocer` responden. Camino normal: con una `pendiente` de un tipo, un segundo `crear` del mismo tipo da `PT409` |
| **`LM-05'`** | E | Redefine `LM-05`. N ≫ 3 `crear` distintos y simultáneos del mismo actor, **mismo tipo**; y otra serie mezclando los 3 tipos; ≥ 10 rondas | Mismo tipo: **exactamente 1** éxito, el resto `PT409` (ninguno `PT429`); mezclado: **≤ 1 por tipo** (≤ 3), sin filas extra ni duplicados |
| **`LM-06'`** | E | Redefine `LM-06`. Fixture con **118** creaciones resueltas en la última hora; luego 3 `crear` simultáneos de los 3 tipos; ≥ 10 rondas | **Exactamente 2** éxitos y **1** `PT429`; creaciones de la última hora = **120** en todas las rondas; el replay no cuenta |
| `LM-07'` | D | Replay con algo sin resolver y con tope alcanzado | Devuelve el id; ni `PT409` ni `PT429` |
| `LM-07a` | D | `crear` de actores distintos y `crear` de tipos distintos de un mismo actor | No se esperan entre sí por la compuerta (solo por el nivel 0 del mismo actor) |
| `AU-04` | D | Perfil inactivo **antes de `crear`**; y perfil inactivo con una sin resolver | `PT403` (no `PT409`, no inserta, no devuelve replay) |
| `AU-05` | D | Verificación de que replay, compuerta y topes **incluyen autorización**: perfil inactivo en cada una (replay de un id existente; compuerta) | `PT403` |
| `ES-05` | S | Compuerta + datos de topes en **una sola sentencia** con `perfiles`; replay con `LEFT JOIN`; lecturas de O2/O3b con `perfiles`; relectura idéntica a la lectura inicial; cero `WHEN OTHERS`, `auth.uid()`, SQL dinámico | Cumple |
| `CC-06` | D | `reconocer` abierto + `crear` mismo tipo; y al revés | `PT409` conservador; luego procede |
| `CC-07` | D | `ejecutar` abierto + `crear` mismo tipo | `PT409`, **sin espera** |
| `CC-13` | D | Un `crear` retiene el nivel 0 | `reconocer`, `ejecutar`, `cancelar`, `listar` no esperan; otro `crear` del actor sí |
| `CC-14` | E | `crear`, `ejecutar`, `cancelar`, `reconocer`, `listar` mezclados, ≥ 10 rondas | Ninguna ronda con `40P01`; invariantes |
| `CC-04'` | D | Mismo id con otro tipo o payload, concurrente | `PT409 intencion_conflicto` |
| `G-R` | D | `rechazada`, `cancelada`, confirmada reconocida; sin resolver de otro actor/empresa/tipo | **No** bloquean |
| `PW-07` | F | Dos operaciones idénticas legítimas en secuencia; y de productos distintos | Permitidas |

### 13.3 Reconocimiento y esquema

| Id | Clase | Caso | Esperado |
|---|---|---|---|
| `EJ-09` | D | `reconocer` sobre cada estado, ajena, inexistente | `'reconocida'`; `PT409 intencion_no_confirmada`; `PT404` indistinguible |
| **`RX-01`** | D | **Reconocimiento cruzado entre actores.** (a) Actor B de la misma empresa y actor de otra empresa llaman `reconocer` con el id de A. (b) A nivel de base, como `propietario_rpc` con una función de prueba: `INSERT` con `actor_id` ≠ `usuario_actual()`; y con `actor_id` correcto pero `operacion_id` de otra intención | (a) `PT404`, sin fila. (b) `42501` por política; y `23503` por FK; ninguna fila creada |
| `AU-06` | D | Perfil inactivo **antes de `reconocer`** (sobre una confirmada) | `PT403`; sin fila |
| `AU-07` | D | Perfil inactivo **antes de `listar`** | `PT403` (`PT401` sin identidad); **nunca** lista vacía ni fila vacía |
| `RC-03` | D/S | **`reconocer` nunca mueve stock:** antes/después, conteos y contenido de `operaciones`, `movimientos_stock`, `stock_actual` e `intenciones_operacion` idénticos; estático: el cuerpo no referencia esas tablas ni las RPC de negocio | Cumple |
| `CC-08` | D/E | Dos `reconocer` simultáneos | 1 fila; **misma marca antes y después** |
| `RC-02` | F | `reconocer` con respuesta perdida (Playwright aborta la respuesta tras el commit) | Reintento idempotente, o reaparece en `sin_resolver` |
| `RF-05` | D | `operacion_id` nulo o de otra intención; `INSERT` con `reconocido_en` | Rechazado por `NOT NULL`, FK o privilegio |
| `RF-06b` | D | `select count(*) from operaciones where id = idempotency_key` | 0 |
| `RF-06c` | S | Ninguna función inserta `id` en `operaciones` (`pg_proc.prosrc`) | Cumple |
| `RF-07` | D | `UNIQUE`: dos intenciones con la misma operación | Rechazado |
| `FK-N` | D | FK a `UNIQUE` con columna anulable: una pendiente (`operacion_id` NULL) ni la viola ni es referenciable | Cumple |
| `OC-1` | D | `INSERT … ON CONFLICT DO NOTHING` bajo RLS real y privilegio por columna | Idempotente; primera marca conservada |
| `ES-01/02/02b/04` | D | Tablas, PK, FK, `UNIQUE`; ACL exacta de ambas tablas (incluido `has_any_column_privilege`); `propietario_rpc` solo `SELECT` e `INSERT` de 3 columnas en la nueva; las 10 funciones: owner, `proconfig`, ACL, sin sobrecargas, pg_temp | Exactos |
| `ES-06` | D | Preflight actualizado pasa con el recuento real y **falla** ante 4.ª política `UPDATE`, ACL indebida o excepción generalizada | Cumple |

### 13.4 Listado

| Id | Clase | Caso | Esperado |
|---|---|---|---|
| `LM-03'` | D | Partes, orden, ventanas, una fila, arreglos vacíos | Exacto |
| `LS-01` | D | Forma de la respuesta **por PostgREST** | Un arreglo de un objeto con las 6 columnas |
| `LM-08` | D | Sin resolver antigua con más de 100 posteriores | Listada; bloquea |
| `LM-11` | D | Fixture de 51 | 50, `truncado = true`; `crear` rechazado (`PT409`/`PT429`); vaciado progresivo hasta 0 |
| `LM-12` | S/E | Una sola sentencia; transiciones durante la lectura | Sin duplicar entre partes |

### 13.5 Seguridad negativa (las 5 RPC y las 2 tablas)

| Id | Clase | Caso | Esperado |
|---|---|---|---|
| `NG-01` | D | `anon` en las 5 RPC | `42501` |
| `NG-02` | D | **Rol incorrecto** (vendedor/piloto) en las 5 RPC | `PT403` |
| `NG-03` | D | **Usuario inactivo** en las 5 RPC | `PT403`; en `listar`, error, no lista vacía |
| `NG-04` | D | **Otra empresa / otro actor** en `ejecutar`, `cancelar`, `reconocer`; `listar` solo devuelve lo propio; `crear` no ve lo ajeno | `PT404` indistinguible |
| `NG-05` | D | `GET/POST/PATCH/DELETE` y `select=` sobre ambas tablas, cada rol | `42501`; nunca `200 []` |
| `NG-06` | D | `service_role` | Sin `EXECUTE` ni privilegios |
| `NG-09` | D | Fachadas funcionan para dueño y encargado sin privilegio de tabla; privadas no invocables por `anon`/`service_role` | Cumple |

### 13.6 Frontend (después de la aprobación normativa)

**Vitest:** `VT-04/VT-05` (`PT500` y `PT404` de `ejecutar` no dan `no_creada`; `sin_resolver`; dos acciones idénticas solo en secuencia); `VT-08` (reconocimiento: orden, pérdida, reintento antes de `crear`); `VT-09` (parser de `listar`: **las diez respuestas fuera de contrato de §7.3** y la forma válida; nunca lista vacía); `VT-10` (ruta única y ausencia de los tres nombres en `dist/`, solo si se aprueba D-IDEM-17). **Playwright:** `PW-01` (respuesta perdida, recarga, otro contexto: un solo movimiento y reconocimiento antes de crear); `PW-08` (dos dispositivos: `PT409`, recuperación, orden texto → solicitud); más de 100 en el historial.
**F1/F2** (código preparatorio de Claude-VM, sin commit) implementan C-mínima: **se adaptan solo después de la aprobación normativa**; no se modifican ahora.

### 13.7 Verificaciones de cierre

`supabase test db` y el arnés de concurrencia en stack descartable; **preflight T3-01 recalculado sobre la futura línea de integración**; `npm run typecheck`, `npm test`, `npx playwright test`, `npm run lint`, `npm run build`; security review; auditoría independiente de Codex y OpenCode sobre un hash; aprobación humana.

### 13.8 Laboratorio mínimo recomendado antes de la enmienda definitiva (requiere autorización; **no autorizado**)

`SD-02`, `SD-03`, `CC-09`, `CC-11`, `SIM-01`, `CL-01`; FK a `UNIQUE` con columna anulable; `ON CONFLICT DO NOTHING` bajo RLS real y primera marca; `AU-03`, `TT-01` (clase I), `H1-P2`, `LK-01`; forma de la respuesta por PostgREST.

### 13.9 Mutantes de sensibilidad [NO EJECUTADO]

Cada mutante se aplica a una copia descartable de la implementación; **debe hacer fallar al menos la prueba indicada**. Un mutante que sobrevive indica una prueba inadecuada y bloquea la aceptación.

| Id | Mutante | Debe detectarlo |
|---|---|---|
| `M-01` | Compuerta partida en dos sentencias | `ES-05` (S); `LM-05'` (E, estadístico) |
| `M-02` | Compuerta/replay sin `perfiles` (sin autorización en la sentencia) | `AU-04`, `AU-05`, `ES-05` |
| `M-03` | O3b ausente (0 filas → `PT404`) | `SD-02`, `CC-09`, `TT-01` |
| `M-04` | `PT404` tras haber visto la fila (O3b con `PT404`) | `CC-09`, `TT-01` |
| `M-05` | O3b con pendiente → continuar en lugar de `PT500` | `SD-03` |
| `M-06` | O3b sin comprobación de autorización (siempre `PT500`) | `AU-03` (I) |
| `M-07` | `cancelar` sin la relectura de O3b (asimétrico) | `SIM-01`, `CL-01` |
| `M-08` | `listar` devuelve fila vacía/lista vacía sin autorización | `AU-07`, `NG-03` |
| `M-09` | `reconocer` toma `actor_id` del parámetro o no filtra por actor | `RX-01`, `NG-04` |
| `M-10` | `reconocer` sin comprobar `confirmada` | `EJ-09` (esperaba `PT409`, el esquema da `23502`) |
| `M-11` | Política `INSERT` de reconocimientos sin predicado de actor | `RX-01(b)` |
| `M-12` | Falta la `UNIQUE` de `operacion_id` | `RF-07` |
| `M-13` | Fachada `STABLE` | `H1-P3` |
| `M-14` | `ejecutar`/`cancelar` sin la comprobación de aislamiento | `R13-E` |
| `M-15` | `reconocer` invoca una RPC de negocio | `RC-03` |
| `M-16` | Orden compuerta → replay | `LM-07'` |
| `M-17` | Tope de `crear` en 60 (> 50) | `LM-11` |
| `M-18` | Cuarta política `UPDATE` permisiva | `ES-03b`, `ES-06a` |
| `M-19` | Orden `FOR UPDATE` primero (v0.1/VM) | **Solo** `ES-05` (S); sin detección dinámica externa |

---

## 14. RIESGOS RESIDUALES

### 14.1 Riesgos de v1.0 que cambian

| Riesgo v1.0 | Cambio |
|---|---|
| **R-1** dos intenciones idénticas a propósito | Reformulado: dos **actores** pueden registrar la misma operación (D-IDEM-12); no se ven ni se bloquean. Requiere aceptación escrita |
| **R-2** bypass por RPC directas | Sin cambio de tratamiento: aceptado temporalmente en Fase 1 (D-IDEM-8); se cierra solo con D-IDEM-13 |
| **R-3** superficie `SECURITY DEFINER` | **Se agrava:** cinco funciones privadas y cinco fachadas, más una tabla |
| **R-4** dos viajes de red por operación | **Se agrava:** tres viajes (`crear`, `ejecutar`, `reconocer`) |
| **R-6** solicitud retrasada junto con una nueva idéntica | **Se reduce:** la nueva no se crea mientras la anterior siga sin resolver; subsiste por la pestaña desactualizada (R-30) |
| **R-9** admitida antes de `vence_en` que confirma después | Sin cambio; ahora además bloquea su tipo hasta conocer el estado |
| **R-14** invariante `idempotency_key = id` no expresable por FK | Sin cambio; la `UNIQUE` agrega la 1:1 operación ↔ intención |
| **R-17** topes bajo concurrencia | **Cambia:** la exactitud la da el nivel 0 más la compuerta; `LM-05'`/`LM-06'` |
| **R-18** el lock serializa los `crear` del actor | **Se agrava:** además, las operaciones del mismo tipo se serializan por la compuerta (R-26) |
| **R-20** excepción A del preflight mal escrita | Ahora para **dos** tablas; igual mitigación (nombre literal, N-COL) |
| **R-22** cambio de versión de PostgreSQL/PostgREST | Se agregan `SD-02`, `LK-01` y la forma de `listar` a las pruebas a repetir |

### 14.2 Riesgos nuevos

| Id | Riesgo | Tratamiento |
|---|---|---|
| **R-23** | `FOR UPDATE` filtrado por RLS sin relectura devolvería `PT404` sobre intenciones existentes | Corregido en §4.2; pendiente de `SD-02` |
| **R-24** | **Cliente que reconoce sin mostrar el resultado** | No eliminable; Playwright lo controla; el reconocimiento no equivale a lectura humana. **Aceptación humana** |
| **R-25** | Reconocimiento perdido | Solo repite un aviso (falso positivo seguro) |
| **R-26** | **Fricción por tipo y viajes de red:** operaciones del mismo tipo se serializan aunque sean de productos distintos; tres viajes por operación; sin conexión tras enviar se bloquea ese tipo hasta recuperar; una vencida bloquea su tipo hasta descartarla | **Sin medir.** **Aceptación humana** (DH-06) |
| **R-27** | La cardinalidad ≤ 3 de `sin_resolver` es un **argumento** (ninguna restricción la impone) | Tope defensivo 50, `sin_resolver_truncado` y bloqueo seguro (§7.3) |
| **R-28** | `operaciones.id ≠ idempotency_key` es propiedad de implementación | `RF-06b/c`; riesgo si una RPC futura asigna `id` desde la clave |
| **R-29** | **Pérdida de autorización posterior a la última validación:** bajo `READ COMMITTED` un perfil inactivado o un rol cambiado después de la última sentencia de validación no se detecta | Efectos acotados (§4.8); sin garantía más allá del snapshot. **Aceptación humana** (DH-07, DH-13) |
| **R-30** | **Pestaña desactualizada con intención no registrada:** una pestaña en `desconocido` que reintenta un id nunca registrado, tras haberse resuelto la operación en otra pestaña, puede crear un duplicado con acción explícita | La compuerta lo reduce pero no lo elimina. **Aceptación humana** |
| **R-31** | Rol perdido con algo sin resolver | `PT403` en todas las RPC; sigue disponible si se reactiva |
| — | Cifras del preflight derivadas por aritmética sobre otra línea | Recuento obligatorio (§12) |
| — | `registrar_carga`/`registrar_descarga` con clave en memoria | Fuera de ADR-010; **no evaluado** |
| — | Todo el diseño de C-VM es argumento hasta ejecutar §13 | — |

---

## 15. TABLA DE CAMBIOS NORMATIVOS

> Todo lo siguiente son **cambios PROPUESTOS**. **No se editó** ADR-010 v1.0, ADR-001 ni `BLUEPRINT.md`; el Blueprint v2.6 vigente describe `intenciones_operacion` tal como se aprobó el 06/11/2026.

### 15.1 Cláusulas de ADR-010 v1.0 que se **modifican**

| # | Cláusula v1.0 | Cambio propuesto | Paquete |
|---|---|---|---|
| 1 | Encabezado: estado, versión, historial | Versión 1.1; fila de historial | — |
| 2 | §0.2 #3 (D-IDEM-15) | Alternativa A y excepción nominal/N-COL se extienden a `intenciones_reconocimientos` | C |
| 3 | §0.2 #7 (D-IDEM-5b) y §5.13 | «20 pendientes vigentes» → «20 sin resolver, todos los tipos y vigencias» (defensa) | C |
| 4 | §0.2 #9 (D-IDEM-5c) y §5.13 «Listado» | 100 filas totales → `sin_resolver` ≤ 50 sin ventana + `historial` ≤ 100 con 7/30 días | C |
| 5 | §0.3 (1), (8), (9), (10) | **Cinco** funciones privadas y **cinco** fachadas; ACL/políticas de la 2.ª tabla; conteos; pruebas nuevas | C |
| 6 | §5.1 R-13 | `ejecutar`/`cancelar` también fallan cerrado fuera de `READ COMMITTED`; privadas y fachadas `VOLATILE` | H |
| 7 | §5.2 | Agrega la `UNIQUE` `intenciones_operacion_operacion_unica` y la tabla `intenciones_reconocimientos` | C |
| 8 | §5.3 | Transición sobre fila obtenida con `FOR UPDATE`; terminal legible sin bloqueo; define «sin resolver» (derivado) | H, C |
| 9 | §5.5 (tabla de RPC) | `cancelar` según §4.2–4.3; `listar` según §7 (fila única, `PT403` sin autorización); fila `reconocer`; errores `PT409 intencion_sin_resolver` e `intencion_no_confirmada`; significado de `PT404`; «cinco funciones» | H, C |
| 10 | §5.5.1 | Pasos 2, 5 y 5b con autorización en la misma sentencia; compuerta; topes sobre sin resolver; orden replay → compuerta → topes | C |
| 11 | §5.6 pasos 2, 3 y 4 | Reemplazados por O1–O3b y O4 (§4.2–4.3); pasos 1, 5, 6 y 7 **intactos** | H |
| 12 | §5.8 | Nivel 1 solo cuando la lectura inicial encontró `pendiente`; nota sobre `FOR UPDATE` filtrado; `reconocer` sin locks | H, C |
| 13 | §5.9 | Se agrega que la autorización se determina en la misma sentencia que la lectura y el alcance de §4.8; el resto **intacto** | H |
| 14 | §5.10 | Exactamente 3 políticas en `intenciones_operacion`; prohibición de UPDATE permisiva; permisos y RLS de la 2.ª tabla | H, C |
| 15 | §5.12 | `reconocer` aplica P13; `PT409` nuevos no se reintentan | C |
| 16 | §5.14 | La restricción pasa de interfaz a servidor; flujo del cliente con `reconocer`; sin «crear otra igual» | C |
| 17 | §3 (fila D2) | Nota: la compuerta no reutiliza tickets; demora una operación legítima, no la pierde | C |
| 18 | §6 (dos filas) | «El actor no crea otra intención de un tipo con algo sin resolver \| PostgreSQL (compuerta)»; operaciones idénticas legítimas «**en secuencia**» | C |
| 19 | §7.1 | **Solo** se agrega el control «referencia `operaciones.id`, no la clave»; la extensión de P15 no cambia | C |
| 20 | §8.1, §8.2, §8.2.1 | Cifras 50/25/13/38 (a recontar); lista 3.4, inventario 3.7, siete bloques +1 relación, excepción y N-COL para la 2.ª tabla | C |
| 21 | **§10.B** | Casos redefinidos: `LM-01`→`LM-01'`, `LM-03`→`LM-03'`, `LM-05`→`LM-05'`, `LM-06`→`LM-06'`, `LM-07`→`LM-07'`, `CC-04`→`CC-04'`, `VT-05`, `NG-01/02/03/04/05`; casos pasados a SD y RLS reales: `EJ-02/06/07`, `CC-01/02`, `VE-03`, `RC-01`, `SD-01`; casos nuevos de §13 | H, C |
| 22 | **§10.C** | Criterio 3: incluye que una confirmada sin reconocer bloquee su tipo y que `reconocer` nunca mueva stock. Criterio 8: cifras 50/25/13/38 y excepción A para las dos tablas. Criterio 10: «los topes por actor son exactos bajo concurrencia (`LM-05'`, `LM-06'`) y ninguna función nueva llama a `auth.uid()` (`ES-05`)». **Criterio nuevo:** autorización en la misma sentencia (`AU-01…AU-07`, mutantes `M-02`, `M-08`) | H, C |
| 23 | §11 | Riesgos según §14 | H, C |
| 24 | §12 | `D-IDEM-18` (paquete H), `D-IDEM-19` (paquete C), `D-IDEM-17` (ruta única; **propuesta**). `D-IDEM-13` **sin cambios** | — |

### 15.2 Disposiciones que se **agregan**

Autorización en la misma sentencia (H-R6, §4.1); procedimiento común O1–O3b (§4.2); alcance de la validación de autorización (§4.8); compuerta (§5.2); definición de «sin resolver» (§5.1); RPC `reconocer_intencion_operacion` (§6.4); tabla `intenciones_reconocimientos` y `UNIQUE` (§6.2–6.3); contrato de `listar` y respuestas fuera de contrato (§7); tope defensivo y bloqueo seguro (§7.3); prohibición de UPDATE permisiva adicional (§4.6); ruta única de B-01 (§10, propuesta).

### 15.3 Lo que queda **intacto** de v1.0

§1, §2 (salvo lo agregado), §4 (decisión C-mínima), **§5.4** (payload canónico, 4096 bytes, `jsonb`), **§5.7** (lista cerrada de rechazos de negocio y su HTTP 200), **§5.9** (salvo la precisión de §15.1 #13), **§5.11**, reglas R-01 a R-12 de §5.1, §5.6 pasos 1, 5, 6 y 7 (admisión por plazo con `clock_timestamp()`, bloque protegido de alcance mínimo, lista cerrada), vencimiento de 24 h, retención indefinida, 120 creaciones/h, `motivo` ≤ 500, visibilidad exclusiva del actor, tres tipos, D-IDEM-7, D-IDEM-8, D-IDEM-13 **pendiente**, §9, §13. **Intactos también:** `operaciones`, `movimientos_stock`, las RPC de stock y de jornadas, ADR-001 (estado y decisiones), P11, O-3/O-4, roles técnicos, **todos los permisos vigentes**.

### 15.4 Documentos que requerirían actualización normativa futura (solo con aprobación humana; **no se editó nada**)

| Documento | Cambio **propuesto** (no realizado) |
|---|---|
| **`BLUEPRINT.md` §8** | **Sí requiere** actualización: la entidad `intenciones_operacion` suma la `UNIQUE (empresa_id, actor_id, operacion_id)` y se registra la entidad `intenciones_reconocimientos` (por `operacion_id`). v2.6 **no** lo contiene |
| **`BLUEPRINT.md` §12** | **Sí requiere** actualización: el ítem «Los límites por actor (20 pendientes, 120 creaciones por hora) se cumplen exactamente bajo concurrencia» pasa a «El actor no tiene más de una intención sin resolver por tipo; el tope defensivo de 20 sin resolver y el de 120 creaciones por hora se cumplen exactamente bajo concurrencia»; se agregan ítems de compuerta, reconocimiento, listado con `sin_resolver`, autorización en la misma sentencia y `reconocer` sin efecto sobre stock. v2.6 **no** lo contiene |
| `BLUEPRINT.md` §17 | Fila de historial de la versión que lo incorpore |
| `BLUEPRINT.md` §7.9.1 | **No cambia** |
| ADR-001 §18.3 (remisión) | **No cambia** (la extensión de P15 no se amplía); a confirmar al aprobar |
| `docs/decisions/README.md` | Estado de ADR-010 v1.1 una vez aprobada |
| `AGENTS.md`, `CLAUDE.md` | Sin cambios previstos |

---

## 16. DECISIONES HUMANAS

### 16.1 Ya decidido por el responsable (dirección normativa; **no** es aprobación de este texto)
- Aprobó como **dirección normativa** los paquetes **H** y **C** (corrección de H1, compuerta, recuperación durable, reconocimiento persistente, listado separado).
- Aprobó las condiciones: autorización `PT403` ante pérdida de autorización, integridad referencial por `operacion_id`, recuperación durable, reconocimiento persistente, y **pruebas reales de RLS y concurrencia**.
- Autorizó **exclusivamente** preparar este borrador y su corrección.

### 16.2 NO autorizado (sigue vigente)
Aprobar ADR-010 v1.1; implementar; migraciones; RPC; cambios de esquema, RLS o permisos; laboratorios; integración de ramas; staging; producción; push; merge; deploy.

### 16.3 Decisiones que seguirán requiriendo aprobación definitiva para aprobar v1.1

| Id | Decisión | Recomendación del borrador |
|---|---|---|
| **DH-01** | Aprobar el **texto** del paquete H: O1–O3b, O4, códigos y condiciones (§4.2–4.5) | Aprobar |
| **DH-02** | Confirmar la prohibición de políticas UPDATE permisivas adicionales (§4.6) | Aprobar |
| **DH-03** | Aprobar el **texto** del paquete C: compuerta con autorización, sin «crear otra igual», vencidas que bloquean, listado con tope 50 y respuestas fuera de contrato | Aprobar |
| **DH-04** | Modificación de **D-IDEM-5b** (20 sin resolver, todos los tipos y vigencias) y **D-IDEM-5c** (listado en dos partes) | Aprobar |
| **DH-05** | Ampliar la excepción nominal A y N-COL de **D-IDEM-15** a `intenciones_reconocimientos` | Aprobar |
| **DH-06** | Aceptar la **fricción por tipo** y el tercer viaje de red (R-26); o replegar a la compuerta solo sobre pendientes (sin tabla), dejando la confirmada con respuesta perdida como residual aceptado por escrito | Aprobar C-VM |
| **DH-07** | Aceptar por escrito los **residuales**: R-1 (dos actores), R-30 (pestaña desactualizada), R-24 (cliente que reconoce sin mostrar), R-29 (pérdida de autorización posterior a la última validación) y R-2 (bypass, ya aceptado para Fase 1). Sin esto D-IDEM-0 no puede cerrarse | Aceptar |
| **DH-08** | **D-IDEM-17**: la ruta única de B-01 como condición de cierre de D-IDEM-0 (§10) — *propuesta* | Aprobar |
| **DH-09** | **D-IDEM-13** queda **fuera de la aprobación de v1.1** y sin alterar permisos: decidir cuándo y cómo (ADR propia) | Mantener separada |
| **DH-10** | **D-IDEM-7:** si el cierre local de T3-01-L (solo `6c45cbd0`) alcanza para habilitar la implementación y **sobre qué línea** se integra | Decidir al autorizar la implementación |
| **DH-11** | Autorizar (o no) el **laboratorio mínimo** de §13.8 antes de la enmienda definitiva | Autorizar |
| **DH-12** | Actualización de `BLUEPRINT.md` §8/§12/§17 y de `README.md` al aprobar (§15.4) | Con la aprobación |
| **DH-13** | Aceptar el **alcance de la validación de autorización** de §4.8 (sin garantía más allá del snapshot) y no adoptar el `FOR SHARE` sobre `perfiles` | Aceptar |

(El antiguo punto H-3 del borrador v0.1 queda **resuelto** por la autorización en la misma sentencia, §4.2; la carrera residual se trata en DH-13.)

### 16.4 Conflictos normativos todavía abiertos
1. Modificación de D-IDEM-5b/5c (§0.2 #7 y #9 de v1.0): texto por aprobar.
2. Restricción de interfaz → servidor (§5.14, §6, §3 D2 de v1.0): texto por aprobar.
3. Extensión de D-IDEM-15 a la 2.ª tabla.
4. `BLUEPRINT.md` §8 y §12 requieren actualización futura (no realizada).
5. Cifras del preflight por recontar sobre otra línea.
6. D-IDEM-17 sin aprobar; D-IDEM-13 pendiente y fuera de v1.1.
7. `operaciones.id ≠ idempotency_key`: propiedad de implementación (no de esquema).
8. T3-01-L está cerrado solo localmente para `6c45cbd0`; T3-01-R y la integración no están autorizados.

---

## 17. Lo que este borrador no hace

No modifica ADR-010 v1.0, ADR-001, `BLUEPRINT.md`, F1/F2, migraciones, RPC, RLS, permisos ni esquema. No implementa, no ejecuta laboratorios, no crea commits, no accede a staging ni producción, no hace push, merge ni deploy. **Ninguna prueba propuesta se ejecutó.** **No declara resuelta D-IDEM-0** ni aprueba la v1.1: B-01 sigue abierta (D-IDEM-0, v1.0 §1.4).
