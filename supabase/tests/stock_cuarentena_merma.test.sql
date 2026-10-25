-- pgTAP: Etapa 2 — Stock, slice 2 «stock-cuarentena-merma» (Blueprint §7.2,
-- §7.4, §7.7, §7.9, §9, §10, §12; ADR-001 Topología D, P11, O-3 y §18.3,
-- decisiones D1–D9 acotadas al dominio Stock). Ejecutar sólo en local.
--
-- B y C son fixtures adversariales (aislamiento y empresa sin cuarentena).
-- La concurrencia se prueba con dos conexiones reales en un arnés aparte.

begin;

create extension if not exists pgtap with schema extensions;

select plan(150);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-0000-4000-8000-000000000000', 'Empresa A (test)'),
  ('bbbbbbbb-0000-4000-8000-000000000000', 'Empresa B (test)'),
  ('cccccccc-0000-4000-8000-000000000000', 'Empresa C sin cuarentena (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'cm.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'cm.a2@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'cm.a3@usuarios.distribuidora.invalid',
   '{"rol":"dueno","empresa_id":"bbbbbbbb-0000-4000-8000-000000000000"}'),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'cm.a4@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'cm.b1@usuarios.distribuidora.invalid', '{}'),
  ('cccccccc-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'cm.c1@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'cm.n1@usuarios.distribuidora.invalid',
   '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000000', 'cm.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000000', 'cm.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000000', 'cm.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000000', 'cm.a4', 'A4', 'dueno', false),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000000', 'cm.b1', 'B1', 'dueno', true),
  ('cccccccc-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000000', 'cm.c1', 'C1', 'dueno', true);

insert into public.camiones (id, empresa_id, patente, nombre, creado_por) values
  ('aaaaaaaa-0000-4000-8000-0000000000c1', 'aaaaaaaa-0000-4000-8000-000000000000', 'CM-01', 'Camión A',
   'aaaaaaaa-0000-4000-8000-000000000001');

insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000000', 'deposito', null),
  ('aaaaaaaa-0000-4000-8000-0000000000d2', 'aaaaaaaa-0000-4000-8000-000000000000', 'cuarentena', null),
  ('aaaaaaaa-0000-4000-8000-0000000000d3', 'aaaaaaaa-0000-4000-8000-000000000000', 'camion',
   'aaaaaaaa-0000-4000-8000-0000000000c1'),
  ('bbbbbbbb-0000-4000-8000-0000000000d1', 'bbbbbbbb-0000-4000-8000-000000000000', 'deposito', null),
  ('bbbbbbbb-0000-4000-8000-0000000000d2', 'bbbbbbbb-0000-4000-8000-000000000000', 'cuarentena', null),
  ('cccccccc-0000-4000-8000-0000000000d1', 'cccccccc-0000-4000-8000-000000000000', 'deposito', null);

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('aaaaaaaa-0000-4000-8000-0000000000f1', 'aaaaaaaa-0000-4000-8000-000000000000', 'CM-A1', 'Leche A', 'lacteos', 'unidad', 100, true,
   'aaaaaaaa-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-0000000000f2', 'aaaaaaaa-0000-4000-8000-000000000000', 'CM-A2', 'Yogur A', 'lacteos', 'unidad', 100, true,
   'aaaaaaaa-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-0000000000f3', 'aaaaaaaa-0000-4000-8000-000000000000', 'CM-A3', 'Inactivo A', 'lacteos', 'unidad', 1, false,
   'aaaaaaaa-0000-4000-8000-000000000001'),
  ('bbbbbbbb-0000-4000-8000-0000000000f1', 'bbbbbbbb-0000-4000-8000-000000000000', 'CM-B1', 'Leche B', 'lacteos', 'unidad', 100, true,
   'bbbbbbbb-0000-4000-8000-000000000001'),
  ('cccccccc-0000-4000-8000-0000000000f1', 'cccccccc-0000-4000-8000-000000000000', 'CM-C1', 'Leche C', 'lacteos', 'unidad', 100, true,
   'cccccccc-0000-4000-8000-000000000001');

create function pg_temp.como_usuario(uid uuid, metadata jsonb default '{}')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated', 'user_metadata', metadata)::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.como_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
end $$;

-- Saldo calculado de forma independiente, como owner (ve todo el ledger).
create function pg_temp.saldo(ub uuid, prod uuid)
returns bigint language sql as $$
  select coalesce(sum(case when ubicacion_destino_id = ub then cantidad::bigint else 0 end), 0)
       - coalesce(sum(case when ubicacion_origen_id = ub then cantidad::bigint else 0 end), 0)
    from public.movimientos_stock where producto_id = prod
$$;

grant execute on function pg_temp.como_usuario(uuid, jsonb) to public;
grant execute on function pg_temp.como_anon() to public;
grant execute on function pg_temp.saldo(uuid, uuid) to public;

create temp table ops (clave text, id uuid);
grant select, insert on ops to public;
create temp table conteos as select 0 as ops, 0 as movs;
grant select, update on conteos to public;

-- Operaciones sin movimiento (como owner) para probar policies y cardinalidad.
with o as (
  insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella) values
    ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'ingreso',
     '66666666-0000-4000-8000-000000000001', repeat('1', 64)),
    ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'a_cuarentena',
     '66666666-0000-4000-8000-000000000002', repeat('2', 64)),
    ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'merma',
     '66666666-0000-4000-8000-000000000003', repeat('3', 64))
  returning id, tipo)
insert into ops select 'sin_mov_' || tipo, id from o;

-- Stock inicial por la RPC de ingreso: A depósito Leche 20, Yogur 10; B 10; C 5.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select public.registrar_ingreso('10000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 20);
select public.registrar_ingreso('10000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-0000000000f2', 10);
select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select public.registrar_ingreso('10000000-0000-4000-8000-000000000003', 'bbbbbbbb-0000-4000-8000-0000000000f1', 10);
select pg_temp.como_usuario('cccccccc-0000-4000-8000-000000000001');
select public.registrar_ingreso('10000000-0000-4000-8000-000000000004', 'cccccccc-0000-4000-8000-0000000000f1', 5);
reset role;

-- ---------------------------------------------------------------------------
-- Catálogo
-- ---------------------------------------------------------------------------
select is(
  (select format_type(atttypid, atttypmod) || ':' || attnotnull::text from pg_attribute
    where attrelid = 'public.movimientos_stock'::regclass and attname = 'motivo_codigo' and not attisdropped),
  'text:false',
  'movimientos_stock.motivo_codigo: text nullable (D6)');

select is(
  array(select conname::text || ':' || pg_get_constraintdef(oid) from pg_constraint
         where conrelid in ('public.operaciones'::regclass, 'public.movimientos_stock'::regclass)
           and conname in ('operaciones_tipo_valido', 'movimientos_stock_tipo_valido',
                           'movimientos_stock_forma_por_tipo', 'movimientos_stock_motivo_codigo_valido',
                           'movimientos_stock_motivo_por_tipo')
         order by conname::text),
  array['movimientos_stock_forma_por_tipo:CHECK ((((tipo_movimiento = ''ingreso''::text) AND (ubicacion_origen_id IS NULL) AND (ubicacion_destino_id IS NOT NULL)) OR ((tipo_movimiento = ''a_cuarentena''::text) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NOT NULL)) OR ((tipo_movimiento = ''merma''::text) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NULL))))',
        'movimientos_stock_motivo_codigo_valido:CHECK (((motivo_codigo IS NULL) OR (motivo_codigo = ANY (ARRAY[''vencido''::text, ''roto_danado''::text, ''mal_estado''::text, ''error_pedido''::text, ''cambio''::text, ''otro''::text]))))',
        'movimientos_stock_motivo_por_tipo:CHECK ((((tipo_movimiento = ''ingreso''::text) AND (motivo_codigo IS NULL)) OR ((tipo_movimiento = ''a_cuarentena''::text) AND (motivo_codigo IS NULL) AND (motivo IS NOT NULL)) OR ((tipo_movimiento = ''merma''::text) AND (motivo_codigo IS NOT NULL) AND ((motivo_codigo <> ''otro''::text) OR (motivo IS NOT NULL)))))',
        'movimientos_stock_tipo_valido:CHECK ((tipo_movimiento = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text])))',
        'operaciones_tipo_valido:CHECK ((tipo = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text])))'],
  'tipos, forma por tipo y motivos: definiciones exactas (catálogo literal de Blueprint §7.7)');

select is(
  pg_get_indexdef('public.movimientos_stock_operacion_unitaria_unica'::regclass),
  'CREATE UNIQUE INDEX movimientos_stock_operacion_unitaria_unica ON public.movimientos_stock USING btree (empresa_id, operacion_id) WHERE (tipo_movimiento = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text]))',
  'índice único parcial de operaciones unitarias (D7)');

select is(
  array(select tablename || '.' || policyname || ':' || cmd || ':' || array_to_string(roles, ',')
          from pg_policies where schemaname = 'public' and tablename in ('operaciones', 'movimientos_stock')
         order by 1),
  array['movimientos_stock.movimientos_stock_insert_propietario_rpc:INSERT:propietario_rpc',
        'movimientos_stock.movimientos_stock_select_empresa:SELECT:authenticated',
        'movimientos_stock.movimientos_stock_select_propietario_rpc:SELECT:propietario_rpc',
        'operaciones.operaciones_insert_propietario_rpc:INSERT:propietario_rpc',
        'operaciones.operaciones_select_empresa:SELECT:authenticated',
        'operaciones.operaciones_select_propietario_rpc:SELECT:propietario_rpc'],
  'policies sin cambios de nombre ni de roles; sin UPDATE ni DELETE');

select ok(
  (select with_check ~ 'deposito' and with_check ~ 'cuarentena' and with_check ~ 'a_cuarentena'
          and with_check ~ 'merma' and with_check ~ 'o\.tipo = movimientos_stock\.tipo_movimiento'
     from pg_policies where policyname = 'movimientos_stock_insert_propietario_rpc'),
  'la policy de INSERT del ledger fija la forma por tipo y el tipo de la operación');

select is(
  (select p.prosecdef::text || '|' || p.proowner::regrole::text || '|' || array_to_string(p.proconfig, ',')
          || '|' || p.provolatile::text || '|'
          || array_to_string(array(select a::text from unnest(p.proacl) a order by 1), ',')
     from pg_proc p where p.oid = 'public.mover_a_cuarentena(uuid,uuid,uuid,integer,text)'::regprocedure),
  'false|postgres|search_path=""|v|authenticated=X/postgres,postgres=X/postgres',
  'fachada mover_a_cuarentena: INVOKER, de postgres, search_path vacío, sólo authenticated');
select is(
  (select p.prosecdef::text || '|' || p.proowner::regrole::text || '|' || array_to_string(p.proconfig, ',')
          || '|' || p.provolatile::text || '|'
          || array_to_string(array(select a::text from unnest(p.proacl) a order by 1), ',')
     from pg_proc p where p.oid = 'public.registrar_merma(uuid,uuid,uuid,integer,text,text)'::regprocedure),
  'false|postgres|search_path=""|v|authenticated=X/postgres,postgres=X/postgres',
  'fachada registrar_merma: INVOKER, de postgres, search_path vacío, sólo authenticated');
select is(
  (select p.prosecdef::text || '|' || p.proowner::regrole::text || '|' || array_to_string(p.proconfig, ',')
          || '|' || p.provolatile::text || '|'
          || array_to_string(array(select a::text from unnest(p.proacl) a order by 1), ',')
     from pg_proc p where p.oid = 'privado.mover_a_cuarentena(uuid,uuid,uuid,integer,text)'::regprocedure),
  'true|propietario_rpc|search_path=""|v|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc',
  'implementación mover_a_cuarentena: DEFINER, de propietario_rpc, search_path vacío');
select is(
  (select p.prosecdef::text || '|' || p.proowner::regrole::text || '|' || array_to_string(p.proconfig, ',')
          || '|' || p.provolatile::text || '|'
          || array_to_string(array(select a::text from unnest(p.proacl) a order by 1), ',')
     from pg_proc p where p.oid = 'privado.registrar_merma(uuid,uuid,uuid,integer,text,text)'::regprocedure),
  'true|propietario_rpc|search_path=""|v|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc',
  'implementación registrar_merma: DEFINER, de propietario_rpc, search_path vacío');
select is(
  (select count(*)::int from pg_proc
    where proname in ('mover_a_cuarentena', 'registrar_merma')
      and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)),
  4, 'sin sobrecargas');
select is(
  (select count(*)::int from pg_proc
    where proname in ('mover_a_cuarentena', 'registrar_merma')
      and (proargnames && array['p_empresa_id', 'p_actor_id', 'p_tipo', 'p_tipo_movimiento',
                                'p_ubicacion_destino_id', 'p_huella'])),
  0, 'el cliente no envía empresa, actor, tipo, destino ni huella');
select ok(
  has_column_privilege('propietario_rpc', 'public.movimientos_stock', 'motivo_codigo', 'INSERT')
  and not has_any_column_privilege('propietario_rpc', 'public.movimientos_stock', 'UPDATE')
  and not has_table_privilege('propietario_rpc', 'public.movimientos_stock', 'DELETE, TRUNCATE'),
  'propietario_rpc: INSERT de motivo_codigo; sin UPDATE, DELETE ni TRUNCATE');
select is(
  (select count(*)::int
     from unnest(array['public.mover_a_cuarentena(uuid,uuid,uuid,integer,text)',
                       'public.registrar_merma(uuid,uuid,uuid,integer,text,text)',
                       'privado.mover_a_cuarentena(uuid,uuid,uuid,integer,text)',
                       'privado.registrar_merma(uuid,uuid,uuid,integer,text,text)']) f,
          unnest(array['anon', 'service_role']) r
    where has_function_privilege(r, f::regprocedure, 'EXECUTE')),
  0, 'anon y service_role sin EXECUTE sobre las cuatro funciones');
select ok(not has_schema_privilege('propietario_rpc', 'privado', 'CREATE'),
  'propietario_rpc no conserva CREATE sobre privado');

-- ---------------------------------------------------------------------------
-- mover_a_cuarentena: depósito → cuarentena
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into ops select 'cua1', public.mover_a_cuarentena(
      '20000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 5, '  Revisión visual  ')$$,
  'el dueño mueve 5 a cuarentena');
reset role;

select results_eq(
  $$select (select count(*)::int from public.operaciones o where o.id = x.id and o.tipo = 'a_cuarentena'),
           m.tipo_movimiento, m.ubicacion_origen_id, m.ubicacion_destino_id, m.cantidad, m.actor_id,
           m.empresa_id, m.motivo, m.motivo_codigo, count(*) over ()::int
      from public.movimientos_stock m join ops x on x.id = m.operacion_id where x.clave = 'cua1'$$,
  $$values (1, 'a_cuarentena', 'aaaaaaaa-0000-4000-8000-0000000000d1'::uuid,
            'aaaaaaaa-0000-4000-8000-0000000000d2'::uuid, 5, 'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
            'aaaaaaaa-0000-4000-8000-000000000000'::uuid, 'Revisión visual', null::text, 1)$$,
  '1 operación y 1 movimiento: depósito → cuarentena del servidor, actor y empresa reales, motivo con trim');

select is(
  (select huella from public.operaciones o join ops x on x.id = o.id where x.clave = 'cua1'),
  encode(sha256(convert_to(
    'v1|a_cuarentena|aaaaaaaa-0000-4000-8000-0000000000f1|aaaaaaaa-0000-4000-8000-0000000000d1|5|+Revisión visual',
    'UTF8')), 'hex'),
  'huella v1 de cuarentena contra el literal canónico');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select results_eq(
  $$select ubicacion_id, cantidad from public.stock_actual
     where producto_id = 'aaaaaaaa-0000-4000-8000-0000000000f1' order by ubicacion_id$$,
  $$values ('aaaaaaaa-0000-4000-8000-0000000000d1'::uuid, 15::bigint),
           ('aaaaaaaa-0000-4000-8000-0000000000d2'::uuid, 5::bigint)$$,
  'stock_actual: el depósito baja a 15 y la cuarentena sube a 5');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$insert into ops select 'cua2', public.mover_a_cuarentena(
      '20000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 5, 'Envase dudoso')$$,
  'el encargado también mueve a cuarentena (D1)');
select lives_ok(
  $$insert into ops select 'cua_exacto', public.mover_a_cuarentena(
      '20000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 10, 'Lote completo')$$,
  'mover exactamente el saldo restante (10) se permite');
reset role;
select is(pg_temp.saldo('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000f1'), 0::bigint,
  'stock exacto: el depósito queda en 0');

update conteos set ops = (select count(*) from public.operaciones), movs = (select count(*) from public.movimientos_stock);
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.mover_a_cuarentena('20000000-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'Sin stock')$$,
  'PT409', 'stock_insuficiente', 'cuarentena con stock insuficiente: PT409 sin revelar saldo');
reset role;
select results_eq(
  $$select (select count(*)::int from public.operaciones), (select count(*)::int from public.movimientos_stock),
           pg_temp.saldo('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000f1')$$,
  $$select ops, movs, 0::bigint from conteos$$,
  'el rechazo por stock no deja operación, movimiento ni saldo negativo');

-- La clave del rechazo por stock no quedó reservada.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.registrar_ingreso('10000000-0000-4000-8000-000000000010', 'aaaaaaaa-0000-4000-8000-0000000000f1', 3)$$,
  'se reponen 3 unidades');
select lives_ok(
  $$insert into ops select 'cua_tras_insuficiente', public.mover_a_cuarentena(
      '20000000-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'Sin stock')$$,
  'la misma clave del rechazo por stock se usa después: no quedó reservada');

-- Orígenes, productos y validaciones.
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d2', 1, 'x')$$,
  'PT400', 'stock_origen_invalido', 'origen cuarentena: PT400 (D3)');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d3', 1, 'x')$$,
  'PT400', 'stock_origen_invalido', 'origen camión: PT400 (D3)');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'bbbbbbbb-0000-4000-8000-0000000000d1', 1, 'x')$$,
  'PT404', 'stock_ubicacion_no_encontrada', 'origen de otra empresa: PT404');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'eeeeeeee-0000-4000-8000-0000000000d1', 1, 'x')$$,
  'PT404', 'stock_ubicacion_no_encontrada', 'origen inexistente: el mismo PT404');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1', null, 1, 'x')$$,
  'PT404', 'stock_ubicacion_no_encontrada', 'origen NULL');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'bbbbbbbb-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'x')$$,
  'PT404', 'stock_producto_no_encontrado', 'producto de otra empresa: PT404');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f3',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'x')$$,
  'PT409', 'stock_producto_inactivo', 'producto inactivo: PT409');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, null)$$,
  'PT400', 'stock_motivo_invalido', 'motivo NULL: PT400 (D2)');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, '   ')$$,
  'PT400', 'stock_motivo_invalido', 'motivo de espacios: PT400 (D2)');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 0, 'x')$$,
  'PT400', 'stock_cantidad_invalida', 'cantidad 0');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', -2, 'x')$$,
  'PT400', 'stock_cantidad_invalida', 'cantidad negativa');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', null, 'x')$$,
  'PT400', 'stock_cantidad_invalida', 'cantidad NULL');
select throws_ok(
  $$select public.mover_a_cuarentena(null, 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'x')$$,
  'PT400', 'stock_clave_invalida', 'clave NULL');
select pg_temp.como_usuario('cccccccc-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.mover_a_cuarentena(gen_random_uuid(), 'cccccccc-0000-4000-8000-0000000000f1',
      'cccccccc-0000-4000-8000-0000000000d1', 1, 'x')$$,
  'PT500', 'stock_ubicacion_no_configurada', 'empresa sin cuarentena: falla cerrado');

-- Idempotencia.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select is(
  public.mover_a_cuarentena('20000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1',
    'aaaaaaaa-0000-4000-8000-0000000000d1', 5, 'Revisión visual'),
  (select id from ops where clave = 'cua1'),
  'replay: misma clave y mismo payload devuelven el mismo id (el stock actual ya no alcanzaría)');
select throws_ok(
  $$select public.mover_a_cuarentena('20000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 6, 'Revisión visual')$$,
  'PT409', 'stock_conflicto_idempotencia', 'conflicto por cantidad');
select throws_ok(
  $$select public.mover_a_cuarentena('20000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d3', 5, 'Revisión visual')$$,
  'PT409', 'stock_conflicto_idempotencia', 'conflicto por origen');
select throws_ok(
  $$select public.mover_a_cuarentena('20000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 5, 'Revisión visual')$$,
  'PT409', 'stock_conflicto_idempotencia', 'conflicto por producto');
select throws_ok(
  $$select public.mover_a_cuarentena('20000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 5, 'Otro motivo')$$,
  'PT409', 'stock_conflicto_idempotencia', 'conflicto por motivo');
select throws_ok(
  $$select public.registrar_merma('20000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 5, 'vencido')$$,
  'PT409', 'stock_conflicto_idempotencia', 'la clave de una cuarentena no sirve para una merma (otro tipo)');
reset role;

-- ---------------------------------------------------------------------------
-- registrar_merma: depósito → exterior
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into ops select 'mer1', public.registrar_merma(
      '30000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'vencido')$$,
  'el dueño registra una merma (vencido, sin texto)');
reset role;
select results_eq(
  $$select (select count(*)::int from public.operaciones o where o.id = x.id and o.tipo = 'merma'),
           m.tipo_movimiento, m.ubicacion_origen_id, m.ubicacion_destino_id, m.cantidad, m.actor_id,
           m.motivo_codigo, m.motivo, count(*) over ()::int
      from public.movimientos_stock m join ops x on x.id = m.operacion_id where x.clave = 'mer1'$$,
  $$values (1, 'merma', 'aaaaaaaa-0000-4000-8000-0000000000d1'::uuid, null::uuid, 2,
            'aaaaaaaa-0000-4000-8000-000000000001'::uuid, 'vencido', null::text, 1)$$,
  '1 operación y 1 movimiento: depósito → exterior, código del catálogo, motivo NULL');
select is(
  (select huella from public.operaciones o join ops x on x.id = o.id where x.clave = 'mer1'),
  encode(sha256(convert_to(
    'v1|merma|aaaaaaaa-0000-4000-8000-0000000000f2|aaaaaaaa-0000-4000-8000-0000000000d1|2|vencido|-',
    'UTF8')), 'hex'),
  'huella v1 de merma contra el literal canónico (motivo NULL)');
select is(pg_temp.saldo('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000f2'), 8::bigint,
  'la merma descuenta del depósito (10 - 2)');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$insert into ops select 'mer2', public.registrar_merma(
      '30000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'mal_estado', '  Golpeado  ')$$,
  'el encargado registra una merma con texto opcional');
select lives_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'roto_danado')$$, 'código roto_danado');
select lives_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'error_pedido')$$, 'código error_pedido');
select lives_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'cambio')$$, 'código cambio');
select lives_ok(
  $$insert into ops select 'mer_otro', public.registrar_merma(
      '30000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'otro', 'Derrame en cámara')$$, 'código otro con texto');
select lives_ok(
  $$insert into ops select 'mer_trim', public.registrar_merma(
      '30000000-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, '  vencido  ')$$, 'el código se compara después de btrim');
reset role;
select results_eq(
  $$select x.clave, m.motivo_codigo, m.motivo from public.movimientos_stock m join ops x on x.id = m.operacion_id
     where x.clave in ('mer2', 'mer_otro', 'mer_trim') order by x.clave collate "C"$$,
  $$values ('mer2', 'mal_estado', 'Golpeado'), ('mer_otro', 'otro', 'Derrame en cámara'),
           ('mer_trim', 'vencido', null::text)$$,
  'código y motivo normalizados');
select is(
  (select array_agg(distinct m.motivo_codigo order by m.motivo_codigo) from public.movimientos_stock m
    where m.empresa_id = 'aaaaaaaa-0000-4000-8000-000000000000' and m.tipo_movimiento = 'merma'),
  array['cambio', 'error_pedido', 'mal_estado', 'otro', 'roto_danado', 'vencido'],
  'los seis códigos del catálogo quedaron registrados');
select is(
  (select huella from public.operaciones o join ops x on x.id = o.id where x.clave = 'mer_otro'),
  encode(sha256(convert_to(
    'v1|merma|aaaaaaaa-0000-4000-8000-0000000000f2|aaaaaaaa-0000-4000-8000-0000000000d1|1|otro|+Derrame en cámara',
    'UTF8')), 'hex'),
  'huella v1 de merma contra el literal canónico (con texto)');
select is(pg_temp.saldo('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000f2'), 2::bigint,
  'saldo del yogur: 10 - 8 = 2');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'robo')$$,
  'PT400', 'stock_motivo_invalido', 'código fuera del catálogo');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'VENCIDO')$$,
  'PT400', 'stock_motivo_invalido', 'sin normalizar mayúsculas: sólo el código exacto');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, null)$$,
  'PT400', 'stock_motivo_invalido', 'código NULL');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'otro', '  ')$$,
  'PT400', 'stock_motivo_invalido', 'otro sin texto');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d2', 1, 'vencido')$$,
  'PT400', 'stock_origen_invalido', 'merma desde cuarentena: PT400 (D4)');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d3', 1, 'vencido')$$,
  'PT400', 'stock_origen_invalido', 'merma desde camión: PT400 (D3)');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'bbbbbbbb-0000-4000-8000-0000000000d1', 1, 'vencido')$$,
  'PT404', 'stock_ubicacion_no_encontrada', 'merma desde un depósito de otra empresa');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'bbbbbbbb-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'vencido')$$,
  'PT404', 'stock_producto_no_encontrado', 'merma de un producto de otra empresa');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 0, 'vencido')$$,
  'PT400', 'stock_cantidad_invalida', 'merma con cantidad 0');
select lives_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'vencido')$$,
  'merma del saldo exacto (2)');
select throws_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'vencido')$$,
  'PT409', 'stock_insuficiente', 'merma con stock insuficiente');
select is(
  public.registrar_merma('30000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f2',
    'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'vencido'),
  (select id from ops where clave = 'mer1'),
  'replay de merma: mismo id aunque ya no haya stock');
select throws_ok(
  $$select public.registrar_merma('30000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'mal_estado')$$,
  'PT409', 'stock_conflicto_idempotencia', 'conflicto de merma por código');
select throws_ok(
  $$select public.registrar_merma('30000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'vencido', 'Con texto')$$,
  'PT409', 'stock_conflicto_idempotencia', 'conflicto de merma por motivo');
select throws_ok(
  $$select public.registrar_merma('30000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 3, 'vencido')$$,
  'PT409', 'stock_conflicto_idempotencia', 'conflicto de merma por cantidad');
reset role;
select is(pg_temp.saldo('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000f2'), 0::bigint,
  'saldo del yogur en 0, nunca negativo');

select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.registrar_merma(gen_random_uuid(), 'bbbbbbbb-0000-4000-8000-0000000000f1',
      'bbbbbbbb-0000-4000-8000-0000000000d1', 1, 'roto_danado')$$,
  'el dueño de B registra una merma en B');
select is((select count(*)::int from public.movimientos_stock where empresa_id = 'aaaaaaaa-0000-4000-8000-000000000000'), 0,
  'el dueño de B no ve movimientos de A');
reset role;

-- ---------------------------------------------------------------------------
-- Autorización (las dos RPC)
-- ---------------------------------------------------------------------------
update conteos set ops = (select count(*) from public.operaciones), movs = (select count(*) from public.movimientos_stock);
create temp table llamadas (rpc text, sql text);
insert into llamadas values
  ('mover_a_cuarentena', $$select public.mover_a_cuarentena(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1', 'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'x')$$),
  ('registrar_merma', $$select public.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1', 'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'vencido')$$);
grant select on llamadas to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003',
  '{"rol":"dueno","empresa_id":"bbbbbbbb-0000-4000-8000-000000000000"}');
select throws_ok(l.sql, 'PT403', 'stock_no_autorizado', l.rpc || ': el vendedor (metadata de dueño) recibe PT403')
  from llamadas l order by l.rpc;
select throws_ok(
  $$select privado.registrar_merma(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1', 'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'vencido')$$,
  'PT403', 'stock_no_autorizado', 'la implementación privada llamada por SQL también rechaza al vendedor');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000004');
select throws_ok(l.sql, 'PT403', 'stock_no_autorizado', l.rpc || ': un perfil inactivo recibe PT403')
  from llamadas l order by l.rpc;
select pg_temp.como_usuario('dddddddd-0000-4000-8000-000000000001',
  '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');
select throws_ok(l.sql, 'PT403', 'stock_no_autorizado', l.rpc || ': una cuenta sin perfil recibe PT403')
  from llamadas l order by l.rpc;
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok(l.sql, 'PT401', 'stock_no_autenticado', l.rpc || ': sin sub en el JWT recibe PT401')
  from llamadas l order by l.rpc;
select pg_temp.como_anon();
select throws_ok(l.sql, '42501', null, l.rpc || ': anon no puede ejecutar')
  from llamadas l order by l.rpc;
reset role;
grant usage on schema extensions to service_role;
set local role service_role;
select throws_ok(l.sql, '42501', null, l.rpc || ': service_role no puede ejecutar')
  from llamadas l order by l.rpc;
reset role;
select results_eq(
  $$select (select count(*)::int from public.operaciones), (select count(*)::int from public.movimientos_stock)$$,
  $$select ops, movs from conteos$$,
  'ningún rechazo de autorización dejó efectos');

-- ---------------------------------------------------------------------------
-- Replay con estado mutable cambiado (cierra también el L-2 del ingreso)
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok($$select public.cambiar_estado_producto('aaaaaaaa-0000-4000-8000-0000000000f1', false)$$,
  'se desactiva el producto de la cuarentena original');
select is(
  public.mover_a_cuarentena('20000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1',
    'aaaaaaaa-0000-4000-8000-0000000000d1', 5, 'Revisión visual'),
  (select id from ops where clave = 'cua1'),
  'replay de cuarentena con el producto inactivo: mismo id');
select lives_ok($$select public.cambiar_estado_producto('aaaaaaaa-0000-4000-8000-0000000000f1', true)$$,
  'se reactiva el producto');
reset role;

update public.perfiles set activo = false where usuario_id = 'aaaaaaaa-0000-4000-8000-000000000001';
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.mover_a_cuarentena('20000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 5, 'Revisión visual')$$,
  'PT403', 'stock_no_autorizado', 'replay de un actor que quedó inactivo: PT403');
reset role;
update public.perfiles set activo = true, rol = 'vendedor_piloto' where usuario_id = 'aaaaaaaa-0000-4000-8000-000000000001';
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.registrar_merma('30000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f2',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 2, 'vencido')$$,
  'PT403', 'stock_no_autorizado', 'replay de merma de un actor que pasó a vendedor: PT403');
select throws_ok(
  $$select public.registrar_ingreso('10000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 20)$$,
  'PT403', 'stock_no_autorizado', 'replay de ingreso de un actor que pasó a vendedor: PT403 (L-2 del slice 1)');
reset role;
update public.perfiles set rol = 'dueno' where usuario_id = 'aaaaaaaa-0000-4000-8000-000000000001';

-- ---------------------------------------------------------------------------
-- Escritura directa: nadie de la API escribe operaciones ni el ledger
-- ---------------------------------------------------------------------------
create temp table huella_ledger as
  select (select md5(string_agg(o::text, '|' order by o.id)) from public.operaciones o) as ops,
         (select md5(string_agg(m::text, '|' order by m.id)) from public.movimientos_stock m) as movs;
grant select on huella_ledger to public;
create temp table dml (n int, sql text);
insert into dml values
  (1, $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella) values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'merma', gen_random_uuid(), repeat('a', 64))$$),
  (2, $$update public.operaciones set tipo = 'merma'$$),
  (3, $$delete from public.operaciones$$),
  (4, $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, actor_id, motivo_codigo) values ('aaaaaaaa-0000-4000-8000-000000000000', gen_random_uuid(), 'merma', 'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001', 'vencido')$$),
  (5, $$update public.movimientos_stock set cantidad = 1$$),
  (6, $$delete from public.movimientos_stock$$);
grant select on dml to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(d.sql, '42501', null, 'dueño: DML directo #' || d.n || ' rechazado') from dml d order by d.n;
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select throws_ok(d.sql, '42501', null, 'encargado: DML directo #' || d.n || ' rechazado') from dml d order by d.n;
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select throws_ok(d.sql, '42501', null, 'vendedor: DML directo #' || d.n || ' rechazado') from dml d order by d.n;
select pg_temp.como_anon();
select throws_ok(d.sql, '42501', null, 'anon: DML directo #' || d.n || ' rechazado') from dml d order by d.n;
reset role;
set local role service_role;
select throws_ok(d.sql, '42501', null, 'service_role: DML directo #' || d.n || ' rechazado') from dml d order by d.n;
reset role;
select results_eq(
  $$select (select md5(string_agg(o::text, '|' order by o.id)) from public.operaciones o),
           (select md5(string_agg(m::text, '|' order by m.id)) from public.movimientos_stock m)$$,
  $$select ops, movs from huella_ledger$$,
  'ningún DML directo cambió operaciones ni el ledger');

-- ---------------------------------------------------------------------------
-- propietario_rpc: policies endurecidas (identidad de dueño A)
-- ---------------------------------------------------------------------------
grant usage on schema extensions to propietario_rpc;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;
select throws_ok($$update public.movimientos_stock set cantidad = 1$$, '42501', null, 'propietario_rpc no actualiza el ledger');
select throws_ok($$delete from public.movimientos_stock$$, '42501', null, 'propietario_rpc no borra el ledger');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_ingreso'), 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d2', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'D8: un ingreso hacia la cuarentena se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_ingreso'), 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d3', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'D8: un ingreso hacia un camión se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_a_cuarentena'), 'a_cuarentena',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000d3',
            'aaaaaaaa-0000-4000-8000-000000000001', 'x')$$,
  '42501', null, 'a_cuarentena de depósito hacia un camión (no cuarentena): rechazado por RLS');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_a_cuarentena'), 'a_cuarentena',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d3', 'aaaaaaaa-0000-4000-8000-0000000000d2',
            'aaaaaaaa-0000-4000-8000-000000000001', 'x')$$,
  '42501', null, 'a_cuarentena con origen camión: rechazado por RLS');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, actor_id, motivo_codigo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_merma'), 'merma',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d2',
            'aaaaaaaa-0000-4000-8000-000000000001', 'vencido')$$,
  '42501', null, 'merma desde cuarentena: rechazada por RLS (D4)');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, actor_id, motivo_codigo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_ingreso'), 'merma',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001', 'vencido')$$,
  '42501', null, 'movimiento de otro tipo que su operación: rechazado por RLS');
select lives_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_a_cuarentena'), 'a_cuarentena',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000d2',
            'aaaaaaaa-0000-4000-8000-000000000001', 'x')$$,
  'control positivo: la forma aprobada de a_cuarentena pasa la policy');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_a_cuarentena'), 'a_cuarentena',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000d2',
            'aaaaaaaa-0000-4000-8000-000000000001', 'x')$$,
  '23505', null, 'D7: un segundo movimiento para la misma operación unitaria se rechaza');
reset role;

-- ---------------------------------------------------------------------------
-- Restricciones del ledger (como owner)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo_codigo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_merma'), 'merma',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000d2',
            'aaaaaaaa-0000-4000-8000-000000000001', 'vencido')$$,
  '23514', null, 'una merma con destino se rechaza (forma)');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_merma'), 'merma',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'una merma sin código se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, actor_id, motivo_codigo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_merma'), 'merma',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001', 'robo')$$,
  '23514', null, 'un código fuera del catálogo se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, actor_id, motivo_codigo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_merma'), 'merma',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001', 'otro')$$,
  '23514', null, 'otro sin texto se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_merma'), 'a_cuarentena',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-0000000000d2',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'una cuarentena sin motivo se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_destino_id, actor_id, motivo_codigo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_ingreso'), 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001', 'vencido')$$,
  '23514', null, 'un ingreso con código de merma se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov_merma'), 'a_cuarentena',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1', 'bbbbbbbb-0000-4000-8000-0000000000d2',
            'aaaaaaaa-0000-4000-8000-000000000001', 'x')$$,
  '23503', null, 'una cuarentena de A hacia la cuarentena de B: FK compuesta (como owner)');

-- ---------------------------------------------------------------------------
-- Atomicidad: si falla el movimiento, no queda la operación ni la clave
-- ---------------------------------------------------------------------------
update conteos set ops = (select count(*) from public.operaciones), movs = (select count(*) from public.movimientos_stock);
revoke insert (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id,
               ubicacion_destino_id, actor_id, motivo, motivo_codigo)
  on table public.movimientos_stock from propietario_rpc;
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.mover_a_cuarentena('40000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'Atómico')$$,
  'PT500', 'stock_error_interno', 'cuarentena: si el movimiento falla, la RPC falla con error interno');
select throws_ok(
  $$select public.registrar_merma('40000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'vencido')$$,
  'PT500', 'stock_error_interno', 'merma: si el movimiento falla, la RPC falla con error interno');
reset role;
grant insert (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id,
              ubicacion_destino_id, actor_id, motivo, motivo_codigo)
  on table public.movimientos_stock to propietario_rpc;
select results_eq(
  $$select (select count(*)::int from public.operaciones), (select count(*)::int from public.movimientos_stock)$$,
  $$select ops, movs from conteos$$,
  'sin operaciones huérfanas ni movimientos');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.mover_a_cuarentena('40000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1',
      'aaaaaaaa-0000-4000-8000-0000000000d1', 1, 'Atómico')$$,
  'la clave del intento fallido se reutiliza');
reset role;

-- Ningún saldo negativo en toda la base de prueba.
select is(
  (select count(*)::int from public.stock_actual where cantidad < 0),
  0, 'ningún saldo de stock_actual es negativo');

select * from finish();

rollback;
