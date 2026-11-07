#!/usr/bin/env bash
# Ejecutor del inventario READ ONLY de O-4 (consultas_ro/Q00–Q6) con verificación de identidad
# fail-closed. NO se ejecuta contra staging sin una autorización humana vigente y nominada
# (ver PROCEDIMIENTO_STAGING_RO.md). Este archivo sólo prepara la ejecución segura.
#
# Qué garantiza:
#  * Entorno libpq limpio: se eliminan TODAS las variables PG*, más PSQLRC y similares, y se fijan
#    valores explícitos y seguros. PGHOSTADDR, PGSERVICE, PGOPTIONS, PGSSLMODE, PGPASSFILE, etc. del
#    entorno heredado nunca llegan a psql.
#  * psql -X (sin ~/.psqlrc) y -v ON_ERROR_STOP=1: la primera falla detiene la sesión (rc ≠ 0).
#  * Una sola sesión en BEGIN READ ONLY … ROLLBACK, con la guardia Q00 PRIMERO.
#  * Identidad esperada obtenida ANTES por un canal independiente (--ref y --sysid los escribe el humano
#    a partir de su sesión del panel del proyecto); jamás se "aprenden" de esta conexión.
#  * Remoto: host exacto db.<ref>.supabase.co, sslmode=verify-full con --sslrootcert, sin hostaddr.
#  * La compuerta LOGIN+TEMP (Q6) exige --revision-login-temp con la huella de la lista revisada.
#
# Uso:
#   ejecutar_inventario_ro.sh --host H --port N --dbname B --user U --ref REF --sysid ID \
#       --estado original|remediado [--revision-login-temp HUELLA] [--sslrootcert FILE] \
#       [--evidencia DIR] [--laboratorio] [--sin-clave] [--dry-run]
#   --laboratorio: sólo socket Unix (host = directorio propio, modo 700, puerto ≠ 5432).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; Q="$DIR/consultas_ro"
fallar() { echo "abortado: $*" >&2; exit 2; }

HOST=""; PORT=""; DBNAME=""; DBUSER=""; REF=""; SYSID=""; ESTADO=""; REVTOK=""; ROOTCERT=""; EV=""
LAB=0; SINCLAVE=0; DRY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;; --port) PORT="${2:-}"; shift 2 ;; --dbname) DBNAME="${2:-}"; shift 2 ;;
    --user) DBUSER="${2:-}"; shift 2 ;; --ref) REF="${2:-}"; shift 2 ;; --sysid) SYSID="${2:-}"; shift 2 ;;
    --estado) ESTADO="${2:-}"; shift 2 ;; --revision-login-temp) REVTOK="${2:-}"; shift 2 ;;
    --sslrootcert) ROOTCERT="${2:-}"; shift 2 ;; --evidencia) EV="${2:-}"; shift 2 ;;
    --laboratorio) LAB=1; shift ;; --sin-clave) SINCLAVE=1; shift ;; --dry-run) DRY=1; shift ;;
    *) fallar "argumento desconocido: $1" ;;
  esac
done

# --- Validación estricta de argumentos (antes de tocar la red o psql) ---
[ -n "$HOST" ] && [ -n "$PORT" ] && [ -n "$DBNAME" ] && [ -n "$DBUSER" ] || fallar "faltan --host, --port, --dbname o --user"
[ -n "$REF" ] || fallar "falta --ref (project-ref obtenido por un canal independiente)"
[ -n "$SYSID" ] || fallar "falta --sysid (system_identifier obtenido por un canal independiente; no se aprende de la conexión)"
[ -n "$ESTADO" ] || fallar "falta --estado"
[[ "$REF" =~ ^[a-z0-9]{20}$ ]] || fallar "--ref con formato inválido"
[[ "$SYSID" =~ ^[0-9]{10,25}$ ]] || fallar "--sysid con formato inválido"
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] || fallar "--port con formato inválido"
[[ "$DBNAME" =~ ^[A-Za-z0-9_]{1,63}$ ]] || fallar "--dbname con formato inválido"
[[ "$DBUSER" =~ ^[A-Za-z0-9_.]{1,63}$ ]] || fallar "--user con formato inválido"
[ "$ESTADO" = original ] || [ "$ESTADO" = remediado ] || fallar "--estado debe ser original o remediado"
if [ -n "$REVTOK" ]; then [[ "$REVTOK" =~ ^[0-9a-f]{64}$ ]] || fallar "--revision-login-temp debe ser una huella sha256 en hexadecimal"; fi
case "$HOST" in *[=,\ \'\"\;\&\?\#]*) fallar "--host con caracteres no admitidos" ;; esac
if [ "$LAB" -eq 1 ]; then
  [[ "$HOST" == /* ]] || fallar "--laboratorio exige un socket Unix (--host = directorio)"
  [ -d "$HOST" ] && [ -O "$HOST" ] && [ "$(stat -c %a "$HOST")" = "700" ] || fallar "el directorio del socket debe existir, ser propio y modo 700"
  [ "$PORT" != "5432" ] || fallar "puerto 5432 prohibido en laboratorio"
  SSLPART=""
else
  [ "$HOST" = "db.${REF}.supabase.co" ] || fallar "--host debe ser exactamente db.<ref>.supabase.co del --ref indicado"
  [ "$SINCLAVE" -eq 0 ] || fallar "--sin-clave sólo se admite en laboratorio"
  [ -n "$ROOTCERT" ] && [ -f "$ROOTCERT" ] || fallar "remoto: --sslrootcert (archivo de CA obtenido por un canal independiente) es obligatorio"
  case "$ROOTCERT" in *[=,\ \'\"]*) fallar "--sslrootcert con caracteres no admitidos" ;; esac
  SSLPART="sslmode=verify-full sslrootcert=$ROOTCERT"
fi

# --- Entorno libpq/psql limpio ---
LIMPIADAS="$(compgen -e | grep -E '^(PG|PSQL|LIBPQ)' | sort | tr '\n' ' ')"
for v in $(compgen -e | grep -E '^(PG|PSQL|LIBPQ)'); do unset "$v"; done
VACIO="$(mktemp)"; chmod 600 "$VACIO"
export PGPASSFILE="$VACIO" PGSERVICEFILE="$VACIO" PGSYSCONFDIR=/nonexistent PGCONNECT_TIMEOUT=15 PGAPPNAME=o4_inventario_ro PAGER=cat
echo "entorno: variables eliminadas: ${LIMPIADAS:-ninguna}"

CONNINFO="host=$HOST port=$PORT dbname=$DBNAME user=$DBUSER connect_timeout=15 application_name=o4_inventario_ro $SSLPART"
VARS=(-v "esperado_sysid=$SYSID" -v "esperado_base=$DBNAME" -v "estado_esperado=$ESTADO")
[ -z "$REVTOK" ] || VARS+=(-v "revision_login_temp=$REVTOK")
PWFLAG=(-W); [ "$SINCLAVE" -eq 1 ] && PWFLAG=(-w)
CMD=(psql -X -v ON_ERROR_STOP=1 -q "${PWFLAG[@]}" "${VARS[@]}" "$CONNINFO" -f -)
if [ "$DRY" -eq 1 ]; then echo "dry-run: ${CMD[*]}"; rm -f "$VACIO"; exit 0; fi

command -v psql >/dev/null || fallar "psql no disponible"
SQL="$(printf 'BEGIN READ ONLY;\n'; for f in Q00_guardia Q0_sesion Q1_roles Q2_funcion Q3_event_triggers Q4_version Q5_rls Q6_veredicto; do cat "$Q/$f.sql"; printf '\n'; done; printf 'ROLLBACK;\n')"
SALIDA="$(mktemp)"; trap 'rm -f "$SALIDA" "$SALIDA.err" "$VACIO"' EXIT
printf '%s\n' "$SQL" | "${CMD[@]}" > "$SALIDA" 2> "$SALIDA.err"; RC=$?
if [ -n "$EV" ]; then mkdir -p "$EV"; cp "$SALIDA" "$EV/inventario.txt"; cp "$SALIDA.err" "$EV/inventario.err"; sha256sum "$EV/inventario.txt" > "$EV/inventario.sha256"; fi
cat "$SALIDA"; cat "$SALIDA.err" >&2; rm -f "$SALIDA.err"
[ $RC -eq 0 ] || { echo "abortado: psql terminó con rc=$RC" >&2; exit 3; }
VER="$(grep -E '^[^|]*\|[0-9a-f]{64}\|[tf]$' "$SALIDA" | tail -1)"
[ -n "$VER" ] || fallar "no se encontró el veredicto de Q6"
[ -z "${VER%%|*}" ] || { echo "ABORTAR: ${VER%%|*}" >&2; exit 4; }
echo "veredicto: sin motivos de abortar (la ejecución sigue sin autorizar cambios)"
