-- T7 — RPC confirmar_salida (Blueprint §7.5, §9 y §12; ADR-007 §2.2, §2.3.5, §2.7 y
-- §7 casos 20, 21, 22 y 24; ADR-001 Topología D, P11, O-3, §17.1, §18.4.2 a §18.4.9 y
-- E-SL1 §18.4.16, aprobada para validación controlada el 04/11/2026).
--
-- Una sola RPC: confirmar_salida(uuid, uuid) — clave y jornada — que devuelve el
-- uuid de la OPERACIÓN (también en replay). Sólo dueño y encargado activos. Sin
-- cambios de esquema, grants ni políticas: usa lo que dejó D-1 (tipo salida_jornada,
-- jornada_id en operaciones, UPDATE (estado) de propietario_rpc sobre jornadas). No
-- define helpers (§18.4.6).
--
-- Reglas de negocio (ADR-007 §2.2 y §2.7):
--   - Confirmación expresa de salida: cargada → en_reparto. Desde cualquier otro
--     estado → PT409 jornada_estado_invalido.
--   - Exige carga neta positiva: por producto, cargas − descargas de esa jornada > 0
--     en al menos uno; si no → PT409 jornada_carga_neta_cero.
--   - Se admite con el camión dado de baja (§2.7): no se valida que esté activo.
--   - No genera movimientos ni historial y no cambia el vendedor (queda fijado por
--     la imposibilidad de reasignar fuera de abierta/cargada, §2.3; P-2 sigue
--     pendiente y no se implementa).
--
-- Orden (ADR-001 §18.4.3): paso 0 E-SL1 (transaction_read_only = on → 25006
-- jornada_metodo_no_permitido, antes de todo); 1 READ COMMITTED; 2 identidad y rol;
-- 3 estructura (clave, jornada); 4 huella; 5 replay sin bloqueos; 6 lectura sin
-- bloqueo de la jornada; 8 FOR UPDATE de la jornada (nivel 3); 8a segunda consulta
-- de la clave; 9 reserva; 10 negocio (estado → carga neta, precedencia aprobada el
-- 04/11/2026); 12 UPDATE del estado. No toma advisory de ningún nivel: no mueve
-- stock, y carga, descarga y salida de la misma jornada se serializan por el FOR
-- UPDATE.
--
-- Huella v1: 'v1|salida_jornada|<jornada>'.
--
-- pg_temp (ADR-001 §17.1): todos los tipos y casts del cuerpo y de esta migración
-- están calificados con pg_catalog, y las relaciones con su esquema. Exige A1.
--
-- Fuera de alcance: corregir_jornada, transiciones posteriores a en_reparto,
-- ventas, frontend, CI. `service_role` sin privilegios (P11). Validación
-- exclusivamente local/staging. Prohibido aplicar en producción.

do $$
begin
  if current_user operator(pg_catalog.<>) 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;

  if pg_catalog.to_regclass('public.jornadas') is null
     or pg_catalog.to_regclass('public.operaciones') is null
     or pg_catalog.to_regclass('public.movimientos_stock') is null
     or pg_catalog.to_regprocedure('privado.usuario_actual()') is null
     or pg_catalog.to_regprocedure('privado.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)') is null then
    raise exception 'jornadas: faltan D-1, usuario_actual o registrar_descarga (T6)';
  end if;

  -- A1: usuario_actual con los casts calificados (plan de remediación pg_temp).
  if (select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex')
        from pg_catalog.pg_proc p
       where p.oid operator(pg_catalog.=) pg_catalog.to_regprocedure('privado.usuario_actual()'))
     is distinct from '2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96' then
    raise exception 'jornadas: falta A1 (privado.usuario_actual() no tiene el cuerpo calificado)';
  end if;

  if not exists (select 1 from pg_catalog.pg_roles where rolname operator(pg_catalog.=) 'propietario_rpc') then
    raise exception 'jornadas: falta el rol propietario_rpc';
  end if;

  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'jornadas: propietario_rpc ya tiene CREATE sobre privado';
  end if;

  if pg_catalog.current_setting('check_function_bodies') operator(pg_catalog.<>) 'on' then
    raise exception 'jornadas: check_function_bodies debe estar activo';
  end if;

  if exists (select 1 from pg_catalog.pg_proc
              where proname operator(pg_catalog.=) 'confirmar_salida') then
    raise exception 'jornadas: confirmar_salida ya existe';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Implementación privilegiada (SECURITY DEFINER, owner propietario_rpc)
-- ---------------------------------------------------------------------------
create function privado.confirmar_salida(
  p_idempotency_key pg_catalog.uuid,
  p_jornada_id pg_catalog.uuid
)
returns pg_catalog.uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
  v_estado pg_catalog.text;
  v_filas integer;
begin
  -- Paso 0 (E-SL1; ADR-001 §6, §16 T14 y §18.4.16): una transacción de sólo lectura
  -- (GET o HEAD por PostgREST) se rechaza antes de cualquier acceso a datos y de la
  -- consulta de idempotencia. SQLSTATE 25006 → HTTP 405 en PostgREST.
  if pg_catalog.current_setting('transaction_read_only') = 'on' then
    raise exception using
      errcode = '25006',
      message = 'jornada_metodo_no_permitido';
  end if;

  -- Paso 1. P13-jornadas: los bloqueos sólo serializan bajo READ COMMITTED.
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

  -- Paso 3. Estructura: clave y jornada (D-N1).
  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'jornada_clave_invalida';
  end if;

  if p_jornada_id is null then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  -- Paso 4. Huella v1.
  v_huella := encode(sha256(convert_to(
    'v1|salida_jornada|' || p_jornada_id::pg_catalog.text, 'UTF8')), 'hex');

  -- Paso 5. Replay previo, sin bloqueos, después de autorizar y validar la estructura.
  select o.id, o.tipo, o.huella
    into v_previa_id, v_previa_tipo, v_previa_huella
    from public.operaciones o
   where o.empresa_id = v_empresa
     and o.actor_id = v_uid
     and o.idempotency_key = p_idempotency_key;

  if found then
    if v_previa_tipo = 'salida_jornada' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 6. Lectura sin bloqueo de la jornada. Inexistente o de otra empresa → PT404.
  -- Paso 7: confirmar_salida no toma advisory locks (ADR-001 §18.4.5).
  perform 1
     from public.jornadas j
    where j.id = p_jornada_id
      and j.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  -- Paso 8. Nivel 3: la fila de la jornada, bloqueada; el estado se lee bajo FOR UPDATE.
  select j.estado
    into v_estado
    from public.jornadas j
   where j.id = p_jornada_id
     and j.empresa_id = v_empresa
     for update;

  if not found then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  -- Paso 8a. Segunda consulta de la clave (H2-R1).
  select o.id, o.tipo, o.huella
    into v_previa_id, v_previa_tipo, v_previa_huella
    from public.operaciones o
   where o.empresa_id = v_empresa
     and o.actor_id = v_uid
     and o.idempotency_key = p_idempotency_key;

  if found then
    if v_previa_tipo = 'salida_jornada' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 8b: no hay valores usados como clave de advisory que reverificar.

  -- Paso 9. Reserva de la clave, con jornada_id. Un rechazo posterior la revierte.
  begin
    insert into public.operaciones (
      empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id
    )
    values (
      v_empresa, v_uid, 'salida_jornada', p_idempotency_key, v_huella, p_jornada_id
    )
    on conflict (empresa_id, actor_id, idempotency_key) do nothing
    returning id into v_operacion;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or not_null_violation or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'jornada_error_interno';
  end;

  if v_operacion is null then
    -- Otra transacción confirmó la misma clave entre los pasos 8a y 9 (otra jornada).
    select o.id, o.tipo, o.huella
      into v_previa_id, v_previa_tipo, v_previa_huella
      from public.operaciones o
     where o.empresa_id = v_empresa
       and o.actor_id = v_uid
       and o.idempotency_key = p_idempotency_key;

    if v_previa_tipo = 'salida_jornada' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 10. Validaciones de negocio (ADR-007 §2.2) con los datos leídos bajo FOR
  -- UPDATE: estado y, después, carga neta positiva en al menos un producto. El camión
  -- puede estar dado de baja (§2.7).
  if v_estado <> 'cargada' then
    raise exception using errcode = 'PT409', message = 'jornada_estado_invalido';
  end if;

  if not exists (select 1
                   from public.movimientos_stock m
                  where m.empresa_id = v_empresa
                    and m.jornada_id = p_jornada_id
                    and m.tipo_movimiento in ('carga', 'descarga')
                  group by m.producto_id
                 having sum(case when m.tipo_movimiento = 'carga'
                                 then m.cantidad::bigint
                                 else -m.cantidad::bigint end) > 0) then
    raise exception using errcode = 'PT409', message = 'jornada_carga_neta_cero';
  end if;

  -- Paso 12. Escritura: cargada → en_reparto, verificada por ROW_COUNT. Una
  -- violación residual de restricción o de RLS no revela su nombre.
  begin
    update public.jornadas
       set estado = 'en_reparto'
     where id = p_jornada_id
       and empresa_id = v_empresa
       and estado = 'cargada';

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
create function public.confirmar_salida(
  p_idempotency_key pg_catalog.uuid,
  p_jornada_id pg_catalog.uuid
)
returns pg_catalog.uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.confirmar_salida(p_idempotency_key, p_jornada_id)
$$;

-- ---------------------------------------------------------------------------
-- EXECUTE (firma exacta) y propiedad (O-3)
-- ---------------------------------------------------------------------------
revoke all on function privado.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)
  from public, anon, authenticated, service_role;
grant execute on function privado.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)
  to authenticated;

revoke all on function public.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)
  to authenticated;

-- CREATE sobre privado sólo mientras se transfiere la propiedad.
grant create on schema privado to propietario_rpc;
alter function privado.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)
  owner to propietario_rpc;
revoke create on schema privado from propietario_rpc;

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
begin
  if (select pg_catalog.count(*) from pg_catalog.pg_proc
       where proname operator(pg_catalog.=) 'confirmar_salida') operator(pg_catalog.<>) 2
     or not exists (
       select 1 from pg_catalog.pg_proc p
        where p.oid operator(pg_catalog.=) 'privado.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)'::pg_catalog.regprocedure
          and p.prosecdef and p.provolatile operator(pg_catalog.=) 'v'
          and p.proowner operator(pg_catalog.=) 'propietario_rpc'::pg_catalog.regrole
          and p.proconfig operator(pg_catalog.=) array['search_path=""']::pg_catalog.text[]
          and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
              operator(pg_catalog.=) array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']::pg_catalog.text[])
     or not exists (
       select 1 from pg_catalog.pg_proc p
        where p.oid operator(pg_catalog.=) 'public.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)'::pg_catalog.regprocedure
          and not p.prosecdef and p.provolatile operator(pg_catalog.=) 'v'
          and p.proowner operator(pg_catalog.=) 'postgres'::pg_catalog.regrole
          and p.proconfig operator(pg_catalog.=) array['search_path=""']::pg_catalog.text[]
          and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
              operator(pg_catalog.=) array['authenticated=X/postgres', 'postgres=X/postgres']::pg_catalog.text[]) then
    raise exception 'jornadas: confirmar_salida fuera de lo aprobado (seguridad, owner, search_path, ACL o sobrecargas)';
  end if;

  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
     or pg_catalog.has_function_privilege('anon', 'public.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'public.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'privado.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'privado.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)', 'EXECUTE') then
    raise exception 'jornadas: confirmar_salida concede privilegios fuera de lo aprobado (CREATE o EXECUTE)';
  end if;
end $$;
