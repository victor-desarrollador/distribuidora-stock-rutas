-- T4 — RPC corregir_jornada (Blueprint §7.5, §9 y §12; ADR-007 §2.1, §2.3.2, §2.4,
-- §2.7, §5 y §7 casos 10, 11, 12, 22 y 24; ADR-001 Topología D, P11, O-3, §17.1,
-- §18.4.2 a §18.4.9 con H-01 y H2-R1, y E-SL1 §18.4.16, aprobada para validación
-- controlada el 04/11/2026).
--
-- Una sola RPC: corregir_jornada(uuid, uuid, date, uuid, text) — clave, jornada,
-- fecha final, camión final y motivo — que devuelve el uuid de la OPERACIÓN
-- (también en replay). Sólo dueño y encargado activos. Sin cambios de esquema,
-- grants ni políticas: usa lo que dejó D-1 (tipo correccion_jornada, historial
-- public.correcciones_jornada, UPDATE (fecha, camion_id) de propietario_rpc sobre
-- jornadas). No define helpers (§18.4.6).
--
-- Reglas de negocio (ADR-007 §2.4 y §2.7; decisiones humanas del 04/11/2026):
--   - Sólo en estado abierta y sin movimientos de stock asociados.
--   - Motivo obligatorio (btrim); idempotente.
--   - Se revalidan SIEMPRE la fecha y el camión finales, aunque no cambien:
--     fecha >= día operativo actual (America/Argentina/Tucuman); camión de la
--     empresa y activo; par (camión, fecha) libre incluso frente a jornadas
--     cerradas; camión sin otra jornada sin cerrar; vendedor vigente sin otra
--     jornada en la fecha final. No se exige que el vendedor vigente esté activo.
--   - No cambia el estado ni el vendedor; no genera movimientos. El par anterior
--     queda libre.
--   - Historial append-only en public.correcciones_jornada.
--
-- Precedencia del paso 10 (decisión humana del 04/11/2026): estado → movimientos →
-- fecha final → existencia y actividad del camión final → jornada_sin_cambios →
-- jornada_duplicada → jornada_camion_con_jornada_abierta → jornada_vendedor_ocupado.
--
-- Orden (ADR-001 §18.4.3): paso 0 E-SL1 (transaction_read_only = on → 25006
-- jornada_metodo_no_permitido, antes de todo); 1 READ COMMITTED; 2 identidad y rol;
-- 3 estructura (clave → jornada → fecha → camión → motivo); 4 huella; 5 replay sin
-- bloqueos; 6 lectura sin bloqueo de la jornada (camión actual y vendedor vigente);
-- 7 advisory nivel 1 (camión actual y final, en orden de uuid, sin duplicar) y
-- nivel 2 (vendedor vigente, SIEMPRE: H-01); 8 FOR UPDATE de la jornada (nivel 3);
-- 8a segunda consulta de la clave; 8b reverificación de camión y vendedor; 9
-- reserva; 10 negocio; 12 historial y UPDATE de la jornada. No toma nivel 4.
--
-- Huella v1: 'v1|correccion_jornada|<jornada>|<YYYY-MM-DD>|<camión>|+<motivo btrim>'.
--
-- pg_temp (ADR-001 §17.1): todos los tipos y casts del cuerpo y de esta migración
-- están calificados con pg_catalog, y las relaciones con su esquema. Exige A1.
--
-- Fuera de alcance: transiciones de estado, reapertura, frontend, CI. `service_role`
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
     or pg_catalog.to_regclass('public.correcciones_jornada') is null
     or pg_catalog.to_regprocedure('privado.usuario_actual()') is null
     or pg_catalog.to_regprocedure('privado.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)') is null then
    raise exception 'jornadas: faltan D-1, usuario_actual o confirmar_salida (T7)';
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
              where proname operator(pg_catalog.=) 'corregir_jornada') then
    raise exception 'jornadas: corregir_jornada ya existe';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Implementación privilegiada (SECURITY DEFINER, owner propietario_rpc)
-- ---------------------------------------------------------------------------
create function privado.corregir_jornada(
  p_idempotency_key pg_catalog.uuid,
  p_jornada_id pg_catalog.uuid,
  p_fecha pg_catalog.date,
  p_camion_id pg_catalog.uuid,
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
  v_huella pg_catalog.text;
  v_operacion pg_catalog.uuid;
  v_previa_id pg_catalog.uuid;
  v_previa_tipo pg_catalog.text;
  v_previa_huella pg_catalog.text;
  v_camion_actual pg_catalog.uuid;
  v_vigente pg_catalog.uuid;
  v_camion_bloqueado pg_catalog.uuid;
  v_vigente_bloqueado pg_catalog.uuid;
  v_estado pg_catalog.text;
  v_fecha pg_catalog.date;
  v_hoy pg_catalog.date;
  v_camion_activo boolean;
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

  -- Paso 3. Estructura, sin leer estado mutable: clave → jornada → fecha → camión
  -- → motivo. La fecha debe ser finita y estar entre 0001-01-01 y 9999-12-31, como
  -- en abrir_jornada (T1-4): la huella v1 no representa otras fechas.
  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'jornada_clave_invalida';
  end if;

  if p_jornada_id is null then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  if p_fecha is null
     or not pg_catalog.isfinite(p_fecha)
     or p_fecha < pg_catalog.date '0001-01-01'
     or p_fecha > pg_catalog.date '9999-12-31' then
    raise exception using errcode = 'PT400', message = 'jornada_fecha_invalida';
  end if;

  if p_camion_id is null then
    raise exception using errcode = 'PT404', message = 'jornada_camion_no_encontrado';
  end if;

  v_motivo := pg_catalog.btrim(p_motivo);
  if v_motivo is null or v_motivo = '' then
    raise exception using errcode = 'PT400', message = 'jornada_motivo_invalido';
  end if;

  -- Paso 4. Huella v1.
  v_huella := encode(sha256(convert_to(
    'v1|correccion_jornada|' || p_jornada_id::pg_catalog.text || '|'
      || to_char(p_fecha, 'YYYY-MM-DD') || '|' || p_camion_id::pg_catalog.text
      || '|+' || v_motivo,
    'UTF8')), 'hex');

  -- Paso 5. Replay previo, sin bloqueos, después de autorizar y validar la estructura.
  select o.id, o.tipo, o.huella
    into v_previa_id, v_previa_tipo, v_previa_huella
    from public.operaciones o
   where o.empresa_id = v_empresa
     and o.actor_id = v_uid
     and o.idempotency_key = p_idempotency_key;

  if found then
    if v_previa_tipo = 'correccion_jornada' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 6. Lectura sin bloqueo de la jornada, para obtener las claves de los
  -- advisory: el camión actual y el vendedor vigente. Inexistente o de otra
  -- empresa → PT404.
  select j.camion_id, j.vendedor_id
    into v_camion_actual, v_vigente
    from public.jornadas j
   where j.id = p_jornada_id
     and j.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'jornada_no_encontrada';
  end if;

  -- Paso 7. Nivel 1: camión actual y camión final, en orden ascendente de uuid y
  -- uno solo si coinciden. Nivel 2: el vendedor vigente, SIEMPRE (H-01), cambie el
  -- camión, la fecha o ambos. Se liberan al terminar la transacción.
  if v_camion_actual = p_camion_id then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:camion:' || v_empresa::pg_catalog.text || ':' || v_camion_actual::pg_catalog.text, 0));
  elsif v_camion_actual < p_camion_id then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:camion:' || v_empresa::pg_catalog.text || ':' || v_camion_actual::pg_catalog.text, 0));
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:camion:' || v_empresa::pg_catalog.text || ':' || p_camion_id::pg_catalog.text, 0));
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:camion:' || v_empresa::pg_catalog.text || ':' || p_camion_id::pg_catalog.text, 0));
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'jornadas:camion:' || v_empresa::pg_catalog.text || ':' || v_camion_actual::pg_catalog.text, 0));
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'jornadas:vendedor:' || v_empresa::pg_catalog.text || ':' || v_vigente::pg_catalog.text, 0));

  -- Paso 8. Nivel 3: la fila de la jornada, bloqueada. Con los bloqueos de los
  -- pasos 7 y 8 en poder de la transacción se releen camión, vendedor, estado y fecha.
  select j.camion_id, j.vendedor_id, j.estado, j.fecha
    into v_camion_bloqueado, v_vigente_bloqueado, v_estado, v_fecha
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
    if v_previa_tipo = 'correccion_jornada' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 8b. Reverificación de los valores usados como clave de bloqueo: si el
  -- camión o el vendedor vigente cambiaron entre los pasos 6 y 8, los advisory
  -- tomados no son los correctos. Sin efectos y reintentable con la misma clave; no
  -- se toman bloqueos fuera de orden.
  if v_camion_bloqueado is distinct from v_camion_actual
     or v_vigente_bloqueado is distinct from v_vigente then
    raise exception using errcode = 'PT409', message = 'jornada_estado_invalido';
  end if;

  -- Paso 9. Reserva de la clave, con el jornada_id que el tipo exige. Un rechazo
  -- posterior revierte esta fila con la transacción.
  begin
    insert into public.operaciones (
      empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id
    )
    values (
      v_empresa, v_uid, 'correccion_jornada', p_idempotency_key, v_huella, p_jornada_id
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

    if v_previa_tipo = 'correccion_jornada' and v_previa_huella = v_huella then
      return v_previa_id;
    end if;
    raise exception using errcode = 'PT409', message = 'jornada_conflicto_idempotencia';
  end if;

  -- Paso 10. Validaciones de negocio de ADR-007 §2.4 con los datos leídos bajo los
  -- bloqueos, en la precedencia aprobada el 04/11/2026.
  if v_estado <> 'abierta' then
    raise exception using errcode = 'PT409', message = 'jornada_estado_invalido';
  end if;

  -- Defensa en profundidad: en abierta no puede haber movimientos (§2.4.1).
  if exists (select 1 from public.movimientos_stock m
              where m.empresa_id = v_empresa
                and m.jornada_id = p_jornada_id) then
    raise exception using errcode = 'PT409', message = 'jornada_con_movimientos';
  end if;

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

  -- §2.7: un camión inactivo no puede ser destino de una corrección (revalidado
  -- aunque el camión no cambie, decisión humana del 04/11/2026).
  if v_camion_activo is not true then
    raise exception using errcode = 'PT409', message = 'jornada_camion_inactivo';
  end if;

  if p_fecha = v_fecha and p_camion_id = v_camion_bloqueado then
    raise exception using errcode = 'PT409', message = 'jornada_sin_cambios';
  end if;

  if exists (select 1 from public.jornadas j
              where j.empresa_id = v_empresa
                and j.camion_id = p_camion_id
                and j.fecha = p_fecha
                and j.id <> p_jornada_id) then
    raise exception using errcode = 'PT409', message = 'jornada_duplicada';
  end if;

  if exists (select 1 from public.jornadas j
              where j.empresa_id = v_empresa
                and j.camion_id = p_camion_id
                and j.estado <> 'cerrada'
                and j.id <> p_jornada_id) then
    raise exception using errcode = 'PT409', message = 'jornada_camion_con_jornada_abierta';
  end if;

  if exists (select 1 from public.jornadas j
              where j.empresa_id = v_empresa
                and j.vendedor_id = v_vigente_bloqueado
                and j.fecha = p_fecha
                and j.id <> p_jornada_id) then
    raise exception using errcode = 'PT409', message = 'jornada_vendedor_ocupado';
  end if;

  -- Paso 12. Escrituras: la fila append-only del historial y el único cambio de la
  -- jornada (fecha y camión). El UPDATE debe afectar exactamente una fila (T2-SR-1):
  -- una policy que la filtre no produce error. Una violación residual de
  -- restricción o de privilegio no revela su nombre.
  begin
    insert into public.correcciones_jornada (
      empresa_id, jornada_id, operacion_id, fecha_anterior, fecha_nueva,
      camion_anterior_id, camion_nuevo_id, motivo, actor_id
    )
    values (
      v_empresa, p_jornada_id, v_operacion, v_fecha, p_fecha,
      v_camion_bloqueado, p_camion_id, v_motivo, v_uid
    );

    update public.jornadas
       set fecha = p_fecha,
           camion_id = p_camion_id
     where id = p_jornada_id
       and empresa_id = v_empresa
       and estado = 'abierta';

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
create function public.corregir_jornada(
  p_idempotency_key pg_catalog.uuid,
  p_jornada_id pg_catalog.uuid,
  p_fecha pg_catalog.date,
  p_camion_id pg_catalog.uuid,
  p_motivo pg_catalog.text
)
returns pg_catalog.uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.corregir_jornada(p_idempotency_key, p_jornada_id, p_fecha, p_camion_id, p_motivo)
$$;

-- ---------------------------------------------------------------------------
-- EXECUTE (firma exacta) y propiedad (O-3)
-- ---------------------------------------------------------------------------
revoke all on function privado.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)
  from public, anon, authenticated, service_role;
grant execute on function privado.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)
  to authenticated;

revoke all on function public.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)
  from public, anon, authenticated, service_role;
grant execute on function public.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)
  to authenticated;

-- CREATE sobre privado sólo mientras se transfiere la propiedad.
grant create on schema privado to propietario_rpc;
alter function privado.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)
  owner to propietario_rpc;
revoke create on schema privado from propietario_rpc;

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
begin
  if (select pg_catalog.count(*) from pg_catalog.pg_proc
       where proname operator(pg_catalog.=) 'corregir_jornada') operator(pg_catalog.<>) 2
     or not exists (
       select 1 from pg_catalog.pg_proc p
        where p.oid operator(pg_catalog.=) 'privado.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)'::pg_catalog.regprocedure
          and p.prosecdef and p.provolatile operator(pg_catalog.=) 'v'
          and p.proowner operator(pg_catalog.=) 'propietario_rpc'::pg_catalog.regrole
          and p.proconfig operator(pg_catalog.=) array['search_path=""']::pg_catalog.text[]
          and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
              operator(pg_catalog.=) array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']::pg_catalog.text[])
     or not exists (
       select 1 from pg_catalog.pg_proc p
        where p.oid operator(pg_catalog.=) 'public.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)'::pg_catalog.regprocedure
          and not p.prosecdef and p.provolatile operator(pg_catalog.=) 'v'
          and p.proowner operator(pg_catalog.=) 'postgres'::pg_catalog.regrole
          and p.proconfig operator(pg_catalog.=) array['search_path=""']::pg_catalog.text[]
          and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
              operator(pg_catalog.=) array['authenticated=X/postgres', 'postgres=X/postgres']::pg_catalog.text[]) then
    raise exception 'jornadas: corregir_jornada fuera de lo aprobado (seguridad, owner, search_path, ACL o sobrecargas)';
  end if;

  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
     or pg_catalog.has_function_privilege('anon', 'public.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'public.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'privado.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'privado.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)', 'EXECUTE') then
    raise exception 'jornadas: corregir_jornada concede privilegios fuera de lo aprobado (CREATE o EXECUTE)';
  end if;
end $$;
