---
name: teatro-reglas-negocio
description: "Authoritative business rules, time windows, payment schemes, capacity constraints, state transitions, and scope boundaries for Teatro de la Ciudad de Coatzacoalcos. Use this skill whenever implementing, validating, or reviewing domain logic, forms, UI copy, pricing, quotes, cart/box-office flows, QR validation, cancellations, reschedules, or tests in either frontend/ or backend/."
---

# Reglas de Negocio y Límites de Alcance (Teatro Coatzacoalcos)

Todas las reglas temporales, cierres y días naturales se evalúan bajo **`America/Mexico_City`** (persistiendo timestamps en UTC). Todos los parámetros numéricos aquí indicados son los valores por defecto de `ConfiguracionSistema` y se aplican con política **snapshot** (cambios posteriores no alteran registros emitidos o confirmados). Para detalle completo, consulta `docs/alcance.md` y `docs/maquinas-de-estado.md`.

## 1. Aforo, Modalidades y Origen de Eventos

- **Recinto:** **1,728 butacas** fijas en **6 secciones oficiales** (`Luneta`, `Platea`, `Mezzanine`, `Primer Piso`, `Segundo Piso`, `Palcos`), incluyendo asientos accesibles (silla de ruedas y acompañante).
- **Modalidades:**
  - **Comercial:** cartelera pública, póster obligatorio, configuración tarifaria y boletaje completo (mapa 1,728, venta web/taquilla, QR).
  - **Público:** cartelera pública informativa, póster obligatorio, bloquea agenda, **sin boletaje ni QR** (el organizador controla acceso físico hasta 1,728 personas).
  - **Privado:** oculto en cartelera pública, sin póster ni boletaje, bloquea agenda.
- **Orígenes:** `ARRENDAMIENTO` (cotización + pago de `USUARIO`) o `DIRECTO` (alta por `ADMIN` sin cotización ni renta; respeta mismas reglas de agenda, póster y tarifas).
- **Relación Evento → Funciones:** `1..N` funciones por evento; cada función comercial tiene inventario independiente de 1,728 butacas. Bloques exclusivos de montaje/ensayo reservan agenda sin habilitar venta de boletos.

## 2. Sub-secciones, Tarifas, Bloqueos y Cortesías (Comercial)

- **Configurador tarifario:** conservar 6 secciones (1 clic), deshabilitar secciones completas o subdividir en **`<= 6` sub-secciones por sección oficial**:
  - Graderías: solo cortes por filas completas y/o bloques continuos de columnas.
  - `Palcos`: solo agrupación de palcos completos (prohibido partir una cabina).
- **Nomenclatura y unicidad:** etiqueta por defecto `{Sección} - Zona {N}`, editable antes de publicar. Unicidad compuesta **`{Sección} - {Nombre}`** (ej. `Luneta - VIP` y `Palcos - VIP` son válidos; repetir nombre en la misma sección oficial o dejarlo vacío es inválido).
- **Piso mínimo y congelamiento:** cada sub-sección habilitada exige **`>= $100.00 MXN`**, cubriendo el 100% de las butacas de las secciones habilitadas. Sub-secciones, nombres y tarifas se **congelan al publicar**.
- **Acciones post-publicación de `ADMIN` (solo sobre `DISPONIBLE` antes del cierre de taquilla):**
  - **Bloqueo técnico:** inhabilita butaca sin emitir boleto ni QR; reversible.
  - **Cortesía:** `$0.00 MXN` (método `Cortesía`), **sí emite boleto con QR válido**, **exenta del límite de 10 boletos**, no requiere cuenta del invitado y permite registrar beneficiario/motivo opcional.

## 3. Agenda, Cotizaciones y Arrendamiento

- **Turnos y no traslape:** `Matutino`, `Vespertino`, `Día Completo` (abarca ambos) y soporte multi-día con horarios por día. Intervalos semiabiertos `[inicio, fin)` permiten turnos consecutivos el mismo día sin falso choque.
- **Revisión y SLA:** `EN_REVISION` no bloquea agenda. SLA objetivo: **3 días hábiles** primera respuesta; alerta de atraso **> 5 días hábiles**; cierre automático `EXPIRADA_POR_FECHA` si pasa la fecha estimada.
- **Fechas alternativas:** `ADMIN` puede proponer hasta **3 opciones** (`PROPUESTA_RETENIDA` por **48 h naturales**). Aceptar 1 libera las otras 2; rechazar o vencer 48 h pasa a `PROPUESTA_EXPIRADA`. Sin chat interno.
- **Pre-reserva:** al aprobar monto oficial, entra en `PRE_RESERVADO` por **48 h naturales** (plazo único tanto para tarjeta como para generación y liquidación de ficha Stripe).
- **Esquema 50/50 vs 100% (snapshot al aprobar respecto a la 1ra fecha reservada, incluido montaje/ensayo):**
  - **`>= 28` días naturales** (`21 d` corte + `7 d` margen): **50/50 permitido**; el 50% restante vence el día **`D-21` a las `23:59:59`**. No se emiten fichas en las últimas **48 h** previas a `D-21 23:59:59` (solo tarjeta).
  - **`< 28` días naturales**: **100% obligatorio** en una exhibición.
  - **Incumplimiento en `D-21`:** `ADMIN` suspende/cancela evento, detiene venta, invalida QRs, conserva historial para devoluciones manuales, libera agenda explícitamente y el anticipo no se reembolsa.
- **Pagos extemporáneos (tras vencer 48 h):**
  - Fecha aún libre → `PAGO_EXTEMPORANEO_EN_REVISION` (**72 h naturales** para que `ADMIN` acepte o rechace con reembolso del 100%).
  - Fecha ya ocupada → **reembolso técnico automático del 100%** (la no reembolsabilidad del anticipo no aplica a desfases bancarios).
- **Límite de publicación:** tras pago inicial, el solicitante tiene **3 días** para cargar póster/tarifas (recordatorios a los **3 d** y cada **7 d**). Fecha límite por defecto: **`D-15`** (o **3 d** tras pago si faltaba `< 15 d`). Al vencer pasa a `VENCIDO_SIN_PUBLICAR` (agenda sigue bloqueada hasta resolución explícita de `ADMIN`).

## 4. Compra de Boletos, Carrito, Taquilla y Acceso QR

- **Portal en línea (`USUARIO`):** cuenta obligatoria (si visitante elige asiento, redirige a login conservando función y selección). **1 carrito activo por usuario y por función única** (cambiar de función advierte y libera el anterior). Reloj único de **10 min** desde el 1er asiento + **5 min** de gracia si está en `PAGO_EN_PROCESO`. Solo tarjeta Stripe; límite **`<= 10` boletos por cuenta y función**; cierre web **`30 min` antes** de `hora_inicio`.
- **Webhook tardío en boletos (`EXPIRADA`):** si el 100% de las butacas siguen `DISPONIBLE`, reasigna y emite boletos; si al menos 1 ya fue ocupada, ejecuta **reembolso técnico automático del 100%** (`REEMBOLSADA_AUTOMATICA`).
- **Taquilla física (`CAJERO`):** sin cuenta de comprador; comparte inventario de 1,728 y apartado de 10 min; pago `Efectivo` o `Tarjeta` (terminal externa); límite **`<= 10` boletos por operación**; cierre **`0 min` antes** (`hora_inicio`).
- **Validación QR (`VERIFICADOR`):** **100% online**, uso único, evalúa la ventana de la función embebida en el token **`[hora_inicio - 2h, hora_fin]`**. Mensajes exactos: `"Acceso permitido"` (+ sub-sección, fila, asiento), `"Abre a las HH:MM"`, `"La función ya terminó"`, `"Boleto de la función DD/MM HH:MM"`, `"Ya ingresó a las HH:MM"`, `"Boleto no válido"`. Respaldo manual por folio corto; reingreso físico con sello/brazalete.
- **Modo contingencia:** exportación PDF/CSV auditada desde **`24 h` antes** de la función + activación explícita + reconciliación en lote.

## 5. Cancelaciones y Reprogramaciones

- **Cancelación por arrendatario (`CANCELADO_POR_ARRENDATARIO`):** solo pagó 50% → anticipo no reembolsable; pagó 100% y faltan `>= 21 d` → retiene 50%, 50% reembolso externo; pagó 100% y `< 21 d` → sin reembolso. Agenda se libera solo por acción explícita de `ADMIN`.
- **Cancelación por Teatro (`CANCELADO_POR_TEATRO`):** 100% reembolso externo o reprogramación sin costo; detiene venta, invalida QRs y conserva padrón para devoluciones manuales.
- **Reprogramación:** 1 cambio sin costo si se solicita con `>= 21 d` y hay agenda libre (`< 21 d` o 2da solicitud cuenta como cancelación + nueva cotización). Funciones con boletos vendidos solo las reprograma `ADMIN` (`REPROGRAMADO`), conservando boletos/QRs vigentes y notificando por correo a cuentas registradas. Siempre atómica en `AgendaService`.

## 6. Exclusiones de Alcance (No Implementar)

- Sin compra en línea como invitado ni fichas de efectivo/transferencia para boletos.
- Sin cortes poligonales libres, división de cabinas de palcos ni precios por asiento individual.
- Sin integración de hardware POS ni facturación electrónica (CFDI).
- Sin cambios de asiento, reembolsos autogestionados, reventa/transferencia entre cuentas ni descuentos (cupones, INAPAM, 2x1, estudiantes).
- Sin boletaje/QR para eventos Públicos o Privados ni listas de espera/sobreventa.
- Sin chat interno, CMS institucional, PWA/validación QR offline, catering/salas lounge/otros salones del Centro de Convenciones ni estacionamiento.
