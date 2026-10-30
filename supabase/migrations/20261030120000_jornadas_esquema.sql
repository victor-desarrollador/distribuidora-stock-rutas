-- D-1 — Esquema de jornadas y carga de camiones (Blueprint §7.4, §7.5, §8,
-- §12; ADR-001 §18.4.1, §18.4.2, §18.4.8 y §18.4.10; ADR-007 §2, §5 y §7).
--
-- Alcance (decisión humana: D-1 a D-9 del preámbulo de implementación):
--   - Sólo esquema: public.jornadas y sus dos historiales append-only
--     (public.reasignaciones_vendedor y public.correcciones_jornada), más la
--     extensión mínima de public.operaciones y public.movimientos_stock
--     (columna jornada_id, tipos nuevos, CHECK, FK, UNIQUE, índices, grants y
--     policies de INSERT de propietario_rpc).
--   - Sin funciones, roles, esquemas ni RPC. Las seis RPC de ADR-007 y el
--     arnés de concurrencia son tareas posteriores.
--   - D7 (movimientos_stock_operacion_unitaria_unica) NO se modifica: su
--     predicado ya excluye carga y descarga, así que una carga puede tener
--     varios movimientos (uno por producto, índice
--     movimientos_stock_operacion_producto_unica).
--   - Sin índice único parcial de jornadas sin cerrar por camión: no está en
--     el contrato aprobado (D-4). "Camión sin otra jornada sin cerrar"
--     (ADR-007 §2.1.5) lo controlan las RPC bajo el advisory del camión
--     (ADR-001 §18.4.5).
--   - jornadas NO es append-only: admite UPDATE de (estado, vendedor_id,
--     fecha, camion_id) sólo para propietario_rpc y sólo dentro de las RPC.
--     Los dos historiales sí son append-only por grants y RLS, sin triggers.
--   - Las columnas futuras de Blueprint §8 (ventas_finalizadas_at,
--     contada_por, cerrada_por, cerrada_at, observaciones) quedan fuera: son
--     de los estados posteriores a en_reparto.
--   - service_role y anon sin privilegios (P11); authenticated sólo SELECT.
--   - D-2 (lector_perfiles_rpc y su vista) no se toca.
--
-- Orden (dependencias reales de PostgreSQL; una FK exige que el destino ya
-- tenga una restricción UNIQUE/PK exacta):
--   1. precheck (1b: contrato completo de D-2); 2. operaciones.jornada_id sin
--   FK; 3. los dos UNIQUE de referencia de operaciones; 4. jornadas;
--   5. operaciones: FK a jornadas, tipos y CHECK; 6. movimientos_stock;
--   7. historiales; 8. grants; 9. policies; 10. verificación final
--   fail-closed; 11. contrato de D-2 otra vez, ya con D-1 aplicado.
-- operaciones.jornada_id es nullable (apertura_jornada nace sin jornada), así
-- que el ciclo operaciones <-> jornadas se resuelve por orden, sin DEFERRABLE.
--
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.
-- Reversión manual: supabase/rollback/20261030120000_jornadas_esquema.rollback.sql

-- ---------------------------------------------------------------------------
-- 1. Precheck fail-closed
-- ---------------------------------------------------------------------------
do $$
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;

  -- D-2 y los roles técnicos deben existir; esta migración no los crea.
  if not exists (select 1 from pg_roles where rolname = 'propietario_rpc')
     or not exists (select 1 from pg_roles where rolname = 'lector_perfiles_rpc')
     or to_regprocedure('privado.empresa_gestion_actual()') is null
     or to_regprocedure('privado.usuario_actual()') is null then
    raise exception 'jornadas: faltan propietario_rpc, lector_perfiles_rpc o sus funciones (D-2)';
  end if;

  -- Los objetos de D-1 no deben existir.
  if to_regclass('public.jornadas') is not null
     or to_regclass('public.reasignaciones_vendedor') is not null
     or to_regclass('public.correcciones_jornada') is not null
     or exists (select 1 from pg_attribute
                 where attrelid in ('public.operaciones'::regclass,
                                    'public.movimientos_stock'::regclass)
                   and attname = 'jornada_id' and not attisdropped) then
    raise exception 'jornadas: ya existen objetos de D-1';
  end if;

  -- Las restricciones a ampliar deben estar en su forma original (Stock).
  if (select pg_get_constraintdef(oid) from pg_constraint
       where conrelid = 'public.operaciones'::regclass and conname = 'operaciones_tipo_valido')
       is distinct from
       'CHECK ((tipo = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text])))'
     or (select pg_get_constraintdef(oid) from pg_constraint
          where conrelid = 'public.movimientos_stock'::regclass and conname = 'movimientos_stock_tipo_valido')
          is distinct from
          'CHECK ((tipo_movimiento = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text])))'
     or (select pg_get_constraintdef(oid) from pg_constraint
          where conrelid = 'public.movimientos_stock'::regclass and conname = 'movimientos_stock_forma_por_tipo')
          is distinct from
          'CHECK ((((tipo_movimiento = ''ingreso''::text) AND (ubicacion_origen_id IS NULL) AND (ubicacion_destino_id IS NOT NULL)) OR ((tipo_movimiento = ''a_cuarentena''::text) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NOT NULL)) OR ((tipo_movimiento = ''merma''::text) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NULL))))'
     or (select pg_get_constraintdef(oid) from pg_constraint
          where conrelid = 'public.movimientos_stock'::regclass and conname = 'movimientos_stock_motivo_por_tipo')
          is distinct from
          'CHECK ((((tipo_movimiento = ''ingreso''::text) AND (motivo_codigo IS NULL)) OR ((tipo_movimiento = ''a_cuarentena''::text) AND (motivo_codigo IS NULL) AND (motivo IS NOT NULL)) OR ((tipo_movimiento = ''merma''::text) AND (motivo_codigo IS NOT NULL) AND ((motivo_codigo <> ''otro''::text) OR (motivo IS NOT NULL)))))' then
    raise exception 'jornadas: las restricciones de operaciones o movimientos_stock no están en su forma original';
  end if;

  -- D7 debe seguir intacto (esta migración no lo toca).
  if to_regclass('public.movimientos_stock_operacion_unitaria_unica') is null then
    raise exception 'jornadas: falta el índice D7 movimientos_stock_operacion_unitaria_unica';
  end if;

  -- Las policies a ampliar deben existir.
  if (select count(*) from pg_policies
       where schemaname = 'public'
         and policyname in ('operaciones_insert_propietario_rpc',
                            'movimientos_stock_insert_propietario_rpc')) <> 2 then
    raise exception 'jornadas: faltan las policies de INSERT de propietario_rpc';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1b. Contrato aprobado de D-2 (precheck)
-- ---------------------------------------------------------------------------
-- D-1 depende de las invariantes aprobadas de D-2 (ADR-001 §18.4.2.1): si D-2
-- las perdió (drift), la migración aborta sin cambios. El bloque siguiente es
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

-- ---------------------------------------------------------------------------
-- 2. operaciones.jornada_id (sin FK todavía: jornadas aún no existe)
-- ---------------------------------------------------------------------------
alter table public.operaciones add column jornada_id uuid;

comment on column public.operaciones.jornada_id is
  'Jornada a la que pertenece la operación (ADR-001 §18.4.1). NULL para ingreso, a_cuarentena, merma y apertura_jornada; NOT NULL para los demás tipos de jornada.';

-- ---------------------------------------------------------------------------
-- 3. Destinos de las FK de referencia (ADR-001 §18.4.1, §18.4.8)
-- ---------------------------------------------------------------------------
alter table public.operaciones
  add constraint operaciones_referencia_apertura
    unique (empresa_id, id, tipo, actor_id);

alter table public.operaciones
  add constraint operaciones_referencia_unica
    unique (empresa_id, id, tipo, actor_id, jornada_id);

-- ---------------------------------------------------------------------------
-- 4. jornadas
-- ---------------------------------------------------------------------------
create table public.jornadas (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  fecha date not null,
  camion_id uuid not null,
  vendedor_id uuid not null,
  estado text not null,
  abierta_por uuid not null,
  operacion_apertura_id uuid not null,
  tipo_operacion_apertura text not null default 'apertura_jornada',
  creado_en timestamptz not null default now(),
  constraint jornadas_pkey primary key (id),
  constraint jornadas_empresa_fk foreign key (empresa_id)
    references public.empresas (id) on delete restrict,
  constraint jornadas_empresa_id_unico unique (empresa_id, id),
  constraint jornadas_camion_fecha_unica unique (empresa_id, camion_id, fecha),
  constraint jornadas_vendedor_fecha_unica unique (empresa_id, vendedor_id, fecha),
  constraint jornadas_operacion_apertura_unica unique (operacion_apertura_id),
  constraint jornadas_camion_fk foreign key (empresa_id, camion_id)
    references public.camiones (empresa_id, id) on delete restrict,
  constraint jornadas_vendedor_fk foreign key (empresa_id, vendedor_id)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint jornadas_abierta_por_fk foreign key (empresa_id, abierta_por)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint jornadas_operacion_apertura_fk
    foreign key (empresa_id, operacion_apertura_id, tipo_operacion_apertura, abierta_por)
    references public.operaciones (empresa_id, id, tipo, actor_id) on delete restrict,
  constraint jornadas_estado_valido
    check (estado in ('abierta', 'cargada', 'en_reparto', 'ventas_finalizadas',
                      'regreso_contado', 'cerrada')),
  constraint jornadas_tipo_operacion_apertura_valido
    check (tipo_operacion_apertura = 'apertura_jornada')
);

comment on table public.jornadas is
  'Jornada de un camión en una fecha operativa (Blueprint §7.5, §8; ADR-007). Escritura sólo por las RPC de jornadas; UPDATE acotado a estado, vendedor_id, fecha y camion_id. Sin DELETE.';

alter table public.jornadas enable row level security;

-- ---------------------------------------------------------------------------
-- 5. operaciones: FK a jornadas, tipos y presencia de jornada por tipo
-- ---------------------------------------------------------------------------
alter table public.operaciones
  add constraint operaciones_jornada_fk foreign key (empresa_id, jornada_id)
    references public.jornadas (empresa_id, id) on delete restrict;

alter table public.operaciones drop constraint operaciones_tipo_valido;
alter table public.operaciones add constraint operaciones_tipo_valido
  check (tipo in ('ingreso', 'a_cuarentena', 'merma', 'apertura_jornada',
                  'reasignacion_vendedor', 'correccion_jornada', 'carga',
                  'descarga', 'salida_jornada'));

alter table public.operaciones add constraint operaciones_jornada_por_tipo
  check (
    (tipo in ('ingreso', 'a_cuarentena', 'merma', 'apertura_jornada')
      and jornada_id is null)
    or (tipo in ('reasignacion_vendedor', 'correccion_jornada', 'carga',
                 'descarga', 'salida_jornada')
      and jornada_id is not null));

-- ---------------------------------------------------------------------------
-- 6. movimientos_stock: jornada_id, tipos carga/descarga, FK e índices
-- ---------------------------------------------------------------------------
alter table public.movimientos_stock add column jornada_id uuid;

comment on column public.movimientos_stock.jornada_id is
  'Jornada del movimiento (ADR-001 §18.4.1). NULL para ingreso, a_cuarentena y merma; NOT NULL para carga y descarga.';

alter table public.movimientos_stock
  add constraint movimientos_stock_jornada_fk foreign key (empresa_id, jornada_id)
    references public.jornadas (empresa_id, id) on delete restrict;

alter table public.movimientos_stock drop constraint movimientos_stock_tipo_valido;
alter table public.movimientos_stock add constraint movimientos_stock_tipo_valido
  check (tipo_movimiento in ('ingreso', 'a_cuarentena', 'merma', 'carga', 'descarga'));

alter table public.movimientos_stock drop constraint movimientos_stock_forma_por_tipo;
alter table public.movimientos_stock add constraint movimientos_stock_forma_por_tipo
  check (
    (tipo_movimiento = 'ingreso'
      and ubicacion_origen_id is null and ubicacion_destino_id is not null)
    or (tipo_movimiento = 'a_cuarentena'
      and ubicacion_origen_id is not null and ubicacion_destino_id is not null)
    or (tipo_movimiento = 'merma'
      and ubicacion_origen_id is not null and ubicacion_destino_id is null)
    or (tipo_movimiento in ('carga', 'descarga')
      and ubicacion_origen_id is not null and ubicacion_destino_id is not null));

alter table public.movimientos_stock drop constraint movimientos_stock_motivo_por_tipo;
alter table public.movimientos_stock add constraint movimientos_stock_motivo_por_tipo
  check (
    (tipo_movimiento = 'ingreso' and motivo_codigo is null)
    or (tipo_movimiento = 'a_cuarentena' and motivo_codigo is null and motivo is not null)
    or (tipo_movimiento = 'merma' and motivo_codigo is not null
        and (motivo_codigo <> 'otro' or motivo is not null))
    or (tipo_movimiento = 'carga' and motivo_codigo is null and motivo is null)
    or (tipo_movimiento = 'descarga' and motivo_codigo is null and motivo is not null));

alter table public.movimientos_stock add constraint movimientos_stock_jornada_por_tipo
  check (
    (tipo_movimiento in ('ingreso', 'a_cuarentena', 'merma') and jornada_id is null)
    or (tipo_movimiento in ('carga', 'descarga') and jornada_id is not null));

-- Para carga y descarga todas las columnas de la FK son NOT NULL, así que se
-- evalúa siempre; para los tipos de Stock jornada_id es NULL y MATCH SIMPLE no
-- la evalúa (los cubre movimientos_stock_operacion_fk y la policy D8).
alter table public.movimientos_stock
  add constraint movimientos_stock_operacion_referencia_fk
    foreign key (empresa_id, operacion_id, tipo_movimiento, actor_id, jornada_id)
    references public.operaciones (empresa_id, id, tipo, actor_id, jornada_id)
    on delete restrict;

-- Una carga/descarga tiene varios movimientos (uno por producto). D7 no se
-- toca: su predicado excluye estos tipos.
create unique index movimientos_stock_operacion_producto_unica
  on public.movimientos_stock (empresa_id, operacion_id, producto_id)
  where tipo_movimiento in ('carga', 'descarga');

create index movimientos_stock_jornada_idx
  on public.movimientos_stock (empresa_id, jornada_id)
  where jornada_id is not null;

-- ---------------------------------------------------------------------------
-- 7. Historiales append-only
-- ---------------------------------------------------------------------------
create table public.reasignaciones_vendedor (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  jornada_id uuid not null,
  operacion_id uuid not null,
  tipo_operacion text not null default 'reasignacion_vendedor',
  vendedor_anterior_id uuid not null,
  vendedor_nuevo_id uuid not null,
  actor_id uuid not null,
  creado_en timestamptz not null default now(),
  constraint reasignaciones_vendedor_pkey primary key (id),
  constraint reasignaciones_vendedor_empresa_fk foreign key (empresa_id)
    references public.empresas (id) on delete restrict,
  constraint reasignaciones_vendedor_operacion_unica unique (empresa_id, operacion_id),
  constraint reasignaciones_vendedor_jornada_fk foreign key (empresa_id, jornada_id)
    references public.jornadas (empresa_id, id) on delete restrict,
  constraint reasignaciones_vendedor_vendedor_anterior_fk
    foreign key (empresa_id, vendedor_anterior_id)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint reasignaciones_vendedor_vendedor_nuevo_fk
    foreign key (empresa_id, vendedor_nuevo_id)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint reasignaciones_vendedor_actor_fk foreign key (empresa_id, actor_id)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint reasignaciones_vendedor_operacion_referencia_fk
    foreign key (empresa_id, operacion_id, tipo_operacion, actor_id, jornada_id)
    references public.operaciones (empresa_id, id, tipo, actor_id, jornada_id)
    on delete restrict,
  constraint reasignaciones_vendedor_tipo_operacion_valido
    check (tipo_operacion = 'reasignacion_vendedor'),
  constraint reasignaciones_vendedor_vendedores_distintos
    check (vendedor_anterior_id <> vendedor_nuevo_id)
);

comment on table public.reasignaciones_vendedor is
  'Historial append-only de reasignaciones de vendedor de una jornada (ADR-007 §2.3). Escritura sólo por reasignar_vendedor; sin UPDATE ni DELETE.';

create table public.correcciones_jornada (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  jornada_id uuid not null,
  operacion_id uuid not null,
  tipo_operacion text not null default 'correccion_jornada',
  fecha_anterior date not null,
  fecha_nueva date not null,
  camion_anterior_id uuid not null,
  camion_nuevo_id uuid not null,
  motivo text not null,
  actor_id uuid not null,
  creado_en timestamptz not null default now(),
  constraint correcciones_jornada_pkey primary key (id),
  constraint correcciones_jornada_empresa_fk foreign key (empresa_id)
    references public.empresas (id) on delete restrict,
  constraint correcciones_jornada_operacion_unica unique (empresa_id, operacion_id),
  constraint correcciones_jornada_jornada_fk foreign key (empresa_id, jornada_id)
    references public.jornadas (empresa_id, id) on delete restrict,
  constraint correcciones_jornada_camion_anterior_fk
    foreign key (empresa_id, camion_anterior_id)
    references public.camiones (empresa_id, id) on delete restrict,
  constraint correcciones_jornada_camion_nuevo_fk
    foreign key (empresa_id, camion_nuevo_id)
    references public.camiones (empresa_id, id) on delete restrict,
  constraint correcciones_jornada_actor_fk foreign key (empresa_id, actor_id)
    references public.perfiles (empresa_id, usuario_id) on delete restrict,
  constraint correcciones_jornada_operacion_referencia_fk
    foreign key (empresa_id, operacion_id, tipo_operacion, actor_id, jornada_id)
    references public.operaciones (empresa_id, id, tipo, actor_id, jornada_id)
    on delete restrict,
  constraint correcciones_jornada_tipo_operacion_valido
    check (tipo_operacion = 'correccion_jornada'),
  constraint correcciones_jornada_cambio_efectivo
    check (fecha_anterior <> fecha_nueva or camion_anterior_id <> camion_nuevo_id),
  constraint correcciones_jornada_motivo_normalizado
    check (motivo = btrim(motivo) and length(motivo) > 0)
);

comment on table public.correcciones_jornada is
  'Historial append-only de correcciones de fecha o camión de una jornada abierta (ADR-007 §2.4). Escritura sólo por corregir_jornada; sin UPDATE ni DELETE.';

alter table public.reasignaciones_vendedor enable row level security;
alter table public.correcciones_jornada enable row level security;

-- ---------------------------------------------------------------------------
-- 8. Grants (explícitos; nada para PUBLIC, anon ni service_role)
-- ---------------------------------------------------------------------------
revoke all on table public.jornadas, public.reasignaciones_vendedor,
  public.correcciones_jornada
  from public, anon, authenticated, service_role;

grant select on table public.jornadas, public.reasignaciones_vendedor,
  public.correcciones_jornada to authenticated;

-- jornadas: UPDATE controlado por columna (no es append-only); sin DELETE.
grant select on table public.jornadas to propietario_rpc;
grant insert (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por,
              operacion_apertura_id)
  on table public.jornadas to propietario_rpc;
grant update (estado, vendedor_id, fecha, camion_id)
  on table public.jornadas to propietario_rpc;

-- Historiales: sólo INSERT por columna; sin SELECT, UPDATE ni DELETE.
grant insert (empresa_id, jornada_id, operacion_id, vendedor_anterior_id,
              vendedor_nuevo_id, actor_id)
  on table public.reasignaciones_vendedor to propietario_rpc;
grant insert (empresa_id, jornada_id, operacion_id, fecha_anterior, fecha_nueva,
              camion_anterior_id, camion_nuevo_id, motivo, actor_id)
  on table public.correcciones_jornada to propietario_rpc;

grant insert (jornada_id) on table public.operaciones to propietario_rpc;
grant insert (jornada_id) on table public.movimientos_stock to propietario_rpc;

-- ---------------------------------------------------------------------------
-- 9. Policies
-- ---------------------------------------------------------------------------
-- jornadas: lectura de dueño/encargado activo de la empresa, o del vendedor
-- asignado con perfil activo (ADR-007 §2.8).
create policy jornadas_select_authenticated
  on public.jornadas
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = jornadas.empresa_id
        and p.usuario_id = (select auth.uid())
        and p.activo
        and (p.rol in ('dueno', 'encargado') or jornadas.vendedor_id = p.usuario_id)
    )
  );

create policy jornadas_select_propietario_rpc
  on public.jornadas
  for select
  to propietario_rpc
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = jornadas.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

create policy jornadas_insert_propietario_rpc
  on public.jornadas
  for insert
  to propietario_rpc
  with check (
    abierta_por = (select privado.usuario_actual())
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = jornadas.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

create policy jornadas_update_propietario_rpc
  on public.jornadas
  for update
  to propietario_rpc
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = jornadas.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  )
  with check (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = jornadas.empresa_id
        and p.usuario_id = (select privado.usuario_actual())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

-- Historiales: lectura sólo de dueño/encargado activo; el vendedor no los ve.
create policy reasignaciones_vendedor_select_gestion
  on public.reasignaciones_vendedor
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = reasignaciones_vendedor.empresa_id
        and p.usuario_id = (select auth.uid())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

create policy correcciones_jornada_select_gestion
  on public.correcciones_jornada
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.perfiles p
      where p.empresa_id = correcciones_jornada.empresa_id
        and p.usuario_id = (select auth.uid())
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

create policy reasignaciones_vendedor_insert_propietario_rpc
  on public.reasignaciones_vendedor
  for insert
  to propietario_rpc
  with check (
    actor_id = (select privado.usuario_actual())
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = reasignaciones_vendedor.empresa_id
        and p.usuario_id = reasignaciones_vendedor.actor_id
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
    and exists (
      select 1
      from public.jornadas j
      where j.id = reasignaciones_vendedor.jornada_id
        and j.empresa_id = reasignaciones_vendedor.empresa_id
    )
  );

create policy correcciones_jornada_insert_propietario_rpc
  on public.correcciones_jornada
  for insert
  to propietario_rpc
  with check (
    actor_id = (select privado.usuario_actual())
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = correcciones_jornada.empresa_id
        and p.usuario_id = correcciones_jornada.actor_id
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
    and exists (
      select 1
      from public.jornadas j
      where j.id = correcciones_jornada.jornada_id
        and j.empresa_id = correcciones_jornada.empresa_id
    )
  );

-- operaciones (D6 ampliada): se conservan las condiciones de Stock (actor,
-- perfil activo, dueño o encargado); se agregan los tipos de jornadas y la
-- presencia de jornada por tipo.
alter policy operaciones_insert_propietario_rpc
  on public.operaciones
  with check (
    actor_id = (select privado.usuario_actual())
    and tipo in ('ingreso', 'a_cuarentena', 'merma', 'apertura_jornada',
                 'reasignacion_vendedor', 'correccion_jornada', 'carga',
                 'descarga', 'salida_jornada')
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = operaciones.empresa_id
        and p.usuario_id = operaciones.actor_id
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
    and (
      (tipo in ('ingreso', 'a_cuarentena', 'merma', 'apertura_jornada')
        and jornada_id is null)
      or (tipo in ('reasignacion_vendedor', 'correccion_jornada', 'carga',
                   'descarga', 'salida_jornada')
        and exists (select 1 from public.jornadas j
                     where j.id = operaciones.jornada_id
                       and j.empresa_id = operaciones.empresa_id))
    )
  );

-- movimientos_stock (D8 ampliada): las tres formas de Stock se conservan
-- textualmente; se agregan carga (depósito propio -> ubicación del camión de
-- la jornada) y descarga (al revés), y la igualdad de jornada con la operación.
alter policy movimientos_stock_insert_propietario_rpc
  on public.movimientos_stock
  with check (
    actor_id = (select privado.usuario_actual())
    and tipo_movimiento in ('ingreso', 'a_cuarentena', 'merma', 'carga', 'descarga')
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
        and o.tipo = movimientos_stock.tipo_movimiento
        and o.jornada_id is not distinct from movimientos_stock.jornada_id
    )
    and (
      (tipo_movimiento = 'ingreso'
        and ubicacion_origen_id is null
        and exists (select 1 from public.ubicaciones d
                     where d.id = movimientos_stock.ubicacion_destino_id
                       and d.empresa_id = movimientos_stock.empresa_id
                       and d.tipo = 'deposito'))
      or (tipo_movimiento = 'a_cuarentena'
        and exists (select 1 from public.ubicaciones o
                     where o.id = movimientos_stock.ubicacion_origen_id
                       and o.empresa_id = movimientos_stock.empresa_id
                       and o.tipo = 'deposito')
        and exists (select 1 from public.ubicaciones d
                     where d.id = movimientos_stock.ubicacion_destino_id
                       and d.empresa_id = movimientos_stock.empresa_id
                       and d.tipo = 'cuarentena'))
      or (tipo_movimiento = 'merma'
        and ubicacion_destino_id is null
        and exists (select 1 from public.ubicaciones o
                     where o.id = movimientos_stock.ubicacion_origen_id
                       and o.empresa_id = movimientos_stock.empresa_id
                       and o.tipo = 'deposito'))
      or (tipo_movimiento = 'carga'
        and exists (select 1 from public.ubicaciones o
                     where o.id = movimientos_stock.ubicacion_origen_id
                       and o.empresa_id = movimientos_stock.empresa_id
                       and o.tipo = 'deposito')
        and exists (select 1
                      from public.jornadas j
                      join public.ubicaciones d
                        on d.empresa_id = j.empresa_id
                       and d.camion_id = j.camion_id
                       and d.tipo = 'camion'
                     where j.id = movimientos_stock.jornada_id
                       and j.empresa_id = movimientos_stock.empresa_id
                       and d.id = movimientos_stock.ubicacion_destino_id))
      or (tipo_movimiento = 'descarga'
        and exists (select 1 from public.ubicaciones d
                     where d.id = movimientos_stock.ubicacion_destino_id
                       and d.empresa_id = movimientos_stock.empresa_id
                       and d.tipo = 'deposito')
        and exists (select 1
                      from public.jornadas j
                      join public.ubicaciones o
                        on o.empresa_id = j.empresa_id
                       and o.camion_id = j.camion_id
                       and o.tipo = 'camion'
                     where j.id = movimientos_stock.jornada_id
                       and j.empresa_id = movimientos_stock.empresa_id
                       and o.id = movimientos_stock.ubicacion_origen_id))
    )
  );

-- ---------------------------------------------------------------------------
-- 10. Verificación final fail-closed
-- ---------------------------------------------------------------------------
do $$
declare
  v_tablas regclass[] := array['public.jornadas'::regclass,
                               'public.reasignaciones_vendedor'::regclass,
                               'public.correcciones_jornada'::regclass];
  v_t regclass;
  v_rol text;
  v_cols text;
begin
  -- Owner y RLS: owner de migraciones, RLS habilitada, sin FORCE (P4).
  if exists (select 1 from pg_class c
              where c.oid = any (v_tablas)
                and (c.relowner <> 'postgres'::regrole
                     or not c.relrowsecurity or c.relforcerowsecurity)) then
    raise exception 'jornadas: owner o RLS de las tablas nuevas fuera de lo aprobado';
  end if;

  -- anon y service_role: ningún privilegio; PUBLIC: ninguno; authenticated:
  -- sólo SELECT (ni DML ni privilegios por columna).
  foreach v_t in array v_tablas loop
    foreach v_rol in array array['anon', 'service_role'] loop
      if has_table_privilege(v_rol, v_t, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
         or has_any_column_privilege(v_rol, v_t, 'SELECT, INSERT, UPDATE, REFERENCES') then
        raise exception 'jornadas: % tiene privilegios sobre %', v_rol, v_t;
      end if;
    end loop;
    if not has_table_privilege('authenticated', v_t, 'SELECT')
       or has_table_privilege('authenticated', v_t, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       or has_any_column_privilege('authenticated', v_t, 'INSERT, UPDATE, REFERENCES') then
      raise exception 'jornadas: authenticated fuera de lo aprobado sobre %', v_t;
    end if;
    if exists (select 1 from pg_class c, aclexplode(c.relacl) a
                where c.oid = v_t and a.grantee = 0) then
      raise exception 'jornadas: PUBLIC tiene privilegios sobre %', v_t;
    end if;
    -- propietario_rpc: sin DELETE, TRUNCATE, REFERENCES ni TRIGGER.
    if has_table_privilege('propietario_rpc', v_t, 'DELETE, TRUNCATE, REFERENCES, TRIGGER') then
      raise exception 'jornadas: propietario_rpc con privilegios de más sobre %', v_t;
    end if;
  end loop;

  -- Columnas exactas de INSERT/UPDATE de propietario_rpc.
  select string_agg(a.attname, ',' order by a.attname) into v_cols
    from pg_attribute a
   where a.attrelid = 'public.jornadas'::regclass and a.attnum > 0 and not a.attisdropped
     and has_column_privilege('propietario_rpc', 'public.jornadas', a.attname, 'INSERT');
  if v_cols is distinct from 'abierta_por,camion_id,empresa_id,estado,fecha,operacion_apertura_id,vendedor_id' then
    raise exception 'jornadas: columnas INSERT de propietario_rpc inesperadas: %', v_cols;
  end if;
  select string_agg(a.attname, ',' order by a.attname) into v_cols
    from pg_attribute a
   where a.attrelid = 'public.jornadas'::regclass and a.attnum > 0 and not a.attisdropped
     and has_column_privilege('propietario_rpc', 'public.jornadas', a.attname, 'UPDATE');
  if v_cols is distinct from 'camion_id,estado,fecha,vendedor_id' then
    raise exception 'jornadas: columnas UPDATE de propietario_rpc inesperadas: %', v_cols;
  end if;
  -- Historiales: append-only (sin SELECT ni UPDATE de propietario_rpc).
  if has_any_column_privilege('propietario_rpc', 'public.reasignaciones_vendedor', 'SELECT, UPDATE')
     or has_any_column_privilege('propietario_rpc', 'public.correcciones_jornada', 'SELECT, UPDATE') then
    raise exception 'jornadas: los historiales no son append-only para propietario_rpc';
  end if;
  select string_agg(a.attname, ',' order by a.attname) into v_cols
    from pg_attribute a
   where a.attrelid = 'public.reasignaciones_vendedor'::regclass and a.attnum > 0 and not a.attisdropped
     and has_column_privilege('propietario_rpc', 'public.reasignaciones_vendedor', a.attname, 'INSERT');
  if v_cols is distinct from 'actor_id,empresa_id,jornada_id,operacion_id,vendedor_anterior_id,vendedor_nuevo_id' then
    raise exception 'jornadas: columnas INSERT de reasignaciones_vendedor inesperadas: %', v_cols;
  end if;
  select string_agg(a.attname, ',' order by a.attname) into v_cols
    from pg_attribute a
   where a.attrelid = 'public.correcciones_jornada'::regclass and a.attnum > 0 and not a.attisdropped
     and has_column_privilege('propietario_rpc', 'public.correcciones_jornada', a.attname, 'INSERT');
  if v_cols is distinct from 'actor_id,camion_anterior_id,camion_nuevo_id,empresa_id,fecha_anterior,fecha_nueva,jornada_id,motivo,operacion_id' then
    raise exception 'jornadas: columnas INSERT de correcciones_jornada inesperadas: %', v_cols;
  end if;

  -- operaciones y movimientos_stock: sigue sin UPDATE/DELETE para propietario_rpc
  -- y el único INSERT nuevo es jornada_id; service_role sigue sin nada.
  if has_any_column_privilege('propietario_rpc', 'public.operaciones', 'UPDATE')
     or has_any_column_privilege('propietario_rpc', 'public.movimientos_stock', 'UPDATE')
     or has_table_privilege('propietario_rpc', 'public.operaciones', 'DELETE, TRUNCATE')
     or has_table_privilege('propietario_rpc', 'public.movimientos_stock', 'DELETE, TRUNCATE')
     or not has_column_privilege('propietario_rpc', 'public.operaciones', 'jornada_id', 'INSERT')
     or not has_column_privilege('propietario_rpc', 'public.movimientos_stock', 'jornada_id', 'INSERT')
     or has_any_column_privilege('service_role', 'public.operaciones', 'SELECT, INSERT, UPDATE, REFERENCES')
     or has_any_column_privilege('service_role', 'public.movimientos_stock', 'SELECT, INSERT, UPDATE, REFERENCES')
     or has_any_column_privilege('authenticated', 'public.operaciones', 'INSERT, UPDATE, REFERENCES')
     or has_any_column_privilege('authenticated', 'public.movimientos_stock', 'INSERT, UPDATE, REFERENCES') then
    raise exception 'jornadas: privilegios de operaciones o movimientos_stock fuera de lo aprobado';
  end if;

  -- Policies exactas de las tablas nuevas (sin UPDATE ni DELETE en los
  -- historiales; sin DELETE en jornadas).
  if (select string_agg(tablename || '.' || policyname || ':' || cmd || ':' || array_to_string(roles, ','),
                        ',' order by tablename, policyname)
        from pg_policies
       where schemaname = 'public'
         and tablename in ('jornadas', 'reasignaciones_vendedor', 'correcciones_jornada'))
     is distinct from
     'correcciones_jornada.correcciones_jornada_insert_propietario_rpc:INSERT:propietario_rpc,'
     || 'correcciones_jornada.correcciones_jornada_select_gestion:SELECT:authenticated,'
     || 'jornadas.jornadas_insert_propietario_rpc:INSERT:propietario_rpc,'
     || 'jornadas.jornadas_select_authenticated:SELECT:authenticated,'
     || 'jornadas.jornadas_select_propietario_rpc:SELECT:propietario_rpc,'
     || 'jornadas.jornadas_update_propietario_rpc:UPDATE:propietario_rpc,'
     || 'reasignaciones_vendedor.reasignaciones_vendedor_insert_propietario_rpc:INSERT:propietario_rpc,'
     || 'reasignaciones_vendedor.reasignaciones_vendedor_select_gestion:SELECT:authenticated' then
    raise exception 'jornadas: policies de las tablas nuevas fuera de lo aprobado';
  end if;

  -- Las policies de operaciones y movimientos_stock conservan nombres y roles,
  -- y D6/D8 siguen exigiendo el tipo de la operación y las formas de Stock.
  if (select string_agg(tablename || '.' || policyname || ':' || cmd || ':' || array_to_string(roles, ','),
                        ',' order by tablename, policyname)
        from pg_policies
       where schemaname = 'public' and tablename in ('operaciones', 'movimientos_stock'))
     is distinct from
     'movimientos_stock.movimientos_stock_insert_propietario_rpc:INSERT:propietario_rpc,'
     || 'movimientos_stock.movimientos_stock_select_empresa:SELECT:authenticated,'
     || 'movimientos_stock.movimientos_stock_select_propietario_rpc:SELECT:propietario_rpc,'
     || 'operaciones.operaciones_insert_propietario_rpc:INSERT:propietario_rpc,'
     || 'operaciones.operaciones_select_empresa:SELECT:authenticated,'
     || 'operaciones.operaciones_select_propietario_rpc:SELECT:propietario_rpc' then
    raise exception 'jornadas: policies de operaciones o movimientos_stock fuera de lo aprobado';
  end if;

  -- D7 intacto.
  if pg_get_indexdef('public.movimientos_stock_operacion_unitaria_unica'::regclass)
     is distinct from
     'CREATE UNIQUE INDEX movimientos_stock_operacion_unitaria_unica ON public.movimientos_stock USING btree (empresa_id, operacion_id) WHERE (tipo_movimiento = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text]))' then
    raise exception 'jornadas: D7 fue modificado';
  end if;

  -- D-2 intacto: ver la sección 11 (contrato completo de D-2).
end $$;

-- ---------------------------------------------------------------------------
-- 11. Contrato aprobado de D-2 (postcheck)
-- ---------------------------------------------------------------------------
-- Segunda comprobación, ya con D-1 aplicado: D-1 no debe haber alterado el
-- contrato de D-2. Mismo bloque literal de la verificación 7 de D-2.
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
