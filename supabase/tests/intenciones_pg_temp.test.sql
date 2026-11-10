-- pgTAP: endurecimiento pg_temp de las RPC de intenciones — C1.2a, objetos hostiles
-- creados ANTES de la primera llamada de la sesión a las RPC de intenciones (el caso «después de una llamada legítima» está en intenciones_pg_temp_posterior.test.sql).
-- (ADR-001 §17.1 y §17.3; plan de remediación pg_temp A1/A3/B1; Blueprint §12 «Seguridad»).
--
-- Atacante modelado: authenticated (TEMP por PUBLIC). Crea en pg_temp dominios uuid, text,
-- jsonb, timestamptz y date cuyo CHECK llama a pg_temp.sonda() (secuencias temporales no
-- transaccionales: una para authenticated y otra para cualquier otro rol), vistas homónimas
-- de las tablas que tocan crear/ejecutar/cancelar, funciones homónimas (btrim, char_length,
-- octet_length, jsonb_typeof) y un operador = para text. Esperado: 0 ejecuciones como
-- propietario_rpc y los mismos resultados que sin objetos hostiles.
--
-- Como en A2/A3: pgTAP declara variables «text» sin esquema, así que no se lo llama mientras
-- existen los objetos hostiles; se mide con pg_temp.intentar(), se eliminan los objetos y
-- recién entonces se afirma.
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(25);

insert into public.empresas (id, nombre) values
  ('5e5e5e5e-0000-4000-8000-000000000000', 'Empresa A (test pg_temp intenciones antes)'),
  ('5f5f5f5f-0000-4000-8000-000000000000', 'Empresa B (test pg_temp intenciones antes)');
insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('5e5e5e5e-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pgiantes.a1@usuarios.distribuidora.invalid', '{}'),
  ('5e5e5e5e-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'pgiantes.a2@usuarios.distribuidora.invalid', '{}'),
  ('5e5e5e5e-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'pgiantes.a3@usuarios.distribuidora.invalid', '{}'),
  ('5f5f5f5f-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pgiantes.b1@usuarios.distribuidora.invalid', '{}');
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('5e5e5e5e-0000-4000-8000-000000000001', '5e5e5e5e-0000-4000-8000-000000000000', 'pgiantes.a1', 'Dueño A', 'dueno', true),
  ('5e5e5e5e-0000-4000-8000-000000000002', '5e5e5e5e-0000-4000-8000-000000000000', 'pgiantes.a2', 'Encargado A', 'encargado', true),
  ('5e5e5e5e-0000-4000-8000-000000000003', '5e5e5e5e-0000-4000-8000-000000000000', 'pgiantes.a3', 'Vendedor A', 'vendedor_piloto', true),
  ('5f5f5f5f-0000-4000-8000-000000000001', '5f5f5f5f-0000-4000-8000-000000000000', 'pgiantes.b1', 'Dueño B', 'dueno', true);
insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('5e5e5e5e-0000-4000-8000-0000000000f1', '5e5e5e5e-0000-4000-8000-000000000000', 'PGIantes-A1', 'Leche A', 'lacteos', 'unidad', 100, true, '5e5e5e5e-0000-4000-8000-000000000001');
insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('5e5e5e5e-0000-4000-8000-0000000000d1', '5e5e5e5e-0000-4000-8000-000000000000', 'deposito', null),
  ('5e5e5e5e-0000-4000-8000-0000000000d2', '5e5e5e5e-0000-4000-8000-000000000000', 'cuarentena', null);

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

create function pg_temp.ej(p_id pg_catalog.text) returns pg_catalog.text language sql as $f$
  select 'select (select e.estado || ''|'' || coalesce(e.operacion_id::pg_catalog.text, ''-'') || ''|'' || coalesce(e.codigo_rechazo, ''-'') '
      || 'from public.ejecutar_intencion_operacion(''' || p_id || '''::pg_catalog.uuid) e)'
$f$;
grant execute on function pg_temp.ej(pg_catalog.text) to public;

-- Ronda de llamadas; p_n (un dígito) distingue las claves; p_uid es un dueño o encargado de A.
create function pg_temp.ronda(p_sufijo pg_catalog.text, p_uid pg_catalog.text, p_n pg_catalog.text) returns pg_catalog.void
language plpgsql as $f$
declare
  v_pi pg_catalog.text := '"producto_id":"5e5e5e5e-0000-4000-8000-0000000000f1"';
  v_ub pg_catalog.text := '"ubicacion_origen_id":"5e5e5e5e-0000-4000-8000-0000000000d1"';
begin
  perform pg_catalog.set_config('request.jwt.claims', '{"sub":"' || p_uid || '","role":"authenticated"}', true);
  perform pg_temp.intentar('c_ingreso' || p_sufijo, 'public.crear_intencion_operacion(''5e5e5e5e-' || p_n || '001-4000-8000-000000000001'', ''ingreso'', ''{' || v_pi || ',"cantidad":3,"motivo":"Ronda"}'')');
  perform pg_temp.intentar('c_replay' || p_sufijo, 'public.crear_intencion_operacion(''5e5e5e5e-' || p_n || '001-4000-8000-000000000001'', ''ingreso'', ''{' || v_pi || ',"cantidad":3,"motivo":"Ronda"}'')');
  perform pg_temp.intentar('c_conflicto' || p_sufijo, 'public.crear_intencion_operacion(''5e5e5e5e-' || p_n || '001-4000-8000-000000000001'', ''ingreso'', ''{' || v_pi || ',"cantidad":4,"motivo":"Ronda"}'')');
  perform pg_temp.intentar('c_bloqueo' || p_sufijo, 'public.crear_intencion_operacion(''5e5e5e5e-' || p_n || '001-4000-8000-000000000009'', ''ingreso'', ''{' || v_pi || ',"cantidad":3,"motivo":null}'')');
  perform pg_temp.intentar('c_cuarentena' || p_sufijo, 'public.crear_intencion_operacion(''5e5e5e5e-' || p_n || '002-4000-8000-000000000001'', ''a_cuarentena'', ''{' || v_pi || ',' || v_ub || ',"cantidad":2,"motivo":"Golpe"}'')');
  perform pg_temp.intentar('c_merma' || p_sufijo, 'public.crear_intencion_operacion(''5e5e5e5e-' || p_n || '003-4000-8000-000000000001'', ''merma'', ''{' || v_pi || ',' || v_ub || ',"cantidad":1,"motivo_codigo":"vencido","motivo":null}'')');
  perform pg_temp.intentar('e_ingreso' || p_sufijo, pg_temp.ej('5e5e5e5e-' || p_n || '001-4000-8000-000000000001'));
  perform pg_temp.intentar('e_replay' || p_sufijo, pg_temp.ej('5e5e5e5e-' || p_n || '001-4000-8000-000000000001'));
  perform pg_temp.intentar('e_cuarentena' || p_sufijo, pg_temp.ej('5e5e5e5e-' || p_n || '002-4000-8000-000000000001'));
  perform pg_temp.intentar('x_merma' || p_sufijo, 'public.cancelar_intencion_operacion(''5e5e5e5e-' || p_n || '003-4000-8000-000000000001'')');
  perform pg_temp.intentar('e_cancelada' || p_sufijo, pg_temp.ej('5e5e5e5e-' || p_n || '003-4000-8000-000000000001'));
  perform pg_temp.intentar('c_merma2' || p_sufijo, 'public.crear_intencion_operacion(''5e5e5e5e-' || p_n || '004-4000-8000-000000000001'', ''merma'', ''{' || v_pi || ',' || v_ub || ',"cantidad":9999,"motivo_codigo":"vencido","motivo":null}'')');
  perform pg_temp.intentar('e_rechazo' || p_sufijo, pg_temp.ej('5e5e5e5e-' || p_n || '004-4000-8000-000000000001'));
  perform pg_temp.intentar('c_clave_nula' || p_sufijo, 'public.crear_intencion_operacion(null, ''venta'', ''{}'')');
  perform pg_catalog.set_config('request.jwt.claims', '{"sub":"5e5e5e5e-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform pg_temp.intentar('c_vendedor' || p_sufijo, 'public.crear_intencion_operacion(''5e5e5e5e-' || p_n || '005-4000-8000-000000000001'', ''ingreso'', ''{' || v_pi || ',"cantidad":1,"motivo":null}'')');
  perform pg_catalog.set_config('request.jwt.claims', '{"sub":"5f5f5f5f-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform pg_temp.intentar('e_otra_empresa' || p_sufijo, pg_temp.ej('5e5e5e5e-' || p_n || '001-4000-8000-000000000001'));
  perform pg_catalog.set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  perform pg_temp.intentar('c_sin_identidad' || p_sufijo, 'public.crear_intencion_operacion(''5e5e5e5e-' || p_n || '006-4000-8000-000000000001'', ''ingreso'', ''{' || v_pi || ',"cantidad":1,"motivo":null}'')');
end $f$;
grant execute on function pg_temp.ronda(pg_catalog.text, pg_catalog.text, pg_catalog.text) to public;

create function pg_temp.normal(p_v pg_catalog.text) returns pg_catalog.text language sql as $f$
  select pg_catalog.regexp_replace(p_v, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g')
$f$;

-- Stock inicial por la RPC real directa (no es una de las RPC bajo prueba).
select pg_catalog.set_config('request.jwt.claims', '{"sub":"5e5e5e5e-0000-4000-8000-000000000001","role":"authenticated"}', true) is not null;
set local role authenticated;
select public.registrar_ingreso('5e5e5e5e-9999-4000-8000-000000000001', '5e5e5e5e-0000-4000-8000-0000000000f1', 100) is not null;
reset role;

-- Calentamiento: compila los event triggers de sql_drop sin objetos hostiles.
create temp table calentamiento_sql_drop ();
drop table calentamiento_sql_drop;

set local role authenticated;
create temp sequence sonda_privilegiada;
create temp sequence sonda_llamador;
grant all on sequence sonda_privilegiada, sonda_llamador to public;
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
create temp view perfiles as select 1 as x where pg_temp.sonda();
create temp view intenciones_operacion as select 1 as x where pg_temp.sonda();
create temp view intenciones_reconocimientos as select 1 as x where pg_temp.sonda();
create temp view operaciones as select 1 as x where pg_temp.sonda();
create temp view movimientos_stock as select 1 as x where pg_temp.sonda();
create temp view productos as select 1 as x where pg_temp.sonda();
create temp view ubicaciones as select 1 as x where pg_temp.sonda();
create function pg_temp.btrim(pg_catalog.text) returns pg_catalog.text language plpgsql as $f$
begin perform pg_temp.sonda(); return $1; end $f$;
create function pg_temp.char_length(pg_catalog.text) returns pg_catalog.int4 language plpgsql as $f$
begin perform pg_temp.sonda(); return 0; end $f$;
create function pg_temp.octet_length(pg_catalog.text) returns pg_catalog.int4 language plpgsql as $f$
begin perform pg_temp.sonda(); return 0; end $f$;
create function pg_temp.jsonb_typeof(pg_catalog.jsonb) returns pg_catalog.text language plpgsql as $f$
begin perform pg_temp.sonda(); return 'object'; end $f$;
create function pg_temp.igual_hostil(pg_catalog.text, pg_catalog.text) returns pg_catalog.bool
language plpgsql as $f$ begin perform pg_temp.sonda(); return $1 operator(pg_catalog.=) $2; end $f$;
create operator pg_temp.= (leftarg = pg_catalog.text, rightarg = pg_catalog.text, function = pg_temp.igual_hostil);
grant execute on function pg_temp.btrim(pg_catalog.text), pg_temp.char_length(pg_catalog.text), pg_temp.octet_length(pg_catalog.text),
  pg_temp.jsonb_typeof(pg_catalog.jsonb), pg_temp.igual_hostil(pg_catalog.text, pg_catalog.text) to public;
create domain pg_temp.uuid as pg_catalog.uuid check (pg_temp.sonda());
create domain pg_temp.text as pg_catalog.text check (pg_temp.sonda());
create domain pg_temp.jsonb as pg_catalog.jsonb check (pg_temp.sonda());
create domain pg_temp.timestamptz as pg_catalog.timestamptz check (pg_temp.sonda());
create domain pg_temp.date as pg_catalog.date check (pg_temp.sonda());
reset role;

insert into pg_temp.resultados
select 'hostiles',
       (select pg_catalog.count(*) from pg_catalog.pg_type t
         where t.typnamespace operator(pg_catalog.=) pg_catalog.pg_my_temp_schema() and t.typtype operator(pg_catalog.=) 'd')::pg_catalog.text
       || '/' || (select pg_catalog.count(*) from pg_catalog.pg_class c
                   where c.relnamespace operator(pg_catalog.=) pg_catalog.pg_my_temp_schema() and c.relkind operator(pg_catalog.=) 'v')::pg_catalog.text
       || '/' || (select pg_catalog.count(*) from pg_catalog.pg_operator o
                   where o.oprnamespace operator(pg_catalog.=) pg_catalog.pg_my_temp_schema())::pg_catalog.text;

-- Ronda con los objetos hostiles presentes.
select pg_temp.ronda('_H', '5e5e5e5e-0000-4000-8000-000000000001', '2');

insert into pg_temp.resultados
select 'medida',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text
       || '/' || (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_llamador s)::pg_catalog.text;

-- Control positivo: una referencia SIN calificar a text, desde una sesión con pg_temp primero, SÍ ejecuta
-- el dominio hostil como el rol de la sesión (el vector existe; la medición anterior no es vacía).
select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
do $c$ begin perform 'x'::text; end $c$;
insert into pg_temp.resultados
select 'control_positivo',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text;

set local role authenticated;
drop domain pg_temp.uuid, pg_temp.text, pg_temp.jsonb, pg_temp.timestamptz, pg_temp.date;
drop view pg_temp.perfiles, pg_temp.intenciones_operacion, pg_temp.intenciones_reconocimientos, pg_temp.operaciones,
  pg_temp.movimientos_stock, pg_temp.productos, pg_temp.ubicaciones;
drop operator pg_temp.=(pg_catalog.text, pg_catalog.text);
drop function pg_temp.btrim(pg_catalog.text), pg_temp.char_length(pg_catalog.text), pg_temp.octet_length(pg_catalog.text),
  pg_temp.jsonb_typeof(pg_catalog.jsonb), pg_temp.igual_hostil(pg_catalog.text, pg_catalog.text), pg_temp.sonda();
reset role;

-- ===========================================================================
-- Afirmaciones (sin objetos hostiles)
-- ===========================================================================
select is((select valor from resultados where caso = 'hostiles'), '5/7/1',
  'P1: los objetos hostiles existían (5 dominios, 7 vistas y 1 operador en pg_temp)');
select is(split_part((select valor from resultados where caso = 'medida'), '/', 1), '0',
  'P3/P4: la sonda NO se ejecutó como propietario_rpc ni como ningún rol distinto de authenticated al llamar a crear, ejecutar y cancelar');
select is(pg_temp.normal((select valor from resultados where caso = 'c_ingreso_H')), 'ok:U',
  'P3: c_ingreso con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'c_replay_H')), 'ok:U',
  'P3: c_replay con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'c_conflicto_H')), 'error:PT409:intencion_conflicto',
  'P3: c_conflicto con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'c_bloqueo_H')), 'error:PT409:intencion_sin_resolver',
  'P3: c_bloqueo con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'c_cuarentena_H')), 'ok:U',
  'P3: c_cuarentena con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'c_merma_H')), 'ok:U',
  'P3: c_merma con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'e_ingreso_H')), 'ok:confirmada|U|-',
  'P3: e_ingreso con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'e_replay_H')), 'ok:confirmada|U|-',
  'P3: e_replay con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'e_cuarentena_H')), 'ok:confirmada|U|-',
  'P3: e_cuarentena con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'x_merma_H')), 'ok:cancelada',
  'P3: x_merma con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'e_cancelada_H')), 'error:PT409:intencion_cancelada',
  'P3: e_cancelada con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'c_merma2_H')), 'ok:U',
  'P3: c_merma2 con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'e_rechazo_H')), 'ok:rechazada|-|stock_insuficiente',
  'P3: e_rechazo con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'c_clave_nula_H')), 'error:PT400:intencion_clave_invalida',
  'P3: c_clave_nula con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'c_vendedor_H')), 'error:PT403:intencion_no_autorizado',
  'P3: c_vendedor con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'e_otra_empresa_H')), 'error:PT404:intencion_no_encontrada',
  'P3: e_otra_empresa con objetos hostiles presentes');
select is(pg_temp.normal((select valor from resultados where caso = 'c_sin_identidad_H')), 'error:PT401:intencion_no_autenticado',
  'P3: c_sin_identidad con objetos hostiles presentes');

select is(
  (select string_agg(x.proname || ':' || x.esquemas, ';' order by x.proname)
     from (select p.proname::text, string_agg(n.nspname::text, ',' order by n.nspname) as esquemas
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where p.proname like '%intencion%' group by p.proname) x),
  'cancelar_intencion_operacion:privado,public;crear_intencion_operacion:privado,public;ejecutar_intencion_operacion:privado,public',
  'P8: sin sobrecargas ni homónimos');
select is(
  (select encode(sha256(convert_to(prosrc, 'UTF8')), 'hex') from pg_proc where oid = 'privado.usuario_actual()'::regprocedure),
  '2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96', 'P8: usuario_actual sigue con el cuerpo de A1');

-- P7 — guardia estática (léxica, sin literales ni comentarios), la misma de A3/B1.
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
                   || '|((?<![.\w"])(uuid|text|date|jsonb|json|bytea|name|oid|timestamptz|timetz|int2|int4|int8|bool|float4|float8|inet|money|xml|regclass|regtype|regprocedure|regrole|regnamespace)\s*'''')'
                   || '|(\m(from|join|update|insert\s+into|delete\s+from)\s+(?!(pg_catalog|public|privado|auth|extensions)\s*\.|\(|[vp]_)[a-z_"])',
                   'gi'))
    from declare_ x
$f$;
select is(
  (select coalesce(string_agg(p.oid::regprocedure::text || '=' || pg_temp.refs_sin_calificar(p.prosrc)::text, ',' order by p.oid::regprocedure::text), '')
     from pg_proc p
    where (p.pronamespace = 'privado'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.prosecdef))
      and p.prokind = 'f' and pg_temp.refs_sin_calificar(p.prosrc) > 0),
  '', 'P7: ninguna función de privado ni SECURITY DEFINER de public (incluidas las 3 nuevas) conserva referencias resolubles por pg_temp');
select is(
  (select string_agg(pg_temp.refs_sin_calificar(replace(replace(replace(p.prosrc, 'pg_catalog.uuid', 'uuid'), 'pg_catalog.text', 'text'), 'pg_catalog.jsonb', 'jsonb'))::text, '/' order by p.proname)
     from pg_proc p where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('crear_intencion_operacion', 'ejecutar_intencion_operacion', 'cancelar_intencion_operacion')) ~ '^[1-9][0-9]*/[1-9][0-9]*/[1-9][0-9]*$',
  true, 'P7 (control M1): revirtiendo las calificaciones de uuid/text/jsonb el detector encuentra referencias en las 3 funciones nuevas');
select is(
  pg_temp.refs_sin_calificar($m$
declare
  v_a pg_catalog.text := 'x::text';  -- y::text date '2000-01-01'
  v_n bigint;
begin
  perform 'a'::pg_catalog.text, 1::bigint, p_id::text, date '2000-01-01';
end $m$),
  2, 'P7 (control M2): ni un literal ni un comentario ocultan el cast y el literal tipado reales sin calificar');
select cmp_ok((select valor from resultados where caso = 'control_positivo')::int, '>=', 1,
  'P6 (control positivo): una referencia sin calificar a text SÍ ejecuta el dominio hostil como el rol de la sesión');

select * from finish();

rollback;
