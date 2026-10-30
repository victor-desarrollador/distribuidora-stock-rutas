-- pgTAP: D-1 — esquema de jornadas y carga (ADR-001 §18.4.1, §18.4.2, §18.4.8,
-- §18.4.9 grupos S y N aplicables sin RPC, §18.4.10; ADR-007 §2, §7 prueba 23).
-- Ejecutar sólo en local: `supabase test db`.
--
-- Cubre el esquema, las restricciones, los grants y las policies de
-- public.jornadas, public.reasignaciones_vendedor y public.correcciones_jornada
-- y la extensión de operaciones y movimientos_stock. NO cubre (requieren las
-- seis RPC, etapa posterior): las 24 pruebas normativas de ADR-007 §7, I1–I14,
-- K1–K12, P11/P12 ni los ítems de S «por cada una de las seis RPC».
--
-- Las empresas A y B son fixtures adversariales (aislamiento), no un producto
-- multiempresa.

begin;

create extension if not exists pgtap with schema extensions;

select plan(123);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-0000-4000-8000-000000000000', 'Empresa A (test)'),
  ('bbbbbbbb-0000-4000-8000-000000000000', 'Empresa B (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'jor.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'jor.a2@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'jor.a3@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'jor.a4@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'jor.a5@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'jor.b1@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'jor.b2@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000000', 'jor.a1', 'A1 dueño', 'dueno', true),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000000', 'jor.a2', 'A2 encargado', 'encargado', true),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000000', 'jor.a3', 'A3 vendedor de J1', 'vendedor_piloto', true),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000000', 'jor.a4', 'A4 dueño inactivo', 'dueno', false),
  ('aaaaaaaa-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000000', 'jor.a5', 'A5 vendedor de J2', 'vendedor_piloto', true),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000000', 'jor.b1', 'B1 dueño', 'dueno', true),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000000', 'jor.b2', 'B2 vendedor', 'vendedor_piloto', true);

insert into public.camiones (id, empresa_id, patente, nombre, creado_por) values
  ('aaaaaaaa-0000-4000-8000-0000000c0001', 'aaaaaaaa-0000-4000-8000-000000000000', 'AAA001', 'Camión A1', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-0000000c0002', 'aaaaaaaa-0000-4000-8000-000000000000', 'AAA002', 'Camión A2', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-0000000c0003', 'aaaaaaaa-0000-4000-8000-000000000000', 'AAA003', 'Camión A3', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('bbbbbbbb-0000-4000-8000-0000000c0001', 'bbbbbbbb-0000-4000-8000-000000000000', 'BBB001', 'Camión B1', 'bbbbbbbb-0000-4000-8000-000000000001');

insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000000', 'deposito', null),
  ('aaaaaaaa-0000-4000-8000-0000000000d2', 'aaaaaaaa-0000-4000-8000-000000000000', 'cuarentena', null),
  ('aaaaaaaa-0000-4000-8000-0000000e0001', 'aaaaaaaa-0000-4000-8000-000000000000', 'camion', 'aaaaaaaa-0000-4000-8000-0000000c0001'),
  ('aaaaaaaa-0000-4000-8000-0000000e0002', 'aaaaaaaa-0000-4000-8000-000000000000', 'camion', 'aaaaaaaa-0000-4000-8000-0000000c0002'),
  ('aaaaaaaa-0000-4000-8000-0000000e0003', 'aaaaaaaa-0000-4000-8000-000000000000', 'camion', 'aaaaaaaa-0000-4000-8000-0000000c0003'),
  ('bbbbbbbb-0000-4000-8000-0000000000d1', 'bbbbbbbb-0000-4000-8000-000000000000', 'deposito', null),
  ('bbbbbbbb-0000-4000-8000-0000000e0001', 'bbbbbbbb-0000-4000-8000-000000000000', 'camion', 'bbbbbbbb-0000-4000-8000-0000000c0001');

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('aaaaaaaa-0000-4000-8000-0000000000f1', 'aaaaaaaa-0000-4000-8000-000000000000', 'A-1', 'Leche A', 'lacteos', 'unidad', 100, true,
   'aaaaaaaa-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-0000000000f2', 'aaaaaaaa-0000-4000-8000-000000000000', 'A-2', 'Jamón A', 'fiambres', 'peso', 2000, true,
   'aaaaaaaa-0000-4000-8000-000000000001'),
  ('bbbbbbbb-0000-4000-8000-0000000000f1', 'bbbbbbbb-0000-4000-8000-000000000000', 'B-1', 'Leche B', 'lacteos', 'unidad', 100, true,
   'bbbbbbbb-0000-4000-8000-000000000001');

-- Operaciones de apertura (jornada_id NULL, CHECK jornada_por_tipo).
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella) values
  ('aaaaaaaa-0000-4000-8000-00000a000001', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'apertura_jornada', gen_random_uuid(), repeat('a', 64)),
  ('aaaaaaaa-0000-4000-8000-00000a000002', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'apertura_jornada', gen_random_uuid(), repeat('a', 64)),
  ('aaaaaaaa-0000-4000-8000-00000a000003', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'apertura_jornada', gen_random_uuid(), repeat('a', 64)),
  ('aaaaaaaa-0000-4000-8000-00000a000004', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000002', 'apertura_jornada', gen_random_uuid(), repeat('a', 64)),
  ('bbbbbbbb-0000-4000-8000-00000a000001', 'bbbbbbbb-0000-4000-8000-000000000000', 'bbbbbbbb-0000-4000-8000-000000000001', 'apertura_jornada', gen_random_uuid(), repeat('a', 64));

-- J1 (camión A1, vendedor A3), J2 (camión A2, vendedor A5) y JB (empresa B).
insert into public.jornadas (id, empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por,
                             operacion_apertura_id) values
  ('aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-000000000000', '2026-11-02',
   'aaaaaaaa-0000-4000-8000-0000000c0001', 'aaaaaaaa-0000-4000-8000-000000000003', 'abierta',
   'aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000a000001'),
  ('aaaaaaaa-0000-4000-8000-00000d000002', 'aaaaaaaa-0000-4000-8000-000000000000', '2026-11-02',
   'aaaaaaaa-0000-4000-8000-0000000c0002', 'aaaaaaaa-0000-4000-8000-000000000005', 'abierta',
   'aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000a000002'),
  ('bbbbbbbb-0000-4000-8000-00000d000001', 'bbbbbbbb-0000-4000-8000-000000000000', '2026-11-02',
   'bbbbbbbb-0000-4000-8000-0000000c0001', 'bbbbbbbb-0000-4000-8000-000000000002', 'abierta',
   'bbbbbbbb-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-00000a000001');

-- Operaciones de jornada sobre J1 (jornada_id NOT NULL) y una de Stock.
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id) values
  ('aaaaaaaa-0000-4000-8000-00000b000001', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'carga', gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001'),
  ('aaaaaaaa-0000-4000-8000-00000b000002', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'descarga', gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001'),
  ('aaaaaaaa-0000-4000-8000-00000b000004', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'reasignacion_vendedor', gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001'),
  ('aaaaaaaa-0000-4000-8000-00000b000005', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'correccion_jornada', gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001'),
  ('aaaaaaaa-0000-4000-8000-00000b000006', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'reasignacion_vendedor', gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001'),
  ('aaaaaaaa-0000-4000-8000-00000b000008', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'correccion_jornada', gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001'),
  ('aaaaaaaa-0000-4000-8000-00000b000009', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'carga', gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001');
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella) values
  ('aaaaaaaa-0000-4000-8000-00000b000007', 'aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'ingreso', gen_random_uuid(), repeat('a', 64));

create function pg_temp.como_usuario(uid uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.como_propietario(uid uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role propietario_rpc';
end $$;

create function pg_temp.como_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
end $$;

create function pg_temp.como_service()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
end $$;

-- Filas afectadas por un UPDATE (un WITH con DML no puede ir en una subconsulta).
create function pg_temp.filas_afectadas(consulta text)
returns integer language plpgsql as $$
declare n integer;
begin
  execute consulta;
  get diagnostics n = row_count;
  return n;
end $$;

grant execute on function pg_temp.filas_afectadas(text) to public;
grant execute on function pg_temp.como_usuario(uuid) to public;
grant execute on function pg_temp.como_propietario(uuid) to public;
grant execute on function pg_temp.como_anon() to public;
grant execute on function pg_temp.como_service() to public;

-- ===========================================================================
-- Catálogo (como owner)
-- ===========================================================================
select has_table('public', 'jornadas', 'existe public.jornadas');
select has_table('public', 'reasignaciones_vendedor', 'existe public.reasignaciones_vendedor');
select has_table('public', 'correcciones_jornada', 'existe public.correcciones_jornada');

select is(
  array(select a.attname::text || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text
               || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-')
          from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
         where a.attrelid = 'public.jornadas'::regclass and a.attnum > 0 and not a.attisdropped
         order by a.attnum),
  array['id:uuid:true:gen_random_uuid()', 'empresa_id:uuid:true:-', 'fecha:date:true:-',
        'camion_id:uuid:true:-', 'vendedor_id:uuid:true:-', 'estado:text:true:-',
        'abierta_por:uuid:true:-', 'operacion_apertura_id:uuid:true:-',
        'tipo_operacion_apertura:text:true:''apertura_jornada''::text',
        'creado_en:timestamp with time zone:true:now()'],
  'jornadas: columnas, tipos, NOT NULL y defaults aprobados (ADR-001 §18.4.1)');

select is(
  array(select a.attname::text || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text
               || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-')
          from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
         where a.attrelid = 'public.reasignaciones_vendedor'::regclass and a.attnum > 0 and not a.attisdropped
         order by a.attnum),
  array['id:uuid:true:gen_random_uuid()', 'empresa_id:uuid:true:-', 'jornada_id:uuid:true:-',
        'operacion_id:uuid:true:-',
        'tipo_operacion:text:true:''reasignacion_vendedor''::text',
        'vendedor_anterior_id:uuid:true:-', 'vendedor_nuevo_id:uuid:true:-', 'actor_id:uuid:true:-',
        'creado_en:timestamp with time zone:true:now()'],
  'reasignaciones_vendedor: columnas, tipos, NOT NULL y defaults aprobados');

select is(
  array(select a.attname::text || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text
               || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-')
          from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
         where a.attrelid = 'public.correcciones_jornada'::regclass and a.attnum > 0 and not a.attisdropped
         order by a.attnum),
  array['id:uuid:true:gen_random_uuid()', 'empresa_id:uuid:true:-', 'jornada_id:uuid:true:-',
        'operacion_id:uuid:true:-',
        'tipo_operacion:text:true:''correccion_jornada''::text',
        'fecha_anterior:date:true:-', 'fecha_nueva:date:true:-',
        'camion_anterior_id:uuid:true:-', 'camion_nuevo_id:uuid:true:-',
        'motivo:text:true:-', 'actor_id:uuid:true:-',
        'creado_en:timestamp with time zone:true:now()'],
  'correcciones_jornada: columnas, tipos, NOT NULL y defaults aprobados');

-- N1: toda columna de las tres tablas nuevas es NOT NULL.
select is(
  array(select c.relname::text || '.' || a.attname::text
          from pg_attribute a join pg_class c on c.oid = a.attrelid
         where a.attrelid in ('public.jornadas'::regclass, 'public.reasignaciones_vendedor'::regclass,
                              'public.correcciones_jornada'::regclass)
           and a.attnum > 0 and not a.attisdropped and not a.attnotnull
         order by 1),
  '{}'::text[],
  'N1: ninguna columna de jornadas ni de los historiales admite NULL');

select is(
  array(select conname::text || ':' || pg_get_constraintdef(oid) from pg_constraint
         where conrelid = 'public.jornadas'::regclass order by conname::text collate "C"),
  array['jornadas_abierta_por_fk:FOREIGN KEY (empresa_id, abierta_por) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT',
        'jornadas_camion_fecha_unica:UNIQUE (empresa_id, camion_id, fecha)',
        'jornadas_camion_fk:FOREIGN KEY (empresa_id, camion_id) REFERENCES camiones(empresa_id, id) ON DELETE RESTRICT',
        'jornadas_empresa_fk:FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE RESTRICT',
        'jornadas_empresa_id_unico:UNIQUE (empresa_id, id)',
        'jornadas_estado_valido:CHECK ((estado = ANY (ARRAY[''abierta''::text, ''cargada''::text, ''en_reparto''::text, ''ventas_finalizadas''::text, ''regreso_contado''::text, ''cerrada''::text])))',
        'jornadas_operacion_apertura_fk:FOREIGN KEY (empresa_id, operacion_apertura_id, tipo_operacion_apertura, abierta_por) REFERENCES operaciones(empresa_id, id, tipo, actor_id) ON DELETE RESTRICT',
        'jornadas_operacion_apertura_unica:UNIQUE (operacion_apertura_id)',
        'jornadas_pkey:PRIMARY KEY (id)',
        'jornadas_tipo_operacion_apertura_valido:CHECK ((tipo_operacion_apertura = ''apertura_jornada''::text))',
        'jornadas_vendedor_fecha_unica:UNIQUE (empresa_id, vendedor_id, fecha)',
        'jornadas_vendedor_fk:FOREIGN KEY (empresa_id, vendedor_id) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT'],
  'jornadas: constraints exactas (4 UNIQUE, FK compuestas con empresa_id, FK de 4 columnas a la apertura, CHECK de estado y tipo constante)');

select is(
  array(select conname::text || ':' || pg_get_constraintdef(oid) from pg_constraint
         where conrelid = 'public.reasignaciones_vendedor'::regclass order by conname::text collate "C"),
  array['reasignaciones_vendedor_actor_fk:FOREIGN KEY (empresa_id, actor_id) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT',
        'reasignaciones_vendedor_empresa_fk:FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE RESTRICT',
        'reasignaciones_vendedor_jornada_fk:FOREIGN KEY (empresa_id, jornada_id) REFERENCES jornadas(empresa_id, id) ON DELETE RESTRICT',
        'reasignaciones_vendedor_operacion_referencia_fk:FOREIGN KEY (empresa_id, operacion_id, tipo_operacion, actor_id, jornada_id) REFERENCES operaciones(empresa_id, id, tipo, actor_id, jornada_id) ON DELETE RESTRICT',
        'reasignaciones_vendedor_operacion_unica:UNIQUE (empresa_id, operacion_id)',
        'reasignaciones_vendedor_pkey:PRIMARY KEY (id)',
        'reasignaciones_vendedor_tipo_operacion_valido:CHECK ((tipo_operacion = ''reasignacion_vendedor''::text))',
        'reasignaciones_vendedor_vendedor_anterior_fk:FOREIGN KEY (empresa_id, vendedor_anterior_id) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT',
        'reasignaciones_vendedor_vendedor_nuevo_fk:FOREIGN KEY (empresa_id, vendedor_nuevo_id) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT',
        'reasignaciones_vendedor_vendedores_distintos:CHECK ((vendedor_anterior_id <> vendedor_nuevo_id))'],
  'reasignaciones_vendedor: constraints exactas (FK de 5 columnas a la operación, anterior distinto de nuevo, UNIQUE por operación)');

select is(
  array(select conname::text || ':' || pg_get_constraintdef(oid) from pg_constraint
         where conrelid = 'public.correcciones_jornada'::regclass order by conname::text collate "C"),
  array['correcciones_jornada_actor_fk:FOREIGN KEY (empresa_id, actor_id) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT',
        'correcciones_jornada_cambio_efectivo:CHECK (((fecha_anterior <> fecha_nueva) OR (camion_anterior_id <> camion_nuevo_id)))',
        'correcciones_jornada_camion_anterior_fk:FOREIGN KEY (empresa_id, camion_anterior_id) REFERENCES camiones(empresa_id, id) ON DELETE RESTRICT',
        'correcciones_jornada_camion_nuevo_fk:FOREIGN KEY (empresa_id, camion_nuevo_id) REFERENCES camiones(empresa_id, id) ON DELETE RESTRICT',
        'correcciones_jornada_empresa_fk:FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE RESTRICT',
        'correcciones_jornada_jornada_fk:FOREIGN KEY (empresa_id, jornada_id) REFERENCES jornadas(empresa_id, id) ON DELETE RESTRICT',
        'correcciones_jornada_motivo_normalizado:CHECK (((motivo = btrim(motivo)) AND (length(motivo) > 0)))',
        'correcciones_jornada_operacion_referencia_fk:FOREIGN KEY (empresa_id, operacion_id, tipo_operacion, actor_id, jornada_id) REFERENCES operaciones(empresa_id, id, tipo, actor_id, jornada_id) ON DELETE RESTRICT',
        'correcciones_jornada_operacion_unica:UNIQUE (empresa_id, operacion_id)',
        'correcciones_jornada_pkey:PRIMARY KEY (id)',
        'correcciones_jornada_tipo_operacion_valido:CHECK ((tipo_operacion = ''correccion_jornada''::text))'],
  'correcciones_jornada: constraints exactas (FK de 5 columnas a la operación, cambio efectivo, motivo normalizado)');

select is(
  pg_get_indexdef('public.movimientos_stock_operacion_producto_unica'::regclass),
  'CREATE UNIQUE INDEX movimientos_stock_operacion_producto_unica ON public.movimientos_stock USING btree (empresa_id, operacion_id, producto_id) WHERE (tipo_movimiento = ANY (ARRAY[''carga''::text, ''descarga''::text]))',
  'índice único parcial (operación, producto) sólo para carga y descarga; D7 no se modifica');

select is(
  (select string_agg(c.relname || ':' || c.relowner::regrole::text || ':' || c.relrowsecurity::text
                     || ':' || c.relforcerowsecurity::text, ',' order by c.relname)
     from pg_class c
    where c.oid in ('public.jornadas'::regclass, 'public.reasignaciones_vendedor'::regclass,
                    'public.correcciones_jornada'::regclass)),
  'correcciones_jornada:postgres:true:false,jornadas:postgres:true:false,reasignaciones_vendedor:postgres:true:false',
  'las tres tablas son del owner de migraciones, con RLS habilitada y sin FORCE (P4)');

select is(
  array(select tablename || '.' || policyname || ':' || cmd || ':' || array_to_string(roles, ',')
          from pg_policies
         where schemaname = 'public'
           and tablename in ('jornadas', 'reasignaciones_vendedor', 'correcciones_jornada')
         order by 1),
  array['correcciones_jornada.correcciones_jornada_insert_propietario_rpc:INSERT:propietario_rpc',
        'correcciones_jornada.correcciones_jornada_select_gestion:SELECT:authenticated',
        'jornadas.jornadas_insert_propietario_rpc:INSERT:propietario_rpc',
        'jornadas.jornadas_select_authenticated:SELECT:authenticated',
        'jornadas.jornadas_select_propietario_rpc:SELECT:propietario_rpc',
        'jornadas.jornadas_update_propietario_rpc:UPDATE:propietario_rpc',
        'reasignaciones_vendedor.reasignaciones_vendedor_insert_propietario_rpc:INSERT:propietario_rpc',
        'reasignaciones_vendedor.reasignaciones_vendedor_select_gestion:SELECT:authenticated'],
  'policies exactas: jornadas sin DELETE; historiales sin UPDATE ni DELETE (append-only)');

select ok(
  (select bool_and(has_table_privilege('authenticated', c, 'SELECT')
                   and not has_table_privilege('authenticated', c,
                         'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
                   and not has_any_column_privilege('authenticated', c, 'INSERT, UPDATE, REFERENCES'))
     from unnest(array['public.jornadas'::regclass, 'public.reasignaciones_vendedor'::regclass,
                       'public.correcciones_jornada'::regclass]) c),
  'authenticated: sólo SELECT en jornadas y en los dos historiales');

select ok(
  (select bool_and(not has_table_privilege(r, c,
                         'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
                   and not has_any_column_privilege(r, c, 'SELECT, INSERT, UPDATE, REFERENCES'))
     from unnest(array['anon', 'service_role']) r,
          unnest(array['public.jornadas'::regclass, 'public.reasignaciones_vendedor'::regclass,
                       'public.correcciones_jornada'::regclass]) c),
  'anon y service_role: ningún privilegio sobre las tres tablas nuevas (P11, sin excepción nueva)');

select ok(
  not exists (select 1 from pg_class c, aclexplode(c.relacl) a
               where c.oid in ('public.jornadas'::regclass, 'public.reasignaciones_vendedor'::regclass,
                               'public.correcciones_jornada'::regclass)
                 and a.grantee = 0),
  'PUBLIC sin privilegios sobre las tres tablas nuevas');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.jornadas'::regclass and a.attnum > 0 and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.jornadas', a.attname, 'INSERT')
         order by 1),
  array['abierta_por', 'camion_id', 'empresa_id', 'estado', 'fecha', 'operacion_apertura_id', 'vendedor_id'],
  'propietario_rpc inserta en jornadas sólo las siete columnas del alta (no id, tipo_operacion_apertura ni creado_en)');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.jornadas'::regclass and a.attnum > 0 and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.jornadas', a.attname, 'UPDATE')
         order by 1),
  array['camion_id', 'estado', 'fecha', 'vendedor_id'],
  'propietario_rpc actualiza en jornadas sólo estado, vendedor_id, fecha y camion_id (UPDATE controlado)');

select ok(
  has_table_privilege('propietario_rpc', 'public.jornadas', 'SELECT')
  and not has_table_privilege('propietario_rpc', 'public.jornadas', 'DELETE, TRUNCATE, REFERENCES, TRIGGER'),
  'propietario_rpc: SELECT en jornadas; sin DELETE, TRUNCATE, REFERENCES ni TRIGGER');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.reasignaciones_vendedor'::regclass and a.attnum > 0 and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.reasignaciones_vendedor', a.attname, 'INSERT')
         order by 1),
  array['actor_id', 'empresa_id', 'jornada_id', 'operacion_id', 'vendedor_anterior_id', 'vendedor_nuevo_id'],
  'propietario_rpc inserta en reasignaciones_vendedor sólo las seis columnas del alta');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.correcciones_jornada'::regclass and a.attnum > 0 and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.correcciones_jornada', a.attname, 'INSERT')
         order by 1),
  array['actor_id', 'camion_anterior_id', 'camion_nuevo_id', 'empresa_id', 'fecha_anterior', 'fecha_nueva',
        'jornada_id', 'motivo', 'operacion_id'],
  'propietario_rpc inserta en correcciones_jornada sólo las nueve columnas del alta');

select ok(
  not has_any_column_privilege('propietario_rpc', 'public.reasignaciones_vendedor', 'SELECT, UPDATE, REFERENCES')
  and not has_any_column_privilege('propietario_rpc', 'public.correcciones_jornada', 'SELECT, UPDATE, REFERENCES')
  and not has_table_privilege('propietario_rpc', 'public.reasignaciones_vendedor', 'DELETE, TRUNCATE, TRIGGER')
  and not has_table_privilege('propietario_rpc', 'public.correcciones_jornada', 'DELETE, TRUNCATE, TRIGGER'),
  'historiales append-only: propietario_rpc sin SELECT, UPDATE, DELETE ni TRUNCATE');

select ok(
  not has_any_column_privilege('propietario_rpc', 'public.operaciones', 'UPDATE')
  and not has_any_column_privilege('propietario_rpc', 'public.movimientos_stock', 'UPDATE')
  and not has_table_privilege('propietario_rpc', 'public.operaciones', 'DELETE, TRUNCATE')
  and not has_table_privilege('propietario_rpc', 'public.movimientos_stock', 'DELETE, TRUNCATE'),
  'propietario_rpc sigue sin UPDATE, DELETE ni TRUNCATE sobre operaciones y movimientos_stock');

select ok(
  exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'perfiles'
             and policyname = 'perfiles_select_empresa_lector')
  and to_regclass('privado.perfiles_empresa_gestion') is not null
  and to_regprocedure('privado.empresa_gestion_actual()') is not null,
  'D-2 intacta: la política, la vista y el helper de lectura de perfiles siguen presentes');

-- ===========================================================================
-- N — nulabilidad (como owner, para que el error sea la restricción y no la RLS)
-- ===========================================================================
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', null,
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000005',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23502', null, 'N2: reasignaciones_vendedor.operacion_id NULL se rechaza');
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000004',
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000005', null)$$,
  '23502', null, 'N3: reasignaciones_vendedor.actor_id NULL se rechaza');
select throws_ok(
  $$insert into public.correcciones_jornada (empresa_id, jornada_id, operacion_id, fecha_anterior, fecha_nueva, camion_anterior_id, camion_nuevo_id, motivo, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', null, '2026-11-02', '2026-11-03',
            'aaaaaaaa-0000-4000-8000-0000000c0001', 'aaaaaaaa-0000-4000-8000-0000000c0001', 'motivo',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23502', null, 'N4: correcciones_jornada.operacion_id NULL se rechaza');
select throws_ok(
  $$insert into public.correcciones_jornada (empresa_id, jornada_id, operacion_id, fecha_anterior, fecha_nueva, camion_anterior_id, camion_nuevo_id, motivo, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000005', '2026-11-02', '2026-11-03',
            'aaaaaaaa-0000-4000-8000-0000000c0001', 'aaaaaaaa-0000-4000-8000-0000000c0001', 'motivo', null)$$,
  '23502', null, 'N5: correcciones_jornada.actor_id NULL se rechaza');
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, tipo_operacion, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000004', null,
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000005',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23502', null, 'N6: tipo_operacion NULL explícito se rechaza (el default no se aplica a un NULL explícito)');
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values (null, 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000004',
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000005',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23502', null, 'N6: empresa_id NULL se rechaza');
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', null, 'aaaaaaaa-0000-4000-8000-00000b000004',
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000005',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23502', null, 'N6: jornada_id NULL se rechaza');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000001', null)$$,
  '23502', null, 'N7: jornadas.operacion_apertura_id NULL se rechaza');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', null, 'aaaaaaaa-0000-4000-8000-00000a000003')$$,
  '23502', null, 'N7: jornadas.abierta_por NULL se rechaza');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id, tipo_operacion_apertura)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000a000003', null)$$,
  '23502', null, 'N7: jornadas.tipo_operacion_apertura NULL se rechaza');

-- N8: control. La misma fila válida se acepta; la que difiere sólo en la
-- operación de otro tipo o de otro actor se rechaza por la FK de referencia.
select lives_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000004',
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000005',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  'N8 (control): una reasignación válida se inserta como owner');
select lives_ok(
  $$insert into public.correcciones_jornada (empresa_id, jornada_id, operacion_id, fecha_anterior, fecha_nueva, camion_anterior_id, camion_nuevo_id, motivo, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000005',
            '2026-11-02', '2026-11-03', 'aaaaaaaa-0000-4000-8000-0000000c0001', 'aaaaaaaa-0000-4000-8000-0000000c0001',
            'fecha mal cargada', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  'N8 (control): una corrección válida se inserta como owner');

-- ===========================================================================
-- S — CHECK (23514)
-- ===========================================================================
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'apertura_jornada',
            gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '23514', null, 'S: apertura_jornada con jornada_id se rechaza (operaciones_jornada_por_tipo)');
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'carga',
            gen_random_uuid(), repeat('a', 64))$$,
  '23514', null, 'S: carga sin jornada_id se rechaza');
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'ingreso',
            gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '23514', null, 'S: ingreso con jornada_id se rechaza (los tipos de Stock no llevan jornada, E13)');
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'venta',
            gen_random_uuid(), repeat('a', 64))$$,
  '23514', null, 'S: un tipo no aprobado (venta) se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000001', 'carga',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 5, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-0000000e0001', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'S: movimiento carga sin jornada_id se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, actor_id, motivo_codigo, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000007', 'merma',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 1, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001', 'vencido', 'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '23514', null, 'S: merma con jornada_id se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, actor_id, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000001', 'carga',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 5, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '23514', null, 'S: carga sin destino se rechaza (forma por tipo)');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000001', 'carga',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 5, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-0000000e0001', 'aaaaaaaa-0000-4000-8000-000000000001',
            'no corresponde', 'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '23514', null, 'S: una carga con motivo se rechaza (motivo por tipo)');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000002', 'descarga',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 5, 'aaaaaaaa-0000-4000-8000-0000000e0001',
            'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '23514', null, 'S: una descarga sin motivo se rechaza (motivo por tipo)');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'inexistente', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000a000003')$$,
  '23514', null, 'S: un estado fuera de los seis de §7.5 se rechaza');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id, tipo_operacion_apertura)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000a000003', 'carga')$$,
  '23514', null, 'S: el tipo de la operación de apertura es constante (apertura_jornada)');
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000006',
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000003',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'S: una reasignación al mismo vendedor se rechaza');
select throws_ok(
  $$insert into public.correcciones_jornada (empresa_id, jornada_id, operacion_id, fecha_anterior, fecha_nueva, camion_anterior_id, camion_nuevo_id, motivo, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000008',
            '2026-11-02', '2026-11-02', 'aaaaaaaa-0000-4000-8000-0000000c0001', 'aaaaaaaa-0000-4000-8000-0000000c0001',
            'sin cambio', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'S: una corrección sin cambio de fecha ni de camión se rechaza');
select throws_ok(
  $$insert into public.correcciones_jornada (empresa_id, jornada_id, operacion_id, fecha_anterior, fecha_nueva, camion_anterior_id, camion_nuevo_id, motivo, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000008',
            '2026-11-02', '2026-11-03', 'aaaaaaaa-0000-4000-8000-0000000c0001', 'aaaaaaaa-0000-4000-8000-0000000c0001',
            ' con espacios ', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23514', null, 'S: el motivo de una corrección debe estar normalizado (btrim) y no vacío');

-- ===========================================================================
-- S — FK de referencia (23503) y aislamiento por empresa
-- ===========================================================================
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000b000001')$$,
  '23503', null, 'S: una jornada que apunta a una operación de tipo carga se rechaza');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000a000004')$$,
  '23503', null, 'S: una jornada que apunta a una apertura de otro actor se rechaza');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'bbbbbbbb-0000-4000-8000-0000000c0001',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000a000003')$$,
  '23503', null, 'S: una jornada con un camión de otra empresa se rechaza (FK compuesta)');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'bbbbbbbb-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000a000003')$$,
  '23503', null, 'S: una jornada con un vendedor de otra empresa se rechaza (FK compuesta)');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-02', 'aaaaaaaa-0000-4000-8000-0000000c0001',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000a000003')$$,
  '23505', null, 'S: el mismo camión en la misma fecha se rechaza, incluso con otro vendedor (UNIQUE)');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-02', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000003', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000a000003')$$,
  '23505', null, 'S: el mismo vendedor en la misma fecha se rechaza, incluso con otro camión (UNIQUE)');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-06', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000a000001')$$,
  '23505', null, 'S: una operación de apertura sólo puede abrir una jornada (UNIQUE operacion_apertura_id)');
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id)
    values ('bbbbbbbb-0000-4000-8000-000000000000', 'bbbbbbbb-0000-4000-8000-000000000001', 'carga',
            gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '23503', null, 'S: una operación de B no puede referenciar una jornada de A (FK compuesta con empresa_id)');
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000002', 'aaaaaaaa-0000-4000-8000-00000b000006',
            'aaaaaaaa-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000003',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23503', null, 'S: un historial que apunta a una operación de otra jornada se rechaza');
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000008',
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000005',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23503', null, 'S: un historial de reasignaciones que apunta a una operación de otro tipo se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000002', 'carga',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 5, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-0000000e0001', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '23503', null, 'S: un movimiento carga con una operación de tipo descarga se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000001', 'carga',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 5, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-0000000e0001', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000d000002')$$,
  '23503', null, 'S: un movimiento cuya jornada difiere de la de su operación se rechaza (FK de referencia)');

-- ===========================================================================
-- Cargas multiproducto y D7 sin cambios
-- ===========================================================================
select lives_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000001', 'carga',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 5, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-0000000e0001', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000d000001'),
           ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000001', 'carga',
            'aaaaaaaa-0000-4000-8000-0000000000f2', 1250, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-0000000e0001', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  'una carga multiproducto (dos productos en la misma operación) se acepta: D7 no la alcanza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000001', 'carga',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 3, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-0000000e0001', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '23505', null, 'el mismo producto dos veces en una carga se rechaza (movimientos_stock_operacion_producto_unica)');
select lives_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000002', 'descarga',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 2, 'aaaaaaaa-0000-4000-8000-0000000e0001',
            'aaaaaaaa-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001', 'devolución por rotura',
            'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  'una descarga con motivo y jornada se acepta (camión -> depósito)');
select lives_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000007', 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 10, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  'un ingreso de Stock sigue siendo válido sin jornada (regresión de Stock)');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_destino_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000007', 'ingreso',
            'aaaaaaaa-0000-4000-8000-0000000000f2', 10, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '23505', null, 'D7 sin cambios: una operación unitaria de Stock sigue admitiendo un único movimiento');

-- ===========================================================================
-- S — policies directas de propietario_rpc
-- ===========================================================================
-- USAGE sobre `extensions` sólo para poder invocar pgTAP con ese rol (pgTAP
-- vive en ese esquema y propietario_rpc no tiene acceso a él). Es un GRANT
-- transaccional: se revierte con el ROLLBACK de este test y no queda ningún
-- privilegio permanente ni se toca ninguna migración (mismo patrón que
-- camiones_catalogo.test.sql, clientes_catalogo.test.sql y
-- productos_catalogo.test.sql).
grant usage on schema extensions to propietario_rpc;

-- jornadas: INSERT
select pg_temp.como_propietario('aaaaaaaa-0000-4000-8000-000000000003');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000003',
            'aaaaaaaa-0000-4000-8000-00000a000003')$$,
  '42501', null, 'RLS: un vendedor/piloto no inserta jornadas');
reset role;
select pg_temp.como_propietario('aaaaaaaa-0000-4000-8000-000000000004');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000004',
            'aaaaaaaa-0000-4000-8000-00000a000003')$$,
  '42501', null, 'RLS: un dueño inactivo no inserta jornadas');
reset role;
select pg_temp.como_propietario('bbbbbbbb-0000-4000-8000-000000000001');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'bbbbbbbb-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000a000003')$$,
  '42501', null, 'RLS: el dueño de B no inserta jornadas en la empresa A');
reset role;
select pg_temp.como_propietario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000002',
            'aaaaaaaa-0000-4000-8000-00000a000004')$$,
  '42501', null, 'RLS: abierta_por debe ser el llamador');
select lives_ok(
  $$insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', '2026-11-05', 'aaaaaaaa-0000-4000-8000-0000000c0003',
            'aaaaaaaa-0000-4000-8000-000000000002', 'abierta', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000a000003')$$,
  'RLS: un dueño activo inserta una jornada de su empresa con abierta_por = llamador');
-- jornadas: SELECT / UPDATE / DELETE
select is(
  (select count(*)::int from public.jornadas),
  3,
  'RLS: propietario_rpc, con el claim de un dueño de A, ve las jornadas de A (3) y ninguna de B');
select is(
  pg_temp.filas_afectadas($q$update public.jornadas set estado = 'cargada'
                              where id = 'aaaaaaaa-0000-4000-8000-00000d000001'$q$),
  1,
  'UPDATE controlado: un dueño actualiza el estado de una jornada de su empresa');
select is(
  pg_temp.filas_afectadas($q$update public.jornadas set estado = 'cargada'
                              where id = 'bbbbbbbb-0000-4000-8000-00000d000001'$q$),
  0,
  'RLS: el dueño de A no actualiza jornadas de B (0 filas)');
select throws_ok(
  $$update public.jornadas set abierta_por = 'aaaaaaaa-0000-4000-8000-000000000002'
     where id = 'aaaaaaaa-0000-4000-8000-00000d000001'$$,
  '42501', null, 'propietario_rpc no actualiza abierta_por (sin privilegio de columna)');
select throws_ok(
  $$update public.jornadas set empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000'
     where id = 'aaaaaaaa-0000-4000-8000-00000d000001'$$,
  '42501', null, 'propietario_rpc no mueve una jornada de empresa (sin privilegio de columna)');
select throws_ok(
  $$update public.jornadas set operacion_apertura_id = 'aaaaaaaa-0000-4000-8000-00000a000003'
     where id = 'aaaaaaaa-0000-4000-8000-00000d000001'$$,
  '42501', null, 'propietario_rpc no cambia la operación de apertura (sin privilegio de columna)');
select throws_ok(
  $$delete from public.jornadas where id = 'aaaaaaaa-0000-4000-8000-00000d000001'$$,
  '42501', null, 'propietario_rpc no borra jornadas');
reset role;
select pg_temp.como_propietario('aaaaaaaa-0000-4000-8000-000000000003');
select is(
  (select count(*)::int from public.jornadas),
  0,
  'RLS: con el claim de un vendedor, propietario_rpc no ve jornadas');
select is(
  pg_temp.filas_afectadas($q$update public.jornadas set estado = 'cerrada'
                              where id = 'aaaaaaaa-0000-4000-8000-00000d000001'$q$),
  0,
  'RLS: un vendedor no actualiza jornadas (0 filas)');
reset role;
select pg_temp.como_propietario('aaaaaaaa-0000-4000-8000-000000000004');
select is(
  (select count(*)::int from public.jornadas),
  0,
  'RLS: con el claim de un dueño inactivo, propietario_rpc no ve jornadas');
reset role;

-- historiales: INSERT
select pg_temp.como_propietario('aaaaaaaa-0000-4000-8000-000000000003');
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000006',
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000005',
            'aaaaaaaa-0000-4000-8000-000000000003')$$,
  '42501', null, 'RLS: un vendedor no inserta en el historial de reasignaciones');
reset role;
select pg_temp.como_propietario('aaaaaaaa-0000-4000-8000-000000000004');
select throws_ok(
  $$insert into public.correcciones_jornada (empresa_id, jornada_id, operacion_id, fecha_anterior, fecha_nueva, camion_anterior_id, camion_nuevo_id, motivo, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000008',
            '2026-11-02', '2026-11-03', 'aaaaaaaa-0000-4000-8000-0000000c0001', 'aaaaaaaa-0000-4000-8000-0000000c0001',
            'motivo', 'aaaaaaaa-0000-4000-8000-000000000004')$$,
  '42501', null, 'RLS: un dueño inactivo no inserta en el historial de correcciones');
reset role;
select pg_temp.como_propietario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000006',
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000005',
            'aaaaaaaa-0000-4000-8000-000000000002')$$,
  '42501', null, 'RLS: el actor del historial debe ser el llamador');
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('bbbbbbbb-0000-4000-8000-000000000000', 'bbbbbbbb-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000006',
            'bbbbbbbb-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'RLS: el dueño de A no inserta historial en la empresa B');
select lives_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000006',
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000005',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  'RLS: un dueño activo inserta una reasignación de su empresa (actor = llamador)');
select lives_ok(
  $$insert into public.correcciones_jornada (empresa_id, jornada_id, operacion_id, fecha_anterior, fecha_nueva, camion_anterior_id, camion_nuevo_id, motivo, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000008',
            '2026-11-02', '2026-11-03', 'aaaaaaaa-0000-4000-8000-0000000c0001', 'aaaaaaaa-0000-4000-8000-0000000c0001',
            'fecha mal cargada', 'aaaaaaaa-0000-4000-8000-000000000001')$$,
  'RLS: un dueño activo inserta una corrección de su empresa (actor = llamador)');
-- Append-only: ni lectura, ni UPDATE, ni DELETE para propietario_rpc.
select throws_ok(
  $$select count(*) from public.reasignaciones_vendedor$$,
  '42501', null, 'propietario_rpc no lee reasignaciones_vendedor (sin SELECT)');
select throws_ok(
  $$select count(*) from public.correcciones_jornada$$,
  '42501', null, 'propietario_rpc no lee correcciones_jornada (sin SELECT)');
select throws_ok(
  $$update public.reasignaciones_vendedor set vendedor_nuevo_id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  '42501', null, 'append-only: propietario_rpc no actualiza reasignaciones_vendedor');
select throws_ok(
  $$delete from public.reasignaciones_vendedor$$,
  '42501', null, 'append-only: propietario_rpc no borra reasignaciones_vendedor');
select throws_ok(
  $$update public.correcciones_jornada set motivo = 'otro'$$,
  '42501', null, 'append-only: propietario_rpc no actualiza correcciones_jornada');
select throws_ok(
  $$delete from public.correcciones_jornada$$,
  '42501', null, 'append-only: propietario_rpc no borra correcciones_jornada');

-- operaciones y ledger (D6/D8 ampliadas)
select lives_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'salida_jornada',
            gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  'D6: una operación de jornada con una jornada de la propia empresa se acepta');
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'salida_jornada',
            gen_random_uuid(), repeat('a', 64), 'bbbbbbbb-0000-4000-8000-00000d000001')$$,
  '42501', null, 'D6: una operación de jornada con una jornada de otra empresa se rechaza');
select throws_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'ingreso',
            gen_random_uuid(), repeat('a', 64), 'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '42501', null, 'D6: un ingreso con jornada_id se rechaza por la policy');
select lives_ok(
  $$insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-000000000001', 'ingreso',
            gen_random_uuid(), repeat('a', 64))$$,
  'D6: un ingreso sin jornada se sigue aceptando (regresión de Stock)');
select lives_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000009', 'carga',
            'aaaaaaaa-0000-4000-8000-0000000000f1', 7, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-0000000e0001', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  'D8: una carga del depósito propio a la ubicación del camión de la jornada se acepta');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000009', 'carga',
            'aaaaaaaa-0000-4000-8000-0000000000f2', 7, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-0000000e0002', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '42501', null, 'D8: una carga hacia la ubicación de otro camión se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000002', 'descarga',
            'aaaaaaaa-0000-4000-8000-0000000000f2', 1, 'aaaaaaaa-0000-4000-8000-0000000e0001',
            'aaaaaaaa-0000-4000-8000-0000000000d2', 'aaaaaaaa-0000-4000-8000-000000000001', 'sobrante',
            'aaaaaaaa-0000-4000-8000-00000d000001')$$,
  '42501', null, 'D8: una descarga hacia algo que no es el depósito se rechaza');
select throws_ok(
  $$insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
                                         ubicacion_origen_id, ubicacion_destino_id, actor_id, jornada_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000b000009', 'carga',
            'aaaaaaaa-0000-4000-8000-0000000000f2', 7, 'aaaaaaaa-0000-4000-8000-0000000000d1',
            'aaaaaaaa-0000-4000-8000-0000000e0002', 'aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-00000d000002')$$,
  '42501', null, 'D8: una jornada del movimiento distinta de la de su operación se rechaza');
reset role;

-- ===========================================================================
-- Lectura por rol (authenticated) y rechazos de anon / service_role
-- ===========================================================================
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select is(
  (select count(*)::int from public.jornadas),
  3,
  'authenticated: el dueño de A lee las jornadas de A y ninguna de B');
select is(
  (select count(*)::int from public.reasignaciones_vendedor) + (select count(*)::int from public.correcciones_jornada),
  4,
  'authenticated: el dueño de A lee los historiales de A (2 + 2)');
reset role;
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select is(
  (select count(*)::int from public.jornadas),
  3,
  'authenticated: el encargado de A lee las jornadas de A');
reset role;
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003');
select is(
  (select array_agg(id) from public.jornadas),
  array['aaaaaaaa-0000-4000-8000-00000d000001'::uuid],
  'authenticated: el vendedor ve sólo su jornada (ADR-007 prueba 23)');
select is(
  (select count(*)::int from public.reasignaciones_vendedor) + (select count(*)::int from public.correcciones_jornada),
  0,
  'authenticated: el vendedor no ve los historiales (ADR-007 prueba 23)');
reset role;
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000005');
select is(
  (select array_agg(id) from public.jornadas),
  array['aaaaaaaa-0000-4000-8000-00000d000002'::uuid],
  'authenticated: otro vendedor ve sólo la suya');
reset role;
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000004');
select is(
  (select count(*)::int from public.jornadas),
  0,
  'authenticated: un dueño inactivo no ve jornadas');
reset role;
select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select is(
  (select array_agg(id) from public.jornadas),
  array['bbbbbbbb-0000-4000-8000-00000d000001'::uuid],
  'authenticated: el dueño de B sólo ve la jornada de B');
select is(
  (select count(*)::int from public.reasignaciones_vendedor) + (select count(*)::int from public.correcciones_jornada),
  0,
  'authenticated: el dueño de B no ve los historiales de A');
reset role;

-- DML directo de authenticated, anon y service_role
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$update public.jornadas set estado = 'cerrada'$$, '42501', null,
  'authenticated no actualiza jornadas');
select throws_ok(
  $$delete from public.jornadas$$, '42501', null,
  'authenticated no borra jornadas');
select throws_ok(
  $$insert into public.reasignaciones_vendedor (empresa_id, jornada_id, operacion_id, vendedor_anterior_id, vendedor_nuevo_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'aaaaaaaa-0000-4000-8000-00000d000001', 'aaaaaaaa-0000-4000-8000-00000b000006',
            'aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000005',
            'aaaaaaaa-0000-4000-8000-000000000001')$$,
  '42501', null, 'authenticated no inserta en el historial de reasignaciones');
select throws_ok(
  $$update public.correcciones_jornada set motivo = 'x'$$, '42501', null,
  'authenticated no actualiza el historial de correcciones');
reset role;
select pg_temp.como_anon();
select throws_ok($$select count(*) from public.jornadas$$, '42501', null,
  'anon no lee jornadas');
select throws_ok($$select count(*) from public.reasignaciones_vendedor$$, '42501', null,
  'anon no lee reasignaciones_vendedor');
select throws_ok($$select count(*) from public.correcciones_jornada$$, '42501', null,
  'anon no lee correcciones_jornada');
reset role;
select pg_temp.como_service();
select throws_ok($$select count(*) from public.jornadas$$, '42501', null,
  'service_role no lee jornadas (P11)');
select throws_ok($$select count(*) from public.reasignaciones_vendedor$$, '42501', null,
  'service_role no lee reasignaciones_vendedor (P11)');
select throws_ok($$select count(*) from public.correcciones_jornada$$, '42501', null,
  'service_role no lee correcciones_jornada (P11)');
select throws_ok(
  $$update public.jornadas set estado = 'cerrada'$$, '42501', null,
  'service_role no actualiza jornadas (P11)');
select throws_ok(
  $$delete from public.correcciones_jornada$$, '42501', null,
  'service_role no borra historiales (P11)');
reset role;

select * from finish();

rollback;
