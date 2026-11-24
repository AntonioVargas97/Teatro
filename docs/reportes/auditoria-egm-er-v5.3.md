# Reporte Consolidado de Auditoría EGM — `Teatro_ER_v5.3.drawio.svg` vs. Alcance y Arquitectura

* **Diagrama auditado:** [Teatro_ER_v5.3.drawio.svg](../modelado_datos/Teatro_ER_v5.3.drawio.svg) (`<diagram name="Teatro v5.3">`)
* **Fuentes de verdad contrastadas:** [alcance.md](../alcance.md) y [arquitectura.md](../arquitectura.md) (tras la resolución de `[I-03]` registrada en [auditoria-egm-documentacion.md](./auditoria-egm-documentacion.md)), con verificación complementaria sobre [maquinas-de-estado.md](../maquinas-de-estado.md), [me04-butaca-qr.puml](../maquinas-de-estado/me04-butaca-qr.puml) y el estado real del repositorio.
* **Revisores EGM ejecutados:** `egm-design`, `egm-implementation-readiness`, `egm-zoom-out`, `egm-codebase-details`, `egm-comprehension` y consolidación vía `egm-synthesizer`.

---

## 1. Dictamen Ejecutivo y Métricas Verificadas del ER

> **Dictamen de Preparación: NO LISTO / BLOQUEADO.** El diagrama `Teatro_ER_v5.3.drawio.svg` no está listo para derivar `docs/modelo-datos.md`, los modelos y migraciones de Django (`models.py`, fuente única de verdad según `ADR-02`) ni los respaldos en `database/*.sql`.

El diagrama exhibe tres familias principales de desalineación:
1. **Sobre-normalización severa:** Modela **30 entidades** frente a las **13 entidades nucleares** definidas en [arquitectura.md](../arquitectura.md#L284-L300) y un esquema objetivo de **~16–18 tablas** (o `23` tablas en su variante altamente normalizada).
2. **Bloqueantes arquitectónicos y de concurrencia:** Fragmenta `OrdenCompra` en 4 entidades rompiendo la jerarquía de candados y la taquilla física sin cuenta; acopla el módulo transversal `agenda` violando `ADR-07` (`import-linter` / ADP) y omite `TSTZRANGE` / `ExclusionConstraint`; impide la idempotencia de *webhooks* de Stripe y la distinción tarjeta vs. ficha SPEI/efectivo; e introduce el anti-patrón `Asiento_evento` que viola el configurador rectangular/por palcos y degrada el *polling* `< 300 ms (p95)`.
3. **Omisiones de negocio y residuos `Ticketmaster`:** Carece de la entidad `Turno`, de Eventos Directos, del esquema `50/50` + corte `D-21` + pagos extemporáneos (`72 h`), de `LFPDPPP` / `session_version`, de cortesías `$0.00 MXN` vs. bloqueos técnicos, de modo contingencia y de restricciones PostgreSQL (`CHECK`, índices únicos parciales, `Decimal(10, 2)`, `TIMESTAMPTZ` UTC); además arrastra conceptos fuera de alcance provenientes de otro dominio (`Ticketmaster`).

### Métricas Verificadas en el XML `<mxfile>`

| Métrica | Conteo verificado | Observación |
| :--- | :---: | :--- |
| **Entidades (rectángulos)** | **30** | Incluye `2` entidades totalmente aisladas (`Configuracion_sistema`, `Registro_auditoría`) y `1` sin atributos (`Asiento_evento`). |
| **Relaciones (rombos Chen)** | **40** | Varias con cardinalidades ambiguas (`N`, `M`) o lectura direccional invertida. |
| **Atributos (elipses)** | **166** | Incluye `1` atributo huérfano desconectado (`fecha_envio` sobre `Propuesta_Fecha` con `tgt=None`). |
| **Etiquetas de cardinalidad visibles** | **79** | En el XML, el grupo contenedor `_8rSmAYqaTynVGkd0J08-61` lleva `value="1"`, no siendo una etiqueta de cardinalidad visible. |
| **Notas de texto / Checks verdes** | **3 / 5** | Iconos `mxgraph.gcp2.check` sobre `Asiento`, `Sección`, `Evento`, `Categoria` y `Artista_Organizacion` (sin leyenda). |
| **Metadata residual en `<mxfile>`** | `Ticketmaster` | `collapsedPageGroups='["Teatro","Ticketmaster"]'` en la cabecera `<mxfile>` de [Teatro_ER_v5.3.drawio.svg](../modelado_datos/Teatro_ER_v5.3.drawio.svg), explicando cargos, paquetes y `Artista_Organizacion` fuera de alcance. |

---

## 2. Hallazgos Críticos / Bloqueantes

### `[ER-C01]` Fragmentación de `OrdenCompra` en 4 entidades: *split-brain*, ruptura de candados y bloqueo de Taquilla Física
* **Respaldo EGM:** `egm-design`, `egm-implementation-readiness`, `egm-zoom-out`, `egm-codebase-details`, `egm-comprehension`.
* **ER afectado:** `Carrito`, `DetalleCarrito`, `Transaccion`, `Detalle_Transaccion`, `Funcion_asiento`; relaciones `Usuario [1] --- (Posee) --- [N] Carrito`, `Carrito [N] --- (Corresponde) --- [1] Funcion`, `Carrito [1] --- (Contiene) --- [N] DetalleCarrito`, `DetalleCarrito [N] --- (Selecciona) --- [1] Funcion_asiento`, `Carrito [1] --- (Genera) --- [0..1] Transaccion`, `Transaccion [1] --- (Contiene) --- [1..N] Detalle_Transaccion`, `Detalle_Transaccion [0..N] --- (Corresponde) --- [1] Funcion_asiento` y `Detalle_Transaccion [0..1] --- (Contiene) --- [0..1] Boleto`.
* **Fuentes de verdad:** [alcance.md](../alcance.md) (§1, §2.7, §2.8, §2.10.A, §2.10.C, §3.5, §3.7, §4.1, §4.13, §6); [arquitectura.md](../arquitectura.md#L295) (`OrdenCompra`, Diagrama 3 L190–223, Concurrencia L306–316, `ADR-06`, `ADR-08`).
* **Impacto técnico:**
  1. Divide el ciclo unificado de `OrdenCompra` (`APARTADO`, `PAGO_EN_PROCESO`, `PAGADA`, `EXPIRADA`, `REEMBOLSADA_AUTOMATICA`) en tres estados desconectados (`Carrito.estatus`, `Transaccion.estado`, `Pago.estado`).
  2. Rompe la jerarquía atómica `Usuario -> OrdenCompra -> DisponibilidadButaca -> Boleto`: `Funcion_asiento` carece de FK directa a la orden y las relaciones `[N]` / `[0..N]` desde `DetalleCarrito` y `Detalle_Transaccion` no impiden a nivel relacional la doble retención simultánea sin índice parcial.
  3. `Usuario [1] --- (Posee) --- [N] Carrito` obliga a tener cuenta para vender en **Taquilla Física** (violando §2.7 y `ADR-06`); asignar el usuario del `CAJERO` contaminaría el límite atómico `<= 10` boletos por cuenta/función (`APARTADO + PAGO_EN_PROCESO + PAGADA`).
  4. Omite `gracia_hasta` (`+5 min`), `payment_intent_id`, `canal` en el apartado, `cajero_id` separado, `metodo_pago` (`EFECTIVO`, `TARJETA_TERMINAL_EXTERNA`, `TARJETA_STRIPE`), FK directa `funcion_id` en la orden pagada y restricción única parcial de `1` carrito activo en `LINEA` por usuario. Además, `Carrito [1] --- [0..1] Transaccion` dificulta reasignar o marcar `REEMBOLSADA_AUTOMATICA` cuando un *webhook* llega tras expirar `PAGO_EN_PROCESO`.
* **Corrección requerida:** Unificar `Carrito`, `DetalleCarrito`, `Transaccion` y `Detalle_Transaccion` en **`OrdenCompra`** (`usuario_id` nullable para `TAQUILLA`, `cajero_id` nullable, `funcion_id`, `canal`, `metodo_pago`, `estado`, `expira_en`, `gracia_hasta`, `payment_intent_id`, índice único parcial de 1 orden activa en `LINEA` por usuario) y enlazar `DisponibilidadButaca` directo a `OrdenCompra`.

---

### `[ER-C02]` Geometría tarifaria ausente, piso mínimo omitido y anti-patrón `Asiento_evento` + `Asiento.estado` + `Funcion_asiento`
* **Respaldo EGM:** `egm-design`, `egm-implementation-readiness`, `egm-zoom-out`, `egm-codebase-details`, `egm-comprehension`.
* **ER afectado:** `Asiento`, `Asiento_evento`, `Funcion_asiento`, `Subsección_tarifaria`, `Sección`.
* **Fuentes de verdad:** [alcance.md](../alcance.md) (§2.3, §3.3, §3.4, §4.3); [arquitectura.md](../arquitectura.md#L292-L294) (`Sección y Butaca / Asiento`, `SubseccionTarifaria`, `DisponibilidadButaca`, Polling L305, Candados L314–316).
* **Impacto técnico:**
  1. `Subsección_tarifaria` carece de rangos rectangulares `(fila_inicio, fila_fin, col_inicio, col_fin)` para graderías, lista de cabinas completas `palco_ids` para `Palcos`, banderas `habilitada` (para deshabilitar secciones completas) y `congelada`, límite `<= 6` sub-secciones por sección oficial, `CHECK (tarifa >= 100.00)` y unicidad compuesta `UNIQUE(evento_id, seccion_id, nombre)`.
  2. `Asiento_evento` (`0` atributos) permite asignación individual asiento por asiento y partición de palcos (prohibidas en §4.3), duplica 1,728 filas por evento, bloquea la materialización completa de 1,728 filas cuando una sección se deshabilita (al exigir `[1] Subsección_tarifaria`), y añade un `JOIN` extra sobre el *polling* ligero `.values_list('butaca_id', 'estado')` (`< 300 ms p95`).
  3. `Asiento.estado` en el catálogo físico permanente contradice la independencia de disponibilidad por función y omite coordenadas numéricas (`fila_orden`, `columna`) para validar bloques rectangulares contiguos y ordenar `ORDER BY (funcion_id, butaca_id) ASC` en `select_for_update()`.
  4. `Funcion_asiento` carece de FK directa a `Asiento`, `SubseccionTarifaria` y `OrdenCompra`, campos de bloqueo técnico (`motivo_bloqueo`, `bloqueado_por`, `bloqueado_en`) y `UNIQUE(funcion_id, butaca_id)`.
* **Corrección requerida:** Eliminar `Asiento_evento`; quitar `Asiento.estado` y `palco`/`codigo_palco` redundantes añadiendo `fila_orden`, `columna` y `cabina_palco` en `Butaca`; completar `SubseccionTarifaria` con geometría, `habilitada`, `congelada`, `CHECK >= 100.00` y unicidad compuesta; y consolidar `Funcion_asiento` en **`DisponibilidadButaca`**.

---

### `[ER-C03]` Agenda acoplada (`Ocupación_teatro` + `Reserva_renta` + `Opción_Fecha`): viola `ADR-07`, omite `TSTZRANGE` y bloquea multi-función y Eventos Directos
* **Respaldo EGM:** `egm-design`, `egm-implementation-readiness`, `egm-zoom-out`, `egm-codebase-details`, `egm-comprehension`.
* **ER afectado:** `Ocupación_teatro`, `Reserva_renta`, `Opción_Fecha`, `Propuesta_Fecha`, `Evento`, `Funcion`; relaciones `(Retiene)`, `(Da lugar a)`, `(Tiene)`, `(Utiliza)` (`Ocupación_teatro [1] --- [0..1] Funcion`).
* **Fuentes de verdad:** [alcance.md](../alcance.md) (§2.2, §2.4, §2.5, §2.9.C); [arquitectura.md](../arquitectura.md#L290-L291) (`BloqueoAgenda`, `ExclusionConstraint` L309, Reglas ADP / `import-linter` L368–377, `ADR-07`).
* **Impacto técnico:**
  1. `Ocupación_teatro` incluye `reserva_id` y mantiene relaciones hacia `Reserva_renta`, `Opción_Fecha` y `Funcion`, violando `ADR-07` (cero *imports* inversos desde `agenda` hacia módulos de dominio, verificado por `import-linter` en CI).
  2. Separa `inicio` y `fin` en lugar de modelar `rango_tiempo` (`TSTZRANGE` `[inicio, fin)`) con `BtreeGistExtension()` y `ExclusionConstraint(rango_tiempo WITH &&) WHERE estado != 'LIBERADO'`.
  3. `Ocupación_teatro [1] --- (Utiliza) --- [0..1] Funcion` prohíbe múltiples funciones dentro de un mismo bloque `RENTA` (`Día Completo` o multi-día) y bloquea la trazabilidad en reprogramaciones.
  4. Los **Eventos Directos** (sin `Cotización` ni `Reserva_renta`), los bloques `MANTENIMIENTO` y los bloques exclusivos de montaje/ensayos quedan desconectados de `Ocupación_teatro`.
  5. `Opción_Fecha` solo tiene `opcion_id` (sin fecha, turno, horario ni estado) y la presencia de `Reserva_renta` (con `fecha_confirmación`) deja sin relación a `Cotización` durante las 48 h de `PRE_RESERVADO`.
* **Corrección requerida:** Refactorizar `Ocupación_teatro` (absorbiendo `Reserva_renta`) en **`BloqueoAgenda`** dentro de `apps/agenda/` con `rango_tiempo` (`TSTZRANGE`), `origen` (`FUNCION | RENTA | MANTENIMIENTO`), `estado` (`PROPUESTA_RETENIDA | PRE_RESERVADO | CONFIRMADO | LIBERADO`), `etiqueta`, `expira_en` y `ExclusionConstraint`; y hacer que `Funcion`, `Evento` (o bloques de montaje/mantenimiento) y `Cotizacion`/`OpcionPropuestaFecha` apunten `N:1` hacia `BloqueoAgenda`.

---

### `[ER-C04]` `Notificación_pago` y `Pago` impiden idempotencia de *webhooks* Stripe y reembolsos diferenciados
* **Respaldo EGM:** `egm-design`, `egm-implementation-readiness`, `egm-zoom-out`, `egm-codebase-details`.
* **ER afectado:** `Notificación_pago`, `Pago`; relaciones `Notificación_pago [0..N] --- (Recibe) --- [1] Pago`, `Pago [0..N] --- [0..1] Transaccion`, `Pago [0..N] --- [0..1] Cuota_Arrendamiento`.
* **Fuentes de verdad:** [alcance.md](../alcance.md) (§2.10, §3.6); [arquitectura.md](../arquitectura.md#L298) (`Transacción / Pasarela de Pagos`, Diagrama 3 L210–222, Celery Worker L313, Seguridad L435).
* **Impacto técnico:**
  1. `Notificación_pago` solo posee `evento_externo_id` (sin PK explícita `stripe_event_id`, sin `estado` `PENDIENTE | PROCESADO | FALLIDO`, `tipo_evento`, `modulo` por `metadata.modulo`, `payload` JSONB ni `recibido_en`/`procesado_en`).
  2. Exigir `[1] Pago` obligatorio impide insertar el evento en `PENDIENTE` antes de `transaction.on_commit()` y bloquea registrar fallos (`payment_intent.payment_failed`).
  3. `Pago` colapsa todo en `ref_pago_externa` (colisionan `pi_xxx` y `re_xxx`): faltan `stripe_payment_intent_id`, `stripe_refund_id`, `idempotency_key` (cobro y reembolso), datos de ficha SPEI/efectivo (`linea_captura`, `url_ficha`, `ficha_expira_en`), estado `REEMBOLSO_BANCARIO_PENDIENTE` y `CHECK` **XOR** físico (hoy relegado a una nota de texto).
* **Corrección requerida:** Convertir `Notificación_pago` en **`WebhookStripe`** (`stripe_webhook_events`) con `stripe_event_id` PK, `estado`, `modulo`, `tipo_evento`, `payload`, timestamps y relación `[0..1]` con `Pago`; ampliar `Pago` (o segregar `PagoArrendamiento`) con IDs de `PaymentIntent`/`Refund`, llaves de idempotencia, campos de ficha y `CHECK` XOR en PostgreSQL.

---

### `[ER-C05]` Ausencia total de `Turno` y desconexión/incompletitud de `Configuracion_sistema` y `Registro_auditoría`
* **Respaldo EGM:** `egm-design`, `egm-implementation-readiness`, `egm-codebase-details`, `egm-comprehension`.
* **ER afectado:** `Configuracion_sistema` (`0` relaciones), `Registro_auditoría` (`0` relaciones), `Bloque_solicitado`, `Detalle_Cotización`, `Servicio`; relación `Servicio [1] --- (Es cotizado en) --- [N] Detalle_Cotización`.
* **Fuentes de verdad:** [alcance.md](../alcance.md) (§2.2, §2.4, §2.5, §3.10, §3.11); [arquitectura.md](../arquitectura.md#L289) (`ConfiguracionSistema`, `RegistroAuditoria` L300, Módulos Transversales L339–340, Auditoría L472).
* **Impacto técnico:**
  1. **Sin entidad `Turno`:** No hay catálogo para `Matutino`, `Vespertino` y `Día Completo` (tarifa base neta + `hora_inicio`/`hora_fin`). Por ello `Bloque_solicitado` carece de `turno_id` y `Servicio [1] --- [N] Detalle_Cotización` obliga a asociar un `Servicio` a toda línea cotizada, impidiendo desglosar la renta base por turno o montaje/ensayos en `` `$0.00 MXN` ``.
  2. **`Configuracion_sistema` sin PK ni parámetros completos:** Agrupa todo en `plazos_editables`, `gracia`, `prerreserva` y un único `cierre` (sin separar cierre web `-30 min` y taquilla `0 min`), omitiendo los ~17 parámetros de §3.10 y la referencia `actualizado_por`.
  3. **`Registro_auditoría` aislado e incompleto:** Carece de `entidad_id`, `actor_id` (FK nullable `PROTECT` hacia `Usuario`) + `actor_rol`, `modulo`, `detalles` JSONB, `ip_origen`, `request_id` y política *append-only*.
* **Corrección requerida:** Crear **`Turno`** en `configuracion`; hacer opcional (`[0..1]`) `servicio_id` en `DetalleCotizacion` con `turno_id` opcional; completar **`ConfiguracionSistema`** (singleton con todos los parámetros y `actualizado_por`); y conectar **`RegistroAuditoria`** con `Usuario` (`0..N` por actor).

---

### `[ER-C06]` Ausencia de restricciones físicas de PostgreSQL, precisión monetaria/temporal y reglas Django ORM (`ADR-02`)
* **Respaldo EGM:** `egm-implementation-readiness`, `egm-design`, `egm-codebase-details`.
* **ER afectado:** Transversal a las 30 entidades (`0` PKs subrayadas, `0` tipos o restricciones declaradas).
* **Fuentes de verdad:** [alcance.md](../alcance.md) (§2.3, §2.8, §2.9); [arquitectura.md](../arquitectura.md#L304-L317) (API L410, `ADR-02`).
* **Impacto técnico:** Faltan en la especificación derivada `ExclusionConstraint` (`BtreeGistExtension()`), `CHECK (tarifa >= 100.00)`, `CHECK` XOR en `Pago`, índices únicos parciales (butaca activa por función, `1` carrito activo en `LINEA`, boleto vigente por butaca, `UNIQUE(evento_id, seccion_id, nombre)`), políticas `ON DELETE PROTECT` (*soft delete* contable), tipos `Decimal(10, 2)` y `TIMESTAMPTZ` UTC.
* **Corrección requerida:** Formalizar tipos, índices, constraints y `ON DELETE` en `docs/modelo-datos.md` antes de implementar `models.py`.

---

## 3. Hallazgos Altos / Importantes

### `[ER-I01]` Brechas críticas en `Evento`, `Funcion` y `Propuesta_Fecha` (Cruce de medianoche, Eventos Directos, `REPROGRAMADO`, `VENCIDO_SIN_PUBLICAR` y Contingencia)
* **Respaldo EGM:** `egm-design`, `egm-implementation-readiness`, `egm-codebase-details`, `egm-comprehension`.
* **ER afectado:** `Evento`, `Funcion`, `Propuesta_Fecha`.
* **Fuentes de verdad:** [alcance.md](../alcance.md) (§2.2, §2.7, §2.9.C, §3.13); [arquitectura.md](../arquitectura.md#L291) (`Evento y Función`, Contingencia L391).
* **Impacto:**
  * `Evento` omite `creado_por` (necesario para **Eventos Directos** sin `Cotización`), `proximo_recordatorio_en` (3 d + cada 7 d), campos de resolución de `VENCIDO_SIN_PUBLICAR` (4 salidas auditadas + prórroga) y cancelación (`CANCELADO_*`); además duplica `aprobado_por` como atributo sobre la relación `(Aprueba)`.
  * `Funcion` mezcla `fecha_hora` con `hora_inicio_funcion` y `hora_final_funcion` sin `fecha` operativa + `inicio_en`/`fin_en` en UTC `TIMESTAMPTZ` (para cruce de medianoche cuando `hora_fin <= hora_inicio`); carece de `bloque_agenda_id`, campos históricos de `REPROGRAMADO` (fecha/hora anterior, `reprogramada_en`, `reprogramada_por`) y banderas de **modo contingencia** (`modo_contingencia_activo`, `contingencia_activada_en`, `contingencia_activada_por`, `contingencia_cerrada_en`).
  * `Propuesta_Fecha` cuelga solo de `Solicitud_Renta`, impidiendo usar propuestas estructuradas de fecha alternativa en reprogramaciones tras confirmar la `Cotización`.

### `[ER-I02]` Modelo financiero de Arrendamiento incompleto (`50/50`, corte `D-21`, pagos extemporáneos `72 h`, cancelaciones y SLA)
* **Respaldo EGM:** `egm-design`, `egm-implementation-readiness`, `egm-comprehension`.
* **ER afectado:** `Solicitud_Renta`, `Bloque_solicitado`, `Cotización`, `Cuota_Arrendamiento`, `Opción_Fecha`, `Reserva_renta`.
* **Fuentes de verdad:** [alcance.md](../alcance.md) (§2.4, §2.5, §2.9, §2.10.B); [arquitectura.md](../arquitectura.md#L296-L297).
* **Impacto:**
  * `Solicitud_Renta` omite `categoria_id`, `atrasada` (SLA `> 5` días hábiles), `es_multidia` y `respondida_en` (SLA `3` días hábiles); `Bloque_solicitado` omite `turno_id` y enum `finalidad` (`EVENTO | MONTAJE_ENSAYO`).
  * `Cotización` carece de `estado_liquidacion` (`ANTICIPO_50_PAGADO | LIQUIDADO_100 | REEMBOLSO_BANCARIO_PENDIENTE`), `monto_anticipo` (`ROUND_HALF_UP`), `saldo_restante` (`total - anticipo`), `fecha_limite_saldo` (`D-21 23:59:59`), `pre_reserva_expira_en` (48 h), `revision_extemporanea_expira_en` (72 h), `reprogramacion_gratuita_usada`, campos de retención/reembolso externo y `snapshot_parametros`.
  * `Cuota_Arrendamiento` omite `tipo_cuota` (`ANTICIPO_50 | SALDO_50 | TOTAL_100`) y `fecha_limite_ficha` (`D-21 - 48 h`) para vetar fichas en las últimas 48 h.
  * `Opción_Fecha` carece de datos de fecha/turno/horario/estado y su relación con `Propuesta_Fecha` dice `[0..3]` en lugar de `[1..3]`.

### `[ER-I03]` Brechas en `Boleto` y relación `Funcion_asiento -- Boleto` (Cortesías, Contingencia y *Soft Delete*)
* **Respaldo EGM:** `egm-design`, `egm-implementation-readiness`, `egm-codebase-details`, `egm-comprehension`.
* **ER afectado:** `Boleto`; relaciones `(Identificado por)` (`Funcion_asiento [1] --- [0..1] Boleto`), `(Contiene)` y `(Emite Cortesía)`.
* **Fuentes de verdad:** [alcance.md](../alcance.md) (§2.3, §2.8, §3.13); [arquitectura.md](../arquitectura.md#L299) (`Boleto`, Validación QR y Contingencia L386–391).
* **Impacto:**
  * `Boleto` omite FK directa a `Funcion`, `beneficiario_cortesia`, `motivo_cortesia`, `validado_en_contingencia` e invalidación auditada (`invalidado_en`, `invalidado_por`, `motivo_invalidacion`), además de usar `folio` en lugar de `folio_corto` y omitir `validado_por` como atributo visible (solo está implícito en nota).
  * `Funcion_asiento [1] --- [0..1] Boleto` impide conservar el boleto invalidado (*soft delete*) si `ADMIN` revoca una cortesía y luego la localidad se vende a otra persona.
  * Falta restricción XOR indicando que todo `Boleto` proviene de compra (`OrdenCompra`) o de cortesía (`ADMIN`), nunca de ambos ni de ninguno.

### `[ER-I04]` Omisiones legales y de sesión en `Usuario` (`LFPDPPP`, `session_version`, Django Auth)
* **Respaldo EGM:** `egm-design`, `egm-implementation-readiness`, `egm-zoom-out`, `egm-codebase-details`.
* **ER afectado:** `Usuario`.
* **Fuentes de verdad:** [alcance.md](../alcance.md) (§3.2, §6 `LFPDPPP`); [arquitectura.md](../arquitectura.md#L288) (Seguridad L431–432, `createsuperuser` L589).
* **Impacto:** Omite la aceptación obligatoria de Aviso de Privacidad y Términos (`LFPDPPP`), `session_version` (para revocación inmediata en Redis) y campos requeridos por `AbstractBaseUser`/`createsuperuser` (`is_staff`, `is_superuser`, `last_login`, `creado_en`, `actualizado_en`).

### `[ER-I05]` Cardinalidades imprecisas/invertidas y divergencia de nomenclatura frente a `arquitectura.md`
* **Respaldo EGM:** `egm-codebase-details`, `egm-comprehension`.
* **ER afectado:** Relaciones `Categoriza`, `Presenta`, `Contiene` (`Bloque_solicitado -- Solicitud_Renta`, `Carrito -- DetalleCarrito`), `Incluye`, `Ofrece`, `Es cotizado en`, `Corresponde` (`Carrito -- Funcion`), `Selecciona`, `Recibe` (`Pago` / `Notificación_pago`), y FKs duplicadas en `Evento`, `Reserva_renta`, `Ocupación_teatro`.
* **Impacto:**
  * Cardinalidades ambiguas con `N`/`M` sin mínimo (`0..N` vs `1..N`), `Solicitud_Renta [1] --- (Incluye) --- [N] Solicitud_servicio` exigiendo al menos 1 extra (debe ser `[0..N]`, además comparte etiqueta `1` visual con `Bloque_solicitado`), `Propuesta_Fecha [1] --- [0..3] Opción_Fecha` (debe ser `[1..3]`), y `Servicio [1] --- [N] Detalle_Cotización` (debe ser `[0..1]`).
  * Lectura verbal invertida (`Bloque_solicitado Contiene Solicitud_Renta`, `Pago Recibe Transaccion`, `Notificación_pago Recibe Pago`, verbo `Recibe` repetido 4 veces) y nombres técnicos desalineados del glosario oficial (`OrdenCompra`, `DisponibilidadButaca`, `BloqueoAgenda`, `ConfiguracionSistema`, `RegistroAuditoria`, `folio_corto`, `expira_en`, `stripe_event_id`).

### `[ER-I06]` 11 flujos de negocio de `alcance.md` invisibles desde el ER
* **Respaldo EGM:** `egm-comprehension`, `egm-implementation-readiness`.
* **Impacto:** Un desarrollador nuevo no puede inferir del diagrama: (1) Eventos Directos sin cotización; (2) diferenciación `Comercial` / `Público` / `Privado` (`OPERACION_SIN_CARTELERA`); (3) Turnos oficiales; (4) montaje/ensayos sin cobro extra en multi-día/multi-función; (5) esquema `50/50` + corte `D-21` + veto de fichas en últimas 48 h; (6) pagos extemporáneos `72 h` (`REEMBOLSO_BANCARIO_PENDIENTE`) y gracia/reasignación/reembolso automático en boletos; (7) `VENCIDO_SIN_PUBLICAR` (4 resoluciones + recordatorios `3d/7d`); (8) `REPROGRAMADO` sobre `Funcion`; (9) Bloqueo Técnico vs. Cortesía `` `$0.00 MXN` ``; (10) Modo Contingencia y reconciliación en lote; (11) límite `<= 10`, cierres independientes (`-30m`/`0m`), ventana QR (`-2 h`), ADP y `ExclusionConstraint`.

---

## 4. Hallazgos Medios / YAGNI / Defectos de Notación y Diagrama

* **`[ER-M01]` Entidad y atributos fuera de alcance (YAGNI / residuos `Ticketmaster`):** `Artista_Organizacion` (con check verde y relación `M:N` `Participa`), `Carrito.cargo_procesamineto` *(sic)*, `DetalleCarrito.cargo_servicio`, `DetalleCarrito.precio_paquete` (violan la absorción de comisiones por el teatro en §3.6/§5 y la exclusión de descuentos/paquetes en §4.7), `Boleto.codigo_barras` (solo se usa QR HMAC + `folio_corto`), y `Usuario.pais` / `Usuario.codigo_postal`.
* **`[ER-M02]` Redundancias y ambigüedades semánticas de atributos:** `Asiento.palco` + `Asiento.codigo_palco` + `Asiento.estado`; `Solicitud_Renta.tipo_evento` vs. `modalidad`; `Servicio.precio` vs. `precio_referencia`; `Cotización.importe_renta` vs. `subtotal_estimado` vs. `total_oficial`; `Funcion.fecha_hora` + `hora_inicio_funcion` + `hora_final_funcion`.
* **`[ER-M03]` Sobre-normalización frente al plazo de 4 semanas / 6 integrantes:** Mantener `30` entidades fragmentadas triplica `JOIN`s, serializadores, migraciones y pruebas frente a las `13` entidades nucleares de `arquitectura.md`.
* **`[ER-M04]` Defectos técnicos en el archivo XML/SVG:** Typo `cargo_procesamineto`; atributo huérfano `fecha_envio` (`tgt=None`) encima de `Propuesta_Fecha`; conector auto-bucle en `Detalle_Transaccion.precio_base` (`Architects Daughter`); arista fantasma degenerada `_8rSmAYqaTynVGkd0J08-44` (`sourcePoint == targetPoint` en `(2858.93, 793.96)`); y grupo `_8rSmAYqaTynVGkd0J08-61` con `value="1"`.
* **`[ER-M05]` Notación Chen incompleta e inconsistencia tipográfica:** `0` PKs subrayadas, `0` atributos derivados/multivaluados, `0` entidades débiles con doble borde; `5` checks verdes sin leyenda; mezcla de estilos (`Cuota_Arre_id`, `Concepto`, `Importe`, `Vence_en`, `DetalleCarrito` vs. `Detalle_Transaccion`, tildes erráticas como `fecha_creación` vs. `fecha_creacion`) y etiquetas con HTML incrustado (`<font>`, `<span>`, `<code>`).

---

## 5. Matriz de Mapeo / Consolidación de Entidades (`ER v5.3` → Modelo Alineado)

| # | Entidad en ER v5.3 | Acción | Entidad / Módulo Objetivo | Ajustes clave requeridos |
| :---: | :--- | :--- | :--- | :--- |
| 1 | `Artista_Organizacion` | **Eliminar (YAGNI)** | — | Residuo `Ticketmaster`; usar `Evento.descripcion`. |
| 2 | `Asiento` | **Renombrar y ajustar** | `Butaca` (`inventario`) | Quitar `estado`, `palco`, `codigo_palco`; añadir `fila_orden`, `columna`, `cabina_palco`; mantener `es_accesible`. |
| 3 | `Asiento_evento` | **Eliminar (YAGNI/Bug)** | — | Anti-patrón; impide secciones deshabilitadas y penaliza el *polling*. |
| 4 | `Bloque_solicitado` | **Mantener y ajustar** | `BloqueSolicitado` (`cotizaciones`) | Añadir `turno_id` (`Turno`), `finalidad` (`EVENTO \| MONTAJE_ENSAYO`) y FK a `Cotizacion`. |
| 5 | `Boleto` | **Mantener y ajustar** | `Boleto` (`boletos`) | Añadir `funcion_id`, `beneficiario_cortesia`, `motivo_cortesia`, `validado_en_contingencia`, invalidación, `folio_corto`, `validado_por`; quitar `codigo_barras`; `[0..N]` desde `DisponibilidadButaca`. |
| 6 | `Carrito` | **Fusionar en `OrdenCompra`** | `OrdenCompra` (`ventas`) | Unificar con `Transaccion`; quitar `cargo_procesamineto`; añadir `canal`, `cajero_id`, `gracia_hasta`, `payment_intent_id`, `usuario_id` nullable. |
| 7 | `Categoria` | **Mantener** | `Categoria` (`cartelera`) | Catálogo fijo de 7 categorías sembradas por `seed_catalogos.py`. |
| 8 | `Configuracion_sistema` | **Renombrar y completar** | `ConfiguracionSistema` (`configuracion`) | PK singleton, ~17 parámetros editables (separar `cierre_web_min` y `cierre_taquilla_min`), `actualizado_por`. |
| 9 | `Cotización` | **Mantener y absorber** | `Cotizacion` (`cotizaciones`) | Absorbe `Solicitud_Renta` y `Reserva_renta`; añadir `50/50`, `D-21`, `72 h`, `estado_liquidacion`, cancelación y `snapshot_parametros`. |
| 10 | `Cuota_Arrendamiento` | **Mantener y ajustar** | `CuotaArrendamiento` (`cotizaciones`) | Añadir `tipo_cuota` (`ANTICIPO_50 \| SALDO_50 \| TOTAL_100`), `fecha_limite_ficha` (`D-21 - 48 h`) y `snake_case`. |
| 11 | `Detalle_Cotización` | **Mantener y ajustar** | `DetalleCotizacion` (`cotizaciones`) | `servicio_id` opcional (`[0..1]`), `turno_id` opcional (`Turno`), `tipo_concepto` y `unidad_cobro` snapshot. |
| 12 | `Detalle_Transaccion` | **Eliminar / Fusionar** | `OrdenCompra` + `DisponibilidadButaca` | Enlazar `DisponibilidadButaca` directo a `OrdenCompra` (y `Boleto` para historial). |
| 13 | `DetalleCarrito` | **Eliminar / Fusionar** | `OrdenCompra` + `DisponibilidadButaca` | Purgar `cargo_servicio` y `precio_paquete` (fuera de alcance). |
| 14 | `Evento` | **Mantener y ajustar** | `Evento` (`cartelera`) | `cotizacion_id` nullable (Eventos Directos); añadir `creado_por`, `proximo_recordatorio_en`, `VENCIDO_SIN_PUBLICAR`, cancelación; quitar `aprobado_por` duplicado. |
| 15 | `Funcion` | **Mantener y ajustar** | `Funcion` (`cartelera`) | FK a `BloqueoAgenda`; reemplazar `fecha_hora` por `fecha` + `hora_inicio`/`hora_fin` + `inicio_en`/`fin_en` UTC; añadir `REPROGRAMADO` y modo contingencia. |
| 16 | `Funcion_asiento` | **Renombrar y ajustar** | `DisponibilidadButaca` (`inventario`) | Enlazar directo a `Funcion`, `Butaca`, `SubseccionTarifaria` y `OrdenCompra`; añadir bloqueo técnico y `UNIQUE(funcion_id, butaca_id)`. |
| 17 | `Notificación_pago` | **Renombrar y completar** | `WebhookStripe` (`ventas`) | Tabla `stripe_webhook_events` (`stripe_event_id` PK, `estado`, `modulo`, `tipo_evento`, `payload`, timestamps); desligar de `[1] Pago`. |
| 18 | `Ocupación_teatro` | **Renombrar y refactorizar** | `BloqueoAgenda` (`agenda`) | Quitar `reserva_id` (`ADR-07`); usar `rango_tiempo` `TSTZRANGE`, `origen`, `estado`, `expira_en` y `ExclusionConstraint`. |
| 19 | `Opción_Fecha` | **Renombrar y completar** | `OpcionPropuestaFecha` (`cotizaciones`) | Corregir `[1..3]`, enlazar a `BloqueoAgenda`, añadir `fecha`, `turno_id`, `hora_inicio`, `hora_fin`, `orden` y `estado`. |
| 20 | `Pago` | **Mantener y ajustar** | `Pago` (`ventas` / pasarela) | Separar `stripe_payment_intent_id`, `stripe_refund_id`, `idempotency_key`, ficha SPEI/efectivo, `REEMBOLSO_BANCARIO_PENDIENTE` y `CHECK` XOR. |
| 21 | `Propuesta_Fecha` | **Mantener y ajustar** | `PropuestaFecha` (`cotizaciones`) | Vincular a `Cotizacion` (soporta reprogramaciones); integrar `fecha_envio` huérfana como `enviada_en`. |
| 22 | `Registro_auditoría` | **Renombrar y completar** | `RegistroAuditoria` (`auditoria`) | Conectar `actor_id` FK (`Usuario`) + `actor_rol`; añadir `modulo`, `entidad_id`, `detalles` JSONB, `ip_origen`, `request_id` (*append-only*). |
| 23 | `Reserva_renta` | **Fusionar en `Cotizacion`** | `Cotizacion` + `BloqueoAgenda` | Duplicaba `CONFIRMADO`/`folio` y rompía `PRE_RESERVADO` 48 h. |
| 24 | `Sección` | **Renombrar** | `Seccion` (`inventario`) | Catálogo fijo de las 6 secciones oficiales (`Luneta`, `Platea`, `Mezzanine`, `Primer Piso`, `Segundo Piso`, `Palcos`). |
| 25 | `Servicio` | **Renombrar y ajustar** | `ServicioExtra` (`configuracion`) | Conservar `precio_referencia` (quitar `precio`), añadir `tipo_concepto` (`EXTRA \| INFRAESTRUCTURA`) y `activo`. |
| 26 | `Solicitud_Renta` | **Fusionar en `Cotizacion`** | `Cotizacion` (`cotizaciones`) | Unifica ciclo ME-01; añadir `es_multidia`, `atrasada`, `respondida_en`, `categoria_id`; quitar `tipo_evento`. |
| 27 | `Solicitud_servicio` | **Fusionar en `DetalleCotizacion`** | `DetalleCotizacion` (`cotizaciones`) | Unifica extras solicitados y cotizados en un único desglose con snapshot. |
| 28 | `Subsección_tarifaria` | **Renombrar y completar** | `SubseccionTarifaria` (`cartelera`) | Añadir `fila_inicio/fin`, `col_inicio/fin`, `palco_ids`, `habilitada`, `congelada`, `CHECK >= 100.00` y `UNIQUE(evento, seccion, nombre)`. |
| 29 | `Transaccion` | **Fusionar en `OrdenCompra`** | `OrdenCompra` (`ventas`) | Concentra el ciclo completo de boletaje (`APARTADO`..`REEMBOLSADA_AUTOMATICA`). |
| 30 | `Usuario` | **Mantener y ajustar** | `Usuario` (`usuarios`) | Quitar `pais`, `codigo_postal`; añadir `acepto_privacidad_en`, `acepto_terminos_en`, `session_version`, `is_staff`, `is_superuser`, `last_login`, timestamps. |
| +1 | *(No existe en ER)* | **Agregar faltante** | `Turno` (`configuracion`) | Catálogo de turnos (`Matutino`, `Vespertino`, `Día Completo`), `hora_inicio`, `hora_fin`, `tarifa_renta` (`Decimal(10, 2)`). |

**Balance numérico de consolidación:** De **30** entidades en `v5.3` se eliminan **4** (`Artista_Organizacion`, `Asiento_evento`, `DetalleCarrito`, `Detalle_Transaccion`), se fusionan otras **4** entidades excedentes al consolidar (`Carrito`+`Transaccion` → `OrdenCompra` [-1]; `Solicitud_Renta`+`Reserva_renta`+`Cotización` → `Cotizacion` [-2]; `Solicitud_servicio`+`Detalle_Cotización` → `DetalleCotizacion` [-1]) y se añade **1** (`Turno`), quedando **23** tablas normalizadas — o **~16–18 tablas** alineadas directamente a las **13 entidades nucleares** de `arquitectura.md` si `Categoria`/`Seccion` operan como `TextChoices` o catálogos embebidos y `CuotaArrendamiento`/`OpcionPropuestaFecha` se consolidan en `Pago`/`BloqueoAgenda`.

---

## 6. Estado del Repositorio y Deriva Residual en Documentos Complementarios

1. **Estado real verificado en el repositorio:**
   * `docs/modelo-datos.md`: aún no existe (pese a ser citado en [alcance.md](../alcance.md#L54) y [arquitectura.md](../arquitectura.md#L282)).
   * [01_esquema.sql](../../database/01_esquema.sql), [02_inserts_teatro.sql](../../database/02_inserts_teatro.sql), [03_inserts_demo.sql](../../database/03_inserts_demo.sql), [pruebas.yml](../../.github/workflows/pruebas.yml), [models.py](../../backend/apps/ventas/models.py) y [seed_teatro.py](../../backend/apps/inventario/management/commands/seed_teatro.py) (`seed_catalogos.py`, `seed_demo.py`): todos tienen `0` bytes (vacíos).
   * [settings.py](../../backend/config/settings.py#L22-L33): `INSTALLED_APPS` aún no registra ninguna app de `backend/apps/*`, y las apps restantes (incluida `configuracion/`) aún no tienen modelos implementados.
2. **Deriva residual detectada fuera de los tres documentos auditados previamente:**
   * [maquinas-de-estado.md](../maquinas-de-estado.md#L29): Conserva `28 días` en `§2.1` y `T-1.4` (L42) frente a los **`21 días naturales`** unificados en `alcance.md` y `arquitectura.md`, además de ubicar `REPROGRAMADO` en `Cotización` (`T-1.11`, L49) en vez de marca sobre `Funcion` (con boletos vendidos).
   * [me04-butaca-qr.puml](../maquinas-de-estado/me04-butaca-qr.puml#L18): Indica `Admin/Cajero emite cortesía`, mientras que `alcance.md` (§2.3 L61) y `arquitectura.md` (L350–352) restringen las cortesías exclusivamente a `ADMIN`.
