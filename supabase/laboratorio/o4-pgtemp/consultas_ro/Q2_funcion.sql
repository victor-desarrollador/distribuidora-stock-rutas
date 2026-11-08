-- Q2 — contrato de public.rls_auto_enable() (todas las homónimas, de cualquier esquema). Solo lectura.
select p.oid::bigint as oid, n.nspname as esquema, p.proowner::regrole::text as owner, p.prokind, p.prosecdef,
       l.lanname, p.prorettype::regtype::text as retorno, p.proconfig,
       encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex') as sha256_prosrc,
       octet_length(convert_to(p.prosrc, 'UTF8')) as bytes,
       (p.prosqlbody is null) as sqlbody_nulo, (p.probin is null) as probin_nulo, p.proacl::text as acl,
       (p.proacl is not distinct from array['postgres=X/postgres'::aclitem]) as acl_exacta_e_o4_acl
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join pg_language l on l.oid = p.prolang
 where p.proname = 'rls_auto_enable'
 order by n.nspname, p.oid;
select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end as grantee, a.privilege_type, a.is_grantable
  from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
 where p.oid = to_regprocedure('public.rls_auto_enable()')
 order by 1, 2;
select r as rol,
       has_function_privilege(r, to_regprocedure('public.rls_auto_enable()'), 'EXECUTE') as execute_efectivo
  from unnest(array['anon', 'authenticated', 'service_role']) r
 order by 1;
