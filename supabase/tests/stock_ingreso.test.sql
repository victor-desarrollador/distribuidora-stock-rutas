-- pgTAP: Etapa 2 — Stock, slice «stock-ingreso» (Blueprint §7.4, §7.9, §8,
-- §9, §10, §12 Stock; ADR-001 Topología D, P11, O-3 y §18.3 dominio Stock).
-- Ejecutar sólo en local: `supabase test db`.
--
-- Empresas B y C son fixtures adversariales (aislamiento y empresa sin
-- depósito), no un producto multiempresa.

begin;

create extension if not exists pgtap with schema extensions;

select plan(120);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-0000-4000-8000-000000000000', 'Empresa A (test)'),
  ('bbbbbbbb-0000-4000-8000-000000000000', 'Empresa B (test)'),
  ('cccccccc-0000-4000-8000-000000000000', 'Empresa C sin depósito (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'stk.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'stk.a2@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'stk.a3@usuarios.distribuidora.invalid',
   '{"rol":"dueno","empresa_id":"bbbbbbbb-0000-4000-8000-000000000000"}'),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'stk.a4@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'stk.b1@usuarios.distribuidora.invalid', '{}'),
  ('cccccccc-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'stk.c1@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'stk.n1@usuarios.distribuidora.invalid',
   '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000000', 'stk.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000000', 'stk.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000000', 'stk.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000000', 'stk.a4', 'A4', 'dueno', false),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000000', 'stk.b1', 'B1', 'dueno', true),
  ('cccccccc-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000000', 'stk.c1', 'C1', 'dueno', true);

-- Ubicaciones fijas de A y B (bootstrap D1); C a propósito sin depósito.
insert into public.ubicaciones (id, empresa_id, tipo) values
  ('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000000', 'deposito'),
  ('aaaaaaaa-0000-4000-8000-0000000000d2', 'aaaaaaaa-0000-4000-8000-000000000000', 'cuarentena'),
  ('bbbbbbbb-0000-4000-8000-0000000000d1', 'bbbbbbbb-0000-4000-8000-000000000000', 'deposito'),
  ('cccccccc-0000-4000-8000-0000000000d2', 'cccccccc-0000-4000-8000-000000000000', 'cuarentena');

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('aaaaaaaa-0000-4000-8000-0000000000f1', 'aaaaaaaa-0000-4000-8000-000000000000', 'A-1', 'Leche A', 'lacteos', 'unidad', 100, true,
   'aaaaaaaa-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-0000000000f2', 'aaaaaaaa-0000-4000-8000-000000000000', 'A-2', 'Jamón A', 'fiambres', 'peso', 2000, true,
   'aaaaaaaa-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-0000000000f3', 'aaaaaaaa-0000-4000-8000-000000000000', 'A-3', 'Inactivo A', 'lacteos', 'unidad', 1, false,
   'aaaaaaaa-0000-4000-8000-000000000001'),
  ('bbbbbbbb-0000-4000-8000-0000000000f1', 'bbbbbbbb-0000-4000-8000-000000000000', 'B-1', 'Leche B', 'lacteos', 'unidad', 100, true,
   'bbbbbbbb-0000-4000-8000-000000000001'),
  ('cccccccc-0000-4000-8000-0000000000f1', 'cccccccc-0000-4000-8000-000000000000', 'C-1', 'Leche C', 'lacteos', 'unidad', 100, true,
   'cccccccc-0000-4000-8000-000000000001');

create function pg_temp.como_usuario(uid uuid, metadata jsonb default '{}')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated', 'user_metadata', metadata)::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.como_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
end $$;

-- Huella v1 esperada, calculada de forma independiente de la implementación.
create function pg_temp.huella_v1(p uuid, c integer, m text)
returns text language sql immutable as $$
  select encode(sha256(convert_to(
    'v1|ingreso|' || p::text || '|' || c::text || '|'
      || case when m is null then '-' else '+' || m end, 'UTF8')), 'hex')
$$;

grant execute on function pg_temp.como_usuario(uuid, jsonb) to public;
grant execute on function pg_temp.como_anon() to public;
grant execute on function pg_temp.huella_v1(uuid, integer, text) to public;

create temp table ops (clave text, id uuid);
grant select, insert on ops to public;

create temp table conteos as select 0 as ops, 0 as movs;
grant select, update on conteos to public;

-- ---------------------------------------------------------------------------
-- Catálogo
-- ---------------------------------------------------------------------------
select has_table('public', 'operaciones', 'existe public.operaciones');
select has_table('public', 'movimientos_stock', 'existe public.movimientos_stock');
select has_view('public', 'stock_actual', 'existe la vista public.stock_actual');

select is(
  array(select a.attname::text || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text
               || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-')
          from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
         where a.attrelid = 'public.operaciones'::regclass and a.attnum > 0 and not a.attisdropped
         order by a.attnum),
  array['id:uuid:true:gen_random_uuid()', 'empresa_id:uuid:true:-', 'actor_id:uuid:true:-',
        'tipo:text:true:-', 'idempotency_key:uuid:true:-', 'huella:text:true:-',
        'creado_en:timestamp with time zone:true:now()', 'jornada_id:uuid:false:-'],
  'operaciones: columnas, tipos, NOT NULL y defaults aprobados (jornada_id nullable, D-1)');

select is(
  array(select a.attname::text || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text
               || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-')
          from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
         where a.attrelid = 'public.movimientos_stock'::regclass and a.attnum > 0 and not a.attisdropped
         order by a.attnum),
  array['id:uuid:true:gen_random_uuid()', 'empresa_id:uuid:true:-', 'operacion_id:uuid:true:-',
        'tipo_movimiento:text:true:-', 'producto_id:uuid:true:-', 'cantidad:integer:true:-',
        'ubicacion_origen_id:uuid:false:-', 'ubicacion_destino_id:uuid:false:-',
        'actor_id:uuid:true:-', 'motivo:text:false:-',
        'creado_en:timestamp with time zone:true:now()', 'motivo_codigo:text:false:-',
        'jornada_id:uuid:false:-'],
  'movimientos_stock: columnas, tipos, NOT NULL y defaults aprobados (jornada_id nullable, D-1)');

select is(
  (select count(*)::int from pg_attribute
    where attrelid in ('public.operaciones'::regclass, 'public.movimientos_stock'::regclass)
      and not attisdropped
      and attname in ('saldo_actual', 'resultado', 'importe')),
  0,
  'sin saldo_actual, resultado (E8) ni importe');

-- E13 (ADR-001 §18.4.1, D-1): jornada_id se agrega con FK real; los tipos de
-- Stock siguen sin jornada (CHECK ..._jornada_por_tipo, probado en
-- jornadas_esquema.test.sql). Aserción positiva que reemplaza la prohibición.
select is(
  array(select c.relname::text || '.' || a.attname::text || ':'
               || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text
               || ':' || (a.atthasdef)::text
          from pg_attribute a join pg_class c on c.oid = a.attrelid
         where a.attrelid in ('public.operaciones'::regclass, 'public.movimientos_stock'::regclass)
           and a.attname = 'jornada_id' and not a.attisdropped
         order by 1),
  array['movimientos_stock.jornada_id:uuid:false:false', 'operaciones.jornada_id:uuid:false:false'],
  'E13 (D-1): jornada_id existe en operaciones y movimientos_stock como uuid nullable y sin default');

select is(
  array(select a.attname::text || ':' || format_type(a.atttypid, a.atttypmod)
          from pg_attribute a
         where a.attrelid = 'public.stock_actual'::regclass and a.attnum > 0 and not a.attisdropped
         order by a.attnum),
  array['empresa_id:uuid', 'ubicacion_id:uuid', 'producto_id:uuid', 'cantidad:bigint'],
  'stock_actual: columnas y cantidad bigint');

select is(
  array(select conname::text || ':' || pg_get_constraintdef(oid) from pg_constraint
         where conrelid = 'public.operaciones'::regclass order by conname::text),
  array['operaciones_actor_fk:FOREIGN KEY (empresa_id, actor_id) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT',
        'operaciones_empresa_id_fkey:FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE RESTRICT',
        'operaciones_empresa_id_unico:UNIQUE (empresa_id, id)',
        'operaciones_huella_sha256:CHECK ((huella ~ ''^[0-9a-f]{64}$''::text))',
        'operaciones_idempotencia_unica:UNIQUE (empresa_id, actor_id, idempotency_key)',
        'operaciones_jornada_fk:FOREIGN KEY (empresa_id, jornada_id) REFERENCES jornadas(empresa_id, id) ON DELETE RESTRICT',
        'operaciones_jornada_por_tipo:CHECK ((((tipo = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text, ''apertura_jornada''::text])) AND (jornada_id IS NULL)) OR ((tipo = ANY (ARRAY[''reasignacion_vendedor''::text, ''correccion_jornada''::text, ''carga''::text, ''descarga''::text, ''salida_jornada''::text])) AND (jornada_id IS NOT NULL))))',
        'operaciones_pkey:PRIMARY KEY (id)',
        'operaciones_referencia_apertura:UNIQUE (empresa_id, id, tipo, actor_id)',
        'operaciones_referencia_unica:UNIQUE (empresa_id, id, tipo, actor_id, jornada_id)',
        'operaciones_tipo_valido:CHECK ((tipo = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text, ''apertura_jornada''::text, ''reasignacion_vendedor''::text, ''correccion_jornada''::text, ''carga''::text, ''descarga''::text, ''salida_jornada''::text])))'],
  'operaciones: constraints exactas (FK compuesta al actor, UNIQUE de idempotencia sin tipo, CHECK de tipo y huella)');

select is(
  array(select conname::text || ':' || pg_get_constraintdef(oid) from pg_constraint
         where conrelid = 'public.movimientos_stock'::regclass order by conname::text),
  array['movimientos_stock_actor_fk:FOREIGN KEY (empresa_id, actor_id) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT',
        'movimientos_stock_cantidad_positiva:CHECK ((cantidad > 0))',
        'movimientos_stock_destino_fk:FOREIGN KEY (empresa_id, ubicacion_destino_id) REFERENCES ubicaciones(empresa_id, id) ON DELETE RESTRICT',
        'movimientos_stock_empresa_id_fkey:FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE RESTRICT',
        'movimientos_stock_empresa_id_unico:UNIQUE (empresa_id, id)',
        'movimientos_stock_extremo_requerido:CHECK (((ubicacion_origen_id IS NOT NULL) OR (ubicacion_destino_id IS NOT NULL)))',
        'movimientos_stock_extremos_distintos:CHECK ((ubicacion_origen_id IS DISTINCT FROM ubicacion_destino_id))',
        'movimientos_stock_forma_por_tipo:CHECK ((((tipo_movimiento = ''ingreso''::text) AND (ubicacion_origen_id IS NULL) AND (ubicacion_destino_id IS NOT NULL)) OR ((tipo_movimiento = ''a_cuarentena''::text) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NOT NULL)) OR ((tipo_movimiento = ''merma''::text) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NULL)) OR ((tipo_movimiento = ANY (ARRAY[''carga''::text, ''descarga''::text])) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NOT NULL))))',
        'movimientos_stock_jornada_fk:FOREIGN KEY (empresa_id, jornada_id) REFERENCES jornadas(empresa_id, id) ON DELETE RESTRICT',
        'movimientos_stock_jornada_por_tipo:CHECK ((((tipo_movimiento = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text])) AND (jornada_id IS NULL)) OR ((tipo_movimiento = ANY (ARRAY[''carga''::text, ''descarga''::text])) AND (jornada_id IS NOT NULL))))',
        'movimientos_stock_motivo_codigo_valido:CHECK (((motivo_codigo IS NULL) OR (motivo_codigo = ANY (ARRAY[''vencido''::text, ''roto_danado''::text, ''mal_estado''::text, ''error_pedido''::text, ''cambio''::text, ''otro''::text]))))',
        'movimientos_stock_motivo_normalizado:CHECK (((motivo IS NULL) OR ((motivo = btrim(motivo)) AND (length(motivo) > 0))))',
        'movimientos_stock_motivo_por_tipo:CHECK ((((tipo_movimiento = ''ingreso''::text) AND (motivo_codigo IS NULL)) OR ((tipo_movimiento = ''a_cuarentena''::text) AND (motivo_codigo IS NULL) AND (motivo IS NOT NULL)) OR ((tipo_movimiento = ''merma''::text) AND (motivo_codigo IS NOT NULL) AND ((motivo_codigo <> ''otro''::text) OR (motivo IS NOT NULL))) OR ((tipo_movimiento = ''carga''::text) AND (motivo_codigo IS NULL) AND (motivo IS NULL)) OR ((tipo_movimiento = ''descarga''::text) AND (motivo_codigo IS NULL) AND (motivo IS NOT NULL))))',
        'movimientos_stock_operacion_fk:FOREIGN KEY (empresa_id, operacion_id) REFERENCES operaciones(empresa_id, id) ON DELETE RESTRICT',
        'movimientos_stock_operacion_referencia_fk:FOREIGN KEY (empresa_id, operacion_id, tipo_movimiento, actor_id, jornada_id) REFERENCES operaciones(empresa_id, id, tipo, actor_id, jornada_id) ON DELETE RESTRICT',
        'movimientos_stock_origen_fk:FOREIGN KEY (empresa_id, ubicacion_origen_id) REFERENCES ubicaciones(empresa_id, id) ON DELETE RESTRICT',
        'movimientos_stock_pkey:PRIMARY KEY (id)',
        'movimientos_stock_producto_fk:FOREIGN KEY (empresa_id, producto_id) REFERENCES productos(empresa_id, id) ON DELETE RESTRICT',
        'movimientos_stock_tipo_valido:CHECK ((tipo_movimiento = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text, ''carga''::text, ''descarga''::text])))'],
  'movimientos_stock: constraints exactas (FK compuestas a operación, producto, ubicaciones y actor; CHECK de cantidad, extremos, tipo, forma y motivo)');

select is(
  array(select pg_get_indexdef(i.indexrelid) from pg_index i
         where i.indrelid = 'public.movimientos_stock'::regclass and not i.indisunique
         order by 1),
  array['CREATE INDEX movimientos_stock_destino_idx ON public.movimientos_stock USING btree (empresa_id, ubicacion_destino_id, producto_id)',
        'CREATE INDEX movimientos_stock_jornada_idx ON public.movimientos_stock USING btree (empresa_id, jornada_id) WHERE (jornada_id IS NOT NULL)',
        'CREATE INDEX movimientos_stock_origen_idx ON public.movimientos_stock USING btree (empresa_id, ubicacion_origen_id, producto_id)'],
  'movimientos_stock: índices por destino, por origen y por jornada (D-1)');

select is(
  (select string_agg(c.relname || ':' || c.relowner::regrole::text, ',' order by c.relname)
     from pg_class c
    where c.oid in ('public.operaciones'::regclass, 'public.movimientos_stock'::regclass,
                    'public.stock_actual'::regclass)),
  'movimientos_stock:postgres,operaciones:postgres,stock_actual:postgres',
  'tablas y vista del owner de migraciones (no de propietario_rpc)');

select ok(
  (select bool_and(relrowsecurity and not relforcerowsecurity) from pg_class
    where oid in ('public.operaciones'::regclass, 'public.movimientos_stock'::regclass)),
  'RLS habilitada y sin FORCE en operaciones y movimientos_stock');

select is(
  array(select tablename || '.' || policyname || ':' || cmd || ':' || array_to_string(roles, ',')
          from pg_policies where schemaname = 'public' and tablename in ('operaciones', 'movimientos_stock')
         order by 1),
  array['movimientos_stock.movimientos_stock_insert_propietario_rpc:INSERT:propietario_rpc',
        'movimientos_stock.movimientos_stock_select_empresa:SELECT:authenticated',
        'movimientos_stock.movimientos_stock_select_propietario_rpc:SELECT:propietario_rpc',
        'operaciones.operaciones_insert_propietario_rpc:INSERT:propietario_rpc',
        'operaciones.operaciones_select_empresa:SELECT:authenticated',
        'operaciones.operaciones_select_propietario_rpc:SELECT:propietario_rpc'],
  'policies exactas; sin UPDATE ni DELETE (append-only, E14)');

select ok(
  (select bool_and(has_table_privilege('authenticated', c, 'SELECT')
                   and not has_table_privilege('authenticated', c,
                         'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
                   and not has_any_column_privilege('authenticated', c, 'INSERT, UPDATE, REFERENCES'))
     from unnest(array['public.operaciones'::regclass, 'public.movimientos_stock'::regclass,
                       'public.stock_actual'::regclass]) c),
  'authenticated: sólo SELECT en operaciones, movimientos_stock y stock_actual');

select ok(
  (select bool_and(not has_table_privilege(r, c,
                         'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
                   and not has_any_column_privilege(r, c, 'SELECT, INSERT, UPDATE, REFERENCES'))
     from unnest(array['anon', 'service_role']) r,
          unnest(array['public.operaciones'::regclass, 'public.movimientos_stock'::regclass,
                       'public.stock_actual'::regclass]) c),
  'anon y service_role: ningún privilegio (P11, sin excepción nueva)');

select ok(
  not exists (select 1 from pg_class c, aclexplode(c.relacl) a
               where c.oid in ('public.operaciones'::regclass, 'public.movimientos_stock'::regclass,
                               'public.stock_actual'::regclass)
                 and a.grantee = 0),
  'PUBLIC sin privilegios');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.operaciones'::regclass and a.attnum > 0 and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.operaciones', a.attname, 'INSERT')
         order by 1),
  array['actor_id', 'empresa_id', 'huella', 'idempotency_key', 'jornada_id', 'tipo'],
  'propietario_rpc inserta en operaciones sólo las columnas del alta');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.movimientos_stock'::regclass and a.attnum > 0 and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.movimientos_stock', a.attname, 'INSERT')
         order by 1),
  array['actor_id', 'cantidad', 'empresa_id', 'jornada_id', 'motivo', 'motivo_codigo', 'operacion_id', 'producto_id',
        'tipo_movimiento', 'ubicacion_destino_id', 'ubicacion_origen_id'],
  'propietario_rpc inserta en movimientos_stock sólo las columnas del alta');

select ok(
  (select bool_and(has_table_privilege('propietario_rpc', c, 'SELECT')
                   and not has_table_privilege('propietario_rpc', c,
                         'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
                   and not has_any_column_privilege('propietario_rpc', c, 'UPDATE, REFERENCES'))
     from unnest(array['public.operaciones'::regclass, 'public.movimientos_stock'::regclass]) c),
  'propietario_rpc: sin UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ni MAINTAIN');

select ok(
  (select reloptions @> array['security_invoker=true'] from pg_class
    where oid = 'public.stock_actual'::regclass),
  'stock_actual es security_invoker (aplica la RLS de quien consulta)');

select is(
  (select p.prosecdef::text || '|' || p.proowner::regrole::text || '|' || array_to_string(p.proconfig, ',')
          || '|' || p.provolatile::text || '|'
          || array_to_string(array(select a::text from unnest(p.proacl) a order by 1), ',')
     from pg_proc p where p.oid = 'public.registrar_ingreso(uuid,uuid,integer,text)'::regprocedure),
  'false|postgres|search_path=""|v|authenticated=X/postgres,postgres=X/postgres',
  'fachada: SECURITY INVOKER, de postgres, search_path vacío, VOLATILE, EXECUTE sólo authenticated');

select is(
  (select p.prosecdef::text || '|' || p.proowner::regrole::text || '|' || array_to_string(p.proconfig, ',')
          || '|' || p.provolatile::text || '|'
          || array_to_string(array(select a::text from unnest(p.proacl) a order by 1), ',')
     from pg_proc p where p.oid = 'privado.registrar_ingreso(uuid,uuid,integer,text)'::regprocedure),
  'true|propietario_rpc|search_path=""|v|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc',
  'implementación: SECURITY DEFINER, de propietario_rpc, search_path vacío, VOLATILE, ACL de Topología D');

select is(
  (select count(*)::int from pg_proc
    where proname = 'registrar_ingreso'
      and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)),
  2,
  'sin sobrecargas de registrar_ingreso (E15)');

select ok(
  not has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
  and not has_schema_privilege('anon', 'privado', 'USAGE'),
  'propietario_rpc sin CREATE sobre privado y anon sin USAGE');

select is(
  (select count(*)::int from pg_proc p
    where p.proname = 'registrar_ingreso'
      and (p.proargnames && array['p_empresa_id', 'p_ubicacion_id', 'p_ubicacion_destino_id',
                                  'p_actor_id', 'p_tipo', 'p_huella'])),
  0,
  'el cliente no envía empresa, ubicación, actor, tipo ni huella');

-- ---------------------------------------------------------------------------
-- Ingreso correcto: dueño y encargado
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into ops select 'dueno', public.registrar_ingreso(
      '11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 10, '  Compra inicial  ')$$,
  'el dueño registra un ingreso');
reset role;

select results_eq(
  $$select o.empresa_id, o.actor_id, o.tipo, o.idempotency_key
      from public.operaciones o join ops x on x.id = o.id where x.clave = 'dueno'$$,
  $$values ('aaaaaaaa-0000-4000-8000-000000000000'::uuid, 'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
            'ingreso', '11111111-0000-4000-8000-000000000001'::uuid)$$,
  'la operación toma empresa y actor del servidor');

select results_eq(
  $$select m.empresa_id, m.tipo_movimiento, m.producto_id, m.cantidad, m.ubicacion_origen_id,
           m.ubicacion_destino_id, m.actor_id, m.motivo, count(*) over ()::int
      from public.movimientos_stock m join ops x on x.id = m.operacion_id where x.clave = 'dueno'$$,
  $$values ('aaaaaaaa-0000-4000-8000-000000000000'::uuid, 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1'::uuid, 10, null::uuid,
            'aaaaaaaa-0000-4000-8000-0000000000d1'::uuid,
            'aaaaaaaa-0000-4000-8000-000000000001'::uuid, 'Compra inicial', 1)$$,
  'exactamente un movimiento: exterior → depósito del servidor, actor y empresa reales, motivo con trim');

select is(
  (select o.huella from public.operaciones o join ops x on x.id = o.id where x.clave = 'dueno'),
  pg_temp.huella_v1('aaaaaaaa-0000-4000-8000-0000000000f1', 10, 'Compra inicial'),
  'huella v1 exacta: sha256(''v1|ingreso|<producto>|<cantidad>|+<motivo normalizado>'')');

select is(
  (select o.huella from public.operaciones o join ops x on x.id = o.id where x.clave = 'dueno'),
  encode(sha256(convert_to('v1|ingreso|aaaaaaaa-0000-4000-8000-0000000000f1|10|+Compra inicial', 'UTF8')), 'hex'),
  'huella v1 contra el literal canónico completo');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$insert into ops select 'encargado', public.registrar_ingreso(
      '22222222-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 5, '   ')$$,
  'el encargado registra un ingreso (motivo de espacios)');
reset role;

select is(
  (select m.motivo from public.movimientos_stock m join ops x on x.id = m.operacion_id where x.clave = 'encargado'),
  null::text,
  'motivo vacío o de espacios se guarda NULL');

select is(
  (select o.huella from public.operaciones o join ops x on x.id = o.id where x.clave = 'encargado'),
  pg_temp.huella_v1('aaaaaaaa-0000-4000-8000-0000000000f1', 5, null),
  'huella v1 con motivo NULL usa la marca ''-''');

select isnt(pg_temp.huella_v1('aaaaaaaa-0000-4000-8000-0000000000f1', 5, null),
            pg_temp.huella_v1('aaaaaaaa-0000-4000-8000-0000000000f1', 5, '-'),
  'huella v1 distingue motivo NULL del texto ''-''');

select ok(
  pg_temp.huella_v1('aaaaaaaa-0000-4000-8000-0000000000f1', 10, 'X')
    <> pg_temp.huella_v1('aaaaaaaa-0000-4000-8000-0000000000f1', 11, 'X')
  and pg_temp.huella_v1('aaaaaaaa-0000-4000-8000-0000000000f1', 10, 'X')
    <> pg_temp.huella_v1('aaaaaaaa-0000-4000-8000-0000000000f2', 10, 'X')
  and pg_temp.huella_v1('aaaaaaaa-0000-4000-8000-0000000000f1', 10, 'X')
    <> pg_temp.huella_v1('aaaaaaaa-0000-4000-8000-0000000000f1', 10, 'Y'),
  'cambiar cantidad, producto o motivo cambia la huella');

-- ---------------------------------------------------------------------------
-- Stock derivado
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select results_eq(
  $$select ubicacion_id, producto_id, cantidad from public.stock_actual order by 1, 2$$,
  $$values ('aaaaaaaa-0000-4000-8000-0000000000d1'::uuid, 'aaaaaaaa-0000-4000-8000-0000000000f1'::uuid, 15::bigint)$$,
  'el dueño ve el depósito con 10 + 5 = 15');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select is((select cantidad from public.stock_actual
            where producto_id = 'aaaaaaaa-0000-4000-8000-0000000000f1'), 15::bigint,
  'el encargado ve el mismo saldo');
reset role;
select is(
  (select cantidad from public.stock_actual
    where ubicacion_id = 'aaaaaaaa-0000-4000-8000-0000000000d1'
      and producto_id = 'aaaaaaaa-0000-4000-8000-0000000000f1'),
  (select sum(case when ubicacion_destino_id = 'aaaaaaaa-0000-4000-8000-0000000000d1' then cantidad else 0 end)
          - sum(case when ubicacion_origen_id = 'aaaaaaaa-0000-4000-8000-0000000000d1' then cantidad else 0 end)
     from public.movimientos_stock where producto_id = 'aaaaaaaa-0000-4000-8000-0000000000f1'),
  'el saldo de la vista coincide con la suma del ledger (Blueprint §12)');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003',
  '{"rol":"dueno","empresa_id":"bbbbbbbb-0000-4000-8000-000000000000"}');
select is((select count(*)::int from public.stock_actual), 0, 'el vendedor no ve stock (E4)');
select is((select count(*)::int from public.movimientos_stock), 0, 'el vendedor no ve movimientos');
select is((select count(*)::int from public.operaciones), 0, 'el vendedor no ve operaciones');
select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select is((select count(*)::int from public.stock_actual where empresa_id = 'aaaaaaaa-0000-4000-8000-000000000000'), 0,
  'el dueño de B no ve stock de A');
select is((select count(*)::int from public.movimientos_stock), 0, 'el dueño de B no ve movimientos de A');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000004');
select is((select count(*)::int from public.stock_actual), 0, 'un perfil inactivo no ve stock');
select pg_temp.como_usuario('dddddddd-0000-4000-8000-000000000001',
  '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');
select is((select count(*)::int from public.operaciones), 0, 'una cuenta sin perfil no ve operaciones aunque su metadata diga dueño de A');
select pg_temp.como_anon();
select throws_ok('select count(*) from public.stock_actual', '42501', null, 'anon no lee stock_actual');
reset role;

-- ---------------------------------------------------------------------------
-- Autorización y validaciones (sin efectos)
-- ---------------------------------------------------------------------------
update conteos set ops = (select count(*) from public.operaciones), movs = (select count(*) from public.movimientos_stock);

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003',
  '{"rol":"dueno","empresa_id":"bbbbbbbb-0000-4000-8000-000000000000"}');
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 1)$$,
  'PT403', 'stock_no_autorizado', 'el vendedor no registra ingresos (metadata de dueño ignorada)');
select throws_ok(
  $$select privado.registrar_ingreso('33333333-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-0000000000f1', 1)$$,
  'PT403', 'stock_no_autorizado', 'la implementación privada llamada por SQL también rechaza al vendedor');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000004');
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-0000000000f1', 1)$$,
  'PT403', 'stock_no_autorizado', 'un dueño inactivo no registra ingresos');
select pg_temp.como_usuario('dddddddd-0000-4000-8000-000000000001',
  '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-0000000000f1', 1)$$,
  'PT403', 'stock_no_autorizado', 'una cuenta sin perfil no registra ingresos');
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-0000000000f1', 1)$$,
  'PT401', 'stock_no_autenticado', 'sin sub en el JWT: no autenticado');
select pg_temp.como_anon();
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000006', 'aaaaaaaa-0000-4000-8000-0000000000f1', 1)$$,
  '42501', null, 'anon no puede ejecutar registrar_ingreso');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000007', 'bbbbbbbb-0000-4000-8000-0000000000f1', 1)$$,
  'PT404', 'stock_producto_no_encontrado', 'un producto de otra empresa responde como inexistente');
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000008', 'eeeeeeee-0000-4000-8000-0000000000f1', 1)$$,
  'PT404', 'stock_producto_no_encontrado', 'un producto inexistente');
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000009', null, 1)$$,
  'PT404', 'stock_producto_no_encontrado', 'un producto NULL');
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000010', 'aaaaaaaa-0000-4000-8000-0000000000f3', 1)$$,
  'PT409', 'stock_producto_inactivo', 'un producto inactivo');
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000011', 'aaaaaaaa-0000-4000-8000-0000000000f1', 0)$$,
  'PT400', 'stock_cantidad_invalida', 'cantidad 0');
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000012', 'aaaaaaaa-0000-4000-8000-0000000000f1', -3)$$,
  'PT400', 'stock_cantidad_invalida', 'cantidad negativa');
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000013', 'aaaaaaaa-0000-4000-8000-0000000000f1', null)$$,
  'PT400', 'stock_cantidad_invalida', 'cantidad NULL');
select throws_ok(
  $$select public.registrar_ingreso(null, 'aaaaaaaa-0000-4000-8000-0000000000f1', 1)$$,
  'PT400', 'stock_clave_invalida', 'idempotency_key NULL');
select pg_temp.como_usuario('cccccccc-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.registrar_ingreso('33333333-0000-4000-8000-000000000014', 'cccccccc-0000-4000-8000-0000000000f1', 1)$$,
  'PT500', 'stock_ubicacion_no_configurada', 'una empresa sin depósito falla cerrado');
reset role;

select results_eq(
  $$select (select count(*)::int from public.operaciones), (select count(*)::int from public.movimientos_stock)$$,
  $$select ops, movs from conteos$$,
  'ningún rechazo dejó operaciones ni movimientos (sin reserva ni huérfanos)');

-- Un rechazo de negocio no deja reserva: la misma clave sirve después.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into ops select 'tras_rechazo', public.registrar_ingreso(
      '33333333-0000-4000-8000-000000000010', 'aaaaaaaa-0000-4000-8000-0000000000f2', 4)$$,
  'la clave de un rechazo previo (producto inactivo) se usa luego con otro payload');
reset role;

-- ---------------------------------------------------------------------------
-- Idempotencia
-- ---------------------------------------------------------------------------
update conteos set ops = (select count(*) from public.operaciones), movs = (select count(*) from public.movimientos_stock);

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select is(
  public.registrar_ingreso('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 10, '  Compra inicial  '),
  (select id from ops where clave = 'dueno'),
  'misma clave y mismo payload: el mismo operaciones.id');
select is(
  public.registrar_ingreso('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 10, 'Compra inicial'),
  (select id from ops where clave = 'dueno'),
  'el payload se normaliza antes de la huella: motivo con o sin espacios es el mismo pedido');
select throws_ok(
  $$select public.registrar_ingreso('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 11, 'Compra inicial')$$,
  'PT409', 'stock_conflicto_idempotencia', 'misma clave y otra cantidad');
select throws_ok(
  $$select public.registrar_ingreso('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f2', 10, 'Compra inicial')$$,
  'PT409', 'stock_conflicto_idempotencia', 'misma clave y otro producto');
select throws_ok(
  $$select public.registrar_ingreso('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 10, 'Otro motivo')$$,
  'PT409', 'stock_conflicto_idempotencia', 'misma clave y otro motivo');
select throws_ok(
  $$select public.registrar_ingreso('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 10)$$,
  'PT409', 'stock_conflicto_idempotencia', 'misma clave y motivo NULL en lugar de texto');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.cambiar_estado_producto('aaaaaaaa-0000-4000-8000-0000000000f1', false)$$,
  'se desactiva el producto del ingreso original');
select is(
  public.registrar_ingreso('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 10, 'Compra inicial'),
  (select id from ops where clave = 'dueno'),
  'un replay válido devuelve el resultado original aunque el producto se haya desactivado');
select throws_ok(
  $$select public.registrar_ingreso('11111111-0000-4000-8000-000000000099', 'aaaaaaaa-0000-4000-8000-0000000000f1', 10)$$,
  'PT409', 'stock_producto_inactivo', 'pero un pedido nuevo con el producto inactivo se rechaza');
select lives_ok(
  $$select public.cambiar_estado_producto('aaaaaaaa-0000-4000-8000-0000000000f1', true)$$,
  'se reactiva el producto');
reset role;

select results_eq(
  $$select (select count(*)::int from public.operaciones), (select count(*)::int from public.movimientos_stock),
           (select cantidad from public.stock_actual
             where ubicacion_id = 'aaaaaaaa-0000-4000-8000-0000000000d1'
               and producto_id = 'aaaaaaaa-0000-4000-8000-0000000000f1')$$,
  $$select ops, movs, 15::bigint from conteos$$,
  'los replays y conflictos no crearon operaciones ni movimientos, y el saldo no se duplicó');

select is(
  (select count(*)::int from public.operaciones
    where idempotency_key = '11111111-0000-4000-8000-000000000001'),
  1,
  'la clave tiene exactamente una operación');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select lives_ok(
  $$insert into ops select 'otra_persona', public.registrar_ingreso(
      '11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 10, 'Compra inicial')$$,
  'otro actor puede usar la misma UUID de clave (alcance por actor, E5)');
reset role;
select isnt((select id from ops where clave = 'otra_persona'), (select id from ops where clave = 'dueno'),
  'y obtiene una operación distinta');

-- ---------------------------------------------------------------------------
-- Ledger append-only y escritura directa
-- ---------------------------------------------------------------------------
-- Una operación de A sin movimiento (como owner), para probar la FK compuesta
-- de producto sin que intervenga el índice único de operaciones unitarias.
with o as (
  insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
  values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'ingreso',
          '55555555-0000-4000-8000-000000000001', repeat('c', 64))
  returning id)
insert into ops select 'sin_mov', id from o;

create temp table huella_ledger as
  select (select md5(string_agg(o::text, '|' order by o.id)) from public.operaciones o) as ops,
         (select md5(string_agg(m::text, '|' order by m.id)) from public.movimientos_stock m) as movs;
grant select on huella_ledger to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'dueno'), 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'el dueño no inserta movimientos directamente');
select throws_ok($$update public.movimientos_stock set cantidad = 999$$, '42501', null,
  'el dueño no actualiza el ledger');
select throws_ok($$delete from public.movimientos_stock$$, '42501', null, 'el dueño no borra el ledger');
select throws_ok($$truncate public.movimientos_stock$$, '42501', null, 'el dueño no trunca el ledger');
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'ingreso',
            gen_random_uuid(), repeat('a', 64))$$,
  '42501', null, 'el dueño no inserta operaciones directamente');
select throws_ok($$update public.operaciones set huella = repeat('b', 64)$$, '42501', null,
  'el dueño no actualiza operaciones');
select throws_ok($$delete from public.operaciones$$, '42501', null, 'el dueño no borra operaciones');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select throws_ok($$update public.movimientos_stock set cantidad = 1$$, '42501', null,
  'el encargado no actualiza el ledger');
select throws_ok($$delete from public.operaciones$$, '42501', null, 'el encargado no borra operaciones');
select pg_temp.como_anon();
select throws_ok('select count(*) from public.movimientos_stock', '42501', null, 'anon no lee el ledger');
select throws_ok($$delete from public.movimientos_stock$$, '42501', null, 'anon no borra el ledger');
reset role;

grant usage on schema extensions to service_role;
set local role service_role;
select throws_ok('select count(*) from public.movimientos_stock', '42501', null, 'service_role no lee el ledger (P11)');
select throws_ok('select count(*) from public.operaciones', '42501', null, 'service_role no lee operaciones');
select throws_ok('select count(*) from public.stock_actual', '42501', null, 'service_role no lee stock_actual');
select throws_ok($$delete from public.movimientos_stock$$, '42501', null, 'service_role no borra el ledger');
select throws_ok(
  $$select public.registrar_ingreso(gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-0000000000f1', 1)$$,
  '42501', null, 'service_role no ejecuta registrar_ingreso');
reset role;

-- propietario_rpc: limitado por grants y RLS (identidad de dueño A).
grant usage on schema extensions to propietario_rpc;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;
select throws_ok($$update public.movimientos_stock set cantidad = 1$$, '42501', null,
  'propietario_rpc no actualiza el ledger');
select throws_ok($$delete from public.movimientos_stock$$, '42501', null, 'propietario_rpc no borra el ledger');
select throws_ok($$truncate public.movimientos_stock$$, '42501', null, 'propietario_rpc no trunca el ledger');
select throws_ok($$update public.operaciones set tipo = 'ingreso'$$, '42501', null,
  'propietario_rpc no actualiza operaciones');
select throws_ok($$delete from public.operaciones$$, '42501', null, 'propietario_rpc no borra operaciones');

-- Cruces de empresa por escritura directa del rol técnico.
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values ('bbbbbbbb-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'ingreso',
            gen_random_uuid(), repeat('a', 64))$$,
  '42501', null, 'operación con actor de A en la empresa B: rechazada');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'sin_mov'), 'ingreso',
            'bbbbbbbb-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23503', null, 'movimiento de A con un producto de B: rechazado por la FK compuesta');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'dueno'), 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'bbbbbbbb-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'movimiento de A hacia una ubicación de B: rechazado por RLS (el ingreso exige un depósito propio, D8)');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'otra_persona'), 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'movimiento colgado de la operación de otro actor: rechazado por RLS');
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000003","role":"authenticated"}', true);
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000003', 'ingreso',
            gen_random_uuid(), repeat('a', 64))$$,
  '42501', null, 'propietario_rpc no crea operaciones en nombre de un vendedor');
reset role;

select results_eq(
  $$select (select md5(string_agg(o::text, '|' order by o.id)) from public.operaciones o),
           (select md5(string_agg(m::text, '|' order by m.id)) from public.movimientos_stock m)$$,
  $$select ops, movs from huella_ledger$$,
  'ningún intento directo cambió operaciones ni el ledger');

-- ---------------------------------------------------------------------------
-- Restricciones del ledger (como owner)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'dueno'), 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 0, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza cantidad 0');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'dueno'), 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza un movimiento sin origen ni destino');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'dueno'), 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'la tabla rechaza origen igual a destino');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'dueno'), 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d2',
            'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'un ingreso con origen se rechaza (forma por tipo)');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'dueno'), 'merma',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'una merma con destino se rechaza (forma por tipo)');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_destino_id, actor_id, motivo)
    values ('aaaaaaaa-0000-4000-8000-000000000000', (select id from ops where clave = 'dueno'), 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001', ' sin trim ')$$,
  '23514', null, 'la tabla rechaza un motivo sin normalizar');
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'venta',
            gen_random_uuid(), repeat('a', 64))$$,
  '23514', null, 'operaciones rechaza tipos no aprobados (venta)');
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'ingreso',
            gen_random_uuid(), repeat('A', 64))$$,
  '23514', null, 'operaciones rechaza una huella que no es SHA-256 hex en minúsculas');
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'ingreso',
            '11111111-0000-4000-8000-000000000001', repeat('a', 64))$$,
  '23505', null, 'la misma clave del mismo actor no se repite (UNIQUE de idempotencia)');

-- ---------------------------------------------------------------------------
-- Atomicidad: si falla el movimiento, no queda la operación
-- ---------------------------------------------------------------------------
update conteos set ops = (select count(*) from public.operaciones), movs = (select count(*) from public.movimientos_stock);
revoke insert (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
               ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo)
  on table public.movimientos_stock from propietario_rpc;
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.registrar_ingreso('44444444-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-0000000000f1', 7)$$,
  'PT500', 'stock_error_interno', 'si el movimiento falla, la RPC falla con error interno estable');
reset role;
grant insert (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
              ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo)
  on table public.movimientos_stock to propietario_rpc;
select results_eq(
  $$select (select count(*)::int from public.operaciones), (select count(*)::int from public.movimientos_stock),
           (select count(*)::int from public.operaciones where idempotency_key = '44444444-0000-4000-8000-000000000001')$$,
  $$select ops, movs, 0 from conteos$$,
  'sin operación huérfana ni movimiento: la reserva de la clave también se revirtió');
select is(
  (select cantidad from public.stock_actual
    where ubicacion_id = 'aaaaaaaa-0000-4000-8000-0000000000d1'
      and producto_id = 'aaaaaaaa-0000-4000-8000-0000000000f1'),
  25::bigint,
  'el saldo no cambió (15 + 10 del otro actor)');

-- Otra empresa registra en su propio depósito.
select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into ops select 'b', public.registrar_ingreso(
      '11111111-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-0000000000f1', 3)$$,
  'el dueño de B registra un ingreso en B');
reset role;
select results_eq(
  $$select m.empresa_id, m.ubicacion_destino_id from public.movimientos_stock m
      join ops x on x.id = m.operacion_id where x.clave = 'b'$$,
  $$values ('bbbbbbbb-0000-4000-8000-000000000000'::uuid, 'bbbbbbbb-0000-4000-8000-0000000000d1'::uuid)$$,
  'el ingreso de B va al depósito de B');

-- Una operación de B no puede ser colgada desde A (FK compuesta), ya con una operación real de B.
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_destino_id, actor_id)
    select 'aaaaaaaa-0000-4000-8000-000000000000', o.id, 'ingreso',
           'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1',
           'aaaaaaaa-0000-4000-8000-000000000001'
      from public.operaciones o where o.empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000' limit 1$$,
  '23503', null, 'movimiento de A colgado de una operación de B: rechazado por la FK compuesta (como owner)');

select * from finish();

rollback;
