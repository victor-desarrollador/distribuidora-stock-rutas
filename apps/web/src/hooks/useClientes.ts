
import { useEffect, useState } from "react";

import {
  clientesIniciales,
  type Cliente,
} from "../data/mockClientes";

import {
  leerCatalogo,
  persistirCatalogo,
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
  const [clientes, setClientes] = useState<Cliente[]>(
    lectura.ok ? lectura.datos : []
  );

  useEffect(() => {
    // Storage corrupto: no se pisa el raw con datos demo ni con ediciones.
    persistirCatalogo(STORAGE_KEY, clientes, lectura);
  }, [clientes, lectura]);

  return { clientes, setClientes, estadoLectura: lectura.estado };
}
