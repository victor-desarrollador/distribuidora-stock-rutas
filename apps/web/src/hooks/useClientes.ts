
import { useEffect, useState } from "react";

import {
  clientesIniciales,
  type Cliente,
} from "../data/mockClientes";

const STORAGE_KEY = "distribuidora_clientes_demo_v1";

function cargarClientes(): Cliente[] {
  try {
    const guardados = localStorage.getItem(STORAGE_KEY);

    if (!guardados) return clientesIniciales;

    const datos: unknown = JSON.parse(guardados);

    if (!Array.isArray(datos)) return clientesIniciales;

    const validos = datos.every((cliente) =>
      cliente !== null &&
      typeof cliente === "object" &&
      Number.isSafeInteger(cliente.id) &&
      typeof cliente.nombreComercio === "string" &&
      typeof cliente.titular === "string" &&
      typeof cliente.telefono === "string" &&
      typeof cliente.direccion === "string" &&
      typeof cliente.zona === "string" &&
      ["contado", "cuenta_corriente"].includes(cliente.condicionPago) &&
      Number.isFinite(cliente.limiteCredito) &&
      cliente.limiteCredito >= 0 &&
      typeof cliente.activo === "boolean"
    );

    return validos ? datos as Cliente[] : clientesIniciales;
  } catch {
    return clientesIniciales;
  }
}

export function useClientes() {
  const [clientes, setClientes] = useState<Cliente[]>(cargarClientes);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(clientes));
    } catch (error) {
      console.error("Error al guardar clientes:", error);
    }
  }, [clientes]);

  return { clientes, setClientes };
}
