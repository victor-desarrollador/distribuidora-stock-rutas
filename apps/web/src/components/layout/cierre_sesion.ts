import type { AccionesBorrador } from "../../pages/carga_borrador";

// FE-1E: cierre de sesión VOLUNTARIO (menú) protegido por el borrador de carga.
// Usa `cerrarSesion` de `useAuth` sin cambiar su contrato: sólo decide si se
// llama ahora o después de que la persona acepte descartar lo escrito. No
// interviene en ningún otro cambio de identidad (vencimiento, otra pestaña,
// acceso bloqueado): esos descartan el borrador en el provider sin preguntar.

/** Pide cerrar sesión: true si se cerró; false si quedó pendiente de confirmar. */
export function pedirSalida(
  borrador: Pick<AccionesBorrador, "pedirCierreSesion">,
  cerrarSesion: () => void
): boolean {
  if (!borrador.pedirCierreSesion()) return false;
  cerrarSesion();
  return true;
}

/** La persona aceptó descartar: el borrador ya se descartó y se cierra sesión. */
export function aceptarSalida(
  borrador: Pick<AccionesBorrador, "aceptarDescarte">,
  cerrarSesion: () => void
): boolean {
  if (borrador.aceptarDescarte()?.tipo !== "cerrar_sesion") return false;
  cerrarSesion();
  return true;
}
