import { useEffect, useState } from "react";

import { obtenerPuertoStock, type IntentoStock, type PuertoStock } from "../lib/stock";
import {
  crearControladorStock,
  type EstadoLecturaStock,
  type ResultadoOperacionStock,
} from "../pages/stock_controlador";
import { generarClaveNavegador } from "../pages/stock_formulario";

/**
 * Stock real de Supabase (B-01). La lógica (lectura vigente, guarda de doble
 * envío, idempotencia y recarga después de cada éxito) vive en
 * `crearControladorStock`; este hook sólo la conecta con el estado de React.
 */
export function useStock(puertoInyectado?: PuertoStock) {
  const [lectura, setLectura] = useState<EstadoLecturaStock>({
    estado: "cargando",
  });
  const [controlador] = useState(() =>
    crearControladorStock(
      puertoInyectado ?? obtenerPuertoStock(),
      setLectura,
      generarClaveNavegador
    )
  );

  useEffect(() => {
    // El estado inicial ya es "cargando".
    void controlador.leer();
    return () => controlador.detener();
  }, [controlador]);

  return {
    lectura,
    recargar: () => controlador.recargar(),
    ejecutar: (intento: IntentoStock): Promise<ResultadoOperacionStock> =>
      controlador.ejecutar(intento),
  };
}
