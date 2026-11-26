---
name: ooad-generador-requisitos
description: Skill para la generación estructurada de Requerimientos Funcionales (RF) y Requerimientos No Funcionales (RNF bajo ISO/IEC 25010). Úsala siempre que el usuario solicite redactar requerimientos, especificaciones de sistema (SRS/ERS), atributos de calidad (rendimiento, seguridad, disponibilidad, usabilidad, mantenibilidad, portabilidad), historias de usuario o desglosar un problema o alcance en funcionalidades y criterios medibles.
---

# Generador de Requerimientos Funcionales y No Funcionales

## Objetivo
Transformar descripciones informales, alcances de proyecto o especificaciones arquitectónicas en requerimientos rigurosos y verificables —**Funcionales (`RF`)** y **No Funcionales (`RNF` bajo ISO/IEC 25010)**—, eliminando ambigüedades y manteniendo cada especificación en documentos independientes.

---

## Modos de Operación, Desambiguación y Salida en Disco

### 1. Desambiguación Obligatoria
Si la solicitud del usuario es **ambigua** (por ejemplo: *"genera los requerimientos del sistema"* o *"saca los requisitos de alcance.md"* sin indicar tipo), **NO asumas un modo por defecto ni generes documentos aún**: pregunta primero al usuario cuál de los 3 modos desea ejecutar:
1. **Solo Requerimientos Funcionales (`RF`)**
2. **Solo Requerimientos No Funcionales (`RNF`)**
3. **Especificación Completa (`RF` + `RNF` en dos documentos independientes)**

### 2. Los 3 Modos y Regla de Documentos Independientes
* **Modo 1 — Solo RF:** Genera un único documento independiente para Requerimientos Funcionales (`requisitos-funcionales.md`).
* **Modo 2 — Solo RNF:** Genera un único documento independiente para Requerimientos No Funcionales (`requisitos-no-funcionales.md`).
* **Modo 3 — Especificación Completa:** Genera **obligatoriamente DOS documentos independientes** (uno exclusivo para `RF` y otro exclusivo para `RNF`). **Está prohibido mezclar tablas de `RF` y `RNF` dentro de un mismo archivo o bloque.**

### 3. Regla de Guardado Automático (Excepción Exclusiva de esta Skill)
Como excepción aplicable **únicamente a esta skill**:
* **Guardado automático por defecto:** Salvo que el usuario indique otra ruta explícita o solicite la salida únicamente como texto en el chat, escribe automáticamente los archivos `.md` resultantes en **`./docs/requisitos/`**, creando `./docs/` y `./docs/requisitos/` automáticamente si no existen:
  * Modo 1 → `./docs/requisitos/requisitos-funcionales.md`
  * Modo 2 → `./docs/requisitos/requisitos-no-funcionales.md`
  * Modo 3 → `./docs/requisitos/requisitos-funcionales.md` **y** `./docs/requisitos/requisitos-no-funcionales.md`
* **Modo solo chat (si el usuario pide explícitamente no guardar archivos):** Entrega un único bloque Markdown `.md` en Modos 1 y 2, o **dos bloques Markdown `.md` separados** (encabezando cada uno con el nombre de archivo sugerido) en Modo 3, evitando texto conversacional innecesario fuera de los bloques.

---

## Reglas para Requerimientos Funcionales (`RF`)

### Patrón Estricto y Atomicidad
Todo requerimiento funcional generado DEBE seguir estrictamente esta estructura en la columna `Descripción`:
**Actor / Acción / Objeto de Acción / Datos de entrada / Resultado esperado**

* **Atomicidad:** Un `RF` representa **UNA única acción**. No uses conjunciones (`"y"`, `"además"`) para agrupar múltiples funcionalidades en un mismo requisito; divídelas en filas separadas.
* **Actor:** Usuario autenticado, perfil operativo o sistema que ejecuta la acción.
* **Acción:** Verbo funcional objetivo.
* **Objeto de acción:** Entidad o componente involucrado.
* **Datos de entrada:** Información necesaria para iniciar la funcionalidad.
* **Resultado esperado:** Estado resultante o salida verificable del sistema.
* **Agrupación y secuencia:** Agrupa por módulos en orden de construcción técnico (ej. Configuración Inicial > Autenticación > Catálogos/CRUD Base > Lógica de Negocio > Control/Auditoría/Reportes).

### Plantilla Estricta de Documento `RF`
```markdown
# Especificación de Requerimientos Funcionales - [Nombre del Proyecto]

## Módulo 1: [Nombre del Módulo Base]
| ID | Descripción | Tipo |
| :--- | :--- | :--- |
| RF-01 | [Actor] debe poder [Acción] el [Objeto de Acción], ingresando [Datos de entrada], para [Resultado esperado]. | (Usuario o Sistema) |

## Módulo N: [Nombre del Módulo Siguiente en Orden de Construcción]
| ID | Descripción | Tipo |
| :--- | :--- | :--- |
| RF-N | [Actor] debe poder [Acción] el [Objeto de Acción], ingresando [Datos de entrada], para [Resultado esperado]. | (Usuario o Sistema) |
```

---

## Reglas para Requerimientos No Funcionales (`RNF` — ISO/IEC 25010)

### Patrón Estricto y Criterios de Calidad
* **Atomicidad de RNF:** Cada `RNF` debe expresar **un único atributo de calidad, restricción o límite verificable** sobre un componente o alcance concreto. No fusiones criterios heterogéneos (por ejemplo, latencia de API junto con política de contraseñas) en una misma fila.
* **Cero ambigüedad:** Prohibido usar adjetivos vagos (`"rápido"`, `"seguro"`, `"escalable"`, `"fácil de usar"`, `"robusto"`) sin su **métrica numérica o criterio binario verificable**.
* **Fidelidad documental:** Toda métrica, tecnología o restricción debe derivarse estrictamente de las fuentes del proyecto proporcionadas. Si falta una métrica objetivo en la fuente, señálalo explícitamente antes de asumir valores arbitrarios.
* **Redacción prescriptiva en `Descripción`:** `[El sistema / componente] debe [garantizar / cumplir / responder / soportar / restringir] [criterio objetivo] [bajo condición o alcance].`

### Categorías Estándar Ordenadas (ISO/IEC 25010)
Organiza los `RNF` agrupándolos en las categorías aplicables en este orden:
1. **Categoría 1: Eficiencia de Desempeño** (comportamiento temporal, latencias `p95`, concurrencia/capacidad, utilización de recursos, caché, paginación y límites de carga).
2. **Categoría 2: Confiabilidad, Concurrencia y Contingencia** (disponibilidad, tolerancia a fallos, atomicidad, anti-empalme/anti-sobreventa, idempotencia, integridad referencial/financiera/temporal, recuperación `RPO`/`RTO`).
3. **Categoría 3: Seguridad y Cumplimiento Normativo** (autenticación, sesiones/CSRF, cifrado/hashing, autorización RBAC/anti-IDOR, firmas criptográficas, rate limiting, cabeceras HTTP, protección OWASP y privacidad/LFPDPPP).
4. **Categoría 4: Usabilidad y Accesibilidad** (responsividad desde ancho mínimo, contraste WCAG, señalización no cromática, legibilidad tabular, mensajes operativos e idioma/localización).
5. **Categoría 5: Mantenibilidad y Arquitectura** (modularidad en capas ADP, separación de responsabilidades, calidad estática, cobertura de pruebas/mutación, observabilidad, logs y healthchecks).
6. **Categoría 6: Compatibilidad, Portabilidad y Despliegue** (navegadores/APIs estándar web, contenerización reproducible, dimensionamiento mínimo, cero dependencias excluidas).

### Plantilla Estricta de Documento `RNF`
```markdown
# Especificación de Requerimientos No Funcionales - [Nombre del Proyecto]

## Categoría 1: [Característica ISO/IEC 25010]
| ID | Subcaracterística | Descripción | Métrica / Criterio de Aceptación | Método de Verificación |
| :--- | :--- | :--- | :--- | :--- |
| RNF-01 | [Subcaracterística ISO 25010] | [El sistema/componente] debe [comportamiento o restricción objetiva] [bajo condición]. | [Umbral numérico o criterio binario verificable] | [Técnica, herramienta o inspección] |
```

---

## Ejemplos de Entrada y Salida

**Ejemplo A — Modo 1 (Solo RF):**
* **Entrada:** `"Genera solo requisitos funcionales para registro de usuarios con correo y contraseña en chat"`
* **Salida:**
```markdown
# Especificación de Requerimientos Funcionales - Proyecto

## Módulo 1: Autenticación
| ID | Descripción | Tipo |
| :--- | :--- | :--- |
| RF-01 | El usuario debe poder registrarse en la plataforma, ingresando correo y contraseña, para obtener acceso al sistema. | Usuario |
```

**Ejemplo B — Modo 2 (Solo RNF):**
* **Entrada:** `"Genera los RNF de rendimiento y seguridad para nuestro mapa de asientos en ./docs/requisitos/"`
* **Acción y salida:** Crea `./docs/requisitos/` si no existe y guarda `./docs/requisitos/requisitos-no-funcionales.md` con la tabla ISO/IEC 25010 (`RNF-01`, `RNF-02`, ...).

---

## Casos de Prueba Sugeridos

- **ID:** `prueba-modo-rf-1`
  - **Prompt:** `"Genera solo RF: El administrador debe poder dar de baja a un alumno proporcionando su ID"`
  - **Criterio:** Genera un único documento `RF` con actor `'administrador'`, acción `'dar de baja'`, objeto `'alumno'`, tabla `ID | Descripción | Tipo` y guardado automático en `./docs/requisitos/requisitos-funcionales.md`.
- **ID:** `prueba-modo-rnf-1`
  - **Prompt:** `"Extrae únicamente los RNF de docs/arquitectura.md"`
  - **Criterio:** Pregunta o procede directo en Modo 2 al estar explícito (`solo RNF`), crea `./docs/requisitos/requisitos-no-funcionales.md` bajo ISO/IEC 25010 con métricas verificables (ej. `< 300 ms p95`, `>= 99.5%`, `RPO <= 24 h`) sin mezclar `RF`.
- **ID:** `prueba-modo-completo-1`
  - **Prompt:** `"Genera la especificación completa (RF y RNF) para un módulo de pagos"`
  - **Criterio:** Crea `./docs/requisitos/` si no existe y genera **dos archivos independientes** (`./docs/requisitos/requisitos-funcionales.md` y `./docs/requisitos/requisitos-no-funcionales.md`) sin mezclar tablas.
- **ID:** `prueba-desambiguacion-1`
  - **Prompt:** `"Genera los requisitos de docs/alcance.md"`
  - **Criterio:** Al haber ambigüedad sobre el tipo de requerimientos, pregunta al usuario qué modo desea (Solo RF, Solo RNF o Especificación Completa en 2 documentos) antes de generar archivos.
