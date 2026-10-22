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
 *
 * En desuso desde el bloque E: los hooks ya no persisten por efecto; usan
 * `actualizarCatalogoPersistido`. Se conserva porque sus pruebas siguen
 * documentando la frontera atada a la lectura inicial.
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

/**
 * Frontera explícita de escritura de catálogos (bloque E / M-1). No debe
 * usarse la lectura capturada al montar como autoridad:
 *
 * 1. relee la clave discriminadamente AHORA (una corrupción aparecida
 *    después del montaje aborta la operación);
 * 2. aplica la transformación sobre los datos actuales y valida el conjunto
 *    nuevo completo;
 * 3. si la clave está corrupta o el conjunto nuevo es inválido, aborta
 *    sin escribir y devuelve null (el estado React NO cambia);
 * 4. persiste; si `setItem` lanza, la operación falla y el raw queda como
 *    estaba;
 * 5. solo si la escritura tuvo éxito devuelve el conjunto persistido
 *    (el llamador actualiza React recién entonces).
 *
 * Con clave ausente (getItem === null) el estado inicial es legítimo: la
 * relectura entrega `iniciales` y el primer cambio se persiste a partir de
 * ese conjunto.
 */
export function actualizarCatalogoPersistido<T>(
  clave: string,
  validar: (elemento: unknown) => boolean,
  iniciales: T[],
  transformar: (actuales: T[]) => T[]
): T[] | null {
  const lectura = leerCatalogo<T>(clave, validar, iniciales);

  if (!lectura.ok) return null;

  const actuales = lectura.datos;
  let nuevos: T[];

  try {
    nuevos = transformar(actuales);
  } catch {
    return null;
  }

  if (!Array.isArray(nuevos) || !nuevos.every(validar)) {
    return null;
  }

  try {
    localStorage.setItem(clave, JSON.stringify(nuevos));
  } catch (error) {
    console.error(`Error al guardar ${clave}:`, error);
    return null;
  }

  return nuevos;
}
