-- A2 — Endurecimiento pg_temp de las RPC de catálogos y de los auxiliares
-- exigir_* (plan de remediación pg_temp, alternativa A; ADR-001 §17.1).
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.
--
-- Defecto (hallazgo ALTO heredado): con search_path = '' PostgreSQL busca pg_temp
-- ANTES que pg_catalog para tipos y relaciones no calificados. Los DECLARE de
-- estas 13 funciones declaran variables «uuid» y «text» sin esquema: al compilar
-- el cuerpo, un dominio pg_temp.uuid / pg_temp.text creado por una sesión que
-- puede asumir authenticated (TEMP por PUBLIC) se usa como tipo de la variable y
-- su CHECK ejecuta código propio como propietario_rpc.
--
-- Cambio: ÚNICAMENTE 29 calificaciones en los DECLARE («uuid» → «pg_catalog.uuid»,
-- «text» → «pg_catalog.text»):
--   10 RPC SECURITY DEFINER: crear_producto (3), actualizar_producto (2),
--      cambiar_estado_producto (1), crear_camion (3), actualizar_camion (2),
--      cambiar_estado_camion (1), crear_cliente (5), actualizar_cliente (2),
--      validar_cliente (2), cambiar_estado_cliente (1);
--   3 auxiliares SECURITY INVOKER: exigir_gestor_productos (3),
--      exigir_dueno_camiones (3), exigir_perfil_clientes (1).
-- Los cuerpos nuevos están escritos explícitamente abajo (texto revisable). Para
-- cada uno se verifican su SHA-256, que quitando «pg_catalog.» se obtiene el
-- cuerpo vigente byte a byte y la cantidad exacta de calificaciones. Las firmas
-- se reescriben con tipos pg_catalog.* y se verifica que pg_proc (salvo prosrc),
-- incluidos oid, owner, ACL, SECURITY, volatilidad, argumentos, valores por
-- defecto y dependencias, quede idéntico.
--
-- Sin referencias resolubles y sin cambios (verificados por manifiesto):
-- validar_campos_*, error_restriccion_*, estado_http_restriccion_*,
-- usuario_actual (A1 exigida: SHA-256 2ab0212d…) y empresa_gestion_actual.
--
-- Alcance: NO cierra la vulnerabilidad global. Quedan A3 (registrar_ingreso,
-- mover_a_cuarentena, registrar_merma) y B1 (jornadas, sobre el apilado).
--
-- Controles agregados respecto de A1 (observaciones A1-B01 y A1-B02 de la
-- security review): check_function_bodies = on exigido; topología completa de
-- propietario_rpc (atributos, sin membresías propias y exactamente dos filas
-- de pg_auth_members: la de O-3 otorgada por postgres y la automática de
-- PostgreSQL 16+ con ADMIN otorgada por un superusuario al crear el rol).
--
-- Resolución de nombres de la propia migración: DECLARE sin inicializadores y
-- con tipos pg_catalog; la primera sentencia fija search_path =
-- 'pg_catalog, pg_temp' (pg_temp explícito y al final) y la última lo restaura.
-- Todo tipo, cast, función y relación está calificado, también en el DDL
-- dinámico (format con %L para el search_path y el cuerpo).
--
-- Atomicidad: un único bloque DO (una sentencia, una transacción). El CREATE
-- transitorio de propietario_rpc sobre privado y el SET LOCAL ROLE
-- propietario_rpc (O-3) se conceden y se retiran dentro del bloque; ante
-- cualquier precondición o verificación fallida se aborta sin cambios.
--
-- Sin cambios de grants permanentes, RLS, tablas, roles, códigos de error ni
-- reglas de negocio.

do $mig$
declare
  -- Sin inicializadores: nada se evalúa antes de fijar el search_path controlado.
  v_search_path_previo pg_catalog.text;
  v_firmas pg_catalog.text[];
  v_cabeceras pg_catalog.text[];
  v_hash_previo pg_catalog.text[];
  v_hash_nuevo pg_catalog.text[];
  v_cantidad pg_catalog.int4[];
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
    raise exception 'pg_temp A2: no se pudo fijar el search_path controlado';
  end if;

  -- -------------------------------------------------------------------------
  -- Constantes (asignadas con el search_path ya controlado)
  -- -------------------------------------------------------------------------
  -- Funciones que cambian: firma calificada, cabecera DDL (firma, retorno,
  -- lenguaje, volatilidad y SECURITY idénticos a los vigentes), SHA-256 del
  -- cuerpo vigente y del nuevo, cantidad de calificaciones y cuerpo nuevo.
  -- 1. privado.exigir_gestor_productos(): 3 calificaciones
  v_firmas[1] := 'privado.exigir_gestor_productos()';
  v_cabeceras[1] := 'privado.exigir_gestor_productos() returns pg_catalog.uuid language plpgsql stable security invoker';
  v_hash_previo[1] := '46b64fe0545eb52fde282fb23645136e7b06ff8b7b9cafc9c843ca4771738fd1';
  v_hash_nuevo[1] := '2db9f4fbfa108f8ea78b6a65787a3ccbfcefd0d50bb0f11b8c670035b1fd1ae1';
  v_cantidad[1] := 3;
  v_cuerpos[1] := $c1$
declare
  v_uid pg_catalog.uuid := privado.usuario_actual();
  v_empresa pg_catalog.uuid;
  v_rol pg_catalog.text;
  v_activo boolean;
begin
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'producto_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if v_empresa is null
     or v_activo is not true
     or v_rol is null
     or v_rol not in ('dueno', 'encargado') then
    raise exception using errcode = 'PT403', message = 'producto_no_autorizado';
  end if;

  return v_empresa;
end $c1$;

  -- 2. privado.exigir_dueno_camiones(): 3 calificaciones
  v_firmas[2] := 'privado.exigir_dueno_camiones()';
  v_cabeceras[2] := 'privado.exigir_dueno_camiones() returns pg_catalog.uuid language plpgsql stable security invoker';
  v_hash_previo[2] := 'bb0231b89d69ff78085791636767ed85089253695d7e4e66568a90629cc27734';
  v_hash_nuevo[2] := '22bdccf7372b52ec6c35faad3f71fc2f270b0e57061ebe63fed6b588a3811f30';
  v_cantidad[2] := 3;
  v_cuerpos[2] := $c2$
declare
  v_uid pg_catalog.uuid := privado.usuario_actual();
  v_empresa pg_catalog.uuid;
  v_rol pg_catalog.text;
  v_activo boolean;
begin
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'camion_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into v_empresa, v_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if v_empresa is null
     or v_activo is not true
     or v_rol is distinct from 'dueno' then
    raise exception using errcode = 'PT403', message = 'camion_no_autorizado';
  end if;

  return v_empresa;
end $c2$;

  -- 3. privado.exigir_perfil_clientes(boolean): 1 calificaciones
  v_firmas[3] := 'privado.exigir_perfil_clientes(pg_catalog.bool)';
  v_cabeceras[3] := 'privado.exigir_perfil_clientes(p_gestion pg_catalog.bool, out o_empresa pg_catalog.uuid, out o_rol pg_catalog.text) returns pg_catalog.record language plpgsql stable security invoker';
  v_hash_previo[3] := '9c11105d924ed7542f0243b2091316ae58722b7d5ec46d8492de43cc206025c4';
  v_hash_nuevo[3] := 'd9baf6136cbb425296ba838b64e9ab062175bf11952ea663aa170b94a4cdf03a';
  v_cantidad[3] := 1;
  v_cuerpos[3] := $c3$
declare
  v_uid pg_catalog.uuid := privado.usuario_actual();
  v_activo boolean;
begin
  if v_uid is null then
    raise exception using errcode = 'PT401', message = 'cliente_no_autenticado';
  end if;

  select p.empresa_id, p.rol, p.activo
    into o_empresa, o_rol, v_activo
    from public.perfiles p
   where p.usuario_id = v_uid;

  if o_empresa is null
     or v_activo is not true
     or (p_gestion and o_rol not in ('dueno', 'encargado')) then
    raise exception using errcode = 'PT403', message = 'cliente_no_autorizado';
  end if;
end $c3$;

  -- 4. privado.crear_producto(text,text,text,text,numeric,integer): 3 calificaciones
  v_firmas[4] := 'privado.crear_producto(pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.numeric, pg_catalog.int4)';
  v_cabeceras[4] := 'privado.crear_producto(p_codigo pg_catalog.text, p_nombre pg_catalog.text, p_categoria pg_catalog.text, p_forma_venta pg_catalog.text, p_precio pg_catalog.numeric, p_stock_minimo pg_catalog.int4) returns pg_catalog.uuid language plpgsql volatile security definer';
  v_hash_previo[4] := 'a0a5a239d6eb60aca8f0a7a1309d4643d3054eef159e821ddfd42cee84355aa3';
  v_hash_nuevo[4] := '1d7975632846bc9afbf6ac2d5706b4ae594fca766a448dc9d5a0e2e7d62b0445';
  v_cantidad[4] := 3;
  v_cuerpos[4] := $c4$
declare
  v_empresa pg_catalog.uuid := privado.exigir_gestor_productos();
  v_id pg_catalog.uuid;
  v_restriccion pg_catalog.text;
begin
  perform privado.validar_campos_producto(p_nombre, p_precio, p_stock_minimo);

  if p_categoria is null or p_categoria not in ('lacteos', 'fiambres') then
    raise exception using errcode = 'PT400', message = 'producto_categoria_invalida';
  end if;

  if p_forma_venta is null or p_forma_venta not in ('unidad', 'peso') then
    raise exception using errcode = 'PT400', message = 'producto_forma_venta_invalida';
  end if;

  if not ((p_categoria = 'lacteos' and p_forma_venta = 'unidad')
       or (p_categoria = 'fiambres' and p_forma_venta = 'peso')) then
    raise exception using errcode = 'PT400', message = 'producto_combinacion_invalida';
  end if;

  begin
    insert into public.productos (
      empresa_id, codigo, nombre, categoria, forma_venta, precio,
      stock_minimo, creado_por
    )
    values (
      v_empresa, nullif(btrim(p_codigo), ''), btrim(p_nombre), p_categoria,
      p_forma_venta, p_precio, p_stock_minimo, privado.usuario_actual()
    )
    returning id into v_id;
  exception
    when unique_violation or check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_producto(v_restriccion),
        message = privado.error_restriccion_producto(v_restriccion);
  end;

  return v_id;
end $c4$;

  -- 5. privado.actualizar_producto(uuid,text,text,numeric,integer): 2 calificaciones
  v_firmas[5] := 'privado.actualizar_producto(pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.numeric, pg_catalog.int4)';
  v_cabeceras[5] := 'privado.actualizar_producto(p_producto_id pg_catalog.uuid, p_codigo pg_catalog.text, p_nombre pg_catalog.text, p_precio pg_catalog.numeric, p_stock_minimo pg_catalog.int4) returns pg_catalog.void language plpgsql volatile security definer';
  v_hash_previo[5] := '83a1d8a927fe1377570e9c63eeba16a3bfc29844cd9c4bf89cd438006a57765f';
  v_hash_nuevo[5] := '9cba80d132f5e2a5db8ebb102418d37945547d2a8c6e4b720b8f4a87bf0cbfb0';
  v_cantidad[5] := 2;
  v_cuerpos[5] := $c5$
declare
  v_empresa pg_catalog.uuid := privado.exigir_gestor_productos();
  v_restriccion pg_catalog.text;
begin
  perform privado.validar_campos_producto(p_nombre, p_precio, p_stock_minimo);

  begin
    update public.productos
       set codigo = nullif(btrim(p_codigo), ''),
           nombre = btrim(p_nombre),
           precio = p_precio,
           stock_minimo = p_stock_minimo
     where id = p_producto_id
       and empresa_id = v_empresa;
  exception
    when unique_violation or check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_producto(v_restriccion),
        message = privado.error_restriccion_producto(v_restriccion);
  end;

  -- Inexistente u otra empresa: mismo resultado (ADR-001 §8.5).
  if not found then
    raise exception using errcode = 'PT404', message = 'producto_no_encontrado';
  end if;
end $c5$;

  -- 6. privado.cambiar_estado_producto(uuid,boolean): 1 calificaciones
  v_firmas[6] := 'privado.cambiar_estado_producto(pg_catalog.uuid, pg_catalog.bool)';
  v_cabeceras[6] := 'privado.cambiar_estado_producto(p_producto_id pg_catalog.uuid, p_activo pg_catalog.bool) returns pg_catalog.void language plpgsql volatile security definer';
  v_hash_previo[6] := '7933b7b7f06a0e815f30e03d9d35dea231b16643529008f8f3b92a13d3b4c1ea';
  v_hash_nuevo[6] := 'd3a5be682a9f13c677c087fa1ab05e83d70527149abc5259b33959f95c3fc0b2';
  v_cantidad[6] := 1;
  v_cuerpos[6] := $c6$
declare
  v_empresa pg_catalog.uuid := privado.exigir_gestor_productos();
begin
  if p_activo is null then
    raise exception using errcode = 'PT400', message = 'producto_estado_invalido';
  end if;

  update public.productos
     set activo = p_activo
   where id = p_producto_id
     and empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'producto_no_encontrado';
  end if;
end $c6$;

  -- 7. privado.crear_camion(text,text): 3 calificaciones
  v_firmas[7] := 'privado.crear_camion(pg_catalog.text, pg_catalog.text)';
  v_cabeceras[7] := 'privado.crear_camion(p_patente pg_catalog.text, p_nombre pg_catalog.text) returns pg_catalog.uuid language plpgsql volatile security definer';
  v_hash_previo[7] := '87a2b750e2969527bdaae655442dc3e4563f73aac02ad5e0acbcd81cda9a64f2';
  v_hash_nuevo[7] := 'ac846c7cb86ca1ea7fbf675f6ac4698b473517399f14d4fd31ce3d54715815bf';
  v_cantidad[7] := 3;
  v_cuerpos[7] := $c7$
declare
  v_empresa pg_catalog.uuid := privado.exigir_dueno_camiones();
  v_id pg_catalog.uuid;
  v_restriccion pg_catalog.text;
begin
  perform privado.validar_campos_camion(p_patente, p_nombre);

  begin
    insert into public.camiones (empresa_id, patente, nombre, creado_por)
    values (v_empresa, btrim(p_patente), btrim(p_nombre), privado.usuario_actual())
    returning id into v_id;

    -- Su ubicación de stock (D2). Una falla acá revierte también el camión;
    -- una restricción de ubicaciones se informa como error interno.
    insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values (v_empresa, 'camion', v_id);
  exception
    when unique_violation or check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_camion(v_restriccion),
        message = privado.error_restriccion_camion(v_restriccion);
  end;

  return v_id;
end $c7$;

  -- 8. privado.actualizar_camion(uuid,text,text): 2 calificaciones
  v_firmas[8] := 'privado.actualizar_camion(pg_catalog.uuid, pg_catalog.text, pg_catalog.text)';
  v_cabeceras[8] := 'privado.actualizar_camion(p_camion_id pg_catalog.uuid, p_patente pg_catalog.text, p_nombre pg_catalog.text) returns pg_catalog.void language plpgsql volatile security definer';
  v_hash_previo[8] := '071bafa17b64a40baf0829977e1e69d525918719aff64a9a64581ceb91c866b0';
  v_hash_nuevo[8] := 'ec3c2fec0c84ae702b0690457821381403e010dbdd1160395d22d686875492ae';
  v_cantidad[8] := 2;
  v_cuerpos[8] := $c8$
declare
  v_empresa pg_catalog.uuid := privado.exigir_dueno_camiones();
  v_restriccion pg_catalog.text;
begin
  perform privado.validar_campos_camion(p_patente, p_nombre);

  begin
    update public.camiones
       set patente = btrim(p_patente),
           nombre = btrim(p_nombre)
     where id = p_camion_id
       and empresa_id = v_empresa;
  exception
    when unique_violation or check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_camion(v_restriccion),
        message = privado.error_restriccion_camion(v_restriccion);
  end;

  -- Inexistente u otra empresa: mismo resultado (ADR-001 §8.5).
  if not found then
    raise exception using errcode = 'PT404', message = 'camion_no_encontrado';
  end if;
end $c8$;

  -- 9. privado.cambiar_estado_camion(uuid,boolean): 1 calificaciones
  v_firmas[9] := 'privado.cambiar_estado_camion(pg_catalog.uuid, pg_catalog.bool)';
  v_cabeceras[9] := 'privado.cambiar_estado_camion(p_camion_id pg_catalog.uuid, p_activo pg_catalog.bool) returns pg_catalog.void language plpgsql volatile security definer';
  v_hash_previo[9] := '570b1fe97adb23ac3baa2c32fb023f505ba56d056567edfe88a70ac6cc0e527c';
  v_hash_nuevo[9] := '1065b36961150678cdd687a92cce75b73e90fca2909ea790b645fc91573cc1b3';
  v_cantidad[9] := 1;
  v_cuerpos[9] := $c9$
declare
  v_empresa pg_catalog.uuid := privado.exigir_dueno_camiones();
begin
  if p_activo is null then
    raise exception using errcode = 'PT400', message = 'camion_estado_invalido';
  end if;

  update public.camiones
     set activo = p_activo
   where id = p_camion_id
     and empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'camion_no_encontrado';
  end if;
end $c9$;

  -- 10. privado.crear_cliente(text,text,text,text): 5 calificaciones
  v_firmas[10] := 'privado.crear_cliente(pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text)';
  v_cabeceras[10] := 'privado.crear_cliente(p_nombre pg_catalog.text, p_telefono pg_catalog.text, p_comercio pg_catalog.text default null::pg_catalog.text, p_direccion pg_catalog.text default null::pg_catalog.text) returns pg_catalog.uuid language plpgsql volatile security definer';
  v_hash_previo[10] := '88f8d9a9108ad8af72b1daea5434d51cb71aac663b9a611833cca63c14da6b4d';
  v_hash_nuevo[10] := 'b05182fe2a5c5b9f40ea6156a54cb2e3d77a7b282171468e43981a3a76ce832b';
  v_cantidad[10] := 5;
  v_cuerpos[10] := $c10$
declare
  v_empresa pg_catalog.uuid;
  v_rol pg_catalog.text;
  v_uid pg_catalog.uuid := privado.usuario_actual();
  v_validado boolean;
  v_id pg_catalog.uuid;
  v_restriccion pg_catalog.text;
begin
  select e.o_empresa, e.o_rol
    into v_empresa, v_rol
    from privado.exigir_perfil_clientes(false) e;

  perform privado.validar_campos_cliente(p_nombre, p_telefono);

  -- Dueño y encargado dan de alta clientes ya validados; el vendedor/piloto,
  -- pendientes de validación.
  v_validado := v_rol in ('dueno', 'encargado');

  begin
    insert into public.clientes (
      empresa_id, nombre, comercio, direccion, telefono,
      estado_validacion, creado_por, validado_por, validado_en
    )
    values (
      v_empresa,
      btrim(p_nombre),
      nullif(btrim(p_comercio), ''),
      nullif(btrim(p_direccion), ''),
      btrim(p_telefono),
      case when v_validado then 'validado' else 'pendiente' end,
      v_uid,
      case when v_validado then v_uid end,
      case when v_validado then now() end
    )
    returning id into v_id;
  exception
    when check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_cliente(v_restriccion),
        message = privado.error_restriccion_cliente(v_restriccion);
  end;

  return v_id;
end $c10$;

  -- 11. privado.actualizar_cliente(uuid,text,text,text,text): 2 calificaciones
  v_firmas[11] := 'privado.actualizar_cliente(pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text)';
  v_cabeceras[11] := 'privado.actualizar_cliente(p_cliente_id pg_catalog.uuid, p_nombre pg_catalog.text, p_telefono pg_catalog.text, p_comercio pg_catalog.text, p_direccion pg_catalog.text) returns pg_catalog.void language plpgsql volatile security definer';
  v_hash_previo[11] := 'cb64fccf120364b603e6abd4380b3421137fae685351097fb5d8febeaa0a6ed5';
  v_hash_nuevo[11] := '314b9c995b364974146a98050c53ed6e962378af89aa750deebdf187c44e66fa';
  v_cantidad[11] := 2;
  v_cuerpos[11] := $c11$
declare
  v_empresa pg_catalog.uuid;
  v_restriccion pg_catalog.text;
begin
  select e.o_empresa into v_empresa from privado.exigir_perfil_clientes(true) e;

  perform privado.validar_campos_cliente(p_nombre, p_telefono);

  begin
    update public.clientes
       set nombre = btrim(p_nombre),
           telefono = btrim(p_telefono),
           comercio = nullif(btrim(p_comercio), ''),
           direccion = nullif(btrim(p_direccion), '')
     where id = p_cliente_id
       and empresa_id = v_empresa;
  exception
    when check_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      raise exception using
        errcode = privado.estado_http_restriccion_cliente(v_restriccion),
        message = privado.error_restriccion_cliente(v_restriccion);
  end;

  -- Inexistente u otra empresa: mismo resultado (ADR-001 §8.5).
  if not found then
    raise exception using errcode = 'PT404', message = 'cliente_no_encontrado';
  end if;
end $c11$;

  -- 12. privado.validar_cliente(uuid): 2 calificaciones
  v_firmas[12] := 'privado.validar_cliente(pg_catalog.uuid)';
  v_cabeceras[12] := 'privado.validar_cliente(p_cliente_id pg_catalog.uuid) returns pg_catalog.void language plpgsql volatile security definer';
  v_hash_previo[12] := '9fe8e7a142836c6c31ad8f4d5abd6b6f17ea037168c50e6eeb40ca675c3c1377';
  v_hash_nuevo[12] := '3a27c544b3fa7e1e7701144c6de5cf9926f3cfc7e2478ba1291f23dd1ca7cc52';
  v_cantidad[12] := 2;
  v_cuerpos[12] := $c12$
declare
  v_empresa pg_catalog.uuid;
  v_uid pg_catalog.uuid := privado.usuario_actual();
begin
  select e.o_empresa into v_empresa from privado.exigir_perfil_clientes(true) e;

  update public.clientes
     set estado_validacion = 'validado',
         validado_por = v_uid,
         validado_en = now()
   where id = p_cliente_id
     and empresa_id = v_empresa
     and estado_validacion = 'pendiente';

  if not found
     and not exists (
       select 1 from public.clientes c
        where c.id = p_cliente_id
          and c.empresa_id = v_empresa
     ) then
    raise exception using errcode = 'PT404', message = 'cliente_no_encontrado';
  end if;
end $c12$;

  -- 13. privado.cambiar_estado_cliente(uuid,boolean): 1 calificaciones
  v_firmas[13] := 'privado.cambiar_estado_cliente(pg_catalog.uuid, pg_catalog.bool)';
  v_cabeceras[13] := 'privado.cambiar_estado_cliente(p_cliente_id pg_catalog.uuid, p_activo pg_catalog.bool) returns pg_catalog.void language plpgsql volatile security definer';
  v_hash_previo[13] := 'b9f84955c1ceb5bdd8caa9034f4eb53b4d14cc93110ede2e3b10d1aa500d5400';
  v_hash_nuevo[13] := '72fe95006a8e4f5dfda473e7a6b70fd8e8e3e81f0e68040db6721be1b23bbfd1';
  v_cantidad[13] := 1;
  v_cuerpos[13] := $c13$
declare
  v_empresa pg_catalog.uuid;
begin
  select e.o_empresa into v_empresa from privado.exigir_perfil_clientes(true) e;

  if p_activo is null then
    raise exception using errcode = 'PT400', message = 'cliente_estado_invalido';
  end if;

  update public.clientes
     set activo = p_activo
   where id = p_cliente_id
     and empresa_id = v_empresa;

  if not found then
    raise exception using errcode = 'PT404', message = 'cliente_no_encontrado';
  end if;
end $c13$;

  -- Las 24 funciones de privado alcanzadas o verificadas por A2.
  v_nombres := array[
    'crear_producto', 'actualizar_producto', 'cambiar_estado_producto',
    'crear_camion', 'actualizar_camion', 'cambiar_estado_camion',
    'crear_cliente', 'actualizar_cliente', 'validar_cliente', 'cambiar_estado_cliente',
    'exigir_gestor_productos', 'exigir_dueno_camiones', 'exigir_perfil_clientes',
    'validar_campos_producto', 'validar_campos_camion', 'validar_campos_cliente',
    'error_restriccion_producto', 'error_restriccion_camion', 'error_restriccion_cliente',
    'estado_http_restriccion_producto', 'estado_http_restriccion_camion',
    'estado_http_restriccion_cliente', 'usuario_actual', 'empresa_gestion_actual'];

  -- Distribución exacta por esquema de esos nombres (implementaciones en
  -- privado y fachadas public de las 10 RPC; ningún otro homónimo).
  v_distribucion := 'actualizar_camion:privado,public;actualizar_cliente:privado,public;actualizar_producto:privado,public;cambiar_estado_camion:privado,public;cambiar_estado_cliente:privado,public;cambiar_estado_producto:privado,public;crear_camion:privado,public;crear_cliente:privado,public;crear_producto:privado,public;empresa_gestion_actual:privado;error_restriccion_camion:privado;error_restriccion_cliente:privado;error_restriccion_producto:privado;estado_http_restriccion_camion:privado;estado_http_restriccion_cliente:privado;estado_http_restriccion_producto:privado;exigir_dueno_camiones:privado;exigir_gestor_productos:privado;exigir_perfil_clientes:privado;usuario_actual:privado;validar_campos_camion:privado;validar_campos_cliente:privado;validar_campos_producto:privado;validar_cliente:privado,public';

  -- Manifiesto exacto de las 24 funciones (una línea por función, ordenadas por
  -- firma): firma | owner | lenguaje | prokind | SECURITY DEFINER | leakproof |
  -- strict | retset | volatilidad | paralelismo | nargs | nargdefaults | tipo de
  -- retorno | nombres de argumentos | modos | support | costo | filas |
  -- proconfig | ACL ordenada | comentario | probin | prosqlbody nulo | SHA-256.
  v_manifiesto_previo :=
       'privado.actualizar_camion(uuid,text,text)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|3|0|void|{p_camion_id,p_patente,p_nombre}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|071bafa17b64a40baf0829977e1e69d525918719aff64a9a64581ceb91c866b0' || E'\n'
    || 'privado.actualizar_cliente(uuid,text,text,text,text)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|5|0|void|{p_cliente_id,p_nombre,p_telefono,p_comercio,p_direccion}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|cb64fccf120364b603e6abd4380b3421137fae685351097fb5d8febeaa0a6ed5' || E'\n'
    || 'privado.actualizar_producto(uuid,text,text,numeric,integer)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|5|0|void|{p_producto_id,p_codigo,p_nombre,p_precio,p_stock_minimo}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|83a1d8a927fe1377570e9c63eeba16a3bfc29844cd9c4bf89cd438006a57765f' || E'\n'
    || 'privado.cambiar_estado_camion(uuid,boolean)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|2|0|void|{p_camion_id,p_activo}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|570b1fe97adb23ac3baa2c32fb023f505ba56d056567edfe88a70ac6cc0e527c' || E'\n'
    || 'privado.cambiar_estado_cliente(uuid,boolean)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|2|0|void|{p_cliente_id,p_activo}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|b9f84955c1ceb5bdd8caa9034f4eb53b4d14cc93110ede2e3b10d1aa500d5400' || E'\n'
    || 'privado.cambiar_estado_producto(uuid,boolean)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|2|0|void|{p_producto_id,p_activo}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|7933b7b7f06a0e815f30e03d9d35dea231b16643529008f8f3b92a13d3b4c1ea' || E'\n'
    || 'privado.crear_camion(text,text)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|2|0|uuid|{p_patente,p_nombre}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|87a2b750e2969527bdaae655442dc3e4563f73aac02ad5e0acbcd81cda9a64f2' || E'\n'
    || 'privado.crear_cliente(text,text,text,text)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|4|2|uuid|{p_nombre,p_telefono,p_comercio,p_direccion}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|88f8d9a9108ad8af72b1daea5434d51cb71aac663b9a611833cca63c14da6b4d' || E'\n'
    || 'privado.crear_producto(text,text,text,text,numeric,integer)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|6|0|uuid|{p_codigo,p_nombre,p_categoria,p_forma_venta,p_precio,p_stock_minimo}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|a0a5a239d6eb60aca8f0a7a1309d4643d3054eef159e821ddfd42cee84355aa3' || E'\n'
    || 'privado.empresa_gestion_actual()|propietario_rpc|sql|f|true|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|6d0a758d68ffaf8f575e1faebb132dc29cab4400e81c953b6dc73ed475fce7cc' || E'\n'
    || 'privado.error_restriccion_camion(text)|propietario_rpc|sql|f|false|false|false|false|i|u|1|0|text|{p_restriccion}|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|97bab45be0c746463b7fed6fa96592e6818bfd8d37bb9ef41e60fa08a830828c' || E'\n'
    || 'privado.error_restriccion_cliente(text)|propietario_rpc|sql|f|false|false|false|false|i|u|1|0|text|{p_restriccion}|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|b1bdbb32a4a9b771f53be3eec6c61a64c23b0ab03978d4363f5d758f22354c25' || E'\n'
    || 'privado.error_restriccion_producto(text)|propietario_rpc|sql|f|false|false|false|false|i|u|1|0|text|{p_restriccion}|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|1b657d872c70cdb11e466253bcedfed8efc847131871ff1086a2a073d94241b1' || E'\n'
    || 'privado.estado_http_restriccion_camion(text)|propietario_rpc|sql|f|false|false|false|false|i|u|1|0|text|{p_restriccion}|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|d9eb261438f58974367dd8e01204d09b62ede7a1c9aa80e0d246e5e36970ee94' || E'\n'
    || 'privado.estado_http_restriccion_cliente(text)|propietario_rpc|sql|f|false|false|false|false|i|u|1|0|text|{p_restriccion}|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|1849676097f40e4ed8840cb81de0f63465d40fdabad36d2046a8e8ee5d89be77' || E'\n'
    || 'privado.estado_http_restriccion_producto(text)|propietario_rpc|sql|f|false|false|false|false|i|u|1|0|text|{p_restriccion}|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|71ca9fae34f47be07cadf9b9dbd627a080a4beb1bce48f4c7119a60c5faaa6a0' || E'\n'
    || 'privado.exigir_dueno_camiones()|propietario_rpc|plpgsql|f|false|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|bb0231b89d69ff78085791636767ed85089253695d7e4e66568a90629cc27734' || E'\n'
    || 'privado.exigir_gestor_productos()|propietario_rpc|plpgsql|f|false|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|46b64fe0545eb52fde282fb23645136e7b06ff8b7b9cafc9c843ca4771738fd1' || E'\n'
    || 'privado.exigir_perfil_clientes(boolean)|propietario_rpc|plpgsql|f|false|false|false|false|s|u|1|0|record|{p_gestion,o_empresa,o_rol}|{i,o,o}|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|9c11105d924ed7542f0243b2091316ae58722b7d5ec46d8492de43cc206025c4' || E'\n'
    || 'privado.usuario_actual()|propietario_rpc|sql|f|false|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96' || E'\n'
    || 'privado.validar_campos_camion(text,text)|propietario_rpc|plpgsql|f|false|false|false|false|i|u|2|0|void|{p_patente,p_nombre}|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|de1daf15134db8ca8662393740295f35f30970113e16c811881e5571c336c67c' || E'\n'
    || 'privado.validar_campos_cliente(text,text)|propietario_rpc|plpgsql|f|false|false|false|false|i|u|2|0|void|{p_nombre,p_telefono}|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|8052ad0330f19eb2a3f69829ac2c4a974c36363e92cf4f5b8174cd4d2f3d2fc3' || E'\n'
    || 'privado.validar_campos_producto(text,numeric,integer)|propietario_rpc|plpgsql|f|false|false|false|false|i|u|3|0|void|{p_nombre,p_precio,p_stock_minimo}|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|197030d06a5544b9cd98103595415cc07ab1603a0c81935baf13d9bb2e35ac0b' || E'\n'
    || 'privado.validar_cliente(uuid)|propietario_rpc|plpgsql|f|true|false|false|false|v|u|1|0|void|{p_cliente_id}|-|-|100|0|{"search_path=\"\""}|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc|-|-|true|9fe8e7a142836c6c31ad8f4d5abd6b6f17ea037168c50e6eeb40ca675c3c1377';
  v_manifiesto_nuevo := v_manifiesto_previo;
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, '46b64fe0545eb52fde282fb23645136e7b06ff8b7b9cafc9c843ca4771738fd1', '2db9f4fbfa108f8ea78b6a65787a3ccbfcefd0d50bb0f11b8c670035b1fd1ae1');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, 'bb0231b89d69ff78085791636767ed85089253695d7e4e66568a90629cc27734', '22bdccf7372b52ec6c35faad3f71fc2f270b0e57061ebe63fed6b588a3811f30');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, '9c11105d924ed7542f0243b2091316ae58722b7d5ec46d8492de43cc206025c4', 'd9baf6136cbb425296ba838b64e9ab062175bf11952ea663aa170b94a4cdf03a');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, 'a0a5a239d6eb60aca8f0a7a1309d4643d3054eef159e821ddfd42cee84355aa3', '1d7975632846bc9afbf6ac2d5706b4ae594fca766a448dc9d5a0e2e7d62b0445');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, '83a1d8a927fe1377570e9c63eeba16a3bfc29844cd9c4bf89cd438006a57765f', '9cba80d132f5e2a5db8ebb102418d37945547d2a8c6e4b720b8f4a87bf0cbfb0');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, '7933b7b7f06a0e815f30e03d9d35dea231b16643529008f8f3b92a13d3b4c1ea', 'd3a5be682a9f13c677c087fa1ab05e83d70527149abc5259b33959f95c3fc0b2');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, '87a2b750e2969527bdaae655442dc3e4563f73aac02ad5e0acbcd81cda9a64f2', 'ac846c7cb86ca1ea7fbf675f6ac4698b473517399f14d4fd31ce3d54715815bf');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, '071bafa17b64a40baf0829977e1e69d525918719aff64a9a64581ceb91c866b0', 'ec3c2fec0c84ae702b0690457821381403e010dbdd1160395d22d686875492ae');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, '570b1fe97adb23ac3baa2c32fb023f505ba56d056567edfe88a70ac6cc0e527c', '1065b36961150678cdd687a92cce75b73e90fca2909ea790b645fc91573cc1b3');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, '88f8d9a9108ad8af72b1daea5434d51cb71aac663b9a611833cca63c14da6b4d', 'b05182fe2a5c5b9f40ea6156a54cb2e3d77a7b282171468e43981a3a76ce832b');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, 'cb64fccf120364b603e6abd4380b3421137fae685351097fb5d8febeaa0a6ed5', '314b9c995b364974146a98050c53ed6e962378af89aa750deebdf187c44e66fa');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, '9fe8e7a142836c6c31ad8f4d5abd6b6f17ea037168c50e6eeb40ca675c3c1377', '3a27c544b3fa7e1e7701144c6de5cf9926f3cfc7e2478ba1291f23dd1ca7cc52');
  v_manifiesto_nuevo := pg_catalog.replace(v_manifiesto_nuevo, 'b9f84955c1ceb5bdd8caa9034f4eb53b4d14cc93110ede2e3b10d1aa500d5400', '72fe95006a8e4f5dfda473e7a6b70fd8e8e3e81f0e68040db6721be1b23bbfd1');

  -- -------------------------------------------------------------------------
  -- Precondiciones de identidad, entorno y roles (fail-closed)
  -- -------------------------------------------------------------------------
  if current_user operator(pg_catalog.<>) 'postgres'
     or session_user operator(pg_catalog.<>) 'postgres' then
    raise exception 'pg_temp A2: la migración debe ejecutarse como postgres; actual: % / %',
      session_user, current_user;
  end if;

  -- A1-B01: los cuerpos se validan al crearlos, en este contexto controlado.
  if pg_catalog.current_setting('check_function_bodies') operator(pg_catalog.<>) 'on' then
    raise exception 'pg_temp A2: check_function_bodies debe estar activo';
  end if;

  -- P3 completo (incluye NOREPLICATION).
  if not exists (select 1 from pg_catalog.pg_roles r
                  where r.rolname = 'propietario_rpc'
                    and not r.rolsuper and not r.rolcanlogin and not r.rolbypassrls
                    and not r.rolcreatedb and not r.rolcreaterole and not r.rolreplication) then
    raise exception 'pg_temp A2: propietario_rpc ausente o con atributos fuera de P3';
  end if;

  -- A1-B02: topología de membresías. propietario_rpc no es miembro de ningún
  -- rol; sus únicos miembros son las dos filas de postgres: O-3 (SET sin
  -- INHERIT ni ADMIN, otorgada por postgres) y la automática de PostgreSQL 16+
  -- al crear el rol (ADMIN sin INHERIT ni SET, otorgada por un superusuario).
  if exists (select 1 from pg_catalog.pg_auth_members m
              where m.member = 'propietario_rpc'::pg_catalog.regrole) then
    raise exception 'pg_temp A2: propietario_rpc es miembro de otro rol';
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
    raise exception 'pg_temp A2: membresías de propietario_rpc fuera de lo aprobado (P3/O-3): %', v_membresias;
  end if;

  -- O-3 efectivo: postgres puede SET ROLE propietario_rpc sin heredar.
  if not pg_catalog.pg_has_role('postgres', 'propietario_rpc', 'SET')
     or pg_catalog.pg_has_role('postgres', 'propietario_rpc', 'USAGE') then
    raise exception 'pg_temp A2: la membresía postgres → propietario_rpc no es la de O-3';
  end if;

  if (select n.nspowner from pg_catalog.pg_namespace n where n.nspname = 'privado')
     is distinct from 'postgres'::pg_catalog.regrole then
    raise exception 'pg_temp A2: el esquema privado no es de postgres';
  end if;

  if pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'pg_temp A2: propietario_rpc ya tiene CREATE sobre privado';
  end if;

  if not pg_catalog.has_language_privilege('propietario_rpc', 'plpgsql', 'USAGE') then
    raise exception 'pg_temp A2: propietario_rpc no puede usar plpgsql';
  end if;

  -- Dependencia de A1: usuario_actual con los dos casts calificados.
  if (select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex')
        from pg_catalog.pg_proc p
       where p.oid = pg_catalog.to_regprocedure('privado.usuario_actual()'))
     is distinct from '2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96' then
    raise exception 'pg_temp A2: falta A1 (privado.usuario_actual() no tiene el cuerpo calificado)';
  end if;

  -- Firmas existentes.
  for i in 1 .. pg_catalog.array_length(v_firmas, 1) loop
    v_oid := pg_catalog.to_regprocedure(v_firmas[i]);
    if v_oid is null then
      raise exception 'pg_temp A2: falta la función %', v_firmas[i];
    end if;
    v_oids[i] := v_oid;
  end loop;

  if pg_catalog.array_length(v_oids, 1) operator(pg_catalog.<>) 13 then
    raise exception 'pg_temp A2: se esperaban 13 funciones a corregir';
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
    raise exception 'pg_temp A2: sobrecargas u homónimos fuera de lo esperado: %', v_manifiesto;
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
    raise exception 'pg_temp A2: el estado de las funciones de catálogos no es el aprobado (manifiesto)';
  end if;

  -- Fotos: pg_proc completo de public y privado (sin prosrc para las 13 que
  -- cambian), dependencias en las que participan las 13, ACL de privado y lista
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
  for i in 1 .. 13 loop
    select p.prosrc into v_src from pg_catalog.pg_proc p where p.oid = v_oids[i];
    if pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_src, 'UTF8')), 'hex')
         operator(pg_catalog.<>) v_hash_previo[i]
       or pg_catalog.strpos(v_src, 'pg_catalog.') operator(pg_catalog.<>) 0
       or pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_cuerpos[i], 'UTF8')), 'hex')
         operator(pg_catalog.<>) v_hash_nuevo[i]
       or pg_catalog.replace(v_cuerpos[i], 'pg_catalog.', '') is distinct from v_src
       or (pg_catalog.length(v_cuerpos[i])
           - pg_catalog.length(pg_catalog.replace(v_cuerpos[i], 'pg_catalog.', '')))
          / pg_catalog.length('pg_catalog.') operator(pg_catalog.<>) v_cantidad[i] then
      raise exception 'pg_temp A2: el cuerpo nuevo de % no es el vigente con las calificaciones previstas', v_firmas[i];
    end if;
  end loop;

  -- -------------------------------------------------------------------------
  -- Sustitución como owner técnico (O-3), con CREATE transitorio
  -- -------------------------------------------------------------------------
  grant create on schema privado to propietario_rpc;
  set local role propietario_rpc;

  if current_user operator(pg_catalog.<>) 'propietario_rpc'
     or pg_catalog.current_setting('search_path') operator(pg_catalog.<>) 'pg_catalog, pg_temp' then
    raise exception 'pg_temp A2: no se pudo actuar como propietario_rpc con el search_path controlado';
  end if;

  for i in 1 .. 13 loop
    execute pg_catalog.format(
      'create or replace function ' || v_cabeceras[i] || ' set search_path = %L as %L',
      '', v_cuerpos[i]);
  end loop;

  reset role;

  if current_user operator(pg_catalog.<>) 'postgres' then
    raise exception 'pg_temp A2: no se pudo volver a postgres';
  end if;

  revoke create on schema privado from propietario_rpc;

  -- -------------------------------------------------------------------------
  -- Verificación fail-closed del resultado
  -- -------------------------------------------------------------------------
  for i in 1 .. 13 loop
    if (select p.prosrc from pg_catalog.pg_proc p where p.oid = v_oids[i]) is distinct from v_cuerpos[i] then
      raise exception 'pg_temp A2: el cuerpo instalado de % no es el previsto', v_firmas[i];
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
    raise exception 'pg_temp A2: cambió un atributo de pg_proc distinto del cuerpo, u otra función';
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
    raise exception 'pg_temp A2: cambiaron las dependencias de las funciones';
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
    raise exception 'pg_temp A2: el estado resultante no es el esperado (manifiesto)';
  end if;

  -- Sin privilegios transitorios.
  if (select coalesce(n.nspacl::pg_catalog.text, '') from pg_catalog.pg_namespace n
       where n.nspname = 'privado') is distinct from v_acl_privado
     or pg_catalog.has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'pg_temp A2: quedó un privilegio CREATE transitorio sobre privado';
  end if;

  -- Misma lista de SECURITY DEFINER.
  if (select pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::pg_catalog.text || '/'
                                   || p.proowner::pg_catalog.regrole::pg_catalog.text, ','
                                   order by p.oid::pg_catalog.regprocedure::pg_catalog.text)
        from pg_catalog.pg_proc p
       where p.prosecdef
         and p.pronamespace in ('public'::pg_catalog.regnamespace, 'privado'::pg_catalog.regnamespace))
       is distinct from v_definer then
    raise exception 'pg_temp A2: cambió la lista de funciones SECURITY DEFINER';
  end if;

  -- P11: EXECUTE de authenticated sólo en las 10 RPC; nunca anon ni service_role.
  for i in 1 .. 13 loop
    if pg_catalog.has_function_privilege('anon', v_oids[i], 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', v_oids[i], 'EXECUTE')
       or pg_catalog.has_function_privilege('authenticated', v_oids[i], 'EXECUTE')
          is distinct from (i operator(pg_catalog.>) 3) then
      raise exception 'pg_temp A2: EXECUTE fuera de lo aprobado en %', v_firmas[i];
    end if;
  end loop;

  -- Restaura el search_path de la sesión para el resto de la transacción.
  perform pg_catalog.set_config('search_path', v_search_path_previo, true);

  if pg_catalog.current_setting('search_path') is distinct from v_search_path_previo then
    raise exception 'pg_temp A2: no se pudo restaurar el search_path';
  end if;
end
$mig$;
