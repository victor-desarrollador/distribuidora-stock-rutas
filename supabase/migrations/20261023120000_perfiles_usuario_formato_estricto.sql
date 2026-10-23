-- Endurece el formato de `perfiles.usuario` (hallazgo LOW-02 de la auditoría
-- de d7c3664).
--
-- El CHECK anterior (`^[a-z0-9][a-z0-9._-]{2,31}$`) aceptaba usuarios como
-- `abc.` o `a..b`, que derivan en una identidad interna de Auth
-- (`<usuario>@usuarios.distribuidora.invalid`) con una parte local de email
-- inválida. Contrato nuevo, idéntico al de
-- apps/web/src/domain/usuario_auth.ts (`es_usuario_valido`):
--
--   - 3 a 32 caracteres, ya normalizado (minúsculas, sin espacios);
--   - empieza y termina con letra a-z o dígito;
--   - caracteres interiores: a-z, 0-9, punto, guion y guion bajo;
--   - sin puntos consecutivos.
--
-- Sólo cambia la restricción; tablas, grants y RLS quedan como estaban.
-- Validación exclusivamente local/staging. Prohibido aplicar en producción.

alter table public.perfiles
  drop constraint perfiles_usuario_formato;

alter table public.perfiles
  add constraint perfiles_usuario_formato
    check (
      usuario ~ '^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$'
      and position('..' in usuario) = 0
    );
