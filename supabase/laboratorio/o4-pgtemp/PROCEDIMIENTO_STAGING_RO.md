# Procedimiento de inventario READ ONLY de staging (O-4) — BORRADOR, NO AUTORIZADO

**Estado:** diseño. Las consultas `consultas_ro/Q0–Q6` se validaron **sólo en laboratorio local descartable** (`probar_consultas_ro.sh`). Este procedimiento **no autoriza** ninguna conexión a staging ni a producción: cada ejecución remota requiere autorización humana explícita, nominada y vigente. Aplica a ADR-001 §18.2.1 (contrato RB + RA). No aplica migraciones.

## 0. Autorización previa (el humano debe dejarla escrita)
- Entorno: **staging**, project-ref `rtsncntppghdynzhezzg` (el registrado en ADR-001 §18.2 como evidencia de staging). Producción queda fuera.
- Quién ejecuta, desde qué máquina y con qué rol de base. Preferir un rol **de solo lectura**; Q0–Q6 funcionan sin privilegios especiales (verificado como `authenticated` en laboratorio).
- Vigencia (fecha y hora) de la autorización.

## 1. Identificación inequívoca del proyecto (antes de la primera consulta)
Se exige **todo** lo siguiente; si algo no coincide, se detiene sin ejecutar nada:
1. El humano escribe el project-ref esperado; debe ser idéntico a la constante de arriba y estar contenido en el host de conexión (`db.<ref>.supabase.co`) o en el usuario del pooler (`postgres.<ref>`). No se aceptan alias, variables de entorno heredadas ni cadenas de conexión pegadas sin revisar.
2. La conexión usa sólo `PGHOST`/URL explícitos del paso anterior (se limpian `PGSERVICE`, `PGSERVICEFILE`, `DATABASE_URL`, `SUPABASE_DB_URL`).
3. Q0 debe informar `solo_lectura = on` y `version_num / 10000 = 17`.
4. **Huella de identidad en dos lecturas:** el `system_identifier` de Q0 se registra la primera vez y debe ser idéntico en toda lectura posterior. Una lectura posterior con otro valor aborta (puede ser otro proyecto o una restauración).
5. Q4 debe listar un historial de migraciones consistente con lo documentado para staging (ADR-001 §18.2: 6 migraciones presentes al 24/10/2026, incluida `20261024180000`). Un historial inesperado aborta.
6. El humano confirma por escrito el valor de `system_identifier` y el project-ref antes de pasar a Q1–Q6.

## 2. Ejecución (sólo si la autorización lo permite)
- Todo dentro de `BEGIN READ ONLY; …; ROLLBACK;` (ver `probar_consultas_ro.sh`, función `ro`). Una escritura dentro de la transacción falla (control verificado en laboratorio).
- Orden: Q0 → Q4 (identidad) → Q1, Q2, Q3, Q5 → Q6 con `-v estado_esperado=original` (estado actual esperado en staging, cuerpo `325ae266…`) o `remediado` (después de una migración autorizada).
- Cada salida se guarda con su SHA-256, hora y rol de conexión. Sin `.env*` ni credenciales en la evidencia.

## 3. Criterios de abortar (los calcula Q6; cualquier texto en `abortar` detiene todo)
Ver `consultas_ro/Q6_veredicto.sql`: transacción no read-only; motor distinto de 17; función ausente o con homónimos; owner distinto de `postgres`; no `SECURITY DEFINER`; `prokind`, lenguaje, retorno, `prosqlbody` o `probin` inesperados; SHA-256 o `proconfig` distintos del estado esperado; EXECUTE para PUBLIC, `anon`, `authenticated` o `service_role`; trigger de tabla sobre la función; `ensure_rls` ausente, duplicado, con otro event trigger, owner, evento, estado (`O`) o tags distintos de las tres exactas; tabla de `public` sin RLS. **Además** (decisión humana, no automática): cualquier rol con LOGIN no reservado y con TEMP (`revisar_login_con_temp` de Q6) y cualquier salida que no pueda interpretarse.

## 4. Paridad de versión (no la resuelve SQL)
Q0/Q4 confirman el motor (17.x) y las extensiones. La **imagen** (`.003` registrada para el remoto vinculado frente a `.004` local) sólo se confirma desde el panel de infraestructura o la API de gestión de Supabase, lo que requiere credenciales y autorización aparte.

## 5. Después de la lectura
Un resultado `ESTADO_A` del preflight completo, corrido también en `BEGIN READ ONLY` y **sin marcador**, es condición necesaria pero no suficiente. La migración sigue sin autorizar hasta que se resuelvan F7, F8 (decisión B/C con evidencia), H-04, PB12C y la security review.
