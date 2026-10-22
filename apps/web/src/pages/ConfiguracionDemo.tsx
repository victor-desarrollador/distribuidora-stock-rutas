
import { useState } from "react";
import {
  AlertTriangle,
  Download,
  RotateCcw,
  ShieldCheck,
  Settings,
} from "lucide-react";
import { Navigate } from "react-router-dom";
import { useAuth } from "../auth/useAuth";
import { CLAVES_STORAGE } from "../data/clavesStorage";

// Claves de las operaciones que vamos a reiniciar.
// No incluir productos, clientes, camiones ni sesión.
const CLAVES_OPERACIONES = [
  CLAVES_STORAGE.jornadas,
  CLAVES_STORAGE.ventas,
  CLAVES_STORAGE.movimientos,
  CLAVES_STORAGE.retornos,
  CLAVES_STORAGE.cobros,
] as const;

const nombresModulos = [
  "Jornadas y cierres",
  "Ventas de autoventa",
  "Mermas, cambios y devoluciones",
  "Retornos al depósito",
  "Cobros de cuentas corrientes",
];

function exportarRespaldo(): void {
  // Guardamos todas las claves de esta aplicación
  // para no depender de conocer cada nombre.
  const almacenamiento: Record<string, string> = {};

  for (let i = 0; i < localStorage.length; i++) {
    const clave = localStorage.key(i);

    if (
      clave &&
      clave.startsWith("distribuidora_")
    ) {
      const valor = localStorage.getItem(clave);

      if (valor !== null) {
        almacenamiento[clave] = valor;
      }
    }
  }

  const respaldo = {
    aplicacion: "Distribuidora Stock y Autoventa",
    tipo: "respaldo-demo",
    fecha: new Date().toISOString(),
    datos: almacenamiento,
  };

  const contenido = JSON.stringify(
    respaldo,
    null,
    2
  );

  const archivo = new Blob([contenido], {
    type: "application/json;charset=utf-8",
  });

  const url = URL.createObjectURL(archivo);
  const enlace = document.createElement("a");

  const fecha = new Date()
    .toISOString()
    .slice(0, 10);

  enlace.href = url;
  enlace.download =
    `distribuidora-respaldo-${fecha}.json`;

  document.body.appendChild(enlace);
  enlace.click();
  enlace.remove();

  // Liberamos la URL temporal después de iniciar
  // la descarga.
  window.setTimeout(() => {
    URL.revokeObjectURL(url);
  }, 1000);
}

export default function ConfiguracionDemo() {
  const { usuario } = useAuth();

  const [confirmacion, setConfirmacion] = useState("");
  const [respaldoPreparado, setRespaldoPreparado] =
    useState(false);
  const [mensaje, setMensaje] = useState("");
  const [error, setError] = useState("");

  if (usuario?.rol !== "administrador") {
    return <Navigate to="/" replace />;
  }

  function descargarRespaldo() {
    setError("");
    setMensaje("");

    try {
      exportarRespaldo();

      setRespaldoPreparado(true);

      setMensaje(
        "Se inició la descarga del respaldo. Comprobá que el archivo JSON se haya guardado antes de reiniciar."
      );
    } catch {
      setRespaldoPreparado(false);
      setError(
        "No se pudo generar el respaldo. No reinicies la demostración."
      );
    }
  }

  function reiniciarDemo() {
    setError("");
    setMensaje("");

    if (!respaldoPreparado) {
      setError(
        "Primero descargá un respaldo de los datos."
      );
      return;
    }

    if (confirmacion.trim() !== "REINICIAR") {
      setError(
        "Escribí REINICIAR para habilitar esta operación."
      );
      return;
    }

    const confirmar = window.confirm(
      "ATENCIÓN\n\n" +
      "Se borrarán las operaciones de prueba:\n" +
      "• Jornadas y rendiciones\n" +
      "• Ventas\n" +
      "• Movimientos\n" +
      "• Retornos\n" +
      "• Cobros\n\n" +
      "Se conservarán Productos, Clientes, " +
      "Camiones y el usuario conectado.\n\n" +
      "¿Confirmás el reinicio?"
    );

    if (!confirmar) return;

    try {
      // Verificamos todas las claves actuales antes
      // de comenzar a escribir.
      const operacionesActuales: Record<
        string,
        string | null
      > = {};

      for (const clave of CLAVES_OPERACIONES) {
        operacionesActuales[clave] =
          localStorage.getItem(clave);
      }

      // Evitamos que una falla de escritura deje
      // algunos módulos reiniciados y otros no.
      try {
        for (const clave of CLAVES_OPERACIONES) {
          localStorage.setItem(clave, "[]");
        }
      } catch {
        for (const clave of CLAVES_OPERACIONES) {
          const anterior = operacionesActuales[clave];

          if (anterior === null) {
            localStorage.removeItem(clave);
          } else {
            localStorage.setItem(clave, anterior);
          }
        }

        throw new Error(
          "No se pudo completar el reinicio."
        );
      }

      // Recargar para que todos los hooks vuelvan
      // a leer los datos limpios.
      window.location.assign("/");
    } catch {
      setError(
        "Ocurrió un error durante el reinicio. Revisá los datos antes de continuar."
      );
    }
  }

  return (
    <div className="mx-auto max-w-4xl space-y-6 pb-12">
      <header>
        <p className="text-xs font-bold uppercase text-blue-600">
          Administración · Sistema
        </p>

        <div className="mt-2 flex items-center gap-3">
          <Settings
            size={30}
            className="text-blue-600"
          />

          <h1 className="text-3xl font-bold text-slate-900">
            Configuración de demo
          </h1>
        </div>

        <p className="mt-2 text-slate-500">
          Prepará el prototipo para una nueva presentación.
        </p>
      </header>

      {mensaje && (
        <div
          role="status"
          className="rounded-xl bg-green-50 p-4 text-green-800"
        >
          {mensaje}
        </div>
      )}

      {error && (
        <div
          role="alert"
          className="rounded-xl bg-red-50 p-4 text-red-800"
        >
          {error}
        </div>
      )}

      <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
        <div className="mb-4 flex items-center gap-2">
          <ShieldCheck
            size={24}
            className="text-green-600"
          />

          <h2 className="text-xl font-bold">
            Datos que se conservarán
          </h2>
        </div>

        <div className="space-y-3 text-sm text-slate-700">
          <p>✓ Catálogo de productos y sus precios</p>
          <p>✓ Clientes registrados</p>
          <p>✓ Catálogo de camiones</p>
          <p>✓ Usuarios y sesión de demostración</p>
        </div>
      </section>

      <section className="rounded-xl border border-amber-200 bg-amber-50 p-6">
        <div className="mb-4 flex items-center gap-2 text-amber-900">
          <AlertTriangle size={24} />

          <h2 className="text-xl font-bold">
            Datos que se reiniciarán
          </h2>
        </div>

        <ul className="list-inside list-disc space-y-2 text-sm text-amber-900">
          {nombresModulos.map((nombre) => (
            <li key={nombre}>{nombre}</li>
          ))}
        </ul>

        <p className="mt-4 text-sm font-medium text-amber-900">
          Este proceso elimina los registros de prueba
          del navegador actual. No modifica el código
          ni el repositorio de GitHub.
        </p>
      </section>

      <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
        <h2 className="text-xl font-bold">
          1. Respaldo de seguridad
        </h2>

        <p className="mt-2 text-sm text-slate-500">
          Descargá una copia JSON antes de reiniciar.
          El archivo puede contener información de
          clientes y operaciones: guardalo en un lugar
          privado.
        </p>

        <button
          type="button"
          onClick={descargarRespaldo}
          className="mt-5 flex min-h-12 items-center justify-center gap-2 rounded-xl bg-blue-600 px-5 font-semibold text-white hover:bg-blue-700"
        >
          <Download size={20} />
          Descargar respaldo JSON
        </button>

        {respaldoPreparado && (
          <p className="mt-3 text-sm text-green-700">
            Descarga iniciada. Verificá el archivo
            en tu carpeta Descargas.
          </p>
        )}
      </section>

      <section className="rounded-xl border border-red-200 bg-white p-6 shadow-sm">
        <div className="mb-4 flex items-center gap-2">
          <RotateCcw
            size={24}
            className="text-red-600"
          />

          <h2 className="text-xl font-bold">
            2. Reiniciar operaciones
          </h2>
        </div>

        <p className="mb-4 text-sm text-slate-600">
          Para confirmar el reinicio escribí
          exactamente:
        </p>

        <p className="mb-3 font-mono text-xl font-bold text-red-700">
          REINICIAR
        </p>

        <input
          type="text"
          value={confirmacion}
          onChange={(e) =>
            setConfirmacion(e.target.value)
          }
          placeholder="Escribir REINICIAR"
          autoComplete="off"
          className="min-h-12 w-full rounded-xl border border-slate-300 p-3"
        />

        <button
          type="button"
          onClick={reiniciarDemo}
          disabled={
            !respaldoPreparado ||
            confirmacion.trim() !== "REINICIAR"
          }
          className="mt-5 flex min-h-14 w-full items-center justify-center gap-2 rounded-xl bg-red-600 px-5 font-bold text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-40"
        >
          <RotateCcw size={21} />
          Reiniciar datos de demostración
        </button>

        <p className="mt-3 text-xs text-slate-500">
          El reinicio es local y no afecta los datos
          almacenados en otros navegadores.
        </p>
      </section>
    </div>
  );
}
