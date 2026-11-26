# Informe de cambios al modelo de datos (v5.3 → v6.1)

* **Proyecto:** Plataforma de boletaje y cotización de arrendamiento del Teatro de la Ciudad de Coatzacoalcos.
* **Estado del modelo:** propuesta v6.1 para revisión del equipo (sustituye al ER v5.3 como base para `models.py` una vez aprobada).
* **Fecha del informe:** 2026-11-25.
* **Responsable de criterios de diseño:** Sanji.

---

## 1. Introducción

Este informe explica qué cambió entre el diagrama entidad-relación v5.3, que la auditoría EGM dictaminó **NO LISTO / BLOQUEADO**, y el modelo relacional v6.1. Describe el problema que resolvía cada cambio, los criterios de diseño impuestos por Sanji y el diccionario de datos completo de las 43 tablas del modelo.

Documentos de referencia (rutas relativas a la raíz del proyecto):

* `docs/modelo-datos.md`: modelo relacional v6.1. Es la **fuente principal**; el diccionario está en su sección 4 y las decisiones en las secciones 1, 5, 6 y 7.
* `docs/reportes/auditoria-egm-er-v5.3.md`: auditoría del ER v5.3, con los hallazgos `ER-C01` a `ER-C06` (críticos), `ER-I01` a `ER-I06` (altos) y `ER-M01` a `ER-M05` (medios).
* `docs/alcance.md`: alcance funcional del sistema. La sección 2.3 fue reescrita para la v6.1.
* `docs/modelado_datos/Teatro_MR_v6.1.drawio`: modelo relacional completo en draw.io.
* `docs/modelado_datos/Teatro_ER_Chen_v6.1.drawio`: diagrama entidad-relación en notación Chen.

### Convenciones de lectura del diccionario

* Nombres de tabla y columna en `snake_case`, sin acentos. Importes en `NUMERIC(10,2)` MXN; instantes en `TIMESTAMPTZ` (UTC); enumeraciones como `TEXT` con `CHECK`.
* **PK** llave primaria, **FK** llave foránea, **UQ** único, **N** admite nulo. Las columnas sin **N** son `NOT NULL`, según la notación de la fuente.
* **—** significa que la fuente no declara ese dato (por ejemplo, el tipo de una columna descrita solo en prosa). No se inventó ningún tipo ni restricción.
* Toda FK es `ON DELETE PROTECT`, porque no hay borrado físico de nada contable.

---

## 2. Resumen de cambios respecto a la v5.3 y a la auditoría

La v5.3 se auditó contra `alcance.md` y `arquitectura.md`. Los tres problemas de fondo fueron: sobre-normalización (30 entidades frente a las 13 entidades nucleares de la arquitectura), bloqueantes de concurrencia y arquitectura (fragmentación de la orden, acoplamiento de la agenda, webhooks no idempotentes) y omisiones de negocio (turnos, 50/50, LFPDPPP, cortesías, contingencia y restricciones de PostgreSQL). La tabla siguiente resume cómo responde la v6.1 a cada hallazgo.

| Hallazgo (auditoría) | Problema en la v5.3 | Respuesta en la v6.1 | Tablas principales |
| :---- | :---- | :---- | :---- |
| ER-C01 | La orden se partía en `Carrito`, `DetalleCarrito`, `Transaccion` y `Detalle_Transaccion`, con tres estados desconectados. Exigía cuenta para la taquilla. | Una sola `orden_compra` con todo el ciclo. | `orden_compra`, `orden_compra_detalle`, `pago_orden` |
| ER-C02 | Geometría tarifaria ausente, anti-patrón `Asiento_evento`, `Asiento.estado` en el catálogo físico. | Catálogo físico sin estado, sección del evento sin precio, precio por sección y fase, disponibilidad por función. | `butaca`, `seccion_evento`, `asignacion_butaca`, `fase_venta`, `precio_seccion`, `disponibilidad_butaca` |
| ER-C03 | `Ocupación_teatro` tenía FKs hacia el dominio (viola ADR-07), usaba `inicio` y `fin` separados y no admitía varias funciones por bloque. | `bloqueo_agenda` con rango `TSTZRANGE` y exclusión por sala, sin FKs hacia el dominio. | `sala`, `bloqueo_agenda` |
| ER-C04 | `Notificación_pago` no tenía PK de evento ni estados, y el `Pago` obligatorio impedía registrar eventos fallidos. Las referencias Stripe colisionaban. | `webhook_stripe` idempotente con `stripe_event_id` como PK; pagos separados por módulo con llaves de idempotencia. | `webhook_stripe`, `pago_orden`, `pago_arrendamiento`, `ficha_pago`, `reembolso_orden`, `reembolso_arrendamiento` |
| ER-C05 | No existía `Turno`. `Configuracion_sistema` y `Registro_auditoría` estaban incompletos y aislados. | Catálogo `turno`, configuración singleton completa y auditoría conectada al actor. | `turno`, `configuracion_sistema`, `registro_auditoria` |
| ER-C06 | Faltaban restricciones físicas de PostgreSQL, precisión monetaria y temporal, e índices únicos parciales. | Tipos, `CHECK`, índices únicos parciales y `EXCLUDE` declarados por tabla. | Todas |
| ER-I01 | `Evento` y `Funcion` no cubrían eventos directos, reprogramaciones, vencimientos ni contingencia. Las horas se guardaban sin fecha. | Origen directo o arrendamiento, `inicio_en` y `fin_en` en UTC, e historiales en tablas propias. | `evento`, `funcion`, `reprogramacion_funcion`, `resolucion_vencimiento`, `contingencia_funcion`, `bloque_evento_directo` |
| ER-I02 | Faltaban el esquema 50/50, el corte D-21, los pagos extemporáneos de 72 h, las cancelaciones y el SLA. | Cuotas, snapshot de parámetros, fichas, revisión extemporánea y cancelaciones en tablas propias. | `cotizacion`, `cotizacion_parametros`, `cuota_arrendamiento`, `pago_arrendamiento`, `ficha_pago`, `revision_pago_extemporaneo`, `cancelacion_arrendamiento` |
| ER-I03 | `Boleto` no conservaba los invalidados y no separaba cortesías. | Cortesía como subtipo, invalidación sin borrar, un boleto vigente por butaca mediante índice parcial. | `boleto`, `cortesia` |
| ER-I04 | `Usuario` no tenía aceptación LFPDPPP ni `session_version`, y faltaban los campos de Django. | `aceptacion_legal` con versión, y campos de sesión y Django en `usuario`. | `usuario`, `aceptacion_legal` |
| ER-I05 | Cardinalidades imprecisas o invertidas, y nombres que no coincidían con el glosario. | Nombres alineados al glosario y tabla de equivalencias (§7 de la fuente). | Todas |
| ER-I06 | Once flujos de negocio no se podían inferir del diagrama. | Los flujos quedan representados en tablas propias (ver el diccionario); la fuente no los matriza uno por uno. | Ver §5, observaciones |
| ER-M01 | Entidades y atributos fuera de alcance (`Artista_Organizacion`, cargos por servicio, paquetes, `codigo_barras`, país, código postal). | Eliminados. Cupones, cartera y métodos de pago guardados quedan fuera de alcance. | — |
| ER-M03 | Sobre-normalización frente al plazo de 4 semanas y 6 integrantes. | No se adopta; ver la sección 3.1. | — |

### 2.1 Orden de compra única (`orden_compra` + `orden_compra_detalle`)

**Problema (ER-C01).** La v5.3 dividía la orden en cuatro entidades. El estado se repartía entre `Carrito.estatus`, `Transaccion.estado` y `Pago.estado`, lo que obligaba a sincronizarlos. Además, la relación `Usuario [1] --- (Posee) --- [N] Carrito` exigía cuenta para vender en taquilla, contra el alcance §2.7 y ADR-06. Tampoco había gracia de 5 minutos, ni índice único para un carrito activo por usuario.

**Solución en v6.1.** `orden_compra` es un único objeto que pasa por `APARTADO → PAGO_EN_PROCESO → PAGADA` (o por `EXPIRADA` y `REEMBOLSADA_AUTOMATICA`). Un `CHECK` exige `usuario_id` para el canal `LINEA` y `cajero_id` para `TAQUILLA`. Un índice único parcial limita a una orden activa por usuario en línea. El total no se guarda: es la suma del detalle, y lo cobrado queda en `pago_orden.monto`.

**Tabla intermedia `orden_compra_detalle`.** La auditoría proponía enlazar `disponibilidad_butaca` directamente con la orden. La v6.1 conserva la tabla intermedia porque, al expirar una orden, la butaca vuelve a `DISPONIBLE` y se perdería qué butacas tenía la orden. Ese dato es necesario para reasignar butacas si llega un pago tardío (alcance §2.10.A). Además guarda `precio_unitario` (copia del precio al apartar) y `fase_venta_id` (fase vigente al apartar).

### 2.2 Agenda con anti-traslape (`sala`, `bloqueo_agenda`)

**Problema (ER-C03).** `Ocupación_teatro` contenía `reserva_id` y apuntaba a `Reserva_renta`, `Opción_Fecha` y `Funcion`. Eso viola ADR-07, que prohíbe importaciones inversas desde `agenda` hacia el dominio. Además separaba `inicio` y `fin`, y no permitía varias funciones dentro de un bloque `RENTA`.

**Solución en v6.1.** `bloqueo_agenda` guarda `sala_id`, `rango` (`TSTZRANGE`, intervalo semiabierto `[inicio, fin)` en UTC), `origen` (`FUNCION`, `RENTA`, `MANTENIMIENTO`), `estado` (`PROPUESTA_RETENIDA`, `PRE_RESERVADO`, `CONFIRMADO`, `LIBERADO`), `etiqueta` y `expira_en`. No conoce eventos ni cotizaciones: los módulos de dominio (`funcion`, `bloque_solicitado`, `opcion_propuesta`, `bloque_evento_directo`) apuntan hacia ella.

**Restricción de exclusión en PostgreSQL.** Se usa la extensión `btree_gist` con `EXCLUDE USING gist (sala_id WITH =, rango WITH &&) WHERE (estado <> 'LIBERADO')`. Así no hay empalmes dentro de una misma sala, y dos salas distintas sí pueden ocuparse a la misma hora. Una segunda restricción exige que `expira_en` esté lleno solo en los estados retenidos (48 h).

### 2.3 Webhooks de Stripe idempotentes (`webhook_stripe`)

**Problema (ER-C04).** `Notificación_pago` no tenía PK de evento ni estado, y exigía un `Pago` obligatorio. Eso impedía guardar el evento como `PENDIENTE` antes de `transaction.on_commit()` y registrar fallos como `payment_intent.payment_failed`. El `Pago` colapsaba todo en `ref_pago_externa`, donde colisionaban `pi_xxx` y `re_xxx`.

**Solución en v6.1.** `webhook_stripe` usa `stripe_event_id` como PK, de modo que la base impide procesar dos veces el mismo evento. Guarda `tipo_evento`, `modulo` (tomado de `metadata.modulo`: `VENTAS` o `COTIZACIONES`), `payload` (JSONB), `estado` (`PENDIENTE`, `PROCESADO`, `FALLIDO`), `recibido_en` y `procesado_en`. El enlace con el pago es lógico, por `payment_intent_id` de tipo texto y sin FK, para que `ventas` no dependa de `cotizaciones`.

**Pagos separados por módulo.** En lugar de un `Pago` con FK XOR, existen `pago_orden` (ventas) y `pago_arrendamiento` (cotizaciones). Cada una tiene llaves de idempotencia y un `CHECK` que exige los identificadores de Stripe cuando el método es tarjeta. Las fichas SPEI y efectivo se modelan en el subtipo `ficha_pago`.

### 2.4 Turnos (`turno`)

**Problema (ER-C05).** No había catálogo de turnos. `Bloque_solicitado` no tenía `turno_id`, y cada línea cotizada obligaba a asociar un `Servicio`, lo que impedía desglosar la renta base por turno o marcar montaje y ensayos en `$0.00`.

**Solución en v6.1.** `turno` guarda `codigo` (`MATUTINO`, `VESPERTINO`, `DIA_COMPLETO`), `nombre`, `hora_inicio`, `hora_fin`, `tarifa_renta` (`CHECK >= 0`) y `activo`. Lo usan `bloque_solicitado.turno_id` y `opcion_propuesta.turno_id`. La renta por turno vive en `bloque_solicitado.tarifa_aplicada` (snapshot), así que `cotizacion_servicio` no necesita un `servicio_id` opcional.

### 2.5 LFPDPPP y avisos legales (`aceptacion_legal`)

**Problema (ER-I04).** `Usuario` no registraba la aceptación obligatoria del Aviso de Privacidad y los Términos, y no tenía `session_version` para revocar sesiones de forma inmediata en Redis.

**Solución en v6.1.** `aceptacion_legal` es un historial con `documento` (`AVISO_PRIVACIDAD`, `TERMINOS`), `version` (por ejemplo `2026-11`), `aceptado_en` e `ip_origen`. La restricción `UQ (usuario_id, documento, version)` permite volver a pedir aceptación cuando cambia la versión del aviso. En `usuario` se agregan `session_version`, `is_staff`, `is_superuser`, `last_login` y las marcas de tiempo.

### 2.6 Otros cambios relevantes (secciones 5 y 6 de `modelo-datos.md`)

* **Inventario y precios (ER-C02).** `Asiento_evento` se sustituye por `asignacion_butaca`, cuya PK `(evento_id, butaca_id)` impide que una butaca esté en dos secciones del mismo evento. `butaca` pierde `estado` y gana `fila_orden`, `columna` y `palco_id`. `seccion_evento` no guarda precio. `fase_venta` y `precio_seccion` reemplazan el precio por sección, y `disponibilidad_butaca` consolida `Funcion_asiento`.
* **Eventos y funciones (ER-I01).** `evento` distingue el origen (`ARRENDAMIENTO` o `DIRECTO`) y agrega `creado_por_id`, `fecha_limite_publicacion` y `proximo_recordatorio_en`. `funcion` reemplaza `fecha_hora` por `fecha`, `inicio_en` y `fin_en`, con un `EXCLUDE` que impide traslapes entre funciones del mismo evento. Las reprogramaciones, las resoluciones de vencimiento y la contingencia pasan a tablas de historial.
* **Arrendamiento (ER-I02).** `cotizacion` absorbe `Solicitud_Renta`, `Cotización` y `Reserva_renta`, porque las tres estaban en relación 1:1 y compartían un ciclo de estados. Se agregan `cotizacion_parametros` (snapshot al aprobar), `cuota_arrendamiento` (con `tipo` y `fecha_limite_ficha`), `pago_arrendamiento`, `reembolso_arrendamiento`, `revision_pago_extemporaneo` y `cancelacion_arrendamiento`. `propuesta_fecha` y `opcion_propuesta` manejan hasta 3 fechas alternativas (`CHECK BETWEEN 1 AND 3`).
* **Boletos (ER-I03).** `boleto` usa `token` (UUID, firmado con `QR_HMAC_SECRET`) y `folio_corto`. Conserva los boletos invalidados. Un índice único parcial permite un solo boleto vigente por butaca y función. Un `CHECK` exige `orden_detalle_id` solo cuando el origen es `COMPRA`. `cortesia` es un subtipo con sus atributos propios.
* **Datos derivados eliminados (regla §1.3).** Se quitan `congelada`, `habilitada`, `saldo_restante`, `estado_liquidacion`, `atrasada`, `reprogramacion_gratuita_usada`, el total de la orden y el precio impreso en el boleto. Lo que una tarea periódica necesita indexar, como `expira_en`, sí se guarda.
* **Historia en lugar de sobrescribir (regla §1.5).** Reprogramaciones, bloqueos técnicos, prórrogas y contingencias se guardan como filas. Antes se perdía el valor anterior al pisarlo.
* **Restricciones físicas (ER-C06).** Todas las FKs compuestas y los índices parciales se declaran en el diccionario. Se usa `NUMERIC(10,2)` para importes y `TIMESTAMPTZ` en UTC para instantes.

### 2.7 Apartamientos deliberados frente a la auditoría

La fuente indica estos apartamientos de forma explícita:

* **A.** `orden_compra_detalle` se conserva (la auditoría la quería eliminar).
* **B.** `asignacion_butaca` se conserva (la auditoría pedía eliminar `Asiento_evento`).
* **C.** Historiales en tablas propias: `bloqueo_tecnico`, `reprogramacion_funcion`, `resolucion_vencimiento`, `contingencia_funcion` y `aceptacion_legal`.
* **D.** Subtipos en tablas propias: `cortesia`, `ficha_pago`, `cotizacion_parametros`, `cancelacion_arrendamiento` y `revision_pago_extemporaneo`.
* **E.** `cotizacion_servicio` no tiene `servicio_id` opcional.
* **F.** Pagos separados por módulo (`pago_orden` y `pago_arrendamiento`).
* **G.** Se quitan los datos derivados mencionados arriba.

---

## 3. Criterios de diseño impuestos por Sanji

### 3.1 Normalizar con tablas intermedias y subtipos, no reducir el número de tablas

Sanji fijó como criterio la normalización (3FN) antes que el número de tablas. La auditoría sugería entre 16 y 18 tablas (o 23 en su variante normalizada). La v6.1 tiene **43 tablas**, porque se conservaron:

* **Tablas intermedias N:M o de relación fina:** `asignacion_butaca` (butaca ↔ evento) y `orden_compra_detalle` (orden ↔ butaca de la función). `precio_seccion` (fase ↔ sección del evento) también es una tabla intermedia.
* **Historiales:** `bloqueo_tecnico`, `reprogramacion_funcion`, `resolucion_vencimiento`, `contingencia_funcion`, `aceptacion_legal`, `cuota_arrendamiento` y los pagos de arrendamiento, porque un hecho que se repite en el tiempo debe conservar su historia.
* **Subtipos en tablas propias:** `cortesia`, `ficha_pago`, `cotizacion_parametros`, `cancelacion_arrendamiento` y `revision_pago_extemporaneo`, porque cada uno tiene 3 o más atributos exclusivos, o historia propia.

La regla de la fuente es que un subtipo con 1 o 2 columnas se queda como columnas nullable con un `CHECK` (por ejemplo, `orden_compra.usuario_id` y `cajero_id`). Los nulos de ciclo de vida (`usado_en`, `pagada_en`) también se quedan en la tabla.

Las 13 entidades nucleares de `arquitectura.md` se mantienen como **agregados de dominio**, y cada una puede ocupar varias tablas. Por ejemplo, Boleto ocupa `boleto` y `cortesia`.

### 3.2 `fase_venta` y `precio_seccion`: precio por fecha de compra

El precio depende de dos dimensiones independientes:

* **Sección del evento** (variación por zona): la define cuántas filas tiene `seccion_evento`.
* **Fase de venta** (variación por fecha de compra): la define cuántas filas tiene `fase_venta`. Una fase es un periodo consecutivo con nombre y `inicia_en`. Dura hasta que inicia la siguiente, y la última dura hasta el cierre de venta. La fase aplica a todas las funciones del evento y se decide por el momento en que el comprador aparta, no por la fecha de la función.

`precio_seccion` es el cruce de ambas dimensiones: siempre tiene `secciones × fases` filas. Su restricción `CHECK (precio >= 100.00)` fija el piso comercial del recinto.

**Ejemplo real que cubre la fuente (caso Marco Barrientos).** Precio único que cambia por fecha: `$350` en septiembre y octubre, y `$500` en noviembre. El evento tiene una sola sección del evento ("General") con todas las butacas, y dos fases: "Preventa" desde el 1 de septiembre y "General" desde el 1 de noviembre. `precio_seccion` tiene dos filas, con `$350` y `$500`.

Los cuatro casos que cubre el modelo son:

| Caso | `seccion_evento` | `fase_venta` | `precio_seccion` |
| :---- | :---- | :---- | :---- |
| 0. Precio único fijo | 1: "General" con las 1,728 butacas | 1: "Venta general" | 1 fila |
| 1. Precio único que cambia por fecha (Marco Barrientos) | 1: "General" | 2: "Preventa" y "General" | 2 filas: $350 y $500 |
| 2. Precio por sección, fijo todo el periodo | N secciones | 1: "Venta general" | N filas |
| 3. Precio por sección y por fecha | N | M | N × M filas |

Otros puntos de diseño que indica la fuente:

* **Valores por defecto del configurador.** Al abrir el configurador se crean una fase ("Venta general", desde la publicación) y una sección del evento por cada sección física. El usuario agrega fases solo si el precio cambia por fecha.
* **Sin columnas opcionales de precio.** No se usan `evento.precio_unico` ni `fase_venta_id` nulo, porque habría dos lugares posibles para el precio. Con una sola regla (precio = cruce de sección y fase vigente), el cálculo siempre usa el mismo `JOIN`.
* **Congelamiento.** Fases, fechas de inicio y precios quedan congelados al publicar el evento, igual que las secciones (alcance §2.3).

### 3.3 `sala` se conserva para la expansión futura

Sanji pidió conservar `sala`. Hoy hay una sola fila (Teatro de la Ciudad), con `aforo` de 1,728 que sirve de tope de asistentes en cotizaciones. El modelo la usa como raíz de `seccion`, `evento`, `cotizacion` y `bloqueo_agenda`, y las restricciones anti-empalme son por sala. Así el inmueble puede anexar otra sala o salón con venta de boletos sin rediseñar la base.

El costo es una columna `sala_id` de enlace en `butaca` y en `asignacion_butaca`, para que PostgreSQL valide que la butaca pertenece a la sala del evento. Las tarifas de turno y los parámetros siguen siendo globales. Si una sala nueva tuviera tarifas propias, `turno` recibiría un `sala_id`.

### 3.4 Secciones del evento que agrupan o dividen secciones físicas

Sanji pidió que las secciones del evento puedan agrupar o partir secciones físicas. Se evaluaron tres opciones:

| Opción | Qué permite | Ventaja | Problema |
| :---- | :---- | :---- | :---- |
| A. Precio directo a la sección física | Solo las 6 secciones tal cual | La más simple | No parte una sección grande ni agrupa |
| B. Subsecciones dentro de una sección física (v6.0) | Dividir, no agrupar | La base impide mezclar secciones | No permite "Palmeras" (4 lunetas) |
| C. Sección del evento libre con asignación por butaca (v6.1, recomendada) | Dividir **y** agrupar | Misma tabla para ambos casos; la PK de `asignacion_butaca` impide solapamientos | Las reglas de forma se validan en el servicio, no en la base |

Con la opción C, `seccion_evento` no tiene `seccion_id`: es una sección lógica con `evento_id`, `nombre` y `orden`. Una sección física deshabilitada simplemente no tiene butacas asignadas. El servicio del configurador valida antes de escribir que:

* Una sección del evento sea la unión de secciones físicas completas, o un bloque rectangular dentro de una sola sección física (usando `fila_orden` y `columna`).
* En Palcos solo se asignen cabinas completas.
* No haya más de 6 divisiones por sección física.
* El 100% de cada sección física habilitada esté cubierto (compuerta de publicación).

---

## 4. Diccionario de datos

Organizado por módulo, igual que la sección 4 de `modelo-datos.md`. Son 43 tablas en 9 módulos.

| Módulo | Tablas |
| :---- | :---- |
| `usuarios` | `usuario`, `aceptacion_legal` |
| `configuracion` (transversal) | `configuracion_sistema`, `turno`, `servicio_extra` |
| `agenda` (transversal) | `sala`, `bloqueo_agenda` |
| `auditoria` (transversal) | `registro_auditoria` |
| `cartelera` | `categoria`, `evento`, `bloque_evento_directo`, `funcion`, `reprogramacion_funcion`, `resolucion_vencimiento` |
| `inventario` | `seccion`, `palco`, `butaca`, `seccion_evento`, `asignacion_butaca`, `fase_venta`, `precio_seccion`, `disponibilidad_butaca`, `bloqueo_tecnico` |
| `ventas` | `orden_compra`, `orden_compra_detalle`, `pago_orden`, `reembolso_orden`, `webhook_stripe` |
| `boletos` | `boleto`, `cortesia`, `contingencia_funcion` |
| `cotizaciones` | `cotizacion`, `cotizacion_parametros`, `bloque_solicitado`, `cotizacion_servicio`, `propuesta_fecha`, `opcion_propuesta`, `cuota_arrendamiento`, `pago_arrendamiento`, `ficha_pago`, `reembolso_arrendamiento`, `revision_pago_extemporaneo`, `cancelacion_arrendamiento` |

### 4.1 Módulo `usuarios`

#### `usuario`

**Propósito:** cuenta de acceso de todas las personas del sistema (Usuario estándar, Admin, Cajero y Verificador). Extiende `AbstractBaseUser` y `PermissionsMixin` de Django. Cada cuenta tiene un solo rol.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador de la cuenta |
| correo | TEXT | UQ (insensible a mayúsculas) | Login |
| password | TEXT | — | Hash Argon2 |
| nombre | TEXT | — | Nombre de la persona |
| apellidos | TEXT | — | Apellidos |
| telefono | TEXT | N | Teléfono de contacto |
| rol | TEXT | — | Dominio cerrado: `ADMIN`, `CAJERO`, `VERIFICADOR`, `USUARIO` |
| is_active | BOOLEAN | — | Suspensión de cuenta |
| is_staff | BOOLEAN | — | Requerido por Django |
| is_superuser | BOOLEAN | — | Requerido por Django |
| session_version | INTEGER | — | Se incrementa para revocar sesiones en Redis |
| last_login | TIMESTAMPTZ | N | Último inicio de sesión |
| creado_en | TIMESTAMPTZ | — | Fecha de creación |
| actualizado_en | TIMESTAMPTZ | — | Última modificación |

#### `aceptacion_legal`

**Propósito:** historial de aceptación del Aviso de Privacidad y los Términos, exigido por la LFPDPPP. Permite volver a pedir aceptación cuando cambie la versión del aviso o de los términos.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| usuario_id | BIGINT | FK → `usuario` | Usuario que acepta |
| documento | TEXT | — | `AVISO_PRIVACIDAD`, `TERMINOS` |
| version | TEXT | — | Versión aceptada, por ejemplo `2026-11` |
| aceptado_en | TIMESTAMPTZ | — | Instante de la aceptación |
| ip_origen | INET | N | IP desde la que se aceptó |

Restricciones de tabla: UQ (`usuario_id`, `documento`, `version`).

### 4.2 Módulo `configuracion` (transversal)

#### `configuracion_sistema`

**Propósito:** fila única con los parámetros operativos editables del sistema, cada uno con su valor por defecto. Los cambios se auditan y no afectan registros ya emitidos, porque cada consumidor guarda su propio snapshot.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | — | CHECK (id = 1) | Fila única del singleton |
| apartado_min | — | — | Minutos de apartado temporal de butacas en carrito y taquilla. Valor por defecto: 10 |
| gracia_pago_min | — | — | Minutos de gracia por pago en proceso. Valor por defecto: 5 |
| cierre_web_min | — | — | Minutos antes de la función en que cierra la venta en línea. Valor por defecto: 30 |
| cierre_taquilla_min | — | — | Minutos antes de la función en que cierra la taquilla. Valor por defecto: 0 |
| prereserva_h | — | — | Horas de vigencia de PRE_RESERVADO para el pago inicial. Valor por defecto: 48 |
| propuesta_h | — | — | Horas de vigencia de PROPUESTA_RETENIDA. Valor por defecto: 48 |
| revision_extemporanea_h | — | — | Horas de revisión de un pago extemporáneo. Valor por defecto: 72 |
| limite_publicacion_d | — | — | Días naturales antes de la primera fecha reservada para la fecha límite de publicación. Valor por defecto: 15 |
| recordatorio_d | — | — | Días naturales entre recordatorios de requisitos pendientes. Valor por defecto: 7 |
| corte_saldo_d | — | — | Días naturales antes de la primera fecha reservada para el corte D-21 del saldo. Valor por defecto: 21 |
| margen_50_50_d | — | `> 0` (ver restricciones de tabla) | Margen en días naturales sobre el corte, para habilitar 50/50. Valor por defecto: 9 |
| retencion_cancelacion_pct | — | — | Porcentaje retenido en cancelación con pago total. Valor por defecto: 50.00 |
| reprogramacion_minima_d | — | — | Días naturales mínimos para reprogramación gratuita. Valor por defecto: 21 |
| sla_respuesta_dh | — | — | SLA de primera respuesta a una cotización, en días hábiles. Valor por defecto: 3 |
| sla_atraso_dh | — | — | Umbral de solicitud atrasada, en días hábiles. Valor por defecto: 5 |
| limite_boletos | — | — | Límite de boletos por cuenta y función, y por operación en taquilla. Valor por defecto: 10 |
| actualizado_por_id | BIGINT | FK → `usuario`, N | Último usuario que modificó la configuración |
| actualizado_en | — | — | Instante de la última modificación |

Restricciones de tabla: `CHECK (id = 1)`. `CHECK` de valores positivos en los parámetros, incluido `margen_50_50_d > 0`, que garantiza que el umbral de 50/50 sea mayor que el corte.

#### `turno`

**Propósito:** catálogo oficial de turnos de renta (Matutino, Vespertino y Día Completo), con su horario y su tarifa base.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| codigo | TEXT | UQ | `MATUTINO`, `VESPERTINO`, `DIA_COMPLETO` |
| nombre | TEXT | — | Nombre visible del turno |
| hora_inicio | TIME | — | Horario oficial de inicio |
| hora_fin | TIME | — | Horario oficial de fin |
| tarifa_renta | NUMERIC(10,2) | `CHECK (>= 0)` | Tarifa base de renta |
| activo | BOOLEAN | — | Indica si el turno está disponible para cotizar |

#### `servicio_extra`

**Propósito:** catálogo de extras e infraestructura escénica que se pueden cotizar en un arrendamiento. Se desactiva, nunca se borra.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| nombre | TEXT | UQ | Nombre del servicio |
| descripcion | TEXT | N | Descripción |
| tipo_concepto | TEXT | — | `EXTRA`, `INFRAESTRUCTURA` |
| unidad_cobro | TEXT | — | `POR_EVENTO`, `POR_DIA`, `POR_TURNO`, `POR_UNIDAD` |
| precio_referencia | NUMERIC(10,2) | `CHECK (>= 0)` | Precio base referencial, neto en MXN |
| activo | BOOLEAN | — | Se desactiva, nunca se borra |

### 4.3 Módulo `agenda` (transversal)

#### `sala`

**Propósito:** raíz de la estructura física y recurso que se reserva en la agenda. Hoy existe una sola fila (Teatro de la Ciudad), pero el modelo admite anexar otra sala o salón con venta de boletos sin rediseñar.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| nombre | TEXT | UQ | Nombre de la sala |
| aforo | INTEGER | `CHECK (aforo > 0)` | 1,728 para el teatro; tope de asistentes en cotizaciones |
| activa | BOOLEAN | — | Indica si la sala está en operación |

#### `bloqueo_agenda`

**Propósito:** intervalo reservado en la agenda de una sala, ya sea por una función, una renta o un mantenimiento. No conoce eventos ni cotizaciones (ADR-07): los módulos de dominio apuntan hacia esta tabla, nunca al revés.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| sala_id | BIGINT | FK → `sala` | Sala que se reserva |
| rango | TSTZRANGE | — | Intervalo semiabierto `[inicio, fin)` en UTC |
| origen | TEXT | — | `FUNCION`, `RENTA`, `MANTENIMIENTO` |
| estado | TEXT | — | `PROPUESTA_RETENIDA`, `PRE_RESERVADO`, `CONFIRMADO`, `LIBERADO` |
| etiqueta | TEXT | — | Texto corto para el calendario |
| expira_en | TIMESTAMPTZ | N | Solo en estados retenidos (48 h) |
| creado_en | TIMESTAMPTZ | — | Fecha de creación |
| actualizado_en | TIMESTAMPTZ | — | Última modificación |

Restricciones de tabla: extensión `btree_gist`. `EXCLUDE USING gist (sala_id WITH =, rango WITH &&) WHERE (estado <> 'LIBERADO')`. `CHECK ((estado IN ('PROPUESTA_RETENIDA','PRE_RESERVADO')) = (expira_en IS NOT NULL))`.

### 4.4 Módulo `auditoria` (transversal)

#### `registro_auditoria`

**Propósito:** bitácora de acciones relevantes del sistema. Es solo de inserción (*append-only*); se recomienda revocar `UPDATE` y `DELETE` al usuario de la aplicación sobre esta tabla. Es una referencia polimórfica (`entidad`, `entidad_id`) a propósito, porque el módulo transversal no puede tener FKs hacia módulos de dominio.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| actor_id | BIGINT | FK → `usuario`, N | Usuario que actúa; nulo cuando actúa el sistema o Celery |
| actor_rol | TEXT | N | Copia del rol del actor al momento de la acción |
| modulo | TEXT | — | Módulo que registra la acción. Ejemplos: `ventas`, `cotizaciones` |
| accion | TEXT | — | Ejemplos: `CORTESIA_EMITIDA`, `FUNCION_REPROGRAMADA` |
| entidad | TEXT | — | Nombre de la tabla afectada |
| entidad_id | BIGINT | — | Identificador del registro afectado |
| detalles | JSONB | — | Antes y después, y datos de contexto |
| ip_origen | INET | N | IP de origen |
| request_id | UUID | N | Identificador de la solicitud HTTP |
| creado_en | TIMESTAMPTZ | — | Instante de la acción |

### 4.5 Módulo `cartelera`

#### `categoria`

**Propósito:** catálogo fijo de categorías de evento. Se siembran las 7 categorías del alcance (§3.1).

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | — | PK | Identificador |
| nombre | — | UQ | Nombre de la categoría |

#### `evento`

**Propósito:** espectáculo o actividad del teatro, originado por un arrendamiento o registrado directamente por el Admin. Agrupa la modalidad, el póster, el ciclo de vida y la publicación.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| nombre | TEXT | — | Nombre del evento |
| descripcion | TEXT | N | Descripción |
| categoria_id | BIGINT | FK → `categoria` | Categoría del evento |
| sala_id | BIGINT | FK → `sala` | Sala donde se realiza |
| modalidad | TEXT | — | `COMERCIAL`, `PUBLICO`, `PRIVADO` |
| origen | TEXT | — | `ARRENDAMIENTO`, `DIRECTO` |
| cotizacion_id | BIGINT | FK → `cotizacion`, N, UQ | Solo si `origen = ARRENDAMIENTO` |
| creado_por_id | BIGINT | FK → `usuario` | Admin en directos; sistema en arrendamientos |
| poster | TEXT (ImageField) | N | Póster publicitario; obligatorio para publicar si no es Privado |
| estado | TEXT | — | `PENDIENTE_PUBLICACION`, `PUBLICADO`, `VENCIDO_SIN_PUBLICAR`, `OPERACION_SIN_CARTELERA`, `CANCELADO_POR_ARRENDATARIO`, `CANCELADO_POR_TEATRO`, `FINALIZADO` |
| fecha_limite_publicacion | TIMESTAMPTZ | N | Fecha límite para publicar; indexada para Celery Beat |
| proximo_recordatorio_en | TIMESTAMPTZ | N | Próximo recordatorio; indexada para Celery Beat |
| aprobado_por_id | BIGINT | FK → `usuario`, N | Admin que aprobó la publicación (ciclo de vida) |
| publicado_en | TIMESTAMPTZ | N | Instante de publicación (ciclo de vida) |
| cancelado_en | TIMESTAMPTZ | N | Instante de cancelación (ciclo de vida) |
| creado_en | TIMESTAMPTZ | — | Fecha de creación |
| actualizado_en | TIMESTAMPTZ | — | Última modificación |

Restricciones de tabla: `CHECK ((origen = 'ARRENDAMIENTO') = (cotizacion_id IS NOT NULL))`. `CHECK (estado <> 'PUBLICADO' OR modalidad = 'PRIVADO' OR poster IS NOT NULL)`. `UQ (id, sala_id)`, usado como destino de FKs compuestas. La función no guarda sala: la toma de su evento.

#### `bloque_evento_directo`

**Propósito:** bloques de agenda de un evento directo (función, montaje o mantenimiento). En arrendamientos los bloques se alcanzan por `cotizacion → bloque_solicitado`, así que no se duplican aquí.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| bloqueo_agenda_id | BIGINT | PK, FK → `bloqueo_agenda` | Bloque de agenda al que corresponde |
| evento_id | BIGINT | FK → `evento` | Evento directo al que pertenece el bloque |
| finalidad | TEXT | — | `EVENTO`, `MONTAJE_ENSAYO` |

#### `funcion`

**Propósito:** presentación específica de un evento, con fecha, hora de inicio y hora de fin, contenida en un bloque de agenda reservado. Es la unidad de venta de boletos y de control de acceso.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| evento_id | BIGINT | FK → `evento` | Evento al que pertenece |
| bloqueo_agenda_id | BIGINT | FK → `bloqueo_agenda` | Bloque `RENTA` o `FUNCION` que la contiene |
| fecha | DATE | — | Fecha operativa (local) |
| inicio_en | TIMESTAMPTZ | — | Instante de inicio |
| fin_en | TIMESTAMPTZ | `CHECK (fin_en > inicio_en)` | Instante de fin; cubre el cruce de medianoche |
| estado | TEXT | — | `PROGRAMADA`, `REPROGRAMADO`, `CANCELADA`, `CONCLUIDA` |
| creado_en | TIMESTAMPTZ | — | Fecha de creación |
| actualizado_en | TIMESTAMPTZ | — | Última modificación |

Restricciones de tabla: `UQ (id, evento_id)`, para FKs compuestas. `EXCLUDE USING gist (evento_id WITH =, tstzrange(inicio_en, fin_en) WITH &&) WHERE (estado <> 'CANCELADA')`, que impide que dos funciones del mismo evento se traslapen. Las horas locales se obtienen de `inicio_en` y `fin_en` convertidos a `America/Mexico_City`. Que la función quede dentro de su bloque lo valida `AgendaService`.

#### `reprogramacion_funcion`

**Propósito:** historial de reprogramaciones de una función. Hay una fila por cada cambio, para no perder las fechas anteriores si la función se reprograma más de una vez.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| funcion_id | BIGINT | FK → `funcion` | Función reprogramada |
| inicio_anterior | TIMESTAMPTZ | — | Inicio antes del cambio |
| fin_anterior | TIMESTAMPTZ | — | Fin antes del cambio |
| inicio_nuevo | TIMESTAMPTZ | — | Inicio después del cambio |
| fin_nuevo | TIMESTAMPTZ | — | Fin después del cambio |
| bloqueo_anterior_id | BIGINT | FK → `bloqueo_agenda` | Bloque anterior |
| bloqueo_nuevo_id | BIGINT | FK → `bloqueo_agenda` | Bloque nuevo |
| reprogramado_por_id | BIGINT | FK → `usuario` | Usuario que reprogramó |
| reprogramado_en | TIMESTAMPTZ | — | Instante del cambio |

#### `resolucion_vencimiento`

**Propósito:** historial de las decisiones del Admin sobre un evento en estado `VENCIDO_SIN_PUBLICAR`. La prórroga puede repetirse, por eso es un historial.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| evento_id | BIGINT | FK → `evento` | Evento resuelto |
| accion | TEXT | — | `APOYO_ADMIN`, `PRORROGA`, `OPERACION_SIN_CARTELERA`, `CANCELACION` |
| nueva_fecha_limite | TIMESTAMPTZ | N; `CHECK ((accion = 'PRORROGA') = (nueva_fecha_limite IS NOT NULL))` | Nueva fecha límite de publicación, solo en prórroga |
| resuelto_por_id | BIGINT | FK → `usuario` | Admin que resolvió |
| resuelto_en | TIMESTAMPTZ | — | Instante de la resolución |

### 4.6 Módulo `inventario`

#### `seccion`

**Propósito:** una de las 6 zonas físicas permanentes e inmutables del plano del recinto. Es estructura fija.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| sala_id | BIGINT | FK → `sala` | Sala a la que pertenece |
| nombre | TEXT | — | Luneta, Platea, Mezzanine, Primer Piso, Segundo Piso, Palcos |
| tipo | TEXT | — | `GRADERIA`, `PALCOS` |
| orden | SMALLINT | — | Orden de despliegue en el mapa |

Restricciones de tabla: `UQ (sala_id, nombre)`, `UQ (id, sala_id)`.

#### `palco`

**Propósito:** cabina de la sección Palcos. Es la unidad mínima de subdivisión de esa sección.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| seccion_id | BIGINT | FK → `seccion` | Sección a la que pertenece (Palcos) |
| codigo | TEXT | — | Código de la cabina, por ejemplo `P-07` |

Restricciones de tabla: `UQ (seccion_id, codigo)`, `UQ (id, seccion_id)`.

#### `butaca`

**Propósito:** catálogo físico permanente de las 1,728 butacas. No tiene estado: la disponibilidad depende de la función, y se guarda en `disponibilidad_butaca`.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| seccion_id | BIGINT | Parte de la FK compuesta de `sala_id` | Sección física |
| sala_id | BIGINT | FK compuesta (`seccion_id`, `sala_id`) → `seccion(id, sala_id)` | Columna de enlace |
| palco_id | BIGINT | N; FK compuesta (`palco_id`, `seccion_id`) → `palco(id, seccion_id)` | Cabina, si la butaca está en Palcos |
| fila | TEXT | — | Etiqueta impresa, por ejemplo `K` |
| fila_orden | SMALLINT | — | Posición numérica de la fila, para validar rectángulos |
| numero | SMALLINT | — | Número impreso |
| columna | SMALLINT | — | Posición numérica horizontal, para validar rectángulos |
| es_accesible | BOOLEAN | — | Silla de ruedas y acompañante |
| activa | BOOLEAN | — | Permite retirar una butaca física sin borrarla |

Restricciones de tabla: `UQ (seccion_id, fila, numero)`, `UQ (id, sala_id)`. `palco_id` es nullable porque es una sola columna; el servicio de siembra garantiza que toda butaca de Palcos tenga palco.

#### `seccion_evento`

**Propósito:** sección del evento, la sección lógica que ve el comprador (por ejemplo "Luneta", "Luneta - VIP" o "Palmeras"). Define la zona de precio y su nombre comercial. No guarda precio: el precio depende también de la fase de venta y vive en `precio_seccion`.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| evento_id | BIGINT | FK → `evento` | Evento al que pertenece |
| nombre | TEXT | `CHECK (btrim(nombre) <> '')` | Nombre único dentro del evento |
| orden | SMALLINT | — | Orden de despliegue en mapa, carrito y taquilla |

Restricciones de tabla: `UQ (evento_id, nombre)`, `UQ (id, evento_id)`. Puede agrupar varias secciones físicas completas o dividir una sección física en bloques (ver la sección 3.4).

#### `asignacion_butaca`

**Propósito:** asiento del evento. Indica a qué sección del evento pertenece cada butaca en cada evento. La PK garantiza que una butaca está en una sola sección por evento.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| evento_id | BIGINT | PK (1/2); parte de la FK compuesta (`evento_id`, `sala_id`) → `evento(id, sala_id)` | Evento |
| butaca_id | BIGINT | PK (2/2); FK compuesta (`butaca_id`, `sala_id`) → `butaca(id, sala_id)` | Butaca asignada |
| sala_id | BIGINT | — | Columna de enlace con la sala del evento |
| seccion_evento_id | BIGINT | FK compuesta (`seccion_evento_id`, `evento_id`) → `seccion_evento(id, evento_id)` | Sección del evento a la que pertenece la butaca |

Restricciones de tabla: PK (`evento_id`, `butaca_id`). El servicio del configurador valida antes de escribir las reglas de forma y de cobertura (ver la sección 3.4), porque no se pueden expresar como `CHECK`.

#### `fase_venta`

**Propósito:** periodo consecutivo de venta con precio propio dentro de un evento comercial (por ejemplo, "Preventa" y "General"). Todo evento comercial tiene al menos una fase. Si no hay cambio de precio por fecha, tiene una sola.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| evento_id | BIGINT | FK → `evento` | Evento al que pertenece |
| nombre | TEXT | — | Por ejemplo "Preventa", "General" |
| inicia_en | TIMESTAMPTZ | — | Inicio de la fase; dura hasta que inicia la siguiente, y la última hasta el cierre de venta |

Restricciones de tabla: `UQ (evento_id, nombre)`, `UQ (evento_id, inicia_en)`, `UQ (id, evento_id)`. Solo se guarda el inicio, así que no pueden existir huecos ni traslapes entre fases. La fase vigente es la de mayor `inicia_en <= now()`. Aplica a todas las funciones del evento y se decide por la fecha de compra.

#### `precio_seccion`

**Propósito:** tabla intermedia N:M entre `fase_venta` y `seccion_evento`. Registra el precio oficial de cada combinación de sección del evento y fase de venta.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| fase_venta_id | BIGINT | PK (1/2) | Fase de venta |
| seccion_evento_id | BIGINT | PK (2/2) | Sección del evento |
| evento_id | BIGINT | — | Columna de enlace con el evento |
| precio | NUMERIC(10,2) | `CHECK (precio >= 100.00)` | Precio oficial de la combinación |

Restricciones de tabla: FK compuesta (`fase_venta_id`, `evento_id`) → `fase_venta(id, evento_id)`. FK compuesta (`seccion_evento_id`, `evento_id`) → `seccion_evento(id, evento_id)`. Compuerta de publicación: cada par (fase, sección del evento) debe tener precio.

#### `disponibilidad_butaca`

**Propósito:** función-asiento. Registra el estado de cada butaca habilitada en cada función. Es el inventario por función y se crea con `bulk_create` al publicar el evento.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| funcion_id | BIGINT | Parte de la FK compuesta (`funcion_id`, `evento_id`) → `funcion(id, evento_id)` | Función |
| evento_id | BIGINT | Columna de enlace | Evento de la función |
| butaca_id | BIGINT | Parte de la FK compuesta (`evento_id`, `butaca_id`) → `asignacion_butaca(evento_id, butaca_id)` | Butaca |
| estado | TEXT | — | `DISPONIBLE`, `APARTADA`, `VENDIDA`, `BLOQUEO_TECNICO`, `CORTESIA` |
| actualizado_en | TIMESTAMPTZ | — | Última modificación del estado |

Restricciones de tabla: FK compuesta (`funcion_id`, `evento_id`) → `funcion(id, evento_id)`. FK compuesta (`evento_id`, `butaca_id`) → `asignacion_butaca(evento_id, butaca_id)`. `UQ (funcion_id, butaca_id)`. `UQ (id, funcion_id)`. Solo existen filas para butacas de secciones habilitadas, así que en el mapa una butaca sin fila se pinta como sección deshabilitada.

#### `bloqueo_tecnico`

**Propósito:** historial de bloqueos técnicos de una butaca en una función. Una butaca puede bloquearse y liberarse varias veces, y cada bloqueo queda como fila.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| disponibilidad_id | BIGINT | FK → `disponibilidad_butaca` | Butaca y función bloqueadas |
| motivo | TEXT | — | Motivo del bloqueo |
| bloqueado_por_id | BIGINT | FK → `usuario` | Usuario que bloqueó |
| bloqueado_en | TIMESTAMPTZ | — | Instante del bloqueo |
| retirado_por_id | BIGINT | FK → `usuario`, N | Usuario que retiró el bloqueo (ciclo de vida) |
| retirado_en | TIMESTAMPTZ | N | Instante del retiro (ciclo de vida) |

Restricciones de tabla: índice único parcial sobre `disponibilidad_id` con `WHERE retirado_en IS NULL`. Hay como máximo un bloqueo vigente por butaca y función.

### 4.7 Módulo `ventas`

#### `orden_compra`

**Propósito:** orden única de compra de boletos. Une el carrito y la transacción de la v5.3, que son el mismo objeto en momentos distintos de un solo ciclo (`APARTADO → PAGO_EN_PROCESO → PAGADA`). Puede ser de canal en línea o de taquilla.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| folio | TEXT | UQ | Número de orden impreso en el boleto |
| funcion_id | BIGINT | FK → `funcion` | Función comprada; una sola por orden |
| canal | TEXT | — | `LINEA`, `TAQUILLA` |
| usuario_id | BIGINT | FK → `usuario`, N | Comprador en línea |
| cajero_id | BIGINT | FK → `usuario`, N | Cajero en taquilla |
| estado | TEXT | — | `APARTADO`, `PAGO_EN_PROCESO`, `PAGADA`, `EXPIRADA`, `REEMBOLSADA_AUTOMATICA` |
| expira_en | TIMESTAMPTZ | — | Primer asiento más 10 minutos |
| gracia_hasta | TIMESTAMPTZ | N | Se llena al pasar a `PAGO_EN_PROCESO` |
| pagada_en | TIMESTAMPTZ | N | Instante del pago (ciclo de vida) |
| creado_en | TIMESTAMPTZ | — | Fecha de creación |
| actualizado_en | TIMESTAMPTZ | — | Última modificación |

Restricciones de tabla: `CHECK ((canal = 'LINEA' AND usuario_id IS NOT NULL AND cajero_id IS NULL) OR (canal = 'TAQUILLA' AND cajero_id IS NOT NULL AND usuario_id IS NULL))`. Índice único parcial sobre `usuario_id` con `WHERE canal = 'LINEA' AND estado IN ('APARTADO','PAGO_EN_PROCESO')`, que permite un solo carrito activo por usuario. `UQ (id, funcion_id)`, para la FK compuesta del detalle. El total no se guarda.

#### `orden_compra_detalle`

**Propósito:** tabla intermedia entre la orden y las butacas de la función. Conserva qué butacas tenía la orden aunque expire, y el precio aplicado a cada una.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| orden_id | BIGINT | Parte de la FK compuesta (`orden_id`, `funcion_id`) → `orden_compra(id, funcion_id)` | Orden a la que pertenece la línea |
| funcion_id | BIGINT | Columna de enlace | Función de la orden |
| disponibilidad_id | BIGINT | Parte de la FK compuesta (`disponibilidad_id`, `funcion_id`) → `disponibilidad_butaca(id, funcion_id)` | Butaca de la función |
| evento_id | BIGINT | Columna de enlace | Evento de la función |
| fase_venta_id | BIGINT | FK compuesta (`fase_venta_id`, `evento_id`) → `fase_venta(id, evento_id)` | Fase vigente al apartar |
| precio_unitario | NUMERIC(10,2) | — | Copia de `precio_seccion.precio` al apartar |
| activo | BOOLEAN | — | `true` mientras la orden retiene o posee la butaca |

Restricciones de tabla: `UQ (orden_id, disponibilidad_id)`. Índice único parcial sobre `disponibilidad_id` con `WHERE activo`, que impide que una butaca esté retenida por dos órdenes a la vez. Las FKs compuestas de `orden_id` y de `disponibilidad_id` impiden mezclar funciones en una orden.

#### `pago_orden`

**Propósito:** pagos de una orden de boletos, con tarjeta en línea o registrados en taquilla. Una orden no se cobra dos veces.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| orden_id | BIGINT | FK → `orden_compra` | Orden pagada |
| metodo | TEXT | — | `TARJETA_STRIPE`, `EFECTIVO`, `TARJETA_TERMINAL` |
| monto | NUMERIC(10,2) | `CHECK (monto > 0)` | Monto cobrado |
| estado | TEXT | — | `PENDIENTE`, `EXITOSO`, `FALLIDO`, `CANCELADO` |
| stripe_payment_intent_id | TEXT | N, UQ | Identificador del PaymentIntent de Stripe |
| idempotency_key | TEXT | N, UQ | Llave de idempotencia del cobro |
| creado_en | TIMESTAMPTZ | — | Fecha de creación |
| confirmado_en | TIMESTAMPTZ | N | Instante de confirmación (ciclo de vida) |

Restricciones de tabla: `CHECK ((metodo = 'TARJETA_STRIPE') = (stripe_payment_intent_id IS NOT NULL AND idempotency_key IS NOT NULL))`. Índice único parcial sobre `orden_id` con `WHERE estado = 'EXITOSO'`, que garantiza que una orden no se cobra dos veces.

#### `reembolso_orden`

**Propósito:** reembolsos técnicos automáticos por pagos confirmados fuera de ventana (alcance §2.10.A). Es la única clase de reembolso que se ejecuta dentro de la plataforma en boletos.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| pago_id | BIGINT | FK → `pago_orden` | Pago que se reembolsa |
| stripe_refund_id | TEXT | UQ, N | Identificador del reembolso en Stripe; nulo hasta que Stripe responde |
| idempotency_key | TEXT | UQ | Llave de idempotencia del reembolso |
| monto | NUMERIC(10,2) | — | Monto reembolsado |
| motivo | TEXT | — | `BUTACAS_OCUPADAS`, `LIMITE_EXCEDIDO`, `FUNCION_CONCLUIDA_O_CANCELADA` |
| estado | TEXT | — | `PENDIENTE`, `EXITOSO`, `FALLIDO` |
| creado_en | TIMESTAMPTZ | — | Fecha de creación |

#### `webhook_stripe`

**Propósito:** bitácora idempotente de los eventos de Stripe, compartida por `ventas` y `cotizaciones`. Su PK impide procesar dos veces el mismo evento.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| stripe_event_id | TEXT | PK | Identificador del evento en Stripe |
| tipo_evento | TEXT | — | Por ejemplo `payment_intent.succeeded` |
| modulo | TEXT | — | `VENTAS`, `COTIZACIONES` (tomado de `metadata.modulo`) |
| payment_intent_id | TEXT | N | Enlace lógico con `pago_orden` o `pago_arrendamiento` |
| payload | JSONB | — | Contenido completo del evento |
| estado | TEXT | — | `PENDIENTE`, `PROCESADO`, `FALLIDO` |
| recibido_en | TIMESTAMPTZ | — | Instante de recepción |
| procesado_en | TIMESTAMPTZ | N | Instante de procesamiento (ciclo de vida) |

Restricciones de tabla: ninguna declarada en la fuente. El enlace con el pago es por `payment_intent_id` de tipo texto, sin FK, para que `ventas` no dependa de `cotizaciones`.

### 4.8 Módulo `boletos`

#### `boleto`

**Propósito:** boleto emitido para una butaca de una función, ya sea por compra o por cortesía. Su acceso se valida con un QR firmado y un folio corto. Los boletos invalidados se conservan.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| token | UUID | UQ | Se firma con `QR_HMAC_SECRET` al generar el QR |
| folio_corto | TEXT | UQ | Al menos 8 caracteres Base32, sin `0`, `O`, `1` ni `I`; para ingreso manual |
| funcion_id | BIGINT | — | Función del boleto |
| disponibilidad_id | BIGINT | FK compuesta (`disponibilidad_id`, `funcion_id`) → `disponibilidad_butaca(id, funcion_id)` | Butaca y función del boleto |
| origen | TEXT | — | `COMPRA`, `CORTESIA` |
| orden_detalle_id | BIGINT | N, UQ; FK → `orden_compra_detalle`, solo si `origen = COMPRA` | Línea de la orden que originó el boleto |
| estado | TEXT | `CHECK ((estado IN ('USADO','USADO_CONTINGENCIA')) = (usado_en IS NOT NULL))` | `EMITIDO`, `USADO`, `USADO_CONTINGENCIA`, `INVALIDADO` |
| emitido_en | TIMESTAMPTZ | — | Instante de emisión |
| usado_en | TIMESTAMPTZ | N | Instante de ingreso (ciclo de vida) |
| validado_por_id | BIGINT | FK → `usuario`, N | Verificador que validó el acceso (ciclo de vida) |
| invalidado_en | TIMESTAMPTZ | N | Instante de invalidación (ciclo de vida) |
| invalidado_por_id | BIGINT | FK → `usuario`, N | Usuario que invalidó el boleto |
| motivo_invalidacion | TEXT | N | Motivo de la invalidación |

Restricciones de tabla: `CHECK ((origen = 'COMPRA') = (orden_detalle_id IS NOT NULL))`. Índice único parcial sobre `disponibilidad_id` con `WHERE estado <> 'INVALIDADO'`, que deja un solo boleto vigente por butaca y función y conserva los invalidados. El precio y el método de pago impresos se obtienen de `orden_compra_detalle` y `pago_orden`; en cortesía son `$0.00` y "Cortesía".

#### `cortesia`

**Propósito:** subtipo de `boleto` para las cortesías emitidas por el Admin. Tiene tres atributos propios.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| boleto_id | BIGINT | PK, FK → `boleto` | Boleto de cortesía |
| emitida_por_id | BIGINT | FK → `usuario` | Admin que emitió la cortesía |
| beneficiario | TEXT | N | Nombre del beneficiario, opcional |
| motivo | TEXT | N | Motivo, opcional |

#### `contingencia_funcion`

**Propósito:** historial de activaciones del modo contingencia de una función, para control impreso en puerta ante una caída total de conectividad, y de su reconciliación en lote. Las exportaciones de folios se registran en `registro_auditoria`.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| funcion_id | BIGINT | FK → `funcion` | Función en contingencia |
| activada_por_id | BIGINT | FK → `usuario` | Admin que activó el modo |
| activada_en | TIMESTAMPTZ | — | Instante de activación |
| cerrada_por_id | BIGINT | FK → `usuario`, N | Admin que cerró la contingencia |
| cerrada_en | TIMESTAMPTZ | N | Instante de cierre |
| aplicados | INTEGER | N | Resultado de la reconciliación en lote: folios aplicados |
| ya_usados | INTEGER | N | Resultado de la reconciliación en lote: folios que ya estaban usados |
| rechazados | INTEGER | N | Resultado de la reconciliación en lote: folios rechazados |

Restricciones de tabla: índice único parcial sobre `funcion_id` con `WHERE cerrada_en IS NULL`, que permite una sola contingencia abierta por función.

### 4.9 Módulo `cotizaciones`

#### `cotizacion`

**Propósito:** solicitud de arrendamiento del teatro desde su envío hasta su confirmación o cierre. Reúne lo que en la v5.3 eran `Solicitud_Renta`, `Cotización` y `Reserva_renta`. Los datos que varían (bloques, servicios, pagos y propuestas) están en tablas propias.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| folio | TEXT | UQ | Folio de la cotización |
| solicitante_id | BIGINT | FK → `usuario` | Usuario que solicita el arrendamiento |
| sala_id | BIGINT | FK → `sala` | Sala cotizada |
| nombre_evento | TEXT | — | Nombre del evento |
| categoria_id | BIGINT | FK → `categoria` | Categoría del evento |
| modalidad | TEXT | — | `COMERCIAL`, `PUBLICO`, `PRIVADO` |
| asistentes_estimados | INTEGER | `CHECK (> 0)` | Tope: `sala.aforo` (1,728), validado en el servicio |
| contacto_nombre | TEXT | — | Dato de contacto para la cotización |
| contacto_telefono | TEXT | — | Dato de contacto para la cotización |
| contacto_correo | TEXT | — | Dato de contacto para la cotización |
| es_multidia | BOOLEAN | — | Indica si el evento dura más de un día |
| subtotal_estimado | NUMERIC(10,2) | — | Informativo, calculado al enviar |
| monto_oficial | NUMERIC(10,2) | N | Lo fija el Admin al aprobar |
| estado | TEXT | — | `EN_REVISION`, `PROPUESTA_RETENIDA`, `PROPUESTA_EXPIRADA`, `PRE_RESERVADO`, `CONFIRMADO`, `EXPIRADA_SIN_PAGO`, `EXPIRADA_POR_FECHA`, `PAGO_EXTEMPORANEO_EN_REVISION`, `RECHAZADA`, `CANCELADO_POR_ARRENDATARIO`, `CANCELADO_POR_TEATRO`, `FINALIZADO` |
| enviada_en | TIMESTAMPTZ | — | Base para el SLA |
| respondida_en | TIMESTAMPTZ | N | Instante de respuesta del Admin (ciclo de vida) |
| aprobada_en | TIMESTAMPTZ | N | Instante de aprobación (ciclo de vida) |
| confirmada_en | TIMESTAMPTZ | N | Instante de confirmación (ciclo de vida) |
| actualizado_en | TIMESTAMPTZ | — | Última modificación |

Restricciones de tabla: ninguna declarada en la fuente. La condición de atraso no se guarda: se calcula con `enviada_en` y los días hábiles. El estado financiero (`ANTICIPO_50_PAGADO`, `LIQUIDADO_100`, `REEMBOLSO_BANCARIO_PENDIENTE`) tampoco se guarda: se deriva de `cuota_arrendamiento` y `reembolso_arrendamiento`.

#### `cotizacion_parametros`

**Propósito:** snapshot de las reglas vigentes al aprobar la cotización. Agrupa valores que no existen antes de la aprobación, por eso no son columnas de `cotizacion`.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| cotizacion_id | BIGINT | PK, FK → `cotizacion` | Cotización a la que pertenece el snapshot |
| esquema_pago | TEXT | — | `50_50`, `100` |
| monto_anticipo | NUMERIC(10,2) | — | Anticipo redondeado con `ROUND_HALF_UP`; igual al total si `esquema_pago = 100` |
| prereserva_h | — | — | Copia de `configuracion_sistema.prereserva_h` |
| revision_extemporanea_h | — | — | Copia de `configuracion_sistema.revision_extemporanea_h` |
| corte_saldo_d | — | — | Copia de `configuracion_sistema.corte_saldo_d` |
| margen_50_50_d | — | — | Copia de `configuracion_sistema.margen_50_50_d` |
| retencion_cancelacion_pct | — | — | Copia de `configuracion_sistema.retencion_cancelacion_pct` |
| reprogramacion_minima_d | — | — | Copia de `configuracion_sistema.reprogramacion_minima_d` |
| tomado_en | TIMESTAMPTZ | — | Instante en que se tomó el snapshot |

Restricciones de tabla: ninguna declarada en la fuente. El saldo se calcula como `monto_oficial - monto_anticipo` y no se guarda.

#### `bloque_solicitado`

**Propósito:** cada día y turno pedido en una cotización, incluidos montaje y ensayos. Es la base de la renta y el vínculo con la agenda.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| cotizacion_id | BIGINT | FK → `cotizacion` | Cotización que pide el bloque |
| fecha | DATE | — | Día solicitado |
| turno_id | BIGINT | FK → `turno`, N | Nulo si el horario es personalizado |
| hora_inicio | TIME | — | Copia del turno o captura libre |
| hora_fin | TIME | — | Copia del turno o captura libre |
| finalidad | TEXT | — | `EVENTO`, `MONTAJE_ENSAYO` |
| tarifa_aplicada | NUMERIC(10,2) | — | Snapshot; `0.00` en montaje y ensayos incluidos |
| bloqueo_agenda_id | BIGINT | FK → `bloqueo_agenda`, N, UQ | Se llena al pre-reservar |

Restricciones de tabla: ninguna declarada en la fuente, salvo las indicadas en las columnas.

#### `cotizacion_servicio`

**Propósito:** extras e infraestructura incluidos en una cotización, con snapshot de su precio. La renta por turno no se guarda aquí, porque está en `bloque_solicitado.tarifa_aplicada`.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| cotizacion_id | BIGINT | FK → `cotizacion` | Cotización |
| servicio_id | BIGINT | FK → `servicio_extra` | Servicio cotizado |
| cantidad | INTEGER | `CHECK (> 0)` | Unidades cotizadas |
| unidad_cobro | TEXT | — | Snapshot de la unidad de cobro |
| precio_unitario | NUMERIC(10,2) | — | Snapshot del precio unitario |

Restricciones de tabla: `UQ (cotizacion_id, servicio_id)`. El subtotal de la línea se calcula y no se guarda.

#### `propuesta_fecha`

**Propósito:** propuesta de fechas alternativas o de reprogramación que el Admin envía al Solicitante. Sirve para ambos casos, y las opciones concretas están en `opcion_propuesta`.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| cotizacion_id | BIGINT | FK → `cotizacion` | Cotización a la que se propone |
| tipo | TEXT | — | `ALTERNATIVA`, `REPROGRAMACION` |
| estado | TEXT | — | `VIGENTE`, `ACEPTADA`, `RECHAZADA`, `EXPIRADA` |
| enviada_por_id | BIGINT | FK → `usuario` | Admin que envió la propuesta |
| enviada_en | TIMESTAMPTZ | — | Instante de envío |
| expira_en | TIMESTAMPTZ | — | Vencimiento de la propuesta, 48 h |
| respondida_en | TIMESTAMPTZ | N | Instante de respuesta (ciclo de vida) |

Restricciones de tabla: ninguna declarada en la fuente. La reprogramación gratuita ya usada no se guarda: se deriva de que exista una propuesta `REPROGRAMACION` en estado `ACEPTADA`.

#### `opcion_propuesta`

**Propósito:** cada una de las opciones de fecha y turno (de 1 a 3) de una propuesta. Cada opción tiene su propia retención de agenda de 48 h.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| propuesta_id | BIGINT | FK → `propuesta_fecha` | Propuesta a la que pertenece la opción |
| orden | SMALLINT | `CHECK (BETWEEN 1 AND 3)` | Posición de la opción dentro de la propuesta |
| fecha | DATE | — | Fecha ofrecida |
| turno_id | BIGINT | FK → `turno`, N | Turno ofrecido |
| hora_inicio | TIME | — | Hora de inicio ofrecida |
| hora_fin | TIME | — | Hora de fin ofrecida |
| bloqueo_agenda_id | BIGINT | FK → `bloqueo_agenda`, UQ | Retención de 48 h de esta opción |
| elegida | BOOLEAN | — | Indica si el Solicitante eligió esta opción |

Restricciones de tabla: `UQ (propuesta_id, orden)`. Índice único parcial sobre `propuesta_id` con `WHERE elegida`, que permite una sola opción elegida por propuesta.

#### `cuota_arrendamiento`

**Propósito:** cuota que la cotización debe pagar (anticipo del 50%, saldo del 50% o pago total del 100%), con su fecha límite.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| cotizacion_id | BIGINT | FK → `cotizacion` | Cotización que se cobra |
| tipo | TEXT | — | `ANTICIPO_50`, `SALDO_50`, `TOTAL_100` |
| monto | NUMERIC(10,2) | — | Monto de la cuota |
| fecha_limite | TIMESTAMPTZ | — | Fin de la pre-reserva, o `D-21` a las 23:59:59 |
| fecha_limite_ficha | TIMESTAMPTZ | N; `CHECK ((tipo = 'SALDO_50') = (fecha_limite_ficha IS NOT NULL))` | Solo en `SALDO_50`: `fecha_limite - 48 h` |
| estado | TEXT | — | `PENDIENTE`, `PAGADA`, `VENCIDA` |
| pagada_en | TIMESTAMPTZ | N | Instante del pago (ciclo de vida) |

Restricciones de tabla: `UQ (cotizacion_id, tipo)`. `CHECK ((tipo = 'SALDO_50') = (fecha_limite_ficha IS NOT NULL))`.

#### `pago_arrendamiento`

**Propósito:** cada intento de pago de una cuota de arrendamiento. Por ejemplo, una tarjeta rechazada seguida de una ficha es dos intentos.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| cuota_id | BIGINT | FK → `cuota_arrendamiento` | Cuota que se intenta pagar |
| metodo | TEXT | — | `TARJETA`, `FICHA_SPEI`, `FICHA_EFECTIVO` |
| monto | NUMERIC(10,2) | — | Monto del intento |
| stripe_payment_intent_id | TEXT | UQ | Identificador del PaymentIntent de Stripe |
| idempotency_key | TEXT | UQ | Llave de idempotencia del intento |
| estado | TEXT | — | `PENDIENTE`, `EXITOSO`, `FALLIDO`, `CANCELADO`, `EXTEMPORANEO` |
| creado_en | TIMESTAMPTZ | — | Fecha de creación |
| acreditado_en | TIMESTAMPTZ | N | Instante en que se acreditó el pago (ciclo de vida) |

Restricciones de tabla: ninguna declarada en la fuente.

#### `ficha_pago`

**Propósito:** subtipo de `pago_arrendamiento` para los pagos con ficha, por SPEI o efectivo. Tiene tres atributos propios.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| pago_id | BIGINT | PK, FK → `pago_arrendamiento` | Pago al que pertenece la ficha |
| linea_captura | TEXT | — | Línea de captura generada por Stripe |
| url_ficha | TEXT | — | URL de la ficha |
| expira_en | TIMESTAMPTZ | — | Vencimiento de la ficha |

#### `reembolso_arrendamiento`

**Propósito:** devoluciones de pagos de arrendamiento, ya sean automáticas a la tarjeta o bancarias externas.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| pago_id | BIGINT | FK → `pago_arrendamiento` | Pago que se devuelve |
| tipo | TEXT | — | `AUTOMATICO_TARJETA`, `BANCARIO_EXTERNO` |
| monto | NUMERIC(10,2) | — | Monto devuelto |
| motivo | TEXT | — | Motivo de la devolución |
| estado | TEXT | — | `PENDIENTE`, `COMPLETADO`, `FALLIDO` |
| stripe_refund_id | TEXT | N, UQ | Identificador del reembolso en Stripe |
| idempotency_key | TEXT | N, UQ | Llave de idempotencia del reembolso |
| creado_en | TIMESTAMPTZ | — | Fecha de creación |
| resuelto_por_id | BIGINT | FK → `usuario`, N | Quién confirmó la devolución bancaria |
| resuelto_en | TIMESTAMPTZ | N | Instante de resolución (ciclo de vida) |

Restricciones de tabla: `CHECK ((tipo = 'AUTOMATICO_TARJETA') = (idempotency_key IS NOT NULL))`.

#### `revision_pago_extemporaneo`

**Propósito:** revisión que hace el Admin de un pago de arrendamiento acreditado después de la pre-reserva de 48 h, cuando la fecha aún estaba libre. El Admin tiene 72 h para resolverla.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| id | BIGINT | PK | Identificador |
| cotizacion_id | BIGINT | FK → `cotizacion` | Cotización revisada |
| pago_id | BIGINT | FK → `pago_arrendamiento`, UQ | Pago extemporáneo revisado |
| expira_en | TIMESTAMPTZ | — | Llegada del pago más 72 h |
| resolucion | TEXT | N | `ACEPTADO`, `RECHAZADO` |
| resuelto_por_id | BIGINT | FK → `usuario`, N | Admin que resolvió |
| resuelto_en | TIMESTAMPTZ | N | Instante de resolución |

Restricciones de tabla: ninguna declarada en la fuente.

#### `cancelacion_arrendamiento`

**Propósito:** registro de la cancelación de una cotización, con los montos retenidos y devueltos según la política del alcance §2.9. Es un subtipo de la cotización, con atributos propios.

| Columna | Tipo | Restricciones / llaves | Descripción |
| :---- | :---- | :---- | :---- |
| cotizacion_id | BIGINT | PK, FK → `cotizacion` | Cotización cancelada |
| tipo | TEXT | — | `POR_ARRENDATARIO`, `POR_TEATRO`, `INCUMPLIMIENTO_D21` |
| solicitada_en | TIMESTAMPTZ | — | Instante de la solicitud de cancelación |
| registrada_por_id | BIGINT | FK → `usuario` | Admin que registró la cancelación |
| monto_retenido | NUMERIC(10,2) | — | Monto retenido según la política de §2.9 |
| monto_a_devolver | NUMERIC(10,2) | — | Monto de devolución externa |
| opcion_solicitante | TEXT | N | `REEMBOLSO`, `REPROGRAMACION` (solo en `POR_TEATRO`) |

Restricciones de tabla: ninguna declarada en la fuente.

---

## 5. Pendientes

Los pendientes siguen la sección 9 de `docs/modelo-datos.md`:

1. **Desglose real del aforo.** Definir el desglose de filas, columnas, palcos y butacas accesibles que suman 1,728 butacas, para `seed_teatro.py`.
2. **Alinear los documentos complementarios.** Ajustar `docs/alcance.md` §2.3 y `docs/arquitectura.md` para reflejar: precio por sección **y** fase de venta, secciones del evento que agrupan o dividen, sala como raíz, `seccion_evento` en `inventario`, filas de `disponibilidad_butaca` solo para secciones habilitadas, y anti-empalmes por sala.
3. **Alcance de la fase de venta.** Confirmar si una fase de venta puede variar por función. Hoy aplica a todo el evento.

### Observaciones detectadas al redactar este informe

* **Cobertura de hallazgos no declarada.** La matriz de la sección 5 de `modelo-datos.md` no tiene fila para `ER-I06`, `ER-M02`, `ER-M04` ni `ER-M05`. Su atención se infiere del diseño, pero la fuente no la documenta. Conviene agregarlas a la matriz o declarar que quedan fuera de alcance.
* **Redacción de nombres en `alcance.md` §2.3.** Según la lectura actual, §2.3 ya describe fases de venta y precio por sección y fase. Sin embargo, sigue usando la regla de nombre por defecto `{Sección} - Zona {N}` al subdividir. La sección 3.4 de `modelo-datos.md` indica que esa regla de nombre compuesto ya no aplica cuando una sección del evento abarca varias físicas. Hay que resolver esa diferencia.
* **Nulos en `configuracion_sistema`.** La fuente no declara el tipo de los parámetros de esta tabla, solo su valor por defecto. En este informe se marcaron con `—`. Conviene definir sus tipos (por ejemplo, `INTEGER` o `NUMERIC`) antes de escribir `models.py`.
