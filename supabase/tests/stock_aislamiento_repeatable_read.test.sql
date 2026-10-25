-- pgTAP: Etapa 2 — Stock, slice 2 «stock-cuarentena-merma». Las RPC que
-- debitan exigen READ COMMITTED (ADR-001 §18.3, P13-stock): bajo REPEATABLE
-- READ fallan cerradas con PT500 antes de cualquier trabajo. Ejecutar sólo en
-- local. El aislamiento se fija al abrir la transacción, antes de cualquier
-- consulta; por eso este caso vive en su propio archivo.

begin isolation level repeatable read;

create extension if not exists pgtap with schema extensions;

select plan(16);

select is(pg_catalog.current_setting('transaction_isolation'), 'repeatable read',
  'la transacción de la prueba es REPEATABLE READ');

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-0000-4000-8000-000000000000', 'Empresa A (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ai.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'ai.a3@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000000', 'ai.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000000', 'ai.a3', 'A3', 'vendedor_piloto', true);

insert into public.ubicaciones (id, empresa_id, tipo) values
  ('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000000', 'deposito'),
  ('aaaaaaaa-0000-4000-8000-0000000000d2', 'aaaaaaaa-0000-4000-8000-000000000000', 'cuarentena');

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('aaaaaaaa-0000-4000-8000-0000000000f1', 'aaaaaaaa-0000-4000-8000-000000000000', 'AI-A1', 'Leche A', 'lacteos', 'unidad', 100, true,
   'aaaaaaaa-0000-4000-8000-000000000001');

create function pg_temp.como_usuario(uid uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;
grant execute on function pg_temp.como_usuario(uuid) to public;

-- Stock inicial (10) y una cuarentena y una merma previas de 1 (como owner),
-- con sus huellas v1, para probar que ni el replay pasa el guard.
with o as (
  insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
  values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'ingreso',
          '70000000-0000-4000-8000-000000000001', repeat('1', 64))
  returning id)
insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                      ubicacion_destino_id, actor_id)
select 'aaaaaaaa-0000-4000-8000-000000000000', o.id, 'ingreso', 'aaaaaaaa-0000-4000-8000-0000000000f1', 10,
       'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001'
  from o;

with o as (
  insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
  values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'a_cuarentena',
          '70000000-0000-4000-8000-000000000002',
          encode(sha256(convert_to(
            'v1|a_cuarentena|aaaaaaaa-0000-4000-8000-0000000000f1|aaaaaaaa-0000-4000-8000-0000000000d1|1|+Previa',
            'UTF8')), 'hex'))
  returning id)
insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                      ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo)
select 'aaaaaaaa-0000-4000-8000-000000000000', o.id, 'a_cuarentena', 'aaaaaaaa-0000-4000-8000-0000000000f1', 1,
       'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000d2',
       'aaaaaaaa-0000-4000-8000-000000000001', 'Previa'
  from o;

with o as (
  insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
  values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'merma',
          '70000000-0000-4000-8000-000000000003',
          encode(sha256(convert_to(
            'v1|merma|aaaaaaaa-0000-4000-8000-0000000000f1|aaaaaaaa-0000-4000-8000-0000000000d1|1|vencido|-',
            'UTF8')), 'hex'))
  returning id)
insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                      ubicacion_origen_id, actor_id, motivo_codigo)
select 'aaaaaaaa-0000-4000-8000-000000000000', o.id, 'merma', 'aaaaaaaa-0000-4000-8000-0000000000f1', 1,
       'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001', 'vencido'
  from o;

create temp table huella_ledger as
  select (select md5(string_agg(o::text, '|' order by o.id)) from public.operaciones o) as ops,
         (select md5(string_agg(m::text, '|' order by m.id)) from public.movimientos_stock m) as movs;
grant select on huella_ledger to public;

-- ---------------------------------------------------------------------------
-- Pedidos válidos: PT500 sin efectos
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.mover_a_cuarentena('71000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'Revisión')$$,
  'PT500', 'stock_error_interno', 'mover_a_cuarentena válido bajo REPEATABLE READ: PT500');
select throws_ok(
  $$select public.registrar_merma('71000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'vencido')$$,
  'PT500', 'stock_error_interno', 'registrar_merma válido bajo REPEATABLE READ: PT500');
select throws_ok(
  $$select privado.mover_a_cuarentena('71000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'Revisión')$$,
  'PT500', 'stock_error_interno', 'la implementación privada de cuarentena también rechaza');
select throws_ok(
  $$select privado.registrar_merma('71000000-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'vencido')$$,
  'PT500', 'stock_error_interno', 'la implementación privada de merma también rechaza');

-- ---------------------------------------------------------------------------
-- Posición del guard: precede a identidad, rol, validaciones y replay
-- ---------------------------------------------------------------------------
select throws_ok(
  $$select public.mover_a_cuarentena(null, 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'Revisión')$$,
  'PT500', 'stock_error_interno', 'cuarentena con clave NULL: PT500 antes de PT400');
select throws_ok(
  $$select public.registrar_merma(null, 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'vencido')$$,
  'PT500', 'stock_error_interno', 'merma con clave NULL: PT500 antes de PT400');
select throws_ok(
  $$select public.mover_a_cuarentena('70000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'Previa')$$,
  'PT500', 'stock_error_interno', 'replay legítimo de cuarentena: PT500, no devuelve el id');
select throws_ok(
  $$select public.registrar_merma('70000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'vencido')$$,
  'PT500', 'stock_error_interno', 'replay legítimo de merma: PT500, no devuelve el id');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'Revisión')$$,
  'PT500', 'stock_error_interno', 'vendedor en cuarentena: PT500 antes de PT403');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'vencido')$$,
  'PT500', 'stock_error_interno', 'vendedor en merma: PT500 antes de PT403');

select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'Revisión')$$,
  'PT500', 'stock_error_interno', 'cuarentena sin sub en el JWT: PT500 antes de PT401');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'vencido')$$,
  'PT500', 'stock_error_interno', 'merma sin sub en el JWT: PT500 antes de PT401');
reset role;

-- ---------------------------------------------------------------------------
-- Sin efectos
-- ---------------------------------------------------------------------------
select results_eq(
  $$select (select md5(string_agg(o::text, '|' order by o.id)) from public.operaciones o),
           (select md5(string_agg(m::text, '|' order by m.id)) from public.movimientos_stock m)$$,
  $$select ops, movs from huella_ledger$$,
  'operaciones y ledger idénticos: ninguna operación ni movimiento nuevo');
select is(
  (select count(*)::int from public.operaciones
    where idempotency_key::text like '71000000-%'),
  0, 'ninguna de las claves rechazadas quedó reservada');
select results_eq(
  $$select ubicacion_id, cantidad from public.stock_actual
     where producto_id = 'aaaaaaaa-0000-4000-8000-0000000000f1' order by ubicacion_id$$,
  $$values ('aaaaaaaa-0000-4000-8000-0000000000d1'::uuid, 8::bigint),
           ('aaaaaaaa-0000-4000-8000-0000000000d2'::uuid, 1::bigint)$$,
  'stock sin cambios: depósito 8 y cuarentena 1');

select * from finish();

rollback;
