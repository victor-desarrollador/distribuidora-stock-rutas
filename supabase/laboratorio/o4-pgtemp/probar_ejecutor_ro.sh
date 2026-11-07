#!/usr/bin/env bash
# Pruebas del ejecutor ejecutar_inventario_ro.sh, de la guardia Q00 y de vinculo_evidencia.sh, SIN Docker y SIN
# red: crea un clúster PostgreSQL 17 descartable SOLO por socket Unix (listen_addresses vacío, directorio 700
# propio, puerto ≠ 5432), con los roles mínimos y la O-4 remediada instalada, y un rol LOGIN de lectura (zz_ro) que
# NO es postgres ni superusuario. Corre los casos y lo elimina. No se conecta a staging ni a producción.
# Uso: probar_ejecutor_ro.sh [dir_evidencia_nuevo_fuera_del_repo]
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$DIR/../../.." && pwd)"
. "$DIR/vinculo_evidencia.sh"
EJ="$DIR/ejecutar_inventario_ro.sh"; B=/usr/lib/postgresql/17/bin; MIG="$REPO/supabase/migrations/20261110120000_o4_pgtemp_remediacion.sql"
[ -x "$B/initdb" ] && [ -x "$B/pg_ctl" ] && [ -x "$B/psql" ] || { echo "abortado: faltan binarios de PostgreSQL 17" >&2; exit 2; }
[ -d /run/user/1000 ] || { echo "abortado: falta /run/user/1000" >&2; exit 2; }
SALIDA_EV="${1:-}"
if [ -n "$SALIDA_EV" ]; then dir_evidencia_seguro "$SALIDA_EV" || exit 2; vinculo_git "$SALIDA_EV" || exit 5; exec > >(tee "$SALIDA_EV/salida_consola.txt") 2>&1; fi
T="$(mktemp -d /run/user/1000/o4ej.XXXXXX)"; chmod 700 "$T"; mkdir -m 700 "$T/ev"; PORT=54998; ADM=lab_admin
cleanup() { "$B/pg_ctl" -D "$T/data" -m immediate stop >/dev/null 2>&1; rm -rf "$T"; }; trap cleanup EXIT
"$B/initdb" -D "$T/data" -U "$ADM" --auth=trust --locale=C.UTF-8 --encoding=UTF8 >"$T/initdb.log" 2>&1 || { echo "abortado: initdb" >&2; exit 3; }
"$B/pg_ctl" -D "$T/data" -o "-c listen_addresses='' -c unix_socket_directories='$T' -c port=$PORT -c fsync=off" -l "$T/pg.log" -w start >/dev/null 2>&1 || { echo "abortado: pg_ctl start" >&2; exit 3; }
adm() { env -i "$B/psql" -X -q -v ON_ERROR_STOP=1 -h "$T" -p $PORT -U "$ADM" -d postgres "$@"; }
adm -Atc "select current_setting('listen_addresses') = '' and current_setting('port') = '$PORT'" | grep -q '^t$' || { echo "abortado: el clúster no es solo-socket" >&2; exit 3; }
SYSID="$(adm -Atc "select system_identifier from pg_control_system()")"
# Roles mínimos, O-4 remediada (cuerpo original + migración real) y el rol de lectura zz_ro (LOGIN, sin privilegios).
{ printf "create role postgres superuser nologin; create role anon nologin; create role authenticated nologin; create role service_role nologin; create role zz_ro login;\nset role postgres;\n"
  printf 'create function public.rls_auto_enable() returns event_trigger language plpgsql security definer set search_path = pg_catalog as $o4$'; cat "$DIR/cuerpo_original_325ae266.txt"
  printf '$o4$;\nrevoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role;\ncreate event trigger ensure_rls on ddl_command_end when tag in (%s) execute function public.rls_auto_enable();\n' "'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO'"
  cat "$MIG"; } | adm >/dev/null 2>"$T/inst.err" || { echo "abortado: instalar O-4 en el clúster de prueba: $(head -c 200 "$T/inst.err")" >&2; exit 3; }

REF=abcdefghij0123456789; n=0
FALLAS=0; TOTAL=0
chk() { TOTAL=$((TOTAL+1)); if [ "$1" = ok ]; then echo "PASA   $2"; else echo "FALLA  $2"; FALLAS=$((FALLAS+1)); fi; }
mkficha() { # mkficha <nombre> [CLAVE=valor ...]  → $T/<nombre>.ficha ; imprime la ruta
  local f="$T/$1.ficha"; shift
  printf 'FICHA_VERSION=1\nMODO=laboratorio\nHOST=%s\nPORT=%s\nPROJECT_REF=%s\nSYSTEM_IDENTIFIER=%s\nDBNAME=postgres\nDBUSER=zz_ro\nCA_SHA256=na\n' "$T" "$PORT" "$REF" "$SYSID" > "$f"
  local kv k v; for kv in "$@"; do k="${kv%%=*}"; v="${kv#*=}"; sed -i "s|^$k=.*|$k=$v|" "$f"; done; echo "$f"; }
hsh() { sha256sum "$1" | cut -d' ' -f1; }
ev() { echo "$T/ev/e$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"; }
ejecuta() { # ejecuta <ficha> <evidencia> [args extra]  (usa el ejecutor del repo)
  local f="$1" e="$2"; shift 2; SAL="$("$EJ" --ficha "$f" --ficha-sha256 "$(hsh "$f")" --estado remediado --evidencia "$e" --sin-clave "$@" 2>&1)"; RC=$?; }
has() { printf '%s' "$SAL" | grep -qF -- "$1"; }
F0="$(mkficha ok)"

echo "# 1. Ejecución completa con un rol LOGIN de lectura (zz_ro), Q00–Q6"
E="$(ev)"; ejecuta "$F0" "$E"
chk "$([ $RC -eq 4 ] && has 'GUARDIA|OK' && has 'compuerta LOGIN+TEMP' && echo ok)" "sin huella de revisión: Q00–Q6 corren y la compuerta LOGIN+TEMP aborta (rc=$RC)"
TOK="$(printf '%s' "$SAL" | grep -E '^[^|]*\|[0-9a-f]{64}\|[tf]$' | tail -1 | cut -d'|' -f2)"
E="$(ev)"; ejecuta "$F0" "$E" --revision-login-temp "$TOK"
chk "$([ $RC -eq 0 ] && has 'veredicto: sin motivos de abortar' && echo ok)" "con la huella de la lista revisada: Q6 exitoso con zz_ro (rc=$RC)"
chk "$(has 'sin supabase_migrations.schema_migrations' && has 'ensure_rls' && has 'tablas_public_sin_rls' && echo ok)" "Q2, Q3, Q4 y Q5 se ejecutan con el rol de lectura"
chk "$([ -f "$E/MANIFIESTO.sha256" ] && grep -q 'VINCULO=NO_VINCULADA_A_COMMIT' "$E/vinculo_git.txt" && [ "$(stat -c %a "$E")" = 700 ] && echo ok)" "la evidencia queda en directorio 700 con manifiesto y vínculo git declarado como NO vinculado (modo desarrollo)"
( cd "$E" && sha256sum -c MANIFIESTO.sha256 >/dev/null 2>&1 ); chk "$([ $? -eq 0 ] && echo ok)" "el manifiesto de la evidencia verifica"
adm -c "create schema supabase_migrations; create table supabase_migrations.schema_migrations (version text primary key, name text); insert into supabase_migrations.schema_migrations values ('20261110120000','o4');"
E="$(ev)"; ejecuta "$F0" "$E" --revision-login-temp "$TOK"
chk "$([ $RC -eq 0 ] && has 'DEPENDENCIA PENDIENTE' && ! has 20261110120000 && echo ok)" "Q4 con historial y rol sin privilegio: informa la dependencia pendiente, no lo lee y no amplía privilegios (rc=$RC)"
adm -c "drop schema supabase_migrations cascade;"

echo "# 2. Ficha de identidad: los parámetros de ejecución no son su propia fuente de confianza"
SAL="$("$EJ" --ficha "$F0" --ficha-sha256 "$(hsh "$F0")" --estado remediado --evidencia "$(ev)" --host /tmp/otro 2>&1)"; RC=$?; chk "$([ $RC -eq 2 ] && has 'argumento desconocido o no permitido' && echo ok)" "--host por línea de comandos: rechazado (rc=$RC)"
for opt in --port --dbname --user --ref --sysid; do SAL="$("$EJ" --ficha "$F0" --ficha-sha256 "$(hsh "$F0")" --estado remediado --evidencia "$(ev)" $opt x 2>&1)"; RC=$?; chk "$([ $RC -eq 2 ] && echo ok)" "$opt por línea de comandos: rechazado (rc=$RC)"; done
SAL="$("$EJ" --ficha "$F0" --ficha-sha256 "$(printf '0%.0s' $(seq 1 64))" --estado remediado --evidencia "$(ev)" 2>&1)"; RC=$?; chk "$([ $RC -eq 2 ] && has 'no coincide con la huella aprobada' && echo ok)" "ficha distinta de la aprobada (huella): rechazada (rc=$RC)"
cp "$F0" "$T/mod.ficha"; H0="$(hsh "$F0")"; sed -i 's/^DBNAME=.*/DBNAME=otra/' "$T/mod.ficha"
SAL="$("$EJ" --ficha "$T/mod.ficha" --ficha-sha256 "$H0" --estado remediado --evidencia "$(ev)" --sin-clave 2>&1)"; RC=$?; chk "$([ $RC -eq 2 ] && echo ok)" "ficha editada después de aprobada: rechazada (rc=$RC)"
FX="$(mkficha sysmal SYSTEM_IDENTIFIER=1234567890123)"; ejecuta "$FX" "$(ev)"; chk "$([ $RC -eq 3 ] && has 'system_identifier distinto' && ! has 'GUARDIA|OK' && ! has 'rolname' && echo ok)" "sysid ajeno en la ficha: la guardia aborta antes de Q0–Q6 (rc=$RC)"
FX="$(mkficha pto PORT=54997)"; ejecuta "$FX" "$(ev)"; chk "$([ $RC -ne 0 ] && echo ok)" "puerto distinto del servidor: no conecta (rc=$RC)"
FX="$(mkficha usr DBUSER=postgres)"; ejecuta "$FX" "$(ev)"; chk "$([ $RC -eq 2 ] && has 'DBUSER no puede ser postgres' && echo ok)" "ficha con DBUSER=postgres: rechazada (rc=$RC)"
FX="$(mkficha dup)"; echo 'DBNAME=postgres' >> "$FX"; ejecuta "$FX" "$(ev)"; chk "$([ $RC -eq 2 ] && has 'duplicada' && echo ok)" "clave duplicada en la ficha: rechazada (rc=$RC)"
FX="$(mkficha ext)"; echo 'HOSTADDR=1.2.3.4' >> "$FX"; ejecuta "$FX" "$(ev)"; chk "$([ $RC -eq 2 ] && has 'clave desconocida' && echo ok)" "clave desconocida (HOSTADDR) en la ficha: rechazada (rc=$RC)"
FX="$(mkficha falta)"; sed -i '/^DBUSER=/d' "$FX"; ejecuta "$FX" "$(ev)"; chk "$([ $RC -eq 2 ] && has 'falta DBUSER' && echo ok)" "ficha incompleta: rechazada (rc=$RC)"
# Q00 por sí sola: base, current_user, session_user, puerto y rol prohibido
q00() { { printf 'BEGIN READ ONLY;\n'; [ -n "$1" ] && printf 'SET ROLE %s;\n' "$1"; cat "$DIR/consultas_ro/Q00_guardia.sql"; printf 'ROLLBACK;\n'; } | env -i "$B/psql" -X -v ON_ERROR_STOP=1 -v "esperado_sysid=$SYSID" -v esperado_base="${BASE:-postgres}" -v esperado_usuario="${USU:-zz_ro}" -v esperado_puerto="${PTO:-$PORT}" -v estado_esperado=remediado -h "$T" -p $PORT -U "${CONN:-zz_ro}" -d postgres 2>&1; }
out="$(BASE=otra q00 '')"; rc=$?; chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'base distinta' && echo ok)" "Q00: base distinta de la ficha aborta"
out="$(USU=otro q00 '')"; rc=$?; chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'current_user distinto' && echo ok)" "Q00: current_user distinto de la ficha aborta"
out="$(CONN=$ADM q00 'zz_ro')"; rc=$?; chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'session_user distinto' && echo ok)" "Q00: session_user distinto (SET ROLE) aborta aunque current_user coincida"
out="$(PTO=1 q00 '')"; rc=$?; chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'puerto distinto' && echo ok)" "Q00: puerto distinto de la ficha aborta"
out="$(USU=$ADM CONN=$ADM q00 '')"; rc=$?; chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'no puede ser postgres' && echo ok)" "Q00: un superusuario como usuario del inventario aborta"
out="$({ printf 'select 1;\n'; cat "$DIR/consultas_ro/Q00_guardia.sql"; } | env -i "$B/psql" -X -v ON_ERROR_STOP=1 -v "esperado_sysid=$SYSID" -v esperado_base=postgres -v esperado_usuario=zz_ro -v esperado_puerto=$PORT -v estado_esperado=remediado -h "$T" -p $PORT -U zz_ro -d postgres 2>&1)"; rc=$?; chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'no es de solo lectura' && echo ok)" "Q00 fuera de READ ONLY: aborta"
for v in sysid base usuario puerto; do o="$({ printf 'BEGIN READ ONLY;\n'; cat "$DIR/consultas_ro/Q00_guardia.sql"; } | env -i "$B/psql" -X -v ON_ERROR_STOP=1 $( [ $v != sysid ] && echo "-v esperado_sysid=$SYSID") $( [ $v != base ] && echo "-v esperado_base=postgres") $( [ $v != usuario ] && echo "-v esperado_usuario=zz_ro") $( [ $v != puerto ] && echo "-v esperado_puerto=$PORT") -v estado_esperado=remediado -h "$T" -p $PORT -U zz_ro -d postgres 2>&1)"; chk "$(printf '%s' "$o" | grep -q "falta esperado_$v" && echo ok)" "Q00 sin esperado_$v: aborta"; done

echo "# 3. Entorno libpq limpio (incluido PGHOSTADDR) y psql -X"
printf '\\echo MARCA_PSQLRC_EJECUTADO\n' > "$T/psqlrc"
CONTAM=(PGHOSTADDR=203.0.113.1 PGSERVICE=zz_inexistente PGOPTIONS="-c default_transaction_read_only=off" PGSSLMODE=require PGPASSFILE="$T/pgpass" PGPORT=1 PGHOST=/nonexistent PGUSER=nadie PGDATABASE=nada PSQLRC="$T/psqlrc")
SAL="$(env "${CONTAM[@]}" "$EJ" --ficha "$F0" --ficha-sha256 "$H0" --estado remediado --evidencia "$(ev)" --sin-clave --revision-login-temp "$TOK" 2>&1)"; RC=$?
chk "$([ $RC -eq 0 ] && has PGHOSTADDR && has PGSERVICE && has PSQLRC && ! has MARCA_PSQLRC_EJECUTADO && echo ok)" "variables PG*/PSQLRC contaminadas: se eliminan y no afectan la ejecución (rc=$RC)"
out="$(env PGSERVICE=zz_inexistente "$B/psql" -X -h "$T" -p $PORT -U zz_ro -d postgres -Atc 'select 1' 2>&1)"; rc=$?; chk "$([ $rc -ne 0 ] && echo ok)" "control: sin la limpieza, PGSERVICE contaminado rompe la conexión"
out="$(env PSQLRC="$T/psqlrc" "$B/psql" -h "$T" -p $PORT -U zz_ro -d postgres -Atc 'select 1' 2>&1)"; chk "$(printf '%s' "$out" | grep -q MARCA_PSQLRC_EJECUTADO && echo ok)" "control: psql sin -X ejecuta el archivo de arranque"
SAL="$("$EJ" --ficha "$F0" --ficha-sha256 "$H0" --estado remediado --sin-clave --dry-run 2>&1)"; RC=$?; chk "$([ $RC -eq 0 ] && has 'psql -X -v ON_ERROR_STOP=1' && echo ok)" "la línea de comando usa psql -X y ON_ERROR_STOP=1"

echo "# 4. Ficha remota: TLS verify-full, host exacto, CA por huella (dry-run, sin red)"
printf 'CA-DE-PRUEBA\n' > "$T/ca.pem"; CAH="$(hsh "$T/ca.pem")"
mkremota() { local f="$T/$1.ficha"; shift; printf 'FICHA_VERSION=1\nMODO=remoto\nHOST=db.%s.supabase.co\nPORT=5432\nPROJECT_REF=%s\nSYSTEM_IDENTIFIER=%s\nDBNAME=postgres\nDBUSER=inventario_ro\nCA_SHA256=%s\n' "$REF" "$REF" "$SYSID" "$CAH" > "$f"; for kv in "$@"; do sed -i "s|^${kv%%=*}=.*|$kv|" "$f"; done; echo "$f"; }
mkdir "$T/falso"; printf '#!/bin/sh\ntouch "%s/psql_invocado"\n' "$T" > "$T/falso/psql"; chmod +x "$T/falso/psql"
rem() { local f="$1"; shift; SAL="$(PATH="$T/falso:$PATH" "$EJ" --ficha "$f" --ficha-sha256 "$(hsh "$f")" --estado original --dry-run "$@" 2>&1)"; RC=$?; }
FR="$(mkremota r1)"; rem "$FR" --ca "$T/ca.pem" --commit-esperado "$(printf 'a%.0s' $(seq 1 40))" --arbol-esperado "$(printf 'b%.0s' $(seq 1 40))"
chk "$([ $RC -eq 0 ] && has 'sslmode=verify-full' && ! has hostaddr && has 'sslrootcert=' && has 'host=db.' && [ ! -e "$T/psql_invocado" ] && echo ok)" "remoto (dry-run): verify-full, sin hostaddr y sin invocar psql"
GI=(--commit-esperado "$(printf 'a%.0s' $(seq 1 40))" --arbol-esperado "$(printf 'b%.0s' $(seq 1 40))")
rem "$FR" "${GI[@]}"; chk "$([ $RC -eq 2 ] && has '--ca' && echo ok)" "remoto sin --ca: rechazado (rc=$RC)"
printf 'OTRA-CA\n' > "$T/ca2.pem"; rem "$FR" --ca "$T/ca2.pem" "${GI[@]}"; chk "$([ $RC -eq 2 ] && has 'CA_SHA256' && echo ok)" "CA que no coincide con la huella de la ficha: rechazada (rc=$RC)"
rem "$FR" --ca "$T/ca.pem"; chk "$([ $RC -eq 2 ] && has 'commit-esperado' && echo ok)" "remoto sin identidad git esperada: rechazado (rc=$RC)"
FX="$(mkremota r2 HOST=db.otroproyecto0123456.supabase.co)"; rem "$FX" --ca "$T/ca.pem" "${GI[@]}"; chk "$([ $RC -eq 2 ] && has 'db.<PROJECT_REF>' && echo ok)" "host de otro proyecto: rechazado (rc=$RC)"
FX="$(mkremota r3 PORT=6543)"; rem "$FX" --ca "$T/ca.pem" "${GI[@]}"; chk "$([ $RC -eq 2 ] && has 'PORT debe ser 5432' && echo ok)" "puerto distinto de 5432 en remoto: rechazado (rc=$RC)"
FX="$(mkremota r4 DBUSER=supabase_admin)"; rem "$FX" --ca "$T/ca.pem" "${GI[@]}"; chk "$([ $RC -eq 2 ] && echo ok)" "remoto con usuario supabase_admin: rechazado (rc=$RC)"
FX="$(mkremota r5 'HOST=db.abcdefghij0123456789.supabase.co,evil')"; rem "$FX" --ca "$T/ca.pem" "${GI[@]}"; chk "$([ $RC -eq 2 ] && echo ok)" "multi-host en la ficha: rechazado (rc=$RC)"
SAL="$(PATH="$T/falso:$PATH" "$EJ" --ficha "$FR" --ficha-sha256 "$(hsh "$FR")" --estado original --sin-clave --dry-run --ca "$T/ca.pem" "${GI[@]}" 2>&1)"; RC=$?; chk "$([ $RC -eq 2 ] && has 'sólo se admite en laboratorio' && echo ok)" "--sin-clave en remoto: rechazado"

echo "# 5. Directorio de evidencia: nuevo, seguro, fuera del repo, sin enlaces ni sobrescritura"
E="$(ev)"; ejecuta "$F0" "$E" --revision-login-temp "$TOK"; h1="$(hsh "$E/inventario.txt")"
ejecuta "$F0" "$E" --revision-login-temp "$TOK"; chk "$([ $RC -eq 2 ] && has 'NUEVO' && [ "$h1" = "$(hsh "$E/inventario.txt")" ] && echo ok)" "directorio ya existente: rechazado y sin sobrescribir (rc=$RC)"
mkdir "$T/vacio"; ejecuta "$F0" "$T/vacio"; chk "$([ $RC -eq 2 ] && echo ok)" "directorio existente (aunque vacío): rechazado (rc=$RC)"
ln -s "$T/ev" "$T/enlace"; ejecuta "$F0" "$T/enlace/nuevo"; chk "$([ $RC -eq 2 ] && has 'enlaces simbólicos' && echo ok)" "enlace simbólico en un componente de la ruta: rechazado (rc=$RC)"
ln -s "$T/ev/inexistente_destino" "$T/ev/hoja"; ejecuta "$F0" "$T/ev/hoja"; chk "$([ $RC -eq 2 ] && echo ok)" "enlace simbólico como hoja: rechazado (rc=$RC)"
ejecuta "$F0" "$REPO/zz_evidencia_prueba"; chk "$([ $RC -eq 2 ] && has 'fuera del repositorio' && [ ! -e "$REPO/zz_evidencia_prueba" ] && echo ok)" "evidencia dentro del repositorio: rechazada (rc=$RC)"
ln -s "$REPO" "$T/aRepo"; ejecuta "$F0" "$T/aRepo/zz_evidencia_prueba"; chk "$([ $RC -eq 2 ] && [ ! -e "$REPO/zz_evidencia_prueba" ] && echo ok)" "enlace hacia el repositorio: rechazado y nada escrito en el repo (rc=$RC)"
ejecuta "$F0" "$T/noexiste/nuevo"; chk "$([ $RC -eq 2 ] && has 'padre no existe' && echo ok)" "padre inexistente: rechazado (rc=$RC)"
for m in 770 777 775 720 702; do mkdir "$T/p$m"; chmod $m "$T/p$m"; ejecuta "$F0" "$T/p$m/nuevo" --revision-login-temp "$TOK"; chk "$([ $RC -eq 2 ] && has 'escribible por el grupo u otros' && [ ! -e "$T/p$m/nuevo" ] && echo ok)" "padre con modo $m: rechazado incondicionalmente, sin crear nada (rc=$RC)"; done
for m in 755 750 700; do mkdir "$T/q$m"; chmod $m "$T/q$m"; ejecuta "$F0" "$T/q$m/nuevo" --revision-login-temp "$TOK"; chk "$([ $RC -eq 0 ] && [ -d "$T/q$m/nuevo" ] && echo ok)" "padre con modo $m (sin escritura de grupo/otros): aceptado (rc=$RC)"; done
ejecuta "$F0" "relativa/ruta"; chk "$([ $RC -eq 2 ] && has 'absoluta' && echo ok)" "ruta relativa: rechazada (rc=$RC)"

echo "# 6. Vínculo con git: identidad y código verificados ANTES de ejecutar (repositorio de prueba aparte)"
G="$T/repo_prueba"; mkdir -p "$G/supabase/laboratorio" "$G/supabase/scripts" "$G/supabase/migrations"
cp -r "$DIR" "$G/supabase/laboratorio/o4-pgtemp"; cp "$REPO/supabase/scripts/validar_topologia_propietario_rpc.sql" "$G/supabase/scripts/"; cp "$MIG" "$G/supabase/migrations/"
( cd "$G" && git init -q && git -c user.email=t@t -c user.name=t add -A && git -c user.email=t@t -c user.name=t commit -q -m prueba ) >/dev/null 2>&1
GC="$(git -C "$G" rev-parse HEAD)"; GT="$(git -C "$G" rev-parse 'HEAD^{tree}')"; EJG="$G/supabase/laboratorio/o4-pgtemp/ejecutar_inventario_ro.sh"
ejg() { local e; e="$(ev)"; SAL="$("$EJG" --ficha "$F0" --ficha-sha256 "$H0" --estado remediado --evidencia "$e" --sin-clave --revision-login-temp "$TOK" "$@" 2>&1)"; RC=$?; EVG="$e"; }
ejg --commit-esperado "$GC" --arbol-esperado "$GT"
chk "$([ $RC -eq 0 ] && grep -q 'VINCULO=ESTRICTO' "$EVG/vinculo_git.txt" && grep -q "commit_actual=$GC" "$EVG/vinculo_git.txt" && echo ok)" "identidad esperada y código limpio: ejecuta y registra commit, árbol y hashes (rc=$RC)"
ejg --commit-esperado "$(printf 'c%.0s' $(seq 1 40))" --arbol-esperado "$GT"; chk "$([ $RC -eq 5 ] && has 'distinto del commit esperado' && [ ! -e "$EVG/inventario.txt" ] && grep -q 'commit_actual' "$EVG/vinculo_git.txt" && echo ok)" "commit distinto del esperado: falla antes de conectar, pero deja registrado lo observado (rc=$RC)"
ejg --commit-esperado "$GC" --arbol-esperado "$(printf 'd%.0s' $(seq 1 40))"; chk "$([ $RC -eq 5 ] && has 'árbol' && [ ! -e "$EVG/inventario.txt" ] && echo ok)" "árbol distinto del esperado: falla antes de conectar (rc=$RC)"
echo '-- cambio' >> "$G/supabase/laboratorio/o4-pgtemp/consultas_ro/Q2_funcion.sql"
ejg --commit-esperado "$GC" --arbol-esperado "$GT"; chk "$([ $RC -eq 5 ] && has 'sin commitear' && [ ! -e "$EVG/inventario.txt" ] && echo ok)" "consulta modificada sin commit: falla antes de conectar (rc=$RC)"
git -C "$G" update-index --assume-unchanged supabase/laboratorio/o4-pgtemp/consultas_ro/Q2_funcion.sql
ejg --commit-esperado "$GC" --arbol-esperado "$GT"; chk "$([ $RC -eq 5 ] && has 'difiere de su blob' && echo ok)" "cambio oculto con assume-unchanged: lo detecta la comparación con el blob (rc=$RC)"
ejg; chk "$([ $RC -eq 0 ] && grep -q 'VINCULO=NO_VINCULADA_A_COMMIT' "$EVG/vinculo_git.txt" && grep -q 'estado_git_rutas_del_paquete=limpio\|MODIFICADO' "$EVG/vinculo_git.txt" && echo ok)" "sin identidad esperada: se ejecuta pero la evidencia queda declarada NO vinculada a commit"
git -C "$G" update-index --no-assume-unchanged supabase/laboratorio/o4-pgtemp/consultas_ro/Q2_funcion.sql; git -C "$G" checkout -q -- supabase/laboratorio/o4-pgtemp/consultas_ro/Q2_funcion.sql
echo 'x' > "$G/supabase/laboratorio/o4-pgtemp/extra.sh"
ejg --commit-esperado "$GC" --arbol-esperado "$GT"; chk "$([ $RC -eq 5 ] && has 'sin commitear' && echo ok)" "archivo sin seguimiento en el paquete: falla antes de conectar (rc=$RC)"
SAL="$("$EJG" --ficha "$F0" --ficha-sha256 "$H0" --estado remediado --evidencia "$(ev)" --sin-clave --commit-esperado "$GC" 2>&1)"; RC=$?; chk "$([ $RC -eq 2 ] && has 'van juntos' && echo ok)" "sólo el commit esperado, sin el árbol: rechazado (rc=$RC)"

echo "# 7. Sin TOCTOU: ficha y CA se copian a un directorio privado y sólo la copia verificada se consume"
FB="$T/fb"; REC="$T/rec"; mkdir "$FB" "$REC"
cat > "$FB/psql" <<'EOS'
#!/bin/bash
# psql falso de laboratorio: sustituye los orígenes DESPUÉS de la validación y registra qué consumiría libpq.
[ "${1:-}" = "--version" ] && { echo "psql (PostgreSQL) 17.0 falso-de-laboratorio"; exit 0; }
printf '%s\n' "$@" > "$T_REC/psql_args"
# Se sustituyen los orígenes ANTES de medir lo que libpq leería: modela el cambio entre la validación y la conexión.
[ -n "${ORIG_FICHA:-}" ] && cp "$MAL_FICHA" "$ORIG_FICHA"
[ -n "${ORIG_CA:-}" ] && cp "$MAL_CA" "$ORIG_CA"
PRIVD="$(dirname "$PGPASSFILE")"; echo "$PRIVD" > "$T_REC/priv"; stat -c %a "$PRIVD" > "$T_REC/priv_modo"
ca="$(printf '%s\n' "$@" | grep -o 'sslrootcert=[^ ]*' | head -1 | cut -d= -f2)"
if [ -n "$ca" ]; then echo "$ca" > "$T_REC/ca_path"; /usr/bin/sha256sum "$ca" | cut -d' ' -f1 > "$T_REC/ca_hash"; stat -c %a "$ca" > "$T_REC/ca_modo"; fi
cat > /dev/null
echo "|$(printf 'a%.0s' $(seq 1 64))|t"
EOS
cat > "$FB/sha256sum" <<'EOS'
#!/bin/bash
# Si alguien hashea el ORIGEN (versión vulnerable), lo sustituye justo después de hashearlo.
out="$(/usr/bin/sha256sum "$@")"; rc=$?
for a in "$@"; do
  if [ -n "${ORIG_FICHA:-}" ] && [ "$a" = "$ORIG_FICHA" ] && [ ! -e "$T_REC/sw_f" ]; then touch "$T_REC/sw_f"; cp "$MAL_FICHA" "$ORIG_FICHA"; fi
  if [ -n "${ORIG_CA:-}" ] && [ "$a" = "$ORIG_CA" ] && [ ! -e "$T_REC/sw_c" ]; then touch "$T_REC/sw_c"; cp "$MAL_CA" "$ORIG_CA"; fi
done
printf '%s\n' "$out"; exit $rc
EOS
chmod +x "$FB/psql" "$FB/sha256sum"
SYS_MAL=9999999999999
ORIG_F="$T/orig.ficha"; MAL_F="$T/mal.ficha"; cp "$F0" "$ORIG_F"; HF="$(hsh "$ORIG_F")"; sed "s/^SYSTEM_IDENTIFIER=.*/SYSTEM_IDENTIFIER=$SYS_MAL/" "$F0" > "$MAL_F"
tox() { # tox <args del ejecutor...>  (con PATH al psql/sha256sum falsos y registro en $REC)
  rm -f "$REC"/*; SAL="$(T_REC="$REC" ORIG_FICHA="${OF:-}" MAL_FICHA="${MF:-}" ORIG_CA="${OC:-}" MAL_CA="${MC:-}" PATH="$FB:$PATH" "$EJX" "$@" 2>&1)"; RC=$?; }
EJX="$EJ"
# --- ficha (modo laboratorio) ---
OF="$ORIG_F" MF="$MAL_F" OC="" MC=""; E="$(ev)"
tox --ficha "$ORIG_F" --ficha-sha256 "$HF" --estado remediado --evidencia "$E" --sin-clave
chk "$([ $RC -eq 0 ] && grep -q "esperado_sysid=$SYSID" "$REC/psql_args" && ! grep -q "$SYS_MAL" "$REC/psql_args" && echo ok)" "T1 ficha sustituida tras validar: psql recibe los valores de la ficha APROBADA (rc=$RC)"
chk "$([ "$(hsh "$E/ficha.txt")" = "$HF" ] && [ "$(hsh "$ORIG_F")" != "$HF" ] && echo ok)" "T2 la evidencia guarda la ficha privada verificada y el origen sí fue sustituido"
chk "$([ "$(cat "$REC/priv_modo")" = 700 ] && [ ! -d "$(cat "$REC/priv")" ] && [ -f "$E/ficha.txt" ] && [ -f "$E/MANIFIESTO.sha256" ] && echo ok)" "T3 el directorio temporal era 0700, se eliminó al terminar y la evidencia se conserva"
# --- CA (modo remoto, repositorio de prueba con identidad git estricta) ---
G2="$T/repo_prueba2"; mkdir -p "$G2/supabase/laboratorio" "$G2/supabase/scripts" "$G2/supabase/migrations"
cp -r "$DIR" "$G2/supabase/laboratorio/o4-pgtemp"; cp "$REPO/supabase/scripts/validar_topologia_propietario_rpc.sql" "$G2/supabase/scripts/"; cp "$MIG" "$G2/supabase/migrations/"
( cd "$G2" && git init -q && git -c user.email=t@t -c user.name=t add -A && git -c user.email=t@t -c user.name=t commit -q -m prueba ) >/dev/null 2>&1
GC2="$(git -C "$G2" rev-parse HEAD)"; GT2="$(git -C "$G2" rev-parse 'HEAD^{tree}')"; EJX="$G2/supabase/laboratorio/o4-pgtemp/ejecutar_inventario_ro.sh"
ORIG_C="$T/orig_ca.pem"; MAL_C="$T/mal_ca.pem"; cp "$T/ca.pem" "$ORIG_C"; printf 'CA-MALICIOSA\n' > "$MAL_C"
FRR="$(mkremota rr)"; cp "$FRR" "$T/orig_rem.ficha"; HRR="$(hsh "$T/orig_rem.ficha")"; sed "s/^SYSTEM_IDENTIFIER=.*/SYSTEM_IDENTIFIER=$SYS_MAL/" "$FRR" > "$T/mal_rem.ficha"
OF="$T/orig_rem.ficha" MF="$T/mal_rem.ficha" OC="$ORIG_C" MC="$MAL_C"; E="$(ev)"
tox --ficha "$T/orig_rem.ficha" --ficha-sha256 "$HRR" --estado original --evidencia "$E" --ca "$ORIG_C" --commit-esperado "$GC2" --arbol-esperado "$GT2"
chk "$([ $RC -eq 0 ] && echo ok)" "T4 ejecución remota simulada (psql falso) con identidad git estricta (rc=$RC)"
CAP="$(cat "$REC/ca_path" 2>/dev/null)"
chk "$([ -n "$CAP" ] && [ "$CAP" != "$ORIG_C" ] && [ "$(dirname "$CAP")" = "$(cat "$REC/priv")" ] && [ "$(cat "$REC/ca_modo")" = 400 ] && echo ok)" "T5 libpq recibe sslrootcert dentro del directorio privado (0400), no la ruta de origen"
chk "$([ "$(cat "$REC/ca_hash")" = "$CAH" ] && [ "$(hsh "$ORIG_C")" != "$CAH" ] && echo ok)" "T6 al invocar psql la CA consumida tiene el SHA-256 aprobado aunque el origen ya fue sustituido"
chk "$([ "$(hsh "$E/ca_verificada.pem")" = "$CAH" ] && [ "$(hsh "$E/ficha.txt")" = "$HRR" ] && grep -q "esperado_sysid=$SYSID" "$REC/psql_args" && ! grep -q "$SYS_MAL" "$REC/psql_args" && echo ok)" "T7 ficha y CA de la evidencia son los bytes aprobados; psql recibe el sysid aprobado"
chk "$([ ! -d "$(cat "$REC/priv")" ] && [ -f "$E/ca_verificada.pem" ] && echo ok)" "T8 la limpieza elimina el temporal privado y conserva la evidencia"
# --- sustitución antes de usar: bytes no aprobados se rechazan ---
cp "$FRR" "$T/orig_rem.ficha"; cp "$MAL_C" "$ORIG_C"; E="$(ev)"; OF="" MF="" OC="" MC=""
tox --ficha "$T/orig_rem.ficha" --ficha-sha256 "$HRR" --estado original --evidencia "$E" --ca "$ORIG_C" --commit-esperado "$GC2" --arbol-esperado "$GT2"
chk "$([ $RC -eq 2 ] && has 'CA_SHA256' && [ ! -e "$REC/psql_args" ] && echo ok)" "T9 CA sustituida antes de usar: rechazada, psql no se invoca (rc=$RC)"
cp "$T/ca.pem" "$ORIG_C"; cp "$MAL_F" "$ORIG_F"; E="$(ev)"
tox --ficha "$ORIG_F" --ficha-sha256 "$HF" --estado remediado --evidencia "$E" --sin-clave
chk "$([ $RC -eq 2 ] && has 'no coincide con la huella aprobada' && [ ! -e "$REC/psql_args" ] && echo ok)" "T10 ficha sustituida antes de usar: rechazada, psql no se invoca (rc=$RC)"
cp "$F0" "$ORIG_F"
# --- sustitución durante la copia: o bytes aprobados (inodo anterior) o rechazo; nunca bytes no aprobados ---
mkdir "$T/fb2"; cat > "$T/fb2/cat" <<'EOS'
#!/bin/bash
# Primera invocación: sustituye el origen de la ficha ANTES de que cat lea (por truncado o por renombre).
if [ ! -e "$T_REC/cat_hecho" ]; then touch "$T_REC/cat_hecho"
  if [ "$CAT_MODO" = truncar ]; then cp "$MAL_FICHA" "$ORIG_FICHA"; else cp "$MAL_FICHA" "$ORIG_FICHA.tmp"; mv "$ORIG_FICHA.tmp" "$ORIG_FICHA"; fi
fi
exec /usr/bin/cat "$@"
EOS
chmod +x "$T/fb2/cat"; EJX="$EJ"
for modo in truncar renombrar; do
  cp "$F0" "$ORIG_F"; E="$(ev)"; rm -f "$REC"/*
  SAL="$(T_REC="$REC" CAT_MODO=$modo ORIG_FICHA="$ORIG_F" MAL_FICHA="$MAL_F" PATH="$T/fb2:$FB:$PATH" "$EJ" --ficha "$ORIG_F" --ficha-sha256 "$HF" --estado remediado --evidencia "$E" --sin-clave 2>&1)"; RC=$?
  if [ $modo = truncar ]; then chk "$([ $RC -eq 2 ] && has 'no coincide con la huella aprobada' && [ ! -e "$REC/psql_args" ] && echo ok)" "T11 sustitución por truncado durante la copia: bytes no aprobados rechazados (rc=$RC)"
  else chk "$([ $RC -eq 0 ] && grep -q "esperado_sysid=$SYSID" "$REC/psql_args" && ! grep -q "$SYS_MAL" "$REC/psql_args" && [ "$(hsh "$E/ficha.txt")" = "$HF" ] && echo ok)" "T12 sustitución por renombre durante la copia: se consume el inodo aprobado (rc=$RC)"; fi
done
cp "$F0" "$ORIG_F"
# --- estático: tras la copia, las rutas de origen no se vuelven a consultar ---
LIN="$(grep -n '^unset FICHA CA' "$EJ" | cut -d: -f1)"
chk "$([ -n "$LIN" ] && ! tail -n +$((LIN+1)) "$EJ" | grep -vE '^\s*#' | grep -qE '\$(\{)?(FICHA|CA)([^A-Za-z0-9_]|$)' && echo ok)" "T13 estático: ninguna referencia a las rutas de origen (FICHA/CA) después de 'unset FICHA CA'"
chk "$(grep -q 'set -uo pipefail' "$EJ" && echo ok)" "T14 'set -u' activo: una referencia posterior a las rutas de origen abortaría"

echo "--- casos: $TOTAL, fallas: $FALLAS"
[ "$FALLAS" -eq 0 ]
