# Pruebas en navegador

**Fecha:** 17/10/2026
**Herramienta:** Playwright CLI **0.1.22**
**Carácter:** herramienta de **apoyo** a la verificación funcional. **No reemplaza** a Vitest ni a las pruebas E2E versionadas del repositorio.
**Fuente:** `BLUEPRINT.md` §3.5 y §12, `AGENTS.md` §9, `.agents/skills/playwright-cli/`.

---

## 1. Qué es y qué no es

- **Es** una herramienta de exploración y depuración en un navegador real: abrir, navegar, interactuar, inspeccionar consola y requests, tomar capturas/traces y generar/afinar pruebas.
- **No es** una prueba automatizada del repositorio. Los flujos críticos deben quedar cubiertos por **tests E2E versionados** (`tests/`, `npx playwright test`) y por **Vitest** para lógica de dominio.
- Una sesión manual de navegador **no constituye por sí sola evidencia suficiente** para cerrar una tarea (`.agents/skills/playwright-cli/UPSTREAM.md`).
- El estado local de la CLI vive en `.playwright-cli/`, que **se ignora por Git** (AGENTS.md §5; `.gitignore`).

### Procedencia

- Skill `playwright-cli`, fijado en `.agents/skills/playwright-cli/`.
- Origen: Microsoft Playwright CLI (`https://github.com/microsoft/playwright-cli`).
- **CLI 0.1.22**; **commit upstream auditado `b85c7a736bb473bf55b584e54a09ffa698d6d871`** (`.agents/skills/playwright-cli/UPSTREAM.md`).
- Instalación usada: `playwright-cli install --skills`.
- En el entorno del proyecto (17/10/2026) el comando global `playwright-cli` está disponible en versión **0.1.22**, y Playwright resuelve **1.64.0**.

---

## 2. Preparación

```bash
# Comprobar disponibilidad (no instala nada)
playwright-cli --version
# Si no hay comando global, usar la versión local:
npx --no-install playwright --version

# Levantar la app en desarrollo (desde apps/web/)
npm run dev
# La URL es la que sirve Vite. La configuración E2E del proyecto usa
# http://127.0.0.1:4173 (apps/web/playwright.config.ts:10,22).
```

La CLI requiere el **navegador Chromium** de Playwright (`npx playwright install chromium` la primera vez, AGENTS.md §9).

---

## 3. Desktop y viewport móvil

Siempre probar **escritorio y móvil**, porque la operación usa ambos (Blueprint §2, §4):

```bash
# Escritorio: fijar tamaño de ventana
playwright-cli open http://127.0.0.1:4173
playwright-cli resize 1920 1080

# Móvil: emular dispositivo genérico (Pixel para Chromium / iPhone para WebKit)
playwright-cli open http://127.0.0.1:4173 --mobile
playwright-cli open http://127.0.0.1:4173 --device="iPhone 15"

# Elegir motor
playwright-cli open http://127.0.0.1:4173 --browser=chrome
```

El viewport móvil es el escenario principal del **vendedor/piloto** (Android); el escritorio, el del **depósito/administración**.

---

## 4. Consola y requests

Inspección obligatoria para detectar errores de runtime y llamadas inesperadas:

```bash
# Mensajes de consola (todos, o filtrar por nivel)
playwright-cli console
playwright-cli console warning

# Requests de red; inspeccionar una en detalle por índice
playwright-cli requests
playwright-cli request 5
```

Regla: un recorrido crítico con **errores en consola** o **requests fallidos** (4xx/5xx) no se considera verificado, aunque la UI se vea correcta.

---

## 5. Capturas, traces y video (cuando correspondan)

- **Snapshot** (estado accesible): `playwright-cli snapshot [--filename=after.yml]`; útil para comparar antes/después (`diff`).
- **Screenshot** (captura puntual): `playwright-cli screenshot [e5] [--filename=...]`.
- **Trace** (depuración con DOM + red + consola por paso):

  ```bash
  playwright-cli tracing-start
  # ... acciones ...
  playwright-cli tracing-stop   # escribe en .playwright-cli/traces/
  ```

- **Video** (demostración / prueba de trabajo de un flujo):

  ```bash
  playwright-cli video-start demo.webm --cursor
  # ... acciones ...
  playwright-cli video-stop
  ```

Usar **trace** para depurar y **video/screenshot** para mostrar un antes/después. Los archivos quedan bajo `.playwright-cli/` y **no se versionan** (§8).

---

## 6. Recorridos críticos

Son los que hay que verificar en cada cambio relevante (alineados con Blueprint §12 y el PRD):

1. **Login y rol** correcto; menú coherente con el rol (dueño / encargado / vendedor).
2. **Productos y clientes:** alta, búsqueda; el vendedor **crea** cliente pero **no edita** existente.
3. **Jornada:** preparación y carga; una jornada por camión y fecha.
4. **Venta (digital) con pago mixto:** la suma de componentes iguala el total; `a_cuenta` no es efectivo.
5. **Devolución / merma** con motivo y clasificación por aptitud.
6. **Finalización de ventas** y **conteo de regreso** por alguien distinto del vendedor.
7. **Retiro de efectivo** con doble confirmación (no descuenta caja hasta confirmar ambos).
8. **Rendición y cierre**, incluido un caso con diferencia; jornada cerrada inmutable.
9. **Responsive:** los recorridos 1–8 en móvil y en escritorio.

> **Alcance actual.** El sistema con base de datos y RPC **todavía no existe** (`INVENTARIO_ETAPA_0.md` §1) y **ADR-001 (versión 1.2, ronda 3) sigue en estado `propuesta` — NO APROBADA**: no hay migraciones ni RPC privilegiadas autorizadas. Por eso hoy estos recorridos solo pueden explorarse contra el **prototipo** con datos de demostración; eso **no** verifica las reglas de stock y dinero del Blueprint.

---

## 7. Exploración manual vs. test automatizado

| Aspecto | Exploración con Playwright CLI | Test E2E versionado (Playwright) |
|---|---|---|
| Naturaleza | Manual, asistida, exploratoria | Automatizada, reproducible |
| Repetición | No | Sí, en cada corrida / CI |
| Dónde vive | Sesión local (`.playwright-cli/`, efímero) | Repositorio (`tests/`) |
| Qué deja | Hallazgos, capturas, trace | Resultado pass/fail reproducible |
| Uso | Descubrir/entender/depurar un flujo; preparar un test | Proteger el flujo contra regresiones |
| Reemplaza al otro | No | No |

Regla: lo que la CLI descubre como flujo crítico **se convierte en test versionado**; la sesión manual queda como apoyo, no como cobertura.

---

## 8. Evidencia requerida para cerrar una tarea

Para dar por verificada una tarea con UI, dejar en la entrada de `docs/progress-log.md`:

- **qué recorridos** se probaron y en qué **viewport** (desktop y/o móvil);
- **salida de `console`** (sin errores) y, si aplica, de **`requests`**;
- resultado de los comandos obligatorios (`typecheck`, `test`, `npx playwright test`, `build`; AGENTS.md §9);
- **captura/trace/video** cuando aporte (antes/después, o estado de falla);
- confirmación de que **el test E2E versionado** del flujo existe o se agregó.

Un cierre basado **solo** en una sesión manual no es válido: el flujo crítico necesita test reproducible.

### `.playwright-cli/` no se versiona

`.playwright-cli/` **nunca** se commitea: puede contener cookies, `localStorage`, estado de sesión, tokens o datos capturados en requests, es decir **estado sensible**. Está en `.gitignore`. Los artefactos de apoyo (traces, video, screenshots) se guardan fuera del control de versiones y no se adjuntan al repositorio.

---

## 9. Limpieza

```bash
playwright-cli close        # cerrar el navegador por defecto
playwright-cli close-all    # cerrar todas las sesiones
playwright-cli kill-all     # forzar procesos colgados
playwright-cli delete-data  # borrar datos de perfil persistentes
```

Al terminar, no dejar sesiones abiertas ni datos de perfil con información sensible.
