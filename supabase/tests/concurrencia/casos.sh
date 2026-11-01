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
  _psql -v ON_ERROR_STOP=1 -U postgres -d "$BASE" -f - <<EOF | tail -1
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
  id=$(preparar_jornada "$CLAVE" "$2" "$3" "$4")
  [[ $id =~ ^[0-9a-f-]{36}$ ]] || { MOTIVO="no se preparó la jornada ($2, +$3, $4): $id"; return 1; }
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

# Invariantes: pares descripción/condición. Imprime el testigo positivo INV_OK
# sólo si la consulta se ejecutó sin error y todas las condiciones se cumplen.
# Si falla alguna, imprime «INV_FALLA: <descripciones>»; si la consulta no se
# pudo ejecutar, «INV_ERROR_SQL(rc=N): <error>». Una salida vacía nunca es
# éxito (T3-C1, H-01): cerrar() exige el testigo.
invariantes() {
  local sql="select concat_ws('; '" d c out rc
  while (( $# >= 2 )); do
    d=$1; c=$2; shift 2
    sql+=", case when not coalesce(($c), false) then '${d//\'/\'\'}' end"
  done
  sql+=")"
  out=$(sql_pg "$BASE" "select case when f = '' then 'INV_OK' else f end from ($sql) as s(f)" 2>&1)
  rc=$?
  if (( rc != 0 )); then
    printf 'INV_ERROR_SQL(rc=%s): %s' "$rc" "${out//$'\n'/ }"
    return 1
  fi
  if [[ $out == INV_OK ]]; then
    printf 'INV_OK'
    return 0
  fi
  printf 'INV_FALLA: %s' "${out:-sin salida}"
  return 1
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
  if (( ok == 0 )); then registrar "$c" "$o" "$r" PASS "$esp" "$obt"
  else registrar "$c" "$o" "$r" FAIL "$esp" "$obt" "$det"; fi
}

# Repite un caso R veces en cada orden, con una base nueva por repetición.
repetir() {   # caso "ordenes" preparar ejecutor evaluar
  local caso=$1 ordenes=$2 prep=$3 ejec=$4 eval=$5 o r antes n
  for o in $ordenes; do
    for (( r = 1; r <= R; r++ )); do
      antes=$TOTAL
      nueva_base
      MOTIVO=""; RES_T1=""; RES_T2=""; DELANTE=""
      if ! $prep; then
        registrar "$caso" "$o" "$r" FAIL "preparación" "-" "$MOTIVO"
      elif $ejec "$o"; then
        $eval "$caso" "$o" "$r"
      else
        registrar "$caso" "$o" "$r" FAIL "mecanismo del caso" "T1=$(res_corto "${RES_T1:-?|}") T2=$(res_corto "${RES_T2:-?|}")" "$MOTIVO"
      fi
      # Exactamente un veredicto por repetición (T3-C1): ninguno o varios es FAIL.
      n=$(( TOTAL - antes ))
      (( n == 1 )) || registrar "$caso" "$o" "$r" FAIL "un veredicto por repetición" "$n veredictos"
      borrar_base "$BASE"
      DEADLOCKS_CASOS=$(( DEADLOCKS_CASOS + DEADLOCKS_ULTIMA_BASE ))
    done
  done
}

# -----------------------------------------------------------------------------
# ORACULO — autoverificación del oráculo de invariantes (T3-C1, H-01). Antes de
# AUTO y de los casos: una condición verdadera debe dar el testigo; una falsa,
# un error SQL real (división por cero, tabla y columna inexistentes), la cadena
# vacía y una concatenación con una falla deben ser rechazados. Si no, el arnés
# termina con exit 1 sin medir nada.
# -----------------------------------------------------------------------------
caso_ORACULO() {
  local inv
  BASE=oraculo
  sql_admin postgres "create database oraculo template arnes owner postgres" >/dev/null \
    || error_entorno "no se creó la base de la autoverificación del oráculo"
  inv=$(invariantes "verdadera" "true")
  if inv_ok "$inv"; then registrar ORACULO - verdadera PASS "INV_OK" "$inv"
  else registrar ORACULO - verdadera FAIL "INV_OK" "$inv"; fi
  local d c
  for d in falsa division_por_cero tabla_inexistente columna_inexistente; do
    case $d in
      falsa) c="false" ;;
      division_por_cero) c="(select 1 / 0) = 1" ;;
      tabla_inexistente) c="(select count(*) from public.tabla_inexistente) = 0" ;;
      columna_inexistente) c="(select count(columna_inexistente) from public.jornadas) = 0" ;;
    esac
    inv=$(invariantes "$d" "$c")
    if inv_ok "$inv"; then registrar ORACULO - "$d" FAIL "rechazo" "$inv"
    else registrar ORACULO - "$d" PASS "rechazo" "${inv:0:60}"; fi
  done
  if inv_ok ""; then registrar ORACULO - vacia FAIL "rechazo" "aceptada"
  else registrar ORACULO - vacia PASS "rechazo" "rechazada"; fi
  inv="$(invariantes "verdadera" "true")$(invariantes "falsa" "false")"
  if inv_ok "$inv"; then registrar ORACULO - concatenada FAIL "rechazo" "$inv"
  else registrar ORACULO - concatenada PASS "rechazo" "${inv:0:60}"; fi
  borrar_base oraculo
  DEADLOCKS_CASOS=$(( DEADLOCKS_CASOS + DEADLOCKS_ULTIMA_BASE ))
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
  local o r primero segundo r1 r2 ok
  BASE=auto
  sql_admin postgres "create database auto template arnes owner postgres" >/dev/null
  sql_pg auto "create schema zz_arnes;
create function zz_arnes.reasignar_ingenua(p_empresa uuid, p_vigente uuid, p_nuevo uuid, p_puerta bigint)
returns void language plpgsql as \$\$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'jornadas:vendedor:' || p_empresa::text || ':' || p_vigente::text, 0));
  perform pg_catalog.pg_advisory_xact_lock_shared(p_puerta);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'jornadas:vendedor:' || p_empresa::text || ':' || p_nuevo::text, 0));
end \$\$;" >/dev/null || error_entorno "no se creó la función de control de AUTO"
  PUERTA=$(clave_txt 'zz_arnes:puerta')
  for o in 1 2; do
    for (( r = 1; r <= R; r++ )); do
      MOTIVO=""; RES_T1=""; RES_T2=""; DELANTE=""
      if [[ $o == 1 ]]; then primero=T1; segundo=T2; else primero=T2; segundo=T1; fi
      EXPR_T1="zz_arnes.reasignar_ingenua('$EMPRESA', '$V3', '$V6', $PUERTA)"
      EXPR_T2="zz_arnes.reasignar_ingenua('$EMPRESA', '$V6', '$V3', $PUERTA)"
      CTRL_CLAVES=("$PUERTA")
      ok=1
      if ses_abrir C auto && ses_abrir T1 auto && ses_abrir T2 auto && control_tomar; then
        ses_lanzar "$primero" "" "$(expr_de "$primero")"
        ses_lanzar "$segundo" "" "$(expr_de "$segundo")"
        if foto_par_estable pred_auto "${S_PID[T1]}" "" "${S_PID[T2]}" "" && control_liberar; then
          RES_T1=$(ses_resultado T1); RES_T2=$(ses_resultado T2)
          ses_fin T1; ses_fin T2
          r1=${RES_T1%%|*}; r2=${RES_T2%%|*}
          [[ "$r1 $r2" == "00000 40P01" || "$r1 $r2" == "40P01 00000" ]] && ok=0
        else
          MOTIVO="las sesiones no llegaron a la puerta: T1[$FOTO1] T2[$FOTO2]"
        fi
      else
        MOTIVO="no se preparó la autoverificación"
      fi
      if (( ok == 0 )); then registrar AUTO "$o" "$r" PASS "{00000,40P01}" "T1=${RES_T1%%|*} T2=${RES_T2%%|*}"
      else registrar AUTO "$o" "$r" FAIL "{00000,40P01}" "T1=${RES_T1%%|*} T2=${RES_T2%%|*}" "${MOTIVO:-sin 40P01}"; fi
      cerrar_todas
    done
  done
  borrar_base auto
  DEADLOCKS_AUTO=$DEADLOCKS_ULTIMA_BASE
  if (( DEADLOCKS_AUTO == 2 * R )); then
    registrar AUTO-CONT - - PASS "deadlocks=$(( 2 * R ))" "deadlocks=$DEADLOCKS_AUTO"
  else
    registrar AUTO-CONT - - FAIL "deadlocks=$(( 2 * R ))" "deadlocks=$DEADLOCKS_AUTO"
  fi
}

# -----------------------------------------------------------------------------
# I10-R — reasignar_vendedor, misma clave y mismo payload. Las dos leen el
# vigente V3 en el paso 6 y esperan en el paso 7; la segunda obtiene los
# bloqueos con el vigente ya cambiado a V6: sin el paso 8a, 8b la rechazaría.
# -----------------------------------------------------------------------------
prep_I10_R() {
  jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$EXPR_T1
  CTRL_CLAVES=("$(kv "$V3")" "$(kv "$V6")")
}
eval_I10_R() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && mismo_uuid && ok=0
  cerrar "$@" $ok "las dos 00000 con el mismo uuid" "$(invariantes \
    "una operación" "$(n_reas 1)" "un historial" "$(n_hist 1)" "clave única" "$(n_clave "$IDEM_T1" 1)" \
    "vendedor final V6" "$(vend_de "$J1" "$V6")" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_I10_R() { repetir I10-R "1 2" prep_I10_R correr_par eval_I10_R; }

# I11-R — misma clave, payload distinto (T1 → V6, T2 → V7): conflicto en 8a,
# nunca jornada_estado_invalido; efectos sólo de la que confirmó.
prep_I11_R() {
  jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(reasignar "$IDEM_T2" "$J1" "$V7")
  CTRL_CLAVES=("$(kv "$V3")" "$(kv "$V6")" "$(kv "$V7")")
}
eval_I11_R() {
  local ok=1 dest
  [[ $DELANTE == T1 ]] && dest=$V6 || dest=$V7
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_conflicto_idempotencia && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_conflicto_idempotencia" "$(invariantes \
    "una operación" "$(n_reas 1)" "un historial" "$(n_hist 1)" \
    "vendedor final = destino de la sesión delante" "$(vend_de "$J1" "$dest")" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_I11_R() { repetir I11-R "1 2" prep_I11_R correr_par eval_I11_R; }

# I10-A — abrir_jornada, misma clave y mismo payload; el control retiene camión
# y vendedor (tabla A-02). No distingue 8a del ON CONFLICT del paso 9.
prep_I10_A() {
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$EXPR_T1
  CTRL_CLAVES=("$(kc "$CAM1")" "$(kv "$V3")")
}
eval_aper_mismo() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && mismo_uuid && ok=0
  cerrar "$@" $ok "las dos 00000 con el mismo uuid de jornada" "$(invariantes \
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
  jornada J1 "$CAM1" 30 "$V3" && jornada J2 "$CAM2" 30 "$V6" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(reasignar "$IDEM_T2" "$J2" "$V3")
  CTRL_CLAVES=("$(kv "$V3")" "$(kv "$V6")")
}
eval_K1() {
  local ok=1
  es_err "$RES_T1" PT409 jornada_vendedor_ocupado && es_err "$RES_T2" PT409 jornada_vendedor_ocupado && ok=0
  cerrar "$@" $ok "las dos PT409 jornada_vendedor_ocupado" "$(invariantes \
    "sin operaciones" "$(n_reas 0)" "sin historial" "$(n_hist 0)" \
    "J1 conserva V3" "$(vend_de "$J1" "$V3")" "J2 conserva V6" "$(vend_de "$J2" "$V6")" "I-J1" "$INV_IJ1")"
}
caso_K1() { repetir K1 "1 2" prep_K1 correr_par eval_K1; }

# K2 — I-1b cadena: J1 (V3) → V7 y J2 (V6) → V3. Resultado del orden serial de
# la cola observada: T1 delante → las dos confirman; T2 delante → T2 PT409
# jornada_vendedor_ocupado y T1 confirma.
prep_K2() {
  jornada J1 "$CAM1" 30 "$V3" && jornada J2 "$CAM2" 30 "$V6" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V7"); EXPR_T2=$(reasignar "$IDEM_T2" "$J2" "$V3")
  CTRL_CLAVES=("$(kv "$V3")" "$(kv "$V6")" "$(kv "$V7")")
}
eval_K2() {
  local ok=1
  if [[ $DELANTE == T1 ]]; then
    es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
    cerrar "$@" $ok "serial T1;T2: las dos 00000" "$(invariantes \
      "dos operaciones" "$(n_reas 2)" "dos historiales" "$(n_hist 2)" \
      "J1 → V7" "$(vend_de "$J1" "$V7")" "J2 → V3" "$(vend_de "$J2" "$V3")" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  else
    es_ok "$RES_T1" && es_err "$RES_T2" PT409 jornada_vendedor_ocupado && ok=0
    cerrar "$@" $ok "serial T2;T1: T2 PT409 jornada_vendedor_ocupado, T1 00000" "$(invariantes \
      "una operación" "$(n_reas 1)" "un historial" "$(n_hist 1)" \
      "J1 → V7" "$(vend_de "$J1" "$V7")" "J2 conserva V6" "$(vend_de "$J2" "$V6")" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  fi
}
caso_K2() { repetir K2 "1 2" prep_K2 correr_par eval_K2; }

# K3 — I-2 apertura con el vigente: T1 reasigna J1 (V3, f) → V6; T2 abre
# (camión 2, f, V3). Se encolan en adv(V3).
prep_K3() {
  jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM2" 30 "$V3")
  CTRL_CLAVES=("$(kv "$V3")")
}
eval_K3() {
  local ok=1
  if [[ $DELANTE == T1 ]]; then
    es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
    cerrar "$@" $ok "serial T1;T2: las dos 00000" "$(invariantes \
      "J1 → V6" "$(vend_de "$J1" "$V6")" "apertura de camión 2 con V3" "$(jorn_en "$CAM2" 30 "$V3" 1)" \
      "una reasignación" "$(n_reas 1)" "dos aperturas" "$(n_aper 2)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  else
    es_err "$RES_T2" PT409 jornada_vendedor_ocupado && es_ok "$RES_T1" && ok=0
    cerrar "$@" $ok "serial T2;T1: T2 PT409 jornada_vendedor_ocupado, T1 00000" "$(invariantes \
      "J1 → V6" "$(vend_de "$J1" "$V6")" "sin jornada del camión 2" "$(n_jorn 1)" \
      "una reasignación" "$(n_reas 1)" "una apertura" "$(n_aper 1)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  fi
}
caso_K3() { repetir K3 "1 2" prep_K3 correr_par eval_K3; }

# K4 — I-2 hacia el nuevo: T1 reasigna J1 (V3, f) → V6; T2 abre (camión 2, f,
# V6). Se encolan en adv(V6): una confirma y la otra PT409 jornada_vendedor_ocupado.
prep_K4() {
  jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM2" 30 "$V6")
  CTRL_CLAVES=("$(kv "$V6")")
}
eval_K4() {
  local ok=1
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_vendedor_ocupado && ok=0
  if [[ $DELANTE == T1 ]]; then
    cerrar "$@" $ok "T1 00000; T2 PT409 jornada_vendedor_ocupado" "$(invariantes \
      "J1 → V6" "$(vend_de "$J1" "$V6")" "sin jornada del camión 2" "$(n_jorn 1)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  else
    cerrar "$@" $ok "T2 00000; T1 PT409 jornada_vendedor_ocupado" "$(invariantes \
      "J1 conserva V3" "$(vend_de "$J1" "$V3")" "apertura de camión 2 con V6" "$(jorn_en "$CAM2" 30 "$V6" 1)" \
      "sin reasignaciones" "$(n_reas 0)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  fi
}
caso_K4() { repetir K4 "1 2" prep_K4 correr_par eval_K4; }

# K9-R — el vigente cambia entre los pasos 6 y 8b por otra operación confirmada
# con DISTINTA clave: la sesión de atrás recibe PT409 jornada_estado_invalido
# (8b), sin reserva ni historial; reintentar con la misma clave confirma.
prep_K9_R() {
  jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(reasignar "$IDEM_T2" "$J1" "$V7")
  CTRL_CLAVES=("$(kv "$V3")" "$(kv "$V6")" "$(kv "$V7")")
}
eval_K9_R() {
  local ok=1 inv_rech reint dest_otro dest_del clave_otro
  if [[ $OTRO == T1 ]]; then dest_otro=$V6; dest_del=$V7; clave_otro=$IDEM_T1
  else dest_otro=$V7; dest_del=$V6; clave_otro=$IDEM_T2; fi
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_estado_invalido && ok=0
  inv_rech=$(invariantes "el rechazo no reservó la clave" "$(n_clave "$clave_otro" 0)" \
    "un historial" "$(n_hist 1)" "J1 → destino de delante" "$(vend_de "$J1" "$dest_del")")
  # Reintento con la misma clave y el mismo payload: la RPC recalcula el vigente.
  ses_lanzar "$OTRO" "$ACTOR" "$(expr_de "$OTRO")"
  reint=$(ses_resultado "$OTRO"); ses_fin "$OTRO"
  es_ok "$reint" || ok=1
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_estado_invalido; reintento 00000" "${inv_rech}$(invariantes \
    "dos operaciones tras el reintento" "$(n_reas 2)" "dos historiales" "$(n_hist 2)" \
    "J1 → destino del reintento" "$(vend_de "$J1" "$dest_otro")" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
  [[ $ok == 0 ]] || echo "    reintento=$(res_corto "$reint")" | tee -a "$SALIDA"
}
caso_K9_R() { repetir K9-R "1 2" prep_K9_R correr_par eval_K9_R; }

# -----------------------------------------------------------------------------
# K10 — aperturas concurrentes (claves distintas salvo d y e).
# -----------------------------------------------------------------------------
prep_K10_a() {  # mismo camión y misma fecha, vendedores distintos
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM1" 30 "$V6")
  CTRL_CLAVES=("$(kc "$CAM1")")
}
eval_K10_a() {
  local ok=1 o
  o=$(res_de "$OTRO")
  es_ok "$(res_de "$DELANTE")" \
    && { es_err "$o" PT409 jornada_duplicada || es_err "$o" PT409 jornada_camion_con_jornada_abierta; } && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_duplicada o jornada_camion_con_jornada_abierta" "$(invariantes \
    "una jornada" "$(n_jorn 1)" "una apertura" "$(n_aper 1)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_K10_a() { repetir K10-a "1 2" prep_K10_a correr_par eval_K10_a; }

prep_K10_b() {  # mismo camión, fechas distintas
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM1" 31 "$V6")
  CTRL_CLAVES=("$(kc "$CAM1")")
}
eval_K10_b() {
  local ok=1
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_camion_con_jornada_abierta && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_camion_con_jornada_abierta" "$(invariantes \
    "una jornada" "$(n_jorn 1)" "una apertura" "$(n_aper 1)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_K10_b() { repetir K10-b "1 2" prep_K10_b correr_par eval_K10_b; }

prep_K10_c() {  # mismo vendedor y misma fecha, camiones distintos: cola en adv(V3)
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM2" 30 "$V3")
  CTRL_CLAVES=("$(kv "$V3")")
}
eval_K10_c() {
  local ok=1
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_vendedor_ocupado && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_vendedor_ocupado" "$(invariantes \
    "una jornada" "$(n_jorn 1)" "una apertura" "$(n_aper 1)" "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_K10_c() { repetir K10-c "1 2" prep_K10_c correr_par eval_K10_c; }

prep_K10_d() {  # misma clave y mismos parámetros; el control retiene sólo el camión
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$EXPR_T1
  CTRL_CLAVES=("$(kc "$CAM1")")
}
caso_K10_d() { repetir K10-d "1 2" prep_K10_d correr_par eval_aper_mismo; }

prep_K10_e() {  # misma clave y distinto vendedor
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM1" 30 "$V3"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM1" 30 "$V6")
  CTRL_CLAVES=("$(kc "$CAM1")")
}
eval_K10_e() {
  local ok=1 vd
  [[ $DELANTE == T1 ]] && vd=$V3 || vd=$V6
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_conflicto_idempotencia && ok=0
  cerrar "$@" $ok "delante 00000; el otro PT409 jornada_conflicto_idempotencia" "$(invariantes \
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
  jornada J1 "$CAM1" 30 "$V3" && jornada J2 "$CAM2" 30 "$V7" || return 1
  nueva_clave; IDEM_T1=$CLAVE; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(reasignar "$IDEM_T2" "$J2" "$V9")
  CTRL_CLAVES=("$(kv "$V3")" "$(kv "$V7")")
}
eval_K8_CLAVE() {
  local ok=1 jd jo vd vo
  if [[ $DELANTE == T1 ]]; then jd=$J1; vd=$V6; jo=$J2; vo=$V7; else jd=$J2; vd=$V9; jo=$J1; vo=$V3; fi
  es_ok "$(res_de "$DELANTE")" && es_err "$(res_de "$OTRO")" PT409 jornada_conflicto_idempotencia && ok=0
  cerrar "$@" $ok "primera 00000; la otra PT409 jornada_conflicto_idempotencia en el paso 9" "$(invariantes \
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
  CTRL_CLAVES=("$(kc "$CAM3")")
}
correr_baja_en_espera() {
  MOTIVO=""; DELANTE=""; OTRO=""; RES_T1=""; RES_T2=""
  ses_abrir C "$BASE" && ses_abrir T1 "$BASE" && ses_abrir T2 "$BASE" || { MOTIVO="no se abrieron las sesiones"; return 1; }
  control_tomar || return 1
  ses_lanzar T1 "$ACTOR" "$EXPR_T1"
  foto_estable pred_abcd "${S_PID[T1]}" "$IDEM_T1" || { MOTIVO="T1 no llegó a la espera: $FOTO"; return 1; }
  ses_lanzar T2 "$ACTOR" "$EXPR_T2"
  RES_T2=$(ses_resultado T2) || { MOTIVO="la baja no terminó: espera espuria ($(foto "${S_PID[T2]}"))"; return 1; }
  ses_fin T2
  foto_estable pred_abcd "${S_PID[T1]}" "$IDEM_T1" && [[ $(campo "$FOTO" 5) == "${S_PID[C]}" ]] \
    || { MOTIVO="T1 dejó de esperar sólo al control: $FOTO"; return 1; }
  control_liberar
  RES_T1=$(ses_resultado T1) || { MOTIVO="T1 no respondió"; return 1; }
  ses_fin T1
}
eval_K8_BAJA_a() {
  local ok=1
  es_ok "$RES_T2" && es_err "$RES_T1" PT409 jornada_camion_inactivo && ok=0
  cerrar "$@" $ok "baja 00000; apertura PT409 jornada_camion_inactivo" "$(invariantes \
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
  cerrar "$@" $ok "apertura 00000; baja 00000 sin esperar" "$(invariantes \
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
  jornada J1 "$CAM1" 30 "$V3" && jornada J2 "$CAM2" 30 "$V7" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(reasignar "$IDEM_T2" "$J2" "$V9")
}
eval_S_ESP_RR() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
  cerrar "$@" $ok "las dos 00000 sin esperarse" "$(invariantes \
    "dos operaciones" "$(n_reas 2)" "J1 → V6" "$(vend_de "$J1" "$V6")" "J2 → V9" "$(vend_de "$J2" "$V9")" \
    "I-J1" "$INV_IJ1" "sin huérfanas" "$INV_HUERFANAS")"
}
caso_S_ESP_RR() { repetir S-ESP-RR "1 2" prep_S_ESP_RR correr_secuencial eval_S_ESP_RR; }

prep_S_ESP_RA() {
  jornada J1 "$CAM1" 30 "$V3" || return 1
  nueva_clave; IDEM_T1=$CLAVE; nueva_clave; IDEM_T2=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$J1" "$V6"); EXPR_T2=$(abrir "$IDEM_T2" "$CAM3" 30 "$V9")
}
eval_S_ESP_RA() {
  local ok=1
  es_ok "$RES_T1" && es_ok "$RES_T2" && ok=0
  cerrar "$@" $ok "las dos 00000 sin esperarse" "$(invariantes \
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
  jornada JO "$([[ $dias == 30 ]] && echo "$CAM1" || echo "$CAM2")" "$dias" "$1" || return 1
  nueva_clave; IDEM_T1=$CLAVE
  EXPR_T1=$(reasignar "$IDEM_T1" "$JO" "$2")
  CTRL_CLAVES=("$3")
  OBS_RET=$(lista "$(kv "$1")" "$(kv "$2")")
}
eval_O() {
  local ok=1
  es_ok "$RES_T1" && [[ -z $MOTIVO ]] && ok=0
  cerrar "$@" $ok "concedidos=[$OBS_G] esperado=[$OBS_W] xid NULL; al volver retiene [$OBS_RET]" \
    "$(invariantes "sin efectos (revertido)" "$(n_clave "$IDEM_T1" 0)")"
}
prep_O_R1() { prep_O_R "$V3" "$V6" "$(kv "$V3")" && OBS_G="" && OBS_W=$(kv "$V3"); }
prep_O_R2() { prep_O_R "$V3" "$V6" "$(kv "$V6")" && OBS_G=$(kv "$V3") && OBS_W=$(kv "$V6"); }
prep_O_R3() { prep_O_R "$V7" "$V3" "$(kv "$V7")" && OBS_G=$(kv "$V3") && OBS_W=$(kv "$V7"); }
prep_O_R4() { prep_O_R "$V7" "$V3" "$(kv "$V3")" && OBS_G="" && OBS_W=$(kv "$V3"); }
prep_O_A() {
  nueva_clave; IDEM_T1=$CLAVE
  EXPR_T1=$(abrir "$IDEM_T1" "$CAM3" 30 "$V9")
  OBS_RET=$(lista "$(kc "$CAM3")" "$(kv "$V9")")
}
prep_O_A1() { prep_O_A && CTRL_CLAVES=("$(kv "$V9")") && OBS_G=$(kc "$CAM3") && OBS_W=$(kv "$V9"); }
prep_O_A2() { prep_O_A && CTRL_CLAVES=("$(kc "$CAM3")") && OBS_G="" && OBS_W=$(kc "$CAM3"); }
caso_O_R1() { repetir O-R1 "-" prep_O_R1 correr_observado eval_O; }
caso_O_R2() { repetir O-R2 "-" prep_O_R2 correr_observado eval_O; }
caso_O_R3() { repetir O-R3 "-" prep_O_R3 correr_observado eval_O; }
caso_O_R4() { repetir O-R4 "-" prep_O_R4 correr_observado eval_O; }
caso_O_A1() { repetir O-A1 "-" prep_O_A1 correr_observado eval_O; }
caso_O_A2() { repetir O-A2 "-" prep_O_A2 correr_observado eval_O; }
