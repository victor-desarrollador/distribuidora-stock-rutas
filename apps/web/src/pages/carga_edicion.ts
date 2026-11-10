// Estado de edición del formulario de carga (FE-1B), puro y sin React.
//
// Sólo describe lo que el usuario está escribiendo: productos, textos de
// cantidad y si pidió revisar el resumen. No genera claves, no llama RPC y no
// guarda nada en el navegador. Las reglas de validación son las del
// controlador FE-1 (`validarCarga`); este módulo no agrega ninguna.
//
// Vive fuera del panel (J-9 del plan CV-1): la relectura de la lista desmonta
// el detalle de la jornada, y lo escrito no debe perderse por eso. Dónde se
// aloja (hook de la pantalla o un nivel superior) depende de la decisión
// pendiente sobre E5/E6; este módulo sirve para cualquiera de las dos.

import {
  validarCarga,
  type EntradaCarga,
  type LineaEntradaCarga,
  type ProductoCarga,
} from "./jornadas_carga";

export interface EdicionCarga {
  lineas: readonly LineaEntradaCarga[];
  // true: se muestra el resumen para confirmar (sólo si las líneas son válidas).
  revisando: boolean;
  // true: el usuario ya intentó revisar; desde entonces se muestran los errores.
  mostrarErrores: boolean;
}

const LINEA_VACIA: LineaEntradaCarga = Object.freeze({ productoId: "", texto: "" });

export const EDICION_INICIAL: EdicionCarga = Object.freeze({
  lineas: Object.freeze([LINEA_VACIA]),
  revisando: false,
  mostrarErrores: false,
});

// Cualquier cambio en las líneas vuelve a la edición: el resumen confirmado
// debe ser exactamente lo que se envía.
function conLineas(e: EdicionCarga, lineas: LineaEntradaCarga[]): EdicionCarga {
  return { ...e, lineas: Object.freeze(lineas), revisando: false };
}

export function agregarLinea(e: EdicionCarga): EdicionCarga {
  return conLineas(e, [...e.lineas, LINEA_VACIA]);
}

/** Quita la línea `i`; siempre queda al menos una (vacía). */
export function quitarLinea(e: EdicionCarga, i: number): EdicionCarga {
  if (i < 0 || i >= e.lineas.length) return e;
  const resto = e.lineas.filter((_, k) => k !== i);
  return conLineas(e, resto.length === 0 ? [LINEA_VACIA] : resto);
}

/** Cambiar el producto borra la cantidad: la unidad puede cambiar (unidad ↔ kg). */
export function cambiarProducto(e: EdicionCarga, i: number, productoId: string): EdicionCarga {
  if (i < 0 || i >= e.lineas.length || e.lineas[i].productoId === productoId) return e;
  return conLineas(e, e.lineas.map((l, k) => (k === i ? { productoId, texto: "" } : l)));
}

export function cambiarTexto(e: EdicionCarga, i: number, texto: string): EdicionCarga {
  if (i < 0 || i >= e.lineas.length) return e;
  return conLineas(e, e.lineas.map((l, k) => (k === i ? { ...l, texto } : l)));
}

/** Pide el resumen: sólo pasa a revisión si `validarCarga` acepta las líneas. */
export function revisar(e: EdicionCarga, catalogo: readonly ProductoCarga[]): EdicionCarga {
  const v = validarCarga(entradaDe(e), catalogo);
  return { ...e, revisando: v.ok, mostrarErrores: true };
}

export function volverAEditar(e: EdicionCarga): EdicionCarga {
  return e.revisando ? { ...e, revisando: false } : e;
}

export function entradaDe(e: EdicionCarga): EntradaCarga {
  return { lineas: e.lineas.map((l) => ({ ...l })) };
}

export interface ErrorEdicion {
  mensaje: string;
  // Índice (desde 0) de la línea con el error, o null si es de la lista entera.
  linea: number | null;
}

/**
 * Primer error de la edición, con la línea donde ocurre, para marcarla como
 * inválida. `validarCarga` recorre las líneas en orden y sólo mira hacia atrás
 * (repetidos), así que la línea del primer error es la del prefijo más corto
 * que falla.
 */
export function errorEdicion(
  e: EdicionCarga,
  catalogo: readonly ProductoCarga[]
): ErrorEdicion | null {
  const total = validarCarga(entradaDe(e), catalogo);
  if (total.ok) return null;
  if (e.lineas.length === 0) return { mensaje: total.mensaje, linea: null };
  for (let k = 1; k <= e.lineas.length; k++) {
    const parcial = validarCarga({ lineas: e.lineas.slice(0, k).map((l) => ({ ...l })) }, catalogo);
    if (!parcial.ok) return { mensaje: total.mensaje, linea: k - 1 };
  }
  return { mensaje: total.mensaje, linea: null };
}

/** Productos que se ofrecen en la línea `i`: activos y no elegidos en otra línea. */
export function productosParaLinea(
  e: EdicionCarga,
  i: number,
  catalogo: readonly ProductoCarga[]
): ProductoCarga[] {
  const otros = new Set(
    e.lineas.filter((_, k) => k !== i).map((l) => l.productoId.toLowerCase())
  );
  return catalogo
    .filter((p) => p.activo && !otros.has(p.id.toLowerCase()))
    .sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
}
