-- PROCEDIMIENTO DE REVERSIÓN MANUAL de
-- supabase/migrations/20261030120000_jornadas_esquema.sql (D-1).
--
-- NO ES UNA MIGRACIÓN. Vive fuera de supabase/migrations/ a propósito: el CLI de
-- Supabase no lo ejecuta ni en `db reset` ni en `db push`. Sólo se corre a mano,
-- en local o staging, con autorización humana expresa y NUNCA en producción.
--
-- Cómo usarlo (como postgres, en una conexión nueva):
--   psql "$DATABASE_URL_LOCAL" -v ON_ERROR_STOP=1 -f supabase/rollback/20261030120000_jornadas_esquema.rollback.sql
-- Es una sola transacción: si cualquier verificación o sentencia falla, no queda
-- nada a medias.
--
-- Garantías:
--   - NO borra filas de datos: si existe cualquier dato de jornadas (filas en
--     jornadas, en los dos historiales, operaciones de jornada o movimientos de
--     carga/descarga), ABORTA sin cambios. Con datos, D-1 no es reversible por
--     este camino; hace falta un respaldo manual y una decisión humana aparte.
--   - NO usa CASCADE. Si algo todavía depende de los objetos de D-1 (vistas,
--     FK de otras tablas, policies, triggers, funciones, índices o restricciones
--     posteriores), ABORTA sin cambios y nombra la dependencia. Cada DROP, sin
--     CASCADE, falla además por la propia restricción de PostgreSQL.
--   - Falla cerrado ante deriva: si las restricciones, índices, policies o ACL
--     ya no son exactamente los que dejó D-1 (por ejemplo, una migración
--     posterior amplió los tipos de operación), ABORTA: restaurar los tres tipos
--     de Stock perdería esa ampliación.
--   - Límite conocido: PostgreSQL no registra en pg_depend las referencias dentro
--     del texto de una función plpgsql. Para eso hay un barrido conservador por
--     nombre sobre las funciones de public y privado (las seis RPC de ADR-007
--     incluidas); una referencia dinámica construida en tiempo de ejecución no se
--     puede detectar.
--   - No es idempotente: una segunda ejecución falla y revierte sin cambios.
--
-- Después de revertir hay que revertir también el código de la rama
-- (`git revert` de la implementación de D-1), porque las pruebas pgTAP de D-1 y
-- las aserciones ampliadas fallarían sin los objetos. La migración original no se
-- edita; para volver a aplicarla en una base ya migrada hay que registrar su
-- estado con el flujo normal de migraciones del entorno (en local, `db reset`).
--
-- Esta reversión no toca D-2 (lector_perfiles_rpc, su vista ni su helper).

begin;

set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 0. Entorno y bloqueo
-- ---------------------------------------------------------------------------
do $$
begin
  if current_user <> 'postgres' then
    raise exception 'la reversión debe ejecutarse como postgres; actual: %', current_user;
  end if;
  if to_regclass('public.jornadas') is null
     or to_regclass('public.reasignaciones_vendedor') is null
     or to_regclass('public.correcciones_jornada') is null then
    raise exception 'reversión D-1: D-1 no está aplicada (faltan las tablas de jornadas)';
  end if;
end $$;

lock table public.jornadas, public.reasignaciones_vendedor, public.correcciones_jornada,
  public.operaciones, public.movimientos_stock in access exclusive mode;

-- ---------------------------------------------------------------------------
-- 1. Precheck bloqueante (no cambia nada)
-- ---------------------------------------------------------------------------
do $$
declare
  v_tablas_d1 oid[] := array['public.jornadas'::regclass::oid,
                             'public.reasignaciones_vendedor'::regclass::oid,
                             'public.correcciones_jornada'::regclass::oid];
  v_op oid := 'public.operaciones'::regclass::oid;
  v_mov oid := 'public.movimientos_stock'::regclass::oid;
  v_att_op smallint;
  v_att_mov smallint;
  v_constraints_compartidas text[] := array[
    'operaciones_referencia_apertura', 'operaciones_referencia_unica',
    'operaciones_jornada_fk', 'operaciones_jornada_por_tipo',
    'movimientos_stock_jornada_fk', 'movimientos_stock_jornada_por_tipo',
    'movimientos_stock_operacion_referencia_fk'];
  v_indices_d1 text[] := array[
    'operaciones_referencia_apertura', 'operaciones_referencia_unica',
    'movimientos_stock_operacion_producto_unica', 'movimientos_stock_jornada_idx'];
  v_policies_compartidas text[] := array[
    'operaciones_insert_propietario_rpc', 'movimientos_stock_insert_propietario_rpc'];
  v_n bigint;
  v_txt text;
  r record;
begin
  select attnum into v_att_op from pg_attribute
   where attrelid = v_op and attname = 'jornada_id' and not attisdropped;
  select attnum into v_att_mov from pg_attribute
   where attrelid = v_mov and attname = 'jornada_id' and not attisdropped;
  if v_att_op is null or v_att_mov is null then
    raise exception 'reversión D-1: falta la columna jornada_id en operaciones o movimientos_stock';
  end if;

  -- (a) DATOS: nada se borra, así que cualquier fila aborta.
  select count(*) into v_n from public.jornadas;
  if v_n > 0 then raise exception 'reversión D-1: jornadas tiene % fila(s); no se revierte con datos', v_n; end if;
  select count(*) into v_n from public.reasignaciones_vendedor;
  if v_n > 0 then raise exception 'reversión D-1: reasignaciones_vendedor tiene % fila(s); no se revierte con datos', v_n; end if;
  select count(*) into v_n from public.correcciones_jornada;
  if v_n > 0 then raise exception 'reversión D-1: correcciones_jornada tiene % fila(s); no se revierte con datos', v_n; end if;
  select count(*) into v_n from public.operaciones
   where tipo not in ('ingreso', 'a_cuarentena', 'merma') or jornada_id is not null;
  if v_n > 0 then raise exception 'reversión D-1: operaciones tiene % fila(s) de jornadas; no se revierte con datos', v_n; end if;
  select count(*) into v_n from public.movimientos_stock
   where tipo_movimiento not in ('ingreso', 'a_cuarentena', 'merma') or jornada_id is not null;
  if v_n > 0 then raise exception 'reversión D-1: movimientos_stock tiene % fila(s) de carga/descarga; no se revierte con datos', v_n; end if;

  -- (b) DEPENDENCIAS: cualquier objeto que dependa de las tablas de D-1, de las
  -- columnas jornada_id o de los destinos de las FK de referencia y que no sea
  -- uno de los objetos propios de D-1 aborta (sin CASCADE).
  for r in
    select pg_describe_object(d.classid, d.objid, d.objsubid) as objeto
      from pg_depend d
     where d.refclassid = 'pg_class'::regclass
       and (d.refobjid = any (v_tablas_d1)
            or (d.refobjid = v_op and d.refobjsubid = v_att_op)
            or (d.refobjid = v_mov and d.refobjsubid = v_att_mov))
       and not (
         (d.classid = 'pg_constraint'::regclass and exists (
            select 1 from pg_constraint c
             where c.oid = d.objid
               and (c.conrelid = any (v_tablas_d1) or c.conname = any (v_constraints_compartidas))))
         or (d.classid = 'pg_class'::regclass and exists (
            select 1 from pg_class c
             where c.oid = d.objid
               and (c.relname = any (v_indices_d1)
                    or exists (select 1 from pg_index i
                                where i.indexrelid = c.oid and i.indrelid = any (v_tablas_d1))
                    or exists (select 1 from pg_class t
                                where t.oid = any (v_tablas_d1) and t.reltoastrelid = c.oid))))
         or (d.classid = 'pg_type'::regclass and exists (
            select 1 from pg_type t where t.oid = d.objid and t.typrelid = any (v_tablas_d1)))
         or (d.classid = 'pg_attrdef'::regclass and exists (
            select 1 from pg_attrdef a where a.oid = d.objid and a.adrelid = any (v_tablas_d1)))
         or (d.classid = 'pg_policy'::regclass and exists (
            select 1 from pg_policy p
             where p.oid = d.objid
               and (p.polrelid = any (v_tablas_d1) or p.polname = any (v_policies_compartidas))))
       )
  loop
    raise exception 'reversión D-1: hay una dependencia posterior que impide revertir sin pérdida: %', r.objeto;
  end loop;

  -- Dependientes de los destinos de las FK de referencia (UNIQUE
  -- operaciones_referencia_*): sólo las FK propias de D-1.
  for r in
    select c.conrelid::regclass::text || '.' || c.conname as objeto
      from pg_constraint c
     where c.contype = 'f'
       and c.conindid in (select conindid from pg_constraint
                           where conrelid = v_op
                             and conname in ('operaciones_referencia_apertura', 'operaciones_referencia_unica'))
       and not (c.conrelid = any (v_tablas_d1) or c.conname = any (v_constraints_compartidas))
  loop
    raise exception 'reversión D-1: una FK posterior depende de los UNIQUE de referencia de operaciones: %', r.objeto;
  end loop;

  -- FK de otras tablas hacia las tablas de D-1.
  for r in
    select c.conrelid::regclass::text || '.' || c.conname as objeto
      from pg_constraint c
     where c.contype = 'f' and c.confrelid = any (v_tablas_d1)
       and not (c.conrelid = any (v_tablas_d1) or c.conname = any (v_constraints_compartidas))
  loop
    raise exception 'reversión D-1: una FK posterior apunta a las tablas de jornadas: %', r.objeto;
  end loop;

  -- Vistas, vistas materializadas y reglas que usen las tablas o jornada_id.
  for r in
    select v.oid::regclass::text as objeto
      from pg_depend d
      join pg_rewrite w on d.classid = 'pg_rewrite'::regclass and w.oid = d.objid
      join pg_class v on v.oid = w.ev_class
     where d.refclassid = 'pg_class'::regclass
       and (d.refobjid = any (v_tablas_d1)
            or (d.refobjid = v_op and d.refobjsubid = v_att_op)
            or (d.refobjid = v_mov and d.refobjsubid = v_att_mov))
       and v.oid <> all (v_tablas_d1)
  loop
    raise exception 'reversión D-1: una vista o regla usa objetos de D-1: %', r.objeto;
  end loop;

  -- Triggers (no internos) sobre las tablas de D-1.
  for r in
    select t.tgrelid::regclass::text || '.' || t.tgname as objeto
      from pg_trigger t
     where t.tgrelid = any (v_tablas_d1) and not t.tgisinternal
  loop
    raise exception 'reversión D-1: hay un trigger sobre las tablas de jornadas: %', r.objeto;
  end loop;

  -- Funciones: dependencias registradas (SQL, tipos de fila) y barrido por
  -- nombre del texto (plpgsql); incluye las seis RPC de ADR-007.
  for r in
    select p.oid::regprocedure::text as objeto
      from pg_proc p
     where p.pronamespace in ('public'::regnamespace, 'privado'::regnamespace)
       and (p.proname in ('abrir_jornada', 'reasignar_vendedor', 'corregir_jornada',
                          'registrar_carga', 'registrar_descarga', 'confirmar_salida')
            or p.prosrc ~* '(jornadas|reasignaciones_vendedor|correcciones_jornada|jornada_id)')
  loop
    raise exception 'reversión D-1: hay una función que usa o declara objetos de jornadas: %', r.objeto;
  end loop;
  for r in
    select pg_describe_object(d.classid, d.objid, d.objsubid) as objeto
      from pg_depend d
     where d.classid = 'pg_proc'::regclass
       and d.refclassid = 'pg_class'::regclass
       and (d.refobjid = any (v_tablas_d1)
            or (d.refobjid = v_op and d.refobjsubid = v_att_op)
            or (d.refobjid = v_mov and d.refobjsubid = v_att_mov))
  loop
    raise exception 'reversión D-1: una función depende de objetos de jornadas: %', r.objeto;
  end loop;

  -- Índices o restricciones posteriores sobre jornada_id en las tablas compartidas.
  for r in
    select i.indexrelid::regclass::text as objeto
      from pg_index i
     where ((i.indrelid = v_op and v_att_op = any (i.indkey::smallint[]))
            or (i.indrelid = v_mov and v_att_mov = any (i.indkey::smallint[])))
       and i.indexrelid::regclass::text <> all (v_indices_d1)
  loop
    raise exception 'reversión D-1: hay un índice posterior sobre jornada_id: %', r.objeto;
  end loop;

  -- (c) DERIVA: el conjunto de restricciones, índices y policies de las tablas
  -- compartidas debe ser exactamente el que dejó D-1.
  select string_agg(conname::text, ',' order by conname::text collate "C") into v_txt
    from pg_constraint where conrelid = v_op;
  if v_txt is distinct from
     'operaciones_actor_fk,operaciones_empresa_id_fkey,operaciones_empresa_id_unico,operaciones_huella_sha256,'
     || 'operaciones_idempotencia_unica,operaciones_jornada_fk,operaciones_jornada_por_tipo,operaciones_pkey,'
     || 'operaciones_referencia_apertura,operaciones_referencia_unica,operaciones_tipo_valido' then
    raise exception 'reversión D-1: las restricciones de operaciones no son las que dejó D-1: %', v_txt;
  end if;
  select string_agg(conname::text, ',' order by conname::text collate "C") into v_txt
    from pg_constraint where conrelid = v_mov;
  if v_txt is distinct from
     'movimientos_stock_actor_fk,movimientos_stock_cantidad_positiva,movimientos_stock_destino_fk,'
     || 'movimientos_stock_empresa_id_fkey,movimientos_stock_empresa_id_unico,movimientos_stock_extremo_requerido,'
     || 'movimientos_stock_extremos_distintos,movimientos_stock_forma_por_tipo,movimientos_stock_jornada_fk,'
     || 'movimientos_stock_jornada_por_tipo,movimientos_stock_motivo_codigo_valido,movimientos_stock_motivo_normalizado,'
     || 'movimientos_stock_motivo_por_tipo,movimientos_stock_operacion_fk,movimientos_stock_operacion_referencia_fk,'
     || 'movimientos_stock_origen_fk,movimientos_stock_pkey,movimientos_stock_producto_fk,movimientos_stock_tipo_valido' then
    raise exception 'reversión D-1: las restricciones de movimientos_stock no son las que dejó D-1: %', v_txt;
  end if;
  select string_agg(c.relname::text, ',' order by c.relname::text collate "C") into v_txt
    from pg_index i join pg_class c on c.oid = i.indexrelid
   where i.indrelid = v_mov;
  if v_txt is distinct from
     'movimientos_stock_destino_idx,movimientos_stock_empresa_id_unico,movimientos_stock_jornada_idx,'
     || 'movimientos_stock_operacion_producto_unica,movimientos_stock_operacion_unitaria_unica,'
     || 'movimientos_stock_origen_idx,movimientos_stock_pkey' then
    raise exception 'reversión D-1: los índices de movimientos_stock no son los que dejó D-1: %', v_txt;
  end if;
  select string_agg(c.relname::text, ',' order by c.relname::text collate "C") into v_txt
    from pg_index i join pg_class c on c.oid = i.indexrelid
   where i.indrelid = v_op;
  if v_txt is distinct from
     'operaciones_empresa_id_unico,operaciones_idempotencia_unica,operaciones_pkey,'
     || 'operaciones_referencia_apertura,operaciones_referencia_unica' then
    raise exception 'reversión D-1: los índices de operaciones no son los que dejó D-1: %', v_txt;
  end if;

  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = v_op and conname = 'operaciones_tipo_valido')
       is distinct from
       'CHECK ((tipo = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text, ''apertura_jornada''::text, ''reasignacion_vendedor''::text, ''correccion_jornada''::text, ''carga''::text, ''descarga''::text, ''salida_jornada''::text])))'
     or (select pg_get_constraintdef(oid) from pg_constraint where conrelid = v_op and conname = 'operaciones_jornada_por_tipo')
       is distinct from
       'CHECK ((((tipo = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text, ''apertura_jornada''::text])) AND (jornada_id IS NULL)) OR ((tipo = ANY (ARRAY[''reasignacion_vendedor''::text, ''correccion_jornada''::text, ''carga''::text, ''descarga''::text, ''salida_jornada''::text])) AND (jornada_id IS NOT NULL))))'
     or (select pg_get_constraintdef(oid) from pg_constraint where conrelid = v_mov and conname = 'movimientos_stock_tipo_valido')
       is distinct from
       'CHECK ((tipo_movimiento = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text, ''carga''::text, ''descarga''::text])))'
     or (select pg_get_constraintdef(oid) from pg_constraint where conrelid = v_mov and conname = 'movimientos_stock_forma_por_tipo')
       is distinct from
       'CHECK ((((tipo_movimiento = ''ingreso''::text) AND (ubicacion_origen_id IS NULL) AND (ubicacion_destino_id IS NOT NULL)) OR ((tipo_movimiento = ''a_cuarentena''::text) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NOT NULL)) OR ((tipo_movimiento = ''merma''::text) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NULL)) OR ((tipo_movimiento = ANY (ARRAY[''carga''::text, ''descarga''::text])) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NOT NULL))))'
     or (select pg_get_constraintdef(oid) from pg_constraint where conrelid = v_mov and conname = 'movimientos_stock_motivo_por_tipo')
       is distinct from
       'CHECK ((((tipo_movimiento = ''ingreso''::text) AND (motivo_codigo IS NULL)) OR ((tipo_movimiento = ''a_cuarentena''::text) AND (motivo_codigo IS NULL) AND (motivo IS NOT NULL)) OR ((tipo_movimiento = ''merma''::text) AND (motivo_codigo IS NOT NULL) AND ((motivo_codigo <> ''otro''::text) OR (motivo IS NOT NULL))) OR ((tipo_movimiento = ''carga''::text) AND (motivo_codigo IS NULL) AND (motivo IS NULL)) OR ((tipo_movimiento = ''descarga''::text) AND (motivo_codigo IS NULL) AND (motivo IS NOT NULL))))'
     or (select pg_get_constraintdef(oid) from pg_constraint where conrelid = v_mov and conname = 'movimientos_stock_jornada_por_tipo')
       is distinct from
       'CHECK ((((tipo_movimiento = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text])) AND (jornada_id IS NULL)) OR ((tipo_movimiento = ANY (ARRAY[''carga''::text, ''descarga''::text])) AND (jornada_id IS NOT NULL))))'
     or pg_get_indexdef('public.movimientos_stock_operacion_producto_unica'::regclass)
       is distinct from
       'CREATE UNIQUE INDEX movimientos_stock_operacion_producto_unica ON public.movimientos_stock USING btree (empresa_id, operacion_id, producto_id) WHERE (tipo_movimiento = ANY (ARRAY[''carga''::text, ''descarga''::text]))'
     or pg_get_indexdef('public.movimientos_stock_operacion_unitaria_unica'::regclass)
       is distinct from
       'CREATE UNIQUE INDEX movimientos_stock_operacion_unitaria_unica ON public.movimientos_stock USING btree (empresa_id, operacion_id) WHERE (tipo_movimiento = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text]))' then
    raise exception 'reversión D-1: alguna restricción o índice fue modificado después de D-1 (deriva)';
  end if;

  -- Policies: mismos nombres y roles que dejó D-1; las dos policies de INSERT
  -- sólo pueden mencionar los literales de D-1 (si una migración posterior sumó
  -- un tipo, restaurar la versión de Stock lo perdería).
  select string_agg(tablename || '.' || policyname || ':' || cmd || ':' || array_to_string(roles, ','),
                    ',' order by tablename, policyname) into v_txt
    from pg_policies
   where schemaname = 'public' and tablename in ('operaciones', 'movimientos_stock');
  if v_txt is distinct from
     'movimientos_stock.movimientos_stock_insert_propietario_rpc:INSERT:propietario_rpc,'
     || 'movimientos_stock.movimientos_stock_select_empresa:SELECT:authenticated,'
     || 'movimientos_stock.movimientos_stock_select_propietario_rpc:SELECT:propietario_rpc,'
     || 'operaciones.operaciones_insert_propietario_rpc:INSERT:propietario_rpc,'
     || 'operaciones.operaciones_select_empresa:SELECT:authenticated,'
     || 'operaciones.operaciones_select_propietario_rpc:SELECT:propietario_rpc' then
    raise exception 'reversión D-1: las policies de operaciones o movimientos_stock no son las que dejó D-1';
  end if;
  select string_agg(distinct m[1], ',' order by m[1]) into v_txt
    from pg_policies p, regexp_matches(p.with_check, '''([a-z_]+)''::text', 'g') m
   where p.schemaname = 'public' and p.policyname = 'operaciones_insert_propietario_rpc';
  if v_txt is distinct from
     'a_cuarentena,apertura_jornada,carga,correccion_jornada,descarga,dueno,encargado,ingreso,merma,reasignacion_vendedor,salida_jornada' then
    raise exception 'reversión D-1: la policy operaciones_insert_propietario_rpc fue modificada (deriva): %', v_txt;
  end if;
  select string_agg(distinct m[1], ',' order by m[1]) into v_txt
    from pg_policies p, regexp_matches(p.with_check, '''([a-z_]+)''::text', 'g') m
   where p.schemaname = 'public' and p.policyname = 'movimientos_stock_insert_propietario_rpc';
  if v_txt is distinct from
     'a_cuarentena,camion,carga,cuarentena,deposito,descarga,dueno,encargado,ingreso,merma' then
    raise exception 'reversión D-1: la policy movimientos_stock_insert_propietario_rpc fue modificada (deriva): %', v_txt;
  end if;

  -- (d) ACL y entorno: sólo los privilegios que dejó D-1.
  if exists (select 1 from pg_class c, aclexplode(c.relacl) a
              where c.oid = any (v_tablas_d1)
                and a.grantee not in ('postgres'::regrole, 'authenticated'::regrole, 'propietario_rpc'::regrole))
     or exists (select 1 from pg_attribute t, aclexplode(t.attacl) a
                 where t.attrelid = any (v_tablas_d1 || v_op || v_mov) and t.attacl is not null
                   and (t.attrelid = any (v_tablas_d1) or t.attname = 'jornada_id')
                   and a.grantee <> 'propietario_rpc'::regrole)
     or exists (select 1 from pg_attribute t, aclexplode(t.attacl) a
                 where t.attrelid = any (array[v_op, v_mov]) and t.attname = 'jornada_id'
                   and a.privilege_type <> 'INSERT')
     or exists (select 1 from pg_class c where c.oid = any (v_tablas_d1)
                   and (c.relowner <> 'postgres'::regrole or not c.relrowsecurity or c.relforcerowsecurity)) then
    raise exception 'reversión D-1: owner, RLS o ACL de las tablas de jornadas fuera de lo que dejó D-1';
  end if;

  -- ACL exacta de las tablas de D-1 (privilegios de tabla y por columna).
  select string_agg(c.relname::text || ':' || a.grantee::regrole::text || ':' || a.privilege_type, ','
                    order by c.relname::text, a.grantee::regrole::text, a.privilege_type) into v_txt
    from pg_class c, aclexplode(c.relacl) a
   where c.oid = any (v_tablas_d1) and a.grantee <> 'postgres'::regrole;
  if v_txt is distinct from
     'correcciones_jornada:authenticated:SELECT,jornadas:authenticated:SELECT,'
     || 'jornadas:propietario_rpc:SELECT,reasignaciones_vendedor:authenticated:SELECT' then
    raise exception 'reversión D-1: la ACL de las tablas de jornadas no es la que dejó D-1: %', v_txt;
  end if;
  select string_agg(t.attrelid::regclass::text || '.' || t.attname::text || ':' || p.p, ','
                    order by t.attrelid::regclass::text, t.attname::text, p.p) into v_txt
    from pg_attribute t,
         (values ('INSERT'), ('UPDATE'), ('SELECT'), ('REFERENCES')) p (p)
   where t.attrelid = any (v_tablas_d1) and t.attnum > 0 and not t.attisdropped
     and has_column_privilege('propietario_rpc', t.attrelid, t.attname, p.p)
     and not has_table_privilege('propietario_rpc', t.attrelid, p.p);
  if v_txt is distinct from
     'correcciones_jornada.actor_id:INSERT,correcciones_jornada.camion_anterior_id:INSERT,'
     || 'correcciones_jornada.camion_nuevo_id:INSERT,correcciones_jornada.empresa_id:INSERT,'
     || 'correcciones_jornada.fecha_anterior:INSERT,correcciones_jornada.fecha_nueva:INSERT,'
     || 'correcciones_jornada.jornada_id:INSERT,correcciones_jornada.motivo:INSERT,'
     || 'correcciones_jornada.operacion_id:INSERT,'
     || 'jornadas.abierta_por:INSERT,jornadas.camion_id:INSERT,jornadas.camion_id:UPDATE,'
     || 'jornadas.empresa_id:INSERT,jornadas.estado:INSERT,jornadas.estado:UPDATE,'
     || 'jornadas.fecha:INSERT,jornadas.fecha:UPDATE,jornadas.operacion_apertura_id:INSERT,'
     || 'jornadas.vendedor_id:INSERT,jornadas.vendedor_id:UPDATE,'
     || 'reasignaciones_vendedor.actor_id:INSERT,reasignaciones_vendedor.empresa_id:INSERT,'
     || 'reasignaciones_vendedor.jornada_id:INSERT,reasignaciones_vendedor.operacion_id:INSERT,'
     || 'reasignaciones_vendedor.vendedor_anterior_id:INSERT,reasignaciones_vendedor.vendedor_nuevo_id:INSERT' then
    raise exception 'reversión D-1: los privilegios por columna de propietario_rpc no son los que dejó D-1: %', v_txt;
  end if;

  -- D-2 debe seguir presente y no se toca.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'perfiles'
                  and policyname = 'perfiles_select_empresa_lector')
     or to_regclass('privado.perfiles_empresa_gestion') is null
     or to_regprocedure('privado.empresa_gestion_actual()') is null then
    raise exception 'reversión D-1: faltan objetos de D-2; estado inesperado';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Reversión en orden inverso (sin CASCADE)
-- ---------------------------------------------------------------------------
-- 2.1 Historiales y policies de las tablas nuevas (los DROP TABLE se llevan sus
--     policies, constraints e índices propios).
drop table public.correcciones_jornada;
drop table public.reasignaciones_vendedor;

-- 2.2 Policies de Stock restauradas a su texto original (20261025033454), antes
--     de soltar jornadas: las versiones de D-1 dependen de esa tabla.
alter policy operaciones_insert_propietario_rpc
  on public.operaciones
  with check (
    actor_id = (select privado.usuario_actual())
    and tipo in ('ingreso', 'a_cuarentena', 'merma')
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = operaciones.empresa_id
        and p.usuario_id = operaciones.actor_id
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
  );

alter policy movimientos_stock_insert_propietario_rpc
  on public.movimientos_stock
  with check (
    actor_id = (select privado.usuario_actual())
    and tipo_movimiento in ('ingreso', 'a_cuarentena', 'merma')
    and exists (
      select 1
      from public.perfiles p
      where p.empresa_id = movimientos_stock.empresa_id
        and p.usuario_id = movimientos_stock.actor_id
        and p.activo
        and p.rol in ('dueno', 'encargado')
    )
    and exists (
      select 1
      from public.operaciones o
      where o.id = movimientos_stock.operacion_id
        and o.empresa_id = movimientos_stock.empresa_id
        and o.actor_id = movimientos_stock.actor_id
        and o.tipo = movimientos_stock.tipo_movimiento
    )
    and (
      (tipo_movimiento = 'ingreso'
        and ubicacion_origen_id is null
        and exists (select 1 from public.ubicaciones d
                     where d.id = movimientos_stock.ubicacion_destino_id
                       and d.empresa_id = movimientos_stock.empresa_id
                       and d.tipo = 'deposito'))
      or (tipo_movimiento = 'a_cuarentena'
        and exists (select 1 from public.ubicaciones o
                     where o.id = movimientos_stock.ubicacion_origen_id
                       and o.empresa_id = movimientos_stock.empresa_id
                       and o.tipo = 'deposito')
        and exists (select 1 from public.ubicaciones d
                     where d.id = movimientos_stock.ubicacion_destino_id
                       and d.empresa_id = movimientos_stock.empresa_id
                       and d.tipo = 'cuarentena'))
      or (tipo_movimiento = 'merma'
        and ubicacion_destino_id is null
        and exists (select 1 from public.ubicaciones o
                     where o.id = movimientos_stock.ubicacion_origen_id
                       and o.empresa_id = movimientos_stock.empresa_id
                       and o.tipo = 'deposito'))
    )
  );

-- 2.3 movimientos_stock: restricciones, índices y columna de D-1.
alter table public.movimientos_stock drop constraint movimientos_stock_operacion_referencia_fk;
drop index public.movimientos_stock_operacion_producto_unica;
drop index public.movimientos_stock_jornada_idx;
alter table public.movimientos_stock drop constraint movimientos_stock_jornada_por_tipo;
alter table public.movimientos_stock drop constraint movimientos_stock_jornada_fk;

alter table public.movimientos_stock drop constraint movimientos_stock_motivo_por_tipo;
alter table public.movimientos_stock add constraint movimientos_stock_motivo_por_tipo
  check (
    (tipo_movimiento = 'ingreso' and motivo_codigo is null)
    or (tipo_movimiento = 'a_cuarentena' and motivo_codigo is null and motivo is not null)
    or (tipo_movimiento = 'merma' and motivo_codigo is not null
        and (motivo_codigo <> 'otro' or motivo is not null)));

alter table public.movimientos_stock drop constraint movimientos_stock_forma_por_tipo;
alter table public.movimientos_stock add constraint movimientos_stock_forma_por_tipo
  check (
    (tipo_movimiento = 'ingreso'
      and ubicacion_origen_id is null and ubicacion_destino_id is not null)
    or (tipo_movimiento = 'a_cuarentena'
      and ubicacion_origen_id is not null and ubicacion_destino_id is not null)
    or (tipo_movimiento = 'merma'
      and ubicacion_origen_id is not null and ubicacion_destino_id is null));

alter table public.movimientos_stock drop constraint movimientos_stock_tipo_valido;
alter table public.movimientos_stock add constraint movimientos_stock_tipo_valido
  check (tipo_movimiento in ('ingreso', 'a_cuarentena', 'merma'));

alter table public.movimientos_stock drop column jornada_id;

-- 2.4 operaciones: FK a jornadas, CHECK de D-1 y tipos restaurados.
alter table public.operaciones drop constraint operaciones_jornada_por_tipo;
alter table public.operaciones drop constraint operaciones_jornada_fk;

alter table public.operaciones drop constraint operaciones_tipo_valido;
alter table public.operaciones add constraint operaciones_tipo_valido
  check (tipo in ('ingreso', 'a_cuarentena', 'merma'));

-- 2.5 jornadas (su FK de apertura depende de operaciones_referencia_apertura).
drop table public.jornadas;

-- 2.6 Destinos de referencia de operaciones y la columna.
alter table public.operaciones drop constraint operaciones_referencia_unica;
alter table public.operaciones drop constraint operaciones_referencia_apertura;
alter table public.operaciones drop column jornada_id;

-- La columna eliminada se lleva su privilegio por columna (INSERT de
-- propietario_rpc sobre jornada_id) en operaciones y movimientos_stock.

-- ---------------------------------------------------------------------------
-- 3. Verificación: el esquema vuelve a ser el de Stock + D-2, sin residuos
-- ---------------------------------------------------------------------------
do $$
declare
  v_txt text;
begin
  if to_regclass('public.jornadas') is not null
     or to_regclass('public.reasignaciones_vendedor') is not null
     or to_regclass('public.correcciones_jornada') is not null
     or exists (select 1 from pg_attribute
                 where attrelid in ('public.operaciones'::regclass, 'public.movimientos_stock'::regclass)
                   and attname = 'jornada_id' and not attisdropped) then
    raise exception 'reversión D-1: quedan objetos de D-1';
  end if;

  select string_agg(conname::text || ':' || pg_get_constraintdef(oid), '|' order by conname::text collate "C") into v_txt
    from pg_constraint where conrelid = 'public.operaciones'::regclass;
  if v_txt is distinct from
     'operaciones_actor_fk:FOREIGN KEY (empresa_id, actor_id) REFERENCES perfiles(empresa_id, usuario_id) ON DELETE RESTRICT'
     || '|operaciones_empresa_id_fkey:FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE RESTRICT'
     || '|operaciones_empresa_id_unico:UNIQUE (empresa_id, id)'
     || '|operaciones_huella_sha256:CHECK ((huella ~ ''^[0-9a-f]{64}$''::text))'
     || '|operaciones_idempotencia_unica:UNIQUE (empresa_id, actor_id, idempotency_key)'
     || '|operaciones_pkey:PRIMARY KEY (id)'
     || '|operaciones_tipo_valido:CHECK ((tipo = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text])))' then
    raise exception 'reversión D-1: las restricciones de operaciones no coinciden con Stock: %', v_txt;
  end if;

  select string_agg(conname::text, ',' order by conname::text collate "C") into v_txt
    from pg_constraint where conrelid = 'public.movimientos_stock'::regclass;
  if v_txt is distinct from
     'movimientos_stock_actor_fk,movimientos_stock_cantidad_positiva,movimientos_stock_destino_fk,'
     || 'movimientos_stock_empresa_id_fkey,movimientos_stock_empresa_id_unico,movimientos_stock_extremo_requerido,'
     || 'movimientos_stock_extremos_distintos,movimientos_stock_forma_por_tipo,movimientos_stock_motivo_codigo_valido,'
     || 'movimientos_stock_motivo_normalizado,movimientos_stock_motivo_por_tipo,movimientos_stock_operacion_fk,'
     || 'movimientos_stock_origen_fk,movimientos_stock_pkey,movimientos_stock_producto_fk,movimientos_stock_tipo_valido' then
    raise exception 'reversión D-1: las restricciones de movimientos_stock no coinciden con Stock: %', v_txt;
  end if;

  if (select pg_get_constraintdef(oid) from pg_constraint
       where conrelid = 'public.movimientos_stock'::regclass and conname = 'movimientos_stock_tipo_valido')
       is distinct from
       'CHECK ((tipo_movimiento = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text])))'
     or (select pg_get_constraintdef(oid) from pg_constraint
          where conrelid = 'public.movimientos_stock'::regclass and conname = 'movimientos_stock_forma_por_tipo')
          is distinct from
          'CHECK ((((tipo_movimiento = ''ingreso''::text) AND (ubicacion_origen_id IS NULL) AND (ubicacion_destino_id IS NOT NULL)) OR ((tipo_movimiento = ''a_cuarentena''::text) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NOT NULL)) OR ((tipo_movimiento = ''merma''::text) AND (ubicacion_origen_id IS NOT NULL) AND (ubicacion_destino_id IS NULL))))'
     or (select pg_get_constraintdef(oid) from pg_constraint
          where conrelid = 'public.movimientos_stock'::regclass and conname = 'movimientos_stock_motivo_por_tipo')
          is distinct from
          'CHECK ((((tipo_movimiento = ''ingreso''::text) AND (motivo_codigo IS NULL)) OR ((tipo_movimiento = ''a_cuarentena''::text) AND (motivo_codigo IS NULL) AND (motivo IS NOT NULL)) OR ((tipo_movimiento = ''merma''::text) AND (motivo_codigo IS NOT NULL) AND ((motivo_codigo <> ''otro''::text) OR (motivo IS NOT NULL)))))' then
    raise exception 'reversión D-1: las restricciones de movimientos_stock no recuperaron su definición de Stock';
  end if;

  select string_agg(c.relname::text, ',' order by c.relname::text collate "C") into v_txt
    from pg_index i join pg_class c on c.oid = i.indexrelid
   where i.indrelid = 'public.movimientos_stock'::regclass;
  if v_txt is distinct from
     'movimientos_stock_destino_idx,movimientos_stock_empresa_id_unico,movimientos_stock_operacion_unitaria_unica,'
     || 'movimientos_stock_origen_idx,movimientos_stock_pkey' then
    raise exception 'reversión D-1: los índices de movimientos_stock no coinciden con Stock: %', v_txt;
  end if;

  if pg_get_indexdef('public.movimientos_stock_operacion_unitaria_unica'::regclass)
     is distinct from
     'CREATE UNIQUE INDEX movimientos_stock_operacion_unitaria_unica ON public.movimientos_stock USING btree (empresa_id, operacion_id) WHERE (tipo_movimiento = ANY (ARRAY[''ingreso''::text, ''a_cuarentena''::text, ''merma''::text]))' then
    raise exception 'reversión D-1: D7 fue alterado';
  end if;

  -- Policies de Stock: sin rastro de jornadas y con las formas originales.
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename in ('operaciones', 'movimientos_stock')
                and (coalesce(with_check, '') ~* 'jornada' or coalesce(qual, '') ~* 'jornada'))
     or (select with_check !~ 'deposito' or with_check !~ 'cuarentena' or with_check !~ 'a_cuarentena'
                or with_check !~ 'merma' or with_check !~ 'o\.tipo = movimientos_stock\.tipo_movimiento'
         from pg_policies where policyname = 'movimientos_stock_insert_propietario_rpc') then
    raise exception 'reversión D-1: las policies de Stock no recuperaron su texto original';
  end if;

  -- Privilegios: propietario_rpc vuelve a las columnas de Stock.
  if has_column_privilege('propietario_rpc', 'public.operaciones', 'tipo', 'INSERT') is not true
     or has_any_column_privilege('propietario_rpc', 'public.operaciones', 'UPDATE')
     or has_any_column_privilege('propietario_rpc', 'public.movimientos_stock', 'UPDATE')
     or has_any_column_privilege('service_role', 'public.operaciones', 'SELECT, INSERT, UPDATE, REFERENCES')
     or has_any_column_privilege('service_role', 'public.movimientos_stock', 'SELECT, INSERT, UPDATE, REFERENCES') then
    raise exception 'reversión D-1: privilegios de operaciones o movimientos_stock fuera de Stock';
  end if;

  -- D-2 intacta.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'perfiles'
                  and policyname = 'perfiles_select_empresa_lector')
     or to_regclass('privado.perfiles_empresa_gestion') is null
     or to_regprocedure('privado.empresa_gestion_actual()') is null then
    raise exception 'reversión D-1: objetos de D-2 alterados';
  end if;
end $$;

commit;
