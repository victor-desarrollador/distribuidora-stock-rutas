# AGENTS.md — Distribuidora de Lácteos y Fiambres

Aplica a **Claude Code, OpenCode, Codex** y cualquier otro agente o persona que trabaje en este repositorio.

## 1. Fuentes de verdad y documentación obligatoria

Los agentes no diseñan el sistema desde conocimiento genérico. Antes de proponer arquitectura o requisitos deben comprender el negocio real, las reglas aprobadas, las decisiones pendientes y el estado observado del repositorio.

### 1.1 Jerarquía documental

En caso de conflicto, rige esta precedencia:

1. **`BLUEPRINT.md`:** fuente de verdad principal del proyecto.
2. **ADR aprobadas:** modifican o precisan el Blueprint dentro del alcance expresamente aprobado. Una ADR `aprobada para validación controlada` sólo tiene la autoridad limitada que declara su estado.
3. **`docs/PRD.md`:** contexto de producto y negocio (usuarios, operación, objetivos y necesidades). No puede contradecir ni reemplazar al Blueprint ni a las ADR aprobadas; si hay conflicto, prevalecen éstos.
4. **`AGENTS.md`:** reglas de proceso, seguridad, auditoría y autorización.
5. **`CLAUDE.md`:** reglas operativas adicionales, especialmente relevantes para Claude; su lectura es obligatoria para todos los agentes para mantener un contexto común.
6. **`INVENTARIO_ETAPA_0.md`:** estado observado del código/prototipo. Sirve como evidencia del presente y no define el diseño futuro.

El código existente tampoco crea una regla de negocio por sí mismo. Si contradice al Blueprint o a una ADR aprobada, prevalece la documentación de mayor autoridad hasta que una decisión humana aprobada la cambie.

### 1.2 Lectura obligatoria antes de programar

Antes de cualquier cambio de comportamiento, UI, frontend, backend, arquitectura, datos o seguridad, todos los agentes deben leer:

1. `BLUEPRINT.md` completo.
2. `docs/PRD.md`.
3. Este archivo completo.
4. `CLAUDE.md` completo. Contiene instrucciones especialmente relevantes para Claude, pero su lectura es obligatoria para todos los agentes para evitar divergencias.
5. `docs/decisions/README.md` y las ADR aprobadas relevantes; revisar también las ADR propuestas necesarias para identificar qué no está autorizado.
6. Las últimas entradas de `docs/progress-log.md`.
7. El código existente afectado por la tarea.

Además:

- Leer `INVENTARIO_ETAPA_0.md` cuando sea necesario comprender el código existente, los flujos actuales, los datos demo, sus limitaciones o sus diferencias con el sistema objetivo.
- Identificar expresamente qué reglas y decisiones siguen pendientes de aprobación.
- En una microcorrección trivial no hace falta releer documentos completos si ya se leyeron en la misma sesión y no cambiaron, pero se debe verificar que sus versiones y el `HEAD` aplicable sigan siendo los mismos.

### 1.3 Preámbulo obligatorio de cada tarea

Antes de modificar código, SQL, migraciones o arquitectura, informar:

A. Objetivo de negocio entendido.
B. Secciones concretas de `BLUEPRINT.md` aplicables.
C. ADR aprobadas aplicables.
D. Contexto relevante de `docs/PRD.md`.
E. Estado actual relevante del código y de `INVENTARIO_ETAPA_0.md`.
F. Fuera de alcance.
G. Decisiones pendientes.
H. Plan corto: archivos, migraciones si están autorizadas, RPC y frontend; marcar «no aplica» donde corresponda. Para tests, identificar explícitamente qué casos exige `BLUEPRINT.md` §12, qué tests existentes se actualizarán, qué casos negativos corresponden y qué comandos de verificación se ejecutarán; marcar «no aplica» con motivo cuando la tarea no afecte comportamiento.

Si una decisión necesaria no está aprobada, **detener la implementación**. No completar huecos por criterio propio. El agente se comporta como un desarrollador junior guiado por la documentación: lee, identifica reglas, propone, espera autorización cuando corresponde, implementa, prueba y reporta.

## 2. Flujo de trabajo entre agentes

### 2.1 Ciclo de trabajo

```
definición / requisitos
  → grilling (cuando haya decisiones abiertas)
  → plan humano autorizado
  → implementación
  → lint / typecheck / tests / build
  → Playwright (cuando corresponda)
  → code review (humana / independiente)
  → security review (cuando corresponda)
  → auditoría independiente (Codex / OpenCode)
  → aprobación humana
```

Cada eslabón es una compuerta: no se avanza al siguiente sin cerrar el anterior. Las etapas y su detalle están en `docs/quality/review-process.md`, que **detalla** este proceso; no lo reemplaza ni amplía su alcance.

### 2.2 Flujo entre agentes

1. **Claude Code implementa** la tarea autorizada en su propia rama, **sin crear commit**.
2. **Codex y OpenCode auditan de forma independiente el mismo commit.** Cada auditoría se hace sobre un hash concreto, sin modificar archivos (en OpenCode, subagente `auditor`, `.opencode/agents/auditor.md`). Un auditor no corrige el código: reporta el hallazgo.
3. **El usuario aprueba.** Decide sobre los hallazgos y autoriza commit, push, merge y deploy.

### 2.2.1 Secuencia de commit y auditoría

```
implementación sin commit
  → revisión humana previa
  → autorización humana para crear el commit
  → ejecución/verificación reproducible (humano o CI)
  → auditoría independiente del hash
  → corrección + nuevo hash, si corresponde
  → aprobación humana
  → push / merge / deploy solo con autorización humana
```

- El commit se crea **solo después** de la autorización humana. Sin esa autorización no se commitea.
- La auditoría del cambio final **siempre identifica un hash concreto**.
- Push, merge y deploy requieren cada uno una autorización humana explícita; la autorización de un paso no se extiende al siguiente.

### 2.3 Reglas obligatorias del ciclo

1. **Ningún agente aprueba su propio trabajo ni el de otro agente.** La aprobación es humana.
2. **El auditor opera en modo solo lectura.** No modifica archivos ni corrige: reporta. (El subagente `auditor` corre con `edit: deny` y `bash: deny`.) Por eso su función es **auditoría estática de solo lectura**: **no puede verificar por sí mismo** el hash, el diff ni el estado del árbol (`git hash`, `git diff`, `git status`), ni ejecutar tests, typecheck, lint, build ni Playwright. Esa evidencia debe provenir de **CI o de una ejecución humana reproducible** y se le entrega al auditor junto con el hash.
3. **Cada auditoría se refiere a un commit/hash concreto.** Sin hash la auditoría no es reproducible y no cuenta como auditoría del cambio final.
4. **Si cambia cualquier archivo después de una auditoría, el nuevo hash vuelve a auditarse.** No se reutiliza la auditoría anterior.
5. **Máximo 3 ciclos `implementar → auditar → corregir`.** Al tercer ciclo sin cierre se detiene el trabajo y se convoca intervención humana; no se encadenan ciclos indefinidos.
6. **Revisión de seguridad obligatoria** cuando el cambio toca alguna superficie sensible (§2.4). Cuando corresponde, es previa a la auditoría independiente.
7. **Revisión humana final** antes de merge y deploy.
8. **Ningún agente hace merge ni deploy por cuenta propia.**
9. **Cada hallazgo se reporta completo:** severidad (crítica / alta / media / baja), archivo y línea, evidencia, regla del Blueprint o ADR afectada, riesgo, corrección propuesta y bloqueo (sí / no). Formato en `docs/quality/review-process.md` §4.

### 2.4 Superficies que disparan security review

La revisión de seguridad es obligatoria cuando el cambio toca alguna de estas superficies:

- Supabase;
- autenticación (auth);
- `empresa_id` o cualquier filtrado multiempresa;
- roles y permisos;
- RLS;
- RPC / funciones SQL;
- `SECURITY DEFINER` / `SECURITY INVOKER`;
- grants (`GRANT`, `REVOKE`, `ALTER DEFAULT PRIVILEGES`);
- `service_role` o credenciales de privilegio amplio;
- `movimientos_stock`;
- ventas;
- pagos;
- retiros;
- cierres;
- idempotencia;
- concurrencia;
- secretos.

Criterios y detalle en `docs/quality/security-review.md`. Si el cambio no toca ninguna de estas superficies la revisión no es exigible, aunque puede pedirse.

### 2.5 Tooling

- **grilling** — entrevista por rondas para requisitos, decisiones abiertas, ADR y PRD. **No reemplaza** al Blueprint ni a la aprobación humana; las respuestas que cambien reglas del Blueprint se canalizan como decisión en `docs/decisions/` con estado `propuesta`. Skill fijada en `.agents/skills/grilling/`.
- **Playwright CLI** — validación de navegador cuando corresponda; es apoyo a la verificación funcional. **No reemplaza** a Vitest ni a las pruebas E2E versionadas (`npx playwright test`). El estado local `.playwright-cli/` **no se versiona**. Detalle en `docs/quality/browser-testing.md`.
- **Claude `/code-review` y `/security-review`** — **pendientes / opcionales por disponibilidad actual**. Mientras sigan en ese estado no son requisitos del proceso ni compuertas garantizadas, y **no deben describirse como herramientas obligatoriamente disponibles**. La obligación es la revisión (humana e independiente), no una herramienta concreta.

## 3. Prohibición expresa: propuestas no aprobadas

**Está prohibido implementar, total o parcialmente, cualquier regla marcada en el Blueprint como `PROPUESTA NO APROBADA` o `PROPUESTA TÉCNICA NO APROBADA`, y cualquier ADR cuyo estado sea `propuesta`. Una ADR `aprobada para validación controlada` sólo habilita el alcance expresamente resuelto en local/staging; no habilita producción ni decisiones todavía pendientes.**

Esto incluye, según lo marcado en el Blueprint (ver Blueprint §15 y las secciones citadas abajo):

- Stock negativo transitorio en camión / marca `excede_stock` (sección 7.4).
- Reglas de anulación de ventas por el vendedor (sección 7.5).
- Prohibición de descuentos / esquema de precio de lista vs aplicado (sección 7.5).
- Retiro de efectivo que supera el saldo registrado sin bloqueo (sección 7.6).
- Vencimientos por partida de ingreso / tabla `partidas_ingreso` (secciones 2, 4, 8).
- **ADR-001, P2–P17:** decisiones técnicas todavía pendientes para completar la validación controlada (`docs/decisions/001-rpc-privilegiadas.md`). P18 sigue como decisión futura separada. P1/P19/P20 están resueltas y no integran esta prohibición.

"Implementar" incluye: código de aplicación, migraciones SQL, funciones RPC, políticas RLS, tipos, pruebas que asuman la regla como vigente y cambios de UI que la reflejen.

Si una tarea depende de alguna de estas propuestas: **detener esa parte del trabajo, informar el bloqueo y pedir aprobación expresa**. No elegir "la opción más razonable" por cuenta propia. Un agente no puede aprobar una propuesta ni cambiar el estado de una ADR.

Tampoco se implementa nada de la sección 5 del Blueprint (fuera de alcance / Fase 2) sin una decisión aprobada en `docs/decisions/`.

## 4. Arquitectura

- Frontend: React + TypeScript + Vite.
- Aplicación web en `apps/web/`.
- Backend previsto: Supabase Auth y PostgreSQL.
- Deploy previsto: Vercel.
- Operaciones críticas de stock y dinero: transacciones PostgreSQL con autorización comprobada.

### 4.1 Contexto rector del producto

Fase 1 es el sistema operativo de una distribuidora de lácteos y fiambres. Su objetivo es saber qué mercadería sale en cada camión, qué se vendió, qué volvió y qué diferencias de mercadería y dinero existen por camión, jornada y vendedor.

Los únicos roles funcionales vigentes son **dueño**, **encargado** y **vendedor/piloto**. No inventar roles funcionales adicionales.

### 4.2 No sobrearquitectura

No introducir conceptos de arquitectura que no respondan a una necesidad concreta del Blueprint o del PRD. Salvo decisión humana explícita, quedan fuera de alcance: SaaS genérico, workspaces, organizaciones gestionables, suscripciones, planes, invitaciones, selector multiempresa, múltiples membresías por usuario, microservicios, event bus e infraestructura adicional.

La existencia de `empresa_id` **no autoriza** convertir el producto en una plataforma SaaS. Su finalidad aprobada en Fase 1 es cumplir el RLS y el aislamiento por `empresa_id` exigidos por `BLUEPRINT.md` §7.3, no crear funcionalidades de plataforma, selector de empresa ni múltiples empresas por usuario.

### 4.3 P5–P7: decisiones todavía abiertas

- El Blueprint exige obtener empresa y rol desde tablas protegidas, nunca desde `user_metadata` ni desde datos modificables por el usuario.
- La estructura exacta de perfiles, membresías, relación usuario ↔ empresa y roles continúa pendiente de aprobación humana en ADR-001 P5–P7.
- Una tabla separada de membresías **no es un requisito del Blueprint** y no debe asumirse automáticamente.
- No resolver ni implementar P5–P7 hasta que exista una decisión humana aprobada con el contexto real de la distribuidora.

## 5. Reglas obligatorias

- No implementar reglas marcadas como PROPUESTA NO APROBADA ni ADR que no estén aprobadas (sección 3).
- No introducir Prisma ni un servidor Express sin aprobación.
- No incorporar un nuevo sistema de persistencia en localStorage.
- No trasladar reglas del prototipo a SQL sin validarlas.
- No mover stock ni dinero desde el frontend. En la versión final, todo cambio de stock o dinero pasa por RPC en la base (Blueprint secciones 3 y 6).
- No usar credenciales administrativas en el navegador.
- No borrar movimientos financieros ni de inventario confirmados.
- No introducir cambios de alcance sin autorización.

### Producción y seguridad

- **No tocar producción.** No ejecutar migraciones remotas, no apuntar a la base de producción, no cambiar la configuración de Vercel productiva.
- Prohibido sin aprobación explícita: `supabase db push`, `supabase migration up`, `vercel --prod` y cualquier comando contra la base o el deploy de producción.
- Prohibido: `git push --force`, `git reset --hard` sobre trabajo ajeno y merge a `main` sin aprobación humana.
- No commitear secretos. Variables de entorno en `.env*` (ignorados); solo `.env.example` sin valores reales.
- No leer ni imprimir archivos `.env*` reales ni credenciales; si hacen falta valores, pedirlos o usar `.env.example`.

## 6. Desarrollo

1. **Una rama por tarea.** Nunca commitear directo a `main`. El merge requiere aprobación humana.
2. Mantener la estructura `apps/web/`.
3. Hacer cambios pequeños y verificables.
4. Toda migración nueva va en `supabase/migrations/`; nunca cambios manuales en la base. (Supabase todavía no está incorporado; no crearlo sin una tarea que lo pida.)
5. Si una regla del Blueprint parece incorrecta, **no cambiarla en el código**: proponer una decisión en `docs/decisions/` con estado `propuesta`.
6. No borrar módulos existentes ni los datos de demostración (`apps/web/src/data/`, pantalla `ConfiguracionDemo`) salvo que una tarea lo pida explícitamente.
7. Agregar pruebas para las reglas nuevas. Nada se da por terminado sin prueba (Blueprint, principio 5): test automatizado o verificación manual documentada.
8. **Dependencias con versión exacta** (`npm install -E`, sin `^` ni `~` en lo que se agregue), preferentemente publicadas hace al menos dos semanas. Lo mismo para plugins de agentes referenciados por git: fijar un tag.
9. Registrar decisiones e incidentes relevantes.
10. Pedir aprobación antes de hacer merge o deploy.

## 7. Idioma y convención de nombres

Documentación, commits y mensajes al usuario en español (Argentina). Identificadores en español, según esta convención (aprobada por el usuario el 20/10/2026):

- **Código nuevo de dominio TypeScript** (`apps/web/src/domain/`): español `snake_case`.
- **SQL/PostgreSQL:** español `snake_case` (Blueprint §8).
- **Tipos, interfaces y componentes React:** `PascalCase` cuando corresponda.
- **Código React/UI existente:** se conserva el `camelCase`/`PascalCase` actual. **No se hacen renombres masivos por motivos cosméticos.**

Ejemplos de dominio válidos que no se renombran: `piezas_a_medias`, `medias_a_piezas`, `calcular_esperado`, `unidad_para_categoria`, `validar_combinacion_categoria_unidad`. Identificadores de UI/legado como `unidadMedida`, `stockMinimo` o `productoEditando` tampoco se renombran por esta regla.

## 8. Estructura del repositorio

```
/
├── BLUEPRINT.md          visión, alcance y reglas vigentes
├── AGENTS.md             este archivo
├── CLAUDE.md             instrucciones específicas de Claude Code
├── opencode.json         configuración de OpenCode (permisos, plugins)
├── .agents/skills/       skills fijadas en el repositorio y compartidas por los agentes
├── .opencode/agents/     subagentes de OpenCode (auditor de solo lectura)
├── .claude/              configuración compartida de Claude Code
├── docs/
│   ├── decisions/        ADR, una por archivo
│   ├── incidents/        incidentes, uno por archivo
│   ├── progress-log.md   bitácora por tarea
│   └── changelog.md      versiones entregadas
├── .github/workflows/    CI (único workflow: ci.yml)
└── apps/web/             frontend React + TypeScript + Vite (deploy en Vercel)
```

El Blueprint muestra `src/` en la raíz; en este repositorio el frontend vive en `apps/web/src/`. Se respeta la estructura existente.

## 9. Comandos (desde `apps/web/`)

| Comando | Qué hace |
|---|---|
| `npm ci` | Instala dependencias exactas del lockfile |
| `npm run dev` | Servidor de desarrollo |
| `npm run typecheck` | Verificación de tipos (`tsc -b`) |
| `npm test` | Pruebas unitarias (Vitest, una pasada; `src/**/*.test.ts(x)`) |
| `npx playwright test` | Pruebas end-to-end (Playwright, `tests/`; requiere `npx playwright install chromium` la primera vez) |
| `npm run lint` | ESLint (debe terminar con exit 0; el incidente histórico `docs/incidents/2026-10-12-lint-falla-en-main.md` está resuelto) |
| `npm run build` | Build de producción |

Antes de pedir revisión: `lint`, `typecheck`, `test`, Playwright y `build` deben pasar. `npm run lint` debe terminar con exit 0.

## 10. Reglas de negocio confirmadas

- Roles: dueño, encargado y vendedor/piloto.
- El vendedor puede crear clientes, pero no editar fichas existentes.
- Un camión tiene como máximo una jornada por día operativo.
- Los fiambres se venden por pieza y media pieza.
- Las ventas admiten pagos combinados.
- Los retiros de efectivo requieren doble confirmación.
- Dueño y encargado pueden aprobar rendiciones.
- Preventa, proveedores y compras corresponden a Fase 2.

El detalle y las excepciones siempre se consultan en `BLUEPRINT.md`.

## 11. Al terminar una tarea

1. Agregar una entrada en `docs/progress-log.md`: qué se hizo, archivos modificados, cómo se verificó, riesgos pendientes.
2. Si se encontró un error, registrarlo en `docs/incidents/`.
3. Presentar el resumen, el diff y el hash a auditar, y **pedir aprobación humana antes del commit, del merge y del deploy**.
