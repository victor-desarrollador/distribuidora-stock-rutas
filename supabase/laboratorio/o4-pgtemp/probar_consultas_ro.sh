#!/usr/bin/env bash
# Validación en LABORATORIO de las consultas READ ONLY Q0–Q6 (consultas_ro/) que se
# usarían para inventariar staging. NO se conecta a ningún destino remoto: crea UN
# contenedor descartable (sin red, sin puertos, sin montajes; ver lab_comun.sh),
# aplica las migraciones del repo, recorre una matriz de estados de O-4 y compara
# una huella del catálogo antes y después de cada consulta.
# Uso: probar_consultas_ro.sh <dir_salida_vacío_o_inexistente_fuera_del_repo>
set -uo pipefail
[ "$#" -eq 1 ] || { echo "uso: $0 <dir_salida_nuevo_absoluto_fuera_del_repo>" >&2; exit 2; }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../.." && pwd)"
. "$DIR/vinculo_evidencia.sh"
OUT="$1"
# Evidencia: directorio NUEVO, 700, fuera del repo, sin enlaces ni sobrescritura; commit, árbol y hashes se
# registran ANTES de ejecutar (modo estricto con GIT_COMMIT_ESPERADO y GIT_ARBOL_ESPERADO; si no, NO vinculada).
dir_evidencia_seguro "$OUT" || exit 2
vinculo_git "$OUT" || { echo "abortado: integridad del código no establecida; ver $OUT/vinculo_git.txt" >&2; exit 5; }
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGPASSWORD PGSERVICE PGSERVICEFILE DATABASE_URL SUPABASE_DB_URL || true
. "$DIR/lab_comun.sh"
Q="$DIR/consultas_ro"; PF="$REPO/supabase/scripts/validar_topologia_propietario_rpc.sql"
MIG="$REPO/supabase/migrations/20261110120000_o4_pgtemp_remediacion.sql"; CUERPO="$DIR/cuerpo_original_325ae266.txt"
[ "$(sha256sum "$CUERPO" | cut -d' ' -f1)" = "325ae266d9b166715ef5230ceaf7ff9d523e483cf5610dfb9779ab3f183f4af9" ] || { echo "abortado: cuerpo de referencia alterado" >&2; exit 2; }
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
# Q6 devuelve  abortar|digest_login_temp|sin_escrituras . Con TOK=AUTO se simula la revisión humana:
# primero se lee la huella de la lista actual y luego se la pasa como -v revision_login_temp.
q6bruto() { VARS=(-v "estado_esperado=$1" "${@:2}" -qtA -F '|'); ro "" "$Q/Q6_veredicto.sql" | grep -v '^$' | tail -1; }
digest_actual() { q6bruto "${1:-remediado}" | cut -d'|' -f2; }
q6raw() { # q6raw <estado> [AUTO|SIN|<huella>]
  local est="$1" tok="${2:-AUTO}"
  case "$tok" in
    SIN)  q6bruto "$est" ;;
    AUTO) q6bruto "$est" -v "revision_login_temp=$(digest_actual "$est")" ;;
    *)    q6bruto "$est" -v "revision_login_temp=$tok" ;;
  esac
}
escenario() { # nombre estado_esperado patrón_en_abortar(o NULL) [patrón_en_revisar]
  local nombre="$1" est="$2" patron="$3" rev="${4:-}" a b s
  a="$(fp)"; r="$(q6raw "$est")"; b="$(fp)"; s="${r##*|}"
  echo "$nombre :: $r" >> "$OUT/Q6_resultados.txt"
  local ok=1
  [ "$a" = "$b" ] || ok=0
  [ "$s" = "t" ] || ok=0
  if [ "$patron" = "NULL" ]; then [ -z "${r%%|*}" ] || ok=0; else printf '%s' "${r%%|*}" | grep -qF -- "$patron" || ok=0; fi
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
# Q4: rama con historial de migraciones (como en un proyecto Supabase real)
printf "%s\n" "create schema supabase_migrations; create table supabase_migrations.schema_migrations (version text primary key, name text); insert into supabase_migrations.schema_migrations values ('20261110120000', 'o4_pgtemp_remediacion');" | lab_sql postgres -q >/dev/null 2>"$OUT/hist.stderr"
VARS=(); r="$(ro "" "$Q/Q4_version.sql")"; echo "$r" > "$OUT/Q4_version.con_historial.txt"
chk "$(printf '%s' "$r" | grep -q '20261110120000' && echo ok)" "Q4 lista supabase_migrations.schema_migrations cuando existe"
printf 'drop schema supabase_migrations cascade;\n' | lab_sql postgres -q >/dev/null 2>&1
escenario "S3 remediada restaurada / esperado remediado" remediado NULL
# --- Compuerta obligatoria LOGIN+TEMP (todos los roles, incluidos reservados y superusuarios) ---
CERO="$(printf '0%.0s' $(seq 1 64))"
A1="$(q6raw remediado SIN)"
chk "$(printf '%s' "${A1%%|*}" | grep -qF 'compuerta LOGIN+TEMP' && echo ok)" "G1 sin huella de revisión: la compuerta LOGIN+TEMP aborta"
r="$(q6raw remediado AUTO)"; chk "$([ -z "${r%%|*}" ] && echo ok)" "G2 con la huella de la lista actual: pasa (simula la revisión humana)"
r="$(q6raw remediado "$CERO")"; chk "$(printf '%s' "${r%%|*}" | grep -qF 'compuerta LOGIN+TEMP' && echo ok)" "G3 huella incorrecta: aborta"
LISTA="$(printf "select string_agg(rolname || ':' || rolsuper::text, ',' order by rolname collate \"C\") from pg_roles r where r.rolcanlogin and has_database_privilege(r.oid, current_database(), 'TEMP');\n" | lab_sql postgres -qtA)"
chk "$(printf '%s' "$LISTA" | grep -q 'supabase_admin:true' && printf '%s' "$LISTA" | grep -q 'postgres:false' && echo ok)" "G5 la lista incluye superusuarios y roles de plataforma (supabase_admin, postgres): $(printf '%s' "$LISTA" | cut -c1-90)..."
HQ1="$({ printf 'BEGIN READ ONLY;\n'; cat "$Q/Q1_roles.sql"; printf 'ROLLBACK;\n'; } | lab_sql postgres -qtA | grep -E '^[0-9a-f]{64}$' | tail -1)"
chk "$([ -n "$HQ1" ] && [ "$HQ1" = "$(digest_actual remediado)" ] && echo ok)" "G6 la huella de Q1 coincide con la de Q6"
# Sensibilidad de la huella: cada dato revisado la modifica; es determinista y no depende de la zona horaria
sens() { # sens <nombre> <sql_aplicar>
  local antes despues; antes="$(digest_actual remediado)"
  printf '%s\n' "$2" | lab_sql postgres -q >/dev/null 2>"$OUT/sens_$1.stderr" || { chk no "$1: no se pudo aplicar ($(head -c 120 "$OUT/sens_$1.stderr"))"; return; }
  despues="$(digest_actual remediado)"; chk "$([ -n "$despues" ] && [ "$antes" != "$despues" ] && echo ok)" "H $1 cambia la huella"; }
D0="$(digest_actual remediado)"
printf 'create role zz_s login;\n' | lab_sql postgres -q >/dev/null 2>&1
chk "$([ "$D0" != "$(digest_actual remediado)" ] && echo ok)" "H1 un rol LOGIN nuevo invalida la revisión anterior"
sens connlimit "alter role zz_s connection limit 5;"
sens validuntil "alter role zz_s valid until '2030-01-01 00:00:00+00';"
sens rolconfig "alter role zz_s set statement_timeout = '5s';"
sens membresia "grant anon to zz_s;"
sens atributo "alter role zz_s createdb;"
DT1="$(digest_actual remediado)"
DT2="$({ printf 'BEGIN READ ONLY;\nset time zone %s;\n' "'Asia/Tokyo'"; cat "$Q/Q6_veredicto.sql"; printf 'ROLLBACK;\n'; } | lab_sql postgres -v ON_ERROR_STOP=1 -v estado_esperado=remediado -qtA -F '|' | grep -E '^[^|]*\|[0-9a-f]{64}\|[tf]$' | tail -1 | cut -d'|' -f2)"
chk "$([ -n "$DT2" ] && [ "$DT1" = "$DT2" ] && echo ok)" "H la huella no depende de la zona horaria de la sesión (valid until presente)"
printf 'drop role zz_s;\n' | lab_sql postgres -q >/dev/null 2>&1
chk "$([ "$D0" = "$(digest_actual remediado)" ] && echo ok)" "H la huella es determinista: vuelve al valor original al deshacer los cambios"
# Patrones de roles reservados: prefijo literal ("x*"), exacto, sin comodines de LIKE
printf "create role zz_pref_a login; create role zz_exacto login; create role zzxaxb login; create role zz_a_b_c login;\n" | lab_sql postgres -q >/dev/null 2>&1
PAT="zz_pref*, zz_exacto, zz_a_b*"
rj() { { printf "BEGIN READ ONLY;\nselect set_config('supautils.reserved_roles', '%s', true);\n" "$PAT"; cat "$Q/Q1_roles.sql"; printf 'ROLLBACK;\n'; } | lab_sql supabase_admin -v ON_ERROR_STOP=1 -qtA 2>&1; }
SAL="$(rj)"; RC=$?
ALTERADO=0
if ! { [ $RC -eq 0 ] && printf '%s' "$SAL" | grep -q '"patrones_reservados"'; }; then
  # La variable es SIGHUP: se fija en la configuración del servidor DESCARTABLE del laboratorio y se restaura al terminar.
  printf "alter system set supautils.reserved_roles = '%s'; select pg_reload_conf();\n" "$PAT" | lab_sql supabase_admin -q >/dev/null 2>"$OUT/alter_system.stderr" && ALTERADO=1 && sleep 2
  SAL="$({ printf 'BEGIN READ ONLY;\n'; cat "$Q/Q1_roles.sql"; printf 'ROLLBACK;\n'; } | lab_sql supabase_admin -v ON_ERROR_STOP=1 -qtA 2>&1)"; RC=$?
fi
if [ $RC -eq 0 ] && printf '%s' "$SAL" | grep -q '"patrones_reservados"'; then
  flag() { # flag <rol> <exacto|prefijo> → true/false, leyendo el JSON canónico impreso por Q1
    printf '%s' "$SAL" | python3 -I -c 'import sys,json; t=sys.stdin.read(); o,_=json.JSONDecoder().raw_decode(t[t.index("{"):]); r=[x for x in o["roles"] if x["rol"]==sys.argv[1]]; print(str(r[0]["reservado_"+sys.argv[2]]).lower() if r else "ausente")' "$1" "$2"; }
  chk "$([ "$(flag zz_pref_a prefijo)" = true ] && echo ok)" "R1 'zz_pref*' marca por prefijo a zz_pref_a"
  chk "$([ "$(flag zz_exacto exacto)" = true ] && [ "$(flag zz_exacto prefijo)" = false ] && echo ok)" "R2 'zz_exacto' marca sólo por coincidencia exacta"
  chk "$([ "$(flag zz_a_b_c prefijo)" = true ] && echo ok)" "R3 'zz_a_b*' marca a zz_a_b_c por prefijo literal"
  chk "$([ "$(flag zzxaxb prefijo)" = false ] && [ "$(flag zzxaxb exacto)" = false ] && echo ok)" "R4 '_' no actúa como comodín: zzxaxb NO coincide con 'zz_a_b*'"
  chk "$(printf '%s' "$SAL" | tr -d ' \n' | grep -q '"patrones_reservados":\["zz_a_b\*","zz_exacto","zz_pref\*"\]' && echo ok)" "R5 los patrones forman parte de la representación revisada, ordenados"
else
  echo "PENDIENTE  R1–R5 patrones reservados: no se pudo fijar supautils.reserved_roles en la sesión del laboratorio ($(printf '%s' "$SAL" | head -c 120)); no se simula el resultado"
fi
[ "$ALTERADO" -eq 1 ] && { printf "alter system reset supautils.reserved_roles; select pg_reload_conf();\n" | lab_sql supabase_admin -q >/dev/null 2>&1; sleep 1; }
printf 'drop role zz_pref_a; drop role zz_exacto; drop role zzxaxb; drop role zz_a_b_c;\n' | lab_sql postgres -q >/dev/null 2>&1

# Rol LOGIN de lectura real (zz_inventario_ro): ni postgres ni SET ROLE; Q00–Q6 completos, como el ejecutor
printf 'create role zz_inventario_ro login;\n' | lab_sql postgres -q >/dev/null 2>"$OUT/rol_ro.stderr" || echo "aviso: no se pudo crear zz_inventario_ro"
SID="$(printf 'select system_identifier::text from pg_control_system();\n' | lab_sql postgres -qtA)"
inv() { # inv <estado> [huella] → sesión completa Q00..Q6 como zz_inventario_ro
  local est="$1" tok="${2:-}"
  { printf 'BEGIN READ ONLY;\n'; for f in Q00_guardia Q0_sesion Q1_roles Q2_funcion Q3_event_triggers Q4_version Q5_rls Q6_veredicto; do cat "$Q/$f.sql"; printf '\n'; done; printf 'ROLLBACK;\n'; } \
   | lab_sql zz_inventario_ro -q -v "esperado_sysid=$SID" -v esperado_base=postgres -v esperado_usuario=zz_inventario_ro -v esperado_puerto=5432 -v "estado_esperado=$est" ${tok:+-v "revision_login_temp=$tok"} 2>&1; }
SAL="$(inv remediado)"; RC=$?
chk "$([ $RC -eq 0 ] && printf '%s' "$SAL" | grep -q 'GUARDIA|OK' && printf '%s' "$SAL" | grep -qF 'compuerta LOGIN+TEMP' && echo ok)" "L1 rol de lectura: Q00–Q6 completos corren y la compuerta aborta sin huella (rc=$RC)"
TOKL="$(printf '%s' "$SAL" | grep -E '^[^|]*\|[0-9a-f]{64}\|[tf]$' | tail -1 | cut -d'|' -f2)"
SAL="$(inv remediado "$TOKL")"; RC=$?; VERL="$(printf '%s' "$SAL" | grep -E '^[^|]*\|[0-9a-f]{64}\|[tf]$' | tail -1)"
chk "$([ $RC -eq 0 ] && [ -n "$VERL" ] && [ -z "${VERL%%|*}" ] && [ "${VERL##*|}" = t ] && echo ok)" "L2 rol de lectura con la huella revisada: Q6 exitoso y sin escrituras (rc=$RC)"
chk "$(printf '%s' "$SAL" | grep -q 'zz_inventario_ro' && echo ok)" "L3 el propio rol de lectura figura en la lista LOGIN+TEMP revisada"
printf 'create schema supabase_migrations; create table supabase_migrations.schema_migrations (version text primary key, name text); insert into supabase_migrations.schema_migrations values (%s, %s);\n' "'20261110120000'" "'o4'" | lab_sql postgres -q >/dev/null 2>&1
SAL="$(inv remediado "$TOKL")"; RC=$?
chk "$([ $RC -eq 0 ] && printf '%s' "$SAL" | grep -q 'DEPENDENCIA PENDIENTE' && ! printf '%s' "$SAL" | grep -q '20261110120000' && echo ok)" "L4 Q4 con historial y rol sin privilegio: dependencia pendiente informada, historial no leído, sin ampliar privilegios (rc=$RC)"
echo "PENDIENTE  L5 lectura del historial por el rol de staging: requiere USAGE/SELECT sobre supabase_migrations.schema_migrations; el privilegio NO está definido ni se otorgó (decisión humana)"
printf 'drop schema supabase_migrations cascade;\n' | lab_sql postgres -q >/dev/null 2>&1
# Guardia Q00 dentro del laboratorio (como zz_inventario_ro)
g() { { printf 'BEGIN READ ONLY;\n'; cat "$Q/Q00_guardia.sql"; printf 'ROLLBACK;\n'; } | lab_sql zz_inventario_ro -v ON_ERROR_STOP=1 "$@" 2>&1; }
GV=(-v "esperado_sysid=$SID" -v esperado_base=postgres -v esperado_usuario=zz_inventario_ro -v esperado_puerto=5432 -v estado_esperado=remediado)
out="$(g "${GV[@]}")"; rc=$?; chk "$([ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'GUARDIA|OK' && echo ok)" "Q00 con identidad correcta: GUARDIA|OK"
out="$(g -v "esperado_sysid=1234567890123" "${GV[@]:2}")"; rc=$?; chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'system_identifier distinto' && echo ok)" "Q00 con sysid ajeno: aborta (rc=$rc)"
out="$(g "${GV[@]}" -v esperado_base=otra)"; rc=$?; chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'base distinta' && echo ok)" "Q00 con base ajena: aborta (rc=$rc)"
out="$(g "${GV[@]}" -v esperado_usuario=otro)"; rc=$?; chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'current_user distinto' && echo ok)" "Q00 con usuario ajeno: aborta (rc=$rc)"
out="$(g "${GV[@]}" -v esperado_puerto=1)"; rc=$?; chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'puerto distinto' && echo ok)" "Q00 con puerto ajeno: aborta (rc=$rc)"
out="$(g "${GV[@]}" -v estado_esperado=zzz)"; rc=$?; chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'estado_esperado invalido' && echo ok)" "Q00 con estado inválido: aborta (rc=$rc)"
out="$({ printf 'BEGIN READ ONLY;\n'; cat "$Q/Q00_guardia.sql"; printf 'ROLLBACK;\n'; } | lab_sql postgres -v ON_ERROR_STOP=1 -v "esperado_sysid=$SID" -v esperado_base=postgres -v esperado_usuario=postgres -v esperado_puerto=5432 -v estado_esperado=remediado 2>&1)"; rc=$?
chk "$([ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'no puede ser postgres' && echo ok)" "Q00 no admite a postgres como sustituto del rol de lectura (rc=$rc)"
printf 'drop role zz_inventario_ro;\n' | lab_sql postgres -q >/dev/null 2>&1
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
