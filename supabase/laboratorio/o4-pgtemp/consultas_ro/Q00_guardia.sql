-- Q00 — guardia de identidad. DEBE ejecutarse primero y dentro de BEGIN READ ONLY.
-- Compara contra valores obtenidos ANTES, por un canal independiente de esta conexión
-- (p. ej. la sesión del humano en el SQL Editor del panel del proyecto): NO se acepta un
-- system_identifier "aprendido" de la propia conexión. Variables psql obligatorias:
--   -v esperado_sysid=<system_identifier>  -v esperado_base=<base>  -v estado_esperado=original|remediado
-- Cualquier variable ausente o no coincidente aborta con ERROR (con ON_ERROR_STOP=1, rc 3)
-- antes de que se ejecute otra consulta. No imprime el valor real encontrado.
\if :{?esperado_sysid}
\else
do $g$ begin raise exception 'guardia: falta esperado_sysid'; end $g$;
\endif
\if :{?esperado_base}
\else
do $g$ begin raise exception 'guardia: falta esperado_base'; end $g$;
\endif
\if :{?estado_esperado}
\else
do $g$ begin raise exception 'guardia: falta estado_esperado'; end $g$;
\endif
select (current_setting('transaction_read_only') = 'on') as g_ro,
       (current_setting('server_version_num')::int / 10000 = 17) as g_v17,
       ((select system_identifier::text from pg_control_system()) = :'esperado_sysid') as g_sysid,
       (current_database() = :'esperado_base') as g_base,
       (:'estado_esperado' in ('original', 'remediado')) as g_estado \gset
\if :g_ro
\else
do $g$ begin raise exception 'guardia: la transaccion no es de solo lectura'; end $g$;
\endif
\if :g_v17
\else
do $g$ begin raise exception 'guardia: motor distinto de 17'; end $g$;
\endif
\if :g_sysid
\else
do $g$ begin raise exception 'guardia: system_identifier distinto del obtenido por el canal independiente'; end $g$;
\endif
\if :g_base
\else
do $g$ begin raise exception 'guardia: base distinta de la esperada'; end $g$;
\endif
\if :g_estado
\else
do $g$ begin raise exception 'guardia: estado_esperado invalido'; end $g$;
\endif
select 'GUARDIA|OK' as guardia;
