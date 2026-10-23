-- pgTAP: Auth base — empresas y perfiles (Blueprint §7.3, §10, §12 Seguridad).
-- Ejecutar sólo en local: `supabase test db`.
--
-- Se usan dos empresas EXCLUSIVAMENTE para demostrar aislamiento. Esto no
-- habilita selector de empresa ni multiempresa funcional.

begin;

create extension if not exists pgtap with schema extensions;

select plan(55);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-0000-4000-8000-000000000000', 'Empresa A (test)'),
  ('bbbbbbbb-0000-4000-8000-000000000000', 'Empresa B (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  -- A1: dueño activo de A
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'test.a1@usuarios.distribuidora.invalid', '{}'),
  -- A2: vendedor activo de A, con metadata que pretende ser dueño de B
  ('aaaaaaaa-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'test.a2@usuarios.distribuidora.invalid',
   '{"rol":"dueno","empresa_id":"bbbbbbbb-0000-4000-8000-000000000000"}'),
  -- A3: perfil inactivo de A
  ('aaaaaaaa-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'test.a3@usuarios.distribuidora.invalid', '{}'),
  -- B1: encargado activo de B
  ('bbbbbbbb-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'test.b1@usuarios.distribuidora.invalid', '{}'),
  -- N1: cuenta Auth sin perfil, con metadata falsa
  ('cccccccc-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'test.n1@usuarios.distribuidora.invalid',
   '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}'),
  -- D1–D3: cuentas Auth para los casos positivos del formato de usuario
  ('dddddddd-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'abc@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'a_b-c.d@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'limite32@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000000',
   'test.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000000',
   'test.a2', 'A2', 'vendedor_piloto', true),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000000',
   'test.a3', 'A3', 'vendedor_piloto', false),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000000',
   'test.b1', 'B1', 'encargado', true);

-- Simula la identidad de la Data API: rol `authenticated` + claims del JWT.
create function pg_temp.como_usuario(uid uuid, metadata jsonb default '{}')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated',
                       'user_metadata', metadata)::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.como_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
end $$;

-- ---------------------------------------------------------------------------
-- 12. RLS habilitada en todas las tablas expuestas creadas (catálogo)
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity),
  0,
  '12. todas las tablas de public tienen RLS habilitada');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.empresas'::regclass),
  '12. RLS habilitada en empresas');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.perfiles'::regclass),
  '12. RLS habilitada en perfiles');

select is(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and tablename in ('empresas', 'perfiles')
      and cmd <> 'SELECT'),
  0,
  'no existen políticas de escritura sobre empresas/perfiles');

select is(
  (select count(*)::int from pg_proc
    where pronamespace = 'public'::regnamespace and prosecdef),
  0,
  'no hay funciones SECURITY DEFINER en public');

select ok(
  not has_table_privilege('anon', 'public.empresas', 'select')
  and not has_table_privilege('anon', 'public.perfiles', 'select'),
  'anon no tiene SELECT sobre empresas ni perfiles');

select ok(
  not has_table_privilege('authenticated', 'public.perfiles', 'insert')
  and not has_table_privilege('authenticated', 'public.perfiles', 'update')
  and not has_table_privilege('authenticated', 'public.perfiles', 'delete')
  and not has_table_privilege('authenticated', 'public.empresas', 'insert')
  and not has_table_privilege('authenticated', 'public.empresas', 'update')
  and not has_table_privilege('authenticated', 'public.empresas', 'delete'),
  'authenticated no tiene INSERT/UPDATE/DELETE sobre empresas ni perfiles');

-- Restricciones de datos del perfil
select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('cccccccc-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', 'x.y', 'X', 'administrador')$$,
  '23514', null, 'rol fuera de dueno/encargado/vendedor_piloto es rechazado');

select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('cccccccc-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', 'Juan', 'X', 'dueno')$$,
  '23514', null, 'usuario no normalizado (mayúsculas) es rechazado');

select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('cccccccc-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', 'test.a1', 'X', 'dueno')$$,
  '23505', null, 'usuario duplicado es rechazado');

select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('aaaaaaaa-0000-4000-8000-000000000001',
            'bbbbbbbb-0000-4000-8000-000000000000', 'test.otro', 'X', 'dueno')$$,
  '23505', null, 'un usuario no puede tener un segundo perfil (otra empresa)');

-- Formato de usuario (LOW-02): 3–32 caracteres, empieza y termina con a-z/0-9,
-- interiores a-z 0-9 . _ -, sin puntos consecutivos. Mismo contrato que
-- apps/web/src/domain/usuario_auth.ts.
select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('cccccccc-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', 'abc.', 'X', 'dueno')$$,
  '23514', null, 'usuario que termina con punto es rechazado');

select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('cccccccc-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', '.aabc', 'X', 'dueno')$$,
  '23514', null, 'usuario que empieza con punto es rechazado');

select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('cccccccc-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', 'a..b', 'X', 'dueno')$$,
  '23514', null, 'usuario con puntos consecutivos es rechazado');

select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('cccccccc-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', 'juan-', 'X', 'dueno')$$,
  '23514', null, 'usuario que termina con guion es rechazado');

select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('cccccccc-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', 'ab', 'X', 'dueno')$$,
  '23514', null, 'usuario de menos de 3 caracteres es rechazado');

select throws_ok(
  format($$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('cccccccc-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', %L, 'X', 'dueno')$$,
         repeat('a', 33)),
  '23514', null, 'usuario de más de 32 caracteres es rechazado');

select lives_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('dddddddd-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', 'abc', 'D1', 'vendedor_piloto')$$,
  'usuario de 3 caracteres es aceptado');

select lives_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('dddddddd-0000-4000-8000-000000000002',
            'aaaaaaaa-0000-4000-8000-000000000000', 'a_b-c.d', 'D2', 'vendedor_piloto')$$,
  'usuario con punto, guion y guion bajo interiores es aceptado');

select lives_ok(
  format($$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('dddddddd-0000-4000-8000-000000000003',
            'aaaaaaaa-0000-4000-8000-000000000000', %L, 'D3', 'vendedor_piloto')$$,
         repeat('a', 32)),
  'usuario de 32 caracteres es aceptado');

-- ---------------------------------------------------------------------------
-- 1–2. anon
-- ---------------------------------------------------------------------------
-- Huella del contenido completo de ambas tablas antes de los intentos de anon.
create temp table huella_antes_anon as
  select (select md5(string_agg(e::text, '|' order by e.id)) from public.empresas e) as empresas,
         (select md5(string_agg(p::text, '|' order by p.usuario_id)) from public.perfiles p) as perfiles;

select pg_temp.como_anon();

select throws_ok('select * from public.empresas', '42501', null,
  '1. anon no puede leer empresas');
select throws_ok('select * from public.perfiles', '42501', null,
  '2. anon no puede leer perfiles');

-- Escrituras efectivas de anon (LOW-03). UPDATE y DELETE van sin WHERE: si
-- alguien concediera esos privilegios a anon, la sentencia no fallaría (RLS
-- filtraría 0 filas) y estas pruebas lo detectarían. Un INSERT concedido
-- seguiría fallando por RLS con el mismo 42501: lo detecta la prueba de
-- catálogo de más abajo.
select throws_ok(
  $$insert into public.empresas (nombre) values ('Empresa anon')$$,
  '42501', null, 'anon no puede insertar empresas');
select throws_ok(
  $$update public.empresas set activo = false$$,
  '42501', null, 'anon no puede modificar empresas');
select throws_ok(
  $$delete from public.empresas$$,
  '42501', null, 'anon no puede borrar empresas');
select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('cccccccc-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', 'anon.x', 'X', 'dueno')$$,
  '42501', null, 'anon no puede insertar perfiles');
select throws_ok(
  $$update public.perfiles set rol = 'dueno'$$,
  '42501', null, 'anon no puede modificar perfiles');
select throws_ok(
  $$delete from public.perfiles$$,
  '42501', null, 'anon no puede borrar perfiles');

reset role;

-- Catálogo: anon no tiene ningún privilegio de tabla (incluye lo heredado de
-- PUBLIC).
select ok(
  not has_table_privilege('anon', 'public.empresas',
    'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'),
  'anon no tiene ningún privilegio sobre empresas');
select ok(
  not has_table_privilege('anon', 'public.perfiles',
    'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'),
  'anon no tiene ningún privilegio sobre perfiles');

select results_eq(
  $$select (select md5(string_agg(e::text, '|' order by e.id)) from public.empresas e),
           (select md5(string_agg(p::text, '|' order by p.usuario_id)) from public.perfiles p)$$,
  'select empresas, perfiles from huella_antes_anon',
  'los intentos de anon no crearon, modificaron ni borraron filas');

-- authenticated sin sub (auth.uid() nulo) no ve nada
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
set local role authenticated;
select is_empty('select 1 from public.perfiles',
  'authenticated sin sub no ve perfiles');
select is_empty('select 1 from public.empresas',
  'authenticated sin sub no ve empresas');
reset role;

-- ---------------------------------------------------------------------------
-- 3–5. Usuario A1 (dueño activo de A)
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');

select results_eq(
  'select usuario_id from public.perfiles',
  $$values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid)$$,
  '3. authenticated sólo ve su propio perfil');

select is_empty(
  $$select 1 from public.perfiles
    where usuario_id in ('aaaaaaaa-0000-4000-8000-000000000002',
                         'bbbbbbbb-0000-4000-8000-000000000001')$$,
  '4. usuario A no ve perfiles de otros usuarios (misma ni otra empresa)');

select results_eq(
  'select id from public.empresas',
  $$values ('aaaaaaaa-0000-4000-8000-000000000000'::uuid)$$,
  '5. usuario de empresa A sólo obtiene su empresa');

select is_empty(
  $$select 1 from public.empresas
    where id = 'bbbbbbbb-0000-4000-8000-000000000000'$$,
  '5. usuario de empresa A no obtiene empresa B');

-- ---------------------------------------------------------------------------
-- 7–10. Escrituras prohibidas
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update public.perfiles set rol = 'dueno'
    where usuario_id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  '42501', null, '7. authenticated no puede cambiar su rol');

select throws_ok(
  $$update public.perfiles set empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000'
    where usuario_id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  '42501', null, '8. authenticated no puede cambiar su empresa_id');

select throws_ok(
  $$update public.perfiles set activo = false
    where usuario_id = 'aaaaaaaa-0000-4000-8000-000000000002'$$,
  '42501', null, '9. authenticated no puede desactivar perfiles');

select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('cccccccc-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000000', 'nuevo.x', 'X', 'dueno')$$,
  '42501', null, '10. authenticated no puede insertar perfiles');

select throws_ok(
  $$delete from public.perfiles
    where usuario_id = 'aaaaaaaa-0000-4000-8000-000000000002'$$,
  '42501', null, '10. authenticated no puede borrar perfiles');

select throws_ok(
  $$insert into public.empresas (nombre) values ('Empresa intrusa')$$,
  '42501', null, 'authenticated no puede crear empresas');

select throws_ok(
  $$update public.empresas set activo = false$$,
  '42501', null, 'authenticated no puede modificar empresas');

reset role;

-- Nada cambió
select results_eq(
  $$select rol, empresa_id::text, activo from public.perfiles
    where usuario_id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  $$values ('dueno'::text, 'aaaaaaaa-0000-4000-8000-000000000000'::text, true)$$,
  '7–8. rol y empresa de A1 siguen intactos');

select is(
  (select count(*)::int from public.perfiles
    where usuario_id = 'aaaaaaaa-0000-4000-8000-000000000002' and activo),
  1, '9–10. perfil de A2 sigue existiendo y activo');

-- ---------------------------------------------------------------------------
-- 6. Perfil inactivo
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');

select results_eq(
  'select activo from public.perfiles',
  $$values (false)$$,
  '6. el usuario inactivo ve sólo su perfil, marcado inactivo');

select is_empty('select 1 from public.empresas',
  '6. perfil inactivo no obtiene su empresa');

select throws_ok(
  $$update public.perfiles set activo = true
    where usuario_id = 'aaaaaaaa-0000-4000-8000-000000000003'$$,
  '42501', null, '9. un perfil inactivo no puede activarse a sí mismo');

reset role;

-- ---------------------------------------------------------------------------
-- 11. user_metadata falso no concede rol ni empresa
-- ---------------------------------------------------------------------------
-- N1: cuenta sin perfil, con metadata y claims que dicen "dueño de A".
select pg_temp.como_usuario('cccccccc-0000-4000-8000-000000000001',
  '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');

select is_empty('select 1 from public.perfiles',
  '11. usuario sin perfil con user_metadata falso no ve perfiles');
select is_empty('select 1 from public.empresas',
  '11. usuario sin perfil con user_metadata falso no obtiene empresas');

reset role;

-- A2: vendedor de A cuya metadata dice "dueño de B".
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002',
  '{"rol":"dueno","empresa_id":"bbbbbbbb-0000-4000-8000-000000000000"}');

select results_eq(
  'select rol from public.perfiles',
  $$values ('vendedor_piloto'::text)$$,
  '11. el rol efectivo es el del perfil, no el de user_metadata');

select results_eq(
  'select id from public.empresas',
  $$values ('aaaaaaaa-0000-4000-8000-000000000000'::uuid)$$,
  '11. user_metadata no da acceso a la empresa B');

reset role;

-- ---------------------------------------------------------------------------
-- Aislamiento desde la empresa B
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');

select results_eq(
  'select id from public.empresas',
  $$values ('bbbbbbbb-0000-4000-8000-000000000000'::uuid)$$,
  '5. usuario de empresa B sólo obtiene la empresa B');

select is_empty(
  $$select 1 from public.perfiles
    where empresa_id = 'aaaaaaaa-0000-4000-8000-000000000000'$$,
  '4. usuario de B no ve perfiles de A');

reset role;

select * from finish();

rollback;
