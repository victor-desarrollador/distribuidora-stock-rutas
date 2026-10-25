-- Ubicaciones internas de stock (Blueprint §7.2, §7.3, §8, §9, §10, §14
-- Etapa 1; ADR-001 Topología D, P2–P4, P11 y O-3).
--
-- Decisiones humanas aprobadas (slice ubicaciones; registradas en
-- docs/progress-log.md):
--   - D1: depósito y cuarentena (una de cada una por empresa) se crean por
--     backfill en esta migración y por la seed / el bootstrap administrativo
--     de la empresa. Sin trigger.
--   - D2: privado.crear_camion crea la ubicación del camión en la MISMA
--     transacción que el camión; los camiones existentes reciben la suya por
--     backfill.
--   - D3: sólo `creado_en`; sin `creado_por` (las filas las genera el sistema;
--     el autor del camión ya está en camiones.creado_por).
--   - D4: dueño, encargado y vendedor/piloto con perfil activo leen todas las
--     ubicaciones de su empresa (sin filtro por rol ni por jornada: las
--     jornadas todavía no existen).
--   - D5: ubicaciones inmutables: sin `activo`, sin UPDATE ni DELETE. Al
--     desactivar un camión su ubicación se conserva.
--   - D6: `tipo` es text con CHECK, no enum.
--
-- La merma y el cliente NO son ubicaciones (Blueprint §7.2). Sin saldos: el
-- stock se derivará de movimientos_stock (Etapa 2), que referenciará
-- (empresa_id, id) para no cruzar empresas.
--
-- `service_role` sin privilegios (P11: denegado por defecto; sin excepción
-- nueva). Validación exclusivamente local/staging. Prohibido aplicar en
-- producción.

do $$
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- ubicaciones
-- ---------------------------------------------------------------------------
create table public.ubicaciones (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  tipo text not null,
  camion_id uuid,
  creado_en timestamptz not null default now(),
  constraint ubicaciones_empresa_id_unico unique (empresa_id, id),
  constraint ubicaciones_camion_unico unique (empresa_id, camion_id),
  -- Con camion_id NULL (depósito, cuarentena) la FK no se evalúa (MATCH SIMPLE).
  constraint ubicaciones_camion_fk foreign key (empresa_id, camion_id)
    references public.camiones (empresa_id, id) on delete restrict,
  constraint ubicaciones_tipo_valido
    check (tipo in ('deposito', 'cuarentena', 'camion')),
  constraint ubicaciones_camion_coherente
    check ((tipo = 'camion') = (camion_id is not null))
);

-- Un depósito y una cuarentena por empresa.
create unique index ubicaciones_fija_unica
  on public.ubicaciones (empresa_id, tipo)
  where camion_id is null;

comment on table public.ubicaciones is
  'Ubicaciones internas de stock (Blueprint §7.2): deposito y cuarentena (una por empresa) y camion (una por camión). Inmutables; sin saldos. Merma y cliente no son ubicaciones.';

-- ---------------------------------------------------------------------------
-- Grants (explícitos; los defaults ya arrancan fail-closed)
-- ---------------------------------------------------------------------------
revoke all on table public.ubicaciones from public, anon, authenticated, service_role;

-- `authenticated` sólo lee (RLS filtra por empresa).
grant select on table public.ubicaciones to authenticated;

-- propietario_rpc: lectura y alta de la ubicación del camión desde
-- crear_camion. Sin UPDATE ni DELETE (D5).
grant select on table public.ubicaciones to propietario_rpc;
grant insert (empresa_id, tipo, camion_id)
  on table public.ubicaciones to propietario_rpc;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.ubicaciones enable row level security;

-- Los tres roles leen las ubicaciones de su empresa mientras su perfil esté
-- activo (D4).
create policy ubicaciones_select_empresa
  on public.ubicaciones
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = ubicaciones.empresa_id
        and p.usuario_id = (select auth.uid())
        and p.activo
    )
  );

-- Defensa en profundidad para el rol técnico (no es owner ni BYPASSRLS).
create policy ubicaciones_select_propietario_rpc
  on public.ubicaciones
  for select
  to propietario_rpc
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = ubicaciones.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
    )
  );

-- Sólo la ubicación de un camión de la misma empresa, dada de alta por un
-- dueño activo (la misma regla que el alta de camiones). Depósito y
-- cuarentena nunca se crean por RPC.
create policy ubicaciones_insert_propietario_rpc
  on public.ubicaciones
  for insert
  to propietario_rpc
  with check (
    tipo = 'camion'
    and camion_id is not null
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = ubicaciones.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol = 'dueno'
    )
    and exists (
      select 1
      from public.camiones c
      where c.id = ubicaciones.camion_id
        and c.empresa_id = ubicaciones.empresa_id
    )
  );

-- ---------------------------------------------------------------------------
-- Backfill (D1, D2): idempotente, como owner de la tabla
-- ---------------------------------------------------------------------------
insert into public.ubicaciones (empresa_id, tipo)
select e.id, t.tipo
  from public.empresas e
 cross join (values ('deposito'), ('cuarentena')) as t (tipo)
on conflict (empresa_id, tipo) where camion_id is null do nothing;

insert into public.ubicaciones (empresa_id, tipo, camion_id)
select c.empresa_id, 'camion', c.id
  from public.camiones c
on conflict (empresa_id, camion_id) do nothing;

-- ---------------------------------------------------------------------------
-- crear_camion: alta del camión y de su ubicación en la misma transacción
-- ---------------------------------------------------------------------------
-- O-3: postgres no hereda los privilegios de propietario_rpc; para redefinir
-- la función se actúa como su owner, con CREATE temporal sobre privado.
grant create on schema privado to propietario_rpc;
set role propietario_rpc;

create or replace function privado.crear_camion(
  p_patente text,
  p_nombre text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa uuid := privado.exigir_dueno_camiones();
  v_id uuid;
  v_restriccion text;
begin
  perform privado.validar_campos_camion(p_patente, p_nombre);

  begin
    insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values (v_empresa, btrim(p_patente), btrim(p_nombre), privado.usuario_actual())
    returning id into v_id;

    -- Su ubicación de stock (D2). Una falla acá revierte también el camión;
    -- una restricción de ubicaciones se informa como error interno.
    insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values (v_empresa, 'camion', v_id);
  exception
    when unique_violation or check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_camion(v_restriccion),
        message = privado.error_restriccion_camion(v_restriccion);
  end;

  return v_id;
end $$;

reset role;
revoke create on schema privado from propietario_rpc;

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
declare
  v_funcion regprocedure := 'privado.crear_camion(text,text)'::regprocedure;
begin
  if exists (
       select 1 from public.empresas e
        where (select count(*) from public.ubicaciones u
                where u.empresa_id = e.id and u.tipo = 'deposito') <> 1
           or (select count(*) from public.ubicaciones u
                where u.empresa_id = e.id and u.tipo = 'cuarentena') <> 1) then
    raise exception 'ubicaciones: alguna empresa no tiene exactamente un depósito y una cuarentena';
  end if;

  if exists (
       select 1 from public.camiones c
        where (select count(*) from public.ubicaciones u
                where u.camion_id = c.id and u.tipo = 'camion') <> 1) then
    raise exception 'ubicaciones: algún camión no tiene exactamente una ubicación';
  end if;

  if exists (
       select 1 from public.ubicaciones u
         join public.camiones c on c.id = u.camion_id
        where c.empresa_id <> u.empresa_id) then
    raise exception 'ubicaciones: una ubicación de camión cruza empresas';
  end if;

  if exists (
       select 1 from public.ubicaciones u
        where u.tipo not in ('deposito', 'cuarentena', 'camion')
           or (u.tipo = 'camion') <> (u.camion_id is not null)) then
    raise exception 'ubicaciones: tipo inválido o combinación tipo/camion_id incoherente';
  end if;

  if (select relowner from pg_class where oid = 'public.ubicaciones'::regclass)
       = 'propietario_rpc'::regrole
     or not (select relrowsecurity and not relforcerowsecurity
               from pg_class where oid = 'public.ubicaciones'::regclass)
     or has_table_privilege('authenticated', 'public.ubicaciones',
          'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     or has_any_column_privilege('authenticated', 'public.ubicaciones', 'INSERT, UPDATE, REFERENCES')
     or has_table_privilege('anon', 'public.ubicaciones',
          'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     or has_table_privilege('service_role', 'public.ubicaciones',
          'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     or has_any_column_privilege('service_role', 'public.ubicaciones', 'SELECT, INSERT, UPDATE, REFERENCES')
     or has_table_privilege('propietario_rpc', 'public.ubicaciones',
          'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN') then
    raise exception 'ubicaciones: owner, RLS o grants fuera de lo aprobado';
  end if;

  if not exists (
       select 1 from pg_proc p
        where p.oid = v_funcion
          and p.prosecdef
          and p.proowner = 'propietario_rpc'::regrole
          and p.proconfig @> array['search_path=""']
          and p.proacl @> array['propietario_rpc=X/propietario_rpc'::aclitem,
                                'authenticated=X/propietario_rpc'::aclitem]
          and array_length(p.proacl, 1) = 2)
     or has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'crear_camion: owner, SECURITY DEFINER, search_path o ACL fuera de lo aprobado';
  end if;
end $$;
