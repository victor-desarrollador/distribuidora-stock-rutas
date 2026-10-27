-- pgTAP: modelo por peso, Slice A (ADR-005 §2.2; Blueprint §7.1, §7.4, §12).
-- Ejecutar sólo en local.
--
-- Las RPC de stock reciben siempre el entero canónico: unidades para un
-- producto `unidad` y gramos para un producto `peso`. No hay kg ni decimales
-- en el ledger. B es un fixture adversarial de aislamiento.

begin;

create extension if not exists pgtap with schema extensions;

select plan(33);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-0000-4000-8000-000000000000', 'Empresa A (test)'),
  ('bbbbbbbb-0000-4000-8000-000000000000', 'Empresa B (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pg.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'pg.a2@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'pg.a3@usuarios.distribuidora.invalid',
   '{"rol":"dueno"}'),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pg.b1@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000000', 'pg.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000000', 'pg.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000000', 'pg.a3', 'A3', 'vendedor_piloto', true),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000000', 'pg.b1', 'B1', 'dueno', true);

insert into public.ubicaciones (id, empresa_id, tipo) values
  ('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000000', 'deposito'),
  ('aaaaaaaa-0000-4000-8000-0000000000d2', 'aaaaaaaa-0000-4000-8000-000000000000', 'cuarentena'),
  ('bbbbbbbb-0000-4000-8000-0000000000d1', 'bbbbbbbb-0000-4000-8000-000000000000', 'deposito'),
  ('bbbbbbbb-0000-4000-8000-0000000000d2', 'bbbbbbbb-0000-4000-8000-000000000000', 'cuarentena');

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, stock_minimo, activo, creado_por) values
  ('aaaaaaaa-0000-4000-8000-0000000000f1', 'aaaaaaaa-0000-4000-8000-000000000000', 'PG-U', 'Leche A', 'lacteos', 'unidad',
   1600.00, 5, true, 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-0000000000f2', 'aaaaaaaa-0000-4000-8000-000000000000', 'PG-P', 'Jamón A', 'fiambres', 'peso',
   12345.67, 2500, true, 'aaaaaaaa-0000-4000-8000-000000000001');

create function pg_temp.como_usuario(uid uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

-- Saldo calculado de forma independiente, como owner (ve todo el ledger).
create function pg_temp.saldo(ub uuid, prod uuid)
returns bigint language sql as $$
  select coalesce(sum(case when ubicacion_destino_id = ub then cantidad::bigint else 0 end), 0)
       - coalesce(sum(case when ubicacion_origen_id = ub then cantidad::bigint else 0 end), 0)
    from public.movimientos_stock where producto_id = prod
$$;

grant execute on function pg_temp.como_usuario(uuid) to public;
grant execute on function pg_temp.saldo(uuid, uuid) to public;

create temp table ops (clave text, id uuid);
grant select, insert on ops to public;

-- ---------------------------------------------------------------------------
-- Catálogo: el ledger sigue en enteros y las firmas no cambian
-- ---------------------------------------------------------------------------
select is(
  (select format_type(atttypid, atttypmod) || ':' || attnotnull::text from pg_attribute
    where attrelid = 'public.movimientos_stock'::regclass and attname = 'cantidad' and not attisdropped),
  'integer:true',
  'movimientos_stock.cantidad sigue siendo integer NOT NULL');

select is(
  (select count(*)::int from pg_attribute
    where attrelid in ('public.movimientos_stock'::regclass, 'public.operaciones'::regclass)
      and attnum > 0 and not attisdropped
      and (format_type(atttypid, atttypmod) like 'numeric%'
           or atttypid in ('real'::regtype, 'double precision'::regtype)
           or attname ~ '(kg|gramo|unidad)')),
  0,
  'el ledger no tiene columnas numeric, float, kg, gramos ni de unidad');

select is(
  (select format_type(atttypid, atttypmod) from pg_attribute
    where attrelid = 'public.stock_actual'::regclass and attname = 'cantidad'),
  'bigint',
  'stock_actual.cantidad sigue siendo bigint (suma de enteros)');

select ok(
  col_description('public.movimientos_stock'::regclass,
    (select attnum from pg_attribute where attrelid = 'public.movimientos_stock'::regclass
        and attname = 'cantidad')) like '%unidades (unidad) o gramos (peso)%',
  'el comentario de movimientos_stock.cantidad documenta unidades o gramos');

select is(
  array(select p.oid::regprocedure::text from pg_proc p
         where p.proname in ('registrar_ingreso', 'mover_a_cuarentena', 'registrar_merma')
           and p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
         order by 1),
  array['mover_a_cuarentena(uuid,uuid,uuid,integer,text)',
        'privado.mover_a_cuarentena(uuid,uuid,uuid,integer,text)',
        'privado.registrar_ingreso(uuid,uuid,integer,text)',
        'privado.registrar_merma(uuid,uuid,uuid,integer,text,text)',
        'registrar_ingreso(uuid,uuid,integer,text)',
        'registrar_merma(uuid,uuid,uuid,integer,text,text)'],
  'las RPC de stock conservan sus firmas con p_cantidad integer, sin sobrecargas');

-- ---------------------------------------------------------------------------
-- Producto unidad: p_cantidad = unidades
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into ops select 'u_ingreso', public.registrar_ingreso(
      '20000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 7, 'Compra')$$,
  'unidad: ingreso de 7');
reset role;

select is(pg_temp.saldo('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000f1'),
  7::bigint, 'unidad: p_cantidad = 7 son 7 unidades en el depósito');

-- ---------------------------------------------------------------------------
-- Producto peso: p_cantidad = gramos (1250 = 1,250 kg)
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into ops select 'p_ingreso', public.registrar_ingreso(
      '20000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-0000000000f2', 1250, 'Compra')$$,
  'peso: ingreso de 1250 g (1,250 kg)');
reset role;

select results_eq(
  $$select m.tipo_movimiento, m.cantidad, m.ubicacion_origen_id, m.ubicacion_destino_id
      from public.movimientos_stock m join ops o on o.id = m.operacion_id
     where o.clave = 'p_ingreso'$$,
  $$values ('ingreso'::text, 1250, null::uuid, 'aaaaaaaa-0000-4000-8000-0000000000d1'::uuid)$$,
  'peso: el movimiento guarda el entero 1250 tal como llegó (sin conversión)');
select is(pg_temp.saldo('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000f2'),
  1250::bigint, 'peso: saldo del depósito 1250 g');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$insert into ops select 'p_cuar', public.mover_a_cuarentena(
      '20000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 250, 'Envase dañado')$$,
  'peso: el encargado mueve 250 g a cuarentena');
reset role;

select is(pg_temp.saldo('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000f2'),
  1000::bigint, 'peso: saldo del depósito 1000 g tras la cuarentena');
select is(pg_temp.saldo('aaaaaaaa-0000-4000-8000-0000000000d2', 'aaaaaaaa-0000-4000-8000-0000000000f2'),
  250::bigint, 'peso: saldo de cuarentena 250 g');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select results_eq(
  $$select ubicacion_id, cantidad from public.stock_actual
     where producto_id = 'aaaaaaaa-0000-4000-8000-0000000000f2' order by cantidad desc$$,
  $$values ('aaaaaaaa-0000-4000-8000-0000000000d1'::uuid, 1000::bigint),
           ('aaaaaaaa-0000-4000-8000-0000000000d2'::uuid, 250::bigint)$$,
  'peso: stock_actual muestra 1000 g en depósito y 250 g en cuarentena');

select lives_ok(
  $$insert into ops select 'p_merma', public.registrar_merma(
      '20000000-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 300, 'vencido')$$,
  'peso: merma de 300 g desde el depósito');
reset role;

select is(pg_temp.saldo('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000f2'),
  700::bigint, 'peso: 1000 g - 300 g de merma = 700 g');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.registrar_merma('20000000-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 701, 'vencido')$$,
  'PT409', 'stock_insuficiente', 'peso: una merma 1 g mayor que el saldo se rechaza');
select throws_ok(
  $$select public.mover_a_cuarentena('20000000-0000-4000-8000-000000000006', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 701, 'Exceso')$$,
  'PT409', 'stock_insuficiente', 'peso: una cuarentena 1 g mayor que el saldo se rechaza');
select lives_ok(
  $$insert into ops select 'p_merma_total', public.registrar_merma(
      '20000000-0000-4000-8000-000000000007', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 700, 'roto_danado')$$,
  'peso: merma exacta del saldo (700 g)');
reset role;

select is(pg_temp.saldo('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000f2'),
  0::bigint, 'peso: el depósito queda en 0 g exactos');

-- Idempotencia: misma clave y mismos gramos repite; otros gramos es conflicto.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select is(
  public.registrar_ingreso('20000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-0000000000f2', 1250, 'Compra'),
  (select id from ops where clave = 'p_ingreso'),
  'peso: reintento idéntico devuelve la misma operación');
select throws_ok(
  $$select public.registrar_ingreso('20000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-0000000000f2', 1251, 'Compra')$$,
  'PT409', 'stock_conflicto_idempotencia', 'peso: la misma clave con 1 g distinto es conflicto');

-- La base no acepta kg ni fracciones: recibe el entero canónico.
select throws_ok(
  $$select public.registrar_ingreso('20000000-0000-4000-8000-000000000008', 'aaaaaaaa-0000-4000-8000-0000000000f2', '1.25')$$,
  '22P02', null, 'peso: 1.25 (kg) no es una cantidad válida; la conversión kg → g es de la UI');
select throws_ok(
  $$select public.registrar_ingreso('20000000-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-0000000000f2', '1250.5')$$,
  '22P02', null, 'peso: una fracción de gramo se rechaza');
select throws_ok(
  $$select public.registrar_ingreso('20000000-0000-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-0000000000f2', 0)$$,
  'PT400', 'stock_cantidad_invalida', 'peso: 0 g se rechaza');
select throws_ok(
  $$select public.registrar_ingreso('20000000-0000-4000-8000-00000000000b', 'aaaaaaaa-0000-4000-8000-0000000000f2', -1250)$$,
  'PT400', 'stock_cantidad_invalida', 'peso: gramos negativos se rechazan');
reset role;

-- ---------------------------------------------------------------------------
-- Autorización y aislamiento con productos peso
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select throws_ok(
  $$select public.registrar_ingreso('20000000-0000-4000-8000-00000000000c', 'aaaaaaaa-0000-4000-8000-0000000000f2', 1250)$$,
  'PT403', 'stock_no_autorizado', 'peso: el vendedor no registra ingresos (metadata ignorada)');
select throws_ok(
  $$select public.registrar_merma('20000000-0000-4000-8000-00000000000d', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d2', 1, 'vencido')$$,
  'PT403', 'stock_no_autorizado', 'peso: el vendedor no registra mermas');

select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.registrar_ingreso('20000000-0000-4000-8000-00000000000e', 'aaaaaaaa-0000-4000-8000-0000000000f2', 1250)$$,
  'PT404', 'stock_producto_no_encontrado', 'peso: el dueño de B no ingresa un producto de A');
select is(
  (select count(*)::int from public.stock_actual
    where producto_id = 'aaaaaaaa-0000-4000-8000-0000000000f2'),
  0, 'peso: el dueño de B no ve el stock de un producto de A');
select is(
  (select count(*)::int from public.movimientos_stock
    where producto_id = 'aaaaaaaa-0000-4000-8000-0000000000f2'),
  0, 'peso: el dueño de B no ve los movimientos de un producto de A');
reset role;

select results_eq(
  $$select tipo_movimiento, cantidad from public.movimientos_stock
     where producto_id = 'aaaaaaaa-0000-4000-8000-0000000000f2' order by cantidad$$,
  $$values ('a_cuarentena'::text, 250), ('merma'::text, 300), ('merma'::text, 700), ('ingreso'::text, 1250)$$,
  'peso: el ledger tiene sólo los cuatro movimientos válidos, en gramos enteros');

select is(
  (select count(*)::int from public.stock_actual where cantidad < 0),
  0, 'ningún saldo de stock_actual es negativo');

select * from finish();

rollback;
