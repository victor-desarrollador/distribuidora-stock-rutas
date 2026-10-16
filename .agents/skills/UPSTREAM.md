# Procedencia de las Agent Skills

Estas skills se incorporan de forma selectiva y reproducible para uso compartido por Claude Code, Codex y OpenCode.

## Fuente fijada

- Repositorio upstream: <https://github.com/addyosmani/agent-skills>
- Versión: `0.6.13`
- Tag: `0.6.13`
- Commit inmutable: `aeac41d4d005999432bb7312f7ff06383a91d59d`
- Método: descarga selectiva de cada `SKILL.md` desde el commit inmutable; no se instaló el paquete completo.

## Archivos y SHA-256

| Skill | Archivo | SHA-256 |
|---|---|---|
| `source-driven-development` | `source-driven-development/SKILL.md` | `c59faf851377f0eeda45306398d16eb96d77ab1c2fd3e1a7fb58e9a0af33c1e9` |
| `api-and-interface-design` | `api-and-interface-design/SKILL.md` | `e83d34f52ff12dd8a7c5134cd7e8140ea4541ec65e204f8a1e4cd366e30c4192` |

## Excepción de estabilidad

La versión `0.6.13` tenía menos de las dos semanas preferidas por `AGENTS.md` al momento de la instalación. El usuario aprobó expresamente esta excepción limitada porque corrige el ejemplo JavaScript inválido de una versión anterior (`throw;` → `throw e;`).

## Integración por agente

- Codex y OpenCode: descubrimiento desde `.agents/skills/`.
- Claude Code: enlaces simbólicos relativos en `.claude/skills/` hacia las copias canónicas de `.agents/skills/`.
- Los enlaces simbólicos pueden no funcionar correctamente en entornos sin soporte de symlinks, incluidos ciertos checkouts de Windows; en esos entornos se debe verificar el descubrimiento antes de usar las skills.
- Las instalaciones globales existentes no se modifican y pueden divergir en el futuro. Para este proyecto, las copias fijadas en `.agents/skills/` tienen precedencia sobre cualquier copia global divergente.

## Dependencias y acceso externo

- Las menciones a `security-and-hardening` y `deprecation-and-migration` son referencias cruzadas opcionales: no son dependencias de ejecución y no se instalaron como parte de esta tarea.
- `source-driven-development` puede consultar documentación oficial externa y, por lo tanto, puede requerir acceso a red. Esa consulta no amplía el alcance autorizado ni reemplaza las reglas del repositorio.

Las instrucciones de estas skills están subordinadas a `BLUEPRINT.md`, a las ADR aprobadas y a las reglas del repositorio. No autorizan cambios de alcance, migraciones, operaciones de producción, commits ni despliegues.
