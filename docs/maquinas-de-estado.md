# **Especificación de Máquinas de Estado y Concurrencia**

* **Proyecto:** Plataforma de Boletaje en Línea y Cotización de Arrendamiento — Teatro de la Ciudad de Coatzacoalcos
* **Responsable Técnico:** José Manuel Fabian Hernández
* **Versión:** 2.0 (Sincronizada con Alcance, Arquitectura y Stack Tecnológico)
* **Zona Horaria Oficial:** `America/Mexico_City` (persistiendo todos los *timestamps* en UTC)
* **Estándares y Patrones Aplicados:** UML 2.5 State Machines, *Domain Services* con `TextChoices`, Separación de Responsabilidades (SoC), Idempotencia y Control de Concurrencia Pesimista.

## **Índice de Diagramas PlantUML**

| Código | Máquina de Estados | Archivo de Diagrama |
| :---- | :---- | :---- |
| **ME-01** | Cotización y Arrendamiento | [me01-cotizacion-arrendamiento.puml](./maquinas-de-estado/me01-cotizacion-arrendamiento.puml) |
| **ME-02** | Evento y Función | [me02-evento-funcion.puml](./maquinas-de-estado/me02-evento-funcion.puml) |
| **ME-03** | Orden de Compra (Boletaje) | [me03-orden-compra.puml](./maquinas-de-estado/me03-orden-compra.puml) |
| **ME-04** | DisponibilidadButaca y Boleto QR | [me04-butaca-qr.puml](./maquinas-de-estado/me04-butaca-qr.puml) |

## **1. Propósito y Reglas Arquitectónicas de Transición**

* **El "qué":** Define los estados finitos, eventos disparadores, condiciones guarda y efectos secundarios de las cuatro entidades transaccionales críticas del sistema (**Cotización/Arrendamiento**, **Evento/Función**, **OrdenCompra** y **DisponibilidadButaca/Boleto QR**), junto con los mecanismos para resolver condiciones de carrera (*race conditions*).
* **El "cómo":** Ningún controlador HTTP (`ViewSet`), tarea de Celery ni *webhook* de Stripe puede modificar directamente el campo `estado` mediante asignaciones crudas (`obj.estado = ...`). Toda transición debe invocarse a través de métodos explícitos en la capa de servicios (`services.py` / *Domain Services*) dentro de bloques transaccionales atómicos (`transaction.atomic()`), registrando cada cambio sensible en la bitácora inmutable de auditoría (`AuditoriaService`).
* **El "por qué" (Prevención de deuda técnica):** Desacopla las reglas temporales y de pago de la interfaz web y evita que procesos concurrentes (dos compradores, el reloj de expiración de Celery Beat y notificaciones asíncronas de Stripe) corrompan el inventario de 1,728 butacas o provoquen dobles reservas de agenda.

## **2. ME-01 — Máquina de Estados de Cotización y Arrendamiento**

### **2.1 Reglas de Diseño del Ciclo de Vida**

* **Bloqueo temprano de agenda:** Una solicitud en `EN_REVISION` no bloquea fechas (la bandera SLA `atrasada = True` se activa a los `> 5 días hábiles` lunes–viernes sin atención, sin crear sub-estados). Los estados `PROPUESTA_RETENIDA`, `PRE_RESERVADO` y `CONFIRMADO` ocupan activamente los rangos de fecha/turno en `BloqueoAgenda` mediante la restricción `ExclusionConstraint` en PostgreSQL (`btree_gist`), impidiendo traslapes entre solicitudes.
* **Esquema `50/50` vs. `100%` y sub-estado financiero en `CONFIRMADO`:** Al aprobar la cotización, el sistema congela como *snapshot* el esquema aplicable según los días naturales entre la aprobación y la primera fecha reservada (incluyendo montaje/ensayos): **`> 30 días naturales` (`>= 31 d`)** permite `50/50` (corte `D-21` + margen de `9 días`); **`<= 30 días naturales`** exige `100%` obligatorio en un solo pago. El anticipo `50%` se redondea a 2 decimales (`ROUND_HALF_UP`) y `saldo = total - anticipo`, venciendo a las `23:59:59` del día `D-21` (sin emisión de fichas Stripe en las últimas `48 h` previas a `D-21 23:59:59`). Un atributo secundario (`estado_liquidacion`: `ANTICIPO_50_PAGADO | LIQUIDADO_100 | REEMBOLSO_BANCARIO_PENDIENTE`) controla el cobro del saldo y las devoluciones bancarias externas de fichas SPEI/efectivo.

### **2.2 Diagrama de Estados (PlantUML)**

* **Diagrama fuente:** [ME-01 — Cotización y Arrendamiento (`me01-cotizacion-arrendamiento.puml`)](./maquinas-de-estado/me01-cotizacion-arrendamiento.puml)

### **2.3 Matriz de Transiciones y Guardas (ME-01)**

| ID | Estado Origen | Evento / Disparador | Condición Guarda | Estado Destino | Efectos Secundarios y Auditoría |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **T-1.1** | `EN_REVISION` | `proponer_fechas_alt` | `1..3` opciones mutuamente disjuntas y libres en `AgendaService`. | `PROPUESTA_RETENIDA` | Inserta bloqueos en `BloqueoAgenda` por 48 h naturales y notifica por correo al solicitante. |
| **T-1.2** | `PROPUESTA_RETENIDA` | `aceptar_alternativa` | Dentro de 48 h y la opción elegida sigue retenida. | `EN_REVISION` | Libera las opciones no elegidas; mantiene retenida la elegida en `BloqueoAgenda` (sin expirar por 48 h) hasta que Admin apruebe tarifa oficial. |
| **T-1.3** | `PROPUESTA_RETENIDA` | `expirar_o_rechazar` | Vencen 48 h o el solicitante rechaza todas. | `PROPUESTA_EXPIRADA` | Libera todas las fechas retenidas en `BloqueoAgenda` (`LIBERADO`). |
| **T-1.4** | `EN_REVISION` | `expirar_por_fecha` | `now() > fecha_estimada` sin aprobación (`Celery Beat`). | `EXPIRADA_POR_FECHA` | Cierra solicitud vencida sin bloquear agenda. |
| **T-1.5** | `EN_REVISION` | `rechazar_solicitud` | Admin rechaza la cotización. | `RECHAZADA` | Libera retención si provenía de `T-1.2` y notifica al solicitante. |
| **T-1.6** | `EN_REVISION` | `aprobar_cotizacion` | Agenda libre en `AgendaService` para fechas solicitadas/elegidas. | `PRE_RESERVADO` | Guarda *snapshot* de configuración, evalúa umbral `> 30 días` (`50/50`) vs `<= 30 días` (`100%`), fija `pre_reserva_expira_en = +48 h` y bloquea `BloqueoAgenda`. |
| **T-1.7** | `PRE_RESERVADO` | `webhook_pago_ok` | `now() <= pre_reserva_expira_en`. | `CONFIRMADO` | Registra pago (`ANTICIPO_50_PAGADO` o `LIQUIDADO_100`), consolida `BloqueoAgenda`, crea `Evento` (`PENDIENTE_PUBLICACION` u `OPERACION_SIN_CARTELERA` si es `Privado`) y sus `Funciones` iniciales. |
| **T-1.8** | `PRE_RESERVADO` | `expirar_prereserva` | `now() > pre_reserva_expira_en` sin pago acreditado. | `EXPIRADA_SIN_PAGO` | Libera `BloqueoAgenda` (`LIBERADO`) y marca intento/ficha caducada. |
| **T-1.9** | `EXPIRADA_SIN_PAGO` | `webhook_pago_tardio` | Pago confirmado tras 48 h y fecha aún libre (`ExclusionConstraint`). | `PAGO_EXTEMPORANEO_EN_REVISION` | Re-retiene bloque por `72 h` (`revision_extemporanea_expira_en`) y alerta al Admin. |
| **T-1.10** | `EXPIRADA_SIN_PAGO` | `webhook_pago_tardio` | Pago confirmado tras 48 h y fecha ya ocupada (`IntegrityError`). | `EXPIRADA_SIN_PAGO` | Devolución íntegra del 100%: si fue **tarjeta**, ejecuta `Refund` vía Stripe API; si fue **ficha SPEI/efectivo**, marca `REEMBOLSO_BANCARIO_PENDIENTE` con alerta al Admin. |
| **T-1.11** | `PAGO_EXTEMPORANEO_EN_REVISION` | `aceptar_extemporaneo` | Admin acepta dentro de 72 h. | `CONFIRMADO` | Consolida `BloqueoAgenda`, registra `ANTICIPO_50_PAGADO`/`LIQUIDADO_100` y crea `Evento`. |
| **T-1.12** | `PAGO_EXTEMPORANEO_EN_REVISION` | `rechazar_o_expirar_72h` | Admin rechaza o `now() > revision_extemporanea_expira_en`. | `EXPIRADA_SIN_PAGO` | Libera `BloqueoAgenda` y devuelve 100%: **tarjeta** -> `Refund` Stripe; **ficha SPEI/efectivo** -> `REEMBOLSO_BANCARIO_PENDIENTE`. |
| **T-1.13** | `CONFIRMADO` | `acreditar_saldo_50` | `esquema == 50/50`, `now() <= D-21 23:59:59` (sin fichas en últimas 48 h). | `CONFIRMADO` | Actualiza `estado_liquidacion = LIQUIDADO_100` y audita el pago. |
| **T-1.14** | `CONFIRMADO` | `reprogramar` | Nueva fecha libre; si pide cliente: `>= 21 d` y 1ra vez gratis (si queda `< 21 d` con `ANTICIPO_50_PAGADO`, exige liquidar 100% previo). | `CONFIRMADO` | Operación atómica en `AgendaService` (libera bloque previo y crea nuevo), recalcula `D-21` y `fecha_limite_publicacion`, conserva boletos y marca `REPROGRAMADO` en `Función`. |
| **T-1.15** | `CONFIRMADO` | `cancelar_arrendatario` / `incumplir_saldo_d21` | Solicitud cliente + Admin, o `50/50` sin saldo tras `D-21 23:59:59`. | `CANCELADO_POR_ARRENDATARIO` | Calcula retención (50% si pagó 100% y `>= 21 d`; 0% reembolso si `< 21 d` o solo anticipo), detiene venta, invalida QRs, conserva historial; agenda se libera solo por acción explícita de Admin. Si llega 2do 50% tardío post `D-21`, devuelve 100% (Stripe o `REEMBOLSO_BANCARIO_PENDIENTE`). |
| **T-1.16** | `CONFIRMADO` | `cancelar_teatro` | Admin declara cancelación por Teatro o fuerza mayor. | `CANCELADO_POR_TEATRO` | 100% reembolso externo o reprogramación sin costo; detiene venta, invalida QRs y conserva padrón para devoluciones manuales. |
| **T-1.17** | `CONFIRMADO` | `finalizar_arrendamiento` | Concluyen todas las fechas/funciones del evento. | `FINALIZADO` | Cierra ciclo operativo del arrendamiento. |

## **3. ME-02 — Máquina de Estados de Evento y Función**

### **3.1 Separación de Niveles (Evento vs. Función)**

* Un **Evento** gobierna la visibilidad en cartelera y los requisitos previos de publicación (`PENDIENTE_PUBLICACION`, `PUBLICADO`, `VENCIDO_SIN_PUBLICAR`, `OPERACION_SIN_CARTELERA`, `CANCELADO_POR_ARRENDATARIO`, `CANCELADO_POR_TEATRO`, `FINALIZADO`). Los eventos `Privado` nacen directamente en `OPERACION_SIN_CARTELERA`. Para `Comercial` y `Público`, la fecha límite determinista se calcula como `fecha_limite_publicacion = min(inicio_primer_bloque_reservado, max(primera_fecha - 15 días naturales, fecha_pago + 3 días naturales))`.
* Cada **Función** (`1 Evento -> 1..N Funciones`) mantiene únicamente estados administrativos (`PROGRAMADA`, `REPROGRAMADO`, `CANCELADA`, `CONCLUIDA`) e intervalos `inicio_en`/`fin_en` en UTC (soportando cruce de medianoche cuando `hora_fin <= hora_inicio`). Las ventanas operativas de venta web (`< inicio_en - 30 min`), taquilla física (`< inicio_en - 0 min`) y acceso QR (`[inicio_en - 2h, fin_en]`) se evalúan **determinísticamente por timestamp** en `services.py` bajo `America/Mexico_City`, evitando colisiones entre ventanas ortogonales o desfases de tareas periódicas.

### **3.2 Diagrama de Estados (PlantUML)**

* **Diagrama fuente:** [ME-02 — Evento y Función (`me02-evento-funcion.puml`)](./maquinas-de-estado/me02-evento-funcion.puml)

### **3.3 Matriz de Transiciones Clave (ME-02)**

| ID | Ámbito | Estado Origen | Disparador / Guarda | Estado Destino | Efectos Secundarios |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **T-2.1** | Evento | `[*]` | Arrendamiento `CONFIRMADO` o Evento Directo (`Comercial` / `Público`). | `PENDIENTE_PUBLICACION` | Calcula `fecha_limite_publicacion`, programa recordatorios (3 d y cada 7 d) y crea `Funciones` iniciales. |
| **T-2.2** | Evento | `[*]` | Arrendamiento `CONFIRMADO` o Evento Directo en modalidad `Privado`. | `OPERACION_SIN_CARTELERA` | Exento de póster, tarifas y cartelera pública; mantiene bloqueo en agenda. |
| **T-2.3** | Evento | `PENDIENTE_PUBLICACION` | Póster cargado (+ tarifas `>= $100.00 MXN` si `Comercial`) + aprobación final de `ADMIN` (`<= fecha_limite_publicacion`). | `PUBLICADO` | Visible en cartelera; si es `Comercial`, congela secciones del evento, fases de venta y tarifas y ejecuta `bulk_create(..., batch_size=1728)` de `DisponibilidadButaca` por función. |
| **T-2.4** | Evento | `PENDIENTE_PUBLICACION` | `now() > fecha_limite_publicacion` sin requisitos completos (`Celery Beat`). | `VENCIDO_SIN_PUBLICAR` | Mantiene bloqueo en agenda (nunca libera automático) y exige resolución auditada del `ADMIN`. |
| **T-2.5** | Evento | `VENCIDO_SIN_PUBLICAR` | Admin apoya capturando póster/tarifas (opción 1) o concede prórroga (opción 2) y aprueba. | `PUBLICADO` | Publica evento y materializa `DisponibilidadButaca` si es `Comercial`. |
| **T-2.6** | Evento | `VENCIDO_SIN_PUBLICAR` | Admin autoriza operar sin venta web ni cartelera (opción 3). | `OPERACION_SIN_CARTELERA` | Conserva bloqueo en agenda para operación presencial sin venta en línea. |
| **T-2.7** | Evento | `VENCIDO_SIN_PUBLICAR` / `PENDIENTE_PUBLICACION` / `PUBLICADO` / `OPERACION_SIN_CARTELERA` | Admin registra cancelación (opción 4, arrendatario, D-21 o Teatro). | `CANCELADO_POR_ARRENDATARIO` / `CANCELADO_POR_TEATRO` | Detiene venta, invalida QRs emitidos, conserva historial; libera agenda explícitamente (o sin retención en Directos). |
| **T-2.8** | Evento | `PUBLICADO` / `OPERACION_SIN_CARTELERA` | Todas sus `Funciones` alcanzan `CONCLUIDA`. | `FINALIZADO` | Cierra ciclo de cartelera/operación del evento. |
| **T-2.9** | Función | `PROGRAMADA` | Admin reprograma fecha u hora (con o sin boletos vendidos). | `REPROGRAMADO` | Operación atómica en `AgendaService`, guarda `inicio_en_anterior`/`fin_en_anterior`, conserva `Evento` en `PUBLICADO` y boletos/QRs vigentes, y notifica a cuentas registradas. |
| **T-2.10** | Función | `PROGRAMADA` / `REPROGRAMADO` | `now() > fin_en` (o evento cancelado). | `CONCLUIDA` / `CANCELADA` | Cierra ventanas operativas de la función. |

## **4. ME-03 — Máquina de Estados de Orden de Compra (`OrdenCompra`)**

### **4.1 Reglas de Diseño**

* **Un solo carrito activo por usuario y por función (`5` estados oficiales):** `OrdenCompra` maneja exclusivamente los estados `APARTADO`, `PAGO_EN_PROCESO`, `PAGADA`, `EXPIRADA` y `REEMBOLSADA_AUTOMATICA`. Al seleccionar la primera butaca disponible se crea la orden en `APARTADO` y arranca un reloj único de 10 minutos (`expira_en`; agregar más butacas dentro de `<= 10` no reinicia el reloj). En línea exige cuenta `USUARIO`; en taquilla (`CAJERO`) opera sin cuenta de comprador hasta `inicio_en` (`0 min`).
* **Cierres independientes y pagos tardíos:** Al llegar el cierre web (`inicio_en - 30 min`), las órdenes aún en `APARTADO` no pueden iniciar `checkout` y expiran; solo continúan en gracia (`gracia_hasta = +5 min`) las ya en `PAGO_EN_PROCESO`. Si un *webhook* `payment_intent.succeeded` llega tras pasar a `EXPIRADA`, bajo el candado global `Usuario -> OrdenCompra -> DisponibilidadButaca` se verifica que la función siga vigente (`now() <= fin_en`, no cancelada), que el 100% de las butacas sigan `DISPONIBLE` y que reasignar no supere `<= 10` boletos acumulados (`APARTADO + PAGO_EN_PROCESO + PAGADA`); de lo contrario, se ejecuta reembolso automático del 100% (`REEMBOLSADA_AUTOMATICA`). Ante cancelación del evento, `OrdenCompra` permanece en `PAGADA` para respaldo contable.

### **4.2 Diagrama de Estados (PlantUML)**

* **Diagrama fuente:** [ME-03 — Orden de Compra (`me03-orden-compra.puml`)](./maquinas-de-estado/me03-orden-compra.puml)

### **4.3 Matriz de Transiciones y Guardas (ME-03)**

| ID | Estado Origen | Evento / Disparador | Condición Guarda | Estado Destino | Efectos Secundarios |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **T-3.1** | `[*]` | `agregar_primera_butaca` | Evento `Comercial` en `PUBLICADO`; ventana vigente (`LINEA`: `now() < inicio_en - 30m`; `TAQUILLA`: `now() < inicio_en`); butaca `DISPONIBLE`; `<= 10` boletos acumulados (`LINEA`) o por operación (`TAQUILLA`). | `APARTADO` | Bloquea `Usuario -> OrdenCompra -> DisponibilidadButaca`, fija `expira_en = now() + 10 min` y cambia butaca a `APARTADA`. Si el usuario tenía otra orden `APARTADO` en otra función, la pasa a `EXPIRADA` liberando sus butacas. |
| **T-3.2** | `APARTADO` | `modificar_butacas` | Misma función, `now() <= expira_en`, cierre vigente y total `<= 10`. | `APARTADO` | Agrega o libera butacas sin reiniciar `expira_en`. |
| **T-3.3** | `APARTADO` | `iniciar_checkout` | Canal `LINEA`, `now() <= expira_en`, `now() < inicio_en - 30m` y `>= 1` butaca. | `PAGO_EN_PROCESO` | Fija `gracia_hasta = expira_en + 5 min` y crea/reutiliza `PaymentIntent` en Stripe fuera del lock BD. |
| **T-3.4** | `APARTADO` | `confirmar_cobro_taquilla` | Canal `TAQUILLA` (`CAJERO`), `now() <= expira_en`, `now() < inicio_en`, cobro `Efectivo` o `Tarjeta` externa. | `PAGADA` | Cambia butacas a `VENDIDA`, emite folios cortos y códigos QR firmados. |
| **T-3.5** | `PAGO_EN_PROCESO` | `confirmar_pago_stripe` | Webhook `payment_intent.succeeded` con `now() <= gracia_hasta`. | `PAGADA` | Cambia butacas a `VENDIDA`, emite folios cortos + QR y encola correo PDF. |
| **T-3.6** | `APARTADO` / `PAGO_EN_PROCESO` | `expirar_o_cancelar_orden` | `now() > limite_vigencia` (10 min o `gracia_hasta`), cierre web `-30m` sobre `APARTADO`, carrito vaciado o Cajero cancela. | `EXPIRADA` | Libera butacas a `DISPONIBLE` y cancela `PaymentIntent` en Stripe si existía. |
| **T-3.7** | `EXPIRADA` | `webhook_tardio_valido` | `payment_intent.succeeded` tardío, `now() <= fin_en`, función no cancelada, 100% butacas `DISPONIBLE` y suma acumulada `<= 10`. | `PAGADA` | Bloquea `Usuario -> OrdenCompra -> DisponibilidadButaca`, pasa butacas a `VENDIDA`, emite boletos QR y envía correo. |
| **T-3.8** | `EXPIRADA` | `webhook_tardio_rechazado` | `payment_intent.succeeded` tardío y (`>= 1` butaca no `DISPONIBLE` o suma `> 10` o función cerrada/cancelada). | `REEMBOLSADA_AUTOMATICA` | Ejecuta `stripe.Refund.create()` por el 100% del monto, audita y notifica por correo. |

## **5. ME-04 — Máquina de Estados de `DisponibilidadButaca` y Boleto QR**

### **5.1 Matriz de Transiciones (`DisponibilidadButaca` y `Boleto`)**

* **Diagrama fuente:** [ME-04 — DisponibilidadButaca y Boleto QR (`me04-butaca-qr.puml`)](./maquinas-de-estado/me04-butaca-qr.puml)

| ID | Entidad | Estado Origen | Disparador / Guarda | Estado Destino | Efectos Secundarios |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **T-4.1** | `DisponibilidadButaca` | `[*]` | Evento `Comercial` pasa a `PUBLICADO` (o nueva función añadida). | `DISPONIBLE` | `bulk_create(..., batch_size=1728)` por cada función. |
| **T-4.2** | `DisponibilidadButaca` | `DISPONIBLE` | Selección en Web o Taquilla (`OrdenCompra` `APARTADO`). | `APARTADA` | Enlaza a `OrdenCompra` con `expira_en`. |
| **T-4.3** | `DisponibilidadButaca` | `APARTADA` | `OrdenCompra` `EXPIRADA` o `PAGADA`. | `DISPONIBLE` / `VENDIDA` | Libera o consolida venta y emite `Boleto` en `EMITIDO`. |
| **T-4.4** | `DisponibilidadButaca` | `DISPONIBLE` <-> `BLOQUEO_TECNICO` | `ADMIN` aplica o retira bloqueo técnico previo al cierre de taquilla. | `BLOQUEO_TECNICO` / `DISPONIBLE` | Inhabilita o restaura localidad sin emitir boleto ni QR; auditado. |
| **T-4.5** | `DisponibilidadButaca` | `DISPONIBLE` | **Exclusivo `ADMIN`** emite cortesía (`$0.00 MXN`, sin cuenta, exento `<= 10`). | `CORTESIA` | Emite `Boleto` en `EMITIDO` con QR válido y beneficiario/motivo opcional. |
| **T-4.6** | `DisponibilidadButaca` | `CORTESIA` | `ADMIN` revoca cortesía antes del ingreso. | `DISPONIBLE` | Cambia `Boleto` asociado a `INVALIDADO` y libera localidad. |
| **T-4.7** | `Boleto` | `EMITIDO` | Escaneo QR o folio manual válido en `[inicio_en - 2h, fin_en]`. | `USADO` | Registra `usado_en` y `validado_por` atómicamente. |
| **T-4.8** | `Boleto` | `EMITIDO` | Reconciliación en lote (`Admin`) tras modo contingencia, o cancelación/D-21/revocación. | `USADO_CONTINGENCIA` / `INVALIDADO` | Marca ingreso en contingencia o invalida QR conservando registro. |

### **5.2 Tabla de Verdad del Escáner QR en Puerta (`POST /api/v1/boletos/validar/`)**

Al leer un código QR (`{token}`), el sistema valida la firma `HMAC-SHA256` (`QR_HMAC_SECRET`) y resuelve el `funcion_id` embebido en el token. Si el Verificador o Admin seleccionó una función en la pantalla de cámara, adjunta `funcion_id` al token para comprobar la correspondencia. En el respaldo manual, `{folio_corto, funcion_id}` son obligatorios. En ambos casos la ventana horaria se evalúa sobre la función del boleto. La evaluación sigue este orden estricto:

| Orden | Condición Evaluada | HTTP | Estado resultante del QR | Mensaje mostrado al Verificador | ¿Consume QR? |
| :---- | :--- | :---: | :--- | :--- | :--- |
| **1** | Entrada o firma inválida (`400`), boleto o folio inexistente (`404`) | `400`/`404` | Sin cambio | `"Boleto no válido"` | No |
| **2** | `boleto.estado == INVALIDADO` o función/evento cancelado | `400` | Sin cambio | `"Boleto no válido"` | No |
| **3** | `boleto.estado IN (USADO, USADO_CONTINGENCIA)` o `usado_en IS NOT NULL` | `409` | Sin cambio | `"Ya ingresó a las HH:MM"` | No |
| **4** | Respaldo manual o contexto con `funcion_id` activa distinta al boleto | `409` | Sin cambio | `"Boleto de la función DD/MM HH:MM"` | No |
| **5** | `now() < funcion.inicio_en - 2 horas` | `422` | Sin cambio | `"Abre a las HH:MM"` | No |
| **6** | `now() > funcion.fin_en` | `422` | Sin cambio | `"La función ya terminó"` | No |
| **7** | `boleto.estado == EMITIDO` y `now()` en `[inicio_en - 2h, fin_en]` | `200` | **`USADO`** | `"Acceso permitido"` + Sección, Fila y Asiento | **Sí** (atómico) |

## **6. Protocolo de Concurrencia, Idempotencia y Tareas Asíncronas**

### **6.1 Resolución de Condiciones de Carrera (*Race Conditions*)**

| Escenario de Colisión | Mecanismo en PostgreSQL / Aplicación | Comportamiento Determinista |
| :--- | :--- | :--- |
| **1. Compras paralelas y límite `<= 10` por usuario/función** | Jerarquía global de candados: `Usuario -> OrdenCompra -> DisponibilidadButaca (funcion_id, butaca_id ASC) -> Boleto` con `select_for_update(nowait=True)` + `UNIQUE (funcion_id, butaca_id)`. | El primer hilo adquiere el candado y aparta la butaca; cualquier colisión simultánea retorna inmediatamente `409 Conflict` sin *deadlocks* ni evasión `6 + 6 = 12`. |
| **2. Dos cotizaciones compiten por la misma fecha/turno** | `AgendaService` (`nowait=True`) + `ExclusionConstraint` (`btree_gist`) sobre `(rango_tiempo WITH &&)` donde `estado != 'LIBERADO'`. | PostgreSQL rechaza físicamente cualquier traslape concurrente, traduciendo `IntegrityError` a `409 Conflict` (o a reembolso `T-1.10` en pago tardío). |
| **3. *Webhook* de Stripe llega al expirar el carrito** | Bloqueo pesimista siguiendo la jerarquía `Usuario -> OrdenCompra -> DisponibilidadButaca` antes de leer o cambiar estado. | Solo uno ejecuta primero: si Celery Beat (`skip_locked=True`) expiró antes, el *webhook* ejecuta `T-3.7` (reasignar) o `T-3.8` (reembolsar 100%); si el *webhook* llega antes, Celery ve `PAGADA`. |
| **4. Reprogramación de fecha de un evento confirmado** | Transacción única (`transaction.atomic()`): `select_for_update()` sobre el `BloqueoAgenda` origen, lo cambia a **`LIBERADO` antes** de insertar el nuevo bloque (o usa `Deferrable.DEFERRED`). | Evita auto-colisión con `ExclusionConstraint`; si el nuevo rango choca con terceros, hace *rollback* automático intacto. |
| **5. Dos verificadores escanean el mismo boleto QR al mismo tiempo** | `SELECT ... FOR UPDATE OF boleto NOWAIT` dentro de `transaction.atomic()` (sin bloquear `Función`) verificando `usado_en IS NULL` y `estado == 'EMITIDO'`. | Exactamente un escáner marca `estado = 'USADO'`, `usado_en = now()` y `validado_por = user` (`200 OK`); el segundo recibe `409 Conflict` (`"Ya ingresó a las HH:MM"`). |

### **6.2 Idempotencia en *Webhooks* de Stripe**

* Todo *webhook* recibido en `/api/v1/ventas/webhooks/stripe/` valida primero la firma `Stripe-Signature` (`STRIPE_WEBHOOK_SECRET`).
* Dentro de `transaction.atomic()`, inserta `event.id` en `stripe_webhook_events` (`stripe_event_id VARCHAR(120) PRIMARY KEY`, `estado = 'PENDIENTE'`, `modulo = metadata.modulo`) y encola la tarea asíncrona de Celery (`acks_late=True`) únicamente dentro de `transaction.on_commit()`.
* Si el `INSERT` falla por llave duplicada (`IntegrityError`), responde `HTTP 200 OK` sin reprocesar; si Redis falla antes de encolar, retorna `HTTP 500` para que Stripe reintente.

#### **Estados de `Transaccion` y `PagoArrendamiento`**

Además del estado de idempotencia del *webhook* (`PENDIENTE`, `PROCESADO`, `FALLIDO` en `stripe_webhook_events`), las entidades financieras derivadas de los flujos de **ME-01** y **ME-03** siguen estos estados oficiales:

* **`Transaccion` (`EstadoTransaccion`, módulo `ventas`):**
  * `PENDIENTE`: `PaymentIntent` creado (tarjeta) o ficha SPEI/efectivo emitida; aguardando confirmación de Stripe.
  * `ACREDITADA`: Confirmada por *webhook* `payment_intent.succeeded`.
  * `FALLIDA`: Rechazada por *webhook* `payment_intent.payment_failed` (reintentable dentro de la ventana vigente).
  * `CANCELADA`: Cancelada explícitamente en Stripe al expirar `OrdenCompra` (`expirar_carritos_boletos`) o `PRE_RESERVADO` (`expirar_retenciones_agenda`).
  * `REEMBOLSADA`: Reembolso técnico automático del 100% ejecutado vía Stripe API (`Refund` / `charge.refunded`) por pago tardío con tarjeta fuera de ventana o sin disponibilidad.
* **`PagoArrendamiento` (`EstadoPagoArrendamiento`, módulo `cotizaciones`):**
  * `PENDIENTE`: Cuota generada (`ANTICIPO_50`, `SALDO_50` o `LIQUIDACION_100`) dentro de plazo (`48 h` en `PRE_RESERVADO` o hasta `D-21 23:59:59`).
  * `ACREDITADO`: Pago validado y aplicado a la cotización (`ANTICIPO_50_PAGADO` o `LIQUIDADO_100`).
  * `EN_REVISION_EXTEMPORANEA`: Pago acreditado tras vencer `48 h` con fecha aún libre (`PAGO_EXTEMPORANEO_EN_REVISION`, plazo `72 h` del Admin).
  * `VENCIDO`: Plazo expirado sin acreditación (`EXPIRADA_SIN_PAGO` o incumplimiento `D-21`).
  * `REEMBOLSADO`: Devuelto al 100% vía Stripe API (tarjeta fuera de ventana o rechazada por Admin).
  * `REEMBOLSO_BANCARIO_PENDIENTE`: Ficha SPEI/efectivo acreditada fuera de ventana o tras `D-21`, pendiente de devolución bancaria externa por Admin.

### **6.3 Catálogo de Tareas Periódicas (Celery Beat)**

Todas las tareas consultan columnas `TIMESTAMPTZ` persistidas en BD bajo `America/Mexico_City` y bloquean lotes con `select_for_update(skip_locked=True)` para no competir con peticiones HTTP:

| Tarea Programada | Frecuencia | Consulta / Condición de Disparo | Acción Ejecutada |
| :--- | :--- | :--- | :--- |
| `expirar_carritos_boletos` | Cada 30 seg | Órdenes en `APARTADO` con `now() > expira_en` o en `PAGO_EN_PROCESO` con `now() > gracia_hasta`. | Pasa orden a `EXPIRADA`, libera butacas y cancela `PaymentIntent` en Stripe. |
| `expirar_retenciones_agenda` | Cada 5 min | Cotizaciones en `PROPUESTA_RETENIDA` o `PRE_RESERVADO` (`now() > pre_reserva_expira_en` / `propuesta_expira_en`). | Pasa a `PROPUESTA_EXPIRADA` o `EXPIRADA_SIN_PAGO` y libera `BloqueoAgenda`. |
| `expirar_revision_extemporanea` | Cada 15 min | Cotizaciones en `PAGO_EXTEMPORANEO_EN_REVISION` con `now() > revision_extemporanea_expira_en` (72 h). | Libera `BloqueoAgenda` y dispara devolución 100% (Stripe `Refund` o `REEMBOLSO_BANCARIO_PENDIENTE`). |
| `verificar_limite_publicacion` | Cada 1 hora | Eventos en `PENDIENTE_PUBLICACION` con `now() > fecha_limite_publicacion`. | Transiciona evento a `VENCIDO_SIN_PUBLICAR` (sin liberar agenda) y genera alerta al Admin. |
| `enviar_recordatorios_requisitos` | Diario 09:00 | Eventos en `PENDIENTE_PUBLICACION` con `now() >= proximo_recordatorio_en` (3 d y cada 7 d). | Encola correo de recordatorio y actualiza `proximo_recordatorio_en` (alerta al Admin en día 3). |
| `verificar_incumplimiento_saldo` | Diario 00:05 | Cotizaciones `CONFIRMADO` (`50/50`) sin liquidar donde pasó `D-21 23:59:59`. | Cancela arrendamiento/evento (`CANCELADO_POR_ARRENDATARIO`), detiene venta, invalida QRs y alerta al Admin (sin liberar agenda automáticamente si hay boletos). |
| `actualizar_sla_cotizaciones` | Cada 1 hora | Cotizaciones `EN_REVISION` con `> 5 días hábiles` (L–V `America/Mexico_City`) o fecha estimada vencida. | Marca `atrasada = True` o transiciona a `EXPIRADA_POR_FECHA`. |

## **7. Guía de Implementación (*Domain Services*)**

Queda prohibido dispersar transiciones o validaciones de estado en `views.py`. Cada transición se encapsula en servicios de dominio siguiendo el orden global de bloqueos y leyendo los parámetros desde `ConfiguracionService` (creando o reutilizando el `PaymentIntent` de Stripe fuera del bloqueo de BD):

```python
from datetime import timedelta

from django.db import transaction
from django.utils import timezone


class TransicionEstadoInvalida(Exception):
    pass


class OrdenCompraService:
    @staticmethod
    def iniciar_proceso_pago(orden_id: int, usuario_id: int, pago_gateway):
        from apps.configuracion.services import ConfiguracionService
        from apps.usuarios.models import Usuario
        from apps.ventas.models import OrdenCompra

        config = ConfiguracionService.obtener_vigente()
        ahora = timezone.now()

        with transaction.atomic():
            # Jerarquía global obligatoria: Usuario -> OrdenCompra (nowait=True -> 409 en colisión)
            Usuario.objects.select_for_update(nowait=True).get(pk=usuario_id)
            orden = (
                OrdenCompra.objects.select_for_update(nowait=True)
                .select_related("funcion")
                .get(pk=orden_id, usuario_id=usuario_id)
            )

            if orden.estado != "APARTADO":
                raise TransicionEstadoInvalida(
                    f"No se puede iniciar pago desde el estado {orden.estado}."
                )

            cierre_web = orden.funcion.inicio_en - timedelta(minutes=config.cierre_web_min)
            if ahora >= cierre_web:
                raise TransicionEstadoInvalida("La venta en línea para esta función ha cerrado.")

            if ahora > orden.expira_en:
                raise TransicionEstadoInvalida("El tiempo de apartado de 10 minutos ha expirado.")

            orden.estado = "PAGO_EN_PROCESO"
            orden.gracia_hasta = orden.expira_en + timedelta(minutes=config.gracia_pago_min)
            orden.save(update_fields=["estado", "gracia_hasta", "actualizado_en"])

        # Llamada HTTP externa a Stripe fuera de select_for_update()
        client_secret, payment_intent_id = pago_gateway.crear_o_reutilizar_intent(orden)
        OrdenCompra.objects.filter(pk=orden.pk).update(payment_intent_id=payment_intent_id)
        return orden, client_secret
```
