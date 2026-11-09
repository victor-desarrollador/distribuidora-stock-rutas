

import { Suspense, lazy } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  Navigate,
} from "react-router-dom";

import AppLayout from "./components/layout/AppLayout";
import ProtectedRoute from "./components/ProtectedRoute";

import { AuthProvider } from "./AuthContext";
import { BorradorCargaProvider } from "./hooks/BorradorCargaProvider";
import { useAuth } from "./auth/useAuth";
import {
  ROLES_GESTION,
  ROLES_SOLO_DUENO,
  ROLES_TODOS,
} from "./auth/roles";
import {
  PantallaAccesoBloqueado,
  PantallaCargandoSesion,
} from "./components/EstadoAcceso";

import Dashboard from "./pages/Dashboard";
import Productos from "./pages/Productos";
import Stock from "./pages/Stock";
import Clientes from "./pages/Clientes";
import Camiones from "./pages/Camiones";
import Jornadas from "./pages/Jornadas";
import Autoventa from "./pages/Autoventa";
import Movimientos from "./pages/Movimientos";
import Rendicion from "./pages/Rendicion";
import Retornos from "./pages/Retornos";
import CuentasCorrientes from "./pages/CuentasCorrientes";
import Login from "./pages/Login";
import ConfiguracionDemo from "./pages/ConfiguracionDemo";
import { RUTA_JORNADAS_DEMO } from "./demo/entorno";

// Pantalla demo (D1/D2): sólo se define —y por lo tanto sólo entra al bundle—
// si `import.meta.env.DEV` es verdadero en tiempo de build (desarrollo). Debe
// escribirse en línea: a través de otra constante el bundler no elimina la
// importación diferida (verificado: el chunk quedaba en dist).
const JornadasDemo = import.meta.env.DEV
  ? lazy(() => import("./pages/JornadasDemo"))
  : null;

// Dueño y encargado: lo que tenía el administrador del prototipo.
// Vendedor/piloto: lo que tenía el vendedor. El rol "depósito" no existe
// (Blueprint §9).
const gestion = ROLES_GESTION;
const todos = ROLES_TODOS;

function Inicio() {
  const { usuario } = useAuth();

  if (usuario?.rol === "vendedor_piloto") {
    return <Navigate to="/autoventa" replace />;
  }

  return <Dashboard />;
}

function RutasPrivadas() {
  const { sesion } = useAuth();

  if (sesion.estado === "cargando") {
    return <PantallaCargandoSesion />;
  }

  if (sesion.estado === "no_autenticado") {
    return <Navigate to="/login" replace />;
  }

  if (sesion.estado !== "autenticado") {
    return <PantallaAccesoBloqueado />;
  }

  return (
    <AppLayout>
      <Routes>
        <Route
          path="/"
          element={
            <ProtectedRoute roles={todos}>
              <Inicio />
            </ProtectedRoute>
          }
        />

        <Route
          path="/productos"
          element={
            <ProtectedRoute roles={gestion}>
              <Productos />
            </ProtectedRoute>
          }
        />

        <Route
          path="/stock"
          element={
            <ProtectedRoute roles={gestion}>
              <Stock />
            </ProtectedRoute>
          }
        />

        <Route
          path="/clientes"
          element={
            <ProtectedRoute roles={todos}>
              <Clientes />
            </ProtectedRoute>
          }
        />

        <Route
          path="/camiones"
          element={
            <ProtectedRoute roles={gestion}>
              <Camiones />
            </ProtectedRoute>
          }
        />

        {/* Real: lectura. El vendedor sólo ve su jornada (RLS decide las filas). */}
        <Route
          path="/jornadas"
          element={
            <ProtectedRoute roles={todos}>
              <Jornadas />
            </ProtectedRoute>
          }
        />

        {/* Demo (legado): sólo gestión y sólo fuera de producción. */}
        {JornadasDemo !== null && (
          <Route
            path={RUTA_JORNADAS_DEMO}
            element={
              <ProtectedRoute roles={gestion}>
                <Suspense fallback={<PantallaCargandoSesion />}>
                  <JornadasDemo />
                </Suspense>
              </ProtectedRoute>
            }
          />
        )}

        <Route
          path="/autoventa"
          element={
            <ProtectedRoute roles={todos}>
              <Autoventa />
            </ProtectedRoute>
          }
        />

        <Route
          path="/ventas"
          element={<Navigate to="/autoventa" replace />}
        />

        <Route
          path="/movimientos"
          element={
            <ProtectedRoute roles={todos}>
              <Movimientos />
            </ProtectedRoute>
          }
        />

        <Route
          path="/rendicion"
          element={
            <ProtectedRoute roles={gestion}>
              <Rendicion />
            </ProtectedRoute>
          }
        />

        <Route
          path="/retornos"
          element={
            <ProtectedRoute roles={gestion}>
              <Retornos />
            </ProtectedRoute>
          }
        />

        <Route
          path="/cuentas"
          element={
            <ProtectedRoute roles={todos}>
              <CuentasCorrientes />
            </ProtectedRoute>
          }
        />

        <Route path="*" element={<Inicio />} />
      </Routes>
    </AppLayout>
  );
}

export default function App() {
  return (
    <AuthProvider>
      {/* FE-1D: borrador de carga sobre el router (sobrevive a la navegación
          interna; se descarta al cambiar de usuario). No registra cargas. */}
      <BorradorCargaProvider>
        <BrowserRouter>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route
              path="/configuracion-demo"
              element={
                <ProtectedRoute roles={ROLES_SOLO_DUENO}>
                  <ConfiguracionDemo />
                </ProtectedRoute>
              }
            />
            <Route path="/*" element={<RutasPrivadas />} />
          </Routes>
        </BrowserRouter>
      </BorradorCargaProvider>
    </AuthProvider>
  );
}
