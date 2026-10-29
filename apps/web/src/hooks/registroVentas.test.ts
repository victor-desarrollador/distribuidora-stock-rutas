// Frontera autoritativa de ventas (AUD-001): pruebas contra
// `registrarVentaPersistida` real sobre localStorage simulado.
//
// En todo rechazo: cero escrituras, ventas/jornadas/movimientos crudos
// intactos y `alGuardar` sin invocar. En todo éxito: exactamente una
// escritura (clave de ventas) y `alGuardar` una vez con el ledger guardado.
import { describe, expect, it, beforeEach, vi } from "vitest";
import {
  MENSAJE_VENTA_INVALIDA,
  MENSAJE_VENTA_NO_GUARDADA,
  registrarVentaPersistida,
} from "./registroVentas";
import { leerVentas } from "./ventasStorage";
import { leerJornadasDiscriminado } from "./useJornadas";
import { leerMovimientosDiscriminado } from "./useMovimientos";
import { CLAVES_STORAGE } from "../data/clavesStorage";
import type { ItemCarga, Jornada } from "../data/mockJornadas";
import type { MovimientoReparto } from "../data/mockMovimientos";
import type { DetalleVenta, Venta } from "../data/mockVentas";
import {
  MENSAJE_STOCK_JORNADA_NO_CALCULABLE,
  MENSAJE_VENTA_CARGA_INCONSISTENTE,
  MENSAJE_VENTA_SALIDAS_SUPERAN_CARGA,
} from "../domain/movimientos";
import { importe_linea_peso } from "../domain/precios";
import {
  MENSAJE_VENTA_MIXTA_NO_HABILITADA,
  MENSAJE_VENTA_PRODUCTO_REPETIDO,
} from "../domain/venta";

const crearMockLocalStorage = () => {
  const store = new Map<string, string>();
  return {
    getItem: vi.fn((key: string) => store.get(key) ?? null),
    setItem: vi.fn((key: string, value: string) => {
      store.set(key, value);
    }),
    removeItem: vi.fn((key: string) => {
      store.delete(key);
    }),
    clear: vi.fn(() => {
      store.clear();
    }),
    get length() {
      return store.size;
    },
    key: vi.fn((index: number) => Array.from(store.keys())[index] ?? null),
    _store: store,
  };
};

let mockLS: ReturnType<typeof crearMockLocalStorage>;

beforeEach(() => {
  mockLS = crearMockLocalStorage();
  Object.defineProperty(globalThis, "localStorage", {
    value: mockLS,
    writable: true,
  });
});

const CV = CLAVES_STORAGE.ventas;
const CJ = CLAVES_STORAGE.jornadas;
const CM = CLAVES_STORAGE.movimientos;
const MAX = Number.MAX_SAFE_INTEGER;
const PRECIO_JAMON_KG = 12500;

// --- Fixtures ---

const lineaYogur = (cantidad: number): DetalleVenta => ({
  productoId: 1,
  nombreProducto: "Yogur",
  unidadMedida: "unidad",
  cantidad,
  precioUnitario: 100,
  subtotal: cantidad * 100,
});

const lineaJamon = (gramos: number): DetalleVenta => ({
  productoId: 4,
  nombreProducto: "Jamón cocido",
  unidadMedida: "peso",
  cantidad: gramos,
  precioUnitario: PRECIO_JAMON_KG,
  subtotal: importe_linea_peso(gramos, PRECIO_JAMON_KG),
});

const venta = (items: DetalleVenta[], extra: Partial<Venta> = {}): Venta => ({
  id: "v-nueva",
  jornadaId: "j1",
  camionId: 1,
  clienteId: 1,
  nombreCliente: "Almacén",
  fecha: "2026-10-28T10:00:00.000Z",
  medioPago: "efectivo",
  items,
  total: items.reduce((suma, item) => suma + item.subtotal, 0),
  ...extra,
});

const cargaYogur = (cantidad: number): ItemCarga => ({
  productoId: 1,
  nombreProducto: "Yogur",
  unidadMedida: "unidad",
  cantidad,
  precioReferencia: 100,
});

const cargaJamon = (gramos: number): ItemCarga => ({
  productoId: 4,
  nombreProducto: "Jamón cocido",
  unidadMedida: "peso",
  cantidad: gramos,
  precioReferencia: PRECIO_JAMON_KG,
});

const jornada = (items: ItemCarga[], extra: Partial<Jornada> = {}): Jornada => ({
  id: "j1",
  camionId: 1,
  chofer: "Chofer",
  zona: "Zona",
  fechaCreacion: "2026-10-28T08:00:00.000Z",
  fechaSalida: "2026-10-28T09:00:00.000Z",
  estado: "abierta",
  items,
  ...extra,
});

const mermaYogur = (cantidad: number): MovimientoReparto => ({
  id: "m1",
  jornadaId: "j1",
  camionId: 1,
  fecha: "2026-10-28T09:30:00.000Z",
  motivo: "Envase roto o dañado",
  tipo: "merma",
  producto: {
    productoId: 1,
    nombreProducto: "Yogur",
    unidadMedida: "unidad",
    cantidad,
  },
  clienteId: null,
  nombreCliente: null,
});

/** Siembra ledgers válidos y verifica que los lectores reales los acepten. */
function sembrar(datos: {
  ventas?: Venta[];
  jornadas?: Jornada[];
  movimientos?: MovimientoReparto[];
}) {
  if (datos.ventas) mockLS._store.set(CV, JSON.stringify(datos.ventas));
  if (datos.jornadas) mockLS._store.set(CJ, JSON.stringify(datos.jornadas));
  if (datos.movimientos) mockLS._store.set(CM, JSON.stringify(datos.movimientos));
  // Precondición: el escenario es legible (no es storage corrupto).
  expect(leerVentas().ok).toBe(true);
  expect(leerJornadasDiscriminado().ok).toBe(true);
  expect(leerMovimientosDiscriminado().ok).toBe(true);
  mockLS.getItem.mockClear();
  mockLS.setItem.mockClear();
}

const crudos = () => [CV, CJ, CM].map((clave) => mockLS._store.get(clave));

function rechazaSinEscribir(v: Venta, esperado: string | RegExp) {
  const antes = crudos();
  const alGuardar = vi.fn();

  const error = registrarVentaPersistida(v, alGuardar);

  if (typeof esperado === "string") {
    expect(error).toBe(esperado);
  } else {
    expect(error).toMatch(esperado);
  }
  expect(mockLS.setItem).not.toHaveBeenCalled();
  expect(alGuardar).not.toHaveBeenCalled();
  expect(crudos()).toEqual(antes);
}

function aceptaConUnaEscritura(v: Venta, previas: Venta[] = []) {
  const alGuardar = vi.fn();

  expect(registrarVentaPersistida(v, alGuardar)).toBeNull();

  expect(mockLS.setItem).toHaveBeenCalledTimes(1);
  expect(mockLS.setItem.mock.calls[0][0]).toBe(CV);
  const guardado = JSON.parse(mockLS._store.get(CV) as string);
  expect(guardado).toEqual([...previas, v]);
  expect(alGuardar).toHaveBeenCalledTimes(1);
  expect(alGuardar).toHaveBeenCalledWith(guardado);
}

const clavesLeidas = () => mockLS.getItem.mock.calls.map(([clave]) => clave);

// --- Pruebas ---

describe("AUD-001: regresión del bypass (escenarios del PoC)", () => {
  it("1 unidad cargada y venta de 2: se rechaza sin escribir (antes persistía)", () => {
    sembrar({ jornadas: [jornada([cargaYogur(1)])], movimientos: [] });
    rechazaSinEscribir(venta([lineaYogur(2)]), "Stock insuficiente de Yogur.");
  });

  it("sin Jornadas ni Movimientos sembrados: se rechaza sin escribir (antes persistía)", () => {
    rechazaSinEscribir(
      venta([lineaYogur(1)]),
      "No se puede registrar: La jornada seleccionada ya no existe."
    );
    expect(mockLS._store.has(CV)).toBe(false);
  });

  it("la frontera relee Ventas, Jornadas y Movimientos por sí misma", () => {
    sembrar({ jornadas: [jornada([cargaYogur(5)])], movimientos: [] });
    aceptaConUnaEscritura(venta([lineaYogur(1)]));
    expect(clavesLeidas()).toEqual(expect.arrayContaining([CV, CJ, CM]));
  });
});

describe("stock exacto por unidad y por peso", () => {
  it("unidad: stock exacto se acepta con una escritura", () => {
    sembrar({ jornadas: [jornada([cargaYogur(3)])] });
    aceptaConUnaEscritura(venta([lineaYogur(3)]));
  });

  it("unidad: +1 se rechaza", () => {
    sembrar({ jornadas: [jornada([cargaYogur(3)])] });
    rechazaSinEscribir(venta([lineaYogur(4)]), "Stock insuficiente de Yogur.");
  });

  it("peso: 1250 g exactos se aceptan", () => {
    sembrar({ jornadas: [jornada([cargaJamon(1250)])] });
    aceptaConUnaEscritura(venta([lineaJamon(1250)]));
  });

  it("peso: +1 g se rechaza", () => {
    sembrar({ jornadas: [jornada([cargaJamon(1250)])] });
    rechazaSinEscribir(venta([lineaJamon(1251)]), "Stock insuficiente de Jamón cocido.");
  });

  it("conserva el historial y agrega la venta al final", () => {
    const previa = venta([lineaYogur(1)], { id: "v-previa" });
    sembrar({ ventas: [previa], jornadas: [jornada([cargaYogur(3)])] });
    aceptaConUnaEscritura(venta([lineaYogur(2)]), [previa]);
  });
});

describe("unicidad de producto por venta nueva (AUD-B3-01)", () => {
  const PRECIO_ABUSO = 499.99;
  const jamonA = (gramos: number): DetalleVenta => ({
    ...lineaJamon(gramos),
    precioUnitario: PRECIO_ABUSO,
    subtotal: importe_linea_peso(gramos, PRECIO_ABUSO),
  });
  const jornadaJamonA = () =>
    jornada([{ ...cargaJamon(1000), precioReferencia: PRECIO_ABUSO }]);

  it("una línea de 1000 g a $499,99/kg se acepta con total $500", () => {
    sembrar({ jornadas: [jornadaJamonA()] });
    const v = venta([jamonA(1000)]);
    expect(v.total).toBe(500);
    aceptaConUnaEscritura(v);
  });

  it("1000 líneas de 1 g del mismo producto se rechazan sin leer ni escribir", () => {
    sembrar({ jornadas: [jornadaJamonA()] });
    const fragmentada = venta(Array.from({ length: 1000 }, () => jamonA(1)));
    expect(fragmentada.total).toBe(0); // el abuso: 1 kg por $0
    rechazaSinEscribir(fragmentada, MENSAJE_VENTA_PRODUCTO_REPETIDO);
    expect(mockLS.getItem).not.toHaveBeenCalled();
    expect(mockLS._store.has(CV)).toBe(false);
  });

  it("dos líneas del mismo producto peso se rechazan aunque el stock alcance", () => {
    sembrar({ jornadas: [jornada([cargaJamon(1250)])] });
    rechazaSinEscribir(
      venta([lineaJamon(1000), lineaJamon(250)]),
      MENSAJE_VENTA_PRODUCTO_REPETIDO
    );
  });

  it("dos líneas del mismo producto unidad se rechazan aunque el stock alcance", () => {
    sembrar({ jornadas: [jornada([cargaYogur(2)])] });
    rechazaSinEscribir(
      venta([lineaYogur(1), lineaYogur(1)]),
      MENSAJE_VENTA_PRODUCTO_REPETIDO
    );
  });

  it("mismo productoId con unidad y peso se rechaza sin escribir (ADR-006 caso 4)", () => {
    // La ADR exige el rechazo, no un mensaje: el guard de venta mixta corre
    // antes que el de producto repetido y es el que responde.
    sembrar({ jornadas: [jornada([cargaJamon(1250)])] });
    const jamonPorUnidad: DetalleVenta = {
      ...lineaYogur(1),
      productoId: 4,
      nombreProducto: "Jamón cocido",
    };
    rechazaSinEscribir(
      venta([lineaJamon(250), jamonPorUnidad]),
      MENSAJE_VENTA_MIXTA_NO_HABILITADA
    );
    expect(mockLS.getItem).not.toHaveBeenCalled();
  });

  it("dos productos distintos en una venta siguen permitidos", () => {
    const cargaLeche: ItemCarga = { ...cargaYogur(5), productoId: 2, nombreProducto: "Leche" };
    const lineaLeche: DetalleVenta = { ...lineaYogur(2), productoId: 2, nombreProducto: "Leche" };
    sembrar({ jornadas: [jornada([cargaYogur(5), cargaLeche])] });
    aceptaConUnaEscritura(venta([lineaYogur(1), lineaLeche]));
  });

  it("una venta histórica con líneas repetidas sigue legible y su consumo se suma (exacto)", () => {
    const historica = venta([lineaYogur(1), lineaYogur(1)], { id: "v-historica" });
    sembrar({ ventas: [historica], jornadas: [jornada([cargaYogur(3)])] });
    aceptaConUnaEscritura(venta([lineaYogur(1)]), [historica]);
  });

  it("una venta histórica con líneas repetidas cuenta para el stock (+1 se rechaza)", () => {
    const historica = venta([lineaYogur(1), lineaYogur(1)], { id: "v-historica" });
    sembrar({ ventas: [historica], jornadas: [jornada([cargaYogur(3)])] });
    rechazaSinEscribir(venta([lineaYogur(2)]), "Stock insuficiente de Yogur.");
  });
});

describe("concurrencia: ventas y movimientos registrados después del render", () => {
  it("una venta de la misma jornada ya registrada consume stock", () => {
    const concurrente = venta([lineaYogur(2)], { id: "v-concurrente" });
    sembrar({ ventas: [concurrente], jornadas: [jornada([cargaYogur(2)])] });
    rechazaSinEscribir(venta([lineaYogur(1)]), "Stock insuficiente de Yogur.");
  });

  it("una merma ya registrada consume stock", () => {
    sembrar({ jornadas: [jornada([cargaYogur(2)])], movimientos: [mermaYogur(2)] });
    rechazaSinEscribir(venta([lineaYogur(1)]), "Stock insuficiente de Yogur.");
  });
});

describe("inconsistencias de la jornada", () => {
  it("saldo histórico negativo de OTRO producto bloquea la venta", () => {
    const previa = venta([lineaJamon(1300)], { id: "v-previa" });
    sembrar({
      ventas: [previa],
      jornadas: [jornada([cargaYogur(5), cargaJamon(1250)])],
    });
    rechazaSinEscribir(venta([lineaYogur(1)]), MENSAJE_VENTA_SALIDAS_SUPERAN_CARGA);
  });

  it("carga con unidades contradictorias se rechaza aunque no se venda ese producto", () => {
    sembrar({
      jornadas: [
        jornada([
          cargaYogur(5),
          cargaJamon(1250),
          { ...cargaJamon(3), unidadMedida: "unidad" },
        ]),
      ],
    });
    rechazaSinEscribir(venta([lineaYogur(1)]), MENSAJE_VENTA_CARGA_INCONSISTENTE);
  });

  it("overflow al acumular la carga → no calculable", () => {
    sembrar({ jornadas: [jornada([cargaYogur(MAX), cargaYogur(1)])] });
    rechazaSinEscribir(venta([lineaYogur(1)]), MENSAJE_STOCK_JORNADA_NO_CALCULABLE);
  });

  it("overflow al acumular ventas previas → no calculable", () => {
    const enorme = (id: string): Venta => ({
      ...venta([{ ...lineaYogur(1), cantidad: MAX, precioUnitario: 0, subtotal: 0 }]),
      id,
      total: 0,
    });
    sembrar({
      ventas: [enorme("v-a"), enorme("v-b")],
      jornadas: [jornada([cargaYogur(5)])],
    });
    rechazaSinEscribir(venta([lineaYogur(1)]), MENSAJE_STOCK_JORNADA_NO_CALCULABLE);
  });

  it("overflow en el pedido nuevo (cantidad × precio inseguro): lo frena venta_nueva_valida sin leer jornadas", () => {
    // Una sola línea: con AUD-B3-01 dos líneas del mismo producto ya se
    // rechazan antes. La agrupación segura se prueba en movimientos.test.ts.
    sembrar({ jornadas: [jornada([cargaYogur(5)])] });
    rechazaSinEscribir(venta([lineaYogur(MAX)]), MENSAJE_VENTA_INVALIDA);
    expect(clavesLeidas()).not.toContain(CJ);
  });

  it("producto no cargado se rechaza", () => {
    sembrar({ jornadas: [jornada([cargaYogur(5)])] });
    const leche: DetalleVenta = { ...lineaYogur(1), productoId: 2, nombreProducto: "Leche" };
    rechazaSinEscribir(venta([leche]), "Leche no está cargado en el camión.");
  });

  it("unidad incompatible con la cargada se rechaza", () => {
    sembrar({ jornadas: [jornada([cargaJamon(1250)])] });
    const jamonPorUnidad: DetalleVenta = {
      ...lineaYogur(1),
      productoId: 4,
      nombreProducto: "Jamón cocido",
    };
    rechazaSinEscribir(
      venta([jamonPorUnidad]),
      "La forma de venta de Jamón cocido no coincide con la cargada en la jornada."
    );
  });
});

describe("jornada autoritativa", () => {
  it("jornada inexistente se rechaza", () => {
    sembrar({ jornadas: [jornada([cargaYogur(5)], { id: "otra" })] });
    rechazaSinEscribir(
      venta([lineaYogur(1)]),
      "No se puede registrar: La jornada seleccionada ya no existe."
    );
  });

  it("jornada cerrada se rechaza", () => {
    sembrar({
      jornadas: [
        jornada([cargaYogur(5)], {
          estado: "cerrada",
          cierre: {
            fecha: "2026-10-28T18:00:00.000Z",
            conteos: {},
            efectivoEntregado: 0,
            efectivoEsperado: 0,
            transferenciasInformadas: 0,
            ventasCuentaCorriente: 0,
            observaciones: "",
          },
        }),
      ],
    });
    rechazaSinEscribir(
      venta([lineaYogur(1)]),
      "No se puede registrar: La jornada ya no está abierta. No se puede registrar una nueva operación en ella."
    );
  });

  it("venta de otro camión se rechaza", () => {
    sembrar({ jornadas: [jornada([cargaYogur(5)])] });
    rechazaSinEscribir(
      venta([lineaYogur(1)], { camionId: 2 }),
      "No se puede registrar: La jornada cambió de camión. Actualizá la pantalla antes de continuar."
    );
  });
});

describe("storage corrupto: falla cerrado sin escribir", () => {
  it.each([
    ["ventas", CV],
    ["jornadas", CJ],
    ["movimientos", CM],
  ])("%s corrupto", (_nombre, clave) => {
    sembrar({ jornadas: [jornada([cargaYogur(5)])], movimientos: [] });
    mockLS._store.set(clave, "{roto");
    rechazaSinEscribir(venta([lineaYogur(1)]), /^No se puede registrar: /);
    expect(mockLS._store.get(clave)).toBe("{roto");
  });
});

describe("validaciones previas a la lectura de stock", () => {
  it("ID duplicado se rechaza sin leer jornadas ni movimientos", () => {
    const existente = venta([lineaYogur(1)]);
    sembrar({ ventas: [existente], jornadas: [jornada([cargaYogur(5)])] });
    rechazaSinEscribir(venta([lineaYogur(1)]), "La venta ya fue registrada.");
    expect(clavesLeidas()).toEqual([CV]);
  });

  it("venta mixta se rechaza sin leer ningún ledger", () => {
    sembrar({ jornadas: [jornada([cargaYogur(5), cargaJamon(1250)])] });
    rechazaSinEscribir(
      venta([lineaYogur(1), lineaJamon(250)]),
      MENSAJE_VENTA_MIXTA_NO_HABILITADA
    );
    expect(mockLS.getItem).not.toHaveBeenCalled();
  });

  it("venta nueva sin ítems (total 0) se rechaza sin leer ningún ledger", () => {
    sembrar({ jornadas: [jornada([cargaYogur(5)])] });
    rechazaSinEscribir(venta([]), MENSAJE_VENTA_INVALIDA);
    expect(mockLS.getItem).not.toHaveBeenCalled();
  });
});

describe("snapshot estable y alGuardar", () => {
  it("valida y persiste un único snapshot aunque `items` sea un getter cambiante", () => {
    sembrar({ jornadas: [jornada([cargaYogur(1)])] });
    const valida = venta([lineaYogur(1)]);
    let lecturas = 0;
    const tramposa = { ...valida } as Venta;
    Object.defineProperty(tramposa, "items", {
      enumerable: true,
      get: () => (lecturas++ === 0 ? valida.items : [lineaYogur(50)]),
    });

    expect(registrarVentaPersistida(tramposa)).toBeNull();
    // El getter se leyó una sola vez (el snapshot); lo persistido es ese valor.
    expect(lecturas).toBe(1);
    expect(mockLS.setItem).toHaveBeenCalledTimes(1);
    expect(JSON.parse(mockLS._store.get(CV) as string)).toEqual([valida]);
  });

  it("alGuardar se invoca sólo después de escribir; si lanza, no se informa 'no guardada'", () => {
    sembrar({ jornadas: [jornada([cargaYogur(5)])] });
    const v = venta([lineaYogur(1)]);
    const alGuardar = vi.fn(() => {
      throw new Error("fallo de UI");
    });

    expect(() => registrarVentaPersistida(v, alGuardar)).toThrow("fallo de UI");
    expect(mockLS.setItem).toHaveBeenCalledTimes(1);
    expect(JSON.parse(mockLS._store.get(CV) as string)).toEqual([v]);
  });

  it("si setItem falla: mensaje de no guardada y alGuardar sin invocar", () => {
    sembrar({ jornadas: [jornada([cargaYogur(5)])] });
    mockLS.setItem.mockImplementationOnce(() => {
      throw new Error("QuotaExceededError");
    });
    const alGuardar = vi.fn();

    expect(registrarVentaPersistida(venta([lineaYogur(1)]), alGuardar)).toBe(
      MENSAJE_VENTA_NO_GUARDADA
    );
    expect(alGuardar).not.toHaveBeenCalled();
    expect(mockLS._store.has(CV)).toBe(false);
  });
});
