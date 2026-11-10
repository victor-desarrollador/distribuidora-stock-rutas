-- Q4 — versión del motor, extensiones y migraciones aplicadas. Solo lectura.
select current_setting('server_version') as server_version, current_setting('server_version_num')::int as version_num,
       version() as version;
select extname, extversion from pg_extension order by extname;
-- Historial de migraciones: requiere USAGE sobre el esquema y SELECT sobre la tabla. Si el rol del inventario no los
-- tiene, NO se amplía ningún privilegio: se informa la dependencia y la sesión continúa (la señal queda sin verificar).
-- (to_regclass falla sin USAGE sobre el esquema, por eso se consulta el privilegio antes.)
select exists (select 1 from pg_namespace where nspname = 'supabase_migrations') as hay_esquema \gset
\if :hay_esquema
select has_schema_privilege('supabase_migrations', 'USAGE') as puede_usar_esquema \gset
\if :puede_usar_esquema
select to_regclass('supabase_migrations.schema_migrations') is not null as hay_historial \gset
\if :hay_historial
select has_table_privilege('supabase_migrations.schema_migrations', 'SELECT') as puede_leer_historial \gset
\if :puede_leer_historial
select version, name from supabase_migrations.schema_migrations order by version;
\else
select 'DEPENDENCIA PENDIENTE: el rol del inventario no tiene SELECT sobre supabase_migrations.schema_migrations; historial NO verificado (el privilegio necesario no esta definido)' as nota;
\endif
\else
select 'sin supabase_migrations.schema_migrations en esta base' as nota;
\endif
\else
select 'DEPENDENCIA PENDIENTE: el rol del inventario no tiene USAGE sobre el esquema supabase_migrations; historial NO verificado (el privilegio necesario no esta definido)' as nota;
\endif
\else
select 'sin supabase_migrations.schema_migrations en esta base' as nota;
\endif
