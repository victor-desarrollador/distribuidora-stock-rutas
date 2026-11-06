import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import type { DatosStock } from "../lib/stock";
import { StockVista, type StockVistaProps } from "./StockVista";
import { formularioStockVacio } from "./stock_formulario";

const datos: DatosStock = {
  depositoId: "dep",
  cuarentenaId: "cua",
  ubicaciones: [
    { id: "dep", tipo: "deposito", camionId: null },
    { id: "cua", tipo: "cuarentena", camionId: null },
  ],
  productos: [
    { id: "pu", codigo: null, nombre: "Yogur", formaVenta: "unidad", stockMinimo: 10, activo: true },
    { id: "pp", codigo: null, nombre: "Jamón", formaVenta: "peso", stockMinimo: 2500, activo: true },
  ],
  camiones: [],
  saldos: [
    { ubicacionId: "dep", productoId: "pu", cantidad: 40 },
    { ubicacionId: "dep", productoId: "pp", cantidad: 12500 },
  ],
};

const noop = () => undefined;
function vista(p: Partial<StockVistaProps>): string {
  return renderToStaticMarkup(
    <StockVista
      lectura={{ estado: "listo", datos }}
      formulario={formularioStockVacio()}
      enviando={false}
      error={null}
      mensaje={null}
      onCambiarFormulario={noop}
      onEnviar={noop}
      onRecargar={noop}
      {...p}
    />
  );
}

describe("StockVista", () => {
  it("cargando: muestra el estado y no ofrece operaciones", () => {
    const html = vista({ lectura: { estado: "cargando" } });
    expect(html).toContain("Cargando stock");
    expect(html).not.toContain("Registrar operación de stock");
  });

  it("error de lectura: alerta con reintento y sin datos viejos", () => {
    const html = vista({ lectura: { estado: "error", error: "No se pudo leer el stock. Intentá de nuevo." } });
    expect(html).toContain('role="alert"');
    expect(html).toContain("Reintentar");
    expect(html).not.toContain("Yogur");
    expect(html).not.toContain("Registrar operación de stock");
  });

  it("listo: muestra saldos en unidades y kg con 3 decimales", () => {
    const html = vista({});
    expect(html).toContain("Yogur");
    expect(html).toContain("40 un.");
    expect(html).toContain("12,500 kg");
  });

  it("sin productos con stock: mensaje vacío", () => {
    const html = vista({ lectura: { estado: "listo", datos: { ...datos, productos: [], saldos: [] } } });
    expect(html).toContain("Todavía no hay productos con stock");
  });

  it("responsive: tabla en PC y tarjetas en móvil", () => {
    const html = vista({});
    expect(html).toContain("hidden overflow-x-auto md:block");
    expect(html).toContain("md:hidden");
    expect(html).toContain("min-h-11");
  });

  it("enviando: bloquea los controles y cambia el texto del botón", () => {
    const html = vista({ enviando: true });
    expect(html).toContain("Registrando…");
    expect(html).toMatch(/<button[^>]*type="submit"[^>]*disabled/);
    expect(html).toMatch(/<select[^>]*disabled/);
  });

  it("muestra error de operación y confirmación", () => {
    expect(vista({ error: "No hay stock suficiente en el depósito." })).toContain("No hay stock suficiente");
    expect(vista({ mensaje: "Ingreso registrado." })).toContain('role="status"');
  });

  it("merma muestra el selector de motivos; ingreso no", () => {
    expect(vista({ formulario: formularioStockVacio("merma") })).toContain("Motivo de la merma");
    expect(vista({})).not.toContain("Motivo de la merma");
  });

  it("cuarentena indica el depósito disponible del producto elegido", () => {
    const html = vista({ formulario: { ...formularioStockVacio("cuarentena"), productoId: "pp" } });
    expect(html).toContain("Disponible en depósito");
    expect(html).toContain("12,500 kg");
  });
});
