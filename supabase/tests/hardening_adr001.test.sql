-- pgTAP: hardening transversal de ADR-001 (Blueprint §10; ADR-001 §6, §7,
-- §12.8, §17.3 y §18.1). Decisiones humanas:
--   - P11: service_role denegado por defecto en objetos de negocio; única
--     excepción nominada, SELECT sobre public.productos.
--   - O-3: postgres → propietario_rpc con SET true e INHERIT false.
--   - O-4: public.rls_auto_enable() y ensure_rls se conservan, sin EXECUTE
--     para PUBLIC, anon, authenticated ni service_role.
-- Ejecutar sólo en local: `supabase test db`.
--
-- public.rls_auto_enable() existe sólo en el proyecto alojado. Donde no
-- existe, sus aserciones se informan como SKIP (no como PASS). El
-- comportamiento del revoke sobre un event trigger se prueba con una réplica
-- local de nombre distinto.

begin;

create extension if not exists pgtap with schema extensions;

select plan(50);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('dddddddd-0000-4000-8000-000000000000', 'Empresa hardening (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('dddddddd-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'hard.dueno@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'hard.vendedor@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('dddddddd-0000-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000000',
   'hard.dueno', 'Dueño hardening', 'dueno', true),
  ('dddddddd-0000-4000-8000-000000000003', 'dddddddd-0000-4000-8000-000000000000',
   'hard.vendedor', 'Vendedor hardening', 'vendedor_piloto', true);

create function pg_temp.como_usuario(uid uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;
grant execute on function pg_temp.como_usuario(uuid) to public;

create temp table tablas_negocio (tabla regclass);
insert into tablas_negocio values
  ('public.empresas'), ('public.perfiles'), ('public.productos'),
  ('public.camiones'), ('public.clientes'), ('public.ubicaciones');
grant select on tablas_negocio to public;

-- Las 20 firmas de negocio (fachadas + implementaciones).
create temp table rpc_negocio (firma regprocedure);
insert into rpc_negocio values
  ('public.crear_producto(text,text,text,text,numeric,integer)'),
  ('public.actualizar_producto(uuid,text,text,numeric,integer)'),
  ('public.cambiar_estado_producto(uuid,boolean)'),
  ('public.crear_camion(text,text)'),
  ('public.actualizar_camion(uuid,text,text)'),
  ('public.cambiar_estado_camion(uuid,boolean)'),
  ('public.crear_cliente(text,text,text,text)'),
  ('public.actualizar_cliente(uuid,text,text,text,text)'),
  ('public.validar_cliente(uuid)'),
  ('public.cambiar_estado_cliente(uuid,boolean)'),
  ('privado.crear_producto(text,text,text,text,numeric,integer)'),
  ('privado.actualizar_producto(uuid,text,text,numeric,integer)'),
  ('privado.cambiar_estado_producto(uuid,boolean)'),
  ('privado.crear_camion(text,text)'),
  ('privado.actualizar_camion(uuid,text,text)'),
  ('privado.cambiar_estado_camion(uuid,boolean)'),
  ('privado.crear_cliente(text,text,text,text)'),
  ('privado.actualizar_cliente(uuid,text,text,text,text)'),
  ('privado.validar_cliente(uuid)'),
  ('privado.cambiar_estado_cliente(uuid,boolean)');
grant select on rpc_negocio to public;

-- ===========================================================================
-- P11 — service_role denegado por defecto
-- ===========================================================================
select is(
  array(select t.tabla::text from tablas_negocio t
         where has_table_privilege('service_role', t.tabla, 'SELECT') order by 1),
  array['productos'],
  'P11: service_role tiene SELECT sólo sobre productos (excepción nominada)');

select is(
  (select count(*)::int
     from tablas_negocio t,
          unnest(array['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p
    where has_table_privilege('service_role', t.tabla, p)),
  0,
  'P11: service_role sin INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN en las tablas de negocio');

select ok(
  not exists (
    select 1 from tablas_negocio t
     where has_any_column_privilege('service_role', t.tabla, 'INSERT, UPDATE, REFERENCES')
        or (t.tabla <> 'public.productos'::regclass
            and has_any_column_privilege('service_role', t.tabla, 'SELECT'))),
  'P11: service_role sin privilegios por columna (salvo el SELECT de productos)');

select is(
  array(select a.privilege_type from pg_class c, aclexplode(c.relacl) a
         where c.oid = 'public.productos'::regclass
           and a.grantee = 'service_role'::regrole order by 1),
  array['SELECT'],
  'P11: la ACL de productos le da a service_role exactamente SELECT (sin MAINTAIN)');

select ok(
  not exists (
    select 1 from tablas_negocio t, pg_class c, aclexplode(c.relacl) a
     where c.oid = t.tabla and t.tabla <> 'public.productos'::regclass
       and a.grantee = 'service_role'::regrole),
  'P11: service_role no figura en la ACL de empresas, perfiles, camiones, clientes ni ubicaciones');

select is(
  (select count(*)::int from rpc_negocio r
    where has_function_privilege('service_role', r.firma, 'EXECUTE')),
  0,
  'P11: service_role sin EXECUTE sobre las 20 firmas de negocio (fachadas e implementaciones)');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and has_function_privilege('service_role', p.oid, 'EXECUTE')),
  0,
  'P11: service_role no ejecuta ninguna función de public ni privado');

select ok(
  not exists (
    select 1 from pg_proc p, aclexplode(p.proacl) a
     where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
       and a.grantee = 'service_role'::regrole),
  'P11: service_role no figura en la ACL de ninguna función de public ni privado');

-- Comportamiento real con el rol (BYPASSRLS no compensa la falta de grants).
grant usage on schema extensions to service_role;
set local role service_role;
select throws_ok('select count(*) from public.empresas', '42501', null,
  'P11: service_role no puede leer empresas');
select throws_ok('select count(*) from public.perfiles', '42501', null,
  'P11: service_role no puede leer perfiles');
select throws_ok('select count(*) from public.camiones', '42501', null,
  'P11: service_role no puede leer camiones');
select throws_ok('select count(*) from public.clientes', '42501', null,
  'P11: service_role no puede leer clientes');
select throws_ok('select count(*) from public.ubicaciones', '42501', null,
  'P11: service_role no puede leer ubicaciones');
select lives_ok('select count(*) from public.productos',
  'P11: service_role lee productos (excepción nominada)');
select throws_ok(
  $$insert into public.productos (empresa_id, nombre, categoria, forma_venta, precio, creado_por)
    values ('dddddddd-0000-4000-8000-000000000000', 'SR', 'lacteos', 'unidad', 1,
            'dddddddd-0000-4000-8000-000000000001')$$,
  '42501', null, 'P11: service_role no inserta productos');
select throws_ok($$update public.productos set nombre = 'SR'$$, '42501', null,
  'P11: service_role no actualiza productos');
select throws_ok($$select public.crear_producto('SR', 'SR', 'lacteos', 'unidad', 1, 0)$$,
  '42501', null, 'P11: service_role no ejecuta la fachada crear_producto');
select throws_ok($$select privado.crear_cliente('SR', '1')$$, '42501', null,
  'P11: service_role no ejecuta la implementación privada crear_cliente');
reset role;

-- ===========================================================================
-- O-3 — postgres → propietario_rpc: SET sí, INHERIT no
-- ===========================================================================
select results_eq(
  $$select am.admin_option, am.inherit_option, am.set_option
      from pg_auth_members am
     where am.roleid = 'propietario_rpc'::regrole
       and am.member = 'postgres'::regrole
       and am.grantor = 'postgres'::regrole$$,
  $$values (false, false, true)$$,
  'O-3: la membresía otorgada por postgres es SET true, INHERIT false, sin ADMIN');

select is(
  (select count(*)::int from pg_auth_members
    where roleid = 'propietario_rpc'::regrole and member = 'postgres'::regrole
      and inherit_option),
  0,
  'O-3: ninguna fila de membresía postgres → propietario_rpc tiene INHERIT');

select ok(pg_has_role('postgres', 'propietario_rpc', 'SET'),
  'O-3: pg_has_role(postgres, propietario_rpc, SET) = true');

select ok(not pg_has_role('postgres', 'propietario_rpc', 'USAGE'),
  'O-3: pg_has_role(postgres, propietario_rpc, USAGE) = false (no hereda privilegios)');

-- Los auxiliares sólo dan EXECUTE a propietario_rpc: sin INHERIT, postgres no
-- lo obtiene. (Las implementaciones sí son ejecutables por postgres, pero vía
-- su membresía en authenticated, que gestiona la plataforma.)
select ok(not has_function_privilege('postgres', 'privado.usuario_actual()', 'EXECUTE'),
  'O-3: postgres ya no hereda el EXECUTE de propietario_rpc sobre privado.usuario_actual()');

select throws_ok(
  $$comment on function privado.usuario_actual() is 'x'$$,
  '42501', null,
  'O-3: sin SET ROLE, postgres no actúa como owner de las funciones de propietario_rpc');

select is(
  (select count(*)::int from pg_proc
    where pronamespace = 'privado'::regnamespace
      and proowner <> 'propietario_rpc'::regrole),
  0,
  'O-3: toda función de privado sigue siendo de propietario_rpc');

select is(
  (select count(*)::int from rpc_negocio r join pg_proc p on p.oid = r.firma
    where p.pronamespace = 'privado'::regnamespace
      and p.prosecdef and p.proowner = 'propietario_rpc'::regrole),
  10,
  'O-3: las 10 implementaciones privadas siguen SECURITY DEFINER y de propietario_rpc');

select ok(
  not exists (select 1 from pg_auth_members
               where roleid = 'propietario_rpc'::regrole and member <> 'postgres'::regrole)
  and not exists (select 1 from pg_auth_members where member = 'propietario_rpc'::regrole),
  'O-3: propietario_rpc no tiene otros miembros y no es miembro de ningún rol');

select ok(
  not exists (
    select 1 from unnest(array['anon', 'authenticated', 'authenticator', 'service_role']) r
     where pg_has_role(r, 'propietario_rpc', 'SET') or pg_has_role(r, 'propietario_rpc', 'USAGE')),
  'O-3: ningún rol de la Data API puede hacer SET ROLE propietario_rpc ni heredarlo');

select ok(
  (select not (rolcanlogin or rolsuper or rolbypassrls or rolcreatedb
               or rolcreaterole or rolreplication)
     from pg_roles where rolname = 'propietario_rpc'),
  'O-3: propietario_rpc sigue NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION');

-- SET ROLE sigue disponible (lo usan migraciones y pruebas).
grant usage on schema extensions to propietario_rpc;
set local role propietario_rpc;
select is(current_user::text, 'propietario_rpc',
  'O-3: postgres puede hacer SET ROLE propietario_rpc');
reset role;

-- ALTER FUNCTION ... OWNER TO propietario_rpc sigue funcionando (con CREATE
-- temporal sobre privado, como hacen las migraciones).
create function privado.zz_o3_owner() returns integer language sql as 'select 1';
grant create on schema privado to propietario_rpc;
select lives_ok(
  $$alter function privado.zz_o3_owner() owner to propietario_rpc$$,
  'O-3: ALTER FUNCTION ... OWNER TO propietario_rpc sigue siendo posible con SET');
revoke create on schema privado from propietario_rpc;
select is(
  (select proowner::regrole::text from pg_proc where oid = 'privado.zz_o3_owner()'::regprocedure),
  'propietario_rpc',
  'O-3: la propiedad quedó transferida');

-- Runtime: la Topología D no depende de la membresía de postgres.
select pg_temp.como_usuario('dddddddd-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.crear_producto('HARD-1', 'Producto hardening', 'lacteos', 'unidad', 10, 0)$$,
  'Runtime: el dueño crea un producto por la fachada');
select lives_ok($$select public.crear_camion('HARD-01', 'Camión hardening')$$,
  'Runtime: el dueño crea un camión por la fachada');
select lives_ok($$select public.crear_cliente('Cliente hardening', '3810000000')$$,
  'Runtime: el dueño crea un cliente por la fachada');
select pg_temp.como_usuario('dddddddd-0000-4000-8000-000000000003');
select throws_ok(
  $$select public.crear_producto('HARD-2', 'X', 'lacteos', 'unidad', 10, 0)$$,
  'PT403', 'producto_no_autorizado', 'Runtime: el vendedor sigue sin poder crear productos');
reset role;

select results_eq(
  $$select (select creado_por from public.productos where codigo = 'HARD-1'),
           (select creado_por from public.camiones where patente = 'HARD-01'),
           (select creado_por from public.clientes where nombre = 'Cliente hardening')$$,
  $$values ('dddddddd-0000-4000-8000-000000000001'::uuid,
            'dddddddd-0000-4000-8000-000000000001'::uuid,
            'dddddddd-0000-4000-8000-000000000001'::uuid)$$,
  'Runtime: las altas quedaron con el autor derivado del servidor');

-- ===========================================================================
-- O-4 — public.rls_auto_enable() (sólo donde exista)
-- ===========================================================================
create temp table o4 as
  select to_regprocedure('public.rls_auto_enable()') as f;
grant select on o4 to public;

select case when (select f from o4) is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else ok((select prosecdef from pg_proc where oid = (select f from o4)),
          'O-4: rls_auto_enable() sigue SECURITY DEFINER') end;
select case when (select f from o4) is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else is((select proowner::regrole::text from pg_proc where oid = (select f from o4)),
          'postgres', 'O-4: rls_auto_enable() sigue siendo de postgres') end;
select case when (select f from o4) is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else is((select array_to_string(proconfig, ',') from pg_proc where oid = (select f from o4)),
          'search_path=pg_catalog', 'O-4: rls_auto_enable() conserva search_path=pg_catalog') end;
select case when (select f from o4) is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else ok(not exists (select 1 from pg_proc p,
                        aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                       where p.oid = (select f from o4) and a.grantee = 0),
          'O-4: PUBLIC sin EXECUTE sobre rls_auto_enable()') end;
select case when (select f from o4) is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else ok(not has_function_privilege('anon', (select f from o4), 'EXECUTE'),
          'O-4: anon sin EXECUTE sobre rls_auto_enable()') end;
select case when (select f from o4) is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else ok(not has_function_privilege('authenticated', (select f from o4), 'EXECUTE'),
          'O-4: authenticated sin EXECUTE sobre rls_auto_enable()') end;
select case when (select f from o4) is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else ok(not has_function_privilege('service_role', (select f from o4), 'EXECUTE'),
          'O-4: service_role sin EXECUTE sobre rls_auto_enable()') end;
select case when (select f from o4) is null
  then skip('O-4: public.rls_auto_enable() no existe en este entorno (local)', 1)
  else ok(exists (select 1 from pg_event_trigger
                   where evtname = 'ensure_rls' and evtfoid = (select f from o4)
                     and evtenabled <> 'D'),
          'O-4: ensure_rls sigue habilitado y apunta a rls_auto_enable()') end;

-- Coherencia sin falsos positivos: la función y su trigger existen juntos o
-- faltan juntos.
select is(
  (select f from o4) is not null,
  exists (select 1 from pg_event_trigger where evtname = 'ensure_rls'),
  'O-4: rls_auto_enable() y ensure_rls están presentes o ausentes juntos');

-- Invariante válido en cualquier entorno: ninguna función SECURITY DEFINER de
-- public (esquema expuesto) es ejecutable por PUBLIC ni por roles de la Data API.
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosecdef
      and (exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                    where a.grantee = 0)
           or has_function_privilege('anon', p.oid, 'EXECUTE')
           or has_function_privilege('authenticated', p.oid, 'EXECUTE')
           or has_function_privilege('service_role', p.oid, 'EXECUTE'))),
  0,
  'O-4: ninguna función SECURITY DEFINER de public es ejecutable por PUBLIC, anon, authenticated ni service_role');

-- Réplica local: el event trigger se dispara aunque quien ejecuta el DDL no
-- tenga EXECUTE sobre la función (revocar EXECUTE no cambia su comportamiento).
create table public.zz_o4_disparos (quien text, objeto text);
create function public.zz_o4_replica() returns event_trigger
language plpgsql security definer set search_path = pg_catalog as $$
declare r record;
begin
  for r in select * from pg_event_trigger_ddl_commands() where command_tag = 'CREATE TABLE' loop
    insert into public.zz_o4_disparos values (current_user, r.object_identity);
  end loop;
end $$;
revoke execute on function public.zz_o4_replica() from public, anon, authenticated, service_role;
create event trigger zz_o4_replica_trigger on ddl_command_end
  when tag in ('CREATE TABLE') execute function public.zz_o4_replica();

create role zz_o4_ddl nologin;
grant zz_o4_ddl to postgres with set true, inherit false;
grant usage, create on schema public to zz_o4_ddl;

select ok(
  not has_function_privilege('zz_o4_ddl', 'public.zz_o4_replica()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.zz_o4_replica()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.zz_o4_replica()', 'EXECUTE'),
  'O-4 (réplica): sin EXECUTE para el rol del DDL, anon ni authenticated');

set local role zz_o4_ddl;
create table public.zz_o4_tabla (id integer);
reset role;

select results_eq(
  $$select quien, objeto from public.zz_o4_disparos$$,
  $$values ('postgres'::text, 'public.zz_o4_tabla'::text)$$,
  'O-4 (réplica): el event trigger se disparó y corrió como su owner aunque el rol del DDL no tenga EXECUTE');

select throws_ok($$select public.zz_o4_replica()$$, '0A000', null,
  'O-4 (réplica): una función event_trigger no se puede invocar directamente');

select * from finish();

rollback;
