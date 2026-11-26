# Contrato de la API del Teatro de la Ciudad de Coatzacoalcos

**Interfaz v1 · Revisión documental 0.2 · Propuesta para implementación y pruebas.** Este documento reúne el acuerdo entre el portal React, la aplicación de gestión, Django REST Framework, Stripe Sandbox y el monitoreo interno. Las rutas ya fijadas en arquitectura conservan sus nombres y respuestas. Los campos y las operaciones complementarias concretan los flujos del alcance para revisión del equipo.

Fuentes del contrato: [Alcance](alcance.md), [Arquitectura, convenciones y endpoints](arquitectura.md), [Stack tecnológico](stack-tecnologico.md) y [Máquinas de estado](maquinas-de-estado.md).

## 1. Convenciones y permisos

Todas las rutas de las tablas llevan el prefijo `/api/v1/` y la barra final. Por ejemplo, `POST ventas/checkout/` corresponde a `POST /api/v1/ventas/checkout/`. El cuerpo ordinario es JSON UTF-8. Los archivos usan el formato indicado en cada operación. Los ID son enteros positivos y los folios son texto. En las tablas, `?` indica un campo opcional.

| Acceso | Alcance |
| :--- | :--- |
| Público | Visitante anónimo. Puede consultar cartelera publicada y mapa comercial. |
| U · USUARIO | Comprador o solicitante autenticado. Cada consulta y escritura comprueba el propietario. |
| C · CAJERO | Operaciones presenciales con sesión del cajero. El asistente puede comprar sin cuenta. |
| V · VERIFICADOR | Control de acceso por QR o folio. |
| A · ADMIN | Operaciones internas según la matriz de permisos, incluidas publicación, contingencia y auditoría. |

React obtiene `csrftoken` en `GET usuarios/csrf/`. Usa `fetch` en el mismo origen con `credentials: 'include'` y envía `X-CSRFToken` en escrituras, incluido el login. La sesión en Redis usa cookie `HttpOnly`, `SameSite=Lax` y `Secure` en producción. El webhook autentica al emisor con `Stripe-Signature` sobre el cuerpo original.

Los listados aceptan `?page=1` y devuelven `{count, next, previous, results}` con 20 elementos por defecto. Los enlaces de página inexistentes son nulos. El mapa es un recurso completo. Las fechas civiles usan `YYYY-MM-DD`, los instantes ISO 8601 con desplazamiento. Django evalúa los cortes en `America/Mexico_City` y persiste UTC. Los importes son cadenas decimales en MXN con dos posiciones; el servidor calcula importes y vencimientos.

| HTTP | Interpretación |
| :--- | :--- |
| 200 / 201 / 204 | Acción o consulta resuelta / recurso creado / éxito sin cuerpo, según la fila. |
| 400 / 401 / 403 / 404 | Entrada inválida / sesión requerida o credenciales incorrectas / permiso, propiedad o CSRF insuficientes / recurso inexistente o ajeno al catálogo público. |
| 409 / 422 | Conflicto con el estado del recurso / acceso fuera de la ventana horaria del boleto. |
| 429 / 500 / 503 | Límite de peticiones / error de procesamiento / dependencia temporalmente indisponible. |

Los errores de negocio devuelven `code` estable, `message` legible y `details` objeto. Ejemplo de conflicto al apartar:

```json
{
  "code": "ASIENTO_NO_DISPONIBLE",
  "message": "La butaca seleccionada ya fue apartada o vendida.",
  "details": {
    "butaca_id": 412
  }
}
```

## 2. Cuentas y sesión

| Método y ruta | Acceso y entrada | Respuesta y reglas |
| :--- | :--- | :--- |
| `GET usuarios/csrf/` | Portal público o de gestión al iniciar. | `200` con cookie `csrftoken`; el cliente envía su valor en `X-CSRFToken` para escritura. |
| `POST usuarios/registro/` | Visitante; `nombre, apellidos, correo, password` y aceptación del aviso y términos vigentes. | `201` con los datos de la cuenta creada y rol `USUARIO`. Datos o aceptación inválidos: `400`. |
| `POST usuarios/login/` / `POST usuarios/logout/` | Inicio con `correo, password`; cierre con sesión activa. | Inicio: `200` con identidad y rol, y cookie de sesión `HttpOnly`; credenciales inválidas: `401`. Cierre: `200` y sesión revocada. |
| `POST usuarios/recuperar-password/` | Visitante; `correo`. | `200` con el mismo mensaje de recepción para cualquier correo válido. Si corresponde a una cuenta, se envía el enlace de recuperación por SMTP. |
| `GET usuarios/perfil/` / `PATCH usuarios/perfil/` | `USUARIO`; en edición, los campos propios que cambian (`nombre, apellidos, telefono`). | `200` con el perfil de la sesión. El rol y el propietario los determina el servidor. |
| `GET usuarios/sesion/` | Público | 200 {autenticado,usuario}. Usuario nulo para visitante. |
| `POST usuarios/recuperar-password/confirmar/` | Público | {uid,token,password_nuevo} → 204. Token de un uso sujeto a caducidad. |
| `GET / POST usuarios/cuentas/` | A | Lista de cuentas / {nombre,correo,rol,password} → 201 cuenta interna. Roles de alta interna C, V o A. |
| `GET / PATCH usuarios/cuentas/{id}/` | A | 200 cuenta {id,nombre,correo,rol,activa}. Editar datos internos o suspender mediante activa:false, revocando sesiones. |

En registro se envían `acepta_privacidad: true` y `acepta_terminos: true`. El backend registra las versiones vigentes y rechaza una aceptación incompleta. El enlace de recuperación tiene una vigencia de 30 minutos. Tras iniciar sesión desde el mapa, el portal recupera la selección preliminar y vuelve a consultar su disponibilidad antes de apartar.

## 3. Cartelera, funciones y configuración

| Método y ruta | Acceso y entrada | Respuesta y reglas |
| :--- | :--- | :--- |
| `GET cartelera/eventos/` | Consulta pública; filtros opcionales de fecha y categoría. | `200` paginado con los eventos publicados comerciales o públicos y sus funciones. Un filtro inválido devuelve `400`. |
| `PUT cartelera/eventos/{id}/tarifario/` | Solicitante de su arrendamiento comercial pagado o `ADMIN`; configuración completa de `secciones_evento`, `fases_venta` y `precios`. | `200` con la configuración guardada. Cada butaca habilitada pertenece a una zona; cada par sección/fase tiene un precio ≥ $100.00. Se validan nombres únicos por evento, fases consecutivas, cobertura sin traslapes y geometría según alcance §2.3. Una configuración inválida devuelve `400`, una cuenta sin permiso `403` y un tarifario ya publicado `409 TARIFARIO_CONGELADO`. |
| `PUT cartelera/eventos/{id}/poster/` | Solicitante de su arrendamiento pagado o `ADMIN` antes de publicar; archivo `poster` en `multipart/form-data`. | `200` con `poster_url`. Admite JPG, PNG o WebP de hasta 5 MB. |
| `POST cartelera/eventos/{id}/publicar/` | `ADMIN`; evento comercial o público. | `200` con el evento en `PUBLICADO`. Requiere póster, pago inicial acreditado si es arrendamiento y tarifario completo si es comercial; ante requisitos pendientes devuelve `409` con el detalle. Congela zonas, fases y precios del evento comercial. |
| `GET cartelera/eventos/{id}/` | Público | `200` con nombre, modalidad, categoría, póster y funciones del evento publicado. Privado o sin publicar: `404`. |
| `GET cartelera/funciones/{id}/` | Público, C/V en operación | 200 función visible con evento y márgenes de cierre aplicables. |
| `GET / POST cartelera/gestion/eventos/` | A | Listar por estado u origen / crear directo con {nombre,categoria,modalidad,bloques,funciones} → 201 evento. El arrendado se vincula a la cotización formalizada. |
| `GET / PATCH cartelera/gestion/eventos/{id}/` | A o U arrendatario propio (lectura) | 200 detalle de gestión. A edita nombre y categoría. Cambios de agenda siguen la operación de reprogramación. |
| `POST cartelera/eventos/{id}/funciones/` | A | {inicio,fin,bloque_id} → 201 función. Inicio y fin deben caber en el bloque del evento. |
| `POST cartelera/eventos/{id}/resolver-vencimiento/` | A | {accion,motivo,nueva_fecha_limite?} → 200 estado. Acciones PUBLICAR, PRORROGAR, REALIZAR_SIN_PUBLICACION, CANCELAR. |
| `POST cartelera/funciones/{id}/reprogramar/` | A | {inicio,fin,bloques,motivo} → 200 función con horario anterior y nuevo. |
| `POST cartelera/eventos/{id}/cancelar/` | A | {causa,motivo,liberar_agenda} → 200 estado y resultado de liberación explícita. Invalida boletos y cierra ambos canales. |

**Tarifario comercial.** Una zona puede corresponder a todo el aforo habilitado, a una sección física, a varias secciones completas o a una subdivisión. En gradería se admiten hasta seis subdivisiones contiguas por sección mediante rectángulos; en Palcos se agrupan cabinas completas. Cada nombre de zona es único dentro del evento. Cada butaca habilitada pertenece a una sola zona. Las fases son consecutivas, comunes a las funciones del evento y cubren desde publicación hasta cierre. Ante datos inválidos se conserva el tarifario anterior.

Ejemplo del cuerpo de `PUT cartelera/eventos/{id}/tarifario/` para un evento que habilita solo Luneta. Las claves locales enlazan zonas y fases dentro de la petición; la respuesta devuelve sus ID de recurso.

```json
{
  "secciones_evento": [
    {
      "clave": "luneta",
      "nombre": "Luneta",
      "secciones_oficiales": [
        1
      ]
    }
  ],
  "fases_venta": [
    {
      "clave": "preventa",
      "nombre": "Preventa",
      "desde_publicacion": true
    },
    {
      "clave": "general",
      "nombre": "General",
      "inicia_en": "2026-12-01T12:00:00-06:00"
    }
  ],
  "precios": [
    {
      "seccion": "luneta",
      "fase": "preventa",
      "precio": "150.00"
    },
    {
      "seccion": "luneta",
      "fase": "general",
      "precio": "200.00"
    }
  ]
}
```

| Método y ruta | Acceso y entrada | Respuesta y reglas |
| :--- | :--- | :--- |
| `GET configuracion/catalogos/` | Usuario autenticado que cotiza o `ADMIN`. | `200` con turnos, tarifas y servicios extra vigentes para el cálculo estimado. |
| `PATCH configuracion/parametros/` | `ADMIN`; parámetros a modificar, por ejemplo `apartado_min` y `gracia_pago_min`. | `200` con la configuración resultante; `400` por valores inválidos. Las cotizaciones con importes y reglas ya fijados conservan su desglose. |
| `GET / PUT configuracion/turnos/{turno}/` | A | {hora_inicio,hora_fin,tarifa_base} → 200 turno. Día completo abarca ambos turnos. |
| `GET / POST configuracion/extras/ · PATCH configuracion/extras/{id}/` | A | Listar / alta {nombre,tipo,precio_base,activo} → 201 / edición parcial → 200. Tipo SERVICIO o INFRAESTRUCTURA. |

## 4. Inventario, carrito y cobro

| Método y ruta | Acceso y entrada | Respuesta y reglas |
| :--- | :--- | :--- |
| `GET inventario/funciones/{id}/mapa/` | Lectura de una función comercial publicada. | `200` con `butacas` (id, sección física, fila, asiento, accesibilidad, habilitación y sección del evento), `fase_venta_id` y `precios` por sección del evento para esa fase. |
| `GET inventario/funciones/{id}/disponibilidad/` | Misma función; sondeo cada 10–15 s con la vista activa y `If-None-Match` tras la primera consulta. | `200` con `fase_venta_id` y pares `butaca_id, estado`; `304` sin cuerpo cuando coincide el `ETag`. El identificador incluye fase y disponibilidad. Al cambiar de fase, aun con las mismas butacas libres, se devuelve `200` y el cliente recarga los precios del mapa. |
| `POST inventario/funciones/{id}/bloqueos/ · DELETE inventario/funciones/{id}/bloqueos/{bloqueo_id}/` | A | {butaca_ids,motivo} → 201 bloqueo técnico. Retirar → 204 y libera localidades. |
| `POST inventario/funciones/{id}/cortesias/` | A | {butaca_ids,beneficiario?,motivo?} → 201 {boleto_ids,total:"0.00"}. Emite QR, método CORTESIA. |
| `POST inventario/funciones/{id}/cortesias/{boleto_id}/revocar/` | A; motivo | `200` con boleto invalidado y butaca libre si aún no ingresó. Si ya ingresó: `409`. |

El mapa conserva sección física, fila, asiento, accesibilidad y zona comercial. Los cinco estados son `DISPONIBLE`, `APARTADA`, `VENDIDA`, `BLOQUEO_TECNICO` y `CORTESIA`. La pantalla identifica sus apartados mediante la orden propia. El sondeo de disponibilidad se pausa al perder foco. El servidor limita la caché a 2–3 s o al próximo cambio de fase, lo que ocurra primero. Una respuesta `304` conserva el mapa anterior; una fase nueva obliga a actualizar los precios aun con los mismos asientos libres.

| Método y ruta | Acceso y entrada | Respuesta y reglas |
| :--- | :--- | :--- |
| `POST ventas/carrito/apartar/` | `USUARIO`; `funcion_id` y `butacas` (lista de identificadores que desea agregar). | `200` con la orden completa. El primer asiento fija `expira_en`; añadir localidades conserva ese vencimiento. Cada nueva butaca toma la fase y el precio vigentes al apartarla. Repetir una butaca ya presente en la misma orden conserva su precio y cantidad. |
| `POST ventas/checkout/` | `USUARIO`; `orden_id` propia, de canal `LINEA`, con al menos una butaca. | `200` con `orden_id, estado, gracia_hasta, total, client_secret`. Suma los precios del detalle. Desde `APARTADO` requiere `now() <= expira_en` y venta web abierta. El reintento de una orden ya en `PAGO_EN_PROCESO` reutiliza el intento vigente y conserva `gracia_hasta`. La confirmación firmada de Stripe acredita el pago. |
| `POST ventas/taquilla/apartar/` | `CAJERO`; `funcion_id, butacas`; cuenta del cajero en sesión. | `200` con el mismo detalle del apartado web. Comparte inventario y temporizador con el portal; aplica el límite de 10 por operación. |
| `POST ventas/taquilla/cobrar/` | `CAJERO`; `orden_id` de su operación y `metodo_pago` (`EFECTIVO` o `TARJETA_TERMINAL`). | `200` con `orden_id, estado: PAGADA, folio, total, boletos`. Requiere apartado vigente y taquilla abierta. Un cobro repetido sobre la misma orden ya pagada devuelve el comprobante existente. |
| `GET ventas/carrito/` | U/C propio | 200 {carrito:null} o {carrito:Orden}. |
| `GET ventas/pagos/ · POST ventas/ordenes/{id}/anulaciones/` | A | Listar cobros por desde,hasta,estado,canal / {motivo} → 201 ajuste auditado con estado resultante. |
| `GET ventas/ordenes/` | U propio o A global | `200` con órdenes paginadas. |
| `GET ventas/ordenes/{id}/` | U propio, C para su operación o A | `200` con la orden y el estado confirmado por el servidor. |
| `POST ventas/ordenes/{id}/liberar/` | U o C propio; `{butacas: [412]}` | `200` con detalle restante y vencimiento original. Retirar la última butaca expira la orden. En cobro: `409 PAGO_EN_PROCESO`. |
| `POST ventas/webhooks/stripe/` | Stripe Sandbox, cuerpo firmado | Firma inválida: `400`. Registro y encolado: `200`. Si falla el encolado: `500` para reintento. La reentrega de un evento ya procesado confirma recepción sin duplicar boletos ni reembolsos. |

**Ejemplo de apartado.** La primera butaca ya está en la orden. El usuario añade otra cuando inicia la venta general.

```json
{
  "funcion_id": 12,
  "butacas": [
    413
  ]
}
```

**Respuesta 200.**
```json
{
  "orden_id": 81,
  "funcion_id": 12,
  "estado": "APARTADO",
  "expira_en": "2026-11-28T12:09:00-06:00",
  "detalle": [
    { "butaca_id": 412, "seccion_evento_id": 4, "fase_venta_id": 1, "precio_unitario": "150.00" },
    { "butaca_id": 413, "seccion_evento_id": 4, "fase_venta_id": 2, "precio_unitario": "200.00" }
  ],
  "total": "350.00"
}
```

* **Conflictos del apartado:** La selección se procesa completa. Una butaca ocupada devuelve `409 ASIENTO_NO_DISPONIBLE`; superar los 10 boletos acumulados por cuenta y función (`APARTADO + PAGO_EN_PROCESO + PAGADA`) devuelve `409 LIMITE_BOLETOS`. Un conflicto deja intacto el apartado vigente.
* **Cambio de función:** Si hay otra orden `APARTADO`, la API devuelve `409 CAMBIO_FUNCION` con su `orden_id` en `details`. Tras advertir al comprador, el cliente repite la petición con `reemplazar_orden_id`. El servidor comprueba que siga siendo la misma orden activa y, en una transacción, libera la anterior y crea la nueva. Una orden con cobro en curso devuelve `409 PAGO_EN_PROCESO`.
* **Vencimiento y cierre por función:** Los valores por defecto son 10 min desde el primer apartado, 5 min adicionales desde `expira_en` para el cobro web iniciado a tiempo, cierre web 30 min antes y cierre de taquilla al inicio. Se usan los parámetros vigentes de Configuración. Al intentar cobrar una orden `APARTADO` vencida se devuelve `409 ORDEN_EXPIRADA`; al alcanzar el cierre del canal se devuelve `409 VENTA_CERRADA` y se liberan los apartados pendientes de ese canal. Una orden web que ya inició el cobro puede concluir hasta `gracia_hasta`. Los pagos confirmados después de expirar siguen las transiciones T-3.7 y T-3.8 de ME-03.

**Reintentos de pago.** Para iniciar cobros se propone la cabecera `Idempotency-Key` con un UUID. La misma cuenta, operación, clave y cuerpo recuperan el intento o comprobante existente; reutilizar la clave con otro cuerpo devuelve `409 CLAVE_REUTILIZADA`. En Stripe, el servidor deduplica por `stripe_event_id`, verifica la firma y encola después del commit. Un reintento tras fallo de encolado debe retomar el evento pendiente.

El checkout cobra el total de los precios fijados por butaca. Stripe Elements utiliza `client_secret`; el regreso del navegador permite consultar la orden. Solo la confirmación firmada acredita el pago. Al llegar tarde, se reasignan todas las localidades si la función sigue vigente y sin cancelar, están todas disponibles y se respeta el límite acumulado. En otro caso procede el reembolso técnico íntegro. El cajero registra efectivo o tarjeta de terminal externa; la cancelación de la operación o el cierre de sesión libera su apartado.

## 5. Boletos, puerta y contingencia

| Método y ruta | Acceso y entrada | Respuesta y reglas |
| :--- | :--- | :--- |
| `GET boletos/ y boletos/{id}/` | U propio, A global | 200 lista o detalle con evento, función, inicio, sección/zona, fila, asiento, orden, folio, método, plataforma y estado. Detalle autorizado incluye QR. |
| `GET boletos/{id}/archivo/` | U propio, A | 200 application/pdf con los datos del boleto y QR. Incluye cortesías para A. |
| `POST boletos/ordenes/{id}/impresiones/` | C/A | {motivo?} → 200 PDF de orden presencial. Reimpresión requiere motivo y reutiliza folios y QR. |

`POST boletos/validar/` admite sesión de `VERIFICADOR` o de `ADMIN` en soporte. Con cámara se envía `token`; si el operador seleccionó una función en la pantalla, se añade `funcion_id` como contexto de puerta. Con captura manual se envían `folio_corto` y `funcion_id` obligatoriamente. Se acepta una sola credencial por petición. La ventana de acceso siempre se calcula con el horario de la función del boleto. El orden de evaluación sigue ME-04, §5.2.

| Resultado | HTTP y `code` | Mensaje en pantalla |
| :---- | :---- | :---- |
| Entrada o firma inválida | `400 BOLETO_INVALIDO` | Boleto no válido |
| Boleto o folio inexistente | `404 BOLETO_NO_ENCONTRADO` | Boleto no válido |
| Boleto invalidado o función/evento cancelado | `400 BOLETO_INVALIDO` | Boleto no válido |
| Boleto usado previamente | `409 BOLETO_YA_USADO` | Ya ingresó a las HH:MM |
| Función de puerta distinta a la del boleto | `409 OTRA_FUNCION` | Boleto de la función DD/MM HH:MM |
| Antes de la ventana / después del fin | `422 ACCESO_ANTICIPADO` / `422 FUNCION_CONCLUIDA` | Abre a las HH:MM / La función ya terminó |
| Boleto válido dentro de su ventana | `200 ACCESO_PERMITIDO` | Acceso permitido + sección, fila y asiento |

Solo el último resultado registra el ingreso. Su JSON contiene `code, message, seccion, fila, asiento`; los errores usan el formato de la sección 1. En contingencia, las siguientes operaciones son exclusivas de `ADMIN` y quedan auditadas:

| Método y ruta | Entrada | Respuesta |
| :---- | :---- | :---- |
| `GET boletos/funciones/{id}/contingencia/listado/` | `formato=pdf` o `csv`, desde 24 h antes de la función. | `200` con PDF o CSV de boletos y cortesías vigentes. Las columnas son `folio_corto, seccion_subseccion, fila, asiento`; `seccion_subseccion` muestra la sección física y, cuando difiere, la zona comercial entre paréntesis, p. ej. **Luneta (General)**. Formato inválido: `400`; descarga anticipada: `409`. |
| `POST boletos/funciones/{id}/contingencia/activar/` | Función comercial indicada en la ruta. | `200` con `modo_contingencia_activo: true`. |
| `POST boletos/funciones/{id}/contingencia/reconciliar/` | Archivo CSV con columna única `folio_corto` o JSON con lista `folios`. | `200` con `aplicados, ya_usados, rechazados`. Procesa exclusivamente esa función, conserva los ingresos previos y cierra la contingencia en la misma transacción. |

Ejemplos de petición al escáner. El primero usa cámara en la puerta de una función seleccionada; el segundo es captura manual.

```json
{
  "token": "<token firmado del boleto>",
  "funcion_id": 12
}
```

```json
{
  "folio_corto": "BH7K9M2P",
  "funcion_id": 12
}
```

## 6. Arrendamientos y agenda

| Método y ruta | Acceso y entrada | Respuesta y reglas |
| :--- | :--- | :--- |
| `POST cotizaciones/` | `USUARIO`; `nombre_evento, categoria_id, modalidad, contacto_nombre, contacto_telefono, contacto_correo, asistentes_estimados, es_multidia, bloques, extras` y póster opcional. | `201` con `cotizacion_id, estado: EN_REVISION` y desglose estimado. Más de 1,728 asistentes o bloques inválidos devuelven `400`. La recepción de la solicitud aún deja libre la agenda. |
| `POST cotizaciones/{id}/aprobar/` | `ADMIN`; `monto_oficial` para una solicitud en revisión. | `200` con `estado: PRE_RESERVADO, monto_oficial, esquema_pago, monto_anticipo, saldo, pre_reserva_expira_en` y el vencimiento del saldo cuando aplique. Un traslape devuelve `409 CRUCE_AGENDA` sin aprobar parcialmente. |
| `POST cotizaciones/{id}/alternativas/` | `ADMIN`; de una a tres opciones de fecha y turno libres y mutuamente disjuntas. | `200` con `estado: PROPUESTA_RETENIDA`, opciones y vencimiento. Cantidad inválida: `400`. Traslape: `409 CRUCE_AGENDA`. |
| `POST cotizaciones/{id}/responder-alternativas/` | Solicitante propietario; aceptación con `opcion_id` o rechazo de todas. | `200` con `EN_REVISION` al aceptar (solo la elegida sigue retenida) o `PROPUESTA_EXPIRADA` al rechazar. Propuesta vencida: `409`. |
| `POST cotizaciones/estimaciones/` | U | {bloques,extra_ids,asistentes,modalidad} → 200 desglose y subtotal referencial. |
| `GET cotizaciones/ y cotizaciones/{id}/` | U propio, A global | Lista por estado o detalle, 200. A recibe indicadores de atraso y proximidad de fecha. |
| `POST cotizaciones/{id}/rechazar/` | A | {motivo} → 200 estado y liberación de retenciones relacionadas. |
| `POST cotizaciones/{id}/pagos/` | U propio | {concepto,metodo} con clave de idempotencia → 201 {pago_id,importe,estado,vence_at,client_secret?,instrucciones_ficha?}. Concepto INICIAL o SALDO; método TARJETA, FICHA_EFECTIVO o SPEI según disponibilidad. |
| `POST cotizaciones/{id}/resolver-pago-extemporaneo/` | A | {decision,motivo} → 200 detalle. ACEPTAR revalida disponibilidad; RECHAZAR tramita reembolso técnico íntegro. |
| `POST cotizaciones/{id}/cambios/` | U propio | {tipo,motivo,bloques_propuestos?} → 201 petición. Tipo CANCELACION o REPROGRAMACION. |
| `POST cotizaciones/{id}/cambios/{cambio_id}/resolver/` | A | {decision,motivo,liberar_agenda?,bloques?} → 200 estado, efecto en agenda y tratamiento administrativo. |
| `POST cotizaciones/{id}/eleccion-cancelacion/` | U propio | Tras cancelación por el teatro, {opcion} REEMBOLSO_EXTERNO o REPROGRAMACION → 200 elección registrada. |
| `GET agenda/bloqueos/` / `POST agenda/mantenimientos/` | `ADMIN`; consulta por intervalo, o alta con `inicio_en, fin_en` y motivo. | Consulta: `200` con ocupaciones. Alta: `201` con bloqueo confirmado; intervalo inválido: `400`; traslape: `409 CRUCE_AGENDA`. Dos bloques contiguos son compatibles porque el fin del intervalo es exclusivo. |
| `POST agenda/mantenimientos/{id}/liberar/` | A; motivo | `200` con bloqueo liberado y registro de auditoría. |

**Solicitud.** Ejemplo de un solo día con montaje y función en el bloque solicitado:

```json
{
  "nombre_evento": "Concierto de invierno",
  "categoria_id": 1,
  "modalidad": "COMERCIAL",
  "contacto_nombre": "Ana Ejemplo",
  "contacto_telefono": "0000000000",
  "contacto_correo": "ana@example.org",
  "asistentes_estimados": 450,
  "es_multidia": false,
  "bloques": [
    {
      "fecha": "2027-02-12",
      "turno": "MATUTINO",
      "actividad": "MONTAJE"
    },
    {
      "fecha": "2027-02-12",
      "turno": "VESPERTINO",
      "actividad": "FUNCION"
    }
  ],
  "extras": []
}
```

**Revisión y ocupación.** Se calcula el estimado al enviar. El SLA inicial es de tres días hábiles y la alerta de atraso corresponde a cinco días hábiles. Una alternativa aceptada libera las demás; la elegida se retiene hasta la decisión del Admin. La pre-reserva nace al aprobar y habilitar el pago. Si vence sin acreditación, se liberan los intervalos. Un conflicto de agenda revierte la operación completa.

En la aprobación se evalúa la **primera fecha reservada**, incluido el montaje. Con la configuración por defecto, a 30 días corresponde `100` y desde 31 días corresponde `50_50`. Django fija el esquema, el anticipo, el vencimiento de la pre-reserva (48 h por defecto) y, para parcialidades, el corte del saldo a las 23:59:59 de `D-21` en `America/Mexico_City`. Las fichas SPEI/efectivo se ofrecen solo para arrendamiento, con sus restricciones de plazo y monto (alcance §2.5). El anticipo se redondea con `ROUND_HALF_UP` a dos decimales y el saldo se calcula por diferencia. Para un total de `"1000.01"`, el anticipo es `"500.01"` y el saldo `"500.00"`. Durante las últimas 48 h previas al corte del saldo (valor por defecto) solo se ofrece tarjeta inmediata. Si el importe supera el tope de efectivo, las opciones son tarjeta o SPEI según disponibilidad. La confirmación de tarjeta o ficha entra por el webhook común de ventas y se despacha según `metadata.modulo`.

**Ejemplo de aprobación.** En `POST cotizaciones/64/aprobar/`, el Admin envía `{"monto_oficial":"1000.01"}`. Si aprueba el 1 de diciembre y el primer montaje es el 1 de enero, la respuesta con los parámetros predeterminados es:

```json
{
  "cotizacion_id": 64,
  "estado": "PRE_RESERVADO",
  "monto_oficial": "1000.01",
  "esquema_pago": "50_50",
  "monto_anticipo": "500.01",
  "saldo": "500.00",
  "pre_reserva_expira_en": "2026-12-03T10:00:00-06:00",
  "corte_saldo_en": "2026-12-11T23:59:59-06:00"
}
```

**Pago tardío de renta.** Si la fecha se ocupó, procede la devolución íntegra. Si sigue libre, queda retenida hasta 72 h por defecto en `PAGO_EXTEMPORANEO_EN_REVISION`. Aceptar confirma la renta; rechazar o agotar las 72 h libera el bloque y activa la devolución. Para tarjeta corresponde reembolso vía Stripe; para ficha, `REEMBOLSO_BANCARIO_PENDIENTE` y atención externa por Admin. Un saldo acreditado después de incumplir D-21 también se devuelve íntegro.

**Publicación y cambios.** En arrendamientos, el límite para publicar es el menor entre el inicio del primer bloque y el mayor de D−15 y pago inicial + 3 días naturales. El atraso genera recordatorios; `VENCIDO_SIN_PUBLICAR` mantiene la reserva hasta resolución. Al incumplir el saldo D−21 se detiene la venta y se invalidan los QR; la liberación de agenda es explícita. Las reprogramaciones se aplican atómicamente, conservan la identidad de la función y de los boletos y recalculan los cortes aplicables.

**Cancelación.** Si el arrendatario solo cubrió el anticipo, se retiene. Si cubrió el total y faltan al menos 21 días, se retiene el 50 % y el resto se gestiona externamente; con menor anticipación se retiene el total. Cancelación por el teatro permite elegir devolución externa íntegra o reprogramación sin costo. El arrendatario dispone de una reprogramación gratuita si la solicita con al menos 21 días y hay disponibilidad. Si la nueva fecha queda a menos de 21 días y solo se cubrió el anticipo, se exige liquidar el total antes de confirmar el cambio. Fuera de las condiciones de reprogramación aplica cancelación y nueva solicitud. Al reprogramar una función con boletos se conservan su id, inventario, folios y QR, se registra el horario anterior y se notifica a compradores con cuenta. Las devoluciones administrativas se distinguen de los reembolsos técnicos gestionados por Stripe.

## 7. Auditoría, monitoreo y aceptación

| Método y ruta | Acceso y entrada | Respuesta y reglas |
| :--- | :--- | :--- |
| `GET auditoria/registros/` | A; filtros por módulo, actor e intervalo | `200` con acción, instante, recurso y resultado paginados. El servidor registra ajustes y transiciones. |
| `GET health/` | Monitoreo interno | `200` con `status, database, redis` en `ok`; `503` con `status: degraded` y la dependencia afectada en `error`. |

| Caso que deben probar los equipos | Resultado verificable desde el cliente |
| :---- | :---- |
| Dos sesiones apartan simultáneamente la misma butaca | Una recibe 200 y la otra 409. Ningún carrito cobra localidades ajenas. |
| Se apartan dos asientos y uno acaba de venderse | 409 con el conflicto y cero nuevos asientos retenidos en ese lote. |
| El usuario ya compró nueve e intenta apartar dos más | 409 LIMITE_BOLETOS. El contador acumula compras por cuenta y función. |
| Se recibe dos veces el webhook de una compra | Una orden pagada y un boleto por localidad. El segundo envío confirma recepción. |
| Dos puertas escanean simultáneamente el mismo boleto | Un acceso 200 y un 409 con la hora del primer ingreso. |
| Un usuario pide el PDF de otro o intenta operar taquilla | 403. El cuerpo carece de datos del tercero. |
| Dos revisores aprueban intervalos incompatibles | Una pre-reserva completa y un 409. El montaje también participa en el cruce. |
| Se reprograma una función vendida y el nuevo bloque está ocupado | 409 y se conserva la programación anterior. |
| Se edita un precio de renta después de aprobar | El desglose y el monto aprobados conservan sus valores. |
| Aprobación a 30 y 31 días de la primera ocupación | Con parámetros por defecto, 100 % a 30 días y 50/50 a 31. Se cuenta el montaje previo. |
| Cambio de fase con carrito vigente | La primera butaca conserva su precio; una nueva toma el de la nueva fase. Se conserva el vencimiento. |
| Cambio de fase sin ventas | El sondeo devuelve 200 con la nueva fase y el mapa actualiza sus precios. |
| Pago de boletos después de expirar | Se reasigna solo si se cumplen las tres condiciones de ME-03 T-3.7. Si falla alguna, reembolso íntegro. |
| QR de otra función y folio inexistente | 409 OTRA_FUNCION y 404 BOLETO_NO_ENCONTRADO, respectivamente. Ningún intento registra ingreso. |
| Vencimiento de la revisión de un pago tardío de renta | Se libera la fecha y se distingue reembolso de tarjeta de devolución bancaria pendiente. |
