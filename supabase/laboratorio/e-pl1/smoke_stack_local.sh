#!/usr/bin/env bash
# E-PL1 / H-02 — stack LOCAL de Supabase (CLI vigente del proyecto, GoTrue y PostgREST
# reales) para (a) correr la suite pgTAP con `supabase test db` SIN reemplazar auth.uid()
# y (b) smoke tests HTTP con JWT reales (smoke_postgrest.py).
#
# Aislamiento: trabaja en una COPIA del proyecto dentro de la carpeta de evidencia, con
# project_id propio (epl1-smoke) y puertos 583xx, para no pisar ningún otro stack local;
# deshabilita los servicios que no hacen falta (realtime, storage, studio, correo,
# edge runtime, analytics). Al terminar ejecuta `supabase stop --no-backup` SÓLO de ese
# project_id. No usa `db push` ni ningún comando contra staging o producción: el stack
# aplica las migraciones del repo en su arranque local.
#
# Uso: SUPABASE_CLI=<ruta al binario supabase> smoke_stack_local.sh <dir_evidencia_nuevo>
#   (por defecto: apps/web/node_modules/.bin/supabase, instalado con `npm ci` en apps/web)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$DIR/../../.." && pwd)"
. "$DIR/lab.sh"
[ "$#" -eq 1 ] || { echo "uso: $0 <dir_evidencia_nuevo>" >&2; exit 2; }
OUT="$1"; dir_evidencia_nuevo "$OUT" || exit 2
CLI="${SUPABASE_CLI:-$REPO/apps/web/node_modules/.bin/supabase}"
[ -x "$CLI" ] || { echo "abortado: no se encuentra la CLI de Supabase ($CLI); ejecutá 'npm ci' en apps/web o definí SUPABASE_CLI" >&2; exit 2; }
export DO_NOT_TRACK=1 SUPABASE_TELEMETRY_DISABLED=1
unset PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD DATABASE_URL SUPABASE_DB_URL SUPABASE_ACCESS_TOKEN || true
vinculo_git "$OUT" || exit 5
PID="epl1-smoke"; DB_CONTAINER="supabase_db_${PID}"; PROY="$OUT/proyecto_stack"
if docker ps -a --format '{{.Names}}' | grep -q "_${PID}\$"; then echo "abortado: ya existen contenedores de $PID" >&2; exit 2; fi
for p in 58320 58321 58322; do ss -ltn 2>/dev/null | grep -q ":$p " && { echo "abortado: el puerto $p está ocupado" >&2; exit 2; }; done

mkdir -p "$PROY/supabase/tests"
cp -r "$REPO/supabase/migrations" "$PROY/supabase/migrations"
cp "$REPO"/supabase/tests/*.test.sql "$PROY/supabase/tests/"
python3 - "$REPO/supabase/config.toml" "$PROY/supabase/config.toml" "$PID" <<'PY'
import re, sys
src, dst, pid = sys.argv[1:4]
apagar = {"realtime", "studio", "local_smtp", "inbucket", "storage", "storage.s3_protocol", "storage.vector",
          "edge_runtime", "analytics", "db.seed", "experimental.pgdelta"}
sec, out = "", []
for l in open(src, encoding="utf-8"):
    m = re.match(r"^\[([^\]]+)\]\s*$", l)
    if m:
        sec = m.group(1)
    if re.match(r'^project_id\s*=', l):
        l = f'project_id = "{pid}"\n'
    elif sec in apagar and re.match(r"^enabled\s*=\s*true", l):
        l = "enabled = false\n"
    l = re.sub(r"\b543(\d\d)\b", r"583\1", l)
    out.append(l)
open(dst, "w", encoding="utf-8").write("".join(out))
PY
parar() { "$CLI" stop --workdir "$PROY" --no-backup --yes > "$OUT/supabase_stop.log" 2>&1; }
trap parar EXIT

{ echo "cli=$("$CLI" --version 2>&1 | head -1)"; echo "project_id=$PID"; } > "$OUT/entorno.txt"
"$CLI" start --workdir "$PROY" --yes -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor \
  > "$OUT/supabase_start.log" 2>&1; echo "rc_start=$?" >> "$OUT/entorno.txt"
grep -q 'rc_start=0' "$OUT/entorno.txt" || { echo "FALLA el arranque del stack (ver $OUT/supabase_start.log)" >&2; exit 6; }
docker ps --filter "name=_${PID}\$" --format '{{.Names}} {{.Image}}' | sort > "$OUT/imagenes_del_stack.txt"

ENVF="$(mktemp)"; "$CLI" status --workdir "$PROY" -o env > "$ENVF" 2>/dev/null
grep -vE 'KEY|SECRET|JWT|PASSWORD|_URL=.*:.*@' "$ENVF" > "$OUT/status_sin_secretos.txt"
getv() { grep -E "^$1=" "$ENVF" | head -1 | cut -d= -f2- | tr -d '"'; }
export API_URL="$(getv API_URL)" ANON_KEY="$(getv ANON_KEY)" SERVICE_ROLE_KEY="$(getv SERVICE_ROLE_KEY)" DB_CONTAINER
rm -f "$ENVF"
case "$API_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "abortado: API_URL no es local ($API_URL)" >&2; exit 7 ;;
esac

# (a) pgTAP completo con el mecanismo del proyecto, sobre GoTrue real (sin preludio de auth.uid()).
"$CLI" test db --workdir "$PROY" --local > "$OUT/supabase_test_db.log" 2>&1; echo "rc_test_db=$?" >> "$OUT/entorno.txt"
# (b) smoke HTTP con JWT reales.
python3 "$DIR/smoke_postgrest.py" "$OUT/smoke_resultados.tsv" "$OUT/smoke_transcripcion.txt" > "$OUT/smoke_consola.txt" 2>&1; echo "rc_smoke=$?" >> "$OUT/entorno.txt"
cat "$OUT/entorno.txt"; tail -3 "$OUT/supabase_test_db.log"; tail -2 "$OUT/smoke_resultados.tsv" 2>/dev/null
( cd "$OUT" && find . -type f ! -name MANIFIESTO.sha256 ! -path './proyecto_stack/*' -print0 | sort -z | xargs -0 sha256sum > MANIFIESTO.sha256 )
grep -q 'rc_test_db=0' "$OUT/entorno.txt" && grep -q 'rc_smoke=0' "$OUT/entorno.txt"
