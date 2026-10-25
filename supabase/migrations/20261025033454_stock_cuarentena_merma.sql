-- Etapa 2 — Stock, slice 2 «stock-cuarentena-merma» (Blueprint §3, §6, §7.1,
-- §7.2, §7.4, §7.7, §7.9, §8, §9, §10, §12; ADR-001 Topología D y §18.3,
-- decisiones acotadas al dominio Stock).
--
-- Decisiones humanas aprobadas (ADR-001 §18.3; docs/progress-log.md):
--   - D1 (E17): mover_a_cuarentena y registrar_merma, sólo dueño y encargado,
--     sin diferencias entre ellos. El vendedor/piloto no.
--   - D2: el motivo de la cuarentena es texto obligatorio (btrim; vacío →
--     PT400 stock_motivo_invalido). Sin catálogo.
--   - D3: el único origen permitido es el depósito; cuarentena y camión →
--     PT400 stock_origen_invalido (el camión llega en la Etapa 3).
--   - D4: sin merma desde cuarentena (va con la revisión de cuarentena).
--   - D5/D6: motivo_codigo de merma con la lista literal de Blueprint §7.7
--     (vencido, roto_danado, mal_estado, error_pedido, cambio, otro); texto
--     obligatorio sólo para 'otro'.
--   - D7: índice único parcial (empresa_id, operacion_id) para los tipos
--     unitarios (ingreso, a_cuarentena, merma).
--   - D8: la policy de INSERT del ledger exige destino depósito para ingreso.
--   - D9: las dos RPC en una sola migración.
--   - Concurrencia (P13-stock): READ COMMITTED + pg_advisory_xact_lock por
--     empresa + ubicación de origen + producto, tomado después de la
--     idempotencia y de validar producto/origen, y antes de leer el saldo.
--     Las RPC exigen READ COMMITTED: con otro aislamiento el saldo se leería
--     con la instantánea previa al lock, así que fallan cerradas (PT500
--     stock_error_interno) antes de cualquier trabajo. No cambian el
--     aislamiento del caller.
--   - Huellas v1:
--       'v1|a_cuarentena|<producto>|<origen>|<cantidad>|<m>'
--       'v1|merma|<producto>|<origen>|<cantidad>|<codigo>|<m>'
--     con <m> = '-' si el motivo es NULL y '+' || motivo normalizado si no.
--
-- Fuera de alcance: cuarentena_apta, merma desde cuarentena, origen camión,
-- carga, jornadas, ventas, devoluciones, conteos, regularizaciones, ajuste,
-- negativo transitorio. `service_role` sin privilegios (P11).
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

do $$
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;

  -- Los datos existentes (sólo ingresos) deben cumplir el modelo nuevo antes
  -- de reemplazar las restricciones.
  if exists (select 1 from public.movimientos_stock
              where tipo_movimiento <> 'ingreso'
                 or ubicacion_origen_id is not null
                 or ubicacion_destino_id is null)
     or exists (select 1 from public.operaciones where tipo <> 'ingreso')
     or exists (select 1 from public.movimientos_stock
                 group by empresa_id, operacion_id having count(*) > 1) then
    raise exception 'stock: datos existentes incompatibles con el modelo del slice 2';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- operaciones: tipos del dominio Stock aprobados
-- ---------------------------------------------------------------------------
alter table public.operaciones drop constraint operaciones_tipo_valido;
alter table public.operaciones add constraint operaciones_tipo_valido
  check (tipo in ('ingreso', 'a_cuarentena', 'merma'));

-- ---------------------------------------------------------------------------
-- movimientos_stock: tipos, forma por tipo y motivos
-- ---------------------------------------------------------------------------
alter table public.movimientos_stock add column motivo_codigo text;

comment on column public.movimientos_stock.motivo_codigo is
  'Motivo predefinido de merma (Blueprint §7.7): vencido, roto_danado, mal_estado, error_pedido, cambio, otro. NULL para los demás tipos.';

alter table public.movimientos_stock drop constraint movimientos_stock_tipo_valido;
alter table public.movimientos_stock add constraint movimientos_stock_tipo_valido
  check (tipo_movimiento in ('ingreso', 'a_cuarentena', 'merma'));

alter table public.movimientos_stock drop constraint movimientos_stock_forma_por_tipo;
alter table public.movimientos_stock add constraint movimientos_stock_forma_por_tipo
  check (
    (tipo_movimiento = 'ingreso'
      and ubicacion_origen_id is null and ubicacion_destino_id is not null)
    or (tipo_movimiento = 'a_cuarentena'
      and ubicacion_origen_id is not null and ubicacion_destino_id is not null)
    or (tipo_movimiento = 'merma'
      and ubicacion_origen_id is not null and ubicacion_destino_id is null));

alter table public.movimientos_stock add constraint movimientos_stock_motivo_codigo_valido
  check (motivo_codigo is null
         or motivo_codigo in ('vencido', 'roto_danado', 'mal_estado',
                              'error_pedido', 'cambio', 'otro'));

alter table public.movimientos_stock add constraint movimientos_stock_motivo_por_tipo
  check (
    (tipo_movimiento = 'ingreso' and motivo_codigo is null)
    or (tipo_movimiento = 'a_cuarentena' and motivo_codigo is null and motivo is not null)
    or (tipo_movimiento = 'merma' and motivo_codigo is not null
        and (motivo_codigo <> 'otro' or motivo is not null)));

-- D7: una operación unitaria tiene exactamente un movimiento. Las operaciones
-- futuras con varios movimientos (carga, venta, retorno) quedan fuera.
create unique index movimientos_stock_operacion_unitaria_unica
  on public.movimientos_stock (empresa_id, operacion_id)
  where tipo_movimiento in ('ingreso', 'a_cuarentena', 'merma');

grant insert (motivo_codigo) on table public.movimientos_stock to propietario_rpc;

-- ---------------------------------------------------------------------------
-- Policies de INSERT de propietario_rpc (sin formas arbitrarias)
-- ---------------------------------------------------------------------------
alter policy operaciones_insert_propietario_rpc
  on public.operaciones
  with check (
    actor_id = (select privado.usuario_actual())
    and tipo in ('ingreso', 'a_cuarentena', 'merma')
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = operaciones.empresa_id
        and p.usuario_id = operaciones.actor_id
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

-- Mismo actor y empresa que la operación, del mismo tipo, y cada tipo con su
-- forma: ingreso → depósito (D8); a_cuarentena depósito → cuarentena; merma
-- depósito → NULL.
alter policy movimientos_stock_insert_propietario_rpc
  on public.movimientos_stock
  with check (
    actor_id = (select privado.usuario_actual())
    and tipo_movimiento in ('ingreso', 'a_cuarentena', 'merma')
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = movimientos_stock.empresa_id
        and p.usuario_id = movimientos_stock.actor_id
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
    and exists (
      select 1
      from public.operaciones o
      where o.id = movimientos_stock.operacion_id
        and o.empresa_id = movimientos_stock.empresa_id
        and o.actor_id = movimientos_stock.actor_id
        and o.tipo = movimientos_stock.tipo_movimiento
    )
    and (
      (tipo_movimiento = 'ingreso'
        and ubicacion_origen_id is null
        and exists (select 1 from public.ubicaciones d
                     where d.id = movimientos_stock.ubicacion_destino_id
                       and d.empresa_id = movimientos_stock.empresa_id
                       and d.tipo = 'deposito'))
      or (tipo_movimiento = 'a_cuarentena'
        and exists (select 1 from public.ubicaciones o
                     where o.id = movimientos_stock.ubicacion_origen_id
                       and o.empresa_id = movimientos_stock.empresa_id
                       and o.tipo = 'deposito')
        and exists (select 1 from public.ubicaciones d
                     where d.id = movimientos_stock.ubicacion_destino_id
                       and d.empresa_id = movimientos_stock.empresa_id
                       and d.tipo = 'cuarentena'))
      or (tipo_movimiento = 'merma'
        and ubicacion_destino_id is null
        and exists (select 1 from public.ubicaciones o
                     where o.id = movimientos_stock.ubicacion_origen_id
                       and o.empresa_id = movimientos_stock.empresa_id
                       and o.tipo = 'deposito'))
    )
  );

-- ---------------------------------------------------------------------------
-- privado.mover_a_cuarentena (SECURITY DEFINER, Topología D)
-- ---------------------------------------------------------------------------
create function privado.mover_a_cuarentena(
  p_idempotency_key uuid,
  p_producto_id uuid,
  p_ubicacion_origen_id uuid,
  p_cantidad integer,
  p_motivo text
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
  v_motivo text := nullif(btrim(p_motivo), '');
  v_huella text;
  v_operacion uuid;
  v_previa_tipo text;
  v_previa_huella text;
  v_producto_activo boolean;
  v_origen_tipo text;
  v_cuarentenas uuid[];
  v_saldo bigint;
begin
  -- P13-stock: el lock sólo serializa el saldo bajo READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end if;

  -- Identidad, perfil activo, empresa y rol desde perfiles (D1).
  v_uid := privado.usuario_actual();
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'stock_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if v_empresa is null or v_activo is not true
     or v_rol not in ('dueno', 'encargado') then
    raise exception using errcode = 'PT403', message = 'stock_no_autorizado';
  end if;

  -- Estructura básica del pedido.
  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'stock_clave_invalida';
  end if;

  if p_cantidad is null or p_cantidad <= 0 then
    raise exception using errcode = 'PT400', message = 'stock_cantidad_invalida';
  end if;

  if v_motivo is null then
    raise exception using errcode = 'PT400', message = 'stock_motivo_invalido';
  end if;

  if p_producto_id is null then
    raise exception using errcode = 'PT404', message = 'stock_producto_no_encontrado';
  end if;

  if p_ubicacion_origen_id is null then
    raise exception using errcode = 'PT404', message = 'stock_ubicacion_no_encontrada';
  end if;

  -- Huella v1 (el destino se deriva en el servidor y no integra la huella).
  v_huella := encode(
    sha256(convert_to(
      'v1|a_cuarentena|' || p_producto_id::text || '|' || p_ubicacion_origen_id::text
        || '|' || p_cantidad::text || '|'
        || case when v_motivo is null then '-' else '+' || v_motivo end,
      'UTF8')),
    'hex');

  -- Reserva de la clave o replay (antes de cualquier validación mutable).
  begin
    insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values (v_empresa, v_uid, 'a_cuarentena', p_idempotency_key, v_huella)
    on conflict (empresa_id, actor_id, idempotency_key) do nothing
    returning id into v_operacion;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end;

  if v_operacion is null then
    select o.id, o.tipo, o.huella
      into v_operacion, v_previa_tipo, v_previa_huella
      from public.operaciones o
     where o.empresa_id = v_empresa
       and o.actor_id = v_uid
       and o.idempotency_key = p_idempotency_key;

    if v_previa_tipo = 'a_cuarentena' and v_previa_huella = v_huella then
      return v_operacion;
    end if;

    raise exception using errcode = 'PT409', message = 'stock_conflicto_idempotencia';
  end if;

  -- Producto de la empresa (otra empresa = inexistente) y activo.
  select pr.activo into v_producto_activo
    from public.productos pr
   where pr.id = p_producto_id
     and pr.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'stock_producto_no_encontrado';
  end if;

  if v_producto_activo is not true then
    raise exception using errcode = 'PT409', message = 'stock_producto_inactivo';
  end if;

  -- Origen: ubicación propia y de tipo depósito (D3).
  select u.tipo into v_origen_tipo
    from public.ubicaciones u
   where u.id = p_ubicacion_origen_id
     and u.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'stock_ubicacion_no_encontrada';
  end if;

  if v_origen_tipo <> 'deposito' then
    raise exception using errcode = 'PT400', message = 'stock_origen_invalido';
  end if;

  -- Destino: la única cuarentena de la empresa, resuelta en el servidor.
  select array_agg(u.id) into v_cuarentenas
    from public.ubicaciones u
   where u.empresa_id = v_empresa
     and u.tipo = 'cuarentena';

  if coalesce(cardinality(v_cuarentenas), 0) <> 1 then
    raise exception using errcode = 'PT500', message = 'stock_ubicacion_no_configurada';
  end if;

  -- Débito serializado por empresa + origen + producto.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'stock:' || v_empresa::text || ':' || p_ubicacion_origen_id::text || ':' || p_producto_id::text, 0));

  select coalesce(sum(case when m.ubicacion_destino_id = p_ubicacion_origen_id
                           then m.cantidad::bigint
                           else -m.cantidad::bigint end), 0)
    into v_saldo
    from public.movimientos_stock m
   where m.empresa_id = v_empresa
     and m.producto_id = p_producto_id
     and (m.ubicacion_destino_id = p_ubicacion_origen_id
          or m.ubicacion_origen_id = p_ubicacion_origen_id);

  if v_saldo < p_cantidad then
    raise exception using errcode = 'PT409', message = 'stock_insuficiente';
  end if;

  begin
    insert into public.movimientos_stock (
      empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
      ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo
    )
    values (
      v_empresa, v_operacion, 'a_cuarentena', p_producto_id, p_cantidad,
      p_ubicacion_origen_id, v_cuarentenas[1], v_uid, v_motivo
    );
  exception
    when unique_violation or check_violation or foreign_key_violation
         or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end;

  return v_operacion;
end $$;

-- ---------------------------------------------------------------------------
-- privado.registrar_merma (SECURITY DEFINER, Topología D)
-- ---------------------------------------------------------------------------
create function privado.registrar_merma(
  p_idempotency_key uuid,
  p_producto_id uuid,
  p_ubicacion_origen_id uuid,
  p_cantidad integer,
  p_motivo_codigo text,
  p_motivo text default null
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
  v_codigo text := btrim(p_motivo_codigo);
  v_motivo text := nullif(btrim(p_motivo), '');
  v_huella text;
  v_operacion uuid;
  v_previa_tipo text;
  v_previa_huella text;
  v_producto_activo boolean;
  v_origen_tipo text;
  v_saldo bigint;
begin
  -- P13-stock: el lock sólo serializa el saldo bajo READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end if;

  v_uid := privado.usuario_actual();
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'stock_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if v_empresa is null or v_activo is not true
     or v_rol not in ('dueno', 'encargado') then
    raise exception using errcode = 'PT403', message = 'stock_no_autorizado';
  end if;

  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'stock_clave_invalida';
  end if;

  if p_cantidad is null or p_cantidad <= 0 then
    raise exception using errcode = 'PT400', message = 'stock_cantidad_invalida';
  end if;

  -- Código exacto del catálogo de Blueprint §7.7 (D5); texto obligatorio sólo
  -- para 'otro'.
  if v_codigo is null
     or v_codigo not in ('vencido', 'roto_danado', 'mal_estado',
                         'error_pedido', 'cambio', 'otro')
     or (v_codigo = 'otro' and v_motivo is null) then
    raise exception using errcode = 'PT400', message = 'stock_motivo_invalido';
  end if;

  if p_producto_id is null then
    raise exception using errcode = 'PT404', message = 'stock_producto_no_encontrado';
  end if;

  if p_ubicacion_origen_id is null then
    raise exception using errcode = 'PT404', message = 'stock_ubicacion_no_encontrada';
  end if;

  v_huella := encode(
    sha256(convert_to(
      'v1|merma|' || p_producto_id::text || '|' || p_ubicacion_origen_id::text
        || '|' || p_cantidad::text || '|' || v_codigo || '|'
        || case when v_motivo is null then '-' else '+' || v_motivo end,
      'UTF8')),
    'hex');

  begin
    insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values (v_empresa, v_uid, 'merma', p_idempotency_key, v_huella)
    on conflict (empresa_id, actor_id, idempotency_key) do nothing
    returning id into v_operacion;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end;

  if v_operacion is null then
    select o.id, o.tipo, o.huella
      into v_operacion, v_previa_tipo, v_previa_huella
      from public.operaciones o
     where o.empresa_id = v_empresa
       and o.actor_id = v_uid
       and o.idempotency_key = p_idempotency_key;

    if v_previa_tipo = 'merma' and v_previa_huella = v_huella then
      return v_operacion;
    end if;

    raise exception using errcode = 'PT409', message = 'stock_conflicto_idempotencia';
  end if;

  select pr.activo into v_producto_activo
    from public.productos pr
   where pr.id = p_producto_id
     and pr.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'stock_producto_no_encontrado';
  end if;

  if v_producto_activo is not true then
    raise exception using errcode = 'PT409', message = 'stock_producto_inactivo';
  end if;

  -- Origen: ubicación propia y de tipo depósito (D3, D4).
  select u.tipo into v_origen_tipo
    from public.ubicaciones u
   where u.id = p_ubicacion_origen_id
     and u.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'stock_ubicacion_no_encontrada';
  end if;

  if v_origen_tipo <> 'deposito' then
    raise exception using errcode = 'PT400', message = 'stock_origen_invalido';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'stock:' || v_empresa::text || ':' || p_ubicacion_origen_id::text || ':' || p_producto_id::text, 0));

  select coalesce(sum(case when m.ubicacion_destino_id = p_ubicacion_origen_id
                           then m.cantidad::bigint
                           else -m.cantidad::bigint end), 0)
    into v_saldo
    from public.movimientos_stock m
   where m.empresa_id = v_empresa
     and m.producto_id = p_producto_id
     and (m.ubicacion_destino_id = p_ubicacion_origen_id
          or m.ubicacion_origen_id = p_ubicacion_origen_id);

  if v_saldo < p_cantidad then
    raise exception using errcode = 'PT409', message = 'stock_insuficiente';
  end if;

  begin
    insert into public.movimientos_stock (
      empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
      ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo, motivo_codigo
    )
    values (
      v_empresa, v_operacion, 'merma', p_producto_id, p_cantidad,
      p_ubicacion_origen_id, null, v_uid, v_motivo, v_codigo
    );
  exception
    when unique_violation or check_violation or foreign_key_violation
         or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end;

  return v_operacion;
end $$;

-- ---------------------------------------------------------------------------
-- Fachadas expuestas (SECURITY INVOKER): sólo delegan
-- ---------------------------------------------------------------------------
create function public.mover_a_cuarentena(
  p_idempotency_key uuid,
  p_producto_id uuid,
  p_ubicacion_origen_id uuid,
  p_cantidad integer,
  p_motivo text
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.mover_a_cuarentena(
    p_idempotency_key, p_producto_id, p_ubicacion_origen_id, p_cantidad, p_motivo)
$$;

create function public.registrar_merma(
  p_idempotency_key uuid,
  p_producto_id uuid,
  p_ubicacion_origen_id uuid,
  p_cantidad integer,
  p_motivo_codigo text,
  p_motivo text default null
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.registrar_merma(
    p_idempotency_key, p_producto_id, p_ubicacion_origen_id, p_cantidad,
    p_motivo_codigo, p_motivo)
$$;

-- ---------------------------------------------------------------------------
-- EXECUTE (firmas exactas) y propiedad
-- ---------------------------------------------------------------------------
-- Privilegios antes de transferir la propiedad (O-3: postgres no actúa como
-- owner de las funciones de propietario_rpc; ALTER ... OWNER TO reescribe el
-- grantor del ACL al nuevo owner).
revoke all on function privado.mover_a_cuarentena(uuid, uuid, uuid, integer, text)
  from public, anon, authenticated, service_role;
grant execute on function privado.mover_a_cuarentena(uuid, uuid, uuid, integer, text)
  to authenticated;
revoke all on function privado.registrar_merma(uuid, uuid, uuid, integer, text, text)
  from public, anon, authenticated, service_role;
grant execute on function privado.registrar_merma(uuid, uuid, uuid, integer, text, text)
  to authenticated;

revoke all on function public.mover_a_cuarentena(uuid, uuid, uuid, integer, text)
  from public, anon, authenticated, service_role;
grant execute on function public.mover_a_cuarentena(uuid, uuid, uuid, integer, text)
  to authenticated;
revoke all on function public.registrar_merma(uuid, uuid, uuid, integer, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.registrar_merma(uuid, uuid, uuid, integer, text, text)
  to authenticated;

-- CREATE sobre privado sólo mientras se transfiere la propiedad.
grant create on schema privado to propietario_rpc;
alter function privado.mover_a_cuarentena(uuid, uuid, uuid, integer, text)
  owner to propietario_rpc;
alter function privado.registrar_merma(uuid, uuid, uuid, integer, text, text)
  owner to propietario_rpc;
revoke create on schema privado from propietario_rpc;

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
declare
  v_fn text;
begin
  foreach v_fn in array array['mover_a_cuarentena', 'registrar_merma'] loop
    if (select count(*) from pg_proc
         where proname = v_fn
           and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)) <> 2
       or not exists (
         select 1 from pg_proc p
          where p.proname = v_fn and p.pronamespace = 'privado'::regnamespace
            and p.prosecdef and p.proowner = 'propietario_rpc'::regrole
            and p.proconfig @> array['search_path=""']
            and array(select a::text from unnest(p.proacl) a order by 1)
                = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc'])
       or not exists (
         select 1 from pg_proc p
          where p.proname = v_fn and p.pronamespace = 'public'::regnamespace
            and not p.prosecdef and p.proowner = 'postgres'::regrole
            and p.proconfig @> array['search_path=""']
            and array(select a::text from unnest(p.proacl) a order by 1)
                = array['authenticated=X/postgres', 'postgres=X/postgres']) then
      raise exception 'stock: % fuera de lo aprobado (seguridad, owner, search_path, ACL o sobrecargas)', v_fn;
    end if;
  end loop;

  if has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
     or exists (
       select 1 from pg_class c
        where c.oid in ('public.operaciones'::regclass, 'public.movimientos_stock'::regclass)
          and (has_table_privilege('authenticated', c.oid,
                 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
               or has_any_column_privilege('authenticated', c.oid, 'INSERT, UPDATE, REFERENCES')
               or has_table_privilege('service_role', c.oid,
                 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
               or has_any_column_privilege('service_role', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
               or has_table_privilege('propietario_rpc', c.oid,
                 'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
               or has_any_column_privilege('propietario_rpc', c.oid, 'UPDATE, REFERENCES')))
     or not has_column_privilege('propietario_rpc', 'public.movimientos_stock', 'motivo_codigo', 'INSERT') then
    raise exception 'stock: grants fuera de lo aprobado o CREATE residual sobre privado';
  end if;
end $$;
