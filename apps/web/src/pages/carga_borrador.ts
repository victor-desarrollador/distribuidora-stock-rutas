// Borrador de «Cargar mercadería» (FE-1D), puro y sin React.
//
// SÓLO PREPARACIÓN: describe qué jornada tiene un borrador abierto y lo escrito
// en él. No tiene confirmación, no genera claves, no conoce ningún puerto de
// ejecución y no guarda nada en el navegador (ni localStorage, ni
// sessionStorage, ni IndexedDB). La carga real sigue deshabilitada mientras
// DP-1 esté abierto: este módulo NO es el controlador FE-1 (`jornadas_carga.ts`)
// y nunca lo construye.
//
// El borrador pertenece a UN contexto de autorización (FE-1F, H-01): usuario,
// empresa y rol efectivos del perfil protegido. Si cualquiera cambia, o la
// autorización deja de estar verificada, se descarta y no se conserva.

import { ROLES_GESTION } from "../auth/roles";
import type { EstadoSesion } from "../auth/sesion";
import { EDICION_INICIAL, type EdicionCarga } from "./carga_edicion";
import { CARGA_INACTIVA, jornadaCargable, type FaseCarga } from "./jornadas_carga";
import type { Jornada } from "../lib/jornadas";

/**
 * Identidad de autorización para preparar una carga (FE-1F, H-01), derivada
 * SÓLO de la sesión que publica `AuthContext` (perfil y empresa leídos de las
 * tablas protegidas; nunca de user_metadata). Falla cerrado: devuelve null si
 * la sesión no está `autenticado`, si el perfil o la empresa no están activos o
 * no coinciden, o si el rol no es de gestión. Mientras CV-1 revalida al mismo
 * usuario conserva el estado anterior, y al publicar el resultado esta clave
 * cambia si cambió la empresa o el rol.
 */
export function contextoAutorizacionCarga(sesion: EstadoSesion): string | null {
  if (sesion.estado !== "autenticado") return null;
  const { perfil, empresa } = sesion;
  if (!perfil.activo || !empresa.activo || empresa.id !== perfil.empresaId) return null;
  if (!ROLES_GESTION.includes(perfil.rol)) return null;
  return JSON.stringify([perfil.usuarioId, perfil.empresaId, perfil.rol]);
}

export interface BorradorCarga {
  // Contexto de autorización dueño del borrador (null: sin autorización
  // verificada para preparar cargas). Ver `contextoAutorizacionCarga`.
  contexto: string | null;
  // Jornada con el formulario abierto, o null si no hay borrador.
  jornadaId: string | null;
  edicion: EdicionCarga;
}

export function borradorVacio(contexto: string | null): BorradorCarga {
  return Object.freeze({ contexto, jornadaId: null, edicion: EDICION_INICIAL });
}

/** El borrador vigente para `contexto`: si es de otro contexto, uno vacío. */
export function borradorDeContexto(b: BorradorCarga, contexto: string | null): BorradorCarga {
  return b.contexto === contexto ? b : borradorVacio(contexto);
}

/**
 * Abre el formulario de una jornada. Si ya había un borrador de ESA jornada se
 * conserva lo escrito; si era de otra, empieza vacío (un borrador por vez).
 */
export function iniciarBorrador(b: BorradorCarga, jornadaId: string): BorradorCarga {
  if (b.contexto === null) return b; // sin autorización no se prepara nada
  if (b.jornadaId === jornadaId) return b;
  return Object.freeze({ contexto: b.contexto, jornadaId, edicion: EDICION_INICIAL });
}

/** Reemplaza lo escrito; sin un borrador abierto no hace nada. */
export function editarBorrador(b: BorradorCarga, edicion: EdicionCarga): BorradorCarga {
  if (b.jornadaId === null) return b;
  return Object.freeze({ ...b, edicion });
}

export function descartarBorrador(b: BorradorCarga): BorradorCarga {
  return borradorVacio(b.contexto);
}

/** true si hay algo escrito que se perdería al recargar o cerrar la página. */
export function borradorSinGuardar(b: BorradorCarga): boolean {
  return (
    b.jornadaId !== null &&
    b.edicion.lineas.some((l) => l.productoId.trim() !== "" || l.texto.trim() !== "")
  );
}

/**
 * Fase que ve el panel de UNA jornada: «confirmando» (formulario abierto) sólo
 * si el borrador es de esa jornada y sigue siendo cargable. Nunca produce
 * «enviando», «verificando», «desconocido» ni «exito»: no hay envío.
 */
export function faseBorradorPara(
  b: BorradorCarga,
  jornada: Pick<Jornada, "id" | "estado">
): FaseCarga {
  if (b.contexto === null || b.jornadaId !== jornada.id || !jornadaCargable(jornada)) {
    return CARGA_INACTIVA;
  }
  return { fase: "confirmando", jornadaId: jornada.id };
}

// ---------------------------------------------------------------------------
// FE-1E: protección del borrador ante acciones VOLUNTARIAS que lo descartarían
// (abrir la carga de otra jornada, cerrar sesión o, desde FE-1F, «Cancelar» en
// el formulario). Si hay algo escrito, la acción queda PENDIENTE hasta que la
// persona acepte descartar o cancele. Sin nada escrito, la acción procede como
// antes. El cambio real del contexto de autorización NO pasa por aquí:
// `estadoDeContexto` lo descarta siempre, sin preguntar y sin conservar ninguna
// solicitud pendiente.

export type SolicitudDescarte = Readonly<
  | { tipo: "cambiar_jornada"; jornadaId: string }
  | { tipo: "cerrar_sesion" }
  | { tipo: "cancelar_carga" }
>;

export interface EstadoBorrador {
  borrador: BorradorCarga;
  // Acción voluntaria que espera la decisión de la persona, o null.
  pendiente: SolicitudDescarte | null;
}

export function estadoBorradorVacio(contexto: string | null): EstadoBorrador {
  return Object.freeze({ borrador: borradorVacio(contexto), pendiente: null });
}

/** Estado vigente para `contexto`: si es de otro contexto, vacío y sin pendiente. */
export function estadoDeContexto(e: EstadoBorrador, contexto: string | null): EstadoBorrador {
  return e.borrador.contexto === contexto ? e : estadoBorradorVacio(contexto);
}

/** true si la acción descartaría algo escrito y debe confirmarse antes. */
export function requiereConfirmarDescarte(b: BorradorCarga, s: SolicitudDescarte): boolean {
  if (!borradorSinGuardar(b)) return false;
  // Reabrir la MISMA jornada conserva lo escrito: no se pierde nada.
  return s.tipo !== "cambiar_jornada" || b.jornadaId !== s.jornadaId;
}

function aplicarSolicitud(b: BorradorCarga, s: SolicitudDescarte): BorradorCarga {
  // `iniciarBorrador` conserva la misma jornada y empieza vacío para otra.
  return s.tipo === "cambiar_jornada" ? iniciarBorrador(b, s.jornadaId) : descartarBorrador(b);
}

/**
 * Pide una acción. `procede`: la acción ya se aplicó al borrador y quien la
 * pidió puede continuar (p. ej. cerrar sesión). Si no procede, queda pendiente.
 */
export function solicitarDescarte(
  e: EstadoBorrador,
  s: SolicitudDescarte
): { estado: EstadoBorrador; procede: boolean } {
  if (requiereConfirmarDescarte(e.borrador, s)) {
    return { estado: Object.freeze({ borrador: e.borrador, pendiente: s }), procede: false };
  }
  return {
    estado: Object.freeze({ borrador: aplicarSolicitud(e.borrador, s), pendiente: null }),
    procede: true,
  };
}

/** La persona acepta descartar: se aplica la acción pendiente (si la hay). */
export function aceptarDescarte(e: EstadoBorrador): {
  estado: EstadoBorrador;
  aceptada: SolicitudDescarte | null;
} {
  if (e.pendiente === null) return { estado: e, aceptada: null };
  return {
    estado: Object.freeze({ borrador: aplicarSolicitud(e.borrador, e.pendiente), pendiente: null }),
    aceptada: e.pendiente,
  };
}

/** La persona cancela: el borrador queda intacto y no se hace la acción. */
export function cancelarDescarte(e: EstadoBorrador): EstadoBorrador {
  return e.pendiente === null ? e : Object.freeze({ borrador: e.borrador, pendiente: null });
}

/** Acciones que ofrece el contexto (sin ninguna de confirmar carga ni enviar). */
export interface AccionesBorrador {
  /** Abre la carga de una jornada; false si quedó pendiente o no hay autorización. */
  iniciar(jornadaId: string): boolean;
  editar(edicion: EdicionCarga): void;
  descartar(): void;
  /**
   * «Cancelar» del formulario (FE-1F, H-02): true si se cerró ya (no había
   * nada escrito); false si quedó pendiente de confirmar el descarte.
   */
  pedirCancelacion(): boolean;
  /** true si se puede cerrar sesión ya; false si quedó pendiente de confirmar. */
  pedirCierreSesion(): boolean;
  /** Aplica la acción pendiente y la devuelve para que quien llamó continúe. */
  aceptarDescarte(): SolicitudDescarte | null;
  cancelarDescarte(): void;
}

/**
 * Acciones sobre el estado `actual` (el del contexto vigente al crearlas). Las
 * escrituras van por `fijar(f)`, que recibe una transformación pura: el
 * provider la aplica sólo si el estado más reciente sigue siendo del MISMO
 * contexto. Los valores devueltos se calculan sobre `actual`.
 *
 * FE-1F (H-01): `esVigente()` dice si el contexto con que se crearon sigue
 * siendo el vigente. Si no lo es (acción tardía tras cambiar usuario, empresa o
 * rol, o tras perder la autorización), la acción NO escribe nada y devuelve el
 * valor que impide continuar (`false` / `null`): ningún diálogo ni callback
 * antiguo puede descartar, abrir ni cerrar sesión sobre el contexto nuevo.
 */
export function crearAccionesBorrador(
  actual: EstadoBorrador,
  fijar: (f: (e: EstadoBorrador) => EstadoBorrador) => void,
  esVigente: () => boolean
): AccionesBorrador {
  const conBorrador = (f: (b: BorradorCarga) => BorradorCarga) =>
    fijar((e) => Object.freeze({ borrador: f(e.borrador), pendiente: e.pendiente }));
  const solicitar = (s: SolicitudDescarte): boolean => {
    if (!esVigente()) return false;
    fijar((e) => solicitarDescarte(e, s).estado);
    return solicitarDescarte(actual, s).procede;
  };
  return {
    iniciar(jornadaId) {
      // Sin autorización verificada no se abre nada (falla cerrado).
      if (actual.borrador.contexto === null) return false;
      return solicitar({ tipo: "cambiar_jornada", jornadaId });
    },
    editar(edicion) {
      if (esVigente()) conBorrador((b) => editarBorrador(b, edicion));
    },
    descartar() {
      if (esVigente()) fijar((e) => estadoBorradorVacio(e.borrador.contexto));
    },
    pedirCancelacion: () => solicitar({ tipo: "cancelar_carga" }),
    pedirCierreSesion: () => solicitar({ tipo: "cerrar_sesion" }),
    aceptarDescarte() {
      if (!esVigente()) return null;
      fijar((e) => aceptarDescarte(e).estado);
      return aceptarDescarte(actual).aceptada;
    },
    cancelarDescarte() {
      if (esVigente()) fijar(cancelarDescarte);
    },
  };
}
