// Bloque E / M-2: revalidación de la Jornada vigente justo antes de
// persistir. Funciones puras, testeables sin React, sin parser paralelo: la
// lectura es la del lector discriminado de `useJornadas`, que se pasa ya
// resuelta como parámetro.

import { type Jornada } from "../data/mockJornadas";

/** Estructura del resultado del lector discriminado de Jornadas. */
export type LecturaOperativaJornadas =
  | { ok: true; jornadas: Jornada[] }
  | { ok: false; error: string };

export type ResultadoRevalidacion =
  | { ok: true; jornada: Jornada }
  | { ok: false; error: string };

export type ResultadoRevalidacionIdentidad =
  | { ok: true; jornadaId: string }
  | { ok: false; error: string };

/**
 * Revalida una jornada vista por la pantalla contra el conjunto actual que
 * entrega el lector discriminado:
 *   - storage corrupto → abortar (no se confía en ningún snapshot);
 *   - jornada inexistente → abortar;
 *   - identidad: el camión de la jornada actual debe coincidir con el que
 *     quedó asociado en la operación de la pantalla;
 *   - estado: debe ser el requerido por la operación ("abierta" para ventas
 *     y movimientos, "cerrada" para retornos).
 *
 * Devuelve la jornada vigente leída AHORA, no el snapshot del montaje.
 */
export function revalidar_jornada_para_operacion(
  lectura: LecturaOperativaJornadas,
  jornadaRender: Pick<Jornada, "id" | "camionId">,
  estadoRequerido: "abierta" | "cerrada"
): ResultadoRevalidacion {
  if (!lectura.ok) {
    return {
      ok: false,
      error: `No se pueden verificar las jornadas: ${lectura.error}`,
    };
  }

  const actual = lectura.jornadas.find(
    (j) => j.id === jornadaRender.id
  );

  if (!actual) {
    return {
      ok: false,
      error: "La jornada seleccionada ya no existe.",
    };
  }

  if (actual.camionId !== jornadaRender.camionId) {
    return {
      ok: false,
      error:
        "La jornada cambió de camión. Actualizá la pantalla antes de continuar.",
    };
  }

  if (actual.estado !== estadoRequerido) {
    return {
      ok: false,
      error:
        estadoRequerido === "abierta"
          ? "La jornada ya no está abierta. No se puede registrar una nueva operación en ella."
          : "La jornada ya no está cerrada. No se puede registrar el retorno en ella.",
    };
  }

  return { ok: true, jornada: actual };
}

/**
 * Revalida la jornada asociada a un cobro (Cobros registra `jornadaId` como
 * string o null; la pantalla decide si aplica). Contrato vigente de la
 * pantalla: solo se ofrecen jornadas abiertas. Si un cobro puede registrarse
 * contra una jornada cerrada es una decisión pendiente del Blueprint: no se
 * inventa aquí una regla nueva, solo se exige que la jornada exista y esté
 * como la pantalla la ofrece.
 */
export function revalidar_jornada_para_cobro(
  lectura: LecturaOperativaJornadas,
  jornadaId: string
): ResultadoRevalidacionIdentidad {
  if (!lectura.ok) {
    return {
      ok: false,
      error: `No se pueden verificar las jornadas: ${lectura.error}`,
    };
  }

  if (!lectura.jornadas.some((j) => j.id === jornadaId)) {
    return {
      ok: false,
      error: "La jornada asociada al cobro ya no existe.",
    };
  }

  const abierta = lectura.jornadas.some(
    (j) => j.id === jornadaId && j.estado === "abierta"
  );

  if (!abierta) {
    return {
      ok: false,
      error: "La jornada asociada al cobro ya no está abierta.",
    };
  }

  return { ok: true, jornadaId };
}
