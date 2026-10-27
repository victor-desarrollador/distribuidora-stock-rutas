// Claves operativas de localStorage del prototipo (ADR-005: modelo por peso).
// Única definición: los hooks y ConfiguracionDemo la importan.
// Todas están en v5 por inicialización limpia (ADR-005 D-R4): las siete rotan
// juntas y no se lee, copia, reinterpreta ni borra ninguna clave v4 (medias
// piezas), v3 o v2. Una cantidad v4 en medias piezas nunca se interpreta como
// gramos.
export const CLAVES_STORAGE = {
  productos: "distribuidora_productos_demo_v5",
  jornadas: "distribuidora_jornadas_demo_v5",
  ventas: "distribuidora_ventas_demo_v5",
  cobros: "distribuidora_cobros_demo_v5",
  movimientos: "distribuidora_movimientos_demo_v5",
  retornos: "distribuidora_retornos_demo_v5",
  camiones: "distribuidora_camiones_demo_v5",
} as const;

// Clientes no depende del modelo de unidades ni de precios: conserva su clave.
export const CLAVE_CLIENTES = "distribuidora_clientes_demo_v2";
