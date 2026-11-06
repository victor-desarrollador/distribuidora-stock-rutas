import { AlertTriangle, CheckCircle2, Warehouse } from "lucide-react";
import type { FormEvent } from "react";

import { MOTIVOS_MERMA } from "../lib/stock";
import type { DatosStock } from "../lib/stock";
import type { EstadoLecturaStock } from "./stock_controlador";
import {
  ETIQUETA_MOTIVO_MERMA,
  ETIQUETA_OPERACION,
  armarFilasStock,
  formatearCantidad,
  saldoDeposito,
  textoUnidadEntrada,
  type FormularioStock,
  type TipoOperacionStock,
} from "./stock_formulario";

// Vista presentacional de la pantalla de stock real (B-01). Sin estado ni
// efectos: todo llega por props, así se prueba con renderToStaticMarkup.

export interface StockVistaProps {
  lectura: EstadoLecturaStock;
  formulario: FormularioStock;
  enviando: boolean;
  error: string | null;
  mensaje: string | null;
  onCambiarFormulario: (formulario: FormularioStock) => void;
  onEnviar: () => void;
  onRecargar: () => void;
}

const TIPOS: TipoOperacionStock[] = ["ingreso", "cuarentena", "merma"];

const CLASE_CAMPO = "w-full rounded-lg border border-slate-300 p-3";

function TablaStock({ datos }: { datos: DatosStock }) {
  const filas = armarFilasStock(datos);

  if (filas.length === 0) {
    return (
      <p className="p-8 text-center text-slate-500">
        Todavía no hay productos con stock. Registrá un ingreso para empezar.
      </p>
    );
  }

  return (
    <>
      {/* PC: tabla */}
      <div className="hidden overflow-x-auto md:block">
        <table className="w-full min-w-[720px] text-left">
          <thead className="bg-slate-50 text-sm text-slate-500">
            <tr>
              <th className="px-5 py-4">Producto</th>
              <th className="px-5 py-4 text-right">Depósito</th>
              <th className="px-5 py-4 text-right">Cuarentena</th>
              <th className="px-5 py-4 text-right">En camiones</th>
              <th className="px-5 py-4 text-right">Total</th>
              <th className="px-5 py-4 text-right">Stock mínimo</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {filas.map((f) => {
              const forma = f.producto.formaVenta;
              return (
                <tr key={f.producto.id} className="hover:bg-slate-50">
                  <td className="px-5 py-4 font-medium text-slate-800">
                    {f.producto.nombre}
                    {!f.producto.activo && (
                      <span className="ml-2 rounded-full bg-slate-200 px-2 py-0.5 text-xs text-slate-600">
                        Inactivo
                      </span>
                    )}
                  </td>
                  <td className="px-5 py-4 text-right">
                    {formatearCantidad(f.deposito, forma)}
                  </td>
                  <td className="px-5 py-4 text-right">
                    {formatearCantidad(f.cuarentena, forma)}
                  </td>
                  <td className="px-5 py-4 text-right">
                    {formatearCantidad(f.camiones, forma)}
                  </td>
                  <td className="px-5 py-4 text-right font-semibold">
                    {formatearCantidad(f.total, forma)}
                  </td>
                  <td className="px-5 py-4 text-right text-slate-500">
                    {formatearCantidad(f.producto.stockMinimo, forma)}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Android: tarjetas */}
      <ul className="divide-y divide-slate-100 md:hidden">
        {filas.map((f) => {
          const forma = f.producto.formaVenta;
          return (
            <li key={f.producto.id} className="space-y-2 p-4">
              <p className="font-medium text-slate-800">
                {f.producto.nombre}
                {!f.producto.activo && (
                  <span className="ml-2 rounded-full bg-slate-200 px-2 py-0.5 text-xs text-slate-600">
                    Inactivo
                  </span>
                )}
              </p>
              <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
                <dt className="text-slate-500">Depósito</dt>
                <dd className="text-right">{formatearCantidad(f.deposito, forma)}</dd>
                <dt className="text-slate-500">Cuarentena</dt>
                <dd className="text-right">{formatearCantidad(f.cuarentena, forma)}</dd>
                <dt className="text-slate-500">En camiones</dt>
                <dd className="text-right">{formatearCantidad(f.camiones, forma)}</dd>
                <dt className="font-semibold text-slate-700">Total</dt>
                <dd className="text-right font-semibold">
                  {formatearCantidad(f.total, forma)}
                </dd>
              </dl>
            </li>
          );
        })}
      </ul>
    </>
  );
}

function PanelOperacion({
  datos,
  formulario,
  enviando,
  onCambiarFormulario,
  onEnviar,
}: {
  datos: DatosStock;
  formulario: FormularioStock;
  enviando: boolean;
  onCambiarFormulario: (formulario: FormularioStock) => void;
  onEnviar: () => void;
}) {
  const productos = datos.productos
    .filter((p) => p.activo)
    .sort((a, b) => a.nombre.localeCompare(b.nombre, "es-AR"));
  const producto = datos.productos.find((p) => p.id === formulario.productoId);
  const desdeDeposito = formulario.tipo !== "ingreso";

  function enviar(evento: FormEvent) {
    evento.preventDefault();
    onEnviar();
  }

  return (
    <form
      onSubmit={enviar}
      aria-label="Registrar operación de stock"
      className="space-y-5 rounded-xl border border-slate-200 bg-white p-4 shadow-sm md:p-6"
    >
      <div role="group" aria-label="Tipo de operación" className="flex flex-wrap gap-2">
        {TIPOS.map((tipo) => (
          <button
            key={tipo}
            type="button"
            aria-pressed={formulario.tipo === tipo}
            disabled={enviando}
            onClick={() =>
              // Cambiar de operación conserva el producto y limpia el resto.
              onCambiarFormulario({
                ...formulario,
                tipo,
                cantidad: "",
                motivo: "",
                motivoCodigo: "",
              })
            }
            className={`min-h-11 flex-1 rounded-lg border px-4 py-2 font-medium disabled:opacity-60 md:flex-none ${
              formulario.tipo === tipo
                ? "border-blue-600 bg-blue-600 text-white"
                : "border-slate-300 hover:bg-slate-50"
            }`}
          >
            {ETIQUETA_OPERACION[tipo]}
          </button>
        ))}
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <label className="space-y-1 text-sm font-medium">
          <span>Producto</span>
          <select
            value={formulario.productoId}
            disabled={enviando}
            onChange={(e) =>
              onCambiarFormulario({
                ...formulario,
                productoId: e.target.value,
                cantidad: "",
              })
            }
            className={CLASE_CAMPO}
          >
            <option value="">Elegí un producto</option>
            {productos.map((p) => (
              <option key={p.id} value={p.id}>
                {p.nombre}
              </option>
            ))}
          </select>
        </label>

        <label className="space-y-1 text-sm font-medium">
          <span>
            Cantidad {producto ? `(${textoUnidadEntrada(producto.formaVenta)})` : ""}
          </span>
          <input
            type="text"
            inputMode={producto?.formaVenta === "peso" ? "decimal" : "numeric"}
            autoComplete="off"
            value={formulario.cantidad}
            disabled={enviando}
            onChange={(e) =>
              onCambiarFormulario({ ...formulario, cantidad: e.target.value })
            }
            className={CLASE_CAMPO}
            placeholder={producto?.formaVenta === "peso" ? "Ej: 2,500" : "Ej: 12"}
          />
          {desdeDeposito && producto && (
            <p className="text-xs font-normal text-slate-500">
              Disponible en depósito:{" "}
              {formatearCantidad(
                saldoDeposito(datos, producto.id),
                producto.formaVenta
              )}
              . Sale siempre del depósito.
            </p>
          )}
        </label>

        {formulario.tipo === "merma" && (
          <label className="space-y-1 text-sm font-medium">
            <span>Motivo de la merma</span>
            <select
              value={formulario.motivoCodigo}
              disabled={enviando}
              onChange={(e) =>
                onCambiarFormulario({ ...formulario, motivoCodigo: e.target.value })
              }
              className={CLASE_CAMPO}
            >
              <option value="">Elegí un motivo</option>
              {MOTIVOS_MERMA.map((codigo) => (
                <option key={codigo} value={codigo}>
                  {ETIQUETA_MOTIVO_MERMA[codigo]}
                </option>
              ))}
            </select>
          </label>
        )}

        <label className="space-y-1 text-sm font-medium md:col-span-2">
          <span>
            {formulario.tipo === "cuarentena"
              ? "Motivo (obligatorio)"
              : formulario.tipo === "merma"
                ? "Detalle (obligatorio si el motivo es «Otro»)"
                : "Motivo (opcional)"}
          </span>
          <input
            type="text"
            value={formulario.motivo}
            disabled={enviando}
            maxLength={500}
            onChange={(e) =>
              onCambiarFormulario({ ...formulario, motivo: e.target.value })
            }
            className={CLASE_CAMPO}
          />
        </label>
      </div>

      <button
        type="submit"
        disabled={enviando}
        className="min-h-11 w-full rounded-lg bg-blue-600 px-5 py-3 font-medium text-white hover:bg-blue-700 disabled:opacity-60 md:w-auto"
      >
        {enviando ? "Registrando…" : `Registrar ${ETIQUETA_OPERACION[formulario.tipo].toLowerCase()}`}
      </button>
    </form>
  );
}

export function StockVista(props: StockVistaProps) {
  const { lectura, error, mensaje } = props;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="flex items-center gap-3 text-3xl font-bold text-slate-800">
          <Warehouse size={28} className="text-blue-600" />
          Stock
        </h1>
        <p className="mt-1 text-slate-500">
          Saldo por ubicación, calculado por la base a partir de los movimientos.
        </p>
      </div>

      {lectura.estado === "error" && (
        <div
          role="alert"
          className="flex flex-wrap items-center gap-3 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800"
        >
          <AlertTriangle size={20} />
          <span>{lectura.error}</span>
          <button
            type="button"
            onClick={props.onRecargar}
            className="min-h-11 rounded-lg border border-red-300 px-4 hover:bg-red-100"
          >
            Reintentar
          </button>
        </div>
      )}

      {error && (
        <div
          role="alert"
          className="flex items-center gap-3 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800"
        >
          <AlertTriangle size={20} />
          {error}
        </div>
      )}

      {mensaje && (
        <div
          role="status"
          className="flex items-center gap-3 rounded-lg border border-green-200 bg-green-50 p-4 text-sm text-green-800"
        >
          <CheckCircle2 size={20} />
          {mensaje}
        </div>
      )}

      {lectura.estado === "listo" && (
        <PanelOperacion
          datos={lectura.datos}
          formulario={props.formulario}
          enviando={props.enviando}
          onCambiarFormulario={props.onCambiarFormulario}
          onEnviar={props.onEnviar}
        />
      )}

      <div className="rounded-xl border border-slate-200 bg-white shadow-sm">
        {lectura.estado === "cargando" && (
          <p role="status" className="p-8 text-center text-slate-500">
            Cargando stock…
          </p>
        )}
        {lectura.estado === "listo" && <TablaStock datos={lectura.datos} />}
      </div>

      <p className="text-sm text-slate-500">
        El stock se modifica sólo con ingresos, pasos a cuarentena y mermas
        registrados en la base; esta pantalla nunca edita saldos. Cuarentena y
        merma salen siempre del depósito. Las demás pantallas operativas siguen
        con datos de demostración de este navegador.
      </p>
    </div>
  );
}
