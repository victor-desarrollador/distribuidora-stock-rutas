import { describe, expect, it } from "vitest";

import type { ItemRetorno, RetornoDeposito } from "../data/mockRetornos";
import {
  cantidad_a_texto,
  cantidad_aprobada_desde_entrada,
  cierre_sin_cambios,
  contado_desde_cierre,
  entrada_desde_cantidad,
  entrada_vacia,
  item_retorno_valido,
  media_aprobable,
  pendiente_retorno,
  retorno_valido,
} from "./retornos";

const MAX = Number.MAX_SAFE_INTEGER;

const item = (
  unidadMedida: ItemRetorno["unidadMedida"],
  contada: number,
  aprobada: number,
  productoId = 1
): ItemRetorno => ({
  productoId,
  nombreProducto: "Producto",
  unidadMedida,
  cantidadContada: contada,
  cantidadAprobada: aprobada,
});

const retorno = (items: unknown[], extra: Record<string, unknown> = {}) =>
  ({
    id: "r1",
    jornadaId: "j1",
    camionId: 1,
    fecha: "2026-10-21T10:00:00.000Z",
    responsable: "Ana",
    observaciones: "",
    items,
    ...extra,
  }) as unknown as RetornoDeposito;

describe("item_retorno_valido: unidad", () => {
  it("0 es válido como aprobado; 2 también", () => {
    expect(item_retorno_valido(item("unidad", 5, 0))).toBe(true);
    expect(item_retorno_valido(item("unidad", 5, 2))).toBe(true);
  });

  it("1.5, NaN, Infinity y negativos son inválidos", () => {
    for (const c of [1.5, NaN, Infinity, -1]) {
      expect(item_retorno_valido(item("unidad", 5, c))).toBe(false);
      expect(item_retorno_valido(item("unidad", c, 0))).toBe(false);
    }
  });

  it("MAX_SAFE_INTEGER válido si no excede lo contado; MAX+1 inválido", () => {
    expect(item_retorno_valido(item("unidad", MAX, MAX))).toBe(true);
    expect(item_retorno_valido(item("unidad", MAX + 1, 0))).toBe(false);
    expect(item_retorno_valido(item("unidad", MAX, MAX + 1))).toBe(false);
  });

  it("aprobada mayor que contada es inválida, sin tolerancia", () => {
    expect(item_retorno_valido(item("unidad", 5, 6))).toBe(false);
  });

  it("kg no es una unidad válida", () => {
    expect(
      item_retorno_valido({ ...item("unidad", 5, 1), unidadMedida: "kg" })
    ).toBe(false);
  });
});

describe("item_retorno_valido: pieza (contado 5 medias)", () => {
  it.each([0, 1, 2, 3, 5])("aprobado %i medias es válido", (a) => {
    expect(item_retorno_valido(item("pieza", 5, a))).toBe(true);
  });

  it("aprobado 6 es inválido", () => {
    expect(item_retorno_valido(item("pieza", 5, 6))).toBe(false);
  });
});

describe("cantidad_aprobada_desde_entrada", () => {
  it("pieza: piezas + media → canónico (contado 5)", () => {
    const aprobar = (texto: string, media: boolean) =>
      cantidad_aprobada_desde_entrada("pieza", { texto, media }, 5);
    expect(aprobar("0", true)).toBe(1);
    expect(aprobar("1", false)).toBe(2);
    expect(aprobar("1", true)).toBe(3);
    expect(aprobar("2", false)).toBe(4);
    expect(aprobar("2", true)).toBe(5);
    expect(aprobar("0", false)).toBe(0);
  });

  it("pieza: no puede superar lo contado (6 medias)", () => {
    expect(
      cantidad_aprobada_desde_entrada("pieza", { texto: "3", media: false }, 5)
    ).toBeNull();
    expect(
      cantidad_aprobada_desde_entrada("pieza", { texto: "2", media: true }, 4)
    ).toBeNull();
  });

  it("unidad: entero, sin media, sin superar lo contado", () => {
    const aprobar = (texto: string, media = false) =>
      cantidad_aprobada_desde_entrada("unidad", { texto, media }, 5);
    expect(aprobar("0")).toBe(0);
    expect(aprobar("5")).toBe(5);
    expect(aprobar("6")).toBeNull();
    expect(aprobar("1.5")).toBeNull();
    expect(aprobar("-1")).toBeNull();
    expect(aprobar("NaN")).toBeNull();
    expect(aprobar("Infinity")).toBeNull();
    expect(aprobar("2", true)).toBeNull();
  });

  it("overflow en pieza → null, sin throw", () => {
    for (const media of [true, false]) {
      expect(() =>
        cantidad_aprobada_desde_entrada(
          "pieza",
          { texto: String(2 ** 52), media },
          MAX
        )
      ).not.toThrow();
      expect(
        cantidad_aprobada_desde_entrada(
          "pieza",
          { texto: String(2 ** 52), media },
          MAX
        )
      ).toBeNull();
    }
  });

  it("contado inválido → null", () => {
    expect(
      cantidad_aprobada_desde_entrada("unidad", { texto: "1", media: false }, 1.5)
    ).toBeNull();
  });
});

describe("completar con contado: entrada_desde_cantidad", () => {
  it.each([
    [1, { texto: "0", media: true }],
    [2, { texto: "1", media: false }],
    [3, { texto: "1", media: true }],
    [5, { texto: "2", media: true }],
    [0, { texto: "0", media: false }],
  ])("pieza %i medias se reconstruye", (c, esperado) => {
    expect(entrada_desde_cantidad("pieza", c)).toEqual(esperado);
  });

  it("unidad se rellena con el entero", () => {
    expect(entrada_desde_cantidad("unidad", 7)).toEqual({
      texto: "7",
      media: false,
    });
  });

  it("round trip: la entrada reconstruida vuelve a la misma cantidad", () => {
    for (const c of [0, 1, 2, 3, 4, 5, 9]) {
      const e = entrada_desde_cantidad("pieza", c)!;
      expect(cantidad_aprobada_desde_entrada("pieza", e, c)).toBe(c);
    }
  });

  it("cantidad inválida → null", () => {
    expect(entrada_desde_cantidad("pieza", 1.5)).toBeNull();
    expect(entrada_desde_cantidad("unidad", -1)).toBeNull();
  });
});

describe("pendiente_retorno (exacto)", () => {
  it("5 contado - 3 aprobado = 2", () => {
    expect(pendiente_retorno(5, 3)).toBe(2);
    expect(pendiente_retorno(5, 5)).toBe(0);
    expect(pendiente_retorno(MAX, 1)).toBe(MAX - 1);
  });

  it("lanza si aprobado supera contado o hay datos inválidos", () => {
    expect(() => pendiente_retorno(5, 6)).toThrow();
    expect(() => pendiente_retorno(5.5, 1)).toThrow();
    expect(() => pendiente_retorno(5, -1)).toThrow();
  });

  it("se muestra según unidad", () => {
    expect(cantidad_a_texto("unidad", 3)).toBe("3 un.");
    expect(cantidad_a_texto("pieza", 3)).toBe("1 pieza y media");
  });
});

describe("media_aprobable y entrada_vacia", () => {
  it("contado 5: con 2 piezas todavía entra una media; con 3 no", () => {
    expect(media_aprobable(5, "2")).toBe(true);
    expect(media_aprobable(5, "3")).toBe(false);
    expect(media_aprobable(5, "")).toBe(true);
    expect(media_aprobable(5, "1.5")).toBe(false);
  });

  it("vacía solo sin texto y sin media", () => {
    expect(entrada_vacia({ texto: " ", media: false })).toBe(true);
    expect(entrada_vacia({ texto: "", media: true })).toBe(false);
    expect(entrada_vacia({ texto: "0", media: false })).toBe(false);
  });
});

describe("cierre_sin_cambios y contado_desde_cierre", () => {
  it("igual y canónico → sin cambios", () => {
    expect(cierre_sin_cambios(5, 5)).toBe(true);
  });

  it("distinto, ausente o inseguro → cambió (falla cerrado)", () => {
    expect(cierre_sin_cambios(4, 5)).toBe(false);
    expect(cierre_sin_cambios(undefined, 5)).toBe(false);
    expect(cierre_sin_cambios(5.0000001, 5)).toBe(false);
    expect(cierre_sin_cambios(MAX + 1, MAX + 1)).toBe(false);
    expect(cierre_sin_cambios("5", 5)).toBe(false);
  });

  it("contado_desde_cierre exige entero seguro >= 0", () => {
    expect(contado_desde_cierre(0)).toBe(0);
    expect(contado_desde_cierre(MAX)).toBe(MAX);
    expect(contado_desde_cierre(1.5)).toBeNull();
    expect(contado_desde_cierre(-1)).toBeNull();
    expect(contado_desde_cierre(NaN)).toBeNull();
    expect(contado_desde_cierre(MAX + 1)).toBeNull();
    expect(contado_desde_cierre(undefined)).toBeNull();
  });
});

describe("retorno_valido", () => {
  it("válido con ítems de unidad y pieza", () => {
    expect(
      retorno_valido(
        retorno([item("unidad", 5, 2, 1), item("pieza", 5, 3, 2)])
      )
    ).toBe(true);
  });

  it("rechaza productoId duplicado", () => {
    expect(
      retorno_valido(retorno([item("unidad", 5, 2, 1), item("unidad", 5, 2, 1)]))
    ).toBe(false);
  });

  it("rechaza id/jornadaId vacíos y camionId no seguro", () => {
    expect(retorno_valido(retorno([], { id: "" }))).toBe(false);
    expect(retorno_valido(retorno([], { jornadaId: " " }))).toBe(false);
    expect(retorno_valido(retorno([], { camionId: 1.5 }))).toBe(false);
  });

  it("responsable vacío: válido al leer, inválido en escritura nueva", () => {
    const r = retorno([], { responsable: "  " });
    expect(retorno_valido(r)).toBe(true);
    expect(retorno_valido(r, { exigir_responsable: true })).toBe(false);
  });

  it("rechaza items que no son array o ítems inválidos", () => {
    expect(retorno_valido(retorno([], { items: null }))).toBe(false);
    expect(retorno_valido(retorno([item("unidad", 5, 6)]))).toBe(false);
    expect(retorno_valido(null)).toBe(false);
  });
});
