# Inventario Etapa 0

> **Precedencia (actualización posterior a la auditoría).** Las erratas y aclaraciones E-1 a E-12 prevalecen y sustituyen las afirmaciones originales a las que hacen referencia. El cuerpo original se conserva exclusivamente como registro histórico. En caso de contradicción, la interpretación vigente es la establecida en las erratas, siempre subordinada a BLUEPRINT.md y a las ADR aprobadas.

Documento de inventario técnico de solo lectura. Convenciones de evidencia:
HECHO = observado directamente en código o documentación (con ruta y línea).
INFERENCIA = fuertemente sugerido por la implementación.
PENDIENTE = no se puede determinar con la evidencia disponible (no se inventa respuesta).
Base: rama chore/configuracion-agentes, commit 6e97696 (árbol limpio, sin cambios locales).
1. Resumen ejecutivo
HECHO Lo que existe hoy es un prototipo frontend de demostración, sin backend. Toda la aplicación vive en apps/web/ (React 19 + TypeScript + Vite + Tailwind 4) y persiste el 100 % del estado en localStorage del navegador (apps/web/src/hooks/*, claves distribuidora_*_demo_v1). No hay Supabase, no hay SQL, no hay migraciones, no hay variables de entorno, no hay llamadas HTTP (fetch/axios: 0 ocurrencias), no hay claves ni secretos.
HECHO Funcionalmente el prototipo cubre, de forma parcial y siempre en el navegador: productos (alta/edición), clientes (alta/edición), camiones, jornadas (preparación de carga y salida), autoventa (venta digital contra el "stock del camión"), movimientos de reparto (merma / devolución / cambio), retorno de sobrantes al depósito, rendición y cierre de jornada, cuentas corrientes con cobros, y una pantalla de reinicio de datos demo.
HECHO La madurez es de prototipo de presentación: sirve para mostrar pantallas y flujos al cliente, no para operar. El propio código lo declara (p. ej. Jornadas.tsx:552-556, Rendicion.tsx:1039-1043, Autoventa.tsx:835-840) y la documentación lo reconoce (docs/progress-log.md:124-131, docs/changelog.md:11).
HECHO La documentación (BLUEPRINT.md v1.4, AGENTS.md, CLAUDE.md, docs/) describe un sistema muy distinto del prototipo: reglas de negocio, modelo de datos relacional, RPC en base, RLS, inmutabilidad de libros y multiempresa. Ese sistema no está implementado en absoluto. BLUEPRINT.md y el prototipo no se contradicen en la intención, pero el código incumple casi todas las reglas vigentes del Blueprint (sección 13 de este inventario).
2. Stack detectado
| Capa | Detalle | Evidencia |
|---|---|---|
| Frontend | React ^19.2.8 (resuelto 19.3.0), react-dom 19.3.0, react-router-dom ^7.18.4 | apps/web/package.json:15-22, lockfile |
| UI / estilos | Tailwind CSS ^4.3.3 vía @tailwindcss/vite 4.3.3, lucide-react ^1.53.0 | package.json:16-21, vite.config.ts:6, index.css:1 |
| Lenguaje / build | TypeScript ~6.0.2 (resuelto 6.0.3), Vite ^8.3.0 (resuelto 8.3.4), target es2023, moduleResolution: bundler, jsx: react-jsx | tsconfig.app.json:4-23 |
| Backend | No existe. Sin servidor, sin API, sin funciones | HECHO: no hay supabase/, no hay *.sql, no hay fetch |
| Base de datos | No existe. Sin esquema, tablas, RLS, RPC ni migraciones | HECHO: find de *.sql/supabase/ = 0 |
| Persistencia | localStorage del navegador (8 claves distribuidora_*_demo_v1) | AuthContext.tsx:20; hooks; ConfiguracionDemo.tsx:15-21 |
| Tests unitarios | Vitest 5.0.2 (exacta), 5 casos | vitest.config.ts, src/**/*.test.ts(x) |
| Tests E2E | Playwright 1.64.0 (exacta), 1 caso trivial, no corre en CI | playwright.config.ts, .github/workflows/ci.yml |
| Lint / formato | ESLint ^10.10.0 (10.12.0) flat config, typescript-eslint, eslint-plugin-react-hooks 7; no hay Prettier | eslint.config.js, incidente de lint abierto |
| Infra / deploy | Vercel (SPA con rewrite a index.html), apps/web/vercel.json. Sin CI de deploy, sin .env*, sin .env.example | apps/web/vercel.json:4-9; find .env* = 0 |
| CI/CD | GitHub Actions, único workflow ci.yml; jobs verificar (bloqueante) y lint (continue-on-error) | .github/workflows/ci.yml:20-49 |
HECHO Las dependencias usan rangos ^/~, salvo @playwright/test y vitest que están fijadas exactas (package.json:24-37). Esto incumple la política de versiones exactas de AGENTS.md §6.8 para lo ya existente (deuda, no incidente nuevo).
3. Estructura del repositorio
/
├── BLUEPRINT.md            v1.4 — fuente de referencia del proyecto (479 líneas)
├── AGENTS.md               reglas para todos los agentes
├── CLAUDE.md               reglas específicas de Claude Code (importa AGENTS.md)
├── README.md               índice de enlaces
├── opencode.json           config OpenCode (permisos ask + plugin superpowers #v6.4.2)
├── opencode.json.backup / opencode.json.pre-superpowers.backup  (ignorados por .gitignore)
├── .claude/settings.json
├── .opencode/agents/auditor.md   subagente auditor (edit: deny, bash: deny)
├── .github/workflows/ci.yml
├── docs/
│   ├── decisions/  001-rpc-privilegiadas.md (propuesta) + README (índice y plantilla)
│   ├── incidents/  2026-10-12-lint-falla-en-main.md (abierto) + README
│   ├── progress-log.md    141 líneas, 2 entradas (Tarea 001 y cierre de configuración)
│   └── changelog.md       sin versiones entregadas
└── apps/web/               TODA la aplicación
    ├── package.json / package-lock.json
    ├── vite.config.ts / vitest.config.ts / playwright.config.ts
    ├── tsconfig.json + tsconfig.app.json + tsconfig.node.json
    ├── eslint.config.js / vercel.json / index.html
    ├── public/ (favicon.svg, icons.svg)
    ├── dist/ (build; ignorado, no versionado)
    ├── tests/example.spec.ts (Playwright)
    └── src/
        ├── main.tsx, App.tsx, AuthContext.tsx, index.css, App.css (muerto)
        ├── components/ProtectedRoute.tsx, components/layout/{AppLayout,Sidebar}.tsx
        ├── data/  mock*.ts (9 archivos: tipos + semillas) + mockData.test.ts
        ├── hooks/ 8 hooks (uno por dominio)
        ├── pages/ 12 pantallas
        └── tests/smoke.test.ts
HECHO No existen: supabase/, migrations/, src/ en la raíz, .env.example, ni directorios legacy/prototipo separados. El Blueprint (sec. 13) muestra supabase/ y src/; el repositorio real difiere (ya documentado en AGENTS.md §8 y progress-log.md:139).
4. Funcionalidades encontradas
| Funcionalidad | Estado | Frontend | Base de datos | Observaciones |
|---|---|---|---|---|
| Usuarios y autenticación | Mock/demo only | Login.tsx, AuthContext.tsx | — | Selector de 3 usuarios fijos, sin contraseña ([HECHO] AuthContext.tsx:22-38) |
| Autorización por roles | Implementada (cliente) | ProtectedRoute.tsx, App.tsx:32-48, Sidebar.tsx:71-96 | — | Roles administrador/vendedor/deposito, no los del Blueprint; eludible |
| Empresas / multiempresa | Not found | — | — | No hay empresa_id en ninguna parte (Blueprint sec. 7.3) |
| Productos | Implementada (demo) | Productos.tsx | localStorage | Alta y edición; stock solo al crear |
| Categorías | Parcial | Productos.tsx | — | Solo enum fijo "Lácteos" / "Fiambres" (mockProductos.ts:6) |
| Clientes | Implementada (demo) | Clientes.tsx | localStorage | Alta/edición/baja lógica (activo); sin roles diferenciados |
| Vendedores/pilotos | Mock/demo only | Jornadas.tsx (campo chofer texto libre) | — | No hay entidad "vendedor" (mockJornadas.ts:38) |
| Camiones | Implementada (demo) | Camiones.tsx | localStorage | Patente única validada en cliente (Camiones.tsx:125-134) |
| Rutas / zonas | Parcial | texto zona en jornada y cliente | — | No hay entidad ruta |
| Stock (depósito) | Parcial / directo | Productos.tsx, Jornadas.tsx | localStorage | producto.stock es un número editable del objeto, sin libro |
| Carga de camión | Parcial (UI only) | Jornadas.tsx | — | No descuenta stock real; la disponibilidad se reconstruye al vuelo ([HECHO] Jornadas.tsx:49-89, 552-556) |
| Descarga / retorno de camión | Parcial | Retornos.tsx | localStorage | Registra cantidades aprobadas; ajusta "disponibilidad" derivada |
| Ventas | Implementada (demo) | Autoventa.tsx | localStorage | Contra stock del camión derivado; sin folios ni papel |
| Devoluciones de cliente | Parcial | Movimientos.tsx (tipo devolucion) | localStorage | Van a "cuarentena" y nunca vuelven al vendible |
| Pagos | Parcial / no mixto | Autoventa.tsx:729-760 | — | Un solo medio por venta (mockVentas.ts:26), no admite combinación |
| Cobros de deuda | Implementada (demo) | CuentasCorrientes.tsx, useCobros.ts | localStorage | Reduce saldo de cuenta corriente |
| Gastos de ruta | Not found | — | — | Sin modelo, sin UI |
| Retiros de efectivo | Not found | — | — | Sin modelo, sin UI, sin doble confirmación |
| Conciliación / rendición diaria | Parcial | Rendicion.tsx | localStorage | Mercadería + caja; sin retiros, gastos, transferencias verificadas |
| Rendición por camión | Parcial | Rendicion.tsx | localStorage | Es la misma pantalla (una jornada = un camión) |
| Rendición por vendedor | Referenced, not implemented | — | — | El Blueprint la pide (sec. 11.2); el prototipo no agrupa por persona |
| Faltantes | Parcial (solo cálculo) | Rendicion.tsx:209-212 | — | Muestra la diferencia; no genera movimiento de faltante |
| Sobrantes | Parcial (solo cálculo) | Rendicion.tsx:209-212 | — | Ídem; no exige autorización |
| Ajustes de stock | Not found | — | — | No existe tipo ajuste |
| Reportes | Not found | — | — | Ninguno de los 9 reportes del Blueprint sec. 11 |
| Dashboard | Mock/demo only | Dashboard.tsx | datos fijos | Estadísticas hardcodeadas (mockDashboard.ts:3-8) |
| Administración / configuración | Implementada (demo) | ConfiguracionDemo.tsx | — | Exportar respaldo JSON y reiniciar datos demo |
| Talonarios / notas de papel | Not found | — | — | Sin modelo ni numeración |
| Alertas de vencimiento | Mock/demo only | Dashboard.tsx | datos fijos | Con campo lote (mockDashboard.ts:10-25) — ver §5 del Blueprint |
| Auditoría | Not found | — | — | Sin tabla ni log de acciones |
5. Pantallas y rutas
HECHO Rutas definidas en App.tsx:73-183; guard por ruta en ProtectedRoute.tsx; menú en Sidebar.tsx:25-96.
| Ruta | Pantalla | Propósito | Fuente de datos | Estado |
|---|---|---|---|---|
| /login | Login.tsx | Iniciar sesión demo eligiendo usuario | usuariosDemo (código) | Funcional (demo) |
| /configuracion-demo | ConfiguracionDemo.tsx | Respaldar/reiniciar datos demo | localStorage directo | Funcional (demo). Fuera de ProtectedRoute; solo guard interno admin (:99-101) |
| / | Inicio → Dashboard.tsx | Panel general | mockDashboard.ts (fijo) | Solo admin (redirige a otros roles; App.tsx:50-62) |
| /productos | Productos.tsx | ABM de productos | useProductos | Funcional (demo) · roles admin+depósito |
| /clientes | Clientes.tsx | ABM de clientes | useClientes | Funcional (demo) · roles admin+vendedor |
| /camiones | Camiones.tsx | ABM de camiones | useCamiones | Funcional (demo) · admin+depósito |
| /jornadas | Jornadas.tsx | Preparar carga, confirmar salida | useJornadas, useProductos, useCamiones, useRetornos | Funcional (demo) · admin+depósito |
| /autoventa | Autoventa.tsx | Registrar ventas en ruta | useVentas, useJornadas, useClientes, useMovimientos | Funcional (demo) · admin+vendedor |
| /ventas | — | Redirección | — | Navigate a /autoventa (App.tsx:128-131) |
| /movimientos | Movimientos.tsx | Merma, devolución, cambio | useMovimientos, resto | Funcional (demo) · todos |
| /rendicion | Rendicion.tsx | Conteo, caja y cierre | useJornadas, useVentas, useMovimientos, useCobros | Funcional (demo) · solo admin |
| /retornos | Retornos.tsx | Recepción de sobrantes | useRetornos, useJornadas | Funcional (demo) · admin+depósito |
| /cuentas | CuentasCorrientes.tsx | Saldos y cobros | useCobros, useVentas, useClientes | Funcional (demo) · admin+vendedor |
| * | Inicio | Fallback | — | — |
6. Modelo de datos actual
HECHO No hay base de datos. El "modelo" son interfaces TypeScript (una por dominio) más un arreglo persistido por dominio en localStorage. Todos los ids son: catálogos → number; documentos → string (crypto.randomUUID()).
| "Entidad" | Definición | Clave localStorage | Campos principales | Observación vs Blueprint |
|---|---|---|---|---|
| Producto | mockProductos.ts:3-11 | distribuidora_productos_demo_v1 | id, nombre, categoria, unidadMedida, stock, precio, stockMinimo | Sin activo (baja lógica) y sin codigo; stock es un saldo editable |
| Cliente | mockClientes.ts:4-14 | ..._clientes_... | id, nombreComercio, titular, telefono, direccion, zona, condicionPago, limiteCredito, activo | Sin creado_por/validado_por/estado_validacion |
| Camión | mockCamiones.ts:7-15 | ..._camiones_... | id, nombre, patente, marca, modelo, estado, observaciones | Sin activo |
| Jornada | mockJornadas.ts:35-47 | ..._jornadas_... | id, camionId, chofer(texto), zona, fechaCreacion, fechaSalida, estado, items[] | Sin vendedor_id, sin empresa_id, sin estados intermedios |
| Ítem de carga | mockJornadas.ts:7-13 | (dentro de jornada) | productoId, nombreProducto, unidadMedida, cantidad, precioReferencia | Duplica el nombre del producto (denormalización manual) |
| Cierre | mockJornadas.ts:16-33 | (dentro de jornada) | fecha, conteos{}, efectivoEntregado, efectivoEsperado, transferenciasInformadas, ventasCuentaCorriente, observaciones | Reemplaza el modelo jornada_conteo + jornada_caja_conteo; sin contado_por |
| Venta | mockVentas.ts:16-29 | ..._ventas_... | id, jornadaId, camionId, clienteId, nombreCliente, fecha, medioPago, items[], total | medioPago único ⇒ sin venta_pagos; sin origen digital/papel, serie, número, estado, idempotency_key |
| Detalle de venta | mockVentas.ts:7-14 | (dentro de venta) | productoId, nombreProducto, unidadMedida, cantidad, precioUnitario, subtotal | Sin precio de lista vs aplicado |
| Movimiento de reparto | mockMovimientos.ts:24-43 | ..._movimientos_... | Unión discriminada: merma / devolucion / cambio | No es movimientos_stock: sin origen/destino, sin ubicaciones, sin tipos ingreso/carga_camion/venta/retorno_camion |
| Retorno al depósito | mockRetornos.ts:14-22, ItemRetorno:2-12 | ..._retornos_... | id, jornadaId, camionId, fecha, responsable, observaciones, items[] | Solo lo apto; no distingue apto/cuarentena/no apto |
| Cobro | mockCobros.ts:4-17 | ..._cobros_... | id, clienteId, nombreCliente, jornadaId|null, fecha, importe, medio, referencia, observaciones | Cuenta corriente (Fase 2 según Blueprint); sin verificado_por |
HECHO No existen relaciones declaradas (FK), índices, restricciones de unicidad, enums de base, vistas, triggers ni políticas RLS. Las únicas "constraints" son validaciones en el código de los hooks y las pantallas.
HECHO La relación entre entidades es por convención de campos y se recalcula en cada render: venta.jornadaId → jornada.id → jornada.camionId → camion.id, cobro.clienteId → cliente.id, etc. INFERENCIA Esto hace que no haya integridad referencial: borrar un camión o un producto deja referencias colgantes que las pantallas resuelven con ?? "no encontrado" (p. ej. Jornadas.tsx:466, Rendicion.tsx:544).
7. RPC, funciones y triggers
HECHO No existe ninguna función SQL, RPC, trigger ni vista. No hay carpeta supabase/ ni archivos .sql en el repositorio. La ADR-001 que definiría ese patrón está en estado propuesta (NO aprobada) (docs/decisions/001-rpc-privilegiadas.md:4), por lo que, según AGENTS.md §3, está prohibido implementarla.
HECHO "Funciones" equivalentes que hoy corren en el cliente (todas reemplazables por RPC en el sistema nuevo):
| Función | Ubicación | Qué hace |
|---|---|---|
| salidasPorMovimiento() | data/mockMovimientos.ts:46-59 | Define qué cantidades descuentan stock según tipo |
| calcularSaldoCliente() | hooks/useCobros.ts:70-88 | Saldo = ventas a cuenta − cobros |
| disponibilidad() / stockReservado | Jornadas.tsx:49-106 | Stock depósito "disponible" = producto.stock − cargado + retornos aprobados |
| productosCamion / cantidadesDescontadas | Autoventa.tsx:111-151 | Stock del camión = carga − ventas − mermas − entregados en cambios |
| filasMercaderia (esperado) | Rendicion.tsx:159-224 | esperado = cargado − vendido − merma − reemplazos |
| resumenCaja | Rendicion.tsx:95-157 | Efectivo esperado = ventas efectivo + cobros efectivo |
| cierreValido(), leerJornadas(), etc. | hooks/useJornadas.ts:11-99 | Validación de forma + persistencia |
| registrarVenta/movimiento/retorno/cobro | hooks respectivos | Escritura "transaccional" sobre una sola clave |
INFERENCIA La misma lógica de descuento de stock está duplicada en 4 lugares (Autoventa.tsx:111-151 y 292-376, Movimientos.tsx:105-140 y 276-312, Rendicion.tsx:159-224, Jornadas.tsx:49-106). Es el mayor foco de divergencia futura.
8. RLS y seguridad
HECHO No hay RLS, ni Supabase, ni backend, ni auth.uid(), ni empresa_id, ni secretos. Búsquedas: service_role = 0, supabase solo en documentación, apikey = 0, import.meta.env/process.env = 0, archivos .env* = 0. HECHO No hay dangerouslySetInnerHTML, innerHTML, eval ni new Function (0 ocurrencias).
Hallazgos, solo documentados:
| # | Severidad | Hallazgo | Evidencia |
|---|---|---|---|
| S1 | Crítico | La autorización es solo de cliente. ProtectedRoute decide mirando un objeto en localStorage; se elude cambiando distribuidora_sesion_demo_v1 a admin-demo desde DevTools, o llamando a las funciones de los hooks desde la consola. Sin servidor no hay defensa real. | AuthContext.tsx:20,70-87; ProtectedRoute.tsx:26-49 |
| S2 | Crítico | Autenticación nula: no hay usuario, contraseña ni sesión firmada; es un <select> con 3 usuarios fijos. | Login.tsx:85-95; AuthContext.tsx:22-38 |
| S3 | Alto | Los libros de stock y dinero son mutables desde el navegador: cualquier usuario puede reescribir/borrar localStorage (ventas, cobros, movimientos, jornadas) sin auditoría. Contradice BLUEPRINT.md:99 (solo inserción) y :276 (sin INSERT/UPDATE/DELETE directos). | hooks de escritura; ConfiguracionDemo.tsx:164-184 (borra 5 claves) |
| S4 | Alto | Roles distintos de los del Blueprint: administrador/vendedor/deposito vs dueño/encargado/vendedor-piloto (BLUEPRINT.md:260-268). | AuthContext.tsx:9-12 |
| S5 | Alto | El vendedor puede editar clientes existentes, prohibido por BLUEPRINT.md:163 y AGENTS.md §10. La ruta /clientes admite vendedor y el botón "Editar" no se condiciona por rol. | App.tsx:92-99; Clientes.tsx:494-501; Clientes.tsx:147-162 |
| S6 | Medio | /configuracion-demo queda fuera de ProtectedRoute; solo la protege un guard interno que también lee localStorage. | App.tsx:181; ConfiguracionDemo.tsx:99-101 |
| S7 | Medio | Sin validación de empresa/tenant en ningún punto (no existe el concepto). Si se migrara el modelo tal cual, sería incompatible con multiempresa. | ausencia de empresa_id |
| S8 | Bajo | useMovimientos.ts:20 usa any (productoValido(p: any)); es 1 de los 10 errores de lint del incidente abierto. | docs/incidents/2026-10-12-lint-falla-en-main.md:13 |
INFERENCIA S1–S3 son esperables en un prototipo y no son "bugs" a corregir en el prototipo: son la razón por la que el sistema nuevo no puede reutilizar la capa de datos ni la de autorización.
9. Manejo actual del stock
HECHO Hay dos "stocks" paralelos que nunca se concilian:
1. Stock de depósito: producto.stock (un número dentro del objeto producto). Se edita a mano en el alta de producto ("Stock inicial", Productos.tsx:302). La edición posterior del producto no toca el stock (comentario y código en Productos.tsx:132-146). INFERENCIA Después de crear un producto no hay ningún camino en la UI para corregir su stock.
2. Stock del camión: no se almacena. Se deriva en cada render:
disponible = item.cantidad − ventas de la jornada − mermas − productos entregados en cambios (Autoventa.tsx:111-151; misma fórmula en Movimientos.tsx:105-140 y Rendicion.tsx:159-224).
HECHO Consecuencias observadas:
- Cargar un camión NO descuenta el stock del depósito. Lo dice el propio pie de la pantalla: "las cargas no descuentan inventario real" (Jornadas.tsx:552-556). La "disponibilidad" se reconstruye restando lo cargado y sumando los retornos aprobados (Jornadas.tsx:49-106).
- Vender no descuenta producto.stock: solo reduce el disponible derivado del camión.
- Registrar un retorno no aumenta producto.stock: aumenta la disponibilidad derivada, y solo si la jornada está cerrada y el producto pertenece a la carga original (Jornadas.tsx:59-87).
- Las devoluciones de cliente no vuelven al vendible: quedan "en cuarentena" (conceptual) y salidasPorMovimiento devuelve [] para ellas (mockMovimientos.ts:57-58). La cuarentena se muestra sumando movimientos en Rendicion.tsx:226-266; no hay ubicación cuarentena real, ni merma, ni depósito (BLUEPRINT.md:118-123).
- No hay libro de movimientos de stock. Los "movimientos" registrados son solo merma/devolución/cambio; no existen ingreso, carga_camion, venta, retorno_camion, a_cuarentena, cuarentena_apta, faltante_rendicion, sobrante_rendicion, ajuste (BLUEPRINT.md:136-148).
- No hay transacción: cada alta escribe una clave de localStorage. No hay operación atómica entre cargar/vender/cerrar.
- No hay inmutabilidad: useJornadas.confirmarSalida y cerrarJornada reescriben el estado de la jornada en el arreglo (useJornadas.ts:148-156, 203-211); setProductos/setClientes/setCamiones reescriben el arreglo completo.
HECHO Guardas que sí existen hoy (y conviene preservar como casos de prueba al reconstruir): no vender más que lo cargado menos lo ya vendido/mermado (Autoventa.tsx:298-372), no cargar más que lo disponible (Jornadas.tsx:180-185), cantidad entera salvo kg (Autoventa.tsx:346-357), no cerrar con esperado negativo (Rendicion.tsx:289-292, 367-372), un solo retorno por jornada (useRetornos.ts:86-92).
10. Manejo actual del dinero
HECHO Piezas existentes: ventas (mockVentas.ts), cobros de cuenta corriente (mockCobros.ts) y el cierre de caja dentro de la jornada (CierreJornada).
- Venta: un único medioPago ∈ {efectivo, transferencia, cuenta_corriente} (mockVentas.ts:2-5, 26). No admite pagos combinados, aunque BLUEPRINT.md:162 los exige para 1A. HECHO
- Cuenta corriente: la venta con medioPago === "cuenta_corriente" genera deuda; los cobros la reducen. Saldo = deuda − cobros (useCobros.ts:70-88). Se valida que el cobro no supere el saldo (useCobros.ts:133-135; CuentasCorrientes.tsx:174-177) y que una transferencia tenga referencia (useCobros.ts:108-113). HECHO Esta funcionalidad corresponde a Fase 2 según BLUEPRINT.md:78 y no debería trasladarse como está.
- Efectivo esperado en rendición: ventas efectivo + cobros efectivo de la jornada (Rendicion.tsx:140-142). No se restan retiros de efectivo (no existen) ni gastos autorizados (no existen). HECHO
- Transferencias: se muestran como "importes informados, no operaciones bancarias conciliadas" (Rendicion.tsx:979-981). No hay estados declarada/verificada ni verificado_por (BLUEPRINT.md:212). HECHO
- Cierre: guarda efectivoEntregado, efectivoEsperado, transferenciasInformadas, ventasCuentaCorriente, conteos y observaciones (Rendicion.tsx:434-444). Exige observación si hay diferencias (Rendicion.tsx:417-425) y confirmación por window.confirm (:427-432). No exige aprobación de un segundo usuario ni registra quién aprobó. HECHO
- "Completar con esperados": botón que copia los valores esperados al campo de conteo físico (Rendicion.tsx:328-351). INFERENCIA Permite "cerrar" sin contar de verdad; combinado con que la rendición la puede ejecutar el mismo usuario que vende, anula la separación de responsabilidades de BLUEPRINT.md:45,164.
- No existen: retiros de efectivo con doble confirmación (Blueprint sec. 7.6), gastos de ruta (7.6), idempotency_key, estados de confirmación, ni libro financiero inmutable.
- Tipos numéricos: los importes son number de JavaScript (doble precisión), redondeados con Math.round(x*100)/100 en cada pantalla (p. ej. useCobros.ts:9-11, Rendicion.tsx:130-131). No hay dinero en centavos ni tipo numeric/decimal. HECHO BLUEPRINT.md no fija el tipo aquí, pero :113 exige enteros para cantidades.
11. Datos demo, mocks y hardcodeados
| Elemento | Ubicación | Naturaleza |
|---|---|---|
| 5 productos, 3 clientes, 3 camiones semilla | data/mockProductos.ts:13-59, mockClientes.ts:16-50, mockCamiones.ts:17-45 | Semillas de demostración (se persisten al primer uso) |
| Dashboard completo | data/mockDashboard.ts:1-42 + Dashboard.tsx:9-13 | 100 % ficticio: ventasHoy: 1250000, cobrosHoy: 890000, clientesAtendidos: 38, camionesActivos: 2, 2 alertas de vencimiento con lote, 2 camiones en reparto |
| Reinicio de demo | ConfiguracionDemo.tsx:15-29, 123-199 | Borra 5 claves de operaciones ([]) conservando productos/clientes/camiones; exige escribir REINICIAR |
| Usuarios y sesión | AuthContext.tsx:22-38 | 3 usuarios fijos sin credenciales |
| Formato de moneda / etiquetas de unidad | Productos.tsx:9-21, Clientes.tsx:44-49, Jornadas.tsx:18-28, etc. | Duplicado en 6+ archivos |
| Motivos de movimiento | Movimientos.tsx:600-605 | Lista fija en el JSX |
| Categorías | mockProductos.ts:6 | "Lácteos" / "Fiambres" fijos |
| Avisos de prototipo | Jornadas.tsx:552-556, Rendicion.tsx:1039-1043, Autoventa.tsx:835-840, Movimientos.tsx:682-685, Retornos.tsx:535-540, CuentasCorrientes.tsx:536-540, Productos.tsx:471-476, Login.tsx:74-78 | Textos que declaran que es demo |
| apps/web/src/App.css | 184 líneas | Código muerto de la plantilla Vite; no se importa en ningún lado |
| index.html | <title>web</title> (:8) | Título de plantilla |
HECHO No hay TODO/FIXME/HACK en el código (grep -w = 0). Los únicos marcadores de trabajo pendiente viven en la documentación (BLUEPRINT.md:426-455, incidente abierto).
12. Tests existentes
HECHO 5 casos en 2 archivos unitarios + 1 E2E:
| Test | Archivo | Qué verifica |
|---|---|---|
| "Configuración inicial: 1+1=2" | src/tests/smoke.test.ts:3-6 | Solo que Vitest corre |
| 1 caso de ids únicos (productos/clientes/camiones) | src/data/mockData.test.ts:17-23 | Integridad de las semillas |
| 3 casos de salidasPorMovimiento | mockData.test.ts:25-79 | Que merma/cambio descuentan y devolución no |
| 1 E2E: body visible | tests/example.spec.ts:3-7 | Que la página carga (URL absoluta, sin baseURL) |
HECHO No hay una sola prueba sobre: hooks de persistencia, validaciones de venta/cierre/retorno/cobro, cálculo de stock del camión, cálculo de caja, roles/permisos, ni ninguna de las pruebas obligatorias de BLUEPRINT.md sec. 12 (todas requieren base de datos + pgTAP, bloqueadas por ADR-001 en estado propuesta).
HECHO CI (.github/workflows/ci.yml): job verificar = npm ci + typecheck + test + build (bloqueante, Node 24); job lint = continue-on-error: true por el incidente abierto. Playwright no se ejecuta en CI. HECHO El workflow nunca corrió en GitHub Actions (progress-log.md:122), y PENDIENTE si corre hoy (depende de permisos de Actions en el repositorio remoto).
13. Diferencias entre documentación y código
| # | Blueprint dice | El código hace | Evidencia |
|---|---|---|---|
| D1 | "El stock nunca se edita a mano" (:44); la lógica que mueve stock vive en RPC en la base (:97) | Todo el stock vive y se muta en el frontend sobre localStorage | Productos.tsx:132-146; hooks |
| D2 | authenticated y anon no tienen escritura directa; libros solo inserción (:276) | Cualquier visitante escribe los "libros" desde el navegador | hooks; ConfiguracionDemo.tsx:164-184 |
| D3 | Roles dueño / encargado / vendedor-piloto (:260-268) | Roles administrador / vendedor / deposito | AuthContext.tsx:9-12 |
| D4 | El vendedor no edita clientes existentes (:163) | El vendedor edita clientes (ruta + botón sin condicionar) | App.tsx:92-99; Clientes.tsx:494-501 |
| D5 | Sin venta por kilogramo; cantidades enteras en unidad mínima; fiambre por pieza/media (:34,110-113) | UnidadMedida incluye "kg" y admite 3 decimales | mockProductos.ts:1; Autoventa.tsx:229-234, 346-357 |
| D6 | Cuentas corrientes completas = Fase 2 (:78) | Existe una cuenta corriente simplificada (saldos y cobros) | CuentasCorrientes.tsx; useCobros.ts |
| D7 | Un flujo de 6 estados de jornada (:154) | 3 estados: preparacion / abierta / cerrada | mockJornadas.ts:2-5 |
| D8 | Máx. una jornada por camión y fecha, incluso cerrada (:156) | Impide dos jornadas no cerradas del mismo camión; no mira la fecha → permite otra jornada el mismo día si la anterior se cerró | useJornadas.ts:121-130 |
| D9 | El conteo lo hace alguien distinto del vendedor (:164) | No existe identidad ni control; el mismo usuario puede vender y cerrar, y hay un botón "Completar con esperados" | Rendicion.tsx:328-351 |
| D10 | Pagos mixtos obligatorios en 1A (:162) | Un solo medio por venta | mockVentas.ts:26; Autoventa.tsx:729-760 |
| D11 | Retiros de efectivo con doble confirmación (:169-172) | No existen | búsqueda sin resultados |
| D12 | Gastos de ruta autorizados (:63,173) | No existen | búsqueda sin resultados |
| D13 | Transferencias con estado declarada/verificada (:212) | Solo un importe informado | Rendicion.tsx:975-983 |
| D14 | Faltantes/sobrantes generan movimiento con autorización (:146-147) | Solo se calcula y muestra la diferencia; no se registra movimiento | Rendicion.tsx:209-212 |
| D15 | Devoluciones se clasifican por aptitud; cuarentena → apta o merma (:142-145) | Toda devolución queda "en cuarentena" y nada la reingresa | mockMovimientos.ts:57-58; Retornos.tsx:469-474 |
| D16 | Vencimientos por partida son PROPUESTA NO APROBADA (:35,229) | El Dashboard muestra alertas de vencimiento con lote | mockDashboard.ts:10-25; Dashboard.tsx:77-107 |
| D17 | Talonarios, notas de papel, numeración e idempotencia (:159,239-241) | No existen; los ids son UUID generados en el cliente | useVentas.ts:69-71 |
| D18 | empresa_id en todas las tablas (:127) | No existe el concepto | modelo actual §6 |
| D19 | Estructura con supabase/ y src/ en la raíz (:359-373) | Frontend en apps/web/, sin supabase/ | ya documentado en AGENTS.md §8 |
| D20 | Reportes sec. 11 (9 reportes) | Ninguno implementado | — |
HECHO docs/progress-log.md:124-131 ya había identificado D1/D3/D5/D6 "al pasar" en la Tarea 001. Este inventario los confirma y agrega el resto.
14. Riesgos técnicos
Críticos
1. Sin backend ni base: no puede haber integridad de stock ni de dinero. El estado es de quien tenga el navegador. (S1–S3)
2. Autorización y autenticación puramente de cliente, eludibles trivialmente.
3. El prototipo no tiene ninguna de las garantías que el negocio pide (libro inmutable, idempotencia, doble confirmación, separación de responsabilidades, auditoría).
4. "kg" como unidad de venta contradice la regla central de unidades del Blueprint y, si se traslada, contamina el modelo de cantidades.
Altos
5. Lógica de stock duplicada en 4 archivos (§7): divergencia segura al evolucionar.
6. Dinero y cantidades en number de punto flotante, sin centavos ni enteros mínimos.
7. Sin idempotencia en ventas/cobros/movimientos: la única protección contra duplicados es un id generado en el cliente por operación (crypto.randomUUID() en Autoventa.tsx:277, Movimientos.tsx:232, CuentasCorrientes.tsx:201); dos envíos generan dos ids distintos ⇒ dos registros.
8. Una jornada cerrada puede "reabrirse" a nivel de datos por manipulación de localStorage; no hay inmutabilidad real (contraste con BLUEPRINT.md:46).
9. stockReservado (Jornadas) solo reincorpora si la jornada está cerrada y el producto coincide; INFERENCIA cargas de jornadas que nunca se cierran dejan el stock "reservado" para siempre sin aviso.
Medios
10. TypeScript sin strict (no hay "strict": true ni strictNullChecks en tsconfig.app.json) ⇒ muchos errores quedan fuera de typecheck.
11. Sin estados de carga ni de error normalizados; las validaciones usan alert() nativo (Clientes.tsx:139, Productos.tsx:128, Camiones.tsx:132).
12. Roles del prototipo ≠ roles del negocio; cualquier UI o prueba que dependa de ellos habrá que rehacerla.
13. Sin tests de negocio (§12) y sin E2E en CI: las reglas del prototipo no están protegidas por nada.
14. Incidente de lint abierto: 10 errores + 1 advertencia, con el job no bloqueante.
Bajos
15. App.css muerto (184 líneas); <title>web</title>; README.md de apps/web es el de la plantilla.
16. Dependencias con ^/~ (deuda contra AGENTS.md §6.8).
17. playwright.config.ts levanta el dev server (no el build) y el E2E usa URL absoluta.
18. opencode.json.backup y opencode.json.pre-superpowers.backup en la raíz (ignorados, pero son ruido).
15. Deuda técnica relevante
1. Duplicación de la verdad del stock en cuatro pantallas (§7). Es deuda estructural: cualquier cambio de regla exige tocar 4 archivos y 4 validaciones casi iguales.
2. Modelo de datos "denormalizado a mano": la venta y el ítem de carga copian nombreProducto, unidadMedida y precio (INFERENCIA intencional, para congelar históricos), pero sin reglas que garanticen coherencia.
3. Persistencia ad hoc: 8 claves localStorage, cada hook con su propio esquema de validación y su propio catch; no hay migración de versiones de datos (las claves terminan en _v1 pero no hay mecanismo de upgrade).
4. Validación de forma duplicada (esCantidadValida existe en useRetornos.ts:10-25, Retornos.tsx:29-44 y useJornadas.ts:186-197).
5. Ausencia de strict en TypeScript y de reglas type-aware en ESLint (eslint.config.js:12-17 usa recommended, no recommendedTypeChecked).
6. Lint no bloqueante con 10 errores (incidente abierto).
7. Sin E2E en CI; el único E2E no prueba nada del negocio.
8. ConfiguracionDemo conoce las claves internas de otros módulos (ConfiguracionDemo.tsx:15-21): acoplamiento que se romperá solo al migrar.
9. Sin ninguna forma de auditoría (quién hizo qué). No es cosmético: el objetivo del sistema es "saber quién es responsable de cada paso".
16. Qué puede reutilizarse
| Elemento | Clasificación | Motivo |
|---|---|---|
| AppLayout, Sidebar (menú por rol, responsive, Escape, overlay) | Reutilizable con modificaciones | Buena UX móvil; cambiar a los 3 roles reales y a la navegación final (Sidebar.tsx:25-96) |
| Patrón ProtectedRoute | Reutilizable con modificaciones | La idea sirve como guard de UI, pero nunca como autorización; detrás debe haber RLS/RPC |
| Estructura de páginas por dominio y composición de tarjetas/secciones | Reutilizable con modificaciones | Layout consistente (Tailwind) y accesible (role="status", role="alert", aria-label) |
| Jornadas.tsx, Autoventa.tsx, Movimientos.tsx, Rendicion.tsx, Retornos.tsx, CuentasCorrientes.tsx (UI) | Reutilizable con modificaciones | Sirven como referencia visual del flujo; la lógica debe migrar a RPC |
| Cálculos resumenCaja, filasMercaderia, disponibilidad | Solo referencia | Son la mejor especificación ejecutable de lo que el Blueprint define en prosa; deben reimplementarse en SQL |
| Tipos de data/mock*.ts | Solo referencia | Útiles para nombrar conceptos; el modelo deberá seguir BLUEPRINT.md sec. 8 |
| Semillas demo (productos/clientes/camiones) | Solo referencia | Sirven como datos de prueba iniciales |
| mockData.test.ts (3 casos de salidasPorMovimiento) | Solo referencia | Bonita intención, pero codifica una regla del prototipo, no del Blueprint |
| Hooks use* y localStorage | Debería reemplazarse | Toda la capa de datos y de autorización |
| AuthContext + Login demo | Debería reemplazarse | Supabase Auth + perfiles/roles en tablas protegidas |
| ConfiguracionDemo | Debería reemplazarse | No debe existir en producción en su forma actual |
| Dashboard + mockDashboard | Debería reemplazarse | Datos ficticios y alertas de vencimiento con lote (propuesta no aprobada) |
17. Qué NO debe trasladarse al sistema nuevo
 1. localStorage como fuente de verdad y cualquier capa de persistencia en el navegador (AGENTS.md §5).
 2. Autorización en el cliente (roles leídos de localStorage, guardas por ruta como única defensa).
 3. Login demo sin credenciales y la sesión como string en localStorage.
 4. Edición directa del stock y el "stock" como campo del producto.
 5. Stock del camión derivado al vuelo en lugar de libro de movimientos + saldos.
 6. Edición in-place del estado de la jornada (preparacion → abierta → cerrada) sin eventos ni registro de transición.
 7. "kg" como unidad de venta y cantidades decimales.
 8. Medio de pago único por venta; debe reemplazarse por desglose de pagos que sume el total.
 9. Toda la cuenta corriente simplificada (Fase 2).
10. "Completar con esperados" como atajo de conteo.
11. Alertas de vencimiento con lote (regla marcada PROPUESTA NO APROBADA en v1.4).
12. IDs generados en el cliente como mecanismo de identidad/idempotencia.
13. Roles administrador/deposito: no son los roles del negocio.
14. La pantalla de reinicio de demo tal como está.
15. Cualquier implementación que dependa de ADR-001 mientras siga en estado propuesta.
18. Decisiones pendientes
PENDIENTE Preguntas que no pueden responderse con el repositorio ni la documentación (no se inventó respuesta). Muchas coinciden con BLUEPRINT.md §15:
 1. Alcance contractual y fechas de 1A/1B (BLUEPRINT.md:429).
 2. Aprobación de ADR-001 (patrón RPC SECURITY DEFINER): sin esto no se puede crear el esquema ni escribir migraciones (docs/decisions/001-rpc-privilegiadas.md:4).
 3. Stock negativo transitorio en camión y marca excede_stock: propuesta no aprobada (BLUEPRINT.md:150,430).
 4. Anulación de ventas por el vendedor: propuesta no aprobada (:160,431).
 5. Prohibición de descuentos / precio de lista vs aplicado: propuesta no aprobada (:161,432).
 6. Retiro que supera el saldo sin bloqueo: propuesta no aprobada (:171).
 7. Vencimientos por partida (partidas_ingreso): propuesta no aprobada (:35,229,440).
 8. Medios de pago exactos admitidos (¿débito/QR? ¿saldo impago en una misma venta?) (:434).
 9. Campos mínimos, duplicados y validación del alta de clientes por el vendedor (:435).
10. Talonarios: serie, numeración, asignación, control de duplicados (:436).
11. Doble confirmación de retiro sin Internet (:437).
12. Gastos de ruta: tipos, autorizador, comprobante, efecto en rendición (:438).
13. Criterios de aptitud para devoluciones por producto (:439).
14. Precio de media pieza y reglas de redondeo (:441).
15. Día operativo, zona horaria y corte de jornada (:442).
16. Verificación de transferencias en Fase 1 (:445).
17. Valuación de faltantes (precio de venta histórico, costo, otro) y responsabilidades (:447).
18. Cantidad exacta de camiones, usuarios y catálogo; conectividad en depósito y ruta (:448).
19. Configuración de Vercel: si el proyecto usa apps/web como root directory (el propio progress-log.md:140 lo deja abierto).
20. Destino del prototipo: ¿se conserva como app de demo separada, se reemplaza en la misma carpeta o se archiva? No hay ninguna decisión registrada.
21. Estado real del CI en GitHub: si el workflow llegó a ejecutarse.
22. Origen de las versiones: el package-lock.json resuelve versiones que parecen futuras (React 19.3, Vite 8.3, TypeScript 6.0.3). PENDIENTE confirmar contra el registro npm real, ya que no se ejecutó ninguna instalación ni consulta de red en esta fase.
19. Punto de partida recomendado
Secuencia propuesta (no implementada, requiere aprobación humana previa en cada paso):
1. Aprobar o rechazar ADR-001 (y, si se aprueba, definir el propietario de mínimo privilegio y el entorno de staging). Sin esto, la Etapa 1 del Blueprint (:416) queda bloqueada. (Bloqueante.)
2. Resolver los pendientes de prioridad alta de BLUEPRINT.md §15 que afectan el diseño de tablas: unidades/media pieza, negativo transitorio, anulaciones, descuentos, medios de pago, vencimientos y zona horaria.
3. Decidir el destino del prototipo (conservarlo como referencia en una rama/etiqueta, o mantenerlo en apps/web/ y construir al lado). Recomiendo etiquetar el commit actual antes de tocar nada, para no perder la referencia visual.
4. Crear el esqueleto de Supabase (solo tras 1 y 2): esquema, empresas/perfiles/roles reales, y tests de seguridad de la sec. 12 desde el primer día. Nada de migraciones antes de eso.
5. Reimplementar por completo la capa de datos y de autorización en el frontend (reemplazar los 8 hooks por un cliente de RPC), reutilizando las pantallas solo como UI.
6. Empezar por stock, no por ventas: ubicaciones, movimientos_stock, saldos_stock y sus pruebas obligatorias (BLUEPRINT.md:306-311) antes de cualquier flujo de jornada.
7. No reutilizar ninguna regla del prototipo sin contrastarla con el Blueprint: el prototipo es referencia de UX, no de reglas.
8. Mantener el flujo de trabajo documentado: una rama por tarea, implementación + auditoría independiente + aprobación humana (AGENTS.md §2), y actualizar docs/progress-log.md al cerrar cada una.
20. Archivos inspeccionados
Raíz y configuración: BLUEPRINT.md (completo, 479 líneas), AGENTS.md, CLAUDE.md, README.md, .gitignore, opencode.json, .claude/settings.json, .opencode/agents/auditor.md, .github/workflows/ci.yml.
Documentación: docs/progress-log.md, docs/changelog.md, docs/decisions/README.md, docs/decisions/001-rpc-privilegiadas.md, docs/incidents/README.md, docs/incidents/2026-10-12-lint-falla-en-main.md, apps/web/README.md.
Aplicación (leídos completos): apps/web/package.json, package-lock.json (versiones resueltas), vite.config.ts, vitest.config.ts, playwright.config.ts, tsconfig.json, tsconfig.app.json, tsconfig.node.json, eslint.config.js, vercel.json, index.html, src/main.tsx, src/App.tsx, src/AuthContext.tsx, src/index.css, src/App.css, src/components/ProtectedRoute.tsx, src/components/layout/AppLayout.tsx, src/components/layout/Sidebar.tsx, los 8 hooks (useCamiones, useClientes, useCobros, useJornadas, useMovimientos, useProductos, useRetornos, useVentas), los 9 archivos de src/data/ (incluido mockData.test.ts), las 12 pantallas (Autoventa, Camiones, Clientes, ConfiguracionDemo, CuentasCorrientes, Dashboard, Jornadas, Login, Movimientos, Productos, Rendicion, Retornos), src/tests/smoke.test.ts, tests/example.spec.ts.
Estado del repositorio: git status (limpio), git ls-files (73 archivos versionados), git log --oneline --all (21 commits, 4 ramas, sin tags), análisis del último commit 6e97696, y búsquedas de TODO/FIXME/HACK/temporary/mock/fake/demo/prototype/hardcoded/localhost/service_role/anon/apikey/env/fetch/localStorage/INSERT/UPDATE/DELETE y de archivos *.sql/*.yml/*.env*.
Cierre del informe
- Naturaleza del repositorio: prototipo/demo de frontend, sin backend ni base de datos; documentación de proyecto sólida y madura, código de prototipo. HECHO
- Nada se modificó: no se creó INVENTARIO_ETAPA_0.md ni ningún otro archivo; no se ejecutaron migraciones, instalaciones ni comandos contra producción; no se cambió de rama ni el estado de Git. HECHO
- Bloqueo vigente: ADR-001 sigue en estado propuesta y hay 5 reglas marcadas PROPUESTA NO APROBADA (BLUEPRINT.md v1.4). Ninguna tarea de base de datos puede avanzar sin decisión humana (AGENTS.md §3).

---

## Erratas y aclaraciones validadas por Codex

Esta sección registra las correcciones surgidas de las revisiones independientes de Codex (primera: **APPROVE WITH CORRECTIONS**; segunda: **CHANGES REQUIRED**; ver «Revisiones independientes» en el apéndice de verificación). **El informe original se conserva como registro histórico auditable**: salvo la corrección editorial del título (E-9), ninguna afirmación del cuerpo original se reescribe; las erratas **E-1 a E-12 prevalecen** sobre las afirmaciones originales a las que refieren (ver la nota de «Precedencia» al inicio del documento). E-1, E-3 y E-4 se **ampliaron en la segunda ronda** de correcciones. Cada ítem cita la afirmación original afectada y precisa su efecto.

### Correcciones importantes

**E-1 — Alcance del bloqueo por ADR-001** (afecta a §12, cierre de «Tests existentes»; §18 ítem 2; §19 pasos 1 y 4; y «Cierre del informe», viñeta «Bloqueo vigente»).
Afirmación original (§12): «ni ninguna de las pruebas obligatorias de BLUEPRINT.md sec. 12 (todas requieren base de datos + pgTAP, **bloqueadas por ADR-001** en estado propuesta)».
Afirmación original («Cierre del informe»): «ADR-001 sigue en estado propuesta y hay 5 reglas marcadas PROPUESTA NO APROBADA (BLUEPRINT.md v1.4). **Ninguna tarea de base de datos puede avanzar** sin decisión humana (AGENTS.md §3).»
Precisión validada y **supersesión**: la segunda afirmación es **demasiado amplia** y queda **sustituida** por la interpretación vigente siguiente.
- **No todas** las pruebas del Blueprint quedan bloqueadas por ADR-001. Las pruebas de **dominio** y de **integración** pueden prepararse de forma independiente; sólo permanecen bloqueadas las que dependen de la arquitectura propuesta de **RPC privilegiadas** (wrappers `SECURITY DEFINER` sobre esquema privado, objeto de ADR-001, aún en estado propuesta).
- **Pueden continuar** la documentación, el análisis arquitectónico, las pruebas independientes y el trabajo de diseño que **no dependa** de la arquitectura propuesta.
- **Siguen bloqueadas** las **migraciones de base de datos** y la implementación que dependa de la arquitectura propuesta de RPC privilegiadas, hasta que exista la aprobación correspondiente (que incluye el caso de §19 pasos 1 y 4: «Sin esto, la Etapa 1 … queda bloqueada» y «Nada de migraciones antes de eso»).

**E-2 — Los cálculos del prototipo son material de caracterización** (afecta a §16, fila «Cálculos resumenCaja, filasMercaderia, disponibilidad»).
Afirmación original (§16): esos cálculos «son la mejor especificación ejecutable de lo que el Blueprint define en prosa».
Precisión validada: son **material de caracterización**, no una especificación ejecutable autoritativa. **Toda fórmula de negocio debe validarse contra `BLUEPRINT.md` y las ADR aprobadas** antes de reimplementarse; el prototipo no define la regla.

**E-3 — Alcance del uso de RPC** (afecta a §7, encabezado «todas reemplazables por RPC en el sistema nuevo», y a §19 paso 5, «reemplazar los 8 hooks por un cliente de RPC»).
Afirmación original (§19 paso 5): «Reimplementar por completo la capa de datos y de autorización en el frontend (reemplazar los 8 hooks por un cliente de RPC)…».
Precisión validada: las **RPC son exigibles para las operaciones críticas de stock y dinero** (escrituras). Las **lecturas ordinarias** y las **operaciones CRUD permitidas** pueden resolverse con **RLS** y funciones **`SECURITY INVOKER`**, según lo defina `BLUEPRINT.md`, sin requerir el patrón de RPC privilegiada. En consecuencia, **reemplazar los ocho hooks por RPC no es un requisito arquitectónico aprobado**: es una opción de implementación. Lo obligatorio es que las **escrituras críticas de stock y dinero** pasen por RPC en la base, no que toda la capa de datos se reescriba como RPC.

**E-4 — Cantidades enteras y pieza/media pieza ya definidas** (afecta a §18 ítem 14 y a §19 paso 2; se relaciona con §13 D5).
Afirmación original (§18 ítem 14): «Precio de media pieza y reglas de redondeo (:441)». Afirmación original (§19 paso 2): «Resolver los pendientes de prioridad alta de BLUEPRINT.md §15 que afectan el diseño de tablas: **unidades/media pieza**, negativo transitorio, anulaciones, descuentos, medios de pago, vencimientos y zona horaria».
Precisión validada: la **representación de cantidades con enteros en la unidad mínima** y la **conversión pieza / media pieza ya están definidas** por el Blueprint (secciones 7.1 y 8). Lo que permanece pendiente en ese punto es **únicamente el precio de la media pieza y las reglas de redondeo**, no la definición de unidades ni la conversión pieza/media pieza.

### Correcciones menores

**E-5 — Se retira una afirmación sin respaldo** (afecta a §8, hallazgo S1).
Afirmación original (S1): la autorización en el cliente «se elude cambiando `distribuidora_sesion_demo_v1` a `admin-demo` desde DevTools, o **llamando a las funciones de los hooks desde la consola**».
Precisión validada: la segunda vía (invocar los hooks desde la consola) **no está respaldada por evidencia del repositorio** y **se retira como afirmación vigente**. La oración original se conserva como registro histórico. El hallazgo S1 se mantiene por el resto de su fundamento (autorización y persistencia delegadas al cliente; sesión editable en `localStorage`).

**E-6 — Relación entre las dos representaciones de stock** (afecta a §9, «Hay dos "stocks" paralelos que nunca se concilian»).
Precisión validada: las dos representaciones **no son fuentes independientes**. El stock de depósito es el saldo almacenado del producto (`producto.stock`) y el stock / disponibilidad del camión se **deriva** de ese saldo (menos lo cargado, más los retornos aprobados). Están vinculadas por los mismos datos; lo que falta es un **libro de movimientos** que las concilie de forma trazable, no un vínculo entre ellas.

**E-7 — Tercer archivo de respaldo ignorado** (afecta a §3, lista de backups ignorados).
Afirmación original (§3): `opencode.json.backup / opencode.json.pre-superpowers.backup  (ignorados por .gitignore)`.
Precisión validada: existe un **tercer archivo ignorado**, `apps/web/opencode.json.backup`, además de los dos anteriores en la raíz.

**E-8 — Alcance del hallazgo «sin secretos»** (afecta a §1, «no hay claves ni secretos», y a §8, «ni secretos»).
Calificación validada: la ausencia de secretos es un hallazgo **acotado al repositorio inspeccionado y a las búsquedas ejecutadas** (`service_role`, `apikey`, `import.meta.env`, `process.env`, `.env*`, etc.). **No es una afirmación absoluta** sobre otros entornos, el historial de Git, configuraciones locales fuera del repositorio ni sistemas externos.

**E-9 — Corrección editorial del título** (afecta al título del documento).
El texto recibido comenzaba con `nventario Etapa 0` (sin la «I» inicial). El título visible se corrige a **`# Inventario Etapa 0`**. Es la **única edición aplicada al cuerpo del informe original**; queda registrada aquí para trazabilidad. Ver también la nota de transcripción del apéndice.

**E-10 — Contexto de las observaciones de árbol limpio** (afecta a §20, «Estado del repositorio: git status (limpio)», y al encabezado «Base: … (árbol limpio, sin cambios locales)»).
Precisión validada: esas observaciones describen el **contexto de la auditoría original** (rama `chore/configuracion-agentes`, commit `6e97696`), no el estado del árbol después de crear este documento.

**E-11 — Alcance de la afirmación de cierre del informe** (afecta a «Cierre del informe», viñeta «Nada se modificó»).
Afirmación original: «Nada se modificó: no se creó INVENTARIO_ETAPA_0.md ni ningún otro archivo».
Precisión validada: esa afirmación describe la **sesión de auditoría original, antes de que existiera este documento**. No contradice la creación posterior de `INVENTARIO_ETAPA_0.md` por la tarea actual.

**E-12 — Reclasificación de DC-5** (afecta al apéndice de verificación y al encabezado «Base»).
La diferencia de rama entre el informe (`chore/configuracion-agentes`) y este documento (`docs/inventario-etapa-0`) se **reclasifica como contexto de procedencia, no como discrepancia material**, dado que el commit es el mismo (`6e97696`).

---

## Verificación del inventario contra el repositorio actual

Verificación de solo lectura, realizada el 16/10/2026, contra el estado actual del repositorio. No se modificó el informe original: las discrepancias se documentan únicamente aquí.

### Rama y commit de esta verificación

| Dato | Valor |
|---|---|
| Rama actual | `docs/inventario-etapa-0` |
| Commit (`git rev-parse HEAD`) | `6e97696dc76afa0dee7f5d410f72ff7dc213c088` |
| Commit del informe | `6e97696` — **coincide** (el mismo hash) |
| `git rev-parse chore/configuracion-agentes` | `6e97696dc76afa0dee7f5d410f72ff7dc213c088` (idéntico) |
| Árbol de trabajo | limpio antes de crear este documento |

### Notas de transcripción (no son hallazgos de la auditoría)

- **Fuente usada:** el informe se recibió en la conversación. El archivo `informe_temporal.txt` indicado por el usuario **no existe** en la raíz del repositorio (`ls`, `find` y `git status --ignored` no lo encuentran), por lo que no pudo leerse ni cotejarse contra el texto. Todo lo verificado abajo se contrastó contra el estado real del repositorio, no contra un archivo fuente.
- **Formato de tablas:** las tablas que en el texto recibido estaban separadas por tabulaciones se transcribieron con separadores `|` para que Markdown las renderice. El texto de cada celda se conservó literal.
- **Título (corregido por Codex; ver E-9):** el texto recibido comienza con `nventario Etapa 0` (sin la "I" inicial). El título visible se corrigió a `# Inventario Etapa 0`; es la única edición aplicada al cuerpo del original y queda registrada en la sección de erratas.

### Resultado global

El informe describe con precisión el estado del repositorio. Se cotejaron las referencias de las 20 secciones (rutas, rangos de línea y hallazgos). Resultado: la gran mayoría **VERIFICADA**; cuatro **DISCREPANCIAS** materiales de detalle (**DC-1 a DC-4**; ninguna cambia las conclusiones del informe); un ítem reclasificado como **contexto de procedencia** (**DC-5**, ver E-12); y los ítems de la sección 18 que por su naturaleza **no** se verifican contra el repositorio (**NOT VERIFIED / PENDIENTE**). No se inventó evidencia para ningún ítem no verificable.

### Revisiones independientes (Codex)

- **Primera revisión:** veredicto **APPROVE WITH CORRECTIONS** (sobre el commit `6e97696`). Solicitó 4 correcciones importantes y 8 menores.
- **Correcciones de OpenCode (ronda 1):** se incorporaron las erratas E-1 a E-12 en la sección «Erratas y aclaraciones validadas por Codex».
- **Segunda revisión:** veredicto **CHANGES REQUIRED**. Planteó 5 hallazgos sobre la ronda 1.
- **Correcciones de OpenCode (ronda 2, actual):** se resuelven los 5 hallazgos: nota de **precedencia** al inicio del documento, y ampliación de **E-1** (supersesión de la afirmación amplia sobre el bloqueo de base de datos), **E-3** (alcance de RPC y §19 paso 5) y **E-4** (§19 paso 2).
- **Estado:** esta versión corregida **no ha pasado todavía una revisión final**; el veredicto CHANGES REQUIRED **no está resuelto** por una nueva revisión. Aprobación humana pendiente.

### Discrepancias encontradas (el informe original no se modifica)

| # | Sección del informe | Texto del informe | Estado real del repositorio | Clasificación |
|---|---|---|---|---|
| DC-1 | §20 "Archivos inspeccionados" | "los 9 archivos de src/data/ (incluido mockData.test.ts)" | `apps/web/src/data/` tiene **10** archivos: 9 `mock*.ts` de tipos/semillas + `mockData.test.ts`. Es decir, 9 **sin** contar el test; 10 contando el test. §3 lo describe bien ("mock*.ts (9 archivos...) + mockData.test.ts"); §20 contradice a §3. | DISCREPANCY |
| DC-2 | §20 "Estado del repositorio" | "git log --oneline --all (21 commits, ...)" | `git log --oneline --all \| wc -l` = **22**; `git rev-list --all --count` = 22; `git rev-list HEAD --count` = 22. | DISCREPANCY |
| DC-3 | §15 punto 4 | "esCantidadValida existe en ... Retornos.tsx:29-44" | En `Retornos.tsx:29-44` la función existe con la misma lógica pero se llama `cantidadValida`, no `esCantidadValida`. En `useRetornos.ts:10-25` sí se llama `esCantidadValida`. | DISCREPANCY |
| DC-4 | §15 punto 4 | "esCantidadValida existe en ... useJornadas.ts:186-197" | En `useJornadas.ts:186-197` **no hay** una función con ese nombre: es la lógica de validación (entero vs kg) escrita **en línea** dentro de `cerrarJornada`. | DISCREPANCY |

**Contexto de procedencia (no es una discrepancia material):** el informe se redactó en la rama `chore/configuracion-agentes`; este documento se crea en `docs/inventario-etapa-0`. Ambos apuntan al **mismo commit** `6e97696`. Reclasificado por **E-12** (antes figuraba como DC-5).

### Otros matices verificados (no son discrepancias, se aclaran por precisión)

- **"8 claves distribuidora_*_demo_v1" (§2, §15.3):** existen **9** coincidencias del patrón `distribuidora_*_demo_v1` en `apps/web/src`: 8 de dominio (productos, clientes, camiones, jornadas, ventas, movimientos, retornos, cobros) y 1 de sesión (`distribuidora_sesion_demo_v1`). El informe cuenta 8 y menciona la sesión por separado, por lo que el número es correcto si se excluye la sesión.
- **Rangos de línea aproximados:** varias citas caen dentro del bloque correcto pero con ±1–3 líneas respecto del inicio exacto (p. ej. `Productos.tsx:302` → el texto "Stock inicial" está en la línea 304; `Rendicion.tsx:226-266` → el bloque `productosCuarentena` arranca en la 227; `Dashboard.tsx:77-107` → la sección de alertas abarca ~76-105). En todos los casos el contenido citado existe y corresponde.
- **Sección 18, ítem 7:** el informe lo cita como "PROPUESTA NO APROBADA"; en `BLUEPRINT.md:35` la marca textual es "PROPUESTA TÉCNICA NO APROBADA". Igual queda comprendido por la prohibición de `AGENTS.md` §3.

### Detalle verificado (VERIFIED)

**Estado del repositorio**
- `git ls-files | wc -l` = **73** ✔; `git tag` = **0** ✔.
- Ramas: 4 locales hoy (`main`, `chore/configuracion-agentes`, `chore/tarea-001-preparar-repo`, `docs/inventario-etapa-0`) y `origin/main`; al momento del informe, 4 refs de rama contando `origin/main` ✔.
- `git status` limpio al iniciar ✔.

**Stack (§2)**
- `package.json:15-22` dependencias; `package.json:24-37` devDependencies ✔.
- Versiones resueltas en `package-lock.json`: react **19.3.0**, react-dom **19.3.0**, vite **8.3.4**, typescript **6.0.3**, eslint **10.12.0**, @tailwindcss/vite **4.3.3** ✔.
- `vite.config.ts:6` (`plugins: [react(), tailwindcss()]`) ✔; `src/index.css:1` (`@import "tailwindcss"`) ✔.
- `tsconfig.app.json:4-23` (target es2023, moduleResolution bundler, jsx react-jsx) ✔; sin `strict` ni `strictNullChecks` ✔ (§14 riesgo 10).
- `@playwright/test` "1.64.0" y `vitest` "5.0.2" fijadas exactas; el resto con `^`/`~` ✔.
- `vitest.config.ts` incluye `src/**/*.test.ts(x)` y excluye `tests/` ✔; `playwright.config.ts` levanta el dev server con Vite ✔.
- No hay Prettier ✔. Único workflow: `.github/workflows/ci.yml` ✔; jobs `verificar` (20-33, bloqueante) y `lint` (`continue-on-error: true`, 35-49) ✔.
- `apps/web/vercel.json:4-9` rewrites a `/index.html` ✔.
- Sin `.env*` ni `.env.example` ✔. `eslint.config.js:12-17` usa `recommended` (no type-aware) ✔.

**Estructura (§3)**
- `BLUEPRINT.md` 479 líneas ✔; `docs/progress-log.md` 141 líneas, 2 entradas ✔; `docs/changelog.md` sin versiones entregadas ✔.
- `docs/decisions/`: `001-rpc-privilegiadas.md` (estado propuesta, línea 4) + `README.md` ✔. `docs/incidents/`: `2026-10-12-lint-falla-en-main.md` + `README.md` ✔.
- `opencode.json`: permisos `edit/bash/external_directory: ask` + plugin `superpowers@...#v6.4.2` ✔. `.opencode/agents/auditor.md`: `edit: deny`, `bash: deny` ✔. `.claude/settings.json`: `defaultMode: default` ✔.
- `apps/web/public/`: `favicon.svg`, `icons.svg` ✔. `apps/web/src/App.css` 184 líneas y **no se importa** en ningún lado (muerto) ✔; `src/main.tsx` importa `./index.css` ✔.
- `apps/web/src/hooks/` = **8** hooks ✔; `apps/web/src/pages/` = **12** pantallas ✔; `components/`: `ProtectedRoute.tsx`, `layout/AppLayout.tsx`, `layout/Sidebar.tsx` ✔.
- No existen `supabase/`, `migrations/`, `src/` en la raíz ni `.env.example` ✔; `*.sql` = 0 ✔.

**Recuentos citados**
- 5 productos / 3 clientes / 3 camiones semilla ✔ (`mockProductos.ts:13-59`, `mockClientes.ts:16-50`, `mockCamiones.ts:17-45`).
- 5 casos unitarios + 1 E2E: `smoke.test.ts` (1) + `mockData.test.ts` (1 ids + 3 movimientos) + `example.spec.ts` (1) ✔.

**Funcionalidades, roles y rutas (§4, §5)**
- Roles `administrador/vendedor/deposito` en `AuthContext.tsx:9-12` ✔; 3 usuarios fijos en `:22-38` ✔; sesión en `localStorage` (`:20`) ✔.
- `App.tsx:73-183` define rutas; `:92-99` clientes (admin+vendedor); `:128-131` redirección de `/ventas`; `:181` `/configuracion-demo` fuera de `ProtectedRoute`; `:50-62` redirección por rol del Inicio; `:32-48` conjuntos de roles ✔.
- Todas las asignaciones rol↔ruta de la tabla de §5 coinciden con `App.tsx` ✔ (productos/camiones/jornadas/retornos admin+depósito; clientes/autoventa/cuentas admin+vendedor; movimientos todos; rendición solo admin).
- `Sidebar.tsx:25-96` menú; `:71-96` filtrado por rol ✔.
- Funcionalidades "Not found": gastos de ruta, retiros de efectivo, ajustes de stock, reportes, talonarios, auditoría ✔ (sin modelo, sin UI).
- `Camiones.tsx:125-134` validación de patente única ✔; `Productos.tsx:132-146` la edición no altera stock ✔; `Productos.tsx:301-304` "Stock inicial" solo para productos nuevos ✔; `Clientes.tsx:494-501` botón "Editar" sin condicionar por rol ✔.
- `Dashboard.tsx:9-13` importa `mockDashboard` (stats ficticias `mockDashboard.ts:3-8` y `alertasVencimiento` `:10-25`) ✔.

**Modelo, RPC y lógica (§6, §7, §9, §10)**
- Rangos de definición de tipos verificados: `mockProductos.ts:3-11` ✔; `mockClientes.ts:4-14` ✔; `mockCamiones.ts:7-15` ✔; `mockJornadas.ts:2-5, 7-13, 16-33, 35-47` ✔; `mockVentas.ts:2-5, 7-14, 16-29` ✔; `mockMovimientos.ts:24-43, 46-59` ✔; `mockRetornos.ts:2-12, 14-22` ✔; `mockCobros.ts:4-17` ✔.
- `salidasPorMovimiento` devuelve `[]` para `devolucion` (`mockMovimientos.ts:57-58`) ✔.
- Funciones citadas en §7: `calcularSaldoCliente` (`useCobros.ts:70-88`) ✔; `stockReservado`/`disponibilidad` (`Jornadas.tsx:49-106`) ✔; `cantidadesDescontadas`/`productosCamion` (`Autoventa.tsx:111-151`) ✔; `filasMercaderia` (`Rendicion.tsx:159-224`) ✔; `resumenCaja` (`Rendicion.tsx:95-157`) ✔; `cierreValido`/`leerJornadas` (`useJornadas.ts:11-99`) ✔.
- Duplicación de la lógica de stock en 4 pantallas (INFERENCIA): confirmada ✔ (`Autoventa.tsx:111-151/292-376`, `Movimientos.tsx:105-140/276-312`, `Rendicion.tsx:159-224`, `Jornadas.tsx:49-106`).
- `crypto.randomUUID()` en `Autoventa.tsx:277`, `Movimientos.tsx:232`, `CuentasCorrientes.tsx:201` (además de `Retornos.tsx:262` y `Jornadas.tsx:188`) ✔.
- IDs huérfanos resueltos con fallback: `Jornadas.tsx:466` ("Camión no encontrado") ✔; `Rendicion.tsx:544` (fallback de camión) ✔.
- Aviso "las cargas no descuentan inventario real" en `Jornadas.tsx:552-556` ✔.
- Guardas citadas: no cargar más que lo disponible (`Jornadas.tsx:180-185`) ✔; no vender más que cargado−vendido−mermado (`Autoventa.tsx:298-372`) ✔; un solo retorno por jornada (`useRetornos.ts:86-92`) ✔; no cerrar con esperado negativo (`Rendicion.tsx:289-292` y `367-372`) ✔.
- Dinero: medio único (`mockVentas.ts:26`) ✔; `resumenCaja` suma efectivo de ventas+cobros (`Rendicion.tsx:140-141`) ✔; cobro no supera saldo (`useCobros.ts:133-135`, `CuentasCorrientes.tsx:174-177`) ✔; transferencia con referencia (`useCobros.ts:108-113`) ✔; "importes informados, no operaciones bancarias" (`Rendicion.tsx:979-983`) ✔; redondeo `Math.round(x*100)/100` (`useCobros.ts:9-11`, `Rendicion.tsx:131`) ✔; "Completar con esperados" (`Rendicion.tsx:328-351`) ✔; cierre guardado (`:434-444`), observación obligatoria (`:417-425`), `window.confirm` (`:427-432`) ✔.

**Seguridad y tests (§8, §12)**
- Búsquedas en `apps/web/src`: `service_role` 0, `apikey` 0, `import.meta.env` 0, `process.env` 0, `dangerouslySetInnerHTML` 0, `innerHTML` 0, `eval(` 0, `new Function` 0 ✔.
- Sin RLS, sin Supabase, sin `auth.uid()`, sin `empresa_id` ✔.
- S8: `useMovimientos.ts:20` usa `(p: any)` ✔; coincide con el incidente de lint (`docs/incidents/2026-10-12-lint-falla-en-main.md:13`, fila `useMovimientos.ts | 20`) ✔.
- Tests: `smoke.test.ts:3-6` ✔; `mockData.test.ts:17-23` y `:25-79` ✔; `example.spec.ts:3-7` (URL absoluta) ✔.
- Sin TODO/FIXME/HACK en `apps/web/src` (grep -w = 0) ✔.

**Diferencias documentación↔código (§13, D1–D20)**
- Verificadas una por una contra `BLUEPRINT.md` y el código: D1 (`:44`, `Productos.tsx:132-146`), D2 (`:276`, `ConfiguracionDemo.tsx:164-184`), D3 (`:260-268`, `AuthContext.tsx:9-12`), D4 (`:163`, `App.tsx:92-99`, `Clientes.tsx:494-501`), D5 (`:34,110-113`, `mockProductos.ts:1`, `Autoventa.tsx:229-234/346-357`), D6 (`:78`, `CuentasCorrientes.tsx`, `useCobros.ts`), D7 (`:154`, `mockJornadas.ts:2-5`), D8 (`:156`, `useJornadas.ts:121-130`), D9 (`:164`, `Rendicion.tsx:328-351`), D10 (`:162`, `mockVentas.ts:26`, `Autoventa.tsx:729-760`), D11 (`:169-172`, sin resultados), D12 (`:63,173`, sin resultados), D13 (`:212`, `Rendicion.tsx:975-983`), D14 (`:146-147`, `Rendicion.tsx:209-212`), D15 (`:142-145`, `mockMovimientos.ts:57-58`, `Retornos.tsx:469-474`), D16 (`:35,229`, `mockDashboard.ts:10-25`, `Dashboard.tsx:77-107`), D17 (`:159,239-241`, `useVentas.ts:69-71`), D18 (`:127`), D19 (`:359-373`, `AGENTS.md §8`), D20 (sec. 11, sin implementación) — **todas VERIFIED** ✔.
- Cita de §13: `docs/progress-log.md:124-131` identifica D1/D3/D5/D6 ✔.

**Vencimientos por partida / reglas no aprobadas**
- `BLUEPRINT.md:35` = "Vencimientos: ... **PROPUESTA TÉCNICA NO APROBADA** ..." ✔; `:229` = `partidas_ingreso` (propuesta) ✔.
- `BLUEPRINT.md:44` ("El stock nunca se edita a mano") ✔; `:45` ("Separación de responsabilidades") ✔; `:46` ("Una jornada cerrada no se modifica") ✔; `:99` (libros solo de inserción) ✔; `:113` (cantidades enteras) ✔; `:118-123` (ubicaciones incl. cuarentena) ✔; `:136-148` (tipos de movimiento) ✔; `:150` (negativo transitorio propuesta) ✔; `:154` (6 estados) ✔; `:156` (una jornada por camión y fecha) ✔; `:160/:161/:171` (anulación/descuentos/retiro, propuestas) ✔; `:173` (gastos de ruta) ✔; `:276` (sin INSERT/UPDATE/DELETE) ✔; `:306-311` (pruebas de stock) ✔; `:415-416` (Etapa 0-Inventario) ✔; `:429` (alcance contractual) ✔; `:430/:432` (propuestas) ✔; `:434-448` (pendientes §15) ✔.
- `docs/decisions/001-rpc-privilegiadas.md:4` = estado **propuesta (NO aprobada)** ✔ → ADR-001 sigue bloqueando la Etapa 1, como dice el informe.

### Ítems NO verificados contra el repositorio (NOT VERIFIED)

- **§18 "Decisiones pendientes", ítems 1–18:** son decisiones de negocio/negocio-técnicas abiertas, no afirmaciones sobre el repositorio. No se pueden resolver con evidencia del código; el propio informe las marca `PENDIENTE`. **NOT VERIFIED** (por naturaleza; no se inventó respuesta).
- **§18 ítem 19 (root directory de Vercel):** requiere consultar el panel de Vercel, fuera del repositorio. **NOT VERIFIED**.
- **§18 ítem 21 (¿corrió el workflow en GitHub Actions?):** requiere consultar GitHub, fuera del repositorio. **NOT VERIFIED**.
- **§18 ítem 22 (versiones "futuras" contra el registro npm real):** requiere consultar el registro npm por red; no se hizo ninguna instalación ni consulta de red en esta verificación. Las versiones **resueltas en el lockfile** sí se verificaron (arriba); su existencia publicada en npm queda **NOT VERIFIED**.
- **§18 ítem 20 (destino del prototipo):** el informe afirma "no hay ninguna decisión registrada" — eso sí se verificó: `docs/decisions/` solo contiene `001-rpc-privilegiadas.md` (propuesta) y `README.md`. **VERIFIED** en cuanto a la ausencia de decisión.
- **§18 ítem 2 (ADR-001 en estado propuesta):** **VERIFIED** (`docs/decisions/001-rpc-privilegiadas.md:4`).

### Conclusión de la verificación

El inventario refleja el estado real del repositorio en el commit `6e97696`. No se detectó ninguna afirmación sustantiva falsa. Las cuatro discrepancias materiales (DC-1 a DC-4) son de detalle: dos recuentos (archivos de `src/data/` y cantidad de commits) y dos nombres/rangos de funciones de validación. La diferencia de rama (antes DC-5) queda como contexto de procedencia (E-12). Ninguna altera el diagnóstico ni las recomendaciones del informe. Los ítems no verificables son decisiones abiertas o datos externos al repositorio, tal como el propio informe declara. Las revisiones independientes de Codex se registran en el apéndice: la **primera** fijó **APPROVE WITH CORRECTIONS**; la **segunda**, sobre la versión corregida, **CHANGES REQUIRED**. La ronda de correcciones en curso (nota de precedencia + ampliación de E-1, E-3 y E-4) queda **pendiente de una revisión final** y de aprobación humana.
