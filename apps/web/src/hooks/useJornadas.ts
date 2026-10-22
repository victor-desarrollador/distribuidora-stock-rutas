import { useState } from "react";

import { CLAVES_STORAGE } from "../data/clavesStorage";
import { precio_valido } from "../domain/precios";
import { es_cantidad_valida } from "../domain/cantidades";

import {
  type Jornada,
  type CierreJornada,
} from "../data/mockJornadas";

const STORAGE_KEY = CLAVES_STORAGE.jornadas;

function cierreValido(cierre: unknown): cierre is CierreJornada {
  if (!cierre || typeof cierre !== "object") return false;

  const c = cierre as Partial<CierreJornada>;

  if (
    typeof c.fecha !== "string" ||
    typeof c.observaciones !== "string" ||
    !Number.isFinite(c.efectivoEntregado) ||
    !Number.isFinite(c.efectivoEsperado) ||
    !Number.isFinite(c.transferenciasInformadas) ||
    !Number.isFinite(c.ventasCuentaCorriente) ||
    !c.conteos ||
    typeof c.conteos !== "object" ||
    Array.isArray(c.conteos)
  ) {
    return false;
  }

  const importes = [
    c.efectivoEntregado!,
    c.efectivoEsperado!,
    c.transferenciasInformadas!,
    c.ventasCuentaCorriente!,
  ];

  return (
    importes.every((n) => n >= 0) &&
    Object.values(c.conteos).every(
      (n) => typeof n === "number" && es_cantidad_valida(n)
    )
  );
}

export function leerJornadas(): Jornada[] {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);
    if (!guardado) return [];

    const datos: unknown = JSON.parse(guardado);
    if (!Array.isArray(datos)) return [];

    const validos = datos.every((j) => {
      if (!j || typeof j !== "object") return false;

      const jornada = j as Partial<Jornada>;

      const baseValida =
        typeof jornada.id === "string" &&
        Number.isSafeInteger(jornada.camionId) &&
        typeof jornada.chofer === "string" &&
        typeof jornada.zona === "string" &&
        typeof jornada.fechaCreacion === "string" &&
        (
          jornada.fechaSalida === null ||
          typeof jornada.fechaSalida === "string"
        ) &&
        ["preparacion", "abierta", "cerrada"].includes(
          jornada.estado ?? ""
        ) &&
        Array.isArray(jornada.items) &&
        jornada.items.every((item) =>
          item !== null &&
          Number.isSafeInteger(item.productoId) &&
          typeof item.nombreProducto === "string" &&
          ["unidad", "pieza"].includes(item.unidadMedida) &&
          // Validación canónica: entero seguro > 0 (dominio compartido)
          typeof item.cantidad === "number" &&
          es_cantidad_valida(item.cantidad) &&
          item.cantidad > 0 &&
          // Precios: solo precioReferencia (precioMediaPieza se deriva)
          precio_valido(item.precioReferencia)
        );

      if (!baseValida) return false;

      // Compatibilidad con jornadas creadas en etapas anteriores.
      if (jornada.estado === "cerrada") {
        return cierreValido(jornada.cierre);
      }

      return jornada.cierre === undefined;
    });

    return validos ? (datos as Jornada[]) : [];
  } catch {
    return [];
  }
}

function guardarJornadas(jornadas: Jornada[]): boolean {
  try {
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify(jornadas)
    );
    return true;
  } catch {
    return false;
  }
}

/**
 * Cierre de jornada sin React: valida, persiste y devuelve las jornadas
 * actualizadas, o null si se rechaza (sin escribir). Es lo que ejecuta el hook.
 */
export function cerrarJornadaPersistida(
  id: string,
  cierre: CierreJornada
): Jornada[] | null {
  const actuales = leerJornadas();
  const jornada = actuales.find((j) => j.id === id);

  // No permitir cerrar dos veces la misma jornada.
  if (!jornada || jornada.estado !== "abierta") {
    return null;
  }

  if (!cierreValido(cierre)) return null;

  const productosContados = Object.keys(cierre.conteos);

  // Exigir un conteo por cada producto cargado.
  if (
    productosContados.length !== jornada.items.length ||
    !jornada.items.every((item) => {
      const cantidad = cierre.conteos[String(item.productoId)];

      return (
        typeof cantidad === "number" &&
        es_cantidad_valida(cantidad)
      );
    })
  ) {
    return null;
  }

  const actualizadas: Jornada[] = actuales.map((j) =>
    j.id === id
      ? {
          ...j,
          estado: "cerrada",
          cierre,
        }
      : j
  );

  return guardarJornadas(actualizadas) ? actualizadas : null;
}

export function useJornadas() {
  const [jornadas, setJornadas] = useState<Jornada[]>(
    leerJornadas
  );

  function crearJornada(jornada: Jornada): boolean {
    const actuales = leerJornadas();

    if (
      actuales.some((j) => j.id === jornada.id) ||
      actuales.some(
        (j) =>
          j.camionId === jornada.camionId &&
          j.estado !== "cerrada"
      )
    ) {
      return false;
    }

    const actualizadas = [...actuales, jornada];

    if (!guardarJornadas(actualizadas)) return false;

    setJornadas(actualizadas);
    return true;
  }

  function confirmarSalida(id: string): boolean {
    const actuales = leerJornadas();
    const jornada = actuales.find((j) => j.id === id);

    if (!jornada || jornada.estado !== "preparacion") {
      return false;
    }

    const actualizadas: Jornada[] = actuales.map((j) =>
      j.id === id
        ? {
            ...j,
            estado: "abierta",
            fechaSalida: new Date().toISOString(),
          }
        : j
    );

    if (!guardarJornadas(actualizadas)) return false;

    setJornadas(actualizadas);
    return true;
  }

  function cerrarJornada(
    id: string,
    cierre: CierreJornada
  ): boolean {
    const actualizadas = cerrarJornadaPersistida(id, cierre);

    if (!actualizadas) return false;

    setJornadas(actualizadas);
    return true;
  }

  return {
    jornadas,
    crearJornada,
    confirmarSalida,
    cerrarJornada,
  };
}