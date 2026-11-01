#!/usr/bin/env bash
# =============================================================================
# Arnés de concurrencia de jornadas — orquestador (ADR-001 §18.4.11).
#
# Uso:   supabase/tests/concurrencia/arnes.sh [CASO ...]
#        (sin argumentos ejecuta todos los casos de casos.sh, AUTO primero)
#
# Parámetros (sólo por variables de entorno; no acepta host, puerto ni URL):
#   ARNES_PG_BIN     directorio de binarios de PostgreSQL 17
#                    (por defecto /usr/lib/postgresql/17/bin)
#   ARNES_R          repeticiones por caso y por orden (por defecto 10)
#   ARNES_PLAZO      segundos: lock_timeout, statement_timeout y cota de cada
#                    espera del arnés (por defecto 30). Es sólo una cota de
#                    FALLO: nunca se usa como prueba de sincronización.
#   ARNES_CONSERVAR  1 = no borra el directorio temporal (diagnóstico)
#
# Sólo usa bash, psql, initdb y pg_ctl de PostgreSQL 17 (más utilidades básicas
# del sistema: mktemp, mkfifo, grep, awk, sort, sleep). Crea su propio clúster
# efímero (listen_addresses = '', socket Unix en un directorio temporal, puerto
# propio, deadlock_timeout reducido), aplica 00_bootstrap_descartable.sql y
# todas las migraciones de supabase/migrations/ en orden lexicográfico, ejecuta
# los casos y al final detiene y borra el clúster. Nunca se conecta a Supabase
# local, staging ni producción.
#
# Mecanismo (§18.4.11, con las decisiones 5c y 5f aprobadas el 01/11/2026):
#   - una sesión de CONTROL retiene, con pg_advisory_lock de sesión, las claves
#     que las RPC usan (18.4.5), en el orden global; no espera ni escribe;
#   - T1 y T2 son conexiones psql independientes con el claim de un dueño
#     activo, SET LOCAL ROLE authenticated y la fachada public real;
#   - un MONITOR de sólo lectura (default_transaction_read_only = on) observa
#     pg_stat_activity (incluida backend_xid), pg_locks y pg_blocking_pids;
#   - toda observación se acepta sólo si dos lecturas consecutivas son
#     idénticas; si cambian, se reintenta (foto estable estricta);
#   - el orden de la cola NO se supone por el orden de lanzamiento: se lee de
#     pg_blocking_pids y el oráculo se indexa por la sesión observada delante;
#   - cualquier bloqueante que no sea el control o el otro participante hace
#     fallar el caso (la instrumentación no puede introducir esperas ajenas);
#   - 5c: la sesión que vuelve conserva su transacción abierta; se observa lo
#     que retiene y se confirma ANTES de esperar a la otra sesión;
#   - los resultados se clasifican sólo por SQLSTATE (y, en los errores de
#     negocio, por el código que la RPC pone en message), nunca por el texto
#     traducido de un mensaje de PostgreSQL.
#
# Criterio de aprobación (exit 0): todos los casos PASS; la autoverificación
# AUTO produce un 40P01 por repetición; la diferencia de deadlocks del clúster
# y las líneas «deadlock detected» del log son exactamente las de AUTO; cero
# 40P01 y 40001 fuera de AUTO; ninguna espera supera el plazo; sin residuos.
# Exit 1: algún caso falló. Exit 2: entorno inválido o error de preparación.
# =============================================================================
set -uo pipefail
trap '' PIPE
export LC_ALL=C

# Sólo el clúster propio: se descarta toda variable PG* del entorno.
for _v in $(compgen -e); do
  case $_v in PG*) unset "$_v" ;; esac
done
unset _v

ARNES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RAIZ=$(cd "$ARNES_DIR/../../.." && pwd)
MIGRACIONES_DIR="$RAIZ/supabase/migrations"
BOOTSTRAP="$ARNES_DIR/00_bootstrap_descartable.sql"

PGBIN=${ARNES_PG_BIN:-/usr/lib/postgresql/17/bin}
R=${ARNES_R:-10}
PLAZO=${ARNES_PLAZO:-30}
CONSERVAR=${ARNES_CONSERVAR:-0}
PUERTO=55431

error_entorno() { echo "arnés: $*" >&2; exit 2; }

[[ $R =~ ^[1-9][0-9]*$ ]] || error_entorno "ARNES_R debe ser un entero positivo"
[[ $PLAZO =~ ^[1-9][0-9]*$ ]] || error_entorno "ARNES_PLAZO debe ser un entero positivo (segundos)"
for _b in initdb pg_ctl postgres psql; do
  [[ -x "$PGBIN/$_b" ]] || error_entorno "falta $PGBIN/$_b"
  "$PGBIN/$_b" --version | grep -Eq '\(PostgreSQL\) 17\.' \
    || error_entorno "$PGBIN/$_b no es PostgreSQL 17: $("$PGBIN/$_b" --version)"
done
unset _b
[[ -f "$BOOTSTRAP" ]] || error_entorno "falta $BOOTSTRAP"
compgen -G "$MIGRACIONES_DIR/*.sql" >/dev/null || error_entorno "no hay migraciones en $MIGRACIONES_DIR"

TMP=$(mktemp -d /tmp/arnes.XXXXXX) || error_entorno "mktemp falló"
SOCK="$TMP/s"
DATA="$TMP/d"
LOG_SERVIDOR="$TMP/servidor.log"
mkdir "$SOCK"
(( ${#SOCK} + 20 <= 107 )) || error_entorno "ruta de socket demasiado larga: $SOCK"

# -----------------------------------------------------------------------------
# Limpieza
# -----------------------------------------------------------------------------
declare -A S_FD=() S_PROC=() S_PID=() S_OUT=() S_N=() S_TOK=()
CLUSTER_ARRIBA=0

ses_cerrar() {
  local n=$1 fd=${S_FD[$1]:-} proc=${S_PROC[$1]:-} i
  [[ -n $fd ]] || return 0
  printf '\\q\n' >&"$fd" 2>/dev/null
  exec {fd}>&-
  for (( i = 0; i < 500; i++ )); do
    kill -0 "$proc" 2>/dev/null || break
    sleep 0.01
  done
  kill -9 "$proc" 2>/dev/null
  wait "$proc" 2>/dev/null
  unset "S_FD[$n]" "S_PROC[$n]" "S_PID[$n]" "S_OUT[$n]" "S_N[$n]" "S_TOK[$n]"
}

cerrar_todas() {
  local n
  for n in "${!S_FD[@]}"; do ses_cerrar "$n"; done
}

limpieza() {
  cerrar_todas
  if (( CLUSTER_ARRIBA )); then
    "$PGBIN/pg_ctl" -D "$DATA" -m immediate -w stop >/dev/null 2>&1
  fi
  if [[ $CONSERVAR == 1 ]]; then
    echo "arnés: directorio conservado en $TMP" >&2
  else
    rm -rf "$TMP"
  fi
}
trap limpieza EXIT
trap 'exit 130' INT TERM

# -----------------------------------------------------------------------------
# Clúster efímero
# -----------------------------------------------------------------------------
_psql() { "$PGBIN/psql" -X -A -t -q -h "$SOCK" -p "$PUERTO" "$@"; }
sql_admin() { _psql -v ON_ERROR_STOP=1 -U supabase_admin -d "$1" -c "$2"; }
sql_pg()    { _psql -v ON_ERROR_STOP=1 -U postgres -d "$1" -c "$2"; }
# Monitor: conexión aparte, de sólo lectura, sin bloqueos que choquen con las RPC.
mon()       { PGOPTIONS='-c default_transaction_read_only=on' _psql -U supabase_admin -d "$1" -c "$2"; }

iniciar_cluster() {
  "$PGBIN/initdb" -D "$DATA" -U supabase_admin --auth=trust -E UTF8 --locale=C.UTF-8 \
    >"$TMP/initdb.log" 2>&1 || { cat "$TMP/initdb.log" >&2; return 1; }
  cat >>"$DATA/postgresql.conf" <<EOF
listen_addresses = ''
unix_socket_directories = '$SOCK'
port = $PUERTO
cluster_name = 'arnes_concurrencia'
deadlock_timeout = '200ms'
lc_messages = 'C'
max_connections = 40
log_line_prefix = '%m [%p] %d '
EOF
  "$PGBIN/pg_ctl" -D "$DATA" -l "$LOG_SERVIDOR" -w -t 60 start >/dev/null || return 1
  CLUSTER_ARRIBA=1
}

preparar_plantilla() {
  local m
  sql_admin postgres "create database arnes" >/dev/null || return 1
  _psql -v ON_ERROR_STOP=1 -v arnes_descartable=1 -U supabase_admin -d arnes -f "$BOOTSTRAP" \
    || { echo "arnés: falló el bootstrap" >&2; return 1; }
  for m in "$MIGRACIONES_DIR"/*.sql; do
    _psql -v ON_ERROR_STOP=1 -U postgres -d arnes -f "$m" >"$TMP/migracion.log" 2>&1 \
      || { echo "arnés: falló la migración $(basename "$m")" >&2; cat "$TMP/migracion.log" >&2; return 1; }
    MIGRACIONES_APLICADAS=$(( ${MIGRACIONES_APLICADAS:-0} + 1 ))
  done
  fixtures_sql | _psql -v ON_ERROR_STOP=1 -U postgres -d arnes -f - >/dev/null \
    || { echo "arnés: fallaron los datos iniciales" >&2; return 1; }
}

# Cada repetición usa una base nueva, copia de la plantilla `arnes`.
NBASE=0
BASE=""
DEADLOCKS_CASOS=0
nueva_base() {
  NBASE=$(( NBASE + 1 ))
  BASE="rep$NBASE"
  sql_admin postgres "create database $BASE template arnes owner postgres" >/dev/null
}

# Espera a que no quede ningún backend en la base, suma sus deadlocks y la borra.
borrar_base() {
  local b=$1 i n d
  cerrar_todas
  for (( i = 0; i < PLAZO * 100; i++ )); do
    n=$(mon postgres "select count(*) from pg_stat_activity where datname = '$b'")
    [[ $n == 0 ]] && break
    sleep 0.01
  done
  [[ $n == 0 ]] || { echo "arnés: quedaron $n backends en $b" >&2; RESIDUOS=$(( RESIDUOS + n )); }
  d=$(mon postgres "select coalesce((select deadlocks from pg_stat_database where datname = '$b'), 0)")
  DEADLOCKS_ULTIMA_BASE=$d
  sql_admin postgres "drop database $b" >/dev/null
}

# -----------------------------------------------------------------------------
# Sesiones psql persistentes (FIFO de entrada, archivo de salida)
# -----------------------------------------------------------------------------
NSES=0
ses_abrir() {   # nombre base [usuario]
  local n=$1 b=$2 u=${3:-postgres} fifo out fd
  NSES=$(( NSES + 1 ))
  fifo="$TMP/ses$NSES.in"
  out="$TMP/ses$NSES.out"
  mkfifo "$fifo"
  : >"$out"
  "$PGBIN/psql" -X -A -t -q -h "$SOCK" -p "$PUERTO" -U "$u" -d "$b" \
    -v ON_ERROR_STOP=0 -v VERBOSITY=verbose <"$fifo" >"$out" 2>&1 &
  S_PROC[$n]=$!
  exec {fd}>"$fifo"
  S_FD[$n]=$fd
  S_OUT[$n]=$out
  S_N[$n]=0
  ses_enviar "$n" "select 'PID|' || pg_backend_pid();"
  ses_esperar "$n" "${S_TOK[$n]}" || return 1
  S_PID[$n]=$(ses_tramo "$n" "${S_TOK[$n]}" | sed -n 's/^PID|//p' | tail -1)
  [[ -n ${S_PID[$n]} ]]
}

ses_enviar() {  # nombre sql
  local n=$1 k
  k=$(( S_N[$n] + 1 ))
  S_N[$n]=$k
  S_TOK[$n]=$k
  printf '%s\n\\echo @@F%s@@\n' "$2" "$k" >&"${S_FD[$n]}"
}

ses_listo() { grep -qxF "@@F$2@@" "${S_OUT[$1]}"; }

ses_esperar() { # nombre token: espera el marcador; el plazo es sólo cota de fallo
  local n=$1 k=$2 i
  for (( i = 0; i < PLAZO * 200; i++ )); do
    ses_listo "$n" "$k" && return 0
    kill -0 "${S_PROC[$n]}" 2>/dev/null || return 1
    sleep 0.005
  done
  return 1
}

ses_tramo() {   # nombre token: líneas emitidas entre el marcador anterior y éste
  awk -v a="@@F$(( $2 - 1 ))@@" -v b="@@F$2@@" -v ini=$(( $2 == 1 ? 1 : 0 )) '
    ini && $0 == b { exit }
    ini { print; next }
    $0 == a { ini = 1 }' "${S_OUT[$1]}"
}

# Bloque de llamada: transacción explícita que NO se confirma aquí (5c).
bloque_llamada() {  # actor expresion
  local claims=''
  if [[ -n $1 ]]; then
    claims="select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true);
set local role authenticated;"
  fi
  cat <<EOF
begin;
$claims
set local lock_timeout = '${PLAZO}s';
set local statement_timeout = '${PLAZO}s';
\\unset r
select $2 as r \\gset
\\if :ERROR
\\echo RES|:SQLSTATE|:LAST_ERROR_MESSAGE
\\elif :{?r}
\\echo RES|:SQLSTATE|:r
\\else
\\echo RES|:SQLSTATE|void
\\endif
EOF
}

ses_lanzar() {  # nombre actor expresion  (actor vacío = sin claims, como postgres)
  ses_enviar "$1" "$(bloque_llamada "$2" "$3")"
}

# Resultado de la última llamada: "SQLSTATE|valor" (valor = uuid, vacío o código).
ses_resultado() {
  local n=$1
  ses_esperar "$n" "${S_TOK[$n]}" || { echo "SIN_RESPUESTA|"; return 1; }
  ses_tramo "$n" "${S_TOK[$n]}" | grep '^RES|' | tail -1 | cut -d'|' -f2-
}

ses_comando() { # nombre sql: envía y espera
  ses_enviar "$1" "$2"
  ses_esperar "$1" "${S_TOK[$1]}"
}

ses_fin() { ses_comando "$1" "commit;"; }     # en transacción abortada equivale a ROLLBACK
ses_revertir() { ses_comando "$1" "rollback;"; }

# -----------------------------------------------------------------------------
# Claves advisory (las mismas cadenas que las RPC; ADR-001 §18.4.5)
# -----------------------------------------------------------------------------
declare -A CLAVE_CACHE=()
clave_txt() {
  local t=$1
  if [[ -z ${CLAVE_CACHE[$t]:-} ]]; then
    CLAVE_CACHE[$t]=$(sql_admin postgres "select pg_catalog.hashtextextended('$t', 0)")
  fi
  printf '%s' "${CLAVE_CACHE[$t]}"
}
kv() { clave_txt "jornadas:vendedor:$EMPRESA:$1"; }   # nivel 2
kc() { clave_txt "jornadas:camion:$EMPRESA:$1"; }     # nivel 1
lista() { (( $# )) || { printf ''; return; }; printf '%s\n' "$@" | sort -n | paste -sd, -; }

# -----------------------------------------------------------------------------
# Monitor: foto de una sesión y foto estable estricta
# Campos: 1 state | 2 wait_event_type | 3 wait_event | 4 xid (N/S) |
#         5 pg_blocking_pids | 6 advisory concedidos | 7 advisory esperados |
#         8 esperas de fila (tuple/transactionid no concedidos) |
#         9 RowExclusiveLock concedidos sobre las tablas de jornadas |
#        10 filas de operaciones con la clave idempotente indicada
# -----------------------------------------------------------------------------
foto() {   # pid [clave_idempotente]
  local p=$1 k=${2:-}
  local ops="'-'"
  [[ -n $k ]] && ops="(select count(*) from public.operaciones o where o.idempotency_key = '$k')::text"
  mon "$BASE" "
select concat_ws('|',
  coalesce(a.state, '-'), coalesce(a.wait_event_type, '-'), coalesce(a.wait_event, '-'),
  case when a.backend_xid is null then 'N' else 'S' end,
  coalesce((select string_agg(b::text, ',' order by b) from unnest(pg_blocking_pids($p)) b), ''),
  coalesce((select string_agg(k::text, ',' order by k) from (
     select ((l.classid::bigint << 32) | l.objid::bigint) k from pg_locks l
      where l.pid = $p and l.locktype = 'advisory' and l.objsubid = 1 and l.granted) s), ''),
  coalesce((select string_agg(k::text, ',' order by k) from (
     select ((l.classid::bigint << 32) | l.objid::bigint) k from pg_locks l
      where l.pid = $p and l.locktype = 'advisory' and l.objsubid = 1 and not l.granted) s), ''),
  (select count(*) from pg_locks l
    where l.pid = $p and not l.granted and l.locktype in ('tuple', 'transactionid')),
  (select count(*) from pg_locks l join pg_class c on c.oid = l.relation
     join pg_namespace n on n.oid = c.relnamespace
    where l.pid = $p and l.granted and l.mode = 'RowExclusiveLock' and n.nspname = 'public'
      and c.relname in ('operaciones', 'jornadas', 'movimientos_stock',
                        'reasignaciones_vendedor', 'correcciones_jornada')),
  $ops)
from pg_stat_activity a where a.pid = $p"
}

campo() { cut -d'|' -f"$2" <<<"$1"; }

# Predicados sobre una foto.
pred_espera_adv() {   # (a) y (b) de 18.4.11
  [[ $(campo "$1" 1) == active && $(campo "$1" 2) == Lock && -n $(campo "$1" 7) ]]
}
pred_abcd() {         # (a), (b), (c) y (d) de 18.4.11
  pred_espera_adv "$1" && [[ $(campo "$1" 9) == 0 ]] && [[ $(campo "$1" 10) == 0 || $(campo "$1" 10) == - ]]
}
pred_espera_lock() { [[ $(campo "$1" 1) == active && $(campo "$1" 2) == Lock ]]; }
pred_espera_fila() {  # espera por una fila o un índice único (transactionid)
  [[ $(campo "$1" 1) == active && $(campo "$1" 2) == Lock && $(campo "$1" 3) == transactionid ]]
}
pred_tx_abierta() { [[ $(campo "$1" 1) == "idle in transaction" ]]; }

# Foto estable estricta: el predicado vale y dos lecturas consecutivas son
# idénticas; si cambian, se reintenta. Deja la foto en FOTO.
FOTO=""
foto_estable() {   # predicado pid [clave]
  local pred=$1 p=$2 k=${3:-} a b i
  for (( i = 0; i < PLAZO * 100; i++ )); do
    a=$(foto "$p" "$k")
    if [[ -n $a ]] && $pred "$a"; then
      b=$(foto "$p" "$k")
      if [[ $a == "$b" ]]; then FOTO=$a; return 0; fi
    fi
    sleep 0.01
  done
  FOTO=${a:-}
  return 1
}

# Foto estable de dos sesiones a la vez (cuatro lecturas: a1 a2 b1 b2).
FOTO1="" FOTO2=""
foto_par_estable() {  # predicado pid1 clave1 pid2 clave2
  local pred=$1 p1=$2 k1=$3 p2=$4 k2=$5 a1 a2 b1 b2 i
  for (( i = 0; i < PLAZO * 100; i++ )); do
    a1=$(foto "$p1" "$k1"); a2=$(foto "$p2" "$k2")
    if [[ -n $a1 && -n $a2 ]] && $pred "$a1" && $pred "$a2"; then
      b1=$(foto "$p1" "$k1"); b2=$(foto "$p2" "$k2")
      if [[ $a1 == "$b1" && $a2 == "$b2" ]]; then FOTO1=$a1; FOTO2=$a2; return 0; fi
    fi
    sleep 0.01
  done
  FOTO1=${a1:-}; FOTO2=${a2:-}
  return 1
}

# ¿Todos los bloqueantes de la foto pertenecen al conjunto permitido?
bloqueantes_permitidos() {  # foto pid_permitido...
  local f=$1 b x ok
  shift
  IFS=, read -ra b <<<"$(campo "$f" 5)"
  for x in "${b[@]}"; do
    ok=0
    for p in "$@"; do [[ $x == "$p" ]] && ok=1; done
    (( ok )) || return 1
  done
  return 0
}
contiene_pid() { [[ ",$(campo "$1" 5)," == *",$2,"* ]]; }

# -----------------------------------------------------------------------------
# Registro de resultados
# -----------------------------------------------------------------------------
TOTAL=0
FALLAS=0
RESIDUOS=0
declare -A RESUMEN_OK=() RESUMEN_FALLA=()
declare -a ORDEN_RESUMEN=()
SALIDA="$TMP/resultados.txt"

registrar() {  # caso orden rep veredicto esperado obtenido [detalle]
  local c=$1 o=$2 r=$3 v=$4
  TOTAL=$(( TOTAL + 1 ))
  [[ -n ${RESUMEN_OK[$c]+x} ]] || { RESUMEN_OK[$c]=0; RESUMEN_FALLA[$c]=0; ORDEN_RESUMEN+=("$c"); }
  if [[ $v == PASS ]]; then
    RESUMEN_OK[$c]=$(( RESUMEN_OK[$c] + 1 ))
  else
    RESUMEN_FALLA[$c]=$(( RESUMEN_FALLA[$c] + 1 ))
    FALLAS=$(( FALLAS + 1 ))
  fi
  printf '%-12s orden=%s rep=%-2s %-4s esperado=[%s] obtenido=[%s]%s\n' \
    "$c" "$o" "$r" "$v" "$5" "$6" "${7:+ detalle=[$7]}" | tee -a "$SALIDA"
}

# Abreviatura de un resultado para el registro: SQLSTATE:código o SQLSTATE:uuid(8).
res_corto() {
  [[ -n $1 ]] || { printf -- '-'; return; }
  local s=${1%%|*} v=${1#*|}
  [[ $s == 00000 && ${#v} -ge 8 ]] && v=${v:0:8}
  printf '%s:%s' "$s" "${v:-void}"
}
es_ok()  { [[ ${1%%|*} == 00000 ]]; }
es_err() { [[ ${1%%|*} == "$2" && ${1#*|} == "$3" ]]; }   # resultado sqlstate código
uuid_de() { printf '%s' "${1#*|}"; }

# -----------------------------------------------------------------------------
# Ejecutores (usados por casos.sh)
# -----------------------------------------------------------------------------
ACTOR=""          # claim: dueño activo (lo fija casos.sh)
CTRL_CLAVES=()    # claves que retiene el control, en el orden global
EXPR_T1="" EXPR_T2="" IDEM_T1="" IDEM_T2=""
DELANTE="" OTRO="" RES_T1="" RES_T2="" FOTO_T1="" FOTO_T2="" FOTO_RET="" MOTIVO=""

control_tomar() {
  local k sql=""
  for k in "${CTRL_CLAVES[@]}"; do sql+="select pg_catalog.pg_advisory_lock($k);"$'\n'; done
  ses_comando C "$sql" || { MOTIVO="el control no tomó sus claves"; return 1; }
  local f
  f=$(foto "${S_PID[C]}")
  [[ $(campo "$f" 6) == "$(lista "${CTRL_CLAVES[@]}")" && -z $(campo "$f" 7) && $(campo "$f" 1) == idle ]] \
    || { MOTIVO="el control no retiene exactamente su conjunto ($f)"; return 1; }
}
control_liberar() { ses_comando C "select pg_catalog.pg_advisory_unlock_all();"; }

idem_de() { [[ $1 == T1 ]] && printf '%s' "$IDEM_T1" || printf '%s' "$IDEM_T2"; }
expr_de() { [[ $1 == T1 ]] && printf '%s' "$EXPR_T1" || printf '%s' "$EXPR_T2"; }

# Dos participantes en la misma cola (I10, I11, K1–K4, K9, K10).
# Orden 1: se lanza T1 y luego T2; orden 2: al revés. El orden de la cola se
# observa; DELANTE es la sesión que pg_blocking_pids muestra delante.
correr_par() {   # orden
  local primero segundo pP pS
  MOTIVO=""; DELANTE=""; OTRO=""; RES_T1=""; RES_T2=""; FOTO_RET=""
  if [[ $1 == 1 ]]; then primero=T1; segundo=T2; else primero=T2; segundo=T1; fi
  ses_abrir C "$BASE" && ses_abrir T1 "$BASE" && ses_abrir T2 "$BASE" \
    || { MOTIVO="no se abrieron las sesiones"; return 1; }
  control_tomar || return 1
  ses_lanzar "$primero" "$ACTOR" "$(expr_de "$primero")"
  foto_estable pred_abcd "${S_PID[$primero]}" "$(idem_de "$primero")" \
    || { MOTIVO="$primero no llegó a la espera con (a)-(d): $FOTO"; return 1; }
  ses_lanzar "$segundo" "$ACTOR" "$(expr_de "$segundo")"
  foto_estable pred_abcd "${S_PID[$segundo]}" "$(idem_de "$segundo")" \
    || { MOTIVO="$segundo no llegó a la espera con (a)-(d): $FOTO"; return 1; }
  foto_par_estable pred_abcd "${S_PID[T1]}" "$IDEM_T1" "${S_PID[T2]}" "$IDEM_T2" \
    || { MOTIVO="sin foto conjunta estable de (a)-(d)"; return 1; }
  FOTO_T1=$FOTO1; FOTO_T2=$FOTO2
  local c=${S_PID[C]} p1=${S_PID[T1]} p2=${S_PID[T2]}
  bloqueantes_permitidos "$FOTO_T1" "$c" "$p2" && bloqueantes_permitidos "$FOTO_T2" "$c" "$p1" \
    || { MOTIVO="bloqueante ajeno al caso: T1[$FOTO_T1] T2[$FOTO_T2]"; return 1; }
  contiene_pid "$FOTO_T1" "$c" && contiene_pid "$FOTO_T2" "$c" \
    || { MOTIVO="alguna sesión no espera al control"; return 1; }
  if contiene_pid "$FOTO_T2" "$p1" && ! contiene_pid "$FOTO_T1" "$p2"; then
    DELANTE=T1; OTRO=T2
  elif contiene_pid "$FOTO_T1" "$p2" && ! contiene_pid "$FOTO_T2" "$p1"; then
    DELANTE=T2; OTRO=T1
  else
    MOTIVO="cola ambigua: T1[$FOTO_T1] T2[$FOTO_T2]"; return 1
  fi
  control_liberar || { MOTIVO="el control no liberó"; return 1; }
  local rd
  rd=$(ses_resultado "$DELANTE") || { MOTIVO="$DELANTE no respondió dentro del plazo"; return 1; }
  if [[ ${rd%%|*} == 00000 ]]; then
    # 5c: DELANTE volvió con su transacción abierta y sus bloqueos; OTRO debe
    # esperar sólo a DELANTE. (Si DELANTE terminó con error, PostgreSQL ya abortó
    # su transacción y liberó los bloqueos, así que OTRO puede avanzar.)
    foto_estable pred_espera_lock "${S_PID[$OTRO]}" \
      || { MOTIVO="$OTRO no quedó esperando a $DELANTE: $FOTO"; return 1; }
    bloqueantes_permitidos "$FOTO" "${S_PID[$DELANTE]}" && contiene_pid "$FOTO" "${S_PID[$DELANTE]}" \
      || { MOTIVO="$OTRO espera a otro proceso: $FOTO"; return 1; }
  fi
  FOTO_RET=$(foto "${S_PID[$DELANTE]}")
  ses_fin "$DELANTE" || { MOTIVO="no se cerró la transacción de $DELANTE"; return 1; }
  local ro
  ro=$(ses_resultado "$OTRO") || { MOTIVO="$OTRO no respondió dentro del plazo"; return 1; }
  ses_fin "$OTRO" || { MOTIVO="no se cerró la transacción de $OTRO"; return 1; }
  if [[ $DELANTE == T1 ]]; then RES_T1=$rd; RES_T2=$ro; else RES_T2=$rd; RES_T1=$ro; fi
  return 0
}

res_de() { [[ $1 == T1 ]] && printf '%s' "$RES_T1" || printf '%s' "$RES_T2"; }

# Dos participantes con claves de cola disjuntas (K8: misma clave en dos
# jornadas). El control retiene una clave de cada uno; ninguno espera al otro.
# Tras liberar, el primero que vuelve (PRIMERO) conserva su transacción (5c) y
# el otro debe quedar esperando por fila/índice único sólo a PRIMERO.
correr_independientes() {   # orden
  local primero segundo i
  MOTIVO=""; DELANTE=""; OTRO=""; RES_T1=""; RES_T2=""; FOTO_RET=""
  if [[ $1 == 1 ]]; then primero=T1; segundo=T2; else primero=T2; segundo=T1; fi
  ses_abrir C "$BASE" && ses_abrir T1 "$BASE" && ses_abrir T2 "$BASE" \
    || { MOTIVO="no se abrieron las sesiones"; return 1; }
  control_tomar || return 1
  ses_lanzar "$primero" "$ACTOR" "$(expr_de "$primero")"
  foto_estable pred_abcd "${S_PID[$primero]}" "$(idem_de "$primero")" \
    || { MOTIVO="$primero no llegó a la espera: $FOTO"; return 1; }
  ses_lanzar "$segundo" "$ACTOR" "$(expr_de "$segundo")"
  foto_estable pred_abcd "${S_PID[$segundo]}" "$(idem_de "$segundo")" \
    || { MOTIVO="$segundo no llegó a la espera: $FOTO"; return 1; }
  foto_par_estable pred_abcd "${S_PID[T1]}" "$IDEM_T1" "${S_PID[T2]}" "$IDEM_T2" \
    || { MOTIVO="sin foto conjunta estable"; return 1; }
  FOTO_T1=$FOTO1; FOTO_T2=$FOTO2
  local c=${S_PID[C]}
  [[ $(campo "$FOTO_T1" 5) == "$c" && $(campo "$FOTO_T2" 5) == "$c" ]] \
    || { MOTIVO="las sesiones no son independientes: T1[$FOTO_T1] T2[$FOTO_T2]"; return 1; }
  control_liberar || { MOTIVO="el control no liberó"; return 1; }
  for (( i = 0; i < PLAZO * 200; i++ )); do
    if ses_listo T1 "${S_TOK[T1]}"; then DELANTE=T1; OTRO=T2; break; fi
    if ses_listo T2 "${S_TOK[T2]}"; then DELANTE=T2; OTRO=T1; break; fi
    sleep 0.005
  done
  [[ -n $DELANTE ]] || { MOTIVO="ninguna sesión respondió dentro del plazo"; return 1; }
  local rd ro
  rd=$(ses_resultado "$DELANTE")
  for (( i = 0; i < PLAZO * 100; i++ )); do
    ses_listo "$OTRO" "${S_TOK[$OTRO]}" && { MOTIVO="$OTRO terminó sin esperar a $DELANTE"; return 1; }
    FOTO=$(foto "${S_PID[$OTRO]}")
    if pred_espera_fila "$FOTO"; then
      local f2
      f2=$(foto "${S_PID[$OTRO]}")
      [[ $f2 == "$FOTO" ]] && break
    fi
    sleep 0.01
  done
  pred_espera_fila "$FOTO" && [[ $(campo "$FOTO" 5) == "${S_PID[$DELANTE]}" && $(campo "$FOTO" 9) -ge 1 ]] \
    || { MOTIVO="$OTRO no espera la reserva de $DELANTE en el índice único: $FOTO"; return 1; }
  FOTO_RET=$FOTO
  ses_fin "$DELANTE" || { MOTIVO="no se cerró $DELANTE"; return 1; }
  ro=$(ses_resultado "$OTRO") || { MOTIVO="$OTRO no respondió dentro del plazo"; return 1; }
  ses_fin "$OTRO" || { MOTIVO="no se cerró $OTRO"; return 1; }
  if [[ $DELANTE == T1 ]]; then RES_T1=$rd; RES_T2=$ro; else RES_T2=$rd; RES_T1=$ro; fi
}

# Secuencial con transacción abierta (S-ESP y K8 baja posterior): el primero
# vuelve y retiene sus bloqueos (5c); el segundo, con recursos disjuntos o
# compatibles, debe terminar sin esperarlo.
correr_secuencial() {   # orden
  local primero segundo f0 f1
  MOTIVO=""; DELANTE=""; OTRO=""; RES_T1=""; RES_T2=""
  if [[ $1 == 1 ]]; then primero=T1; segundo=T2; else primero=T2; segundo=T1; fi
  DELANTE=$primero; OTRO=$segundo
  ses_abrir T1 "$BASE" && ses_abrir T2 "$BASE" || { MOTIVO="no se abrieron las sesiones"; return 1; }
  ses_lanzar "$primero" "$ACTOR" "$(expr_de "$primero")"
  local rp rs
  rp=$(ses_resultado "$primero") || { MOTIVO="$primero no respondió"; return 1; }
  foto_estable pred_tx_abierta "${S_PID[$primero]}" || { MOTIVO="$primero sin transacción abierta"; return 1; }
  f0=$FOTO
  ses_lanzar "$segundo" "$ACTOR" "$(expr_de "$segundo")"
  rs=$(ses_resultado "$segundo") || { MOTIVO="$segundo no terminó: espera espuria ($(foto "${S_PID[$segundo]}"))"; return 1; }
  f1=$(foto "${S_PID[$primero]}")
  [[ $f1 == "$f0" ]] || { MOTIVO="$primero cambió mientras $segundo corría: [$f0] -> [$f1]"; return 1; }
  FOTO_RET=$f0
  ses_fin "$segundo" && ses_fin "$primero" || { MOTIVO="no se cerraron las transacciones"; return 1; }
  if [[ $primero == T1 ]]; then RES_T1=$rp; RES_T2=$rs; else RES_T2=$rp; RES_T1=$rs; fi
}

# Una sesión observada (O2′, O3, O4, O5): el control retiene una clave; se
# verifica qué advisory tiene concedidos y cuál espera, y que backend_xid sea
# NULL mientras espera (O2′); al volver, lo que retiene con la transacción
# abierta (O5). Se revierte: no deja efectos.
OBS_G="" OBS_W="" OBS_RET=""
correr_observado() {
  MOTIVO=""; RES_T1=""
  ses_abrir C "$BASE" && ses_abrir T1 "$BASE" || { MOTIVO="no se abrieron las sesiones"; return 1; }
  control_tomar || return 1
  ses_lanzar T1 "$ACTOR" "$EXPR_T1"
  foto_estable pred_abcd "${S_PID[T1]}" "$IDEM_T1" || { MOTIVO="T1 no llegó a la espera: $FOTO"; return 1; }
  FOTO_T1=$FOTO
  local m=""
  [[ $(campo "$FOTO" 6) == "$OBS_G" ]] || m+="concedidos [$(campo "$FOTO" 6)] != [$OBS_G]; "
  [[ $(campo "$FOTO" 7) == "$OBS_W" ]] || m+="esperado [$(campo "$FOTO" 7)] != [$OBS_W]; "
  [[ $(campo "$FOTO" 3) == advisory ]] || m+="wait_event $(campo "$FOTO" 3); "
  [[ $(campo "$FOTO" 4) == N ]] || m+="backend_xid asignado mientras espera (O2′); "
  [[ $(campo "$FOTO" 5) == "${S_PID[C]}" ]] || m+="bloqueantes [$(campo "$FOTO" 5)]; "
  control_liberar || { MOTIVO="el control no liberó"; return 1; }
  RES_T1=$(ses_resultado T1) || { MOTIVO="T1 no respondió"; return 1; }
  foto_estable pred_tx_abierta "${S_PID[T1]}" || { MOTIVO="T1 sin transacción abierta"; return 1; }
  FOTO_RET=$FOTO
  [[ $(campo "$FOTO" 6) == "$OBS_RET" ]] || m+="retenidos [$(campo "$FOTO" 6)] != [$OBS_RET] (O5); "
  [[ $(campo "$FOTO" 4) == S ]] || m+="sin xid al volver; "
  ses_revertir T1
  MOTIVO=$m
  [[ -z $m ]]
}

# -----------------------------------------------------------------------------
# Programa principal
# -----------------------------------------------------------------------------
bash -n "$ARNES_DIR/casos.sh" || error_entorno "casos.sh tiene errores de sintaxis"
# shellcheck source=casos.sh
source "$ARNES_DIR/casos.sh" || error_entorno "no se pudo cargar casos.sh"
[[ ${#CASOS[@]} -gt 0 ]] || error_entorno "casos.sh no define CASOS"

SELECCION=("$@")
(( ${#SELECCION[@]} )) || SELECCION=("${CASOS[@]}")
es_caso() {
  local x
  for x in "${CASOS[@]}"; do [[ $x == "$1" ]] && return 0; done
  return 1
}
for _c in "${SELECCION[@]}"; do
  es_caso "$_c" || error_entorno "caso desconocido: '$_c' (casos: ${CASOS[*]})"
done
# Un caso sin función definida nunca puede pasar en silencio.
for _c in "${CASOS[@]}"; do
  declare -F "caso_${_c//-/_}" >/dev/null || error_entorno "casos.sh no define caso_${_c//-/_}"
done
# AUTO precede siempre a los demás casos (§18.4.11): si no detecta, no se mide nada.

T_INICIO=$(date +%s)
echo "arnés: PostgreSQL $("$PGBIN/postgres" --version | awk '{print $3}') en $PGBIN; R=$R; plazo=${PLAZO}s; directorio $TMP" | tee "$SALIDA"
iniciar_cluster || error_entorno "no arrancó el clúster efímero"
preparar_plantilla || error_entorno "no se preparó la plantilla"
echo "arnés: bootstrap + $MIGRACIONES_APLICADAS migraciones + datos iniciales aplicados; servidor $(sql_admin postgres 'show server_version')" | tee -a "$SALIDA"
EMPRESA=$EMPRESA_A
LOG_DEADLOCKS_0=$(grep -c 'deadlock detected' "$LOG_SERVIDOR")

DEADLOCKS_AUTO=0
caso_AUTO
if (( ${RESUMEN_FALLA[AUTO]:-1} > 0 || ${RESUMEN_FALLA[AUTO-CONT]:-1} > 0 )); then
  echo "arnés: la autoverificación AUTO no detectó el deadlock esperado; el arnés no mide nada" | tee -a "$SALIDA"
  exit 1
fi
for _c in "${SELECCION[@]}"; do
  [[ $_c == AUTO ]] && continue
  _antes=$TOTAL
  "caso_${_c//-/_}" || true
  # Un caso que no registró ninguna verificación nunca cuenta como aprobado.
  (( TOTAL > _antes )) || registrar "$_c" - - FAIL "verificaciones registradas" "ninguna"
done

# Deadlocks: sólo los de AUTO, por contador y por log.
LOG_DEADLOCKS=$(( $(grep -c 'deadlock detected' "$LOG_SERVIDOR") - LOG_DEADLOCKS_0 ))
echo "arnés: deadlocks AUTO=$DEADLOCKS_AUTO, fuera de AUTO=$DEADLOCKS_CASOS, líneas «deadlock detected» en el log=$LOG_DEADLOCKS" | tee -a "$SALIDA"
if (( DEADLOCKS_CASOS != 0 || LOG_DEADLOCKS != DEADLOCKS_AUTO )); then
  registrar DEADLOCKS - - FAIL "AUTO=$DEADLOCKS_AUTO casos=0 log=$DEADLOCKS_AUTO" "AUTO=$DEADLOCKS_AUTO casos=$DEADLOCKS_CASOS log=$LOG_DEADLOCKS"
fi
if grep -q 'could not serialize access' "$LOG_SERVIDOR"; then
  registrar SERIALIZACION - - FAIL "sin 40001" "40001 en el log"
fi

# Residuos antes de detener el clúster.
cerrar_todas
_res=$(mon postgres "select (select count(*) from pg_stat_activity where backend_type = 'client backend' and pid <> pg_backend_pid())
  || '|' || (select count(*) from pg_locks where pid <> pg_backend_pid())
  || '|' || (select count(*) from pg_prepared_xacts)
  || '|' || (select count(*) from pg_database where datname like 'rep%' or datname = 'auto')")
echo "arnés: residuos (sesiones|locks|transacciones preparadas|bases de repetición) = $_res" | tee -a "$SALIDA"
[[ $_res == "0|0|0|0" ]] || RESIDUOS=$(( RESIDUOS + 1 ))
(( RESIDUOS == 0 )) || registrar RESIDUOS - - FAIL "0|0|0|0" "$_res"

echo "arnés: resumen por caso" | tee -a "$SALIDA"
for _c in "${ORDEN_RESUMEN[@]}"; do
  printf '  %-12s PASS=%-3s FAIL=%s\n' "$_c" "${RESUMEN_OK[$_c]}" "${RESUMEN_FALLA[$_c]}" | tee -a "$SALIDA"
done
echo "arnés: $TOTAL verificaciones, $FALLAS fallas, $(( $(date +%s) - T_INICIO )) s" | tee -a "$SALIDA"
(( FALLAS == 0 )) && exit 0
exit 1
