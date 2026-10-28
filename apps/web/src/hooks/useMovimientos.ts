
import { useState } from "react";

import { CLAVES_STORAGE } from "../data/clavesStorage";

import type { Jornada } from "../data/mockJornadas";
import { type MovimientoReparto } from "../data/mockMovimientos";
import { revalidar_jornada_para_operacion } from "../domain/jornadas";
import {
  es_cambio_mixto,
  MENSAJE_CAMBIO_MIXTO_NO_HABILITADO,
  movimiento_valido,
  producto_movimiento_valido,
  validar_stock_movimiento,
} from "../domain/movimientos";
import { leerJornadasDiscriminado } from "./useJornadas";
import { leerVentas } from "./useVentas";

const STORAGE_KEY = CLAVES_STORAGE.movimientos;

/** Resultado discriminado de la lectura del ledger de movimientos. */
export type ResultadoLecturaMovimientos =
  | { ok: true; movimientos: MovimientoReparto[]; estado: "valido" | "inicial" }
  | { ok: false; error: string; estado: "corrupto" };

/**
 * Lectura que distingue explícitamente:
 * - clave ausente: ledger inicial válido ([])
 * - clave presente y válida: movimientos cargados
 * - clave presente pero corrupta: error explícito
 * Es la única autoridad tanto para la frontera de escritura como para el
 * estado que la UI usa para advertir corrupción.
 */
export function leerMovimientosDiscriminado(): ResultadoLecturaMovimientos {
  try {
    const guardado = localStorage.getItem(STORAGE_KEY);

    if (guardado === null) {
      return { ok: true, movimientos: [], estado: "inicial" };
    }

    let datos: unknown;
    try {
      datos = JSON.parse(guardado);
    } catch {
      return {
        ok: false,
        error: "JSON inválido en almacenamiento de movimientos.",
        estado: "corrupto",
      };
    }

    if (!Array.isArray(datos)) {
      return {
        ok: false,
        error: "Estructura inválida: se esperaba un array de movimientos.",
        estado: "corrupto",
      };
    }

    const valido = datos.every(movimiento_valido);

    if (!valido) {
      return {
        ok: false,
        error: "Uno o más movimientos no pasan la validación estructural.",
        estado: "corrupto",
      };
    }

    return { ok: true, movimientos: datos as MovimientoReparto[], estado: "valido" };
  } catch (e) {
    return {
      ok: false,
      error: `Error inesperado al leer movimientos: ${String(e)}`,
      estado: "corrupto",
    };
  }
}

/**
 * Lectura para UI: comportamiento visual fail-closed.
 * Devuelve [] tanto para ausente como para corrupto (semántica existente).
 * NO usar en la frontera de escritura.
 */
export function leerMovimientos(): MovimientoReparto[] {
  const lectura = leerMovimientosDiscriminado();
  return lectura.ok ? lectura.movimientos : [];
}

export type ResultadoRegistroMovimiento =
  | { ok: true; movimientos: MovimientoReparto[] }
  | { ok: false; error: string };

/**
 * Operación pura de registro de movimiento: valida y devuelve el ledger
 * resultante, sin escribir nada. NO es una frontera: el único caller
 * productivo es registrarMovimientoPersistido, que inyecta la validación
 * autoritativa y persiste sólo si el resultado es ok.
 *
 * @param cargarActuales - Función que devuelve el estado actual con discriminación de corrupción.
 *   En producción usa `leerMovimientosDiscriminado()`. En tests puede inyectarse un mock.
 */
export function registrarMovimientoOperacion(
  movimiento: MovimientoReparto,
  validar: (actuales: MovimientoReparto[]) => string | null,
  cargarActuales: () => ResultadoLecturaMovimientos
): ResultadoRegistroMovimiento {
  // 1a. Un cambio unidad ↔ peso con lados por lo demás válidos recibe su
  //     motivo concreto, ANTES de cualquier efecto: no tiene semántica
  //     aprobada (B2) y no se convierte entre unidades.
  if (
    movimiento.tipo === "cambio" &&
    producto_movimiento_valido(movimiento.productoDevuelto) &&
    producto_movimiento_valido(movimiento.productoEntregado) &&
    es_cambio_mixto(movimiento.productoDevuelto, movimiento.productoEntregado)
  ) {
    return { ok: false, error: MENSAJE_CAMBIO_MIXTO_NO_HABILITADO };
  }

  // 1b. Validación estructural y de cantidades ANTES de cualquier efecto.
  //     `unidad` (unidades) y `peso` (gramos) se validan igual: enteros
  //     seguros > 0 en la unidad mínima.
  if (!movimiento_valido(movimiento)) {
    return {
      ok: false,
      error: "El movimiento no es válido: las cantidades deben ser enteros positivos y seguros.",
    };
  }

  // 2. Cargar estado previo con discriminación de corrupción (usa función inyectada).
  const lectura = cargarActuales();

  // 2b. Si el almacenamiento está corrupto, ABORTAR antes de cualquier efecto lateral.
  if (!lectura.ok) {
    return { ok: false, error: `No se puede registrar: ${lectura.error}` };
  }

  const actuales = lectura.movimientos;

  // 3. Duplicado por ID.
  if (actuales.some((m) => m.id === movimiento.id)) {
    return { ok: false, error: "Este movimiento ya está registrado." };
  }

  // 4. Validación externa de stock/disponibilidad.
  const error = validar(actuales);

  if (error) return { ok: false, error };

  // 5. Ledger resultante: quien llama persiste SOLO si todo pasó.
  return { ok: true, movimientos: [...actuales, movimiento] };
}

export const MENSAJE_MOVIMIENTO_OTRA_JORNADA =
  "No se puede registrar: el movimiento no corresponde a la jornada seleccionada.";

/**
 * M-2 (bloque E): validación de stock de un movimiento con lecturas frescas,
 * justo antes de persistir. La ejecuta siempre registrarMovimientoPersistido;
 * ningún caller puede reemplazarla ni omitirla:
 *   - revalida la jornada del render contra Jornadas leídas AHORA (existe,
 *     mismo camión, sigue abierta); storage corrupto → aborta;
 *   - exige que el movimiento pertenezca a esa jornada (mismo id y camión):
 *     si no, sus salidas nunca se descontarían de ella;
 *   - relee Ventas; corrupto → aborta;
 *   - valida las salidas contra lo cargado en la jornada vigente, menos
 *     ventas y movimientos actuales (`actuales` lo relee la frontera), en la
 *     unidad mínima y sin tolerancia (1 g de más se rechaza). Overflow →
 *     falla cerrado.
 */
export function validarMovimientoConLecturas(
  movimiento: MovimientoReparto,
  jornadaRender: Jornada,
  actuales: MovimientoReparto[]
): string | null {
  const revalidacionJornada = revalidar_jornada_para_operacion(
    leerJornadasDiscriminado(),
    jornadaRender,
    "abierta"
  );

  if (!revalidacionJornada.ok) {
    return `No se puede registrar: ${revalidacionJornada.error}`;
  }

  if (
    movimiento.jornadaId !== revalidacionJornada.jornada.id ||
    movimiento.camionId !== revalidacionJornada.jornada.camionId
  ) {
    return MENSAJE_MOVIMIENTO_OTRA_JORNADA;
  }

  const lecturaVentas = leerVentas();
  if (!lecturaVentas.ok) {
    return `No se puede registrar: ${lecturaVentas.error}`;
  }

  return validar_stock_movimiento(
    movimiento,
    revalidacionJornada.jornada.items,
    lecturaVentas.ventas,
    actuales
  );
}

/**
 * Frontera REAL de escritura sin React: lee el ledger de localStorage con
 * discriminación de corrupción, ejecuta SIEMPRE validarMovimientoConLecturas
 * (no acepta un validador del caller) y persiste sólo si todo pasa. Es lo que
 * ejecuta el hook. La jornada del render es un snapshot que se revalida
 * contra Jornadas leídas ahora. Si el almacenamiento está corrupto no escribe
 * nada (no lo reinterpreta como vacío ni lo pisa con solo el movimiento nuevo).
 */
export function registrarMovimientoPersistido(
  movimiento: MovimientoReparto,
  jornadaRender: Jornada
): ResultadoRegistroMovimiento {
  try {
    const resultado = registrarMovimientoOperacion(
      movimiento,
      (actuales) =>
        validarMovimientoConLecturas(movimiento, jornadaRender, actuales),
      leerMovimientosDiscriminado
    );

    if (!resultado.ok) return resultado;

    localStorage.setItem(STORAGE_KEY, JSON.stringify(resultado.movimientos));

    return resultado;
  } catch {
    return { ok: false, error: "No se pudo guardar el movimiento." };
  }
}

export function useMovimientos() {
  const [lectura] = useState(leerMovimientosDiscriminado);
  const [movimientos, setMovimientos] = useState<MovimientoReparto[]>(
    lectura.ok ? lectura.movimientos : []
  );

  // Devuelve el error concreto o null si se guardó.
  function registrarMovimiento(
    movimiento: MovimientoReparto,
    jornadaRender: Jornada
  ): string | null {
    const resultado = registrarMovimientoPersistido(movimiento, jornadaRender);

    if (resultado.ok) {
      setMovimientos(resultado.movimientos);
      return null;
    }

    return resultado.error;
  }

  return {
    movimientos,
    registrarMovimiento,
    estadoLectura: lectura.estado,
  };
}
