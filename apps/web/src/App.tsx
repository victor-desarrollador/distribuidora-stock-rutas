

import {
  BrowserRouter,
  Routes,
  Route,
  Navigate,
} from "react-router-dom";

import AppLayout from "./components/layout/AppLayout";
import ProtectedRoute from "./components/ProtectedRoute";

import {
  AuthProvider,
  useAuth,
  type RolUsuario,
} from "./AuthContext";

import Dashboard from "./pages/Dashboard";
import Productos from "./pages/Productos";
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

const admin: RolUsuario[] = ["administrador"];

const adminDeposito: RolUsuario[] = [
  "administrador",
  "deposito",
];

const adminVendedor: RolUsuario[] = [
  "administrador",
  "vendedor",
];

const todos: RolUsuario[] = [
  "administrador",
  "vendedor",
  "deposito",
];

function Inicio() {
  const { usuario } = useAuth();

  if (usuario?.rol === "vendedor") {
    return <Navigate to="/autoventa" replace />;
  }

  if (usuario?.rol === "deposito") {
    return <Navigate to="/jornadas" replace />;
  }

  return <Dashboard />;
}

function RutasPrivadas() {
  const { usuario } = useAuth();

  if (!usuario) {
    return <Navigate to="/login" replace />;
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
            <ProtectedRoute roles={adminDeposito}>
              <Productos />
            </ProtectedRoute>
          }
        />

        <Route
          path="/clientes"
          element={
            <ProtectedRoute roles={adminVendedor}>
              <Clientes />
            </ProtectedRoute>
          }
        />

        <Route
          path="/camiones"
          element={
            <ProtectedRoute roles={adminDeposito}>
              <Camiones />
            </ProtectedRoute>
          }
        />

        <Route
          path="/jornadas"
          element={
            <ProtectedRoute roles={adminDeposito}>
              <Jornadas />
            </ProtectedRoute>
          }
        />

        <Route
          path="/autoventa"
          element={
            <ProtectedRoute roles={adminVendedor}>
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
            <ProtectedRoute roles={admin}>
              <Rendicion />
            </ProtectedRoute>
          }
        />

        <Route
          path="/retornos"
          element={
            <ProtectedRoute roles={adminDeposito}>
              <Retornos />
            </ProtectedRoute>
          }
        />

        <Route
          path="/cuentas"
          element={
            <ProtectedRoute roles={adminVendedor}>
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
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/configuracion-demo" element={<ConfiguracionDemo />} />
          <Route path="/*" element={<RutasPrivadas />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
