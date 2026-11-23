# **Especificación de Máquinas de Estado y Concurrencia**

* **Proyecto:** Plataforma de Boletaje en Línea y Cotización de Arrendamiento — Teatro de la Ciudad de Coatzacoalcos
* **Responsable Técnico:** José Manuel Fabian Hernández
* **Versión:** 1.0 (Línea Base de Comportamiento)
* **Zona Horaria Oficial:** America/Mexico\_City
* **Estándares y Patrones Aplicados:** UML 2.5 State Machines, Patrón *State* / *Domain Services*, Separación de Responsabilidades (SoC), Idempotencia y Control de Concurrencia Pesimista.

## **Índice de Diagramas PlantUML**

| Código | Máquina de Estados | Archivo de Diagrama |
| :---- | :---- | :---- |
| **ME-01** | Cotización y Arrendamiento | [me01-cotizacion-arrendamiento.puml](./maquinas-de-estado/me01-cotizacion-arrendamiento.puml) |
| **ME-02** | Evento y Función | [me02-evento-funcion.puml](./maquinas-de-estado/me02-evento-funcion.puml) |
| **ME-03** | Orden de Compra (Boletaje) | [me03-orden-compra.puml](./maquinas-de-estado/me03-orden-compra.puml) |
| **ME-04** | Butaca por Función y Boleto QR | [me04-butaca-qr.puml](./maquinas-de-estado/me04-butaca-qr.puml) |

## **1. Propósito y Reglas Arquitectónicas de Transición**

* **El "qué":** Define los estados finitos, eventos disparadores, condiciones guarda y efectos secundarios de las cuatro entidades transaccionales críticas del sistema (**Cotización/Arrendamiento**, **Evento/Función**, **Orden de Compra** y **Butaca/Boleto QR**), junto con los mecanismos para resolver condiciones de carrera (*race conditions*).
* **El "cómo":** Ningún controlador HTTP (ViewSet), tarea de Celery ni *webhook* de Stripe puede modificar directamente el campo estado mediante asignaciones crudas (`obj.estado = ...`). Toda transición debe invocarse a través de métodos explícitos en la capa de servicios (Domain Services) dentro de bloques transaccionales atómicos (`transaction.atomic()`), registrando cada cambio en la bitácora inmutable de auditoría (`AuditoriaService`).
* **El "por qué" (Prevención de deuda técnica):** Desacopla las reglas temporales y de pago de la interfaz web y evita que procesos concurrentes (dos compradores, el reloj de expiración de Celery y notificaciones asíncronas de Stripe) corrompan el inventario de $1,728$ butacas o provoquen dobles reservas de agenda.

## **2. ME-01 — Máquina de Estados de Cotización y Arrendamiento**

### **2.1 Reglas de Diseño del Ciclo de Vida**

* **Bloqueo temprano de agenda:** Los estados `PROPUESTA_RETENIDA`, `PRE_RESERVADO` y `CONFIRMADO` ocupan activamente los rangos de fecha/turno en agenda mediante la restricción `ExclusionConstraint` en PostgreSQL (`btree_gist`), impidiendo traslapes entre solicitudes.
* **Sub-estado financiero en CONFIRMADO:** Al aprobar la cotización, el sistema congela como *snapshot* el esquema aplicable según los días naturales entre la aprobación y la primera fecha reservada ($\geq 28\text{ días}$ permite 50/50; $< 28\text{ días}$ exige 100%). Dentro de `CONFIRMADO`, un atributo secundario (`estado_liquidacion`: `ANTICIPO_50_PAGADO | LIQUIDADO_100`) controla el cobro del saldo pendiente antes de las 23:59:59 del día $D-21$.

### **2.2 Diagrama de Estados (PlantUML)**

* **Diagrama fuente:** [ME-01 — Cotización y Arrendamiento (`me01-cotizacion-arrendamiento.puml`)](./maquinas-de-estado/me01-cotizacion-arrendamiento.puml)

### **2.3 Matriz de Transiciones y Guardas (ME-01)**

| ID | Estado Origen | Evento / Disparador | Condición Guarda | Estado Destino | Efectos Secundarios y Auditoría |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **T-1.1** | `EN_REVISION` | `proponer_fechas_alt` | $\leq 3$ opciones libres en agenda. | `PROPUESTA_RETENIDA` | Inserta bloqueos temporales en agenda por 48 h naturales y notifica por correo al solicitante. |
| **T-1.2** | `PROPUESTA_RETENIDA` | `aceptar_alternativa` | Dentro de 48 h y la opción elegida sigue retenida. | `EN_REVISION` | Libera las opciones no elegidas; mantiene retenida la elegida hasta que Admin confirme tarifa oficial. |
| **T-1.3** | `PROPUESTA_RETENIDA` | `expirar_o_rechazar` | Vencen 48 h o el solicitante rechaza todas. | `PROPUESTA_EXPIRADA` | Libera todas las fechas retenidas en agenda. |
| **T-1.4** | `EN_REVISION` | `aprobar_cotizacion` | Agenda libre para las fechas solicitadas/elegidas. | `PRE_RESERVADO` | Guarda *snapshot* de configuración, evalúa umbral de 28 días (50/50 vs 100%) e inicia reloj de 48 h para pago. |
| **T-1.5** | `PRE_RESERVADO` | `webhook_pago_ok` | `now() <= pre_reserva_expira_en`. | `CONFIRMADO` | Registra pago (`ANTICIPO_50_PAGADO` o `LIQUIDADO_100`), consolida bloqueo en agenda y crea Evento en `PENDIENTE_PUBLICACION`. |
| **T-1.6** | `PRE_RESERVADO` | `expirar_prereserva` | `now() > pre_reserva_expira_en` sin pago acreditado. | `EXPIRADA_SIN_PAGO` | Libera bloqueo de agenda y marca ficha/intento como caducado. |
| **T-1.7** | `EXPIRADA_SIN_PAGO` | `webhook_pago_tardio` | Pago confirmado tras expirar 48 h y fecha sigue libre. | `PAGO_EXTEMPORANEO_EN_REVISION` | Re-retiene fecha por 72 h y alerta al Admin para decidir aceptación o reembolso íntegro. |
| **T-1.8** | `EXPIRADA_SIN_PAGO` | `webhook_pago_tardio` | Pago confirmado tras expirar 48 h y fecha ya está ocupada. | `EXPIRADA_SIN_PAGO` | Dispara reembolso automático del \$100\%\$ vía Stripe sin retención y notifica por correo. |
| **T-1.9** | `CONFIRMADO` | `cancelar_arrendatario` | Solicitante lo pide desde panel y Admin lo registra. | `CANCELADO_POR_ARRENDATARIO` | Calcula retención (\$50\%\$ retenido si pagó \$100\%\$ y faltan $\geq 21\text{ d}$; \$0\%\$ reembolso si $< 21\text{ d}$ o solo pagó anticipo). Libera agenda por acción explícita. |
| **T-1.10** | `CONFIRMADO` | `cancelar_teatro` | Admin declara cancelación por Teatro o fuerza mayor. | `CANCELADO_POR_TEATRO` | Detiene venta de boletos, invalida todos los QR emitidos y conserva padrón de compradores para devolución manual. |
| **T-1.11** | `CONFIRMADO` | `reprogramar` | Nueva fecha libre en agenda ($\geq 21\text{ d}$ si pide cliente, o cualquier plazo si es por Teatro). | `REPROGRAMADO` | Operación atómica: reserva nuevo bloque en agenda, libera anterior, conserva boletos/QR vigentes y envía aviso por correo. |
| **T-1.12** | `CONFIRMADO` | `incumplir_saldo_d21` | `esquema == 50/50` y `now() > D-21 23:59:59` sin acreditar saldo. | `CANCELADO_POR_ARRENDATARIO` | Cancela evento, detiene venta si existía, invalida QRs y aplica no reembolsabilidad del anticipo. |

## **3. ME-02 — Máquina de Estados de Evento y Función**

### **3.1 Separación de Niveles (Evento vs. Función)**

* Un **Evento** gobierna la visibilidad en cartelera y los requisitos previos de publicación (póster y tarifas), con fecha límite de 15 días naturales antes de la primera fecha reservada.
* Cada **Función** ($1\text{ Evento} \rightarrow 1..N\text{ Funciones}$) gobierna su propio reloj de venta web (`T_inicio - 30 min`), venta en taquilla (`T_inicio`), acceso QR (`[T_inicio - 2h, T_fin]`) y modo contingencia.

### **3.2 Diagrama de Estados (PlantUML)**

* **Diagrama fuente:** [ME-02 — Evento y Función (`me02-evento-funcion.puml`)](./maquinas-de-estado/me02-evento-funcion.puml)

### **3.3 Matriz de Transiciones Clave (ME-02)**

| ID | Ámbito | Estado Origen | Disparador / Guarda | Estado Destino | Efectos Secundarios |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **T-2.1** | Evento | `PENDIENTE_PUBLICACION` | Carga de póster (y tarifas si es Comercial) antes de D-15. | `PUBLICADO` | Visible en cartelera pública; habilita venta web si es Comercial. |
| **T-2.2** | Evento | `PENDIENTE_PUBLICACION` | `now() > D-15` sin requisitos completos (Celery Beat). | `VENCIDO_SIN_PUBLICAR` | Mantiene bloqueo en agenda (nunca libera automático) y exige resolución auditada del Admin. |
| **T-2.3** | Evento | `VENCIDO_SIN_PUBLICAR` | Admin elige *"Realizar sin venta en línea"* (opción 3). | `OPERACION_SIN_CARTELERA` | Conserva bloqueo en agenda, permite cortesías/acceso físico y bloquea venta en línea. |
| **T-2.4** | Función | `VENTA_ACTIVA` | `now() >= hora_inicio - margen_cierre_web` (30 min por defecto). | `VENTA_WEB_CERRADA` | Bloquea nuevas compras en portal web; permite terminar pagos ya en `PAGO_EN_PROCESO` y mantiene taquilla física abierta. |
| **T-2.5** | Función | `VENTA_WEB_CERRADA` | `now() >= hora_inicio - margen_cierre_taquilla` (0 min por defecto). | `VENTA_CERRADA_TOTAL` | Cierra emisión de boletos en taquilla física; solo permite cortesías si Admin lo autoriza. |

## **4. ME-03 — Máquina de Estados de Orden de Compra (Boletaje)**

### **4.1 Reglas de Diseño**

* **Un solo carrito activo por usuario y por función:** Al seleccionar la primera butaca disponible se crea la orden en estado `APARTADO` y arranca un temporizador único de 10 minutos (agregar más butacas dentro del límite $\leq 10$ no reinicia el reloj).
* **Excepción de pagos fuera de ventana:** Si un *webhook* `payment_intent.succeeded` de Stripe llega después de pasar a `EXPIRADA`, el sistema verifica atómicamente la disponibilidad de todas las butacas de la orden para reasignarlas o ejecutar reembolso técnico automático.

### **4.2 Diagrama de Estados (PlantUML)**

* **Diagrama fuente:** [ME-03 — Orden de Compra (`me03-orden-compra.puml`)](./maquinas-de-estado/me03-orden-compra.puml)

### **4.3 Matriz de Transiciones y Guardas (ME-03)**

| ID | Estado Origen | Evento / Disparador | Condición Guarda | Estado Destino | Efectos Secundarios |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **T-3.1** | `[*]` | `agregar_primera_butaca` | Función en `VENTA_ACTIVA` (web) o `VENTA_WEB_CERRADA` (taquilla); butaca en `DISPONIBLE`. | `APARTADO` | Crea orden, fija `expira_en = now() + 10 min` y cambia butaca a `APARTADA`. Si el usuario tenía otro carrito activo, lo cancela primero. |
| **T-3.2** | `APARTADO` | `iniciar_checkout` | `now() <= expira_en` y $\geq 1$ butaca en carrito. | `PAGO_EN_PROCESO` | Crea `PaymentIntent` en Stripe y extiende `gracia_hasta = expira_en + 5 min`. |
| **T-3.3** | `PAGO_EN_PROCESO` | `confirmar_pago` | Webhook `payment_intent.succeeded` (o cobro efectivo/terminal de Cajero). | `PAGADA` | Cambia butacas a `VENDIDA`, genera folios + códigos QR firmados y encola correo con PDF. |
| **T-3.4** | `APARTADO` / `PAGO_EN_PROCESO` | `expirar_orden` | `now() > limite_vigencia` (10 min o 15 min con gracia). | `EXPIRADA` | Libera butacas a `DISPONIBLE` y solicita cancelación del `PaymentIntent` en Stripe. |
| **T-3.5** | `EXPIRADA` | `webhook_tardio_libre` | `payment_intent.succeeded` tardío y \$100\%$ de las butacas siguen en `DISPONIBLE`. | `PAGADA` | Bloquea butacas con `FOR UPDATE`, las pasa a `VENDIDA`, emite boletos QR y envía correo. |
| **T-3.6** | `EXPIRADA` | `webhook_tardio_ocupado` | `payment_intent.succeeded` tardío y al menos $1$ butaca está en `APARTADA`, `VENDIDA`, `CORTESIA` o `BLOQUEO_TECNICO`. | `REEMBOLSADA_AUTOMATICA` | Ejecuta `stripe.Refund.create()` por el \$100\%$ del monto y notifica al comprador por correo. |

## **5. ME-04 — Máquina de Estados de Butaca por Función y Boleto QR**

### **5.1 Estados de Inventario por Butaca ($1..1,728$ en cada Función) y Boleto QR**

* **Diagrama fuente:** [ME-04 — Butaca por Función y Boleto QR (`me04-butaca-qr.puml`)](./maquinas-de-estado/me04-butaca-qr.puml)

### **5.2 Tabla de Verdad del Escáner QR en Puerta (Verificador)**

Al leer un código QR, el sistema resuelve el `funcion_id` embebido en el token firmado (sin depender de una selección manual de función activa) y evalúa las reglas en el siguiente orden estricto:

| Orden | Condición Evaluada | Estado resultante del QR | Mensaje mostrado al Verificador | ¿Consume QR? |
| :---- | :---- | :---- | :---- | :---- |
| **1** | Firma criptográfica inválida o folio inexistente | Sin cambio | "Boleto no válido" | No |
| **2** | `boleto.estado == INVALIDADO` o función cancelada | `INVALIDADO` | "Boleto no válido" | No |
| **3** | `boleto.estado IN (USADO, USADO_CONTINGENCIA)` | Sin cambio | "Ya ingresó a las HH:MM" | No |
| **4** | El QR pertenece a una función de otra fecha/horario distinto al turno en curso | `EMITIDO` | "Boleto de la función DD/MM HH:MM" | No |
| **5** | `now() < funcion.hora_inicio - 2 horas` | `EMITIDO` | "Abre a las HH:MM" | No |
| **6** | `now() > funcion.hora_fin` | `EMITIDO` | "La función ya terminó" | No |
| **7** | `boleto.estado == EMITIDO` y `now()` $\in$ `[hora_inicio - 2h, hora_fin]` | **`USADO`** | **"Acceso permitido"** + Sub-sección, Fila y Asiento | **Sí** (atómico) |

## **6. Protocolo de Concurrencia, Idempotencia y Tareas Asíncronas**

### **6.1 Resolución de Condiciones de Carrera (*Race Conditions*)**

| Escenario de Colisión | Mecanismo en PostgreSQL / Aplicación | Comportamiento Determinista |
| :---- | :---- | :---- |
| **1. Dos usuarios seleccionan la misma butaca simultáneamente** | Bloqueo pesimista a nivel de fila (`SELECT ... FOR UPDATE NOWAIT`) + índice único parcial `UNIQUE (funcion_id, butaca_id) WHERE estado IN ('APARTADA', 'VENDIDA', 'CORTESIA', 'BLOQUEO_TECNICO')`. | El primer hilo adquiere el candado y aparta la butaca; el segundo recibe error inmediato de concurrencia y la API retorna `409 Conflict` sin esperar *timeouts*. |
| **2. Dos cotizaciones compiten por la misma fecha/turno** | Restricción de exclusión `ExclusionConstraint` con extensión `btree_gist` sobre `(rango_tiempo WITH &&)` filtrada para estados `PROPUESTA_RETENIDA`, `PRE_RESERVADO` y `CONFIRMADO`. | PostgreSQL rechaza a nivel de motor cualquier inserción o actualización que traslape rangos activos, garantizando cero doble-reserva. |
| **3. *Webhook* de Stripe llega en el mismo segundo que expira el carrito** | Bloqueo de fila sobre la `OrdenCompra` (`SELECT ... FOR UPDATE`) antes de leer o cambiar su estado. | Solo uno ejecuta primero: si Celery expira primero, el *webhook* ejecuta la rama tardía (reasignar si sigue libre o reembolsar \$100\%$ si ya se ocupó); si el *webhook* llega primero, Celery ve `PAGADA` y no hace nada. |
| **4. Reprogramación de fecha de un evento confirmado** | Transacción única (`transaction.atomic()`) que inserta el nuevo `BloqueoAgenda` (validado por `btree_gist`) y libera el anterior en la misma operación. | Si la nueva fecha choca con otro evento, toda la transacción hace *rollback* automático y la fecha original permanece intacta. |
| **5. Dos verificadores escanean el mismo boleto QR al mismo tiempo** | Actualización condicional atómica: `UPDATE boletos SET estado = 'USADO', usado_en = now() WHERE id = :id AND estado = 'EMITIDO' RETURNING id`. | Exactamente un escáner obtiene 1 fila actualizada ("Acceso permitido"); el segundo obtiene 0 filas y muestra "Ya ingresó a las HH:MM". |

### **6.2 Idempotencia en *Webhooks* de Stripe**

* Todo *webhook* recibido en `/api/v1/ventas/webhooks/stripe/` valida primero la cabecera criptográfica `Stripe-Signature`.
* Dentro de `transaction.atomic()`, se inserta el `event.id` de Stripe en la tabla `stripe_webhook_events` (`stripe_event_id VARCHAR(120) PRIMARY KEY`).
* Si el `INSERT` falla por llave duplicada (`IntegrityError`), el *endpoint* responde inmediatamente `HTTP 200 OK` sin volver a ejecutar lógica de negocio ni emitir boletos o reembolsos duplicados.

### **6.3 Catálogo de Tareas Periódicas (Celery Beat)**

Todas las tareas evalúan columnas `TIMESTAMPTZ` persistidas en base de datos bajo la zona horaria **America/Mexico\_City** (nunca dependen de temporizadores en memoria RAM de Celery, evitando pérdida de estado ante reinicios del contenedor).

| Tarea Programada | Frecuencia | Consulta / Condición de Disparo | Acción Ejecutada |
| :---- | :---- | :---- | :---- |
| `expirar_carritos_boletos` | Cada 30 seg | Órdenes en `APARTADO` con `now() > expira_en` o en `PAGO_EN_PROCESO` con `now() > gracia_hasta`. | Pasa orden a `EXPIRADA`, libera butacas y cancela `PaymentIntent` en Stripe. |
| `expirar_retenciones_agenda` | Cada 5 min | Cotizaciones en `PROPUESTA_RETENIDA` o `PRE_RESERVADO` con `now() > vigencia_hasta`. | Pasa a `PROPUESTA_EXPIRADA` o `EXPIRADA_SIN_PAGO` y libera bloqueo en agenda. |
| `verificar_cierre_venta_web` | Cada 1 min | Funciones en `VENTA_ACTIVA` con `now() >= hora_inicio - margen_web`. | Transiciona función a `VENTA_WEB_CERRADA`. |
| `verificar_limite_publicacion` | Cada 1 hora | Eventos en `PENDIENTE_PUBLICACION` con `now() > primera_fecha - 15 días`. | Transiciona evento a `VENCIDO_SIN_PUBLICAR` y genera alerta prioritaria en panel Admin. |
| `enviar_recordatorios_requisitos` | Diario 09:00 | Eventos en `PENDIENTE_PUBLICACION` a 3 días del pago y luego cada 7 días. | Encola correo de recordatorio al solicitante (y alerta a Admin en día 3). |
| `verificar_incumplimiento_saldo` | Diario 00:05 | Cotizaciones `CONFIRMADO` (50/50) sin liquidar donde ya pasó `D-21 23:59:59`. | Cancela arrendamiento/evento, invalida QRs y notifica incumplimiento. |
| `actualizar_sla_cotizaciones` | Cada 1 hora | Cotizaciones `EN_REVISION` con > 5 días hábiles o cuya fecha estimada ya pasó. | Marca bandera `atrasada = True` o transiciona a `EXPIRADA_POR_FECHA`. |

## **7. Guía de Implementación (Patrón State / Domain Service)**

Para evitar deuda técnica, **queda prohibido** dispersar validaciones de estado en las vistas de Django REST Framework. Cada transición debe encapsularse en servicios de dominio dedicados:

```python
from django.db import transaction
from django.utils import timezone


class TransicionEstadoInvalida(Exception):
    pass


class OrdenCompraService:
    @staticmethod
    @transaction.atomic
    def iniciar_proceso_pago(orden_id: int, gracia_minutos: int = 5):
        from apps.ventas.models import OrdenCompra

        orden = OrdenCompra.objects.select_for_update().get(pk=orden_id)
        ahora = timezone.now()

        if orden.estado != "APARTADO":
            raise TransicionEstadoInvalida(
                f"No se puede iniciar pago desde el estado {orden.estado}."
            )

        if ahora > orden.expira_en:
            raise TransicionEstadoInvalida("El tiempo de apartado de 10 minutos ha expirado.")

        orden.estado = "PAGO_EN_PROCESO"
        orden.gracia_hasta = orden.expira_en + timezone.timedelta(minutes=gracia_minutos)
        orden.save(update_fields=["estado", "gracia_hasta", "actualizado_en"])
        return orden
```
