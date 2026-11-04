-- pgTAP: endurecimiento pg_temp de las RPC de jornadas — B1 (plan de
-- remediación pg_temp, alternativa A; ADR-001 §17.1 y §18.4; ADR-007 §2.1;
-- Blueprint §7.3 y §12). Objetos hostiles creados ANTES de la primera llamada
-- de la sesión; el caso «después de una llamada legítima» está en
-- pg_temp_jornadas_posterior.test.sql.
--
-- Atacante modelado: authenticated (TEMP por PUBLIC). Crea en pg_temp dominios
-- uuid, text, date y jsonb cuyo CHECK llama a pg_temp.sonda() (secuencias
-- temporales, no transaccionales: una para authenticated y otra para cualquier
-- otro rol), vistas homónimas de las tablas que tocan estas RPC, funciones
-- homónimas (encode, to_char) y un operador = para text. Esperado: 0 ejecuciones
-- como propietario_rpc, mismas huellas v1 y mismos efectos.
--
-- Como en A2/A3: pgTAP declara variables «text» sin esquema, así que no se lo
-- llama mientras existen los objetos hostiles; se mide con pg_temp.intentar(),
-- se eliminan los objetos y recién entonces se afirma. Un DROP inocuo previo
-- compila los event triggers de sql_drop de la plataforma antes de los dominios.
--
-- Base: cuerpos con la guarda GET/HEAD (E-SL1, aprobada para validación
-- controlada el 04/11/2026; migración 20261104120000). Se prueba además que la
-- guarda sigue como paso 0 y rechaza las transacciones de sólo lectura con los
-- objetos hostiles presentes. La guardia estática P7 cubre además TODAS las funciones de privado
-- y todas las SECURITY DEFINER de public: con A1–A3 y B1 ninguna conserva
-- referencias de tipo resolubles por pg_temp.
--
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final). Ninguna RPC se
-- llama antes de crear los objetos hostiles.
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('b1b1b1b1-0000-4000-8000-000000000000', 'Empresa A (test pg_temp B1)'),
  ('c1c1c1c1-0000-4000-8000-000000000000', 'Empresa B (test pg_temp B1)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('b1b1b1b1-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pgb1.a1@usuarios.distribuidora.invalid', '{}'),
  ('b1b1b1b1-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'pgb1.a2@usuarios.distribuidora.invalid', '{}'),
  ('b1b1b1b1-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'pgb1.a3@usuarios.distribuidora.invalid', '{}'),
  ('b1b1b1b1-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'pgb1.a4@usuarios.distribuidora.invalid', '{}'),
  ('b1b1b1b1-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'pgb1.a5@usuarios.distribuidora.invalid', '{}'),
  ('b1b1b1b1-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'pgb1.a6@usuarios.distribuidora.invalid', '{}'),
  ('c1c1c1c1-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pgb1.b1@usuarios.distribuidora.invalid', '{}'),
  ('c1c1c1c1-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'pgb1.b2@usuarios.distribuidora.invalid', '{}');

-- A: dueño (1), encargado (2) y vendedores (3, 4, 5, 6). B: dueño y vendedor.
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('b1b1b1b1-0000-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-000000000000', 'pgb1.a1', 'Dueño A', 'dueno', true),
  ('b1b1b1b1-0000-4000-8000-000000000002', 'b1b1b1b1-0000-4000-8000-000000000000', 'pgb1.a2', 'Encargado A', 'encargado', true),
  ('b1b1b1b1-0000-4000-8000-000000000003', 'b1b1b1b1-0000-4000-8000-000000000000', 'pgb1.a3', 'Vendedor A3', 'vendedor_piloto', true),
  ('b1b1b1b1-0000-4000-8000-000000000004', 'b1b1b1b1-0000-4000-8000-000000000000', 'pgb1.a4', 'Vendedor A4', 'vendedor_piloto', true),
  ('b1b1b1b1-0000-4000-8000-000000000005', 'b1b1b1b1-0000-4000-8000-000000000000', 'pgb1.a5', 'Vendedor A5', 'vendedor_piloto', true),
  ('b1b1b1b1-0000-4000-8000-000000000006', 'b1b1b1b1-0000-4000-8000-000000000000', 'pgb1.a6', 'Vendedor A6', 'vendedor_piloto', true),
  ('c1c1c1c1-0000-4000-8000-000000000001', 'c1c1c1c1-0000-4000-8000-000000000000', 'pgb1.b1', 'Dueño B', 'dueno', true),
  ('c1c1c1c1-0000-4000-8000-000000000002', 'c1c1c1c1-0000-4000-8000-000000000000', 'pgb1.b2', 'Vendedor B', 'vendedor_piloto', true);

insert into public.camiones (id, empresa_id, patente, nombre, activo, creado_por) values
  ('b1b1b1b1-0000-4000-8000-0000000000c1', 'b1b1b1b1-0000-4000-8000-000000000000', 'PB1-01', 'Camión A1', true, 'b1b1b1b1-0000-4000-8000-000000000001'),
  ('b1b1b1b1-0000-4000-8000-0000000000c2', 'b1b1b1b1-0000-4000-8000-000000000000', 'PB1-02', 'Camión A2', true, 'b1b1b1b1-0000-4000-8000-000000000001'),
  ('b1b1b1b1-0000-4000-8000-0000000000c3', 'b1b1b1b1-0000-4000-8000-000000000000', 'PB1-03', 'Camión A3', false, 'b1b1b1b1-0000-4000-8000-000000000001'),
  ('b1b1b1b1-0000-4000-8000-0000000000c4', 'b1b1b1b1-0000-4000-8000-000000000000', 'PB1-04', 'Camión A4', true, 'b1b1b1b1-0000-4000-8000-000000000001'),
  ('b1b1b1b1-0000-4000-8000-0000000000c5', 'b1b1b1b1-0000-4000-8000-000000000000', 'PB1-05', 'Camión A5', true, 'b1b1b1b1-0000-4000-8000-000000000001'),
  ('c1c1c1c1-0000-4000-8000-0000000000c1', 'c1c1c1c1-0000-4000-8000-000000000000', 'PB1-B1', 'Camión B1', true, 'c1c1c1c1-0000-4000-8000-000000000001');

-- T5: depósito, ubicación del camión c1 y un producto con stock (ingreso como owner,
-- sin llamar a ninguna RPC) para registrar_carga con los objetos hostiles presentes.
insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('b1b1b1b1-0000-4000-8000-0000000000d1', 'b1b1b1b1-0000-4000-8000-000000000000', 'deposito', null),
  ('b1b1b1b1-0000-4000-8000-0000000000e1', 'b1b1b1b1-0000-4000-8000-000000000000', 'camion', 'b1b1b1b1-0000-4000-8000-0000000000c1');
insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('b1b1b1b1-0000-4000-8000-0000000000f1', 'b1b1b1b1-0000-4000-8000-000000000000', 'PB1-P1', 'Leche A', 'lacteos', 'unidad', 100, true, 'b1b1b1b1-0000-4000-8000-000000000001');
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella) values
  ('b1b1b1b1-0000-4000-8000-0000000000b0', 'b1b1b1b1-0000-4000-8000-000000000000', 'b1b1b1b1-0000-4000-8000-000000000001',
   'ingreso', 'b1b1b1b1-0000-4000-8000-0000000000b0', repeat('e', 64));
insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                      ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo) values
  ('b1b1b1b1-0000-4000-8000-000000000000', 'b1b1b1b1-0000-4000-8000-0000000000b0', 'ingreso',
   'b1b1b1b1-0000-4000-8000-0000000000f1', 50, null, 'b1b1b1b1-0000-4000-8000-0000000000d1',
   'b1b1b1b1-0000-4000-8000-000000000001', 'fixture T5');

-- Jornada de B creada como fixture (sin llamar a la RPC: no se compila nada
-- antes de los objetos hostiles).
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella) values
  ('c1c1c1c1-0000-4000-8000-0000000000a1', 'c1c1c1c1-0000-4000-8000-000000000000', 'c1c1c1c1-0000-4000-8000-000000000001',
   'apertura_jornada', 'c1c1c1c1-0000-4000-8000-0000000000a0', repeat('c', 64));
insert into public.jornadas (id, empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id) values
  ('c1c1c1c1-0000-4000-8000-0000000000a1', 'c1c1c1c1-0000-4000-8000-000000000000', date '2999-03-01',
   'c1c1c1c1-0000-4000-8000-0000000000c1', 'c1c1c1c1-0000-4000-8000-000000000002', 'abierta',
   'c1c1c1c1-0000-4000-8000-000000000001', 'c1c1c1c1-0000-4000-8000-0000000000a1');

create temp table huella_b as
select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.jornadas t
         where t.empresa_id = 'c1c1c1c1-0000-4000-8000-000000000000')
       || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.operaciones t
                   where t.empresa_id = 'c1c1c1c1-0000-4000-8000-000000000000')
       || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.camiones t
                   where t.empresa_id = 'c1c1c1c1-0000-4000-8000-000000000000')
       || '/' || (select count(*)::text from public.reasignaciones_vendedor t
                   where t.empresa_id = 'c1c1c1c1-0000-4000-8000-000000000000') as huella;

-- ===========================================================================
-- P8 — catálogo (antes de los objetos hostiles; no se llama ninguna RPC)
-- ===========================================================================
select is(
  (select string_agg(p.oid::regprocedure::text || '|' || encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex'), ','
                     order by p.oid::regprocedure::text)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('abrir_jornada', 'reasignar_vendedor')),
  'privado.abrir_jornada(uuid,uuid,date,uuid)|7e2f2d07ffe75a90af6fba379c32d874ca3d229daa7c841f300aef5f467c5440,privado.reasignar_vendedor(uuid,uuid,uuid)|6593c5e2e1ed10d47ca1d880eee3e53ff9809596987d5f33f8beedef6ba618dd',
  'P8: los 2 cuerpos son exactamente los de B1 (SHA-256)');

select is(
  (select string_agg(p.oid::regprocedure::text || '|'
                     || encode(sha256(convert_to(replace(replace(replace(p.prosrc, 'pg_catalog.uuid', 'uuid'),
                                                                 'pg_catalog.text', 'text'),
                                                         'pg_catalog.date', 'date'), 'UTF8')), 'hex'), ','
                     order by p.oid::regprocedure::text)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('abrir_jornada', 'reasignar_vendedor')),
  'privado.abrir_jornada(uuid,uuid,date,uuid)|f6f88764d337df49f2d05fdb8deaafd6a5be9e13500c38caf8be31b143faea07,privado.reasignar_vendedor(uuid,uuid,uuid)|381e59c479faad5e5e7829311da859640adbdab702054582cf1d198ce9e58943',
  'P8: equivalencia mecánica — revirtiendo «pg_catalog.uuid», «pg_catalog.text» y «pg_catalog.date» se obtienen los cuerpos con la guarda GET/HEAD (20261104120000)');

select is(
  (select string_agg(p.oid::regprocedure::text || '|'
                     || ((length(p.prosrc) - length(replace(p.prosrc, 'pg_catalog.uuid', ''))) / length('pg_catalog.uuid')
                         + (length(p.prosrc) - length(replace(p.prosrc, 'pg_catalog.text', ''))) / length('pg_catalog.text')
                         + (length(p.prosrc) - length(replace(p.prosrc, 'pg_catalog.date', ''))) / length('pg_catalog.date'))::text
                     || '|' || ((length(p.prosrc) - length(replace(p.prosrc, 'pg_catalog.', ''))) / length('pg_catalog.'))::text, ','
                     order by p.oid::regprocedure::text)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('abrir_jornada', 'reasignar_vendedor')),
  'privado.abrir_jornada(uuid,uuid,date,uuid)|19|27,privado.reasignar_vendedor(uuid,uuid,uuid)|24|36',
  'P8: 43 calificaciones nuevas (19/24) más las 8 y 12 previas de funciones (incluida la de la guarda)');

select is(
  (select string_agg(p.oid::regprocedure::text || '|' || encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex'), ','
                     order by p.oid::regprocedure::text)
     from pg_proc p
    where p.oid in ('privado.usuario_actual()'::regprocedure,
                    'public.abrir_jornada(uuid,uuid,date,uuid)'::regprocedure,
                    'public.reasignar_vendedor(uuid,uuid,uuid)'::regprocedure)),
  'abrir_jornada(uuid,uuid,date,uuid)|349c03bf2c303f757d8fa97dc55aff6f85b4b463b85c3e3b901f39f3c28e9115,'
  || 'privado.usuario_actual()|2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96,'
  || 'reasignar_vendedor(uuid,uuid,uuid)|bb55c733a1c8e1c3506763482b05a46a40cc5602de5f49c0c9411b7da0c0b2df',
  'P8: usuario_actual sigue con el cuerpo de A1 y las fachadas public de T1/T2 sin cambios');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('abrir_jornada', 'reasignar_vendedor')
      and p.prosecdef and p.provolatile = 'v'
      and p.proowner = 'propietario_rpc'::regrole
      and p.proconfig = array['search_path=""']
      and array(select a::text from unnest(p.proacl) a order by 1)
          = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']),
  2,
  'P8: las 2 RPC siguen SECURITY DEFINER, VOLATILE, de propietario_rpc, con search_path vacío y ACL exacta');

select ok(
  not exists (
    select 1 from pg_proc p, unnest(array['anon', 'service_role']) r
     where p.pronamespace in ('privado'::regnamespace, 'public'::regnamespace)
       and p.proname in ('abrir_jornada', 'reasignar_vendedor')
       and has_function_privilege(r, p.oid, 'EXECUTE'))
  and not has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
  and (select nspacl::text from pg_namespace where nspname = 'privado')
      = '{postgres=UC/postgres,authenticated=U/postgres,propietario_rpc=U/postgres}',
  'P8/P11: anon y service_role sin EXECUTE; sin CREATE residual y ACL de privado sin cambios');

select is(
  (select string_agg(x.proname || ':' || x.esquemas, ';' order by x.proname)
     from (select p.proname::text, string_agg(n.nspname::text, ',' order by n.nspname) as esquemas
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where p.proname in ('abrir_jornada', 'reasignar_vendedor')
            group by p.proname) x),
  'abrir_jornada:privado,public;reasignar_vendedor:privado,public',
  'P8: sin sobrecargas ni homónimos nuevos');

-- ===========================================================================
-- P7 — guardia estática (léxica, sin literales ni comentarios)
-- ===========================================================================
-- Como en A3, más los literales tipados («date '…'», «uuid '…'»): los cuerpos
-- de jornadas usan «date '0001-01-01'», que también resuelve por search_path.
-- La alternativa de relaciones ignora las variables v_/p_ (como
-- analizar_cuerpos.py): «is distinct from v_vigente» no es una relación.
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
                   || '|((?<![.\w"])(uuid|text|date|jsonb|json|bytea|name|oid|timestamptz|timetz|int2|int4|int8|bool|float4|float8|inet|money|xml|regclass|regtype|regprocedure|regrole|regnamespace)\s*'''')'
                   || '|(\m(from|join|update|insert\s+into|delete\s+from)\s+(?!(pg_catalog|public|privado|auth|extensions)\s*\.|\(|[vp]_)[a-z_"])',
                   'gi'))
    from declare_ x
$f$;

select is(
  (select coalesce(string_agg(p.oid::regprocedure::text || '=' || pg_temp.refs_sin_calificar(p.prosrc)::text, ','
                              order by p.oid::regprocedure::text), '')
     from pg_proc p
    where (p.pronamespace = 'privado'::regnamespace
           or (p.pronamespace = 'public'::regnamespace and p.prosecdef))
      and p.prokind = 'f'
      and pg_temp.refs_sin_calificar(p.prosrc) > 0),
  '',
  'P7: ninguna función de privado ni SECURITY DEFINER de public conserva referencias resolubles por pg_temp (A1–A3 + B1)');

select is(
  (select string_agg(pg_temp.refs_sin_calificar(replace(replace(replace(p.prosrc, 'pg_catalog.uuid', 'uuid'),
                                                                'pg_catalog.text', 'text'),
                                                        'pg_catalog.date', 'date'))::text, '/'
                     order by p.proname)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('abrir_jornada', 'reasignar_vendedor')),
  '19/24',
  'P7 (control M1): el detector encuentra las 19/24 referencias de los cuerpos anteriores (incluidos los 2 literales «date ''…''»; no cuenta boolean)');

select is(
  pg_temp.refs_sin_calificar($m$
declare
  v_a pg_catalog.text := 'x::text';  -- y::text date '2000-01-01'
  v_d pg_catalog.date := pg_catalog.date '2000-01-01';
  v_n bigint;
begin
  perform 'a'::pg_catalog.text, 1::bigint, p_id::text, date '2000-01-01';
end $m$),
  2,
  'P7 (control M2): ni un literal ni un comentario ocultan el cast y el literal tipado reales sin calificar');

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
create temp sequence control_ok;
create temp sequence control_ro;
create temp sequence control_ro_priv;
grant all on sequence sonda_privilegiada, sonda_llamador, control_directo, control_mutante, control_ok,
  control_ro, control_ro_priv to public;
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
create temp view camiones as select 1 as x where pg_temp.sonda();
create temp view perfiles as select 1 as x where pg_temp.sonda();
create temp view perfiles_empresa_gestion as select 1 as x where pg_temp.sonda();
create temp view movimientos_stock as select 1 as x where pg_temp.sonda();
create temp view productos as select 1 as x where pg_temp.sonda();
create temp view ubicaciones as select 1 as x where pg_temp.sonda();
create function pg_temp.encode(pg_catalog.bytea, pg_catalog.text) returns pg_catalog.text language plpgsql as $f$
begin perform pg_temp.sonda(); return 'x'; end $f$;
create function pg_temp.to_char(pg_catalog.date, pg_catalog.text) returns pg_catalog.text language plpgsql as $f$
begin perform pg_temp.sonda(); return 'x'; end $f$;
create function pg_temp.igual_hostil(pg_catalog.text, pg_catalog.text) returns pg_catalog.bool
language plpgsql as $f$ begin perform pg_temp.sonda(); return $1 operator(pg_catalog.=) $2; end $f$;
create operator pg_temp.= (leftarg = pg_catalog.text, rightarg = pg_catalog.text,
                           function = pg_temp.igual_hostil);
grant execute on function pg_temp.encode(pg_catalog.bytea, pg_catalog.text),
  pg_temp.to_char(pg_catalog.date, pg_catalog.text),
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
-- P2 / P4 — llamadas por las fachadas public como authenticated
-- ===========================================================================
set local role authenticated;

-- Vendedor de A y sin identidad: rechazo antes de cualquier escritura.
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"b1b1b1b1-0000-4000-8000-000000000003","role":"authenticated"}', true) is not null;
select pg_temp.intentar('rol_abrir', $$public.abrir_jornada('b1b1b1b1-1111-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-0000000000c1', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000003')$$);
select pg_temp.intentar('rol_reasignar', $$public.reasignar_vendedor('b1b1b1b1-1111-4000-8000-000000000002', 'c1c1c1c1-0000-4000-8000-0000000000a1', 'b1b1b1b1-0000-4000-8000-000000000004')$$);
select pg_catalog.set_config('request.jwt.claims', '{"role":"authenticated"}', true) is not null;
select pg_temp.intentar('sin_identidad', $$public.abrir_jornada('b1b1b1b1-1111-4000-8000-000000000003', 'b1b1b1b1-0000-4000-8000-0000000000c1', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000003')$$);

-- Dueño de A: apertura, replay, conflicto de huella, reglas de ADR-007 §2.1 y reasignación.
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"b1b1b1b1-0000-4000-8000-000000000001","role":"authenticated"}', true) is not null;
select pg_temp.intentar('abrir', $$public.abrir_jornada('b1b1b1b1-2222-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-0000000000c1', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000003')$$);
select pg_temp.intentar('replay_abrir', $$public.abrir_jornada('b1b1b1b1-2222-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-0000000000c1', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000003')$$);
select pg_temp.intentar('conflicto_abrir', $$public.abrir_jornada('b1b1b1b1-2222-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-0000000000c1', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000004')$$);
select pg_temp.intentar('duplicada', $$public.abrir_jornada('b1b1b1b1-2222-4000-8000-000000000002', 'b1b1b1b1-0000-4000-8000-0000000000c1', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000004')$$);
select pg_temp.intentar('vendedor_ocupado', $$public.abrir_jornada('b1b1b1b1-2222-4000-8000-000000000003', 'b1b1b1b1-0000-4000-8000-0000000000c2', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000003')$$);
select pg_temp.intentar('camion_inactivo', $$public.abrir_jornada('b1b1b1b1-2222-4000-8000-000000000004', 'b1b1b1b1-0000-4000-8000-0000000000c3', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000004')$$);
select pg_temp.intentar('fecha_pasada', $$public.abrir_jornada('b1b1b1b1-2222-4000-8000-000000000005', 'b1b1b1b1-0000-4000-8000-0000000000c2', '2000-01-01', 'b1b1b1b1-0000-4000-8000-000000000004')$$);
select pg_temp.intentar('reasignar', pg_catalog.format($$public.reasignar_vendedor('b1b1b1b1-2222-4000-8000-000000000006', %L, 'b1b1b1b1-0000-4000-8000-000000000004')$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));
select pg_temp.intentar('replay_reasignar', pg_catalog.format($$public.reasignar_vendedor('b1b1b1b1-2222-4000-8000-000000000006', %L, 'b1b1b1b1-0000-4000-8000-000000000004')$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));
select pg_temp.intentar('sin_cambios', pg_catalog.format($$public.reasignar_vendedor('b1b1b1b1-2222-4000-8000-000000000007', %L, 'b1b1b1b1-0000-4000-8000-000000000004')$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));

-- T5: registrar_carga sobre la jornada abierta (ya reasignada) y su replay.
select pg_temp.intentar('cargar', pg_catalog.format($$public.registrar_carga('b1b1b1b1-2222-4000-8000-000000000008', %L, array['b1b1b1b1-0000-4000-8000-0000000000f1']::pg_catalog.uuid[], array[5])$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));
select pg_temp.intentar('replay_cargar', pg_catalog.format($$public.registrar_carga('b1b1b1b1-2222-4000-8000-000000000008', %L, array['b1b1b1b1-0000-4000-8000-0000000000f1']::pg_catalog.uuid[], array[5])$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));

-- T6: registrar_descarga sobre la jornada ya cargada (motivo con espacios laterales) y su replay.
select pg_temp.intentar('descargar', pg_catalog.format($$public.registrar_descarga('b1b1b1b1-2222-4000-8000-000000000009', %L, array['b1b1b1b1-0000-4000-8000-0000000000f1']::pg_catalog.uuid[], array[2], '  Sobrante ')$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));
select pg_temp.intentar('replay_descargar', pg_catalog.format($$public.registrar_descarga('b1b1b1b1-2222-4000-8000-000000000009', %L, array['b1b1b1b1-0000-4000-8000-0000000000f1']::pg_catalog.uuid[], array[2], 'Sobrante')$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));

-- T7: confirmar_salida de la jornada cargada (carga neta 3) y su replay.
select pg_temp.intentar('salir', pg_catalog.format($$public.confirmar_salida('b1b1b1b1-2222-4000-8000-00000000000a', %L)$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));
select pg_temp.intentar('replay_salir', pg_catalog.format($$public.confirmar_salida('b1b1b1b1-2222-4000-8000-00000000000a', %L)$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));

-- Dueño de A con objetos de la empresa B.
select pg_temp.intentar('b_camion', $$public.abrir_jornada('b1b1b1b1-3333-4000-8000-000000000001', 'c1c1c1c1-0000-4000-8000-0000000000c1', '2999-03-02', 'b1b1b1b1-0000-4000-8000-000000000005')$$);
select pg_temp.intentar('b_vendedor', $$public.abrir_jornada('b1b1b1b1-3333-4000-8000-000000000002', 'b1b1b1b1-0000-4000-8000-0000000000c4', '2999-03-02', 'c1c1c1c1-0000-4000-8000-000000000002')$$);
select pg_temp.intentar('b_jornada', $$public.reasignar_vendedor('b1b1b1b1-3333-4000-8000-000000000003', 'c1c1c1c1-0000-4000-8000-0000000000a1', 'b1b1b1b1-0000-4000-8000-000000000005')$$);

-- Encargado de A: también abre jornadas.
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"b1b1b1b1-0000-4000-8000-000000000002","role":"authenticated"}', true) is not null;
select pg_temp.intentar('encargado_abrir', $$public.abrir_jornada('b1b1b1b1-4444-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-0000000000c2', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000005')$$);
reset role;

insert into pg_temp.resultados
select 'medida_p2',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text
       || '/' || (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_llamador s)::pg_catalog.text;

-- ===========================================================================
-- E-SL1 — guarda GET/HEAD con los objetos hostiles presentes: en una
-- transacción de sólo lectura (como GET/HEAD por PostgREST) las 2 RPC
-- responden 25006 antes de cualquier replay, con clave nueva, con clave usada
-- y misma huella, y con clave usada y otra huella. resultados es transaccional:
-- lo medido se guarda en secuencias y el subbloque se revierte.
-- ===========================================================================
select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
savepoint solo_lectura;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"b1b1b1b1-0000-4000-8000-000000000001","role":"authenticated"}', true) is not null;
set local transaction_read_only = on;
select pg_temp.intentar('ro_abrir_nueva', $$public.abrir_jornada('b1b1b1b1-6666-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-0000000000c4', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000006')$$);
select pg_temp.intentar('ro_abrir_replay', $$public.abrir_jornada('b1b1b1b1-2222-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-0000000000c1', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000003')$$);
select pg_temp.intentar('ro_abrir_otra_huella', $$public.abrir_jornada('b1b1b1b1-2222-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-0000000000c1', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000004')$$);
select pg_temp.intentar('ro_reasignar_replay', pg_catalog.format($$public.reasignar_vendedor('b1b1b1b1-2222-4000-8000-000000000006', %L, 'b1b1b1b1-0000-4000-8000-000000000004')$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));
select pg_temp.intentar('ro_cargar_replay', pg_catalog.format($$public.registrar_carga('b1b1b1b1-2222-4000-8000-000000000008', %L, array['b1b1b1b1-0000-4000-8000-0000000000f1']::pg_catalog.uuid[], array[5])$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));
select pg_temp.intentar('ro_descargar_replay', pg_catalog.format($$public.registrar_descarga('b1b1b1b1-2222-4000-8000-000000000009', %L, array['b1b1b1b1-0000-4000-8000-0000000000f1']::pg_catalog.uuid[], array[2], 'Sobrante')$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));
select pg_temp.intentar('ro_salir_replay', pg_catalog.format($$public.confirmar_salida('b1b1b1b1-2222-4000-8000-00000000000a', %L)$$,
  (select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r where r.caso operator(pg_catalog.=) 'abrir')));
select pg_catalog.setval('pg_temp.control_ro'::pg_catalog.regclass,
  (select pg_catalog.count(*) from pg_temp.resultados r
    where r.caso operator(pg_catalog.~~) 'ro\_%'
      and r.valor operator(pg_catalog.=) 'error:25006:jornada_metodo_no_permitido') operator(pg_catalog.+) 1, false);
select pg_catalog.setval('pg_temp.control_ro_priv'::pg_catalog.regclass,
  (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s) operator(pg_catalog.+) 1, false);
reset role;
rollback to savepoint solo_lectura;

-- ===========================================================================
-- P6 — control del detector: cuerpo anterior de abrir_jornada
-- ===========================================================================
select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
savepoint control_m1;
grant create on schema privado to propietario_rpc;
set local role propietario_rpc;
do $c$
begin
  execute pg_catalog.format(
    'create or replace function privado.abrir_jornada(p_idempotency_key pg_catalog.uuid, '
    || 'p_camion_id pg_catalog.uuid, p_fecha pg_catalog.date, p_vendedor_id pg_catalog.uuid) '
    || 'returns pg_catalog.uuid language plpgsql volatile security definer set search_path = %L as %L', '',
    (select pg_catalog.replace(pg_catalog.replace(pg_catalog.replace(p.prosrc, 'pg_catalog.uuid', 'uuid'),
                                                  'pg_catalog.text', 'text'), 'pg_catalog.date', 'date')
       from pg_catalog.pg_proc p
      where p.oid operator(pg_catalog.=) 'privado.abrir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid)'::pg_catalog.regprocedure));
end $c$;
reset role;
revoke create on schema privado from propietario_rpc;
select pg_catalog.setval('pg_temp.control_mutante'::pg_catalog.regclass, 1,
  (select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex')
     from pg_catalog.pg_proc p
    where p.oid operator(pg_catalog.=) 'privado.abrir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid)'::pg_catalog.regprocedure)
  operator(pg_catalog.=) 'f6f88764d337df49f2d05fdb8deaafd6a5be9e13500c38caf8be31b143faea07');
set local role authenticated;
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"b1b1b1b1-0000-4000-8000-000000000001","role":"authenticated"}', true) is not null;
select pg_temp.intentar('m1', $$public.abrir_jornada('b1b1b1b1-5555-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-0000000000c4', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000006')$$);
reset role;
-- resultados es transaccional: el éxito del mutante se guarda en una secuencia.
select pg_catalog.setval('pg_temp.control_ok'::pg_catalog.regclass, 1,
  exists (select 1 from pg_temp.resultados r
           where r.caso operator(pg_catalog.=) 'm1' and r.valor operator(pg_catalog.~~) 'ok:%'));
select pg_catalog.setval('pg_temp.control_directo'::pg_catalog.regclass,
  (select case when s.is_called then s.last_value else 1 end from pg_temp.sonda_privilegiada s),
  (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s) operator(pg_catalog.>) 0);
rollback to savepoint control_m1;

select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
set local role authenticated;
select pg_temp.intentar('post_m1', $$public.abrir_jornada('b1b1b1b1-5555-4000-8000-000000000002', 'b1b1b1b1-0000-4000-8000-0000000000c5', '2999-03-01', 'b1b1b1b1-0000-4000-8000-000000000006')$$);
reset role;
insert into pg_temp.resultados
select 'medida_post_m1',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text;

-- Se eliminan los objetos hostiles (dominios primero) antes de usar pgTAP.
set local role authenticated;
drop domain pg_temp.uuid, pg_temp.text, pg_temp.date, pg_temp.jsonb;
drop operator pg_temp.= (pg_catalog.text, pg_catalog.text);
drop function pg_temp.igual_hostil(pg_catalog.text, pg_catalog.text), pg_temp.encode(pg_catalog.bytea, pg_catalog.text),
  pg_temp.to_char(pg_catalog.date, pg_catalog.text);
drop view pg_temp.jornadas, pg_temp.operaciones, pg_temp.reasignaciones_vendedor, pg_temp.camiones,
  pg_temp.perfiles, pg_temp.perfiles_empresa_gestion, pg_temp.movimientos_stock, pg_temp.productos, pg_temp.ubicaciones;
drop function pg_temp.sonda();
reset role;

-- ===========================================================================
-- Afirmaciones (sin objetos hostiles)
-- ===========================================================================
select is((select valor from resultados where caso = 'hostiles'), '4/9/1',
  'P1: 4 dominios, 9 vistas homónimas y 1 operador hostiles creados antes de la primera llamada');

select is(
  (select string_agg(caso || '=' || split_part(valor, ':', 1), ',' order by caso) from resultados
    where caso in ('abrir', 'replay_abrir', 'reasignar', 'replay_reasignar', 'encargado_abrir', 'cargar', 'replay_cargar',
                   'descargar', 'replay_descargar', 'salir', 'replay_salir')),
  'abrir=ok,cargar=ok,descargar=ok,encargado_abrir=ok,reasignar=ok,replay_abrir=ok,replay_cargar=ok,replay_descargar=ok,replay_reasignar=ok,replay_salir=ok,salir=ok',
  'P2: las 5 RPC (y la apertura del encargado) completan con los objetos hostiles presentes');

select is(
  (select valor from resultados where caso = 'replay_abrir') || '/' || (select valor from resultados where caso = 'replay_reasignar')
  || '/' || (select valor from resultados where caso = 'replay_cargar')
  || '/' || (select valor from resultados where caso = 'replay_descargar')
  || '/' || (select valor from resultados where caso = 'replay_salir'),
  (select valor from resultados where caso = 'abrir') || '/' || (select valor from resultados where caso = 'reasignar')
  || '/' || (select valor from resultados where caso = 'cargar')
  || '/' || (select valor from resultados where caso = 'descargar')
  || '/' || (select valor from resultados where caso = 'salir'),
  'P2: los replays con la misma clave y huella devuelven la misma jornada y las mismas operaciones');

select is(
  (select o.huella from public.operaciones o where o.id = (select substr(valor, 4)::uuid from resultados where caso = 'cargar'))
  || '/' || (select string_agg(m.cantidad::text || ':' || right(m.ubicacion_origen_id::text, 2) || '>' || right(m.ubicacion_destino_id::text, 2), ',')
               from public.movimientos_stock m where m.operacion_id = (select substr(valor, 4)::uuid from resultados where caso = 'cargar')),
  encode(sha256(convert_to('v1|carga|' || (select substr(valor, 4) from resultados where caso = 'abrir')
                           || '|b1b1b1b1-0000-4000-8000-0000000000f1:5', 'UTF8')), 'hex') || '/5:d1>e1',
  'T5: registrar_carga con los objetos hostiles presentes: huella v1 canónica y un movimiento depósito → camión');

select is(
  (select string_agg(o.tipo || '=' || (o.huella = encode(sha256(convert_to(
             case o.tipo
               when 'apertura_jornada' then 'v1|apertura_jornada|b1b1b1b1-0000-4000-8000-0000000000c1|2999-03-01|b1b1b1b1-0000-4000-8000-000000000003'
               when 'reasignacion_vendedor' then 'v1|reasignacion_vendedor|' || (select substr(valor, 4) from resultados where caso = 'abrir')
                                                 || '|b1b1b1b1-0000-4000-8000-000000000004'
             end, 'UTF8')), 'hex'))::text, ',' order by o.tipo)
     from public.operaciones o
    where o.empresa_id = 'b1b1b1b1-0000-4000-8000-000000000000'
      and o.idempotency_key in ('b1b1b1b1-2222-4000-8000-000000000001', 'b1b1b1b1-2222-4000-8000-000000000006')),
  'apertura_jornada=true,reasignacion_vendedor=true',
  'P2: las huellas v1 coinciden con el literal canónico (los casts calificados no cambian la huella)');

select is(
  (select string_agg(right(j.camion_id::text, 2) || ':' || j.fecha::text || ':' || right(j.vendedor_id::text, 2) || ':' || j.estado,
                     ',' order by j.camion_id)
     from public.jornadas j where j.empresa_id = 'b1b1b1b1-0000-4000-8000-000000000000')
  || ';' || (select string_agg(right(r.vendedor_anterior_id::text, 2) || '>' || right(r.vendedor_nuevo_id::text, 2), ',')
               from public.reasignaciones_vendedor r where r.empresa_id = 'b1b1b1b1-0000-4000-8000-000000000000')
  || ';' || (select string_agg(o.tipo, ',' order by o.tipo) from public.operaciones o
              where o.empresa_id = 'b1b1b1b1-0000-4000-8000-000000000000'),
  'c1:2999-03-01:04:en_reparto,c2:2999-03-01:05:abierta,c5:2999-03-01:06:abierta;03>04;apertura_jornada,apertura_jornada,apertura_jornada,carga,descarga,ingreso,reasignacion_vendedor,salida_jornada',
  'P2/P5: equivalencia de comportamiento — 3 jornadas (c1 cargada por T5; la del control revertida no queda), 1 reasignación y sólo las 7 operaciones del contrato (con la carga de T5, la descarga de T6 y la salida de T7), más el ingreso de fixture');

select is(
  (select string_agg(caso || '=' || valor, ' ; ' order by caso) from resultados
    where caso in ('rol_abrir', 'rol_reasignar', 'sin_identidad', 'conflicto_abrir', 'duplicada',
                   'vendedor_ocupado', 'camion_inactivo', 'fecha_pasada', 'sin_cambios')),
  'camion_inactivo=error:PT409:jornada_camion_inactivo ; conflicto_abrir=error:PT409:jornada_conflicto_idempotencia ; duplicada=error:PT409:jornada_duplicada ; fecha_pasada=error:PT400:jornada_fecha_invalida ; rol_abrir=error:PT403:jornada_no_autorizado ; rol_reasignar=error:PT403:jornada_no_autorizado ; sin_cambios=error:PT409:jornada_sin_cambios ; sin_identidad=error:PT401:jornada_no_autenticado ; vendedor_ocupado=error:PT409:jornada_vendedor_ocupado',
  'P4: rechazos por rol, identidad, idempotencia, duplicado, vendedor ocupado, camión inactivo, fecha y sin cambios, con códigos estables');

select is(
  (select string_agg(caso || '=' || valor, ' ; ' order by caso) from resultados where caso like 'b\_%'),
  'b_camion=error:PT404:jornada_camion_no_encontrado ; b_jornada=error:PT404:jornada_no_encontrada ; b_vendedor=error:PT404:jornada_vendedor_no_encontrado',
  'P4: con camión, vendedor o jornada de otra empresa, las 2 RPC responden no encontrado');

select is(
  (select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.jornadas t
            where t.empresa_id = 'c1c1c1c1-0000-4000-8000-000000000000')
          || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.operaciones t
                      where t.empresa_id = 'c1c1c1c1-0000-4000-8000-000000000000')
          || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.camiones t
                      where t.empresa_id = 'c1c1c1c1-0000-4000-8000-000000000000')
          || '/' || (select count(*)::text from public.reasignaciones_vendedor t
                      where t.empresa_id = 'c1c1c1c1-0000-4000-8000-000000000000')),
  (select huella from huella_b),
  'P4: jornadas, operaciones, camiones y reasignaciones de la empresa B sin cambios');

select is((select valor from resultados where caso = 'medida_p2'), '0/0',
  'P1/P2/P4: 0 ejecuciones del código temporal como propietario_rpc y como authenticated en las 23 llamadas');

select is(
  (select last_value - 1 from pg_temp.control_ro) || '/' || (select last_value - 1 from pg_temp.control_ro_priv),
  '7/0',
  'E-SL1: en sólo lectura, las 7 llamadas (clave nueva, replay, otra huella y replays de reasignación, carga, descarga y salida) responden 25006 jornada_metodo_no_permitido, con 0 ejecuciones como propietario_rpc');

select is(
  (select prosrc from pg_proc where oid = 'privado.abrir_jornada(uuid,uuid,date,uuid)'::regprocedure) ~ E'\nbegin\n  -- Paso 0 \\(corrección T14'
  and (select prosrc from pg_proc where oid = 'privado.reasignar_vendedor(uuid,uuid,uuid)'::regprocedure) ~ E'\nbegin\n  -- Paso 0 \\(corrección T14',
  true,
  'E-SL1: la guarda sigue siendo la primera sentencia de las 2 implementaciones');

select is(
  (select count(*)::int from public.operaciones o
    where o.idempotency_key = 'b1b1b1b1-6666-4000-8000-000000000001'),
  0,
  'E-SL1: el rechazo por sólo lectura no reserva la clave nueva');

select ok(pg_temp.ejecuciones_secuencia('pg_temp.control_mutante') = 1,
  'P6: el cuerpo reintroducido es exactamente el anterior a B1, con la guarda (SHA-256 f6f88764…)');

select cmp_ok(pg_temp.ejecuciones_secuencia('pg_temp.control_directo'), '>', 0::bigint,
  'P6: con referencias sin calificar, abrir_jornada ejecuta el código temporal como propietario_rpc (el detector funciona)');

select is(
  pg_temp.ejecuciones_secuencia('pg_temp.control_ok')::text
  || '/' || (select split_part(valor, ':', 1) from resultados where caso = 'post_m1')
  || '/' || (select valor from resultados where caso = 'medida_post_m1')
  || '/' || (select encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex') from pg_proc p
              where p.oid = 'privado.abrir_jornada(uuid,uuid,date,uuid)'::regprocedure)
  || '/' || has_schema_privilege('propietario_rpc', 'privado', 'CREATE')::text,
  '1/ok/0/7e2f2d07ffe75a90af6fba379c32d874ca3d229daa7c841f300aef5f467c5440/false',
  'P6: el mutante completa (se mide ejecución, no un error); tras revertirlo vuelve el cuerpo de B1, sin CREATE residual, y la llamada vuelve a 0 ejecuciones');

select * from finish();

rollback;
