#!/usr/bin/env bash
# O-4 PRESENTE — pruebas del preflight (sección 3.7) y de la migración
# 20261110120000 con public.rls_auto_enable() y ensure_rls presentes en distintos
# estados, SIN tocar el laboratorio de forma persistente: cada caso corre en
# BEGIN … ROLLBACK (el DDL, incluidos los event triggers, es transaccional).
# Requiere el contenedor del laboratorio (LAB_CONTAINER + LAB_NONCE; ver
# lab_comun.sh), SIN O-4 al comienzo. No forma parte de `supabase test db`.
# Bloque B: preflight (esperado ESTADO_A sólo con el contrato RB + RA completo).
# Bloque C: migración (comportamiento ante estados válidos y no válidos).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../.." && pwd)"
PF="$REPO/supabase/scripts/validar_topologia_propietario_rpc.sql"
MIG="$REPO/supabase/migrations/20261110120000_o4_pgtemp_remediacion.sql"
CUERPO="$DIR/cuerpo_original_325ae266.txt"
[ -f "$PF" ] && [ -f "$MIG" ] && [ -f "$CUERPO" ] || { echo "abortado: faltan archivos" >&2; exit 2; }
[ "$(sha256sum "$CUERPO" | cut -d' ' -f1)" = "325ae266d9b166715ef5230ceaf7ff9d523e483cf5610dfb9779ab3f183f4af9" ] || { echo "abortado: cuerpo de referencia alterado" >&2; exit 2; }
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGPASSWORD PGSERVICE PGSERVICEFILE DATABASE_URL SUPABASE_DB_URL || true
. "$DIR/lab_comun.sh"
lab_verificar; lab_identidad
[ "$(printf "select to_regprocedure('public.rls_auto_enable()') is null and not exists (select 1 from pg_event_trigger where evtname='ensure_rls');\n" | lab_sql postgres -qtA)" = "t" ] \
  || { echo "abortado: el laboratorio debe comenzar SIN O-4" >&2; exit 2; }

TAGS="'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO'"
# Estado ORIGINAL (cuerpo de staging 325ae266…, search_path=pg_catalog), como postgres.
# (cat con centinela «x»: conserva los saltos de línea finales y por tanto el hash exacto del cuerpo.)
ORIG="$(printf 'create function public.rls_auto_enable() returns event_trigger language plpgsql security definer set search_path = pg_catalog as $o4$'; cat "$CUERPO"; printf '$o4$;\nrevoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role;\ncreate event trigger ensure_rls on ddl_command_end when tag in (%s) execute function public.rls_auto_enable();\n' "$TAGS"; printf x)"; ORIG="${ORIG%x}"
# Estado REMEDIADO: ORIGINAL + la migración real.
REM_SQL() { printf '%s\n' "$ORIG"; cat "$MIG"; printf '\n'; }
NOOP="create or replace function public.rls_auto_enable() returns event_trigger language plpgsql security definer set search_path = pg_catalog, pg_temp as \$x\$ BEGIN NULL; END \$x\$;"

FALLAS=0; TOTAL=0
# caso <nombre> <estado: orig|rem|nada> <sql_extra> <archivo_a_ejecutar> <rc: 0|!0> <patrón> <patrón_prohibido|-> [rol]
caso() {
  local nombre="$1" estado="$2" extra="$3" archivo="$4" rc_esp="$5" debe="$6" nodebe="$7" rol="${8:-}" salida rc ok=1
  TOTAL=$((TOTAL+1))
  salida="$({ printf 'BEGIN;\nSET LOCAL client_min_messages = warning;\n'
              case "$estado" in orig) printf '%s\n' "$ORIG" ;; rem) REM_SQL ;; esac
              printf 'SET LOCAL client_min_messages = notice;\n'
              printf '%s\n' "$extra"
              [ -n "$rol" ] && printf 'SET LOCAL ROLE %s;\n' "$rol"
              cat "$archivo"; printf '\nROLLBACK;\n'; } | lab_sql postgres 2>&1)"; rc=$?
  if [ "$rc_esp" = "0" ]; then [ $rc -eq 0 ] || ok=0; else [ $rc -ne 0 ] || ok=0; fi
  printf '%s' "$salida" | grep -qF -- "$debe" || ok=0
  if [ "$nodebe" != "-" ] && printf '%s' "$salida" | grep -qF -- "$nodebe"; then ok=0; fi
  if [ $ok -eq 1 ]; then echo "PASA   $nombre (rc=$rc)"; else echo "FALLA  $nombre (rc=$rc)"; printf '%s\n' "$salida" | grep -E "ERROR|WARNING|ESTADO|NOTICE:  o4" | tail -4; FALLAS=$((FALLAS+1)); fi
}
R="[O4_RLS_AUTO_ENABLE]"

echo "# Bloque B — preflight con O-4 presente"
caso "B01 remediada (RB+RA, trigger válido): ESTADO_A"      rem  "" "$PF" 0 "[ESTADO_A]" "ESTADO_LOCAL"
caso "B02 original vulnerable: rechazo"                      orig "" "$PF" '!0' "$R" "ESTADO_"
caso "B03 hash desconocido: rechazo"                         rem  "$NOOP" "$PF" '!0' "$R" "ESTADO_"
caso "B04 trigger ausente: rechazo"                          rem  "drop event trigger ensure_rls;" "$PF" '!0' "no existe ensure_rls asociado" "ESTADO_"
caso "B05 trigger duplicado: rechazo"                        rem  "create event trigger ensure_rls_2 on ddl_command_end when tag in ($TAGS) execute function public.rls_auto_enable();" "$PF" '!0' "$R" "ESTADO_"
caso "B06 trigger deshabilitado: rechazo"                    rem  "alter event trigger ensure_rls disable;" "$PF" '!0' "$R" "ESTADO_"
caso "B07 trigger ENABLE REPLICA: rechazo"                   rem  "alter event trigger ensure_rls enable replica;" "$PF" '!0' "$R" "ESTADO_"
caso "B08 trigger ENABLE ALWAYS: rechazo"                    rem  "alter event trigger ensure_rls enable always;" "$PF" '!0' "$R" "ESTADO_"
caso "B09 tags alteradas (sólo CREATE TABLE): rechazo"       rem  "drop event trigger ensure_rls; create event trigger ensure_rls on ddl_command_end when tag in ('CREATE TABLE') execute function public.rls_auto_enable();" "$PF" '!0' "$R" "ESTADO_"
caso "B10 tags duplicadas: rechazo"                          rem  "drop event trigger ensure_rls; create event trigger ensure_rls on ddl_command_end when tag in ('CREATE TABLE','CREATE TABLE','CREATE TABLE AS','SELECT INTO') execute function public.rls_auto_enable();" "$PF" '!0' "$R" "ESTADO_"
caso "B11 tag de más (ALTER TABLE): rechazo"                 rem  "drop event trigger ensure_rls; create event trigger ensure_rls on ddl_command_end when tag in ($TAGS, 'ALTER TABLE') execute function public.rls_auto_enable();" "$PF" '!0' "$R" "ESTADO_"
caso "B12 EXECUTE a authenticated: rechazo"                  rem  "grant execute on function public.rls_auto_enable() to authenticated;" "$PF" '!0' "$R" "ESTADO_"
caso "B13 EXECUTE a anon: rechazo"                           rem  "grant execute on function public.rls_auto_enable() to anon;" "$PF" '!0' "$R" "ESTADO_"
caso "B14 EXECUTE a service_role: rechazo"                   rem  "grant execute on function public.rls_auto_enable() to service_role;" "$PF" '!0' "$R" "ESTADO_"
caso "B15 EXECUTE a PUBLIC: rechazo"                         rem  "grant execute on function public.rls_auto_enable() to public;" "$PF" '!0' "$R" "ESTADO_"
caso "B16 propietario incorrecto (rol ajeno): rechazo en O-4"  rem  "create role zz_owner nologin; grant zz_owner to postgres with set true; grant create on schema public to zz_owner; alter function public.rls_auto_enable() owner to zz_owner; revoke create on schema public from zz_owner;" "$PF" '!0' "$R" "ESTADO_"
caso "B17 sin SECURITY DEFINER: rechazo"                     rem  "alter function public.rls_auto_enable() security invoker;" "$PF" '!0' "$R" "ESTADO_"
caso "B18 proconfig sin pg_temp (RA ausente): rechazo"       rem  "alter function public.rls_auto_enable() set search_path = pg_catalog;" "$PF" '!0' "$R" "ESTADO_"
caso "B19 marcador temporal junto con O-4: rechazo"          rem  "create temp table preflight_o4_ausente_laboratorio (modo text); insert into preflight_o4_ausente_laboratorio values ('LABORATORIO_LOCAL_SIN_O4');" "$PF" '!0' "[O4_MARCADOR_INVALIDO]" "ESTADO_"

echo "# Bloque C — migración 20261110120000 (negativos y positivos)"
VERIF_PRE="create temp table zz_pre as select p.oid, p.proacl::text acl, p.proowner from pg_proc p where p.oid = to_regprocedure('public.rls_auto_enable()');"
VERIF_POST="do \$v\$ begin if not exists (select 1 from zz_pre z join pg_proc p on p.oid = z.oid and p.proacl::text is not distinct from z.acl and p.proowner = z.proowner and to_regprocedure('public.rls_auto_enable()') = z.oid) then raise exception 'VERIF_FALLA: OID, ACL u owner cambiaron'; end if; raise notice 'VERIF_OK: mismo OID, ACL y owner'; end \$v\$;"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
# CM01 necesita captura previa y verificación posterior alrededor de la migración.
{ cat "$MIG"; printf '\n%s\n' "$VERIF_POST"; } > "$TMP"
caso "CM01 original → remediada: aplica, mismo OID/ACL/owner"   orig "$VERIF_PRE" "$TMP" 0 "VERIF_OK" "VERIF_FALLA"
caso "CM02 remediada: nueva ejecución sin cambios"              rem  "" "$MIG" 0 "contrato remediado ya presente: sin cambios" "remediación aplicada"
caso "CM03 cuerpo desconocido con config original: error"       orig "$NOOP alter function public.rls_auto_enable() set search_path = pg_catalog;" "$MIG" '!0' "definición desconocida" "remediación aplicada"
caso "CM04 sin ensure_rls: error"                               orig "drop event trigger ensure_rls;" "$MIG" '!0' "ensure_rls fuera de contrato" "remediación aplicada"
caso "CM05 ensure_rls sin la función: error"                    nada "create function public.zz_f() returns event_trigger language plpgsql as \$q\$ begin null; end \$q\$; create event trigger ensure_rls on ddl_command_end execute function public.zz_f();" "$MIG" '!0' "ensure_rls existe sin public.rls_auto_enable()" "O-4 ausente (entorno local)"
caso "CM06 homónimo fuera de public sin la función: error"      nada "create schema zz_h; create function zz_h.rls_auto_enable() returns int language sql as 'select 1';" "$MIG" '!0' "homónimos de rls_auto_enable" "O-4 ausente (entorno local)"
caso "CM07 EXECUTE a PUBLIC: error sin cambios"                 orig "grant execute on function public.rls_auto_enable() to public;" "$MIG" '!0' "EXECUTE para PUBLIC" "remediación aplicada"
caso "CM08 rol no-postgres con O-4 presente: error de identidad" orig "" "$MIG" '!0' "debe ejecutarse como postgres" "remediación aplicada" authenticated
caso "CM09 rol no-postgres sobre remediada: error de identidad"  rem  "" "$MIG" '!0' "debe ejecutarse como postgres" "sin cambios" authenticated

echo "--- casos: $TOTAL, fallas: $FALLAS"
[ "$FALLAS" -eq 0 ]
