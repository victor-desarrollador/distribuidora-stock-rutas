-- C1.2a — RPC de intenciones persistidas: crear, ejecutar y cancelar
-- (ADR-010 v1.0 §5.5 a §5.9, enmienda v1.1 §4 y §5.2, adenda A-1 a A-4 y
-- aclaración C1.2a-D1 `docs/decisions/010-aclaracion-c1-2a-clave-nula.md`;
-- ADR-001 Topología D, P11, O-3, §17.1 y §18.3; Blueprint §8 y §12).
--
-- Seis funciones: tres implementaciones privilegiadas en `privado`
-- (SECURITY DEFINER, owner propietario_rpc, search_path = '') y tres fachadas en
-- `public` (SECURITY INVOKER, language sql, owner postgres). EXECUTE sólo para
-- `authenticated`. Sin sobrecargas (P14). Sin tablas, políticas, grants de tabla,
-- índices ni roles nuevos: usa el esquema de C1.1 tal como está.
--
--   crear_intencion_operacion(p_intencion_id uuid, p_tipo text, p_payload jsonb) -> uuid
--   ejecutar_intencion_operacion(p_intencion_id uuid)
--       -> table (estado text, operacion_id uuid, codigo_rechazo text)
--   cancelar_intencion_operacion(p_intencion_id uuid) -> text
--
-- `crear` (anexo §5.2 + C1.2a-D1): 0 READ COMMITTED; 1 identidad (PT401); 2 perfil
-- y rol (PT403); 3 identificador nulo (PT400 intencion_clave_invalida), después
-- tipo y payload (reconstrucción canónica, §5.4); 4 lock de nivel 0 por empresa y
-- actor; 5 replay (una sentencia con autorización); 5b compuerta y topes (una
-- sentencia con autorización); 7 INSERT ... ON CONFLICT DO NOTHING; 8 devuelve el
-- id. Orden de decisiones: replay -> compuerta -> topes.
--
-- `ejecutar` y `cancelar` (anexo §4.2-4.3, H1): procedimiento común O1-O3b
-- (lectura plana con autorización en la misma sentencia -> FOR UPDATE sólo si se
-- vio `pendiente` -> relectura con la misma sentencia); sólo difiere O4. `ejecutar`
-- invoca por nombre calificado las RPC de stock existentes (sin modificarlas) con
-- p_idempotency_key = id de la intención; captura únicamente PT400/PT404/PT409 y
-- dentro sólo la lista cerrada de ocho códigos stock_* (ADR-010 §5.7); todo lo
-- demás se relanza. No hay WHEN OTHERS, ni SQL dinámico, ni auth.uid().
--
-- pg_temp (ADR-001 §17.1): todos los tipos y casts están calificados con
-- pg_catalog (salvo las palabras clave boolean/integer/bigint) y las relaciones
-- con su esquema. GREATEST/COALESCE/CASE/EXISTS y los operadores no se califican.
--
-- Las columnas de salida de `ejecutar` (estado, operacion_id, codigo_rechazo) son
-- también variables de salida de plpgsql: toda referencia a esas columnas dentro
-- del cuerpo va calificada con el alias de la tabla.
--
-- ATENCIÓN: sin `reconocer` (C1.2b), una intención `confirmada` bloquea su tipo
-- para siempre (compuerta). Este corte sólo se valida en un entorno local
-- descartable y no se despliega por separado de C1.2b. Fuera de alcance:
-- reconocer, listar, índices (DT-1), p_desde futuro, D-IDEM-13.

do $$
begin
  if current_user operator(pg_catalog.<>) 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;

  if pg_catalog.to_regclass('public.intenciones_operacion') is null
     or pg_catalog.to_regclass('public.intenciones_reconocimientos') is null
     or pg_catalog.to_regclass('public.perfiles') is null
     or pg_catalog.to_regclass('public.operaciones') is null
     or pg_catalog.to_regprocedure('privado.usuario_actual()') is null
     or pg_catalog.to_regprocedure('privado.registrar_ingreso(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)') is null
     or pg_catalog.to_regprocedure('privado.mover_a_cuarentena(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)') is null
     or pg_catalog.to_regprocedure('privado.registrar_merma(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text, pg_catalog.text)') is null then
    raise exception 'intenciones: faltan C1.1, usuario_actual o las RPC de stock';
  end if;

  if (select pg_catalog.count(*) from pg_catalog.pg_policy po
       where po.polrelid operator(pg_catalog.=) 'public.intenciones_operacion'::pg_catalog.regclass) operator(pg_catalog.<>) 3
     or (select pg_catalog.count(*) from pg_catalog.pg_policy po
          where po.polrelid operator(pg_catalog.=) 'public.intenciones_reconocimientos'::pg_catalog.regclass) operator(pg_catalog.<>) 2 then
    raise exception 'intenciones: el esquema de C1.1 no tiene las 3 + 2 políticas esperadas';
  end if;

  -- A1: usuario_actual con los casts calificados (plan de remediación pg_temp).
  if (select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex')
        from pg_catalog.pg_proc p
       where p.oid operator(pg_catalog.=) pg_catalog.to_regprocedure('privado.usuario_actual()'))
     is distinct from '2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96' then
    raise exception 'intenciones: falta A1 (privado.usuario_actual() no tiene el cuerpo calificado)';
  end if;

  if not exists (select 1 from pg_catalog.pg_roles where rolname operator(pg_catalog.=) 'propietario_rpc') then
    raise exception 'intenciones: falta el rol propietario_rpc';
  end if;

  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'intenciones: propietario_rpc ya tiene CREATE sobre privado';
  end if;

  if pg_catalog.current_setting('check_function_bodies') operator(pg_catalog.<>) 'on' then
    raise exception 'intenciones: check_function_bodies debe estar activo';
  end if;

  if exists (select 1 from pg_catalog.pg_proc
              where proname operator(pg_catalog.~~) '%intencion%') then
    raise exception 'intenciones: ya existen funciones de intenciones';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- crear_intencion_operacion — implementación privilegiada
-- ---------------------------------------------------------------------------
create function privado.crear_intencion_operacion(
  p_intencion_id pg_catalog.uuid,
  p_tipo pg_catalog.text,
  p_payload pg_catalog.jsonb
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
  v_autorizado boolean;
  v_esperadas pg_catalog.text[];
  v_claves pg_catalog.text[];
  v_valor pg_catalog.text;
  v_tipo_json pg_catalog.text;
  v_producto pg_catalog.uuid;
  v_origen pg_catalog.uuid;
  v_cantidad integer;
  v_motivo pg_catalog.text;
  v_motivo_codigo pg_catalog.text;
  v_payload pg_catalog.jsonb;
  v_existe boolean;
  v_previa_tipo pg_catalog.text;
  v_previa_payload pg_catalog.jsonb;
  v_bloqueado boolean;
  v_sin_resolver bigint;
  v_hora bigint;
  v_filas integer;
begin
  -- Paso 0 (R-13): los topes y la compuerta sólo son exactos bajo READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = 'PT500', message = 'intencion_error_interno';
  end if;

  -- Paso 1. Identidad, sólo por privado.usuario_actual() (R-10, R-12).
  v_uid := privado.usuario_actual();
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'intencion_no_autenticado';
  end if;

  -- Paso 2. Perfil activo y rol habilitado, antes del lock.
  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles as p
   where p.usuario_id = v_uid;

  if v_empresa is null or v_activo is not true
     or v_rol is null or v_rol not in ('dueno', 'encargado') then
    raise exception using errcode = 'PT403', message = 'intencion_no_autorizado';
  end if;

  -- Paso 3. Estructura, sin leer tablas de negocio. C1.2a-D1: el identificador
  -- nulo se rechaza primero, antes de validar tipo y payload y de todo lock,
  -- replay o INSERT.
  if p_intencion_id is null then
    raise exception using errcode = 'PT400', message = 'intencion_clave_invalida';
  end if;

  if p_tipo is null or p_tipo not in ('ingreso', 'a_cuarentena', 'merma') then
    raise exception using errcode = 'PT400', message = 'intencion_tipo_invalido';
  end if;

  -- Payload (ADR-010 §5.4): entrada no confiable; se valida campo por campo y se
  -- reconstruye. Cualquier incumplimiento es PT400 intencion_payload_invalido.
  if p_payload is null
     or pg_catalog.jsonb_typeof(p_payload) is distinct from 'object'
     or pg_catalog.octet_length(p_payload::pg_catalog.text) > 4096 then
    raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
  end if;

  v_esperadas := case p_tipo
    when 'ingreso'
      then array['cantidad', 'motivo', 'producto_id']::pg_catalog.text[]
    when 'a_cuarentena'
      then array['cantidad', 'motivo', 'producto_id', 'ubicacion_origen_id']::pg_catalog.text[]
    else array['cantidad', 'motivo', 'motivo_codigo', 'producto_id', 'ubicacion_origen_id']::pg_catalog.text[]
  end;

  select pg_catalog.array_agg(k order by k collate "C")
    into v_claves
    from pg_catalog.jsonb_object_keys(p_payload) as k;

  if v_claves is distinct from v_esperadas then
    raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
  end if;

  -- producto_id
  if pg_catalog.jsonb_typeof(p_payload -> 'producto_id') is distinct from 'string' then
    raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
  end if;
  v_valor := p_payload ->> 'producto_id';
  if v_valor !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
  end if;
  v_producto := v_valor::pg_catalog.uuid;

  -- ubicacion_origen_id (a_cuarentena y merma)
  if p_tipo in ('a_cuarentena', 'merma') then
    if pg_catalog.jsonb_typeof(p_payload -> 'ubicacion_origen_id') is distinct from 'string' then
      raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
    end if;
    v_valor := p_payload ->> 'ubicacion_origen_id';
    if v_valor !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
    end if;
    v_origen := v_valor::pg_catalog.uuid;
  end if;

  -- cantidad: entero estricto de 1 a 2147483647, sin escala (texto normalizado por jsonb)
  if pg_catalog.jsonb_typeof(p_payload -> 'cantidad') is distinct from 'number' then
    raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
  end if;
  v_valor := p_payload ->> 'cantidad';
  if v_valor !~ '^[1-9][0-9]{0,9}$' or v_valor::bigint > 2147483647 then
    raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
  end if;
  v_cantidad := v_valor::integer;

  -- motivo: cadena o null; cadena vacía o de blancos equivale a null; hasta 500 caracteres
  v_tipo_json := pg_catalog.jsonb_typeof(p_payload -> 'motivo');
  if v_tipo_json = 'string' then
    v_motivo := nullif(pg_catalog.btrim(p_payload ->> 'motivo'), '');
    if pg_catalog.char_length(v_motivo) > 500 then
      raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
    end if;
  elsif v_tipo_json = 'null' then
    v_motivo := null;
  else
    raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
  end if;

  -- motivo_codigo (merma): cadena sin espacios laterales, de 1 a 40 caracteres
  if p_tipo = 'merma' then
    if pg_catalog.jsonb_typeof(p_payload -> 'motivo_codigo') is distinct from 'string' then
      raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
    end if;
    v_motivo_codigo := p_payload ->> 'motivo_codigo';
    if v_motivo_codigo <> pg_catalog.btrim(v_motivo_codigo)
       or pg_catalog.char_length(v_motivo_codigo) not between 1 and 40 then
      raise exception using errcode = 'PT400', message = 'intencion_payload_invalido';
    end if;
  end if;

  -- Reconstrucción: sólo este documento se almacena, se compara y se ejecuta.
  v_payload := case p_tipo
    when 'ingreso' then pg_catalog.jsonb_build_object(
        'producto_id', v_producto, 'cantidad', v_cantidad, 'motivo', v_motivo)
    when 'a_cuarentena' then pg_catalog.jsonb_build_object(
        'producto_id', v_producto, 'ubicacion_origen_id', v_origen,
        'cantidad', v_cantidad, 'motivo', v_motivo)
    else pg_catalog.jsonb_build_object(
        'producto_id', v_producto, 'ubicacion_origen_id', v_origen,
        'cantidad', v_cantidad, 'motivo_codigo', v_motivo_codigo, 'motivo', v_motivo)
  end;

  -- Paso 4. Lock transaccional de nivel 0 por empresa y actor (no por tipo).
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'intenciones:' || v_empresa::pg_catalog.text || ':' || v_uid::pg_catalog.text, 0));

  -- Paso 5. Replay: una sola sentencia con autorización (perfiles LEFT JOIN intención).
  select (p.activo is true and p.rol in ('dueno', 'encargado')),
         i.id is not null,
         i.tipo,
         i.payload
    into v_autorizado, v_existe, v_previa_tipo, v_previa_payload
    from public.perfiles as p
    left join public.intenciones_operacion as i
      on i.empresa_id = p.empresa_id
     and i.actor_id = p.usuario_id
     and i.id = p_intencion_id
   where p.usuario_id = v_uid;

  if not found or v_autorizado is not true then
    raise exception using errcode = 'PT403', message = 'intencion_no_autorizado';
  end if;

  if v_existe then
    if v_previa_tipo = p_tipo and v_previa_payload = v_payload then
      return p_intencion_id;
    end if;
    raise exception using errcode = 'PT409', message = 'intencion_conflicto';
  end if;

  -- Paso 5b. Compuerta y datos de topes: una sola sentencia con autorización,
  -- posterior al lock. «Sin resolver» = pendiente (vigente o vencida) o confirmada
  -- sin reconocimiento; la compuerta es por actor y tipo; los topes, por actor.
  select (p.activo is true and p.rol in ('dueno', 'encargado')),
         exists (
           select 1
             from public.intenciones_operacion as i
            where i.empresa_id = p.empresa_id
              and i.actor_id = p.usuario_id
              and i.tipo = p_tipo
              and (i.estado = 'pendiente'
                   or (i.estado = 'confirmada'
                       and not exists (
                         select 1
                           from public.intenciones_reconocimientos as r
                          where r.empresa_id = i.empresa_id
                            and r.actor_id = i.actor_id
                            and r.operacion_id = i.operacion_id)))),
         (select pg_catalog.count(*)
            from public.intenciones_operacion as i
           where i.empresa_id = p.empresa_id
             and i.actor_id = p.usuario_id
             and (i.estado = 'pendiente'
                  or (i.estado = 'confirmada'
                      and not exists (
                        select 1
                          from public.intenciones_reconocimientos as r
                         where r.empresa_id = i.empresa_id
                           and r.actor_id = i.actor_id
                           and r.operacion_id = i.operacion_id)))),
         (select pg_catalog.count(*)
            from public.intenciones_operacion as i
           where i.empresa_id = p.empresa_id
             and i.actor_id = p.usuario_id
             and i.creado_en > pg_catalog.clock_timestamp() - '1 hour'::pg_catalog.interval)
    into v_autorizado, v_bloqueado, v_sin_resolver, v_hora
    from public.perfiles as p
   where p.usuario_id = v_uid;

  if not found or v_autorizado is not true then
    raise exception using errcode = 'PT403', message = 'intencion_no_autorizado';
  end if;

  if v_bloqueado then
    raise exception using errcode = 'PT409', message = 'intencion_sin_resolver';
  end if;

  if v_sin_resolver >= 20 then
    raise exception using errcode = 'PT429', message = 'intencion_limite_excedido';
  end if;

  if v_hora >= 120 then
    raise exception using errcode = 'PT429', message = 'intencion_limite_excedido';
  end if;

  -- Paso 7. INSERT: la política exige actor y perfil activo en su propia
  -- instantánea; un 42501 se PROPAGA (no se convierte). Las violaciones residuales
  -- de restricción no revelan su nombre.
  begin
    insert into public.intenciones_operacion (empresa_id, actor_id, id, tipo, payload, vence_en)
    values (v_empresa, v_uid, p_intencion_id, p_tipo, v_payload,
            pg_catalog.clock_timestamp() + '24 hours'::pg_catalog.interval)
    on conflict (empresa_id, actor_id, id) do nothing;

    get diagnostics v_filas = row_count;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or not_null_violation then
      raise exception using errcode = 'PT500', message = 'intencion_error_interno';
  end;

  if v_filas = 0 then
    -- Defensa en profundidad: releer con la sentencia del paso 5 y aplicar su regla.
    select (p.activo is true and p.rol in ('dueno', 'encargado')),
           i.id is not null,
           i.tipo,
           i.payload
      into v_autorizado, v_existe, v_previa_tipo, v_previa_payload
      from public.perfiles as p
      left join public.intenciones_operacion as i
        on i.empresa_id = p.empresa_id
       and i.actor_id = p.usuario_id
       and i.id = p_intencion_id
     where p.usuario_id = v_uid;

    if not found or v_autorizado is not true then
      raise exception using errcode = 'PT403', message = 'intencion_no_autorizado';
    end if;

    if v_existe and v_previa_tipo = p_tipo and v_previa_payload = v_payload then
      return p_intencion_id;
    end if;
    if v_existe then
      raise exception using errcode = 'PT409', message = 'intencion_conflicto';
    end if;
    raise exception using errcode = 'PT500', message = 'intencion_error_interno';
  end if;

  -- Paso 8.
  return p_intencion_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- ejecutar_intencion_operacion — implementación privilegiada
-- ---------------------------------------------------------------------------
create function privado.ejecutar_intencion_operacion(
  p_intencion_id pg_catalog.uuid
)
returns table (
  estado pg_catalog.text,
  operacion_id pg_catalog.uuid,
  codigo_rechazo pg_catalog.text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid pg_catalog.uuid;
  v_empresa pg_catalog.uuid;
  v_autorizado boolean;
  v_i_id pg_catalog.uuid;
  v_i_estado pg_catalog.text;
  v_i_tipo pg_catalog.text;
  v_i_payload pg_catalog.jsonb;
  v_i_operacion pg_catalog.uuid;
  v_i_codigo pg_catalog.text;
  v_i_vence pg_catalog.timestamptz;
  v_op pg_catalog.uuid;
  v_rechazo pg_catalog.text;
  v_cod pg_catalog.text;
  v_filas integer;
begin
  -- Paso 0 (anexo §4.5): fuera de READ COMMITTED falla cerrado.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = 'PT500', message = 'intencion_error_interno';
  end if;

  -- O1. Identidad.
  v_uid := privado.usuario_actual();
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'intencion_no_autenticado';
  end if;

  -- O2. Lectura inicial plana: una sola sentencia con autorización.
  select p.empresa_id,
         (p.activo is true and p.rol in ('dueno', 'encargado')),
         i.id, i.estado, i.tipo, i.payload, i.operacion_id, i.codigo_rechazo, i.vence_en
    into v_empresa, v_autorizado,
         v_i_id, v_i_estado, v_i_tipo, v_i_payload, v_i_operacion, v_i_codigo, v_i_vence
    from public.perfiles as p
    left join public.intenciones_operacion as i
      on i.empresa_id = p.empresa_id
     and i.actor_id = p.usuario_id
     and i.id = p_intencion_id
   where p.usuario_id = v_uid;

  if not found or v_autorizado is not true then
    raise exception using errcode = 'PT403', message = 'intencion_no_autorizado';
  end if;

  if v_i_id is null then
    raise exception using errcode = 'PT404', message = 'intencion_no_encontrada';
  end if;

  if v_i_estado = 'pendiente' then
    -- O3. Bloqueo de la fila (nivel 1), sólo porque la lectura plana vio `pendiente`.
    select i.estado, i.tipo, i.payload, i.vence_en
      into v_i_estado, v_i_tipo, v_i_payload, v_i_vence
      from public.intenciones_operacion as i
     where i.empresa_id = v_empresa
       and i.actor_id = v_uid
       and i.id = p_intencion_id
       for update;

    if found then
      if v_i_estado is distinct from 'pendiente' then
        raise exception using errcode = 'PT500', message = 'intencion_error_interno';
      end if;
    else
      -- O3b. 0 filas no significa inexistencia: relectura con la MISMA sentencia que O2.
      select p.empresa_id,
             (p.activo is true and p.rol in ('dueno', 'encargado')),
             i.id, i.estado, i.tipo, i.payload, i.operacion_id, i.codigo_rechazo, i.vence_en
        into v_empresa, v_autorizado,
             v_i_id, v_i_estado, v_i_tipo, v_i_payload, v_i_operacion, v_i_codigo, v_i_vence
        from public.perfiles as p
        left join public.intenciones_operacion as i
          on i.empresa_id = p.empresa_id
         and i.actor_id = p.usuario_id
         and i.id = p_intencion_id
       where p.usuario_id = v_uid;

      if not found or v_autorizado is not true then
        raise exception using errcode = 'PT403', message = 'intencion_no_autorizado';
      end if;

      if v_i_id is null
         or v_i_estado not in ('confirmada', 'rechazada', 'cancelada') then
        raise exception using errcode = 'PT500', message = 'intencion_error_interno';
      end if;
    end if;
  end if;

  -- O4. Según el estado almacenado.
  if v_i_estado in ('confirmada', 'rechazada') then
    -- Idempotente: devuelve lo almacenado, sin RPC de negocio y sin mirar el plazo.
    return query select v_i_estado, v_i_operacion, v_i_codigo;
    return;
  end if;

  if v_i_estado = 'cancelada' then
    raise exception using errcode = 'PT409', message = 'intencion_cancelada';
  end if;

  -- `pendiente` bajo bloqueo. Admisión por plazo (única comprobación de vencimiento).
  if pg_catalog.clock_timestamp() >= v_i_vence then
    raise exception using errcode = 'PT409', message = 'intencion_vencida';
  end if;

  -- Bloque protegido de alcance mínimo: sólo la llamada a la RPC de negocio.
  begin
    case v_i_tipo
      when 'ingreso' then
        v_op := privado.registrar_ingreso(
          p_intencion_id,
          (v_i_payload ->> 'producto_id')::pg_catalog.uuid,
          (v_i_payload ->> 'cantidad')::integer,
          v_i_payload ->> 'motivo');
      when 'a_cuarentena' then
        v_op := privado.mover_a_cuarentena(
          p_intencion_id,
          (v_i_payload ->> 'producto_id')::pg_catalog.uuid,
          (v_i_payload ->> 'ubicacion_origen_id')::pg_catalog.uuid,
          (v_i_payload ->> 'cantidad')::integer,
          v_i_payload ->> 'motivo');
      when 'merma' then
        v_op := privado.registrar_merma(
          p_intencion_id,
          (v_i_payload ->> 'producto_id')::pg_catalog.uuid,
          (v_i_payload ->> 'ubicacion_origen_id')::pg_catalog.uuid,
          (v_i_payload ->> 'cantidad')::integer,
          v_i_payload ->> 'motivo_codigo',
          v_i_payload ->> 'motivo');
      else
        raise exception using errcode = 'PT500', message = 'intencion_error_interno';
    end case;
  exception
    when sqlstate 'PT400' or sqlstate 'PT404' or sqlstate 'PT409' then
      get stacked diagnostics v_cod = message_text;
      if v_cod not in ('stock_cantidad_invalida', 'stock_motivo_invalido',
                       'stock_origen_invalido', 'stock_producto_no_encontrado',
                       'stock_ubicacion_no_encontrada', 'stock_producto_inactivo',
                       'stock_insuficiente', 'stock_conflicto_idempotencia') then
        raise;
      end if;
      v_rechazo := v_cod;
  end;

  -- Fuera del bloque protegido, en la misma transacción: transición atómica con el efecto.
  begin
    if v_rechazo is null then
      update public.intenciones_operacion as i
         set estado = 'confirmada',
             operacion_id = v_op,
             resuelto_en = pg_catalog.clock_timestamp()
       where i.empresa_id = v_empresa
         and i.actor_id = v_uid
         and i.id = p_intencion_id
         and i.estado = 'pendiente';
    else
      update public.intenciones_operacion as i
         set estado = 'rechazada',
             codigo_rechazo = v_rechazo,
             resuelto_en = pg_catalog.clock_timestamp()
       where i.empresa_id = v_empresa
         and i.actor_id = v_uid
         and i.id = p_intencion_id
         and i.estado = 'pendiente';
    end if;

    get diagnostics v_filas = row_count;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or not_null_violation then
      raise exception using errcode = 'PT500', message = 'intencion_error_interno';
  end;

  if v_filas <> 1 then
    raise exception using errcode = 'PT500', message = 'intencion_error_interno';
  end if;

  if v_rechazo is null then
    return query select 'confirmada'::pg_catalog.text, v_op, null::pg_catalog.text;
  else
    return query select 'rechazada'::pg_catalog.text, null::pg_catalog.uuid, v_rechazo;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- cancelar_intencion_operacion — implementación privilegiada
-- ---------------------------------------------------------------------------
create function privado.cancelar_intencion_operacion(
  p_intencion_id pg_catalog.uuid
)
returns pg_catalog.text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid pg_catalog.uuid;
  v_empresa pg_catalog.uuid;
  v_autorizado boolean;
  v_i_id pg_catalog.uuid;
  v_i_estado pg_catalog.text;
  v_i_tipo pg_catalog.text;
  v_i_payload pg_catalog.jsonb;
  v_i_operacion pg_catalog.uuid;
  v_i_codigo pg_catalog.text;
  v_i_vence pg_catalog.timestamptz;
  v_filas integer;
begin
  -- Paso 0 (anexo §4.5): fuera de READ COMMITTED falla cerrado.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = 'PT500', message = 'intencion_error_interno';
  end if;

  -- O1. Identidad.
  v_uid := privado.usuario_actual();
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'intencion_no_autenticado';
  end if;

  -- O2. Lectura inicial plana: una sola sentencia con autorización (idéntica a ejecutar).
  select p.empresa_id,
         (p.activo is true and p.rol in ('dueno', 'encargado')),
         i.id, i.estado, i.tipo, i.payload, i.operacion_id, i.codigo_rechazo, i.vence_en
    into v_empresa, v_autorizado,
         v_i_id, v_i_estado, v_i_tipo, v_i_payload, v_i_operacion, v_i_codigo, v_i_vence
    from public.perfiles as p
    left join public.intenciones_operacion as i
      on i.empresa_id = p.empresa_id
     and i.actor_id = p.usuario_id
     and i.id = p_intencion_id
   where p.usuario_id = v_uid;

  if not found or v_autorizado is not true then
    raise exception using errcode = 'PT403', message = 'intencion_no_autorizado';
  end if;

  if v_i_id is null then
    raise exception using errcode = 'PT404', message = 'intencion_no_encontrada';
  end if;

  if v_i_estado = 'pendiente' then
    -- O3. Bloqueo de la fila (nivel 1), sólo porque la lectura plana vio `pendiente`.
    select i.estado, i.tipo, i.payload, i.vence_en
      into v_i_estado, v_i_tipo, v_i_payload, v_i_vence
      from public.intenciones_operacion as i
     where i.empresa_id = v_empresa
       and i.actor_id = v_uid
       and i.id = p_intencion_id
       for update;

    if found then
      if v_i_estado is distinct from 'pendiente' then
        raise exception using errcode = 'PT500', message = 'intencion_error_interno';
      end if;
    else
      -- O3b. Relectura con la MISMA sentencia que O2.
      select p.empresa_id,
             (p.activo is true and p.rol in ('dueno', 'encargado')),
             i.id, i.estado, i.tipo, i.payload, i.operacion_id, i.codigo_rechazo, i.vence_en
        into v_empresa, v_autorizado,
             v_i_id, v_i_estado, v_i_tipo, v_i_payload, v_i_operacion, v_i_codigo, v_i_vence
        from public.perfiles as p
        left join public.intenciones_operacion as i
          on i.empresa_id = p.empresa_id
         and i.actor_id = p.usuario_id
         and i.id = p_intencion_id
       where p.usuario_id = v_uid;

      if not found or v_autorizado is not true then
        raise exception using errcode = 'PT403', message = 'intencion_no_autorizado';
      end if;

      if v_i_id is null
         or v_i_estado not in ('confirmada', 'rechazada', 'cancelada') then
        raise exception using errcode = 'PT500', message = 'intencion_error_interno';
      end if;
    end if;
  end if;

  -- O4. Según el estado almacenado.
  if v_i_estado in ('rechazada', 'cancelada') then
    return v_i_estado;
  end if;

  if v_i_estado = 'confirmada' then
    raise exception using errcode = 'PT409', message = 'intencion_ya_confirmada';
  end if;

  -- `pendiente` bajo bloqueo: se cancela también si está vencida. Sin efectos sobre stock.
  begin
    update public.intenciones_operacion as i
       set estado = 'cancelada',
           resuelto_en = pg_catalog.clock_timestamp()
     where i.empresa_id = v_empresa
       and i.actor_id = v_uid
       and i.id = p_intencion_id
       and i.estado = 'pendiente';

    get diagnostics v_filas = row_count;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or not_null_violation then
      raise exception using errcode = 'PT500', message = 'intencion_error_interno';
  end;

  if v_filas <> 1 then
    raise exception using errcode = 'PT500', message = 'intencion_error_interno';
  end if;

  return 'cancelada'::pg_catalog.text;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fachadas expuestas (SECURITY INVOKER): sólo delegan
-- ---------------------------------------------------------------------------
create function public.crear_intencion_operacion(
  p_intencion_id pg_catalog.uuid,
  p_tipo pg_catalog.text,
  p_payload pg_catalog.jsonb
)
returns pg_catalog.uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.crear_intencion_operacion(p_intencion_id, p_tipo, p_payload)
$$;

create function public.ejecutar_intencion_operacion(
  p_intencion_id pg_catalog.uuid
)
returns table (
  estado pg_catalog.text,
  operacion_id pg_catalog.uuid,
  codigo_rechazo pg_catalog.text
)
language sql
volatile
security invoker
set search_path = ''
as $$
  select e.estado, e.operacion_id, e.codigo_rechazo
    from privado.ejecutar_intencion_operacion(p_intencion_id) as e
$$;

create function public.cancelar_intencion_operacion(
  p_intencion_id pg_catalog.uuid
)
returns pg_catalog.text
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.cancelar_intencion_operacion(p_intencion_id)
$$;

-- ---------------------------------------------------------------------------
-- EXECUTE (firma exacta) y propiedad (O-3)
-- ---------------------------------------------------------------------------
revoke all on function privado.crear_intencion_operacion(pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb)
  from public, anon, authenticated, service_role;
grant execute on function privado.crear_intencion_operacion(pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb)
  to authenticated;
revoke all on function public.crear_intencion_operacion(pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.crear_intencion_operacion(pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb)
  to authenticated;

revoke all on function privado.ejecutar_intencion_operacion(pg_catalog.uuid)
  from public, anon, authenticated, service_role;
grant execute on function privado.ejecutar_intencion_operacion(pg_catalog.uuid)
  to authenticated;
revoke all on function public.ejecutar_intencion_operacion(pg_catalog.uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ejecutar_intencion_operacion(pg_catalog.uuid)
  to authenticated;

revoke all on function privado.cancelar_intencion_operacion(pg_catalog.uuid)
  from public, anon, authenticated, service_role;
grant execute on function privado.cancelar_intencion_operacion(pg_catalog.uuid)
  to authenticated;
revoke all on function public.cancelar_intencion_operacion(pg_catalog.uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.cancelar_intencion_operacion(pg_catalog.uuid)
  to authenticated;

-- CREATE sobre privado sólo mientras se transfiere la propiedad.
grant create on schema privado to propietario_rpc;
alter function privado.crear_intencion_operacion(pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb)
  owner to propietario_rpc;
alter function privado.ejecutar_intencion_operacion(pg_catalog.uuid)
  owner to propietario_rpc;
alter function privado.cancelar_intencion_operacion(pg_catalog.uuid)
  owner to propietario_rpc;
revoke create on schema privado from propietario_rpc;

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
declare
  v_firma pg_catalog.text;
  v_nombre pg_catalog.text;
begin
  -- Seis funciones de intenciones, exactamente: sin sobrecargas ni extras.
  if (select pg_catalog.count(*) from pg_catalog.pg_proc
       where proname operator(pg_catalog.~~) '%intencion%') operator(pg_catalog.<>) 6 then
    raise exception 'intenciones: el conjunto de funciones de intenciones no es el aprobado (6)';
  end if;

  for v_nombre, v_firma in
    select * from (values
      ('crear_intencion_operacion', '(pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb)'),
      ('ejecutar_intencion_operacion', '(pg_catalog.uuid)'),
      ('cancelar_intencion_operacion', '(pg_catalog.uuid)')
    ) as f(nombre, firma)
  loop
    if (select pg_catalog.count(*) from pg_catalog.pg_proc
         where proname operator(pg_catalog.=) v_nombre) operator(pg_catalog.<>) 2
       or not exists (
         select 1 from pg_catalog.pg_proc p
          where p.oid operator(pg_catalog.=) pg_catalog.to_regprocedure('privado.' operator(pg_catalog.||) v_nombre operator(pg_catalog.||) v_firma)
            and p.prosecdef and p.provolatile operator(pg_catalog.=) 'v'
            and p.prolang operator(pg_catalog.=) (select l.oid from pg_catalog.pg_language l where l.lanname operator(pg_catalog.=) 'plpgsql')
            and p.proowner operator(pg_catalog.=) 'propietario_rpc'::pg_catalog.regrole
            and p.proconfig operator(pg_catalog.=) array['search_path=""']::pg_catalog.text[]
            and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
                operator(pg_catalog.=) array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']::pg_catalog.text[])
       or not exists (
         select 1 from pg_catalog.pg_proc p
          where p.oid operator(pg_catalog.=) pg_catalog.to_regprocedure('public.' operator(pg_catalog.||) v_nombre operator(pg_catalog.||) v_firma)
            and not p.prosecdef and p.provolatile operator(pg_catalog.=) 'v'
            and p.prolang operator(pg_catalog.=) (select l.oid from pg_catalog.pg_language l where l.lanname operator(pg_catalog.=) 'sql')
            and p.proowner operator(pg_catalog.=) 'postgres'::pg_catalog.regrole
            and p.proconfig operator(pg_catalog.=) array['search_path=""']::pg_catalog.text[]
            and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
                operator(pg_catalog.=) array['authenticated=X/postgres', 'postgres=X/postgres']::pg_catalog.text[]) then
      raise exception 'intenciones: % fuera de lo aprobado (seguridad, owner, search_path, ACL o sobrecargas)', v_nombre;
    end if;

    if pg_catalog.has_function_privilege('anon', 'public.' operator(pg_catalog.||) v_nombre operator(pg_catalog.||) v_firma, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', 'public.' operator(pg_catalog.||) v_nombre operator(pg_catalog.||) v_firma, 'EXECUTE')
       or pg_catalog.has_function_privilege('anon', 'privado.' operator(pg_catalog.||) v_nombre operator(pg_catalog.||) v_firma, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', 'privado.' operator(pg_catalog.||) v_nombre operator(pg_catalog.||) v_firma, 'EXECUTE')
       or not pg_catalog.has_function_privilege('authenticated', 'public.' operator(pg_catalog.||) v_nombre operator(pg_catalog.||) v_firma, 'EXECUTE') then
      raise exception 'intenciones: % concede o niega EXECUTE fuera de lo aprobado', v_nombre;
    end if;
  end loop;

  -- Retornos aprobados.
  if (select pg_catalog.pg_get_function_result('public.ejecutar_intencion_operacion(pg_catalog.uuid)'::pg_catalog.regprocedure))
       is distinct from 'TABLE(estado text, operacion_id uuid, codigo_rechazo text)'
     or (select pg_catalog.pg_get_function_result('privado.ejecutar_intencion_operacion(pg_catalog.uuid)'::pg_catalog.regprocedure))
       is distinct from 'TABLE(estado text, operacion_id uuid, codigo_rechazo text)'
     or (select pg_catalog.pg_get_function_result('public.crear_intencion_operacion(pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb)'::pg_catalog.regprocedure))
       is distinct from 'uuid'
     or (select pg_catalog.pg_get_function_result('public.cancelar_intencion_operacion(pg_catalog.uuid)'::pg_catalog.regprocedure))
       is distinct from 'text' then
    raise exception 'intenciones: retornos fuera de lo aprobado';
  end if;

  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'intenciones: propietario_rpc conserva CREATE sobre privado';
  end if;
end $$;
