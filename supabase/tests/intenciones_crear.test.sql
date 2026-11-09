-- pgTAP: crear_intencion_operacion — corte C1.2a
-- (ADR-010 v1.0 §5.4/§5.5/§5.5.1, anexo v1.1 §5.2 y §13, aclaración C1.2a-D1
-- `docs/decisions/010-aclaracion-c1-2a-clave-nula.md`; ADR-001 Topología D, P11;
-- Blueprint §12 «Intenciones persistidas de stock» y «Seguridad»).
-- Migración 20261111120100_rpc_intenciones_nucleo.sql.
--
-- Cubre (clase D = determinista, S = estática): PL-01…13 (payload), LM-01'
-- (topes por fixture), LM-02/LM-07'/LM-07a (replay y compuerta), G-R, AU-04,
-- AU-05, NG-01/02/03/04 para `crear`, CR-ID-01…08, ES-04 (las seis funciones) y
-- ES-05 (parte `crear`). NO cubre carreras (CC-*), que no se pueden forzar desde
-- una sola sesión pgTAP: se miden en un arnés aparte (C1.2a, local, no
-- versionado) y las estadísticas e instrumentadas son C1.3.
--
-- Datos sintéticos; se revierten al final. Las intenciones se siembran como
-- propietario de la tabla (la RLS no lo filtra). El actor se emula con
-- request.jwt.claims + SET LOCAL ROLE dentro de pg_temp.llamar().
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(93);

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
    when 'ingreso' then '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","cantidad":5,"motivo":null}'::pg_catalog.jsonb
    when 'a_cuarentena' then '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","ubicacion_origen_id":"e2e2e2e2-0000-4000-8000-0000000000d1","cantidad":5,"motivo":"x"}'::pg_catalog.jsonb
    else '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","ubicacion_origen_id":"e2e2e2e2-0000-4000-8000-0000000000d1","cantidad":5,"motivo_codigo":"vencido","motivo":null}'::pg_catalog.jsonb
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
  ('a2a2a2a2-0000-4000-8000-000000000000', 'Empresa A (test crear)'),
  ('b2b2b2b2-0000-4000-8000-000000000000', 'Empresa B (test crear)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('a2a2a2a2-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'cr.a1@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'cr.a2@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'cr.a3@usuarios.distribuidora.invalid',
     '{"rol":"dueno","empresa_id":"b2b2b2b2-0000-4000-8000-000000000000"}'),
  ('a2a2a2a2-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'cr.a4@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'cr.a5@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'cr.a6@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'cr.a7@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000008', 'authenticated', 'authenticated', 'cr.a8@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-000000000009', 'authenticated', 'authenticated', 'cr.a9@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', 'cr.aa@usuarios.distribuidora.invalid', '{}'),
  ('a2a2a2a2-0000-4000-8000-0000000000f1', 'authenticated', 'authenticated', 'cr.x1@usuarios.distribuidora.invalid',
     '{"rol":"dueno","empresa_id":"a2a2a2a2-0000-4000-8000-000000000000"}'),
  ('b2b2b2b2-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'cr.b1@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('a2a2a2a2-0000-4000-8000-000000000001', 'a2a2a2a2-0000-4000-8000-000000000000', 'cr.a1', 'Dueño A', 'dueno', true),
  ('a2a2a2a2-0000-4000-8000-000000000002', 'a2a2a2a2-0000-4000-8000-000000000000', 'cr.a2', 'Encargado A', 'encargado', true),
  ('a2a2a2a2-0000-4000-8000-000000000003', 'a2a2a2a2-0000-4000-8000-000000000000', 'cr.a3', 'Vendedor A', 'vendedor_piloto', true),
  ('a2a2a2a2-0000-4000-8000-000000000004', 'a2a2a2a2-0000-4000-8000-000000000000', 'cr.a4', 'Dueño inactivo A', 'dueno', false),
  ('a2a2a2a2-0000-4000-8000-000000000005', 'a2a2a2a2-0000-4000-8000-000000000000', 'cr.a5', 'Tope sin resolver', 'dueno', true),
  ('a2a2a2a2-0000-4000-8000-000000000006', 'a2a2a2a2-0000-4000-8000-000000000000', 'cr.a6', 'Tope hora', 'dueno', true),
  ('a2a2a2a2-0000-4000-8000-000000000007', 'a2a2a2a2-0000-4000-8000-000000000000', 'cr.a7', 'Tope hora previo', 'dueno', true),
  ('a2a2a2a2-0000-4000-8000-000000000008', 'a2a2a2a2-0000-4000-8000-000000000000', 'cr.a8', 'Replay inactivado', 'dueno', true),
  ('a2a2a2a2-0000-4000-8000-000000000009', 'a2a2a2a2-0000-4000-8000-000000000000', 'cr.a9', 'Compuerta', 'encargado', true),
  ('a2a2a2a2-0000-4000-8000-00000000000a', 'a2a2a2a2-0000-4000-8000-000000000000', 'cr.aa', 'CR-ID-06', 'dueno', true),
  ('b2b2b2b2-0000-4000-8000-000000000001', 'b2b2b2b2-0000-4000-8000-000000000000', 'cr.b1', 'Dueño B', 'dueno', true);
-- (a2…f1 no tiene perfil: su user_metadata afirma ser dueño de A y no cuenta.)

-- Constantes de payload.
create temp table k (nombre pg_catalog.text primary key, v pg_catalog.text);
insert into k values
  ('P',  'e2e2e2e2-0000-4000-8000-0000000000f1'),
  ('U',  'e2e2e2e2-0000-4000-8000-0000000000d1'),
  ('PI', '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","cantidad":5,"motivo":null}'),
  ('PC', '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","ubicacion_origen_id":"e2e2e2e2-0000-4000-8000-0000000000d1","cantidad":5,"motivo":"Golpeado"}'),
  ('PM', '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","ubicacion_origen_id":"e2e2e2e2-0000-4000-8000-0000000000d1","cantidad":5,"motivo_codigo":"vencido","motivo":null}');
grant select on k to public;

create temp table libros0 as select pg_temp.huella_libros() as h;

-- ===========================================================================
-- A. Éxito, forma almacenada y replay (PL-01, PL-11)
-- ===========================================================================
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001', 'ingreso', (select v from k where nombre = 'PI')),
  'OK:11111111-0000-4000-8000-000000000001',
  'PL-01: crear ingreso válido devuelve el mismo id');

select is(
  (select estado || '|' || (operacion_id is null)::text || '|' || (codigo_rechazo is null)::text || '|' || (resuelto_en is null)::text
          || '|' || empresa_id::text || '|' || actor_id::text
     from public.intenciones_operacion where id = '11111111-0000-4000-8000-000000000001'),
  'pendiente|true|true|true|a2a2a2a2-0000-4000-8000-000000000000|a2a2a2a2-0000-4000-8000-000000000001',
  'PL-01: queda pendiente, sin operación, con empresa y actor tomados de perfiles');

select ok(
  (select vence_en between creado_en + interval '23 hours 59 minutes' and creado_en + interval '24 hours 1 minute'
     from public.intenciones_operacion where id = '11111111-0000-4000-8000-000000000001'),
  'PL-01: vence_en = creado_en + 24 h (fijado por el servidor)');

select is(
  (select payload from public.intenciones_operacion where id = '11111111-0000-4000-8000-000000000001'),
  '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","cantidad":5,"motivo":null}'::jsonb,
  'PL-01: el payload almacenado es el reconstruido por el servidor');

select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001', 'ingreso',
    -- mismo contenido con otro orden de claves, espacios y notación numérica
    '{ "motivo": null, "cantidad": 5e0, "producto_id": "e2e2e2e2-0000-4000-8000-0000000000f1" }'),
  'OK:11111111-0000-4000-8000-000000000001',
  'PL-11: replay con el mismo id y contenido equivalente (otro orden, 5e0) devuelve el id');

select is((select count(*)::int from public.intenciones_operacion where actor_id = 'a2a2a2a2-0000-4000-8000-000000000001'), 1,
  'PL-11: el replay no crea otra fila');

select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001', 'ingreso',
    '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","cantidad":6,"motivo":null}'),
  'ERR:PT409:intencion_conflicto',
  'PL-12: mismo id con otra cantidad → PT409 intencion_conflicto');

select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001', 'merma', (select v from k where nombre = 'PM')),
  'ERR:PT409:intencion_conflicto',
  'PL-12: mismo id con otro tipo → PT409 intencion_conflicto (el replay precede a la compuerta)');

select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000002', 'a_cuarentena', (select v from k where nombre = 'PC')),
  'OK:11111111-0000-4000-8000-000000000002', 'PL-01: crear a_cuarentena válido');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000003', 'merma', (select v from k where nombre = 'PM')),
  'OK:11111111-0000-4000-8000-000000000003', 'PL-01: crear merma válida');
select is(
  (select payload from public.intenciones_operacion where id = '11111111-0000-4000-8000-000000000003'),
  '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","ubicacion_origen_id":"e2e2e2e2-0000-4000-8000-0000000000d1","cantidad":5,"motivo_codigo":"vencido","motivo":null}'::jsonb,
  'PL-01: payload canónico de merma con sus cinco claves');

select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000002', '11111111-0000-4000-8000-000000000001', 'ingreso', (select v from k where nombre = 'PI')),
  'OK:11111111-0000-4000-8000-000000000001',
  'Espacio de ids por actor: otro actor de la misma empresa crea con el mismo uuid sin colisión');
select is(pg_temp.crear('b2b2b2b2-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001', 'ingreso', (select v from k where nombre = 'PI')),
  'OK:11111111-0000-4000-8000-000000000001',
  'Espacio de ids por actor: un actor de otra empresa crea con el mismo uuid sin colisión');
select is((select count(*)::int from public.intenciones_operacion where id = '11111111-0000-4000-8000-000000000001'), 3,
  'Tres filas independientes con el mismo uuid (PK empresa, actor, id); la del actor A1 no se tocó');

-- ===========================================================================
-- B. Autenticación y autorización (NG-01/02/03 para `crear`, AU-04)
-- ===========================================================================
select is(pg_temp.llamar('authenticated', '{"role":"authenticated"}',
    $q$select public.crear_intencion_operacion('11111111-0000-4000-8000-0000000000a1', 'ingreso', '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","cantidad":5,"motivo":null}')::text$q$),
  'ERR:PT401:intencion_no_autenticado', 'PT401: authenticated sin identidad (sin sub)');
select is(pg_temp.llamar('anon', '{"role":"anon"}',
    $q$select public.crear_intencion_operacion('11111111-0000-4000-8000-0000000000a2', 'ingreso', '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","cantidad":5,"motivo":null}')::text$q$) like 'ERR:42501:%',
  true, 'NG-01: anon no ejecuta la fachada (42501)');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000003', '11111111-0000-4000-8000-0000000000a3', 'ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT403:intencion_no_autorizado', 'NG-02: vendedor_piloto → PT403');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000004', '11111111-0000-4000-8000-0000000000a4', 'ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT403:intencion_no_autorizado', 'NG-03/AU-04: perfil inactivo → PT403');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-0000000000f1', '11111111-0000-4000-8000-0000000000a5', 'ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT403:intencion_no_autorizado', 'Usuario sin perfil (aunque user_metadata afirme ser dueño) → PT403');
select is((select count(*)::int from public.intenciones_operacion
            where actor_id in ('a2a2a2a2-0000-4000-8000-000000000003', 'a2a2a2a2-0000-4000-8000-000000000004', 'a2a2a2a2-0000-4000-8000-0000000000f1')),
  0, 'Los rechazos de autenticación y autorización no escriben');

-- AU-04/05: replay y compuerta incluyen autorización.
select pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000008', '88888888-0000-4000-8000-000000000001', 'ingreso', (select v from k where nombre = 'PI')) is not null;
update public.perfiles set activo = false where usuario_id = 'a2a2a2a2-0000-4000-8000-000000000008';
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000008', '88888888-0000-4000-8000-000000000001', 'ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT403:intencion_no_autorizado',
  'AU-04: perfil inactivado después de crear; el replay de su propio id existente → PT403 (no devuelve el id)');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000008', '88888888-0000-4000-8000-000000000002', 'ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT403:intencion_no_autorizado',
  'AU-05: con una pendiente propia y perfil inactivo, un id nuevo → PT403 (no PT409 sin_resolver)');
update public.perfiles set activo = true where usuario_id = 'a2a2a2a2-0000-4000-8000-000000000008';

-- ===========================================================================
-- C. Tipo y payload (PL-02…PL-10, PL-13): casos inválidos → PT400
-- ===========================================================================
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000009', '99999999-0000-4000-8000-0000000000b1', 'venta', (select v from k where nombre = 'PI')),
  'ERR:PT400:intencion_tipo_invalido', 'PL-02: tipo fuera de la lista cerrada');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000009', '99999999-0000-4000-8000-0000000000b2', null, (select v from k where nombre = 'PI')),
  'ERR:PT400:intencion_tipo_invalido', 'PL-02: tipo nulo (lectura fail-closed de la lista cerrada)');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000009', '99999999-0000-4000-8000-0000000000b3', 'Ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT400:intencion_tipo_invalido', 'PL-02: el tipo distingue mayúsculas');

create temp table casos_invalidos (nombre pg_catalog.text, tipo pg_catalog.text, payload pg_catalog.text);
insert into casos_invalidos
select c.nombre, c.tipo, replace(replace(c.payload, '@P', (select v from k where nombre = 'P')), '@U', (select v from k where nombre = 'U'))
from (values
  ('payload_nulo', 'ingreso', null),
  ('arreglo', 'ingreso', '[]'),
  ('json_null', 'ingreso', 'null'),
  ('cadena', 'ingreso', '"x"'),
  ('numero', 'ingreso', '5'),
  ('objeto_vacio', 'ingreso', '{}'),
  ('clave_extra', 'ingreso', '{"producto_id":"@P","cantidad":1,"motivo":null,"x":1}'),
  ('falta_motivo', 'ingreso', '{"producto_id":"@P","cantidad":1}'),
  ('falta_cantidad', 'ingreso', '{"producto_id":"@P","motivo":null}'),
  ('falta_producto', 'ingreso', '{"cantidad":1,"motivo":null}'),
  ('clave_con_espacio', 'ingreso', '{"producto_id":"@P","cantidad ":1,"motivo":null}'),
  ('ingreso_con_origen', 'ingreso', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo":null}'),
  ('producto_mayusculas', 'ingreso', '{"producto_id":"E2E2E2E2-0000-4000-8000-0000000000F1","cantidad":1,"motivo":null}'),
  ('producto_con_llaves', 'ingreso', '{"producto_id":"{@P}","cantidad":1,"motivo":null}'),
  ('producto_sin_guiones', 'ingreso', '{"producto_id":"e2e2e2e2000040008000000000000f1a","cantidad":1,"motivo":null}'),
  ('producto_numero', 'ingreso', '{"producto_id":5,"cantidad":1,"motivo":null}'),
  ('producto_null', 'ingreso', '{"producto_id":null,"cantidad":1,"motivo":null}'),
  ('cantidad_cero', 'ingreso', '{"producto_id":"@P","cantidad":0,"motivo":null}'),
  ('cantidad_negativa', 'ingreso', '{"producto_id":"@P","cantidad":-1,"motivo":null}'),
  ('cantidad_decimal', 'ingreso', '{"producto_id":"@P","cantidad":1.5,"motivo":null}'),
  ('cantidad_con_escala', 'ingreso', '{"producto_id":"@P","cantidad":1.0,"motivo":null}'),
  ('cantidad_escala_10E-1', 'ingreso', '{"producto_id":"@P","cantidad":10E-1,"motivo":null}'),
  ('cantidad_cadena', 'ingreso', '{"producto_id":"@P","cantidad":"5","motivo":null}'),
  ('cantidad_booleana', 'ingreso', '{"producto_id":"@P","cantidad":true,"motivo":null}'),
  ('cantidad_null', 'ingreso', '{"producto_id":"@P","cantidad":null,"motivo":null}'),
  ('cantidad_sobre_integer', 'ingreso', '{"producto_id":"@P","cantidad":2147483648,"motivo":null}'),
  ('cantidad_1e10', 'ingreso', '{"producto_id":"@P","cantidad":1e10,"motivo":null}'),
  ('motivo_numero', 'ingreso', '{"producto_id":"@P","cantidad":1,"motivo":5}'),
  ('motivo_booleano', 'ingreso', '{"producto_id":"@P","cantidad":1,"motivo":false}'),
  ('motivo_objeto', 'ingreso', '{"producto_id":"@P","cantidad":1,"motivo":{}}'),
  ('motivo_501', 'ingreso', '{"producto_id":"@P","cantidad":1,"motivo":"' || repeat('a', 501) || '"}'),
  ('cuarentena_sin_origen', 'a_cuarentena', '{"producto_id":"@P","cantidad":1,"motivo":"x"}'),
  ('cuarentena_origen_mayusculas', 'a_cuarentena', '{"producto_id":"@P","ubicacion_origen_id":"E2E2E2E2-0000-4000-8000-0000000000D1","cantidad":1,"motivo":"x"}'),
  ('cuarentena_origen_numero', 'a_cuarentena', '{"producto_id":"@P","ubicacion_origen_id":7,"cantidad":1,"motivo":"x"}'),
  ('cuarentena_con_codigo', 'a_cuarentena', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo":"x","motivo_codigo":"vencido"}'),
  ('merma_sin_codigo', 'merma', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo":null}'),
  ('merma_codigo_vacio', 'merma', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo_codigo":"","motivo":null}'),
  ('merma_codigo_espacios', 'merma', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo_codigo":" vencido","motivo":null}'),
  ('merma_codigo_41', 'merma', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo_codigo":"' || repeat('a', 41) || '","motivo":null}'),
  ('merma_codigo_numero', 'merma', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo_codigo":3,"motivo":null}'),
  ('merma_codigo_null', 'merma', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo_codigo":null,"motivo":null}'),
  ('payload_mayor_a_4096_bytes', 'ingreso', '{"producto_id":"@P","cantidad":1,"motivo":null,"z":"' || repeat('z', 4100) || '"}')
) as c(nombre, tipo, payload);

create function pg_temp.verificar_invalidos() returns pg_catalog.text language plpgsql as $f$
declare
  r record;
  res pg_catalog.text;
  fallos pg_catalog.text := '';
  n integer := 0;
begin
  for r in select * from casos_invalidos order by nombre loop
    n := n + 1;
    res := pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000009', '99999999-0000-4000-8000-' || pg_catalog.lpad(n::pg_catalog.text, 12, '0'), r.tipo, r.payload);
    if res is distinct from 'ERR:PT400:intencion_payload_invalido' then
      fallos := fallos || r.nombre || '=' || res || ';';
    end if;
  end loop;
  return fallos;
end $f$;
select is(pg_temp.verificar_invalidos(), '',
  'PL-03…PL-10: 42 payloads inválidos (nulo, forma, claves, uuid, cantidad, motivo, motivo_codigo, tamaño) → PT400 intencion_payload_invalido');
select is((select count(*)::int from casos_invalidos), 42, 'PL: la tabla de casos inválidos tiene 42 filas');
select is((select count(*)::int from public.intenciones_operacion where actor_id = 'a2a2a2a2-0000-4000-8000-000000000009'), 0,
  'PL: ningún payload inválido escribió una fila');

-- Casos válidos: se crea, se compara lo almacenado y se limpia como propietario.
create temp table casos_validos (nombre pg_catalog.text, tipo pg_catalog.text, payload pg_catalog.text, esperado pg_catalog.jsonb);
insert into casos_validos
select c.nombre, c.tipo,
       replace(replace(c.payload, '@P', (select v from k where nombre = 'P')), '@U', (select v from k where nombre = 'U')),
       replace(replace(c.esperado, '@P', (select v from k where nombre = 'P')), '@U', (select v from k where nombre = 'U'))::jsonb
from (values
  ('cantidad_maxima', 'ingreso', '{"producto_id":"@P","cantidad":2147483647,"motivo":null}', '{"producto_id":"@P","cantidad":2147483647,"motivo":null}'),
  ('cantidad_1e3', 'ingreso', '{"producto_id":"@P","cantidad":1E+3,"motivo":null}', '{"producto_id":"@P","cantidad":1000,"motivo":null}'),
  ('cantidad_5e0', 'ingreso', '{"producto_id":"@P","cantidad":0.5e1,"motivo":null}', '{"producto_id":"@P","cantidad":5,"motivo":null}'),
  ('motivo_recortado', 'ingreso', '{"producto_id":"@P","cantidad":1,"motivo":"  Remito 7  "}', '{"producto_id":"@P","cantidad":1,"motivo":"Remito 7"}'),
  ('motivo_blancos_a_null', 'ingreso', '{"producto_id":"@P","cantidad":1,"motivo":"   "}', '{"producto_id":"@P","cantidad":1,"motivo":null}'),
  ('motivo_vacio_a_null', 'ingreso', '{"producto_id":"@P","cantidad":1,"motivo":""}', '{"producto_id":"@P","cantidad":1,"motivo":null}'),
  ('motivo_500', 'ingreso', '{"producto_id":"@P","cantidad":1,"motivo":"' || repeat('á', 500) || '"}', '{"producto_id":"@P","cantidad":1,"motivo":"' || repeat('á', 500) || '"}'),
  ('motivo_unicode', 'ingreso', '{"producto_id":"@P","cantidad":1,"motivo":"ñandú 🧀 é"}', '{"producto_id":"@P","cantidad":1,"motivo":"ñandú 🧀 é"}'),
  ('clave_duplicada_gana_la_ultima', 'ingreso', '{"producto_id":"@P","cantidad":1,"cantidad":2,"motivo":null}', '{"producto_id":"@P","cantidad":2,"motivo":null}'),
  ('cuarentena_valida', 'a_cuarentena', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":3,"motivo":"Golpeado"}', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":3,"motivo":"Golpeado"}'),
  ('cuarentena_motivo_null', 'a_cuarentena', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":3,"motivo":null}', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":3,"motivo":null}'),
  ('merma_codigo_40', 'merma', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo_codigo":"' || repeat('c', 40) || '","motivo":null}', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo_codigo":"' || repeat('c', 40) || '","motivo":null}'),
  ('merma_otro_con_motivo', 'merma', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo_codigo":"otro","motivo":" cambio "}', '{"producto_id":"@P","ubicacion_origen_id":"@U","cantidad":1,"motivo_codigo":"otro","motivo":"cambio"}')
) as c(nombre, tipo, payload, esperado);

create function pg_temp.verificar_validos() returns pg_catalog.text language plpgsql as $f$
declare
  r record;
  res pg_catalog.text;
  alm pg_catalog.jsonb;
  fallos pg_catalog.text := '';
  n integer := 0;
  v_id pg_catalog.text;
begin
  for r in select * from casos_validos order by nombre loop
    n := n + 1;
    v_id := '99999999-0000-4000-8000-1' || pg_catalog.lpad(n::pg_catalog.text, 11, '0');
    res := pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000009', v_id, r.tipo, r.payload);
    select i.payload into alm from public.intenciones_operacion i where i.id = v_id::pg_catalog.uuid and i.actor_id = 'a2a2a2a2-0000-4000-8000-000000000009';
    if res is distinct from 'OK:' || v_id or alm is distinct from r.esperado then
      fallos := fallos || r.nombre || '=' || res || '/' || coalesce(alm::pg_catalog.text, 'sin fila') || ';';
    end if;
    delete from public.intenciones_operacion where id = v_id::pg_catalog.uuid and actor_id = 'a2a2a2a2-0000-4000-8000-000000000009';
  end loop;
  return fallos;
end $f$;
select is(pg_temp.verificar_validos(), '',
  'PL: 13 payloads válidos normalizados (1e3→1000, 0.5e1→5, motivo recortado/blancos→null, 500 caracteres, unicode, clave duplicada, código de 40) se almacenan reconstruidos');
select is((select count(*)::int from casos_validos), 13, 'PL: la tabla de casos válidos tiene 13 filas');

-- PL-13: crear no revela existencia de productos ni ubicaciones (no los lee).
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000009', '99999999-0000-4000-8000-0000000000c1', 'merma',
    '{"producto_id":"00000000-0000-4000-8000-00000000dead","ubicacion_origen_id":"00000000-0000-4000-8000-00000000beef","cantidad":1,"motivo_codigo":"vencido","motivo":null}'),
  'OK:99999999-0000-4000-8000-0000000000c1',
  'PL-13: producto y ubicación inexistentes se aceptan en crear (se validan al ejecutar; crear no sondea datos)');
delete from public.intenciones_operacion where id = '99999999-0000-4000-8000-0000000000c1';

-- ===========================================================================
-- D. CR-ID-01…08 (aclaración C1.2a-D1)
-- ===========================================================================
create temp table antes as select pg_temp.n_int() as n, pg_temp.huella_libros() as libros;

select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', null, 'ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT400:intencion_clave_invalida',
  'CR-ID-01: actor autorizado, p_intencion_id NULL → PT400 intencion_clave_invalida');
select is(pg_temp.n_int() || '/' || pg_temp.huella_libros(), (select n || '/' || libros from antes),
  'CR-ID-01: cero efectos persistentes (intenciones, operaciones y movimientos sin cambios) y nunca 23502');

select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000004', null, 'ingreso', (select v from k where nombre = 'PI')), 'ERR:PT403:intencion_no_autorizado',
  'CR-ID-02: id nulo con perfil inactivo → PT403');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000003', null, 'ingreso', (select v from k where nombre = 'PI')), 'ERR:PT403:intencion_no_autorizado',
  'CR-ID-02: id nulo con vendedor_piloto → PT403');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-0000000000f1', null, 'ingreso', (select v from k where nombre = 'PI')), 'ERR:PT403:intencion_no_autorizado',
  'CR-ID-02: id nulo sin perfil → PT403');

select is(pg_temp.llamar('authenticated', '{"role":"authenticated"}',
    $q$select public.crear_intencion_operacion(null, 'ingreso', '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","cantidad":5,"motivo":null}')::text$q$),
  'ERR:PT401:intencion_no_autenticado', 'CR-ID-03: id nulo sin identidad → PT401');
select is(pg_temp.llamar('anon', '{"role":"anon"}',
    $q$select public.crear_intencion_operacion(null, 'ingreso', '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","cantidad":5,"motivo":null}')::text$q$) like 'ERR:42501:%',
  true, 'CR-ID-04: id nulo como anon → 42501 (sin EXECUTE)');

select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', null, 'venta', (select v from k where nombre = 'PI')),
  'ERR:PT400:intencion_clave_invalida', 'CR-ID-05: id NULL y tipo inválido → intencion_clave_invalida (no intencion_tipo_invalido)');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', null, 'ingreso', '{"x":1}'),
  'ERR:PT400:intencion_clave_invalida', 'CR-ID-05: id NULL y payload inválido → intencion_clave_invalida (no intencion_payload_invalido)');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', null, 'venta', '{"x":1}'),
  'ERR:PT400:intencion_clave_invalida', 'CR-ID-05: id NULL, tipo y payload inválidos → intencion_clave_invalida');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', null, null, null),
  'ERR:PT400:intencion_clave_invalida', 'CR-ID-05: id NULL, tipo NULL y payload NULL → intencion_clave_invalida');
select is(pg_temp.n_int() || '/' || pg_temp.huella_libros(), (select n || '/' || libros from antes),
  'CR-ID-05: cero efectos persistentes');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '11111111-0000-4000-8000-0000000000d1', 'venta', (select v from k where nombre = 'PI')),
  'ERR:PT400:intencion_tipo_invalido', 'CR-ID-05 (control): con id válido, el tipo inválido conserva intencion_tipo_invalido');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '11111111-0000-4000-8000-0000000000d2', 'merma', '{"x":1}'),
  'ERR:PT400:intencion_payload_invalido', 'CR-ID-05 (control): con id válido, el payload inválido conserva intencion_payload_invalido');

-- CR-ID-07 (estático): el nulo se rechaza antes de tipo/payload, del lock, de toda lectura y del INSERT.
select ok(
  (select position('intencion_clave_invalida' in lower(p.prosrc)) > 0
      and position('intencion_clave_invalida' in lower(p.prosrc)) < position('intencion_tipo_invalido' in lower(p.prosrc))
      and position('intencion_tipo_invalido' in lower(p.prosrc)) < position('intencion_payload_invalido' in lower(p.prosrc))
      and position('intencion_clave_invalida' in lower(p.prosrc)) < position('pg_advisory_xact_lock' in lower(p.prosrc))
      and position('intencion_clave_invalida' in lower(p.prosrc)) < position('public.intenciones_operacion' in lower(p.prosrc))
      and position('intencion_clave_invalida' in lower(p.prosrc)) < position('insert into' in lower(p.prosrc))
      and position('intencion_no_autenticado' in lower(p.prosrc)) < position('intencion_no_autorizado' in lower(p.prosrc))
      and position('intencion_no_autorizado' in lower(p.prosrc)) < position('intencion_clave_invalida' in lower(p.prosrc))
     from pg_proc p where p.oid = 'privado.crear_intencion_operacion(uuid,text,jsonb)'::regprocedure),
  'CR-ID-07 (S): orden PT401 → PT403 → clave nula → tipo → payload, y la clave nula precede al lock, a toda lectura de intenciones y al INSERT');

-- CR-ID-08: ejecutar y cancelar con identificador nulo.
select is(pg_temp.ejecutar('a2a2a2a2-0000-4000-8000-000000000001', null), 'ERR:PT404:intencion_no_encontrada', 'CR-ID-08: ejecutar con id nulo y autorización válida → PT404');
select is(pg_temp.cancelar('a2a2a2a2-0000-4000-8000-000000000001', null), 'ERR:PT404:intencion_no_encontrada', 'CR-ID-08: cancelar con id nulo y autorización válida → PT404');
select is(pg_temp.ejecutar('a2a2a2a2-0000-4000-8000-000000000003', null), 'ERR:PT403:intencion_no_autorizado', 'CR-ID-08: ejecutar con id nulo y vendedor_piloto → PT403');
select is(pg_temp.cancelar('a2a2a2a2-0000-4000-8000-000000000004', null), 'ERR:PT403:intencion_no_autorizado', 'CR-ID-08: cancelar con id nulo y perfil inactivo → PT403');
select is(pg_temp.llamar('authenticated', '{"role":"authenticated"}', $q$select public.cancelar_intencion_operacion(null)::text$q$),
  'ERR:PT401:intencion_no_autenticado', 'CR-ID-08: cancelar con id nulo sin identidad → PT401');
select is(pg_temp.llamar('anon', '{"role":"anon"}', $q$select public.ejecutar_intencion_operacion(null)::text$q$) like 'ERR:42501:%',
  true, 'CR-ID-08: ejecutar con id nulo como anon → 42501');
select is(pg_temp.n_int() || '/' || pg_temp.huella_libros(), (select n || '/' || libros from antes),
  'CR-ID-08: sin intenciones creadas ni estados modificados');

-- ===========================================================================
-- E. Compuerta por actor y tipo (anexo §5.2, §5.3; LM-02, LM-07a, G-R)
-- ===========================================================================
-- A1 tiene pendientes de ingreso (…01), a_cuarentena (…02) y merma (…03).
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '22222222-0000-4000-8000-000000000001', 'ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT409:intencion_sin_resolver', 'LM-02: segunda intención del mismo tipo con una pendiente → PT409 intencion_sin_resolver');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '22222222-0000-4000-8000-000000000002', 'merma', (select v from k where nombre = 'PM')),
  'ERR:PT409:intencion_sin_resolver', 'LM-02: ídem para merma');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000009', '22222222-0000-4000-8000-000000000003', 'ingreso', (select v from k where nombre = 'PI')),
  'OK:22222222-0000-4000-8000-000000000003', 'LM-07a: otro actor, mismo tipo → no se bloquean entre sí');
delete from public.intenciones_operacion where id = '22222222-0000-4000-8000-000000000003';

-- Replay con la compuerta cerrada: devuelve el id (orden replay → compuerta).
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001', 'ingreso', (select v from k where nombre = 'PI')),
  'OK:11111111-0000-4000-8000-000000000001', 'LM-07p: replay con algo sin resolver del mismo tipo → devuelve el id, no PT409 sin_resolver');

-- Pendiente vencida sigue bloqueando.
update public.intenciones_operacion
   set creado_en = clock_timestamp() - interval '25 hours', vence_en = clock_timestamp() - interval '1 hour'
 where id = '11111111-0000-4000-8000-000000000001' and actor_id = 'a2a2a2a2-0000-4000-8000-000000000001';
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '22222222-0000-4000-8000-000000000004', 'ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT409:intencion_sin_resolver', 'Una pendiente VENCIDA sigue bloqueando su tipo');

-- G-R: rechazada, cancelada y confirmada reconocida no bloquean; confirmada sin reconocer sí.
select pg_temp.sembrar('a2a2a2a2-0000-4000-8000-000000000009', '33333333-0000-4000-8000-000000000001', 'merma', 'rechazada');
select pg_temp.sembrar('a2a2a2a2-0000-4000-8000-000000000009', '33333333-0000-4000-8000-000000000002', 'a_cuarentena', 'cancelada');
select pg_temp.sembrar('a2a2a2a2-0000-4000-8000-000000000009', '33333333-0000-4000-8000-000000000003', 'ingreso', 'confirmada');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000009', '33333333-0000-4000-8000-0000000000a1', 'merma', (select v from k where nombre = 'PM')),
  'OK:33333333-0000-4000-8000-0000000000a1', 'G-R: una rechazada no bloquea su tipo');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000009', '33333333-0000-4000-8000-0000000000a2', 'a_cuarentena', (select v from k where nombre = 'PC')),
  'OK:33333333-0000-4000-8000-0000000000a2', 'G-R: una cancelada no bloquea su tipo');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000009', '33333333-0000-4000-8000-0000000000a3', 'ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT409:intencion_sin_resolver', 'Una confirmada SIN reconocer bloquea su tipo');
select pg_temp.reconocer_sql('a2a2a2a2-0000-4000-8000-000000000009', '33333333-0000-4000-8000-000000000003');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000009', '33333333-0000-4000-8000-0000000000a4', 'ingreso', (select v from k where nombre = 'PI')),
  'OK:33333333-0000-4000-8000-0000000000a4', 'G-R: una confirmada con reconocimiento no bloquea su tipo');
select is(pg_temp.crear('b2b2b2b2-0000-4000-8000-000000000001', '33333333-0000-4000-8000-0000000000a5', 'a_cuarentena', (select v from k where nombre = 'PC')),
  'OK:33333333-0000-4000-8000-0000000000a5', 'G-R: lo sin resolver de otra empresa no bloquea');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000002', '33333333-0000-4000-8000-0000000000a6', 'a_cuarentena', (select v from k where nombre = 'PC')),
  'OK:33333333-0000-4000-8000-0000000000a6', 'G-R: lo sin resolver de otro actor de la misma empresa no bloquea');

-- ===========================================================================
-- F. Topes (LM-01', TP-02…05 del laboratorio): 20 sin resolver y 120 por hora
-- ===========================================================================
-- A5: 19 pendientes de merma (fixture; la compuerta impide llegar así por crear).
insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, vence_en)
select ('55555555-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid, 'a2a2a2a2-0000-4000-8000-000000000000',
       'a2a2a2a2-0000-4000-8000-000000000005', 'merma',
       '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","ubicacion_origen_id":"e2e2e2e2-0000-4000-8000-0000000000d1","cantidad":1,"motivo_codigo":"vencido","motivo":null}'::jsonb,
       clock_timestamp() + interval '24 hours'
  from generate_series(1, 19) g;
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000005', '55555555-0000-4000-8000-0000000000f1', 'merma', (select v from k where nombre = 'PM')),
  'ERR:PT409:intencion_sin_resolver', 'Orden compuerta → topes: mismo tipo con 19 pendientes → PT409 (no PT429)');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000005', '55555555-0000-4000-8000-0000000000f2', 'ingreso', (select v from k where nombre = 'PI')),
  'OK:55555555-0000-4000-8000-0000000000f2', 'TP: con 19 sin resolver, el 20.º (otro tipo) se acepta');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000005', '55555555-0000-4000-8000-0000000000f3', 'a_cuarentena', (select v from k where nombre = 'PC')),
  'ERR:PT429:intencion_limite_excedido', 'TP: con 20 sin resolver, el 21.º (otro tipo) → PT429 intencion_limite_excedido');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000005', '55555555-0000-4000-8000-0000000000f2', 'ingreso', (select v from k where nombre = 'PI')),
  'OK:55555555-0000-4000-8000-0000000000f2', 'LM-07p: replay con 20 sin resolver y tope alcanzado → devuelve el id (no PT429)');
select is((select count(*)::int from public.intenciones_operacion where actor_id = 'a2a2a2a2-0000-4000-8000-000000000005'), 20,
  'TP: nunca más de 20 sin resolver');

-- CR-ID-06: el nulo precede a compuerta y topes.
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000005', null, 'ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT400:intencion_clave_invalida', 'CR-ID-06: id nulo con 20 sin resolver y compuerta cerrada → intencion_clave_invalida (no PT429 ni PT409)');
select is((select count(*)::int from public.intenciones_operacion where actor_id = 'a2a2a2a2-0000-4000-8000-000000000005'), 20,
  'CR-ID-06: el rechazo por id nulo no cuenta para los topes ni escribe');

-- Vencidas cuentan como sin resolver (todos los tipos y vigencias).
update public.intenciones_operacion set creado_en = clock_timestamp() - interval '30 hours', vence_en = clock_timestamp() - interval '6 hours'
 where actor_id = 'a2a2a2a2-0000-4000-8000-000000000005' and tipo = 'merma';
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000005', '55555555-0000-4000-8000-0000000000f4', 'a_cuarentena', (select v from k where nombre = 'PC')),
  'ERR:PT429:intencion_limite_excedido', 'TP: las vencidas siguen contando como sin resolver para el tope de 20');

-- Tope horario: A6 con 119 canceladas creadas hace instantes (no bloquean).
insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, estado, creado_en, vence_en, resuelto_en)
select ('66666666-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid, 'a2a2a2a2-0000-4000-8000-000000000000',
       'a2a2a2a2-0000-4000-8000-000000000006', 'ingreso',
       '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","cantidad":1,"motivo":null}'::jsonb, 'cancelada',
       clock_timestamp() - interval '10 minutes', clock_timestamp() + interval '23 hours', clock_timestamp() - interval '9 minutes'
  from generate_series(1, 119) g;
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000006', '66666666-0000-4000-8000-0000000000f1', 'ingreso', (select v from k where nombre = 'PI')),
  'OK:66666666-0000-4000-8000-0000000000f1', 'TP: con 119 creaciones en la última hora, la 120.ª se acepta');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000006', '66666666-0000-4000-8000-0000000000f2', 'merma', (select v from k where nombre = 'PM')),
  'ERR:PT429:intencion_limite_excedido', 'TP: la 121.ª en la última hora → PT429 intencion_limite_excedido');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000006', '66666666-0000-4000-8000-0000000000f1', 'ingreso', (select v from k where nombre = 'PI')),
  'OK:66666666-0000-4000-8000-0000000000f1', 'TP: el replay con el tope horario alcanzado devuelve el id y no cuenta');
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000001', '66666666-0000-4000-8000-0000000000f3', 'ingreso', (select v from k where nombre = 'PI')),
  'ERR:PT409:intencion_sin_resolver', 'TP: el tope horario es por actor (A1 sigue evaluando su propia compuerta)');
-- A7: 130 creaciones hace 2 h no cuentan en la ventana de 1 h.
insert into public.intenciones_operacion (id, empresa_id, actor_id, tipo, payload, estado, creado_en, vence_en, resuelto_en)
select ('77777777-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid, 'a2a2a2a2-0000-4000-8000-000000000000',
       'a2a2a2a2-0000-4000-8000-000000000007', 'ingreso',
       '{"producto_id":"e2e2e2e2-0000-4000-8000-0000000000f1","cantidad":1,"motivo":null}'::jsonb, 'cancelada',
       clock_timestamp() - interval '2 hours', clock_timestamp() + interval '22 hours', clock_timestamp() - interval '119 minutes'
  from generate_series(1, 130) g;
select is(pg_temp.crear('a2a2a2a2-0000-4000-8000-000000000007', '77777777-0000-4000-8000-0000000000f1', 'ingreso', (select v from k where nombre = 'PI')),
  'OK:77777777-0000-4000-8000-0000000000f1', 'TP: 130 creaciones de hace 2 h no cuentan para el tope horario');

-- Ningún rechazo anterior (PT400/PT403/PT409/PT429) dejó filas: conteos coherentes.
select is((select count(*)::int from public.intenciones_operacion where actor_id = 'a2a2a2a2-0000-4000-8000-000000000006'), 120,
  'TP: A6 tiene exactamente 119 sembradas + 1 creada (120); ninguna de las rechazadas escribió');

-- ===========================================================================
-- G. Seguridad de las seis funciones (ES-04, NG-06) y revisión estática (ES-05)
-- ===========================================================================
select is(
  (select string_agg(x.proname || ':' || x.esquemas, ';' order by x.proname)
     from (select p.proname::text, string_agg(n.nspname::text, ',' order by n.nspname) as esquemas
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where p.proname like '%intencion%' group by p.proname) x),
  'cancelar_intencion_operacion:privado,public;crear_intencion_operacion:privado,public;ejecutar_intencion_operacion:privado,public',
  'ES-04: exactamente las tres RPC de C1.2a, cada una con privada y fachada, sin sobrecargas');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace and p.proname like '%intencion%'
      and p.prosecdef and p.provolatile = 'v' and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
      and p.proowner = 'propietario_rpc'::regrole and p.proconfig = array['search_path=""']
      and array(select a::text from unnest(p.proacl) a order by 1)
          = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']),
  3, 'ES-04: las 3 privadas son SECURITY DEFINER, VOLATILE, plpgsql, de propietario_rpc, con search_path vacío y ACL exacta');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname like '%intencion%'
      and not p.prosecdef and p.provolatile = 'v' and p.prolang = (select oid from pg_language where lanname = 'sql')
      and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']
      and array(select a::text from unnest(p.proacl) a order by 1)
          = array['authenticated=X/postgres', 'postgres=X/postgres']),
  3, 'ES-04: las 3 fachadas son SECURITY INVOKER, VOLATILE, sql, de postgres, con search_path vacío y ACL exacta');
select ok(
  not exists (
    select 1 from pg_proc p, unnest(array['anon', 'service_role']) r
     where p.proname like '%intencion%' and p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
       and has_function_privilege(r, p.oid, 'EXECUTE'))
  and not has_schema_privilege('propietario_rpc', 'privado', 'CREATE'),
  'NG-06/ES-04: anon y service_role sin EXECUTE en ninguna de las seis; propietario_rpc sin CREATE residual');
select is(
  (select p.oid::regprocedure::text || '|' || pg_get_function_result(p.oid)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'crear_intencion_operacion'),
  'crear_intencion_operacion(uuid,text,jsonb)|uuid', 'Firma exacta de crear: (uuid, text, jsonb) → uuid; p_payload es jsonb y no json (R-11)');
select is(
  (select p.oid::regprocedure::text || '|' || pg_get_function_result(p.oid)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'ejecutar_intencion_operacion'),
  'ejecutar_intencion_operacion(uuid)|TABLE(estado text, operacion_id uuid, codigo_rechazo text)', 'Firma exacta de ejecutar');
select is(
  (select p.oid::regprocedure::text || '|' || pg_get_function_result(p.oid)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'cancelar_intencion_operacion'),
  'cancelar_intencion_operacion(uuid)|text', 'Firma exacta de cancelar');
select is(
  (select pg_get_function_arguments(p.oid) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = 'crear_intencion_operacion'),
  'p_intencion_id uuid, p_tipo text, p_payload jsonb', 'Nombres de parámetros de crear conforme al contrato');

-- ES-05 (S) sobre `crear`.
select ok(
  (select lower(p.prosrc) !~ 'when\s+others' and lower(p.prosrc) !~ 'auth\.uid' and lower(p.prosrc) !~ 'auth\.'
      and lower(p.prosrc) !~ '\mexecute\M' and lower(p.prosrc) !~ '\mformat\s*\('
      and lower(p.prosrc) !~ 'user_metadata' and lower(p.prosrc) !~ 'for\s+update'
     from pg_proc p where p.oid = 'privado.crear_intencion_operacion(uuid,text,jsonb)'::regprocedure),
  'ES-05 (S): crear sin WHEN OTHERS, auth.uid(), user_metadata, SQL dinámico ni FOR UPDATE');
select is(
  (select (length(lower(p.prosrc)) - length(replace(lower(p.prosrc), 'from public.perfiles', ''))) / length('from public.perfiles')
     from pg_proc p where p.oid = 'privado.crear_intencion_operacion(uuid,text,jsonb)'::regprocedure),
  4, 'ES-05 (S): crear consulta perfiles en 4 sentencias (perfil, replay, compuerta+topes, relectura); replay y compuerta con autorización en la misma sentencia');
select is(
  (select (length(lower(p.prosrc)) - length(replace(lower(p.prosrc), 'left join public.intenciones_operacion', ''))) / length('left join public.intenciones_operacion')
     from pg_proc p where p.oid = 'privado.crear_intencion_operacion(uuid,text,jsonb)'::regprocedure),
  2, 'ES-05 (S): replay y relectura con LEFT JOIN desde perfiles (autorización y fila en la misma sentencia)');
select ok(
  (select position('hashtextextended' in lower(p.prosrc)) > 0 and position('pg_advisory_xact_lock' in lower(p.prosrc)) > 0
      and position('pg_advisory_lock(' in lower(p.prosrc)) = 0 and position('nowait' in lower(p.prosrc)) = 0
      and position('lock_timeout' in lower(p.prosrc)) = 0
     from pg_proc p where p.oid = 'privado.crear_intencion_operacion(uuid,text,jsonb)'::regprocedure),
  'ES-05 (S): lock de nivel 0 transaccional (xact), sin lock de sesión, sin NOWAIT ni lock_timeout');

-- Libros mayores: crear no toca operaciones ni movimientos (RF-06c, ES-07).
select is((select count(*)::int from public.movimientos_stock), (select split_part(h, '/', 2)::int from libros0),
  'Libros mayores: crear no escribe movimientos_stock');
select is((select count(*)::int from public.operaciones), (select split_part(h, '/', 1)::int from libros0) + 1,
  'Libros mayores: crear no escribe operaciones (solo la 1 operación sembrada para la fixture G-R)');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
      and p.proname like '%intencion%' and lower(p.prosrc) ~ 'insert\s+into\s+public\.(operaciones|movimientos_stock)'),
  0, 'RF-06c (S): ninguna función de intenciones inserta en operaciones ni en movimientos_stock');

select * from finish();

rollback;
