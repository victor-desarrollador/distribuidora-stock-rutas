# Rollbacks manuales — artefactos experimentales

> **Estado: NO AUTORIZADOS para operaciones reales.**
> Estado declarado por la [ADR-009](../../docs/decisions/009-migraciones-hacia-adelante-y-rollbacks.md), **APROBADA PARA VALIDACIÓN CONTROLADA** el 04/11/2026, 23:29 (`America/Argentina/Tucuman`), F-1 a F-9.

## Advertencia

- **Prohibido ejecutarlos** en staging, en producción y en cualquier base con datos reales o cuya identidad no esté verificada.
- **No son un mecanismo de recuperación.** La recuperación se hace con una migración correctiva hacia adelante, o con un backup verificado y autorizado (ADR-009 §2.5).
- Sus comentarios internos («local o staging») **no prevalecen** sobre la ADR-009 (`AGENTS.md` §1.1).
- **No editar estos scripts** sin una tarea autorizada: cualquier cambio altera el hash auditado y obliga a una auditoría nueva. Este README fija el estado con SHA-256.

## Scripts alcanzados

| Script | Revierte | SHA-256 (04/11/2026) |
|---|---|---|
| `20261029233000_lector_perfiles_rpc.rollback.sql` | D-2 | `c7642b9357bed59078cd609e31a64cc2434f2b5ac44e4d03f951192d9d5ffc56` |
| `20261030120000_jornadas_esquema.rollback.sql` | D-1 | `213ddbeb2181694a6bbb7207daab0e4df87d09d9eaa6c60ac80c149f77f614a3` |
| `20261031120000_rpc_abrir_jornada.rollback.sql` | T1 | `f23f09107211e8cc8bd6841c2f6d6770bc667e1a2be44b34f91b68328cc12092` |
| `20261101120000_rpc_reasignar_vendedor.rollback.sql` | T2 | `b79fb81d64ea6f3328f0ad1bc87192732e1cbd3921e890fed4a05daff4910fad` |

## Defectos conocidos (abiertos)

Ninguno está corregido. Se conservan como hallazgos técnicos abiertos de la auditoría; no se declaran aceptados.

| ID | Severidad | Defecto |
|---|---|---|
| **T1-1** | Alto | El rollback de D-2 elimina la vista `privado.perfiles_empresa_gestion`, el helper y el rol **sin comprobar consumidores**. `abrir_jornada` y `reasignar_vendedor` usan la vista; las referencias PL/pgSQL no quedan en `pg_depend`, así que el `DROP VIEW` prospera y las RPC quedan rotas. |
| **T1-2** | Medio | El barrido de funciones del rollback de D-1 sólo mira `public` y `privado`; una función de otro esquema que use `public.jornadas` sobrevive y queda rota. La corrección `476a84f` **no** está integrada. |
| **T1-3** | Informativo | Los manifiestos de los rollbacks de T1 y T2 derivaron: no forman una cadena ejecutable del HEAD; abortan fail-closed por diseño. |
| **M-4** | Alto (proceso) | Una función creada o reemplazada en otra sesión entre el barrido y el `COMMIT` pasa el control y queda rota. No hay `LOCK` de funciones. |
| **N-1** | Bajo | Un `GRANT`/`REVOKE` concurrente posterior al precheck de ACL se pierde sin aviso. |
| **B-1** | — | Las referencias dinámicas construidas en ejecución no son detectables. |
| **H-14** | Alto (proceso) | Cambios concurrentes de roles, membresías, privilegios y ownership no quedan cubiertos por las verificaciones. |
| **A5** | Medio | En la versión `e225fff` el barrido no cubría otros esquemas (origen de T1-2); corregido sólo en `476a84f`, no integrado. |

## Orden de dependencia

- **D-2 no puede revertirse si D-1 está aplicada** (T1-1): rompe `abrir_jornada` y `reasignar_vendedor`.
- **D-1 exige que D-2 esté presente y sin cambios**: su rollback verifica los objetos y definiciones de D-2 y aborta si no coinciden.
- **D-1 aborta** si detecta datos de jornadas, funciones de jornadas, triggers, vistas o índices posteriores. Es fail-closed.
- Ninguno de los cuatro scripts es idempotente.

## Uso permitido

**Hoy: ninguno.** Si en el futuro una decisión humana autoriza un rollback (F-9 de ADR-009), sólo podrá ejecutarse en una base local descartable, con autorización expresa, `ON_ERROR_STOP=1`, como `postgres`, sin DDL concurrente y con registro en `docs/progress-log.md`. Bajo esas condiciones, los defectos de la tabla vuelven a bloquear hasta que ADR-008 esté aprobada e implementada.
