#!/usr/bin/env bash
# Funciones comunes del inventario Q0–Q6 para la integridad de la evidencia (se "source"-ea; no se ejecuta):
#   dir_evidencia_seguro <ruta>   crea un directorio NUEVO, 700, fuera del repositorio, sin enlaces simbólicos
#   vinculo_git <dir_evidencia>   registra commit, árbol y hashes ANTES de ejecutar y, si hay identidad
#                                 esperada, falla ante identidad distinta o código modificado
# Requiere REPO (raíz del repositorio) definido por quien lo incluye.

# Rutas versionadas que forman el paquete ejecutable del inventario.
VINCULO_RUTAS=(supabase/laboratorio/o4-pgtemp supabase/scripts/validar_topologia_propietario_rpc.sql supabase/migrations/20261110120000_o4_pgtemp_remediacion.sql)

dir_evidencia_seguro() {
  local ruta="$1" padre real_s real_m repo_real
  [ -n "$ruta" ] || { echo "abortado: ruta de evidencia vacía" >&2; return 2; }
  case "$ruta" in /*) ;; *) echo "abortado: la ruta de evidencia debe ser absoluta" >&2; return 2 ;; esac
  case "$ruta" in *$'\n'*|*..*) echo "abortado: ruta de evidencia con caracteres no admitidos" >&2; return 2 ;; esac
  [ ! -e "$ruta" ] && [ ! -L "$ruta" ] || { echo "abortado: la evidencia exige un directorio NUEVO (ya existe o es un enlace): $ruta" >&2; return 2; }
  padre="$(dirname -- "$ruta")"
  [ -d "$padre" ] || { echo "abortado: el directorio padre no existe: $padre" >&2; return 2; }
  # Ningún componente puede ser un enlace simbólico: la ruta resuelta debe ser igual a la lexical.
  real_s="$(realpath -m -s -- "$ruta")"; real_m="$(realpath -m -- "$ruta")"
  [ "$real_s" = "$real_m" ] || { echo "abortado: la ruta de evidencia contiene enlaces simbólicos" >&2; return 2; }
  repo_real="$(realpath -- "$REPO")"
  case "$real_m/" in "$repo_real"/*) echo "abortado: la evidencia debe quedar fuera del repositorio" >&2; return 2 ;; esac
  [ -O "$padre" ] || { echo "abortado: el directorio padre no pertenece al usuario actual" >&2; return 2; }
  local modo gid_p gid_u miembros
  modo="$(stat -c %a "$padre")"
  [ $(( 8#$modo & 8#002 )) -eq 0 ] || { echo "abortado: el directorio padre es escribible por cualquiera" >&2; return 2; }
  if [ $(( 8#$modo & 8#020 )) -ne 0 ]; then
    gid_p="$(stat -c %g "$padre")"; gid_u="$(id -g)"
    miembros="$(getent group "$gid_p" | cut -d: -f4)"
    { [ "$gid_p" = "$gid_u" ] && [ -z "$miembros" ]; } || { echo "abortado: el directorio padre es escribible por un grupo compartido" >&2; return 2; }
  fi
  ( umask 077; mkdir -m 700 -- "$ruta" ) || { echo "abortado: no se pudo crear el directorio de evidencia" >&2; return 2; }
  [ "$(realpath -- "$ruta")" = "$real_s" ] || { echo "abortado: la ruta cambió durante la creación" >&2; return 2; }
  return 0
}

# vinculo_git <dir_evidencia>: se llama ANTES de ejecutar cualquier consulta o prueba.
# Variables: GIT_COMMIT_ESPERADO, GIT_ARBOL_ESPERADO (ambas obligatorias para el modo estricto).
vinculo_git() {
  local ev="$1" head tree sucio f h modo
  command -v git >/dev/null || { echo "abortado: git no disponible" >&2; return 5; }
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "abortado: $REPO no es un repositorio git" >&2; return 5; }
  head="$(git -C "$REPO" rev-parse HEAD)"; tree="$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
  sucio="$(git -C "$REPO" status --porcelain --untracked-files=all -- "${VINCULO_RUTAS[@]}")"
  if [ -n "${GIT_COMMIT_ESPERADO:-}" ] || [ -n "${GIT_ARBOL_ESPERADO:-}" ]; then
    [ -n "${GIT_COMMIT_ESPERADO:-}" ] && [ -n "${GIT_ARBOL_ESPERADO:-}" ] || { echo "abortado: modo estricto exige GIT_COMMIT_ESPERADO y GIT_ARBOL_ESPERADO" >&2; return 5; }
    [[ "$GIT_COMMIT_ESPERADO" =~ ^[0-9a-f]{40}$ && "$GIT_ARBOL_ESPERADO" =~ ^[0-9a-f]{40}$ ]] || { echo "abortado: identidad git esperada con formato inválido" >&2; return 5; }
    modo=ESTRICTO
  else
    modo=NO_VINCULADA_A_COMMIT
  fi
  {
    echo "VINCULO=$modo"
    echo "commit_actual=$head"; echo "arbol_actual=$tree"
    echo "commit_esperado=${GIT_COMMIT_ESPERADO:-}"; echo "arbol_esperado=${GIT_ARBOL_ESPERADO:-}"
    echo "estado_git_rutas_del_paquete=$([ -z "$sucio" ] && echo limpio || echo MODIFICADO)"
    [ -z "$sucio" ] || printf '%s\n' "$sucio" | sed 's/^/  /'
    echo "--- sha256 de los archivos del paquete (árbol de trabajo) y de su blob en HEAD"
    for f in $(git -C "$REPO" ls-files -- "${VINCULO_RUTAS[@]}") $(git -C "$REPO" ls-files --others --exclude-standard -- "${VINCULO_RUTAS[@]}"); do
      h="$(sha256sum "$REPO/$f" | cut -d' ' -f1)"
      echo "$h  $f  blob_head=$(git -C "$REPO" show "HEAD:$f" 2>/dev/null | sha256sum | cut -d' ' -f1)"
    done
    echo "psql=$(psql --version 2>&1 | head -1)"
  } > "$ev/vinculo_git.txt"
  if [ "$modo" = ESTRICTO ]; then
    [ "$head" = "$GIT_COMMIT_ESPERADO" ] || { echo "abortado: HEAD ($head) distinto del commit esperado" >&2; return 5; }
    [ "$tree" = "$GIT_ARBOL_ESPERADO" ] || { echo "abortado: árbol ($tree) distinto del esperado" >&2; return 5; }
    [ -z "$sucio" ] || { echo "abortado: hay cambios sin commitear en el paquete ejecutable" >&2; return 5; }
    for f in $(git -C "$REPO" ls-files -- "${VINCULO_RUTAS[@]}"); do
      [ "$(sha256sum "$REPO/$f" | cut -d' ' -f1)" = "$(git -C "$REPO" show "HEAD:$f" | sha256sum | cut -d' ' -f1)" ] || { echo "abortado: $f difiere de su blob en HEAD" >&2; return 5; }
    done
  fi
  return 0
}
