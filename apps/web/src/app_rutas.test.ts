// Pruebas de la ESTRUCTURA de App.tsx leyendo su fuente (?raw): son una
// comprobación estática de que las guardas están donde se espera, NO un
// montaje del router ni una prueba de comportamiento. El comportamiento de
// ProtectedRoute está en components/ProtectedRoute.test.tsx; la ausencia de la
// ruta demo en producción se verifica sobre el build (ver progress-log).
import { describe, expect, it } from "vitest";

import fuenteApp from "./App.tsx?raw";
import fuenteEntorno from "./demo/entorno.ts?raw";
import fuenteDemo from "./pages/JornadasDemo.tsx?raw";
import fuenteSidebar from "./components/layout/Sidebar.tsx?raw";
import { ROLES_GESTION, ROLES_TODOS } from "./auth/roles";

const sinComentarios = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
const app = sinComentarios(fuenteApp);

describe("App.tsx: rutas de jornadas", () => {
  it("roles: todos incluye al vendedor; gestión no", () => {
    expect(ROLES_TODOS).toContain("vendedor_piloto");
    expect(ROLES_GESTION).not.toContain("vendedor_piloto");
  });

  it("/jornadas (real) está protegida para todos los roles", () => {
    expect(app).toMatch(/path="\/jornadas"\s+element=\{\s*<ProtectedRoute roles=\{todos\}>\s*<Jornadas \/>/);
  });

  it("la pantalla demo se define sólo con import.meta.env.DEV escrito en línea", () => {
    expect(app).toMatch(/const JornadasDemo = import\.meta\.env\.DEV\s*\?\s*lazy\(\(\) => import\("\.\/pages\/JornadasDemo"\)\)\s*:\s*null;/);
    // Ninguna otra importación (estática o diferida) de la pantalla demo.
    expect(app.match(/JornadasDemo"/g)).toHaveLength(1);
  });

  it("la ruta demo sólo existe si la pantalla se definió y exige rol de gestión", () => {
    expect(app).toMatch(/\{JornadasDemo !== null && \(\s*<Route\s+path=\{RUTA_JORNADAS_DEMO\}\s+element=\{\s*<ProtectedRoute roles=\{gestion\}>/);
    expect(fuenteEntorno).toContain('"/demo/jornadas"');
  });

  it("el acceso del menú a la demo depende de import.meta.env.DEV en línea", () => {
    expect(sinComentarios(fuenteSidebar)).toMatch(/import\.meta\.env\.DEV\s*\?\s*\[/);
  });
});

describe("JornadasDemo.tsx (legado)", () => {
  const demo = sinComentarios(fuenteDemo);

  it("rotula la pantalla como demostración con datos locales", () => {
    expect(demo).toContain("Jornadas (demostración)");
    expect(demo).toContain("Datos de este navegador, no reales");
  });

  it("no llama a Supabase ni a la capa real de jornadas", () => {
    expect(/supabase|lib\/jornadas|\.rpc\(|useJornadasLectura|obtenerPuertoJornadas/i.test(demo)).toBe(false);
  });
});
