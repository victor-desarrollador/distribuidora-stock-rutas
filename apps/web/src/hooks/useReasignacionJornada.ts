import { useEffect, useState } from "react";

import { obtenerPuertoJornadas, type Jornada, type PuertoJornadas } from "../lib/jornadas";
import {
  obtenerPuertoVendedoresJornada,
  type PuertoVendedoresJornada,
} from "../lib/vendedores_jornada";
import {
  VENDEDORES_INACTIVO,
  crearControladorVendedores,
  type EstadoVendedores,
} from "../pages/jornadas_apertura";
import type { ArbitroJornadas } from "../pages/jornadas_operacion";
import {
  REASIGNACION_INACTIVA,
  arbitroRevocable,
  crearControladorReasignacion,
  type EntradaReasignacion,
  type FaseReasignacion,
} from "../pages/jornadas_reasignacion";
import type { BuscarJornada } from "../pages/jornadas_correccion";

/**
 * Busca la jornada en su fecha con la lectura de B-02a (todas las páginas, sin
 * listados parciales; RLS decide las filas). La reasignación no cambia la
 * fecha: se consulta sólo la de la jornada. `undefined` si la lectura falló;
 * `null` si no es visible.
 */
export function buscarEnFecha(
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

export interface DependenciasReasignacion {
  // Se piden recién al usar el puerto: montar la pantalla no construye nada.
  puertoJornadas: () => Pick<PuertoJornadas, "ejecutar" | "leerTodasLasJornadas">;
  puertoVendedores: () => PuertoVendedoresJornada;
  generarClave?: () => string;
}

const DEPENDENCIAS_REALES: DependenciasReasignacion = {
  puertoJornadas: obtenerPuertoJornadas,
  puertoVendedores: obtenerPuertoVendedoresJornada,
};

/**
 * Una «sesión» de reasignación pertenece a UN contexto de autorización
 * (usuario, empresa y rol). Reúne el controlador de la operación y la lectura
 * de vendedores; `detener` la descarta: las respuestas tardías no publican ni
 * releen y su retención en el árbitro se libera.
 */
export function crearSesionReasignacion(
  releer: () => void,
  arbitro: ArbitroJornadas,
  publicarFase: (fase: FaseReasignacion) => void,
  publicarVendedores: (estado: EstadoVendedores) => void,
  deps: DependenciasReasignacion = DEPENDENCIAS_REALES
) {
  const participacion = arbitroRevocable(arbitro);
  const jornadas: Pick<PuertoJornadas, "ejecutar" | "leerTodasLasJornadas"> = {
    ejecutar: (comando, clave) => deps.puertoJornadas().ejecutar(comando, clave),
    leerTodasLasJornadas: (filtro) => deps.puertoJornadas().leerTodasLasJornadas(filtro),
  };
  const controlador = crearControladorReasignacion(
    jornadas,
    buscarEnFecha(jornadas),
    releer,
    publicarFase,
    { arbitro: participacion.arbitro, generarClave: deps.generarClave }
  );
  const vendedores = crearControladorVendedores(
    { listarVendedores: () => deps.puertoVendedores().listarVendedores() },
    publicarVendedores
  );

  return {
    controlador,
    vendedores,
    /** Abre el formulario y, sólo si se abrió, lee la lista vigente de vendedores. */
    solicitar(jornada: Jornada): void {
      controlador.solicitar(jornada);
      const f = controlador.obtener();
      if (f.fase === "confirmando" && f.jornadaId === jornada.id) void vendedores.recargar();
    },
    iniciar(): void {
      participacion.reactivar();
      controlador.iniciar();
      vendedores.iniciar();
    },
    detener(): void {
      controlador.detener();
      vendedores.detener();
      participacion.revocar();
    },
  };
}

export type SesionReasignacion = ReturnType<typeof crearSesionReasignacion>;

const nada = () => undefined;

/**
 * «Cambiar vendedor» (FE-2B). La lógica vive en `crearSesionReasignacion`;
 * este hook sólo la conecta con React.
 *
 * `contexto` es el contexto de autorización vigente (`contextoAutorizacionCarga`):
 * null para el vendedor/piloto o sin autorización verificada, y entonces no se
 * crea nada ni se lee nada. Si cambia, la sesión anterior se descarta (su
 * intención, su lista de vendedores y su retención en el árbitro).
 * `releer` y `arbitro` se toman UNA vez (como en `useCorreccionJornada`).
 */
export function useReasignacionJornada(
  contexto: string | null,
  releer: () => void,
  arbitro: ArbitroJornadas
) {
  const [fase, setFase] = useState<{ contexto: string | null; fase: FaseReasignacion }>({
    contexto,
    fase: REASIGNACION_INACTIVA,
  });
  const [vendedores, setVendedores] = useState<{ contexto: string | null; estado: EstadoVendedores }>({
    contexto,
    estado: VENDEDORES_INACTIVO,
  });
  const [sesionPara] = useState(() => {
    let actual: { contexto: string; sesion: SesionReasignacion } | null = null;
    return (ctx: string | null): SesionReasignacion | null => {
      if (ctx === null) return null;
      if (actual === null || actual.contexto !== ctx) {
        actual = {
          contexto: ctx,
          sesion: crearSesionReasignacion(
            releer,
            arbitro,
            (f) => setFase({ contexto: ctx, fase: f }),
            (e) => setVendedores({ contexto: ctx, estado: e })
          ),
        };
      }
      return actual.sesion;
    };
  });
  const sesion = sesionPara(contexto);

  useEffect(() => {
    if (sesion === null) return;
    sesion.iniciar();
    return () => sesion.detener();
  }, [sesion]);

  return {
    // Lo publicado por otro contexto no se muestra.
    fase: fase.contexto === contexto ? fase.fase : REASIGNACION_INACTIVA,
    vendedores: vendedores.contexto === contexto ? vendedores.estado : VENDEDORES_INACTIVO,
    solicitar: sesion ? sesion.solicitar : nada,
    cancelar: sesion ? sesion.controlador.cancelar : nada,
    confirmar: sesion
      ? (entrada: EntradaReasignacion) => void sesion.controlador.confirmar(entrada)
      : nada,
    reintentar: sesion ? () => void sesion.controlador.reintentar() : nada,
    verificarEstado: sesion ? () => void sesion.controlador.verificarEstado() : nada,
    recargarVendedores: sesion ? () => void sesion.vendedores.recargar() : nada,
    trasRelectura: sesion ? sesion.controlador.trasRelectura : nada,
  };
}
