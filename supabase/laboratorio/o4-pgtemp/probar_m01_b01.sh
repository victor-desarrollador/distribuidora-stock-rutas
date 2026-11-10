#!/usr/bin/env bash
# M-01 / B-01 — pruebas focalizadas contra una base LOCAL DESCARTABLE SIN O-4
# (sin public.rls_auto_enable() ni ensure_rls), con las migraciones ya aplicadas.
# NO forma parte de `supabase test db`. No se ejecuta automáticamente.
#
# Dos modos de destino (fail-closed, nunca se aceptan hosts TCP):
#  (a) Contenedor: LAB_CONTAINER + LAB_NONCE (los crea probar_o4_docker.sh; ver
#      lab_comun.sh: sin red, sin puertos, sin montajes, imagen por digest).
#  (b) Socket Unix: PSQL_LAB_URL='postgresql://supabase_admin@/postgres?host=/dir_700&port=N'
#      + LAB_NONCE igual al de zz_laboratorio.identidad (directorio propio, modo 700).
# Se requiere un superusuario de la base descartable (SET ROLE en B-01).
# Sale con 0 sólo si TODOS los casos dan el resultado esperado.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../.." && pwd)"
PF="$REPO/supabase/scripts/validar_topologia_propietario_rpc.sql"
MIG="$REPO/supabase/migrations/20261110120000_o4_pgtemp_remediacion.sql"
[ -f "$PF" ] && [ -f "$MIG" ] || { echo "abortado: faltan archivos" >&2; exit 2; }
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGPASSWORD PGSERVICE PGSERVICEFILE DATABASE_URL SUPABASE_DB_URL || true
: "${LAB_NONCE:?falta LAB_NONCE}"

if [ -n "${LAB_CONTAINER:-}" ]; then
  . "$DIR/lab_comun.sh"
  lab_verificar; lab_identidad
  RUNSQL() { docker exec -i "$LAB_CONTAINER" psql -X -U supabase_admin -h localhost -d postgres -v ON_ERROR_STOP=1 "$@"; }
else
  : "${PSQL_LAB_URL:?falta LAB_CONTAINER o PSQL_LAB_URL}"
  case "$PSQL_LAB_URL" in postgresql://*@/*host=/*) ;; *) echo "abortado: PSQL_LAB_URL debe ser postgresql://usuario@/db?host=/ruta_socket (sin host TCP)" >&2; exit 2 ;; esac
  case "$PSQL_LAB_URL" in *hostaddr*|*,*|*' '*|*sslmode*|*service=*) echo "abortado: parámetros no admitidos" >&2; exit 2 ;; esac
  SOCKDIR="${PSQL_LAB_URL#*host=}"; SOCKDIR="${SOCKDIR%%&*}"
  [ -d "$SOCKDIR" ] && [ -O "$SOCKDIR" ] && [ "$(stat -c %a "$SOCKDIR")" = "700" ] \
    || { echo "abortado: el directorio del socket debe existir, ser propio y tener modo 700" >&2; exit 2; }
  case "$PSQL_LAB_URL" in *port=5432*|*:5432*) echo "abortado: puerto 5432 prohibido" >&2; exit 2 ;; esac
  RUNSQL() { psql "$PSQL_LAB_URL" -X -v ON_ERROR_STOP=1 "$@"; }
fi
q() { printf '%s\n' "$1" | RUNSQL -q -At; }
# Identidad: sin IP de servidor (socket/loopback interno), puerto != 5432, nonce
# coincidente con zz_laboratorio.identidad y servidor 17.x. Si algo no cuadra, aborta.
# En modo contenedor el 5432 es el puerto INTERNO de un contenedor sin red: no se exige.
[ "$(q "select (current_setting('port') <> '5432' or '${LAB_CONTAINER:-}' <> '') and current_setting('server_version_num')::int/10000 = 17 and exists (select 1 from zz_laboratorio.identidad where nonce = '$LAB_NONCE')")" = "t" ] \
  || { echo "abortado: el destino no es el laboratorio verificado" >&2; exit 2; }
[ "$(q "select to_regprocedure('public.rls_auto_enable()') is null and not exists (select 1 from pg_event_trigger where evtname='ensure_rls')")" = "t" ] \
  || { echo "abortado: la base debe ser SIN O-4" >&2; exit 2; }

FALLAS=0
# caso <nombre> <patrón_que_debe_aparecer> <patrón_que_NO_debe_aparecer|-> <rc_esperado: 0|!0> <sql_previo> <archivo> [rol]
caso() {
  local nombre="$1" debe="$2" nodebe="$3" rc_esp="$4" previo="$5" archivo="$6" rol="${7:-}" salida rc
  salida="$({ printf '%s\n%s\n' "BEGIN;${rol:+ SET LOCAL ROLE $rol;}" "$previo"; cat "$archivo"; printf '\nROLLBACK;\n'; } \
            | RUNSQL 2>&1)"; rc=$?
  local ok=1
  if [ "$rc_esp" = "0" ]; then [ $rc -eq 0 ] || ok=0; else [ $rc -ne 0 ] || ok=0; fi
  printf '%s' "$salida" | grep -qF -- "$debe" || ok=0
  if [ "$nodebe" != "-" ] && printf '%s' "$salida" | grep -qF -- "$nodebe"; then ok=0; fi
  if [ $ok -eq 1 ]; then echo "PASA   $nombre"; else echo "FALLA  $nombre (rc=$rc)"; printf '%s\n' "$salida" | tail -5; FALLAS=$((FALLAS+1)); fi
}
M="preflight_o4_ausente_laboratorio"
V="LABORATORIO_LOCAL_SIN_O4"

# --- M-01 ---
caso "M01-1 sin marcador: rechazo estricto [O4_AUSENTE], sin ESTADO_A"  "[O4_AUSENTE]" "ESTADO_A" '!0' "" "$PF"
caso "M01-2 marcador válido: ESTADO_LOCAL_SIN_O4 y nunca ESTADO_A"      "[ESTADO_LOCAL_SIN_O4]" "[ESTADO_A]" 0 \
  "CREATE TEMP TABLE $M (modo text); INSERT INTO $M VALUES ('$V');" "$PF"
caso "M01-3 marcador con valor erróneo"                                  "[O4_MARCADOR_INVALIDO]" "ESTADO_" '!0' \
  "CREATE TEMP TABLE $M (modo text); INSERT INTO $M VALUES ('otro');" "$PF"
caso "M01-4 marcador vacío (0 filas)"                                    "[O4_MARCADOR_INVALIDO]" "ESTADO_" '!0' \
  "CREATE TEMP TABLE $M (modo text);" "$PF"
caso "M01-5 marcador con 2 filas"                                        "[O4_MARCADOR_INVALIDO]" "ESTADO_" '!0' \
  "CREATE TEMP TABLE $M (modo text); INSERT INTO $M VALUES ('$V'),('$V');" "$PF"
caso "M01-6 marcador con columna extra"                                  "[O4_MARCADOR_INVALIDO]" "ESTADO_" '!0' \
  "CREATE TEMP TABLE $M (modo text, extra int); INSERT INTO $M(modo) VALUES ('$V');" "$PF"
caso "M01-7 marcador con tipo distinto de text"                          "[O4_MARCADOR_INVALIDO]" "ESTADO_" '!0' \
  "CREATE TEMP TABLE $M (modo varchar); INSERT INTO $M VALUES ('$V');" "$PF"
caso "M01-8 marcador con otro nombre de columna"                         "[O4_MARCADOR_INVALIDO]" "ESTADO_" '!0' \
  "CREATE TEMP TABLE $M (valor text); INSERT INTO $M VALUES ('$V');" "$PF"
caso "M01-9 marcador como vista temporal (relkind distinto)"             "[O4_MARCADOR_INVALIDO]" "ESTADO_" '!0' \
  "CREATE TEMP VIEW $M AS SELECT '$V'::text AS modo;" "$PF"
caso "M01-10 tabla PERMANENTE homónima en public no vale como marcador"  "[O4_AUSENTE]" "ESTADO_" '!0' \
  "CREATE TABLE public.$M (modo text); ALTER TABLE public.$M ENABLE ROW LEVEL SECURITY; INSERT INTO public.$M VALUES ('$V');" "$PF"
# --- B-01 ---
caso "B01-1 como no-postgres y O-4 ausente: ERROR de identidad (antes del retorno temprano)" \
  "debe ejecutarse como postgres" "O-4 ausente (entorno local)" '!0' "" "$MIG" authenticated
caso "B01-2 como postgres y O-4 ausente: sin cambios (NOTICE)" \
  "O-4 ausente (entorno local): sin cambios" "debe ejecutarse como postgres" 0 "" "$MIG" postgres

echo "--- fallas: $FALLAS"
[ "$FALLAS" -eq 0 ]
