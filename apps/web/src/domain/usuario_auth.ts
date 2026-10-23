// Mapeo usuario visible -> identidad interna de Supabase Auth.
//
// Supabase Auth autentica con contraseña sólo por email o teléfono. La
// persona usuaria inicia sesión con un `usuario`; el sistema lo traduce de
// forma determinista a un identificador interno con dominio reservado
// `.invalid` (RFC 2606), que no es un email de negocio ni recibe correo.
//
// El contrato debe coincidir con el CHECK `perfiles_usuario_formato` de
// supabase/migrations/20261023120000_perfiles_usuario_formato_estricto.sql:
// mismo patrón y la misma prohibición de puntos consecutivos.

export const DOMINIO_AUTH_INTERNO = "usuarios.distribuidora.invalid";

// 3 a 32 caracteres: letras a-z, dígitos, punto, guion y guion bajo; empieza
// y termina con letra o dígito.
export const PATRON_USUARIO = /^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$/;

// Un punto doble produciría una parte local de email inválida.
export function es_usuario_valido(usuario: string): boolean {
  return PATRON_USUARIO.test(usuario) && !usuario.includes("..");
}

// Normaliza: recorta espacios y pasa a minúsculas. Devuelve null si el
// resultado no cumple el contrato.
export function normalizar_usuario(entrada: string): string | null {
  const normalizado = entrada.trim().toLowerCase();

  return es_usuario_valido(normalizado) ? normalizado : null;
}

export function identificador_auth_interno(usuario_normalizado: string): string {
  if (!es_usuario_valido(usuario_normalizado)) {
    throw new Error("El usuario no está normalizado.");
  }

  return `${usuario_normalizado}@${DOMINIO_AUTH_INTERNO}`;
}
