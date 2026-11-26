# **Stack Tecnológico y Especificación de Dependencias**

Plataforma de boletaje y cotización de renta del Teatro de la Ciudad de Coatzacoalcos

> **Estado:** versión final (2026-11-26), alineada con `arquitectura.md` y `modelo-datos.md` v6.2. Los cambios respecto a la propuesta anterior se explican en la sección [Registro de cambios de esta versión](#registro-de-cambios-de-esta-versión-2026-11-26).

Este documento define las tecnologías base, motores de infraestructura, herramientas operativas y librerías específicas que utilizará el equipo de desarrollo. Todas las elecciones están alineadas con un **monolito modular en tres capas**, un plazo de **cuatro semanas con seis integrantes** y despliegue centralizado en un **servidor único (PC local en la primera etapa; servidor propio después, con Nginx)**.

**Nota sobre versiones:** Las versiones indicadas en este documento definen las ramas compatibles únicas aprobadas para todo el equipo. Las versiones exactas bloqueadas en frontend residen en `frontend/package-lock.json` (y sus rangos aprobados en `frontend/package.json`), mientras que `backend/requirements.txt` mantiene actualmente los rangos compatibles aprobados y deberá fijarse con versiones exactas (`==`) mediante `pip freeze` antes del primer despliegue en el servidor.

## **1. Entorno Base, Infraestructura y Herramientas Operativas**

### **1.1. Motores Base y Servicios de Ejecución**

| Componente | Tecnología y Versión Base | Rol en la Plataforma |
| :---- | :---- | :---- |
| **Lenguaje Backend** | Python 3.12+ | Ejecución de la API REST, lógica de negocio, generación documental y trabajadores asíncronos. |
| **Lenguaje y Entorno Frontend** | TypeScript 5.x + Node.js 22 LTS | Tipado estático en ambos frontends (`/` Portal Público y `/gestion/` Operación Interna) y entorno exclusivo de desarrollo local, pruebas y compilación (*build*) del cliente. **No se ejecuta como servidor en el servidor de producción.** |
| **Base de Datos Relacional** | PostgreSQL 16+ (con extensión btree_gist) | Persistencia transaccional ACID en UTC, bloqueos `SELECT ... FOR UPDATE` sobre el inventario de 1,728 butacas (`DisponibilidadButaca`) y restricciones `ExclusionConstraint` sobre `TSTZRANGE` (*timestamp with time zone range*) en la agenda del recinto (por sala). Incluye FKs compuestas (14, declaradas con `RunSQL`) e índices únicos parciales. Dos roles de base de datos: `teatro_owner` ejecuta las migraciones y `teatro_app` ejecuta la aplicación, con `REVOKE UPDATE, DELETE` sobre `registro_auditoria` y solo inserciones en `cotizacion_version`. Las pruebas corren siempre sobre PostgreSQL, nunca sobre SQLite. |
| **Almacén en Memoria / Broker** | Redis 7.x | Almacenamiento de sesiones de usuario (`HttpOnly`), caché breve del plano de asientos y caché del plano por evento (configuración congelada al publicar), *rate limiting* y *broker* de mensajes para Celery (`appendonly yes`, `maxmemory-policy noeviction` y bases lógicas separadas `db 0/1/2`). |
| **Servidor Web y Proxy Inverso** | Nginx 1.24+ | Terminación TLS 1.2/1.3, entrega de los dos *builds* estáticos de React bajo el mismo dominio (`/` para Portal Público y `/gestion/` para Operación Interna), entrega de pósters (`/media/`) y proxy hacia Gunicorn (`/api/v1/`). |
| **Correo Transaccional (SMTP)** | django.core.mail (SMTP nativo) | Envío asíncrono desde Celery Worker hacia un proveedor SMTP transaccional configurado en .env (confirmación de boletos/QR, recuperación de contraseña, recordatorios de 3 d / 7 d, pre-reservas de 48 h, reprogramaciones y reembolsos técnicos). |
| **Contenerización** | Docker + Docker Compose v2 | Estandarización del entorno local (PostgreSQL, Redis, Django, Celery Worker/Beat y Mailpit) y despliegue reproducible en el servidor. Incluye un perfil de producción local con Nginx + Gunicorn en la PC del proyecto (Docker Desktop + WSL2 en Windows). |

### **1.2. Herramientas de Operación, Desarrollo Local y CI/CD**

| Herramienta | Entorno | Responsabilidad Operativa |
| :---- | :---- | :---- |
| **Mailpit** | Desarrollo local (docker-compose.yml) | Servidor SMTP capturador ligero con interfaz web local para inspeccionar correos transaccionales y enlaces de recuperación sin enviar correos reales. La imagen se fija a una versión concreta (no `latest`). |
| **Stripe CLI** | Desarrollo local | Reenvío seguro de eventos *webhook* firmados desde **Stripe Sandbox** hacia http://localhost:8000/api/v1/pagos/webhooks/stripe/ (despacho por `metadata.modulo` hacia ventas y cotizaciones). |
| **Certbot (Let's Encrypt)** | Producción (servidor propio) | Emisión y renovación automática de certificados HTTPS (TLS 1.2 y TLS 1.3), habilitando cookies Secure y acceso a cámara móvil para escaneo QR. |
| **pg_dump + cron** | Producción (servidor propio) | Respaldos diarios automatizados y comprimidos de PostgreSQL hacia almacenamiento externo cifrado, cumpliendo el objetivo RPO (*Recovery Point Objective*) ≤ 24horas y RTO (*Recovery Time Objective*) ≤ 2horas. |
| **GitHub Actions** | CI/CD (.github/workflows/pruebas.yml) | Ejecución automatizada en cada contribución de Django TestCase, import-linter, ruff, ESLint + Prettier, Vitest y pruebas de integración. |
| **k6** | QA / Pre-release (CLI externo o contenedor) | Ejecución externa de pruebas de carga y rendimiento contra el perfil Docker local para validar `p95 < 300 ms` (`150–250` usuarios concurrentes) y `< 200 ms` en validación QR (`RNF-01`–`RNF-03`), sin añadir dependencias a `requirements.txt` ni `package.json`. |

## **2. Dependencias del Backend (backend/requirements.txt)**

El backend opera como una **API REST pura** (sin django.contrib.admin) respaldada por Django y Django REST Framework.

### **2.1. Core Web, API REST y Filtrado**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| Django | `>=5.2,<5.3` | Framework principal, ORM, sistema de migraciones (única fuente de verdad del esquema), gestión nativa de sesiones, correo SMTP (django.core.mail) y protección CSRF. Se usa la versión 5.2 LTS (soporte hasta abril de 2028), con la misma versión mayor para todo el equipo. Se apoya en `ExclusionConstraint`, `UniqueConstraint(condition=…)` y `select_for_update(nowait=True, skip_locked=True)`. No se usa `CompositePrimaryKey`: un `ForeignKey` no puede apuntar a un modelo con PK compuesta y DRF no la maneja bien; se usan PK sustitutas (`id`) con `UNIQUE` y FKs compuestas declaradas con `RunSQL`. |
| djangorestframework | `>=3.15,<3.17` | Serialización JSON, vistas de API (/api/v1/), permisos RBAC y anti-IDOR (permissions.py), *throttling*, paginación (PageNumberPagination), búsqueda/ordenamiento (SearchFilter, OrderingFilter) y manejo centralizado de excepciones. |
| django-filter | `>=24.3,<26.0` | Filtrado declarativo y validado por *query params* (FilterSet) complementario a DRF para cartelera (fecha y categoría), cotizaciones, eventos, ventas y auditoría, devolviendo 400 Bad Request uniforme ante parámetros inválidos. |

### **2.2. Persistencia, Sesiones, Caché y Zona Horaria**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| psycopg[binary] | `>=3.2,<3.4` | Adaptador moderno de PostgreSQL para Python con soporte nativo para tipos de rango (TSTZRANGE) y transacciones atómicas de alto rendimiento. |
| django-redis | `>=5.4,<6.0` | Conecta el motor de sesiones y caché de Django con Redis, permitiendo revocación inmediata de sesiones y *rate limiting* compartido. |
| tzdata | `>=2024.2` | Provee la base oficial de zonas horarias IANA para zoneinfo en entornos Docker minimalistas y Windows locales, garantizando evaluación determinista bajo America/Mexico_City. |

**Aclaración sobre resolución horaria vía API:** El sistema **no consulta APIs externas de hora**. El servidor sincronizado por NTP y PostgreSQL (persistiendo marcas temporales en **UTC**) actúan como única fuente de verdad; Django evalúa todas las reglas de negocio (cierres de 30 min / 0 min, corte `D-21` a las 23:59:59, vencimientos de 10 min / 48 h y ventanas QR de 2 h) en el servidor bajo America/Mexico_City e intercambia fechas en formato **ISO 8601** a través de /api/v1/.

### **2.3. Procesamiento Asíncrono, Tareas Programadas y Correos**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| celery | `>=5.4,<5.6` | Ejecución asíncrona en segundo plano: procesamiento idempotente de *webhooks* de Stripe, ejecución de reembolsos técnicos automáticos del 100% fuera de ventana, generación de documentos y envío de correos transaccionales vía django.core.mail (SMTP). |
| django-celery-beat | `>=2.7,<2.9` | Planificador periódico almacenado en base de datos basado en *timestamps* explícitos: liberación de carritos vencidos (10 min + 5 min de gracia), expiración de pre-reservas y propuestas de fechas alternativas (48 h), cierre automático de solicitudes vencidas (EXPIRADA_POR_FECHA), recordatorios periódicos (3 d y cada 7 d) y alertas de fecha límite de publicación (15 d). |

### **2.4. Pasarela de Pagos, Medios y Seguridad**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| stripe | `>=11.0,<13.0` | SDK oficial encapsulado tras `StripeAdapter` (módulo base `pagos`) para crear PaymentIntent (tarjeta en boletaje y tarjeta o fichas SPEI/efectivo en arrendamientos, con `metadata.modulo` y llaves de idempotencia), verificar criptográficamente `Stripe-Signature` de los *webhooks*, ejecutar reembolsos técnicos automáticos vía API en pagos con **tarjeta** y registrar seguimiento `REEMBOLSO_BANCARIO_PENDIENTE` cuando una ficha SPEI/efectivo requiera devolución bancaria externa. |
| Pillow | `>=10.4,<12.0` | Requerido por ImageField de Django para validar formato (JPG/PNG/WebP), `Image.MAX_IMAGE_PIXELS`, peso (≤ 5 MB) y re-codificar pósters eliminando metadatos EXIF antes de guardar en `MEDIA_ROOT`. |
| argon2-cffi | `>=23.1,<25.0` | Algoritmo recomendado de hashing de contraseñas (Argon2PasswordHasher) para proteger las cuentas de usuarios y personal interno. |
| django-environ | `>=0.11,<0.13` | Carga tipada de variables de entorno desde `.env` (BD, secretos de Django, `QR_HMAC_SECRET`, `CSRF_TRUSTED_ORIGINS`, `REDIS_URL`, SMTP y llaves de Stripe). |

### **2.5. Generación de Documentos PDF y Exportación**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| `reportlab` | `>=4.2,<4.4` | Generación binaria en memoria en Python puro (sin dependencias nativas de sistema operativo en Docker) para toda la salida PDF de la plataforma: **(1)** listado tabular paginado de control de folios del **modo contingencia** desde 24 h antes de cada función comercial (`apps/boletos/`), **(2) boletos digitales, cortesías y reimpresiones en taquilla** con código QR integrado nativamente vía `reportlab.graphics.barcode.qr.QrCodeWidget`, y **(3) comprobantes de cotización/arrendamiento** con desglose *snapshot* (`apps/cotizaciones/`). La exportación complementaria en CSV se resuelve directamente con el módulo estándar `csv` de Python. |

### **2.6. Servidor de Aplicación, Pruebas y Calidad de Código**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| gunicorn | `>=22.0,<24.0` | Servidor WSGI de producción ejecutado detrás de Nginx para atender las peticiones /api/v1/. |
| import-linter | `>=2.0,<3.0` | Verificación automatizada en CI/CD con un contrato `layers` que fija el orden `boletos > ventas > inventario > cartelera > cotizaciones > (usuarios, configuracion, recinto, agenda, auditoria, pagos)`: cada módulo solo depende de los que están a su derecha, y los módulos base no dependen de dominio. Se complementa con una prueba que recorre `apps.get_models()` y revisa que ninguna FK apunte a una capa superior, porque las FKs declaradas por texto escapan al linter. Aplica el Principio ADP (*Acyclic Dependencies Principle*). |
| ruff | `>=0.6,<0.10` | Linter y formateador ultrarrápido para mantener consistencia de estilo en Python entre los seis integrantes del equipo. |

**Motor oficial de pruebas Backend:** Todas las pruebas unitarias, de integración y de concurrencia (verificación de select_for_update() y ExclusionConstraint) se ejecutan exclusivamente con **django.test.TestCase y TransactionTestCase** mediante python manage.py test.

### **2.7. Dependencias opcionales aprobadas**

Se adoptan solo si el equipo decide generar el contrato de la API a partir del código. No son obligatorias para la primera entrega.

| Paquete | Rama Recomendada | Justificación Técnica |
| :- | :- | :- |
| `drf-spectacular` | `>=0.27,<0.29` | Genera el esquema OpenAPI del contrato de `/api/v1/` a partir de los serializadores y vistas de DRF, para documentar la API sin mantenerla a mano. |
| `openapi-typescript` (desarrollo, frontend) | `^7` | Genera los tipos TypeScript de `src/shared/api/client.ts` a partir del esquema OpenAPI, para que el cliente y la API no se desalineen. |

## **3. Dependencias del Frontend (frontend/package.json)**

El frontend se compila en dos aplicaciones *Single Page Application* (SPA) responsivas (operativas desde `360px` de ancho) en TypeScript bajo el mismo dominio Nginx (`/` para el Portal Público y `/gestion/` para Operación Interna), sin dependencias de PWA (*Progressive Web App*) ni almacenamiento offline. El formateo de fechas en `America/Mexico_City` y moneda (`MXN`) se resuelve directamente con las APIs nativas del navegador **Intl.DateTimeFormat** e **Intl.NumberFormat**.

### **3.1. Core de Interfaz, Enrutamiento, Estilos e Iconografía**

| Paquete | Rama en `package.json` | Justificación Técnica |
| :---- | :---- | :---- |
| `react` / `react-dom` | `^18.3.1` / `^18.3.1` | Versión LTS única para el equipo, garantizando estabilidad y cero conflictos de `peerDependencies` al construir el portal público (`/`), el mapa interactivo de 1,728 butacas y la app interna de gestión (`/gestion/`: taquilla física, validador QR y panel administrativo ligero). |
| `@types/react` / `@types/react-dom` | `^18.3.12` / `^18.3.1` | Definiciones oficiales de tipos TypeScript para React 18 y DOM en ambos *frontends*. |
| `react-router-dom` | `^6.28.0` | Enrutamiento declarativo y *Route Guards* (`ProtectedRoute.tsx`) en `/` y `/gestion/` según la ruta base y el rol del usuario autenticado. |
| `tailwindcss` / `postcss` / `autoprefixer` | `^3.4.15` / `^8.4.49` / `^10.4.20` | Sistema de utilidades CSS y posprocesado para maquetación responsiva ágil y uniforme desde `360 px` en el mapa de butacas, configurador de sub-secciones, validador móvil y panel administrativo. |
| `lucide-react` | `^0.460.0` | Conjunto ligero de iconos SVG con *tree-shaking* nativo, tipado TypeScript e integración directa con utilidades de Tailwind CSS. |

### **3.2. Pagos, Códigos QR y Agenda Visual**

| Paquete | Rama en `package.json` | Justificación Técnica |
| :---- | :---- | :---- |
| `@stripe/stripe-js` / `@stripe/react-stripe-js` | `^4.10.0` / `^2.9.0` | Renderizado seguro de **Stripe Elements** en el checkout en línea, evitando que los datos de tarjetas toquen los servidores del teatro (cumplimiento PCI-DSS, estándar de seguridad para datos de tarjetas). |
| `html5-qrcode` | `^2.3.8` | Lectura de códigos QR en tiempo real desde navegadores móviles (Safari iOS y Chrome Android) mediante `MediaDevices.getUserMedia()` en `ValidarAccesoPage.tsx`. |
| `qrcode.react` | `^4.1.0` | Renderizado limpio en SVG/Canvas del código QR firmado dentro de `MisBoletosPage.tsx` para que el asistente lo presente en puerta desde su teléfono. |
| `@fullcalendar/react` (+ `daygrid`, `timegrid`, `interaction`) | `^6.1.15` | Vista de calendario maestro en `AdminAgendaSolicitudesPage.tsx` (bajo `/gestion/`) para visualizar bloques de agenda diferenciando su **origen** (`FUNCION`, `RENTA`, `MANTENIMIENTO`) y su **estado** (`PROPUESTA_RETENIDA`, `PRE_RESERVADO`, `CONFIRMADO`) y reprogramar solicitudes sin empalmes. |

### **3.3. Empaquetado, Calidad de Código y Pruebas**

| Paquete | Rama en `package.json` | Justificación Técnica |
| :---- | :---- | :---- |
| `typescript` | `^5.6.0` | Verificación estática de tipos en contratos de API (`api/client.ts`), estado de `OrdenCompra` y *props* de componentes. |
| `vite` / `@vitejs/plugin-react` | `^5.4.11` / `^4.3.4` | Empaquetador y servidor de desarrollo con HMR rápido, proxy local de `/api/v1/` y `/media/` hacia Django bajo el mismo origen y compilación estática optimizada de `/` y `/gestion/` para Nginx. |
| `@vitejs/plugin-basic-ssl` | `^1.1.0` | Habilita HTTPS local temporal para probar la cámara web de escaneo QR desde teléfonos reales en la red local (combinado con `CSRF_TRUSTED_ORIGINS` en backend local). |
| `eslint` / `prettier` / `eslint-config-prettier` / `eslint-plugin-react-hooks` / `typescript-eslint` | `^9.15.0` / `^3.4.2` / `^9.1.0` / `^5.0.0` / `^8.15.0` | Linting estático y formateo automático de TypeScript/React (contraparte de `ruff` en backend), previniendo errores de dependencias en `useEffect` (escáner QR y *polling* del mapa) y conflictos de estilo en Git. |
| `vitest` / `@testing-library/react` / `@testing-library/jest-dom` / `jsdom` | `^2.1.0` / `^16.0.0` / `^6.6.3` / `^25.0.0` | Ejecución rápida de pruebas unitarias y de componentes en `src/features/**/__tests__/`, integrada nativamente con `vite.config.ts` y entorno DOM simulado `jsdom`. |
| `@playwright/test` | `^1.48.0` | Pruebas automatizadas extremo a extremo (E2E) en `tests/e2e/` sobre navegadores reales para validar compra, taquilla, cotizaciones y escaneo QR. |

## **4. Exclusiones Intencionales (Principios YAGNI, KISS y Seguridad)**

Para evitar contradicciones arquitectónicas y sobreingeniería (*YAGNI — You Aren't Gonna Need It*; *KISS — Keep It Simple, Stupid*) durante las cuatro semanas de desarrollo, **queda explícitamente descartada** la instalación de las siguientes categorías de paquetes:

* **Librerías JWT (djangorestframework-simplejwt):** Descartadas porque el sistema despliega ambos frontends (`/` y `/gestion/`) y el backend (`/api/v1/`) bajo el mismo origen en Nginx usando sesiones nativas de Django en Redis (HttpOnly + Secure + SameSite=Lax + CSRF), permitiendo revocación inmediata sin riesgos de XSS en localStorage.
* **Cabeceras CORS abiertas (django-cors-headers):** Descartada deliberadamente porque Nginx sirve `/`, `/gestion/`, `/api/v1/` y `/media/` bajo un único origen en producción y Vite realiza el proxy local hacia Django en desarrollo, protegiendo el esquema de cookies de sesión y CSRF.
* **WebSockets y servidores ASGI (django-channels, daphne, socket.io):** Descartados para mantener la simplicidad operativa de Gunicorn (WSGI) en un servidor de 2 vCPU / 4 GB RAM. La actualización en tiempo real del mapa de 1,728 butacas se implementa mediante *polling* HTTP ligero cada 10–15 s en SeleccionButacasPage.tsx (pausado cuando la pestaña pierde foco y optimizado con React.memo), respaldado por SELECT ... FOR UPDATE en PostgreSQL y respuestas 409 Conflict.
* **Plugins PWA / Service Workers (vite-plugin-pwa, workbox):** Descartados porque la validación de acceso QR es **100% online en tiempo real** para garantizar entrada única por boleto; las caídas totales de red se resuelven mediante el modo contingencia auditado.
* **Motores PDF basados en navegador o librerías nativas pesadas (weasyprint, pdfkit, puppeteer), librerías QR extra en Python (qrcode, segno) y librerías de hojas de cálculo (pandas, openpyxl):** Descartados porque reportlab genera todos los PDFs (incluyendo códigos QR vía QrCodeWidget) en Python puro sin añadir dependencias de sistema operativo (Cairo, Pango o Chromium) a Docker, y el CSV se resuelve con la librería estándar csv de Python.
* **Frameworks alternativos de pruebas en backend (pytest, pytest-django):** Descartados para evitar configuración duplicada frente a django.test.TestCase y TransactionTestCase nativos.
* **Clientes HTTP pesados (axios), librerías de fechas JS (moment, dayjs) y estado global complejo (redux, @reduxjs/toolkit):** Innecesarios frente a un *wrapper* ligero sobre fetch nativo (src/api/client.ts con credentials: 'include' y X-CSRFToken), las APIs nativas Intl.DateTimeFormat / Intl.NumberFormat y React Context + hooks estándar (AuthContext.tsx).
* **Microservicios, segundas bases de datos y brokers de eventos (Kafka, RabbitMQ como bus de dominio):** Descartados porque el modelo usa FKs compuestas entre módulos y transacciones únicas en una sola base de datos, y los eventos de dominio son señales de Django en proceso (ver ADR-10 y ADR-12 en `arquitectura.md`).
* **Otros frameworks y ORM (FastAPI + SQLAlchemy, NestJS + Prisma):** Evaluados y descartados. SQLAlchemy declara FKs compuestas de forma nativa, pero el costo de cambiar de stack no se compensa en cuatro semanas. Prisma no soporta la restricción `EXCLUDE` que usa la agenda.

## **5. Gobernanza de Dependencias en el Equipo**

1. **Aprobación previa:** Antes de añadir cualquier paquete nuevo a requirements.txt o package.json, el integrante debe validar que no duplique una capacidad ya cubierta por el stack (DRY) y que sea indispensable para el alcance de cuatro semanas (YAGNI).
2. **Sincronización del entorno:** Toda incorporación de dependencia en backend obliga a reconstruir la imagen de Docker (docker compose up --build) y validar que el pipeline de CI (.github/workflows/pruebas.yml) pase sin errores.
3. **Versionado bloqueado:** `frontend/package-lock.json` debe incluirse siempre en el control de versiones y todas las dependencias Python en `backend/requirements.txt` deben fijarse con versión exacta (`==`) mediante `pip freeze` antes del primer despliegue en el servidor.


## **Registro de cambios de esta versión (2026-11-26)**

| Tema | Antes | Ahora | Motivo |
| :---- | :---- | :---- | :---- |
| Django | `>=5.1,<5.3`. | `>=5.2,<5.3` (5.2 LTS, soporte hasta abril de 2028). | Misma versión mayor para todo el equipo, con soporte a largo plazo y las funciones de restricciones que usa el modelo. |
| Claves primarias en tablas puente | Sin decisión explícita sobre PK compuestas ni FKs compuestas. | PK sustitutas (`id`) con `UNIQUE` en las tablas puente; FKs compuestas (14) declaradas con `RunSQL`. No se usa `CompositePrimaryKey`. | Un `ForeignKey` no puede apuntar a un modelo con PK compuesta, y DRF no la maneja bien. `RunSQL` conserva la garantía en la base. |
| Roles de PostgreSQL | Un solo rol de base de datos. | Dos roles: `teatro_owner` ejecuta las migraciones y `teatro_app` ejecuta la aplicación, con `REVOKE UPDATE, DELETE` sobre `registro_auditoria`. | La aplicación no debe poder alterar el esquema ni borrar la auditoría. |
| Perfil de producción local | Solo entorno de desarrollo y despliegue directo en el VPS. | Perfil de Docker Compose de producción con Nginx + Gunicorn en la PC del proyecto (Docker Desktop + WSL2). | Permite ensayar la topología de producción antes de contar con el servidor propio. |
| Servidor único | "Servidor único (VPS con Nginx)". | Servidor único: primera etapa en la PC local y después en un servidor propio, con la misma topología. Certbot, UFW y pg_dump se activan en el servidor propio. | Refleja el plan real del proyecto. |
| Webhook de Stripe | Endpoint `/api/v1/ventas/webhooks/stripe/`; Stripe CLI reenvía a esa ruta. | Endpoint `/api/v1/pagos/webhooks/stripe/` en el módulo base `pagos`; Stripe CLI reenvía a esa ruta. | El webhook sirve a `ventas` y a `cotizaciones`; en un módulo base no crea dependencias entre ellos. |
| Import-linter | Contrato que solo prohíbe imports de módulos transversales hacia dominio. | Contrato `layers` con el orden de capas y una prueba que recorre `apps.get_models()` para revisar FKs entre módulos. | Las FKs declaradas por texto escapan al linter, por eso se necesita la prueba adicional. |
| Mailpit | Imagen sin versión fija. | Imagen fijada a una versión concreta (no `latest`). | Evita cambios inesperados en el entorno local del equipo. |
| Dependencias opcionales | No definidas. | `drf-spectacular` (`>=0.27,<0.29`) y `openapi-typescript` (`^7`), adoptables si el equipo decide generar el contrato de la API. | Permiten documentar la API a partir del código, sin obligar a adoptarlas en la primera entrega. |
| Exclusiones nuevas | Exclusiones de JWT, CORS, WebSockets, PWA y motores PDF pesados. | Se agregan: microservicios, segundas bases de datos y brokers de eventos; otros frameworks y ORM (FastAPI + SQLAlchemy, NestJS + Prisma). | Dejan explícitas las alternativas evaluadas y el motivo de descartarlas. |

No se agregó ni retiró ninguna pieza principal del stack; el modelo v6.2 confirma la elección de PostgreSQL y Django.
