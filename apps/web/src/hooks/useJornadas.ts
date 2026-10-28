import { useState } from "react";

import { CLAVES_STORAGE } from "../data/clavesStorage";
import { precio_valido } from "../domain/precios";
import {
  es_cantidad_valida,
  sumar_cantidades_seguras,
} from "../domain/cantidades";

import {
  type Jornada,
  type CierreJornada,
  type ItemCarga,
} from "../data/mockJornadas";
import type { Producto } from "../data/mockProductos";
import type { RetornoDeposito } from "../data/mockRetornos";
import { leerProductos } from "./useProductos";
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
      // `unidad` (unidades enteras) o `peso` (gramos enteros). B2 prepara y
      // confirma jornadas `peso`; el cierre sigue bloqueado hasta B4.
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

/**
 * Una jornada nueva sólo nace en `preparacion`: válida (jornadaValida), sin
 * fecha de salida y sin cierre. `abierta` y `cerrada` se alcanzan únicamente
 * por confirmarSalidaPersistida y cerrarJornadaPersistida (el cierre con
 * `peso` sigue bloqueado hasta B4). La única alta persistente es
 * crearPreparacionPersistida.
 */
function esPreparacionNueva(jornada: Jornada): boolean {
  return (
    jornadaValida(jornada) &&
    jornada.estado === "preparacion" &&
    jornada.fechaSalida === null &&
    jornada.cierre === undefined
  );
}

/**
 * Confirmación de salida sin React: `preparacion` → `abierta`. Devuelve las
 * jornadas guardadas o el error concreto; si se rechaza, no escribe.
 */
export type ResultadoConfirmacionSalida =
  | { ok: true; jornadas: Jornada[] }
  | { ok: false; error: string };

export function confirmarSalidaPersistida(
  id: string
): ResultadoConfirmacionSalida {
  const jornadas = escribirJornadas((actuales) => {
    const jornada = actuales.find((j) => j.id === id);

    // La jornada se valida tal como está guardada, no con el snapshot del
    // render. B2: una jornada con ítems `peso` puede salir.
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

  return jornadas
    ? { ok: true, jornadas }
    : { ok: false, error: "No se pudo confirmar la salida." };
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

    // La rendición de productos `peso` no está migrada (B4): falla cerrado,
    // sin escribir. Una jornada `peso` queda abierta hasta B4.
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

export const MENSAJE_PREPARACION_INVALIDA =
  "La preparación no es válida: revisá las cantidades, los precios y el estado de la carga.";

export const MENSAJE_STOCK_NO_CALCULABLE =
  "No se puede calcular el stock disponible: hay cantidades inválidas o fuera del rango seguro.";

/**
 * Stock comprometido del depósito por producto, en la unidad mínima
 * (unidades o gramos): lo cargado en todas las jornadas menos lo aprobado en
 * los retornos del mismo camión sobre jornadas cerradas. Misma semántica que
 * el cálculo previo de la pantalla Jornadas, sin aproximar nada:
 *   - las sumas son exactas (sumar_cantidades_seguras) y lanzan si exceden
 *     el rango seguro;
 *   - un retorno que no corresponde a una jornada cerrada del mismo camión no
 *     libera stock (no aplica; nunca aumenta el disponible);
 *   - un ítem de retorno inconsistente con su jornada (producto no cargado,
 *     otra unidad, cantidades no canónicas, aprobado > contado) lanza;
 *   - lo aprobado por jornada y producto nunca puede superar lo cargado en
 *     esa jornada: si lo supera, lanza. Así el depósito no recibe más de lo
 *     que salió y ningún reservado queda negativo.
 * Lanzar es fallar cerrado: quien llama no persiste nada.
 */
export function calcularStockReservado(
  jornadas: ReadonlyArray<Jornada>,
  retornos: ReadonlyArray<RetornoDeposito>
): Record<number, number> {
  const reservado: Record<number, number> = {};

  for (const jornada of jornadas) {
    for (const item of jornada.items) {
      reservado[item.productoId] = sumar_cantidades_seguras(
        reservado[item.productoId] ?? 0,
        item.cantidad
      );
    }
  }

  // Aprobado acumulado por jornada y producto (varios retornos de la misma
  // jornada se suman).
  const aprobadoPorJornada = new Map<string, number>();

  for (const retorno of retornos) {
    const jornadaOrigen = jornadas.find(
      (j) => j.id === retorno.jornadaId
    );
    if (
      !jornadaOrigen ||
      jornadaOrigen.estado !== "cerrada" ||
      jornadaOrigen.camionId !== retorno.camionId
    ) {
      continue;
    }
    for (const item of retorno.items) {
      const cargados = jornadaOrigen.items.filter(
        (p) => p.productoId === item.productoId
      );
      if (
        cargados.length === 0 ||
        cargados.some((p) => p.unidadMedida !== item.unidadMedida) ||
        !es_cantidad_valida(item.cantidadContada) ||
        !es_cantidad_valida(item.cantidadAprobada) ||
        item.cantidadAprobada > item.cantidadContada
      ) {
        throw new Error(
          `Retorno ${retorno.id} inconsistente con su jornada (producto ${item.productoId}).`
        );
      }

      const cargado = cargados.reduce(
        (total, p) => sumar_cantidades_seguras(total, p.cantidad),
        0
      );
      const clave = `${jornadaOrigen.id}:${item.productoId}`;
      const aprobado = sumar_cantidades_seguras(
        aprobadoPorJornada.get(clave) ?? 0,
        item.cantidadAprobada
      );
      if (aprobado > cargado) {
        throw new Error(
          `Retorno ${retorno.id}: lo aprobado (${aprobado}) supera lo cargado (${cargado}) del producto ${item.productoId}.`
        );
      }
      aprobadoPorJornada.set(clave, aprobado);

      // Entero seguro >= 0: el reservado del producto incluye lo cargado en
      // esta jornada y lo aprobado de ella nunca lo supera.
      reservado[item.productoId] =
        reservado[item.productoId] - item.cantidadAprobada;
    }
  }

  // Defensa: con las invariantes anteriores es inalcanzable.
  for (const cantidad of Object.values(reservado)) {
    if (!es_cantidad_valida(cantidad)) {
      throw new Error("Stock reservado inconsistente.");
    }
  }

  return reservado;
}

/**
 * Validación pura del stock de una preparación contra lecturas frescas de
 * Productos, Jornadas y Retornos. Compara en la unidad mínima (unidades o
 * gramos), sin conversión ni tolerancia: exceder el disponible por 1 g se
 * rechaza. Devuelve el error concreto o null si alcanza.
 */
export function validarStockPreparacion(
  items: ReadonlyArray<ItemCarga>,
  productos: ReadonlyArray<Producto>,
  jornadas: ReadonlyArray<Jornada>,
  retornos: ReadonlyArray<RetornoDeposito>
): string | null {
  let reservado: Record<number, number>;
  const pedido: Record<number, number> = {};

  try {
    reservado = calcularStockReservado(jornadas, retornos);
    for (const item of items) {
      pedido[item.productoId] = sumar_cantidades_seguras(
        pedido[item.productoId] ?? 0,
        item.cantidad
      );
    }
  } catch {
    return MENSAJE_STOCK_NO_CALCULABLE;
  }

  for (const item of items) {
    const producto = productos.find((p) => p.id === item.productoId);

    if (!producto) {
      return `El producto ${item.nombreProducto} ya no está en el catálogo.`;
    }

    // Sin conversión entre unidades: si el catálogo cambió la forma de
    // venta, la cantidad de la carga no es comparable con su stock.
    if (producto.unidadMedida !== item.unidadMedida) {
      return `La forma de venta de ${producto.nombre} cambió; revisá la carga.`;
    }

    // Sin Math.max: si el catálogo tiene menos stock que lo ya reservado, el
    // disponible es negativo y cualquier pedido (> 0) se rechaza.
    const disponible = producto.stock - (reservado[producto.id] ?? 0);

    if (pedido[producto.id] > disponible) {
      return `No hay stock suficiente de ${producto.nombre}.`;
    }
  }

  return null;
}

/**
 * M-3 (bloque E): creación de una preparación con relectura de las
 * dependencias mutables justo antes de persistir. Productos, Jornadas y
 * Retornos pueden cambiar o corromperse entre el montaje y el guardar: el
 * snapshot del render NO es autoridad para el stock ni para la unicidad.
 * Esta frontera:
 *   0) exige una preparación nueva válida (esPreparacionNueva): cantidades
 *      canónicas > 0, precios válidos, estado `preparacion`, sin salida ni
 *      cierre;
 *   1) relee Jornadas, Retornos y Productos discriminadamente (sin
 *      reinterpretar corrupto como vacío) y aborta si alguna falla;
 *   2) comprueba la unicidad contra lo leído AHORA (id duplicado / camión
 *      con otra jornada activa);
 *   3) valida el stock con esas lecturas (validarStockPreparacion: unidades
 *      o gramos exactos, sumas seguras) y aborta si no alcanza;
 *   4) persiste. Si algo falla, no se escribe nada y el raw queda intacto.
 * Devuelve las jornadas guardadas o el error concreto.
 */
export function crearPreparacionPersistida(
  jornada: Jornada
): ResultadoCreacionPreparacion {
  if (!esPreparacionNueva(jornada)) {
    return { ok: false, error: MENSAJE_PREPARACION_INVALIDA };
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

  const lecturaProductos = leerProductos();

  if (!lecturaProductos.ok) {
    return {
      ok: false,
      error: `No se puede guardar la preparación: ${lecturaProductos.error}`,
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

  const errorStock = validarStockPreparacion(
    jornada.items,
    lecturaProductos.datos,
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

  // Como crearPreparacion: devuelve el error concreto o null si se guardó.
  function confirmarSalida(id: string): string | null {
    const resultado = confirmarSalidaPersistida(id);

    if (resultado.ok) {
      setJornadas(resultado.jornadas);
      return null;
    }

    return resultado.error;
  }

  function cerrarJornada(
    id: string,
    cierre: CierreJornada
  ): boolean {
    return aplicar(cerrarJornadaPersistida(id, cierre));
  }

  // M-3 (bloque E): el error concreto que devuelve la frontera persistida es
  // el que muestra la pantalla, sin duplicar lógica en el render.
  function crearPreparacion(jornada: Jornada): string | null {
    const resultado = crearPreparacionPersistida(jornada);

    if (resultado.ok) {
      setJornadas(resultado.jornadas);
      return null;
    }

    return resultado.error;
  }

  return {
    jornadas,
    crearPreparacion,
    confirmarSalida,
    cerrarJornada,
    estadoLectura: lectura.estado,
  };
}
