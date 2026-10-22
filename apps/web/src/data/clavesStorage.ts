// Claves operativas de localStorage del prototipo (ADR-003).
// Única definición: los hooks y ConfiguracionDemo la importan.
// Todas están en v4 por inicialización limpia: no se lee, copia, reinterpreta
// ni borra ninguna clave v3 o v2. Clientes (v2) y sesión (v1) no dependen del
// modelo de precios y conservan su clave.
export const CLAVES_STORAGE = {
  productos: "distribuidora_productos_demo_v4",
  jornadas: "distribuidora_jornadas_demo_v4",
  ventas: "distribuidora_ventas_demo_v4",
  cobros: "distribuidora_cobros_demo_v4",
  movimientos: "distribuidora_movimientos_demo_v4",
  retornos: "distribuidora_retornos_demo_v4",
  camiones: "distribuidora_camiones_demo_v4",
} as const;