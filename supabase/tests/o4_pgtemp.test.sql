-- pgTAP RUTINARIO: contrato de public.rls_auto_enable() remediada contra
-- O4-PGTEMP (RB + RA). Sólo LECTURA del catálogo: no crea objetos hostiles, no
-- reemplaza la función, no ejecuta ataques ni DDL propio (sólo la extensión
-- pgtap y las tablas temporales internas de pgTAP, como todo el árbol). Ejecutar sólo en local: `supabase test db`.
--
-- Gobernanza:
--   * ADR-001 §18.2 VIGENTE (O-4): se conservan rls_auto_enable() y
--     ensure_rls; EXECUTE revocado a PUBLIC/anon/authenticated/service_role;
--     no se modifica el comportamiento funcional del event trigger.
--   * El contrato RB + RA que verifica este archivo (SHA-256 de prosrc
--     e1b231fb…, search_path = pg_catalog, pg_temp) es una ENMIENDA PROPUESTA,
--     NO APROBADA. Su implementación local es la migración
--     20261110120000_o4_pgtemp_remediacion.sql.
--   * El cuerpo original de staging (325ae266…, search_path = pg_catalog) es
--     vulnerable a la resolución de tipos en pg_temp y se rechaza.
--
-- La función sólo existe en el proyecto alojado (y en laboratorios). Donde no
-- existe, las aserciones de contrato se informan como SKIP, no como PASS.
--
-- La prueba DINÁMICA de explotación NO vive aquí: está en
-- supabase/laboratorio/o4-pgtemp/ y sólo corre en un contenedor descartable
-- sin red, creado y verificado por su propio arnés.

begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- 1. Coherencia (válida en cualquier entorno).
select is(
  pg_catalog.to_regprocedure('public.rls_auto_enable()') is not null,
  exists (select 1 from pg_catalog.pg_event_trigger where evtname = 'ensure_rls'),
  'O-4: rls_auto_enable() y ensure_rls están presentes o ausentes juntos');

-- 2. Identidad remediada (RB).
select case when pg_catalog.to_regprocedure('public.rls_auto_enable()') is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else is((select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex')
             from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('public.rls_auto_enable()')),
          'e1b231fb7db1d25c9dfab71d09dbc968c092c00c0049aca1f529f7e79296fb6e',
          'O4-PGTEMP: SHA-256 de prosrc = contrato RB propuesto (e1b231fb…)') end;

-- 3. Rechazo explícito del cuerpo original vulnerable.
select case when pg_catalog.to_regprocedure('public.rls_auto_enable()') is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else isnt((select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex')
               from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('public.rls_auto_enable()')),
            '325ae266d9b166715ef5230ceaf7ff9d523e483cf5610dfb9779ab3f183f4af9',
            'O4-PGTEMP: el cuerpo original vulnerable (325ae266…) no está presente') end;

-- 4. search_path exacto (RA): pg_temp explícito y último.
select case when pg_catalog.to_regprocedure('public.rls_auto_enable()') is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else is((select p.proconfig::pg_catalog.text from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('public.rls_auto_enable()')),
          '{"search_path=pg_catalog, pg_temp"}',
          'O4-PGTEMP: proconfig exacto {search_path=pg_catalog, pg_temp} (RA)') end;

-- 5. Referencias de tipo calificadas en el cuerpo (RB), comprobación textual.
select case when pg_catalog.to_regprocedure('public.rls_auto_enable()') is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else ok((select p.prosrc ~ '\mcmd\s+pg_catalog\.record\s*;'
                  and p.prosrc ~ '\mtbl\s+pg_catalog\.name\s*;'
                  and p.prosrc ~ 'FROM\s+pg_catalog\.pg_event_trigger_ddl_commands\(\)'
                  and p.prosrc !~ '\m(cmd|tbl)\s+(record|name)\s*;'
             from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('public.rls_auto_enable()')),
          'O4-PGTEMP: record, name y pg_event_trigger_ddl_commands() calificados con pg_catalog') end;

-- 6. Atributos de la función.
select case when pg_catalog.to_regprocedure('public.rls_auto_enable()') is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else ok((select p.prosecdef and p.prokind = 'f'
                  and p.proowner = 'postgres'::pg_catalog.regrole
                  and p.prorettype = 'pg_catalog.event_trigger'::pg_catalog.regtype
                  and l.lanname = 'plpgsql'
                  and p.prosqlbody is null and p.probin is null
                  and (select pg_catalog.count(*) from pg_catalog.pg_proc x where x.proname = 'rls_auto_enable') = 1
             from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid = p.prolang
            where p.oid = pg_catalog.to_regprocedure('public.rls_auto_enable()')),
          'O-4: SECURITY DEFINER, prokind f, owner postgres, event_trigger, plpgsql, sin homónimos') end;

-- 7. Privilegios: sin EXECUTE para PUBLIC ni para los roles de la Data API.
select case when pg_catalog.to_regprocedure('public.rls_auto_enable()') is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else ok(not exists (select 1 from pg_catalog.pg_proc p,
                        pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
                       where p.oid = pg_catalog.to_regprocedure('public.rls_auto_enable()') and a.grantee = 0 and a.privilege_type = 'EXECUTE')
          and not pg_catalog.has_function_privilege('anon', pg_catalog.to_regprocedure('public.rls_auto_enable()'), 'EXECUTE')
          and not pg_catalog.has_function_privilege('authenticated', pg_catalog.to_regprocedure('public.rls_auto_enable()'), 'EXECUTE')
          and not pg_catalog.has_function_privilege('service_role', pg_catalog.to_regprocedure('public.rls_auto_enable()'), 'EXECUTE'),
          'O-4: sin EXECUTE para PUBLIC, anon, authenticated ni service_role') end;

-- 8. Event trigger: único, owner postgres, ddl_command_end, O y 3 tags exactas.
select case when pg_catalog.to_regprocedure('public.rls_auto_enable()') is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else ok(exists (select 1 from pg_catalog.pg_event_trigger t
                   where t.evtname = 'ensure_rls' and t.evtfoid = pg_catalog.to_regprocedure('public.rls_auto_enable()')
                     and t.evtowner = 'postgres'::pg_catalog.regrole
                     and t.evtevent = 'ddl_command_end' and t.evtenabled = 'O'
                     and pg_catalog.array_ndims(t.evttags) = 1
                     and array(select u from pg_catalog.unnest(t.evttags) u order by u collate pg_catalog."C")
                         = array['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::pg_catalog.text[])
          and (select pg_catalog.count(*) from pg_catalog.pg_event_trigger t
                where t.evtfoid = pg_catalog.to_regprocedure('public.rls_auto_enable()') or t.evtname = 'ensure_rls') = 1
          and not exists (select 1 from pg_catalog.pg_trigger tg where tg.tgfoid = pg_catalog.to_regprocedure('public.rls_auto_enable()')),
          'O-4: ensure_rls único, owner postgres, ddl_command_end, evtenabled O y exactamente 3 tags') end;

-- 9. Ninguna otra función SECURITY DEFINER de public (válida en cualquier entorno).
select is(
  (select coalesce(pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::pg_catalog.text, ', '), '')
     from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::pg_catalog.regnamespace and p.prosecdef
      and p.oid is distinct from pg_catalog.to_regprocedure('public.rls_auto_enable()')),
  '',
  'O-4: rls_auto_enable() es la única función SECURITY DEFINER de public');

select * from finish();

rollback;
