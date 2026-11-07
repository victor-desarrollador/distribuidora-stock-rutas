#!/usr/bin/env bash
# Pruebas NEGATIVAS del ejecutor ejecutar_inventario_ro.sh y de la guardia Q00, sin Docker y sin red:
# crea un clúster PostgreSQL 17 descartable SOLO por socket Unix (listen_addresses vacío, directorio
# 700 propio, puerto ≠ 5432), corre los casos y lo elimina. No se conecta a staging ni a producción.
# Uso: probar_ejecutor_ro.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EJ="$DIR/ejecutar_inventario_ro.sh"; B=/usr/lib/postgresql/17/bin
[ -x "$B/initdb" ] && [ -x "$B/pg_ctl" ] && [ -x "$B/psql" ] || { echo "abortado: faltan binarios de PostgreSQL 17" >&2; exit 2; }
[ -d /run/user/1000 ] || { echo "abortado: falta /run/user/1000" >&2; exit 2; }
T="$(mktemp -d /run/user/1000/o4ej.XXXXXX)"; chmod 700 "$T"; PORT=54998; USR=lab_admin
cleanup() { "$B/pg_ctl" -D "$T/data" -m immediate stop >/dev/null 2>&1; rm -rf "$T"; }; trap cleanup EXIT
"$B/initdb" -D "$T/data" -U "$USR" --auth=trust --locale=C.UTF-8 --encoding=UTF8 >"$T/initdb.log" 2>&1 || { echo "abortado: initdb" >&2; exit 3; }
"$B/pg_ctl" -D "$T/data" -o "-c listen_addresses='' -c unix_socket_directories='$T' -c port=$PORT -c fsync=off" -l "$T/pg.log" -w start >/dev/null 2>&1 || { echo "abortado: pg_ctl start" >&2; exit 3; }
env -i "$B/psql" -X -h "$T" -p $PORT -U "$USR" -d postgres -Atc "select current_setting('listen_addresses') = '' and current_setting('port') = '$PORT'" | grep -q '^t$' || { echo "abortado: el clúster no es solo-socket" >&2; exit 3; }
SYSID="$(env -i "$B/psql" -X -h "$T" -p $PORT -U "$USR" -d postgres -Atc "select system_identifier from pg_control_system()")"
REF=abcdefghij0123456789
base=(--laboratorio --sin-clave --host "$T" --port $PORT --dbname postgres --user "$USR" --ref "$REF" --estado remediado)
FALLAS=0; TOTAL=0
chk() { TOTAL=$((TOTAL+1)); if [ "$1" = ok ]; then echo "PASA   $2"; else echo "FALLA  $2"; FALLAS=$((FALLAS+1)); fi; }
run() { SAL="$("$EJ" "$@" 2>&1)"; RC=$?; }   # SAL = stdout+stderr, RC = código
has() { printf '%s' "$SAL" | grep -qF -- "$1"; }

echo "# 1. Identidad fail-closed"
run "${base[@]}"; chk "$([ $RC -eq 2 ] && has 'falta --sysid' && ! has GUARDIA && echo ok)" "sin --sysid: aborta antes de conectar (rc=$RC)"
run "${base[@]}" --sysid 1234567890123; chk "$([ $RC -eq 3 ] && has 'system_identifier distinto' && ! has 'GUARDIA|OK' && ! has rolname && echo ok)" "sysid incorrecto: la guardia aborta antes de Q0–Q6 (rc=$RC)"
run "${base[@]}" --sysid "$SYSID"; chk "$([ $RC -eq 4 ] && has 'GUARDIA|OK' && has rolname && has 'ABORTAR' && echo ok)" "sysid correcto: pasa la guardia y Q6 aborta por falta de O-4 (rc=$RC)"
run "${base[@]}" --sysid "12ab"; chk "$([ $RC -eq 2 ] && has 'formato inválido' && echo ok)" "sysid con formato inválido: rc=$RC"
out="$(printf 'select 1;\n' | env -i "$B/psql" -X -v ON_ERROR_STOP=1 -v "esperado_sysid=$SYSID" -v esperado_base=postgres -v estado_esperado=remediado -h "$T" -p $PORT -U "$USR" -d postgres -f "$DIR/consultas_ro/Q00_guardia.sql" 2>&1)"; rc=$?
chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'no es de solo lectura' && echo ok)" "Q00 fuera de READ ONLY: aborta (rc=$rc)"
out="$({ printf 'BEGIN READ ONLY;\n'; cat "$DIR/consultas_ro/Q00_guardia.sql"; printf 'ROLLBACK;\n'; } | env -i "$B/psql" -X -v ON_ERROR_STOP=1 -v esperado_base=postgres -v estado_esperado=remediado -h "$T" -p $PORT -U "$USR" -d postgres 2>&1)"; rc=$?
chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'falta esperado_sysid' && echo ok)" "Q00 sin esperado_sysid: aborta (rc=$rc)"

echo "# 2. Entorno libpq limpio (incluido PGHOSTADDR) y psql -X"
printf '\\echo MARCA_PSQLRC_EJECUTADO\n' > "$T/psqlrc"
CONTAM=(PGHOSTADDR=203.0.113.1 PGSERVICE=zz_inexistente PGOPTIONS="-c default_transaction_read_only=off" PGSSLMODE=require PGPASSFILE="$T/pgpass" PGPORT=1 PGHOST=/nonexistent PGUSER=nadie PGDATABASE=nada PSQLRC="$T/psqlrc")
SAL="$(env "${CONTAM[@]}" "$EJ" "${base[@]}" --sysid "$SYSID" 2>&1)"; RC=$?
chk "$([ $RC -eq 4 ] && has 'GUARDIA|OK' && has PGHOSTADDR && has PGSERVICE && has PSQLRC && ! has MARCA_PSQLRC_EJECUTADO && echo ok)" "variables PG*/PSQLRC contaminadas: se eliminan y no afectan la ejecución (rc=$RC)"
out="$(env PGSERVICE=zz_inexistente "$B/psql" -X -h "$T" -p $PORT -U "$USR" -d postgres -Atc 'select 1' 2>&1)"; rc=$?
chk "$([ $rc -ne 0 ] && echo ok)" "control: sin la limpieza, PGSERVICE contaminado rompe la conexión (rc=$rc)"
out="$(env PSQLRC="$T/psqlrc" "$B/psql" -h "$T" -p $PORT -U "$USR" -d postgres -Atc 'select 1' 2>&1)"
chk "$(printf '%s' "$out" | grep -q MARCA_PSQLRC_EJECUTADO && echo ok)" "control: psql sin -X ejecuta el archivo de arranque"
run "${base[@]}" --sysid "$SYSID" --dry-run; chk "$([ $RC -eq 0 ] && has 'psql -X -v ON_ERROR_STOP=1' && echo ok)" "la línea de comando usa psql -X y ON_ERROR_STOP=1"

echo "# 3. Validación de destino (aborta antes de conectar)"
mkdir "$T/falso"; printf '#!/bin/sh\ntouch "%s/psql_invocado"\n' "$T" > "$T/falso/psql"; chmod +x "$T/falso/psql"
printf 'CA\n' > "$T/ca.pem"
sal_y_psql() { SAL="$(PATH="$T/falso:$PATH" "$EJ" "$@" 2>&1)"; RC=$?; }
sal_y_psql --host "db.${REF}.supabase.co" --port 5432 --dbname postgres --user postgres --ref "$REF" --sysid "$SYSID" --estado remediado --sslrootcert "$T/ca.pem" --dry-run
chk "$([ $RC -eq 0 ] && has 'sslmode=verify-full' && ! has hostaddr && has 'sslrootcert=' && [ ! -e "$T/psql_invocado" ] && echo ok)" "remoto (dry-run): verify-full, sin hostaddr y sin invocar psql"
run --host "db.otroproyecto0123456.supabase.co" --port 5432 --dbname postgres --user postgres --ref "$REF" --sysid "$SYSID" --estado remediado --sslrootcert "$T/ca.pem" --dry-run
chk "$([ $RC -eq 2 ] && has 'db.<ref>.supabase.co' && echo ok)" "host de otro proyecto: rechazado (rc=$RC)"
run --host "db.${REF}.supabase.co" --port 5432 --dbname postgres --user postgres --ref "$REF" --sysid "$SYSID" --estado remediado --dry-run
chk "$([ $RC -eq 2 ] && has 'sslrootcert' && echo ok)" "remoto sin --sslrootcert: rechazado (rc=$RC)"
run --host "db.${REF}.supabase.co,evil.example" --port 5432 --dbname postgres --user postgres --ref "$REF" --sysid "$SYSID" --estado remediado --sslrootcert "$T/ca.pem" --dry-run
chk "$([ $RC -eq 2 ] && echo ok)" "multi-host (coma) en --host: rechazado (rc=$RC)"
run --host "db.${REF}.supabase.co hostaddr=1.2.3.4" --port 5432 --dbname postgres --user postgres --ref "$REF" --sysid "$SYSID" --estado remediado --sslrootcert "$T/ca.pem" --dry-run
chk "$([ $RC -eq 2 ] && echo ok)" "inyección de hostaddr en --host: rechazada (rc=$RC)"
run --laboratorio --host "db.${REF}.supabase.co" --port 54998 --dbname postgres --user postgres --ref "$REF" --sysid "$SYSID" --estado remediado --dry-run
chk "$([ $RC -eq 2 ] && has 'socket Unix' && echo ok)" "--laboratorio con host remoto: rechazado (rc=$RC)"
run --sin-clave --host "db.${REF}.supabase.co" --port 5432 --dbname postgres --user postgres --ref "$REF" --sysid "$SYSID" --estado remediado --sslrootcert "$T/ca.pem" --dry-run
chk "$([ $RC -eq 2 ] && has 'sólo se admite en laboratorio' && echo ok)" "--sin-clave en remoto: rechazado (rc=$RC)"
run --laboratorio --sin-clave --host "$T" --port 5432 --dbname postgres --user "$USR" --ref "$REF" --sysid "$SYSID" --estado remediado --dry-run
chk "$([ $RC -eq 2 ] && has 5432 && echo ok)" "laboratorio con puerto 5432: rechazado (rc=$RC)"
run "${base[@]}" --sysid "$SYSID" --revision-login-temp "xyz"; chk "$([ $RC -eq 2 ] && has 'huella sha256' && echo ok)" "huella de revisión con formato inválido: rechazada (rc=$RC)"

echo "--- casos: $TOTAL, fallas: $FALLAS"
[ "$FALLAS" -eq 0 ]
