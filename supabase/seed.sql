-- SEED EXCLUSIVAMENTE LOCAL (supabase start / supabase db reset).
--
-- Crea una empresa y cuentas de PRUEBA para desarrollo y Playwright.
-- La contraseña es una credencial de prueba explícita, conocida y sin valor:
-- no es una contraseña real, no se reutiliza y este archivo nunca se aplica
-- a staging ni a producción. Las cuentas reales se crean administrativamente
-- (ver docs/progress-log.md, entrada feat/auth-backend-base).
--
-- Contraseña de prueba de todas las cuentas: Prueba-Local-2026
--
-- Usuarios de login (identidad Auth interna = <usuario>@usuarios.distribuidora.invalid):
--   dueno.prueba      dueno            activo
--   encargado.prueba  encargado        activo
--   vendedor.prueba   vendedor_piloto  activo
--   inactivo.prueba   vendedor_piloto  INACTIVO
--   sinperfil.prueba  (cuenta Auth sin perfil)
--   otraempresa.prueba dueno           activo, de OTRA empresa (fixture adversarial
--                                      para probar aislamiento por empresa_id; no
--                                      es un producto multiempresa)
--
-- Todos cumplen el contrato de `perfiles_usuario_formato` (3–32 caracteres,
-- empieza y termina con a-z/0-9, interiores a-z 0-9 . _ -, sin puntos
-- consecutivos), el mismo que apps/web/src/domain/usuario_auth.ts.

insert into public.empresas (id, nombre)
values ('00000000-0000-4000-8000-0000000000e1', 'Distribuidora (local)'),
       -- Fixture adversarial de aislamiento (ver cabecera).
       ('00000000-0000-4000-8000-0000000000e2', 'Otra empresa (local, aislamiento)');

with cuentas (id, usuario) as (
  values
    ('00000000-0000-4000-8000-000000000001'::uuid, 'dueno.prueba'),
    ('00000000-0000-4000-8000-000000000002'::uuid, 'encargado.prueba'),
    ('00000000-0000-4000-8000-000000000003'::uuid, 'vendedor.prueba'),
    ('00000000-0000-4000-8000-000000000004'::uuid, 'inactivo.prueba'),
    ('00000000-0000-4000-8000-000000000005'::uuid, 'sinperfil.prueba'),
    ('00000000-0000-4000-8000-000000000006'::uuid, 'otraempresa.prueba')
)
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new,
  email_change, email_change_token_current, phone_change,
  phone_change_token, reauthentication_token
)
select
  '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated',
  usuario || '@usuarios.distribuidora.invalid',
  extensions.crypt('Prueba-Local-2026', extensions.gen_salt('bf')),
  now(), '{"provider":"email","providers":["email"]}'::jsonb,
  -- Metadata deliberadamente engañosa en una cuenta: no debe conceder nada.
  case when usuario = 'vendedor.prueba'
    then '{"rol":"dueno"}'::jsonb else '{}'::jsonb end,
  now(), now(),
  '', '', '', '', '', '', '', ''
from cuentas;

insert into auth.identities (
  id, user_id, provider_id, provider, identity_data,
  last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(), u.id, u.id::text, 'email',
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  now(), now(), now()
from auth.users u
where u.email like '%@usuarios.distribuidora.invalid';

insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo)
values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000e1',
   'dueno.prueba', 'Dueño de prueba', 'dueno', true),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000000e1',
   'encargado.prueba', 'Encargado de prueba', 'encargado', true),
  ('00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-0000000000e1',
   'vendedor.prueba', 'Vendedor de prueba', 'vendedor_piloto', true),
  ('00000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-0000000000e1',
   'inactivo.prueba', 'Inactivo de prueba', 'vendedor_piloto', false),
  ('00000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-0000000000e2',
   'otraempresa.prueba', 'Dueño de otra empresa', 'dueno', true);

-- Cliente de la otra empresa: ningún usuario de la empresa principal debe
-- verlo ni poder modificarlo (Playwright, tests/clientes-catalogo.spec.ts).
insert into public.clientes (
  id, empresa_id, nombre, comercio, direccion, telefono, activo,
  estado_validacion, creado_por, validado_por, validado_en
)
values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000e2',
   'Cliente de otra empresa (seed)', null, null, '0000000000', true,
   'validado', '00000000-0000-4000-8000-000000000006',
   '00000000-0000-4000-8000-000000000006', now());

-- Catálogo de productos de prueba (sólo local). Sin stock: el stock sólo
-- sale de movimientos_stock (Blueprint §3.1). Fiambres con precio de pieza
-- completa; la media se deriva (ADR-003).
insert into public.productos (
  id, empresa_id, codigo, nombre, categoria, forma_venta, precio,
  stock_minimo, activo, creado_por
)
values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000e1',
   'LAC-001', 'Yogur bebible 1 L', 'lacteos', 'unidad', 2300.00, 20, true,
   '00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000e1',
   'LAC-002', 'Leche entera 1 L', 'lacteos', 'unidad', 1600.00, 30, true,
   '00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-0000000000a3', '00000000-0000-4000-8000-0000000000e1',
   'FIA-001', 'Jamón cocido', 'fiambres', 'pieza', 12500.00, 10, true,
   '00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-0000000000a4', '00000000-0000-4000-8000-0000000000e1',
   null, 'Salame milán', 'fiambres', 'pieza', 9800.00, 16, false,
   '00000000-0000-4000-8000-000000000001');
