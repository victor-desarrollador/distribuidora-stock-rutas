-- T5 — RPC registrar_carga (Blueprint §7.2, §7.4, §7.5, §9 y §12; ADR-007 §2.2, §2.5,
-- §2.7 y §7 casos 4, 13 a 17, 22 y 24; ADR-005 D-R2; ADR-001 Topología D, P11, O-3,
-- §17.1, §18.4.2 a §18.4.9 y E-SL1 §18.4.16, aprobada para validación controlada el
-- 04/11/2026).
--
-- Una sola RPC: registrar_carga(uuid, uuid, uuid[], integer[]) — clave, jornada,
-- productos y cantidades — que devuelve el uuid de la OPERACIÓN (también en replay).
-- Sólo dueño y encargado activos. Sin cambios de esquema, grants ni políticas: usa
-- lo que dejó D-1 (20261030120000_jornadas_esquema.sql: tipo carga, jornada_id, FK de
-- referencia de 5 columnas, política del ledger para carga, INSERT (jornada_id) y
-- UPDATE (estado) de propietario_rpc). No define helpers (ADR-001 §18.4.6).
--
-- Reglas de negocio (ADR-007 §2.5 y §2.7):
--   - Movimiento carga: depósito propio → ubicación del camión de la jornada, con
--     jornada_id, una fila por producto. Operación atómica.
--   - Estados admitidos: abierta y cargada. La primera carga lleva abierta → cargada;
--     las siguientes no cambian el estado.
--   - Sólo productos activos de la empresa; cantidades enteras positivas en unidad
--     mínima (unidades, o gramos del peso realmente cargado; ADR-005 D-R2).
--   - El depósito nunca queda negativo. La cuarentena no se carga: el origen es
--     siempre el depósito.
--   - Stock residual: antes de la primera carga (jornada abierta) el saldo de la
--     ubicación del camión debe ser cero en todos los productos.
--   - Camión inactivo → PT409 jornada_camion_inactivo.
--
-- Orden (ADR-001 §18.4.3): paso 0 E-SL1 (transaction_read_only = on → 25006
-- jornada_metodo_no_permitido, antes de todo); 1 READ COMMITTED; 2 identidad y rol;
-- 3 estructura (clave, jornada, arreglos, repetidos, cantidades); 4 huella; 5 replay
-- sin bloqueos; 6 lectura sin bloqueo de la jornada; 8 FOR UPDATE de la jornada
-- (nivel 3); 8a segunda consulta de la clave; 9 reserva; 10 negocio (estado, camión
-- activo, ubicaciones, productos inexistentes y luego inactivos); 11 advisory de stock
-- del depósito por producto (nivel 4, en orden de uuid; misma cadena que
-- mover_a_cuarentena y registrar_merma), stock residual y saldo; 12 movimientos y
-- UPDATE del estado. No toma advisory de niveles 1 ni 2. La precedencia dentro de los
-- pasos 10 y 11 es una elección de implementación fijada por los tests, no una regla
-- nueva.
--
-- Huella v1: 'v1|carga|<jornada>|<producto>:<cantidad>,…' con las líneas ordenadas por
-- el texto del uuid del producto (collation C).
--
-- pg_temp (ADR-001 §17.1, plan de remediación): todos los tipos y casts del cuerpo y
-- de esta migración están calificados con pg_catalog, y las relaciones con su
-- esquema. Exige A1 (usuario_actual calificado).
--
-- Fuera de alcance: registrar_descarga, confirmar_salida, corregir_jornada, frontend,
-- CI. `service_role` sin privilegios (P11). Validación exclusivamente local/staging.
-- Prohibido aplicar en producción.

do $$
begin
  if current_user operator(pg_catalog.<>) 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;

  if pg_catalog.to_regclass('public.jornadas') is null
     or pg_catalog.to_regclass('public.operaciones') is null
     or pg_catalog.to_regclass('public.movimientos_stock') is null
     or pg_catalog.to_regclass('public.ubicaciones') is null
     or pg_catalog.to_regclass('public.productos') is null
     or pg_catalog.to_regclass('public.camiones') is null
     or pg_catalog.to_regprocedure('privado.usuario_actual()') is null then
    raise exception 'jornadas: faltan D-1 o tablas de Stock (jornadas, operaciones, movimientos_stock, ubicaciones, productos, camiones o usuario_actual)';
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
              where proname operator(pg_catalog.=) 'registrar_carga') then
    raise exception 'jornadas: registrar_carga ya existe';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Implementación privilegiada (SECURITY DEFINER, owner propietario_rpc)
-- ---------------------------------------------------------------------------
create function privado.registrar_carga(
  p_idempotency_key pg_catalog.uuid,
  p_jornada_id pg_catalog.uuid,
  p_productos pg_catalog.uuid[],
  p_cantidades pg_catalog.int4[]
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
  v_texto pg_catalog.text;
  v_huella pg_catalog.text;
  v_operacion pg_catalog.uuid;
  v_previa_id pg_catalog.uuid;
  v_previa_tipo pg_catalog.text;
  v_previa_huella pg_catalog.text;
  v_camion pg_catalog.uuid;
  v_estado pg_catalog.text;
  v_camion_activo boolean;
  v_deposito pg_catalog.uuid;
  v_ubicacion_camion pg_catalog.uuid;
  v_producto pg_catalog.uuid;
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

  -- Paso 3. Estructura, sin leer estado mutable: clave, jornada (D-N1), arreglos
  -- (no nulos, unidimensionales, mismo largo, uno o más elementos, sin nulos),
  -- productos repetidos y cantidades positivas.
  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'jornada_clave_invalida';
  end if;

  if p_jornada_id is null then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  if p_productos is null or p_cantidades is null
     or pg_catalog.array_ndims(p_productos) is distinct from 1
     or pg_catalog.array_ndims(p_cantidades) is distinct from 1
     or pg_catalog.cardinality(p_productos) <> pg_catalog.cardinality(p_cantidades)
     or pg_catalog.array_position(p_productos, null) is not null
     or pg_catalog.array_position(p_cantidades, null) is not null then
    raise exception using errcode = 'PT400', message = 'jornada_lineas_invalidas';
  end if;

  if (select pg_catalog.count(distinct x.producto) from pg_catalog.unnest(p_productos) as x(producto))
     <> pg_catalog.cardinality(p_productos) then
    raise exception using errcode = 'PT400', message = 'jornada_producto_repetido';
  end if;

  if exists (select 1 from pg_catalog.unnest(p_cantidades) as x(cantidad) where x.cantidad <= 0) then
    raise exception using errcode = 'PT400', message = 'jornada_cantidad_invalida';
  end if;

  -- Paso 4. Huella v1, con las líneas ordenadas por el texto del uuid del producto.
  select 'v1|carga|' || p_jornada_id::pg_catalog.text || '|'
         || pg_catalog.string_agg(p_productos[l.i]::pg_catalog.text || ':' || p_cantidades[l.i]::pg_catalog.text, ','
                                  order by p_productos[l.i]::pg_catalog.text collate pg_catalog."C")
    into v_texto
    from pg_catalog.generate_subscripts(p_productos, 1) as l(i);

  v_huella := encode(sha256(convert_to(v_texto, 'UTF8')), 'hex');

  -- Paso 5. Replay previo, sin bloqueos, después de autorizar y validar la estructura.
  select o.id, o.tipo, o.huella
    into v_previa_id, v_previa_tipo, v_previa_huella
    from public.operaciones o
   where o.empresa_id = v_empresa
     and o.actor_id = v_uid
     and o.idempotency_key = p_idempotency_key;

  if found then
    if v_previa_tipo = 'carga' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 6. Lectura sin bloqueo de la jornada. Inexistente o de otra empresa → PT404.
  -- Paso 7: registrar_carga no toma advisory de niveles 1 ni 2 (ADR-001 §18.4.5).
  perform 1
     from public.jornadas j
    where j.id = p_jornada_id
      and j.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  -- Paso 8. Nivel 3: la fila de la jornada, bloqueada (I-CAMION a). Estado y camión
  -- se leen bajo FOR UPDATE.
  select j.estado, j.camion_id
    into v_estado, v_camion
    from public.jornadas j
   where j.id = p_jornada_id
     and j.empresa_id = v_empresa
     for update;

  if not found then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  -- Paso 8a. Segunda consulta de la clave (H2-R1): una solicitud repetida y
  -- concurrente que esperó el FOR UPDATE ve lo que la primera confirmó.
  select o.id, o.tipo, o.huella
    into v_previa_id, v_previa_tipo, v_previa_huella
    from public.operaciones o
   where o.empresa_id = v_empresa
     and o.actor_id = v_uid
     and o.idempotency_key = p_idempotency_key;

  if found then
    if v_previa_tipo = 'carga' and v_previa_huella = v_huella then
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
      v_empresa, v_uid, 'carga', p_idempotency_key, v_huella, p_jornada_id
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

    if v_previa_tipo = 'carga' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 10. Validaciones de negocio (ADR-007 §2.5 y §2.7) con los datos leídos bajo
  -- FOR UPDATE: estado, camión activo, ubicaciones, productos inexistentes o de otra
  -- empresa y, después, productos inactivos.
  if v_estado not in ('abierta', 'cargada') then
    raise exception using errcode = 'PT409', message = 'jornada_estado_invalido';
  end if;

  select c.activo into v_camion_activo
    from public.camiones c
   where c.id = v_camion
     and c.empresa_id = v_empresa;

  if v_camion_activo is not true then
    raise exception using errcode = 'PT409', message = 'jornada_camion_inactivo';
  end if;

  select u.id into v_deposito
    from public.ubicaciones u
   where u.empresa_id = v_empresa
     and u.tipo = 'deposito'
     and u.camion_id is null;

  select u.id into v_ubicacion_camion
    from public.ubicaciones u
   where u.empresa_id = v_empresa
     and u.tipo = 'camion'
     and u.camion_id = v_camion;

  if v_deposito is null or v_ubicacion_camion is null then
    raise exception using errcode = 'PT500', message = 'jornada_ubicacion_no_configurada';
  end if;

  if exists (select 1
               from pg_catalog.unnest(p_productos) as x(producto)
              where not exists (select 1 from public.productos pr
                                 where pr.id = x.producto
                                   and pr.empresa_id = v_empresa)) then
    raise exception using errcode = 'PT404', message = 'jornada_producto_no_encontrado';
  end if;

  if exists (select 1
               from pg_catalog.unnest(p_productos) as x(producto)
               join public.productos pr
                 on pr.id = x.producto
                and pr.empresa_id = v_empresa
              where pr.activo is not true) then
    raise exception using errcode = 'PT409', message = 'jornada_producto_inactivo';
  end if;

  -- Paso 11. Nivel 4: advisory de stock del depósito por producto, en orden de
  -- (ubicación, producto); la cadena es la de mover_a_cuarentena y registrar_merma.
  for v_producto in
    select x.producto from pg_catalog.unnest(p_productos) as x(producto) order by x.producto
  loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'stock:' || v_empresa::pg_catalog.text || ':' || v_deposito::pg_catalog.text || ':' || v_producto::pg_catalog.text, 0));
  end loop;

  -- Stock residual (sólo antes de la primera carga): ningún producto con saldo
  -- distinto de cero en la ubicación del camión.
  if v_estado = 'abierta'
     and exists (select 1
                   from public.movimientos_stock m
                  where m.empresa_id = v_empresa
                    and (m.ubicacion_destino_id = v_ubicacion_camion
                         or m.ubicacion_origen_id = v_ubicacion_camion)
                  group by m.producto_id
                 having sum(case when m.ubicacion_destino_id = v_ubicacion_camion
                                 then m.cantidad::bigint
                                 else -m.cantidad::bigint end) <> 0) then
    raise exception using errcode = 'PT409', message = 'jornada_stock_residual';
  end if;

  -- Saldo del depósito por producto (suma del ledger): nunca queda negativo.
  if exists (select 1
               from pg_catalog.generate_subscripts(p_productos, 1) as l(i)
              where p_cantidades[l.i]::bigint > (
                      select coalesce(sum(case when m.ubicacion_destino_id = v_deposito
                                               then m.cantidad::bigint
                                               else -m.cantidad::bigint end), 0)
                        from public.movimientos_stock m
                       where m.empresa_id = v_empresa
                         and m.producto_id = p_productos[l.i]
                         and (m.ubicacion_destino_id = v_deposito
                              or m.ubicacion_origen_id = v_deposito))) then
    raise exception using errcode = 'PT409', message = 'jornada_stock_insuficiente';
  end if;

  -- Paso 12. Escrituras: un movimiento carga por línea y, en la primera carga, el
  -- cambio de estado abierta → cargada. Cada escritura se verifica por ROW_COUNT; una
  -- violación residual de restricción o de RLS no revela su nombre.
  begin
    insert into public.movimientos_stock (
      empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
      ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id
    )
    select v_empresa, v_operacion, 'carga', p_productos[l.i], p_cantidades[l.i],
           v_deposito, v_ubicacion_camion, v_uid, p_jornada_id
      from pg_catalog.generate_subscripts(p_productos, 1) as l(i)
     order by p_productos[l.i];

    get diagnostics v_filas = row_count;
    if v_filas <> pg_catalog.cardinality(p_productos) then
      raise exception using errcode = 'PT500', message = 'jornada_error_interno';
    end if;

    if v_estado = 'abierta' then
      update public.jornadas
         set estado = 'cargada'
       where id = p_jornada_id
         and empresa_id = v_empresa
         and estado = 'abierta';

      get diagnostics v_filas = row_count;
      if v_filas <> 1 then
        raise exception using errcode = 'PT500', message = 'jornada_error_interno';
      end if;
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
create function public.registrar_carga(
  p_idempotency_key pg_catalog.uuid,
  p_jornada_id pg_catalog.uuid,
  p_productos pg_catalog.uuid[],
  p_cantidades pg_catalog.int4[]
)
returns pg_catalog.uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.registrar_carga(p_idempotency_key, p_jornada_id, p_productos, p_cantidades)
$$;

-- ---------------------------------------------------------------------------
-- EXECUTE (firma exacta) y propiedad (O-3)
-- ---------------------------------------------------------------------------
revoke all on function privado.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])
  from public, anon, authenticated, service_role;
grant execute on function privado.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])
  to authenticated;

revoke all on function public.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])
  from public, anon, authenticated, service_role;
grant execute on function public.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])
  to authenticated;

-- CREATE sobre privado sólo mientras se transfiere la propiedad.
grant create on schema privado to propietario_rpc;
alter function privado.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])
  owner to propietario_rpc;
revoke create on schema privado from propietario_rpc;

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
begin
  if (select pg_catalog.count(*) from pg_catalog.pg_proc
       where proname operator(pg_catalog.=) 'registrar_carga') operator(pg_catalog.<>) 2
     or not exists (
       select 1 from pg_catalog.pg_proc p
        where p.oid operator(pg_catalog.=) 'privado.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])'::pg_catalog.regprocedure
          and p.prosecdef and p.provolatile operator(pg_catalog.=) 'v'
          and p.proowner operator(pg_catalog.=) 'propietario_rpc'::pg_catalog.regrole
          and p.proconfig operator(pg_catalog.=) array['search_path=""']::pg_catalog.text[]
          and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
              operator(pg_catalog.=) array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']::pg_catalog.text[])
     or not exists (
       select 1 from pg_catalog.pg_proc p
        where p.oid operator(pg_catalog.=) 'public.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])'::pg_catalog.regprocedure
          and not p.prosecdef and p.provolatile operator(pg_catalog.=) 'v'
          and p.proowner operator(pg_catalog.=) 'postgres'::pg_catalog.regrole
          and p.proconfig operator(pg_catalog.=) array['search_path=""']::pg_catalog.text[]
          and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
              operator(pg_catalog.=) array['authenticated=X/postgres', 'postgres=X/postgres']::pg_catalog.text[]) then
    raise exception 'jornadas: registrar_carga fuera de lo aprobado (seguridad, owner, search_path, ACL o sobrecargas)';
  end if;

  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
     or pg_catalog.has_function_privilege('anon', 'public.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'public.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'privado.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'privado.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])', 'EXECUTE') then
    raise exception 'jornadas: registrar_carga concede privilegios fuera de lo aprobado (CREATE o EXECUTE)';
  end if;
end $$;
