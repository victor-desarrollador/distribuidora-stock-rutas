-- ADR-010 v1.1 + adenda A-1…A-4 — corte C1.1: esquema y seguridad de las
-- intenciones persistidas de stock (Blueprint §8 y §12; ADR-001 Topología D,
-- P3/P4/P11 y §18.3; ADR-010 v1.0 §5.2/§5.10 y anexo v1.1 §6.2/§6.3).
--
-- Alcance EXCLUSIVO de este archivo: dos tablas, sus restricciones, el único
-- índice aprobado, RLS, políticas y privilegios. NO crea funciones ni RPC
-- (llegan en C1.2), NO modifica ninguna tabla, función, política, rol ni
-- privilegio existente y NO agrega índices fuera del contrato (DT-1 diferido).
-- Tampoco decide el tratamiento de `p_desde` futuro (decisión humana
-- pendiente; no afecta a este esquema).
--
-- Contrato aplicado:
--   - intenciones_operacion (ADR-010 v1.0 §5.2): PK (empresa_id, actor_id, id);
--     `id` ES la idempotency_key de la operación de negocio (§5.11); FK a
--     empresas y a perfiles (empresa_id, usuario_id); FK COMPUESTA
--     (empresa_id, operacion_id, tipo, actor_id) → operaciones, que usa la
--     UNIQUE operaciones_referencia_apertura ya existente (20261030120000), de
--     modo que `operaciones` NO recibe columnas ni restricciones nuevas;
--     CHECK de tipo, estado, payload objeto, vence_en > creado_en y coherencia
--     estado ↔ operacion_id/codigo_rechazo/resuelto_en.
--   - v1.1 §6.2 (1): UNIQUE (empresa_id, actor_id, operacion_id), destino de la
--     FK de reconocimientos; operacion_id es anulable (NULLS DISTINCT: las
--     pendientes no chocan).
--   - intenciones_reconocimientos (v1.1 §6.2 (2)): registro solo de inserción;
--     referencia la UNIQUE anterior por operacion_id y NO almacena la
--     idempotency_key (P15 / extensión de §7.1 de v1.0).
--   - Alternativa A (D-IDEM-15): ningún acceso directo de `authenticated`,
--     `anon`, `service_role` ni `lector_perfiles_rpc` (ni de tabla ni de
--     columna). `propietario_rpc` con SELECT de tabla e INSERT/UPDATE solo por
--     columna; sin DELETE (retención indefinida, D-IDEM-3).
--   - RLS habilitada SIN FORCE (P4). Exactamente 3 + 2 políticas, todas para
--     propietario_rpc; PROHIBIDA toda política UPDATE permisiva adicional
--     (anexo §4.6): las terminales no cambian.
--   - Identidad solo por privado.usuario_actual(); ningún uso de auth.uid() ni
--     de user_metadata (R-10, R-12).
--
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

do $$
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;

  -- Dependencias que este corte NO crea: fallar cerrado si faltan.
  if to_regclass('public.empresas') is null
     or to_regclass('public.perfiles') is null
     or to_regclass('public.operaciones') is null
     or to_regprocedure('privado.usuario_actual()') is null
     or not exists (select 1 from pg_roles where rolname = 'propietario_rpc')
     or not exists (
          select 1 from pg_constraint
           where conrelid = 'public.operaciones'::regclass
             and conname = 'operaciones_referencia_apertura'
             and contype = 'u'
             and pg_get_constraintdef(oid) = 'UNIQUE (empresa_id, id, tipo, actor_id)')
     or not exists (
          select 1 from pg_constraint
           where conrelid = 'public.perfiles'::regclass
             and conname = 'perfiles_empresa_usuario_unico'
             and contype = 'u') then
    raise exception
      'intenciones: faltan dependencias aprobadas (empresas, perfiles, operaciones, operaciones_referencia_apertura, privado.usuario_actual(), propietario_rpc)';
  end if;

  if to_regclass('public.intenciones_operacion') is not null
     or to_regclass('public.intenciones_reconocimientos') is not null then
    raise exception 'intenciones: las tablas ya existen; esta migración es hacia adelante y no es repetible';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- intenciones_operacion
-- ---------------------------------------------------------------------------
create table public.intenciones_operacion (
  id uuid not null,
  empresa_id uuid not null,
  actor_id uuid not null,
  tipo text not null,
  payload jsonb not null,
  estado text not null default 'pendiente',
  operacion_id uuid,
  codigo_rechazo text,
  creado_en timestamptz not null default clock_timestamp(),
  vence_en timestamptz not null,
  resuelto_en timestamptz,
  constraint intenciones_operacion_pkey primary key (empresa_id, actor_id, id),
  constraint intenciones_operacion_empresa_fk foreign key (empresa_id)
    references public.empresas (id) on delete restrict,
  constraint intenciones_operacion_actor_fk foreign key (empresa_id, actor_id)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  -- MATCH SIMPLE (por defecto): mientras la intención está `pendiente`,
  -- operacion_id es NULL y la FK no se evalúa.
  constraint intenciones_operacion_operacion_fk
    foreign key (empresa_id, operacion_id, tipo, actor_id)
    references public.operaciones (empresa_id, id, tipo, actor_id) on delete restrict,
  constraint intenciones_tipo_valido
    check (tipo in ('ingreso', 'a_cuarentena', 'merma')),
  constraint intenciones_estado_valido
    check (estado in ('pendiente', 'confirmada', 'rechazada', 'cancelada')),
  constraint intenciones_payload_objeto
    check (jsonb_typeof(payload) = 'object'),
  constraint intenciones_vence_posterior
    check (vence_en > creado_en),
  constraint intenciones_coherencia check (
       (estado = 'pendiente'  and operacion_id is null     and codigo_rechazo is null     and resuelto_en is null)
    or (estado = 'confirmada' and operacion_id is not null and codigo_rechazo is null     and resuelto_en is not null)
    or (estado = 'rechazada'  and operacion_id is null     and codigo_rechazo is not null and resuelto_en is not null)
    or (estado = 'cancelada'  and operacion_id is null     and codigo_rechazo is null     and resuelto_en is not null))
);

-- v1.1 §6.2 (1): relación 1:1 operación ↔ intención y destino de la FK de
-- reconocimientos. operacion_id anulable: las pendientes no chocan.
alter table public.intenciones_operacion
  add constraint intenciones_operacion_operacion_unica
  unique (empresa_id, actor_id, operacion_id);

-- Único índice aprobado (ADR-010 v1.0 §5.2).
create index intenciones_actor_idx
  on public.intenciones_operacion (empresa_id, actor_id, creado_en desc);

comment on table public.intenciones_operacion is
  'ADR-010: intención persistida y previa a una operación de stock. id = idempotency_key de la operación. No es ledger ni auditoría. Acceso solo por RPC; retención indefinida.';

-- ---------------------------------------------------------------------------
-- intenciones_reconocimientos (solo inserción; no almacena la idempotency_key)
-- ---------------------------------------------------------------------------
create table public.intenciones_reconocimientos (
  empresa_id uuid not null,
  actor_id uuid not null,
  operacion_id uuid not null,
  reconocido_en timestamptz not null default clock_timestamp(),
  constraint intenciones_reconocimientos_pkey primary key (empresa_id, actor_id, operacion_id),
  constraint intenciones_reconocimientos_intencion_fk
    foreign key (empresa_id, actor_id, operacion_id)
    references public.intenciones_operacion (empresa_id, actor_id, operacion_id)
    on delete restrict
);

comment on table public.intenciones_reconocimientos is
  'ADR-010 v1.1: marca de que la interfaz mostró al actor una operación confirmada. Solo inserción; referencia operacion_id (no la idempotency_key); nunca mueve stock. Acceso solo por RPC.';

-- ---------------------------------------------------------------------------
-- Privilegios (explícitos; los defaults ya arrancan fail-closed)
-- ---------------------------------------------------------------------------
-- El REVOKE de tabla también revoca los privilegios por columna (PostgreSQL).
revoke all on table public.intenciones_operacion, public.intenciones_reconocimientos
  from public, anon, authenticated, service_role;

grant select on table public.intenciones_operacion to propietario_rpc;
grant insert (empresa_id, actor_id, id, tipo, payload, vence_en)
  on table public.intenciones_operacion to propietario_rpc;
grant update (estado, operacion_id, codigo_rechazo, resuelto_en)
  on table public.intenciones_operacion to propietario_rpc;

grant select on table public.intenciones_reconocimientos to propietario_rpc;
grant insert (empresa_id, actor_id, operacion_id)
  on table public.intenciones_reconocimientos to propietario_rpc;

-- ---------------------------------------------------------------------------
-- RLS (habilitada, sin FORCE) y políticas: 3 + 2, todas para propietario_rpc
-- ---------------------------------------------------------------------------
alter table public.intenciones_operacion enable row level security;
alter table public.intenciones_reconocimientos enable row level security;

-- Solo el actor creador ve su intención, con perfil activo de la misma empresa.
create policy intenciones_operacion_select_propietario_rpc
  on public.intenciones_operacion
  for select
  to propietario_rpc
  using (
    actor_id = (select privado.usuario_actual())
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = intenciones_operacion.empresa_id
        and p.usuario_id = intenciones_operacion.actor_id
        and p.activo
    )
  );

create policy intenciones_operacion_insert_propietario_rpc
  on public.intenciones_operacion
  for insert
  to propietario_rpc
  with check (
    actor_id = (select privado.usuario_actual())
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = intenciones_operacion.empresa_id
        and p.usuario_id = intenciones_operacion.actor_id
        and p.activo
    )
  );

-- UPDATE: USING y WITH CHECK explícitos y distintos (precisión de Codex,
-- ADR-010 §5.10). Solo se actualizan intenciones PENDIENTES del propio actor
-- (las terminales no cambian) y la fila resultante queda del actor en un estado
-- TERMINAL: no se puede volver a `pendiente` ni reasignar el actor. La
-- coherencia de los campos la impone intenciones_coherencia.
create policy intenciones_operacion_update_propietario_rpc
  on public.intenciones_operacion
  for update
  to propietario_rpc
  using (
    estado = 'pendiente'
    and actor_id = (select privado.usuario_actual())
  )
  with check (
    actor_id = (select privado.usuario_actual())
    and estado in ('confirmada', 'rechazada', 'cancelada')
  );

create policy intenciones_reconocimientos_select_propietario_rpc
  on public.intenciones_reconocimientos
  for select
  to propietario_rpc
  using (
    actor_id = (select privado.usuario_actual())
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = intenciones_reconocimientos.empresa_id
        and p.usuario_id = intenciones_reconocimientos.actor_id
        and p.activo
    )
  );

-- Sin EXISTS sobre la intención: «corresponde a una confirmada» lo impone el
-- esquema (FK + NOT NULL + intenciones_coherencia); actor y empresa, esta
-- política y la RPC (anexo §6.2 (3), §6.3).
create policy intenciones_reconocimientos_insert_propietario_rpc
  on public.intenciones_reconocimientos
  for insert
  to propietario_rpc
  with check (
    actor_id = (select privado.usuario_actual())
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = intenciones_reconocimientos.empresa_id
        and p.usuario_id = intenciones_reconocimientos.actor_id
        and p.activo
    )
  );

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
declare
  v_roles text[] := array['anon', 'authenticated', 'service_role', 'lector_perfiles_rpc'];
  v_rol text;
  v_tabla regclass;
begin
  foreach v_tabla in array array['public.intenciones_operacion'::regclass,
                                 'public.intenciones_reconocimientos'::regclass] loop
    -- Owner de migraciones, RLS habilitada, sin FORCE (P4).
    if not exists (select 1 from pg_class c
                    where c.oid = v_tabla and c.relkind = 'r'
                      and c.relowner = 'postgres'::regrole
                      and c.relrowsecurity and not c.relforcerowsecurity) then
      raise exception 'intenciones: owner, RLS o FORCE de % fuera de lo aprobado', v_tabla;
    end if;

    -- Ningún privilegio de tabla ni de columna (incluido SELECT por columna)
    -- para PUBLIC ni para los roles de la Data API, service_role y el lector.
    if exists (select 1 from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
                where c.oid = v_tabla and a.grantee = 0)
       or exists (select 1 from pg_attribute at, aclexplode(at.attacl) a
                   where at.attrelid = v_tabla and at.attnum > 0 and not at.attisdropped
                     and a.grantee = 0) then
      raise exception 'intenciones: PUBLIC tiene privilegios sobre %', v_tabla;
    end if;
    foreach v_rol in array v_roles loop
      if has_table_privilege(v_rol, v_tabla,
           'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
         or has_any_column_privilege(v_rol, v_tabla, 'SELECT, INSERT, UPDATE, REFERENCES') then
        raise exception 'intenciones: el rol % tiene privilegios sobre % (alternativa A: ninguno)', v_rol, v_tabla;
      end if;
    end loop;

    -- propietario_rpc: sin ningún privilegio de tabla de escritura.
    if has_table_privilege('propietario_rpc', v_tabla,
         'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
       or not has_table_privilege('propietario_rpc', v_tabla, 'SELECT') then
      raise exception 'intenciones: privilegios de tabla de propietario_rpc sobre % fuera de lo aprobado', v_tabla;
    end if;
  end loop;

  -- Privilegios por columna de propietario_rpc: exactamente los aprobados.
  if (select array_agg(at.attname::text order by at.attname)
        from pg_attribute at
       where at.attrelid = 'public.intenciones_operacion'::regclass and at.attnum > 0 and not at.attisdropped
         and has_column_privilege('propietario_rpc', at.attrelid, at.attnum, 'INSERT'))
        is distinct from array['actor_id', 'empresa_id', 'id', 'payload', 'tipo', 'vence_en']
     or (select array_agg(at.attname::text order by at.attname)
           from pg_attribute at
          where at.attrelid = 'public.intenciones_operacion'::regclass and at.attnum > 0 and not at.attisdropped
            and has_column_privilege('propietario_rpc', at.attrelid, at.attnum, 'UPDATE'))
           is distinct from array['codigo_rechazo', 'estado', 'operacion_id', 'resuelto_en']
     or (select array_agg(at.attname::text order by at.attname)
           from pg_attribute at
          where at.attrelid = 'public.intenciones_reconocimientos'::regclass and at.attnum > 0 and not at.attisdropped
            and has_column_privilege('propietario_rpc', at.attrelid, at.attnum, 'INSERT'))
           is distinct from array['actor_id', 'empresa_id', 'operacion_id']
     or exists (select 1 from pg_attribute at
                 where at.attrelid = 'public.intenciones_reconocimientos'::regclass and at.attnum > 0
                   and not at.attisdropped
                   and has_column_privilege('propietario_rpc', at.attrelid, at.attnum, 'UPDATE')) then
    raise exception 'intenciones: privilegios por columna de propietario_rpc fuera de lo aprobado';
  end if;

  -- Exactamente 3 + 2 políticas, todas para propietario_rpc y ninguna para otro rol.
  if (select count(*) from pg_policy where polrelid = 'public.intenciones_operacion'::regclass) <> 3
     or (select count(*) from pg_policy where polrelid = 'public.intenciones_reconocimientos'::regclass) <> 2
     or exists (select 1 from pg_policy p
                 where p.polrelid in ('public.intenciones_operacion'::regclass,
                                      'public.intenciones_reconocimientos'::regclass)
                   and (p.polroles <> array['propietario_rpc'::regrole]::oid[] or not p.polpermissive))
     or (select count(*) from pg_policy p
          where p.polrelid = 'public.intenciones_operacion'::regclass and p.polcmd = 'w') <> 1 then
    raise exception 'intenciones: el conjunto de políticas RLS no es el aprobado (3 + 2, solo propietario_rpc, una sola UPDATE)';
  end if;

  -- Integridad: PK, FK compuesta de 4 columnas, UNIQUE y FK de reconocimientos.
  if not exists (select 1 from pg_constraint
                  where conname = 'intenciones_operacion_operacion_fk'
                    and conrelid = 'public.intenciones_operacion'::regclass
                    and confrelid = 'public.operaciones'::regclass
                    and array_length(conkey, 1) = 4 and confdeltype = 'r' and confmatchtype = 's')
     or not exists (select 1 from pg_constraint
                     where conname = 'intenciones_operacion_operacion_unica'
                       and conrelid = 'public.intenciones_operacion'::regclass and contype = 'u'
                       and pg_get_constraintdef(oid) = 'UNIQUE (empresa_id, actor_id, operacion_id)')
     or not exists (select 1 from pg_constraint
                     where conname = 'intenciones_reconocimientos_intencion_fk'
                       and conrelid = 'public.intenciones_reconocimientos'::regclass
                       and confrelid = 'public.intenciones_operacion'::regclass
                       and array_length(conkey, 1) = 3 and confdeltype = 'r')
     or exists (select 1 from pg_attribute at
                 where at.attrelid = 'public.intenciones_reconocimientos'::regclass and at.attnum > 0
                   and not at.attisdropped and at.attname in ('idempotency_key', 'intencion_id', 'id')) then
    raise exception 'intenciones: restricciones de integridad fuera de lo aprobado';
  end if;

  -- Índices: solo los aprobados (PK, UNIQUE e intenciones_actor_idx; PK de reconocimientos).
  if (select count(*) from pg_index where indrelid = 'public.intenciones_operacion'::regclass) <> 3
     or (select count(*) from pg_index where indrelid = 'public.intenciones_reconocimientos'::regclass) <> 1 then
    raise exception 'intenciones: índices fuera de lo aprobado';
  end if;

  -- Esta migración no crea funciones ni triggers.
  if exists (select 1 from pg_trigger t
              where t.tgrelid in ('public.intenciones_operacion'::regclass,
                                  'public.intenciones_reconocimientos'::regclass)
                and not t.tgisinternal) then
    raise exception 'intenciones: no se admiten triggers en este corte';
  end if;
end $$;
