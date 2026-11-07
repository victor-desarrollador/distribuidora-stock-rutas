-- Q1 — roles con LOGIN, privilegio TEMP y configuración supautils. Solo lectura.
select r.rolname, r.rolsuper, r.rolcreaterole, r.rolcreatedb, r.rolreplication, r.rolbypassrls,
       r.rolconnlimit, r.rolvaliduntil, r.rolconfig,
       has_database_privilege(r.oid, current_database(), 'TEMP') as temp_en_base,
       (select string_agg(m.roleid::regrole::text, ',' order by m.roleid::regrole::text)
          from pg_auth_members m where m.member = r.oid) as miembro_de
  from pg_roles r
 where r.rolcanlogin
 order by r.rolname;
select name, setting from pg_settings where name like 'supautils.%' order by name;
