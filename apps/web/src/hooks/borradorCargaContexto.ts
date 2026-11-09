import { createContext, useContext } from "react";

import type { AccionesBorrador, BorradorCarga, SolicitudDescarte } from "../pages/carga_borrador";

// Contexto del borrador de carga (FE-1D). Sólo preparación: no expone ninguna
// acción de confirmación de carga, envío ni verificación (DP-1 abierto).
// FE-1E: `pendiente` es la acción voluntaria (abrir otra jornada o cerrar
// sesión) que espera que la persona acepte descartar lo escrito o cancele.
export interface ContextoBorradorCarga extends AccionesBorrador {
  borrador: BorradorCarga;
  pendiente: SolicitudDescarte | null;
}

export const BorradorCargaContexto = createContext<ContextoBorradorCarga | null>(null);

export function useBorradorCarga(): ContextoBorradorCarga {
  const contexto = useContext(BorradorCargaContexto);
  if (!contexto) {
    throw new Error("useBorradorCarga debe utilizarse dentro de BorradorCargaProvider");
  }
  return contexto;
}
