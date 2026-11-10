-- O4-PGTEMP — sesión de UN vector (la arma el arnés: guardia.sql + este
-- archivo). Variables psql: lab_nonce, lab_sysid, atacante, vector, ddl.
-- Vectores (uno por sesión, sesión nueva = sin caché de plpgsql):
--   record : dominio pg_temp."record" (tipo de «cmd»);
--   name   : dominio pg_temp."name"   (tipo de «tbl»);
--   format : función pg_temp.format(text, text, name) (+ llamada explícita de control);
--   op_eq  : operador pg_temp.= (text, text)        (+ llamada explícita de control).
-- La sonda sólo cuenta en secuencias temporales quién la ejecuta (el atacante
-- u otro rol); no modifica nada. El DDL disparador se revierte siempre.
set client_min_messages = log;
select pg_catalog.set_config('o4lab.atacante', :'atacante', false) \gset o4lab_
-- Compila los event triggers de la plataforma (pgrst_ddl_watch/drop_watch,
-- SECURITY INVOKER) ANTES de los objetos hostiles, sin disparar ensure_rls
-- (CREATE/DROP SEQUENCE no están entre sus tags).
create temp sequence o4_calentar;
drop sequence o4_calentar;
create temp sequence o4_cnt_priv;
create temp sequence o4_cnt_atk;
grant usage, select, update on sequence pg_temp.o4_cnt_priv, pg_temp.o4_cnt_atk to public;
select pg_catalog.set_config('o4lab.vector', :'vector', false) \gset o4lab_
set role :"atacante";
create function pg_temp.o4_sonda(v pg_catalog.text) returns pg_catalog.bool
language plpgsql as $f$
begin
  if current_user::pg_catalog.text = pg_catalog.current_setting('o4lab.atacante') then
    perform pg_catalog.nextval('pg_temp.o4_cnt_atk');
  else
    perform pg_catalog.nextval('pg_temp.o4_cnt_priv');
  end if;
  return true;
end $f$;
\if :{?v_record}
create domain pg_temp."record" as pg_catalog.text check (pg_temp.o4_sonda(value));
\endif
\if :{?v_name}
create domain pg_temp."name" as pg_catalog.text check (pg_temp.o4_sonda(value));
\endif
\if :{?v_format}
create function pg_temp.format(pg_catalog.text, pg_catalog.text, pg_catalog.name) returns pg_catalog.text
  language sql as $f$ select pg_catalog.concat(pg_temp.o4_sonda($1), $2, $3) $f$;
-- control: la sonda funciona cuando se la invoca explícitamente
select 'CONTROL|' || pg_temp.format('x', 'y', 'z'::pg_catalog.name);
\endif
\if :{?v_op_eq}
create function pg_temp.o4_eq(pg_catalog.text, pg_catalog.text) returns pg_catalog.bool
  language sql as $f$ select pg_temp.o4_sonda($1) and $1 operator(pg_catalog.=) $2 $f$;
create operator pg_temp.= (leftarg = pg_catalog.text, rightarg = pg_catalog.text, function = pg_temp.o4_eq);
-- control: el operador funciona cuando se lo invoca explícitamente
select 'CONTROL|' || ('a'::pg_catalog.text operator(pg_temp.=) 'a'::pg_catalog.text)::pg_catalog.text;
\endif
select pg_catalog.set_config('o4lab.ddl', :'ddl', false) \gset o4lab_
-- Contador de control ANTES del DDL (las llamadas explícitas suman al atacante).
select 'ANTES|atk=' || (select case when is_called then last_value else 0 end from pg_temp.o4_cnt_atk);
do $a$
declare v_ctx pg_catalog.text;
begin
  begin
    execute pg_catalog.current_setting('o4lab.ddl');
    raise exception 'o4lab_revertir';
  exception when others then
    get stacked diagnostics v_ctx = pg_exception_context;
    if sqlerrm <> 'o4lab_revertir' then
      raise notice 'DDL_ERROR|%|%', sqlerrm, pg_catalog.replace(v_ctx, E'\n', ' / ');
    end if;
  end;
end
$a$;
reset role;
select 'MEDIDA|' || pg_catalog.current_setting('o4lab.vector')
       || '|priv=' || (select case when is_called then last_value else 0 end from pg_temp.o4_cnt_priv)
       || '|atk=' || (select case when is_called then last_value else 0 end from pg_temp.o4_cnt_atk);
