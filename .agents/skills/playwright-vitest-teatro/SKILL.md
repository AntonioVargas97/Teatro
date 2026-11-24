---
name: playwright-vitest-teatro
description: "Testing, linting, concurrency verification, and CI conventions for Teatro de la Ciudad de Coatzacoalcos across backend (Django TestCase, TransactionTestCase, ruff, import-linter) and frontend (Vitest, React Testing Library, Playwright E2E, ESLint, Prettier, TypeScript). Use this skill whenever writing, running, reviewing, or debugging unit, integration, concurrency, or E2E tests, or configuring CI in .github/workflows/pruebas.yml."
---

# Testing & QA Guide (Teatro Coatzacoalcos)

Follow these testing, mocking, concurrency, and CI conventions across `backend/` and `frontend/`. For full specs, consult `docs/arquitectura.md`, `docs/stack-tecnologico.md`, and `docs/maquinas-de-estado.md`.

## 1. Backend Testing (`backend/apps/<modulo>/tests/`)

- **Official test runner:** Always use **`django.test.TestCase`** and **`django.test.TransactionTestCase`** via `python manage.py test`. Never install or use `pytest` or `pytest-django`.
- **Execution in Docker:**
  ```powershell
  docker compose exec -T backend python manage.py test
  docker compose exec -T backend ruff check .
  docker compose exec -T backend lint-imports
  ```

### Unit & Integration Tests (`TestCase`)
- Test business transitions in `services.py` (`<= 6` sub-sections, `>= $100.00 MXN`, single-function `OrdenCompra`, `30m`/`0m` closes blocking `APARTADO -> checkout`, `50/50` vs `100%` at `>30d`/`D-21` and reschedule recalc, Mon-Fri SLA, midnight-crossing functions, `bulk_create` of `1,728` rows on `PUBLICADO`, `$0.00` courtesies, PDF/CSV exports and batch contingency reconciliation, cancellations including `CANCELADO_POR_ARRENDATARIO` with sold tickets, late-payment auto-refunds vs `REEMBOLSO_BANCARIO_PENDIENTE`).
- Test RBAC and anti-IDOR rules in `permissions.py` across all 4 roles (`ADMIN`, `CAJERO`, `VERIFICADOR`, `USUARIO`) and anonymous `Visitante` (`401`/`403` verification on cross-user resources).
- **Stripe & time mocking:** Mock `PaymentGateway` / `StripeAdapter` with `unittest.mock` in unit tests so tests run offline. Test webhook idempotency by replaying the same `stripe_event_id` and verifying `200 OK` without duplicate tickets or refunds. Simulate time progression by patching `django.utils.timezone.now` or using explicit DB `TIMESTAMPTZ` timestamps (do not add external time-mocking dependencies).

### Concurrency Tests (`TransactionTestCase`)
- Always use **`TransactionTestCase`** (never `TestCase`, which wraps each test in an uncommitted outer transaction and masks real row locks across threads).
- Verify pessimistic row locks (`Usuario -> OrdenCompra -> DisponibilidadButaca -> Boleto` with `select_for_update(nowait=True)`) and `ExclusionConstraint` (`btree_gist`) under multi-threaded `threading.Thread` / `ThreadPoolExecutor` contention:
  - Concurrent seat holds on the same seat: exactly 1 succeeds, others get `409 Conflict` (`0%` overselling).
  - Parallel-tab `<= 10` limit check (`6 + 6 = 12` simultaneous apartados for the same `USUARIO` + `Funcion` fails second with `409 Conflict`, and late-webhook reassignment re-verifies `<= 10`).
  - Concurrent QR gate scans on the same ticket (`of=('self',)` only on `Boleto`): exactly 1 gets `200 OK`, others get `409 Conflict`.
  - Concurrent agenda reservations on overlapping intervals: `ExclusionConstraint` rejects overlap (`409 Conflict`).
- Call `connections.close_all()` inside worker threads so PostgreSQL connections clean up properly between runs.

## 2. Frontend Unit & Component Tests (`frontend/src/features/**/__tests__/`)

- **Stack:** **Vitest** (`^2.1.0`) + **React Testing Library** (`@testing-library/react`, `@testing-library/jest-dom`, `jsdom`), configured in `frontend/vite.config.ts`.
- **Placement:** Co-locate component tests inside each feature's `__tests__/` folder (e.g., `src/features/ventas/__tests__/CarritoPage.test.tsx`).
- **Commands (from `frontend/`):**
  ```powershell
  npm test              # vitest run
  npm run typecheck     # tsc --noEmit
  npm run lint          # eslint .
  npm run format:check  # prettier --check .
  ```
- Mock `src/api/client.ts` (`fetch`) to verify session/selection preservation across login redirect, seat-map status rendering, single-function cart warnings, countdown display, and form validation without hitting a live server.

## 3. End-to-End Tests (`frontend/tests/e2e/`)

- **Stack:** **Playwright** (`@playwright/test`, `frontend/playwright.config.ts`).
- **Core E2E specs:** `compra.spec.ts`, `acceso.spec.ts`, `cotizacion.spec.ts`.
- **Command (from `frontend/`):**
  ```powershell
  npm run test:e2e      # playwright test
  ```
- Cover critical user journeys end-to-end:
  1. **Compra (`compra.spec.ts`):** Register/login preserving selected seat, 1,728-seat map selection, single-function cart timer, Stripe Sandbox checkout, and box-office sale by `CAJERO`.
  2. **Acceso (`acceso.spec.ts`):** Ticket PDF/QR emission, online QR validation by `VERIFICADOR` (valid, duplicate, wrong function, out-of-window), manual short-folio fallback, and contingency export/reconciliation.
  3. **Cotización (`cotizacion.spec.ts`):** Multi-day quote request, `ADMIN` review/alternative dates (`PROPUESTA_RETENIDA`), approval (`PRE_RESERVADO`), payment, poster upload, and tariff sub-section configurator.

## 4. CI Pipeline Checks (`.github/workflows/pruebas.yml`)

Every pull request/push must pass:
- **Backend:** `ruff check .`, `lint-imports` (strict unidirectional `apps/agenda/` dependency), and `python manage.py test`.
- **Frontend:** `tsc --noEmit`, `eslint .`, `prettier --check .`, and `vitest run`.
