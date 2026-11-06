import { useState } from "react";

import { useStock } from "../hooks/useStock";
import { StockVista } from "./StockVista";
import {
  ETIQUETA_OPERACION,
  formularioStockVacio,
  validarFormularioStock,
  type FormularioStock,
} from "./stock_formulario";

// Pantalla de stock real (B-01). Rutas sólo para dueño y encargado. Todo el
// movimiento de stock pasa por las RPC; el saldo lo calcula la base.
export default function Stock() {
  const { lectura, recargar, ejecutar } = useStock();
  const [formulario, setFormulario] = useState<FormularioStock>(
    formularioStockVacio()
  );
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mensaje, setMensaje] = useState<string | null>(null);

  async function enviar() {
    if (lectura.estado !== "listo") return;

    setError(null);
    setMensaje(null);

    const validacion = validarFormularioStock(formulario, lectura.datos);
    if (!validacion.ok) {
      setError(validacion.error);
      return;
    }

    setEnviando(true);
    try {
      const resultado = await ejecutar(validacion.intento);
      if ("enCurso" in resultado) return;
      if (resultado.ok) {
        setMensaje(`${ETIQUETA_OPERACION[formulario.tipo]} registrado.`);
        setFormulario(formularioStockVacio(formulario.tipo));
      } else {
        // El formulario se conserva: reintentar reutiliza la misma clave.
        setError(resultado.error);
      }
    } finally {
      setEnviando(false);
    }
  }

  return (
    <StockVista
      lectura={lectura}
      formulario={formulario}
      enviando={enviando}
      error={error}
      mensaje={mensaje}
      onCambiarFormulario={setFormulario}
      onEnviar={() => void enviar()}
      onRecargar={() => void recargar()}
    />
  );
}
