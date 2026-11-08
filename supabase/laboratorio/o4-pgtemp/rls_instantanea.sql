-- Instantánea CANÓNICA de RLS del esquema public para el arnés de explotación (ejecutar.sh) y su prueba de sensibilidad
-- (probar_rls_instantanea.sh). Sólo lectura. Corrige H-04 (Codex, 06/11/2026): la comparación anterior sólo contaba políticas y no
-- detectaba una política modificada o sustituida que conservara el conteo.
-- Una línea por tabla (T|…) y una por política (P|…), ordenadas de forma determinista por esquema, tabla y nombre (collation C):
-- no dependen del orden físico de pg_policy ni del orden en que se declararon los roles.
--   T|esquema.tabla|rls=…|force=…
--   P|esquema.tabla|nombre|cmd=…|permissive=…|roles=…|using=…|check=…
-- roles: nombres ordenados (collation C); PUBLIC si polroles contiene 0. using/check: ABSENT si la expresión es NULL; si existe,
-- EXPR: + SHA-256 del texto de pg_get_expr (conserva la diferencia entre NULL y expresión presente, y detecta cualquier cambio de texto).
-- El archivo termina con el único «;» de la sentencia (el arnés lo convierte en CREATE TEMP TABLE … AS cuando hace falta).
select l.linea
  from (
    select 1 as orden, n.nspname::text as esquema, c.relname::text as tabla, ''::text as politica,
           concat_ws('|', 'T', n.nspname || '.' || c.relname, 'rls=' || c.relrowsecurity::text, 'force=' || c.relforcerowsecurity::text) as linea
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
    union all
    select 2, n.nspname::text, c.relname::text, p.polname::text,
           concat_ws('|', 'P', n.nspname || '.' || c.relname, p.polname::text,
                     'cmd=' || p.polcmd::text,
                     'permissive=' || p.polpermissive::text,
                     'roles=' || coalesce((select string_agg(r.nombre, ',' order by r.nombre collate "C")
                                             from (select case when x = 0 then 'PUBLIC'
                                                               else (select o.rolname::text from pg_roles o where o.oid = x) end as nombre
                                                     from unnest(p.polroles) as x) r), ''),
                     'using=' || case when p.polqual is null then 'ABSENT'
                                      else 'EXPR:' || encode(sha256(convert_to(pg_get_expr(p.polqual, p.polrelid), 'UTF8')), 'hex') end,
                     'check=' || case when p.polwithcheck is null then 'ABSENT'
                                      else 'EXPR:' || encode(sha256(convert_to(pg_get_expr(p.polwithcheck, p.polrelid), 'UTF8')), 'hex') end)
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
  ) l
 order by l.orden, l.esquema collate "C", l.tabla collate "C", l.politica collate "C";
