-- pgTAP: endurecimiento pg_temp de jornadas — B1, objetos hostiles creados
-- DESPUÉS de una primera llamada legítima a cada RPC (plan de remediación
-- pg_temp, §5, segundo bloque; ADR-001 §17.1).
--
-- La sesión llama primero a las 2 RPC sin objetos hostiles (compila y guarda en
-- caché los cuerpos PL/pgSQL); después authenticated crea los dominios y las
-- vistas homónimas y se repiten las llamadas con otras claves. Esperado: mismos
-- resultados y 0 ejecuciones del código temporal como propietario_rpc.
--
-- Como en A2/A3, PL/pgSQL conserva el cuerpo ya compilado en la sesión: la
-- ronda hostil, aislada, no detectaría por sí sola un cuerpo vulnerable. El
-- control redefine reasignar_vendedor con el cuerpo anterior (invalida la
-- caché) y, al revertirlo, la siguiente llamada vuelve a compilar con los
-- objetos hostiles presentes: ésa es la medición que falla sin B1.
--
-- No se llama a pgTAP mientras existen los objetos hostiles.
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

insert into public.empresas (id, nombre) values
  ('b1b1b1b1-1111-4000-8000-000000000000', 'Empresa A (test pg_temp B1 posterior)'),
  ('c1c1c1c1-1111-4000-8000-000000000000', 'Empresa B (test pg_temp B1 posterior)');
insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('b1b1b1b1-1111-4000-8000-000000000001', 'authenticated', 'authenticated', 'pgb1p.a1@usuarios.distribuidora.invalid', '{}'),
  ('b1b1b1b1-1111-4000-8000-000000000003', 'authenticated', 'authenticated', 'pgb1p.a3@usuarios.distribuidora.invalid', '{}'),
  ('b1b1b1b1-1111-4000-8000-000000000004', 'authenticated', 'authenticated', 'pgb1p.a4@usuarios.distribuidora.invalid', '{}'),
  ('b1b1b1b1-1111-4000-8000-000000000005', 'authenticated', 'authenticated', 'pgb1p.a5@usuarios.distribuidora.invalid', '{}'),
  ('b1b1b1b1-1111-4000-8000-000000000006', 'authenticated', 'authenticated', 'pgb1p.a6@usuarios.distribuidora.invalid', '{}'),
  ('b1b1b1b1-1111-4000-8000-000000000007', 'authenticated', 'authenticated', 'pgb1p.a7@usuarios.distribuidora.invalid', '{}'),
  ('c1c1c1c1-1111-4000-8000-000000000001', 'authenticated', 'authenticated', 'pgb1p.b1@usuarios.distribuidora.invalid', '{}'),
  ('c1c1c1c1-1111-4000-8000-000000000002', 'authenticated', 'authenticated', 'pgb1p.b2@usuarios.distribuidora.invalid', '{}');
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('b1b1b1b1-1111-4000-8000-000000000001', 'b1b1b1b1-1111-4000-8000-000000000000', 'pgb1p.a1', 'Dueño A', 'dueno', true),
  ('b1b1b1b1-1111-4000-8000-000000000003', 'b1b1b1b1-1111-4000-8000-000000000000', 'pgb1p.a3', 'Vendedor A3', 'vendedor_piloto', true),
  ('b1b1b1b1-1111-4000-8000-000000000004', 'b1b1b1b1-1111-4000-8000-000000000000', 'pgb1p.a4', 'Vendedor A4', 'vendedor_piloto', true),
  ('b1b1b1b1-1111-4000-8000-000000000005', 'b1b1b1b1-1111-4000-8000-000000000000', 'pgb1p.a5', 'Vendedor A5', 'vendedor_piloto', true),
  ('b1b1b1b1-1111-4000-8000-000000000006', 'b1b1b1b1-1111-4000-8000-000000000000', 'pgb1p.a6', 'Vendedor A6', 'vendedor_piloto', true),
  ('b1b1b1b1-1111-4000-8000-000000000007', 'b1b1b1b1-1111-4000-8000-000000000000', 'pgb1p.a7', 'Vendedor A7', 'vendedor_piloto', true),
  ('c1c1c1c1-1111-4000-8000-000000000001', 'c1c1c1c1-1111-4000-8000-000000000000', 'pgb1p.b1', 'Dueño B', 'dueno', true),
  ('c1c1c1c1-1111-4000-8000-000000000002', 'c1c1c1c1-1111-4000-8000-000000000000', 'pgb1p.b2', 'Vendedor B', 'vendedor_piloto', true);
insert into public.camiones (id, empresa_id, patente, nombre, activo, creado_por) values
  ('b1b1b1b1-1111-4000-8000-0000000000c1', 'b1b1b1b1-1111-4000-8000-000000000000', 'PB1P-01', 'Camión A1', true, 'b1b1b1b1-1111-4000-8000-000000000001'),
  ('b1b1b1b1-1111-4000-8000-0000000000c2', 'b1b1b1b1-1111-4000-8000-000000000000', 'PB1P-02', 'Camión A2', true, 'b1b1b1b1-1111-4000-8000-000000000001'),
  ('c1c1c1c1-1111-4000-8000-0000000000c1', 'c1c1c1c1-1111-4000-8000-000000000000', 'PB1P-B1', 'Camión B1', true, 'c1c1c1c1-1111-4000-8000-000000000001');
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella) values
  ('c1c1c1c1-1111-4000-8000-0000000000a1', 'c1c1c1c1-1111-4000-8000-000000000000', 'c1c1c1c1-1111-4000-8000-000000000001',
   'apertura_jornada', 'c1c1c1c1-1111-4000-8000-0000000000a0', repeat('c', 64));
insert into public.jornadas (id, empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id) values
  ('c1c1c1c1-1111-4000-8000-0000000000a1', 'c1c1c1c1-1111-4000-8000-000000000000', date '2999-04-01',
   'c1c1c1c1-1111-4000-8000-0000000000c1', 'c1c1c1c1-1111-4000-8000-000000000002', 'abierta',
   'c1c1c1c1-1111-4000-8000-000000000001', 'c1c1c1c1-1111-4000-8000-0000000000a1');

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

-- Ronda de llamadas a las 2 RPC. p_sufijo (L/H) distingue los casos, p_ronda
-- (un dígito) las claves, p_camion el camión (c1/c2) y p_v1/p_v2 los vendedores
-- de apertura y de reasignación (dígito final).
create function pg_temp.ronda(p_sufijo pg_catalog.text, p_ronda pg_catalog.text, p_camion pg_catalog.text,
                              p_v1 pg_catalog.text, p_v2 pg_catalog.text) returns pg_catalog.void
language plpgsql as $f$
begin
  perform pg_catalog.set_config('request.jwt.claims',
    '{"sub":"b1b1b1b1-1111-4000-8000-000000000001","role":"authenticated"}', true);
  perform pg_temp.intentar('abrir' || p_sufijo, pg_catalog.format(
    $$public.abrir_jornada('b1b1b1b1-%s001-4000-8000-000000000001', 'b1b1b1b1-1111-4000-8000-0000000000%s', '2999-04-01', 'b1b1b1b1-1111-4000-8000-00000000000%s')$$,
    p_ronda, p_camion, p_v1));
  perform pg_temp.intentar('replay' || p_sufijo, pg_catalog.format(
    $$public.abrir_jornada('b1b1b1b1-%s001-4000-8000-000000000001', 'b1b1b1b1-1111-4000-8000-0000000000%s', '2999-04-01', 'b1b1b1b1-1111-4000-8000-00000000000%s')$$,
    p_ronda, p_camion, p_v1));
  perform pg_temp.intentar('reasignar' || p_sufijo, pg_catalog.format(
    $$public.reasignar_vendedor('b1b1b1b1-%s002-4000-8000-000000000001', %L, 'b1b1b1b1-1111-4000-8000-00000000000%s')$$,
    p_ronda,
    (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) ('abrir' || p_sufijo)),
    p_v2));
  perform pg_temp.intentar('b_jornada' || p_sufijo, pg_catalog.format(
    $$public.reasignar_vendedor('b1b1b1b1-%s003-4000-8000-000000000001', 'c1c1c1c1-1111-4000-8000-0000000000a1', 'b1b1b1b1-1111-4000-8000-00000000000%s')$$,
    p_ronda, p_v2));
end $f$;
grant execute on function pg_temp.ronda(pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text) to public;

-- ---------------------------------------------------------------------------
-- Ronda legítima (sin objetos hostiles): compila las 2 RPC en la sesión
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.ronda('L', '1', 'c1', '3', '4');
reset role;

-- ---------------------------------------------------------------------------
-- Objetos hostiles de authenticated, creados después de la ronda legítima
-- ---------------------------------------------------------------------------
create temp table calentamiento_sql_drop ();
drop table calentamiento_sql_drop;

set local role authenticated;
create temp sequence sonda_privilegiada;
create temp sequence sonda_llamador;
create temp sequence control_directo;
create temp sequence control_ok;
grant all on sequence sonda_privilegiada, sonda_llamador, control_directo, control_ok to public;
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
create temp view jornadas as select 1 as x where pg_temp.sonda();
create temp view operaciones as select 1 as x where pg_temp.sonda();
create temp view reasignaciones_vendedor as select 1 as x where pg_temp.sonda();
create domain pg_temp.uuid as pg_catalog.uuid check (pg_temp.sonda());
create domain pg_temp.text as pg_catalog.text check (pg_temp.sonda());
create domain pg_temp.date as pg_catalog.date check (pg_temp.sonda());
create domain pg_temp.jsonb as pg_catalog.jsonb check (pg_temp.sonda());

select pg_temp.ronda('H', '2', 'c2', '5', '6');
reset role;

insert into pg_temp.resultados
select 'medida_hostil',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text
       || '/' || (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_llamador s)::pg_catalog.text;

-- ---------------------------------------------------------------------------
-- Control: cuerpo anterior de reasignar_vendedor (invalida la caché)
-- ---------------------------------------------------------------------------
select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
savepoint control_m1;
grant create on schema privado to propietario_rpc;
set local role propietario_rpc;
do $c$
begin
  execute pg_catalog.format(
    'create or replace function privado.reasignar_vendedor(p_idempotency_key pg_catalog.uuid, '
    || 'p_jornada_id pg_catalog.uuid, p_vendedor_id pg_catalog.uuid) returns pg_catalog.uuid '
    || 'language plpgsql volatile security definer set search_path = %L as %L', '',
    (select pg_catalog.replace(pg_catalog.replace(pg_catalog.replace(p.prosrc, 'pg_catalog.uuid', 'uuid'),
                                                  'pg_catalog.text', 'text'), 'pg_catalog.date', 'date')
       from pg_catalog.pg_proc p
      where p.oid operator(pg_catalog.=) 'privado.reasignar_vendedor(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)'::pg_catalog.regprocedure));
end $c$;
reset role;
revoke create on schema privado from propietario_rpc;
set local role authenticated;
select pg_temp.intentar('m1', pg_catalog.format(
  $$public.reasignar_vendedor('b1b1b1b1-9001-4000-8000-000000000001', %L, 'b1b1b1b1-1111-4000-8000-000000000007')$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrirH')));
reset role;
select pg_catalog.setval('pg_temp.control_ok'::pg_catalog.regclass, 1,
  exists (select 1 from pg_temp.resultados r
           where r.caso operator(pg_catalog.=) 'm1' and r.valor operator(pg_catalog.~~) 'ok:%'));
select pg_catalog.setval('pg_temp.control_directo'::pg_catalog.regclass,
  (select case when s.is_called then s.last_value else 1 end from pg_temp.sonda_privilegiada s),
  (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s) operator(pg_catalog.>) 0);
rollback to savepoint control_m1;

-- Tras revertir: la siguiente llamada recompila con los objetos hostiles presentes.
select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
set local role authenticated;
select pg_temp.intentar('post_m1', pg_catalog.format(
  $$public.reasignar_vendedor('b1b1b1b1-9002-4000-8000-000000000001', %L, 'b1b1b1b1-1111-4000-8000-000000000007')$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrirH')));
reset role;
insert into pg_temp.resultados
select 'medida_post_m1',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text;

set local role authenticated;
drop domain pg_temp.uuid, pg_temp.text, pg_temp.date, pg_temp.jsonb;
drop view pg_temp.jornadas, pg_temp.operaciones, pg_temp.reasignaciones_vendedor;
drop function pg_temp.sonda();
reset role;

-- ---------------------------------------------------------------------------
-- Afirmaciones (sin objetos hostiles)
-- ---------------------------------------------------------------------------
select is(
  (select string_agg(caso || '=' || split_part(valor, ':', 1)
                     || case when valor like 'error:%' then ':' || split_part(valor, ':', 3) else '' end,
                     ',' order by caso)
     from resultados where caso like '%L'),
  'abrirL=ok,b_jornadaL=error:jornada_no_encontrada,reasignarL=ok,replayL=ok',
  'Posterior: la ronda legítima completa las 2 RPC y rechaza la jornada de otra empresa');

select is(
  (select string_agg(regexp_replace(l.caso, 'L$', ''), ',' order by l.caso)
     from resultados l join resultados h on h.caso = regexp_replace(l.caso, 'L$', 'H')
    where l.caso like '%L'
      and (split_part(l.valor, ':', 1) <> split_part(h.valor, ':', 1)
           or (l.valor like 'error:%' and l.valor <> h.valor))),
  null,
  'Posterior: con los objetos hostiles cada RPC da el mismo resultado (éxito o el mismo error) que en la ronda legítima');

select is(
  (select (select valor from resultados where caso = 'replayH') = (select valor from resultados where caso = 'abrirH'))
  and (select count(*) from public.reasignaciones_vendedor r
        where r.empresa_id = 'c1c1c1c1-1111-4000-8000-000000000000') = 0
  and (select string_agg(right(j.vendedor_id::text, 1), ',' order by j.camion_id) from public.jornadas j
        where j.empresa_id = 'b1b1b1b1-1111-4000-8000-000000000000') = '4,7',
  true,
  'Posterior: replay idempotente en la ronda hostil, sin reasignaciones en la empresa B y vendedores finales esperados (4 y 7)');

select is((select valor from resultados where caso = 'medida_hostil'), '0/0',
  'Posterior: 0 ejecuciones del código temporal (propietario_rpc / authenticated) en la ronda hostil');

select cmp_ok(pg_temp.ejecuciones_secuencia('pg_temp.control_directo'), '>', 0::bigint,
  'Posterior (control): con el cuerpo anterior, reasignar_vendedor ejecuta el código temporal como propietario_rpc');

select is(pg_temp.ejecuciones_secuencia('pg_temp.control_ok')::text
          || '/' || (select split_part(valor, ':', 1) from resultados where caso = 'post_m1'),
  '1/ok',
  'Posterior (control): el mutante y la llamada posterior completan (el control mide ejecución, no un error)');

select is((select valor from resultados where caso = 'medida_post_m1'), '0',
  'Posterior: tras revertir el control (recompilación con objetos hostiles presentes), 0 ejecuciones como propietario_rpc');

select * from finish();

rollback;
