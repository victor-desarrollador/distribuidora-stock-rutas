-- Hardening de grants y privilegios por defecto (Blueprint §10; ADR-001 §12.4,
-- §12.6, §12.7, §12.8, §17.3 y §18.1 P11-productos).
--
-- Origen: validación post-migración de staging (23/10/2026).
--   - O-1: `service_role` no tenía SELECT sobre `public.productos` en staging.
--     ADR-001 §18.1 (P11-productos) dice que «conserva SELECT» y el pgTAP de
--     productos lo exige. En local lo daba el privilegio por defecto de la
--     plataforma; la migración 20261023140000 sólo revocó la escritura y nunca
--     concedió el SELECT de forma explícita.
--   - O-2: `service_role` conservaba TRUNCATE, REFERENCES y TRIGGER sobre
--     `empresas` y `perfiles`, y los privilegios por defecto de `postgres` en
--     `public` difieren entre local y staging (tablas: `arwdDxtm` vs `Dxtm`;
--     secuencias: `rwU` vs `w`; funciones: EXECUTE a anon/authenticated/
--     service_role sólo en local) y son más amplios que el modelo RPC +
--     mínimo privilegio. En `privado`, `PUBLIC` recibe EXECUTE por defecto.
--
-- Qué hace:
--   1. Fija los privilegios por defecto de `postgres` (rol que ejecuta las
--      migraciones) para objetos FUTUROS: tablas, secuencias y funciones de
--      `public` sin privilegios para anon, authenticated ni service_role, y
--      funciones sin EXECUTE para PUBLIC. Cada migración futura declara de
--      forma explícita lo que concede.
--   2. Deja explícito el estado de las tres tablas existentes.
--
-- Qué NO hace: no toca RLS, Topología D, `propietario_rpc`, las fachadas ni las
-- implementaciones privadas, ni el SELECT/INSERT/UPDATE/DELETE de `service_role`
-- sobre `empresas` y `perfiles` (P11 global sigue pendiente y hoy difiere entre
-- entornos), ni MAINTAIN, ni los privilegios por defecto de `supabase_admin`
-- o del esquema `storage`.
--
-- Idempotente: todo GRANT/REVOKE/ALTER DEFAULT PRIVILEGES se puede repetir.
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

-- ---------------------------------------------------------------------------
-- Rol creador real (ADR-001 §12.6)
-- ---------------------------------------------------------------------------
-- Los privilegios por defecto se definen por rol creador. Si las migraciones
-- corrieran con otro rol, los ALTER DEFAULT PRIVILEGES de abajo no cubrirían
-- los objetos que ese rol cree: se aborta en lugar de aplicar en silencio algo
-- que no protege.
do $$
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres (rol creador de objetos); actual: %',
      current_user;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Privilegios por defecto de objetos futuros creados por postgres
-- ---------------------------------------------------------------------------
-- Tablas y secuencias de `public`: nada para los roles de la Data API. Cada
-- tabla nueva concede explícitamente lo que necesite (p. ej. SELECT a
-- authenticated) y revoca lo que no.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;

-- Funciones de `public`: los EXECUTE por esquema que la plataforma concede a
-- anon/authenticated/service_role (se deshacen porque son un GRANT previo).
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, service_role;

-- EXECUTE de PUBLIC en funciones nuevas (todos los esquemas, incluido
-- `privado`). Debe ser la forma global, sin IN SCHEMA: un REVOKE por esquema
-- no elimina el privilegio global de PUBLIC (ADR-001 §12.6; verificado en
-- local: con IN SCHEMA privado la ACL de una función nueva sigue siendo NULL).
alter default privileges for role postgres
  revoke execute on functions from public;

-- ---------------------------------------------------------------------------
-- Tablas existentes: estado explícito, sin depender de los defaults
-- ---------------------------------------------------------------------------
-- anon: ningún privilegio. authenticated: sólo SELECT (RLS filtra por
-- empresa_id); las escrituras de productos pasan por las RPC (Topología D).
revoke all on table public.empresas, public.perfiles, public.productos
  from public, anon, authenticated;

grant select on table public.empresas, public.perfiles, public.productos
  to authenticated;

-- service_role (BYPASSRLS) no necesita TRUNCATE, REFERENCES ni TRIGGER sobre
-- ninguna tabla de negocio. Sobre empresas y perfiles no se cambia el resto
-- (P11 global pendiente; ADR-001 §18.1: no cambia sus privilegios sobre
-- perfiles).
revoke truncate, references, trigger
  on table public.empresas, public.perfiles from service_role;

-- O-1: productos. P11-productos: conserva SELECT y no escribe directamente.
grant select on table public.productos to service_role;

revoke insert, update, delete, truncate, references, trigger
  on table public.productos from service_role;
