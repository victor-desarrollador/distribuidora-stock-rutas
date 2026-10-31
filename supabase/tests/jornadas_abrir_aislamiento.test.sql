-- pgTAP: T1 — guarda de aislamiento de abrir_jornada (ADR-001 §18.4.3, paso 1; P13-jornadas).
-- La RPC exige READ COMMITTED: los advisory locks sólo serializan el estado bajo ese nivel,
-- así que bajo REPEATABLE READ o SERIALIZABLE falla cerrada con PT500 jornada_error_interno,
-- antes de la identidad, la estructura y el replay. Ejecutar sólo en local.
--
-- El aislamiento se fija al abrir cada transacción, antes de cualquier consulta, y un archivo
-- pgTAP corre normalmente en una sola. Este archivo abre TRES, una por nivel, con un único
-- plan() y un único finish(). Cada pedido se ejecuta dentro de pg_temp.sandbox(), que carga
-- los datos de prueba, ejecuta el pedido con el claim indicado y fuerza el ROLLBACK de su
-- sub-transacción en cualquier caso: los COMMIT entre las tres partes sólo confirman el
-- estado interno de pgTAP (tablas temporales de la sesión). Si la guarda faltara y el pedido
-- prosperara, tampoco quedaría ninguna fila. Cada sandbox compara el conteo de filas de
-- operaciones, jornadas, movimientos e historiales antes y después del pedido.
-- El flujo concurrente (I10, I11 y K10) no se prueba acá.

begin isolation level read committed;

create extension if not exists pgtap with schema extensions;

select plan(33);

-- Conteo de filas de jornadas y operaciones, leído como owner (SECURITY DEFINER).
create function pg_temp.conteo()
returns text language sql security definer set search_path = '' as $$
  select (select count(*) from public.operaciones)::text
    || ',' || (select count(*) from public.jornadas)::text
    || ',' || (select count(*) from public.movimientos_stock)::text
    || ',' || (select count(*) from public.reasignaciones_vendedor)::text
    || ',' || (select count(*) from public.correcciones_jornada)::text
$$;

-- Suma d_op y d_jor a las dos primeras posiciones de un conteo.
create function pg_temp.mas(c text, d_op int, d_jor int)
returns text language sql as $$
  select (split_part(c, ',', 1)::int + d_op)::text || ',' || (split_part(c, ',', 2)::int + d_jor)::text
    || ',' || split_part(c, ',', 3) || ',' || split_part(c, ',', 4) || ',' || split_part(c, ',', 5)
$$;

-- Carga p_setup, ejecuta p_sql con el claim de p_actor (NULL = sin sub) como authenticated
-- y devuelve 'código#conteo antes#conteo después'. Siempre revierte lo que cargó.
create function pg_temp.sandbox(p_setup text, p_actor uuid, p_sql text)
returns text language plpgsql as $$
declare
  v_antes text;
  v_despues text;
  v_codigo text;
begin
  begin
    execute p_setup;
    v_antes := pg_temp.conteo();
    perform set_config('request.jwt.claims',
      case when p_actor is null then '{"role":"authenticated"}'
           else jsonb_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
    execute 'set local role authenticated';
    begin
      execute p_sql;
      v_codigo := 'OK';
    exception when others then
      v_codigo := sqlstate || ':' || sqlerrm;
    end;
    v_despues := pg_temp.conteo();
    raise exception using errcode = 'PX001', message = v_codigo || '#' || v_antes || '#' || v_despues;
  exception when sqlstate 'PX001' then
    return sqlerrm;
  end;
end $$;

grant execute on function pg_temp.conteo() to public;
grant execute on function pg_temp.mas(text, int, int) to public;
grant execute on function pg_temp.sandbox(text, uuid, text) to public;

create temp table fx (sql text);

insert into fx values ($fx$insert into public.empresas (id, nombre) values ('aaaaaaaa-1200-4000-8000-000000000000', 'Empresa A (aislamiento)');
insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-1200-4000-8000-000000000001', 'authenticated', 'authenticated', 'jai.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-1200-4000-8000-000000000003', 'authenticated', 'authenticated', 'jai.a3@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-1200-4000-8000-000000000006', 'authenticated', 'authenticated', 'jai.a6@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-1200-4000-8000-000000000007', 'authenticated', 'authenticated', 'jai.a7@usuarios.distribuidora.invalid', '{}');
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-1200-4000-8000-000000000001', 'aaaaaaaa-1200-4000-8000-000000000000', 'jai.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-1200-4000-8000-000000000003', 'aaaaaaaa-1200-4000-8000-000000000000', 'jai.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-1200-4000-8000-000000000006', 'aaaaaaaa-1200-4000-8000-000000000000', 'jai.a6', 'A6', 'vendedor_piloto', true),
  ('aaaaaaaa-1200-4000-8000-000000000007', 'aaaaaaaa-1200-4000-8000-000000000000', 'jai.a7', 'A7', 'vendedor_piloto', true);
insert into public.camiones (id, empresa_id, patente, nombre, creado_por) values
  ('aaaaaaaa-1200-4000-8000-0000000000c1', 'aaaaaaaa-1200-4000-8000-000000000000', 'JAI-01', 'Camión AI 1', 'aaaaaaaa-1200-4000-8000-000000000001'),
  ('aaaaaaaa-1200-4000-8000-0000000000c2', 'aaaaaaaa-1200-4000-8000-000000000000', 'JAI-02', 'Camión AI 2', 'aaaaaaaa-1200-4000-8000-000000000001');
with o as (
  insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
  values ('aaaaaaaa-1200-4000-8000-000000000000', 'aaaaaaaa-1200-4000-8000-000000000001', 'apertura_jornada', '12000000-1200-4000-8000-000000000001',
          encode(sha256(convert_to('v1|apertura_jornada|aaaaaaaa-1200-4000-8000-0000000000c1|2999-01-01|aaaaaaaa-1200-4000-8000-000000000006', 'UTF8')), 'hex'))
  returning id)
insert into public.jornadas (empresa_id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id)
select 'aaaaaaaa-1200-4000-8000-000000000000', date '2999-01-01', 'aaaaaaaa-1200-4000-8000-0000000000c1', 'aaaaaaaa-1200-4000-8000-000000000006', 'abierta', 'aaaaaaaa-1200-4000-8000-000000000001', o.id from o;$fx$);
create temp table r (k text primary key, v text);
grant select, insert on r to public;

-- ---------------------------------------------------------------------------
-- Parte 1. READ COMMITTED: la operación se admite
-- ---------------------------------------------------------------------------
select is(pg_catalog.current_setting('transaction_isolation'), 'read committed', 'la transacción de la parte 1 es READ COMMITTED');
insert into r select 'RC_valida', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000001'::uuid, $q$select public.abrir_jornada('12000000-1200-4000-8000-000000000002', 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'RC_privada', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000001'::uuid, $q$select privado.abrir_jornada('12000000-1200-4000-8000-000000000003', 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'RC_replay', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000001'::uuid, $q$select public.abrir_jornada('12000000-1200-4000-8000-000000000001', 'aaaaaaaa-1200-4000-8000-0000000000c1', date '2999-01-01', 'aaaaaaaa-1200-4000-8000-000000000006')$q$);
select is(split_part((select v from r where k = 'RC_valida'), '#', 1), 'OK', 'READ COMMITTED: el pedido válido por la fachada se admite');
select is(split_part((select v from r where k = 'RC_valida'), '#', 3), pg_temp.mas(split_part((select v from r where k = 'RC_valida'), '#', 2), 1, 1), 'READ COMMITTED: la apertura suma exactamente una operación y una jornada, sin movimientos ni historiales');
select is(split_part((select v from r where k = 'RC_privada'), '#', 1), 'OK', 'READ COMMITTED: el pedido válido por la implementación privada se admite');
select is(split_part((select v from r where k = 'RC_privada'), '#', 3), pg_temp.mas(split_part((select v from r where k = 'RC_privada'), '#', 2), 1, 1), 'READ COMMITTED: la implementación privada suma exactamente una operación y una jornada');
select is(split_part((select v from r where k = 'RC_replay'), '#', 1), 'OK', 'READ COMMITTED: el replay legítimo se admite');
select is(split_part((select v from r where k = 'RC_replay'), '#', 3), split_part((select v from r where k = 'RC_replay'), '#', 2), 'READ COMMITTED: el replay no agrega filas');
commit;

-- ---------------------------------------------------------------------------
-- Parte 2. REPEATABLE READ: PT500 jornada_error_interno, antes de identidad, estructura y replay
-- ---------------------------------------------------------------------------
begin isolation level repeatable read;

select is(pg_catalog.current_setting('transaction_isolation'), 'repeatable read', 'la transacción de la parte 2 es REPEATABLE READ');
insert into r select 'RR_valida', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000001'::uuid, $q$select public.abrir_jornada('12000000-1200-4000-8000-000000000002', 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'RR_privada', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000001'::uuid, $q$select privado.abrir_jornada('12000000-1200-4000-8000-000000000003', 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'RR_claveNull', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000001'::uuid, $q$select public.abrir_jornada(null, 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'RR_sinSub', pg_temp.sandbox((select sql from fx), null, $q$select public.abrir_jornada('12000000-1200-4000-8000-000000000004', 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'RR_vendedorPiloto', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000003'::uuid, $q$select public.abrir_jornada('12000000-1200-4000-8000-000000000005', 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'RR_replay', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000001'::uuid, $q$select public.abrir_jornada('12000000-1200-4000-8000-000000000001', 'aaaaaaaa-1200-4000-8000-0000000000c1', date '2999-01-01', 'aaaaaaaa-1200-4000-8000-000000000006')$q$);
select is(split_part((select v from r where k = 'RR_valida'), '#', 1), 'PT500:jornada_error_interno', 'REPEATABLE READ: pedido válido por la fachada → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'RR_valida'), '#', 3), split_part((select v from r where k = 'RR_valida'), '#', 2), 'REPEATABLE READ: pedido válido por la fachada: no se crearon operaciones, jornadas, movimientos ni historiales');
select is(split_part((select v from r where k = 'RR_privada'), '#', 1), 'PT500:jornada_error_interno', 'REPEATABLE READ: pedido válido por la implementación privada → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'RR_privada'), '#', 3), split_part((select v from r where k = 'RR_privada'), '#', 2), 'REPEATABLE READ: pedido válido por la implementación privada: no se crearon operaciones, jornadas, movimientos ni historiales');
select is(split_part((select v from r where k = 'RR_claveNull'), '#', 1), 'PT500:jornada_error_interno', 'REPEATABLE READ: clave nula (sin la guarda daría PT400 jornada_clave_invalida) → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'RR_claveNull'), '#', 3), split_part((select v from r where k = 'RR_claveNull'), '#', 2), 'REPEATABLE READ: clave nula (sin la guarda daría PT400 jornada_clave_invalida): no se crearon operaciones, jornadas, movimientos ni historiales');
select is(split_part((select v from r where k = 'RR_sinSub'), '#', 1), 'PT500:jornada_error_interno', 'REPEATABLE READ: sin sub en el JWT (sin la guarda daría PT401 jornada_no_autenticado) → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'RR_sinSub'), '#', 3), split_part((select v from r where k = 'RR_sinSub'), '#', 2), 'REPEATABLE READ: sin sub en el JWT (sin la guarda daría PT401 jornada_no_autenticado): no se crearon operaciones, jornadas, movimientos ni historiales');
select is(split_part((select v from r where k = 'RR_vendedorPiloto'), '#', 1), 'PT500:jornada_error_interno', 'REPEATABLE READ: vendedor_piloto (sin la guarda daría PT403 jornada_no_autorizado) → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'RR_vendedorPiloto'), '#', 3), split_part((select v from r where k = 'RR_vendedorPiloto'), '#', 2), 'REPEATABLE READ: vendedor_piloto (sin la guarda daría PT403 jornada_no_autorizado): no se crearon operaciones, jornadas, movimientos ni historiales');
select is(split_part((select v from r where k = 'RR_replay'), '#', 1), 'PT500:jornada_error_interno', 'REPEATABLE READ: replay legítimo (sin la guarda devolvería el uuid de la jornada original) → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'RR_replay'), '#', 3), split_part((select v from r where k = 'RR_replay'), '#', 2), 'REPEATABLE READ: replay legítimo (sin la guarda devolvería el uuid de la jornada original): no se crearon operaciones, jornadas, movimientos ni historiales');

commit;

-- ---------------------------------------------------------------------------
-- Parte 3. SERIALIZABLE: PT500 jornada_error_interno, antes de identidad, estructura y replay
-- ---------------------------------------------------------------------------
begin isolation level serializable;

select is(pg_catalog.current_setting('transaction_isolation'), 'serializable', 'la transacción de la parte 3 es SERIALIZABLE');
insert into r select 'SER_valida', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000001'::uuid, $q$select public.abrir_jornada('12000000-1200-4000-8000-000000000002', 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'SER_privada', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000001'::uuid, $q$select privado.abrir_jornada('12000000-1200-4000-8000-000000000003', 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'SER_claveNull', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000001'::uuid, $q$select public.abrir_jornada(null, 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'SER_sinSub', pg_temp.sandbox((select sql from fx), null, $q$select public.abrir_jornada('12000000-1200-4000-8000-000000000004', 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'SER_vendedorPiloto', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000003'::uuid, $q$select public.abrir_jornada('12000000-1200-4000-8000-000000000005', 'aaaaaaaa-1200-4000-8000-0000000000c2', (now() at time zone 'America/Argentina/Tucuman')::date + 1, 'aaaaaaaa-1200-4000-8000-000000000007')$q$);
insert into r select 'SER_replay', pg_temp.sandbox((select sql from fx), 'aaaaaaaa-1200-4000-8000-000000000001'::uuid, $q$select public.abrir_jornada('12000000-1200-4000-8000-000000000001', 'aaaaaaaa-1200-4000-8000-0000000000c1', date '2999-01-01', 'aaaaaaaa-1200-4000-8000-000000000006')$q$);
select is(split_part((select v from r where k = 'SER_valida'), '#', 1), 'PT500:jornada_error_interno', 'SERIALIZABLE: pedido válido por la fachada → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'SER_valida'), '#', 3), split_part((select v from r where k = 'SER_valida'), '#', 2), 'SERIALIZABLE: pedido válido por la fachada: no se crearon operaciones, jornadas, movimientos ni historiales');
select is(split_part((select v from r where k = 'SER_privada'), '#', 1), 'PT500:jornada_error_interno', 'SERIALIZABLE: pedido válido por la implementación privada → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'SER_privada'), '#', 3), split_part((select v from r where k = 'SER_privada'), '#', 2), 'SERIALIZABLE: pedido válido por la implementación privada: no se crearon operaciones, jornadas, movimientos ni historiales');
select is(split_part((select v from r where k = 'SER_claveNull'), '#', 1), 'PT500:jornada_error_interno', 'SERIALIZABLE: clave nula (sin la guarda daría PT400 jornada_clave_invalida) → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'SER_claveNull'), '#', 3), split_part((select v from r where k = 'SER_claveNull'), '#', 2), 'SERIALIZABLE: clave nula (sin la guarda daría PT400 jornada_clave_invalida): no se crearon operaciones, jornadas, movimientos ni historiales');
select is(split_part((select v from r where k = 'SER_sinSub'), '#', 1), 'PT500:jornada_error_interno', 'SERIALIZABLE: sin sub en el JWT (sin la guarda daría PT401 jornada_no_autenticado) → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'SER_sinSub'), '#', 3), split_part((select v from r where k = 'SER_sinSub'), '#', 2), 'SERIALIZABLE: sin sub en el JWT (sin la guarda daría PT401 jornada_no_autenticado): no se crearon operaciones, jornadas, movimientos ni historiales');
select is(split_part((select v from r where k = 'SER_vendedorPiloto'), '#', 1), 'PT500:jornada_error_interno', 'SERIALIZABLE: vendedor_piloto (sin la guarda daría PT403 jornada_no_autorizado) → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'SER_vendedorPiloto'), '#', 3), split_part((select v from r where k = 'SER_vendedorPiloto'), '#', 2), 'SERIALIZABLE: vendedor_piloto (sin la guarda daría PT403 jornada_no_autorizado): no se crearon operaciones, jornadas, movimientos ni historiales');
select is(split_part((select v from r where k = 'SER_replay'), '#', 1), 'PT500:jornada_error_interno', 'SERIALIZABLE: replay legítimo (sin la guarda devolvería el uuid de la jornada original) → PT500 jornada_error_interno');
select is(split_part((select v from r where k = 'SER_replay'), '#', 3), split_part((select v from r where k = 'SER_replay'), '#', 2), 'SERIALIZABLE: replay legítimo (sin la guarda devolvería el uuid de la jornada original): no se crearon operaciones, jornadas, movimientos ni historiales');

select * from finish();
rollback;
