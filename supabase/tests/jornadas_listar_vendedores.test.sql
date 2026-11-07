-- pgTAP: E-PL1 — listar_vendedores_jornada() y ampliación de D-2 a cinco columnas
-- (ADR-001 §18.4.2.2; Blueprint §7.5, §9, §10; ADR-007 §2.3).
--
-- Cubre: contrato exacto de las dos funciones, privilegios efectivos (has_*_privilege,
-- no sólo ACL), vista y rol lector (cinco columnas, opciones, dueño, ACL), positivos y
-- negativos de autorización y aislamiento por empresa, acceso directo a la función
-- privada y a la vista, atomicidad con fallo inyectado de la ventana de privilegios
-- transitorios, nombre no nulo ni vacío, y transacción de sólo lectura.
--
-- Fuera de pgTAP (no se puede probar desde SQL): que `privado` no esté expuesto por la
-- Data API (`[api] schemas` de supabase/config.toml); se verifica en la evidencia.
--
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(70);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('a3a3a3a3-0000-4000-8000-000000000000', 'Empresa A (test E-PL1)'),
  ('b3b3b3b3-0000-4000-8000-000000000000', 'Empresa B (test E-PL1)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('a3a3a3a3-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pl1.a1@usuarios.distribuidora.invalid', '{}'),
  ('a3a3a3a3-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'pl1.a2@usuarios.distribuidora.invalid', '{}'),
  ('a3a3a3a3-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'pl1.a3@usuarios.distribuidora.invalid', '{}'),
  ('a3a3a3a3-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'pl1.a4@usuarios.distribuidora.invalid', '{}'),
  ('a3a3a3a3-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'pl1.a5@usuarios.distribuidora.invalid', '{}'),
  ('a3a3a3a3-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'pl1.a6@usuarios.distribuidora.invalid', '{}'),
  ('a3a3a3a3-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'pl1.a7@usuarios.distribuidora.invalid', '{}'),
  ('b3b3b3b3-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pl1.b1@usuarios.distribuidora.invalid', '{}'),
  ('b3b3b3b3-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'pl1.b2@usuarios.distribuidora.invalid', '{}'),
  ('c3c3c3c3-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pl1.n1@usuarios.distribuidora.invalid', '{}');

-- Empresa A: A1 dueño, A2 encargado, A3 vendedor (nombre con espacios), A4 dueño
-- INACTIVO, A5 vendedor INACTIVO, A6 encargado INACTIVO, A7 encargado.
-- Empresa B: B1 dueño, B2 vendedor. N1: cuenta Auth sin perfil.
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('a3a3a3a3-0000-4000-8000-000000000001', 'a3a3a3a3-0000-4000-8000-000000000000', 'pl1.a1', 'Zeta Dueño', 'dueno', true),
  ('a3a3a3a3-0000-4000-8000-000000000002', 'a3a3a3a3-0000-4000-8000-000000000000', 'pl1.a2', 'alfa Encargado', 'encargado', true),
  ('a3a3a3a3-0000-4000-8000-000000000003', 'a3a3a3a3-0000-4000-8000-000000000000', 'pl1.a3', '  Beta Vendedor ', 'vendedor_piloto', true),
  ('a3a3a3a3-0000-4000-8000-000000000004', 'a3a3a3a3-0000-4000-8000-000000000000', 'pl1.a4', 'Dueño inactivo A', 'dueno', false),
  ('a3a3a3a3-0000-4000-8000-000000000005', 'a3a3a3a3-0000-4000-8000-000000000000', 'pl1.a5', 'Vendedor inactivo A', 'vendedor_piloto', false),
  ('a3a3a3a3-0000-4000-8000-000000000006', 'a3a3a3a3-0000-4000-8000-000000000000', 'pl1.a6', 'Encargado inactivo A', 'encargado', false),
  ('a3a3a3a3-0000-4000-8000-000000000007', 'a3a3a3a3-0000-4000-8000-000000000000', 'pl1.a7', 'Beta Encargado', 'encargado', true),
  ('b3b3b3b3-0000-4000-8000-000000000001', 'b3b3b3b3-0000-4000-8000-000000000000', 'pl1.b1', 'Dueño B', 'dueno', true),
  ('b3b3b3b3-0000-4000-8000-000000000002', 'b3b3b3b3-0000-4000-8000-000000000000', 'pl1.b2', 'Vendedor B', 'vendedor_piloto', true);

-- ===========================================================================
-- ES — estado estático (como propietario; antes de conceder USAGE sobre `extensions`)
-- ===========================================================================
select is(
  pg_get_function_result('public.listar_vendedores_jornada()'::regprocedure),
  'TABLE(usuario_id uuid, nombre text, rol text)',
  'ES1: la fachada devuelve exactamente TABLE(usuario_id uuid, nombre text, rol text)');

select is(
  pg_get_function_result('privado.listar_vendedores_jornada()'::regprocedure),
  'TABLE(usuario_id uuid, nombre text, rol text)',
  'ES2: la implementación privada devuelve exactamente la misma tabla');

select ok(
  exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
           where p.oid = 'public.listar_vendedores_jornada()'::regprocedure
             and l.lanname = 'sql' and not p.prosecdef and p.provolatile = 's' and p.pronargs = 0
             and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']),
  'ES3: la fachada es SQL, SECURITY INVOKER, STABLE, sin parámetros, owner postgres y search_path vacío');

select ok(
  exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
           where p.oid = 'privado.listar_vendedores_jornada()'::regprocedure
             and l.lanname = 'plpgsql' and p.prosecdef and p.provolatile = 's' and p.pronargs = 0
             and p.proowner = 'propietario_rpc'::regrole and p.proconfig = array['search_path=""']),
  'ES4: la implementación es plpgsql, SECURITY DEFINER, STABLE, sin parámetros, owner propietario_rpc y search_path vacío');

select is(
  (select count(*)::int from pg_proc
    where proname = 'listar_vendedores_jornada'
      and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)),
  2,
  'ES5: exactamente una función por esquema, sin sobrecargas');

select is(
  array(select a.grantee::regrole::text || ':' || a.privilege_type
          from pg_proc p, aclexplode(p.proacl) a
         where p.oid = 'public.listar_vendedores_jornada()'::regprocedure order by 1),
  array['authenticated:EXECUTE', 'postgres:EXECUTE'],
  'ES6: ACL exacta de la fachada: postgres y authenticated, sin PUBLIC');

select is(
  array(select a.grantee::regrole::text || ':' || a.privilege_type
          from pg_proc p, aclexplode(p.proacl) a
         where p.oid = 'privado.listar_vendedores_jornada()'::regprocedure order by 1),
  array['authenticated:EXECUTE', 'propietario_rpc:EXECUTE'],
  'ES7: ACL exacta de la implementación privada: propietario_rpc y authenticated, sin PUBLIC');

select ok(
  has_function_privilege('authenticated', 'public.listar_vendedores_jornada()', 'EXECUTE')
  and has_function_privilege('authenticated', 'privado.listar_vendedores_jornada()', 'EXECUTE')
  and has_schema_privilege('authenticated', 'privado', 'USAGE'),
  'ES8: privilegios efectivos de authenticated: EXECUTE de ambas funciones y USAGE de privado (necesarios para la fachada INVOKER)');

select ok(
  not exists (
    select 1 from unnest(array['anon', 'service_role', 'lector_perfiles_rpc']) r
     where has_function_privilege(r, 'public.listar_vendedores_jornada()', 'EXECUTE')
        or has_function_privilege(r, 'privado.listar_vendedores_jornada()', 'EXECUTE')
        or has_schema_privilege(r, 'privado', 'USAGE')),
  'ES9: privilegios efectivos: anon, service_role y lector_perfiles_rpc sin EXECUTE de las funciones ni USAGE de privado');

select ok(
  has_function_privilege('propietario_rpc', 'privado.listar_vendedores_jornada()', 'EXECUTE')
  and not has_function_privilege('propietario_rpc', 'public.listar_vendedores_jornada()', 'EXECUTE'),
  'ES10: propietario_rpc ejecuta la implementación privada y no la fachada');

select is(
  array(select attname::text from pg_attribute
         where attrelid = 'privado.perfiles_empresa_gestion'::regclass
           and attnum > 0 and not attisdropped
         order by attnum),
  array['usuario_id', 'empresa_id', 'rol', 'activo', 'nombre'],
  'ES11: la vista protegida expone exactamente cinco columnas, con nombre al final');

select ok(
  exists (select 1 from pg_class c
           where c.oid = 'privado.perfiles_empresa_gestion'::regclass and c.relkind = 'v'
             and c.relowner = 'lector_perfiles_rpc'::regrole
             and c.reloptions @> array['security_barrier=true', 'security_invoker=false']
             and cardinality(c.reloptions) = 2),
  'ES12: la vista conserva dueño lector_perfiles_rpc, security_barrier=true y security_invoker=false');

select is(
  coalesce((select array_agg(a.grantee::regrole::text || ':' || a.privilege_type
                              order by a.grantee::regrole::text, a.privilege_type)
              from pg_class c, aclexplode(c.relacl) a
             where c.oid = 'privado.perfiles_empresa_gestion'::regclass
               and a.grantee <> c.relowner), array[]::text[]),
  array['propietario_rpc:SELECT'],
  'ES13: ACL de la vista: sólo el dueño y SELECT de propietario_rpc');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.perfiles'::regclass and a.attnum > 0 and not a.attisdropped
           and has_column_privilege('lector_perfiles_rpc', 'public.perfiles', a.attname, 'SELECT')
         order by a.attnum),
  array['usuario_id', 'empresa_id', 'nombre', 'rol', 'activo'],
  'ES14: lector_perfiles_rpc tiene SELECT exactamente en cinco columnas de perfiles (sin usuario ni creado_en)');

select ok(
  not has_table_privilege('lector_perfiles_rpc', 'public.perfiles',
        'select, insert, update, delete, truncate, references, trigger')
  and not has_any_column_privilege('lector_perfiles_rpc', 'public.perfiles', 'insert, update, references'),
  'ES15: lector_perfiles_rpc sin privilegios de tabla ni de escritura sobre perfiles');

select ok(
  not has_schema_privilege('lector_perfiles_rpc', 'privado', 'USAGE')
  and not has_schema_privilege('lector_perfiles_rpc', 'privado', 'CREATE')
  and not has_schema_privilege('lector_perfiles_rpc', 'public', 'CREATE')
  and not exists (select 1 from pg_namespace n, aclexplode(n.nspacl) a
                   where a.grantee = 'lector_perfiles_rpc'::regrole),
  'ES16: lector_perfiles_rpc sin USAGE ni CREATE en privado, sin CREATE en public y sin entradas propias en la ACL de ningún esquema');

select ok(
  (select count(*) from pg_class where relowner = 'lector_perfiles_rpc'::regrole) = 1
  and not exists (select 1 from pg_proc where proowner = 'lector_perfiles_rpc'::regrole),
  'ES17: lector_perfiles_rpc es dueño de una sola relación (la vista) y de ninguna función');

select ok(
  not has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
  and not has_schema_privilege('propietario_rpc', 'public', 'CREATE'),
  'ES18: propietario_rpc sin CREATE residual sobre privado ni public');

select is(
  array(select policyname || ':' || cmd || ':' || roles::text
          from pg_policies where schemaname = 'public' and tablename = 'perfiles' order by policyname),
  array['perfiles_select_empresa_lector:SELECT:{lector_perfiles_rpc}',
        'perfiles_select_propio:SELECT:{authenticated}',
        'perfiles_select_propio_propietario_rpc:SELECT:{propietario_rpc}'],
  'ES19: las políticas de perfiles son exactamente las tres vigentes (E-PL1 no cambia la RLS)');

select ok(
  exists (select 1 from pg_class where oid = 'public.perfiles'::regclass
             and relrowsecurity and not relforcerowsecurity),
  'ES20: perfiles conserva RLS habilitada y sin FORCE');

select ok(
  not has_table_privilege('anon', 'privado.perfiles_empresa_gestion', 'SELECT, INSERT, UPDATE, DELETE')
  and not has_table_privilege('authenticated', 'privado.perfiles_empresa_gestion', 'SELECT, INSERT, UPDATE, DELETE')
  and not has_table_privilege('service_role', 'privado.perfiles_empresa_gestion', 'SELECT, INSERT, UPDATE, DELETE')
  and not has_column_privilege('anon', 'privado.perfiles_empresa_gestion', 'nombre', 'SELECT')
  and not has_column_privilege('authenticated', 'privado.perfiles_empresa_gestion', 'nombre', 'SELECT')
  and not has_column_privilege('service_role', 'privado.perfiles_empresa_gestion', 'nombre', 'SELECT'),
  'ES21: anon, authenticated y service_role sin acceso a la vista ni a su columna nombre (privilegios efectivos)');

select ok(
  not has_column_privilege('anon', 'public.perfiles', 'nombre', 'SELECT')
  and not has_column_privilege('service_role', 'public.perfiles', 'nombre', 'SELECT'),
  'ES22: anon y service_role sin SELECT sobre perfiles.nombre (sin privilegios nuevos)');

select ok(
  (select a.attnotnull from pg_attribute a
    where a.attrelid = 'public.perfiles'::regclass and a.attname = 'nombre')
  and exists (select 1 from pg_constraint
               where conrelid = 'public.perfiles'::regclass and conname = 'perfiles_nombre_no_vacio'
                 and pg_get_constraintdef(oid) like '%btrim%'),
  'ES23: perfiles.nombre es NOT NULL y tiene el CHECK perfiles_nombre_no_vacio (el contrato no necesita coalesce)');

-- A partir de acá, las pruebas cambian de rol: pgTAP vive en `extensions`.
grant usage on schema extensions to anon, authenticated, service_role,
  propietario_rpc, lector_perfiles_rpc;

-- ===========================================================================
-- Dueño de A (authenticated): resultado exacto
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select results_eq(
  $$select usuario_id, nombre, rol from public.listar_vendedores_jornada()$$,
  $$values ('a3a3a3a3-0000-4000-8000-000000000003'::uuid, '  Beta Vendedor '::text, 'vendedor_piloto'::text),
           ('a3a3a3a3-0000-4000-8000-000000000007', 'Beta Encargado', 'encargado'),
           ('a3a3a3a3-0000-4000-8000-000000000001', 'Zeta Dueño', 'dueno'),
           ('a3a3a3a3-0000-4000-8000-000000000002', 'alfa Encargado', 'encargado')$$,
  'L1: el dueño de A recibe sólo los 4 perfiles activos de A, con nombre almacenado tal cual y en orden COLLATE "C" (espacio < mayúsculas < minúsculas)');

select ok(
  (select array_agg(distinct rol order by rol) = array['dueno', 'encargado', 'vendedor_piloto']
     from public.listar_vendedores_jornada()),
  'L2: incluye los tres roles admitidos por ADR-007 §2.3');

select ok(
  exists (select 1 from public.listar_vendedores_jornada()
           where usuario_id = 'a3a3a3a3-0000-4000-8000-000000000001'),
  'L3: incluye al propio llamador');

select is(
  (select count(*)::int from public.listar_vendedores_jornada()
    where usuario_id in ('a3a3a3a3-0000-4000-8000-000000000004', 'a3a3a3a3-0000-4000-8000-000000000005',
                         'a3a3a3a3-0000-4000-8000-000000000006')),
  0,
  'L4: no devuelve perfiles inactivos (dueño, vendedor ni encargado)');

select is(
  (select count(*)::int from public.listar_vendedores_jornada()
    where usuario_id in ('b3b3b3b3-0000-4000-8000-000000000001', 'b3b3b3b3-0000-4000-8000-000000000002')),
  0,
  'L5: no devuelve perfiles de otra empresa');

select ok(
  (select count(*) = 4 and bool_and(nombre is not null and length(btrim(nombre)) > 0)
     from public.listar_vendedores_jornada()),
  'L6: ningún nombre es nulo ni vacío');

select is(
  (select count(*)::int from public.perfiles), 1,
  'L7: por la Data API authenticated sigue viendo únicamente su propio perfil');

select is(
  (select count(*)::int from public.perfiles where usuario_id <> 'a3a3a3a3-0000-4000-8000-000000000001'), 0,
  'L8: authenticated no lee el nombre de ningún otro perfil por public.perfiles');

-- Acceso directo a la implementación privada: mismas comprobaciones, mismos datos.
select results_eq(
  $$select usuario_id, nombre, rol from privado.listar_vendedores_jornada()$$,
  $$select usuario_id, nombre, rol from public.listar_vendedores_jornada()$$,
  'D1: la llamada directa a la función privada devuelve exactamente lo mismo que la fachada (no hay ruta con menos controles)');

select throws_ok('select * from privado.perfiles_empresa_gestion', '42501', null,
  'D2: authenticated no lee la vista protegida directamente');
select throws_ok('select privado.empresa_gestion_actual()', '42501', null,
  'D3: authenticated no ejecuta el helper empresa_gestion_actual');
reset role;

-- ===========================================================================
-- Encargado de A
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select results_eq(
  $$select usuario_id from public.listar_vendedores_jornada()$$,
  $$values ('a3a3a3a3-0000-4000-8000-000000000003'::uuid), ('a3a3a3a3-0000-4000-8000-000000000007'),
           ('a3a3a3a3-0000-4000-8000-000000000001'), ('a3a3a3a3-0000-4000-8000-000000000002')$$,
  'L9: el encargado activo de A recibe los mismos 4 perfiles, en el mismo orden');
reset role;

-- Encargado A7 (otro encargado activo) también autorizado
select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.listar_vendedores_jornada()), 4,
  'L10: otro encargado activo de A recibe los 4 perfiles');
reset role;

-- ===========================================================================
-- Dueño de B: sólo B
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"b3b3b3b3-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select results_eq(
  $$select usuario_id, nombre, rol from public.listar_vendedores_jornada()$$,
  $$values ('b3b3b3b3-0000-4000-8000-000000000001'::uuid, 'Dueño B'::text, 'dueno'::text),
           ('b3b3b3b3-0000-4000-8000-000000000002', 'Vendedor B', 'vendedor_piloto')$$,
  'L11: el dueño de B recibe únicamente los 2 perfiles de B (aislamiento por empresa_id)');
reset role;

-- ===========================================================================
-- N — negativos de autorización y autenticación
-- ===========================================================================
-- Vendedor activo de A
select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select throws_ok('select * from public.listar_vendedores_jornada()', 'PT403', 'jornada_no_autorizado',
  'N1: el vendedor/piloto activo no puede listar (PT403 jornada_no_autorizado)');
select throws_ok('select * from privado.listar_vendedores_jornada()', 'PT403', 'jornada_no_autorizado',
  'N2: el vendedor tampoco por llamada directa a la función privada (mismas comprobaciones)');
reset role;

-- Dueño inactivo
select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000004","role":"authenticated"}', true);
set local role authenticated;
select throws_ok('select * from public.listar_vendedores_jornada()', 'PT403', 'jornada_no_autorizado',
  'N3: un dueño inactivo no puede listar');
reset role;

-- Vendedor inactivo
select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000005","role":"authenticated"}', true);
set local role authenticated;
select throws_ok('select * from public.listar_vendedores_jornada()', 'PT403', 'jornada_no_autorizado',
  'N4: un vendedor inactivo no puede listar');
reset role;

-- Encargado inactivo
select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000006","role":"authenticated"}', true);
set local role authenticated;
select throws_ok('select * from public.listar_vendedores_jornada()', 'PT403', 'jornada_no_autorizado',
  'N5: un encargado inactivo no puede listar');
reset role;

-- Usuario autenticado sin perfil, aunque su user_metadata diga que es dueño de A
select set_config('request.jwt.claims',
  '{"sub":"c3c3c3c3-0000-4000-8000-000000000001","role":"authenticated","user_metadata":{"rol":"dueno","empresa_id":"a3a3a3a3-0000-4000-8000-000000000000"}}', true);
set local role authenticated;
select throws_ok('select * from public.listar_vendedores_jornada()', 'PT403', 'jornada_no_autorizado',
  'N6: un usuario sin perfil no puede listar, aunque su metadata diga dueño de A (la autoridad es la tabla)');
reset role;

-- Sin sub
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
set local role authenticated;
select throws_ok('select * from public.listar_vendedores_jornada()', 'PT401', 'jornada_no_autenticado',
  'N7: authenticated sin sub: PT401 jornada_no_autenticado');
select throws_ok('select * from privado.listar_vendedores_jornada()', 'PT401', 'jornada_no_autenticado',
  'N8: sin sub, la llamada directa a la función privada también da PT401');
reset role;

select set_config('request.jwt.claims', '', true);
set local role authenticated;
select throws_ok('select * from public.listar_vendedores_jornada()', 'PT401', 'jornada_no_autenticado',
  'N9: sin claims: PT401 jornada_no_autenticado');
reset role;

-- anon y service_role (con el sub de un dueño: el rol manda, no el claim)
select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role anon;
select throws_ok('select * from public.listar_vendedores_jornada()', '42501', null,
  'N10: anon no ejecuta la fachada');
select throws_ok('select * from privado.listar_vendedores_jornada()', '42501', null,
  'N11: anon no ejecuta la función privada (sin USAGE de privado)');
select throws_ok('select * from privado.perfiles_empresa_gestion', '42501', null,
  'N12: anon no lee la vista');
reset role;

set local role service_role;
select throws_ok('select * from public.listar_vendedores_jornada()', '42501', null,
  'N13: service_role no ejecuta la fachada (P11: sin excepciones nuevas)');
select throws_ok('select * from privado.listar_vendedores_jornada()', '42501', null,
  'N14: service_role no ejecuta la función privada');
select throws_ok('select * from privado.perfiles_empresa_gestion', '42501', null,
  'N15: service_role no lee la vista');
reset role;

-- lector_perfiles_rpc: sin EXECUTE ni USAGE (ES9) y, por la política, falla cerrado.
set local role lector_perfiles_rpc;
select throws_ok('select * from public.listar_vendedores_jornada()', '42501', null,
  'N16: lector_perfiles_rpc no ejecuta la fachada');
reset role;

-- ===========================================================================
-- V — la vista entrega nombre sólo a propietario_rpc, acotada a la empresa del llamador
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;
select is(
  (select count(*)::int from privado.perfiles_empresa_gestion where nombre is not null), 7,
  'V1: como propietario_rpc con el claim de un dueño de A, la vista da nombre de los 7 perfiles de A (incluidos inactivos)');
select is(
  (select count(*)::int from privado.perfiles_empresa_gestion
    where empresa_id = 'b3b3b3b3-0000-4000-8000-000000000000'), 0,
  'V2: la vista no da ningún perfil de B al dueño de A');
reset role;

select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role propietario_rpc;
select is((select count(*)::int from privado.perfiles_empresa_gestion), 0,
  'V3: con el claim de un vendedor la vista no da ninguna fila (la política exige dueño o encargado activo)');
reset role;

-- ===========================================================================
-- DP — defensa en profundidad (H-01): la función no depende sólo de la RLS del lector
-- ===========================================================================
-- Se simula un drift peligroso de la política del lector (USING true: la vista pasaría
-- a devolver perfiles de TODAS las empresas). La función compara además el empresa_id
-- con el del llamador, así que no debe filtrar nada de otra empresa. Se restaura la
-- política justo después (y la transacción se revierte al final).
alter policy perfiles_select_empresa_lector on public.perfiles using (true);

select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;
select is(
  (select count(*)::int from privado.perfiles_empresa_gestion
    where empresa_id = 'b3b3b3b3-0000-4000-8000-000000000000'),
  2,
  'DP1 (control): con la política alterada la vista SÍ devuelve los perfiles de B al dueño de A (el drift es real)');
reset role;

set local role authenticated;
select results_eq(
  $$select usuario_id from public.listar_vendedores_jornada()$$,
  $$values ('a3a3a3a3-0000-4000-8000-000000000003'::uuid), ('a3a3a3a3-0000-4000-8000-000000000007'),
           ('a3a3a3a3-0000-4000-8000-000000000001'), ('a3a3a3a3-0000-4000-8000-000000000002')$$,
  'DP2: con la política alterada la función sigue devolviendo sólo los 4 perfiles activos de A (ninguno de B)');
reset role;

select set_config('request.jwt.claims',
  '{"sub":"b3b3b3b3-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select results_eq(
  $$select usuario_id from public.listar_vendedores_jornada()$$,
  $$values ('b3b3b3b3-0000-4000-8000-000000000001'::uuid), ('b3b3b3b3-0000-4000-8000-000000000002')$$,
  'DP3: con la política alterada el dueño de B recibe sólo los 2 perfiles de B (ninguno de A)');
reset role;

select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select throws_ok('select * from public.listar_vendedores_jornada()', 'PT403', 'jornada_no_autorizado',
  'DP4: con la política alterada el vendedor sigue recibiendo PT403 (no se filtra nada)');
reset role;

alter policy perfiles_select_empresa_lector on public.perfiles
  using (empresa_id = (select privado.empresa_gestion_actual()));
select ok(
  (select qual ~ 'empresa_gestion_actual' and qual ~ 'empresa_id' and qual !~ '^true$'
     from pg_policies where schemaname = 'public' and tablename = 'perfiles'
      and policyname = 'perfiles_select_empresa_lector'),
  'DP5: la política del lector quedó restaurada (filtra empresa_id con empresa_gestion_actual)');

-- ===========================================================================
-- AT — atomicidad de la ventana de privilegios transitorios (fallo inyectado)
-- ===========================================================================
-- Repite los pasos de la migración (GRANT CREATE transitorio, SET ROLE, reemplazo de
-- la vista con una sexta columna distinta, RESET ROLE) y falla antes del REVOKE. El
-- sub-bloque debe deshacer TODO: ni grant residual ni vista modificada.
create temp table ventana_resultado (msg text);
do $$
declare
  v_msg text;
begin
  begin
    grant create on schema privado to lector_perfiles_rpc;
    execute 'set role lector_perfiles_rpc';
    create or replace view privado.perfiles_empresa_gestion
      with (security_invoker = false, security_barrier = true)
    as
    select p.usuario_id, p.empresa_id, p.rol, p.activo, p.nombre, p.creado_en
      from public.perfiles p;
    execute 'reset role';
    raise exception 'ventana|%|%',
      has_schema_privilege('lector_perfiles_rpc', 'privado', 'CREATE'),
      (select count(*) from pg_attribute
        where attrelid = 'privado.perfiles_empresa_gestion'::regclass
          and attnum > 0 and not attisdropped);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into ventana_resultado values (v_msg);
  end;
end $$;

select is((select msg from ventana_resultado), 'ventana|t|6',
  'AT1: dentro de la ventana el CREATE transitorio existía y la vista tenía 6 columnas (el fallo se inyectó tras el reemplazo)');
select ok(
  not has_schema_privilege('lector_perfiles_rpc', 'privado', 'CREATE')
  and not has_schema_privilege('lector_perfiles_rpc', 'privado', 'USAGE'),
  'AT2: tras el fallo inyectado no queda CREATE ni USAGE residual para lector_perfiles_rpc');
select is(
  array(select attname::text from pg_attribute
         where attrelid = 'privado.perfiles_empresa_gestion'::regclass and attnum > 0 and not attisdropped
         order by attnum),
  array['usuario_id', 'empresa_id', 'rol', 'activo', 'nombre'],
  'AT3: la vista volvió a sus cinco columnas (el reemplazo se deshizo)');
select ok(
  exists (select 1 from pg_class c
           where c.oid = 'privado.perfiles_empresa_gestion'::regclass
             and c.relowner = 'lector_perfiles_rpc'::regrole
             and c.reloptions @> array['security_barrier=true', 'security_invoker=false']
             and cardinality(c.reloptions) = 2),
  'AT4: dueño y opciones de la vista intactos tras el fallo inyectado');
select ok(current_user = 'postgres' and session_user = 'postgres',
  'AT5: el SET ROLE de la ventana se deshizo (current_user y session_user = postgres)');

-- ===========================================================================
-- NV — nombre no nulo ni vacío (el contrato no usa coalesce)
-- ===========================================================================
select throws_ok(
  $$update public.perfiles set nombre = null where usuario = 'pl1.a2'$$, '23502', null,
  'NV1: perfiles.nombre no admite NULL');
select throws_ok(
  $$update public.perfiles set nombre = '' where usuario = 'pl1.a2'$$, '23514', null,
  'NV2: perfiles.nombre no admite cadena vacía');
select throws_ok(
  $$update public.perfiles set nombre = '   ' where usuario = 'pl1.a2'$$, '23514', null,
  'NV3: perfiles.nombre no admite sólo espacios');

-- ===========================================================================
-- RO — lectura pura: se admite en una transacción de sólo lectura (E-SL1 no aplica)
-- ===========================================================================
-- Último: una vez en sólo lectura la transacción no vuelve a lectura-escritura.
select set_config('request.jwt.claims',
  '{"sub":"a3a3a3a3-0000-4000-8000-000000000001","role":"authenticated"}', true);
set transaction_read_only = on;
set local role authenticated;
select is((select count(*)::int from public.listar_vendedores_jornada()), 4,
  'RO1: la RPC de lectura funciona dentro de una transacción de sólo lectura');
reset role;

select * from finish();

rollback;
