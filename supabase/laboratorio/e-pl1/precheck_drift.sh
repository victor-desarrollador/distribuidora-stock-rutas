#!/usr/bin/env bash
# E-PL1 / H-01 — pruebas NEGATIVAS del precheck de la migración 20261111120000: ante una
# deriva del contrato D-2 (rol, membresías, privilegios, política, helper, vista) la
# migración debe ABORTAR sin dejar grants ni cambios en la vista.
#
# Cómo: UN contenedor aislado (lab.sh). Se aplican las 25 migraciones previas. Cada caso
# corre en una transacción: deriva → SAVEPOINT → migración nueva (sin ON_ERROR_STOP) →
# ROLLBACK TO SAVEPOINT → inspección del estado → ROLLBACK. Si la migración abortó, la
# inspección debe mostrar la vista con 4 columnas, sin grant de `nombre`, sin CREATE
# transitorio y sin funciones. Un caso pasa sólo si (a) hay un ERROR cuyo texto coincide
# con el esperado y (b) el estado observado tras la migración abortada es IDÉNTICO al
# observado justo después de la deriva (la deriva puede alterar por sí sola algún dato,
# p. ej. un lector superusuario "tiene" el grant) y no existen las funciones nuevas. Al final, un CONTROL POSITIVO aplica la
# migración sobre el estado limpio, como `postgres`, y debe terminar bien.
#
# Uso: precheck_drift.sh <dir_evidencia_nuevo_fuera_del_repo>
# Las derivas de atributos de rol exigen superusuario: se aplican como supabase_admin (el
# superusuario de la imagen) y la migración corre luego con `SET ROLE postgres`.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$DIR/../../.." && pwd)"
. "$DIR/lab.sh"
[ "$#" -eq 1 ] || { echo "uso: $0 <dir_evidencia_nuevo>" >&2; exit 2; }
OUT="$1"; dir_evidencia_nuevo "$OUT" || exit 2
unset PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD DATABASE_URL SUPABASE_DB_URL || true
vinculo_git "$OUT" || exit 5
lab_up || exit 3
trap 'lab_down' EXIT
echo "select version();" | lab_sql postgres -qtA > "$OUT/version.txt"
lab_migraciones "$OUT/migraciones_base" "$LAB_NUEVA_MIGRACION" || exit 4
MIG="$REPO/supabase/migrations/$LAB_NUEVA_MIGRACION"
mkdir -p "$OUT/casos"; : > "$OUT/resultados.tsv"
# Contadores separados (M-01): negativas y controles positivos NO se suman. Las cantidades
# esperadas son fijas a propósito: agregar o quitar un caso exige cambiarlas en el mismo
# commit, para que el conjunto de casos no se achique en silencio.
NEG_EJEC=0; NEG_OK=0; POS_EJEC=0; POS_OK=0; FALLOS=0
ESPERADO_NEG=29; ESPERADO_POS=1

# caso <nombre> <regex_del_error_esperado> <sql_de_la_deriva>
caso() {
  local nombre="$1" esperado="$2" deriva="$3" log="$OUT/casos/$1.log" estado previo err
  {
    echo "begin;"
    printf '%s\n' "$deriva"
    lab_inspeccion_sql
    echo "savepoint antes_de_la_migracion;"
    echo "set role postgres;"
    cat "$MIG"
    echo "rollback to savepoint antes_de_la_migracion;"
    echo "reset role;"
    lab_inspeccion_sql
    echo "rollback;"
  } | docker exec -i "$LAB_CONTAINER" psql -X -a -U supabase_admin -h localhost -d postgres -v ON_ERROR_STOP=0 > "$log" 2>&1
  NEG_EJEC=$((NEG_EJEC+1))
  err="$(grep -m1 -E '^psql:.*ERROR:|^ERROR:' "$log" | head -1)"
  previo="$(grep -E '^ ?INSPECCION\|vista_columnas=[0-9]' "$log" | head -1 | sed 's/^ //')"
  estado="$(grep -E '^ ?INSPECCION\|vista_columnas=[0-9]' "$log" | tail -1 | sed 's/^ //')"
  if [ -n "$err" ] && printf '%s' "$err" | grep -Eq -- "$esperado" \
     && [ -n "$previo" ] && [ "$estado" = "$previo" ] && [[ "$estado" == *"|fn_privada=false|fn_fachada=false" ]]; then
    NEG_OK=$((NEG_OK+1))
    printf 'PASA\t%s\t%s\n' "$nombre" "${err#*ERROR:  }" | tee -a "$OUT/resultados.tsv"
  else
    FALLOS=$((FALLOS+1))
    printf 'FALLA\t%s\terror=[%s] previo=[%s] estado=[%s]\n' "$nombre" "$err" "$previo" "$estado" | tee -a "$OUT/resultados.tsv"
  fi
}


# --- atributos de rol ---
caso lector_bypassrls          'atributos de lector_perfiles_rpc'            "alter role lector_perfiles_rpc bypassrls;"
caso lector_superusuario       'atributos de lector_perfiles_rpc|estado D-2 de cuatro columnas|privilegios de esquema residuales'            "alter role lector_perfiles_rpc superuser;"
caso lector_login              'atributos de lector_perfiles_rpc'            "alter role lector_perfiles_rpc login;"
caso lector_createrole         'atributos de lector_perfiles_rpc'            "alter role lector_perfiles_rpc createrole;"
caso propietario_bypassrls     'atributos de propietario_rpc'                "alter role propietario_rpc bypassrls;"
caso propietario_superusuario  'atributos de propietario_rpc|privilegios de esquema residuales'                "alter role propietario_rpc superuser;"
caso propietario_login         'atributos de propietario_rpc'                "alter role propietario_rpc login;"
caso propietario_createrole    'atributos de propietario_rpc'                "alter role propietario_rpc createrole;"
caso lector_row_security_off   'configuración propia'                        "alter role lector_perfiles_rpc set row_security = off;"
# --- membresías ---
caso authenticated_puede_set_lector 'membresía|puede hacer SET'              "grant lector_perfiles_rpc to authenticated;"
caso lector_miembro_de_otro_rol     'membresía|estado D-2 de cuatro columnas|P2'                              "grant authenticated to lector_perfiles_rpc;"
# --- privilegios peligrosos ---
caso lector_select_usuario     'D-2 \(P2\)'                                  "grant select (usuario) on public.perfiles to lector_perfiles_rpc;"
caso lector_update_activo       'D-2 \(P2\)'                                  "grant update (activo) on public.perfiles to lector_perfiles_rpc;"
caso lector_select_empresas     'D-2 \(P2\)'                                  "grant select on public.empresas to lector_perfiles_rpc;"
caso lector_usage_privado       'privilegios de esquema residuales'           "grant usage on schema privado to lector_perfiles_rpc;"
caso lector_default_acl         'privilegios por defecto'                     "alter default privileges for role postgres in schema public grant select on tables to lector_perfiles_rpc;"
caso lector_ya_tiene_nombre     'estado D-2 de cuatro columnas|D-2 \(P2\)'    "grant select (nombre) on public.perfiles to lector_perfiles_rpc;"
# --- política alterada ---
caso politica_lector_true       'la política del lector no'   "alter policy perfiles_select_empresa_lector on public.perfiles using (true);"
caso politica_lector_otro_rol   'la política del lector no|no coinciden con las aprobadas' "alter policy perfiles_select_empresa_lector on public.perfiles to public;"
caso politica_extra_lector      'no coinciden con las aprobadas'             "create policy deriva_extra on public.perfiles for select to lector_perfiles_rpc using (true);"
caso politica_authenticated_true 'perfiles_select_propio no es la aprobada'  "alter policy perfiles_select_propio on public.perfiles using (true);"
caso perfiles_force_rls         'sin FORCE'                                  "alter table public.perfiles force row level security;"
# --- helper modificado ---
caso helper_cuerpo_distinto     'cuerpo del helper'                          "create or replace function privado.empresa_gestion_actual() returns uuid language sql stable security definer set search_path = '' as \$f\$ select p.empresa_id from public.perfiles p limit 1 \$f\$;"
caso helper_execute_authenticated 'helper no es SQL|helper no quedó|P3|acceso a la vista o al helper' "grant execute on function privado.empresa_gestion_actual() to authenticated;"
caso helper_owner_postgres      'helper no quedó|P3'                         "alter function privado.empresa_gestion_actual() owner to postgres;"
# --- vista protegida ---
caso vista_sin_opciones         'la vista no quedó con el owner, las opciones' "create or replace view privado.perfiles_empresa_gestion as select p.usuario_id, p.empresa_id, p.rol, p.activo from public.perfiles p;"
caso vista_acl_authenticated    'la vista no quedó con el owner, las opciones|acceso a la vista' "grant select on privado.perfiles_empresa_gestion to authenticated;"
caso vista_owner_postgres       'la vista no quedó con el owner, las opciones' "alter view privado.perfiles_empresa_gestion owner to postgres;"
caso vista_columna_extra        'D-2 \(P4\)|definición|estado D-2 de cuatro columnas'                      "create or replace view privado.perfiles_empresa_gestion with (security_invoker = false, security_barrier = true) as select p.usuario_id, p.empresa_id, p.rol, p.activo, p.usuario from public.perfiles p;"

# --- CONTROL POSITIVO: sobre el estado limpio la migración (como postgres) debe aplicar ---
lab_sql postgres -a < "$MIG" > "$OUT/control_positivo.log" 2>&1; RC=$?
lab_inspeccion_sql | lab_sql postgres -qtA > "$OUT/control_positivo_estado.txt" 2>&1
POS_EJEC=$((POS_EJEC+1))
if [ "$RC" -eq 0 ] && grep -q '^INSPECCION|vista_columnas=5|grant_nombre_lector=true|create_lector_privado=false|create_propietario_privado=false|fn_privada=true|fn_fachada=true$' "$OUT/control_positivo_estado.txt"; then
  POS_OK=$((POS_OK+1))
  printf 'PASA\tcontrol_positivo\tla migración aplica sobre el estado limpio\n' | tee -a "$OUT/resultados.tsv"
else
  FALLOS=$((FALLOS+1)); printf 'FALLA\tcontrol_positivo\trc=%s\n' "$RC" | tee -a "$OUT/resultados.tsv"
fi
# Cobertura: el conjunto de casos no puede achicarse (ni crecer) sin cambiar las constantes.
if [ "$NEG_EJEC" -ne "$ESPERADO_NEG" ] || [ "$POS_EJEC" -ne "$ESPERADO_POS" ]; then
  FALLOS=$((FALLOS+1))
  printf 'FALLA\tcobertura\tse esperaban %s negativas y %s control(es) positivo(s); se ejecutaron %s y %s\n' "$ESPERADO_NEG" "$ESPERADO_POS" "$NEG_EJEC" "$POS_EJEC" | tee -a "$OUT/resultados.tsv"
fi
echo "--- negativas: ejecutadas=$NEG_EJEC rechazadas_correctamente=$NEG_OK | controles_positivos: ejecutados=$POS_EJEC aprobados=$POS_OK | fallos=$FALLOS" | tee -a "$OUT/resultados.tsv"
( cd "$OUT" && find . -type f ! -name MANIFIESTO.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFIESTO.sha256 )
[ "$FALLOS" -eq 0 ] && [ "$NEG_OK" -eq "$NEG_EJEC" ] && [ "$POS_OK" -eq "$POS_EJEC" ]
