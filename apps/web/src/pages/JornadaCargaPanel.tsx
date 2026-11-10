import type { ReactNode } from "react";
import { AlertTriangle, ClipboardCheck, Loader2, PackagePlus, Plus, Trash2 } from "lucide-react";

import type { Jornada } from "../lib/jornadas";
import {
  agregarLinea,
  cambiarProducto,
  cambiarTexto,
  entradaDe,
  errorEdicion,
  productosParaLinea,
  quitarLinea,
  revisar,
  volverAEditar,
  type EdicionCarga,
} from "./carga_edicion";
import {
  jornadaCargable,
  resumenCarga,
  validarCarga,
  type EntradaCarga,
  type FaseCarga,
  type ProductoCarga,
} from "./jornadas_carga";
import { ETIQUETA_ESTADO_JORNADA } from "./jornadas_presentacion";

// Panel de «Cargar mercadería» (FE-1B) dentro del detalle de la jornada.
// Presentacional y CONTROLADO: la fase llega del controlador FE-1 y lo escrito
// (`edicion`) de afuera, porque la relectura de la lista desmonta el detalle
// (J-9). No llama RPC, no genera claves y no guarda nada en el navegador.
//
// FE-1D: montado en `Jornadas.tsx` SÓLO para preparar y revisar un borrador.
// Sin `onConfirmar`, «Confirmar carga» queda deshabilitado (sin manejador) y se
// explica por qué: DP-1 (doble carga tras perder la clave) sigue abierta. El
// éxito o el rechazo los anunciaría el aviso de la pantalla, como en los demás
// paneles; este panel nunca afirma que el stock cambió.

export const MENSAJE_CONFIRMACION_DESHABILITADA =
  "La confirmación de carga está temporalmente deshabilitada. Podés preparar y revisar este borrador, pero todavía no se registra ninguna carga ni se mueve stock.";
export const MENSAJE_BORRADOR_VOLATIL =
  "El borrador no se guarda: se pierde al recargar o cerrar la página, al cerrar sesión o al cambiar de usuario.";

export interface JornadaCargaPanelProps {
  jornada: Jornada;
  fase: FaseCarga;
  // Otra operación retiene esta jornada. Sólo presentación: la exclusión
  // efectiva la aplica el motor (árbitro).
  bloqueadaPorOtra?: boolean;
  // Productos del catálogo, null si no se pudo leer o "cargando".
  catalogo: readonly ProductoCarga[] | null | "cargando";
  nombreCamion: (camionId: string) => string;
  edicion: EdicionCarga;
  onEdicion: (edicion: EdicionCarga) => void;
  onSolicitar: (jornada: Jornada) => void;
  onCancelar: () => void;
  // Sin `onConfirmar` la confirmación queda deshabilitada (modo borrador,
  // FE-1D). Sin `onReintentar`/`onVerificar` esos botones no se ofrecen.
  onConfirmar?: (entrada: EntradaCarga) => void;
  onReintentar?: () => void;
  onVerificar?: () => void;
}

const BOTON =
  "flex min-h-12 items-center justify-center gap-2 rounded-lg px-5 font-semibold disabled:cursor-not-allowed disabled:opacity-60";
const CAMPO = "min-h-12 w-full rounded-lg border bg-white px-3 text-base";
const CAMPO_OK = `${CAMPO} border-slate-300`;
const CAMPO_ERROR = `${CAMPO} border-red-500`;

function BotonDeshabilitado({ id, razon }: { id: string; razon: string }) {
  return (
    <div className="mt-4 space-y-1">
      <button type="button" disabled aria-describedby={id} className={`${BOTON} bg-slate-200 text-slate-500`}>
        Cargar mercadería
      </button>
      <p id={id} className="text-xs text-slate-500">
        {razon}
      </p>
    </div>
  );
}

export function JornadaCargaPanel(props: JornadaCargaPanelProps) {
  const { jornada, fase, bloqueadaPorOtra = false, onSolicitar, onReintentar, onVerificar } = props;
  const propia = fase.fase !== "inactiva" && fase.jornadaId === jornada.id ? fase : null;
  const idAyuda = `carga-ayuda-${jornada.id}`;

  if (propia?.fase === "confirmando") {
    return <FormularioCarga {...props} errorServidor={propia.error} />;
  }

  if (propia?.fase === "enviando" || propia?.fase === "verificando") {
    return (
      <div className="mt-4 space-y-2">
        <button type="button" disabled aria-disabled="true" className={`${BOTON} bg-slate-200 text-slate-600`}>
          <Loader2 size={18} className="animate-spin" aria-hidden="true" />
          {propia.fase === "enviando" ? "Registrando carga…" : "Consultando estado…"}
        </button>
        <p role="status" className="text-sm text-slate-600">
          {propia.fase === "enviando"
            ? "Enviando la carga. No cierres, no recargues y no cambies de sección."
            : "No se recibió la respuesta. Consultando el estado real de la jornada…"}
        </p>
      </div>
    );
  }

  if (propia?.fase === "desconocido") {
    return (
      <div role="alert" className="mt-4 space-y-3 rounded-xl bg-amber-50 p-4 text-amber-900">
        <p className="flex items-start gap-2">
          <AlertTriangle size={20} className="mt-0.5 shrink-0" aria-hidden="true" />
          <span>{propia.mensaje}</span>
        </p>
        <div className="flex flex-col gap-3 sm:flex-row">
          {propia.reintentable && onReintentar && (
            <button type="button" onClick={onReintentar} className={`${BOTON} bg-amber-600 text-white`}>
              Reintentar la misma carga
            </button>
          )}
          {onVerificar && (
            <button type="button" onClick={onVerificar} className={`${BOTON} border border-amber-400 text-amber-900`}>
              Verificar estado
            </button>
          )}
        </div>
      </div>
    );
  }

  // Tras un éxito no se ofrece otra carga hasta releer la lista (E8): una
  // nueva carga es otra intención, con otra clave, y no debe partir de datos viejos.
  if (propia?.fase === "exito" && propia.releida !== true) return null;

  if (bloqueadaPorOtra) {
    return (
      <BotonDeshabilitado
        id={idAyuda}
        razon="Hay otra operación de esta jornada en curso o sin resolver. Terminala o verificá su estado antes de cargar."
      />
    );
  }

  if (fase.fase === "desconocido" && fase.jornadaId !== jornada.id) {
    return (
      <BotonDeshabilitado
        id={idAyuda}
        razon="Hay una carga de otra jornada sin resolver. Abrí esa jornada y verificá su estado antes de cargar otra."
      />
    );
  }

  if (!jornadaCargable(jornada)) {
    return (
      <BotonDeshabilitado
        id={idAyuda}
        razon={`Sólo se puede cargar una jornada abierta o cargada (estado actual: ${ETIQUETA_ESTADO_JORNADA[jornada.estado]}).`}
      />
    );
  }

  return (
    <div className="mt-4">
      <button
        type="button"
        onClick={() => onSolicitar(jornada)}
        className={`${BOTON} border border-blue-600 text-blue-700`}
      >
        <PackagePlus size={18} aria-hidden="true" />
        Cargar mercadería
      </button>
    </div>
  );
}

function FormularioCarga(props: JornadaCargaPanelProps & { errorServidor?: string }) {
  const { jornada, catalogo, nombreCamion, edicion, onEdicion, onCancelar, onConfirmar, errorServidor } = props;
  const base = `carga-${jornada.id}`;

  if (catalogo === "cargando") {
    return (
      <div className="mt-4 space-y-3 rounded-xl border border-blue-200 bg-blue-50 p-4">
        <p role="status" className="flex items-center gap-2 text-sm text-slate-700">
          <Loader2 size={18} className="animate-spin" aria-hidden="true" />
          <span>Leyendo el catálogo de productos…</span>
        </p>
        <button type="button" onClick={onCancelar} className={`${BOTON} border border-slate-300 text-slate-700`}>
          Cancelar
        </button>
      </div>
    );
  }

  if (catalogo === null) {
    return (
      <div className="mt-4 space-y-3 rounded-xl border border-red-200 bg-red-50 p-4">
        <p role="alert" className="flex items-start gap-2 text-sm text-red-700">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" aria-hidden="true" />
          <span>No se pudo leer el catálogo de productos. Volvé a intentarlo más tarde.</span>
        </p>
        <button type="button" onClick={onCancelar} className={`${BOTON} border border-slate-300 text-slate-700`}>
          Cancelar
        </button>
      </div>
    );
  }

  const encabezado = (
    <>
      <p id={`${base}-titulo`} className="font-semibold text-slate-800">
        Cargar mercadería
      </p>
      <p className="text-sm text-slate-600">
        Camión: <span className="font-medium">{nombreCamion(jornada.camionId)}</span>. Sale del
        depósito hacia el camión de esta jornada.
      </p>
      {onConfirmar === undefined && (
        <p
          id={`${base}-deshabilitada`}
          role="note"
          className="flex items-start gap-2 rounded-lg bg-amber-50 p-3 text-sm text-amber-900"
        >
          <AlertTriangle size={18} className="mt-0.5 shrink-0" aria-hidden="true" />
          <span>
            {MENSAJE_CONFIRMACION_DESHABILITADA} {MENSAJE_BORRADOR_VOLATIL}
          </span>
        </p>
      )}
    </>
  );

  // El resumen se recalcula desde lo escrito: si el catálogo cambió y ya no
  // valida, se vuelve a la edición con el error a la vista.
  const validacion = validarCarga(entradaDe(edicion), catalogo);
  if (edicion.revisando && validacion.ok) {
    return (
      <ResumenCarga
        base={base}
        encabezado={encabezado}
        filas={resumenCarga(validacion.lineas, catalogo)}
        errorServidor={errorServidor}
        onConfirmar={onConfirmar ? () => onConfirmar(entradaDe(edicion)) : undefined}
        idDeshabilitada={`${base}-deshabilitada`}
        onEditar={() => onEdicion(volverAEditar(edicion))}
        onCancelar={onCancelar}
      />
    );
  }

  const error = edicion.mostrarErrores ? errorEdicion(edicion, catalogo) : null;
  const idError = `${base}-error`;
  const porId = new Map(catalogo.map((p) => [p.id.toLowerCase(), p]));

  return (
    <form
      noValidate
      aria-labelledby={`${base}-titulo`}
      onSubmit={(e) => {
        e.preventDefault();
        onEdicion(revisar(edicion, catalogo));
      }}
      className="mt-4 space-y-4 rounded-xl border border-blue-200 bg-blue-50 p-4"
    >
      {encabezado}

      <ol className="space-y-3" aria-label="Productos a cargar">
        {edicion.lineas.map((linea, i) => {
          const n = i + 1;
          const producto = porId.get(linea.productoId.toLowerCase());
          const peso = producto?.formaVenta === "peso";
          const invalida = error !== null && error.linea === i;
          const idProducto = `${base}-producto-${i}`;
          const idCantidad = `${base}-cantidad-${i}`;
          const idUnidad = `${base}-unidad-${i}`;
          return (
            <li
              key={i}
              className="grid grid-cols-1 gap-2 rounded-lg border border-slate-200 bg-white p-3 sm:grid-cols-[minmax(0,1fr)_11rem_auto] sm:items-end"
            >
              <div className="space-y-1">
                <label htmlFor={idProducto} className="block text-sm font-medium text-slate-700">
                  Producto {n}
                </label>
                <select
                  id={idProducto}
                  value={linea.productoId}
                  onChange={(e) => onEdicion(cambiarProducto(edicion, i, e.target.value))}
                  aria-invalid={invalida || undefined}
                  aria-describedby={invalida ? idError : undefined}
                  className={invalida ? CAMPO_ERROR : CAMPO_OK}
                >
                  <option value="">Elegí un producto</option>
                  {productosParaLinea(edicion, i, catalogo).map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.codigo ? `${p.nombre} (${p.codigo})` : p.nombre} · {p.formaVenta === "peso" ? "por kg" : "por unidad"}
                    </option>
                  ))}
                </select>
              </div>

              <div className="space-y-1">
                <label htmlFor={idCantidad} className="block text-sm font-medium text-slate-700">
                  {peso ? `Peso en kg ${n}` : `Cantidad ${n}`}
                </label>
                <input
                  id={idCantidad}
                  type="text"
                  inputMode={peso ? "decimal" : "numeric"}
                  autoComplete="off"
                  disabled={producto === undefined}
                  value={linea.texto}
                  placeholder={peso ? "Ej.: 1,250" : "Ej.: 24"}
                  onChange={(e) => onEdicion(cambiarTexto(edicion, i, e.target.value))}
                  aria-invalid={invalida || undefined}
                  aria-describedby={invalida ? `${idUnidad} ${idError}` : idUnidad}
                  className={invalida ? CAMPO_ERROR : CAMPO_OK}
                />
                <p id={idUnidad} className="text-xs text-slate-500">
                  {producto === undefined
                    ? "Elegí primero el producto."
                    : peso
                      ? "Kilogramos con coma, hasta 3 decimales."
                      : "Unidades enteras."}
                </p>
              </div>

              <button
                type="button"
                onClick={() => onEdicion(quitarLinea(edicion, i))}
                aria-label={`Quitar producto ${n}`}
                className={`${BOTON} border border-slate-300 px-3 text-slate-600`}
              >
                <Trash2 size={18} aria-hidden="true" />
                <span className="sm:hidden">Quitar</span>
              </button>
            </li>
          );
        })}
      </ol>

      <button
        type="button"
        onClick={() => onEdicion(agregarLinea(edicion))}
        className={`${BOTON} w-full border border-dashed border-blue-400 text-blue-700 sm:w-auto`}
      >
        <Plus size={18} aria-hidden="true" />
        Agregar producto
      </button>

      {(error || errorServidor) && (
        <p id={idError} role="alert" className="flex items-start gap-2 text-sm text-red-700">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" aria-hidden="true" />
          <span>{error?.mensaje ?? errorServidor}</span>
        </p>
      )}

      <div className="flex flex-col gap-3 sm:flex-row">
        <button type="submit" className={`${BOTON} bg-blue-600 text-white`}>
          <ClipboardCheck size={18} aria-hidden="true" />
          Revisar carga
        </button>
        <button type="button" onClick={onCancelar} className={`${BOTON} border border-slate-300 text-slate-700`}>
          Cancelar
        </button>
      </div>
    </form>
  );
}

function ResumenCarga({
  base,
  encabezado,
  filas,
  errorServidor,
  onConfirmar,
  idDeshabilitada,
  onEditar,
  onCancelar,
}: {
  base: string;
  encabezado: ReactNode;
  filas: ReturnType<typeof resumenCarga>;
  errorServidor?: string;
  // Sin manejador: botón deshabilitado y SIN onClick (no hay nada que invocar).
  onConfirmar?: () => void;
  idDeshabilitada: string;
  onEditar: () => void;
  onCancelar: () => void;
}) {
  return (
    <section
      aria-labelledby={`${base}-titulo`}
      className="mt-4 space-y-4 rounded-xl border border-blue-200 bg-blue-50 p-4"
    >
      {encabezado}
      <table className="w-full table-fixed border-collapse text-sm">
        <caption className="pb-2 text-left font-medium text-slate-700">
          Revisá la carga antes de confirmarla ({filas.length} {filas.length === 1 ? "producto" : "productos"})
        </caption>
        <thead>
          <tr className="border-b border-slate-300 text-left text-slate-600">
            <th scope="col" className="py-2 pr-2">Producto</th>
            <th scope="col" className="w-32 py-2 text-right">Cantidad</th>
          </tr>
        </thead>
        <tbody>
          {filas.map((f) => (
            <tr key={f.productoId} className="border-b border-slate-200">
              <td className="break-words py-2 pr-2">{f.producto}</td>
              <td className="py-2 text-right font-mono tabular-nums">{f.cantidad}</td>
            </tr>
          ))}
        </tbody>
      </table>

      {errorServidor && (
        <p role="alert" className="flex items-start gap-2 text-sm text-red-700">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" aria-hidden="true" />
          <span>{errorServidor}</span>
        </p>
      )}

      <div className="flex flex-col gap-3 sm:flex-row">
        {onConfirmar ? (
          <button type="button" onClick={onConfirmar} className={`${BOTON} bg-blue-600 text-white`}>
            <PackagePlus size={18} aria-hidden="true" />
            Confirmar carga
          </button>
        ) : (
          <button
            type="button"
            disabled
            aria-disabled="true"
            aria-describedby={idDeshabilitada}
            className={`${BOTON} bg-slate-200 text-slate-500`}
          >
            <PackagePlus size={18} aria-hidden="true" />
            Confirmar carga
          </button>
        )}
        <button type="button" onClick={onEditar} className={`${BOTON} border border-slate-300 text-slate-700`}>
          Volver a editar
        </button>
        <button type="button" onClick={onCancelar} className={`${BOTON} border border-slate-300 text-slate-700`}>
          Cancelar
        </button>
      </div>
    </section>
  );
}
