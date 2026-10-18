// Dominio puro de rendición de mercadería. Sin dependencias de infraestructura:
// no toca movimientos_stock, persistencia, Supabase, RPC, RLS ni dinero.
//
// Fuente: BLUEPRINT.md §7.4 (movimientos que entran y salen del camión) y §12
// (casos sin diferencia, con faltante y con sobrante).
//
//   esperado   = cargado - vendido - merma - otras_salidas
//   diferencia = contado - esperado
//
// El signo de la diferencia alcanza para leer el estado: 0 sin diferencia,
// < 0 faltante, > 0 sobrante.
//
// Nota: los identificadores van en snake_case por instrucción explícita de la
// tarea; el resto del frontend usa camelCase.

import { validar_cantidad } from "./cantidades";

/** Cantidades de una jornada expresadas en la unidad mínima del producto. */
export type EntradaEsperado = {
  cargado: number;
  vendido: number;
  merma: number;
  otras_salidas: number;
};

/**
 * Mercadería que debería volver del camión. Todos los componentes deben ser
 * cantidades almacenables. Si los descuentos superan lo cargado no se devuelve
 * un esperado negativo en silencio: es una inconsistencia que debe
 * regularizarse de forma trazable (§7.4).
 */
export function calcular_esperado(input: EntradaEsperado): number {
  validar_cantidad(input.cargado);
  validar_cantidad(input.vendido);
  validar_cantidad(input.merma);
  validar_cantidad(input.otras_salidas);

  const salidas = input.vendido + input.merma + input.otras_salidas;

  if (salidas > input.cargado) {
    throw new Error(
      `Inconsistencia de rendición: las salidas del camión (${salidas}) superan lo cargado (${input.cargado}). Requiere regularización trazable (§7.4).`
    );
  }

  return input.cargado - salidas;
}

/**
 * Diferencia entre lo contado y lo esperado. Ambas entradas deben ser
 * cantidades no negativas enteras; el resultado sí puede ser negativo, porque
 * una diferencia negativa representa un faltante.
 */
export function calcular_diferencia(contado: number, esperado: number): number {
  validar_cantidad(contado);
  validar_cantidad(esperado);

  return contado - esperado;
}
