-- pgTAP: T7 — RPC confirmar_salida (Blueprint §7.5, §9 y §12; ADR-007 §2.2, §2.3 y
-- §7 casos 20, 21, 22 y 24; ADR-001 §18.4.2 a §18.4.9, grupos S e I, y E-SL1
-- §18.4.16). Ejecutar sólo en local.
--
-- B es un fixture adversarial (aislamiento por empresa_id). Las cargas y descargas
-- se registran con las RPC reales de T5 y T6. La sección 8 es la regresión de flujo
-- real de T5/T6 (decisión humana del 04/11/2026): abrir_jornada → registrar_carga →
-- registrar_descarga → confirmar_salida reales, y después carga, descarga y
-- reasignación rechazadas y replays válidos. La concurrencia (K11-a/b/c, I10-S,
-- I11-S) está en supabase/tests/concurrencia/casos.sh; los objetos pg_temp
-- adversariales y la guardia estática, en pg_temp_jornadas.test.sql. El bloque de
-- sólo lectura (E-SL1) va al final.

begin;

create extension if not exists pgtap with schema extensions;

select plan(65);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-7700-4000-8000-000000000000', 'Empresa A (test T7)'),
  ('bbbbbbbb-7700-4000-8000-000000000000', 'Empresa B (test T7)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-7700-4000-8000-000000000001', 'authenticated', 'authenticated', 'js.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-7700-4000-8000-000000000002', 'authenticated', 'authenticated', 'js.a2@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-7700-4000-8000-000000000003', 'authenticated', 'authenticated', 'js.a3@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-7700-4000-8000-000000000004', 'authenticated', 'authenticated', 'js.a4@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-7700-4000-8000-000000000005', 'authenticated', 'authenticated', 'js.a5@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-7700-4000-8000-000000000006', 'authenticated', 'authenticated', 'js.a6@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-7700-4000-8000-000000000007', 'authenticated', 'authenticated', 'js.a7@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-7700-4000-8000-000000000008', 'authenticated', 'authenticated', 'js.a8@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-7700-4000-8000-000000000009', 'authenticated', 'authenticated', 'js.a9@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-7700-4000-8000-000000000001', 'authenticated', 'authenticated', 'js.b1@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-7700-4000-8000-000000000002', 'authenticated', 'authenticated', 'js.b2@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-7700-4000-8000-000000000001', 'authenticated', 'authenticated', 'js.n1@usuarios.distribuidora.invalid', '{"rol":"dueno","empresa_id":"aaaaaaaa-7700-4000-8000-000000000000"}');

-- A: dueño (1), encargado (2), vendedores (3, 5, 6, 7, 8, 9), dueño inactivo (4).
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-7700-4000-8000-000000000001', 'aaaaaaaa-7700-4000-8000-000000000000', 'js.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-7700-4000-8000-000000000002', 'aaaaaaaa-7700-4000-8000-000000000000', 'js.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-7700-4000-8000-000000000003', 'aaaaaaaa-7700-4000-8000-000000000000', 'js.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-7700-4000-8000-000000000004', 'aaaaaaaa-7700-4000-8000-000000000000', 'js.a4', 'A4', 'dueno', false),
  ('aaaaaaaa-7700-4000-8000-000000000005', 'aaaaaaaa-7700-4000-8000-000000000000', 'js.a5', 'A5', 'vendedor_piloto', true),
  ('aaaaaaaa-7700-4000-8000-000000000006', 'aaaaaaaa-7700-4000-8000-000000000000', 'js.a6', 'A6', 'vendedor_piloto', true),
  ('aaaaaaaa-7700-4000-8000-000000000007', 'aaaaaaaa-7700-4000-8000-000000000000', 'js.a7', 'A7', 'vendedor_piloto', true),
  ('aaaaaaaa-7700-4000-8000-000000000008', 'aaaaaaaa-7700-4000-8000-000000000000', 'js.a8', 'A8', 'vendedor_piloto', true),
  ('aaaaaaaa-7700-4000-8000-000000000009', 'aaaaaaaa-7700-4000-8000-000000000000', 'js.a9', 'A9', 'vendedor_piloto', true),
  ('bbbbbbbb-7700-4000-8000-000000000001', 'bbbbbbbb-7700-4000-8000-000000000000', 'js.b1', 'B1', 'dueno', true),
  ('bbbbbbbb-7700-4000-8000-000000000002', 'bbbbbbbb-7700-4000-8000-000000000000', 'js.b2', 'B2', 'vendedor_piloto', true);

-- Camiones: c1 (salida normal), c2 (carga neta cero), c3 (abierta sin carga), c4
-- (se da de baja), c5 (I9), c6 (I8/I4), c7 (flujo real). B: uno.
insert into public.camiones (id, empresa_id, patente, nombre, activo, creado_por)
select ('aaaaaaaa-7700-4000-8000-0000000000c' || n)::uuid, 'aaaaaaaa-7700-4000-8000-000000000000',
       'JS-0' || n, 'Camión A' || n, true, 'aaaaaaaa-7700-4000-8000-000000000001'
  from generate_series(1, 7) n;
insert into public.camiones (id, empresa_id, patente, nombre, activo, creado_por) values
  ('bbbbbbbb-7700-4000-8000-0000000000c1', 'bbbbbbbb-7700-4000-8000-000000000000', 'JS-B1', 'Camión B1', true, 'bbbbbbbb-7700-4000-8000-000000000001');
insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('aaaaaaaa-7700-4000-8000-0000000000d1', 'aaaaaaaa-7700-4000-8000-000000000000', 'deposito', null),
  ('bbbbbbbb-7700-4000-8000-0000000000d1', 'bbbbbbbb-7700-4000-8000-000000000000', 'deposito', null),
  ('bbbbbbbb-7700-4000-8000-0000000000e1', 'bbbbbbbb-7700-4000-8000-000000000000', 'camion', 'bbbbbbbb-7700-4000-8000-0000000000c1');
insert into public.ubicaciones (id, empresa_id, tipo, camion_id)
select ('aaaaaaaa-7700-4000-8000-0000000000e' || n)::uuid, 'aaaaaaaa-7700-4000-8000-000000000000', 'camion',
       ('aaaaaaaa-7700-4000-8000-0000000000c' || n)::uuid
  from generate_series(1, 7) n;

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('aaaaaaaa-7700-4000-8000-0000000000f1', 'aaaaaaaa-7700-4000-8000-000000000000', 'JS-U', 'Leche A', 'lacteos', 'unidad', 100, true, 'aaaaaaaa-7700-4000-8000-000000000001'),
  ('aaaaaaaa-7700-4000-8000-0000000000f2', 'aaaaaaaa-7700-4000-8000-000000000000', 'JS-P', 'Jamón A', 'fiambres', 'peso', 9000, true, 'aaaaaaaa-7700-4000-8000-000000000001'),
  ('bbbbbbbb-7700-4000-8000-0000000000f1', 'bbbbbbbb-7700-4000-8000-000000000000', 'JS-B', 'Leche B', 'lacteos', 'unidad', 100, true, 'bbbbbbbb-7700-4000-8000-000000000001');

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
create function pg_temp.jornada(j uuid, camion uuid, fecha date, vendedor uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella)
  values (j, 'aaaaaaaa-7700-4000-8000-000000000000', 'aaaaaaaa-7700-4000-8000-000000000001',
          'apertura_jornada', j, repeat('a', 64));
  insert into public.jornadas (id, empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
  values (j, 'aaaaaaaa-7700-4000-8000-000000000000', fecha, camion, vendedor, 'abierta',
          'aaaaaaaa-7700-4000-8000-000000000001', j);
$$;
create function pg_temp.saldo(ubicacion uuid, producto uuid)
returns bigint language sql security definer set search_path = '' as $$
  select coalesce(sum(case when m.ubicacion_destino_id = ubicacion then m.cantidad::bigint
                           else -m.cantidad::bigint end), 0)
    from public.movimientos_stock m
   where m.producto_id = producto
     and (m.ubicacion_destino_id = ubicacion or m.ubicacion_origen_id = ubicacion)
$$;
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
    || '|' || (select count(*) from public.reasignaciones_vendedor)::text
    || '|' || (select string_agg(j.id::text || '=' || j.estado || '=' || j.vendedor_id::text, ',' order by j.id)
                 from public.jornadas j where j.empresa_id = 'aaaaaaaa-7700-4000-8000-000000000000')
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

-- Jornadas abiertas (fixture) J1..J6 en c1..c6; JB de B.
select pg_temp.jornada(('aaaaaaaa-7700-4000-8000-0000000000a' || n)::uuid, ('aaaaaaaa-7700-4000-8000-0000000000c' || n)::uuid,
                       date '2999-07-01', ('aaaaaaaa-7700-4000-8000-00000000000' || (n + 2))::uuid)
  from generate_series(1, 6) n where n <> 2;
select pg_temp.jornada('aaaaaaaa-7700-4000-8000-0000000000a2', 'aaaaaaaa-7700-4000-8000-0000000000c2', date '2999-07-01', 'aaaaaaaa-7700-4000-8000-000000000001');
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella) values
  ('bbbbbbbb-7700-4000-8000-0000000000a1', 'bbbbbbbb-7700-4000-8000-000000000000', 'bbbbbbbb-7700-4000-8000-000000000001',
   'apertura_jornada', 'bbbbbbbb-7700-4000-8000-0000000000a1', repeat('b', 64));
insert into public.jornadas (id, empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id) values
  ('bbbbbbbb-7700-4000-8000-0000000000a1', 'bbbbbbbb-7700-4000-8000-000000000000', date '2999-07-01',
   'bbbbbbbb-7700-4000-8000-0000000000c1', 'bbbbbbbb-7700-4000-8000-000000000002', 'abierta',
   'bbbbbbbb-7700-4000-8000-000000000001', 'bbbbbbbb-7700-4000-8000-0000000000a1');

-- Stock y cargas reales. J1, J4, J5, J6: carga de f1. J2: carga y descarga total
-- (carga neta cero). J3: abierta, sin carga. JB: cargada.
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000001');
select public.registrar_ingreso('77000000-0000-4000-8000-000000000001', 'aaaaaaaa-7700-4000-8000-0000000000f1', 100, 'Remito T7');
select public.registrar_ingreso('77000000-0000-4000-8000-000000000002', 'aaaaaaaa-7700-4000-8000-0000000000f2', 2000, 'Remito T7');
select public.registrar_carga(('77000000-0000-4000-8000-0000000000c' || n)::uuid, ('aaaaaaaa-7700-4000-8000-0000000000a' || n)::uuid,
                              array['aaaaaaaa-7700-4000-8000-0000000000f1']::uuid[], array[5])
  from generate_series(1, 6) n where n <> 3;
select public.registrar_descarga('77000000-0000-4000-8000-0000000000d2', 'aaaaaaaa-7700-4000-8000-0000000000a2',
                                 array['aaaaaaaa-7700-4000-8000-0000000000f1']::uuid[], array[5], 'Sin reparto');
reset role;
select pg_temp.como_usuario('bbbbbbbb-7700-4000-8000-000000000001');
select public.registrar_ingreso('77000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-7700-4000-8000-0000000000f1', 50, 'Remito B');
select public.registrar_carga('77000000-0000-4000-8000-0000000000b2', 'bbbbbbbb-7700-4000-8000-0000000000a1',
  array['bbbbbbbb-7700-4000-8000-0000000000f1']::uuid[], array[7]);
reset role;

create temp table huella_b as
select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.jornadas t
         where t.empresa_id = 'bbbbbbbb-7700-4000-8000-000000000000')
       || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.operaciones t
                   where t.empresa_id = 'bbbbbbbb-7700-4000-8000-000000000000') as h;

-- ===========================================================================
-- 1. Catálogo (S)
-- ===========================================================================
select is(
  (select count(*)::int from pg_proc where proname = 'confirmar_salida'),
  2, 'confirmar_salida: exactamente dos funciones (fachada e implementación), sin sobrecargas');
select ok(
  (select p.prosecdef and p.provolatile = 'v' and p.proowner = 'propietario_rpc'::regrole
          and p.proconfig = array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']
     from pg_proc p where p.oid = 'privado.confirmar_salida(uuid,uuid)'::regprocedure),
  'implementación: SECURITY DEFINER, VOLATILE, owner propietario_rpc, search_path vacío, ACL exacta');
select ok(
  (select not p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole
          and p.proconfig = array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/postgres', 'postgres=X/postgres']
          and p.prosrc !~* 'insert|update|delete'
     from pg_proc p where p.oid = 'public.confirmar_salida(uuid,uuid)'::regprocedure),
  'fachada: SECURITY INVOKER, owner postgres, search_path vacío, ACL exacta, sólo delega');
select ok(
  not has_function_privilege('anon', 'public.confirmar_salida(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.confirmar_salida(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'privado.confirmar_salida(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'privado.confirmar_salida(uuid,uuid)', 'execute')
  and not has_schema_privilege('propietario_rpc', 'privado', 'create'),
  'P11: anon y service_role sin EXECUTE; propietario_rpc sin CREATE residual');
select ok(
  (select prosrc from pg_proc where oid = 'privado.confirmar_salida(uuid,uuid)'::regprocedure)
    ~ E'\\nbegin\\n  -- Paso 0 \\(E-SL1',
  'E-SL1: la guarda de sólo lectura es la primera sentencia');

-- ===========================================================================
-- 2. Seguridad (S)
-- ===========================================================================
select pg_temp.como_anon();
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000100', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, '42501', null, 'anon no puede ejecutar la fachada');
reset role;
select pg_temp.como_anon();
select throws_ok($q$select privado.confirmar_salida('77000000-0000-4000-8000-000000000100', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, '42501', null, 'anon no puede ejecutar la implementación');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000100', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, '42501', null, 'service_role no puede ejecutar la fachada');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select privado.confirmar_salida('77000000-0000-4000-8000-000000000100', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, '42501', null, 'service_role no puede ejecutar la implementación');
reset role;

select pg_temp.fijar();
select pg_temp.sin_sub();
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000101', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, 'PT401', 'jornada_no_autenticado', 'sin sub: PT401');
reset role;
select pg_temp.como_usuario('dddddddd-7700-4000-8000-000000000001');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000102', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, 'PT403', 'jornada_no_autorizado', 'cuenta sin perfil (con metadata de dueño de A): PT403');
reset role;
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000004');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000103', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, 'PT403', 'jornada_no_autorizado', 'dueño inactivo: PT403');
reset role;
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000003');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000104', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, 'PT403', 'jornada_no_autorizado', 'vendedor_piloto (asignado a la jornada): PT403');
reset role;
select pg_temp.como_usuario('bbbbbbbb-7700-4000-8000-000000000001');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000105', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, 'PT404', 'jornada_no_encontrada', 'dueño de B con la jornada de A: PT404, igual que inexistente');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000106', 'cccccccc-7700-4000-8000-0000000000a1')$q$, 'PT404', 'jornada_no_encontrada', 'jornada inexistente: PT404');
reset role;
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000001');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000107', 'bbbbbbbb-7700-4000-8000-0000000000a1')$q$, 'PT404', 'jornada_no_encontrada', 'dueño de A con la jornada de B: PT404');
select throws_ok($q$update public.jornadas set estado = 'en_reparto' where id = 'aaaaaaaa-7700-4000-8000-0000000000a1'$q$, '42501', null, 'UPDATE directo de authenticated sobre jornadas: 42501');
select throws_ok($q$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-7700-4000-8000-000000000000', 'aaaaaaaa-7700-4000-8000-000000000001', 'salida_jornada', '77000000-0000-4000-8000-000000000108', repeat('a', 64), 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, '42501', null, 'INSERT directo de authenticated sobre operaciones: 42501');
reset role;
select ok(pg_temp.igual(), 'los rechazos de seguridad no dejaron filas nuevas ni cambiaron estados');
select ok(pg_temp.sin_clave('77000000-0000-4000-8000-000000000101') and pg_temp.sin_clave('77000000-0000-4000-8000-000000000105'),
  'los rechazos de seguridad no reservaron claves');

-- ===========================================================================
-- 3. Estructura (paso 3; I5, I13, I14)
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000001');
select throws_ok($q$select public.confirmar_salida(null, 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, 'PT400', 'jornada_clave_invalida', 'I14: clave nula');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000201', null)$q$, 'PT404', 'jornada_no_encontrada', 'I13: jornada nula (D-N1)');
reset role;
select ok(pg_temp.igual() and pg_temp.sin_clave('77000000-0000-4000-8000-000000000201'),
  'I13/I14: los rechazos estructurales no dejaron filas ni reservaron la clave');

-- ===========================================================================
-- 4. Salida válida (I1; ADR-007 caso 20). Usa la clave rechazada en I13.
-- ===========================================================================
create temp table antes_salida as
select (select count(*) from public.movimientos_stock) as movs,
       (select count(*) from public.reasignaciones_vendedor) as reas,
       (select vendedor_id from public.jornadas where id = 'aaaaaaaa-7700-4000-8000-0000000000a1') as vend;
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000001');
insert into res select 'S1', public.confirmar_salida('77000000-0000-4000-8000-000000000201', 'aaaaaaaa-7700-4000-8000-0000000000a1');
reset role;
select is(
  (select o.tipo || '|' || o.jornada_id::text || '|' || o.actor_id::text || '|' || o.empresa_id::text
     from public.operaciones o where o.id = (select v from res where k = 'S1')),
  'salida_jornada|aaaaaaaa-7700-4000-8000-0000000000a1|aaaaaaaa-7700-4000-8000-000000000001|aaaaaaaa-7700-4000-8000-000000000000',
  'I1/I13: la respuesta es la operación salida_jornada (la clave rechazada antes se usó como primera ejecución)');
select is(
  (select o.huella from public.operaciones o where o.id = (select v from res where k = 'S1')),
  pg_temp.huella('v1|salida_jornada|aaaaaaaa-7700-4000-8000-0000000000a1'),
  'I1: la huella es la v1 canónica, recalculada con un texto escrito aparte');
select is((select estado from public.jornadas where id = 'aaaaaaaa-7700-4000-8000-0000000000a1'), 'en_reparto',
  'caso 20: salida desde cargada con carga neta positiva → en_reparto');
select ok(
  (select count(*) from public.movimientos_stock) = (select movs from antes_salida)
  and (select count(*) from public.reasignaciones_vendedor) = (select reas from antes_salida)
  and (select vendedor_id from public.jornadas where id = 'aaaaaaaa-7700-4000-8000-0000000000a1') = (select vend from antes_salida),
  'I1: la salida no genera movimientos ni historial y no cambia el vendedor');

-- ===========================================================================
-- 5. Idempotencia (I2, I3, I5, I6, I12)
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000001');
insert into res select 'R1', public.confirmar_salida('77000000-0000-4000-8000-000000000201', 'aaaaaaaa-7700-4000-8000-0000000000a1');
insert into res select 'R2', public.confirmar_salida('77000000-0000-4000-8000-000000000201', 'AAAAAAAA-7700-4000-8000-0000000000A1');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000201', 'aaaaaaaa-7700-4000-8000-0000000000a4')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otra jornada');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000201', null)$q$, 'PT404', 'jornada_no_encontrada', 'I5: jornada nula con la clave usada: PT404 antes del replay');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000202', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, 'PT409', 'jornada_estado_invalido', 'I3/caso 22: una salida nueva (otra clave) sobre la jornada en_reparto se rechaza');
reset role;
select is((select v from res where k = 'R1'), (select v from res where k = 'S1'), 'I2/I3: replay idéntico, con la jornada ya en_reparto, devuelve la misma operación');
select is((select v from res where k = 'R2'), (select v from res where k = 'S1'), 'I12: uuid de la jornada en mayúsculas = replay');
select ok(pg_temp.igual() and pg_temp.sin_clave('77000000-0000-4000-8000-000000000202'), 'I2/I3/I5/I6/I12: sin filas nuevas ni cambios de estado');

-- ===========================================================================
-- 6. Rechazos de negocio, camión de baja e I9 (casos 21 y 24)
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000001');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000301', 'aaaaaaaa-7700-4000-8000-0000000000a2')$q$, 'PT409', 'jornada_carga_neta_cero', 'caso 21: carga neta cero después de descargas: PT409');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000302', 'aaaaaaaa-7700-4000-8000-0000000000a3')$q$, 'PT409', 'jornada_estado_invalido', 'caso 21: salida desde abierta (sin carga): estado antes que carga neta');
reset role;
select ok(pg_temp.igual() and pg_temp.sin_clave('77000000-0000-4000-8000-000000000301') and pg_temp.sin_clave('77000000-0000-4000-8000-000000000302'),
  'caso 21: los rechazos no dejaron operaciones ni cambios de estado y no reservaron claves');
-- Caso 24: camión dado de baja con jornada cargada: la salida se admite.
update public.camiones set activo = false where id = 'aaaaaaaa-7700-4000-8000-0000000000c4';
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000001');
insert into res select 'S4', public.confirmar_salida('77000000-0000-4000-8000-000000000303', 'aaaaaaaa-7700-4000-8000-0000000000a4');
-- I9: la clave del rechazo por carga neta cero, con una jornada válida (J5).
insert into res select 'I9', public.confirmar_salida('77000000-0000-4000-8000-000000000301', 'aaaaaaaa-7700-4000-8000-0000000000a5');
reset role;
select is((select estado from public.jornadas where id = 'aaaaaaaa-7700-4000-8000-0000000000a4'), 'en_reparto',
  'caso 24: con el camión dado de baja la salida se confirma');
select is((select o.tipo || '/' || o.jornada_id::text from public.operaciones o where o.id = (select v from res where k = 'I9')),
  'salida_jornada/aaaaaaaa-7700-4000-8000-0000000000a5', 'I9: tras un rechazo, la misma clave con payload válido se ejecuta como primera ejecución');

-- ===========================================================================
-- 7. I4, I7 e I8
-- ===========================================================================
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000002');
insert into res select 'E6', public.confirmar_salida('77000000-0000-4000-8000-000000000201', 'aaaaaaaa-7700-4000-8000-0000000000a6');
reset role;
select ok((select v from res where k = 'E6') <> (select v from res where k = 'S1')
          and (select o.actor_id from public.operaciones o where o.id = (select v from res where k = 'E6')) = 'aaaaaaaa-7700-4000-8000-000000000002',
  'I8: la misma clave usada por otro actor (encargado) es una operación nueva e independiente');
update public.perfiles set activo = false where usuario_id = 'aaaaaaaa-7700-4000-8000-000000000002';
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000002');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000201', 'aaaaaaaa-7700-4000-8000-0000000000a6')$q$, 'PT403', 'jornada_no_autorizado', 'I4: replay con autorización perdida: PT403');
reset role;
update public.perfiles set activo = true where usuario_id = 'aaaaaaaa-7700-4000-8000-000000000002';
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000001');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-0000000000c1', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una carga');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-0000000000d2', 'aaaaaaaa-7700-4000-8000-0000000000a2')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una descarga');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000001', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de un ingreso de Stock');
select throws_ok($q$select public.registrar_carga('77000000-0000-4000-8000-000000000201', 'aaaaaaaa-7700-4000-8000-0000000000a3', array['aaaaaaaa-7700-4000-8000-0000000000f1']::uuid[], array[1])$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: registrar_carga con la clave de una salida');
select throws_ok($q$select public.registrar_merma('77000000-0000-4000-8000-000000000201', 'aaaaaaaa-7700-4000-8000-0000000000f1', 'aaaaaaaa-7700-4000-8000-0000000000d1', 1, 'vencido', null)$q$, 'PT409', 'stock_conflicto_idempotencia', 'I7 (regresión): registrar_merma con una clave de salida sigue respondiendo stock_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I4/I7: sin filas nuevas ni cambios de estado');

-- ===========================================================================
-- 8. Regresión de flujo real (T5/T6 → T7): apertura, carga, descarga y salida
--    reales; después carga, descarga y reasignación rechazadas y replays válidos
-- ===========================================================================
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000001');
insert into res select 'FA', public.abrir_jornada('77000000-0000-4000-8000-000000000400', 'aaaaaaaa-7700-4000-8000-0000000000c7', date '2999-07-02', 'aaaaaaaa-7700-4000-8000-000000000009');
insert into res select 'FC', public.registrar_carga('77000000-0000-4000-8000-000000000401', (select v from res where k = 'FA'),
  array['aaaaaaaa-7700-4000-8000-0000000000f1', 'aaaaaaaa-7700-4000-8000-0000000000f2']::uuid[], array[6, 750]);
insert into res select 'FD', public.registrar_descarga('77000000-0000-4000-8000-000000000402', (select v from res where k = 'FA'),
  array['aaaaaaaa-7700-4000-8000-0000000000f2']::uuid[], array[750], 'Sin pedido de fiambres');
insert into res select 'FS', public.confirmar_salida('77000000-0000-4000-8000-000000000403', (select v from res where k = 'FA'));
reset role;
select is(
  (select estado from public.jornadas where id = (select v from res where k = 'FA')) || '/'
  || pg_temp.neta((select v from res where k = 'FA'), 'aaaaaaaa-7700-4000-8000-0000000000f1')::text || '/'
  || pg_temp.neta((select v from res where k = 'FA'), 'aaaaaaaa-7700-4000-8000-0000000000f2')::text,
  'en_reparto/6/0', 'flujo real: abierta → cargada → descarga de f2 → en_reparto con carga neta positiva sólo en f1');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000001');
select throws_ok(format($q$select public.registrar_carga('77000000-0000-4000-8000-000000000404', %L, array['aaaaaaaa-7700-4000-8000-0000000000f1']::uuid[], array[1])$q$, (select v from res where k = 'FA')),
  'PT409', 'jornada_estado_invalido', 'flujo real (caso 22): carga después de la salida: PT409');
select throws_ok(format($q$select public.registrar_descarga('77000000-0000-4000-8000-000000000405', %L, array['aaaaaaaa-7700-4000-8000-0000000000f1']::uuid[], array[1], 'x')$q$, (select v from res where k = 'FA')),
  'PT409', 'jornada_estado_invalido', 'flujo real (caso 22): descarga después de la salida: PT409');
select throws_ok(format($q$select public.reasignar_vendedor('77000000-0000-4000-8000-000000000406', %L, 'aaaaaaaa-7700-4000-8000-000000000008')$q$, (select v from res where k = 'FA')),
  'PT409', 'jornada_estado_invalido', 'flujo real (caso 22): reasignación después de la salida: PT409 (el vendedor queda fijado)');
select is(public.registrar_carga('77000000-0000-4000-8000-000000000401', (select v from res where k = 'FA'),
            array['aaaaaaaa-7700-4000-8000-0000000000f2', 'aaaaaaaa-7700-4000-8000-0000000000f1']::uuid[], array[750, 6]),
  (select v from res where k = 'FC'), 'flujo real (I3 de T5): replay de la carga después de la salida devuelve la operación original');
select is(public.registrar_descarga('77000000-0000-4000-8000-000000000402', (select v from res where k = 'FA'),
            array['aaaaaaaa-7700-4000-8000-0000000000f2']::uuid[], array[750], '  Sin pedido de fiambres '),
  (select v from res where k = 'FD'), 'flujo real (I3 de T6): replay de la descarga después de la salida devuelve la operación original');
select is(public.confirmar_salida('77000000-0000-4000-8000-000000000403', (select v from res where k = 'FA')),
  (select v from res where k = 'FS'), 'flujo real: replay de la salida devuelve la operación original');
reset role;
select ok(pg_temp.igual() and pg_temp.sin_clave('77000000-0000-4000-8000-000000000404') and pg_temp.sin_clave('77000000-0000-4000-8000-000000000406'),
  'flujo real: los rechazos posteriores a la salida y los replays no dejaron efectos');
select is((select vendedor_id from public.jornadas where id = (select v from res where k = 'FA')), 'aaaaaaaa-7700-4000-8000-000000000009'::uuid,
  'flujo real: el vendedor asignado al confirmar la salida queda fijado');

-- ===========================================================================
-- 9. Invariantes finales
-- ===========================================================================
select is(
  (select count(*)::int from public.jornadas j
    where j.empresa_id = 'aaaaaaaa-7700-4000-8000-000000000000' and j.estado = 'en_reparto'
      and not exists (select 1 from public.movimientos_stock m
                       where m.jornada_id = j.id and m.tipo_movimiento in ('carga', 'descarga')
                       group by m.producto_id
                      having sum(case when m.tipo_movimiento = 'carga' then m.cantidad else -m.cantidad end) > 0)),
  0, 'I-J4: toda jornada en_reparto tiene carga neta positiva en al menos un producto');
select is(
  (select count(*)::int from public.jornadas j
    join public.ubicaciones u on u.camion_id = j.camion_id and u.tipo = 'camion'
    cross join (select distinct producto_id from public.movimientos_stock where empresa_id = 'aaaaaaaa-7700-4000-8000-000000000000') p
   where j.empresa_id = 'aaaaaaaa-7700-4000-8000-000000000000' and j.estado <> 'cerrada'
     and pg_temp.saldo(u.id, p.producto_id) <> pg_temp.neta(j.id, p.producto_id)),
  0, 'I-J2: por jornada sin cerrar y producto, saldo del camión = Σ cargas − Σ descargas de la jornada');
select is(
  (select count(*)::int from (select jornada_id from public.operaciones where tipo = 'salida_jornada'
                               group by jornada_id having count(*) > 1) x),
  0, 'a lo sumo una operación salida_jornada por jornada');
select is(
  (select count(*)::int from public.stock_actual s where s.empresa_id = 'aaaaaaaa-7700-4000-8000-000000000000' and s.cantidad < 0),
  0, 'ningún saldo negativo en ninguna ubicación de A');
select is(
  (select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.jornadas t
            where t.empresa_id = 'bbbbbbbb-7700-4000-8000-000000000000')
          || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.operaciones t
                      where t.empresa_id = 'bbbbbbbb-7700-4000-8000-000000000000')),
  (select h from huella_b), 'aislamiento: jornadas y operaciones de B sin cambios');

-- ===========================================================================
-- 10. E-SL1: sólo lectura (GET/HEAD) → 25006 antes de todo, también en replay
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000001');
set local transaction_read_only = on;
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000501', 'aaaaaaaa-7700-4000-8000-0000000000a3')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave nueva: 25006');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000201', 'aaaaaaaa-7700-4000-8000-0000000000a1')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave usada y misma huella: 25006, no el uuid guardado');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000201', 'aaaaaaaa-7700-4000-8000-0000000000a3')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave usada y otra huella: 25006, no PT409');
reset role;
select pg_temp.como_usuario('aaaaaaaa-7700-4000-8000-000000000003');
select throws_ok($q$select public.confirmar_salida('77000000-0000-4000-8000-000000000502', 'aaaaaaaa-7700-4000-8000-0000000000a3')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura con vendedor_piloto: 25006, no PT403');
reset role;
select ok(pg_temp.igual() and pg_temp.sin_clave('77000000-0000-4000-8000-000000000501'), 'E-SL1: el rechazo por sólo lectura no reserva la clave ni deja efectos');

select * from finish();

rollback;
