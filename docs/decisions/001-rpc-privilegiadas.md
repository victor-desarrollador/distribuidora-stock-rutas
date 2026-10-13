# ADR-001 — Puerta de entrada SQL para operaciones privilegiadas

**Fecha:** 12/10/2026  
**Estado:** propuesta; pendiente de revisión y pruebas (NO aprobada)

## Contexto
La interfaz React usa Supabase Data API, pero usuarios `authenticated` no deben poder escribir directamente en tablas de movimientos de stock y dinero. RPC `SECURITY INVOKER` sobre esas tablas requeriría grants directos que permitirían saltar reglas de negocio.

## Decisión propuesta
Implementar wrappers RPC específicos en un esquema expuesto `public`, con `SECURITY DEFINER`, `SET search_path = ''`, nombres de objetos calificados, privilegios `EXECUTE` revocados a `PUBLIC` y `anon`, concedidos selectivamente a `authenticated`. Cada wrapper valida `auth.uid()`, membresía, `empresa_id`, rol, estado, permisos sobre la operación, cantidades e idempotencia y llama lógica interna en esquema privado que no es directamente accesible desde la Data API. Restringir grants de escritura sobre libros mayores y auditar cada cambio. Definir propietario técnico de mínimo privilegio y revisar privilegios por defecto de nuevas funciones. En PostgreSQL las funciones nuevas pueden ser ejecutables por `PUBLIC` por defecto (y de allí por `anon`/`authenticated`). Configurar `ALTER DEFAULT PRIVILEGES FOR ROLE <rol_creador> IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated` para el rol creador correspondiente, y **además** revocar explícitamente `EXECUTE` de cada función sensible al crearla antes de otorgarlo solo a los roles autorizados. Verificar los privilegios efectivos en staging; los defaults son por rol creador.

## Alternativas
- `SECURITY INVOKER` con grants INSERT a authenticated: descartada para libros mayores por permitir escritura directa.
- Edge Function autenticada: alternativa válida cuando intervengan servicios externos o lógica no apta para SQL; innecesaria por ahora si se comprueba la seguridad de la opción RPC.

## Riesgos y pruebas obligatorias
`SECURITY DEFINER` puede ejecutar con permisos elevados y eludir RLS. Ensayar `anon`, usuario sin rol, usuarios de otra empresa, vendedor, encargado y dueño, incluyendo intentos de editar asientos directamente y llamar funciones internas. Verificar `REVOKE`/`GRANT`, propiedad de funciones, `search_path`, concurrencia y idempotencia en staging. Las pruebas de base y permisos se escriben con **pgTAP** en `supabase/tests/` y se ejecutan mediante `supabase test db` en un entorno aislado; complementar con pruebas del cliente HTTP/RPC donde corresponda. No aplicar a producción antes de aprobar la ADR y superar estas pruebas.

## Consecuencias
Las operaciones críticas se mantienen transaccionales dentro de Postgres, sin requerir Edge Function por defecto. Los agentes no pueden asumir que una RPC pública es segura solamente por exigir autenticación.
