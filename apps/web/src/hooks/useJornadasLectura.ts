import { useEffect, useState } from "react";

import { obtenerPuertoJornadas } from "../lib/jornadas";
import {
  ESTADO_INICIAL_JORNADAS,
  crearControladorJornadas,
  type EstadoPantallaJornadas,
  type PuertoLecturaJornadas,
} from "../pages/jornadas_lectura";

/**
 * Jornadas reales de Supabase (B-02b.1), sólo lectura. La lógica vive en
 * `crearControladorJornadas`; este hook sólo la conecta con el estado de React.
 * Reemplaza al modo demo (`useJornadas`, localStorage) en la pantalla de
 * jornadas.
 */
export function useJornadasLectura(puertoInyectado?: PuertoLecturaJornadas) {
  const [estado, setEstado] = useState<EstadoPantallaJornadas>(
    ESTADO_INICIAL_JORNADAS
  );
  const [controlador] = useState(() =>
    crearControladorJornadas(
      puertoInyectado ?? obtenerPuertoJornadas(),
      setEstado
    )
  );

  useEffect(() => {
    // El estado inicial ya es "cargando".
    void controlador.iniciar();
    return () => controlador.detener();
  }, [controlador]);

  return {
    estado,
    recargar: () => void controlador.recargar(),
    cambiarFecha: (fecha: string | null) => void controlador.cambiarFecha(fecha),
    cargarMas: () => void controlador.cargarMas(),
    cargarTodas: () => void controlador.cargarTodas(),
    seleccionar: (id: string | null) => controlador.seleccionar(id),
  };
}
