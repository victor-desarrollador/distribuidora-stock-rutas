# Proceso de revisión de calidad

**Fecha:** 17/10/2026
**Ámbito:** todo cambio en el repositorio (documentación, código de aplicación, SQL, migraciones, configuración, tooling).
**Fuente:** `AGENTS.md` §2 y §11, `CLAUDE.md`, `BLUEPRINT.md` §13. Este documento **detalla** ese proceso; no lo reemplaza ni lo amplía en alcance.

---

## 1. Cadena del ciclo

```
definición / requisitos
  → grilling (cuando haya decisiones abiertas)
  → plan humano autorizado
  → implementación
  → lint / typecheck / tests / build
  → Playwright (cuando corresponda)
  → code review (disponible)
  → security review (cuando corresponda)
  → auditoría independiente (Codex / OpenCode)
  → aprobación humana
```

Cada eslabón es una compuerta: no se avanza al siguiente sin cerrar el anterior.

---

## 2. Etapas

### 2.1 Definición / requisitos
- Leer `BLUEPRINT.md` completo, `AGENTS.md`, `CLAUDE.md`, las ADR **aprobadas** y las últimas entradas de `docs/progress-log.md` (AGENTS.md §1).
- **Versión documental actual de ADR-001:** ADR-001 — Puerta de entrada SQL para operaciones privilegiadas, **versión 1.2 (ronda 3)**, estado **`propuesta` — NO APROBADA**. Sus **P1–P20** son decisiones pendientes de aprobación humana y sus recomendaciones son **no vinculantes**; la propia ADR propone decidir **P19 y P20 primero**, y **P18** es una decisión futura separada que **no** es requisito previo (`docs/decisions/001-rpc-privilegiadas.md` §15 y §18; `docs/decisions/README.md`).
- Identificar qué reglas del Blueprint siguen **pendientes de aprobación**.
- Si la tarea depende de una regla `PROPUESTA NO APROBADA` / `PROPUESTA TÉCNICA NO APROBADA` o de una ADR en estado `propuesta`: **detener esa parte, informar el bloqueo y pedir aprobación expresa** (AGENTS.md §3; `CLAUDE.md`, Procedimiento 4). No elegir «la opción más razonable» por cuenta propia.

### 2.2 Grilling (cuando haya decisiones abiertas)
Se usa cuando hay decisiones abiertas que conviene stress-testear antes de implementar: requisitos, alcance, ADR, PRD, ambigüedades.

- Herramienta: skill **`grilling`**, fijada en `.agents/skills/grilling/`.
  - Origen: `https://github.com/mattpocock/skills`, ruta `skills/productivity/grilling/SKILL.md`; **commit upstream auditado `49dd158d1076134a641b33efb035946536778336`** (`.agents/skills/grilling/UPSTREAM.md`).
- Método: entrevista al usuario por **rondas** sobre un árbol de decisiones; cada pregunta con una respuesta recomendada; el hallazgo de **hechos** es tarea del agente (búsqueda/subagentes), las **decisiones** son del humano.
- El grilling **no reemplaza** al Blueprint, a las ADR aprobadas, a la revisión de código, a la auditoría de seguridad ni a la aprobación humana (`.agents/skills/grilling/UPSTREAM.md`).
- Las respuestas que cambien reglas del Blueprint se canalizan como **decisión/ADR** en `docs/decisions/` con estado `propuesta` (AGENTS.md §6.5). No se implementan hasta su aprobación.

### 2.3 Plan humano autorizado
- Se presenta un plan breve (objetivo, riesgos, decisiones pendientes) y se espera **aprobación humana explícita** antes de tocar el código.
- Una rama por tarea; nunca se commitea directo a `main`. El merge requiere aprobación humana (AGENTS.md §6.1).

### 2.4 Implementación
- Solo lo autorizado. Cambios pequeños y verificables.
- Toda migración nueva va en `supabase/migrations/`; nunca cambios manuales en la base (AGENTS.md §6.4).

### 2.5 lint / typecheck / tests / build
Desde `apps/web/` (AGENTS.md §9):

| Comando | Qué hace |
|---|---|
| `npm run typecheck` | Verificación de tipos (`tsc -b`). |
| `npm test` | Unitarias (Vitest, una pasada). |
| `npm run lint` | ESLint. Comparar contra el incidente abierto (`docs/incidents/2026-10-12-lint-falla-en-main.md`); **no introducir errores nuevos**. |
| `npm run build` | Build de producción. |

Antes de pedir revisión: `typecheck`, `test`, Playwright y `build` deben pasar, y no deben aparecer errores de lint nuevos respecto del incidente abierto (AGENTS.md §9).

### 2.6 Playwright (cuando corresponda)
- E2E versionado (`npx playwright test`) para recorridos críticos.
- Playwright CLI como apoyo de exploración/depuración. Detalle en `docs/quality/browser-testing.md`.
- Una sesión manual de navegador **no** constituye por sí sola evidencia suficiente: los flujos críticos deben tener tests reproducibles.

### 2.7 Code review (disponible)
- Revisión de código disponible en el entorno. Si el revisor es un agente, **no aprueba su propio trabajo** (ver §3).
- Comentarios de revisión se evalúan con rigor técnico; cuando sean dudosos, se verifican antes de implementarlos.

### 2.8 Security review (cuando corresponda)
- Obligatoria cuando el cambio toca superficies sensibles. Criterios y superficies en `docs/quality/security-review.md`.
- Cuando corresponda, es **previa** a la auditoría independiente.

### 2.9 Auditoría independiente (Codex / OpenCode)
- **Claude Code implementa** la tarea autorizada en su rama (AGENTS.md §2).
- **Codex y OpenCode auditan de forma independiente el mismo commit** (AGENTS.md §2).
- La auditoría no modifica archivos. En OpenCode se hace con el subagente de solo lectura `auditor` (`.opencode/agents/auditor.md`).

### 2.10 Aprobación humana
- El usuario decide sobre los hallazgos y autoriza commit, push, merge y deploy (AGENTS.md §2, §11).
- **Ningún agente aprueba su propio trabajo ni el de otro agente** (AGENTS.md §2).

---

## 3. Reglas obligatorias

1. **Ningún agente aprueba su propio trabajo.** Tampoco el de otro agente. La aprobación es humana (AGENTS.md §2).
2. **El auditor no modifica archivos.** Reporta; no corrige. El subagente `auditor` corre con `edit: deny` y `bash: deny` (`.opencode/agents/auditor.md`).
3. **Si cambia el código después de una auditoría, el nuevo commit (nuevo hash) vuelve a auditarse.** No se reutiliza la auditoría anterior (AGENTS.md §2).
4. **Máximo 3 ciclos `implementar → auditar → corregir`.** Al tercer ciclo sin cierre, se detiene y se **convoca intervención humana**. No se encadenan ciclos indefinidos.
5. **Auditorías siempre sobre un commit/hash concreto** cuando sea posible. Cada auditoría se identifica por el hash auditado; sin hash, la auditoría no es reproducible.
6. **Hallazgos con formato completo y bloqueo explícito.** Cada hallazgo incluye:
   - **severidad** (crítico / alto / medio / bajo);
   - **archivo y línea**;
   - **evidencia**;
   - **regla del Blueprint (o ADR) afectada**;
   - **riesgo**;
   - **corrección propuesta**;
   - **bloqueo** (si bloquea el cierre o no).

---

## 4. Formato de un hallazgo

```
[H-<n>] <título corto>
Severidad: crítica | alta | media | baja
Archivo/línea: <ruta>:<línea>
Evidencia: <qué se observó; cita o salida>
Regla afectada: BLUEPRINT.md §<x> / ADR-<n> / AGENTS.md §<x>
Riesgo: <consecuencia si no se corrige>
Corrección propuesta: <qué hacer>
Bloqueo: sí | no
```

---

## 5. Cierre de una tarea

- Agregar una entrada en `docs/progress-log.md`: qué se hizo, archivos modificados, cómo se verificó y riesgos pendientes (AGENTS.md §11).
- Si se encontró un error, registrarlo en `docs/incidents/` con la plantilla del Blueprint §13.
- Presentar resumen, diff y **hash a auditar**, y **pedir aprobación humana antes del commit, del merge y del deploy** (AGENTS.md §11).

---

## 6. Prohibiciones de proceso

- No ejecutar `git push --force`, `git reset --hard` sobre trabajo ajeno ni merge a `main` sin aprobación humana (AGENTS.md §5).
- No tocar producción: nada de `supabase db push`, `supabase migration up`, `vercel --prod` ni comandos contra la base o el deploy de producción sin aprobación explícita (AGENTS.md §5).
- No commitear secretos; no leer ni imprimir archivos `.env*` reales ni credenciales (AGENTS.md §5; `CLAUDE.md`).
