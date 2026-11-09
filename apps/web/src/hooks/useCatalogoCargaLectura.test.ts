// FE-1F (H-01) — el catálogo de la carga pertenece al contexto de autorización
// con que se leyó. Sin DOM de pruebas en el proyecto: se prueban la decisión de
// qué mostrar (`catalogoParaContexto`) y el lector por generaciones
// (`crearLectorCatalogo`), que son lo que el hook usa en cada render y efecto.

import { describe, expect, it, vi } from "vitest";

import type { ProductoCatalogo, ResultadoProductos } from "../lib/productos";
import {
  catalogoParaContexto,
  crearLectorCatalogo,
  type LecturaCatalogo,
  type PuertoLecturaProductos,
} from "./useCatalogoCargaLectura";
import fuenteCatalogo from "./useCatalogoCargaLectura.ts?raw";
import fuenteJornadas from "../pages/Jornadas.tsx?raw";

const CA = JSON.stringify(["u", "empresa-a", "dueno"]);
const CB = JSON.stringify(["u", "empresa-b", "dueno"]);

function producto(id: string, nombre: string): ProductoCatalogo {
  return { id, codigo: null, nombre, categoria: "Lácteos", formaVenta: "unidad", precio: 1, stockMinimo: 0, activo: true };
}
const DE_A = [producto("pa", "Producto de A")];
const DE_B = [producto("pb", "Producto de B")];

// Puerto con respuestas que el test resuelve a mano (orden arbitrario).
function puertoManual() {
  const pendientes: ((r: ResultadoProductos<ProductoCatalogo[]>) => void)[] = [];
  const rechazos: ((e: unknown) => void)[] = [];
  const puerto: PuertoLecturaProductos = {
    listar: vi.fn(
      () =>
        new Promise<ResultadoProductos<ProductoCatalogo[]>>((ok, mal) => {
          pendientes.push(ok);
          rechazos.push(mal);
        })
    ),
  };
  return { puerto, pendientes, rechazos };
}
const tick = () => new Promise((r) => setTimeout(r, 0));

describe("FE-1F: qué catálogo se muestra para el contexto vigente", () => {
  const leidoEnA: LecturaCatalogo = { contexto: CA, catalogo: DE_A };

  it("mismo contexto: el catálogo leído", () => {
    expect(catalogoParaContexto(leidoEnA, CA)).toBe(DE_A);
  });

  it("otro contexto (misma persona, otra empresa): nunca el de A, ni siquiera un render", () => {
    expect(catalogoParaContexto(leidoEnA, CB)).toBe("cargando");
  });

  it("sin contexto (pendiente, bloqueado, error, sin gestión): null, falla cerrado", () => {
    expect(catalogoParaContexto(leidoEnA, null)).toBeNull();
  });
});

describe("FE-1F: lector del catálogo por generaciones", () => {
  it("publica la lectura etiquetada con su contexto", async () => {
    const m = puertoManual();
    const publicadas: LecturaCatalogo[] = [];
    crearLectorCatalogo(m.puerto, (l) => publicadas.push(l)).leer(CA);
    m.pendientes[0]({ ok: true, datos: DE_A });
    await tick();
    expect(publicadas).toEqual([{ contexto: CA, catalogo: DE_A }]);
    expect(Object.isFrozen(publicadas[0].catalogo)).toBe(true);
  });

  it("cambio de contexto: la respuesta tardía de A se descarta y sólo se publica B", async () => {
    const m = puertoManual();
    const publicadas: LecturaCatalogo[] = [];
    const lector = crearLectorCatalogo(m.puerto, (l) => publicadas.push(l));
    lector.leer(CA);
    lector.invalidar(); // efecto de A limpiado al cambiar el contexto
    lector.leer(CB);
    m.pendientes[1]({ ok: true, datos: DE_B });
    m.pendientes[0]({ ok: true, datos: DE_A }); // llega tarde
    await tick();
    expect(publicadas).toEqual([{ contexto: CB, catalogo: DE_B }]);
    expect(JSON.stringify(publicadas)).not.toContain("Producto de A");
  });

  it("invalidar sin nueva lectura (contexto perdido): no se publica nada", async () => {
    const m = puertoManual();
    const publicar = vi.fn();
    const lector = crearLectorCatalogo(m.puerto, publicar);
    lector.leer(CA);
    lector.invalidar();
    m.pendientes[0]({ ok: true, datos: DE_A });
    await tick();
    expect(publicar).not.toHaveBeenCalled();
  });

  it("error de lectura o rechazo: null (falla cerrado, sin datos viejos)", async () => {
    const m = puertoManual();
    const publicadas: LecturaCatalogo[] = [];
    const lector = crearLectorCatalogo(m.puerto, (l) => publicadas.push(l));
    lector.leer(CA);
    m.pendientes[0]({ ok: false, error: "x" });
    await tick();
    lector.leer(CA);
    m.rechazos[1](new Error("red"));
    await tick();
    expect(publicadas).toEqual([
      { contexto: CA, catalogo: null },
      { contexto: CA, catalogo: null },
    ]);
  });
});

describe("FE-1F: sin escrituras ni persistencia", () => {
  const sinComentarios = (t: string) => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");

  it.each([
    ["useCatalogoCargaLectura.ts", fuenteCatalogo],
    ["Jornadas.tsx", fuenteJornadas],
  ])("%s: sin almacenamiento del navegador, RPC, registrar_carga ni controlador de carga", (_n, fuente) => {
    expect(sinComentarios(fuente)).not.toMatch(
      /localStorage|sessionStorage|indexedDB|\.rpc\(|registrar_carga|crearControladorCarga|definicionCarga|randomUUID/
    );
  });

  it("el hook del catálogo recibe el contexto de autorización, no un booleano ni sólo el usuario", () => {
    expect(sinComentarios(fuenteJornadas)).toMatch(
      /useCatalogoCargaLectura\(contextoAutorizacionCarga\(sesion\)\)/
    );
  });
});
