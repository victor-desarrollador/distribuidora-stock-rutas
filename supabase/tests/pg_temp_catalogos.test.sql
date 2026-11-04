-- pgTAP: endurecimiento pg_temp de las RPC de catálogos y de los auxiliares
-- exigir_* — A2 (plan de remediación pg_temp, alternativa A; ADR-001 §17.1 y
-- §17.3; Blueprint §7.3). Objetos hostiles creados ANTES de la primera llamada
-- de la sesión; el caso «después de una llamada legítima» está en
-- pg_temp_catalogos_posterior.test.sql.
--
-- Atacante modelado: authenticated (TEMP por PUBLIC). Crea en pg_temp dominios
-- uuid, text, date y jsonb cuyo CHECK llama a pg_temp.sonda() (cuenta en
-- secuencias temporales, no transaccionales: una para authenticated y otra
-- para cualquier otro rol), vistas homónimas de las tablas de catálogos que
-- también llaman a la sonda, funciones homónimas (btrim, now) y un operador =
-- para text en pg_temp. Esperado: 0 ejecuciones como propietario_rpc.
--
-- Importante: pgTAP declara variables «text» sin esquema. Mientras existen los
-- objetos hostiles no se llama a pgTAP: las mediciones se registran con
-- pg_temp.intentar() (tipos calificados) en una tabla temporal y en
-- secuencias, los objetos hostiles se eliminan y recién entonces se afirma.
--
-- Alcance A2: 10 RPC SECURITY DEFINER de productos, camiones y clientes y los
-- auxiliares exigir_*. Stock (A3) y jornadas (B1) quedan fuera.
--
-- Ejecutar sólo en local: `supabase test db`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como propietario; se revierten al final). Ninguna RPC se
-- llama antes de crear los objetos hostiles.
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('a9a9a9a9-0000-4000-8000-000000000000', 'Empresa A (test pg_temp A2)'),
  ('b9b9b9b9-0000-4000-8000-000000000000', 'Empresa B (test pg_temp A2)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('a9a9a9a9-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pga2.a1@usuarios.distribuidora.invalid', '{}'),
  ('a9a9a9a9-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'pga2.a2@usuarios.distribuidora.invalid', '{}'),
  ('a9a9a9a9-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'pga2.a3@usuarios.distribuidora.invalid', '{}'),
  ('b9b9b9b9-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'pga2.b1@usuarios.distribuidora.invalid', '{}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('a9a9a9a9-0000-4000-8000-000000000001', 'a9a9a9a9-0000-4000-8000-000000000000', 'pga2.a1', 'Dueño A', 'dueno', true),
  ('a9a9a9a9-0000-4000-8000-000000000002', 'a9a9a9a9-0000-4000-8000-000000000000', 'pga2.a2', 'Encargado A', 'encargado', true),
  ('a9a9a9a9-0000-4000-8000-000000000003', 'a9a9a9a9-0000-4000-8000-000000000000', 'pga2.a3', 'Vendedor A', 'vendedor_piloto', true),
  ('b9b9b9b9-0000-4000-8000-000000000001', 'b9b9b9b9-0000-4000-8000-000000000000', 'pga2.b1', 'Dueño B', 'dueno', true);

-- Objetos de la empresa B (directos, sin RPC).
insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta, precio, creado_por) values
  ('b9b9b9b9-0000-4000-8000-0000000000f1', 'b9b9b9b9-0000-4000-8000-000000000000', 'PGA2-B1', 'Leche B', 'lacteos', 'unidad', 300, 'b9b9b9b9-0000-4000-8000-000000000001');
insert into public.camiones (id, empresa_id, patente, nombre, creado_por) values
  ('b9b9b9b9-0000-4000-8000-0000000000c1', 'b9b9b9b9-0000-4000-8000-000000000000', 'PGA2-B', 'Camión B', 'b9b9b9b9-0000-4000-8000-000000000001');
insert into public.clientes (id, empresa_id, nombre, telefono, estado_validacion, creado_por) values
  ('b9b9b9b9-0000-4000-8000-0000000000d1', 'b9b9b9b9-0000-4000-8000-000000000000', 'Cliente B', '381-900', 'pendiente', 'b9b9b9b9-0000-4000-8000-000000000001');

create temp table huella_b as
select (select md5(string_agg(p::text, '|' order by p.id)) from public.productos p
         where p.empresa_id = 'b9b9b9b9-0000-4000-8000-000000000000')
       || '/' || (select md5(string_agg(c::text, '|' order by c.id)) from public.camiones c
                   where c.empresa_id = 'b9b9b9b9-0000-4000-8000-000000000000')
       || '/' || (select md5(string_agg(c::text, '|' order by c.id)) from public.clientes c
                   where c.empresa_id = 'b9b9b9b9-0000-4000-8000-000000000000') as huella;

-- ===========================================================================
-- P8 — catálogo (antes de los objetos hostiles; no se llama ninguna RPC)
-- ===========================================================================
select is(
  (select string_agg(p.oid::regprocedure::text || '|' || encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex'), ','
                     order by p.oid::regprocedure::text)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('crear_producto', 'actualizar_producto', 'cambiar_estado_producto',
                        'crear_camion', 'actualizar_camion', 'cambiar_estado_camion',
                        'crear_cliente', 'actualizar_cliente', 'validar_cliente', 'cambiar_estado_cliente',
                        'exigir_gestor_productos', 'exigir_dueno_camiones', 'exigir_perfil_clientes')),
  'privado.actualizar_camion(uuid,text,text)|ec3c2fec0c84ae702b0690457821381403e010dbdd1160395d22d686875492ae,privado.actualizar_cliente(uuid,text,text,text,text)|314b9c995b364974146a98050c53ed6e962378af89aa750deebdf187c44e66fa,privado.actualizar_producto(uuid,text,text,numeric,integer)|9cba80d132f5e2a5db8ebb102418d37945547d2a8c6e4b720b8f4a87bf0cbfb0,privado.cambiar_estado_camion(uuid,boolean)|1065b36961150678cdd687a92cce75b73e90fca2909ea790b645fc91573cc1b3,privado.cambiar_estado_cliente(uuid,boolean)|72fe95006a8e4f5dfda473e7a6b70fd8e8e3e81f0e68040db6721be1b23bbfd1,privado.cambiar_estado_producto(uuid,boolean)|d3a5be682a9f13c677c087fa1ab05e83d70527149abc5259b33959f95c3fc0b2,privado.crear_camion(text,text)|ac846c7cb86ca1ea7fbf675f6ac4698b473517399f14d4fd31ce3d54715815bf,privado.crear_cliente(text,text,text,text)|b05182fe2a5c5b9f40ea6156a54cb2e3d77a7b282171468e43981a3a76ce832b,privado.crear_producto(text,text,text,text,numeric,integer)|1d7975632846bc9afbf6ac2d5706b4ae594fca766a448dc9d5a0e2e7d62b0445,privado.exigir_dueno_camiones()|22bdccf7372b52ec6c35faad3f71fc2f270b0e57061ebe63fed6b588a3811f30,privado.exigir_gestor_productos()|2db9f4fbfa108f8ea78b6a65787a3ccbfcefd0d50bb0f11b8c670035b1fd1ae1,privado.exigir_perfil_clientes(boolean)|d9baf6136cbb425296ba838b64e9ab062175bf11952ea663aa170b94a4cdf03a,privado.validar_cliente(uuid)|3a27c544b3fa7e1e7701144c6de5cf9926f3cfc7e2478ba1291f23dd1ca7cc52',
  'P8: los 13 cuerpos son exactamente los de A2 (SHA-256)');

select is(
  (select string_agg(p.oid::regprocedure::text || '|'
                     || encode(sha256(convert_to(replace(p.prosrc, 'pg_catalog.', ''), 'UTF8')), 'hex'), ','
                     order by p.oid::regprocedure::text)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('crear_producto', 'actualizar_producto', 'cambiar_estado_producto',
                        'crear_camion', 'actualizar_camion', 'cambiar_estado_camion',
                        'crear_cliente', 'actualizar_cliente', 'validar_cliente', 'cambiar_estado_cliente',
                        'exigir_gestor_productos', 'exigir_dueno_camiones', 'exigir_perfil_clientes')),
  'privado.actualizar_camion(uuid,text,text)|071bafa17b64a40baf0829977e1e69d525918719aff64a9a64581ceb91c866b0,privado.actualizar_cliente(uuid,text,text,text,text)|cb64fccf120364b603e6abd4380b3421137fae685351097fb5d8febeaa0a6ed5,privado.actualizar_producto(uuid,text,text,numeric,integer)|83a1d8a927fe1377570e9c63eeba16a3bfc29844cd9c4bf89cd438006a57765f,privado.cambiar_estado_camion(uuid,boolean)|570b1fe97adb23ac3baa2c32fb023f505ba56d056567edfe88a70ac6cc0e527c,privado.cambiar_estado_cliente(uuid,boolean)|b9f84955c1ceb5bdd8caa9034f4eb53b4d14cc93110ede2e3b10d1aa500d5400,privado.cambiar_estado_producto(uuid,boolean)|7933b7b7f06a0e815f30e03d9d35dea231b16643529008f8f3b92a13d3b4c1ea,privado.crear_camion(text,text)|87a2b750e2969527bdaae655442dc3e4563f73aac02ad5e0acbcd81cda9a64f2,privado.crear_cliente(text,text,text,text)|88f8d9a9108ad8af72b1daea5434d51cb71aac663b9a611833cca63c14da6b4d,privado.crear_producto(text,text,text,text,numeric,integer)|a0a5a239d6eb60aca8f0a7a1309d4643d3054eef159e821ddfd42cee84355aa3,privado.exigir_dueno_camiones()|bb0231b89d69ff78085791636767ed85089253695d7e4e66568a90629cc27734,privado.exigir_gestor_productos()|46b64fe0545eb52fde282fb23645136e7b06ff8b7b9cafc9c843ca4771738fd1,privado.exigir_perfil_clientes(boolean)|9c11105d924ed7542f0243b2091316ae58722b7d5ec46d8492de43cc206025c4,privado.validar_cliente(uuid)|9fe8e7a142836c6c31ad8f4d5abd6b6f17ea037168c50e6eeb40ca675c3c1377',
  'P8: equivalencia mecánica — quitando «pg_catalog.» se obtienen los cuerpos anteriores (SHA-256 de las migraciones de catálogos)');

select is(
  (select string_agg(p.oid::regprocedure::text || '|'
                     || ((length(p.prosrc) - length(replace(p.prosrc, 'pg_catalog.', ''))) / length('pg_catalog.'))::text, ','
                     order by p.oid::regprocedure::text)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('crear_producto', 'actualizar_producto', 'cambiar_estado_producto',
                        'crear_camion', 'actualizar_camion', 'cambiar_estado_camion',
                        'crear_cliente', 'actualizar_cliente', 'validar_cliente', 'cambiar_estado_cliente',
                        'exigir_gestor_productos', 'exigir_dueno_camiones', 'exigir_perfil_clientes')),
  'privado.actualizar_camion(uuid,text,text)|2,privado.actualizar_cliente(uuid,text,text,text,text)|2,privado.actualizar_producto(uuid,text,text,numeric,integer)|2,privado.cambiar_estado_camion(uuid,boolean)|1,privado.cambiar_estado_cliente(uuid,boolean)|1,privado.cambiar_estado_producto(uuid,boolean)|1,privado.crear_camion(text,text)|3,privado.crear_cliente(text,text,text,text)|5,privado.crear_producto(text,text,text,text,numeric,integer)|3,privado.exigir_dueno_camiones()|3,privado.exigir_gestor_productos()|3,privado.exigir_perfil_clientes(boolean)|1,privado.validar_cliente(uuid)|2',
  'P8: cantidad exacta de calificaciones por función (29 en total)');

select is(
  (select string_agg(p.oid::regprocedure::text || '|' || encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex'), ','
                     order by p.oid::regprocedure::text)
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('validar_campos_producto', 'validar_campos_camion', 'validar_campos_cliente',
                        'error_restriccion_producto', 'error_restriccion_camion', 'error_restriccion_cliente',
                        'estado_http_restriccion_producto', 'estado_http_restriccion_camion',
                        'estado_http_restriccion_cliente', 'usuario_actual', 'empresa_gestion_actual')),
  'privado.empresa_gestion_actual()|6d0a758d68ffaf8f575e1faebb132dc29cab4400e81c953b6dc73ed475fce7cc,privado.error_restriccion_camion(text)|97bab45be0c746463b7fed6fa96592e6818bfd8d37bb9ef41e60fa08a830828c,privado.error_restriccion_cliente(text)|b1bdbb32a4a9b771f53be3eec6c61a64c23b0ab03978d4363f5d758f22354c25,privado.error_restriccion_producto(text)|1b657d872c70cdb11e466253bcedfed8efc847131871ff1086a2a073d94241b1,privado.estado_http_restriccion_camion(text)|d9eb261438f58974367dd8e01204d09b62ede7a1c9aa80e0d246e5e36970ee94,privado.estado_http_restriccion_cliente(text)|1849676097f40e4ed8840cb81de0f63465d40fdabad36d2046a8e8ee5d89be77,privado.estado_http_restriccion_producto(text)|71ca9fae34f47be07cadf9b9dbd627a080a4beb1bce48f4c7119a60c5faaa6a0,privado.usuario_actual()|2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96,privado.validar_campos_camion(text,text)|de1daf15134db8ca8662393740295f35f30970113e16c811881e5571c336c67c,privado.validar_campos_cliente(text,text)|8052ad0330f19eb2a3f69829ac2c4a974c36363e92cf4f5b8174cd4d2f3d2fc3,privado.validar_campos_producto(text,numeric,integer)|197030d06a5544b9cd98103595415cc07ab1603a0c81935baf13d9bb2e35ac0b',
  'P8: los 9 auxiliares sin referencias, usuario_actual (A1) y empresa_gestion_actual no cambian');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('crear_producto', 'actualizar_producto', 'cambiar_estado_producto',
                        'crear_camion', 'actualizar_camion', 'cambiar_estado_camion',
                        'crear_cliente', 'actualizar_cliente', 'validar_cliente', 'cambiar_estado_cliente')
      and p.prosecdef and p.provolatile = 'v'
      and p.proowner = 'propietario_rpc'::regrole
      and p.proconfig = array['search_path=""']
      and array(select a::text from unnest(p.proacl) a order by 1)
          = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']),
  10,
  'P8: las 10 RPC siguen SECURITY DEFINER, VOLATILE, de propietario_rpc, con search_path vacío y ACL exacta');

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('exigir_gestor_productos', 'exigir_dueno_camiones', 'exigir_perfil_clientes')
      and not p.prosecdef and p.provolatile = 's'
      and p.proowner = 'propietario_rpc'::regrole
      and p.proconfig = array['search_path=""']
      and array(select a::text from unnest(p.proacl) a order by 1) = array['propietario_rpc=X/propietario_rpc']),
  3,
  'P8: los 3 exigir_* siguen SECURITY INVOKER, STABLE, de propietario_rpc, con search_path vacío y sólo EXECUTE del owner');

select ok(
  not exists (
    select 1 from pg_proc p, unnest(array['anon', 'service_role']) r
     where p.pronamespace = 'privado'::regnamespace
       and has_function_privilege(r, p.oid, 'EXECUTE'))
  and not exists (
    select 1 from pg_proc p
     where p.pronamespace = 'privado'::regnamespace
       and p.proname in ('exigir_gestor_productos', 'exigir_dueno_camiones', 'exigir_perfil_clientes')
       and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  'P8/P11: anon y service_role sin EXECUTE en privado; authenticated sin EXECUTE en los exigir_*');

select ok(
  not has_schema_privilege('propietario_rpc', 'privado', 'CREATE')
  and not has_schema_privilege('propietario_rpc', 'public', 'CREATE')
  and (select nspacl::text from pg_namespace where nspname = 'privado')
      = '{postgres=UC/postgres,authenticated=U/postgres,propietario_rpc=U/postgres}',
  'P8: sin CREATE residual de propietario_rpc y ACL de privado sin cambios');

select is(
  (select string_agg(x.proname || ':' || x.esquemas, ';' order by x.proname)
     from (select p.proname::text, string_agg(n.nspname::text, ',' order by n.nspname) as esquemas
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where p.proname in ('crear_producto', 'actualizar_producto', 'cambiar_estado_producto',
                                'crear_camion', 'actualizar_camion', 'cambiar_estado_camion',
                                'crear_cliente', 'actualizar_cliente', 'validar_cliente', 'cambiar_estado_cliente',
                                'exigir_gestor_productos', 'exigir_dueno_camiones', 'exigir_perfil_clientes')
            group by p.proname) x),
  'actualizar_camion:privado,public;actualizar_cliente:privado,public;actualizar_producto:privado,public;cambiar_estado_camion:privado,public;cambiar_estado_cliente:privado,public;cambiar_estado_producto:privado,public;crear_camion:privado,public;crear_cliente:privado,public;crear_producto:privado,public;exigir_dueno_camiones:privado;exigir_gestor_productos:privado;exigir_perfil_clientes:privado;validar_cliente:privado,public',
  'P8: sin sobrecargas ni homónimos nuevos (implementaciones en privado y fachadas en public)');

select is(
  (select string_agg(m.member::regrole::text || '|' || m.admin_option::text || '|' || m.inherit_option::text
                     || '|' || m.set_option::text, ','
                     order by m.member::regrole::text, m.admin_option, m.inherit_option, m.set_option)
     from pg_auth_members m where m.roleid = 'propietario_rpc'::regrole)
  || ';' || (select count(*)::text from pg_auth_members m where m.member = 'propietario_rpc'::regrole)
  || ';' || (select rolreplication::text from pg_roles where rolname = 'propietario_rpc'),
  'postgres|false|false|true,postgres|true|false|false;0;false',
  'P8 (A1-B02): propietario_rpc NOREPLICATION, sin membresías propias; sólo la fila O-3 y la automática de PostgreSQL 16+');

-- ===========================================================================
-- P7 — guardia estática (léxica, sin literales ni comentarios)
-- ===========================================================================
-- (En las expresiones regulares de PostgreSQL la voracidad de toda la expresión
-- la fija el primer cuantificador: por eso «\s*?» al comienzo.)
-- Cuenta referencias resolubles por pg_temp: declaraciones del DECLARE con un
-- tipo sin esquema (salvo los tipos que son palabras clave de la gramática y
-- siempre resuelven a pg_catalog), casts «::» sin esquema, CAST(...),
-- %TYPE/%ROWTYPE y relaciones sin esquema tras FROM/JOIN/UPDATE/INSERT INTO/
-- DELETE FROM.
create function pg_temp.refs_sin_calificar(p_src pg_catalog.text)
returns pg_catalog.int4 language sql immutable as $f$
  with limpio as (
    select pg_catalog.regexp_replace(
             pg_catalog.regexp_replace(p_src, '''([^'']|'''')*''', '''''', 'g'),
             '--[^\n]*', '', 'g') as s
  ), declare_ as (
    select coalesce(pg_catalog.substring(l.s, '(?is)^\s*?declare(.*?)\mbegin\M'), '') as d, l.s
      from limpio l
  )
  select (select pg_catalog.count(*)::pg_catalog.int4
            from pg_catalog.regexp_matches(x.d,
                   '(?:^|;)\s*[a-z_][a-z0-9_]*\s+(?:constant\s+)?'
                   || '(?!pg_catalog\s*\.|(?:boolean|integer|int|smallint|bigint|numeric|decimal|real|double|varchar|character|char|timestamp|time|interval|bit)\M)'
                   || '[a-z_"]', 'gi'))
       + (select pg_catalog.count(*)::pg_catalog.int4
            from pg_catalog.regexp_matches(x.s,
                   '(::\s*(?!pg_catalog\s*\.)[a-z_"])'
                   || '|(\mcast\s*\()'
                   || '|(%\s*(row)?type\M)'
                   || '|(\m(from|join|update|insert\s+into|delete\s+from)\s+(?!(pg_catalog|public|privado|auth|extensions)\s*\.|\()[a-z_"])',
                   'gi'))
    from declare_ x
$f$;

select is(
  (select coalesce(string_agg(p.oid::regprocedure::text || '=' || pg_temp.refs_sin_calificar(p.prosrc)::text, ','
                              order by p.oid::regprocedure::text), '')
     from pg_proc p
    where p.pronamespace = 'privado'::regnamespace
      and p.proname in ('crear_producto', 'actualizar_producto', 'cambiar_estado_producto',
                        'crear_camion', 'actualizar_camion', 'cambiar_estado_camion',
                        'crear_cliente', 'actualizar_cliente', 'validar_cliente', 'cambiar_estado_cliente',
                        'exigir_gestor_productos', 'exigir_dueno_camiones', 'exigir_perfil_clientes',
                        'validar_campos_producto', 'validar_campos_camion', 'validar_campos_cliente',
                        'error_restriccion_producto', 'error_restriccion_camion', 'error_restriccion_cliente',
                        'estado_http_restriccion_producto', 'estado_http_restriccion_camion',
                        'estado_http_restriccion_cliente', 'usuario_actual', 'empresa_gestion_actual')
      and pg_temp.refs_sin_calificar(p.prosrc) > 0),
  '',
  'P7: ninguna de las 24 funciones de catálogos, auxiliares y A1 tiene referencias resolubles por pg_temp');

select is(
  (select pg_temp.refs_sin_calificar(replace(prosrc, 'pg_catalog.', '')) || '/'
          || (select pg_temp.refs_sin_calificar(replace(prosrc, 'pg_catalog.', ''))
                from pg_proc where oid = 'privado.crear_cliente(text,text,text,text)'::regprocedure)
     from pg_proc where oid = 'privado.crear_producto(text,text,text,text,numeric,integer)'::regprocedure),
  '3/5',
  'P7 (control M1): el detector encuentra las referencias de los cuerpos anteriores (crear_producto 3, crear_cliente 5)');

select is(
  (select pg_temp.refs_sin_calificar(replace(prosrc, 'pg_catalog.', ''))
     from pg_proc where oid = 'privado.exigir_perfil_clientes(boolean)'::regprocedure),
  1,
  'P7 (control): en exigir_perfil_clientes cuenta el uuid, no el boolean ni el destino de SELECT … INTO');

select is(
  pg_temp.refs_sin_calificar($m$
declare
  v_a pg_catalog.text := 'v_b uuid;';  -- v_c uuid;
  v_d date;
begin
  perform 'x'::pg_catalog.uuid;
end $m$),
  1,
  'P7 (control M2): una declaración en un literal o comentario no oculta la declaración real sin calificar');

-- ===========================================================================
-- P1 — objetos hostiles de authenticated ANTES de la primera llamada
-- ===========================================================================
create temp table resultados (caso pg_catalog.text, valor pg_catalog.text);
grant all on resultados to public;

-- Registro de mediciones: ejecuta una expresión como el rol vigente y guarda el
-- resultado o el SQLSTATE y el mensaje. Tipos calificados (se compila con los
-- objetos hostiles presentes).
create function pg_temp.intentar(p_caso pg_catalog.text, p_expresion pg_catalog.text)
returns pg_catalog.void language plpgsql as $f$
declare
  v_valor pg_catalog.text;
begin
  execute 'select (' || p_expresion || ')::pg_catalog.text' into v_valor;
  insert into pg_temp.resultados values (p_caso, 'ok:' || coalesce(v_valor, 'null'));
exception when others then
  insert into pg_temp.resultados values (p_caso, 'error:' || sqlstate || ':' || sqlerrm);
end $f$;
grant execute on function pg_temp.intentar(pg_catalog.text, pg_catalog.text) to public;

create function pg_temp.valor(p_caso pg_catalog.text) returns pg_catalog.text
language sql stable as $f$
  select pg_catalog.substr(r.valor, 4) from pg_temp.resultados r
   where r.caso operator(pg_catalog.=) p_caso
$f$;
grant execute on function pg_temp.valor(pg_catalog.text) to public;

-- Lectura de una secuencia de medición (sólo se usa sin objetos hostiles).
create function pg_temp.ejecuciones_secuencia(p_secuencia pg_catalog.regclass) returns pg_catalog.int8
language plpgsql as $f$
declare
  v pg_catalog.int8;
begin
  execute pg_catalog.format('select case when is_called then last_value else 0 end from %s', p_secuencia) into v;
  return v;
end $f$;

-- Calentamiento: un DROP inocuo compila los event triggers de sql_drop antes de
-- que existan objetos hostiles.
create temp table calentamiento_sql_drop ();
drop table calentamiento_sql_drop;

set local role authenticated;
create temp sequence sonda_privilegiada;
create temp sequence sonda_llamador;
create temp sequence control_directo;
create temp sequence control_mutante;
grant all on sequence sonda_privilegiada, sonda_llamador, control_directo, control_mutante to public;
create function pg_temp.sonda() returns pg_catalog.bool language plpgsql as $f$
begin
  if current_user operator(pg_catalog.=) 'authenticated' then
    perform pg_catalog.nextval('pg_temp.sonda_llamador'::pg_catalog.regclass);
  else
    perform pg_catalog.nextval('pg_temp.sonda_privilegiada'::pg_catalog.regclass);
  end if;
  return true;
end $f$;
grant execute on function pg_temp.sonda() to public;
-- Relaciones homónimas de las tablas de catálogos: leerlas ejecuta la sonda.
create temp view productos as select 1 as x where pg_temp.sonda();
create temp view camiones as select 1 as x where pg_temp.sonda();
create temp view clientes as select 1 as x where pg_temp.sonda();
create temp view perfiles as select 1 as x where pg_temp.sonda();
create temp view ubicaciones as select 1 as x where pg_temp.sonda();
-- Funciones y operador homónimos (pg_temp nunca se busca para funciones ni
-- operadores; se incluyen para comprobarlo).
create function pg_temp.btrim(pg_catalog.text) returns pg_catalog.text language plpgsql as $f$
begin perform pg_temp.sonda(); return $1; end $f$;
create function pg_temp.now() returns pg_catalog.timestamptz language plpgsql as $f$
begin perform pg_temp.sonda(); return pg_catalog.now(); end $f$;
create function pg_temp.igual_hostil(pg_catalog.text, pg_catalog.text) returns pg_catalog.bool
language plpgsql as $f$ begin perform pg_temp.sonda(); return $1 operator(pg_catalog.=) $2; end $f$;
create operator pg_temp.= (leftarg = pg_catalog.text, rightarg = pg_catalog.text,
                           function = pg_temp.igual_hostil);
grant execute on function pg_temp.btrim(pg_catalog.text), pg_temp.now(),
  pg_temp.igual_hostil(pg_catalog.text, pg_catalog.text) to public;
-- Los dominios van al final: los event triggers de la plataforma (pgrst_*,
-- grant_pg_*) son PL/pgSQL sin search_path propio y se compilan una vez por
-- sesión; ya quedaron compilados por el DDL anterior y por el calentamiento de
-- sql_drop, así que no capturan los dominios hostiles.
create domain pg_temp.uuid as pg_catalog.uuid check (pg_temp.sonda());
create domain pg_temp.text as pg_catalog.text check (pg_temp.sonda());
create domain pg_temp.date as pg_catalog.date check (pg_temp.sonda());
create domain pg_temp.jsonb as pg_catalog.jsonb check (pg_temp.sonda());
reset role;

insert into pg_temp.resultados
select 'hostiles',
       (select pg_catalog.count(*) from pg_catalog.pg_type t
         where t.typnamespace operator(pg_catalog.=) pg_catalog.pg_my_temp_schema() and t.typtype operator(pg_catalog.=) 'd'
           and t.typname operator(pg_catalog.=) any (array['uuid', 'text', 'date', 'jsonb']::pg_catalog.name[]))::pg_catalog.text
       || '/' || (select pg_catalog.count(*) from pg_catalog.pg_class c
                   where c.relnamespace operator(pg_catalog.=) pg_catalog.pg_my_temp_schema() and c.relkind operator(pg_catalog.=) 'v')::pg_catalog.text
       || '/' || (select pg_catalog.count(*) from pg_catalog.pg_proc p
                   where p.pronamespace operator(pg_catalog.=) pg_catalog.pg_my_temp_schema()
                     and p.proname operator(pg_catalog.=) any (array['btrim', 'now', 'igual_hostil']::pg_catalog.name[]))::pg_catalog.text
       || '/' || (select pg_catalog.count(*) from pg_catalog.pg_operator o
                   where o.oprnamespace operator(pg_catalog.=) pg_catalog.pg_my_temp_schema())::pg_catalog.text;

-- ===========================================================================
-- P3 / P4 — llamadas por las fachadas public como authenticated
-- ===========================================================================
set local role authenticated;

-- Vendedor de A: alta de cliente pendiente; rechazos por rol.
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"a9a9a9a9-0000-4000-8000-000000000003","role":"authenticated"}', true) is not null;
select pg_temp.intentar('cli_pend', $$public.crear_cliente('Cliente pendiente A', '381-100')$$);
select pg_temp.intentar('rol_crear_producto', $$public.crear_producto('PGA2-X', 'X', 'lacteos', 'unidad', 1, 0)$$);
select pg_temp.intentar('rol_crear_camion', $$public.crear_camion('PGA2-X', 'X')$$);
select pg_temp.intentar('rol_validar_cliente',
  pg_catalog.format('public.validar_cliente(%L::pg_catalog.uuid)', pg_temp.valor('cli_pend')));
select pg_temp.intentar('rol_estado_cliente',
  pg_catalog.format('public.cambiar_estado_cliente(%L::pg_catalog.uuid, false)', pg_temp.valor('cli_pend')));

-- Encargado de A: los camiones son sólo del dueño.
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"a9a9a9a9-0000-4000-8000-000000000002","role":"authenticated"}', true) is not null;
select pg_temp.intentar('rol_encargado_camion', $$public.crear_camion('PGA2-Y', 'Y')$$);

-- Sin perfil y sin identidad.
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"c9c9c9c9-0000-4000-8000-000000000001","role":"authenticated"}', true) is not null;
select pg_temp.intentar('sin_perfil', $$public.crear_producto('PGA2-Z', 'Z', 'lacteos', 'unidad', 1, 0)$$);
select pg_catalog.set_config('request.jwt.claims', '{"role":"authenticated"}', true) is not null;
select pg_temp.intentar('sin_identidad', $$public.crear_cliente('Z', '381-0')$$);

-- Dueño de A: las 10 RPC (crear_cliente y validar_cliente sobre el pendiente).
select pg_catalog.set_config('request.jwt.claims',
  '{"sub":"a9a9a9a9-0000-4000-8000-000000000001","role":"authenticated"}', true) is not null;
select pg_temp.intentar('prod', $$public.crear_producto('PGA2-A1', 'Leche A', 'lacteos', 'unidad', 100, 0)$$);
select pg_temp.intentar('act_prod',
  pg_catalog.format($$public.actualizar_producto(%L::pg_catalog.uuid, 'PGA2-A1B', 'Leche A2', 120.50, 3)$$, pg_temp.valor('prod')));
select pg_temp.intentar('est_prod',
  pg_catalog.format('public.cambiar_estado_producto(%L::pg_catalog.uuid, false)', pg_temp.valor('prod')));
select pg_temp.intentar('cam', $$public.crear_camion('PGA2-A', 'Camión A')$$);
select pg_temp.intentar('act_cam',
  pg_catalog.format($$public.actualizar_camion(%L::pg_catalog.uuid, 'PGA2-AB', 'Camión A2')$$, pg_temp.valor('cam')));
select pg_temp.intentar('est_cam',
  pg_catalog.format('public.cambiar_estado_camion(%L::pg_catalog.uuid, false)', pg_temp.valor('cam')));
select pg_temp.intentar('cli', $$public.crear_cliente('Cliente A', '381-200', 'Almacén A', null)$$);
select pg_temp.intentar('act_cli',
  pg_catalog.format($$public.actualizar_cliente(%L::pg_catalog.uuid, 'Cliente A2', '381-201', null, 'Calle 1')$$, pg_temp.valor('cli')));
select pg_temp.intentar('validar',
  pg_catalog.format('public.validar_cliente(%L::pg_catalog.uuid)', pg_temp.valor('cli_pend')));
select pg_temp.intentar('est_cli',
  pg_catalog.format('public.cambiar_estado_cliente(%L::pg_catalog.uuid, false)', pg_temp.valor('cli')));

-- Dueño de A con IDs de la empresa B.
select pg_temp.intentar('b_act_prod',
  $$public.actualizar_producto('b9b9b9b9-0000-4000-8000-0000000000f1'::pg_catalog.uuid, 'PGA2-B1', 'Pirata', 1, 0)$$);
select pg_temp.intentar('b_est_prod',
  $$public.cambiar_estado_producto('b9b9b9b9-0000-4000-8000-0000000000f1'::pg_catalog.uuid, false)$$);
select pg_temp.intentar('b_act_cam',
  $$public.actualizar_camion('b9b9b9b9-0000-4000-8000-0000000000c1'::pg_catalog.uuid, 'PIRATA', 'Pirata')$$);
select pg_temp.intentar('b_est_cam',
  $$public.cambiar_estado_camion('b9b9b9b9-0000-4000-8000-0000000000c1'::pg_catalog.uuid, false)$$);
select pg_temp.intentar('b_act_cli',
  $$public.actualizar_cliente('b9b9b9b9-0000-4000-8000-0000000000d1'::pg_catalog.uuid, 'Pirata', '381-666', null, null)$$);
select pg_temp.intentar('b_validar',
  $$public.validar_cliente('b9b9b9b9-0000-4000-8000-0000000000d1'::pg_catalog.uuid)$$);
select pg_temp.intentar('b_est_cli',
  $$public.cambiar_estado_cliente('b9b9b9b9-0000-4000-8000-0000000000d1'::pg_catalog.uuid, false)$$);
reset role;

insert into pg_temp.resultados
select 'medida_p3',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text
       || '/' || (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_llamador s)::pg_catalog.text;

-- ===========================================================================
-- P6 — control del detector: cuerpos anteriores reintroducidos
-- ===========================================================================
-- En un savepoint: CREATE transitorio, SET ROLE propietario_rpc (O-3) y los
-- cuerpos anteriores (quitando «pg_catalog.») de crear_producto y de su
-- auxiliar exigir_gestor_productos. Las mediciones van a secuencias porque el
-- ROLLBACK TO revierte la tabla de resultados.
select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
savepoint control_m1;
grant create on schema privado to propietario_rpc;
set local role propietario_rpc;
do $c$
begin
  execute pg_catalog.format(
    'create or replace function privado.exigir_gestor_productos() returns pg_catalog.uuid '
    || 'language plpgsql stable security invoker set search_path = %L as %L', '',
    (select pg_catalog.replace(p.prosrc, 'pg_catalog.', '') from pg_catalog.pg_proc p
      where p.oid operator(pg_catalog.=) 'privado.exigir_gestor_productos()'::pg_catalog.regprocedure));
  execute pg_catalog.format(
    'create or replace function privado.crear_producto(p_codigo pg_catalog.text, p_nombre pg_catalog.text, '
    || 'p_categoria pg_catalog.text, p_forma_venta pg_catalog.text, p_precio pg_catalog.numeric, '
    || 'p_stock_minimo pg_catalog.int4) returns pg_catalog.uuid language plpgsql volatile security definer '
    || 'set search_path = %L as %L', '',
    (select pg_catalog.replace(p.prosrc, 'pg_catalog.', '') from pg_catalog.pg_proc p
      where p.oid operator(pg_catalog.=) 'privado.crear_producto(pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.numeric, pg_catalog.int4)'::pg_catalog.regprocedure));
end $c$;
reset role;
revoke create on schema privado from propietario_rpc;
select pg_catalog.setval('pg_temp.control_mutante'::pg_catalog.regclass, 1,
  (select pg_catalog.string_agg(pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex'), ','
                                order by p.proname)
     from pg_catalog.pg_proc p
    where p.oid operator(pg_catalog.=) any (array['privado.crear_producto(pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.numeric, pg_catalog.int4)'::pg_catalog.regprocedure,
                                                  'privado.exigir_gestor_productos()'::pg_catalog.regprocedure]::pg_catalog.oid[]))
  operator(pg_catalog.=) 'a0a5a239d6eb60aca8f0a7a1309d4643d3054eef159e821ddfd42cee84355aa3,46b64fe0545eb52fde282fb23645136e7b06ff8b7b9cafc9c843ca4771738fd1');
set local role authenticated;
select pg_temp.intentar('m1', $$public.crear_producto('PGA2-M1', 'Mutante', 'lacteos', 'unidad', 1, 0)$$);
reset role;
select pg_catalog.setval('pg_temp.control_directo'::pg_catalog.regclass,
  (select case when s.is_called then s.last_value else 1 end from pg_temp.sonda_privilegiada s),
  (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s) operator(pg_catalog.>) 0);
rollback to savepoint control_m1;

-- Después del control: cuerpos calificados restaurados; la llamada vuelve a 0.
select pg_catalog.setval('pg_temp.sonda_privilegiada'::pg_catalog.regclass, 1, false) is not null;
set local role authenticated;
select pg_temp.intentar('post_m1', $$public.crear_producto('PGA2-M2', 'Post control', 'lacteos', 'unidad', 1, 0)$$);
reset role;
insert into pg_temp.resultados
select 'medida_post_m1',
       (select case when s.is_called then s.last_value else 0 end from pg_temp.sonda_privilegiada s)::pg_catalog.text;

-- Se eliminan los objetos hostiles antes de volver a usar pgTAP.
set local role authenticated;
drop domain pg_temp.uuid, pg_temp.text, pg_temp.date, pg_temp.jsonb;
drop operator pg_temp.= (pg_catalog.text, pg_catalog.text);
drop function pg_temp.igual_hostil(pg_catalog.text, pg_catalog.text), pg_temp.btrim(pg_catalog.text), pg_temp.now();
drop view pg_temp.productos, pg_temp.camiones, pg_temp.clientes, pg_temp.perfiles, pg_temp.ubicaciones;
drop function pg_temp.sonda();
reset role;

-- ===========================================================================
-- Afirmaciones (sin objetos hostiles)
-- ===========================================================================
select is((select valor from resultados where caso = 'hostiles'), '4/5/3/1',
  'P1: se crearon 4 dominios, 5 vistas homónimas, 3 funciones y 1 operador hostiles antes de la primera llamada');

select is(
  (select count(*)::int from resultados
    where caso in ('cli_pend', 'prod', 'act_prod', 'est_prod', 'cam', 'act_cam', 'est_cam',
                   'cli', 'act_cli', 'validar', 'est_cli')
      and valor like 'ok:%'),
  11,
  'P3: las 10 RPC (y el alta de un pendiente por el vendedor) completan con los objetos hostiles presentes');

select is(
  (select p.codigo || '|' || p.nombre || '|' || p.precio::text || '|' || p.stock_minimo::text || '|' || p.activo::text
     from public.productos p where p.id = (select substr(valor, 4)::uuid from resultados where caso = 'prod'))
  || ';' ||
  (select c.patente || '|' || c.nombre || '|' || c.activo::text || '|'
          || (select count(*)::text from public.ubicaciones u where u.camion_id = c.id and u.tipo = 'camion')
     from public.camiones c where c.id = (select substr(valor, 4)::uuid from resultados where caso = 'cam'))
  || ';' ||
  (select c.nombre || '|' || c.telefono || '|' || coalesce(c.comercio, '-') || '|' || coalesce(c.direccion, '-')
          || '|' || c.estado_validacion || '|' || c.activo::text
     from public.clientes c where c.id = (select substr(valor, 4)::uuid from resultados where caso = 'cli'))
  || ';' ||
  (select c.estado_validacion || '|' || c.validado_por::text || '|' || (c.validado_en is not null)::text
     from public.clientes c where c.id = (select substr(valor, 4)::uuid from resultados where caso = 'cli_pend')),
  'PGA2-A1B|Leche A2|120.50|3|false;PGA2-AB|Camión A2|false|1;Cliente A2|381-201|-|Calle 1|validado|false;validado|a9a9a9a9-0000-4000-8000-000000000001|true',
  'P3: equivalencia de comportamiento — estado final de producto, camión (con su ubicación), cliente y validación');

select is(
  (select string_agg(caso || '=' || valor, ' ; ' order by caso) from resultados
    where caso in ('rol_crear_producto', 'rol_crear_camion', 'rol_validar_cliente', 'rol_estado_cliente',
                   'rol_encargado_camion', 'sin_perfil', 'sin_identidad')),
  'rol_crear_camion=error:PT403:camion_no_autorizado ; rol_crear_producto=error:PT403:producto_no_autorizado ; rol_encargado_camion=error:PT403:camion_no_autorizado ; rol_estado_cliente=error:PT403:cliente_no_autorizado ; rol_validar_cliente=error:PT403:cliente_no_autorizado ; sin_identidad=error:PT401:cliente_no_autenticado ; sin_perfil=error:PT403:producto_no_autorizado',
  'P4: rechazos por rol, sin perfil y sin identidad, con los códigos estables');

select is(
  (select string_agg(caso || '=' || valor, ' ; ' order by caso) from resultados where caso like 'b\_%'),
  'b_act_cam=error:PT404:camion_no_encontrado ; b_act_cli=error:PT404:cliente_no_encontrado ; b_act_prod=error:PT404:producto_no_encontrado ; b_est_cam=error:PT404:camion_no_encontrado ; b_est_cli=error:PT404:cliente_no_encontrado ; b_est_prod=error:PT404:producto_no_encontrado ; b_validar=error:PT404:cliente_no_encontrado',
  'P4: con IDs de otra empresa, las 7 RPC de modificación responden no encontrado');

select is(
  (select (select md5(string_agg(p::text, '|' order by p.id)) from public.productos p
            where p.empresa_id = 'b9b9b9b9-0000-4000-8000-000000000000')
          || '/' || (select md5(string_agg(c::text, '|' order by c.id)) from public.camiones c
                      where c.empresa_id = 'b9b9b9b9-0000-4000-8000-000000000000')
          || '/' || (select md5(string_agg(c::text, '|' order by c.id)) from public.clientes c
                      where c.empresa_id = 'b9b9b9b9-0000-4000-8000-000000000000')),
  (select huella from huella_b),
  'P4: las filas de la empresa B no cambiaron');

select is((select valor from resultados where caso = 'medida_p3'), '0/0',
  'P1/P3/P4: 0 ejecuciones del código temporal como propietario_rpc y 0 como authenticated en las 25 llamadas');

select ok(pg_temp.ejecuciones_secuencia('pg_temp.control_mutante') = 1,
  'P6: los cuerpos reintroducidos son exactamente los anteriores a A2 (SHA-256)');

select cmp_ok(pg_temp.ejecuciones_secuencia('pg_temp.control_directo'), '>', 0::bigint,
  'P6: con declaraciones sin calificar, crear_producto ejecuta el código temporal como propietario_rpc (el detector funciona)');

select is(
  (select split_part(valor, ':', 1) from resultados where caso = 'post_m1')
  || '/' || (select valor from resultados where caso = 'medida_post_m1')
  || '/' || (select string_agg(encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex'), ',' order by p.proname)
               from pg_proc p
              where p.oid in ('privado.crear_producto(text,text,text,text,numeric,integer)'::regprocedure,
                              'privado.exigir_gestor_productos()'::regprocedure))
  || '/' || has_schema_privilege('propietario_rpc', 'privado', 'CREATE')::text,
  'ok/0/1d7975632846bc9afbf6ac2d5706b4ae594fca766a448dc9d5a0e2e7d62b0445,2db9f4fbfa108f8ea78b6a65787a3ccbfcefd0d50bb0f11b8c670035b1fd1ae1/false',
  'P6: tras revertir el control vuelven los cuerpos de A2, sin CREATE residual, y la llamada vuelve a 0 ejecuciones');

select * from finish();

rollback;
