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
#   - 5c: la sesión que vuelve conserva su transacción abierta y se confirma
#     ANTES de esperar a la otra sesión; en la cola compartida se verifica que
#     la otra espere sólo a ella. Lo que retiene al volver (O5) se verifica en
#     los casos O (sesión observada);
#   - los resultados se clasifican sólo por SQLSTATE (y, en los errores de
#     negocio, por el código que la RPC pone en message), nunca por el texto
#     traducido de un mensaje de PostgreSQL.
#
# Fallos instrumentales (fail-closed; intervención humana extraordinaria T3):
#   - toda llamada a una función instrumental (SQL, monitor, sesiones, control,
#     bases, claves, datos e invariantes) pasa por `ins`, que anota cualquier
#     retorno ≠ 0 en un registro de sólo-agregar ($TMP/fallos) aunque el sitio
#     de llamada pierda el código (por ejemplo, dentro de $(…));
#   - cada repetición, AUTO y ORACULO revisan el registro y un fallo nuevo es
#     FAIL atribuido a su caso, orden, repetición y base; antes del exit, el
#     cierre global convierte cualquier fallo no atribuido en FAIL INSTRUMENTAL;
#   - los únicos fallos esperados son los tres errores SQL de ORACULO, anotados
#     con `ins_esperado`;
#   - LINT rechaza llamadas instrumentales sin `ins` y funciones en segundo
#     plano; INSTR prueba en cada corrida el registro, su validación y el aviso
#     por SIGUSR1. Ninguna de las dos toca el clúster ni registra veredictos.
#
# Criterio de aprobación (exit 0): todos los casos PASS; la autoverificación
# AUTO produce un 40P01 por repetición; la diferencia de deadlocks del clúster
# y las líneas «deadlock detected» del log son exactamente las de AUTO; cero
# 40P01 y 40001 fuera de AUTO; ninguna espera supera el plazo; sin residuos;
# sin fallos instrumentales.
# Exit 1: algún caso o verificación falló, incluido un fallo instrumental.
# Exit 2: entorno inválido o error de preparación; mecanismo de fallos
# inutilizable (registro corrupto, truncado, borrado o no escribible; LINT o
# INSTR fallidos); limpieza fallida después de una corrida que terminaba con 0.
# =============================================================================
set -uo pipefail
# PID del shell principal: los subshells de $(…) lo heredan en $$ y lo usan
# para avisar por SIGUSR1 que no pudieron anotar un fallo.
readonly ARNES_PID=$$
if [[ $BASHPID != "$ARNES_PID" ]]; then echo "arnés: no se ejecuta en el shell principal" >&2; exit 2; fi
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

# Aviso de un subshell que no pudo anotar un fallo: el mecanismo es inutilizable
# (exit 2). Se instala antes de mktemp y de toda llamada instrumental. Sólo la
# autoprueba INSTR (INSTR_SENAL=1) lo intercepta, para comprobar que llega.
REGISTRO_ROTO=0 INSTR_SENAL=0 SENAL_INSTR=0
senal_registro() {
  if (( INSTR_SENAL )); then SENAL_INSTR=1; return; fi
  REGISTRO_ROTO=1
  error_entorno "registro de fallos inutilizable: un subshell no pudo anotar un fallo (SIGUSR1)"
}
trap senal_registro USR1

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
# Registro de fallos instrumentales (sólo-agregar, en $TMP)
#   Encabezado: ARNES_FALLOS v1 <pid> <tmp>
#   Línea:      v1 <TAB> REP_ID <TAB> ESPERADO(0|1) <TAB> origen <TAB> rc <TAB> detalle <TAB> FIN
# Escriben sólo el shell principal y sus subshells sincrónicos ($(…), tuberías),
# nunca en paralelo (LINT prohíbe funciones en segundo plano); cada línea es un
# único printf >> de menos de 512 bytes. Lo lee sólo el shell principal, que
# valida encabezado, formato, línea final completa, monotonía y que las líneas
# ya leídas no cambien. Cualquier anomalía es exit 2.
# -----------------------------------------------------------------------------
REGISTRO="$TMP/fallos"
REGISTRO_CABECERA="ARNES_FALLOS v1 $ARNES_PID $TMP"
REGISTRO_LISTO=0 REGISTRO_LINEAS=0 EN_LIMPIEZA=0 REG_ERROR=""
REP_ID=GLOBAL
declare -a REG=() REG_PREV=()
REG_LINEA_RE=$'^v1\t[^\t]+\t[01]\t[^\t]+\t[1-9][0-9]*\t[^\t]+\tFIN$'

fallo_instr() {  # esperado origen rc detalle
  local rid=${REP_ID:-GLOBAL} det=${4:--} linea
  rid=${rid//[$'\t\n\r']/ }; det=${det//[$'\t\n\r']/ }; det=${det:0:200}
  printf -v linea 'v1\t%s\t%s\t%s\t%s\t%s\tFIN\n' "$rid" "$1" "${2//[$'\t\n\r']/ }" "$3" "${det:--}"
  if (( REGISTRO_LISTO )) && printf '%s' "$linea" >>"$REGISTRO" 2>/dev/null; then return 0; fi
  echo "arnés: no se pudo anotar un fallo instrumental: ${linea//$'\t'/ }" >&2
  (( EN_LIMPIEZA )) && return 1   # la limpieza decide su propio exit
  if [[ $BASHPID == "$ARNES_PID" ]]; then
    REGISTRO_ROTO=1
    error_entorno "registro de fallos inutilizable"
  fi
  kill -USR1 "$ARNES_PID" 2>/dev/null
  exit 2
}

# Despachador de toda llamada instrumental: ejecuta la función sin alterar su
# salida y, si devuelve ≠ 0, lo anota y devuelve el mismo código.
ins() {
  "$@"
  local rc=$?
  (( rc == 0 )) || fallo_instr 0 "$1" "$rc" "llamador=${FUNCNAME[1]:-main} ${*:2}"
  return "$rc"
}

# Fallo esperado (sólo los errores SQL de ORACULO): anota ESPERADO=1 y devuelve 0
# únicamente si la función devolvió exactamente el código esperado, dentro de
# caso_ORACULO; cualquier otro resultado devuelve 1 y, si fue un fallo, se anota
# como inesperado.
ins_esperado() {  # rc_esperado funcion args…
  local esp=$1
  shift
  "$@"
  local rc=$?
  if (( rc == esp && rc != 0 )) && [[ $REP_ID == ORACULO && ${FUNCNAME[1]:-} == caso_ORACULO ]]; then
    fallo_instr 1 "$1" "$rc" "esperado por ORACULO"
    return 0
  fi
  (( rc == 0 )) || fallo_instr 0 "$1" "$rc" "ins_esperado: se esperaba rc=$esp en ORACULO; llamador=${FUNCNAME[1]:-main}"
  return 1
}

registro_iniciar() {
  ( set -C; printf '%s\n' "$REGISTRO_CABECERA" >"$REGISTRO" ) 2>/dev/null || return 1
  local l
  IFS= read -r l <"$REGISTRO" && [[ $l == "$REGISTRO_CABECERA" ]] || return 1
  REGISTRO_LINEAS=0; REG=(); REG_PREV=()
  REGISTRO_LISTO=1
}

# Valida el registro y carga sus líneas en REG; devuelve 1 con REG_ERROR si no es válido.
registro_validar() {
  local l="" primera=1 i rid esp
  REG=(); REG_ERROR=""
  [[ -f $REGISTRO && -r $REGISTRO ]] || { REG_ERROR="no existe o no se puede leer"; return 1; }
  while IFS= read -r l; do
    if (( primera )); then
      [[ $l == "$REGISTRO_CABECERA" ]] || { REG_ERROR="encabezado alterado"; return 1; }
      primera=0
      continue
    fi
    [[ $l =~ $REG_LINEA_RE ]] || { REG_ERROR="línea mal formada: ${l:0:80}"; return 1; }
    IFS=$'\t' read -r _ rid esp _ <<<"$l"
    [[ $esp == 0 || $rid == ORACULO ]] || { REG_ERROR="fallo esperado fuera de ORACULO: ${l:0:80}"; return 1; }
    REG+=("$l")
  done <"$REGISTRO"
  [[ -z $l ]] || { REG_ERROR="última línea incompleta: ${l:0:80}"; return 1; }
  (( primera == 0 )) || { REG_ERROR="vacío (sin encabezado)"; return 1; }
  (( ${#REG[@]} >= REGISTRO_LINEAS )) || { REG_ERROR="truncado (${#REG[@]} < $REGISTRO_LINEAS líneas)"; return 1; }
  for (( i = 0; i < REGISTRO_LINEAS; i++ )); do
    [[ ${REG[i]} == "${REG_PREV[i]}" ]] || { REG_ERROR="línea $(( i + 1 )) modificada"; return 1; }
  done
  return 0
}
registro_leer() {
  registro_validar || error_entorno "registro de fallos inválido: $REG_ERROR"
  REGISTRO_LINEAS=${#REG[@]}
  REG_PREV=("${REG[@]}")
}

# Fallos inesperados posteriores a la línea N: deja la cantidad en REG_N, el
# detalle en REG_DET y en REG_AJENA las líneas cuyo REP_ID no es el vigente.
registro_nuevos() {  # N
  local i rid esp orig rc det
  REG_N=0 REG_DET="" REG_AJENA=0
  for (( i = $1; i < ${#REG[@]}; i++ )); do
    IFS=$'\t' read -r _ rid esp orig rc det _ <<<"${REG[i]}"
    [[ $esp == 0 ]] || continue
    REG_N=$(( REG_N + 1 ))
    REG_DET+="$orig(rc=$rc; ${det:0:60}) "
    [[ $rid == "$REP_ID" ]] || REG_AJENA=$(( REG_AJENA + 1 ))
  done
}

# Punto de control de una repetición: un fallo instrumental nuevo es FAIL de
# esa repetición, aunque ningún sitio de llamada lo haya comprobado.
control_registro() {  # caso orden rep N
  registro_leer
  registro_nuevos "$4"
  (( REG_N == 0 )) && return 0
  ins registrar "$1" "$2" "$3" FAIL "sin fallos instrumentales [$REP_ID]" "$REG_N fallo(s)" \
    "${REG_DET:0:300}$( (( REG_AJENA )) && printf '; %s con atribución distinta' "$REG_AJENA")"
  return 1
}

# -----------------------------------------------------------------------------
# Limpieza
# -----------------------------------------------------------------------------
declare -A S_FD=() S_PROC=() S_PID=() S_OUT=() S_N=() S_TOK=()
CLUSTER_ARRIBA=0

# Cierra una sesión. Devuelve 1 si hizo falta SIGKILL (fallo instrumental),
# pero siempre libera el proceso y su estado.
ses_cerrar() {
  local n=$1 fd=${S_FD[$1]:-} proc=${S_PROC[$1]:-} i rc=0
  [[ -n $fd ]] || return 0
  printf '\\q\n' >&"$fd" 2>/dev/null
  exec {fd}>&-
  for (( i = 0; i < 500; i++ )); do
    kill -0 "$proc" 2>/dev/null || break
    sleep 0.01
  done
  if kill -0 "$proc" 2>/dev/null; then
    kill -9 "$proc" 2>/dev/null
    rc=1
  fi
  wait "$proc" 2>/dev/null
  unset "S_FD[$n]" "S_PROC[$n]" "S_PID[$n]" "S_OUT[$n]" "S_N[$n]" "S_TOK[$n]"
  return "$rc"
}

# Cierra todas las sesiones aunque alguna falle; devuelve 1 si alguna falló.
cerrar_todas() {
  local n rc=0
  for n in "${!S_FD[@]}"; do ins ses_cerrar "$n" || rc=1; done
  return "$rc"
}

# trap EXIT: completa toda la limpieza posible. Si la corrida terminaba con 0 y
# algo de la limpieza falló, el exit pasa a 2; si ya había fallado, se conserva
# su código y se avisa.
limpieza() {
  local rc_orig=$? fallo=""
  EN_LIMPIEZA=1
  cerrar_todas || fallo+="alguna sesión necesitó SIGKILL; "
  if (( CLUSTER_ARRIBA )); then
    "$PGBIN/pg_ctl" -D "$DATA" -m immediate -w stop >/dev/null 2>&1 || fallo+="pg_ctl stop falló; "
    "$PGBIN/pg_ctl" -D "$DATA" status >/dev/null 2>&1 && fallo+="el postmaster sigue activo; "
  fi
  # Red detrás del cierre global: una corrida aprobada no puede dejar fallos anotados.
  if (( rc_orig == 0 && REGISTRO_LISTO )); then
    if registro_validar; then
      registro_nuevos 0
      (( REG_N == 0 )) || fallo+="$REG_N fallo(s) instrumental(es) anotado(s) tras el cierre: ${REG_DET:0:200}; "
    else
      fallo+="registro de fallos inválido: $REG_ERROR; "
    fi
  fi
  if [[ $CONSERVAR == 1 ]]; then
    echo "arnés: directorio conservado en $TMP" >&2
  else
    rm -rf "$TMP" 2>/dev/null || fallo+="rm -rf falló; "
    [[ ! -e $TMP ]] || fallo+="quedó $TMP; "
  fi
  if [[ -n $fallo ]]; then
    echo "arnés: falló la limpieza (exit original $rc_orig): $fallo" >&2
    (( rc_orig == 0 )) && exit 2
  fi
}
trap limpieza EXIT
trap 'exit 130' INT TERM
registro_iniciar || error_entorno "no se pudo crear el registro de fallos en $REGISTRO"

# -----------------------------------------------------------------------------
# Clúster efímero
# -----------------------------------------------------------------------------
_psql() { "$PGBIN/psql" -X -A -t -q -h "$SOCK" -p "$PUERTO" "$@"; }
sql_admin() { ins _psql -v ON_ERROR_STOP=1 -U supabase_admin -d "$1" -c "$2"; }
sql_pg()    { ins _psql -v ON_ERROR_STOP=1 -U postgres -d "$1" -c "$2"; }
# Monitor: conexión aparte, de sólo lectura, sin bloqueos que choquen con las RPC.
mon()       { PGOPTIONS='-c default_transaction_read_only=on' ins _psql -U supabase_admin -d "$1" -c "$2"; }

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
  ins sql_admin postgres "create database arnes" >/dev/null || return 1
  ins _psql -v ON_ERROR_STOP=1 -v arnes_descartable=1 -U supabase_admin -d arnes -f "$BOOTSTRAP" \
    || { echo "arnés: falló el bootstrap" >&2; return 1; }
  for m in "$MIGRACIONES_DIR"/*.sql; do
    ins _psql -v ON_ERROR_STOP=1 -U postgres -d arnes -f "$m" >"$TMP/migracion.log" 2>&1 \
      || { echo "arnés: falló la migración $(basename "$m")" >&2; cat "$TMP/migracion.log" >&2; return 1; }
    MIGRACIONES_APLICADAS=$(( ${MIGRACIONES_APLICADAS:-0} + 1 ))
  done
  fixtures_sql | ins _psql -v ON_ERROR_STOP=1 -U postgres -d arnes -f - >/dev/null \
    || { echo "arnés: fallaron los datos iniciales" >&2; return 1; }
}

# Cada repetición usa una base nueva, copia de la plantilla `arnes`.
NBASE=0
BASE=""
DEADLOCKS_CASOS=0
nueva_base() {
  NBASE=$(( NBASE + 1 ))
  BASE="rep$NBASE"
  ins sql_admin postgres "create database $BASE template arnes owner postgres" >/dev/null
}

# Espera a que no quede ningún backend en la base, suma sus deadlocks y la borra.
# Completa todos los pasos aunque uno falle; devuelve 1 si alguno falló.
DEADLOCKS_ULTIMA_BASE=0
borrar_base() {
  local b=$1 i n="" d rc=0
  DEADLOCKS_ULTIMA_BASE=0
  ins cerrar_todas || rc=1
  for (( i = 0; i < PLAZO * 100; i++ )); do
    n=$(ins mon postgres "select count(*) from pg_stat_activity where datname = '$b'") || { rc=1; n=""; break; }
    [[ $n == 0 ]] && break
    sleep 0.01
  done
  if [[ $n =~ ^[0-9]+$ ]]; then
    [[ $n == 0 ]] || { echo "arnés: quedaron $n backends en $b" >&2; RESIDUOS=$(( RESIDUOS + n )); }
  else
    rc=1
  fi
  d=$(ins mon postgres "select coalesce((select deadlocks from pg_stat_database where datname = '$b'), 0)") || rc=1
  if [[ $d =~ ^[0-9]+$ ]]; then DEADLOCKS_ULTIMA_BASE=$d; else rc=1; fi
  ins sql_admin postgres "drop database $b" >/dev/null || rc=1
  return "$rc"
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
  mkfifo "$fifo" && : >"$out" || return 1
  "$PGBIN/psql" -X -A -t -q -h "$SOCK" -p "$PUERTO" -U "$u" -d "$b" \
    -v ON_ERROR_STOP=0 -v VERBOSITY=verbose <"$fifo" >"$out" 2>&1 &
  S_PROC[$n]=$!
  exec {fd}>"$fifo" || return 1
  S_FD[$n]=$fd
  S_OUT[$n]=$out
  S_N[$n]=0
  ins ses_enviar "$n" "select 'PID|' || pg_backend_pid();" || return 1
  ins ses_esperar "$n" "${S_TOK[$n]}" || return 1
  S_PID[$n]=$(ins ses_tramo "$n" "${S_TOK[$n]}" | sed -n 's/^PID|//p' | tail -1) || return 1
  [[ ${S_PID[$n]} =~ ^[0-9]+$ ]]
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
  ins ses_enviar "$1" "$(bloque_llamada "$2" "$3")"
}

# Resultado de la última llamada: "SQLSTATE|valor" (valor = uuid, vacío o código).
# Un SQLSTATE de la RPC es un resultado, no un fallo: devuelve 1 sólo si no hubo
# respuesta o no se encontró la línea RES|.
ses_resultado() {
  local n=$1
  ins ses_esperar "$n" "${S_TOK[$n]}" || { echo "SIN_RESPUESTA|"; return 1; }
  ins ses_tramo "$n" "${S_TOK[$n]}" | grep '^RES|' | tail -1 | cut -d'|' -f2-
}

ses_comando() { # nombre sql: envía y espera
  ins ses_enviar "$1" "$2" || return 1
  ins ses_esperar "$1" "${S_TOK[$1]}"
}

ses_fin() { ins ses_comando "$1" "commit;"; }     # en transacción abortada equivale a ROLLBACK
ses_revertir() { ins ses_comando "$1" "rollback;"; }

# -----------------------------------------------------------------------------
# Claves advisory (las mismas cadenas que las RPC; ADR-001 §18.4.5)
# -----------------------------------------------------------------------------
declare -A CLAVE_CACHE=()
clave_txt() {
  local t=$1 k
  if [[ -z ${CLAVE_CACHE[$t]:-} ]]; then
    k=$(ins sql_admin postgres "select pg_catalog.hashtextextended('$t', 0)") && [[ $k =~ ^-?[0-9]+$ ]] || return 1
    CLAVE_CACHE[$t]=$k
  fi
  printf '%s' "${CLAVE_CACHE[$t]}"
}
kv() { ins clave_txt "jornadas:vendedor:$EMPRESA:$1"; }   # nivel 2
kc() { ins clave_txt "jornadas:camion:$EMPRESA:$1"; }     # nivel 1
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
  ins mon "$BASE" "
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
# idénticas; si cambian, se reintenta. Deja la foto en FOTO. Devuelve 1 si no se
# alcanzó en el plazo (resultado) o si el monitor falló (anotado por ins).
FOTO=""
foto_estable() {   # predicado pid [clave]
  local pred=$1 p=$2 k=${3:-} a="" b i
  for (( i = 0; i < PLAZO * 100; i++ )); do
    a=$(ins foto "$p" "$k") || { FOTO="(falló el monitor)"; return 1; }
    if [[ -n $a ]] && $pred "$a"; then
      b=$(ins foto "$p" "$k") || { FOTO="(falló el monitor)"; return 1; }
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
  local pred=$1 p1=$2 k1=$3 p2=$4 k2=$5 a1="" a2="" b1 b2 i
  for (( i = 0; i < PLAZO * 100; i++ )); do
    a1=$(ins foto "$p1" "$k1") && a2=$(ins foto "$p2" "$k2") \
      || { FOTO1="(falló el monitor)"; FOTO2=""; return 1; }
    if [[ -n $a1 && -n $a2 ]] && $pred "$a1" && $pred "$a2"; then
      b1=$(ins foto "$p1" "$k1") && b2=$(ins foto "$p2" "$k2") \
        || { FOTO1="(falló el monitor)"; FOTO2=""; return 1; }
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
DELANTE="" OTRO="" RES_T1="" RES_T2="" FOTO_T1="" FOTO_T2="" MOTIVO=""

control_tomar() {
  local k sql=""
  for k in "${CTRL_CLAVES[@]}"; do sql+="select pg_catalog.pg_advisory_lock($k);"$'\n'; done
  ins ses_comando C "$sql" || { MOTIVO="el control no tomó sus claves"; return 1; }
  local f
  f=$(ins foto "${S_PID[C]}") || { MOTIVO="falló la foto del control"; return 1; }
  [[ $(campo "$f" 6) == "$(lista "${CTRL_CLAVES[@]}")" && -z $(campo "$f" 7) && $(campo "$f" 1) == idle ]] \
    || { MOTIVO="el control no retiene exactamente su conjunto ($f)"; return 1; }
}
control_liberar() { ins ses_comando C "select pg_catalog.pg_advisory_unlock_all();"; }

idem_de() { [[ $1 == T1 ]] && printf '%s' "$IDEM_T1" || printf '%s' "$IDEM_T2"; }
expr_de() { [[ $1 == T1 ]] && printf '%s' "$EXPR_T1" || printf '%s' "$EXPR_T2"; }

# Dos participantes en la misma cola (I10, I11, K1–K4, K9, K10).
# Orden 1: se lanza T1 y luego T2; orden 2: al revés. El orden de la cola se
# observa; DELANTE es la sesión que pg_blocking_pids muestra delante.
correr_par() {   # orden
  local primero segundo
  MOTIVO=""; DELANTE=""; OTRO=""; RES_T1=""; RES_T2=""
  if [[ $1 == 1 ]]; then primero=T1; segundo=T2; else primero=T2; segundo=T1; fi
  ins ses_abrir C "$BASE" && ins ses_abrir T1 "$BASE" && ins ses_abrir T2 "$BASE" \
    || { MOTIVO="no se abrieron las sesiones"; return 1; }
  ins control_tomar || return 1
  ins ses_lanzar "$primero" "$ACTOR" "$(expr_de "$primero")" || { MOTIVO="no se lanzó $primero"; return 1; }
  foto_estable pred_abcd "${S_PID[$primero]}" "$(idem_de "$primero")" \
    || { MOTIVO="$primero no llegó a la espera con (a)-(d): $FOTO"; return 1; }
  ins ses_lanzar "$segundo" "$ACTOR" "$(expr_de "$segundo")" || { MOTIVO="no se lanzó $segundo"; return 1; }
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
  ins control_liberar || { MOTIVO="el control no liberó"; return 1; }
  local rd
  rd=$(ins ses_resultado "$DELANTE") || { MOTIVO="$DELANTE no respondió dentro del plazo"; return 1; }
  if [[ ${rd%%|*} == 00000 ]]; then
    # 5c: DELANTE volvió con su transacción abierta y sus bloqueos; OTRO debe
    # esperar sólo a DELANTE. (Si DELANTE terminó con error, PostgreSQL ya abortó
    # su transacción y liberó los bloqueos, así que OTRO puede avanzar.)
    foto_estable pred_espera_lock "${S_PID[$OTRO]}" \
      || { MOTIVO="$OTRO no quedó esperando a $DELANTE: $FOTO"; return 1; }
    bloqueantes_permitidos "$FOTO" "${S_PID[$DELANTE]}" && contiene_pid "$FOTO" "${S_PID[$DELANTE]}" \
      || { MOTIVO="$OTRO espera a otro proceso: $FOTO"; return 1; }
  fi
  ins ses_fin "$DELANTE" || { MOTIVO="no se cerró la transacción de $DELANTE"; return 1; }
  local ro
  ro=$(ins ses_resultado "$OTRO") || { MOTIVO="$OTRO no respondió dentro del plazo"; return 1; }
  ins ses_fin "$OTRO" || { MOTIVO="no se cerró la transacción de $OTRO"; return 1; }
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
  MOTIVO=""; DELANTE=""; OTRO=""; RES_T1=""; RES_T2=""
  if [[ $1 == 1 ]]; then primero=T1; segundo=T2; else primero=T2; segundo=T1; fi
  ins ses_abrir C "$BASE" && ins ses_abrir T1 "$BASE" && ins ses_abrir T2 "$BASE" \
    || { MOTIVO="no se abrieron las sesiones"; return 1; }
  ins control_tomar || return 1
  ins ses_lanzar "$primero" "$ACTOR" "$(expr_de "$primero")" || { MOTIVO="no se lanzó $primero"; return 1; }
  foto_estable pred_abcd "${S_PID[$primero]}" "$(idem_de "$primero")" \
    || { MOTIVO="$primero no llegó a la espera: $FOTO"; return 1; }
  ins ses_lanzar "$segundo" "$ACTOR" "$(expr_de "$segundo")" || { MOTIVO="no se lanzó $segundo"; return 1; }
  foto_estable pred_abcd "${S_PID[$segundo]}" "$(idem_de "$segundo")" \
    || { MOTIVO="$segundo no llegó a la espera: $FOTO"; return 1; }
  foto_par_estable pred_abcd "${S_PID[T1]}" "$IDEM_T1" "${S_PID[T2]}" "$IDEM_T2" \
    || { MOTIVO="sin foto conjunta estable"; return 1; }
  FOTO_T1=$FOTO1; FOTO_T2=$FOTO2
  local c=${S_PID[C]}
  [[ $(campo "$FOTO_T1" 5) == "$c" && $(campo "$FOTO_T2" 5) == "$c" ]] \
    || { MOTIVO="las sesiones no son independientes: T1[$FOTO_T1] T2[$FOTO_T2]"; return 1; }
  ins control_liberar || { MOTIVO="el control no liberó"; return 1; }
  for (( i = 0; i < PLAZO * 200; i++ )); do
    if ses_listo T1 "${S_TOK[T1]}"; then DELANTE=T1; OTRO=T2; break; fi
    if ses_listo T2 "${S_TOK[T2]}"; then DELANTE=T2; OTRO=T1; break; fi
    sleep 0.005
  done
  [[ -n $DELANTE ]] || { MOTIVO="ninguna sesión respondió dentro del plazo"; return 1; }
  local rd ro
  rd=$(ins ses_resultado "$DELANTE") || { MOTIVO="sin resultado de $DELANTE"; return 1; }
  for (( i = 0; i < PLAZO * 100; i++ )); do
    ses_listo "$OTRO" "${S_TOK[$OTRO]}" && { MOTIVO="$OTRO terminó sin esperar a $DELANTE"; return 1; }
    FOTO=$(ins foto "${S_PID[$OTRO]}") || { MOTIVO="falló el monitor"; return 1; }
    if pred_espera_fila "$FOTO"; then
      local f2
      f2=$(ins foto "${S_PID[$OTRO]}") || { MOTIVO="falló el monitor"; return 1; }
      [[ $f2 == "$FOTO" ]] && break
    fi
    sleep 0.01
  done
  pred_espera_fila "$FOTO" && [[ $(campo "$FOTO" 5) == "${S_PID[$DELANTE]}" && $(campo "$FOTO" 9) -ge 1 ]] \
    || { MOTIVO="$OTRO no espera la reserva de $DELANTE en el índice único: $FOTO"; return 1; }
  ins ses_fin "$DELANTE" || { MOTIVO="no se cerró $DELANTE"; return 1; }
  ro=$(ins ses_resultado "$OTRO") || { MOTIVO="$OTRO no respondió dentro del plazo"; return 1; }
  ins ses_fin "$OTRO" || { MOTIVO="no se cerró $OTRO"; return 1; }
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
  ins ses_abrir T1 "$BASE" && ins ses_abrir T2 "$BASE" || { MOTIVO="no se abrieron las sesiones"; return 1; }
  ins ses_lanzar "$primero" "$ACTOR" "$(expr_de "$primero")" || { MOTIVO="no se lanzó $primero"; return 1; }
  local rp rs
  rp=$(ins ses_resultado "$primero") || { MOTIVO="$primero no respondió"; return 1; }
  foto_estable pred_tx_abierta "${S_PID[$primero]}" || { MOTIVO="$primero sin transacción abierta"; return 1; }
  f0=$FOTO
  ins ses_lanzar "$segundo" "$ACTOR" "$(expr_de "$segundo")" || { MOTIVO="no se lanzó $segundo"; return 1; }
  rs=$(ins ses_resultado "$segundo") || { MOTIVO="$segundo no terminó: espera espuria ($(ins foto "${S_PID[$segundo]}"))"; return 1; }
  f1=$(ins foto "${S_PID[$primero]}") || { MOTIVO="falló el monitor"; return 1; }
  [[ $f1 == "$f0" ]] || { MOTIVO="$primero cambió mientras $segundo corría: [$f0] -> [$f1]"; return 1; }
  ins ses_fin "$segundo" && ins ses_fin "$primero" || { MOTIVO="no se cerraron las transacciones"; return 1; }
  if [[ $primero == T1 ]]; then RES_T1=$rp; RES_T2=$rs; else RES_T2=$rp; RES_T1=$rs; fi
}

# Una sesión observada (O2′, O3, O4, O5): el control retiene una clave; se
# verifica qué advisory tiene concedidos y cuál espera, y que backend_xid sea
# NULL mientras espera (O2′); al volver, lo que retiene con la transacción
# abierta (O5). Se revierte: no deja efectos.
OBS_G="" OBS_W="" OBS_RET=""
correr_observado() {
  MOTIVO=""; RES_T1=""
  ins ses_abrir C "$BASE" && ins ses_abrir T1 "$BASE" || { MOTIVO="no se abrieron las sesiones"; return 1; }
  ins control_tomar || return 1
  ins ses_lanzar T1 "$ACTOR" "$EXPR_T1" || { MOTIVO="no se lanzó T1"; return 1; }
  foto_estable pred_abcd "${S_PID[T1]}" "$IDEM_T1" || { MOTIVO="T1 no llegó a la espera: $FOTO"; return 1; }
  FOTO_T1=$FOTO
  local m=""
  [[ $(campo "$FOTO" 6) == "$OBS_G" ]] || m+="concedidos [$(campo "$FOTO" 6)] != [$OBS_G]; "
  [[ $(campo "$FOTO" 7) == "$OBS_W" ]] || m+="esperado [$(campo "$FOTO" 7)] != [$OBS_W]; "
  [[ $(campo "$FOTO" 3) == advisory ]] || m+="wait_event $(campo "$FOTO" 3); "
  [[ $(campo "$FOTO" 4) == N ]] || m+="backend_xid asignado mientras espera (O2′); "
  [[ $(campo "$FOTO" 5) == "${S_PID[C]}" ]] || m+="bloqueantes [$(campo "$FOTO" 5)]; "
  ins control_liberar || { MOTIVO="el control no liberó"; return 1; }
  RES_T1=$(ins ses_resultado T1) || { MOTIVO="T1 no respondió"; return 1; }
  foto_estable pred_tx_abierta "${S_PID[T1]}" || { MOTIVO="T1 sin transacción abierta"; return 1; }
  [[ $(campo "$FOTO" 6) == "$OBS_RET" ]] || m+="retenidos [$(campo "$FOTO" 6)] != [$OBS_RET] (O5); "
  [[ $(campo "$FOTO" 4) == S ]] || m+="sin xid al volver; "
  # T3-C3 (D5): un rollback fallido es un fallo del mecanismo, nunca PASS.
  ins ses_revertir T1 || { MOTIVO="no se revirtió T1${m:+; $m}"; return 1; }
  MOTIVO=$m
  [[ -z $m ]]
}

# -----------------------------------------------------------------------------
# LINT — ninguna llamada instrumental sin `ins` (análisis léxico del código
# normalizado por `declare -f` y del programa principal). Marca:
#   - un nombre de INSTRUMENTALES en posición de orden (inicio de línea, tras
#     ; & | ! ( { $( then else do if elif while until o tras una asignación de
#     entorno) que no esté precedido por `ins ` o `ins_esperado N `;
#   - una función instrumental pasada como argumento a repetir/foto_estable/
#     foto_par_estable (llamada indirecta);
#   - una orden en segundo plano (`&`) fuera del psql de ses_abrir;
#   - una asignación de arreglo con dos o más $(…): si una de ellas envía
#     SIGUSR1 mientras queda otra por expandir, bash 5.2 no ejecuta el trap
#     (error de sintaxis), aborta la orden de nivel superior y sigue; se escribe
#     un elemento por orden (A=(); A+=("$(…)")).
# Excepciones nominales con cantidad exacta (función:llamada:cantidad): en esa
# función debe haber exactamente esa cantidad de llamadas directas (sin ins) a
# esa instrumental; una más o una menos es un hallazgo. Las protegidas por ins
# no se cuentan.
#   limpieza:cerrar_todas:1 — la limpieza no usa el registro y decide su exit;
#   invariantes:_psql:1     — invariantes clasifica el rc de su consulta (2 =
#                             error) y sus llamadores usan ins / ins_esperado.
# La configuración real no admite excepciones para funciones zz_* ni __lab_*.
# -----------------------------------------------------------------------------
# registrar se incluye: un veredicto no contado o no impreso (rc ≠ 0) es un
# fallo instrumental aunque el camino que lo llama no cuente sus veredictos.
INSTRUMENTALES="_psql sql_admin sql_pg mon foto ses_abrir ses_enviar ses_esperar ses_tramo ses_lanzar ses_resultado ses_comando ses_fin ses_revertir ses_cerrar cerrar_todas control_tomar control_liberar nueva_base borrar_base clave_txt kv kc preparar_jornada jornada invariantes registrar"
LINT_EXCEPCIONES="limpieza:cerrar_todas:1 invariantes:_psql:1"
# Muestra de la autoprueba: dos llamadas sin proteger, una asignación de entorno,
# una llamada indirecta, una orden en segundo plano, una llamada directa de más
# en una función exceptuada y un arreglo con dos $(…) (6 hallazgos), y una
# función correcta (ninguno). La excepción de zz_exc vale sólo para la muestra.
LINT_MUESTRA=$'zz_mal () \n{ \n    x=$(mon postgres "select 1")\n}\nzz_asig () \n{ \n    PGOPTIONS=\'-c x=1\' _psql -c "select 1"\n}\nzz_indirecto () \n{ \n    repetir X "1" prep_X correr_par kv\n}\nzz_fondo () \n{ \n    ins foto 1 &\n}\nzz_exc () \n{ \n    x=$(_psql -c "select 1");\n    _psql -c "select 2";\n    y=$(ins _psql -c "select 3")\n}\nzz_arreglo () \n{ \n    A=("$(ins kv 1)" "$(ins kv 2)")\n}\nzz_bien () \n{ \n    x=$(ins mon postgres "select 1") || return 1;\n    PGOPTIONS=\'-c x=1\' ins _psql -c "select 1";\n    ins_esperado 2 invariantes "a" "true";\n    A=();\n    A+=("$(ins kv 1)");\n    A+=("$(ins kv 2)");\n    B=("$(ins kv 3)") && x=$(ins kv 4) && y=$(ins kc 5)\n}\n'
LINT_MUESTRA_EXCEPCIONES="zz_exc:_psql:1"

lint_texto() {  # excepciones; código normalizado por stdin → hallazgos "función: …"
  awk -v nombres="$INSTRUMENTALES" -v exc="$1" -v q="'" '
    # Reemplaza cada llamada protegida por @P@ sin consumir el delimitador siguiente.
    function proteger(l, pat,    m, s, c) {
      while (match(l, "(^|[^A-Za-z0-9_])" pat)) {
        m = substr(l, RSTART, RLENGTH); s = RSTART; c = RLENGTH
        if (substr(m, 1, 1) != "i") { s++; c-- }
        if (substr(m, RLENGTH, 1) ~ /[[:space:];)|&]/) c--
        l = substr(l, 1, s - 1) "@P@" substr(l, s + c)
      }
      return l
    }
    # Cantidad de llamadas directas a nom en l (cada una se reemplaza por @X@).
    function contar(l, nom,    k, e) {
      k = 0
      while (match(l, pre nom fin)) {
        e = RSTART + RLENGTH - 1
        if (substr(l, e, 1) ~ /[[:space:];)|&]/) e--
        l = substr(l, 1, e - length(nom)) "@X@" substr(l, e + 1)
        k++
      }
      return k
    }
    # Cantidad de $(…) dentro de los paréntesis de la asignación de arreglo que
    # empieza en la posición p (justo después de «=(»); no cuenta $((…)).
    function sust_en_arreglo(s, p,    d, k, c) {
      d = 1; k = 0
      while (p <= length(s) && d > 0) {
        c = substr(s, p, 1)
        if (c == "$" && substr(s, p + 1, 1) == "(" && substr(s, p + 2, 1) != "(") { k++; d++; p += 2; continue }
        if (c == "(") d++
        else if (c == ")") d--
        p++
      }
      return k
    }
    BEGIN {
      n = split(nombres, N, " ")
      for (i = 1; i <= n; i++) ES[N[i]] = 1
      ne = split(exc, EX, " ")
      for (i = 1; i <= ne; i++) {
        split(EX[i], P, ":"); AUT[P[1] ":" P[2]] = P[3] + 0; CNT[P[1] ":" P[2]] = 0
      }
      pre = "(^|[;&|!({]|\\$\\(|[[:space:]](then|else|do|if|elif|while|until)[[:space:]]|=(" q "[^" q "]*" q "|\"[^\"]*\"|[^[:space:]\"" q "]*)[[:space:]])[[:space:]]*"
      fin = "([[:space:];)|&]|$)"
    }
    /^[A-Za-z_][A-Za-z0-9_]* \(\) *$/ { fn = $1; next }
    {
      l = $0
      for (i = 1; i <= n; i++) {
        l = proteger(l, "ins_esperado [0-9]+ " N[i] fin)
        l = proteger(l, "ins " N[i] fin)
      }
      for (i = 1; i <= n; i++) {
        if (!(l ~ (pre N[i] fin))) continue
        if ((fn ":" N[i]) in AUT) CNT[fn ":" N[i]] += contar(l, N[i])
        else print fn ": sin ins: " N[i] ": " $0
      }
      if (match(l, /(^|[^A-Za-z0-9_])(repetir|foto_estable|foto_par_estable)[[:space:]]/)) {
        m = split(substr(l, RSTART), T, /[[:space:]"]+/)
        for (j = 2; j <= m; j++) if (T[j] in ES) print fn ": llamada indirecta: " T[j] ": " $0
      }
      if (l ~ /(^|[^&>|])&[[:space:]]*$/ && !(fn == "ses_abrir" && l ~ /PGBIN\/psql/))
        print fn ": orden en segundo plano: " $0
      r = $0
      while (match(r, /(^|[^A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=\(/)) {
        r = substr(r, RSTART + RLENGTH)
        if (sust_en_arreglo(r, 1) >= 2) { print fn ": arreglo con varias sustituciones $(…): " $0; break }
      }
    }
    END {
      for (k in AUT)
        if (CNT[k] != AUT[k]) {
          split(k, P, ":")
          print P[1] ": excepción " P[2] ": " CNT[k] " llamada(s) directa(s), autorizadas " AUT[k]
        }
    }'
}

verificar_protecciones() {
  local h n f e
  # Configuración real: cada excepción es función:instrumental:cantidad, sin
  # repetir, y nunca para funciones de muestra (zz_*) ni de laboratorio (__lab_*).
  for e in $LINT_EXCEPCIONES; do
    [[ $e =~ ^([A-Za-z_][A-Za-z0-9_]*):([A-Za-z_][A-Za-z0-9_]*):([1-9][0-9]*)$ ]] \
      && [[ " $INSTRUMENTALES " == *" ${BASH_REMATCH[2]} "* ]] \
      && [[ ${BASH_REMATCH[1]} != zz_* && ${BASH_REMATCH[1]} != __lab_* ]] \
      && [[ " $LINT_EXCEPCIONES " != *" ${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:"*" ${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:"* ]] \
      || error_entorno "LINT: excepción inválida: $e"
  done
  # Autoprueba: el LINT debe marcar exactamente los seis defectos de la muestra.
  h=$(printf '%s' "$LINT_MUESTRA" | lint_texto "$LINT_MUESTRA_EXCEPCIONES") || error_entorno "LINT: falló el análisis de la autoprueba"
  n=$(grep -c . <<<"$h")
  [[ $n == 6 ]] && grep -q '^zz_mal: sin ins: mon' <<<"$h" && grep -q '^zz_asig: sin ins: _psql' <<<"$h" \
    && grep -q '^zz_indirecto: llamada indirecta: kv' <<<"$h" && grep -q '^zz_fondo: orden en segundo plano' <<<"$h" \
    && grep -q '^zz_exc: excepción _psql: 2 llamada(s) directa(s), autorizadas 1$' <<<"$h" \
    && grep -q '^zz_arreglo: arreglo con varias sustituciones' <<<"$h" \
    && ! grep -q '^zz_bien' <<<"$h" \
    || error_entorno "LINT: la autoprueba no detectó lo esperado ($n hallazgos): ${h//$'\n'/ | }"
  h=$( { for f in $(declare -F | awk '{print $3}'); do declare -f "$f"; done
         echo 'main () '
         sed -n '/^# Programa principal/,$p' "$ARNES_DIR/arnes.sh" | grep -v '^[[:space:]]*#'
       } | lint_texto "$LINT_EXCEPCIONES" ) || error_entorno "LINT: falló el análisis"
  [[ -z $h ]] || error_entorno "LINT: llamadas instrumentales sin protección, en segundo plano, fuera de la cantidad exceptuada o en arreglos con varias \$(…): ${h//$'\n'/ | }"
  echo "arnés: LINT ok ($(declare -F | wc -l) funciones y el programa principal; autoprueba 6/6)" | tee -a "$SALIDA"
}

# -----------------------------------------------------------------------------
# INSTR — autoverificación del registro de fallos, en un registro aparte
# ($TMP/fallos.instr). No toca el clúster, no registra veredictos y exige que el
# registro principal y los contadores queden intactos. Cualquier falla: exit 2.
# -----------------------------------------------------------------------------
zz_instr_ok() { printf 'salida'; }
zz_instr_falla() { printf 'efecto'; return 3; }

autoverificar_registro() {
  local principal=$REGISTRO cab_principal=$REGISTRO_CABECERA antes total0=$TOTAL fallas0=$FALLAS
  antes=$(<"$principal") || error_entorno "INSTR: no se pudo leer el registro principal"
  local REGISTRO="$TMP/fallos.instr" REGISTRO_CABECERA="ARNES_FALLOS v1 $ARNES_PID $TMP INSTR"
  local REGISTRO_LINEAS=0 REP_ID=INSTR REG_ERROR="" REG_N=0 REG_DET="" REG_AJENA=0 x rc copia m
  local t3=$'\t3\t' t4=$'\t4\t' linea1=$'v1\tINSTR\t0\tzz_instr_falla\t3\t'
  local -a REG=() REG_PREV=() buenas=()
  ( set -C; printf '%s\n' "$REGISTRO_CABECERA" >"$REGISTRO" ) 2>/dev/null || error_entorno "INSTR: no se creó su registro"
  registro_leer
  # 1. ins con rc 0 no anota y no altera la salida.
  x=$(ins zz_instr_ok); rc=$?; registro_leer
  (( rc == 0 && ${#REG[@]} == 0 )) && [[ $x == salida ]] || error_entorno "INSTR: ins con rc 0 anotó o alteró la salida"
  # 2. Dentro de una sustitución: anota y conserva salida y rc.
  x=$(ins zz_instr_falla); rc=$?; registro_leer
  (( rc == 3 && ${#REG[@]} == 1 )) && [[ $x == efecto && ${REG[0]} == "$linea1"* ]] \
    || error_entorno "INSTR: fallo dentro de \$(…) no anotado (rc=$rc líneas=${#REG[@]})"
  # 3. Sentencia suelta, fuera de una sustitución.
  ins zz_instr_falla >/dev/null; rc=$?; registro_leer
  (( rc == 3 && ${#REG[@]} == 2 )) || error_entorno "INSTR: fallo en una sentencia suelta no anotado"
  # 4. Dentro de un argumento, con el rc perdido.
  echo "$(ins zz_instr_falla)" >/dev/null; registro_leer
  (( ${#REG[@]} == 3 )) || error_entorno "INSTR: fallo dentro de un argumento no anotado"
  # 5. Atribución por contenido.
  registro_nuevos 0
  (( REG_N == 3 && REG_AJENA == 0 )) || error_entorno "INSTR: conteo o atribución de fallos nuevos"
  REP_ID=OTRA; registro_nuevos 0; REP_ID=INSTR
  (( REG_AJENA == 3 )) || error_entorno "INSTR: no se detectó una atribución distinta"
  # 6. Corrupción: cada alteración de una copia debe invalidarla.
  buenas=("${REG[@]}")
  for m in parcial truncado borrado encabezado modificada malformada esperado_ajeno; do
    copia="$TMP/fallos.instr.$m"
    printf '%s\n' "$REGISTRO_CABECERA" "${buenas[@]}" >"$copia" || error_entorno "INSTR: no se copió el registro"
    case $m in
      parcial) printf 'v1\tINSTR\t0' >>"$copia" ;;
      truncado) { printf '%s\n' "$REGISTRO_CABECERA"; printf '%s\n' "${buenas[@]:0:2}"; } >"$copia" ;;
      borrado) rm -f "$copia" ;;
      encabezado) { printf 'ARNES_FALLOS v0\n'; printf '%s\n' "${buenas[@]}"; } >"$copia" ;;
      modificada) { printf '%s\n' "$REGISTRO_CABECERA" "${buenas[0]/"$t3"/"$t4"}"; printf '%s\n' "${buenas[@]:1}"; } >"$copia" ;;
      malformada) printf 'basura\n' >>"$copia" ;;
      esperado_ajeno) printf 'v1\tINSTR\t1\tzz\t2\tx\tFIN\n' >>"$copia" ;;
    esac
    REGISTRO=$copia
    if registro_validar; then error_entorno "INSTR: no se detectó el registro $m"; fi
    REGISTRO="$TMP/fallos.instr"
    rm -f "$copia"
  done
  registro_validar || error_entorno "INSTR: el registro sano no validó: $REG_ERROR"
  # 7. Escritura fallida o registro no inicializado en un subshell: SIGUSR1 al
  #    PID principal y exit 2 del subshell; dentro y fuera de $(…) y en una tubería.
  INSTR_SENAL=1
  for m in sustitucion subshell tuberia no_inicializado; do
    SENAL_INSTR=0
    case $m in
      sustitucion) x=$(REGISTRO="$TMP/no_existe/fallos"; ins zz_instr_falla 2>/dev/null); rc=$? ;;
      subshell) ( REGISTRO="$TMP/no_existe/fallos"; ins zz_instr_falla >/dev/null 2>&1 ); rc=$? ;;
      tuberia) { REGISTRO="$TMP/no_existe/fallos"; ins zz_instr_falla 2>/dev/null; } | cat >/dev/null; rc=$? ;;
      no_inicializado) x=$(REGISTRO_LISTO=0; ins zz_instr_falla 2>/dev/null); rc=$? ;;
    esac
    (( rc == 2 && SENAL_INSTR == 1 )) || { INSTR_SENAL=0; error_entorno "INSTR: aviso SIGUSR1 ($m): rc=$rc señal=$SENAL_INSTR"; }
  done
  INSTR_SENAL=0 SENAL_INSTR=0
  # 8. Sin contaminación: registro principal intacto, sin veredictos.
  [[ $(<"$principal") == "$antes" && $antes == "$cab_principal" ]] || error_entorno "INSTR: alteró el registro principal"
  (( TOTAL == total0 && FALLAS == fallas0 )) || error_entorno "INSTR: registró veredictos"
  echo "arnés: INSTR ok (anotación en \$(…), sentencia y argumento; atribución; 7 corrupciones; SIGUSR1 en 4 contextos; registro principal intacto)" | tee -a "$SALIDA"
}

# Cierre global, inmediatamente antes del exit: todo fallo inesperado anotado en
# cualquier momento es FAIL INSTRUMENTAL; los esperados deben ser exactamente 3.
cierre_registro() {
  local l rid esp e=0
  registro_leer
  for l in "${REG[@]}"; do
    IFS=$'\t' read -r _ rid esp _ <<<"$l"
    [[ $esp == 1 ]] && e=$(( e + 1 ))
  done
  (( e == 3 )) || error_entorno "registro de fallos: $e fallos esperados (se esperan los 3 de ORACULO)"
  REP_ID=GLOBAL
  registro_nuevos 0
  echo "arnés: fallos instrumentales anotados = $REG_N (esperados de ORACULO = $e)" | tee -a "$SALIDA"
  (( REG_N == 0 )) || ins registrar INSTRUMENTAL - - FAIL "0 fallos instrumentales" "$REG_N" "${REG_DET:0:400}"
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
# Autoverificaciones del mecanismo de fallos, antes de tocar el clúster.
verificar_protecciones
autoverificar_registro
iniciar_cluster || error_entorno "no arrancó el clúster efímero"
preparar_plantilla || error_entorno "no se preparó la plantilla"
_ver=$(ins sql_admin postgres 'show server_version') || error_entorno "no se leyó la versión del servidor"
echo "arnés: bootstrap + $MIGRACIONES_APLICADAS migraciones + datos iniciales aplicados; servidor $_ver" | tee -a "$SALIDA"
EMPRESA=$EMPRESA_A
LOG_DEADLOCKS_0=$(grep -c 'deadlock detected' "$LOG_SERVIDOR")

DEADLOCKS_AUTO=0
# El oráculo de invariantes debe rechazar fallas y errores SQL (T3-C1, H-01).
caso_ORACULO
if (( ${RESUMEN_FALLA[ORACULO]:-1} > 0 )); then
  echo "arnés: la autoverificación del oráculo falló; el arnés no mide nada" | tee -a "$SALIDA"
  exit 1
fi
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
  (( TOTAL > _antes )) || ins registrar "$_c" - - FAIL "verificaciones registradas" "ninguna"
done

# Deadlocks: sólo los de AUTO, por contador y por log.
LOG_DEADLOCKS=$(( $(grep -c 'deadlock detected' "$LOG_SERVIDOR") - LOG_DEADLOCKS_0 ))
echo "arnés: deadlocks AUTO=$DEADLOCKS_AUTO, fuera de AUTO=$DEADLOCKS_CASOS, líneas «deadlock detected» en el log=$LOG_DEADLOCKS" | tee -a "$SALIDA"
if (( DEADLOCKS_CASOS != 0 || LOG_DEADLOCKS != DEADLOCKS_AUTO )); then
  ins registrar DEADLOCKS - - FAIL "AUTO=$DEADLOCKS_AUTO casos=0 log=$DEADLOCKS_AUTO" "AUTO=$DEADLOCKS_AUTO casos=$DEADLOCKS_CASOS log=$LOG_DEADLOCKS"
fi
if grep -q 'could not serialize access' "$LOG_SERVIDOR"; then
  ins registrar SERIALIZACION - - FAIL "sin 40001" "40001 en el log"
fi

# Residuos antes de detener el clúster.
ins cerrar_todas
_res=$(ins mon postgres "select (select count(*) from pg_stat_activity where backend_type = 'client backend' and pid <> pg_backend_pid())
  || '|' || (select count(*) from pg_locks where pid <> pg_backend_pid())
  || '|' || (select count(*) from pg_prepared_xacts)
  || '|' || (select count(*) from pg_database where datname like 'rep%' or datname in ('auto', 'oraculo'))")
echo "arnés: residuos (sesiones|locks|transacciones preparadas|bases de repetición) = $_res" | tee -a "$SALIDA"
[[ $_res == "0|0|0|0" ]] || RESIDUOS=$(( RESIDUOS + 1 ))
(( RESIDUOS == 0 )) || ins registrar RESIDUOS - - FAIL "0|0|0|0" "$_res"

# Cierre global del registro de fallos: nada posterior anota fallos.
cierre_registro

echo "arnés: resumen por caso" | tee -a "$SALIDA"
for _c in "${ORDEN_RESUMEN[@]}"; do
  printf '  %-12s PASS=%-3s FAIL=%s\n' "$_c" "${RESUMEN_OK[$_c]}" "${RESUMEN_FALLA[$_c]}" | tee -a "$SALIDA"
done
echo "arnés: $TOTAL verificaciones, $FALLAS fallas, $(( $(date +%s) - T_INICIO )) s" | tee -a "$SALIDA"
(( FALLAS == 0 )) && exit 0
exit 1
