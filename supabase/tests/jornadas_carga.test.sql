-- pgTAP: T5 — RPC registrar_carga (Blueprint §7.2, §7.4, §7.5, §9 y §12; ADR-007 §2.2,
-- §2.5, §2.7 y §7 casos 4, 13 a 17, 22 y 24; ADR-005 D-R2; ADR-001 §18.4.2 a §18.4.9,
-- grupos S e I, y E-SL1 §18.4.16). Ejecutar sólo en local.
--
-- B es un fixture adversarial (aislamiento por empresa_id). La concurrencia (I10,
-- I11 y K8 de carga) NO se prueba acá: está en supabase/tests/concurrencia/casos.sh.
-- Las jornadas de fixture se insertan como owner (con su operación de apertura): el
-- estado en_reparto (casos 22 e I3) es un fixture controlado porque confirmar_salida
-- todavía no existe; se repite con el flujo real en T7.
-- Los objetos pg_temp adversariales y la guardia estática (P7 global) para esta RPC
-- están en pg_temp_jornadas.test.sql. El bloque de sólo lectura (E-SL1) va al final:
-- después de SET transaction_read_only = on la transacción ya no vuelve a escritura.

begin;

create extension if not exists pgtap with schema extensions;

select plan(82);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-5500-4000-8000-000000000000', 'Empresa A (test T5)'),
  ('bbbbbbbb-5500-4000-8000-000000000000', 'Empresa B (test T5)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-5500-4000-8000-000000000001', 'authenticated', 'authenticated', 'jc.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-5500-4000-8000-000000000002', 'authenticated', 'authenticated', 'jc.a2@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-5500-4000-8000-000000000003', 'authenticated', 'authenticated', 'jc.a3@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-5500-4000-8000-000000000004', 'authenticated', 'authenticated', 'jc.a4@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-5500-4000-8000-000000000005', 'authenticated', 'authenticated', 'jc.a5@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-5500-4000-8000-000000000006', 'authenticated', 'authenticated', 'jc.a6@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-5500-4000-8000-000000000007', 'authenticated', 'authenticated', 'jc.a7@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-5500-4000-8000-000000000001', 'authenticated', 'authenticated', 'jc.b1@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-5500-4000-8000-000000000002', 'authenticated', 'authenticated', 'jc.b2@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-5500-4000-8000-000000000001', 'authenticated', 'authenticated', 'jc.n1@usuarios.distribuidora.invalid', '{"rol":"dueno","empresa_id":"aaaaaaaa-5500-4000-8000-000000000000"}');

-- A: dueño (1), encargado (2), vendedores (3, 5, 6, 7), dueño inactivo (4).
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-5500-4000-8000-000000000001', 'aaaaaaaa-5500-4000-8000-000000000000', 'jc.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-5500-4000-8000-000000000002', 'aaaaaaaa-5500-4000-8000-000000000000', 'jc.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-5500-4000-8000-000000000003', 'aaaaaaaa-5500-4000-8000-000000000000', 'jc.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-5500-4000-8000-000000000004', 'aaaaaaaa-5500-4000-8000-000000000000', 'jc.a4', 'A4', 'dueno', false),
  ('aaaaaaaa-5500-4000-8000-000000000005', 'aaaaaaaa-5500-4000-8000-000000000000', 'jc.a5', 'A5', 'vendedor_piloto', true),
  ('aaaaaaaa-5500-4000-8000-000000000006', 'aaaaaaaa-5500-4000-8000-000000000000', 'jc.a6', 'A6', 'vendedor_piloto', true),
  ('aaaaaaaa-5500-4000-8000-000000000007', 'aaaaaaaa-5500-4000-8000-000000000000', 'jc.a7', 'A7', 'vendedor_piloto', true),
  ('bbbbbbbb-5500-4000-8000-000000000001', 'bbbbbbbb-5500-4000-8000-000000000000', 'jc.b1', 'B1', 'dueno', true),
  ('bbbbbbbb-5500-4000-8000-000000000002', 'bbbbbbbb-5500-4000-8000-000000000000', 'jc.b2', 'B2', 'vendedor_piloto', true);

-- Camiones: c1 (cargas normales), c2 (stock residual), c3 (se da de baja), c4
-- (jornada en_reparto), c5 (sin ubicación configurada), c6 (jornada para I3 y
-- cuarentena). B: un camión.
insert into public.camiones (id, empresa_id, patente, nombre, activo, creado_por) values
  ('aaaaaaaa-5500-4000-8000-0000000000c1', 'aaaaaaaa-5500-4000-8000-000000000000', 'JC-01', 'Camión A1', true, 'aaaaaaaa-5500-4000-8000-000000000001'),
  ('aaaaaaaa-5500-4000-8000-0000000000c2', 'aaaaaaaa-5500-4000-8000-000000000000', 'JC-02', 'Camión A2', true, 'aaaaaaaa-5500-4000-8000-000000000001'),
  ('aaaaaaaa-5500-4000-8000-0000000000c3', 'aaaaaaaa-5500-4000-8000-000000000000', 'JC-03', 'Camión A3', true, 'aaaaaaaa-5500-4000-8000-000000000001'),
  ('aaaaaaaa-5500-4000-8000-0000000000c4', 'aaaaaaaa-5500-4000-8000-000000000000', 'JC-04', 'Camión A4', true, 'aaaaaaaa-5500-4000-8000-000000000001'),
  ('aaaaaaaa-5500-4000-8000-0000000000c5', 'aaaaaaaa-5500-4000-8000-000000000000', 'JC-05', 'Camión A5', true, 'aaaaaaaa-5500-4000-8000-000000000001'),
  ('aaaaaaaa-5500-4000-8000-0000000000c6', 'aaaaaaaa-5500-4000-8000-000000000000', 'JC-06', 'Camión A6', true, 'aaaaaaaa-5500-4000-8000-000000000001'),
  ('bbbbbbbb-5500-4000-8000-0000000000c1', 'bbbbbbbb-5500-4000-8000-000000000000', 'JC-B1', 'Camión B1', true, 'bbbbbbbb-5500-4000-8000-000000000001');

insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('aaaaaaaa-5500-4000-8000-0000000000d1', 'aaaaaaaa-5500-4000-8000-000000000000', 'deposito', null),
  ('aaaaaaaa-5500-4000-8000-0000000000d2', 'aaaaaaaa-5500-4000-8000-000000000000', 'cuarentena', null),
  ('aaaaaaaa-5500-4000-8000-0000000000e1', 'aaaaaaaa-5500-4000-8000-000000000000', 'camion', 'aaaaaaaa-5500-4000-8000-0000000000c1'),
  ('aaaaaaaa-5500-4000-8000-0000000000e2', 'aaaaaaaa-5500-4000-8000-000000000000', 'camion', 'aaaaaaaa-5500-4000-8000-0000000000c2'),
  ('aaaaaaaa-5500-4000-8000-0000000000e3', 'aaaaaaaa-5500-4000-8000-000000000000', 'camion', 'aaaaaaaa-5500-4000-8000-0000000000c3'),
  ('aaaaaaaa-5500-4000-8000-0000000000e4', 'aaaaaaaa-5500-4000-8000-000000000000', 'camion', 'aaaaaaaa-5500-4000-8000-0000000000c4'),
  ('aaaaaaaa-5500-4000-8000-0000000000e6', 'aaaaaaaa-5500-4000-8000-000000000000', 'camion', 'aaaaaaaa-5500-4000-8000-0000000000c6'),
  ('bbbbbbbb-5500-4000-8000-0000000000d1', 'bbbbbbbb-5500-4000-8000-000000000000', 'deposito', null),
  ('bbbbbbbb-5500-4000-8000-0000000000e1', 'bbbbbbbb-5500-4000-8000-000000000000', 'camion', 'bbbbbbbb-5500-4000-8000-0000000000c1');

-- Productos de A: f1 unidad, f2 fiambre por peso (gramos), f3 (se da de baja), f4
-- (sólo en cuarentena). B: un producto.
insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('aaaaaaaa-5500-4000-8000-0000000000f1', 'aaaaaaaa-5500-4000-8000-000000000000', 'JC-U', 'Leche A', 'lacteos', 'unidad', 100, true, 'aaaaaaaa-5500-4000-8000-000000000001'),
  ('aaaaaaaa-5500-4000-8000-0000000000f2', 'aaaaaaaa-5500-4000-8000-000000000000', 'JC-P', 'Jamón A', 'fiambres', 'peso', 9000, true, 'aaaaaaaa-5500-4000-8000-000000000001'),
  ('aaaaaaaa-5500-4000-8000-0000000000f3', 'aaaaaaaa-5500-4000-8000-000000000000', 'JC-I', 'Queso A', 'lacteos', 'unidad', 100, true, 'aaaaaaaa-5500-4000-8000-000000000001'),
  ('aaaaaaaa-5500-4000-8000-0000000000f4', 'aaaaaaaa-5500-4000-8000-000000000000', 'JC-Q', 'Yogur A', 'lacteos', 'unidad', 100, true, 'aaaaaaaa-5500-4000-8000-000000000001'),
  ('bbbbbbbb-5500-4000-8000-0000000000f1', 'bbbbbbbb-5500-4000-8000-000000000000', 'JC-B', 'Leche B', 'lacteos', 'unidad', 100, true, 'bbbbbbbb-5500-4000-8000-000000000001');

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
  values (j, 'aaaaaaaa-5500-4000-8000-000000000000', 'aaaaaaaa-5500-4000-8000-000000000001',
          'apertura_jornada', j, repeat('a', 64));
  insert into public.jornadas (id, empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
  values (j, 'aaaaaaaa-5500-4000-8000-000000000000', fecha, camion, vendedor, estado,
          'aaaaaaaa-5500-4000-8000-000000000001', j);
$$;

-- Saldo de una ubicación por producto, leído como owner desde cualquier rol.
create function pg_temp.saldo(ubicacion uuid, producto uuid)
returns bigint language sql security definer set search_path = '' as $$
  select coalesce(sum(case when m.ubicacion_destino_id = ubicacion then m.cantidad::bigint
                           else -m.cantidad::bigint end), 0)
    from public.movimientos_stock m
   where m.producto_id = producto
     and (m.ubicacion_destino_id = ubicacion or m.ubicacion_origen_id = ubicacion)
$$;

-- Conteo global de filas que una carga puede tocar, y estado de las jornadas de A.
create function pg_temp.conteo()
returns text language sql security definer set search_path = '' as $$
  select (select count(*) from public.operaciones)::text
    || '|' || (select count(*) from public.movimientos_stock)::text
    || '|' || (select count(*) from public.jornadas)::text
    || '|' || (select string_agg(j.id::text || '=' || j.estado, ',' order by j.id)
                 from public.jornadas j where j.empresa_id = 'aaaaaaaa-5500-4000-8000-000000000000')
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
  pg_temp.como_service_role(), pg_temp.saldo(uuid, uuid), pg_temp.conteo(), pg_temp.fijar(),
  pg_temp.igual(), pg_temp.sin_clave(uuid), pg_temp.huella(text) to public;

create temp table res (k text primary key, v uuid);
grant select, insert on res to public;

-- Jornadas: J1 (c1, abierta: cargas normales), J2 (c2 con stock residual, abierta),
-- J3 (c3, abierta; el camión se da de baja), J4 (c4, en_reparto), J5 (c5 sin
-- ubicación, abierta), J6 (c6, abierta: I3), JB (de B, como owner de B).
select pg_temp.jornada('aaaaaaaa-5500-4000-8000-0000000000a1', 'aaaaaaaa-5500-4000-8000-0000000000c1', date '2999-05-01', 'aaaaaaaa-5500-4000-8000-000000000003', 'abierta');
select pg_temp.jornada('aaaaaaaa-5500-4000-8000-0000000000a0', 'aaaaaaaa-5500-4000-8000-0000000000c2', date '2999-04-30', 'aaaaaaaa-5500-4000-8000-000000000005', 'abierta');
select pg_temp.jornada('aaaaaaaa-5500-4000-8000-0000000000a3', 'aaaaaaaa-5500-4000-8000-0000000000c3', date '2999-05-01', 'aaaaaaaa-5500-4000-8000-000000000006', 'abierta');
select pg_temp.jornada('aaaaaaaa-5500-4000-8000-0000000000a4', 'aaaaaaaa-5500-4000-8000-0000000000c4', date '2999-05-01', 'aaaaaaaa-5500-4000-8000-000000000007', 'en_reparto');
select pg_temp.jornada('aaaaaaaa-5500-4000-8000-0000000000a5', 'aaaaaaaa-5500-4000-8000-0000000000c5', date '2999-05-01', 'aaaaaaaa-5500-4000-8000-000000000001', 'abierta');
select pg_temp.jornada('aaaaaaaa-5500-4000-8000-0000000000a6', 'aaaaaaaa-5500-4000-8000-0000000000c6', date '2999-05-01', 'aaaaaaaa-5500-4000-8000-000000000002', 'abierta');
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella) values
  ('bbbbbbbb-5500-4000-8000-0000000000a1', 'bbbbbbbb-5500-4000-8000-000000000000', 'bbbbbbbb-5500-4000-8000-000000000001',
   'apertura_jornada', 'bbbbbbbb-5500-4000-8000-0000000000a1', repeat('b', 64));
insert into public.jornadas (id, empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id) values
  ('bbbbbbbb-5500-4000-8000-0000000000a1', 'bbbbbbbb-5500-4000-8000-000000000000', date '2999-05-01',
   'bbbbbbbb-5500-4000-8000-0000000000c1', 'bbbbbbbb-5500-4000-8000-000000000002', 'abierta',
   'bbbbbbbb-5500-4000-8000-000000000001', 'bbbbbbbb-5500-4000-8000-0000000000a1');

-- Stock inicial por las RPC de Stock (dueño de A y de B): depósito de A con 100 u de
-- f1, 5000 g de f2, 20 u de f3 y 8 u de f4 (que se mueven a cuarentena); B con 50 u.
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
select public.registrar_ingreso('55000000-0000-4000-8000-000000000001', 'aaaaaaaa-5500-4000-8000-0000000000f1', 100, 'Remito T5');
select public.registrar_ingreso('55000000-0000-4000-8000-000000000002', 'aaaaaaaa-5500-4000-8000-0000000000f2', 5000, 'Remito T5');
select public.registrar_ingreso('55000000-0000-4000-8000-000000000003', 'aaaaaaaa-5500-4000-8000-0000000000f3', 20, 'Remito T5');
select public.registrar_ingreso('55000000-0000-4000-8000-000000000004', 'aaaaaaaa-5500-4000-8000-0000000000f4', 8, 'Remito T5');
select public.mover_a_cuarentena('55000000-0000-4000-8000-000000000005', 'aaaaaaaa-5500-4000-8000-0000000000f4', 'aaaaaaaa-5500-4000-8000-0000000000d1', 8, 'Golpeado');
reset role;
select pg_temp.como_usuario('bbbbbbbb-5500-4000-8000-000000000001');
select public.registrar_ingreso('55000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-5500-4000-8000-0000000000f1', 50, 'Remito B');
reset role;

-- Stock residual en c2: una carga en J0 (c2), que después se cierra como owner, y
-- una jornada nueva J2 en c2.
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
select public.registrar_carga('55000000-0000-4000-8000-0000000000c0', 'aaaaaaaa-5500-4000-8000-0000000000a0',
  array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[3]);
reset role;
update public.jornadas set estado = 'cerrada' where id = 'aaaaaaaa-5500-4000-8000-0000000000a0';
select pg_temp.jornada('aaaaaaaa-5500-4000-8000-0000000000a2', 'aaaaaaaa-5500-4000-8000-0000000000c2', date '2999-05-01', 'aaaaaaaa-5500-4000-8000-000000000005', 'abierta');

-- Huella de B antes de las pruebas.
create temp table huella_b as
select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.jornadas t
         where t.empresa_id = 'bbbbbbbb-5500-4000-8000-000000000000')
       || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.operaciones t
                   where t.empresa_id = 'bbbbbbbb-5500-4000-8000-000000000000')
       || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.movimientos_stock t
                   where t.empresa_id = 'bbbbbbbb-5500-4000-8000-000000000000') as h;

-- ===========================================================================
-- 1. Catálogo (S): dos funciones, Topología D, ACL, sin sobrecargas
-- ===========================================================================
select is(
  (select count(*)::int from pg_proc where proname = 'registrar_carga'),
  2, 'registrar_carga: exactamente dos funciones (fachada e implementación), sin sobrecargas');
select ok(
  (select p.prosecdef and p.provolatile = 'v' and p.proowner = 'propietario_rpc'::regrole
          and p.proconfig = array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']
     from pg_proc p where p.oid = 'privado.registrar_carga(uuid,uuid,uuid[],integer[])'::regprocedure),
  'implementación: SECURITY DEFINER, VOLATILE, owner propietario_rpc, search_path vacío, ACL exacta');
select ok(
  (select not p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole
          and p.proconfig = array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/postgres', 'postgres=X/postgres']
          and p.prosrc !~* 'insert|update|delete'
     from pg_proc p where p.oid = 'public.registrar_carga(uuid,uuid,uuid[],integer[])'::regprocedure),
  'fachada: SECURITY INVOKER, owner postgres, search_path vacío, ACL exacta, sólo delega');
select ok(
  not has_function_privilege('anon', 'public.registrar_carga(uuid,uuid,uuid[],integer[])', 'execute')
  and not has_function_privilege('service_role', 'public.registrar_carga(uuid,uuid,uuid[],integer[])', 'execute')
  and not has_function_privilege('anon', 'privado.registrar_carga(uuid,uuid,uuid[],integer[])', 'execute')
  and not has_function_privilege('service_role', 'privado.registrar_carga(uuid,uuid,uuid[],integer[])', 'execute')
  and not has_schema_privilege('propietario_rpc', 'privado', 'create'),
  'P11: anon y service_role sin EXECUTE; propietario_rpc sin CREATE residual');
select ok(
  (select prosrc from pg_proc where oid = 'privado.registrar_carga(uuid,uuid,uuid[],integer[])'::regprocedure)
    ~ E'\\nbegin\\n  -- Paso 0 \\(E-SL1',
  'E-SL1: la guarda de sólo lectura es la primera sentencia');

-- ===========================================================================
-- 2. Seguridad (S): anon, service_role, sin sub, sin perfil, inactivo, vendedor, B
-- ===========================================================================
select pg_temp.como_anon();
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000100', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, '42501', null, 'anon no puede ejecutar la fachada');
reset role;
select pg_temp.como_anon();
select throws_ok($q$select privado.registrar_carga('55000000-0000-4000-8000-000000000100', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, '42501', null, 'anon no puede ejecutar la implementación');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000100', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, '42501', null, 'service_role no puede ejecutar la fachada');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select privado.registrar_carga('55000000-0000-4000-8000-000000000100', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, '42501', null, 'service_role no puede ejecutar la implementación');
reset role;

select pg_temp.fijar();
select pg_temp.sin_sub();
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000101', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT401', 'jornada_no_autenticado', 'sin sub: PT401');
reset role;
select pg_temp.como_usuario('dddddddd-5500-4000-8000-000000000001');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000102', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT403', 'jornada_no_autorizado', 'cuenta sin perfil (con metadata de dueño de A): PT403');
reset role;
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000004');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000103', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT403', 'jornada_no_autorizado', 'dueño inactivo: PT403');
reset role;
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000003');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000104', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT403', 'jornada_no_autorizado', 'vendedor_piloto (asignado a la jornada): PT403');
reset role;
select pg_temp.como_usuario('bbbbbbbb-5500-4000-8000-000000000001');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000105', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['bbbbbbbb-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT404', 'jornada_no_encontrada', 'dueño de B con la jornada de A: PT404, igual que inexistente');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000106', 'cccccccc-5500-4000-8000-0000000000a1', array['bbbbbbbb-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT404', 'jornada_no_encontrada', 'jornada inexistente: PT404');
reset role;
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000107', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['bbbbbbbb-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT404', 'jornada_producto_no_encontrado', 'producto de otra empresa: PT404');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000108', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['cccccccc-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT404', 'jornada_producto_no_encontrado', 'producto inexistente: el mismo PT404');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000109', 'bbbbbbbb-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT404', 'jornada_no_encontrada', 'dueño de A con la jornada de B: PT404');
select throws_ok($q$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id) values ('aaaaaaaa-5500-4000-8000-000000000000', 'aaaaaaaa-5500-4000-8000-0000000000a1', 'carga', 'aaaaaaaa-5500-4000-8000-0000000000f1', 1, 'aaaaaaaa-5500-4000-8000-0000000000d1', 'aaaaaaaa-5500-4000-8000-0000000000e1', 'aaaaaaaa-5500-4000-8000-000000000001', 'aaaaaaaa-5500-4000-8000-0000000000a1')$q$, '42501', null, 'DML directo de authenticated sobre el ledger: 42501');
select throws_ok($q$update public.jornadas set estado = 'cargada' where id = 'aaaaaaaa-5500-4000-8000-0000000000a1'$q$, '42501', null, 'UPDATE directo de authenticated sobre jornadas: 42501');
reset role;
select ok(pg_temp.igual(), 'los rechazos de seguridad no dejaron filas nuevas ni cambiaron estados');
select ok(pg_temp.sin_clave('55000000-0000-4000-8000-000000000101') and pg_temp.sin_clave('55000000-0000-4000-8000-000000000105')
          and pg_temp.sin_clave('55000000-0000-4000-8000-000000000107'),
  'los rechazos de seguridad no reservaron claves');

-- ===========================================================================
-- 3. Estructura (paso 3; I5, I13 e I14)
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
select throws_ok($q$select public.registrar_carga(null, 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT400', 'jornada_clave_invalida', 'I14: clave nula');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000201', null, array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT404', 'jornada_no_encontrada', 'I13: jornada nula (D-N1)');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000202', 'aaaaaaaa-5500-4000-8000-0000000000a1', null, array[1])$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: productos nulo');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000203', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], null)$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: cantidades nulo');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000204', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1', 'aaaaaaaa-5500-4000-8000-0000000000f2']::uuid[], array[1])$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: arreglos de largo distinto');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000205', 'aaaaaaaa-5500-4000-8000-0000000000a1', '{}'::uuid[], '{}'::integer[])$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: arreglos vacíos');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000206', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1', null]::uuid[], array[1, 2])$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: producto nulo en el arreglo');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000207', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[null]::integer[])$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: cantidad nula en el arreglo');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000208', 'aaaaaaaa-5500-4000-8000-0000000000a1', '{{aaaaaaaa-5500-4000-8000-0000000000f1}}'::uuid[], '{{1}}'::integer[])$q$, 'PT400', 'jornada_lineas_invalidas', 'I13: arreglos bidimensionales');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000209', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1', 'aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1, 2])$q$, 'PT400', 'jornada_producto_repetido', 'I13: producto repetido');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000210', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[0])$q$, 'PT400', 'jornada_cantidad_invalida', 'I13: cantidad 0');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000211', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[-3])$q$, 'PT400', 'jornada_cantidad_invalida', 'I13: cantidad negativa');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000212', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], '{1.5}'::integer[])$q$, '22P02', null, 'cantidad fraccionaria: rechazada por el tipo integer antes de la RPC (ADR-007 caso 16)');
reset role;
select ok(pg_temp.igual(), 'I13/I14: ningún rechazo estructural dejó filas ni cambió estados');
select ok(pg_temp.sin_clave('55000000-0000-4000-8000-000000000201') and pg_temp.sin_clave('55000000-0000-4000-8000-000000000204')
          and pg_temp.sin_clave('55000000-0000-4000-8000-000000000209') and pg_temp.sin_clave('55000000-0000-4000-8000-000000000210'),
  'I13: los rechazos estructurales no reservaron la clave');
-- I13: la misma clave con el payload corregido se ejecuta como primera ejecución
-- (sobre J6, para no consumir la primera carga de J1).
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
insert into res select 'I13', public.registrar_carga('55000000-0000-4000-8000-000000000210', 'aaaaaaaa-5500-4000-8000-0000000000a6', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1]);
reset role;
select is((select o.tipo || '/' || o.jornada_id::text from public.operaciones o where o.id = (select v from res where k = 'I13')),
  'carga/aaaaaaaa-5500-4000-8000-0000000000a6', 'I13: la clave rechazada antes se usa después como primera ejecución');

-- ===========================================================================
-- 4. Primera carga válida (I1; ADR-007 casos 13 y 17)
-- ===========================================================================
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
insert into res select 'C1', public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1',
  array['aaaaaaaa-5500-4000-8000-0000000000f2', 'aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1250, 10]);
reset role;
select is(
  (select o.tipo || '|' || o.jornada_id::text || '|' || o.actor_id::text || '|' || o.empresa_id::text || '|' || o.idempotency_key::text
     from public.operaciones o where o.id = (select v from res where k = 'C1')),
  'carga|aaaaaaaa-5500-4000-8000-0000000000a1|aaaaaaaa-5500-4000-8000-000000000001|aaaaaaaa-5500-4000-8000-000000000000|55000000-0000-4000-8000-000000000301',
  'I1: la respuesta es la operación carga, con jornada, actor, empresa y clave');
select is(
  (select o.huella from public.operaciones o where o.id = (select v from res where k = 'C1')),
  pg_temp.huella('v1|carga|aaaaaaaa-5500-4000-8000-0000000000a1|aaaaaaaa-5500-4000-8000-0000000000f1:10,aaaaaaaa-5500-4000-8000-0000000000f2:1250'),
  'I1: la huella es la v1 canónica (líneas ordenadas por el uuid del producto), recalculada con un texto escrito aparte');
select is(
  (select string_agg(m.tipo_movimiento || ':' || right(m.producto_id::text, 2) || ':' || m.cantidad::text || ':'
                     || right(m.ubicacion_origen_id::text, 2) || '>' || right(m.ubicacion_destino_id::text, 2) || ':'
                     || (m.jornada_id = 'aaaaaaaa-5500-4000-8000-0000000000a1')::text || ':'
                     || coalesce(m.motivo, '-') || ':' || coalesce(m.motivo_codigo, '-') || ':'
                     || (m.actor_id = 'aaaaaaaa-5500-4000-8000-000000000001')::text,
                     ',' order by m.producto_id)
     from public.movimientos_stock m where m.operacion_id = (select v from res where k = 'C1')),
  'carga:f1:10:d1>e1:true:-:-:true,carga:f2:1250:d1>e1:true:-:-:true',
  'I1 (caso 13): un movimiento carga por línea, depósito → camión de la jornada, con jornada, sin motivo');
select is((select estado from public.jornadas where id = 'aaaaaaaa-5500-4000-8000-0000000000a1'), 'cargada',
  'caso 13: la primera carga lleva la jornada de abierta a cargada');
select is(
  pg_temp.saldo('aaaaaaaa-5500-4000-8000-0000000000d1', 'aaaaaaaa-5500-4000-8000-0000000000f1')::text || '/'
  || pg_temp.saldo('aaaaaaaa-5500-4000-8000-0000000000e1', 'aaaaaaaa-5500-4000-8000-0000000000f1')::text || '/'
  || pg_temp.saldo('aaaaaaaa-5500-4000-8000-0000000000d1', 'aaaaaaaa-5500-4000-8000-0000000000f2')::text || '/'
  || pg_temp.saldo('aaaaaaaa-5500-4000-8000-0000000000e1', 'aaaaaaaa-5500-4000-8000-0000000000f2')::text,
  '86/10/3750/1250',
  'saldos: depósito −c y camión +c (f1: 100 − 3 de J0 − 1 de I13 − 10; f2: 1,250 kg = 1250 g en ambos lados, caso 17)');

-- ===========================================================================
-- 5. Idempotencia (I2, I6, I12)
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
insert into res select 'R1', public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1',
  array['aaaaaaaa-5500-4000-8000-0000000000f2', 'aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1250, 10]);
insert into res select 'R2', public.registrar_carga('55000000-0000-4000-8000-000000000301', 'AAAAAAAA-5500-4000-8000-0000000000A1',
  array['AAAAAAAA-5500-4000-8000-0000000000F1', 'aaaaaaaa-5500-4000-8000-0000000000f2']::uuid[], array[10, 1250]);
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f2', 'aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1250, 11])$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otra cantidad');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f3', 'aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1250, 10])$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otro producto');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[10])$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, una línea quitada');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f2', 'aaaaaaaa-5500-4000-8000-0000000000f1', 'aaaaaaaa-5500-4000-8000-0000000000f3']::uuid[], array[1250, 10, 1])$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, una línea agregada');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a6', array['aaaaaaaa-5500-4000-8000-0000000000f2', 'aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1250, 10])$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otra jornada');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1', 'aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[10, 10])$q$, 'PT400', 'jornada_producto_repetido', 'I5/I12: producto repetido con la clave usada: PT400 antes del replay');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[10, 1250])$q$, 'PT400', 'jornada_lineas_invalidas', 'I5/I12: largo distinto con la clave usada: PT400 antes del replay');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f2', 'aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1250, 0])$q$, 'PT400', 'jornada_cantidad_invalida', 'I5: cantidad 0 con la clave usada: PT400 antes del replay');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', null, array['aaaaaaaa-5500-4000-8000-0000000000f2', 'aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1250, 10])$q$, 'PT404', 'jornada_no_encontrada', 'I5: jornada nula con la clave usada: PT404 antes del replay');
reset role;
select is((select v from res where k = 'R1'), (select v from res where k = 'C1'), 'I2: replay idéntico devuelve la misma operación');
select is((select v from res where k = 'R2'), (select v from res where k = 'C1'), 'I12: mismas líneas en otro orden y uuid en mayúsculas = replay');
select ok(pg_temp.igual(), 'I2/I6/I12: sin filas nuevas ni cambios de estado');

-- ===========================================================================
-- 6. Carga posterior (caso 14), I8 y otros actores
-- ===========================================================================
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000002');
insert into res select 'C2', public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1',
  array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[5]);
reset role;
select ok((select v from res where k = 'C2') <> (select v from res where k = 'C1')
          and (select o.actor_id from public.operaciones o where o.id = (select v from res where k = 'C2')) = 'aaaaaaaa-5500-4000-8000-000000000002',
  'I8: la misma clave usada por otro actor (encargado) es una operación nueva e independiente');
select is(
  (select estado from public.jornadas where id = 'aaaaaaaa-5500-4000-8000-0000000000a1') || '/'
  || pg_temp.saldo('aaaaaaaa-5500-4000-8000-0000000000e1', 'aaaaaaaa-5500-4000-8000-0000000000f1')::text || '/'
  || (select count(*) from public.operaciones where jornada_id = 'aaaaaaaa-5500-4000-8000-0000000000a1' and tipo = 'carga')::text,
  'cargada/15/2',
  'caso 14: la carga posterior (encargado) no cambia el estado ni repite la comprobación de residual; el camión suma 15');

-- ===========================================================================
-- 7. Rechazos de negocio sin efectos (casos 4, 15, 16, 22, 24; I9)
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000401', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[82])$q$, 'PT409', 'jornada_stock_insuficiente', 'caso 16: más que el saldo del depósito (81): PT409');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000402', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f4']::uuid[], array[1])$q$, 'PT409', 'jornada_stock_insuficiente', 'caso 16: mercadería en cuarentena (depósito en 0): PT409');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000403', 'aaaaaaaa-5500-4000-8000-0000000000a2', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT409', 'jornada_stock_residual', 'caso 15: primera carga con stock residual en el camión: PT409');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000404', 'aaaaaaaa-5500-4000-8000-0000000000a4', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT409', 'jornada_estado_invalido', 'caso 22: carga en en_reparto: PT409');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000405', 'aaaaaaaa-5500-4000-8000-0000000000a5', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT500', 'jornada_ubicacion_no_configurada', 'camión sin ubicación de stock: PT500');
reset role;
update public.productos set activo = false where id = 'aaaaaaaa-5500-4000-8000-0000000000f3';
update public.camiones set activo = false where id = 'aaaaaaaa-5500-4000-8000-0000000000c3';
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000406', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1', 'aaaaaaaa-5500-4000-8000-0000000000f3']::uuid[], array[1, 1])$q$, 'PT409', 'jornada_producto_inactivo', 'caso 16: producto inactivo (aunque tenga saldo): PT409');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000407', 'aaaaaaaa-5500-4000-8000-0000000000a3', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT409', 'jornada_camion_inactivo', 'casos 4 y 24: carga con el camión dado de baja: PT409');
reset role;
select ok(pg_temp.igual(), 'casos 4, 15, 16, 22 y 24: los rechazos no dejaron operaciones, movimientos ni cambios de estado');
select ok(pg_temp.sin_clave('55000000-0000-4000-8000-000000000401') and pg_temp.sin_clave('55000000-0000-4000-8000-000000000403')
          and pg_temp.sin_clave('55000000-0000-4000-8000-000000000406'),
  'los rechazos de negocio no reservaron claves');
-- I9: la clave del rechazo por saldo, con un payload válido, es una primera ejecución.
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
insert into res select 'I9', public.registrar_carga('55000000-0000-4000-8000-000000000401', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[81]);
reset role;
select is(
  pg_temp.saldo('aaaaaaaa-5500-4000-8000-0000000000d1', 'aaaaaaaa-5500-4000-8000-0000000000f1')::text || '/'
  || (select count(*) from public.movimientos_stock where operacion_id = (select v from res where k = 'I9'))::text,
  '0/1',
  'I9: tras un rechazo, la misma clave con payload válido se ejecuta; el depósito llega exactamente a 0, nunca negativo');
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000408', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT409', 'jornada_stock_insuficiente', 'depósito en 0: una unidad más se rechaza');
reset role;

-- ===========================================================================
-- 8. I3, I4 e I7
-- ===========================================================================
-- I3: la jornada J6 pasa a en_reparto (fixture como owner); el replay de su carga
-- devuelve la misma operación sin revalidar el estado.
update public.jornadas set estado = 'en_reparto' where id = 'aaaaaaaa-5500-4000-8000-0000000000a6';
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
select is(public.registrar_carga('55000000-0000-4000-8000-000000000210', 'aaaaaaaa-5500-4000-8000-0000000000a6', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1]),
  (select v from res where k = 'I13'), 'I3: replay después de en_reparto: la misma operación, sin revalidar estado');
-- I7: claves de otros tipos (ingreso y a_cuarentena de Stock, apertura de jornada).
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000001', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f2']::uuid[], array[1])$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de un ingreso de Stock');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000005', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f2']::uuid[], array[1])$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de un a_cuarentena de Stock');
-- Regresión de Stock: registrar_merma con la clave de una carga responde su propio código.
select throws_ok($q$select public.registrar_merma('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000f2', 'aaaaaaaa-5500-4000-8000-0000000000d1', 1, 'vencido', null)$q$, 'PT409', 'stock_conflicto_idempotencia', 'I7 (regresión): registrar_merma con una clave de carga sigue respondiendo stock_conflicto_idempotencia');
reset role;
-- I4: autorización perdida (el encargado queda inactivo): PT403 antes del replay.
update public.perfiles set activo = false where usuario_id = 'aaaaaaaa-5500-4000-8000-000000000002';
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000002');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[5])$q$, 'PT403', 'jornada_no_autorizado', 'I4: replay con autorización perdida: PT403');
reset role;
update public.perfiles set activo = true where usuario_id = 'aaaaaaaa-5500-4000-8000-000000000002';
select ok(pg_temp.igual(), 'I3/I4/I7: sin filas nuevas ni cambios de estado (salvo el fixture)');

-- ===========================================================================
-- 10. Invariantes finales
-- ===========================================================================
select is(
  (select count(*)::int from public.stock_actual s
    where s.empresa_id = 'aaaaaaaa-5500-4000-8000-000000000000' and s.cantidad < 0),
  0, 'ningún saldo negativo en ninguna ubicación de A');
select is(
  (select count(*)::int from public.movimientos_stock m join public.jornadas j on j.id = m.jornada_id
     join public.ubicaciones u on u.id = m.ubicacion_destino_id
    where m.tipo_movimiento = 'carga' and (u.tipo <> 'camion' or u.camion_id <> j.camion_id)),
  0, 'I-CAMION: toda carga tiene por destino la ubicación del camión de su jornada');
select is(
  (select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.jornadas t
            where t.empresa_id = 'bbbbbbbb-5500-4000-8000-000000000000')
          || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.operaciones t
                      where t.empresa_id = 'bbbbbbbb-5500-4000-8000-000000000000')
          || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.movimientos_stock t
                      where t.empresa_id = 'bbbbbbbb-5500-4000-8000-000000000000')),
  (select h from huella_b), 'aislamiento: jornadas, operaciones y movimientos de B sin cambios');

-- ===========================================================================
-- 11. E-SL1: sólo lectura (GET/HEAD) → 25006 antes de todo, también en replay
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000001');
set local transaction_read_only = on;
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000501', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f2']::uuid[], array[1])$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave nueva: 25006');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f2', 'aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[1250, 10])$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave usada y misma huella: 25006, no el uuid guardado');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000301', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f1']::uuid[], array[99])$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave usada y otra huella: 25006, no PT409');
reset role;
select pg_temp.como_usuario('aaaaaaaa-5500-4000-8000-000000000003');
select throws_ok($q$select public.registrar_carga('55000000-0000-4000-8000-000000000502', 'aaaaaaaa-5500-4000-8000-0000000000a1', array['aaaaaaaa-5500-4000-8000-0000000000f2']::uuid[], array[1])$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura con vendedor_piloto: 25006, no PT403 (la guarda precede a la autorización)');
reset role;
select ok(pg_temp.igual() and pg_temp.sin_clave('55000000-0000-4000-8000-000000000501'), 'E-SL1: el rechazo por sólo lectura no reserva la clave ni deja efectos');

select * from finish();

rollback;
