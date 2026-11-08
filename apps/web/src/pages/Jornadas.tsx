import { useEffect, useState } from "react";

import { useAuth } from "../auth/useAuth";
import { ROLES_GESTION } from "../auth/roles";
import { useAperturaJornada } from "../hooks/useAperturaJornada";
import { useAvisoSalidaPagina } from "../hooks/useAvisoSalidaPagina";
import { useCatalogoCamiones } from "../hooks/useCatalogoCamiones";
import { useJornadasLectura } from "../hooks/useJornadasLectura";
import { useCorreccionJornada } from "../hooks/useCorreccionJornada";
import { useHistorialJornada } from "../hooks/useHistorialJornada";
import { useSalidaJornada } from "../hooks/useSalidaJornada";
import { useVendedoresJornada } from "../hooks/useVendedoresJornada";
import { AvisoSalidaJornada } from "./AvisoSalidaJornada";
import { JornadaAperturaPanel } from "./JornadaAperturaPanel";
import { JornadaContinuidadPanel } from "./JornadaContinuidadPanel";
import { JornadaCorreccionPanel } from "./JornadaCorreccionPanel";
import { JornadaHistorialPanel } from "./JornadaHistorialPanel";
import { JornadaSalidaPanel } from "./JornadaSalidaPanel";
import { JornadasVista } from "./JornadasVista";
import { faseConRiesgoApertura } from "./jornadas_apertura";
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
// otra no puede iniciarse sobre esa jornada (S2 M-02). Reasignar, cargar y
// descargar siguen sin habilitarse.
// B-02b.2 / S3-0: dueño y encargado ven, en el detalle, el historial de cargas
// y descargas registradas (SÓLO LECTURA; hooks/useHistorialJornada.ts,
// pages/jornadas_historial.ts). No participa del árbitro: no opera.
// B-02b.2 / S3-1: estado de cierre y bloqueos de continuidad (SÓLO LECTURA,
// pages/jornadas_continuidad.ts), derivado de la jornada y del mismo historial:
// no hace lecturas propias.
// D-B2-1: dueño y encargado abren una jornada real (camión activo, fecha
// operativa y vendedor de la lista real de `listar_vendedores_jornada`) con el
// controlador independiente pages/jornadas_apertura.ts. No participa del
// árbitro: la apertura no retiene ninguna jornada existente.
// T-1: mientras la apertura envía, consulta o tiene resultado desconocido, se
// pide al navegador confirmar la salida (puede no mostrarlo). T-2: ante
// `jornada_duplicada` o `jornada_vendedor_ocupado`, el panel orienta a revisar
// las jornadas de la fecha; esa lectura nunca confirma la apertura.
export default function Jornadas() {
  const jornadas = useJornadasLectura();
  // Un árbitro por montaje de la pantalla, compartido por ambas operaciones.
  const [arbitro] = useState(crearArbitroJornadas);
  const salida = useSalidaJornada(jornadas.recargar, arbitro);
  const correccion = useCorreccionJornada(jornadas.recargar, arbitro);
  const vendedores = useVendedoresJornada();
  const apertura = useAperturaJornada(jornadas.recargar, vendedores.recargar);
  const { trasRelectura } = correccion;
  const { trasRelectura: trasRelecturaApertura } = apertura;
  useAvisoSalidaPagina(faseConRiesgoApertura(apertura.fase));
  const lectura = jornadas.estado.lectura;
  // Cada lectura completa (`listo`) llega en un objeto nuevo y la generación de
  // la lectura descarta respuestas viejas: tras un éxito, el primer `listo` es
  // de la relectura posterior. Sólo libera una NUEVA corrección o apertura; no relee.
  useEffect(() => {
    if (lectura.estado === "listo") {
      trasRelectura();
      trasRelecturaApertura();
    }
  }, [lectura, trasRelectura, trasRelecturaApertura]);
  const { catalogo } = useCatalogoCamiones();
  const { usuario } = useAuth();
  // Sólo presentación: el acceso lo decide ProtectedRoute; las filas, RLS; y
  // quién puede confirmar la salida, el servidor.
  const puedeAdministrar =
    usuario !== null && ROLES_GESTION.includes(usuario.rol);
  // Historial sólo para gestión: para el vendedor/piloto no se lee nada
  // (RLS tampoco le devolvería movimientos, ADR-007 §2.8).
  const historial = useHistorialJornada(
    puedeAdministrar ? jornadas.estado.seleccionadaId : null
  );

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
                <JornadaContinuidadPanel
                  jornada={jornada}
                  historial={historial.estado}
                  nombreCamion={nombreCamion(jornada.camionId)}
                />
                <JornadaHistorialPanel
                  jornada={jornada}
                  estado={historial.estado}
                  usuarioId={usuario?.usuarioId ?? null}
                  onActualizar={historial.actualizar}
                />
              </>
            )
          : undefined
      }
      apertura={
        puedeAdministrar ? (
          <JornadaAperturaPanel
            fase={apertura.fase}
            camionesActivos={camionesActivos}
            vendedores={vendedores.estado}
            hoy={fechaOperativaHoy()}
            nombreCamion={nombreCamion}
            onSolicitar={() => {
              apertura.solicitar();
              // La lista se lee al abrir el formulario: es la vigente ahora.
              vendedores.recargar();
            }}
            onCancelar={apertura.cancelar}
            onConfirmar={apertura.confirmar}
            onReintentar={apertura.reintentar}
            onRecargarVendedores={vendedores.recargar}
            onVerFecha={jornadas.cambiarFecha}
          />
        ) : undefined
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
