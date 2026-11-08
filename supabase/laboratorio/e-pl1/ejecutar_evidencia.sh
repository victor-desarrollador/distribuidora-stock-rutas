#!/usr/bin/env bash
# E-PL1 / H-02 — procedimiento LOCAL y reproducible de evidencia. Corre, en este orden:
#   1. vínculo Git (commit, árbol, estado y SHA-256 de los archivos) ANTES de ejecutar;
#   2. 26 migraciones desde base limpia en un contenedor aislado (logs íntegros);
#   3. la suite pgTAP completa en ese contenedor (con el preludio de auth.uid(), declarado);
#   4. las pruebas negativas de deriva del precheck (precheck_drift.sh);
#   5. opcional (CON_STACK=1): stack local de Supabase con `supabase test db` y smoke HTTP
#      reales, SIN preludio (smoke_stack_local.sh).
# Conserva todo en <dir_evidencia_nuevo> (fuera del repositorio, modo 700, no se sobrescribe).
#
# Evidencia VINCULADA a un commit: exportar GIT_COMMIT_ESPERADO y GIT_ARBOL_ESPERADO; el
# procedimiento aborta si el HEAD o el árbol difieren o si hay cambios sin commitear. Sin
# esas variables la corrida es EXPLORATORIA y queda marcada NO VINCULADA.
# No usa `supabase db push`, no se conecta a staging ni producción.
#
# Uso: [CON_STACK=1 SUPABASE_CLI=...] [GIT_COMMIT_ESPERADO=... GIT_ARBOL_ESPERADO=...] \
#        ejecutar_evidencia.sh <dir_evidencia_nuevo>
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$DIR/../../.." && pwd)"
. "$DIR/lab.sh"
[ "$#" -eq 1 ] || { echo "uso: $0 <dir_evidencia_nuevo>" >&2; exit 2; }
OUT="$1"; dir_evidencia_nuevo "$OUT" || exit 2
unset PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD DATABASE_URL SUPABASE_DB_URL || true
vinculo_git "$OUT" || exit 5
cat "$OUT/ESTADO_DE_LA_EVIDENCIA.txt"
RC=0
lab_up || exit 3
trap 'lab_down' EXIT
{ echo "imagen=$LAB_IMG"; docker inspect --format 'imagen_id={{.Image}} red={{.HostConfig.NetworkMode}} puertos={{json .HostConfig.PortBindings}} montajes={{json .Mounts}}' "$LAB_CONTAINER"; } > "$OUT/aislamiento.txt"
echo "select version();" | lab_sql postgres -qtA > "$OUT/version_postgresql.txt"
echo "select 'auth.uid(' || ')=' || regexp_replace(prosrc, '\s+', ' ', 'g') from pg_proc where oid='auth.uid'::regproc;" | lab_sql postgres -qtA > "$OUT/auth_uid_de_la_imagen.txt"

echo "== 1. migraciones (desde base limpia)"
lab_migraciones "$OUT/migraciones" || { echo "FALLÓ una migración" | tee "$OUT/RESULTADO.txt"; exit 4; }
echo "migraciones aplicadas: $(ls "$OUT/migraciones"/*.rc | wc -l)" | tee "$OUT/resumen_migraciones.txt"

echo "== 2. pgTAP completo (con preludio de auth.uid() de laboratorio)"
lab_sql supabase_admin -q < "$DIR/preludio_authuid.sql" > "$OUT/preludio_authuid.log" 2>&1
mkdir -p "$OUT/pgtap"; : > "$OUT/pgtap/_resumen.txt"; TOK=0; TNOK=0
for t in "$REPO"/supabase/tests/*.test.sql; do
  b="$(basename "$t" .test.sql)"
  docker exec -i "$LAB_CONTAINER" psql -X -qtA -U postgres -h localhost -d postgres -v ON_ERROR_STOP=0 < "$t" > "$OUT/pgtap/$b.tap" 2>&1
  ok=$(grep -cE '^ok ' "$OUT/pgtap/$b.tap"); nok=$(grep -cE '^not ok ' "$OUT/pgtap/$b.tap"); plan=$(grep -m1 -oE '^1\.\.[0-9]+' "$OUT/pgtap/$b.tap")
  TOK=$((TOK+ok)); TNOK=$((TNOK+nok)); echo "$b plan=${plan:-?} ok=$ok not_ok=$nok" >> "$OUT/pgtap/_resumen.txt"
  [ "$nok" -eq 0 ] && [ "${plan#1..}" = "$ok" ] || RC=1
done
echo "TOTAL ok=$TOK not_ok=$TNOK" | tee -a "$OUT/pgtap/_resumen.txt"

echo "== 3. pruebas negativas de deriva del precheck"
bash "$DIR/precheck_drift.sh" "$OUT/deriva_precheck" > "$OUT/deriva_precheck.consola.txt" 2>&1 || RC=1
tail -1 "$OUT/deriva_precheck.consola.txt"

if [ "${CON_STACK:-0}" = 1 ]; then
  echo "== 4. stack local de Supabase (supabase test db + smoke HTTP, sin preludio)"
  bash "$DIR/smoke_stack_local.sh" "$OUT/stack_local" > "$OUT/stack_local.consola.txt" 2>&1 || RC=1
  tail -4 "$OUT/stack_local.consola.txt"
fi

echo "rc_global=$RC" | tee "$OUT/RESULTADO.txt"
( cd "$OUT" && find . -type f ! -name MANIFIESTO.sha256 ! -path './stack_local/proyecto_stack/*' -print0 | sort -z | xargs -0 sha256sum > MANIFIESTO.sha256 && sha256sum -c MANIFIESTO.sha256 > /dev/null ) || RC=1
exit "$RC"
