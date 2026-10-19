// Pruebas del módulo puro de cálculo de rendición de UI.
// Escritas ANTES de la implementación (TDD: RED → GREEN).
//
// Fuente: BLUEPRINT.md §2 y §7.1 (unidad / pieza / media pieza; nunca
// kilogramo) y §12 (sin diferencia, faltante y sobrante).
//
// No se prueba aquí la conversión pieza/media pieza: eso pertenece a
// `domain/cantidades.test.ts`. Este archivo solo fija la lógica de la pantalla.
// No toca stock, dinero, persistencia, Supabase, RPC ni RLS.

import { describe, expect, it } from "vitest";

import type { ItemCarga } from "../data/mockJornadas";
import {
  MENSAJE_PIEZA_LEGACY,
  bloqueaRendicion,
  calcularFilaMercaderia,
  conteoValido,
  type FilaMercaderia,
} from "./rendicion_calculos";

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

function filaUnidad(
  parcial: Partial<ItemCarga> = {},
  resto: {
    vendido?: number;
    merma?: number;
    reemplazos?: number;
    contadoTexto?: string;
  } = {}
): FilaMercaderia {
  return calcularFilaMercaderia({
    item: item(parcial),
    vendido: resto.vendido ?? 0,
    merma: resto.merma ?? 0,
    reemplazos: resto.reemplazos ?? 0,
    contadoTexto: resto.contadoTexto,
  });
}

describe("unidad · dominio canónico", () => {
  it("esperado correcto y sin diferencia", () => {
    const fila = filaUnidad(
      { cantidad: 10 },
      { vendido: 4, merma: 2, reemplazos: 1, contadoTexto: "3" }
    );

    expect(fila.estado).toBe("ok");
    expect(fila.esperado).toBe(3);
    expect(fila.contado).toBe(3);
    expect(fila.diferencia).toBe(0);
    expect(Number.isInteger(fila.esperado)).toBe(true);
  });

  it("faltante: contado por debajo del esperado", () => {
    const fila = filaUnidad(
      { cantidad: 10 },
      { vendido: 4, contadoTexto: "5" }
    );

    expect(fila.estado).toBe("ok");
    expect(fila.esperado).toBe(6);
    expect(fila.diferencia).toBe(-1);
  });

  it("sobrante: contado por encima del esperado", () => {
    const fila = filaUnidad(
      { cantidad: 10 },
      { vendido: 4, contadoTexto: "8" }
    );

    expect(fila.estado).toBe("ok");
    expect(fila.esperado).toBe(6);
    expect(fila.diferencia).toBe(2);
  });

  it("sin conteo no calcula diferencia", () => {
    const fila = filaUnidad({ cantidad: 10 }, { vendido: 4 });

    expect(fila.estado).toBe("ok");
    expect(fila.esperado).toBe(6);
    expect(fila.contado).toBeNull();
    expect(fila.diferencia).toBeNull();
  });

  it("un conteo decimal no es un conteo válido", () => {
    const fila = filaUnidad(
      { cantidad: 10 },
      { vendido: 4, contadoTexto: "6.5" }
    );

    expect(fila.contado).toBeNull();
    expect(fila.diferencia).toBeNull();
  });

  it("conteoValido rechaza decimales, negativos y vacíos", () => {
    expect(conteoValido("4")).toBe(4);
    expect(conteoValido("0")).toBe(0);
    expect(conteoValido("6.5")).toBeNull();
    expect(conteoValido("-1")).toBeNull();
    expect(conteoValido("")).toBeNull();
    expect(conteoValido(undefined)).toBeNull();
  });

  it("salidas > cargado: inconsistencia sin excepción hacia React", () => {
    expect(() =>
      filaUnidad({ cantidad: 3 }, { vendido: 4, contadoTexto: "0" })
    ).not.toThrow();

    const fila = filaUnidad(
      { cantidad: 3 },
      { vendido: 4, contadoTexto: "0" }
    );

    expect(fila.estado).toBe("inconsistente");
    expect(fila.esperado).toBeNull();
    expect(fila.diferencia).toBeNull();
    expect(bloqueaRendicion([fila])).toBe(true);
  });

  it("la suma de salidas también puede superar lo cargado", () => {
    const fila = filaUnidad(
      { cantidad: 5 },
      { vendido: 3, merma: 2, reemplazos: 1, contadoTexto: "0" }
    );

    expect(fila.estado).toBe("inconsistente");
    expect(fila.esperado).toBeNull();
    expect(bloqueaRendicion([fila])).toBe(true);
  });
});

describe("pieza legacy · no conciliable", () => {
  const pieza = item({
    productoId: 2,
    nombreProducto: "Queso cremoso",
    unidadMedida: "pieza",
    cantidad: 4,
  });

  it("marca la fila como no conciliable (pieza_legacy)", () => {
    const fila = calcularFilaMercaderia({
      item: pieza,
      vendido: 1,
      merma: 0,
      reemplazos: 0,
      contadoTexto: "3",
    });

    expect(fila.estado).toBe("pieza_legacy");
  });

  it("no produce esperado canónico ni diferencia canónica", () => {
    const fila = calcularFilaMercaderia({
      item: pieza,
      vendido: 1,
      merma: 0,
      reemplazos: 0,
      contadoTexto: "3",
    });

    expect(fila.esperado).toBeNull();
    expect(fila.diferencia).toBeNull();
  });

  it("provoca el bloqueo del cierre", () => {
    const fila = calcularFilaMercaderia({
      item: pieza,
      vendido: 1,
      merma: 0,
      reemplazos: 0,
      contadoTexto: "3",
    });

    expect(bloqueaRendicion([fila])).toBe(true);
  });

  it("bloquea el cierre aunque el resto de las filas sea conciliable", () => {
    const ok = filaUnidad(
      { cantidad: 10 },
      { vendido: 4, contadoTexto: "6" }
    );
    const legacy = calcularFilaMercaderia({
      item: pieza,
      vendido: 1,
      merma: 0,
      reemplazos: 0,
      contadoTexto: "3",
    });

    expect(bloqueaRendicion([ok, legacy])).toBe(true);
  });

  it("el mensaje deja claro que requiere migración a medias piezas", () => {
    expect(MENSAJE_PIEZA_LEGACY).toMatch(/medias piezas/i);
    expect(MENSAJE_PIEZA_LEGACY).toMatch(/migrar/i);
  });
});

describe("kg legacy · no soportado", () => {
  // Fixture deliberadamente inválido: "kg" ya no es un valor válido de
  // UnidadMedida. Se usa solo para verificar robustez ante datos legacy
  // que aún pudieran existir en localStorage v1.
  it("no se concilia con el dominio y bloquea el cierre", () => {
    const fila = calcularFilaMercaderia({
      item: item({
        productoId: 3,
        unidadMedida: "kg" as unknown as ItemCarga["unidadMedida"],
        cantidad: 2.5,
      }),
      vendido: 0,
      merma: 0,
      reemplazos: 0,
      contadoTexto: "2.5",
    });

    expect(fila.estado).toBe("no_soportada");
    expect(fila.esperado).toBeNull();
    expect(fila.diferencia).toBeNull();
    expect(bloqueaRendicion([fila])).toBe(true);
  });
});

describe("bloqueaRendicion", () => {
  it("no bloquea cuando todas las filas son conciliables", () => {
    const fila = filaUnidad(
      { cantidad: 10 },
      { vendido: 4, contadoTexto: "6" }
    );

    expect(bloqueaRendicion([fila])).toBe(false);
    expect(bloqueaRendicion([])).toBe(false);
  });

  it("bloquea ante cualquier fila no conciliable", () => {
    const inconsistente = filaUnidad(
      { cantidad: 3 },
      { vendido: 4, contadoTexto: "0" }
    );

    expect(bloqueaRendicion([inconsistente])).toBe(true);
  });
});
