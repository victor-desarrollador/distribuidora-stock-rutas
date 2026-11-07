# Procedimiento de inventario READ ONLY de staging (O-4) — BORRADOR, NO AUTORIZADO

**Estado:** diseño. Las consultas `consultas_ro/Q0–Q6` se validaron **sólo en laboratorio local descartable** (`probar_consultas_ro.sh`). Este procedimiento **no autoriza** ninguna conexión a staging ni a producción: cada ejecución remota requiere autorización humana explícita, nominada y vigente. Aplica a ADR-001 §18.2.1 (contrato RB + RA). No aplica migraciones.

## 0. Autorización previa (el humano debe dejarla escrita)
- Entorno: **staging**, project-ref `rtsncntppghdynzhezzg` (el registrado en ADR-001 §18.2 como evidencia de staging). Producción queda fuera.
- Quién ejecuta, desde qué máquina y con qué rol de base. Preferir un rol **de solo lectura**; Q0–Q6 funcionan sin privilegios especiales (verificado como `authenticated` en laboratorio).
- Vigencia (fecha y hora) de la autorización.

## 1. Identificación inequívoca del proyecto (fail-closed)
La identidad se verifica contra datos obtenidos **antes y por un canal independiente de la conexión que se va a usar**. **Nunca** se acepta un `system_identifier` "aprendido" de la propia conexión (si la conexión apuntara a otro destino, lo aprendería y lo daría por bueno).
1. **Canal independiente (lo hace el humano, antes de ejecutar nada):** desde su sesión autenticada del panel del proyecto, anota el project-ref y ejecuta allí, en solo lectura, `select system_identifier from pg_control_system();`. Esos dos valores, y el archivo de CA del proyecto, son la "ficha de identidad". No provienen de variables de entorno, del repositorio ni de la salida de esta herramienta.
2. **Ejecutor único:** `ejecutar_inventario_ro.sh` (no se usa `psql` a mano). Recibe `--ref` y `--sysid` de la ficha, exige host exactamente `db.<ref>.supabase.co`, `sslmode=verify-full` con `--sslrootcert`, nunca `hostaddr`, y valida formatos antes de tocar la red.
3. **Entorno libpq limpio:** elimina todas las variables `PG*`, `PSQL*` y `LIBPQ*` heredadas (incluidos `PGHOSTADDR`, `PGSERVICE`, `PGOPTIONS`, `PGSSLMODE`, `PGPASSFILE`) y fija valores explícitos y seguros. Informa los nombres eliminados.
4. **psql seguro:** `psql -X -v ON_ERROR_STOP=1`; una sola sesión en `BEGIN READ ONLY … ROLLBACK`; la guardia `Q00` se ejecuta **primero** y aborta (rc 3) si falta una variable, la transacción no es de solo lectura, el motor no es 17, el `system_identifier` o la base no coinciden con la ficha, o el estado esperado es inválido. No imprime el valor real encontrado.
5. **Historial de migraciones (Q4)** y la versión del motor se comparan después con lo documentado; son señales adicionales, no sustituyen la ficha.
6. El humano confirma por escrito la ficha y la autorización vigente antes de la primera ejecución. Sin ficha, no se ejecuta.

## 2. Ejecución (sólo si la autorización lo permite)
- Orden dentro de la sesión: Q00 → Q0 → Q1 → Q2 → Q3 → Q4 → Q5 → Q6 con `--estado original` (estado actual esperado en staging, cuerpo `325ae266…`) o `remediado` (después de una migración autorizada).
- Cada salida se guarda con su SHA-256 (`--evidencia`), hora y rol de conexión. Sin `.env*` ni credenciales en la evidencia. La contraseña se ingresa por el prompt de psql; no se guarda.

## 3. Compuertas y criterios de abortar (los calcula Q6; cualquier texto en `abortar` detiene todo; rc 4)
Ver `consultas_ro/Q6_veredicto.sql`: transacción no read-only; motor distinto de 17; función ausente o con homónimos; owner distinto de `postgres`; no `SECURITY DEFINER`; `prokind`, lenguaje, retorno, `prosqlbody` o `probin` inesperados; SHA-256 o `proconfig` distintos del estado esperado; EXECUTE para PUBLIC, `anon`, `authenticated` o `service_role`; trigger de tabla sobre la función; `ensure_rls` ausente, duplicado, con otro event trigger, owner, evento, estado (`O`) o tags distintos de las tres exactas; tabla de `public` sin RLS.

**Compuerta obligatoria LOGIN+TEMP.** Todo rol con LOGIN y privilegio TEMP sobre la base entra en la revisión, **incluidos los roles reservados de la plataforma y los superusuarios**: ser rol de plataforma no implica seguridad (O4-PGTEMP).
1. La primera ejecución, sin `--revision-login-temp`, **aborta** (rc 4) y Q1/Q6 muestran la lista y su huella (`digest_login_temp`).
2. El humano revisa la lista de Q1 (atributos: superusuario, creación de roles y bases, replicación, BYPASSRLS, reservado) y decide, por escrito, si cada rol es aceptable.
3. Sólo entonces se vuelve a ejecutar con `--revision-login-temp <huella>`. Si cambia cualquier rol o atributo, la huella cambia y la revisión previa deja de valer.
4. La huella no es una aprobación: es la constancia de qué lista se revisó. Qué se hace con un rol no aceptable (revocar TEMP, cambiar el rol, etc.) es una decisión humana aparte y **no** forma parte de este inventario.

## 4. Paridad de versión (no la resuelve SQL)
Q0/Q4 confirman el motor (17.x) y las extensiones. La **imagen** (`.003` registrada para el remoto vinculado frente a `.004` local) sólo se confirma desde el panel de infraestructura o la API de gestión de Supabase, lo que requiere credenciales y autorización aparte.

## 5. Después de la lectura
Un resultado `ESTADO_A` del preflight completo, corrido también en `BEGIN READ ONLY` y **sin marcador**, es condición necesaria pero no suficiente. La migración sigue sin autorizar hasta que se resuelvan F7, F8 (decisión B/C con evidencia), H-04, PB12C y la security review.
