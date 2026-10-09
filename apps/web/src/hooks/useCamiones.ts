
import { useEffect, useState } from "react";

import {
  camionesIniciales,
  type Camion,
} from "../data/mockCamiones";

const STORAGE_KEY = "distribuidora_camiones_demo_v1";

function cargarCamiones(): Camion[] {
  try {
    const guardados = localStorage.getItem(STORAGE_KEY);

    if (!guardados) return camionesIniciales;

    const datos: unknown = JSON.parse(guardados);

    if (!Array.isArray(datos)) return camionesIniciales;

    const validos = datos.every(
      (camion) =>
        camion !== null &&
        typeof camion === "object" &&
        Number.isSafeInteger(camion.id) &&
        typeof camion.nombre === "string" &&
        typeof camion.patente === "string" &&
        typeof camion.marca === "string" &&
        typeof camion.modelo === "string" &&
        typeof camion.observaciones === "string" &&
        ["disponible", "en_reparto", "mantenimiento"].includes(
          camion.estado
        )
    );

    return validos ? (datos as Camion[]) : camionesIniciales;
  } catch {
    return camionesIniciales;
  }
}

export function useCamiones() {
  const [camiones, setCamiones] = useState<Camion[]>(cargarCamiones);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(camiones));
    } catch (error) {
      console.error("Error al guardar camiones:", error);
    }
  }, [camiones]);

  return { camiones, setCamiones };
}
