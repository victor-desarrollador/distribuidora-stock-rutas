-- Q5 — RLS de las relaciones de public (tablas y particionadas). Solo lectura.
select c.oid::regclass::text as relacion, c.relkind::text, c.relrowsecurity, c.relforcerowsecurity,
       c.relowner::regrole::text as owner
  from pg_class c
 where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
 order by 1;
select count(*) as tablas_public_sin_rls
  from pg_class c
 where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and not c.relrowsecurity;
