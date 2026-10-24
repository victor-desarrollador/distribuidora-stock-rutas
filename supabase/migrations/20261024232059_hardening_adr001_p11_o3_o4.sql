-- Hardening transversal de ADR-001: P11 global, O-3 y O-4 (Blueprint §10;
-- ADR-001 §6, §7, §12.4, §12.8, §17.3 y §18.1).
--
-- Decisiones humanas aplicadas (registradas en docs/progress-log.md):
--   - P11: `service_role` queda denegado por defecto en los objetos de
--     negocio. Las excepciones son explícitas y nominadas; la única vigente es
--     SELECT sobre `public.productos` (P11-productos, ADR-001 §18.1). Sin
--     EXECUTE sobre las RPC de negocio y sin MAINTAIN.
--   - O-3: `postgres` conserva la capacidad de SET ROLE propietario_rpc
--     (necesaria para ALTER FUNCTION ... OWNER TO propietario_rpc) pero NO
--     hereda sus privilegios (INHERIT false). El runtime de las RPC no cambia:
--     la implementación SECURITY DEFINER corre como su owner.
--   - O-4: se conservan `public.rls_auto_enable()` y el event trigger
--     `ensure_rls` (objetos del proyecto alojado, no de este repositorio) y se
--     revoca EXECUTE a PUBLIC, anon, authenticated y service_role. El disparo
--     de un event trigger no chequea EXECUTE del rol que ejecuta el DDL
--     (verificado en local), así que el comportamiento del trigger no cambia.
--
-- Qué NO hace: no toca RLS, policies, el cuerpo de ninguna función, los
-- privilegios de anon/authenticated/propietario_rpc, objetos de plataforma
-- (auth, storage, realtime, graphql, extensions) ni los privilegios por
-- defecto. No resuelve P8–P10 ni P12–P17.
--
-- Idempotente: todo GRANT/REVOKE se puede repetir; O-4 tolera que la función
-- no exista (en local no existe). Validación exclusivamente local/staging.
-- Prohibido aplicar en producción.

do $$
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- P11 — service_role denegado por defecto en tablas de negocio
-- ---------------------------------------------------------------------------
-- REVOKE ALL incluye MAINTAIN (PostgreSQL 17). La excepción nominada se
-- vuelve a conceder de forma explícita.
revoke all on table public.empresas, public.perfiles, public.productos,
                    public.camiones, public.clientes
  from service_role;

-- Excepción aprobada (P11-productos): sólo lectura del catálogo.
grant select on table public.productos to service_role;

-- ---------------------------------------------------------------------------
-- P11 — sin EXECUTE de service_role sobre las RPC de negocio (firmas exactas)
-- ---------------------------------------------------------------------------
-- Fachadas de public (owner postgres).
revoke all on function public.crear_producto(text, text, text, text, numeric, integer),
                       public.actualizar_producto(uuid, text, text, numeric, integer),
                       public.cambiar_estado_producto(uuid, boolean),
                       public.crear_camion(text, text),
                       public.actualizar_camion(uuid, text, text),
                       public.cambiar_estado_camion(uuid, boolean),
                       public.crear_cliente(text, text, text, text),
                       public.actualizar_cliente(uuid, text, text, text, text),
                       public.validar_cliente(uuid),
                       public.cambiar_estado_cliente(uuid, boolean)
  from service_role;

-- Implementaciones de privado: su owner es propietario_rpc. Sin INHERIT,
-- postgres sólo actúa como owner tras SET ROLE (sin él, REVOKE no revoca nada
-- y sólo emite un WARNING).
set role propietario_rpc;

revoke all on function privado.crear_producto(text, text, text, text, numeric, integer),
                       privado.actualizar_producto(uuid, text, text, numeric, integer),
                       privado.cambiar_estado_producto(uuid, boolean),
                       privado.crear_camion(text, text),
                       privado.actualizar_camion(uuid, text, text),
                       privado.cambiar_estado_camion(uuid, boolean),
                       privado.crear_cliente(text, text, text, text),
                       privado.actualizar_cliente(uuid, text, text, text, text),
                       privado.validar_cliente(uuid),
                       privado.cambiar_estado_cliente(uuid, boolean)
  from service_role;

reset role;

-- ---------------------------------------------------------------------------
-- O-3 — postgres: SET sí, INHERIT no
-- ---------------------------------------------------------------------------
-- Modifica la membresía que otorgó `grant propietario_rpc to current_user`
-- (20261023140000; grantor postgres). La fila con ADMIN OPTION que PostgreSQL
-- crea automáticamente (grantor supabase_admin, sin SET ni INHERIT) no se toca.
grant propietario_rpc to postgres with inherit false, set true;

-- ---------------------------------------------------------------------------
-- O-4 — public.rls_auto_enable() sin EXECUTE para roles de la Data API
-- ---------------------------------------------------------------------------
-- La función existe sólo en el proyecto alojado. Fail-closed: si existe y el
-- REVOKE no surte efecto (por ejemplo, otro owner), la migración aborta en
-- lugar de dejar el estado sin endurecer en silencio.
do $$
declare
  v_funcion regprocedure := to_regprocedure('public.rls_auto_enable()');
begin
  if v_funcion is null then
    return;
  end if;

  execute 'revoke execute on function public.rls_auto_enable() '
          'from public, anon, authenticated, service_role';

  if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              where p.oid = v_funcion and a.grantee = 0)
     or has_function_privilege('anon', v_funcion, 'EXECUTE')
     or has_function_privilege('authenticated', v_funcion, 'EXECUTE')
     or has_function_privilege('service_role', v_funcion, 'EXECUTE') then
    raise exception
      'O-4: public.rls_auto_enable() sigue ejecutable por PUBLIC/anon/authenticated/service_role (owner %)',
      (select proowner::regrole from pg_proc where oid = v_funcion);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Verificación fail-closed de P11 y O-3
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
       select 1 from pg_auth_members
        where roleid = 'propietario_rpc'::regrole and member = 'postgres'::regrole
          and grantor = 'postgres'::regrole and set_option and not inherit_option)
     or exists (
       select 1 from pg_auth_members
        where roleid = 'propietario_rpc'::regrole and member = 'postgres'::regrole
          and inherit_option)
     or pg_has_role('postgres', 'propietario_rpc', 'USAGE')
     or not pg_has_role('postgres', 'propietario_rpc', 'SET') then
    raise exception 'O-3: la membresía postgres → propietario_rpc no quedó en SET true / INHERIT false';
  end if;

  if exists (
       select 1 from pg_class c
        where c.oid in ('public.empresas'::regclass, 'public.perfiles'::regclass,
                        'public.productos'::regclass, 'public.camiones'::regclass,
                        'public.clientes'::regclass)
          and (has_table_privilege('service_role', c.oid,
                 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
               or (c.oid <> 'public.productos'::regclass
                   and has_any_column_privilege('service_role', c.oid, 'SELECT'))
               or has_any_column_privilege('service_role', c.oid, 'INSERT, UPDATE, REFERENCES')))
     or not has_table_privilege('service_role', 'public.productos', 'SELECT')
     -- Todo privado es de este repositorio; en public, sólo las fachadas de
     -- negocio (otras funciones de public pueden ser de la plataforma).
     or exists (
       select 1 from pg_proc p
        where (p.pronamespace = 'privado'::regnamespace
               or p.oid in ('public.crear_producto(text,text,text,text,numeric,integer)'::regprocedure,
                            'public.actualizar_producto(uuid,text,text,numeric,integer)'::regprocedure,
                            'public.cambiar_estado_producto(uuid,boolean)'::regprocedure,
                            'public.crear_camion(text,text)'::regprocedure,
                            'public.actualizar_camion(uuid,text,text)'::regprocedure,
                            'public.cambiar_estado_camion(uuid,boolean)'::regprocedure,
                            'public.crear_cliente(text,text,text,text)'::regprocedure,
                            'public.actualizar_cliente(uuid,text,text,text,text)'::regprocedure,
                            'public.validar_cliente(uuid)'::regprocedure,
                            'public.cambiar_estado_cliente(uuid,boolean)'::regprocedure))
          and has_function_privilege('service_role', p.oid, 'EXECUTE')) then
    raise exception 'P11: service_role no quedó en deny-by-default con la excepción SELECT de productos';
  end if;
end $$;
