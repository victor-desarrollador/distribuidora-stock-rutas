import { describe, expect, it } from "vitest";

import { ROLES } from "../../auth/roles";
import { itemsMenuPorRol, type ItemMenu } from "./menu";

const rutas = (items: ItemMenu[]) => items.map((i) => i.ruta);
const DEMO: ItemMenu = { nombre: "Jornadas (demo)", icono: (() => null) as ItemMenu["icono"], ruta: "/demo/jornadas" };

describe("itemsMenuPorRol", () => {
  it("el vendedor/piloto ve «Mi jornada» y sólo sus rutas", () => {
    const items = itemsMenuPorRol("vendedor_piloto");
    expect(rutas(items)).toEqual(["/clientes", "/jornadas"]);
    expect(items.find((i) => i.ruta === "/jornadas")?.nombre).toBe("Mi jornada");
  });

  it("dueño y encargado ven «Jornadas»; no existe ruta de Configuración", () => {
    const dueno = itemsMenuPorRol("dueno");
    const encargado = itemsMenuPorRol("encargado");
    expect(dueno.find((i) => i.ruta === "/jornadas")?.nombre).toBe("Jornadas");
    expect(encargado.find((i) => i.ruta === "/jornadas")?.nombre).toBe("Jornadas");
    expect(rutas(dueno)).not.toContain("/configuracion-demo");
    expect(rutas(encargado)).not.toContain("/configuracion-demo");
  });

  it("el acceso demo sólo se agrega si se pasa como extra explícito", () => {
    for (const rol of ["dueno", "encargado"] as const) {
      const r = rutas(itemsMenuPorRol(rol, [DEMO]));
      expect(r.indexOf("/demo/jornadas")).toBe(r.indexOf("/jornadas") + 1);
    }
    expect(rutas(itemsMenuPorRol("vendedor_piloto", [DEMO]))).not.toContain("/demo/jornadas");
    expect(rutas(itemsMenuPorRol(null, [DEMO]))).toEqual([]);
    expect(rutas(itemsMenuPorRol(undefined, [DEMO]))).toEqual([]);
  });

  it("sin el extra no hay entrada demo (producción)", () => {
    for (const rol of ROLES) expect(rutas(itemsMenuPorRol(rol))).not.toContain("/demo/jornadas");
  });

  it("el vendedor no obtiene ninguna ruta de gestión", () => {
    const gestionSolo = ["/productos", "/stock", "/camiones"];
    const r = rutas(itemsMenuPorRol("vendedor_piloto", [DEMO]));
    for (const g of gestionSolo) expect(r).not.toContain(g);
  });
});
