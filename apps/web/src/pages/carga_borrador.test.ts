import { describe, expect, it } from "vitest";

import type { RolUsuario } from "../auth/roles";
import type { EstadoSesion } from "../auth/sesion";
import type { EstadoJornada } from "../lib/jornadas";
import * as moduloBorrador from "./carga_borrador";
import {
  aceptarDescarte,
  cancelarDescarte,
  contextoAutorizacionCarga,
  crearAccionesBorrador,
  estadoBorradorVacio,
  estadoDeContexto,
  requiereConfirmarDescarte,
  solicitarDescarte,
  type EstadoBorrador,
  borradorDeContexto,
  borradorSinGuardar,
  borradorVacio,
  descartarBorrador,
  editarBorrador,
  faseBorradorPara,
  iniciarBorrador,
  type BorradorCarga,
} from "./carga_borrador";
import {
  EDICION_INICIAL,
  cambiarProducto,
  cambiarTexto,
  productosParaLinea,
  revisar,
} from "./carga_edicion";
import { validarCarga, type ProductoCarga } from "./jornadas_carga";
import fuenteBorrador from "./carga_borrador.ts?raw";

const A = "11111111-1111-4111-8111-111111111111";
const B = "44444444-4444-4444-8444-444444444444";
const J1 = "00000000-0000-4000-8000-000000000001";
const J2 = "00000000-0000-4000-8000-000000000002";
const LECHE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const JAMON = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const VIEJO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const CATALOGO: ProductoCarga[] = [
  { id: LECHE, codigo: "L1", nombre: "Leche entera", formaVenta: "unidad", activo: true },
  { id: JAMON, codigo: null, nombre: "Jamón cocido", formaVenta: "peso", activo: true },
  { id: VIEJO, codigo: null, nombre: "Queso discontinuado", formaVenta: "unidad", activo: false },
];

function conLeche(b: BorradorCarga, texto = "24"): BorradorCarga {
  return editarBorrador(b, cambiarTexto(cambiarProducto(b.edicion, 0, LECHE), 0, texto));
}

describe("ciclo del borrador", () => {
  it("vacío: sin jornada, edición inicial y nada sin guardar", () => {
    const b = borradorVacio(A);
    expect(b).toEqual({ contexto: A, jornadaId: null, edicion: EDICION_INICIAL });
    expect(borradorSinGuardar(b)).toBe(false);
  });

  it("iniciar abre la jornada; editar conserva; descartar vuelve a vacío del mismo usuario", () => {
    const b = conLeche(iniciarBorrador(borradorVacio(A), J1));
    expect(b.jornadaId).toBe(J1);
    expect(b.edicion.lineas).toEqual([{ productoId: LECHE, texto: "24" }]);
    expect(borradorSinGuardar(b)).toBe(true);
    expect(descartarBorrador(b)).toEqual(borradorVacio(A));
  });

  it("iniciar la MISMA jornada conserva lo escrito; OTRA jornada empieza vacío", () => {
    const b = conLeche(iniciarBorrador(borradorVacio(A), J1));
    expect(iniciarBorrador(b, J1)).toBe(b);
    const otro = iniciarBorrador(b, J2);
    expect(otro.jornadaId).toBe(J2);
    expect(otro.edicion).toBe(EDICION_INICIAL);
  });

  it("sin sesión no se abre borrador; sin borrador abierto editar no hace nada", () => {
    expect(iniciarBorrador(borradorVacio(null), J1).jornadaId).toBeNull();
    const vacio = borradorVacio(A);
    expect(editarBorrador(vacio, { ...EDICION_INICIAL, revisando: true })).toBe(vacio);
  });

  it("formulario abierto pero sin escribir: no pide aviso al salir", () => {
    expect(borradorSinGuardar(iniciarBorrador(borradorVacio(A), J1))).toBe(false);
  });
});

describe("cambio de sesión: el borrador no se conserva entre cuentas", () => {
  const deA = conLeche(iniciarBorrador(borradorVacio(A), J1));

  it("otro usuario recibe un borrador vacío", () => {
    expect(borradorDeContexto(deA, B)).toEqual(borradorVacio(B));
  });

  it("cerrar sesión (null) lo descarta y ya no se puede abrir uno", () => {
    const sinSesion = borradorDeContexto(deA, null);
    expect(sinSesion).toEqual(borradorVacio(null));
    expect(faseBorradorPara(sinSesion, { id: J1, estado: "abierta" })).toEqual({ fase: "inactiva" });
  });

  it("A → null → A: volver a entrar con la misma cuenta NO recupera el borrador", () => {
    const tras = borradorDeContexto(borradorDeContexto(deA, null), A);
    expect(tras).toEqual(borradorVacio(A));
    expect(borradorSinGuardar(tras)).toBe(false);
  });

  it("el mismo usuario conserva su borrador (p. ej. tras navegar)", () => {
    expect(borradorDeContexto(deA, A)).toBe(deA);
  });
});

describe("fase que ve el panel: nunca de envío", () => {
  const b = conLeche(iniciarBorrador(borradorVacio(A), J1));

  it.each<EstadoJornada>(["abierta", "cargada"])("jornada %s con borrador: confirmando", (estado) => {
    expect(faseBorradorPara(b, { id: J1, estado })).toEqual({ fase: "confirmando", jornadaId: J1 });
  });

  it.each<EstadoJornada>(["en_reparto", "ventas_finalizadas", "regreso_contado", "cerrada"])(
    "jornada %s (ya no cargable): inactiva aunque haya borrador",
    (estado) => {
      expect(faseBorradorPara(b, { id: J1, estado })).toEqual({ fase: "inactiva" });
    }
  );

  it("otra jornada: inactiva", () => {
    expect(faseBorradorPara(b, { id: J2, estado: "abierta" })).toEqual({ fase: "inactiva" });
  });
});

describe("productos y cantidades (ADR-005) en el borrador", () => {
  const abierto = iniciarBorrador(borradorVacio(A), J1);

  it("un producto inactivo no se ofrece para elegir", () => {
    const ids = productosParaLinea(abierto.edicion, 0, CATALOGO).map((p) => p.id);
    expect(ids).toEqual([JAMON, LECHE]);
    expect(ids).not.toContain(VIEJO);
  });

  it("un producto inactivo forzado en el borrador no pasa a revisión", () => {
    const b = editarBorrador(abierto, cambiarTexto(cambiarProducto(abierto.edicion, 0, VIEJO), 0, "3"));
    const r = revisar(b.edicion, CATALOGO);
    expect(r.revisando).toBe(false);
    expect(validarCarga({ lineas: [...b.edicion.lineas] }, CATALOGO)).toEqual({
      ok: false,
      mensaje: "Línea 1: el producto está dado de baja.",
    });
  });

  it.each([
    ["24", 24],
    ["1", 1],
  ])("unidad «%s» → %i unidades enteras", (texto, esperado) => {
    const v = validarCarga({ lineas: [{ productoId: LECHE, texto }] }, CATALOGO);
    expect(v).toEqual({ ok: true, lineas: [{ productoId: LECHE, cantidad: esperado }] });
  });

  it.each(["1,5", "1.5", "0", "-2", "1e3", "+5", "0x10", ""])("unidad «%s»: rechazada", (texto) => {
    expect(validarCarga({ lineas: [{ productoId: LECHE, texto }] }, CATALOGO).ok).toBe(false);
  });

  it.each([
    ["1,250", 1250],
    ["0,001", 1],
    ["2", 2000],
    ["3,1", 3100],
    ["0,1", 100],
    ["1,005", 1005],
  ])("peso «%s» kg → %i gramos enteros exactos", (texto, gramos) => {
    const v = validarCarga({ lineas: [{ productoId: JAMON, texto }] }, CATALOGO);
    expect(v).toEqual({ ok: true, lineas: [{ productoId: JAMON, cantidad: gramos }] });
    if (v.ok) expect(Number.isInteger(v.lineas[0].cantidad)).toBe(true);
  });

  it.each(["1,2345", "0", "0,000", "-1", "abc", ""])("peso «%s»: rechazado", (texto) => {
    expect(validarCarga({ lineas: [{ productoId: JAMON, texto }] }, CATALOGO).ok).toBe(false);
  });
});

describe("gate de escritura del módulo", () => {
  const sinComentarios = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");

  it("sólo exporta preparación: ninguna función de confirmar, enviar o ejecutar", () => {
    expect(Object.keys(moduloBorrador).sort()).toEqual([
      "aceptarDescarte",
      "borradorDeContexto",
      "borradorSinGuardar",
      "borradorVacio",
      "cancelarDescarte",
      "contextoAutorizacionCarga",
      "crearAccionesBorrador",
      "descartarBorrador",
      "editarBorrador",
      "estadoBorradorVacio",
      "estadoDeContexto",
      "faseBorradorPara",
      "iniciarBorrador",
      "requiereConfirmarDescarte",
      "solicitarDescarte",
    ]);
  });

  it("no usa almacenamiento del navegador, RPC, claves ni el controlador de carga", () => {
    expect(sinComentarios(fuenteBorrador)).not.toMatch(
      /localStorage|sessionStorage|indexedDB|\.rpc\(|registrar_carga|randomUUID|nuevaClaveIdempotencia|ejecutar|crearControladorCarga|definicionCarga|obtenerPuertoJornadas/
    );
  });
});

describe("FE-1E: descarte voluntario del borrador con confirmación", () => {
  const escrito = (jornadaId = J1, usuario = A) => conLeche(iniciarBorrador(borradorVacio(usuario), jornadaId));
  const conEstado = (b: BorradorCarga): EstadoBorrador => ({ borrador: b, pendiente: null });
  const CAMBIO_J2 = { tipo: "cambiar_jornada", jornadaId: J2 } as const;
  const CIERRE = { tipo: "cerrar_sesion" } as const;

  // Simula el provider: cada `acciones()` es un render con el estado y el
  // contexto vigentes; `cambiarContexto` es un nuevo render tras cambiar la
  // autorización (descarta en el render y actualiza el contexto vigente).
  function memoria(inicial: EstadoBorrador, contexto: string | null = A) {
    let e = inicial;
    let vigente = contexto;
    return {
      estado: () => e,
      cambiarContexto(c: string | null) {
        vigente = c;
        e = estadoDeContexto(e, c);
      },
      acciones: () => {
        const propio = vigente;
        return crearAccionesBorrador(
          e,
          (f) => {
            if (e.borrador.contexto === propio) e = f(e);
          },
          () => vigente === propio
        );
      },
    };
  }

  it("sólo pide confirmación si hay algo escrito que se perdería", () => {
    expect(requiereConfirmarDescarte(borradorVacio(A), CIERRE)).toBe(false);
    expect(requiereConfirmarDescarte(iniciarBorrador(borradorVacio(A), J1), CIERRE)).toBe(false);
    expect(requiereConfirmarDescarte(iniciarBorrador(borradorVacio(A), J1), CAMBIO_J2)).toBe(false);
    expect(requiereConfirmarDescarte(escrito(), CIERRE)).toBe(true);
    expect(requiereConfirmarDescarte(escrito(), CAMBIO_J2)).toBe(true);
    // Reabrir la misma jornada no pierde nada.
    expect(requiereConfirmarDescarte(escrito(), { tipo: "cambiar_jornada", jornadaId: J1 })).toBe(false);
  });

  it("cambiar de jornada con borrador y CANCELAR: lo escrito queda intacto", () => {
    const m = memoria(conEstado(escrito()));
    expect(m.acciones().iniciar(J2)).toBe(false);
    expect(m.estado()).toEqual({ borrador: escrito(), pendiente: CAMBIO_J2 });
    m.acciones().cancelarDescarte();
    expect(m.estado()).toEqual(conEstado(escrito()));
  });

  it("cambiar de jornada y CONFIRMAR: se descarta y se abre la nueva vacía", () => {
    const m = memoria(conEstado(escrito()));
    m.acciones().iniciar(J2);
    expect(m.acciones().aceptarDescarte()).toEqual(CAMBIO_J2);
    expect(m.estado()).toEqual(conEstado(iniciarBorrador(borradorVacio(A), J2)));
    expect(borradorSinGuardar(m.estado().borrador)).toBe(false);
  });

  it("cerrar sesión con borrador y CANCELAR: no procede y lo escrito queda intacto", () => {
    const m = memoria(conEstado(escrito()));
    expect(m.acciones().pedirCierreSesion()).toBe(false);
    expect(m.estado().pendiente).toEqual(CIERRE);
    m.acciones().cancelarDescarte();
    expect(m.estado()).toEqual(conEstado(escrito()));
  });

  it("cerrar sesión y CONFIRMAR: se descarta y se informa para continuar", () => {
    const m = memoria(conEstado(escrito()));
    m.acciones().pedirCierreSesion();
    expect(m.acciones().aceptarDescarte()).toEqual(CIERRE);
    expect(m.estado()).toEqual(estadoBorradorVacio(A));
  });

  it("sin borrador escrito las acciones proceden sin preguntar", () => {
    const m = memoria(estadoBorradorVacio(A));
    expect(m.acciones().iniciar(J1)).toBe(true);
    expect(m.estado()).toEqual(conEstado(iniciarBorrador(borradorVacio(A), J1)));
    expect(m.acciones().pedirCierreSesion()).toBe(true);
    expect(m.estado()).toEqual(estadoBorradorVacio(A));
  });

  it("aceptar o cancelar sin nada pendiente no cambia nada", () => {
    const e = conEstado(escrito());
    expect(aceptarDescarte(e)).toEqual({ estado: e, aceptada: null });
    expect(cancelarDescarte(e)).toBe(e);
  });

  it("una nueva solicitud reemplaza la pendiente anterior", () => {
    const e = solicitarDescarte(solicitarDescarte(conEstado(escrito()), CAMBIO_J2).estado, CIERRE).estado;
    expect(e.pendiente).toEqual(CIERRE);
    expect(e.borrador).toEqual(escrito());
  });

  describe("cambio REAL de identidad: siempre descarta, sin preguntar", () => {
    it("A → B con borrador escrito y cierre pendiente: B recibe vacío y sin pendiente", () => {
      const conPendiente = solicitarDescarte(conEstado(escrito()), CIERRE).estado;
      expect(estadoDeContexto(conPendiente, B)).toEqual(estadoBorradorVacio(B));
    });

    it("A → null (sesión perdida) con cambio de jornada pendiente: vacío y sin pendiente", () => {
      const conPendiente = solicitarDescarte(conEstado(escrito()), CAMBIO_J2).estado;
      expect(estadoDeContexto(conPendiente, null)).toEqual(estadoBorradorVacio(null));
    });

    it("una acción tardía de A, ya con B vigente, no revive el borrador ni la pendiente", () => {
      const m = memoria(solicitarDescarte(conEstado(escrito()), CIERRE).estado);
      const tardias = m.acciones();
      m.cambiarContexto(B);
      expect(tardias.aceptarDescarte()).toBeNull();
      tardias.cancelarDescarte();
      tardias.editar(escrito(J1, A).edicion);
      expect(m.estado()).toEqual(estadoBorradorVacio(B));
    });
  });
});

// ---------------------------------------------------------------------------
// FE-1F (H-01): el borrador pertenece al contexto de autorización efectivo.

const CIERRE_F = { tipo: "cerrar_sesion" } as const;
const EMPRESA_A = "e0000000-0000-4000-8000-00000000000a";
const EMPRESA_B = "e0000000-0000-4000-8000-00000000000b";

function sesion(
  cambios: Partial<{ usuarioId: string; empresaId: string; rol: RolUsuario; activo: boolean }> = {},
  empresa: Partial<{ id: string; activo: boolean }> = {}
): EstadoSesion {
  const perfil = { usuarioId: A, empresaId: EMPRESA_A, usuario: "u", nombre: "N", rol: "dueno" as RolUsuario, activo: true, ...cambios };
  return {
    estado: "autenticado",
    perfil,
    empresa: { id: perfil.empresaId, nombre: "E", activo: true, ...empresa },
  };
}
const ctx = (s: EstadoSesion) => contextoAutorizacionCarga(s);

describe("FE-1F: contexto de autorización del borrador (H-01)", () => {
  it("dueño o encargado autenticado, perfil y empresa activos: contexto propio", () => {
    expect(ctx(sesion())).not.toBeNull();
    expect(ctx(sesion({ rol: "encargado" }))).not.toBeNull();
    // Misma sesión revalidada con los mismos datos: mismo contexto (se conserva).
    expect(ctx(sesion())).toBe(ctx(sesion()));
  });

  it("mismo usuario: otra empresa u otro rol de gestión dan OTRO contexto", () => {
    const base = ctx(sesion());
    expect(ctx(sesion({ empresaId: EMPRESA_B }))).not.toBe(base);
    expect(ctx(sesion({ rol: "encargado" }))).not.toBe(base);
    expect(ctx(sesion({ usuarioId: B }))).not.toBe(base);
  });

  it.each<[string, EstadoSesion]>([
    ["autorización pendiente (cargando)", { estado: "cargando" }],
    ["no autenticado", { estado: "no_autenticado" }],
    ["perfil inactivo (bloqueado)", { estado: "bloqueado", motivo: "perfil_inactivo" }],
    ["empresa no disponible (bloqueado)", { estado: "bloqueado", motivo: "empresa_no_disponible" }],
    ["error no verificable", { estado: "error", mensaje: "x" }],
    ["rol sin gestión (vendedor/piloto)", sesion({ rol: "vendedor_piloto" })],
    ["perfil desactivado aunque diga autenticado", sesion({ activo: false })],
    ["empresa inactiva aunque diga autenticado", sesion({}, { activo: false })],
    ["empresa que no coincide con el perfil", sesion({}, { id: EMPRESA_B })],
  ])("%s: sin contexto (falla cerrado)", (_n, s) => {
    expect(ctx(s)).toBeNull();
  });

  const CA = ctx(sesion())!;
  const escritoEn = (c: string) => ({ borrador: conLeche(iniciarBorrador(borradorVacio(c), J1)), pendiente: null });

  function memoriaCtx(inicial: EstadoBorrador, contexto: string | null) {
    let e = inicial;
    let vigente = contexto;
    return {
      estado: () => e,
      cambiarSesion(s: EstadoSesion) {
        vigente = ctx(s);
        e = estadoDeContexto(e, vigente);
      },
      acciones: () => {
        const propio = vigente;
        return crearAccionesBorrador(
          e,
          (f) => {
            if (e.borrador.contexto === propio) e = f(e);
          },
          () => vigente === propio
        );
      },
    };
  }

  it("mismo usuario, distinta empresa: el borrador escrito se descarta", () => {
    const m = memoriaCtx(escritoEn(CA), CA);
    m.cambiarSesion(sesion({ empresaId: EMPRESA_B }));
    expect(borradorSinGuardar(m.estado().borrador)).toBe(false);
    expect(m.estado()).toEqual(estadoBorradorVacio(ctx(sesion({ empresaId: EMPRESA_B }))));
    // Volver a la empresa A tampoco lo recupera.
    m.cambiarSesion(sesion());
    expect(m.estado()).toEqual(estadoBorradorVacio(CA));
  });

  it("mismo usuario, permisos reducidos (dueño → vendedor/piloto): invalidado y no se recupera", () => {
    const m = memoriaCtx(escritoEn(CA), CA);
    m.cambiarSesion(sesion({ rol: "vendedor_piloto" }));
    expect(m.estado()).toEqual(estadoBorradorVacio(null));
    // Sin contexto no se puede abrir uno nuevo.
    expect(m.acciones().iniciar(J1)).toBe(false);
    expect(m.estado().borrador.jornadaId).toBeNull();
    m.cambiarSesion(sesion());
    expect(m.estado()).toEqual(estadoBorradorVacio(CA));
  });

  it("mismo usuario, dueño → encargado: también se descarta (otro rol efectivo)", () => {
    const m = memoriaCtx(escritoEn(CA), CA);
    m.cambiarSesion(sesion({ rol: "encargado" }));
    expect(borradorSinGuardar(m.estado().borrador)).toBe(false);
  });

  it("usuario desactivado: los datos anteriores no se reutilizan al reactivarlo", () => {
    const m = memoriaCtx(escritoEn(CA), CA);
    m.cambiarSesion({ estado: "bloqueado", motivo: "perfil_inactivo" });
    expect(m.estado()).toEqual(estadoBorradorVacio(null));
    m.cambiarSesion(sesion());
    expect(borradorSinGuardar(m.estado().borrador)).toBe(false);
    expect(m.estado().borrador.jornadaId).toBeNull();
  });

  it.each<[string, EstadoSesion]>([
    ["cargando", { estado: "cargando" }],
    ["error", { estado: "error", mensaje: "x" }],
  ])("autorización %s: falla cerrado (descarta, no abre ni opera)", (_n, s) => {
    const m = memoriaCtx(escritoEn(CA), CA);
    m.cambiarSesion(s);
    expect(m.estado()).toEqual(estadoBorradorVacio(null));
    const acciones = m.acciones();
    expect(acciones.iniciar(J1)).toBe(false);
    acciones.editar(escritoEn(CA).borrador.edicion);
    expect(m.estado()).toEqual(estadoBorradorVacio(null));
    expect(faseBorradorPara(m.estado().borrador, { id: J1, estado: "abierta" })).toEqual({ fase: "inactiva" });
  });

  it.each<[string, EstadoSesion]>([
    ["empresa", sesion({ empresaId: EMPRESA_B })],
    ["rol", sesion({ rol: "encargado" })],
    ["usuario", sesion({ usuarioId: B })],
    ["autorización perdida", { estado: "cargando" }],
  ])("confirmación pendiente cancelada al cambiar %s", (_n, s) => {
    for (const pedir of ["pedirCierreSesion", "pedirCancelacion"] as const) {
      const m = memoriaCtx(escritoEn(CA), CA);
      expect(m.acciones()[pedir]()).toBe(false);
      expect(m.estado().pendiente).not.toBeNull();
      m.cambiarSesion(s);
      expect(m.estado().pendiente).toBeNull();
      expect(borradorSinGuardar(m.estado().borrador)).toBe(false);
    }
  });

  it("un callback antiguo (diálogo de A) no puede operar sobre el contexto nuevo", () => {
    const m = memoriaCtx(escritoEn(CA), CA);
    m.acciones().pedirCierreSesion();
    const antiguas = m.acciones(); // capturadas por el diálogo de A
    const CB = ctx(sesion({ empresaId: EMPRESA_B }))!;
    m.cambiarSesion(sesion({ empresaId: EMPRESA_B }));
    // En B se escribe un borrador nuevo y se pide cerrar sesión.
    m.acciones().iniciar(J2);
    m.acciones().editar(conLeche(iniciarBorrador(borradorVacio(CB), J2)).edicion);
    m.acciones().pedirCierreSesion();
    const enB = m.estado();
    expect(enB.borrador.contexto).toBe(CB);
    expect(enB.pendiente).toEqual(CIERRE_F);

    // Ninguna acción de A cambia nada ni habilita a quien la llamó a continuar.
    expect(antiguas.aceptarDescarte()).toBeNull();
    antiguas.cancelarDescarte();
    antiguas.descartar();
    antiguas.editar(EDICION_INICIAL);
    expect(antiguas.iniciar(J1)).toBe(false);
    expect(antiguas.pedirCierreSesion()).toBe(false);
    expect(antiguas.pedirCancelacion()).toBe(false);
    expect(m.estado()).toBe(enB);
  });
});

// ---------------------------------------------------------------------------
// FE-1F (H-02): «Cancelar» del formulario con algo escrito pide confirmación.

describe("FE-1F: Cancelar el formulario de carga (H-02)", () => {
  const CANCELAR = { tipo: "cancelar_carga" } as const;
  function memoriaSimple(inicial: EstadoBorrador) {
    let e = inicial;
    return {
      estado: () => e,
      acciones: () => crearAccionesBorrador(e, (f) => (e = f(e)), () => true),
    };
  }
  const escrito = (): EstadoBorrador => ({ borrador: conLeche(iniciarBorrador(borradorVacio(A), J1)), pendiente: null });

  it("sin nada escrito: cancela directo, sin preguntar", () => {
    const m = memoriaSimple({ borrador: iniciarBorrador(borradorVacio(A), J1), pendiente: null });
    expect(m.acciones().pedirCancelacion()).toBe(true);
    expect(m.estado()).toEqual(estadoBorradorVacio(A));
  });

  it("con borrador escrito: queda pendiente de confirmar y no toca lo escrito", () => {
    const m = memoriaSimple(escrito());
    expect(requiereConfirmarDescarte(escrito().borrador, CANCELAR)).toBe(true);
    expect(m.acciones().pedirCancelacion()).toBe(false);
    expect(m.estado()).toEqual({ borrador: escrito().borrador, pendiente: CANCELAR });
  });

  it("elegir conservar: líneas y jornada intactas, sin pendiente", () => {
    const m = memoriaSimple(escrito());
    m.acciones().pedirCancelacion();
    m.acciones().cancelarDescarte();
    expect(m.estado()).toEqual(escrito());
    expect(m.estado().borrador.jornadaId).toBe(J1);
  });

  it("elegir descartar: borra el borrador y cierra la edición", () => {
    const m = memoriaSimple(escrito());
    m.acciones().pedirCancelacion();
    expect(m.acciones().aceptarDescarte()).toEqual(CANCELAR);
    expect(m.estado()).toEqual(estadoBorradorVacio(A));
    expect(faseBorradorPara(m.estado().borrador, { id: J1, estado: "abierta" })).toEqual({ fase: "inactiva" });
  });
});
