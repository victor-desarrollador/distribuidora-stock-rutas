// Mapeo usuario visible -> identidad interna de Supabase Auth.
//
// Supabase Auth autentica con contraseña sólo por email o teléfono. La
// persona usuaria inicia sesión con un `usuario`; el sistema lo traduce de
// forma determinista a un identificador interno con dominio reservado
// `.invalid` (RFC 2606), que no es un email de negocio ni recibe correo.
//
// El patrón debe coincidir con el CHECK `perfiles_usuario_formato` de
// supabase/migrations/20261022120000_auth_base_empresas_perfiles.sql.

export const DOMINIO_AUTH_INTERNO = "usuarios.distribuidora.invalid";

export const PATRON_USUARIO = /^[a-z0-9][a-z0-9._-]{2,31}$/;

// Normaliza: recorta espacios y pasa a minúsculas. Devuelve null si el
// resultado no cumple el formato permitido (3 a 32 caracteres: letras a-z,
// dígitos, punto, guion y guion bajo; empieza con letra o dígito).
export function normalizar_usuario(entrada: string): string | null {
  const normalizado = entrada.trim().toLowerCase();

  return PATRON_USUARIO.test(normalizado) ? normalizado : null;
}

export function identificador_auth_interno(usuario_normalizado: string): string {
  if (!PATRON_USUARIO.test(usuario_normalizado)) {
    throw new Error("El usuario no está normalizado.");
  }

  return `${usuario_normalizado}@${DOMINIO_AUTH_INTERNO}`;
}
