---
name: django-teatro-backend
description: "Architecture, domain rules, concurrency, security, and testing conventions for the Django + DRF backend of Teatro de la Ciudad de Coatzacoalcos. Use this skill whenever creating, editing, reviewing, or testing any file in backend/ (models, serializers, permissions, views, filters, services, Celery tasks, migrations, management commands, Stripe integration, PDF/QR generation, or Django tests), even if the user does not explicitly mention architecture rules or ADRs."
---

# Django + DRF Backend Guide (Teatro Coatzacoalcos)

Follow these non-negotiable architectural and domain conventions when working in `backend/`. For full specs, consult `docs/arquitectura.md`, `docs/stack-tecnologico.md`, and `docs/maquinas-de-estado.md`.

## 1. Module Layout & Dependency Direction (ADR-01, ADR-07)

The backend is a **modular monolith** under `backend/apps/`:

- **Domain apps:** `usuarios`, `cartelera`, `inventario`, `ventas`, `boletos`, `cotizaciones`
- **Transversal apps:** `agenda` (venue occupancy) and `auditoria` (immutable audit log)

Standard file layout per domain app (`admin.py` is **omitted**):

```text
apps/<modulo>/
├── __init__.py
├── apps.py
├── models.py
├── serializers.py
├── filters.py       # django-filter FilterSet (when endpoint filters exist)
├── permissions.py   # RBAC + anti-IDOR object permissions
├── views.py
├── services.py      # Business logic, state transitions, atomic transactions
├── tasks.py         # Celery tasks (if async/periodic work exists)
├── urls.py
├── migrations/
└── tests/
```

### Strict ADP Rules for `apps/agenda/` (Solución B)
1. **Zero upward/reverse imports:** `apps/agenda/` must **never** import models, serializers, or services from any business module (`cartelera`, `cotizaciones`, `ventas`, etc.). Enforced in CI via `import-linter`.
2. **Single entry point:** External modules (`cartelera`, `cotizaciones`) must never create or mutate `BloqueoAgenda` directly via ORM; always call `AgendaService` in `apps/agenda/services.py` (`verificar_disponibilidad`, `retener_propuestas`, `pre_reservar_bloque`, `confirmar_bloque`, `reprogramar_bloque`, `liberar_bloque`).
3. **Semantic neutrality:** `agenda` stores time intervals `[inicio, fin)` in UTC, block origin (`FUNCION`, `RENTA`, `MANTENIMIENTO`), status (`PROPUESTA_RETENIDA`, `PRE_RESERVADO`, `CONFIRMADO`, `LIBERADO`), and a short label—no pricing, posters, or quote logic.

## 2. Pure REST API, Auth & RBAC (ADR-03, ADR-04, ADR-06)

- **No Django Admin:** `django.contrib.admin` is excluded; never create `admin.py` or `/admin/` routes. All internal operations go through `/api/v1/` backed by `services.py`, `permissions.py`, and `AuditoriaService`.
- **Sessions over Redis (no JWT, no CORS):** Use Django `SessionAuthentication` (`HttpOnly`, `SameSite=Lax`, CSRF `X-CSRFToken`) and `Argon2PasswordHasher`. Never install `djangorestframework-simplejwt` or `django-cors-headers`.
- **Closed RBAC roles (`TextChoices`):** `ADMIN`, `CAJERO`, `VERIFICADOR`, `USUARIO` (plus anonymous read-only `Visitante`).
- **Anti-IDOR / BOLA:** Every object lookup or mutation for `USUARIO` in `cartelera` (tenant poster/pricing), `ventas`, `boletos`, and `cotizaciones` must verify ownership (`recurso.usuario_id == request.user.id`) in `permissions.py`.
- **Filtering & pagination:** Use `django-filter` `FilterSet`, `SearchFilter`, and `OrderingFilter` with `PageNumberPagination` (`PAGE_SIZE = 20`) instead of manual query-param parsing in `views.py`. Return uniform 4xx/5xx JSON (`code`, `message`, `details`).

## 3. Service Layer, State Machines & Audit

- **Never mutate `estado` directly in views, serializers, Celery tasks, or webhooks.** Encapsulate every transition in explicit `services.py` methods wrapped in `@transaction.atomic`.
- **Audit trail:** Log sensitive operations (box office sales, quote approvals/rejections/reschedules/cancellations, `VENCIDO_SIN_PUBLICAR` & late-payment resolutions, technical blocks, courtesies, auto-refunds, contingency exports/reconciliation, config changes, staff accounts) via `AuditoriaService`.
- **Soft delete only:** Never physically delete confirmed `Venta`, `Pago`, `Boleto`, `Cotizacion`, or `BloqueoAgenda` records; transition status instead.
- **Snapshots:** Config changes (`ConfiguracionSistema`, turn rates, extras/infrastructure) and published event tariffs/sub-sections must be snapshotted so existing quotes, orders, and tickets are never retroactively altered.

## 4. Concurrency, Database & Timezones (ADR-02, ADR-05, ADR-08)

- **Django ORM migrations are the single source of truth** (`database/*.sql` is reference-only). Seed official 1,728 seats, catalogs, and demo data via `seed_teatro`, `seed_catalogos`, and `seed_demo`.
- **Row-level pessimistic locking:**
  - Seat reservation / checkout / release (`LocalidadFuncion` / `OrdenCompra`): use `select_for_update()` (or `NOWAIT` + deterministic ordering to prevent deadlocks) and return `409 Conflict` on contention.
  - QR gate scan (`Boleto`): evaluate atomically inside `transaction.atomic()` (`select_for_update()` or conditional `UPDATE ... WHERE estado = 'EMITIDO'`) so concurrent scans yield one `200 OK` and `409 Conflict` for duplicates.
  - Agenda overlap: rely on `AgendaService` transactions + PostgreSQL `ExclusionConstraint` (`btree_gist`) on half-open `[inicio, fin)` ranges where `estado != 'LIBERADO'`.
- **Timezones:** Persist `TIMESTAMPTZ` in **UTC**; evaluate all business deadlines (`30m` web close, `0m` box office close, `10m + 5m` cart, `48h` pre-reserve/alternatives, `72h` late payment, `D-21 23:59:59`, `min(inicio_primer_bloque, max(primera_fecha - 15d, fecha_pago + 3d))`, `[hora_inicio - 2h, hora_fin]` QR window) deterministically in **`America/Mexico_City`** using `zoneinfo` + `tzdata`. Never call external time APIs.
- **Money:** Use `Decimal(10, 2)` (`MXN`, net final prices without extra VAT), never `float`. Enforce commercial floor `>= $100.00 MXN` per sub-section; in `50/50` (`>= 21d`), round advance with `ROUND_HALF_UP` and compute `saldo = total - anticipo`.

## 5. Stripe, Celery & Document Generation

- **Stripe Gateway (`PaymentGateway` / `StripeAdapter`):** Keep Stripe SDK behind an adapter interface so unit tests can mock it and integration tests can hit Stripe Sandbox. Always verify `Stripe-Signature`, enforce idempotency keys, and persist `stripe_event_id` in `stripe_webhook_events` inside `transaction.atomic()` (returning `200 OK` on duplicate `IntegrityError`).
- **Channel rules:** Online ticket sales require a `USUARIO` account, single-function cart, `<= 10` tickets per account/function, and card-only immediate payment (auto `100%` refund if late webhook hits occupied seats). Rental payments allow card or Stripe payment slips (`48h` pre-reserve, blocked within `48h` of `D-21`).
- **Celery Beat:** Schedule periodic checks against persisted DB `TIMESTAMPTZ` columns—never rely on in-memory Celery countdowns.
- **PDF & CSV:** Generate all PDFs (tickets with `QrCodeWidget`, courtesies, quotes, contingency folio lists) in memory with `reportlab` and CSVs with stdlib `csv`.

## 6. Excluded Libraries (Do Not Introduce)

Never add or use: `djangorestframework-simplejwt`, `django-cors-headers`, `django-channels`, `daphne`, `weasyprint`, `pdfkit`, `puppeteer`, `qrcode`, `segno`, `pandas`, `openpyxl`, `pytest`, or `pytest-django`.

## 7. Testing & Verification Workflow

- Write all backend unit, integration, and concurrency tests using **`django.test.TestCase`** and **`TransactionTestCase`**.
- Run checks inside the Docker backend container:
  ```powershell
  docker compose exec -T backend python manage.py check
  docker compose exec -T backend python manage.py test
  docker compose exec -T backend ruff check .
  docker compose exec -T backend lint-imports
  ```
