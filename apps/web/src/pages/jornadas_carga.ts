// Controlador de «Cargar camión» (FE-1), sin React. PARCHE AISLADO: no se monta
// en ninguna pantalla mientras DP-1 y la decisión sobre E5/E6 sigan abiertas.
//
// Usa sólo `ejecutar` de la capa B-02a con el comando `cargar` (RPC
// `registrar_carga`) sobre el motor común `jornadas_operacion.ts` (clave por
// intención, envío único, verificación ante respuesta perdida, reintento con la
// misma clave y el mismo comando congelado, intención incierta conservada,
// arbitraje con las otras operaciones sobre la misma jornada).
//
// Contrato de la RPC (migración 20261106120000; ADR-007 §2.5 y §2.7):
// - Sólo dueño y encargado activos (PT403 jornada_no_autorizado si no).
// - Estados admitidos: abierta y cargada. La primera carga lleva abierta →
//   cargada en la MISMA transacción que los movimientos; las siguientes no
//   cambian el estado (cargas incrementales).
// - Productos activos de la empresa, sin repetidos; cantidades enteras > 0 en
//   unidad mínima (unidades o gramos; ADR-005). El camión es el de la jornada:
//   no se elige ni se envía.
// - Idempotente por (empresa, actor, clave) con huella del payload. El replay
//   (paso 5) y la segunda consulta tras el FOR UPDATE (paso 8a) ocurren ANTES
//   de las validaciones de negocio: reenviar la MISMA clave con el MISMO
//   payload devuelve la operación original si se registró y, si no, revalida
//   todo y la aplica una sola vez.
// La validación local es igual o más laxa que la del servidor, que decide.
//
// Respuesta perdida (modelo M-01): leer la jornada NUNCA prueba que ESTA carga
// se registró (ver `cargada` puede deberse a otra carga). Por eso la
// verificación jamás declara éxito; sólo decide si reenviar la MISMA intención
// es seguro. Sólo la respuesta del servidor a ese reenvío resuelve la intención.
//
// LÍMITE CONOCIDO (DP-1, abierto): la clave sólo vive en memoria. Si la
// intención se pierde (recarga E4, navegación interna E5, sesión E6, otra
// pestaña E7), una nueva carga lleva otra clave y el servidor la registra como
// una carga distinta: doble movimiento. Este módulo NO lo resuelve.

import {
  cantidadDesdeTexto,
  esUuid,
  type EstadoJornada,
  type Jornada,
  type LineaJornada,
} from "../lib/jornadas";
import type { ProductoCatalogo } from "../lib/productos";
import { formatearCantidadHistorial } from "./jornadas_historial";
import {
  OPERACION_INACTIVA,
  crearControladorOperacion,
  type ArbitroJornadas,
  type DefinicionOperacion,
  type FaseOperacion,
  type PuertoOperacion,
  type Verificacion,
} from "./jornadas_operacion";
import type { VerificarJornada } from "./jornadas_salida";

export type FaseCarga = FaseOperacion;
export const CARGA_INACTIVA: FaseCarga = OPERACION_INACTIVA;

/** Estados en los que `registrar_carga` admite cargar (ADR-007 §2.5). */
export const ESTADOS_CARGABLES: readonly EstadoJornada[] = Object.freeze([
  "abierta",
  "cargada",
] as EstadoJornada[]);

export type ProductoCarga = Pick<
  ProductoCatalogo,
  "id" | "codigo" | "nombre" | "formaVenta" | "activo"
>;

/** Lo que escribe el usuario: un producto elegido y la cantidad como texto. */
export interface LineaEntradaCarga {
  productoId: string;
  texto: string;
}

export interface EntradaCarga {
  lineas: LineaEntradaCarga[];
}

export interface DatosCarga {
  jornadaId: string;
  // Fecha de la jornada: la lectura de verificación la busca en ese día.
  fecha: string;
  // Estado al confirmar: permite saber, tras una respuesta perdida, si la
  // primera carga pudo no haber tenido efecto todavía.
  estadoInicial: EstadoJornada;
  lineas: readonly LineaJornada[];
}

export interface LineaResumenCarga {
  productoId: string;
  producto: string;
  cantidad: string;
}

export const MENSAJE_CARGA_OK = "Carga registrada. La jornada se actualizó.";
export const MENSAJE_CARGA_SIN_JORNADA = "Elegí una jornada abierta o cargada.";
export const MENSAJE_CARGA_SIN_CAMION = "La jornada no tiene un camión válido.";
export const MENSAJE_CARGA_SIN_LINEAS = "Agregá al menos un producto.";
export const MENSAJE_CARGA_SIN_PRODUCTO = (n: number) => `Línea ${n}: elegí un producto.`;
export const MENSAJE_CARGA_PRODUCTO_DESCONOCIDO = (n: number) =>
  `Línea ${n}: el producto no está en el catálogo.`;
export const MENSAJE_CARGA_PRODUCTO_INACTIVO = (n: number) =>
  `Línea ${n}: el producto está dado de baja.`;
export const MENSAJE_CARGA_PRODUCTO_REPETIDO = (n: number) =>
  `Línea ${n}: el producto ya está en otra línea. Sumá las cantidades en una sola.`;
export const MENSAJE_CARGA_CANTIDAD_UNIDAD = (n: number) =>
  `Línea ${n}: ingresá una cantidad entera mayor que cero.`;
export const MENSAJE_CARGA_CANTIDAD_PESO = (n: number) =>
  `Línea ${n}: ingresá el peso en kg, mayor que cero y con hasta 3 decimales (por ejemplo 1,250).`;

export const MENSAJE_CARGA_SIN_EFECTO =
  "No se pudo confirmar si la carga se registró y la jornada sigue sin cargas. Podés reintentar desde esta pantalla: se reenvía la misma carga y no se registra dos veces.";
export const MENSAJE_CARGA_INCIERTA =
  "No se pudo confirmar si esta carga se registró: la jornada tiene cargas, pero pueden ser de otra operación. Reintentá desde esta pantalla, sin recargarla ni cambiar de sección: se reenvía la misma carga; si ya se registró no se repite.";
export const MENSAJE_CARGA_NO_VISIBLE =
  "No se pudo confirmar si la carga se registró y la jornada ya no aparece. Reintentá desde esta pantalla: si ya se registró no se repite y, si no, el servidor decide.";
export const MENSAJE_CARGA_SIN_VERIFICAR =
  "No se pudo confirmar si la carga se registró ni leer la jornada. No recargues ni cambies de sección: verificá el estado antes de reintentar.";

// Unidades: sólo dígitos. `cantidad_unidad_desde_texto` (domain/cantidades.ts)
// usa Number() y acepta «1e3», «0x10» o «+5»; el parser de peso ya los rechaza.
// No se cambia el dominio compartido desde FE-1: se filtra el formato aquí.
const FORMATO_UNIDAD = /^\d+$/;

// Rechazos definitivos que indican que la jornada cambió en la base.
const CODIGOS_RELEER: ReadonlySet<string> = new Set([
  "jornada_estado_invalido",
  "jornada_no_encontrada",
  "jornada_camion_inactivo",
]);

export function jornadaCargable(jornada: Pick<Jornada, "estado">): boolean {
  return ESTADOS_CARGABLES.includes(jornada.estado);
}

/** Jornadas que la pantalla ofrece para cargar (sólo presentación). */
export function jornadasCargables<J extends Pick<Jornada, "estado">>(jornadas: readonly J[]): J[] {
  return jornadas.filter(jornadaCargable);
}

export type ValidacionCarga =
  | { ok: true; lineas: readonly LineaJornada[] }
  | { ok: false; mensaje: string };

/**
 * Validación local de las líneas contra el catálogo; nunca usa punto flotante
 * (las cantidades pasan por `cantidadDesdeTexto`). Devuelve el PRIMER error.
 */
export function validarCarga(
  entrada: EntradaCarga,
  catalogo: readonly ProductoCarga[]
): ValidacionCarga {
  if (entrada.lineas.length === 0) return { ok: false, mensaje: MENSAJE_CARGA_SIN_LINEAS };
  const porId = new Map(catalogo.map((p) => [p.id.toLowerCase(), p]));
  const vistos = new Set<string>();
  const lineas: LineaJornada[] = [];

  for (const [i, linea] of entrada.lineas.entries()) {
    const n = i + 1;
    const id = linea.productoId.trim();
    if (id === "") return { ok: false, mensaje: MENSAJE_CARGA_SIN_PRODUCTO(n) };
    const producto = esUuid(id) ? porId.get(id.toLowerCase()) : undefined;
    if (producto === undefined) return { ok: false, mensaje: MENSAJE_CARGA_PRODUCTO_DESCONOCIDO(n) };
    if (!producto.activo) return { ok: false, mensaje: MENSAJE_CARGA_PRODUCTO_INACTIVO(n) };
    if (vistos.has(id.toLowerCase())) {
      return { ok: false, mensaje: MENSAJE_CARGA_PRODUCTO_REPETIDO(n) };
    }
    vistos.add(id.toLowerCase());
    const formatoOk = producto.formaVenta === "peso" || FORMATO_UNIDAD.test(linea.texto.trim());
    const cantidad = formatoOk ? cantidadDesdeTexto(producto.formaVenta, linea.texto) : null;
    if (cantidad === null) {
      return {
        ok: false,
        mensaje:
          producto.formaVenta === "peso"
            ? MENSAJE_CARGA_CANTIDAD_PESO(n)
            : MENSAJE_CARGA_CANTIDAD_UNIDAD(n),
      };
    }
    lineas.push(Object.freeze({ productoId: producto.id, cantidad }));
  }
  return { ok: true, lineas: Object.freeze(lineas) };
}

/** Resumen legible de lo que se va a cargar, para el paso de confirmación. */
export function resumenCarga(
  lineas: readonly LineaJornada[],
  catalogo: readonly ProductoCarga[]
): LineaResumenCarga[] {
  const porId = new Map(catalogo.map((p) => [p.id.toLowerCase(), p]));
  return lineas.map((l) => {
    const p = porId.get(l.productoId.toLowerCase());
    if (p === undefined) {
      // validarCarga ya lo impide; si el catálogo cambió, falla cerrado.
      throw new Error("resumenCarga: producto fuera del catálogo");
    }
    const nombre = p.codigo !== null && p.codigo.trim() !== "" ? `${p.nombre} (${p.codigo})` : p.nombre;
    return {
      productoId: p.id,
      producto: nombre,
      cantidad: formatearCantidadHistorial(l.cantidad, p.formaVenta),
    };
  });
}

export function definicionCarga(
  catalogo: () => readonly ProductoCarga[],
  verificarJornada: VerificarJornada
): DefinicionOperacion<EntradaCarga, DatosCarga> {
  return {
    admite: jornadaCargable,
    preparar(jornada, entrada) {
      if (!esUuid(jornada.id) || !jornadaCargable(jornada)) {
        return { ok: false, mensaje: MENSAJE_CARGA_SIN_JORNADA };
      }
      if (!esUuid(jornada.camionId)) return { ok: false, mensaje: MENSAJE_CARGA_SIN_CAMION };
      const v = validarCarga(entrada, catalogo());
      if (!v.ok) return { ok: false, mensaje: v.mensaje };
      return {
        ok: true,
        datos: Object.freeze({ jornadaId: jornada.id, fecha: jornada.fecha, estadoInicial: jornada.estado, lineas: v.lineas }),
      };
    },
    comando: (d) => ({ tipo: "cargar", jornadaId: d.jornadaId, lineas: [...d.lineas] }),
    mensajeExito: MENSAJE_CARGA_OK,
    async verificar(d): Promise<Verificacion> {
      const estado = await verificarJornada({ id: d.jornadaId, fecha: d.fecha });
      if (estado === undefined) {
        return { resultado: "sin_verificar", mensaje: MENSAJE_CARGA_SIN_VERIFICAR };
      }
      if (estado === null) {
        // Replay (paso 5) precede a la búsqueda de la jornada: reenviar es seguro.
        return { resultado: "incierta", mensaje: MENSAJE_CARGA_NO_VISIBLE, reintentable: true };
      }
      // Primera carga: abierta → cargada va en la MISMA transacción que los
      // movimientos. Si sigue abierta, ESTA carga no tuvo efecto todavía (la
      // primera solicitud podría seguir en curso: el reenvío con la misma clave
      // espera el FOR UPDATE y ve su resultado en el paso 8a).
      if (d.estadoInicial === "abierta" && estado === "abierta") {
        return { resultado: "sin_efecto", mensaje: MENSAJE_CARGA_SIN_EFECTO };
      }
      // `cargada` (u otro estado) no prueba nada sobre ESTA carga. Reenviar la
      // misma intención es seguro: replay si se registró; si no, el servidor
      // revalida y la aplica una sola vez o la rechaza sin efecto.
      return { resultado: "incierta", mensaje: MENSAJE_CARGA_INCIERTA, reintentable: true };
    },
    releerTrasRechazo: (codigo) => codigo !== null && CODIGOS_RELEER.has(codigo),
  };
}

export function crearControladorCarga(
  puerto: PuertoOperacion,
  catalogo: () => readonly ProductoCarga[],
  verificarJornada: VerificarJornada,
  alCambiarJornada: () => void,
  publicar: (fase: FaseCarga) => void,
  opciones: { generarClave?: () => string; arbitro?: ArbitroJornadas } = {}
) {
  return crearControladorOperacion(
    definicionCarga(catalogo, verificarJornada),
    puerto,
    alCambiarJornada,
    publicar,
    opciones.generarClave,
    opciones.arbitro
  );
}

export type ControladorCarga = ReturnType<typeof crearControladorCarga>;
