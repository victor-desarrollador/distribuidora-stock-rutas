

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
import Login from "./pages/Login";

// Dueño y encargado: lo que tenía el administrador del prototipo.
// Vendedor/piloto: lo que tenía el vendedor. El rol "depósito" no existe
// (Blueprint §9).
const gestion = ROLES_GESTION;
const todos = ROLES_TODOS;

function Inicio() {
  // La página de inicio es común para todos los roles autenticados. La ruta
  // /autoventa se retiró porque depende de localStorage como fuente de verdad
  // de negocio; no se redirige a una pantalla demo operativa.
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

        <Route path="*" element={<Navigate to="/" replace />} />
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
            <Route path="/*" element={<RutasPrivadas />} />
          </Routes>
        </BrowserRouter>
      </BorradorCargaProvider>
    </AuthProvider>
  );
}
