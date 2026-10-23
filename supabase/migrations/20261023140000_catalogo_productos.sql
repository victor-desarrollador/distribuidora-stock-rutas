-- Catálogo de productos (Blueprint §4, §7.1, §8, §9, §10; ADR-003).
--
-- Decisiones humanas usadas (23/10/2026, slice productos; registradas en
-- docs/progress-log.md):
--   - DE-1/DE-3/DE-4/DE-5/DE-6/DE-7/DE-8/DE-9/DE-10/DE-12/DE-13/DE-14 del
--     análisis del catálogo; DE-11 modificada: `empresa_id` se deriva del
--     perfil en el servidor, nunca lo envía el cliente.
--   - DE-2: `precio` se persiste como numeric(14,2). Toda asignación a esa
--     columna redondea antes de cualquier CHECK, trigger o política, así que
--     más de 2 decimales sólo se puede rechazar sobre un parámetro `numeric`
--     sin escala. Por eso `authenticated` no escribe la tabla: escribe sólo
--     por RPC con Topología D (ADR-001 P1): fachada SECURITY INVOKER en
--     `public` + implementación SECURITY DEFINER en `privado`, propiedad de
--     `propietario_rpc` (P2/P3/P4).
--   - DE-15: el control de decimales es por valor (round(p, 2) = p).
--   - P10/P14/P16 resueltas SÓLO para este slice: dueño y encargado crean,
--     editan y cambian el estado; vendedor/piloto sólo lee; sin sobrecargas;
--     errores con códigos estables y sin detalle SQL.
--   - Identidad dentro de `propietario_rpc`: el rol de migraciones no puede
--     conceder USAGE sobre el esquema `auth` (propiedad de supabase_admin),
--     así que `privado.usuario_actual()` lee el mismo claim que auth.uid().
--
-- Sin stock: el stock sólo puede salir de movimientos_stock (Blueprint §3.1,
-- §7.4), que no existe todavía.
--
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

-- ---------------------------------------------------------------------------
-- perfiles: clave compuesta para FK con aislamiento por empresa_id (ADR-001 §8, DE-8)
-- ---------------------------------------------------------------------------
alter table public.perfiles
  add constraint perfiles_empresa_usuario_unico unique (empresa_id, usuario_id);

-- ---------------------------------------------------------------------------
-- Rol técnico propietario_rpc (P3)
-- ---------------------------------------------------------------------------
-- Los roles son globales del clúster: se crea sólo si no existe. Si ya
-- existe con otros atributos, la migración falla en lugar de corregirlos
-- (un rol no superusuario no puede alterar algunos atributos).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'propietario_rpc') then
    create role propietario_rpc
      nologin nosuperuser nocreatedb nocreaterole nobypassrls noreplication;
  elsif exists (
    select 1 from pg_roles
     where rolname = 'propietario_rpc'
       and (rolcanlogin or rolsuper or rolcreatedb or rolcreaterole
            or rolbypassrls or rolreplication)
  ) then
    raise exception 'propietario_rpc existe con atributos no permitidos';
  end if;
end $$;

-- Necesario para transferirle la propiedad de las funciones privadas.
grant propietario_rpc to current_user;

-- ---------------------------------------------------------------------------
-- Esquema privado, no expuesto por la Data API (P2)
-- ---------------------------------------------------------------------------
create schema privado;

revoke all on schema privado from public;
grant usage on schema privado to authenticated, propietario_rpc;
-- CREATE sólo mientras se transfiere la propiedad; se revoca al final.
grant create on schema privado to propietario_rpc;

grant usage on schema public to propietario_rpc;

-- ---------------------------------------------------------------------------
-- productos
-- ---------------------------------------------------------------------------
-- `categoria` y `forma_venta` son inmutables (DE-6): cambiarlas
-- reinterpretaría las cantidades en unidad mínima. `codigo` es opcional,
-- normalizado (sin espacios en los extremos) y único por empresa (DE-3).
create table public.productos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  codigo text,
  nombre text not null,
  categoria text not null,
  forma_venta text not null,
  precio numeric(14,2) not null,
  stock_minimo integer not null default 0,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  creado_por uuid not null,
  constraint productos_empresa_id_unico unique (empresa_id, id),
  constraint productos_codigo_unico unique (empresa_id, codigo),
  constraint productos_creado_por_fk foreign key (empresa_id, creado_por)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint productos_codigo_normalizado
    check (codigo is null or (codigo = btrim(codigo) and length(codigo) > 0)),
  constraint productos_nombre_normalizado
    check (nombre = btrim(nombre) and length(nombre) > 0),
  constraint productos_categoria_valida
    check (categoria in ('lacteos', 'fiambres')),
  constraint productos_forma_venta_valida
    check (forma_venta in ('unidad', 'pieza')),
  constraint productos_combinacion_valida
    check ((categoria = 'lacteos' and forma_venta = 'unidad')
        or (categoria = 'fiambres' and forma_venta = 'pieza')),
  constraint productos_precio_no_negativo check (precio >= 0),
  constraint productos_stock_minimo_no_negativo check (stock_minimo >= 0)
);

comment on table public.productos is
  'Catálogo de productos (Blueprint §8). Sin stock. Escritura sólo por las RPC crear_producto, actualizar_producto y cambiar_estado_producto.';
comment on column public.productos.precio is
  'Precio unitario (unidad) o de pieza completa (pieza). La media pieza se deriva y no se guarda (ADR-003).';
comment on column public.productos.stock_minimo is
  'Entero >= 0 en unidad mínima: unidades enteras o medias piezas (Blueprint §7.1).';

-- ---------------------------------------------------------------------------
-- Grants sobre tablas
-- ---------------------------------------------------------------------------
-- `authenticated` sólo lee: un INSERT/UPDATE directo esquivaría la
-- validación del precio. Sólo `propietario_rpc` escribe, y sólo las columnas
-- que necesita.
revoke all on table public.productos from public, anon, authenticated;

-- `service_role` (BYPASSRLS) recibe por defecto todos los privilegios sobre
-- las tablas de `public`; con ellos podría insertar un precio con fracción de
-- centavo (redondeo silencioso) o mutar categoria/forma_venta. Decisión
-- humana P11-productos (complemento): no participa de la escritura del
-- catálogo. Conserva SELECT. No resuelve P11 globalmente.
revoke insert, update, delete, truncate, references, trigger
  on table public.productos from service_role;

grant select on table public.productos to authenticated;
grant select on table public.productos to propietario_rpc;
grant insert (empresa_id, codigo, nombre, categoria, forma_venta, precio,
              stock_minimo, creado_por)
  on table public.productos to propietario_rpc;
grant update (codigo, nombre, precio, stock_minimo, activo)
  on table public.productos to propietario_rpc;

grant select on table public.perfiles to propietario_rpc;

-- ---------------------------------------------------------------------------
-- Identidad del llamador dentro de propietario_rpc
-- ---------------------------------------------------------------------------
-- Copia exacta de la expresión de auth.uid() (claim `sub` del JWT que fija
-- PostgREST). Mismo modelo de confianza que auth.uid(); una prueba pgTAP
-- verifica que ambas devuelvan siempre lo mismo.
create function privado.usuario_actual()
returns uuid
language sql
stable
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

alter function privado.usuario_actual() owner to propietario_rpc;
revoke all on function privado.usuario_actual()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.productos enable row level security;

-- Los tres roles leen los productos de su empresa mientras su perfil esté
-- activo (DE-9).
create policy productos_select_empresa
  on public.productos
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = productos.empresa_id
        and p.usuario_id = (select auth.uid())
        and p.activo
    )
  );

-- Defensa en profundidad para el rol técnico: no es propietario de la tabla
-- ni tiene BYPASSRLS (P4), así que RLS vuelve a exigir empresa y rol.
create policy productos_select_propietario_rpc
  on public.productos
  for select
  to propietario_rpc
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = productos.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
    )
  );

create policy productos_insert_propietario_rpc
  on public.productos
  for insert
  to propietario_rpc
  with check (
    creado_por = (select privado.usuario_actual())
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = productos.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

create policy productos_update_propietario_rpc
  on public.productos
  for update
  to propietario_rpc
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = productos.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  )
  with check (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = productos.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

-- El rol técnico lee sólo el perfil del llamador.
create policy perfiles_select_propio_propietario_rpc
  on public.perfiles
  for select
  to propietario_rpc
  using (usuario_id = (select privado.usuario_actual()));

-- ---------------------------------------------------------------------------
-- Auxiliares privados (SECURITY INVOKER; sólo los ejecuta propietario_rpc)
-- ---------------------------------------------------------------------------
-- Errores P16-productos: SQLSTATE PTxyz (PostgREST responde HTTP xyz) y un
-- `message` estable. Nunca se devuelve el detalle SQL.

-- Exige un perfil activo de dueño o encargado y devuelve su empresa.
create function privado.exigir_gestor_productos()
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
    raise exception using errcode = 'PT401', message = 'producto_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if v_empresa is null
     or v_activo is not true
     or v_rol is null
     or v_rol not in ('dueno', 'encargado') then
    raise exception using errcode = 'PT403', message = 'producto_no_autorizado';
  end if;

  return v_empresa;
end $$;

-- Campos editables. El precio se valida sobre `numeric` sin escala, ANTES de
-- asignarlo a la columna numeric(14,2): no nulo, >= 0, dentro del rango de
-- numeric(14,2) y con a lo sumo 2 decimales por valor (DE-15). El rango va
-- antes que el redondeo: NaN e Infinity no son < 10^12.
create function privado.validar_campos_producto(
  p_nombre text,
  p_precio numeric,
  p_stock_minimo integer
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_nombre is null or btrim(p_nombre) = '' then
    raise exception using errcode = 'PT400', message = 'producto_nombre_invalido';
  end if;

  if (p_precio >= 0
      and p_precio < 1000000000000
      and round(p_precio, 2) = p_precio) is not true then
    raise exception using errcode = 'PT400', message = 'producto_precio_invalido';
  end if;

  if p_stock_minimo is null or p_stock_minimo < 0 then
    raise exception using errcode = 'PT400', message = 'producto_stock_minimo_invalido';
  end if;
end $$;

-- Traduce una violación de restricción a un error estable, sin detalle.
create function privado.error_restriccion_producto(p_restriccion text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_restriccion
    when 'productos_codigo_unico' then 'producto_codigo_duplicado'
    when 'productos_codigo_normalizado' then 'producto_codigo_invalido'
    when 'productos_nombre_normalizado' then 'producto_nombre_invalido'
    when 'productos_categoria_valida' then 'producto_categoria_invalida'
    when 'productos_forma_venta_valida' then 'producto_forma_venta_invalida'
    when 'productos_combinacion_valida' then 'producto_combinacion_invalida'
    when 'productos_precio_no_negativo' then 'producto_precio_invalido'
    when 'productos_stock_minimo_no_negativo' then 'producto_stock_minimo_invalido'
    else 'producto_error_interno'
  end
$$;

create function privado.estado_http_restriccion_producto(p_restriccion text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case privado.error_restriccion_producto(p_restriccion)
    when 'producto_codigo_duplicado' then 'PT409'
    when 'producto_error_interno' then 'PT500'
    else 'PT400'
  end
$$;

-- ---------------------------------------------------------------------------
-- Implementaciones privadas (SECURITY DEFINER, Topología D)
-- ---------------------------------------------------------------------------
-- Son la frontera real de seguridad: validan todo aunque se las llame
-- directamente por SQL.

create function privado.crear_producto(
  p_codigo text,
  p_nombre text,
  p_categoria text,
  p_forma_venta text,
  p_precio numeric,
  p_stock_minimo integer
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa uuid := privado.exigir_gestor_productos();
  v_id uuid;
  v_restriccion text;
begin
  perform privado.validar_campos_producto(p_nombre, p_precio, p_stock_minimo);

  if p_categoria is null or p_categoria not in ('lacteos', 'fiambres') then
    raise exception using errcode = 'PT400', message = 'producto_categoria_invalida';
  end if;

  if p_forma_venta is null or p_forma_venta not in ('unidad', 'pieza') then
    raise exception using errcode = 'PT400', message = 'producto_forma_venta_invalida';
  end if;

  if not ((p_categoria = 'lacteos' and p_forma_venta = 'unidad')
       or (p_categoria = 'fiambres' and p_forma_venta = 'pieza')) then
    raise exception using errcode = 'PT400', message = 'producto_combinacion_invalida';
  end if;

  begin
    insert into public.productos (
      empresa_id, codigo, nombre, categoria, forma_venta, precio,
      stock_minimo, creado_por
    )
    values (
      v_empresa, nullif(btrim(p_codigo), ''), btrim(p_nombre), p_categoria,
      p_forma_venta, p_precio, p_stock_minimo, privado.usuario_actual()
    )
    returning id into v_id;
  exception
    when unique_violation or check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_producto(v_restriccion),
        message = privado.error_restriccion_producto(v_restriccion);
  end;

  return v_id;
end $$;

create function privado.actualizar_producto(
  p_producto_id uuid,
  p_codigo text,
  p_nombre text,
  p_precio numeric,
  p_stock_minimo integer
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa uuid := privado.exigir_gestor_productos();
  v_restriccion text;
begin
  perform privado.validar_campos_producto(p_nombre, p_precio, p_stock_minimo);

  begin
    update public.productos
       set codigo = nullif(btrim(p_codigo), ''),
           nombre = btrim(p_nombre),
           precio = p_precio,
           stock_minimo = p_stock_minimo
     where id = p_producto_id
       and empresa_id = v_empresa;
  exception
    when unique_violation or check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_producto(v_restriccion),
        message = privado.error_restriccion_producto(v_restriccion);
  end;

  -- Inexistente u otra empresa: mismo resultado (ADR-001 §8.5).
  if not found then
    raise exception using errcode = 'PT404', message = 'producto_no_encontrado';
  end if;
end $$;

create function privado.cambiar_estado_producto(
  p_producto_id uuid,
  p_activo boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa uuid := privado.exigir_gestor_productos();
begin
  if p_activo is null then
    raise exception using errcode = 'PT400', message = 'producto_estado_invalido';
  end if;

  update public.productos
     set activo = p_activo
   where id = p_producto_id
     and empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'producto_no_encontrado';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fachadas expuestas (SECURITY INVOKER): sólo delegan
-- ---------------------------------------------------------------------------
create function public.crear_producto(
  p_codigo text,
  p_nombre text,
  p_categoria text,
  p_forma_venta text,
  p_precio numeric,
  p_stock_minimo integer
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.crear_producto(
    p_codigo, p_nombre, p_categoria, p_forma_venta, p_precio, p_stock_minimo
  )
$$;

create function public.actualizar_producto(
  p_producto_id uuid,
  p_codigo text,
  p_nombre text,
  p_precio numeric,
  p_stock_minimo integer
)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.actualizar_producto(
    p_producto_id, p_codigo, p_nombre, p_precio, p_stock_minimo
  )
$$;

create function public.cambiar_estado_producto(
  p_producto_id uuid,
  p_activo boolean
)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  select privado.cambiar_estado_producto(p_producto_id, p_activo)
$$;

-- ---------------------------------------------------------------------------
-- Propiedad y EXECUTE (firmas exactas; ADR-001 §12)
-- ---------------------------------------------------------------------------
alter function privado.exigir_gestor_productos() owner to propietario_rpc;
alter function privado.validar_campos_producto(text, numeric, integer)
  owner to propietario_rpc;
alter function privado.error_restriccion_producto(text) owner to propietario_rpc;
alter function privado.estado_http_restriccion_producto(text)
  owner to propietario_rpc;
alter function privado.crear_producto(text, text, text, text, numeric, integer)
  owner to propietario_rpc;
alter function privado.actualizar_producto(uuid, text, text, numeric, integer)
  owner to propietario_rpc;
alter function privado.cambiar_estado_producto(uuid, boolean)
  owner to propietario_rpc;

-- Auxiliares: sólo su propietario (propietario_rpc) los ejecuta.
revoke all on function privado.exigir_gestor_productos()
  from public, anon, authenticated, service_role;
revoke all on function privado.validar_campos_producto(text, numeric, integer)
  from public, anon, authenticated, service_role;
revoke all on function privado.error_restriccion_producto(text)
  from public, anon, authenticated, service_role;
revoke all on function privado.estado_http_restriccion_producto(text)
  from public, anon, authenticated, service_role;

-- Implementaciones privadas: `authenticated` las necesita para que la
-- fachada INVOKER pueda delegar (ADR-001 §5 D).
revoke all on function privado.crear_producto(text, text, text, text, numeric, integer)
  from public, anon, authenticated, service_role;
revoke all on function privado.actualizar_producto(uuid, text, text, numeric, integer)
  from public, anon, authenticated, service_role;
revoke all on function privado.cambiar_estado_producto(uuid, boolean)
  from public, anon, authenticated, service_role;

grant execute on function privado.crear_producto(text, text, text, text, numeric, integer)
  to authenticated;
grant execute on function privado.actualizar_producto(uuid, text, text, numeric, integer)
  to authenticated;
grant execute on function privado.cambiar_estado_producto(uuid, boolean)
  to authenticated;

-- Fachadas: sólo `authenticated`.
revoke all on function public.crear_producto(text, text, text, text, numeric, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.actualizar_producto(uuid, text, text, numeric, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.cambiar_estado_producto(uuid, boolean)
  from public, anon, authenticated, service_role;

grant execute on function public.crear_producto(text, text, text, text, numeric, integer)
  to authenticated;
grant execute on function public.actualizar_producto(uuid, text, text, numeric, integer)
  to authenticated;
grant execute on function public.cambiar_estado_producto(uuid, boolean)
  to authenticated;

-- La propiedad ya quedó transferida: propietario_rpc no puede crear objetos.
revoke create on schema privado from propietario_rpc;
