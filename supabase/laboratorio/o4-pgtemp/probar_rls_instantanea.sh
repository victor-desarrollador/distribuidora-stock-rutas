#!/usr/bin/env bash
# H-04 — Sensibilidad de la instantánea canónica de RLS (rls_instantanea.sql). NO se conecta a ningún destino remoto: crea UN
# contenedor descartable (sin red, sin puertos, sin montajes; ver lab_comun.sh), aplica las migraciones del repo y, dentro de
# BEGIN … ROLLBACK, modifica o sustituye políticas conservando su cantidad para comprobar que la instantánea lo detecta.
# Casos «I» (la instantánea debe quedar IGUAL: orden físico, orden de roles) y «N» (debe DIFERIR). Ningún caso deja residuos (R01).
# Uso: probar_rls_instantanea.sh <dir_salida_nuevo_absoluto_fuera_del_repo>
set -uo pipefail
[ "$#" -eq 1 ] || { echo "uso: $0 <dir_salida_nuevo_absoluto_fuera_del_repo>" >&2; exit 2; }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../.." && pwd)"
. "$DIR/vinculo_evidencia.sh"
OUT="$1"
dir_evidencia_seguro "$OUT" || exit 2
vinculo_git "$OUT" || { echo "abortado: integridad del código no establecida; ver $OUT/vinculo_git.txt" >&2; exit 5; }
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGPASSWORD PGSERVICE PGSERVICEFILE DATABASE_URL SUPABASE_DB_URL || true
. "$DIR/lab_comun.sh"
SNAPF="$DIR/rls_instantanea.sql"
docker image inspect "$LAB_IMG" >/dev/null 2>&1 || { echo "abortado: imagen $LAB_IMG no presente (no se descarga)" >&2; exit 2; }
export LAB_NONCE="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"; export LAB_CONTAINER="${LAB_PREFIJO}${LAB_NONCE:0:12}"
CID=""; limpiar() { [ -n "$CID" ] && docker rm -f -v "$CID" > "$OUT/contenedor_eliminado.txt" 2>&1; }; trap limpiar EXIT
CID="$(docker run -d --name "$LAB_CONTAINER" --label "t3.o4m01.nonce=$LAB_NONCE" --network none -e POSTGRES_PASSWORD="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')" "$LAB_IMG")" || { echo "abortado: docker run" >&2; exit 3; }
lab_verificar; docker inspect --format 'red={{.HostConfig.NetworkMode}} puertos={{json .HostConfig.PortBindings}} montajes={{json .Mounts}}' "$LAB_CONTAINER" | tee "$OUT/aislamiento.txt"
for i in $(seq 1 90); do docker exec "$LAB_CONTAINER" pg_isready -U postgres -h localhost >/dev/null 2>&1 && break; sleep 2; done; sleep 3
for f in "$REPO"/supabase/migrations/*.sql; do
  lab_sql postgres -q < "$f" >/dev/null 2>"$OUT/mig_$(basename "$f").stderr" || { echo "abortado: migración $(basename "$f")" >&2; exit 4; }
done
lab_sql supabase_admin -qtA >/dev/null <<SQL || { echo "abortado: identidad" >&2; exit 5; }
create schema zz_laboratorio; create table zz_laboratorio.identidad (nonce text not null, sysid text not null);
insert into zz_laboratorio.identidad values ('$LAB_NONCE', (select system_identifier::text from pg_control_system()));
SQL
lab_identidad

FALLAS=0; TOTAL=0
chk() { TOTAL=$((TOTAL+1)); if [ "$1" = "ok" ]; then echo "PASA   $2"; else echo "FALLA  $2"; FALLAS=$((FALLAS+1)); fi; }
# La instantánea como sentencia reutilizable: sin el «;» final.
SNAP="$(cat "$SNAPF")"; SNAP="${SNAP%;}"
[ -n "$SNAP" ] || { echo "abortado: no se pudo leer la instantánea" >&2; exit 2; }

FIXTURE="create table public.zz_h04_t (id int, emp int);
alter table public.zz_h04_t enable row level security;
create policy p_sel on public.zz_h04_t as permissive for select to authenticated, anon using (emp = 1);
create policy p_ins on public.zz_h04_t for insert to authenticated with check (emp = 1);
create policy p_upd on public.zz_h04_t for update to authenticated using (emp = 1) with check (emp = 1);
create policy p_upd2 on public.zz_h04_t for update to authenticated using (emp = 1);
create policy p_upd3 on public.zz_h04_t for update to authenticated with check (emp = 1);
create policy p_del on public.zz_h04_t for delete to authenticated using (emp = 1);"

# caso <id> <igual|distinto> <descripción> <sql_mutación>
caso() {
  local id="$1" esp="$2" desc="$3" mut="$4" r a b ca cb res ok=1
  r="$({ printf 'BEGIN;\n%s\n' "$FIXTURE"
         printf 'create temp table zz_s0 as select row_number() over () as n, x.linea from (%s) x;\nselect count(*) into temp table zz_c0 from pg_policy;\n' "$SNAP"
         printf '%s\n' "$mut"
         printf 'create temp table zz_s1 as select row_number() over () as n, x.linea from (%s) x;\nselect count(*) into temp table zz_c1 from pg_policy;\n' "$SNAP"
         printf "select 'RES|' || ((select array_agg(linea order by n) from zz_s0) is not distinct from (select array_agg(linea order by n) from zz_s1))::text || '|conteo_igual=' || ((select count from zz_c0) = (select count from zz_c1))::text;\n"
         printf 'ROLLBACK;\n'; } | lab_sql postgres -qtA 2>&1)"
  res="$(printf '%s' "$r" | grep -m1 '^RES|')"
  if [ -z "$res" ]; then chk no "$id $desc: la sesión falló ($(printf '%s' "$r" | head -c 200))"; return; fi
  case "$esp" in
    igual)   [ "${res#RES|}" = "true|conteo_igual=true" ] || ok=0 ;;
    distinto) printf '%s' "$res" | grep -q '^RES|false|conteo_igual=true$' || ok=0 ;;
  esac
  chk "$([ $ok -eq 1 ] && echo ok)" "$id $desc → ${res#RES|} (esperado: instantánea $esp; el conteo antiguo no lo vería)"
}

echo "# I — la instantánea debe quedar IGUAL (no depende del orden físico ni del orden de roles)"
caso I01 igual "sin cambios" "select 1;"
caso I02 igual "políticas recreadas idénticas en otro orden (orden físico distinto)" "drop policy p_del on public.zz_h04_t; drop policy p_upd3 on public.zz_h04_t; drop policy p_upd2 on public.zz_h04_t; drop policy p_upd on public.zz_h04_t; drop policy p_ins on public.zz_h04_t; drop policy p_sel on public.zz_h04_t;
create policy p_del on public.zz_h04_t for delete to authenticated using (emp = 1);
create policy p_upd3 on public.zz_h04_t for update to authenticated with check (emp = 1);
create policy p_upd2 on public.zz_h04_t for update to authenticated using (emp = 1);
create policy p_upd on public.zz_h04_t for update to authenticated using (emp = 1) with check (emp = 1);
create policy p_ins on public.zz_h04_t for insert to authenticated with check (emp = 1);
create policy p_sel on public.zz_h04_t as permissive for select to authenticated, anon using (emp = 1);"
caso I03 igual "mismos roles declarados en otro orden" "alter policy p_sel on public.zz_h04_t to anon, authenticated;"
caso I04 igual "misma expresión reescrita sin cambio de texto normalizado" "alter policy p_sel on public.zz_h04_t using (emp = 1);"
echo "# N — la instantánea debe DIFERIR conservando la cantidad de políticas"
caso N01 distinto "cambio de nombre" "alter policy p_sel on public.zz_h04_t rename to p_sel_renombrada;"
caso N02 distinto "cambio de comando (misma cantidad)" "drop policy p_ins on public.zz_h04_t; create policy p_ins on public.zz_h04_t for delete to authenticated using (emp = 1);"
caso N03 distinto "cambio de permisividad" "drop policy p_sel on public.zz_h04_t; create policy p_sel on public.zz_h04_t as restrictive for select to authenticated, anon using (emp = 1);"
caso N04 distinto "cambio de roles" "alter policy p_sel on public.zz_h04_t to authenticated;"
caso N05 distinto "cambio de USING" "alter policy p_sel on public.zz_h04_t using (emp = 2);"
caso N06 distinto "cambio de WITH CHECK" "alter policy p_upd on public.zz_h04_t with check (emp = 2);"
caso N07 distinto "WITH CHECK pasa de NULL a presente" "alter policy p_upd2 on public.zz_h04_t with check (emp = 1);"
caso N08 distinto "USING pasa de NULL a presente" "alter policy p_upd3 on public.zz_h04_t using (emp = 1);"
caso N09 distinto "sustitución de una política por otra con el mismo conteo" "drop policy p_ins on public.zz_h04_t; create policy p_otra on public.zz_h04_t for insert to authenticated with check (emp = 1);"
caso N10 distinto "RLS deshabilitada en la tabla" "alter table public.zz_h04_t disable row level security;"
caso N11 distinto "FORCE ROW LEVEL SECURITY habilitado" "alter table public.zz_h04_t force row level security;"
caso N12 distinto "USING reemplazado por otra expresión (política sustituida)" "drop policy p_del on public.zz_h04_t; create policy p_del on public.zz_h04_t for delete to authenticated using (true);"
caso N13 distinto "USING pasa de presente a NULL (política sustituida)" "drop policy p_upd2 on public.zz_h04_t; create policy p_upd2 on public.zz_h04_t for update to authenticated with check (emp = 1);"

echo "# C — controles sobre las políticas reales de las migraciones"
real="$(printf '%s;\n' "$SNAP" | lab_sql postgres -qtA 2>&1)"
np="$(printf '%s\n' "$real" | grep -c '^P|')"; npp="$(printf 'select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = %s::regnamespace;\n' "'public'" | lab_sql postgres -qtA)"
nt="$(printf '%s\n' "$real" | grep -c '^T|')"; ntt="$(printf "select count(*) from pg_class where relnamespace = 'public'::regnamespace and relkind in ('r','p');\n" | lab_sql postgres -qtA)"
chk "$([ "$np" = "$npp" ] && [ "$np" -gt 0 ] && echo ok)" "C01 la instantánea lista todas las políticas de public ($np de $npp)"
chk "$([ "$nt" = "$ntt" ] && [ "$nt" -gt 0 ] && echo ok)" "C02 la instantánea lista todas las tablas de public ($nt de $ntt)"
chk "$(printf '%s\n' "$real" | grep '^P|' | grep -vqE '\|using=(ABSENT|EXPR:[0-9a-f]{64})\|check=(ABSENT|EXPR:[0-9a-f]{64})$' && echo no || echo ok)" "C03 todas las líneas de política tienen using/check bien formados"
chk "$(printf '%s\n' "$real" | grep '^P|' | grep -q 'using=ABSENT' && printf '%s\n' "$real" | grep '^P|' | grep -q 'using=EXPR:' && echo ok)" "C04 las políticas reales incluyen casos con USING ausente y con USING presente"
R2="$(printf '%s;\n' "$SNAP" | lab_sql postgres -qtA 2>&1)"
chk "$([ "$real" = "$R2" ] && echo ok)" "C05 dos lecturas consecutivas de la instantánea son idénticas"

# E — de extremo a extremo con el mismo método que el arnés (archivos de texto comparados con cmp) sobre una política REAL
e2e() { # e2e <id> <igual|distinto> <descripción> <sql de mutación sobre la política real elegida>
  local id="$1" esp="$2" desc="$3" mut="$4" r ok=1
  r="$({ printf 'BEGIN;\n'; printf '%s;\n' "$SNAP"; printf "select '=====CORTE=====';\n"; printf '%s\n' "$mut"; printf '%s;\n' "$SNAP"; printf 'ROLLBACK;\n'; } | lab_sql postgres -qtA 2>&1)"
  printf '%s\n' "$r" | awk 'BEGIN{f="'"$OUT"'/e2e_'"$id"'_antes.txt"} /^=====CORTE=====$/{f="'"$OUT"'/e2e_'"$id"'_despues.txt"; next} {print > f}'
  if cmp -s "$OUT/e2e_${id}_antes.txt" "$OUT/e2e_${id}_despues.txt"; then res=igual; else res=distinto; fi
  [ -s "$OUT/e2e_${id}_antes.txt" ] && [ "$res" = "$esp" ] || ok=0
  chk "$([ $ok -eq 1 ] && echo ok)" "$id $desc → cmp: $res (esperado: $esp; $(wc -l < "$OUT/e2e_${id}_antes.txt") líneas)"
}
e2e E01 igual "política real sin cambios" "do \$d\$ begin null; end \$d\$;"
e2e E02 distinto "política real renombrada (mismo conteo)" "do \$d\$ declare v_n text; v_t text; begin select p.polname, p.polrelid::regclass::text into v_n, v_t from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = 'public'::regnamespace order by p.oid limit 1; execute format('alter policy %I on %s rename to %I', v_n, v_t, v_n || '_zz'); end \$d\$;"
e2e E03 distinto "política real con USING sustituido por true (mismo conteo)" "do \$d\$ declare v_n text; v_t text; begin select p.polname, p.polrelid::regclass::text into v_n, v_t from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = 'public'::regnamespace and p.polqual is not null order by p.oid limit 1; execute format('alter policy %I on %s using (true)', v_n, v_t); end \$d\$;"

# D — control permanente del DETECTOR DEGRADADO (H-04): la comprobación original sólo comparaba, por tabla, relrowsecurity,
# relforcerowsecurity y la CANTIDAD de políticas. Sobre una política REAL (dentro de BEGIN … ROLLBACK) se la altera conservando el
# conteo (cada medición con su propia mutación: ROLLBACK TO SAVEPOINT entre ambas): el detector antiguo debe informar igualdad (falso negativo reproducido) y la instantánea nueva, diferencia.
CONTEO_ANTIGUO="select c.oid::regclass || '|' || c.relrowsecurity || '|' || c.relforcerowsecurity || '|' || (select count(*) from pg_policy p where p.polrelid = c.oid) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p') order by 1"
SNAP_PREVIA="$(printf '%s;\n' "$SNAP" | lab_sql postgres -qtA 2>&1 | sha256sum | cut -d' ' -f1)"
MUT_REAL="do \$d\$ declare v_n text; v_t text; begin select p.polname, p.polrelid::regclass::text into v_n, v_t from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = 'public'::regnamespace and p.polqual is not null order by p.oid limit 1; execute format('alter policy %I on %s using (true)', v_n, v_t); raise notice 'D_MUTADA %.%', v_t, v_n; end \$d\$;"
{ printf 'BEGIN;\nSAVEPOINT zz_d_a;\n%s;\n' "$CONTEO_ANTIGUO"; printf "select '=====CORTE=====';\n"; printf '%s\n' "$MUT_REAL"; printf '%s;\n' "$CONTEO_ANTIGUO"; printf 'ROLLBACK TO SAVEPOINT zz_d_a;\n'; printf "select '=====CORTE2=====';\n"; printf '%s;\n' "$SNAP"; printf "select '=====CORTE3=====';\n"; printf '%s\n' "$MUT_REAL"; printf '%s;\n' "$SNAP"; printf 'ROLLBACK;\n'; } | lab_sql postgres -qtA > "$OUT/D_crudo.txt" 2> "$OUT/D_avisos.txt"
awk -v d="$OUT" 'BEGIN{f=d"/D_antiguo_antes.txt"} /^=====CORTE=====$/{f=d"/D_antiguo_despues.txt";next} /^=====CORTE2=====$/{f=d"/D_nuevo_base.txt";next} /^=====CORTE3=====$/{f=d"/D_nuevo_despues.txt";next} {print > f}' "$OUT/D_crudo.txt"
chk "$(grep -q '^NOTICE:  D_MUTADA ' "$OUT/D_avisos.txt" && [ -s "$OUT/D_antiguo_antes.txt" ] && echo ok)" "D01 la mutación real se aplicó ($(grep -m1 -o 'D_MUTADA .*' "$OUT/D_avisos.txt")) sobre $(wc -l < "$OUT/D_antiguo_antes.txt") tablas"
chk "$(cmp -s "$OUT/D_antiguo_antes.txt" "$OUT/D_antiguo_despues.txt" && echo ok)" "D02 detector ANTIGUO (conteo): antes y después IGUALES → falso negativo reproducido"
chk "$(! cmp -s "$OUT/D_nuevo_base.txt" "$OUT/D_nuevo_despues.txt" && [ -s "$OUT/D_nuevo_base.txt" ] && echo ok)" "D03 instantánea NUEVA sobre la misma mutación: DIFERENTE → detectada"
SNAP_POSTERIOR="$(printf '%s;\n' "$SNAP" | lab_sql postgres -qtA 2>&1 | sha256sum | cut -d' ' -f1)"
chk "$([ "$SNAP_PREVIA" = "$SNAP_POSTERIOR" ] && echo ok)" "D04 ROLLBACK: la instantánea completa de public es idéntica antes y después de D (sin residuos)"

# R01: sin residuos (todo corrió en BEGIN … ROLLBACK)
RES="$(printf "select (to_regclass('public.zz_h04_t') is null)::text || '|' || (select count(*) from pg_policy where polname like 'p\\_%%')::text || '|' || (select count(*) from pg_class where relname like 'zz\\_h04%%')::text;\n" | lab_sql postgres -qtA)"
chk "$([ "$RES" = "true|0|0" ] && echo ok)" "R01 sin residuos tras los casos: tabla de prueba ausente, 0 políticas y 0 relaciones zz_h04 ($RES)"
echo "--- casos: $TOTAL, fallas: $FALLAS"
[ "$FALLAS" -eq 0 ]
