-- T1 — RPC abrir_jornada (Blueprint §7.5, §9, §10, §12; ADR-007 §2.1 y §7;
-- ADR-001 Topología D, P11, O-3 y §18.4.2, §18.4.3, §18.4.4, §18.4.5, §18.4.7).
--
-- Una sola RPC: abrir_jornada(uuid, uuid, date, uuid) — clave, camión, fecha y
-- vendedor — que devuelve el uuid de la jornada. Sólo dueño y encargado
-- activos. Sin cambios de esquema: usa las tablas, columnas, policies y grants
-- que dejó D-1 (20261030120000_jornadas_esquema.sql) y la lectura acotada de
-- perfiles de D-2 (privado.perfiles_empresa_gestion). No define helpers: el
-- contrato de ADR-001 §18.4.6 fija 12 funciones para las seis RPC.
--
-- Decisiones humanas de la tarea (docs/progress-log.md):
--   - T1-1: fecha pasada → PT400 jornada_fecha_invalida (paso 10).
--   - T1-2: precedencia determinista, subordinada al orden de §18.4.3:
--       paso 3: clave, fecha, vendedor, camión;
--       paso 10: fecha pasada, camión (inexistente o de otra empresa, luego
--       inactivo), vendedor (inexistente o de otra empresa, luego inactivo),
--       jornada_duplicada, jornada_camion_con_jornada_abierta,
--       jornada_vendedor_ocupado.
--   - T1-3: el día operativo es (now() at time zone 'America/Argentina/Tucuman')
--     ::date; now() es el instante de la transacción.
--   - T1-4 (opción A, regla técnica acotada a T1; ampliada tras la auditoría de
--     44b1670): la fecha debe ser finita y estar entre 0001-01-01 y 9999-12-31
--     inclusive (paso 3) y no ser anterior al día operativo actual (paso 10).
--     Una fecha nula, infinita, anterior a 0001-01-01 o posterior a 9999-12-31 se
--     rechaza en el paso 3, antes de la huella y de cualquier consulta de replay
--     o reserva de la clave, con PT400 jornada_fecha_invalida. Motivo: la huella
--     v1 escribe la fecha con to_char(fecha, 'YYYY-MM-DD'); to_char(infinity)
--     devuelve NULL, to_char de fechas posteriores al año 294276 falla, y el
--     formato no imprime la era, de modo que una fecha a. C. produce el mismo
--     texto (y la misma huella) que la fecha d. C. de igual año, mes y día. Dentro
--     de [0001-01-01, 9999-12-31] el formato es inyectivo. La fórmula de la huella
--     v1 no cambia.
--   - T1-5: propietario_rpc ya tiene los privilegios y las policies necesarios
--     (verificado); esta migración no cambia ningún permiso de D-1 ni de D-2.
--
-- Concurrencia (P13-jornadas): READ COMMITTED; advisory locks de nivel 1
-- (camión) y nivel 2 (vendedor), en ese orden, tomados después del replay
-- previo (paso 5) y antes de la segunda consulta de la clave (paso 8a). No hay
-- fila previa que bloquear (nivel 3) ni stock (nivel 4). La RPC exige
-- READ COMMITTED: con otro aislamiento falla cerrada (PT500).
--
-- Huella v1: 'v1|apertura_jornada|<camión>|<fecha YYYY-MM-DD>|<vendedor>'.
-- Respuesta (también en replay): el uuid de jornadas.id, la fila ligada a la
-- operación por jornadas.operacion_apertura_id.
--
-- Fuera de alcance: las otras cinco RPC, el arnés de concurrencia (I10, I11 y
-- K10 quedan para T3), el frontend y el CI. `service_role` sin privilegios (P11).
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

do $$
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;

  if to_regclass('public.jornadas') is null
     or to_regclass('public.operaciones') is null
     or to_regclass('privado.perfiles_empresa_gestion') is null
     or to_regprocedure('privado.usuario_actual()') is null then
    raise exception 'jornadas: faltan D-1 o D-2 (jornadas, operaciones, la vista de perfiles o usuario_actual)';
  end if;

  if not exists (select 1 from pg_roles where rolname = 'propietario_rpc') then
    raise exception 'jornadas: falta el rol propietario_rpc';
  end if;

  if exists (select 1 from pg_proc
              where proname = 'abrir_jornada'
                and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)) then
    raise exception 'jornadas: abrir_jornada ya existe';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Implementación privilegiada (SECURITY DEFINER, owner propietario_rpc)
-- ---------------------------------------------------------------------------
create function privado.abrir_jornada(
  p_idempotency_key uuid,
  p_camion_id uuid,
  p_fecha date,
  p_vendedor_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_empresa uuid;
  v_rol text;
  v_activo boolean;
  v_huella text;
  v_operacion uuid;
  v_jornada uuid;
  v_previa_id uuid;
  v_previa_tipo text;
  v_previa_huella text;
  v_hoy date;
  v_camion_activo boolean;
  v_vendedor_activo boolean;
begin
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
     or p_fecha < date '0001-01-01'
     or p_fecha > date '9999-12-31' then
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
      'v1|apertura_jornada|' || p_camion_id::text || '|'
        || to_char(p_fecha, 'YYYY-MM-DD') || '|' || p_vendedor_id::text,
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
    'jornadas:camion:' || v_empresa::text || ':' || p_camion_id::text, 0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'jornadas:vendedor:' || v_empresa::text || ':' || p_vendedor_id::text, 0));

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
  v_hoy := (pg_catalog.now() at time zone 'America/Argentina/Tucuman')::date;

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
$$;

-- ---------------------------------------------------------------------------
-- Fachada expuesta (SECURITY INVOKER): sólo delega
-- ---------------------------------------------------------------------------
create function public.abrir_jornada(
  p_idempotency_key uuid,
  p_camion_id uuid,
  p_fecha date,
  p_vendedor_id uuid
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.abrir_jornada(p_idempotency_key, p_camion_id, p_fecha, p_vendedor_id)
$$;

-- ---------------------------------------------------------------------------
-- EXECUTE (firma exacta) y propiedad
-- ---------------------------------------------------------------------------
-- Privilegios antes de transferir la propiedad (O-3: postgres no actúa como
-- owner de las funciones de propietario_rpc; ALTER ... OWNER TO reescribe el
-- grantor del ACL al nuevo owner).
revoke all on function privado.abrir_jornada(uuid, uuid, date, uuid)
  from public, anon, authenticated, service_role;
grant execute on function privado.abrir_jornada(uuid, uuid, date, uuid)
  to authenticated;

revoke all on function public.abrir_jornada(uuid, uuid, date, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.abrir_jornada(uuid, uuid, date, uuid)
  to authenticated;

-- CREATE sobre privado sólo mientras se transfiere la propiedad.
grant create on schema privado to propietario_rpc;
alter function privado.abrir_jornada(uuid, uuid, date, uuid)
  owner to propietario_rpc;
revoke create on schema privado from propietario_rpc;

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pg_proc
       where proname = 'abrir_jornada'
         and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)) <> 2
     or not exists (
       select 1 from pg_proc p
        where p.oid = 'privado.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure
          and p.prosecdef and p.proowner = 'propietario_rpc'::regrole
          and p.proconfig @> array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc'])
     or not exists (
       select 1 from pg_proc p
        where p.oid = 'public.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure
          and not p.prosecdef and p.proowner = 'postgres'::regrole
          and p.proconfig @> array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/postgres', 'postgres=X/postgres']) then
    raise exception 'jornadas: abrir_jornada fuera de lo aprobado (seguridad, owner, search_path, ACL o sobrecargas)';
  end if;

  if has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
     or has_function_privilege('anon', 'public.abrir_jornada(uuid, uuid, date, uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.abrir_jornada(uuid, uuid, date, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'privado.abrir_jornada(uuid, uuid, date, uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'privado.abrir_jornada(uuid, uuid, date, uuid)', 'EXECUTE') then
    raise exception 'jornadas: abrir_jornada concede privilegios fuera de lo aprobado (CREATE o EXECUTE)';
  end if;
end $$;
