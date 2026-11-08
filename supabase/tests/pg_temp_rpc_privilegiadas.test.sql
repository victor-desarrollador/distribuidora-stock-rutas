-- pgTAP: endurecimiento pg_temp de las funciones privilegiadas — A1
-- (privado.usuario_actual() y privado.empresa_gestion_actual()).
-- Plan de remediación pg_temp, alternativa A; ADR-001 §17.1 y §17.3; Blueprint
-- §7.3. Matriz del plan: P1, P3, P4, P6, P7 y P8 para los auxiliares.
--
-- Este archivo crea los dominios hostiles ANTES de la primera llamada de la
-- sesión. El caso «dominios creados después de una llamada legítima» está en
-- pg_temp_rpc_privilegiadas_posterior.test.sql (cada archivo es otra sesión).
--
-- Alcance A1: las RPC SECURITY DEFINER y los auxiliares exigir_* todavía tienen
-- referencias propias sin calificar (A2, A3, B1). Por eso aquí no se llaman
-- RPC: las rutas positivas son la llamada directa a los auxiliares como
-- propietario_rpc, la vista privada (empresa_gestion_actual → usuario_actual) y
-- las políticas RLS de propietario_rpc (usuario_actual). La guardia estática P7
-- se aplica sólo a los dos auxiliares; A2/A3/B1 la extienden a sus funciones.
--
-- Sonda: el atacante modelado es authenticated (TEMP por PUBLIC). Crea en
-- pg_temp dominios uuid y jsonb cuyo CHECK llama a pg_temp.sonda(), que cuenta
-- en dos secuencias temporales (no transaccionales): una para el llamador
-- authenticated y otra para cualquier otro rol (privilegiado). El esperado de
-- la ruta privilegiada es 0 ejecuciones.
--
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(42);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final). Sin llamar a los
-- auxiliares: la primera llamada de la sesión ocurre con los dominios creados.
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('a7a7a7a7-0000-4000-8000-000000000000', 'Empresa A (test pg_temp)'),
  ('b7b7b7b7-0000-4000-8000-000000000000', 'Empresa B (test pg_temp)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('a7a7a7a7-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pgt.a1@usuarios.distribuidora.invalid', '{}'),
  ('a7a7a7a7-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'pgt.a2@usuarios.distribuidora.invalid', '{}'),
  ('b7b7b7b7-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pgt.b1@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('a7a7a7a7-0000-4000-8000-000000000001', 'a7a7a7a7-0000-4000-8000-000000000000', 'pgt.a1', 'Dueño A', 'dueno', true),
  ('a7a7a7a7-0000-4000-8000-000000000002', 'a7a7a7a7-0000-4000-8000-000000000000', 'pgt.a2', 'Vendedor A', 'vendedor_piloto', true),
  ('b7b7b7b7-0000-4000-8000-000000000001', 'b7b7b7b7-0000-4000-8000-000000000000', 'pgt.b1', 'Dueño B', 'dueno', true);

insert into public.productos (empresa_id, codigo, nombre, categoria, forma_venta, precio, creado_por) values
  ('a7a7a7a7-0000-4000-8000-000000000000', 'PGT-A1', 'Leche A', 'lacteos', 'unidad', 100, 'a7a7a7a7-0000-4000-8000-000000000001'),
  ('a7a7a7a7-0000-4000-8000-000000000000', 'PGT-A2', 'Jamón A', 'fiambres', 'peso', 200, 'a7a7a7a7-0000-4000-8000-000000000001'),
  ('b7b7b7b7-0000-4000-8000-000000000000', 'PGT-B1', 'Leche B', 'lacteos', 'unidad', 300, 'b7b7b7b7-0000-4000-8000-000000000001');

-- Huella de las filas de la empresa B (aislamiento: no deben cambiar).
create temp table huella_b as
select (select md5(string_agg(p::text, '|' order by p.usuario_id)) from public.perfiles p
         where p.empresa_id = 'b7b7b7b7-0000-4000-8000-000000000000') as perfiles,
       (select md5(string_agg(p::text, '|' order by p.id)) from public.productos p
         where p.empresa_id = 'b7b7b7b7-0000-4000-8000-000000000000') as productos;

-- ===========================================================================
-- P8 — catálogo: manifiesto, owner, ACL, oid/dependencias, SECURITY DEFINER
-- ===========================================================================
create temp table manifiesto_auxiliares as
select p.oid::regprocedure::text as firma,
       p.oid::regprocedure::text
       || '|' || p.proowner::regrole::text || '|' || l.lanname::text || '|' || p.prokind::text
       || '|' || p.prosecdef::text || '|' || p.proleakproof::text || '|' || p.proisstrict::text
       || '|' || p.proretset::text || '|' || p.provolatile::text || '|' || p.proparallel::text
       || '|' || p.pronargs::text || '|' || p.pronargdefaults::text || '|' || p.prorettype::regtype::text
       || '|' || coalesce(p.proargnames::text, '-') || '|' || coalesce(p.proargmodes::text, '-')
       || '|' || coalesce(nullif(p.prosupport::oid, 0::oid)::text, '-')
       || '|' || p.procost::text || '|' || p.prorows::text
       || '|' || coalesce(p.proconfig::text, '-')
       || '|' || coalesce(array_to_string(array(select a::text from unnest(p.proacl) a order by 1), ','), '-')
       || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-') || '|' || coalesce(p.probin, '-')
       || '|' || (p.prosqlbody is null)::text
       || '|' || encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex') as linea
  from pg_proc p join pg_language l on l.oid = p.prolang
 where p.oid in ('privado.usuario_actual()'::regprocedure, 'privado.empresa_gestion_actual()'::regprocedure);

select is(
  (select linea from manifiesto_auxiliares where firma = 'privado.usuario_actual()'),
  'privado.usuario_actual()|propietario_rpc|sql|f|false|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96',
  'P8: manifiesto de usuario_actual (owner, SECURITY INVOKER, STABLE, search_path vacío, ACL, cuerpo calificado)');

select is(
  (select linea from manifiesto_auxiliares where firma = 'privado.empresa_gestion_actual()'),
  'privado.empresa_gestion_actual()|propietario_rpc|sql|f|true|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|6d0a758d68ffaf8f575e1faebb132dc29cab4400e81c953b6dc73ed475fce7cc',
  'P8: manifiesto de empresa_gestion_actual sin cambios (SECURITY DEFINER, cuerpo de D-2)');

select is(
  (select prosrc from pg_proc where oid = 'privado.usuario_actual()'::regprocedure),
  E'\n  select coalesce(\n    nullif(current_setting(''request.jwt.claim.sub'', true), ''''),\n    (nullif(current_setting(''request.jwt.claims'', true), '''')::pg_catalog.jsonb ->> ''sub'')\n  )::pg_catalog.uuid\n',
  'P8: cuerpo de usuario_actual exacto, con los dos casts calificados');

select is(
  (select encode(sha256(convert_to(replace(prosrc, 'pg_catalog.', ''), 'UTF8')), 'hex')
     from pg_proc where oid = 'privado.usuario_actual()'::regprocedure),
  '6c5f9459584dc092061bdb45d5531759ad946b27eecd502059ca687b214070b0',
  'P8: equivalencia mecánica — quitando «pg_catalog.» se obtiene el cuerpo anterior (SHA-256 de 20261023140000)');

select is(
  (select (length(prosrc) - length(replace(prosrc, 'pg_catalog.', ''))) / length('pg_catalog.')
     from pg_proc where oid = 'privado.usuario_actual()'::regprocedure),
  2,
  'P8: exactamente 2 calificaciones en usuario_actual');

select ok(
  not exists (
    select 1
      from unnest(array['privado.usuario_actual()', 'privado.empresa_gestion_actual()']) f,
           unnest(array['anon', 'authenticated', 'service_role', 'lector_perfiles_rpc', 'postgres']) r
     where has_function_privilege(r, f::regprocedure, 'EXECUTE')),
  'P8/P11: ni anon, authenticated, service_role, lector_perfiles_rpc ni postgres ejecutan los auxiliares');

select ok(
  not has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
  and not has_schema_privilege('propietario_rpc', 'public', 'CREATE')
  and (select nspacl::text from pg_namespace where nspname = 'privado')
      = '{postgres=UC/postgres,authenticated=U/postgres,propietario_rpc=U/postgres}',
  'P8: sin CREATE residual de propietario_rpc y ACL de privado sin cambios');

select is(
  (select count(*)::int from pg_proc
    where proname in ('usuario_actual', 'empresa_gestion_actual')),
  2,
  'P8: sin sobrecargas ni homónimos de los auxiliares en ningún esquema');

select ok(
  not exists (
    select 1 from pg_proc p
     where p.prosecdef
       and p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
       and (p.pronamespace <> 'privado'::regnamespace
            or p.proowner <> 'propietario_rpc'::regrole
            or p.proconfig is distinct from array['search_path=""'])
       -- Única excepción: O-4.
       --   * VIGENTE — ADR-001 §18.2: la función y ensure_rls se conservan,
       --     sin EXECUTE para PUBLIC/anon/authenticated/service_role.
       --   * HISTÓRICO — B.1.2b/B.1.2c (06/11/2026): el cuerpo de staging
       --     325ae266… con search_path=pg_catalog; vulnerable (O4-PGTEMP), ya
       --     no se exime.
       --   * APROBADO SÓLO COMO NORMA (ADR-001 §18.2.1) — contrato RB + RA (hash
       --     e1b231fb… y search_path=pg_catalog, pg_temp): es el que se exige abajo.
       -- Se exime sólo public.rls_auto_enable(), identificada por OID y con el
       -- contrato completo de la función y de ensure_rls. Fuera de contrato no
       -- se exime y la aserción falla. En local la función no existe y la
       -- excepción no se usa. coalesce: un término NULL (p. ej. un elemento
       -- NULL en evttags) nunca exime.
       and not coalesce((
         p.oid = to_regprocedure('public.rls_auto_enable()')
         and p.prokind = 'f'
         and p.proowner = 'postgres'::regrole
         and p.prorettype = 'event_trigger'::regtype
         and p.proconfig = array['search_path=pg_catalog, pg_temp']
         and p.prolang = (select l.oid from pg_language l where l.lanname = 'plpgsql')
         and p.prosqlbody is null and p.probin is null
         and encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex')
             = 'e1b231fb7db1d25c9dfab71d09dbc968c092c00c0049aca1f529f7e79296fb6e'
         and not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                          where a.grantee = 0)
         and not has_function_privilege('anon', p.oid, 'EXECUTE')
         and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
         and not has_function_privilege('service_role', p.oid, 'EXECUTE')
         and not exists (select 1 from pg_trigger tg where tg.tgfoid = p.oid)
         and (select count(*) from pg_event_trigger t
               where t.evtfoid = p.oid or t.evtname = 'ensure_rls') = 1
         and exists (select 1 from pg_event_trigger t
                      where t.evtname = 'ensure_rls' and t.evtfoid = p.oid
                        and t.evtowner = 'postgres'::regrole
                        and t.evtevent = 'ddl_command_end'
                        and t.evtenabled = 'O'
                        and array_ndims(t.evttags) = 1
                        and array(select u.tag from unnest(t.evttags) u(tag) order by u.tag collate "C")
                            = array['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[])), false)),
  'P8: toda función SECURITY DEFINER de public/privado vive en privado, es de propietario_rpc y tiene search_path vacío (única excepción: public.rls_auto_enable() con el contrato O-4 completo)');

select ok(
  (select not prosecdef from pg_proc where oid = 'privado.usuario_actual()'::regprocedure)
  and (select prosecdef from pg_proc where oid = 'privado.empresa_gestion_actual()'::regprocedure),
  'P8: usuario_actual sigue SECURITY INVOKER y empresa_gestion_actual sigue SECURITY DEFINER');

-- oid: las políticas que nombran usuario_actual dependen del oid vigente
-- (CREATE OR REPLACE conserva el oid; un DROP/CREATE las habría roto).
select ok(
  (select count(*) from pg_policies
    where coalesce(qual, '') || coalesce(with_check, '') ~ 'privado\.usuario_actual\(\)') > 0
  and (select count(*) from pg_policies
        where coalesce(qual, '') || coalesce(with_check, '') ~ 'privado\.usuario_actual\(\)')
      = (select count(distinct d.objid) from pg_depend d
          where d.classid = 'pg_policy'::regclass
            and d.refclassid = 'pg_proc'::regclass
            and d.refobjid = 'privado.usuario_actual()'::regprocedure),
  'P8: toda política que usa usuario_actual depende del oid vigente');

select is(
  array(select po.polname::text from pg_depend d join pg_policy po on po.oid = d.objid
         where d.classid = 'pg_policy'::regclass
           and d.refobjid = 'privado.empresa_gestion_actual()'::regprocedure
         order by 1),
  array['perfiles_select_empresa_lector'],
  'P8: la política del lector depende del oid vigente de empresa_gestion_actual');

-- ===========================================================================
-- P7 — guardia estática (análisis léxico sin literales ni comentarios)
-- ===========================================================================
-- Cuenta: casts «::» sin esquema, CAST(...), %TYPE/%ROWTYPE y relaciones sin
-- esquema tras FROM/JOIN/INTO/UPDATE. Es deliberadamente estricta (marca
-- también palabras clave como ::integer). Limitación: es léxica; P1/P3/P6
-- cubren el comportamiento.
create function pg_temp.refs_sin_calificar(p_src pg_catalog.text)
returns pg_catalog.int4 language sql immutable as $f$
  select pg_catalog.count(*)::pg_catalog.int4
    from pg_catalog.regexp_matches(
           pg_catalog.regexp_replace(
             pg_catalog.regexp_replace(p_src, '''([^'']|'''')*''', '''''', 'g'),
             '--[^\n]*', '', 'g'),
           '(::\s*(?!pg_catalog\s*\.)[a-z_"])'
           || '|(\mcast\s*\()'
           || '|(%\s*(row)?type\M)'
           || '|(\m(from|join|into|update)\s+(?!(pg_catalog|public|privado|auth|extensions)\s*\.|\()[a-z_"])',
           'gi')
$f$;

select is(
  pg_temp.refs_sin_calificar((select prosrc from pg_proc where oid = 'privado.usuario_actual()'::regprocedure)),
  0,
  'P7: usuario_actual sin tipos, casts ni relaciones sin calificar');

select is(
  pg_temp.refs_sin_calificar((select prosrc from pg_proc where oid = 'privado.empresa_gestion_actual()'::regprocedure)),
  0,
  'P7: empresa_gestion_actual sin tipos, casts ni relaciones sin calificar');

-- Sensibilidad del detector: el cuerpo anterior (M1) y una calificación
-- escondida en un literal (M2) se detectan.
select is(
  pg_temp.refs_sin_calificar(E'\n  select coalesce(\n    nullif(current_setting(''request.jwt.claim.sub'', true), ''''),\n    (nullif(current_setting(''request.jwt.claims'', true), '''')::jsonb ->> ''sub'')\n  )::uuid\n'),
  2,
  'P7 (control M1): el detector encuentra los 2 casts del cuerpo anterior');

select is(
  pg_temp.refs_sin_calificar($m$ select 'x::pg_catalog.uuid'::uuid -- ::pg_catalog.uuid $m$),
  1,
  'P7 (control M2): una calificación dentro de un literal o comentario no oculta el cast sin calificar');

-- ===========================================================================
-- P1 — objetos hostiles de authenticated ANTES de la primera llamada
-- ===========================================================================
create temp table resultados (caso text, valor text);
grant all on resultados to public;

set local role authenticated;
create temp sequence sonda_privilegiada;
create temp sequence sonda_llamador;
create temp sequence control_directo;
create temp sequence control_rls;
create temp sequence control_mutante;
grant all on sequence sonda_privilegiada, sonda_llamador, control_directo, control_rls, control_mutante to public;
create function pg_temp.sonda() returns pg_catalog.bool language plpgsql as $f$
begin
  if current_user operator(pg_catalog.=) 'authenticated' then
    perform pg_catalog.nextval('pg_temp.sonda_llamador'::pg_catalog.regclass);
  else
    perform pg_catalog.nextval('pg_temp.sonda_privilegiada'::pg_catalog.regclass);
  end if;
  return true;
end $f$;
-- postgres tiene privilegios por defecto que quitan EXECUTE a PUBLIC: la sonda
-- la crea authenticated y la concede explícitamente.
grant execute on function pg_temp.sonda() to public;
create domain pg_temp.uuid as pg_catalog.uuid check (pg_temp.sonda());
create domain pg_temp.jsonb as pg_catalog.jsonb check (pg_temp.sonda());
reset role;

create function pg_temp.ejecuciones(p_secuencia pg_catalog.regclass) returns pg_catalog.int8
language plpgsql as $f$
declare v pg_catalog.int8;
begin
  execute pg_catalog.format('select case when is_called then last_value else 0 end from %s', p_secuencia) into v;
  return v;
end $f$;
create function pg_temp.reiniciar_sondas() returns pg_catalog.bool language sql as $f$
  select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null
     and pg_catalog.setval('pg_temp.sonda_llamador'::pg_catalog.regclass, 1, false) is not null
$f$;

select ok(
  (select count(*) from pg_type t
    where t.typnamespace = pg_my_temp_schema()
      and t.typname in ('uuid', 'jsonb') and t.typtype = 'd'
      and t.typowner = 'authenticated'::regrole) = 2
  and (select count(*) from pg_constraint c join pg_type t on t.oid = c.contypid
        where t.typnamespace = pg_my_temp_schema() and t.typname in ('uuid', 'jsonb')
          and pg_get_constraintdef(c.oid) ~ 'pg_temp\.sonda\(\)') = 2,
  'P1: dominios hostiles pg_temp.uuid y pg_temp.jsonb de authenticated, con CHECK que llama a la sonda');

-- ===========================================================================
-- P3 — rutas positivas como propietario_rpc (atraviesan los casts)
-- ===========================================================================
-- C1: claim JSON del dueño de A (atraviesa ::pg_catalog.jsonb y ::pg_catalog.uuid).
select pg_temp.reiniciar_sondas();
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims',
  '{"sub":"a7a7a7a7-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;
insert into pg_temp.resultados select 'c1', privado.usuario_actual()::pg_catalog.text;
reset role;
select is((select valor from resultados where caso = 'c1'), 'a7a7a7a7-0000-4000-8000-000000000001',
  'P3/C1: usuario_actual devuelve el sub del claim JSON');
select is(pg_temp.ejecuciones('pg_temp.sonda_privilegiada'), 0::bigint,
  'P3/C1: 0 ejecuciones del código temporal como propietario_rpc');

-- C2: claim heredado request.jwt.claim.sub (sólo ::pg_catalog.uuid).
select pg_temp.reiniciar_sondas();
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', 'a7a7a7a7-0000-4000-8000-000000000001', true);
set local role propietario_rpc;
insert into pg_temp.resultados select 'c2', privado.usuario_actual()::pg_catalog.text;
reset role;
select set_config('request.jwt.claim.sub', '', true);
select is((select valor from resultados where caso = 'c2'), 'a7a7a7a7-0000-4000-8000-000000000001',
  'P3/C2: usuario_actual devuelve el claim sub heredado');
select is(pg_temp.ejecuciones('pg_temp.sonda_privilegiada'), 0::bigint,
  'P3/C2: 0 ejecuciones del código temporal como propietario_rpc');

-- C3: claim JSON sin sub (el valor nulo también atraviesa ambos casts).
select pg_temp.reiniciar_sondas();
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
set local role propietario_rpc;
insert into pg_temp.resultados select 'c3', coalesce(privado.usuario_actual()::pg_catalog.text, 'nulo');
reset role;
select is((select valor from resultados where caso = 'c3'), 'nulo',
  'P3/C3: usuario_actual es nulo sin sub');
select is(pg_temp.ejecuciones('pg_temp.sonda_privilegiada'), 0::bigint,
  'P3/C3: 0 ejecuciones del código temporal como propietario_rpc');

-- C4–C6: dueño de A por empresa_gestion_actual, la vista y las políticas RLS.
select pg_temp.reiniciar_sondas();
select set_config('request.jwt.claims',
  '{"sub":"a7a7a7a7-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;
insert into pg_temp.resultados select 'c4', privado.empresa_gestion_actual()::pg_catalog.text;
insert into pg_temp.resultados
  select 'c5', pg_catalog.string_agg(v.empresa_id::pg_catalog.text || ':' || v.rol::pg_catalog.text, ','
                                     order by v.rol::pg_catalog.text)
    from privado.perfiles_empresa_gestion v;
insert into pg_temp.resultados
  select 'c6', pg_catalog.string_agg(p.codigo, ',' order by p.codigo)
    from public.productos p where p.codigo operator(pg_catalog.~~) 'PGT-%';
reset role;
select is((select valor from resultados where caso = 'c4'), 'a7a7a7a7-0000-4000-8000-000000000000',
  'P3/C4: empresa_gestion_actual devuelve la empresa del dueño de A');
select is((select valor from resultados where caso = 'c5'),
  'a7a7a7a7-0000-4000-8000-000000000000:dueno,a7a7a7a7-0000-4000-8000-000000000000:vendedor_piloto',
  'P3/C5: la vista privada (empresa_gestion_actual → usuario_actual) muestra sólo perfiles de A');
select is((select valor from resultados where caso = 'c6'), 'PGT-A1,PGT-A2',
  'P3/C6: RLS de propietario_rpc (usuario_actual) muestra sólo productos de A');
select is(pg_temp.ejecuciones('pg_temp.sonda_privilegiada'), 0::bigint,
  'P3/C4–C6: 0 ejecuciones del código temporal como propietario_rpc (helper, vista y RLS)');

-- ===========================================================================
-- P4 — aislamiento por empresa_id
-- ===========================================================================
-- C7: claims de A con IDs de B.
select pg_temp.reiniciar_sondas();
set local role propietario_rpc;
insert into pg_temp.resultados
  select 'c7_productos', pg_catalog.count(*)::pg_catalog.text from public.productos p
   where p.empresa_id operator(pg_catalog.=) 'b7b7b7b7-0000-4000-8000-000000000000'::pg_catalog.uuid;
insert into pg_temp.resultados
  select 'c7_perfiles', pg_catalog.count(*)::pg_catalog.text from privado.perfiles_empresa_gestion v
   where v.empresa_id operator(pg_catalog.=) 'b7b7b7b7-0000-4000-8000-000000000000'::pg_catalog.uuid;
reset role;
select is((select valor from resultados where caso = 'c7_productos'), '0',
  'P4/C7: con claims de A no se ve ningún producto de B por RLS');
select is((select valor from resultados where caso = 'c7_perfiles'), '0',
  'P4/C7: con claims de A la vista no muestra perfiles de B');

-- C8: claims de B.
select set_config('request.jwt.claims',
  '{"sub":"b7b7b7b7-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;
insert into pg_temp.resultados select 'c8_empresa', privado.empresa_gestion_actual()::pg_catalog.text;
insert into pg_temp.resultados
  select 'c8_productos', pg_catalog.string_agg(p.codigo, ',' order by p.codigo)
    from public.productos p where p.codigo operator(pg_catalog.~~) 'PGT-%';
reset role;
select is((select valor from resultados where caso = 'c8_empresa'), 'b7b7b7b7-0000-4000-8000-000000000000',
  'P4/C8: con claims de B, empresa_gestion_actual devuelve B');
select is((select valor from resultados where caso = 'c8_productos'), 'PGT-B1',
  'P4/C8: con claims de B, RLS muestra sólo productos de B');

-- C9: vendedor de A (sin gestión): helper nulo y vista vacía.
select set_config('request.jwt.claims',
  '{"sub":"a7a7a7a7-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role propietario_rpc;
insert into pg_temp.resultados select 'c9_empresa', coalesce(privado.empresa_gestion_actual()::pg_catalog.text, 'nulo');
insert into pg_temp.resultados select 'c9_vista', pg_catalog.count(*)::pg_catalog.text from privado.perfiles_empresa_gestion;
reset role;
select is((select valor from resultados where caso = 'c9_empresa'), 'nulo',
  'P4/C9: para un vendedor, empresa_gestion_actual es nulo');
select is((select valor from resultados where caso = 'c9_vista'), '0',
  'P4/C9: para un vendedor, la vista no muestra perfiles');

select is(pg_temp.ejecuciones('pg_temp.sonda_privilegiada'), 0::bigint,
  'P4/C7–C9: 0 ejecuciones del código temporal como propietario_rpc');
select is(pg_temp.ejecuciones('pg_temp.sonda_llamador'), 0::bigint,
  'P1–P4: el código temporal tampoco se ejecutó como authenticated en estas rutas');

select is(
  (select (select md5(string_agg(p::text, '|' order by p.usuario_id)) from public.perfiles p
            where p.empresa_id = 'b7b7b7b7-0000-4000-8000-000000000000')
          || '/' ||
          (select md5(string_agg(p::text, '|' order by p.id)) from public.productos p
            where p.empresa_id = 'b7b7b7b7-0000-4000-8000-000000000000')),
  (select perfiles || '/' || productos from huella_b),
  'P4: las filas de perfiles y productos de B no cambiaron');

-- ===========================================================================
-- P6 — control del detector: reintroducir el cuerpo anterior (sin calificar)
-- ===========================================================================
-- En un savepoint: CREATE transitorio, SET ROLE propietario_rpc (O-3) y el
-- cuerpo vigente antes de A1, byte a byte. Las mediciones se guardan en
-- secuencias (no transaccionales) y se afirman después del ROLLBACK TO, porque
-- revertir el savepoint también revierte los resultados de pgTAP.
select set_config('request.jwt.claims',
  '{"sub":"a7a7a7a7-0000-4000-8000-000000000001","role":"authenticated"}', true);
savepoint control_m1;
grant create on schema privado to propietario_rpc;
set local role propietario_rpc;
create or replace function privado.usuario_actual()
returns pg_catalog.uuid language sql stable security invoker
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;
reset role;
revoke create on schema privado from propietario_rpc;
insert into pg_temp.resultados
  select 'm1_hash', encode(sha256(convert_to(prosrc, 'UTF8')), 'hex')
    from pg_proc where oid = 'privado.usuario_actual()'::regprocedure;
select pg_temp.reiniciar_sondas();
set local role propietario_rpc;
select privado.usuario_actual() is not null;
reset role;
select setval('pg_temp.control_directo', greatest(pg_temp.ejecuciones('pg_temp.sonda_privilegiada'), 1),
              pg_temp.ejecuciones('pg_temp.sonda_privilegiada') > 0);
select pg_temp.reiniciar_sondas();
set local role propietario_rpc;
select count(*) from public.productos;
reset role;
select setval('pg_temp.control_rls', greatest(pg_temp.ejecuciones('pg_temp.sonda_privilegiada'), 1),
              pg_temp.ejecuciones('pg_temp.sonda_privilegiada') > 0);
-- El mutante es exactamente el cuerpo anterior (se registra antes del rollback
-- en una secuencia: 1 = coincide).
select setval('pg_temp.control_mutante', 1,
              (select valor from resultados where caso = 'm1_hash')
                = '6c5f9459584dc092061bdb45d5531759ad946b27eecd502059ca687b214070b0');
rollback to savepoint control_m1;

select ok(pg_temp.ejecuciones('pg_temp.control_mutante') = 1,
  'P6: el mutante reintroducido es el cuerpo anterior a A1, byte a byte');
select cmp_ok(pg_temp.ejecuciones('pg_temp.control_directo'), '>', 0::bigint,
  'P6: con un cast sin calificar, la llamada directa ejecuta el código temporal como propietario_rpc (el detector funciona)');
select cmp_ok(pg_temp.ejecuciones('pg_temp.control_rls'), '>', 0::bigint,
  'P6: con un cast sin calificar, la ruta RLS de propietario_rpc ejecuta el código temporal (el detector funciona)');

select ok(
  (select encode(sha256(convert_to(prosrc, 'UTF8')), 'hex') from pg_proc
    where oid = 'privado.usuario_actual()'::regprocedure)
    = '2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96'
  and not has_schema_privilege('propietario_rpc', 'privado', 'CREATE'),
  'P6: tras el rollback vuelve el cuerpo calificado y no queda CREATE transitorio');

-- Después del control, la ruta calificada sigue en 0 (el caché no reintroduce
-- el problema).
select pg_temp.reiniciar_sondas();
set local role propietario_rpc;
insert into pg_temp.resultados select 'post_m1', privado.usuario_actual()::pg_catalog.text;
insert into pg_temp.resultados select 'post_m1_rls', pg_catalog.count(*)::pg_catalog.text
  from public.productos p where p.codigo operator(pg_catalog.~~) 'PGT-%';
reset role;
select is((select valor || '/' || (select valor from resultados where caso = 'post_m1_rls')
             from resultados where caso = 'post_m1'),
  'a7a7a7a7-0000-4000-8000-000000000001/2',
  'P6: después del control, usuario_actual y RLS devuelven lo esperado');
select is(pg_temp.ejecuciones('pg_temp.sonda_privilegiada'), 0::bigint,
  'P6: después del control, 0 ejecuciones del código temporal como propietario_rpc');

select * from finish();

rollback;
