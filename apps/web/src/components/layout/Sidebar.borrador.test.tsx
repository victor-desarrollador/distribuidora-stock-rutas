// FE-1E — cierre de sesión voluntario (menú) con un borrador de carga escrito.
//
// Sin DOM de pruebas en el proyecto: el menú se renderiza estático y se
// capturan las props del aviso para disparar sus manejadores; el flujo del
// botón «Cerrar sesión» se prueba en `pedirSalida`/`aceptarSalida` (lo que
// `salir` invoca) con el estado real del borrador en memoria.

import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { AuthContext, type AuthContextType } from "../../auth/AuthContextValue";
import {
  BorradorCargaContexto,
  type ContextoBorradorCarga,
} from "../../hooks/borradorCargaContexto";
import {
  borradorVacio,
  crearAccionesBorrador,
  editarBorrador,
  estadoBorradorVacio,
  estadoDeContexto,
  iniciarBorrador,
  type EstadoBorrador,
} from "../../pages/carga_borrador";
import { cambiarProducto, cambiarTexto } from "../../pages/carga_edicion";
import type { ConfirmarDescarteBorradorProps } from "../ConfirmarDescarteBorrador";
import { aceptarSalida, pedirSalida } from "./cierre_sesion";
import Sidebar from "./Sidebar";
import fuenteSidebar from "./Sidebar.tsx?raw";
import fuenteCierre from "./cierre_sesion.ts?raw";
import fuenteConfirmar from "../ConfirmarDescarteBorrador.tsx?raw";
import fuenteProvider from "../../hooks/BorradorCargaProvider.tsx?raw";
import fuenteBorrador from "../../pages/carga_borrador.ts?raw";

const s = vi.hoisted(() => ({ confirmaciones: [] as ConfirmarDescarteBorradorProps[] }));
vi.mock("../ConfirmarDescarteBorrador", async (orig) => {
  const m = await orig<typeof import("../ConfirmarDescarteBorrador")>();
  return {
    ...m,
    ConfirmarDescarteBorrador: (p: ConfirmarDescarteBorradorProps) => {
      s.confirmaciones.push(p);
      return m.ConfirmarDescarteBorrador(p);
    },
  };
});

const USUARIO = "11111111-1111-4111-8111-111111111111";
const J1 = "00000000-0000-4000-8000-000000000001";
const LECHE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

function auth(cerrarSesion = vi.fn(async () => {})): AuthContextType {
  const perfil = { usuarioId: USUARIO, empresaId: "e", usuario: "u", nombre: "N", rol: "dueno" as const, activo: true };
  return {
    sesion: { estado: "autenticado", perfil, empresa: { id: "e", nombre: "E", activo: true } } as AuthContextType["sesion"],
    usuario: perfil,
    iniciarSesion: vi.fn(),
    cerrarSesion,
  };
}

const escrito = (): EstadoBorrador => {
  const b = iniciarBorrador(borradorVacio(USUARIO), J1);
  return { borrador: editarBorrador(b, cambiarTexto(cambiarProducto(b.edicion, 0, LECHE), 0, "24")), pendiente: null };
};

// Estado real del borrador en memoria: cada `ctx()` es un render nuevo.
function memoria(inicial: EstadoBorrador) {
  let e = inicial;
  return {
    estado: () => e,
    ctx: (): ContextoBorradorCarga => ({
      borrador: e.borrador,
      pendiente: e.pendiente,
      ...crearAccionesBorrador(e, (f) => (e = f(estadoDeContexto(e, USUARIO))), () => true),
    }),
  };
}

function menu(a: AuthContextType, ctx: ContextoBorradorCarga): string {
  return renderToStaticMarkup(
    <MemoryRouter>
      <AuthContext.Provider value={a}>
        <BorradorCargaContexto.Provider value={ctx}>
          <Sidebar />
        </BorradorCargaContexto.Provider>
      </AuthContext.Provider>
    </MemoryRouter>
  );
}

beforeEach(() => {
  s.confirmaciones.length = 0;
});

describe("FE-1E: cerrar sesión con un borrador escrito", () => {
  it("el botón del menú usa el flujo protegido (no llama a cerrarSesion directo)", () => {
    const sinComentarios = fuenteSidebar.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
    expect(sinComentarios).toMatch(/function salir\(\) \{\s*pedirSalida\(borradorCarga, cerrarYOcultar\);\s*\}/);
    expect(sinComentarios).toMatch(/onClick=\{salir\}/);
    expect(sinComentarios.match(/cerrarSesion\(\)/g)).toHaveLength(1); // sólo en cerrarYOcultar
  });

  it("pedir salir queda pendiente: no cierra sesión y el menú muestra la pregunta", () => {
    const m = memoria(escrito());
    const cerrar = vi.fn();
    expect(pedirSalida(m.ctx(), cerrar)).toBe(false);
    expect(cerrar).not.toHaveBeenCalled();
    expect(m.estado().pendiente).toEqual({ tipo: "cerrar_sesion" });

    const h = menu(auth(), m.ctx());
    expect(h).toContain('role="alertdialog"');
    expect(h).toContain("Si cerrás sesión, el borrador se descarta y no se puede recuperar");
    expect(h).toContain("Seguir con el borrador");
    expect(h).toContain("Descartar y cerrar sesión");
  });

  it("CANCELAR: no cierra sesión y el borrador queda intacto", () => {
    const m = memoria(escrito());
    const a = auth();
    pedirSalida(m.ctx(), vi.fn());
    menu(a, m.ctx());
    s.confirmaciones.at(-1)!.onCancelar();
    expect(m.estado()).toEqual(escrito());
    expect(a.cerrarSesion).not.toHaveBeenCalled();
    s.confirmaciones.length = 0;
    expect(menu(a, m.ctx())).not.toContain('role="alertdialog"');
    expect(s.confirmaciones).toHaveLength(0);
  });

  it("CONFIRMAR: descarta el borrador y cierra sesión con el contrato existente", () => {
    const m = memoria(escrito());
    const a = auth();
    pedirSalida(m.ctx(), vi.fn());
    menu(a, m.ctx());
    s.confirmaciones.at(-1)!.onAceptar();
    expect(m.estado()).toEqual(estadoBorradorVacio(USUARIO));
    expect(a.cerrarSesion).toHaveBeenCalledTimes(1);
    expect(a.cerrarSesion).toHaveBeenCalledWith();
  });

  it("sin borrador escrito: cierra sesión de inmediato, sin pregunta", () => {
    const m = memoria(estadoBorradorVacio(USUARIO));
    const cerrar = vi.fn();
    expect(pedirSalida(m.ctx(), cerrar)).toBe(true);
    expect(cerrar).toHaveBeenCalledTimes(1);
    expect(menu(auth(), m.ctx())).not.toContain('role="alertdialog"');
  });

  it("aceptar sin un cierre pendiente no cierra sesión", () => {
    const cerrar = vi.fn();
    expect(aceptarSalida(memoria(escrito()).ctx(), cerrar)).toBe(false);
    expect(cerrar).not.toHaveBeenCalled();
  });

  it("un cambio de jornada pendiente no se muestra como cierre de sesión", () => {
    const m = memoria(escrito());
    m.ctx().iniciar("00000000-0000-4000-8000-000000000002");
    expect(menu(auth(), m.ctx())).not.toContain('role="alertdialog"');
  });
});

describe("FE-1E: sin persistencia ni escritura de carga", () => {
  const sinComentarios = (t: string) => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
  it.each([
    ["Sidebar.tsx", fuenteSidebar],
    ["cierre_sesion.ts", fuenteCierre],
    ["ConfirmarDescarteBorrador.tsx", fuenteConfirmar],
    ["BorradorCargaProvider.tsx", fuenteProvider],
    ["carga_borrador.ts", fuenteBorrador],
  ])("%s: sin almacenamiento del navegador, RPC ni registrar_carga", (_n, fuente) => {
    expect(sinComentarios(fuente)).not.toMatch(
      /localStorage|sessionStorage|indexedDB|\.rpc\(|registrar_carga|crearControladorCarga|obtenerPuertoJornadas|randomUUID/
    );
  });
});
