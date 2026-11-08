import { useEffect, useState } from "react";

import { obtenerPuertoVendedoresJornada } from "../lib/vendedores_jornada";
import {
  VENDEDORES_INACTIVO,
  crearControladorVendedores,
  type EstadoVendedores,
} from "../pages/jornadas_apertura";

/**
 * Lista real de vendedores asignables (RPC `listar_vendedores_jornada`, D-B2-1).
 * No lee nada al montar: la pantalla la pide al abrir el formulario de
 * apertura (sólo dueño y encargado), así la lista es la vigente en ese momento.
 * `recargar` es estable durante la vida del componente.
 */
export function useVendedoresJornada() {
  const [estado, setEstado] = useState<EstadoVendedores>(VENDEDORES_INACTIVO);
  const [controlador] = useState(() =>
    crearControladorVendedores(obtenerPuertoVendedoresJornada(), setEstado)
  );

  useEffect(() => {
    controlador.iniciar();
    return () => controlador.detener();
  }, [controlador]);

  const [recargar] = useState(() => () => void controlador.recargar());
  return { estado, recargar };
}
