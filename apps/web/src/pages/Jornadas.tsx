import { useEffect, useState } from "react";

import { useAuth } from "../auth/useAuth";
import { ROLES_GESTION } from "../auth/roles";
import { useCatalogoCamiones } from "../hooks/useCatalogoCamiones";
import { useJornadasLectura } from "../hooks/useJornadasLectura";
import { useCorreccionJornada } from "../hooks/useCorreccionJornada";
import { useSalidaJornada } from "../hooks/useSalidaJornada";
import { AvisoSalidaJornada } from "./AvisoSalidaJornada";
import { JornadaCorreccionPanel } from "./JornadaCorreccionPanel";
import { JornadaSalidaPanel } from "./JornadaSalidaPanel";
import { JornadasVista } from "./JornadasVista";
import { fechaOperativaHoy } from "./jornadas_correccion";
import { crearArbitroJornadas, jornadaRetenida } from "./jornadas_operacion";
import { idCorto } from "./jornadas_presentacion";

// Pantalla de jornadas reales. Lectura (B-02b.1) sobre la capa B-02a: dueño y
// encargado leen las jornadas de su empresa; el vendedor/piloto lee sólo la
// suya (Blueprint §9, ADR-007 §2.8; la RLS decide las filas).
// B-02b.2 / S1: dueño y encargado pueden confirmar la salida de una jornada
// cargada; la operación vive en hooks/useSalidaJornada.ts y
// pages/jornadas_salida.ts.
// B-02b.2 / S2: dueño y encargado pueden corregir la fecha o el camión de una
// jornada abierta (hooks/useCorreccionJornada.ts, pages/jornadas_correccion.ts).
// Ambas operaciones usan el motor común pages/jornadas_operacion.ts, cada una
// con su propio controlador e intención, y un árbitro compartido: mientras una
// confirma, envía, verifica o tiene resultado desconocido sobre una jornada, la
// otra no puede iniciarse sobre esa jornada (S2 M-02). Abrir, reasignar, cargar
// y descargar siguen sin habilitarse.
export default function Jornadas() {
  const jornadas = useJornadasLectura();
  // Un árbitro por montaje de la pantalla, compartido por ambas operaciones.
  const [arbitro] = useState(crearArbitroJornadas);
  const salida = useSalidaJornada(jornadas.recargar, arbitro);
  const correccion = useCorreccionJornada(jornadas.recargar, arbitro);
  const { trasRelectura } = correccion;
  const lectura = jornadas.estado.lectura;
  // Cada lectura completa (`listo`) llega en un objeto nuevo y la generación de
  // la lectura descarta respuestas viejas: tras un éxito, el primer `listo` es
  // de la relectura posterior. Sólo libera una NUEVA corrección; no relee.
  useEffect(() => {
    if (lectura.estado === "listo") trasRelectura();
  }, [lectura, trasRelectura]);
  const { catalogo } = useCatalogoCamiones();
  const { usuario } = useAuth();
  // Sólo presentación: el acceso lo decide ProtectedRoute; las filas, RLS; y
  // quién puede confirmar la salida, el servidor.
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

  // Destinos de una corrección: sólo camiones activos (el servidor revalida).
  const camionesActivos =
    catalogo.estado === "listo" ? catalogo.camiones.filter((c) => c.activo) : null;

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
      accionesDetalle={
        puedeAdministrar
          ? (jornada) => (
              <>
                <JornadaSalidaPanel
                  jornada={jornada}
                  fase={salida.fase}
                  bloqueadaPorOtra={jornadaRetenida(correccion.fase) === jornada.id}
                  nombreCamion={nombreCamion(jornada.camionId)}
                  onSolicitar={salida.solicitar}
                  onCancelar={salida.cancelar}
                  onConfirmar={salida.confirmar}
                  onReintentar={salida.reintentar}
                  onVerificar={salida.verificarEstado}
                />
                <JornadaCorreccionPanel
                  jornada={jornada}
                  fase={correccion.fase}
                  bloqueadaPorOtra={jornadaRetenida(salida.fase) === jornada.id}
                  camionesActivos={camionesActivos}
                  nombreCamion={nombreCamion}
                  hoy={fechaOperativaHoy()}
                  onSolicitar={correccion.solicitar}
                  onCancelar={correccion.cancelar}
                  onConfirmar={correccion.confirmar}
                  onReintentar={correccion.reintentar}
                  onVerificar={correccion.verificarEstado}
                />
              </>
            )
          : undefined
      }
      avisos={
        puedeAdministrar ? (
          <>
            <AvisoSalidaJornada fase={salida.fase} />
            <AvisoSalidaJornada fase={correccion.fase} />
          </>
        ) : undefined
      }
    />
  );
}
