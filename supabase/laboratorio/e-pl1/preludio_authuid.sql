-- PRELUDIO DE LABORATORIO (sólo para la corrida en contenedor aislado de ejecutar_evidencia.sh).
-- Las imágenes supabase/postgres locales traen `auth.uid()` con la definición previa a GoTrue
-- (`select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid`), que ignora
-- `request.jwt.claims` (el formato que usan los tests). En un stack Supabase real GoTrue la
-- reemplaza al migrar; esta es su última redefinición (migración 20220224000811 de
-- supabase/gotrue v2.197.0, idéntica sin espacios; ver la evidencia). La prueba con el stack
-- local (smoke_stack_local.sh) NO usa este preludio: usa el auth.uid() de GoTrue.
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$$;
