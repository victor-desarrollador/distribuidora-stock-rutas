import { useEffect, useState } from "react";

import { useAuth } from "../auth/useAuth";
import { ROLES_GESTION } from "../auth/roles";
import {
  ConfirmarDescarteBorrador,
  MENSAJE_DESCARTE_CAMBIO_JORNADA,
  MENSAJE_DESCARTE_CANCELAR,
} from "../components/ConfirmarDescarteBorrador";
import { useAperturaJornada } from "../hooks/useAperturaJornada";
import { useAvisoSalidaPagina } from "../hooks/useAvisoSalidaPagina";
import { useBorradorCarga } from "../hooks/borradorCargaContexto";
import { useCatalogoCargaLectura } from "../hooks/useCatalogoCargaLectura";
import { useCatalogoCamiones } from "../hooks/useCatalogoCamiones";
import { useJornadasLectura } from "../hooks/useJornadasLectura";
import { useCorreccionJornada } from "../hooks/useCorreccionJornada";
import { useHistorialJornada } from "../hooks/useHistorialJornada";
import { useSalidaJornada } from "../hooks/useSalidaJornada";
import { useVendedoresJornada } from "../hooks/useVendedoresJornada";
import { AvisoSalidaJornada } from "./AvisoSalidaJornada";
import { JornadaAperturaPanel } from "./JornadaAperturaPanel";
import { JornadaCargaPanel } from "./JornadaCargaPanel";
import { JornadaContinuidadPanel } from "./JornadaContinuidadPanel";
import { JornadaCorreccionPanel } from "./JornadaCorreccionPanel";
import { JornadaHistorialPanel } from "./JornadaHistorialPanel";
import { JornadaSalidaPanel } from "./JornadaSalidaPanel";
import { JornadasVista } from "./JornadasVista";
import { faseConRiesgoApertura } from "./jornadas_apertura";
import { contextoAutorizacionCarga, faseBorradorPara } from "./carga_borrador";
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
// FE-1D: dueño y encargado preparan y revisan un BORRADOR de carga
// (JornadaCargaPanel). Sólo lectura del catálogo de productos; el borrador vive
// en BorradorCargaProvider (sobre el router). La confirmación está
// deshabilitada: la pantalla no recibe ni construye el controlador de carga ni
// su puerto de ejecución (DP-1 abierto).
// FE-1E: si hay un borrador escrito de otra jornada, abrir la carga de esta
// pide confirmar el descarte (ConfirmarDescarteBorrador) y se puede cancelar.
// FE-1F (H-02): «Cancelar» del formulario con algo escrito pide la misma
// confirmación; sin nada escrito cierra directo. (H-01): el catálogo y el
// borrador pertenecen al contexto de autorización vigente.
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
  const { usuario, sesion } = useAuth();
  // Sólo presentación: el acceso lo decide ProtectedRoute; las filas, RLS; y
  // quién puede confirmar la salida, el servidor.
  const puedeAdministrar =
    usuario !== null && ROLES_GESTION.includes(usuario.rol);
  // Historial sólo para gestión: para el vendedor/piloto no se lee nada
  // (RLS tampoco le devolvería movimientos, ADR-007 §2.8).
  const historial = useHistorialJornada(
    puedeAdministrar ? jornadas.estado.seleccionadaId : null
  );
  const borradorCarga = useBorradorCarga();
  // FE-1F (H-01): sólo gestión con autorización verificada lee el catálogo, y
  // lo leído queda atado a ese contexto (usuario + empresa + rol): si cambia,
  // el catálogo anterior se borra y se relee.
  const catalogoCarga = useCatalogoCargaLectura(contextoAutorizacionCarga(sesion));
  const pendienteCarga = borradorCarga.pendiente;

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
                {/* FE-1E: abrir la carga de esta jornada descartaría el
                    borrador escrito de otra: se pregunta antes. */}
                {pendienteCarga?.tipo === "cambiar_jornada" &&
                pendienteCarga.jornadaId === jornada.id ? (
                  <ConfirmarDescarteBorrador
                    id={`descarte-carga-${jornada.id}`}
                    mensaje={MENSAJE_DESCARTE_CAMBIO_JORNADA}
                    textoCancelar="Conservar el borrador"
                    textoAceptar="Descartar y cargar esta jornada"
                    onCancelar={borradorCarga.cancelarDescarte}
                    onAceptar={() => {
                      if (borradorCarga.aceptarDescarte()?.tipo === "cambiar_jornada") {
                        catalogoCarga.recargar();
                      }
                    }}
                  />
                ) : pendienteCarga?.tipo === "cancelar_carga" &&
                  borradorCarga.borrador.jornadaId === jornada.id ? (
                  /* FE-1F (H-02): «Cancelar» con algo escrito. */
                  <ConfirmarDescarteBorrador
                    id={`cancelar-carga-${jornada.id}`}
                    mensaje={MENSAJE_DESCARTE_CANCELAR}
                    textoCancelar="Conservar el borrador"
                    textoAceptar="Descartar el borrador"
                    onCancelar={borradorCarga.cancelarDescarte}
                    onAceptar={() => {
                      borradorCarga.aceptarDescarte();
                    }}
                  />
                ) : (
                /* Sin onConfirmar: «Confirmar carga» deshabilitado (DP-1). */
                <JornadaCargaPanel
                  jornada={jornada}
                  fase={faseBorradorPara(borradorCarga.borrador, jornada)}
                  bloqueadaPorOtra={
                    jornadaRetenida(salida.fase) === jornada.id ||
                    jornadaRetenida(correccion.fase) === jornada.id
                  }
                  catalogo={catalogoCarga.catalogo}
                  nombreCamion={nombreCamion}
                  edicion={borradorCarga.borrador.edicion}
                  onEdicion={borradorCarga.editar}
                  onSolicitar={(j) => {
                    // Con un borrador escrito de otra jornada queda pendiente
                    // de confirmar y todavía no se abre ni se relee nada.
                    if (borradorCarga.iniciar(j.id)) {
                      // El catálogo se relee al abrir el formulario: es el vigente ahora.
                      catalogoCarga.recargar();
                    }
                  }}
                  // Con algo escrito queda pendiente de confirmar (H-02).
                  onCancelar={() => {
                    borradorCarga.pedirCancelacion();
                  }}
                />
                )}
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
