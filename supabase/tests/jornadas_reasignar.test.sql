-- pgTAP: T2 — RPC reasignar_vendedor (Blueprint §7.5, §9, §10, §12; ADR-007 §2.2, §2.3 y §7
-- casos 8, 9, 22 y 23; ADR-001 §18.4.2, §18.4.3, §18.4.4, §18.4.5, §18.4.7 y §18.4.9,
-- grupos S, P e I). Ejecutar sólo en local.
--
-- B es un fixture adversarial (aislamiento por empresa_id). Las jornadas de prueba se abren con
-- la RPC abrir_jornada de T1. La concurrencia (I10, I11 y K1 a K9) NO se prueba acá: queda para
-- el arnés de T3 y no se declara aprobada por este archivo. El estado cargada, en_reparto y
-- cerrada se fija como owner (fixture controlado) porque las RPC de carga, salida y cierre aún
-- no existen; se repite con el flujo real en T5 y T7. La guarda de aislamiento se prueba en
-- jornadas_reasignar_aislamiento.test.sql.

begin;

create extension if not exists pgtap with schema extensions;

select plan(148);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------

insert into public.empresas (id, nombre) values
  ('aaaaaaaa-2100-4000-8000-000000000000', 'Empresa A (test)'),
  ('bbbbbbbb-2100-4000-8000-000000000000', 'Empresa B (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-2100-4000-8000-000000000001', 'authenticated', 'authenticated', 'jr.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000002', 'authenticated', 'authenticated', 'jr.a2@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000003', 'authenticated', 'authenticated', 'jr.a3@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000004', 'authenticated', 'authenticated', 'jr.a4@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000005', 'authenticated', 'authenticated', 'jr.a5@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000006', 'authenticated', 'authenticated', 'jr.a6@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000007', 'authenticated', 'authenticated', 'jr.a7@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000008', 'authenticated', 'authenticated', 'jr.a8@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000009', 'authenticated', 'authenticated', 'jr.a9@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000010', 'authenticated', 'authenticated', 'jr.a10@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000011', 'authenticated', 'authenticated', 'jr.a11@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000012', 'authenticated', 'authenticated', 'jr.a12@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000013', 'authenticated', 'authenticated', 'jr.a13@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-2100-4000-8000-000000000014', 'authenticated', 'authenticated', 'jr.a14@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-2100-4000-8000-000000000001', 'authenticated', 'authenticated', 'jr.b1@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-2100-4000-8000-000000000002', 'authenticated', 'authenticated', 'jr.b2@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-2100-4000-8000-000000000003', 'authenticated', 'authenticated', 'jr.b3@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-2100-4000-8000-000000000001', 'authenticated', 'authenticated', 'jr.n1@usuarios.distribuidora.invalid', '{"rol":"dueno","empresa_id":"aaaaaaaa-2100-4000-8000-000000000000"}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-2100-4000-8000-000000000001', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-2100-4000-8000-000000000002', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-2100-4000-8000-000000000003', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-2100-4000-8000-000000000004', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a4', 'A4', 'dueno', false),
  ('aaaaaaaa-2100-4000-8000-000000000005', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a5', 'A5', 'vendedor_piloto', false),
  ('aaaaaaaa-2100-4000-8000-000000000006', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a6', 'A6', 'vendedor_piloto', true),
  ('aaaaaaaa-2100-4000-8000-000000000007', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a7', 'A7', 'vendedor_piloto', true),
  ('aaaaaaaa-2100-4000-8000-000000000008', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a8', 'A8', 'encargado', true),
  ('aaaaaaaa-2100-4000-8000-000000000009', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a9', 'A9', 'vendedor_piloto', true),
  ('aaaaaaaa-2100-4000-8000-000000000010', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a10', 'A10', 'vendedor_piloto', true),
  ('aaaaaaaa-2100-4000-8000-000000000011', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a11', 'A11', 'vendedor_piloto', true),
  ('aaaaaaaa-2100-4000-8000-000000000012', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a12', 'A12', 'vendedor_piloto', true),
  ('aaaaaaaa-2100-4000-8000-000000000013', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a13', 'A13', 'vendedor_piloto', true),
  ('aaaaaaaa-2100-4000-8000-000000000014', 'aaaaaaaa-2100-4000-8000-000000000000', 'jr.a14', 'A14', 'vendedor_piloto', true),
  ('bbbbbbbb-2100-4000-8000-000000000001', 'bbbbbbbb-2100-4000-8000-000000000000', 'jr.b1', 'B1', 'dueno', true),
  ('bbbbbbbb-2100-4000-8000-000000000002', 'bbbbbbbb-2100-4000-8000-000000000000', 'jr.b2', 'B2', 'vendedor_piloto', true),
  ('bbbbbbbb-2100-4000-8000-000000000003', 'bbbbbbbb-2100-4000-8000-000000000000', 'jr.b3', 'B3', 'vendedor_piloto', true);

insert into public.camiones (id, empresa_id, patente, nombre, creado_por) values
  ('aaaaaaaa-2100-4000-8000-0000000000c1', 'aaaaaaaa-2100-4000-8000-000000000000', 'JR-01', 'Camión A1', 'aaaaaaaa-2100-4000-8000-000000000001'),
  ('aaaaaaaa-2100-4000-8000-0000000000c2', 'aaaaaaaa-2100-4000-8000-000000000000', 'JR-02', 'Camión A2', 'aaaaaaaa-2100-4000-8000-000000000001'),
  ('aaaaaaaa-2100-4000-8000-0000000000c3', 'aaaaaaaa-2100-4000-8000-000000000000', 'JR-03', 'Camión A3', 'aaaaaaaa-2100-4000-8000-000000000001'),
  ('aaaaaaaa-2100-4000-8000-0000000000c4', 'aaaaaaaa-2100-4000-8000-000000000000', 'JR-04', 'Camión A4', 'aaaaaaaa-2100-4000-8000-000000000001'),
  ('aaaaaaaa-2100-4000-8000-0000000000c5', 'aaaaaaaa-2100-4000-8000-000000000000', 'JR-05', 'Camión A5', 'aaaaaaaa-2100-4000-8000-000000000001'),
  ('aaaaaaaa-2100-4000-8000-0000000000c6', 'aaaaaaaa-2100-4000-8000-000000000000', 'JR-06', 'Camión A6', 'aaaaaaaa-2100-4000-8000-000000000001'),
  ('aaaaaaaa-2100-4000-8000-0000000000c7', 'aaaaaaaa-2100-4000-8000-000000000000', 'JR-07', 'Camión A7', 'aaaaaaaa-2100-4000-8000-000000000001'),
  ('aaaaaaaa-2100-4000-8000-0000000000c8', 'aaaaaaaa-2100-4000-8000-000000000000', 'JR-08', 'Camión A8', 'aaaaaaaa-2100-4000-8000-000000000001'),
  ('aaaaaaaa-2100-4000-8000-0000000000c9', 'aaaaaaaa-2100-4000-8000-000000000000', 'JR-09', 'Camión A9', 'aaaaaaaa-2100-4000-8000-000000000001'),
  ('aaaaaaaa-2100-4000-8000-0000000000ca', 'aaaaaaaa-2100-4000-8000-000000000000', 'JR-10', 'Camión A10', 'aaaaaaaa-2100-4000-8000-000000000001'),
  ('bbbbbbbb-2100-4000-8000-0000000000c1', 'bbbbbbbb-2100-4000-8000-000000000000', 'JR-B1', 'Camión B1', 'bbbbbbbb-2100-4000-8000-000000000001');

insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('aaaaaaaa-2100-4000-8000-0000000000d1', 'aaaaaaaa-2100-4000-8000-000000000000', 'deposito', null);

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('aaaaaaaa-2100-4000-8000-0000000000f1', 'aaaaaaaa-2100-4000-8000-000000000000', 'JR-A1', 'Leche A', 'lacteos', 'unidad', 100, true, 'aaaaaaaa-2100-4000-8000-000000000001');

create function pg_temp.como_usuario(uid uuid, metadata jsonb default '{}')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated', 'user_metadata', metadata)::text, true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.sin_sub() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.como_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
end $$;
create function pg_temp.como_service_role() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
end $$;
create function pg_temp.hoy() returns date language sql as $$
  select (now() at time zone 'America/Argentina/Tucuman')::date
$$;
-- Conteo de filas relacionadas con jornadas, leído como owner (SECURITY DEFINER).
create function pg_temp.conteo()
returns text language sql security definer set search_path = '' as $$
  select (select count(*) from public.operaciones)::text
    || ',' || (select count(*) from public.jornadas)::text
    || ',' || (select count(*) from public.movimientos_stock)::text
    || ',' || (select count(*) from public.reasignaciones_vendedor)::text
    || ',' || (select count(*) from public.correcciones_jornada)::text
$$;
create temp table snap (v text);
grant select, insert, delete on snap to public;
create function pg_temp.fijar() returns void language sql security definer set search_path = '' as $$
  delete from pg_temp.snap;
  insert into pg_temp.snap select pg_temp.conteo();
$$;
create function pg_temp.igual() returns boolean language sql security definer set search_path = '' as $$
  select pg_temp.conteo() = (select v from pg_temp.snap)
$$;
-- Suma deltas a las cinco posiciones del conteo: operaciones, jornadas, movimientos, reasignaciones, correcciones.
create function pg_temp.mas(c text, d1 int, d2 int, d3 int, d4 int, d5 int)
returns text language sql as $$
  select (split_part(c, ',', 1)::int + d1)::text || ',' || (split_part(c, ',', 2)::int + d2)::text
    || ',' || (split_part(c, ',', 3)::int + d3)::text || ',' || (split_part(c, ',', 4)::int + d4)::text
    || ',' || (split_part(c, ',', 5)::int + d5)::text
$$;
create function pg_temp.huella_reasignacion(jornada uuid, vendedor uuid)
returns text language sql as $$
  select encode(sha256(convert_to('v1|reasignacion_vendedor|' || jornada::text || '|' || vendedor::text, 'UTF8')), 'hex')
$$;
grant execute on function pg_temp.como_usuario(uuid, jsonb) to public;
grant execute on function pg_temp.sin_sub() to public;
grant execute on function pg_temp.como_anon() to public;
grant execute on function pg_temp.como_service_role() to public;
grant execute on function pg_temp.hoy() to public;
grant execute on function pg_temp.conteo() to public;
grant execute on function pg_temp.fijar() to public;
grant execute on function pg_temp.igual() to public;
grant execute on function pg_temp.mas(text, int, int, int, int, int) to public;
grant execute on function pg_temp.huella_reasignacion(uuid, uuid) to public;
create temp table res (k text, v uuid);
grant select, insert on res to public;

-- ---------------------------------------------------------------------------
-- 0. Jornadas de prueba (abiertas con abrir_jornada de T1) y fixtures de estado
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J1', public.abrir_jornada('22220000-2100-4000-8000-000000000901', 'aaaaaaaa-2100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-2100-4000-8000-000000000003')$q$, 'fixture: J1 abierta por la RPC de T1');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J2', public.abrir_jornada('22220000-2100-4000-8000-000000000902', 'aaaaaaaa-2100-4000-8000-0000000000c2', pg_temp.hoy() + 1, 'aaaaaaaa-2100-4000-8000-000000000006')$q$, 'fixture: J2 abierta por la RPC de T1');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J3', public.abrir_jornada('22220000-2100-4000-8000-000000000903', 'aaaaaaaa-2100-4000-8000-0000000000c3', pg_temp.hoy() + 2, 'aaaaaaaa-2100-4000-8000-000000000007')$q$, 'fixture: J3 abierta por la RPC de T1');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J4', public.abrir_jornada('22220000-2100-4000-8000-000000000904', 'aaaaaaaa-2100-4000-8000-0000000000c4', pg_temp.hoy() + 3, 'aaaaaaaa-2100-4000-8000-000000000008')$q$, 'fixture: J4 abierta por la RPC de T1');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J5', public.abrir_jornada('22220000-2100-4000-8000-000000000905', 'aaaaaaaa-2100-4000-8000-0000000000c5', pg_temp.hoy() + 4, 'aaaaaaaa-2100-4000-8000-000000000009')$q$, 'fixture: J5 abierta por la RPC de T1');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J6', public.abrir_jornada('22220000-2100-4000-8000-000000000906', 'aaaaaaaa-2100-4000-8000-0000000000c6', pg_temp.hoy() + 4, 'aaaaaaaa-2100-4000-8000-000000000010')$q$, 'fixture: J6 abierta por la RPC de T1');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J8', public.abrir_jornada('22220000-2100-4000-8000-000000000907', 'aaaaaaaa-2100-4000-8000-0000000000c7', pg_temp.hoy() + 5, 'aaaaaaaa-2100-4000-8000-000000000009')$q$, 'fixture: J8 abierta por la RPC de T1');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J9', public.abrir_jornada('22220000-2100-4000-8000-000000000908', 'aaaaaaaa-2100-4000-8000-0000000000c8', pg_temp.hoy() + 6, 'aaaaaaaa-2100-4000-8000-000000000011')$q$, 'fixture: J9 abierta por la RPC de T1');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J10', public.abrir_jornada('22220000-2100-4000-8000-000000000909', 'aaaaaaaa-2100-4000-8000-0000000000c9', pg_temp.hoy() + 7, 'aaaaaaaa-2100-4000-8000-000000000013')$q$, 'fixture: J10 abierta por la RPC de T1');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J11', public.abrir_jornada('22220000-2100-4000-8000-000000000910', 'aaaaaaaa-2100-4000-8000-0000000000ca', pg_temp.hoy() + 8, 'aaaaaaaa-2100-4000-8000-000000000014')$q$, 'fixture: J11 abierta por la RPC de T1');
reset role;
select pg_temp.como_usuario('bbbbbbbb-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'JB', public.abrir_jornada('22220000-2100-4000-8000-000000000911', 'bbbbbbbb-2100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'bbbbbbbb-2100-4000-8000-000000000002')$q$, 'fixture: JB de la empresa B');
reset role;
update public.jornadas set estado = 'cargada' where id = (select v from res where k = 'J3');
update public.jornadas set estado = 'en_reparto' where id = (select v from res where k = 'J4');
update public.jornadas set estado = 'cerrada' where id = (select v from res where k = 'J5');
-- ---------------------------------------------------------------------------
-- 1. Catálogo: dos funciones, ACL, owner, search_path, sin sobrecargas
-- ---------------------------------------------------------------------------
select is((select count(*)::int from pg_proc where proname = 'reasignar_vendedor' and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)), 2,
  'reasignar_vendedor existe una sola vez en public y una en privado, sin sobrecargas');
select ok(exists (select 1 from pg_proc p where p.oid = 'privado.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure
     and p.prosecdef and p.proowner = 'propietario_rpc'::regrole and p.proconfig @> array['search_path=""'] and p.provolatile = 'v'
     and p.prorettype = 'uuid'::regtype and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
     and array(select a::text from unnest(p.proacl) a order by 1) = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']),
  'privado.reasignar_vendedor: SECURITY DEFINER, owner propietario_rpc, search_path vacío, VOLATILE, devuelve uuid y ACL exacta');
select ok(exists (select 1 from pg_proc p where p.oid = 'public.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure
     and not p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""'] and p.provolatile = 'v'
     and p.prorettype = 'uuid'::regtype and p.prolang = (select oid from pg_language where lanname = 'sql')
     and array(select a::text from unnest(p.proacl) a order by 1) = array['authenticated=X/postgres', 'postgres=X/postgres']),
  'public.reasignar_vendedor: SECURITY INVOKER, owner postgres, search_path vacío, VOLATILE, devuelve uuid y ACL exacta');
select is((select p.proargnames from pg_proc p where p.oid = 'public.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure),
  array['p_idempotency_key', 'p_jornada_id', 'p_vendedor_id'], 'los parámetros se llaman p_idempotency_key, p_jornada_id y p_vendedor_id');
select ok((select p.prosrc from pg_proc p where p.oid = 'public.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure)
    ~ 'privado\.reasignar_vendedor\(p_idempotency_key, p_jornada_id, p_vendedor_id\)'
  and (select p.prosrc from pg_proc p where p.oid = 'public.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure) !~* 'insert|update|delete',
  'la fachada sólo delega en la implementación');
select ok(not has_function_privilege('anon', 'public.reasignar_vendedor(uuid, uuid, uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.reasignar_vendedor(uuid, uuid, uuid)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'public.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure and a.grantee = 0)
  and has_function_privilege('authenticated', 'public.reasignar_vendedor(uuid, uuid, uuid)', 'execute'),
  'fachada: EXECUTE sólo para authenticated (ni PUBLIC, ni anon, ni service_role)');
select ok(not has_function_privilege('anon', 'privado.reasignar_vendedor(uuid, uuid, uuid)', 'execute')
  and not has_function_privilege('service_role', 'privado.reasignar_vendedor(uuid, uuid, uuid)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'privado.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure and a.grantee = 0)
  and has_function_privilege('authenticated', 'privado.reasignar_vendedor(uuid, uuid, uuid)', 'execute'),
  'implementación: EXECUTE sólo para authenticated (ni PUBLIC, ni anon, ni service_role)');
select ok(not has_schema_privilege('propietario_rpc', 'privado', 'create') and not has_schema_privilege('propietario_rpc', 'public', 'create'),
  'propietario_rpc no conserva CREATE sobre privado ni public tras transferir la propiedad');
select ok((select p.prosrc from pg_proc p where p.oid = 'privado.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure) ~ 'hashtextextended'
  and (select p.prosrc from pg_proc p where p.oid = 'privado.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure) ~* 'for update',
  'la implementación toma advisory locks de vendedor y bloquea la jornada con FOR UPDATE');

-- ---------------------------------------------------------------------------
-- 2. Seguridad: anon, service_role, sin sesión, sin perfil, inactivo, vendedor_piloto, DML directo
-- ---------------------------------------------------------------------------
select pg_temp.como_anon();
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000800', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, '42501', null, 'anon no puede ejecutar la fachada');
reset role;
select pg_temp.como_anon();
select throws_ok($q$select privado.reasignar_vendedor('22220000-2100-4000-8000-000000000800', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, '42501', null, 'anon no puede ejecutar la implementación');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000800', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, '42501', null, 'service_role no puede ejecutar la fachada');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select privado.reasignar_vendedor('22220000-2100-4000-8000-000000000800', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, '42501', null, 'service_role no puede ejecutar la implementación');
reset role;
select pg_temp.fijar();
select pg_temp.sin_sub();
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000800', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT401', 'jornada_no_autenticado', 'sin sub en el JWT: PT401');
reset role;
select ok(pg_temp.igual(), 'sin sub en el JWT: PT401: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('dddddddd-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000800', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT403', 'jornada_no_autorizado', 'cuenta sin perfil (con metadata de dueño de A): PT403');
reset role;
select ok(pg_temp.igual(), 'cuenta sin perfil (con metadata de dueño de A): PT403: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000004');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000800', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT403', 'jornada_no_autorizado', 'dueño con perfil inactivo: PT403');
reset role;
select ok(pg_temp.igual(), 'dueño con perfil inactivo: PT403: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000003');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000800', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT403', 'jornada_no_autorizado', 'vendedor_piloto: PT403');
reset role;
select ok(pg_temp.igual(), 'vendedor_piloto: PT403: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000003', '{"rol":"dueno","empresa_id":"bbbbbbbb-2100-4000-8000-000000000000"}');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000800', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT403', 'jornada_no_autorizado', 'vendedor_piloto con metadata falsa de dueño de otra empresa: PT403');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$update public.jornadas set vendedor_id = 'aaaaaaaa-2100-4000-8000-000000000012'$q$, '42501', null, 'dueño: DML directo #1 rechazado');
select throws_ok($q$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id) values ('aaaaaaaa-2100-4000-8000-000000000000', (select v from res where k = 'J9'), '22220000-2100-4000-8000-000000000001', 'aaaaaaaa-2100-4000-8000-000000000011', 'aaaaaaaa-2100-4000-8000-000000000012', 'aaaaaaaa-2100-4000-8000-000000000001')$q$, '42501', null, 'dueño: DML directo #2 rechazado');
select throws_ok($q$delete from public.reasignaciones_vendedor$q$, '42501', null, 'dueño: DML directo #3 rechazado');
select throws_ok($q$update public.reasignaciones_vendedor set vendedor_nuevo_id = 'aaaaaaaa-2100-4000-8000-000000000012'$q$, '42501', null, 'dueño: DML directo #4 rechazado');
reset role;
-- ---------------------------------------------------------------------------
-- 3. Estructura, recursos de otra empresa o inexistentes: respuesta indistinguible
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor(null, (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT400', 'jornada_clave_invalida', 'I14: clave nula → PT400 jornada_clave_invalida');
reset role;
select ok(pg_temp.igual(), 'I14: clave nula → PT400 jornada_clave_invalida: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000810', (select v from res where k = 'J9'), null)$q$, 'PT400', 'jornada_vendedor_invalido', 'vendedor nulo → PT400 jornada_vendedor_invalido');
reset role;
select ok(pg_temp.igual(), 'vendedor nulo → PT400 jornada_vendedor_invalido: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000811', null, 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT404', 'jornada_no_encontrada', 'jornada nula → PT404 jornada_no_encontrada (D-N1)');
reset role;
select ok(pg_temp.igual(), 'jornada nula → PT404 jornada_no_encontrada (D-N1): sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor(null, null, null)$q$, 'PT400', 'jornada_clave_invalida', 'precedencia del paso 3: clave nula antes que vendedor y jornada nulos');
reset role;
select ok(pg_temp.igual(), 'precedencia del paso 3: clave nula antes que vendedor y jornada nulos: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000812', null, null)$q$, 'PT400', 'jornada_vendedor_invalido', 'precedencia del paso 3: vendedor nulo antes que jornada nula');
reset role;
select ok(pg_temp.igual(), 'precedencia del paso 3: vendedor nulo antes que jornada nula: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000813', (select v from res where k = 'JB'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT404', 'jornada_no_encontrada', 'jornada de otra empresa → PT404 jornada_no_encontrada');
reset role;
select ok(pg_temp.igual(), 'jornada de otra empresa → PT404 jornada_no_encontrada: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000814', 'eeeeeeee-2100-4000-8000-0000000000a1', 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT404', 'jornada_no_encontrada', 'jornada inexistente → el mismo PT404 y el mismo mensaje');
reset role;
select ok(pg_temp.igual(), 'jornada inexistente → el mismo PT404 y el mismo mensaje: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000815', (select v from res where k = 'J9'), 'bbbbbbbb-2100-4000-8000-000000000002')$q$, 'PT404', 'jornada_vendedor_no_encontrado', 'vendedor de otra empresa → PT404 jornada_vendedor_no_encontrado');
reset role;
select ok(pg_temp.igual(), 'vendedor de otra empresa → PT404 jornada_vendedor_no_encontrado: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000816', (select v from res where k = 'J9'), 'eeeeeeee-2100-4000-8000-000000000001')$q$, 'PT404', 'jornada_vendedor_no_encontrado', 'vendedor inexistente → el mismo PT404 y el mismo mensaje');
reset role;
select ok(pg_temp.igual(), 'vendedor inexistente → el mismo PT404 y el mismo mensaje: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('bbbbbbbb-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000817', (select v from res where k = 'J9'), 'bbbbbbbb-2100-4000-8000-000000000003')$q$, 'PT404', 'jornada_no_encontrada', 'dueño de B no reasigna jornadas de A');
reset role;
select ok(pg_temp.igual(), 'dueño de B no reasigna jornadas de A: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select is((select count(*)::int from public.operaciones where idempotency_key in ('22220000-2100-4000-8000-000000000810','22220000-2100-4000-8000-000000000811','22220000-2100-4000-8000-000000000812','22220000-2100-4000-8000-000000000813','22220000-2100-4000-8000-000000000814','22220000-2100-4000-8000-000000000815','22220000-2100-4000-8000-000000000816','22220000-2100-4000-8000-000000000817')), 0,
  'I13: ningún rechazo estructural ni de recurso ajeno reservó su clave');
-- ---------------------------------------------------------------------------
-- 4. Rechazos de negocio: estado, vendedor nuevo, sin cambios y vendedor ocupado (ADR-007 §7, casos 8 y 22)
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000030', (select v from res where k = 'J4'), 'aaaaaaaa-2100-4000-8000-000000000002')$q$, 'PT409', 'jornada_estado_invalido', 'caso 22: reasignación en en_reparto → PT409 jornada_estado_invalido');
reset role;
select ok(pg_temp.igual(), 'caso 22: reasignación en en_reparto → PT409 jornada_estado_invalido: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000031', (select v from res where k = 'J5'), 'aaaaaaaa-2100-4000-8000-000000000002')$q$, 'PT409', 'jornada_estado_invalido', 'reasignación en una jornada cerrada → PT409 jornada_estado_invalido');
reset role;
select ok(pg_temp.igual(), 'reasignación en una jornada cerrada → PT409 jornada_estado_invalido: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000032', (select v from res where k = 'J4'), 'aaaaaaaa-2100-4000-8000-000000000005')$q$, 'PT409', 'jornada_estado_invalido', 'precedencia: el estado de la jornada precede al vendedor inactivo');
reset role;
select ok(pg_temp.igual(), 'precedencia: el estado de la jornada precede al vendedor inactivo: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000033', (select v from res where k = 'J4'), 'eeeeeeee-2100-4000-8000-000000000001')$q$, 'PT409', 'jornada_estado_invalido', 'precedencia: el estado de la jornada precede al vendedor inexistente');
reset role;
select ok(pg_temp.igual(), 'precedencia: el estado de la jornada precede al vendedor inexistente: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000034', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000005')$q$, 'PT400', 'jornada_vendedor_invalido', 'P12: vendedor nuevo inactivo → PT400 jornada_vendedor_invalido');
reset role;
select ok(pg_temp.igual(), 'P12: vendedor nuevo inactivo → PT400 jornada_vendedor_invalido: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000035', (select v from res where k = 'J1'), 'bbbbbbbb-2100-4000-8000-000000000002')$q$, 'PT404', 'jornada_vendedor_no_encontrado', 'P12: vendedor nuevo de otra empresa → PT404 jornada_vendedor_no_encontrado');
reset role;
select ok(pg_temp.igual(), 'P12: vendedor nuevo de otra empresa → PT404 jornada_vendedor_no_encontrado: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000036', (select v from res where k = 'J1'), 'eeeeeeee-2100-4000-8000-000000000001')$q$, 'PT404', 'jornada_vendedor_no_encontrado', 'P12: vendedor nuevo inexistente → el mismo PT404');
reset role;
select ok(pg_temp.igual(), 'P12: vendedor nuevo inexistente → el mismo PT404: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000037', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000003')$q$, 'PT409', 'jornada_sin_cambios', 'T2-1: vendedor nuevo igual al vigente → PT409 jornada_sin_cambios');
reset role;
select ok(pg_temp.igual(), 'T2-1: vendedor nuevo igual al vigente → PT409 jornada_sin_cambios: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000038', (select v from res where k = 'J6'), 'aaaaaaaa-2100-4000-8000-000000000009')$q$, 'PT409', 'jornada_vendedor_ocupado', 'caso 8: vendedor con jornada ese día, aunque esté cerrada → PT409 jornada_vendedor_ocupado');
reset role;
select ok(pg_temp.igual(), 'caso 8: vendedor con jornada ese día, aunque esté cerrada → PT409 jornada_vendedor_ocupado: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000039', (select v from res where k = 'J2'), 'aaaaaaaa-2100-4000-8000-000000000003')$q$, 'PT409', 'jornada_vendedor_ocupado', 'caso 8: vendedor con otra jornada abierta ese día → PT409 jornada_vendedor_ocupado');
reset role;
select ok(pg_temp.igual(), 'caso 8: vendedor con otra jornada abierta ese día → PT409 jornada_vendedor_ocupado: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000040', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000006')$q$, 'PT409', 'jornada_vendedor_ocupado', 'caso 8: intercambio directo (A6 está en J2 el mismo día) → PT409 jornada_vendedor_ocupado');
reset role;
select ok(pg_temp.igual(), 'caso 8: intercambio directo (A6 está en J2 el mismo día) → PT409 jornada_vendedor_ocupado: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
-- ---------------------------------------------------------------------------
-- 5. Reasignación válida: abierta y cargada, efectos exactos (I1) y vendedor anterior libre (caso 9)
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R1', public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000010')$q$, 'dueño reasigna J1 (abierta) del vendedor A3 a A10');
reset role;
select is(pg_temp.conteo(), (select pg_temp.mas(v, 1, 0, 0, 1, 0) from pg_temp.snap), 'I1: la reasignación suma exactamente una operación y una fila de historial; cero jornadas nuevas, movimientos y correcciones');
select is((select row(o.tipo, o.jornada_id, o.actor_id, o.empresa_id, o.huella)::text from public.operaciones o where o.id = (select v from res where k = 'R1')),
  row('reasignacion_vendedor', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000001'::uuid, 'aaaaaaaa-2100-4000-8000-000000000000'::uuid, pg_temp.huella_reasignacion((select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000010'))::text,
  'I1: la operación es reasignacion_vendedor, con la jornada, el actor, la empresa y la huella v1 recalculada aparte');
select is((select row(r.empresa_id, r.jornada_id, r.operacion_id, r.tipo_operacion, r.vendedor_anterior_id, r.vendedor_nuevo_id, r.actor_id)::text
     from public.reasignaciones_vendedor r where r.operacion_id = (select v from res where k = 'R1')),
  row('aaaaaaaa-2100-4000-8000-000000000000'::uuid, (select v from res where k = 'J1'), (select v from res where k = 'R1'), 'reasignacion_vendedor', 'aaaaaaaa-2100-4000-8000-000000000003'::uuid, 'aaaaaaaa-2100-4000-8000-000000000010'::uuid, 'aaaaaaaa-2100-4000-8000-000000000001'::uuid)::text,
  'I1: el historial guarda jornada, operación, vendedor anterior, vendedor nuevo y actor');
select is((select row(j.vendedor_id, j.estado, j.fecha, j.camion_id, j.abierta_por, j.empresa_id)::text from public.jornadas j where j.id = (select v from res where k = 'J1')),
  row('aaaaaaaa-2100-4000-8000-000000000010'::uuid, 'abierta', pg_temp.hoy() + 1, 'aaaaaaaa-2100-4000-8000-0000000000c1'::uuid, 'aaaaaaaa-2100-4000-8000-000000000001'::uuid, 'aaaaaaaa-2100-4000-8000-000000000000'::uuid)::text,
  'I1: sólo cambió jornadas.vendedor_id; estado, fecha, camión y abierta_por intactos');
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R2', public.reasignar_vendedor('22220000-2100-4000-8000-000000000002', (select v from res where k = 'J2'), 'aaaaaaaa-2100-4000-8000-000000000003')$q$, 'caso 9: el vendedor anterior (A3) queda libre ese día y puede recibir otra jornada');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000002');
select lives_ok($q$insert into res select 'R3', public.reasignar_vendedor('22220000-2100-4000-8000-000000000003', (select v from res where k = 'J3'), 'aaaaaaaa-2100-4000-8000-000000000002')$q$, 'encargado reasigna J3 (cargada) y el encargado puede ser el vendedor');
reset role;
select is((select j.estado || ':' || j.vendedor_id::text from public.jornadas j where j.id = (select v from res where k = 'J3')), 'cargada:aaaaaaaa-2100-4000-8000-000000000002', 'caso 9: en cargada la reasignación conserva el estado y cambia el vendedor');
update public.perfiles set activo = false where usuario_id = 'aaaaaaaa-2100-4000-8000-000000000009';
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R4', public.reasignar_vendedor('22220000-2100-4000-8000-000000000004', (select v from res where k = 'J8'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'se reasigna desde un vendedor vigente que ya está inactivo (la baja posterior se admite)');
reset role;
update public.perfiles set activo = false where usuario_id = 'aaaaaaaa-2100-4000-8000-000000000013';
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000041', (select v from res where k = 'J10'), 'aaaaaaaa-2100-4000-8000-000000000013')$q$, 'PT400', 'jornada_vendedor_invalido', 'precedencia: vendedor nuevo inactivo antes que jornada_sin_cambios (nuevo = vigente)');
reset role;
select ok(pg_temp.igual(), 'precedencia: vendedor nuevo inactivo antes que jornada_sin_cambios (nuevo = vigente): sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
-- ---------------------------------------------------------------------------
-- 6. Idempotencia (I2 a I9 e I12 a I14)
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'RR1', public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000010')$q$, 'I2: replay idéntico de la reasignación');
reset role;
select is((select v from res where k = 'RR1'), (select v from res where k = 'R1'), 'I2: el replay devuelve la misma operación');
select ok(pg_temp.igual(), 'I2: el replay no agrega filas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R5', public.reasignar_vendedor('22220000-2100-4000-8000-000000000042', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000002')$q$, 'J1 se reasigna otra vez (A10 → A2)');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R6', public.reasignar_vendedor('22220000-2100-4000-8000-000000000043', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000010')$q$, 'J1 vuelve al vendedor A10');
reset role;
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'RR2', public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000010')$q$, 'T2-1: replay legítimo cuando el vendedor vigente ya coincide con el pedido');
reset role;
select is((select v from res where k = 'RR2'), (select v from res where k = 'R1'), 'T2-1: devuelve la operación original; no es jornada_sin_cambios (el replay precede a la revalidación)');
select ok(pg_temp.igual(), 'T2-1: el replay no agregó filas');
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'RR3', public.reasignar_vendedor('22220000-2100-4000-8000-000000000042', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000002')$q$, 'I3: replay de una reasignación posterior, ya superada por otra');
reset role;
select is((select v from res where k = 'RR3'), (select v from res where k = 'R5'), 'I3: devuelve la operación de esa reasignación, no el estado actual');
update public.jornadas set estado = 'en_reparto' where id = (select v from res where k = 'J1');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'RR4', public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000010')$q$, 'I3: replay después de que la jornada pasó a en_reparto (fixture controlado; se repite con el flujo real en T7)');
reset role;
select is((select v from res where k = 'RR4'), (select v from res where k = 'R1'), 'I3: la misma respuesta que la primera ejecución, sin revalidar el estado');
select is((select estado from public.jornadas where id = (select v from res where k = 'J1')), 'en_reparto', 'I3: la jornada conserva el estado alcanzado');
select ok(pg_temp.igual(), 'I3: cero filas nuevas');
update public.perfiles set activo = false where usuario_id = 'aaaaaaaa-2100-4000-8000-000000000001';
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000010')$q$, 'PT403', 'jornada_no_autorizado', 'I4: replay de un actor que quedó inactivo → PT403');
reset role;
update public.perfiles set activo = true, rol = 'vendedor_piloto' where usuario_id = 'aaaaaaaa-2100-4000-8000-000000000001';
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000010')$q$, 'PT403', 'jornada_no_autorizado', 'I4: replay de un actor que pasó a vendedor_piloto → PT403');
reset role;
update public.perfiles set rol = 'dueno' where usuario_id = 'aaaaaaaa-2100-4000-8000-000000000001';
select ok(pg_temp.igual(), 'I4: los rechazos de replay no dejaron efectos');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', (select v from res where k = 'J1'), null)$q$, 'PT400', 'jornada_vendedor_invalido', 'I5: misma clave y vendedor nulo → PT400 (no replay, no conflicto)');
reset role;
select ok(pg_temp.igual(), 'I5: misma clave y vendedor nulo → PT400 (no replay, no conflicto): sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', null, 'aaaaaaaa-2100-4000-8000-000000000010')$q$, 'PT404', 'jornada_no_encontrada', 'I5: misma clave y jornada nula → PT404');
reset role;
select ok(pg_temp.igual(), 'I5: misma clave y jornada nula → PT404: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', (select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave y otro vendedor → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I6: misma clave y otro vendedor → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000010')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave y otra jornada → PT409');
reset role;
select ok(pg_temp.igual(), 'I6: misma clave y otra jornada → PT409: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select is((select o.huella from public.operaciones o where o.idempotency_key = '22220000-2100-4000-8000-000000000001' and o.actor_id = 'aaaaaaaa-2100-4000-8000-000000000001'), pg_temp.huella_reasignacion((select v from res where k = 'J1'), 'aaaaaaaa-2100-4000-8000-000000000010'), 'I6: la operación original conserva su huella');
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-2100-4000-8000-000000000000', 'aaaaaaaa-2100-4000-8000-000000000001', 'ingreso', '22220000-2100-4000-8000-000000000060', repeat('0', 64), null);
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-2100-4000-8000-000000000000', 'aaaaaaaa-2100-4000-8000-000000000001', 'a_cuarentena', '22220000-2100-4000-8000-000000000061', repeat('1', 64), null);
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-2100-4000-8000-000000000000', 'aaaaaaaa-2100-4000-8000-000000000001', 'merma', '22220000-2100-4000-8000-000000000062', repeat('2', 64), null);
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-2100-4000-8000-000000000000', 'aaaaaaaa-2100-4000-8000-000000000001', 'apertura_jornada', '22220000-2100-4000-8000-000000000063', repeat('3', 64), null);
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-2100-4000-8000-000000000000', 'aaaaaaaa-2100-4000-8000-000000000001', 'correccion_jornada', '22220000-2100-4000-8000-000000000064', repeat('4', 64), (select v from res where k = 'J9'));
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-2100-4000-8000-000000000000', 'aaaaaaaa-2100-4000-8000-000000000001', 'carga', '22220000-2100-4000-8000-000000000065', repeat('5', 64), (select v from res where k = 'J9'));
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-2100-4000-8000-000000000000', 'aaaaaaaa-2100-4000-8000-000000000001', 'descarga', '22220000-2100-4000-8000-000000000066', repeat('6', 64), (select v from res where k = 'J9'));
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-2100-4000-8000-000000000000', 'aaaaaaaa-2100-4000-8000-000000000001', 'salida_jornada', '22220000-2100-4000-8000-000000000067', repeat('7', 64), (select v from res where k = 'J9'));
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000060', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación ingreso → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación ingreso → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000061', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación a_cuarentena → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación a_cuarentena → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000062', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación merma → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación merma → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000063', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación apertura_jornada → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación apertura_jornada → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000064', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación correccion_jornada → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación correccion_jornada → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000065', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación carga → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación carga → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000066', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación descarga → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación descarga → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000067', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación salida_jornada → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación salida_jornada → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.registrar_ingreso('22220000-2100-4000-8000-000000000001', 'aaaaaaaa-2100-4000-8000-0000000000f1', 5)$q$, 'PT409', 'stock_conflicto_idempotencia', 'I7 (regresión de Stock): registrar_ingreso con la clave de una reasignación sigue devolviendo su propio stock_conflicto_idempotencia');
reset role;
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000002');
select lives_ok($q$insert into res select 'R8', public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', (select v from res where k = 'J9'), 'aaaaaaaa-2100-4000-8000-000000000012')$q$, 'I8: la misma clave usada por otro actor de la misma empresa es una operación nueva e independiente');
reset role;
select isnt((select v from res where k = 'R8'), (select v from res where k = 'R1'), 'I8: no devuelve la operación del primer actor');
select is((select count(*)::int from public.operaciones where idempotency_key = '22220000-2100-4000-8000-000000000001'), 2, 'I8: existen dos operaciones con esa clave, una por actor');
select pg_temp.como_usuario('bbbbbbbb-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R9', public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', (select v from res where k = 'JB'), 'bbbbbbbb-2100-4000-8000-000000000003')$q$, 'I8: la misma clave en otra empresa tampoco es replay');
reset role;
select is((select j.vendedor_id from public.jornadas j where j.id = (select v from res where k = 'JB')), 'bbbbbbbb-2100-4000-8000-000000000003'::uuid, 'I8: la jornada de B se reasignó dentro de B');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select throws_ok($q$select public.reasignar_vendedor('22220000-2100-4000-8000-000000000050', (select v from res where k = 'J4'), 'aaaaaaaa-2100-4000-8000-000000000002')$q$, 'PT409', 'jornada_estado_invalido', 'I9: rechazo por estado (paso 10), después de reservar la clave');
reset role;
select ok(pg_temp.igual(), 'I9: rechazo por estado (paso 10), después de reservar la clave: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select is((select count(*)::int from public.operaciones where idempotency_key = '22220000-2100-4000-8000-000000000050'), 0, 'I9: el rechazo no dejó fila en operaciones (revierte la reserva)');
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R10', public.reasignar_vendedor('22220000-2100-4000-8000-000000000050', (select v from res where k = 'J11'), 'aaaaaaaa-2100-4000-8000-000000000011')$q$, 'I9: la misma clave con un payload válido se ejecuta como primera ejecución');
reset role;
select is((select count(*)::int from public.operaciones where idempotency_key = '22220000-2100-4000-8000-000000000050'), 1, 'I9: queda exactamente una operación con esa clave');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
insert into res select 'RR5', public.reasignar_vendedor('22220000-2100-4000-8000-000000000001', upper(((select v from res where k = 'J1'))::text)::uuid, upper('aaaaaaaa-2100-4000-8000-000000000010')::uuid);
reset role;
select is((select v from res where k = 'RR5'), (select v from res where k = 'R1'), 'I12: uuid escritos en mayúsculas son el mismo valor: replay idéntico, no conflicto');
select ok(pg_temp.igual(), 'I12: cero filas nuevas');
select pg_temp.como_usuario('aaaaaaaa-2100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R11', public.reasignar_vendedor('22220000-2100-4000-8000-000000000811', (select v from res where k = 'J11'), 'aaaaaaaa-2100-4000-8000-000000000002')$q$, 'I13: la clave del rechazo por jornada nula se ejecuta como primera ejecución con el payload corregido');
reset role;
select is((select count(*)::int from public.reasignaciones_vendedor where jornada_id = (select v from res where k = 'J11')), 2, 'historial: J11 tiene exactamente las dos reasignaciones confirmadas');
select * from finish();
rollback;
