import { describe, expect, it } from "vitest";

import {
  DOMINIO_AUTH_INTERNO,
  identificador_auth_interno,
  normalizar_usuario,
} from "./usuario_auth";

describe("normalizar_usuario", () => {
  it("recorta espacios y pasa a minúsculas", () => {
    expect(normalizar_usuario("  Juan  ")).toBe("juan");
    expect(normalizar_usuario("JUAN.PEREZ")).toBe("juan.perez");
  });

  it("es estable: normalizar dos veces da lo mismo", () => {
    const una = normalizar_usuario(" Ana_B-2 ");
    expect(una).toBe("ana_b-2");
    expect(normalizar_usuario(una ?? "")).toBe(una);
  });

  it("variantes de mayúsculas producen el mismo usuario", () => {
    expect(normalizar_usuario("Juan")).toBe(normalizar_usuario("jUAN"));
  });

  it.each([
    ["", "vacío"],
    ["   ", "sólo espacios"],
    ["ab", "menos de 3 caracteres"],
    ["a".repeat(33), "más de 32 caracteres"],
    ["juan perez", "espacio interno"],
    ["juan@x", "arroba"],
    ["josé", "acento"],
    [".juan", "empieza con punto"],
    ["-juan", "empieza con guion"],
    ["juan;drop", "punto y coma"],
    ["abc.", "termina con punto"],
    [".aabc", "empieza con punto (otro caso)"],
    ["a..b", "puntos consecutivos"],
    ["juan..perez", "puntos consecutivos internos"],
    ["juan-", "termina con guion"],
    ["juan_", "termina con guion bajo"],
    ["_juan", "empieza con guion bajo"],
    ["Abc.", "termina con punto tras normalizar"],
  ])("rechaza %j (%s)", (entrada) => {
    expect(normalizar_usuario(entrada)).toBeNull();
  });

  it.each([
    ["juan.perez"],
    ["a.b"],
    ["a_b-c.d"],
    ["a-b"],
    ["a__b"],
    ["dueno.prueba"],
    ["encargado.prueba"],
    ["vendedor.prueba"],
    ["inactivo.prueba"],
    ["sinperfil.prueba"],
  ])("acepta %j", (entrada) => {
    expect(normalizar_usuario(entrada)).toBe(entrada);
  });

  it("acepta los límites de longitud", () => {
    expect(normalizar_usuario("abc")).toBe("abc");
    expect(normalizar_usuario("a".repeat(32))).toBe("a".repeat(32));
  });
});

describe("identificador_auth_interno", () => {
  it("deriva el email interno determinista con dominio .invalid", () => {
    expect(identificador_auth_interno("juan")).toBe(
      "juan@usuarios.distribuidora.invalid"
    );
    expect(DOMINIO_AUTH_INTERNO.endsWith(".invalid")).toBe(true);
  });

  it("falla cerrado si recibe un usuario no normalizado", () => {
    expect(() => identificador_auth_interno("Juan")).toThrow();
    expect(() => identificador_auth_interno("juan@evil.com")).toThrow();
    expect(() => identificador_auth_interno("abc.")).toThrow();
    expect(() => identificador_auth_interno("a..b")).toThrow();
  });
});
