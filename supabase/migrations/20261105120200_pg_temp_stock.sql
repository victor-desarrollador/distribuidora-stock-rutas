-- A3 — Endurecimiento pg_temp de las RPC de Stock (plan de remediación pg_temp,
-- alternativa A; ADR-001 §17.1). Validación exclusivamente local/staging.
-- Prohibido aplicar en producción.
--
-- Defecto (hallazgo ALTO heredado): con search_path = '' PostgreSQL busca pg_temp
-- ANTES que pg_catalog para tipos y relaciones no calificados. Estas tres RPC
-- declaran variables «uuid», «uuid[]» y «text» sin esquema y usan casts «::text»
-- en la huella de idempotencia y en la clave del advisory lock: un dominio
-- pg_temp.uuid / pg_temp.text creado por una sesión que puede asumir
-- authenticated (TEMP por PUBLIC) ejecuta su CHECK como propietario_rpc, dentro
-- de operaciones que escriben operaciones y movimientos_stock.
--
-- Cambio: ÚNICAMENTE 43 calificaciones («uuid» → «pg_catalog.uuid», «text» →
-- «pg_catalog.text»):
--   registrar_ingreso (11: 9 declaraciones + 2 casts de la huella);
--   mover_a_cuarentena (16: 10 declaraciones + 3 casts de la huella + 3 del lock);
--   registrar_merma (16: 10 declaraciones + 3 casts de la huella + 3 del lock).
-- «bigint» y «boolean» son palabras clave y resuelven siempre a pg_catalog. El
-- cast a pg_catalog.text es el mismo tipo (mismo oid): la huella v1 y la clave
-- del lock no cambian, y los replays de operaciones anteriores siguen
-- coincidiendo.
--
-- Los cuerpos nuevos están escritos explícitamente abajo (texto revisable). Dos
-- cuerpos vigentes ya contienen calificaciones pg_catalog. de funciones
-- (current_setting, pg_advisory_xact_lock, hashtextextended), así que la
-- equivalencia mecánica revierte sólo «pg_catalog.uuid» y «pg_catalog.text»
-- (ausentes en los cuerpos vigentes) y exige que la cantidad de «pg_catalog.»
-- crezca exactamente en las calificaciones previstas. Se verifica que pg_proc
-- (salvo prosrc), las dependencias y el resto de las funciones de public y
-- privado queden idénticos.
--
-- Exige A1 (usuario_actual con SHA-256 2ab0212d…). Incorpora los controles
-- A1-B01 (check_function_bodies = on) y A1-B02 (topología completa de
-- propietario_rpc) ya aplicados en A2.
--
-- Alcance: NO cierra la vulnerabilidad global. Queda B1 (abrir_jornada y
-- reasignar_vendedor, sobre el apilado de jornadas).
--
-- Resolución de nombres, SQL dinámico, CREATE transitorio, SET LOCAL ROLE y
-- atomicidad: idéntico a A1/A2 (un único bloque DO; search_path
-- 'pg_catalog, pg_temp' fijado en la primera sentencia y restaurado al final;
-- format con %L).
--
-- Sin cambios de grants permanentes, RLS, tablas, roles, códigos de error,
-- huellas ni reglas de negocio.

do $mig$
declare
  -- Sin inicializadores: nada se evalúa antes de fijar el search_path controlado.
  v_search_path_previo pg_catalog.text;
  v_firmas pg_catalog.text[];
  v_cabeceras pg_catalog.text[];
  v_hash_previo pg_catalog.text[];
  v_hash_nuevo pg_catalog.text[];
  v_cantidad pg_catalog.int4[];
  v_previas pg_catalog.int4[];
  v_cuerpos pg_catalog.text[];
  v_oids pg_catalog.oid[];
  v_nombres pg_catalog.text[];
  v_manifiesto_previo pg_catalog.text;
  v_manifiesto_nuevo pg_catalog.text;
  v_manifiesto pg_catalog.text;
  v_distribucion pg_catalog.text;
  v_membresias pg_catalog.text;
  v_foto_cambian pg_catalog.jsonb;
  v_foto_resto pg_catalog.jsonb;
  v_dependencias pg_catalog.text;
  v_acl_privado pg_catalog.text;
  v_definer pg_catalog.text;
  v_oid pg_catalog.oid;
  v_src pg_catalog.text;
  i pg_catalog.int4;
begin
  -- -------------------------------------------------------------------------
  -- search_path controlado (primera sentencia; se restaura al final)
  -- -------------------------------------------------------------------------
  v_search_path_previo := pg_catalog.current_setting('search_path');
  perform pg_catalog.set_config('search_path', 'pg_catalog, pg_temp', true);

  if pg_catalog.current_setting('search_path') operator(pg_catalog.<>) 'pg_catalog, pg_temp' then
    raise exception 'pg_temp A3: no se pudo fijar el search_path controlado';
  end if;

  -- -------------------------------------------------------------------------
  -- Constantes (asignadas con el search_path ya controlado)
  -- -------------------------------------------------------------------------
  -- Funciones que cambian: firma calificada, cabecera DDL (firma, retorno,
  -- lenguaje, volatilidad y SECURITY idénticos a los vigentes), SHA-256 del
  -- cuerpo vigente y del nuevo, calificaciones pg_catalog. previas, cantidad de
  -- calificaciones nuevas y cuerpo nuevo.
  -- 1. privado.registrar_ingreso(uuid,uuid,integer,text): 11 calificaciones (0 previas)
  v_firmas[1] := 'privado.registrar_ingreso(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)';
  v_cabeceras[1] := 'privado.registrar_ingreso(p_idempotency_key pg_catalog.uuid, p_producto_id pg_catalog.uuid, p_cantidad pg_catalog.int4, p_motivo pg_catalog.text default null::pg_catalog.text) returns pg_catalog.uuid language plpgsql volatile security definer';
  v_hash_previo[1] := 'a809e6a4a7ee07e06bdcc0d9c4a97099f8c614abd19e3f425fa75c0a52cb9e78';
  v_hash_nuevo[1] := 'b87c32fb38443dbe57abfc19ddce449a0d05d2c567a499165c09ba6a2ef9ece6';
  v_previas[1] := 0;
  v_cantidad[1] := 11;
  v_cuerpos[1] := $c1$
declare
  v_uid pg_catalog.uuid := privado.usuario_actual();
  v_empresa pg_catalog.uuid;
  v_rol pg_catalog.text;
  v_activo boolean;
  v_motivo pg_catalog.text := nullif(btrim(p_motivo), '');
  v_huella pg_catalog.text;
  v_operacion pg_catalog.uuid;
  v_previa_tipo pg_catalog.text;
  v_previa_huella pg_catalog.text;
  v_producto_activo boolean;
  v_depositos pg_catalog.uuid[];
begin
  -- 1-4. Identidad, perfil activo, empresa y rol desde perfiles.
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'stock_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if v_empresa is null or v_activo is not true
     or v_rol not in ('dueno', 'encargado') then
    raise exception using errcode = 'PT403', message = 'stock_no_autorizado';
  end if;

  -- 5-7. Estructura básica del pedido.
  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'stock_clave_invalida';
  end if;

  if p_cantidad is null or p_cantidad <= 0 then
    raise exception using errcode = 'PT400', message = 'stock_cantidad_invalida';
  end if;

  if p_producto_id is null then
    raise exception using errcode = 'PT404', message = 'stock_producto_no_encontrado';
  end if;

  -- 8. Huella v1 sobre los parámetros ya normalizados.
  v_huella := encode(
    sha256(convert_to(
      'v1|ingreso|' || p_producto_id::pg_catalog.text || '|' || p_cantidad::pg_catalog.text || '|'
        || case when v_motivo is null then '-' else '+' || v_motivo end,
      'UTF8')),
    'hex');

  -- 9-10. Reserva de la clave o replay. Un ingreso concurrente con la misma
  -- clave espera acá a que el primero confirme o revierta.
  begin
    insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values (v_empresa, v_uid, 'ingreso', p_idempotency_key, v_huella)
    on conflict (empresa_id, actor_id, idempotency_key) do nothing
    returning id into v_operacion;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end;

  if v_operacion is null then
    select o.id, o.tipo, o.huella
      into v_operacion, v_previa_tipo, v_previa_huella
      from public.operaciones o
     where o.empresa_id = v_empresa
       and o.actor_id = v_uid
       and o.idempotency_key = p_idempotency_key;

    if v_previa_tipo = 'ingreso' and v_previa_huella = v_huella then
      return v_operacion;
    end if;

    raise exception using errcode = 'PT409', message = 'stock_conflicto_idempotencia';
  end if;

  -- 11. Producto de la empresa (otra empresa = inexistente) y activo.
  select pr.activo into v_producto_activo
    from public.productos pr
   where pr.id = p_producto_id
     and pr.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'stock_producto_no_encontrado';
  end if;

  if v_producto_activo is not true then
    raise exception using errcode = 'PT409', message = 'stock_producto_inactivo';
  end if;

  -- 12. Depósito resuelto en el servidor: exactamente uno (fail-closed).
  select array_agg(u.id) into v_depositos
    from public.ubicaciones u
   where u.empresa_id = v_empresa
     and u.tipo = 'deposito';

  if coalesce(cardinality(v_depositos), 0) <> 1 then
    raise exception using errcode = 'PT500', message = 'stock_ubicacion_no_configurada';
  end if;

  -- 13. Un único movimiento: exterior → depósito.
  begin
    insert into public.movimientos_stock (
      empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
      ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo
    )
    values (
      v_empresa, v_operacion, 'ingreso', p_producto_id, p_cantidad,
      null, v_depositos[1], v_uid, v_motivo
    );
  exception
    when unique_violation or check_violation or foreign_key_violation
         or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end;

  -- 14. Resultado estable (también en el replay).
  return v_operacion;
end $c1$;

  -- 2. privado.mover_a_cuarentena(uuid,uuid,uuid,integer,text): 16 calificaciones (3 previas)
  v_firmas[2] := 'privado.mover_a_cuarentena(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)';
  v_cabeceras[2] := 'privado.mover_a_cuarentena(p_idempotency_key pg_catalog.uuid, p_producto_id pg_catalog.uuid, p_ubicacion_origen_id pg_catalog.uuid, p_cantidad pg_catalog.int4, p_motivo pg_catalog.text) returns pg_catalog.uuid language plpgsql volatile security definer';
  v_hash_previo[2] := '6b0e2159afbbde32dff90b7b51c6408ed4a9c2c6a94fd430701db38b94c0e99e';
  v_hash_nuevo[2] := '1e27e5ae6d3067466ca679025d2e31b0384a8f9e5a69f70f856292a6ffbbb380';
  v_previas[2] := 3;
  v_cantidad[2] := 16;
  v_cuerpos[2] := $c2$
declare
  v_uid pg_catalog.uuid;
  v_empresa pg_catalog.uuid;
  v_rol pg_catalog.text;
  v_activo boolean;
  v_motivo pg_catalog.text := nullif(btrim(p_motivo), '');
  v_huella pg_catalog.text;
  v_operacion pg_catalog.uuid;
  v_previa_tipo pg_catalog.text;
  v_previa_huella pg_catalog.text;
  v_producto_activo boolean;
  v_origen_tipo pg_catalog.text;
  v_cuarentenas pg_catalog.uuid[];
  v_saldo bigint;
begin
  -- P13-stock: el lock sólo serializa el saldo bajo READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end if;

  -- Identidad, perfil activo, empresa y rol desde perfiles (D1).
  v_uid := privado.usuario_actual();
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'stock_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if v_empresa is null or v_activo is not true
     or v_rol not in ('dueno', 'encargado') then
    raise exception using errcode = 'PT403', message = 'stock_no_autorizado';
  end if;

  -- Estructura básica del pedido.
  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'stock_clave_invalida';
  end if;

  if p_cantidad is null or p_cantidad <= 0 then
    raise exception using errcode = 'PT400', message = 'stock_cantidad_invalida';
  end if;

  if v_motivo is null then
    raise exception using errcode = 'PT400', message = 'stock_motivo_invalido';
  end if;

  if p_producto_id is null then
    raise exception using errcode = 'PT404', message = 'stock_producto_no_encontrado';
  end if;

  if p_ubicacion_origen_id is null then
    raise exception using errcode = 'PT404', message = 'stock_ubicacion_no_encontrada';
  end if;

  -- Huella v1 (el destino se deriva en el servidor y no integra la huella).
  v_huella := encode(
    sha256(convert_to(
      'v1|a_cuarentena|' || p_producto_id::pg_catalog.text || '|' || p_ubicacion_origen_id::pg_catalog.text
        || '|' || p_cantidad::pg_catalog.text || '|'
        || case when v_motivo is null then '-' else '+' || v_motivo end,
      'UTF8')),
    'hex');

  -- Reserva de la clave o replay (antes de cualquier validación mutable).
  begin
    insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values (v_empresa, v_uid, 'a_cuarentena', p_idempotency_key, v_huella)
    on conflict (empresa_id, actor_id, idempotency_key) do nothing
    returning id into v_operacion;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end;

  if v_operacion is null then
    select o.id, o.tipo, o.huella
      into v_operacion, v_previa_tipo, v_previa_huella
      from public.operaciones o
     where o.empresa_id = v_empresa
       and o.actor_id = v_uid
       and o.idempotency_key = p_idempotency_key;

    if v_previa_tipo = 'a_cuarentena' and v_previa_huella = v_huella then
      return v_operacion;
    end if;

    raise exception using errcode = 'PT409', message = 'stock_conflicto_idempotencia';
  end if;

  -- Producto de la empresa (otra empresa = inexistente) y activo.
  select pr.activo into v_producto_activo
    from public.productos pr
   where pr.id = p_producto_id
     and pr.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'stock_producto_no_encontrado';
  end if;

  if v_producto_activo is not true then
    raise exception using errcode = 'PT409', message = 'stock_producto_inactivo';
  end if;

  -- Origen: ubicación propia y de tipo depósito (D3).
  select u.tipo into v_origen_tipo
    from public.ubicaciones u
   where u.id = p_ubicacion_origen_id
     and u.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'stock_ubicacion_no_encontrada';
  end if;

  if v_origen_tipo <> 'deposito' then
    raise exception using errcode = 'PT400', message = 'stock_origen_invalido';
  end if;

  -- Destino: la única cuarentena de la empresa, resuelta en el servidor.
  select array_agg(u.id) into v_cuarentenas
    from public.ubicaciones u
   where u.empresa_id = v_empresa
     and u.tipo = 'cuarentena';

  if coalesce(cardinality(v_cuarentenas), 0) <> 1 then
    raise exception using errcode = 'PT500', message = 'stock_ubicacion_no_configurada';
  end if;

  -- Débito serializado por empresa + origen + producto.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'stock:' || v_empresa::pg_catalog.text || ':' || p_ubicacion_origen_id::pg_catalog.text || ':' || p_producto_id::pg_catalog.text, 0));

  select coalesce(sum(case when m.ubicacion_destino_id = p_ubicacion_origen_id
                           then m.cantidad::bigint
                           else -m.cantidad::bigint end), 0)
    into v_saldo
    from public.movimientos_stock m
   where m.empresa_id = v_empresa
     and m.producto_id = p_producto_id
     and (m.ubicacion_destino_id = p_ubicacion_origen_id
          or m.ubicacion_origen_id = p_ubicacion_origen_id);

  if v_saldo < p_cantidad then
    raise exception using errcode = 'PT409', message = 'stock_insuficiente';
  end if;

  begin
    insert into public.movimientos_stock (
      empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
      ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo
    )
    values (
      v_empresa, v_operacion, 'a_cuarentena', p_producto_id, p_cantidad,
      p_ubicacion_origen_id, v_cuarentenas[1], v_uid, v_motivo
    );
  exception
    when unique_violation or check_violation or foreign_key_violation
         or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end;

  return v_operacion;
end $c2$;

  -- 3. privado.registrar_merma(uuid,uuid,uuid,integer,text,text): 16 calificaciones (3 previas)
  v_firmas[3] := 'privado.registrar_merma(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text, pg_catalog.text)';
  v_cabeceras[3] := 'privado.registrar_merma(p_idempotency_key pg_catalog.uuid, p_producto_id pg_catalog.uuid, p_ubicacion_origen_id pg_catalog.uuid, p_cantidad pg_catalog.int4, p_motivo_codigo pg_catalog.text, p_motivo pg_catalog.text default null::pg_catalog.text) returns pg_catalog.uuid language plpgsql volatile security definer';
  v_hash_previo[3] := 'ffb6ab8572c74292aeb9ae49cfb2fc33114ffec48c12b7be1e40e5146f4eb3ca';
  v_hash_nuevo[3] := '767897feea86d00edfba693f5291e043096800c1605a43ad6ceca8316f846322';
  v_previas[3] := 3;
  v_cantidad[3] := 16;
  v_cuerpos[3] := $c3$
declare
  v_uid pg_catalog.uuid;
  v_empresa pg_catalog.uuid;
  v_rol pg_catalog.text;
  v_activo boolean;
  v_codigo pg_catalog.text := btrim(p_motivo_codigo);
  v_motivo pg_catalog.text := nullif(btrim(p_motivo), '');
  v_huella pg_catalog.text;
  v_operacion pg_catalog.uuid;
  v_previa_tipo pg_catalog.text;
  v_previa_huella pg_catalog.text;
  v_producto_activo boolean;
  v_origen_tipo pg_catalog.text;
  v_saldo bigint;
begin
  -- P13-stock: el lock sólo serializa el saldo bajo READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end if;

  v_uid := privado.usuario_actual();
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'stock_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if v_empresa is null or v_activo is not true
     or v_rol not in ('dueno', 'encargado') then
    raise exception using errcode = 'PT403', message = 'stock_no_autorizado';
  end if;

  if p_idempotency_key is null then
    raise exception using errcode = 'PT400', message = 'stock_clave_invalida';
  end if;

  if p_cantidad is null or p_cantidad <= 0 then
    raise exception using errcode = 'PT400', message = 'stock_cantidad_invalida';
  end if;

  -- Código exacto del catálogo de Blueprint §7.7 (D5); texto obligatorio sólo
  -- para 'otro'.
  if v_codigo is null
     or v_codigo not in ('vencido', 'roto_danado', 'mal_estado',
                         'error_pedido', 'cambio', 'otro')
     or (v_codigo = 'otro' and v_motivo is null) then
    raise exception using errcode = 'PT400', message = 'stock_motivo_invalido';
  end if;

  if p_producto_id is null then
    raise exception using errcode = 'PT404', message = 'stock_producto_no_encontrado';
  end if;

  if p_ubicacion_origen_id is null then
    raise exception using errcode = 'PT404', message = 'stock_ubicacion_no_encontrada';
  end if;

  v_huella := encode(
    sha256(convert_to(
      'v1|merma|' || p_producto_id::pg_catalog.text || '|' || p_ubicacion_origen_id::pg_catalog.text
        || '|' || p_cantidad::pg_catalog.text || '|' || v_codigo || '|'
        || case when v_motivo is null then '-' else '+' || v_motivo end,
      'UTF8')),
    'hex');

  begin
    insert into public.operaciones (empresa_id, actor_id, tipo, idempotency_key, huella)
    values (v_empresa, v_uid, 'merma', p_idempotency_key, v_huella)
    on conflict (empresa_id, actor_id, idempotency_key) do nothing
    returning id into v_operacion;
  exception
    when unique_violation or check_violation or foreign_key_violation
         or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end;

  if v_operacion is null then
    select o.id, o.tipo, o.huella
      into v_operacion, v_previa_tipo, v_previa_huella
      from public.operaciones o
     where o.empresa_id = v_empresa
       and o.actor_id = v_uid
       and o.idempotency_key = p_idempotency_key;

    if v_previa_tipo = 'merma' and v_previa_huella = v_huella then
      return v_operacion;
    end if;

    raise exception using errcode = 'PT409', message = 'stock_conflicto_idempotencia';
  end if;

  select pr.activo into v_producto_activo
    from public.productos pr
   where pr.id = p_producto_id
     and pr.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'stock_producto_no_encontrado';
  end if;

  if v_producto_activo is not true then
    raise exception using errcode = 'PT409', message = 'stock_producto_inactivo';
  end if;

  -- Origen: ubicación propia y de tipo depósito (D3, D4).
  select u.tipo into v_origen_tipo
    from public.ubicaciones u
   where u.id = p_ubicacion_origen_id
     and u.empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'stock_ubicacion_no_encontrada';
  end if;

  if v_origen_tipo <> 'deposito' then
    raise exception using errcode = 'PT400', message = 'stock_origen_invalido';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'stock:' || v_empresa::pg_catalog.text || ':' || p_ubicacion_origen_id::pg_catalog.text || ':' || p_producto_id::pg_catalog.text, 0));

  select coalesce(sum(case when m.ubicacion_destino_id = p_ubicacion_origen_id
                           then m.cantidad::bigint
                           else -m.cantidad::bigint end), 0)
    into v_saldo
    from public.movimientos_stock m
   where m.empresa_id = v_empresa
     and m.producto_id = p_producto_id
     and (m.ubicacion_destino_id = p_ubicacion_origen_id
          or m.ubicacion_origen_id = p_ubicacion_origen_id);

  if v_saldo < p_cantidad then
    raise exception using errcode = 'PT409', message = 'stock_insuficiente';
  end if;

  begin
    insert into public.movimientos_stock (
      empresa_id, operacion_id, tipo_movimiento, producto_id, cantidad,
      ubicacion_origen_id, ubicacion_destino_id, actor_id, motivo, motivo_codigo
    )
    values (
      v_empresa, v_operacion, 'merma', p_producto_id, p_cantidad,
      p_ubicacion_origen_id, null, v_uid, v_motivo, v_codigo
    );
  exception
    when unique_violation or check_violation or foreign_key_violation
         or insufficient_privilege then
      raise exception using errcode = 'PT500', message = 'stock_error_interno';
  end;

  return v_operacion;
end $c3$;

  -- Las 4 funciones de privado alcanzadas o verificadas por A3.
  v_nombres := array['registrar_ingreso', 'mover_a_cuarentena', 'registrar_merma', 'usuario_actual'];

  -- Distribución exacta por esquema de esos nombres (implementaciones en
  -- privado y fachadas public de las 3 RPC; ningún otro homónimo).
  v_distribucion := 'mover_a_cuarentena:privado,public;registrar_ingreso:privado,public;registrar_merma:privado,public;usuario_actual:privado';

  -- Manifiesto exacto de las 4 funciones (una línea por función, ordenadas por
  -- firma): firma | owner | lenguaje | prokind | SECURITY DEFINER | leakproof |
  -- strict | retset | volatilidad | paralelismo | nargs | nargdefaults | tipo de
  -- retorno | nombres de argumentos | modos | support | costo | filas |
  -- proconfig | ACL ordenada | comentario | probin | prosqlbody nulo | SHA-256.
  v_manifiesto_previo :=
       'privado.mover_a_cuarentena(uuid,uuid,uuid,integer,text)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|5|0|uuid|{p_idempotency_key,p_producto_id,p_ubicacion_origen_id,p_cantidad,p_motivo}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|6b0e2159afbbde32dff90b7b51c6408ed4a9c2c6a94fd430701db38b94c0e99e' || E'\n'
    || 'privado.registrar_ingreso(uuid,uuid,integer,text)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|4|1|uuid|{p_idempotency_key,p_producto_id,p_cantidad,p_motivo}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|a809e6a4a7ee07e06bdcc0d9c4a97099f8c614abd19e3f425fa75c0a52cb9e78' || E'\n'
    || 'privado.registrar_merma(uuid,uuid,uuid,integer,text,text)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|6|1|uuid|{p_idempotency_key,p_producto_id,p_ubicacion_origen_id,p_cantidad,p_motivo_codigo,p_motivo}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|ffb6ab8572c74292aeb9ae49cfb2fc33114ffec48c12b7be1e40e5146f4eb3ca' || E'\n'
    || 'privado.usuario_actual()|propietario_rpc|sql|f|false|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96';
  v_manifiesto_nuevo := v_manifiesto_previo;
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, 'a809e6a4a7ee07e06bdcc0d9c4a97099f8c614abd19e3f425fa75c0a52cb9e78', 'b87c32fb38443dbe57abfc19ddce449a0d05d2c567a499165c09ba6a2ef9ece6');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, '6b0e2159afbbde32dff90b7b51c6408ed4a9c2c6a94fd430701db38b94c0e99e', '1e27e5ae6d3067466ca679025d2e31b0384a8f9e5a69f70f856292a6ffbbb380');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, 'ffb6ab8572c74292aeb9ae49cfb2fc33114ffec48c12b7be1e40e5146f4eb3ca', '767897feea86d00edfba693f5291e043096800c1605a43ad6ceca8316f846322');

  -- -------------------------------------------------------------------------
  -- Precondiciones de identidad, entorno y roles (fail-closed)
  -- -------------------------------------------------------------------------
  if current_user operator(pg_catalog.<>) 'postgres'
     or session_user operator(pg_catalog.<>) 'postgres' then
    raise exception 'pg_temp A3: la migración debe ejecutarse como postgres; actual: % / %',
      session_user, current_user;
  end if;

  -- A1-B01: los cuerpos se validan al crearlos, en este contexto controlado.
  if pg_catalog.current_setting('check_function_bodies') operator(pg_catalog.<>) 'on' then
    raise exception 'pg_temp A3: check_function_bodies debe estar activo';
  end if;

  -- P3 completo (incluye NOREPLICATION).
  if not exists (select 1 from pg_catalog.pg_roles r
                  where r.rolname = 'propietario_rpc'
                    and not r.rolsuper and not r.rolcanlogin and not r.rolbypassrls
                    and not r.rolcreatedb and not r.rolcreaterole and not r.rolreplication) then
    raise exception 'pg_temp A3: propietario_rpc ausente o con atributos fuera de P3';
  end if;

  -- A1-B02: topología de membresías. propietario_rpc no es miembro de ningún
  -- rol; sus únicos miembros son las dos filas de postgres: O-3 (SET sin
  -- INHERIT ni ADMIN, otorgada por postgres) y la automática de PostgreSQL 16+
  -- al crear el rol (ADMIN sin INHERIT ni SET, otorgada por un superusuario).
  if exists (select 1 from pg_catalog.pg_auth_members m
              where m.member = 'propietario_rpc'::pg_catalog.regrole) then
    raise exception 'pg_temp A3: propietario_rpc es miembro de otro rol';
  end if;

  select pg_catalog.string_agg(x.fila, ',' order by x.fila) into v_membresias
    from (select m.member::pg_catalog.regrole::pg_catalog.text
                 || '|' || m.admin_option::pg_catalog.text
                 || '|' || m.inherit_option::pg_catalog.text
                 || '|' || m.set_option::pg_catalog.text
                 || '|' || case when m.grantor operator(pg_catalog.=) 'postgres'::pg_catalog.regrole then 'postgres'
                                when g.rolsuper then 'superusuario'
                                else 'otro' end as fila
            from pg_catalog.pg_auth_members m
            join pg_catalog.pg_roles g on g.oid operator(pg_catalog.=) m.grantor
           where m.roleid = 'propietario_rpc'::pg_catalog.regrole) x;

  if v_membresias is distinct from
     'postgres|false|false|true|postgres,postgres|true|false|false|superusuario' then
    raise exception 'pg_temp A3: membresías de propietario_rpc fuera de lo aprobado (P3/O-3): %', v_membresias;
  end if;

  -- O-3 efectivo: postgres puede SET ROLE propietario_rpc sin heredar.
  if not pg_catalog.pg_has_role('postgres', 'propietario_rpc', 'SET')
     or pg_catalog.pg_has_role('postgres', 'propietario_rpc', 'USAGE') then
    raise exception 'pg_temp A3: la membresía postgres → propietario_rpc no es la de O-3';
  end if;

  if (select n.nspowner from pg_catalog.pg_namespace n where n.nspname = 'privado')
     is distinct from 'postgres'::pg_catalog.regrole then
    raise exception 'pg_temp A3: el esquema privado no es de postgres';
  end if;

  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'pg_temp A3: propietario_rpc ya tiene CREATE sobre privado';
  end if;

  if not pg_catalog.has_language_privilege('propietario_rpc', 'plpgsql', 'USAGE') then
    raise exception 'pg_temp A3: propietario_rpc no puede usar plpgsql';
  end if;

  -- Dependencia de A1: usuario_actual con los dos casts calificados.
  if (select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex')
        from pg_catalog.pg_proc p
       where p.oid = pg_catalog.to_regprocedure('privado.usuario_actual()'))
     is distinct from '2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96' then
    raise exception 'pg_temp A3: falta A1 (privado.usuario_actual() no tiene el cuerpo calificado)';
  end if;

  -- Firmas existentes.
  for i in 1 .. pg_catalog.array_length(v_firmas, 1) loop
    v_oid := pg_catalog.to_regprocedure(v_firmas[i]);
    if v_oid is null then
      raise exception 'pg_temp A3: falta la función %', v_firmas[i];
    end if;
    v_oids[i] := v_oid;
  end loop;

  if pg_catalog.array_length(v_oids, 1) operator(pg_catalog.<>) 3 then
    raise exception 'pg_temp A3: se esperaban 3 funciones a corregir';
  end if;

  -- Sin sobrecargas ni homónimos fuera de lo esperado, en ningún esquema.
  select pg_catalog.string_agg(x.proname::pg_catalog.text || ':' || x.esquemas, ';' order by x.proname)
    into v_manifiesto
    from (select p.proname,
                 pg_catalog.string_agg(n.nspname::pg_catalog.text, ',' order by n.nspname) as esquemas
            from pg_catalog.pg_proc p
            join pg_catalog.pg_namespace n on n.oid operator(pg_catalog.=) p.pronamespace
           where p.proname::pg_catalog.text operator(pg_catalog.=) any (v_nombres)
           group by p.proname) x;

  if v_manifiesto is distinct from v_distribucion then
    raise exception 'pg_temp A3: sobrecargas u homónimos fuera de lo esperado: %', v_manifiesto;
  end if;

  -- -------------------------------------------------------------------------
  -- Estado aprobado exacto, antes de cualquier cambio
  -- -------------------------------------------------------------------------
  select pg_catalog.string_agg(
           p.oid::pg_catalog.regprocedure::pg_catalog.text
           || '|' || p.proowner::pg_catalog.regrole::pg_catalog.text
           || '|' || l.lanname::pg_catalog.text
           || '|' || p.prokind::pg_catalog.text
           || '|' || p.prosecdef::pg_catalog.text
           || '|' || p.proleakproof::pg_catalog.text
           || '|' || p.proisstrict::pg_catalog.text
           || '|' || p.proretset::pg_catalog.text
           || '|' || p.provolatile::pg_catalog.text
           || '|' || p.proparallel::pg_catalog.text
           || '|' || p.pronargs::pg_catalog.text
           || '|' || p.pronargdefaults::pg_catalog.text
           || '|' || p.prorettype::pg_catalog.regtype::pg_catalog.text
           || '|' || coalesce(p.proargnames::pg_catalog.text, '-')
           || '|' || coalesce(p.proargmodes::pg_catalog.text, '-')
           || '|' || coalesce(nullif(p.prosupport::pg_catalog.oid, 0::pg_catalog.oid)::pg_catalog.text, '-')
           || '|' || p.procost::pg_catalog.text
           || '|' || p.prorows::pg_catalog.text
           || '|' || coalesce(p.proconfig::pg_catalog.text, '-')
           || '|' || coalesce(pg_catalog.array_to_string(array(
                        select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1), ','), '-')
           || '|' || coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '-')
           || '|' || coalesce(p.probin, '-')
           || '|' || (p.prosqlbody is null)::pg_catalog.text
           || '|' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex'),
           E'\n' order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
    into v_manifiesto
    from pg_catalog.pg_proc p
    join pg_catalog.pg_language l on l.oid = p.prolang
   where p.pronamespace = 'privado'::pg_catalog.regnamespace
     and p.proname::pg_catalog.text operator(pg_catalog.=) any (v_nombres);

  if v_manifiesto is distinct from v_manifiesto_previo then
    raise exception 'pg_temp A3: el estado de las funciones de Stock no es el aprobado (manifiesto)';
  end if;

  -- Fotos: pg_proc completo de public y privado (sin prosrc para las 3 que
  -- cambian), dependencias en las que participan las 3, ACL de privado y lista
  -- de SECURITY DEFINER.
  select pg_catalog.jsonb_object_agg(p.oid::pg_catalog.text,
           pg_catalog.to_jsonb(p) operator(pg_catalog.-) 'prosrc'::pg_catalog.text)
    into v_foto_cambian
    from pg_catalog.pg_proc p where p.oid operator(pg_catalog.=) any (v_oids);
  select pg_catalog.jsonb_object_agg(p.oid::pg_catalog.text, pg_catalog.to_jsonb(p))
    into v_foto_resto
    from pg_catalog.pg_proc p
   where p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace)
     and not (p.oid operator(pg_catalog.=) any (v_oids));
  select coalesce(pg_catalog.string_agg(
           d.classid::pg_catalog.text || ':' || d.objid::pg_catalog.text || ':' || d.objsubid::pg_catalog.text
           || '>' || d.refclassid::pg_catalog.text || ':' || d.refobjid::pg_catalog.text || ':'
           || d.refobjsubid::pg_catalog.text || ':' || d.deptype::pg_catalog.text,
           ',' order by d.classid, d.objid, d.objsubid, d.refclassid, d.refobjid, d.refobjsubid, d.deptype), '')
    into v_dependencias
    from pg_catalog.pg_depend d
   where (d.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass and d.objid operator(pg_catalog.=) any (v_oids))
      or (d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass and d.refobjid operator(pg_catalog.=) any (v_oids));
  select coalesce(n.nspacl::pg_catalog.text, '') into v_acl_privado
    from pg_catalog.pg_namespace n where n.nspname = 'privado';
  select pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::pg_catalog.text || '/'
                               || p.proowner::pg_catalog.regrole::pg_catalog.text, ','
                               order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
    into v_definer
    from pg_catalog.pg_proc p
   where p.prosecdef
     and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace);

  -- -------------------------------------------------------------------------
  -- Verificación de los cuerpos nuevos (antes de instalarlos)
  -- -------------------------------------------------------------------------
  -- Equivalencia: el cuerpo vigente no contiene «pg_catalog.uuid» ni
  -- «pg_catalog.text»; revirtiendo sólo esos dos tokens en el cuerpo nuevo se
  -- obtiene el vigente byte a byte, y la cantidad de «pg_catalog.» pasa de la
  -- previa a la previa más las calificaciones previstas.
  for i in 1 .. 3 loop
    select p.prosrc into v_src from pg_catalog.pg_proc p where p.oid = v_oids[i];
    if pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_src, 'UTF8')), 'hex')
         operator(pg_catalog.<>) v_hash_previo[i]
       or pg_catalog.strpos(v_src, 'pg_catalog.uuid') operator(pg_catalog.<>) 0
       or pg_catalog.strpos(v_src, 'pg_catalog.text') operator(pg_catalog.<>) 0
       or (pg_catalog.length(v_src) - pg_catalog.length(pg_catalog.replace(v_src, 'pg_catalog.', '')))
          / pg_catalog.length('pg_catalog.') operator(pg_catalog.<>) v_previas[i]
       or pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_cuerpos[i], 'UTF8')), 'hex')
         operator(pg_catalog.<>) v_hash_nuevo[i]
       or pg_catalog.replace(pg_catalog.replace(v_cuerpos[i], 'pg_catalog.uuid', 'uuid'),
                             'pg_catalog.text', 'text') is distinct from v_src
       or (pg_catalog.length(v_cuerpos[i])
           - pg_catalog.length(pg_catalog.replace(v_cuerpos[i], 'pg_catalog.', '')))
          / pg_catalog.length('pg_catalog.') operator(pg_catalog.<>) v_previas[i] + v_cantidad[i] then
      raise exception 'pg_temp A3: el cuerpo nuevo de % no es el vigente con las calificaciones previstas', v_firmas[i];
    end if;
  end loop;

  -- -------------------------------------------------------------------------
  -- Sustitución como owner técnico (O-3), con CREATE transitorio
  -- -------------------------------------------------------------------------
  grant create on schema privado to propietario_rpc;
  set local role propietario_rpc;

  if current_user operator(pg_catalog.<>) 'propietario_rpc'
     or pg_catalog.current_setting('search_path') operator(pg_catalog.<>) 'pg_catalog, pg_temp' then
    raise exception 'pg_temp A3: no se pudo actuar como propietario_rpc con el search_path controlado';
  end if;

  for i in 1 .. 3 loop
    execute pg_catalog.format(
      'create or replace function ' || v_cabeceras[i] || ' set search_path = %L as %L',
      '', v_cuerpos[i]);
  end loop;

  reset role;

  if current_user operator(pg_catalog.<>) 'postgres' then
    raise exception 'pg_temp A3: no se pudo volver a postgres';
  end if;

  revoke create on schema privado from propietario_rpc;

  -- -------------------------------------------------------------------------
  -- Verificación fail-closed del resultado
  -- -------------------------------------------------------------------------
  for i in 1 .. 3 loop
    if (select p.prosrc from pg_catalog.pg_proc p where p.oid = v_oids[i]) is distinct from v_cuerpos[i] then
      raise exception 'pg_temp A3: el cuerpo instalado de % no es el previsto', v_firmas[i];
    end if;
  end loop;

  -- pg_proc idéntico salvo prosrc (mismo oid, owner, ACL, SECURITY, search_path,
  -- volatilidad, argumentos, valores por defecto…) y el resto de las funciones
  -- de public y privado sin ningún cambio.
  if (select pg_catalog.jsonb_object_agg(p.oid::pg_catalog.text,
              pg_catalog.to_jsonb(p) operator(pg_catalog.-) 'prosrc'::pg_catalog.text)
        from pg_catalog.pg_proc p where p.oid operator(pg_catalog.=) any (v_oids))
       is distinct from v_foto_cambian
     or (select pg_catalog.jsonb_object_agg(p.oid::pg_catalog.text, pg_catalog.to_jsonb(p))
           from pg_catalog.pg_proc p
          where p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace)
            and not (p.oid operator(pg_catalog.=) any (v_oids)))
       is distinct from v_foto_resto then
    raise exception 'pg_temp A3: cambió un atributo de pg_proc distinto del cuerpo, u otra función';
  end if;

  -- Mismas dependencias (tipos de argumentos y retorno, lenguaje, esquema y
  -- quienes dependen de estas funciones).
  if (select coalesce(pg_catalog.string_agg(
              d.classid::pg_catalog.text || ':' || d.objid::pg_catalog.text || ':' || d.objsubid::pg_catalog.text
              || '>' || d.refclassid::pg_catalog.text || ':' || d.refobjid::pg_catalog.text || ':'
              || d.refobjsubid::pg_catalog.text || ':' || d.deptype::pg_catalog.text,
              ',' order by d.classid, d.objid, d.objsubid, d.refclassid, d.refobjid, d.refobjsubid, d.deptype), '')
        from pg_catalog.pg_depend d
       where (d.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass and d.objid operator(pg_catalog.=) any (v_oids))
          or (d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass and d.refobjid operator(pg_catalog.=) any (v_oids)))
     is distinct from v_dependencias then
    raise exception 'pg_temp A3: cambiaron las dependencias de las funciones';
  end if;

  select pg_catalog.string_agg(
           p.oid::pg_catalog.regprocedure::pg_catalog.text
           || '|' || p.proowner::pg_catalog.regrole::pg_catalog.text
           || '|' || l.lanname::pg_catalog.text
           || '|' || p.prokind::pg_catalog.text
           || '|' || p.prosecdef::pg_catalog.text
           || '|' || p.proleakproof::pg_catalog.text
           || '|' || p.proisstrict::pg_catalog.text
           || '|' || p.proretset::pg_catalog.text
           || '|' || p.provolatile::pg_catalog.text
           || '|' || p.proparallel::pg_catalog.text
           || '|' || p.pronargs::pg_catalog.text
           || '|' || p.pronargdefaults::pg_catalog.text
           || '|' || p.prorettype::pg_catalog.regtype::pg_catalog.text
           || '|' || coalesce(p.proargnames::pg_catalog.text, '-')
           || '|' || coalesce(p.proargmodes::pg_catalog.text, '-')
           || '|' || coalesce(nullif(p.prosupport::pg_catalog.oid, 0::pg_catalog.oid)::pg_catalog.text, '-')
           || '|' || p.procost::pg_catalog.text
           || '|' || p.prorows::pg_catalog.text
           || '|' || coalesce(p.proconfig::pg_catalog.text, '-')
           || '|' || coalesce(pg_catalog.array_to_string(array(
                        select a::pg_catalog.text from pg_catalog.unnest(p.proacl) a order by 1), ','), '-')
           || '|' || coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '-')
           || '|' || coalesce(p.probin, '-')
           || '|' || (p.prosqlbody is null)::pg_catalog.text
           || '|' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex'),
           E'\n' order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
    into v_manifiesto
    from pg_catalog.pg_proc p
    join pg_catalog.pg_language l on l.oid = p.prolang
   where p.pronamespace = 'privado'::pg_catalog.regnamespace
     and p.proname::pg_catalog.text operator(pg_catalog.=) any (v_nombres);

  if v_manifiesto is distinct from v_manifiesto_nuevo then
    raise exception 'pg_temp A3: el estado resultante no es el esperado (manifiesto)';
  end if;

  -- Sin privilegios transitorios.
  if (select coalesce(n.nspacl::pg_catalog.text, '') from pg_catalog.pg_namespace n
       where n.nspname = 'privado') is distinct from v_acl_privado
     or pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'pg_temp A3: quedó un privilegio CREATE transitorio sobre privado';
  end if;

  -- Misma lista de SECURITY DEFINER.
  if (select pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::pg_catalog.text || '/'
                                   || p.proowner::pg_catalog.regrole::pg_catalog.text, ','
                                   order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
        from pg_catalog.pg_proc p
       where p.prosecdef
         and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace))
       is distinct from v_definer then
    raise exception 'pg_temp A3: cambió la lista de funciones SECURITY DEFINER';
  end if;

  -- P11: EXECUTE de authenticated en las 3 RPC; nunca anon ni service_role.
  for i in 1 .. 3 loop
    if pg_catalog.has_function_privilege('anon', v_oids[i], 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', v_oids[i], 'EXECUTE')
       or not pg_catalog.has_function_privilege('authenticated', v_oids[i], 'EXECUTE') then
      raise exception 'pg_temp A3: EXECUTE fuera de lo aprobado en %', v_firmas[i];
    end if;
  end loop;

  -- Restaura el search_path de la sesión para el resto de la transacción.
  perform pg_catalog.set_config('search_path', v_search_path_previo, true);

  if pg_catalog.current_setting('search_path') is distinct from v_search_path_previo then
    raise exception 'pg_temp A3: no se pudo restaurar el search_path';
  end if;
end
$mig$;
