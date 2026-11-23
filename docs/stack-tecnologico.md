# **Stack Tecnológico y Especificación de Dependencias**

Plataforma de boletaje y cotización de renta del Teatro de la Ciudad de Coatzacoalcos

Este documento define las tecnologías base, motores de infraestructura, herramientas operativas y librerías específicas que utilizará el equipo de desarrollo. Todas las elecciones están alineadas con un **monolito modular en tres capas**, un plazo de **cuatro semanas con seis integrantes** y despliegue centralizado en un **servidor único (VPS con Nginx)**.

**Nota sobre versiones:** Las versiones indicadas en este documento definen las ramas compatibles únicas aprobadas para todo el equipo. Las versiones exactas fijadas para compilaciones reproducibles residen exclusivamente en backend/requirements.txt y frontend/package-lock.json.

## **1\. Entorno Base, Infraestructura y Herramientas Operativas**

### **1.1. Motores Base y Servicios de Ejecución**

| Componente | Tecnología y Versión Base | Rol en la Plataforma |
| :---- | :---- | :---- |
| **Lenguaje Backend** | Python 3.12+ | Ejecución de la API REST, lógica de negocio, generación documental y trabajadores asíncronos. |
| **Lenguaje y Entorno Frontend** | TypeScript 5.x \+ Node.js 22 LTS | Tipado estático en la SPA y entorno exclusivo de desarrollo local, pruebas y compilación (*build*) del cliente. **No se ejecuta como servidor en el VPS de producción.** |
| **Base de Datos Relacional** | PostgreSQL 16+ (con extensión btree\_gist) | Persistencia transaccional ACID en UTC, bloqueos SELECT ... FOR UPDATE sobre el inventario de $1,728$ butacas y restricciones ExclusionConstraint sobre TSTZRANGE en la agenda del recinto. |
| **Almacén en Memoria / Broker** | Redis 7.x | Almacenamiento de sesiones de usuario (HttpOnly), *rate limiting* compartido y *broker* de mensajes para Celery. |
| **Servidor Web y Proxy Inverso** | Nginx 1.24+ | Terminación TLS 1.2/1.3, entrega del *build* estático de React (/), entrega de pósters (/media/) y proxy hacia Gunicorn (/api/v1/). |
| **Correo Transaccional (SMTP)** | django.core.mail (SMTP nativo) | Envío asíncrono desde Celery Worker hacia un proveedor SMTP transaccional configurado en .env (confirmación de boletos/QR, recuperación de contraseña, recordatorios de $3d$ / $7d$, pre-reservas de $48h$, reprogramaciones y reembolsos técnicos). |
| **Contenerización** | Docker \+ Docker Compose v2 | Estandarización del entorno local (PostgreSQL, Redis, Django, Celery Worker/Beat y Mailpit) y despliegue reproducible en el VPS. |

### **1.2. Herramientas de Operación, Desarrollo Local y CI/CD**

| Herramienta | Entorno | Responsabilidad Operativa |
| :---- | :---- | :---- |
| **Mailpit** | Desarrollo local (docker-compose.yml) | Servidor SMTP capturador ligero con interfaz web local para inspeccionar correos transaccionales y enlaces de recuperación sin enviar correos reales. |
| **Stripe CLI** | Desarrollo local | Reenvío seguro de eventos *webhook* firmados desde **Stripe Sandbox** hacia http\://localhost:8000/api/v1/ventas/webhooks/stripe/. |
| **Certbot (Let's Encrypt)** | Producción (VPS) | Emisión y renovación automática de certificados HTTPS (TLS 1.2 y TLS 1.3), habilitando cookies Secure y acceso a cámara móvil para escaneo QR. |
| **pg\_dump \+ cron** | Producción (VPS) | Respaldos diarios automatizados y comprimidos de PostgreSQL hacia almacenamiento externo cifrado, cumpliendo el objetivo $RPO\leq 24horas$. |
| **GitHub Actions** | CI/CD (.github/workflows/pruebas.yml) | Ejecución automatizada en cada contribución de Django TestCase, import-linter, ruff, ESLint \+ Prettier, Vitest y pruebas de integración. |

## **2\. Dependencias del Backend (backend/requirements.txt)**

El backend opera como una **API REST pura** (sin django.contrib.admin) respaldada por Django y Django REST Framework.

### **2.1. Core Web, API REST y Filtrado**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| Django | \>=5.1,\<5.3 | Framework principal, ORM, sistema de migraciones (única fuente de verdad del esquema), gestión nativa de sesiones, correo SMTP (django.core.mail) y protección CSRF. |
| djangorestframework | \>=3.15,\<3.17 | Serialización JSON, vistas de API (/api/v1/), permisos RBAC y anti-IDOR (permissions.py), *throttling*, paginación (PageNumberPagination), búsqueda/ordenamiento (SearchFilter, OrderingFilter) y manejo centralizado de excepciones. |
| django-filter | \>=24.3,\<26.0 | Filtrado declarativo y validado por *query params* (FilterSet) complementario a DRF para cartelera (fecha y categoría), cotizaciones, eventos, ventas y auditoría, devolviendo 400 Bad Request uniforme ante parámetros inválidos. |

### **2.2. Persistencia, Sesiones, Caché y Zona Horaria**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| psycopg\[binary\] | \>=3.2,\<3.4 | Adaptador moderno de PostgreSQL para Python con soporte nativo para tipos de rango (TSTZRANGE) y transacciones atómicas de alto rendimiento. |
| django-redis | \>=5.4,\<6.0 | Conecta el motor de sesiones y caché de Django con Redis, permitiendo revocación inmediata de sesiones y *rate limiting* compartido. |
| tzdata | \>=2024.2 | Provee la base oficial de zonas horarias IANA para zoneinfo en entornos Docker minimalistas y Windows locales, garantizando evaluación determinista bajo America/Mexico\_City. |

**Aclaración sobre resolución horaria vía API:** El sistema **no consulta APIs externas de hora**. El VPS sincronizado por NTP y PostgreSQL (persistiendo marcas temporales en **UTC**) actúan como única fuente de verdad; Django evalúa todas las reglas de negocio (cierres de $30min$ / $0min$, corte $D-21$ a las 23:59:59, vencimientos de $10min$ / $48h$ y ventanas QR de $2h$) en el servidor bajo America/Mexico\_City e intercambia fechas en formato **ISO 8601** a través de /api/v1/.

### **2.3. Procesamiento Asíncrono, Tareas Programadas y Correos**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| celery | \>=5.4,\<5.6 | Ejecución asíncrona en segundo plano: procesamiento idempotente de *webhooks* de Stripe, ejecución de reembolsos técnicos automáticos del \$100\\%\$ fuera de ventana, generación de documentos y envío de correos transaccionales vía django.core.mail (SMTP). |
| django-celery-beat | \>=2.7,\<2.9 | Planificador periódico almacenado en base de datos basado en *timestamps* explícitos: liberación de carritos vencidos ($10min$ \+ $5min$ de gracia), expiración de pre-reservas y propuestas de fechas alternativas ($48h$), cierre automático de solicitudes vencidas (EXPIRADA\_POR\_FECHA), recordatorios periódicos ($3d$ y cada $7d$) y alertas de fecha límite de publicación ($15d$). |

### **2.4. Pasarela de Pagos, Medios y Seguridad**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| stripe | \>=11.0,\<13.0 | SDK oficial encapsulado tras StripeAdapter para crear PaymentIntent (tarjeta en boletaje y tarjeta o fichas SPEI/efectivo en arrendamientos) en **Stripe Sandbox**, ejecutar reembolsos técnicos con llaves de idempotencia y verificar criptográficamente la firma Stripe-Signature de los *webhooks*. |
| Pillow | \>=10.4,\<12.0 | Requerido por ImageField de Django para validar formato (JPG/PNG/WebP), dimensiones, integridad y peso ($\leq 5MB$) de los pósters subidos a MEDIA\_ROOT. |
| argon2-cffi | \>=23.1,\<25.0 | Algoritmo recomendado de hashing de contraseñas (Argon2PasswordHasher) para proteger las cuentas de usuarios y personal interno. |
| django-environ | \>=0.11,\<0.13 | Carga tipada de variables de entorno desde .env (credenciales de BD, secretos de Django, REDIS\_URL, parámetros SMTP y llaves de Stripe). |

### **2.5. Generación de Documentos PDF y Exportación**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| reportlab | \>=4.2,\<4.4 | Generación binaria en memoria en Python puro (sin dependencias nativas de sistema operativo en Docker) para toda la salida PDF de la plataforma: **(1)** listado tabular paginado de control de folios del **modo contingencia** desde $24h$ antes de cada función comercial (apps/boletos/), **(2)** **boletos digitales, cortesías y reimpresiones en taquilla** con código QR integrado nativamente vía reportlab.graphics.barcode.qr.QrCodeWidget, y **(3)** **comprobantes de cotización/arrendamiento** con desglose *snapshot* (apps/cotizaciones/). La exportación complementaria en CSV se resuelve directamente con el módulo estándar csv de Python. |

### **2.6. Servidor de Aplicación, Pruebas y Calidad de Código**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| gunicorn | \>=22.0,\<24.0 | Servidor WSGI de producción ejecutado detrás de Nginx para atender las peticiones /api/v1/. |
| import-linter | \>=2.0,\<3.0 | Verificación automatizada en CI/CD que garantiza la dependencia estrictamente unidireccional del módulo transversal apps/agenda/, bloqueando importaciones inversas (Principio ADP). |
| ruff | \>=0.6,\<0.10 | Linter y formateador ultrarrápido para mantener consistencia de estilo en Python entre los seis integrantes del equipo. |

**Motor oficial de pruebas Backend:** Todas las pruebas unitarias, de integración y de concurrencia (verificación de select\_for\_update() y ExclusionConstraint) se ejecutan exclusivamente con **django.test.TestCase y TransactionTestCase** mediante python manage.py test.

## **3\. Dependencias del Frontend (frontend/package.json)**

El frontend es una Single Page Application (SPA) responsiva (operativa desde $360px$ de ancho) escrita en TypeScript, sin dependencias de PWA ni almacenamiento offline. El formateo de fechas en America/Mexico\_City y moneda (MXN) se resuelve directamente con las APIs nativas del navegador **Intl.DateTimeFormat** e **Intl.NumberFormat**.

### **3.1. Core de Interfaz, Enrutamiento, Estilos e Iconografía**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| react / react-dom | ^18.3.1 | Versión LTS única para el equipo, garantizando estabilidad y cero conflictos de peerDependencies al construir el portal público, el mapa interactivo de $1,728$ butacas, la taquilla física, el validador QR y el panel administrativo ligero. |
| react-router-dom | ^6.28.0 | Enrutamiento declarativo en router.tsx e implementación de *Route Guards* (ProtectedRoute.tsx) según el rol del usuario autenticado. |
| tailwindcss (+ postcss, autoprefixer) | ^3.4.x | Sistema de utilidades CSS para maquetación responsiva ágil y uniforme desde $360px$ en el mapa de butacas, configurador de sub-secciones, validador móvil y panel administrativo. |
| lucide-react | ^0.460.0 | Conjunto ligero de iconos SVG con *tree-shaking* nativo, tipado TypeScript e integración directa con utilidades de Tailwind CSS. |

### **3.2. Pagos, Códigos QR y Agenda Visual**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| @stripe/stripe-js y @stripe/react-stripe-js | ^4.x / ^2.x | Renderizado seguro de **Stripe Elements** en el checkout en línea, evitando que los datos de tarjetas toquen los servidores del teatro (cumplimiento PCI-DSS). |
| html5-qrcode | ^2.3.8 | Lectura de códigos QR en tiempo real desde navegadores móviles (Safari iOS y Chrome Android) mediante MediaDevices.getUserMedia() en ValidarAccesoPage.tsx. |
| qrcode.react | ^4.1.0 | Renderizado limpio en SVG/Canvas del código QR firmado dentro de MisBoletosPage.tsx para que el asistente lo presente en puerta desde su teléfono. |
| @fullcalendar/react (+ daygrid, timegrid, interaction) | ^6.1.15 | Vista de calendario maestro en AdminAgendaSolicitudesPage.tsx para visualizar bloqueos (FUNCION, RENTA, MANTENIMIENTO, PROPUESTA\_RETENIDA, PRE\_RESERVADO) y reprogramar solicitudes sin empalmes. |

### **3.3. Empaquetado, Calidad de Código y Pruebas**

| Paquete | Rama Recomendada | Justificación Técnica |
| :---- | :---- | :---- |
| typescript | ^5.6.0 | Verificación estática de tipos en contratos de API (api/client.ts), estado del carrito y props de componentes. |
| vite y @vitejs/plugin-react | ^5.4.x | Servidor de desarrollo con HMR rápido, proxy local de /api/ y /media/ hacia Django bajo el mismo origen y empaquetado estático optimizado para Nginx. |
| @vitejs/plugin-basic-ssl | ^1.1.0 | Habilita HTTPS local temporal para probar la cámara web de escaneo QR desde teléfonos reales en la red local. |
| eslint, prettier (+ eslint-config-prettier, eslint-plugin-react-hooks, typescript-eslint) | ^9.x / ^3.x | Linting estático y formateo automático de TypeScript/React (contraparte de ruff en backend), previniendo errores de dependencias en useEffect (escáner QR y *polling* del mapa) y conflictos de estilo en Git. |
| vitest, @testing-library/react, @testing-library/jest-dom, jsdom | ^2.1.0 / ^16.0.0 | Ejecución rápida de pruebas unitarias y de componentes en src/features/\*\*/\_\_tests\_\_/, integrada nativamente con vite.config.ts. |
| @playwright/test | ^1.48.0 | Pruebas automatizadas extremo a extremo (E2E) en tests/e2e/ sobre navegadores reales para validar compra, taquilla, cotizaciones y escaneo QR. |

## **4\. Exclusiones Intencionales (Principios YAGNI, KISS y Seguridad)**

Para evitar contradicciones arquitectónicas y sobreingeniería durante las cuatro semanas de desarrollo, **queda explícitamente descartada** la instalación de las siguientes categorías de paquetes:

* **Librerías JWT (djangorestframework-simplejwt):** Descartadas porque el sistema despliega frontend y backend bajo el mismo origen en Nginx usando sesiones nativas de Django en Redis (HttpOnly \+ Secure \+ SameSite=Lax \+ CSRF), permitiendo revocación inmediata sin riesgos de XSS en localStorage.  
* **Cabeceras CORS abiertas (django-cors-headers):** Descartada deliberadamente porque Nginx sirve /, /api/v1/ y /media/ bajo un único origen en producción y Vite realiza el proxy local hacia Django en desarrollo, protegiendo el esquema de cookies de sesión y CSRF.  
* **WebSockets y servidores ASGI (django-channels, daphne, socket.io):** Descartados para mantener la simplicidad operativa de Gunicorn (WSGI) en un VPS de $2vCPU$ / $4GB$ RAM. La actualización en tiempo real del mapa de $1,728$ butacas se implementa mediante *polling* HTTP ligero cada $10--15s$ en SeleccionButacasPage.tsx (pausado cuando la pestaña pierde foco y optimizado con React.memo), respaldado por SELECT ... FOR UPDATE en PostgreSQL y respuestas 409 Conflict.  
* **Plugins PWA / Service Workers (vite-plugin-pwa, workbox):** Descartados porque la validación de acceso QR es **100% online en tiempo real** para garantizar entrada única por boleto; las caídas totales de red se resuelven mediante el modo contingencia auditado.  
* **Motores PDF basados en navegador o librerías nativas pesadas (weasyprint, pdfkit, puppeteer), librerías QR extra en Python (qrcode, segno) y librerías de hojas de cálculo (pandas, openpyxl):** Descartados porque reportlab genera todos los PDFs (incluyendo códigos QR vía QrCodeWidget) en Python puro sin añadir dependencias de sistema operativo (Cairo, Pango o Chromium) a Docker, y el CSV se resuelve con la librería estándar csv de Python.  
* **Frameworks alternativos de pruebas en backend (pytest, pytest-django):** Descartados para evitar configuración duplicada frente a django.test.TestCase y TransactionTestCase nativos.  
* **Clientes HTTP pesados (axios), librerías de fechas JS (moment, dayjs) y estado global complejo (redux, @reduxjs/toolkit):** Innecesarios frente a un *wrapper* ligero sobre fetch nativo (src/api/client.ts con credentials: 'include' y X-CSRFToken), las APIs nativas Intl.DateTimeFormat / Intl.NumberFormat y React Context \+ hooks estándar (AuthContext.tsx).

## **5\. Gobernanza de Dependencias en el Equipo**

1. **Aprobación previa:** Antes de añadir cualquier paquete nuevo a requirements.txt o package.json, el integrante debe validar que no duplique una capacidad ya cubierta por el stack (DRY) y que sea indispensable para el alcance de cuatro semanas (YAGNI).  
2. **Sincronización del entorno:** Toda incorporación de dependencia en backend obliga a reconstruir la imagen de Docker (docker compose up \--build) y validar que el pipeline de CI (.github/workflows/pruebas.yml) pase sin errores.  
3. **Versionado bloqueado:** frontend/package-lock.json debe incluirse siempre en el control de versiones y todas las dependencias Python en backend/requirements.txt deben fijarse con versión exacta (\==) antes del primer despliegue en el VPS.  
1. 

