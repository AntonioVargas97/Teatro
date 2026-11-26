---
name: react-teatro-frontend
description: "Architecture, API contract, seat-map polling, QR scanner, Stripe Elements, SPA performance, and UI conventions for the React 18 + TypeScript + Vite + Tailwind frontend of Teatro de la Ciudad de Coatzacoalcos. Use this skill whenever creating, editing, or reviewing files in frontend/src/ (pages, components, AuthContext, ProtectedRoute, api/client.ts, vite.config.ts, or Tailwind styles)."
---

# React + TypeScript Frontend Guide (Teatro Coatzacoalcos)

Follow these architectural, performance, and UI conventions when working in `frontend/`. For full specs, consult `docs/arquitectura.md`, `docs/stack-tecnologico.md`, and `docs/alcance.md`.

## 1. Dual-SPA Architecture, Routing & Auth Guards (Same-Origin Nginx)

- **Two separate frontend builds under one origin (`/` and `/gestion/`):** Serve the **Public & Client Portal at `/`** (`cartelera`, seat selection, `OrdenCompra` checkout, `MisBoletos`, quotes/configurator, `USUARIO` auth) and **Internal Operations at `/gestion/`** (`ADMIN` views — including `ContingenciaBoletosPage.tsx` and global sales/audit `AdminVentasAuditoriaPage.tsx` — plus `CAJERO` box office and `VERIFICADOR` mobile QR scanner) so public `/` visitors never download internal staff/admin code while preserving same-origin session cookies + CSRF (`zero CORS/JWT`).
- Keep build-time shared modules (`MapaAsientos.tsx`, `Button.tsx`, `api/client.ts`) DRY across both apps (`frontend/src/shared/` when split from the initial `features/` scaffold), with feature modules (`usuarios`, `admin`, `cartelera`, `inventario`, `ventas`, `boletos`, `cotizaciones`), and Tailwind entry in `styles/global.css`.
- **Client routing (`react-router-dom` v6):** `ProtectedRoute.tsx` in both `/` and `/gestion/` is strictly a UX guard; real RBAC and anti-IDOR authorization live in Django `permissions.py`.
- **Preserve seat selection on login redirect:** If an anonymous `Visitante` selects a seat on the map, redirect to login/register, preserve `funcion_id` and chosen seats in `AuthContext.tsx` (in-memory/session state), and restore them after authentication.
- **Responsive baseline:** Design every view (`ValidarAccesoPage.tsx`, `ConfiguradorTarifas.tsx`, `MapaAsientos.tsx`, `AdminAgendaSolicitudesPage.tsx`) to operate cleanly down to **`360px` width** (iOS Safari and Android Chrome) with Tailwind CSS and `lucide-react` icons.

## 2. API Client, Sessions & Formatting (`src/api/client.ts`)

- **Fetch wrapper only:** Use native `fetch` with `credentials: "include"`, `X-CSRFToken` header on mutating requests, and relative `/api/v1/` paths (proxied by Vite in `vite.config.ts` to Django under the same origin).
- **Uniform error handling:** Parse `{ code, message, details }` from 4xx/5xx responses and handle `401` (unauthenticated), `403` (forbidden), `409 Conflict` (seat taken, schedule clash, closed sale, duplicate QR), and `422` (outside QR time window).
- **Formatting:** Format dates in **`America/Mexico_City`** and currency in **`MXN`** exclusively with native **`Intl.DateTimeFormat`** and **`Intl.NumberFormat`**. Do not use floating-point math for totals/subtotals when avoidable.

## 3. SPA Performance & Re-render Rules

- **Eliminate request waterfalls:** Fetch independent endpoints concurrently with `Promise.all(...)` (e.g., event detail + seat availability + pricing sections).
- **Lazy-load heavy feature routes:** Use `React.lazy` + `Suspense` for heavy optional views (`@fullcalendar/react` in `AdminAgendaSolicitudesPage.tsx`, `html5-qrcode` in `ValidarAccesoPage.tsx`) to keep the public cartelera bundle fast.
- **O(1) lookups on 1,728 seats:** Index seat statuses and selected seats in `Map` / `Set` keyed by `butaca_id` instead of calling `.find()` / `.includes()` inside loops over 1,728 nodes.
- **Keep `React.memo` effective:** Pass primitive props (status string, selected boolean, price) and stable callbacks (`useCallback` + functional `setState(prev => ...)`); avoid inline object/array literals on memoized seat components and never declare components inside other components.
- **Derived state & effects:** Compute derived values (totals, counts, remaining seats, button disabled flags) directly during render—never mirror them in `useEffect` + `useState`. Use lazy `useState(() => ...)` for expensive initial computations and ternary (`cond ? <A /> : null`) instead of `count && <A />` for numeric conditionals.

## 4. Feature-Specific Conventions

- **1,728-Seat Map (`SeleccionButacasPage.tsx`, `MapaAsientos.tsx`, `TaquillaPanel.tsx`):**
  - Synchronize real-time availability via lightweight HTTP **polling every 10–15s** (automatically paused when `document.visibilityState !== "visible"`).
  - Visually distinguish all 5 uppercase seat states (`DISPONIBLE`, `APARTADA`, `VENDIDA`, `BLOQUEO_TECNICO`, `CORTESIA`) plus wheelchair/companion accessible seats.
- **Tariff Configurator (`ConfiguradorTarifas.tsx`):** Support the 4 modalities for Secciones del Evento (standard 6 sections, single section 'General', grouping complete official sections, or subdivision <= 6 per official section in rectangular blocks `(fila_inicio, fila_fin, col_inicio, col_fin)` / complete palco booths), unique non-empty section names per event, consecutive sale phases (`FaseVenta`) with start timestamp, and price matrix by section and phase with net final `>= $100.00 MXN` floor price.
- **Online Checkout & Cart (`CarritoPage.tsx`):** Single-function `OrdenCompra`, visible 10-minute countdown, warning before clearing active hold on function switch, and **Stripe Elements** (`@stripe/react-stripe-js`, `@stripe/stripe-js`) for card payments—never touch raw card data.
- **QR Validation & Tickets (`ValidarAccesoPage.tsx` under `/gestion/`, `MisBoletosPage.tsx` under `/`):**
  - Use **`html5-qrcode`** (`MediaDevices.getUserMedia()`) with a manual short-folio input directly below the camera viewfinder and display exact server messages (*"Acceso permitido"* + sección, fila y asiento, *Abre a las HH:MM*, *La función ya terminó*, *Boleto de la función DD/MM HH:MM*, *Ya ingresó a las HH:MM*, *Boleto no válido*).
  - Test mobile camera locally over HTTPS (`@vitejs/plugin-basic-ssl` or tunnel). Render digital ticket QRs with **`qrcode.react`**.
- **Admin Calendar, Contingency & Sales/Audit (`AdminAgendaSolicitudesPage.tsx`, `ContingenciaBoletosPage.tsx`, `AdminVentasAuditoriaPage.tsx` under `/gestion/`):** Use **`@fullcalendar/react`** (`daygrid`, `timegrid`, `interaction`) differentiating block **origins** (`FUNCION`, `RENTA`, `MANTENIMIENTO`) from **statuses** (`PROPUESTA_RETENIDA`, `PRE_RESERVADO`, `CONFIRMADO`) when rescheduling without overlaps; place Admin-only contingency export/batch reconciliation and global sales + `RegistroAuditoria` views in `/gestion/` `admin/`.
- **Static assets (`public/carteles/`):** Reserve strictly for static build placeholders (e.g. `sin-poster.jpg`); dynamic event posters load from `/media/`.

## 5. Excluded Libraries (Do Not Introduce)

Never add or use: `axios`, `redux`, `@reduxjs/toolkit`, `moment`, `dayjs`, `swr`, `socket.io-client`, `vite-plugin-pwa`, `workbox`, or localStorage JWT auth tokens.

## 6. Verification Commands (from `frontend/`)

```powershell
npm run typecheck     # tsc --noEmit
npm run lint          # eslint .
npm run format:check  # prettier --check .
npm test              # vitest run
```
