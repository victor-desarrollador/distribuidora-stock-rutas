
import { useState } from "react";
import { CLAVES_STORAGE } from "../data/clavesStorage";
import type {
  RetornoDeposito,
  ItemRetorno,
} from "../data/mockRetornos";

const STORAGE_KEY = CLAVES_STORAGE.retornos;

export function esCantidadValida(cantidad: number) {
  return (
    Number.isFinite(cantidad) &&
    Number.isInteger(cantidad) &&
    cantidad >= 0
  );
}

export function leerRetornos(): RetornoDeposito[] {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (!guardado) return [];

    const datos: unknown = JSON.parse(guardado);

    if (!Array.isArray(datos)) return [];

    const valido = datos.every((r) => {
      if (!r || typeof r !== "object") return false;

      return (
        typeof r.id === "string" &&
        typeof r.jornadaId === "string" &&
        Number.isSafeInteger(r.camionId) &&
        typeof r.fecha === "string" &&
        typeof r.responsable === "string" &&
        typeof r.observaciones === "string" &&
        Array.isArray(r.items) &&
        r.items.every((item: ItemRetorno) =>
          item !== null &&
          Number.isSafeInteger(item.productoId) &&
          typeof item.nombreProducto === "string" &&
          ["unidad", "pieza"].includes(item.unidadMedida) &&
          esCantidadValida(item.cantidadContada) &&
          esCantidadValida(item.cantidadAprobada) &&
          item.cantidadAprobada <=
            item.cantidadContada + 0.000001
        )
      );
    });

    return valido ? (datos as RetornoDeposito[]) : [];
  } catch {
    return [];
  }
}

export function useRetornos() {
  const [retornos, setRetornos] = useState<
    RetornoDeposito[]
  >(leerRetornos);

  function registrarRetorno(
    retorno: RetornoDeposito
  ): string | null {
    try {
      const actuales = leerRetornos();

      // No permitir registrar dos recepciones
      // para la misma jornada en esta versión.
      if (
        actuales.some(
          (r) => r.jornadaId === retorno.jornadaId
        )
      ) {
        return "Esta jornada ya tiene un retorno registrado.";
      }

      const ids = retorno.items.map((i) => i.productoId);

      if (
        new Set(ids).size !== ids.length ||
        retorno.items.some(
          (item) =>
            !esCantidadValida(item.cantidadContada) ||
            !esCantidadValida(item.cantidadAprobada) ||
            item.cantidadAprobada >
              item.cantidadContada + 0.000001
        )
      ) {
        return "Las cantidades del retorno no son válidas.";
      }

      const actualizados = [...actuales, retorno];

      localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify(actualizados)
      );

      setRetornos(actualizados);
      return null;
    } catch {
      return "No se pudo guardar el retorno.";
    }
  }

  return { retornos, registrarRetorno };
}
