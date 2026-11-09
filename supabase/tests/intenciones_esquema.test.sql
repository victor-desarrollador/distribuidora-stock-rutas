-- pgTAP: esquema y seguridad de las intenciones persistidas — corte C1.1
-- (ADR-010 v1.0 §5.2/§5.10/§5.11, anexo v1.1 §4.6/§6.2/§6.3, adenda A-1…A-4;
-- ADR-001 P3/P4/P11; Blueprint §8 y §12 «Intenciones persistidas de stock» y
-- «Seguridad»). Migración 20261111120000_intenciones_operacion_esquema.sql.
--
-- Cubre las pruebas mínimas del corte: ES-01, ES-02, ES-03, ES-03b, ES-07,
-- RF-01/02/03/05/06b/07, FK-N, RX-01(b), OC-1, NG-05 (nivel base, 42501 y
-- nunca filas vacías), aislamiento por empresa/actor, protección pg_temp y el
-- inventario exacto de funciones de intenciones (C1.2a: seis). NO cubre el
-- comportamiento de las RPC (tests intenciones_*.test.sql) ni la concurrencia (C1.3). El preflight T3-01 y sus negativos se verifican aparte.
--
-- El actor «propietario_rpc» y los roles de la Data API se emulan con
-- SET LOCAL ROLE dentro de pg_temp.llamar(); el rol efectivo del actor lo da
-- privado.usuario_actual() a partir de request.jwt.claims.
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(115);

-- ---------------------------------------------------------------------------
-- Ayudantes (tipos calificados: la sección H crea dominios hostiles en pg_temp)
-- ---------------------------------------------------------------------------
-- llamar(rol, usuario, sentencia): ejecuta UNA sentencia que devuelve un escalar
-- bajo el rol indicado y devuelve 'OK:<valor>' o 'ERR:<sqlstate>'.
create function pg_temp.llamar(p_rol pg_catalog.text, p_uid pg_catalog.uuid, p_sql pg_catalog.text)
returns pg_catalog.text language plpgsql as $f$
declare v pg_catalog.text;
begin
  perform pg_catalog.set_config('request.jwt.claims',
    case when p_uid is null then '{"role":"anon"}'
         else pg_catalog.jsonb_build_object('sub', p_uid, 'role', 'authenticated')::pg_catalog.text end, true);
  execute pg_catalog.format('set local role %I', p_rol);
  begin
    execute p_sql into v;
    v := 'OK:' || coalesce(v, 'NULL');
  exception when others then
    v := 'ERR:' || sqlstate;
  end;
  reset role;
  return v;
end $f$;

-- err(sentencia): como el rol de la sesión (postgres), 'OK' o el SQLSTATE.
create function pg_temp.err(p_sql pg_catalog.text) returns pg_catalog.text language plpgsql as $f$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlstate;
end $f$;

-- ---------------------------------------------------------------------------
-- Datos sintéticos (se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('a1a1a1a1-0000-4000-8000-000000000000', 'Empresa A (test intenciones)'),
  ('b1b1b1b1-0000-4000-8000-000000000000', 'Empresa B (test intenciones)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('a1a1a1a1-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ic.a1@usuarios.distribuidora.invalid', '{}'),
  ('a1a1a1a1-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'ic.a2@usuarios.distribuidora.invalid', '{}'),
  ('a1a1a1a1-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'ic.a3@usuarios.distribuidora.invalid',
     '{"rol":"dueno","empresa_id":"b1b1b1b1-0000-4000-8000-000000000000"}'),
  ('a1a1a1a1-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'ic.a4@usuarios.distribuidora.invalid', '{}'),
  ('b1b1b1b1-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ic.b1@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('a1a1a1a1-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000000', 'ic.a1', 'Dueño A', 'dueno', true),
  ('a1a1a1a1-0000-4000-8000-000000000002', 'a1a1a1a1-0000-4000-8000-000000000000', 'ic.a2', 'Encargado A', 'encargado', true),
  ('a1a1a1a1-0000-4000-8000-000000000003', 'a1a1a1a1-0000-4000-8000-000000000000', 'ic.a3', 'Vendedor A', 'vendedor_piloto', true),
  ('a1a1a1a1-0000-4000-8000-000000000004', 'a1a1a1a1-0000-4000-8000-000000000000', 'ic.a4', 'Dueño inactivo A', 'dueno', false),
  ('b1b1b1b1-0000-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-000000000000', 'ic.b1', 'Dueño B', 'dueno', true);

-- Operaciones (id distinto de la idempotency_key: P15 / RF-06b).
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella) values
  ('c0c0c0c0-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', 'd0d0d0d0-0000-4000-8000-000000000001', repeat('a', 64)),
  ('c0c0c0c0-0000-4000-8000-000000000002', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'merma',   'd0d0d0d0-0000-4000-8000-000000000002', repeat('a', 64)),
  ('c0c0c0c0-0000-4000-8000-000000000003', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000002', 'ingreso', 'd0d0d0d0-0000-4000-8000-000000000003', repeat('a', 64)),
  ('c0c0c0c0-0000-4000-8000-000000000004', 'b1b1b1b1-0000-4000-8000-000000000000', 'b1b1b1b1-0000-4000-8000-000000000001', 'ingreso', 'd0d0d0d0-0000-4000-8000-000000000004', repeat('a', 64)),
  ('c0c0c0c0-0000-4000-8000-000000000005', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', 'd0d0d0d0-0000-4000-8000-000000000005', repeat('a', 64)),
  ('c0c0c0c0-0000-4000-8000-000000000006', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', 'd0d0d0d0-0000-4000-8000-000000000006', repeat('a', 64)),
  ('c0c0c0c0-0000-4000-8000-000000000007', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', 'd0d0d0d0-0000-4000-8000-000000000007', repeat('a', 64));

-- Intenciones sembradas como propietario (la RLS no las filtra): una de cada
-- estado para el actor A1 y una para cada otro actor. Las confirmadas usan
-- id = idempotency_key de su operación (invariante RF-03).
insert into public.intenciones_operacion
  (id, empresa_id, actor_id, tipo, payload, estado, operacion_id, codigo_rechazo, creado_en, vence_en, resuelto_en)
select v.id, v.emp, v.actor, v.tipo, '{"producto_id":"e0e0e0e0-0000-4000-8000-000000000001","cantidad":5,"motivo":null}'::jsonb,
       v.estado, v.op, v.cod, clock_timestamp() - interval '1 hour', clock_timestamp() + interval '23 hours',
       case when v.estado <> 'pendiente' then clock_timestamp() end
  from (values
    ('f0f0f0f0-0000-4000-8000-000000000001'::uuid, 'a1a1a1a1-0000-4000-8000-000000000000'::uuid, 'a1a1a1a1-0000-4000-8000-000000000001'::uuid, 'ingreso', 'pendiente',  null::uuid, null::text),
    ('f0f0f0f0-0000-4000-8000-000000000002', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', 'pendiente',  null, null),
    ('f0f0f0f0-0000-4000-8000-000000000003', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'merma',   'pendiente',  null, null),
    ('d0d0d0d0-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', 'confirmada', 'c0c0c0c0-0000-4000-8000-000000000001', null),
    ('d0d0d0d0-0000-4000-8000-000000000005', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', 'confirmada', 'c0c0c0c0-0000-4000-8000-000000000005', null),
    ('f0f0f0f0-0000-4000-8000-000000000008', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', 'rechazada',  null, 'stock_insuficiente'),
    ('f0f0f0f0-0000-4000-8000-000000000009', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', 'cancelada',  null, null),
    ('f0f0f0f0-0000-4000-8000-00000000000a', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000002', 'ingreso', 'pendiente',  null, null),
    ('d0d0d0d0-0000-4000-8000-000000000003', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000002', 'ingreso', 'confirmada', 'c0c0c0c0-0000-4000-8000-000000000003', null),
    ('f0f0f0f0-0000-4000-8000-00000000000b', 'b1b1b1b1-0000-4000-8000-000000000000', 'b1b1b1b1-0000-4000-8000-000000000001', 'ingreso', 'pendiente',  null, null),
    ('f0f0f0f0-0000-4000-8000-00000000000c', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000004', 'ingreso', 'pendiente',  null, null)
  ) as v(id, emp, actor, tipo, estado, op, cod);

-- ===========================================================================
-- A. Estructura (ES-01)
-- ===========================================================================
select has_table('public', 'intenciones_operacion', 'ES-01: existe public.intenciones_operacion');
select has_table('public', 'intenciones_reconocimientos', 'ES-01: existe public.intenciones_reconocimientos');

select is(
  (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull, ',' order by a.attnum)
     from pg_attribute a
    where a.attrelid = 'public.intenciones_operacion'::regclass and a.attnum > 0 and not a.attisdropped),
  'id:uuid:true,empresa_id:uuid:true,actor_id:uuid:true,tipo:text:true,payload:jsonb:true,estado:text:true,operacion_id:uuid:false,codigo_rechazo:text:false,creado_en:timestamp with time zone:true,vence_en:timestamp with time zone:true,resuelto_en:timestamp with time zone:false',
  'ES-01: columnas, tipos y NOT NULL de intenciones_operacion exactos');

select is(
  (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull, ',' order by a.attnum)
     from pg_attribute a
    where a.attrelid = 'public.intenciones_reconocimientos'::regclass and a.attnum > 0 and not a.attisdropped),
  'empresa_id:uuid:true,actor_id:uuid:true,operacion_id:uuid:true,reconocido_en:timestamp with time zone:true',
  'ES-01: columnas de intenciones_reconocimientos exactas, sin idempotency_key ni intencion_id (P15)');

select is(
  (select string_agg(a.attname || '=' || pg_get_expr(d.adbin, d.adrelid), ',' order by a.attname)
     from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass)),
  'creado_en=clock_timestamp(),estado=''pendiente''::text,reconocido_en=clock_timestamp()',
  'ES-01: defaults del servidor (estado pendiente; marcas de tiempo con clock_timestamp)');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'intenciones_operacion_pkey' and conrelid = 'public.intenciones_operacion'::regclass),
  'PRIMARY KEY (empresa_id, actor_id, id)',
  'ES-01: PK por (empresa, actor, id): espacio de ids por actor');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'intenciones_operacion_actor_fk'),
  'FOREIGN KEY (empresa_id, actor_id) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT',
  'ES-01: FK del actor a perfiles (empresa, usuario)');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'intenciones_operacion_empresa_fk'),
  'FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE RESTRICT',
  'ES-01: FK a empresas');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'intenciones_operacion_operacion_fk'),
  'FOREIGN KEY (empresa_id, operacion_id, tipo, actor_id) REFERENCES operaciones(empresa_id, id, tipo, actor_id) ON DELETE RESTRICT',
  'ES-01: FK COMPUESTA (empresa, operacion, tipo, actor) a operaciones_referencia_apertura');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'intenciones_operacion_operacion_unica'),
  'UNIQUE (empresa_id, actor_id, operacion_id)',
  'ES-01: UNIQUE (empresa, actor, operacion_id): relación 1:1 operación ↔ intención');

select is(
  (select array_agg(conname::text order by conname) from pg_constraint
    where conrelid = 'public.intenciones_operacion'::regclass and contype = 'c'),
  array['intenciones_coherencia', 'intenciones_estado_valido', 'intenciones_payload_objeto', 'intenciones_tipo_valido', 'intenciones_vence_posterior'],
  'ES-01: los cinco CHECK aprobados (tipo, estado, payload objeto, vencimiento, coherencia)');

select is(
  (select count(*)::int from pg_constraint where conrelid = 'public.intenciones_operacion'::regclass),
  10,
  'ES-01: exactamente 10 restricciones (PK, 3 FK, UNIQUE, 5 CHECK); ninguna fuera del contrato');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'intenciones_reconocimientos_intencion_fk'),
  'FOREIGN KEY (empresa_id, actor_id, operacion_id) REFERENCES intenciones_operacion(empresa_id, actor_id, operacion_id) ON DELETE RESTRICT',
  'ES-01: FK de reconocimientos a la UNIQUE de intenciones (no a operaciones, no a la clave)');

select is(
  (select array_agg(conname::text order by conname) from pg_constraint where conrelid = 'public.intenciones_reconocimientos'::regclass),
  array['intenciones_reconocimientos_intencion_fk', 'intenciones_reconocimientos_pkey'],
  'ES-01: reconocimientos tiene solo PK y FK');

select is(
  (select array_agg(indexname::text order by indexname) from pg_indexes
    where schemaname = 'public' and tablename = 'intenciones_operacion'),
  array['intenciones_actor_idx', 'intenciones_operacion_operacion_unica', 'intenciones_operacion_pkey'],
  'ES-01: solo los índices aprobados en intenciones_operacion (sin DT-1)');

select is(
  (select indexdef from pg_indexes where indexname = 'intenciones_actor_idx'),
  'CREATE INDEX intenciones_actor_idx ON public.intenciones_operacion USING btree (empresa_id, actor_id, creado_en DESC)',
  'ES-01: intenciones_actor_idx (empresa, actor, creado_en DESC)');

select is(
  (select array_agg(indexname::text order by indexname) from pg_indexes
    where schemaname = 'public' and tablename = 'intenciones_reconocimientos'),
  array['intenciones_reconocimientos_pkey'],
  'ES-01: reconocimientos solo tiene el índice de su PK');

-- ===========================================================================
-- B. Libros mayores y objetos existentes sin cambios (ES-07); inventario de funciones
-- ===========================================================================
select set_config('search_path', 'pg_catalog, pg_temp', true);

create temp table huella_libros as
select (select md5(string_agg(l, E'\n' order by l collate "C")) || '|' || count(*) from (
     select concat_ws('|','rel',c.relname,c.relkind,pg_get_userbyid(c.relowner),c.relrowsecurity,c.relforcerowsecurity,coalesce(c.relacl::text,'-'),coalesce(c.reloptions::text,'-')) l
       from pg_class c where c.oid in ('public.operaciones'::regclass,'public.movimientos_stock'::regclass)
     union all
     select concat_ws('|','col',a.attrelid::regclass::text,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,coalesce(pg_get_expr(d.adbin,d.adrelid),'-'),coalesce(a.attacl::text,'-'))
       from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
      where a.attrelid in ('public.operaciones'::regclass,'public.movimientos_stock'::regclass) and a.attnum>0 and not a.attisdropped
     union all
     select concat_ws('|','con',o.conrelid::regclass::text,o.conname,pg_get_constraintdef(o.oid))
       from pg_constraint o where o.conrelid in ('public.operaciones'::regclass,'public.movimientos_stock'::regclass)
     union all
     select concat_ws('|','pol',p.polrelid::regclass::text,p.polname,p.polcmd,p.polpermissive,coalesce(pg_get_expr(p.polqual,p.polrelid),'-'),coalesce(pg_get_expr(p.polwithcheck,p.polrelid),'-'))
       from pg_policy p where p.polrelid in ('public.operaciones'::regclass,'public.movimientos_stock'::regclass)
   ) x) as h;

select set_config('search_path', '"$user", public, extensions', true);

select is(
  (select h from huella_libros),
  'd4615b92926a9208fc3b69af8a134336|59',
  'ES-07: operaciones y movimientos_stock (columnas, restricciones, políticas, ACL, RLS) idénticos a la línea base 995ad7c (huella de 59 líneas)');

select set_config('search_path', '"$user", public, extensions', true);

select is(
  (select count(*)::int from pg_constraint o
    where o.contype = 'f' and o.conrelid in ('public.operaciones'::regclass, 'public.movimientos_stock'::regclass)
      and o.confrelid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass)),
  0,
  'ES-07: operaciones y movimientos_stock no referencian a las tablas nuevas (la FK va de la intención a la operación)');

-- Inventario EXACTO de funciones de intenciones (C1.2a): solo las seis autorizadas, con firma y
-- atributos aprobados. Cualquier función adicional o faltante (p. ej. reconocer/listar antes de
-- C1.2b) hace fallar la aserción. En C1.2b la lista pasa a diez.
select is(
  (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')|'
                              || case when p.prosecdef then 'definer' else 'invoker' end || '|' || p.provolatile::text || '|'
                              || pg_get_userbyid(p.proowner) || '|' || coalesce(p.proconfig[1], 'sin_config'), ';'
                              order by n.nspname, p.proname), '')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'privado') and p.proname like '%intencion%'),
  'privado.cancelar_intencion_operacion(p_intencion_id uuid)|definer|v|propietario_rpc|search_path="";'
  || 'privado.crear_intencion_operacion(p_intencion_id uuid, p_tipo text, p_payload jsonb)|definer|v|propietario_rpc|search_path="";'
  || 'privado.ejecutar_intencion_operacion(p_intencion_id uuid)|definer|v|propietario_rpc|search_path="";'
  || 'public.cancelar_intencion_operacion(p_intencion_id uuid)|invoker|v|postgres|search_path="";'
  || 'public.crear_intencion_operacion(p_intencion_id uuid, p_tipo text, p_payload jsonb)|invoker|v|postgres|search_path="";'
  || 'public.ejecutar_intencion_operacion(p_intencion_id uuid)|invoker|v|postgres|search_path=""',
  'C1.2a: el inventario de funciones de intenciones son exactamente las seis autorizadas (crear, ejecutar y cancelar; privada y fachada), sin funciones adicionales');

select is(
  (select count(*)::int from pg_trigger t
    where t.tgrelid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass)
      and not t.tgisinternal),
  0,
  'ES-01: sin triggers en las tablas nuevas (las transiciones se imponen por RLS y por las funciones)');

-- ===========================================================================
-- C. Comportamiento de restricciones (como propietario; RLS no interviene)
-- ===========================================================================
create temp table seq_id (n int);
insert into seq_id values (0);

-- CHECK de estado, tipo, payload, vencimiento y coherencia (ES-01). Cada intento
-- usa un id nuevo y el actor A1.
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en)
  values ('aaaaaaaa-1111-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours')$q$),
  'OK', 'ES-01: una pendiente válida se inserta (estado por defecto pendiente)');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en)
  values ('aaaaaaaa-1111-4000-8000-000000000002', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'venta', '{"x":1}', clock_timestamp() + interval '24 hours')$q$),
  '23514', 'ES-01: tipo fuera de (ingreso, a_cuarentena, merma) → CHECK');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en)
  values ('aaaaaaaa-1111-4000-8000-000000000003', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '[1]', clock_timestamp() + interval '24 hours')$q$),
  '23514', 'ES-01: payload que no es objeto → CHECK');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, creado_en)
  values ('aaaaaaaa-1111-4000-8000-000000000004', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', now(), now())$q$),
  '23514', 'ES-01: vence_en no posterior a creado_en → CHECK');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, estado)
  values ('aaaaaaaa-1111-4000-8000-000000000005', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours', 'ejecutando')$q$),
  '23514', 'ES-01: estado fuera de los cuatro → CHECK');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, estado, resuelto_en)
  values ('aaaaaaaa-1111-4000-8000-000000000006', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours', 'pendiente', now())$q$),
  '23514', 'ES-01 coherencia: pendiente con resuelto_en → CHECK');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, estado, resuelto_en)
  values ('aaaaaaaa-1111-4000-8000-000000000007', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours', 'confirmada', now())$q$),
  '23514', 'ES-01 coherencia: confirmada sin operacion_id → CHECK');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, estado, resuelto_en)
  values ('aaaaaaaa-1111-4000-8000-000000000008', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours', 'rechazada', now())$q$),
  '23514', 'ES-01 coherencia: rechazada sin codigo_rechazo → CHECK');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, estado, resuelto_en, codigo_rechazo)
  values ('aaaaaaaa-1111-4000-8000-000000000009', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours', 'cancelada', now(), 'stock_insuficiente')$q$),
  '23514', 'ES-01 coherencia: cancelada con codigo_rechazo → CHECK');

-- PK y espacio de ids por actor; FK de actor y de empresa.
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en)
  values ('aaaaaaaa-1111-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours')$q$),
  '23505', 'ES-01: mismo (empresa, actor, id) → violación de PK');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en)
  values ('aaaaaaaa-1111-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000002', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours')$q$),
  'OK', 'ES-01: el mismo id puede existir para otro actor (espacio de ids por actor, sin colisión ni fuga)');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en)
  values ('aaaaaaaa-1111-4000-8000-00000000000a', 'b1b1b1b1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours')$q$),
  '23503', 'ES-01: actor de otra empresa (perfiles) → FK');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en)
  values ('aaaaaaaa-1111-4000-8000-00000000000b', '99999999-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours')$q$),
  '23503', 'ES-01: empresa inexistente → FK');

-- RF-01: la FK compuesta rechaza operaciones de otro actor, otro tipo u otra empresa.
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, estado, operacion_id, resuelto_en)
  values ('aaaaaaaa-1111-4000-8000-00000000000c', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours',
          'confirmada', 'c0c0c0c0-0000-4000-8000-000000000003', now())$q$),
  '23503', 'RF-01: operación de OTRO ACTOR → violación de la FK compuesta');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, estado, operacion_id, resuelto_en)
  values ('aaaaaaaa-1111-4000-8000-00000000000d', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours',
          'confirmada', 'c0c0c0c0-0000-4000-8000-000000000002', now())$q$),
  '23503', 'RF-01: operación de OTRO TIPO (merma vs ingreso) → violación de la FK compuesta');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, estado, operacion_id, resuelto_en)
  values ('aaaaaaaa-1111-4000-8000-00000000000e', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours',
          'confirmada', 'c0c0c0c0-0000-4000-8000-000000000004', now())$q$),
  '23503', 'RF-01: operación de OTRA EMPRESA → violación de la FK compuesta');
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, estado, operacion_id, resuelto_en)
  values ('d0d0d0d0-0000-4000-8000-000000000006', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours',
          'confirmada', 'c0c0c0c0-0000-4000-8000-000000000006', now())$q$),
  'OK', 'RF-01: la operación de la misma empresa, actor y tipo sí se enlaza (control positivo)');

-- RF-07 / RF-02 / FK-N.
select is(pg_temp.err($q$insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, estado, operacion_id, resuelto_en)
  values ('aaaaaaaa-1111-4000-8000-00000000000f', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', clock_timestamp() + interval '24 hours',
          'confirmada', 'c0c0c0c0-0000-4000-8000-000000000001', now())$q$),
  '23505', 'RF-07: dos intenciones con la misma operación → violación de la UNIQUE');
select cmp_ok(
  (select count(*)::int from public.intenciones_operacion where operacion_id is null and estado = 'pendiente' and actor_id = 'a1a1a1a1-0000-4000-8000-000000000001'),
  '>=', 3,
  'RF-02/FK-N: varias pendientes con operacion_id NULL conviven (NULLS DISTINCT; la FK no se evalúa)');

-- RF-03 / RF-06b: invariante de la clave y la operación.
select is(
  (select count(*)::int from public.intenciones_operacion i
    where i.estado = 'confirmada'
      and not exists (select 1 from public.operaciones o
                       where o.id = i.operacion_id and o.idempotency_key = i.id and o.actor_id = i.actor_id)),
  0,
  'RF-03: para toda intención confirmada, operaciones.idempotency_key = intenciones_operacion.id');
select is(
  (select count(*)::int from public.operaciones where id = idempotency_key),
  0,
  'RF-06b: operaciones.id nunca coincide con la idempotency_key');

-- Reconocimientos: integridad (RF-05, FK-N, OC-1 estructural).
select is(pg_temp.err($q$insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id)
  values ('a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', null)$q$),
  '23502', 'RF-05: operacion_id nulo → NOT NULL');
select is(pg_temp.err($q$insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id)
  values ('a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'c0c0c0c0-0000-4000-8000-0000000000ff')$q$),
  '23503', 'RF-05: operacion_id inexistente → FK');
select is(pg_temp.err($q$insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id)
  values ('a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'c0c0c0c0-0000-4000-8000-000000000003')$q$),
  '23503', 'RF-05: operación de OTRA intención/actor (A2) bajo el actor A1 → FK');
select is(pg_temp.err($q$insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id)
  values ('b1b1b1b1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'c0c0c0c0-0000-4000-8000-000000000001')$q$),
  '23503', 'RF-05: empresa distinta de la de la intención → FK');
select is(pg_temp.err($q$insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id)
  values ('a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'c0c0c0c0-0000-4000-8000-000000000001')$q$),
  'OK', 'Reconocimiento válido de una confirmada (control positivo)');
select is(pg_temp.err($q$insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id)
  values ('a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'c0c0c0c0-0000-4000-8000-000000000001')$q$),
  '23505', 'Reconocimiento repetido sin ON CONFLICT → violación de la PK (1 marca por operación)');

-- ===========================================================================
-- D. Privilegios efectivos (ES-02): ninguno para la Data API; mínimos para propietario_rpc
-- ===========================================================================
select is(
  (select count(*)::int
     from (values ('public.intenciones_operacion'), ('public.intenciones_reconocimientos')) t(tabla),
          (values ('anon'), ('authenticated'), ('service_role'), ('lector_perfiles_rpc')) r(rol)
    where has_table_privilege(r.rol, t.tabla, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
       or has_any_column_privilege(r.rol, t.tabla, 'SELECT, INSERT, UPDATE, REFERENCES')),
  0,
  'ES-02/N-COL: anon, authenticated, service_role y lector_perfiles_rpc sin privilegio de tabla NI de columna (incluido SELECT por columna)');

select is(
  (select count(*)::int from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
    where c.oid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass) and a.grantee = 0),
  0,
  'ES-02: PUBLIC sin privilegios de tabla');

select is(
  (select count(*)::int from pg_attribute at, aclexplode(at.attacl) a
    where at.attrelid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass)
      and at.attnum > 0 and not at.attisdropped and a.grantee = 0),
  0,
  'ES-02: PUBLIC sin privilegios de columna');

select is(
  (select count(*)::int from pg_class c, aclexplode(c.relacl) a
    where c.oid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass)
      and a.grantee = (select oid from pg_roles where rolname = 'service_role')),
  0,
  'ES-02/P11: service_role no figura en la ACL de ninguna de las dos tablas (sin excepción nueva)');

select is(
  (select array_agg(c.relname::text || '=' || a.privilege_type order by c.relname, a.privilege_type)
     from pg_class c, aclexplode(c.relacl) a
    where c.oid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass)
      and a.grantee = (select oid from pg_roles where rolname = 'propietario_rpc')),
  array['intenciones_operacion=SELECT', 'intenciones_reconocimientos=SELECT'],
  'ES-02: propietario_rpc tiene a nivel de tabla SOLO SELECT (sin DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN ni INSERT/UPDATE de tabla)');

select is(
  (select array_agg(at.attname::text order by at.attname) from pg_attribute at
    where at.attrelid = 'public.intenciones_operacion'::regclass and at.attnum > 0 and not at.attisdropped
      and has_column_privilege('propietario_rpc', at.attrelid, at.attnum, 'INSERT')),
  array['actor_id', 'empresa_id', 'id', 'payload', 'tipo', 'vence_en'],
  'ES-02: INSERT de propietario_rpc en exactamente 6 columnas (estado, resultado y marcas las fija el servidor)');

select is(
  (select array_agg(at.attname::text order by at.attname) from pg_attribute at
    where at.attrelid = 'public.intenciones_operacion'::regclass and at.attnum > 0 and not at.attisdropped
      and has_column_privilege('propietario_rpc', at.attrelid, at.attnum, 'UPDATE')),
  array['codigo_rechazo', 'estado', 'operacion_id', 'resuelto_en'],
  'ES-02: UPDATE de propietario_rpc en exactamente 4 columnas');

select is(
  (select array_agg(at.attname::text order by at.attname) from pg_attribute at
    where at.attrelid = 'public.intenciones_reconocimientos'::regclass and at.attnum > 0 and not at.attisdropped
      and has_column_privilege('propietario_rpc', at.attrelid, at.attnum, 'INSERT')),
  array['actor_id', 'empresa_id', 'operacion_id'],
  'ES-02: INSERT en reconocimientos solo en 3 columnas (reconocido_en no se fija desde afuera)');

select is(
  (select count(*)::int from pg_attribute at
    where at.attrelid = 'public.intenciones_reconocimientos'::regclass and at.attnum > 0 and not at.attisdropped
      and has_column_privilege('propietario_rpc', at.attrelid, at.attnum, 'UPDATE')),
  0,
  'ES-02: reconocimientos es de solo inserción para propietario_rpc (sin UPDATE)');

select is(
  (select count(*)::int from pg_class c
    where c.oid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass)
      and c.relkind = 'r' and c.relowner = 'postgres'::regrole and c.relrowsecurity and not c.relforcerowsecurity),
  2,
  'ES-03/P4: owner postgres, RLS habilitada y SIN FORCE en las dos tablas');

select is(
  (select count(*)::int from pg_class c where c.relowner in (
     (select oid from pg_roles where rolname in ('propietario_rpc', 'lector_perfiles_rpc', 'anon', 'authenticated', 'service_role')))
     and c.relnamespace = 'public'::regnamespace),
  0,
  'P3: ningún rol técnico ni de la Data API es dueño de tablas de public (propietario_rpc no es dueño de las nuevas)');

-- ===========================================================================
-- E. Políticas RLS (ES-03)
-- ===========================================================================
select is(
  (select count(*)::int from pg_policy where polrelid = 'public.intenciones_operacion'::regclass), 3,
  'ES-03: exactamente 3 políticas en intenciones_operacion');
select is(
  (select count(*)::int from pg_policy where polrelid = 'public.intenciones_reconocimientos'::regclass), 2,
  'ES-03: exactamente 2 políticas en intenciones_reconocimientos');

select is(
  (select array_agg(p.polname::text || ':' || p.polcmd::text || ':' || p.polpermissive::text order by p.polname) from pg_policy p
    where p.polrelid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass)),
  array['intenciones_operacion_insert_propietario_rpc:a:true', 'intenciones_operacion_select_propietario_rpc:r:true',
        'intenciones_operacion_update_propietario_rpc:w:true',
        'intenciones_reconocimientos_insert_propietario_rpc:a:true', 'intenciones_reconocimientos_select_propietario_rpc:r:true'],
  'ES-03: nombres, comandos y modo (todas permisivas) de las cinco políticas');

select is(
  (select count(*)::int from pg_policy p
    where p.polrelid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass)
      and p.polroles <> array['propietario_rpc'::regrole]::oid[]),
  0,
  'ES-03: todas las políticas son exclusivamente para propietario_rpc; ninguna para authenticated, anon ni PUBLIC');

select is(
  (select count(*)::int from pg_policy where polrelid = 'public.intenciones_operacion'::regclass and polcmd = 'w'),
  1,
  'H2/ES-03: UNA sola política UPDATE en intenciones_operacion (ninguna permisiva adicional)');

select is(
  (select count(*)::int from pg_policy where polrelid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass) and polcmd in ('d', '*')),
  0,
  'ES-03: sin políticas DELETE ni ALL (retención indefinida)');

-- Hashes de USING/WITH CHECK con el mismo search_path del preflight.
select set_config('search_path', 'pg_catalog, pg_temp', true);
create temp table hashes_politicas as
select p.polname::text as politica,
       coalesce(encode(sha256(convert_to(pg_get_expr(p.polqual, p.polrelid), 'UTF8')), 'hex'), '-') as h_using,
       coalesce(encode(sha256(convert_to(pg_get_expr(p.polwithcheck, p.polrelid), 'UTF8')), 'hex'), '-') as h_check
  from pg_policy p
 where p.polrelid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass);
select set_config('search_path', '"$user", public, extensions', true);

select is(
  (select string_agg(politica || '|' || h_using || '|' || h_check, E'\n' order by politica) from hashes_politicas),
  E'intenciones_operacion_insert_propietario_rpc|-|1a8a0e8bffa9f1ac18c15a92580f8345d16275f4613bfc7545cece87d24da13e\n'
  'intenciones_operacion_select_propietario_rpc|1a8a0e8bffa9f1ac18c15a92580f8345d16275f4613bfc7545cece87d24da13e|-\n'
  'intenciones_operacion_update_propietario_rpc|69fec85de1026b60d96e011dc5fe329cfb8a42d4ac139543c1fa86431b9c1849|ac98a486361edc7027558c5eb6fc3abd301aba44a292bdb8dd8badac224e04c1\n'
  'intenciones_reconocimientos_insert_propietario_rpc|-|1b7e089f196e770f0c6e5eda43e936a05f19167ee56bd526e4aadd79510f22fd\n'
  'intenciones_reconocimientos_select_propietario_rpc|1b7e089f196e770f0c6e5eda43e936a05f19167ee56bd526e4aadd79510f22fd|-',
  'ES-03: hashes SHA-256 de USING/WITH CHECK de las cinco políticas (los mismos que fija el manifiesto del preflight)');

select is(
  (select count(*)::int from pg_policy p
    where p.polrelid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass)
      and (pg_get_expr(p.polqual, p.polrelid) ~* '(auth\.uid|uid\(\)|user_metadata|raw_user_meta|jwt)'
           or pg_get_expr(p.polwithcheck, p.polrelid) ~* '(auth\.uid|uid\(\)|user_metadata|raw_user_meta|jwt)')),
  0,
  'R-10/R-12: ninguna política usa auth.uid(), user_metadata ni claims directos; la identidad es solo privado.usuario_actual()');

select is(
  (select count(*)::int from pg_policy p
    where p.polrelid in ('public.intenciones_operacion'::regclass, 'public.intenciones_reconocimientos'::regclass)
      and p.polname not like '%\_propietario\_rpc'),
  0,
  'ES-03: nomenclatura de políticas coherente con el resto del esquema (<tabla>_<cmd>_propietario_rpc)');

-- ===========================================================================
-- F. Negativos de la Data API por rol (NG-05 nivel base): 42501, nunca filas ni vacío
-- ===========================================================================
create temp table roles_prueba (rol pg_catalog.text, uid pg_catalog.uuid, etiqueta pg_catalog.text);
insert into roles_prueba values
  ('anon',                null,                                       'anon'),
  ('authenticated',       'a1a1a1a1-0000-4000-8000-000000000001',     'dueño A'),
  ('authenticated',       'a1a1a1a1-0000-4000-8000-000000000002',     'encargado A'),
  ('authenticated',       'a1a1a1a1-0000-4000-8000-000000000003',     'vendedor/piloto A (otro rol)'),
  ('authenticated',       'b1b1b1b1-0000-4000-8000-000000000001',     'dueño B (otra empresa)'),
  ('service_role',        null,                                       'service_role'),
  ('lector_perfiles_rpc', null,                                       'lector_perfiles_rpc');

create temp table sentencias_prueba (tabla pg_catalog.text, op pg_catalog.text, sql pg_catalog.text);
insert into sentencias_prueba values
  ('intenciones_operacion', 'select',
     'select pg_catalog.count(*)::pg_catalog.text from public.intenciones_operacion'),
  ('intenciones_operacion', 'select columna',
     'select estado from public.intenciones_operacion limit 1'),
  ('intenciones_operacion', 'insert',
     'with i as (insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en) values (''bbbbbbbb-2222-4000-8000-000000000001'', ''a1a1a1a1-0000-4000-8000-000000000000'', ''a1a1a1a1-0000-4000-8000-000000000001'', ''ingreso'', ''{"x":1}'', pg_catalog.clock_timestamp() + interval ''24 hours'') returning 1) select pg_catalog.count(*)::pg_catalog.text from i'),
  ('intenciones_operacion', 'update',
     'with u as (update public.intenciones_operacion set estado = ''cancelada'' returning 1) select pg_catalog.count(*)::pg_catalog.text from u'),
  ('intenciones_operacion', 'delete',
     'with d as (delete from public.intenciones_operacion returning 1) select pg_catalog.count(*)::pg_catalog.text from d'),
  ('intenciones_reconocimientos', 'select',
     'select pg_catalog.count(*)::pg_catalog.text from public.intenciones_reconocimientos'),
  ('intenciones_reconocimientos', 'select columna',
     'select operacion_id from public.intenciones_reconocimientos limit 1'),
  ('intenciones_reconocimientos', 'insert',
     'with i as (insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id) values (''a1a1a1a1-0000-4000-8000-000000000000'', ''a1a1a1a1-0000-4000-8000-000000000001'', ''c0c0c0c0-0000-4000-8000-000000000005'') returning 1) select pg_catalog.count(*)::pg_catalog.text from i'),
  ('intenciones_reconocimientos', 'update',
     'with u as (update public.intenciones_reconocimientos set reconocido_en = pg_catalog.now() returning 1) select pg_catalog.count(*)::pg_catalog.text from u'),
  ('intenciones_reconocimientos', 'delete',
     'with d as (delete from public.intenciones_reconocimientos returning 1) select pg_catalog.count(*)::pg_catalog.text from d');

create temp table resultados_negativos as
select r.etiqueta, s.tabla, s.op, pg_temp.llamar(r.rol, r.uid, s.sql) as resultado
  from roles_prueba r cross join sentencias_prueba s;

select is((select count(*)::int from resultados_negativos), 70, 'NG-05: 7 roles × 10 operaciones directas evaluadas');
select is((select count(*)::int from resultados_negativos where resultado = 'ERR:42501'), 70,
  'NG-05: TODAS las operaciones directas (SELECT, SELECT por columna, INSERT, UPDATE, DELETE) de anon, dueño, encargado, vendedor/piloto, otra empresa, service_role y lector → 42501');
select is((select count(*)::int from resultados_negativos where resultado like 'OK:%'), 0,
  'NG-05: ninguna operación directa devuelve filas ni «0 filas» (nunca 200 []): la denegación es por privilegio');
select is((select count(*)::int from public.intenciones_reconocimientos), 1,
  'NG-05: tras los intentos directos, la tabla de reconocimientos conserva solo la fila sembrada (nada se escribió)');

-- ===========================================================================
-- G. propietario_rpc bajo RLS real (SECURITY DEFINER futuro): ES-03b, RX-01(b), aislamiento, OC-1
-- ===========================================================================
-- ES-03b: las terminales no cambian por ninguna vía.
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_operacion set estado = 'cancelada', operacion_id = null where id = 'd0d0d0d0-0000-4000-8000-000000000005' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'OK:0', 'ES-03b: confirmada → cancelada afecta 0 filas');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_operacion set estado = 'confirmada', codigo_rechazo = null, operacion_id = 'c0c0c0c0-0000-4000-8000-000000000007' where id = 'f0f0f0f0-0000-4000-8000-000000000008' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'OK:0', 'ES-03b: rechazada → confirmada afecta 0 filas');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_operacion set estado = 'pendiente', resuelto_en = null where id = 'f0f0f0f0-0000-4000-8000-000000000009' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'OK:0', 'ES-03b: cancelada → pendiente afecta 0 filas');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_operacion set resuelto_en = pg_catalog.clock_timestamp() where id = 'f0f0f0f0-0000-4000-8000-000000000009' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'OK:0', 'ES-03b: cancelada → cancelada (otro resuelto_en) afecta 0 filas');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_operacion set actor_id = 'a1a1a1a1-0000-4000-8000-000000000002' where id = 'f0f0f0f0-0000-4000-8000-000000000001' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'ERR:42501', 'ES-03b: cambiar el actor es imposible (sin privilegio de columna)');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_operacion set empresa_id = 'b1b1b1b1-0000-4000-8000-000000000000' where id = 'f0f0f0f0-0000-4000-8000-000000000001' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'ERR:42501', 'ES-03b: cambiar la empresa es imposible (sin privilegio de columna)');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_operacion set payload = '{"x":2}' where id = 'f0f0f0f0-0000-4000-8000-000000000001' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'ERR:42501', 'ES-03b: el payload almacenado no se puede modificar (sin privilegio de columna)');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_operacion set estado = 'pendiente', resuelto_en = null where id = 'f0f0f0f0-0000-4000-8000-000000000002' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'ERR:42501', 'ES-03b: pendiente → pendiente es rechazado por el WITH CHECK (el destino debe ser terminal)');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_operacion set estado = 'cancelada', resuelto_en = pg_catalog.clock_timestamp() where id = 'f0f0f0f0-0000-4000-8000-000000000001' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'OK:1', 'ES-03b (control positivo): pendiente → cancelada del propio actor afecta 1 fila');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_operacion set estado = 'confirmada', operacion_id = 'c0c0c0c0-0000-4000-8000-000000000007', resuelto_en = pg_catalog.clock_timestamp() where id = 'f0f0f0f0-0000-4000-8000-000000000002' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'OK:1', 'ES-03b (control positivo): pendiente → confirmada con operación de su actor y tipo afecta 1 fila');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000002',
  $q$with u as (update public.intenciones_operacion set estado = 'cancelada', resuelto_en = pg_catalog.clock_timestamp() where id = 'f0f0f0f0-0000-4000-8000-000000000003' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'OK:0', 'Aislamiento: otro actor de la misma empresa no puede transicionar la intención ajena (0 filas)');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with d as (delete from public.intenciones_operacion where id = 'f0f0f0f0-0000-4000-8000-000000000003' returning 1) select pg_catalog.count(*)::pg_catalog.text from d$q$),
  'ERR:42501', 'Retención indefinida: propietario_rpc no puede borrar intenciones (sin DELETE)');
select is((select estado from public.intenciones_operacion where id = 'd0d0d0d0-0000-4000-8000-000000000005'),
  'confirmada', 'ES-03b: la confirmada sigue confirmada tras los intentos');

-- Aislamiento de lectura por actor y por empresa; perfil inactivo.
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000002',
  $q$select pg_catalog.count(*)::pg_catalog.text from public.intenciones_operacion where actor_id <> 'a1a1a1a1-0000-4000-8000-000000000002'$q$),
  'OK:0', 'Aislamiento: el actor A2 no ve ninguna intención de otro actor de su misma empresa');
select is(pg_temp.llamar('propietario_rpc', 'b1b1b1b1-0000-4000-8000-000000000001',
  $q$select pg_catalog.count(*)::pg_catalog.text from public.intenciones_operacion where empresa_id <> 'b1b1b1b1-0000-4000-8000-000000000000'$q$),
  'OK:0', 'Aislamiento: un actor de la empresa B no ve intenciones de la empresa A');
select is(pg_temp.llamar('propietario_rpc', 'b1b1b1b1-0000-4000-8000-000000000001',
  $q$select pg_catalog.count(*)::pg_catalog.text from public.intenciones_operacion$q$),
  'OK:1', 'Aislamiento: el actor B1 ve exactamente su propia intención');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000004',
  $q$select pg_catalog.count(*)::pg_catalog.text from public.intenciones_operacion$q$),
  'OK:0', 'Perfil inactivo: no ve ni su propia intención (la política SELECT exige perfil activo)');
select is(pg_temp.llamar('propietario_rpc', null,
  $q$select pg_catalog.count(*)::pg_catalog.text from public.intenciones_operacion$q$),
  'OK:0', 'Sin identidad (usuario_actual() nulo): ninguna fila visible');

-- RX-01(b): inserciones cruzadas rechazadas por la política y por la FK.
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en) values ('bbbbbbbb-3333-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000002', 'ingreso', '{"x":1}', pg_catalog.clock_timestamp() + interval '24 hours') returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'ERR:42501', 'RX-01(b)/aislamiento: insertar con actor_id ≠ usuario_actual() → 42501 por política');
select is(pg_temp.llamar('propietario_rpc', 'b1b1b1b1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en) values ('bbbbbbbb-3333-4000-8000-000000000002', 'a1a1a1a1-0000-4000-8000-000000000000', 'b1b1b1b1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', pg_catalog.clock_timestamp() + interval '24 hours') returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'ERR:42501', 'Aislamiento: un actor de la empresa B no puede insertar una intención en la empresa A');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000004',
  $q$with i as (insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en) values ('bbbbbbbb-3333-4000-8000-000000000003', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000004', 'ingreso', '{"x":1}', pg_catalog.clock_timestamp() + interval '24 hours') returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'ERR:42501', 'Perfil inactivo: la política INSERT exige perfil activo → 42501');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en) values ('bbbbbbbb-3333-4000-8000-000000000004', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', pg_catalog.clock_timestamp() + interval '24 hours') returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'OK:1', 'Control positivo: el actor activo inserta su propia intención (estado pendiente por defecto)');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en, estado) values ('bbbbbbbb-3333-4000-8000-000000000005', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', '{"x":1}', pg_catalog.clock_timestamp() + interval '24 hours', 'confirmada') returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'ERR:42501', 'Sin privilegio de columna: no se puede insertar con estado explícito (lo fija el servidor)');

-- Reconocimientos bajo RLS real.
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id) values ('a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000002', 'c0c0c0c0-0000-4000-8000-000000000003') returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'ERR:42501', 'RX-01(b): reconocer a nombre de OTRO actor (actor_id ≠ usuario_actual()) → 42501 por política');
select is(pg_temp.llamar('propietario_rpc', 'b1b1b1b1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id) values ('a1a1a1a1-0000-4000-8000-000000000000', 'b1b1b1b1-0000-4000-8000-000000000001', 'c0c0c0c0-0000-4000-8000-000000000001') returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'ERR:42501', 'RX-01(b): reconocer desde otra empresa → 42501 por política');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id) values ('a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'c0c0c0c0-0000-4000-8000-000000000007') returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'OK:1', 'Reconocer una confirmada propia (op7, confirmada en este test) → 1 fila');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id) values ('a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'c0c0c0c0-0000-4000-8000-0000000000aa') returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'ERR:23503', 'RX-01(b): actor correcto pero operacion_id sin intención confirmada → 23503 por FK');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id, reconocido_en) values ('a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'c0c0c0c0-0000-4000-8000-000000000005', now() - interval '10 days') returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'ERR:42501', 'RF-05: reconocido_en no se puede fijar desde afuera (sin privilegio de columna)');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id) values ('a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'c0c0c0c0-0000-4000-8000-000000000001') on conflict do nothing returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'OK:0', 'OC-1: INSERT … ON CONFLICT DO NOTHING bajo RLS real y privilegio por columna es idempotente (0 filas nuevas)');
select is(
  (select count(*)::int from public.intenciones_reconocimientos where operacion_id = 'c0c0c0c0-0000-4000-8000-000000000001'),
  1, 'OC-1: sigue habiendo una sola marca por operación');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_reconocimientos set reconocido_en = pg_catalog.now() returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'ERR:42501', 'OC-1: la marca no se puede modificar (solo inserción: se conserva la primera)');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with d as (delete from public.intenciones_reconocimientos returning 1) select pg_catalog.count(*)::pg_catalog.text from d$q$),
  'ERR:42501', 'OC-1: la marca no se puede borrar');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000002',
  $q$select pg_catalog.count(*)::pg_catalog.text from public.intenciones_reconocimientos where actor_id <> 'a1a1a1a1-0000-4000-8000-000000000002'$q$),
  'OK:0', 'Aislamiento: el actor A2 no ve reconocimientos de otro actor');
select is(pg_temp.llamar('propietario_rpc', 'b1b1b1b1-0000-4000-8000-000000000001',
  $q$select pg_catalog.count(*)::pg_catalog.text from public.intenciones_reconocimientos$q$),
  'OK:0', 'Aislamiento: un actor de la empresa B no ve ningún reconocimiento de la empresa A');

-- Libros mayores inmutables (ADR-001, Blueprint §12 Seguridad).
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.operaciones set huella = huella returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'ERR:42501', 'Libros mayores: propietario_rpc sigue sin UPDATE sobre operaciones');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with d as (delete from public.movimientos_stock returning 1) select pg_catalog.count(*)::pg_catalog.text from d$q$),
  'ERR:42501', 'Libros mayores: propietario_rpc sigue sin DELETE sobre movimientos_stock');
select is(pg_temp.llamar('authenticated', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella) values ('a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'ingreso', 'bbbbbbbb-4444-4000-8000-000000000001', repeat('a', 64)) returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'ERR:42501', 'Libros mayores: authenticated no inserta operaciones por la Data API');

-- ===========================================================================
-- H. Protección pg_temp: dominios hostiles no se ejecutan en el camino de las tablas
-- ===========================================================================
create temp table sonda_log (quien pg_catalog.text);
grant insert on sonda_log to public;
create function pg_temp.sonda() returns pg_catalog.bool language plpgsql as $f$
begin
  insert into pg_temp.sonda_log values (current_user);
  return true;
end $f$;
create domain pg_temp.uuid  as pg_catalog.uuid  check (pg_temp.sonda());
create domain pg_temp.text  as pg_catalog.text  check (pg_temp.sonda());
create domain pg_temp.jsonb as pg_catalog.jsonb check (pg_temp.sonda());

-- Control positivo: una referencia SIN calificar a `text` desde una sesión con pg_temp primero SÍ la invoca.
do $$ begin perform 'x'::text; end $$;
select cmp_ok((select count(*)::int from sonda_log where quien = 'postgres'), '>=', 1,
  'pg_temp (control positivo): una referencia sin calificar a text SÍ ejecuta el dominio hostil (la sonda detecta el vector)');

select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with i as (insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en) values ('bbbbbbbb-5555-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000000', 'a1a1a1a1-0000-4000-8000-000000000001', 'merma', '{"x":1}', pg_catalog.clock_timestamp() + interval '24 hours') returning 1) select pg_catalog.count(*)::pg_catalog.text from i$q$),
  'OK:1', 'pg_temp: INSERT de propietario_rpc con dominios hostiles presentes sigue funcionando');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$with u as (update public.intenciones_operacion set estado = 'cancelada', resuelto_en = pg_catalog.clock_timestamp() where id = 'bbbbbbbb-5555-4000-8000-000000000001' returning 1) select pg_catalog.count(*)::pg_catalog.text from u$q$),
  'OK:1', 'pg_temp: UPDATE de propietario_rpc (políticas, CHECK) con dominios hostiles presentes');
select is(pg_temp.llamar('propietario_rpc', 'a1a1a1a1-0000-4000-8000-000000000001',
  $q$select pg_catalog.count(*)::pg_catalog.text from public.intenciones_operacion where id = 'bbbbbbbb-5555-4000-8000-000000000001'$q$),
  'OK:1', 'pg_temp: SELECT de propietario_rpc (política SELECT, usuario_actual()) con dominios hostiles presentes');
select is((select count(*)::int from sonda_log where quien = 'propietario_rpc'), 0,
  'pg_temp: la sonda NO se ejecutó como propietario_rpc: ni los CHECK, ni las FK ni las políticas resuelven nombres en pg_temp');
select is((select count(*)::int from sonda_log where quien = 'authenticated'), 0,
  'pg_temp: la sonda tampoco se ejecutó como authenticated');

select * from finish();

rollback;
