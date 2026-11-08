import { useEffect, useState } from "react";

import { obtenerPuertoJornadas } from "../lib/jornadas";
import {
  APERTURA_INACTIVA,
  crearControladorApertura,
  type EntradaApertura,
  type FaseApertura,
  type OpcionesPermitidas,
} from "../pages/jornadas_apertura";

/**
 * «Abrir jornada» (D-B2-1). La lógica vive en `crearControladorApertura`;
 * este hook sólo la conecta con React.
 *
 * `releer` y `alRechazoVendedor` se toman UNA vez, al crear el controlador:
 * deben delegar en algo estable durante la vida del componente
 * (`useJornadasLectura().recargar`, `useVendedoresJornada().recargar`).
 */
export function useAperturaJornada(releer: () => void, alRechazoVendedor: () => void) {
  const [fase, setFase] = useState<FaseApertura>(APERTURA_INACTIVA);
  const [controlador] = useState(() => {
    const puerto = obtenerPuertoJornadas();
    return crearControladorApertura(puerto, puerto, releer, setFase, { alRechazoVendedor });
  });

  useEffect(() => {
    controlador.iniciar();
    return () => controlador.detener();
  }, [controlador]);

  return {
    fase,
    solicitar: controlador.solicitar,
    cancelar: controlador.cancelar,
    confirmar: (entrada: EntradaApertura, permitidas: OpcionesPermitidas) =>
      void controlador.confirmar(entrada, permitidas),
    reintentar: () => void controlador.reintentar(),
    trasRelectura: controlador.trasRelectura,
  };
}
