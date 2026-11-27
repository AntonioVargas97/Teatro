---
name: django-teatro-backend
description: "Architecture, domain rules, concurrency, security, and testing conventions for the Django + DRF backend of Teatro de la Ciudad de Coatzacoalcos. Use this skill whenever creating, editing, reviewing, or testing any file in backend/ (models, serializers, permissions, views, filters, services, Celery tasks, migrations, management commands, Stripe integration, PDF/QR generation, or Django tests), even if the user does not explicitly mention architecture rules or ADRs."
---

# Django + DRF Backend Guide (Teatro Coatzacoalcos)

Follow these non-negotiable architectural and domain conventions when working in `backend/`. For full specs, consult `docs/arquitectura.md`, `docs/stack-tecnologico.md`, and `docs/maquinas-de-estado.md`.

## 1. Module Layout & Dependency Direction (ADR-01, ADR-07)

The backend is a **modular monolith** under `backend/apps/`:

- **Base apps:** `usuarios`, `configuracion` (`ConfiguracionSistema`, turns, extra/infrastructure catalog, `Categoria`), `recinto` (`Sala`, `Seccion`, `Palco`, `Butaca`), `agenda` (venue occupancy), `auditoria` (immutable audit log), and `pagos` (`WebhookStripe`, shared by `ventas` and `cotizaciones`). Base apps do not depend on domain apps.
- **Domain apps in layers (lower to upper):** `cotizaciones` < `cartelera` < `inventario` < `ventas` < `boletos`. An app may import only base apps and domain apps in lower layers. `cartelera` owns `SeccionEvento`, `AsignacionButaca`, `FaseVenta` and `PrecioSeccion`; `inventario` owns `DisponibilidadButaca` and `BloqueoTecnico`; `boletos` owns `Cortesia`.

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

### Strict ADP Rules for Base Apps (`agenda`, `configuracion`, `auditoria`, `recinto`, `pagos`)
1. **Zero upward/reverse imports:** `apps/agenda/`, `apps/configuracion/`, `apps/auditoria/`, `apps/recinto/` and `apps/pagos/` must **never** import models, serializers, or services from any domain module (`cotizaciones`, `cartelera`, `inventario`, `ventas`, `boletos`). Base apps may depend on each other in the direction of the graph (for example, `agenda` depends on `recinto`, and `auditoria` references `usuarios` by foreign key). Enforced in CI via `import-linter` with a `layers` contract.
2. **Single entry point:** External modules (`cartelera`, `cotizaciones`, `ventas`) must never create or mutate `BloqueoAgenda` directly via ORM; always call `AgendaService` in `apps/agenda/services.py` (`verificar_disponibilidad`, `retener_propuestas`, `pre_reservar_bloque`, `confirmar_bloque`, `reprogramar_bloque`, `liberar_bloque`). Read/update system config, turns, and extras via `ConfiguracionService` (`apps/configuracion/`) and apply snapshots in the consuming module.
3. **Semantic neutrality:** `agenda` stores time intervals `[inicio, fin)` in UTC, block origin (`FUNCION`, `RENTA`, `MANTENIMIENTO`), status (`PROPUESTA_RETENIDA`, `PRE_RESERVADO`, `CONFIRMADO`, `LIBERADO`), and a short label—no pricing, posters, or quote logic. `configuracion` holds editable defaults and catalogs without referencing quotes, events, or orders.
4. **Layered domain flows:** flows that go from a lower layer to an upper one use in-process Django signals, never direct imports: `cotizacion_confirmada` and `cotizacion_cancelada` (create or cancel the event), `evento_publicado` and `funcion_agregada` (inventory), and `orden_pagada` (emit tickets).

## 2. Pure REST API, Auth & RBAC (ADR-03, ADR-04, ADR-06)

- **No Django Admin:** `django.contrib.admin` is excluded; never create `admin.py` or `/admin/` routes. All internal operations go through `/api/v1/` backed by `services.py`, `permissions.py`, and `AuditoriaService`.
- **Sessions over Redis (no JWT, no CORS):** Use Django `SessionAuthentication` (`HttpOnly`, `SESSION_COOKIE_SECURE = not DEBUG`, `SameSite=Lax`, CSRF `X-CSRFToken`, `CSRF_TRUSTED_ORIGINS` env-parameterized for local HTTPS/`@vitejs/plugin-basic-ssl`), `PASSWORD_RESET_TIMEOUT = 1800` (30 min), and `Argon2PasswordHasher`. Never install `djangorestframework-simplejwt` or `django-cors-headers`.
- **Bootstrap initial staff & catalogs:** Override `UserManager.create_superuser` so `manage.py createsuperuser` assigns `rol = 'ADMIN'` (never expose `/admin/`). Seed fixed billboard categories, 1,730 seats, and defaults via `seed_teatro` / `seed_catalogos` (`seed_demo` is dev-only).
- **Closed RBAC roles (`TextChoices`):** `ADMIN`, `CAJERO`, `VERIFICADOR`, `USUARIO` (plus anonymous read-only `Visitante`).
- **Anti-IDOR / BOLA:** Every object lookup or mutation for `USUARIO` in `cartelera` (tenant poster/pricing), `ventas`, `boletos`, and `cotizaciones` must verify ownership (`recurso.usuario_id == request.user.id`) in `permissions.py`.
- **Filtering & pagination:** Use `django-filter` `FilterSet`, `SearchFilter`, and `OrderingFilter` with `PageNumberPagination` (`PAGE_SIZE = 20`) instead of manual query-param parsing in `views.py`. Return uniform 4xx/5xx JSON (`code`, `message`, `details`).

## 3. Service Layer, State Machines & Audit

- **Never mutate `estado` directly in views, serializers, Celery tasks, or webhooks.** Encapsulate every transition in explicit `services.py` methods wrapped in `@transaction.atomic`.
- **Audit trail:** Log sensitive operations (box office sales, quote approvals/rejections/reschedules/cancellations, `VENCIDO_SIN_PUBLICAR` & late-payment resolutions, technical blocks, courtesies, auto-refunds, contingency exports/reconciliation, config changes, staff accounts) via `AuditoriaService`.
- **Soft delete only:** Never physically delete confirmed `OrdenCompra`, `PagoOrden`, `PagoArrendamiento`, `Boleto`, `Cotizacion`, or `BloqueoAgenda` records; transition status instead. `CotizacionVersion` and `RegistroAuditoria` are insert-only.
- **Snapshots:** Config changes (`ConfiguracionSistema`, turn rates, extras/infrastructure in `apps/configuracion/`) and published event sections, sale phases, and prices (`SeccionEvento`, `FaseVenta`, `PrecioSeccion`) must be snapshotted so existing quotes, orders, and tickets are never retroactively altered. Quote approval snapshots the approved version (`CotizacionParametros.version_aprobada`) and the agreed attendance (`asistentes_acordados`).

## 4. Concurrency, Database & Timezones (ADR-02, ADR-05, ADR-08)

- **Django ORM migrations are the single source of truth** (`database/*.sql` is reference-only). Seed official 1,730 seats (single room in initial delivery: `Sala` "Teatro de la Ciudad", architected for multi-room expansion), catalogs, and demo data via `seed_teatro`, `seed_catalogos`, and `seed_demo`.
- **Django and PostgreSQL:** Django 5.2 LTS (`Django>=5.2,<5.3`). Every foreign key uses `on_delete=models.PROTECT` (a test walks all models to verify it).
- **Surrogate PKs and composite FKs:** `AsignacionButaca` and `PrecioSeccion` use a surrogate `id` plus a `UniqueConstraint` over their two columns, because Django 5.2 cannot point a `ForeignKey` at a `CompositePrimaryKey`. The 14 composite FKs are declared with `migrations.RunSQL` (with `reverse_sql`) in one `00xx_restricciones_compuestas` migration per module; a test checks them in `pg_constraint`.
- **Database roles:** migrations run as the owner role `teatro_owner`; the application runs as `teatro_app`, which has no `UPDATE` or `DELETE` on `registro_auditoria`.
- **Inventory rows:** `DisponibilidadButaca` stores only the function, the seat, the state and `actualizado_en`. Rows exist only for seats that have a sale section, so there can be fewer than 1,730: use `bulk_create` without `batch_size=1000`. The order, the sale phase applied and the charged price live in `OrdenCompraDetalle` (with `activo`).
- **Global lock hierarchy & pessimistic locking:**
  - Always acquire row locks in strict order **`Usuario` -> `OrdenCompra` -> `DisponibilidadButaca` ordered by `(funcion_id, butaca_id) ASC` -> `OrdenCompraDetalle` -> `Boleto`** (locking only the minimum required scope).
  - Seat reservation / checkout (`OrdenCompra` / `DisponibilidadButaca`): use `select_for_update(nowait=True)` in HTTP requests (`409 Conflict` on contention) and `select_for_update(skip_locked=True)` in Celery Beat cleanup tasks.
  - **Atomic `<= 10` ticket limit:** Lock the `Usuario` row in online flows and sum `(usuario_id, funcion_id)` tickets across `APARTADO + PAGO_EN_PROCESO + PAGADA` (blocking parallel-tab `6 + 6 = 12` bypasses). Also **re-verify `<= 10`** inside the same lock hierarchy before reassigning an `EXPIRADA` order on a late Stripe webhook (trigger automatic 100% refund `REEMBOLSADA_AUTOMATICA` if exceeded).
  - QR gate scan (`Boleto`): lock only `select_for_update(of=('self',), nowait=True)` inside `transaction.atomic()`, checking `usado_en IS NULL` so concurrent scans across doors never serialize on `Funcion` (`200 OK` vs `409 Conflict`).
  - Agenda overlap: rely on `AgendaService` (`nowait=True`) + PostgreSQL `ExclusionConstraint` (`btree_gist`) on half-open `[inicio, fin)` ranges where `estado != 'LIBERADO'`.
- **Naming conventions:** Use Spanish `snake_case` timestamps (`usado_en`, `expira_en`, `gracia_hasta`, `validado_por`, `proximo_recordatorio_en`) and uppercase seat states (`DISPONIBLE`, `APARTADA`, `VENDIDA`, `BLOQUEO_TECNICO`, `CORTESIA`).
- **Timezones & function lifecycle:** Persist `TIMESTAMPTZ` in **UTC** (`inicio_en`, `fin_en` on `Funcion`, advancing `fin_en` +1 day when `hora_fin <= hora_inicio`); evaluate all business deadlines (`30m` web close / `0m` box office blocking `APARTADO -> checkout`, `10m + 5m` cart, `48h` pre-reserve/alternatives, `72h` late payment, `D-21 23:59:59`, `min(inicio_primer_bloque, max(primera_fecha - 15d, fecha_pago + 3d))`, Mon-Fri business-day SLA, `[inicio_en - 2h, fin_en]` QR window) deterministically in **`America/Mexico_City`** using `zoneinfo` + `tzdata`. Never call external time APIs. Materialize the `1,730` `DisponibilidadButaca` rows via `bulk_create` solo para butacas con sección del evento asignada when the Commercial event transitions to `PUBLICADO` (creating initial `Funciones` when lease payment hits `CONFIRMADO`). Recalculate `D-21`/`D-15` on reschedule (requiring `100%` payment first if `< 21d`).
- **Money:** Use `Decimal(10, 2)` (`MXN`, net final prices without extra VAT), never `float`. Enforce commercial floor `>= $100.00 MXN` per event section and sale phase combination (`PrecioSeccion`); in `50/50` (`> 30d`, `D-21` cutoff + `9d` margin), round advance with `ROUND_HALF_UP` and compute `saldo = total - anticipo`.

## 5. Stripe, Celery & Document Generation

- **Stripe Gateway (`PaymentGateway` / `StripeAdapter`):** Keep Stripe SDK behind an adapter interface so unit tests can mock it and integration tests can hit Stripe Sandbox. Always verify `Stripe-Signature`, enforce idempotency keys, and persist `stripe_event_id` as the primary key of `WebhookStripe` (module `pagos`, states `PENDIENTE`, `PROCESADO`, `FALLIDO`) inside `transaction.atomic()` (returning `200 OK` on duplicate `IntegrityError`). The webhook endpoint is `/api/v1/pagos/webhooks/stripe/`.
- **Channel rules:** Online ticket sales require a `USUARIO` account, single-function cart, `<= 10` tickets per account/function, and card-only immediate payment (auto `100%` refund if late webhook hits occupied seats). Rental payments allow card or Stripe payment slips (`48h` pre-reserve, blocked within `48h` of `D-21`).
- **Payment models:** there is no transaction model. `PagoOrden` (`ventas`; methods `TARJETA_STRIPE`, `EFECTIVO`, `TARJETA_TERMINAL`; states `PENDIENTE`, `EXITOSO`, `FALLIDO`, `CANCELADO`) and `ReembolsoOrden` belong to `ventas`. `PagoArrendamiento`, `FichaPago` and `ReembolsoArrendamiento` belong to `cotizaciones`. Each module keeps its own payments.
- **Celery Beat:** Schedule periodic checks against persisted DB `TIMESTAMPTZ` columns—never rely on in-memory Celery countdowns.
- **PDF & CSV:** Generate all PDFs (tickets with `QrCodeWidget`, courtesies, quotes, contingency folio lists) in memory with `reportlab` and CSVs with stdlib `csv`.

## 6. Excluded Libraries (Do Not Introduce)

Never add or use: `djangorestframework-simplejwt`, `django-cors-headers`, `django-channels`, `daphne`, `weasyprint`, `pdfkit`, `puppeteer`, `qrcode`, `segno`, `pandas`, `openpyxl`, `pytest`, or `pytest-django`.

## 7. Testing & Verification Workflow

- Write all backend unit, integration, and concurrency tests using **`django.test.TestCase`** and **`TransactionTestCase`**.
- Tests always run on PostgreSQL: `ExclusionConstraint`, `TSTZRANGE`, composite FKs and partial indexes are not supported by SQLite. Cover the cross-layer FK check and the `layers` contract of `import-linter`.
- Run checks inside the Docker backend container:
  ```powershell
  docker compose exec -T backend python manage.py check
  docker compose exec -T backend python manage.py test
  docker compose exec -T backend ruff check .
  docker compose exec -T backend lint-imports
  ```
