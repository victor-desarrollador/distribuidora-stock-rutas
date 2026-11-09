-- pgTAP: ejecutar_intencion_operacion y cancelar_intencion_operacion — corte C1.2a
-- (ADR-010 v1.0 §5.6/§5.7/§5.8, anexo v1.1 §4 (H1) y §13, aclaración C1.2a-D1;
-- ADR-001 Topología D, P11; Blueprint §12). Migración
-- 20261111120100_rpc_intenciones_nucleo.sql.
--
-- Cubre (D = determinista, S = estática): EJ-01…08 para ingreso, a_cuarentena y
-- merma con las RPC de stock REALES, los ocho rechazos de la lista cerrada que
-- son alcanzables, errores relanzados (la intención sigue pendiente), VE-01…07
-- (vencidas), SD-01/02/03, SIM-01 (matriz estado × escenario contra ambas),
-- H1-P2/H1-P3, AU-01/02, NG-01…04 para ambas, RF-03/RF-06b/c/INV-01 con
-- confirmadas generadas por `ejecutar` real, libros mayores y ES-05 estática.
--
-- NO cubre (se declara): carreras entre sesiones (CC-*), R13-E (cambio de nivel
-- de aislamiento, imposible dentro de esta transacción) ni la clase I (TT-01/02,
-- AU-03): se miden en un arnés aparte o quedan para C1.3. Código stock_cantidad_
-- invalida: no alcanzable (crear exige cantidad >= 1).
-- La RPC `reconocer` llega en C1.2b: los reconocimientos se siembran por SQL.
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(92);

-- ---------------------------------------------------------------------------
-- Ayudantes (tipos calificados)
-- ---------------------------------------------------------------------------
-- llamar(rol, claims, sentencia): ejecuta UNA sentencia escalar bajo el rol y los
-- claims indicados; devuelve 'OK:<valor>' o 'ERR:<sqlstate>:<mensaje>'.
create function pg_temp.llamar(p_rol pg_catalog.text, p_claims pg_catalog.jsonb, p_sql pg_catalog.text)
returns pg_catalog.text language plpgsql as $f$
declare
  v pg_catalog.text;
  m pg_catalog.text;
begin
  perform pg_catalog.set_config('request.jwt.claims', coalesce(p_claims::pg_catalog.text, ''), true);
  execute pg_catalog.format('set local role %I', p_rol);
  begin
    execute p_sql into v;
    v := 'OK:' || coalesce(v, 'NULL');
  exception when others then
    get stacked diagnostics m = message_text;
    v := 'ERR:' || sqlstate || ':' || m;
  end;
  reset role;
  return v;
end $f$;

create function pg_temp.cl(p_uid pg_catalog.text) returns pg_catalog.jsonb language sql as $f$
  select pg_catalog.jsonb_build_object('sub', p_uid, 'role', 'authenticated')
$f$;

-- crear(uid, id, tipo, payload) como authenticated, por la fachada pública.
create function pg_temp.crear(p_uid pg_catalog.text, p_id pg_catalog.text, p_tipo pg_catalog.text, p_payload pg_catalog.text)
returns pg_catalog.text language sql as $f$
  select pg_temp.llamar('authenticated', pg_temp.cl(p_uid),
    pg_catalog.format('select public.crear_intencion_operacion(%L::uuid, %L::text, %L::jsonb)::text', p_id, p_tipo, p_payload))
$f$;

create function pg_temp.ejecutar(p_uid pg_catalog.text, p_id pg_catalog.text)
returns pg_catalog.text language sql as $f$
  select pg_temp.llamar('authenticated', pg_temp.cl(p_uid),
    pg_catalog.format($q$select e.estado || '|' || coalesce(e.operacion_id::pg_catalog.text, '-') || '|' || coalesce(e.codigo_rechazo, '-')
                          from public.ejecutar_intencion_operacion(%L::uuid) e$q$, p_id))
$f$;

create function pg_temp.cancelar(p_uid pg_catalog.text, p_id pg_catalog.text)
returns pg_catalog.text language sql as $f$
  select pg_temp.llamar('authenticated', pg_temp.cl(p_uid),
    pg_catalog.format('select public.cancelar_intencion_operacion(%L::uuid)::pg_catalog.text', p_id))
$f$;

-- Siembra como propietario: intención con estado y marcas coherentes (CHECK).
create function pg_temp.sembrar(p_actor pg_catalog.uuid, p_id pg_catalog.uuid, p_tipo pg_catalog.text,
                                p_estado pg_catalog.text default 'pendiente',
                                p_creado pg_catalog.timestamptz default pg_catalog.clock_timestamp())
returns pg_catalog.void language plpgsql as $f$
declare
  v_emp pg_catalog.uuid;
  v_op pg_catalog.uuid;
  v_payload pg_catalog.jsonb;
begin
  select empresa_id into v_emp from public.perfiles where usuario_id = p_actor;
  v_payload := case p_tipo
    when 'ingreso' then '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","cantidad":5,"motivo":null}'::pg_catalog.jsonb
    when 'a_cuarentena' then '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"a5a5a5a5-0000-4000-8000-0000000000d1","cantidad":5,"motivo":"x"}'::pg_catalog.jsonb
    else '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"a5a5a5a5-0000-4000-8000-0000000000d1","cantidad":5,"motivo_codigo":"vencido","motivo":null}'::pg_catalog.jsonb
  end;
  if p_estado = 'confirmada' then
    insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values (v_emp, p_actor, p_tipo, p_id, pg_catalog.repeat('a', 64))
    returning id into v_op;
  end if;
  insert into public.intenciones_operacion
    (id, empresa_id, actor_id, tipo, payload, estado, operacion_id, codigo_rechazo, creado_en, vence_en, resuelto_en)
  values (p_id, v_emp, p_actor, p_tipo, v_payload, p_estado, v_op,
          case when p_estado = 'rechazada' then 'stock_insuficiente' end,
          p_creado, p_creado + '24 hours'::pg_catalog.interval,
          case when p_estado <> 'pendiente' then p_creado + '1 minute'::pg_catalog.interval end);
end $f$;

-- Siembra de un reconocimiento (la RPC `reconocer` llega en C1.2b).
create function pg_temp.reconocer_sql(p_actor pg_catalog.uuid, p_id pg_catalog.uuid)
returns pg_catalog.void language plpgsql as $f$
begin
  insert into public.intenciones_reconocimientos (empresa_id, actor_id, operacion_id)
  select i.empresa_id, i.actor_id, i.operacion_id from public.intenciones_operacion i
   where i.actor_id = p_actor and i.id = p_id and i.estado = 'confirmada';
end $f$;

create function pg_temp.n_int() returns pg_catalog.int8 language sql as $f$
  select pg_catalog.count(*) from public.intenciones_operacion
$f$;
create function pg_temp.huella_libros() returns pg_catalog.text language sql as $f$
  select (select pg_catalog.count(*) from public.operaciones)::pg_catalog.text || '/'
      || (select pg_catalog.count(*) from public.movimientos_stock)::pg_catalog.text
$f$;

-- ---------------------------------------------------------------------------
-- Datos sintéticos
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('a5a5a5a5-0000-4000-8000-000000000000', 'Empresa A (test ejecutar)'),
  ('b5b5b5b5-0000-4000-8000-000000000000', 'Empresa B (test ejecutar)'),
  ('c5c5c5c5-0000-4000-8000-000000000000', 'Empresa C sin cuarentena (test ejecutar)');
insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('a5a5a5a5-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ej.a1@usuarios.distribuidora.invalid', '{}'),
  ('a5a5a5a5-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'ej.a2@usuarios.distribuidora.invalid', '{}'),
  ('a5a5a5a5-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'ej.a3@usuarios.distribuidora.invalid', '{}'),
  ('a5a5a5a5-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'ej.a4@usuarios.distribuidora.invalid', '{}'),
  ('a5a5a5a5-0000-4000-8000-0000000000f1', 'authenticated', 'authenticated', 'ej.x1@usuarios.distribuidora.invalid',
     '{"rol":"dueno","empresa_id":"a5a5a5a5-0000-4000-8000-000000000000"}'),
  ('b5b5b5b5-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ej.b1@usuarios.distribuidora.invalid', '{}'),
  ('c5c5c5c5-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ej.c1@usuarios.distribuidora.invalid', '{}');
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('a5a5a5a5-0000-4000-8000-000000000001', 'a5a5a5a5-0000-4000-8000-000000000000', 'ej.a1', 'Dueño A', 'dueno', true),
  ('a5a5a5a5-0000-4000-8000-000000000002', 'a5a5a5a5-0000-4000-8000-000000000000', 'ej.a2', 'Encargado A', 'encargado', true),
  ('a5a5a5a5-0000-4000-8000-000000000003', 'a5a5a5a5-0000-4000-8000-000000000000', 'ej.a3', 'Vendedor A', 'vendedor_piloto', true),
  ('a5a5a5a5-0000-4000-8000-000000000004', 'a5a5a5a5-0000-4000-8000-000000000000', 'ej.a4', 'Dueño inactivo A', 'dueno', false),
  ('b5b5b5b5-0000-4000-8000-000000000001', 'b5b5b5b5-0000-4000-8000-000000000000', 'ej.b1', 'Dueño B', 'dueno', true),
  ('c5c5c5c5-0000-4000-8000-000000000001', 'c5c5c5c5-0000-4000-8000-000000000000', 'ej.c1', 'Dueño C', 'dueno', true);
insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, activo, creado_por) values
  ('a5a5a5a5-0000-4000-8000-0000000000f1', 'a5a5a5a5-0000-4000-8000-000000000000', 'EJ-A1', 'Leche A', 'lacteos', 'unidad', 100, true, 'a5a5a5a5-0000-4000-8000-000000000001'),
  ('a5a5a5a5-0000-4000-8000-0000000000f2', 'a5a5a5a5-0000-4000-8000-000000000000', 'EJ-A2', 'Inactivo A', 'lacteos', 'unidad', 100, false, 'a5a5a5a5-0000-4000-8000-000000000001'),
  ('b5b5b5b5-0000-4000-8000-0000000000f1', 'b5b5b5b5-0000-4000-8000-000000000000', 'EJ-B1', 'Leche B', 'lacteos', 'unidad', 100, true, 'b5b5b5b5-0000-4000-8000-000000000001'),
  ('c5c5c5c5-0000-4000-8000-0000000000f1', 'c5c5c5c5-0000-4000-8000-000000000000', 'EJ-C1', 'Leche C', 'lacteos', 'unidad', 100, true, 'c5c5c5c5-0000-4000-8000-000000000001');
insert into public.ubicaciones (id, empresa_id, tipo, camion_id) values
  ('a5a5a5a5-0000-4000-8000-0000000000d1', 'a5a5a5a5-0000-4000-8000-000000000000', 'deposito', null),
  ('a5a5a5a5-0000-4000-8000-0000000000d2', 'a5a5a5a5-0000-4000-8000-000000000000', 'cuarentena', null),
  ('b5b5b5b5-0000-4000-8000-0000000000d1', 'b5b5b5b5-0000-4000-8000-000000000000', 'deposito', null),
  ('b5b5b5b5-0000-4000-8000-0000000000d2', 'b5b5b5b5-0000-4000-8000-000000000000', 'cuarentena', null),
  ('c5c5c5c5-0000-4000-8000-0000000000d1', 'c5c5c5c5-0000-4000-8000-000000000000', 'deposito', null);

-- Stock inicial por la RPC real (directa): A 50 de Leche A en depósito; C 5.
select pg_temp.llamar('authenticated', pg_temp.cl('a5a5a5a5-0000-4000-8000-000000000001'),
  $q$select public.registrar_ingreso('10000000-0000-4000-8000-000000000001', 'a5a5a5a5-0000-4000-8000-0000000000f1', 50)::text$q$);
select pg_temp.llamar('authenticated', pg_temp.cl('c5c5c5c5-0000-4000-8000-000000000001'),
  $q$select public.registrar_ingreso('10000000-0000-4000-8000-000000000002', 'c5c5c5c5-0000-4000-8000-0000000000f1', 5)::text$q$);

create function pg_temp.saldo(p_ub pg_catalog.uuid) returns pg_catalog.int8 language sql as $f$
  select coalesce(sum(case when ubicacion_destino_id = p_ub then cantidad::pg_catalog.int8 else 0 end), 0)
       - coalesce(sum(case when ubicacion_origen_id = p_ub then cantidad::pg_catalog.int8 else 0 end), 0)
    from public.movimientos_stock where producto_id = 'a5a5a5a5-0000-4000-8000-0000000000f1'
$f$;
create function pg_temp.op_de(p_id pg_catalog.text) returns pg_catalog.uuid language sql as $f$
  select operacion_id from public.intenciones_operacion where id = p_id::pg_catalog.uuid and actor_id in
    ('a5a5a5a5-0000-4000-8000-000000000001','a5a5a5a5-0000-4000-8000-000000000002','c5c5c5c5-0000-4000-8000-000000000001')
$f$;
create function pg_temp.n_ops(p_clave pg_catalog.text) returns pg_catalog.int8 language sql as $f$
  select pg_catalog.count(*) from public.operaciones where idempotency_key = p_clave::pg_catalog.uuid
$f$;
create function pg_temp.n_movs(p_op pg_catalog.uuid) returns pg_catalog.int8 language sql as $f$
  select pg_catalog.count(*) from public.movimientos_stock where operacion_id = p_op
$f$;
-- codigos(funcion, uid, ids): SQLSTATE (o OK) de cada llamada, separados por coma.
create function pg_temp.codigos(p_func pg_catalog.text, p_uid pg_catalog.text, p_ids pg_catalog.text[])
returns pg_catalog.text language plpgsql as $f$
declare
  v_id pg_catalog.text;
  v_res pg_catalog.text;
  v_out pg_catalog.text[] := '{}';
begin
  foreach v_id in array p_ids loop
    v_res := case p_func when 'ejecutar' then pg_temp.ejecutar(p_uid, v_id) else pg_temp.cancelar(p_uid, v_id) end;
    v_out := v_out || case when v_res like 'ERR:%' then pg_catalog.split_part(v_res, ':', 2) else 'OK' end;
  end loop;
  return pg_catalog.array_to_string(v_out, ',');
end $f$;
-- caso_rechazo: crear + ejecutar de una intención que el negocio rechaza.
create function pg_temp.caso_rechazo(p_n pg_catalog.int4, p_tipo pg_catalog.text, p_payload pg_catalog.text, p_codigo pg_catalog.text)
returns pg_catalog.text language plpgsql as $f$
declare
  v_id pg_catalog.text := 'd5d5d5d5-0000-4000-8000-' || pg_catalog.lpad(p_n::pg_catalog.text, 12, '0');
  v_r pg_catalog.text;
  v_e1 pg_catalog.text;
  v_e2 pg_catalog.text;
  v_libros pg_catalog.text := pg_temp.huella_libros();
  v_fila pg_catalog.text;
  v_out pg_catalog.text := '';
begin
  v_r := pg_temp.crear('a5a5a5a5-0000-4000-8000-000000000001', v_id, p_tipo, p_payload);
  if v_r is distinct from 'OK:' || v_id then v_out := v_out || 'crear=' || v_r || ';'; end if;
  v_libros := pg_temp.huella_libros();
  v_e1 := pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', v_id);
  if v_e1 is distinct from 'OK:rechazada|-|' || p_codigo then v_out := v_out || 'ejecutar=' || v_e1 || ';'; end if;
  v_e2 := pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', v_id);
  if v_e2 is distinct from v_e1 then v_out := v_out || 'replay=' || v_e2 || ';'; end if;
  select i.estado || '|' || coalesce(i.codigo_rechazo, '-') || '|' || (i.operacion_id is null)::pg_catalog.text || '|' || (i.resuelto_en is not null)::pg_catalog.text
    into v_fila from public.intenciones_operacion i where i.id = v_id::pg_catalog.uuid and i.actor_id = 'a5a5a5a5-0000-4000-8000-000000000001';
  if v_fila is distinct from 'rechazada|' || p_codigo || '|true|true' then v_out := v_out || 'fila=' || coalesce(v_fila, 'null') || ';'; end if;
  if pg_temp.n_ops(v_id) <> 0 or pg_temp.huella_libros() is distinct from v_libros then v_out := v_out || 'libros;'; end if;
  return v_out;
end $f$;

create temp table k (nombre pg_catalog.text primary key, v pg_catalog.text);
insert into k values
  ('P',  'a5a5a5a5-0000-4000-8000-0000000000f1'),
  ('D',  'a5a5a5a5-0000-4000-8000-0000000000d1'),
  ('Q',  'a5a5a5a5-0000-4000-8000-0000000000d2');
grant select on k to public;
create temp table res (clave pg_catalog.text primary key, valor pg_catalog.text);
create temp sequence s_sd03e; create temp sequence s_sd03c; create temp sequence s_h1p2e; create temp sequence s_h1p2c;

-- ===========================================================================
-- 1. EJ-01: ingreso por la ruta real crear → ejecutar
-- ===========================================================================
select is(pg_temp.crear('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001', 'ingreso',
    '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","cantidad":7,"motivo":"Remito 1"}'),
  'OK:11111111-0000-4000-8000-000000000001', 'EJ-01: crear ingreso');
insert into res select 'e1', pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001');
select alike((select valor from res where clave = 'e1'), 'OK:confirmada|%|-', 'EJ-01: ejecutar ingreso → confirmada con operacion_id y sin código');
select is(
  (select estado || '|' || (operacion_id = pg_temp.op_de('11111111-0000-4000-8000-000000000001'))::text || '|' || (resuelto_en is not null)::text || '|' || (codigo_rechazo is null)::text
     from public.intenciones_operacion where id = '11111111-0000-4000-8000-000000000001' and actor_id = 'a5a5a5a5-0000-4000-8000-000000000001'),
  'confirmada|true|true|true', 'EJ-01: la intención queda confirmada con operacion_id y resuelto_en');
select is(
  (select o.tipo || '|' || o.actor_id::text || '|' || (o.id <> o.idempotency_key)::text
     from public.operaciones o where o.id = pg_temp.op_de('11111111-0000-4000-8000-000000000001')),
  'ingreso|a5a5a5a5-0000-4000-8000-000000000001|true', 'RF-03: la operación es de tipo ingreso, del actor, y su id ≠ la clave (P15)');
select is(pg_temp.n_ops('11111111-0000-4000-8000-000000000001'), 1::bigint, 'RF-03: exactamente 1 operación con idempotency_key = id de la intención');
select is(
  (select tipo_movimiento || '|' || cantidad::text || '|' || ubicacion_destino_id::text || '|' || coalesce(ubicacion_origen_id::text, '-')
     from public.movimientos_stock where operacion_id = pg_temp.op_de('11111111-0000-4000-8000-000000000001')),
  'ingreso|7|a5a5a5a5-0000-4000-8000-0000000000d1|-', 'EJ-01: un movimiento de ingreso de 7 al depósito');
select is(pg_temp.saldo('a5a5a5a5-0000-4000-8000-0000000000d1'), 57::bigint, 'EJ-01: saldo del depósito 50 + 7');
create temp table libros1 as select pg_temp.huella_libros() as h;
select is(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001'),
  (select valor from res where clave = 'e1'), 'EJ-02: ejecutar repetido devuelve lo almacenado (idempotente)');
select is(pg_temp.huella_libros(), (select h from libros1), 'EJ-02: el replay no duplica operaciones ni movimientos');
select pg_temp.reconocer_sql('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001');

-- ===========================================================================
-- 2. a_cuarentena y merma con las RPC reales (EJ-03)
-- ===========================================================================
select is(pg_temp.crear('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000002', 'a_cuarentena',
    '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"a5a5a5a5-0000-4000-8000-0000000000d1","cantidad":3,"motivo":"Golpeado"}'),
  'OK:11111111-0000-4000-8000-000000000002', 'EJ-03: crear a_cuarentena');
insert into res select 'e2', pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000002');
select alike((select valor from res where clave = 'e2'), 'OK:confirmada|%|-', 'EJ-03: ejecutar a_cuarentena → confirmada');
select is(
  (select tipo_movimiento || '|' || cantidad::text || '|' || ubicacion_origen_id::text || '|' || ubicacion_destino_id::text
     from public.movimientos_stock where operacion_id = pg_temp.op_de('11111111-0000-4000-8000-000000000002')),
  'a_cuarentena|3|a5a5a5a5-0000-4000-8000-0000000000d1|a5a5a5a5-0000-4000-8000-0000000000d2', 'EJ-03: un movimiento a_cuarentena de depósito a cuarentena');
select is(pg_temp.saldo('a5a5a5a5-0000-4000-8000-0000000000d1') || '/' || pg_temp.saldo('a5a5a5a5-0000-4000-8000-0000000000d2'), '54/3',
  'EJ-03: saldos depósito 54 y cuarentena 3');
select is(pg_temp.n_ops('11111111-0000-4000-8000-000000000002'), 1::bigint, 'RF-03: 1 operación para la intención de cuarentena');

select is(pg_temp.crear('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000003', 'merma',
    '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"a5a5a5a5-0000-4000-8000-0000000000d1","cantidad":2,"motivo_codigo":"vencido","motivo":null}'),
  'OK:11111111-0000-4000-8000-000000000003', 'EJ-03: crear merma');
insert into res select 'e3', pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000003');
select alike((select valor from res where clave = 'e3'), 'OK:confirmada|%|-', 'EJ-03: ejecutar merma → confirmada');
select is(
  (select tipo_movimiento || '|' || cantidad::text || '|' || ubicacion_origen_id::text || '|' || coalesce(ubicacion_destino_id::text, '-') || '|' || motivo_codigo
     from public.movimientos_stock where operacion_id = pg_temp.op_de('11111111-0000-4000-8000-000000000003')),
  'merma|2|a5a5a5a5-0000-4000-8000-0000000000d1|-|vencido', 'EJ-03: un movimiento de merma con su código');
select is(pg_temp.saldo('a5a5a5a5-0000-4000-8000-0000000000d1'), 52::bigint, 'EJ-03: saldo del depósito 52');
select pg_temp.reconocer_sql('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000002');
select pg_temp.reconocer_sql('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000003');

-- Encargado: gestiona sus propias intenciones.
select pg_temp.crear('a5a5a5a5-0000-4000-8000-000000000002', '11111111-0000-4000-8000-000000000004', 'ingreso',
  '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","cantidad":1,"motivo":null}') is not null;
select alike(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000002', '11111111-0000-4000-8000-000000000004'), 'OK:confirmada|%|-',
  'EJ-01: el encargado ejecuta su propia intención');
select pg_temp.reconocer_sql('a5a5a5a5-0000-4000-8000-000000000002', '11111111-0000-4000-8000-000000000004');

-- ===========================================================================
-- 3. Rechazos de negocio de la lista cerrada → estado `rechazada` (HTTP 200)
-- ===========================================================================
select is(pg_temp.caso_rechazo(1, 'merma', '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"a5a5a5a5-0000-4000-8000-0000000000d1","cantidad":9999,"motivo_codigo":"vencido","motivo":null}', 'stock_insuficiente'), '',
  'EJ-04: merma sin stock → rechazada stock_insuficiente (sin operación ni movimiento; replay idéntico)');
select is(pg_temp.caso_rechazo(2, 'a_cuarentena', '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"a5a5a5a5-0000-4000-8000-0000000000d1","cantidad":9999,"motivo":"x"}', 'stock_insuficiente'), '',
  'EJ-04: a_cuarentena sin stock → rechazada stock_insuficiente');
select is(pg_temp.caso_rechazo(3, 'ingreso', '{"producto_id":"b5b5b5b5-0000-4000-8000-0000000000f1","cantidad":1,"motivo":null}', 'stock_producto_no_encontrado'), '',
  'EJ-04: producto de otra empresa → rechazada stock_producto_no_encontrado');
select is(pg_temp.caso_rechazo(4, 'merma', '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"00000000-0000-4000-8000-00000000beef","cantidad":1,"motivo_codigo":"vencido","motivo":null}', 'stock_ubicacion_no_encontrada'), '',
  'EJ-04: ubicación inexistente → rechazada stock_ubicacion_no_encontrada');
select is(pg_temp.caso_rechazo(5, 'ingreso', '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f2","cantidad":1,"motivo":null}', 'stock_producto_inactivo'), '',
  'EJ-04: producto inactivo → rechazada stock_producto_inactivo');
select is(pg_temp.caso_rechazo(6, 'a_cuarentena', '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"a5a5a5a5-0000-4000-8000-0000000000d1","cantidad":1,"motivo":null}', 'stock_motivo_invalido'), '',
  'EJ-04: cuarentena sin motivo → rechazada stock_motivo_invalido');
select is(pg_temp.caso_rechazo(7, 'merma', '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"a5a5a5a5-0000-4000-8000-0000000000d1","cantidad":1,"motivo_codigo":"zzz","motivo":null}', 'stock_motivo_invalido'), '',
  'EJ-04: código de merma fuera del catálogo → rechazada stock_motivo_invalido');
select is(pg_temp.caso_rechazo(8, 'a_cuarentena', '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"a5a5a5a5-0000-4000-8000-0000000000d2","cantidad":1,"motivo":"x"}', 'stock_origen_invalido'), '',
  'EJ-04: origen = cuarentena → rechazada stock_origen_invalido');

-- stock_conflicto_idempotencia: el mismo actor usó la clave directamente con otro payload.
select pg_temp.llamar('authenticated', pg_temp.cl('a5a5a5a5-0000-4000-8000-000000000001'),
  $q$select public.registrar_ingreso('d6d6d6d6-0000-4000-8000-000000000001', 'a5a5a5a5-0000-4000-8000-0000000000f1', 5)::text$q$) is not null;
select is(pg_temp.crear('a5a5a5a5-0000-4000-8000-000000000001', 'd6d6d6d6-0000-4000-8000-000000000001', 'ingreso',
    '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","cantidad":6,"motivo":null}'), 'OK:d6d6d6d6-0000-4000-8000-000000000001', 'EJ-04: crear con una clave ya usada directamente');
create temp table libros2 as select pg_temp.huella_libros() as h;
select is(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', 'd6d6d6d6-0000-4000-8000-000000000001'),
  'OK:rechazada|-|stock_conflicto_idempotencia', 'EJ-04: payload distinto sobre una clave existente → rechazada stock_conflicto_idempotencia');
select is(pg_temp.huella_libros(), (select h from libros2), 'EJ-04: el conflicto no crea operación ni movimiento nuevos');
-- Replay compatible: la intención adopta la operación directa previa (ADR-010 §5.11).
select pg_temp.llamar('authenticated', pg_temp.cl('a5a5a5a5-0000-4000-8000-000000000001'),
  $q$select public.registrar_ingreso('d6d6d6d6-0000-4000-8000-000000000002', 'a5a5a5a5-0000-4000-8000-0000000000f1', 5)::text$q$) is not null;
select pg_temp.crear('a5a5a5a5-0000-4000-8000-000000000001', 'd6d6d6d6-0000-4000-8000-000000000002', 'ingreso',
  '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","cantidad":5,"motivo":null}') is not null;
create temp table libros3 as select pg_temp.huella_libros() as h;
select alike(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', 'd6d6d6d6-0000-4000-8000-000000000002'), 'OK:confirmada|%|-',
  'EJ-02: payload idéntico a una operación directa previa → confirmada con esa operación');
select is(pg_temp.huella_libros(), (select h from libros3), 'EJ-02: sin operación ni movimiento duplicados (una sola operación efectiva)');
select pg_temp.reconocer_sql('a5a5a5a5-0000-4000-8000-000000000001', 'd6d6d6d6-0000-4000-8000-000000000002');

-- ===========================================================================
-- 4. Errores que no son rechazo de negocio: se relanzan y la intención sigue pendiente
-- ===========================================================================
select pg_temp.crear('c5c5c5c5-0000-4000-8000-000000000001', 'e6e6e6e6-0000-4000-8000-000000000001', 'a_cuarentena',
  '{"producto_id":"c5c5c5c5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"c5c5c5c5-0000-4000-8000-0000000000d1","cantidad":1,"motivo":"x"}') is not null;
select is(pg_temp.ejecutar('c5c5c5c5-0000-4000-8000-000000000001', 'e6e6e6e6-0000-4000-8000-000000000001'),
  'ERR:PT500:stock_ubicacion_no_configurada', 'EJ-05: PT500 de la RPC de negocio (empresa sin cuarentena) se relanza, no se vuelve rechazo');
select is((select estado || '|' || (operacion_id is null)::text || '|' || (resuelto_en is null)::text from public.intenciones_operacion where id = 'e6e6e6e6-0000-4000-8000-000000000001'),
  'pendiente|true|true', 'EJ-05: la intención sigue pendiente, sin escribir');
select is(pg_temp.n_ops('e6e6e6e6-0000-4000-8000-000000000001'), 0::bigint, 'EJ-05: sin operación (la subtransacción se revirtió)');

select pg_temp.crear('a5a5a5a5-0000-4000-8000-000000000002', 'e6e6e6e6-0000-4000-8000-000000000002', 'merma',
  '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","ubicacion_origen_id":"a5a5a5a5-0000-4000-8000-0000000000d1","cantidad":1,"motivo_codigo":"vencido","motivo":null}') is not null;
update public.perfiles set rol = 'vendedor_piloto' where usuario_id = 'a5a5a5a5-0000-4000-8000-000000000002';
select is(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000002', 'e6e6e6e6-0000-4000-8000-000000000002'),
  'ERR:PT403:intencion_no_autorizado', 'EJ-06: rol perdido entre crear y ejecutar → PT403 (la intención no otorga autoridad)');
update public.perfiles set rol = 'encargado', activo = false where usuario_id = 'a5a5a5a5-0000-4000-8000-000000000002';
select is(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000002', 'e6e6e6e6-0000-4000-8000-000000000002'),
  'ERR:PT403:intencion_no_autorizado', 'EJ-06/AU-01: perfil inactivado → PT403 (no PT404)');
update public.perfiles set activo = true where usuario_id = 'a5a5a5a5-0000-4000-8000-000000000002';
select is((select estado from public.intenciones_operacion where id = 'e6e6e6e6-0000-4000-8000-000000000002'), 'pendiente',
  'EJ-06: la intención siguió pendiente tras los PT403');
select alike(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000002', 'e6e6e6e6-0000-4000-8000-000000000002'), 'OK:confirmada|%|-',
  'EJ-06: restituido el perfil, la misma intención se ejecuta una sola vez');
select pg_temp.reconocer_sql('a5a5a5a5-0000-4000-8000-000000000002', 'e6e6e6e6-0000-4000-8000-000000000002');

select is(pg_temp.llamar('authenticated', '{"role":"authenticated"}', $q$select public.cancelar_intencion_operacion('11111111-0000-4000-8000-000000000001')::text$q$),
  'ERR:PT401:intencion_no_autenticado', 'EJ-04: cancelar sin identidad → PT401');
select is(pg_temp.llamar('authenticated', '{"role":"authenticated"}', $q$select e.estado from public.ejecutar_intencion_operacion('11111111-0000-4000-8000-000000000001') e$q$),
  'ERR:PT401:intencion_no_autenticado', 'EJ-04: ejecutar sin identidad → PT401');

-- ===========================================================================
-- 5. Vencidas y cancelación (VE-01…07, SIM-01d)
-- ===========================================================================
select pg_temp.crear('a5a5a5a5-0000-4000-8000-000000000001', 'f6f6f6f6-0000-4000-8000-000000000001', 'ingreso',
  '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","cantidad":4,"motivo":null}') is not null;
update public.intenciones_operacion set creado_en = clock_timestamp() - interval '25 hours', vence_en = clock_timestamp() - interval '1 hour'
 where id = 'f6f6f6f6-0000-4000-8000-000000000001';
create temp table libros4 as select pg_temp.huella_libros() as h;
select is(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', 'f6f6f6f6-0000-4000-8000-000000000001'),
  'ERR:PT409:intencion_vencida', 'VE-01: ejecutar una vencida → PT409 intencion_vencida');
select is((select estado from public.intenciones_operacion where id = 'f6f6f6f6-0000-4000-8000-000000000001') || '/' || pg_temp.huella_libros(),
  'pendiente/' || (select h from libros4), 'VE-01: sin escribir: sigue pendiente y no hay efectos en stock');
select is(pg_temp.cancelar('a5a5a5a5-0000-4000-8000-000000000001', 'f6f6f6f6-0000-4000-8000-000000000001'), 'OK:cancelada',
  'VE-07: cancelar una vencida la cancela');
select is(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', 'f6f6f6f6-0000-4000-8000-000000000001'),
  'ERR:PT409:intencion_cancelada', 'SD-02c: ejecutar una cancelada → PT409 intencion_cancelada');
select is(pg_temp.cancelar('a5a5a5a5-0000-4000-8000-000000000001', 'f6f6f6f6-0000-4000-8000-000000000001'), 'OK:cancelada',
  'SIM-01c: cancelar una cancelada es idempotente');
select is((select resuelto_en is not null and codigo_rechazo is null and operacion_id is null from public.intenciones_operacion where id = 'f6f6f6f6-0000-4000-8000-000000000001'),
  true, 'La cancelada queda coherente (resuelto_en, sin operación ni código)');
select is(pg_temp.huella_libros(), (select h from libros4), 'cancelar no genera operaciones ni movimientos');

-- Una confirmada con el plazo ya vencido devuelve lo almacenado (no se mira el plazo).
update public.intenciones_operacion set creado_en = clock_timestamp() - interval '40 hours', vence_en = clock_timestamp() - interval '16 hours'
 where id = '11111111-0000-4000-8000-000000000001' and actor_id = 'a5a5a5a5-0000-4000-8000-000000000001';
select is(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001'),
  (select valor from res where clave = 'e1'), 'VE-05: ejecutar una confirmada ya vencida devuelve lo almacenado (sin mirar el plazo)');
select is(pg_temp.cancelar('a5a5a5a5-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001'),
  'ERR:PT409:intencion_ya_confirmada', 'SIM-01a: cancelar una confirmada → PT409 intencion_ya_confirmada');
select is(pg_temp.cancelar('a5a5a5a5-0000-4000-8000-000000000001', 'd5d5d5d5-0000-4000-8000-000000000001'), 'OK:rechazada',
  'SIM-01b: cancelar una rechazada es idempotente y devuelve rechazada');
select is(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', 'd5d5d5d5-0000-4000-8000-000000000001'), 'OK:rechazada|-|stock_insuficiente',
  'SD-02b: ejecutar una rechazada devuelve lo almacenado');
select is(pg_temp.huella_libros(), (select h from libros4), 'Las lecturas idempotentes de terminales no escriben en los libros');

-- cancelar una pendiente vigente
select pg_temp.crear('a5a5a5a5-0000-4000-8000-000000000001', 'f6f6f6f6-0000-4000-8000-000000000002', 'ingreso',
  '{"producto_id":"a5a5a5a5-0000-4000-8000-0000000000f1","cantidad":4,"motivo":null}') is not null;
select is(pg_temp.cancelar('a5a5a5a5-0000-4000-8000-000000000001', 'f6f6f6f6-0000-4000-8000-000000000002'), 'OK:cancelada', 'SIM-01d: cancelar una pendiente vigente → cancelada');
select is(pg_temp.huella_libros(), (select h from libros4), 'SIM-01d: cancelar no mueve stock');

-- ===========================================================================
-- 6. Matriz SIM-01 / SD-02 / AU-01 / AU-02 / NG-02…04: estado × escenario, ambas funciones
-- ===========================================================================
select pg_temp.sembrar('a5a5a5a5-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000001', 'ingreso', 'pendiente');
select pg_temp.sembrar('a5a5a5a5-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000002', 'ingreso', 'confirmada');
select pg_temp.sembrar('a5a5a5a5-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000003', 'ingreso', 'rechazada');
select pg_temp.sembrar('a5a5a5a5-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000004', 'ingreso', 'cancelada');
select pg_temp.sembrar('a5a5a5a5-0000-4000-8000-000000000004', '72000000-0000-4000-8000-000000000001', 'ingreso', 'pendiente');
select pg_temp.sembrar('a5a5a5a5-0000-4000-8000-000000000004', '72000000-0000-4000-8000-000000000002', 'ingreso', 'confirmada');
select pg_temp.sembrar('a5a5a5a5-0000-4000-8000-000000000004', '72000000-0000-4000-8000-000000000003', 'ingreso', 'rechazada');
select pg_temp.sembrar('a5a5a5a5-0000-4000-8000-000000000004', '72000000-0000-4000-8000-000000000004', 'ingreso', 'cancelada');
create temp table ids_a1 as select array['71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004'] as ids;
create temp table ids_a4 as select array['72000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000002','72000000-0000-4000-8000-000000000003','72000000-0000-4000-8000-000000000004'] as ids;
select is(pg_temp.codigos('ejecutar', 'a5a5a5a5-0000-4000-8000-000000000002', (select ids from ids_a1)), 'PT404,PT404,PT404,PT404',
  'H1-02a/NG-04: ejecutar sobre intenciones de OTRO actor de la misma empresa → PT404 en los 4 estados');
select is(pg_temp.codigos('cancelar', 'a5a5a5a5-0000-4000-8000-000000000002', (select ids from ids_a1)), 'PT404,PT404,PT404,PT404',
  'H1-02a/NG-04: cancelar, ídem (simetría)');
select is(pg_temp.codigos('ejecutar', 'b5b5b5b5-0000-4000-8000-000000000001', (select ids from ids_a1)), 'PT404,PT404,PT404,PT404',
  'H1-02b/NG-04: ejecutar sobre intenciones de OTRA empresa → PT404');
select is(pg_temp.codigos('cancelar', 'b5b5b5b5-0000-4000-8000-000000000001', (select ids from ids_a1)), 'PT404,PT404,PT404,PT404',
  'H1-02b/NG-04: cancelar, ídem');
select is(pg_temp.codigos('ejecutar', 'a5a5a5a5-0000-4000-8000-000000000001', array['00000000-0000-4000-8000-00000000f0f0']) || '/'
       || pg_temp.codigos('cancelar', 'a5a5a5a5-0000-4000-8000-000000000001', array['00000000-0000-4000-8000-00000000f0f0']), 'PT404/PT404',
  'H1-02c: id inexistente → PT404 en ambas');
select is(pg_temp.codigos('ejecutar', 'a5a5a5a5-0000-4000-8000-000000000003', (select ids from ids_a1)), 'PT403,PT403,PT403,PT403',
  'AU-02/NG-02: vendedor_piloto → PT403 (nunca PT404) en los 4 estados');
select is(pg_temp.codigos('cancelar', 'a5a5a5a5-0000-4000-8000-000000000003', (select ids from ids_a1)), 'PT403,PT403,PT403,PT403',
  'AU-02/NG-02: cancelar, ídem');
select is(pg_temp.codigos('ejecutar', 'a5a5a5a5-0000-4000-8000-000000000004', (select ids from ids_a4)), 'PT403,PT403,PT403,PT403',
  'AU-01/NG-03: perfil inactivo con intenciones propias en los 4 estados → PT403 (nunca PT404 ni el resultado)');
select is(pg_temp.codigos('cancelar', 'a5a5a5a5-0000-4000-8000-000000000004', (select ids from ids_a4)), 'PT403,PT403,PT403,PT403',
  'AU-01/NG-03: cancelar, ídem');
select is(pg_temp.codigos('ejecutar', 'a5a5a5a5-0000-4000-8000-0000000000f1', (select ids from ids_a1)) || '/'
       || pg_temp.codigos('cancelar', 'a5a5a5a5-0000-4000-8000-0000000000f1', (select ids from ids_a1)),
  'PT403,PT403,PT403,PT403/PT403,PT403,PT403,PT403', 'AU-02b: sin perfil (user_metadata engañoso) → PT403 en ambas');
select is(pg_temp.llamar('anon', '{"role":"anon"}', $q$select e.estado from public.ejecutar_intencion_operacion('71000000-0000-4000-8000-000000000001') e$q$) like 'ERR:42501:%'
      and pg_temp.llamar('anon', '{"role":"anon"}', $q$select public.cancelar_intencion_operacion('71000000-0000-4000-8000-000000000001')::text$q$) like 'ERR:42501:%',
  true, 'NG-01: anon no ejecuta ninguna de las dos fachadas (42501)');
-- Propia, terminales (no mutan): O4 distinto entre ejecutar y cancelar (SIM-01).
select is(pg_temp.codigos('ejecutar', 'a5a5a5a5-0000-4000-8000-000000000001', array['71000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004']),
  'OK,OK,PT409', 'SIM-01 O4 ejecutar: confirmada y rechazada devuelven lo almacenado; cancelada → PT409');
select is(pg_temp.codigos('cancelar', 'a5a5a5a5-0000-4000-8000-000000000001', array['71000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004']),
  'PT409,OK,OK', 'SIM-01 O4 cancelar: confirmada → PT409; rechazada y cancelada idempotentes');
select is(pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000003'), 'OK:rechazada|-|stock_insuficiente',
  'SD-02: lo almacenado de la rechazada sembrada incluye su código');

-- ===========================================================================
-- 7. H1 sobre los cuerpos reales: SD-03 y H1-P2 (savepoint, se revierte)
-- ===========================================================================
savepoint sp_sd03;
drop policy intenciones_operacion_update_propietario_rpc on public.intenciones_operacion;
select setval('s_sd03e', 1, pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000001') = 'ERR:PT500:intencion_error_interno') is not null;
select setval('s_sd03c', 1, pg_temp.cancelar('a5a5a5a5-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000001') = 'ERR:PT500:intencion_error_interno') is not null;
rollback to savepoint sp_sd03;
select ok((select is_called from s_sd03e), 'SD-03: sin política UPDATE, ejecutar sobre una pendiente → PT500 (el FOR UPDATE da 0 filas y la relectura la ve pendiente), no PT404');
select ok((select is_called from s_sd03c), 'SD-03: ídem cancelar (simetría)');
select is((select count(*)::int from pg_policy where polrelid = 'public.intenciones_operacion'::regclass and polcmd = 'w'), 1,
  'SD-03: la política UPDATE quedó restituida tras el ROLLBACK TO');

savepoint sp_h1p2;
revoke update (estado, operacion_id, codigo_rechazo, resuelto_en) on public.intenciones_operacion from propietario_rpc;
select setval('s_h1p2e', 1, pg_temp.ejecutar('a5a5a5a5-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000001') like 'ERR:42501:%') is not null;
select setval('s_h1p2c', 1, pg_temp.cancelar('a5a5a5a5-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000001') like 'ERR:42501:%') is not null;
rollback to savepoint sp_h1p2;
select ok((select is_called from s_h1p2e), 'H1-P2: sin privilegio UPDATE de columna, ejecutar propaga 42501 (no 0 filas ni PT404)');
select ok((select is_called from s_h1p2c), 'H1-P2: ídem cancelar');
select ok(has_column_privilege('propietario_rpc', 'public.intenciones_operacion', 'estado', 'UPDATE')
      and has_column_privilege('propietario_rpc', 'public.intenciones_operacion', 'resuelto_en', 'UPDATE'),
  'H1-P2: los privilegios de columna quedaron restituidos');
select is((select estado from public.intenciones_operacion where id = '71000000-0000-4000-8000-000000000001' and actor_id = 'a5a5a5a5-0000-4000-8000-000000000001'),
  'pendiente', 'SD-03/H1-P2: la pendiente sembrada no se modificó');

-- ===========================================================================
-- 8. Invariantes: RF-03, RF-06b/c, INV-01, libros mayores
-- ===========================================================================
select is((select count(*)::int from public.intenciones_operacion i join public.operaciones o on o.id = i.operacion_id
            where i.estado = 'confirmada' and o.idempotency_key <> i.id), 0,
  'RF-03: para toda confirmada, operaciones.idempotency_key = id de la intención (0 violaciones)');
select is((select count(*)::int from public.intenciones_operacion i
            where i.estado = 'confirmada' and not exists (select 1 from public.operaciones o where o.id = i.operacion_id and o.idempotency_key = i.id)), 0,
  'RF-03: toda confirmada tiene su operación con esa clave');
select is((select count(*)::int from public.operaciones where id = idempotency_key), 0, 'RF-06b: ninguna operación tiene id = idempotency_key');
select is((select count(*)::int from public.intenciones_operacion i
            where i.id in ('11111111-0000-4000-8000-000000000001','11111111-0000-4000-8000-000000000002','11111111-0000-4000-8000-000000000003',
                           'd6d6d6d6-0000-4000-8000-000000000002','e6e6e6e6-0000-4000-8000-000000000002')
              and i.estado = 'confirmada' and pg_temp.n_movs(i.operacion_id) <> 1), 0,
  'INV-01: cada confirmada generada por ejecutar real tiene exactamente 1 operación y 1 movimiento');
select is((select count(*)::int from (select operacion_id from public.movimientos_stock group by operacion_id having count(*) > 1) d), 0,
  'Cero movimientos_stock duplicados por operación');
select is((select count(*)::int from (select empresa_id, actor_id, idempotency_key from public.operaciones group by 1, 2, 3 having count(*) > 1) d), 0,
  'Cero operaciones duplicadas por clave');
select is((select count(*)::int from public.operaciones o where o.idempotency_key in ('f6f6f6f6-0000-4000-8000-000000000001','f6f6f6f6-0000-4000-8000-000000000002')), 0,
  'Cancelar y las vencidas no generaron operaciones');
select ok(not has_table_privilege('propietario_rpc', 'public.operaciones', 'UPDATE,DELETE') and not has_table_privilege('propietario_rpc', 'public.movimientos_stock', 'UPDATE,DELETE')
      and not has_table_privilege('authenticated', 'public.operaciones', 'INSERT') and not has_table_privilege('authenticated', 'public.movimientos_stock', 'INSERT'),
  'Libros mayores inmutables: sin UPDATE/DELETE para propietario_rpc ni INSERT directo para authenticated');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace) and p.proname like '%intencion%'
      and lower(p.prosrc) ~ 'insert\s+into\s+public\.(operaciones|movimientos_stock)'), 0,
  'RF-06c (S): ninguna función de intenciones inserta directamente en operaciones ni movimientos_stock');
select is(pg_temp.huella_libros() is not null, true, 'Libros: huella calculable');

-- ===========================================================================
-- 9. ES-05 (S) sobre ejecutar y cancelar
-- ===========================================================================
select ok(
  (select bool_and(lower(p.prosrc) !~ 'when\s+others' and lower(p.prosrc) !~ 'auth\.' and lower(p.prosrc) !~ '\mexecute\M'
                   and lower(p.prosrc) !~ '\mformat\s*\(' and lower(p.prosrc) !~ 'user_metadata' and lower(p.prosrc) !~ 'nowait|lock_timeout|skip\s+locked'
                   and lower(p.prosrc) !~ 'pg_advisory')
     from pg_proc p where p.pronamespace = 'privado'::regnamespace and p.proname in ('ejecutar_intencion_operacion', 'cancelar_intencion_operacion')),
  'ES-05 (S): ejecutar y cancelar sin WHEN OTHERS, auth.*, SQL dinámico, NOWAIT/lock_timeout ni advisory locks (no toman el nivel 0)');
select is(
  (select string_agg(p.proname::text || '=' || ((length(lower(p.prosrc)) - length(replace(lower(p.prosrc), 'for update', ''))) / length('for update'))::text, ',' order by p.proname)
     from pg_proc p where p.pronamespace = 'privado'::regnamespace and p.proname in ('ejecutar_intencion_operacion', 'cancelar_intencion_operacion')),
  'cancelar_intencion_operacion=1,ejecutar_intencion_operacion=1', 'ES-05 (S): un solo FOR UPDATE por función (nivel 1)');
select is(
  (select string_agg(p.proname::text || '=' || x.n::text || '/' || x.distintas::text, ',' order by p.proname)
     from pg_proc p,
          lateral (select count(*) as n, count(distinct regexp_replace(m[1], '\s+', ' ', 'g')) as distintas
                     from regexp_matches(lower(p.prosrc), '(select p\.empresa_id,.*?where p\.usuario_id = v_uid;)', 'gs') m) x
    where p.pronamespace = 'privado'::regnamespace and p.proname in ('ejecutar_intencion_operacion', 'cancelar_intencion_operacion')),
  'cancelar_intencion_operacion=2/1,ejecutar_intencion_operacion=2/1',
  'ES-05 (S): la relectura O3b es idéntica a la lectura inicial O2 (2 apariciones, 1 texto distinto) y ambas parten de perfiles con LEFT JOIN');
select is(
  (select (length(lower(p.prosrc)) - length(replace(lower(p.prosrc), 'left join public.intenciones_operacion', ''))) / length('left join public.intenciones_operacion')
     from pg_proc p where p.oid = 'privado.ejecutar_intencion_operacion(uuid)'::regprocedure), 2, 'ES-05 (S): ejecutar lee la intención solo con LEFT JOIN desde perfiles (+ el FOR UPDATE)');
select ok(
  (select lower(p.prosrc) ~ 'case v_i_tipo' and lower(p.prosrc) ~ 'when sqlstate ''pt400'' or sqlstate ''pt404'' or sqlstate ''pt409'''
      and lower(p.prosrc) ~ 'stock_cantidad_invalida' and lower(p.prosrc) ~ 'stock_conflicto_idempotencia' and lower(p.prosrc) ~ 'raise;'
     from pg_proc p where p.oid = 'privado.ejecutar_intencion_operacion(uuid)'::regprocedure),
  'ES-05 (S): CASE estático por tipo, captura solo PT400/PT404/PT409, lista cerrada de 8 códigos y RAISE; para el resto');
select is(
  (select position('stock_insuficiente' in lower(p.prosrc)) > 0 and position('for update' in lower(p.prosrc)) < position('registrar_ingreso' in lower(p.prosrc))
     from pg_proc p where p.oid = 'privado.ejecutar_intencion_operacion(uuid)'::regprocedure), true,
  'ES-05 (S): el bloqueo de la intención (nivel 1) precede a la llamada a las RPC de stock (nivel 2)');

select * from finish();

rollback;
