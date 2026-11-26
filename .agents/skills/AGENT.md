# Coordinación de Skills del Proyecto (Teatro de la Ciudad de Coatzacoalcos)

Este repositorio usa skills complementarias bajo `.agents/skills/`. Cuando dos guías coincidan sobre una misma pantalla, módulo o flujo, aplica este orden de prioridad:

## 1. Jerarquía y Límites entre Skills

1. **Reglas de negocio y arquitectura del proyecto (Máxima prioridad):**
   - `teatro-reglas-negocio`, `django-teatro-backend`, `react-teatro-frontend` y `playwright-vitest-teatro` reflejan las decisiones oficiales de `docs/alcance.md`, `docs/arquitectura.md`, `docs/stack-tecnologico.md` y `docs/maquinas-de-estado.md`.
2. **Límite estricto para `frontend-design`:**
   - `frontend-design` **únicamente define la estética visual** (paleta de colores, tipografía, espaciado, jerarquía visual y estilo de componentes).
   - `frontend-design` **NO puede modificar, reescribir ni ocultar textos obligatorios de negocio** (como los mensajes exactos del escáner QR en `ValidarAccesoPage.tsx`, avisos legales LFPDPPP o etiquetas compuestas `{Sección} - {Nombre}`), **ni sacrificar la claridad, contraste o legibilidad operativa del mapa de `1,728` butacas**, sus `5` estados + asientos accesibles, el carrito, la taquilla o las vistas móviles desde `360px`.
3. **Seguridad (`security-audit`):**
   - En trabajo cotidiano aplica en modo guía (respaldando RBAC, anti-IDOR, cookies `HttpOnly`/CSRF y firmas de Stripe/QR); solo ejecuta el flujo completo de auditoría cuando el usuario lo solicite explícitamente.
4. **Control de versiones (`git-workflow`):**
   - Usa Conventional Commits y commits atómicos. Mientras el repositorio siga en etapa de configuración sobre `main`, **pregunta antes de commitear en `main`** salvo que el usuario ya indique explícitamente la rama destino.
5. **Reportes de auditoría (`.agents/rules/auditorias-docs.md`):**
   - Toda auditoría nueva debe guardarse en `docs/reportes/<tipo-auditoria>/auditoria-[nombreDescriptivo]-[fecha].md` separada por tipo (`egm/`, `seguridad/`, `codigo/`, etc.).

6. **Diagramas UML (`plantuml-diagrama-clases`):**
   - Todo diagrama de clases en PlantUML vive en `docs/diagramas-uml/` y sigue UML 2.5.1 con relaciones sin cruces, verificado con `scripts/check_crossings.py`. Se construye solo con lo definido en las fuentes de verdad (`docs/arquitectura.md`, `docs/alcance.md`, `docs/maquinas-de-estado.md`).
   - Diagramas de robustez (`plantuml-diagrama-robustez`): `docs/diagramas-uml/diagramas-de-robustez/RBNN_*.puml`, reglas ICONIX sustantivo–verbo verificadas con `scripts/check_robustness.py`.
   - Diagramas de secuencia (`plantuml-diagrama-secuencia`): `docs/diagramas-uml/diagramas-de-secuencia/SDNN_*.puml`, UML 2.5.1 con lifelines del diagrama de robustez del mismo `NN`, verificados con `scripts/check_sequence.py`. Orden de trabajo: casos de uso → robustez → secuencia.
7. **Ingeniería de Requisitos (`ooad-generador-requisitos`):**
   - Opera en 3 modos independientes (`Solo RF`, `Solo RNF` bajo ISO/IEC 25010 y `Especificación Completa` generando **dos archivos separados**). Bajo ambigüedad, pregunta siempre el modo antes de generar.
   - Por excepción exclusiva de esa skill, guarda automáticamente los archivos en `./docs/requisitos/` (`requisitos-funcionales.md` y `requisitos-no-funcionales.md`), creando las carpetas si no existen.
