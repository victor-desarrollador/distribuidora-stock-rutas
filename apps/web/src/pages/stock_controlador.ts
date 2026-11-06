// Controlador de la pantalla de stock real (B-01), independiente de React.
//
// - Lectura: sólo la última lectura iniciada publica su resultado; ante un
//   error no se muestran datos viejos (falla cerrado). La base es la autoridad.
// - Escritura: una sola operación en vuelo (guarda de doble envío); la clave
//   de idempotencia se reutiliza para el mismo intento hasta que se confirme
//   el éxito; después de cada éxito se vuelve a leer el stock.
// - El frontend nunca calcula ni corrige saldos: sólo llama a las RPC.

import {
  type DatosStock,
  type IntentoStock,
  type PuertoStock,
  type ResultadoStock,
} from "../lib/stock";
import { EN_CURSO, crearGestorIntentos, crearGuardaEnVuelo } from "./stock_formulario";

export type EstadoLecturaStock =
  | { estado: "cargando" }
  | { estado: "listo"; datos: DatosStock }
  | { estado: "error"; error: string };

export type ResultadoOperacionStock =
  | ResultadoStock<string>
  | { ok: false; enCurso: true };

export const MENSAJE_SIN_CLAVE =
  "El navegador no puede generar la clave de la operación. Usá un navegador actualizado.";

export function crearControladorStock(
  puerto: PuertoStock,
  publicar: (estado: EstadoLecturaStock) => void,
  generarClave: () => string | null
) {
  let lecturaVigente = 0;
  const guarda = crearGuardaEnVuelo();
  let falloClave = false;
  const gestor = crearGestorIntentos(() => {
    const clave = generarClave();
    if (clave === null) {
      falloClave = true;
      return "";
    }
    return clave;
  });

  async function leer(): Promise<void> {
    const lectura = ++lecturaVigente;
    const resultado = await puerto.leer();
    if (lectura !== lecturaVigente) return;
    publicar(
      resultado.ok
        ? { estado: "listo", datos: resultado.datos }
        : { estado: "error", error: resultado.error }
    );
  }

  async function recargar(): Promise<void> {
    publicar({ estado: "cargando" });
    await leer();
  }

  async function ejecutar(
    intento: IntentoStock
  ): Promise<ResultadoOperacionStock> {
    const resultado = await guarda.intentar(async () => {
      falloClave = false;
      const clave = gestor.claveParaIntento(intento);
      if (falloClave || clave === "") {
        // Sin clave no se envía nada: la RPC la exige (stock_clave_invalida).
        gestor.confirmarExito();
        return { ok: false as const, error: MENSAJE_SIN_CLAVE };
      }

      const respuesta = await puerto.ejecutar(intento, clave);
      if (respuesta.ok) {
        gestor.confirmarExito();
        await recargar();
      }
      return respuesta;
    });

    if (resultado === EN_CURSO) return { ok: false, enCurso: true };
    return resultado;
  }

  return {
    leer,
    recargar,
    ejecutar,
    get ocupado(): boolean {
      return guarda.ocupada;
    },
    // Al desmontar, ninguna lectura pendiente publica su resultado.
    detener(): void {
      lecturaVigente += 1;
    },
  };
}
