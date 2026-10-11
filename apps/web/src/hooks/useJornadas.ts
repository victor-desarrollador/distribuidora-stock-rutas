
import { useState } from "react";
import {
  type Jornada,
  type ItemCarga,
} from "../data/mockJornadas";

const STORAGE_KEY = "distribuidora_jornadas_demo_v1";

function cargarJornadas(): Jornada[] {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (!guardado) return [];

    const datos: unknown = JSON.parse(guardado);

    if (!Array.isArray(datos)) return [];

    const validos = datos.every((j) => {
      if (j === null || typeof j !== "object") return false;

      const jornada = j as Partial<Jornada>;

      return (
        typeof jornada.id === "string" &&
        Number.isSafeInteger(jornada.camionId) &&
        typeof jornada.chofer === "string" &&
        typeof jornada.zona === "string" &&
        typeof jornada.fechaCreacion === "string" &&
        (jornada.fechaSalida === null ||
          typeof jornada.fechaSalida === "string") &&
        ["preparacion", "abierta", "cerrada"].includes(
          jornada.estado ?? ""
        ) &&
        Array.isArray(jornada.items) &&
        jornada.items.every((item: ItemCarga) =>
          item !== null &&
          Number.isSafeInteger(item.productoId) &&
          typeof item.nombreProducto === "string" &&
          ["unidad", "pieza", "kg"].includes(item.unidadMedida) &&
          Number.isFinite(item.cantidad) &&
          item.cantidad > 0 &&
          Number.isFinite(item.precioReferencia) &&
          item.precioReferencia >= 0
        )
      );
    });

    return validos ? datos as Jornada[] : [];
  } catch {
    return [];
  }
}

export function useJornadas() {
  const [jornadas, setJornadas] = useState<Jornada[]>(
    cargarJornadas
  );

  function guardarJornadas(actualizadas: Jornada[]) {
    // Si no es posible guardar, evitamos mostrar un
    // cambio que se perdería al actualizar la página.
    try {
      localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify(actualizadas)
      );

      setJornadas(actualizadas);
      return true;
    } catch {
      return false;
    }
  }

  function crearJornada(jornada: Jornada) {
    return guardarJornadas([...jornadas, jornada]);
  }

  function confirmarSalida(id: string) {
    const actualizadas = jornadas.map((jornada) =>
      jornada.id === id && jornada.estado === "preparacion"
        ? {
            ...jornada,
            estado: "abierta" as const,
            fechaSalida: new Date().toISOString(),
          }
        : jornada
    );

    return guardarJornadas(actualizadas);
  }

  return {
    jornadas,
    crearJornada,
    confirmarSalida,
  };
}
