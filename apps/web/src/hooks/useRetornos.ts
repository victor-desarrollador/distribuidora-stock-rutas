import { useState } from "react";
import { CLAVES_STORAGE } from "../data/clavesStorage";
import type { RetornoDeposito } from "../data/mockRetornos";
import { retorno_valido } from "../domain/retornos";

const STORAGE_KEY = CLAVES_STORAGE.retornos;

/** Resultado discriminado de la lectura del ledger de retornos. */
export type ResultadoLecturaRetornos =
  | { ok: true; retornos: RetornoDeposito[]; estado: "inicial" | "valido" }
  | { ok: false; error: string; estado: "corrupto" };

/**
 * Lectura interna que distingue: clave ausente (ledger inicial válido []),
 * clave válida y clave corrupta (error). Es la que usa la frontera de
 * escritura; nunca reinterpreta un storage corrupto como vacío.
 */
export function leerRetornosDiscriminado(): ResultadoLecturaRetornos {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (guardado === null) {
      return { ok: true, retornos: [], estado: "inicial" };
    }

    let datos: unknown;
    try {
      datos = JSON.parse(guardado);
    } catch {
      return {
        ok: false,
        error: "JSON inválido en almacenamiento de retornos.",
        estado: "corrupto",
      };
    }

    if (!Array.isArray(datos)) {
      return {
        ok: false,
        error: "Estructura inválida: se esperaba un array de retornos.",
        estado: "corrupto",
      };
    }

    if (!datos.every((r) => retorno_valido(r))) {
      return {
        ok: false,
        error: "Uno o más retornos no pasan la validación.",
        estado: "corrupto",
      };
    }

    return { ok: true, retornos: datos as RetornoDeposito[], estado: "valido" };
  } catch (e) {
    return {
      ok: false,
      error: `Error inesperado al leer retornos: ${String(e)}`,
      estado: "corrupto",
    };
  }
}

/**
 * Lectura para UI: fail-closed visual (devuelve [] tanto para ausente como
 * para corrupto). NO usar en la frontera de escritura.
 */
export function leerRetornos(): RetornoDeposito[] {
  const lectura = leerRetornosDiscriminado();
  return lectura.ok ? lectura.retornos : [];
}

/**
 * Operación pura de registro de retorno. Orden: 1) validar el retorno nuevo,
 * 2) leer el storage anterior, 3) abortar si está corrupto, 4) jornada
 * duplicada, 5) validación externa, 6) persistir.
 */
export function registrarRetornoOperacion(
  retorno: RetornoDeposito,
  validar: (actuales: RetornoDeposito[]) => string | null,
  cargarActuales: () => ResultadoLecturaRetornos,
  guardarActualizados: (retornos: RetornoDeposito[]) => void
): string | null {
  if (!retorno_valido(retorno, { exigir_responsable: true })) {
    return "El retorno no es válido: las cantidades deben ser enteros seguros, con aprobado menor o igual que contado.";
  }

  const lectura = cargarActuales();

  if (!lectura.ok) {
    return `No se puede registrar: ${lectura.error}`;
  }

  const actuales = lectura.retornos;

  // Una sola recepción por jornada, contra el storage leído ahora.
  if (actuales.some((r) => r.jornadaId === retorno.jornadaId)) {
    return "Esta jornada ya tiene un retorno registrado.";
  }

  const error = validar(actuales);

  if (error) return error;

  guardarActualizados([...actuales, retorno]);

  return null;
}

/**
 * Frontera REAL de escritura sin React: es lo que ejecuta el hook. Si el
 * almacenamiento está corrupto no escribe nada.
 */
export function registrarRetornoPersistido(
  retorno: RetornoDeposito,
  alGuardar?: (nuevos: RetornoDeposito[]) => void,
  validar: (actuales: RetornoDeposito[]) => string | null = () => null
): string | null {
  try {
    return registrarRetornoOperacion(
      retorno,
      validar,
      leerRetornosDiscriminado,
      (nuevos) => {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(nuevos));
        alGuardar?.(nuevos);
      }
    );
  } catch {
    return "No se pudo guardar el retorno.";
  }
}

export function useRetornos() {
  const [lectura] = useState(leerRetornosDiscriminado);
  const [retornos, setRetornos] = useState<RetornoDeposito[]>(
    lectura.ok ? lectura.retornos : []
  );

  function registrarRetorno(retorno: RetornoDeposito): string | null {
    return registrarRetornoPersistido(retorno, setRetornos);
  }

  return { retornos, registrarRetorno, estadoLectura: lectura.estado };
}
