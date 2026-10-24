-- pgTAP: catálogo de camiones (Blueprint §8, §9, §10, §12 Seguridad;
-- ADR-001 Topología D; decisión humana del 24/10/2026: dueño escribe,
-- encargado y vendedor/piloto sólo leen).
-- Ejecutar sólo en local: `supabase test db`.
--
-- Se usan dos empresas EXCLUSIVAMENTE para demostrar aislamiento: la empresa B
-- es un fixture adversarial, no un producto multiempresa.

begin;

create extension if not exists pgtap with schema extensions;

select plan(112);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-0000-4000-8000-000000000000', 'Empresa A (test)'),
  ('bbbbbbbb-0000-4000-8000-000000000000', 'Empresa B (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  -- A1: dueño activo de A
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'cam.a1@usuarios.distribuidora.invalid', '{}'),
  -- A2: encargado activo de A
  ('aaaaaaaa-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'cam.a2@usuarios.distribuidora.invalid', '{}'),
  -- A3: vendedor activo de A, con metadata que pretende ser dueño
  ('aaaaaaaa-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'cam.a3@usuarios.distribuidora.invalid', '{"rol":"dueno"}'),
  -- A4: dueño INACTIVO de A
  ('aaaaaaaa-0000-4000-8000-000000000004', 'authenticated', 'authenticated',
   'cam.a4@usuarios.distribuidora.invalid', '{}'),
  -- B1: dueño activo de B
  ('bbbbbbbb-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'cam.b1@usuarios.distribuidora.invalid', '{}'),
  -- N1: cuenta Auth sin perfil, con metadata falsa
  ('cccccccc-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'cam.n1@usuarios.distribuidora.invalid',
   '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000000',
   'cam.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000000',
   'cam.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000000',
   'cam.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000000',
   'cam.a4', 'A4', 'dueno', false),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000000',
   'cam.b1', 'B1', 'dueno', true);

insert into public.camiones (id, empresa_id, patente, nombre, creado_por) values
  ('aaaaaaaa-0000-4000-8000-00000000c001', 'aaaaaaaa-0000-4000-8000-000000000000',
   'AA111AA', 'Camión 1', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-00000000c002', 'aaaaaaaa-0000-4000-8000-000000000000',
   'AB222BB', 'Camión 2', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('bbbbbbbb-0000-4000-8000-00000000c001', 'bbbbbbbb-0000-4000-8000-000000000000',
   'BB333CC', 'Camión B', 'bbbbbbbb-0000-4000-8000-000000000001');

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

-- Los privilegios por defecto de postgres no dan EXECUTE a PUBLIC en
-- funciones nuevas: los helpers se invocan desde los roles simulados.
grant execute on function pg_temp.como_usuario(uuid, jsonb) to public;
grant execute on function pg_temp.como_anon() to public;

-- Firmas exactas (sin sobrecargas).
create temp table firmas (firma text, expuesta boolean);
insert into firmas values
  ('public.crear_camion(text,text)', true),
  ('public.actualizar_camion(uuid,text,text)', true),
  ('public.cambiar_estado_camion(uuid,boolean)', true),
  ('privado.crear_camion(text,text)', false),
  ('privado.actualizar_camion(uuid,text,text)', false),
  ('privado.cambiar_estado_camion(uuid,boolean)', false);
grant select on firmas to public;

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_table('public', 'camiones', 'la tabla public.camiones existe');

select is(
  array(select a.attname::text || ':' || format_type(a.atttypid, a.atttypmod)
               || ':' || a.attnotnull::text
               || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-')
          from pg_attribute a
          left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
         where a.attrelid = 'public.camiones'::regclass
           and a.attnum > 0 and not a.attisdropped
         order by a.attnum),
  array['id:uuid:true:gen_random_uuid()',
        'empresa_id:uuid:true:-',
        'patente:text:true:-',
        'nombre:text:true:-',
        'activo:boolean:true:true',
        'creado_en:timestamp with time zone:true:now()',
        'creado_por:uuid:true:-'],
  'columnas, tipos, NOT NULL y defaults del modelo mínimo (sin marca, modelo, estado ni observaciones)');

select ok(
  (select relrowsecurity and not relforcerowsecurity
     from pg_class where oid = 'public.camiones'::regclass),
  'camiones tiene RLS habilitada y sin FORCE (P4)');

select is(
  (select count(*)::int from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity),
  0,
  'todas las tablas de public tienen RLS habilitada');

select is(
  array(select conname::text from pg_constraint
         where conrelid = 'public.camiones'::regclass order by conname::text),
  array['camiones_creado_por_fk', 'camiones_empresa_id_fkey',
        'camiones_empresa_id_unico', 'camiones_nombre_normalizado',
        'camiones_patente_normalizada', 'camiones_patente_unica',
        'camiones_pkey'],
  'constraints: PK, unique (empresa_id,id), unique (empresa_id,patente), FKs y CHECK de normalización');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint
    where conname = 'camiones_creado_por_fk'),
  'FOREIGN KEY (empresa_id, creado_por) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT',
  'el autor se valida con FK compuesta contra perfiles de la misma empresa');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint
    where conname = 'camiones_patente_unica'),
  'UNIQUE (empresa_id, patente)',
  'la patente es única por empresa (sensible a mayúsculas, sin citext)');

select is(
  (select count(*)::int from firmas f where to_regprocedure(f.firma) is not null),
  6,
  'existen las seis firmas aprobadas');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and p.proname in ('crear_camion', 'actualizar_camion',
                        'cambiar_estado_camion')),
  6,
  'una única firma por nombre y esquema (sin sobrecargas)');

select is(
  array(select p.oid::regprocedure::text from pg_proc p
         where p.prosecdef
           and p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
         order by 1),
  array['privado.actualizar_camion(uuid,text,text)',
        'privado.actualizar_producto(uuid,text,text,numeric,integer)',
        'privado.cambiar_estado_camion(uuid,boolean)',
        'privado.cambiar_estado_producto(uuid,boolean)',
        'privado.crear_camion(text,text)',
        'privado.crear_producto(text,text,text,text,numeric,integer)'],
  'ninguna función de public es SECURITY DEFINER; sólo las implementaciones privadas lo son');

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
    where not f.expuesta
      and (not p.prosecdef
           or p.proowner <> 'propietario_rpc'::regrole
           or p.provolatile <> 'v'
           or not p.proconfig @> array['search_path=""'])),
  0,
  'las implementaciones privadas son SECURITY DEFINER, VOLATILE, de propietario_rpc y con search_path vacío');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and (p.proowner <> 'propietario_rpc'::regrole
           or p.proconfig is null
           or not p.proconfig @> array['search_path=""'])),
  0,
  'toda función de privado es de propietario_rpc y fija search_path vacío');

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
select ok(
  not has_table_privilege('anon', 'public.camiones',
        'select, insert, update, delete, truncate, references, trigger')
  and not has_any_column_privilege('anon', 'public.camiones',
        'select, insert, update, references'),
  'anon no tiene ningún privilegio sobre camiones (ni por columna)');

select ok(
  has_table_privilege('authenticated', 'public.camiones', 'select'),
  'authenticated puede leer camiones');

select ok(
  not has_table_privilege('authenticated', 'public.camiones',
        'insert, update, delete, truncate, references, trigger')
  and not has_any_column_privilege('authenticated', 'public.camiones', 'insert')
  and not has_any_column_privilege('authenticated', 'public.camiones', 'update')
  and not has_any_column_privilege('authenticated', 'public.camiones', 'references'),
  'authenticated sólo tiene SELECT sobre camiones (ni INSERT/UPDATE por columna)');

select ok(
  not exists (
    select 1 from pg_class c, aclexplode(c.relacl) a
     where c.oid = 'public.camiones'::regclass and a.grantee = 0),
  'PUBLIC no tiene privilegios sobre camiones');

-- Política deliberada del slice: sin decisión aprobada para camiones y con
-- P11 global pendiente, service_role no recibe nada.
select ok(
  not has_table_privilege('service_role', 'public.camiones',
        'select, insert, update, delete, truncate, references, trigger')
  and not has_any_column_privilege('service_role', 'public.camiones',
        'select, insert, update, references'),
  'service_role no tiene ningún privilegio sobre camiones (sin decisión aprobada; P11 global pendiente)');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.camiones'::regclass and a.attnum > 0
           and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.camiones', a.attname, 'insert')
         order by a.attname::text),
  array['creado_por', 'empresa_id', 'nombre', 'patente'],
  'propietario_rpc inserta sólo empresa_id, patente, nombre y creado_por (sin id, activo, creado_en)');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.camiones'::regclass and a.attnum > 0
           and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.camiones', a.attname, 'update')
         order by a.attname::text),
  array['activo', 'nombre', 'patente'],
  'propietario_rpc actualiza sólo patente, nombre y activo');

select ok(
  has_table_privilege('propietario_rpc', 'public.camiones', 'select')
  and not has_table_privilege('propietario_rpc', 'public.camiones',
        'delete, truncate, references, trigger'),
  'propietario_rpc lee camiones y no puede borrar ni truncar');

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
  'anon y service_role no pueden ejecutar ninguna RPC de camiones');

select is(
  (select count(*)::int from firmas f
     join pg_proc p on p.oid = f.firma::regprocedure
    where p.proacl is null
       or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)),
  0,
  'ninguna RPC de camiones conserva EXECUTE para PUBLIC');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('exigir_dueno_camiones', 'validar_campos_camion',
                        'error_restriccion_camion',
                        'estado_http_restriccion_camion')
      and (has_function_privilege('authenticated', p.oid, 'execute')
           or has_function_privilege('anon', p.oid, 'execute')
           or has_function_privilege('service_role', p.oid, 'execute')
           or p.proacl is null
           or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0))),
  0,
  'los auxiliares de camiones en privado sólo los ejecuta propietario_rpc');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('exigir_dueno_camiones', 'validar_campos_camion',
                        'error_restriccion_camion',
                        'estado_http_restriccion_camion')),
  4,
  'existen los cuatro auxiliares privados de camiones');

-- ---------------------------------------------------------------------------
-- Bypass directo: authenticated y anon no escriben la tabla
-- ---------------------------------------------------------------------------
create temp table huella_antes as
  select md5(string_agg(c::text, '|' order by c.id)) as camiones
    from public.camiones c;
grant select on huella_antes to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');

select throws_ok(
  $$insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'DIR000', 'Directo',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'el dueño no puede insertar directamente');

select throws_ok(
  $$update public.camiones set nombre = 'Directo'$$,
  '42501', null, 'el dueño no puede actualizar directamente');

select throws_ok(
  $$delete from public.camiones$$,
  '42501', null, 'el dueño no puede borrar camiones');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');

select throws_ok(
  $$update public.camiones set activo = false$$,
  '42501', null, 'el encargado no puede actualizar directamente');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003',
  '{"rol":"dueno"}');

select throws_ok(
  $$insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'DIR001', 'Directo',
            'aaaaaaaa-0000-4000-8000-000000000003')$$,
  '42501', null, 'el vendedor con metadata de dueño no puede insertar directamente');

select pg_temp.como_anon();

select throws_ok('select * from public.camiones', '42501', null,
  'anon no puede leer camiones');

select throws_ok(
  $$select public.crear_camion('X1', 'X')$$,
  '42501', null, 'anon no puede ejecutar crear_camion');
select throws_ok(
  $$select public.actualizar_camion('aaaaaaaa-0000-4000-8000-00000000c001', 'X1', 'X')$$,
  '42501', null, 'anon no puede ejecutar actualizar_camion');
select throws_ok(
  $$select public.cambiar_estado_camion('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  '42501', null, 'anon no puede ejecutar cambiar_estado_camion');
select throws_ok(
  $$select privado.crear_camion('X1', 'X')$$,
  '42501', null, 'anon no puede ejecutar la implementación privada');

reset role;

select is(
  (select md5(string_agg(c::text, '|' order by c.id)) from public.camiones c),
  (select camiones from huella_antes),
  'los intentos directos no cambiaron ningún camión');

-- ---------------------------------------------------------------------------
-- Lectura por empresa y estado del perfil
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select results_eq(
  $$select id from public.camiones order by id$$,
  $$values ('aaaaaaaa-0000-4000-8000-00000000c001'::uuid),
           ('aaaaaaaa-0000-4000-8000-00000000c002'::uuid)$$,
  'el dueño lee los camiones de su empresa y no los de otra');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select results_eq(
  $$select id from public.camiones order by id$$,
  $$values ('aaaaaaaa-0000-4000-8000-00000000c001'::uuid),
           ('aaaaaaaa-0000-4000-8000-00000000c002'::uuid)$$,
  'el encargado lee los camiones de su empresa');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select results_eq(
  $$select id from public.camiones order by id$$,
  $$values ('aaaaaaaa-0000-4000-8000-00000000c001'::uuid),
           ('aaaaaaaa-0000-4000-8000-00000000c002'::uuid)$$,
  'el vendedor/piloto lee los camiones de su empresa');

select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select results_eq(
  $$select id from public.camiones order by id$$,
  $$values ('bbbbbbbb-0000-4000-8000-00000000c001'::uuid)$$,
  'el dueño de B sólo ve camiones de B (otra empresa no ve)');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000004');
select is((select count(*)::int from public.camiones), 0,
  'un perfil inactivo no ve camiones');

select pg_temp.como_usuario('cccccccc-0000-4000-8000-000000000001',
  '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');
select is((select count(*)::int from public.camiones), 0,
  'una cuenta sin perfil no ve camiones, aunque su metadata diga dueño');

-- ---------------------------------------------------------------------------
-- Autorización de las RPC: sólo el dueño escribe
-- ---------------------------------------------------------------------------
-- Cuenta sin perfil (N1, sigue como authenticated).
select throws_ok(
  $$select public.crear_camion('NP001', 'Sin perfil')$$,
  'PT403', 'camion_no_autorizado', 'una cuenta sin perfil no puede crear');
select throws_ok(
  $$select public.actualizar_camion('aaaaaaaa-0000-4000-8000-00000000c001', 'NP001', 'X')$$,
  'PT403', 'camion_no_autorizado', 'una cuenta sin perfil no puede actualizar');
select throws_ok(
  $$select public.cambiar_estado_camion('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  'PT403', 'camion_no_autorizado', 'una cuenta sin perfil no puede cambiar el estado');

-- Dueño inactivo (A4).
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000004');
select throws_ok(
  $$select public.crear_camion('IN001', 'Inactivo')$$,
  'PT403', 'camion_no_autorizado', 'un dueño inactivo no puede crear');
select throws_ok(
  $$select public.actualizar_camion('aaaaaaaa-0000-4000-8000-00000000c001', 'IN001', 'X')$$,
  'PT403', 'camion_no_autorizado', 'un dueño inactivo no puede actualizar');
select throws_ok(
  $$select public.cambiar_estado_camion('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  'PT403', 'camion_no_autorizado', 'un dueño inactivo no puede cambiar el estado');

-- Encargado (A2): sólo lectura.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select throws_ok(
  $$select public.crear_camion('EN001', 'Encargado')$$,
  'PT403', 'camion_no_autorizado', 'el encargado no puede crear');
select throws_ok(
  $$select public.actualizar_camion('aaaaaaaa-0000-4000-8000-00000000c001', 'EN001', 'X')$$,
  'PT403', 'camion_no_autorizado', 'el encargado no puede actualizar');
select throws_ok(
  $$select public.cambiar_estado_camion('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  'PT403', 'camion_no_autorizado', 'el encargado no puede cambiar el estado');
select throws_ok(
  $$select privado.crear_camion('EN001', 'Encargado')$$,
  'PT403', 'camion_no_autorizado',
  'la implementación privada llamada por SQL también rechaza al encargado');

-- Vendedor (A3) con user_metadata.rol = 'dueno': la metadata no autoriza.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003', '{"rol":"dueno"}');
select throws_ok(
  $$select public.crear_camion('VE001', 'Vendedor')$$,
  'PT403', 'camion_no_autorizado', 'el vendedor no puede crear (metadata ignorada)');
select throws_ok(
  $$select public.actualizar_camion('aaaaaaaa-0000-4000-8000-00000000c001', 'VE001', 'X')$$,
  'PT403', 'camion_no_autorizado', 'el vendedor no puede actualizar (metadata ignorada)');
select throws_ok(
  $$select public.cambiar_estado_camion('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  'PT403', 'camion_no_autorizado', 'el vendedor no puede cambiar el estado (metadata ignorada)');

-- Sin sub en el JWT: no autenticado.
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok(
  $$select public.crear_camion('NA001', 'Sin sub')$$,
  'PT401', 'camion_no_autenticado', 'sin sub en el JWT: no autenticado');

-- ---------------------------------------------------------------------------
-- Aislamiento por empresa_id
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.actualizar_camion('aaaaaaaa-0000-4000-8000-00000000c001', 'ROB001', 'Robado')$$,
  'PT404', 'camion_no_encontrado', 'el dueño de B no puede actualizar un camión de A');
select throws_ok(
  $$select public.cambiar_estado_camion('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  'PT404', 'camion_no_encontrado', 'el dueño de B no puede desactivar un camión de A');
select throws_ok(
  $$select public.actualizar_camion('eeeeeeee-0000-4000-8000-000000000000', 'ROB002', 'X')$$,
  'PT404', 'camion_no_encontrado', 'un camión inexistente responde igual que uno de otra empresa');
select throws_ok(
  $$select public.cambiar_estado_camion(null, false)$$,
  'PT404', 'camion_no_encontrado', 'un id nulo responde no encontrado');

-- Simétrico: el dueño de A tampoco toca el camión de B.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.actualizar_camion('bbbbbbbb-0000-4000-8000-00000000c001', 'ROB003', 'Robado')$$,
  'PT404', 'camion_no_encontrado', 'el dueño de A no puede actualizar un camión de B');
select throws_ok(
  $$select public.cambiar_estado_camion('bbbbbbbb-0000-4000-8000-00000000c001', false)$$,
  'PT404', 'camion_no_encontrado', 'el dueño de A no puede desactivar un camión de B');

-- empresa_id no es parámetro: las firmas no lo aceptan.
select throws_ok(
  $$select public.crear_camion(p_patente => 'EMP001', p_nombre => 'X',
                               p_empresa_id => 'bbbbbbbb-0000-4000-8000-000000000000')$$,
  '42883', null, 'crear_camion no acepta p_empresa_id');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and p.proname in ('crear_camion', 'actualizar_camion', 'cambiar_estado_camion')
      and (p.proargnames @> array['p_empresa_id'] or p.proargnames @> array['empresa_id'])),
  0,
  'ninguna firma de camiones recibe empresa_id');

-- Headers inventados no cambian la empresa: el servidor la deriva del perfil.
select set_config('request.headers', '{"x-empresa-id":"bbbbbbbb-0000-4000-8000-000000000000"}', true);
create temp table creados (clave text, id uuid);
grant select, insert on creados to public;
select lives_ok(
  $$insert into creados select 'header', public.crear_camion('HDR001', 'Con header')$$,
  'el dueño crea un camión con un header de empresa inventado');

reset role;
select is(
  (select empresa_id from public.camiones c join creados x on x.id = c.id
    where x.clave = 'header'),
  'aaaaaaaa-0000-4000-8000-000000000000'::uuid,
  'el header inventado se ignora: el camión queda en la empresa del perfil');

select is(
  (select count(*)::int from public.camiones
    where empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000'),
  1,
  'los intentos cruzados no crearon camiones en B');

select results_eq(
  $$select patente, nombre, activo from public.camiones
     where id = 'bbbbbbbb-0000-4000-8000-00000000c001'$$,
  $$values ('BB333CC', 'Camión B', true)$$,
  'los intentos cruzados no cambiaron la fila de B');

-- ---------------------------------------------------------------------------
-- Escritura del dueño
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');

select lives_ok(
  $$insert into creados
    select 'dueno', public.crear_camion('  CD123EF  ', '  Camión Norte  ')$$,
  'el dueño crea un camión');

select lives_ok(
  $$select public.actualizar_camion('aaaaaaaa-0000-4000-8000-00000000c002',
                                    ' AB222BC ', ' Camión 2 bis ')$$,
  'el dueño actualiza un camión');

select lives_ok(
  $$select public.cambiar_estado_camion('aaaaaaaa-0000-4000-8000-00000000c002', false)$$,
  'el dueño desactiva un camión');

select lives_ok(
  $$select public.cambiar_estado_camion('aaaaaaaa-0000-4000-8000-00000000c002', false)$$,
  'repetir la desactivación no falla');

select lives_ok(
  $$select public.cambiar_estado_camion('aaaaaaaa-0000-4000-8000-00000000c002', true)$$,
  'el dueño reactiva un camión');

reset role;

select results_eq(
  $$select c.empresa_id, c.creado_por, c.patente, c.nombre, c.activo
      from public.camiones c join creados x on x.id = c.id
     where x.clave = 'dueno'$$,
  $$values ('aaaaaaaa-0000-4000-8000-000000000000'::uuid,
            'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
            'CD123EF', 'Camión Norte', true)$$,
  'empresa_id y creado_por salen del perfil; patente y nombre se guardan sin espacios en los extremos');

select results_eq(
  $$select patente, nombre, activo from public.camiones
     where id = 'aaaaaaaa-0000-4000-8000-00000000c002'$$,
  $$values ('AB222BC', 'Camión 2 bis', true)$$,
  'la edición y la reactivación quedan guardadas');

-- ---------------------------------------------------------------------------
-- Validaciones
-- ---------------------------------------------------------------------------
create temp table conteo_antes as select count(*)::int as n from public.camiones;
grant select on conteo_antes to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');

select throws_ok($$select public.crear_camion(null, 'X')$$,
  'PT400', 'camion_patente_invalida', 'una patente nula se rechaza');
select throws_ok($$select public.crear_camion('', 'X')$$,
  'PT400', 'camion_patente_invalida', 'una patente vacía se rechaza');
select throws_ok($$select public.crear_camion('   ', 'X')$$,
  'PT400', 'camion_patente_invalida', 'una patente de espacios se rechaza');
select throws_ok($$select public.crear_camion('V001', null)$$,
  'PT400', 'camion_nombre_invalido', 'un nombre nulo se rechaza');
select throws_ok($$select public.crear_camion('V001', '')$$,
  'PT400', 'camion_nombre_invalido', 'un nombre vacío se rechaza');
select throws_ok($$select public.crear_camion('V001', '   ')$$,
  'PT400', 'camion_nombre_invalido', 'un nombre de espacios se rechaza');
select throws_ok(
  $$select public.actualizar_camion('aaaaaaaa-0000-4000-8000-00000000c001', ' ', 'X')$$,
  'PT400', 'camion_patente_invalida', 'actualizar con patente vacía se rechaza');
select throws_ok(
  $$select public.actualizar_camion('aaaaaaaa-0000-4000-8000-00000000c001', 'V001', null)$$,
  'PT400', 'camion_nombre_invalido', 'actualizar con nombre nulo se rechaza');
select throws_ok(
  $$select public.cambiar_estado_camion('aaaaaaaa-0000-4000-8000-00000000c001', null)$$,
  'PT400', 'camion_estado_invalido', 'un estado nulo se rechaza');
select throws_ok($$select privado.crear_camion(' ', 'X')$$,
  'PT400', 'camion_patente_invalida',
  'la implementación privada llamada por SQL también valida');

-- Patente única por empresa, sensible a mayúsculas, sin tocar espacios internos.
select throws_ok($$select public.crear_camion('AA111AA', 'Repetido')$$,
  'PT409', 'camion_patente_duplicada', 'una patente repetida en la empresa se rechaza');
select throws_ok($$select public.crear_camion('  AA111AA  ', 'Repetido')$$,
  'PT409', 'camion_patente_duplicada', 'la patente se compara sin espacios en los extremos');
select throws_ok(
  $$select public.actualizar_camion('aaaaaaaa-0000-4000-8000-00000000c002', 'AA111AA', 'Camión 2')$$,
  'PT409', 'camion_patente_duplicada', 'actualizar con una patente repetida se rechaza');
select lives_ok(
  $$insert into creados select 'minuscula', public.crear_camion('aa111aa', 'Minúsculas')$$,
  'la patente distingue mayúsculas (decisión conservadora, sin normalización)');
select lives_ok(
  $$insert into creados select 'interno', public.crear_camion('AA 111 AA', 'Con espacios')$$,
  'los espacios internos se conservan: no se inventa formato de patente');
select lives_ok(
  $$select public.actualizar_camion('aaaaaaaa-0000-4000-8000-00000000c001', 'AA111AA', 'Camión 1 renombrado')$$,
  'actualizar conservando la propia patente no es un duplicado');

-- Una patente de B no choca con la misma patente de A: unicidad por empresa.
select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into creados select 'mismaB', public.crear_camion('AA111AA', 'Misma patente en B')$$,
  'la misma patente en otra empresa se acepta (unicidad por empresa)');

reset role;

select is((select count(*)::int from public.camiones), (select n from conteo_antes) + 3,
  'sólo los tres casos válidos crearon camiones; ningún inválido dejó filas');

-- ---------------------------------------------------------------------------
-- Restricciones de la tabla (defensa si alguien escribiera como owner)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', ' T001', 'X',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza patentes sin normalizar');
select throws_ok(
  $$insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '', 'X',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza patentes vacías');
select throws_ok(
  $$insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'T002', ' X ',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza nombres sin normalizar');
select throws_ok(
  $$insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values ('bbbbbbbb-0000-4000-8000-000000000000', 'T003', 'Mezcla',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23503', null, 'un camión de B no puede tener como autor a un usuario de A');

-- ---------------------------------------------------------------------------
-- propietario_rpc: limitado por privilegios y RLS
-- ---------------------------------------------------------------------------
-- USAGE sobre `extensions` sólo para poder invocar pgTAP con ese rol; se
-- revierte con la transacción del test y no toca camiones.
grant usage on schema extensions to propietario_rpc;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;

select throws_ok(
  $$update public.camiones set empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000'
     where id = 'aaaaaaaa-0000-4000-8000-00000000c001'$$,
  '42501', null, 'propietario_rpc no puede mover un camión de empresa');
select throws_ok(
  $$update public.camiones set creado_por = 'aaaaaaaa-0000-4000-8000-000000000002'
     where id = 'aaaaaaaa-0000-4000-8000-00000000c001'$$,
  '42501', null, 'propietario_rpc no puede cambiar el autor');
select throws_ok(
  $$delete from public.camiones where id = 'aaaaaaaa-0000-4000-8000-00000000c001'$$,
  '42501', null, 'propietario_rpc no puede borrar');
select throws_ok(
  $$insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values ('bbbbbbbb-0000-4000-8000-000000000000', 'RLS001', 'Cruzado',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'RLS impide a propietario_rpc insertar en otra empresa');
select throws_ok(
  $$insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'RLS002', 'Ajeno',
            'aaaaaaaa-0000-4000-8000-000000000002')$$,
  '42501', null, 'RLS impide a propietario_rpc atribuir el alta a otro usuario');
select is(
  (select count(*)::int from public.camiones
    where empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000'),
  0,
  'propietario_rpc no ve camiones de otra empresa');

-- Con la identidad de un encargado, RLS impide cualquier escritura.
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000002","role":"authenticated"}', true);
select throws_ok(
  $$insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'RLS003', 'Encargado',
            'aaaaaaaa-0000-4000-8000-000000000002')$$,
  '42501', null, 'RLS impide a propietario_rpc insertar en nombre de un encargado');
select results_eq(
  $$with u as (update public.camiones set nombre = 'Hackeado'
                where id = 'aaaaaaaa-0000-4000-8000-00000000c001' returning 1)
    select count(*)::int from u$$,
  $$values (0)$$,
  'RLS impide a propietario_rpc editar en nombre de un encargado');

reset role;

-- ---------------------------------------------------------------------------
-- service_role (BYPASSRLS) tampoco accede: sin privilegios sobre camiones
-- ---------------------------------------------------------------------------
create temp table huella_service_role as
  select count(*)::int as filas,
         md5(string_agg(c::text, '|' order by c.id)) as camiones
    from public.camiones c;
grant select on huella_service_role to public;

grant usage on schema extensions to service_role;
set local role service_role;

select throws_ok('select * from public.camiones', '42501', null,
  'service_role no puede leer camiones (sin decisión aprobada)');
select throws_ok(
  $$insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'SR001', 'Directo SR',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'service_role no puede insertar');
select throws_ok(
  $$update public.camiones set nombre = 'SR' where true$$,
  '42501', null, 'service_role no puede actualizar');
select throws_ok(
  $$delete from public.camiones$$,
  '42501', null, 'service_role no puede borrar');
select throws_ok(
  $$select public.crear_camion('SR002', 'SR')$$,
  '42501', null, 'service_role no puede ejecutar crear_camion');

reset role;

select results_eq(
  $$select count(*)::int, md5(string_agg(c::text, '|' order by c.id))
      from public.camiones c$$,
  $$select filas, camiones from huella_service_role$$,
  'los intentos de service_role no modificaron la tabla');

select * from finish();

rollback;
