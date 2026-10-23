import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";

import { AuthContext, type AuthContextType } from "../auth/AuthContextValue";
import type { RolUsuario } from "../auth/roles";
import type { EstadoSesion } from "../auth/sesion";
import ProtectedRoute from "./ProtectedRoute";

function render(sesion: EstadoSesion, roles: RolUsuario[]) {
  const valor: AuthContextType = {
    sesion,
    usuario: sesion.estado === "autenticado" ? sesion.perfil : null,
    iniciarSesion: async () => ({ ok: true }),
    cerrarSesion: async () => undefined,
  };

  return renderToStaticMarkup(
    <AuthContext.Provider value={valor}>
      <MemoryRouter>
        <ProtectedRoute roles={roles}>
          <p>CONTENIDO PROTEGIDO</p>
        </ProtectedRoute>
      </MemoryRouter>
    </AuthContext.Provider>
  );
}

function autenticado(rol: RolUsuario, activo = true): EstadoSesion {
  return {
    estado: "autenticado",
    perfil: { usuarioId: "u", empresaId: "e", usuario: "u", nombre: "U", rol, activo },
    empresa: { id: "e", nombre: "E", activo: true },
  };
}

describe("ProtectedRoute", () => {
  it("muestra el contenido al rol permitido", () => {
    expect(render(autenticado("encargado"), ["dueno", "encargado"])).toContain(
      "CONTENIDO PROTEGIDO"
    );
  });

  it("vendedor/piloto no accede a una ruta de dueño/encargado", () => {
    const html = render(autenticado("vendedor_piloto"), ["dueno", "encargado"]);

    expect(html).not.toContain("CONTENIDO PROTEGIDO");
    expect(html).toContain("Acceso no permitido");
  });

  it("encargado no accede a una ruta sólo de dueño", () => {
    expect(render(autenticado("encargado"), ["dueno"])).toContain(
      "Acceso no permitido"
    );
  });

  it("mientras se resuelve la sesión no muestra contenido", () => {
    const html = render({ estado: "cargando" }, ["dueno"]);

    expect(html).not.toContain("CONTENIDO PROTEGIDO");
    expect(html).toContain("Verificando sesión");
  });

  it("sin sesión no muestra contenido (redirige a login)", () => {
    expect(render({ estado: "no_autenticado" }, ["dueno"])).not.toContain(
      "CONTENIDO PROTEGIDO"
    );
  });

  it("usuario sin perfil queda bloqueado", () => {
    const html = render({ estado: "bloqueado", motivo: "sin_perfil" }, ["dueno"]);

    expect(html).not.toContain("CONTENIDO PROTEGIDO");
    expect(html).toContain("Acceso bloqueado");
  });

  it("perfil inactivo queda bloqueado", () => {
    const html = render(
      { estado: "bloqueado", motivo: "perfil_inactivo" },
      ["vendedor_piloto"]
    );

    expect(html).not.toContain("CONTENIDO PROTEGIDO");
    expect(html).toContain("desactivada");
  });

  it("un perfil marcado inactivo nunca pasa aunque el estado diga autenticado", () => {
    expect(render(autenticado("dueno", false), ["dueno"])).not.toContain(
      "CONTENIDO PROTEGIDO"
    );
  });
});
