import { useEffect, useState } from "react";

import {
  obtenerPuertoHistorialJornada,
  type PuertoHistorialJornada,
} from "../lib/jornadas_historial";
import {
  HISTORIAL_INACTIVO,
  crearControladorHistorial,
  type EstadoHistorial,
} from "../pages/jornadas_historial";

/**
 * Historial de cargas y descargas de la jornada seleccionada (B-02b.2 / S3-0),
 * sólo lectura. La lógica vive en `crearControladorHistorial`; este hook sólo
 * la conecta con React. Con `jornadaId` null no se lee nada (la pantalla lo
 * pasa así para quien no es dueño ni encargado).
 */
export function useHistorialJornada(
  jornadaId: string | null,
  puertoInyectado?: PuertoHistorialJornada
) {
  const [estado, setEstado] = useState<EstadoHistorial>(HISTORIAL_INACTIVO);
  const [controlador] = useState(() =>
    crearControladorHistorial(puertoInyectado ?? obtenerPuertoHistorialJornada(), setEstado)
  );

  useEffect(() => {
    controlador.iniciar();
    return () => controlador.detener();
  }, [controlador]);

  useEffect(() => {
    void controlador.mostrar(jornadaId);
  }, [controlador, jornadaId]);

  return {
    estado,
    actualizar: () => void controlador.actualizar(),
  };
}
