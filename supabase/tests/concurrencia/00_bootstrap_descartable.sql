-- =============================================================================
-- Arnés de concurrencia (ADR-001 §18.4.11) — bootstrap EMULADO y DESCARTABLE.
--
-- NO es un test pgTAP. Sólo lo aplica `arnes.sh` sobre su propio clúster efímero
-- (initdb + pg_ctl, sin red), en la base `arnes`, antes de las migraciones.
--
-- Protección P1: `supabase test db` ejecuta `pg_prove --ext .pg --ext .sql -r
-- supabase/tests` (verificado con el CLI 2.120.0), así que descubre y ejecuta
-- este archivo. Sin la variable `arnes_descartable` (que sólo define arnes.sh)
-- el archivo emite un plan TAP vacío (`1..0 # SKIP`) y no ejecuta ninguna
-- sentencia: no crea roles, esquemas ni tablas. Con la variable definida exige,
-- además, la base `arnes` y el `cluster_name` que fija arnes.sh, de modo que
-- tampoco puede aplicarse por error sobre Supabase local, staging ni producción.
--
-- Emulación (atributos observados en Supabase 17.11, ADR-001 §18.4.11):
--   - superusuario de arranque `supabase_admin` (lo crea initdb, no este archivo);
--   - `postgres` LOGIN NOSUPERUSER CREATEROLE BYPASSRLS, miembro con INHERIT de
--     `anon`, `authenticated` y `service_role`;
--   - `service_role` BYPASSRLS; `anon` y `authenticated` NOBYPASSRLS;
--   - `authenticator` (LOGIN NOINHERIT, miembro de los tres roles de la Data API):
--     no figura en la lista de §18.4.11, pero las migraciones lo recorren al
--     verificar privilegios y sin él no se aplican;
--   - esquema `auth` con USAGE para `anon`, `authenticated`, `service_role` y
--     `postgres`; `auth.uid()` con la misma expresión de claims que
--     `privado.usuario_actual()`; tabla mínima `auth.users (id uuid primary key)`
--     para que se pueda crear la FK de `perfiles`.
-- No emula GoTrue, JWT reales, PostgREST ni la imagen de Supabase.
-- =============================================================================
\if :{?arnes_descartable}
\set ON_ERROR_STOP on

do $$
begin
  if current_setting('cluster_name') <> 'arnes_concurrencia'
     or current_database() <> 'arnes' then
    raise exception 'bootstrap descartable: clúster o base inesperados (%, %)',
      current_setting('cluster_name'), current_database();
  end if;
end $$;

create role postgres login nosuperuser createrole bypassrls;
create role anon nologin noinherit nobypassrls;
create role authenticated nologin noinherit nobypassrls;
create role service_role nologin noinherit bypassrls;
create role authenticator login noinherit;

grant anon, authenticated, service_role to authenticator;
grant anon, authenticated, service_role to postgres with inherit true, set true;

alter database arnes owner to postgres;
alter schema public owner to postgres;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role, postgres;

create table auth.users (id uuid primary key);
grant all on table auth.users to postgres;

create function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;
grant execute on function auth.uid() to anon, authenticated, service_role, postgres;
\else
\echo 1..0 # SKIP archivo del arnés de concurrencia: no es un test pgTAP
\endif
