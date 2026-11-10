// Pruebas de la ESTRUCTURA de App.tsx leyendo su fuente (?raw): son una
// comprobación estática de que las guardas están donde se espera, NO un
// montaje del router ni una prueba de comportamiento. El comportamiento de
// ProtectedRoute está en components/ProtectedRoute.test.tsx.
import { describe, expect, it } from "vitest";

import fuenteApp from "./App.tsx?raw";
import { ROLES_GESTION, ROLES_TODOS } from "./auth/roles";

const sinComentarios = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
const app = sinComentarios(fuenteApp);

const RUTAS_RETIRADAS = [
  "/demo/jornadas",
  "/autoventa",
  "/ventas",
  "/movimientos",
  "/rendicion",
  "/retornos",
  "/cuentas",
  "/configuracion-demo",
];

describe("App.tsx: rutas retiradas (dependían de localStorage de negocio)", () => {
  it("roles: todos incluye al vendedor; gestión no", () => {
    expect(ROLES_TODOS).toContain("vendedor_piloto");
    expect(ROLES_GESTION).not.toContain("vendedor_piloto");
  });

  it.each(RUTAS_RETIRADAS)("no registra la ruta %s", (ruta) => {
    expect(app).not.toContain(`path="${ruta}"`);
    expect(app).not.toContain(`path={${JSON.stringify(ruta)}}`);
    expect(app).not.toContain(`Navigate to="${ruta}"`);
    expect(app).not.toContain(`to="${ruta}"`);
  });

  it("no importa ni registra JornadasDemo", () => {
    expect(app).not.toContain("JornadasDemo");
    expect(app).not.toContain("RUTA_JORNADAS_DEMO");
  });

  it("no redirige al vendedor a /autoventa", () => {
    expect(app).not.toContain('/autoventa');
  });
});

describe("App.tsx: rutas reales de Supabase conservadas", () => {
  it("/jornadas (real) está protegida para todos los roles", () => {
    expect(app).toMatch(/path="\/jornadas"\s+element=\{\s*<ProtectedRoute roles=\{todos\}>\s*<Jornadas \/>/);
  });

  it("registra rutas de catálogos reales (productos, stock, clientes, camiones)", () => {
    expect(app).toContain('path="/productos"');
    expect(app).toContain('path="/stock"');
    expect(app).toContain('path="/clientes"');
    expect(app).toContain('path="/camiones"');
  });

  it("mantiene el login y la ruta de inicio protegida", () => {
    expect(app).toContain('path="/login"');
    expect(app).toContain('path="/"');
  });
});
