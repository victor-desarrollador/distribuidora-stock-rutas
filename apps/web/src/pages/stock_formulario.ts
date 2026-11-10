// Lógica pura de la pantalla de stock real (B-01): validación del formulario,
// clave de idempotencia por intento, guarda de doble envío, formato de
// cantidades y armado de filas. Sin React ni Supabase: se prueba con Vitest.
//
// Reglas (Blueprint §7.1, §7.4, §7.7; ADR-005; ADR-001 §18.3):
//   - cantidades enteras > 0 en unidad mínima: unidades (`unidad`) o gramos
//     (`peso`, ingresados en kg con hasta 3 decimales y coma decimal); nunca
//     float, nunca redondeo ni truncamiento;
//   - ingreso: motivo opcional; cuarentena: motivo obligatorio; merma: código
//     de la lista de §7.7 y texto obligatorio sólo con «otro»;
//   - cuarentena y merma sólo desde el depósito (D3/D4): el origen no se elige.

import { kg_a_gramos } from "../domain/peso";
import {
  CANTIDAD_MAXIMA,
  MOTIVOS_MERMA,
  type DatosStock,
  type FormaVentaStock,
  type IntentoStock,
  type MotivoMerma,
  type ProductoStock,
} from "../lib/stock";

export type TipoOperacionStock = IntentoStock["tipo"];

export const ETIQUETA_OPERACION: Record<TipoOperacionStock, string> = {
  ingreso: "Ingreso",
  cuarentena: "A cuarentena",
  merma: "Merma",
};

export const ETIQUETA_MOTIVO_MERMA: Record<MotivoMerma, string> = {
  vencido: "Vencido",
  roto_danado: "Roto o dañado",
  mal_estado: "Mal estado",
  error_pedido: "Error de pedido",
  cambio: "Cambio",
  otro: "Otro",
};

export interface FormularioStock {
  tipo: TipoOperacionStock;
  productoId: string;
  // Unidades enteras (unidad) o kg con hasta 3 decimales (peso).
  cantidad: string;
  motivo: string;
  motivoCodigo: string;
}

export function formularioStockVacio(
  tipo: TipoOperacionStock = "ingreso"
): FormularioStock {
  return { tipo, productoId: "", cantidad: "", motivo: "", motivoCodigo: "" };
}

const ENTERO = /^\d+$/;

/**
 * Convierte el texto de cantidad a unidad mínima según la forma de venta.
 * Devuelve null si no es un entero > 0 (unidad) o kg válidos > 0 (peso), o si
 * supera el máximo de `p_cantidad integer`. Nunca redondea ni trunca.
 */
export function cantidadDesdeTexto(
  texto: string,
  formaVenta: FormaVentaStock
): number | null {
  const limpio = texto.trim();
  let cantidad: number | null;

  if (formaVenta === "unidad") {
    // Sólo dígitos: rechaza «1,5», «1.5», «1e3», «0x10», signos y espacios.
    cantidad = ENTERO.test(limpio) ? Number(limpio) : null;
  } else {
    cantidad = kg_a_gramos(limpio);
  }

  if (
    cantidad === null ||
    !Number.isSafeInteger(cantidad) ||
    cantidad <= 0 ||
    cantidad > CANTIDAD_MAXIMA
  ) {
    return null;
  }
  return cantidad;
}

export function esMotivoMerma(valor: string): valor is MotivoMerma {
  return (MOTIVOS_MERMA as readonly string[]).includes(valor);
}

export type ValidacionStock =
  | { ok: true; intento: IntentoStock }
  | { ok: false; error: string };

export function validarFormularioStock(
  formulario: FormularioStock,
  datos: DatosStock
): ValidacionStock {
  const producto = datos.productos.find((p) => p.id === formulario.productoId);
  if (!producto) return { ok: false, error: "Elegí un producto." };
  if (!producto.activo) {
    return { ok: false, error: "El producto está dado de baja." };
  }

  const cantidad = cantidadDesdeTexto(formulario.cantidad, producto.formaVenta);
  if (cantidad === null) {
    return {
      ok: false,
      error:
        producto.formaVenta === "peso"
          ? "Ingresá un peso mayor que cero en kg, con coma decimal y hasta 3 decimales (por ejemplo 1,250)."
          : "Ingresá una cantidad entera de unidades mayor que cero.",
    };
  }

  const motivo = formulario.motivo.trim();

  if (formulario.tipo === "ingreso") {
    return {
      ok: true,
      intento: {
        tipo: "ingreso",
        productoId: producto.id,
        cantidad,
        motivo: motivo === "" ? null : motivo,
      },
    };
  }

  if (formulario.tipo === "cuarentena") {
    if (motivo === "") {
      return { ok: false, error: "Indicá el motivo de la cuarentena." };
    }
    return {
      ok: true,
      intento: {
        tipo: "cuarentena",
        productoId: producto.id,
        origenId: datos.depositoId,
        cantidad,
        motivo,
      },
    };
  }

  if (!esMotivoMerma(formulario.motivoCodigo)) {
    return { ok: false, error: "Elegí el motivo de la merma." };
  }
  if (formulario.motivoCodigo === "otro" && motivo === "") {
    return { ok: false, error: "Describí el motivo de la merma." };
  }
  return {
    ok: true,
    intento: {
      tipo: "merma",
      productoId: producto.id,
      origenId: datos.depositoId,
      cantidad,
      motivoCodigo: formulario.motivoCodigo,
      motivo: motivo === "" ? null : motivo,
    },
  };
}

/** Firma estable del intento (sin la clave) para decidir si es el mismo. */
export function firmaIntento(intento: IntentoStock): string {
  return JSON.stringify(intento);
}

/**
 * Clave de idempotencia por intento (P12): el mismo intento (misma firma)
 * reutiliza la misma clave mientras no se confirme el éxito, así un reintento
 * después de un error de red no duplica la operación. Un intento distinto o
 * uno nuevo después de un éxito obtiene otra clave.
 */
export function crearGestorIntentos(generarClave: () => string) {
  let firma: string | null = null;
  let clave: string | null = null;

  return {
    claveParaIntento(intento: IntentoStock): string {
      const actual = firmaIntento(intento);
      if (clave === null || actual !== firma) {
        firma = actual;
        clave = generarClave();
      }
      return clave;
    },
    confirmarExito(): void {
      firma = null;
      clave = null;
    },
  };
}

export const EN_CURSO = Symbol("operacion-en-curso");

/**
 * Guarda de doble envío independiente del ciclo de render: mientras una
 * operación está en vuelo, cualquier otra devuelve EN_CURSO sin ejecutarse.
 */
export function crearGuardaEnVuelo() {
  let enVuelo = false;

  return {
    get ocupada(): boolean {
      return enVuelo;
    },
    async intentar<T>(operacion: () => Promise<T>): Promise<T | typeof EN_CURSO> {
      if (enVuelo) return EN_CURSO;
      enVuelo = true;
      try {
        return await operacion();
      } finally {
        enVuelo = false;
      }
    },
  };
}

/** Genera una clave uuid con la API del navegador; null si no existe. */
export function generarClaveNavegador(): string | null {
  const c = globalThis.crypto as Crypto | undefined;
  return typeof c?.randomUUID === "function" ? c.randomUUID() : null;
}

/**
 * Presenta una cantidad en unidad mínima: unidades («12 un.») o kg con 3
 * decimales fijos («1,250 kg»). Trabaja sobre el entero exacto (BigInt): nunca
 * pasa por `Number`, así un total mayor que Number.MAX_SAFE_INTEGER no pierde
 * precisión. Una cantidad no entera lanza (falla cerrado). Un negativo (no
 * debería existir) se muestra con signo, sin corregirlo.
 */
export function formatearCantidad(
  cantidad: number | bigint,
  formaVenta: FormaVentaStock
): string {
  const valor = BigInt(cantidad);
  const signo = valor < 0n ? "-" : "";
  const absoluto = valor < 0n ? -valor : valor;

  if (formaVenta === "peso") {
    const digitos = absoluto.toString().padStart(4, "0");
    return `${signo}${digitos.slice(0, -3)},${digitos.slice(-3)} kg`;
  }
  return `${signo}${absoluto} un.`;
}

// Los saldos individuales son enteros seguros (filaASaldo); sus sumas se hacen
// en BigInt porque pueden superar Number.MAX_SAFE_INTEGER.
export interface FilaStock {
  producto: ProductoStock;
  deposito: bigint;
  cuarentena: bigint;
  camiones: bigint;
  total: bigint;
}

/**
 * Una fila por producto con stock distinto de cero o activo. Las cantidades
 * son sumas exactas de saldos en unidad mínima.
 */
export function armarFilasStock(datos: DatosStock): FilaStock[] {
  const tipoPorUbicacion = new Map(datos.ubicaciones.map((u) => [u.id, u.tipo]));
  const filas = new Map<string, FilaStock>(
    datos.productos.map((p) => [
      p.id,
      { producto: p, deposito: 0n, cuarentena: 0n, camiones: 0n, total: 0n },
    ])
  );

  for (const saldo of datos.saldos) {
    const fila = filas.get(saldo.productoId);
    const tipo = tipoPorUbicacion.get(saldo.ubicacionId);
    if (!fila || !tipo) continue;
    const cantidad = BigInt(saldo.cantidad);
    if (tipo === "deposito") fila.deposito += cantidad;
    else if (tipo === "cuarentena") fila.cuarentena += cantidad;
    else fila.camiones += cantidad;
    fila.total += cantidad;
  }

  return [...filas.values()]
    // Un producto de baja se muestra sólo si todavía tiene stock en algún lado.
    .filter(
      (f) =>
        f.producto.activo ||
        f.deposito !== 0n ||
        f.cuarentena !== 0n ||
        f.camiones !== 0n
    )
    .sort((a, b) => a.producto.nombre.localeCompare(b.producto.nombre, "es-AR"));
}

/** Saldo en depósito de un producto (exacto, en BigInt). */
export function saldoDeposito(datos: DatosStock, productoId: string): bigint {
  return datos.saldos
    .filter((s) => s.productoId === productoId && s.ubicacionId === datos.depositoId)
    .reduce((suma, s) => suma + BigInt(s.cantidad), 0n);
}

export function textoUnidadEntrada(formaVenta: FormaVentaStock): string {
  return formaVenta === "peso" ? "kg (hasta 3 decimales)" : "unidades enteras";
}
