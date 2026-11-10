-- PROCEDIMIENTO DE REVERSIÓN MANUAL de
-- supabase/migrations/20261031120000_rpc_abrir_jornada.sql (T1, RPC abrir_jornada).
--
-- NO ES UNA MIGRACIÓN. Vive fuera de supabase/migrations/ a propósito: el CLI de
-- Supabase no lo ejecuta ni en `db reset` ni en `db push`. Sólo se corre a mano,
-- en local o staging, con autorización humana expresa y NUNCA en producción.
--
-- Cómo usarlo (como postgres, en una conexión nueva):
--   psql "$DATABASE_URL_LOCAL" -v ON_ERROR_STOP=1 -f supabase/rollback/20261031120000_rpc_abrir_jornada.rollback.sql
-- Es una sola transacción: si cualquier verificación o sentencia falla, no queda
-- nada a medias.
--
-- Qué hace: elimina las dos funciones (la fachada public.abrir_jornada y la
-- implementación privado.abrir_jornada), sin CASCADE. NO borra filas: las
-- jornadas y operaciones creadas con la RPC quedan en sus tablas. Si algo
-- depende de ellas, el DROP sin CASCADE falla.
--
-- Falla cerrado ante deriva: antes del DROP compara cada función con un
-- manifiesto generado desde el esquema limpio que deja la migración, para no
-- descartar en silencio un cambio posterior confirmado (un COMMENT ON FUNCTION,
-- un CREATE OR REPLACE FUNCTION o un ALTER FUNCTION). Por función compara:
-- esquema y nombre; owner; lenguaje; tipo de función; SECURITY DEFINER;
-- LEAKPROOF; STRICT; RETSET; volatilidad; paralelismo; cantidad de argumentos y
-- de defaults; tipo de retorno; tipos, nombres y modos de los argumentos; costo
-- y filas; variádico y soporte; la configuración (proconfig) por igualdad
-- exacta; la ausencia de comentario (comprobada contra pg_description, sin
-- valores centinela: un comentario literal '-' no se confunde con no tener
-- comentario); la cantidad de etiquetas de seguridad; la ACL (con la opción de
-- re-otorgar); y el SHA-256 del cuerpo (sin retornos de carro).
-- Además verifica en pg_depend que ninguna de las dos funciones dependa de una
-- extensión (pg_extension): la migración no crea ninguna, y un ALTER FUNCTION ...
-- DEPENDS ON EXTENSION o la pertenencia a una extensión posteriores abortan. Las
-- dependencias normales de la migración (esquema y lenguaje) no apuntan a
-- pg_extension y no se confunden con ellas.
-- Evita pg_get_functiondef y los árboles de nodos, cuya representación puede
-- variar entre versiones de PostgreSQL: de proargdefaults, prosqlbody y
-- protrftypes sólo verifica que sean nulos.
--
-- Límites (el manifiesto NO es una garantía absoluta de integridad):
--   - Atributos no cubiertos: las dependencias de otros objetos hacia las
--     funciones (el DROP sin CASCADE las rechaza), los privilegios iniciales
--     (pg_init_privs) y el contenido de las etiquetas de seguridad (se cuenta,
--     no se compara). Los campos opcionales del manifiesto que no existen
--     (nombres y modos de argumentos, configuración) se representan con '-'; no
--     hay una colisión alcanzable por SQL (las firmas son fijas y proconfig se
--     compara aparte por igualdad exacta).
--   - Un cambio de formato del archivo de la migración (espacios, tabuladores)
--     altera el SHA-256 del cuerpo y produce un aborto (falso positivo, fail-closed).
--   - La ventana entre la verificación y el DROP sigue abierta: no hay un LOCK
--     de funciones (ver el límite siguiente).
--
-- Límite conocido: PostgreSQL no permite bloquear una función como una tabla.
-- Un CREATE OR REPLACE o un ALTER FUNCTION concurrente entre la verificación y
-- el DROP no se puede excluir; hay que correr el procedimiento sin DDL
-- concurrente (misma limitación que la de ADR-001 sobre DDL de funciones).
--
-- Después de revertir hay que revertir también el código de la rama
-- (`git revert` de la implementación de T1), porque las pruebas pgTAP y las
-- aserciones ampliadas de catálogo fallarían sin las funciones. La migración
-- original no se edita; para volver a aplicarla en una base ya migrada hay que
-- registrar su estado con el flujo normal de migraciones del entorno (en local,
-- `db reset`).
--
-- Esta reversión no toca D-1, D-2 ni las RPC de Stock.

begin;

set local lock_timeout = '5s';
set local search_path = pg_catalog, public;

do $$
begin
  if current_user <> 'postgres' then
    raise exception 'la reversión debe ejecutarse como postgres; actual: %', current_user;
  end if;

  if to_regprocedure('public.abrir_jornada(uuid, uuid, date, uuid)') is null
     or to_regprocedure('privado.abrir_jornada(uuid, uuid, date, uuid)') is null then
    raise exception 'reversión T1: abrir_jornada no está aplicada (faltan la fachada o la implementación)';
  end if;

  -- Deriva: las funciones deben ser exactamente las que dejó la migración.
  if (select count(*) from pg_proc
       where proname = 'abrir_jornada'
         and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)) <> 2
     or not exists (
       select 1 from pg_proc p
        where p.oid = 'privado.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure
          and p.prosecdef and p.proowner = 'propietario_rpc'::regrole
          and p.proconfig @> array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc'])
     or not exists (
       select 1 from pg_proc p
        where p.oid = 'public.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure
          and not p.prosecdef and p.proowner = 'postgres'::regrole
          and p.proconfig @> array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/postgres', 'postgres=X/postgres']) then
    raise exception 'reversión T1: abrir_jornada difiere de lo que dejó la migración (owner, SECURITY, search_path, ACL o sobrecargas)';
  end if;
end $$;

-- Dependencias de extensión: la migración no crea ninguna. Un ALTER FUNCTION ... DEPENDS ON
-- EXTENSION posterior (deptype 'x') o la pertenencia a una extensión (deptype 'e') son una
-- modificación posterior; las dependencias normales de la migración (esquema, lenguaje) no
-- apuntan a pg_extension y no se confunden con ellas.
do $$
begin
  if exists (select 1 from pg_depend d
              where d.classid = 'pg_proc'::regclass
                and d.refclassid = 'pg_extension'::regclass
                and d.objid in ('public.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure,
                                'privado.abrir_jornada(uuid, uuid, date, uuid)'::regprocedure)) then
    raise exception 'reversión T1: abrir_jornada tiene una dependencia de extensión (DEPENDS ON EXTENSION o membresía) que la migración no creó';
  end if;
end $$;

-- Manifiesto de las dos funciones (generado desde el esquema limpio que deja la
-- migración; ver el encabezado). Un cambio posterior confirmado hace abortar.
do $$
declare
  v_txt text;
begin
  select string_agg(
    n.nspname || '.' || p.proname
    || '|' || p.proowner::regrole::text
    || '|' || l.lanname
    || '|' || p.prokind::text || '|' || p.prosecdef::text || '|' || p.proleakproof::text || '|' || p.proisstrict::text || '|' || p.proretset::text
    || '|' || p.provolatile::text || '|' || p.proparallel::text
    || '|' || p.pronargs::text || '|' || p.pronargdefaults::text
    || '|' || format_type(p.prorettype, null)
    || '|' || (select string_agg(format_type(t, null), ',' order by o) from unnest(p.proargtypes::oid[]) with ordinality u(t, o))
    || '|' || coalesce(array_to_string(p.proargnames, ','), '-')
    || '|' || coalesce(p.proargmodes::text, '-')
    || '|' || p.procost::numeric::text || '|' || p.prorows::numeric::text
    || '|' || p.provariadic::oid::text || '|' || p.prosupport::oid::text
    || '|' || coalesce(array_to_string(p.proconfig, ','), '-')
    || '|' || (p.proargdefaults is null)::text || '|' || (p.prosqlbody is null)::text || '|' || (p.protrftypes is null)::text
    || '|' || (not exists (select 1 from pg_description d where d.classoid = 'pg_proc'::regclass and d.objoid = p.oid and d.objsubid = 0))::text
    || '|' || (select count(*) from pg_seclabel s where s.objoid = p.oid and s.classoid = 'pg_proc'::regclass)::text
    || '|' || encode(sha256(convert_to(replace(p.prosrc, E'\r', ''), 'UTF8')), 'hex')
    , E'\n' order by n.nspname collate "C")
    into v_txt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
  where p.proname = 'abrir_jornada' and n.nspname in ('public', 'privado');

  if v_txt is distinct from
     $m$privado.abrir_jornada|propietario_rpc|plpgsql|f|true|false|false|false|v|u|4|0|uuid|uuid,uuid,date,uuid|p_idempotency_key,p_camion_id,p_fecha,p_vendedor_id|-|100|0|0|0|search_path=""|true|true|true|true|0|463c3490fc6063abc7ecddb78264fe051dd4f6691fc9f8103f0bc2beec1cffd7
public.abrir_jornada|postgres|sql|f|false|false|false|false|v|u|4|0|uuid|uuid,uuid,date,uuid|p_idempotency_key,p_camion_id,p_fecha,p_vendedor_id|-|100|0|0|0|search_path=""|true|true|true|true|0|349c03bf2c303f757d8fa97dc55aff6f85b4b463b85c3e3b901f39f3c28e9115$m$ then
    raise exception 'reversión T1: abrir_jornada difiere del manifiesto (cuerpo, comentario, firma, lenguaje, atributos, owner o configuración)';
  end if;

  -- proconfig por igualdad exacta (además de su texto dentro del manifiesto).
  if exists (select 1 from pg_proc p
              where p.proname = 'abrir_jornada'
                and p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
                and p.proconfig is distinct from array['search_path=""']) then
    raise exception 'reversión T1: la configuración (proconfig) de abrir_jornada difiere de search_path=""';
  end if;
end $$;

-- La fachada es de postgres.
drop function public.abrir_jornada(uuid, uuid, date, uuid);

-- La implementación es de propietario_rpc: sin INHERIT, postgres actúa como su
-- owner sólo tras SET ROLE (O-3).
set role propietario_rpc;
drop function privado.abrir_jornada(uuid, uuid, date, uuid);
reset role;

-- Verificación: no queda ninguna función ni privilegio residual.
do $$
begin
  if exists (select 1 from pg_proc
              where proname = 'abrir_jornada'
                and pronamespace in ('public'::regnamespace, 'privado'::regnamespace))
     or has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'reversión T1: quedaron residuos de abrir_jornada o CREATE sobre privado';
  end if;
end $$;

commit;
