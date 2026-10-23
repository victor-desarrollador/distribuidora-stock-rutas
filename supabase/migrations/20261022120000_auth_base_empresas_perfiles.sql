-- Auth base: empresas y perfiles (Blueprint §7.3, §8, §9, §10).
--
-- Decisiones humanas usadas (22/10/2026, registradas en ADR-001 §18 y en
-- docs/progress-log.md): un usuario pertenece a una sola empresa (P6), tiene
-- exactamente un rol (P7) y su empresa/rol se leen de un único perfil 1:1 con
-- auth.users (P5). Sin tabla de membresías ni tabla de roles.
--
-- Este bloque NO crea funciones SECURITY DEFINER, RPC ni esquemas privados
-- (ADR-001 P2/P3/P4/P14 siguen pendientes). Las tablas quedan en `public`,
-- propiedad del rol que ejecuta las migraciones, y RLS se aplica a `anon` y
-- `authenticated`.
--
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

-- ---------------------------------------------------------------------------
-- empresas
-- ---------------------------------------------------------------------------
-- Entidad dueña de los datos de negocio. En Fase 1 existe una sola empresa
-- real; no hay registro público ni panel de plataforma (Blueprint §7.3).
create table public.empresas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  constraint empresas_nombre_no_vacio check (length(btrim(nombre)) > 0)
);

comment on table public.empresas is
  'Empresa dueña de los datos de negocio (Blueprint §7.3). Sin registro público ni administración de plataforma.';

-- ---------------------------------------------------------------------------
-- perfiles
-- ---------------------------------------------------------------------------
-- Perfil 1:1 con auth.users. Es la única fuente de autoridad para empresa,
-- rol y estado del usuario: nunca se usa user_metadata (Blueprint §7.3, §10).
--
-- `usuario` es el identificador visible para iniciar sesión. Se guarda ya
-- normalizado (minúsculas, sin espacios) y el CHECK impide cualquier otra
-- forma, por lo que UNIQUE sobre la columna equivale a unicidad
-- case-insensitive. La identidad interna de Supabase Auth se deriva de forma
-- determinista: `<usuario>@usuarios.distribuidora.invalid` (detalle técnico de
-- Auth, no es un email de negocio).
--
-- `rol` usa CHECK sobre text en lugar de enum: es igual de restrictivo, se lee
-- en el DDL y cambiarlo no requiere ALTER TYPE. No existe tabla `roles`
-- (Blueprint §8: no aprobada).
--
-- FK a auth.users con ON DELETE RESTRICT: una cuenta con perfil no se borra,
-- se desactiva (`activo = false`), para no perder trazabilidad futura.
create table public.perfiles (
  usuario_id uuid primary key references auth.users (id) on delete restrict,
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  usuario text not null,
  nombre text not null,
  rol text not null,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  constraint perfiles_usuario_unico unique (usuario),
  constraint perfiles_usuario_formato
    check (usuario ~ '^[a-z0-9][a-z0-9._-]{2,31}$'),
  constraint perfiles_nombre_no_vacio check (length(btrim(nombre)) > 0),
  constraint perfiles_rol_valido
    check (rol in ('dueno', 'encargado', 'vendedor_piloto'))
);

create index perfiles_empresa_id_idx on public.perfiles (empresa_id);

comment on table public.perfiles is
  'Perfil 1:1 con auth.users: empresa, rol y estado. Fuente de autoridad; nunca user_metadata.';
comment on column public.perfiles.usuario is
  'Usuario visible de login, normalizado. Identidad Auth interna: <usuario>@usuarios.distribuidora.invalid.';

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
-- No se depende de los privilegios por defecto del proyecto: se revoca todo y
-- se concede sólo lectura a `authenticated`. `anon` no recibe nada. Las altas,
-- cambios de rol/empresa/estado y bajas son administrativas (fuera de la Data
-- API del usuario).
revoke all on table public.empresas from public, anon, authenticated;
revoke all on table public.perfiles from public, anon, authenticated;

grant select on table public.empresas to authenticated;
grant select on table public.perfiles to authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.empresas enable row level security;
alter table public.perfiles enable row level security;

-- Cada usuario autenticado lee únicamente su propio perfil (también si está
-- inactivo, para que la interfaz pueda informar el bloqueo). Un perfil
-- inactivo no autoriza nada: la política de empresas lo excluye y el
-- frontend bloquea el acceso.
create policy perfiles_select_propio
  on public.perfiles
  for select
  to authenticated
  using (usuario_id = (select auth.uid()));

-- Un usuario autenticado lee sólo la empresa de su propio perfil activo.
-- La subconsulta sobre perfiles está a su vez sujeta a la RLS de perfiles
-- (sólo la fila propia), sin funciones SECURITY DEFINER.
create policy empresas_select_propia
  on public.empresas
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = empresas.id
        and p.usuario_id = (select auth.uid())
        and p.activo
    )
  );

-- Sin políticas de INSERT/UPDATE/DELETE: con RLS activa y sin grants de
-- escritura, `authenticated` no puede crear, modificar (rol, empresa_id,
-- activo) ni borrar perfiles o empresas.
