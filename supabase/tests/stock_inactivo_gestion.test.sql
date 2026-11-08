-- pgTAP: B-01, observación no bloqueante de Codex sobre 2a0aa43.
-- Aísla `perfiles.activo = false` del rol en las tres RPC de stock
-- (registrar_ingreso, mover_a_cuarentena, registrar_merma): el MISMO perfil,
-- con el MISMO rol de gestión (dueño o encargado), es aceptado activo,
-- rechazado inactivo (PT403 stock_no_autorizado, sin efectos ni lecturas) y
-- aceptado de nuevo al reactivarlo. Blueprint §9 y §10; ADR-001 §18.3.
--
-- Sólo prueba; no cambia RPC, migraciones, RLS, permisos ni el seed. Los
-- datos se crean y se revierten en esta transacción.
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(40);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('eeeeeeee-0000-4000-8000-000000000000', 'Empresa E (test inactivo)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('eeeeeeee-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ina.d1@usuarios.distribuidora.invalid', '{}'),
  ('eeeeeeee-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'ina.e1@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('eeeeeeee-0000-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000000', 'ina.d1', 'Dueño E', 'dueno', true),
  ('eeeeeeee-0000-4000-8000-000000000002', 'eeeeeeee-0000-4000-8000-000000000000', 'ina.e1', 'Encargado E', 'encargado', true);

insert into public.ubicaciones (id, empresa_id, tipo) values
  ('eeeeeeee-0000-4000-8000-0000000000d1', 'eeeeeeee-0000-4000-8000-000000000000', 'deposito'),
  ('eeeeeeee-0000-4000-8000-0000000000d2', 'eeeeeeee-0000-4000-8000-000000000000', 'cuarentena');

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-000000000000', 'E-1', 'Leche E', 'lacteos', 'unidad', 100, true,
   'eeeeeeee-0000-4000-8000-000000000001');

create function pg_temp.como_usuario(uid uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated', 'user_metadata', '{}'::jsonb)::text, true);
  execute 'set local role authenticated';
end $$;
-- Ayudante temporal de esta transacción (igual que stock_ingreso.test.sql):
-- se invoca también ya como `authenticated`.
grant execute on function pg_temp.como_usuario(uuid) to public;

-- Conteos de la empresa E, leídos como owner (sin RLS de por medio).
create function pg_temp.ops_e() returns integer language sql as $$
  select count(*)::int from public.operaciones where empresa_id = 'eeeeeeee-0000-4000-8000-000000000000'
$$;
create function pg_temp.movs_e() returns integer language sql as $$
  select count(*)::int from public.movimientos_stock where empresa_id = 'eeeeeeee-0000-4000-8000-000000000000'
$$;

create temp table conteos (ops integer, movs integer);
insert into conteos values (0, 0);

-- ---------------------------------------------------------------------------
-- 1. Control positivo: dueño y encargado ACTIVOS operan las tres RPC
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('eeeeeeee-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.registrar_ingreso('e1000000-0000-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-0000000000f1', 50)$$,
  'dueño activo: registrar_ingreso aceptado');
select lives_ok(
  $$select public.mover_a_cuarentena('e1000000-0000-4000-8000-000000000002', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'control')$$,
  'dueño activo: mover_a_cuarentena aceptado');
select lives_ok(
  $$select public.registrar_merma('e1000000-0000-4000-8000-000000000003', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'vencido')$$,
  'dueño activo: registrar_merma aceptado');

select pg_temp.como_usuario('eeeeeeee-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.registrar_ingreso('e2000000-0000-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-0000000000f1', 50)$$,
  'encargado activo: registrar_ingreso aceptado');
select lives_ok(
  $$select public.mover_a_cuarentena('e2000000-0000-4000-8000-000000000002', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'control')$$,
  'encargado activo: mover_a_cuarentena aceptado');
select lives_ok(
  $$select public.registrar_merma('e2000000-0000-4000-8000-000000000003', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'roto_danado')$$,
  'encargado activo: registrar_merma aceptado');
select ok((select count(*) from public.stock_actual) > 0, 'encargado activo: lee stock de su empresa');
reset role;

select is(pg_temp.ops_e(), 6, 'seis operaciones de los perfiles activos');
select is(pg_temp.movs_e(), 6, 'seis movimientos de los perfiles activos');

-- ---------------------------------------------------------------------------
-- 2. Dueño INACTIVO (mismo perfil, mismo rol): PT403, sin efectos ni lecturas
-- ---------------------------------------------------------------------------
update public.perfiles set activo = false where usuario_id = 'eeeeeeee-0000-4000-8000-000000000001';
select is((select rol from public.perfiles where usuario_id = 'eeeeeeee-0000-4000-8000-000000000001'), 'dueno',
  'el dueño inactivo conserva el rol dueno: sólo cambió activo');
update conteos set ops = pg_temp.ops_e(), movs = pg_temp.movs_e();

select pg_temp.como_usuario('eeeeeeee-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.registrar_ingreso('e1000000-0000-4000-8000-000000000011', 'eeeeeeee-0000-4000-8000-0000000000f1', 5)$$,
  'PT403', 'stock_no_autorizado', 'dueño inactivo: registrar_ingreso PT403');
select throws_ok(
  $$select public.mover_a_cuarentena('e1000000-0000-4000-8000-000000000012', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'x')$$,
  'PT403', 'stock_no_autorizado', 'dueño inactivo: mover_a_cuarentena PT403');
select throws_ok(
  $$select public.registrar_merma('e1000000-0000-4000-8000-000000000013', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'vencido')$$,
  'PT403', 'stock_no_autorizado', 'dueño inactivo: registrar_merma PT403');
select throws_ok(
  $$select public.registrar_ingreso('e1000000-0000-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-0000000000f1', 50)$$,
  'PT403', 'stock_no_autorizado', 'dueño inactivo: el replay de su propia clave confirmada también es PT403');
select is((select count(*)::int from public.stock_actual), 0, 'dueño inactivo: no ve stock');
select is((select count(*)::int from public.operaciones), 0, 'dueño inactivo: no ve operaciones');
select is((select count(*)::int from public.movimientos_stock), 0, 'dueño inactivo: no ve movimientos');
reset role;
select is(pg_temp.ops_e(), (select ops from conteos), 'dueño inactivo: ninguna operación nueva');
select is(pg_temp.movs_e(), (select movs from conteos), 'dueño inactivo: ningún movimiento nuevo');

-- ---------------------------------------------------------------------------
-- 3. Encargado INACTIVO (mismo perfil, mismo rol): PT403, sin efectos ni lecturas
-- ---------------------------------------------------------------------------
update public.perfiles set activo = false where usuario_id = 'eeeeeeee-0000-4000-8000-000000000002';
select is((select rol from public.perfiles where usuario_id = 'eeeeeeee-0000-4000-8000-000000000002'), 'encargado',
  'el encargado inactivo conserva el rol encargado: sólo cambió activo');
update conteos set ops = pg_temp.ops_e(), movs = pg_temp.movs_e();

select pg_temp.como_usuario('eeeeeeee-0000-4000-8000-000000000002');
select throws_ok(
  $$select public.registrar_ingreso('e2000000-0000-4000-8000-000000000011', 'eeeeeeee-0000-4000-8000-0000000000f1', 5)$$,
  'PT403', 'stock_no_autorizado', 'encargado inactivo: registrar_ingreso PT403');
select throws_ok(
  $$select public.mover_a_cuarentena('e2000000-0000-4000-8000-000000000012', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'x')$$,
  'PT403', 'stock_no_autorizado', 'encargado inactivo: mover_a_cuarentena PT403');
select throws_ok(
  $$select public.registrar_merma('e2000000-0000-4000-8000-000000000013', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'vencido')$$,
  'PT403', 'stock_no_autorizado', 'encargado inactivo: registrar_merma PT403');
select throws_ok(
  $$select public.registrar_merma('e2000000-0000-4000-8000-000000000003', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'roto_danado')$$,
  'PT403', 'stock_no_autorizado', 'encargado inactivo: el replay de su propia clave confirmada también es PT403');
select is((select count(*)::int from public.stock_actual), 0, 'encargado inactivo: no ve stock');
select is((select count(*)::int from public.operaciones), 0, 'encargado inactivo: no ve operaciones');
select is((select count(*)::int from public.movimientos_stock), 0, 'encargado inactivo: no ve movimientos');
reset role;
select is(pg_temp.ops_e(), (select ops from conteos), 'encargado inactivo: ninguna operación nueva');
select is(pg_temp.movs_e(), (select movs from conteos), 'encargado inactivo: ningún movimiento nuevo');

-- ---------------------------------------------------------------------------
-- 4. Reactivados (mismo perfil, mismo rol): vuelven a ser aceptados
-- ---------------------------------------------------------------------------
update public.perfiles set activo = true
 where usuario_id in ('eeeeeeee-0000-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000002');
update conteos set ops = pg_temp.ops_e(), movs = pg_temp.movs_e();

select pg_temp.como_usuario('eeeeeeee-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.registrar_ingreso('e1000000-0000-4000-8000-000000000021', 'eeeeeeee-0000-4000-8000-0000000000f1', 5)$$,
  'dueño reactivado: registrar_ingreso aceptado');
select lives_ok(
  $$select public.mover_a_cuarentena('e1000000-0000-4000-8000-000000000022', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'reactivado')$$,
  'dueño reactivado: mover_a_cuarentena aceptado');
select lives_ok(
  $$select public.registrar_merma('e1000000-0000-4000-8000-000000000023', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'vencido')$$,
  'dueño reactivado: registrar_merma aceptado');
select ok((select count(*) from public.stock_actual) > 0, 'dueño reactivado: vuelve a leer stock');

select pg_temp.como_usuario('eeeeeeee-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.registrar_ingreso('e2000000-0000-4000-8000-000000000021', 'eeeeeeee-0000-4000-8000-0000000000f1', 5)$$,
  'encargado reactivado: registrar_ingreso aceptado');
select lives_ok(
  $$select public.mover_a_cuarentena('e2000000-0000-4000-8000-000000000022', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'reactivado')$$,
  'encargado reactivado: mover_a_cuarentena aceptado');
select lives_ok(
  $$select public.registrar_merma('e2000000-0000-4000-8000-000000000023', 'eeeeeeee-0000-4000-8000-0000000000f1', 'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'vencido')$$,
  'encargado reactivado: registrar_merma aceptado');
select ok((select count(*) from public.operaciones) > 0, 'encargado reactivado: vuelve a ver operaciones');
reset role;

select is(pg_temp.ops_e(), (select ops from conteos) + 6, 'reactivados: seis operaciones nuevas');
select is(pg_temp.movs_e(), (select movs from conteos) + 6, 'reactivados: seis movimientos nuevos');
-- La única diferencia entre los rechazos y las aceptaciones fue `activo`.
select is((select array_agg(rol order by usuario_id) from public.perfiles
            where empresa_id = 'eeeeeeee-0000-4000-8000-000000000000'),
  array['dueno', 'encargado'], 'los roles nunca cambiaron durante la prueba');

select * from finish();

rollback;
