-- Modelo por peso, Slice A (Blueprint v2.2 §2, §7.1, §8; ADR-005 v1.1 §2.1,
-- §2.2, §2.3.1 y §2.6 D-R4; ADR-001 Topología D, P11, O-3).
--
-- Cambia la forma de venta vigente de `unidad | pieza` a `unidad | peso`:
--   - lacteos  + unidad: cantidad canónica en unidades enteras; precio unitario.
--   - fiambres + peso:   cantidad canónica en gramos enteros; precio por kg.
-- No existen la pieza ni la media pieza.
--
-- Tipos sin cambios: `productos.precio numeric(14,2)`, `productos.stock_minimo
-- integer` y `movimientos_stock.cantidad integer`. Lo que cambia es la
-- semántica: el entero está en la unidad mínima del producto (unidades o
-- gramos) y la `forma_venta` del producto la determina. No hay kg ni
-- decimales en la base; la conversión kg → gramos ocurre en la frontera de
-- entrada: la pantalla Productos ya la implementa en Slice A y el resto de
-- los flujos operativos queda para Slice B. Las RPC de stock conservan sus
-- firmas (`p_cantidad integer`) y no cambian: ya reciben el entero canónico.
--
-- D-R4 (reinicio limpio): esta migración NO convierte ni reinterpreta datos
-- del modelo anterior. Si existe algún producto `pieza` (y, con él, sus
-- movimientos en medias piezas), aborta sin modificar nada. No borra, no
-- normaliza y no cambia precios ni stock mínimo.
--
-- D-R1 no se implementa acá: el catálogo guarda el precio, no importes de
-- línea. Fuera de alcance: frontend/demo, carga, ventas, rendición,
-- presupuestos y el redondeo de líneas `unidad` (pendiente, ADR-005 §5).
--
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

-- ---------------------------------------------------------------------------
-- Guarda fail-closed (D-R4)
-- ---------------------------------------------------------------------------
-- El lock impide que entre un producto `pieza` entre la comprobación y el
-- reemplazo de las restricciones. Aun sin él, la restricción nueva se valida
-- contra las filas existentes y fallaría.
do $$
declare
  v_productos bigint;
  v_movimientos bigint;
begin
  if current_user <> 'postgres' then
    raise exception
      'las migraciones deben ejecutarse como postgres; actual: %', current_user;
  end if;

  lock table public.productos in access exclusive mode;
  lock table public.movimientos_stock in share mode;

  -- Antes de esta migración sólo podían existir `unidad` y `pieza`: todo lo
  -- que no es `unidad` pertenece al modelo anterior.
  select count(*) into v_productos
    from public.productos
   where forma_venta <> 'unidad';

  select count(*) into v_movimientos
    from public.movimientos_stock m
    join public.productos p
      on p.empresa_id = m.empresa_id and p.id = m.producto_id
   where p.forma_venta <> 'unidad';

  if v_productos > 0 then
    raise exception
      'modelo_peso_gramos: % producto(s) del modelo pieza/media pieza y % movimiento(s) asociados',
      v_productos, v_movimientos
      using hint = 'ADR-005 D-R4: no se convierten ni se reinterpretan como gramos. '
                   'Se requiere un reinicio limpio de los datos de local/staging; '
                   'esta migración no modificó nada.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- productos: forma de venta `unidad | peso`
-- ---------------------------------------------------------------------------
-- Se conservan los nombres de las restricciones: el mapeo de errores
-- (privado.error_restriccion_producto) no cambia.
alter table public.productos
  drop constraint productos_forma_venta_valida,
  drop constraint productos_combinacion_valida,
  add constraint productos_forma_venta_valida
    check (forma_venta in ('unidad', 'peso')),
  add constraint productos_combinacion_valida
    check ((categoria = 'lacteos' and forma_venta = 'unidad')
        or (categoria = 'fiambres' and forma_venta = 'peso'));

comment on column public.productos.forma_venta is
  'unidad | peso (ADR-005). Inmutable: determina la unidad mínima de todas las cantidades del producto (unidad → unidades enteras; peso → gramos enteros).';
comment on column public.productos.precio is
  'Precio unitario (unidad) o precio por kg (peso), exacto en numeric(14,2): >= 0 y a lo sumo 2 decimales (ADR-005 §2.1, §2.3.1).';
comment on column public.productos.stock_minimo is
  'Entero >= 0 en unidad mínima: unidades enteras (unidad) o gramos enteros (peso) (ADR-005 §2.2).';

comment on column public.movimientos_stock.cantidad is
  'Entero > 0 en la unidad mínima del producto según productos.forma_venta: unidades (unidad) o gramos (peso). Nunca kg ni decimales (ADR-005 §2.2).';
comment on view public.stock_actual is
  'Saldo por empresa, ubicación y producto = entradas - salidas de movimientos_stock, en la unidad mínima del producto: unidades o gramos (Blueprint §7.4, §8 saldos_stock [DERIVADA]; ADR-005 §2.2).';

-- ---------------------------------------------------------------------------
-- crear_producto: valida `peso` en lugar de `pieza`
-- ---------------------------------------------------------------------------
-- Misma firma: CREATE OR REPLACE conserva owner y ACL. O-3: postgres no
-- hereda los privilegios de propietario_rpc; para redefinir la función se
-- actúa como su owner, con CREATE temporal sobre privado.
grant create on schema privado to propietario_rpc;
set role propietario_rpc;

create or replace function privado.crear_producto(
  p_codigo text,
  p_nombre text,
  p_categoria text,
  p_forma_venta text,
  p_precio numeric,
  p_stock_minimo integer
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa uuid := privado.exigir_gestor_productos();
  v_id uuid;
  v_restriccion text;
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
end $$;

reset role;
revoke create on schema privado from propietario_rpc;

comment on function public.crear_producto(text, text, text, text, numeric, integer) is
  'Alta de producto (dueño/encargado). p_forma_venta: unidad (lacteos) o peso (fiambres). p_precio: unitario o por kg, a lo sumo 2 decimales. p_stock_minimo: entero en unidades o gramos.';

-- ---------------------------------------------------------------------------
-- Verificación fail-closed
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from public.productos
              where forma_venta not in ('unidad', 'peso')) then
    raise exception 'modelo_peso_gramos: quedaron productos fuera de unidad | peso';
  end if;

  if (select count(*) from pg_constraint
       where conrelid = 'public.productos'::regclass
         and conname in ('productos_forma_venta_valida', 'productos_combinacion_valida')
         and convalidated
         and position('pieza' in pg_get_constraintdef(oid)) = 0
         and position('''peso''' in pg_get_constraintdef(oid)) > 0) <> 2 then
    raise exception 'modelo_peso_gramos: restricciones de forma de venta fuera de lo aprobado';
  end if;

  if (select format_type(atttypid, atttypmod) from pg_attribute
       where attrelid = 'public.productos'::regclass and attname = 'precio') <> 'numeric(14,2)'
     or (select format_type(atttypid, atttypmod) from pg_attribute
          where attrelid = 'public.productos'::regclass and attname = 'stock_minimo') <> 'integer'
     or (select format_type(atttypid, atttypmod) from pg_attribute
          where attrelid = 'public.movimientos_stock'::regclass and attname = 'cantidad') <> 'integer' then
    raise exception 'modelo_peso_gramos: tipos de precio, stock_minimo o cantidad fuera de lo aprobado';
  end if;

  if not exists (
       select 1 from pg_proc p
        where p.oid = 'privado.crear_producto(text,text,text,text,numeric,integer)'::regprocedure
          and p.prosecdef
          and p.proowner = 'propietario_rpc'::regrole
          and p.proconfig @> array['search_path=""']
          and position('pieza' in p.prosrc) = 0
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/propietario_rpc', 'propietario_rpc=X/propietario_rpc'])
     or not exists (
       select 1 from pg_proc p
        where p.oid = 'public.crear_producto(text,text,text,text,numeric,integer)'::regprocedure
          and not p.prosecdef
          and p.proowner = 'postgres'::regrole
          and p.proconfig @> array['search_path=""']
          and array(select a::text from unnest(p.proacl) a order by 1)
              = array['authenticated=X/postgres', 'postgres=X/postgres'])
     or (select count(*) from pg_proc
          where proname = 'crear_producto'
            and pronamespace in ('public'::regnamespace, 'privado'::regnamespace)) <> 2
     or has_schema_privilege('propietario_rpc', 'privado', 'CREATE') then
    raise exception 'crear_producto: seguridad, owner, search_path, ACL o sobrecargas fuera de lo aprobado';
  end if;

  -- Inmutabilidad de categoria/forma_venta y P11 sobre productos.
  if has_any_column_privilege('authenticated', 'public.productos', 'INSERT, UPDATE, REFERENCES')
     or has_table_privilege('authenticated', 'public.productos',
          'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     or has_column_privilege('propietario_rpc', 'public.productos', 'categoria', 'UPDATE')
     or has_column_privilege('propietario_rpc', 'public.productos', 'forma_venta', 'UPDATE')
     or has_table_privilege('service_role', 'public.productos',
          'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     or has_any_column_privilege('service_role', 'public.productos', 'INSERT, UPDATE, REFERENCES')
     or not has_table_privilege('service_role', 'public.productos', 'SELECT')
     or not (select relrowsecurity and not relforcerowsecurity
               from pg_class where oid = 'public.productos'::regclass) then
    raise exception 'productos: RLS o grants fuera de lo aprobado';
  end if;
end $$;
