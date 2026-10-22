# ADR-004 — Cobros asociados a jornadas cerradas

**Fecha:** 22/10/2026
**Estado:** PROPUESTA — NO APROBADA
**Versión:** 1.0

> Esta ADR registra una decisión pendiente. No autoriza cambios de código, pruebas, datos, Blueprint, backend ni reglas de negocio.

## 1. Contexto

El frontend permite registrar cobros y, cuando el cobro incluye `jornadaId`, el comportamiento actual exige que la jornada exista y esté abierta. El Bloque E reforzó ese comportamiento preexistente mediante una revalidación de la jornada inmediatamente antes de persistir; no creó ni aprobó una regla de negocio nueva.

El Blueprint no formaliza si un cobro puede asociarse a una jornada cerrada. Su principio general indica que una jornada cerrada no se modifica, pero no define si un cobro posterior constituye una modificación de la jornada, una operación financiera independiente o una referencia histórica permitida.

## 2. Decisión pendiente

Debe resolverse mediante aprobación humana la siguiente pregunta:

> ¿Un cobro puede asociarse a una jornada cerrada?

Esta ADR no responde la pregunta ni selecciona una alternativa. Hasta que exista una decisión aprobada, el comportamiento actual del prototipo sigue exigiendo una jornada abierta cuando `jornadaId` existe, únicamente como comportamiento preexistente reforzado por el Bloque E.

## 3. Alternativas a evaluar

- Permitir la asociación a una jornada cerrada como operación financiera posterior e independiente, definiendo su efecto sobre rendición, saldos, auditoría y reportes.
- Exigir jornada abierta y derivar los cobros posteriores a otro mecanismo, definiendo cuál es su referencia operativa.
- Permitirla solo bajo condiciones o roles específicos, que deberán quedar formalizados y probados.

Ninguna alternativa está aprobada.

## 4. Consecuencias

- No se modifica código ni se agregan pruebas que asuman una alternativa como regla vigente.
- No se modifica el Blueprint hasta que haya aprobación humana.
- Una decisión futura deberá precisar el efecto sobre jornadas, rendiciones, cuentas corrientes, auditoría y backend antes de implementarse.
- ADR-001 continúa **PROPUESTA — NO APROBADA** y no resulta afectada por este registro.
