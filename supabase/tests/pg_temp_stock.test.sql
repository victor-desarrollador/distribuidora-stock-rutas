-- pgTAP: endurecimiento pg_temp de las RPC de Stock — A3 (plan de remediación
-- pg_temp, alternativa A; ADR-001 §17.1 y §17.3; Blueprint §7.3 y §12 Stock).
-- Objetos hostiles creados ANTES de la primera llamada de la sesión; el caso
-- «después de una llamada legítima» está en pg_temp_stock_posterior.test.sql.
--
-- Atacante modelado: authenticated (TEMP por PUBLIC). Crea en pg_temp dominios
-- uuid, text, date y jsonb cuyo CHECK llama a pg_temp.sonda() (secuencias
-- temporales, no transaccionales: una para authenticated y otra para cualquier
-- otro rol), vistas homónimas de las tablas que tocan estas RPC, funciones
-- homónimas (btrim, encode) y un operador = para text. Esperado: 0 ejecuciones
-- como propietario_rpc, mismas huellas v1 y mismos movimientos.
--
-- Como en A2: pgTAP declara variables «text» sin esquema, así que no se lo
-- llama mientras existen los objetos hostiles; se mide con pg_temp.intentar(),
-- se eliminan los objetos y recién entonces se afirma. Un DROP inocuo previo
-- compila los event triggers de sql_drop de la plataforma antes de los dominios.
--
-- Alcance A3: registrar_ingreso, mover_a_cuarentena y registrar_merma. Las
-- jornadas (B1) quedan fuera.
--
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final). Ninguna RPC se
-- llama antes de crear los objetos hostiles.
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('a3a3a3a3-0000-4000-8000-000000000000', 'Empresa A (test pg_temp A3)'),
  ('b3b3b3b3-0000-4000-8000-000000000000', 'Empresa B (test pg_temp A3)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('a3a3a3a3-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pga3.a1@usuarios.distribuidora.invalid', '{}'),
  ('a3a3a3a3-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'pga3.a2@usuarios.distribuidora.invalid', '{}'),
  ('a3a3a3a3-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'pga3.a3@usuarios.distribuidora.invalid', '{}'),
  ('b3b3b3b3-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pga3.b1@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('a3a3a3a3-0000-4000-8000-000000000001', 'a3a3a3a3-0000-4000-8000-000000000000', 'pga3.a1', 'Dueño A', 'dueno', true),
  ('a3a3a3a3-0000-4000-8000-000000000002', 'a3a3a3a3-0000-4000-8000-000000000000', 'pga3.a2', 'Encargado A', 'encargado', true),
  ('a3a3a3a3-0000-4000-8000-000000000003', 'a3a3a3a3-0000-4000-8000-000000000000', 'pga3.a3', 'Vendedor A', 'vendedor_piloto', true),
  ('b3b3b3b3-0000-4000-8000-000000000001', 'b3b3b3b3-0000-4000-8000-000000000000', 'pga3.b1', 'Dueño B', 'dueno', true);

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('a3a3a3a3-0000-4000-8000-0000000000f1', 'a3a3a3a3-0000-4000-8000-000000000000', 'PGA3-A1', 'Leche A', 'lacteos', 'unidad', 100, true, 'a3a3a3a3-0000-4000-8000-000000000001'),
  ('a3a3a3a3-0000-4000-8000-0000000000f2', 'a3a3a3a3-0000-4000-8000-000000000000', 'PGA3-A2', 'Leche A inactiva', 'lacteos', 'unidad', 100, false, 'a3a3a3a3-0000-4000-8000-000000000001'),
  ('b3b3b3b3-0000-4000-8000-0000000000f1', 'b3b3b3b3-0000-4000-8000-000000000000', 'PGA3-B1', 'Leche B', 'lacteos', 'unidad', 300, true, 'b3b3b3b3-0000-4000-8000-000000000001');

insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('a3a3a3a3-0000-4000-8000-0000000000d1', 'a3a3a3a3-0000-4000-8000-000000000000', 'deposito', null),
  ('a3a3a3a3-0000-4000-8000-0000000000c1', 'a3a3a3a3-0000-4000-8000-000000000000', 'cuarentena', null),
  ('b3b3b3b3-0000-4000-8000-0000000000d1', 'b3b3b3b3-0000-4000-8000-000000000000', 'deposito', null),
  ('b3b3b3b3-0000-4000-8000-0000000000c1', 'b3b3b3b3-0000-4000-8000-000000000000', 'cuarentena', null);

create temp table huella_b as
select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.productos t
         where t.empresa_id = 'b3b3b3b3-0000-4000-8000-000000000000')
       || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.ubicaciones t
                   where t.empresa_id = 'b3b3b3b3-0000-4000-8000-000000000000')
       || '/' || (select count(*)::text from public.operaciones t
                   where t.empresa_id = 'b3b3b3b3-0000-4000-8000-000000000000')
       || '/' || (select count(*)::text from public.movimientos_stock t
                   where t.empresa_id = 'b3b3b3b3-0000-4000-8000-000000000000') as huella;

-- ===========================================================================
-- P8 — catálogo (antes de los objetos hostiles; no se llama ninguna RPC)
-- ===========================================================================
select is(
  (select string_agg(p.oid::regprocedure::text || '|' || encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex'), ','
                     order by p.oid::regprocedure::text)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('registrar_ingreso', 'mover_a_cuarentena', 'registrar_merma')),
  'privado.mover_a_cuarentena(uuid,uuid,uuid,integer,text)|1e27e5ae6d3067466ca679025d2e31b0384a8f9e5a69f70f856292a6ffbbb380,privado.registrar_ingreso(uuid,uuid,integer,text)|b87c32fb38443dbe57abfc19ddce449a0d05d2c567a499165c09ba6a2ef9ece6,privado.registrar_merma(uuid,uuid,uuid,integer,text,text)|767897feea86d00edfba693f5291e043096800c1605a43ad6ceca8316f846322',
  'P8: los 3 cuerpos son exactamente los de A3 (SHA-256)');

select is(
  (select string_agg(p.oid::regprocedure::text || '|'
                     || encode(sha256(convert_to(replace(replace(p.prosrc, 'pg_catalog.uuid', 'uuid'),
                                                         'pg_catalog.text', 'text'), 'UTF8')), 'hex'), ','
                     order by p.oid::regprocedure::text)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('registrar_ingreso', 'mover_a_cuarentena', 'registrar_merma')),
  'privado.mover_a_cuarentena(uuid,uuid,uuid,integer,text)|6b0e2159afbbde32dff90b7b51c6408ed4a9c2c6a94fd430701db38b94c0e99e,privado.registrar_ingreso(uuid,uuid,integer,text)|a809e6a4a7ee07e06bdcc0d9c4a97099f8c614abd19e3f425fa75c0a52cb9e78,privado.registrar_merma(uuid,uuid,uuid,integer,text,text)|ffb6ab8572c74292aeb9ae49cfb2fc33114ffec48c12b7be1e40e5146f4eb3ca',
  'P8: equivalencia mecánica — revirtiendo «pg_catalog.uuid» y «pg_catalog.text» se obtienen los cuerpos anteriores (SHA-256 de las migraciones de Stock)');

select is(
  (select string_agg(p.oid::regprocedure::text || '|'
                     || ((length(p.prosrc) - length(replace(p.prosrc, 'pg_catalog.uuid', ''))) / length('pg_catalog.uuid')
                         + (length(p.prosrc) - length(replace(p.prosrc, 'pg_catalog.text', ''))) / length('pg_catalog.text'))::text
                     || '|' || ((length(p.prosrc) - length(replace(p.prosrc, 'pg_catalog.', ''))) / length('pg_catalog.'))::text, ','
                     order by p.oid::regprocedure::text)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('registrar_ingreso', 'mover_a_cuarentena', 'registrar_merma')),
  'privado.mover_a_cuarentena(uuid,uuid,uuid,integer,text)|16|19,privado.registrar_ingreso(uuid,uuid,integer,text)|11|11,privado.registrar_merma(uuid,uuid,uuid,integer,text,text)|16|19',
  'P8: 43 calificaciones nuevas (11/16/16) más las 3 previas de cuarentena y merma');

select is(
  (select encode(sha256(convert_to(prosrc, 'UTF8')), 'hex') from pg_proc
    where oid = 'privado.usuario_actual()'::regprocedure),
  '2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96',
  'P8: usuario_actual sigue con el cuerpo de A1');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('registrar_ingreso', 'mover_a_cuarentena', 'registrar_merma')
      and p.prosecdef and p.provolatile = 'v'
      and p.proowner = 'propietario_rpc'::regrole
      and p.proconfig = array['search_path=""']
      and array(select a::text from unnest(p.proacl) a order by 1)
          = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']),
  3,
  'P8: las 3 RPC siguen SECURITY DEFINER, VOLATILE, de propietario_rpc, con search_path vacío y ACL exacta');

select ok(
  not exists (
    select 1 from pg_proc p, unnest(array['anon', 'service_role']) r
     where p.pronamespace = 'privado'::regnamespace
       and p.proname in ('registrar_ingreso', 'mover_a_cuarentena', 'registrar_merma')
       and has_function_privilege(r, p.oid, 'EXECUTE'))
  and not has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
  and (select nspacl::text from pg_namespace where nspname = 'privado')
      = '{postgres=UC/postgres,authenticated=U/postgres,propietario_rpc=U/postgres}',
  'P8/P11: anon y service_role sin EXECUTE; sin CREATE residual y ACL de privado sin cambios');

select is(
  (select string_agg(x.proname || ':' || x.esquemas, ';' order by x.proname)
     from (select p.proname::text, string_agg(n.nspname::text, ',' order by n.nspname) as esquemas
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where p.proname in ('registrar_ingreso', 'mover_a_cuarentena', 'registrar_merma')
            group by p.proname) x),
  'mover_a_cuarentena:privado,public;registrar_ingreso:privado,public;registrar_merma:privado,public',
  'P8: sin sobrecargas ni homónimos nuevos');

-- ===========================================================================
-- P7 — guardia estática (léxica, sin literales ni comentarios)
-- ===========================================================================
-- Como en A2, más la exclusión de los tipos que son palabras clave también en
-- los casts (los cuerpos de Stock usan «::bigint», que siempre es pg_catalog).
-- (En las expresiones regulares de PostgreSQL la voracidad de toda la expresión
-- la fija el primer cuantificador: por eso «\s*?» al comienzo.)
create function pg_temp.refs_sin_calificar(p_src pg_catalog.text)
returns pg_catalog.int4 language sql immutable as $f$
  with limpio as (
    select pg_catalog.regexp_replace(
             pg_catalog.regexp_replace(p_src, '''([^'']|'''')*''', '''''', 'g'),
             '--[^\n]*', '', 'g') as s
  ), declare_ as (
    select coalesce(pg_catalog.substring(l.s, '(?is)^\s*?declare(.*?)\mbegin\M'), '') as d, l.s
      from limpio l
  )
  select (select pg_catalog.count(*)::pg_catalog.int4
            from pg_catalog.regexp_matches(x.d,
                   '(?:^|;)\s*[a-z_][a-z0-9_]*\s+(?:constant\s+)?'
                   || '(?!pg_catalog\s*\.|(?:boolean|integer|int|smallint|bigint|numeric|decimal|real|double|varchar|character|char|timestamp|time|interval|bit)\M)'
                   || '[a-z_"]', 'gi'))
       + (select pg_catalog.count(*)::pg_catalog.int4
            from pg_catalog.regexp_matches(x.s,
                   '(::\s*(?!pg_catalog\s*\.|(?:boolean|integer|int|smallint|bigint|numeric|decimal|real|double|varchar|character|char|timestamp|time|interval|bit)\M)[a-z_"])'
                   || '|(\mcast\s*\()'
                   || '|(%\s*(row)?type\M)'
                   || '|(\m(from|join|update|insert\s+into|delete\s+from)\s+(?!(pg_catalog|public|privado|auth|extensions)\s*\.|\()[a-z_"])',
                   'gi'))
    from declare_ x
$f$;

select is(
  (select coalesce(string_agg(p.oid::regprocedure::text || '=' || pg_temp.refs_sin_calificar(p.prosrc)::text, ','
                              order by p.oid::regprocedure::text), '')
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('registrar_ingreso', 'mover_a_cuarentena', 'registrar_merma', 'usuario_actual')
      and pg_temp.refs_sin_calificar(p.prosrc) > 0),
  '',
  'P7: las 3 RPC de Stock y usuario_actual sin referencias resolubles por pg_temp');

select is(
  (select string_agg(pg_temp.refs_sin_calificar(replace(replace(p.prosrc, 'pg_catalog.uuid', 'uuid'),
                                                        'pg_catalog.text', 'text'))::text, '/'
                     order by p.proname)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('registrar_ingreso', 'mover_a_cuarentena', 'registrar_merma')),
  '16/11/16',
  'P7 (control M1): el detector encuentra las 16/11/16 referencias de los cuerpos anteriores (no cuenta ::bigint ni boolean)');

select is(
  pg_temp.refs_sin_calificar($m$
declare
  v_a pg_catalog.text := 'x::text';  -- y::text
  v_n bigint;
begin
  perform 'a'::pg_catalog.text, 1::bigint, p_id::text;
end $m$),
  1,
  'P7 (control M2): un cast en un literal o comentario no oculta el cast real sin calificar');

-- ===========================================================================
-- P1 — objetos hostiles de authenticated ANTES de la primera llamada
-- ===========================================================================
create temp table resultados (caso pg_catalog.text, valor pg_catalog.text);
grant all on resultados to public;

create function pg_temp.intentar(p_caso pg_catalog.text, p_expresion pg_catalog.text)
returns pg_catalog.void language plpgsql as $f$
declare
  v_valor pg_catalog.text;
begin
  execute 'select (' || p_expresion || ')::pg_catalog.text' into v_valor;
  insert into pg_temp.resultados values (p_caso, 'ok:' || coalesce(v_valor, 'null'));
exception when others then
  insert into pg_temp.resultados values (p_caso, 'error:' || sqlstate || ':' || sqlerrm);
end $f$;
grant execute on function pg_temp.intentar(pg_catalog.text, pg_catalog.text) to public;

create function pg_temp.ejecuciones_secuencia(p_secuencia pg_catalog.regclass) returns pg_catalog.int8
language plpgsql as $f$
declare
  v pg_catalog.int8;
begin
  execute pg_catalog.format('select case when is_called then last_value else 0 end from %s', p_secuencia) into v;
  return v;
end $f$;

-- Calentamiento: compila los event triggers de sql_drop sin objetos hostiles.
create temp table calentamiento_sql_drop ();
drop table calentamiento_sql_drop;

set local role authenticated;
create temp sequence sonda_privilegiada;
create temp sequence sonda_llamador;
create temp sequence control_directo;
create temp sequence control_mutante;
grant all on sequence sonda_privilegiada, sonda_llamador, control_directo, control_mutante to public;
create function pg_temp.sonda() returns pg_catalog.bool language plpgsql as $f$
begin
  if current_user operator(pg_catalog.=) 'authenticated' then
    perform pg_catalog.nextval('pg_temp.sonda_llamador'::pg_catalog.regclass);
  else
    perform pg_catalog.nextval('pg_temp.sonda_privilegiada'::pg_catalog.regclass);
  end if;
  return true;
end $f$;
grant execute on function pg_temp.sonda() to public;
create temp view operaciones as select 1 as x where pg_temp.sonda();
create temp view movimientos_stock as select 1 as x where pg_temp.sonda();
create temp view productos as select 1 as x where pg_temp.sonda();
create temp view ubicaciones as select 1 as x where pg_temp.sonda();
create temp view perfiles as select 1 as x where pg_temp.sonda();
create function pg_temp.btrim(pg_catalog.text) returns pg_catalog.text language plpgsql as $f$
begin perform pg_temp.sonda(); return $1; end $f$;
create function pg_temp.encode(pg_catalog.bytea, pg_catalog.text) returns pg_catalog.text language plpgsql as $f$
begin perform pg_temp.sonda(); return 'x'; end $f$;
create function pg_temp.igual_hostil(pg_catalog.text, pg_catalog.text) returns pg_catalog.bool
language plpgsql as $f$ begin perform pg_temp.sonda(); return $1 operator(pg_catalog.=) $2; end $f$;
create operator pg_temp.= (leftarg = pg_catalog.text, rightarg = pg_catalog.text,
                           function = pg_temp.igual_hostil);
grant execute on function pg_temp.btrim(pg_catalog.text), pg_temp.encode(pg_catalog.bytea, pg_catalog.text),
  pg_temp.igual_hostil(pg_catalog.text, pg_catalog.text) to public;
create domain pg_temp.uuid as pg_catalog.uuid check (pg_temp.sonda());
create domain pg_temp.text as pg_catalog.text check (pg_temp.sonda());
create domain pg_temp.date as pg_catalog.date check (pg_temp.sonda());
create domain pg_temp.jsonb as pg_catalog.jsonb check (pg_temp.sonda());
reset role;

insert into pg_temp.resultados
select 'hostiles',
       (select pg_catalog.count(*) from pg_catalog.pg_type t
         where t.typnamespace operator(pg_catalog.=) pg_catalog.pg_my_temp_schema() and t.typtype operator(pg_catalog.=) 'd')::pg_catalog.text
       || '/' || (select pg_catalog.count(*) from pg_catalog.pg_class c
                   where c.relnamespace operator(pg_catalog.=) pg_catalog.pg_my_temp_schema() and c.relkind operator(pg_catalog.=) 'v')::pg_catalog.text
       || '/' || (select pg_catalog.count(*) from pg_catalog.pg_operator o
                   where o.oprnamespace operator(pg_catalog.=) pg_catalog.pg_my_temp_schema())::pg_catalog.text;

-- ===========================================================================
-- P3 / P4 — llamadas por las fachadas public como authenticated
-- ===========================================================================
set local role authenticated;

-- Vendedor de A y sin identidad: rechazo antes de cualquier escritura.
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000003","role":"authenticated"}', true) is not null;
select pg_temp.intentar('rol_ingreso', $$public.registrar_ingreso('a3a3a3a3-1111-4000-8000-000000000001', 'a3a3a3a3-0000-4000-8000-0000000000f1', 1, null)$$);
select pg_temp.intentar('rol_cuarentena', $$public.mover_a_cuarentena('a3a3a3a3-1111-4000-8000-000000000002', 'a3a3a3a3-0000-4000-8000-0000000000f1', 'a3a3a3a3-0000-4000-8000-0000000000d1', 1, 'x')$$);
select pg_temp.intentar('rol_merma', $$public.registrar_merma('a3a3a3a3-1111-4000-8000-000000000003', 'a3a3a3a3-0000-4000-8000-0000000000f1', 'a3a3a3a3-0000-4000-8000-0000000000d1', 1, 'vencido', null)$$);
select pg_catalog.set_config('request.jwt.claims', '{"role":"authenticated"}', true) is not null;
select pg_temp.intentar('sin_identidad', $$public.registrar_ingreso('a3a3a3a3-1111-4000-8000-000000000004', 'a3a3a3a3-0000-4000-8000-0000000000f1', 1, null)$$);

-- Dueño de A: ingreso, replay, conflicto de huella, cuarentena, merma y rechazos.
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000001","role":"authenticated"}', true) is not null;
select pg_temp.intentar('ingreso', $$public.registrar_ingreso('a3a3a3a3-2222-4000-8000-000000000001', 'a3a3a3a3-0000-4000-8000-0000000000f1', 10, 'Remito 1')$$);
select pg_temp.intentar('replay', $$public.registrar_ingreso('a3a3a3a3-2222-4000-8000-000000000001', 'a3a3a3a3-0000-4000-8000-0000000000f1', 10, '  Remito 1 ')$$);
select pg_temp.intentar('conflicto', $$public.registrar_ingreso('a3a3a3a3-2222-4000-8000-000000000001', 'a3a3a3a3-0000-4000-8000-0000000000f1', 11, 'Remito 1')$$);
select pg_temp.intentar('cuarentena', $$public.mover_a_cuarentena('a3a3a3a3-2222-4000-8000-000000000002', 'a3a3a3a3-0000-4000-8000-0000000000f1', 'a3a3a3a3-0000-4000-8000-0000000000d1', 3, 'Golpeado')$$);
select pg_temp.intentar('merma', $$public.registrar_merma('a3a3a3a3-2222-4000-8000-000000000003', 'a3a3a3a3-0000-4000-8000-0000000000f1', 'a3a3a3a3-0000-4000-8000-0000000000d1', 2, 'vencido', null)$$);
select pg_temp.intentar('merma_otro_sin_motivo', $$public.registrar_merma('a3a3a3a3-2222-4000-8000-000000000004', 'a3a3a3a3-0000-4000-8000-0000000000f1', 'a3a3a3a3-0000-4000-8000-0000000000d1', 1, 'otro', null)$$);
select pg_temp.intentar('insuficiente', $$public.registrar_merma('a3a3a3a3-2222-4000-8000-000000000005', 'a3a3a3a3-0000-4000-8000-0000000000f1', 'a3a3a3a3-0000-4000-8000-0000000000d1', 100, 'vencido', null)$$);
select pg_temp.intentar('inactivo', $$public.registrar_ingreso('a3a3a3a3-2222-4000-8000-000000000006', 'a3a3a3a3-0000-4000-8000-0000000000f2', 1, null)$$);
select pg_temp.intentar('origen_cuarentena', $$public.mover_a_cuarentena('a3a3a3a3-2222-4000-8000-000000000007', 'a3a3a3a3-0000-4000-8000-0000000000f1', 'a3a3a3a3-0000-4000-8000-0000000000c1', 1, 'x')$$);

-- Dueño de A con objetos de la empresa B.
select pg_temp.intentar('b_ingreso', $$public.registrar_ingreso('a3a3a3a3-3333-4000-8000-000000000001', 'b3b3b3b3-0000-4000-8000-0000000000f1', 1, null)$$);
select pg_temp.intentar('b_cuarentena_ubicacion', $$public.mover_a_cuarentena('a3a3a3a3-3333-4000-8000-000000000002', 'a3a3a3a3-0000-4000-8000-0000000000f1', 'b3b3b3b3-0000-4000-8000-0000000000d1', 1, 'x')$$);
select pg_temp.intentar('b_merma_producto', $$public.registrar_merma('a3a3a3a3-3333-4000-8000-000000000003', 'b3b3b3b3-0000-4000-8000-0000000000f1', 'a3a3a3a3-0000-4000-8000-0000000000d1', 1, 'vencido', null)$$);
select pg_temp.intentar('b_merma_ubicacion', $$public.registrar_merma('a3a3a3a3-3333-4000-8000-000000000004', 'a3a3a3a3-0000-4000-8000-0000000000f1', 'b3b3b3b3-0000-4000-8000-0000000000d1', 1, 'vencido', null)$$);

-- Encargado de A: también gestiona Stock.
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000002","role":"authenticated"}', true) is not null;
select pg_temp.intentar('encargado_ingreso', $$public.registrar_ingreso('a3a3a3a3-4444-4000-8000-000000000001', 'a3a3a3a3-0000-4000-8000-0000000000f1', 4, null)$$);
reset role;

insert into pg_temp.resultados
select 'medida_p3',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text
       || '/' || (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_llamador s)::pg_catalog.text;

-- ===========================================================================
-- P6 — control del detector: cuerpo anterior de registrar_ingreso
-- ===========================================================================
select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
savepoint control_m1;
grant create on schema privado to propietario_rpc;
set local role propietario_rpc;
do $c$
begin
  execute pg_catalog.format(
    'create or replace function privado.registrar_ingreso(p_idempotency_key pg_catalog.uuid, '
    || 'p_producto_id pg_catalog.uuid, p_cantidad pg_catalog.int4, '
    || 'p_motivo pg_catalog.text default null::pg_catalog.text) returns pg_catalog.uuid '
    || 'language plpgsql volatile security definer set search_path = %L as %L', '',
    (select pg_catalog.replace(pg_catalog.replace(p.prosrc, 'pg_catalog.uuid', 'uuid'), 'pg_catalog.text', 'text')
       from pg_catalog.pg_proc p
      where p.oid operator(pg_catalog.=) 'privado.registrar_ingreso(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)'::pg_catalog.regprocedure));
end $c$;
reset role;
revoke create on schema privado from propietario_rpc;
select pg_catalog.setval('pg_temp.control_mutante'::pg_catalog.regclass, 1,
  (select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex')
     from pg_catalog.pg_proc p
    where p.oid operator(pg_catalog.=) 'privado.registrar_ingreso(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)'::pg_catalog.regprocedure)
  operator(pg_catalog.=) 'a809e6a4a7ee07e06bdcc0d9c4a97099f8c614abd19e3f425fa75c0a52cb9e78');
set local role authenticated;
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000001","role":"authenticated"}', true) is not null;
select pg_temp.intentar('m1', $$public.registrar_ingreso('a3a3a3a3-5555-4000-8000-000000000001', 'a3a3a3a3-0000-4000-8000-0000000000f1', 1, null)$$);
reset role;
select pg_catalog.setval('pg_temp.control_directo'::pg_catalog.regclass,
  (select case when s.is_called then s.last_value else 1 end from pg_temp.sonda_privilegiada s),
  (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s) operator(pg_catalog.>) 0);
rollback to savepoint control_m1;

select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
set local role authenticated;
select pg_temp.intentar('post_m1', $$public.registrar_ingreso('a3a3a3a3-5555-4000-8000-000000000002', 'a3a3a3a3-0000-4000-8000-0000000000f1', 1, null)$$);
reset role;
insert into pg_temp.resultados
select 'medida_post_m1',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text;

-- Se eliminan los objetos hostiles (dominios primero) antes de usar pgTAP.
set local role authenticated;
drop domain pg_temp.uuid, pg_temp.text, pg_temp.date, pg_temp.jsonb;
drop operator pg_temp.= (pg_catalog.text, pg_catalog.text);
drop function pg_temp.igual_hostil(pg_catalog.text, pg_catalog.text), pg_temp.btrim(pg_catalog.text),
  pg_temp.encode(pg_catalog.bytea, pg_catalog.text);
drop view pg_temp.operaciones, pg_temp.movimientos_stock, pg_temp.productos, pg_temp.ubicaciones, pg_temp.perfiles;
drop function pg_temp.sonda();
reset role;

-- ===========================================================================
-- Afirmaciones (sin objetos hostiles)
-- ===========================================================================
select is((select valor from resultados where caso = 'hostiles'), '4/5/1',
  'P1: 4 dominios, 5 vistas homónimas y 1 operador hostiles creados antes de la primera llamada');

select is(
  (select string_agg(caso || '=' || split_part(valor, ':', 1), ',' order by caso) from resultados
    where caso in ('ingreso', 'replay', 'cuarentena', 'merma', 'encargado_ingreso')),
  'cuarentena=ok,encargado_ingreso=ok,ingreso=ok,merma=ok,replay=ok',
  'P3: las 3 RPC (y el ingreso del encargado) completan con los objetos hostiles presentes');

select is(
  (select valor from resultados where caso = 'replay'),
  (select valor from resultados where caso = 'ingreso'),
  'P3: el replay con la misma clave y huella normalizada devuelve la misma operación');

select is(
  (select string_agg(o.tipo || '=' || (o.huella = encode(sha256(convert_to(
             case o.tipo
               when 'ingreso' then 'v1|ingreso|a3a3a3a3-0000-4000-8000-0000000000f1|10|+Remito 1'
               when 'a_cuarentena' then 'v1|a_cuarentena|a3a3a3a3-0000-4000-8000-0000000000f1|a3a3a3a3-0000-4000-8000-0000000000d1|3|+Golpeado'
               when 'merma' then 'v1|merma|a3a3a3a3-0000-4000-8000-0000000000f1|a3a3a3a3-0000-4000-8000-0000000000d1|2|vencido|-'
             end, 'UTF8')), 'hex'))::text, ',' order by o.tipo)
     from public.operaciones o
    where o.id in (select substr(valor, 4)::uuid from resultados where caso in ('ingreso', 'cuarentena', 'merma'))),
  'a_cuarentena=true,ingreso=true,merma=true',
  'P3: las huellas v1 coinciden con el literal canónico (el cast calificado no cambia la huella)');

select is(
  (select string_agg(u.tipo || '=' || (select coalesce(sum(case when m.ubicacion_destino_id = u.id then m.cantidad
                                                                else -m.cantidad end), 0)
                                         from public.movimientos_stock m
                                        where m.producto_id = 'a3a3a3a3-0000-4000-8000-0000000000f1'
                                          and (m.ubicacion_destino_id = u.id or m.ubicacion_origen_id = u.id))::text,
                     ',' order by u.tipo)
     from public.ubicaciones u where u.empresa_id = 'a3a3a3a3-0000-4000-8000-000000000000')
  || ';' || (select count(*)::text from public.movimientos_stock m
              where m.empresa_id = 'a3a3a3a3-0000-4000-8000-000000000000'),
  'cuarentena=3,deposito=10;5',
  'P3: equivalencia de comportamiento — saldos exactos (10 + 4 + 1 posterior al control − 3 − 2 en depósito; 3 en cuarentena) y 5 movimientos');

select is(
  (select string_agg(caso || '=' || valor, ' ; ' order by caso) from resultados
    where caso in ('rol_ingreso', 'rol_cuarentena', 'rol_merma', 'sin_identidad', 'conflicto',
                   'merma_otro_sin_motivo', 'insuficiente', 'inactivo', 'origen_cuarentena')),
  'conflicto=error:PT409:stock_conflicto_idempotencia ; inactivo=error:PT409:stock_producto_inactivo ; insuficiente=error:PT409:stock_insuficiente ; merma_otro_sin_motivo=error:PT400:stock_motivo_invalido ; origen_cuarentena=error:PT400:stock_origen_invalido ; rol_cuarentena=error:PT403:stock_no_autorizado ; rol_ingreso=error:PT403:stock_no_autorizado ; rol_merma=error:PT403:stock_no_autorizado ; sin_identidad=error:PT401:stock_no_autenticado',
  'P4: rechazos por rol, identidad, idempotencia, motivo, saldo, producto inactivo y origen, con códigos estables');

select is(
  (select string_agg(caso || '=' || valor, ' ; ' order by caso) from resultados where caso like 'b\_%'),
  'b_cuarentena_ubicacion=error:PT404:stock_ubicacion_no_encontrada ; b_ingreso=error:PT404:stock_producto_no_encontrado ; b_merma_producto=error:PT404:stock_producto_no_encontrado ; b_merma_ubicacion=error:PT404:stock_ubicacion_no_encontrada',
  'P4: con productos o ubicaciones de otra empresa, las 3 RPC responden no encontrado');

select is(
  (select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.productos t
            where t.empresa_id = 'b3b3b3b3-0000-4000-8000-000000000000')
          || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.ubicaciones t
                      where t.empresa_id = 'b3b3b3b3-0000-4000-8000-000000000000')
          || '/' || (select count(*)::text from public.operaciones t
                      where t.empresa_id = 'b3b3b3b3-0000-4000-8000-000000000000')
          || '/' || (select count(*)::text from public.movimientos_stock t
                      where t.empresa_id = 'b3b3b3b3-0000-4000-8000-000000000000')),
  (select huella from huella_b),
  'P4: productos, ubicaciones, operaciones y movimientos de la empresa B sin cambios');

select is(
  (select count(*)::int from public.operaciones o
    where o.empresa_id = 'a3a3a3a3-0000-4000-8000-000000000000'),
  5,
  'P4: sólo las 5 operaciones válidas quedan registradas (los rechazos y el control revertido no dejan operaciones)');

select is((select valor from resultados where caso = 'medida_p3'), '0/0',
  'P1/P3/P4: 0 ejecuciones del código temporal como propietario_rpc y como authenticated en las 22 llamadas');

select ok(pg_temp.ejecuciones_secuencia('pg_temp.control_mutante') = 1,
  'P6: el cuerpo reintroducido es exactamente el anterior a A3 (SHA-256)');

select cmp_ok(pg_temp.ejecuciones_secuencia('pg_temp.control_directo'), '>', 0::bigint,
  'P6: con referencias sin calificar, registrar_ingreso ejecuta el código temporal como propietario_rpc (el detector funciona)');

select is(
  (select split_part(valor, ':', 1) from resultados where caso = 'post_m1')
  || '/' || (select valor from resultados where caso = 'medida_post_m1')
  || '/' || (select encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex') from pg_proc p
              where p.oid = 'privado.registrar_ingreso(uuid,uuid,integer,text)'::regprocedure)
  || '/' || has_schema_privilege('propietario_rpc', 'privado', 'CREATE')::text,
  'ok/0/b87c32fb38443dbe57abfc19ddce449a0d05d2c567a499165c09ba6a2ef9ece6/false',
  'P6: tras revertir el control vuelve el cuerpo de A3, sin CREATE residual, y la llamada vuelve a 0 ejecuciones');

select * from finish();

rollback;
