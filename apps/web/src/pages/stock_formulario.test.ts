import { describe, expect, it } from "vitest";

import type { DatosStock } from "../lib/stock";
import {
  armarFilasStock,
  cantidadDesdeTexto,
  crearGestorIntentos,
  crearGuardaEnVuelo,
  EN_CURSO,
  firmaIntento,
  formatearCantidad,
  formularioStockVacio,
  generarClaveNavegador,
  saldoDeposito,
  validarFormularioStock,
  type FormularioStock,
} from "./stock_formulario";

const datos: DatosStock = {
  depositoId: "dep",
  cuarentenaId: "cua",
  ubicaciones: [
    { id: "dep", tipo: "deposito", camionId: null },
    { id: "cua", tipo: "cuarentena", camionId: null },
    { id: "cam", tipo: "camion", camionId: "c1" },
  ],
  productos: [
    { id: "pu", codigo: null, nombre: "Yogur", formaVenta: "unidad", stockMinimo: 10, activo: true },
    { id: "pp", codigo: null, nombre: "Jamón", formaVenta: "peso", stockMinimo: 2500, activo: true },
    { id: "pi", codigo: null, nombre: "Antiguo", formaVenta: "unidad", stockMinimo: 0, activo: false },
    { id: "pj", codigo: null, nombre: "Baja con stock", formaVenta: "unidad", stockMinimo: 0, activo: false },
  ],
  saldos: [
    { ubicacionId: "dep", productoId: "pu", cantidad: 40 },
    { ubicacionId: "cua", productoId: "pu", cantidad: 2 },
    { ubicacionId: "cam", productoId: "pu", cantidad: 8 },
    { ubicacionId: "dep", productoId: "pp", cantidad: 12500 },
    { ubicacionId: "dep", productoId: "pj", cantidad: 3 },
  ],
};

const form = (p: Partial<FormularioStock>): FormularioStock => ({ ...formularioStockVacio("ingreso"), ...p });

describe("cantidadDesdeTexto", () => {
  it.each([
    ["12", "unidad", 12],
    [" 7 ", "unidad", 7],
    ["1,250", "peso", 1250],
    ["2", "peso", 2000],
    ["0,001", "peso", 1],
  ] as const)("%s (%s) → %s", (texto, forma, esperado) => {
    expect(cantidadDesdeTexto(texto, forma)).toBe(esperado);
  });

  it.each(["", "0", "-1", "1,5", "1.5", "1e3", "0x10", "abc", "12 3", "2147483648", "99999999999999999999"])(
    "rechaza unidades inválidas %j",
    (texto) => {
      expect(cantidadDesdeTexto(texto, "unidad")).toBeNull();
    }
  );

  it.each(["", "0", "0,000", "-1", "1,2345", "1.250", "1,", ",5", "abc", "2147484"])(
    "rechaza kg inválidos %j (sin redondear ni truncar)",
    (texto) => {
      expect(cantidadDesdeTexto(texto, "peso")).toBeNull();
    }
  );

  it("acepta el máximo de integer y rechaza uno más", () => {
    expect(cantidadDesdeTexto("2147483647", "unidad")).toBe(2147483647);
    expect(cantidadDesdeTexto("2147483,647", "peso")).toBe(2147483647);
    expect(cantidadDesdeTexto("2147483,648", "peso")).toBeNull();
  });
});

describe("validarFormularioStock", () => {
  it("ingreso: motivo opcional; vacío va como null", () => {
    expect(validarFormularioStock(form({ productoId: "pu", cantidad: "5" }), datos)).toEqual({
      ok: true,
      intento: { tipo: "ingreso", productoId: "pu", cantidad: 5, motivo: null },
    });
    expect(validarFormularioStock(form({ productoId: "pp", cantidad: "1,5", motivo: " compra " }), datos)).toEqual({
      ok: true,
      intento: { tipo: "ingreso", productoId: "pp", cantidad: 1500, motivo: "compra" },
    });
  });

  it("exige producto, producto activo y cantidad válida", () => {
    expect(validarFormularioStock(form({ cantidad: "1" }), datos).ok).toBe(false);
    expect(validarFormularioStock(form({ productoId: "inexistente", cantidad: "1" }), datos).ok).toBe(false);
    expect(validarFormularioStock(form({ productoId: "pi", cantidad: "1" }), datos)).toEqual({
      ok: false,
      error: "El producto está dado de baja.",
    });
    expect(validarFormularioStock(form({ productoId: "pu", cantidad: "1,5" }), datos).ok).toBe(false);
    expect(validarFormularioStock(form({ productoId: "pp", cantidad: "1.250" }), datos).ok).toBe(false);
    expect(validarFormularioStock(form({ productoId: "pu", cantidad: "0" }), datos).ok).toBe(false);
  });

  it("cuarentena: motivo obligatorio y origen siempre el depósito", () => {
    const f = form({ tipo: "cuarentena", productoId: "pu", cantidad: "3" });
    expect(validarFormularioStock(f, datos)).toEqual({ ok: false, error: "Indicá el motivo de la cuarentena." });
    expect(validarFormularioStock({ ...f, motivo: "   " }, datos).ok).toBe(false);
    expect(validarFormularioStock({ ...f, motivo: "revisión" }, datos)).toEqual({
      ok: true,
      intento: { tipo: "cuarentena", productoId: "pu", origenId: "dep", cantidad: 3, motivo: "revisión" },
    });
  });

  it("merma: código de la lista; «otro» exige texto", () => {
    const f = form({ tipo: "merma", productoId: "pp", cantidad: "0,500" });
    expect(validarFormularioStock(f, datos)).toEqual({ ok: false, error: "Elegí el motivo de la merma." });
    expect(validarFormularioStock({ ...f, motivoCodigo: "inventado" }, datos).ok).toBe(false);
    expect(validarFormularioStock({ ...f, motivoCodigo: "otro" }, datos).ok).toBe(false);
    expect(validarFormularioStock({ ...f, motivoCodigo: "otro", motivo: "se cayó" }, datos).ok).toBe(true);
    expect(validarFormularioStock({ ...f, motivoCodigo: "vencido" }, datos)).toEqual({
      ok: true,
      intento: { tipo: "merma", productoId: "pp", origenId: "dep", cantidad: 500, motivoCodigo: "vencido", motivo: null },
    });
  });
});

describe("sumas exactas (bigint) y presentación sin pérdida de precisión", () => {
  const SEGURO = Number.MAX_SAFE_INTEGER; // 9007199254740991
  const datosGrandes: DatosStock = {
    ...datos,
    ubicaciones: [
      ...datos.ubicaciones,
      { id: "cam2", tipo: "camion", camionId: "c2" },
    ],
    saldos: [
      { ubicacionId: "dep", productoId: "pp", cantidad: SEGURO },
      { ubicacionId: "cua", productoId: "pp", cantidad: SEGURO },
      { ubicacionId: "cam", productoId: "pp", cantidad: SEGURO },
      { ubicacionId: "cam2", productoId: "pp", cantidad: 1 },
    ],
  };

  it("la suma de saldos individualmente seguros que supera MAX_SAFE_INTEGER es exacta", () => {
    const fila = armarFilasStock(datosGrandes).find((f) => f.producto.id === "pp")!;
    expect(fila.deposito).toBe(9007199254740991n);
    expect(fila.camiones).toBe(9007199254740992n); // en Number sería inexacto (o igual a la siguiente)
    expect(fila.total).toBe(3n * 9007199254740991n + 1n);
    expect(typeof fila.total).toBe("bigint");
  });

  it("el total se presenta exacto, sin pasar por Number", () => {
    const fila = armarFilasStock(datosGrandes).find((f) => f.producto.id === "pp")!;
    // 27021597764222974 g = 27021597764222,974 kg
    expect(formatearCantidad(fila.total, "peso")).toBe("27021597764222,974 kg");
    expect(formatearCantidad(fila.total, "unidad")).toBe("27021597764222974 un.");
    // Number lo habría redondeado: 27021597764222974 no es representable.
    expect(String(Number(fila.total))).not.toBe("27021597764222974");
  });

  it("saldoDeposito suma en BigInt", () => {
    const d: DatosStock = {
      ...datos,
      saldos: [
        { ubicacionId: "dep", productoId: "pu", cantidad: SEGURO },
        { ubicacionId: "dep", productoId: "pu", cantidad: SEGURO },
      ],
    };
    expect(saldoDeposito(d, "pu")).toBe(2n * 9007199254740991n);
  });

  it("falla cerrado ante una cantidad no entera (no redondea)", () => {
    expect(() => formatearCantidad(1.5, "unidad")).toThrow();
    expect(() => formatearCantidad(Number.NaN, "peso")).toThrow();
  });

  it("acepta bigint y number con el mismo resultado en el rango seguro", () => {
    expect(formatearCantidad(1250n, "peso")).toBe(formatearCantidad(1250, "peso"));
    expect(formatearCantidad(-1250n, "peso")).toBe("-1,250 kg");
  });
});

describe("sin conversiones no autorizadas", () => {
  it("toda cantidad enviada a las RPC es un entero positivo en unidad mínima", () => {
    const entradas: [string, string, "unidad" | "peso"][] = [
      ["pu", "40", "unidad"],
      ["pp", "1,250", "peso"],
      ["pp", "0,001", "peso"],
      ["pp", "28,680", "peso"],
    ];
    for (const [productoId, cantidad, forma] of entradas) {
      const r = validarFormularioStock(form({ productoId, cantidad }), datos);
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      expect(Number.isSafeInteger(r.intento.cantidad)).toBe(true);
      expect(r.intento.cantidad).toBeGreaterThan(0);
      // peso: gramos exactos (kg × 1000); unidad: el mismo entero.
      expect(r.intento.cantidad).toBe(
        forma === "peso" ? Number(cantidad.replace(",", "")) : Number(cantidad)
      );
    }
  });

  it("no interpreta piezas ni medias piezas: un producto unidad no admite decimales ni «1/2»", () => {
    for (const t of ["0,5", "1/2", "1 1/2", "0.5"]) {
      expect(cantidadDesdeTexto(t, "unidad")).toBeNull();
    }
  });

  it("peso rechaza punto decimal, notación científica y más de 3 decimales", () => {
    for (const t of ["1.250", "1e3", "1,2500", "-0,5", "+1"]) {
      expect(cantidadDesdeTexto(t, "peso")).toBeNull();
    }
  });
});

describe("clave de idempotencia por intento", () => {
  const intento = { tipo: "ingreso", productoId: "pu", cantidad: 5, motivo: null } as const;

  it("reintentar el mismo intento reutiliza la clave hasta confirmar el éxito", () => {
    let n = 0;
    const g = crearGestorIntentos(() => `k${++n}`);
    expect(g.claveParaIntento(intento)).toBe("k1");
    expect(g.claveParaIntento({ ...intento })).toBe("k1");
    g.confirmarExito();
    expect(g.claveParaIntento(intento)).toBe("k2");
  });

  it("un intento distinto obtiene otra clave", () => {
    let n = 0;
    const g = crearGestorIntentos(() => `k${++n}`);
    g.claveParaIntento(intento);
    expect(g.claveParaIntento({ ...intento, cantidad: 6 })).toBe("k2");
    expect(firmaIntento(intento)).not.toBe(firmaIntento({ ...intento, cantidad: 6 }));
  });

  it("genera claves uuid distintas con la API del navegador", () => {
    const a = generarClaveNavegador();
    const b = generarClaveNavegador();
    expect(a).toMatch(/^[0-9a-f-]{36}$/);
    expect(a).not.toBe(b);
  });
});

describe("guarda de doble envío", () => {
  it("rechaza una segunda operación mientras la primera está en vuelo y se libera al terminar", async () => {
    const guarda = crearGuardaEnVuelo();
    let liberar!: () => void;
    let ejecuciones = 0;
    const primera = guarda.intentar(
      () => new Promise<string>((res) => { ejecuciones++; liberar = () => res("ok"); })
    );
    expect(guarda.ocupada).toBe(true);
    expect(await guarda.intentar(async () => { ejecuciones++; return "x"; })).toBe(EN_CURSO);
    liberar();
    expect(await primera).toBe("ok");
    expect(guarda.ocupada).toBe(false);
    expect(ejecuciones).toBe(1);
    expect(await guarda.intentar(async () => "otra")).toBe("otra");
  });

  it("se libera aunque la operación lance", async () => {
    const guarda = crearGuardaEnVuelo();
    await expect(guarda.intentar(async () => { throw new Error("x"); })).rejects.toThrow();
    expect(guarda.ocupada).toBe(false);
  });
});

describe("presentación", () => {
  it("formatea unidades y kg con 3 decimales fijos", () => {
    expect(formatearCantidad(12, "unidad")).toBe("12 un.");
    expect(formatearCantidad(1250, "peso")).toBe("1,250 kg");
    expect(formatearCantidad(5, "peso")).toBe("0,005 kg");
    expect(formatearCantidad(-3, "unidad")).toBe("-3 un.");
    expect(formatearCantidad(-1250, "peso")).toBe("-1,250 kg");
  });

  it("arma filas con sumas exactas por ubicación y oculta bajas sin stock", () => {
    const filas = armarFilasStock(datos);
    expect(filas.map((f) => f.producto.id)).toEqual(["pj", "pp", "pu"]);
    const yogur = filas.find((f) => f.producto.id === "pu")!;
    expect(yogur).toMatchObject({ deposito: 40n, cuarentena: 2n, camiones: 8n, total: 50n });
    expect(saldoDeposito(datos, "pp")).toBe(12500n);
    expect(saldoDeposito(datos, "pi")).toBe(0n);
  });
});
