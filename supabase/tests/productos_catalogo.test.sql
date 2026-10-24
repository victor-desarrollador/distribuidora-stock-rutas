-- pgTAP: catálogo de productos (Blueprint §7.1, §8, §9, §10, §12 Seguridad;
-- ADR-001 Topología D y §16; ADR-003; decisiones del slice productos).
-- Ejecutar sólo en local: `supabase test db`.
--
-- Se usan dos empresas EXCLUSIVAMENTE para demostrar aislamiento.

begin;

create extension if not exists pgtap with schema extensions;

select plan(125);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-0000-4000-8000-000000000000', 'Empresa A (test)'),
  ('bbbbbbbb-0000-4000-8000-000000000000', 'Empresa B (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  -- A1: dueño activo de A
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'prod.a1@usuarios.distribuidora.invalid', '{}'),
  -- A2: encargado activo de A
  ('aaaaaaaa-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'prod.a2@usuarios.distribuidora.invalid', '{}'),
  -- A3: vendedor activo de A, con metadata que pretende ser dueño
  ('aaaaaaaa-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'prod.a3@usuarios.distribuidora.invalid', '{"rol":"dueno"}'),
  -- A4: dueño INACTIVO de A
  ('aaaaaaaa-0000-4000-8000-000000000004', 'authenticated', 'authenticated',
   'prod.a4@usuarios.distribuidora.invalid', '{}'),
  -- B1: dueño activo de B
  ('bbbbbbbb-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'prod.b1@usuarios.distribuidora.invalid', '{}'),
  -- N1: cuenta Auth sin perfil, con metadata falsa
  ('cccccccc-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'prod.n1@usuarios.distribuidora.invalid',
   '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000000',
   'prod.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000000',
   'prod.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000000',
   'prod.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000000',
   'prod.a4', 'A4', 'dueno', false),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000000',
   'prod.b1', 'B1', 'dueno', true);

insert into public.productos (
  id, empresa_id, codigo, nombre, categoria, forma_venta, precio,
  stock_minimo, creado_por
) values
  ('aaaaaaaa-0000-4000-8000-00000000a001', 'aaaaaaaa-0000-4000-8000-000000000000',
   'C-1', 'Yogur A', 'lacteos', 'unidad', 100.00, 5,
   'aaaaaaaa-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-00000000a002', 'aaaaaaaa-0000-4000-8000-000000000000',
   null, 'Jamón A', 'fiambres', 'pieza', 21.00, 2,
   'aaaaaaaa-0000-4000-8000-000000000001'),
  ('bbbbbbbb-0000-4000-8000-00000000b001', 'bbbbbbbb-0000-4000-8000-000000000000',
   'C-2', 'Leche B', 'lacteos', 'unidad', 50.00, 0,
   'bbbbbbbb-0000-4000-8000-000000000001');

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

-- Los privilegios por defecto de postgres ya no dan EXECUTE a PUBLIC en
-- funciones nuevas (migración de hardening): los helpers se invocan también
-- desde los roles simulados, así que lo conceden de forma explícita.
grant execute on function pg_temp.como_usuario(uuid, jsonb) to public;
grant execute on function pg_temp.como_anon() to public;

-- Firmas exactas (P14-productos: sin sobrecargas).
create temp table firmas (firma text, expuesta boolean);
insert into firmas values
  ('public.crear_producto(text,text,text,text,numeric,integer)', true),
  ('public.actualizar_producto(uuid,text,text,numeric,integer)', true),
  ('public.cambiar_estado_producto(uuid,boolean)', true),
  ('privado.crear_producto(text,text,text,text,numeric,integer)', false),
  ('privado.actualizar_producto(uuid,text,text,numeric,integer)', false),
  ('privado.cambiar_estado_producto(uuid,boolean)', false);
grant select on firmas to public;

-- ---------------------------------------------------------------------------
-- Catálogo: tabla, RLS y grants
-- ---------------------------------------------------------------------------
select ok(
  (select relrowsecurity and not relforcerowsecurity
     from pg_class where oid = 'public.productos'::regclass),
  'productos tiene RLS habilitada y sin FORCE (P4)');

select is(
  (select count(*)::int from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity),
  0,
  'todas las tablas de public tienen RLS habilitada');

select ok(
  has_table_privilege('authenticated', 'public.productos', 'select'),
  'authenticated puede leer productos');

select ok(
  not has_table_privilege('authenticated', 'public.productos',
        'insert, update, delete, truncate, references, trigger')
  and not has_any_column_privilege('authenticated', 'public.productos', 'insert')
  and not has_any_column_privilege('authenticated', 'public.productos', 'update'),
  'authenticated no tiene INSERT/UPDATE/DELETE/TRUNCATE sobre productos (ni por columna)');

select ok(
  not has_table_privilege('anon', 'public.productos',
        'select, insert, update, delete, truncate, references, trigger')
  and not has_any_column_privilege('anon', 'public.productos',
        'select, insert, update, references'),
  'anon no tiene ningún privilegio sobre productos');

select ok(
  not exists (
    select 1 from pg_class c, aclexplode(c.relacl) a
     where c.oid = 'public.productos'::regclass and a.grantee = 0),
  'PUBLIC no tiene privilegios sobre productos');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.productos'::regclass and a.attnum > 0
           and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.productos', a.attname, 'insert')
         order by a.attname::text),
  array['categoria', 'codigo', 'creado_por', 'empresa_id', 'forma_venta',
        'nombre', 'precio', 'stock_minimo'],
  'propietario_rpc inserta sólo las columnas de negocio (sin id, activo, creado_en)');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.productos'::regclass and a.attnum > 0
           and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.productos', a.attname, 'update')
         order by a.attname::text),
  array['activo', 'codigo', 'nombre', 'precio', 'stock_minimo'],
  'propietario_rpc actualiza sólo codigo, nombre, precio, stock_minimo y activo (DE-6)');

select ok(
  not has_table_privilege('propietario_rpc', 'public.productos', 'delete, truncate'),
  'propietario_rpc no puede borrar ni truncar productos');

select ok(
  not has_table_privilege('propietario_rpc', 'public.perfiles', 'insert, update, delete, truncate')
  and not has_table_privilege('propietario_rpc', 'public.empresas',
        'select, insert, update, delete, truncate'),
  'propietario_rpc sólo lee perfiles y no toca empresas');

-- ---------------------------------------------------------------------------
-- Catálogo: rol técnico, esquema privado y funciones
-- ---------------------------------------------------------------------------
select ok(
  (select not rolcanlogin and not rolsuper and not rolcreatedb
          and not rolcreaterole and not rolbypassrls and not rolreplication
     from pg_roles where rolname = 'propietario_rpc'),
  'propietario_rpc es NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS (P3)');

select is(
  (select count(*)::int from pg_class
    where relowner = 'propietario_rpc'::regrole),
  0,
  'propietario_rpc no es propietario de ninguna tabla (P4)');

select ok(
  not has_schema_privilege('anon', 'privado', 'usage')
  and not exists (
    select 1 from pg_namespace n, aclexplode(n.nspacl) a
     where n.nspname = 'privado' and a.grantee = 0),
  'anon y PUBLIC no tienen USAGE sobre privado');

select ok(
  has_schema_privilege('authenticated', 'privado', 'usage')
  and not has_schema_privilege('authenticated', 'privado', 'create')
  and not has_schema_privilege('propietario_rpc', 'privado', 'create'),
  'privado: authenticated sólo USAGE; nadie de la app puede crear objetos');

select is(
  array(select p.oid::regprocedure::text from pg_proc p
         where p.prosecdef
           and p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
         order by 1),
  array['privado.actualizar_camion(uuid,text,text)',
        'privado.actualizar_cliente(uuid,text,text,text,text)',
        'privado.actualizar_producto(uuid,text,text,numeric,integer)',
        'privado.cambiar_estado_camion(uuid,boolean)',
        'privado.cambiar_estado_cliente(uuid,boolean)',
        'privado.cambiar_estado_producto(uuid,boolean)',
        'privado.crear_camion(text,text)',
        'privado.crear_cliente(text,text,text,text)',
        'privado.crear_producto(text,text,text,text,numeric,integer)',
        'privado.validar_cliente(uuid)'],
  'sólo las diez implementaciones privadas (productos, camiones y clientes) son SECURITY DEFINER');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and (p.proowner <> 'propietario_rpc'::regrole
           or p.proconfig is null
           or not p.proconfig @> array['search_path=""'])),
  0,
  'toda función de privado es de propietario_rpc y fija search_path vacío');

select is(
  (select count(*)::int from firmas f
     join pg_proc p on p.oid = f.firma::regprocedure
    where f.expuesta
      and (p.prosecdef
           or p.proowner = 'propietario_rpc'::regrole
           or p.provolatile <> 'v'
           or not p.proconfig @> array['search_path=""'])),
  0,
  'las fachadas son SECURITY INVOKER, VOLATILE, con search_path vacío y no son de propietario_rpc');

select is(
  (select count(*)::int from firmas f
     join pg_proc p on p.oid = f.firma::regprocedure
    where not f.expuesta and p.provolatile <> 'v'),
  0,
  'las implementaciones privadas son VOLATILE (GET responde 405)');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and p.proname in ('crear_producto', 'actualizar_producto',
                        'cambiar_estado_producto')),
  6,
  'P14-productos: una única firma por nombre y esquema (sin sobrecargas)');

select is(
  (select count(*)::int from firmas f
    where not has_function_privilege('authenticated', f.firma, 'execute')),
  0,
  'authenticated puede ejecutar las seis firmas aprobadas');

select is(
  (select count(*)::int from firmas f
    where has_function_privilege('anon', f.firma, 'execute')
       or has_function_privilege('service_role', f.firma, 'execute')),
  0,
  'anon y service_role no pueden ejecutar ninguna RPC de productos');

-- P11-productos (complemento): service_role no participa de la escritura.
select ok(
  has_table_privilege('service_role', 'public.productos', 'select'),
  'service_role puede leer productos');

select ok(
  not has_table_privilege('service_role', 'public.productos',
        'insert, update, delete, truncate, references, trigger'),
  'service_role no tiene INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER sobre productos');

select ok(
  not has_any_column_privilege('service_role', 'public.productos',
        'insert, update, references'),
  'service_role no tiene INSERT/UPDATE/REFERENCES por columna sobre productos');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('privado'::regnamespace, 'public'::regnamespace)
      and p.proname in ('crear_producto', 'actualizar_producto',
                        'cambiar_estado_producto')
      and has_function_privilege('service_role', p.oid, 'execute')),
  0,
  'service_role no ejecuta ninguna fachada ni implementación de productos');

select is(
  (select count(*)::int from firmas f
     join pg_proc p on p.oid = f.firma::regprocedure
    where p.proacl is null
       or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)),
  0,
  'ninguna RPC de productos conserva EXECUTE para PUBLIC');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.oid::regprocedure::text not in (select firma from firmas)
      -- Las implementaciones de camiones y clientes las cubren
      -- camiones_catalogo.test.sql y clientes_catalogo.test.sql.
      and p.proname not in ('crear_camion', 'actualizar_camion',
                            'cambiar_estado_camion', 'crear_cliente',
                            'actualizar_cliente', 'validar_cliente',
                            'cambiar_estado_cliente')
      and (has_function_privilege('authenticated', p.oid, 'execute')
           or has_function_privilege('anon', p.oid, 'execute')
           or p.proacl is null
           or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0))),
  0,
  'los auxiliares de privado sólo los ejecuta propietario_rpc');

-- ---------------------------------------------------------------------------
-- privado.usuario_actual() coincide con auth.uid()
-- ---------------------------------------------------------------------------
-- usuario_actual() sólo lo ejecuta su owner, propietario_rpc (postgres ya no
-- hereda ese EXECUTE: O-3), y propietario_rpc no tiene USAGE sobre `auth`.
-- auth.uid() se evalúa como postgres y se compara como propietario_rpc.
create temp table uid_esperado (caso text, uid uuid);
grant select on uid_esperado to public;
grant usage on schema extensions to propietario_rpc;

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}', true);
insert into uid_esperado select 'claims', auth.uid();
set local role propietario_rpc;
select is(privado.usuario_actual(), (select uid from uid_esperado where caso = 'claims'),
  'usuario_actual = auth.uid() con claims completos');
reset role;

select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-4000-8000-000000000001', true);
insert into uid_esperado select 'sub', auth.uid();
set local role propietario_rpc;
select is(privado.usuario_actual(), (select uid from uid_esperado where caso = 'sub'),
  'usuario_actual = auth.uid() con el claim sub heredado');
reset role;
select set_config('request.jwt.claim.sub', '', true);

select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
insert into uid_esperado select 'sin_sub', auth.uid();
set local role propietario_rpc;
select ok(privado.usuario_actual() is null
          and (select uid from uid_esperado where caso = 'sin_sub') is null,
  'usuario_actual y auth.uid() son nulos sin sub');
reset role;

select set_config('request.jwt.claims', '', true);
insert into uid_esperado select 'sin_claims', auth.uid();
set local role propietario_rpc;
select ok(privado.usuario_actual() is null
          and (select uid from uid_esperado where caso = 'sin_claims') is null,
  'usuario_actual y auth.uid() son nulos sin claims');
reset role;

-- ---------------------------------------------------------------------------
-- Bypass directo: authenticated no escribe la tabla
-- ---------------------------------------------------------------------------
create temp table huella_antes as
  select md5(string_agg(p::text, '|' order by p.id)) as productos
    from public.productos p;
grant select on huella_antes to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');

select throws_ok(
  $$insert into public.productos (empresa_id, nombre, categoria, forma_venta,
                                  precio, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'Directo', 'lacteos',
            'unidad', 20.999, 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'el dueño no puede insertar directamente (saltear la validación de precio)');

select throws_ok(
  $$update public.productos set precio = 20.999$$,
  '42501', null, 'el dueño no puede actualizar directamente');

select throws_ok(
  $$delete from public.productos$$,
  '42501', null, 'el dueño no puede borrar productos');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');

select throws_ok(
  $$update public.productos set precio = 1$$,
  '42501', null, 'el vendedor no puede cambiar precios directamente (§9)');

select pg_temp.como_anon();

select throws_ok('select * from public.productos', '42501', null,
  'anon no puede leer productos');

select throws_ok(
  $$select public.crear_producto(null, 'X', 'lacteos', 'unidad', 1, 0)$$,
  '42501', null, 'anon no puede ejecutar crear_producto');

select throws_ok(
  $$select privado.crear_producto(null, 'X', 'lacteos', 'unidad', 1, 0)$$,
  '42501', null, 'anon no puede ejecutar la implementación privada');

reset role;

select is(
  (select md5(string_agg(p::text, '|' order by p.id)) from public.productos p),
  (select productos from huella_antes),
  'los intentos directos no cambiaron ningún producto');

-- ---------------------------------------------------------------------------
-- Lectura por empresa y estado del perfil (DE-9)
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select results_eq(
  $$select id from public.productos
     where id::text like 'aaaaaaaa%' or id::text like 'bbbbbbbb%' order by id$$,
  $$values ('aaaaaaaa-0000-4000-8000-00000000a001'::uuid),
           ('aaaaaaaa-0000-4000-8000-00000000a002'::uuid)$$,
  'el vendedor lee los productos de su empresa y no los de otra');

select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select results_eq(
  $$select id from public.productos
     where id::text like 'aaaaaaaa%' or id::text like 'bbbbbbbb%' order by id$$,
  $$values ('bbbbbbbb-0000-4000-8000-00000000b001'::uuid)$$,
  'el dueño de B sólo ve productos de B');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000004');
select is((select count(*)::int from public.productos), 0,
  'un perfil inactivo no ve productos');

select pg_temp.como_usuario('cccccccc-0000-4000-8000-000000000001',
  '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');
select is((select count(*)::int from public.productos), 0,
  'una cuenta sin perfil no ve productos, aunque su metadata diga dueño');

-- ---------------------------------------------------------------------------
-- Autorización de las RPC (P10-productos)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$select public.crear_producto(null, 'X', 'lacteos', 'unidad', 1, 0)$$,
  'PT403', 'producto_no_autorizado', 'una cuenta sin perfil no puede crear');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000004');
select throws_ok(
  $$select public.crear_producto(null, 'X', 'lacteos', 'unidad', 1, 0)$$,
  'PT403', 'producto_no_autorizado', 'un dueño inactivo no puede crear');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003', '{"rol":"dueno"}');
select throws_ok(
  $$select public.crear_producto(null, 'X', 'lacteos', 'unidad', 1, 0)$$,
  'PT403', 'producto_no_autorizado', 'el vendedor no puede crear (metadata ignorada)');
select throws_ok(
  $$select public.actualizar_producto('aaaaaaaa-0000-4000-8000-00000000a001',
                                      'C-1', 'Yogur A', 1, 5)$$,
  'PT403', 'producto_no_autorizado', 'el vendedor no puede editar ni cambiar precios');
select throws_ok(
  $$select public.cambiar_estado_producto('aaaaaaaa-0000-4000-8000-00000000a001', false)$$,
  'PT403', 'producto_no_autorizado', 'el vendedor no puede dar de baja');
select throws_ok(
  $$select privado.crear_producto(null, 'X', 'lacteos', 'unidad', 1, 0)$$,
  'PT403', 'producto_no_autorizado',
  'la implementación privada llamada por SQL también rechaza al vendedor');

select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok(
  $$select public.crear_producto(null, 'X', 'lacteos', 'unidad', 1, 0)$$,
  'PT401', 'producto_no_autenticado', 'sin sub en el JWT: no autenticado');

-- Otra empresa: igual que inexistente (ADR-001 §8.5).
select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.actualizar_producto('aaaaaaaa-0000-4000-8000-00000000a001',
                                      'C-1', 'Robado', 1, 5)$$,
  'PT404', 'producto_no_encontrado', 'el dueño de B no puede editar un producto de A');
select throws_ok(
  $$select public.cambiar_estado_producto('aaaaaaaa-0000-4000-8000-00000000a001', false)$$,
  'PT404', 'producto_no_encontrado', 'el dueño de B no puede dar de baja un producto de A');
select throws_ok(
  $$select public.actualizar_producto('eeeeeeee-0000-4000-8000-000000000000',
                                      null, 'X', 1, 0)$$,
  'PT404', 'producto_no_encontrado', 'un producto inexistente responde igual');
select throws_ok(
  $$select public.actualizar_producto(null, null, 'X', 1, 0)$$,
  'PT404', 'producto_no_encontrado', 'un id nulo responde no encontrado');

-- Empresa y autor derivados del perfil (DE-11, DE-7).
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
create temp table creados (clave text, id uuid);
grant select, insert on creados to public;

select lives_ok(
  $$insert into creados
    select 'encargado', public.crear_producto(' E-1 ', '  Queso en bote  ',
                                              'lacteos', 'unidad', 8500.50, 3)$$,
  'el encargado crea un producto');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into creados
    select 'dueno', public.crear_producto(null, 'Salame', 'fiambres', 'pieza',
                                          9800, 16)$$,
  'el dueño crea un producto');

reset role;

select results_eq(
  $$select p.empresa_id, p.creado_por, p.codigo, p.nombre, p.categoria,
           p.forma_venta, p.precio, p.stock_minimo, p.activo
      from public.productos p join creados c on c.id = p.id
     where c.clave = 'encargado'$$,
  $$values ('aaaaaaaa-0000-4000-8000-000000000000'::uuid,
            'aaaaaaaa-0000-4000-8000-000000000002'::uuid,
            'E-1', 'Queso en bote', 'lacteos', 'unidad', 8500.50::numeric,
            3, true)$$,
  'empresa_id y creado_por salen del perfil; codigo y nombre se guardan sin espacios');

select ok(
  (select p.empresa_id = 'aaaaaaaa-0000-4000-8000-000000000000'
          and p.creado_por = 'aaaaaaaa-0000-4000-8000-000000000001'
          and p.codigo is null
     from public.productos p join creados c on c.id = p.id
    where c.clave = 'dueno'),
  'el producto del dueño queda en su empresa, a su nombre y sin código');

-- ---------------------------------------------------------------------------
-- Precio exacto (DE-2, DE-15): se rechaza sin redondear
-- ---------------------------------------------------------------------------
create temp table conteo_antes as
  select count(*)::int as n from public.productos;
grant select on conteo_antes to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');

select throws_ok(
  $$select public.crear_producto(null, 'P', 'lacteos', 'unidad', 20.999, 0)$$,
  'PT400', 'producto_precio_invalido', '20.999 se rechaza (no se redondea a 21.00)');
select throws_ok(
  $$select public.crear_producto(null, 'P', 'lacteos', 'unidad', 0.001, 0)$$,
  'PT400', 'producto_precio_invalido', '0.001 se rechaza (no se redondea a 0.00)');
select throws_ok(
  $$select public.crear_producto(null, 'P', 'lacteos', 'unidad', 1e-3, 0)$$,
  'PT400', 'producto_precio_invalido', '1e-3 se rechaza');
select throws_ok(
  $$select public.crear_producto(null, 'P', 'lacteos', 'unidad', -0.01, 0)$$,
  'PT400', 'producto_precio_invalido', 'un precio negativo se rechaza');
select throws_ok(
  $$select public.crear_producto(null, 'P', 'lacteos', 'unidad', 1000000000000, 0)$$,
  'PT400', 'producto_precio_invalido', '10^12 está fuera del rango de numeric(14,2)');
select throws_ok(
  $$select public.crear_producto(null, 'P', 'lacteos', 'unidad', 'NaN'::numeric, 0)$$,
  'PT400', 'producto_precio_invalido', 'NaN se rechaza');
select throws_ok(
  $$select public.crear_producto(null, 'P', 'lacteos', 'unidad', 'Infinity'::numeric, 0)$$,
  'PT400', 'producto_precio_invalido', 'Infinity se rechaza');
select throws_ok(
  $$select public.crear_producto(null, 'P', 'lacteos', 'unidad', '-Infinity'::numeric, 0)$$,
  'PT400', 'producto_precio_invalido', '-Infinity se rechaza');
select throws_ok(
  $$select public.crear_producto(null, 'P', 'lacteos', 'unidad', null, 0)$$,
  'PT400', 'producto_precio_invalido', 'un precio nulo se rechaza');
select throws_ok(
  $$select public.actualizar_producto('aaaaaaaa-0000-4000-8000-00000000a001',
                                      'C-1', 'Yogur A', 20.999, 5)$$,
  'PT400', 'producto_precio_invalido', 'actualizar con 20.999 se rechaza');
select throws_ok(
  $$select public.actualizar_producto('aaaaaaaa-0000-4000-8000-00000000a001',
                                      'C-1', 'Yogur A', 'NaN'::numeric, 5)$$,
  'PT400', 'producto_precio_invalido', 'actualizar con NaN se rechaza');
select throws_ok(
  $$select public.actualizar_producto('aaaaaaaa-0000-4000-8000-00000000a001',
                                      'C-1', 'Yogur A', null, 5)$$,
  'PT400', 'producto_precio_invalido', 'actualizar con precio nulo se rechaza');
select throws_ok(
  $$select privado.crear_producto(null, 'P', 'lacteos', 'unidad', 20.999, 0)$$,
  'PT400', 'producto_precio_invalido',
  'la implementación privada llamada por SQL también rechaza 20.999');

reset role;
select is((select count(*)::int from public.productos), (select n from conteo_antes),
  'ningún precio inválido creó un producto');
select is(
  (select precio from public.productos
    where id = 'aaaaaaaa-0000-4000-8000-00000000a001'),
  100.00::numeric,
  'ningún precio inválido modificó el producto existente');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into creados
    select 'p0', public.crear_producto(null, 'P0', 'lacteos', 'unidad', 0, 0)$$,
  'precio 0 se acepta (>= 0, ADR-003)');
select lives_ok(
  $$insert into creados
    select 'p2099', public.crear_producto(null, 'P1', 'lacteos', 'unidad', 20.99, 0)$$,
  '20.99 se acepta');
select lives_ok(
  $$insert into creados
    select 'p20990', public.crear_producto(null, 'P2', 'lacteos', 'unidad', 20.990, 0)$$,
  '20.990 se acepta: tiene 2 decimales por valor (DE-15)');
select lives_ok(
  $$insert into creados
    select 'pmax', public.crear_producto(null, 'P3', 'lacteos', 'unidad',
                                         999999999999.99, 0)$$,
  '999999999999.99 (máximo de numeric(14,2)) se acepta');

reset role;
select results_eq(
  $$select c.clave, p.precio from creados c join public.productos p on p.id = c.id
     where c.clave in ('p0', 'p2099', 'p20990', 'pmax') order by c.clave$$,
  $$values ('p0', 0.00::numeric), ('p2099', 20.99::numeric),
           ('p20990', 20.99::numeric), ('pmax', 999999999999.99::numeric)$$,
  'los precios aceptados se guardan exactamente');

select is(
  (select format_type(atttypid, atttypmod) from pg_attribute
    where attrelid = 'public.productos'::regclass and attname = 'precio'),
  'numeric(14,2)',
  'productos.precio se persiste como numeric(14,2)');

-- ---------------------------------------------------------------------------
-- Validación de campos e integridad (DE-3, DE-5, DE-6, DE-8, DE-10)
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');

select throws_ok(
  $$select public.crear_producto(null, 'X', 'lacteos', 'pieza', 1, 0)$$,
  'PT400', 'producto_combinacion_invalida', 'Lácteos + pieza se rechaza');
select throws_ok(
  $$select public.crear_producto(null, 'X', 'fiambres', 'unidad', 1, 0)$$,
  'PT400', 'producto_combinacion_invalida', 'Fiambres + unidad se rechaza');
select throws_ok(
  $$select public.crear_producto(null, 'X', 'Lácteos', 'unidad', 1, 0)$$,
  'PT400', 'producto_categoria_invalida', 'una categoría desconocida se rechaza');
select throws_ok(
  $$select public.crear_producto(null, 'X', 'lacteos', 'kg', 1, 0)$$,
  'PT400', 'producto_forma_venta_invalida', 'kg no existe en Fase 1');
select throws_ok(
  $$select public.crear_producto(null, 'X', null, 'unidad', 1, 0)$$,
  'PT400', 'producto_categoria_invalida', 'una categoría nula se rechaza');
select throws_ok(
  $$select public.crear_producto(null, '   ', 'lacteos', 'unidad', 1, 0)$$,
  'PT400', 'producto_nombre_invalido', 'un nombre vacío se rechaza');
select throws_ok(
  $$select public.crear_producto(null, null, 'lacteos', 'unidad', 1, 0)$$,
  'PT400', 'producto_nombre_invalido', 'un nombre nulo se rechaza');
select throws_ok(
  $$select public.crear_producto(null, 'X', 'lacteos', 'unidad', 1, -1)$$,
  'PT400', 'producto_stock_minimo_invalido', 'un stock mínimo negativo se rechaza');
select throws_ok(
  $$select public.crear_producto(null, 'X', 'lacteos', 'unidad', 1, null)$$,
  'PT400', 'producto_stock_minimo_invalido', 'un stock mínimo nulo se rechaza');
select throws_ok(
  $$select public.cambiar_estado_producto('aaaaaaaa-0000-4000-8000-00000000a001', null)$$,
  'PT400', 'producto_estado_invalido', 'un estado nulo se rechaza');

-- Código: opcional, sin espacios, único por empresa, mayúsculas intactas (DE-3).
select throws_ok(
  $$select public.crear_producto('C-1', 'X', 'lacteos', 'unidad', 1, 0)$$,
  'PT409', 'producto_codigo_duplicado', 'un código repetido en la empresa se rechaza');
select throws_ok(
  $$select public.crear_producto('  C-1  ', 'X', 'lacteos', 'unidad', 1, 0)$$,
  'PT409', 'producto_codigo_duplicado', 'el código se compara sin espacios en los extremos');
select lives_ok(
  $$insert into creados
    select 'c2', public.crear_producto('C-2', 'X', 'lacteos', 'unidad', 1, 0)$$,
  'el mismo código que usa otra empresa se acepta');
select lives_ok(
  $$insert into creados
    select 'c1min', public.crear_producto('c-1', 'X', 'lacteos', 'unidad', 1, 0)$$,
  'el código distingue mayúsculas');
select lives_ok(
  $$insert into creados
    select 'vacio1', public.crear_producto('', 'X', 'lacteos', 'unidad', 1, 0)$$,
  'un código vacío se acepta como sin código');
select lives_ok(
  $$insert into creados
    select 'vacio2', public.crear_producto('   ', 'X', 'lacteos', 'unidad', 1, 0)$$,
  'dos productos sin código pueden convivir');
select throws_ok(
  $$select public.actualizar_producto('aaaaaaaa-0000-4000-8000-00000000a002',
                                      'C-1', 'Jamón A', 21, 2)$$,
  'PT409', 'producto_codigo_duplicado', 'actualizar con un código repetido se rechaza');

-- Edición, baja lógica e inmutabilidad (DE-6, DE-14).
select lives_ok(
  $$select public.actualizar_producto('aaaaaaaa-0000-4000-8000-00000000a002',
                                      'J-9', 'Jamón cocido', 25.50, 4)$$,
  'el dueño edita un producto');
select lives_ok(
  $$select public.cambiar_estado_producto('aaaaaaaa-0000-4000-8000-00000000a002', false)$$,
  'el dueño da de baja un producto');
select lives_ok(
  $$select public.cambiar_estado_producto('aaaaaaaa-0000-4000-8000-00000000a002', false)$$,
  'repetir la baja no falla');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.cambiar_estado_producto('aaaaaaaa-0000-4000-8000-00000000a001', false)$$,
  'el encargado da de baja un producto');
select lives_ok(
  $$select public.cambiar_estado_producto('aaaaaaaa-0000-4000-8000-00000000a001', true)$$,
  'el encargado reactiva un producto');

reset role;
select results_eq(
  $$select codigo, nombre, categoria, forma_venta, precio, stock_minimo, activo
      from public.productos where id = 'aaaaaaaa-0000-4000-8000-00000000a002'$$,
  $$values ('J-9', 'Jamón cocido', 'fiambres', 'pieza', 25.50::numeric, 4, false)$$,
  'la edición cambia sólo los campos editables; categoría y forma de venta quedan igual');
select ok(
  (select activo from public.productos
    where id = 'aaaaaaaa-0000-4000-8000-00000000a001'),
  'la reactivación queda guardada');

-- Ni el rol técnico puede cambiar categoría, forma de venta, empresa ni autor.
-- USAGE sobre `extensions` sólo para poder invocar pgTAP con ese rol; se
-- revierte con la transacción del test y no toca productos.
grant usage on schema extensions to propietario_rpc;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;
select throws_ok(
  $$update public.productos set categoria = 'fiambres', forma_venta = 'pieza'
     where id = 'aaaaaaaa-0000-4000-8000-00000000a001'$$,
  '42501', null, 'propietario_rpc no puede cambiar categoría ni forma de venta (DE-6)');
select throws_ok(
  $$update public.productos set empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000'
     where id = 'aaaaaaaa-0000-4000-8000-00000000a001'$$,
  '42501', null, 'propietario_rpc no puede mover un producto de empresa');
select throws_ok(
  $$update public.productos set creado_por = 'aaaaaaaa-0000-4000-8000-000000000002'
     where id = 'aaaaaaaa-0000-4000-8000-00000000a001'$$,
  '42501', null, 'propietario_rpc no puede cambiar el autor');
select throws_ok(
  $$delete from public.productos where id = 'aaaaaaaa-0000-4000-8000-00000000a001'$$,
  '42501', null, 'propietario_rpc no puede borrar');

-- RLS del rol técnico: aun con grant, no escribe en otra empresa ni con otro autor.
select throws_ok(
  $$insert into public.productos (empresa_id, nombre, categoria, forma_venta,
                                  precio, creado_por)
    values ('bbbbbbbb-0000-4000-8000-000000000000', 'Cruzado', 'lacteos',
            'unidad', 1, 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'RLS impide a propietario_rpc insertar en otra empresa');
select throws_ok(
  $$insert into public.productos (empresa_id, nombre, categoria, forma_venta,
                                  precio, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'Ajeno', 'lacteos',
            'unidad', 1, 'aaaaaaaa-0000-4000-8000-000000000002')$$,
  '42501', null, 'RLS impide a propietario_rpc atribuir el alta a otro usuario');
select is(
  (select count(*)::int from public.productos
    where empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000'),
  0,
  'propietario_rpc no ve productos de otra empresa');

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000003","role":"authenticated"}', true);
select results_eq(
  $$with u as (update public.productos set nombre = 'Hackeado'
                where id = 'aaaaaaaa-0000-4000-8000-00000000a001' returning 1)
    select count(*)::int from u$$,
  $$values (0)$$,
  'RLS impide a propietario_rpc editar en nombre de un vendedor');

reset role;

-- Integridad de aislamiento por empresa_id del autor (DE-8): FK compuesta, también para el owner.
select throws_ok(
  $$insert into public.productos (empresa_id, nombre, categoria, forma_venta,
                                  precio, creado_por)
    values ('bbbbbbbb-0000-4000-8000-000000000000', 'Mezcla', 'lacteos',
            'unidad', 1, 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23503', null, 'un producto de B no puede tener como autor a un usuario de A');

-- Restricciones de la tabla (defensa si alguien escribiera como owner).
select throws_ok(
  $$insert into public.productos (empresa_id, nombre, categoria, forma_venta,
                                  precio, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'X', 'lacteos', 'pieza', 1,
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza la combinación Lácteos + pieza');
select throws_ok(
  $$insert into public.productos (empresa_id, nombre, categoria, forma_venta,
                                  precio, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'X', 'lacteos', 'unidad', -1,
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza precios negativos');
select throws_ok(
  $$insert into public.productos (empresa_id, nombre, categoria, forma_venta,
                                  precio, stock_minimo, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'X', 'lacteos', 'unidad', 1, -1,
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza stock mínimo negativo');
select throws_ok(
  $$insert into public.productos (empresa_id, codigo, nombre, categoria,
                                  forma_venta, precio, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', ' Z ', 'X', 'lacteos',
            'unidad', 1, 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza códigos sin normalizar');
select throws_ok(
  $$insert into public.productos (empresa_id, nombre, categoria, forma_venta,
                                  precio, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', ' X', 'lacteos', 'unidad', 1,
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza nombres sin normalizar');

-- service_role (BYPASSRLS) tampoco escribe: los intentos fallan por privilegio
-- y no modifican la tabla. TRUNCATE falla antes de tocar nada y todo el test
-- corre dentro de una transacción que se revierte.
create temp table huella_service_role as
  select count(*)::int as filas,
         md5(string_agg(p::text, '|' order by p.id)) as productos
    from public.productos p;
grant select on huella_service_role to public;

grant usage on schema extensions to service_role;
set local role service_role;

select ok(
  (select count(*) from public.productos) > 0,
  'service_role lee productos de todas las empresas');
select throws_ok(
  $$insert into public.productos (empresa_id, nombre, categoria, forma_venta,
                                  precio, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'Directo SR', 'lacteos',
            'unidad', 20.999, 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'service_role no puede insertar directo (20.999 no se redondea)');
select throws_ok(
  $$update public.productos set precio = 20.999
     where id = 'aaaaaaaa-0000-4000-8000-00000000a001'$$,
  '42501', null, 'service_role no puede actualizar el precio');
select throws_ok(
  $$update public.productos set categoria = 'fiambres', forma_venta = 'pieza'
     where id = 'aaaaaaaa-0000-4000-8000-00000000a001'$$,
  '42501', null, 'service_role no puede cambiar categoría ni forma de venta');
select throws_ok(
  $$delete from public.productos where id = 'aaaaaaaa-0000-4000-8000-00000000a001'$$,
  '42501', null, 'service_role no puede borrar');
select throws_ok(
  $$truncate table public.productos$$,
  '42501', null, 'service_role no puede truncar');

reset role;

select results_eq(
  $$select count(*)::int, md5(string_agg(p::text, '|' order by p.id))
      from public.productos p$$,
  $$select filas, productos from huella_service_role$$,
  'los intentos de service_role no modificaron la tabla');

-- Caracterización (por qué existe la RPC): una escritura directa en la
-- columna numeric(14,2) redondea en silencio. Sólo el owner puede hacerla.
select results_eq(
  $$with i as (
      insert into public.productos (empresa_id, nombre, categoria, forma_venta,
                                    precio, creado_por)
      values ('aaaaaaaa-0000-4000-8000-000000000000', 'Caracterización',
              'lacteos', 'unidad', 20.999, 'aaaaaaaa-0000-4000-8000-000000000001')
      returning precio)
    select precio from i$$,
  $$values (21.00::numeric)$$,
  'caracterización: asignar 20.999 directo a numeric(14,2) redondea a 21.00');

select * from finish();

rollback;
