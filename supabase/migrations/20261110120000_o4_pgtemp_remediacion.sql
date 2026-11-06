-- O4-PGTEMP — remediación RB + RA de public.rls_auto_enable() (O-4).
-- Estado: implementación LOCAL para validación en laboratorio. La enmienda de
-- ADR-001 §18.2 que la respalda es una PROPUESTA NO APROBADA; no autoriza
-- staging ni producción. Forward-only (ADR-009): no hay rollback y está
-- prohibido restaurar el cuerpo anterior (325ae266…), que es vulnerable.
--
-- Problema: el cuerpo de staging declara «cmd record» y «tbl name» sin
-- esquema; con search_path = pg_catalog, pg_temp se busca PRIMERO para tipos,
-- así que dominios de pg_temp podían ejecutar código como postgres.
--   RB: cuerpo con 3 referencias calificadas (pg_catalog.record,
--       pg_catalog.name, pg_catalog.pg_event_trigger_ddl_commands());
--       SHA-256 de prosrc e1b231fb7db1d25c9dfab71d09dbc968c092c00c0049aca1f529f7e79296fb6e.
--   RA: search_path = pg_catalog, pg_temp (pg_temp explícito y último).
--
-- Comportamiento:
--   * función ausente y sin ensure_rls ni homónimos → sin cambios (NOTICE): local;
--   * ensure_rls u homónimos sin la función           → ERROR;
--   * contrato remediado completo ya presente           → sin cambios (NOTICE);
--   * contrato original EXACTO (325ae266…)             → CREATE OR REPLACE y
--     verificación posterior (OID, hash, proconfig, ACL, contrato y trigger);
--   * cualquier otro estado                             → ERROR, sin cambios.
-- No toca tablas, grants, roles ni service_role. Exige current_user postgres
-- (owner de la función). Un único DO: atómico; todo error revierte.
do $mig$
declare
  c_hash_original  constant pg_catalog.text := '325ae266d9b166715ef5230ceaf7ff9d523e483cf5610dfb9779ab3f183f4af9';
  c_hash_remediado constant pg_catalog.text := 'e1b231fb7db1d25c9dfab71d09dbc968c092c00c0049aca1f529f7e79296fb6e';
  c_cfg_original   constant pg_catalog.text[] := array['search_path=pg_catalog'];
  c_cfg_remediado  constant pg_catalog.text[] := array['search_path=pg_catalog, pg_temp'];
  c_tags           constant pg_catalog.text[] := array['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO'];
  v_oid      pg_catalog.oid;
  v_oid_post pg_catalog.oid;
  v_hash     pg_catalog.text;
  v_cfg      pg_catalog.text[];
  v_acl      pg_catalog.aclitem[];
  v_acl_post pg_catalog.aclitem[];
  v_err      pg_catalog.text;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('o4_pgtemp_remediacion'));

  v_oid := pg_catalog.to_regprocedure('public.rls_auto_enable()');
  if v_oid is null then
    if exists (select 1 from pg_catalog.pg_event_trigger where evtname = 'ensure_rls') then
      raise exception 'o4_pgtemp: ensure_rls existe sin public.rls_auto_enable(): estado incoherente, no se modifica nada';
    end if;
    if exists (select 1 from pg_catalog.pg_proc where proname = 'rls_auto_enable') then
      raise exception 'o4_pgtemp: hay homónimos de rls_auto_enable sin public.rls_auto_enable(): definición desconocida, no se modifica nada';
    end if;
    raise notice 'o4_pgtemp: O-4 ausente (entorno local): sin cambios';
    return;
  end if;

  if current_user::pg_catalog.text <> 'postgres' then
    raise exception 'o4_pgtemp: debe ejecutarse como postgres (owner de la función); current_user=%', current_user;
  end if;

  select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex'), p.proconfig, p.proacl
    into v_hash, v_cfg, v_acl
    from pg_catalog.pg_proc p where p.oid = v_oid;

  select pg_catalog.concat_ws('; ',
           case when not p.prosecdef then 'no es SECURITY DEFINER' end,
           case when p.prokind <> 'f' then 'prokind ' || p.prokind::pg_catalog.text end,
           case when p.proowner <> 'postgres'::pg_catalog.regrole then 'owner ' || p.proowner::pg_catalog.regrole::pg_catalog.text end,
           case when p.prorettype <> 'pg_catalog.event_trigger'::pg_catalog.regtype then 'retorno distinto' end,
           case when l.lanname <> 'plpgsql' then 'lenguaje ' || l.lanname::pg_catalog.text end,
           case when p.prosqlbody is not null or p.probin is not null then 'prosqlbody/probin' end,
           case when exists (select 1 from pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
                              where a.grantee = 0) then 'EXECUTE para PUBLIC' end,
           case when pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
                  or pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                  or pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE') then 'EXECUTE para roles de la Data API' end,
           case when (select pg_catalog.count(*) from pg_catalog.pg_proc x where x.proname = 'rls_auto_enable') <> 1 then 'homónimos' end,
           case when exists (select 1 from pg_catalog.pg_trigger t where t.tgfoid = p.oid) then 'trigger de tabla' end,
           case when (select pg_catalog.count(*) from pg_catalog.pg_event_trigger t
                       where t.evtfoid = p.oid or t.evtname = 'ensure_rls') <> 1
                  or not exists (select 1 from pg_catalog.pg_event_trigger t
                                  where t.evtname = 'ensure_rls' and t.evtfoid = p.oid
                                    and t.evtowner = 'postgres'::pg_catalog.regrole
                                    and t.evtevent = 'ddl_command_end' and t.evtenabled = 'O'
                                    and pg_catalog.array_ndims(t.evttags) = 1
                                    and array(select u from pg_catalog.unnest(t.evttags) u order by u collate pg_catalog."C")
                                        = c_tags)
                then 'ensure_rls fuera de contrato' end)
    into v_err
    from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid = p.prolang
   where p.oid = v_oid;
  if v_err <> '' then
    raise exception 'o4_pgtemp: definición desconocida, no se modifica nada: %', v_err;
  end if;

  if v_hash = c_hash_remediado and v_cfg is not distinct from c_cfg_remediado then
    raise notice 'o4_pgtemp: contrato remediado ya presente: sin cambios';
    return;
  end if;
  if v_hash is distinct from c_hash_original or v_cfg is distinct from c_cfg_original then
    raise exception 'o4_pgtemp: definición desconocida (sha256 %, proconfig %): no se modifica nada', v_hash, v_cfg;
  end if;

  -- Reemplazo (mismo OID, owner, ACL y dependencia del trigger).
  create or replace function public.rls_auto_enable() returns event_trigger
    language plpgsql security definer set search_path = pg_catalog, pg_temp
    as $o4$
DECLARE
  cmd pg_catalog.record;
  tbl pg_catalog.name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_catalog.pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$o4$;

  -- Verificación posterior: cualquier desvío aborta y revierte todo.
  v_oid_post := pg_catalog.to_regprocedure('public.rls_auto_enable()');
  if v_oid_post is distinct from v_oid then
    raise exception 'o4_pgtemp: el OID cambió (% → %)', v_oid, v_oid_post;
  end if;
  select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex'), p.proconfig, p.proacl
    into v_hash, v_cfg, v_acl_post
    from pg_catalog.pg_proc p where p.oid = v_oid;
  if v_hash is distinct from c_hash_remediado then
    raise exception 'o4_pgtemp: hash posterior inesperado %', v_hash;
  end if;
  if v_cfg is distinct from c_cfg_remediado then
    raise exception 'o4_pgtemp: proconfig posterior inesperado %', v_cfg;
  end if;
  if v_acl_post is distinct from v_acl then
    raise exception 'o4_pgtemp: la ACL cambió (% → %)', v_acl, v_acl_post;
  end if;
  select pg_catalog.concat_ws('; ',
           case when not p.prosecdef then 'no es SECURITY DEFINER' end,
           case when p.prokind <> 'f' then 'prokind ' || p.prokind::pg_catalog.text end,
           case when p.proowner <> 'postgres'::pg_catalog.regrole then 'owner ' || p.proowner::pg_catalog.regrole::pg_catalog.text end,
           case when p.prorettype <> 'pg_catalog.event_trigger'::pg_catalog.regtype then 'retorno distinto' end,
           case when l.lanname <> 'plpgsql' then 'lenguaje ' || l.lanname::pg_catalog.text end,
           case when p.prosqlbody is not null or p.probin is not null then 'prosqlbody/probin' end,
           case when exists (select 1 from pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
                              where a.grantee = 0) then 'EXECUTE para PUBLIC' end,
           case when pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
                  or pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                  or pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE') then 'EXECUTE para roles de la Data API' end,
           case when (select pg_catalog.count(*) from pg_catalog.pg_proc x where x.proname = 'rls_auto_enable') <> 1 then 'homónimos' end,
           case when exists (select 1 from pg_catalog.pg_trigger t where t.tgfoid = p.oid) then 'trigger de tabla' end,
           case when (select pg_catalog.count(*) from pg_catalog.pg_event_trigger t
                       where t.evtfoid = p.oid or t.evtname = 'ensure_rls') <> 1
                  or not exists (select 1 from pg_catalog.pg_event_trigger t
                                  where t.evtname = 'ensure_rls' and t.evtfoid = p.oid
                                    and t.evtowner = 'postgres'::pg_catalog.regrole
                                    and t.evtevent = 'ddl_command_end' and t.evtenabled = 'O'
                                    and pg_catalog.array_ndims(t.evttags) = 1
                                    and array(select u from pg_catalog.unnest(t.evttags) u order by u collate pg_catalog."C")
                                        = c_tags)
                then 'ensure_rls fuera de contrato' end)
    into v_err
    from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid = p.prolang
   where p.oid = v_oid;
  if v_err <> '' then
    raise exception 'o4_pgtemp: contrato posterior incumplido: %', v_err;
  end if;
  raise notice 'o4_pgtemp: remediación aplicada (sha256 %, proconfig %)', v_hash, v_cfg;
end
$mig$;
