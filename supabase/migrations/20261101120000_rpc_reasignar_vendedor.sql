-- T2 — RPC reasignar_vendedor (Blueprint §7.5, §9, §10, §12; ADR-007 §2.2, §2.3 y §7
-- casos 8, 9, 22 y 23; ADR-001 Topología D, P11, O-3 y §18.4.2, §18.4.3, §18.4.4,
-- §18.4.5, §18.4.7 y §18.4.9).
--
-- Una sola RPC: reasignar_vendedor(uuid, uuid, uuid) — clave, jornada y vendedor
-- nuevo — que devuelve el uuid de la OPERACIÓN (también en replay). Sólo dueño y
-- encargado activos. Sin cambios de esquema: usa las tablas, columnas, policies y
-- grants que dejó D-1 (20261030120000_jornadas_esquema.sql), la lectura acotada de
-- perfiles de D-2 (privado.perfiles_empresa_gestion) y no toca T1. No define
-- helpers: el contrato de ADR-001 §18.4.6 fija 12 funciones para las seis RPC.
--
-- Reglas de negocio (ADR-007 §2.3):
--   - Sólo se reasigna una jornada en estado abierta o cargada; en cualquier otro
--     estado → PT409 jornada_estado_invalido.
--   - El vendedor nuevo es un perfil de la empresa, activo, con rol dueno,
--     encargado o vendedor_piloto, y sin otra jornada en la fecha de ésta (incluso
--     cerrada). El vendedor anterior queda libre esa fecha.
--   - Se puede reasignar desde un vendedor vigente que ya está inactivo (la baja
--     posterior se admite); sólo se exige que el nuevo esté activo.
--   - Cada reasignación confirmada deja una operación reasignacion_vendedor (con
--     jornada_id) y una fila append-only en reasignaciones_vendedor (anterior,
--     nuevo, operación, actor). Se actualiza únicamente jornadas.vendedor_id.
--   - No se agrega ninguna restricción por fecha de la jornada: ADR-007 y
--     ADR-001 no la definen (decisión T2-5).
--
-- Corrección T2-SR-1 (primer ciclo posauditoría): el UPDATE de jornadas.vendedor_id se
-- verifica con GET DIAGNOSTICS ... ROW_COUNT inmediatamente después y debe afectar
-- exactamente una fila; si no, PT500 jornada_error_interno y se revierten la operación y
-- el historial (ver el paso 12).
--
-- Decisiones humanas de la tarea (docs/progress-log.md):
--   - T2-1: vendedor nuevo igual al vigente → PT409 jornada_sin_cambios (código del
--     catálogo de ADR-001 §18.4.7). Es una solicitud nueva (otra clave); el replay
--     legítimo de la misma clave y huella devuelve la operación original ANTES de
--     revalidar el estado (pasos 5 y 8a) y nunca se confunde con jornada_sin_cambios.
--   - T2-2: precedencia determinista, subordinada al orden de §18.4.3:
--       paso 3: clave, vendedor, jornada;
--       paso 10: estado de la jornada; vendedor nuevo (inexistente o de otra empresa,
--       luego inactivo); sin cambios; vendedor ocupado en la fecha de la jornada.
--   - T2-3: rama feat/rpc-jornadas-t2-reasignar, desde 8e4aefa.
--
-- Concurrencia (P13-jornadas): READ COMMITTED. Advisory locks de nivel 2 (vendedor):
-- el vigente y el nuevo, en orden ascendente de uuid (uno solo si coinciden), tomados
-- después del replay previo (paso 5) y de la lectura sin bloqueo de la jornada
-- (paso 6); después SELECT ... FOR UPDATE de la jornada (nivel 3), la segunda consulta
-- de la clave (paso 8a) y la reverificación del vendedor vigente (paso 8b). No toma
-- camión (nivel 1) ni stock (nivel 4). La reserva de la clave (paso 9) es posterior al
-- FOR UPDATE. La RPC exige READ COMMITTED: con otro aislamiento falla cerrada (PT500).
--
-- Huella v1: 'v1|reasignacion_vendedor|<jornada>|<vendedor>'.
--
-- Fuera de alcance: las otras cuatro RPC, el arnés de concurrencia (I10, I11 y K1 a
-- K9 quedan para T3), el frontend y el CI. `service_role` sin privilegios (P11).
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

do $$
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;

  if to_regclass('public.jornadas') is null
     or to_regclass('public.reasignaciones_vendedor') is null
     or to_regclass('public.operaciones') is null
     or to_regclass('privado.perfiles_empresa_gestion') is null
     or to_regprocedure('privado.usuario_actual()') is null then
    raise exception 'jornadas: faltan D-1 o D-2 (jornadas, reasignaciones_vendedor, operaciones, la vista de perfiles o usuario_actual)';
  end if;

  if not exists (select 1 from pg_roles where rolname = 'propietario_rpc') then
    raise exception 'jornadas: falta el rol propietario_rpc';
  end if;

  if exists (select 1 from pg_proc
              where proname = 'reasignar_vendedor'
                and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)) then
    raise exception 'jornadas: reasignar_vendedor ya existe';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Implementación privilegiada (SECURITY DEFINER, owner propietario_rpc)
-- ---------------------------------------------------------------------------
create function privado.reasignar_vendedor(
  p_idempotency_key uuid,
  p_jornada_id uuid,
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
  v_previa_id uuid;
  v_previa_tipo text;
  v_previa_huella text;
  v_vigente uuid;
  v_vigente_bloqueado uuid;
  v_estado text;
  v_fecha date;
  v_vendedor_activo boolean;
  v_filas integer;
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
      'v1|reasignacion_vendedor|' || p_jornada_id::text || '|' || p_vendedor_id::text,
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
      'jornadas:vendedor:' || v_empresa::text || ':' || v_vigente::text, 0));
  elsif v_vigente < p_vendedor_id then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:vendedor:' || v_empresa::text || ':' || v_vigente::text, 0));
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:vendedor:' || v_empresa::text || ':' || p_vendedor_id::text, 0));
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:vendedor:' || v_empresa::text || ':' || p_vendedor_id::text, 0));
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:vendedor:' || v_empresa::text || ':' || v_vigente::text, 0));
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
$$;

-- ---------------------------------------------------------------------------
-- Fachada expuesta (SECURITY INVOKER): sólo delega
-- ---------------------------------------------------------------------------
create function public.reasignar_vendedor(
  p_idempotency_key uuid,
  p_jornada_id uuid,
  p_vendedor_id uuid
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.reasignar_vendedor(p_idempotency_key, p_jornada_id, p_vendedor_id)
$$;

-- ---------------------------------------------------------------------------
-- EXECUTE (firma exacta) y propiedad
-- ---------------------------------------------------------------------------
-- Privilegios antes de transferir la propiedad (O-3: postgres no actúa como
-- owner de las funciones de propietario_rpc; ALTER ... OWNER TO reescribe el
-- grantor del ACL al nuevo owner).
revoke all on function privado.reasignar_vendedor(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function privado.reasignar_vendedor(uuid, uuid, uuid)
  to authenticated;

revoke all on function public.reasignar_vendedor(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.reasignar_vendedor(uuid, uuid, uuid)
  to authenticated;

-- CREATE sobre privado sólo mientras se transfiere la propiedad.
grant create on schema privado to propietario_rpc;
alter function privado.reasignar_vendedor(uuid, uuid, uuid)
  owner to propietario_rpc;
revoke create on schema privado from propietario_rpc;

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pg_proc
       where proname = 'reasignar_vendedor'
         and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)) <> 2
     or not exists (
       select 1 from pg_proc p
        where p.oid = 'privado.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure
          and p.prosecdef and p.proowner = 'propietario_rpc'::regrole
          and p.proconfig @> array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc'])
     or not exists (
       select 1 from pg_proc p
        where p.oid = 'public.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure
          and not p.prosecdef and p.proowner = 'postgres'::regrole
          and p.proconfig @> array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/postgres', 'postgres=X/postgres']) then
    raise exception 'jornadas: reasignar_vendedor fuera de lo aprobado (seguridad, owner, search_path, ACL o sobrecargas)';
  end if;

  if has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
     or has_function_privilege('anon', 'public.reasignar_vendedor(uuid, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.reasignar_vendedor(uuid, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'privado.reasignar_vendedor(uuid, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'privado.reasignar_vendedor(uuid, uuid, uuid)', 'EXECUTE') then
    raise exception 'jornadas: reasignar_vendedor concede privilegios fuera de lo aprobado (CREATE o EXECUTE)';
  end if;
end $$;
