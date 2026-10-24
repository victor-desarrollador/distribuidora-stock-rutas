-- pgTAP: catálogo de clientes (Blueprint §2, §8, §9, §10, §12 Seguridad;
-- ADR-001 Topología D; decisiones humanas del slice clientes: vendedor/piloto
-- crea pendiente y no edita; dueño y encargado crean validado, editan,
-- validan y activan/desactivan; dueño y encargado leen activos e inactivos,
-- el vendedor/piloto sólo activos; sin unicidad ni bloqueo de duplicados).
-- Ejecutar sólo en local: `supabase test db`.
--
-- Se usan dos empresas EXCLUSIVAMENTE para demostrar aislamiento: la empresa B
-- es un fixture adversarial, no un producto multiempresa.

begin;

create extension if not exists pgtap with schema extensions;

select plan(183);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-0000-4000-8000-000000000000', 'Empresa A (test)'),
  ('bbbbbbbb-0000-4000-8000-000000000000', 'Empresa B (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  -- A1: dueño activo de A
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'cli.a1@usuarios.distribuidora.invalid', '{}'),
  -- A2: encargado activo de A
  ('aaaaaaaa-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'cli.a2@usuarios.distribuidora.invalid', '{}'),
  -- A3: vendedor activo de A, con metadata que pretende ser dueño
  ('aaaaaaaa-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'cli.a3@usuarios.distribuidora.invalid', '{"rol":"dueno"}'),
  -- A4: dueño INACTIVO de A
  ('aaaaaaaa-0000-4000-8000-000000000004', 'authenticated', 'authenticated',
   'cli.a4@usuarios.distribuidora.invalid', '{}'),
  -- A5: vendedor INACTIVO de A
  ('aaaaaaaa-0000-4000-8000-000000000005', 'authenticated', 'authenticated',
   'cli.a5@usuarios.distribuidora.invalid', '{}'),
  -- B1: dueño activo de B
  ('bbbbbbbb-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'cli.b1@usuarios.distribuidora.invalid', '{}'),
  -- B2: vendedor activo de B
  ('bbbbbbbb-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'cli.b2@usuarios.distribuidora.invalid', '{}'),
  -- N1: cuenta Auth sin perfil, con metadata falsa
  ('cccccccc-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'cli.n1@usuarios.distribuidora.invalid',
   '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000000',
   'cli.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000000',
   'cli.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000000',
   'cli.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000000',
   'cli.a4', 'A4', 'dueno', false),
  ('aaaaaaaa-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000000',
   'cli.a5', 'A5', 'vendedor_piloto', false),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000000',
   'cli.b1', 'B1', 'dueno', true),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000000',
   'cli.b2', 'B2', 'vendedor_piloto', true);

-- c001: validado por el dueño; c002: pendiente creado por el vendedor;
-- c003: validado e inactivo; B c001: de la otra empresa.
insert into public.clientes
  (id, empresa_id, nombre, comercio, direccion, telefono, activo,
   estado_validacion, creado_por, validado_por, validado_en) values
  ('aaaaaaaa-0000-4000-8000-00000000c001', 'aaaaaaaa-0000-4000-8000-000000000000',
   'Pedro Gómez', 'Almacén Don Pedro', 'Belgrano 1250', '3815551234', true,
   'validado', 'aaaaaaaa-0000-4000-8000-000000000001',
   'aaaaaaaa-0000-4000-8000-000000000001', '2026-10-01 10:00:00+00'),
  ('aaaaaaaa-0000-4000-8000-00000000c002', 'aaaaaaaa-0000-4000-8000-000000000000',
   'Marta Díaz', null, null, '3815550002', true,
   'pendiente', 'aaaaaaaa-0000-4000-8000-000000000003', null, null),
  ('aaaaaaaa-0000-4000-8000-00000000c003', 'aaaaaaaa-0000-4000-8000-000000000000',
   'Inactivo Uno', null, null, '3815550003', false,
   'validado', 'aaaaaaaa-0000-4000-8000-000000000002',
   'aaaaaaaa-0000-4000-8000-000000000002', '2026-10-02 10:00:00+00'),
  ('bbbbbbbb-0000-4000-8000-00000000c001', 'bbbbbbbb-0000-4000-8000-000000000000',
   'Cliente B', 'Comercio B', null, '3815559999', true,
   'validado', 'bbbbbbbb-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000001', '2026-10-03 10:00:00+00');

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
  ('public.crear_cliente(text,text,text,text)', true),
  ('public.actualizar_cliente(uuid,text,text,text,text)', true),
  ('public.validar_cliente(uuid)', true),
  ('public.cambiar_estado_cliente(uuid,boolean)', true),
  ('privado.crear_cliente(text,text,text,text)', false),
  ('privado.actualizar_cliente(uuid,text,text,text,text)', false),
  ('privado.validar_cliente(uuid)', false),
  ('privado.cambiar_estado_cliente(uuid,boolean)', false);
grant select on firmas to public;

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_table('public', 'clientes', 'la tabla public.clientes existe');

select is(
  array(select a.attname::text || ':' || format_type(a.atttypid, a.atttypmod)
               || ':' || a.attnotnull::text
               || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-')
          from pg_attribute a
          left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
         where a.attrelid = 'public.clientes'::regclass
           and a.attnum > 0 and not a.attisdropped
         order by a.attnum),
  array['id:uuid:true:gen_random_uuid()',
        'empresa_id:uuid:true:-',
        'nombre:text:true:-',
        'comercio:text:false:-',
        'direccion:text:false:-',
        'telefono:text:true:-',
        'activo:boolean:true:true',
        'estado_validacion:text:true:-',
        'creado_en:timestamp with time zone:true:now()',
        'creado_por:uuid:true:-',
        'validado_en:timestamp with time zone:false:-',
        'validado_por:uuid:false:-'],
  'columnas, tipos, NOT NULL y defaults del modelo (sin CUIT, email, zona, crédito ni condición de pago)');

select ok(
  (select relrowsecurity and not relforcerowsecurity
     from pg_class where oid = 'public.clientes'::regclass),
  'clientes tiene RLS habilitada y sin FORCE (P4)');

select is(
  (select count(*)::int from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity),
  0,
  'todas las tablas de public tienen RLS habilitada');

select is(
  (select relowner::regrole::text from pg_class
    where oid = 'public.clientes'::regclass),
  'postgres',
  'clientes pertenece al owner de las migraciones (no a propietario_rpc)');

select is(
  array(select conname::text from pg_constraint
         where conrelid = 'public.clientes'::regclass order by conname::text),
  array['clientes_comercio_normalizado', 'clientes_creado_por_fk',
        'clientes_direccion_normalizada', 'clientes_empresa_id_fkey',
        'clientes_empresa_id_unico', 'clientes_estado_validacion_valido',
        'clientes_nombre_normalizado', 'clientes_pkey',
        'clientes_telefono_normalizado', 'clientes_validacion_coherente',
        'clientes_validado_por_fk'],
  'constraints: PK, unique (empresa_id,id), FKs y CHECK; ninguna unicidad de nombre, teléfono, comercio ni dirección');

select is(
  (select count(*)::int from pg_index i
    where i.indrelid = 'public.clientes'::regclass
      and i.indisunique and not i.indisprimary
      and i.indexrelid::regclass::text <> 'clientes_empresa_id_unico'),
  0,
  'el único índice UNIQUE además de la PK es (empresa_id, id): no hay regla de duplicados');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint
    where conname = 'clientes_creado_por_fk'),
  'FOREIGN KEY (empresa_id, creado_por) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT',
  'el autor se valida con FK compuesta contra perfiles de la misma empresa');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint
    where conname = 'clientes_validado_por_fk'),
  'FOREIGN KEY (empresa_id, validado_por) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT',
  'el validador pertenece a la misma empresa (FK compuesta contra perfiles)');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint
    where conname = 'clientes_estado_validacion_valido'),
  'CHECK ((estado_validacion = ANY (ARRAY[''pendiente''::text, ''validado''::text])))',
  'estado_validacion sólo admite pendiente y validado');

select is(
  (select count(*)::int from firmas f where to_regprocedure(f.firma) is not null),
  8,
  'existen las ocho firmas aprobadas');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and p.proname in ('crear_cliente', 'actualizar_cliente',
                        'validar_cliente', 'cambiar_estado_cliente')),
  8,
  'una única firma por nombre y esquema (sin sobrecargas)');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and p.prosecdef
      and p.proname like '%cliente%'
      and p.pronamespace = 'public'::regnamespace),
  0,
  'ninguna función de clientes en public es SECURITY DEFINER');

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

select ok(
  not has_schema_privilege('anon', 'privado', 'usage')
  and not has_schema_privilege('propietario_rpc', 'privado', 'create'),
  'privado no es accesible para anon y propietario_rpc no puede crear objetos en privado');

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
select ok(
  not has_table_privilege('anon', 'public.clientes',
        'select, insert, update, delete, truncate, references, trigger')
  and not has_any_column_privilege('anon', 'public.clientes',
        'select, insert, update, references'),
  'anon no tiene ningún privilegio sobre clientes (ni por columna)');

select ok(
  has_table_privilege('authenticated', 'public.clientes', 'select'),
  'authenticated puede leer clientes');

select ok(
  not has_table_privilege('authenticated', 'public.clientes',
        'insert, update, delete, truncate, references, trigger')
  and not has_any_column_privilege('authenticated', 'public.clientes', 'insert')
  and not has_any_column_privilege('authenticated', 'public.clientes', 'update')
  and not has_any_column_privilege('authenticated', 'public.clientes', 'references'),
  'authenticated sólo tiene SELECT sobre clientes (ni INSERT/UPDATE por columna)');

select ok(
  not exists (
    select 1 from pg_class c, aclexplode(c.relacl) a
     where c.oid = 'public.clientes'::regclass and a.grantee = 0),
  'PUBLIC no tiene privilegios sobre clientes');

-- Política deliberada del slice: sin decisión aprobada para clientes y con
-- P11 global pendiente, service_role no recibe nada.
select ok(
  not has_table_privilege('service_role', 'public.clientes',
        'select, insert, update, delete, truncate, references, trigger')
  and not has_any_column_privilege('service_role', 'public.clientes',
        'select, insert, update, references'),
  'service_role no tiene ningún privilegio sobre clientes (sin decisión aprobada; P11 global pendiente)');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.clientes'::regclass and a.attnum > 0
           and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.clientes', a.attname, 'insert')
         order by a.attname::text),
  array['comercio', 'creado_por', 'direccion', 'empresa_id', 'estado_validacion',
        'nombre', 'telefono', 'validado_en', 'validado_por'],
  'propietario_rpc inserta sólo las columnas del alta (sin id, activo ni creado_en)');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.clientes'::regclass and a.attnum > 0
           and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.clientes', a.attname, 'update')
         order by a.attname::text),
  array['activo', 'comercio', 'direccion', 'estado_validacion', 'nombre',
        'telefono', 'validado_en', 'validado_por'],
  'propietario_rpc actualiza sólo campos editables, activo y validación (nunca empresa_id, creado_por, creado_en ni id)');

select ok(
  has_table_privilege('propietario_rpc', 'public.clientes', 'select')
  and not has_table_privilege('propietario_rpc', 'public.clientes',
        'delete, truncate, references, trigger'),
  'propietario_rpc lee clientes y no puede borrar ni truncar');

select is(
  (select count(*)::int from firmas f
    where not has_function_privilege('authenticated', f.firma, 'execute')),
  0,
  'authenticated puede ejecutar las ocho firmas aprobadas');

select is(
  (select count(*)::int from firmas f
    where has_function_privilege('anon', f.firma, 'execute')
       or has_function_privilege('service_role', f.firma, 'execute')),
  0,
  'anon y service_role no pueden ejecutar ninguna RPC de clientes');

select is(
  (select count(*)::int from firmas f
     join pg_proc p on p.oid = f.firma::regprocedure
    where p.proacl is null
       or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)),
  0,
  'ninguna RPC de clientes conserva EXECUTE para PUBLIC');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('exigir_perfil_clientes', 'validar_campos_cliente',
                        'error_restriccion_cliente',
                        'estado_http_restriccion_cliente')
      and (has_function_privilege('authenticated', p.oid, 'execute')
           or has_function_privilege('anon', p.oid, 'execute')
           or has_function_privilege('service_role', p.oid, 'execute')
           or p.proacl is null
           or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0))),
  0,
  'los auxiliares de clientes en privado sólo los ejecuta propietario_rpc');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('exigir_perfil_clientes', 'validar_campos_cliente',
                        'error_restriccion_cliente',
                        'estado_http_restriccion_cliente')),
  4,
  'existen los cuatro auxiliares privados de clientes');

-- ---------------------------------------------------------------------------
-- Bypass directo: authenticated y anon no escriben la tabla
-- ---------------------------------------------------------------------------
create temp table huella_antes as
  select md5(string_agg(c::text, '|' order by c.id)) as clientes
    from public.clientes c;
grant select on huella_antes to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'Directo', '1',
            'pendiente', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'el dueño no puede insertar directamente');
select throws_ok(
  $$update public.clientes set nombre = 'Directo'$$,
  '42501', null, 'el dueño no puede actualizar directamente');
select throws_ok(
  $$delete from public.clientes$$,
  '42501', null, 'el dueño no puede borrar clientes');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'Directo', '1',
            'pendiente', 'aaaaaaaa-0000-4000-8000-000000000002')$$,
  '42501', null, 'el encargado no puede insertar directamente');
select throws_ok(
  $$update public.clientes set activo = false$$,
  '42501', null, 'el encargado no puede actualizar directamente');
select throws_ok(
  $$delete from public.clientes$$,
  '42501', null, 'el encargado no puede borrar clientes');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003',
  '{"rol":"dueno"}');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'Directo', '1',
            'pendiente', 'aaaaaaaa-0000-4000-8000-000000000003')$$,
  '42501', null, 'el vendedor con metadata de dueño no puede insertar directamente');
select throws_ok(
  $$update public.clientes set estado_validacion = 'validado'$$,
  '42501', null, 'el vendedor no puede auto-validar clientes directamente');
select throws_ok(
  $$delete from public.clientes$$,
  '42501', null, 'el vendedor no puede borrar clientes');

select pg_temp.como_anon();
select throws_ok('select * from public.clientes', '42501', null,
  'anon no puede leer clientes');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'Directo', '1',
            'pendiente', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'anon no puede insertar directamente');
select throws_ok($$update public.clientes set nombre = 'x'$$,
  '42501', null, 'anon no puede actualizar directamente');
select throws_ok($$delete from public.clientes$$,
  '42501', null, 'anon no puede borrar clientes');
select throws_ok($$select public.crear_cliente('X', '1')$$,
  '42501', null, 'anon no puede ejecutar crear_cliente');
select throws_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c001', 'X', '1', null, null)$$,
  '42501', null, 'anon no puede ejecutar actualizar_cliente');
select throws_ok(
  $$select public.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c002')$$,
  '42501', null, 'anon no puede ejecutar validar_cliente');
select throws_ok(
  $$select public.cambiar_estado_cliente('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  '42501', null, 'anon no puede ejecutar cambiar_estado_cliente');
select throws_ok($$select privado.crear_cliente('X', '1')$$,
  '42501', null, 'anon no puede ejecutar la implementación privada');

reset role;

select is(
  (select md5(string_agg(c::text, '|' order by c.id)) from public.clientes c),
  (select clientes from huella_antes),
  'los intentos directos no cambiaron ningún cliente');

-- ---------------------------------------------------------------------------
-- Lectura por empresa y estado del perfil
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select results_eq(
  $$select id from public.clientes order by id$$,
  $$values ('aaaaaaaa-0000-4000-8000-00000000c001'::uuid),
           ('aaaaaaaa-0000-4000-8000-00000000c002'::uuid),
           ('aaaaaaaa-0000-4000-8000-00000000c003'::uuid)$$,
  'el dueño lee los clientes de su empresa, activos e inactivos, y no los de otra');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select results_eq(
  $$select id from public.clientes order by id$$,
  $$values ('aaaaaaaa-0000-4000-8000-00000000c001'::uuid),
           ('aaaaaaaa-0000-4000-8000-00000000c002'::uuid),
           ('aaaaaaaa-0000-4000-8000-00000000c003'::uuid)$$,
  'el encargado lee los clientes de su empresa, activos e inactivos');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select results_eq(
  $$select id from public.clientes order by id$$,
  $$values ('aaaaaaaa-0000-4000-8000-00000000c001'::uuid),
           ('aaaaaaaa-0000-4000-8000-00000000c002'::uuid)$$,
  'el vendedor/piloto lee sólo los clientes activos de su empresa');

-- Decisión humana: dueño y encargado ven inactivos; el vendedor/piloto, no.
select is(
  (select count(*)::int from public.clientes
    where id = 'aaaaaaaa-0000-4000-8000-00000000c001'),
  1,
  'vendedor + cliente activo: visible');
select is(
  (select count(*)::int from public.clientes
    where id = 'aaaaaaaa-0000-4000-8000-00000000c003'),
  0,
  'vendedor + cliente inactivo: invisible');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003', '{"rol":"dueno"}');
select is(
  (select count(*)::int from public.clientes
    where id = 'aaaaaaaa-0000-4000-8000-00000000c003'),
  0,
  'vendedor con metadata de dueño + cliente inactivo: invisible (metadata ignorada)');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select is(
  (select count(*)::int from public.clientes
    where id = 'aaaaaaaa-0000-4000-8000-00000000c003'),
  1,
  'dueño + cliente inactivo: visible');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select is(
  (select count(*)::int from public.clientes
    where id = 'aaaaaaaa-0000-4000-8000-00000000c003'),
  1,
  'encargado + cliente inactivo: visible');

select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select results_eq(
  $$select id from public.clientes order by id$$,
  $$values ('bbbbbbbb-0000-4000-8000-00000000c001'::uuid)$$,
  'el dueño de B sólo ve clientes de B (otra empresa no ve)');

select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000002');
select results_eq(
  $$select id from public.clientes order by id$$,
  $$values ('bbbbbbbb-0000-4000-8000-00000000c001'::uuid)$$,
  'el vendedor de B sólo ve clientes de B');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000004');
select is((select count(*)::int from public.clientes), 0,
  'un dueño inactivo no ve clientes');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000005');
select is((select count(*)::int from public.clientes), 0,
  'un vendedor inactivo no ve clientes');

select pg_temp.como_usuario('cccccccc-0000-4000-8000-000000000001',
  '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');
select is((select count(*)::int from public.clientes), 0,
  'una cuenta sin perfil no ve clientes, aunque su metadata diga dueño');

-- ---------------------------------------------------------------------------
-- Autorización de las RPC
-- ---------------------------------------------------------------------------
-- Cuenta sin perfil (N1, sigue como authenticated): nada.
select throws_ok($$select public.crear_cliente('NP', '1')$$,
  'PT403', 'cliente_no_autorizado', 'una cuenta sin perfil no puede crear');
select throws_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c001', 'NP', '1', null, null)$$,
  'PT403', 'cliente_no_autorizado', 'una cuenta sin perfil no puede actualizar');
select throws_ok(
  $$select public.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c002')$$,
  'PT403', 'cliente_no_autorizado', 'una cuenta sin perfil no puede validar');
select throws_ok(
  $$select public.cambiar_estado_cliente('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  'PT403', 'cliente_no_autorizado', 'una cuenta sin perfil no puede cambiar el estado');

-- Dueño inactivo (A4) y vendedor inactivo (A5): nada.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000004');
select throws_ok($$select public.crear_cliente('IN', '1')$$,
  'PT403', 'cliente_no_autorizado', 'un dueño inactivo no puede crear');
select throws_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c001', 'IN', '1', null, null)$$,
  'PT403', 'cliente_no_autorizado', 'un dueño inactivo no puede actualizar');
select throws_ok(
  $$select public.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c002')$$,
  'PT403', 'cliente_no_autorizado', 'un dueño inactivo no puede validar');
select throws_ok(
  $$select public.cambiar_estado_cliente('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  'PT403', 'cliente_no_autorizado', 'un dueño inactivo no puede cambiar el estado');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000005');
select throws_ok($$select public.crear_cliente('IN', '1')$$,
  'PT403', 'cliente_no_autorizado', 'un vendedor inactivo no puede crear');

-- Vendedor (A3) con user_metadata.rol = 'dueno': crea, pero nada más.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003', '{"rol":"dueno"}');
select throws_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c002', 'VE', '1', null, null)$$,
  'PT403', 'cliente_no_autorizado', 'el vendedor no puede actualizar (metadata ignorada)');
select throws_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c001', 'VE', '1', null, null)$$,
  'PT403', 'cliente_no_autorizado', 'el vendedor no puede editar un cliente validado');
select throws_ok(
  $$select public.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c002')$$,
  'PT403', 'cliente_no_autorizado', 'el vendedor no puede validar ni siquiera su propio alta');
select throws_ok(
  $$select public.cambiar_estado_cliente('aaaaaaaa-0000-4000-8000-00000000c002', false)$$,
  'PT403', 'cliente_no_autorizado', 'el vendedor no puede activar ni desactivar');
select throws_ok(
  $$select privado.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c002', 'VE', '1', null, null)$$,
  'PT403', 'cliente_no_autorizado',
  'la implementación privada llamada por SQL también rechaza al vendedor');
select throws_ok(
  $$select privado.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c002')$$,
  'PT403', 'cliente_no_autorizado',
  'validar_cliente privado llamado por SQL también rechaza al vendedor');

-- Sin sub en el JWT: no autenticado.
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok($$select public.crear_cliente('NA', '1')$$,
  'PT401', 'cliente_no_autenticado', 'sin sub en el JWT: no autenticado');
select throws_ok(
  $$select public.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c002')$$,
  'PT401', 'cliente_no_autenticado', 'validar sin sub en el JWT: no autenticado');

-- ---------------------------------------------------------------------------
-- Aislamiento por empresa_id
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c001', 'Robado', '1', null, null)$$,
  'PT404', 'cliente_no_encontrado', 'el dueño de B no puede actualizar un cliente de A');
select throws_ok(
  $$select public.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c002')$$,
  'PT404', 'cliente_no_encontrado', 'el dueño de B no puede validar un cliente de A');
select throws_ok(
  $$select public.cambiar_estado_cliente('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  'PT404', 'cliente_no_encontrado', 'el dueño de B no puede desactivar un cliente de A');
select throws_ok(
  $$select public.actualizar_cliente('eeeeeeee-0000-4000-8000-000000000000', 'X', '1', null, null)$$,
  'PT404', 'cliente_no_encontrado', 'un cliente inexistente responde igual que uno de otra empresa (actualizar)');
select throws_ok(
  $$select public.validar_cliente('eeeeeeee-0000-4000-8000-000000000000')$$,
  'PT404', 'cliente_no_encontrado', 'un cliente inexistente responde igual que uno de otra empresa (validar)');
select throws_ok($$select public.cambiar_estado_cliente(null, false)$$,
  'PT404', 'cliente_no_encontrado', 'un id nulo responde no encontrado');

-- Simétrico: dueño y encargado de A tampoco tocan el cliente de B.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.actualizar_cliente('bbbbbbbb-0000-4000-8000-00000000c001', 'Robado', '1', null, null)$$,
  'PT404', 'cliente_no_encontrado', 'el dueño de A no puede actualizar un cliente de B');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select throws_ok(
  $$select public.cambiar_estado_cliente('bbbbbbbb-0000-4000-8000-00000000c001', false)$$,
  'PT404', 'cliente_no_encontrado', 'el encargado de A no puede desactivar un cliente de B');

-- Dueño de A: empresa_id/creado_por/validado_por no son parámetros.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.crear_cliente(p_nombre => 'E', p_telefono => '1',
                                p_empresa_id => 'bbbbbbbb-0000-4000-8000-000000000000')$$,
  '42883', null, 'crear_cliente no acepta p_empresa_id');
select throws_ok(
  $$select public.crear_cliente(p_nombre => 'E', p_telefono => '1',
                                p_creado_por => 'aaaaaaaa-0000-4000-8000-000000000002')$$,
  '42883', null, 'crear_cliente no acepta p_creado_por');
select throws_ok(
  $$select public.crear_cliente(p_nombre => 'E', p_telefono => '1',
                                p_estado_validacion => 'validado')$$,
  '42883', null, 'crear_cliente no acepta p_estado_validacion');
select throws_ok(
  $$select public.validar_cliente(p_cliente_id => 'aaaaaaaa-0000-4000-8000-00000000c002',
                                  p_validado_por => 'aaaaaaaa-0000-4000-8000-000000000002')$$,
  '42883', null, 'validar_cliente no acepta p_validado_por');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and p.proname in ('crear_cliente', 'actualizar_cliente',
                        'validar_cliente', 'cambiar_estado_cliente')
      and (p.proargnames && array['p_empresa_id', 'empresa_id', 'p_creado_por',
                                  'creado_por', 'p_validado_por', 'validado_por',
                                  'p_validado_en', 'validado_en',
                                  'p_estado_validacion', 'estado_validacion'])),
  0,
  'ninguna firma de clientes recibe empresa, autor, validador ni estado de validación');

-- Headers inventados no cambian la empresa: el servidor la deriva del perfil.
select set_config('request.headers',
  '{"x-empresa-id":"bbbbbbbb-0000-4000-8000-000000000000"}', true);
create temp table creados (clave text, id uuid);
grant select, insert on creados to public;
select lives_ok(
  $$insert into creados select 'header', public.crear_cliente('Con header', '111')$$,
  'el dueño crea un cliente con un header de empresa inventado');

reset role;
select is(
  (select empresa_id from public.clientes c join creados x on x.id = c.id
    where x.clave = 'header'),
  'aaaaaaaa-0000-4000-8000-000000000000'::uuid,
  'el header inventado se ignora: el cliente queda en la empresa del perfil');

select is(
  (select count(*)::int from public.clientes
    where empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000'),
  1,
  'los intentos cruzados no crearon clientes en B');

select results_eq(
  $$select nombre, telefono, activo, estado_validacion from public.clientes
     where id = 'bbbbbbbb-0000-4000-8000-00000000c001'$$,
  $$values ('Cliente B', '3815559999', true, 'validado')$$,
  'los intentos cruzados no cambiaron la fila de B');

-- ---------------------------------------------------------------------------
-- Alta
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into creados select 'dueno',
      public.crear_cliente('  Juan Pérez  ', '  3815551111  ',
                           '  Kiosco Juan  ', '  Mitre 100  ')$$,
  'el dueño crea un cliente con todos los campos');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$insert into creados select 'encargado',
      public.crear_cliente('Ana López', '3815552222')$$,
  'el encargado crea un cliente sin comercio ni dirección');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003', '{"rol":"dueno"}');
select lives_ok(
  $$insert into creados select 'vendedor',
      public.crear_cliente('Luis Gómez', '3815553333', 'Despensa Luis', null)$$,
  'el vendedor/piloto crea un cliente (con metadata de dueño que se ignora)');

select lives_ok(
  $$insert into creados select 'opcionales_vacios',
      public.crear_cliente('Vacíos', '3815554444', '   ', '')$$,
  'comercio y dirección vacíos o de espacios se aceptan');

reset role;

select results_eq(
  $$select c.empresa_id, c.creado_por, c.nombre, c.telefono, c.comercio,
           c.direccion, c.activo, c.estado_validacion, c.validado_por,
           c.validado_en is not null
      from public.clientes c join creados x on x.id = c.id
     where x.clave = 'dueno'$$,
  $$values ('aaaaaaaa-0000-4000-8000-000000000000'::uuid,
            'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
            'Juan Pérez', '3815551111', 'Kiosco Juan', 'Mitre 100', true,
            'validado', 'aaaaaaaa-0000-4000-8000-000000000001'::uuid, true)$$,
  'alta del dueño: validado, validado_por = dueño, validado_en del servidor, textos con trim, empresa y autor del perfil');

select results_eq(
  $$select c.creado_por, c.comercio, c.direccion, c.estado_validacion,
           c.validado_por, c.validado_en is not null
      from public.clientes c join creados x on x.id = c.id
     where x.clave = 'encargado'$$,
  $$values ('aaaaaaaa-0000-4000-8000-000000000002'::uuid, null::text, null::text,
            'validado', 'aaaaaaaa-0000-4000-8000-000000000002'::uuid, true)$$,
  'alta del encargado: validado por el encargado; comercio y dirección omitidos quedan NULL');

select results_eq(
  $$select c.empresa_id, c.creado_por, c.comercio, c.direccion,
           c.estado_validacion, c.validado_por, c.validado_en
      from public.clientes c join creados x on x.id = c.id
     where x.clave = 'vendedor'$$,
  $$values ('aaaaaaaa-0000-4000-8000-000000000000'::uuid,
            'aaaaaaaa-0000-4000-8000-000000000003'::uuid,
            'Despensa Luis', null::text, 'pendiente', null::uuid,
            null::timestamptz)$$,
  'alta del vendedor/piloto: pendiente, sin validador ni fecha de validación');

select results_eq(
  $$select c.comercio, c.direccion from public.clientes c
      join creados x on x.id = c.id where x.clave = 'opcionales_vacios'$$,
  $$values (null::text, null::text)$$,
  'comercio y dirección vacíos o de espacios se guardan como NULL');

select is(
  (select c.validado_en from public.clientes c join creados x on x.id = c.id
    where x.clave = 'dueno'),
  now(),
  'validado_en es el now() del servidor (no un valor del cliente)');

-- ---------------------------------------------------------------------------
-- Validaciones de campos
-- ---------------------------------------------------------------------------
create temp table conteo_antes as select count(*)::int as n from public.clientes;
grant select on conteo_antes to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');

select throws_ok($$select public.crear_cliente(null, '1')$$,
  'PT400', 'cliente_nombre_invalido', 'un nombre nulo se rechaza');
select throws_ok($$select public.crear_cliente('', '1')$$,
  'PT400', 'cliente_nombre_invalido', 'un nombre vacío se rechaza');
select throws_ok($$select public.crear_cliente('   ', '1')$$,
  'PT400', 'cliente_nombre_invalido', 'un nombre de espacios se rechaza');
select throws_ok($$select public.crear_cliente('X', null)$$,
  'PT400', 'cliente_telefono_invalido', 'un teléfono nulo se rechaza');
select throws_ok($$select public.crear_cliente('X', '')$$,
  'PT400', 'cliente_telefono_invalido', 'un teléfono vacío se rechaza');
select throws_ok($$select public.crear_cliente('X', '   ')$$,
  'PT400', 'cliente_telefono_invalido', 'un teléfono de espacios se rechaza');
select throws_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c001', ' ', '1', null, null)$$,
  'PT400', 'cliente_nombre_invalido', 'actualizar con nombre vacío se rechaza');
select throws_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c001', 'X', null, null, null)$$,
  'PT400', 'cliente_telefono_invalido', 'actualizar con teléfono nulo se rechaza');
select throws_ok(
  $$select public.cambiar_estado_cliente('aaaaaaaa-0000-4000-8000-00000000c001', null)$$,
  'PT400', 'cliente_estado_invalido', 'un estado nulo se rechaza');
select throws_ok($$select privado.crear_cliente(' ', '1')$$,
  'PT400', 'cliente_nombre_invalido',
  'la implementación privada llamada por SQL también valida');

select lives_ok(
  $$insert into creados select 'letras', public.crear_cliente('Sin formato', 'llamar a la tarde')$$,
  'el teléfono no tiene regex ni normalización: se acepta tal cual');

reset role;

select is((select count(*)::int from public.clientes), (select n from conteo_antes) + 1,
  'sólo el caso válido creó un cliente; ningún alta inválida dejó filas');

-- ---------------------------------------------------------------------------
-- Duplicados permitidos
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into creados select 'dup_nombre', public.crear_cliente('Pedro Gómez', '3810000001')$$,
  'mismo nombre que otro cliente: permitido (homónimos)');
select lives_ok(
  $$insert into creados select 'dup_tel', public.crear_cliente('Otro Nombre', '3815551234')$$,
  'mismo teléfono que otro cliente: permitido');
select lives_ok(
  $$insert into creados select 'dup_total',
      public.crear_cliente('Pedro Gómez', '3815551234', 'Almacén Don Pedro', 'Belgrano 1250')$$,
  'duplicado completo de un cliente existente: permitido');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select lives_ok(
  $$insert into creados select 'dup_vendedor',
      public.crear_cliente('Pedro Gómez', '3815551234', 'Almacén Don Pedro', 'Belgrano 1250')$$,
  'el vendedor/piloto también puede repetir datos (queda pendiente para validar)');

select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into creados select 'dup_empresa_b',
      public.crear_cliente('Pedro Gómez', '3815551234', 'Almacén Don Pedro', 'Belgrano 1250')$$,
  'los mismos datos en otra empresa se aceptan');

reset role;

select is(
  (select count(*)::int from public.clientes
    where nombre = 'Pedro Gómez' and telefono = '3815551234'
      and empresa_id = 'aaaaaaaa-0000-4000-8000-000000000000'),
  3,
  'conviven tres clientes con el mismo nombre y teléfono en la empresa A');

-- ---------------------------------------------------------------------------
-- Edición (dueño y encargado)
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c001',
      '  Pedro G. ', ' 3815550000 ', ' Almacén P ', ' San Martín 5 ')$$,
  'el dueño edita un cliente');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c002',
      'Marta Díaz Ruiz', '3815550022', 'Tienda Marta', null)$$,
  'el encargado edita un cliente pendiente');

reset role;

select results_eq(
  $$select nombre, telefono, comercio, direccion from public.clientes
     where id = 'aaaaaaaa-0000-4000-8000-00000000c001'$$,
  $$values ('Pedro G.', '3815550000', 'Almacén P', 'San Martín 5')$$,
  'la edición del dueño queda guardada con trim');

select results_eq(
  $$select nombre, telefono, comercio, direccion, estado_validacion, validado_por
      from public.clientes where id = 'aaaaaaaa-0000-4000-8000-00000000c002'$$,
  $$values ('Marta Díaz Ruiz', '3815550022', 'Tienda Marta', null::text,
            'pendiente', null::uuid)$$,
  'editar un pendiente no lo valida');

select results_eq(
  $$select creado_por, validado_por, estado_validacion, empresa_id, activo
      from public.clientes where id = 'aaaaaaaa-0000-4000-8000-00000000c001'$$,
  $$values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
            'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
            'validado', 'aaaaaaaa-0000-4000-8000-000000000000'::uuid, true)$$,
  'editar no cambia autor, validador, estado de validación, empresa ni activo');

select is(
  (select validado_en from public.clientes
    where id = 'aaaaaaaa-0000-4000-8000-00000000c001'),
  '2026-10-01 10:00:00+00'::timestamptz,
  'editar no cambia validado_en');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c001',
      'Pedro G.', '3815550000', null, '')$$,
  'editar permite borrar comercio y dirección con null o vacío');
select lives_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c003',
      'Inactivo Uno', '3815550003', null, null)$$,
  'se puede editar un cliente inactivo');
reset role;
select results_eq(
  $$select comercio, direccion from public.clientes
     where id = 'aaaaaaaa-0000-4000-8000-00000000c001'$$,
  $$values (null::text, null::text)$$,
  'comercio y dirección borrados quedan NULL');

-- Los campos protegidos no se pueden cambiar por ninguna RPC: actualizar no
-- los recibe, así que ni el dueño ni el encargado pueden alterarlos.
select is(
  (select count(*)::int from public.clientes
    where id = 'aaaaaaaa-0000-4000-8000-00000000c001'
      and creado_por = 'aaaaaaaa-0000-4000-8000-000000000001'
      and creado_en is not null
      and empresa_id = 'aaaaaaaa-0000-4000-8000-000000000000'),
  1,
  'la metadata protegida del cliente editado sigue intacta');

-- ---------------------------------------------------------------------------
-- Validación (pendiente → validado)
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c002')$$,
  'el dueño valida un cliente pendiente');
reset role;

select results_eq(
  $$select estado_validacion, validado_por, validado_en is not null
      from public.clientes where id = 'aaaaaaaa-0000-4000-8000-00000000c002'$$,
  $$values ('validado', 'aaaaaaaa-0000-4000-8000-000000000001'::uuid, true)$$,
  'la validación fija estado, validado_por = dueño y validado_en del servidor');

select is(
  (select validado_en from public.clientes
    where id = 'aaaaaaaa-0000-4000-8000-00000000c002'),
  now(),
  'validado_en de la validación es el now() del servidor');

create temp table validacion_antes as
  select validado_por, validado_en from public.clientes
   where id = 'aaaaaaaa-0000-4000-8000-00000000c002';
grant select on validacion_antes to public;

-- Validar de nuevo (idempotente): otro usuario de gestión no pisa al validador original.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c002')$$,
  'validar un cliente ya validado es idempotente (no falla)');
reset role;

select results_eq(
  $$select validado_por, validado_en from public.clientes
     where id = 'aaaaaaaa-0000-4000-8000-00000000c002'$$,
  $$select validado_por, validado_en from validacion_antes$$,
  'la revalidación conserva el validador y la fecha originales');

-- El encargado valida un pendiente creado por el vendedor.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select lives_ok(
  $$insert into creados select 'a_validar', public.crear_cliente('Para validar', '3815556666')$$,
  'el vendedor crea un pendiente');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.validar_cliente((select id from creados where clave = 'a_validar'))$$,
  'el encargado valida un pendiente creado por el vendedor');
reset role;
select results_eq(
  $$select c.estado_validacion, c.validado_por, c.creado_por
      from public.clientes c join creados x on x.id = c.id
     where x.clave = 'a_validar'$$,
  $$values ('validado', 'aaaaaaaa-0000-4000-8000-000000000002'::uuid,
            'aaaaaaaa-0000-4000-8000-000000000003'::uuid)$$,
  'validado por el encargado; el autor original no cambia');

-- Validar un inactivo también transiciona (no se inventan reglas extra).
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c003')$$,
  'validar un cliente ya validado e inactivo no falla ni lo reactiva');
reset role;
select is(
  (select activo from public.clientes where id = 'aaaaaaaa-0000-4000-8000-00000000c003'),
  false,
  'validar no cambia el estado activo');

-- ---------------------------------------------------------------------------
-- Activar / desactivar
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.cambiar_estado_cliente('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  'el dueño desactiva un cliente');
select lives_ok(
  $$select public.cambiar_estado_cliente('aaaaaaaa-0000-4000-8000-00000000c001', false)$$,
  'repetir la desactivación no falla');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select is(
  (select count(*)::int from public.clientes
    where id = 'aaaaaaaa-0000-4000-8000-00000000c001'),
  0,
  'el vendedor deja de ver un cliente al desactivarlo');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.cambiar_estado_cliente('aaaaaaaa-0000-4000-8000-00000000c001', true)$$,
  'el encargado reactiva un cliente');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select is(
  (select count(*)::int from public.clientes
    where id = 'aaaaaaaa-0000-4000-8000-00000000c001'),
  1,
  'el vendedor vuelve a ver un cliente reactivado');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.cambiar_estado_cliente('aaaaaaaa-0000-4000-8000-00000000c003', true)$$,
  'el encargado activa un cliente inactivo');
reset role;
select results_eq(
  $$select id, activo from public.clientes
     where id in ('aaaaaaaa-0000-4000-8000-00000000c001',
                  'aaaaaaaa-0000-4000-8000-00000000c003') order by id$$,
  $$values ('aaaaaaaa-0000-4000-8000-00000000c001'::uuid, true),
           ('aaaaaaaa-0000-4000-8000-00000000c003'::uuid, true)$$,
  'los cambios de activo quedan guardados');

-- ---------------------------------------------------------------------------
-- Atomicidad: lo inválido no altera filas
-- ---------------------------------------------------------------------------
create temp table huella_atomicidad as
  select md5(string_agg(c::text, '|' order by c.id)) as clientes
    from public.clientes c;
grant select on huella_atomicidad to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c001', '  ', '1', 'No', 'No')$$,
  'PT400', 'cliente_nombre_invalido', 'una edición inválida se rechaza');
select throws_ok(
  $$select public.actualizar_cliente('aaaaaaaa-0000-4000-8000-00000000c001', 'N', ' ', 'No', 'No')$$,
  'PT400', 'cliente_telefono_invalido', 'una edición sin teléfono se rechaza');
select throws_ok(
  $$select public.validar_cliente('eeeeeeee-0000-4000-8000-000000000000')$$,
  'PT404', 'cliente_no_encontrado', 'una validación inexistente se rechaza');
select throws_ok(
  $$select public.cambiar_estado_cliente('aaaaaaaa-0000-4000-8000-00000000c001', null)$$,
  'PT400', 'cliente_estado_invalido', 'un cambio de estado nulo se rechaza');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select throws_ok(
  $$select public.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c002')$$,
  'PT403', 'cliente_no_autorizado', 'una validación del vendedor se rechaza');
reset role;

select is(
  (select md5(string_agg(c::text, '|' order by c.id)) from public.clientes c),
  (select clientes from huella_atomicidad),
  'ningún intento fallido (edición, validación, estado) alteró ninguna fila');

-- ---------------------------------------------------------------------------
-- Restricciones de la tabla (defensa si alguien escribiera como owner)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', ' T', '1', 'pendiente',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza nombres sin normalizar');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'T', '', 'pendiente',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza teléfonos vacíos');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, comercio, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'T', '', '1', 'pendiente',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza comercio vacío (debe ser NULL)');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, direccion, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'T', ' x', '1', 'pendiente',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza dirección sin normalizar');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'T', '1', 'aprobado',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza estados de validación fuera de pendiente/validado');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'T', '1', 'validado',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza validado sin validador ni fecha');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por, validado_por, validado_en)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'T', '1', 'pendiente',
            'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000001', now())$$,
  '23514', null, 'la tabla rechaza pendiente con validador');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por)
    values ('bbbbbbbb-0000-4000-8000-000000000000', 'T', '1', 'pendiente',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23503', null, 'un cliente de B no puede tener como autor a un usuario de A');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por, validado_por, validado_en)
    values ('bbbbbbbb-0000-4000-8000-000000000000', 'T', '1', 'validado',
            'bbbbbbbb-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000001', now())$$,
  '23503', null, 'un cliente de B no puede tener como validador a un usuario de A');

-- ---------------------------------------------------------------------------
-- propietario_rpc: limitado por privilegios y RLS
-- ---------------------------------------------------------------------------
-- USAGE sobre `extensions` sólo para poder invocar pgTAP con ese rol; se
-- revierte con la transacción del test y no toca clientes.
grant usage on schema extensions to propietario_rpc;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;

select throws_ok(
  $$update public.clientes set empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000'
     where id = 'aaaaaaaa-0000-4000-8000-00000000c001'$$,
  '42501', null, 'propietario_rpc no puede mover un cliente de empresa');
select throws_ok(
  $$update public.clientes set creado_por = 'aaaaaaaa-0000-4000-8000-000000000002'
     where id = 'aaaaaaaa-0000-4000-8000-00000000c001'$$,
  '42501', null, 'propietario_rpc no puede cambiar el autor');
select throws_ok(
  $$update public.clientes set creado_en = now()
     where id = 'aaaaaaaa-0000-4000-8000-00000000c001'$$,
  '42501', null, 'propietario_rpc no puede cambiar creado_en');
select throws_ok(
  $$delete from public.clientes where id = 'aaaaaaaa-0000-4000-8000-00000000c001'$$,
  '42501', null, 'propietario_rpc no puede borrar');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por, validado_por, validado_en)
    values ('bbbbbbbb-0000-4000-8000-000000000000', 'RLS', '1', 'validado',
            'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000001', now())$$,
  '42501', null, 'RLS impide a propietario_rpc insertar en otra empresa');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por, validado_por, validado_en)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'RLS', '1', 'validado',
            'aaaaaaaa-0000-4000-8000-000000000002',
            'aaaaaaaa-0000-4000-8000-000000000001', now())$$,
  '42501', null, 'RLS impide a propietario_rpc atribuir el alta a otro usuario');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'RLS', '1', 'pendiente',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'RLS impide a propietario_rpc dar de alta como pendiente en nombre de un dueño');
select is(
  (select count(*)::int from public.clientes
    where empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000'),
  0,
  'propietario_rpc no ve clientes de otra empresa');

-- Con la identidad de un vendedor, RLS impide validar o editar.
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000003","role":"authenticated"}', true);
select results_eq(
  $$with u as (update public.clientes set nombre = 'Hackeado'
                where id = 'aaaaaaaa-0000-4000-8000-00000000c001' returning 1)
    select count(*)::int from u$$,
  $$values (0)$$,
  'RLS impide a propietario_rpc editar en nombre de un vendedor');
select results_eq(
  $$with u as (update public.clientes
                  set estado_validacion = 'validado',
                      validado_por = 'aaaaaaaa-0000-4000-8000-000000000003',
                      validado_en = now()
                where estado_validacion = 'pendiente' returning 1)
    select count(*)::int from u$$,
  $$values (0)$$,
  'RLS impide a propietario_rpc validar en nombre de un vendedor');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por, validado_por, validado_en)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'RLS', '1', 'validado',
            'aaaaaaaa-0000-4000-8000-000000000003',
            'aaaaaaaa-0000-4000-8000-000000000003', now())$$,
  '42501', null, 'RLS impide a propietario_rpc dar de alta como validado en nombre de un vendedor');

reset role;

-- ---------------------------------------------------------------------------
-- service_role (BYPASSRLS) tampoco accede: sin privilegios sobre clientes
-- ---------------------------------------------------------------------------
create temp table huella_service_role as
  select count(*)::int as filas,
         md5(string_agg(c::text, '|' order by c.id)) as clientes
    from public.clientes c;
grant select on huella_service_role to public;

grant usage on schema extensions to service_role;
set local role service_role;

select throws_ok('select * from public.clientes', '42501', null,
  'service_role no puede leer clientes (sin decisión aprobada)');
select throws_ok(
  $$insert into public.clientes (empresa_id, nombre, telefono, estado_validacion, creado_por)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'SR', '1', 'pendiente',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'service_role no puede insertar');
select throws_ok(
  $$update public.clientes set nombre = 'SR' where true$$,
  '42501', null, 'service_role no puede actualizar');
select throws_ok($$delete from public.clientes$$,
  '42501', null, 'service_role no puede borrar');
select throws_ok($$select public.crear_cliente('SR', '1')$$,
  '42501', null, 'service_role no puede ejecutar crear_cliente');
select throws_ok(
  $$select public.validar_cliente('aaaaaaaa-0000-4000-8000-00000000c002')$$,
  '42501', null, 'service_role no puede ejecutar validar_cliente');

reset role;

select results_eq(
  $$select count(*)::int, md5(string_agg(c::text, '|' order by c.id))
      from public.clientes c$$,
  $$select filas, clientes from huella_service_role$$,
  'los intentos de service_role no modificaron la tabla');

select * from finish();

rollback;
