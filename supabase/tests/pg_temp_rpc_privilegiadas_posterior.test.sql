-- pgTAP: endurecimiento pg_temp de las funciones privilegiadas — A1, objetos
-- hostiles creados DESPUÉS de una primera llamada legítima en la sesión.
-- Plan de remediación pg_temp, alternativa A (§5, segundo bloque); ADR-001 §17.1.
--
-- La sesión primero llama legítimamente a usuario_actual(), a
-- empresa_gestion_actual(), a la vista privada y a la ruta RLS (sin objetos
-- hostiles); después authenticated crea los dominios pg_temp.uuid y
-- pg_temp.jsonb y se repiten las mismas llamadas. Esperado: 0 ejecuciones del
-- código temporal como propietario_rpc y los mismos resultados. Un control
-- (cuerpo anterior reintroducido en un savepoint) prueba que, en este mismo
-- orden, el detector sí ve la ejecución.
--
-- La sonda y el contexto de alcance son los de pg_temp_rpc_privilegiadas.test.sql.
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('a8a8a8a8-0000-4000-8000-000000000000', 'Empresa A (test pg_temp posterior)'),
  ('b8b8b8b8-0000-4000-8000-000000000000', 'Empresa B (test pg_temp posterior)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('a8a8a8a8-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pgtp.a1@usuarios.distribuidora.invalid', '{}'),
  ('b8b8b8b8-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pgtp.b1@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('a8a8a8a8-0000-4000-8000-000000000001', 'a8a8a8a8-0000-4000-8000-000000000000', 'pgtp.a1', 'Dueño A', 'dueno', true),
  ('b8b8b8b8-0000-4000-8000-000000000001', 'b8b8b8b8-0000-4000-8000-000000000000', 'pgtp.b1', 'Dueño B', 'dueno', true);

insert into public.productos (empresa_id, codigo, nombre, categoria, forma_venta, precio, creado_por) values
  ('a8a8a8a8-0000-4000-8000-000000000000', 'PGTP-A1', 'Leche A', 'lacteos', 'unidad', 100, 'a8a8a8a8-0000-4000-8000-000000000001'),
  ('b8b8b8b8-0000-4000-8000-000000000000', 'PGTP-B1', 'Leche B', 'lacteos', 'unidad', 300, 'b8b8b8b8-0000-4000-8000-000000000001');

create temp table resultados (fase text, valor text);
grant all on resultados to public;

-- ---------------------------------------------------------------------------
-- Primera llamada legítima (sin objetos hostiles)
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims',
  '{"sub":"a8a8a8a8-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;
insert into pg_temp.resultados
  select 'legitima',
         privado.usuario_actual()::pg_catalog.text
         || '|' || privado.empresa_gestion_actual()::pg_catalog.text
         || '|' || (select pg_catalog.count(*) from privado.perfiles_empresa_gestion)::pg_catalog.text
         || '|' || (select pg_catalog.string_agg(p.codigo, ',' order by p.codigo) from public.productos p
                     where p.codigo operator(pg_catalog.~~) 'PGTP-%');
reset role;

select is((select valor from resultados where fase = 'legitima'),
  'a8a8a8a8-0000-4000-8000-000000000001|a8a8a8a8-0000-4000-8000-000000000000|1|PGTP-A1',
  'Posterior: la llamada legítima previa devuelve usuario, empresa, vista y RLS de A');

-- ---------------------------------------------------------------------------
-- Objetos hostiles de authenticated, creados después de la llamada legítima
-- ---------------------------------------------------------------------------
set local role authenticated;
create temp sequence sonda_privilegiada;
create temp sequence sonda_llamador;
create temp sequence control_directo;
create temp sequence control_rls;
grant all on sequence sonda_privilegiada, sonda_llamador, control_directo, control_rls to public;
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
      and t.typowner = 'authenticated'::regrole) = 2,
  'Posterior: dominios hostiles pg_temp.uuid y pg_temp.jsonb creados después de la llamada legítima');

-- ---------------------------------------------------------------------------
-- Mismas llamadas, ahora con los objetos hostiles
-- ---------------------------------------------------------------------------
select pg_temp.reiniciar_sondas();
set local role propietario_rpc;
insert into pg_temp.resultados
  select 'hostil',
         privado.usuario_actual()::pg_catalog.text
         || '|' || privado.empresa_gestion_actual()::pg_catalog.text
         || '|' || (select pg_catalog.count(*) from privado.perfiles_empresa_gestion)::pg_catalog.text
         || '|' || (select pg_catalog.string_agg(p.codigo, ',' order by p.codigo) from public.productos p
                     where p.codigo operator(pg_catalog.~~) 'PGTP-%');
reset role;

select is((select valor from resultados where fase = 'hostil'),
  (select valor from resultados where fase = 'legitima'),
  'Posterior: con los objetos hostiles, los resultados son idénticos a los de la llamada legítima');
select is(pg_temp.ejecuciones('pg_temp.sonda_privilegiada'), 0::bigint,
  'Posterior: 0 ejecuciones del código temporal como propietario_rpc');
select is(pg_temp.ejecuciones('pg_temp.sonda_llamador'), 0::bigint,
  'Posterior: 0 ejecuciones del código temporal como authenticated');

-- Claims de B en la misma sesión (aislamiento con objetos hostiles).
select pg_temp.reiniciar_sondas();
select set_config('request.jwt.claims',
  '{"sub":"b8b8b8b8-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;
insert into pg_temp.resultados
  select 'hostil_b',
         privado.empresa_gestion_actual()::pg_catalog.text
         || '|' || (select pg_catalog.string_agg(p.codigo, ',' order by p.codigo) from public.productos p
                     where p.codigo operator(pg_catalog.~~) 'PGTP-%');
reset role;

select is((select valor from resultados where fase = 'hostil_b'),
  'b8b8b8b8-0000-4000-8000-000000000000|PGTP-B1',
  'Posterior: con claims de B se ve sólo la empresa y los productos de B');
select is(pg_temp.ejecuciones('pg_temp.sonda_privilegiada'), 0::bigint,
  'Posterior: con claims de B, 0 ejecuciones del código temporal como propietario_rpc');

-- ---------------------------------------------------------------------------
-- Control del detector en este orden: cuerpo anterior reintroducido
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"a8a8a8a8-0000-4000-8000-000000000001","role":"authenticated"}', true);
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
rollback to savepoint control_m1;

select cmp_ok(pg_temp.ejecuciones('pg_temp.control_directo'), '>', 0::bigint,
  'Posterior (control): con el cuerpo anterior, la llamada directa ejecuta el código temporal como propietario_rpc');
select cmp_ok(pg_temp.ejecuciones('pg_temp.control_rls'), '>', 0::bigint,
  'Posterior (control): con el cuerpo anterior, la ruta RLS ejecuta el código temporal como propietario_rpc');

-- Tras revertir el control, la ruta calificada vuelve a 0.
select pg_temp.reiniciar_sondas();
set local role propietario_rpc;
select privado.usuario_actual() is not null;
select count(*) from public.productos;
reset role;
select is(pg_temp.ejecuciones('pg_temp.sonda_privilegiada'), 0::bigint,
  'Posterior: tras revertir el control, 0 ejecuciones del código temporal como propietario_rpc');

select * from finish();

rollback;
