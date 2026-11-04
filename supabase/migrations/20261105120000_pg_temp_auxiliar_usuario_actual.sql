-- A1 — Endurecimiento pg_temp de privado.usuario_actual() (plan de remediación
-- pg_temp, alternativa A; ADR-001 §17.1). Validación exclusivamente
-- local/staging. Prohibido aplicar en producción.
--
-- Defecto (hallazgo ALTO heredado, ronda 4 de la security review de jornadas):
-- con search_path = '' PostgreSQL sigue buscando pg_temp ANTES que pg_catalog
-- para tipos y relaciones no calificados (no para funciones ni operadores). El
-- cuerpo de privado.usuario_actual() tiene dos casts sin calificar, «::jsonb» y
-- «::uuid». Una sesión que pueda asumir authenticated (TEMP por PUBLIC) puede
-- crear dominios pg_temp.jsonb / pg_temp.uuid con un CHECK que llama a código
-- propio: ese código corre como propietario_rpc cada vez que usuario_actual()
-- se evalúa, dentro de cualquier RPC SECURITY DEFINER o de cualquier política
-- RLS de propietario_rpc, y también dentro de privado.empresa_gestion_actual().
--
-- Cambio: ÚNICAMENTE esas dos calificaciones, «::pg_catalog.jsonb» y
-- «::pg_catalog.uuid». El cuerpo nuevo está escrito explícitamente abajo (texto
-- revisable, no generado). Se verifican su SHA-256, que quitando «pg_catalog.»
-- se obtiene el cuerpo vigente byte a byte y que hay exactamente 2
-- calificaciones. Se conservan search_path = '', owner propietario_rpc, ACL,
-- SECURITY INVOKER, STABLE, el oid (CREATE OR REPLACE) y, por lo tanto, las
-- dependencias de las políticas RLS.
--
-- Alcance: esto NO cierra la vulnerabilidad global. Las 15 RPC SECURITY DEFINER
-- y los tres auxiliares exigir_* conservan sus propias referencias sin calificar
-- (A2 catálogos, A3 stock, B1 jornadas). empresa_gestion_actual() no cambia: no
-- tiene referencias propias; sólo se verifica su manifiesto.
--
-- Integridad previa y posterior: manifiesto exacto de las dos funciones (firma,
-- owner, lenguaje, SECURITY, volatilidad, paralelismo, strict, costo,
-- search_path, ACL, comentario y SHA-256 del cuerpo). Después: el resto de
-- pg_proc idéntico (incluido el oid), mismas dependencias de políticas, mismo ACL
-- de privado sin CREATE residual, misma lista de SECURITY DEFINER y P11.
--
-- Resolución de nombres de la propia migración: DECLARE sin inicializadores y
-- con tipos pg_catalog; la primera sentencia fija search_path =
-- 'pg_catalog, pg_temp' (pg_temp explícito y al final) y la última lo restaura.
-- Todo tipo, cast, función y relación está calificado, también en el DDL
-- dinámico.
--
-- Atomicidad: un único bloque DO (una sentencia, una transacción). El CREATE
-- transitorio de propietario_rpc sobre privado (CREATE OR REPLACE FUNCTION exige
-- CREATE en el esquema) y el SET ROLE propietario_rpc (O-3: postgres tiene SET
-- sin INHERIT) se conceden y se retiran dentro del bloque; ante cualquier
-- precondición o verificación fallida se aborta sin cambios.
--
-- Sin cambios de grants permanentes, RLS, tablas, roles, códigos de error ni
-- reglas de negocio.

do $mig$
declare
  -- Sin inicializadores: nada se evalúa antes de fijar el search_path controlado.
  v_search_path_previo pg_catalog.text;
  v_cuerpo_nuevo pg_catalog.text;
  v_usuario_previo pg_catalog.text;
  v_usuario_nuevo pg_catalog.text;
  v_empresa_hash pg_catalog.text;
  v_manifiesto_previo pg_catalog.text;
  v_manifiesto_nuevo pg_catalog.text;
  v_manifiesto pg_catalog.text;
  v_usuario pg_catalog.regprocedure;
  v_empresa pg_catalog.regprocedure;
  v_sql pg_catalog.oid;
  v_src_usuario pg_catalog.text;
  v_attr_usuario pg_catalog.jsonb;
  v_attr_empresa pg_catalog.jsonb;
  v_acl_privado pg_catalog.text;
  v_definer pg_catalog.text;
  v_dep_usuario pg_catalog.text;
  v_dep_empresa pg_catalog.text;
begin
  -- -------------------------------------------------------------------------
  -- search_path controlado (primera sentencia; se restaura al final)
  -- -------------------------------------------------------------------------
  v_search_path_previo := pg_catalog.current_setting('search_path');
  perform pg_catalog.set_config('search_path', 'pg_catalog, pg_temp', true);

  if pg_catalog.current_setting('search_path') operator(pg_catalog.<>) 'pg_catalog, pg_temp' then
    raise exception 'pg_temp A1: no se pudo fijar el search_path controlado';
  end if;

  -- -------------------------------------------------------------------------
  -- Constantes (asignadas con el search_path ya controlado)
  -- -------------------------------------------------------------------------
  -- Cuerpo nuevo, explícito: el vigente con «::jsonb» → «::pg_catalog.jsonb» y
  -- «::uuid» → «::pg_catalog.uuid». Nada más cambia (ni espacios ni saltos).
  v_cuerpo_nuevo := $c$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::pg_catalog.jsonb ->> 'sub')
  )::pg_catalog.uuid
$c$;

  -- SHA-256 de prosrc: usuario_actual vigente (20261023140000_catalogo_productos)
  -- y esperado; empresa_gestion_actual (20261029233000_lector_perfiles_rpc), que
  -- no cambia.
  v_usuario_previo := '6c5f9459584dc092061bdb45d5531759ad946b27eecd502059ca687b214070b0';
  v_usuario_nuevo := '2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96';
  v_empresa_hash := '6d0a758d68ffaf8f575e1faebb132dc29cab4400e81c953b6dc73ed475fce7cc';

  -- Manifiesto exacto (una línea por función, ordenadas por firma): firma |
  -- owner | lenguaje | prokind | SECURITY DEFINER | leakproof | strict | retset
  -- | volatilidad | paralelismo | nargs | nargdefaults | tipo de retorno |
  -- nombres de argumentos | modos | support | costo | filas | proconfig | ACL
  -- ordenada | comentario | probin | prosqlbody nulo | SHA-256 de prosrc.
  v_manifiesto_previo :=
       'privado.empresa_gestion_actual()|propietario_rpc|sql|f|true|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|' || v_empresa_hash || E'\n'
    || 'privado.usuario_actual()|propietario_rpc|sql|f|false|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|' || v_usuario_previo;
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_previo, v_usuario_previo, v_usuario_nuevo);

  -- -------------------------------------------------------------------------
  -- Precondiciones de identidad y de roles (fail-closed)
  -- -------------------------------------------------------------------------
  if current_user operator(pg_catalog.<>) 'postgres'
     or session_user operator(pg_catalog.<>) 'postgres' then
    raise exception 'pg_temp A1: la migración debe ejecutarse como postgres; actual: % / %',
      session_user, current_user;
  end if;

  if not exists (select 1 from pg_catalog.pg_roles r
                  where r.rolname = 'propietario_rpc'
                    and not r.rolsuper and not r.rolcanlogin and not r.rolbypassrls
                    and not r.rolcreatedb and not r.rolcreaterole) then
    raise exception 'pg_temp A1: propietario_rpc ausente o con atributos fuera de P3';
  end if;

  -- O-3: postgres puede SET ROLE propietario_rpc sin heredar sus privilegios.
  if not pg_catalog.pg_has_role('postgres', 'propietario_rpc', 'SET')
     or pg_catalog.pg_has_role('postgres', 'propietario_rpc', 'USAGE') then
    raise exception 'pg_temp A1: la membresía postgres → propietario_rpc no es la de O-3';
  end if;

  if (select n.nspowner from pg_catalog.pg_namespace n where n.nspname = 'privado')
     is distinct from 'postgres'::pg_catalog.regrole then
    raise exception 'pg_temp A1: el esquema privado no es de postgres';
  end if;

  -- Ningún permiso CREATE preexistente para propietario_rpc.
  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'pg_temp A1: propietario_rpc ya tiene CREATE sobre privado';
  end if;

  if not pg_catalog.has_language_privilege('propietario_rpc', 'sql', 'USAGE') then
    raise exception 'pg_temp A1: propietario_rpc no puede usar sql';
  end if;

  v_usuario := pg_catalog.to_regprocedure('privado.usuario_actual()');
  v_empresa := pg_catalog.to_regprocedure('privado.empresa_gestion_actual()');
  select l.oid into v_sql from pg_catalog.pg_language l where l.lanname = 'sql';

  if v_usuario is null or v_empresa is null or v_sql is null then
    raise exception 'pg_temp A1: faltan privado.usuario_actual() o privado.empresa_gestion_actual()';
  end if;

  -- Sin sobrecargas ni homónimos en public/privado.
  if (select pg_catalog.count(*) from pg_catalog.pg_proc p
       where p.proname = 'usuario_actual'
         and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace))
       operator(pg_catalog.<>) 1
     or (select pg_catalog.count(*) from pg_catalog.pg_proc p
          where p.proname = 'empresa_gestion_actual'
            and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace))
       operator(pg_catalog.<>) 1 then
    raise exception 'pg_temp A1: sobrecargas o funciones faltantes de usuario_actual/empresa_gestion_actual';
  end if;

  -- -------------------------------------------------------------------------
  -- Estado aprobado exacto, antes de cualquier cambio
  -- -------------------------------------------------------------------------
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
   where p.oid in (v_usuario, v_empresa);

  if v_manifiesto is distinct from v_manifiesto_previo then
    raise exception 'pg_temp A1: el estado de usuario_actual/empresa_gestion_actual no es el aprobado (manifiesto)';
  end if;

  select p.prosrc into v_src_usuario from pg_catalog.pg_proc p where p.oid = v_usuario;

  -- Ausencia previa de calificaciones (no se reaplica sobre un cuerpo ya tocado).
  if pg_catalog.strpos(v_src_usuario, 'pg_catalog.') operator(pg_catalog.<>) 0 then
    raise exception 'pg_temp A1: el cuerpo vigente ya contiene calificaciones pg_catalog.';
  end if;

  -- Fotos: todo pg_proc salvo prosrc de usuario_actual; empresa_gestion_actual
  -- completa; ACL de privado; lista de SECURITY DEFINER; dependencias de las
  -- políticas RLS hacia ambas funciones.
  select pg_catalog.to_jsonb(p) operator(pg_catalog.-) 'prosrc'::pg_catalog.text into v_attr_usuario
    from pg_catalog.pg_proc p where p.oid = v_usuario;
  select pg_catalog.to_jsonb(p) into v_attr_empresa
    from pg_catalog.pg_proc p where p.oid = v_empresa;
  select coalesce(n.nspacl::pg_catalog.text, '') into v_acl_privado
    from pg_catalog.pg_namespace n where n.nspname = 'privado';
  select pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::pg_catalog.text || '/'
                               || p.proowner::pg_catalog.regrole::pg_catalog.text, ','
                               order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
    into v_definer
    from pg_catalog.pg_proc p
   where p.prosecdef
     and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace);
  select coalesce(pg_catalog.string_agg(d.objid::pg_catalog.text || ':' || d.deptype::pg_catalog.text, ','
                                        order by d.objid, d.deptype), '')
    into v_dep_usuario
    from pg_catalog.pg_depend d
   where d.classid = 'pg_catalog.pg_policy'::pg_catalog.regclass
     and d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass
     and d.refobjid = v_usuario;
  select coalesce(pg_catalog.string_agg(d.objid::pg_catalog.text || ':' || d.deptype::pg_catalog.text, ','
                                        order by d.objid, d.deptype), '')
    into v_dep_empresa
    from pg_catalog.pg_depend d
   where d.classid = 'pg_catalog.pg_policy'::pg_catalog.regclass
     and d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass
     and d.refobjid = v_empresa;

  if v_dep_usuario operator(pg_catalog.=) '' or v_dep_empresa operator(pg_catalog.=) '' then
    raise exception 'pg_temp A1: no se encontraron las políticas que dependen de los auxiliares';
  end if;

  -- -------------------------------------------------------------------------
  -- Verificación del cuerpo nuevo (antes de instalarlo)
  -- -------------------------------------------------------------------------
  -- SHA-256 esperado; equivalencia mecánica (quitando «pg_catalog.» se obtiene
  -- el cuerpo vigente byte a byte); exactamente 2 calificaciones, y son las dos
  -- previstas.
  if pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_cuerpo_nuevo, 'UTF8')), 'hex')
       operator(pg_catalog.<>) v_usuario_nuevo
     or pg_catalog.replace(v_cuerpo_nuevo, 'pg_catalog.', '') is distinct from v_src_usuario
     or (pg_catalog.length(v_cuerpo_nuevo)
         - pg_catalog.length(pg_catalog.replace(v_cuerpo_nuevo, 'pg_catalog.', '')))
        / pg_catalog.length('pg_catalog.') operator(pg_catalog.<>) 2
     or pg_catalog.strpos(v_cuerpo_nuevo, ')::pg_catalog.jsonb ->> ''sub'')') operator(pg_catalog.=) 0
     or pg_catalog.strpos(v_cuerpo_nuevo, E'\n  )::pg_catalog.uuid\n') operator(pg_catalog.=) 0 then
    raise exception 'pg_temp A1: el cuerpo nuevo no es el vigente con las dos calificaciones previstas';
  end if;

  -- -------------------------------------------------------------------------
  -- Sustitución como owner técnico (O-3), con CREATE transitorio
  -- -------------------------------------------------------------------------
  grant create on schema privado to propietario_rpc;
  set local role propietario_rpc;

  if current_user operator(pg_catalog.<>) 'propietario_rpc'
     or pg_catalog.current_setting('search_path') operator(pg_catalog.<>) 'pg_catalog, pg_temp' then
    raise exception 'pg_temp A1: no se pudo actuar como propietario_rpc con el search_path controlado';
  end if;

  execute pg_catalog.format(
    'create or replace function privado.usuario_actual() '
      || 'returns pg_catalog.uuid language sql stable security invoker '
      || 'set search_path = %L as %L',
    '', v_cuerpo_nuevo);

  reset role;

  if current_user operator(pg_catalog.<>) 'postgres' then
    raise exception 'pg_temp A1: no se pudo volver a postgres';
  end if;

  revoke create on schema privado from propietario_rpc;

  -- -------------------------------------------------------------------------
  -- Verificación fail-closed del resultado
  -- -------------------------------------------------------------------------
  if (select p.prosrc from pg_catalog.pg_proc p where p.oid = v_usuario) is distinct from v_cuerpo_nuevo
     or pg_catalog.replace((select p.prosrc from pg_catalog.pg_proc p where p.oid = v_usuario),
                           'pg_catalog.', '') is distinct from v_src_usuario then
    raise exception 'pg_temp A1: el cuerpo instalado no es el vigente con las dos calificaciones';
  end if;

  -- El resto de pg_proc idéntico (mismo oid, owner, ACL, SECURITY, search_path,
  -- volatilidad, firma…) y empresa_gestion_actual sin ningún cambio.
  if (select pg_catalog.to_jsonb(p) operator(pg_catalog.-) 'prosrc'::pg_catalog.text
        from pg_catalog.pg_proc p where p.oid = v_usuario) is distinct from v_attr_usuario
     or (select pg_catalog.to_jsonb(p) from pg_catalog.pg_proc p where p.oid = v_empresa)
          is distinct from v_attr_empresa then
    raise exception 'pg_temp A1: cambió un atributo de pg_proc distinto del cuerpo';
  end if;

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
   where p.oid in (v_usuario, v_empresa);

  if v_manifiesto is distinct from v_manifiesto_nuevo then
    raise exception 'pg_temp A1: el estado resultante no es el esperado (manifiesto)';
  end if;

  -- Las políticas RLS siguen dependiendo del mismo oid.
  if (select coalesce(pg_catalog.string_agg(d.objid::pg_catalog.text || ':' || d.deptype::pg_catalog.text, ','
                                            order by d.objid, d.deptype), '')
        from pg_catalog.pg_depend d
       where d.classid = 'pg_catalog.pg_policy'::pg_catalog.regclass
         and d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass
         and d.refobjid = v_usuario) is distinct from v_dep_usuario
     or (select coalesce(pg_catalog.string_agg(d.objid::pg_catalog.text || ':' || d.deptype::pg_catalog.text, ','
                                               order by d.objid, d.deptype), '')
           from pg_catalog.pg_depend d
          where d.classid = 'pg_catalog.pg_policy'::pg_catalog.regclass
            and d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass
            and d.refobjid = v_empresa) is distinct from v_dep_empresa then
    raise exception 'pg_temp A1: cambiaron las dependencias de las políticas RLS';
  end if;

  -- Sin privilegios transitorios: el ACL de privado vuelve a ser el anterior y
  -- propietario_rpc no conserva CREATE.
  if (select coalesce(n.nspacl::pg_catalog.text, '') from pg_catalog.pg_namespace n
       where n.nspname = 'privado') is distinct from v_acl_privado
     or pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'pg_temp A1: quedó un privilegio CREATE transitorio sobre privado';
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
          where p.proname in ('usuario_actual', 'empresa_gestion_actual')
            and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace))
       operator(pg_catalog.<>) 2 then
    raise exception 'pg_temp A1: cambió la lista de funciones SECURITY DEFINER o hay sobrecargas';
  end if;

  -- P11 y ACL de auxiliares: sólo propietario_rpc ejecuta ambas funciones.
  if pg_catalog.has_function_privilege('anon', v_usuario, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', v_usuario, 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', v_usuario, 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', v_empresa, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', v_empresa, 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', v_empresa, 'EXECUTE') then
    raise exception 'pg_temp A1: EXECUTE fuera de lo aprobado para anon, authenticated o service_role';
  end if;

  -- Restaura el search_path de la sesión para el resto de la transacción.
  perform pg_catalog.set_config('search_path', v_search_path_previo, true);

  if pg_catalog.current_setting('search_path') is distinct from v_search_path_previo then
    raise exception 'pg_temp A1: no se pudo restaurar el search_path';
  end if;
end
$mig$;
