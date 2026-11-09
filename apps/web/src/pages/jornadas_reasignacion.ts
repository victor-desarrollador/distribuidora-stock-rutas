// Controlador de «Cambiar vendedor» (FE-2B, reasignación), sin React.
//
// Usa sólo `ejecutar` de la capa B-02a con el comando `reasignar` (RPC
// `reasignar_vendedor`, migración 20261101120000) sobre el motor común
// `jornadas_operacion.ts`: clave por intención, envío único, comando congelado,
// verificación ante respuesta perdida, reintento sólo con la misma clave,
// intención incierta conservada y árbitro compartido con salida y corrección.
//
// Contrato de la RPC (ADR-007 §2.3; ADR-001 §18.4):
// - Sólo dueño y encargado activos (`jornada_no_autorizado` en otro caso).
// - Sólo jornadas `abierta` o `cargada` (`jornada_estado_invalido`).
// - Vendedor nuevo: perfil activo de la empresa con rol dueno, encargado o
//   vendedor_piloto (`jornada_vendedor_no_encontrado` / `_invalido`), libre en
//   la fecha (`jornada_vendedor_ocupado`) y distinto del vigente
//   (`jornada_sin_cambios`). Sin motivo.
// - Idempotente por (empresa, actor, clave) con huella: el replay (paso 5)
//   ocurre ANTES de revalidar estado y negocio, así que reenviar la MISMA clave
//   con el MISMO payload devuelve la operación original si se registró y, si
//   no, revalida todo desde cero.
//
// Lista de candidatos: `listar_vendedores_jornada` (E-PL1, ADR-001 §18.4.2.2,
// alcance «jornadas (ADR-007 §2.3)»). Un uuid que no vino de esa lista se
// rechaza localmente: no hay uuid manual. El servidor decide siempre.
//
// Respuesta perdida: leer la jornada NUNCA prueba que ESTE cambio se registró
// (otra persona pudo elegir el mismo vendedor). La verificación no declara
// éxito: sólo decide si reenviar la MISMA intención es seguro. Sólo la
// respuesta del servidor a ese reenvío (uuid de la operación o un rechazo
// definitivo) resuelve la intención. No hay reintentos automáticos.

import { nombreRol } from "../auth/roles";
import { esUuid, type EstadoJornada, type Jornada } from "../lib/jornadas";
import type { EstadoVendedores } from "./jornadas_apertura";
import type { BuscarJornada } from "./jornadas_correccion";
import { idCorto } from "./jornadas_presentacion";
import {
  OPERACION_INACTIVA,
  crearControladorOperacion,
  type ArbitroJornadas,
  type DefinicionOperacion,
  type FaseOperacion,
  type PuertoOperacion,
  type Verificacion,
} from "./jornadas_operacion";

export type FaseReasignacion = FaseOperacion;
export const REASIGNACION_INACTIVA: FaseReasignacion = OPERACION_INACTIVA;

/** Estados en los que la reasignación está permitida (ADR-007 §2.3.3). */
export const ESTADOS_REASIGNABLES: readonly EstadoJornada[] = ["abierta", "cargada"];

export interface EntradaReasignacion {
  vendedorId: string;
  // Usuarios ofrecidos por `listar_vendedores_jornada` en esta apertura del
  // formulario. Sólo se acepta un vendedor de esta lista.
  permitidos: readonly string[];
}

export interface DatosReasignacion {
  jornadaId: string;
  // Fecha de la jornada al confirmar: la reasignación no la cambia.
  fecha: string;
  // Vendedor vigente al confirmar: permite saber si el cambio tuvo efecto.
  original: string;
  vendedorId: string;
}

export const MENSAJE_REASIGNACION_OK = "Vendedor cambiado. La jornada se actualizó.";
export const MENSAJE_REASIGNACION_SIN_EFECTO =
  "No se pudo confirmar si el cambio de vendedor se registró y la jornada sigue con el vendedor anterior. Podés reintentar: se reenvía el mismo cambio y no se registra dos veces.";
export const MENSAJE_REASIGNACION_SIN_VERIFICAR =
  "No se pudo confirmar si el cambio de vendedor se registró ni leer la jornada. Verificá el estado antes de reintentar.";
export const MENSAJE_REASIGNACION_COINCIDE =
  "La jornada ya tiene el vendedor elegido, pero no se puede asegurar que sea por este cambio (pudo hacerlo otra persona). Reintentá para confirmarlo: se reenvía el mismo cambio; si ya se registró no se repite y, si no, se rechaza sin cambios.";
export const MENSAJE_REASIGNACION_OTRO_ESTADO =
  "No se pudo confirmar si el cambio de vendedor se registró y la jornada ya no admite cambios de vendedor. Reintentá para confirmarlo: se reenvía el mismo cambio; si ya se registró no se repite y, si no, se rechaza sin cambios.";
export const MENSAJE_REASIGNACION_OTRO_VENDEDOR =
  "No se pudo confirmar si el cambio de vendedor se registró y la jornada tiene otro vendedor (pudo cambiarlo otra persona). No se ofrece reintentar para no pisar ese cambio: verificá el estado o revisá la jornada.";
export const MENSAJE_REASIGNACION_NO_VISIBLE =
  "No se pudo confirmar si el cambio de vendedor se registró y la jornada no aparece en su fecha. Verificá el estado o revisá la lista.";

export const MENSAJE_VENDEDOR_NO_OFRECIDO = "Elegí un vendedor de la lista.";
export const MENSAJE_MISMO_VENDEDOR = "Elegí un vendedor distinto del actual.";

// Rechazos definitivos que indican que la jornada o los vendedores cambiaron
// en la base: se relee la lista de jornadas. `jornada_sin_cambios` sólo puede
// llegar si la jornada cambió después de leerla (la validación local impide
// elegir al vendedor vigente).
const CODIGOS_RELEER: ReadonlySet<string> = new Set([
  "jornada_estado_invalido",
  "jornada_no_encontrada",
  "jornada_sin_cambios",
  "jornada_vendedor_ocupado",
  "jornada_vendedor_no_encontrado",
  "jornada_vendedor_invalido",
]);

const mismo = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();

/** «Nombre (Rol)» si la lista de vendedores lo trae; si no, un id corto (nunca un dato inventado). */
export function etiquetaVendedor(vendedores: EstadoVendedores, id: string): string {
  if (vendedores.estado === "listo") {
    const v = vendedores.vendedores.find((x) => x.usuarioId === id.toLowerCase());
    if (v) return `${v.nombre} (${nombreRol(v.rol)})`;
  }
  return `Vendedor ${idCorto(id)}`;
}

export function admiteReasignacion(jornada: Pick<Jornada, "estado">): boolean {
  return ESTADOS_REASIGNABLES.includes(jornada.estado);
}

/** Validación local de la entrada; `null` si se puede enviar. */
export function validarReasignacion(
  jornada: Pick<Jornada, "vendedorId">,
  entrada: EntradaReasignacion
): string | null {
  if (
    !esUuid(entrada.vendedorId) ||
    !entrada.permitidos.some((p) => mismo(p, entrada.vendedorId))
  ) {
    return MENSAJE_VENDEDOR_NO_OFRECIDO;
  }
  if (mismo(entrada.vendedorId, jornada.vendedorId)) return MENSAJE_MISMO_VENDEDOR;
  return null;
}

export function definicionReasignacion(
  buscar: BuscarJornada
): DefinicionOperacion<EntradaReasignacion, DatosReasignacion> {
  return {
    admite: admiteReasignacion,
    preparar(jornada, entrada) {
      const error = validarReasignacion(jornada, entrada);
      if (error !== null) return { ok: false, mensaje: error };
      return {
        ok: true,
        datos: Object.freeze({
          jornadaId: jornada.id,
          fecha: jornada.fecha,
          original: jornada.vendedorId.toLowerCase(),
          vendedorId: entrada.vendedorId.toLowerCase(),
        }),
      };
    },
    comando: (d) => ({ tipo: "reasignar", jornadaId: d.jornadaId, vendedorId: d.vendedorId }),
    mensajeExito: MENSAJE_REASIGNACION_OK,
    async verificar(d): Promise<Verificacion> {
      let j: Jornada | null | undefined;
      try {
        j = await buscar(d.jornadaId, [d.fecha]);
      } catch {
        j = undefined;
      }
      if (j === undefined) {
        return { resultado: "sin_verificar", mensaje: MENSAJE_REASIGNACION_SIN_VERIFICAR };
      }
      if (j === null) {
        // Pudo cambiar de fecha por una corrección: no se sabe nada.
        return { resultado: "incierta", mensaje: MENSAJE_REASIGNACION_NO_VISIBLE, reintentable: false };
      }
      // Coincidir con lo pedido NO prueba que se haya registrado ESTE cambio.
      // Reenviar es seguro: si fue éste, el replay devuelve la operación
      // original; si no, el servidor responde `jornada_sin_cambios` (o
      // `jornada_estado_invalido`) y no cambia nada.
      if (mismo(j.vendedorId, d.vendedorId)) {
        return { resultado: "incierta", mensaje: MENSAJE_REASIGNACION_COINCIDE, reintentable: true };
      }
      if (mismo(j.vendedorId, d.original)) {
        // La RPC escribe operación, historial y jornada en UNA transacción: con
        // el vendedor original y un estado que admite el cambio, éste no tuvo
        // efecto TODAVÍA (el reenvío con la misma clave espera esa reserva).
        if (admiteReasignacion(j)) {
          return { resultado: "sin_efecto", mensaje: MENSAJE_REASIGNACION_SIN_EFECTO };
        }
        // Ya no admite: el reenvío sólo confirma (replay) o rechaza sin efecto.
        return { resultado: "incierta", mensaje: MENSAJE_REASIGNACION_OTRO_ESTADO, reintentable: true };
      }
      // Un tercer vendedor: reenviar podría pisar el cambio de otra persona.
      return { resultado: "incierta", mensaje: MENSAJE_REASIGNACION_OTRO_VENDEDOR, reintentable: false };
    },
    releerTrasRechazo: (codigo) => codigo !== null && CODIGOS_RELEER.has(codigo),
  };
}

export function crearControladorReasignacion(
  puerto: PuertoOperacion,
  buscar: BuscarJornada,
  alCambiarJornada: () => void,
  publicar: (fase: FaseReasignacion) => void,
  opciones: { generarClave?: () => string; arbitro?: ArbitroJornadas } = {}
) {
  return crearControladorOperacion(
    definicionReasignacion(buscar),
    puerto,
    alCambiarJornada,
    publicar,
    opciones.generarClave,
    opciones.arbitro
  );
}

export type ControladorReasignacion = ReturnType<typeof crearControladorReasignacion>;

/**
 * Participación revocable en el árbitro de la pantalla. Cuando cambia el
 * contexto de autorización (usuario, empresa o rol) la intención del contexto
 * anterior se descarta: su retención se libera y sus actualizaciones tardías
 * se ignoran. `reactivar` (remontaje del mismo contexto) vuelve a aplicar la
 * última retención conocida.
 */
export function arbitroRevocable(base: ArbitroJornadas) {
  let vigente = true;
  const ultimas = new Map<symbol, string | null>();
  const arbitro: ArbitroJornadas = {
    retenidaPorOtra: (participante, jornadaId) => base.retenidaPorOtra(participante, jornadaId),
    actualizar(participante, jornadaId) {
      ultimas.set(participante, jornadaId);
      if (vigente) base.actualizar(participante, jornadaId);
    },
  };
  return {
    arbitro,
    revocar() {
      vigente = false;
      for (const participante of ultimas.keys()) base.actualizar(participante, null);
    },
    reactivar() {
      vigente = true;
      for (const [participante, jornadaId] of ultimas) base.actualizar(participante, jornadaId);
    },
  };
}
