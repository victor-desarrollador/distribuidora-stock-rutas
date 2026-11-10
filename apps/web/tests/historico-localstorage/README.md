# Suites históricas de localStorage (prototipo demo)

Este directorio contiene pruebas Playwright que pertenecen al **prototipo de
demostración sobre `localStorage`**, cuyas rutas operativas fueron retiradas en
la tarea `chore/retirar-rutas-demo-negocio`:

- `/demo/jornadas`, `/autoventa`, `/ventas`, `/movimientos`, `/rendicion`,
  `/retornos`, `/cuentas`, `/configuracion-demo`.

**Estos archivos NO forman parte de la colección activa de Playwright.**
`playwright.config.ts` los excluye mediante `testIgnore:
['historico-localstorage/**']`. El patrón es relativo a `testDir: './tests'`.

**Motivo de exclusión:** las rutas a las que navegan ya no existen en el router
(`App.tsx`), por tanto los specs fallarían si se ejecutaran como parte de la
suite activa. Se conservan aquí, **sin borrar**, como referencia histórica del
comportamiento del prototipo demo. No se presentan como pruebas actuales ni se
incluyen en la ejecución CI de `npx playwright test`.

Verificación del 09/11/2026: `npx playwright test --list` descubre 172 pruebas
en 17 archivos (1 setup y 171 pruebas actuales) y ningún caso de este
directorio. Incluso al filtrar por `tests/historico-localstorage`, la
configuración vigente devuelve `No tests found` y 0 pruebas; para recuperarlas
haría falta una configuración separada y una tarea expresamente autorizada.

**No reintegrar en la colección activa mientras las rutas retiradas no
vuelvan a existir y estén conectadas a Supabase (no a localStorage).**
