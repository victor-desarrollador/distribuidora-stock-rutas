-- pgTAP: D-2 — rol técnico lector_perfiles_rpc y lectura acotada de perfiles
-- (ADR-001 §18.4.2.1 y §18.4.9 grupo P; Blueprint §7.3, §10, §12 Seguridad).
-- Casos P2–P10, P13 y P14. P1 (membresía) está en hardening_adr001.test.sql.
--
-- P11 y P12 (abrir_jornada y reasignar_vendedor con vendedor de otra empresa,
-- inexistente o inactivo) quedan DIFERIDOS a la implementación de las RPC de
-- jornadas: dependen de funciones que todavía no existen. No se cuentan como
-- cumplidos por D-2.
--
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(52);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('a2a2a2a2-0000-4000-8000-000000000000', 'Empresa A (test D-2)'),
  ('b2b2b2b2-0000-4000-8000-000000000000', 'Empresa B (test D-2)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('a2a2a2a2-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'd2.a1@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'd2.a2@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'd2.a3@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'd2.a4@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'd2.a5@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'd2.a6@usuarios.distribuidora.invalid', '{}'),
  ('b2b2b2b2-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'd2.b1@usuarios.distribuidora.invalid', '{}'),
  ('b2b2b2b2-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'd2.b2@usuarios.distribuidora.invalid', '{}'),
  ('c2c2c2c2-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'd2.n1@usuarios.distribuidora.invalid', '{}');

-- Empresa A: 6 perfiles (A1 dueño, A2 encargado, A3 vendedor, A4 dueño
-- INACTIVO, A5 vendedor INACTIVO, A6 encargado). Empresa B: B1 dueño, B2
-- vendedor. N1: cuenta Auth sin perfil.
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('a2a2a2a2-0000-4000-8000-000000000001', 'a2a2a2a2-0000-4000-8000-000000000000', 'd2.a1', 'Dueño A', 'dueno', true),
  ('a2a2a2a2-0000-4000-8000-000000000002', 'a2a2a2a2-0000-4000-8000-000000000000', 'd2.a2', 'Encargado A', 'encargado', true),
  ('a2a2a2a2-0000-4000-8000-000000000003', 'a2a2a2a2-0000-4000-8000-000000000000', 'd2.a3', 'Vendedor A', 'vendedor_piloto', true),
  ('a2a2a2a2-0000-4000-8000-000000000004', 'a2a2a2a2-0000-4000-8000-000000000000', 'd2.a4', 'Dueño inactivo A', 'dueno', false),
  ('a2a2a2a2-0000-4000-8000-000000000005', 'a2a2a2a2-0000-4000-8000-000000000000', 'd2.a5', 'Vendedor inactivo A', 'vendedor_piloto', false),
  ('a2a2a2a2-0000-4000-8000-000000000006', 'a2a2a2a2-0000-4000-8000-000000000000', 'd2.a6', 'Encargado 2 A', 'encargado', true),
  ('b2b2b2b2-0000-4000-8000-000000000001', 'b2b2b2b2-0000-4000-8000-000000000000', 'd2.b1', 'Dueño B', 'dueno', true),
  ('b2b2b2b2-0000-4000-8000-000000000002', 'b2b2b2b2-0000-4000-8000-000000000000', 'd2.b2', 'Vendedor B', 'vendedor_piloto', true);

-- ===========================================================================
-- P2 — rol: atributos, privilegios y ausencia de privilegios residuales
-- (se verifica antes de conceder USAGE sobre `extensions`, que sólo necesitan
-- las pruebas para llamar a pgTAP con el rol cambiado)
-- ===========================================================================
select ok(
  coalesce((select not (rolcanlogin or rolsuper or rolcreatedb or rolcreaterole
                        or rolreplication or rolbypassrls)
              from pg_roles where rolname = 'lector_perfiles_rpc'), false),
  'P2: lector_perfiles_rpc existe y es NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS');

select ok(
  (select bool_and(has_column_privilege('lector_perfiles_rpc', 'public.perfiles', c, 'SELECT'))
     from unnest(array['usuario_id', 'empresa_id', 'rol', 'activo']) c),
  'P2: SELECT por columna sobre usuario_id, empresa_id, rol y activo de perfiles');

select ok(
  not exists (
    select 1 from unnest(array['usuario', 'nombre', 'creado_en']) c
     where has_column_privilege('lector_perfiles_rpc', 'public.perfiles', c, 'SELECT')),
  'P2: sin SELECT sobre usuario, nombre ni creado_en');

select ok(
  not has_table_privilege('lector_perfiles_rpc', 'public.perfiles',
        'select, insert, update, delete, truncate, references, trigger')
  and not has_any_column_privilege('lector_perfiles_rpc', 'public.perfiles',
        'insert, update, references'),
  'P2: sin privilegios de tabla ni INSERT/UPDATE/REFERENCES por columna sobre perfiles');

select is(
  (select count(*)::int from pg_class c
    where c.relnamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and c.relkind in ('r', 'p', 'v', 'm', 'f')
      and c.oid not in ('public.perfiles'::regclass, 'privado.perfiles_empresa_gestion'::regclass)
      and has_any_column_privilege('lector_perfiles_rpc', c.oid, 'select, insert, update, references')),
  0,
  'P2: ningún privilegio sobre otras tablas o vistas de public ni privado');

select ok(
  not has_schema_privilege('lector_perfiles_rpc', 'privado', 'CREATE')
  and not has_schema_privilege('lector_perfiles_rpc', 'privado', 'USAGE')
  and not has_schema_privilege('lector_perfiles_rpc', 'public', 'CREATE')
  and not has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
  and not has_schema_privilege('propietario_rpc', 'public', 'CREATE')
  and not exists (select 1 from pg_namespace n, aclexplode(n.nspacl) a
                   where a.grantee = 'lector_perfiles_rpc'::regrole),
  'P2: sin CREATE residual (ni lector ni propietario_rpc), sin USAGE sobre privado y sin ningún grant de esquema al rol');

select ok(
  (select count(*) from pg_class where relowner = 'lector_perfiles_rpc'::regrole) = 1
  and not exists (select 1 from pg_proc where proowner = 'lector_perfiles_rpc'::regrole)
  and not exists (select 1 from pg_namespace where nspowner = 'lector_perfiles_rpc'::regrole)
  and (select relowner from pg_class where oid = 'privado.perfiles_empresa_gestion'::regclass)
        = 'lector_perfiles_rpc'::regrole,
  'P2: lector_perfiles_rpc es dueño de exactamente una relación (la vista), de ninguna función ni esquema');

-- ===========================================================================
-- P3 — helper privado.empresa_gestion_actual()
-- ===========================================================================
select ok(
  (select p.prosecdef and p.provolatile = 's' and p.pronargs = 0
          and p.proowner = 'propietario_rpc'::regrole
          and p.prorettype = 'uuid'::regtype
          and p.proconfig @> array['search_path=""']
          and l.lanname = 'sql'
     from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = 'privado.empresa_gestion_actual()'::regprocedure),
  'P3: helper SECURITY DEFINER, STABLE, sin parámetros, devuelve uuid, search_path vacío y owner propietario_rpc');

select is(
  array(select a.grantee::regrole::text || ':' || a.privilege_type
          from pg_proc p, aclexplode(p.proacl) a
         where p.oid = 'privado.empresa_gestion_actual()'::regprocedure
         order by 1),
  array['propietario_rpc:EXECUTE'],
  'P3: la ACL del helper contiene únicamente EXECUTE de propietario_rpc (sin PUBLIC)');

select ok(
  not exists (
    select 1 from unnest(array['lector_perfiles_rpc', 'authenticated', 'anon', 'service_role', 'postgres']) r
     where has_function_privilege(r, 'privado.empresa_gestion_actual()', 'EXECUTE')),
  'P3: ni lector_perfiles_rpc, ni authenticated, anon, service_role ni postgres ejecutan el helper');

select is(
  (select count(*)::int from pg_proc
    where pronamespace = 'privado'::regnamespace and proname = 'empresa_gestion_actual'),
  1,
  'P3: el helper no tiene sobrecargas');

-- ===========================================================================
-- P4 — vista privado.perfiles_empresa_gestion
-- ===========================================================================
select ok(
  (select c.relkind = 'v'
          and c.relowner = 'lector_perfiles_rpc'::regrole
          and c.reloptions @> array['security_barrier=true', 'security_invoker=false']
     from pg_class c where c.oid = 'privado.perfiles_empresa_gestion'::regclass),
  'P4: vista de owner lector_perfiles_rpc con security_barrier=true y security_invoker=false');

select is(
  array(select attname::text from pg_attribute
         where attrelid = 'privado.perfiles_empresa_gestion'::regclass
           and attnum > 0 and not attisdropped
         order by attnum),
  array['usuario_id', 'empresa_id', 'rol', 'activo'],
  'P4: la vista expone exactamente usuario_id, empresa_id, rol y activo');

select is(
  array(select a.grantee::regrole::text || ':' || a.privilege_type
          from pg_class c, aclexplode(c.relacl) a
         where c.oid = 'privado.perfiles_empresa_gestion'::regclass
           and a.grantee <> c.relowner
         order by 1),
  array['propietario_rpc:SELECT'],
  'P4: la ACL de la vista, además de su owner, contiene únicamente SELECT de propietario_rpc');

-- ===========================================================================
-- P5 — políticas de perfiles
-- ===========================================================================
select is(
  array(select policyname || ':' || cmd || ':' || roles::text
          from pg_policies where schemaname = 'public' and tablename = 'perfiles'
         order by policyname),
  array['perfiles_select_empresa_lector:SELECT:{lector_perfiles_rpc}',
        'perfiles_select_propio:SELECT:{authenticated}',
        'perfiles_select_propio_propietario_rpc:SELECT:{propietario_rpc}'],
  'P5: las dos políticas previas no cambian, hay una sola nueva y ninguna de escritura');

select ok(
  (select qual ~ 'empresa_gestion_actual' and qual ~ 'empresa_id'
     from pg_policies
    where schemaname = 'public' and tablename = 'perfiles'
      and policyname = 'perfiles_select_empresa_lector'),
  'P5: la política del lector filtra empresa_id con privado.empresa_gestion_actual()');

select ok(
  (select relrowsecurity and not relforcerowsecurity
     from pg_class where oid = 'public.perfiles'::regclass),
  'P5: perfiles conserva RLS habilitada y sin FORCE');

-- A partir de acá, las pruebas cambian de rol: pgTAP vive en `extensions`.
grant usage on schema extensions to anon, authenticated, service_role,
  propietario_rpc, lector_perfiles_rpc;

-- ===========================================================================
-- P6 — dueño de A, leyendo como propietario_rpc
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"a2a2a2a2-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;

select results_eq(
  $$select usuario_id from privado.perfiles_empresa_gestion order by usuario_id$$,
  $$values ('a2a2a2a2-0000-4000-8000-000000000001'::uuid),
           ('a2a2a2a2-0000-4000-8000-000000000002'),
           ('a2a2a2a2-0000-4000-8000-000000000003'),
           ('a2a2a2a2-0000-4000-8000-000000000004'),
           ('a2a2a2a2-0000-4000-8000-000000000005'),
           ('a2a2a2a2-0000-4000-8000-000000000006')$$,
  'P6: dueño de A lee los 6 perfiles de A (sin 42P17 ni 54001)');

select is(
  (select count(*)::int from privado.perfiles_empresa_gestion
    where empresa_id = 'b2b2b2b2-0000-4000-8000-000000000000'),
  0,
  'P6: dueño de A no ve ningún perfil de B');

select ok(
  (select count(*) filter (where not activo) = 2
          and count(*) filter (where rol = 'vendedor_piloto') = 2
     from privado.perfiles_empresa_gestion),
  'P6: la vista incluye perfiles inactivos y vendedores de la propia empresa');

-- ===========================================================================
-- P7 — otros llamadores
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"a2a2a2a2-0000-4000-8000-000000000002","role":"authenticated"}', true);
select is((select count(*)::int from privado.perfiles_empresa_gestion), 6,
  'P7: encargado de A lee los 6 perfiles de A');

select set_config('request.jwt.claims',
  '{"sub":"a2a2a2a2-0000-4000-8000-000000000003","role":"authenticated"}', true);
select is((select count(*)::int from privado.perfiles_empresa_gestion), 0,
  'P7: vendedor de A (activo) ve 0 filas');

select set_config('request.jwt.claims',
  '{"sub":"a2a2a2a2-0000-4000-8000-000000000004","role":"authenticated"}', true);
select is((select count(*)::int from privado.perfiles_empresa_gestion), 0,
  'P7: dueño inactivo de A ve 0 filas');

select set_config('request.jwt.claims',
  '{"sub":"a2a2a2a2-0000-4000-8000-000000000005","role":"authenticated"}', true);
select is((select count(*)::int from privado.perfiles_empresa_gestion), 0,
  'P7: vendedor inactivo de A ve 0 filas');

select set_config('request.jwt.claims',
  '{"sub":"c2c2c2c2-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is((select count(*)::int from privado.perfiles_empresa_gestion), 0,
  'P7: usuario sin perfil ve 0 filas');

select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select is((select count(*)::int from privado.perfiles_empresa_gestion), 0,
  'P7: llamador sin sub ve 0 filas');

select set_config('request.jwt.claims', '', true);
select is((select count(*)::int from privado.perfiles_empresa_gestion), 0,
  'P7: llamador sin claims ve 0 filas');

-- ===========================================================================
-- P8 — dueño de B
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"b2b2b2b2-0000-4000-8000-000000000001","role":"authenticated"}', true);
select results_eq(
  $$select usuario_id from privado.perfiles_empresa_gestion order by usuario_id$$,
  $$values ('b2b2b2b2-0000-4000-8000-000000000001'::uuid),
           ('b2b2b2b2-0000-4000-8000-000000000002')$$,
  'P8: dueño de B lee sólo los 2 perfiles de B');

select is(
  (select count(*)::int from privado.perfiles_empresa_gestion
    where empresa_id = 'a2a2a2a2-0000-4000-8000-000000000000'),
  0,
  'P8: dueño de B no ve ningún perfil de A');

-- ===========================================================================
-- P9 — propietario_rpc sobre public.perfiles sigue viendo sólo su fila
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"a2a2a2a2-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is((select count(*)::int from public.perfiles), 1,
  'P9: propietario_rpc, SELECT directo de public.perfiles con el claim de un dueño: una sola fila');
select is((select usuario_id from public.perfiles),
  'a2a2a2a2-0000-4000-8000-000000000001'::uuid,
  'P9: esa fila es la del llamador');

-- Escritura sobre la vista por el rol técnico: rechazada.
select throws_ok(
  $$insert into privado.perfiles_empresa_gestion (usuario_id, empresa_id, rol, activo)
    values (gen_random_uuid(), 'a2a2a2a2-0000-4000-8000-000000000000', 'dueno', true)$$,
  '42501', null, 'propietario_rpc no inserta en la vista');
select throws_ok(
  $$update privado.perfiles_empresa_gestion set activo = false$$,
  '42501', null, 'propietario_rpc no actualiza la vista');
select throws_ok(
  $$delete from privado.perfiles_empresa_gestion$$,
  '42501', null, 'propietario_rpc no borra de la vista');
reset role;

-- ===========================================================================
-- P10 — authenticated, anon y service_role
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"a2a2a2a2-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select throws_ok('select count(*) from privado.perfiles_empresa_gestion', '42501', null,
  'P10: authenticated no lee la vista');
select throws_ok('select privado.empresa_gestion_actual()', '42501', null,
  'P10: authenticated no ejecuta el helper');
select throws_ok(
  $$insert into privado.perfiles_empresa_gestion (usuario_id, empresa_id, rol, activo)
    values (gen_random_uuid(), 'a2a2a2a2-0000-4000-8000-000000000000', 'dueno', true)$$,
  '42501', null, 'P10: authenticated no escribe en la vista');
select is((select count(*)::int from public.perfiles), 1,
  'P10: authenticated sigue viendo sólo su propio perfil en public.perfiles (sin cambio)');
reset role;

set local role anon;
select throws_ok('select count(*) from privado.perfiles_empresa_gestion', '42501', null,
  'P10: anon no lee la vista');
select throws_ok('select privado.empresa_gestion_actual()', '42501', null,
  'P10: anon no ejecuta el helper');
reset role;

set local role service_role;
select throws_ok('select count(*) from privado.perfiles_empresa_gestion', '42501', null,
  'P10: service_role no lee la vista');
select throws_ok('select privado.empresa_gestion_actual()', '42501', null,
  'P10: service_role no ejecuta el helper');
select throws_ok('select count(*) from public.perfiles', '42501', null,
  'P10: service_role no lee public.perfiles');
reset role;

-- ===========================================================================
-- P13 — el EXECUTE del helper se verifica contra el llamador, no contra el
-- dueño de la vista. Todo se restituye explícitamente (sin savepoints: pgTAP
-- guarda sus resultados en tablas temporales de esta misma transacción).
-- ===========================================================================
set local role propietario_rpc;
revoke execute on function privado.empresa_gestion_actual() from propietario_rpc;
reset role;

select set_config('request.jwt.claims',
  '{"sub":"a2a2a2a2-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;
select throws_ok('select count(*) from privado.perfiles_empresa_gestion', '42501', null,
  'P13: sin EXECUTE del helper para propietario_rpc, leer la vista falla con 42501 (el privilegio se verifica contra el llamador)');
reset role;

set local role propietario_rpc;
grant execute on function privado.empresa_gestion_actual() to propietario_rpc;
reset role;

select is(
  array(select a.grantee::regrole::text || ':' || a.privilege_type
          from pg_proc p, aclexplode(p.proacl) a
         where p.oid = 'privado.empresa_gestion_actual()'::regprocedure
         order by 1),
  array['propietario_rpc:EXECUTE'],
  'P13: la ACL del helper quedó restituida');

set local role propietario_rpc;
select is((select count(*)::int from privado.perfiles_empresa_gestion), 6,
  'P13: con el EXECUTE restituido, el dueño de A vuelve a leer los 6 perfiles');
reset role;

-- ===========================================================================
-- P14 — leer perfiles como lector_perfiles_rpc falla cerrado
-- ===========================================================================
-- Para llegar a la política hay que pedir sólo las cuatro columnas concedidas:
-- con `select *` el rechazo es anterior (privilegio de columna sobre usuario,
-- nombre y creado_en) y no demuestra nada sobre la política. Los mensajes se
-- comparan además del SQLSTATE para fijar la causa; dependen de lc_messages
-- en inglés (Supabase local: en_US.UTF-8).
set local role lector_perfiles_rpc;
select throws_ok(
  $$select usuario_id, empresa_id, rol, activo from public.perfiles$$,
  '42501', 'permission denied for function empresa_gestion_actual',
  'P14: lector_perfiles_rpc, SELECT de las cuatro columnas concedidas de public.perfiles: 42501 por falta de EXECUTE del helper de la política (falla cerrado, sin recursión)');
select throws_ok('select * from public.perfiles', '42501', 'permission denied for table perfiles',
  'P14 (privilegio de columna): SELECT * de public.perfiles como lector falla antes de evaluar la política, porque usuario, nombre y creado_en no están concedidas');
select throws_ok(
  $$insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol)
    values ('c2c2c2c2-0000-4000-8000-000000000001', 'a2a2a2a2-0000-4000-8000-000000000000',
            'd2.n1x', 'X', 'dueno')$$,
  '42501', null, 'P14: lector_perfiles_rpc no inserta perfiles');
reset role;

-- Con USAGE transitorio sobre public y privado (dentro de la transacción de
-- prueba) el resultado no cambia: `public` ya es usable por herencia de PUBLIC,
-- y la lectura de las cuatro columnas y la de la vista fallan por el EXECUTE
-- del helper de la política; `select *` sigue fallando por las columnas.
grant usage on schema public, privado to lector_perfiles_rpc;
set local role lector_perfiles_rpc;
select throws_ok(
  $$select usuario_id, empresa_id, rol, activo from public.perfiles$$,
  '42501', 'permission denied for function empresa_gestion_actual',
  'P14: con USAGE de esquema, leer las cuatro columnas de perfiles como lector falla con 42501 por el EXECUTE del helper (no recursa)');
select throws_ok('select * from public.perfiles', '42501', 'permission denied for table perfiles',
  'P14 (privilegio de columna): con USAGE de esquema, SELECT * de public.perfiles sigue fallando por las columnas no concedidas');
select throws_ok('select * from privado.perfiles_empresa_gestion', '42501',
  'permission denied for function empresa_gestion_actual',
  'P14: el propio lector tampoco puede leer su vista: 42501 por falta de EXECUTE del helper');
reset role;

select * from finish();

rollback;
