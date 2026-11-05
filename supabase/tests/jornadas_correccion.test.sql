-- pgTAP: T4 — RPC corregir_jornada (Blueprint §7.5, §9 y §12; ADR-007 §2.4, §2.7 y
-- §7 casos 10, 11, 12, 22 y 24; ADR-001 §18.4.2 a §18.4.9, grupos S e I, H-01, y
-- E-SL1 §18.4.16). Ejecutar sólo en local.
--
-- Decisiones humanas del 04/11/2026: precedencia del paso 10 (estado → movimientos
-- → fecha final → camión final → sin cambios → duplicada → camión con jornada
-- abierta → vendedor ocupado); revalidar siempre la fecha y el camión finales,
-- aunque no cambien; no exigir que el vendedor vigente esté activo.
--
-- B es un fixture adversarial (aislamiento por empresa_id). Las cargas, descargas
-- y salidas se registran con las RPC reales de T5, T6 y T7. La sección 9 es el
-- flujo real apertura → corrección → carga → salida. La concurrencia (I10-CJ,
-- I11-CJ, K5, K6, K7, K9-C, K12, O-C) está en supabase/tests/concurrencia/casos.sh;
-- los objetos pg_temp adversariales, en pg_temp_jornadas.test.sql. El bloque de
-- sólo lectura (E-SL1) va al final.

begin;

create extension if not exists pgtap with schema extensions;

select plan(105);

-- ---------------------------------------------------------------------------
-- Identificadores (funciones temporales inmutables)
-- ---------------------------------------------------------------------------
create function pg_temp.u(n int) returns uuid language sql immutable as $$
  select ('aaaaaaaa-4400-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.c(n int) returns uuid language sql immutable as $$
  select ('aaaaaaaa-4400-4000-8000-0000000c00' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.j(n int) returns uuid language sql immutable as $$
  select ('aaaaaaaa-4400-4000-8000-0000000a00' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.e(n int) returns uuid language sql immutable as $$
  select ('aaaaaaaa-4400-4000-8000-0000000e00' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.k(n int) returns uuid language sql immutable as $$
  select ('44000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.f(n int) returns date language sql immutable as $$
  select date '2999-08-01' + n $$;
create function pg_temp.hoy() returns date language sql stable as $$
  select (now() at time zone 'America/Argentina/Tucuman')::date $$;
grant execute on function pg_temp.u(int), pg_temp.c(int), pg_temp.j(int), pg_temp.e(int),
  pg_temp.k(int), pg_temp.f(int), pg_temp.hoy() to public;

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-4400-4000-8000-000000000000', 'Empresa A (test T4)'),
  ('bbbbbbbb-4400-4000-8000-000000000000', 'Empresa B (test T4)');

insert into auth.users (id, aud, role, email, raw_user_meta_data)
select pg_temp.u(n), 'authenticated', 'authenticated', 'jc.a' || n || '@usuarios.distribuidora.invalid', '{}'
  from generate_series(1, 9) n;
insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('bbbbbbbb-4400-4000-8000-000000000001', 'authenticated', 'authenticated', 'jc.b1@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-4400-4000-8000-000000000002', 'authenticated', 'authenticated', 'jc.b2@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-4400-4000-8000-000000000001', 'authenticated', 'authenticated', 'jc.n1@usuarios.distribuidora.invalid', '{"rol":"dueno","empresa_id":"aaaaaaaa-4400-4000-8000-000000000000"}');

-- A: dueño (1), encargado (2), vendedores (3, 5, 6, 7, 8, 9), dueño inactivo (4).
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo)
select pg_temp.u(n), 'aaaaaaaa-4400-4000-8000-000000000000', 'jc.a' || n, 'A' || n,
       case n when 1 then 'dueno' when 2 then 'encargado' when 4 then 'dueno' else 'vendedor_piloto' end,
       n <> 4
  from generate_series(1, 9) n;
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('bbbbbbbb-4400-4000-8000-000000000001', 'bbbbbbbb-4400-4000-8000-000000000000', 'jc.b1', 'B1', 'dueno', true),
  ('bbbbbbbb-4400-4000-8000-000000000002', 'bbbbbbbb-4400-4000-8000-000000000000', 'jc.b2', 'B2', 'vendedor_piloto', true);

-- Camiones c1..c19 de A (c12 inactivo desde el inicio) y uno de B, con su ubicación.
insert into public.camiones (id, empresa_id, patente, nombre, activo, creado_por)
select pg_temp.c(n), 'aaaaaaaa-4400-4000-8000-000000000000', 'JC-' || lpad(n::text, 2, '0'),
       'Camión A' || n, n <> 12, pg_temp.u(1)
  from generate_series(1, 19) n;
insert into public.camiones (id, empresa_id, patente, nombre, activo, creado_por) values
  ('bbbbbbbb-4400-4000-8000-0000000c0001', 'bbbbbbbb-4400-4000-8000-000000000000', 'JC-B1', 'Camión B1', true, 'bbbbbbbb-4400-4000-8000-000000000001');
insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('aaaaaaaa-4400-4000-8000-0000000d0001', 'aaaaaaaa-4400-4000-8000-000000000000', 'deposito', null),
  ('aaaaaaaa-4400-4000-8000-0000000d0002', 'aaaaaaaa-4400-4000-8000-000000000000', 'cuarentena', null),
  ('bbbbbbbb-4400-4000-8000-0000000d0001', 'bbbbbbbb-4400-4000-8000-000000000000', 'deposito', null),
  ('bbbbbbbb-4400-4000-8000-0000000e0001', 'bbbbbbbb-4400-4000-8000-000000000000', 'camion', 'bbbbbbbb-4400-4000-8000-0000000c0001');
insert into public.ubicaciones (id, empresa_id, tipo, camion_id)
select pg_temp.e(n), 'aaaaaaaa-4400-4000-8000-000000000000', 'camion', pg_temp.c(n)
  from generate_series(1, 19) n;

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('aaaaaaaa-4400-4000-8000-0000000f0001', 'aaaaaaaa-4400-4000-8000-000000000000', 'JC-U', 'Leche A', 'lacteos', 'unidad', 100, true, 'aaaaaaaa-4400-4000-8000-000000000001');

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
-- Jornada abierta de fixture (operación de apertura con clave = id de la jornada).
create function pg_temp.jornada(j uuid, camion uuid, fecha date, vendedor uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella)
  values (j, 'aaaaaaaa-4400-4000-8000-000000000000', 'aaaaaaaa-4400-4000-8000-000000000001',
          'apertura_jornada', j, repeat('a', 64));
  insert into public.jornadas (id, empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
  values (j, 'aaaaaaaa-4400-4000-8000-000000000000', fecha, camion, vendedor, 'abierta',
          'aaaaaaaa-4400-4000-8000-000000000001', j);
$$;
create function pg_temp.conteo()
returns text language sql security definer set search_path = '' as $$
  select (select count(*) from public.operaciones)::text
    || '|' || (select count(*) from public.movimientos_stock)::text
    || '|' || (select count(*) from public.jornadas)::text
    || '|' || (select count(*) from public.reasignaciones_vendedor)::text
    || '|' || (select count(*) from public.correcciones_jornada)::text
    || '|' || (select string_agg(j.id::text || '=' || j.estado || '=' || j.vendedor_id::text || '=' || j.camion_id::text
                                 || '=' || j.fecha::text, ',' order by j.id)
                 from public.jornadas j where j.empresa_id = 'aaaaaaaa-4400-4000-8000-000000000000')
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
create function pg_temp.jor(id uuid)
returns text language sql security definer set search_path = '' as $$
  select right(j.camion_id::text, 2) || '/' || j.fecha::text || '/' || right(j.vendedor_id::text, 2) || '/' || j.estado
    from public.jornadas j where j.id = jor.id
$$;
grant execute on function pg_temp.como_usuario(uuid), pg_temp.sin_sub(), pg_temp.como_anon(),
  pg_temp.como_service_role(), pg_temp.conteo(), pg_temp.fijar(), pg_temp.igual(),
  pg_temp.sin_clave(uuid), pg_temp.huella(text), pg_temp.jor(uuid) to public;

create temp table res (k text primary key, v uuid);
grant select, insert on res to public;

-- Jornadas abiertas de fixture (F = 2999-08-01):
--   J1  c1,  F,     V5   corrección de fecha y camión (I1)
--   J2  c3,  F,     V6   sólo fecha, por el encargado (I8, caso 10)
--   J3  c4,  F,     V7   sólo camión (I9, caso 10)
--   J4  c6,  F,     V8   rechazos (casos 11 y 24, precedencia)
--   J5  c7,  F,     V9   se corrige, se carga y sale (I3, casos 12 y 22)
--   J7  c9,  F,     A2   con un movimiento de fixture (jornada_con_movimientos)
--   J8  c11, F,     V3   hacia el día operativo actual
--   J9  c14, F+12,  V6   su camión se da de baja (decisión 2)
--   J10 c15, 2000-01-02, V5  fecha ya pasada (decisión 2)
--   J11 c16, F+13,  A4   vendedor vigente inactivo (decisión 3)
--   JC  c10, F+5,   V3   cerrada (par ocupado incluso cerrada)
--   JV  c13, F+7,   V8   ocupa a V8 en F+7
--   JR  c17, F+8,   V6   se reasigna a V7 (clave de reasignación para I7)
select pg_temp.jornada(pg_temp.j(1), pg_temp.c(1), pg_temp.f(0), pg_temp.u(5));
select pg_temp.jornada(pg_temp.j(2), pg_temp.c(3), pg_temp.f(0), pg_temp.u(6));
select pg_temp.jornada(pg_temp.j(3), pg_temp.c(4), pg_temp.f(0), pg_temp.u(7));
select pg_temp.jornada(pg_temp.j(4), pg_temp.c(6), pg_temp.f(0), pg_temp.u(8));
select pg_temp.jornada(pg_temp.j(5), pg_temp.c(7), pg_temp.f(0), pg_temp.u(9));
select pg_temp.jornada(pg_temp.j(7), pg_temp.c(9), pg_temp.f(0), pg_temp.u(2));
select pg_temp.jornada(pg_temp.j(8), pg_temp.c(11), pg_temp.f(0), pg_temp.u(3));
select pg_temp.jornada(pg_temp.j(9), pg_temp.c(14), pg_temp.f(12), pg_temp.u(6));
select pg_temp.jornada(pg_temp.j(10), pg_temp.c(15), date '2000-01-02', pg_temp.u(5));
select pg_temp.jornada(pg_temp.j(11), pg_temp.c(16), pg_temp.f(13), pg_temp.u(4));
select pg_temp.jornada(pg_temp.j(20), pg_temp.c(10), pg_temp.f(5), pg_temp.u(3));
update public.jornadas set estado = 'cerrada' where id = pg_temp.j(20);
select pg_temp.jornada(pg_temp.j(21), pg_temp.c(13), pg_temp.f(7), pg_temp.u(8));
select pg_temp.jornada(pg_temp.j(22), pg_temp.c(17), pg_temp.f(8), pg_temp.u(6));
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella) values
  ('bbbbbbbb-4400-4000-8000-0000000a0001', 'bbbbbbbb-4400-4000-8000-000000000000', 'bbbbbbbb-4400-4000-8000-000000000001',
   'apertura_jornada', 'bbbbbbbb-4400-4000-8000-0000000a0001', repeat('b', 64));
insert into public.jornadas (id, empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id) values
  ('bbbbbbbb-4400-4000-8000-0000000a0001', 'bbbbbbbb-4400-4000-8000-000000000000', date '2999-08-01',
   'bbbbbbbb-4400-4000-8000-0000000c0001', 'bbbbbbbb-4400-4000-8000-000000000002', 'abierta',
   'bbbbbbbb-4400-4000-8000-000000000001', 'bbbbbbbb-4400-4000-8000-0000000a0001');

-- Stock (ingreso real) y un movimiento de fixture en J7, que sigue abierta: sólo es
-- posible como owner (defensa en profundidad de ADR-007 §2.4.1).
select pg_temp.como_usuario(pg_temp.u(1));
select public.registrar_ingreso(pg_temp.k(1), 'aaaaaaaa-4400-4000-8000-0000000f0001', 100, 'Remito T4');
reset role;
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values
  (pg_temp.k(2), 'aaaaaaaa-4400-4000-8000-000000000000', pg_temp.u(1), 'carga', pg_temp.k(2), repeat('c', 64), pg_temp.j(7));
insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                      ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo, jornada_id)
values ('aaaaaaaa-4400-4000-8000-000000000000', pg_temp.k(2), 'carga', 'aaaaaaaa-4400-4000-8000-0000000f0001', 1,
        'aaaaaaaa-4400-4000-8000-0000000d0001', pg_temp.e(9), pg_temp.u(1), null, pg_temp.j(7));

create temp table huella_b as
select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.jornadas t
         where t.empresa_id = 'bbbbbbbb-4400-4000-8000-000000000000')
       || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.operaciones t
                   where t.empresa_id = 'bbbbbbbb-4400-4000-8000-000000000000')
       || '/' || (select count(*)::text from public.correcciones_jornada t
                   where t.empresa_id = 'bbbbbbbb-4400-4000-8000-000000000000') as h;

-- ===========================================================================
-- 1. Catálogo (S)
-- ===========================================================================
select is(
  (select count(*)::int from pg_proc where proname = 'corregir_jornada'),
  2, 'corregir_jornada: exactamente dos funciones (fachada e implementación), sin sobrecargas');
select ok(
  (select p.prosecdef and p.provolatile = 'v' and p.proowner = 'propietario_rpc'::regrole
          and p.proconfig = array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']
     from pg_proc p where p.oid = 'privado.corregir_jornada(uuid,uuid,date,uuid,text)'::regprocedure),
  'implementación: SECURITY DEFINER, VOLATILE, owner propietario_rpc, search_path vacío, ACL exacta');
select ok(
  (select not p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole
          and p.proconfig = array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/postgres', 'postgres=X/postgres']
          and p.prosrc !~* 'insert|update|delete'
     from pg_proc p where p.oid = 'public.corregir_jornada(uuid,uuid,date,uuid,text)'::regprocedure),
  'fachada: SECURITY INVOKER, owner postgres, search_path vacío, ACL exacta, sólo delega');
select ok(
  not has_function_privilege('anon', 'public.corregir_jornada(uuid,uuid,date,uuid,text)', 'execute')
  and not has_function_privilege('service_role', 'public.corregir_jornada(uuid,uuid,date,uuid,text)', 'execute')
  and not has_function_privilege('anon', 'privado.corregir_jornada(uuid,uuid,date,uuid,text)', 'execute')
  and not has_function_privilege('service_role', 'privado.corregir_jornada(uuid,uuid,date,uuid,text)', 'execute')
  and not has_schema_privilege('propietario_rpc', 'privado', 'create'),
  'P11: anon y service_role sin EXECUTE; propietario_rpc sin CREATE residual');
select ok(
  (select prosrc from pg_proc where oid = 'privado.corregir_jornada(uuid,uuid,date,uuid,text)'::regprocedure)
    ~ E'\\nbegin\\n  -- Paso 0 \\(E-SL1',
  'E-SL1: la guarda de sólo lectura es la primera sentencia');
select ok(
  (select prosrc from pg_proc where oid = 'privado.corregir_jornada(uuid,uuid,date,uuid,text)'::regprocedure)
    ~ 'jornadas:camion:.*jornadas:camion:.*jornadas:camion:.*jornadas:vendedor:.*for update',
  'H-01: los advisory de camión (nivel 1) y de vendedor (nivel 2) preceden al FOR UPDATE de la jornada (nivel 3)');

-- ===========================================================================
-- 2. Seguridad (S)
-- ===========================================================================
select pg_temp.como_anon();
select throws_ok($q$select public.corregir_jornada(pg_temp.k(100), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, '42501', null, 'anon no puede ejecutar la fachada');
reset role;
select pg_temp.como_anon();
select throws_ok($q$select privado.corregir_jornada(pg_temp.k(100), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, '42501', null, 'anon no puede ejecutar la implementación');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select public.corregir_jornada(pg_temp.k(100), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, '42501', null, 'service_role no puede ejecutar la fachada');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select privado.corregir_jornada(pg_temp.k(100), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, '42501', null, 'service_role no puede ejecutar la implementación');
reset role;

select pg_temp.fijar();
select pg_temp.sin_sub();
select throws_ok($q$select public.corregir_jornada(pg_temp.k(101), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT401', 'jornada_no_autenticado', 'sin sub: PT401');
reset role;
select pg_temp.como_usuario('dddddddd-4400-4000-8000-000000000001');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(102), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT403', 'jornada_no_autorizado', 'cuenta sin perfil (con metadata de dueño de A): PT403');
reset role;
select pg_temp.como_usuario(pg_temp.u(4));
select throws_ok($q$select public.corregir_jornada(pg_temp.k(103), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT403', 'jornada_no_autorizado', 'dueño inactivo: PT403');
reset role;
select pg_temp.como_usuario(pg_temp.u(8));
select throws_ok($q$select public.corregir_jornada(pg_temp.k(104), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT403', 'jornada_no_autorizado', 'vendedor_piloto (asignado a la jornada): PT403');
reset role;
select pg_temp.como_usuario('bbbbbbbb-4400-4000-8000-000000000001');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(105), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT404', 'jornada_no_encontrada', 'dueño de B con la jornada de A: PT404, igual que inexistente');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(106), 'cccccccc-4400-4000-8000-0000000a0001', pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT404', 'jornada_no_encontrada', 'jornada inexistente: PT404');
reset role;
select pg_temp.como_usuario(pg_temp.u(1));
select throws_ok($q$select public.corregir_jornada(pg_temp.k(107), 'bbbbbbbb-4400-4000-8000-0000000a0001', pg_temp.f(1), 'bbbbbbbb-4400-4000-8000-0000000c0001', 'x')$q$, 'PT404', 'jornada_no_encontrada', 'dueño de A con la jornada de B: PT404');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(108), pg_temp.j(4), pg_temp.f(1), 'bbbbbbbb-4400-4000-8000-0000000c0001', 'x')$q$, 'PT404', 'jornada_camion_no_encontrado', 'camión final de B: PT404, igual que inexistente');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(109), pg_temp.j(4), pg_temp.f(1), 'cccccccc-4400-4000-8000-0000000c0001', 'x')$q$, 'PT404', 'jornada_camion_no_encontrado', 'camión final inexistente: PT404');
select throws_ok($q$update public.jornadas set fecha = pg_temp.f(1) where id = pg_temp.j(4)$q$, '42501', null, 'UPDATE directo de authenticated sobre jornadas: 42501');
select throws_ok($q$insert into public.correcciones_jornada (empresa_id, jornada_id, operacion_id, fecha_anterior, fecha_nueva, camion_anterior_id, camion_nuevo_id, motivo, actor_id) values ('aaaaaaaa-4400-4000-8000-000000000000', pg_temp.j(4), pg_temp.k(2), pg_temp.f(0), pg_temp.f(1), pg_temp.c(6), pg_temp.c(6), 'x', pg_temp.u(1))$q$, '42501', null, 'INSERT directo de authenticated sobre correcciones_jornada: 42501');
reset role;
select ok(pg_temp.igual(), 'los rechazos de seguridad no dejaron filas nuevas ni cambiaron jornadas');
select ok(pg_temp.sin_clave(pg_temp.k(101)) and pg_temp.sin_clave(pg_temp.k(105)) and pg_temp.sin_clave(pg_temp.k(108)),
  'los rechazos de seguridad no reservaron claves');

-- ===========================================================================
-- 3. Estructura (paso 3; I5, I13, I14)
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario(pg_temp.u(1));
select throws_ok($q$select public.corregir_jornada(null, pg_temp.j(1), pg_temp.f(1), pg_temp.c(2), 'x')$q$, 'PT400', 'jornada_clave_invalida', 'I14: clave nula');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), null, pg_temp.f(1), pg_temp.c(2), 'x')$q$, 'PT404', 'jornada_no_encontrada', 'I13: jornada nula (D-N1)');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), null, pg_temp.c(2), 'x')$q$, 'PT400', 'jornada_fecha_invalida', 'I13: fecha nula');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), 'infinity', pg_temp.c(2), 'x')$q$, 'PT400', 'jornada_fecha_invalida', 'I13: fecha infinita');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), null, 'x')$q$, 'PT404', 'jornada_camion_no_encontrado', 'I13: camión final nulo (D-N1)');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), pg_temp.c(2), null)$q$, 'PT400', 'jornada_motivo_invalido', 'I13: motivo nulo');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), pg_temp.c(2), '    ')$q$, 'PT400', 'jornada_motivo_invalido', 'I13: motivo vacío después de btrim');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), null, null, null, null)$q$, 'PT404', 'jornada_no_encontrada', 'paso 3: orden clave → jornada → fecha → camión → motivo (la jornada nula precede)');
reset role;
select ok(pg_temp.igual() and pg_temp.sin_clave(pg_temp.k(201)),
  'I13/I14: los rechazos estructurales no dejaron filas ni reservaron la clave');

-- ===========================================================================
-- 4. Corrección válida de fecha y camión (I1; ADR-007 caso 10). Usa la clave
--    rechazada en I13.
-- ===========================================================================
create temp table antes as
select (select count(*) from public.movimientos_stock) as movs,
       (select count(*) from public.reasignaciones_vendedor) as reas,
       (select count(*) from public.correcciones_jornada) as corr;
select pg_temp.como_usuario(pg_temp.u(1));
insert into res select 'C1', public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), pg_temp.c(2), '  Error de tipeo  ');
reset role;
select is(
  (select o.tipo || '|' || o.jornada_id::text || '|' || o.actor_id::text || '|' || o.empresa_id::text
     from public.operaciones o where o.id = (select v from res where k = 'C1')),
  'correccion_jornada|' || pg_temp.j(1)::text || '|' || pg_temp.u(1)::text || '|aaaaaaaa-4400-4000-8000-000000000000',
  'I1/I13: la respuesta es la operación correccion_jornada (la clave rechazada antes se usó como primera ejecución)');
select is(
  (select o.huella from public.operaciones o where o.id = (select v from res where k = 'C1')),
  pg_temp.huella('v1|correccion_jornada|aaaaaaaa-4400-4000-8000-0000000a0001|2999-08-02|aaaaaaaa-4400-4000-8000-0000000c0002|+Error de tipeo'),
  'I1: la huella es la v1 canónica (fecha YYYY-MM-DD, motivo con btrim), recalculada con un texto escrito aparte');
select is(pg_temp.jor(pg_temp.j(1)), '02/2999-08-02/05/abierta',
  'caso 10: fecha y camión nuevos; vendedor y estado intactos');
select is(
  (select c.jornada_id::text || '|' || c.operacion_id::text || '|' || c.fecha_anterior::text || '>' || c.fecha_nueva::text
          || '|' || right(c.camion_anterior_id::text, 2) || '>' || right(c.camion_nuevo_id::text, 2) || '|' || c.motivo
          || '|' || c.actor_id::text || '|' || c.tipo_operacion
     from public.correcciones_jornada c where c.operacion_id = (select v from res where k = 'C1')),
  pg_temp.j(1)::text || '|' || (select v from res where k = 'C1')::text || '|2999-08-01>2999-08-02|01>02|Error de tipeo|'
  || pg_temp.u(1)::text || '|correccion_jornada',
  'I1/caso 10: historial de correcciones con fecha y camión anteriores y nuevos, motivo recortado, operación y actor');
select ok(
  (select count(*) from public.movimientos_stock) = (select movs from antes)
  and (select count(*) from public.reasignaciones_vendedor) = (select reas from antes)
  and (select count(*) from public.correcciones_jornada) = (select corr from antes) + 1,
  'I1/caso 10: un historial de corrección; sin movimientos; historial de reasignaciones sin cambios');
-- §2.4.5: el par anterior (c1, F) queda libre; también la fecha anterior de V5.
select pg_temp.como_usuario(pg_temp.u(1));
insert into res select 'A1', public.abrir_jornada(pg_temp.k(202), pg_temp.c(1), pg_temp.f(0), pg_temp.u(5));
reset role;
select is(pg_temp.jor((select v from res where k = 'A1')), '01/2999-08-01/05/abierta',
  '§2.4.5: el par anterior (camión, fecha) queda libre y admite una apertura nueva');

-- ===========================================================================
-- 5. Idempotencia (I2, I5, I6, I12)
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario(pg_temp.u(1));
insert into res select 'R1', public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), pg_temp.c(2), '  Error de tipeo  ');
insert into res select 'R2', public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), pg_temp.c(2), 'Error de tipeo');
insert into res select 'R3', public.corregir_jornada(pg_temp.k(201), 'AAAAAAAA-4400-4000-8000-0000000A0001', pg_temp.f(1), 'AAAAAAAA-4400-4000-8000-0000000C0002', ' Error de tipeo ');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(2), pg_temp.c(2), 'Error de tipeo')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otra fecha');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), pg_temp.c(5), 'Error de tipeo')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otro camión');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), pg_temp.c(2), 'Otro motivo')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otro motivo');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(4), pg_temp.f(1), pg_temp.c(2), 'Error de tipeo')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave, otra jornada');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), pg_temp.c(2), 'ERROR DE TIPEO')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I12: motivo en mayúsculas = conflicto');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), pg_temp.c(2), 'Error  de tipeo')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I12: espacios internos distintos = conflicto');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), null, pg_temp.c(2), 'Error de tipeo')$q$, 'PT400', 'jornada_fecha_invalida', 'I5: fecha nula con la clave usada: PT400 antes del replay');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), pg_temp.c(2), ' ')$q$, 'PT400', 'jornada_motivo_invalido', 'I5: motivo vacío con la clave usada: PT400 antes del replay');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), null, pg_temp.f(1), pg_temp.c(2), 'Error de tipeo')$q$, 'PT404', 'jornada_no_encontrada', 'I5: jornada nula con la clave usada: PT404 antes del replay');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), null, 'Error de tipeo')$q$, 'PT404', 'jornada_camion_no_encontrado', 'I5: camión nulo con la clave usada: PT404 antes del replay');
reset role;
select is((select v from res where k = 'R1'), (select v from res where k = 'C1'), 'I2: replay idéntico devuelve la misma operación, sin revalidar (la jornada ya tiene los valores nuevos)');
select ok((select v from res where k = 'R2') = (select v from res where k = 'C1') and (select v from res where k = 'R3') = (select v from res where k = 'C1'),
  'I12: motivo con espacios laterales distintos y uuid en mayúsculas = replay');
select ok(pg_temp.igual(), 'I2/I5/I6/I12: sin filas nuevas ni cambios en las jornadas');

-- ===========================================================================
-- 6. Rechazos de negocio (casos 11, 12 y 24) y precedencia del paso 10
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario(pg_temp.u(1));
select throws_ok($q$select public.corregir_jornada(pg_temp.k(301), pg_temp.j(4), pg_temp.f(5), pg_temp.c(10), 'x')$q$, 'PT409', 'jornada_duplicada', 'caso 11: hacia un par (camión, fecha) ocupado por una jornada CERRADA');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(302), pg_temp.j(4), pg_temp.f(1), pg_temp.c(2), 'x')$q$, 'PT409', 'jornada_duplicada', 'caso 11: hacia un par ocupado por una jornada abierta (duplicada precede a camión con jornada abierta)');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(303), pg_temp.j(4), '2000-01-01', pg_temp.c(6), 'x')$q$, 'PT400', 'jornada_fecha_invalida', 'caso 11: hacia una fecha pasada');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(304), pg_temp.j(4), pg_temp.hoy() - 1, pg_temp.c(6), 'x')$q$, 'PT400', 'jornada_fecha_invalida', 'caso 11: hacia el día anterior al operativo actual (America/Argentina/Tucuman)');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(305), pg_temp.j(4), pg_temp.f(0), pg_temp.c(12), 'x')$q$, 'PT409', 'jornada_camion_inactivo', 'casos 11 y 24: hacia un camión inactivo');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(306), pg_temp.j(4), pg_temp.f(6), pg_temp.c(1), 'x')$q$, 'PT409', 'jornada_camion_con_jornada_abierta', 'caso 11: hacia un camión con otra jornada sin cerrar (otra fecha)');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(307), pg_temp.j(4), pg_temp.f(7), pg_temp.c(6), 'x')$q$, 'PT409', 'jornada_vendedor_ocupado', 'caso 11: el vendedor vigente ya tiene jornada en la fecha nueva');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(308), pg_temp.j(4), pg_temp.f(0), pg_temp.c(6), 'Otro motivo')$q$, 'PT409', 'jornada_sin_cambios', 'sin cambios de fecha ni de camión (aunque cambie el motivo)');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(309), pg_temp.j(4), '2000-01-01', pg_temp.c(12), 'x')$q$, 'PT400', 'jornada_fecha_invalida', 'precedencia: la fecha final precede al camión final');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(310), pg_temp.j(4), pg_temp.f(7), pg_temp.c(1), 'x')$q$, 'PT409', 'jornada_camion_con_jornada_abierta', 'precedencia: camión con jornada abierta precede a vendedor ocupado');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(311), pg_temp.j(7), pg_temp.f(4), pg_temp.c(9), 'x')$q$, 'PT409', 'jornada_con_movimientos', 'defensa en profundidad: jornada abierta con un movimiento asociado');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(312), pg_temp.j(7), '2000-01-01', pg_temp.c(12), 'x')$q$, 'PT409', 'jornada_con_movimientos', 'precedencia: los movimientos preceden a la fecha y al camión');
-- Decisión 2: la fecha y el camión finales se revalidan aunque no cambien.
select throws_ok($q$select public.corregir_jornada(pg_temp.k(313), pg_temp.j(10), date '2000-01-02', pg_temp.c(18), 'x')$q$, 'PT400', 'jornada_fecha_invalida', 'decisión 2: sólo cambia el camión, pero la fecha (sin cambiar) ya pasó');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(314), pg_temp.j(10), date '2000-01-02', pg_temp.c(15), 'x')$q$, 'PT400', 'jornada_fecha_invalida', 'precedencia: fecha pasada precede a sin cambios');
reset role;
update public.camiones set activo = false where id = pg_temp.c(14);
select pg_temp.fijar();
select pg_temp.como_usuario(pg_temp.u(1));
select throws_ok($q$select public.corregir_jornada(pg_temp.k(315), pg_temp.j(9), pg_temp.f(14), pg_temp.c(14), 'x')$q$, 'PT409', 'jornada_camion_inactivo', 'decisión 2 (caso 24): sólo cambia la fecha, pero el camión (sin cambiar) está de baja');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(316), pg_temp.j(9), pg_temp.f(12), pg_temp.c(14), 'x')$q$, 'PT409', 'jornada_camion_inactivo', 'precedencia: camión inactivo precede a sin cambios');
reset role;
select ok(pg_temp.igual(), 'casos 11, 12 y 24: los rechazos no dejaron filas ni cambiaron las jornadas');
select ok((select bool_and(pg_temp.sin_clave(pg_temp.k(n))) from generate_series(301, 316) n),
  'los rechazos de negocio no reservaron ninguna de sus claves');
-- Caso 24 (positivo): una jornada de un camión dado de baja puede corregirse HACIA
-- un camión activo.
select pg_temp.como_usuario(pg_temp.u(1));
insert into res select 'C9', public.corregir_jornada(pg_temp.k(317), pg_temp.j(9), pg_temp.f(12), pg_temp.c(18), 'Camión de baja');
reset role;
select is(pg_temp.jor(pg_temp.j(9)), '18/2999-08-13/06/abierta', 'caso 24: desde un camión dado de baja hacia uno activo, admitido');

-- ===========================================================================
-- 7. Sólo fecha, sólo camión, hacia hoy y vendedor inactivo (caso 10); I4, I8, I9
-- ===========================================================================
select pg_temp.como_usuario(pg_temp.u(2));
insert into res select 'E2', public.corregir_jornada(pg_temp.k(201), pg_temp.j(2), pg_temp.f(2), pg_temp.c(3), 'Fecha equivocada');
reset role;
select ok((select v from res where k = 'E2') <> (select v from res where k = 'C1')
          and (select o.actor_id from public.operaciones o where o.id = (select v from res where k = 'E2')) = pg_temp.u(2)
          and pg_temp.jor(pg_temp.j(2)) = '03/2999-08-03/06/abierta',
  'I8/caso 10: la misma clave usada por otro actor (encargado) es una operación nueva; sólo cambia la fecha');
select pg_temp.como_usuario(pg_temp.u(1));
insert into res select 'I9', public.corregir_jornada(pg_temp.k(303), pg_temp.j(3), pg_temp.f(0), pg_temp.c(5), 'Otro camión');
insert into res select 'HOY', public.corregir_jornada(pg_temp.k(318), pg_temp.j(8), pg_temp.hoy(), pg_temp.c(11), 'Sale hoy');
insert into res select 'V11', public.corregir_jornada(pg_temp.k(319), pg_temp.j(11), pg_temp.f(14), pg_temp.c(16), 'Vendedor de baja');
reset role;
select is(pg_temp.jor(pg_temp.j(3)), '05/2999-08-01/07/abierta',
  'I9/caso 10: la clave de un rechazo se usa con un payload válido como primera ejecución; sólo cambia el camión');
select is(pg_temp.jor(pg_temp.j(8)), '11/' || pg_temp.hoy()::text || '/03/abierta', 'caso 10: hacia el día operativo actual, admitido');
select is(pg_temp.jor(pg_temp.j(11)), '16/2999-08-15/04/abierta', 'decisión 3: no se exige que el vendedor vigente esté activo; no se lo modifica');
update public.perfiles set activo = false where usuario_id = pg_temp.u(2);
select pg_temp.fijar();
select pg_temp.como_usuario(pg_temp.u(2));
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(2), pg_temp.f(2), pg_temp.c(3), 'Fecha equivocada')$q$, 'PT403', 'jornada_no_autorizado', 'I4: replay con autorización perdida: PT403');
reset role;
update public.perfiles set activo = true where usuario_id = pg_temp.u(2);
select ok(pg_temp.igual(), 'I4: sin efectos');

-- ===========================================================================
-- 8. J5: corregida, cargada, descargada y en reparto (I3, I7, casos 12 y 22)
-- ===========================================================================
select pg_temp.como_usuario(pg_temp.u(1));
insert into res select 'C5', public.corregir_jornada(pg_temp.k(401), pg_temp.j(5), pg_temp.f(3), pg_temp.c(7), 'Reprogramada');
insert into res select 'K5', public.registrar_carga(pg_temp.k(402), pg_temp.j(5), array['aaaaaaaa-4400-4000-8000-0000000f0001']::uuid[], array[5]);
insert into res select 'D5', public.registrar_descarga(pg_temp.k(403), pg_temp.j(5), array['aaaaaaaa-4400-4000-8000-0000000f0001']::uuid[], array[2], 'Sobrante');
insert into res select 'RE', public.reasignar_vendedor(pg_temp.k(404), pg_temp.j(22), pg_temp.u(7));
reset role;
select pg_temp.fijar();
select pg_temp.como_usuario(pg_temp.u(1));
select is(public.corregir_jornada(pg_temp.k(401), pg_temp.j(5), pg_temp.f(3), pg_temp.c(7), 'Reprogramada'),
  (select v from res where k = 'C5'), 'I3: replay con la jornada ya cargada devuelve la operación original, sin revalidar');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(405), pg_temp.j(5), pg_temp.f(4), pg_temp.c(7), 'x')$q$, 'PT409', 'jornada_estado_invalido', 'caso 12: corrección en cargada (el estado precede a los movimientos)');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(402), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una carga');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(403), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una descarga');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(404), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una reasignación');
select throws_ok($q$select public.corregir_jornada(pg_temp.j(4), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una apertura');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(1), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de un ingreso de Stock');
select throws_ok($q$select public.registrar_carga(pg_temp.k(201), pg_temp.j(4), array['aaaaaaaa-4400-4000-8000-0000000f0001']::uuid[], array[1])$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: registrar_carga con la clave de una corrección');
select throws_ok($q$select public.registrar_merma(pg_temp.k(201), 'aaaaaaaa-4400-4000-8000-0000000f0001', 'aaaaaaaa-4400-4000-8000-0000000d0001', 1, 'vencido', null)$q$, 'PT409', 'stock_conflicto_idempotencia', 'I7 (regresión): registrar_merma con una clave de corrección sigue respondiendo stock_conflicto_idempotencia');
select throws_ok($q$select public.mover_a_cuarentena(pg_temp.k(201), 'aaaaaaaa-4400-4000-8000-0000000f0001', 'aaaaaaaa-4400-4000-8000-0000000d0001', 1, 'x')$q$, 'PT409', 'stock_conflicto_idempotencia', 'I7 (regresión): mover_a_cuarentena con una clave de corrección sigue respondiendo stock_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual() and pg_temp.sin_clave(pg_temp.k(405)), 'I3/I7/caso 12: sin filas nuevas ni cambios');
select pg_temp.como_usuario(pg_temp.u(1));
insert into res select 'S5', public.confirmar_salida(pg_temp.k(406), pg_temp.j(5));
select throws_ok($q$select public.corregir_jornada(pg_temp.k(406), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una salida');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(407), pg_temp.j(5), pg_temp.f(4), pg_temp.c(8), 'x')$q$, 'PT409', 'jornada_estado_invalido', 'caso 22: corrección en en_reparto');
select is(public.corregir_jornada(pg_temp.k(401), pg_temp.j(5), pg_temp.f(3), pg_temp.c(7), ' Reprogramada '),
  (select v from res where k = 'C5'), 'I3: replay con la jornada en_reparto devuelve la operación original');
reset role;
select is(pg_temp.jor(pg_temp.j(5)), '07/2999-08-04/09/en_reparto', 'J5: conserva la corrección y llega a en_reparto');

-- ===========================================================================
-- 9. Flujo real: apertura → corrección → carga → salida (I-CAMION)
-- ===========================================================================
select pg_temp.como_usuario(pg_temp.u(1));
insert into res select 'FA', public.abrir_jornada(pg_temp.k(501), pg_temp.c(8), pg_temp.f(9), pg_temp.u(7));
insert into res select 'FC', public.corregir_jornada(pg_temp.k(503), (select v from res where k = 'FA'), pg_temp.f(10), pg_temp.c(19), 'Cambio de camión');
insert into res select 'FK', public.registrar_carga(pg_temp.k(504), (select v from res where k = 'FA'),
  array['aaaaaaaa-4400-4000-8000-0000000f0001']::uuid[], array[6]);
insert into res select 'FS', public.confirmar_salida(pg_temp.k(505), (select v from res where k = 'FA'));
reset role;
select is(pg_temp.jor((select v from res where k = 'FA')), '19/2999-08-11/07/en_reparto',
  'flujo real: abierta → corregida (c19, F+10) → cargada → en_reparto');
select is(
  (select string_agg(m.cantidad::text || ':' || right(m.ubicacion_destino_id::text, 2), ',')
     from public.movimientos_stock m where m.operacion_id = (select v from res where k = 'FK')),
  '6:19', 'flujo real (I-CAMION): la carga posterior va a la ubicación del camión corregido');
select pg_temp.fijar();
select pg_temp.como_usuario(pg_temp.u(1));
select throws_ok(format($q$select public.corregir_jornada(pg_temp.k(506), %L, pg_temp.f(11), pg_temp.c(19), 'x')$q$, (select v from res where k = 'FA')),
  'PT409', 'jornada_estado_invalido', 'flujo real (caso 22): corrección después de la salida');
select is(public.corregir_jornada(pg_temp.k(503), (select v from res where k = 'FA'), pg_temp.f(10), pg_temp.c(19), 'Cambio de camión'),
  (select v from res where k = 'FC'), 'flujo real: replay de la corrección después de la salida devuelve la operación original');
reset role;
select ok(pg_temp.igual() and pg_temp.sin_clave(pg_temp.k(506)), 'flujo real: el rechazo y el replay no dejaron efectos');

-- ===========================================================================
-- 10. Invariantes finales
-- ===========================================================================
select ok(
  not exists (select 1 from public.jornadas group by empresa_id, camion_id, fecha having count(*) > 1)
  and not exists (select 1 from public.jornadas group by empresa_id, vendedor_id, fecha having count(*) > 1)
  and not exists (select 1 from public.jornadas where estado <> 'cerrada' group by empresa_id, camion_id having count(*) > 1),
  'I-J1: a lo sumo una jornada por (camión, fecha) y por (vendedor, fecha), y una sin cerrar por camión');
select is(
  (select count(*)::int from public.operaciones o where o.tipo = 'correccion_jornada'
      and not exists (select 1 from public.correcciones_jornada c where c.operacion_id = o.id))
  + (select count(*)::int from public.correcciones_jornada c
      where not exists (select 1 from public.operaciones o where o.id = c.operacion_id and o.tipo = 'correccion_jornada')),
  0, 'una fila de historial por operación de corrección confirmada, y ninguna sin operación');
select is((select count(*)::int from public.correcciones_jornada where empresa_id = 'aaaaaaaa-4400-4000-8000-000000000000'), 8,
  'ocho correcciones confirmadas en A (J1, J9, J2 del encargado, J3, J8, J11, J5 y la del flujo real); ninguna de las rechazadas');
select is(
  (select (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.jornadas t
            where t.empresa_id = 'bbbbbbbb-4400-4000-8000-000000000000')
          || '/' || (select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.operaciones t
                      where t.empresa_id = 'bbbbbbbb-4400-4000-8000-000000000000')
          || '/' || (select count(*)::text from public.correcciones_jornada t
                      where t.empresa_id = 'bbbbbbbb-4400-4000-8000-000000000000')),
  (select h from huella_b), 'aislamiento: jornadas, operaciones y correcciones de B sin cambios');

-- ===========================================================================
-- 11. E-SL1: sólo lectura (GET/HEAD) → 25006 antes de todo, también en replay
-- ===========================================================================
select pg_temp.fijar();
select pg_temp.como_usuario(pg_temp.u(1));
set local transaction_read_only = on;
select throws_ok($q$select public.corregir_jornada(pg_temp.k(601), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave nueva: 25006');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(1), pg_temp.c(2), 'Error de tipeo')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave usada y misma huella: 25006, no el uuid guardado');
select throws_ok($q$select public.corregir_jornada(pg_temp.k(201), pg_temp.j(1), pg_temp.f(2), pg_temp.c(2), 'Error de tipeo')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura, clave usada y otra huella: 25006, no PT409');
reset role;
select pg_temp.como_usuario(pg_temp.u(3));
select throws_ok($q$select public.corregir_jornada(pg_temp.k(602), pg_temp.j(4), pg_temp.f(1), pg_temp.c(6), 'x')$q$, '25006', 'jornada_metodo_no_permitido', 'E-SL1: sólo lectura con vendedor_piloto: 25006, no PT403');
reset role;
select ok(pg_temp.igual() and pg_temp.sin_clave(pg_temp.k(601)), 'E-SL1: el rechazo por sólo lectura no reserva la clave ni deja efectos');

select * from finish();

rollback;
