// Frontera AUTORITATIVA de escritura de ventas (AUD-001).
//
// No acepta validadores del caller: relee Ventas, Jornadas y Movimientos y
// valida todo internamente justo antes de la única escritura.
//
// Limitación conocida del prototipo: localStorage no es transaccional. Una
// venta o un movimiento registrado después del render SE considera (lectura
// fresca), pero dos pestañas que escriben en el mismo instante pueden
// intercalarse entre la lectura y la escritura. La atomicidad real queda
// para la futura RPC/transacción en PostgreSQL (BLUEPRINT.md §3 y §6).
import { CLAVES_STORAGE } from "../data/clavesStorage";
import type { Venta } from "../data/mockVentas";
import { revalidar_jornada_para_operacion } from "../domain/jornadas";
import { validar_stock_venta } from "../domain/movimientos";
import { venta_nueva_valida } from "../domain/validacion";
import {
  es_venta_mixta,
  MENSAJE_VENTA_MIXTA_NO_HABILITADA,
  MENSAJE_VENTA_PRODUCTO_REPETIDO,
  tiene_productos_repetidos,
} from "../domain/venta";
import {
  leerJornadasDiscriminado,
  type ResultadoLecturaJornadas,
} from "./useJornadas";
import {
  leerMovimientosDiscriminado,
  type ResultadoLecturaMovimientos,
} from "./useMovimientos";
import { leerVentas, type ResultadoLecturaVentas } from "./ventasStorage";

// Texto observable conservado. La referencia a ADR-003 es histórica: el
// contrato vigente es ADR-005 (§2.3.4 lectura / regla vigente en escritura).
// Corregir el texto es una tarea aparte para no mezclarlo con AUD-001.
export const MENSAJE_VENTA_INVALIDA =
  "La venta no pasa la validación monetaria/estructural (ADR-003).";

export const MENSAJE_VENTA_NO_GUARDADA =
  "No se pudo guardar la venta en este navegador.";

export type ResultadoRegistroVenta =
  | { ok: true; ventas: Venta[] }
  | { ok: false; error: string };

/** Lectoras de datos (NO validadores). La frontera siempre usa las reales. */
export interface LectorasVenta {
  ventas: () => ResultadoLecturaVentas;
  jornadas: () => ResultadoLecturaJornadas;
  movimientos: () => ResultadoLecturaMovimientos;
}

const LECTORAS_REALES: LectorasVenta = {
  ventas: leerVentas,
  jornadas: leerJornadasDiscriminado,
  movimientos: leerMovimientosDiscriminado,
};

/**
 * Copia plana de la venta recibida: se valida y se persiste ESE snapshot, así
 * un objeto con getters o un Proxy no puede cambiar entre la validación y la
 * escritura. null si no es serializable o no es un objeto.
 */
function copiar_venta(venta: unknown): Venta | null {
  try {
    const copia: unknown = JSON.parse(JSON.stringify(venta));
    return typeof copia === "object" && copia !== null && !Array.isArray(copia)
      ? (copia as Venta)
      : null;
  } catch {
    return null;
  }
}

/**
 * Operación pura: valida y devuelve el ledger resultante. NO escribe; el
 * único caller productivo es registrarVentaPersistida.
 *
 * Orden (cada ledger se lee lo más tarde posible; una venta inválida no lee):
 *   0. snapshot plano de la venta;
 *   1. venta mixta `unidad` + `peso` → mensaje específico;
 *   1b. más de una línea del mismo producto → mensaje específico
 *       (AUD-B3-01; también lo exige venta_nueva_valida);
 *   2. venta_nueva_valida (estructura, al menos un ítem, regla vigente);
 *   3. Ventas legibles (corrupto → aborta);
 *   4. ID duplicado;
 *   5. Jornada de `venta.jornadaId` leída ahora: existe, mismo camión que
 *      `venta.camionId`, abierta (corrupto → aborta);
 *   6. Movimientos legibles (corrupto → aborta);
 *   7. stock exacto contra la jornada fresca (validar_stock_venta).
 */
export function registrarVentaOperacion(
  venta: Venta,
  leer: LectorasVenta
): ResultadoRegistroVenta {
  const ventaPlana = copiar_venta(venta);
  if (ventaPlana === null) {
    return { ok: false, error: MENSAJE_VENTA_INVALIDA };
  }

  if (Array.isArray(ventaPlana.items) && es_venta_mixta(ventaPlana.items)) {
    return { ok: false, error: MENSAJE_VENTA_MIXTA_NO_HABILITADA };
  }

  if (
    Array.isArray(ventaPlana.items) &&
    tiene_productos_repetidos(ventaPlana.items)
  ) {
    return { ok: false, error: MENSAJE_VENTA_PRODUCTO_REPETIDO };
  }

  if (!venta_nueva_valida(ventaPlana)) {
    return { ok: false, error: MENSAJE_VENTA_INVALIDA };
  }

  const lecturaVentas = leer.ventas();
  if (!lecturaVentas.ok) {
    return { ok: false, error: `No se puede registrar: ${lecturaVentas.error}` };
  }

  if (lecturaVentas.ventas.some((v) => v.id === ventaPlana.id)) {
    return { ok: false, error: "La venta ya fue registrada." };
  }

  const revalidacion = revalidar_jornada_para_operacion(
    leer.jornadas(),
    { id: ventaPlana.jornadaId, camionId: ventaPlana.camionId },
    "abierta"
  );
  if (!revalidacion.ok) {
    return { ok: false, error: `No se puede registrar: ${revalidacion.error}` };
  }

  const lecturaMovimientos = leer.movimientos();
  if (!lecturaMovimientos.ok) {
    return {
      ok: false,
      error: `No se puede registrar: ${lecturaMovimientos.error}`,
    };
  }

  const errorStock = validar_stock_venta(
    ventaPlana,
    revalidacion.jornada.items,
    lecturaVentas.ventas,
    lecturaMovimientos.movimientos
  );
  if (errorStock) return { ok: false, error: errorStock };

  return { ok: true, ventas: [...lecturaVentas.ventas, ventaPlana] };
}

/**
 * Frontera REAL de escritura sin React. Usa SIEMPRE las lectoras reales y
 * escribe exactamente una vez, sólo si todo pasó. `alGuardar` no participa en
 * ninguna decisión: se invoca únicamente después de una escritura exitosa.
 */
export function registrarVentaPersistida(
  venta: Venta,
  alGuardar?: (ventas: Venta[]) => void
): string | null {
  let guardadas: Venta[];
  try {
    const resultado = registrarVentaOperacion(venta, LECTORAS_REALES);
    if (!resultado.ok) return resultado.error;

    localStorage.setItem(
      CLAVES_STORAGE.ventas,
      JSON.stringify(resultado.ventas)
    );
    guardadas = resultado.ventas;
  } catch {
    return MENSAJE_VENTA_NO_GUARDADA;
  }

  alGuardar?.(guardadas);
  return null;
}
