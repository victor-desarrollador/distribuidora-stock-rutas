import { useEffect } from "react";

// T-1 (D-B2-1): aviso del navegador al recargar o cerrar la pantalla mientras
// una operación está en curso o tiene resultado desconocido. Es una protección
// de interfaz, igual que la de B-01: el navegador decide si muestra el aviso
// (puede no hacerlo, por ejemplo sin interacción previa del usuario) y el
// texto lo pone el navegador. No guarda nada: sin localStorage, sessionStorage
// ni IndexedDB. No reemplaza la recuperación durable (ADR-010).

type DestinoEventos = Pick<EventTarget, "addEventListener" | "removeEventListener">;

/** Pide al navegador confirmar la salida; devuelve la función que lo quita. */
export function instalarAvisoSalida(destino: DestinoEventos): () => void {
  const avisar = (e: Event) => {
    e.preventDefault();
    // Navegadores que todavía exigen `returnValue` para mostrar el aviso.
    (e as unknown as { returnValue: string }).returnValue = "";
  };
  destino.addEventListener("beforeunload", avisar);
  return () => destino.removeEventListener("beforeunload", avisar);
}

/** Activa el aviso sólo mientras `activo` sea true. */
export function useAvisoSalidaPagina(activo: boolean): void {
  useEffect(() => {
    if (!activo) return;
    return instalarAvisoSalida(window);
  }, [activo]);
}
