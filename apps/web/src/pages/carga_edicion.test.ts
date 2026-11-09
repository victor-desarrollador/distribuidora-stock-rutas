import { describe, expect, it } from "vitest";

import {
  EDICION_INICIAL,
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
  MENSAJE_CARGA_CANTIDAD_PESO,
  MENSAJE_CARGA_CANTIDAD_UNIDAD,
  MENSAJE_CARGA_PRODUCTO_REPETIDO,
  MENSAJE_CARGA_SIN_LINEAS,
  MENSAJE_CARGA_SIN_PRODUCTO,
  type ProductoCarga,
} from "./jornadas_carga";
import fuente from "./carga_edicion.ts?raw";

const LECHE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const JAMON = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const VIEJO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const CATALOGO: ProductoCarga[] = [
  { id: LECHE, codigo: "L1", nombre: "Leche entera", formaVenta: "unidad", activo: true },
  { id: JAMON, codigo: null, nombre: "Jamón cocido", formaVenta: "peso", activo: true },
  { id: VIEJO, codigo: null, nombre: "Queso discontinuado", formaVenta: "unidad", activo: false },
];

const con = (...lineas: Array<[string, string]>): EdicionCarga => ({
  lineas: lineas.map(([productoId, texto]) => ({ productoId, texto })),
  revisando: false,
  mostrarErrores: false,
});

describe("edición de líneas", () => {
  it("arranca con una línea vacía, sin revisión ni errores visibles", () => {
    expect(EDICION_INICIAL).toEqual({ lineas: [{ productoId: "", texto: "" }], revisando: false, mostrarErrores: false });
    expect(Object.isFrozen(EDICION_INICIAL)).toBe(true);
  });

  it("agrega y quita líneas; nunca queda sin ninguna", () => {
    let e = agregarLinea(EDICION_INICIAL);
    expect(e.lineas).toHaveLength(2);
    e = quitarLinea(quitarLinea(e, 0), 0);
    expect(e.lineas).toEqual([{ productoId: "", texto: "" }]);
    expect(quitarLinea(e, 5)).toBe(e);
  });

  it("cambiar el producto borra la cantidad (puede cambiar de unidades a kg)", () => {
    const e = cambiarProducto(con([LECHE, "24"]), 0, JAMON);
    expect(e.lineas[0]).toEqual({ productoId: JAMON, texto: "" });
    const igual = con([LECHE, "24"]);
    expect(cambiarProducto(igual, 0, LECHE)).toBe(igual);
  });

  it("cualquier cambio vuelve de la revisión a la edición", () => {
    const enRevision = revisar(con([LECHE, "24"]), CATALOGO);
    expect(enRevision.revisando).toBe(true);
    expect(cambiarTexto(enRevision, 0, "25").revisando).toBe(false);
    expect(agregarLinea(enRevision).revisando).toBe(false);
    expect(quitarLinea(enRevision, 0).revisando).toBe(false);
    expect(cambiarProducto(enRevision, 0, JAMON).revisando).toBe(false);
    expect(volverAEditar(enRevision).revisando).toBe(false);
  });

  it("no muta el estado anterior", () => {
    const e = con([LECHE, "24"]);
    cambiarTexto(e, 0, "1");
    expect(e.lineas[0].texto).toBe("24");
  });
});

describe("revisar: sólo pasa al resumen con líneas válidas", () => {
  it("válida: revisando y entrada idéntica a lo escrito", () => {
    const e = revisar(con([LECHE, "24"], [JAMON, "3,250"]), CATALOGO);
    expect(e).toMatchObject({ revisando: true, mostrarErrores: true });
    expect(entradaDe(e)).toEqual({
      lineas: [
        { productoId: LECHE, texto: "24" },
        { productoId: JAMON, texto: "3,250" },
      ],
    });
  });

  it("inválida: queda en edición y desde ahora muestra errores", () => {
    expect(revisar(con([LECHE, "0"]), CATALOGO)).toMatchObject({ revisando: false, mostrarErrores: true });
  });
});

describe("errorEdicion: mismo mensaje que el controlador y la línea a marcar", () => {
  it.each([
    [con([LECHE, "1"], ["", "2"]), MENSAJE_CARGA_SIN_PRODUCTO(2), 1],
    [con([LECHE, "1"], [JAMON, "1,2345"]), MENSAJE_CARGA_CANTIDAD_PESO(2), 1],
    [con([LECHE, "1,5"], [JAMON, "1"]), MENSAJE_CARGA_CANTIDAD_UNIDAD(1), 0],
    [con([JAMON, "1"], [LECHE, "1"], [JAMON, "2"]), MENSAJE_CARGA_PRODUCTO_REPETIDO(3), 2],
  ] as const)("caso %#", (e, mensaje, linea) => {
    expect(errorEdicion(e, CATALOGO)).toEqual({ mensaje, linea });
  });

  it("sin líneas: error de la lista, sin línea", () => {
    expect(errorEdicion({ ...EDICION_INICIAL, lineas: [] }, CATALOGO)).toEqual({
      mensaje: MENSAJE_CARGA_SIN_LINEAS,
      linea: null,
    });
  });

  it("válida: sin error", () => {
    expect(errorEdicion(con([LECHE, "24"]), CATALOGO)).toBeNull();
  });
});

describe("productosParaLinea", () => {
  it("sólo activos, sin los elegidos en otras líneas, ordenados por nombre", () => {
    const e = con([LECHE, "1"], ["", ""]);
    expect(productosParaLinea(e, 1, CATALOGO).map((p) => p.id)).toEqual([JAMON]);
    expect(productosParaLinea(e, 0, CATALOGO).map((p) => p.id)).toEqual([JAMON, LECHE]);
  });
});

describe("límites", () => {
  it("no llama RPC, no genera claves ni usa almacenamiento del navegador", () => {
    const codigo = fuente.replace(/\/\/.*$/gm, "");
    expect(codigo).not.toMatch(/localStorage|sessionStorage|indexedDB|\.rpc\(|randomUUID|nuevaClaveIdempotencia|ejecutar/);
  });
});
