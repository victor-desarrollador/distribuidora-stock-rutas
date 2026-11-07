-- Q6 — criterios de abortar, calculados. Requiere  -v estado_esperado=original|remediado .
-- Devuelve  abortar  (texto o NULL) y  revisar  (a criterio humano). Solo lectura.
-- Q6 — criterios de abortar, calculados. Requiere  -v estado_esperado=original|remediado  y, para pasar la
-- compuerta LOGIN+TEMP,  -v revision_login_temp=<digest>  (huella de Q1 tras la revisión humana de la lista).
-- Devuelve  abortar  (texto o vacío),  digest_login_temp  y  sin_escrituras. Solo lectura.
\if :{?estado_esperado}
\else
do $g$ begin raise exception 'Q6: falta -v estado_esperado=original|remediado'; end $g$;
\endif
\if :{?revision_login_temp}
\set rev_tok :revision_login_temp
\else
\set rev_tok ''
\endif
\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
with f as (select p.* from pg_proc p where p.oid = to_regprocedure('public.rls_auto_enable()')),
     lt as (select coalesce(string_agg(concat_ws('|', r.rolname, r.rolsuper, r.rolcreaterole, r.rolcreatedb, r.rolreplication, r.rolbypassrls,
                   (r.rolname = any (array(select trim(trailing '*' from btrim(y))
                                             from unnest(string_to_array(coalesce(current_setting('supautils.reserved_roles', true), ''), ',')) y)))),
                   ';' order by r.rolname collate "C"), '') as lista
              from pg_roles r where r.rolcanlogin and has_database_privilege(r.oid, current_database(), 'TEMP')),
     ex as (select case :'estado_esperado'
                     when 'original'  then '325ae266d9b166715ef5230ceaf7ff9d523e483cf5610dfb9779ab3f183f4af9'
                     when 'remediado' then 'e1b231fb7db1d25c9dfab71d09dbc968c092c00c0049aca1f529f7e79296fb6e' end as hash,
                   case :'estado_esperado'
                     when 'original'  then '{search_path=pg_catalog}'
                     when 'remediado' then '{"search_path=pg_catalog, pg_temp"}' end as cfg),
     ev as (select * from pg_event_trigger e where e.evtname = 'ensure_rls' or e.evtfoid = to_regprocedure('public.rls_auto_enable()')::oid)
select nullif(concat_ws('; ',
  case when current_setting('transaction_read_only') <> 'on' then 'transaccion no read only' end,
  case when current_setting('server_version_num')::int / 10000 <> 17 then 'motor distinto de 17' end,
  case when (select hash from ex) is null then 'estado_esperado invalido' end,
  case when not exists (select 1 from f) then 'public.rls_auto_enable() ausente' end,
  case when (select count(*) from pg_proc where proname = 'rls_auto_enable') <> 1 then 'homonimos o cantidad distinta de 1' end,
  case when exists (select 1 from f where pg_get_userbyid(proowner) is distinct from 'postgres') then 'owner distinto de postgres' end,
  case when exists (select 1 from f where not prosecdef) then 'no es SECURITY DEFINER' end,
  case when exists (select 1 from f where prokind <> 'f') then 'prokind distinto de f' end,
  case when exists (select 1 from f join pg_language l on l.oid = f.prolang where l.lanname <> 'plpgsql') then 'lenguaje distinto de plpgsql' end,
  case when exists (select 1 from f where prorettype <> 'event_trigger'::regtype) then 'retorno distinto de event_trigger' end,
  case when exists (select 1 from f where prosqlbody is not null or probin is not null) then 'prosqlbody o probin no nulos' end,
  case when exists (select 1 from f, ex where encode(sha256(convert_to(f.prosrc, 'UTF8')), 'hex') <> ex.hash) then 'sha256 de prosrc distinto del esperado' end,
  case when exists (select 1 from f, ex where f.proconfig::text is distinct from ex.cfg) then 'proconfig distinto del esperado' end,
  case when exists (select 1 from f, lateral aclexplode(coalesce(f.proacl, acldefault('f', f.proowner))) a where a.grantee = 0) then 'EXECUTE para PUBLIC' end,
  case when coalesce(has_function_privilege('anon', to_regprocedure('public.rls_auto_enable()'), 'EXECUTE'), false)
         or coalesce(has_function_privilege('authenticated', to_regprocedure('public.rls_auto_enable()'), 'EXECUTE'), false)
         or coalesce(has_function_privilege('service_role', to_regprocedure('public.rls_auto_enable()'), 'EXECUTE'), false)
       then 'EXECUTE para anon/authenticated/service_role' end,
  case when exists (select 1 from pg_trigger t where t.tgfoid = to_regprocedure('public.rls_auto_enable()')) then 'trigger de tabla usa la funcion' end,
  case when (select count(*) from ev) <> 1 then 'ensure_rls ausente, duplicado o con otro event trigger sobre la funcion' end,
  case when exists (select 1 from ev where evtname <> 'ensure_rls') then 'event trigger adicional sobre la funcion' end,
  case when exists (select 1 from ev where pg_get_userbyid(evtowner) is distinct from 'postgres') then 'ensure_rls con owner distinto de postgres' end,
  case when exists (select 1 from ev where evtevent <> 'ddl_command_end') then 'ensure_rls con evento distinto de ddl_command_end' end,
  case when exists (select 1 from ev where evtenabled <> 'O') then 'ensure_rls no esta en estado O' end,
  case when exists (select 1 from ev where evttags is null or array_ndims(evttags) is distinct from 1
                       or array(select u from unnest(evttags) u order by u collate "C") <> array['CREATE TABLE','CREATE TABLE AS','SELECT INTO']) then 'tags de ensure_rls distintas de las tres exactas' end,
  case when exists (select 1 from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p') and not c.relrowsecurity) then 'tabla de public sin RLS' end,
  case when (select lista from lt) <> ''
        and :'rev_tok' is distinct from encode(sha256(convert_to((select lista from lt), 'UTF8')), 'hex')
       then 'compuerta LOGIN+TEMP: revision humana no confirmada (falta la huella o no coincide con la lista actual)' end
 ), '') as abortar,
 encode(sha256(convert_to((select lista from lt), 'UTF8')), 'hex') as digest_login_temp,
 pg_current_xact_id_if_assigned() is null as sin_escrituras;
