// Pruebas del dominio de Retornos en B1 (ADR-005).
//
// Estado B1:
//   - `unidad` funciona igual que antes (validación, entrada, pendiente,
//     cierre sin cambios).
//   - El storage v5 acepta estructuralmente `peso` con gramos enteros, pero
//     la entrada de UI y la frontera de escritura lo rechazan hasta B4.
//   - `pieza` se rechaza. No hay conteo ni retorno en kg.
import { describe, expect, it, vi } from "vitest";

import type { ItemRetorno, RetornoDeposito } from "../data/mockRetornos";
import {
  cantidad_aprobada_desde_entrada,
  cierre_sin_cambios,
  contado_desde_cierre,
  entrada_desde_cantidad,
  entrada_vacia,
  item_retorno_valido,
  pendiente_retorno,
  retorno_valido,
} from "./retornos";
import { cantidad_a_texto, MENSAJE_PESO_NO_OPERABLE } from "./productos";
import { registrarRetornoOperacion } from "../hooks/useRetornos";

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
});

describe("item_retorno_valido: storage v5", () => {
  it("peso con gramos enteros es estructuralmente válido", () => {
    expect(item_retorno_valido(item("peso", 18000, 17999))).toBe(true);
    expect(item_retorno_valido(item("peso", 9, 0))).toBe(true);
  });

  it("peso con gramos fraccionarios es inválido", () => {
    expect(item_retorno_valido(item("peso", 1250.5, 0))).toBe(false);
    expect(item_retorno_valido(item("peso", 1250, 0.5))).toBe(false);
  });

  it("peso: aprobado mayor que contado es inválido, sin tolerancia (1 g)", () => {
    expect(item_retorno_valido(item("peso", 1250, 1251))).toBe(false);
  });

  it.each(["pieza", "media_pieza", "kg"])("rechaza la unidad '%s'", (unidad) => {
    expect(
      item_retorno_valido({ ...item("unidad", 5, 1), unidadMedida: unidad })
    ).toBe(false);
  });
});

describe("cantidad_aprobada_desde_entrada", () => {
  it("unidad: entero sin superar lo contado", () => {
    const aprobar = (texto: string) =>
      cantidad_aprobada_desde_entrada("unidad", { texto }, 5);
    expect(aprobar("0")).toBe(0);
    expect(aprobar("5")).toBe(5);
    expect(aprobar("6")).toBeNull();
    expect(aprobar("1.5")).toBeNull();
    expect(aprobar("-1")).toBeNull();
    expect(aprobar("NaN")).toBeNull();
    expect(aprobar("Infinity")).toBeNull();
  });

  it("contado inválido → null", () => {
    expect(
      cantidad_aprobada_desde_entrada("unidad", { texto: "1" }, 1.5)
    ).toBeNull();
  });

  it.each(["0", "1", "1250", "1,250"])(
    "peso devuelve null en B1 (sin entrada en kg) para %j",
    (texto) => {
      expect(
        cantidad_aprobada_desde_entrada("peso", { texto }, 18000)
      ).toBeNull();
    }
  );

  it("'pieza' no es una unidad válida", () => {
    expect(
      cantidad_aprobada_desde_entrada("pieza" as never, { texto: "1" }, 5)
    ).toBeNull();
  });
});

describe("entrada_desde_cantidad", () => {
  it("unidad se rellena con el entero", () => {
    expect(entrada_desde_cantidad("unidad", 7)).toEqual({ texto: "7" });
    expect(entrada_desde_cantidad("unidad", 0)).toEqual({ texto: "0" });
  });

  it("round trip unidad: la entrada reconstruida vuelve a la misma cantidad", () => {
    for (const c of [0, 1, 5, 9]) {
      const e = entrada_desde_cantidad("unidad", c)!;
      expect(cantidad_aprobada_desde_entrada("unidad", e, c)).toBe(c);
    }
  });

  it("peso devuelve null en B1 (sin entrada en kg)", () => {
    expect(entrada_desde_cantidad("peso", 18000)).toBeNull();
    expect(entrada_desde_cantidad("peso", 0)).toBeNull();
  });

  it("cantidad inválida → null", () => {
    expect(entrada_desde_cantidad("unidad", 1.5)).toBeNull();
    expect(entrada_desde_cantidad("unidad", -1)).toBeNull();
  });
});

describe("entrada_vacia", () => {
  it("vacía sólo sin texto", () => {
    expect(entrada_vacia({ texto: " " })).toBe(true);
    expect(entrada_vacia({ texto: "" })).toBe(true);
    expect(entrada_vacia({ texto: "0" })).toBe(false);
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
});

describe("presentación de cantidades (helper canónico de domain/productos)", () => {
  it("unidad: '3 un.'", () => {
    expect(cantidad_a_texto("unidad", 3)).toBe("3 un.");
  });

  it("peso: gramos → kg con 3 decimales fijos", () => {
    expect(cantidad_a_texto("peso", 18000)).toBe("18,000 kg");
    expect(cantidad_a_texto("peso", 2500)).toBe("2,500 kg");
    expect(cantidad_a_texto("peso", 9)).toBe("0,009 kg");
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
  it("válido con ítems unidad", () => {
    expect(
      retorno_valido(retorno([item("unidad", 5, 2, 1), item("unidad", 3, 3, 2)]))
    ).toBe(true);
  });

  it("estructuralmente válido con un ítem peso en gramos (storage v5)", () => {
    expect(
      retorno_valido(retorno([item("unidad", 5, 2, 1), item("peso", 18000, 17500, 4)]))
    ).toBe(true);
  });

  it("rechaza un ítem pieza", () => {
    expect(
      retorno_valido(
        retorno([{ ...item("unidad", 5, 3, 2), unidadMedida: "pieza" }])
      )
    ).toBe(false);
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

describe("registrarRetornoOperacion: guard de peso en B1 (B4)", () => {
  function registrar(r: RetornoDeposito) {
    const cargar = vi.fn(() => ({
      ok: true as const,
      retornos: [] as RetornoDeposito[],
      estado: "valido" as const,
    }));
    const guardar = vi.fn();
    const validar = vi.fn().mockReturnValue(null);
    const error = registrarRetornoOperacion(r, validar, cargar, guardar);
    return { error, cargar, guardar, validar };
  }

  it("un retorno con un ítem peso se rechaza sin leer, validar ni persistir", () => {
    const { error, cargar, guardar, validar } = registrar(
      retorno([item("unidad", 5, 2, 1), item("peso", 18000, 18000, 4)])
    );

    expect(error).toBe(MENSAJE_PESO_NO_OPERABLE);
    expect(cargar).not.toHaveBeenCalled();
    expect(validar).not.toHaveBeenCalled();
    expect(guardar).not.toHaveBeenCalled();
  });

  it("un retorno unidad válido se persiste", () => {
    const r = retorno([item("unidad", 5, 2, 1)]);
    const { error, guardar } = registrar(r);

    expect(error).toBeNull();
    expect(guardar).toHaveBeenCalledWith([r]);
  });
});
