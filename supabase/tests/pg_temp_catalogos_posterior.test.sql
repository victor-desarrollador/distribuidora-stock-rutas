-- pgTAP: endurecimiento pg_temp de catálogos — A2, objetos hostiles creados
-- DESPUÉS de una primera llamada legítima a cada RPC (plan de remediación
-- pg_temp, §5, segundo bloque; ADR-001 §17.1).
--
-- La sesión llama primero a las 10 RPC sin objetos hostiles (compila y guarda
-- en caché los cuerpos PL/pgSQL); después authenticated crea los dominios
-- uuid/text/date/jsonb y las vistas homónimas, y se repiten las llamadas.
-- Esperado: mismos resultados y 0 ejecuciones del código temporal como
-- propietario_rpc. El control redefine crear_camion y exigir_dueno_camiones
-- con los cuerpos anteriores (lo que invalida su caché) y comprueba que, en
-- este mismo orden, el detector sí ve la ejecución.
--
-- Igual que en pg_temp_catalogos.test.sql, no se llama a pgTAP mientras
-- existen los objetos hostiles.
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

insert into public.empresas (id, nombre) values
  ('a8a8a8a8-1111-4000-8000-000000000000', 'Empresa A (test pg_temp A2 posterior)'),
  ('b8b8b8b8-1111-4000-8000-000000000000', 'Empresa B (test pg_temp A2 posterior)');
insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('a8a8a8a8-1111-4000-8000-000000000001', 'authenticated', 'authenticated', 'pga2p.a1@usuarios.distribuidora.invalid', '{}'),
  ('a8a8a8a8-1111-4000-8000-000000000003', 'authenticated', 'authenticated', 'pga2p.a3@usuarios.distribuidora.invalid', '{}'),
  ('b8b8b8b8-1111-4000-8000-000000000001', 'authenticated', 'authenticated', 'pga2p.b1@usuarios.distribuidora.invalid', '{}');
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('a8a8a8a8-1111-4000-8000-000000000001', 'a8a8a8a8-1111-4000-8000-000000000000', 'pga2p.a1', 'Dueño A', 'dueno', true),
  ('a8a8a8a8-1111-4000-8000-000000000003', 'a8a8a8a8-1111-4000-8000-000000000000', 'pga2p.a3', 'Vendedor A', 'vendedor_piloto', true),
  ('b8b8b8b8-1111-4000-8000-000000000001', 'b8b8b8b8-1111-4000-8000-000000000000', 'pga2p.b1', 'Dueño B', 'dueno', true);
insert into public.camiones (id, empresa_id, patente, nombre, creado_por) values
  ('b8b8b8b8-1111-4000-8000-0000000000c1', 'b8b8b8b8-1111-4000-8000-000000000000', 'PGA2P-B', 'Camión B', 'b8b8b8b8-1111-4000-8000-000000000001');

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

create function pg_temp.valor(p_caso pg_catalog.text) returns pg_catalog.text
language sql stable as $f$
  select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r
   where r.caso operator(pg_catalog.=) p_caso
$f$;
grant execute on function pg_temp.valor(pg_catalog.text) to public;

create function pg_temp.ejecuciones_secuencia(p_secuencia pg_catalog.regclass) returns pg_catalog.int8
language plpgsql as $f$
declare
  v pg_catalog.int8;
begin
  execute pg_catalog.format('select case when is_called then last_value else 0 end from %s', p_secuencia) into v;
  return v;
end $f$;

-- Ronda de llamadas a las 10 RPC (sufijo distingue la ronda legítima de la hostil).
create function pg_temp.ronda(p_sufijo pg_catalog.text) returns pg_catalog.void
language plpgsql as $f$
begin
  perform pg_catalog.set_config('request.jwt.claims',
    '{"sub":"a8a8a8a8-1111-4000-8000-000000000003","role":"authenticated"}', true);
  perform pg_temp.intentar('cli_pend' || p_sufijo,
    pg_catalog.format('public.crear_cliente(%L, %L)', 'Pendiente ' || p_sufijo, '381-1' || p_sufijo));
  perform pg_catalog.set_config('request.jwt.claims',
    '{"sub":"a8a8a8a8-1111-4000-8000-000000000001","role":"authenticated"}', true);
  perform pg_temp.intentar('prod' || p_sufijo,
    pg_catalog.format($$public.crear_producto(%L, 'Leche', 'lacteos', 'unidad', 100, 0)$$, 'PGA2P-' || p_sufijo));
  perform pg_temp.intentar('act_prod' || p_sufijo,
    pg_catalog.format($$public.actualizar_producto(%L::pg_catalog.uuid, null, 'Leche 2', 110, 1)$$, pg_temp.valor('prod' || p_sufijo)));
  perform pg_temp.intentar('est_prod' || p_sufijo,
    pg_catalog.format('public.cambiar_estado_producto(%L::pg_catalog.uuid, false)', pg_temp.valor('prod' || p_sufijo)));
  perform pg_temp.intentar('cam' || p_sufijo,
    pg_catalog.format($$public.crear_camion(%L, 'Camión')$$, 'PGA2P-' || p_sufijo));
  perform pg_temp.intentar('act_cam' || p_sufijo,
    pg_catalog.format($$public.actualizar_camion(%L::pg_catalog.uuid, %L, 'Camión 2')$$, pg_temp.valor('cam' || p_sufijo), 'PGA2P-X' || p_sufijo));
  perform pg_temp.intentar('est_cam' || p_sufijo,
    pg_catalog.format('public.cambiar_estado_camion(%L::pg_catalog.uuid, false)', pg_temp.valor('cam' || p_sufijo)));
  perform pg_temp.intentar('cli' || p_sufijo,
    pg_catalog.format($$public.crear_cliente(%L, '381-2')$$, 'Cliente ' || p_sufijo));
  perform pg_temp.intentar('act_cli' || p_sufijo,
    pg_catalog.format($$public.actualizar_cliente(%L::pg_catalog.uuid, 'Cliente 2', '381-3', null, null)$$, pg_temp.valor('cli' || p_sufijo)));
  perform pg_temp.intentar('validar' || p_sufijo,
    pg_catalog.format('public.validar_cliente(%L::pg_catalog.uuid)', pg_temp.valor('cli_pend' || p_sufijo)));
  perform pg_temp.intentar('est_cli' || p_sufijo,
    pg_catalog.format('public.cambiar_estado_cliente(%L::pg_catalog.uuid, false)', pg_temp.valor('cli' || p_sufijo)));
  perform pg_temp.intentar('b_cam' || p_sufijo,
    $$public.cambiar_estado_camion('b8b8b8b8-1111-4000-8000-0000000000c1'::pg_catalog.uuid, false)$$);
end $f$;
grant execute on function pg_temp.ronda(pg_catalog.text) to public;

-- ---------------------------------------------------------------------------
-- Ronda legítima (sin objetos hostiles): compila las 10 RPC en la sesión
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.ronda('L');
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
create temp view productos as select 1 as x where pg_temp.sonda();
create temp view camiones as select 1 as x where pg_temp.sonda();
create temp view clientes as select 1 as x where pg_temp.sonda();
create temp view perfiles as select 1 as x where pg_temp.sonda();
create temp view ubicaciones as select 1 as x where pg_temp.sonda();
create domain pg_temp.uuid as pg_catalog.uuid check (pg_temp.sonda());
create domain pg_temp.text as pg_catalog.text check (pg_temp.sonda());
create domain pg_temp.date as pg_catalog.date check (pg_temp.sonda());
create domain pg_temp.jsonb as pg_catalog.jsonb check (pg_temp.sonda());

-- Ronda con objetos hostiles.
select pg_temp.ronda('H');
reset role;

insert into pg_temp.resultados
select 'medida_hostil',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text
       || '/' || (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_llamador s)::pg_catalog.text;

-- ---------------------------------------------------------------------------
-- Control: cuerpos anteriores de crear_camion y exigir_dueno_camiones
-- ---------------------------------------------------------------------------
select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
savepoint control_m1;
grant create on schema privado to propietario_rpc;
set local role propietario_rpc;
do $c$
begin
  execute pg_catalog.format(
    'create or replace function privado.exigir_dueno_camiones() returns pg_catalog.uuid '
    || 'language plpgsql stable security invoker set search_path = %L as %L', '',
    (select pg_catalog.replace(p.prosrc, 'pg_catalog.', '') from pg_catalog.pg_proc p
      where p.oid operator(pg_catalog.=) 'privado.exigir_dueno_camiones()'::pg_catalog.regprocedure));
  execute pg_catalog.format(
    'create or replace function privado.crear_camion(p_patente pg_catalog.text, p_nombre pg_catalog.text) '
    || 'returns pg_catalog.uuid language plpgsql volatile security definer set search_path = %L as %L', '',
    (select pg_catalog.replace(p.prosrc, 'pg_catalog.', '') from pg_catalog.pg_proc p
      where p.oid operator(pg_catalog.=) 'privado.crear_camion(pg_catalog.text, pg_catalog.text)'::pg_catalog.regprocedure));
end $c$;
reset role;
revoke create on schema privado from propietario_rpc;
set local role authenticated;
select pg_temp.intentar('m1', $$public.crear_camion('PGA2P-M1', 'Mutante')$$);
reset role;
-- El ROLLBACK TO revierte la fila de resultados: el éxito del mutante va a una secuencia.
select pg_catalog.setval('pg_temp.control_ok'::pg_catalog.regclass, 1,
  exists (select 1 from pg_temp.resultados r
           where r.caso operator(pg_catalog.=) 'm1' and r.valor operator(pg_catalog.~~) 'ok:%'));
select pg_catalog.setval('pg_temp.control_directo'::pg_catalog.regclass,
  (select case when s.is_called then s.last_value else 1 end from pg_temp.sonda_privilegiada s),
  (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s) operator(pg_catalog.>) 0);
rollback to savepoint control_m1;

select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
set local role authenticated;
select pg_temp.intentar('post_m1', $$public.crear_camion('PGA2P-M2', 'Post control')$$);
reset role;
insert into pg_temp.resultados
select 'medida_post_m1',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text;

set local role authenticated;
drop domain pg_temp.uuid, pg_temp.text, pg_temp.date, pg_temp.jsonb;
drop view pg_temp.productos, pg_temp.camiones, pg_temp.clientes, pg_temp.perfiles, pg_temp.ubicaciones;
drop function pg_temp.sonda();
reset role;

-- ---------------------------------------------------------------------------
-- Afirmaciones (sin objetos hostiles)
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from resultados
    where caso ~ '^(cli_pend|prod|act_prod|est_prod|cam|act_cam|est_cam|cli|act_cli|validar|est_cli)L$'
      and valor like 'ok:%'),
  11,
  'Posterior: la ronda legítima completa las 10 RPC');

select is(
  (select string_agg(regexp_replace(l.caso, 'L$', '') || '=' || split_part(l.valor, ':', 1)
                     || (case when l.valor like 'error:%' then ':' || h.valor else '' end), ',' order by l.caso)
     from resultados l join resultados h on h.caso = regexp_replace(l.caso, 'L$', 'H')
    where l.caso like '%L'
      and (split_part(l.valor, ':', 1) <> split_part(h.valor, ':', 1)
           or (l.valor like 'error:%' and l.valor <> h.valor))),
  null,
  'Posterior: con los objetos hostiles cada RPC da el mismo resultado (éxito o el mismo error) que en la ronda legítima');

select is(
  (select valor from resultados where caso = 'b_camH'),
  'error:PT404:camion_no_encontrado',
  'Posterior: con objetos hostiles, otra empresa sigue respondiendo no encontrado');

select is(
  (select p.nombre || '|' || p.activo::text from public.productos p
    where p.id = (select substr(valor, 4)::uuid from resultados where caso = 'prodH'))
  || ';' || (select c.patente || '|' || c.activo::text from public.camiones c
              where c.id = (select substr(valor, 4)::uuid from resultados where caso = 'camH'))
  || ';' || (select c.estado_validacion from public.clientes c
              where c.id = (select substr(valor, 4)::uuid from resultados where caso = 'cli_pendH'))
  || ';' || (select activo::text from public.camiones where id = 'b8b8b8b8-1111-4000-8000-0000000000c1'),
  'Leche 2|false;PGA2P-XH|false;validado;true',
  'Posterior: estado final de la ronda hostil igual al contrato, y el camión de B sin cambios');

select is((select valor from resultados where caso = 'medida_hostil'), '0/0',
  'Posterior: 0 ejecuciones del código temporal (propietario_rpc / authenticated) en la ronda hostil');

select cmp_ok(pg_temp.ejecuciones_secuencia('pg_temp.control_directo'), '>', 0::bigint,
  'Posterior (control): con los cuerpos anteriores, crear_camion ejecuta el código temporal como propietario_rpc');

select is(pg_temp.ejecuciones_secuencia('pg_temp.control_ok')::text
          || '/' || (select split_part(valor, ':', 1) from resultados where caso = 'post_m1'),
  '1/ok',
  'Posterior (control): el mutante y la llamada posterior completan (el control mide ejecución, no un error)');

select is((select valor from resultados where caso = 'medida_post_m1'), '0',
  'Posterior: tras revertir el control, 0 ejecuciones del código temporal como propietario_rpc');

select * from finish();

rollback;
