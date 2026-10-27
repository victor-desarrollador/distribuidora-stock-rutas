#!/usr/bin/env bash
# Arnés de D-R4 (ADR-005 §2.6) para la migración 20261027001542_modelo_peso_gramos.
# EXCLUSIVAMENTE LOCAL: reinicia la base local de Supabase y actúa sólo sobre
# su contenedor (docker exec, socket local, sin credenciales). Nunca apunta a
# staging ni a producción.
#
# Por qué es un arnés aparte: pgTAP corre después de todas las migraciones, y
# con el modelo nuevo ya no puede existir un producto `pieza`. Para probar que
# la migración falla cerrada hay que detener la base en la versión anterior,
# sembrar datos del modelo pieza/media pieza y aplicar la migración encima.
#
# Fase A: con un producto `pieza` y su movimiento en medias piezas, la
#         migración aborta con el error de D-R4 y no cambia nada (ni el
#         producto, ni su precio, ni su stock mínimo, ni el movimiento, ni las
#         restricciones ni las funciones).
# Fase B: con sólo productos `unidad`, la migración se aplica y no toca sus
#         datos.
# Al final reinicia la base local completa (migraciones + seed).
#
# Uso (desde la raíz del repositorio, con `supabase start` corriendo):
#   bash supabase/scripts/verificar_legado_pieza.sh

set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$raiz"

migracion="supabase/migrations/20261027001542_modelo_peso_gramos.sql"
version_previa="20261025033454"
proyecto="$(sed -n 's/^project_id *= *"\(.*\)"/\1/p' supabase/config.toml)"
contenedor="supabase_db_${proyecto}"

fallas=0
ok() { echo "PASS  $1"; }
mal() { echo "FAIL  $1"; fallas=$((fallas + 1)); }
psql_local() {
  docker exec -i "$contenedor" psql -X -q -At -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"
}

[ -f "$migracion" ] || { echo "No existe $migracion"; exit 2; }
docker ps --format '{{.Names}}' | grep -qx "$contenedor" \
  || { echo "El contenedor local $contenedor no está corriendo (supabase start)"; exit 2; }

# Datos del modelo anterior. Ids fijos para poder comparar.
sembrar() {
  local con_pieza="$1"
  psql_local <<SQL
insert into public.empresas (id, nombre)
values ('99999999-0000-4000-8000-0000000000e1', 'Legado (arnés D-R4)');
insert into auth.users (id, aud, role, email)
values ('99999999-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
        'legado.dueno@usuarios.distribuidora.invalid');
insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo)
values ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-0000000000e1',
        'legado.dueno', 'Dueño legado', 'dueno', true);
insert into public.ubicaciones (id, empresa_id, tipo)
values ('99999999-0000-4000-8000-0000000000d1', '99999999-0000-4000-8000-0000000000e1', 'deposito');

insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta,
                              precio, stock_minimo, creado_por)
values ('99999999-0000-4000-8000-0000000000f1', '99999999-0000-4000-8000-0000000000e1',
        'LEG-U', 'Leche legado', 'lacteos', 'unidad', 1600.00, 4,
        '99999999-0000-4000-8000-000000000001');
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella)
values ('99999999-0000-4000-8000-0000000000a1', '99999999-0000-4000-8000-0000000000e1',
        '99999999-0000-4000-8000-000000000001', 'ingreso',
        '99999999-0000-4000-8000-0000000000b1', repeat('a', 64));
insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id,
                                      cantidad, ubicacion_destino_id, actor_id)
values ('99999999-0000-4000-8000-0000000000e1', '99999999-0000-4000-8000-0000000000a1',
        'ingreso', '99999999-0000-4000-8000-0000000000f1', 7,
        '99999999-0000-4000-8000-0000000000d1', '99999999-0000-4000-8000-000000000001');
SQL
  if [ "$con_pieza" = "si" ]; then
    # Un jamón en el modelo anterior: precio de pieza completa, stock mínimo y
    # un ingreso de 9 medias piezas. Nada de esto puede leerse como gramos.
    psql_local <<SQL
insert into public.productos (id, empresa_id, codigo, nombre, categoria, forma_venta,
                              precio, stock_minimo, creado_por)
values ('99999999-0000-4000-8000-0000000000f2', '99999999-0000-4000-8000-0000000000e1',
        'LEG-P', 'Jamón legado', 'fiambres', 'pieza', 12500.00, 9,
        '99999999-0000-4000-8000-000000000001');
insert into public.operaciones (id, empresa_id, actor_id, tipo, idempotency_key, huella)
values ('99999999-0000-4000-8000-0000000000a2', '99999999-0000-4000-8000-0000000000e1',
        '99999999-0000-4000-8000-000000000001', 'ingreso',
        '99999999-0000-4000-8000-0000000000b2', repeat('b', 64));
insert into public.movimientos_stock (empresa_id, operacion_id, tipo_movimiento, producto_id,
                                      cantidad, ubicacion_destino_id, actor_id)
values ('99999999-0000-4000-8000-0000000000e1', '99999999-0000-4000-8000-0000000000a2',
        'ingreso', '99999999-0000-4000-8000-0000000000f2', 9,
        '99999999-0000-4000-8000-0000000000d1', '99999999-0000-4000-8000-000000000001');
SQL
  fi
}

# Huella de todo lo que la migración podría tocar: filas, restricciones,
# comentarios y la definición de crear_producto.
huella() {
  psql_local <<'SQL'
select md5(concat_ws('#',
  (select string_agg(p::text, '|' order by p.id) from public.productos p),
  (select string_agg(m::text, '|' order by m.id) from public.movimientos_stock m),
  (select string_agg(o::text, '|' order by o.id) from public.operaciones o),
  (select string_agg(conname || ':' || pg_get_constraintdef(oid), '|' order by conname)
     from pg_constraint where conrelid = 'public.productos'::regclass),
  (select string_agg(coalesce(col_description(attrelid, attnum), '-'), '|' order by attnum)
     from pg_attribute where attrelid = 'public.productos'::regclass and attnum > 0),
  col_description('public.movimientos_stock'::regclass,
    (select attnum from pg_attribute where attrelid = 'public.movimientos_stock'::regclass
        and attname = 'cantidad')),
  (select prosrc from pg_proc
    where oid = 'privado.crear_producto(text,text,text,text,numeric,integer)'::regprocedure)));
SQL
}

aplicar_migracion() {
  # Una sola transacción, como la aplica el CLI; ON_ERROR_STOP aborta y revierte.
  docker exec -i "$contenedor" psql -X -q -v ON_ERROR_STOP=1 -1 -U postgres -d postgres \
    < "$migracion"
}

reiniciar_previa() {
  npx supabase db reset --local --version "$version_previa" --no-seed > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
echo "== Fase A: datos pieza/media pieza presentes"
reiniciar_previa
sembrar si
antes="$(huella)"

set +e
salida="$(aplicar_migracion 2>&1)"
rc=$?
set -e

if [ "$rc" -ne 0 ]; then ok "la migración falla (rc=$rc)"; else mal "la migración se aplicó con datos pieza"; fi
if grep -q "modelo_peso_gramos: 1 producto(s) del modelo pieza/media pieza y 1 movimiento(s) asociados" <<<"$salida"; then
  ok "el error es el de la guarda D-R4"
else
  mal "error inesperado: $salida"
fi
if grep -q "D-R4" <<<"$salida"; then ok "el hint cita D-R4"; else mal "el hint no cita D-R4"; fi

despues="$(huella)"
if [ "$antes" = "$despues" ]; then
  ok "filas, restricciones, comentarios y crear_producto quedaron idénticos"
else
  mal "la base cambió tras el intento fallido"
fi

estado="$(psql_local <<'SQL'
select concat_ws(',',
  (select forma_venta || '/' || precio || '/' || stock_minimo from public.productos
    where id = '99999999-0000-4000-8000-0000000000f2'),
  (select cantidad from public.movimientos_stock
    where producto_id = '99999999-0000-4000-8000-0000000000f2'),
  (select count(*) from public.productos where forma_venta = 'peso'),
  (select position('''pieza''' in pg_get_constraintdef(oid)) > 0 from pg_constraint
    where conrelid = 'public.productos'::regclass and conname = 'productos_forma_venta_valida'),
  (select position('''pieza''' in prosrc) > 0 from pg_proc
    where oid = 'privado.crear_producto(text,text,text,text,numeric,integer)'::regprocedure));
SQL
)"
if [ "$estado" = "pieza/12500.00/9,9,0,t,t" ]; then
  ok "el producto sigue pieza, precio 12500.00 y stock mínimo 9; el movimiento sigue en 9; no hay productos peso; restricciones y RPC del modelo anterior"
else
  mal "estado inesperado tras el intento: $estado"
fi

# ---------------------------------------------------------------------------
echo "== Fase B: sólo productos unidad"
reiniciar_previa
sembrar no
datos_unidad() {
  psql_local <<'SQL'
select md5(concat_ws('#',
  (select string_agg(p::text, '|' order by p.id) from public.productos p),
  (select string_agg(m::text, '|' order by m.id) from public.movimientos_stock m),
  (select string_agg(o::text, '|' order by o.id) from public.operaciones o)));
SQL
}
antes="$(datos_unidad)"

set +e
salida="$(aplicar_migracion 2>&1)"
rc=$?
set -e

if [ "$rc" -eq 0 ]; then ok "la migración se aplica sin datos pieza"; else mal "la migración falló sin datos pieza: $salida"; fi
if [ "$antes" = "$(datos_unidad)" ]; then ok "los datos unidad no cambiaron"; else mal "los datos unidad cambiaron"; fi
nuevo="$(psql_local <<'SQL'
select position('''peso''' in pg_get_constraintdef(oid)) > 0
       and position('pieza' in pg_get_constraintdef(oid)) = 0
  from pg_constraint
 where conrelid = 'public.productos'::regclass and conname = 'productos_forma_venta_valida';
SQL
)"
if [ "$nuevo" = "t" ]; then ok "la restricción nueva admite unidad | peso"; else mal "restricción inesperada"; fi

# ---------------------------------------------------------------------------
echo "== Restaurando la base local completa (migraciones + seed)"
npx supabase db reset --local > /dev/null 2>&1

if [ "$fallas" -eq 0 ]; then
  echo "RESULTADO: PASS"
else
  echo "RESULTADO: FAIL ($fallas)"
  exit 1
fi
