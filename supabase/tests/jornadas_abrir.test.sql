-- pgTAP: T1 — RPC abrir_jornada (Blueprint §7.5, §9, §10, §12; ADR-007 §2.1 y §7
-- casos 1 a 7; ADR-001 §18.4.2, §18.4.3, §18.4.4, §18.4.5, §18.4.7 y §18.4.9, grupos
-- S e I). Ejecutar sólo en local.
--
-- B es un fixture adversarial (aislamiento por empresa_id). La concurrencia
-- (I10, I11 y K10) NO se prueba acá: queda para el arnés de T3 y no se declara
-- aprobada por este archivo. I3 usa un fixture controlado (el owner lleva la
-- jornada a un estado posterior) porque las RPC de carga y salida aún no
-- existen; se repite con el flujo real en T7.

begin;

create extension if not exists pgtap with schema extensions;

select plan(153);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------

insert into public.empresas (id, nombre) values
  ('aaaaaaaa-1100-4000-8000-000000000000', 'Empresa A (test)'),
  ('bbbbbbbb-1100-4000-8000-000000000000', 'Empresa B (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-1100-4000-8000-000000000001', 'authenticated', 'authenticated', 'ja.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-1100-4000-8000-000000000002', 'authenticated', 'authenticated', 'ja.a2@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-1100-4000-8000-000000000003', 'authenticated', 'authenticated', 'ja.a3@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-1100-4000-8000-000000000004', 'authenticated', 'authenticated', 'ja.a4@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-1100-4000-8000-000000000005', 'authenticated', 'authenticated', 'ja.a5@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-1100-4000-8000-000000000006', 'authenticated', 'authenticated', 'ja.a6@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-1100-4000-8000-000000000007', 'authenticated', 'authenticated', 'ja.a7@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-1100-4000-8000-000000000008', 'authenticated', 'authenticated', 'ja.a8@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-1100-4000-8000-000000000009', 'authenticated', 'authenticated', 'ja.a9@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-1100-4000-8000-000000000001', 'authenticated', 'authenticated', 'ja.b1@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-1100-4000-8000-000000000002', 'authenticated', 'authenticated', 'ja.b2@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-1100-4000-8000-000000000001', 'authenticated', 'authenticated', 'ja.n1@usuarios.distribuidora.invalid', '{"rol":"dueno","empresa_id":"aaaaaaaa-1100-4000-8000-000000000000"}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-000000000000', 'ja.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-1100-4000-8000-000000000002', 'aaaaaaaa-1100-4000-8000-000000000000', 'ja.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-1100-4000-8000-000000000003', 'aaaaaaaa-1100-4000-8000-000000000000', 'ja.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-1100-4000-8000-000000000004', 'aaaaaaaa-1100-4000-8000-000000000000', 'ja.a4', 'A4', 'dueno', false),
  ('aaaaaaaa-1100-4000-8000-000000000005', 'aaaaaaaa-1100-4000-8000-000000000000', 'ja.a5', 'A5', 'vendedor_piloto', false),
  ('aaaaaaaa-1100-4000-8000-000000000006', 'aaaaaaaa-1100-4000-8000-000000000000', 'ja.a6', 'A6', 'vendedor_piloto', true),
  ('aaaaaaaa-1100-4000-8000-000000000007', 'aaaaaaaa-1100-4000-8000-000000000000', 'ja.a7', 'A7', 'vendedor_piloto', true),
  ('aaaaaaaa-1100-4000-8000-000000000008', 'aaaaaaaa-1100-4000-8000-000000000000', 'ja.a8', 'A8', 'encargado', true),
  ('aaaaaaaa-1100-4000-8000-000000000009', 'aaaaaaaa-1100-4000-8000-000000000000', 'ja.a9', 'A9', 'vendedor_piloto', true),
  ('bbbbbbbb-1100-4000-8000-000000000001', 'bbbbbbbb-1100-4000-8000-000000000000', 'ja.b1', 'B1', 'dueno', true),
  ('bbbbbbbb-1100-4000-8000-000000000002', 'bbbbbbbb-1100-4000-8000-000000000000', 'ja.b2', 'B2', 'vendedor_piloto', true);

insert into public.camiones (id, empresa_id, patente, nombre, activo, creado_por) values
  ('aaaaaaaa-1100-4000-8000-0000000000c1', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-01', 'Camión A1', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000c2', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-02', 'Camión A2', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000c3', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-03', 'Camión A3', false, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000c4', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-04', 'Camión A4', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000c5', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-05', 'Camión A5', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000c6', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-06', 'Camión A6', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000c7', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-07', 'Camión A7', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000c8', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-08', 'Camión A8', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000c9', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-09', 'Camión A9', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000ca', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-010', 'Camión A10', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000cb', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-011', 'Camión A11', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000cc', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-012', 'Camión A12', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000cd', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-013', 'Camión A13', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000ce', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-014', 'Camión A14', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000cf', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-015', 'Camión A15', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('aaaaaaaa-1100-4000-8000-0000000000d0', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-016', 'Camión A16', true, 'aaaaaaaa-1100-4000-8000-000000000001'),
  ('bbbbbbbb-1100-4000-8000-0000000000c1', 'bbbbbbbb-1100-4000-8000-000000000000', 'JA-B1', 'Camión B1', true, 'bbbbbbbb-1100-4000-8000-000000000001');

insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('aaaaaaaa-1100-4000-8000-0000000000d1', 'aaaaaaaa-1100-4000-8000-000000000000', 'deposito', null);

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('aaaaaaaa-1100-4000-8000-0000000000f1', 'aaaaaaaa-1100-4000-8000-000000000000', 'JA-A1', 'Leche A', 'lacteos', 'unidad', 100, true, 'aaaaaaaa-1100-4000-8000-000000000001');

create function pg_temp.como_usuario(uid uuid, metadata jsonb default '{}')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated', 'user_metadata', metadata)::text, true);
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

-- Día operativo, con la misma expresión que usa la RPC (T1-3).
create function pg_temp.hoy()
returns date language sql as $$
  select (now() at time zone 'America/Argentina/Tucuman')::date
$$;

-- Conteo global de filas relacionadas con jornadas, leído como owner
-- (SECURITY DEFINER) para poder compararlo desde cualquier rol.
create function pg_temp.conteo()
returns text language sql security definer set search_path = '' as $$
  select (select count(*) from public.operaciones)::text
    || '|' || (select count(*) from public.jornadas)::text
    || '|' || (select count(*) from public.movimientos_stock)::text
    || '|' || (select count(*) from public.reasignaciones_vendedor)::text
    || '|' || (select count(*) from public.correcciones_jornada)::text
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
create function pg_temp.huella_apertura(camion uuid, fecha date, vendedor uuid)
returns text language sql as $$
  select encode(sha256(convert_to(
    'v1|apertura_jornada|' || camion::text || '|' || to_char(fecha, 'YYYY-MM-DD') || '|' || vendedor::text,
    'UTF8')), 'hex')
$$;

grant execute on function pg_temp.como_usuario(uuid, jsonb) to public;
grant execute on function pg_temp.sin_sub() to public;
grant execute on function pg_temp.como_anon() to public;
grant execute on function pg_temp.como_service_role() to public;
grant execute on function pg_temp.hoy() to public;
grant execute on function pg_temp.conteo() to public;
grant execute on function pg_temp.fijar() to public;
grant execute on function pg_temp.igual() to public;
grant execute on function pg_temp.huella_apertura(uuid, date, uuid) to public;

create temp table res (k text, v uuid);
grant select, insert on res to public;

-- ---------------------------------------------------------------------------
-- 1. Catálogo: dos funciones, ACL, owner, search_path, sin sobrecargas
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_proc
    where proname = 'abrir_jornada'
      and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)),
  2, 'abrir_jornada existe una sola vez en public y una en privado, sin sobrecargas');
select ok(exists (
  select 1 from pg_proc p
   where p.oid = 'privado.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure
     and p.prosecdef and p.proowner = 'propietario_rpc'::regrole
     and p.proconfig @> array['search_path=""'] and p.provolatile = 'v'
     and p.prorettype = 'uuid'::regtype and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
     and array(select a::text from unnest(p.proacl) a order by 1)
         = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']),
  'privado.abrir_jornada: SECURITY DEFINER, owner propietario_rpc, search_path vacío, VOLATILE, devuelve uuid y ACL exacta');
select ok(exists (
  select 1 from pg_proc p
   where p.oid = 'public.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure
     and not p.prosecdef and p.proowner = 'postgres'::regrole
     and p.proconfig @> array['search_path=""'] and p.provolatile = 'v'
     and p.prorettype = 'uuid'::regtype and p.prolang = (select oid from pg_language where lanname = 'sql')
     and array(select a::text from unnest(p.proacl) a order by 1)
         = array['authenticated=X/postgres', 'postgres=X/postgres']),
  'public.abrir_jornada: SECURITY INVOKER, owner postgres, search_path vacío, VOLATILE, devuelve uuid y ACL exacta');
select is(
  (select p.proargnames from pg_proc p where p.oid = 'public.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure),
  array['p_idempotency_key', 'p_camion_id', 'p_fecha', 'p_vendedor_id'],
  'los parámetros se llaman p_idempotency_key, p_camion_id, p_fecha y p_vendedor_id');
select ok(
  (select p.prosrc from pg_proc p where p.oid = 'public.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure)
    ~ 'privado\.abrir_jornada\(p_idempotency_key, p_camion_id, p_fecha, p_vendedor_id\)'
  and (select p.prosrc from pg_proc p where p.oid = 'public.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure) !~* 'insert|update|delete',
  'la fachada sólo delega en la implementación');
select ok(
  not has_function_privilege('anon', 'public.abrir_jornada(uuid, uuid, date, uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.abrir_jornada(uuid, uuid, date, uuid)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = 'public.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure and a.grantee = 0)
  and has_function_privilege('authenticated', 'public.abrir_jornada(uuid, uuid, date, uuid)', 'execute'),
  'fachada: EXECUTE sólo para authenticated (ni PUBLIC, ni anon, ni service_role)');
select ok(
  not has_function_privilege('anon', 'privado.abrir_jornada(uuid, uuid, date, uuid)', 'execute')
  and not has_function_privilege('service_role', 'privado.abrir_jornada(uuid, uuid, date, uuid)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = 'privado.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure and a.grantee = 0)
  and has_function_privilege('authenticated', 'privado.abrir_jornada(uuid, uuid, date, uuid)', 'execute'),
  'implementación: EXECUTE sólo para authenticated (ni PUBLIC, ni anon, ni service_role)');
select ok(
  not has_schema_privilege('propietario_rpc', 'privado', 'create')
  and not has_schema_privilege('propietario_rpc', 'public', 'create'),
  'propietario_rpc no conserva CREATE sobre privado ni public tras transferir la propiedad');
select ok(
  (select p.prosrc from pg_proc p where p.oid = 'privado.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure)
    ~ 'America/Argentina/Tucuman'
  and (select p.prosrc from pg_proc p where p.oid = 'privado.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure)
    ~ 'hashtextextended',
  'la implementación calcula el día operativo en America/Argentina/Tucuman y toma advisory locks');

-- ---------------------------------------------------------------------------
-- 2. Seguridad: anon, service_role, sin sesión, sin perfil, inactivo, vendedor_piloto
-- ---------------------------------------------------------------------------
select pg_temp.como_anon();
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000900', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 30, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, '42501', null, 'anon no puede ejecutar la fachada');
reset role;
select pg_temp.como_anon();
select throws_ok($q$select privado.abrir_jornada('11110000-1100-4000-8000-000000000900', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 30, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, '42501', null, 'anon no puede ejecutar la implementación');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000900', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 30, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, '42501', null, 'service_role no puede ejecutar la fachada');
reset role;
select pg_temp.como_service_role();
select throws_ok($q$select privado.abrir_jornada('11110000-1100-4000-8000-000000000900', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 30, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, '42501', null, 'service_role no puede ejecutar la implementación');
reset role;
select pg_temp.fijar();
select pg_temp.sin_sub();
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000900', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 30, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT401', 'jornada_no_autenticado', 'sin sub en el JWT: PT401');
reset role;
select ok(pg_temp.igual(), 'sin sub en el JWT: PT401: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('dddddddd-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000900', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 30, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT403', 'jornada_no_autorizado', 'cuenta sin perfil (con metadata de dueño de A): PT403');
reset role;
select ok(pg_temp.igual(), 'cuenta sin perfil (con metadata de dueño de A): PT403: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000004');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000900', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 30, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT403', 'jornada_no_autorizado', 'dueño con perfil inactivo: PT403');
reset role;
select ok(pg_temp.igual(), 'dueño con perfil inactivo: PT403: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000003');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000900', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 30, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT403', 'jornada_no_autorizado', 'vendedor_piloto: PT403');
reset role;
select ok(pg_temp.igual(), 'vendedor_piloto: PT403: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000003', '{"rol":"dueno","empresa_id":"bbbbbbbb-1100-4000-8000-000000000000"}');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000900', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 30, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT403', 'jornada_no_autorizado', 'vendedor_piloto con metadata falsa de dueño de otra empresa: PT403');
reset role;
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id) values ('aaaaaaaa-1100-4000-8000-000000000000', current_date, 'aaaaaaaa-1100-4000-8000-0000000000c8', 'aaaaaaaa-1100-4000-8000-000000000009', 'abierta', 'aaaaaaaa-1100-4000-8000-000000000001', '11110000-1100-4000-8000-000000000001')$q$, '42501', null, 'dueño: DML directo #1 rechazado');
select throws_ok($q$update public.jornadas set estado = 'cerrada'$q$, '42501', null, 'dueño: DML directo #2 rechazado');
select throws_ok($q$delete from public.jornadas$q$, '42501', null, 'dueño: DML directo #3 rechazado');
select throws_ok($q$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella) values ('aaaaaaaa-1100-4000-8000-000000000000', 'aaaaaaaa-1100-4000-8000-000000000001', 'apertura_jornada', '11110000-1100-4000-8000-000000000901', repeat('a', 64))$q$, '42501', null, 'dueño: DML directo #4 rechazado');
reset role;
-- ---------------------------------------------------------------------------
-- 3. Apertura válida: dueño y encargado, efectos exactos (I1) y roles de vendedor (caso 6)
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J1', public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'dueño abre con camión activo, día operativo actual y vendedor_piloto (caso 3: día operativo)');
reset role;
select is(pg_temp.conteo(), (select (split_part(v,'|',1)::int + 1)::text || '|' || (split_part(v,'|',2)::int + 1)::text || '|' || split_part(v,'|',3) || '|' || split_part(v,'|',4) || '|' || split_part(v,'|',5) from pg_temp.snap), 'I1: la apertura suma exactamente una operación y una jornada; cero movimientos y cero historiales');
select is(
  (select o from (select o.tipo, o.jornada_id is null as sin_jornada, o.actor_id, o.empresa_id, o.huella,
                         o.huella = pg_temp.huella_apertura('aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003') as huella_ok
                    from public.operaciones o
                   where o.empresa_id = 'aaaaaaaa-1100-4000-8000-000000000000' and o.idempotency_key = '11110000-1100-4000-8000-000000000001') o)::text,
  row('apertura_jornada', true, 'aaaaaaaa-1100-4000-8000-000000000001'::uuid, 'aaaaaaaa-1100-4000-8000-000000000000'::uuid, pg_temp.huella_apertura('aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003'), true)::text,
  'I1: la operación es apertura_jornada, sin jornada_id, del actor y la empresa, con la huella v1 recalculada aparte');
select is(
  (select row(j.empresa_id, j.fecha, j.camion_id, j.vendedor_id, j.estado, j.abierta_por,
              j.tipo_operacion_apertura, j.operacion_apertura_id = o.id)::text
     from public.jornadas j
     join public.operaciones o on o.id = j.operacion_apertura_id
    where j.id = (select v from res where k = 'J1')),
  row('aaaaaaaa-1100-4000-8000-000000000000'::uuid, pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-0000000000c1'::uuid, 'aaaaaaaa-1100-4000-8000-000000000003'::uuid, 'abierta', 'aaaaaaaa-1100-4000-8000-000000000001'::uuid, 'apertura_jornada', true)::text,
  'I1: la jornada nace abierta, con camión, fecha, vendedor y abierta_por del pedido, ligada a su operación');
select is((select o.id from public.operaciones o where o.idempotency_key = '11110000-1100-4000-8000-000000000001'),
  (select j.operacion_apertura_id from public.jornadas j where j.id = (select v from res where k = 'J1')),
  'la respuesta es el uuid de la jornada ligada por operacion_apertura_id');
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000002');
select lives_ok($q$insert into res select 'J2', public.abrir_jornada('11110000-1100-4000-8000-000000000002', 'aaaaaaaa-1100-4000-8000-0000000000c2', pg_temp.hoy() + 1, 'aaaaaaaa-1100-4000-8000-000000000006')$q$, 'encargado abre con fecha futura (caso 3: fecha futura)');
reset role;
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J3', public.abrir_jornada('11110000-1100-4000-8000-000000000003', 'aaaaaaaa-1100-4000-8000-0000000000c4', pg_temp.hoy() + 2, 'aaaaaaaa-1100-4000-8000-000000000001')$q$, 'caso 6: un dueño activo puede ser el vendedor asignado');
reset role;
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J4', public.abrir_jornada('11110000-1100-4000-8000-000000000004', 'aaaaaaaa-1100-4000-8000-0000000000c5', pg_temp.hoy() + 2, 'aaaaaaaa-1100-4000-8000-000000000008')$q$, 'caso 6: un encargado activo puede ser el vendedor asignado');
reset role;
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J5', public.abrir_jornada('11110000-1100-4000-8000-000000000005', 'aaaaaaaa-1100-4000-8000-0000000000c6', pg_temp.hoy() + 3, 'aaaaaaaa-1100-4000-8000-000000000007')$q$, 'caso 6: un vendedor_piloto activo puede ser el vendedor asignado');
reset role;
select is((select count(*)::int from public.jornadas where estado = 'abierta'), 5,
  'las cinco aperturas válidas quedaron abiertas');
-- ---------------------------------------------------------------------------
-- 4. Fechas (T1-1 y T1-4): NULL, infinity, -infinity, ayer, hoy, mañana, 9999-12-31 y 10000-01-01
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J6', public.abrir_jornada('11110000-1100-4000-8000-000000000006', 'aaaaaaaa-1100-4000-8000-0000000000c7', date '9999-12-31', 'aaaaaaaa-1100-4000-8000-000000000009')$q$, '9999-12-31 se acepta (límite superior inclusive)');
reset role;
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000010', 'aaaaaaaa-1100-4000-8000-0000000000c8', null, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT400', 'jornada_fecha_invalida', 'caso 3: fecha nula → PT400 jornada_fecha_invalida');
reset role;
select ok(pg_temp.igual(), 'caso 3: fecha nula → PT400 jornada_fecha_invalida: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000011', 'aaaaaaaa-1100-4000-8000-0000000000c8', 'infinity'::date, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT400', 'jornada_fecha_invalida', 'caso 3: infinity → PT400 jornada_fecha_invalida');
reset role;
select ok(pg_temp.igual(), 'caso 3: infinity → PT400 jornada_fecha_invalida: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000012', 'aaaaaaaa-1100-4000-8000-0000000000c8', '-infinity'::date, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT400', 'jornada_fecha_invalida', 'caso 3: -infinity → PT400 jornada_fecha_invalida');
reset role;
select ok(pg_temp.igual(), 'caso 3: -infinity → PT400 jornada_fecha_invalida: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000013', 'aaaaaaaa-1100-4000-8000-0000000000c8', date '10000-01-01', 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT400', 'jornada_fecha_invalida', 'caso 3: 10000-01-01 (posterior a 9999-12-31) → PT400 jornada_fecha_invalida');
reset role;
select ok(pg_temp.igual(), 'caso 3: 10000-01-01 (posterior a 9999-12-31) → PT400 jornada_fecha_invalida: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000014', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() - 1, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT400', 'jornada_fecha_invalida', 'caso 3: ayer (día operativo anterior) → PT400 jornada_fecha_invalida');
reset role;
select ok(pg_temp.igual(), 'caso 3: ayer (día operativo anterior) → PT400 jornada_fecha_invalida: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select is((select count(*)::int from public.operaciones where idempotency_key in ('11110000-1100-4000-8000-000000000010','11110000-1100-4000-8000-000000000011','11110000-1100-4000-8000-000000000012','11110000-1100-4000-8000-000000000013','11110000-1100-4000-8000-000000000014')), 0,
  'ningún rechazo de fecha reservó su clave de idempotencia');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000015', null, 'infinity'::date, null)$q$, 'PT400', 'jornada_fecha_invalida', 'precedencia del paso 3: fecha infinita + vendedor y camión nulos → fecha_invalida');
reset role;
select ok(pg_temp.igual(), 'precedencia del paso 3: fecha infinita + vendedor y camión nulos → fecha_invalida: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada(null, 'aaaaaaaa-1100-4000-8000-0000000000c8', 'infinity'::date, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT400', 'jornada_clave_invalida', 'precedencia del paso 3: clave nula + fecha infinita → clave_invalida');
reset role;
select ok(pg_temp.igual(), 'precedencia del paso 3: clave nula + fecha infinita → clave_invalida: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
-- ---------------------------------------------------------------------------
-- 5. Estructura (I13, I14): vendedor, camión y clave nulos
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada(null, 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 40, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT400', 'jornada_clave_invalida', 'I14: clave nula → PT400 jornada_clave_invalida');
reset role;
select ok(pg_temp.igual(), 'I14: clave nula → PT400 jornada_clave_invalida: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000020', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 40, null)$q$, 'PT400', 'jornada_vendedor_invalido', 'vendedor nulo → PT400 jornada_vendedor_invalido');
reset role;
select ok(pg_temp.igual(), 'vendedor nulo → PT400 jornada_vendedor_invalido: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000021', null, pg_temp.hoy() + 40, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT404', 'jornada_camion_no_encontrado', 'camión nulo → PT404 jornada_camion_no_encontrado (D-N1)');
reset role;
select ok(pg_temp.igual(), 'camión nulo → PT404 jornada_camion_no_encontrado (D-N1): sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select is((select count(*)::int from public.operaciones where idempotency_key in ('11110000-1100-4000-8000-000000000020','11110000-1100-4000-8000-000000000021')), 0,
  'I13: los rechazos estructurales no reservaron la clave');
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J20', public.abrir_jornada('11110000-1100-4000-8000-000000000020', 'aaaaaaaa-1100-4000-8000-0000000000ca', pg_temp.hoy() + 40, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'I13: la misma clave con el vendedor corregido se ejecuta como primera ejecución');
select lives_ok($q$insert into res select 'J21', public.abrir_jornada('11110000-1100-4000-8000-000000000021', 'aaaaaaaa-1100-4000-8000-0000000000cb', pg_temp.hoy() + 41, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'I13: la misma clave con el camión corregido se ejecuta como primera ejecución');
reset role;
-- ---------------------------------------------------------------------------
-- 6. Recursos de otra empresa o inexistentes: respuesta indistinguible
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000030', 'bbbbbbbb-1100-4000-8000-0000000000c1', pg_temp.hoy() + 50, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT404', 'jornada_camion_no_encontrado', 'camión de otra empresa → PT404 jornada_camion_no_encontrado');
reset role;
select ok(pg_temp.igual(), 'camión de otra empresa → PT404 jornada_camion_no_encontrado: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000031', 'eeeeeeee-1100-4000-8000-0000000000c1', pg_temp.hoy() + 50, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT404', 'jornada_camion_no_encontrado', 'camión inexistente → el mismo PT404 y el mismo mensaje');
reset role;
select ok(pg_temp.igual(), 'camión inexistente → el mismo PT404 y el mismo mensaje: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000032', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 50, 'bbbbbbbb-1100-4000-8000-000000000002')$q$, 'PT404', 'jornada_vendedor_no_encontrado', 'vendedor de otra empresa → PT404 jornada_vendedor_no_encontrado');
reset role;
select ok(pg_temp.igual(), 'vendedor de otra empresa → PT404 jornada_vendedor_no_encontrado: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000033', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 50, 'eeeeeeee-1100-4000-8000-000000000001')$q$, 'PT404', 'jornada_vendedor_no_encontrado', 'vendedor inexistente → el mismo PT404 y el mismo mensaje');
reset role;
select ok(pg_temp.igual(), 'vendedor inexistente → el mismo PT404 y el mismo mensaje: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('bbbbbbbb-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000034', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 50, 'bbbbbbbb-1100-4000-8000-000000000002')$q$, 'PT404', 'jornada_camion_no_encontrado', 'dueño de B no usa camiones de A');
reset role;
select ok(pg_temp.igual(), 'dueño de B no usa camiones de A: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
-- ---------------------------------------------------------------------------
-- 7. ADR-007 §7: casos 1, 2, 4, 5 y 7, y precedencia de validaciones (T1-2)
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000040', 'aaaaaaaa-1100-4000-8000-0000000000c3', pg_temp.hoy() + 60, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_camion_inactivo', 'caso 4: camión inactivo → PT409 jornada_camion_inactivo');
reset role;
select ok(pg_temp.igual(), 'caso 4: camión inactivo → PT409 jornada_camion_inactivo: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000041', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 60, 'aaaaaaaa-1100-4000-8000-000000000005')$q$, 'PT400', 'jornada_vendedor_invalido', 'caso 5: vendedor inactivo → PT400 jornada_vendedor_invalido');
reset role;
select ok(pg_temp.igual(), 'caso 5: vendedor inactivo → PT400 jornada_vendedor_invalido: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000042', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_duplicada', 'caso 1: segundo par (camión, fecha) → PT409 jornada_duplicada');
reset role;
select ok(pg_temp.igual(), 'caso 1: segundo par (camión, fecha) → PT409 jornada_duplicada: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000043', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy() + 5, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_camion_con_jornada_abierta', 'caso 2: camión con otra jornada sin cerrar (otra fecha)');
reset role;
select ok(pg_temp.igual(), 'caso 2: camión con otra jornada sin cerrar (otra fecha): sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000044', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'PT409', 'jornada_vendedor_ocupado', 'caso 7: mismo vendedor y misma fecha → PT409 jornada_vendedor_ocupado');
reset role;
select ok(pg_temp.igual(), 'caso 7: mismo vendedor y misma fecha → PT409 jornada_vendedor_ocupado: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000045', 'aaaaaaaa-1100-4000-8000-0000000000c3', pg_temp.hoy() - 1, 'aaaaaaaa-1100-4000-8000-000000000005')$q$, 'PT400', 'jornada_fecha_invalida', 'precedencia: fecha pasada antes que camión inactivo y vendedor inactivo');
reset role;
select ok(pg_temp.igual(), 'precedencia: fecha pasada antes que camión inactivo y vendedor inactivo: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000046', 'aaaaaaaa-1100-4000-8000-0000000000c3', pg_temp.hoy() + 60, 'aaaaaaaa-1100-4000-8000-000000000005')$q$, 'PT409', 'jornada_camion_inactivo', 'precedencia: camión inactivo antes que vendedor inactivo');
reset role;
select ok(pg_temp.igual(), 'precedencia: camión inactivo antes que vendedor inactivo: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000047', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000005')$q$, 'PT400', 'jornada_vendedor_invalido', 'precedencia: vendedor inactivo antes que jornada_duplicada');
reset role;
select ok(pg_temp.igual(), 'precedencia: vendedor inactivo antes que jornada_duplicada: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000048', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'PT409', 'jornada_duplicada', 'precedencia: jornada_duplicada antes que camión con jornada abierta y vendedor ocupado');
reset role;
select ok(pg_temp.igual(), 'precedencia: jornada_duplicada antes que camión con jornada abierta y vendedor ocupado: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000049', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-1100-4000-8000-000000000006')$q$, 'PT409', 'jornada_camion_con_jornada_abierta', 'precedencia: camión con jornada abierta antes que vendedor ocupado');
reset role;
select ok(pg_temp.igual(), 'precedencia: camión con jornada abierta antes que vendedor ocupado: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
update public.jornadas set estado = 'cerrada' where id = (select v from res where k = 'J1');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000050', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_duplicada', 'caso 1: el par (camión, fecha) sigue ocupado aunque la jornada esté cerrada');
reset role;
select ok(pg_temp.igual(), 'caso 1: el par (camión, fecha) sigue ocupado aunque la jornada esté cerrada: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000051', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'PT409', 'jornada_vendedor_ocupado', 'caso 7: el vendedor sigue ocupado esa fecha aunque su jornada esté cerrada');
reset role;
select ok(pg_temp.igual(), 'caso 7: el vendedor sigue ocupado esa fecha aunque su jornada esté cerrada: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J7', public.abrir_jornada('11110000-1100-4000-8000-000000000052', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy() + 5, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'caso 2: con la jornada anterior cerrada, el camión admite una nueva en otra fecha');
reset role;
-- ---------------------------------------------------------------------------
-- 8. Idempotencia (I2 a I9 e I12 a I14)
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R1', public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'I2: replay idéntico de la apertura');
reset role;
select is((select v from res where k = 'R1'), (select v from res where k = 'J1'), 'I2: el replay devuelve la misma jornada (aunque ya esté cerrada)');
select ok(pg_temp.igual(), 'I2: el replay no agrega filas en operaciones, jornadas, movimientos ni historiales');
select is((select estado from public.jornadas where id = (select v from res where k = 'J1')), 'cerrada', 'I2: el replay no revalida ni modifica la jornada');
update public.jornadas set estado = 'en_reparto' where id = (select v from res where k = 'J2');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000002');
select lives_ok($q$insert into res select 'R2', public.abrir_jornada('11110000-1100-4000-8000-000000000002', 'aaaaaaaa-1100-4000-8000-0000000000c2', pg_temp.hoy() + 1, 'aaaaaaaa-1100-4000-8000-000000000006')$q$, 'I3: replay después de que la jornada pasó a en_reparto (fixture controlado; se repite con el flujo real en T7)');
reset role;
select is((select v from res where k = 'R2'), (select v from res where k = 'J2'), 'I3: devuelve la misma respuesta que la primera ejecución');
select is((select estado from public.jornadas where id = (select v from res where k = 'J2')), 'en_reparto', 'I3: no revalida estado: la jornada conserva el estado alcanzado');
select ok(pg_temp.igual(), 'I3: cero filas nuevas');
update public.perfiles set activo = false where usuario_id = 'aaaaaaaa-1100-4000-8000-000000000001';
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'PT403', 'jornada_no_autorizado', 'I4: replay de un actor que quedó inactivo → PT403');
reset role;
update public.perfiles set activo = true, rol = 'vendedor_piloto' where usuario_id = 'aaaaaaaa-1100-4000-8000-000000000001';
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'PT403', 'jornada_no_autorizado', 'I4: replay de un actor que pasó a vendedor_piloto → PT403');
reset role;
update public.perfiles set rol = 'dueno' where usuario_id = 'aaaaaaaa-1100-4000-8000-000000000001';
select ok(pg_temp.igual(), 'I4: los rechazos de replay no dejaron efectos');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000c1', null, 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'PT400', 'jornada_fecha_invalida', 'I5: misma clave y fecha nula → PT400 (no replay, no conflicto)');
reset role;
select ok(pg_temp.igual(), 'I5: misma clave y fecha nula → PT400 (no replay, no conflicto): sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000c1', 'infinity'::date, 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'PT400', 'jornada_fecha_invalida', 'I5: misma clave y fecha infinita → PT400');
reset role;
select ok(pg_temp.igual(), 'I5: misma clave y fecha infinita → PT400: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), null)$q$, 'PT400', 'jornada_vendedor_invalido', 'I5: misma clave y vendedor nulo → PT400');
reset role;
select ok(pg_temp.igual(), 'I5: misma clave y vendedor nulo → PT400: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000001', null, pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'PT404', 'jornada_camion_no_encontrado', 'I5: misma clave y camión nulo → PT404');
reset role;
select ok(pg_temp.igual(), 'I5: misma clave y camión nulo → PT404: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000c7', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave y otro camión → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I6: misma clave y otro camión → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy() + 10, 'aaaaaaaa-1100-4000-8000-000000000003')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave y otra fecha → PT409');
reset role;
select ok(pg_temp.igual(), 'I6: misma clave y otra fecha → PT409: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I6: misma clave y otro vendedor → PT409');
reset role;
select ok(pg_temp.igual(), 'I6: misma clave y otro vendedor → PT409: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select is((select o.huella from public.operaciones o where o.idempotency_key = '11110000-1100-4000-8000-000000000001' and o.actor_id = 'aaaaaaaa-1100-4000-8000-000000000001'), pg_temp.huella_apertura('aaaaaaaa-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'aaaaaaaa-1100-4000-8000-000000000003'), 'I6: la operación original conserva su huella');
-- I7: la clave ya usada por una operación de otro tipo
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-1100-4000-8000-000000000000', 'aaaaaaaa-1100-4000-8000-000000000001', 'ingreso', '11110000-1100-4000-8000-000000000060', repeat('0', 64), null);
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-1100-4000-8000-000000000000', 'aaaaaaaa-1100-4000-8000-000000000001', 'a_cuarentena', '11110000-1100-4000-8000-000000000061', repeat('1', 64), null);
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-1100-4000-8000-000000000000', 'aaaaaaaa-1100-4000-8000-000000000001', 'merma', '11110000-1100-4000-8000-000000000062', repeat('2', 64), null);
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-1100-4000-8000-000000000000', 'aaaaaaaa-1100-4000-8000-000000000001', 'reasignacion_vendedor', '11110000-1100-4000-8000-000000000063', repeat('3', 64), (select v from res where k = 'J3'));
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-1100-4000-8000-000000000000', 'aaaaaaaa-1100-4000-8000-000000000001', 'correccion_jornada', '11110000-1100-4000-8000-000000000064', repeat('4', 64), (select v from res where k = 'J3'));
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-1100-4000-8000-000000000000', 'aaaaaaaa-1100-4000-8000-000000000001', 'carga', '11110000-1100-4000-8000-000000000065', repeat('5', 64), (select v from res where k = 'J3'));
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-1100-4000-8000-000000000000', 'aaaaaaaa-1100-4000-8000-000000000001', 'descarga', '11110000-1100-4000-8000-000000000066', repeat('6', 64), (select v from res where k = 'J3'));
insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values ('aaaaaaaa-1100-4000-8000-000000000000', 'aaaaaaaa-1100-4000-8000-000000000001', 'salida_jornada', '11110000-1100-4000-8000-000000000067', repeat('7', 64), (select v from res where k = 'J3'));
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000060', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 70, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación ingreso → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación ingreso → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000061', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 70, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación a_cuarentena → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación a_cuarentena → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000062', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 70, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación merma → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación merma → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000063', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 70, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación reasignacion_vendedor → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación reasignacion_vendedor → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000064', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 70, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación correccion_jornada → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación correccion_jornada → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000065', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 70, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación carga → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación carga → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000066', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 70, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación descarga → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación descarga → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000067', 'aaaaaaaa-1100-4000-8000-0000000000c8', pg_temp.hoy() + 70, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_conflicto_idempotencia', 'I7: clave de una operación salida_jornada → PT409 jornada_conflicto_idempotencia');
reset role;
select ok(pg_temp.igual(), 'I7: clave de una operación salida_jornada → PT409 jornada_conflicto_idempotencia: sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.registrar_ingreso('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000f1', 5)$q$, 'PT409', 'stock_conflicto_idempotencia', 'I7 (regresión de Stock): registrar_ingreso con la clave de una apertura sigue devolviendo su propio stock_conflicto_idempotencia');
reset role;
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000002');
select lives_ok($q$insert into res select 'J8', public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'aaaaaaaa-1100-4000-8000-0000000000cc', pg_temp.hoy() + 6, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'I8: la misma clave usada por otro actor de la misma empresa es una operación nueva e independiente');
reset role;
select isnt((select v from res where k = 'J8'), (select v from res where k = 'J1'), 'I8: no devuelve la jornada del primer actor');
select is((select count(*)::int from public.operaciones where idempotency_key = '11110000-1100-4000-8000-000000000001'), 2, 'I8: existen dos operaciones con esa clave, una por actor');
select pg_temp.como_usuario('bbbbbbbb-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J9', public.abrir_jornada('11110000-1100-4000-8000-000000000001', 'bbbbbbbb-1100-4000-8000-0000000000c1', pg_temp.hoy(), 'bbbbbbbb-1100-4000-8000-000000000002')$q$, 'I8: la misma clave en otra empresa tampoco es replay');
reset role;
select is((select j.empresa_id from public.jornadas j where j.id = (select v from res where k = 'J9')), 'bbbbbbbb-1100-4000-8000-000000000000'::uuid, 'I8: la jornada de B pertenece a B');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('11110000-1100-4000-8000-000000000080', 'aaaaaaaa-1100-4000-8000-0000000000c3', pg_temp.hoy() + 80, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'PT409', 'jornada_camion_inactivo', 'I9: rechazo por camión inactivo (paso 10)');
reset role;
select ok(pg_temp.igual(), 'I9: rechazo por camión inactivo (paso 10): sin filas nuevas en operaciones, jornadas, movimientos ni historiales');
select is((select count(*)::int from public.operaciones where idempotency_key = '11110000-1100-4000-8000-000000000080'), 0, 'I9: el rechazo no dejó fila en operaciones (revierte la reserva)');
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J10', public.abrir_jornada('11110000-1100-4000-8000-000000000080', 'aaaaaaaa-1100-4000-8000-0000000000cd', pg_temp.hoy() + 80, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'I9: la misma clave con un payload válido se ejecuta como primera ejecución');
reset role;
select is((select count(*)::int from public.operaciones where idempotency_key = '11110000-1100-4000-8000-000000000080'), 1, 'I9: queda exactamente una operación con esa clave');
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R3', public.abrir_jornada('11110000-1100-4000-8000-000000000003', upper('aaaaaaaa-1100-4000-8000-0000000000c4')::uuid, pg_temp.hoy() + 2, upper('aaaaaaaa-1100-4000-8000-000000000001')::uuid)$q$, 'I12: uuid escritos en mayúsculas son el mismo valor');
reset role;
select is((select v from res where k = 'R3'), (select v from res where k = 'J3'), 'I12: replay idéntico, no conflicto');
select ok(pg_temp.igual(), 'I12: cero filas nuevas');
select pg_temp.como_usuario('aaaaaaaa-1100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J11', public.abrir_jornada('11110000-1100-4000-8000-000000000010', 'aaaaaaaa-1100-4000-8000-0000000000ce', pg_temp.hoy() + 90, 'aaaaaaaa-1100-4000-8000-000000000009')$q$, 'I13: la clave del rechazo por fecha nula se ejecuta como primera ejecución con la fecha corregida');
reset role;
-- I10, I11 y K10 (concurrencia) quedan pendientes para el arnés de T3; no se prueban ni se declaran aprobados acá.
select * from finish();
rollback;
