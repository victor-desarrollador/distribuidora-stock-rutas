# Revisión de seguridad

**Fecha:** 22/10/2026
**Ámbito:** cambios que tocan autenticación, autorización, datos por empresa, RPC, RLS, dinero o stock.
**Fuente:** `BLUEPRINT.md` §6 y §10, `AGENTS.md` §5, `CLAUDE.md`, ADR-001 v1.5 (**APROBADA PARA VALIDACIÓN CONTROLADA**). Este documento no amplía esa aprobación: P2–P7 están resueltas, P8–P17 siguen pendientes, P18 es una decisión futura separada y producción continúa bloqueada.

---

## 1. Cuándo es obligatoria

Es **obligatoria** una revisión de seguridad cuando el cambio toca alguna de estas superficies:

- configuración de **Supabase**;
- **autenticación** (Auth, sesiones, cuentas);
- **`empresa_id`** o cualquier aislamiento por `empresa_id`;
- **roles** y permisos;
- **RLS** (políticas, `authenticated`, `anon`);
- **RPC** / funciones SQL;
- **`SECURITY DEFINER` / `SECURITY INVOKER`**;
- **grants** (`GRANT`, `REVOKE`, `ALTER DEFAULT PRIVILEGES`);
- **`service_role`** o cualquier credencial con privilegios amplios;
- las tablas de **`movimientos_stock`**;
- **`ventas`**;
- **`pagos`** (incluido `venta_pagos`);
- **retiros** (`retiros_efectivo`);
- **cierres** (rendición / cierre de jornada);
- **idempotencia**;
- **concurrencia**;
- **secretos**.

Si el cambio no toca ninguna de estas superficies, la revisión de seguridad no es exigible, aunque puede pedirse de todos modos.

---

## 2. Revisión manual independiente

- La realiza una **persona o agente distinto de quien implementó**. Ningún agente aprueba su propio trabajo (AGENTS.md §2; `docs/quality/review-process.md` §3).
- Es **previa** a la auditoría independiente de Codex/OpenCode cuando corresponde.
- No modifica archivos: reporta hallazgos con el formato de `docs/quality/review-process.md` §4 (severidad, archivo/línea, evidencia, regla, riesgo, corrección, bloqueo).
- Se apoya en el Blueprint §10 como regla de referencia.

---

## 3. Verificación de permisos negativos (pgTAP)

Las pruebas de base y permisos **se escribirán** con **pgTAP** en `supabase/tests/` y se ejecutarán con `supabase test db` exclusivamente en local/staging, una vez resueltas las P8–P17 necesarias para el alcance de validación (ADR-001 §16; Blueprint §12). Deben probar, como mínimo, que **fallan** los accesos no autorizados:

| Caso negativo | Resultado esperado |
|---|---|
| **`anon`** intenta ejecutar la operación / leer datos | Rechazo. |
| Usuario con **rol incorrecto** intenta una operación de otro rol (p. ej. vendedor cerrando jornada o haciendo un retiro) | Rechazo. |
| Usuario de **otra empresa** (`empresa_id` distinto) intenta leer u operar | Rechazo (aislamiento por `empresa_id`). |
| **Intento directo de DML prohibido** (`INSERT`/`UPDATE`/`DELETE`) sobre libros de movimientos de stock o caja, o sobre registros confirmados, por `authenticated` o `anon` | Rechazo. |
| Invocación directa de una **función privada privilegiada** desde la Data API | Rechazo. |
| `UPDATE`/`DELETE` sobre `movimientos_stock` por cualquier rol | Rechazo. |

Además, pruebas positivas: la operación autorizada **sí** funciona para el rol habilitado, con los controles de idempotencia y concurrencia.

> **Bloqueo vigente:** ADR-001 v1.5 resolvió P1 con Topología D, P19/P20 con validación en dos etapas y migraciones sólo local/staging, P5–P7 (perfil 1:1, una empresa, un rol) y P2–P4 (`public`/`privado`, `propietario_rpc`, RLS obligatoria sin `FORCE` global). Las pruebas e implementaciones que dependan de P8–P17 continúan bloqueadas hasta resolverlas; P18 no es requisito previo. Nada de esto autoriza producción, que exige evidencia, auditoría independiente y aceptación humana final.

---

## 4. Reglas no negociables (Blueprint §10)

- `authenticated` y `anon` **no reciben INSERT/UPDATE/DELETE directos** sobre libros de movimientos de stock/caja ni sobre registros confirmados; los registros son inmutables y se rectifican con asientos compensatorios.
- La **empresa y el rol** se leen del perfil (tabla protegida), **no** de `user_metadata` modificable por el usuario.
- **RLS en todas las tablas expuestas.** Los controles visuales nunca son la única defensa.
- **`SECURITY DEFINER` ejecuta con privilegios del propietario y puede eludir RLS.** La implementación privada de Topología D debe tener propietario de mínimo privilegio, `search_path = ''`, referencias totalmente calificadas, grants revisados y pruebas reales desde `anon`, `authenticated` ajeno y roles válidos. No se ubica en un esquema expuesto.
- **`SECURITY INVOKER`** para la fachada expuesta y para lecturas/ediciones ordinarias, con grants y RLS apropiados.
- Las **escrituras críticas de stock y dinero** siguen la cadena Data API → fachada expuesta `SECURITY INVOKER` → implementación privada `SECURITY DEFINER` → validaciones completas → transacción. La implementación privada es la frontera real de seguridad (ADR-001 v1.5; Blueprint §10).
- **No usar credenciales administrativas en el navegador** (AGENTS.md §5).
- **Idempotencia y transacciones atómicas** para cargas, ventas, retiros y cierres; protección contra concurrencia/bloqueos (Blueprint §10).

---

## 5. Secretos

- **Nunca en el frontend ni en el repositorio.** Variables de entorno en `.env*` (ignorados); solo `.env.example` sin valores reales (AGENTS.md §5).
- **No leer ni imprimir** archivos `.env*` reales ni credenciales; si hacen falta valores, pedirlos o usar `.env.example` (AGENTS.md §5; `CLAUDE.md`).
- Nunca commitear secretos, `service_role`, `apikey` ni claves equivalentes.
- Entornos local/staging/producción separados (Blueprint §10).

---

## 6. Herramientas de apoyo

### 6.1 Claude `/security-review` — **OPCIONAL / PENDIENTE DE DISPONIBILIDAD**
- El comando `/security-review` de Claude se considera una herramienta **opcional** de apoyo.
- **No está confirmado como disponible.** Su uso queda **pendiente de disponibilidad**.
- Aun cuando esté disponible, **no reemplaza** la revisión manual independiente ni las pruebas pgTAP de permisos negativos, y **no constituye por sí solo** la aprobación de seguridad.

### 6.2 GitHub Action `claude-code-security-review` — **NO INSTALADA**
- La GitHub Action `claude-code-security-review` **no está instalada**.
- Su incorporación **requiere una decisión separada** y **credencial/API key**.
- No forma parte del flujo actual; mientras no exista decisión aprobada, no se agrega a CI.

---

## 7. Relación con otras compuertas

- La revisión de seguridad es una etapa del ciclo documentado en `docs/quality/review-process.md`.
- La verificación funcional en navegador (Playwright CLI) **no** es una revisión de seguridad: ver `docs/quality/browser-testing.md`.
- Ningún agente aprueba su propio trabajo; la aprobación final es humana (AGENTS.md §2).
