// Jornadas reales en Supabase (B-02a): capa de datos tipada, sin pantalla.
// Blueprint §7.5 (jornada, carga, descarga, salida), §7.1 y ADR-005 (unidad
// mínima: unidades o gramos enteros), §3/§6 (stock sólo por RPC); ADR-007;
// ADR-001 §18.4 (contrato de las seis RPC) y E-SL1 §18.4.16.
//
// Escritura: sólo por las RPC aprobadas (fachadas SECURITY INVOKER →
// implementaciones privadas SECURITY DEFINER). Todas reciben una clave de
// idempotencia y devuelven un uuid (supabase/migrations/20261031…–20261109…):
//   - abrir_jornada(p_idempotency_key, p_camion_id, p_fecha, p_vendedor_id)
//       → id de la JORNADA
//   - reasignar_vendedor(p_idempotency_key, p_jornada_id, p_vendedor_id)
//   - corregir_jornada(p_idempotency_key, p_jornada_id, p_fecha, p_camion_id, p_motivo)
//   - registrar_carga(p_idempotency_key, p_jornada_id, p_productos uuid[], p_cantidades int4[])
//   - registrar_descarga(p_idempotency_key, p_jornada_id, p_productos uuid[], p_cantidades int4[], p_motivo)
//   - confirmar_salida(p_idempotency_key, p_jornada_id)
//       → id de la OPERACIÓN
// `empresa_id` y el actor los deriva el servidor del perfil: nunca se envían.
// Este módulo no escribe tablas: nunca usa insert/update/upsert/delete.
//
// Lectura: SELECT con RLS sobre `jornadas` (ADR-001 §18.4.2: dueño o encargado
// activo de la empresa, o el vendedor asignado de la jornada), SIEMPRE paginada
// por cursor (fecha desc, id desc; orden total porque `id` es la clave primaria).
// PostgREST corta en `max_rows` (1000 en supabase/config.toml) sin avisar, así
// que una lectura sin límite explícito podría truncarse en silencio. Contrato:
//   - `leerPaginaJornadas` devuelve UNA página y `siguiente` (cursor) o null. Una
//     página nunca es "el conjunto": sólo `siguiente === null` indica el final.
//   - `leerTodasLasJornadas` recorre todas las páginas o falla; nunca devuelve
//     un listado parcial.
//   - Se piden TAMANO_PAGINA_JORNADAS + 1 filas (< max_rows) con conteo exacto:
//     la fila extra revela si hay más y el conteo permite detectar que el
//     servidor devolvió menos filas de las pedidas (tope de max_rows menor al
//     esperado). Cualquier inconsistencia falla cerrado.
//   - Sin consistencia transaccional entre solicitudes: cada página es una
//     lectura independiente. Altas posteriores a una página con fecha/id
//     menores al cursor sí aparecen; altas o cambios (reasignar, corregir la
//     fecha) de filas ya recorridas o con claves mayores al cursor no aparecen;
//     una fila cuya fecha se corrige entre páginas puede omitirse o repetirse.
//     `leerTodasLasJornadas` descarta repetidos por id (conserva la primera
//     lectura) pero no puede detectar omisiones. Es una foto aproximada; las
//     garantías de estado las da la RPC, no esta lectura.
//
// Reintentos (P13-stock, aplicado a jornadas por decisión de la tarea): máximo
// 3 intentos en total, con la MISMA clave y el MISMO payload, sólo ante 40001,
// 40P01 o falta de respuesta (error sin código o excepción). Ningún PTxxx se
// reintenta solo; tampoco 42501, 55P03 ni 57014. Sin esperas entre intentos: la
// ADR no las define.
//
// LIMITACIÓN CONOCIDA (no resuelta aquí): la clave de idempotencia vive sólo en
// memoria. Si la respuesta se pierde y el usuario recarga, cierra la pestaña o
// cambia de dispositivo, un nuevo intento usa otra clave y el servidor puede
// ejecutar la operación otra vez. ADR-010 cubre sólo los comandos de stock y no
// está implementada; no se usa localStorage, sessionStorage ni IndexedDB.

import type { SupabaseClient } from "@supabase/supabase-js";

import { cantidad_unidad_desde_texto } from "../domain/cantidades";
import { kg_a_gramos } from "../domain/peso";
import { obtenerClienteSupabase } from "./supabase";

export const ESTADOS_JORNADA = [
  "abierta",
  "cargada",
  "en_reparto",
  "ventas_finalizadas",
  "regreso_contado",
  "cerrada",
] as const;
export type EstadoJornada = (typeof ESTADOS_JORNADA)[number];

export interface Jornada {
  id: string;
  // Fecha operativa 'AAAA-MM-DD' (columna date; zona America/Argentina/Tucuman).
  fecha: string;
  camionId: string;
  vendedorId: string;
  estado: EstadoJornada;
  abiertaPor: string;
  operacionAperturaId: string;
  creadoEn: string;
}

export interface LineaJornada {
  productoId: string;
  // Unidad mínima: unidades enteras o gramos enteros (ADR-005).
  cantidad: number;
}

export type ComandoJornada =
  | { tipo: "abrir"; camionId: string; fecha: string; vendedorId: string }
  | { tipo: "reasignar"; jornadaId: string; vendedorId: string }
  | {
      tipo: "corregir";
      jornadaId: string;
      fecha: string;
      camionId: string;
      motivo: string;
    }
  | { tipo: "cargar"; jornadaId: string; lineas: LineaJornada[] }
  | {
      tipo: "descargar";
      jornadaId: string;
      lineas: LineaJornada[];
      motivo: string;
    }
  | { tipo: "salir"; jornadaId: string };

export interface ErrorJornada {
  // Código estable del servidor (`jornada_*`), SQLSTATE o null si no hubo respuesta.
  codigo: string | null;
  mensaje: string;
  // true: la operación pudo haberse registrado (no hubo respuesta confirmada).
  resultadoDesconocido: boolean;
}

export type ResultadoJornada<T> =
  | { ok: true; datos: T; intentos: number }
  | { ok: false; error: ErrorJornada; intentos: number };

/** Posición en el orden (fecha desc, id desc): la última fila ya leída. */
export interface CursorJornadas {
  fecha: string;
  id: string;
}

export interface PaginaJornadas {
  jornadas: Jornada[];
  // null = no hay más filas (fin comprobado); si no, pasar como `despues`.
  siguiente: CursorJornadas | null;
}

export interface OpcionesLecturaJornadas {
  fecha?: string;
  despues?: CursorJornadas;
}

export interface PuertoJornadas {
  /** UNA página; nunca el conjunto completo salvo que `siguiente` sea null. */
  leerPaginaJornadas(
    opciones?: OpcionesLecturaJornadas
  ): Promise<ResultadoJornada<PaginaJornadas>>;
  /** Todas las páginas o error: jamás un listado parcial. `intentos` = solicitudes. */
  leerTodasLasJornadas(filtro?: {
    fecha?: string;
  }): Promise<ResultadoJornada<Jornada[]>>;
  ejecutar(
    comando: ComandoJornada,
    claveIdempotencia: string,
    opciones?: OpcionesEjecucion
  ): Promise<ResultadoJornada<string>>;
}

/**
 * FE-2D (H-1): condiciones para EMITIR cada intento. No cambian la política de
 * reintentos (códigos, cantidad ni espera): sólo impiden enviar uno nuevo.
 * Un intento ya enviado nunca se cancela ni se da por fallido.
 */
export interface OpcionesEjecucion {
  // Usuario que inició la intención: si la sesión es de otro, no se envía nada.
  usuarioEsperado?: string;
  // false: quien envió se detuvo (desmontaje o cambio de contexto); no se
  // emiten intentos nuevos.
  continuar?: () => boolean;
  // FE-2E (D-2): se invoca UNA vez por llamada, con el usuario fijado, justo
  // antes del primer despacho real (sin espera de por medio). No se invoca si
  // no sale ningún intento. Permite fijar la identidad de la intención lógica.
  alFijarActor?: (usuarioId: string) => void;
}

// Máximo de `int4` (PostgreSQL): tope de cada cantidad.
export const CANTIDAD_MAXIMA = 2147483647;
export const MAX_INTENTOS = 3;
// Debe ser MENOR que `max_rows` de PostgREST (1000): se piden TAMANO + 1 filas.
export const TAMANO_PAGINA_JORNADAS = 500;
// Tope de seguridad de leerTodasLasJornadas (500 × 200 = 100.000 filas): si se
// supera, falla en lugar de devolver un listado parcial.
export const MAX_PAGINAS_JORNADAS = 200;

export const MENSAJE_ERROR_LECTURA =
  "No se pudieron leer las jornadas. Intentá de nuevo.";
export const MENSAJE_ERROR_GENERICO =
  "No se pudo registrar la operación. Intentá de nuevo.";
// Sin respuesta: no se sabe si se registró. Sólo reintentar desde esta misma
// pantalla (misma clave) es seguro; tras recargar no hay garantía.
export const MENSAJE_RESULTADO_DESCONOCIDO =
  "No se pudo confirmar la operación. Reintentá desde esta pantalla, sin recargarla: no se registra dos veces. Si recargaste, revisá la jornada antes de volver a cargarla.";
export const MENSAJE_CONCURRENCIA =
  "Otra operación sobre la misma jornada estaba en curso y ésta no se registró. Intentá de nuevo.";
export const MENSAJE_SIN_PERMISO =
  "No tenés permiso para realizar esta operación.";
export const MENSAJE_DATOS_INVALIDOS = "Los datos de la operación no son válidos.";
// FE-2D: no se envió ningún intento (sin sesión, sesión de otro usuario o
// pantalla detenida). Nada pudo registrarse.
export const MENSAJE_SESION_CAMBIADA =
  "Tu sesión cambió antes de enviar la operación. No se registró nada.";
// FE-2E: un reintento que no salió, de una intención ya enviada antes. La
// operación original sigue sin confirmar (su clave y sus datos se conservan).
export const MENSAJE_REINTENTO_NO_ENVIADO =
  "No se envió el reintento: tu sesión cambió o no se pudo comprobar. La operación original sigue sin confirmar; volvé a intentarlo con tu sesión.";

const MENSAJES_ERROR: Record<string, string> = {
  jornada_no_autenticado: "Tu sesión no es válida. Volvé a iniciar sesión.",
  jornada_no_autorizado: MENSAJE_SIN_PERMISO,
  jornada_clave_invalida: MENSAJE_ERROR_GENERICO,
  jornada_fecha_invalida:
    "La fecha no es válida: no puede ser anterior al día operativo actual.",
  jornada_cantidad_invalida: "Las cantidades deben ser mayores que cero.",
  jornada_lineas_invalidas: "Revisá los productos y las cantidades cargadas.",
  jornada_producto_repetido: "Un producto aparece más de una vez.",
  jornada_motivo_invalido: "El motivo es obligatorio.",
  jornada_vendedor_invalido:
    "El vendedor no es válido o su perfil está inactivo.",
  jornada_no_encontrada: "La jornada no existe o no pertenece a tu empresa.",
  jornada_camion_no_encontrado:
    "El camión no existe o no pertenece a tu empresa.",
  jornada_vendedor_no_encontrado:
    "El vendedor no existe o no pertenece a tu empresa.",
  jornada_producto_no_encontrado:
    "El producto no existe o no pertenece a tu empresa.",
  jornada_duplicada: "Ese camión ya tiene una jornada en esa fecha.",
  jornada_camion_con_jornada_abierta:
    "El camión tiene otra jornada sin cerrar.",
  jornada_camion_inactivo: "El camión está dado de baja.",
  jornada_vendedor_ocupado: "El vendedor ya tiene una jornada en esa fecha.",
  jornada_estado_invalido:
    "La jornada cambió o no está en el estado que permite esta operación. Revisala e intentá de nuevo.",
  jornada_con_movimientos:
    "La jornada ya tiene movimientos: no se puede corregir.",
  jornada_sin_cambios: "No hay cambios para registrar.",
  jornada_producto_inactivo: "El producto está dado de baja.",
  jornada_stock_residual: "El camión tiene stock que no corresponde a la jornada.",
  jornada_stock_insuficiente: "No hay stock suficiente.",
  jornada_descarga_excede_carga:
    "La descarga supera lo cargado en el camión.",
  jornada_carga_neta_cero:
    "El camión no tiene carga neta: no se puede confirmar la salida.",
  jornada_conflicto_idempotencia:
    "Esta operación ya se registró con otros datos. Revisá la jornada antes de volver a cargarla.",
  jornada_error_interno: MENSAJE_ERROR_GENERICO,
  jornada_ubicacion_no_configurada:
    "La empresa no tiene configurado el depósito o la ubicación del camión.",
  // E-SL1 (25006): sólo ocurre si la RPC se invoca por GET/HEAD.
  jornada_metodo_no_permitido: MENSAJE_ERROR_GENERICO,
};

type Clase = "definitivo" | "transitorio" | "sin_respuesta";

interface Clasificacion {
  clase: Clase;
  codigo: string | null;
  mensaje: string;
}

/**
 * Clasifica un error de Supabase. Sólo se usa el `message` cuando es un
 * código conocido; cualquier otra cosa se reemplaza por un mensaje genérico.
 */
export function clasificarErrorJornada(error: unknown): Clasificacion {
  if (error !== null && typeof error === "object") {
    const { code, message } = error as { code?: unknown; message?: unknown };

    if (typeof message === "string" && Object.hasOwn(MENSAJES_ERROR, message)) {
      return { clase: "definitivo", codigo: message, mensaje: MENSAJES_ERROR[message] };
    }
    if (code === "40001" || code === "40P01") {
      return { clase: "transitorio", codigo: code, mensaje: MENSAJE_CONCURRENCIA };
    }
    if (code === "42501") {
      return { clase: "definitivo", codigo: code, mensaje: MENSAJE_SIN_PERMISO };
    }
    // supabase-js devuelve `code` vacío ante un fallo de red.
    if (code === "" || code === undefined) {
      return { clase: "sin_respuesta", codigo: null, mensaje: MENSAJE_RESULTADO_DESCONOCIDO };
    }
    return {
      clase: "definitivo",
      codigo: typeof code === "string" ? code : null,
      mensaje: MENSAJE_ERROR_GENERICO,
    };
  }
  return { clase: "sin_respuesta", codigo: null, mensaje: MENSAJE_RESULTADO_DESCONOCIDO };
}

const FORMATO_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FORMATO_FECHA = /^(\d{4})-(\d{2})-(\d{2})$/;

export function esUuid(valor: unknown): valor is string {
  return typeof valor === "string" && FORMATO_UUID.test(valor);
}

/** Fecha de calendario real 'AAAA-MM-DD' entre 0001-01-01 y 9999-12-31. */
export function esFechaValida(valor: unknown): valor is string {
  if (typeof valor !== "string") return false;
  const m = FORMATO_FECHA.exec(valor);
  if (m === null) return false;
  const [anio, mes, dia] = [Number(m[1]), Number(m[2]), Number(m[3])];
  if (anio < 1 || mes < 1 || mes > 12 || dia < 1) return false;
  const bisiesto = (anio % 4 === 0 && anio % 100 !== 0) || anio % 400 === 0;
  const dias = [31, bisiesto ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return dia <= dias[mes - 1];
}

export function esCantidadJornada(valor: unknown): valor is number {
  return (
    typeof valor === "number" &&
    Number.isSafeInteger(valor) &&
    valor >= 1 &&
    valor <= CANTIDAD_MAXIMA
  );
}

/**
 * Cantidad en unidad mínima desde el texto que escribe el usuario: `unidad`
 * en enteros; `peso` en kg con coma decimal y hasta 3 decimales, convertido a
 * gramos enteros sin punto flotante (domain/peso.ts). Devuelve null si el
 * texto no es válido o la cantidad no es un entero entre 1 y 2147483647.
 */
export function cantidadDesdeTexto(
  formaVenta: "unidad" | "peso",
  texto: string
): number | null {
  const valor =
    formaVenta === "peso" ? kg_a_gramos(texto) : cantidad_unidad_desde_texto(texto);
  return valor !== null && esCantidadJornada(valor) ? valor : null;
}

function lineasValidas(lineas: unknown): boolean {
  if (!Array.isArray(lineas) || lineas.length === 0) return false;
  const vistos = new Set<string>();
  for (const l of lineas as unknown[]) {
    if (l === null || typeof l !== "object") return false;
    const { productoId, cantidad } = l as Record<string, unknown>;
    if (!esUuid(productoId) || !esCantidadJornada(cantidad)) return false;
    const clave = productoId.toLowerCase();
    if (vistos.has(clave)) return false;
    vistos.add(clave);
  }
  return true;
}

function motivoValido(motivo: unknown): boolean {
  return typeof motivo === "string" && motivo.trim() !== "";
}

/**
 * Validación local, igual o más laxa que la del servidor (que siempre decide):
 * evita enviar pedidos que el servidor rechazaría por forma. No valida reglas
 * de negocio (estados, fechas pasadas, stock): eso lo hace la RPC.
 */
export function validarComandoJornada(comando: ComandoJornada): string | null {
  switch (comando.tipo) {
    case "abrir":
      return esUuid(comando.camionId) &&
        esUuid(comando.vendedorId) &&
        esFechaValida(comando.fecha)
        ? null
        : MENSAJE_DATOS_INVALIDOS;
    case "reasignar":
      return esUuid(comando.jornadaId) && esUuid(comando.vendedorId)
        ? null
        : MENSAJE_DATOS_INVALIDOS;
    case "corregir":
      return esUuid(comando.jornadaId) &&
        esUuid(comando.camionId) &&
        esFechaValida(comando.fecha) &&
        motivoValido(comando.motivo)
        ? null
        : MENSAJE_DATOS_INVALIDOS;
    case "cargar":
      return esUuid(comando.jornadaId) && lineasValidas(comando.lineas)
        ? null
        : MENSAJE_DATOS_INVALIDOS;
    case "descargar":
      return esUuid(comando.jornadaId) &&
        lineasValidas(comando.lineas) &&
        motivoValido(comando.motivo)
        ? null
        : MENSAJE_DATOS_INVALIDOS;
    case "salir":
      return esUuid(comando.jornadaId) ? null : MENSAJE_DATOS_INVALIDOS;
  }
}

export interface LlamadaRpc {
  nombre:
    | "abrir_jornada"
    | "reasignar_vendedor"
    | "corregir_jornada"
    | "registrar_carga"
    | "registrar_descarga"
    | "confirmar_salida";
  argumentos: Readonly<Record<string, unknown>>;
}

/**
 * Traduce un comando a la RPC exacta y sus argumentos. El resultado se congela:
 * los reintentos envían exactamente el mismo payload.
 */
export function llamadaRpcJornada(
  comando: ComandoJornada,
  clave: string
): LlamadaRpc {
  const productos = (l: LineaJornada[]) => l.map((x) => x.productoId);
  const cantidades = (l: LineaJornada[]) => l.map((x) => x.cantidad);
  let llamada: LlamadaRpc;

  switch (comando.tipo) {
    case "abrir":
      llamada = {
        nombre: "abrir_jornada",
        argumentos: {
          p_idempotency_key: clave,
          p_camion_id: comando.camionId,
          p_fecha: comando.fecha,
          p_vendedor_id: comando.vendedorId,
        },
      };
      break;
    case "reasignar":
      llamada = {
        nombre: "reasignar_vendedor",
        argumentos: {
          p_idempotency_key: clave,
          p_jornada_id: comando.jornadaId,
          p_vendedor_id: comando.vendedorId,
        },
      };
      break;
    case "corregir":
      llamada = {
        nombre: "corregir_jornada",
        argumentos: {
          p_idempotency_key: clave,
          p_jornada_id: comando.jornadaId,
          p_fecha: comando.fecha,
          p_camion_id: comando.camionId,
          p_motivo: comando.motivo,
        },
      };
      break;
    case "cargar":
      llamada = {
        nombre: "registrar_carga",
        argumentos: {
          p_idempotency_key: clave,
          p_jornada_id: comando.jornadaId,
          p_productos: Object.freeze(productos(comando.lineas)),
          p_cantidades: Object.freeze(cantidades(comando.lineas)),
        },
      };
      break;
    case "descargar":
      llamada = {
        nombre: "registrar_descarga",
        argumentos: {
          p_idempotency_key: clave,
          p_jornada_id: comando.jornadaId,
          p_productos: Object.freeze(productos(comando.lineas)),
          p_cantidades: Object.freeze(cantidades(comando.lineas)),
          p_motivo: comando.motivo,
        },
      };
      break;
    case "salir":
      llamada = {
        nombre: "confirmar_salida",
        argumentos: { p_idempotency_key: clave, p_jornada_id: comando.jornadaId },
      };
      break;
  }

  return Object.freeze({ nombre: llamada.nombre, argumentos: Object.freeze(llamada.argumentos) });
}

/** Clave nueva por intento lógico (una por acción del usuario, no por reintento). */
export function nuevaClaveIdempotencia(): string {
  return crypto.randomUUID();
}

export function filaAJornada(fila: unknown): Jornada | null {
  if (fila === null || typeof fila !== "object") return null;
  const f = fila as Record<string, unknown>;
  const estado = ESTADOS_JORNADA.find((e) => e === f.estado);

  if (
    !esUuid(f.id) ||
    !esFechaValida(f.fecha) ||
    !esUuid(f.camion_id) ||
    !esUuid(f.vendedor_id) ||
    estado === undefined ||
    !esUuid(f.abierta_por) ||
    !esUuid(f.operacion_apertura_id) ||
    typeof f.creado_en !== "string" ||
    f.creado_en === ""
  ) {
    return null;
  }

  return {
    id: f.id,
    fecha: f.fecha,
    camionId: f.camion_id,
    vendedorId: f.vendedor_id,
    estado,
    abiertaPor: f.abierta_por,
    operacionAperturaId: f.operacion_apertura_id,
    creadoEn: f.creado_en,
  };
}

const COLUMNAS_JORNADA =
  "id, fecha, camion_id, vendedor_id, estado, abierta_por, operacion_apertura_id, creado_en";

// true si `a` está estrictamente después de `b` en el orden fecha desc, id desc
// (las fechas AAAA-MM-DD y los uuid en minúscula comparan igual como texto).
function esAnterior(a: CursorJornadas, b: CursorJornadas): boolean {
  if (a.fecha !== b.fecha) return a.fecha < b.fecha;
  return a.id.toLowerCase() < b.id.toLowerCase();
}

function fallo<T>(error: ErrorJornada, intentos: number): ResultadoJornada<T> {
  return { ok: false, error, intentos };
}

export function crearPuertoJornadas(cliente: SupabaseClient): PuertoJornadas {
  async function leerPaginaJornadas(
    opciones?: OpcionesLecturaJornadas
  ): Promise<ResultadoJornada<PaginaJornadas>> {
    const errorLectura: ErrorJornada = {
      codigo: null,
      mensaje: MENSAJE_ERROR_LECTURA,
      resultadoDesconocido: false,
    };
    const fecha = opciones?.fecha;
    const despues = opciones?.despues;
    if (
      (fecha !== undefined && !esFechaValida(fecha)) ||
      (despues !== undefined &&
        (despues === null ||
          typeof despues !== "object" ||
          !esFechaValida(despues.fecha) ||
          !esUuid(despues.id)))
    ) {
      return fallo({ ...errorLectura, mensaje: MENSAJE_DATOS_INVALIDOS }, 0);
    }
    // Con filtro de fecha, el cursor debe pertenecer a esa misma fecha: de lo
    // contrario la consulta sería inconsistente (filas posteriores a un cursor
    // de otra fecha que nunca coinciden con el filtro).
    if (fecha !== undefined && despues !== undefined && fecha !== despues.fecha) {
      return fallo({ ...errorLectura, mensaje: MENSAJE_DATOS_INVALIDOS }, 0);
    }
    const pedidas = TAMANO_PAGINA_JORNADAS + 1;
    try {
      let consulta = cliente
        .from("jornadas")
        .select(COLUMNAS_JORNADA, { count: "exact" });
      if (fecha !== undefined) consulta = consulta.eq("fecha", fecha);
      // fecha y id ya validados (sólo dígitos, guiones y hex): sin inyección.
      if (despues !== undefined) {
        consulta = consulta.or(
          `fecha.lt.${despues.fecha},and(fecha.eq.${despues.fecha},id.lt.${despues.id})`
        );
      }
      const { data, error, count } = await consulta
        .order("fecha", { ascending: false })
        .order("id", { ascending: false })
        .limit(pedidas);

      if (error || !Array.isArray(data)) return fallo(errorLectura, 1);
      // Consistencia de tamaño: no se confía sólo en "vinieron menos filas".
      // Con conteo exacto, debe venir min(pedidas, total) filas; si vinieron
      // menos, el servidor truncó (max_rows) y la página no es confiable.
      if (
        typeof count !== "number" ||
        !Number.isSafeInteger(count) ||
        count < data.length ||
        data.length !== Math.min(pedidas, count)
      ) {
        return fallo(errorLectura, 1);
      }
      const todas = data.map(filaAJornada);
      // Una fila inesperada invalida toda la lectura (falla cerrada).
      if (todas.some((j) => j === null)) return fallo(errorLectura, 1);
      const filas = todas as Jornada[];

      // Invariantes del keyset: filtro de fecha, posterior al cursor y orden
      // estricto (fecha desc, id desc) sin repetidos.
      let previa: CursorJornadas | undefined = despues;
      for (const j of filas) {
        if (fecha !== undefined && j.fecha !== fecha) return fallo(errorLectura, 1);
        if (previa !== undefined && !esAnterior(j, previa)) {
          return fallo(errorLectura, 1);
        }
        previa = { fecha: j.fecha, id: j.id };
      }

      const hayMas = filas.length > TAMANO_PAGINA_JORNADAS;
      const jornadas = hayMas ? filas.slice(0, TAMANO_PAGINA_JORNADAS) : filas;
      const ultima = jornadas[jornadas.length - 1];
      return {
        ok: true,
        datos: {
          jornadas,
          siguiente: hayMas ? { fecha: ultima.fecha, id: ultima.id } : null,
        },
        intentos: 1,
      };
    } catch {
      return fallo(errorLectura, 1);
    }
  }

  async function leerTodasLasJornadas(filtro?: {
    fecha?: string;
  }): Promise<ResultadoJornada<Jornada[]>> {
    const vistos = new Set<string>();
    const acumuladas: Jornada[] = [];
    let despues: CursorJornadas | undefined;
    let solicitudes = 0;

    while (solicitudes < MAX_PAGINAS_JORNADAS) {
      const r = await leerPaginaJornadas({ fecha: filtro?.fecha, despues });
      solicitudes += 1;
      // Error en cualquier página: se descarta lo leído (nada parcial).
      if (!r.ok) return { ok: false, error: r.error, intentos: solicitudes };
      for (const j of r.datos.jornadas) {
        if (!vistos.has(j.id)) {
          vistos.add(j.id);
          acumuladas.push(j);
        }
      }
      if (r.datos.siguiente === null) {
        return { ok: true, datos: acumuladas, intentos: solicitudes };
      }
      despues = r.datos.siguiente;
    }
    return fallo(
      {
        codigo: null,
        mensaje: MENSAJE_ERROR_LECTURA,
        resultadoDesconocido: false,
      },
      solicitudes
    );
  }

  return {
    leerPaginaJornadas,
    leerTodasLasJornadas,

    async ejecutar(comando, claveIdempotencia, opciones = {}) {
      if (!esUuid(claveIdempotencia)) {
        return fallo(
          { codigo: null, mensaje: MENSAJE_ERROR_GENERICO, resultadoDesconocido: false },
          0
        );
      }
      const invalido = validarComandoJornada(comando);
      if (invalido !== null) {
        return fallo({ codigo: null, mensaje: invalido, resultadoDesconocido: false }, 0);
      }

      // Mismo nombre y mismos argumentos (congelados) en todos los intentos.
      const llamada = llamadaRpcJornada(comando, claveIdempotencia);
      let ultima: Clasificacion = {
        clase: "sin_respuesta",
        codigo: null,
        mensaje: MENSAJE_RESULTADO_DESCONOCIDO,
      };

      // Identidad del primer intento: todos los reintentos salen con ella o no salen.
      let actorFijado: string | null = opciones.usuarioEsperado ?? null;

      // FE-2D (H-1): sin intento nuevo. Si no salió ninguno, nada pudo
      // registrarse; si salió alguno, se conserva su clasificación (un intento
      // sin respuesta deja el resultado desconocido: no se cancela ni se niega).
      const sinEnviar = (enviados: number): ResultadoJornada<string> =>
        enviados === 0
          ? fallo({ codigo: null, mensaje: MENSAJE_SESION_CAMBIADA, resultadoDesconocido: false }, 0)
          : fallo(
              {
                codigo: ultima.codigo,
                mensaje: ultima.mensaje,
                resultadoDesconocido: ultima.clase === "sin_respuesta",
              },
              enviados
            );

      for (let intento = 1; intento <= MAX_INTENTOS; intento++) {
        if (opciones.continuar && !opciones.continuar()) return sinEnviar(intento - 1);
        let token: string;
        let actorEnvio: string;
        try {
          const { data: sesion } = await cliente.auth.getSession();
          const actor = sesion.session?.user.id ?? null;
          if (!sesion.session || actor === null) return sinEnviar(intento - 1);
          if (actorFijado === null) actorFijado = actor;
          if (actor !== actorFijado) return sinEnviar(intento - 1);
          token = sesion.session.access_token;
          actorEnvio = actor;
        } catch {
          return sinEnviar(intento - 1);
        }
        // getSession espera: se vuelve a comprobar justo antes de enviar.
        if (opciones.continuar && !opciones.continuar()) return sinEnviar(intento - 1);
        // FE-2E: el primer despacho de esta llamada fija la identidad de la
        // intención (síncrono, inmediatamente antes del envío).
        if (intento === 1) opciones.alFijarActor?.(actorEnvio);

        try {
          // El token enviado es exactamente el verificado (supabase-js no
          // reemplaza un Authorization explícito).
          const { data, error } = await cliente
            .rpc(llamada.nombre, llamada.argumentos)
            .setHeader("Authorization", `Bearer ${token}`);
          if (!error) {
            if (esUuid(data)) return { ok: true, datos: data, intentos: intento };
            // Respuesta sin uuid: no se puede confirmar el resultado.
            ultima = { clase: "sin_respuesta", codigo: null, mensaje: MENSAJE_RESULTADO_DESCONOCIDO };
          } else {
            ultima = clasificarErrorJornada(error);
          }
        } catch {
          ultima = { clase: "sin_respuesta", codigo: null, mensaje: MENSAJE_RESULTADO_DESCONOCIDO };
        }

        if (ultima.clase === "definitivo") {
          return fallo(
            { codigo: ultima.codigo, mensaje: ultima.mensaje, resultadoDesconocido: false },
            intento
          );
        }
      }

      // Agotados los intentos: 40001/40P01 revierten la transacción (sin
      // efectos); sin respuesta, el resultado es desconocido.
      return fallo(
        {
          codigo: ultima.codigo,
          mensaje: ultima.mensaje,
          resultadoDesconocido: ultima.clase === "sin_respuesta",
        },
        MAX_INTENTOS
      );
    },
  };
}

let puerto: PuertoJornadas | null = null;

export function obtenerPuertoJornadas(): PuertoJornadas {
  if (!puerto) puerto = crearPuertoJornadas(obtenerClienteSupabase());
  return puerto;
}
