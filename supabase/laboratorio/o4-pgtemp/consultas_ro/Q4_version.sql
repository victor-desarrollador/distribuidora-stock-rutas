-- Q4 — versión del motor, extensiones y migraciones aplicadas. Solo lectura.
select current_setting('server_version') as server_version, current_setting('server_version_num')::int as version_num,
       version() as version;
select extname, extversion from pg_extension order by extname;
select to_regclass('supabase_migrations.schema_migrations') is not null as hay_historial \gset
\if :hay_historial
select version, name from supabase_migrations.schema_migrations order by version;
\else
select 'sin supabase_migrations.schema_migrations en esta base' as nota;
\endif
