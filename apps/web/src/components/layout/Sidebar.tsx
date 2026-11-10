
import { useEffect, useState } from "react";
import { NavLink } from "react-router-dom";

import {
  LogOut,
  UserCircle,
  Menu,
  X,
} from "lucide-react";

import { useAuth } from "../../auth/useAuth";
import { nombreRol } from "../../auth/roles";
import { useBorradorCarga } from "../../hooks/borradorCargaContexto";
import {
  ConfirmarDescarteBorrador,
  MENSAJE_DESCARTE_CIERRE_SESION,
} from "../ConfirmarDescarteBorrador";
import { aceptarSalida, pedirSalida } from "./cierre_sesion";
import { itemsMenuPorRol } from "./menu";

export default function Sidebar() {
  const { usuario, cerrarSesion } = useAuth();
  const borradorCarga = useBorradorCarga();

  const [menuAbierto, setMenuAbierto] = useState(false);

  // Permitir cerrar el menú con Escape.
  useEffect(() => {
    if (!menuAbierto) return;

    function cerrarConEscape(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setMenuAbierto(false);
      }
    }

    window.addEventListener("keydown", cerrarConEscape);

    return () => {
      window.removeEventListener("keydown", cerrarConEscape);
    };
  }, [menuAbierto]);

  const menuVisible = itemsMenuPorRol(usuario?.rol);

  const rolVisible = usuario ? nombreRol(usuario.rol) : "Sin sesión";

  // FE-1E: con un borrador de carga escrito, cerrar sesión pide confirmar el
  // descarte; el menú queda abierto para mostrar la pregunta.
  function cerrarYOcultar() {
    setMenuAbierto(false);
    void cerrarSesion();
  }

  function salir() {
    pedirSalida(borradorCarga, cerrarYOcultar);
  }

  const confirmandoSalida = borradorCarga.pendiente?.tipo === "cerrar_sesion";

  return (
    <>
      {/* BOTÓN HAMBURGUESA PARA CELULARES */}
      <button
        type="button"
        onClick={() => setMenuAbierto(true)}
        aria-label="Abrir menú de navegación"
        aria-expanded={menuAbierto}
        aria-controls="sidebar-principal"
        className="fixed left-3 top-3 z-40 flex h-12 w-12 items-center justify-center rounded-xl bg-slate-900 text-white shadow-lg md:hidden"
      >
        <Menu size={25} />
      </button>

      {/* FONDO OSCURO AL ABRIR EL MENÚ EN MÓVIL */}
      {menuAbierto && (
        <button
          type="button"
          onClick={() => setMenuAbierto(false)}
          aria-label="Cerrar menú"
          className="fixed inset-0 z-40 bg-black/60 md:hidden"
        />
      )}

      {/* SIDEBAR RESPONSIVE */}
      <aside
        id="sidebar-principal"
        className={`
          fixed inset-y-0 left-0 z-50
          flex h-dvh w-72 max-w-[85vw] flex-col
          bg-slate-900 p-5 text-white shadow-xl
          transition-transform duration-200 ease-in-out

          md:static md:z-auto md:h-screen md:w-64
          md:max-w-none md:shrink-0 md:translate-x-0
          md:shadow-none

          ${
            menuAbierto
              ? "translate-x-0"
              : "-translate-x-full"
          }
        `}
      >
        {/* ENCABEZADO */}
        <div className="mb-6 flex items-start justify-between gap-3">
          <div>
            <h1 className="text-xl font-bold">
              Distribuidora
            </h1>

            <p className="mt-1 text-sm text-slate-400">
              Stock
            </p>
          </div>

          {/* CERRAR MENÚ EN CELULAR */}
          <button
            type="button"
            onClick={() => setMenuAbierto(false)}
            aria-label="Cerrar navegación"
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-slate-800 text-white md:hidden"
          >
            <X size={22} />
          </button>
        </div>

        {/* USUARIO CONECTADO */}
        <div className="mb-5 flex items-center gap-3 rounded-xl bg-slate-800 p-3">
          <UserCircle
            size={30}
            className="shrink-0 text-blue-400"
          />

          <div className="min-w-0">
            <p className="truncate text-sm font-semibold">
              {usuario?.nombre ?? "Sin usuario"}
            </p>

            <p className="text-xs text-slate-400">
              {rolVisible}
            </p>
          </div>
        </div>

        {/* ENLACES DE NAVEGACIÓN */}
        <nav
          aria-label="Menú principal"
          className="min-h-0 flex-1 space-y-1 overflow-y-auto overscroll-contain pb-4"
        >
          {menuVisible.map(
            ({ nombre, icono: Icono, ruta }) => (
              <NavLink
                key={ruta}
                to={ruta}
                end={ruta === "/"}
                onClick={() => setMenuAbierto(false)}
                className={({ isActive }) =>
                  `flex min-h-12 items-center gap-3 rounded-lg px-4 py-3 text-sm font-medium transition-colors ${
                    isActive
                      ? "bg-blue-600 text-white"
                      : "text-slate-300 hover:bg-slate-800 hover:text-white"
                  }`
                }
              >
                <Icono
                  size={20}
                  className="shrink-0"
                />

                <span>{nombre}</span>
              </NavLink>
            )
          )}
        </nav>

        {/* CERRAR SESIÓN */}
        <div className="shrink-0 border-t border-slate-700 pt-4">
          {confirmandoSalida && (
            <ConfirmarDescarteBorrador
              id="descarte-carga-cierre-sesion"
              mensaje={MENSAJE_DESCARTE_CIERRE_SESION}
              textoCancelar="Seguir con el borrador"
              textoAceptar="Descartar y cerrar sesión"
              onCancelar={borradorCarga.cancelarDescarte}
              onAceptar={() => aceptarSalida(borradorCarga, cerrarYOcultar)}
            />
          )}

          <button
            type="button"
            onClick={salir}
            className="flex min-h-12 w-full items-center gap-3 rounded-lg px-4 py-3 text-left text-sm font-medium text-slate-300 transition-colors hover:bg-red-900/30 hover:text-red-300"
          >
            <LogOut size={20} />

            <span>Cerrar sesión</span>
          </button>
        </div>
      </aside>
    </>
  );
}
