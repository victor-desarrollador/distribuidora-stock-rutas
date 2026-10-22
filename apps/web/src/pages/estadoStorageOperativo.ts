import type { EstadoLectura } from "./avisosStorage";

export type FuenteOperativa =
  | "jornadas"
  | "productos"
  | "camiones"
  | "clientes"
  | "ventas"
  | "movimientos"
  | "retornos";

const avisos: Record<FuenteOperativa, string> = {
  jornadas:
    "Los datos de jornadas guardados están dañados. No se puede continuar con esta operación con seguridad.",
  productos:
    "Los datos de productos guardados están dañados. El catálogo no está disponible para operar.",
  camiones:
    "Los datos de camiones guardados están dañados. El catálogo no está disponible para operar.",
  clientes:
    "Los datos de clientes guardados están dañados. El catálogo no está disponible para operar.",
  ventas:
    "Los datos de ventas guardados están dañados. No se puede calcular el stock operativo con seguridad.",
  movimientos:
    "Los datos de movimientos guardados están dañados. No se puede calcular el stock operativo con seguridad.",
  retornos:
    "Los datos de retornos guardados están dañados. No se puede calcular el stock operativo con seguridad.",
};

export interface EstadoStorageOperativo {
  avisos: string[];
  bloqueado: boolean;
}

/**
 * Evalúa solo las fuentes requeridas por una pantalla operativa. Ausencia
 * legítima y datos válidos permiten operar; corrupción bloquea sin reparar ni
 * escribir el storage.
 */
export function estadoStorageOperativo(
  fuentes: Partial<Record<FuenteOperativa, EstadoLectura>>
): EstadoStorageOperativo {
  const danadas = (Object.entries(fuentes) as Array<
    [FuenteOperativa, EstadoLectura]
  >).filter(([, estado]) => estado === "corrupto");

  return {
    avisos: danadas.map(([fuente]) => avisos[fuente]),
    bloqueado: danadas.length > 0,
  };
}
