import { useAuth } from "../auth/useAuth";
import { ROLES_GESTION } from "../auth/roles";
import { useCatalogoCamiones } from "../hooks/useCatalogoCamiones";
import { useJornadasLectura } from "../hooks/useJornadasLectura";
import { JornadasVista } from "./JornadasVista";
import { idCorto } from "./jornadas_presentacion";

// Pantalla de jornadas reales (B-02b.1): sólo lectura sobre la capa B-02a.
// Dueño y encargado leen las jornadas de su empresa; el vendedor/piloto lee
// sólo la suya (Blueprint §9, ADR-007 §2.8; la RLS decide las filas). Las operaciones mutadoras
// (abrir, cargar, descargar, confirmar salida) llegan en B-02b.2: hasta
// entonces sus botones están deshabilitados y no se llama a ninguna RPC.
export default function Jornadas() {
  const jornadas = useJornadasLectura();
  const { catalogo } = useCatalogoCamiones();
  const { usuario } = useAuth();
  // Sólo presentación: el acceso lo decide ProtectedRoute y las filas, RLS.
  const puedeAdministrar =
    usuario !== null && ROLES_GESTION.includes(usuario.rol);

  // Nombre del camión del catálogo real; si el catálogo no se pudo leer o el
  // camión no figura, se muestra un identificador corto (nunca un dato inventado).
  function nombreCamion(camionId: string): string {
    if (catalogo.estado === "listo") {
      const camion = catalogo.camiones.find((c) => c.id === camionId);
      if (camion) return `${camion.nombre} · ${camion.patente}`;
    }
    return `Camión ${idCorto(camionId)}`;
  }

  return (
    <JornadasVista
      estado={jornadas.estado}
      puedeAdministrar={puedeAdministrar}
      nombreCamion={nombreCamion}
      onCambiarFecha={jornadas.cambiarFecha}
      onRecargar={jornadas.recargar}
      onCargarMas={jornadas.cargarMas}
      onCargarTodas={jornadas.cargarTodas}
      onSeleccionar={jornadas.seleccionar}
    />
  );
}
