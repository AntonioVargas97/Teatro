# Reglas Globales y Orquestación del Proyecto — Teatro de la Ciudad de Coatzacoalcos

Este archivo define las reglas siempre activas para todo el repositorio y coordina el uso de `.agents/rules/` y `.agents/skills/`.

## 1. Fuentes de Verdad (Máxima Prioridad)

1. `docs/alcance.md` — Reglas de negocio, plazos, límites, roles y exclusiones de alcance.
2. `docs/arquitectura.md` — Capas, módulos transversales (`agenda`, `configuracion`, `auditoria`), concurrencia, RBAC y ADRs.
3. `docs/stack-tecnologico.md` — Versiones aprobadas y librerías explícitamente excluidas.
4. `docs/maquinas-de-estado.md` y `docs/maquinas-de-estado/*.puml` — Estados, guardas y transiciones oficiales.

* **Sincronización obligatoria:** Ninguna implementación, prueba o diagrama puede contradecir estas fuentes. Si cambia una regla de negocio o arquitectura, deben actualizarse primero (o en el mismo cambio) las fuentes de verdad y las *skills* impactadas.

## 2. Orquestación de Skills y Reglas

Consulta y aplica la guía correspondiente según el área de trabajo (ver detalle en `.agents/skills/AGENT.md`):

* **Dominio y reglas de negocio:** `teatro-reglas-negocio` (plazos `> 30d` / `D-21`, `48h`, `72h`, `<= 10` boletos, secciones del evento: conservación, sección única, agrupación o subdivisión `<= 6`, fases de venta consecutivas, `>= $100.00 MXN`, exclusiones).
* **Backend (`backend/`):** `django-teatro-backend` (API REST `/api/v1/` sin Django Admin, `services.py`, orden de candados `Usuario -> OrdenCompra -> DisponibilidadButaca -> Boleto`, `nowait=True`/`skip_locked=True`, `import-linter`, `StripeAdapter`).
* **Frontend (`frontend/`):** `react-teatro-frontend` (SPAs `/` y `/gestion/`, cookies `HttpOnly` + CSRF, *polling* del mapa `1,728` butacas, `Stripe Elements`, escáner QR) y `frontend-design` (**solo estética visual**, sin alterar textos legales/QR obligatorios ni legibilidad operativa desde `360px`).
* **Pruebas y CI (`.github/workflows/pruebas.yml`):** `playwright-vitest-teatro` (`TestCase`, `TransactionTestCase` para concurrencia, `ruff`, `import-linter`, `tsc --noEmit`, `ESLint + Prettier`, `Vitest`, `Playwright`).
* **Seguridad:** `security-audit` como guía continua (RBAC, anti-IDOR/BOLA, firmas Stripe y QR); ejecutar auditoría completa solo cuando se solicite explícitamente.
* **Control de versiones:** `git-workflow` (Conventional Commits, commits atómicos). Mientras siga la etapa inicial sobre `main`, preguntar antes de commitear directo en `main` salvo indicación explícita.
* **Diagramas de clases UML:** `plantuml-diagrama-clases` (PlantUML en `docs/diagramas-uml/`, UML 2.5.1, relaciones sin cruces verificadas con `check_crossings.py`, solo con entidades y estados definidos en las fuentes de verdad).
* **Auditorías:** Regla condicional `.agents/rules/auditorias-docs.md` (reportes inmutables *append-only* en `docs/reportes/<tipo-auditoria>/auditoria-[nombreDescriptivo]-[fecha].md`).

## 3. Reglas Operativas Siempre Activas

* **Esquema y migraciones (`ADR-02`):** Django ORM y sus migraciones son la única fuente de verdad de la base de datos. Prohibido editar migraciones ya integradas en `main` o usar `database/*.sql` para alterar el esquema vivo.
* **Secretos y datos personales (`LFPDPPP`):** Prohibido commitear archivos `.env`, llaves privadas/reales de Stripe, `QR_HMAC_SECRET`, credenciales SMTP o respaldos con datos personales; usar solo `backend/.env.example` con *placeholders*.
* **Tiempo y moneda:** Evaluar reglas temporales en `America/Mexico_City` persistiendo *timestamps* en UTC (`TIMESTAMPTZ`), y operar importes en `Decimal(10, 2)` MXN (nunca `float`).
