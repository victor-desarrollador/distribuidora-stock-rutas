#!/usr/bin/env bash
# Corredor del laboratorio Docker M-01/B-01 + O-4 presente. Crea UN contenedor
# descartable de la imagen supabase/postgres 17.11.0.004 (fijada por digest, que
# debe estar ya presente: NO descarga), sin red, sin puertos, sin montajes y con
# nombre exclusivo; aplica las migraciones del repo; ejecuta probar_m01_b01.sh y
# probar_o4_presente.sh; guarda la evidencia en <dir_salida> (fuera del repo) y
# elimina únicamente SU contenedor (por ID).
# Uso: probar_o4_docker.sh <dir_salida_vacío_o_inexistente>
set -uo pipefail
[ "$#" -eq 1 ] || { echo "uso: $0 <dir_salida>" >&2; exit 2; }
OUT="$1"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../.." && pwd)"
case "$(cd "$(dirname "$OUT")" 2>/dev/null && pwd)/$(basename "$OUT")" in "$REPO"/*) echo "abortado: la evidencia debe quedar fuera del repositorio" >&2; exit 2 ;; esac
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGPASSWORD PGSERVICE PGSERVICEFILE DATABASE_URL SUPABASE_DB_URL || true
. "$DIR/lab_comun.sh"
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then echo "abortado: $OUT no está vacío" >&2; exit 2; fi
mkdir -p "$OUT"
command -v docker >/dev/null || { echo "abortado: docker no disponible" >&2; exit 2; }
docker image inspect "$LAB_IMG" >/dev/null 2>&1 || { echo "abortado: imagen $LAB_IMG no presente (no se descarga)" >&2; exit 2; }

export LAB_NONCE="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
export LAB_CONTAINER="${LAB_PREFIJO}${LAB_NONCE:0:12}"
CID=""
limpiar() { [ -n "$CID" ] && docker rm -f -v "$CID" > "$OUT/contenedor_eliminado.txt" 2>&1; }
trap limpiar EXIT

# Inventario previo (sólo lectura).
{ docker ps -a --format '{{.ID}} {{.Names}} {{.Status}}'; echo '--- redes'; docker network ls --format '{{.Name}}'; echo '--- volúmenes'; docker volume ls --format '{{.Name}}'; } > "$OUT/docker_antes.txt"

CID="$(docker run -d --name "$LAB_CONTAINER" --label "t3.o4m01.nonce=$LAB_NONCE" --network none \
        -e POSTGRES_PASSWORD="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')" "$LAB_IMG")" || { echo "abortado: docker run" >&2; exit 3; }
lab_verificar
{ echo "contenedor=$LAB_CONTAINER id=$CID"; echo "imagen=$LAB_IMG"; docker inspect --format 'imagen_id={{.Image}} red={{.HostConfig.NetworkMode}} puertos={{json .HostConfig.PortBindings}} montajes={{json .Mounts}}' "$LAB_CONTAINER"; } | tee "$OUT/aislamiento.txt"
for i in $(seq 1 90); do docker exec "$LAB_CONTAINER" pg_isready -U postgres -h localhost >/dev/null 2>&1 && break; sleep 2; done
sleep 3

: > "$OUT/migraciones.txt"
for f in "$REPO"/supabase/migrations/*.sql; do
  lab_sql postgres -q < "$f" > /dev/null 2> "$OUT/mig_$(basename "$f").stderr" || { echo "abortado: migración $(basename "$f")" >&2; exit 4; }
  echo "$(sha256sum "$f" | cut -d' ' -f1) $(basename "$f")" >> "$OUT/migraciones.txt"
done
lab_sql supabase_admin -qtA > "$OUT/identidad.txt" 2>&1 <<SQL || { echo "abortado: identidad" >&2; exit 5; }
create schema zz_laboratorio;
create table zz_laboratorio.identidad (nonce text not null, sysid text not null);
insert into zz_laboratorio.identidad values ('$LAB_NONCE', (select system_identifier::text from pg_control_system()));
select 'IDENTIDAD|OK';
SQL
lab_identidad
{ sha256sum "$REPO/supabase/scripts/validar_topologia_propietario_rpc.sql" "$REPO/supabase/migrations/20261110120000_o4_pgtemp_remediacion.sql" "$DIR"/*.sh "$DIR"/*.sql "$DIR/cuerpo_original_325ae266.txt"; } > "$OUT/hashes_probados.txt"
echo "select version(), (select rolsuper from pg_roles where rolname='postgres') as postgres_super;" | lab_sql supabase_admin -qtA > "$OUT/version.txt"

RC=0
bash "$DIR/probar_m01_b01.sh"     > "$OUT/A_m01_b01.txt" 2>&1;      R1=$?; echo "A_m01_b01 rc=$R1" | tee -a "$OUT/codigos.txt"
bash "$DIR/probar_o4_presente.sh" > "$OUT/BC_o4_presente.txt" 2>&1;  R2=$?; echo "BC_o4_presente rc=$R2" | tee -a "$OUT/codigos.txt"
cat "$OUT/A_m01_b01.txt" "$OUT/BC_o4_presente.txt"
lab_identidad
{ docker ps -a --format '{{.ID}} {{.Names}} {{.Status}}'; echo '--- redes'; docker network ls --format '{{.Name}}'; echo '--- volúmenes'; docker volume ls --format '{{.Name}}'; } > "$OUT/docker_despues_con_lab.txt"
[ "$R1" -eq 0 ] && [ "$R2" -eq 0 ]
