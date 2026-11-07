-- E-PL1 (ADR-001 §18.4.2.2): lectura protegida de vendedores para abrir jornadas
-- (Blueprint §7.5, §9; ADR-007 §2.3) y ampliación expresa de D-2 de cuatro a cinco
-- columnas (`nombre`).
--
-- Decisión humana: E-PL1 (A-1, A-2, A-3, A-4) APROBADA PARA VALIDACIÓN CONTROLADA
-- (local/staging). Prohibido aplicar en producción. No autoriza staging ni producción.
--
-- Qué hace:
--   1. Amplía `lector_perfiles_rpc` con `SELECT (nombre)` sobre `public.perfiles` y
--      reemplaza `privado.perfiles_empresa_gestion` para exponer
--      (usuario_id, empresa_id, rol, activo, nombre). Todo en UN bloque DO (atómico
--      aunque el ejecutor de migraciones no envuelva el archivo en una transacción):
--      si algo falla, no queda ningún grant ni privilegio transitorio.
--   2. Crea `privado.listar_vendedores_jornada()` (SECURITY DEFINER, owner
--      `propietario_rpc`) y su fachada `public.listar_vendedores_jornada()`
--      (SECURITY INVOKER, owner `postgres`). Sin parámetros y sin sobrecargas.
--
-- Qué NO hace: no cambia ninguna política de RLS (`perfiles_select_propio`,
-- `perfiles_select_propio_propietario_rpc`, `perfiles_select_empresa_lector`), no da
-- privilegios nuevos a `anon`, `authenticated` ni `service_role` sobre `perfiles` ni
-- sobre la vista, no concede `USAGE` a `lector_perfiles_rpc` (sólo un `CREATE`
-- transitorio, revocado en el mismo bloque), no expone `usuario` ni `creado_en`, no
-- crea operaciones, claves de idempotencia ni bloqueos (lectura pura), y no edita
-- migraciones anteriores (ADR-009: sólo hacia adelante). El precheck de cuatro
-- columnas de 20261030120000 corre antes de esta migración y no se rompe.
--
-- Hechos verificados en el laboratorio local (imagen supabase/postgres 17.11):
--   - `CREATE OR REPLACE VIEW` por `lector_perfiles_rpc` exige `CREATE` sobre
--     `privado` (con sólo `USAGE` falla con 42501) y descarta las opciones de la
--     vista si se omite `WITH (...)`: por eso se escriben explícitas.
--   - Crear la vista no valida el privilegio de columna sobre `perfiles`; lo valida
--     la consulta. Por eso el `GRANT SELECT (nombre)` va primero y la verificación
--     final lo comprueba.
--   - `authenticated` necesita `EXECUTE` sobre la función privada y `USAGE` sobre
--     `privado` para que la fachada SECURITY INVOKER funcione; la barrera de
--     exposición es que `privado` no está en `[api] schemas` de la Data API.
--
-- Orden de la consulta: `ORDER BY nombre COLLATE "C", usuario_id` (A-4).

do $$
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;

  if to_regclass('public.perfiles') is null
     or to_regclass('privado.perfiles_empresa_gestion') is null
     or to_regprocedure('privado.empresa_gestion_actual()') is null
     or to_regprocedure('privado.usuario_actual()') is null then
    raise exception 'E-PL1: falta D-2 (perfiles, la vista de perfiles o sus helpers)';
  end if;

  if not exists (select 1 from pg_roles where rolname = 'propietario_rpc')
     or not exists (select 1 from pg_roles where rolname = 'lector_perfiles_rpc') then
    raise exception 'E-PL1: faltan los roles propietario_rpc o lector_perfiles_rpc';
  end if;

  -- La migración parte del estado D-2 de cuatro columnas: si la vista ya expone
  -- otra cosa o el lector ya tiene `nombre`, hay drift y se aborta sin cambios.
  if array(select attname::text from pg_attribute
            where attrelid = 'privado.perfiles_empresa_gestion'::regclass
              and attnum > 0 and not attisdropped
            order by attnum) <> array['usuario_id', 'empresa_id', 'rol', 'activo']
     or has_column_privilege('lector_perfiles_rpc', 'public.perfiles', 'nombre', 'SELECT') then
    raise exception 'E-PL1: la vista o el grant del lector no están en el estado D-2 de cuatro columnas';
  end if;

  if exists (select 1 from pg_proc
              where proname = 'listar_vendedores_jornada'
                and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)) then
    raise exception 'E-PL1: listar_vendedores_jornada ya existe';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. D-2 de cuatro a cinco columnas (E-PL1.4 y E-PL1.5), en UN bloque atómico
-- ---------------------------------------------------------------------------
do $$
declare
  v_vista regclass := 'privado.perfiles_empresa_gestion'::regclass;
begin
  -- 1. Grant de columna. Antes que la vista: la consulta (no la creación) lo exige.
  grant select (nombre) on table public.perfiles to lector_perfiles_rpc;

  -- 2. CREATE transitorio (no USAGE): permite al dueño de la vista reemplazarla.
  grant create on schema privado to lector_perfiles_rpc;

  -- 3-5. Reemplazo de la vista como su dueño. WITH explícito: sin él se pierden
  -- security_barrier y security_invoker=false.
  execute 'set role lector_perfiles_rpc';
  create or replace view privado.perfiles_empresa_gestion
    with (security_invoker = false, security_barrier = true)
  as
  select p.usuario_id, p.empresa_id, p.rol, p.activo, p.nombre
    from public.perfiles p;
  execute 'reset role';

  -- 6. Se revoca el CREATE transitorio.
  revoke create on schema privado from lector_perfiles_rpc;

  -- 7. Verificación fail-closed (si falla, el bloque entero se deshace).
  if has_schema_privilege('lector_perfiles_rpc', 'privado', 'CREATE')
     or has_schema_privilege('lector_perfiles_rpc', 'privado', 'USAGE')
     or has_schema_privilege('lector_perfiles_rpc', 'public', 'CREATE')
     or has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
     or has_schema_privilege('propietario_rpc', 'public', 'CREATE')
     or exists (select 1 from pg_namespace n, aclexplode(n.nspacl) a
                 where a.grantee = 'lector_perfiles_rpc'::regrole) then
    raise exception 'E-PL1: privilegios de esquema residuales o no aprobados';
  end if;

  if not exists (
       select 1 from pg_class c
        where c.oid = v_vista and c.relkind = 'v'
          and c.relowner = 'lector_perfiles_rpc'::regrole
          and c.reloptions @> array['security_barrier=true', 'security_invoker=false']
          and cardinality(c.reloptions) = 2) then
    raise exception 'E-PL1: la vista no quedó con el owner o las opciones aprobados';
  end if;

  if array(select attname::text from pg_attribute
            where attrelid = v_vista and attnum > 0 and not attisdropped
            order by attnum)
     <> array['usuario_id', 'empresa_id', 'rol', 'activo', 'nombre'] then
    raise exception 'E-PL1: la vista no expone exactamente usuario_id, empresa_id, rol, activo y nombre';
  end if;

  if coalesce((select array_agg(a.grantee::regrole::text || ':' || a.privilege_type
                                order by a.grantee::regrole::text, a.privilege_type)
                 from pg_class c, aclexplode(c.relacl) a
                where c.oid = v_vista and a.grantee <> c.relowner),
              array[]::text[]) <> array['propietario_rpc:SELECT'] then
    raise exception 'E-PL1: la ACL de la vista no es la aprobada';
  end if;

  if (select count(*) from pg_class where relowner = 'lector_perfiles_rpc'::regrole) <> 1
     or exists (select 1 from pg_proc where proowner = 'lector_perfiles_rpc'::regrole) then
    raise exception 'E-PL1: lector_perfiles_rpc debe ser dueño sólo de la vista';
  end if;

  -- Las cinco columnas con SELECT, exactamente; sin escritura ni referencias.
  if array(select a.attname::text from pg_attribute a
            where a.attrelid = 'public.perfiles'::regclass and a.attnum > 0 and not a.attisdropped
              and has_column_privilege('lector_perfiles_rpc', 'public.perfiles', a.attname, 'SELECT')
            order by a.attnum)
     <> array['usuario_id', 'empresa_id', 'nombre', 'rol', 'activo']
     or has_table_privilege('lector_perfiles_rpc', 'public.perfiles',
          'select, insert, update, delete, truncate, references, trigger')
     or has_any_column_privilege('lector_perfiles_rpc', 'public.perfiles',
          'insert, update, references') then
    raise exception 'E-PL1: los privilegios del lector sobre perfiles no son sólo SELECT en sus cinco columnas';
  end if;

  -- Ningún privilegio del lector sobre otras tablas o vistas de public ni privado.
  if exists (
       select 1 from pg_class c
        where c.relnamespace in ('public'::regnamespace, 'privado'::regnamespace)
          and c.relkind in ('r', 'p', 'v', 'm', 'f')
          and c.oid not in ('public.perfiles'::regclass, v_vista)
          and has_any_column_privilege('lector_perfiles_rpc', c.oid,
                'select, insert, update, references')) then
    raise exception 'E-PL1: lector_perfiles_rpc tiene privilegios sobre otras tablas o vistas';
  end if;

  -- Ningún acceso nuevo para los roles de la Data API sobre la vista.
  if has_table_privilege('anon', v_vista, 'SELECT, INSERT, UPDATE, DELETE')
     or has_table_privilege('authenticated', v_vista, 'SELECT, INSERT, UPDATE, DELETE')
     or has_table_privilege('service_role', v_vista, 'SELECT, INSERT, UPDATE, DELETE')
     or has_column_privilege('anon', v_vista, 'nombre', 'SELECT')
     or has_column_privilege('authenticated', v_vista, 'nombre', 'SELECT')
     or has_column_privilege('service_role', v_vista, 'nombre', 'SELECT') then
    raise exception 'E-PL1: anon, authenticated o service_role tienen acceso a la vista';
  end if;

  -- Las políticas de perfiles no cambian (tres, sin escritura) y sin FORCE.
  if array(select policyname || ':' || cmd || ':' || roles::text
             from pg_policies
            where schemaname = 'public' and tablename = 'perfiles'
            order by policyname)
     <> array['perfiles_select_empresa_lector:SELECT:{lector_perfiles_rpc}',
              'perfiles_select_propio:SELECT:{authenticated}',
              'perfiles_select_propio_propietario_rpc:SELECT:{propietario_rpc}'] then
    raise exception 'E-PL1: las políticas de perfiles cambiaron';
  end if;

  if not exists (select 1 from pg_class
                  where oid = 'public.perfiles'::regclass
                    and relrowsecurity and not relforcerowsecurity) then
    raise exception 'E-PL1: perfiles debe tener RLS habilitada y sin FORCE';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Implementación privilegiada (SECURITY DEFINER, owner propietario_rpc)
-- ---------------------------------------------------------------------------
-- Lectura pura. Orden de comprobaciones: identidad (PT401), luego autorización
-- (PT403). `privado.empresa_gestion_actual()` devuelve NULL si el llamador no es
-- dueño o encargado activo (vendedor, sin perfil, perfil inactivo). La vista ya
-- filtra por la empresa del llamador (política perfiles_select_empresa_lector);
-- acá se filtran sólo activos con los tres roles de ADR-007 §2.3. `nombre` no
-- puede ser nulo ni vacío (NOT NULL y CHECK perfiles_nombre_no_vacio): se devuelve
-- tal como está almacenado.
create function privado.listar_vendedores_jornada()
returns table (usuario_id uuid, nombre text, rol text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if privado.usuario_actual() is null then
    raise exception using errcode = 'PT401', message = 'jornada_no_autenticado';
  end if;

  if privado.empresa_gestion_actual() is null then
    raise exception using errcode = 'PT403', message = 'jornada_no_autorizado';
  end if;

  return query
    select v.usuario_id, v.nombre, v.rol
      from privado.perfiles_empresa_gestion v
     where v.activo
       and v.rol in ('dueno', 'encargado', 'vendedor_piloto')
     order by v.nombre collate "C", v.usuario_id;
end
$$;

-- CREATE sólo mientras se transfiere la propiedad; se revoca de inmediato.
grant create on schema privado to propietario_rpc;
alter function privado.listar_vendedores_jornada() owner to propietario_rpc;
revoke create on schema privado from propietario_rpc;

-- Sin INHERIT, postgres sólo actúa como owner tras SET ROLE (sin él, REVOKE no
-- revoca nada y sólo emite un WARNING).
set role propietario_rpc;
revoke all on function privado.listar_vendedores_jornada()
  from public, anon, authenticated, service_role;
grant execute on function privado.listar_vendedores_jornada() to authenticated;
reset role;

-- ---------------------------------------------------------------------------
-- 3. Fachada expuesta (SECURITY INVOKER, owner postgres): sólo delega
-- ---------------------------------------------------------------------------
create function public.listar_vendedores_jornada()
returns table (usuario_id uuid, nombre text, rol text)
language sql
stable
security invoker
set search_path = ''
as $$
  select r.usuario_id, r.nombre, r.rol
    from privado.listar_vendedores_jornada() r
$$;

revoke all on function public.listar_vendedores_jornada()
  from public, anon, authenticated, service_role;
grant execute on function public.listar_vendedores_jornada() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Verificación fail-closed de las dos funciones
-- ---------------------------------------------------------------------------
do $$
declare
  v_priv regprocedure := 'privado.listar_vendedores_jornada()'::regprocedure;
  v_pub regprocedure := 'public.listar_vendedores_jornada()'::regprocedure;
  v_rol text;
begin
  -- Implementación privada: atributos exactos y sin sobrecargas.
  if not exists (
       select 1 from pg_proc p join pg_language l on l.oid = p.prolang
        where p.oid = v_priv and l.lanname = 'plpgsql'
          and p.prosecdef and p.provolatile = 's' and p.pronargs = 0 and p.proretset
          and p.proowner = 'propietario_rpc'::regrole
          and p.proconfig @> array['search_path=""'] and cardinality(p.proconfig) = 1
          and p.proargnames = array['usuario_id', 'nombre', 'rol']
          and p.proallargtypes = array['uuid'::regtype::oid, 'text'::regtype::oid, 'text'::regtype::oid]
          and p.proargmodes = array['t', 't', 't']::"char"[])
     or (select count(*) from pg_proc
          where pronamespace = 'privado'::regnamespace
            and proname = 'listar_vendedores_jornada') <> 1 then
    raise exception 'E-PL1: la implementación privada no quedó con los atributos aprobados';
  end if;

  -- Fachada: SECURITY INVOKER, owner postgres, sin sobrecargas.
  if not exists (
       select 1 from pg_proc p join pg_language l on l.oid = p.prolang
        where p.oid = v_pub and l.lanname = 'sql'
          and not p.prosecdef and p.provolatile = 's' and p.pronargs = 0 and p.proretset
          and p.proowner = 'postgres'::regrole
          and p.proconfig @> array['search_path=""'] and cardinality(p.proconfig) = 1
          and p.proargnames = array['usuario_id', 'nombre', 'rol']
          and p.proallargtypes = array['uuid'::regtype::oid, 'text'::regtype::oid, 'text'::regtype::oid]
          and p.proargmodes = array['t', 't', 't']::"char"[])
     or (select count(*) from pg_proc
          where pronamespace = 'public'::regnamespace
            and proname = 'listar_vendedores_jornada') <> 1 then
    raise exception 'E-PL1: la fachada no quedó con los atributos aprobados';
  end if;

  -- ACL exactas, sin entrada PUBLIC.
  if array(select a.grantee::regrole::text || ':' || a.privilege_type
             from pg_proc p, aclexplode(p.proacl) a where p.oid = v_priv order by 1)
     <> array['authenticated:EXECUTE', 'propietario_rpc:EXECUTE']
     or array(select a.grantee::regrole::text || ':' || a.privilege_type
                from pg_proc p, aclexplode(p.proacl) a where p.oid = v_pub order by 1)
     <> array['authenticated:EXECUTE', 'postgres:EXECUTE'] then
    raise exception 'E-PL1: las ACL de las funciones no son las aprobadas';
  end if;

  -- Privilegios efectivos (no sólo ACL).
  foreach v_rol in array array['anon', 'service_role', 'lector_perfiles_rpc'] loop
    if has_function_privilege(v_rol, v_priv, 'EXECUTE')
       or has_function_privilege(v_rol, v_pub, 'EXECUTE')
       or has_schema_privilege(v_rol, 'privado', 'USAGE') then
      raise exception 'E-PL1: % tiene EXECUTE o USAGE sobre privado que no corresponden', v_rol;
    end if;
  end loop;

  if not has_function_privilege('authenticated', v_priv, 'EXECUTE')
     or not has_function_privilege('authenticated', v_pub, 'EXECUTE')
     or not has_schema_privilege('authenticated', 'privado', 'USAGE')
     or has_function_privilege('propietario_rpc', v_pub, 'EXECUTE')
     or not has_function_privilege('propietario_rpc', v_priv, 'EXECUTE') then
    raise exception 'E-PL1: los privilegios efectivos de authenticated o propietario_rpc no son los aprobados';
  end if;

  -- Sin CREATE residual transitorio.
  if has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
     or has_schema_privilege('propietario_rpc', 'public', 'CREATE')
     or has_schema_privilege('lector_perfiles_rpc', 'privado', 'CREATE') then
    raise exception 'E-PL1: CREATE residual sobre privado o public';
  end if;
end $$;
