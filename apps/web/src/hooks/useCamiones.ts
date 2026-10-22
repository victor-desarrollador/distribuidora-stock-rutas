
import { useState } from "react";

import { CLAVES_STORAGE } from "../data/clavesStorage";
import {
  camionesIniciales,
  type Camion,
} from "../data/mockCamiones";

import {
  actualizarCatalogoPersistido,
  leerCatalogo,
  type ResultadoLectura,
} from "./catalogoStorage";

const STORAGE_KEY = CLAVES_STORAGE.camiones;

function camionValido(camion: unknown): boolean {
  if (camion === null || typeof camion !== "object") return false;

  const c = camion as Partial<Camion>;

  return (
    Number.isSafeInteger(c.id) &&
    typeof c.nombre === "string" &&
    typeof c.patente === "string" &&
    typeof c.marca === "string" &&
    typeof c.modelo === "string" &&
    typeof c.observaciones === "string" &&
    ["disponible", "en_reparto", "mantenimiento"].includes(
      c.estado ?? ""
    )
  );
}

/** Lectura discriminada (ausente / válido / corrupto). */
export function leerCamiones(): ResultadoLectura<Camion> {
  return leerCatalogo(STORAGE_KEY, camionValido, camionesIniciales);
}

/** Datos para la UI: iniciales si está ausente o corrupto (nunca persiste). */
export function cargarCamiones(): Camion[] {
  const lectura = leerCamiones();
  return lectura.ok ? lectura.datos : camionesIniciales;
}

export function useCamiones() {
  const [lectura] = useState(leerCamiones);
  const [camiones, setCamionesEstado] = useState<Camion[]>(
    lectura.ok ? lectura.datos : []
  );

  /**
   * Frontera explícita de edición (bloque E / M-1): relee la clave, aborta si
   * está corrupta (sin escribir ni cambiar React), persiste y solo si la
   * escritura tuvo éxito actualiza el estado. Devuelve false cuando la
   * operación no se guardó.
   */
  function actualizarCamiones(
    transformar: (actuales: Camion[]) => Camion[]
  ): boolean {
    const nuevos = actualizarCatalogoPersistido(
      STORAGE_KEY,
      camionValido,
      camionesIniciales,
      transformar
    );

    if (nuevos === null) return false;

    setCamionesEstado(nuevos);
    return true;
  }

  return { camiones, actualizarCamiones, estadoLectura: lectura.estado };
}
