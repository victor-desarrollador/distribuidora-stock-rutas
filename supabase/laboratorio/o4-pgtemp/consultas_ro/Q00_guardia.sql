-- Q00 — guardia de identidad. DEBE ejecutarse primero y dentro de BEGIN READ ONLY.
-- Compara contra la ficha de identidad aprobada por el humano ANTES y por un canal independiente de esta
-- conexión (ver ejecutar_inventario_ro.sh y PROCEDIMIENTO_STAGING_RO.md): NO se acepta un valor "aprendido"
-- de la propia conexión. Variables psql obligatorias (las inyecta el ejecutor desde la ficha verificada):
--   esperado_sysid, esperado_base, esperado_usuario, esperado_puerto, estado_esperado (original|remediado)
-- Cualquier variable ausente o no coincidente aborta con ERROR (con ON_ERROR_STOP=1, rc 3) antes de que se
-- ejecute otra consulta. No imprime el valor real encontrado.
\if :{?esperado_sysid}
\else
do $g$ begin raise exception 'guardia: falta esperado_sysid'; end $g$;
\endif
\if :{?esperado_base}
\else
do $g$ begin raise exception 'guardia: falta esperado_base'; end $g$;
\endif
\if :{?esperado_usuario}
\else
do $g$ begin raise exception 'guardia: falta esperado_usuario'; end $g$;
\endif
\if :{?esperado_puerto}
\else
do $g$ begin raise exception 'guardia: falta esperado_puerto'; end $g$;
\endif
\if :{?estado_esperado}
\else
do $g$ begin raise exception 'guardia: falta estado_esperado'; end $g$;
\endif
select (current_setting('transaction_read_only') = 'on') as g_ro,
       (current_setting('server_version_num')::int / 10000 = 17) as g_v17,
       ((select system_identifier::text from pg_control_system()) = :'esperado_sysid') as g_sysid,
       (current_database() = :'esperado_base') as g_base,
       (current_user::text = :'esperado_usuario') as g_usuario,
       (session_user::text = :'esperado_usuario') as g_sesion,
       (current_setting('port') = :'esperado_puerto') as g_puerto,
       (current_user::text not in ('postgres', 'supabase_admin')
          and not exists (select 1 from pg_roles r where r.rolname = current_user and r.rolsuper)) as g_rol_lectura,
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
do $g$ begin raise exception 'guardia: system_identifier distinto del de la ficha'; end $g$;
\endif
\if :g_base
\else
do $g$ begin raise exception 'guardia: base distinta de la ficha'; end $g$;
\endif
\if :g_usuario
\else
do $g$ begin raise exception 'guardia: current_user distinto del de la ficha'; end $g$;
\endif
\if :g_sesion
\else
do $g$ begin raise exception 'guardia: session_user distinto del de la ficha'; end $g$;
\endif
\if :g_puerto
\else
do $g$ begin raise exception 'guardia: puerto distinto del de la ficha'; end $g$;
\endif
\if :g_rol_lectura
\else
do $g$ begin raise exception 'guardia: el usuario del inventario no puede ser postgres, supabase_admin ni un superusuario'; end $g$;
\endif
\if :g_estado
\else
do $g$ begin raise exception 'guardia: estado_esperado invalido'; end $g$;
\endif
select 'GUARDIA|OK' as guardia;
