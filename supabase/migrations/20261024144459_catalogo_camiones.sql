-- Catálogo de camiones (Blueprint §3, §4, §7.3, §8, §9, §10; ADR-001 Topología D).
--
-- Decisión humana usada (24/10/2026, slice camiones; registrada en
-- docs/progress-log.md): matriz de permisos del catálogo.
--   - dueño: SELECT, crear, editar y activar/desactivar.
--   - encargado y vendedor/piloto: SELECT únicamente.
--   - anon y otra empresa: nada.
-- No amplía esa matriz. Escritura sólo por las RPC crear_camion,
-- actualizar_camion y cambiar_estado_camion (Topología D: fachada
-- SECURITY INVOKER en `public` + implementación SECURITY DEFINER en
-- `privado`, propiedad de `propietario_rpc`). `empresa_id` y el autor los
-- deriva el servidor del perfil: nunca los envía el cliente.
--
-- Modelo mínimo (Blueprint §8): patente, nombre, activo. Sin marca, modelo,
-- observaciones ni estado operativo: `en_reparto` se resolverá cuando exista
-- la jornada (Blueprint §7.5) y no se duplica acá como dato mutable.
--
-- Decisiones técnicas del slice (no son reglas de negocio nuevas):
--   - `patente` se guarda tal como se recibe, sólo sin espacios en los
--     extremos. Sin regex, sin normalizar mayúsculas ni quitar espacios o
--     guiones, sin asumir formato legacy o Mercosur, sin citext.
--   - UNIQUE (empresa_id, patente), sensible a mayúsculas como cualquier
--     comparación de PostgreSQL: «abc123» y «ABC123» serían dos patentes
--     distintas. Queda registrado como riesgo para decisión humana.
--   - Sin idempotency_key ni locks explícitos: CRUD maestro simple, igual
--     que productos (UNIQUE + transacción de la sentencia alcanzan).
--   - `service_role` NO recibe privilegios sobre camiones: no existe una
--     decisión aprobada para esta tabla y P11 global sigue pendiente. Queda
--     sin privilegios, como dejan las tablas nuevas los privilegios por
--     defecto endurecidos (20261024010921).
--
-- Depende de las cuatro migraciones anteriores (perfiles con
-- (empresa_id, usuario_id) único, esquema `privado`, `propietario_rpc`,
-- `privado.usuario_actual()` y los privilegios por defecto fail-closed).
--
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

-- ---------------------------------------------------------------------------
-- camiones
-- ---------------------------------------------------------------------------
create table public.camiones (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  patente text not null,
  nombre text not null,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  creado_por uuid not null,
  constraint camiones_empresa_id_unico unique (empresa_id, id),
  constraint camiones_patente_unica unique (empresa_id, patente),
  constraint camiones_creado_por_fk foreign key (empresa_id, creado_por)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint camiones_patente_normalizada
    check (patente = btrim(patente) and length(patente) > 0),
  constraint camiones_nombre_normalizado
    check (nombre = btrim(nombre) and length(nombre) > 0)
);

comment on table public.camiones is
  'Catálogo de camiones (Blueprint §8): patente, nombre y activo. Sin estado operativo ni stock. Escritura sólo por las RPC crear_camion, actualizar_camion y cambiar_estado_camion.';
comment on column public.camiones.patente is
  'Se guarda tal como se recibe, sin espacios en los extremos. Única por empresa y sensible a mayúsculas.';

-- ---------------------------------------------------------------------------
-- Grants sobre la tabla (explícitos; los defaults ya arrancan fail-closed)
-- ---------------------------------------------------------------------------
revoke all on table public.camiones from public, anon, authenticated, service_role;

-- `authenticated` sólo lee (RLS filtra por empresa): la escritura directa
-- esquivaría la autorización por rol de las RPC.
grant select on table public.camiones to authenticated;

-- Sólo `propietario_rpc` escribe, y sólo las columnas que necesita.
grant select on table public.camiones to propietario_rpc;
grant insert (empresa_id, patente, nombre, creado_por)
  on table public.camiones to propietario_rpc;
grant update (patente, nombre, activo)
  on table public.camiones to propietario_rpc;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.camiones enable row level security;

-- Los tres roles leen los camiones de su empresa mientras su perfil esté
-- activo.
create policy camiones_select_empresa
  on public.camiones
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = camiones.empresa_id
        and p.usuario_id = (select auth.uid())
        and p.activo
    )
  );

-- Defensa en profundidad para el rol técnico: no es propietario de la tabla
-- ni tiene BYPASSRLS (P4), así que RLS vuelve a exigir empresa y rol.
create policy camiones_select_propietario_rpc
  on public.camiones
  for select
  to propietario_rpc
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = camiones.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
    )
  );

create policy camiones_insert_propietario_rpc
  on public.camiones
  for insert
  to propietario_rpc
  with check (
    creado_por = (select privado.usuario_actual())
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = camiones.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol = 'dueno'
    )
  );

create policy camiones_update_propietario_rpc
  on public.camiones
  for update
  to propietario_rpc
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = camiones.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol = 'dueno'
    )
  )
  with check (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = camiones.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol = 'dueno'
    )
  );

-- ---------------------------------------------------------------------------
-- Auxiliares privados (SECURITY INVOKER; sólo los ejecuta propietario_rpc)
-- ---------------------------------------------------------------------------
-- Errores: SQLSTATE PTxyz (PostgREST responde HTTP xyz) y un `message`
-- estable. Nunca se devuelve el detalle SQL, el nombre de la restricción ni
-- identificadores de otra empresa.

-- Exige un perfil activo de dueño y devuelve su empresa.
create function privado.exigir_dueno_camiones()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := privado.usuario_actual();
  v_empresa uuid;
  v_rol text;
  v_activo boolean;
begin
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'camion_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if v_empresa is null
     or v_activo is not true
     or v_rol is distinct from 'dueno' then
    raise exception using errcode = 'PT403', message = 'camion_no_autorizado';
  end if;

  return v_empresa;
end $$;

-- Campos editables. Se valida antes de tocar la tabla para devolver un error
-- estable y sin depender de los CHECK.
create function privado.validar_campos_camion(
  p_patente text,
  p_nombre text
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_patente is null or btrim(p_patente) = '' then
    raise exception using errcode = 'PT400', message = 'camion_patente_invalida';
  end if;

  if p_nombre is null or btrim(p_nombre) = '' then
    raise exception using errcode = 'PT400', message = 'camion_nombre_invalido';
  end if;
end $$;

-- Traduce una violación de restricción a un error estable, sin detalle.
create function privado.error_restriccion_camion(p_restriccion text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_restriccion
    when 'camiones_patente_unica' then 'camion_patente_duplicada'
    when 'camiones_patente_normalizada' then 'camion_patente_invalida'
    when 'camiones_nombre_normalizado' then 'camion_nombre_invalido'
    else 'camion_error_interno'
  end
$$;

create function privado.estado_http_restriccion_camion(p_restriccion text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case privado.error_restriccion_camion(p_restriccion)
    when 'camion_patente_duplicada' then 'PT409'
    when 'camion_error_interno' then 'PT500'
    else 'PT400'
  end
$$;

-- ---------------------------------------------------------------------------
-- Implementaciones privadas (SECURITY DEFINER, Topología D)
-- ---------------------------------------------------------------------------
-- Son la frontera real de seguridad: validan todo aunque se las llame
-- directamente por SQL.

create function privado.crear_camion(
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
  exception
    when unique_violation or check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_camion(v_restriccion),
        message = privado.error_restriccion_camion(v_restriccion);
  end;

  return v_id;
end $$;

create function privado.actualizar_camion(
  p_camion_id uuid,
  p_patente text,
  p_nombre text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa uuid := privado.exigir_dueno_camiones();
  v_restriccion text;
begin
  perform privado.validar_campos_camion(p_patente, p_nombre);

  begin
    update public.camiones
       set patente = btrim(p_patente),
           nombre = btrim(p_nombre)
     where id = p_camion_id
       and empresa_id = v_empresa;
  exception
    when unique_violation or check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_camion(v_restriccion),
        message = privado.error_restriccion_camion(v_restriccion);
  end;

  -- Inexistente u otra empresa: mismo resultado (ADR-001 §8.5).
  if not found then
    raise exception using errcode = 'PT404', message = 'camion_no_encontrado';
  end if;
end $$;

create function privado.cambiar_estado_camion(
  p_camion_id uuid,
  p_activo boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa uuid := privado.exigir_dueno_camiones();
begin
  if p_activo is null then
    raise exception using errcode = 'PT400', message = 'camion_estado_invalido';
  end if;

  update public.camiones
     set activo = p_activo
   where id = p_camion_id
     and empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'camion_no_encontrado';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fachadas expuestas (SECURITY INVOKER): sólo delegan
-- ---------------------------------------------------------------------------
create function public.crear_camion(
  p_patente text,
  p_nombre text
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.crear_camion(p_patente, p_nombre)
$$;

create function public.actualizar_camion(
  p_camion_id uuid,
  p_patente text,
  p_nombre text
)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.actualizar_camion(p_camion_id, p_patente, p_nombre)
$$;

create function public.cambiar_estado_camion(
  p_camion_id uuid,
  p_activo boolean
)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.cambiar_estado_camion(p_camion_id, p_activo)
$$;

-- ---------------------------------------------------------------------------
-- Propiedad y EXECUTE (firmas exactas; ADR-001 §12)
-- ---------------------------------------------------------------------------
-- CREATE sobre privado sólo mientras se transfiere la propiedad (la
-- migración de productos lo revocó al terminar); se vuelve a revocar al final.
grant create on schema privado to propietario_rpc;

alter function privado.exigir_dueno_camiones() owner to propietario_rpc;
alter function privado.validar_campos_camion(text, text) owner to propietario_rpc;
alter function privado.error_restriccion_camion(text) owner to propietario_rpc;
alter function privado.estado_http_restriccion_camion(text)
  owner to propietario_rpc;
alter function privado.crear_camion(text, text) owner to propietario_rpc;
alter function privado.actualizar_camion(uuid, text, text) owner to propietario_rpc;
alter function privado.cambiar_estado_camion(uuid, boolean) owner to propietario_rpc;

-- Auxiliares: sólo su propietario (propietario_rpc) los ejecuta.
revoke all on function privado.exigir_dueno_camiones()
  from public, anon, authenticated, service_role;
revoke all on function privado.validar_campos_camion(text, text)
  from public, anon, authenticated, service_role;
revoke all on function privado.error_restriccion_camion(text)
  from public, anon, authenticated, service_role;
revoke all on function privado.estado_http_restriccion_camion(text)
  from public, anon, authenticated, service_role;

-- Implementaciones privadas: `authenticated` las necesita para que la
-- fachada INVOKER pueda delegar (ADR-001 §5 D). Ni PUBLIC, ni anon, ni
-- service_role.
revoke all on function privado.crear_camion(text, text)
  from public, anon, authenticated, service_role;
revoke all on function privado.actualizar_camion(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function privado.cambiar_estado_camion(uuid, boolean)
  from public, anon, authenticated, service_role;

grant execute on function privado.crear_camion(text, text) to authenticated;
grant execute on function privado.actualizar_camion(uuid, text, text)
  to authenticated;
grant execute on function privado.cambiar_estado_camion(uuid, boolean)
  to authenticated;

-- Fachadas: sólo `authenticated`.
revoke all on function public.crear_camion(text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.actualizar_camion(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.cambiar_estado_camion(uuid, boolean)
  from public, anon, authenticated, service_role;

grant execute on function public.crear_camion(text, text) to authenticated;
grant execute on function public.actualizar_camion(uuid, text, text)
  to authenticated;
grant execute on function public.cambiar_estado_camion(uuid, boolean)
  to authenticated;

-- La propiedad ya quedó transferida: propietario_rpc no puede crear objetos.
revoke create on schema privado from propietario_rpc;
