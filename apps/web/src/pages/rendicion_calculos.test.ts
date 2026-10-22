// Pruebas del módulo puro de cálculo de rendición de UI.
//
// Fuente: BLUEPRINT.md §2 y §7.1 (unidad / pieza / media pieza; nunca
// kilogramo) y §12 (sin diferencia, faltante y sobrante).
//
// `unidad` y `pieza` se concilian con el mismo algoritmo en cantidades
// canónicas (enteros seguros; medias piezas para pieza). La conversión
// pieza/media pieza pertenece a `domain/cantidades.test.ts`.
// No toca stock, dinero, persistencia, Supabase, RPC ni RLS.

import { describe, expect, it } from "vitest";

import type { ItemCarga } from "../data/mockJornadas";
import type { MovimientoReparto } from "../data/mockMovimientos";
import { entrada_desde_cantidad } from "../domain/retornos";
import {
  acumularCuarentena,
  acumularSalidasProducto,
  bloqueaRendicion,
  calcularFilaMercaderia,
  conteoDesdeEntrada,
  conteoValido,
  type FilaMercaderia,
} from "./rendicion_calculos";

const MAX = Number.MAX_SAFE_INTEGER;

function item(parcial: Partial<ItemCarga> = {}): ItemCarga {
  return {
    productoId: 1,
    nombreProducto: "Yogur bebible 1 L",
    unidadMedida: "unidad",
    cantidad: 10,
    precioReferencia: 2300,
    ...parcial,
  };
}

function fila(
  parcial: Partial<ItemCarga> = {},
  resto: {
    vendido?: number;
    merma?: number;
    reemplazos?: number;
    contado?: number | null;
    acumulacionInvalida?: boolean;
  } = {}
): FilaMercaderia {
  return calcularFilaMercaderia({
    item: item(parcial),
    vendido: resto.vendido ?? 0,
    merma: resto.merma ?? 0,
    reemplazos: resto.reemplazos ?? 0,
    contado: resto.contado ?? null,
    acumulacionInvalida: resto.acumulacionInvalida,
  });
}

const PIEZA = {
  productoId: 2,
  nombreProducto: "Jamón cocido",
  unidadMedida: "pieza" as const,
};

describe("unidad · dominio canónico", () => {
  it("esperado correcto y sin diferencia", () => {
    const f = fila({ cantidad: 10 }, { vendido: 4, merma: 2, reemplazos: 1, contado: 3 });

    expect(f.estado).toBe("ok");
    expect(f.esperado).toBe(3);
    expect(f.contado).toBe(3);
    expect(f.diferencia).toBe(0);
    expect(f.mermaYCambios).toBe(3);
  });

  it("faltante: contado por debajo del esperado", () => {
    const f = fila({ cantidad: 10 }, { vendido: 4, contado: 5 });
    expect(f.esperado).toBe(6);
    expect(f.diferencia).toBe(-1);
  });

  it("sobrante: contado por encima del esperado", () => {
    const f = fila({ cantidad: 10 }, { vendido: 4, contado: 8 });
    expect(f.esperado).toBe(6);
    expect(f.diferencia).toBe(2);
  });

  it("sin conteo no calcula diferencia", () => {
    const f = fila({ cantidad: 10 }, { vendido: 4 });
    expect(f.estado).toBe("ok");
    expect(f.contado).toBeNull();
    expect(f.diferencia).toBeNull();
  });

  it("salidas > cargado: inconsistencia sin excepción hacia React", () => {
    expect(() => fila({ cantidad: 3 }, { vendido: 4, contado: 0 })).not.toThrow();
    const f = fila({ cantidad: 3 }, { vendido: 4, contado: 0 });
    expect(f.estado).toBe("inconsistente");
    expect(f.esperado).toBeNull();
    expect(f.diferencia).toBeNull();
    expect(bloqueaRendicion([f])).toBe(true);
  });

  it("la suma de salidas también puede superar lo cargado", () => {
    const f = fila({ cantidad: 5 }, { vendido: 3, merma: 2, reemplazos: 1, contado: 0 });
    expect(f.estado).toBe("inconsistente");
    expect(bloqueaRendicion([f])).toBe(true);
  });
});

describe("pieza · medias piezas canónicas (ya no existe pieza_legacy)", () => {
  it("cargado 5, vendido 1, merma 1, reemplazos 1 → esperado 2", () => {
    const f = fila({ ...PIEZA, cantidad: 5 }, { vendido: 1, merma: 1, reemplazos: 1, contado: 2 });
    expect(f.estado).toBe("ok");
    expect(f.esperado).toBe(2);
    expect(f.diferencia).toBe(0);
  });

  it("contado 1 → diferencia -1 (faltante)", () => {
    const f = fila({ ...PIEZA, cantidad: 5 }, { vendido: 1, merma: 1, reemplazos: 1, contado: 1 });
    expect(f.estado).toBe("ok");
    expect(f.diferencia).toBe(-1);
  });

  it("contado 3 → diferencia +1 (sobrante)", () => {
    const f = fila({ ...PIEZA, cantidad: 5 }, { vendido: 1, merma: 1, reemplazos: 1, contado: 3 });
    expect(f.diferencia).toBe(1);
  });

  it("una pieza válida NO bloquea la rendición", () => {
    const f = fila({ ...PIEZA, cantidad: 5 }, { vendido: 1, contado: 4 });
    expect(bloqueaRendicion([f])).toBe(false);
  });

  it("pieza válida y unidad válida se concilian juntas", () => {
    const u = fila({ cantidad: 10 }, { vendido: 4, contado: 6 });
    const p = fila({ ...PIEZA, cantidad: 5 }, { vendido: 1, contado: 4 });
    expect(bloqueaRendicion([u, p])).toBe(false);
  });

  it("componentes decimales o no seguros → inconsistente", () => {
    for (const vendido of [1.5, MAX + 1, -1, NaN, Infinity]) {
      const f = fila({ ...PIEZA, cantidad: 5 }, { vendido, contado: 2 });
      expect(f.estado).toBe("inconsistente");
      expect(f.esperado).toBeNull();
      expect(bloqueaRendicion([f])).toBe(true);
    }
    expect(fila({ ...PIEZA, cantidad: 4.5 }).estado).toBe("inconsistente");
    expect(fila({ ...PIEZA, cantidad: MAX + 1 }).estado).toBe("inconsistente");
  });

  it("un contado no canónico se ignora (null), no se corrige", () => {
    expect(fila({ ...PIEZA, cantidad: 5 }, { contado: 1.5 }).contado).toBeNull();
    expect(fila({ ...PIEZA, cantidad: 5 }, { contado: MAX + 1 }).contado).toBeNull();
  });
});

describe("overflow y acumulación inválida", () => {
  it("salidas combinadas que exceden MAX_SAFE_INTEGER → inconsistente, sin throw", () => {
    const f = fila(
      { cantidad: MAX },
      { vendido: MAX, merma: 1, reemplazos: 0, contado: 0 }
    );
    expect(f.estado).toBe("inconsistente");
    expect(f.mermaYCambios).toBe(1);
  });

  it("merma + reemplazos que desbordan → mermaYCambios null", () => {
    const f = fila({ cantidad: MAX }, { merma: MAX, reemplazos: 1 });
    expect(f.mermaYCambios).toBeNull();
    expect(f.estado).toBe("inconsistente");
  });

  it("acumulacionInvalida fuerza inconsistente", () => {
    const f = fila({ cantidad: 10 }, { contado: 3, acumulacionInvalida: true });
    expect(f.estado).toBe("inconsistente");
    expect(bloqueaRendicion([f])).toBe(true);
  });
});

describe("unidad no soportada (defensivo en runtime)", () => {
  it("kg no se concilia y bloquea el cierre", () => {
    const f = fila(
      { productoId: 3, unidadMedida: "kg" as unknown as ItemCarga["unidadMedida"], cantidad: 2 },
      { contado: 2 }
    );
    expect(f.estado).toBe("no_soportada");
    expect(f.esperado).toBeNull();
    expect(f.diferencia).toBeNull();
    expect(bloqueaRendicion([f])).toBe(true);
  });
});

describe("bloqueaRendicion", () => {
  it("no bloquea cuando todas las filas son conciliables", () => {
    expect(bloqueaRendicion([fila({ cantidad: 10 }, { vendido: 4, contado: 6 })])).toBe(false);
    expect(bloqueaRendicion([])).toBe(false);
  });

  it("bloquea ante cualquier fila no conciliable", () => {
    expect(bloqueaRendicion([fila({ cantidad: 3 }, { vendido: 4, contado: 0 })])).toBe(true);
  });
});

describe("conteo: entrada de UI ↔ cantidad canónica", () => {
  it("conteoValido: entero seguro >= 0", () => {
    expect(conteoValido("4")).toBe(4);
    expect(conteoValido("0")).toBe(0);
    expect(conteoValido(String(MAX))).toBe(MAX);
    for (const t of ["6.5", "-1", "", "NaN", "Infinity", String(MAX + 1)]) {
      expect(conteoValido(t)).toBeNull();
    }
    expect(conteoValido(undefined)).toBeNull();
  });

  it("unidad: entero simple; no admite media", () => {
    expect(conteoDesdeEntrada("unidad", { texto: "7", media: false })).toBe(7);
    expect(conteoDesdeEntrada("unidad", { texto: "0", media: false })).toBe(0);
    expect(conteoDesdeEntrada("unidad", { texto: "7", media: true })).toBeNull();
    expect(conteoDesdeEntrada("unidad", { texto: "1.5", media: false })).toBeNull();
  });

  it("pieza: piezas + media → medias canónicas", () => {
    const c = (texto: string, media: boolean) =>
      conteoDesdeEntrada("pieza", { texto, media });
    expect(c("0", false)).toBe(0);
    expect(c("0", true)).toBe(1);
    expect(c("", true)).toBe(1);
    expect(c("1", false)).toBe(2);
    expect(c("1", true)).toBe(3);
    expect(c("2", false)).toBe(4);
    expect(c("2", true)).toBe(5);
  });

  it("vacío o indefinido → null (sin contar)", () => {
    expect(conteoDesdeEntrada("pieza", { texto: " ", media: false })).toBeNull();
    expect(conteoDesdeEntrada("pieza", undefined)).toBeNull();
  });

  it("pieza inválida u overflow → null, sin throw", () => {
    for (const texto of ["1.5", "-1", "NaN", "Infinity", String(2 ** 52)]) {
      for (const media of [true, false]) {
        expect(() => conteoDesdeEntrada("pieza", { texto, media })).not.toThrow();
        expect(conteoDesdeEntrada("pieza", { texto, media })).toBeNull();
      }
    }
  });

  it("round trip canónico → UI → canónico (completar con esperados / cierre existente)", () => {
    for (const unidad of ["unidad", "pieza"] as const) {
      for (const c of [0, 1, 2, 3, 4, 5, 9]) {
        const entrada = entrada_desde_cantidad(unidad, c)!;
        expect(conteoDesdeEntrada(unidad, entrada)).toBe(c);
      }
    }
    expect(entrada_desde_cantidad("pieza", 5)).toEqual({ texto: "2", media: true });
    expect(entrada_desde_cantidad("pieza", 1)).toEqual({ texto: "0", media: true });
  });
});

describe("acumularSalidasProducto", () => {
  const merma = (cantidad: number, productoId = 1, jornadaId = "j1"): MovimientoReparto => ({
    id: `m${cantidad}${productoId}`,
    jornadaId,
    camionId: 1,
    fecha: "2026-10-21T10:00:00.000Z",
    motivo: "x",
    tipo: "merma",
    producto: { productoId, nombreProducto: "P", unidadMedida: "pieza", cantidad },
    clienteId: null,
    nombreCliente: null,
  });

  const cambio = (entregado: number, productoId = 1): MovimientoReparto => ({
    id: `c${entregado}`,
    jornadaId: "j1",
    camionId: 1,
    fecha: "2026-10-21T10:00:00.000Z",
    motivo: "x",
    tipo: "cambio",
    clienteId: 1,
    nombreCliente: "C",
    productoDevuelto: { productoId: 99, nombreProducto: "D", unidadMedida: "unidad", cantidad: 7 },
    productoEntregado: { productoId, nombreProducto: "P", unidadMedida: "pieza", cantidad: entregado },
  });

  const venta = (cantidad: number, productoId = 1, jornadaId = "j1") => ({
    jornadaId,
    items: [{ productoId, cantidad }],
  });

  it("caso global: carga 5, venta 1, merma 1, cambio 1 → esperado 2, conteo 2, ok", () => {
    const salidas = acumularSalidasProducto(1, "j1", [venta(1)], [merma(1), cambio(1)]);
    expect(salidas).toEqual({ vendido: 1, merma: 1, reemplazos: 1, valido: true });

    const f = calcularFilaMercaderia({
      item: item({ productoId: 1, unidadMedida: "pieza", cantidad: 5 }),
      vendido: salidas.vendido,
      merma: salidas.merma,
      reemplazos: salidas.reemplazos,
      acumulacionInvalida: !salidas.valido,
      contado: conteoDesdeEntrada("pieza", { texto: "1", media: false }),
    });

    expect(f.esperado).toBe(2);
    expect(f.contado).toBe(2);
    expect(f.diferencia).toBe(0);
    expect(f.estado).toBe("ok");
    expect(bloqueaRendicion([f])).toBe(false);
  });

  it("ignora otras jornadas y otros productos; el producto devuelto no es salida", () => {
    const s = acumularSalidasProducto(
      1,
      "j1",
      [venta(2), venta(9, 1, "j2"), venta(5, 2)],
      [merma(3, 1, "j2"), cambio(1, 1), merma(4, 2)]
    );
    expect(s).toEqual({ vendido: 2, merma: 0, reemplazos: 1, valido: true });
  });

  it("límite exacto MAX permitido; exceso → valido:false sin valores aproximados", () => {
    expect(acumularSalidasProducto(1, "j1", [venta(MAX - 1), venta(1)], []).vendido).toBe(MAX);
    const roto = acumularSalidasProducto(1, "j1", [venta(MAX), venta(1)], []);
    expect(roto).toEqual({ vendido: 0, merma: 0, reemplazos: 0, valido: false });
  });

  it("overflow por ventas + movimientos solo si es la misma categoría; merma y venta son contadores separados", () => {
    expect(acumularSalidasProducto(1, "j1", [venta(MAX)], [merma(MAX)]).valido).toBe(true);
    expect(acumularSalidasProducto(1, "j1", [], [merma(MAX), merma(1)]).valido).toBe(false);
  });

  it("cantidad inválida en una venta → valido:false", () => {
    expect(acumularSalidasProducto(1, "j1", [venta(1.5)], []).valido).toBe(false);
  });
});


describe("M-1: mermaYCambios no muestra 0 falso cuando acumulación falló", () => {
  it("merma = 1, reemplazos = 2 → mermaYCambios === 3 (control positivo)", () => {
    const f = fila({ cantidad: 10 }, { merma: 1, reemplazos: 2 });
    expect(f.mermaYCambios).toBe(3);
    expect(f.estado).toBe("ok");
  });

  it("acumulacionInvalida → mermaYCambios === null, estado inconsistente", () => {
    const f = fila(
      { cantidad: 10 },
      { merma: 1, reemplazos: 2, acumulacionInvalida: true }
    );
    expect(f.mermaYCambios).toBeNull();
    expect(f.estado).toBe("inconsistente");
    expect(f.esperado).toBeNull();
    expect(f.diferencia).toBeNull();
  });

  it("overflow en merma + reemplazos → mermaYCambios null, estado inconsistente", () => {
    const f = fila({ cantidad: MAX }, { merma: MAX, reemplazos: 1 });
    expect(f.mermaYCambios).toBeNull();
    expect(f.estado).toBe("inconsistente");
  });

  it("acumulacionInvalida + merma + reemplazos = 0 → mermaYCambios === null (no 0)", () => {
    const f = fila(
      { cantidad: 10 },
      { merma: 0, reemplazos: 0, acumulacionInvalida: true }
    );
    // Cuando la acumulación falló, mermaYCambios debe ser null, no 0
    expect(f.mermaYCambios).toBeNull();
    expect(f.estado).toBe("inconsistente");
  });
});


describe("acumularCuarentena (informativo)", () => {
  const dev = (cantidad: number, productoId = 1): MovimientoReparto => ({
    id: `d${cantidad}`,
    jornadaId: "j1",
    camionId: 1,
    fecha: "2026-10-21T10:00:00.000Z",
    motivo: "x",
    tipo: "devolucion",
    clienteId: 1,
    nombreCliente: "C",
    producto: { productoId, nombreProducto: "P", unidadMedida: "pieza", cantidad },
  });

  it("suma exacta por producto, ignorando mermas y otras jornadas", () => {
    const r = acumularCuarentena("j1", [dev(1), dev(2), dev(4, 2)]);
    expect(r.map((p) => [p.productoId, p.cantidad])).toEqual([[1, 3], [2, 4]]);
  });

  it("overflow → cantidad null (no se inventa un saldo) y se mantiene null", () => {
    const r = acumularCuarentena("j1", [dev(MAX), dev(1), dev(1)]);
    expect(r[0].cantidad).toBeNull();
  });
});
