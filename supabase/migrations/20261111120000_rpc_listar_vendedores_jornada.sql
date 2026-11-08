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
-- 0b. Contrato aprobado de D-2 (precheck; H-01)
-- ---------------------------------------------------------------------------
-- E-PL1 depende de las invariantes aprobadas de D-2 (ADR-001 §18.4.2.1): si D-2
-- las perdió (drift), la migración aborta sin cambios y ANTES de cualquier grant o
-- cambio de la vista. Copia literal de la sección 1b de 20261030120000_jornadas_esquema.sql
-- (el contrato de cuatro columnas vigente antes de E-PL1); esa migración no se edita. El bloque siguiente es
-- una copia literal de «7. Verificación fail-closed» de
-- supabase/migrations/20261029233000_lector_perfiles_rpc.sql (líneas 155-281).
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

-- Complemento: invariantes de D-2 que fijan las pruebas P2–P5 de
-- supabase/tests/lector_perfiles_rpc.test.sql y que el bloque anterior no
-- verifica (privilegios por columna del rol, ningún privilegio sobre otras
-- relaciones, propiedad de esquemas, lenguaje y EXECUTE exacto del helper,
-- columnas de la vista y condición de la política). Traducción literal de esas
-- aserciones.
do $$
begin
  -- P2: privilegios efectivos del rol sobre perfiles: SELECT por columna en las
  -- cuatro columnas aprobadas y nada más.
  if not coalesce((select bool_and(has_column_privilege('lector_perfiles_rpc', 'public.perfiles', c, 'SELECT'))
                     from unnest(array['usuario_id', 'empresa_id', 'rol', 'activo']) c), false)
     or exists (select 1 from unnest(array['usuario', 'nombre', 'creado_en']) c
                 where has_column_privilege('lector_perfiles_rpc', 'public.perfiles', c, 'SELECT'))
     or has_table_privilege('lector_perfiles_rpc', 'public.perfiles',
          'select, insert, update, delete, truncate, references, trigger')
     or has_any_column_privilege('lector_perfiles_rpc', 'public.perfiles',
          'insert, update, references') then
    raise exception 'D-2 (P2): los privilegios de lector_perfiles_rpc sobre perfiles no son sólo SELECT en sus cuatro columnas';
  end if;

  -- P2: ningún privilegio sobre otras tablas o vistas de public ni privado.
  if exists (
       select 1 from pg_class c
        where c.relnamespace in ('public'::regnamespace, 'privado'::regnamespace)
          and c.relkind in ('r', 'p', 'v', 'm', 'f')
          and c.oid not in ('public.perfiles'::regclass, 'privado.perfiles_empresa_gestion'::regclass)
          and has_any_column_privilege('lector_perfiles_rpc', c.oid,
                'select, insert, update, references')) then
    raise exception 'D-2 (P2): lector_perfiles_rpc tiene privilegios sobre otras tablas o vistas';
  end if;

  -- P2: no es dueño de ningún esquema.
  if exists (select 1 from pg_namespace where nspowner = 'lector_perfiles_rpc'::regrole) then
    raise exception 'D-2 (P2): lector_perfiles_rpc es dueño de un esquema';
  end if;

  -- P3: helper en lenguaje sql, ACL con únicamente EXECUTE de propietario_rpc y
  -- sin EXECUTE para el lector, authenticated, anon, service_role ni postgres.
  if not coalesce((select l.lanname = 'sql'
                     from pg_proc p join pg_language l on l.oid = p.prolang
                    where p.oid = 'privado.empresa_gestion_actual()'::regprocedure), false)
     or array(select a.grantee::regrole::text || ':' || a.privilege_type
                from pg_proc p, aclexplode(p.proacl) a
               where p.oid = 'privado.empresa_gestion_actual()'::regprocedure
               order by 1) <> array['propietario_rpc:EXECUTE']
     or exists (
          select 1 from unnest(array['lector_perfiles_rpc', 'authenticated', 'anon', 'service_role', 'postgres']) r
           where has_function_privilege(r, 'privado.empresa_gestion_actual()', 'EXECUTE')) then
    raise exception 'D-2 (P3): el helper no es SQL, o su ACL/EXECUTE no es el aprobado';
  end if;

  -- P4: la vista expone exactamente usuario_id, empresa_id, rol y activo.
  if array(select attname::text from pg_attribute
            where attrelid = 'privado.perfiles_empresa_gestion'::regclass
              and attnum > 0 and not attisdropped
            order by attnum) <> array['usuario_id', 'empresa_id', 'rol', 'activo'] then
    raise exception 'D-2 (P4): la vista no expone exactamente usuario_id, empresa_id, rol y activo';
  end if;

  -- P5: la política del lector filtra empresa_id con privado.empresa_gestion_actual().
  if not coalesce((select qual ~ 'empresa_gestion_actual' and qual ~ 'empresa_id'
                     from pg_policies
                    where schemaname = 'public' and tablename = 'perfiles'
                      and policyname = 'perfiles_select_empresa_lector'), false) then
    raise exception 'D-2 (P5): la política del lector no filtra empresa_id con privado.empresa_gestion_actual()';
  end if;
end $$;

-- Definiciones completas del helper, la vista y la política contra la migración de D-2
-- (ADR-001 §18.4.2.1): comparación exacta, no por fragmentos.
do $$
begin
  -- Helper: cuerpo exacto de la definición aprobada (20261029233000_lector_perfiles_rpc.sql,
  -- creación del helper; ADR-001 §18.4.2.1, Capa 1). prosrc se guarda tal cual se
  -- escribió (no se deparsea): se normalizan sólo los espacios en blanco, así que la
  -- comparación no depende de la versión de PostgreSQL ni de search_path.
  if btrim(regexp_replace(
       (select prosrc from pg_proc where oid = 'privado.empresa_gestion_actual()'::regprocedure),
       '\s+', ' ', 'g'))
     is distinct from
     'select p.empresa_id from public.perfiles p where p.usuario_id = privado.usuario_actual() and p.activo and p.rol in (''dueno'', ''encargado'')' then
    raise exception 'D-2 (definición): el cuerpo del helper no es el aprobado';
  end if;

  -- Vista: la consulta completa se compara contra una vista de referencia
  -- temporal creada en esta transacción con el SELECT aprobado (Capa 2). Ambas se
  -- deparsean con el mismo servidor y el mismo search_path de la sesión, así que
  -- la igualdad no depende de ninguno de los dos. Se elimina al terminar.
  create temp view d2_ref_vista with (security_invoker = false, security_barrier = true) as
    select p.usuario_id, p.empresa_id, p.rol, p.activo from public.perfiles p;
  if pg_get_viewdef('privado.perfiles_empresa_gestion'::regclass)
     is distinct from pg_get_viewdef('pg_temp.d2_ref_vista'::regclass) then
    raise exception 'D-2 (definición): la consulta de la vista no es la aprobada';
  end if;
  drop view pg_temp.d2_ref_vista;

  -- Política: comando, tipo (PERMISSIVE/RESTRICTIVE), roles, ausencia de WITH
  -- CHECK y condición completa contra una política de referencia temporal con la
  -- cláusula aprobada, sobre una tabla temporal con RLS. Se elimina al terminar.
  create temp table d2_ref_perfiles (empresa_id uuid);
  alter table pg_temp.d2_ref_perfiles enable row level security;
  create policy d2_ref_politica on pg_temp.d2_ref_perfiles
    for select to lector_perfiles_rpc
    using (empresa_id = (select privado.empresa_gestion_actual()));
  if (select row(pg_get_expr(a.polqual, a.polrelid), a.polcmd, a.polpermissive,
                 a.polwithcheck is null,
                 array(select r.rolname::text from pg_roles r where r.oid = any (a.polroles) order by 1))
        from pg_policy a
       where a.polrelid = 'public.perfiles'::regclass and a.polname = 'perfiles_select_empresa_lector')
     is distinct from
     (select row(pg_get_expr(b.polqual, b.polrelid), b.polcmd, b.polpermissive,
                 b.polwithcheck is null,
                 array(select r.rolname::text from pg_roles r where r.oid = any (b.polroles) order by 1))
        from pg_policy b
       where b.polrelid = 'pg_temp.d2_ref_perfiles'::regclass and b.polname = 'd2_ref_politica') then
    raise exception 'D-2 (definición): la política del lector no es la aprobada (condición completa, PERMISSIVE, SELECT, rol)';
  end if;
  drop table pg_temp.d2_ref_perfiles;
end $$;

-- Privilegios por defecto a favor del lector (objetos futuros).
do $$
begin
  -- ALTER DEFAULT PRIVILEGES que le darían al lector privilegios sobre objetos
  -- FUTUROS. Lectura estricta de ADR-001 §18.4.2.1 («su único privilegio es
  -- SELECT (usuario_id, empresa_id, rol, activo) sobre public.perfiles»):
  --   - cualquier ACL por defecto cuyo destinatario sea el propio lector, creada
  --     por cualquier otro rol, en cualquier esquema o globalmente;
  --   - cualquier ACL por defecto a favor de PUBLIC sobre tablas ('r'),
  --     secuencias ('S') o esquemas ('n'), porque PUBLIC incluye al lector.
  -- Quedan fuera, a propósito: el EXECUTE de PUBLIC sobre funciones y el USAGE
  -- sobre tipos (valores base de PostgreSQL; el de funciones lo gobierna el
  -- hardening de grants), las ACL por defecto de otros roles (Data API, etc.) y las
  -- filas cuyo creador es el propio lector (entrada de su propio owner). El lector
  -- no es miembro de ningún rol (bloque anterior), así que no hereda ACL por
  -- defecto de terceros.
  if exists (
       select 1
         from pg_default_acl d, aclexplode(d.defaclacl) a
        where (a.grantee = 'lector_perfiles_rpc'::regrole
               and d.defaclrole <> 'lector_perfiles_rpc'::regrole)
           or (a.grantee = 0 and d.defaclobjtype in ('r', 'S', 'n'))) then
    raise exception 'D-2 (privilegios por defecto): una ACL por defecto otorga privilegios a lector_perfiles_rpc o a PUBLIC sobre tablas, secuencias o esquemas futuros';
  end if;
end $$;

-- Políticas previas de perfiles (condición completa).
do $$
begin
  -- Las dos políticas previas de perfiles (sin cambios desde su creación): el
  -- bloque A sólo comprueba su nombre, comando y rol. Aquí se compara la
  -- condición completa, el tipo (PERMISSIVE/RESTRICTIVE) y la ausencia de WITH
  -- CHECK contra políticas de referencia temporales con el USING aprobado:
  --   - perfiles_select_propio: 20261022120000_auth_base_empresas_perfiles.sql:96-100;
  --   - perfiles_select_propio_propietario_rpc: 20261023140000_catalogo_productos.sql:241-245.
  -- Ambas leen sólo la fila propia (ADR-001 §18.4.2.1, caso P9). Misma técnica que
  -- el bloque anterior: la comparación no depende del search_path ni de la versión.
  create temp table d2_ref_perfiles_previas (usuario_id uuid);
  alter table pg_temp.d2_ref_perfiles_previas enable row level security;
  create policy d2_ref_propio on pg_temp.d2_ref_perfiles_previas
    for select to authenticated
    using (usuario_id = (select auth.uid()));
  create policy d2_ref_propio_rpc on pg_temp.d2_ref_perfiles_previas
    for select to propietario_rpc
    using (usuario_id = (select privado.usuario_actual()));
  if (select row(pg_get_expr(a.polqual, a.polrelid), a.polcmd, a.polpermissive,
                 a.polwithcheck is null,
                 array(select r.rolname::text from pg_roles r where r.oid = any (a.polroles) order by 1))
        from pg_policy a
       where a.polrelid = 'public.perfiles'::regclass and a.polname = 'perfiles_select_propio')
     is distinct from
     (select row(pg_get_expr(b.polqual, b.polrelid), b.polcmd, b.polpermissive,
                 b.polwithcheck is null,
                 array(select r.rolname::text from pg_roles r where r.oid = any (b.polroles) order by 1))
        from pg_policy b
       where b.polrelid = 'pg_temp.d2_ref_perfiles_previas'::regclass and b.polname = 'd2_ref_propio') then
    raise exception 'D-2 (definición): la política perfiles_select_propio no es la aprobada';
  end if;
  if (select row(pg_get_expr(a.polqual, a.polrelid), a.polcmd, a.polpermissive,
                 a.polwithcheck is null,
                 array(select r.rolname::text from pg_roles r where r.oid = any (a.polroles) order by 1))
        from pg_policy a
       where a.polrelid = 'public.perfiles'::regclass and a.polname = 'perfiles_select_propio_propietario_rpc')
     is distinct from
     (select row(pg_get_expr(b.polqual, b.polrelid), b.polcmd, b.polpermissive,
                 b.polwithcheck is null,
                 array(select r.rolname::text from pg_roles r where r.oid = any (b.polroles) order by 1))
        from pg_policy b
       where b.polrelid = 'pg_temp.d2_ref_perfiles_previas'::regclass and b.polname = 'd2_ref_propio_rpc') then
    raise exception 'D-2 (definición): la política perfiles_select_propio_propietario_rpc no es la aprobada';
  end if;
  drop table pg_temp.d2_ref_perfiles_previas;
end $$;

-- H-01 (complemento al contrato D-2 copiado): el rol que ejecuta la función
-- (propietario_rpc) también debe conservar sus atributos aprobados, y ninguno de los dos
-- roles técnicos puede tener configuración propia que altere la RLS (por ejemplo
-- `ALTER ROLE ... SET row_security = off`).
do $$
begin
  if not exists (
       select 1 from pg_roles
        where rolname = 'propietario_rpc'
          and not (rolcanlogin or rolsuper or rolcreatedb or rolcreaterole
                   or rolreplication or rolbypassrls)) then
    raise exception 'E-PL1 (precheck): atributos de propietario_rpc fuera de lo aprobado (NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS)';
  end if;

  if exists (
       select 1 from pg_db_role_setting s
        where s.setrole in ('propietario_rpc'::regrole, 'lector_perfiles_rpc'::regrole)) then
    raise exception 'E-PL1 (precheck): propietario_rpc o lector_perfiles_rpc tienen configuración propia (pg_db_role_setting)';
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
-- DEFENSA EN PROFUNDIDAD (H-01): además se compara explícitamente el empresa_id de
-- cada perfil con la empresa del llamador obtenida UNA vez del helper protegido, de
-- modo que un drift de la RLS del lector (política alterada, BYPASSRLS, vista
-- reemplazada) no pueda devolver perfiles de otra empresa. Acá se filtran además
-- sólo activos con los tres roles de ADR-007 §2.3. `nombre` no
-- puede ser nulo ni vacío (NOT NULL y CHECK perfiles_nombre_no_vacio): se devuelve
-- tal como está almacenado.
create function privado.listar_vendedores_jornada()
returns table (usuario_id uuid, nombre text, rol text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_empresa pg_catalog.uuid;  -- tipo calificado: sin referencias resolubles por pg_temp (P7)
begin
  if privado.usuario_actual() is null then
    raise exception using errcode = 'PT401', message = 'jornada_no_autenticado';
  end if;

  v_empresa := privado.empresa_gestion_actual();
  if v_empresa is null then
    raise exception using errcode = 'PT403', message = 'jornada_no_autorizado';
  end if;

  return query
    select v.usuario_id, v.nombre, v.rol
      from privado.perfiles_empresa_gestion v
     where v.empresa_id = v_empresa
       and v.activo
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
