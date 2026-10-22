// Lectura y persistencia fail-closed de catálogos demo en localStorage
// (productos, camiones, clientes).
//
// Distingue tres estados de la clave:
//   - ausente  (getItem === null)             → "inicial": datos demo legítimos.
//   - válida   (JSON array, todo válido)       → "valido".
//   - corrupta (presente pero ""/"null"/JSON inválido/no array/elemento
//                inválido)                      → "corrupto".
//
// Un storage corrupto NO es "primera ejecución": nunca se reemplaza ni se pisa
// con los datos demo. No usa `if (!guardado)`, que mezclaría ausente con "".

export type EstadoCatalogo = "inicial" | "valido" | "corrupto";

export type ResultadoLectura<T> =
  | { ok: true; datos: T[]; estado: "inicial" | "valido" }
  | { ok: false; estado: "corrupto"; error: string };

export function leerCatalogo<T>(
  clave: string,
  validar: (elemento: unknown) => boolean,
  iniciales: T[]
): ResultadoLectura<T> {
  try {
    const guardado = localStorage.getItem(clave);

    if (guardado === null) {
      return { ok: true, datos: iniciales, estado: "inicial" };
    }

    let datos: unknown;
    try {
      datos = JSON.parse(guardado);
    } catch {
      return {
        ok: false,
        estado: "corrupto",
        error: `JSON inválido en ${clave}.`,
      };
    }

    if (!Array.isArray(datos)) {
      return {
        ok: false,
        estado: "corrupto",
        error: `Estructura inválida en ${clave}: se esperaba un array.`,
      };
    }

    if (!datos.every(validar)) {
      return {
        ok: false,
        estado: "corrupto",
        error: `Un elemento de ${clave} no pasa la validación.`,
      };
    }

    return { ok: true, datos: datos as T[], estado: "valido" };
  } catch (e) {
    return {
      ok: false,
      estado: "corrupto",
      error: `Error inesperado al leer ${clave}: ${String(e)}`,
    };
  }
}

/**
 * Persistencia que ejecuta el efecto de cada hook, atada al resultado de la
 * lectura inicial. Si esa lectura fue corrupta NO escribe nunca, ni siquiera
 * tras modificaciones del estado en la sesión: no hay recuperación automática
 * ni borrado del raw. Devuelve true solo si escribió.
 */
export function persistirCatalogo<T, U>(
  clave: string,
  datos: T[],
  lectura: ResultadoLectura<U>
): boolean {
  if (!lectura.ok) return false;

  try {
    localStorage.setItem(clave, JSON.stringify(datos));
    return true;
  } catch (error) {
    console.error(`Error al guardar ${clave}:`, error);
    return false;
  }
}
