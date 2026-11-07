-- Q1 — roles con LOGIN y TEMP (compuerta obligatoria de revisión) y configuración supautils. Solo lectura.
-- TODOS los roles con LOGIN y privilegio TEMP entran en la compuerta, incluidos los reservados de la
-- plataforma y los superusuarios: ser rol de plataforma no implica seguridad (O4-PGTEMP).
select r.rolname, r.rolsuper, r.rolcreaterole, r.rolcreatedb, r.rolreplication, r.rolbypassrls,
       (r.rolname = any (array(select trim(trailing '*' from btrim(x))
                                 from unnest(string_to_array(coalesce(current_setting('supautils.reserved_roles', true), ''), ',')) x))) as reservado,
       has_database_privilege(r.oid, current_database(), 'TEMP') as temp_en_base,
       r.rolconnlimit, r.rolvaliduntil, r.rolconfig,
       (select string_agg(m.roleid::regrole::text, ',' order by m.roleid::regrole::text)
          from pg_auth_members m where m.member = r.oid) as miembro_de
  from pg_roles r
 where r.rolcanlogin
 order by r.rolname collate "C";
-- Huella de la lista exacta que se revisa (la misma expresión que usa Q6): si cambia un rol o un atributo,
-- cambia la huella y la revisión previa deja de valer.
select coalesce(string_agg(concat_ws('|', x.rolname, x.rolsuper, x.rolcreaterole, x.rolcreatedb, x.rolreplication, x.rolbypassrls, x.reservado),
                                     ';' order by x.rolname collate "C"), '') as lista_login_temp,
       encode(sha256(convert_to(coalesce(string_agg(concat_ws('|', x.rolname, x.rolsuper, x.rolcreaterole, x.rolcreatedb, x.rolreplication, x.rolbypassrls, x.reservado),
                                     ';' order by x.rolname collate "C"), ''), 'UTF8')), 'hex') as digest_login_temp
  from (select r.rolname, r.rolsuper, r.rolcreaterole, r.rolcreatedb, r.rolreplication, r.rolbypassrls,
               (r.rolname = any (array(select trim(trailing '*' from btrim(y))
                                         from unnest(string_to_array(coalesce(current_setting('supautils.reserved_roles', true), ''), ',')) y))) as reservado
          from pg_roles r
         where r.rolcanlogin and has_database_privilege(r.oid, current_database(), 'TEMP')) x;
select name, setting from pg_settings where name like 'supautils.%' order by name;
