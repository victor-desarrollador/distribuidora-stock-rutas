import { useEffect, useState } from "react";

import { obtenerPuertoJornadas, type PuertoJornadas } from "../lib/jornadas";
import {
  SALIDA_INACTIVA,
  crearControladorSalida,
  type FaseSalida,
  type VerificarJornada,
} from "../pages/jornadas_salida";

/**
 * Lee el estado REAL de una jornada desde Supabase con la lectura de B-02a
 * (todas las jornadas de su fecha, sin listados parciales). `undefined` si la
 * lectura falló; `null` si la jornada no es visible.
 */
export function verificarConLectura(
  puerto: Pick<PuertoJornadas, "leerTodasLasJornadas">
): VerificarJornada {
  return async ({ id, fecha }) => {
    const r = await puerto.leerTodasLasJornadas({ fecha });
    if (!r.ok) return undefined;
    return r.datos.find((j) => j.id === id)?.estado ?? null;
  };
}

/**
 * «Confirmar salida» (B-02b.2 / S1). La lógica vive en
 * `crearControladorSalida`; este hook sólo la conecta con React. `releer` se
 * invoca después de un éxito (o de un cambio de estado detectado) para volver
 * a leer la lista desde Supabase.
 *
 * `releer` se toma UNA vez, al crear el controlador: debe delegar en algo
 * estable durante la vida del componente. `useJornadasLectura().recargar`
 * cumple: llama siempre al mismo controlador de lectura.
 */
export function useSalidaJornada(releer: () => void) {
  const [fase, setFase] = useState<FaseSalida>(SALIDA_INACTIVA);
  const [controlador] = useState(() => {
    const puerto = obtenerPuertoJornadas();
    return crearControladorSalida(puerto, verificarConLectura(puerto), releer, setFase);
  });

  useEffect(() => {
    controlador.iniciar();
    return () => controlador.detener();
  }, [controlador]);

  return {
    fase,
    solicitar: controlador.solicitar,
    cancelar: controlador.cancelar,
    confirmar: () => void controlador.confirmar(),
    reintentar: () => void controlador.reintentar(),
    verificarEstado: () => void controlador.verificarEstado(),
  };
}
