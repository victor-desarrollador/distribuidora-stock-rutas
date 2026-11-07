# Procedimiento de inventario READ ONLY de staging (O-4) — BORRADOR, NO AUTORIZADO

**Estado:** diseño. Las consultas `consultas_ro/Q0–Q6` se validaron **sólo en laboratorio local descartable** (`probar_consultas_ro.sh`). Este procedimiento **no autoriza** ninguna conexión a staging ni a producción: cada ejecución remota requiere autorización humana explícita, nominada y vigente. Aplica a ADR-001 §18.2.1 (contrato RB + RA). No aplica migraciones.

## 0. Autorización previa (el humano la deja escrita; sin ella no se ejecuta nada)
- Entorno: **staging**, project-ref `rtsncntppghdynzhezzg` (el registrado en ADR-001 §18.2 como evidencia de staging). Producción queda fuera.
- Quién ejecuta, desde qué máquina y con qué **rol de lectura propio** (nunca `postgres` ni `supabase_admin`; la guardia Q00 lo rechaza). Vigencia (fecha y hora).
- **Dependencia NO definida (pendiente de decisión humana):** el privilegio que necesita ese rol para leer `supabase_migrations.schema_migrations` (USAGE sobre el esquema y SELECT sobre la tabla). Hasta que se defina, Q4 informa "DEPENDENCIA PENDIENTE" y el historial **no se verifica**; no se otorga ningún privilegio ni se usa `postgres` como sustituto. Q00–Q6 restantes se ejecutaron con un rol LOGIN sin privilegios en laboratorio.

## 1. Identificación inequívoca del proyecto (fail-closed)
La identidad se verifica contra una **ficha aprobada ANTES y por un canal independiente de la conexión que se va a usar**. Nunca se acepta un valor "aprendido" de la propia conexión, y los parámetros de ejecución no son su propia fuente de confianza.
1. **Ficha (la escribe el humano a partir de su sesión autenticada del panel del proyecto, en solo lectura):** `FICHA_VERSION=1`, `MODO=remoto`, `HOST=db.<ref>.supabase.co`, `PORT=5432`, `PROJECT_REF`, `SYSTEM_IDENTIFIER` (de `select system_identifier from pg_control_system();` ejecutado allí), `DBNAME`, `DBUSER` (el rol de lectura) y `CA_SHA256` (SHA-256 del certificado de CA del proyecto). Un archivo `CLAVE=valor`, sin comentarios ejecutables; claves desconocidas, duplicadas o faltantes se rechazan.
2. **La huella de la ficha** (`sha256sum`) la comunica el humano aparte y se pasa con `--ficha-sha256`: una ficha editada después de aprobada no ejecuta. Host, puerto, base, usuario, ref y sysid **no** pueden pasarse por línea de comandos.
3. **Ejecutor único:** `ejecutar_inventario_ro.sh` (no se usa `psql` a mano): valida la ficha y la CA (`--ca`, cuyo SHA-256 debe ser `CA_SHA256`) **antes de conectar**, exige `sslmode=verify-full` y nunca usa `hostaddr`.
4. **Entorno libpq limpio:** elimina todas las variables `PG*`, `PSQL*` y `LIBPQ*` heredadas (incluidos `PGHOSTADDR`, `PGSERVICE`, `PGOPTIONS`, `PGSSLMODE`, `PGPASSFILE`) y fija valores explícitos y seguros; informa los nombres eliminados. `psql -X -v ON_ERROR_STOP=1`; una sola sesión en `BEGIN READ ONLY … ROLLBACK`.
5. **Guardia Q00 primero:** aborta (rc 3) si falta una variable, la transacción no es de solo lectura, el motor no es 17, o no coinciden con la ficha el `system_identifier`, la base, `current_user`, `session_user` y el puerto; también si el usuario es `postgres`, `supabase_admin` o un superusuario. No imprime el valor real encontrado.
6. **Integridad de la evidencia, ANTES de conectar:** el ejecutor exige `--commit-esperado` y `--arbol-esperado` (el commit auditado), registra commit, árbol y SHA-256 de cada archivo del paquete en `vinculo_git.txt`, y **falla** si el HEAD o el árbol son otros, si hay cambios sin commitear o archivos sin seguimiento en el paquete, o si algún archivo difiere de su blob en HEAD. Sin identidad esperada (sólo laboratorio) la evidencia queda declarada **NO vinculada a commit**.
7. **Directorio de evidencia (`--evidencia`):** debe ser **nuevo**, absoluto, fuera del repositorio, sin ningún enlace simbólico en la ruta, con padre propio y no escribible por terceros; se crea 700 y no se sobrescribe nada. Al final se escribe `MANIFIESTO.sha256`.
8. El historial de migraciones (Q4) y la versión del motor son señales adicionales que se comparan con lo documentado; no sustituyen la ficha.
9. El humano confirma por escrito la ficha y la autorización vigente antes de la primera ejecución.

**Límites que este diseño no resuelve:** (a) que la sesión del panel de la que sale la ficha sea realmente la del proyecto correcto es una verificación organizativa; (b) no hay una raíz de confianza criptográfica para la ficha más allá de su huella comunicada por el humano; (c) el arnés no ata criptográficamente una ejecución a un commit más allá de las comprobaciones de arriba.

## 2. Ejecución (sólo si la autorización lo permite)
- Orden dentro de la sesión: Q00 → Q0 → Q1 → Q2 → Q3 → Q4 → Q5 → Q6 con `--estado original` (estado actual esperado en staging, cuerpo `325ae266…`) o `remediado` (después de una migración autorizada).
- La contraseña se ingresa por el prompt de psql; no se guarda. La evidencia no contiene `.env*` ni credenciales.

## 3. Compuertas y criterios de abortar (los calcula Q6; cualquier texto en `abortar` detiene todo; rc 4)
Ver `consultas_ro/Q6_veredicto.sql`: transacción no read-only; motor distinto de 17; función ausente o con homónimos; owner distinto de `postgres`; no `SECURITY DEFINER`; `prokind`, lenguaje, retorno, `prosqlbody` o `probin` inesperados; SHA-256 o `proconfig` distintos del estado esperado; EXECUTE para PUBLIC, `anon`, `authenticated` o `service_role`; trigger de tabla sobre la función; `ensure_rls` ausente, duplicado, con otro event trigger, owner, evento, estado (`O`) o tags distintos de las tres exactas; tabla de `public` sin RLS.

**Compuerta obligatoria LOGIN+TEMP.** Todo rol con LOGIN y privilegio TEMP sobre la base entra en la revisión, **incluidos los roles reservados de la plataforma y los superusuarios**: ser rol de plataforma no implica seguridad (O4-PGTEMP).
1. **Qué se revisa (representación canónica, ordenada y sin delimitadores ambiguos):** un `jsonb` con, por rol, nombre, atributos (superusuario, herencia, creación de roles y bases, replicación, BYPASSRLS), `rolconnlimit`, `rolvaliduntil` (en época, independiente de la zona horaria), `rolconfig` ordenado y las membresías directas con sus opciones (admin, inherit, set); más los patrones de `supautils.reserved_roles` ordenados y, por rol, si coincide **exacto** o por **prefijo literal** (`x*`; sin comodines de LIKE). Q1 imprime ese JSON y su huella SHA-256.
2. La primera ejecución, sin `--revision-login-temp`, **aborta** (rc 4) y muestra la lista y la huella.
3. El humano revisa la lista y decide por escrito si cada rol es aceptable; sólo entonces se ejecuta de nuevo con `--revision-login-temp <huella>`. Si cambia cualquier dato revisado, la huella cambia y la revisión previa deja de valer.
4. **La huella es una fotografía puntual** de ese instante: no demuestra que no hubo cambios transitorios antes o después, ni cubre membresías indirectas ni privilegios heredados más allá de TEMP. **No es una autorización**, ni automática ni diferida: es la constancia de qué lista se revisó. Qué hacer con un rol no aceptable (revocar TEMP, cambiar el rol, etc.) es una decisión humana aparte y no forma parte de este inventario.

## 4. Paridad de versión (no la resuelve SQL)
Q0/Q4 confirman el motor (17.x) y las extensiones. La **imagen** (`.003` registrada para el remoto vinculado frente a `.004` local) sólo se confirma desde el panel de infraestructura o la API de gestión de Supabase, lo que requiere credenciales y autorización aparte.

## 5. Después de la lectura
Un resultado `ESTADO_A` del preflight completo, corrido también en `BEGIN READ ONLY` y **sin marcador**, es condición necesaria pero no suficiente. La migración sigue sin autorizar hasta que se resuelvan F7, F8 (decisión B/C con evidencia), H-04, PB12C y la security review.
