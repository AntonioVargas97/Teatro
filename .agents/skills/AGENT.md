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
