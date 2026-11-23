# **Arquitectura de Software y Estructura del Proyecto**

Plataforma de boletaje y cotización de renta del Teatro de la Ciudad de Coatzacoalcos

Se propone un **monolito modular organizado en tres capas lógicas, con comunicación cliente-servidor mediante una API REST pura desplegada en un servidor único (VPS con Nginx). El frontend utilizará React y TypeScript (estilizado con Tailwind CSS e iconografía lucide-react, incluyendo el portal público, taquilla presencial, validador web móvil online y un panel administrativo ligero), el backend Django con Django REST Framework (sin Django Admin), procesamiento asíncrono y colas de tareas con Celery y Redis, y la persistencia en PostgreSQL.**

Esta organización permite repartir el trabajo de seis integrantes por funcionalidad y completar una primera entrega en cuatro semanas. Los módulos del servidor se desplegarán como una sola aplicación Django (acompañada de sus trabajadores asíncronos de Celery) y compartirán una base de datos bajo la zona horaria oficial **America/Mexico\_City** (almacenando marcas temporales en UTC).

## **Las tres capas**

| Capa | Tecnología | Responsabilidad |
| :---- | :---- | :---- |
| **Presentación** | React 18 \+ TypeScript \+ Tailwind CSS \+ lucide-react | Mostrar cartelera (eventos comerciales y públicos), mapa interactivo de \$1,728\$ butacas con sub-secciones tarifarias (sincronizado vía *polling* REST ligero), registro/login y recuperación de contraseña, carrito por función única, boletos digitales, taquilla presencial, validación web móvil online de QR, cotizador multi-día/panel de seguimiento y el **panel administrativo ligero** (eventos directos/arrendados, agenda maestra, configuración de tarifas/parámetros, cortesías/bloqueos, contingencia y cuentas internas). |
| **Negocio y Procesamiento Asíncrono** | Django \+ Django REST Framework (django-filter) \+ Celery \+ Redis | Exponer la API REST pura (/api/v1/), comprobar permisos RBAC y de propiedad, gestionar sesiones en Redis, aplicar reglas *snapshot* de tarifas y esquemas de cobro, apartar butacas por función única, procesar pagos inmediatos con tarjeta (boletos) y tarjetas/fichas de pago (arrendamientos) en **Stripe Sandbox**, generar PDFs en memoria (reportlab) y CSV (csv), gestionar agenda centralizada con estados de retención/pre-reserva, ejecutar reembolsos técnicos automáticos fuera de ventana y correr tareas periódicas/asíncronas (vencimientos, *webhooks* y notificaciones transaccionales vía SMTP nativo). |
| **Datos** | PostgreSQL (btree\_gist) \+ ORM de Django | Guardar registros y proteger relaciones, unicidad compuesta de sub-secciones, no empalme de agenda (ExclusionConstraint) e integridad contable. Ejecutar transacciones atómicas de venta, acceso QR, ocupación del teatro y bitácora inmutable de auditoría. |

**Nota sobre dependencias y versiones:** El catálogo detallado de librerías, versiones únicas fijadas para el equipo, herramientas operativas y exclusiones tecnológicas se documenta en docs/stack-tecnologico.md (STACK\_TECNOLOGICO.md), mientras que las versiones exactas bloqueadas para compilaciones reproducibles residen en backend/requirements.txt y frontend/package.json (package-lock.json).

# **Vistas Gráficas de la Arquitectura**

## **1\. Diagrama de Contenedores (Vista C4 — Mermaid)**

```
flowchart TB
    subgraph Clientes["Clientes (Navegador Web / Móvil)"]
        WebPublico["Visitante / Usuario estándar\n(Cartelera, Mapa, Stripe, Cotizaciones)"]
        Taquilla["Cajero / Admin\n(Taquilla, Panel Admin y Configuración)"]
        MovilQR["Verificador\n(Navegador Móvil - Escáner QR)"]
    end

    subgraph VPS["Servidor Único (VPS - Puertos 80/443 públicos)"]
        Nginx["Nginx\nProxy Inverso + TLS 1.2/1.3 + Rate Limiting\nSirve / (SPA) y /media/ (Pósters)"]
        Django["Backend API REST\nDjango + DRF (Gunicorn)\n/api/v1/"]
        CeleryW["Celery Worker\n(Webhooks Stripe, Reembolsos,\nCorreos Transaccionales)"]
        CeleryB["Celery Beat\n(Vencimientos: Carritos 10m,\nPre-reservas 48h, Recordatorios)"]
        Redis[("Redis\nSesiones HttpOnly + Broker")]
        PG[("PostgreSQL\nBD Relacional + FOR UPDATE +\nExclusionConstraint")]
        Media[("Disco Persistente\nMEDIA_ROOT /carteles/")]
    end

    Stripe["Stripe Sandbox API\n(PaymentIntents, Fichas Arrendamiento,\nWebhooks y Reembolsos Técnicos)"]

    WebPublico -->|HTTPS| Nginx
    Taquilla -->|HTTPS| Nginx
    MovilQR -->|HTTPS| Nginx

    Nginx -->|Archivos estáticos| Media
    Nginx -->|/api/v1/| Django
    Stripe -->|Webhook HTTPS firmado| Nginx

    Django --> PG
    Django --> Redis
    Django -->|SDK / API| Stripe
    Django -->|Escribe pósters| Media

    CeleryW --> Redis
    CeleryW --> PG
    CeleryW -->|Reembolsos / Consultas| Stripe
    CeleryB --> Redis

```

## **2\. Diagrama de Componentes General (3 Capas — UML 2.5 / PlantUML)**

```
@startuml
skinparam componentStyle uml2
top to bottom direction

package "Capa de Presentación (Frontend - React + TypeScript)" as L1 {
    component "Router y RouteGuards\n(router.tsx / ProtectedRoute)" as RTR
    component "Features Portal Público y Cliente\n(cartelera, inventario, ventas,\nboletos, cotizaciones, usuarios)" as FE_PUB
    component "Features Operación Interna\n(Panel Admin, Configuración,\nTaquilla Física, Validador QR Online)" as FE_INT
    component "Componentes Reutilizables\n(components/)" as FE_UI
    component "Cliente HTTP\n(api/client.ts - Cookies + CSRF)" as FE_API

    RTR --> FE_PUB
    RTR --> FE_INT
    FE_PUB --> FE_UI
    FE_INT --> FE_UI
    FE_PUB --> FE_API
    FE_INT --> FE_API
}

component "Nginx Reverse Proxy\n(VPS - TLS 1.2/1.3, /, /api/v1/, /media/)" as NGX

package "Capa de Negocio (Backend - Monolito Modular Django + DRF)" as L2 {
    component "DRF API Router (/api/v1/)\n+ Auth Sesiones Redis y RBAC (permissions.py)" as DRF

    package "Módulos de Dominio (backend/apps/)" as DOM {
        component "usuarios\n(Auth, Recuperación, Cuentas)" as USR
        component "ventas\n(Carrito Función Única,\nVentasService y Taquilla)" as VTA
        component "cotizaciones\n(CotizacionesService,\nSnapshot y Parcialidades)" as COT
        component "cartelera\n(CarteleraService, Eventos Directos,\nFunciones, Sub-secciones y Config)" as CAR
        component "inventario\n(InventarioService, Bloqueos\ny Cortesías - select_for_update)" as INV
        component "boletos\n(BoletosService, QR por Función\ny Modo Contingencia)" as BOL
    }

    package "Módulos Transversales e Integración" as CORE {
        component "agenda (Solución B)\nAgendaService y BloqueoAgenda\n(Sin imports hacia arriba)" as AGD
        component "auditoria\nAuditoriaService" as AUD
        interface "PaymentGateway" as IPay
        component "StripeAdapter" as PAY
        component "Celery Workers y Beat\n(Vencimientos 10m/48h/15d,\nwebhooks, reembolsos, correos)" as CEL

        PAY .up.|> IPay
    }

    DRF --> USR
    DRF --> VTA
    DRF --> COT
    DRF --> CAR
    DRF --> INV
    DRF --> BOL

    VTA --> INV : reserva / confirma butacas
    VTA --> BOL : emite boletos y QR
    VTA --> IPay : cobro tarjeta / reembolso técnico
    VTA --> AUD : registra taquilla / reembolso
    VTA ..> CEL : enfila tareas post-pago

    COT --> AGD : retiene / pre-reserva / confirma
    COT --> IPay : tarjeta o ficha Stripe
    COT --> AUD : registra aprobación / cancelación
    COT ..> CEL : enfila notificaciones / alertas

    CAR --> AGD : valida / bloquea / reprograma
    CAR --> AUD : registra publicación / config
    INV --> CAR : consulta función y tarifas
    INV --> BOL : emite QR de cortesía ($0)
    INV --> AUD : registra bloqueo / cortesía
    BOL --> CAR : consulta ventana de función
    BOL --> AUD : registra contingencia
}

package "Capa de Datos e Infraestructura" as L3 {
    database "PostgreSQL\nORM Django, ACID,\nselect_for_update(),\nExclusionConstraint" as PG
    database "Redis\nSesiones Django,\nBroker Celery,\nRate Limiting" as RED
    folder "Almacenamiento Local VPS\nMEDIA_ROOT (/media/)" as MED
    component "Stripe Sandbox API y Webhooks\n(Pasarela Externa)" as STR

    FE_API --> NGX : HTTPS JSON
    NGX --> DRF : Proxy WSGI (Gunicorn)
    NGX ..> MED : Sirve pósters estáticos

    USR --> PG
    VTA --> PG
    COT --> PG
    CAR --> PG
    INV --> PG
    BOL --> PG
    AGD --> PG
    AUD --> PG

    CAR --> MED : escribe pósters
    DRF --> RED
    CEL --> RED
    PAY --> STR : HTTPS
    STR ..> NGX : Webhook firmado
}
@enduml

```

## **3\. Diagrama de Secuencia: Compra Concurrente en Línea (Stripe \+ QR — UML 2.5 / PlantUML)**

```
@startuml
actor "Usuario estándar" as U
participant "React SPA" as FE
participant "Django API\n(ventas/services.py)" as API
database "PostgreSQL" as PG
queue "Redis / Celery" as Q
participant "Stripe Sandbox" as ST

U -> FE : Selecciona butacas de una Función
FE -> API : POST /api/v1/ventas/carrito/apartar/ {funcion_id, butacas}
API -> PG : BEGIN + SELECT ... FOR UPDATE (LocalidadFuncion)

alt Butacas disponibles y cierre web vigente (> 30 min antes)
    API -> PG : Cambia estado a "apartado" (10 min desde 1er asiento) + COMMIT
    API --> FE : 200 OK (Carrito de función única con expires_at)
else Butaca no disponible o función cerrada
    API -> PG : ROLLBACK
    API --> FE : 409 Conflict (Asiento no disponible / Venta cerrada)
end

U -> FE : Confirma pago con tarjeta en línea
FE -> API : POST /api/v1/ventas/checkout/
API -> PG : Extiende gracia (+5 min) y marca orden PAGO_EN_PROCESO
API -> ST : Crea PaymentIntent (solo tarjeta, idempotency_key)
ST --> API : client_secret
API --> FE : 200 OK (client_secret)
FE -> ST : Confirma tarjeta (Stripe Elements)

ST -> API : POST /api/v1/ventas/webhooks/stripe/ (Stripe-Signature)
API -> API : Verifica firma HMAC y encola idempotentemente
API -> Q : Encola tarea confirmar_pago_boletos
API --> ST : 200 OK

Q -> PG : Transacción atómica sobre orden y LocalidadFuncion
alt Orden vigente o butacas aún disponibles
    Q -> PG : Venta = PAGADA, Butaca = vendida, emite Boletos (QR firmado)
    Q --> U : Envía correo con comprobante y boletos digitales
else Orden expirada y alguna butaca ya fue ocupada
    Q -> ST : Ejecuta reembolso técnico automático del 100%
    Q -> PG : Venta = REEMBOLSADA_AUTOMATICA + AuditoriaService
    Q --> U : Envía correo notificando reembolso automático
end
@enduml

```

## **4\. Diagrama de Secuencia: Validación 100% Online de QR en Puerta (UML 2.5 / PlantUML)**

```
@startuml
actor "Verificador (Móvil)" as V
participant "ValidarAccesoPage.tsx" as FE
participant "Django API\n(boletos/services.py)" as API
database "PostgreSQL" as PG

V -> FE : Escanea QR con cámara (o ingresa folio manual)
FE -> API : POST /api/v1/boletos/validar/ {token}
API -> PG : BEGIN + SELECT ... FOR UPDATE (Boleto + Función)
API -> API : Valida firma HMAC, vigencia (no invalidado),\ncorrespondencia de función y ventana [hora_inicio - 2h, hora_fin]

alt Boleto válido, dentro de ventana y usado_at IS NULL
    API -> PG : UPDATE Boleto SET usado_at = NOW(), validado_por = V + COMMIT
    API --> FE : 200 OK ("Acceso permitido" + Sub-sección, Fila y Asiento)
else Boleto ya escaneado previamente
    API -> PG : ROLLBACK
    API --> FE : 409 Conflict ("Ya ingresó a las HH:MM")
else Boleto pertenece a otra función
    API -> PG : ROLLBACK
    API --> FE : 409 Conflict ("Boleto de la función DD/MM HH:MM")
else Fuera de ventana horaria (muy pronto / concluida)
    API -> PG : ROLLBACK
    API --> FE : 422 / 409 ("Abre a las HH:MM" / "La función ya terminó")
else Token inválido o boleto cancelado
    API -> PG : ROLLBACK
    API --> FE : 400 / 404 ("Boleto no válido")
end
@enduml
```

# **Modelo de Datos y Persistencia**

La persistencia se realizará en PostgreSQL utilizando **Django ORM y sus migraciones como única fuente de verdad del esquema de base de datos**. Todos los modelos en models.py definen las tablas, relaciones, índices y restricciones del dominio, garantizando compatibilidad total con Django, DRF y la creación automática de bases de datos temporales durante las pruebas (TestCase / TransactionTestCase).

Al prescindir de Django Admin, la carga inicial del aforo oficial (\$1,728\$ butacas en \$6\$ secciones, incluyendo butacas accesibles), los catálogos base (turnos, servicios extra e infraestructura escénica), los parámetros operativos por defecto y los datos de demostración se gestionará mediante **comandos personalizados de Django (manage.py seed\_teatro, manage.py seed\_catalogos, manage.py seed\_demo) y/o *fixtures* JSON (loaddata)**, reutilizables tanto en despliegue como en entornos de pruebas. La carpeta database/ se conservará únicamente como respaldo documental y referencia SQL:

```
database/
├── 01_esquema.sql        Referencia documental DDL exportada del dominio
├── 02_inserts_teatro.sql Respaldo SQL del aforo oficial (1,728 butacas en 6 secciones)
└── 03_inserts_demo.sql   Respaldo SQL de datos de muestra para referencia local

```

### **Responsabilidades de los archivos SQL de referencia (database/)**

| Archivo SQL | Contenido y Propósito |
| :---- | :---- |
| 01\_esquema.sql | Script DDL de referencia documental del esquema del dominio (no reemplaza a las migraciones de Django). |
| 02\_inserts\_teatro.sql | Respaldo SQL del catálogo oficial del aforo (\$1,728\$ butacas distribuidas en \$6\$ secciones), equivalente al comando seed\_teatro. |
| 03\_inserts\_demo.sql | Respaldo SQL de datos de prueba de referencia, equivalente al comando seed\_demo. |

Dado que el modelo relacional detallado se especificará en docs/modelo-datos.md, la arquitectura establece las siguientes **entidades nucleares de dominio** obligatorias, derivadas directamente de docs/alcance.md:

## **1\. Entidades Nucleares**

| Entidad | Descripción |
| :---- | :---- |
| **Usuario / Perfil** | Almacena cuentas registradas, credenciales seguras (Argon2), aceptación obligatoria de Aviso de Privacidad y Términos (LFPDPPP), tokens de recuperación de contraseña y un campo de rol cerrado (TextChoices: ADMIN, CAJERO, VERIFICADOR, USUARIO). No existe un rol separado de organizador: el Usuario estándar ejerce tanto el perfil funcional de Comprador en línea como el de Solicitante de arrendamientos con su misma cuenta. |
| **ConfiguracionSistema y Catálogos Base** | Entidad administrativa (Admin) que almacena los parámetros operativos editables con valores por defecto (apartado de carrito \$10\\text{ min}\$, gracia \$5\\text{ min}\$, cierres web \$30\\text{ min}\$ y taquilla \$0\\text{ min}\$, pre-reserva \$48\\text{ h}\$, propuesta alternativa \$48\\text{ h}\$, revisión extemporánea \$72\\text{ h}\$, fecha límite de publicación \$15\\text{ d}\$, recordatorios cada \$7\\text{ d}\$, corte de saldo \$21\\text{ d}\$ \+ margen \$7\\text{ d}\$ \= umbral efectivo \$28\\text{ d}\$, retención \$50\\%\$, umbral de reprogramación/reembolso \$21\\text{ d}\$ y SLA \$3/5\\text{ días hábiles}\$), además de los turnos oficiales (Matutino, Vespertino, Día Completo con tarifas y horarios) y el catálogo editable de servicios extra e infraestructura escénica. Aplica política *snapshot* para no alterar registros previos. |
| **BloqueoAgenda** | Entidad transversal perteneciente al módulo agenda que centraliza los intervalos de ocupación del inmueble completo (montaje, ensayos, función y desmontaje), clasificándolos por origen operativo (FUNCION, RENTA, MANTENIMIENTO), etiqueta breve y estado (PROPUESTA\_RETENIDA, PRE\_RESERVADO, CONFIRMADO, LIBERADO), sin importar modelos de negocio externos. |
| **Evento y Función** | Clasificados por modalidad (Comercial, Público, Privado) y origen (ARRENDAMIENTO vinculado a Cotización, o DIRECTO creado por Admin sin cotización ni pago de renta). Evento almacena metadatos, póster (ImageField, obligatorio en Comercial y Público), fecha límite de publicación (\$15\\text{ d}\$) y estado de ciclo de vida (PENDIENTE\_PUBLICACION, PUBLICADO, VENCIDO\_SIN\_PUBLICAR, CANCELADO\_POR\_ARRENDATARIO, CANCELADO\_POR\_TEATRO, REPROGRAMADO). Cada Evento agrupa \$1\$ **o más Funciones**, cada una con fecha, hora\_inicio, hora\_fin y su referencia hacia BloqueoAgenda. |
| **Sección y Butaca / Asiento** | Catálogo físico, oficial y fijo de las \$1,728\$ butacas del recinto distribuidas en \$6\$ secciones (Luneta, Platea, Mezzanine, Primer Piso, Segundo Piso y Palcos), con su ubicación, numeración permanente y bandera de accesibilidad (es\_accesible para silla de ruedas y acompañante). |
| **SubseccionTarifaria** | Entidad de configuración tarifaria por Evento comercial que modela las secciones oficiales habilitadas o sus subdivisiones estructuradas (\$\\leq 6\$ por sección oficial: cortes por filas/bloques continuos de columnas en graderías y agrupación por palcos completos en Palcos), con etiqueta secuencial editable por defecto ({Sección} \- Zona {N}), unicidad compuesta ({Sección} \- {Nombre}), tarifa \$\\geq\$ \$100.00 MXN y congelamiento al publicarse el evento. |
| **DisponibilidadButaca / LocalidadFuncion** | Entidad asociativa transaccional (exclusiva de eventos Comerciales) que vincula cada Función con cada Butaca física del catálogo, almacenando la tarifa congelada (*snapshot*) de su sub-sección y su estado en tiempo real (disponible, apartado, vendido, bloqueo\_tecnico, cortesia). |
| **Carrito (Temporal)** | Entidad transitoria asociada al usuario autenticado (Usuario estándar en línea o Cajero en taquilla física), restringida estrictamente a **una sola Función comercial por transacción** (\$1\$ carrito activo por usuario) y sujeta a un temporizador único desde la primera selección (\$10\\text{ min}\$ por defecto \+ \$5\\text{ min}\$ de gracia por pago en proceso). |
| **Venta y Pago** | Registra la transacción comercial de compra de boletos al \$100\\%\$ de liquidación (solo eventos Comerciales), diferenciando canal (linea con tarjeta inmediata en Stripe o taquilla presencial con Efectivo o Tarjeta en terminal bancaria externa), número de orden y estados explícitos (APARTADO, PAGO\_EN\_PROCESO, PAGADA, EXPIRADA, REEMBOLSADA\_AUTOMATICA). En línea exige cuenta de Usuario estándar; en taquilla se vincula al Cajero sin exigir cuenta al comprador. Nunca se borra físicamente. |
| **Cotización** | Almacena las solicitudes de arrendamiento enviadas por un Usuario estándar (Solicitante) con soporte de un día o múltiples días/turnos, conceptos extra e infraestructura seleccionados, subtotal estimado informativo y monto oficial confirmado por Admin (*snapshot*), *snapshot* del esquema de cobro (50/50 si faltan \$\\geq 28\$ días naturales a la primera fecha reservada o 100% si faltan \$\< 28\$ días), propuestas estructuradas de hasta \$3\$ fechas alternativas (PROPUESTA\_RETENIDA por \$48\\text{ h}\$) y referencia hacia BloqueoAgenda. |
| **Pago de Arrendamiento / Reserva** | Entidad financiera derivada de una Cotización aprobada que controla el anticipo (\$50\\%\$) o liquidación total (\$100\\%\$), el saldo restante acreditable hasta las 23:59:59 del día \$D-21\$ (restringiendo emisión de fichas en las últimas \$48\\text{ h}\$ previas al corte) y la resolución de pagos extemporáneos (PAGO\_EXTEMPORANEO\_EN\_REVISION). |
| **Transacción / Pasarela de Pagos (Stripe)** | Registra el detalle técnico y financiero de **Stripe Sandbox**: PaymentIntent con tarjeta en línea para boletaje y arrendamientos, **fichas de pago con línea de captura (transferencia/efectivo) restringidas exclusivamente a arrendamientos**, procesamiento idempotente de *webhooks* firmados y ejecución de **reembolsos técnicos automáticos del** \$100\\%\$ por pagos confirmados fuera de ventana. |
| **Boleto** | Entidad derivada de una venta comercial o de una **emisión de cortesía por Admin** (\$0.00 MXN, sin cuenta de invitado y con beneficiario/motivo opcional) asociada a una LocalidadFuncion. Incluye folio corto de respaldo, límite de \$\\leq 10\$ boletos por cuenta/operación por función (exentas las cortesías), token no secuencial firmado (UUID v4 / HMAC-SHA256) ligado a su Función para validación 100% online en puerta, bandera de invalidación y soporte de exportación PDF/CSV y reconciliación en lote para **modo contingencia**. |
| **RegistroAuditoria** | Bitácora inmutable perteneciente al módulo transversal auditoria que registra acciones administrativas y operativas sensibles (ventas en taquilla, aprobaciones/reprogramaciones/cancelaciones, resoluciones de VENCIDO\_SIN\_PUBLICAR y pagos extemporáneos, bloqueos técnicos y cortesías, reembolsos automáticos, activación/exportación/reconciliación de modo contingencia, cambios en configuración y gestión de cuentas internas). |

## **2\. Reglas de Consistencia, Concurrencia, Integridad y Negocio**

* **Zona Horaria Oficial (America/Mexico\_City) y Resolución Horaria Determinista en Servidor:** El VPS sincronizado por NTP y PostgreSQL (persistiendo todos los *timestamps* en **UTC**) actúan como **única fuente de verdad horaria**, sin consultar APIs externas de hora ni depender del reloj del dispositivo cliente. Django evalúa de forma determinista todas las reglas de negocio (cierres de venta por función a los \$30\\text{ min}\$ / \$0\\text{ min}\$, corte de liquidación a las 23:59:59 del día \$D-21\$, ventanas QR \$\[hora\\\_inicio \- 2\\text{ h}, hora\\\_fin\]\$ y cálculos de días naturales) bajo **America/Mexico\_City** mediante zoneinfo \+ tzdata, intercambiando fechas en formato **ISO 8601** por /api/v1/ para su presentación en frontend mediante Intl.DateTimeFormat.  
* **Sincronización del Mapa de** \$1,728\$ **Butacas bajo WSGI (Sin WebSockets):** Al operar sobre Gunicorn (WSGI) y API REST pura sin WebSockets/ASGI, la actualización visual en tiempo real del plano de asientos en SeleccionButacasPage.tsx y TaquillaPanel.tsx se implementa mediante ***polling*** **HTTP ligero** (cada \$10\\text{--}15\\text{ s}\$ mientras la vista esté activa, pausado automáticamente al perder foco mediante document.visibilityState y optimizado con React.memo sobre cada asiento). La consistencia fuerte ante selecciones simultáneas recae siempre en el candado atómico SELECT ... FOR UPDATE en PostgreSQL, devolviendo 409 Conflict cuando una localidad fue ocupada milisegundos antes.  
* **Compra en Línea con Cuenta Obligatoria vs. Taquilla Física:**  
  * **Canal en línea:** Obliga a iniciar sesión (Usuario estándar); si un Visitante selecciona un asiento en el mapa, el frontend preserva la funcion\_id y localidades elegidas tras autenticarse. El carrito opera sobre **una sola Función** a la vez, con reloj único de \$10\\text{ min}\$ desde el primer asiento y pago exclusivo con tarjeta inmediata vía Stripe.  
  * **Taquilla física:** El Cajero autenticado opera sin exigir cuenta al asistente, compartiendo el mismo bloqueo temporal de \$10\\text{ min}\$ e inventario en tiempo real con la web, y registrando cobros en Efectivo o Tarjeta en terminal externa.  
* **Integridad de Agenda y Prevención de Empalmes (ExclusionConstraint \+ btree\_gist):** Todos los bloqueos del recinto en BloqueoAgenda se representan como intervalos semiabiertos \$\[inicio, fin)\$ en UTC (permitiendo turnos consecutivos exactos, como Matutino seguido de Vespertino, sin falsas colisiones). La no superposición de bloques vigentes se garantiza con doble candado: transacciones atómicas en AgendaService (incluyendo reprogramaciones atómicas que reservan y liberan en una sola operación) respaldadas físicamente por una ExclusionConstraint nativa de PostgreSQL sobre rangos temporales apoyada en btree\_gist para cualquier bloqueo cuyo estado sea distinto de LIBERADO (PROPUESTA\_RETENIDA, PRE\_RESERVADO, CONFIRMADO), traduciendo cualquier choque concurrente a HTTP 409 Conflict.  
* **Integridad Contable y Trazabilidad (*Soft Delete*):** Ningún rol (incluyendo Admin) puede eliminar físicamente registros confirmados de Venta, Pago, Pago de Arrendamiento, Boleto, Cotización ni BloqueoAgenda. Toda cancelación (CANCELADO\_POR\_ARRENDATARIO, CANCELADO\_POR\_TEATRO), invalidación de QR o liberación de agenda se gestiona mediante cambios de estado auditados en RegistroAuditoria.  
* **Procesamiento Asíncrono, Vencimientos por Timestamp e Idempotencia (Redis \+ Celery):**  
  * **Celery Beat** ejecuta tareas periódicas limpias consultando marcas temporales explícitas (expires\_at, grace\_expires\_at, fecha\_limite\_publicacion, proximo\_recordatorio\_at) para liberar carritos vencidos, expirar propuestas/pre-reservas de \$48\\text{ h}\$, cerrar solicitudes cuya fecha estimada ya pasó (EXPIRADA\_POR\_FECHA) y disparar recordatorios (\$3\\text{ d}\$ y cada \$7\\text{ d}\$) y alertas de publicación (\$15\\text{ d}\$).  
  * **Celery Worker** procesa de forma **idempotente** los *webhooks* firmados de Stripe (registrando el stripe\_event\_id), ejecuta **reembolsos técnicos automáticos del** \$100\\%\$ cuando un pago llega fuera de ventana y la localidad/fecha ya fue ocupada, y envía las notificaciones transaccionales por correo electrónico vía django.core.mail (SMTP).  
* **Transacciones Atómicas:** Las operaciones críticas sobre DisponibilidadButaca / LocalidadFuncion (apartado en web/taquilla, confirmación de pago, bloqueos técnicos y cortesías), Carrito, Venta y validación/reconciliación de Boleto utilizan bloqueos a nivel de fila (select\_for\_update()) ordenados determinísticamente en PostgreSQL para evitar sobreventas, interbloqueos (*deadlocks*) y dobles accesos.  
* **Fuente Única de Verdad y Estrategia de Migraciones:** Django es la **única fuente de verdad** del esquema de base de datos mediante makemigrations y migrate, apoyado por los comandos de sembrado seed\_teatro, seed\_catalogos y seed\_demo.

## **3\. Almacenamiento de Imágenes y Pósters de Eventos (VPS / Nginx)**

La carpeta frontend/public/carteles/ se reservará **exclusivamente para activos estáticos empaquetados en el build** (como el logo del teatro o sin-poster.jpg). Los pósters dinámicos de eventos comerciales y públicos (ImageField) se almacenarán de forma persistente directamente en el VPS:

* **Directorio Persistente (MEDIA\_ROOT):** Django guarda las imágenes cargadas en un volumen persistente fuera del código compilado (ej. /var/www/teatro/media/carteles/).  
* **Entrega Directa por Nginx:** Nginx expone directamente /media/ con validación previa en backend de tamaño máximo (\$\\leq 5\\text{ MB}\$) y formato (JPG/PNG/WebP).

# **Módulos, Control de Acceso (RBAC) y Comunicación (API REST)**

Los módulos se organizarán en **seis módulos de dominio** orientados a las funciones del teatro y **dos módulos transversales internos** (agenda y auditoria) que evitan dependencias circulares y duplicación de lógica. Cada aplicación Django mantendrá sus modelos, servicios, filtros declarativos, pruebas y, cuando exponga endpoints, sus permisos (permissions.py) y rutas.

| Módulo | Tipo | Responsabilidad |
| :---- | :---- | :---- |
| usuarios | Dominio | Registro (con aceptación LFPDPPP), autenticación mediante sesiones en Redis, recuperación de contraseña por correo SMTP, cierre de sesión/revocación, gestión de perfil propio y CRUD de cuentas internas (ADMIN, CAJERO, VERIFICADOR, USUARIO). |
| cartelera | Dominio | Categorías, eventos (Comercial, Público, Privado; origen arrendamiento o Evento Directo), funciones (fecha, hora\_inicio, hora\_fin), pósters, configurador de sub-secciones tarifarias (\$\\leq 6\$ por sección, \$\\geq\$ \$100.00 MXN, congelamiento al publicar), gestión de fecha límite de publicación (VENCIDO\_SIN\_PUBLICAR), cancelaciones/reprogramaciones y **Configuración Administrativa** (ConfiguracionSistema, turnos y catálogo de extras). |
| inventario | Dominio | Plano fijo de \$1,728\$ butacas (incluyendo accesibles), consulta ligera para *polling* de disponibilidad en tiempo real por Función (DisponibilidadButaca), bloqueos técnicos sin QR y emisión de cortesías (\$0.00 MXN con QR, sin cuenta de invitado). |
| ventas | Dominio | Carrito temporal por **función única** (\$10\\text{ min}\$ \+ \$5\\text{ min}\$ gracia), apartado compartido con taquilla física, cierres independientes por función (\$30\\text{ min}\$ web / \$0\\text{ min}\$ taquilla), cobros inmediatos con tarjeta en **Stripe Sandbox**, ventas presenciales de Cajero, procesamiento idempotente de *webhooks* y reembolsos técnicos automáticos fuera de ventana. |
| boletos | Dominio | Emisión de folios cortos y códigos QR firmados por Función, generación binaria en memoria de **PDFs de boletos digitales, cortesías y reimpresiones de taquilla** (reportlab \+ QrCodeWidget), validación 100% online en tiempo real contra la ventana determinista de su propia función (\$\[hora\\\_inicio \- 2\\text{ h}, hora\\\_fin\]\$) y **modo contingencia** (exportación auditada en PDF con reportlab y CSV con csv estándar desde \$24\\text{ h}\$ antes, más reconciliación en lote). |
| cotizaciones | Dominio | Solicitudes de arrendamiento enviadas por Usuario estándar (un día o multi-día/turnos), cálculo de subtotal estimado informativo y monto oficial confirmado por Admin (*snapshot*), generación de **comprobantes de cotización en PDF** (reportlab), flujo estructurado de hasta \$3\$ fechas alternativas (PROPUESTA\_RETENIDA \$48\\text{ h}\$), pre-reserva estricta (PRE\_RESERVADO \$48\\text{ h}\$), esquema 50/50 vs 100% (umbral efectivo \$28\\text{ d}\$, saldo \$D-21\$), pagos con tarjeta o ficha Stripe y resolución de pagos extemporáneos (\$72\\text{ h}\$). |
| agenda | Transversal | Control centralizado y neutral de ocupación del inmueble (BloqueoAgenda y AgendaService) para validar, retener propuestas, pre-reservar, confirmar, reprogramar atómicamente y liberar intervalos sin acoplar cartelera con cotizaciones. |
| auditoria | Transversal | Registro inmutable de acciones sensibles (RegistroAuditoria y AuditoriaService) consumido por la capa de servicios de todos los módulos operativos. |

## **1\. Matriz Oficial de Roles y Permisos (RBAC)**

El control de acceso diferencia entre **Visitantes anónimos** (sin sesión) y **4 roles cerrados** implementados mediante TextChoices en el modelo de usuario, aplicando el principio de menor privilegio. Los módulos transversales agenda y auditoria no exponen operaciones de escritura públicas: se invocan internamente a través de los servicios autorizados de cada módulo (y la vista consolidada del calendario maestro/auditoría es exclusiva para Admin).

| Módulo | Visitante (Sin sesión) | Usuario estándar (USUARIO) | Cajero (CAJERO) | Verificador (VERIFICADOR) | Admin (ADMIN) |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **cartelera** | Leer eventos comerciales/públicos publicados y funciones. | Leer eventos publicados, configurar sub-secciones/precios y subir póster de **sus** arrendamientos pagados. | Leer funciones comerciales activas para venta en taquilla. | Leer funciones activas para referencia operativa. | **CRUD completo** (eventos directos/arrendados, funciones, pósters, publicación, VENCIDO\_SIN\_PUBLICAR, cancelaciones, reprogramaciones y **Configuración**). |
| **inventario** | Ver mapa de \$1,728\$ butacas, sub-secciones y disponibilidad (lectura). | Ver mapa y apartar temporalmente localidades de una función. | Ver mapa, apartar (\$10\\text{ min}\$) y vender localidades en taquilla física. | Sin acceso. | **Control total** (consulta, bloqueos técnicos sin QR y emisión/descarga de cortesías \$0.00 MXN). |
| **ventas** | Sin acceso (al elegir asiento redirige a login conservando selección). | Crear carrito (**1 función**), pagar en línea con tarjeta vía Stripe y ver **sus** órdenes. | Registrar ventas y cobros presenciales en taquilla (Efectivo / Tarjeta externa). | Sin acceso. | Ver historial global de ventas/pagos, conciliación, reembolsos técnicos y anulaciones auditadas. |
| **boletos** | Sin acceso. | Consultar y descargar **únicamente sus** boletos y QR (web y PDF). | Emitir y reimprimir excepcionalmente boletos vendidos en taquilla (PDF). | Escanear QR / folio manual y registrar ingreso único. | Consulta global, descarga PDF de cortesías, soporte de acceso y **modo contingencia** (exportación PDF/CSV y reconciliación en lote). |
| **cotizaciones** | Sin acceso. | Crear solicitudes de renta, descargar comprobante PDF, responder fechas alternativas, pagar (tarjeta/ficha) y solicitar cancelación/reprogramación de **las suyas**. | Sin acceso. | Sin acceso. | **Gestión completa**: revisar (SLA), ajustar monto oficial, aprobar/rechazar, proponer hasta \$3\$ fechas alternativas, resolver pagos extemporáneos y cancelaciones. |
| **usuarios** | Registro (LFPDPPP), login y recuperación de contraseña. | Editar **su propio** perfil y cerrar sesión. | Gestionar su propia sesión. | Gestionar su propia sesión. | **CRUD de cuentas internas** (Cajero, Verificador, Admin) y suspensión de cuentas. |

### **Reglas de implementación RBAC**

* **Autorización en el backend como única fuente de verdad:** Todas las restricciones se aplican en permissions.py de cada módulo DRF. Los *Route Guards* en React (ProtectedRoute.tsx) sirven únicamente para experiencia de usuario.  
* **Permisos a nivel de objeto (Anti-IDOR / BOLA):** En cartelera (edición de póster/sub-secciones del arrendatario), ventas, boletos y cotizaciones, toda consulta o acción de un Usuario estándar valida estrictamente la propiedad del recurso (recurso.usuario\_id \== request.user.id), impidiendo el acceso a registros de terceros mediante manipulación de identificadores en la URL.

## **2\. Reglas entre módulos**

Ventas coordina la compra de eventos **Comerciales** usando los servicios de inventario (DisponibilidadButaca) y boletos: en compras en línea exige cuenta registrada (Usuario estándar), acota el carrito a **una sola Función**, valida el límite de \$\\leq 10\$ boletos acumulados por cuenta/función y el horario de cierre web (\$30\\text{ min}\$ antes por defecto) y procesa cobros inmediatos con tarjeta mediante **Stripe Sandbox** (ejecutando reembolsos técnicos automáticos si una confirmación llega fuera de ventana y las localidades ya fueron tomadas). En taquilla física permite al Cajero autenticado apartar temporalmente localidades (\$10\\text{ min}\$) y registrar ventas presenciales hasta el cierre de taquilla (\$0\\text{ min}\$ antes por defecto) sin solicitar cuenta al comprador.

Cotizaciones permite a cualquier Usuario estándar enviar solicitudes de renta (un día o multi-día) mostrando un subtotal estimado informativo. Tanto la propuesta de hasta \$3\$ fechas alternativas (PROPUESTA\_RETENIDA por \$48\\text{ h}\$), la aprobación con pre-reserva (PRE\_RESERVADO por \$48\\text{ h}\$), la confirmación de pago (CONFIRMADO) como la programación de funciones o mantenimientos en cartelera validan y bloquean el intervalo completo exclusivamente a través del módulo transversal agenda. Los eventos de modalidad **Público** (sin boletaje ni QR) y **Privado** (ocultos en cartelera pública y sin póster) bloquean la agenda con las mismas reglas.

### **Reglas arquitectónicas obligatorias para el módulo transversal agenda (Solución B)**

Para preservar el **Principio de Dependencias Acíclicas (ADP)** y evitar errores de desarrollo durante el trabajo en paralelo:

1. **Dependencia estrictamente unidireccional (Cero imports inversos):** cartelera y cotizaciones dependen de apps/agenda/ y referencian a BloqueoAgenda. Queda estrictamente prohibido que cualquier archivo dentro de apps/agenda/ importe modelos, servicios o serializadores de otros módulos de negocio.  
2. **Puerta única de acceso (AgendaService):** Ningún módulo externo puede crear, modificar ni eliminar registros de BloqueoAgenda directamente vía ORM; toda interacción debe pasar por la interfaz pública de apps/agenda/services.py (verificar\_disponibilidad, retener\_propuestas, pre\_reservar\_bloque, confirmar\_bloque, reprogramar\_bloque y liberar\_bloque).  
3. **Neutralidad semántica (SoC):** agenda no contiene lógica de precios, eventos, pósters ni cotizaciones; únicamente gestiona intervalos de ocupación del inmueble, origen de bloqueo, estado (PROPUESTA\_RETENIDA, PRE\_RESERVADO, CONFIRMADO, LIBERADO) y una etiqueta descriptiva.  
4. **Doble candado ante concurrencia:** Las retenciones, reservas y reprogramaciones atómicas se ejecutan dentro de transacciones de base de datos combinadas con ExclusionConstraint en PostgreSQL (estado \!= 'LIBERADO').  
5. **Ciclo de vida controlado:** Una solicitud de cotización en estado EN\_REVISION no bloquea fechas; el BloqueoAgenda se genera al retener fechas propuestas (PROPUESTA\_RETENIDA), al aprobar una cotización (PRE\_RESERVADO) o al confirmar un evento directo/mantenimiento (CONFIRMADO), y pasa a LIBERADO al expirar, cancelarse o rechazarse (sin borrado físico).  
6. **Verificación automatizada en CI:** La suite de pruebas incluye una verificación arquitectónica automatizada (import-linter) que impide la introducción accidental de importaciones inversas desde apps/agenda/ hacia módulos de dominio.

**Eliminación de Django Admin (API REST pura):** Se elimina django.contrib.admin del proyecto para reducir la superficie de ataque, unificar la experiencia de autenticación y evitar modificaciones directas en base de datos fuera de la lógica de negocio. Toda la operación interna se realiza exclusivamente desde **React** consumiendo la API REST, garantizando que el \$100\\%\$ de las operaciones pasen por services.py, permissions.py y AuditoriaService.

## **3\. Validación de Acceso QR (100% Online) y Modo Contingencia**

La validación de boletos en puerta para eventos **Comerciales** (incluyendo cortesías emitidas por Admin) es **oficialmente 100% online en tiempo real** mediante la vista web responsiva ValidarAccesoPage.tsx, accesible directamente desde navegadores móviles modernos (Safari en iOS y Chrome en Android) **sin requerir PWA, Service Workers ni instalación de aplicaciones nativas**. Para operar con fiabilidad ante aforos de hasta \$1,728\$ personas, se establecen las siguientes reglas técnicas y operativas:

1. **Acceso a cámara por API web estándar:** Uso de MediaDevices.getUserMedia() mediante una librería ligera de lectura QR (html5-qrcode).  
2. **HTTPS estrictamente obligatorio:** En producción se garantiza mediante TLS 1.2/1.3 configurado en **Nginx** (certificados automatizados con Certbot); en pruebas móviles locales se utilizará un túnel HTTPS (cloudflared / ngrok) o el plugin @vitejs/plugin-basic-ssl en Vite.  
3. **Bloqueo atómico anti-duplicados:** El endpoint POST /api/v1/boletos/validar/ ejecuta una transacción atómica con select\_for\_update() sobre el registro del boleto, verificando que usado\_at sea nulo y el boleto no esté invalidado antes de marcar el ingreso. Ante dos escaneos simultáneos del mismo QR en distintas puertas, el segundo recibirá inmediatamente 409 Conflict indicando la hora de uso previo.  
4. **Validación determinista contra su propia función:** El código QR contiene un identificador no secuencial y firmado (UUID v4 \+ firma HMAC-SHA256 generada por el backend) vinculado a su Función específica. Al validar, el servidor evalúa **exclusivamente la ventana horaria determinista de esa función** (desde \$2\\text{ horas}\$ antes de hora\_inicio hasta hora\_fin, bajo America/Mexico\_City), permitiendo que funciones consecutivas traslapen sus horarios de acceso sin conflicto y devolviendo mensajes estructurados (*Acceso permitido*, *Abre a las HH:MM*, *La función ya terminó*, *Ya ingresó a las HH:MM*, *Boleto no válido*). El reingreso temporal durante intermedios se gestiona físicamente en puerta (sello o brazalete).  
5. **Resiliencia y Modo Contingencia Auditado:**  
   * Payload ligero de validación buscando respuestas en \$\< 200\\text{ ms}\$ y operación sobre red Wi-Fi privada dedicada del teatro con respaldo en datos móviles 4G/5G.  
   * Campo manual de respaldo por folio corto integrado debajo del visor de cámara en ValidarAccesoPage.tsx.  
   * **Modo contingencia:** Desde \$24\\text{ horas}\$ antes de cada función comercial, el Admin puede exportar desde el servidor un **listado de control de folios** generado en memoria en **PDF (reportlab, paginado con encabezados repetidos)** o **CSV (módulo estándar csv)** con folio corto, sub-sección, fila y asiento, quedando cada descarga registrada en AuditoriaService. Ante una caída total de conectividad en la zona, el Admin activa explícitamente (de forma auditada) el modo contingencia para tache impreso en puerta y, al restablecerse la conexión, ejecuta la **reconciliación en lote** marcando como utilizados los folios ingresados.

## **4\. Convenciones Transversales de la API REST**

La comunicación entre React y Django se realiza mediante **API REST JSON** bajo el mismo dominio servido por Nginx (excluyendo deliberadamente django-cors-headers para proteger las cookies de sesión y CSRF). Para mantener uniformidad entre los seis integrantes del equipo, todos los módulos cumplirán las siguientes convenciones:

* **Versionado y rutas:** Prefijo obligatorio /api/v1/\<modulo\>/ en minúsculas y plurales (ej. /api/v1/cartelera/eventos/, /api/v1/boletos/validar/).  
* **Formato uniforme de errores JSON:** Todas las respuestas 4xx/5xx devolverán una estructura consistente mediante un *custom exception handler* en DRF:

```
{
  "code": "ASIENTO_NO_DISPONIBLE",
  "message": "La butaca seleccionada ya fue apartada o vendida.",
  "details": { "butaca_id": 412 }
}

```

*   
  **Códigos HTTP estándar clave:** 200 OK / 201 Created (éxito), 400 Bad Request (validación y parámetros de filtro inválidos), 401 Unauthorized (sin sesión), 403 Forbidden (rol o propiedad insuficiente), 404 Not Found, 409 Conflict (butaca ocupada, cruce de agenda, función cerrada o boleto QR ya utilizado), 422 Unprocessable Entity (ventana horaria QR fuera de rango) y 429 Too Many Requests (límite de peticiones excedido).  
* **Fechas, horarios y moneda:** Almacenamiento en **UTC** en PostgreSQL e intercambio en formato **ISO 8601** bajo la zona horaria oficial **America/Mexico\_City** (evaluada determinísticamente en backend con zoneinfo \+ tzdata, y presentada en cliente con Intl.DateTimeFormat). Importes monetarios en Decimal(10, 2\) (MXN), formateados en frontend con Intl.NumberFormat y nunca procesados en punto flotante (float).  
* **Paginación y filtrado:** Paginación estándar en listados (PageNumberPagination, tamaño por defecto de \$20\$ elementos) combinada con **filtrado declarativo en backend mediante django-filter (FilterSet)** y los filtros nativos **SearchFilter y OrderingFilter** de DRF. Todos los parámetros de consulta (*query params*) de cartelera (fecha, categoría), cotizaciones, ventas y auditoría se validan antes de consultar PostgreSQL, devolviendo 400 Bad Request bajo el formato uniforme de errores ante valores inválidos y manteniendo views.py libre de parseos manuales repetitivos (**DRY** y **SoC**).

## **5\. Endpoints principales por módulo**

| Endpoint base | Descripción |
| :---- | :---- |
| **/api/v1/usuarios/** | Registro (con aceptación LFPDPPP), inicio/cierre de sesión en Redis (cookies HttpOnly \+ CSRF), recuperación de contraseña por correo SMTP, consulta/edición de perfil propio y CRUD de cuentas internas (Admin). |
| **/api/v1/cartelera/** | Consulta pública paginada y filtrable (django-filter por categoría y fecha) de eventos comerciales/públicos publicados, funciones y pósters (excluyendo privados y no publicados), CRUD de eventos directos/arrendados (Admin), carga de póster y configurador de sub-secciones/tarifas (\$\\leq 6\$ por sección, \$\\geq\$ \$100.00 MXN), resolución de VENCIDO\_SIN\_PUBLICAR, cancelaciones/reprogramaciones y **Configuración Administrativa** (ConfiguracionSistema, turnos y catálogo de extras). |
| **/api/v1/inventario/** | Consulta del mapa de \$1,728\$ asientos (incluyendo accesibles), endpoint ligero para *polling* de disponibilidad en tiempo real por función, bloqueos técnicos sin QR y emisión/descarga de cortesías (\$0.00 MXN con QR) por Admin. |
| **/api/v1/ventas/** | Gestión de carrito por **función única** (\$10\\text{ min}\$ \+ \$5\\text{ min}\$ gracia), creación de PaymentIntent con tarjeta en **Stripe Sandbox**, recepción idempotente de *webhooks* firmados (con reembolsos técnicos automáticos fuera de ventana) y endpoint protegido de venta presencial en taquilla para Cajero. |
| **/api/v1/boletos/** | Consulta y descarga en PDF (reportlab \+ QrCodeWidget) de boletos digitales del usuario y cortesías, reimpresión excepcional en taquilla, endpoint atómico POST /api/v1/boletos/validar/ para Verificador y endpoints auditados de **modo contingencia** (exportación PDF/CSV de folios y reconciliación en lote para Admin). |
| **/api/v1/cotizaciones/** | Envío de solicitudes de arrendamiento (un día o multi-día) con cálculo estimado informativo, descarga de comprobante PDF (reportlab), revisión y ajuste de monto oficial (*snapshot*) por Admin, envío y aceptación/rechazo de hasta \$3\$ fechas alternativas (PROPUESTA\_RETENIDA \$48\\text{ h}\$), pagos de arrendamiento (tarjeta o ficha Stripe dentro de PRE\_RESERVADO \$48\\text{ h}\$ y corte \$D-21\$), resolución de pagos extemporáneos (\$72\\text{ h}\$) y solicitudes de cancelación/reprogramación. |
| **/api/v1/agenda/** | Consulta de solo lectura del calendario maestro de ocupación (retenciones, pre-reservas, funciones, rentas y mantenimientos) y registro de bloqueos de mantenimiento restringida a Admin. |

# **Seguridad Aplicada**

Al tratarse de una plataforma con pagos electrónicos, control de aforo y acceso físico, la seguridad se diseña por capas:

1. **Autenticación, Recuperación y Gestión de Sesiones (VPS bajo el mismo dominio):**  
   * **Sesiones nativas de Django respaldadas en Redis (SessionAuthentication):** Cookies configuradas estrictamente como HttpOnly, Secure y SameSite=Lax, complementadas con la protección nativa contra **CSRF** (X-CSRFToken). Se descartan tokens estáticos sin expiración, JWT en localStorage y políticas CORS abiertas (django-cors-headers) para prevenir robo de credenciales vía XSS y permitir revocación inmediata al cerrar sesión o suspender una cuenta interna.  
   * **Contraseñas y recuperación:** Hashing seguro mediante **Argon2** (argon2-cffi), política de complejidad mínima y tokens de un solo uso con expiración corta para recuperación de contraseña por correo electrónico vía SMTP.  
2. **Seguridad en Pagos y Reembolsos Técnicos (Stripe Sandbox):**  
   * Cumplimiento PCI-DSS delegado: el servidor jamás recibe, procesa ni almacena números de tarjeta o CVV (captura directa con Stripe Elements).  
   * Validación criptográfica obligatoria de la cabecera Stripe-Signature en el endpoint de *webhooks* usando STRIPE\_WEBHOOK\_SECRET, registro de stripe\_event\_id para garantizar idempotencia estricta y llaves de idempotencia tanto en cobros como en **reembolsos técnicos automáticos** fuera de ventana.  
3. **Integridad de Boletos QR y Anti-Reventa:**  
   * Los códigos QR usan identificadores no predecibles (UUID v4) firmados con HMAC-SHA256 del servidor, impidiendo la falsificación o enumeración secuencial.  
   * Validación en capa de servicio del límite de \$\\leq 10\$ boletos acumulados por cuenta y función en ventas en línea (y por operación en taquilla), excluyendo únicamente las cortesías emitidas por Admin.  
4. **Protección Perimetral y OWASP Top 10:**  
   * **Rate Limiting en Nginx y DRF (*throttling*):** Límites estrictos en login y recuperación de contraseña (fuerza bruta), creación de carritos/checkout (bots acaparadores de boletos) y validación QR.  
   * **Cabeceras de seguridad HTTP en Nginx:** Strict-Transport-Security (HSTS), X-Content-Type-Options: nosniff, X-Frame-Options: DENY y política Content-Security-Policy (CSP) compatible con Stripe.  
   * **Prevención de inyección y carga insegura:** Uso estricto del ORM de Django (consultas parametrizadas \+ filtros validados con django-filter) y validación de tipo MIME, extensión y peso en la carga de pósters con Pillow.

# **Atributos de Calidad, Dimensionamiento y Contingencia**

## **1\. Requisitos No Funcionales Objetivo**

| Atributo | Métrica / Criterio Objetivo |
| :---- | :---- |
| **Rendimiento de API** | Consulta de cartelera y mapa de asientos \$\< 300\\text{ ms}\$ (p95); validación de código QR en puerta \$\< 200\\text{ ms}\$ (p95). |
| **Concurrencia** | Soporte simultáneo de al menos \$150\\text{--}250\$ usuarios concurrentes en picos de apertura de taquilla en línea sin sobreventas ni empalmes de agenda (\$0\\%\$ de doble asignación garantizado por select\_for\_update() y ExclusionConstraint). |
| **Disponibilidad** | \$\\geq 99.5\\%\$ durante ventanas activas de venta y acceso a funciones; reinicio automático de contenedores/servicios ante fallos. |
| **Usabilidad Móvil** | Interfaz responsiva con Tailwind CSS operativa en pantallas desde \$360\\text{ px}\$ de ancho (iOS Safari y Android Chrome), especialmente en ValidarAccesoPage.tsx, configurador de sub-secciones y consulta de boletos. |

## **2\. Dimensionamiento Mínimo del VPS**

Para ejecutar de forma estable Nginx, Gunicorn (Django), Celery Worker, Celery Beat, PostgreSQL y Redis en un servidor único (**sin proceso Node.js residente en producción**):

* **CPU / RAM:** Mínimo \$2\\text{ vCPU}\$ y \$4\\text{ GB}\$ de RAM (recomendado \$4\\text{ vCPU}\$ / \$8\\text{ GB}\$ RAM en eventos de alta demanda masiva).  
* **Almacenamiento:** Mínimo \$40\\text{ GB}\$ SSD NVMe (sistema operativo, base de datos PostgreSQL, directorio /media/carteles/, logs rotados y respaldos locales).  
* **Red:** Ancho de banda dedicado con IP fija y certificado TLS renovado automáticamente vía Certbot.

## **3\. Respaldos (RPO / RTO) y Contingencia Operativa**

* **Respaldos automatizados:** Volcado diario de PostgreSQL (pg\_dump comprimido mediante cron) y sincronización de /media/ hacia almacenamiento externo cifrado (ej. bucket S3/Backblaze o servidor secundario), buscando un **RPO** \$\\leq 24\\text{ horas}\$ (respaldo adicional previo a eventos grandes) y un **RTO** \$\\leq 2\\text{ horas}\$.  
* **Protocolo de contingencia ante caída de internet en puerta:** Dado que la validación QR es 100% online, el personal de acceso mantendrá como respaldo inmediato conexión por datos móviles 4G/5G si falla el Wi-Fi del recinto. Ante una caída total de conectividad en la zona, el Admin exporta desde \$24\\text{ horas}\$ antes el listado PDF (reportlab) o CSV de folios y localidades de la función, activa de forma auditada el **modo contingencia** para control impreso en puerta (complementado con sello/brazalete físico) y ejecuta posteriormente la **reconciliación en lote** de los folios ingresados.

# **Observabilidad y Auditoría**

* **Logs estructurados:** Registro en formato JSON (o texto estructurado con timestamp UTC, nivel, request\_id, usuario y módulo) para Nginx (accesos y errores), Gunicorn/Django, Celery Worker (tareas fallidas, reintentos, correos SMTP y reembolsos técnicos) y eventos de *webhooks* de Stripe. Rotación automática mediante logrotate para evitar llenado de disco en el VPS.  
* **Monitoreo de salud (*Healthchecks*):** Endpoint interno GET /api/v1/health/ que verifica conectividad con PostgreSQL y Redis, consumido por Docker/monitoreo del VPS para alertas tempranas.  
* **Auditoría funcional (auditoria / RegistroAuditoria):** Toda operación crítica (venta en taquilla, aprobación/rechazo/propuesta/reprogramación/cancelación de cotización o evento, resolución de VENCIDO\_SIN\_PUBLICAR y pagos extemporáneos, bloqueos técnicos y cortesías, reembolsos técnicos automáticos, exportación/activación/reconciliación de modo contingencia, cambios en Configuración Administrativa y gestión de cuentas internas) persiste automáticamente su rastro inmutable en base de datos mediante AuditoriaService.

# **Estructura del Repositorio**

**Nota:** Los árboles de directorios siguientes representan la **estructura base de referencia** del proyecto para coordinar a los seis integrantes. Los subcomponentes o utilidades menores que surjan durante las cuatro semanas de desarrollo (como archivos filters.py para django-filter, tailwind.config.js o plantillas de comprobantes PDF) se organizarán siguiendo este mismo patrón por módulo sin requerir modificar esta documentación.

## **Árbol general del repositorio**

```
teatro-coatzacoalcos/
├── frontend/
│   ├── public/
│   │   └── carteles/              Solo assets estáticos y placeholders (ej. sin-poster.jpg)
│   ├── src/
│   │   ├── app/
│   │   │   ├── App.tsx
│   │   │   └── router.tsx
│   │   ├── components/
│   │   │   ├── Header.tsx
│   │   │   ├── Footer.tsx
│   │   │   └── Button.tsx
│   │   ├── features/
│   │   │   ├── usuarios/
│   │   │   │   ├── LoginPage.tsx
│   │   │   │   ├── RegistroPage.tsx
│   │   │   │   ├── RecuperarPasswordPage.tsx
│   │   │   │   ├── PerfilPage.tsx
│   │   │   │   ├── LegalPage.tsx
│   │   │   │   ├── AuthContext.tsx
│   │   │   │   └── ProtectedRoute.tsx
│   │   │   ├── admin/
│   │   │   │   ├── AdminEventosPage.tsx
│   │   │   │   ├── AdminAgendaSolicitudesPage.tsx
│   │   │   │   ├── AdminConfiguracionPage.tsx
│   │   │   │   └── AdminPersonalPage.tsx
│   │   │   ├── cartelera/
│   │   │   │   ├── CarteleraPage.tsx
│   │   │   │   ├── EventoPage.tsx
│   │   │   │   ├── EventoCard.tsx
│   │   │   │   └── ConfiguradorTarifas.tsx
│   │   │   ├── inventario/
│   │   │   │   ├── SeleccionButacasPage.tsx
│   │   │   │   └── MapaAsientos.tsx
│   │   │   ├── ventas/
│   │   │   │   ├── CarritoPage.tsx
│   │   │   │   ├── ConfirmacionCompraPage.tsx
│   │   │   │   ├── TaquillaPanel.tsx
│   │   │   │   └── __tests__/
│   │   │   │       └── CarritoPage.test.tsx
│   │   │   ├── boletos/
│   │   │   │   ├── MisBoletosPage.tsx
│   │   │   │   ├── ValidarAccesoPage.tsx
│   │   │   │   └── ContingenciaBoletosPage.tsx
│   │   │   └── cotizaciones/
│   │   │       ├── SolicitudRentaPage.tsx
│   │   │       └── DetalleCotizacionPage.tsx
│   │   ├── api/
│   │   │   └── client.ts
│   │   ├── styles/
│   │   │   └── global.css
│   │   └── main.tsx
│   ├── tests/
│   │   └── e2e/
│   │       ├── compra.spec.ts
│   │       ├── acceso.spec.ts
│   │       └── cotizacion.spec.ts
│   ├── package.json
│   ├── package-lock.json
│   ├── playwright.config.ts
│   ├── vite.config.ts
│   └── tsconfig.json
├── backend/
│   ├── config/
│   │   ├── __init__.py
│   │   ├── celery.py
│   │   ├── settings.py
│   │   ├── urls.py
│   │   └── wsgi.py
│   ├── apps/
│   │   ├── __init__.py
│   │   ├── agenda/                Módulo transversal de ocupación del recinto (Solución B)
│   │   ├── auditoria/             Módulo transversal de bitácora inmutable
│   │   ├── usuarios/
│   │   ├── cartelera/
│   │   ├── inventario/
│   │   │   └── management/
│   │   │       └── commands/
│   │   │           ├── seed_teatro.py
│   │   │           ├── seed_catalogos.py
│   │   │           └── seed_demo.py
│   │   ├── boletos/
│   │   ├── cotizaciones/
│   │   └── ventas/
│   │       ├── __init__.py
│   │       ├── apps.py
│   │       ├── models.py
│   │       ├── serializers.py
│   │       ├── permissions.py
│   │       ├── views.py
│   │       ├── services.py
│   │       ├── tasks.py
│   │       ├── urls.py
│   │       ├── migrations/
│   │       │   └── __init__.py
│   │       └── tests/
│   │           ├── __init__.py
│   │           ├── test_apartados.py
│   │           └── test_compras.py
│   ├── Dockerfile
│   ├── manage.py
│   ├── requirements.txt
│   └── .env.example
├── database/
│   ├── 01_esquema.sql
│   ├── 02_inserts_teatro.sql
│   └── 03_inserts_demo.sql
├── .github/
│   └── workflows/
│       └── pruebas.yml
├── docker-compose.yml
├── .gitignore
└── README.md

```

Django es la fuente única de verdad para el esquema de la base de datos mediante sus migraciones y comandos de sembrado (seed\_teatro, seed\_catalogos, seed\_demo), conservando database/ como respaldo documental SQL. docker-compose.yml estandariza el entorno local de los seis integrantes (**PostgreSQL, Redis, Django, Celery Worker, Celery Beat y Mailpit** para pruebas locales de correo SMTP). .env.example documentará las variables de configuración y cada integrante guardará sus valores locales en un archivo .env excluido por .gitignore.

## **Árbol detallado del frontend**

```
frontend/
├── public/
│   └── carteles/
├── src/
│   ├── app/
│   │   ├── App.tsx
│   │   └── router.tsx
│   ├── components/
│   │   ├── Header.tsx
│   │   ├── Footer.tsx
│   │   └── Button.tsx
│   ├── features/
│   │   ├── usuarios/
│   │   │   ├── LoginPage.tsx
│   │   │   ├── RegistroPage.tsx
│   │   │   ├── RecuperarPasswordPage.tsx
│   │   │   ├── PerfilPage.tsx
│   │   │   ├── LegalPage.tsx
│   │   │   ├── AuthContext.tsx
│   │   │   └── ProtectedRoute.tsx
│   │   ├── admin/
│   │   │   ├── AdminEventosPage.tsx
│   │   │   ├── AdminAgendaSolicitudesPage.tsx
│   │   │   ├── AdminConfiguracionPage.tsx
│   │   │   └── AdminPersonalPage.tsx
│   │   ├── cartelera/
│   │   │   ├── CarteleraPage.tsx
│   │   │   ├── EventoPage.tsx
│   │   │   ├── EventoCard.tsx
│   │   │   └── ConfiguradorTarifas.tsx
│   │   ├── inventario/
│   │   │   ├── SeleccionButacasPage.tsx
│   │   │   └── MapaAsientos.tsx
│   │   ├── ventas/
│   │   │   ├── CarritoPage.tsx
│   │   │   ├── ConfirmacionCompraPage.tsx
│   │   │   ├── TaquillaPanel.tsx
│   │   │   └── __tests__/
│   │   │       └── CarritoPage.test.tsx
│   │   ├── boletos/
│   │   │   ├── MisBoletosPage.tsx
│   │   │   ├── ValidarAccesoPage.tsx
│   │   │   └── ContingenciaBoletosPage.tsx
│   │   └── cotizaciones/
│   │       ├── SolicitudRentaPage.tsx
│   │       └── DetalleCotizacionPage.tsx
│   ├── api/
│   │   └── client.ts
│   ├── styles/
│   │   └── global.css
│   └── main.tsx
├── tests/
│   └── e2e/
│       ├── compra.spec.ts
│       ├── acceso.spec.ts
│       └── cotizacion.spec.ts
├── package.json
├── package-lock.json
├── playwright.config.ts
├── vite.config.ts
└── tsconfig.json

```

### **Responsabilidades de cada archivo (Frontend)**

| Archivo / Directorio | Contenido y Responsabilidad |
| :---- | :---- |
| public/carteles/ | Activos estáticos de compilación y respaldo visual (sin-poster.jpg); no almacena pósters dinámicos subidos en producción. |
| App.tsx y router.tsx | Componente principal de la aplicación y enrutamiento global de la SPA (react-router-dom v6). |
| components/ | Componentes de interfaz reutilizables globales (Header, Footer, Button) estilizados con Tailwind CSS e iconografía lucide-react. |
| features/usuarios/ | Flujos de autenticación: LoginPage.tsx, RegistroPage.tsx (con aceptación LFPDPPP), RecuperarPasswordPage.tsx, PerfilPage.tsx, LegalPage.tsx (Aviso de Privacidad y Términos), contexto global (AuthContext.tsx, preservando selección de asientos tras login) y protección de rutas (ProtectedRoute.tsx). |
| features/admin/ | **Panel administrativo ligero en React** (exclusivo para Admin): alta/edición de eventos directos y arrendados (AdminEventosPage.tsx), agenda visual (@fullcalendar/react) para revisar, aprobar, proponer fechas alternativas, reprogramar y cancelar (AdminAgendaSolicitudesPage.tsx), administración de tarifas base de turnos, catálogo de extras y parámetros operativos (AdminConfiguracionPage.tsx) y gestión de cuentas internas (AdminPersonalPage.tsx). |
| features/ (resto de módulos) | Módulos funcionales del portal y operación diaria: cartelera y configurador de sub-secciones (ConfiguradorTarifas.tsx), mapa interactivo de \$1,728\$ butacas (optimizado con React.memo y *polling* ligero) con bloqueos técnicos y cortesías, carrito por función única, TaquillaPanel.tsx (Cajero), ValidarAccesoPage.tsx (Verificador) y ContingenciaBoletosPage.tsx (Admin). |
| features/\*\*/\_\_tests\_\_/ | Pruebas unitarias y de componentes colocadas junto a cada módulo (ejecutadas con **Vitest \+ React Testing Library**). |
| api/client.ts | Cliente HTTP ligero sobre fetch nativo para la comunicación con /api/v1/ con envío automático de credenciales de sesión (credentials: 'include') y cabecera X-CSRFToken. |
| styles/global.css | Punto de entrada de **Tailwind CSS** (@tailwind base/components/utilities) y ajustes visuales responsivos globales (desde \$360\\text{ px}\$). |
| tests/e2e/ y playwright.config.ts | Pruebas automatizadas extremo a extremo (E2E) de flujos críticos de usuario. |
| vite.config.ts y tsconfig.json | Configuración del empaquetador Vite 5.4, proxy local de /api/ y /media/, pruebas Vitest y opciones del compilador TypeScript (ejecutado sobre Node.js 22 LTS únicamente en desarrollo/CI/build). |

## **Árbol del backend**

El detalle de ventas muestra el patrón de organización para las demás aplicaciones de dominio; agenda y auditoria siguen el mismo formato minimalista centrado en models.py, services.py, migrations/ y tests/. Se omite admin.py al operar el backend como API REST pura sin django.contrib.admin.

```
backend/
├── config/
│   ├── __init__.py
│   ├── celery.py
│   ├── settings.py
│   ├── urls.py
│   └── wsgi.py
├── apps/
│   ├── __init__.py
│   ├── agenda/
│   │   ├── __init__.py
│   │   ├── apps.py
│   │   ├── models.py
│   │   ├── services.py
│   │   ├── views.py
│   │   ├── urls.py
│   │   ├── migrations/
│   │   │   └── __init__.py
│   │   └── tests/
│   │       ├── __init__.py
│   │       └── test_agenda.py
│   ├── auditoria/
│   ├── usuarios/
│   ├── cartelera/
│   ├── inventario/
│   │   └── management/
│   │       └── commands/
│   │           ├── seed_teatro.py
│   │           ├── seed_catalogos.py
│   │           └── seed_demo.py
│   ├── boletos/
│   ├── cotizaciones/
│   └── ventas/
│       ├── __init__.py
│       ├── apps.py
│       ├── models.py
│       ├── serializers.py
│       ├── permissions.py
│       ├── views.py
│       ├── services.py
│       ├── tasks.py
│       ├── urls.py
│       ├── migrations/
│       │   └── __init__.py
│       └── tests/
│           ├── __init__.py
│           ├── test_apartados.py
│           └── test_compras.py
├── Dockerfile
├── manage.py
├── requirements.txt
└── .env.example

```

### **Responsabilidades de cada archivo (Backend)**

| Archivo | Contenido |
| :---- | :---- |
| config/celery.py | Configuración de la instancia de Celery, conexión con Redis y programación periódica (*Celery Beat*) de vencimientos y recordatorios. |
| apps.py | Configuración de la aplicación Django *(se omite admin.py al eliminar django.contrib.admin)*. |
| models.py | Modelos, índices y restricciones de las tablas del módulo (fuente única de verdad del esquema). |
| serializers.py | Validación y conversión de datos JSON de la API. |
| permissions.py | Clases de autorización de DRF basadas en la matriz RBAC (ADMIN, CAJERO, VERIFICADOR, USUARIO) y validación de propiedad a nivel de objeto (anti-IDOR). |
| views.py y urls.py | Recepción de peticiones, vinculación de permisos, filtrado declarativo (django-filter), respuestas y rutas de la API REST (/api/v1/). |
| services.py | Operaciones del negocio, límites transaccionales, generación de PDFs/CSV (reportlab y csv), coordinación con AgendaService y registro de auditoría. |
| tasks.py | Tareas asíncronas y programadas ejecutadas por Celery (liberación de carritos vencidos, expiración de propuestas/pre-reservas de \$48\\text{ h}\$, recordatorios de publicación, procesamiento idempotente de *webhooks* de Stripe, reembolsos técnicos automáticos y correos transaccionales vía django.core.mail). |
| management/commands/ | Comandos administrativos de Django (seed\_teatro.py, seed\_catalogos.py, seed\_demo.py) para poblar de forma idempotente las \$1,728\$ butacas, turnos, catálogos de servicios/infraestructura, parámetros por defecto y datos de prueba. |
| migrations/ y tests/ | Evolución versionada del esquema en PostgreSQL y pruebas automatizadas de comportamiento y límites arquitectónicos (Django TestCase / TransactionTestCase). |
| Dockerfile | Definición de la imagen del contenedor backend para desarrollo local con Docker Compose y despliegue reproducible en el VPS. |

# **Estrategia de Pruebas y Calidad**

Para garantizar la estabilidad del sistema, prevenir fallos críticos en la venta de boletos y asegurar el cumplimiento de los requerimientos de negocio, se implementará una estrategia de pruebas en múltiples niveles:

## **1\. Niveles de Pruebas**

* **Pruebas Unitarias (Backend y Frontend):**  
  * *Backend (Django):* Validación de la lógica de negocio en services.py (sub-secciones \$\\leq 6\$ y mínimo \$100.00 MXN, carrito por función única, cierres de \$30\\text{ min}\$ / \$0\\text{ min}\$, *snapshot* de tarifas y esquema 50/50 con umbral efectivo de \$28\\text{ d}\$, cortesías \$0.00 MXN, generación de PDFs/CSV, cancelaciones/reprogramaciones y reembolsos técnicos fuera de ventana), permisos RBAC y anti-IDOR en permissions.py, reglas de no empalme en AgendaService, tareas de Celery en tasks.py, modelos y restricciones utilizando **django.test.TestCase** (el adaptador de Stripe se simula con *mocks* en pruebas unitarias). Incluye verificación automatizada de dependencias unidireccionales del módulo agenda mediante import-linter.  
  * *Frontend (React \+ TypeScript):* Pruebas de componentes individuales, hooks y lógica de cliente ubicadas en src/features/\*\*/\_\_tests\_\_/ utilizando **Vitest y React Testing Library** (integrados nativamente con vite.config.ts).  
* **Pruebas de Integración:** Verificación de la correcta comunicación entre la API REST de Django, PostgreSQL y el broker Redis/Celery, así como la integración real con los *webhooks* firmados, fichas de arrendamiento y reembolsos de la pasarela **Stripe en entorno *sandbox***.  
* **Pruebas de Sistema y Extremo a Extremo (E2E):** Simulación de los flujos críticos del usuario final desde frontend/tests/e2e/ mediante **Playwright**, validando de punta a punta el registro e inicio de sesión (preservando selección), el configurador de sub-secciones y mapa de \$1,728\$ butacas, el carrito por función única, el pago en Stripe Sandbox, la venta presencial por Cajero, la gestión por Admin, la emisión del boleto con QR y su validación 100% online por Verificador.

## **2\. Pruebas de Concurrencia y Rendimiento**

* **Simulación de Alta Concurrencia:** Ejecución de pruebas mediante TransactionTestCase orientadas a verificar los bloqueos a nivel de fila (select\_for\_update()) sobre DisponibilidadButaca y Boleto, y la restricción ExclusionConstraint sobre BloqueoAgenda (PROPUESTA\_RETENIDA, PRE\_RESERVADO, CONFIRMADO), garantizando \$0\\%\$ de sobreventas (ni siquiera entre web y taquilla simultáneas), \$0\\%\$ de empalmes de fechas y \$0\\%\$ de dobles accesos al escanear QR.

## **3\. Automatización (CI/CD)**

* **Integración Continua:** Configuración de flujos de integración continua (GitHub Actions en .github/workflows/pruebas.yml) para ejecutar automáticamente en cada contribución al repositorio:  
  * **Backend:** Linting y formato con **ruff**, verificación de límites de dependencias con **import-linter** y ejecución de pruebas unitarias/integración con **Django TestCase (python manage.py test)**.  
  * **Frontend:** Verificación estática de tipos (**tsc \--noEmit**), linting y formato con **ESLint \+ Prettier** y pruebas de componentes con **Vitest**.

# **Despliegue e Infraestructura**

Para la puesta en producción y gestión del entorno de ejecución de la plataforma, se adopta una **arquitectura centralizada en Servidor Único (VPS con Nginx)**, acompañada de un esquema contenedorizado para desarrollo local y control estricto de configuración:

## **1\. Diagrama de Despliegue en VPS (UML 2.5 / PlantUML)**

```
@startuml
left to right direction

cloud "Internet\n(HTTPS :443 / HTTP :80)" as Internet

node "Servidor Único (VPS Linux)" <<device>> as VPS {
    node "Firewall UFW\n(Solo puertos 80/443 públicos)" <<infrastructure>> as UFW
    node "Nginx Reverse Proxy\n(TLS 1.2/1.3 + HSTS + Rate Limit)" <<executionEnvironment>> as Nginx {
        artifact "Build Estático React\n(SPA /)" as Static
    }

    node "Red Interna Docker / Localhost\n(Puertos no expuestos)" <<executionEnvironment>> as RedInterna {
        node "Gunicorn :8000" <<executionEnvironment>> as Gunicorn {
            artifact "Backend Django + DRF\n(/api/v1/)" as DjangoApp
        }
        node "Celery Worker + Beat" <<executionEnvironment>> as Worker {
            artifact "Tareas Asíncronas y Periódicas\n(tasks.py)" as TasksApp
        }
        database "PostgreSQL :5432\n(BD Relacional)" as PG
        database "Redis :6379\n(Sesiones + Broker)" as Redis
    }

    folder "Volumen Persistente\nMEDIA_ROOT (/media/)" as Media
}

node "Almacenamiento Externo Cifrado" <<device>> as Backup

Internet --> UFW : HTTPS (443)
UFW --> Nginx
Nginx --> Static : Sirve /
Nginx --> Media : Sirve /media/
Nginx --> Gunicorn : Proxy /api/v1/

DjangoApp --> PG : TCP :5432
DjangoApp --> Redis : TCP :6379
DjangoApp --> Media : Escribe pósters
TasksApp --> Redis : Consume cola
TasksApp --> PG : TCP :5432
PG ..> Backup : pg_dump diario (cron)
@enduml

```

## **2\. Arquitectura de Producción: Servidor Único (VPS / Nginx)**

* **Arquitectura Centralizada bajo un Mismo Dominio:** Despliegue integral en un servidor virtual privado (VPS) donde **Nginx** actúa como servidor web de archivos estáticos, proxy inverso hacia el backend y punto de terminación de cifrado SSL/TLS. **Node.js no se ejecuta como servicio activo en el VPS**; únicamente compila el *build* estático de React durante el empaquetado/CI.  
* **Políticas HTTPS y Cifrado:** Configuración estricta de HTTPS (certificados automatizados vía Let's Encrypt / Certbot) soportando exclusivamente protocolos **TLS 1.3 y TLS 1.2**. Quedan explícitamente descartadas y deshabilitadas las versiones anteriores (SSLv3, TLS 1.0 y TLS 1.1) por vulnerabilidades de seguridad. El uso estricto de HTTPS habilita además el acceso seguro a la cámara en navegadores móviles para la validación de códigos QR y protege las cookies Secure.  
* **Enrutamiento de Tráfico y Medios en Nginx:**  
  * / \$\\rightarrow\$ Sirve directamente los archivos estáticos compilados de React (incluyendo el portal público, taquilla, validador QR y panel administrativo) con respaldo de rutas SPA (try\_files \$uri /index.html).  
  * /media/ \$\\rightarrow\$ Sirve directamente los pósters dinámicos de eventos desde el directorio persistente del servidor (MEDIA\_ROOT).  
  * /api/ \$\\rightarrow\$ Redirige las peticiones a la aplicación Django REST Framework ejecutada tras **Gunicorn** (sin ruta /admin/ expuesta).  
* **Servicios Internos y Respaldos:** En el mismo VPS operan **PostgreSQL** (con respaldos automáticos diarios mediante pg\_dump programado en cron), **Redis** (almacén de sesiones y *broker* de mensajes), **Celery Worker** y **Celery Beat**, administrados mediante **Docker Compose** con políticas restart: unless-stopped.  
* **Seguridad de Red:** Exposición pública exclusiva de los puertos 80 (redirección permanente a HTTPS) y 443 mediante firewall (ufw), manteniendo PostgreSQL y Redis accesibles únicamente en la red interna privada.

## **3\. Entorno de Desarrollo Local**

* **Orquestación con Docker Compose:** El archivo docker-compose.yml en la raíz levanta de forma idéntica para los seis integrantes los servicios de **PostgreSQL, Redis, Django, Celery Worker, Celery Beat y Mailpit** (servidor SMTP capturador ligero con interfaz web local para inspeccionar correos transaccionales y enlaces de recuperación sin enviar correos reales ni alterar la configuración SMTP de producción), evitando incompatibilidades entre sistemas operativos (especialmente Redis y tzdata en Windows) y replicando fielmente el entorno del VPS.  
* **Frontend local:** Uso de Vite 5.4 (sobre Node.js 22 LTS) para el cliente React en modo servidor de desarrollo con Hot Module Replacement (HMR), redirigiendo las llamadas /api/ y /media/ al backend local (http\://localhost:8000) bajo el mismo origen para mantener consistencia con las cookies de sesión y CSRF. Para pruebas de cámara QR desde teléfonos reales en red local se habilitará HTTPS temporal (@vitejs/plugin-basic-ssl o túnel cloudflared/ngrok), y **Stripe CLI** para reenviar *webhooks* de Stripe Sandbox hacia localhost.

## **4\. Gestión de Configuración y Variables de Entorno**

* **Variables de Entorno:** Control de credenciales y parámetros de configuración mediante archivos .env. El repositorio contiene una plantilla .env.example detallando las claves requeridas (conexión a PostgreSQL, secretos de Django, REDIS\_URL para sesiones y Celery, ruta de MEDIA\_ROOT, configuración SMTP para notificaciones transaccionales —apuntando a Mailpit en local y a proveedor transaccional en producción— y llaves de **Stripe Sandbox** incluyendo STRIPE\_SECRET\_KEY y STRIPE\_WEBHOOK\_SECRET), manteniendo los valores sensibles locales y de producción fuera del control de versiones mediante .gitignore.

# **Patrones de Diseño y Principios de Desarrollo**

Para garantizar un sistema escalable, mantenible y desacoplado, la arquitectura de la plataforma del Teatro de la Ciudad de Coatzacoalcos incorpora los siguientes patrones de diseño aplicados al stack de Django y React:

## **1\. Patrón Arquitectónico y Capa de Servicios (Service Layer)**

* **Service Layer (Django):** Aísla la lógica de negocio pesada fuera de las vistas (views.py) y modelos de Django, concentrándola en módulos dedicados (services.py). Esto permite coordinar operaciones complejas transaccionales como la venta de boletos en línea y taquilla, bloqueo de inventario, cortesías, generación de PDFs/CSV (reportlab y csv), validación y contingencia de QR, gestión centralizada de agenda (AgendaService), registro de auditoría (AuditoriaService) y reglas de negocio en un solo punto reutilizable.

## **2\. Patrones Creacionales**

* **Factory Method y Builder:** Utilizados para la generación estructurada de boletos digitales y cortesías con tokens dinámicos firmados para códigos QR por función (y su renderizado PDF vía reportlab), así como la construcción personalizada de cotizaciones de arrendamiento (un día o multi-día) con sus extras, infraestructura escénica y valores *snapshot*.

## **3\. Patrones Estructurales**

* **Adapter:** Implementado para encapsular la pasarela real (**Stripe Sandbox**) mediante una interfaz genérica de procesamiento de pagos (PaymentGateway / StripeAdapter). Esto desacopla el backend del proveedor específico tanto para cobros (PaymentIntent y fichas de arrendamiento) como para **reembolsos técnicos automáticos** fuera de ventana, permitiendo usar un adaptador simulado en pruebas unitarias rápidas (TestCase) sin red y ejecutar pruebas de integración reales contra Stripe Sandbox.

## **4\. Patrones de Comportamiento**

* **Strategy:** Define algoritmos intercambiables para evaluar las políticas financieras y de ciclo de vida en Cotización y Pago de Arrendamiento: determinación de esquema 50/50 vs 100% según el umbral efectivo de \$28\\text{ días naturales}\$ (\$21\\text{ d}\$ de corte \+ \$7\\text{ d}\$ de margen) y aplicación de reglas de retención/reembolso externo ante cancelación o reprogramación según el umbral de \$21\\text{ días naturales}\$.  
* **Observer / Pub-Sub:** Implementado sobre **Celery \+ Redis** para gestionar el procesamiento asíncrono de eventos del sistema: confirmación idempotente de pagos vía *webhooks* de Stripe, ejecución de reembolsos técnicos automáticos fuera de ventana, liberación de carritos/pre-reservas vencidas y envío de notificaciones transaccionales por correo SMTP.

# **Principios de Diseño y Calidad del Código**

Para evitar la complejidad involuntaria y garantizar el cumplimiento con la entrega en cuatro semanas, la arquitectura y el desarrollo del proyecto se regirán por los siguientes principios fundamentales:

* **SoC (Separation of Concerns / Separación de Responsabilidades):** Cada módulo, capa y componente debe mantener una única responsabilidad claramente delimitada (dividiendo de forma estricta presentación, negocio, módulos transversales y datos).  
* **YAGNI (You Aren't Gonna Need It):** Queda prohibido desarrollar funcionalidades no solicitadas o incurrir en sobreingeniería fuera del alcance definido.  
* **DRY (Don't Repeat Yourself):** Promoción activa de la reutilización de componentes UI en React (ej. mapa de \$1,728\$ butacas compartido entre portal público, taquilla y gestión de bloqueos/cortesías del Admin) y centralización de la lógica de negocio y filtrado (django-filter) en el backend.  
* **Principios SOLID y ADP esenciales:** Enfoque prioritario en Responsabilidad Única (*Single Responsibility*), Inversión de Dependencias (*Dependency Inversion*, clave para desacoplar integraciones como la pasarela de pagos con Stripe) y Dependencias Acíclicas (ADP, garantizado mediante la extracción transversal de agenda y auditoria).

# **Registro de Decisiones Arquitectónicas (ADR)**

| ID | Decisión | Alternativa descartada | Justificación técnica |
| :---- | :---- | :---- | :---- |
| **ADR-01** | Monolito modular en Django \+ DRF. | Microservicios (combinando Django y ASP.NET). | Garantiza transacciones ACID atómicas sobre PostgreSQL para el aforo de \$1,728\$ butacas, evita transacciones distribuidas y maximiza la velocidad de \$6\$ integrantes en \$4\$ semanas. |
| **ADR-02** | Django ORM y migraciones como única fuente de verdad de la BD. | Creación inicial manual mediante scripts .sql. | Evita desincronización de django\_migrations, permite ejecutar TestCase sin fricción y estandariza el sembrado vía comandos seed\_\*. |
| **ADR-03** | Servidor único (VPS \+ Nginx) con MEDIA\_ROOT y sesiones en Redis (sin CORS). | Nube desacoplada (Vercel \+ Render) con JWT en cliente. | Un solo origen simplifica seguridad (cookies HttpOnly \+ Secure \+ SameSite=Lax \+ CSRF sin django-cors-headers), permite revocación instantánea de sesiones y centraliza almacenamiento persistente de pósters. |
| **ADR-04** | Panel administrativo ligero en React y eliminación de Django Admin. | Exponer /admin/ de Django para gestión del teatro. | Permite construir una agenda visual, configurador de parámetros y gestión de cortesías/contingencias, fuerza a que el \$100\\%\$ de las acciones pasen por services.py y AuditoriaService, y reduce la superficie de ataque. |
| **ADR-05** | Validación QR 100% online desde navegador móvil (sin PWA) con modo contingencia auditado. | Modo híbrido offline con PWA e IndexedDB. | Evita el riesgo de doble acceso en puertas simultáneas sin conexión, elimina la complejidad de sincronización offline y resuelve caídas extremas con exportación PDF/CSV (reportlab/csv) de folios y reconciliación en lote. |
| **ADR-06** | Cuenta obligatoria solo en línea; taquilla física presencial por Cajero. | Modo invitado en línea o cuenta obligatoria en taquilla. | Permite hacer cumplir el límite de \$\\leq 10\$ boletos por función y dar seguimiento a cotizaciones en línea sin frenar la atención tradicional en taquilla física. |
| **ADR-07** | Extracción del módulo transversal agenda (Solución B) con ExclusionConstraint. | Mantener la agenda acoplada dentro de cartelera. | Elimina dependencias circulares entre cartelera y cotizaciones (ADP), permite trabajo paralelo real del equipo, soporta estados de retención/pre-reserva (PROPUESTA\_RETENIDA, PRE\_RESERVADO, CONFIRMADO) y garantiza integridad física contra empalmes en PostgreSQL. |
| **ADR-08** | Carrito por función única y segregación de medios de pago Stripe. | Carrito multi-evento o fichas de efectivo para boletos web. | Alinea el reloj único de \$10\\text{ min}\$ (+ \$5\\text{ min}\$ gracia), el cierre web independiente por función (\$30\\text{ min}\$ antes) y el límite de \$\\leq 10\$ boletos; restringe las fichas con línea de captura exclusivamente a arrendamientos (\$48\\text{ h}\$ de pre-reserva). |

