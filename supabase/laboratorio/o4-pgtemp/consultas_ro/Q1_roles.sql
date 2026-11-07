-- Q1 — roles con LOGIN y TEMP (compuerta obligatoria de revisión) y configuración supautils. Solo lectura.
-- TODOS los roles con LOGIN y privilegio TEMP entran en la compuerta, incluidos los reservados de la plataforma y
-- los superusuarios: ser rol de plataforma no implica seguridad (O4-PGTEMP).
-- Representación revisada = jsonb canónico (claves y listas ordenadas con collation "C", sin delimitadores
-- ambiguos): atributos, rolconnlimit, rolvaliduntil, rolconfig, membresías directas (con admin/inherit/set) y los
-- patrones de roles reservados con su coincidencia exacta o por prefijo ("x*" = prefijo literal; sin LIKE).
-- La huella es una FOTOGRAFÍA PUNTUAL de este instante: no demuestra que no hubo cambios transitorios antes o
-- después, y no es una autorización.
with pat as (
  select coalesce(jsonb_agg(btrim(x) order by btrim(x) collate "C"), '[]'::jsonb) as p,
         coalesce(array_agg(btrim(x)), array[]::text[]) as a
    from unnest(string_to_array(coalesce(current_setting('supautils.reserved_roles', true), ''), ',')) x
   where btrim(x) <> ''),
rl as (
  select r.oid, r.rolname, r.rolsuper, r.rolinherit, r.rolcreaterole, r.rolcreatedb, r.rolreplication, r.rolbypassrls,
         r.rolconnlimit, r.rolvaliduntil, r.rolconfig
    from pg_roles r
   where r.rolcanlogin and has_database_privilege(r.oid, current_database(), 'TEMP')),
canon as (
  select jsonb_build_object(
    'patrones_reservados', (select p from pat),
    'roles', coalesce(jsonb_agg(jsonb_build_object(
        'rol', rl.rolname, 'super', rl.rolsuper, 'inherit', rl.rolinherit, 'createrole', rl.rolcreaterole,
        'createdb', rl.rolcreatedb, 'replicacion', rl.rolreplication, 'bypassrls', rl.rolbypassrls,
        'connlimit', rl.rolconnlimit,
        'valido_hasta_epoch', case when rl.rolvaliduntil is null then null else extract(epoch from rl.rolvaliduntil)::text end,
        'config', coalesce((select jsonb_agg(c order by c collate "C") from unnest(rl.rolconfig) c), '[]'::jsonb),
        'membresias', coalesce((select jsonb_agg(jsonb_build_object('rol', m.roleid::regrole::text, 'admin', m.admin_option,
                                                                    'inherit', m.inherit_option, 'set', m.set_option)
                                                 order by m.roleid::regrole::text collate "C")
                                  from pg_auth_members m where m.member = rl.oid), '[]'::jsonb),
        'reservado_exacto', exists (select 1 from unnest((select a from pat)) e where e not like '%*' and rl.rolname = e),
        'reservado_prefijo', exists (select 1 from unnest((select a from pat)) e
                                      where e like '%*' and left(rl.rolname, length(e) - 1) = left(e, length(e) - 1))
      ) order by rl.rolname collate "C"), '[]'::jsonb)) as j
    from rl)
select jsonb_pretty(j) as lista_login_temp_canonica from canon;
with pat as (
  select coalesce(jsonb_agg(btrim(x) order by btrim(x) collate "C"), '[]'::jsonb) as p,
         coalesce(array_agg(btrim(x)), array[]::text[]) as a
    from unnest(string_to_array(coalesce(current_setting('supautils.reserved_roles', true), ''), ',')) x
   where btrim(x) <> ''),
rl as (
  select r.oid, r.rolname, r.rolsuper, r.rolinherit, r.rolcreaterole, r.rolcreatedb, r.rolreplication, r.rolbypassrls,
         r.rolconnlimit, r.rolvaliduntil, r.rolconfig
    from pg_roles r
   where r.rolcanlogin and has_database_privilege(r.oid, current_database(), 'TEMP')),
canon as (
  select jsonb_build_object(
    'patrones_reservados', (select p from pat),
    'roles', coalesce(jsonb_agg(jsonb_build_object(
        'rol', rl.rolname, 'super', rl.rolsuper, 'inherit', rl.rolinherit, 'createrole', rl.rolcreaterole,
        'createdb', rl.rolcreatedb, 'replicacion', rl.rolreplication, 'bypassrls', rl.rolbypassrls,
        'connlimit', rl.rolconnlimit,
        'valido_hasta_epoch', case when rl.rolvaliduntil is null then null else extract(epoch from rl.rolvaliduntil)::text end,
        'config', coalesce((select jsonb_agg(c order by c collate "C") from unnest(rl.rolconfig) c), '[]'::jsonb),
        'membresias', coalesce((select jsonb_agg(jsonb_build_object('rol', m.roleid::regrole::text, 'admin', m.admin_option,
                                                                    'inherit', m.inherit_option, 'set', m.set_option)
                                                 order by m.roleid::regrole::text collate "C")
                                  from pg_auth_members m where m.member = rl.oid), '[]'::jsonb),
        'reservado_exacto', exists (select 1 from unnest((select a from pat)) e where e not like '%*' and rl.rolname = e),
        'reservado_prefijo', exists (select 1 from unnest((select a from pat)) e
                                      where e like '%*' and left(rl.rolname, length(e) - 1) = left(e, length(e) - 1))
      ) order by rl.rolname collate "C"), '[]'::jsonb)) as j
    from rl)
select encode(sha256(convert_to(j::text, 'UTF8')), 'hex') as digest_login_temp from canon;
select name, setting from pg_settings where name like 'supautils.%' order by name;
