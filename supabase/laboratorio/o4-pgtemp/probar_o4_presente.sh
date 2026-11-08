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
# ACL REALMENTE NULL (pg_proc.proacl IS NULL) con el contrato RB + RA completo, por DDL y sin tocar el catálogo:
# GRANT EXECUTE … TO PUBLIC NO produce NULL (deja una ACL explícita con «=X/postgres», igual que B15). PostgreSQL deja
# proacl NULL sólo cuando la función se crea con exactamente los privilegios por defecto de PostgreSQL. La cadena de migraciones
# (20261024010921) revoca EXECUTE de PUBLIC por defecto para postgres, así que una función nueva nace con {postgres=X/postgres}:
# para obtener NULL hay que deshacer transitoriamente ese REVOKE. Se reconstruye la función
# remediada con su propia definición (pg_get_functiondef) bajo ALTER DEFAULT PRIVILEGES transitorio y se restauran los
# privilegios por defecto originales dentro del mismo bloque (se recuerda qué había antes). Precondiciones
# fail-closed: si proacl no es NULL, o el hash/proconfig no son los de RB + RA, el bloque aborta con PRECONDICION_BA16.
NULL_REAL="do \$n\$
declare d text; v_acl aclitem[]; v_hash text; v_cfg text[]; v_glob boolean; v_sch aclitem[]; v_pub boolean; v_anon boolean; v_auth boolean; v_srv boolean;
begin
  v_glob := exists (select 1 from pg_default_acl a where a.defaclrole = 'postgres'::regrole and a.defaclnamespace = 0 and a.defaclobjtype = 'f');
  select a.defaclacl into v_sch from pg_default_acl a where a.defaclrole = 'postgres'::regrole and a.defaclnamespace = 'public'::regnamespace and a.defaclobjtype = 'f';
  v_pub := v_sch is null or exists (select 1 from unnest(v_sch) x where x::text = '=X/postgres');
  v_anon := v_sch is not null and exists (select 1 from unnest(v_sch) x where x::text = 'anon=X/postgres');
  v_auth := v_sch is not null and exists (select 1 from unnest(v_sch) x where x::text = 'authenticated=X/postgres');
  v_srv := v_sch is not null and exists (select 1 from unnest(v_sch) x where x::text = 'service_role=X/postgres');
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.oid = to_regprocedure('public.rls_auto_enable()');
  drop event trigger ensure_rls;
  drop function public.rls_auto_enable();
  alter default privileges for role postgres grant execute on functions to public;
  alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated, service_role, public;
  execute d;
  if v_glob then alter default privileges for role postgres revoke execute on functions from public; end if;
  if v_pub then alter default privileges for role postgres in schema public grant execute on functions to public; else alter default privileges for role postgres in schema public revoke execute on functions from public; end if;
  if v_anon then alter default privileges for role postgres in schema public grant execute on functions to anon; end if;
  if v_auth then alter default privileges for role postgres in schema public grant execute on functions to authenticated; end if;
  if v_srv then alter default privileges for role postgres in schema public grant execute on functions to service_role; end if;
  create event trigger ensure_rls on ddl_command_end when tag in ($TAGS) execute function public.rls_auto_enable();
  select p.proacl, encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex'), p.proconfig into v_acl, v_hash, v_cfg
    from pg_proc p where p.oid = to_regprocedure('public.rls_auto_enable()');
  if v_acl is not null then raise exception 'PRECONDICION_BA16: proacl no es NULL (%)', v_acl; end if;
  if v_hash <> 'e1b231fb7db1d25c9dfab71d09dbc968c092c00c0049aca1f529f7e79296fb6e' or v_cfg::text <> '{\"search_path=pg_catalog, pg_temp\"}' then
    raise exception 'PRECONDICION_BA16: hash o proconfig distintos de RB + RA'; end if;
  raise notice 'PRECONDICION_BA16_OK: proacl IS NULL, hash e1b231fb…, proconfig RA';
end \$n\$;"
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

RESIDUOS_SQL="select md5(coalesce((select string_agg(d::text, '|' order by d::text) from pg_default_acl d), '')) || '|' || (to_regprocedure('public.rls_auto_enable()') is null)::text || '|' || (select count(*) from pg_event_trigger)::text || '|' || (select count(*) from pg_roles where rolname like 'zz\\_%')::text;"
RES_ANTES="$(printf '%s\n' "$RESIDUOS_SQL" | lab_sql postgres -qtA)"
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
A="ACL distinta de {postgres=X/postgres}"
# E-O4-ACL (decisión humana, sólo LOCAL; ADR-001 §18.2.2). Los identificadores BA16..BA20 corresponden
# a los casos «B16–B20» de la decisión; se prefijan con «A» (ACL) porque B16..B19 ya designan otros casos.
# BA16 usa proacl NULL real (ver NULL_REAL); B15 (GRANT … TO PUBLIC) deja una ACL EXPLÍCITA con «=X/postgres», no NULL.
caso "BA16 precondición: proacl IS NULL verificado en la base antes del preflight (RB+RA íntegro)" rem "$NULL_REAL" "$PF" '!0' "PRECONDICION_BA16_OK" "PRECONDICION_BA16:"
caso "BA16b proacl REALMENTE NULL (distinto de B15, que deja ACL explícita con PUBLIC): rechazo fail-closed" rem "$NULL_REAL" "$PF" '!0' "ACL distinta de {postgres=X/postgres} (E-O4-ACL; ACL actual: NULL)" "cuerpo distinto"
caso "BA17 grantee adicional fuera de la lista (zz_acl): rechazo" rem  "create role zz_acl nologin; grant execute on function public.rls_auto_enable() to zz_acl;" "$PF" '!0' "$A" "ESTADO_"
caso "BA18 WITH GRANT OPTION del propietario: rechazo"          rem  "grant execute on function public.rls_auto_enable() to postgres with grant option;" "$PF" '!0' "$A" "ESTADO_"
caso "BA19 ACL vacía (propietario sin EXECUTE): rechazo"        rem  "revoke execute on function public.rls_auto_enable() from postgres;" "$PF" '!0' "$A" "ESTADO_"
caso "BA20 grantee adicional con GRANT OPTION (zz_acl): rechazo" rem "create role zz_acl nologin; grant execute on function public.rls_auto_enable() to zz_acl with grant option;" "$PF" '!0' "$A" "ESTADO_"
caso "BA21 ACL exacta {postgres=X/postgres}: sin defecto de ACL" rem  "" "$PF" 0 "[ESTADO_A]" "$A"

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

TOTAL=$((TOTAL+1)); RES_DESPUES="$(printf '%s\n' "$RESIDUOS_SQL" | lab_sql postgres -qtA)"
if [ "$RES_ANTES" = "$RES_DESPUES" ] && printf '%s' "$RES_DESPUES" | grep -q '|true|'; then echo "PASA   R01 sin residuos: rollback completo (pg_default_acl, O-4 ausente, event triggers y roles zz_* idénticos: $RES_DESPUES)"; else echo "FALLA  R01 residuos tras los casos (antes=$RES_ANTES despues=$RES_DESPUES)"; FALLAS=$((FALLAS+1)); fi
echo "--- casos: $TOTAL, fallas: $FALLAS"
[ "$FALLAS" -eq 0 ]
