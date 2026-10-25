-- Etapa 2 — Stock, slice 1 «stock-ingreso» (Blueprint §3, §6, §7.1, §7.4,
-- §7.9, §8, §9, §10, §12 Stock, §14 Etapa 2; ADR-001 Topología D y §18.3,
-- decisiones acotadas al dominio Stock).
--
-- Decisiones humanas aprobadas (registradas en ADR-001 §18.3 y en
-- docs/progress-log.md):
--   - E1/P10: este slice sólo implementa registrar_ingreso (exterior →
--     depósito). Sin cuarentena, merma, carga, ventas ni regularizaciones.
--   - E2: registran ingresos dueño y encargado; el vendedor/piloto no.
--   - E3: motivo opcional; btrim; vacío o de espacios → NULL.
--   - E4: leen operaciones, movimientos_stock y stock_actual sólo dueño y
--     encargado de la misma empresa con perfil activo.
--   - E5/E6/E7/E8 (P12): idempotencia por UNIQUE (empresa_id, actor_id,
--     idempotency_key uuid); el tipo va en la huella; retención indefinida;
--     el resultado estable del replay es operaciones.id.
--   - E9 (P13): READ COMMITTED + advisory locks por empresa+ubicación+producto
--     sólo para las RPC que debitan stock. registrar_ingreso sólo acredita:
--     NO toma locks.
--   - E11 (P16): errores stock_*. E12 (P17): operaciones + movimientos_stock
--     son la auditoría exitosa; sin tabla `auditoria`.
--   - E13: sin jornada_id (se agrega en la Etapa 3 con FK real).
--   - E14: append-only por grants y RLS; sin trigger.
--   - E15 (P14): sin sobrecargas. E16 (P15): idempotency_key sólo en
--     operaciones.
--   - Huella v1: SHA-256 (hex en minúsculas) de
--       'v1|ingreso|<producto uuid canónico>|<cantidad entera>|<motivo>'
--     con <motivo> = '-' si es NULL y '+' || motivo normalizado si no lo es.
--     Un cambio de semántica crea 'v2'; nunca se reinterpretan operaciones
--     existentes con otra fórmula.
--
-- `service_role` sin privilegios (P11: única excepción vigente, SELECT sobre
-- public.productos). Sin saldo_actual: el stock se deriva del ledger.
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

do $$
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- operaciones: una ejecución lógica idempotente de un comando (§7.9.1)
-- ---------------------------------------------------------------------------
create table public.operaciones (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  actor_id uuid not null,
  tipo text not null,
  idempotency_key uuid not null,
  huella text not null,
  creado_en timestamptz not null default now(),
  constraint operaciones_empresa_id_unico unique (empresa_id, id),
  constraint operaciones_idempotencia_unica unique (empresa_id, actor_id, idempotency_key),
  constraint operaciones_actor_fk foreign key (empresa_id, actor_id)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint operaciones_tipo_valido check (tipo in ('ingreso')),
  constraint operaciones_huella_sha256 check (huella ~ '^[0-9a-f]{64}$')
);

comment on table public.operaciones is
  'Una ejecución lógica e idempotente de un comando de negocio (Blueprint §7.9.1). Sin cantidades ni importes. Escritura sólo por las RPC.';
comment on column public.operaciones.huella is
  'SHA-256 hex de la representación canónica versionada del payload (v1 para ingreso).';

-- ---------------------------------------------------------------------------
-- movimientos_stock: ledger append-only, fuente de verdad del stock (§7.4)
-- ---------------------------------------------------------------------------
create table public.movimientos_stock (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  operacion_id uuid not null,
  tipo_movimiento text not null,
  producto_id uuid not null,
  cantidad integer not null,
  ubicacion_origen_id uuid,
  ubicacion_destino_id uuid,
  actor_id uuid not null,
  motivo text,
  creado_en timestamptz not null default now(),
  constraint movimientos_stock_empresa_id_unico unique (empresa_id, id),
  constraint movimientos_stock_operacion_fk foreign key (empresa_id, operacion_id)
    references public.operaciones (empresa_id, id) on delete restrict,
  constraint movimientos_stock_producto_fk foreign key (empresa_id, producto_id)
    references public.productos (empresa_id, id) on delete restrict,
  constraint movimientos_stock_origen_fk foreign key (empresa_id, ubicacion_origen_id)
    references public.ubicaciones (empresa_id, id) on delete restrict,
  constraint movimientos_stock_destino_fk foreign key (empresa_id, ubicacion_destino_id)
    references public.ubicaciones (empresa_id, id) on delete restrict,
  constraint movimientos_stock_actor_fk foreign key (empresa_id, actor_id)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint movimientos_stock_cantidad_positiva check (cantidad > 0),
  constraint movimientos_stock_extremo_requerido
    check (ubicacion_origen_id is not null or ubicacion_destino_id is not null),
  constraint movimientos_stock_extremos_distintos
    check (ubicacion_origen_id is distinct from ubicacion_destino_id),
  constraint movimientos_stock_tipo_valido check (tipo_movimiento in ('ingreso')),
  constraint movimientos_stock_forma_por_tipo check (
    tipo_movimiento <> 'ingreso'
    or (ubicacion_origen_id is null and ubicacion_destino_id is not null)),
  constraint movimientos_stock_motivo_normalizado
    check (motivo is null or (motivo = btrim(motivo) and length(motivo) > 0))
);

create index movimientos_stock_destino_idx
  on public.movimientos_stock (empresa_id, ubicacion_destino_id, producto_id);
create index movimientos_stock_origen_idx
  on public.movimientos_stock (empresa_id, ubicacion_origen_id, producto_id);

comment on table public.movimientos_stock is
  'Ledger append-only de stock (Blueprint §7.4): cantidad entera positiva en unidad mínima; dirección dada por origen/destino. Sin saldo_actual. Sin UPDATE ni DELETE.';

-- ---------------------------------------------------------------------------
-- Grants (explícitos; los defaults ya arrancan fail-closed)
-- ---------------------------------------------------------------------------
revoke all on table public.operaciones, public.movimientos_stock
  from public, anon, authenticated, service_role;

grant select on table public.operaciones, public.movimientos_stock to authenticated;

grant select on table public.operaciones, public.movimientos_stock to propietario_rpc;
grant insert (empresa_id, actor_id, tipo, idempotency_key, huella)
  on table public.operaciones to propietario_rpc;
grant insert (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
              ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo)
  on table public.movimientos_stock to propietario_rpc;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.operaciones enable row level security;
alter table public.movimientos_stock enable row level security;

-- Lectura: sólo dueño y encargado de la empresa, con perfil activo (E4).
create policy operaciones_select_empresa
  on public.operaciones
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = operaciones.empresa_id
        and p.usuario_id = (select auth.uid())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

create policy movimientos_stock_select_empresa
  on public.movimientos_stock
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = movimientos_stock.empresa_id
        and p.usuario_id = (select auth.uid())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

-- Defensa en profundidad para el rol técnico (no es owner ni BYPASSRLS).
create policy operaciones_select_propietario_rpc
  on public.operaciones
  for select
  to propietario_rpc
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = operaciones.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
    )
  );

create policy movimientos_stock_select_propietario_rpc
  on public.movimientos_stock
  for select
  to propietario_rpc
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = movimientos_stock.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
    )
  );

-- Alta de la operación: el actor es el usuario actual, de su empresa, con el
-- rol permitido para el tipo (ingreso: dueño o encargado).
create policy operaciones_insert_propietario_rpc
  on public.operaciones
  for insert
  to propietario_rpc
  with check (
    actor_id = (select privado.usuario_actual())
    and tipo = 'ingreso'
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = operaciones.empresa_id
        and p.usuario_id = operaciones.actor_id
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

-- Alta del movimiento: mismo actor y empresa que su operación, de tipo
-- compatible.
create policy movimientos_stock_insert_propietario_rpc
  on public.movimientos_stock
  for insert
  to propietario_rpc
  with check (
    actor_id = (select privado.usuario_actual())
    and tipo_movimiento = 'ingreso'
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
        and o.tipo = 'ingreso'
    )
  );

-- ---------------------------------------------------------------------------
-- stock_actual: saldo derivado del ledger (sin tabla de saldos ni caché)
-- ---------------------------------------------------------------------------
-- security_invoker: aplica la RLS de movimientos_stock de quien consulta, así
-- que sólo dueño y encargado de la empresa obtienen filas.
create view public.stock_actual
with (security_invoker = true)
as
select m.empresa_id, m.ubicacion_id, m.producto_id, sum(m.delta)::bigint as cantidad
  from (
    select ms.empresa_id, ms.ubicacion_destino_id as ubicacion_id, ms.producto_id,
           ms.cantidad::bigint as delta
      from public.movimientos_stock ms
     where ms.ubicacion_destino_id is not null
    union all
    select ms.empresa_id, ms.ubicacion_origen_id, ms.producto_id,
           -ms.cantidad::bigint
      from public.movimientos_stock ms
     where ms.ubicacion_origen_id is not null
  ) m
 group by m.empresa_id, m.ubicacion_id, m.producto_id;

comment on view public.stock_actual is
  'Saldo por empresa, ubicación y producto = entradas - salidas de movimientos_stock (Blueprint §7.4, §8 saldos_stock [DERIVADA]).';

revoke all on table public.stock_actual from public, anon, authenticated, service_role;
grant select on table public.stock_actual to authenticated;

-- ---------------------------------------------------------------------------
-- Implementación privada (SECURITY DEFINER, Topología D)
-- ---------------------------------------------------------------------------
-- Errores: SQLSTATE PTxyz (PostgREST responde HTTP xyz) y message stock_*
-- estable; nunca el detalle SQL, el nombre de una restricción ni datos de
-- otra empresa.
create function privado.registrar_ingreso(
  p_idempotency_key uuid,
  p_producto_id uuid,
  p_cantidad integer,
  p_motivo text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := privado.usuario_actual();
  v_empresa uuid;
  v_rol text;
  v_activo boolean;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_huella text;
  v_operacion uuid;
  v_previa_tipo text;
  v_previa_huella text;
  v_producto_activo boolean;
  v_depositos uuid[];
begin
  -- 1-4. Identidad, perfil activo, empresa y rol desde perfiles.
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

  -- 5-7. Estructura básica del pedido.
  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'stock_clave_invalida';
  end if;

  if p_cantidad is null or p_cantidad <= 0 then
    raise exception using errcode = 'PT400', message = 'stock_cantidad_invalida';
  end if;

  if p_producto_id is null then
    raise exception using errcode = 'PT404', message = 'stock_producto_no_encontrado';
  end if;

  -- 8. Huella v1 sobre los parámetros ya normalizados.
  v_huella := encode(
    sha256(convert_to(
      'v1|ingreso|' || p_producto_id::text || '|' || p_cantidad::text || '|'
        || case when v_motivo is null then '-' else '+' || v_motivo end,
      'UTF8')),
    'hex');

  -- 9-10. Reserva de la clave o replay. Un ingreso concurrente con la misma
  -- clave espera acá a que el primero confirme o revierta.
  begin
    insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values (v_empresa, v_uid, 'ingreso', p_idempotency_key, v_huella)
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

    if v_previa_tipo = 'ingreso' and v_previa_huella = v_huella then
      return v_operacion;
    end if;

    raise exception using errcode = 'PT409', message = 'stock_conflicto_idempotencia';
  end if;

  -- 11. Producto de la empresa (otra empresa = inexistente) y activo.
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

  -- 12. Depósito resuelto en el servidor: exactamente uno (fail-closed).
  select array_agg(u.id) into v_depositos
    from public.ubicaciones u
   where u.empresa_id = v_empresa
     and u.tipo = 'deposito';

  if coalesce(cardinality(v_depositos), 0) <> 1 then
    raise exception using errcode = 'PT500', message = 'stock_ubicacion_no_configurada';
  end if;

  -- 13. Un único movimiento: exterior → depósito.
  begin
    insert into public.movimientos_stock (
      empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
      ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo
    )
    values (
      v_empresa, v_operacion, 'ingreso', p_producto_id, p_cantidad,
      null, v_depositos[1], v_uid, v_motivo
    );
  exception
    when unique_violation or check_violation or foreign_key_violation
         or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end;

  -- 14. Resultado estable (también en el replay).
  return v_operacion;
end $$;

-- ---------------------------------------------------------------------------
-- Fachada expuesta (SECURITY INVOKER): sólo delega
-- ---------------------------------------------------------------------------
create function public.registrar_ingreso(
  p_idempotency_key uuid,
  p_producto_id uuid,
  p_cantidad integer,
  p_motivo text default null
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.registrar_ingreso(p_idempotency_key, p_producto_id, p_cantidad, p_motivo)
$$;

-- ---------------------------------------------------------------------------
-- EXECUTE (firmas exactas) y propiedad
-- ---------------------------------------------------------------------------
-- Los privilegios se fijan antes de transferir la propiedad: con O-3,
-- postgres no actúa como owner de las funciones de propietario_rpc, y
-- ALTER ... OWNER TO reescribe el grantor del ACL al nuevo owner.
revoke all on function privado.registrar_ingreso(uuid, uuid, integer, text)
  from public, anon, authenticated, service_role;
grant execute on function privado.registrar_ingreso(uuid, uuid, integer, text)
  to authenticated;

revoke all on function public.registrar_ingreso(uuid, uuid, integer, text)
  from public, anon, authenticated, service_role;
grant execute on function public.registrar_ingreso(uuid, uuid, integer, text)
  to authenticated;

-- CREATE sobre privado sólo mientras se transfiere la propiedad.
grant create on schema privado to propietario_rpc;
alter function privado.registrar_ingreso(uuid, uuid, integer, text)
  owner to propietario_rpc;
revoke create on schema privado from propietario_rpc;

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
declare
  v_impl regprocedure := 'privado.registrar_ingreso(uuid,uuid,integer,text)'::regprocedure;
  v_fachada regprocedure := 'public.registrar_ingreso(uuid,uuid,integer,text)'::regprocedure;
begin
  if exists (
       select 1 from pg_class c
        where c.oid in ('public.operaciones'::regclass, 'public.movimientos_stock'::regclass)
          and (c.relowner <> 'postgres'::regrole
               or not c.relrowsecurity or c.relforcerowsecurity
               or has_table_privilege('authenticated', c.oid,
                    'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
               or has_any_column_privilege('authenticated', c.oid, 'INSERT, UPDATE, REFERENCES')
               or has_table_privilege('anon', c.oid,
                    'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
               or has_table_privilege('service_role', c.oid,
                    'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
               or has_any_column_privilege('service_role', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
               or has_table_privilege('propietario_rpc', c.oid,
                    'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
               or has_any_column_privilege('propietario_rpc', c.oid, 'UPDATE, REFERENCES'))) then
    raise exception 'stock: owner, RLS o grants de operaciones/movimientos_stock fuera de lo aprobado';
  end if;

  if not exists (select 1 from pg_class
                  where oid = 'public.stock_actual'::regclass
                    and reloptions @> array['security_invoker=true'])
     or has_table_privilege('anon', 'public.stock_actual', 'SELECT')
     or has_table_privilege('service_role', 'public.stock_actual', 'SELECT')
     or has_table_privilege('authenticated', 'public.stock_actual', 'INSERT, UPDATE, DELETE') then
    raise exception 'stock: stock_actual no es security_invoker o tiene grants fuera de lo aprobado';
  end if;

  if not exists (
       select 1 from pg_proc p
        where p.oid = v_impl and p.prosecdef
          and p.proowner = 'propietario_rpc'::regrole
          and p.proconfig @> array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc'])
     or not exists (
       select 1 from pg_proc p
        where p.oid = v_fachada and not p.prosecdef
          and p.proowner = 'postgres'::regrole
          and p.proconfig @> array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/postgres', 'postgres=X/postgres'])
     or (select count(*) from pg_proc
          where proname = 'registrar_ingreso'
            and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)) <> 2
     or has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'stock: registrar_ingreso fuera de lo aprobado (seguridad, owner, search_path, ACL o sobrecargas)';
  end if;
end $$;
