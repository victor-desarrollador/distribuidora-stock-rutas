-- Q0 — identidad de la sesión. Solo lectura.
select current_setting('transaction_read_only') as solo_lectura,
       current_user, session_user, current_database() as base,
       current_setting('server_version_num')::int as version_num,
       version() as version,
       (select system_identifier::text from pg_control_system()) as system_identifier,
       inet_server_addr() as ip_servidor, current_setting('port') as puerto;
