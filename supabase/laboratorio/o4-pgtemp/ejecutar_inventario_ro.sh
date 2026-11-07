#!/usr/bin/env bash
# Ejecutor del inventario READ ONLY de O-4 (consultas_ro/Q00–Q6) con identidad fail-closed.
# NO se ejecuta contra staging sin una autorización humana vigente y nominada (ver
# PROCEDIMIENTO_STAGING_RO.md). Este archivo sólo prepara la ejecución segura.
#
# Garantías:
#  * FICHA DE IDENTIDAD aprobada por el humano ANTES y por un canal independiente: host, project-ref,
#    system_identifier, base, usuario, puerto y SHA-256 de la CA. Host, puerto, base, usuario, ref y sysid NO se
#    aceptan por línea de comandos: salen sólo de la ficha, cuya huella se pasa aparte (--ficha-sha256). Así los
#    parámetros de ejecución no son su propia fuente de confianza.
#  * Sin TOCTOU: ficha y CA se copian UNA vez a un directorio temporal privado 0700; el SHA-256 se verifica sobre la
#    COPIA; sólo la copia verificada se parsea, se guarda como evidencia y se entrega a libpq (sslrootcert). Las rutas
#    de origen no se vuelven a leer (las variables se eliminan: cualquier uso posterior aborta por set -u).
#  * La CA (--ca) debe tener el SHA-256 de la ficha. Remoto: host db.<ref>.supabase.co, puerto 5432,
#    sslmode=verify-full, sin hostaddr; el usuario no puede ser postgres ni supabase_admin.
#  * Entorno libpq limpio (todas las PG*, PSQL*, LIBPQ*), psql -X, -v ON_ERROR_STOP=1, una sola sesión en
#    BEGIN READ ONLY … ROLLBACK con la guardia Q00 primero (base, current_user, session_user, puerto, sysid).
#  * Directorio de evidencia NUEVO, 700, fuera del repo y sin enlaces simbólicos; commit, árbol y hashes se
#    registran ANTES de ejecutar; en remoto exige --commit-esperado y --arbol-esperado y falla ante otra identidad
#    git o código modificado.
#  * La huella LOGIN+TEMP (--revision-login-temp) es constancia de una revisión puntual, no una autorización.
#
# Uso: ejecutar_inventario_ro.sh --ficha F --ficha-sha256 H --estado original|remediado --evidencia DIR
#        [--ca FILE] [--revision-login-temp HUELLA] [--commit-esperado C --arbol-esperado T] [--sin-clave] [--dry-run]
set -uo pipefail
umask 077
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; Q="$DIR/consultas_ro"; REPO="$(cd "$DIR/../../.." && pwd)"
. "$DIR/vinculo_evidencia.sh"
fallar() { echo "abortado: $*" >&2; exit 2; }

FICHA=""; FICHA_H=""; ESTADO=""; REVTOK=""; CA=""; EV=""; SINCLAVE=0; DRY=0; GC=""; GT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ficha) FICHA="${2:-}"; shift 2 ;; --ficha-sha256) FICHA_H="${2:-}"; shift 2 ;; --estado) ESTADO="${2:-}"; shift 2 ;;
    --revision-login-temp) REVTOK="${2:-}"; shift 2 ;; --ca) CA="${2:-}"; shift 2 ;; --evidencia) EV="${2:-}"; shift 2 ;;
    --commit-esperado) GC="${2:-}"; shift 2 ;; --arbol-esperado) GT="${2:-}"; shift 2 ;;
    --sin-clave) SINCLAVE=1; shift ;; --dry-run) DRY=1; shift ;;
    *) fallar "argumento desconocido o no permitido (host, puerto, base, usuario, ref y sysid sólo salen de la ficha): $1" ;;
  esac
done
[ -n "$FICHA" ] && [ -f "$FICHA" ] && [ ! -L "$FICHA" ] || fallar "falta --ficha (archivo regular, no enlace)"
# --- Directorio temporal privado 0700 (limpieza segura al terminar; nunca contiene ni borra la evidencia) ---
PRIV="$(mktemp -d "${TMPDIR:-/tmp}/o4inv.XXXXXX")" || fallar "no se pudo crear el directorio temporal privado"
limpiar_priv() { case "$PRIV" in */o4inv.??????) [ -d "$PRIV" ] && [ -O "$PRIV" ] && [ ! -L "$PRIV" ] && rm -rf -- "$PRIV" ;; esac; }
trap limpiar_priv EXIT; trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
[[ "$PRIV" =~ ^/[A-Za-z0-9_./-]+$ ]] || fallar "ruta temporal con caracteres no admitidos"
[ -d "$PRIV" ] && [ -O "$PRIV" ] && [ ! -L "$PRIV" ] && [ "$(stat -c %a "$PRIV")" = 700 ] || fallar "el directorio temporal no es privado (0700, propio)"
# Copia única de la ficha por un solo descriptor; a partir de aquí sólo existe la copia.
PF_FICHA="$PRIV/ficha.txt"
exec 3< "$FICHA" || fallar "no se pudo abrir --ficha"
cat <&3 > "$PF_FICHA"; exec 3<&-
chmod 400 "$PF_FICHA"
[[ "$FICHA_H" =~ ^[0-9a-f]{64}$ ]] || fallar "falta --ficha-sha256 (huella de la ficha aprobada, 64 hex)"
[ "$ESTADO" = original ] || [ "$ESTADO" = remediado ] || fallar "--estado debe ser original o remediado"
if [ -n "$REVTOK" ]; then [[ "$REVTOK" =~ ^[0-9a-f]{64}$ ]] || fallar "--revision-login-temp debe ser una huella sha256 en hexadecimal"; fi
[ "$(sha256sum "$PF_FICHA" | cut -d' ' -f1)" = "$FICHA_H" ] || fallar "la ficha no coincide con la huella aprobada (--ficha-sha256)"

# --- Lectura estricta de la ficha (sin "source": sólo CLAVE=valor, claves conocidas, sin duplicados) ---
declare -A F=()
while IFS= read -r linea || [ -n "$linea" ]; do
  [ -z "$linea" ] && continue; case "$linea" in \#*) continue ;; esac
  [[ "$linea" =~ ^([A-Z0-9_]+)=([^[:space:]]*)$ ]] || fallar "línea inválida en la ficha"
  k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
  case "$k" in FICHA_VERSION|MODO|HOST|PORT|PROJECT_REF|SYSTEM_IDENTIFIER|DBNAME|DBUSER|CA_SHA256) ;; *) fallar "clave desconocida en la ficha: $k" ;; esac
  [ -z "${F[$k]+x}" ] || fallar "clave duplicada en la ficha: $k"
  F[$k]="$v"
done < "$PF_FICHA"
for k in FICHA_VERSION MODO HOST PORT PROJECT_REF SYSTEM_IDENTIFIER DBNAME DBUSER CA_SHA256; do [ -n "${F[$k]:-}" ] || fallar "falta $k en la ficha"; done
[ "${F[FICHA_VERSION]}" = 1 ] || fallar "FICHA_VERSION no soportada"
[[ "${F[PROJECT_REF]}" =~ ^[a-z0-9]{20}$ ]] || fallar "PROJECT_REF con formato inválido"
[[ "${F[SYSTEM_IDENTIFIER]}" =~ ^[0-9]{10,25}$ ]] || fallar "SYSTEM_IDENTIFIER con formato inválido"
[[ "${F[PORT]}" =~ ^[0-9]{1,5}$ ]] || fallar "PORT con formato inválido"
[[ "${F[DBNAME]}" =~ ^[A-Za-z0-9_]{1,63}$ ]] || fallar "DBNAME con formato inválido"
[[ "${F[DBUSER]}" =~ ^[A-Za-z0-9_.]{1,63}$ ]] || fallar "DBUSER con formato inválido"
case "${F[DBUSER]}" in postgres|supabase_admin) fallar "DBUSER no puede ser ${F[DBUSER]}: el inventario usa un rol de lectura propio" ;; esac
case "${F[HOST]}" in *[=,\ \'\"\;\&\?\#]*) fallar "HOST con caracteres no admitidos" ;; esac
HOST="${F[HOST]}"; PORT="${F[PORT]}"; SSLPART=""
case "${F[MODO]}" in
  laboratorio)
    [[ "$HOST" == /* ]] || fallar "modo laboratorio exige un socket Unix (HOST = directorio)"
    [ -d "$HOST" ] && [ -O "$HOST" ] && [ "$(stat -c %a "$HOST")" = "700" ] || fallar "el directorio del socket debe existir, ser propio y modo 700"
    [ "$PORT" != 5432 ] || fallar "puerto 5432 prohibido en laboratorio"
    [ "${F[CA_SHA256]}" = na ] || fallar "en laboratorio CA_SHA256 debe ser 'na'" ;;
  remoto)
    [ "$HOST" = "db.${F[PROJECT_REF]}.supabase.co" ] || fallar "HOST debe ser exactamente db.<PROJECT_REF>.supabase.co"
    [ "$PORT" = 5432 ] || fallar "remoto: PORT debe ser 5432"
    [ "$SINCLAVE" -eq 0 ] || fallar "--sin-clave sólo se admite en laboratorio"
    [[ "${F[CA_SHA256]}" =~ ^[0-9a-f]{64}$ ]] || fallar "remoto: CA_SHA256 debe ser una huella sha256"
    [ -n "$CA" ] && [ -f "$CA" ] && [ ! -L "$CA" ] || fallar "remoto: --ca (archivo regular de CA obtenido por un canal independiente) es obligatorio"
    CA_PRIV="$PRIV/ca.pem"
    exec 4< "$CA" || fallar "no se pudo abrir --ca"
    cat <&4 > "$CA_PRIV"; exec 4<&-
    chmod 400 "$CA_PRIV"
    [ "$(sha256sum "$CA_PRIV" | cut -d' ' -f1)" = "${F[CA_SHA256]}" ] || fallar "la CA no coincide con CA_SHA256 de la ficha"
    SSLPART="sslmode=verify-full sslrootcert=$CA_PRIV"
    [ -n "$GC" ] && [ -n "$GT" ] || fallar "remoto: --commit-esperado y --arbol-esperado son obligatorios" ;;
  *) fallar "MODO debe ser laboratorio o remoto" ;;
esac
# Las rutas de origen no se vuelven a consultar: cualquier referencia posterior aborta (set -u).
unset FICHA CA
if [ -n "$GC" ] || [ -n "$GT" ]; then [ -n "$GC" ] && [ -n "$GT" ] || fallar "--commit-esperado y --arbol-esperado van juntos"; fi

# --- Entorno libpq/psql limpio ---
LIMPIADAS="$(compgen -e | grep -E '^(PG|PSQL|LIBPQ)' | sort | tr '\n' ' ')"
for v in $(compgen -e | grep -E '^(PG|PSQL|LIBPQ)'); do unset "$v"; done
VACIO="$PRIV/vacio"; : > "$VACIO"; chmod 600 "$VACIO"
export PGPASSFILE="$VACIO" PGSERVICEFILE="$VACIO" PGSYSCONFDIR=/nonexistent PGCONNECT_TIMEOUT=15 PGAPPNAME=o4_inventario_ro PAGER=cat
echo "entorno: variables eliminadas: ${LIMPIADAS:-ninguna}"

CONNINFO="host=$HOST port=$PORT dbname=${F[DBNAME]} user=${F[DBUSER]} connect_timeout=15 application_name=o4_inventario_ro $SSLPART"
VARS=(-v "esperado_sysid=${F[SYSTEM_IDENTIFIER]}" -v "esperado_base=${F[DBNAME]}" -v "esperado_usuario=${F[DBUSER]}" -v "esperado_puerto=$PORT" -v "estado_esperado=$ESTADO")
[ -z "$REVTOK" ] || VARS+=(-v "revision_login_temp=$REVTOK")
PWFLAG=(-W); [ "$SINCLAVE" -eq 1 ] && PWFLAG=(-w)
CMD=(psql -X -v ON_ERROR_STOP=1 -q "${PWFLAG[@]}" "${VARS[@]}" "$CONNINFO" -f -)
if [ "$DRY" -eq 1 ]; then echo "dry-run: ${CMD[*]}"; exit 0; fi
command -v psql >/dev/null || fallar "psql no disponible"

# --- Evidencia: directorio nuevo y seguro; vínculo git y hashes ANTES de conectar ---
case "$(realpath -m -- "$EV")/" in "$PRIV"/*) fallar "la evidencia no puede quedar dentro del directorio temporal privado" ;; esac
dir_evidencia_seguro "$EV" || exit 2
GIT_COMMIT_ESPERADO="$GC" GIT_ARBOL_ESPERADO="$GT" vinculo_git "$EV" || { echo "abortado: la integridad del código no se pudo establecer; ver $EV/vinculo_git.txt" >&2; ( cd "$EV" && find . -type f ! -name MANIFIESTO.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFIESTO.sha256 ); exit 5; }
cp "$PF_FICHA" "$EV/ficha.txt"; sha256sum "$EV/ficha.txt" > "$EV/ficha.sha256"; [ -z "${CA_PRIV:-}" ] || { cp "$CA_PRIV" "$EV/ca_verificada.pem"; sha256sum "$EV/ca_verificada.pem" > "$EV/ca_verificada.sha256"; }; echo "entorno eliminado: ${LIMPIADAS:-ninguno}" > "$EV/entorno_limpiado.txt"
echo "${CMD[*]}" > "$EV/comando.txt"
SQL="$(printf 'BEGIN READ ONLY;\n'; for f in Q00_guardia Q0_sesion Q1_roles Q2_funcion Q3_event_triggers Q4_version Q5_rls Q6_veredicto; do cat "$Q/$f.sql"; printf '\n'; done; printf 'ROLLBACK;\n')"
printf '%s\n' "$SQL" | "${CMD[@]}" > "$EV/inventario.txt" 2> "$EV/inventario.err"; RC=$?
echo "$RC" > "$EV/codigo_salida.txt"
cat "$EV/inventario.txt"; cat "$EV/inventario.err" >&2
VER="$(grep -E '^[^|]*\|[0-9a-f]{64}\|[tf]$' "$EV/inventario.txt" | tail -1)"
SALIDA_FINAL=0
if [ $RC -ne 0 ]; then echo "abortado: psql terminó con rc=$RC" >&2; SALIDA_FINAL=3
elif [ -z "$VER" ]; then echo "abortado: no se encontró el veredicto de Q6" >&2; SALIDA_FINAL=2
elif [ -n "${VER%%|*}" ]; then echo "ABORTAR: ${VER%%|*}" >&2; SALIDA_FINAL=4
else echo "veredicto: sin motivos de abortar (la ejecución sigue sin autorizar cambios)"; fi
( cd "$EV" && find . -type f ! -name MANIFIESTO.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFIESTO.sha256 )
exit $SALIDA_FINAL
