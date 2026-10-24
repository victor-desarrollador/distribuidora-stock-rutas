import { useCallback, useEffect, useRef, useState } from "react";

import {
  obtenerPuertoCamiones,
  type CamionCatalogo,
  type DatosCamion,
  type PuertoCamiones,
  type ResultadoCamiones,
} from "../lib/camiones";

export type EstadoCatalogoCamiones =
  | { estado: "cargando" }
  | { estado: "listo"; camiones: CamionCatalogo[] }
  | { estado: "error"; error: string };

/**
 * Catálogo de camiones de Supabase. La lectura falla cerrado: ante un error no
 * se muestran datos viejos. Después de cada escritura exitosa se vuelve a leer
 * el catálogo: la base es la autoridad.
 */
export function useCatalogoCamiones(puertoInyectado?: PuertoCamiones) {
  const [puerto] = useState(() => puertoInyectado ?? obtenerPuertoCamiones());
  const [catalogo, setCatalogo] = useState<EstadoCatalogoCamiones>({
    estado: "cargando",
  });
  // Sólo la última lectura iniciada puede publicar su resultado.
  const lecturaVigente = useRef(0);

  // Publica el resultado sólo después de la respuesta de la base.
  const leer = useCallback(async () => {
    const lectura = ++lecturaVigente.current;

    const resultado = await puerto.listar();
    if (lectura !== lecturaVigente.current) return;

    setCatalogo(
      resultado.ok
        ? { estado: "listo", camiones: resultado.datos }
        : { estado: "error", error: resultado.error }
    );
  }, [puerto]);

  // Recarga explícita: deja de mostrar los datos anteriores mientras lee.
  const recargar = useCallback(async () => {
    setCatalogo({ estado: "cargando" });
    await leer();
  }, [leer]);

  useEffect(() => {
    // El estado inicial ya es "cargando".
    void leer();
    // Al desmontar, ninguna lectura pendiente publica su resultado.
    return () => {
      lecturaVigente.current += 1;
    };
  }, [leer]);

  async function escribir<T>(
    operacion: () => Promise<ResultadoCamiones<T>>
  ): Promise<ResultadoCamiones<T>> {
    const resultado = await operacion();
    if (resultado.ok) await recargar();
    return resultado;
  }

  return {
    catalogo,
    recargar,
    crear: (datos: DatosCamion) => escribir(() => puerto.crear(datos)),
    actualizar: (id: string, datos: DatosCamion) =>
      escribir(() => puerto.actualizar(id, datos)),
    cambiarEstado: (id: string, activo: boolean) =>
      escribir(() => puerto.cambiarEstado(id, activo)),
  };
}
