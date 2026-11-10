#!/usr/bin/env bash
# E-PL1 (ADR-001 §18.4.2.2) — funciones comunes del procedimiento de evidencia local.
# Se "source"-ea; no se ejecuta solo. Requiere REPO (raíz del repositorio) definido.
#
# Laboratorio: UN contenedor supabase/postgres 17.11 descartable (imagen fijada por
# digest, que debe estar presente: NO se descarga), SIN red, sin puertos y sin montajes.
# Toda la SQL entra por `docker exec` dentro de ese contenedor: ninguna función de este
# archivo acepta un destino de conexión. No se conecta a staging ni a producción.

LAB_IMG_DIGEST="sha256:b15d862126dd2dac02da524696ccfde2dcce2ceaee0a58973b2727befe492706"  # supabase/postgres 17.11.0.004
LAB_IMG="public.ecr.aws/supabase/postgres@${LAB_IMG_DIGEST}"
LAB_PREFIJO="epl1lab_"
LAB_NUEVA_MIGRACION="20261111120200_rpc_listar_vendedores_jornada.sql"

# Rutas versionadas que forman el paquete de E-PL1 (se hashean ANTES de ejecutar).
VINCULO_RUTAS=(supabase/migrations supabase/tests supabase/laboratorio/e-pl1
               docs/decisions/001-rpc-privilegiadas.md docs/progress-log.md AGENTS.md)

# dir_evidencia_nuevo <ruta>: directorio NUEVO (modo 700), absoluto, fuera del repositorio.
dir_evidencia_nuevo() {
  local ruta="$1" padre
  case "$ruta" in /*) ;; *) echo "abortado: la ruta de evidencia debe ser absoluta" >&2; return 2 ;; esac
  case "$ruta" in *..*|*$'\n'*) echo "abortado: ruta de evidencia con caracteres no admitidos" >&2; return 2 ;; esac
  [ ! -e "$ruta" ] && [ ! -L "$ruta" ] || { echo "abortado: la evidencia exige un directorio NUEVO: $ruta" >&2; return 2; }
  padre="$(dirname -- "$ruta")"; [ -d "$padre" ] || { echo "abortado: no existe el padre: $padre" >&2; return 2; }
  case "$(realpath -m -- "$ruta")/" in "$(realpath -- "$REPO")"/*) echo "abortado: la evidencia debe quedar fuera del repositorio" >&2; return 2 ;; esac
  mkdir -m 700 "$ruta"
}

# vinculo_git <dir_evidencia>: registra commit, árbol, estado y SHA-256 de los archivos
# ANTES de ejecutar nada. Modo estricto (VINCULO=ESTRICTO) sólo si se dan
# GIT_COMMIT_ESPERADO y GIT_ARBOL_ESPERADO, el HEAD y el árbol coinciden y el árbol de
# trabajo está limpio (incluidos los archivos sin seguimiento). En cualquier otro caso la
# evidencia queda marcada NO_VINCULADA: no se afirma que corresponda a un commit.
vinculo_git() {
  local ev="$1" f="$1/vinculo_git.txt" head tree sucio estricto=no
  head="$(git -C "$REPO" rev-parse HEAD)"; tree="$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
  sucio="$(git -C "$REPO" status --porcelain --untracked-files=all | wc -l)"
  if [ -n "${GIT_COMMIT_ESPERADO:-}" ] || [ -n "${GIT_ARBOL_ESPERADO:-}" ]; then
    [ -n "${GIT_COMMIT_ESPERADO:-}" ] && [ -n "${GIT_ARBOL_ESPERADO:-}" ] || { echo "abortado: el modo estricto exige GIT_COMMIT_ESPERADO y GIT_ARBOL_ESPERADO" >&2; return 5; }
    [[ "$GIT_COMMIT_ESPERADO" =~ ^[0-9a-f]{40}$ && "$GIT_ARBOL_ESPERADO" =~ ^[0-9a-f]{40}$ ]] || { echo "abortado: identidad esperada con formato inválido" >&2; return 5; }
    estricto=si
  fi
  {
    echo "fecha_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "rama=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
    echo "commit_actual=$head"; echo "arbol_actual=$tree"
    echo "commit_esperado=${GIT_COMMIT_ESPERADO:-}"; echo "arbol_esperado=${GIT_ARBOL_ESPERADO:-}"
    echo "archivos_con_cambios_o_sin_seguimiento=$sucio"
    git -C "$REPO" status --porcelain --untracked-files=all | sed 's/^/  /'
    echo "--- sha256 de los archivos del paquete (árbol de trabajo), antes de ejecutar"
    ( cd "$REPO" && git ls-files -co --exclude-standard -- "${VINCULO_RUTAS[@]}" | LC_ALL=C sort | while IFS= read -r p; do sha256sum -- "$p"; done )
  } > "$f"
  if [ "$estricto" = si ]; then
    [ "$head" = "$GIT_COMMIT_ESPERADO" ] || { echo "abortado: HEAD ($head) distinto del commit esperado" >&2; echo "VINCULO=ABORTADO" >> "$f"; return 5; }
    [ "$tree" = "$GIT_ARBOL_ESPERADO" ] || { echo "abortado: árbol ($tree) distinto del esperado" >&2; echo "VINCULO=ABORTADO" >> "$f"; return 5; }
    [ "$sucio" -eq 0 ] || { echo "abortado: hay cambios sin commitear; no se afirma evidencia vinculada" >&2; echo "VINCULO=ABORTADO" >> "$f"; return 5; }
    echo "VINCULO=ESTRICTO" >> "$f"
    echo "VINCULADA al commit $head (árbol $tree), árbol de trabajo limpio" > "$ev/ESTADO_DE_LA_EVIDENCIA.txt"
  else
    echo "VINCULO=NO_VINCULADA" >> "$f"
    echo "NO VINCULADA a ningún commit (corrida exploratoria${sucio:+; archivos con cambios o sin seguimiento: $sucio}). No citar como evidencia del commit $head." > "$ev/ESTADO_DE_LA_EVIDENCIA.txt"
  fi
}

# lab_up: crea y verifica el contenedor aislado. Define LAB_CONTAINER y LAB_CID.
lab_up() {
  command -v docker >/dev/null || { echo "abortado: docker no disponible" >&2; return 2; }
  docker image inspect "$LAB_IMG" >/dev/null 2>&1 || { echo "abortado: imagen $LAB_IMG no presente (no se descarga)" >&2; return 2; }
  LAB_NONCE="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"; LAB_CONTAINER="${LAB_PREFIJO}${LAB_NONCE:0:12}"
  LAB_CID="$(docker run -d --name "$LAB_CONTAINER" --label "e-pl1.nonce=$LAB_NONCE" --network none \
              -e POSTGRES_PASSWORD="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')" "$LAB_IMG")" || return 3
  local net ports mounts
  net="$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$LAB_CONTAINER")"
  ports="$(docker inspect --format '{{json .HostConfig.PortBindings}}' "$LAB_CONTAINER")"
  mounts="$(docker inspect --format '{{json .Mounts}}' "$LAB_CONTAINER")"
  [ "$net" = none ] && { [ "$ports" = "{}" ] || [ "$ports" = null ]; } && [ "$mounts" = "[]" ] || { echo "abortado: el contenedor no está aislado" >&2; docker rm -f -v "$LAB_CID" >/dev/null 2>&1; return 3; }
  local i; for i in $(seq 1 90); do docker exec "$LAB_CONTAINER" pg_isready -U postgres -h localhost >/dev/null 2>&1 && break; sleep 2; done; sleep 3
}
lab_down() { [ -n "${LAB_CID:-}" ] && docker rm -f -v "$LAB_CID" >/dev/null 2>&1; LAB_CID=""; }

# lab_sql <usuario> [args de psql]: lee SQL de stdin y lo ejecuta dentro del contenedor.
lab_sql() { docker exec -i "$LAB_CONTAINER" psql -X -U "$1" -h localhost -d postgres -v ON_ERROR_STOP=1 "${@:2}"; }

# lab_migraciones <dir_logs> [excluir]: aplica supabase/migrations en orden como postgres.
# Guarda el log ÍNTEGRO (entrada y salida, stdout+stderr) y el código de salida de cada una.
lab_migraciones() {
  local logs="$1" excluir="${2:-}" f b
  mkdir -p "$logs"; : > "$logs/_migraciones.sha256"
  for f in "$REPO"/supabase/migrations/*.sql; do
    b="$(basename "$f")"
    [ -n "$excluir" ] && [ "$b" = "$excluir" ] && continue
    lab_sql postgres -a < "$f" > "$logs/$b.log" 2>&1; echo "rc=$?" > "$logs/$b.rc"
    echo "$(sha256sum < "$f" | cut -d' ' -f1)  $b" >> "$logs/_migraciones.sha256"
    grep -q '^rc=0$' "$logs/$b.rc" || { echo "FALLA la migración $b (ver $logs/$b.log)" >&2; return 4; }
  done
}

# Estado observable para comprobar que una migración fallida no dejó nada.
lab_inspeccion_sql() { cat <<'SQL'
select 'INSPECCION|vista_columnas='||(select count(*) from pg_attribute where attrelid='privado.perfiles_empresa_gestion'::regclass and attnum>0 and not attisdropped)
  ||'|grant_nombre_lector='||has_column_privilege('lector_perfiles_rpc','public.perfiles','nombre','SELECT')
  ||'|create_lector_privado='||has_schema_privilege('lector_perfiles_rpc','privado','CREATE')
  ||'|create_propietario_privado='||has_schema_privilege('propietario_rpc','privado','CREATE')
  ||'|fn_privada='||(to_regprocedure('privado.listar_vendedores_jornada()') is not null)
  ||'|fn_fachada='||(to_regprocedure('public.listar_vendedores_jornada()') is not null);
SQL
}
