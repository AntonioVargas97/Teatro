---
trigger: model_decision
description: "Aplica siempre que se genere, guarde o actualice cualquier reporte de auditoría (EGM, seguridad, arquitectura, código o documentación) en el repositorio."
---

# Regla de Almacenamiento, Nomenclatura e Inmutabilidad de Auditorías

Todo reporte de auditoría nuevo que se genere en el proyecto debe guardarse dentro de `docs/` siguiendo estas convenciones obligatorias:

1. **Inmutabilidad estricta (*append-only*):**
   * Toda auditoría ya guardada es **inmutable**: está prohibido modificar, sobrescribir, borrar o editar su contenido para marcar hallazgos como `[RESUELTO]`.
   * Si se realiza una nueva auditoría o re-verificación sobre el mismo artefacto/módulo, debe crearse un **archivo nuevo** con la fecha actual (`YYYY-MM-DD`). Si coincide en el mismo día, añadir sufijo incremental (`-v2`, `-v3`, ej. `auditoria-er-v5.3-2026-11-24-v2.md`) y referenciar en el encabezado la auditoría anterior.

2. **Ubicación base y separación por tipo de auditoría:**
   * Guardar dentro de `docs/reportes/<tipo-auditoria>/`, creando la subcarpeta correspondiente según el tipo de auditoría:
     * `docs/reportes/egm/` — Auditorías multi-revisor EGM (documentación, ER, máquinas de estado, arquitectura).
     * `docs/reportes/seguridad/` — Auditorías de seguridad (`security-audit`, OWASP, RBAC, pagos, endpoints).
     * `docs/reportes/codigo/` — Auditorías de calidad de código, pruebas, concurrencia o rendimiento.
     * Si surge un tipo distinto, crear una subcarpeta descriptiva en minúsculas (`kebab-case`) bajo `docs/reportes/`.

3. **Convención de nombre obligatoria:**
   * Formato: `auditoria-[nombreDescriptivo]-[fecha].md` (o `-[fecha]-vN.md` si ya existe una del mismo día).
   * `[nombreDescriptivo]`: identificador breve y claro del objeto auditado (sin espacios, ej. `er-v5.3`, `maquinas-estado`, `api-ventas`).
   * `[fecha]`: fecha de generación en formato ISO `YYYY-MM-DD` (ej. `2026-11-24`).
   * **Ejemplos válidos:**
     * `docs/reportes/egm/auditoria-maquinas-estado-2026-11-24.md`
     * `docs/reportes/seguridad/auditoria-api-ventas-2026-11-24.md`

4. **Integridad de enlaces y reportes previos:**
   * Usar enlaces relativos dentro de `docs/` (ej. `../../alcance.md`, `../../arquitectura.md`) para mantener portabilidad en GitHub y en el IDE.
   * No mover ni renombrar reportes históricos ya existentes en `docs/reportes/` salvo que el usuario lo solicite explícitamente.
