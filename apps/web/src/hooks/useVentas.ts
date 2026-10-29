import { useState } from "react";
import type { Venta } from "../data/mockVentas";
import { registrarVentaPersistida } from "./registroVentas";
import { leerVentas } from "./ventasStorage";

// La lectura vive en ventasStorage (módulo hoja, sin otros hooks); se
// reexporta para que los consumidores sigan importando desde useVentas.
export { cargarVentas, leerVentas, type ResultadoLecturaVentas } from "./ventasStorage";

export function useVentas() {
  // Una sola lectura discriminada al montar: de ahí salen el estado y, solo si
  // no está corrupto, los datos. La UI usa `estadoLectura` para avisar.
  const [lectura] = useState(leerVentas);
  const [ventas, setVentas] = useState<Venta[]>(
    lectura.ok ? lectura.ventas : []
  );

  // La frontera relee Ventas, Jornada y Movimientos y valida el stock por sí
  // misma (AUD-001): el hook no acepta ni reenvía validadores.
  function registrarVenta(venta: Venta): string | null {
    return registrarVentaPersistida(venta, setVentas);
  }

  return {
    ventas,
    registrarVenta,
    estadoLectura: lectura.estado,
  };
}
