-- O4-PGTEMP — guardia de identidad del laboratorio. Se antepone a TODA sesión
-- que crea objetos hostiles o prepara el cuerpo vulnerable. Aborta (ERROR con
-- ON_ERROR_STOP) si cualquier comprobación falla o falta un dato:
--   1. variables psql lab_nonce y lab_sysid presentes (las inyecta el arnés);
--   2. existe exactamente una fila en zz_laboratorio.identidad (creada por el
--      arnés al crear el contenedor) y su nonce coincide;
--   3. system_identifier del clúster = el registrado y = lab_sysid;
--   4. conexión local (socket o loopback), base postgres.
-- No es la única protección: el arnés crea y verifica el contenedor (sin red,
-- sin puertos, sin montajes) y sólo se conecta con `docker exec` dentro de él.
\set ON_ERROR_STOP on
\if :{?lab_nonce}
\else
do $g$ begin raise exception 'guardia O4-PGTEMP: falta lab_nonce; abortado'; end $g$;
\endif
\if :{?lab_sysid}
\else
do $g$ begin raise exception 'guardia O4-PGTEMP: falta lab_sysid; abortado'; end $g$;
\endif
select pg_catalog.set_config('o4lab.nonce', :'lab_nonce', false),
       pg_catalog.set_config('o4lab.sysid', :'lab_sysid', false) \gset o4lab_
do $g$
declare
  v_n     pg_catalog.int8;
  v_nonce pg_catalog.text;
  v_sysid pg_catalog.text;
  v_real  pg_catalog.text;
begin
  if pg_catalog.to_regclass('zz_laboratorio.identidad') is null then
    raise exception 'guardia O4-PGTEMP: no existe zz_laboratorio.identidad: no es el laboratorio; abortado';
  end if;
  select pg_catalog.count(*) into v_n from zz_laboratorio.identidad;
  if v_n <> 1 then
    raise exception 'guardia O4-PGTEMP: zz_laboratorio.identidad tiene % filas; abortado', v_n;
  end if;
  select i.nonce, i.sysid into v_nonce, v_sysid from zz_laboratorio.identidad i;
  select s.system_identifier::pg_catalog.text into v_real from pg_catalog.pg_control_system() s;
  if v_nonce is distinct from pg_catalog.current_setting('o4lab.nonce') or pg_catalog.length(v_nonce) < 32 then
    raise exception 'guardia O4-PGTEMP: nonce distinto; abortado';
  end if;
  if v_sysid is distinct from v_real or v_real is distinct from pg_catalog.current_setting('o4lab.sysid') then
    raise exception 'guardia O4-PGTEMP: system_identifier distinto; abortado';
  end if;
  if pg_catalog.inet_server_addr() is not null
     and pg_catalog.host(pg_catalog.inet_server_addr()) not in ('127.0.0.1', '::1') then
    raise exception 'guardia O4-PGTEMP: conexión no local (%); abortado', pg_catalog.inet_server_addr();
  end if;
  if pg_catalog.current_database() <> 'postgres' then
    raise exception 'guardia O4-PGTEMP: base inesperada %; abortado', pg_catalog.current_database();
  end if;
end
$g$;
select 'GUARDIA|OK|sysid=' || pg_catalog.current_setting('o4lab.sysid');
