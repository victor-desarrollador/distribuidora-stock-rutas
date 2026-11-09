// Lectura de los vendedores asignables a una jornada (D-B2-1).
//
// Contrato aprobado (A-1 a A-4 y E-PL1 corregida, decisión del responsable):
//   public.listar_vendedores_jornada()  — sin parámetros
//   → filas (usuario_id uuid, nombre text, rol text)
// - Sólo perfiles ACTIVOS de la empresa del llamador, de los tres roles
//   aprobados (dueno, encargado, vendedor_piloto): ADR-007 §2.3.1 admite
//   cualquiera de ellos como vendedor.
// - Sólo la pueden usar dueño y encargado activos. El servidor decide.
// - Orden: nombre COLLATE "C", usuario_id. Se conserva el orden recibido (la
//   comparación de JavaScript no equivale a COLLATE "C" fuera del ASCII).
// - No expone el usuario de login ni el correo.
//
// Falla cerrada: una fila con otras columnas, un uuid inválido, un rol fuera de
// los tres aprobados, un nombre vacío o un usuario repetido invalidan TODA la
// lectura; nunca se muestra una lista parcial. Con conteo exacto se detecta un
// truncamiento del servidor (max_rows). Sin reintentos automáticos: es una
// lectura y la pantalla ofrece «Reintentar».
//
// Esta capa no inventa vendedores, no admite un uuid escrito a mano y no
// guarda nada en el navegador.

import type { SupabaseClient } from "@supabase/supabase-js";

import { esRolUsuario, type RolUsuario } from "../auth/roles";
import { esUuid } from "./jornadas";
import { obtenerClienteSupabase } from "./supabase";

export interface VendedorJornada {
  usuarioId: string;
  nombre: string;
  rol: RolUsuario;
}

export type ResultadoVendedores =
  | { ok: true; vendedores: VendedorJornada[] }
  | { ok: false; mensaje: string };

export interface PuertoVendedoresJornada {
  listarVendedores(): Promise<ResultadoVendedores>;
}

export const RPC_LISTAR_VENDEDORES = "listar_vendedores_jornada";

export const MENSAJE_ERROR_VENDEDORES =
  "No se pudo leer la lista de vendedores. Intentá de nuevo.";
export const MENSAJE_SIN_PERMISO_VENDEDORES =
  "No tenés permiso para ver los vendedores de la empresa.";

// Columnas exactas del contrato, en orden alfabético para compararlas.
const COLUMNAS_CONTRATO = ["nombre", "rol", "usuario_id"] as const;

/** Convierte una fila del contrato; `null` si no cumple exactamente con él. */
export function filaAVendedor(fila: unknown): VendedorJornada | null {
  if (fila === null || typeof fila !== "object" || Array.isArray(fila)) return null;
  const claves = Object.keys(fila).sort();
  if (
    claves.length !== COLUMNAS_CONTRATO.length ||
    claves.some((c, i) => c !== COLUMNAS_CONTRATO[i])
  ) {
    return null;
  }
  const f = fila as Record<string, unknown>;
  if (
    !esUuid(f.usuario_id) ||
    typeof f.nombre !== "string" ||
    f.nombre.trim() === "" ||
    !esRolUsuario(f.rol)
  ) {
    return null;
  }
  return { usuarioId: f.usuario_id.toLowerCase(), nombre: f.nombre, rol: f.rol };
}

function mensajeError(error: unknown): string {
  if (error !== null && typeof error === "object") {
    const { code } = error as { code?: unknown };
    // Rechazo de permisos genérico de PostgreSQL/PostgREST (no es un código
    // propio del contrato): el llamador no es dueño ni encargado activo.
    if (code === "42501" || code === "PT403") return MENSAJE_SIN_PERMISO_VENDEDORES;
  }
  return MENSAJE_ERROR_VENDEDORES;
}

export function crearPuertoVendedoresJornada(
  cliente: SupabaseClient
): PuertoVendedoresJornada {
  return {
    async listarVendedores() {
      try {
        const { data, error, count } = await cliente.rpc(
          RPC_LISTAR_VENDEDORES,
          {},
          { count: "exact" }
        );
        if (error) return { ok: false, mensaje: mensajeError(error) };
        if (!Array.isArray(data)) return { ok: false, mensaje: MENSAJE_ERROR_VENDEDORES };
        // Consistencia de tamaño: si el servidor truncó, la lista no es confiable.
        if (typeof count !== "number" || count !== data.length) {
          return { ok: false, mensaje: MENSAJE_ERROR_VENDEDORES };
        }
        const vendedores: VendedorJornada[] = [];
        const vistos = new Set<string>();
        for (const fila of data as unknown[]) {
          const v = filaAVendedor(fila);
          if (v === null || vistos.has(v.usuarioId)) {
            return { ok: false, mensaje: MENSAJE_ERROR_VENDEDORES };
          }
          vistos.add(v.usuarioId);
          vendedores.push(v);
        }
        return { ok: true, vendedores };
      } catch {
        return { ok: false, mensaje: MENSAJE_ERROR_VENDEDORES };
      }
    },
  };
}

let puerto: PuertoVendedoresJornada | null = null;

export function obtenerPuertoVendedoresJornada(): PuertoVendedoresJornada {
  if (!puerto) puerto = crearPuertoVendedoresJornada(obtenerClienteSupabase());
  return puerto;
}
