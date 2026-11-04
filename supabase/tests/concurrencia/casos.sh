# shellcheck shell=bash
# =============================================================================
# Arnés de concurrencia de jornadas — definición de los casos (ADR-001 §18.4.9
# y §18.4.11). Lo carga arnes.sh; no se ejecuta solo.
#
# Alcance T3 (decisión humana del 01/11/2026): sólo las RPC existentes,
# `abrir_jornada` (T1) y `reasignar_vendedor` (T2), y sólo los escenarios que la
# verificación de Fase A en PostgreSQL 17 clasificó como demostrables:
#
#   AUTO        autoverificación de sensibilidad (40P01 determinista, orden ingenuo)
#   I10-R       reasignar_vendedor, misma clave y mismo payload (prueba el paso 8a)
#   I10-A       abrir_jornada, misma clave y mismo payload (no distingue 8a del paso 9)
#   I11-R       reasignar_vendedor, misma clave y payload distinto (conflicto en 8a)
#   K1..K4      I-1 intercambio, I-1b cadena, I-2 apertura vs reasignación (vigente / nuevo)
#   K9-R        vigente cambiado por otra operación con distinta clave (paso 8b) y reintento
#   K10-a..e    aperturas concurrentes
#   K8-CLAVE    (parcial) misma clave en dos jornadas: ON CONFLICT del paso 9
#   K8-BAJA-a/b (parcial) baja de camión durante la espera / después de la apertura
#   S-ESP-RR/RA sin esperas espurias entre operaciones con recursos disjuntos
#               (no es el grupo S de seguridad de §18.4.9)
#   O-R1..R4    reasignar_vendedor: advisory concedidos/esperados (O3), backend_xid
#               NULL mientras espera (O2′) y conjunto retenido al volver (O5)
#   O-A1..A2    abrir_jornada: camión antes que vendedor (O4), O2′ y O5
#
# Fuera de T3 (documentado en docs/progress-log.md): K5–K7, K11, K12 (requieren
# corregir_jornada, registrar_carga, registrar_descarga y confirmar_salida),
# el resto de K8, I10/I11 de las otras cuatro RPC, O1 y las series L (el modo de
# bloqueo de fila no es observable), 5a, 5b y 5d.
#
# Límites de lo que demuestran (no se declara cubierto nada más):
#   - O2′ detecta cualquier bloqueo de fila o escritura previos al advisory que
#     la sesión está esperando; no distingue el modo, ni detecta un FOR UPDATE
#     que no devuelve filas o que espera otra fila.
#   - En abrir_jornada (I10-A, K10-d) el resultado no distingue el paso 8a del
#     ON CONFLICT del paso 9: sólo prueba que nadie resolvió el replay en el paso 5.
#   - K8-CLAVE prueba el paso 9 porque la segunda sesión queda esperando, con su
#     reserva en curso, a la transacción abierta de la primera (5c).
# =============================================================================

# Datos iniciales (los mismos de la Fase A), cargados como `postgres` en la plantilla.
EMPRESA_A='aaaaaaaa-2100-4000-8000-000000000000'
EMPRESA_B='bbbbbbbb-2100-4000-8000-000000000000'
u() { printf 'aaaaaaaa-2100-4000-8000-%012d' "$1"; }
DUENO=$(u 1)
V3=$(u 3) V6=$(u 6) V7=$(u 7) V9=$(u 9)    # vendedores activos; orden de uuid V3 < V6 < V7 < V9
CAM1='aaaaaaaa-2100-4000-8000-0000000000c1'
CAM2='aaaaaaaa-2100-4000-8000-0000000000c2'
CAM3='aaaaaaaa-2100-4000-8000-0000000000c3'
ACTOR=$DUENO

fixtures_sql() {
  cat <<EOF
insert into public.empresas (id, nombre) values
  ('$EMPRESA_A', 'Empresa A (arnés)'), ('$EMPRESA_B', 'Empresa B (arnés)');
insert into auth.users (id) values
  ('$(u 1)'), ('$(u 2)'), ('$(u 3)'), ('$(u 6)'), ('$(u 7)'), ('$(u 9)'),
  ('bbbbbbbb-2100-4000-8000-000000000001');
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('$(u 1)', '$EMPRESA_A', 'jr.a1', 'A1', 'dueno', true),
  ('$(u 2)', '$EMPRESA_A', 'jr.a2', 'A2', 'encargado', true),
  ('$(u 3)', '$EMPRESA_A', 'jr.a3', 'A3', 'vendedor_piloto', true),
  ('$(u 6)', '$EMPRESA_A', 'jr.a6', 'A6', 'vendedor_piloto', true),
  ('$(u 7)', '$EMPRESA_A', 'jr.a7', 'A7', 'vendedor_piloto', true),
  ('$(u 9)', '$EMPRESA_A', 'jr.a9', 'A9', 'vendedor_piloto', true),
  ('bbbbbbbb-2100-4000-8000-000000000001', '$EMPRESA_B', 'jr.b1', 'B1', 'dueno', true);
insert into public.camiones (id, empresa_id, patente, nombre, creado_por) values
  ('$CAM1', '$EMPRESA_A', 'JR-01', 'Camión A1', '$(u 1)'),
  ('$CAM2', '$EMPRESA_A', 'JR-02', 'Camión A2', '$(u 1)'),
  ('$CAM3', '$EMPRESA_A', 'JR-03', 'Camión A3', '$(u 1)');
EOF
}

CASOS=(AUTO I10-R I10-A I11-R K1 K2 K3 K4 K9-R K10-a K10-b K10-c K10-d K10-e
       K8-CLAVE K8-BAJA-a K8-BAJA-b S-ESP-RR S-ESP-RA
       O-R1 O-R2 O-R3 O-R4 O-A1 O-A2)

# -----------------------------------------------------------------------------
# Utilidades de los casos
# -----------------------------------------------------------------------------
NCLAVE=0
CLAVE=""
nueva_clave() { NCLAVE=$(( NCLAVE + 1 )); printf -v CLAVE 'fa000000-0000-4000-8000-%012x' "$NCLAVE"; }

# Jornada confirmada como dato inicial del caso, con la RPC real y el dueño.
preparar_jornada() {   # clave camion dias vendedor -> uuid de la jornada
  ins _psql -v ON_ERROR_STOP=1 -U postgres -d "$BASE" -f - <<EOF | tail -1
begin;
select set_config('request.jwt.claims', '{"sub":"$ACTOR","role":"authenticated"}', true) is not null;
set local role authenticated;
select public.abrir_jornada('$1', '$2', current_date + $3, '$4');
commit;
EOF
}
jornada() {   # variable camion dias vendedor
  local id
  nueva_clave
  id=$(ins preparar_jornada "$CLAVE" "$2" "$3" "$4") && [[ $id =~ ^[0-9a-f-]{36}$ ]] \
    || { MOTIVO="no se preparó la jornada ($2, +$3, $4): $id"; return 1; }
  printf -v "$1" '%s' "$id"
}

reasignar() { printf "public.reasignar_vendedor('%s', '%s', '%s')" "$1" "$2" "$3"; }
abrir()     { printf "public.abrir_jornada('%s', '%s', current_date + %s, '%s')" "$1" "$2" "$3" "$4"; }
baja_camion() { printf "public.cambiar_estado_camion('%s', false)" "$1"; }
mismo_uuid() {
  local a b
  a=$(uuid_de "$RES_T1"); b=$(uuid_de "$RES_T2")
  [[ -n $a && $a == "$b" ]]
}

# Invariantes: pares descripción/condición. Separa dos resultados:
#   - instrumental, por el código de salida: 0 = la consulta corrió y su salida
#     se pudo interpretar; 2 = error SQL o de conexión (INV_ERROR_SQL), salida
#     no interpretable (INV_ERROR_SALIDA) o uso inválido (INV_ERROR_USO);
#   - lógico, por el testigo: INV_OK si todas las condiciones se cumplen;
#     «INV_FALLA: <descripciones>» si alguna no.
# El testigo sólo vale con rc 0; cerrar() decide por el testigo (T3-C1, H-01) y
# quien la llama usa ins, que anota el rc 2. INV_FALLA se acepta sólo si la
# salida es una única línea formada por descripciones pasadas, en orden y
# separadas por «; » (clasificador estricto, decisión A-1).
invariantes() {
  local sql="select concat_ws('; '" d c out rc p i=0 sep=$'\x1f'
  local -a descs=() partes=()
  (( $# >= 2 && $# % 2 == 0 )) || { printf 'INV_ERROR_USO: %s argumentos' "$#"; return 2; }
  while (( $# >= 2 )); do
    d=$1; c=$2; shift 2
    [[ -n $d && $d != *';'* && $d != *$'\n'* ]] || { printf 'INV_ERROR_USO: descripción inválida [%s]' "$d"; return 2; }
    descs+=("$d")
    sql+=", case when not coalesce(($c), false) then '${d//\'/\'\'}' end"
  done
  sql+=")"
  # invariantes clasifica su propio rc: llama a _psql directamente (excepción de LINT).
  out=$(_psql -v ON_ERROR_STOP=1 -U postgres -d "$BASE" -c "select case when f = '' then 'INV_OK' else f end from ($sql) as s(f)" 2>&1)
  rc=$?
  if (( rc != 0 )); then
    printf 'INV_ERROR_SQL(rc=%s): %s' "$rc" "${out//$'\n'/ }"
    return 2
  fi
  if [[ $out == INV_OK ]]; then
    printf 'INV_OK'
    return 0
  fi
  [[ -n $out && $out != *$'\n'* ]] || { printf 'INV_ERROR_SALIDA: %s' "${out:-vacía}"; return 2; }
  IFS=$sep read -r -a partes <<<"${out//; /$sep}"
  for p in "${partes[@]}"; do
    while (( i < ${#descs[@]} )) && [[ ${descs[i]} != "$p" ]]; do i=$(( i + 1 )); done
    (( i < ${#descs[@]} )) || { printf 'INV_ERROR_SALIDA: %s' "$out"; return 2; }
    i=$(( i + 1 ))
  done
  printf 'INV_FALLA: %s' "$out"
  return 0
}
# Uno o más testigos INV_OK concatenados, y nada más (cadena vacía = falla).
inv_ok() { [[ $1 =~ ^(INV_OK)+$ ]]; }
INV_IJ1="not exists (select 1 from public.jornadas group by empresa_id, camion_id, fecha having count(*) > 1)
 and not exists (select 1 from public.jornadas group by empresa_id, vendedor_id, fecha having count(*) > 1)
 and not exists (select 1 from public.jornadas where estado <> 'cerrada' group by empresa_id, camion_id having count(*) > 1)"
INV_HUERFANAS="not exists (select 1 from public.operaciones o where o.tipo = 'reasignacion_vendedor'
   and not exists (select 1 from public.reasignaciones_vendedor h where h.operacion_id = o.id))
 and not exists (select 1 from public.operaciones o where o.tipo = 'apertura_jornada'
   and not exists (select 1 from public.jornadas j where j.operacion_apertura_id = o.id))"
n_reas() { printf "(select count(*) from public.operaciones where tipo = 'reasignacion_vendedor') = %s" "$1"; }
n_hist() { printf "(select count(*) from public.reasignaciones_vendedor) = %s" "$1"; }
n_jorn() { printf "(select count(*) from public.jornadas) = %s" "$1"; }
n_aper() { printf "(select count(*) from public.operaciones where tipo = 'apertura_jornada') = %s" "$1"; }
n_clave() { printf "(select count(*) from public.operaciones where idempotency_key = '%s') = %s" "$1" "$2"; }
vend_de() { printf "(select vendedor_id from public.jornadas where id = '%s') = '%s'" "$1" "$2"; }
jorn_en() { printf "(select count(*) from public.jornadas where camion_id = '%s' and fecha = current_date + %s and vendedor_id = '%s') = %s" "$1" "$2" "$3" "$4"; }

# Cierra el veredicto de una repetición.
cerrar() {  # caso orden rep ok esperado resultado_de_invariantes
  local c=$1 o=$2 r=$3 ok=$4 esp=$5 inv=${6:-} det="resultado distinto del esperado"
  local obt="T1=$(res_corto "$RES_T1") T2=$(res_corto "$RES_T2")${DELANTE:+ delante=$DELANTE}"
  if ! inv_ok "$inv"; then ok=1; det=${inv:-invariantes sin resultado}; fi
  if (( ok == 0 )); then ins registrar "$c" "$o" "$r" PASS "$esp" "$obt"
  else ins registrar "$c" "$o" "$r" FAIL "$esp" "$obt" "$det"; fi
}

# Repite un caso R veces en cada orden, con una base nueva por repetición.
# Cada repetición fija REP_ID (caso|orden|rep|base) antes de crear su base y lo
# restaura después de borrarla: todo fallo instrumental anotado en ese tramo,
# incluida la creación y el borrado de la base, es FAIL de esa repetición.
repetir() {   # caso "ordenes" preparar ejecutor evaluar
  local caso=$1 ordenes=$2 prep=$3 ejec=$4 eval=$5 o r antes n rc desde
  for o in $ordenes; do
    for (( r = 1; r <= R; r++ )); do
      REP_ID="$caso|$o|$r|rep$(( NBASE + 1 ))"
      registro_leer; desde=${#REG[@]}
      MOTIVO=""; RES_T1=""; RES_T2=""; DELANTE=""
      if ! ins nueva_base; then
        ins registrar "$caso" "$o" "$r" FAIL "base de la repetición" "-" "no se creó $BASE"
      elif [[ $BASE != "${REP_ID##*|}" ]]; then
        ins registrar "$caso" "$o" "$r" FAIL "base de la repetición" "$BASE" "atribución: se esperaba ${REP_ID##*|}"
      elif ! $prep; then
        ins registrar "$caso" "$o" "$r" FAIL "preparación" "-" "$MOTIVO"
      elif $ejec "$o"; then
        # El evaluador debe registrar exactamente un veredicto propio (T3-C1) y
        # devolver 0 (T3-C2). Ambos se miden inmediatamente después de llamarlo;
        # los FAIL que agrega aquí el orquestador se registran después de medir,
        # no cuentan como veredictos del evaluador y no ocultan el suyo.
        antes=$TOTAL
        $eval "$caso" "$o" "$r"
        rc=$?
        n=$(( TOTAL - antes ))
        (( n == 1 )) || ins registrar "$caso" "$o" "$r" FAIL "un veredicto del evaluador" "$n veredictos"
        (( rc == 0 )) || ins registrar "$caso" "$o" "$r" FAIL "retorno 0 del evaluador" "retorno $rc"
      else
        ins registrar "$caso" "$o" "$r" FAIL "mecanismo del caso" "T1=$(res_corto "${RES_T1:-?|}") T2=$(res_corto "${RES_T2:-?|}")" "$MOTIVO"
      fi
      ins borrar_base "$BASE"
      DEADLOCKS_CASOS=$(( DEADLOCKS_CASOS + DEADLOCKS_ULTIMA_BASE ))
      # Punto de control: después de medir el veredicto y el retorno del evaluador.
      control_registro "$caso" "$o" "$r" "$desde"
      REP_ID=GLOBAL
    done
  done
}

# -----------------------------------------------------------------------------
# ORACULO — autoverificación del oráculo de invariantes (T3-C1, H-01; contrato
# A-2). Antes de AUTO y de los casos, distingue resultado lógico de error
# instrumental:
#   - verdadera: rc 0 y exactamente INV_OK;
#   - falsa: rc 0 e «INV_FALLA: falsa» (resultado lógico, no es un fallo);
#   - división por cero, tabla y columna inexistentes: rc 2, INV_ERROR_SQL y un
#     fallo esperado anotado por ins_esperado (los únicos del arnés);
#   - la cadena vacía y una concatenación con una falla: rechazadas por inv_ok.
# Además, el registro debe tener exactamente esos 3 esperados y ningún fallo
# inesperado de ORACULO. Si algo no se cumple, el arnés termina con exit 1 sin
# medir nada.
# -----------------------------------------------------------------------------
caso_ORACULO() {
  local inv rc a b ra rb d c desde i rid esp e=0
  BASE=oraculo
  REP_ID=ORACULO
  registro_leer; desde=${#REG[@]}
  ins sql_admin postgres "create database oraculo template arnes owner postgres" >/dev/null \
    || error_entorno "no se creó la base de la autoverificación del oráculo"
  inv=$(ins invariantes "verdadera" "true"); rc=$?
  if (( rc == 0 )) && [[ $inv == INV_OK ]] && inv_ok "$inv"; then ins registrar ORACULO - verdadera PASS "rc=0 INV_OK" "rc=$rc $inv"
  else ins registrar ORACULO - verdadera FAIL "rc=0 INV_OK" "rc=$rc $inv"; fi
  inv=$(ins invariantes "falsa" "false"); rc=$?
  if (( rc == 0 )) && [[ $inv == "INV_FALLA: falsa" ]] && ! inv_ok "$inv"; then ins registrar ORACULO - falsa PASS "rc=0 INV_FALLA" "rc=$rc $inv"
  else ins registrar ORACULO - falsa FAIL "rc=0 INV_FALLA" "rc=$rc ${inv:0:60}"; fi
  for d in division_por_cero tabla_inexistente columna_inexistente; do
    case $d in
      division_por_cero) c="(select 1 / 0) = 1" ;;
      tabla_inexistente) c="(select count(*) from public.tabla_inexistente) = 0" ;;
      columna_inexistente) c="(select count(columna_inexistente) from public.jornadas) = 0" ;;
    esac
    inv=$(ins_esperado 2 invariantes "$d" "$c"); rc=$?
    if (( rc == 0 )) && [[ $inv == 'INV_ERROR_SQL('* ]] && ! inv_ok "$inv"; then ins registrar ORACULO - "$d" PASS "rc=2 INV_ERROR_SQL" "${inv:0:60}"
    else ins registrar ORACULO - "$d" FAIL "rc=2 INV_ERROR_SQL" "ins_esperado=$rc ${inv:0:60}"; fi
  done
  if inv_ok ""; then ins registrar ORACULO - vacia FAIL "rechazo" "aceptada"
  else ins registrar ORACULO - vacia PASS "rechazo" "rechazada"; fi
  a=$(ins invariantes "verdadera" "true"); ra=$?
  b=$(ins invariantes "falsa" "false"); rb=$?
  inv="$a$b"
  if (( ra == 0 && rb == 0 )) && ! inv_ok "$inv"; then ins registrar ORACULO - concatenada PASS "rechazo" "${inv:0:60}"
  else ins registrar ORACULO - concatenada FAIL "rechazo" "rc=$ra/$rb $inv"; fi
  ins borrar_base oraculo
  DEADLOCKS_CASOS=$(( DEADLOCKS_CASOS + DEADLOCKS_ULTIMA_BASE ))
  # Registro: exactamente los 3 esperados y ningún inesperado, todos de ORACULO.
  registro_leer
  for (( i = desde; i < ${#REG[@]}; i++ )); do
    IFS=$'\t' read -r _ rid esp _ <<<"${REG[i]}"
    [[ $esp == 1 && $rid == ORACULO ]] && e=$(( e + 1 ))
  done
  registro_nuevos "$desde"
  if (( e != 3 || REG_N != 0 )); then
    ins registrar ORACULO - registro FAIL "3 esperados, 0 inesperados" "$e esperados, $REG_N inesperados" "${REG_DET:0:200}"
  fi
  REP_ID=GLOBAL
}

# -----------------------------------------------------------------------------
# AUTO — autoverificación (§18.4.11). Función de control zz_ creada sólo en el
# clúster efímero (nunca en una migración): toma los advisory de vendedor en el
# orden ingenuo vigente → nuevo, con una «puerta» compartida entre ambos para que
# el intercambio I-1 produzca el ciclo en cada repetición. Exige exactamente un
# 40P01 por repetición. Si no lo detecta, el arnés no mide nada y termina.
# -----------------------------------------------------------------------------
pred_auto() { pred_espera_adv "$1" && [[ $(campo "$1" 6) != *,* && -n $(campo "$1" 6) && $(campo "$1" 7) == "$PUERTA" ]]; }

caso_AUTO() {
  local o r primero segundo r1 r2 ok desde
  BASE=auto
  REP_ID="AUTO|-|preparación|auto"
  registro_leer; desde=${#REG[@]}
  ins sql_admin postgres "create database auto template arnes owner postgres" >/dev/null
  ins sql_pg auto "create schema zz_arnes;
create function zz_arnes.reasignar_ingenua(p_empresa uuid, p_vigente uuid, p_nuevo uuid, p_puerta bigint)
returns void language plpgsql as \$\$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'jornadas:vendedor:' || p_empresa::text || ':' || p_vigente::text, 0));
  perform pg_catalog.pg_advisory_xact_lock_shared(p_puerta);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'jornadas:vendedor:' || p_empresa::text || ':' || p_nuevo::text, 0));
end \$\$;" >/dev/null || error_entorno "no se creó la función de control de AUTO"
  PUERTA=$(ins clave_txt 'zz_arnes:puerta') || error_entorno "no se calculó la clave de la puerta de AUTO"
  control_registro AUTO - preparación "$desde"
  for o in 1 2; do
    for (( r = 1; r <= R; r++ )); do
      REP_ID="AUTO|$o|$r|auto"
      registro_leer; desde=${#REG[@]}
      MOTIVO=""; RES_T1=""; RES_T2=""; DELANTE=""
      if [[ $o == 1 ]]; then primero=T1; segundo=T2; else primero=T2; segundo=T1; fi
      EXPR_T1="zz_arnes.reasignar_ingenua('$EMPRESA', '$V3', '$V6', $PUERTA)"
      EXPR_T2="zz_arnes.reasignar_ingenua('$EMPRESA', '$V6', '$V3', $PUERTA)"
      CTRL_CLAVES=("$PUERTA")
      ok=1
      if ins ses_abrir C auto && ins ses_abrir T1 auto && ins ses_abrir T2 auto && ins control_tomar; then
        # T3-C3: lanzamientos, resultados y cierres se comprueban uno por uno.
        if ! { ins ses_lanzar "$primero" "" "$(expr_de "$primero")" && ins ses_lanzar "$segundo" "" "$(expr_de "$segundo")"; }; then
          MOTIVO="no se lanzaron las sesiones"
        elif foto_par_estable pred_auto "${S_PID[T1]}" "" "${S_PID[T2]}" "" && ins control_liberar; then
          if RES_T1=$(ins ses_resultado T1) && RES_T2=$(ins ses_resultado T2) && ins ses_fin T1 && ins ses_fin T2; then
            r1=${RES_T1%%|*}; r2=${RES_T2%%|*}
            [[ "$r1 $r2" == "00000 40P01" || "$r1 $r2" == "40P01 00000" ]] && ok=0
          else
            MOTIVO="falló la lectura del resultado o el cierre de una sesión"
          fi
        else
          MOTIVO="las sesiones no llegaron a la puerta: T1[$FOTO1] T2[$FOTO2]"
        fi
      else
        MOTIVO="no se preparó la autoverificación"
      fi
      if (( ok == 0 )); then ins registrar AUTO "$o" "$r" PASS "{00000,40P01}" "T1=${RES_T1%%|*} T2=${RES_T2%%|*}"
      else ins registrar AUTO "$o" "$r" FAIL "{00000,40P01}" "T1=${RES_T1%%|*} T2=${RES_T2%%|*}" "${MOTIVO:-sin 40P01}"; fi
      ins cerrar_todas
      control_registro AUTO "$o" "$r" "$desde"
    done
  done
  REP_ID="AUTO|-|cierre|auto"
  registro_leer; desde=${#REG[@]}
  ins borrar_base auto
  control_registro AUTO - cierre "$desde"
  REP_ID=GLOBAL
  DEADLOCKS_AUTO=$DEADLOCKS_ULTIMA_BASE
  if (( DEADLOCKS_AUTO == 2 * R )); then
    ins registrar AUTO-CONT - - PASS "deadlocks=$(( 2 * R ))" "deadlocks=$DEADLOCKS_AUTO"
  else
    ins registrar AUTO-CONT - - FAIL "deadlocks=$(( 2 * R ))" "deadlocks=$DEADLOCKS_AUTO"
  fi
}

# -----------------------------------------------------------------------------
# I10-R — reasignar_vendedor, misma clave y mismo payload. Las dos leen el
# vigente V3 en el paso 6 y esperan en el paso 7; la segunda obtiene los
# bloqueos con el vigente ya cambiado a V6: sin el paso 8a, 8b la rechazaría.
# -----------------------------------------------------------------------------
prep_I10_R() {
  ins jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$EXPR_T1
  CTRL_CLAVES=()   # un elemento por orden: SIGUSR1 nunca llega con otra $(…) pendiente
  CTRL_CLAVES+=("$(ins kv "$V3")")
  CTRL_CLAVES+=("$(ins kv "$V6")")
}
eval_I10_R() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && mismo_uuid && ok=0
  cerrar "$@" $ok "las dos 00000 con el mismo uuid" "$(ins invariantes \
    "una operación" "$(n_reas 1)" "un historial" "$(n_hist 1)" "clave única" "$(n_clave "$IDEM_T1" 1)" \
    "vendedor final V6" "$(vend_de "$J1" "$V6")" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_I10_R() { repetir I10-R "1 2" prep_I10_R correr_par eval_I10_R; }

# I11-R — misma clave, payload distinto (T1 → V6, T2 → V7): conflicto en 8a,
# nunca jornada_estado_invalido; efectos sólo de la que confirmó.
prep_I11_R() {
  ins jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(reasignar "$IDEM_T2" "$J1" "$V7")
  CTRL_CLAVES=()   # un elemento por orden: SIGUSR1 nunca llega con otra $(…) pendiente
  CTRL_CLAVES+=("$(ins kv "$V3")")
  CTRL_CLAVES+=("$(ins kv "$V6")")
  CTRL_CLAVES+=("$(ins kv "$V7")")
}
eval_I11_R() {
  local ok=1 dest
  [[ $DELANTE == T1 ]] && dest=$V6 || dest=$V7
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_conflicto_idempotencia && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_conflicto_idempotencia" "$(ins invariantes \
    "una operación" "$(n_reas 1)" "un historial" "$(n_hist 1)" \
    "vendedor final = destino de la sesión delante" "$(vend_de "$J1" "$dest")" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_I11_R() { repetir I11-R "1 2" prep_I11_R correr_par eval_I11_R; }

# I10-A — abrir_jornada, misma clave y mismo payload; el control retiene camión
# y vendedor (tabla A-02). No distingue 8a del ON CONFLICT del paso 9.
prep_I10_A() {
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$EXPR_T1
  CTRL_CLAVES=()   # un elemento por orden: SIGUSR1 nunca llega con otra $(…) pendiente
  CTRL_CLAVES+=("$(ins kc "$CAM1")")
  CTRL_CLAVES+=("$(ins kv "$V3")")
}
eval_aper_mismo() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && mismo_uuid && ok=0
  cerrar "$@" $ok "las dos 00000 con el mismo uuid de jornada" "$(ins invariantes \
    "una jornada" "$(n_jorn 1)" "una apertura" "$(n_aper 1)" "clave única" "$(n_clave "$IDEM_T1" 1)" \
    "la jornada pedida" "$(jorn_en "$CAM1" 30 "$V3" 1)" \
    "respuesta = jornada" "(select id::text from public.jornadas) = '$(uuid_de "$RES_T1")'" \
    "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_I10_A() { repetir I10-A "1 2" prep_I10_A correr_par eval_aper_mismo; }

# -----------------------------------------------------------------------------
# K1 — I-1 intercambio: J1 (V3, f) → V6 y J2 (V6, f) → V3. Las dos PT409
# jornada_vendedor_ocupado en cualquier orden; cero 40P01.
# -----------------------------------------------------------------------------
prep_K1() {
  ins jornada J1 "$CAM1" 30 "$V3" && ins jornada J2 "$CAM2" 30 "$V6" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(reasignar "$IDEM_T2" "$J2" "$V3")
  CTRL_CLAVES=()   # un elemento por orden: SIGUSR1 nunca llega con otra $(…) pendiente
  CTRL_CLAVES+=("$(ins kv "$V3")")
  CTRL_CLAVES+=("$(ins kv "$V6")")
}
eval_K1() {
  local ok=1
  es_err "$RES_T1" PT409 jornada_vendedor_ocupado && es_err "$RES_T2" PT409 jornada_vendedor_ocupado && ok=0
  cerrar "$@" $ok "las dos PT409 jornada_vendedor_ocupado" "$(ins invariantes \
    "sin operaciones" "$(n_reas 0)" "sin historial" "$(n_hist 0)" \
    "J1 conserva V3" "$(vend_de "$J1" "$V3")" "J2 conserva V6" "$(vend_de "$J2" "$V6")" "I-J1" "$INV_IJ1")"
}
caso_K1() { repetir K1 "1 2" prep_K1 correr_par eval_K1; }

# K2 — I-1b cadena: J1 (V3) → V7 y J2 (V6) → V3. Resultado del orden serial de
# la cola observada: T1 delante → las dos confirman; T2 delante → T2 PT409
# jornada_vendedor_ocupado y T1 confirma.
prep_K2() {
  ins jornada J1 "$CAM1" 30 "$V3" && ins jornada J2 "$CAM2" 30 "$V6" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V7"); EXPR_T2=$(reasignar "$IDEM_T2" "$J2" "$V3")
  CTRL_CLAVES=()   # un elemento por orden: SIGUSR1 nunca llega con otra $(…) pendiente
  CTRL_CLAVES+=("$(ins kv "$V3")")
  CTRL_CLAVES+=("$(ins kv "$V6")")
  CTRL_CLAVES+=("$(ins kv "$V7")")
}
eval_K2() {
  local ok=1
  if [[ $DELANTE == T1 ]]; then
    es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
    cerrar "$@" $ok "serial T1;T2: las dos 00000" "$(ins invariantes \
      "dos operaciones" "$(n_reas 2)" "dos historiales" "$(n_hist 2)" \
      "J1 → V7" "$(vend_de "$J1" "$V7")" "J2 → V3" "$(vend_de "$J2" "$V3")" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  else
    es_ok "$RES_T1" && es_err "$RES_T2" PT409 jornada_vendedor_ocupado && ok=0
    cerrar "$@" $ok "serial T2;T1: T2 PT409 jornada_vendedor_ocupado, T1 00000" "$(ins invariantes \
      "una operación" "$(n_reas 1)" "un historial" "$(n_hist 1)" \
      "J1 → V7" "$(vend_de "$J1" "$V7")" "J2 conserva V6" "$(vend_de "$J2" "$V6")" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  fi
}
caso_K2() { repetir K2 "1 2" prep_K2 correr_par eval_K2; }

# K3 — I-2 apertura con el vigente: T1 reasigna J1 (V3, f) → V6; T2 abre
# (camión 2, f, V3). Se encolan en adv(V3).
prep_K3() {
  ins jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM2" 30 "$V3")
  CTRL_CLAVES=("$(ins kv "$V3")")
}
eval_K3() {
  local ok=1
  if [[ $DELANTE == T1 ]]; then
    es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
    cerrar "$@" $ok "serial T1;T2: las dos 00000" "$(ins invariantes \
      "J1 → V6" "$(vend_de "$J1" "$V6")" "apertura de camión 2 con V3" "$(jorn_en "$CAM2" 30 "$V3" 1)" \
      "una reasignación" "$(n_reas 1)" "dos aperturas" "$(n_aper 2)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  else
    es_err "$RES_T2" PT409 jornada_vendedor_ocupado && es_ok "$RES_T1" && ok=0
    cerrar "$@" $ok "serial T2;T1: T2 PT409 jornada_vendedor_ocupado, T1 00000" "$(ins invariantes \
      "J1 → V6" "$(vend_de "$J1" "$V6")" "sin jornada del camión 2" "$(n_jorn 1)" \
      "una reasignación" "$(n_reas 1)" "una apertura" "$(n_aper 1)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  fi
}
caso_K3() { repetir K3 "1 2" prep_K3 correr_par eval_K3; }

# K4 — I-2 hacia el nuevo: T1 reasigna J1 (V3, f) → V6; T2 abre (camión 2, f,
# V6). Se encolan en adv(V6): una confirma y la otra PT409 jornada_vendedor_ocupado.
prep_K4() {
  ins jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM2" 30 "$V6")
  CTRL_CLAVES=("$(ins kv "$V6")")
}
eval_K4() {
  local ok=1
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_vendedor_ocupado && ok=0
  if [[ $DELANTE == T1 ]]; then
    cerrar "$@" $ok "T1 00000; T2 PT409 jornada_vendedor_ocupado" "$(ins invariantes \
      "J1 → V6" "$(vend_de "$J1" "$V6")" "sin jornada del camión 2" "$(n_jorn 1)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  else
    cerrar "$@" $ok "T2 00000; T1 PT409 jornada_vendedor_ocupado" "$(ins invariantes \
      "J1 conserva V3" "$(vend_de "$J1" "$V3")" "apertura de camión 2 con V6" "$(jorn_en "$CAM2" 30 "$V6" 1)" \
      "sin reasignaciones" "$(n_reas 0)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  fi
}
caso_K4() { repetir K4 "1 2" prep_K4 correr_par eval_K4; }

# K9-R — el vigente cambia entre los pasos 6 y 8b por otra operación confirmada
# con DISTINTA clave: la sesión de atrás recibe PT409 jornada_estado_invalido
# (8b), sin reserva ni historial; reintentar con la misma clave confirma.
prep_K9_R() {
  ins jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(reasignar "$IDEM_T2" "$J1" "$V7")
  CTRL_CLAVES=()   # un elemento por orden: SIGUSR1 nunca llega con otra $(…) pendiente
  CTRL_CLAVES+=("$(ins kv "$V3")")
  CTRL_CLAVES+=("$(ins kv "$V6")")
  CTRL_CLAVES+=("$(ins kv "$V7")")
}
eval_K9_R() {
  local ok=1 inv_rech reint="" fallo="" dest_otro dest_del clave_otro
  if [[ $OTRO == T1 ]]; then dest_otro=$V6; dest_del=$V7; clave_otro=$IDEM_T1
  else dest_otro=$V7; dest_del=$V6; clave_otro=$IDEM_T2; fi
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_estado_invalido && ok=0
  inv_rech=$(ins invariantes "el rechazo no reservó la clave" "$(n_clave "$clave_otro" 0)" \
    "un historial" "$(n_hist 1)" "J1 → destino de delante" "$(vend_de "$J1" "$dest_del")")
  # Reintento con la misma clave y el mismo payload: la RPC recalcula el vigente.
  # Cada paso instrumental se comprueba (T3-C3, C2-H01): si uno falla, la
  # repetición es FAIL aunque los efectos observados parezcan correctos.
  if ! ins ses_lanzar "$OTRO" "$ACTOR" "$(expr_de "$OTRO")"; then fallo="no se lanzó el reintento"
  elif ! reint=$(ins ses_resultado "$OTRO"); then fallo="el reintento no respondió"
  elif ! ins ses_fin "$OTRO"; then fallo="no se cerró la transacción del reintento"
  fi
  [[ -z $fallo ]] && es_ok "$reint" || ok=1
  (( ok == 0 )) || echo "    reintento=$(res_corto "$reint")${fallo:+ fallo=[$fallo]}" | tee -a "$SALIDA"
  # cerrar() es el último comando: su retorno es el del evaluador (T3-C3).
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_estado_invalido; reintento 00000" "${inv_rech}$(ins invariantes \
    "dos operaciones tras el reintento" "$(n_reas 2)" "dos historiales" "$(n_hist 2)" \
    "J1 → destino del reintento" "$(vend_de "$J1" "$dest_otro")" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_K9_R() { repetir K9-R "1 2" prep_K9_R correr_par eval_K9_R; }

# -----------------------------------------------------------------------------
# K10 — aperturas concurrentes (claves distintas salvo d y e).
# -----------------------------------------------------------------------------
prep_K10_a() {  # mismo camión y misma fecha, vendedores distintos
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM1" 30 "$V6")
  CTRL_CLAVES=("$(ins kc "$CAM1")")
}
eval_K10_a() {
  local ok=1 o
  o=$(res_de "$OTRO")
  es_ok "$(res_de "$DELANTE")" \
    && { es_err "$o" PT409 jornada_duplicada || es_err "$o" PT409 jornada_camion_con_jornada_abierta; } && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_duplicada o jornada_camion_con_jornada_abierta" "$(ins invariantes \
    "una jornada" "$(n_jorn 1)" "una apertura" "$(n_aper 1)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_K10_a() { repetir K10-a "1 2" prep_K10_a correr_par eval_K10_a; }

prep_K10_b() {  # mismo camión, fechas distintas
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM1" 31 "$V6")
  CTRL_CLAVES=("$(ins kc "$CAM1")")
}
eval_K10_b() {
  local ok=1
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_camion_con_jornada_abierta && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_camion_con_jornada_abierta" "$(ins invariantes \
    "una jornada" "$(n_jorn 1)" "una apertura" "$(n_aper 1)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_K10_b() { repetir K10-b "1 2" prep_K10_b correr_par eval_K10_b; }

prep_K10_c() {  # mismo vendedor y misma fecha, camiones distintos: cola en adv(V3)
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM2" 30 "$V3")
  CTRL_CLAVES=("$(ins kv "$V3")")
}
eval_K10_c() {
  local ok=1
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_vendedor_ocupado && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_vendedor_ocupado" "$(ins invariantes \
    "una jornada" "$(n_jorn 1)" "una apertura" "$(n_aper 1)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_K10_c() { repetir K10-c "1 2" prep_K10_c correr_par eval_K10_c; }

prep_K10_d() {  # misma clave y mismos parámetros; el control retiene sólo el camión
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$EXPR_T1
  CTRL_CLAVES=("$(ins kc "$CAM1")")
}
caso_K10_d() { repetir K10-d "1 2" prep_K10_d correr_par eval_aper_mismo; }

prep_K10_e() {  # misma clave y distinto vendedor
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM1" 30 "$V6")
  CTRL_CLAVES=("$(ins kc "$CAM1")")
}
eval_K10_e() {
  local ok=1 vd
  [[ $DELANTE == T1 ]] && vd=$V3 || vd=$V6
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_conflicto_idempotencia && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_conflicto_idempotencia" "$(ins invariantes \
    "una jornada" "$(n_jorn 1)" "una apertura" "$(n_aper 1)" "la jornada de la sesión delante" "$(jorn_en "$CAM1" 30 "$vd" 1)" \
    "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_K10_e() { repetir K10-e "1 2" prep_K10_e correr_par eval_K10_e; }

# -----------------------------------------------------------------------------
# K8 (parcial)
# -----------------------------------------------------------------------------
# K8-CLAVE — misma clave en dos jornadas distintas (J1 V3 → V6; J2 V7 → V9): no
# comparten bloqueos. La segunda pasa 8a sin ver nada y queda esperando, con su
# reserva en curso, a la transacción abierta de la primera (paso 9); al
# confirmar la primera, el ON CONFLICT da PT409 jornada_conflicto_idempotencia.
prep_K8_CLAVE() {
  ins jornada J1 "$CAM1" 30 "$V3" && ins jornada J2 "$CAM2" 30 "$V7" || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(reasignar "$IDEM_T2" "$J2" "$V9")
  CTRL_CLAVES=()   # un elemento por orden: SIGUSR1 nunca llega con otra $(…) pendiente
  CTRL_CLAVES+=("$(ins kv "$V3")")
  CTRL_CLAVES+=("$(ins kv "$V7")")
}
eval_K8_CLAVE() {
  local ok=1 jd jo vd vo
  if [[ $DELANTE == T1 ]]; then jd=$J1; vd=$V6; jo=$J2; vo=$V7; else jd=$J2; vd=$V9; jo=$J1; vo=$V3; fi
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_conflicto_idempotencia && ok=0
  cerrar "$@" $ok "primera 00000; la otra PT409 jornada_conflicto_idempotencia en el paso 9" "$(ins invariantes \
    "una operación con la clave" "$(n_clave "$IDEM_T1" 1)" "un historial" "$(n_hist 1)" \
    "jornada de la primera cambiada" "$(vend_de "$jd" "$vd")" "jornada de la otra intacta" "$(vend_de "$jo" "$vo")" \
    "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_K8_CLAVE() { repetir K8-CLAVE "1 2" prep_K8_CLAVE correr_independientes eval_K8_CLAVE; }

# K8-BAJA-a — baja del camión mientras la apertura espera su advisory: la baja no
# espera (no toma advisory de jornadas) y la apertura, que lee camiones.activo
# después de los bloqueos, recibe PT409 jornada_camion_inactivo.
prep_K8_BAJA() {
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=""
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM3" 30 "$V9"); EXPR_T2=$(baja_camion "$CAM3")
  CTRL_CLAVES=("$(ins kc "$CAM3")")
}
correr_baja_en_espera() {
  MOTIVO=""; DELANTE=""; OTRO=""; RES_T1=""; RES_T2=""
  ins ses_abrir C "$BASE" && ins ses_abrir T1 "$BASE" && ins ses_abrir T2 "$BASE" || { MOTIVO="no se abrieron las sesiones"; return 1; }
  ins control_tomar || return 1
  # T3-C3: cada operación instrumental se comprueba; ninguna queda sin verificar.
  ins ses_lanzar T1 "$ACTOR" "$EXPR_T1" || { MOTIVO="no se lanzó la apertura"; return 1; }
  foto_estable pred_abcd "${S_PID[T1]}" "$IDEM_T1" || { MOTIVO="T1 no llegó a la espera: $FOTO"; return 1; }
  ins ses_lanzar T2 "$ACTOR" "$EXPR_T2" || { MOTIVO="no se lanzó la baja"; return 1; }
  RES_T2=$(ins ses_resultado T2) || { MOTIVO="la baja no terminó: espera espuria ($(ins foto "${S_PID[T2]}"))"; return 1; }
  ins ses_fin T2 || { MOTIVO="no se cerró la transacción de la baja"; return 1; }
  foto_estable pred_abcd "${S_PID[T1]}" "$IDEM_T1" && [[ $(campo "$FOTO" 5) == "${S_PID[C]}" ]] \
    || { MOTIVO="T1 dejó de esperar sólo al control: $FOTO"; return 1; }
  ins control_liberar || { MOTIVO="el control no liberó"; return 1; }
  RES_T1=$(ins ses_resultado T1) || { MOTIVO="T1 no respondió"; return 1; }
  ins ses_fin T1 || { MOTIVO="no se cerró la transacción de la apertura"; return 1; }
}
eval_K8_BAJA_a() {
  local ok=1
  es_ok "$RES_T2" && es_err "$RES_T1" PT409 jornada_camion_inactivo && ok=0
  cerrar "$@" $ok "baja 00000; apertura PT409 jornada_camion_inactivo" "$(ins invariantes \
    "sin jornadas" "$(n_jorn 0)" "sin aperturas" "$(n_aper 0)" "camión inactivo" "(select not activo from public.camiones where id = '$CAM3')")"
}
caso_K8_BAJA_a() { repetir K8-BAJA-a "-" prep_K8_BAJA correr_baja_en_espera eval_K8_BAJA_a; }

# K8-BAJA-b — baja del camión después de que la apertura volvió con la
# transacción abierta (5c): el FOR KEY SHARE de la FK es compatible con el
# UPDATE de baja (no toca claves), así que la baja termina sin esperar; equivale
# a una baja inmediatamente posterior (ADR-001 §18.4.5; ADR-007 §2.7).
eval_K8_BAJA_b() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
  cerrar "$@" $ok "apertura 00000; baja 00000 sin esperar" "$(ins invariantes \
    "una jornada" "$(n_jorn 1)" "la apertura pedida" "$(jorn_en "$CAM3" 30 "$V9" 1)" \
    "camión inactivo" "(select not activo from public.camiones where id = '$CAM3')" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_K8_BAJA_b() { repetir K8-BAJA-b "1" prep_K8_BAJA correr_secuencial eval_K8_BAJA_b; }

# -----------------------------------------------------------------------------
# S-ESP — sin esperas espurias: con la primera operación devuelta y su
# transacción abierta (retiene advisory, FOR UPDATE, reserva e índices únicos),
# una operación sobre recursos disjuntos termina sin esperarla.
# -----------------------------------------------------------------------------
prep_S_ESP_RR() {
  ins jornada J1 "$CAM1" 30 "$V3" && ins jornada J2 "$CAM2" 30 "$V7" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(reasignar "$IDEM_T2" "$J2" "$V9")
}
eval_S_ESP_RR() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
  cerrar "$@" $ok "las dos 00000 sin esperarse" "$(ins invariantes \
    "dos operaciones" "$(n_reas 2)" "J1 → V6" "$(vend_de "$J1" "$V6")" "J2 → V9" "$(vend_de "$J2" "$V9")" \
    "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_S_ESP_RR() { repetir S-ESP-RR "1 2" prep_S_ESP_RR correr_secuencial eval_S_ESP_RR; }

prep_S_ESP_RA() {
  ins jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM3" 30 "$V9")
}
eval_S_ESP_RA() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
  cerrar "$@" $ok "las dos 00000 sin esperarse" "$(ins invariantes \
    "J1 → V6" "$(vend_de "$J1" "$V6")" "apertura de camión 3" "$(jorn_en "$CAM3" 30 "$V9" 1)" \
    "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_S_ESP_RA() { repetir S-ESP-RA "1 2" prep_S_ESP_RA correr_secuencial eval_S_ESP_RA; }

# -----------------------------------------------------------------------------
# O — observación de una sola sesión sobre la RPC real (se revierte).
#   O3: reasignar_vendedor toma vigente y nuevo en orden de uuid;
#   O4: abrir_jornada toma camión (nivel 1) antes que vendedor (nivel 2);
#   O2′: backend_xid NULL mientras espera cualquiera de sus advisory;
#   O5: al volver, la transacción retiene exactamente su conjunto y tiene xid.
# -----------------------------------------------------------------------------
prep_O_R() {   # vigente nuevo clave_retenida
  local dias=30
  [[ $1 == "$V7" ]] && dias=31
  ins jornada JO "$([[ $dias == 30 ]] && echo "$CAM1" || echo "$CAM2")" "$dias" "$1" || return 1
  nueva_clave; IDEM_T1=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$JO" "$2")
  CTRL_CLAVES=("$3")
  OBS_RET=$(lista "$(ins kv "$1")" "$(ins kv "$2")")
}
eval_O() {
  local ok=1
  es_ok "$RES_T1" && [[ -z $MOTIVO ]] && ok=0
  cerrar "$@" $ok "concedidos=[$OBS_G] esperado=[$OBS_W] xid NULL; al volver retiene [$OBS_RET]" \
    "$(ins invariantes "sin efectos (revertido)" "$(n_clave "$IDEM_T1" 0)")"
}
prep_O_R1() { prep_O_R "$V3" "$V6" "$(ins kv "$V3")" && OBS_G="" && OBS_W=$(ins kv "$V3"); }
prep_O_R2() { prep_O_R "$V3" "$V6" "$(ins kv "$V6")" && OBS_G=$(ins kv "$V3") && OBS_W=$(ins kv "$V6"); }
prep_O_R3() { prep_O_R "$V7" "$V3" "$(ins kv "$V7")" && OBS_G=$(ins kv "$V3") && OBS_W=$(ins kv "$V7"); }
prep_O_R4() { prep_O_R "$V7" "$V3" "$(ins kv "$V3")" && OBS_G="" && OBS_W=$(ins kv "$V3"); }
prep_O_A() {
  nueva_clave; IDEM_T1=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM3" 30 "$V9")
  OBS_RET=$(lista "$(ins kc "$CAM3")" "$(ins kv "$V9")")
}
prep_O_A1() { prep_O_A && CTRL_CLAVES=("$(ins kv "$V9")") && OBS_G=$(ins kc "$CAM3") && OBS_W=$(ins kv "$V9"); }
prep_O_A2() { prep_O_A && CTRL_CLAVES=("$(ins kc "$CAM3")") && OBS_G="" && OBS_W=$(ins kc "$CAM3"); }
caso_O_R1() { repetir O-R1 "-" prep_O_R1 correr_observado eval_O; }
caso_O_R2() { repetir O-R2 "-" prep_O_R2 correr_observado eval_O; }
caso_O_R3() { repetir O-R3 "-" prep_O_R3 correr_observado eval_O; }
caso_O_R4() { repetir O-R4 "-" prep_O_R4 correr_observado eval_O; }
caso_O_A1() { repetir O-A1 "-" prep_O_A1 correr_observado eval_O; }
caso_O_A2() { repetir O-A2 "-" prep_O_A2 correr_observado eval_O; }

# =============================================================================
# T5 — registrar_carga (ADR-001 §18.4.9 I10, I11 y K8; §18.4.11). Casos nuevos,
# agregados sin modificar arnes.sh ni los casos de T3 (decisión humana del
# 04/11/2026, opción a):
#
#   I10-C       misma clave y mismo payload: las dos con la misma operación
#   I11-C       misma clave y payload distinto: una confirma, la otra PT409
#   K8-CC-a     dos cargas de la misma jornada (CONC-18.4-01), ambas caben
#   K8-CC-b     dos cargas de la misma jornada cuya suma excede el depósito
#   K8-CR       carga contra reasignación de la misma jornada
#   K8-CM       registrar_merma contra registrar_carga, misma clave y mismo
#               advisory de stock (nivel 4)
#   K8-SM       registrar_merma contra registrar_carga, claves distintas, suma
#               mayor que el depósito: el advisory de nivel 4 las serializa
#   K8-CLAVE-C  misma clave en dos jornadas: ON CONFLICT del paso 9
#
# registrar_carga no toma advisory de niveles 1 ni 2: según §18.4.11 el control
# retiene el FOR UPDATE de la jornada (nivel 3) y las sesiones esperan esa fila
# (paso 8). En K8-CM y K8-SM el control retiene el advisory de stock del depósito
# (nivel 4), que las dos RPC piden después de reservar su clave. Las esperas se
# observan con el monitor (pg_stat_activity, pg_locks, pg_blocking_pids) y la foto
# estable estricta; los sleep sólo espacian lecturas, nunca son la evidencia.
# K11 (salida contra cambios de carga neta) queda NO APLICABLE en T5: requiere
# registrar_descarga y confirmar_salida (T6 y T7).
# =============================================================================
PROD1='aaaaaaaa-2100-4000-8000-0000000000f1'
DEP='aaaaaaaa-2100-4000-8000-0000000000d1'
UBI1='aaaaaaaa-2100-4000-8000-0000000000e1'
UBI2='aaaaaaaa-2100-4000-8000-0000000000e2'
OP_ING='aaaaaaaa-2100-4000-8000-0000000000b0'
JORNADAS_CTRL=()   # filas de jornadas que retiene el control, en orden de uuid

# Depósito, ubicaciones de CAM1 y CAM2, un producto y su ingreso inicial, como
# postgres (owner, sin RPC) en la base de la repetición.
preparar_stock() {   # cantidad inicial de PROD1 en el depósito
  ins sql_pg "$BASE" "
insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('$DEP', '$EMPRESA_A', 'deposito', null),
  ('$UBI1', '$EMPRESA_A', 'camion', '$CAM1'),
  ('$UBI2', '$EMPRESA_A', 'camion', '$CAM2');
insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por)
  values ('$PROD1', '$EMPRESA_A', 'JR-P1', 'Leche', 'lacteos', 'unidad', 100, true, '$DUENO');
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella)
  values ('$OP_ING', '$EMPRESA_A', '$DUENO', 'ingreso', '$OP_ING', repeat('e', 64));
insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                      ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo)
  values ('$EMPRESA_A', '$OP_ING', 'ingreso', '$PROD1', $1, null, '$DEP', '$DUENO', 'arnés T5');" >/dev/null \
    || { MOTIVO="no se preparó el stock"; return 1; }
}

cargar() { printf "public.registrar_carga('%s', '%s', array['%s']::uuid[], array[%s])" "$1" "$2" "$PROD1" "$3"; }
mermar() { printf "public.registrar_merma('%s', '%s', '%s', %s, 'vencido', null)" "$1" "$PROD1" "$DEP" "$2"; }
ks() { ins clave_txt "stock:$EMPRESA:$1:$2"; }   # nivel 4

saldo_es() {  # ubicación cantidad
  printf "(select coalesce(sum(case when ubicacion_destino_id = '%s' then cantidad else -cantidad end), 0)
             from public.movimientos_stock where producto_id = '%s'
              and (ubicacion_destino_id = '%s' or ubicacion_origen_id = '%s')) = %s" "$1" "$PROD1" "$1" "$1" "$2"
}
n_tipo() { printf "(select count(*) from public.operaciones where tipo = '%s') = %s" "$1" "$2"; }
n_mov() { printf "(select count(*) from public.movimientos_stock where tipo_movimiento = '%s') = %s" "$1" "$2"; }
estado_es() { printf "(select estado from public.jornadas where id = '%s') = '%s'" "$1" "$2"; }
INV_STOCK="not exists (select 1 from public.stock_actual where cantidad < 0)"
INV_HUERFANAS_STOCK="not exists (select 1 from public.operaciones o where o.tipo in ('carga', 'merma')
   and not exists (select 1 from public.movimientos_stock m where m.operacion_id = o.id))
 and not exists (select 1 from public.movimientos_stock m join public.operaciones o on o.id = m.operacion_id
                  where m.tipo_movimiento <> o.tipo)"

# Predicados del monitor para las esperas de T5.
pred_fila_abcd() {   # (a) espera Lock; (b) fila/tupla no concedida; (c) sin reserva; (d) sin operación con la clave
  [[ $(campo "$1" 1) == active && $(campo "$1" 2) == Lock && $(campo "$1" 8) -ge 1 && $(campo "$1" 9) == 0 ]] \
    && [[ $(campo "$1" 10) == 0 || $(campo "$1" 10) == - ]]
}
pred_adv_reservado() {  # espera un advisory con la clave ya reservada (sin confirmar: no visible)
  [[ $(campo "$1" 1) == active && $(campo "$1" 2) == Lock && -n $(campo "$1" 7) && $(campo "$1" 9) -ge 1 ]] \
    && [[ $(campo "$1" 10) == 0 || $(campo "$1" 10) == - ]]
}

# El control retiene las filas de JORNADAS_CTRL con FOR UPDATE, en una transacción
# abierta, sin advisory ni escrituras.
control_fila_tomar() {
  local j f sql="begin;"
  for j in "${JORNADAS_CTRL[@]}"; do
    sql+=$'\n'"select 1 from public.jornadas where id = '$j' and empresa_id = '$EMPRESA' for update;"
  done
  ins ses_comando C "$sql" || { MOTIVO="el control no tomó las filas"; return 1; }
  f=$(ins foto "${S_PID[C]}") || { MOTIVO="falló la foto del control"; return 1; }
  [[ $(campo "$f" 1) == "idle in transaction" && -z $(campo "$f" 6) && $(campo "$f" 9) == 0 ]] \
    || { MOTIVO="el control no retiene sólo las filas ($f)"; return 1; }
}

abrir_sesiones() {
  ins ses_abrir C "$BASE" && ins ses_abrir T1 "$BASE" && ins ses_abrir T2 "$BASE" \
    || { MOTIVO="no se abrieron las sesiones"; return 1; }
}

# Tras liberar: DELANTE vuelve con su transacción abierta (5c); si confirmó, OTRO
# debe esperar sólo a DELANTE. Después se confirman las dos y se leen resultados.
terminar_par() {
  local rd ro
  rd=$(ins ses_resultado "$DELANTE") || { MOTIVO="$DELANTE no respondió dentro del plazo"; return 1; }
  if [[ ${rd%%|*} == 00000 ]]; then
    foto_estable pred_espera_lock "${S_PID[$OTRO]}" \
      || { MOTIVO="$OTRO no quedó esperando a $DELANTE: $FOTO"; return 1; }
    bloqueantes_permitidos "$FOTO" "${S_PID[$DELANTE]}" && contiene_pid "$FOTO" "${S_PID[$DELANTE]}" \
      || { MOTIVO="$OTRO espera a otro proceso: $FOTO"; return 1; }
  fi
  ins ses_fin "$DELANTE" || { MOTIVO="no se cerró la transacción de $DELANTE"; return 1; }
  ro=$(ins ses_resultado "$OTRO") || { MOTIVO="$OTRO no respondió dentro del plazo"; return 1; }
  ins ses_fin "$OTRO" || { MOTIVO="no se cerró la transacción de $OTRO"; return 1; }
  if [[ $DELANTE == T1 ]]; then RES_T1=$rd; RES_T2=$ro; else RES_T2=$rd; RES_T1=$ro; fi
}

# Cola compartida del FOR UPDATE de una jornada (I10-C, I11-C, K8-CC, K8-CR). El
# primero de la cola espera sólo al control; el otro espera al primero.
correr_fila_par() {   # orden
  local primero segundo c p1 p2
  MOTIVO=""; DELANTE=""; OTRO=""; RES_T1=""; RES_T2=""
  if [[ $1 == 1 ]]; then primero=T1; segundo=T2; else primero=T2; segundo=T1; fi
  abrir_sesiones || return 1
  control_fila_tomar || return 1
  ins ses_lanzar "$primero" "$ACTOR" "$(expr_de "$primero")" || { MOTIVO="no se lanzó $primero"; return 1; }
  foto_estable pred_fila_abcd "${S_PID[$primero]}" "$(idem_de "$primero")" \
    || { MOTIVO="$primero no llegó a la espera de la fila con (a)-(d): $FOTO"; return 1; }
  ins ses_lanzar "$segundo" "$ACTOR" "$(expr_de "$segundo")" || { MOTIVO="no se lanzó $segundo"; return 1; }
  foto_estable pred_fila_abcd "${S_PID[$segundo]}" "$(idem_de "$segundo")" \
    || { MOTIVO="$segundo no llegó a la espera de la fila con (a)-(d): $FOTO"; return 1; }
  foto_par_estable pred_fila_abcd "${S_PID[T1]}" "$IDEM_T1" "${S_PID[T2]}" "$IDEM_T2" \
    || { MOTIVO="sin foto conjunta estable de (a)-(d)"; return 1; }
  FOTO_T1=$FOTO1; FOTO_T2=$FOTO2
  c=${S_PID[C]}; p1=${S_PID[T1]}; p2=${S_PID[T2]}
  bloqueantes_permitidos "$FOTO_T1" "$c" "$p2" && bloqueantes_permitidos "$FOTO_T2" "$c" "$p1" \
    || { MOTIVO="bloqueante ajeno al caso: T1[$FOTO_T1] T2[$FOTO_T2]"; return 1; }
  if [[ $(campo "$FOTO_T1" 5) == "$c" ]] && contiene_pid "$FOTO_T2" "$p1"; then
    DELANTE=T1; OTRO=T2
  elif [[ $(campo "$FOTO_T2" 5) == "$c" ]] && contiene_pid "$FOTO_T1" "$p2"; then
    DELANTE=T2; OTRO=T1
  else
    MOTIVO="cola ambigua: T1[$FOTO_T1] T2[$FOTO_T2]"; return 1
  fi
  ins ses_revertir C || { MOTIVO="el control no liberó"; return 1; }
  terminar_par
}

# Dos jornadas, sin bloqueos compartidos (K8-CLAVE-C): cada sesión espera su fila
# sólo al control. Tras liberar, la que vuelve primero retiene su reserva y la
# otra debe quedar esperando en el índice único de operaciones a esa sesión.
correr_fila_indep() {   # orden
  local primero segundo c i rd ro f2
  MOTIVO=""; DELANTE=""; OTRO=""; RES_T1=""; RES_T2=""
  if [[ $1 == 1 ]]; then primero=T1; segundo=T2; else primero=T2; segundo=T1; fi
  abrir_sesiones || return 1
  control_fila_tomar || return 1
  ins ses_lanzar "$primero" "$ACTOR" "$(expr_de "$primero")" || { MOTIVO="no se lanzó $primero"; return 1; }
  foto_estable pred_fila_abcd "${S_PID[$primero]}" "$(idem_de "$primero")" \
    || { MOTIVO="$primero no llegó a la espera: $FOTO"; return 1; }
  ins ses_lanzar "$segundo" "$ACTOR" "$(expr_de "$segundo")" || { MOTIVO="no se lanzó $segundo"; return 1; }
  foto_estable pred_fila_abcd "${S_PID[$segundo]}" "$(idem_de "$segundo")" \
    || { MOTIVO="$segundo no llegó a la espera: $FOTO"; return 1; }
  foto_par_estable pred_fila_abcd "${S_PID[T1]}" "$IDEM_T1" "${S_PID[T2]}" "$IDEM_T2" \
    || { MOTIVO="sin foto conjunta estable"; return 1; }
  FOTO_T1=$FOTO1; FOTO_T2=$FOTO2
  c=${S_PID[C]}
  [[ $(campo "$FOTO_T1" 5) == "$c" && $(campo "$FOTO_T2" 5) == "$c" ]] \
    || { MOTIVO="las sesiones no son independientes: T1[$FOTO_T1] T2[$FOTO_T2]"; return 1; }
  ins ses_revertir C || { MOTIVO="el control no liberó"; return 1; }
  for (( i = 0; i < PLAZO * 200; i++ )); do
    if ses_listo T1 "${S_TOK[T1]}"; then DELANTE=T1; OTRO=T2; break; fi
    if ses_listo T2 "${S_TOK[T2]}"; then DELANTE=T2; OTRO=T1; break; fi
    sleep 0.005
  done
  [[ -n $DELANTE ]] || { MOTIVO="ninguna sesión respondió dentro del plazo"; return 1; }
  rd=$(ins ses_resultado "$DELANTE") || { MOTIVO="sin resultado de $DELANTE"; return 1; }
  for (( i = 0; i < PLAZO * 100; i++ )); do
    ses_listo "$OTRO" "${S_TOK[$OTRO]}" && { MOTIVO="$OTRO terminó sin esperar a $DELANTE"; return 1; }
    FOTO=$(ins foto "${S_PID[$OTRO]}") || { MOTIVO="falló el monitor"; return 1; }
    if pred_espera_fila "$FOTO"; then
      f2=$(ins foto "${S_PID[$OTRO]}") || { MOTIVO="falló el monitor"; return 1; }
      [[ $f2 == "$FOTO" ]] && break
    fi
    sleep 0.01
  done
  pred_espera_fila "$FOTO" && [[ $(campo "$FOTO" 5) == "${S_PID[$DELANTE]}" && $(campo "$FOTO" 9) -ge 1 ]] \
    || { MOTIVO="$OTRO no espera la reserva de $DELANTE en el índice único: $FOTO"; return 1; }
  ins ses_fin "$DELANTE" || { MOTIVO="no se cerró $DELANTE"; return 1; }
  ro=$(ins ses_resultado "$OTRO") || { MOTIVO="$OTRO no respondió dentro del plazo"; return 1; }
  ins ses_fin "$OTRO" || { MOTIVO="no se cerró $OTRO"; return 1; }
  if [[ $DELANTE == T1 ]]; then RES_T1=$rd; RES_T2=$ro; else RES_T2=$rd; RES_T1=$ro; fi
}

# Misma clave en merma y carga (K8-CM): el control retiene el advisory de stock.
# El primero reserva su clave y queda esperando ese advisory; el segundo queda
# esperando en el índice único la reserva del primero.
correr_reserva_par() {   # orden
  local primero segundo
  MOTIVO=""; DELANTE=""; OTRO=""; RES_T1=""; RES_T2=""
  if [[ $1 == 1 ]]; then primero=T1; segundo=T2; else primero=T2; segundo=T1; fi
  DELANTE=$primero; OTRO=$segundo
  abrir_sesiones || return 1
  ins control_tomar || return 1
  ins ses_lanzar "$primero" "$ACTOR" "$(expr_de "$primero")" || { MOTIVO="no se lanzó $primero"; return 1; }
  foto_estable pred_adv_reservado "${S_PID[$primero]}" "$(idem_de "$primero")" \
    || { MOTIVO="$primero no reservó y esperó el advisory de stock: $FOTO"; return 1; }
  FOTO_T1=$FOTO
  ins ses_lanzar "$segundo" "$ACTOR" "$(expr_de "$segundo")" || { MOTIVO="no se lanzó $segundo"; return 1; }
  foto_estable pred_espera_fila "${S_PID[$segundo]}" \
    || { MOTIVO="$segundo no quedó esperando la reserva de $primero: $FOTO"; return 1; }
  FOTO_T2=$FOTO
  [[ $(campo "$FOTO_T2" 5) == "${S_PID[$primero]}" && $(campo "$FOTO_T1" 5) == "${S_PID[C]}" ]] \
    || { MOTIVO="cola distinta de control → $primero → $segundo: [$FOTO_T1] [$FOTO_T2]"; return 1; }
  ins control_liberar || { MOTIVO="el control no liberó"; return 1; }
  terminar_par
}

# Claves distintas, mismo advisory de stock (K8-SM): las dos reservan y esperan el
# advisory que retiene el control; el primero de la cola espera sólo al control y
# el otro también al primero.
correr_adv_par() {   # orden
  local primero segundo c p1 p2
  MOTIVO=""; DELANTE=""; OTRO=""; RES_T1=""; RES_T2=""
  if [[ $1 == 1 ]]; then primero=T1; segundo=T2; else primero=T2; segundo=T1; fi
  abrir_sesiones || return 1
  ins control_tomar || return 1
  ins ses_lanzar "$primero" "$ACTOR" "$(expr_de "$primero")" || { MOTIVO="no se lanzó $primero"; return 1; }
  foto_estable pred_adv_reservado "${S_PID[$primero]}" "$(idem_de "$primero")" \
    || { MOTIVO="$primero no llegó a la espera del advisory: $FOTO"; return 1; }
  ins ses_lanzar "$segundo" "$ACTOR" "$(expr_de "$segundo")" || { MOTIVO="no se lanzó $segundo"; return 1; }
  foto_estable pred_adv_reservado "${S_PID[$segundo]}" "$(idem_de "$segundo")" \
    || { MOTIVO="$segundo no llegó a la espera del advisory: $FOTO"; return 1; }
  foto_par_estable pred_adv_reservado "${S_PID[T1]}" "$IDEM_T1" "${S_PID[T2]}" "$IDEM_T2" \
    || { MOTIVO="sin foto conjunta estable"; return 1; }
  FOTO_T1=$FOTO1; FOTO_T2=$FOTO2
  c=${S_PID[C]}; p1=${S_PID[T1]}; p2=${S_PID[T2]}
  bloqueantes_permitidos "$FOTO_T1" "$c" "$p2" && bloqueantes_permitidos "$FOTO_T2" "$c" "$p1" \
    || { MOTIVO="bloqueante ajeno al caso: T1[$FOTO_T1] T2[$FOTO_T2]"; return 1; }
  contiene_pid "$FOTO_T1" "$c" && contiene_pid "$FOTO_T2" "$c" \
    || { MOTIVO="alguna sesión no espera al control"; return 1; }
  if contiene_pid "$FOTO_T2" "$p1" && ! contiene_pid "$FOTO_T1" "$p2"; then
    DELANTE=T1; OTRO=T2
  elif contiene_pid "$FOTO_T1" "$p2" && ! contiene_pid "$FOTO_T2" "$p1"; then
    DELANTE=T2; OTRO=T1
  else
    MOTIVO="cola ambigua: T1[$FOTO_T1] T2[$FOTO_T2]"; return 1
  fi
  ins control_liberar || { MOTIVO="el control no liberó"; return 1; }
  terminar_par
}

# Preparación común: stock inicial, jornada J1 abierta en CAM1 (vendedor V3) y el
# control sobre la fila de J1.
prep_carga_base() {   # stock
  preparar_stock "$1" || return 1
  ins jornada J1 "$CAM1" 30 "$V3" || return 1
  JORNADAS_CTRL=("$J1")
}

# I10-C — misma clave y mismo payload (4 de 10).
prep_I10_C() {
  prep_carga_base 10 || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(cargar "$IDEM_T1" "$J1" 4); EXPR_T2=$EXPR_T1
}
eval_I10_C() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && mismo_uuid && ok=0
  cerrar "$@" $ok "las dos 00000 con la misma operación" "$(ins invariantes \
    "una operación con la clave" "$(n_clave "$IDEM_T1" 1)" "una carga" "$(n_tipo carga 1)" \
    "un movimiento" "$(n_mov carga 1)" "depósito 6" "$(saldo_es "$DEP" 6)" "camión 4" "$(saldo_es "$UBI1" 4)" \
    "jornada cargada" "$(estado_es "$J1" cargada)" "sin saldos negativos" "$INV_STOCK" \
    "sin huérfanas" "$INV_HUERFANAS_STOCK")"
}
caso_I10_C() { repetir I10-C "1 2" prep_I10_C correr_fila_par eval_I10_C; }

# I11-C — misma clave, payload distinto (4 y 5 de 10).
prep_I11_C() {
  prep_carga_base 10 || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(cargar "$IDEM_T1" "$J1" 4); EXPR_T2=$(cargar "$IDEM_T2" "$J1" 5)
}
eval_I11_C() {
  local ok=1 q
  [[ $DELANTE == T1 ]] && q=4 || q=5
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_conflicto_idempotencia && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_conflicto_idempotencia" "$(ins invariantes \
    "una operación con la clave" "$(n_clave "$IDEM_T1" 1)" "un movimiento" "$(n_mov carga 1)" \
    "depósito sólo con la de delante" "$(saldo_es "$DEP" $(( 10 - q )))" "camión sólo con la de delante" "$(saldo_es "$UBI1" "$q")" \
    "sin saldos negativos" "$INV_STOCK" "sin huérfanas" "$INV_HUERFANAS_STOCK")"
}
caso_I11_C() { repetir I11-C "1 2" prep_I11_C correr_fila_par eval_I11_C; }

# K8-CC-a — dos cargas de la misma jornada, claves distintas, ambas caben (4 + 5 de 10).
prep_K8_CC_a() {
  prep_carga_base 10 || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(cargar "$IDEM_T1" "$J1" 4); EXPR_T2=$(cargar "$IDEM_T2" "$J1" 5)
}
eval_K8_CC_a() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && ! mismo_uuid && ok=0
  cerrar "$@" $ok "las dos 00000 con operaciones distintas" "$(ins invariantes \
    "dos cargas" "$(n_tipo carga 2)" "dos movimientos" "$(n_mov carga 2)" \
    "depósito 1" "$(saldo_es "$DEP" 1)" "camión 9" "$(saldo_es "$UBI1" 9)" \
    "jornada cargada" "$(estado_es "$J1" cargada)" "sin saldos negativos" "$INV_STOCK" \
    "sin huérfanas" "$INV_HUERFANAS_STOCK")"
}
caso_K8_CC_a() { repetir K8-CC-a "1 2" prep_K8_CC_a correr_fila_par eval_K8_CC_a; }

# K8-CC-b — dos cargas de la misma jornada que juntas exceden el depósito (6 + 6 de 10).
prep_K8_CC_b() {
  prep_carga_base 10 || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(cargar "$IDEM_T1" "$J1" 6); EXPR_T2=$(cargar "$IDEM_T2" "$J1" 6)
}
eval_K8_CC_b() {
  local ok=1
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_stock_insuficiente && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_stock_insuficiente" "$(ins invariantes \
    "una carga" "$(n_tipo carga 1)" "un movimiento" "$(n_mov carga 1)" \
    "la rechazada no reservó" "$(n_clave "$(idem_de "$OTRO")" 0)" \
    "depósito 4" "$(saldo_es "$DEP" 4)" "camión 6" "$(saldo_es "$UBI1" 6)" \
    "sin saldos negativos" "$INV_STOCK" "sin huérfanas" "$INV_HUERFANAS_STOCK")"
}
caso_K8_CC_b() { repetir K8-CC-b "1 2" prep_K8_CC_b correr_fila_par eval_K8_CC_b; }

# K8-CR — carga (T1) contra reasignación V3 → V6 (T2) de la misma jornada.
prep_K8_CR() {
  prep_carga_base 10 || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(cargar "$IDEM_T1" "$J1" 4); EXPR_T2=$(reasignar "$IDEM_T2" "$J1" "$V6")
}
eval_K8_CR() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
  cerrar "$@" $ok "las dos 00000 (equivale a algún orden serial)" "$(ins invariantes \
    "una carga" "$(n_tipo carga 1)" "una reasignación" "$(n_reas 1)" "un historial" "$(n_hist 1)" \
    "vendedor V6" "$(vend_de "$J1" "$V6")" "jornada cargada" "$(estado_es "$J1" cargada)" \
    "depósito 6" "$(saldo_es "$DEP" 6)" "camión 4" "$(saldo_es "$UBI1" 4)" \
    "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS" "sin huérfanas de stock" "$INV_HUERFANAS_STOCK")"
}
caso_K8_CR() { repetir K8-CR "1 2" prep_K8_CR correr_fila_par eval_K8_CR; }

# K8-CM — registrar_merma (T1, 3) contra registrar_carga (T2, 4) con la misma
# clave y el mismo advisory de stock.
prep_K8_CM() {
  prep_carga_base 10 || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(mermar "$IDEM_T1" 3); EXPR_T2=$(cargar "$IDEM_T2" "$J1" 4)
  CTRL_CLAVES=()
  CTRL_CLAVES+=("$(ks "$DEP" "$PROD1")")
}
eval_K8_CM() {
  local ok=1 inv
  if [[ $DELANTE == T1 ]]; then
    es_ok "$RES_T1" && es_err "$RES_T2" PT409 jornada_conflicto_idempotencia && ok=0
    inv=$(ins invariantes "una operación con la clave" "$(n_clave "$IDEM_T1" 1)" "una merma" "$(n_tipo merma 1)" \
      "ninguna carga" "$(n_tipo carga 0)" "depósito 7" "$(saldo_es "$DEP" 7)" "camión 0" "$(saldo_es "$UBI1" 0)" \
      "jornada abierta" "$(estado_es "$J1" abierta)" "sin saldos negativos" "$INV_STOCK" "sin huérfanas" "$INV_HUERFANAS_STOCK")
  else
    es_ok "$RES_T2" && es_err "$RES_T1" PT409 stock_conflicto_idempotencia && ok=0
    inv=$(ins invariantes "una operación con la clave" "$(n_clave "$IDEM_T1" 1)" "una carga" "$(n_tipo carga 1)" \
      "ninguna merma" "$(n_tipo merma 0)" "depósito 6" "$(saldo_es "$DEP" 6)" "camión 4" "$(saldo_es "$UBI1" 4)" \
      "jornada cargada" "$(estado_es "$J1" cargada)" "sin saldos negativos" "$INV_STOCK" "sin huérfanas" "$INV_HUERFANAS_STOCK")
  fi
  cerrar "$@" $ok "la primera 00000; la otra su propio PT409 de conflicto de idempotencia" "$inv"
}
caso_K8_CM() { repetir K8-CM "1 2" prep_K8_CM correr_reserva_par eval_K8_CM; }

# K8-SM — registrar_merma (T1, 6) contra registrar_carga (T2, 6), claves distintas,
# 10 en el depósito: el advisory de nivel 4 las serializa y el depósito no queda
# negativo.
prep_K8_SM() {
  prep_carga_base 10 || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(mermar "$IDEM_T1" 6); EXPR_T2=$(cargar "$IDEM_T2" "$J1" 6)
  CTRL_CLAVES=()
  CTRL_CLAVES+=("$(ks "$DEP" "$PROD1")")
}
eval_K8_SM() {
  local ok=1 inv
  if [[ $DELANTE == T1 ]]; then
    es_ok "$RES_T1" && es_err "$RES_T2" PT409 jornada_stock_insuficiente && ok=0
    inv=$(ins invariantes "una merma" "$(n_tipo merma 1)" "ninguna carga" "$(n_tipo carga 0)" \
      "la carga no reservó" "$(n_clave "$IDEM_T2" 0)" "depósito 4" "$(saldo_es "$DEP" 4)" \
      "jornada abierta" "$(estado_es "$J1" abierta)" "sin saldos negativos" "$INV_STOCK" "sin huérfanas" "$INV_HUERFANAS_STOCK")
  else
    es_ok "$RES_T2" && es_err "$RES_T1" PT409 stock_insuficiente && ok=0
    inv=$(ins invariantes "una carga" "$(n_tipo carga 1)" "ninguna merma" "$(n_tipo merma 0)" \
      "la merma no reservó" "$(n_clave "$IDEM_T1" 0)" "depósito 4" "$(saldo_es "$DEP" 4)" "camión 6" "$(saldo_es "$UBI1" 6)" \
      "jornada cargada" "$(estado_es "$J1" cargada)" "sin saldos negativos" "$INV_STOCK" "sin huérfanas" "$INV_HUERFANAS_STOCK")
  fi
  cerrar "$@" $ok "delante 00000; la otra su PT409 de saldo insuficiente" "$inv"
}
caso_K8_SM() { repetir K8-SM "1 2" prep_K8_SM correr_adv_par eval_K8_SM; }

# K8-CLAVE-C — misma clave en dos jornadas (J1 en CAM1, 2; J2 en CAM2, 3): no
# comparten bloqueos; la segunda queda esperando la reserva de la primera (paso 9).
prep_K8_CLAVE_C() {
  preparar_stock 10 || return 1
  ins jornada J1 "$CAM1" 30 "$V3" && ins jornada J2 "$CAM2" 30 "$V7" || return 1
  if [[ $J1 < $J2 ]]; then JORNADAS_CTRL=("$J1" "$J2"); else JORNADAS_CTRL=("$J2" "$J1"); fi
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(cargar "$IDEM_T1" "$J1" 2); EXPR_T2=$(cargar "$IDEM_T2" "$J2" 3)
}
eval_K8_CLAVE_C() {
  local ok=1 q jd jo ud uo
  if [[ $DELANTE == T1 ]]; then q=2; jd=$J1; jo=$J2; ud=$UBI1; uo=$UBI2; else q=3; jd=$J2; jo=$J1; ud=$UBI2; uo=$UBI1; fi
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_conflicto_idempotencia && ok=0
  cerrar "$@" $ok "primera 00000; la otra PT409 jornada_conflicto_idempotencia en el paso 9" "$(ins invariantes \
    "una operación con la clave" "$(n_clave "$IDEM_T1" 1)" "un movimiento" "$(n_mov carga 1)" \
    "depósito sólo con la primera" "$(saldo_es "$DEP" $(( 10 - q )))" "camión de la primera" "$(saldo_es "$ud" "$q")" \
    "camión de la otra vacío" "$(saldo_es "$uo" 0)" "jornada de la primera cargada" "$(estado_es "$jd" cargada)" \
    "jornada de la otra abierta" "$(estado_es "$jo" abierta)" "sin saldos negativos" "$INV_STOCK" \
    "sin huérfanas" "$INV_HUERFANAS_STOCK")"
}
caso_K8_CLAVE_C() { repetir K8-CLAVE-C "1 2" prep_K8_CLAVE_C correr_fila_indep eval_K8_CLAVE_C; }

CASOS+=(I10-C I11-C K8-CC-a K8-CC-b K8-CR K8-CM K8-SM K8-CLAVE-C)

# =============================================================================
# T6 — registrar_descarga (ADR-001 §18.4.9 I10, I11 y K11-d; §18.4.11). Casos
# nuevos, agregados sin modificar arnes.sh ni los casos anteriores:
#
#   I10-D   misma clave y mismo payload: las dos con la misma operación
#   I11-D   misma clave y payload distinto: una confirma, la otra PT409
#   K11-d   dos descargas con claves distintas, cada una dentro de lo cargado neto
#           pero con suma mayor: una confirma y la otra jornada_descarga_excede_carga
#   K8-CD   carga contra descarga de la misma jornada (regresión de K8)
#
# Como registrar_carga, la descarga no toma advisory de niveles 1 ni 2: el control
# retiene el FOR UPDATE de la jornada (correr_fila_par de T5). La jornada se
# prepara cargada con la RPC real. K11-a, K11-b y K11-c (contra confirmar_salida)
# quedan NO APLICABLES hasta T7.
# =============================================================================
descargar() { printf "public.registrar_descarga('%s', '%s', array['%s']::uuid[], array[%s], '%s')" "$1" "$2" "$PROD1" "$3" "$4"; }

# Carga confirmada como dato inicial del caso, con la RPC real y el dueño.
cargar_previa() {   # jornada cantidad
  local r
  nueva_clave
  r=$(ins _psql -v ON_ERROR_STOP=1 -U postgres -d "$BASE" -f - <<EOF | tail -1
begin;
select set_config('request.jwt.claims', '{"sub":"$ACTOR","role":"authenticated"}', true) is not null;
set local role authenticated;
select $(cargar "$CLAVE" "$1" "$2");
commit;
EOF
) && [[ $r =~ ^[0-9a-f-]{36}$ ]] || { MOTIVO="no se preparó la carga previa ($1, $2): $r"; return 1; }
}

# Stock 10 en el depósito, J1 en CAM1 cargada con 8, control sobre la fila de J1.
prep_descarga_base() {
  prep_carga_base 10 || return 1
  cargar_previa "$J1" 8
}

prep_I10_D() {
  prep_descarga_base || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(descargar "$IDEM_T1" "$J1" 3 "Sobrante"); EXPR_T2=$EXPR_T1
}
eval_I10_D() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && mismo_uuid && ok=0
  cerrar "$@" $ok "las dos 00000 con la misma operación" "$(ins invariantes \
    "una operación con la clave" "$(n_clave "$IDEM_T1" 1)" "una descarga" "$(n_tipo descarga 1)" \
    "un movimiento de descarga" "$(n_mov descarga 1)" "camión 5" "$(saldo_es "$UBI1" 5)" "depósito 5" "$(saldo_es "$DEP" 5)" \
    "jornada cargada" "$(estado_es "$J1" cargada)" "sin saldos negativos" "$INV_STOCK" \
    "sin huérfanas" "$INV_HUERFANAS_STOCK")"
}
caso_I10_D() { repetir I10-D "1 2" prep_I10_D correr_fila_par eval_I10_D; }

prep_I11_D() {
  prep_descarga_base || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(descargar "$IDEM_T1" "$J1" 3 "Sobrante"); EXPR_T2=$(descargar "$IDEM_T2" "$J1" 4 "Sobrante")
}
eval_I11_D() {
  local ok=1 q
  [[ $DELANTE == T1 ]] && q=3 || q=4
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_conflicto_idempotencia && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_conflicto_idempotencia" "$(ins invariantes \
    "una operación con la clave" "$(n_clave "$IDEM_T1" 1)" "un movimiento de descarga" "$(n_mov descarga 1)" \
    "camión sólo con la de delante" "$(saldo_es "$UBI1" $(( 8 - q )))" "depósito sólo con la de delante" "$(saldo_es "$DEP" $(( 2 + q )))" \
    "sin saldos negativos" "$INV_STOCK" "sin huérfanas" "$INV_HUERFANAS_STOCK")"
}
caso_I11_D() { repetir I11-D "1 2" prep_I11_D correr_fila_par eval_I11_D; }

# K11-d — dos descargas (5 y 5) sobre una carga neta de 8.
prep_K11_d() {
  prep_descarga_base || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(descargar "$IDEM_T1" "$J1" 5 "Sobrante A"); EXPR_T2=$(descargar "$IDEM_T2" "$J1" 5 "Sobrante B")
}
eval_K11_d() {
  local ok=1
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_descarga_excede_carga && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_descarga_excede_carga" "$(ins invariantes \
    "una descarga" "$(n_tipo descarga 1)" "un movimiento de descarga" "$(n_mov descarga 1)" \
    "la rechazada no reservó" "$(n_clave "$(idem_de "$OTRO")" 0)" \
    "camión 3" "$(saldo_es "$UBI1" 3)" "depósito 7" "$(saldo_es "$DEP" 7)" \
    "jornada cargada" "$(estado_es "$J1" cargada)" "sin saldos negativos" "$INV_STOCK" \
    "sin huérfanas" "$INV_HUERFANAS_STOCK")"
}
caso_K11_d() { repetir K11-d "1 2" prep_K11_d correr_fila_par eval_K11_d; }

# K8-CD — carga de 2 (T1) contra descarga de 3 (T2) de la misma jornada: las dos
# caben en cualquier orden serial.
prep_K8_CD() {
  prep_descarga_base || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(cargar "$IDEM_T1" "$J1" 2); EXPR_T2=$(descargar "$IDEM_T2" "$J1" 3 "Sobrante")
}
eval_K8_CD() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
  cerrar "$@" $ok "las dos 00000 (equivale a algún orden serial)" "$(ins invariantes \
    "dos cargas" "$(n_tipo carga 2)" "una descarga" "$(n_tipo descarga 1)" \
    "camión 7" "$(saldo_es "$UBI1" 7)" "depósito 3" "$(saldo_es "$DEP" 3)" \
    "jornada cargada" "$(estado_es "$J1" cargada)" "sin saldos negativos" "$INV_STOCK" \
    "sin huérfanas" "$INV_HUERFANAS_STOCK")"
}
caso_K8_CD() { repetir K8-CD "1 2" prep_K8_CD correr_fila_par eval_K8_CD; }

CASOS+=(I10-D I11-D K11-d K8-CD)

# =============================================================================
# T7 — confirmar_salida (ADR-001 §18.4.9 K11 y I10/I11; §18.4.11). Casos nuevos,
# agregados sin modificar arnes.sh ni los casos anteriores:
#
#   K11-a   salida (T1) contra descarga de toda la carga neta (T2): nunca las dos
#   K11-b   salida (T1) contra carga incremental (T2)
#   K11-c   dos salidas con claves distintas: una confirma, la otra estado_invalido
#   I10-S   dos salidas con la misma clave: la misma operación, una sola salida
#   I11-S   misma clave en dos jornadas: ON CONFLICT del paso 9
#
# confirmar_salida no toma advisory: el control retiene el FOR UPDATE de la
# jornada (correr_fila_par de T5) y la salida se serializa con la carga y la
# descarga de la misma jornada. Invariantes I-J2, I-J3 e I-J4 en cada repetición.
# =============================================================================
confirmar() { printf "public.confirmar_salida('%s', '%s')" "$1" "$2"; }
INV_IJ4="not exists (select 1 from public.jornadas j where j.estado = 'en_reparto'
   and not exists (select 1 from public.movimientos_stock m where m.jornada_id = j.id
                    and m.tipo_movimiento in ('carga', 'descarga') group by m.producto_id
                   having sum(case when m.tipo_movimiento = 'carga' then m.cantidad else -m.cantidad end) > 0))"
INV_UNA_SALIDA="not exists (select 1 from public.operaciones where tipo = 'salida_jornada'
   group by jornada_id having count(*) > 1)"

# K11-a — salida contra descarga de toda la carga neta (8).
prep_K11_a() {
  prep_descarga_base || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(confirmar "$IDEM_T1" "$J1"); EXPR_T2=$(descargar "$IDEM_T2" "$J1" 8 "Sin reparto")
}
eval_K11_a() {
  local ok=1 inv
  if [[ $DELANTE == T1 ]]; then
    es_ok "$RES_T1" && es_err "$RES_T2" PT409 jornada_estado_invalido && ok=0
    inv=$(ins invariantes "jornada en_reparto" "$(estado_es "$J1" en_reparto)" "una salida" "$(n_tipo salida_jornada 1)" \
      "ninguna descarga" "$(n_tipo descarga 0)" "camión 8" "$(saldo_es "$UBI1" 8)" \
      "I-J4" "$INV_IJ4" "sin saldos negativos" "$INV_STOCK" "sin huérfanas" "$INV_HUERFANAS_STOCK")
  else
    es_ok "$RES_T2" && es_err "$RES_T1" PT409 jornada_carga_neta_cero && ok=0
    inv=$(ins invariantes "jornada cargada" "$(estado_es "$J1" cargada)" "ninguna salida" "$(n_tipo salida_jornada 0)" \
      "una descarga" "$(n_tipo descarga 1)" "camión 0" "$(saldo_es "$UBI1" 0)" "depósito 10" "$(saldo_es "$DEP" 10)" \
      "I-J4" "$INV_IJ4" "sin saldos negativos" "$INV_STOCK" "sin huérfanas" "$INV_HUERFANAS_STOCK")
  fi
  cerrar "$@" $ok "salida primero: en_reparto y descarga estado_invalido; descarga primero: salida carga_neta_cero" "$inv"
}
caso_K11_a() { repetir K11-a "1 2" prep_K11_a correr_fila_par eval_K11_a; }

# K11-b — salida contra carga incremental (2).
prep_K11_b() {
  prep_descarga_base || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(confirmar "$IDEM_T1" "$J1"); EXPR_T2=$(cargar "$IDEM_T2" "$J1" 2)
}
eval_K11_b() {
  local ok=1 inv
  if [[ $DELANTE == T2 ]]; then
    es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
    inv=$(ins invariantes "jornada en_reparto" "$(estado_es "$J1" en_reparto)" "dos cargas" "$(n_tipo carga 2)" \
      "camión 10" "$(saldo_es "$UBI1" 10)" "depósito 0" "$(saldo_es "$DEP" 0)" \
      "I-J4" "$INV_IJ4" "sin saldos negativos" "$INV_STOCK" "sin huérfanas" "$INV_HUERFANAS_STOCK")
  else
    es_ok "$RES_T1" && es_err "$RES_T2" PT409 jornada_estado_invalido && ok=0
    inv=$(ins invariantes "jornada en_reparto" "$(estado_es "$J1" en_reparto)" "una carga" "$(n_tipo carga 1)" \
      "la carga no reservó" "$(n_clave "$IDEM_T2" 0)" "camión 8" "$(saldo_es "$UBI1" 8)" "depósito 2" "$(saldo_es "$DEP" 2)" \
      "I-J4" "$INV_IJ4" "sin saldos negativos" "$INV_STOCK" "sin huérfanas" "$INV_HUERFANAS_STOCK")
  fi
  cerrar "$@" $ok "carga primero: las dos 00000; salida primero: carga estado_invalido sin movimientos" "$inv"
}
caso_K11_b() { repetir K11-b "1 2" prep_K11_b correr_fila_par eval_K11_b; }

# K11-c — dos salidas con claves distintas.
prep_K11_c() {
  prep_descarga_base || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(confirmar "$IDEM_T1" "$J1"); EXPR_T2=$(confirmar "$IDEM_T2" "$J1")
}
eval_K11_c() {
  local ok=1
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_estado_invalido && ok=0
  cerrar "$@" $ok "delante 00000; la otra PT409 jornada_estado_invalido" "$(ins invariantes \
    "jornada en_reparto" "$(estado_es "$J1" en_reparto)" "una salida" "$(n_tipo salida_jornada 1)" \
    "la rechazada no reservó" "$(n_clave "$(idem_de "$OTRO")" 0)" "una salida por jornada" "$INV_UNA_SALIDA" \
    "I-J4" "$INV_IJ4" "sin huérfanas" "$INV_HUERFANAS_STOCK")"
}
caso_K11_c() { repetir K11-c "1 2" prep_K11_c correr_fila_par eval_K11_c; }

# I10-S — dos salidas con la misma clave (K11-c con la misma clave).
prep_I10_S() {
  prep_descarga_base || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(confirmar "$IDEM_T1" "$J1"); EXPR_T2=$EXPR_T1
}
eval_I10_S() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && mismo_uuid && ok=0
  cerrar "$@" $ok "las dos 00000 con la misma operación" "$(ins invariantes \
    "jornada en_reparto" "$(estado_es "$J1" en_reparto)" "una operación con la clave" "$(n_clave "$IDEM_T1" 1)" \
    "una salida" "$(n_tipo salida_jornada 1)" "una salida por jornada" "$INV_UNA_SALIDA" "I-J4" "$INV_IJ4")"
}
caso_I10_S() { repetir I10-S "1 2" prep_I10_S correr_fila_par eval_I10_S; }

# I11-S — misma clave sobre dos jornadas cargadas (J1 con 8, J2 con 2).
prep_I11_S() {
  preparar_stock 10 || return 1
  ins jornada J1 "$CAM1" 30 "$V3" && ins jornada J2 "$CAM2" 30 "$V7" || return 1
  cargar_previa "$J1" 8 && cargar_previa "$J2" 2 || return 1
  if [[ $J1 < $J2 ]]; then JORNADAS_CTRL=("$J1" "$J2"); else JORNADAS_CTRL=("$J2" "$J1"); fi
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(confirmar "$IDEM_T1" "$J1"); EXPR_T2=$(confirmar "$IDEM_T2" "$J2")
}
eval_I11_S() {
  local ok=1 jd jo
  if [[ $DELANTE == T1 ]]; then jd=$J1; jo=$J2; else jd=$J2; jo=$J1; fi
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_conflicto_idempotencia && ok=0
  cerrar "$@" $ok "primera 00000; la otra PT409 jornada_conflicto_idempotencia en el paso 9" "$(ins invariantes \
    "una operación con la clave" "$(n_clave "$IDEM_T1" 1)" "una salida" "$(n_tipo salida_jornada 1)" \
    "jornada de la primera en_reparto" "$(estado_es "$jd" en_reparto)" "jornada de la otra cargada" "$(estado_es "$jo" cargada)" \
    "I-J4" "$INV_IJ4")"
}
caso_I11_S() { repetir I11-S "1 2" prep_I11_S correr_fila_indep eval_I11_S; }

CASOS+=(K11-a K11-b K11-c I10-S I11-S)
