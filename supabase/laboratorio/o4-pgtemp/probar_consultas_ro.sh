#!/usr/bin/env bash
# Validación en LABORATORIO de las consultas READ ONLY Q0–Q6 (consultas_ro/) que se
# usarían para inventariar staging. NO se conecta a ningún destino remoto: crea UN
# contenedor descartable (sin red, sin puertos, sin montajes; ver lab_comun.sh),
# aplica las migraciones del repo, recorre una matriz de estados de O-4 y compara
# una huella del catálogo antes y después de cada consulta.
# Uso: probar_consultas_ro.sh <dir_salida_vacío_o_inexistente_fuera_del_repo>
set -uo pipefail
[ "$#" -eq 1 ] || { echo "uso: $0 <dir_salida>" >&2; exit 2; }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../.." && pwd)"
# Canonicalización completa aunque el padre no exista (realpath -m); rechaza lo que caiga en el repo.
OUT="$(realpath -m -- "$1")"; REPO_REAL="$(realpath -- "$REPO")"
case "$OUT/" in "$REPO_REAL"/*) echo "abortado: la evidencia debe quedar fuera del repositorio" >&2; exit 2 ;; esac
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGPASSWORD PGSERVICE PGSERVICEFILE DATABASE_URL SUPABASE_DB_URL || true
. "$DIR/lab_comun.sh"
Q="$DIR/consultas_ro"; PF="$REPO/supabase/scripts/validar_topologia_propietario_rpc.sql"
MIG="$REPO/supabase/migrations/20261110120000_o4_pgtemp_remediacion.sql"; CUERPO="$DIR/cuerpo_original_325ae266.txt"
[ "$(sha256sum "$CUERPO" | cut -d' ' -f1)" = "325ae266d9b166715ef5230ceaf7ff9d523e483cf5610dfb9779ab3f183f4af9" ] || { echo "abortado: cuerpo de referencia alterado" >&2; exit 2; }
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then echo "abortado: $OUT no está vacío" >&2; exit 2; fi
mkdir -p "$OUT"
docker image inspect "$LAB_IMG" >/dev/null 2>&1 || { echo "abortado: imagen $LAB_IMG no presente (no se descarga)" >&2; exit 2; }
export LAB_NONCE="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"; export LAB_CONTAINER="${LAB_PREFIJO}${LAB_NONCE:0:12}"
CID=""; limpiar() { [ -n "$CID" ] && docker rm -f -v "$CID" > "$OUT/contenedor_eliminado.txt" 2>&1; }; trap limpiar EXIT
{ docker ps -a --format '{{.ID}} {{.Names}} {{.Status}}'; echo '--- redes'; docker network ls --format '{{.Name}}'; echo '--- volúmenes'; docker volume ls --format '{{.Name}}'; } > "$OUT/docker_antes.txt"
CID="$(docker run -d --name "$LAB_CONTAINER" --label "t3.o4m01.nonce=$LAB_NONCE" --network none -e POSTGRES_PASSWORD="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')" "$LAB_IMG")" || { echo "abortado: docker run" >&2; exit 3; }
lab_verificar; docker inspect --format 'red={{.HostConfig.NetworkMode}} puertos={{json .HostConfig.PortBindings}} montajes={{json .Mounts}}' "$LAB_CONTAINER" | tee "$OUT/aislamiento.txt"
for i in $(seq 1 90); do docker exec "$LAB_CONTAINER" pg_isready -U postgres -h localhost >/dev/null 2>&1 && break; sleep 2; done; sleep 3
for f in "$REPO"/supabase/migrations/2026102*.sql "$REPO"/supabase/migrations/2026103*.sql "$REPO"/supabase/migrations/2026110[1-9]*.sql; do
  [ "$(basename "$f")" = "20261110120000_o4_pgtemp_remediacion.sql" ] && continue
  lab_sql postgres -q < "$f" >/dev/null 2>"$OUT/mig_$(basename "$f").stderr" || { echo "abortado: migración $(basename "$f")" >&2; exit 4; }
done
lab_sql supabase_admin -qtA >/dev/null <<SQL || { echo "abortado: identidad" >&2; exit 5; }
create schema zz_laboratorio; create table zz_laboratorio.identidad (nonce text not null, sysid text not null);
insert into zz_laboratorio.identidad values ('$LAB_NONCE', (select system_identifier::text from pg_control_system()));
SQL
lab_identidad
# Sin O-4 al comienzo (la migración O-4 se aplica más adelante, como un escenario).
[ "$(printf "select to_regprocedure('public.rls_auto_enable()') is null and not exists (select 1 from pg_event_trigger where evtname='ensure_rls');\n" | lab_sql postgres -qtA)" = "t" ] || { echo "abortado: el laboratorio debe comenzar SIN O-4" >&2; exit 2; }

TAGS="'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO'"
ORIG="$(printf 'create function public.rls_auto_enable() returns event_trigger language plpgsql security definer set search_path = pg_catalog as $o4$'; cat "$CUERPO"; printf '$o4$;\nrevoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role;\ncreate event trigger ensure_rls on ddl_command_end when tag in (%s) execute function public.rls_auto_enable();\n' "$TAGS"; printf x)"; ORIG="${ORIG%x}"
MIGSQL="$(cat "$MIG"; printf x)"; MIGSQL="${MIGSQL%x}"
REINSTALAR="drop event trigger if exists ensure_rls; drop function if exists public.rls_auto_enable();
$ORIG
$MIGSQL"
EVT3="create event trigger ensure_rls on ddl_command_end when tag in ($TAGS) execute function public.rls_auto_enable();"

# huella del catálogo (detecta cualquier efecto persistente)
FP="select md5(concat_ws('|',
 (select string_agg(concat_ws(',', oid, relname, relacl::text, relrowsecurity, relowner), ';' order by oid) from pg_class),
 (select string_agg(concat_ws(',', oid, proname, proacl::text, md5(prosrc), proconfig::text, proowner), ';' order by oid) from pg_proc),
 (select string_agg(concat_ws(',', oid, rolname, rolcanlogin, rolconfig::text), ';' order by oid) from pg_roles),
 (select string_agg(concat_ws(',', oid, evtname, evtenabled, evtowner, evttags::text, evtfoid), ';' order by oid) from pg_event_trigger),
 (select string_agg(concat_ws(',', roleid, member, grantor), ';' order by roleid, member) from pg_auth_members),
 (select string_agg(concat_ws(',', oid, polname), ';' order by oid) from pg_policy)));"
fp() { printf '%s\n' "$FP" | lab_sql postgres -qtA; }
# ejecuta archivos dentro de BEGIN READ ONLY … ROLLBACK, como $1 (rol opcional con SET LOCAL ROLE en $2)
ro() { local rol="$1"; shift; { printf 'BEGIN READ ONLY;\n'; [ -n "$rol" ] && printf 'SET LOCAL ROLE %s;\n' "$rol"; for a in "$@"; do cat "$a"; printf '\n'; done; printf 'ROLLBACK;\n'; } | lab_sql postgres -v ON_ERROR_STOP=1 "${VARS[@]}" 2>&1; }
VARS=()
FALLAS=0; TOTAL=0
chk() { TOTAL=$((TOTAL+1)); if [ "$1" = "ok" ]; then echo "PASA   $2"; else echo "FALLA  $2"; FALLAS=$((FALLAS+1)); fi; }

echo "# 1. Q0–Q5 en BEGIN READ ONLY (sin O-4), huella antes/después"
F0="$(fp)"
for q in "$Q"/Q[0-5]_*.sql; do
  n="$(basename "$q" .sql)"; VARS=(); ro "" "$q" > "$OUT/$n.sin_o4.txt"; rc=$?
  chk "$([ $rc -eq 0 ] && echo ok)" "$n corre en READ ONLY sin O-4 (rc=$rc)"
done
chk "$([ "$F0" = "$(fp)" ] && echo ok)" "huella del catálogo idéntica tras Q0–Q5"
grep -q "solo_lectura" "$OUT/Q0_sesion.sin_o4.txt" && grep -qE '^\s*on\s' "$OUT/Q0_sesion.sin_o4.txt" && chk ok "Q0 informa transaction_read_only = on" || chk no "Q0 informa transaction_read_only = on"
chk "$(! grep -qiE '^\s*(insert|update|delete|create|alter|drop|grant|revoke|truncate|set |reset )' "$Q"/Q[0-6]_*.sql && echo ok)" "las consultas no contienen sentencias de escritura (estático)"
VARS=(); out="$({ printf 'BEGIN READ ONLY;\ncreate temp table zz_intento(i int);\nROLLBACK;\n'; } | lab_sql postgres 2>&1)"
chk "$(printf '%s' "$out" | grep -q 'read-only transaction' && echo ok)" "control: una escritura dentro de READ ONLY falla"

echo "# 2. Matriz de estados con Q6 (abortar / revisar / sin_escrituras)"
q6() { # q6 <estado_esperado> -> "abortar|revisar|sin_escrituras"
  VARS=(-v "estado_esperado=$1"); ro "" "$Q/Q6_veredicto.sql" | sed -n '1p'; }
q6raw() { VARS=(-v "estado_esperado=$1" -qtA -F '|'); ro "" "$Q/Q6_veredicto.sql" | grep -v '^$' | tail -1; }
escenario() { # nombre estado_esperado patrón_en_abortar(o NULL) [patrón_en_revisar]
  local nombre="$1" est="$2" patron="$3" rev="${4:-}" a b s
  a="$(fp)"; r="$(q6raw "$est")"; b="$(fp)"; s="${r##*|}"
  echo "$nombre :: $r" >> "$OUT/Q6_resultados.txt"
  local ok=1
  [ "$a" = "$b" ] || ok=0
  [ "$s" = "t" ] || ok=0
  if [ "$patron" = "NULL" ]; then [ -z "${r%%|*}" ] || ok=0; else printf '%s' "${r%%|*}" | grep -qF -- "$patron" || ok=0; fi
  if [ -n "$rev" ]; then printf '%s' "$r" | cut -d'|' -f2 | grep -qF -- "$rev" || ok=0; fi
  chk "$([ $ok -eq 1 ] && echo ok)" "$nombre → abortar=${r%%|*} (esperado: $patron)"
}
mut() { # mut <nombre> <estado_esperado> <patrón> <setup> <undo> [patrón_revisar]
  printf '%s\n' "$4" | lab_sql postgres -q >/dev/null 2>"$OUT/mut_$1.stderr" || { chk no "$1: setup falló ($(head -c 150 "$OUT/mut_$1.stderr"))"; printf '%s\n' "$5" | lab_sql postgres -q >/dev/null 2>&1; return; }
  escenario "$1" "$2" "$3" "${6:-}"
  printf '%s\n' "$5" | lab_sql postgres -q >/dev/null 2>"$OUT/undo_$1.stderr" || chk no "$1: undo falló"
}
: > "$OUT/Q6_resultados.txt"
escenario "S0 sin O-4 (esperado remediado)"           remediado "public.rls_auto_enable() ausente"
printf '%s\n' "$ORIG" | lab_sql postgres -q >/dev/null 2>"$OUT/inst_orig.stderr" || { echo "abortado: instalar original" >&2; exit 6; }
escenario "S1 original / esperado original"           original  NULL
escenario "S1b original / esperado remediado"         remediado "sha256 de prosrc distinto del esperado"
printf '%s\n' "$MIGSQL" | lab_sql postgres -q >/dev/null 2>"$OUT/inst_mig.stderr" || { echo "abortado: aplicar migración" >&2; exit 6; }
escenario "S2 remediada / esperado remediado"         remediado NULL
escenario "S2b remediada / esperado original"         original  "sha256 de prosrc distinto del esperado"
escenario "S2c estado_esperado inválido"              zzz       "estado_esperado invalido"
mut M01 remediado "no esta en estado O"                "alter event trigger ensure_rls disable;"  "alter event trigger ensure_rls enable;"
mut M02 remediado "no esta en estado O"                "alter event trigger ensure_rls enable replica;" "alter event trigger ensure_rls enable;"
mut M03 remediado "no esta en estado O"                "alter event trigger ensure_rls enable always;"  "alter event trigger ensure_rls enable;"
mut M04 remediado "duplicado o con otro event trigger" "create event trigger ensure_rls_2 on ddl_command_end when tag in ($TAGS) execute function public.rls_auto_enable();" "drop event trigger ensure_rls_2;"
mut M05 remediado "ensure_rls ausente"                "drop event trigger ensure_rls;"           "$EVT3"
mut M06 remediado "tags de ensure_rls distintas"       "drop event trigger ensure_rls; create event trigger ensure_rls on ddl_command_end when tag in ('CREATE TABLE') execute function public.rls_auto_enable();" "drop event trigger ensure_rls; $EVT3"
mut M07 remediado "tags de ensure_rls distintas"       "drop event trigger ensure_rls; create event trigger ensure_rls on ddl_command_end when tag in ('CREATE TABLE','CREATE TABLE','CREATE TABLE AS','SELECT INTO') execute function public.rls_auto_enable();" "drop event trigger ensure_rls; $EVT3"
mut M08 remediado "EXECUTE para anon/authenticated/service_role" "grant execute on function public.rls_auto_enable() to authenticated;" "revoke execute on function public.rls_auto_enable() from authenticated;"
mut M09 remediado "EXECUTE para PUBLIC"              "grant execute on function public.rls_auto_enable() to public;" "revoke execute on function public.rls_auto_enable() from public;"
mut M10 remediado "owner distinto de postgres"         "create role zz_o nologin; grant zz_o to postgres with set true; grant create on schema public to zz_o; alter function public.rls_auto_enable() owner to zz_o; revoke create on schema public from zz_o;" "alter function public.rls_auto_enable() owner to postgres; drop owned by zz_o; drop role zz_o;"
mut M11 remediado "no es SECURITY DEFINER"            "alter function public.rls_auto_enable() security invoker;" "alter function public.rls_auto_enable() security definer;"
mut M12 remediado "proconfig distinto del esperado"    "alter function public.rls_auto_enable() set search_path = pg_catalog;" "alter function public.rls_auto_enable() set search_path = pg_catalog, pg_temp;"
mut M13 remediado "homonimos"                          "create schema zz_h; create function zz_h.rls_auto_enable() returns int language sql as 'select 1';" "drop schema zz_h cascade;"
mut M14 remediado "homonimos"                          "create function public.rls_auto_enable(int) returns int language sql as 'select 1';" "drop function public.rls_auto_enable(int);"
mut M15 remediado "sha256 de prosrc distinto"          "create or replace function public.rls_auto_enable() returns event_trigger language plpgsql security definer set search_path = pg_catalog, pg_temp as \$x\$ BEGIN NULL; END \$x\$;" "$REINSTALAR"
mut M16 remediado "tabla de public sin RLS"            "create table public.zz_sin_rls (i int); alter table public.zz_sin_rls disable row level security;" "drop table public.zz_sin_rls;"
mut M17 remediado NULL                                 "create role zz_login login;" "drop role zz_login;" "zz_login"
# Q4: rama con historial de migraciones (como en un proyecto Supabase real)
printf "%s\n" "create schema supabase_migrations; create table supabase_migrations.schema_migrations (version text primary key, name text); insert into supabase_migrations.schema_migrations values ('20261110120000', 'o4_pgtemp_remediacion');" | lab_sql postgres -q >/dev/null 2>"$OUT/hist.stderr"
VARS=(); r="$(ro "" "$Q/Q4_version.sql")"; echo "$r" > "$OUT/Q4_version.con_historial.txt"
chk "$(printf '%s' "$r" | grep -q '20261110120000' && echo ok)" "Q4 lista supabase_migrations.schema_migrations cuando existe"
printf 'drop schema supabase_migrations cascade;\n' | lab_sql postgres -q >/dev/null 2>&1
escenario "S3 remediada restaurada / esperado remediado" remediado NULL
# F7 (compensación): con ensure_rls remediado, una tabla nueva en public queda con RLS activa.
printf 'create table public.zz_f7 (i int);\n' | lab_sql postgres -q >/dev/null 2>&1
chk "$([ "$(printf "select relrowsecurity from pg_class where oid='public.zz_f7'::regclass;\n" | lab_sql postgres -qtA)" = "t" ] && echo ok)" "F7 (observación): CREATE TABLE en public deja RLS activa vía ensure_rls"
printf 'drop table public.zz_f7;\n' | lab_sql postgres -q >/dev/null 2>&1

echo "# 3. Privilegios: Q0–Q5 como postgres y como authenticated (informativo)"
: > "$OUT/privilegios.tsv"
for q in "$Q"/Q[0-5]_*.sql; do n="$(basename "$q" .sql)"
  for rol in "" authenticated; do VARS=(); r="$(ro "$rol" "$q")"; rc=$?
    printf '%s\t%s\t%s\t%s\n' "$n" "${rol:-postgres}" "$([ $rc -eq 0 ] && echo ok || echo ERROR)" "$(printf '%s' "$r" | grep -m1 ERROR | cut -c1-110)" >> "$OUT/privilegios.tsv"
  done
done
column -t -s $'\t' "$OUT/privilegios.tsv"

echo "# 4. Preflight estricto SIN marcador, en READ ONLY"
fa="$(fp)"
out="$({ printf 'BEGIN READ ONLY;\n'; cat "$PF"; printf '\nROLLBACK;\n'; } | lab_sql postgres 2>&1)"; rc=$?
chk "$([ $rc -eq 0 ] && printf '%s' "$out" | grep -q '\[ESTADO_A\]' && echo ok)" "preflight con O-4 remediada, READ ONLY: ESTADO_A (rc=$rc)"
printf '%s\n' "drop event trigger ensure_rls; drop function public.rls_auto_enable();" | lab_sql postgres -q >/dev/null 2>&1
out="$({ printf 'BEGIN READ ONLY;\n'; cat "$PF"; printf '\nROLLBACK;\n'; } | lab_sql postgres 2>&1)"; rc=$?
chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q '\[O4_AUSENTE\]' && ! printf '%s' "$out" | grep -q 'ESTADO_' && echo ok)" "preflight sin O-4 y sin marcador, READ ONLY: [O4_AUSENTE], sin ESTADO (rc=$rc)"
printf '%s\n' "$ORIG" | lab_sql postgres -q >/dev/null 2>&1
out="$({ printf 'BEGIN READ ONLY;\n'; cat "$PF"; printf '\nROLLBACK;\n'; } | lab_sql postgres 2>&1)"; rc=$?
chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q '\[O4_RLS_AUTO_ENABLE\]' && echo ok)" "preflight con O-4 original vulnerable: rechazo (rc=$rc)"
printf '%s\n' "$REINSTALAR" | lab_sql postgres -q >/dev/null 2>&1

{ docker ps -a --format '{{.ID}} {{.Names}} {{.Status}}'; echo '--- redes'; docker network ls --format '{{.Name}}'; echo '--- volúmenes'; docker volume ls --format '{{.Name}}'; } > "$OUT/docker_durante.txt"
echo "--- casos: $TOTAL, fallas: $FALLAS"
[ "$FALLAS" -eq 0 ]
