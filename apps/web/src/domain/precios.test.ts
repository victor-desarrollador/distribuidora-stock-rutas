import { describe, expect, it } from "vitest";
import {
  centavos_a_pesos,
  importe_linea_peso,
  importe_linea_peso_centavos,
  precio_a_centavos,
  precio_media_pieza,
  precio_valido,
  subtotal_linea,
  subtotal_linea_centavos,
  subtotal_linea_historica,
  sumar_importes,
  validar_precio,
} from "./precios";
import { kg_a_gramos } from "./peso";

const fiambre = { unidad_medida: "pieza", precio: 10000 } as const;

describe("subtotal de pieza (ADR-003)", () => {
  // precio = 10000 → media = 5000 (10000/2 = 5000)
  it.each([
    [0, 0],
    [1, 5000],
    [2, 10000],
    [3, 15000],
    [4, 20000],
    [5, 25000],
    [8, 40000],
    [9, 45000],
  ])("c=%i → %i", (cantidad, esperado) => {
    expect(subtotal_linea({ ...fiambre, cantidad })).toBe(esperado);
  });

  describe("pieza = 21 → media = 11: c=2 es UNA pieza completa, no dos medias", () => {
    const pieza_21 = { unidad_medida: "pieza", precio: 21 } as const;

    it.each([
      [1, 11],
      [2, 21],
      [3, 32],
    ])("c=%i → %i", (cantidad, esperado) => {
      expect(subtotal_linea({ ...pieza_21, cantidad })).toBe(esperado);
    });

    it("c=2 cobra el precio de pieza (21), nunca 2 medias (22)", () => {
      expect(
        subtotal_linea({
          unidad_medida: "pieza",
          precio: 21,
          cantidad: 2,
        })
      ).toBe(21);
      expect(
        subtotal_linea({
          unidad_medida: "pieza",
          precio: 21,
          cantidad: 2,
        })
      ).not.toBe(22);
    });
  });
});

describe("subtotal de unidad", () => {
  const base = { unidad_medida: "unidad", precio: 2300 } as const;
  it.each([
    [0, 0],
    [1, 2300],
    [10, 23000],
  ])("cantidad %i → %i", (cantidad, esperado) => {
    expect(subtotal_linea({ ...base, cantidad })).toBe(esperado);
  });
});

describe("precio_media_pieza (ADR-003): centavos enteros, .50 sube", () => {
  it.each([
    // bordes de la fracción de la mitad: .49 baja, .495 baja, .50 sube, .505 y .51 suben
    [20.98, 10],
    [20.99, 10],
    [21.0, 11],
    [21.01, 11],
    [21.02, 11],
    // pesos enteros
    [20, 10],
    [21, 11],
    [25, 13],
    // extremos chicos
    [0, 0],
    [0.99, 0],
    [1, 1],
  ])("pieza %d → media %i", (precio_pieza, esperado) => {
    expect(precio_media_pieza(precio_pieza)).toBe(esperado);
  });

  it("coincide con floor((centavos + 100) / 200) calculado en BigInt", () => {
    for (let centavos = 0; centavos <= 100_000; centavos++) {
      const esperado = Number((BigInt(centavos) + 100n) / 200n);
      expect(precio_media_pieza(centavos / 100)).toBe(esperado);
    }
  });

  it("devuelve siempre un peso entero", () => {
    for (const precio_pieza of [0.01, 10.1, 20.98, 21.01, 12345.67]) {
      expect(Number.isInteger(precio_media_pieza(precio_pieza))).toBe(true);
    }
  });

  it("rechaza precios inválidos", () => {
    expect(() => precio_media_pieza(-1)).toThrow(Error);
    expect(() => precio_media_pieza(NaN)).toThrow(Error);
    expect(() => precio_media_pieza(Infinity)).toThrow(Error);
    expect(() => precio_media_pieza(10.001)).toThrow(Error); // > 2 decimales
  });

  it("falla cerrado si el cálculo excede el entero seguro", () => {
    // 90071992547409.9 → MAX_SAFE_INTEGER centavos (válido), pero + 100 ya no es seguro
    expect(precio_a_centavos(90071992547409.9)).toBe(Number.MAX_SAFE_INTEGER);
    expect(() => precio_media_pieza(90071992547409.9)).toThrow(Error);
  });
});

describe("centavos exactos", () => {
  it("hasta 2 decimales, sin error binario — vectores explícitos L3", () => {
    expect(precio_a_centavos(0.01)).toBe(1);
    expect(precio_a_centavos(0.1)).toBe(10);
    expect(precio_a_centavos(0.2)).toBe(20);
    expect(precio_a_centavos(0.29)).toBe(29);
    expect(precio_a_centavos(1.01)).toBe(101);
    expect(precio_a_centavos(12.34)).toBe(1234);
    expect(precio_a_centavos(1234.56)).toBe(123456);
    expect(subtotal_linea({ unidad_medida: "unidad", precio: 0.1, cantidad: 3 })).toBe(0.3);
    // precio = 10.1 → 1010 centavos → media = floor(1110 / 200) = 5 → 1 pieza + 1 media = 10.1 + 5 = 15.10 = 1510 centavos
    expect(
      subtotal_linea_centavos({ unidad_medida: "pieza", precio: 10.1, cantidad: 3 })
    ).toBe(1510);
    expect(sumar_importes([0.1, 0.2])).toBe(0.3);
    expect(centavos_a_pesos(123456)).toBe(1234.56);
  });

  it("rechaza explícitamente más de 2 decimales", () => {
    expect(() => precio_a_centavos(0.001)).toThrow(Error);
    expect(() => precio_a_centavos(1.005)).toThrow(Error);
    expect(() => precio_a_centavos(12.345)).toThrow(Error);
  });
});

describe("fail closed", () => {
  it("rechaza más de 2 decimales sin redondear ni truncar", () => {
    expect(() => precio_a_centavos(10.001)).toThrow(Error);
    expect(() => precio_a_centavos(1.005)).toThrow(Error);
    expect(() => precio_a_centavos(0.001)).toThrow(Error);
    expect(() =>
      subtotal_linea({ unidad_medida: "unidad", precio: 10.5, cantidad: 1.5 })
    ).toThrow(Error);
    expect(() =>
      subtotal_linea({ unidad_medida: "pieza", precio: 10, cantidad: 1.5 })
    ).toThrow(Error);
  });

  it("rechaza precios negativos, NaN e Infinity", () => {
    for (const precio of [-1, Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
      expect(() => precio_a_centavos(precio)).toThrow(Error);
    }
  });

  it("acepta precio 0 (validación mínima vigente)", () => {
    expect(precio_a_centavos(0)).toBe(0);
  });

  it("rechaza cantidades no canónicas", () => {
    for (const cantidad of [-1, 0.5, 1.5, Number.NaN, Number.POSITIVE_INFINITY]) {
      expect(() => subtotal_linea({ ...fiambre, cantidad })).toThrow(Error);
      expect(() =>
        subtotal_linea({ unidad_medida: "unidad", precio: 100, cantidad })
      ).toThrow(Error);
    }
  });

  it("rechaza cantidad con decimales para pieza", () => {
    expect(() =>
      subtotal_linea({ unidad_medida: "pieza", precio: 100, cantidad: 1.5 })
    ).toThrow(Error);
  });

  it("validar_precio y precio_valido solo validan el precio (no hay media configurable)", () => {
    expect(precio_valido(100)).toBe(true);
    expect(precio_valido(-1)).toBe(false);
    expect(() => validar_precio(-1)).toThrow(Error);
  });
});

describe("subtotal_linea_historica (snapshot histórico, fail closed)", () => {
  it("pieza con media en snapshot → válido", () => {
    expect(
      subtotal_linea_historica({
        unidad_medida: "pieza",
        precio: 21,
        precio_media_pieza: 11,
        cantidad: 3,
      })
    ).toBe(32);
  });

  it("usa la media del snapshot, NO la re-deriva con la regla vigente", () => {
    // La regla vigente daría 11 para pieza 21; el snapshot guardó 12 y se respeta.
    expect(
      subtotal_linea_historica({
        unidad_medida: "pieza",
        precio: 21,
        precio_media_pieza: 12,
        cantidad: 3,
      })
    ).toBe(33);
  });

  it("pieza sin media en snapshot → throw", () => {
    expect(() =>
      subtotal_linea_historica({ unidad_medida: "pieza", precio: 100, cantidad: 1 })
    ).toThrow(Error);
  });

  it("unidad sin media → válido", () => {
    expect(
      subtotal_linea_historica({ unidad_medida: "unidad", precio: 2300, cantidad: 2 })
    ).toBe(4600);
  });

  it("unidad con precio_media_pieza → throw", () => {
    expect(() =>
      subtotal_linea_historica({
        unidad_medida: "unidad",
        precio: 2300,
        precio_media_pieza: 1150,
        cantidad: 2,
      })
    ).toThrow(Error);
  });
});

describe("sumar_importes y aritmética monetaria", () => {
  it("suma en centavos evita error binario", () => {
    expect(sumar_importes([0.1, 0.2])).toBe(0.3);
    expect(sumar_importes([0.1, 0.2, 0.3])).toBe(0.6);
    expect(sumar_importes([10.5, 20.25])).toBe(30.75);
  });

  it("rechaza importes inválidos en suma", () => {
    expect(() => sumar_importes([0.1, -0.1])).toThrow(Error);
    expect(() => sumar_importes([NaN])).toThrow(Error);
    expect(() => sumar_importes([Infinity])).toThrow(Error);
  });

  it("overflow controlado", () => {
    // MAX_SAFE_INTEGER = 9007199254740991
    expect(() =>
      sumar_importes([5e15, 5e15])
    ).toThrow(Error);
  });
});

// D-R1 (ADR-005 §2.3.3): N = gramos × centavos/kg está en milésimas de
// centavo; el importe exacto en pesos es N / 100000 y se redondea UNA vez al
// peso entero, con r >= 50000 hacia arriba. En cada caso se anota el importe
// exacto en centavos (N / 1000) para mostrar que no hay redondeo intermedio.
describe("importe_linea_peso (D-R1)", () => {
  it.each([
    // [gramos, precio/kg, exacto en ¢, pesos]
    [1250, 1234.56, "154320", 1543], // §12: $1.543,20 → $1.543
    [1250, 1235.6, "154450", 1545], // §12 empate: $1.544,50 → $1.545
    [1, 1544490, "154449", 1544], // §12: $1.544,49 → $1.544
    [1, 1544990, "154499", 1545], // §12: $1.544,99 → $1.545
    [1, 1544499.99, "154449,999", 1544], // r = 49999 → baja
    [1, 1544500, "154450", 1545], // r = 50000 → sube
    [1, 0.01, "0,001", 0], // 1 g × $0,01/kg = $0,00001
    [1250, 0, "0", 0], // precio 0 admitido (>= 0)
  ])("%i g × $%s/kg = %s ¢ exactos → $%i", (gramos, precio, _exacto, pesos) => {
    expect(importe_linea_peso(gramos, precio)).toBe(pesos);
    expect(importe_linea_peso_centavos(gramos, precio)).toBe(pesos * 100);
  });

  it("un solo redondeo: $1.544,4995 exactos → $1.544 (a centavos primero daría $1.545)", () => {
    // N = 1 × 154449950 → q = 1544, r = 49950 < 50000. Redondear antes a
    // centavos (154449,95 ¢ → 154450 ¢ = $1.544,50) y después a pesos daría
    // $1.545: ese doble redondeo está prohibido.
    expect(importe_linea_peso(1, 1544499.5)).toBe(1544);
  });

  it("§12: dos líneas de 1,250 kg × $1.234,72 suman $3.086, no $3.087", () => {
    // $1.543,40 exactos por línea → $1.543 cada una; el total suma importes
    // ya redondeados y no redondea el total exacto $3.086,80.
    const linea = importe_linea_peso(1250, 1234.72);
    expect(linea).toBe(1543);
    expect(sumar_importes([linea, linea])).toBe(3086);
  });

  it("sin punto flotante: 1,005 kg (1005 g) × $999,99/kg = 100498,995 ¢ → $1.005", () => {
    const gramos = kg_a_gramos("1,005");
    expect(gramos).toBe(1005);
    expect(importe_linea_peso(gramos as number, 999.99)).toBe(1005);
  });

  it.each([0, -1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1])(
    "rechaza gramos %s",
    (gramos) => {
      expect(() => importe_linea_peso(gramos, 1000)).toThrow(Error);
    }
  );

  it.each([10.001, -1, NaN, Infinity])("rechaza precio/kg %s", (precio) => {
    expect(() => importe_linea_peso(1250, precio)).toThrow(Error);
  });

  it("desbordamiento: falla con error, nunca un valor aproximado", () => {
    expect(() =>
      importe_linea_peso(Number.MAX_SAFE_INTEGER, 1_000_000)
    ).toThrow("El importe excede el máximo entero seguro.");
  });
});