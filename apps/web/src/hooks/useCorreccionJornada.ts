import { useEffect, useState } from "react";

import { obtenerPuertoJornadas, type PuertoJornadas } from "../lib/jornadas";
import {
  CORRECCION_INACTIVA,
  crearControladorCorreccion,
  type BuscarJornada,
  type EntradaCorreccion,
  type FaseCorreccion,
} from "../pages/jornadas_correccion";
import type { ArbitroJornadas } from "../pages/jornadas_operacion";

/**
 * Busca una jornada REAL en Supabase con la lectura de B-02a (todas las
 * jornadas de cada fecha, sin listados parciales). Una corrección puede haber
 * cambiado la fecha, por eso se consultan la original y la nueva. `undefined`
 * si alguna lectura falló; `null` si no es visible en ninguna.
 */
export function buscarConLectura(
  puerto: Pick<PuertoJornadas, "leerTodasLasJornadas">
): BuscarJornada {
  return async (id, fechas) => {
    for (const fecha of fechas) {
      const r = await puerto.leerTodasLasJornadas({ fecha });
      if (!r.ok) return undefined;
      const j = r.datos.find((x) => x.id === id);
      if (j) return j;
    }
    return null;
  };
}

/**
 * «Corregir jornada» (B-02b.2 / S2). La lógica vive en
 * `crearControladorCorreccion`; este hook sólo la conecta con React.
 *
 * `releer` se toma UNA vez, al crear el controlador: debe delegar en algo
 * estable durante la vida del componente (`useJornadasLectura().recargar`).
 * `arbitro` (también tomado una vez) es el árbitro compartido de la pantalla:
 * excluye la salida sobre la misma jornada (S2 M-02).
 */
export function useCorreccionJornada(releer: () => void, arbitro?: ArbitroJornadas) {
  const [fase, setFase] = useState<FaseCorreccion>(CORRECCION_INACTIVA);
  const [controlador] = useState(() => {
    const puerto = obtenerPuertoJornadas();
    return crearControladorCorreccion(puerto, buscarConLectura(puerto), releer, setFase, {
      arbitro,
    });
  });

  useEffect(() => {
    controlador.iniciar();
    return () => controlador.detener();
  }, [controlador]);

  return {
    fase,
    solicitar: controlador.solicitar,
    cancelar: controlador.cancelar,
    confirmar: (entrada: EntradaCorreccion) => void controlador.confirmar(entrada),
    reintentar: () => void controlador.reintentar(),
    verificarEstado: () => void controlador.verificarEstado(),
    trasRelectura: controlador.trasRelectura,
  };
}
