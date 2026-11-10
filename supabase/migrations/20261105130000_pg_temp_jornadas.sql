-- B1 — Endurecimiento pg_temp de las RPC de jornadas (plan de remediación
-- pg_temp, alternativa A; ADR-001 §17.1). Validación exclusivamente
-- local/staging. Prohibido aplicar en producción.
--
-- Defecto (hallazgo ALTO heredado): con search_path = '' PostgreSQL busca pg_temp
-- ANTES que pg_catalog para tipos y relaciones no calificados. abrir_jornada y
-- reasignar_vendedor declaran variables «uuid», «text» y «date» sin esquema y
-- usan casts «::text» en la huella de idempotencia y en las claves de advisory
-- lock: un dominio pg_temp.uuid / pg_temp.text / pg_temp.date creado por una
-- sesión que puede asumir authenticated (TEMP por PUBLIC) ejecuta su CHECK como
-- propietario_rpc, dentro de operaciones que escriben jornadas, operaciones e
-- historial (reproducido: abierta → cerrada sin operación).
--
-- Cambio: ÚNICAMENTE 43 calificaciones («uuid» → «pg_catalog.uuid», «text» →
-- «pg_catalog.text», «date» → «pg_catalog.date»):
--   abrir_jornada (19: 10 declaraciones + 2 literales tipados «date '…'» +
--     2 casts de la huella + 4 de las claves de lock + 1 cast «::date» de v_hoy);
--   reasignar_vendedor (24: 12 declaraciones + 2 casts de la huella + 10 de las
--     claves de lock).
-- «boolean» es palabra clave y resuelve siempre a pg_catalog. Los casts a
-- pg_catalog.text / pg_catalog.date son el mismo tipo (mismo oid): la huella v1
-- y las claves de lock no cambian, y los replays de operaciones anteriores
-- siguen coincidiendo.
--
-- Base (decisiones humanas del 04/11/2026: E-SL1 aprobada para validación
-- controlada y alternativa B): cuerpos con la guarda GET/HEAD de
-- 20261104120000 (SHA-256 f6f88764… y 381e59c4…). La guarda (paso 0,
-- transaction_read_only = on → 25006) no contiene tipos sin calificar y se
-- conserva byte a byte como primera sentencia, antes de la identidad y de todo
-- replay: se verifica en los cuerpos nuevos y en los instalados.
--
-- Los cuerpos nuevos están escritos explícitamente abajo (texto revisable). Los
-- cuerpos vigentes ya contienen calificaciones pg_catalog. de funciones (8 y 12,
-- incluida pg_catalog.current_setting de la guarda),
-- así que la equivalencia mecánica revierte sólo «pg_catalog.uuid»,
-- «pg_catalog.text» y «pg_catalog.date» (ausentes en los cuerpos vigentes) y
-- exige que la cantidad de «pg_catalog.» crezca exactamente en las
-- calificaciones previstas. Se verifica que pg_proc (salvo prosrc), las
-- dependencias, las fachadas public y el resto de las funciones de public y
-- privado queden idénticos.
--
-- Exige A1 (usuario_actual con SHA-256 2ab0212d…). Incorpora los controles
-- A1-B01 (check_function_bodies = on) y A1-B02 (topología completa de
-- propietario_rpc) ya aplicados en A2/A3.
--
-- Alcance: con A1–A3 y B1 quedan calificadas las 19 funciones del inventario
-- del plan. El cierre de la vulnerabilidad global requiere la revisión de
-- seguridad y la aprobación humana; esta migración no lo declara.
--
-- Resolución de nombres, SQL dinámico, CREATE transitorio, SET LOCAL ROLE y
-- atomicidad: idéntico a A1/A2/A3 (un único bloque DO; search_path
-- 'pg_catalog, pg_temp' fijado en la primera sentencia y restaurado al final;
-- format con %L).
--
-- Sin cambios de grants permanentes, RLS, tablas, roles, códigos de error,
-- huellas ni reglas de negocio.

do $mig$
declare
  -- Sin inicializadores: nada se evalúa antes de fijar el search_path controlado.
  v_search_path_previo pg_catalog.text;
  v_firmas pg_catalog.text[];
  v_cabeceras pg_catalog.text[];
  v_hash_previo pg_catalog.text[];
  v_hash_nuevo pg_catalog.text[];
  v_cantidad pg_catalog.int4[];
  v_previas pg_catalog.int4[];
  v_cuerpos pg_catalog.text[];
  v_oids pg_catalog.oid[];
  v_nombres pg_catalog.text[];
  v_manifiesto_previo pg_catalog.text;
  v_manifiesto_nuevo pg_catalog.text;
  v_manifiesto pg_catalog.text;
  v_distribucion pg_catalog.text;
  v_membresias pg_catalog.text;
  v_foto_cambian pg_catalog.jsonb;
  v_foto_resto pg_catalog.jsonb;
  v_dependencias pg_catalog.text;
  v_acl_privado pg_catalog.text;
  v_definer pg_catalog.text;
  v_oid pg_catalog.oid;
  v_src pg_catalog.text;
  v_fachadas pg_catalog.text;
  v_guarda pg_catalog.text;
  i pg_catalog.int4;
begin
  -- -------------------------------------------------------------------------
  -- search_path controlado (primera sentencia; se restaura al final)
  -- -------------------------------------------------------------------------
  v_search_path_previo := pg_catalog.current_setting('search_path');
  perform pg_catalog.set_config('search_path', 'pg_catalog, pg_temp', true);

  if pg_catalog.current_setting('search_path') operator(pg_catalog.<>) 'pg_catalog, pg_temp' then
    raise exception 'pg_temp B1: no se pudo fijar el search_path controlado';
  end if;

  -- -------------------------------------------------------------------------
  -- Constantes (asignadas con el search_path ya controlado)
  -- -------------------------------------------------------------------------
  -- Funciones que cambian: firma calificada, cabecera DDL (firma, retorno,
  -- lenguaje, volatilidad y SECURITY idénticos a los vigentes), SHA-256 del
  -- cuerpo vigente y del nuevo, calificaciones pg_catalog. previas, cantidad de
  -- calificaciones nuevas y cuerpo nuevo.
  -- 1. privado.abrir_jornada(uuid,uuid,date,uuid): 19 calificaciones (8 previas)
  v_firmas[1] := 'privado.abrir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid)';
  v_cabeceras[1] := 'privado.abrir_jornada(p_idempotency_key pg_catalog.uuid, p_camion_id pg_catalog.uuid, p_fecha pg_catalog.date, p_vendedor_id pg_catalog.uuid) returns pg_catalog.uuid language plpgsql volatile security definer';
  v_hash_previo[1] := 'f6f88764d337df49f2d05fdb8deaafd6a5be9e13500c38caf8be31b143faea07';
  v_hash_nuevo[1] := '7e2f2d07ffe75a90af6fba379c32d874ca3d229daa7c841f300aef5f467c5440';
  v_previas[1] := 8;
  v_cantidad[1] := 19;
  v_cuerpos[1] := $c1$
declare
  v_uid pg_catalog.uuid;
  v_empresa pg_catalog.uuid;
  v_rol pg_catalog.text;
  v_activo boolean;
  v_huella pg_catalog.text;
  v_operacion pg_catalog.uuid;
  v_jornada pg_catalog.uuid;
  v_previa_id pg_catalog.uuid;
  v_previa_tipo pg_catalog.text;
  v_previa_huella pg_catalog.text;
  v_hoy pg_catalog.date;
  v_camion_activo boolean;
  v_vendedor_activo boolean;
begin
  -- Paso 0 (corrección T14; ADR-001 §6 y §16): una transacción de sólo lectura
  -- (GET o HEAD por PostgREST) se rechaza antes de cualquier acceso a datos y de
  -- la consulta de idempotencia. Sin esta guarda, un replay sólo leía y respondía
  -- 200 a un GET. SQLSTATE 25006 → HTTP 405 en PostgREST.
  if pg_catalog.current_setting('transaction_read_only') = 'on' then
    raise exception using
      errcode = '25006',
      message = 'jornada_metodo_no_permitido';
  end if;

  -- Paso 1. P13-jornadas: los advisory locks sólo serializan bajo READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = 'PT500', message = 'jornada_error_interno';
  end if;

  -- Paso 2. Identidad y rol, desde tablas protegidas.
  v_uid := privado.usuario_actual();
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'jornada_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if v_empresa is null or v_activo is not true
     or v_rol not in ('dueno', 'encargado') then
    raise exception using errcode = 'PT403', message = 'jornada_no_autorizado';
  end if;

  -- Paso 3. Estructura, sin leer estado mutable (orden T1-2). La fecha debe ser
  -- finita y estar entre 0001-01-01 y 9999-12-31 (T1-4): la huella v1 no
  -- representa infinity, -infinity ni fechas posteriores al año 294276, y no
  -- distingue una fecha a. C. de la fecha d. C. de igual texto.
  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'jornada_clave_invalida';
  end if;

  if p_fecha is null
     or not pg_catalog.isfinite(p_fecha)
     or p_fecha < pg_catalog.date '0001-01-01'
     or p_fecha > pg_catalog.date '9999-12-31' then
    raise exception using errcode = 'PT400', message = 'jornada_fecha_invalida';
  end if;

  if p_vendedor_id is null then
    raise exception using errcode = 'PT400', message = 'jornada_vendedor_invalido';
  end if;

  if p_camion_id is null then
    raise exception using errcode = 'PT404', message = 'jornada_camion_no_encontrado';
  end if;

  -- Paso 4. Huella v1.
  v_huella := encode(
    sha256(convert_to(
      'v1|apertura_jornada|' || p_camion_id::pg_catalog.text || '|'
        || to_char(p_fecha, 'YYYY-MM-DD') || '|' || p_vendedor_id::pg_catalog.text,
      'UTF8')),
    'hex');

  -- Paso 5. Replay previo, sin bloqueos. Se ejecuta después de autenticar y
  -- autorizar (paso 2) y de validar la estructura (paso 3).
  select o.id, o.tipo, o.huella
    into v_previa_id, v_previa_tipo, v_previa_huella
    from public.operaciones o
   where o.empresa_id = v_empresa
     and o.actor_id = v_uid
     and o.idempotency_key = p_idempotency_key;

  if found then
    if v_previa_tipo = 'apertura_jornada' and v_previa_huella = v_huella then
      select j.id into v_jornada
        from public.jornadas j
       where j.empresa_id = v_empresa
         and j.operacion_apertura_id = v_previa_id;
      if v_jornada is null then
        raise exception using errcode = 'PT500', message = 'jornada_error_interno';
      end if;
      return v_jornada;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 7. Advisory locks, en el orden global de P13-jornadas: nivel 1
  -- (camión) y después nivel 2 (vendedor). Se liberan al terminar la transacción.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'jornadas:camion:' || v_empresa::pg_catalog.text || ':' || p_camion_id::pg_catalog.text, 0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'jornadas:vendedor:' || v_empresa::pg_catalog.text || ':' || p_vendedor_id::pg_catalog.text, 0));

  -- Paso 8a. Segunda consulta de la clave (H2-R1): una solicitud repetida y
  -- concurrente que esperó los bloqueos ve aquí lo que la primera confirmó.
  select o.id, o.tipo, o.huella
    into v_previa_id, v_previa_tipo, v_previa_huella
    from public.operaciones o
   where o.empresa_id = v_empresa
     and o.actor_id = v_uid
     and o.idempotency_key = p_idempotency_key;

  if found then
    if v_previa_tipo = 'apertura_jornada' and v_previa_huella = v_huella then
      select j.id into v_jornada
        from public.jornadas j
       where j.empresa_id = v_empresa
         and j.operacion_apertura_id = v_previa_id;
      if v_jornada is null then
        raise exception using errcode = 'PT500', message = 'jornada_error_interno';
      end if;
      return v_jornada;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 9. Reserva de la clave. No incluye jornada_id (apertura_jornada lo
  -- exige nulo). Un rechazo posterior revierte esta fila con la transacción.
  begin
    insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values (v_empresa, v_uid, 'apertura_jornada', p_idempotency_key, v_huella)
    on conflict (empresa_id, actor_id, idempotency_key) do nothing
    returning id into v_operacion;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or not_null_violation or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'jornada_error_interno';
  end;

  if v_operacion is null then
    -- Otra transacción confirmó la misma clave entre los pasos 8a y 9.
    select o.id, o.tipo, o.huella
      into v_previa_id, v_previa_tipo, v_previa_huella
      from public.operaciones o
     where o.empresa_id = v_empresa
       and o.actor_id = v_uid
       and o.idempotency_key = p_idempotency_key;

    if v_previa_tipo = 'apertura_jornada' and v_previa_huella = v_huella then
      select j.id into v_jornada
        from public.jornadas j
       where j.empresa_id = v_empresa
         and j.operacion_apertura_id = v_previa_id;
      if v_jornada is null then
        raise exception using errcode = 'PT500', message = 'jornada_error_interno';
      end if;
      return v_jornada;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 10. Validaciones de negocio de ADR-007 §2.1 (precedencia T1-2), con
  -- datos leídos después de los bloqueos.
  v_hoy := (pg_catalog.now() at time zone 'America/Argentina/Tucuman')::pg_catalog.date;

  if p_fecha < v_hoy then
    raise exception using errcode = 'PT400', message = 'jornada_fecha_invalida';
  end if;

  select c.activo into v_camion_activo
    from public.camiones c
   where c.id = p_camion_id
     and c.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'jornada_camion_no_encontrado';
  end if;

  if v_camion_activo is not true then
    raise exception using errcode = 'PT409', message = 'jornada_camion_inactivo';
  end if;

  -- El vendedor se lee en la vista acotada de D-2, bajo su advisory de nivel 2.
  select v.activo into v_vendedor_activo
    from privado.perfiles_empresa_gestion v
   where v.usuario_id = p_vendedor_id
     and v.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'jornada_vendedor_no_encontrado';
  end if;

  if v_vendedor_activo is not true then
    raise exception using errcode = 'PT400', message = 'jornada_vendedor_invalido';
  end if;

  if exists (select 1 from public.jornadas j
              where j.empresa_id = v_empresa
                and j.camion_id = p_camion_id
                and j.fecha = p_fecha) then
    raise exception using errcode = 'PT409', message = 'jornada_duplicada';
  end if;

  if exists (select 1 from public.jornadas j
              where j.empresa_id = v_empresa
                and j.camion_id = p_camion_id
                and j.estado <> 'cerrada') then
    raise exception using errcode = 'PT409', message = 'jornada_camion_con_jornada_abierta';
  end if;

  if exists (select 1 from public.jornadas j
              where j.empresa_id = v_empresa
                and j.vendedor_id = p_vendedor_id
                and j.fecha = p_fecha) then
    raise exception using errcode = 'PT409', message = 'jornada_vendedor_ocupado';
  end if;

  -- Paso 12. Escritura. Una violación residual de restricción no revela su nombre.
  begin
    insert into public.jornadas (
      empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por,
      operacion_apertura_id
    )
    values (
      v_empresa, p_fecha, p_camion_id, p_vendedor_id, 'abierta', v_uid,
      v_operacion
    )
    returning id into v_jornada;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or not_null_violation or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'jornada_error_interno';
  end;

  return v_jornada;
end;
$c1$;

  -- 2. privado.reasignar_vendedor(uuid,uuid,uuid): 24 calificaciones (12 previas)
  v_firmas[2] := 'privado.reasignar_vendedor(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)';
  v_cabeceras[2] := 'privado.reasignar_vendedor(p_idempotency_key pg_catalog.uuid, p_jornada_id pg_catalog.uuid, p_vendedor_id pg_catalog.uuid) returns pg_catalog.uuid language plpgsql volatile security definer';
  v_hash_previo[2] := '381e59c479faad5e5e7829311da859640adbdab702054582cf1d198ce9e58943';
  v_hash_nuevo[2] := '6593c5e2e1ed10d47ca1d880eee3e53ff9809596987d5f33f8beedef6ba618dd';
  v_previas[2] := 12;
  v_cantidad[2] := 24;
  v_cuerpos[2] := $c2$
declare
  v_uid pg_catalog.uuid;
  v_empresa pg_catalog.uuid;
  v_rol pg_catalog.text;
  v_activo boolean;
  v_huella pg_catalog.text;
  v_operacion pg_catalog.uuid;
  v_previa_id pg_catalog.uuid;
  v_previa_tipo pg_catalog.text;
  v_previa_huella pg_catalog.text;
  v_vigente pg_catalog.uuid;
  v_vigente_bloqueado pg_catalog.uuid;
  v_estado pg_catalog.text;
  v_fecha pg_catalog.date;
  v_vendedor_activo boolean;
  v_filas integer;
begin
  -- Paso 0 (corrección T14; ADR-001 §6 y §16): una transacción de sólo lectura
  -- (GET o HEAD por PostgREST) se rechaza antes de cualquier acceso a datos y de
  -- la consulta de idempotencia. Sin esta guarda, un replay sólo leía y respondía
  -- 200 a un GET. SQLSTATE 25006 → HTTP 405 en PostgREST.
  if pg_catalog.current_setting('transaction_read_only') = 'on' then
    raise exception using
      errcode = '25006',
      message = 'jornada_metodo_no_permitido';
  end if;

  -- Paso 1. P13-jornadas: los advisory locks sólo serializan bajo READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = 'PT500', message = 'jornada_error_interno';
  end if;

  -- Paso 2. Identidad y rol, desde tablas protegidas.
  v_uid := privado.usuario_actual();
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'jornada_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if v_empresa is null or v_activo is not true
     or v_rol not in ('dueno', 'encargado') then
    raise exception using errcode = 'PT403', message = 'jornada_no_autorizado';
  end if;

  -- Paso 3. Estructura, sin leer estado mutable (orden T2-2): clave, vendedor, jornada.
  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'jornada_clave_invalida';
  end if;

  if p_vendedor_id is null then
    raise exception using errcode = 'PT400', message = 'jornada_vendedor_invalido';
  end if;

  if p_jornada_id is null then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  -- Paso 4. Huella v1.
  v_huella := encode(
    sha256(convert_to(
      'v1|reasignacion_vendedor|' || p_jornada_id::pg_catalog.text || '|' || p_vendedor_id::pg_catalog.text,
      'UTF8')),
    'hex');

  -- Paso 5. Replay previo, sin bloqueos. Va después de autenticar y autorizar
  -- (paso 2) y de validar la estructura (paso 3), y antes de revalidar el estado.
  select o.id, o.tipo, o.huella
    into v_previa_id, v_previa_tipo, v_previa_huella
    from public.operaciones o
   where o.empresa_id = v_empresa
     and o.actor_id = v_uid
     and o.idempotency_key = p_idempotency_key;

  if found then
    if v_previa_tipo = 'reasignacion_vendedor' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 6. Lectura sin bloqueo de la jornada, para obtener la clave de los
  -- advisory: el vendedor vigente. Inexistente o de otra empresa → PT404.
  select j.vendedor_id
    into v_vigente
    from public.jornadas j
   where j.id = p_jornada_id
     and j.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  -- Paso 7. Advisory locks de nivel 2 (vendedor): el vigente y el nuevo, en orden
  -- ascendente de uuid, y uno solo si coinciden. Se liberan al terminar la transacción.
  if v_vigente = p_vendedor_id then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:vendedor:' || v_empresa::pg_catalog.text || ':' || v_vigente::pg_catalog.text, 0));
  elsif v_vigente < p_vendedor_id then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:vendedor:' || v_empresa::pg_catalog.text || ':' || v_vigente::pg_catalog.text, 0));
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:vendedor:' || v_empresa::pg_catalog.text || ':' || p_vendedor_id::pg_catalog.text, 0));
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:vendedor:' || v_empresa::pg_catalog.text || ':' || p_vendedor_id::pg_catalog.text, 0));
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:vendedor:' || v_empresa::pg_catalog.text || ':' || v_vigente::pg_catalog.text, 0));
  end if;

  -- Paso 8. Nivel 3: la fila de la jornada, bloqueada. Con los bloqueos de los
  -- pasos 7 y 8 en poder de la transacción se releen vendedor, estado y fecha.
  select j.vendedor_id, j.estado, j.fecha
    into v_vigente_bloqueado, v_estado, v_fecha
    from public.jornadas j
   where j.id = p_jornada_id
     and j.empresa_id = v_empresa
     for update;

  if not found then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  -- Paso 8a. Segunda consulta de la clave (H2-R1), antes de la reverificación: una
  -- solicitud repetida y concurrente que esperó los bloqueos ve aquí lo que la
  -- primera confirmó y recibe la operación original, no jornada_estado_invalido.
  select o.id, o.tipo, o.huella
    into v_previa_id, v_previa_tipo, v_previa_huella
    from public.operaciones o
   where o.empresa_id = v_empresa
     and o.actor_id = v_uid
     and o.idempotency_key = p_idempotency_key;

  if found then
    if v_previa_tipo = 'reasignacion_vendedor' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 8b. Reverificación del valor usado como clave de bloqueo: si el vendedor
  -- vigente cambió entre los pasos 6 y 8, los advisory tomados no son los correctos.
  -- Sin efectos y reintentable con la misma clave; no se toman bloqueos fuera de orden.
  if v_vigente_bloqueado is distinct from v_vigente then
    raise exception using errcode = 'PT409', message = 'jornada_estado_invalido';
  end if;

  -- Paso 9. Reserva de la clave, con el jornada_id que el tipo exige. Un rechazo
  -- posterior revierte esta fila con la transacción.
  begin
    insert into public.operaciones (
      empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id
    )
    values (
      v_empresa, v_uid, 'reasignacion_vendedor', p_idempotency_key, v_huella,
      p_jornada_id
    )
    on conflict (empresa_id, actor_id, idempotency_key) do nothing
    returning id into v_operacion;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or not_null_violation or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'jornada_error_interno';
  end;

  if v_operacion is null then
    -- Otra transacción confirmó la misma clave entre los pasos 8a y 9.
    select o.id, o.tipo, o.huella
      into v_previa_id, v_previa_tipo, v_previa_huella
      from public.operaciones o
     where o.empresa_id = v_empresa
       and o.actor_id = v_uid
       and o.idempotency_key = p_idempotency_key;

    if v_previa_tipo = 'reasignacion_vendedor' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 10. Validaciones de negocio de ADR-007 §2.3 (precedencia T2-2), con los
  -- datos leídos bajo FOR UPDATE.
  if v_estado not in ('abierta', 'cargada') then
    raise exception using errcode = 'PT409', message = 'jornada_estado_invalido';
  end if;

  -- El vendedor nuevo se lee en la vista acotada de D-2, bajo su advisory de nivel 2.
  select v.activo into v_vendedor_activo
    from privado.perfiles_empresa_gestion v
   where v.usuario_id = p_vendedor_id
     and v.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'jornada_vendedor_no_encontrado';
  end if;

  if v_vendedor_activo is not true then
    raise exception using errcode = 'PT400', message = 'jornada_vendedor_invalido';
  end if;

  if p_vendedor_id = v_vigente_bloqueado then
    raise exception using errcode = 'PT409', message = 'jornada_sin_cambios';
  end if;

  if exists (select 1 from public.jornadas j
              where j.empresa_id = v_empresa
                and j.vendedor_id = p_vendedor_id
                and j.fecha = v_fecha) then
    raise exception using errcode = 'PT409', message = 'jornada_vendedor_ocupado';
  end if;

  -- Paso 12. Escrituras: la fila append-only del historial y el único cambio de la
  -- jornada (vendedor_id). Una violación residual de restricción no revela su nombre.
  -- T2-SR-1: el UPDATE debe afectar exactamente una fila. Una policy de RLS que filtre
  -- la fila (por ejemplo, si el actor dejó de estar habilitado entre la autorización y
  -- la escritura) no produce error: afecta cero filas. Sin esta comprobación la RPC
  -- confirmaría la operación y el historial sin cambiar el vendedor de la jornada. El
  -- conteo se lee inmediatamente después del UPDATE, sin escrituras intermedias. El
  -- PT500 que se levanta acá no lo captura el manejador de abajo (sólo atiende
  -- violaciones de restricción y de privilegio) y revierte la operación y el historial.
  begin
    insert into public.reasignaciones_vendedor (
      empresa_id, jornada_id, operacion_id, vendedor_anterior_id,
      vendedor_nuevo_id, actor_id
    )
    values (
      v_empresa, p_jornada_id, v_operacion, v_vigente_bloqueado, p_vendedor_id, v_uid
    );

    update public.jornadas
       set vendedor_id = p_vendedor_id
     where id = p_jornada_id
       and empresa_id = v_empresa;

    get diagnostics v_filas = row_count;
    if v_filas <> 1 then
      raise exception using errcode = 'PT500', message = 'jornada_error_interno';
    end if;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or not_null_violation or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'jornada_error_interno';
  end;

  return v_operacion;
end;
$c2$;

  -- Guarda GET/HEAD de E-SL1 (paso 0), que debe quedar intacta y antes de la
  -- identidad en cada cuerpo.
  v_guarda := E'\nbegin\n  -- Paso 0 (corrección T14; ADR-001 §6 y §16): una transacción de sólo lectura\n'
    || E'  -- (GET o HEAD por PostgREST) se rechaza antes de cualquier acceso a datos y de\n'
    || E'  -- la consulta de idempotencia. Sin esta guarda, un replay sólo leía y respondía\n'
    || E'  -- 200 a un GET. SQLSTATE 25006 → HTTP 405 en PostgREST.\n'
    || E'  if pg_catalog.current_setting(''transaction_read_only'') = ''on'' then\n'
    || E'    raise exception using\n'
    || E'      errcode = ''25006'',\n'
    || E'      message = ''jornada_metodo_no_permitido'';\n'
    || E'  end if;\n';

  -- Las 4 funciones de privado alcanzadas o verificadas por B1.
  v_nombres := array['abrir_jornada', 'reasignar_vendedor', 'usuario_actual', 'empresa_gestion_actual'];

  -- Distribución exacta por esquema de esos nombres (implementaciones en
  -- privado y fachadas public de las 2 RPC; ningún otro homónimo).
  v_distribucion := 'abrir_jornada:privado,public;empresa_gestion_actual:privado;reasignar_vendedor:privado,public;usuario_actual:privado';

  -- Manifiesto exacto de las 4 funciones (una línea por función, ordenadas por
  -- firma): firma | owner | lenguaje | prokind | SECURITY DEFINER | leakproof |
  -- strict | retset | volatilidad | paralelismo | nargs | nargdefaults | tipo de
  -- retorno | nombres de argumentos | modos | support | costo | filas |
  -- proconfig | ACL ordenada | comentario | probin | prosqlbody nulo | SHA-256.
  v_manifiesto_previo :=
       'privado.abrir_jornada(uuid,uuid,date,uuid)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|4|0|uuid|{p_idempotency_key,p_camion_id,p_fecha,p_vendedor_id}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|f6f88764d337df49f2d05fdb8deaafd6a5be9e13500c38caf8be31b143faea07' || E'\n'
    || 'privado.empresa_gestion_actual()|propietario_rpc|sql|f|true|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|6d0a758d68ffaf8f575e1faebb132dc29cab4400e81c953b6dc73ed475fce7cc' || E'\n'
    || 'privado.reasignar_vendedor(uuid,uuid,uuid)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|3|0|uuid|{p_idempotency_key,p_jornada_id,p_vendedor_id}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|381e59c479faad5e5e7829311da859640adbdab702054582cf1d198ce9e58943' || E'\n'
    || 'privado.usuario_actual()|propietario_rpc|sql|f|false|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96';
  v_manifiesto_nuevo := v_manifiesto_previo;
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, 'f6f88764d337df49f2d05fdb8deaafd6a5be9e13500c38caf8be31b143faea07', '7e2f2d07ffe75a90af6fba379c32d874ca3d229daa7c841f300aef5f467c5440');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, '381e59c479faad5e5e7829311da859640adbdab702054582cf1d198ce9e58943', '6593c5e2e1ed10d47ca1d880eee3e53ff9809596987d5f33f8beedef6ba618dd');

  -- -------------------------------------------------------------------------
  -- Precondiciones de identidad, entorno y roles (fail-closed)
  -- -------------------------------------------------------------------------
  if current_user operator(pg_catalog.<>) 'postgres'
     or session_user operator(pg_catalog.<>) 'postgres' then
    raise exception 'pg_temp B1: la migración debe ejecutarse como postgres; actual: % / %',
      session_user, current_user;
  end if;

  -- A1-B01: los cuerpos se validan al crearlos, en este contexto controlado.
  if pg_catalog.current_setting('check_function_bodies') operator(pg_catalog.<>) 'on' then
    raise exception 'pg_temp B1: check_function_bodies debe estar activo';
  end if;

  -- P3 completo (incluye NOREPLICATION).
  if not exists (select 1 from pg_catalog.pg_roles r
                  where r.rolname = 'propietario_rpc'
                    and not r.rolsuper and not r.rolcanlogin and not r.rolbypassrls
                    and not r.rolcreatedb and not r.rolcreaterole and not r.rolreplication) then
    raise exception 'pg_temp B1: propietario_rpc ausente o con atributos fuera de P3';
  end if;

  -- A1-B02: topología de membresías. propietario_rpc no es miembro de ningún
  -- rol; sus únicos miembros son las dos filas de postgres: O-3 (SET sin
  -- INHERIT ni ADMIN, otorgada por postgres) y la automática de PostgreSQL 16+
  -- al crear el rol (ADMIN sin INHERIT ni SET, otorgada por un superusuario).
  if exists (select 1 from pg_catalog.pg_auth_members m
              where m.member = 'propietario_rpc'::pg_catalog.regrole) then
    raise exception 'pg_temp B1: propietario_rpc es miembro de otro rol';
  end if;

  select pg_catalog.string_agg(x.fila, ',' order by x.fila) into v_membresias
    from (select m.member::pg_catalog.regrole::pg_catalog.text
                 || '|' || m.admin_option::pg_catalog.text
                 || '|' || m.inherit_option::pg_catalog.text
                 || '|' || m.set_option::pg_catalog.text
                 || '|' || case when m.grantor operator(pg_catalog.=) 'postgres'::pg_catalog.regrole then 'postgres'
                                when g.rolsuper then 'superusuario'
                                else 'otro' end as fila
            from pg_catalog.pg_auth_members m
            join pg_catalog.pg_roles g on g.oid operator(pg_catalog.=) m.grantor
           where m.roleid = 'propietario_rpc'::pg_catalog.regrole) x;

  if v_membresias is distinct from
     'postgres|false|false|true|postgres,postgres|true|false|false|superusuario' then
    raise exception 'pg_temp B1: membresías de propietario_rpc fuera de lo aprobado (P3/O-3): %', v_membresias;
  end if;

  -- O-3 efectivo: postgres puede SET ROLE propietario_rpc sin heredar.
  if not pg_catalog.pg_has_role('postgres', 'propietario_rpc', 'SET')
     or pg_catalog.pg_has_role('postgres', 'propietario_rpc', 'USAGE') then
    raise exception 'pg_temp B1: la membresía postgres → propietario_rpc no es la de O-3';
  end if;

  if (select n.nspowner from pg_catalog.pg_namespace n where n.nspname = 'privado')
     is distinct from 'postgres'::pg_catalog.regrole then
    raise exception 'pg_temp B1: el esquema privado no es de postgres';
  end if;

  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'pg_temp B1: propietario_rpc ya tiene CREATE sobre privado';
  end if;

  if not pg_catalog.has_language_privilege('propietario_rpc', 'plpgsql', 'USAGE') then
    raise exception 'pg_temp B1: propietario_rpc no puede usar plpgsql';
  end if;

  -- Dependencia de A1: usuario_actual con los dos casts calificados.
  if (select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex')
        from pg_catalog.pg_proc p
       where p.oid = pg_catalog.to_regprocedure('privado.usuario_actual()'))
     is distinct from '2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96' then
    raise exception 'pg_temp B1: falta A1 (privado.usuario_actual() no tiene el cuerpo calificado)';
  end if;

  -- Fachadas public SECURITY INVOKER de T1/T2: sin cambios (SHA-256 del cuerpo).
  select pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::pg_catalog.text || '|'
           || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex'),
           ',' order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
    into v_fachadas
    from pg_catalog.pg_proc p
   where p.pronamespace = 'public'::pg_catalog.regnamespace
     and p.proname operator(pg_catalog.=) any (array['abrir_jornada', 'reasignar_vendedor']::pg_catalog.name[]);

  if v_fachadas is distinct from
     'public.abrir_jornada(uuid,uuid,date,uuid)|349c03bf2c303f757d8fa97dc55aff6f85b4b463b85c3e3b901f39f3c28e9115,'
     || 'public.reasignar_vendedor(uuid,uuid,uuid)|bb55c733a1c8e1c3506763482b05a46a40cc5602de5f49c0c9411b7da0c0b2df' then
    raise exception 'pg_temp B1: las fachadas public de jornadas no son las aprobadas: %', v_fachadas;
  end if;

  -- Firmas existentes.
  for i in 1 .. pg_catalog.array_length(v_firmas, 1) loop
    v_oid := pg_catalog.to_regprocedure(v_firmas[i]);
    if v_oid is null then
      raise exception 'pg_temp B1: falta la función %', v_firmas[i];
    end if;
    v_oids[i] := v_oid;
  end loop;

  if pg_catalog.array_length(v_oids, 1) operator(pg_catalog.<>) 2 then
    raise exception 'pg_temp B1: se esperaban 2 funciones a corregir';
  end if;

  -- Sin sobrecargas ni homónimos fuera de lo esperado, en ningún esquema.
  select pg_catalog.string_agg(x.proname::pg_catalog.text || ':' || x.esquemas, ';' order by x.proname)
    into v_manifiesto
    from (select p.proname,
                 pg_catalog.string_agg(n.nspname::pg_catalog.text, ',' order by n.nspname) as esquemas
            from pg_catalog.pg_proc p
            join pg_catalog.pg_namespace n on n.oid operator(pg_catalog.=) p.pronamespace
           where p.proname::pg_catalog.text operator(pg_catalog.=) any (v_nombres)
           group by p.proname) x;

  if v_manifiesto is distinct from v_distribucion then
    raise exception 'pg_temp B1: sobrecargas u homónimos fuera de lo esperado: %', v_manifiesto;
  end if;

  -- -------------------------------------------------------------------------
  -- Estado aprobado exacto, antes de cualquier cambio
  -- -------------------------------------------------------------------------
  select pg_catalog.string_agg(
           p.oid::pg_catalog.regprocedure::pg_catalog.text
           || '|' || p.proowner::pg_catalog.regrole::pg_catalog.text
           || '|' || l.lanname::pg_catalog.text
           || '|' || p.prokind::pg_catalog.text
           || '|' || p.prosecdef::pg_catalog.text
           || '|' || p.proleakproof::pg_catalog.text
           || '|' || p.proisstrict::pg_catalog.text
           || '|' || p.proretset::pg_catalog.text
           || '|' || p.provolatile::pg_catalog.text
           || '|' || p.proparallel::pg_catalog.text
           || '|' || p.pronargs::pg_catalog.text
           || '|' || p.pronargdefaults::pg_catalog.text
           || '|' || p.prorettype::pg_catalog.regtype::pg_catalog.text
           || '|' || coalesce(p.proargnames::pg_catalog.text, '-')
           || '|' || coalesce(p.proargmodes::pg_catalog.text, '-')
           || '|' || coalesce(nullif(p.prosupport::pg_catalog.oid, 0::pg_catalog.oid)::pg_catalog.text, '-')
           || '|' || p.procost::pg_catalog.text
           || '|' || p.prorows::pg_catalog.text
           || '|' || coalesce(p.proconfig::pg_catalog.text, '-')
           || '|' || coalesce(pg_catalog.array_to_string(array(
                        select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1), ','), '-')
           || '|' || coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '-')
           || '|' || coalesce(p.probin, '-')
           || '|' || (p.prosqlbody is null)::pg_catalog.text
           || '|' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex'),
           E'\n' order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
    into v_manifiesto
    from pg_catalog.pg_proc p
    join pg_catalog.pg_language l on l.oid = p.prolang
   where p.pronamespace = 'privado'::pg_catalog.regnamespace
     and p.proname::pg_catalog.text operator(pg_catalog.=) any (v_nombres);

  if v_manifiesto is distinct from v_manifiesto_previo then
    raise exception 'pg_temp B1: el estado de las funciones de jornadas no es el aprobado (manifiesto)';
  end if;

  -- Fotos: pg_proc completo de public y privado (sin prosrc para las 2 que
  -- cambian), dependencias en las que participan las 2, ACL de privado y lista
  -- de SECURITY DEFINER.
  select pg_catalog.jsonb_object_agg(p.oid::pg_catalog.text,
           pg_catalog.to_jsonb(p) operator(pg_catalog.-) 'prosrc'::pg_catalog.text)
    into v_foto_cambian
    from pg_catalog.pg_proc p where p.oid operator(pg_catalog.=) any (v_oids);
  select pg_catalog.jsonb_object_agg(p.oid::pg_catalog.text, pg_catalog.to_jsonb(p))
    into v_foto_resto
    from pg_catalog.pg_proc p
   where p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace)
     and not (p.oid operator(pg_catalog.=) any (v_oids));
  select coalesce(pg_catalog.string_agg(
           d.classid::pg_catalog.text || ':' || d.objid::pg_catalog.text || ':' || d.objsubid::pg_catalog.text
           || '>' || d.refclassid::pg_catalog.text || ':' || d.refobjid::pg_catalog.text || ':'
           || d.refobjsubid::pg_catalog.text || ':' || d.deptype::pg_catalog.text,
           ',' order by d.classid, d.objid, d.objsubid, d.refclassid, d.refobjid, d.refobjsubid, d.deptype), '')
    into v_dependencias
    from pg_catalog.pg_depend d
   where (d.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass and d.objid operator(pg_catalog.=) any (v_oids))
      or (d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass and d.refobjid operator(pg_catalog.=) any (v_oids));
  select coalesce(n.nspacl::pg_catalog.text, '') into v_acl_privado
    from pg_catalog.pg_namespace n where n.nspname = 'privado';
  select pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::pg_catalog.text || '/'
                               || p.proowner::pg_catalog.regrole::pg_catalog.text, ','
                               order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
    into v_definer
    from pg_catalog.pg_proc p
   where p.prosecdef
     and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace);

  -- -------------------------------------------------------------------------
  -- Verificación de los cuerpos nuevos (antes de instalarlos)
  -- -------------------------------------------------------------------------
  -- Equivalencia: el cuerpo vigente no contiene «pg_catalog.uuid»,
  -- «pg_catalog.text» ni «pg_catalog.date»; revirtiendo sólo esos tres
  -- tokens en el cuerpo nuevo se
  -- obtiene el vigente byte a byte, y la cantidad de «pg_catalog.» pasa de la
  -- previa a la previa más las calificaciones previstas.
  for i in 1 .. 2 loop
    select p.prosrc into v_src from pg_catalog.pg_proc p where p.oid = v_oids[i];
    if pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_src, 'UTF8')), 'hex')
         operator(pg_catalog.<>) v_hash_previo[i]
       or pg_catalog.strpos(v_src, 'pg_catalog.uuid') operator(pg_catalog.<>) 0
       or pg_catalog.strpos(v_src, 'pg_catalog.text') operator(pg_catalog.<>) 0
       or pg_catalog.strpos(v_src, 'pg_catalog.date') operator(pg_catalog.<>) 0
       or (pg_catalog.length(v_src) - pg_catalog.length(pg_catalog.replace(v_src, 'pg_catalog.', '')))
          / pg_catalog.length('pg_catalog.') operator(pg_catalog.<>) v_previas[i]
       or pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_cuerpos[i], 'UTF8')), 'hex')
         operator(pg_catalog.<>) v_hash_nuevo[i]
       or pg_catalog.replace(pg_catalog.replace(pg_catalog.replace(
            v_cuerpos[i], 'pg_catalog.uuid', 'uuid'), 'pg_catalog.text', 'text'),
            'pg_catalog.date', 'date') is distinct from v_src
       or (pg_catalog.length(v_cuerpos[i])
           - pg_catalog.length(pg_catalog.replace(v_cuerpos[i], 'pg_catalog.', '')))
          / pg_catalog.length('pg_catalog.') operator(pg_catalog.<>) v_previas[i] + v_cantidad[i] then
      raise exception 'pg_temp B1: el cuerpo nuevo de % no es el vigente con las calificaciones previstas', v_firmas[i];
    end if;
    if (pg_catalog.length(v_cuerpos[i]) - pg_catalog.length(pg_catalog.replace(v_cuerpos[i], v_guarda, '')))
         / pg_catalog.length(v_guarda) operator(pg_catalog.<>) 1
       or pg_catalog.strpos(v_cuerpos[i], v_guarda)
          operator(pg_catalog.>) pg_catalog.strpos(v_cuerpos[i], 'privado.usuario_actual()') then
      raise exception 'pg_temp B1: la guarda GET/HEAD no está como paso 0 en el cuerpo nuevo de %', v_firmas[i];
    end if;
  end loop;

  -- -------------------------------------------------------------------------
  -- Sustitución como owner técnico (O-3), con CREATE transitorio
  -- -------------------------------------------------------------------------
  grant create on schema privado to propietario_rpc;
  set local role propietario_rpc;

  if current_user operator(pg_catalog.<>) 'propietario_rpc'
     or pg_catalog.current_setting('search_path') operator(pg_catalog.<>) 'pg_catalog, pg_temp' then
    raise exception 'pg_temp B1: no se pudo actuar como propietario_rpc con el search_path controlado';
  end if;

  for i in 1 .. 2 loop
    execute pg_catalog.format(
      'create or replace function ' || v_cabeceras[i] || ' set search_path = %L as %L',
      '', v_cuerpos[i]);
  end loop;

  reset role;

  if current_user operator(pg_catalog.<>) 'postgres' then
    raise exception 'pg_temp B1: no se pudo volver a postgres';
  end if;

  revoke create on schema privado from propietario_rpc;

  -- -------------------------------------------------------------------------
  -- Verificación fail-closed del resultado
  -- -------------------------------------------------------------------------
  for i in 1 .. 2 loop
    if (select p.prosrc from pg_catalog.pg_proc p where p.oid = v_oids[i]) is distinct from v_cuerpos[i] then
      raise exception 'pg_temp B1: el cuerpo instalado de % no es el previsto', v_firmas[i];
    end if;
    if pg_catalog.strpos((select p.prosrc from pg_catalog.pg_proc p where p.oid = v_oids[i]), v_guarda)
       operator(pg_catalog.=) 0 then
      raise exception 'pg_temp B1: el cuerpo instalado de % perdió la guarda GET/HEAD', v_firmas[i];
    end if;
  end loop;

  -- pg_proc idéntico salvo prosrc (mismo oid, owner, ACL, SECURITY, search_path,
  -- volatilidad, argumentos, valores por defecto…) y el resto de las funciones
  -- de public y privado sin ningún cambio.
  if (select pg_catalog.jsonb_object_agg(p.oid::pg_catalog.text,
              pg_catalog.to_jsonb(p) operator(pg_catalog.-) 'prosrc'::pg_catalog.text)
        from pg_catalog.pg_proc p where p.oid operator(pg_catalog.=) any (v_oids))
       is distinct from v_foto_cambian
     or (select pg_catalog.jsonb_object_agg(p.oid::pg_catalog.text, pg_catalog.to_jsonb(p))
           from pg_catalog.pg_proc p
          where p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace)
            and not (p.oid operator(pg_catalog.=) any (v_oids)))
       is distinct from v_foto_resto then
    raise exception 'pg_temp B1: cambió un atributo de pg_proc distinto del cuerpo, u otra función';
  end if;

  -- Mismas dependencias (tipos de argumentos y retorno, lenguaje, esquema y
  -- quienes dependen de estas funciones).
  if (select coalesce(pg_catalog.string_agg(
              d.classid::pg_catalog.text || ':' || d.objid::pg_catalog.text || ':' || d.objsubid::pg_catalog.text
              || '>' || d.refclassid::pg_catalog.text || ':' || d.refobjid::pg_catalog.text || ':'
              || d.refobjsubid::pg_catalog.text || ':' || d.deptype::pg_catalog.text,
              ',' order by d.classid, d.objid, d.objsubid, d.refclassid, d.refobjid, d.refobjsubid, d.deptype), '')
        from pg_catalog.pg_depend d
       where (d.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass and d.objid operator(pg_catalog.=) any (v_oids))
          or (d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass and d.refobjid operator(pg_catalog.=) any (v_oids)))
     is distinct from v_dependencias then
    raise exception 'pg_temp B1: cambiaron las dependencias de las funciones';
  end if;

  select pg_catalog.string_agg(
           p.oid::pg_catalog.regprocedure::pg_catalog.text
           || '|' || p.proowner::pg_catalog.regrole::pg_catalog.text
           || '|' || l.lanname::pg_catalog.text
           || '|' || p.prokind::pg_catalog.text
           || '|' || p.prosecdef::pg_catalog.text
           || '|' || p.proleakproof::pg_catalog.text
           || '|' || p.proisstrict::pg_catalog.text
           || '|' || p.proretset::pg_catalog.text
           || '|' || p.provolatile::pg_catalog.text
           || '|' || p.proparallel::pg_catalog.text
           || '|' || p.pronargs::pg_catalog.text
           || '|' || p.pronargdefaults::pg_catalog.text
           || '|' || p.prorettype::pg_catalog.regtype::pg_catalog.text
           || '|' || coalesce(p.proargnames::pg_catalog.text, '-')
           || '|' || coalesce(p.proargmodes::pg_catalog.text, '-')
           || '|' || coalesce(nullif(p.prosupport::pg_catalog.oid, 0::pg_catalog.oid)::pg_catalog.text, '-')
           || '|' || p.procost::pg_catalog.text
           || '|' || p.prorows::pg_catalog.text
           || '|' || coalesce(p.proconfig::pg_catalog.text, '-')
           || '|' || coalesce(pg_catalog.array_to_string(array(
                        select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1), ','), '-')
           || '|' || coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '-')
           || '|' || coalesce(p.probin, '-')
           || '|' || (p.prosqlbody is null)::pg_catalog.text
           || '|' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex'),
           E'\n' order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
    into v_manifiesto
    from pg_catalog.pg_proc p
    join pg_catalog.pg_language l on l.oid = p.prolang
   where p.pronamespace = 'privado'::pg_catalog.regnamespace
     and p.proname::pg_catalog.text operator(pg_catalog.=) any (v_nombres);

  if v_manifiesto is distinct from v_manifiesto_nuevo then
    raise exception 'pg_temp B1: el estado resultante no es el esperado (manifiesto)';
  end if;

  -- Sin privilegios transitorios.
  if (select coalesce(n.nspacl::pg_catalog.text, '') from pg_catalog.pg_namespace n
       where n.nspname = 'privado') is distinct from v_acl_privado
     or pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'pg_temp B1: quedó un privilegio CREATE transitorio sobre privado';
  end if;

  -- Misma lista de SECURITY DEFINER.
  if (select pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::pg_catalog.text || '/'
                                   || p.proowner::pg_catalog.regrole::pg_catalog.text, ','
                                   order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
        from pg_catalog.pg_proc p
       where p.prosecdef
         and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace))
       is distinct from v_definer then
    raise exception 'pg_temp B1: cambió la lista de funciones SECURITY DEFINER';
  end if;

  -- P11: EXECUTE de authenticated en las 2 RPC; nunca anon ni service_role.
  for i in 1 .. 2 loop
    if pg_catalog.has_function_privilege('anon', v_oids[i], 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', v_oids[i], 'EXECUTE')
       or not pg_catalog.has_function_privilege('authenticated', v_oids[i], 'EXECUTE') then
      raise exception 'pg_temp B1: EXECUTE fuera de lo aprobado en %', v_firmas[i];
    end if;
  end loop;

  -- Restaura el search_path de la sesión para el resto de la transacción.
  perform pg_catalog.set_config('search_path', v_search_path_previo, true);

  if pg_catalog.current_setting('search_path') is distinct from v_search_path_previo then
    raise exception 'pg_temp B1: no se pudo restaurar el search_path';
  end if;
end
$mig$;
