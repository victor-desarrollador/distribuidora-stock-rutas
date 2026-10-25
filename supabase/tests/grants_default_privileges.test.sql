-- pgTAP: hardening de grants y privilegios por defecto (Blueprint §10, §12
-- Seguridad; ADR-001 §12.4, §12.6, §12.7, §12.8, §17.3 y §18.1 P11-productos).
-- Ejecutar sólo en local: `supabase test db`.
--
-- Falla si reaparece O-1 (service_role sin SELECT sobre productos) u O-2
-- (privilegios de tabla innecesarios o privilegios por defecto amplios para
-- objetos futuros), o si service_role se sale de P11 global (denegado por
-- defecto; única excepción nominada: SELECT sobre productos), incluido
-- MAINTAIN.

begin;

create extension if not exists pgtap with schema extensions;

select plan(32);

-- ---------------------------------------------------------------------------
-- Matriz esperada de privilegios de tabla
-- ---------------------------------------------------------------------------
-- P11 global: service_role sólo tiene la excepción nominada SELECT sobre
-- productos. MAINTAIN (PostgreSQL 17) también se evalúa.
create temp table matriz (tabla text, rol text, privilegio text, esperado boolean);

insert into matriz
select t.tabla, r.rol, p.privilegio,
  case
    when r.rol = 'anon' then false
    when r.rol = 'authenticated' then p.privilegio = 'SELECT'
    when r.rol = 'service_role' and t.tabla = 'public.productos'
      then p.privilegio = 'SELECT'
    when r.rol = 'service_role' then false
  end
from (values ('public.empresas'), ('public.perfiles'), ('public.productos'),
             ('public.camiones'), ('public.clientes'), ('public.ubicaciones')) t(tabla),
     (values ('anon'), ('authenticated'), ('service_role')) r(rol),
     (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
             ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')) p(privilegio);

-- ---------------------------------------------------------------------------
-- Tablas existentes: matriz por rol
-- ---------------------------------------------------------------------------
select is_empty(
  $$select tabla, privilegio from matriz
     where rol = 'anon' and esperado is not null
       and has_table_privilege('anon', tabla, privilegio) <> esperado$$,
  'anon no tiene ningún privilegio de tabla sobre empresas, perfiles, productos, camiones ni clientes');

select is_empty(
  $$select tabla, privilegio from matriz
     where rol = 'authenticated' and esperado is not null
       and has_table_privilege('authenticated', tabla, privilegio) <> esperado$$,
  'authenticated tiene sólo SELECT (sin INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) en las seis tablas');

select is_empty(
  $$select tabla, privilegio from matriz
     where rol = 'service_role' and tabla = 'public.productos' and esperado is not null
       and has_table_privilege('service_role', tabla, privilegio) <> esperado$$,
  'O-1: service_role tiene SELECT y ningún otro privilegio sobre productos');

select ok(
  has_table_privilege('service_role', 'public.productos', 'select'),
  'O-1: service_role conserva SELECT sobre productos (ADR-001 §18.1 P11-productos)');

select is_empty(
  $$select tabla, privilegio from matriz
     where rol = 'service_role' and tabla <> 'public.productos' and esperado is not null
       and has_table_privilege('service_role', tabla, privilegio) <> esperado$$,
  'P11: service_role no tiene ningún privilegio (ni SELECT ni MAINTAIN) sobre empresas, perfiles, camiones, clientes ni ubicaciones');

-- Privilegios por columna (un GRANT por columna no aparece en la ACL de tabla).
select ok(
  not has_any_column_privilege('anon', 'public.empresas', 'select, insert, update, references')
  and not has_any_column_privilege('anon', 'public.perfiles', 'select, insert, update, references')
  and not has_any_column_privilege('anon', 'public.productos', 'select, insert, update, references')
  and not has_any_column_privilege('anon', 'public.camiones', 'select, insert, update, references')
  and not has_any_column_privilege('anon', 'public.ubicaciones', 'select, insert, update, references'),
  'anon no tiene privilegios por columna en las tablas de negocio');

select ok(
  not has_any_column_privilege('authenticated', 'public.empresas', 'insert, update, references')
  and not has_any_column_privilege('authenticated', 'public.perfiles', 'insert, update, references')
  and not has_any_column_privilege('authenticated', 'public.productos', 'insert, update, references')
  and not has_any_column_privilege('authenticated', 'public.camiones', 'insert, update, references')
  and not has_any_column_privilege('authenticated', 'public.ubicaciones', 'insert, update, references'),
  'authenticated no tiene INSERT/UPDATE/REFERENCES por columna en las tablas de negocio');

select ok(
  not has_any_column_privilege('service_role', 'public.productos', 'insert, update, references'),
  'service_role no tiene INSERT/UPDATE/REFERENCES por columna sobre productos');

select ok(
  not exists (
    select 1 from pg_class c, aclexplode(c.relacl) a
     where c.oid in ('public.empresas'::regclass, 'public.perfiles'::regclass,
                     'public.productos'::regclass, 'public.camiones'::regclass,
                     'public.clientes'::regclass, 'public.ubicaciones'::regclass)
       and a.grantee = 0),
  'PUBLIC no tiene privilegios sobre las seis tablas');

-- ---------------------------------------------------------------------------
-- Catálogo genérico: cualquier tabla futura de public que se salga del modelo
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
      and has_table_privilege('anon', c.oid,
            'select, insert, update, delete, truncate, references, trigger')),
  0,
  'ninguna tabla de public concede algún privilegio a anon');

select is(
  (select count(*)::int from pg_class c, unnest(array['anon', 'authenticated', 'service_role']) r
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
      and has_table_privilege(r, c.oid, 'truncate, references, trigger')),
  0,
  'ninguna tabla de public concede TRUNCATE/REFERENCES/TRIGGER a anon, authenticated ni service_role');

-- Si una tabla futura necesita escritura directa de authenticated, esa decisión
-- debe tomarse y probarse de forma explícita (Blueprint §10): se actualiza esta prueba.
select is(
  (select count(*)::int from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
      and has_table_privilege('authenticated', c.oid, 'insert, update, delete')),
  0,
  'ninguna tabla de public concede INSERT/UPDATE/DELETE directos a authenticated');

select is(
  (select count(*)::int from pg_class c
    where c.relnamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and c.relkind = 'S'
      and (has_sequence_privilege('anon', c.oid, 'usage, select, update')
        or has_sequence_privilege('authenticated', c.oid, 'usage, select, update')
        or has_sequence_privilege('service_role', c.oid, 'usage, select, update'))),
  0,
  'ninguna secuencia de public ni privado concede privilegios a anon, authenticated ni service_role');

-- ---------------------------------------------------------------------------
-- Funciones: sin EXECUTE para PUBLIC ni anon; Topología D intacta
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and (p.proacl is null
           or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0))),
  0,
  'ninguna función de public ni privado conserva EXECUTE para PUBLIC');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and has_function_privilege('anon', p.oid, 'execute')),
  0,
  'anon no ejecuta ninguna función de public ni privado');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and has_function_privilege('service_role', p.oid, 'execute')),
  0,
  'service_role no ejecuta ninguna función de public ni privado');

select is(
  array(select p.oid::regprocedure::text from pg_proc p
         where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
           and has_function_privilege('authenticated', p.oid, 'execute')
         order by 1),
  array['actualizar_camion(uuid,text,text)',
        'actualizar_cliente(uuid,text,text,text,text)',
        'actualizar_producto(uuid,text,text,numeric,integer)',
        'cambiar_estado_camion(uuid,boolean)',
        'cambiar_estado_cliente(uuid,boolean)',
        'cambiar_estado_producto(uuid,boolean)',
        'crear_camion(text,text)',
        'crear_cliente(text,text,text,text)',
        'crear_producto(text,text,text,text,numeric,integer)',
        'privado.actualizar_camion(uuid,text,text)',
        'privado.actualizar_cliente(uuid,text,text,text,text)',
        'privado.actualizar_producto(uuid,text,text,numeric,integer)',
        'privado.cambiar_estado_camion(uuid,boolean)',
        'privado.cambiar_estado_cliente(uuid,boolean)',
        'privado.cambiar_estado_producto(uuid,boolean)',
        'privado.crear_camion(text,text)',
        'privado.crear_cliente(text,text,text,text)',
        'privado.crear_producto(text,text,text,text,numeric,integer)',
        'privado.validar_cliente(uuid)',
        'validar_cliente(uuid)'],
  'authenticated ejecuta únicamente las veinte firmas aprobadas: productos, camiones y clientes (Topología D sin cambios)');

-- ---------------------------------------------------------------------------
-- pg_default_acl del rol creador de las migraciones (postgres)
-- ---------------------------------------------------------------------------
select ok(
  not exists (
    select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
     where d.defaclrole = 'postgres'::regrole
       and d.defaclnamespace = 'public'::regnamespace
       and d.defaclobjtype = 'r'
       and (a.grantee = 0 or a.grantee::regrole::text in ('anon', 'authenticated', 'service_role'))),
  'default de tablas nuevas de postgres en public: nada para PUBLIC, anon, authenticated ni service_role');

select ok(
  not exists (
    select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
     where d.defaclrole = 'postgres'::regrole
       and d.defaclnamespace = 'public'::regnamespace
       and d.defaclobjtype = 'S'
       and (a.grantee = 0 or a.grantee::regrole::text in ('anon', 'authenticated', 'service_role'))),
  'default de secuencias nuevas de postgres en public: nada para PUBLIC, anon, authenticated ni service_role');

select ok(
  not exists (
    select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
     where d.defaclrole = 'postgres'::regrole
       and d.defaclnamespace = 'public'::regnamespace
       and d.defaclobjtype = 'f'
       and (a.grantee = 0 or a.grantee::regrole::text in ('anon', 'authenticated', 'service_role'))),
  'default de funciones nuevas de postgres en public: sin EXECUTE para PUBLIC, anon, authenticated ni service_role');

-- Sin la entrada global, PostgreSQL concede EXECUTE a PUBLIC de forma implícita
-- (un REVOKE por esquema no la elimina; ADR-001 §12.6).
select ok(
  exists (
    select 1 from pg_default_acl d
     where d.defaclrole = 'postgres'::regrole
       and d.defaclnamespace = 0
       and d.defaclobjtype = 'f')
  and not exists (
    select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
     where d.defaclrole = 'postgres'::regrole
       and d.defaclnamespace = 0
       and d.defaclobjtype = 'f'
       and a.grantee = 0),
  'default global de funciones nuevas de postgres (incluye privado): sin EXECUTE para PUBLIC');

select is(
  (select count(*)::int from pg_default_acl d
    where d.defaclrole = 'postgres'::regrole
      and d.defaclnamespace = 'privado'::regnamespace),
  0,
  'no hay privilegios por defecto específicos para el esquema privado');

-- ---------------------------------------------------------------------------
-- Comportamiento: objetos nuevos creados por postgres no heredan privilegios
-- ---------------------------------------------------------------------------
-- Se crean dentro de la transacción del test y se revierten al final.
select is(current_user::text, 'postgres',
  'las pruebas de objetos nuevos corren como el rol creador de las migraciones');

create table public.zz_tabla_nueva (id integer);
create sequence public.zz_secuencia_nueva;
create function public.zz_funcion_nueva() returns integer
  language sql as 'select 1';
create function privado.zz_funcion_nueva() returns integer
  language sql as 'select 1';

select is(
  (select count(*)::int from unnest(array['anon', 'authenticated', 'service_role']) r
    where has_table_privilege(r, 'public.zz_tabla_nueva',
            'select, insert, update, delete, truncate, references, trigger')),
  0,
  'una tabla nueva de public no concede privilegios a anon, authenticated ni service_role');

select ok(
  (select c.relacl is null
       or not exists (select 1 from aclexplode(c.relacl) a where a.grantee <> c.relowner)
     from pg_class c where c.oid = 'public.zz_tabla_nueva'::regclass),
  'la ACL de una tabla nueva sólo contiene a su propietario');

select is(
  (select count(*)::int from unnest(array['anon', 'authenticated', 'service_role']) r
    where has_sequence_privilege(r, 'public.zz_secuencia_nueva', 'usage, select, update')),
  0,
  'una secuencia nueva de public no concede privilegios a anon, authenticated ni service_role');

select is(
  (select count(*)::int from unnest(array['anon', 'authenticated', 'service_role']) r
    where has_function_privilege(r, 'public.zz_funcion_nueva()', 'execute')),
  0,
  'una función nueva de public no concede EXECUTE a anon, authenticated ni service_role');

select ok(
  (select p.proacl is not null
          and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
     from pg_proc p where p.oid = 'public.zz_funcion_nueva()'::regprocedure),
  'una función nueva de public no concede EXECUTE a PUBLIC');

select is(
  (select count(*)::int from unnest(array['anon', 'authenticated', 'service_role']) r
    where has_function_privilege(r, 'privado.zz_funcion_nueva()', 'execute')),
  0,
  'una función nueva de privado no concede EXECUTE a anon, authenticated ni service_role');

select ok(
  (select p.proacl is not null
          and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
     from pg_proc p where p.oid = 'privado.zz_funcion_nueva()'::regprocedure),
  'una función nueva de privado no concede EXECUTE a PUBLIC');

-- Prueba real: authenticated tiene USAGE sobre privado (Topología D) pero no
-- puede ejecutar una función privada nueva.
create function pg_temp.como_authenticated()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}', true);
  execute 'set local role authenticated';
end $$;

select pg_temp.como_authenticated();

select throws_ok(
  $$select privado.zz_funcion_nueva()$$,
  '42501', null,
  'authenticated no puede ejecutar una función nueva de privado (aunque tiene USAGE)');

select throws_ok(
  $$select public.zz_funcion_nueva()$$,
  '42501', null,
  'authenticated no puede ejecutar una función nueva de public');

reset role;

select * from finish();

rollback;
