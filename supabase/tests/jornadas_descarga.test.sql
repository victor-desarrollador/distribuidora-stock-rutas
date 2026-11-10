-- pgTAP: T6 — RPC registrar_descarga (Blueprint §7.2, §7.4, §7.5, §9 y §12; ADR-007
-- §2.2, §2.6, §2.7 y §7 casos 18, 19, 22 y 24; ADR-005 D-R2; ADR-001 §18.4.2 a §18.4.9,
-- grupos S e I, y E-SL1 §18.4.16). Ejecutar sólo en local.
--
-- B es un fixture adversarial (aislamiento por empresa_id). Las jornadas se cargan
-- con la RPC real de T5. La concurrencia (I10-D, I11-D, K11-d y carga contra
-- descarga) está en supabase/tests/concurrencia/casos.sh. El estado en_reparto
-- (caso 22 e I3) es un fixture controlado (owner) porque confirmar_salida todavía
-- no existe; se repite con el flujo real en T7. Los objetos pg_temp adversariales y
-- la guardia estática (P7 global) están en pg_temp_jornadas.test.sql. El bloque de
-- sólo lectura (E-SL1) va al final: después de SET transaction_read_only = on la
-- transacción ya no vuelve a escritura.

begin;

create extension if not exists pgtap with schema extensions;

select plan(93);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-6600-4000-8000-000000000000', 'Empresa A (test T6)'),
  ('bbbbbbbb-6600-4000-8000-000000000000', 'Empresa B (test T6)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-6600-4000-8000-000000000001', 'authenticated', 'authenticated', 'jd.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-6600-4000-8000-000000000002', 'authenticated', 'authenticated', 'jd.a2@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-6600-4000-8000-000000000003', 'authenticated', 'authenticated', 'jd.a3@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-6600-4000-8000-000000000004', 'authenticated', 'authenticated', 'jd.a4@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-6600-4000-8000-000000000005', 'authenticated', 'authenticated', 'jd.a5@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-6600-4000-8000-000000000006', 'authenticated', 'authenticated', 'jd.a6@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-6600-4000-8000-000000000007', 'authenticated', 'authenticated', 'jd.a7@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-6600-4000-8000-000000000001', 'authenticated', 'authenticated', 'jd.b1@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-6600-4000-8000-000000000002', 'authenticated', 'authenticated', 'jd.b2@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-6600-4000-8000-000000000001', 'authenticated', 'authenticated', 'jd.n1@usuarios.distribuidora.invalid', '{"rol":"dueno","empresa_id":"aaaaaaaa-6600-4000-8000-000000000000"}');

-- A: dueño (1), encargado (2), vendedores (3, 5, 6, 7), dueño inactivo (4).
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-6600-4000-8000-000000000001', 'aaaaaaaa-6600-4000-8000-000000000000', 'jd.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-6600-4000-8000-000000000002', 'aaaaaaaa-6600-4000-8000-000000000000', 'jd.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-6600-4000-8000-000000000003', 'aaaaaaaa-6600-4000-8000-000000000000', 'jd.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-6600-4000-8000-000000000004', 'aaaaaaaa-6600-4000-8000-000000000000', 'jd.a4', 'A4', 'dueno', false),
  ('aaaaaaaa-6600-4000-8000-000000000005', 'aaaaaaaa-6600-4000-8000-000000000000', 'jd.a5', 'A5', 'vendedor_piloto', true),
  ('aaaaaaaa-6600-4000-8000-000000000006', 'aaaaaaaa-6600-4000-8000-000000000000', 'jd.a6', 'A6', 'vendedor_piloto', true),
  ('aaaaaaaa-6600-4000-8000-000000000007', 'aaaaaaaa-6600-4000-8000-000000000000', 'jd.a7', 'A7', 'vendedor_piloto', true),
  ('bbbbbbbb-6600-4000-8000-000000000001', 'bbbbbbbb-6600-4000-8000-000000000000', 'jd.b1', 'B1', 'dueno', true),
  ('bbbbbbbb-6600-4000-8000-000000000002', 'bbbbbbbb-6600-4000-8000-000000000000', 'jd.b2', 'B2', 'vendedor_piloto', true);

-- Camiones: c1 (descargas normales), c2 (se da de baja con jornada cargada), c3
-- (jornada abierta), c4 (jornada en_reparto), c5 (sin ubicación), c6 (I3). B: uno.
insert into public.camiones (id, empresa_id, patente, nombre, activo, creado_por) values
  ('aaaaaaaa-6600-4000-8000-0000000000c1', 'aaaaaaaa-6600-4000-8000-000000000000', 'JD-01', 'Camión A1', true, 'aaaaaaaa-6600-4000-8000-000000000001'),
  ('aaaaaaaa-6600-4000-8000-0000000000c2', 'aaaaaaaa-6600-4000-8000-000000000000', 'JD-02', 'Camión A2', true, 'aaaaaaaa-6600-4000-8000-000000000001'),
  ('aaaaaaaa-6600-4000-8000-0000000000c3', 'aaaaaaaa-6600-4000-8000-000000000000', 'JD-03', 'Camión A3', true, 'aaaaaaaa-6600-4000-8000-000000000001'),
  ('aaaaaaaa-6600-4000-8000-0000000000c4', 'aaaaaaaa-6600-4000-8000-000000000000', 'JD-04', 'Camión A4', true, 'aaaaaaaa-6600-4000-8000-000000000001'),
  ('aaaaaaaa-6600-4000-8000-0000000000c5', 'aaaaaaaa-6600-4000-8000-000000000000', 'JD-05', 'Camión A5', true, 'aaaaaaaa-6600-4000-8000-000000000001'),
  ('aaaaaaaa-6600-4000-8000-0000000000c6', 'aaaaaaaa-6600-4000-8000-000000000000', 'JD-06', 'Camión A6', true, 'aaaaaaaa-6600-4000-8000-000000000001'),
  ('bbbbbbbb-6600-4000-8000-0000000000c1', 'bbbbbbbb-6600-4000-8000-000000000000', 'JD-B1', 'Camión B1', true, 'bbbbbbbb-6600-4000-8000-000000000001');

insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('aaaaaaaa-6600-4000-8000-0000000000d1', 'aaaaaaaa-6600-4000-8000-000000000000', 'deposito', null),
  ('aaaaaaaa-6600-4000-8000-0000000000e1', 'aaaaaaaa-6600-4000-8000-000000000000', 'camion', 'aaaaaaaa-6600-4000-8000-0000000000c1'),
  ('aaaaaaaa-6600-4000-8000-0000000000e2', 'aaaaaaaa-6600-4000-8000-000000000000', 'camion', 'aaaaaaaa-6600-4000-8000-0000000000c2'),
  ('aaaaaaaa-6600-4000-8000-0000000000e3', 'aaaaaaaa-6600-4000-8000-000000000000', 'camion', 'aaaaaaaa-6600-4000-8000-0000000000c3'),
  ('aaaaaaaa-6600-4000-8000-0000000000e4', 'aaaaaaaa-6600-4000-8000-000000000000', 'camion', 'aaaaaaaa-6600-4000-8000-0000000000c4'),
  ('aaaaaaaa-6600-4000-8000-0000000000e6', 'aaaaaaaa-6600-4000-8000-000000000000', 'camion', 'aaaaaaaa-6600-4000-8000-0000000000c6'),
  ('bbbbbbbb-6600-4000-8000-0000000000d1', 'bbbbbbbb-6600-4000-8000-000000000000', 'deposito', null),
  ('bbbbbbbb-6600-4000-8000-0000000000e1', 'bbbbbbbb-6600-4000-8000-000000000000', 'camion', 'bbbbbbbb-6600-4000-8000-0000000000c1');

-- Productos de A: f1 unidad, f2 fiambre por peso (gramos), f3 (se da de baja
-- después de cargarlo), f4 (nunca se carga en J1). B: un producto.
insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('aaaaaaaa-6600-4000-8000-0000000000f1', 'aaaaaaaa-6600-4000-8000-000000000000', 'JD-U', 'Leche A', 'lacteos', 'unidad', 100, true, 'aaaaaaaa-6600-4000-8000-000000000001'),
  ('aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-000000000000', 'JD-P', 'Jamón A', 'fiambres', 'peso', 9000, true, 'aaaaaaaa-6600-4000-8000-000000000001'),
  ('aaaaaaaa-6600-4000-8000-0000000000f3', 'aaaaaaaa-6600-4000-8000-000000000000', 'JD-I', 'Queso A', 'lacteos', 'unidad', 100, true, 'aaaaaaaa-6600-4000-8000-000000000001'),
  ('aaaaaaaa-6600-4000-8000-0000000000f4', 'aaaaaaaa-6600-4000-8000-000000000000', 'JD-N', 'Yogur A', 'lacteos', 'unidad', 100, true, 'aaaaaaaa-6600-4000-8000-000000000001'),
  ('bbbbbbbb-6600-4000-8000-0000000000f1', 'bbbbbbbb-6600-4000-8000-000000000000', 'JD-B', 'Leche B', 'lacteos', 'unidad', 100, true, 'bbbbbbbb-6600-4000-8000-000000000001');

create function pg_temp.como_usuario(uid uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.sin_sub()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.como_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
end $$;
create function pg_temp.como_service_role()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
end $$;

-- Jornada de fixture (como owner): operación de apertura + jornada.
create function pg_temp.jornada(j uuid, camion uuid, fecha date, vendedor uuid, estado text)
returns void language sql security definer set search_path = '' as $$
  insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella)
  values (j, 'aaaaaaaa-6600-4000-8000-000000000000', 'aaaaaaaa-6600-4000-8000-000000000001',
          'apertura_jornada', j, repeat('a', 64));
  insert into public.jornadas (id, empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
  values (j, 'aaaaaaaa-6600-4000-8000-000000000000', fecha, camion, vendedor, estado,
          'aaaaaaaa-6600-4000-8000-000000000001', j);
$$;
create function pg_temp.saldo(ubicacion uuid, producto uuid)
returns bigint language sql security definer set search_path = '' as $$
  select coalesce(sum(case when m.ubicacion_destino_id = ubicacion then m.cantidad::bigint
                           else -m.cantidad::bigint end), 0)
    from public.movimientos_stock m
   where m.producto_id = producto
     and (m.ubicacion_destino_id = ubicacion or m.ubicacion_origen_id = ubicacion)
$$;
-- Carga neta de una jornada por producto (Σ cargas − Σ descargas de esa jornada).
create function pg_temp.neta(jornada uuid, producto uuid)
returns bigint language sql security definer set search_path = '' as $$
  select coalesce(sum(case when m.tipo_movimiento = 'carga' then m.cantidad::bigint
                           else -m.cantidad::bigint end), 0)
    from public.movimientos_stock m
   where m.jornada_id = jornada and m.producto_id = producto
     and m.tipo_movimiento in ('carga', 'descarga')
$$;
create function pg_temp.conteo()
returns text language sql security definer set search_path = '' as $$
  select (select count(*) from public.operaciones)::text
    || '|' || (select count(*) from public.movimientos_stock)::text
    || '|' || (select count(*) from public.jornadas)::text
    || '|' || (select string_agg(j.id::text || '=' || j.estado, ',' order by j.id)
                 from public.jornadas j where j.empresa_id = 'aaaaaaaa-6600-4000-8000-000000000000')
$$;
create temp table snap (v text);
grant select, insert, delete on snap to public;
create function pg_temp.fijar()
returns void language sql security definer set search_path = '' as $$
  delete from pg_temp.snap;
  insert into pg_temp.snap select pg_temp.conteo();
$$;
create function pg_temp.igual()
returns boolean language sql security definer set search_path = '' as $$
  select pg_temp.conteo() = (select v from pg_temp.snap)
$$;
create function pg_temp.sin_clave(k uuid)
returns boolean language sql security definer set search_path = '' as $$
  select not exists (select 1 from public.operaciones o where o.idempotency_key = k)
$$;
create function pg_temp.huella(texto text)
returns text language sql as $$
  select encode(sha256(convert_to(texto, 'UTF8')), 'hex')
$$;
grant execute on function pg_temp.como_usuario(uuid), pg_temp.sin_sub(), pg_temp.como_anon(),
  pg_temp.como_service_role(), pg_temp.saldo(uuid, uuid), pg_temp.neta(uuid, uuid), pg_temp.conteo(),
  pg_temp.fijar(), pg_temp.igual(), pg_temp.sin_clave(uuid), pg_temp.huella(text) to public;

create temp table res (k text primary key, v uuid);
grant select, insert on res to public;

-- Jornadas: J1 (c1), J2 (c2), J3 (c3, queda abierta), J4 (c4, pasa a en_reparto),
-- J5 (c5, cargada como fixture, sin ubicación), J6 (c6, I3). JB de B.
select pg_temp.jornada('aaaaaaaa-6600-4000-8000-0000000000a1', 'aaaaaaaa-6600-4000-8000-0000000000c1', date '2999-06-01', 'aaaaaaaa-6600-4000-8000-000000000003', 'abierta');
select pg_temp.jornada('aaaaaaaa-6600-4000-8000-0000000000a2', 'aaaaaaaa-6600-4000-8000-0000000000c2', date '2999-06-01', 'aaaaaaaa-6600-4000-8000-000000000005', 'abierta');
select pg_temp.jornada('aaaaaaaa-6600-4000-8000-0000000000a3', 'aaaaaaaa-6600-4000-8000-0000000000c3', date '2999-06-01', 'aaaaaaaa-6600-4000-8000-000000000006', 'abierta');
select pg_temp.jornada('aaaaaaaa-6600-4000-8000-0000000000a4', 'aaaaaaaa-6600-4000-8000-0000000000c4', date '2999-06-01', 'aaaaaaaa-6600-4000-8000-000000000007', 'abierta');
select pg_temp.jornada('aaaaaaaa-6600-4000-8000-0000000000a5', 'aaaaaaaa-6600-4000-8000-0000000000c5', date '2999-06-01', 'aaaaaaaa-6600-4000-8000-000000000001', 'cargada');
select pg_temp.jornada('aaaaaaaa-6600-4000-8000-0000000000a6', 'aaaaaaaa-6600-4000-8000-0000000000c6', date '2999-06-01', 'aaaaaaaa-6600-4000-8000-000000000002', 'abierta');
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella) values
  ('bbbbbbbb-6600-4000-8000-0000000000a1', 'bbbbbbbb-6600-4000-8000-000000000000', 'bbbbbbbb-6600-4000-8000-000000000001',
   'apertura_jornada', 'bbbbbbbb-6600-4000-8000-0000000000a1', repeat('b', 64));
insert into public.jornadas (id, empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id) values
  ('bbbbbbbb-6600-4000-8000-0000000000a1', 'bbbbbbbb-6600-4000-8000-000000000000', date '2999-06-01',
   'bbbbbbbb-6600-4000-8000-0000000000c1', 'bbbbbbbb-6600-4000-8000-000000000002', 'abierta',
   'bbbbbbbb-6600-4000-8000-000000000001', 'bbbbbbbb-6600-4000-8000-0000000000a1');

-- Stock y cargas con las RPC reales (dueño de A y de B). Depósito de A: f1 100,
-- f2 5000 g, f3 20, f4 10. Cargas: J1 f1 30, f2 2000 g, f3 5; J2 f1 10; J4 f1 5;
-- J6 f1 4. B: 50 al depósito y 7 cargadas en JB.
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000001');
select public.registrar_ingreso('66000000-0000-4000-8000-000000000001', 'aaaaaaaa-6600-4000-8000-0000000000f1', 100, 'Remito T6');
select public.registrar_ingreso('66000000-0000-4000-8000-000000000002', 'aaaaaaaa-6600-4000-8000-0000000000f2', 5000, 'Remito T6');
select public.registrar_ingreso('66000000-0000-4000-8000-000000000003', 'aaaaaaaa-6600-4000-8000-0000000000f3', 20, 'Remito T6');
select public.registrar_ingreso('66000000-0000-4000-8000-000000000004', 'aaaaaaaa-6600-4000-8000-0000000000f4', 10, 'Remito T6');
select public.registrar_carga('66000000-0000-4000-8000-0000000000c1', 'aaaaaaaa-6600-4000-8000-0000000000a1',
  array['aaaaaaaa-6600-4000-8000-0000000000f1', 'aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f3']::uuid[], array[30, 2000, 5]);
select public.registrar_carga('66000000-0000-4000-8000-0000000000c2', 'aaaaaaaa-6600-4000-8000-0000000000a2',
  array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[10]);
select public.registrar_carga('66000000-0000-4000-8000-0000000000c4', 'aaaaaaaa-6600-4000-8000-0000000000a4',
  array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[5]);
select public.registrar_carga('66000000-0000-4000-8000-0000000000c6', 'aaaaaaaa-6600-4000-8000-0000000000a6',
  array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[4]);
reset role;
select pg_temp.como_usuario('bbbbbbbb-6600-4000-8000-000000000001');
select public.registrar_ingreso('66000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-6600-4000-8000-0000000000f1', 50, 'Remito B');
select public.registrar_carga('66000000-0000-4000-8000-0000000000b2', 'bbbbbbbb-6600-4000-8000-0000000000a1',
  array['bbbbbbbb-6600-4000-8000-0000000000f1']::uuid[], array[7]);
reset role;
-- Fixtures posteriores a la carga: J4 en_reparto; baja de c2 y de f3.
update public.jornadas set estado = 'en_reparto' where id = 'aaaaaaaa-6600-4000-8000-0000000000a4';
update public.camiones set activo = false where id = 'aaaaaaaa-6600-4000-8000-0000000000c2';
update public.productos set activo = false where id = 'aaaaaaaa-6600-4000-8000-0000000000f3';

create temp table huella_b as
select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.jornadas t
         where t.empresa_id = 'bbbbbbbb-6600-4000-8000-000000000000')
       || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.operaciones t
                   where t.empresa_id = 'bbbbbbbb-6600-4000-8000-000000000000')
       || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.movimientos_stock t
                   where t.empresa_id = 'bbbbbbbb-6600-4000-8000-000000000000') as h;
create temp table cargas_j1 as
select string_agg(m.id::text || ':' || m.cantidad::text, ',' order by m.id) as h
  from public.movimientos_stock m
 where m.jornada_id = 'aaaaaaaa-6600-4000-8000-0000000000a1' and m.tipo_movimiento = 'carga';

-- ===========================================================================
-- 1. Catálogo (S)
-- ===========================================================================
select is(
  (select count(*)::int from pg_proc where proname = 'registrar_descarga'),
  2, 'registrar_descarga: exactamente dos funciones (fachada e implementación), sin sobrecargas');
select ok(
  (select p.prosecdef and p.provolatile = 'v' and p.proowner = 'propietario_rpc'::regrole
          and p.proconfig = array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']
     from pg_proc p where p.oid = 'privado.registrar_descarga(uuid,uuid,uuid[],integer[],text)'::regprocedure),
  'implementación: SECURITY DEFINER, VOLATILE, owner propietario_rpc, search_path vacío, ACL exacta');
select ok(
  (select not p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole
          and p.proconfig = array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/postgres', 'postgres=X/postgres']
          and p.prosrc !~* 'insert|update|delete'
     from pg_proc p where p.oid = 'public.registrar_descarga(uuid,uuid,uuid[],integer[],text)'::regprocedure),
  'fachada: SECURITY INVOKER, owner postgres, search_path vacío, ACL exacta, sólo delega');
select ok(
  not has_function_privilege('anon', 'public.registrar_descarga(uuid,uuid,uuid[],integer[],text)', 'execute')
  and not has_function_privilege('service_role', 'public.registrar_descarga(uuid,uuid,uuid[],integer[],text)', 'execute')
  and not has_function_privilege('anon', 'privado.registrar_descarga(uuid,uuid,uuid[],integer[],text)', 'execute')
  and not has_function_privilege('service_role', 'privado.registrar_descarga(uuid,uuid,uuid[],integer[],text)', 'execute')
  and not has_schema_privilege('propietario_rpc', 'privado', 'create'),
  'P11: anon y service_role sin EXECUTE; propietario_rpc sin CREATE residual');
select ok(
  (select prosrc from pg_proc where oid = 'privado.registrar_descarga(uuid,uuid,uuid[],integer[],text)'::regprocedure)
    ~ E'\\nbegin\\n  -- Paso 0 \\(E-SL1',
  'E-SL1: la guarda de sólo lectura es la primera sentencia');

-- ===========================================================================
-- 2. Seguridad (S)
-- ===========================================================================
select pg_temp.como_anon();
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000100', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, '42501', null, 'anon no puede ejecutar la fachada');
reset role;
select pg_temp.como_anon();
select throws_ok($q$select privado.registrar_descarga('66000000-0000-4000-8000-000000000100', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, '42501', null, 'anon no puede ejecutar la implementación');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000100', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, '42501', null, 'service_role no puede ejecutar la fachada');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select privado.registrar_descarga('66000000-0000-4000-8000-000000000100', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, '42501', null, 'service_role no puede ejecutar la implementación');
reset role;

select pg_temp.fijar();
select pg_temp.sin_sub();
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000101', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT401', 'jornada_no_autenticado', 'sin sub: PT401');
reset role;
select pg_temp.como_usuario('dddddddd-6600-4000-8000-000000000001');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000102', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT403', 'jornada_no_autorizado', 'cuenta sin perfil (con metadata de dueño de A): PT403');
reset role;
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000004');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000103', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT403', 'jornada_no_autorizado', 'dueño inactivo: PT403');
reset role;
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000003');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000104', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT403', 'jornada_no_autorizado', 'vendedor_piloto (asignado a la jornada): PT403');
reset role;
select pg_temp.como_usuario('bbbbbbbb-6600-4000-8000-000000000001');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000105', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['bbbbbbbb-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT404', 'jornada_no_encontrada', 'dueño de B con la jornada de A: PT404, igual que inexistente');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000106', 'cccccccc-6600-4000-8000-0000000000a1', array['bbbbbbbb-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT404', 'jornada_no_encontrada', 'jornada inexistente: PT404');
reset role;
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000001');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000107', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['bbbbbbbb-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT404', 'jornada_producto_no_encontrado', 'producto de otra empresa: PT404');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000108', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['cccccccc-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT404', 'jornada_producto_no_encontrado', 'producto inexistente: el mismo PT404');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000109', 'bbbbbbbb-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT404', 'jornada_no_encontrada', 'dueño de A con la jornada de B: PT404');
select throws_ok($q$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id, motivo) values ('aaaaaaaa-6600-4000-8000-000000000000', 'aaaaaaaa-6600-4000-8000-0000000000a1', 'descarga', 'aaaaaaaa-6600-4000-8000-0000000000f1', 1, 'aaaaaaaa-6600-4000-8000-0000000000e1', 'aaaaaaaa-6600-4000-8000-0000000000d1', 'aaaaaaaa-6600-4000-8000-000000000001', 'aaaaaaaa-6600-4000-8000-0000000000a1', 'x')$q$, '42501', null, 'DML directo de authenticated sobre el ledger: 42501');
reset role;
select ok(pg_temp.igual(), 'los rechazos de seguridad no dejaron filas nuevas ni cambiaron estados');
select ok(pg_temp.sin_clave('66000000-0000-4000-8000-000000000101') and pg_temp.sin_clave('66000000-0000-4000-8000-000000000105')
          and pg_temp.sin_clave('66000000-0000-4000-8000-000000000107'),
  'los rechazos de seguridad no reservaron claves');

-- ===========================================================================
-- 3. Estructura (paso 3; I5, I13 e I14)
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000001');
select throws_ok($q$select public.registrar_descarga(null, 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT400', 'jornada_clave_invalida', 'I14: clave nula');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000201', null, array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT404', 'jornada_no_encontrada', 'I13: jornada nula (D-N1)');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000202', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], null)$q$, 'PT400', 'jornada_motivo_invalido', 'I13: motivo nulo');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000203', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], '   ')$q$, 'PT400', 'jornada_motivo_invalido', 'I13: motivo vacío después de btrim');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000204', 'aaaaaaaa-6600-4000-8000-0000000000a1', null, array[1], 'x')$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: productos nulo');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000205', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], null, 'x')$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: cantidades nulo');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000206', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1', 'aaaaaaaa-6600-4000-8000-0000000000f2']::uuid[], array[1], 'x')$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: arreglos de largo distinto');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000207', 'aaaaaaaa-6600-4000-8000-0000000000a1', '{}'::uuid[], '{}'::integer[], 'x')$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: arreglos vacíos');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000208', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1', null]::uuid[], array[1, 2], 'x')$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: producto nulo en el arreglo');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000209', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[null]::integer[], 'x')$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: cantidad nula en el arreglo');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000210', 'aaaaaaaa-6600-4000-8000-0000000000a1', '{{aaaaaaaa-6600-4000-8000-0000000000f1}}'::uuid[], '{{1}}'::integer[], 'x')$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: arreglos bidimensionales');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000211', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1, 2], 'x')$q$, 'PT400', 'jornada_producto_repetido', 'I13: producto repetido');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000212', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[0], 'x')$q$, 'PT400', 'jornada_cantidad_invalida', 'I13: cantidad 0');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000213', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[-2], 'x')$q$, 'PT400', 'jornada_cantidad_invalida', 'I13: cantidad negativa');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000214', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], '{1.5}'::integer[], 'x')$q$, '22P02', null, 'cantidad fraccionaria: rechazada por el tipo integer antes de la RPC');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000215', 'aaaaaaaa-6600-4000-8000-0000000000a1', array[]::uuid[], array[]::integer[], null)$q$, 'PT400', 'jornada_motivo_invalido', 'precedencia del paso 3: el motivo se valida antes que los arreglos');
reset role;
select ok(pg_temp.igual(), 'I13/I14: ningún rechazo estructural dejó filas ni cambió estados');
select ok(pg_temp.sin_clave('66000000-0000-4000-8000-000000000202') and pg_temp.sin_clave('66000000-0000-4000-8000-000000000206')
          and pg_temp.sin_clave('66000000-0000-4000-8000-000000000211') and pg_temp.sin_clave('66000000-0000-4000-8000-000000000212'),
  'I13: los rechazos estructurales no reservaron la clave');
-- I13: la misma clave con el payload corregido es una primera ejecución (sobre J6).
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000001');
insert into res select 'I13', public.registrar_descarga('66000000-0000-4000-8000-000000000212', 'aaaaaaaa-6600-4000-8000-0000000000a6', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'Devolución');
reset role;
select is((select o.tipo || '/' || o.jornada_id::text from public.operaciones o where o.id = (select v from res where k = 'I13')),
  'descarga/aaaaaaaa-6600-4000-8000-0000000000a6', 'I13: la clave rechazada antes se usa después como primera ejecución');

-- ===========================================================================
-- 4. Primera descarga válida (I1; ADR-007 caso 18)
-- ===========================================================================
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000001');
insert into res select 'D1', public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1',
  array['aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[500, 10], '  Sobrante de carga  ');
reset role;
select is(
  (select o.tipo || '|' || o.jornada_id::text || '|' || o.actor_id::text || '|' || o.empresa_id::text || '|' || o.idempotency_key::text
     from public.operaciones o where o.id = (select v from res where k = 'D1')),
  'descarga|aaaaaaaa-6600-4000-8000-0000000000a1|aaaaaaaa-6600-4000-8000-000000000001|aaaaaaaa-6600-4000-8000-000000000000|66000000-0000-4000-8000-000000000301',
  'I1: la respuesta es la operación descarga, con jornada, actor, empresa y clave');
select is(
  (select o.huella from public.operaciones o where o.id = (select v from res where k = 'D1')),
  pg_temp.huella('v1|descarga|aaaaaaaa-6600-4000-8000-0000000000a1|aaaaaaaa-6600-4000-8000-0000000000f1:10,aaaaaaaa-6600-4000-8000-0000000000f2:500|+Sobrante de carga'),
  'I1: la huella es la v1 canónica (líneas ordenadas y motivo con btrim), recalculada con un texto escrito aparte');
select is(
  (select string_agg(m.tipo_movimiento || ':' || right(m.producto_id::text, 2) || ':' || m.cantidad::text || ':'
                     || right(m.ubicacion_origen_id::text, 2) || '>' || right(m.ubicacion_destino_id::text, 2) || ':'
                     || (m.jornada_id = 'aaaaaaaa-6600-4000-8000-0000000000a1')::text || ':'
                     || coalesce(m.motivo, '-') || ':' || coalesce(m.motivo_codigo, '-'),
                     ',' order by m.producto_id)
     from public.movimientos_stock m where m.operacion_id = (select v from res where k = 'D1')),
  'descarga:f1:10:e1>d1:true:Sobrante de carga:-,descarga:f2:500:e1>d1:true:Sobrante de carga:-',
  'I1 (caso 18): un movimiento descarga por línea, camión de la jornada → depósito, con jornada y el motivo normalizado');
select is((select estado from public.jornadas where id = 'aaaaaaaa-6600-4000-8000-0000000000a1'), 'cargada',
  'la descarga no cambia el estado de la jornada');
select is((select string_agg(m.id::text || ':' || m.cantidad::text, ',' order by m.id) from public.movimientos_stock m
            where m.jornada_id = 'aaaaaaaa-6600-4000-8000-0000000000a1' and m.tipo_movimiento = 'carga'),
  (select h from cargas_j1), 'caso 18: los movimientos de carga originales quedan intactos (compensatoria)');
select is(
  pg_temp.saldo('aaaaaaaa-6600-4000-8000-0000000000e1', 'aaaaaaaa-6600-4000-8000-0000000000f1')::text || '/'
  || pg_temp.saldo('aaaaaaaa-6600-4000-8000-0000000000d1', 'aaaaaaaa-6600-4000-8000-0000000000f1')::text || '/'
  || pg_temp.saldo('aaaaaaaa-6600-4000-8000-0000000000e1', 'aaaaaaaa-6600-4000-8000-0000000000f2')::text || '/'
  || pg_temp.saldo('aaaaaaaa-6600-4000-8000-0000000000d1', 'aaaaaaaa-6600-4000-8000-0000000000f2')::text || '/'
  || pg_temp.neta('aaaaaaaa-6600-4000-8000-0000000000a1', 'aaaaaaaa-6600-4000-8000-0000000000f1')::text,
  '20/62/1500/3500/20',
  'saldos: camión −c y depósito +c (f1: 30 − 10 = 20 y 100 − 49 + 1 + 10 = 62; f2 en gramos); carga neta de f1 en J1 = 20');

-- ===========================================================================
-- 5. Idempotencia (I2, I5, I6, I12)
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000001');
insert into res select 'R1', public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1',
  array['aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[500, 10], '  Sobrante de carga  ');
insert into res select 'R2', public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'AAAAAAAA-6600-4000-8000-0000000000A1',
  array['AAAAAAAA-6600-4000-8000-0000000000F1', 'aaaaaaaa-6600-4000-8000-0000000000f2']::uuid[], array[10, 500], 'Sobrante de carga');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[500, 11], 'Sobrante de carga')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otra cantidad');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f3', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[500, 10], 'Sobrante de carga')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otro producto');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[10], 'Sobrante de carga')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, una línea quitada');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f1', 'aaaaaaaa-6600-4000-8000-0000000000f3']::uuid[], array[500, 10, 1], 'Sobrante de carga')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, una línea agregada');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a6', array['aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[500, 10], 'Sobrante de carga')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otra jornada');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[500, 10], 'Otro motivo')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otro motivo');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[500, 10], 'SOBRANTE DE CARGA')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I12: motivo en mayúsculas = conflicto');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[500, 10], 'Sobrante  de carga')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I12: espacios internos distintos en el motivo = conflicto');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[500, 10], ' ')$q$, 'PT400', 'jornada_motivo_invalido', 'I5: motivo vacío con la clave usada: PT400 antes del replay');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[10, 10], 'Sobrante de carga')$q$, 'PT400', 'jornada_producto_repetido', 'I5: producto repetido con la clave usada: PT400 antes del replay');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', null, array['aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[500, 10], 'Sobrante de carga')$q$, 'PT404', 'jornada_no_encontrada', 'I5: jornada nula con la clave usada: PT404 antes del replay');
reset role;
select is((select v from res where k = 'R1'), (select v from res where k = 'D1'), 'I2: replay idéntico devuelve la misma operación');
select is((select v from res where k = 'R2'), (select v from res where k = 'D1'), 'I12: líneas en otro orden, uuid en mayúsculas y motivo sin espacios laterales = replay');
select ok(pg_temp.igual(), 'I2/I5/I6/I12: sin filas nuevas ni cambios de estado');

-- ===========================================================================
-- 6. Carga neta, saldo y estados (casos 19, 22 y 24; §2.6.3; I9)
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000001');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000401', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[21], 'x')$q$, 'PT409', 'jornada_descarga_excede_carga', 'caso 19: más que la carga neta de la jornada (20): PT409');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000402', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f4']::uuid[], array[1], 'x')$q$, 'PT409', 'jornada_descarga_excede_carga', 'producto nunca cargado en la jornada (carga neta 0): PT409');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000403', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1', 'aaaaaaaa-6600-4000-8000-0000000000f2']::uuid[], array[1, 1501], 'x')$q$, 'PT409', 'jornada_descarga_excede_carga', 'una línea excedida rechaza toda la operación (atómica)');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000404', 'aaaaaaaa-6600-4000-8000-0000000000a3', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT409', 'jornada_estado_invalido', 'caso 19: descarga en abierta: PT409');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000405', 'aaaaaaaa-6600-4000-8000-0000000000a4', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT409', 'jornada_estado_invalido', 'caso 22: descarga en en_reparto: PT409');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000406', 'aaaaaaaa-6600-4000-8000-0000000000a5', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT500', 'jornada_ubicacion_no_configurada', 'camión sin ubicación de stock: PT500');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000407', 'aaaaaaaa-6600-4000-8000-0000000000a3', array['cccccccc-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT409', 'jornada_estado_invalido', 'precedencia: el estado se valida antes que los productos');
reset role;
select ok(pg_temp.igual(), 'casos 19 y 22: los rechazos no dejaron operaciones, movimientos ni cambios de estado');
select ok(pg_temp.sin_clave('66000000-0000-4000-8000-000000000401') and pg_temp.sin_clave('66000000-0000-4000-8000-000000000403')
          and pg_temp.sin_clave('66000000-0000-4000-8000-000000000404'),
  'los rechazos de negocio no reservaron claves');

-- Caso 24: camión dado de baja con jornada cargada: la descarga se admite; la carga no.
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000001');
insert into res select 'D24', public.registrar_descarga('66000000-0000-4000-8000-000000000410', 'aaaaaaaa-6600-4000-8000-0000000000a2', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[3], 'Camión fuera de servicio');
select throws_ok($q$select public.registrar_carga('66000000-0000-4000-8000-000000000411', 'aaaaaaaa-6600-4000-8000-0000000000a2', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT409', 'jornada_camion_inactivo', 'caso 24: con el camión dado de baja la carga sigue rechazada');
-- §2.6.3: producto dado de baja después de cargarlo.
insert into res select 'DI', public.registrar_descarga('66000000-0000-4000-8000-000000000412', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f3']::uuid[], array[5], 'Producto discontinuado');
-- Descarga de todo lo que queda de f1: el camión puede quedar vacío y la jornada sigue cargada.
insert into res select 'DT', public.registrar_descarga('66000000-0000-4000-8000-000000000413', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[20], 'Sin reparto');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000414', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, 'PT409', 'jornada_descarga_excede_carga', 'después de descargar todo, una unidad más se rechaza');
reset role;
select is(
  (select count(*) from public.movimientos_stock where operacion_id = (select v from res where k = 'D24'))::text || '/'
  || pg_temp.saldo('aaaaaaaa-6600-4000-8000-0000000000e2', 'aaaaaaaa-6600-4000-8000-0000000000f1')::text || '/'
  || (select estado from public.jornadas where id = 'aaaaaaaa-6600-4000-8000-0000000000a2'),
  '1/7/cargada', 'caso 24: con el camión dado de baja la descarga se registra (10 − 3 = 7) y la jornada sigue cargada');
select is(
  pg_temp.saldo('aaaaaaaa-6600-4000-8000-0000000000e1', 'aaaaaaaa-6600-4000-8000-0000000000f3')::text || '/'
  || pg_temp.saldo('aaaaaaaa-6600-4000-8000-0000000000d1', 'aaaaaaaa-6600-4000-8000-0000000000f3')::text,
  '0/20', '§2.6.3: el producto dado de baja después de cargarlo se descarga completo y vuelve al depósito');
select is(
  pg_temp.saldo('aaaaaaaa-6600-4000-8000-0000000000e1', 'aaaaaaaa-6600-4000-8000-0000000000f1')::text || '/'
  || pg_temp.neta('aaaaaaaa-6600-4000-8000-0000000000a1', 'aaaaaaaa-6600-4000-8000-0000000000f1')::text || '/'
  || (select estado from public.jornadas where id = 'aaaaaaaa-6600-4000-8000-0000000000a1'),
  '0/0/cargada', 'f1 descargado por completo: camión y carga neta en 0, la jornada sigue cargada (sin transición hacia atrás)');
-- I9: la clave rechazada por exceso, con un payload válido, es una primera ejecución.
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000001');
insert into res select 'I9', public.registrar_descarga('66000000-0000-4000-8000-000000000401', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2']::uuid[], array[100], 'Ajuste');
reset role;
select is((select o.tipo from public.operaciones o where o.id = (select v from res where k = 'I9')), 'descarga',
  'I9: tras un rechazo, la misma clave con payload válido se ejecuta como primera ejecución');

-- ===========================================================================
-- 7. I3, I4, I7 e I8
-- ===========================================================================
-- I3: J6 (con la descarga de I13) pasa a en_reparto; el replay devuelve la misma
-- operación sin revalidar el estado.
update public.jornadas set estado = 'en_reparto' where id = 'aaaaaaaa-6600-4000-8000-0000000000a6';
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000001');
select is(public.registrar_descarga('66000000-0000-4000-8000-000000000212', 'aaaaaaaa-6600-4000-8000-0000000000a6', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[1], 'Devolución'),
  (select v from res where k = 'I13'), 'I3: replay después de en_reparto: la misma operación, sin revalidar estado');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-0000000000c1', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2']::uuid[], array[1], 'x')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una carga');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000001', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2']::uuid[], array[1], 'x')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de un ingreso de Stock');
select throws_ok($q$select public.registrar_carga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2']::uuid[], array[1])$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: registrar_carga con la clave de una descarga');
select throws_ok($q$select public.registrar_merma('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000d1', 1, 'vencido', null)$q$, 'PT409', 'stock_conflicto_idempotencia', 'I7 (regresión): registrar_merma con una clave de descarga sigue respondiendo stock_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I3/I7: sin filas nuevas ni cambios de estado (salvo el fixture)');
-- I8: la misma clave de D1 usada por el encargado es una operación nueva e independiente.
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000002');
insert into res select 'E1', public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2']::uuid[], array[50], 'Encargado');
reset role;
select ok((select v from res where k = 'E1') <> (select v from res where k = 'D1')
          and (select o.actor_id from public.operaciones o where o.id = (select v from res where k = 'E1')) = 'aaaaaaaa-6600-4000-8000-000000000002',
  'I8: la misma clave usada por otro actor (encargado) es una operación nueva e independiente');
-- I4: autorización perdida (el encargado queda inactivo): PT403 antes del replay.
update public.perfiles set activo = false where usuario_id = 'aaaaaaaa-6600-4000-8000-000000000002';
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000002');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2']::uuid[], array[50], 'Encargado')$q$, 'PT403', 'jornada_no_autorizado', 'I4: replay con autorización perdida: PT403');
reset role;
update public.perfiles set activo = true where usuario_id = 'aaaaaaaa-6600-4000-8000-000000000002';

-- ===========================================================================
-- 8. Invariantes finales
-- ===========================================================================
select is(
  (select count(*)::int from public.stock_actual s
    where s.empresa_id = 'aaaaaaaa-6600-4000-8000-000000000000' and s.cantidad < 0),
  0, 'ningún saldo negativo en ninguna ubicación de A');
select is(
  (select count(*)::int from public.jornadas j
    join public.ubicaciones u on u.camion_id = j.camion_id and u.tipo = 'camion'
    cross join (select distinct producto_id from public.movimientos_stock where empresa_id = 'aaaaaaaa-6600-4000-8000-000000000000') p
   where j.empresa_id = 'aaaaaaaa-6600-4000-8000-000000000000' and j.estado <> 'cerrada'
     and pg_temp.saldo(u.id, p.producto_id) <> pg_temp.neta(j.id, p.producto_id)),
  0, 'I-J2: por jornada sin cerrar y producto, saldo del camión = Σ cargas − Σ descargas de la jornada');
select is(
  (select sum(s.cantidad)::text from public.stock_actual s
    where s.empresa_id = 'aaaaaaaa-6600-4000-8000-000000000000' and s.producto_id = 'aaaaaaaa-6600-4000-8000-0000000000f1'),
  '100', 'conservación: depósito + camiones de f1 = 100 ingresadas (cargas y descargas sólo trasladan)');
select is(
  (select count(*)::int from public.movimientos_stock m join public.jornadas j on j.id = m.jornada_id
     join public.ubicaciones o on o.id = m.ubicacion_origen_id
     join public.ubicaciones d on d.id = m.ubicacion_destino_id
    where m.tipo_movimiento = 'descarga'
      and (o.tipo <> 'camion' or o.camion_id <> j.camion_id or d.tipo <> 'deposito' or m.motivo is null or m.motivo <> btrim(m.motivo))),
  0, 'I-CAMION: toda descarga sale del camión de su jornada, entra al depósito y lleva motivo normalizado');
select is(
  (select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.jornadas t
            where t.empresa_id = 'bbbbbbbb-6600-4000-8000-000000000000')
          || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.operaciones t
                      where t.empresa_id = 'bbbbbbbb-6600-4000-8000-000000000000')
          || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.movimientos_stock t
                      where t.empresa_id = 'bbbbbbbb-6600-4000-8000-000000000000')),
  (select h from huella_b), 'aislamiento: jornadas, operaciones y movimientos de B sin cambios');

-- ===========================================================================
-- 9. E-SL1: sólo lectura (GET/HEAD) → 25006 antes de todo, también en replay
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000001');
set local transaction_read_only = on;
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000501', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2']::uuid[], array[1], 'x')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave nueva: 25006');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2', 'aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[500, 10], 'Sobrante de carga')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave usada y misma huella: 25006, no el uuid guardado');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000301', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f1']::uuid[], array[99], 'Otro')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave usada y otra huella: 25006, no PT409');
reset role;
select pg_temp.como_usuario('aaaaaaaa-6600-4000-8000-000000000003');
select throws_ok($q$select public.registrar_descarga('66000000-0000-4000-8000-000000000502', 'aaaaaaaa-6600-4000-8000-0000000000a1', array['aaaaaaaa-6600-4000-8000-0000000000f2']::uuid[], array[1], 'x')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura con vendedor_piloto: 25006, no PT403 (la guarda precede a la autorización)');
reset role;
select ok(pg_temp.igual() and pg_temp.sin_clave('66000000-0000-4000-8000-000000000501'), 'E-SL1: el rechazo por sólo lectura no reserva la clave ni deja efectos');

select * from finish();

rollback;
