// Contenido del respaldo JSON de la demo (ConfiguracionDemo).
//
// Whitelist explícita: sólo las claves vigentes del modelo (ADR-005 D-R4). Las
// claves operativas anteriores (`_demo_v4`, en medias piezas) no se leen, no
// se copian al respaldo y no se borran: quedan intactas en el navegador, fuera
// del modelo nuevo. No se usa un filtro genérico por prefijo.
import { CLAVE_CLIENTES, CLAVES_STORAGE } from "../data/clavesStorage";

export const CLAVES_RESPALDO: readonly string[] = [
  ...Object.values(CLAVES_STORAGE),
  CLAVE_CLIENTES,
];

/** Lee únicamente las claves de la whitelist; omite las ausentes. */
export function datosRespaldo(): Record<string, string> {
  const almacenamiento: Record<string, string> = {};

  for (const clave of CLAVES_RESPALDO) {
    const valor = localStorage.getItem(clave);

    if (valor !== null) {
      almacenamiento[clave] = valor;
    }
  }

  return almacenamiento;
}
