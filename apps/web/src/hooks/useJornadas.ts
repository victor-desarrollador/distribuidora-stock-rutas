import { useState } from "react";

import { CLAVES_STORAGE } from "../data/clavesStorage";
import { precio_valido } from "../domain/precios";
import { es_cantidad_valida } from "../domain/cantidades";
import { MENSAJE_PESO_NO_OPERABLE } from "../domain/productos";

import {
  type Jornada,
  type CierreJornada,
} from "../data/mockJornadas";
import type { RetornoDeposito } from "../data/mockRetornos";
import { leerRetornosDiscriminado } from "./useRetornos";

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

/** Jornada válida (estructura, cantidades canónicas, precios y cierre). */
function jornadaValida(j: unknown): j is Jornada {
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
      // Estructuralmente, `peso` (gramos enteros) es válido en v5; los flujos
      // de B1 no lo generan (ver guards de preparación y cierre).
      ["unidad", "peso"].includes(item.unidadMedida) &&
      // Validación canónica: entero seguro > 0 (dominio compartido)
      typeof item.cantidad === "number" &&
      es_cantidad_valida(item.cantidad) &&
      item.cantidad > 0 &&
      // Precio: precioReferencia (unitario o por kg)
      precio_valido(item.precioReferencia)
    );

  if (!baseValida) return false;

  // Compatibilidad con jornadas creadas en etapas anteriores.
  if (jornada.estado === "cerrada") {
    return cierreValido(jornada.cierre);
  }

  return jornada.cierre === undefined;
}

/** Resultado discriminado de la lectura del ledger de jornadas (interno). */
export type ResultadoLecturaJornadas =
  | { ok: true; jornadas: Jornada[]; estado: "inicial" | "valido" }
  | { ok: false; error: string; estado: "corrupto" };

/**
 * Lectura que distingue: clave ausente (getItem === null → ledger inicial []),
 * clave presente y válida, y clave presente pero corrupta (incluye "" , "null",
 * JSON inválido, no array y cualquier jornada/ítem/cierre inválido).
 * Es la única autoridad para las escrituras.
 */
/**
 * Lectura discriminada y exportada (bloque E / M-2): es la única autoridad
 * tanto para las escrituras como para la revalidación de la Jornada vigente
 * justo antes de persistir en operaciones operativas (ventas, movimientos,
 * cobros con jornada, retornos, preparación). No existe parser paralelo.
 */
export function leerJornadasDiscriminado(): ResultadoLecturaJornadas {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (guardado === null) {
      return { ok: true, jornadas: [], estado: "inicial" };
    }

    let datos: unknown;
    try {
      datos = JSON.parse(guardado);
    } catch {
      return {
        ok: false,
        error: "JSON inválido en almacenamiento de jornadas.",
        estado: "corrupto",
      };
    }

    if (!Array.isArray(datos)) {
      return {
        ok: false,
        error: "Estructura inválida: se esperaba un array de jornadas.",
        estado: "corrupto",
      };
    }

    if (!datos.every(jornadaValida)) {
      return {
        ok: false,
        error: "Una o más jornadas no pasan la validación.",
        estado: "corrupto",
      };
    }

    return { ok: true, jornadas: datos, estado: "valido" };
  } catch (e) {
    return {
      ok: false,
      error: `Error inesperado al leer jornadas: ${String(e)}`,
      estado: "corrupto",
    };
  }
}

/**
 * Lectura para UI: fail-closed visual (devuelve [] tanto para ausente como
 * para corrupto). NO usar como autoridad en una escritura.
 */
export function leerJornadas(): Jornada[] {
  const lectura = leerJornadasDiscriminado();
  return lectura.ok ? lectura.jornadas : [];
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
 * Frontera ÚNICA de escritura: lee con discriminación de corrupción, aborta
 * (sin escribir) si el storage está corrupto, aplica la transformación y
 * persiste solo si esta devuelve las jornadas nuevas. Devuelve las jornadas
 * guardadas o null si se rechazó.
 */
function escribirJornadas(
  transformar: (actuales: Jornada[]) => Jornada[] | null
): Jornada[] | null {
  const lectura = leerJornadasDiscriminado();

  if (!lectura.ok) return null;

  const actualizadas = transformar(lectura.jornadas);

  if (!actualizadas) return null;

  return guardarJornadas(actualizadas) ? actualizadas : null;
}

/** Alta de jornada sin React. null si se rechaza (sin escribir). */
export function crearJornadaPersistida(
  jornada: Jornada
): Jornada[] | null {
  return escribirJornadas((actuales) => {
    if (
      actuales.some((j) => j.id === jornada.id) ||
      actuales.some(
        (j) =>
          j.camionId === jornada.camionId &&
          j.estado !== "cerrada"
      )
    ) {
      return null;
    }

    return [...actuales, jornada];
  });
}

/** Confirmación de salida sin React. null si se rechaza (sin escribir). */
export function confirmarSalidaPersistida(
  id: string
): Jornada[] | null {
  return escribirJornadas((actuales) => {
    const jornada = actuales.find((j) => j.id === id);

    if (!jornada || jornada.estado !== "preparacion") {
      return null;
    }

    return actuales.map((j) =>
      j.id === id
        ? {
            ...j,
            estado: "abierta" as const,
            fechaSalida: new Date().toISOString(),
          }
        : j
    );
  });
}

/**
 * Cierre de jornada sin React: valida, persiste y devuelve las jornadas
 * actualizadas, o null si se rechaza (sin escribir). Es lo que ejecuta el hook.
 */
export function cerrarJornadaPersistida(
  id: string,
  cierre: CierreJornada
): Jornada[] | null {
  return escribirJornadas((actuales) => {
    const jornada = actuales.find((j) => j.id === id);

    // No permitir cerrar dos veces la misma jornada.
    if (!jornada || jornada.estado !== "abierta") {
      return null;
    }

    // B1: la rendición de productos `peso` no está migrada (B4).
    if (jornada.items.some((item) => item.unidadMedida !== "unidad")) {
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

    return actuales.map((j) =>
      j.id === id
        ? {
            ...j,
            estado: "cerrada" as const,
            cierre,
          }
        : j
    );
  });
}

export type ResultadoCreacionPreparacion =
  | { ok: true; jornadas: Jornada[] }
  | { ok: false; error: string };

/**
 * M-3 (bloque E): creación de una preparación con relectura de las
 * dependencias mutables justo antes de persistir. Jornadas y Retornos pueden
 * cambiar o corromperse entre el montaje y el guardar: el snapshot del render
 * NO es autoridad para calcular el stock reservado ni para las comprobaciones
 * de unicidad. Esta frontera:
 *   1) releer Jornadas y Retornos discriminadamente (sin reinterpretar
 *      corrupto como vacío) y abortar si alguna falla;
 *   2) comprobar unicidad contra lo leído AHORA (id duplicado / camión con
 *      otra jornada activa);
 *   3) calcular el stock con las lecturas frescas vía el callback
 *      `validarStock` (pura, testeable) y abortar si no alcanza;
 *   4) persistir. Si algo falla, no se escribe nada y el raw queda intacto.
 * Devuelve las jornadas guardadas o el error concreto.
 */
export function crearPreparacionPersistida(
  jornada: Jornada,
  validarStock: (
    jornadasActuales: Jornada[],
    retornosActuales: RetornoDeposito[]
  ) => string | null
): ResultadoCreacionPreparacion {
  // B1: la carga de productos `peso` no está migrada (B2). Falla cerrado
  // antes de leer o escribir.
  if (jornada.items.some((item) => item.unidadMedida !== "unidad")) {
    return { ok: false, error: MENSAJE_PESO_NO_OPERABLE };
  }

  const lecturaJornadas = leerJornadasDiscriminado();

  if (!lecturaJornadas.ok) {
    return {
      ok: false,
      error: `No se puede guardar la preparación: ${lecturaJornadas.error}`,
    };
  }

  const lecturaRetornos = leerRetornosDiscriminado();

  if (!lecturaRetornos.ok) {
    return {
      ok: false,
      error: `No se puede guardar la preparación: ${lecturaRetornos.error}`,
    };
  }

  const jornadasActuales = lecturaJornadas.jornadas;

  // Unicidad contra el storage leído AHORA, no contra el montaje: la misma
  // jornada no dos veces y un camión sin otra jornada en curso.
  if (
    jornadasActuales.some((j) => j.id === jornada.id) ||
    jornadasActuales.some(
      (j) =>
        j.camionId === jornada.camionId &&
        j.estado !== "cerrada"
    )
  ) {
    return {
      ok: false,
      error: "Ya existe una jornada activa para ese camión.",
    };
  }

  const errorStock = validarStock(
    jornadasActuales,
    lecturaRetornos.retornos
  );

  if (errorStock) {
    return { ok: false, error: errorStock };
  }

  const jornadasNuevas = [...jornadasActuales, jornada];

  return guardarJornadas(jornadasNuevas)
    ? { ok: true, jornadas: jornadasNuevas }
    : {
        ok: false,
        error: "No se pudo guardar la preparación en este navegador.",
      };
}

export function useJornadas() {
  const [lectura] = useState(leerJornadasDiscriminado);
  const [jornadas, setJornadas] = useState<Jornada[]>(
    lectura.ok ? lectura.jornadas : []
  );

  // Cada operación delega en su función persistida (misma frontera que los
  // tests); el hook solo actualiza el estado si se guardó.
  function aplicar(actualizadas: Jornada[] | null): boolean {
    if (!actualizadas) return false;

    setJornadas(actualizadas);
    return true;
  }

  function crearJornada(jornada: Jornada): boolean {
    return aplicar(crearJornadaPersistida(jornada));
  }

  function confirmarSalida(id: string): boolean {
    return aplicar(confirmarSalidaPersistida(id));
  }

  function cerrarJornada(
    id: string,
    cierre: CierreJornada
  ): boolean {
    return aplicar(cerrarJornadaPersistida(id, cierre));
  }

  // M-3 (bloque E): el error concreto que devuelve la frontera persistida es
  // el que muestra la pantalla, sin duplicar lógica en el render.
  function crearPreparacion(
    jornada: Jornada,
    validarStock: (
      jornadasActuales: Jornada[],
      retornosActuales: RetornoDeposito[]
    ) => string | null
  ): string | null {
    const resultado = crearPreparacionPersistida(
      jornada,
      validarStock
    );

    if (resultado.ok) {
      setJornadas(resultado.jornadas);
      return null;
    }

    return resultado.error;
  }

  return {
    jornadas,
    crearJornada,
    crearPreparacion,
    confirmarSalida,
    cerrarJornada,
    estadoLectura: lectura.estado,
  };
}
