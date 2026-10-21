// Claves operativas de localStorage del prototipo (ADR-002).
// Única definición: los hooks y ConfiguracionDemo la importan.
//
// Todas están en v3 por inicialización limpia: no se lee, copia, reinterpreta
// ni borra ninguna clave v2. Clientes (v2) y sesión (v1) no dependen del
// modelo de precios y conservan su clave.
export const CLAVES_STORAGE = {
  productos: "distribuidora_productos_demo_v3",
  jornadas: "distribuidora_jornadas_demo_v3",
  ventas: "distribuidora_ventas_demo_v3",
  cobros: "distribuidora_cobros_demo_v3",
  movimientos: "distribuidora_movimientos_demo_v3",
  retornos: "distribuidora_retornos_demo_v3",
  camiones: "distribuidora_camiones_demo_v3",
} as const;
