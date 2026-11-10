-- Q3 — event triggers y triggers de tabla que referencian la función. Solo lectura.
select e.evtname, e.evtowner::regrole::text as owner, e.evtevent, e.evtfoid::regprocedure::text as funcion,
       e.evtenabled::text as habilitado, e.evttags
  from pg_event_trigger e
 order by e.evtname;
select count(*) as triggers_de_tabla_que_usan_la_funcion
  from pg_trigger t
 where t.tgfoid = to_regprocedure('public.rls_auto_enable()');
