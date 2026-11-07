// Rutas de las pantallas de demostración (D1/D2).
//
// La habilitación NO se decide aquí: App.tsx usa `import.meta.env.DEV` escrito
// en línea, porque Vite lo reemplaza de forma estática y el bundler elimina
// entonces la importación diferida de la pantalla demo del build de producción.
// Una constante exportada desde otro módulo NO produce esa eliminación (se
// comprobó: el chunk de JornadasDemo quedaba en dist). Ocultar un enlace tampoco
// protege una ruta: en producción la ruta misma no existe.
export const RUTA_JORNADAS_DEMO = "/demo/jornadas";
