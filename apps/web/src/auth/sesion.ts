// Lógica de sesión independiente de React y de Supabase.
//
// La autoridad sobre empresa, rol y estado es exclusivamente la fila de
// `perfiles` (tabla protegida por RLS). El puerto nunca expone user_metadata
// ni app_metadata, de modo que no pueden usarse para autorizar.

import {
  identificador_auth_interno,
  normalizar_usuario,
} from "../domain/usuario_auth";
import { esRolUsuario, type RolUsuario } from "./roles";

export interface Perfil {
  usuarioId: string;
  empresaId: string;
  usuario: string;
  nombre: string;
  rol: RolUsuario;
  activo: boolean;
}

export interface Empresa {
  id: string;
  nombre: string;
  activo: boolean;
}

export type MotivoBloqueo =
  | "sin_perfil"
  | "perfil_invalido"
  | "perfil_inactivo"
  | "empresa_no_disponible";

export type EstadoSesion =
  | { estado: "cargando" }
  | { estado: "no_autenticado" }
  | { estado: "autenticado"; perfil: Perfil; empresa: Empresa }
  | { estado: "bloqueado"; motivo: MotivoBloqueo }
  | { estado: "error"; mensaje: string };

export type ErrorInicioSesion = "credenciales" | "otro";

// Operaciones que la aplicación necesita del proveedor de Auth.
export interface PuertoAuth {
  iniciarConPassword(
    identificador: string,
    password: string
  ): Promise<{ error: ErrorInicioSesion | null }>;
  cerrarSesion(): Promise<void>;
  // Notifica el id del usuario autenticado (o null) al suscribirse y en cada
  // evento de Auth, aunque el id no cambie. El cierre de sesión (null) se
  // notifica de inmediato. Devuelve la función para desuscribirse.
  alCambiarUsuario(callback: (usuarioId: string | null) => void): () => void;
  // Lecturas sujetas a RLS. Devuelven null si no hay fila visible y lanzan
  // ante errores de red o de base.
  leerPerfil(usuarioId: string): Promise<unknown>;
  leerEmpresa(empresaId: string): Promise<unknown>;
}

export const MENSAJE_CREDENCIALES = "Usuario o contraseña incorrectos.";

export type ResultadoInicioSesion =
  | { ok: true }
  | { ok: false; mensaje: string };

export async function iniciarSesion(
  puerto: PuertoAuth,
  usuarioIngresado: string,
  password: string
): Promise<ResultadoInicioSesion> {
  const usuario = normalizar_usuario(usuarioIngresado);

  if (!usuario) {
    return {
      ok: false,
      mensaje:
        "Usuario inválido: usá de 3 a 32 letras, números, punto, guion o guion bajo; debe empezar y terminar con letra o número, sin puntos seguidos.",
    };
  }

  if (password.length === 0) {
    return { ok: false, mensaje: "Ingresá la contraseña." };
  }

  try {
    const { error } = await puerto.iniciarConPassword(
      identificador_auth_interno(usuario),
      password
    );

    if (error === "credenciales") {
      return { ok: false, mensaje: MENSAJE_CREDENCIALES };
    }

    if (error) {
      return {
        ok: false,
        mensaje:
          "No se pudo iniciar sesión. Verificá la conexión e intentá de nuevo.",
      };
    }

    return { ok: true };
  } catch {
    return {
      ok: false,
      mensaje:
        "No se pudo iniciar sesión. Verificá la conexión e intentá de nuevo.",
    };
  }
}

function esTexto(valor: unknown): valor is string {
  return typeof valor === "string" && valor.length > 0;
}

export function parsearPerfil(fila: unknown): Perfil | null {
  if (typeof fila !== "object" || fila === null) return null;

  const f = fila as Record<string, unknown>;

  if (
    !esTexto(f.usuario_id) ||
    !esTexto(f.empresa_id) ||
    !esTexto(f.usuario) ||
    !esTexto(f.nombre) ||
    !esRolUsuario(f.rol) ||
    typeof f.activo !== "boolean"
  ) {
    return null;
  }

  return {
    usuarioId: f.usuario_id,
    empresaId: f.empresa_id,
    usuario: f.usuario,
    nombre: f.nombre,
    rol: f.rol,
    activo: f.activo,
  };
}

export function parsearEmpresa(fila: unknown): Empresa | null {
  if (typeof fila !== "object" || fila === null) return null;

  const f = fila as Record<string, unknown>;

  if (
    !esTexto(f.id) ||
    !esTexto(f.nombre) ||
    typeof f.activo !== "boolean"
  ) {
    return null;
  }

  return { id: f.id, nombre: f.nombre, activo: f.activo };
}

export const MENSAJE_ERROR_PERFIL =
  "No se pudo verificar tu perfil. Recargá la página o intentá más tarde.";

// Resuelve el estado de acceso a partir del usuario autenticado, leyendo
// perfil y empresa desde las tablas protegidas. Falla cerrado: cualquier
// ausencia o dato inválido bloquea el acceso.
export async function resolverEstadoSesion(
  puerto: PuertoAuth,
  usuarioId: string | null
): Promise<EstadoSesion> {
  if (!usuarioId) return { estado: "no_autenticado" };

  try {
    const filaPerfil = await puerto.leerPerfil(usuarioId);

    if (filaPerfil === null || filaPerfil === undefined) {
      return { estado: "bloqueado", motivo: "sin_perfil" };
    }

    const perfil = parsearPerfil(filaPerfil);

    if (!perfil || perfil.usuarioId !== usuarioId) {
      return { estado: "bloqueado", motivo: "perfil_invalido" };
    }

    if (!perfil.activo) {
      return { estado: "bloqueado", motivo: "perfil_inactivo" };
    }

    const empresa = parsearEmpresa(
      await puerto.leerEmpresa(perfil.empresaId)
    );

    if (!empresa || empresa.id !== perfil.empresaId || !empresa.activo) {
      return { estado: "bloqueado", motivo: "empresa_no_disponible" };
    }

    return { estado: "autenticado", perfil, empresa };
  } catch {
    return { estado: "error", mensaje: MENSAJE_ERROR_PERFIL };
  }
}

export interface ControladorSesion {
  // Evento de Auth con el usuario vigente (o null). Con usuario, siempre
  // vuelve a leer el perfil, aunque el id no haya cambiado.
  notificarUsuario(usuarioId: string | null): void;
  // Descarta de inmediato el estado autorizado y toda lectura en curso.
  invalidar(): void;
  detener(): void;
}

// Coordina eventos de Auth y lecturas de perfil. Cada evento abre una nueva
// generación: sólo el resultado de la generación vigente se publica, de modo
// que una respuesta vieja (de otro usuario o previa al logout) nunca
// sobrescribe el estado actual.
//
// Cambio de usuario: se publica `cargando` antes de leer, para no mostrar el
// perfil anterior. Mismo usuario: se conserva el estado mientras se
// revalida y luego se reemplaza por el resultado (rol, empresa o `activo`
// actualizados; error => fail-closed).
export function crearControladorSesion(
  puerto: PuertoAuth,
  publicar: (estado: EstadoSesion) => void
): ControladorSesion {
  let generacion = 0;
  let usuarioVigente: string | null = null;
  let detenido = false;

  function invalidar() {
    if (detenido) return;

    generacion++;
    usuarioVigente = null;
    publicar({ estado: "no_autenticado" });
  }

  function notificarUsuario(usuarioId: string | null) {
    if (detenido) return;
    if (!usuarioId) return invalidar();

    const propia = ++generacion;

    if (usuarioId !== usuarioVigente) {
      usuarioVigente = usuarioId;
      publicar({ estado: "cargando" });
    }

    void resolverEstadoSesion(puerto, usuarioId).then((estado) => {
      if (!detenido && propia === generacion) publicar(estado);
    });
  }

  return {
    notificarUsuario,
    invalidar,
    detener() {
      detenido = true;
      generacion++;
    },
  };
}

export type DecisionAcceso =
  | "cargando"
  | "redirigir_login"
  | "bloqueado"
  | "rol_no_permitido"
  | "permitido";

export function decidirAcceso(
  sesion: EstadoSesion,
  roles: readonly RolUsuario[]
): DecisionAcceso {
  if (sesion.estado === "cargando") return "cargando";
  if (sesion.estado === "no_autenticado") return "redirigir_login";
  if (sesion.estado !== "autenticado") return "bloqueado";

  // Defensa en profundidad: aunque el estado diga autenticado, un perfil
  // inactivo nunca pasa.
  if (!sesion.perfil.activo) return "bloqueado";

  return roles.includes(sesion.perfil.rol)
    ? "permitido"
    : "rol_no_permitido";
}

export function mensajeBloqueo(sesion: EstadoSesion): string {
  if (sesion.estado === "error") return sesion.mensaje;
  if (sesion.estado !== "bloqueado") return "";

  switch (sesion.motivo) {
    case "sin_perfil":
      return "Tu cuenta no tiene un perfil habilitado. Pedile al dueño o encargado que lo configure.";
    case "perfil_invalido":
      return "Tu perfil tiene datos inválidos. Pedile al dueño o encargado que lo revise.";
    case "perfil_inactivo":
      return "Tu cuenta está desactivada. Pedile al dueño o encargado que la habilite.";
    case "empresa_no_disponible":
      return "La empresa asociada a tu cuenta no está disponible.";
  }
}
