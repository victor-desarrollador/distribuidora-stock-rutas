
import {
  BrowserRouter,
  Routes,
  Route,
} from "react-router-dom";

import AppLayout from "./components/layout/AppLayout";

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

export default function App() {
  return (
    <BrowserRouter>
      <AppLayout>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/productos" element={<Productos />} />
          <Route path="/clientes" element={<Clientes />} />
          <Route path="/camiones" element={<Camiones />} />
          <Route path="/jornadas" element={<Jornadas />} />
          <Route path="/ventas" element={<Autoventa />} />
          <Route path="/retornos" element={<Retornos />} />
          <Route path="/movimientos" element={<Movimientos />} />
          <Route path="/rendicion" element={<Rendicion />} />
          <Route path="/cuentas" element={<CuentasCorrientes />}/>
          <Route path="*" element={<Dashboard />} />
        </Routes>
      </AppLayout>
    </BrowserRouter>
  );
}
