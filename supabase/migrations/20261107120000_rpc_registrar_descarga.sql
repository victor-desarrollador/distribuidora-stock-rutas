-- T6 — RPC registrar_descarga (Blueprint §7.2, §7.4, §7.5, §9 y §12; ADR-007 §2.2,
-- §2.6, §2.7 y §7 casos 18, 19, 22 y 24; ADR-005 D-R2; ADR-001 Topología D, P11, O-3,
-- §17.1, §18.4.2 a §18.4.9 y E-SL1 §18.4.16, aprobada para validación controlada el
-- 04/11/2026).
--
-- Una sola RPC: registrar_descarga(uuid, uuid, uuid[], integer[], text) — clave,
-- jornada, productos, cantidades y motivo — que devuelve el uuid de la OPERACIÓN
-- (también en replay). Sólo dueño y encargado activos. Sin cambios de esquema, grants
-- ni políticas: usa lo que dejó D-1 (20261030120000_jornadas_esquema.sql: tipo
-- descarga, jornada_id, FK de referencia de 5 columnas, política del ledger para
-- descarga, INSERT (jornada_id) de propietario_rpc). No define helpers (§18.4.6).
--
-- Reglas de negocio (ADR-007 §2.6 y §2.7):
--   - Movimiento descarga: ubicación del camión de la jornada → depósito propio, con
--     jornada_id y motivo (btrim), una fila por producto. Operación atómica y
--     compensatoria: no edita ni borra movimientos previos.
--   - Sólo en estado cargada. El estado no cambia (aunque el camión quede vacío).
--   - Motivo obligatorio: nulo o vacío después de btrim → PT400 jornada_motivo_invalido.
--   - Por producto, la cantidad no supera lo cargado neto de esa jornada (cargas −
--     descargas) ni el saldo de la ubicación del camión → PT409
--     jornada_descarga_excede_carga.
--   - Se admite descargar un producto dado de baja (§2.6.3) y con el camión dado de
--     baja (§2.7): no se valida que el producto ni el camión estén activos.
--
-- Orden (ADR-001 §18.4.3): paso 0 E-SL1 (transaction_read_only = on → 25006
-- jornada_metodo_no_permitido, antes de todo); 1 READ COMMITTED; 2 identidad y rol;
-- 3 estructura (clave, jornada, motivo, arreglos, repetidos, cantidades); 4 huella;
-- 5 replay sin bloqueos; 6 lectura sin bloqueo de la jornada; 8 FOR UPDATE de la
-- jornada (nivel 3); 8a segunda consulta de la clave; 9 reserva; 10 negocio
-- (estado, ubicaciones, productos inexistentes o de otra empresa); 11 advisory de
-- stock de la ubicación del camión por producto (nivel 4, en orden de uuid; I-CAMION
-- c), carga neta y saldo del camión; 12 movimientos. No toma advisory de niveles 1
-- ni 2. Precedencia aprobada por el usuario (04/11/2026): estado → ubicaciones →
-- productos → carga neta y saldo.
--
-- Huella v1: 'v1|descarga|<jornada>|<producto>:<cantidad>,…|+<motivo con btrim>' con
-- las líneas ordenadas por el texto del uuid del producto (collation C).
--
-- pg_temp (ADR-001 §17.1): todos los tipos y casts del cuerpo y de esta migración
-- están calificados con pg_catalog, y las relaciones con su esquema. Exige A1.
--
-- Fuera de alcance: confirmar_salida, corregir_jornada, frontend, CI. `service_role`
-- sin privilegios (P11). Validación exclusivamente local/staging. Prohibido aplicar
-- en producción.

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
     or pg_catalog.to_regprocedure('privado.usuario_actual()') is null
     or pg_catalog.to_regprocedure('privado.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])') is null then
    raise exception 'jornadas: faltan D-1, tablas de Stock, usuario_actual o registrar_carga (T5)';
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
              where proname operator(pg_catalog.=) 'registrar_descarga') then
    raise exception 'jornadas: registrar_descarga ya existe';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Implementación privilegiada (SECURITY DEFINER, owner propietario_rpc)
-- ---------------------------------------------------------------------------
create function privado.registrar_descarga(
  p_idempotency_key pg_catalog.uuid,
  p_jornada_id pg_catalog.uuid,
  p_productos pg_catalog.uuid[],
  p_cantidades pg_catalog.int4[],
  p_motivo pg_catalog.text
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
  v_motivo pg_catalog.text;
  v_texto pg_catalog.text;
  v_huella pg_catalog.text;
  v_operacion pg_catalog.uuid;
  v_previa_id pg_catalog.uuid;
  v_previa_tipo pg_catalog.text;
  v_previa_huella pg_catalog.text;
  v_camion pg_catalog.uuid;
  v_estado pg_catalog.text;
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

  -- Paso 3. Estructura, sin leer estado mutable: clave, jornada (D-N1), motivo,
  -- arreglos (no nulos, unidimensionales, mismo largo, uno o más elementos, sin
  -- nulos), productos repetidos y cantidades positivas.
  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'jornada_clave_invalida';
  end if;

  if p_jornada_id is null then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  v_motivo := pg_catalog.btrim(p_motivo);
  if v_motivo is null or v_motivo = '' then
    raise exception using errcode = 'PT400', message = 'jornada_motivo_invalido';
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

  -- Paso 4. Huella v1, con las líneas ordenadas por el texto del uuid del producto y
  -- el motivo con btrim.
  select 'v1|descarga|' || p_jornada_id::pg_catalog.text || '|'
         || pg_catalog.string_agg(p_productos[l.i]::pg_catalog.text || ':' || p_cantidades[l.i]::pg_catalog.text, ','
                                  order by p_productos[l.i]::pg_catalog.text collate pg_catalog."C")
         || '|+' || v_motivo
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
    if v_previa_tipo = 'descarga' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 6. Lectura sin bloqueo de la jornada. Inexistente o de otra empresa → PT404.
  -- Paso 7: registrar_descarga no toma advisory de niveles 1 ni 2 (ADR-001 §18.4.5).
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

  -- Paso 8a. Segunda consulta de la clave (H2-R1).
  select o.id, o.tipo, o.huella
    into v_previa_id, v_previa_tipo, v_previa_huella
    from public.operaciones o
   where o.empresa_id = v_empresa
     and o.actor_id = v_uid
     and o.idempotency_key = p_idempotency_key;

  if found then
    if v_previa_tipo = 'descarga' and v_previa_huella = v_huella then
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
      v_empresa, v_uid, 'descarga', p_idempotency_key, v_huella, p_jornada_id
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

    if v_previa_tipo = 'descarga' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 10. Validaciones de negocio (ADR-007 §2.6 y §2.7) con los datos leídos bajo
  -- FOR UPDATE: estado, ubicaciones y productos inexistentes o de otra empresa. No se
  -- valida que el camión ni los productos estén activos (§2.6.3 y §2.7).
  if v_estado <> 'cargada' then
    raise exception using errcode = 'PT409', message = 'jornada_estado_invalido';
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

  -- Paso 11. Nivel 4: advisory de stock de la ubicación del camión por producto (la
  -- descarga debita el camión; I-CAMION c), en orden de (ubicación, producto).
  for v_producto in
    select x.producto from pg_catalog.unnest(p_productos) as x(producto) order by x.producto
  loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'stock:' || v_empresa::pg_catalog.text || ':' || v_ubicacion_camion::pg_catalog.text || ':' || v_producto::pg_catalog.text, 0));
  end loop;

  -- Por producto: la cantidad no supera lo cargado neto de esta jornada (cargas −
  -- descargas) ni el saldo de la ubicación del camión (suma del ledger).
  if exists (select 1
               from pg_catalog.generate_subscripts(p_productos, 1) as l(i)
              where p_cantidades[l.i]::bigint > (
                      select coalesce(sum(case when m.tipo_movimiento = 'carga'
                                               then m.cantidad::bigint
                                               else -m.cantidad::bigint end), 0)
                        from public.movimientos_stock m
                       where m.empresa_id = v_empresa
                         and m.jornada_id = p_jornada_id
                         and m.producto_id = p_productos[l.i]
                         and m.tipo_movimiento in ('carga', 'descarga'))
                 or p_cantidades[l.i]::bigint > (
                      select coalesce(sum(case when m.ubicacion_destino_id = v_ubicacion_camion
                                               then m.cantidad::bigint
                                               else -m.cantidad::bigint end), 0)
                        from public.movimientos_stock m
                       where m.empresa_id = v_empresa
                         and m.producto_id = p_productos[l.i]
                         and (m.ubicacion_destino_id = v_ubicacion_camion
                              or m.ubicacion_origen_id = v_ubicacion_camion))) then
    raise exception using errcode = 'PT409', message = 'jornada_descarga_excede_carga';
  end if;

  -- Paso 12. Escrituras: un movimiento descarga por línea, verificado por ROW_COUNT;
  -- el estado no cambia. Una violación residual de restricción o de RLS no revela su
  -- nombre.
  begin
    insert into public.movimientos_stock (
      empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
      ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id, motivo
    )
    select v_empresa, v_operacion, 'descarga', p_productos[l.i], p_cantidades[l.i],
           v_ubicacion_camion, v_deposito, v_uid, p_jornada_id, v_motivo
      from pg_catalog.generate_subscripts(p_productos, 1) as l(i)
     order by p_productos[l.i];

    get diagnostics v_filas = row_count;
    if v_filas <> pg_catalog.cardinality(p_productos) then
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
create function public.registrar_descarga(
  p_idempotency_key pg_catalog.uuid,
  p_jornada_id pg_catalog.uuid,
  p_productos pg_catalog.uuid[],
  p_cantidades pg_catalog.int4[],
  p_motivo pg_catalog.text
)
returns pg_catalog.uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.registrar_descarga(p_idempotency_key, p_jornada_id, p_productos, p_cantidades, p_motivo)
$$;

-- ---------------------------------------------------------------------------
-- EXECUTE (firma exacta) y propiedad (O-3)
-- ---------------------------------------------------------------------------
revoke all on function privado.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)
  from public, anon, authenticated, service_role;
grant execute on function privado.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)
  to authenticated;

revoke all on function public.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)
  from public, anon, authenticated, service_role;
grant execute on function public.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)
  to authenticated;

-- CREATE sobre privado sólo mientras se transfiere la propiedad.
grant create on schema privado to propietario_rpc;
alter function privado.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)
  owner to propietario_rpc;
revoke create on schema privado from propietario_rpc;

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
begin
  if (select pg_catalog.count(*) from pg_catalog.pg_proc
       where proname operator(pg_catalog.=) 'registrar_descarga') operator(pg_catalog.<>) 2
     or not exists (
       select 1 from pg_catalog.pg_proc p
        where p.oid operator(pg_catalog.=) 'privado.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)'::pg_catalog.regprocedure
          and p.prosecdef and p.provolatile operator(pg_catalog.=) 'v'
          and p.proowner operator(pg_catalog.=) 'propietario_rpc'::pg_catalog.regrole
          and p.proconfig operator(pg_catalog.=) array['search_path=""']::pg_catalog.text[]
          and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
              operator(pg_catalog.=) array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']::pg_catalog.text[])
     or not exists (
       select 1 from pg_catalog.pg_proc p
        where p.oid operator(pg_catalog.=) 'public.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)'::pg_catalog.regprocedure
          and not p.prosecdef and p.provolatile operator(pg_catalog.=) 'v'
          and p.proowner operator(pg_catalog.=) 'postgres'::pg_catalog.regrole
          and p.proconfig operator(pg_catalog.=) array['search_path=""']::pg_catalog.text[]
          and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
              operator(pg_catalog.=) array['authenticated=X/postgres', 'postgres=X/postgres']::pg_catalog.text[]) then
    raise exception 'jornadas: registrar_descarga fuera de lo aprobado (seguridad, owner, search_path, ACL o sobrecargas)';
  end if;

  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
     or pg_catalog.has_function_privilege('anon', 'public.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'public.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'privado.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'privado.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)', 'EXECUTE') then
    raise exception 'jornadas: registrar_descarga concede privilegios fuera de lo aprobado (CREATE o EXECUTE)';
  end if;
end $$;
