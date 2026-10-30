-- PROCEDIMIENTO DE REVERSIÓN MANUAL de
-- supabase/migrations/20261029233000_lector_perfiles_rpc.sql (D-2).
--
-- NO ES UNA MIGRACIÓN. Vive fuera de supabase/migrations/ a propósito: el CLI de
-- Supabase no lo ejecuta ni en `db reset` ni en `db push`. Sólo se corre a mano,
-- en local o staging, con autorización humana expresa y NUNCA en producción.
--
-- Cómo usarlo (como postgres, en una conexión nueva):
--   psql "$DATABASE_URL_LOCAL" -v ON_ERROR_STOP=1 -f supabase/rollback/20261029233000_lector_perfiles_rpc.rollback.sql
-- Es una sola transacción: si algo falla, no queda nada a medias.
--
-- Después de revertir hay que revertir también el código de la rama
-- (`git revert` de la implementación de D-2), porque las pruebas pgTAP de D-2 y
-- las aserciones ampliadas fallarían sin los objetos. La migración original no
-- se edita; para volver a aplicarla en una base ya migrada hay que registrar su
-- estado con el flujo normal de migraciones del entorno (en local, `db reset`).
--
-- El rol lector_perfiles_rpc es global del clúster: no se borra si aún tiene
-- objetos o privilegios (DROP ROLE falla y la transacción se revierte).

begin;

do $$
begin
  if current_user <> 'postgres' then
    raise exception 'la reversión debe ejecutarse como postgres; actual: %', current_user;
  end if;
end $$;

-- 1. Política de lector_perfiles_rpc sobre perfiles.
drop policy if exists perfiles_select_empresa_lector on public.perfiles;

-- 2. Vista (owner lector_perfiles_rpc). Sin INHERIT, postgres sólo actúa como su
--    owner tras SET ROLE, y el rol necesita USAGE transitorio sobre privado
--    para resolver el nombre de la vista.
grant usage on schema privado to lector_perfiles_rpc;
set role lector_perfiles_rpc;
drop view if exists privado.perfiles_empresa_gestion;
reset role;
revoke usage on schema privado from lector_perfiles_rpc;

-- 3. Helper (owner propietario_rpc).
set role propietario_rpc;
drop function if exists privado.empresa_gestion_actual();
reset role;

-- 4. Privilegios del rol y el rol.
revoke select (usuario_id, empresa_id, rol, activo)
  on table public.perfiles from lector_perfiles_rpc;
drop role if exists lector_perfiles_rpc;

-- 5. Verificación: no queda ningún rastro de D-2 ni privilegios residuales.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'lector_perfiles_rpc')
     or to_regclass('privado.perfiles_empresa_gestion') is not null
     or to_regprocedure('privado.empresa_gestion_actual()') is not null
     or exists (select 1 from pg_policies
                 where schemaname = 'public' and tablename = 'perfiles'
                   and policyname = 'perfiles_select_empresa_lector') then
    raise exception 'reversión D-2 incompleta';
  end if;
  if has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'reversión D-2: quedó CREATE residual sobre privado';
  end if;
end $$;

commit;
