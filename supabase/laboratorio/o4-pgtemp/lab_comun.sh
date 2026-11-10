#!/usr/bin/env bash
# Funciones comunes de los arneses M-01/B-01 y O-4 presente (se "source"-ea; no se ejecuta).
# Todo el SQL entra por `docker exec` dentro de UN contenedor creado por
# probar_o4_docker.sh: sin red, sin puertos, sin montajes, con etiqueta de nonce,
# imagen fijada por digest y nombre exclusivo. Nunca acepta un destino de conexión.

LAB_IMG_DIGEST="sha256:b15d862126dd2dac02da524696ccfde2dcce2ceaee0a58973b2727befe492706"  # supabase/postgres 17.11.0.004
LAB_IMG="public.ecr.aws/supabase/postgres@${LAB_IMG_DIGEST}"
LAB_PREFIJO="o4m01lab_"

# lab_verificar: aborta (exit 3) si el contenedor LAB_CONTAINER no es el laboratorio.
lab_verificar() {
  : "${LAB_CONTAINER:?falta LAB_CONTAINER}" "${LAB_NONCE:?falta LAB_NONCE}"
  case "$LAB_CONTAINER" in ${LAB_PREFIJO}*) ;; *) echo "abortado: nombre de contenedor ajeno al laboratorio" >&2; exit 3 ;; esac
  local net ports mounts nets label img
  net="$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$LAB_CONTAINER" 2>/dev/null)" || { echo "abortado: contenedor inexistente" >&2; exit 3; }
  ports="$(docker inspect --format '{{json .HostConfig.PortBindings}}' "$LAB_CONTAINER")"
  mounts="$(docker inspect --format '{{json .Mounts}}' "$LAB_CONTAINER")"
  nets="$(docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$LAB_CONTAINER")"
  label="$(docker inspect --format '{{index .Config.Labels "t3.o4m01.nonce"}}' "$LAB_CONTAINER")"
  img="$(docker inspect --format '{{.Image}}' "$LAB_CONTAINER")"
  [ "$net" = "none" ] && [ "$nets" = "none " ] || { echo "abortado: red $net/$nets" >&2; exit 3; }
  [ "$ports" = "{}" ] || [ "$ports" = "null" ] || { echo "abortado: puertos $ports" >&2; exit 3; }
  [ "$mounts" = "[]" ] || { echo "abortado: montajes $mounts" >&2; exit 3; }
  [ "$label" = "$LAB_NONCE" ] || { echo "abortado: nonce distinto" >&2; exit 3; }
  [ "$img" = "$LAB_IMG_DIGEST" ] || { echo "abortado: imagen $img" >&2; exit 3; }
}

# lab_sql <usuario>: lee SQL de stdin y lo ejecuta en el contenedor (ON_ERROR_STOP).
lab_sql() {
  docker exec -i "$LAB_CONTAINER" psql -X -U "$1" -h localhost -d postgres -v ON_ERROR_STOP=1 "${@:2}"
}

# lab_identidad: exige la identidad registrada dentro de la base (nonce) y que NO haya O-4
# cuando se pide con $1 = sin_o4.
lab_identidad() {
  local r
  r="$(printf "select exists (select 1 from zz_laboratorio.identidad where nonce = '%s') and current_setting('server_version_num')::int/10000 = 17;\n" "$LAB_NONCE" | lab_sql supabase_admin -qtA)" || r=""
  [ "$r" = "t" ] || { echo "abortado: la base no es el laboratorio verificado" >&2; exit 3; }
}
