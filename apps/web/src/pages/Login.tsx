
import { useState, type FormEvent } from "react";
import { Truck, LogIn } from "lucide-react";
import { Navigate } from "react-router-dom";

import { useAuth } from "../auth/useAuth";
import { inicioPorRol } from "../auth/roles";
import { PantallaCargandoSesion } from "../components/EstadoAcceso";

export default function Login() {
  const { sesion, iniciarSesion } = useAuth();

  const [usuario, setUsuario] = useState("");
  const [password, setPassword] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState("");

  if (sesion.estado === "autenticado") {
    return (
      <Navigate
        to={inicioPorRol(sesion.perfil.rol)}
        replace
      />
    );
  }

  // Cuenta válida en Auth pero sin autorización: la pantalla de bloqueo vive
  // dentro de las rutas privadas.
  if (sesion.estado === "bloqueado") {
    return <Navigate to="/" replace />;
  }

  if (sesion.estado === "cargando" && !enviando) {
    return <PantallaCargandoSesion />;
  }

  async function ingresar(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (enviando) return;

    setError("");
    setEnviando(true);

    const resultado = await iniciarSesion(usuario, password);

    // Nunca se conserva la contraseña más allá del intento.
    setPassword("");

    if (!resultado.ok) {
      setError(resultado.mensaje);
    }

    setEnviando(false);
  }

  const errorConfiguracion =
    sesion.estado === "error" ? sesion.mensaje : "";

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-100 p-4">
      <div className="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-8 shadow-lg">
        <div className="mb-6 flex justify-center">
          <div className="rounded-2xl bg-blue-600 p-4 text-white">
            <Truck size={38} />
          </div>
        </div>

        <h1 className="text-center text-3xl font-bold text-slate-900">
          Distribuidora
        </h1>

        <p className="mt-2 text-center text-slate-500">
          Stock, reparto y autoventa
        </p>

        <form onSubmit={ingresar} className="mt-6 space-y-4" noValidate>
          <label className="block space-y-2">
            <span className="text-sm font-semibold text-slate-700">
              Usuario
            </span>

            <input
              name="usuario"
              type="text"
              value={usuario}
              onChange={(e) => setUsuario(e.target.value)}
              autoComplete="username"
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              required
              className="min-h-14 w-full rounded-xl border border-slate-300 bg-white p-3"
            />
          </label>

          <label className="block space-y-2">
            <span className="text-sm font-semibold text-slate-700">
              Contraseña
            </span>

            <input
              name="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
              required
              className="min-h-14 w-full rounded-xl border border-slate-300 bg-white p-3"
            />
          </label>

          {(error || errorConfiguracion) && (
            <p role="alert" className="text-sm text-red-700">
              {error || errorConfiguracion}
            </p>
          )}

          <button
            type="submit"
            disabled={enviando || Boolean(errorConfiguracion)}
            className="flex min-h-14 w-full items-center justify-center gap-2 rounded-xl bg-blue-600 font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-300"
          >
            <LogIn size={21} />
            {enviando ? "Ingresando…" : "Ingresar al sistema"}
          </button>
        </form>
      </div>
    </div>
  );
}
