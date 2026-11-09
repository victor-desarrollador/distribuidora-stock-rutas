import { useLayoutEffect, useMemo, useState, type ReactNode } from "react";

import { useAuth } from "../auth/useAuth";
import {
  borradorSinGuardar,
  contextoAutorizacionCarga,
  crearAccionesBorrador,
  estadoBorradorVacio,
  estadoDeContexto,
} from "../pages/carga_borrador";
import { BorradorCargaContexto, type ContextoBorradorCarga } from "./borradorCargaContexto";
import { useAvisoSalidaPagina } from "./useAvisoSalidaPagina";

// Borrador de carga por ENCIMA del router (FE-1D): navegar entre secciones de
// la aplicación no lo pierde. Sólo memoria del proceso: recargar la página,
// cerrar la pestaña, cerrar sesión o cambiar el contexto de autorización lo
// descartan.
//
// No consume ni construye ningún puerto de ejecución (`registrar_carga` sigue
// deshabilitada por DP-1): sólo guarda lo escrito. Consume `useAuth` sin cambiar
// su contrato.
//
// FE-1F (H-01): el dueño del borrador es el contexto de autorización efectivo
// (usuario + empresa + rol de gestión, `contextoAutorizacionCarga`), derivado
// de la sesión publicada por AuthContext; no hay otra fuente de verdad. Si
// cambia la empresa o el rol del MISMO usuario (CV-1 revalida sin desmontar),
// o la autorización pasa a cargando/bloqueada/error, el borrador y la solicitud
// pendiente se descartan en el mismo render, y las acciones creadas en renders
// anteriores dejan de operar.
//
// FE-1E: abrir la carga de otra jornada, cerrar sesión o (FE-1F) «Cancelar» con
// algo escrito queda PENDIENTE hasta que la persona acepte descartar o cancele
// (`pendiente`). El provider no cierra sesión: sólo informa si quien lo pide
// puede continuar.
//
// Aviso al recargar o cerrar (T-1, `useAvisoSalidaPagina`): mientras haya algo
// escrito el navegador pide confirmar, pero puede no mostrarlo (sin interacción
// previa, cierre forzado, falla del dispositivo). No es una protección completa
// ni recupera el borrador.
// Registro del contexto vigente, fuera del estado de React: sólo lo escribe el
// efecto de confirmación del render y sólo lo leen las acciones al ejecutarse.
function crearVigencia(inicial: string | null) {
  let vigente = inicial;
  return {
    fijar(contexto: string | null) {
      vigente = contexto;
    },
    es(contexto: string | null) {
      return vigente === contexto;
    },
  };
}

export function BorradorCargaProvider({ children }: { children: ReactNode }) {
  const { sesion } = useAuth();
  const contexto = contextoAutorizacionCarga(sesion);
  const [estado, setEstado] = useState(() => estadoBorradorVacio(contexto));

  // Cambio real de contexto (otra cuenta, otra empresa, otro rol, perder la
  // autorización o cerrar sesión): se descarta en el mismo render, sin
  // preguntar ni conservar ninguna solicitud pendiente, así nunca se muestra el
  // borrador de otro contexto. Volver al mismo contexto tampoco lo recupera.
  if (estado.borrador.contexto !== contexto) {
    setEstado(estadoBorradorVacio(contexto));
  }
  const actual = estadoDeContexto(estado, contexto);

  // Contexto vigente para las acciones ya entregadas. Se actualiza al confirmar
  // el render (antes de cualquier evento): un callback de un render anterior lo
  // compara con el suyo y, si difiere, no opera.
  const [vigencia] = useState(() => crearVigencia(contexto));
  useLayoutEffect(() => {
    vigencia.fijar(contexto);
  }, [vigencia, contexto]);

  useAvisoSalidaPagina(borradorSinGuardar(actual.borrador));

  const valor = useMemo<ContextoBorradorCarga>(
    () => ({
      borrador: actual.borrador,
      pendiente: actual.pendiente,
      // Toda escritura se aplica sólo si el estado más reciente sigue siendo
      // del mismo contexto: una acción tardía no puede revivir ni tocar nada.
      ...crearAccionesBorrador(
        actual,
        (f) => setEstado((previo) => (previo.borrador.contexto === contexto ? f(previo) : previo)),
        () => vigencia.es(contexto)
      ),
    }),
    [actual, contexto, vigencia]
  );

  return <BorradorCargaContexto.Provider value={valor}>{children}</BorradorCargaContexto.Provider>;
}
