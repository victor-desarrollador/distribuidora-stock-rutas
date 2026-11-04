-- pgTAP: corrección extraordinaria T1/T2 — abrir_jornada y reasignar_vendedor
-- rechazan una transacción de sólo lectura (ADR-001 §6, §16 T14 y §18.4.3;
-- migración 20261104120000_jornadas_rpc_rechazo_solo_lectura.sql). Ejecutar sólo
-- en local.
--
-- PostgREST ejecuta GET y HEAD en una transacción READ ONLY. Como todo este
-- archivo corre en una única transacción de escritura, el modo de sólo lectura se
-- activa dentro de un subbloque (pg_temp.en_solo_lectura): set_config de
-- transaction_read_only = on (pasar a sólo lectura está permitido en cualquier
-- momento), la llamada y la captura de SQLSTATE y mensaje. El subbloque siempre
-- se revierte, y con él el modo; por eso «sin cambios» no basta como evidencia:
-- además se mide, con pg_stat_xact_user_tables (contadores del backend que la
-- reversión de una subtransacción no descuenta), que la RPC no leyó ninguna
-- tabla antes de rechazar. La prueba HTTP con PostgREST real está en
-- apps/web/tests/jornadas-rpc-http.spec.ts.
--
-- B es un fixture adversarial (aislamiento por empresa_id).

begin;

create extension if not exists pgtap with schema extensions;

select plan(74);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-5100-4000-8000-000000000000', 'Empresa A (sólo lectura)'),
  ('bbbbbbbb-5100-4000-8000-000000000000', 'Empresa B (sólo lectura)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-5100-4000-8000-000000000001', 'authenticated', 'authenticated', 'sl.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-5100-4000-8000-000000000002', 'authenticated', 'authenticated', 'sl.a2@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-5100-4000-8000-000000000003', 'authenticated', 'authenticated', 'sl.a3@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-5100-4000-8000-000000000004', 'authenticated', 'authenticated', 'sl.a4@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-5100-4000-8000-000000000005', 'authenticated', 'authenticated', 'sl.a5@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-5100-4000-8000-000000000006', 'authenticated', 'authenticated', 'sl.a6@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-5100-4000-8000-000000000001', 'authenticated', 'authenticated', 'sl.b1@usuarios.distribuidora.invalid', '{}'),
  ('dddddddd-5100-4000-8000-000000000001', 'authenticated', 'authenticated', 'sl.n1@usuarios.distribuidora.invalid', '{"rol":"dueno","empresa_id":"aaaaaaaa-5100-4000-8000-000000000000"}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-000000000000', 'sl.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-5100-4000-8000-000000000002', 'aaaaaaaa-5100-4000-8000-000000000000', 'sl.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-5100-4000-8000-000000000003', 'aaaaaaaa-5100-4000-8000-000000000000', 'sl.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-5100-4000-8000-000000000004', 'aaaaaaaa-5100-4000-8000-000000000000', 'sl.a4', 'A4', 'dueno', false),
  ('aaaaaaaa-5100-4000-8000-000000000005', 'aaaaaaaa-5100-4000-8000-000000000000', 'sl.a5', 'A5', 'vendedor_piloto', true),
  ('aaaaaaaa-5100-4000-8000-000000000006', 'aaaaaaaa-5100-4000-8000-000000000000', 'sl.a6', 'A6', 'vendedor_piloto', true),
  ('bbbbbbbb-5100-4000-8000-000000000001', 'bbbbbbbb-5100-4000-8000-000000000000', 'sl.b1', 'B1', 'dueno', true);

insert into public.camiones (id, empresa_id, patente, nombre, activo, creado_por) values
  ('aaaaaaaa-5100-4000-8000-0000000000c1', 'aaaaaaaa-5100-4000-8000-000000000000', 'SL-01', 'Camión SL1', true, 'aaaaaaaa-5100-4000-8000-000000000001'),
  ('aaaaaaaa-5100-4000-8000-0000000000c2', 'aaaaaaaa-5100-4000-8000-000000000000', 'SL-02', 'Camión SL2', true, 'aaaaaaaa-5100-4000-8000-000000000001'),
  ('aaaaaaaa-5100-4000-8000-0000000000c3', 'aaaaaaaa-5100-4000-8000-000000000000', 'SL-03', 'Camión SL3', true, 'aaaaaaaa-5100-4000-8000-000000000001');

create function pg_temp.como_usuario(uid uuid, metadata jsonb default '{}')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated', 'user_metadata', metadata)::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.sin_sub()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.como_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
end $$;

create function pg_temp.como_service_role()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
end $$;

create function pg_temp.hoy()
returns date language sql as $$
  select (now() at time zone 'America/Argentina/Tucuman')::date
$$;

-- Ejecuta la sentencia con transaction_read_only = on dentro de un subbloque que
-- siempre se revierte (también el modo). Devuelve
-- '<modo durante la llamada>|<SQLSTATE>|<message>'. Si la sentencia no falla,
-- el subbloque se revierte con ZZ999 «sin_error», para que el resultado lo
-- muestre y nada quede escrito.
create function pg_temp.en_solo_lectura(sentencia text)
returns text language plpgsql as $$
declare
  v_modo text;
  v_estado text;
  v_mensaje text;
begin
  begin
    perform pg_catalog.set_config('transaction_read_only', 'on', true);
    v_modo := pg_catalog.current_setting('transaction_read_only');
    execute sentencia;
    raise exception using errcode = 'ZZ999', message = 'sin_error';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_mensaje = message_text;
  end;
  return coalesce(v_modo, '?') || '|' || v_estado || '|' || v_mensaje;
end $$;

-- Conteo global de filas relacionadas con jornadas, leído como owner.
create function pg_temp.conteo()
returns text language sql security definer set search_path = '' as $$
  select (select count(*) from public.operaciones)::text
    || '|' || (select count(*) from public.jornadas)::text
    || '|' || (select count(*) from public.movimientos_stock)::text
    || '|' || (select count(*) from public.reasignaciones_vendedor)::text
    || '|' || (select count(*) from public.correcciones_jornada)::text
$$;

-- Lecturas (seq + idx scans) hechas por esta transacción sobre las tablas que
-- las dos RPC consultan. pg_stat_xact_user_tables acumula los contadores del
-- backend y no los descuenta cuando una subtransacción se revierte.
create function pg_temp.lecturas()
returns bigint language sql security definer set search_path = '' as $$
  select coalesce(sum(coalesce(s.seq_scan, 0) + coalesce(s.idx_scan, 0)), 0)::bigint
    from pg_catalog.pg_stat_xact_user_tables s
   where s.schemaname = 'public'
     and s.relname in ('perfiles', 'operaciones', 'jornadas', 'camiones',
                       'reasignaciones_vendedor')
$$;

create temp table snap (k text primary key, v text);
grant select, insert, update, delete on snap to public;
create function pg_temp.fijar()
returns void language sql security definer set search_path = '' as $$
  delete from pg_temp.snap;
  insert into pg_temp.snap values ('conteo', pg_temp.conteo());
  insert into pg_temp.snap values ('lecturas', pg_temp.lecturas()::text);
$$;
create function pg_temp.sin_cambios()
returns boolean language sql security definer set search_path = '' as $$
  select pg_temp.conteo() = (select v from pg_temp.snap where k = 'conteo')
$$;
create function pg_temp.sin_lecturas()
returns boolean language sql security definer set search_path = '' as $$
  select pg_temp.lecturas()::text = (select v from pg_temp.snap where k = 'lecturas')
$$;

grant execute on function pg_temp.como_usuario(uuid, jsonb) to public;
grant execute on function pg_temp.sin_sub() to public;
grant execute on function pg_temp.como_anon() to public;
grant execute on function pg_temp.como_service_role() to public;
grant execute on function pg_temp.hoy() to public;
grant execute on function pg_temp.en_solo_lectura(text) to public;
grant execute on function pg_temp.conteo() to public;
grant execute on function pg_temp.lecturas() to public;
grant execute on function pg_temp.fijar() to public;
grant execute on function pg_temp.sin_cambios() to public;
grant execute on function pg_temp.sin_lecturas() to public;

create temp table res (k text primary key, v uuid);
grant select, insert on res to public;

-- ---------------------------------------------------------------------------
-- 1. Catálogo: la guarda es la primera sentencia y no cambió nada más
-- ---------------------------------------------------------------------------
select is(
  (select encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex') from pg_proc p
    where p.oid = 'privado.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure),
  '7e2f2d07ffe75a90af6fba379c32d874ca3d229daa7c841f300aef5f467c5440',
  'privado.abrir_jornada: el cuerpo instalado es el de la migración correctiva con las calificaciones pg_temp de B1 (20261105130000)');
select is(
  (select encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex') from pg_proc p
    where p.oid = 'privado.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure),
  '6593c5e2e1ed10d47ca1d880eee3e53ff9809596987d5f33f8beedef6ba618dd',
  'privado.reasignar_vendedor: el cuerpo instalado es el de la migración correctiva con las calificaciones pg_temp de B1 (20261105130000)');
select ok(
  (select strpos(p.prosrc, E'\nbegin\n  -- Paso 0') > 0
      and strpos(p.prosrc, 'transaction_read_only') < strpos(p.prosrc, 'transaction_isolation')
      and strpos(p.prosrc, 'transaction_read_only') < strpos(p.prosrc, 'privado.usuario_actual()')
      and strpos(p.prosrc, 'transaction_read_only') < strpos(p.prosrc, 'public.operaciones')
      and strpos(p.prosrc, 'transaction_read_only') < strpos(p.prosrc, 'public.perfiles')
     from pg_proc p where p.oid = 'privado.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure),
  'abrir_jornada: la guarda va al comienzo, antes del paso 1, de la identidad, de perfiles y de operaciones');
select ok(
  (select strpos(p.prosrc, E'\nbegin\n  -- Paso 0') > 0
      and strpos(p.prosrc, 'transaction_read_only') < strpos(p.prosrc, 'transaction_isolation')
      and strpos(p.prosrc, 'transaction_read_only') < strpos(p.prosrc, 'privado.usuario_actual()')
      and strpos(p.prosrc, 'transaction_read_only') < strpos(p.prosrc, 'public.operaciones')
      and strpos(p.prosrc, 'transaction_read_only') < strpos(p.prosrc, 'public.perfiles')
     from pg_proc p where p.oid = 'privado.reasignar_vendedor(uuid, uuid, uuid)'::regprocedure),
  'reasignar_vendedor: la guarda va al comienzo, antes del paso 1, de la identidad, de perfiles y de operaciones');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('abrir_jornada', 'reasignar_vendedor')
      and p.prosecdef and p.proowner = 'propietario_rpc'::regrole
      and p.proconfig = array['search_path=""'] and p.provolatile = 'v'
      and array(select a::text from unnest(p.proacl) a order by 1)
          = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']),
  2, 'las dos implementaciones conservan SECURITY DEFINER, owner propietario_rpc, search_path vacío, VOLATILE y ACL exacta');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('abrir_jornada', 'reasignar_vendedor')
      and not p.prosecdef and p.proowner = 'postgres'::regrole
      and p.proconfig = array['search_path=""']
      and array(select a::text from unnest(p.proacl) a order by 1)
          = array['authenticated=X/postgres', 'postgres=X/postgres']),
  2, 'las dos fachadas siguen SECURITY INVOKER, de postgres, con search_path vacío y ACL exacta');
select ok(
  not has_schema_privilege('propietario_rpc', 'privado', 'create')
  and not has_schema_privilege('propietario_rpc', 'public', 'create'),
  'propietario_rpc no conserva CREATE sobre privado ni public tras la migración correctiva');
select is(
  (select count(*)::int from pg_proc
    where proname in ('abrir_jornada', 'reasignar_vendedor')
      and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)),
  4, 'sin sobrecargas nuevas');

-- ---------------------------------------------------------------------------
-- 2. abrir_jornada: estado previo en una transacción de escritura
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J1', public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$,
  'escritura: el dueño abre J1 con la clave K1 (llamada SQL legítima)');
reset role;
select is(current_setting('transaction_read_only'), 'off', 'la transacción de prueba es de escritura');

-- Control de sensibilidad del medidor de lecturas: una llamada de escritura
-- rechazada en el paso 2 (vendedor_piloto) sí lee perfiles.
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000003');
select throws_ok($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000099', 'aaaaaaaa-5100-4000-8000-0000000000c2', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000006')$q$,
  'PT403', 'jornada_no_autorizado', 'control: en escritura, vendedor_piloto sigue recibiendo PT403');
reset role;
select ok(not pg_temp.sin_lecturas(), 'control: el medidor detecta la lectura de perfiles de una llamada de escritura');

-- ---------------------------------------------------------------------------
-- 3. abrir_jornada en sólo lectura: siempre 25006, sin leer datos
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000001');
select is(pg_temp.en_solo_lectura($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000002', 'aaaaaaaa-5100-4000-8000-0000000000c2', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000006')$q$),
  'on|25006|jornada_metodo_no_permitido', 'abrir_jornada, sólo lectura, dueño, clave nueva: 25006 jornada_metodo_no_permitido');
select is(pg_temp.en_solo_lectura($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$),
  'on|25006|jornada_metodo_no_permitido', 'abrir_jornada, sólo lectura, clave ya usada y misma huella: 25006, no el uuid guardado');
select is(pg_temp.en_solo_lectura($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c2', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$),
  'on|25006|jornada_metodo_no_permitido', 'abrir_jornada, sólo lectura, clave ya usada y otra huella: 25006, no PT409');
select is(pg_temp.en_solo_lectura($q$select privado.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$),
  'on|25006|jornada_metodo_no_permitido', 'abrir_jornada, sólo lectura, implementación directa con clave usada: 25006');
reset role;
select is(current_setting('transaction_read_only'), 'off', 'abrir_jornada: el subbloque restauró el modo de escritura');
select ok(pg_temp.sin_lecturas(), 'abrir_jornada, dueño en sólo lectura: ninguna lectura de perfiles, operaciones, jornadas ni camiones');
select ok(pg_temp.sin_cambios(), 'abrir_jornada, dueño en sólo lectura: sin filas nuevas');

select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000002');
select is(pg_temp.en_solo_lectura($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000003', 'aaaaaaaa-5100-4000-8000-0000000000c2', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000006')$q$),
  'on|25006|jornada_metodo_no_permitido', 'abrir_jornada, sólo lectura, encargado: 25006');
reset role;
select pg_temp.sin_sub();
select is(pg_temp.en_solo_lectura($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$),
  'on|25006|jornada_metodo_no_permitido', 'abrir_jornada, sólo lectura, authenticated sin sub (anónimo de Auth): 25006, no PT401');
reset role;
select pg_temp.como_usuario('dddddddd-5100-4000-8000-000000000001');
select is(pg_temp.en_solo_lectura($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$),
  'on|25006|jornada_metodo_no_permitido', 'abrir_jornada, sólo lectura, cuenta sin perfil: 25006');
reset role;
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000003');
select is(pg_temp.en_solo_lectura($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$),
  'on|25006|jornada_metodo_no_permitido', 'abrir_jornada, sólo lectura, vendedor_piloto (rol no autorizado): 25006');
reset role;
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000004');
select is(pg_temp.en_solo_lectura($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$),
  'on|25006|jornada_metodo_no_permitido', 'abrir_jornada, sólo lectura, dueño inactivo: 25006');
reset role;
select pg_temp.como_usuario('bbbbbbbb-5100-4000-8000-000000000001');
select is(pg_temp.en_solo_lectura($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$),
  'on|25006|jornada_metodo_no_permitido', 'abrir_jornada, sólo lectura, dueño de otra empresa con la clave y el camión de A: 25006');
reset role;
select ok(pg_temp.sin_lecturas(), 'abrir_jornada, sólo lectura (encargado, sin sub, sin perfil, vendedor, inactivo, otra empresa): ninguna lectura de datos');
select ok(pg_temp.sin_cambios(), 'abrir_jornada, sólo lectura (encargado, sin sub, sin perfil, vendedor, inactivo, otra empresa): sin filas nuevas');

-- anon y service_role no tienen EXECUTE: el rechazo de privilegio precede al cuerpo.
select pg_temp.como_anon();
select is(split_part(pg_temp.en_solo_lectura($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$), '|', 2),
  '42501', 'abrir_jornada, sólo lectura, anon: 42501 (sin EXECUTE)');
reset role;
select pg_temp.como_service_role();
select is(split_part(pg_temp.en_solo_lectura($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$), '|', 2),
  '42501', 'abrir_jornada, sólo lectura, service_role: 42501 en la fachada (P11)');
select is(split_part(pg_temp.en_solo_lectura($q$select privado.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$), '|', 2),
  '42501', 'abrir_jornada, sólo lectura, service_role: 42501 en la implementación (P11)');
reset role;

-- ---------------------------------------------------------------------------
-- 4. abrir_jornada: después del rechazo, la escritura conserva la idempotencia
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J1r', public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c1', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$,
  'escritura posterior con K1 y los mismos parámetros');
reset role;
select is((select v from res where k = 'J1r'), (select v from res where k = 'J1'), 'la escritura posterior con K1 devuelve el uuid original');
select ok(pg_temp.sin_cambios(), 'el replay posterior no agrega filas');
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000001');
select throws_ok($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000001', 'aaaaaaaa-5100-4000-8000-0000000000c2', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000005')$q$,
  'PT409', 'jornada_conflicto_idempotencia', 'en escritura, K1 con otra huella sigue siendo PT409');
select lives_ok($q$insert into res select 'J2', public.abrir_jornada('51000000-5100-4000-8000-000000000002', 'aaaaaaaa-5100-4000-8000-0000000000c2', pg_temp.hoy() + 1, 'aaaaaaaa-5100-4000-8000-000000000006')$q$,
  'la clave rechazada en sólo lectura (K2) se ejecuta después como primera ejecución');
reset role;
select is((select count(*)::int from public.operaciones where idempotency_key = '51000000-5100-4000-8000-000000000002'), 1,
  'K2: exactamente una operación; el rechazo en sólo lectura no la reservó');
select is((select j.operacion_apertura_id from public.jornadas j where j.id = (select v from res where k = 'J2')),
  (select o.id from public.operaciones o where o.idempotency_key = '51000000-5100-4000-8000-000000000002'),
  'K2: la jornada nueva queda ligada a su operación');
select is((select count(*)::int from public.operaciones where idempotency_key = '51000000-5100-4000-8000-000000000003'), 0,
  'K3 (encargado, sólo lectura): ninguna operación');
select is((select count(*)::int from public.operaciones where idempotency_key = '51000000-5100-4000-8000-000000000001'), 1,
  'K1: sigue habiendo una sola operación');

-- ---------------------------------------------------------------------------
-- 5. reasignar_vendedor: estado previo en una transacción de escritura
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'J3', public.abrir_jornada('51000000-5100-4000-8000-000000000010', 'aaaaaaaa-5100-4000-8000-0000000000c3', pg_temp.hoy() + 2, 'aaaaaaaa-5100-4000-8000-000000000005')$q$,
  'escritura: el dueño abre J3 para reasignar');
reset role;
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R1', public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', (select v from res where k = 'J3'), 'aaaaaaaa-5100-4000-8000-000000000006')$q$,
  'escritura: el dueño reasigna J3 a A6 con la clave R1 (llamada SQL legítima)');
reset role;
select is((select vendedor_id from public.jornadas where id = (select v from res where k = 'J3')),
  'aaaaaaaa-5100-4000-8000-000000000006'::uuid, 'J3 quedó con A6');

-- ---------------------------------------------------------------------------
-- 6. reasignar_vendedor en sólo lectura: siempre 25006, sin leer datos
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000001');
select is(pg_temp.en_solo_lectura(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000002', %L, 'aaaaaaaa-5100-4000-8000-000000000005')$q$, (select v from res where k = 'J3'))),
  'on|25006|jornada_metodo_no_permitido', 'reasignar_vendedor, sólo lectura, dueño, clave nueva: 25006 jornada_metodo_no_permitido');
select is(pg_temp.en_solo_lectura(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3'))),
  'on|25006|jornada_metodo_no_permitido', 'reasignar_vendedor, sólo lectura, clave ya usada y misma huella: 25006, no el uuid guardado');
select is(pg_temp.en_solo_lectura(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000005')$q$, (select v from res where k = 'J3'))),
  'on|25006|jornada_metodo_no_permitido', 'reasignar_vendedor, sólo lectura, clave ya usada y otra huella: 25006, no PT409');
select is(pg_temp.en_solo_lectura(format($q$select privado.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3'))),
  'on|25006|jornada_metodo_no_permitido', 'reasignar_vendedor, sólo lectura, implementación directa con clave usada: 25006');
reset role;
select is(current_setting('transaction_read_only'), 'off', 'reasignar_vendedor: el subbloque restauró el modo de escritura');
select ok(pg_temp.sin_lecturas(), 'reasignar_vendedor, dueño en sólo lectura: ninguna lectura de perfiles, operaciones ni jornadas');
select ok(pg_temp.sin_cambios(), 'reasignar_vendedor, dueño en sólo lectura: sin filas nuevas');

select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000002');
select is(pg_temp.en_solo_lectura(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000003', %L, 'aaaaaaaa-5100-4000-8000-000000000005')$q$, (select v from res where k = 'J3'))),
  'on|25006|jornada_metodo_no_permitido', 'reasignar_vendedor, sólo lectura, encargado: 25006');
reset role;
select pg_temp.sin_sub();
select is(pg_temp.en_solo_lectura(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3'))),
  'on|25006|jornada_metodo_no_permitido', 'reasignar_vendedor, sólo lectura, authenticated sin sub (anónimo de Auth): 25006, no PT401');
reset role;
select pg_temp.como_usuario('dddddddd-5100-4000-8000-000000000001');
select is(pg_temp.en_solo_lectura(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3'))),
  'on|25006|jornada_metodo_no_permitido', 'reasignar_vendedor, sólo lectura, cuenta sin perfil: 25006');
reset role;
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000003');
select is(pg_temp.en_solo_lectura(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3'))),
  'on|25006|jornada_metodo_no_permitido', 'reasignar_vendedor, sólo lectura, vendedor_piloto (rol no autorizado): 25006');
reset role;
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000004');
select is(pg_temp.en_solo_lectura(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3'))),
  'on|25006|jornada_metodo_no_permitido', 'reasignar_vendedor, sólo lectura, dueño inactivo: 25006');
reset role;
select pg_temp.como_usuario('bbbbbbbb-5100-4000-8000-000000000001');
select is(pg_temp.en_solo_lectura(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3'))),
  'on|25006|jornada_metodo_no_permitido', 'reasignar_vendedor, sólo lectura, dueño de otra empresa con la jornada de A: 25006');
reset role;
select ok(pg_temp.sin_lecturas(), 'reasignar_vendedor, sólo lectura (encargado, sin sub, sin perfil, vendedor, inactivo, otra empresa): ninguna lectura de datos');
select ok(pg_temp.sin_cambios(), 'reasignar_vendedor, sólo lectura (encargado, sin sub, sin perfil, vendedor, inactivo, otra empresa): sin filas nuevas');

select pg_temp.como_anon();
select is(split_part(pg_temp.en_solo_lectura(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3'))), '|', 2),
  '42501', 'reasignar_vendedor, sólo lectura, anon: 42501 (sin EXECUTE)');
reset role;
select pg_temp.como_service_role();
select is(split_part(pg_temp.en_solo_lectura(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3'))), '|', 2),
  '42501', 'reasignar_vendedor, sólo lectura, service_role: 42501 en la fachada (P11)');
select is(split_part(pg_temp.en_solo_lectura(format($q$select privado.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3'))), '|', 2),
  '42501', 'reasignar_vendedor, sólo lectura, service_role: 42501 en la implementación (P11)');
reset role;

-- ---------------------------------------------------------------------------
-- 7. reasignar_vendedor: después del rechazo, la escritura conserva la idempotencia
-- ---------------------------------------------------------------------------
select pg_temp.fijar();
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000001');
select lives_ok($q$insert into res select 'R1r', public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', (select v from res where k = 'J3'), 'aaaaaaaa-5100-4000-8000-000000000006')$q$,
  'escritura posterior con R1 y los mismos parámetros');
reset role;
select is((select v from res where k = 'R1r'), (select v from res where k = 'R1'), 'la escritura posterior con R1 devuelve el uuid de la operación original');
select ok(pg_temp.sin_cambios(), 'el replay posterior no agrega filas ni historial');
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000001');
select throws_ok(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000001', %L, 'aaaaaaaa-5100-4000-8000-000000000005')$q$, (select v from res where k = 'J3')),
  'PT409', 'jornada_conflicto_idempotencia', 'en escritura, R1 con otra huella sigue siendo PT409');
select lives_ok($q$insert into res select 'R2', public.reasignar_vendedor('52000000-5100-4000-8000-000000000002', (select v from res where k = 'J3'), 'aaaaaaaa-5100-4000-8000-000000000005')$q$,
  'la clave rechazada en sólo lectura (R2) se ejecuta después como primera ejecución');
reset role;
select is((select count(*)::int from public.operaciones where idempotency_key = '52000000-5100-4000-8000-000000000002'), 1,
  'R2: exactamente una operación; el rechazo en sólo lectura no la reservó');
select is((select count(*)::int from public.reasignaciones_vendedor where operacion_id = (select v from res where k = 'R2')), 1,
  'R2: una fila de historial ligada a su operación');
select is((select vendedor_id from public.jornadas where id = (select v from res where k = 'J3')),
  'aaaaaaaa-5100-4000-8000-000000000005'::uuid, 'R2: J3 volvió a A5');
select is((select count(*)::int from public.operaciones where idempotency_key = '52000000-5100-4000-8000-000000000003'), 0,
  'R3 (encargado, sólo lectura): ninguna operación');
select is((select count(*)::int from public.reasignaciones_vendedor where jornada_id = (select v from res where k = 'J3')), 2,
  'J3: exactamente dos reasignaciones confirmadas (R1 y R2)');

-- ---------------------------------------------------------------------------
-- 8. Transacciones de escritura y otros niveles: sin cambios de comportamiento
-- ---------------------------------------------------------------------------
-- El paso 1 (READ COMMITTED) sigue vigente; la guarda no lo reemplaza. En este
-- archivo la transacción es READ COMMITTED; SERIALIZABLE no puede fijarse a mitad
-- de transacción, por eso se prueba la precedencia con el modo y no con el nivel.
select is(current_setting('transaction_isolation'), 'read committed', 'la transacción de prueba es READ COMMITTED');
select pg_temp.como_usuario('aaaaaaaa-5100-4000-8000-000000000003');
select throws_ok(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000098', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3')),
  'PT403', 'jornada_no_autorizado', 'en escritura, reasignar_vendedor con vendedor_piloto sigue en PT403');
reset role;
select pg_temp.sin_sub();
select throws_ok($q$select public.abrir_jornada('51000000-5100-4000-8000-000000000097', 'aaaaaaaa-5100-4000-8000-0000000000c2', pg_temp.hoy() + 3, 'aaaaaaaa-5100-4000-8000-000000000006')$q$,
  'PT401', 'jornada_no_autenticado', 'en escritura, abrir_jornada sin sub sigue en PT401');
reset role;
select pg_temp.como_usuario('bbbbbbbb-5100-4000-8000-000000000001');
select throws_ok(format($q$select public.reasignar_vendedor('52000000-5100-4000-8000-000000000096', %L, 'aaaaaaaa-5100-4000-8000-000000000006')$q$, (select v from res where k = 'J3')),
  'PT404', 'jornada_no_encontrada', 'en escritura, la jornada de A para el dueño de B sigue siendo PT404');
reset role;

select * from finish();
rollback;
