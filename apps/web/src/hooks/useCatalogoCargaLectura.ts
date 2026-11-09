import { useCallback, useEffect, useState } from "react";

import { obtenerPuertoProductos, type PuertoProductos } from "../lib/productos";
import type { ProductoCarga } from "../pages/jornadas_carga";

// Catálogo de productos para el borrador de carga (FE-1D). SÓLO LECTURA: el
// puerto que recibe es `listar` y nada más (SELECT sobre `productos`, acotado
// por RLS a la empresa del perfil). Las escrituras del catálogo
// (`crear_producto`, etc.) no se exponen aquí.
//
// FE-1F (H-01): el catálogo leído pertenece al contexto de autorización con que
// se leyó (`contextoAutorizacionCarga`: usuario + empresa + rol). Si el contexto
// cambia, el catálogo anterior se borra en el mismo render y se vuelve a leer;
// una respuesta tardía de otro contexto se descarta y nunca se muestra, ni
// siquiera durante un render. Sin contexto (no autorizado, revalidando con
// error, bloqueado) no hay catálogo: null, falla cerrado.

export type PuertoLecturaProductos = Pick<PuertoProductos, "listar">;

/** Puerto real reducido a la lectura: no expone ninguna escritura. */
export function crearLecturaProductos(
  puerto: () => PuertoLecturaProductos = obtenerPuertoProductos
): PuertoLecturaProductos {
  return Object.freeze({ listar: () => puerto().listar() });
}

// "cargando": todavía no hay respuesta. null: la lectura falló (falla cerrado,
// sin datos viejos). Lista: productos de la empresa, activos e inactivos; el
// formulario sólo ofrece los activos y la validación rechaza los inactivos.
export type CatalogoCarga = readonly ProductoCarga[] | null | "cargando";

/** Catálogo junto con el contexto de autorización con que se leyó. */
export interface LecturaCatalogo {
  contexto: string | null;
  catalogo: CatalogoCarga;
}

/** Lo que se puede mostrar para `contexto`: nunca el catálogo de otro contexto. */
export function catalogoParaContexto(lectura: LecturaCatalogo, contexto: string | null): CatalogoCarga {
  if (contexto === null) return null;
  return lectura.contexto === contexto ? lectura.catalogo : "cargando";
}

export interface LectorCatalogo {
  /** Lee para `contexto`; invalida cualquier lectura anterior en curso. */
  leer(contexto: string): void;
  /** Descarta toda lectura en curso: su respuesta ya no se publica. */
  invalidar(): void;
}

/**
 * Coordina las lecturas por generación (como el controlador de sesión): sólo
 * se publica la respuesta de la lectura vigente, etiquetada con su contexto.
 */
export function crearLectorCatalogo(
  puerto: PuertoLecturaProductos,
  publicar: (lectura: LecturaCatalogo) => void
): LectorCatalogo {
  let generacion = 0;
  return {
    leer(contexto) {
      const propia = ++generacion;
      const publicarSiVigente = (catalogo: CatalogoCarga) => {
        if (propia === generacion) publicar({ contexto, catalogo });
      };
      puerto.listar().then(
        (r) => publicarSiVigente(r.ok ? Object.freeze([...r.datos]) : null),
        () => publicarSiVigente(null)
      );
    },
    invalidar() {
      generacion++;
    },
  };
}

export function useCatalogoCargaLectura(
  contexto: string | null,
  puertoInyectado?: PuertoLecturaProductos
) {
  const [lectura, setLectura] = useState<LecturaCatalogo>(() => ({ contexto, catalogo: "cargando" }));
  const [lector] = useState(() =>
    crearLectorCatalogo(puertoInyectado ?? crearLecturaProductos(), setLectura)
  );

  // Cambió el contexto: el catálogo anterior se borra en el mismo render.
  if (lectura.contexto !== contexto) {
    setLectura({ contexto, catalogo: "cargando" });
  }

  const recargar = useCallback(() => {
    if (contexto === null) return;
    setLectura({ contexto, catalogo: "cargando" });
    lector.leer(contexto);
  }, [contexto, lector]);

  useEffect(() => {
    if (contexto === null) return;
    lector.leer(contexto);
    // Al cambiar el contexto (o desmontar) la lectura en curso queda inválida.
    return () => lector.invalidar();
  }, [contexto, lector]);

  return { catalogo: catalogoParaContexto(lectura, contexto), recargar };
}
