// Cálculos puros de la pantalla de rendición de mercadería.
//
// Vive fuera de `Rendicion.tsx` a propósito: la pantalla es un componente y no
// debe exportar funciones puras (regla `react-refresh/only-export-components`),
// y así los cálculos se pueden probar sin montar React.
//
// Sin dependencias de infraestructura: no toca stock, dinero, persistencia,
// localStorage, Supabase, RPC, RLS ni migraciones. No modifica datos.
//
// Fuente: BLUEPRINT.md §2 y §7.1 (unidad / pieza / media pieza; nunca
// kilogramo) y §7.4 (salidas del camión).
//
// Reglas:
//   - `unidad` y `pieza` se concilian con el mismo algoritmo y el mismo dominio
//     canónico (`calcular_esperado`, `calcular_diferencia`): todas las
//     cantidades son enteros seguros >= 0 en la unidad mínima (unidad entera o
//     medias piezas). Solo cambia cómo se muestran.
//   - cualquier otra unidad (kilogramo): no soportada por el negocio; no tiene
//     camino funcional en la pantalla (estado defensivo `no_soportada`).
//   - No se convierte ningún dato legacy ni se usan tolerancias.

import type { ItemCarga } from "../data/mockJornadas";
import type {
  MovimientoReparto,
} from "../data/mockMovimientos";
import { salidasPorMovimiento } from "../data/mockMovimientos";
import {
  es_cantidad_valida,
  recomponer_medias,
  sumar_cantidades_seguras,
} from "../domain/cantidades";
import {
  calcular_diferencia,
  calcular_esperado,
} from "../domain/rendicion";

export type EstadoFilaMercaderia =
  /** Conciliable con el dominio canónico. */
  | "ok"
  /** Componentes inválidos, acumulación insegura o salidas > cargado. */
  | "inconsistente"
  /** Unidad fuera del dominio (por ejemplo kilogramo). */
  | "no_soportada";

/** Entrada de UI de un conteo: texto del input entero + media opcional. */
export interface EntradaConteo {
  /** "unidad": cantidad entera. "pieza": piezas completas. */
  texto: string;
  /** Solo "pieza". En "unidad" debe ser false. */
  media: boolean;
}

export interface EntradaFilaMercaderia {
  item: ItemCarga;
  vendido: number;
  merma: number;
  reemplazos: number;
  /** Conteo físico ya convertido a cantidad canónica; null si no hay. */
  contado: number | null;
  /** La acumulación de salidas no pudo calcularse exactamente. */
  acumulacionInvalida?: boolean;
}

export interface FilaMercaderia {
  productoId: number;
  nombreProducto: string;
  unidadMedida: ItemCarga["unidadMedida"];
  cargado: number;
  vendido: number;
  merma: number;
  reemplazos: number;
  /** merma + reemplazos, exacto; null si no puede calcularse. */
  mermaYCambios: number | null;
  esperado: number | null;
  contado: number | null;
  diferencia: number | null;
  estado: EstadoFilaMercaderia;
}

/** Lee un número finito >= 0 de un texto; `null` si está vacío o es inválido. */
export function leerCantidad(
  texto: string | undefined
): number | null {
  if (texto === undefined || texto.trim() === "") {
    return null;
  }

  const cantidad = Number(texto);

  return Number.isFinite(cantidad) && cantidad >= 0
    ? cantidad
    : null;
}

/**
 * Conteo almacenable: entero seguro >= 0 (BLUEPRINT §7.4). Devuelve `null` si
 * el texto está vacío, no es numérico, es negativo, tiene decimales o excede el
 * rango seguro.
 */
export function conteoValido(
  texto: string | undefined
): number | null {
  const cantidad = leerCantidad(texto);

  return cantidad !== null && es_cantidad_valida(cantidad)
    ? cantidad
    : null;
}

/**
 * Convierte la entrada de UI de un conteo en cantidad canónica, o null si está
 * vacía o es inválida. `pieza`: piezas enteras + media opcional →
 * medias piezas. No lanza.
 */
export function conteoDesdeEntrada(
  unidad: ItemCarga["unidadMedida"],
  entrada: EntradaConteo | undefined
): number | null {
  if (!entrada) return null;

  const textoVacio = entrada.texto.trim() === "";

  if (textoVacio && !entrada.media) return null;

  const base = textoVacio ? 0 : conteoValido(entrada.texto);

  if (base === null) return null;

  if (unidad === "unidad") {
    return entrada.media ? null : base;
  }

  if (unidad === "pieza") {
    try {
      return recomponer_medias({ piezas: base, media: entrada.media });
    } catch {
      return null;
    }
  }

  return null;
}

/**
 * Calcula la fila de mercadería de una jornada.
 *
 * No lanza hacia React: si las salidas superan lo cargado, hay componentes
 * inválidos o una acumulación insegura, devuelve la fila `inconsistente`.
 */
export function calcularFilaMercaderia(
  entrada: EntradaFilaMercaderia
): FilaMercaderia {
  const { item, vendido, merma, reemplazos } = entrada;
  const contado =
    entrada.contado !== null && es_cantidad_valida(entrada.contado)
      ? entrada.contado
      : null;

  let mermaYCambios: number | null;

  try {
    mermaYCambios = sumar_cantidades_seguras(merma, reemplazos);
  } catch {
    mermaYCambios = null;
  }

  const base = {
    productoId: item.productoId,
    nombreProducto: item.nombreProducto,
    unidadMedida: item.unidadMedida,
    cargado: item.cantidad,
    vendido,
    merma,
    reemplazos,
    mermaYCambios,
    contado,
  };

  if (item.unidadMedida !== "unidad" && item.unidadMedida !== "pieza") {
    // Kilogramo u otra unidad fuera del Blueprint: sin camino funcional.
    return {
      ...base,
      esperado: null,
      diferencia: null,
      estado: "no_soportada",
    };
  }

  const inconsistente = (): FilaMercaderia => ({
    ...base,
    esperado: null,
    diferencia: null,
    estado: "inconsistente",
  });

  // Mismo algoritmo para unidad y pieza: enteros seguros en la unidad mínima.
  if (
    entrada.acumulacionInvalida ||
    !es_cantidad_valida(item.cantidad) ||
    !es_cantidad_valida(vendido) ||
    !es_cantidad_valida(merma) ||
    !es_cantidad_valida(reemplazos)
  ) {
    return inconsistente();
  }

  try {
    const esperado = calcular_esperado({
      cargado: item.cantidad,
      vendido,
      merma,
      otras_salidas: reemplazos,
    });

    return {
      ...base,
      esperado,
      diferencia:
        contado === null ? null : calcular_diferencia(contado, esperado),
      estado: "ok",
    };
  } catch {
    // Salidas > cargado u overflow: inconsistencia sin romper el render.
    return inconsistente();
  }
}

export interface SalidasProducto {
  vendido: number;
  merma: number;
  reemplazos: number;
  /** false si alguna acumulación fue inválida o superó el rango seguro. */
  valido: boolean;
}

interface VentaConItems {
  jornadaId: string;
  items: ReadonlyArray<{ productoId: number; cantidad: number }>;
}

/**
 * Acumula vendido / merma / reemplazos de un producto en una jornada con suma
 * exacta. Ante una cantidad inválida o un desbordamiento devuelve valido:false
 * (la fila terminará inconsistente); nunca un valor aproximado.
 */
export function acumularSalidasProducto(
  productoId: number,
  jornadaId: string,
  ventas: ReadonlyArray<VentaConItems>,
  movimientos: ReadonlyArray<MovimientoReparto>
): SalidasProducto {
  let vendido = 0;
  let merma = 0;
  let reemplazos = 0;

  try {
    for (const venta of ventas) {
      if (venta.jornadaId !== jornadaId) continue;

      for (const detalle of venta.items) {
        if (detalle.productoId === productoId) {
          vendido = sumar_cantidades_seguras(vendido, detalle.cantidad);
        }
      }
    }

    for (const movimiento of movimientos) {
      if (movimiento.jornadaId !== jornadaId) continue;

      if (
        movimiento.tipo === "merma" &&
        movimiento.producto.productoId === productoId
      ) {
        merma = sumar_cantidades_seguras(
          merma,
          movimiento.producto.cantidad
        );
      }

      if (movimiento.tipo === "cambio") {
        for (const salida of salidasPorMovimiento(movimiento)) {
          if (salida.productoId === productoId) {
            reemplazos = sumar_cantidades_seguras(
              reemplazos,
              salida.cantidad
            );
          }
        }
      }
    }
  } catch {
    return { vendido: 0, merma: 0, reemplazos: 0, valido: false };
  }

  return { vendido, merma, reemplazos, valido: true };
}

export interface ProductoCuarentena {
  productoId: number;
  nombre: string;
  unidadMedida: ItemCarga["unidadMedida"];
  /** null: el acumulado no puede calcularse exactamente. */
  cantidad: number | null;
}

/**
 * Productos devueltos/cambiados de la jornada, solo informativo (no aumenta el
 * stock vendible). La cantidad se acumula con suma exacta; si no puede
 * calcularse queda en null y la pantalla no muestra un saldo aproximado.
 */
export function acumularCuarentena(
  jornadaId: string,
  movimientos: ReadonlyArray<MovimientoReparto>
): ProductoCuarentena[] {
  const acumulado = new Map<number, ProductoCuarentena>();

  for (const movimiento of movimientos) {
    if (movimiento.jornadaId !== jornadaId || movimiento.tipo === "merma") {
      continue;
    }

    const producto =
      movimiento.tipo === "cambio"
        ? movimiento.productoDevuelto
        : movimiento.producto;

    const anterior = acumulado.get(producto.productoId);

    let cantidad: number | null;

    try {
      cantidad = sumar_cantidades_seguras(
        anterior ? anterior.cantidad ?? Number.NaN : 0,
        producto.cantidad
      );
    } catch {
      cantidad = null;
    }

    acumulado.set(producto.productoId, {
      productoId: producto.productoId,
      nombre: producto.nombreProducto,
      unidadMedida: producto.unidadMedida,
      cantidad,
    });
  }

  return [...acumulado.values()];
}

/**
 * Una jornada solo se puede rendir si todas sus filas quedaron conciliables.
 * Bloquea «Completar con esperados» y «Confirmar cierre» cuando hay filas
 * inconsistentes o con unidad no soportada.
 */
export function bloqueaRendicion(
  filas: FilaMercaderia[]
): boolean {
  return filas.some((fila) => fila.estado !== "ok");
}
