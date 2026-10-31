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
-- jornadas y operaciones creadas con la RPC quedan en sus tablas. Falla cerrado
-- si las funciones ya no son exactamente las aprobadas (owner, SECURITY,
-- search_path o ACL distintos), para no descartar en silencio un cambio
-- posterior. Si algo depende de ellas, el DROP sin CASCADE falla.
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
