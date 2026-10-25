-- pgTAP: ubicaciones internas de stock (Blueprint §7.2, §7.3, §8, §9, §10,
-- §12 Seguridad; ADR-001 Topología D, P11 y O-3; decisiones humanas D1–D6 del
-- slice ubicaciones). Ejecutar sólo en local: `supabase test db`.
--
-- Se usan dos empresas EXCLUSIVAMENTE para demostrar aislamiento: la empresa B
-- es un fixture adversarial, no un producto multiempresa.

begin;

create extension if not exists pgtap with schema extensions;

select plan(82);

-- ---------------------------------------------------------------------------
-- Datos de prueba (como owner; se revierten al final)
-- ---------------------------------------------------------------------------
insert into public.empresas (id, nombre) values
  ('aaaaaaaa-0000-4000-8000-000000000000', 'Empresa A (test)'),
  ('bbbbbbbb-0000-4000-8000-000000000000', 'Empresa B (test)');

insert into auth.users (id, aud, role, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'ubi.a1@usuarios.distribuidora.invalid', '{}'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'ubi.a2@usuarios.distribuidora.invalid', '{}'),
  -- A3: vendedor con metadata que pretende ser dueño de B
  ('aaaaaaaa-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'ubi.a3@usuarios.distribuidora.invalid',
   '{"rol":"dueno","empresa_id":"bbbbbbbb-0000-4000-8000-000000000000"}'),
  -- A4: dueño INACTIVO
  ('aaaaaaaa-0000-4000-8000-000000000004', 'authenticated', 'authenticated',
   'ubi.a4@usuarios.distribuidora.invalid', '{}'),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'ubi.b1@usuarios.distribuidora.invalid', '{}'),
  -- N1: cuenta Auth sin perfil, con metadata falsa
  ('cccccccc-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'ubi.n1@usuarios.distribuidora.invalid',
   '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000000',
   'ubi.a1', 'A1', 'dueno', true),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000000',
   'ubi.a2', 'A2', 'encargado', true),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000000',
   'ubi.a3', 'A3', 'vendedor_piloto', true),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000000',
   'ubi.a4', 'A4', 'dueno', false),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000000',
   'ubi.b1', 'B1', 'dueno', true);

-- Camiones preexistentes (como si existieran antes de la migración):
-- ca1 de A y cb1 de B se cubren con el backfill; ca2 y cb2 quedan sin
-- ubicación para probar la policy de propietario_rpc.
insert into public.camiones (id, empresa_id, patente, nombre, creado_por) values
  ('aaaaaaaa-0000-4000-8000-0000000000a1', 'aaaaaaaa-0000-4000-8000-000000000000',
   'UB-A1', 'Camión A1', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('bbbbbbbb-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-000000000000',
   'UB-B1', 'Camión B1', 'bbbbbbbb-0000-4000-8000-000000000001');

-- Backfill: mismas sentencias que la migración 20261025010315 (D1, D2).
insert into public.ubicaciones (empresa_id, tipo)
select e.id, t.tipo
  from public.empresas e
 cross join (values ('deposito'), ('cuarentena')) as t (tipo)
on conflict (empresa_id, tipo) where camion_id is null do nothing;

insert into public.ubicaciones (empresa_id, tipo, camion_id)
select c.empresa_id, 'camion', c.id
  from public.camiones c
on conflict (empresa_id, camion_id) do nothing;

insert into public.camiones (id, empresa_id, patente, nombre, creado_por) values
  ('aaaaaaaa-0000-4000-8000-0000000000a2', 'aaaaaaaa-0000-4000-8000-000000000000',
   'UB-A2', 'Camión A2', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('bbbbbbbb-0000-4000-8000-0000000000b2', 'bbbbbbbb-0000-4000-8000-000000000000',
   'UB-B2', 'Camión B2', 'bbbbbbbb-0000-4000-8000-000000000001');

create function pg_temp.como_usuario(uid uuid, metadata jsonb default '{}')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated',
                       'user_metadata', metadata)::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.como_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
end $$;

grant execute on function pg_temp.como_usuario(uuid, jsonb) to public;
grant execute on function pg_temp.como_anon() to public;

create temp table ids (clave text, id uuid);
insert into ids
select 'a_deposito', id from public.ubicaciones
 where empresa_id = 'aaaaaaaa-0000-4000-8000-000000000000' and tipo = 'deposito'
union all
select 'b_deposito', id from public.ubicaciones
 where empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000' and tipo = 'deposito';
grant select, insert on ids to public;

create temp table ubic_a as
  select id from public.ubicaciones
   where empresa_id = 'aaaaaaaa-0000-4000-8000-000000000000';
create temp table ubic_b as
  select id from public.ubicaciones
   where empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000';
grant select on ubic_a, ubic_b to public;

-- ---------------------------------------------------------------------------
-- Backfill
-- ---------------------------------------------------------------------------
select results_eq(
  $$select e.id, (select count(*)::int from public.ubicaciones u where u.empresa_id = e.id and u.tipo = 'deposito'),
                 (select count(*)::int from public.ubicaciones u where u.empresa_id = e.id and u.tipo = 'cuarentena')
      from public.empresas e
     where e.id in ('aaaaaaaa-0000-4000-8000-000000000000', 'bbbbbbbb-0000-4000-8000-000000000000')
     order by e.id$$,
  $$values ('aaaaaaaa-0000-4000-8000-000000000000'::uuid, 1, 1),
           ('bbbbbbbb-0000-4000-8000-000000000000'::uuid, 1, 1)$$,
  'backfill: cada empresa tiene exactamente un depósito y una cuarentena');

select results_eq(
  $$select c.id, (select count(*)::int from public.ubicaciones u
                   where u.camion_id = c.id and u.tipo = 'camion' and u.empresa_id = c.empresa_id)
      from public.camiones c
     where c.id in ('aaaaaaaa-0000-4000-8000-0000000000a1', 'bbbbbbbb-0000-4000-8000-0000000000b1')
     order by c.id$$,
  $$values ('aaaaaaaa-0000-4000-8000-0000000000a1'::uuid, 1),
           ('bbbbbbbb-0000-4000-8000-0000000000b1'::uuid, 1)$$,
  'backfill: cada camión existente tiene exactamente una ubicación de su empresa');

create temp table conteo_backfill as select count(*)::int as n from public.ubicaciones;
insert into public.ubicaciones (empresa_id, tipo)
select e.id, t.tipo
  from public.empresas e
 cross join (values ('deposito'), ('cuarentena')) as t (tipo)
on conflict (empresa_id, tipo) where camion_id is null do nothing;
insert into public.ubicaciones (empresa_id, tipo, camion_id)
select c.empresa_id, 'camion', c.id
  from public.camiones c
 where c.id in ('aaaaaaaa-0000-4000-8000-0000000000a1', 'bbbbbbbb-0000-4000-8000-0000000000b1')
on conflict (empresa_id, camion_id) do nothing;
select is((select count(*)::int from public.ubicaciones), (select n from conteo_backfill),
  'backfill repetido: no duplica ninguna fila');

select is(
  (select count(*)::int from public.empresas e
    where (select count(*) from public.ubicaciones u where u.empresa_id = e.id and u.tipo = 'deposito') <> 1
       or (select count(*) from public.ubicaciones u where u.empresa_id = e.id and u.tipo = 'cuarentena') <> 1),
  0,
  'toda empresa de la base (seed y fixtures) tiene exactamente un depósito y una cuarentena');

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_table('public', 'ubicaciones', 'la tabla public.ubicaciones existe');

select is(
  array(select a.attname::text || ':' || format_type(a.atttypid, a.atttypmod)
               || ':' || a.attnotnull::text
               || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-')
          from pg_attribute a
          left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
         where a.attrelid = 'public.ubicaciones'::regclass
           and a.attnum > 0 and not a.attisdropped
         order by a.attnum),
  array['id:uuid:true:gen_random_uuid()',
        'empresa_id:uuid:true:-',
        'tipo:text:true:-',
        'camion_id:uuid:false:-',
        'creado_en:timestamp with time zone:true:now()'],
  'columnas, tipos, NOT NULL y defaults aprobados');

select is(
  (select count(*)::int from pg_attribute
    where attrelid = 'public.ubicaciones'::regclass and not attisdropped
      and attname in ('nombre', 'activo', 'saldo_actual', 'creado_por')),
  0,
  'sin nombre, activo, saldo_actual ni creado_por (D3, D5)');

select is(
  array(select conname::text || ':' || pg_get_constraintdef(oid) from pg_constraint
         where conrelid = 'public.ubicaciones'::regclass order by conname::text),
  array['ubicaciones_camion_coherente:CHECK (((tipo = ''camion''::text) = (camion_id IS NOT NULL)))',
        'ubicaciones_camion_fk:FOREIGN KEY (empresa_id, camion_id) REFERENCES camiones(empresa_id, id) ON DELETE RESTRICT',
        'ubicaciones_camion_unico:UNIQUE (empresa_id, camion_id)',
        'ubicaciones_empresa_id_fkey:FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE RESTRICT',
        'ubicaciones_empresa_id_unico:UNIQUE (empresa_id, id)',
        'ubicaciones_pkey:PRIMARY KEY (id)',
        'ubicaciones_tipo_valido:CHECK ((tipo = ANY (ARRAY[''deposito''::text, ''cuarentena''::text, ''camion''::text])))'],
  'constraints exactas: PK, FK a empresas, FK compuesta a camiones, UNIQUE (empresa_id, id) y (empresa_id, camion_id), CHECK de tipo y de coherencia');

select is(
  (select pg_get_indexdef('public.ubicaciones_fija_unica'::regclass)),
  'CREATE UNIQUE INDEX ubicaciones_fija_unica ON public.ubicaciones USING btree (empresa_id, tipo) WHERE (camion_id IS NULL)',
  'índice único parcial de ubicaciones fijas');

select is(
  array(select i.indexrelid::regclass::text from pg_index i
         where i.indrelid = 'public.ubicaciones'::regclass and i.indisunique
         order by 1),
  array['ubicaciones_camion_unico', 'ubicaciones_empresa_id_unico',
        'ubicaciones_fija_unica', 'ubicaciones_pkey'],
  'no hay otras unicidades');

select is(
  (select relowner::regrole::text from pg_class where oid = 'public.ubicaciones'::regclass),
  'postgres',
  'ubicaciones pertenece al owner de las migraciones (no a propietario_rpc)');

select ok(
  (select relrowsecurity and not relforcerowsecurity
     from pg_class where oid = 'public.ubicaciones'::regclass),
  'ubicaciones tiene RLS habilitada y sin FORCE (P4)');

select is(
  array(select policyname || ':' || cmd || ':' || array_to_string(roles, ',')
          from pg_policies where schemaname = 'public' and tablename = 'ubicaciones'
         order by policyname),
  array['ubicaciones_insert_propietario_rpc:INSERT:propietario_rpc',
        'ubicaciones_select_empresa:SELECT:authenticated',
        'ubicaciones_select_propietario_rpc:SELECT:propietario_rpc'],
  'policies exactas: SELECT de authenticated; SELECT e INSERT de propietario_rpc; sin UPDATE ni DELETE');

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
select ok(
  has_table_privilege('authenticated', 'public.ubicaciones', 'SELECT')
  and not has_table_privilege('authenticated', 'public.ubicaciones',
        'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
  and not has_any_column_privilege('authenticated', 'public.ubicaciones', 'INSERT, UPDATE, REFERENCES'),
  'authenticated sólo tiene SELECT (ni por columna)');

select ok(
  not has_table_privilege('anon', 'public.ubicaciones',
        'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
  and not has_any_column_privilege('anon', 'public.ubicaciones', 'SELECT, INSERT, UPDATE, REFERENCES'),
  'anon no tiene ningún privilegio (ni por columna)');

select ok(
  not has_table_privilege('service_role', 'public.ubicaciones',
        'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
  and not has_any_column_privilege('service_role', 'public.ubicaciones', 'SELECT, INSERT, UPDATE, REFERENCES'),
  'service_role no tiene ningún privilegio (P11, sin excepción nueva)');

select ok(
  not exists (select 1 from pg_class c, aclexplode(c.relacl) a
               where c.oid = 'public.ubicaciones'::regclass and a.grantee = 0),
  'PUBLIC no tiene privilegios sobre ubicaciones');

select is(
  array(select a.attname::text from pg_attribute a
         where a.attrelid = 'public.ubicaciones'::regclass and a.attnum > 0 and not a.attisdropped
           and has_column_privilege('propietario_rpc', 'public.ubicaciones', a.attname, 'INSERT')
         order by 1),
  array['camion_id', 'empresa_id', 'tipo'],
  'propietario_rpc inserta sólo empresa_id, tipo y camion_id');

select ok(
  has_table_privilege('propietario_rpc', 'public.ubicaciones', 'SELECT')
  and not has_table_privilege('propietario_rpc', 'public.ubicaciones',
        'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
  and not has_any_column_privilege('propietario_rpc', 'public.ubicaciones', 'UPDATE, REFERENCES'),
  'propietario_rpc lee y no actualiza, borra, trunca ni referencia (D5)');

-- ---------------------------------------------------------------------------
-- Restricciones (como owner: defensa aunque se saltee RLS)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo) values ('aaaaaaaa-0000-4000-8000-000000000000', 'camion')$$,
  '23514', null, 'una ubicación camion sin camion_id se rechaza');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'deposito', 'aaaaaaaa-0000-4000-8000-0000000000a2')$$,
  '23514', null, 'un depósito con camion_id se rechaza');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'cuarentena', 'aaaaaaaa-0000-4000-8000-0000000000a2')$$,
  '23514', null, 'una cuarentena con camion_id se rechaza');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo) values ('aaaaaaaa-0000-4000-8000-000000000000', 'merma')$$,
  '23514', null, 'merma no es una ubicación');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo) values ('aaaaaaaa-0000-4000-8000-000000000000', 'cliente')$$,
  '23514', null, 'cliente no es una ubicación');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo) values ('aaaaaaaa-0000-4000-8000-000000000000', 'deposito')$$,
  '23505', null, 'un segundo depósito en la misma empresa se rechaza');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo) values ('aaaaaaaa-0000-4000-8000-000000000000', 'cuarentena')$$,
  '23505', null, 'una segunda cuarentena en la misma empresa se rechaza');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'camion', 'aaaaaaaa-0000-4000-8000-0000000000a1')$$,
  '23505', null, 'una segunda ubicación para el mismo camión se rechaza');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'camion', 'bbbbbbbb-0000-4000-8000-0000000000b2')$$,
  '23503', null, 'una ubicación de A no puede apuntar a un camión de B');

-- ---------------------------------------------------------------------------
-- Lectura por empresa y estado del perfil (D4)
-- ---------------------------------------------------------------------------
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select set_eq($$select id from public.ubicaciones$$, $$select id from ubic_a$$,
  'el dueño lee todas las ubicaciones de su empresa');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select set_eq($$select id from public.ubicaciones$$, $$select id from ubic_a$$,
  'el encargado lee todas las ubicaciones de su empresa');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003',
  '{"rol":"dueno","empresa_id":"bbbbbbbb-0000-4000-8000-000000000000"}');
select set_eq($$select id from public.ubicaciones$$, $$select id from ubic_a$$,
  'el vendedor (con metadata de dueño de B) lee sólo las ubicaciones de su empresa');
select is(
  (select count(*)::int from public.ubicaciones
    where id = (select id from ids where clave = 'b_deposito')),
  0,
  'el vendedor de A no ve el depósito de B ni pidiéndolo por id');
select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select set_eq($$select id from public.ubicaciones$$, $$select id from ubic_b$$,
  'el dueño de B sólo ve las ubicaciones de B');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000004');
select is((select count(*)::int from public.ubicaciones), 0,
  'un perfil inactivo no ve ubicaciones');
select pg_temp.como_usuario('cccccccc-0000-4000-8000-000000000001',
  '{"rol":"dueno","empresa_id":"aaaaaaaa-0000-4000-8000-000000000000"}');
select is((select count(*)::int from public.ubicaciones), 0,
  'una cuenta sin perfil no ve ubicaciones, aunque su metadata diga dueño de A');
select pg_temp.como_anon();
select throws_ok('select count(*) from public.ubicaciones', '42501', null,
  'anon no puede leer ubicaciones');
reset role;

-- ---------------------------------------------------------------------------
-- Escritura directa: nadie de la Data API escribe la tabla
-- ---------------------------------------------------------------------------
create temp table huella as
  select md5(string_agg(u::text, '|' order by u.id)) as h from public.ubicaciones u;
grant select on huella to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'camion', 'aaaaaaaa-0000-4000-8000-0000000000a2')$$,
  '42501', null, 'el dueño no inserta directamente');
select throws_ok($$update public.ubicaciones set tipo = 'cuarentena'$$,
  '42501', null, 'el dueño no actualiza directamente');
select throws_ok($$delete from public.ubicaciones$$,
  '42501', null, 'el dueño no borra ubicaciones');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'camion', 'aaaaaaaa-0000-4000-8000-0000000000a2')$$,
  '42501', null, 'el encargado no inserta directamente');
select throws_ok($$update public.ubicaciones set camion_id = null$$,
  '42501', null, 'el encargado no actualiza directamente');
select throws_ok($$delete from public.ubicaciones$$,
  '42501', null, 'el encargado no borra ubicaciones');

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003',
  '{"rol":"dueno","empresa_id":"bbbbbbbb-0000-4000-8000-000000000000"}');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo) values ('aaaaaaaa-0000-4000-8000-000000000000', 'deposito')$$,
  '42501', null, 'el vendedor no inserta directamente');
select throws_ok($$update public.ubicaciones set empresa_id = 'bbbbbbbb-0000-4000-8000-000000000000'$$,
  '42501', null, 'el vendedor no mueve ubicaciones de empresa');
select throws_ok($$delete from public.ubicaciones$$,
  '42501', null, 'el vendedor no borra ubicaciones');

select pg_temp.como_anon();
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo) values ('aaaaaaaa-0000-4000-8000-000000000000', 'deposito')$$,
  '42501', null, 'anon no inserta');
select throws_ok($$update public.ubicaciones set tipo = 'deposito'$$, '42501', null, 'anon no actualiza');
select throws_ok($$delete from public.ubicaciones$$, '42501', null, 'anon no borra');
reset role;

grant usage on schema extensions to service_role;
set local role service_role;
select throws_ok('select count(*) from public.ubicaciones', '42501', null,
  'service_role no lee ubicaciones (P11)');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo) values ('aaaaaaaa-0000-4000-8000-000000000000', 'deposito')$$,
  '42501', null, 'service_role no inserta');
select throws_ok($$update public.ubicaciones set tipo = 'deposito' where true$$, '42501', null,
  'service_role no actualiza');
select throws_ok($$delete from public.ubicaciones$$, '42501', null, 'service_role no borra');
reset role;

select is((select md5(string_agg(u::text, '|' order by u.id)) from public.ubicaciones u),
  (select h from huella),
  'ningún intento de escritura directa cambió ubicaciones');

-- ---------------------------------------------------------------------------
-- propietario_rpc: limitado por grants y RLS
-- ---------------------------------------------------------------------------
grant usage on schema extensions to propietario_rpc;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role propietario_rpc;

select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo) values ('aaaaaaaa-0000-4000-8000-000000000000', 'deposito')$$,
  '42501', null, 'RLS impide a propietario_rpc crear un depósito');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo) values ('aaaaaaaa-0000-4000-8000-000000000000', 'cuarentena')$$,
  '42501', null, 'RLS impide a propietario_rpc crear una cuarentena');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values ('bbbbbbbb-0000-4000-8000-000000000000', 'camion', 'bbbbbbbb-0000-4000-8000-0000000000b2')$$,
  '42501', null, 'RLS impide a propietario_rpc crear la ubicación de un camión de otra empresa');
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'camion', 'bbbbbbbb-0000-4000-8000-0000000000b2')$$,
  '42501', null, 'RLS impide a propietario_rpc apuntar a un camión de otra empresa desde la propia');
select throws_ok($$update public.ubicaciones set tipo = 'deposito'$$, '42501', null,
  'propietario_rpc no actualiza ubicaciones');
select throws_ok($$delete from public.ubicaciones$$, '42501', null,
  'propietario_rpc no borra ubicaciones');
select lives_ok(
  $$insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'camion', 'aaaaaaaa-0000-4000-8000-0000000000a2')$$,
  'con identidad de dueño, propietario_rpc crea la ubicación de un camión propio (control positivo)');

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000003","role":"authenticated"}', true);
select throws_ok(
  $$insert into public.ubicaciones (empresa_id, tipo, camion_id)
    values ('aaaaaaaa-0000-4000-8000-000000000000', 'camion', 'aaaaaaaa-0000-4000-8000-0000000000a2')$$,
  '42501', null, 'RLS impide a propietario_rpc crear ubicaciones en nombre de un vendedor');
reset role;

-- ---------------------------------------------------------------------------
-- crear_camion: camión y ubicación en la misma transacción (D2)
-- ---------------------------------------------------------------------------
create temp table creados (clave text, id uuid);
grant select, insert on creados to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$insert into creados select 'nuevo', public.crear_camion('  UB-N1  ', '  Camión nuevo  ')$$,
  'el dueño crea un camión');
reset role;

select results_eq(
  $$select c.empresa_id, c.patente, c.nombre, c.activo, c.creado_por
      from public.camiones c join creados x on x.id = c.id where x.clave = 'nuevo'$$,
  $$values ('aaaaaaaa-0000-4000-8000-000000000000'::uuid, 'UB-N1', 'Camión nuevo', true,
            'aaaaaaaa-0000-4000-8000-000000000001'::uuid)$$,
  'el camión mantiene el comportamiento vigente (trim, empresa y autor del servidor)');

select results_eq(
  $$select u.empresa_id, u.tipo, count(*) over ()::int
      from public.ubicaciones u join creados x on x.id = u.camion_id where x.clave = 'nuevo'$$,
  $$values ('aaaaaaaa-0000-4000-8000-000000000000'::uuid, 'camion', 1)$$,
  'crear_camion crea exactamente una ubicación camion, de la misma empresa');

create temp table huella_cc as
  select (select count(*)::int from public.camiones) as camiones,
         (select count(*)::int from public.ubicaciones) as ubicaciones;
grant select on huella_cc to public;

select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok($$select public.crear_camion('UB-N1', 'Repetido')$$,
  'PT409', 'camion_patente_duplicada', 'patente duplicada: mismo error que antes');
select throws_ok($$select public.crear_camion('', 'X')$$,
  'PT400', 'camion_patente_invalida', 'patente vacía: mismo error que antes');
select throws_ok($$select public.crear_camion('UB-X1', '  ')$$,
  'PT400', 'camion_nombre_invalido', 'nombre vacío: mismo error que antes');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000002');
select throws_ok($$select public.crear_camion('UB-E1', 'Encargado')$$,
  'PT403', 'camion_no_autorizado', 'el encargado no crea camiones');
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000003',
  '{"rol":"dueno","empresa_id":"bbbbbbbb-0000-4000-8000-000000000000"}');
select throws_ok($$select public.crear_camion('UB-V1', 'Vendedor')$$,
  'PT403', 'camion_no_autorizado', 'el vendedor no crea camiones (metadata ignorada)');
reset role;

select results_eq(
  $$select (select count(*)::int from public.camiones), (select count(*)::int from public.ubicaciones)$$,
  $$select camiones, ubicaciones from huella_cc$$,
  'ningún intento fallido dejó camiones parciales ni ubicaciones huérfanas');

-- Si falla la ubicación, tampoco queda el camión (misma transacción).
revoke insert (empresa_id, tipo, camion_id) on table public.ubicaciones from propietario_rpc;
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select throws_ok($$select public.crear_camion('UB-AT1', 'Atómico')$$,
  '42501', null, 'si el alta de la ubicación falla, la RPC falla');
reset role;
grant insert (empresa_id, tipo, camion_id) on table public.ubicaciones to propietario_rpc;
select is((select count(*)::int from public.camiones where patente = 'UB-AT1'), 0,
  'y el camión no quedó persistido (sin camión parcial)');

-- Cambios de estado: la ubicación se conserva, sin duplicarse.
select pg_temp.como_usuario('aaaaaaaa-0000-4000-8000-000000000001');
select lives_ok(
  $$select public.cambiar_estado_camion((select id from creados where clave = 'nuevo'), false)$$,
  'el dueño desactiva el camión');
select lives_ok(
  $$select public.cambiar_estado_camion((select id from creados where clave = 'nuevo'), false)$$,
  'repetir la desactivación no falla');
select lives_ok(
  $$select public.cambiar_estado_camion((select id from creados where clave = 'nuevo'), true)$$,
  'el dueño reactiva el camión');
reset role;
select results_eq(
  $$select c.activo, (select count(*)::int from public.ubicaciones u where u.camion_id = c.id)
      from public.camiones c join creados x on x.id = c.id where x.clave = 'nuevo'$$,
  $$values (true, 1)$$,
  'desactivar y reactivar conserva exactamente una ubicación');

-- Otra empresa: el dueño de B crea en B.
select pg_temp.como_usuario('bbbbbbbb-0000-4000-8000-000000000001');
select lives_ok($$insert into creados select 'nuevoB', public.crear_camion('UB-N1', 'Misma patente en B')$$,
  'el dueño de B crea un camión con la misma patente');
reset role;
select is(
  (select u.empresa_id from public.ubicaciones u join creados x on x.id = u.camion_id
    where x.clave = 'nuevoB'),
  'bbbbbbbb-0000-4000-8000-000000000000'::uuid,
  'la ubicación del camión de B queda en B');

-- Atributos de la función (owner, seguridad, search_path, ACL) sin cambios.
select is(
  (select p.prosecdef::text || '|' || p.proowner::regrole::text || '|'
          || array_to_string(p.proconfig, ',') || '|' || p.provolatile::text || '|'
          || array_to_string(array(select a::text from unnest(p.proacl) a order by 1), ',')
     from pg_proc p where p.oid = 'privado.crear_camion(text,text)'::regprocedure),
  'true|propietario_rpc|search_path=""|v|authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc',
  'privado.crear_camion sigue SECURITY DEFINER, de propietario_rpc, search_path vacío, VOLATILE y con el mismo ACL');
select is(
  (select p.prosecdef::text || '|' || p.proowner::regrole::text || '|'
          || array_to_string(array(select a::text from unnest(p.proacl) a order by 1), ',')
     from pg_proc p where p.oid = 'public.crear_camion(text,text)'::regprocedure),
  'false|postgres|authenticated=X/postgres,postgres=X/postgres',
  'la fachada public.crear_camion no cambió (INVOKER, mismo ACL)');
select ok(not has_schema_privilege('propietario_rpc', 'privado', 'CREATE'),
  'propietario_rpc no conserva CREATE sobre privado');

-- Preparación para movimientos_stock (Etapa 2): (empresa_id, id) referenciable.
select ok(
  exists (select 1 from pg_constraint
           where conrelid = 'public.ubicaciones'::regclass and contype = 'u'
             and conname = 'ubicaciones_empresa_id_unico'),
  '(empresa_id, id) es único y puede ser destino de una FK compuesta sin cruzar empresas');

select * from finish();

rollback;
