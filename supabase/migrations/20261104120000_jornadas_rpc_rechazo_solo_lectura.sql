-- Corrección extraordinaria T1/T2 — rechazo de transacciones de sólo lectura en
-- privado.abrir_jornada y privado.reasignar_vendedor (ADR-001 §6, §16 T14 y
-- §18.4.3; ADR-007). Validación exclusivamente local/staging. Prohibido aplicar
-- en producción.
--
-- Defecto (reproducido sobre 90672be con PostgREST real): PostgREST ejecuta GET y
-- HEAD en una transacción READ ONLY. Con una idempotency_key ya usada, el replay
-- (pasos 5 y 8a de 18.4.3) sólo lee: GET/HEAD respondían 200 con el uuid
-- original, y con otra huella 409. El contrato (ADR-001 §6 y T14) exige 405.
-- Con clave nueva el 405 dependía de que la primera escritura fallara, y el
-- mensaje exponía el texto interno de PostgreSQL.
--
-- Cambio: al comienzo de cada implementación privada, antes del paso 1, de
-- cualquier acceso a datos y de la consulta de idempotencia, se agrega la guarda
--   transaction_read_only = on → SQLSTATE 25006, message jornada_metodo_no_permitido
-- (PostgREST traduce 25006 a HTTP 405). Es el ÚNICO cambio: el cuerpo nuevo se
-- construye insertando la guarda en el cuerpo vigente, después de validar su
-- SHA-256, y se verifica que quitando la guarda se obtenga el cuerpo anterior
-- byte a byte. Las fachadas public no cambian.
--
-- Integridad previa y posterior (H-02 de la security review): antes de cualquier
-- cambio se exige el estado aprobado exacto de las cuatro funciones — firma,
-- lenguaje, SECURITY INVOKER/DEFINER, owner, volatilidad, search_path, ACL y los
-- demás atributos de pg_proc, comentario y SHA-256 del cuerpo — mediante un
-- manifiesto fijo; después, el manifiesto esperado con los cuerpos nuevos.
--
-- Resolución de nombres (H-01 de la security review): el DECLARE no tiene
-- inicializadores y sus tipos están calificados con pg_catalog; la primera
-- sentencia fija search_path = 'pg_catalog, pg_temp' (pg_temp explícito y al
-- final: si no figura, se busca primero para tipos y relaciones) y la última lo
-- restaura. Todo tipo, cast, función y relación está calificado, también en el DDL
-- dinámico. Así ninguna función, dominio, tipo o relación de public, extensions o
-- pg_temp se resuelve ni se ejecuta como postgres o propietario_rpc.
--
-- Atomicidad: todo ocurre en un único bloque DO (una sola sentencia y, por lo
-- tanto, una sola transacción con cualquier ejecutor: la CLI de Supabase o psql
-- del arnés T3). El CREATE transitorio de propietario_rpc sobre privado (CREATE OR
-- REPLACE FUNCTION exige CREATE en el esquema) y el SET ROLE propietario_rpc
-- (O-3: postgres tiene SET sin INHERIT) se conceden y se retiran dentro del mismo
-- bloque; si cualquier precondición o verificación falla, se aborta sin cambios.
--
-- Fuera de alcance: cambiar migraciones T1 y T2, D-1, D-2 o T3; las otras cuatro
-- RPC; el frontend; los grants. El código jornada_metodo_no_permitido y el paso
-- previo al paso 1 requieren la enmienda E-SL1 de ADR-001 (§18.4.16), PROPUESTA
-- TÉCNICA NO APROBADA.

do $mig$
declare
  -- Sin inicializadores: nada se evalúa antes de fijar el search_path controlado.
  v_search_path_previo pg_catalog.text;
  v_guarda pg_catalog.text;
  v_ancla pg_catalog.text;
  v_manifiesto_previo pg_catalog.text;
  v_manifiesto_nuevo pg_catalog.text;
  v_abrir_previo pg_catalog.text;
  v_abrir_nuevo pg_catalog.text;
  v_reasignar_previo pg_catalog.text;
  v_reasignar_nuevo pg_catalog.text;
  v_abrir pg_catalog.regprocedure;
  v_reasignar pg_catalog.regprocedure;
  v_pub_abrir pg_catalog.regprocedure;
  v_pub_reasignar pg_catalog.regprocedure;
  v_plpgsql pg_catalog.oid;
  v_sql pg_catalog.oid;
  v_src_abrir pg_catalog.text;
  v_src_reasignar pg_catalog.text;
  v_nuevo_abrir pg_catalog.text;
  v_nuevo_reasignar pg_catalog.text;
  v_attr_abrir pg_catalog.jsonb;
  v_attr_reasignar pg_catalog.jsonb;
  v_attr_pub pg_catalog.jsonb;
  v_acl_privado pg_catalog.text;
  v_definer pg_catalog.text;
  v_manifiesto pg_catalog.text;
  v_pos pg_catalog.int4;
begin
  -- -------------------------------------------------------------------------
  -- search_path controlado (primera sentencia; se restaura al final)
  -- -------------------------------------------------------------------------
  v_search_path_previo := pg_catalog.current_setting('search_path');
  perform pg_catalog.set_config('search_path', 'pg_catalog, pg_temp', true);

  if pg_catalog.current_setting('search_path') operator(pg_catalog.<>) 'pg_catalog, pg_temp' then
    raise exception 'jornadas: no se pudo fijar el search_path controlado';
  end if;

  -- -------------------------------------------------------------------------
  -- Constantes (asignadas con el search_path ya controlado)
  -- -------------------------------------------------------------------------
  -- Guarda que se inserta, sin otra modificación, tras la línea «begin» del
  -- bloque externo de cada implementación.
  v_guarda := $g$  -- Paso 0 (corrección T14; ADR-001 §6 y §16): una transacción de sólo lectura
  -- (GET o HEAD por PostgREST) se rechaza antes de cualquier acceso a datos y de
  -- la consulta de idempotencia. Sin esta guarda, un replay sólo leía y respondía
  -- 200 a un GET. SQLSTATE 25006 → HTTP 405 en PostgREST.
  if pg_catalog.current_setting('transaction_read_only') = 'on' then
    raise exception using
      errcode = '25006',
      message = 'jornada_metodo_no_permitido';
  end if;

$g$;
  v_ancla := E'\nbegin\n';

  -- SHA-256 de prosrc: cuerpos vigentes (T1 8e4aefa, T2 b9ba369) y cuerpos
  -- esperados después de insertar la guarda.
  v_abrir_previo := '463c3490fc6063abc7ecddb78264fe051dd4f6691fc9f8103f0bc2beec1cffd7';
  v_abrir_nuevo := 'f6f88764d337df49f2d05fdb8deaafd6a5be9e13500c38caf8be31b143faea07';
  v_reasignar_previo := '94f1177b3df789a0e9e1cb45e0d4a4f00109bb6852b6b93e4b7d571ae07e3b14';
  v_reasignar_nuevo := '381e59c479faad5e5e7829311da859640adbdab702054582cf1d198ce9e58943';

  -- Manifiesto exacto de las cuatro funciones (una línea por función, ordenadas
  -- por firma): firma | owner | lenguaje | prokind | SECURITY DEFINER | leakproof
  -- | strict | retset | volatilidad | paralelismo | nargs | nargdefaults | tipo de
  -- retorno | nombres de argumentos | modos | support | costo | filas | proconfig |
  -- ACL ordenada | comentario | probin | prosqlbody nulo | SHA-256 de prosrc.
  v_manifiesto_previo :=
       'privado.abrir_jornada(uuid,uuid,date,uuid)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|4|0|uuid|{p_idempotency_key,p_camion_id,p_fecha,p_vendedor_id}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|' || v_abrir_previo || E'\n'
    || 'privado.reasignar_vendedor(uuid,uuid,uuid)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|3|0|uuid|{p_idempotency_key,p_jornada_id,p_vendedor_id}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|' || v_reasignar_previo || E'\n'
    || 'public.abrir_jornada(uuid,uuid,date,uuid)|postgres|sql|f|false|false|false|false|v|u|4|0|uuid|{p_idempotency_key,p_camion_id,p_fecha,p_vendedor_id}|-|-|100|0|{"search_path=\"\""}|authenticated=X/postgres,postgres=X/postgres|-|-|true|349c03bf2c303f757d8fa97dc55aff6f85b4b463b85c3e3b901f39f3c28e9115' || E'\n'
    || 'public.reasignar_vendedor(uuid,uuid,uuid)|postgres|sql|f|false|false|false|false|v|u|3|0|uuid|{p_idempotency_key,p_jornada_id,p_vendedor_id}|-|-|100|0|{"search_path=\"\""}|authenticated=X/postgres,postgres=X/postgres|-|-|true|bb55c733a1c8e1c3506763482b05a46a40cc5602de5f49c0c9411b7da0c0b2df';
  v_manifiesto_nuevo := pg_catalog.replace(pg_catalog.replace(v_manifiesto_previo,
    v_abrir_previo, v_abrir_nuevo), v_reasignar_previo, v_reasignar_nuevo);

  -- -------------------------------------------------------------------------
  -- Precondiciones de identidad y de roles (fail-closed)
  -- -------------------------------------------------------------------------
  if current_user operator(pg_catalog.<>) 'postgres'
     or session_user operator(pg_catalog.<>) 'postgres' then
    raise exception 'jornadas: la migración debe ejecutarse como postgres; actual: % / %',
      session_user, current_user;
  end if;

  if not exists (select 1 from pg_catalog.pg_roles r
                  where r.rolname = 'propietario_rpc'
                    and not r.rolsuper and not r.rolcanlogin and not r.rolbypassrls
                    and not r.rolcreatedb and not r.rolcreaterole) then
    raise exception 'jornadas: propietario_rpc ausente o con atributos fuera de P3';
  end if;

  -- O-3: postgres puede SET ROLE propietario_rpc sin heredar sus privilegios.
  if not pg_catalog.pg_has_role('postgres', 'propietario_rpc', 'SET')
     or pg_catalog.pg_has_role('postgres', 'propietario_rpc', 'USAGE') then
    raise exception 'jornadas: la membresía postgres → propietario_rpc no es la de O-3';
  end if;

  if (select n.nspowner from pg_catalog.pg_namespace n where n.nspname = 'privado')
     is distinct from 'postgres'::pg_catalog.regrole then
    raise exception 'jornadas: el esquema privado no es de postgres';
  end if;

  -- Ningún permiso CREATE preexistente para propietario_rpc (no se hereda nada).
  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'jornadas: propietario_rpc ya tiene CREATE sobre privado';
  end if;

  if not pg_catalog.has_language_privilege('propietario_rpc', 'plpgsql', 'USAGE') then
    raise exception 'jornadas: propietario_rpc no puede usar plpgsql';
  end if;

  -- Las cuatro firmas, con tipos calificados.
  v_abrir := pg_catalog.to_regprocedure(
    'privado.abrir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid)');
  v_reasignar := pg_catalog.to_regprocedure(
    'privado.reasignar_vendedor(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)');
  v_pub_abrir := pg_catalog.to_regprocedure(
    'public.abrir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid)');
  v_pub_reasignar := pg_catalog.to_regprocedure(
    'public.reasignar_vendedor(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)');
  select l.oid into v_plpgsql from pg_catalog.pg_language l where l.lanname = 'plpgsql';
  select l.oid into v_sql from pg_catalog.pg_language l where l.lanname = 'sql';

  if v_abrir is null or v_reasignar is null or v_pub_abrir is null or v_pub_reasignar is null
     or v_plpgsql is null or v_sql is null then
    raise exception 'jornadas: faltan abrir_jornada o reasignar_vendedor (fachada o implementación)';
  end if;

  -- Sin sobrecargas: exactamente una implementación y una fachada por RPC.
  if (select pg_catalog.count(*) from pg_catalog.pg_proc p
       where p.proname = 'abrir_jornada'
         and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace))
       operator(pg_catalog.<>) 2
     or (select pg_catalog.count(*) from pg_catalog.pg_proc p
          where p.proname = 'reasignar_vendedor'
            and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace))
       operator(pg_catalog.<>) 2 then
    raise exception 'jornadas: sobrecargas o funciones faltantes de abrir_jornada/reasignar_vendedor';
  end if;

  -- -------------------------------------------------------------------------
  -- Estado aprobado exacto, antes de cualquier cambio
  -- -------------------------------------------------------------------------
  -- Fachadas (H-02): SQL, SECURITY INVOKER, owner postgres, VOLATILE, search_path
  -- vacío, ACL exacta (sólo authenticated y el owner), retorno uuid.
  if (select pg_catalog.count(*) from pg_catalog.pg_proc p
       where p.oid in (v_pub_abrir, v_pub_reasignar)
         and p.prolang = v_sql
         and p.prokind = 'f'
         and not p.prosecdef
         and p.proowner = 'postgres'::pg_catalog.regrole
         and p.provolatile = 'v'
         and p.proconfig = array['search_path=""']::pg_catalog.text[]
         and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
             = array['authenticated=X/postgres', 'postgres=X/postgres']::pg_catalog.text[]
         and p.prorettype = 'pg_catalog.uuid'::pg_catalog.regtype)
     operator(pg_catalog.<>) 2 then
    raise exception 'jornadas: una fachada public está fuera de lo aprobado (lenguaje, SECURITY, owner, volatilidad, search_path o ACL)';
  end if;

  -- Implementaciones: plpgsql, SECURITY DEFINER, owner propietario_rpc, VOLATILE,
  -- search_path vacío, ACL exacta.
  if (select pg_catalog.count(*) from pg_catalog.pg_proc p
       where p.oid in (v_abrir, v_reasignar)
         and p.prolang = v_plpgsql
         and p.prokind = 'f'
         and p.prosecdef
         and p.proowner = 'propietario_rpc'::pg_catalog.regrole
         and p.provolatile = 'v'
         and p.proconfig = array['search_path=""']::pg_catalog.text[]
         and array(select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1)
             = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc']::pg_catalog.text[]
         and p.prorettype = 'pg_catalog.uuid'::pg_catalog.regtype)
     operator(pg_catalog.<>) 2 then
    raise exception 'jornadas: una implementación privada está fuera de lo aprobado (lenguaje, SECURITY, owner, volatilidad, search_path o ACL)';
  end if;

  -- Manifiesto completo de las cuatro funciones (incluye los SHA-256 de los
  -- cuerpos de T1/T2 y de las fachadas).
  select pg_catalog.string_agg(
           p.oid::pg_catalog.regprocedure::pg_catalog.text
           || '|' || p.proowner::pg_catalog.regrole::pg_catalog.text
           || '|' || l.lanname::pg_catalog.text
           || '|' || p.prokind::pg_catalog.text
           || '|' || p.prosecdef::pg_catalog.text
           || '|' || p.proleakproof::pg_catalog.text
           || '|' || p.proisstrict::pg_catalog.text
           || '|' || p.proretset::pg_catalog.text
           || '|' || p.provolatile::pg_catalog.text
           || '|' || p.proparallel::pg_catalog.text
           || '|' || p.pronargs::pg_catalog.text
           || '|' || p.pronargdefaults::pg_catalog.text
           || '|' || p.prorettype::pg_catalog.regtype::pg_catalog.text
           || '|' || coalesce(p.proargnames::pg_catalog.text, '-')
           || '|' || coalesce(p.proargmodes::pg_catalog.text, '-')
           || '|' || coalesce(nullif(p.prosupport::pg_catalog.oid, 0::pg_catalog.oid)::pg_catalog.text, '-')
           || '|' || p.procost::pg_catalog.text
           || '|' || p.prorows::pg_catalog.text
           || '|' || coalesce(p.proconfig::pg_catalog.text, '-')
           || '|' || coalesce(pg_catalog.array_to_string(array(
                        select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1), ','), '-')
           || '|' || coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '-')
           || '|' || coalesce(p.probin, '-')
           || '|' || (p.prosqlbody is null)::pg_catalog.text
           || '|' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex'),
           E'\n' order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
    into v_manifiesto
    from pg_catalog.pg_proc p
    join pg_catalog.pg_language l on l.oid = p.prolang
   where p.oid in (v_abrir, v_reasignar, v_pub_abrir, v_pub_reasignar);

  if v_manifiesto is distinct from v_manifiesto_previo then
    raise exception 'jornadas: el estado de abrir_jornada/reasignar_vendedor no es el aprobado de T1/T2 (manifiesto)';
  end if;

  select p.prosrc into v_src_abrir from pg_catalog.pg_proc p where p.oid = v_abrir;
  select p.prosrc into v_src_reasignar from pg_catalog.pg_proc p where p.oid = v_reasignar;

  -- Fotos de todo pg_proc salvo prosrc, de las fachadas, del ACL de privado y de
  -- la lista de SECURITY DEFINER de public y privado.
  select pg_catalog.to_jsonb(p) operator(pg_catalog.-) 'prosrc'::pg_catalog.text into v_attr_abrir
    from pg_catalog.pg_proc p where p.oid = v_abrir;
  select pg_catalog.to_jsonb(p) operator(pg_catalog.-) 'prosrc'::pg_catalog.text into v_attr_reasignar
    from pg_catalog.pg_proc p where p.oid = v_reasignar;
  select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) order by p.oid) into v_attr_pub
    from pg_catalog.pg_proc p where p.oid in (v_pub_abrir, v_pub_reasignar);
  select coalesce(n.nspacl::pg_catalog.text, '') into v_acl_privado
    from pg_catalog.pg_namespace n where n.nspname = 'privado';
  select pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::pg_catalog.text || '/'
                               || p.proowner::pg_catalog.regrole::pg_catalog.text, ','
                               order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
    into v_definer
    from pg_catalog.pg_proc p
   where p.prosecdef
     and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace);

  -- -------------------------------------------------------------------------
  -- Construcción de los cuerpos nuevos: cuerpo vigente + guarda tras «begin»
  -- -------------------------------------------------------------------------
  if (pg_catalog.length(v_src_abrir) - pg_catalog.length(pg_catalog.replace(v_src_abrir, v_ancla, '')))
       / pg_catalog.length(v_ancla) operator(pg_catalog.<>) 1
     or (pg_catalog.length(v_src_reasignar) - pg_catalog.length(pg_catalog.replace(v_src_reasignar, v_ancla, '')))
       / pg_catalog.length(v_ancla) operator(pg_catalog.<>) 1
     or pg_catalog.strpos(v_src_abrir, v_guarda) operator(pg_catalog.<>) 0
     or pg_catalog.strpos(v_src_reasignar, v_guarda) operator(pg_catalog.<>) 0 then
    raise exception 'jornadas: ancla «begin» no única o guarda ya presente';
  end if;

  v_pos := pg_catalog.strpos(v_src_abrir, v_ancla) + pg_catalog.length(v_ancla);
  v_nuevo_abrir := pg_catalog.substr(v_src_abrir, 1, v_pos - 1) || v_guarda
                   || pg_catalog.substr(v_src_abrir, v_pos);
  v_pos := pg_catalog.strpos(v_src_reasignar, v_ancla) + pg_catalog.length(v_ancla);
  v_nuevo_reasignar := pg_catalog.substr(v_src_reasignar, 1, v_pos - 1) || v_guarda
                       || pg_catalog.substr(v_src_reasignar, v_pos);

  if pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_nuevo_abrir, 'UTF8')), 'hex')
       operator(pg_catalog.<>) v_abrir_nuevo
     or pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_nuevo_reasignar, 'UTF8')), 'hex')
       operator(pg_catalog.<>) v_reasignar_nuevo then
    raise exception 'jornadas: el cuerpo construido no coincide con el esperado';
  end if;

  -- -------------------------------------------------------------------------
  -- Sustitución como owner técnico (O-3), con CREATE transitorio
  -- -------------------------------------------------------------------------
  grant create on schema privado to propietario_rpc;
  set local role propietario_rpc;

  if current_user operator(pg_catalog.<>) 'propietario_rpc'
     or pg_catalog.current_setting('search_path') operator(pg_catalog.<>) 'pg_catalog, pg_temp' then
    raise exception 'jornadas: no se pudo actuar como propietario_rpc con el search_path controlado';
  end if;

  execute pg_catalog.format(
    'create or replace function privado.abrir_jornada('
      || 'p_idempotency_key pg_catalog.uuid, p_camion_id pg_catalog.uuid, '
      || 'p_fecha pg_catalog.date, p_vendedor_id pg_catalog.uuid) '
      || 'returns pg_catalog.uuid language plpgsql volatile security definer '
      || 'set search_path = %L as %L',
    '', v_nuevo_abrir);

  execute pg_catalog.format(
    'create or replace function privado.reasignar_vendedor('
      || 'p_idempotency_key pg_catalog.uuid, p_jornada_id pg_catalog.uuid, '
      || 'p_vendedor_id pg_catalog.uuid) '
      || 'returns pg_catalog.uuid language plpgsql volatile security definer '
      || 'set search_path = %L as %L',
    '', v_nuevo_reasignar);

  reset role;

  if current_user operator(pg_catalog.<>) 'postgres' then
    raise exception 'jornadas: no se pudo volver a postgres';
  end if;

  revoke create on schema privado from propietario_rpc;

  -- -------------------------------------------------------------------------
  -- Verificación fail-closed del resultado
  -- -------------------------------------------------------------------------
  -- Único cambio: la guarda. Quitándola se recupera el cuerpo anterior exacto.
  if (select p.prosrc from pg_catalog.pg_proc p where p.oid = v_abrir) is distinct from v_nuevo_abrir
     or (select p.prosrc from pg_catalog.pg_proc p where p.oid = v_reasignar) is distinct from v_nuevo_reasignar
     or pg_catalog.replace(v_nuevo_abrir, v_guarda, '') is distinct from v_src_abrir
     or pg_catalog.replace(v_nuevo_reasignar, v_guarda, '') is distinct from v_src_reasignar then
    raise exception 'jornadas: el cuerpo instalado no es el anterior más la guarda';
  end if;

  -- El resto de pg_proc, idéntico (mismo oid, owner, ACL, SECURITY DEFINER,
  -- search_path, volatilidad, firma…), y las fachadas sin ningún cambio.
  if (select pg_catalog.to_jsonb(p) operator(pg_catalog.-) 'prosrc'::pg_catalog.text
        from pg_catalog.pg_proc p where p.oid = v_abrir) is distinct from v_attr_abrir
     or (select pg_catalog.to_jsonb(p) operator(pg_catalog.-) 'prosrc'::pg_catalog.text
           from pg_catalog.pg_proc p where p.oid = v_reasignar) is distinct from v_attr_reasignar
     or (select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) order by p.oid) from pg_catalog.pg_proc p
          where p.oid in (v_pub_abrir, v_pub_reasignar)) is distinct from v_attr_pub then
    raise exception 'jornadas: cambió un atributo de pg_proc distinto del cuerpo';
  end if;

  -- Manifiesto esperado después del cambio: sólo cambian los SHA-256 de los dos
  -- cuerpos privados.
  select pg_catalog.string_agg(
           p.oid::pg_catalog.regprocedure::pg_catalog.text
           || '|' || p.proowner::pg_catalog.regrole::pg_catalog.text
           || '|' || l.lanname::pg_catalog.text
           || '|' || p.prokind::pg_catalog.text
           || '|' || p.prosecdef::pg_catalog.text
           || '|' || p.proleakproof::pg_catalog.text
           || '|' || p.proisstrict::pg_catalog.text
           || '|' || p.proretset::pg_catalog.text
           || '|' || p.provolatile::pg_catalog.text
           || '|' || p.proparallel::pg_catalog.text
           || '|' || p.pronargs::pg_catalog.text
           || '|' || p.pronargdefaults::pg_catalog.text
           || '|' || p.prorettype::pg_catalog.regtype::pg_catalog.text
           || '|' || coalesce(p.proargnames::pg_catalog.text, '-')
           || '|' || coalesce(p.proargmodes::pg_catalog.text, '-')
           || '|' || coalesce(nullif(p.prosupport::pg_catalog.oid, 0::pg_catalog.oid)::pg_catalog.text, '-')
           || '|' || p.procost::pg_catalog.text
           || '|' || p.prorows::pg_catalog.text
           || '|' || coalesce(p.proconfig::pg_catalog.text, '-')
           || '|' || coalesce(pg_catalog.array_to_string(array(
                        select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1), ','), '-')
           || '|' || coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '-')
           || '|' || coalesce(p.probin, '-')
           || '|' || (p.prosqlbody is null)::pg_catalog.text
           || '|' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex'),
           E'\n' order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
    into v_manifiesto
    from pg_catalog.pg_proc p
    join pg_catalog.pg_language l on l.oid = p.prolang
   where p.oid in (v_abrir, v_reasignar, v_pub_abrir, v_pub_reasignar);

  if v_manifiesto is distinct from v_manifiesto_nuevo then
    raise exception 'jornadas: el estado resultante no es el esperado (manifiesto)';
  end if;

  -- Sin privilegios transitorios: el ACL de privado vuelve a ser el anterior y
  -- propietario_rpc no conserva CREATE.
  if (select coalesce(n.nspacl::pg_catalog.text, '') from pg_catalog.pg_namespace n
       where n.nspname = 'privado') is distinct from v_acl_privado
     or pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'jornadas: quedó un privilegio CREATE transitorio sobre privado';
  end if;

  -- Misma lista de funciones SECURITY DEFINER y sin sobrecargas nuevas.
  if (select pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::pg_catalog.text || '/'
                                   || p.proowner::pg_catalog.regrole::pg_catalog.text, ','
                                   order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
        from pg_catalog.pg_proc p
       where p.prosecdef
         and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace))
       is distinct from v_definer
     or (select pg_catalog.count(*) from pg_catalog.pg_proc p
          where p.proname in ('abrir_jornada', 'reasignar_vendedor')
            and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace))
       operator(pg_catalog.<>) 4 then
    raise exception 'jornadas: cambió la lista de funciones SECURITY DEFINER o hay sobrecargas';
  end if;

  -- P11: anon y service_role siguen sin EXECUTE en fachadas e implementaciones.
  if pg_catalog.has_function_privilege('anon', v_abrir, 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', v_abrir, 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', v_reasignar, 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', v_reasignar, 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', v_pub_abrir, 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', v_pub_abrir, 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', v_pub_reasignar, 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', v_pub_reasignar, 'EXECUTE') then
    raise exception 'jornadas: EXECUTE fuera de lo aprobado para anon o service_role';
  end if;

  -- Restaura el search_path de la sesión para el resto de la transacción.
  perform pg_catalog.set_config('search_path', v_search_path_previo, true);

  if pg_catalog.current_setting('search_path') is distinct from v_search_path_previo then
    raise exception 'jornadas: no se pudo restaurar el search_path';
  end if;
end
$mig$;
