# Auditoría EGM — Contrato de la API (`docs/contrato-api.md`)

* **Fecha:** 2026-11-26
* **Artefacto auditado:** [contrato-api.md](../../contrato-api.md) (Interfaz v1 · Revisión documental 0.2, líneas 1–322)
* **Fuentes de verdad contrastadas:**
  * [alcance.md](../../alcance.md)
  * [arquitectura.md](../../arquitectura.md)
  * [stack-tecnologico.md](../../stack-tecnologico.md)
  * [maquinas-de-estado.md](../../maquinas-de-estado.md) *(referencia auxiliar para nombres exactos de estados y transiciones citadas en el contrato)*
* **Metodología:** Revisión paralela EGM con **3 subagentes especializados**:
  1. `egm-codebase-details` — Fidelidad estricta contra las fuentes de verdad.
  2. `egm-design` — Arquitectura de API, seguridad RBAC/anti-IDOR, concurrencia, pagos e idempotencia.
  3. `egm-implementation-readiness` — Completitud de esquemas y ausencia de ambigüedades para backend/frontend.

---

## 1. Veredicto Ejecutivo

El documento [contrato-api.md](../../contrato-api.md) alinea correctamente las reglas temporales centrales del negocio (`10 min + 5 min`, `48 h`, `72 h`, `> 30 días / D-21`, `D-15`, SLA `3/5 días hábiles`, cierres `-30 min` / `0 min`, ventana QR `-2 h`, contingencia `24 h`), los mensajes exactos del escáner QR, las columnas de exportación de contingencia (`folio_corto, seccion_subseccion, fila, asiento`), el método presencial `TARJETA_TERMINAL` y las tecnologías aprobadas en [stack-tecnologico.md](../../stack-tecnologico.md).

Sin embargo, en su estado actual (`v0.2`), el contrato **no es implementable de forma directa sin adivinar contratos de datos ni expone el ciclo de vida completo de varias transiciones críticas**. Se consolidaron **23 hallazgos únicos** tras deduplicar los 3 reportes:

| Severidad | Cantidad | Resumen de impacto |
| :--- | :---: | :--- |
| **CRÍTICO** | **8** | Endpoints faltantes del ciclo de vida (liberación explícita de agenda, PDF de cotización, lectura de parámetros/categorías/bloqueos), estado inválido en `anulaciones/`, contradicción de concurrencia `nowait=True` en doble escaneo QR, y esquemas JSON incompletos (`tarifario/`, `cotizaciones/`, `mapa/`, `eventos/`). |
| **ALTO** | **10** | Falta de endpoint para cerrar `REEMBOLSO_BANCARIO_PENDIENTE`, ausencia de *rate limiting* (`429`), ambigüedad en `Idempotency-Key` y webhooks Stripe, ruptura de jerarquía de candados al cierre de venta, vacíos RBAC/anti-IDOR, contradicción en `concepto` de pagos, omisión de `unidad_cobro`, inconsistencias de nombres y formato uniforme de errores. |
| **MEDIO** | **4** | Casos borde en `reemplazar_orden_id` / `liberar/` / `bloqueos/` / `cortesias/`, nombres de *query params* sin definir, detalles de sesión en `usuarios/` y campos faltantes en `validar/` / `impresiones/` / `cancelar/`. |
| **BAJO** | **1** | `apellidos` en cuentas internas, `max_page_size = 100`, enum `{turno}` y JSON de respuesta en `mantenimientos/`. |

---

## 2. Hallazgos Consolidados

### 🔴 Severidad CRÍTICA

#### `[API-C01]` Ausencia de endpoint para liberación explícita de agenda tras cancelación o incumplimiento D-21
* **Origen:** `egm-design`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §3 (`POST cartelera/eventos/{id}/cancelar/`, L73) y §6 (`POST cotizaciones/{id}/cambios/{cambio_id}/resolver/`, L241; `POST agenda/mantenimientos/{id}/liberar/`, L244; L295) · Fuentes: [alcance.md](../../alcance.md) §2.6, §2.9.A, §2.9.D; [arquitectura.md](../../arquitectura.md) §2 (L381, L384).
* **Problema:** Las fuentes de verdad prohíben liberar automáticamente la agenda cuando existen boletos vendidos o tras incumplimiento `D-21` / cancelación con retención, exigiendo una **acción explícita posterior del Admin**. El contrato solo contempla `liberar_agenda` en el momento de cancelar y únicamente tiene ruta independiente de liberación para mantenimientos (`POST agenda/mantenimientos/{id}/liberar/`). Si el Admin cancela inicialmente con `liberar_agenda: false`, no existe endpoint para liberar ese `BloqueoAgenda` después, dejando la fecha bloqueada indefinidamente.
* **Remediación:** Agregar un endpoint exclusivo de `ADMIN` —por ejemplo `POST agenda/bloqueos/{id}/liberar/` (o `POST cartelera/eventos/{id}/liberar-agenda/` y `POST cotizaciones/{id}/liberar-agenda/`)— que reciba `{ motivo }`, valide estado cancelado/terminado, invoque `AgendaService.liberar_bloque()` y registre el movimiento en `RegistroAuditoria`.

#### `[API-C02]` `POST ventas/ordenes/{id}/anulaciones/` sin estado válido en `OrdenCompra` ni impacto en inventario/Stripe
* **Origen:** `egm-design` + `egm-codebase-details` + `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §4 (L143) · Fuentes: [arquitectura.md](../../arquitectura.md) L304, L360; [maquinas-de-estado.md](../../maquinas-de-estado.md) L87.
* **Problema:** El contrato devuelve "`201` ajuste auditado con estado resultante", pero `OrdenCompra` en las fuentes de verdad solo posee 5 estados (`APARTADO`, `PAGO_EN_PROCESO`, `PAGADA`, `EXPIRADA`, `REEMBOLSADA_AUTOMATICA`). No se especifica: (a) qué estado toma la orden, (b) si aplica solo a `TAQUILLA` o también a `LINEA`, (c) si libera `DisponibilidadButaca` a `DISPONIBLE` e invalida los QR (y qué ocurre si un boleto ya fue `USADO`), ni (d) si ejecuta reembolso Stripe o ajuste administrativo.
* **Remediación:** Precisar en L143 el estado resultante exacto de `OrdenCompra` (alineado con [maquinas-de-estado.md](../../maquinas-de-estado.md)), las precondiciones (`PAGADA`, bloqueo `409` si algún boleto ya ingresó), los efectos atómicos sobre `Boleto` y `DisponibilidadButaca` respetando el orden de candados, y el canal/alcance financiero.

#### `[API-C03]` Contradicción de concurrencia en doble escaneo QR (`nowait=True` vs `409 BOLETO_YA_USADO` con `HH:MM`)
* **Origen:** `egm-design`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §5 (L191, L198) y §7 (L312) · Fuentes: [arquitectura.md](../../arquitectura.md) §3.3 (L395), §4 (L244, L254–255).
* **Problema:** [arquitectura.md](../../arquitectura.md) exige `select_for_update(of=('self',), nowait=True)` sobre `Boleto` en `POST boletos/validar/`, mientras que [contrato-api.md](../../contrato-api.md) (L198, L312) exige que ante dos escaneos simultáneos el segundo reciba `409 BOLETO_YA_USADO` con `"Ya ingresó a las HH:MM"`. En PostgreSQL, mientras la Puerta A retiene el candado antes del `COMMIT`, la Puerta B recibe `OperationalError (55P03 lock_not_available)` sin poder leer aún `usado_en`, lo que provocaría un `500` o un `409` sin hora.
* **Remediación:** Documentar en §5 el manejo explícito de contención de candado por `nowait=True`: ya sea exponiendo un código específico `409 VALIDACION_EN_CURSO` ("Validación en proceso, reintente") o especificando un único reintento acotado (p. ej. 50 ms) para leer el `usado_en` recién confirmado y devolver `409 BOLETO_YA_USADO` con `HH:MM`, sin bloquear hilos de Gunicorn.

#### `[API-C04]` Esquema incompleto de `secciones_evento` (y respuesta `200`) en `PUT cartelera/eventos/{id}/tarifario/`
* **Origen:** `egm-implementation-readiness` + `egm-codebase-details`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §3 (L63, L75, L79–115) · Fuentes: [alcance.md](../../alcance.md) §2.3 (L56); [arquitectura.md](../../arquitectura.md) L302.
* **Problema:** El ejemplo JSON (L79–114) solo muestra `secciones_oficiales: [1]`. No define la estructura ni los nombres de campo para: (1) sección única, (2) subdivisión rectangular en graderías (`fila_inicio`, `fila_fin`, `col_inicio`, `col_fin`, tipos string vs int y `seccion_oficial_id`), (3) agrupación de cabinas completas en Palcos, ni (4) el cuerpo JSON de la respuesta `200` con los IDs creados.
* **Remediación:** Especificar un discriminador o campos explícitos por modalidad en `secciones_evento[]` (`secciones_oficiales`, `subdivision_rectangulos: { seccion_oficial_id, rectangulos: [{ fila_inicio, fila_fin, col_inicio, col_fin }] }`, `subdivision_palcos: { seccion_oficial_id, cabinas }`) e incluir el ejemplo completo de la respuesta `200`.

#### `[API-C05]` Endpoints obligatorios faltantes respecto a las fuentes de verdad
* **Origen:** `egm-codebase-details` + `egm-design` + `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §3 (L62, L68, L120), §4 (L130), §6 (L231, L236, L239, L293) · Fuentes: [alcance.md](../../alcance.md) §2.10.B; [arquitectura.md](../../arquitectura.md) L305–307, L346, L358, L362, L432, L667; [stack-tecnologico.md](../../stack-tecnologico.md) L75.
* **Problema:** Faltan 5 rutas necesarias para completar los flujos oficiales:
  1. `GET cotizaciones/{id}/comprobante/` (`U propio, A` → `200 application/pdf` con `reportlab` y desglose *snapshot*).
  2. `GET configuracion/parametros/` (`ADMIN` → lectura de los parámetros vigentes antes de usar `PATCH`).
  3. `POST cotizaciones/{id}/pagos/{pago_id}/confirmar-reembolso-bancario/` (`ADMIN` → cierre manual con `{ referencia_externa?, motivo }` para transicionar `REEMBOLSO_BANCARIO_PENDIENTE -> REEMBOLSADO`).
  4. `GET cartelera/categorias/` (`Público` → catálogo de categorías para filtrar cartelera y enviar `categoria_id` en cotizaciones/eventos).
  5. `GET inventario/funciones/{id}/bloqueos/` (`ADMIN` → listado de bloqueos técnicos activos para obtener `bloqueo_id` y `motivo`).
* **Remediación:** Incorporar las 5 rutas en sus tablas correspondientes con acceso, entrada, respuesta y códigos de error.

#### `[API-C06]` `POST cotizaciones/`: conflicto JSON vs `multipart/form-data` (póster) y falta de `cantidad` en extras
* **Origen:** `egm-implementation-readiness` + `egm-codebase-details`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §6 (L231, L235, L246–272) · Fuente: [alcance.md](../../alcance.md) §2.5 (L83).
* **Problema:** L231 indica "y póster opcional" dentro de `POST cotizaciones/`, pero el ejemplo L248–272 es JSON puro con arreglos anidados (`bloques`, `extras`), incompatible con carga binaria sin especificar `multipart/form-data`. Además, `POST cotizaciones/` muestra `"extras": []` y `POST cotizaciones/estimaciones/` usa `extra_ids`, omitiendo `cantidad` cuando un extra tiene unidad `POR_UNIDAD`.
* **Remediación:** Separar la carga del póster a `PUT cotizaciones/{id}/poster/` (`multipart/form-data`, ≤ 5 MB, simétrico a `cartelera/eventos/{id}/poster/`) y unificar `extras` en ambos endpoints como `[{ "extra_id": number, "cantidad": number }]`.

#### `[API-C07]` Esquemas JSON indefinidos en `GET inventario/funciones/{id}/mapa/` y `disponibilidad/` (+ `Cache-Control`)
* **Origen:** `egm-implementation-readiness` + `egm-design`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §4 (L128–129, L134) · Fuente: [arquitectura.md](../../arquitectura.md) §2 (L314).
* **Problema:** Los campos de `mapa/` se listan en prosa española sin nombres exactos de claves JSON (`es_accesible` vs `accesible`, estructura de `precios` y `butacas`, inclusión o no de `estado` inicial y `ETag`). En `disponibilidad/`, "pares `butaca_id, estado`" es ambiguo entre tuplas, objetos o diccionario. Además, L134 menciona caché de 2–3 s sin distinguir caché interna en Redis (`on_commit()`) de `Cache-Control: private, no-cache, must-revalidate` en HTTP (riesgo de servir asientos ocupados tras un `409` si el navegador cachea).
* **Remediación:** Fijar ejemplos JSON completos de respuesta `200` para `mapa/` y `disponibilidad/`, e indicar `ETag` + `Cache-Control: private, no-cache, must-revalidate` en HTTP mientras la caché de 2–3 s opera en Redis.

#### `[API-C08]` Esquemas indefinidos para eventos directos, funciones y reprogramación
* **Origen:** `egm-implementation-readiness` + `egm-design`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §3 (L68–70, L72).
* **Problema:** `POST cartelera/gestion/eventos/` (`{nombre, categoria, modalidad, bloques, funciones}`) no define el esquema de `bloques` ni `funciones` ni si `funciones` es opcional en eventos `PRIVADO`. `POST cartelera/eventos/{id}/funciones/` (`{inicio, fin, bloque_id}`) y `POST cartelera/funciones/{id}/reprogramar/` (`{inicio, fin, bloques, motivo}`) no precisan si `bloques` es arreglo de intervalos nuevos ni cómo difiere entre eventos `DIRECTO` (mueve `BloqueoAgenda` `FUNCION`) y `ARRENDAMIENTO` (valida contención dentro de `RENTA`).
* **Remediación:** Documentar payloads JSON completos para los 3 endpoints, unificar `inicio_en` / `fin_en` y explicitar la regla de reprogramación según `origen` del evento.

---

### 🟠 Severidad ALTA

#### `[API-A01]` Omisión de especificación de Rate Limiting (`429`) y diferenciación IP vs `user.id`
* **Origen:** `egm-design`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §1 (L28), §2 (L47–52), §4 (L138–147), §5 (L191) · Fuente: [arquitectura.md](../../arquitectura.md) §Seguridad.4 (L538).
* **Problema:** Aunque L28 lista `429`, no define cuotas ni estrategia por ruta. Aplicar límite por IP a `boletos/validar/` o `ventas/taquilla/*` bloquearía a todos los operadores bajo el Wi-Fi NAT del recinto; aplicarlo a `webhooks/stripe/` o `health/` causaría pérdida de pagos o falsas alarmas.
* **Remediación:** Añadir subsección de *Rate Limiting* en §1: límite por IP en Nginx para rutas anónimas sensibles (`login/`, `registro/`, `recuperar-password/`), exención explícita de `webhooks/stripe/` y `health/`, `ScopedRateThrottle` por `user.id` en `boletos/validar/`, `apartar/`, `checkout/` y `taquilla/*`, y respuesta `429` con cabecera `Retry-After`.

#### `[API-A02]` Especificación ambigua de `Idempotency-Key` en cobros y reembolsos
* **Origen:** `egm-design` + `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §4 (L139, L141, L179), §6 (L238) · Fuente: [arquitectura.md](../../arquitectura.md) §Seguridad.2 (L533).
* **Problema:** L179 dice "se propone la cabecera `Idempotency-Key`" sin aclarar si es obligatoria (`400` si falta o no es UUID v4), no se menciona en las filas de `checkout/` (L139) ni `taquilla/cobrar/` (L141), ni define el TTL ni qué ocurre ante peticiones concurrentes con la misma clave aún en vuelo (`409 OPERACION_EN_CURSO`).
* **Remediación:** Hacer obligatoria `Idempotency-Key` (UUID v4) en `ventas/checkout/`, `ventas/taquilla/cobrar/` y `cotizaciones/{id}/pagos/`, definir su alcance `(usuario_id, ruta, key)`, TTL y código ante petición en curso o faltante.

#### `[API-A03]` Vacíos en `POST ventas/webhooks/stripe/` y ventana de latencia post-Stripe Elements
* **Origen:** `egm-design`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §4 (L147, L179, L181) · Fuente: [arquitectura.md](../../arquitectura.md) L215–218, L322.
* **Problema:** Falta especificar: (a) exención de CSRF/sesión y lectura del cuerpo crudo (`request.body`), (b) lista cerrada de eventos procesados (`payment_intent.succeeded`, `payment_intent.payment_failed`, `payment_intent.canceled`) devolviendo `200` ante eventos no suscritos, (c) reencolado `on_commit` si un `stripe_event_id` previo quedó en `PENDIENTE`/`FALLIDO`, y (d) sondeo en `GET ventas/ordenes/{id}/` al regresar de Stripe Elements mientras la orden sigue en `PAGO_EN_PROCESO`.
* **Remediación:** Documentar estas 4 reglas explícitamente en §4.

#### `[API-A04]` Liberación masiva de apartados ajenos en `checkout/` ante `409 VENTA_CERRADA` rompe jerarquía de candados
* **Origen:** `egm-design`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §4 (L177) · Fuente: [arquitectura.md](../../arquitectura.md) L323–325, L372.
* **Problema:** L177 indica que al alcanzar el cierre de canal `"se devuelve 409 VENTA_CERRADA y se liberan los apartados pendientes de ese canal"`. Liberar órdenes de *otros* usuarios desde una petición HTTP síncrona viola la jerarquía `Usuario -> OrdenCompra -> DisponibilidadButaca` y provoca colisiones `nowait=True` o *deadlocks*.
* **Remediación:** Aclarar que la petición HTTP que recibe `409 VENTA_CERRADA` únicamente expira y libera la propia orden del solicitante; las órdenes ajenas vencidas se liberan vía Celery Beat (`skip_locked=True`).

#### `[API-A05]` Vacíos de RBAC, Anti-IDOR y revocación de sesiones
* **Origen:** `egm-design`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §2 (L52–54), §3 (L119), §4 (L128–129, L138), §5 (L189), §6 (L231) · Fuente: [arquitectura.md](../../arquitectura.md) L355–368, L529.
* **Problema:**
  * `PATCH usuarios/cuentas/{id}/` (L54) omite revocar sesiones al cambiar `rol` y no impide que un `ADMIN` se desactive/degrade a sí mismo; `recuperar-password/confirmar/` (L52) omite revocar sesiones activas.
  * `GET inventario/funciones/{id}/mapa/` y `disponibilidad/` (L128–129) no especifican `404` para funciones privadas o sin publicar.
  * `POST boletos/ordenes/{id}/impresiones/` (L189) no restringe que `CAJERO` solo imprima órdenes `TAQUILLA` en estado `PAGADA`, ni define cómo distingue el servidor primera impresión vs reimpresión (donde `motivo` es obligatorio).
  * `apartar/` (L138), `cotizaciones/` (L231) y `catalogos/` (L119) deben restringirse explícitamente para bloquear con `403` a `CAJERO`/`VERIFICADOR`.
* **Remediación:** Precisar estas reglas en sus respectivas filas de permisos.

#### `[API-A06]` Contradicción en `concepto` de `POST cotizaciones/{id}/pagos/` y reglas de rechazo/reprogramación
* **Origen:** `egm-codebase-details` + `egm-design`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §6 (L238–241) · Fuentes: [alcance.md](../../alcance.md) §2.9.C (L157); [maquinas-de-estado.md](../../maquinas-de-estado.md) L167.
* **Problema:** L238 usa `Concepto INICIAL o SALDO`, mientras [maquinas-de-estado.md](../../maquinas-de-estado.md) L167 define `ANTICIPO_50`, `SALDO_50` y `LIQUIDACION_100`. Además, faltan códigos `409` para ficha prohibida en últimas 48 h de `D-21` o sobre tope de efectivo, `409 CRUCE_AGENDA` en `resolver-pago-extemporaneo/`, y la guarda de `alcance.md` L157 que exige liquidar el saldo pendiente antes de reprogramar a `< 21` días si está en `ANTICIPO_50_PAGADO`.
* **Remediación:** Alinear `concepto` con los nombres oficiales (o documentar la derivación en servidor) y explicitar las guardas y códigos `409` en L238–241.

#### `[API-A07]` Omisión de `unidad_cobro` en `configuracion/extras/` y catálogo completo de `configuracion/parametros/`
* **Origen:** `egm-codebase-details` + `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §3 (L119–122) · Fuentes: [alcance.md](../../alcance.md) L83, L196; [arquitectura.md](../../arquitectura.md) L297, L348.
* **Problema:** `POST / PATCH configuracion/extras/` omite `unidad_cobro` (`POR_EVENTO | POR_DIA | POR_TURNO | POR_UNIDAD`). `PATCH configuracion/parametros/` solo cita 2 parámetros "por ejemplo", dejando sin especificar las ~13 claves restantes de `ConfiguracionSistema`.
* **Remediación:** Añadir `unidad_cobro` como campo obligatorio en `extras/` y listar la tabla completa de parámetros de `ConfiguracionSistema` (nombre, tipo, rango válido y valor por defecto).

#### `[API-A08]` Inconsistencias internas de nomenclatura entre endpoints
* **Origen:** `egm-codebase-details` + `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) L68, L70, L72, L130–131, L138, L140–141, L146, L231, L235, L238, L243, L251.
* **Problema:** Se mezclan nombres distintos para el mismo concepto: `butacas` vs `butaca_ids`; `metodo_pago` vs `metodo`; `vence_at` (Spanglish) vs `expira_en` / `inicio_en`; `categoria` vs `categoria_id`; `inicio, fin` vs `inicio_en, fin_en`; y `extras` / `asistentes_estimados` (`cotizaciones/`) vs `extra_ids` / `asistentes` (`estimaciones/`).
* **Remediación:** Estandarizar en todo el documento: `butaca_ids` (o `butacas`), `metodo_pago`, `vence_en`, `categoria_id`, `inicio_en`/`fin_en`, `extras` y `asistentes_estimados`.

#### `[API-A09]` Esquemas JSON faltantes en propuestas alternativas, cambios, `GET boletos/` y `contingencia/reconciliar/`
* **Origen:** `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §5 (L187, L209), §6 (L233–234, L240–242).
* **Problema:** No se definen los payloads ni enums de `alternativas/`, `responder-alternativas/` (cómo se rechazan todas), `cambios/`, `cambios/{cambio_id}/resolver/` (`APROBAR` vs `ACEPTAR`) ni `eleccion-cancelacion/`. En `GET boletos/{id}/` falta si el QR es `qr_token` (para `qrcode.react`) o imagen y el enum exacto de `estado`. En `contingencia/reconciliar/` falta el nombre del campo CSV en `multipart/form-data` y si `{aplicados, ya_usados, rechazados}` son enteros o arreglos.
* **Remediación:** Añadir ejemplos JSON concretos y tipos exactos en todos estos endpoints.

#### `[API-A10]` Cobertura incompleta del formato uniforme `{code, message, details}` en `400`/`409` y `GET health/`
* **Origen:** `egm-design` + `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §1 (L23–40), L65, L132, L193–203, L207, L234, §7 (L304) · Fuente: [arquitectura.md](../../arquitectura.md) §4 (L407–418).
* **Problema:** L30 solo menciona `{code, message, details}` para "errores de negocio", sin aclarar que el *custom exception handler* normaliza todo `4xx`/`5xx` (incluyendo `400` de validación de campos, `401`, `403`, `404`, `429`). Además, faltan los `code` de varios `409` (L65, L132, L207, L234), y en `GET health/` (L304) no se aclara que es sin sesión y sin exponer detalles internos en `503`.
* **Remediación:** Documentar la tabla de códigos `code` estándar del exception handler, asignar `code` a todos los `409` pendientes y precisar el contrato de `GET health/`.

---

### 🟡 Severidad MEDIA

#### `[API-M01]` Vacíos de concurrencia y códigos de error en `reemplazar_orden_id`, `liberar/`, `bloqueos/` y `cortesias/`
* **Origen:** `egm-design` + `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §4 (L130–132, L138–146, L176).
* **Problema:** No se especifica si `taquilla/apartar/` soporta `reemplazar_orden_id` ni `CAMBIO_FUNCION`, ni el rollback ante fallo en la nueva selección, ni qué devuelve `GET ventas/carrito/` en `PAGO_EN_PROCESO`, ni errores en `liberar/` (`butacas` vacío/ajeno, orden expirada) o atomicidad all-or-nothing en `bloqueos/` y `cortesias/`.
* **Remediación:** Documentar explícitamente estos casos borde y garantizar atomicidad bajo el orden de candados global.

#### `[API-M02]` Query parameters sin nombres exactos en listados
* **Origen:** `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) L21, L62, L68, L143–144, L187, L236, L243, L303.
* **Problema:** Los filtros de `cartelera/eventos/` (fecha/categoría), `agenda/bloqueos/` (intervalo y si pagina o no), `auditoria/registros/` y `ventas/pagos/` se describen en prosa sin nombres exactos ni formatos de parámetro.
* **Remediación:** Definir la tabla de *query params* (`?fecha=`, `?categoria_id=`, `?desde=`, `?hasta=`, `?modulo=`, `?actor_id=`, etc.) en cada endpoint `GET`.

#### `[API-M03]` Detalles faltantes en `usuarios/` (`registro/`, `activa: false`, `csrf/`, `logout/`)
* **Origen:** `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) §2 (L46–56).
* **Problema:** No se define el cuerpo JSON de `csrf/` ni `logout/`, ni si `registro/` inicia sesión automáticamente (set-cookie), ni qué código HTTP devuelve `login/` ante una cuenta con `activa: false` (`401` vs `403 CUENTA_SUSPENDIDA`).
* **Remediación:** Especificar los cuerpos JSON exactos de respuesta y el comportamiento de `registro/` y cuentas desactivadas.

#### `[API-M04]` Tipos, enums y `details` faltantes en `resolver-vencimiento/`, `cancelar/`, `boletos/validar/` e `impresiones/`
* **Origen:** `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) L71, L73, L189, L191–203.
* **Problema:** Faltan el formato de `nueva_fecha_limite`, los valores enum de `causa` en `cancelar/`, las claves exactas dentro de `details` en errores de `boletos/validar/` (`usado_en`, `funcion_inicio_en`, `abre_en`), y el código `400` ante reimpresión sin `motivo`.
* **Remediación:** Explicitar tipos, enums y estructuras `details` en estas operaciones.

---

### 🟢 Severidad BAJA

#### `[API-B01]` Omisión de `apellidos` en `usuarios/cuentas/`, `max_page_size`, enum `{turno}` y JSON en `mantenimientos/`
* **Origen:** `egm-codebase-details` + `egm-design` + `egm-implementation-readiness`
* **Ubicación:** [contrato-api.md](../../contrato-api.md) L21, L53–54, L121, L243–244, L303.
* **Problema:** `usuarios/cuentas/` omite `apellidos` (presente en `registro/` y `perfil/`). La paginación no define `max_page_size` (ej. `100`). `configuracion/turnos/{turno}/` no enumera los valores válidos de `{turno}` ni el formato `HH:MM`. `agenda/mantenimientos/` carece de ejemplo de respuesta JSON.
* **Remediación:** Añadir `apellidos` en cuentas internas, fijar `max_page_size = 100` en §1, explicitar `{turno}` (`MATUTINO | VESPERTINO | DIA_COMPLETO`) y añadir ejemplos JSON en mantenimientos.
