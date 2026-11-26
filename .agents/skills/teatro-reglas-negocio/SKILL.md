---
name: teatro-reglas-negocio
description: "Authoritative business rules, time windows, payment schemes, capacity constraints, state transitions, and scope boundaries for Teatro de la Ciudad de Coatzacoalcos. Use this skill whenever implementing, validating, or reviewing domain logic, forms, UI copy, pricing, quotes, cart/box-office flows, QR validation, cancellations, reschedules, or tests in either frontend/ or backend/."
---

# Reglas de Negocio y Límites de Alcance (Teatro Coatzacoalcos)

Todas las reglas temporales, cierres y días naturales se evalúan bajo **`America/Mexico_City`** (persistiendo timestamps en UTC). Todos los parámetros numéricos aquí indicados son los valores por defecto de `ConfiguracionSistema` y se aplican con política **snapshot** (cambios posteriores no alteran registros emitidos o confirmados). Para detalle completo, consulta `docs/alcance.md` y `docs/maquinas-de-estado.md`.

## 1. Aforo, Modalidades y Origen de Eventos

- **Recinto:** Sala única en primera entrega ("Teatro de la Ciudad", con modelo de datos preparado para multi-sala), con **1,728 butacas** fijas en **6 secciones oficiales** (`Luneta`, `Platea`, `Mezzanine`, `Primer Piso`, `Segundo Piso`, `Palcos`), incluyendo asientos accesibles (silla de ruedas y acompañante).
- **Modalidades:**
  - **Comercial:** cartelera pública, póster obligatorio, configuración tarifaria, aprobación final de `ADMIN` y boletaje completo (mapa 1,728, venta web/taquilla, QR).
  - **Público:** cartelera pública informativa, póster obligatorio y aprobación final de `ADMIN`, bloquea agenda, **sin boletaje ni QR** (el organizador controla acceso físico hasta 1,728 personas).
  - **Privado:** oculto en cartelera pública, sin póster ni boletaje, nace directo en `OPERACION_SIN_CARTELERA` y bloquea agenda.
- **Categorías fijas de cartelera (sembradas en `seed_catalogos`):** `Teatro`, `Música`, `Danza`, `Infantil y Familiar`, `Comedia / Stand-up`, `Conferencia / Institucional`, `Festival / Otros`.
- **Orígenes:** `ARRENDAMIENTO` (cotización + pago de `USUARIO`) o `DIRECTO` (alta por `ADMIN` sin cotización ni renta; respeta mismas reglas de agenda, póster y tarifas).
- **Relación Evento → Funciones:** Al confirmar pago inicial se crean el `Evento` y las `Funciones` iniciales de bloques de función (excluyendo bloques exclusivos de montaje/ensayos); al pasar un evento Comercial a `PUBLICADO` se ejecutan los `bulk_create` de 1,728 `DisponibilidadButaca` por función compartiendo póster, secciones del evento, fases de venta y tarifas congeladas. Soporta funciones nocturnas que cruzan medianoche (`fin_en` al día siguiente). Al rentar más de 1 día o más de 1 función el mismo día, los bloques de montaje/ensayo van incluidos en el precio (solo reservan agenda sin habilitar venta ni costo extra de turno).

## 2. Secciones del Evento, Fases de Venta, Tarifas, Bloqueos y Cortesías (Comercial)

- **Configurador tarifario (2 dimensiones independientes):**
  - **Secciones del evento (zonas de precio):** Cada butaca habilitada pertenece exactamente a una sección del evento. Cuatro modalidades:
    1. *Conservación estándar (1 clic, por defecto):* 6 secciones oficiales (`Luneta`, `Platea`, `Mezzanine`, `Primer Piso`, `Segundo Piso`, `Palcos`), con opción de deshabilitar secciones completas.
    2. *Sección única:* Todo el aforo habilitado en una sola sección comercial (ej. `"General"`).
    3. *Agrupación de secciones oficiales completas:* Unir dos o más secciones oficiales completas en una sola sección comercial con nombre libre (ej. `"Palmeras"`).
    4. *Subdivisión estructurada de una sección oficial:* Dividir una sección oficial en hasta `<= 6` secciones del evento contiguas (en graderías, un bloque rectangular de butacas contiguas que el configurador usa solo para capturar la geometría; el sistema expande la regla a una asignación por butaca en `asignacion_butaca`, y cada butaca queda en una sola sección del evento; en `Palcos` únicamente agrupando cabinas completas sin partir cabinas).
  - **Nomenclatura y unicidad:** Nombres sugeridos por defecto (`{Sección}` en conservación o `{Sección} - Zona {N}` al subdividir) o personalizados. El nombre no puede quedar vacío ni repetirse dentro del mismo evento.
  - **Fases de venta (variación por fecha de compra):** El periodo de venta se divide en una o más fases consecutivas (ej. `"Preventa"`, `"Venta general"`), cada una con nombre y fecha/hora de inicio; cada fase dura hasta que inicia la siguiente y la última hasta el cierre. Todo evento comercial tiene al menos una fase. La fase aplica a todas las funciones del evento y se determina por el momento en que el comprador aparta sus butacas.
  - **Matriz de precios y congelamiento:** Cada combinación de sección del evento y fase de venta tiene un precio oficial **`>= $100.00 MXN`** (precios finales netos en MXN sin IVA adicional), cubriendo el 100% de las butacas de las secciones habilitadas. Secciones del evento, nombres, fases de venta (incluyendo fecha de inicio) y precios se **congelan al publicar**.
- **Acciones post-publicación de `ADMIN` (solo sobre `DISPONIBLE` antes del cierre de taquilla):**
  - **Bloqueo técnico:** inhabilita butaca sin emitir boleto ni QR; reversible.
  - **Cortesía:** `$0.00 MXN` (método `Cortesía`), **sí emite boleto con QR válido**, **exenta del límite de 10 boletos**, no requiere cuenta del invitado y permite registrar beneficiario/motivo opcional.

## 3. Agenda, Cotizaciones y Arrendamiento

- **Turnos y no traslape:** `Matutino`, `Vespertino`, `Día Completo` (abarca ambos) y soporte multi-día con horarios por día. Intervalos semiabiertos `[inicio, fin)` permiten turnos consecutivos el mismo día sin falso choque.
- **Revisión y SLA:** `EN_REVISION` no bloquea agenda. SLA objetivo: **3 días hábiles** primera respuesta; alerta de atraso **> 5 días hábiles** ("días hábiles" = **lunes a viernes**, excluyendo fines de semana bajo `America/Mexico_City`); cierre automático `EXPIRADA_POR_FECHA` si pasa la fecha estimada.
- **Fechas alternativas:** `ADMIN` puede proponer hasta **3 opciones** (`PROPUESTA_RETENIDA` por **48 h naturales**) con un motivo opcional visible para el solicitante (`propuesta_fecha.motivo`). Aceptar 1 libera las otras 2; rechazar o vencer 48 h pasa a `PROPUESTA_EXPIRADA`. Sin chat interno.
- **Pre-reserva:** al aprobar monto oficial, entra en `PRE_RESERVADO` por **48 h naturales** (plazo único tanto para tarjeta como para generación y liquidación de ficha Stripe).
- **Versiones del monto oficial:** cada monto que envía `ADMIN` es una versión numerada (`cotizacion_version`) con nota opcional. La vigente es la de mayor número, las versiones anteriores no se editan y el aprobado queda en `cotizacion_parametros.version_aprobada_id`. Al aprobar se registra también el aforo acordado (`asistentes_acordados`), que puede diferir del estimado.
- **Extras e infraestructura:** precios base netos en MXN (sin IVA adicional) y unidad de cobro **configurable por ítem** (`POR_EVENTO`, `POR_DIA`, `POR_TURNO`, `POR_UNIDAD`).
- **Esquema 50/50 vs 100% (snapshot al aprobar respecto a la 1ra fecha reservada, incluido montaje/ensayo):**
  - **`> 30` días naturales (`>= 31 d`)**: **50/50 permitido** (corte `D-21` + margen de `9 d`); anticipo redondeado a 2 decimales (`ROUND_HALF_UP`) y `saldo = total - anticipo`, venciendo el día **`D-21` a las `23:59:59`**. No se emiten fichas en las últimas **48 h** previas a `D-21 23:59:59` (solo tarjeta).
  - **`<= 30` días naturales (`30 d` o menos)**: **100% obligatorio** en un solo pago.
  - **Incumplimiento en `D-21`:** `ADMIN` suspende/cancela evento, detiene venta, invalida QRs, conserva historial para devoluciones manuales, libera agenda explícitamente y el anticipo no se reembolsa.
- **Pagos extemporáneos (tras vencer 48 h o tras D-21):**
  - Fecha aún libre (solo pre-reserva inicial) → `PAGO_EXTEMPORANEO_EN_REVISION` (**72 h naturales** para que `ADMIN` acepte o rechace con devolución del 100%).
  - Fecha ya ocupada (o saldo tardío tras incumplir `D-21`) → **devolución íntegra del 100%**: reembolso técnico automático API para **tarjeta**, o estado `REEMBOLSO_BANCARIO_PENDIENTE` para **fichas SPEI/efectivo** (la no reembolsabilidad no aplica a desfases bancarios).
- **Límite de publicación:** tras pago inicial, el solicitante tiene **3 días** para cargar póster/tarifas (recordatorios a los **3 d** y cada **7 d**). Fecha límite determinista: **`min(inicio_primer_bloque_reservado, max(primera_fecha - 15d, fecha_pago + 3d))`** (eventos `Privado` pasan directo a `OPERACION_SIN_CARTELERA`). Al vencer pasa a `VENCIDO_SIN_PUBLICAR` (agenda sigue bloqueada hasta resolución explícita de `ADMIN`).

## 4. Compra de Boletos, Carrito, Taquilla y Acceso QR

- **Portal en línea (`USUARIO`):** cuenta obligatoria (si visitante elige asiento, redirige a login conservando función y selección). **1 `OrdenCompra` activa por usuario y por función única** (cambiar de función advierte y libera el apartado anterior). Reloj único de **10 min** (`expira_en`) desde el 1er asiento + **5 min** (`gracia_hasta`) si está en `PAGO_EN_PROCESO`. Solo tarjeta Stripe; límite **`<= 10` boletos acumulados por cuenta y función** sumando `APARTADO + PAGO_EN_PROCESO + PAGADA` (bloqueo atómico en `Usuario`); cierre web **`30 min` antes** de `hora_inicio`.
- **Webhook tardío en boletos (`EXPIRADA`):** bajo bloqueo global (`Usuario -> OrdenCompra -> DisponibilidadButaca -> OrdenCompraDetalle`), si el 100% de las butacas siguen `DISPONIBLE` y reasignar no supera `<= 10` boletos acumulados, reasigna y emite boletos (`PAGADA`); en caso contrario ejecuta **reembolso técnico automático del 100%** (`REEMBOLSADA_AUTOMATICA`).
- **Cierre independiente por función (`-30m` web / `0m` taquilla):** Al llegar el cierre, las `OrdenCompra` aún en `APARTADO` **no** pueden iniciar `checkout` y expiran; solo continúan en gracia (+5 min) las órdenes ya en `PAGO_EN_PROCESO` antes del cierre.
- **Taquilla física (`CAJERO`):** sin cuenta de comprador; comparte inventario de 1,728 y apartado de 10 min; pago `Efectivo` o `Tarjeta` (terminal externa); límite **`<= 10` boletos por operación**; cierre **`0 min` antes** (`hora_inicio`).
- **Validación QR (`VERIFICADOR`):** **100% online**, uso único, evalúa la ventana de la función embebida en el token **`[inicio_en - 2h, fin_en]`** (soportando cruce de medianoche). Mensajes exactos: `"Acceso permitido"` (+ sección, fila, asiento), `"Abre a las HH:MM"`, `"La función ya terminó"`, `"Boleto de la función DD/MM HH:MM"`, `"Ya ingresó a las HH:MM"`, `"Boleto no válido"`. Respaldo manual por folio corto; reingreso físico con sello/brazalete.
- **Modo contingencia:** exportación PDF/CSV (`folio_corto, seccion_subseccion, fila, asiento`) auditada desde **`24 h` antes** de la función + activación explícita registrada por función en `contingencia_funcion` (historial; una sola contingencia abierta por función) + reconciliación en lote vía CSV (`folio_corto`) o lista pegada en `ADMIN`. La reconciliación guarda los folios `aplicados`, `ya_usados` y `rechazados`; los boletos reconciliados quedan en `USADO_CONTINGENCIA`.

## 5. Cancelaciones y Reprogramaciones

- **Cancelación por arrendatario (`CANCELADO_POR_ARRENDATARIO`):** solo pagó 50% → anticipo no reembolsable; pagó 100% y faltan `>= 21 d` → retiene 50%, 50% reembolso externo; pagó 100% y `< 21 d` → sin reembolso. Si ya existen boletos vendidos en evento Comercial, `ADMIN` detiene venta, invalida QRs y conserva historial para devolución externa (bajo acuerdo organizador-teatro). Agenda se libera solo por acción explícita de `ADMIN`.
- **Cancelación por Teatro (`CANCELADO_POR_TEATRO`):** 100% reembolso externo o reprogramación sin costo; detiene venta, invalida QRs y conserva padrón para devoluciones manuales.
- **Reprogramación:** 1 cambio sin costo si se solicita con `>= 21 d` y hay agenda libre (`< 21 d` o 2da solicitud cuenta como cancelación + nueva cotización). Recalcula `D-21` y fecha límite de publicación respecto a la nueva fecha; si queda a `< 21 d` de hoy con saldo pendiente, exige liquidar `100%` antes de confirmar. Funciones con boletos vendidos solo las reprograma `ADMIN` (`REPROGRAMADO`), conservando boletos/QRs vigentes y notificando por correo a cuentas registradas. Siempre atómica en `AgendaService`.

## 6. Exclusiones de Alcance (No Implementar)

- Sin compra en línea como invitado ni fichas de efectivo/transferencia para boletos.
- Sin cortes poligonales libres, división de cabinas de palcos ni precios por asiento individual.
- Sin integración de hardware POS ni facturación electrónica (CFDI).
- Sin cambios de asiento, reembolsos autogestionados, reventa/transferencia entre cuentas ni descuentos (cupones, INAPAM, 2x1, estudiantes).
- Sin boletaje/QR para eventos Públicos o Privados ni listas de espera/sobreventa.
- Sin chat interno, CMS institucional, PWA/validación QR offline, catering/salas lounge/otros salones del Centro de Convenciones ni estacionamiento.
