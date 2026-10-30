-- D-2: segundo rol técnico `lector_perfiles_rpc` y lectura acotada de perfiles
-- (ADR-001 §18.4.2.1; Blueprint §7.3, §9, §10; ADR-007 §2.3).
--
-- Decisión humana: ADR-001 §18.4 aprobado el 29/10/2026 para VALIDACIÓN
-- CONTROLADA local/staging, acotado a jornadas y carga de camiones. D-2 amplía
-- P2–P4 (hasta hoy un solo rol técnico, `propietario_rpc`) y no cambia P11 ni
-- P5–P7. Validación exclusivamente local/staging. Prohibido aplicar en
-- producción.
--
-- Qué resuelve. Para validar el vendedor asignado a una jornada, las RPC
-- (que corren como `propietario_rpc`) tienen que leer perfiles que no son el
-- del llamador, pero la RLS de `perfiles` sólo muestra la fila propia. Una
-- política sobre `perfiles` que consulte `perfiles` recursa (42P17), y un
-- helper SECURITY DEFINER del mismo owner usado dentro de su propia política
-- también (54001). Solución en dos capas, sin recursión:
--   1. `privado.empresa_gestion_actual()` (owner `propietario_rpc`) devuelve la
--      empresa del llamador si es dueño o encargado activo. Lo alcanza sólo la
--      política vigente de `propietario_rpc` sobre `perfiles`.
--   2. La vista `privado.perfiles_empresa_gestion` (owner `lector_perfiles_rpc`)
--      lee `perfiles` bajo la política `perfiles_select_empresa_lector`, que
--      filtra por esa empresa. `propietario_rpc` sólo recibe SELECT sobre la
--      vista: no gana ningún privilegio nuevo sobre `perfiles`.
--
-- Lo que NO hace: no cambia las políticas de `authenticated` ni de
-- `propietario_rpc`; no da ningún privilegio a `anon`, `authenticated` ni
-- `service_role`; no crea tablas, RPC, jornadas ni cambios de Stock; no usa
-- FORCE ROW LEVEL SECURITY; no deja CREATE ni USAGE residuales.
--
-- Procedimiento de reversión (NO es una migración): supabase/rollback/.

do $$
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Rol técnico lector_perfiles_rpc
-- ---------------------------------------------------------------------------
-- Los roles son globales del clúster: se crea sólo si no existe. Si ya existe
-- con otros atributos, la migración falla en lugar de corregirlos. No es
-- miembro de ningún rol, no es propietario de tablas ni de funciones y no
-- recibe USAGE ni CREATE en ningún esquema.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'lector_perfiles_rpc') then
    create role lector_perfiles_rpc
      nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  elsif exists (
    select 1 from pg_roles
     where rolname = 'lector_perfiles_rpc'
       and (rolcanlogin or rolsuper or rolcreatedb or rolcreaterole
            or rolbypassrls or rolreplication)
  ) then
    raise exception 'lector_perfiles_rpc existe con atributos no permitidos';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Membresía (patrón O-3)
-- ---------------------------------------------------------------------------
-- CREATE ROLE, ejecutado por postgres (CREATEROLE), genera automáticamente una
-- fila con grantor el superusuario de arranque (ADMIN OPTION, sin SET ni
-- INHERIT). Esta línea agrega la fila de postgres: SET sí, INHERIT no. Se
-- necesita SET para transferirle la vista y para actuar como el rol en pruebas;
-- no se hereda ningún privilegio.
grant lector_perfiles_rpc to postgres with inherit false, set true;

-- ---------------------------------------------------------------------------
-- 3. Único privilegio del rol: cuatro columnas de perfiles
-- ---------------------------------------------------------------------------
-- Sin `usuario`, `nombre` ni `creado_en`; sin INSERT/UPDATE/DELETE.
grant select (usuario_id, empresa_id, rol, activo)
  on table public.perfiles to lector_perfiles_rpc;

-- ---------------------------------------------------------------------------
-- 4. Capa 1: privado.empresa_gestion_actual()
-- ---------------------------------------------------------------------------
-- Empresa del llamador si es dueño o encargado activo; NULL en cualquier otro
-- caso (vendedor, perfil inactivo, sin perfil, sin `sub`). No tiene parámetros
-- y no deriva empresa ni rol del JWT: sólo de `perfiles` (P5–P7). Por ser
-- SECURITY DEFINER y tener `proconfig`, el planificador no la expande en línea.
-- Corre como propietario_rpc, a quien sólo se le aplica la política vigente
-- `perfiles_select_propio_propietario_rpc` (fila propia).
create function privado.empresa_gestion_actual()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.empresa_id
    from public.perfiles p
   where p.usuario_id = privado.usuario_actual()
     and p.activo
     and p.rol in ('dueno', 'encargado')
$$;

-- CREATE sólo mientras se transfiere la propiedad; se revoca de inmediato.
grant create on schema privado to propietario_rpc;
alter function privado.empresa_gestion_actual() owner to propietario_rpc;
revoke create on schema privado from propietario_rpc;

-- Sin INHERIT, postgres sólo actúa como owner tras SET ROLE (sin él, REVOKE no
-- revoca nada y sólo emite un WARNING).
set role propietario_rpc;
revoke all on function privado.empresa_gestion_actual()
  from public, anon, authenticated, service_role;
grant execute on function privado.empresa_gestion_actual() to propietario_rpc;
reset role;

-- ---------------------------------------------------------------------------
-- 5. Capa 2: vista privado.perfiles_empresa_gestion
-- ---------------------------------------------------------------------------
-- Propiedad de lector_perfiles_rpc, así que la RLS de `perfiles` se le aplica
-- a ese rol (no es el owner de la tabla ni tiene BYPASSRLS). Vive en `privado`,
-- que no está expuesto por la Data API.
create view privado.perfiles_empresa_gestion
  with (security_invoker = false, security_barrier = true)
as
select p.usuario_id, p.empresa_id, p.rol, p.activo
  from public.perfiles p;

revoke all on table privado.perfiles_empresa_gestion
  from public, anon, authenticated, service_role;
grant select on table privado.perfiles_empresa_gestion to propietario_rpc;

-- Sin CREATE temporal, ALTER ... OWNER falla con 42501.
grant create on schema privado to lector_perfiles_rpc;
alter view privado.perfiles_empresa_gestion owner to lector_perfiles_rpc;
revoke create on schema privado from lector_perfiles_rpc;

-- ---------------------------------------------------------------------------
-- 6. Política de lector_perfiles_rpc sobre perfiles
-- ---------------------------------------------------------------------------
-- Sólo perfiles de la empresa del llamador. Llamador no gestor, inactivo, sin
-- perfil o sin `sub` ⇒ el helper devuelve NULL ⇒ 0 filas. El EXECUTE del
-- helper se verifica contra el usuario que consulta (propietario_rpc), no
-- contra el dueño de la vista: por eso lector_perfiles_rpc no recibe EXECUTE.
-- Si alguien lee `perfiles` como lector_perfiles_rpc, la consulta falla
-- cerrada con 42501 y no entra en recursión.
create policy perfiles_select_empresa_lector
  on public.perfiles
  for select
  to lector_perfiles_rpc
  using (empresa_id = (select privado.empresa_gestion_actual()));

-- ---------------------------------------------------------------------------
-- 7. Verificación fail-closed
-- ---------------------------------------------------------------------------
-- Aborta la migración si algo de lo anterior no quedó exactamente como se
-- aprobó o si quedó algún privilegio transitorio.
do $$
declare
  v_vista regclass := 'privado.perfiles_empresa_gestion'::regclass;
  v_helper regprocedure := 'privado.empresa_gestion_actual()'::regprocedure;
  v_rol text;
begin
  -- Sin privilegios de esquema residuales.
  if has_schema_privilege('lector_perfiles_rpc', 'privado', 'CREATE')
     or has_schema_privilege('lector_perfiles_rpc', 'privado', 'USAGE')
     or has_schema_privilege('lector_perfiles_rpc', 'public', 'CREATE')
     or has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
     or has_schema_privilege('propietario_rpc', 'public', 'CREATE')
     or exists (select 1 from pg_namespace n, aclexplode(n.nspacl) a
                 where a.grantee = 'lector_perfiles_rpc'::regrole) then
    raise exception 'D-2: privilegios de esquema residuales o no aprobados';
  end if;

  -- Atributos del rol.
  if not exists (
       select 1 from pg_roles
        where rolname = 'lector_perfiles_rpc'
          and not (rolcanlogin or rolsuper or rolcreatedb or rolcreaterole
                   or rolreplication or rolbypassrls)) then
    raise exception 'D-2: atributos de lector_perfiles_rpc fuera de lo aprobado';
  end if;

  -- Vista: owner, opciones y ACL exactos (owner + SELECT de propietario_rpc).
  if not exists (
       select 1 from pg_class c
        where c.oid = v_vista and c.relkind = 'v'
          and c.relowner = 'lector_perfiles_rpc'::regrole
          and c.reloptions @> array['security_barrier=true', 'security_invoker=false'])
     or coalesce((select array_agg(a.grantee::regrole::text || ':' || a.privilege_type
                                   order by a.grantee::regrole::text, a.privilege_type)
                    from pg_class c, aclexplode(c.relacl) a
                   where c.oid = v_vista and a.grantee <> c.relowner),
                 array[]::text[])
        <> array['propietario_rpc:SELECT'] then
    raise exception 'D-2: la vista no quedó con el owner, las opciones o la ACL aprobados';
  end if;

  -- Helper: SECURITY DEFINER, STABLE, search_path vacío, sin parámetros,
  -- owner propietario_rpc, ACL exacta y sin sobrecargas.
  if not exists (
       select 1 from pg_proc p
        where p.oid = v_helper
          and p.prosecdef and p.provolatile = 's' and p.pronargs = 0
          and p.proowner = 'propietario_rpc'::regrole
          and p.prorettype = 'uuid'::regtype
          and p.proconfig @> array['search_path=""']
          and p.proacl is not null)
     or (select array_agg(distinct a.grantee::regrole::text)
           from pg_proc p, aclexplode(p.proacl) a where p.oid = v_helper)
        <> array['propietario_rpc']
     or (select count(*) from pg_proc
          where pronamespace = 'privado'::regnamespace
            and proname = 'empresa_gestion_actual') <> 1 then
    raise exception 'D-2: el helper no quedó con los atributos o la ACL aprobados';
  end if;

  -- Membresía: exactamente dos filas (ADMIN automática del superusuario de
  -- arranque; postgres con SET sin INHERIT) y el rol no es miembro de nadie.
  if (select count(*) from pg_auth_members
       where roleid = 'lector_perfiles_rpc'::regrole) <> 2
     or not exists (
       select 1 from pg_auth_members
        where roleid = 'lector_perfiles_rpc'::regrole
          and member = 'postgres'::regrole and grantor = 'postgres'::regrole
          and not admin_option and not inherit_option and set_option)
     or not exists (
       select 1 from pg_auth_members am join pg_roles g on g.oid = am.grantor
        where am.roleid = 'lector_perfiles_rpc'::regrole
          and am.member = 'postgres'::regrole and g.rolsuper
          and am.admin_option and not am.inherit_option and not am.set_option)
     or exists (
       select 1 from pg_auth_members
        where roleid = 'lector_perfiles_rpc'::regrole and inherit_option)
     or exists (
       select 1 from pg_auth_members
        where member = 'lector_perfiles_rpc'::regrole)
     or not pg_has_role('postgres', 'lector_perfiles_rpc', 'SET')
     or pg_has_role('postgres', 'lector_perfiles_rpc', 'USAGE') then
    raise exception 'D-2: la membresía de lector_perfiles_rpc no quedó en SET true / INHERIT false';
  end if;

  foreach v_rol in array array['anon', 'authenticated', 'authenticator', 'service_role', 'propietario_rpc'] loop
    if exists (select 1 from pg_roles where rolname = v_rol)
       and (pg_has_role(v_rol, 'lector_perfiles_rpc', 'SET')
            or pg_has_role(v_rol, 'lector_perfiles_rpc', 'USAGE')) then
      raise exception 'D-2: % puede hacer SET ROLE o heredar lector_perfiles_rpc', v_rol;
    end if;
  end loop;

  -- Propiedad: una sola relación (la vista) y ninguna función.
  if (select count(*) from pg_class where relowner = 'lector_perfiles_rpc'::regrole) <> 1
     or exists (select 1 from pg_proc where proowner = 'lector_perfiles_rpc'::regrole) then
    raise exception 'D-2: lector_perfiles_rpc debe ser dueño sólo de la vista';
  end if;

  -- Políticas de perfiles: las dos previas sin cambio y una sola nueva; ninguna
  -- de escritura; sin FORCE.
  if array(select policyname || ':' || cmd || ':' || roles::text
             from pg_policies
            where schemaname = 'public' and tablename = 'perfiles'
            order by policyname)
     <> array['perfiles_select_empresa_lector:SELECT:{lector_perfiles_rpc}',
              'perfiles_select_propio:SELECT:{authenticated}',
              'perfiles_select_propio_propietario_rpc:SELECT:{propietario_rpc}'] then
    raise exception 'D-2: las políticas de perfiles no coinciden con las aprobadas';
  end if;

  if not exists (select 1 from pg_class
                  where oid = 'public.perfiles'::regclass
                    and relrowsecurity and not relforcerowsecurity) then
    raise exception 'D-2: perfiles debe tener RLS habilitada y sin FORCE';
  end if;

  -- Sin acceso nuevo para los roles de la Data API sobre la vista y el helper.
  if has_table_privilege('anon', v_vista, 'SELECT, INSERT, UPDATE, DELETE')
     or has_table_privilege('authenticated', v_vista, 'SELECT, INSERT, UPDATE, DELETE')
     or has_table_privilege('service_role', v_vista, 'SELECT, INSERT, UPDATE, DELETE')
     or has_function_privilege('anon', v_helper, 'EXECUTE')
     or has_function_privilege('authenticated', v_helper, 'EXECUTE')
     or has_function_privilege('service_role', v_helper, 'EXECUTE') then
    raise exception 'D-2: anon, authenticated o service_role tienen acceso a la vista o al helper';
  end if;
end $$;
