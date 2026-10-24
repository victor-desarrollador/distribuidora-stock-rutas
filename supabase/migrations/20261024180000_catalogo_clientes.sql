-- Catálogo de clientes (Blueprint §2, §3, §7.3, §8, §9, §10, §14; ADR-001
-- Topología D).
--
-- Decisiones humanas usadas (slice clientes; registradas en
-- docs/progress-log.md):
--   - Campos: nombre y telefono OBLIGATORIOS; comercio y direccion OPCIONALES.
--     Todo texto se guarda con btrim; comercio/direccion vacíos → NULL.
--   - Sin regex ni normalización de teléfono, sin unicidad de nombre,
--     teléfono, comercio o dirección, sin CUIT/DNI, email ni límite de
--     crédito. Los duplicados NO se bloquean (la política de duplicados
--     sigue pendiente), por eso no existe ningún PT409.
--   - Validación (estado_validacion): `pendiente` | `validado`.
--       vendedor/piloto crea → pendiente, validado_por/validado_en NULL.
--       dueño o encargado crea → validado, validado_por = usuario actual y
--       validado_en = now() del servidor.
--     Dueño y encargado validan un pendiente con validar_cliente (idempotente:
--     validar uno ya validado no cambia validado_por ni validado_en).
--   - Edición (nombre, telefono, comercio, direccion) y baja lógica (activo):
--     sólo dueño y encargado. El vendedor/piloto crea y consulta, nunca edita,
--     valida ni activa/desactiva. Sin DELETE.
--   - Lectura: dueño y encargado leen los clientes de su empresa (activos e
--     inactivos); el vendedor/piloto, sólo los activos. Siempre con el perfil
--     activo. No se inventan restricciones por jornada: las jornadas reales
--     todavía no existen.
--
-- Escritura sólo por las RPC crear_cliente, actualizar_cliente,
-- validar_cliente y cambiar_estado_cliente (Topología D: fachada SECURITY
-- INVOKER en `public` + implementación SECURITY DEFINER en `privado`,
-- propiedad de `propietario_rpc`). `empresa_id`, `creado_por`, `validado_por`
-- y `validado_en` los deriva el servidor: nunca los envía el cliente.
--
-- `service_role` NO recibe privilegios sobre clientes: no existe una decisión
-- aprobada para esta tabla y P11 global sigue pendiente. Queda sin
-- privilegios, como dejan las tablas nuevas los privilegios por defecto
-- endurecidos (20261024010921). No se generaliza el SELECT de productos.
--
-- Depende de las migraciones anteriores (perfiles con (empresa_id,
-- usuario_id) único, esquema `privado`, `propietario_rpc`,
-- `privado.usuario_actual()` y los privilegios por defecto fail-closed).
--
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

-- ---------------------------------------------------------------------------
-- clientes
-- ---------------------------------------------------------------------------
create table public.clientes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  nombre text not null,
  comercio text,
  direccion text,
  telefono text not null,
  activo boolean not null default true,
  estado_validacion text not null,
  creado_en timestamptz not null default now(),
  creado_por uuid not null,
  validado_en timestamptz,
  validado_por uuid,
  constraint clientes_empresa_id_unico unique (empresa_id, id),
  -- Autor y validador deben ser perfiles de la misma empresa. Con
  -- validado_por NULL la FK (MATCH SIMPLE) no se evalúa.
  constraint clientes_creado_por_fk foreign key (empresa_id, creado_por)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint clientes_validado_por_fk foreign key (empresa_id, validado_por)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint clientes_nombre_normalizado
    check (nombre = btrim(nombre) and length(nombre) > 0),
  constraint clientes_telefono_normalizado
    check (telefono = btrim(telefono) and length(telefono) > 0),
  constraint clientes_comercio_normalizado
    check (comercio is null or (comercio = btrim(comercio) and length(comercio) > 0)),
  constraint clientes_direccion_normalizada
    check (direccion is null or (direccion = btrim(direccion) and length(direccion) > 0)),
  constraint clientes_estado_validacion_valido
    check (estado_validacion in ('pendiente', 'validado')),
  constraint clientes_validacion_coherente
    check (
      (estado_validacion = 'pendiente'
        and validado_por is null and validado_en is null)
      or (estado_validacion = 'validado'
        and validado_por is not null and validado_en is not null)
    )
);

comment on table public.clientes is
  'Catálogo de clientes (Blueprint §8): contraparte comercial, no ubicación de stock. Escritura sólo por las RPC crear_cliente, actualizar_cliente, validar_cliente y cambiar_estado_cliente.';
comment on column public.clientes.estado_validacion is
  'pendiente (alta de vendedor/piloto) | validado (alta de dueño/encargado, o validado después).';

-- ---------------------------------------------------------------------------
-- Grants sobre la tabla (explícitos; los defaults ya arrancan fail-closed)
-- ---------------------------------------------------------------------------
revoke all on table public.clientes from public, anon, authenticated, service_role;

-- `authenticated` sólo lee (RLS filtra por empresa): la escritura directa
-- esquivaría la autorización por rol de las RPC.
grant select on table public.clientes to authenticated;

-- Sólo `propietario_rpc` escribe, y sólo las columnas que necesita. Sin id,
-- activo ni creado_en en INSERT (defaults); sin empresa_id, creado_por ni
-- creado_en en UPDATE; sin DELETE.
grant select on table public.clientes to propietario_rpc;
grant insert (empresa_id, nombre, comercio, direccion, telefono,
              estado_validacion, creado_por, validado_por, validado_en)
  on table public.clientes to propietario_rpc;
grant update (nombre, comercio, direccion, telefono, activo,
              estado_validacion, validado_por, validado_en)
  on table public.clientes to propietario_rpc;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.clientes enable row level security;

-- Los tres roles leen los clientes de su empresa mientras su perfil esté
-- activo; el vendedor/piloto sólo ve los activos.
create policy clientes_select_empresa
  on public.clientes
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = clientes.empresa_id
        and p.usuario_id = (select auth.uid())
        and p.activo
        and (
          p.rol in ('dueno', 'encargado')
          or clientes.activo
        )
    )
  );

-- Defensa en profundidad para el rol técnico: no es propietario de la tabla
-- ni tiene BYPASSRLS (P4), así que RLS vuelve a exigir empresa y rol.
create policy clientes_select_propietario_rpc
  on public.clientes
  for select
  to propietario_rpc
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = clientes.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
    )
  );

-- Alta: dueño/encargado → validado por sí mismos; vendedor/piloto → pendiente
-- y sin validador.
create policy clientes_insert_propietario_rpc
  on public.clientes
  for insert
  to propietario_rpc
  with check (
    creado_por = (select privado.usuario_actual())
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = clientes.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and (
          (p.rol in ('dueno', 'encargado')
            and clientes.estado_validacion = 'validado'
            and clientes.validado_por = p.usuario_id
            and clientes.validado_en is not null)
          or (p.rol = 'vendedor_piloto'
            and clientes.estado_validacion = 'pendiente'
            and clientes.validado_por is null
            and clientes.validado_en is null)
        )
    )
  );

-- Modificación: sólo dueño o encargado activos de la misma empresa.
create policy clientes_update_propietario_rpc
  on public.clientes
  for update
  to propietario_rpc
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = clientes.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  )
  with check (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = clientes.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

-- ---------------------------------------------------------------------------
-- Auxiliares privados (SECURITY INVOKER; sólo los ejecuta propietario_rpc)
-- ---------------------------------------------------------------------------
-- Errores: SQLSTATE PTxyz (PostgREST responde HTTP xyz) y un `message`
-- estable. Nunca se devuelve el detalle SQL, el nombre de la restricción ni
-- identificadores de otra empresa.

-- Exige un perfil activo y devuelve su empresa y rol. Con p_gestion = true
-- sólo admite dueño y encargado.
create function privado.exigir_perfil_clientes(
  p_gestion boolean,
  out o_empresa uuid,
  out o_rol text
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := privado.usuario_actual();
  v_activo boolean;
begin
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'cliente_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into o_empresa, o_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if o_empresa is null
     or v_activo is not true
     or (p_gestion and o_rol not in ('dueno', 'encargado')) then
    raise exception using errcode = 'PT403', message = 'cliente_no_autorizado';
  end if;
end $$;

-- Campos obligatorios. Se valida antes de tocar la tabla para devolver un
-- error estable y sin depender de los CHECK.
create function privado.validar_campos_cliente(
  p_nombre text,
  p_telefono text
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_nombre is null or btrim(p_nombre) = '' then
    raise exception using errcode = 'PT400', message = 'cliente_nombre_invalido';
  end if;

  if p_telefono is null or btrim(p_telefono) = '' then
    raise exception using errcode = 'PT400', message = 'cliente_telefono_invalido';
  end if;
end $$;

-- Traduce una violación de CHECK a un error estable, sin detalle. Como el
-- servidor ya validó y normalizó, llegar acá indica un defecto: PT500 salvo
-- las normalizaciones, que se informan como campo inválido.
create function privado.error_restriccion_cliente(p_restriccion text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_restriccion
    when 'clientes_nombre_normalizado' then 'cliente_nombre_invalido'
    when 'clientes_telefono_normalizado' then 'cliente_telefono_invalido'
    else 'cliente_error_interno'
  end
$$;

create function privado.estado_http_restriccion_cliente(p_restriccion text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case privado.error_restriccion_cliente(p_restriccion)
    when 'cliente_error_interno' then 'PT500'
    else 'PT400'
  end
$$;

-- ---------------------------------------------------------------------------
-- Implementaciones privadas (SECURITY DEFINER, Topología D)
-- ---------------------------------------------------------------------------
-- Son la frontera real de seguridad: validan todo aunque se las llame
-- directamente por SQL.

create function privado.crear_cliente(
  p_nombre text,
  p_telefono text,
  p_comercio text default null,
  p_direccion text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa uuid;
  v_rol text;
  v_uid uuid := privado.usuario_actual();
  v_validado boolean;
  v_id uuid;
  v_restriccion text;
begin
  select e.o_empresa, e.o_rol
    into v_empresa, v_rol
    from privado.exigir_perfil_clientes(false) e;

  perform privado.validar_campos_cliente(p_nombre, p_telefono);

  -- Dueño y encargado dan de alta clientes ya validados; el vendedor/piloto,
  -- pendientes de validación.
  v_validado := v_rol in ('dueno', 'encargado');

  begin
    insert into public.clientes (
      empresa_id, nombre, comercio, direccion, telefono,
      estado_validacion, creado_por, validado_por, validado_en
    )
    values (
      v_empresa,
      btrim(p_nombre),
      nullif(btrim(p_comercio), ''),
      nullif(btrim(p_direccion), ''),
      btrim(p_telefono),
      case when v_validado then 'validado' else 'pendiente' end,
      v_uid,
      case when v_validado then v_uid end,
      case when v_validado then now() end
    )
    returning id into v_id;
  exception
    when check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_cliente(v_restriccion),
        message = privado.error_restriccion_cliente(v_restriccion);
  end;

  return v_id;
end $$;

-- Reemplaza los cuatro campos editables: un comercio o dirección nulos o
-- vacíos los borran. No toca la validación ni el estado activo.
create function privado.actualizar_cliente(
  p_cliente_id uuid,
  p_nombre text,
  p_telefono text,
  p_comercio text,
  p_direccion text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa uuid;
  v_restriccion text;
begin
  select e.o_empresa into v_empresa from privado.exigir_perfil_clientes(true) e;

  perform privado.validar_campos_cliente(p_nombre, p_telefono);

  begin
    update public.clientes
       set nombre = btrim(p_nombre),
           telefono = btrim(p_telefono),
           comercio = nullif(btrim(p_comercio), ''),
           direccion = nullif(btrim(p_direccion), '')
     where id = p_cliente_id
       and empresa_id = v_empresa;
  exception
    when check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_cliente(v_restriccion),
        message = privado.error_restriccion_cliente(v_restriccion);
  end;

  -- Inexistente u otra empresa: mismo resultado (ADR-001 §8.5).
  if not found then
    raise exception using errcode = 'PT404', message = 'cliente_no_encontrado';
  end if;
end $$;

-- Transición pendiente → validado. Idempotente: validar un cliente ya
-- validado no cambia quién ni cuándo lo validó.
create function privado.validar_cliente(p_cliente_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa uuid;
  v_uid uuid := privado.usuario_actual();
begin
  select e.o_empresa into v_empresa from privado.exigir_perfil_clientes(true) e;

  update public.clientes
     set estado_validacion = 'validado',
         validado_por = v_uid,
         validado_en = now()
   where id = p_cliente_id
     and empresa_id = v_empresa
     and estado_validacion = 'pendiente';

  if not found
     and not exists (
       select 1 from public.clientes c
        where c.id = p_cliente_id
          and c.empresa_id = v_empresa
     ) then
    raise exception using errcode = 'PT404', message = 'cliente_no_encontrado';
  end if;
end $$;

create function privado.cambiar_estado_cliente(
  p_cliente_id uuid,
  p_activo boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa uuid;
begin
  select e.o_empresa into v_empresa from privado.exigir_perfil_clientes(true) e;

  if p_activo is null then
    raise exception using errcode = 'PT400', message = 'cliente_estado_invalido';
  end if;

  update public.clientes
     set activo = p_activo
   where id = p_cliente_id
     and empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'cliente_no_encontrado';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fachadas expuestas (SECURITY INVOKER): sólo delegan
-- ---------------------------------------------------------------------------
create function public.crear_cliente(
  p_nombre text,
  p_telefono text,
  p_comercio text default null,
  p_direccion text default null
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.crear_cliente(p_nombre, p_telefono, p_comercio, p_direccion)
$$;

create function public.actualizar_cliente(
  p_cliente_id uuid,
  p_nombre text,
  p_telefono text,
  p_comercio text,
  p_direccion text
)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.actualizar_cliente(
    p_cliente_id, p_nombre, p_telefono, p_comercio, p_direccion)
$$;

create function public.validar_cliente(p_cliente_id uuid)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.validar_cliente(p_cliente_id)
$$;

create function public.cambiar_estado_cliente(
  p_cliente_id uuid,
  p_activo boolean
)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.cambiar_estado_cliente(p_cliente_id, p_activo)
$$;

-- ---------------------------------------------------------------------------
-- Propiedad y EXECUTE (firmas exactas; ADR-001 §12)
-- ---------------------------------------------------------------------------
-- CREATE sobre privado sólo mientras se transfiere la propiedad; se vuelve a
-- revocar al final.
grant create on schema privado to propietario_rpc;

alter function privado.exigir_perfil_clientes(boolean) owner to propietario_rpc;
alter function privado.validar_campos_cliente(text, text) owner to propietario_rpc;
alter function privado.error_restriccion_cliente(text) owner to propietario_rpc;
alter function privado.estado_http_restriccion_cliente(text)
  owner to propietario_rpc;
alter function privado.crear_cliente(text, text, text, text)
  owner to propietario_rpc;
alter function privado.actualizar_cliente(uuid, text, text, text, text)
  owner to propietario_rpc;
alter function privado.validar_cliente(uuid) owner to propietario_rpc;
alter function privado.cambiar_estado_cliente(uuid, boolean)
  owner to propietario_rpc;

-- Auxiliares: sólo su propietario (propietario_rpc) los ejecuta.
revoke all on function privado.exigir_perfil_clientes(boolean)
  from public, anon, authenticated, service_role;
revoke all on function privado.validar_campos_cliente(text, text)
  from public, anon, authenticated, service_role;
revoke all on function privado.error_restriccion_cliente(text)
  from public, anon, authenticated, service_role;
revoke all on function privado.estado_http_restriccion_cliente(text)
  from public, anon, authenticated, service_role;

-- Implementaciones privadas: `authenticated` las necesita para que la
-- fachada INVOKER pueda delegar (ADR-001 §5 D). Ni PUBLIC, ni anon, ni
-- service_role.
revoke all on function privado.crear_cliente(text, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function privado.actualizar_cliente(uuid, text, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function privado.validar_cliente(uuid)
  from public, anon, authenticated, service_role;
revoke all on function privado.cambiar_estado_cliente(uuid, boolean)
  from public, anon, authenticated, service_role;

grant execute on function privado.crear_cliente(text, text, text, text)
  to authenticated;
grant execute on function privado.actualizar_cliente(uuid, text, text, text, text)
  to authenticated;
grant execute on function privado.validar_cliente(uuid) to authenticated;
grant execute on function privado.cambiar_estado_cliente(uuid, boolean)
  to authenticated;

-- Fachadas: sólo `authenticated`.
revoke all on function public.crear_cliente(text, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.actualizar_cliente(uuid, text, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.validar_cliente(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.cambiar_estado_cliente(uuid, boolean)
  from public, anon, authenticated, service_role;

grant execute on function public.crear_cliente(text, text, text, text)
  to authenticated;
grant execute on function public.actualizar_cliente(uuid, text, text, text, text)
  to authenticated;
grant execute on function public.validar_cliente(uuid) to authenticated;
grant execute on function public.cambiar_estado_cliente(uuid, boolean)
  to authenticated;

-- La propiedad ya quedó transferida: propietario_rpc no puede crear objetos.
revoke create on schema privado from propietario_rpc;
