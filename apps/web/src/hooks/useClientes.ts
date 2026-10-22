
import { useState } from "react";

import {
  clientesIniciales,
  type Cliente,
} from "../data/mockClientes";

import {
  actualizarCatalogoPersistido,
  leerCatalogo,
  type ResultadoLectura,
} from "./catalogoStorage";

const STORAGE_KEY = "distribuidora_clientes_demo_v2";

function clienteValido(cliente: unknown): boolean {
  if (cliente === null || typeof cliente !== "object") return false;

  const c = cliente as Partial<Cliente>;

  return (
    Number.isSafeInteger(c.id) &&
    typeof c.nombreComercio === "string" &&
    typeof c.titular === "string" &&
    typeof c.telefono === "string" &&
    typeof c.direccion === "string" &&
    typeof c.zona === "string" &&
    ["contado", "cuenta_corriente"].includes(c.condicionPago ?? "") &&
    Number.isFinite(c.limiteCredito) &&
    (c.limiteCredito as number) >= 0 &&
    typeof c.activo === "boolean"
  );
}

/** Lectura discriminada (ausente / válido / corrupto). */
export function leerClientes(): ResultadoLectura<Cliente> {
  return leerCatalogo(STORAGE_KEY, clienteValido, clientesIniciales);
}

/** Datos para la UI: iniciales si está ausente o corrupto (nunca persiste). */
export function cargarClientes(): Cliente[] {
  const lectura = leerClientes();
  return lectura.ok ? lectura.datos : clientesIniciales;
}

export function useClientes() {
  const [lectura] = useState(leerClientes);
  const [clientes, setClientesEstado] = useState<Cliente[]>(
    lectura.ok ? lectura.datos : []
  );

  /**
   * Frontera explícita de edición (bloque E / M-1): relee la clave, aborta si
   * está corrupta (sin escribir ni cambiar React), persiste y solo si la
   * escritura tuvo éxito actualiza el estado. Devuelve false cuando la
   * operación no se guardó.
   */
  function actualizarClientes(
    transformar: (actuales: Cliente[]) => Cliente[]
  ): boolean {
    const nuevos = actualizarCatalogoPersistido(
      STORAGE_KEY,
      clienteValido,
      clientesIniciales,
      transformar
    );

    if (nuevos === null) return false;

    setClientesEstado(nuevos);
    return true;
  }

  return { clientes, actualizarClientes, estadoLectura: lectura.estado };
}
