#!/usr/bin/env bash
# O4-PGTEMP — prueba de EXPLOTACIÓN (regresión de seguridad). NO forma parte de
# `supabase test db`. Sólo corre en un contenedor PostgreSQL 17 descartable que
# este arnés crea, aísla (--network none, sin puertos ni montajes) y verifica;
# nunca acepta un destino de conexión: toda la SQL entra por `docker exec`
# dentro de ESE contenedor. Cualquier incertidumbre aborta.
#
# Qué demuestra (cada vector en su propia sesión, sin caché de plpgsql):
#   estado ORIGINAL (cuerpo de staging 325ae266…, search_path=pg_catalog):
#     record y name → la sonda corre como un rol privilegiado (control positivo);
#   estado REMEDIADO (migración 20261110120000, RB + RA):
#     record, name, format y op_eq → 0 ejecuciones privilegiadas;
#   format y op_eq: PostgreSQL nunca busca funciones ni operadores en pg_temp;
#     se verifica que la sonda funciona si se la invoca explícitamente y que el
#     trigger no la invoca en ninguno de los dos estados (sin control positivo
#     posible: no son vectores de resolución).
# La sonda sólo cuenta; no altera datos ni RLS.
#
# Uso: supabase/laboratorio/o4-pgtemp/ejecutar.sh <dir_salida_vacío_o_inexistente>
set -euo pipefail
[ "$#" -eq 1 ] || { echo "uso: $0 <dir_salida>" >&2; exit 2; }
OUT="$1"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../.." && pwd)"
IMG="public.ecr.aws/supabase/postgres@sha256:b15d862126dd2dac02da524696ccfde2dcce2ceaee0a58973b2727befe492706"  # 17.11.0.004
H_ORIGINAL=325ae266d9b166715ef5230ceaf7ff9d523e483cf5610dfb9779ab3f183f4af9
MIG="$REPO/supabase/migrations/20261110120000_o4_pgtemp_remediacion.sql"

# Ninguna variable de conexión del entorno puede influir.
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGPASSWORD PGSERVICE PGSERVICEFILE PGPASSFILE DATABASE_URL SUPABASE_DB_URL || true

if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then echo "abortado: $OUT no está vacío" >&2; exit 2; fi
mkdir -p "$OUT"
command -v docker >/dev/null || { echo "abortado: docker no disponible" >&2; exit 2; }
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "abortado: imagen $IMG no presente localmente (no se descarga desde aquí)" >&2; exit 2; }
[ "$(sha256sum "$DIR/cuerpo_original_325ae266.txt" | cut -d' ' -f1)" = "$H_ORIGINAL" ] || { echo "abortado: cuerpo de referencia alterado" >&2; exit 2; }
[ -f "$MIG" ] || { echo "abortado: falta la migración RB + RA" >&2; exit 2; }

NONCE="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
LAB="o4lab_${NONCE:0:16}"
CID=""
limpiar() { [ -n "$CID" ] && docker rm -f "$CID" > "$OUT/contenedor_eliminado.txt" 2>&1 || true; }
trap limpiar EXIT

CID="$(docker run -d --name "$LAB" --label "t3.o4pgtemp.nonce=$NONCE" --network none \
        -e POSTGRES_PASSWORD="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')" "$IMG")"

# --- Verificación del aislamiento del contenedor (antes de cualquier SQL) ---
verificar_contenedor() {
  local id net ports mounts nets label img
  id="$(docker inspect --format '{{.Id}}' "$LAB")"
  net="$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$LAB")"
  ports="$(docker inspect --format '{{json .HostConfig.PortBindings}}' "$LAB")"
  mounts="$(docker inspect --format '{{json .Mounts}}' "$LAB")"
  nets="$(docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$LAB")"
  label="$(docker inspect --format '{{index .Config.Labels "t3.o4pgtemp.nonce"}}' "$LAB")"
  img="$(docker inspect --format '{{.Image}}' "$LAB")"
  [ "$id" = "$CID" ] || { echo "abortado: ID de contenedor distinto" >&2; exit 3; }
  [ "$net" = "none" ] || { echo "abortado: red $net" >&2; exit 3; }
  [ "$nets" = "none " ] || { echo "abortado: redes '$nets'" >&2; exit 3; }
  [ "$ports" = "{}" ] || [ "$ports" = "null" ] || { echo "abortado: puertos $ports" >&2; exit 3; }
  [ "$mounts" = "[]" ] || { echo "abortado: montajes $mounts" >&2; exit 3; }
  [ "$label" = "$NONCE" ] || { echo "abortado: etiqueta nonce distinta" >&2; exit 3; }
  [ "$img" = "sha256:b15d862126dd2dac02da524696ccfde2dcce2ceaee0a58973b2727befe492706" ] || { echo "abortado: imagen $img" >&2; exit 3; }
  echo "AISLAMIENTO|OK|id=${CID:0:12}|red=$net|puertos=$ports|montajes=$mounts|imagen=${img:7:12}"
}
verificar_contenedor | tee "$OUT/aislamiento.txt"
for i in $(seq 1 90); do docker exec "$CID" pg_isready -U postgres -h localhost >/dev/null 2>&1 && break; sleep 2; done
sleep 3
ps() { docker exec -i "$CID" psql -X -U "$1" -h localhost -d postgres -v ON_ERROR_STOP=1 "${@:2}"; }

# --- Migraciones del repo (incluida RB + RA: no-op sin O-4) ---
: > "$OUT/migraciones.txt"
for f in "$REPO"/supabase/migrations/*.sql; do
  ps postgres -q < "$f" > /dev/null 2> "$OUT/mig_$(basename "$f").stderr" || { echo "abortado: migración $(basename "$f")" >&2; exit 4; }
  echo "$(sha256sum "$f" | cut -d' ' -f1) $(basename "$f")" >> "$OUT/migraciones.txt"
done

# --- Identidad del laboratorio y roles del atacante (sólo aquí) ---
SYSID="$(ps postgres -qtA -c 'select system_identifier from pg_control_system()')"
ps supabase_admin -qtA > "$OUT/identidad.txt" 2>&1 <<SQL
create schema zz_laboratorio;
create table zz_laboratorio.identidad (nonce text not null, sysid text not null);
insert into zz_laboratorio.identidad values ('$NONCE', (select system_identifier::text from pg_control_system()));
grant usage on schema zz_laboratorio to postgres;
grant select on zz_laboratorio.identidad to postgres;
create role zz_atk nologin;
create role zz_atk_create nologin;
grant create on schema public to zz_atk_create;
grant zz_atk, zz_atk_create to postgres with set true, inherit false;
select 'IDENTIDAD|OK';
SQL
grep -q 'IDENTIDAD|OK' "$OUT/identidad.txt" || { echo "abortado: identidad" >&2; exit 5; }
verificar_contenedor >> "$OUT/aislamiento.txt"

sesion() { # sesion <archivo_salida> <sql> [opciones psql]
  local o="$1" sql="$2"; shift 2
  set +e
  { cat "$DIR/guardia.sql"; printf '%s\n' "$sql"; } | ps postgres -qtA -v lab_nonce="$NONCE" -v lab_sysid="$SYSID" "$@" > "$o.stdout" 2> "$o.stderr"
  echo $? > "$o.rc"; set -e
}

# --- Autocomprobación de la guardia (debe abortar sin ejecutar nada) ---
mkdir -p "$OUT/guardia"
set +e
{ cat "$DIR/guardia.sql"; echo "select 'NO_DEBIO_LLEGAR';"; } | ps postgres -qtA -v lab_nonce="${NONCE%?}x" -v lab_sysid="$SYSID" > "$OUT/guardia/G1_nonce_erroneo.stdout" 2> "$OUT/guardia/G1_nonce_erroneo.stderr"; echo $? > "$OUT/guardia/G1_nonce_erroneo.rc"
{ cat "$DIR/guardia.sql"; echo "select 'NO_DEBIO_LLEGAR';"; } | ps postgres -qtA -v lab_sysid="$SYSID" > "$OUT/guardia/G2_sin_nonce.stdout" 2> "$OUT/guardia/G2_sin_nonce.stderr"; echo $? > "$OUT/guardia/G2_sin_nonce.rc"
{ cat "$DIR/guardia.sql"; echo "select 'NO_DEBIO_LLEGAR';"; } | ps postgres -qtA -v lab_nonce="$NONCE" -v lab_sysid=1 > "$OUT/guardia/G3_sysid_erroneo.stdout" 2> "$OUT/guardia/G3_sysid_erroneo.stderr"; echo $? > "$OUT/guardia/G3_sysid_erroneo.rc"
set -e
for g in G1_nonce_erroneo G2_sin_nonce G3_sysid_erroneo; do
  if [ "$(cat "$OUT/guardia/$g.rc")" = 0 ] || grep -q NO_DEBIO_LLEGAR "$OUT/guardia/$g.stdout"; then echo "abortado: la guardia no detuvo $g" >&2; exit 6; fi
done
echo "GUARDIA_AUTOPRUEBA|OK|G1 G2 G3 abortaron" | tee "$OUT/guardia/resumen.txt"

# H-04: instantánea CANÓNICA de RLS (tablas y, por política: nombre, comando, permisividad, roles ordenados, USING y WITH CHECK con
# la diferencia entre NULL y expresión presente), en lugar del conteo de políticas. Ver rls_instantanea.sql y probar_rls_instantanea.sh.
rls() { ps postgres -qtA < "$DIR/rls_instantanea.sql" > "$1"; }

# --- Estado ORIGINAL (vulnerable): sólo dentro del laboratorio verificado ---
mkdir -p "$OUT/original" "$OUT/remediado"
PREP="$(printf 'create function public.rls_auto_enable() returns event_trigger\n  language plpgsql security definer set search_path = pg_catalog\n  as $o4$'; cat "$DIR/cuerpo_original_325ae266.txt"; printf '$o4$;\nrevoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role;\ncreate event trigger ensure_rls on ddl_command_end\n  when tag in (%s)\n  execute function public.rls_auto_enable();\n' "'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO'"; printf x)"; PREP="${PREP%x}"
sesion "$OUT/original/preparacion" "$PREP"
[ "$(cat "$OUT/original/preparacion.rc")" = 0 ] || { echo "abortado: preparación del estado original" >&2; exit 7; }
HASH_ACT() { ps postgres -qtA -c "select encode(sha256(convert_to(prosrc,'UTF8')),'hex') || '|' || proconfig::text from pg_proc where oid = to_regprocedure('public.rls_auto_enable()')"; }
echo "ESTADO|original|$(HASH_ACT)" | tee "$OUT/original/estado.txt"
grep -q "^ESTADO|original|$H_ORIGINAL|{search_path=pg_catalog}$" "$OUT/original/estado.txt" || { echo "abortado: estado original inesperado" >&2; exit 7; }

vectores() { # vectores <estado>
  local e="$1"
  rls "$OUT/$e/rls_antes.txt"
  for v in record name format op_eq; do
    local at=zz_atk ddl="create temp table zz_o4_t (i pg_catalog.int4)"
    [ "$v" = format ] && { at=zz_atk_create; ddl="create table public.zz_o4_v (i pg_catalog.int4)"; }
    sesion "$OUT/$e/$v" "$(cat "$DIR/vector.sql")" -v atacante="$at" -v vector="$v" -v ddl="$ddl" -v "v_$v=1"
    grep -q 'GUARDIA|OK' "$OUT/$e/$v.stdout" || { echo "abortado: guardia en $e/$v" >&2; exit 8; }
  done
  rls "$OUT/$e/rls_despues.txt"
}
vectores original

# --- Remediación con la migración real del repo ---
sesion "$OUT/remediado/migracion" "$(cat "$MIG")"
grep -q 'o4_pgtemp: remediación aplicada' "$OUT/remediado/migracion.stderr" || { echo "abortado: la migración no aplicó la remediación" >&2; exit 9; }
echo "ESTADO|remediado|$(HASH_ACT)" | tee "$OUT/remediado/estado.txt"
vectores remediado

# --- Aserciones individuales (una por vector y estado) ---
R="$OUT/resumen.tsv"; printf 'id\testado\tvector\tpriv\tatk\tdisparo\tcontrol\tesperado\tveredicto\n' > "$R"
fallas=0
aserta() { # aserta <id> <estado> <vector> <esperado: escala|no_escala>
  local id="$1" e="$2" v="$3" esp="$4" f="$OUT/$2/$3"
  local m priv atk disp ctrl ok
  m="$(grep -m1 '^MEDIDA|' "$f.stdout" || true)"
  priv="$(printf '%s' "$m" | sed -n 's/.*|priv=\([0-9]*\)|.*/\1/p')"; atk="$(printf '%s' "$m" | sed -n 's/.*|atk=\([0-9]*\)$/\1/p')"
  # El trigger se disparó: LOG propio o error con contexto de rls_auto_enable.
  if grep -q 'LOG:  rls_auto_enable:' "$f.stderr" || grep -q 'DDL_ERROR|.*rls_auto_enable' "$f.stderr"; then disp=si; else disp=no; fi
  ctrl=na; if [ "$v" = format ] || [ "$v" = op_eq ]; then grep -q '^CONTROL|' "$f.stdout" && [ "$(grep -m1 '^ANTES|' "$f.stdout" | sed 's/.*atk=//')" -ge 1 ] && ctrl=si || ctrl=no; fi
  ok=FALLA
  if [ "$(cat "$f.rc")" = 0 ] && [ -n "$priv" ] && [ "$disp" = si ] && [ "$ctrl" != no ]; then
    if [ "$esp" = escala ] && [ "$priv" -gt 0 ]; then ok=PASA; fi
    if [ "$esp" = no_escala ] && [ "$priv" -eq 0 ]; then ok=PASA; fi
  fi
  [ "$ok" = PASA ] || fallas=$((fallas+1))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$e" "$v" "${priv:-?}" "${atk:-?}" "$disp" "$ctrl" "$esp" "$ok" >> "$R"
}
aserta X01 original  record escala
aserta X02 original  name   escala
aserta X03 original  format no_escala
aserta X04 original  op_eq  no_escala
aserta X05 remediado record no_escala
aserta X06 remediado name   no_escala
aserta X07 remediado format no_escala
aserta X08 remediado op_eq  no_escala
for e in original remediado; do
  if cmp -s "$OUT/$e/rls_antes.txt" "$OUT/$e/rls_despues.txt"; then r=PASA; else r=FALLA; fallas=$((fallas+1)); fi
  printf 'X_RLS_%s\t%s\trls_public\t-\t-\t-\t-\tsin_cambios\t%s\n' "$e" "$e" "$r" >> "$R"
done
column -t -s $'\t' "$R"
echo "RESULTADO|fallas=$fallas"
[ "$fallas" -eq 0 ]
