# Auditoría de Sincronización Global — Diseño, Reglas de Negocio, Diagramas y Skills

* **Fecha:** 2026-11-26
* **Tipo:** Auditoría Cruzada de Consistencia y Sincronización (Multi-agente)
* **Ubicación del reporte:** `docs/reportes/egm/auditoria-sincronizacion-diseno-skills-2026-11-26.md`
* **Artefactos y Fuentes de Verdad Contrastadas:**
  * **Fuentes de Verdad:**
    * [alcance.md](../../alcance.md)
    * [arquitectura.md](../../arquitectura.md)
    * [modelo-datos.md](../../modelo-datos.md) (v6.2: 44 tablas, 6 módulos base, 5 módulos de dominio)
    * [stack-tecnologico.md](../../stack-tecnologico.md)
    * [maquinas-de-estado.md](../../maquinas-de-estado.md) y diagramas PlantUML en [maquinas-de-estado/](../../maquinas-de-estado/) (`me01` a `me04`)
  * **Especificación de Requisitos y Calidad:**
    * [requisitos-funcionales.md](../../requisitos/requisitos-funcionales.md) (`RF-01` a `RF-103`)
    * [requisitos-no-funcionales.md](../../requisitos/requisitos-no-funcionales.md) (`RNF-01` a `RNF-43` bajo ISO/IEC 25010)
    * [plan-pruebas.md](../../plan-pruebas.md) (Matriz RTM completa, pruebas de carga con `k6`, concurrencia y mutación)
  * **Contrato de API y Prototipo UI:**
    * [contrato-api.md](../../contrato-api.md) (Interfaz REST v1)
    * `docs/aforo_preliminar.json`
    * Documentación del prototipo: `docs/prototipo/seatmap-and-states.md`, `docs/prototipo/surfaces-and-layouts.md`, `docs/prototipo/design.json`, `docs/prototipo/DESIGN.md`, `docs/prototipo/PRODUCT.md`
  * **Diagramas UML:**
    * Clases y enumeraciones en `docs/diagramas-uml/`
    * Diagramas de Robustez (`RB01` a `RB10`) y Secuencia (`SD01` a `SD10`)
  * **Skills y Reglas de Agente:**
    * `AGENTS.md` y `.agents/skills/AGENT.md`
    * `.agents/skills/teatro-reglas-negocio/SKILL.md`
    * `.agents/skills/django-teatro-backend/SKILL.md`
    * `.agents/skills/react-teatro-frontend/SKILL.md`
    * `.agents/skills/teatro-design-system/SKILL.md`
    * `.agents/skills/playwright-vitest-teatro/SKILL.md`
    * `.agents/skills/ooad-generador-requisitos/SKILL.md`
    * `.agents/skills/frontend-design/SKILL.md`
    * `.agents/skills/plantuml-*/SKILL.md`
* **Metodología:** Auditoría cruzada ejecutada mediante dos subagentes independientes sin contexto previo (*zero-shot*), enfocados en:
  1. *Subagente 1:* Trazabilidad vertical (Fuentes de verdad vs. Requisitos, Modelo Relacional v6.2, Máquinas de Estado, Contrato API y Plan de Pruebas).
  2. *Subagente 2:* Coherencia horizontal (Skills de backend/frontend/diseño vs. Modelo v6.2, Prototipo UI, Diagramas UML y Reglas Operativas).

---

## 1. Resumen Ejecutivo y Veredicto

El proyecto presenta una **alta coherencia y robustez en la definición de reglas de negocio centrales**, habiéndose verificado la perfecta alineación en los siguientes ejes críticos:
- **Reglas temporales e importes:** Zona horaria `America/Mexico_City`, persistencia en UTC (`TIMESTAMPTZ`), importes en `Decimal(10, 2)` con redondeo `ROUND_HALF_UP`, compra mínima de `$100.00 MXN`, plazos de apartado (`10 min + 5 min`), cierres de taquilla (`-30 min` presencial / `0 min` en línea), retención 50/50 (`> 30 días / D-21 23:59:59`), SLA de cotizaciones (`3/5 días hábiles`), pre-reserva de 48 h, ventana de gracia de 72 h por pago tardío y vigencia de 24 h en contingencia.
- **Trazabilidad RTM (Requirements Traceability Matrix):** La matriz en [plan-pruebas.md](../../plan-pruebas.md) cubre al 100% los 103 `RF`, los 43 `RNF` (en las 6 categorías ISO/IEC 25010), las 43 transiciones de estado oficiales y los 10 diagramas de secuencia (`SD01`–`SD10`).
- **Seguridad y Acceso:** 6 mensajes literales exactos del escáner QR, orden estricto de candados pesimistas (`Usuario -> OrdenCompra -> DisponibilidadButaca -> OrdenCompraDetalle -> Boleto`), uso de tokens CSRF con cookies `HttpOnly`, y unificación del umbral responsive en `360px`.

No obstante, la evolución estructural del repositorio (en particular la transición del modelo de datos de v5.3 a v6.2, la expansión de las especificaciones funcionales y la adición del contrato de API) introdujo **desincronizaciones y lagunas documentales** que requieren remediación antes del inicio formal de la fase de codificación.

### Tabla de Hallazgos Consolidados

| Severidad | Total | Ejes Impactados |
| :--- | :---: | :--- |
| 🔴 **CRÍTICO** | **5** | Aforo oficial, transiciones de máquina de estado, reapertura de cancelaciones institucionales, tablas huérfanas entre API y BD, y divergencia de enums. |
| 🟡 **ALTO** | **7** | Visibilidad de cortesías en frontend, residuo de `bulk_create` (1,728 vs `<= 1,728`), UI de validación QR, discrepancia de rutas `/gestion/`, parámetros faltantes en `configuracion_sistema`, residuos pre-v6.2 en arquitectura, y colisión de directrices de diseño. |
| 🔵 **MEDIO** | **6** | Dependencia `mutmut` sin `pytest`, `import-linter` plano, enlaces rotos en docs, trazabilidad de reglas de montaje, omisión de `429` en contrato, y detalles de pruebas concurrentes. |
| 🟢 **BAJO** | **4** | Campos opcionales en cuentas internas, estandarización de errores de validación, documentación de turnos mixtos y metadatos de versión en diagramas. |

---

## 2. Hallazgos Detallados por Severidad

### 🔴 Severidad CRÍTICA

#### `[DIS-C01]` Aforo total divergente: 1,728 butacas normativas vs 1,730 en `docs/aforo_preliminar.json`
* **Artefactos impactados:** `docs/aforo_preliminar.json`, [alcance.md](../../alcance.md) §2.3, [modelo-datos.md](../../modelo-datos.md) v6.2, [teatro-design-system/SKILL.md](../../../.agents/skills/teatro-design-system/SKILL.md), `docs/prototipo/seatmap-and-states.md`.
* **Discrepancia:** Todas las fuentes normativas y el modelo relacional v6.2 fijan el aforo invariante en **1,728 butacas** distribuidas en 6 secciones oficiales:
  - Luneta: 564
  - Segundo Nivel: 288
  - Tercer Nivel: 288
  - Cuarto Nivel: 288
  - Palcos Primer Piso: 150
  - Palcos Segundo Piso: 150
  *(Total = 564 + 288*3 + 300 = 1,728).*
  Sin embargo, en `docs/aforo_preliminar.json` la Luneta tiene **566 asientos** (aparecen filas de Luneta con 2 asientos de más), sumando un total de **1,730**. Asimismo, en `seatmap-and-states.md` se introduce confusión textual al describir `1,728 (+12 accesibles)` como si fueran adicionales, cuando [alcance.md](../../alcance.md) y [modelo-datos.md](../../modelo-datos.md) dejan claro que las 12 plazas accesibles están **incluidas** dentro de las 1,728.
* **Impacto:** Si el seeder de base de datos o el frontend cargan `aforo_preliminar.json`, se romperán las restricciones de unicidad e integridad referencial y se sobrepasará la capacidad estructural del recinto.
* **Remediación:** Corregir inmediatamente `docs/aforo_preliminar.json` eliminando las 2 butacas excedentes en Luneta para totalizar exactamente 564 en dicha sección y 1,728 globales. Clarificar en `seatmap-and-states.md` que las 12 plazas accesibles forman parte integral del aforo de 1,728.

---

#### `[DIS-C02]` Transición errónea de prórroga (T-2.5) en `maquinas-de-estado.md` salta directo a `PUBLICADO`
* **Artefactos impactados:** [maquinas-de-estado.md](../../maquinas-de-estado.md) §2 (T-2.5, L188), [me02-evento.puml](../../maquinas-de-estado/me02-evento.puml), [alcance.md](../../alcance.md) §2.9.D, [RF-40](../../requisitos/requisitos-funcionales.md).
* **Discrepancia:** La transición `T-2.5` establece el flujo cuando un evento cae en `VENCIDO_SIN_PUBLICAR` (por expirar a las 72 h tras aprobación) y el Administrador concede una prórroga de 48 h. En [maquinas-de-estado.md](../../maquinas-de-estado.md), la tabla indica que el evento pasa de `VENCIDO_SIN_PUBLICAR` directamente a `PUBLICADO`.
* **Impacto:** Rompe la guarda de negocio `CHECK (poster IS NOT NULL)` y el flujo operativo: el evento no se había publicado precisamente porque faltaba material gráfico (o configuración final). Conceder prórroga debe otorgar tiempo al productor para completar los requisitos, regresando el evento al estado `PENDIENTE_PUBLICACION`.
* **Remediación:** Ajustar `T-2.5` en [maquinas-de-estado.md](../../maquinas-de-estado.md) y en [me02-evento.puml](../../maquinas-de-estado/me02-evento.puml) para que el estado destino sea `PENDIENTE_PUBLICACION`, con temporizador restablecido a 48 h.

---

#### `[DIS-C03]` Reanudación de cotización tras cancelación institucional (T-1.16) marcada como terminal
* **Artefactos impactados:** [me01-cotizacion-arrendamiento.puml](../../maquinas-de-estado/me01-cotizacion-arrendamiento.puml), [alcance.md](../../alcance.md) §2.6 (L156), [RF-48](../../requisitos/requisitos-funcionales.md), [contrato-api.md](../../contrato-api.md) L335.
* **Discrepancia:** En [alcance.md](../../alcance.md) §2.6 y en `RF-48`, si el Teatro cancela un evento por causas de fuerza mayor o institucionales (T-1.16), el productor tiene derecho a **reprogramar sin costo** dentro de los siguientes 30 días naturales. Sin embargo, en el diagrama PlantUML `me01-cotizacion-arrendamiento.puml`, la transición de cancelación por el Teatro conduce a un estado terminal `[*]` sin ninguna transición saliente hacia reprogramación o reactivación.
* **Impacto:** Si la máquina de estados bloquea el expediente como terminal, el sistema obligará a crear una cotización completamente nueva desde cero y perderá la trazabilidad del saldo a favor / anticipo pagado.
* **Remediación:** Modelar en `me01` una transición o sub-estado `CANCELADA_REPROGRAMABLE` o una transición `reprogramar` que permita generar un nuevo expediente vinculado o reactivar la cotización conservando el comprobante financiero.

---

#### `[DIS-C04]` Discrepancias estructurales entre `contrato-api.md` y `modelo-datos.md` v6.2
* **Artefactos impactados:** [contrato-api.md](../../contrato-api.md) §3, §4, §6; [modelo-datos.md](../../modelo-datos.md) v6.2.
* **Discrepancia:** Varios endpoints definidos en el contrato de API no cuentan con soporte en las 44 tablas del modelo relacional v6.2:
  1. `POST cotizaciones/{id}/cambios/` (solicitud de cambios de cotización): no existe tabla `solicitud_cambio_cotizacion` ni columnas equivalentes en `cotizacion` o `arrendamiento_evento`.
  2. `cotizacion.poster`: en el contrato se lee `poster` en cotizaciones, pero en el modelo relacional v6.2 el póster pertenece estrictamente a la tabla `evento` (`cartelera`).
  3. `POST ventas/ordenes/{id}/anulaciones/`: no existe tabla ni estado `ANULADA` en `orden_compra` (solo existen 5 estados en `OrdenCompra`: `APARTADO`, `PAGO_EN_PROCESO`, `PAGADA`, `EXPIRADA`, `REEMBOLSADA_AUTOMATICA`).
  4. Bitácora de reimpresiones en Taquilla (`boletos/reimpresiones/`): no existe tabla de auditoría específica para reimpresión física (debe mapearse a `registro_auditoria` con acción tipificada o definirse explícitamente).
* **Impacto:** Imposibilidad de generar migraciones de Django que satisfagan el contrato de API sin inventar tablas o campos fuera de la fuente de verdad.
* **Remediación:** Clarificar si las solicitudes de cambios y anulaciones se gestionan mediante eventos tipificados en `registro_auditoria` o si se requiere una migración controlada que añada tablas específicas; alinear `poster` como atributo exclusivo de `evento`.

---

#### `[DIS-C05]` Divergencia en enumeraciones y nombres de atributos entre módulos
* **Artefactos impactados:** [contrato-api.md](../../contrato-api.md), [modelo-datos.md](../../modelo-datos.md), [maquinas-de-estado.md](../../maquinas-de-estado.md), `.agents/skills/django-teatro-backend/SKILL.md`.
* **Discrepancia:** Existen discrepancias léxicas que provocarán fallos de serialización y deserialización:
  - Método de pago: `FICHA_SPEI` (en contrato L214) vs `SPEI` (en `modelo-datos.md` y `maquinas-de-estado.md`).
  - Tipo de reembolso: `REEMBOLSO` (en contrato) vs `REEMBOLSO_EXTERNO` (en modelo relacional).
  - Puerta de acceso: `acceso_puerta` (en contrato) vs `puerta_acceso` (en `modelo-datos.md`).
  - Tipo de actividad en agenda: `finalidad` con valores `['EVENTO', 'MONTAJE_ENSAYO']` (en contrato L287) vs `actividad` con valores `['MONTAJE', 'FUNCION']` (en `modelo-datos.md` y `alcance.md`).
  - Acciones sobre evento vencido: `APOYO_ADMIN`, `PRORROGA`, `OPERACION_SIN_CARTELERA`, `CANCELACION` (en contrato L67) vs `PUBLICAR`, `PRORROGAR`, `REALIZAR_SIN_PUBLICACION`, `CANCELAR` (en `maquinas-de-estado.md` L208).
  - Discriminador de auditoría: `VENTAS` y `COTIZACIONES` (mayúsculas en contrato) vs `venta` y `cotizacion` (minúsculas en `modelo-datos.md`).
* **Impacto:** Inconsistencias de validación en DRF (`ValidationError`) y fallos en consultas SQL que filtren por enumeraciones.
* **Remediación:** Homogeneizar todos los enums en `contrato-api.md` adoptando estrictamente los identificadores de `modelo-datos.md` v6.2.

---

### 🟡 Severidad ALTA

#### `[DIS-A01]` Representación de butacas `CORTESIA` en el mapa público
* **Artefactos impactados:** `docs/prototipo/seatmap-and-states.md` (L63), [alcance.md](../../alcance.md) §2.3, [contrato-api.md](../../contrato-api.md) §3 (L108).
* **Discrepancia:** En `seatmap-and-states.md` se afirma que las butacas con cortesía se muestran en el mapa público agrupadas indistinguiblemente bajo el estado visual de `VENDIDA`. Sin embargo, [alcance.md](../../alcance.md) §2.3 y [contrato-api.md](../../contrato-api.md) establecen expresamente que el endpoint de mapa y el cliente público diferencian **5 estados de inventario**: `DISPONIBLE`, `APARTADA`, `VENDIDA`, `CORTESIA` y `BLOQUEADA`.
* **Impacto:** Confusión en la implementación del componente React del mapa de butacas (`SeatMap.tsx`) y divergencia entre la UI y los datos servidos por `/api/v1/cartelera/eventos/{id}/mapa/`.
* **Remediación:** Unificar el criterio: en el backend y en la API siempre se devuelve el estado real (`CORTESIA`). En la UI pública, si por regla comercial el usuario general no debe comprarla, se estiliza con el color correspondiente a cortesía o se bloquea para selección, respetando los 5 estados documentados.

---

#### `[DIS-A02]` Residuos en skills sobre `bulk_create` fijo de 1,728 butacas
* **Artefactos impactados:** `.agents/skills/django-teatro-backend/SKILL.md` (L63 vs L71), `.agents/skills/teatro-reglas-negocio/SKILL.md` (L19), `.agents/skills/playwright-vitest-teatro/SKILL.md` (L22).
* **Discrepancia:** En el modelo relacional previo (v5.3), cada función generaba 1,728 registros obligatorios en `disponibilidad_butaca`. En el modelo v6.2 (ADR de aforo dinámico por evento), **solo se generan registros para las butacas pertenecientes a las secciones oficiales habilitadas en el evento** (`seccion_evento`), sumando un total `<= 1,728`. Sin embargo, varias skills conservan frases que exigen crear exactamente 1,728 filas por función.
* **Impacto:** Un desarrollador o agente que implemente `EventoService.crear_funcion()` intentará poblar 1,728 registros incluso cuando el evento sea solo en Luneta (564 butacas), generando registros huérfanos sin tarifa asociada.
* **Remediación:** Actualizar las skills de backend y reglas de negocio para explicitar que `bulk_create` genera `N` registros (`N <= 1,728`) correspondientes a las butacas de las secciones activas del evento.

---

#### `[DIS-A03]` Desalineación de diseño en la interfaz de escaneo QR (Taquilla y Acceso)
* **Artefactos impactados:** `.agents/skills/react-teatro-frontend/SKILL.md`, `docs/prototipo/surfaces-and-layouts.md`.
* **Discrepancia:** En `react-teatro-frontend/SKILL.md` se instruye ubicar el input de validación manual de folio/alfanumérico **debajo del visor de la cámara**, mientras que en `surfaces-and-layouts.md` se define el input **encima del botón principal de acción**, con una distribución de teclado numérico específica.
* **Impacto:** Inconsistencia ergonómica en terminales móviles o tabletas de acceso para el personal de puerta.
* **Remediación:** Estandarizar la maqueta en `react-teatro-frontend` y en el prototipo, priorizando la ergonomía operativa recomendada en `teatro-design-system`.

---

#### `[DIS-A04]` Inconsistencia en la estructura de vistas de la consola `/gestion/`
* **Artefactos impactados:** [arquitectura.md](../../arquitectura.md) §3.4, `docs/prototipo/surfaces-and-layouts.md`.
* **Discrepancia:** [arquitectura.md](../../arquitectura.md) especifica **6 vistas principales** en la SPA `/gestion/` (Dashboard, Cotizaciones, Cartelera/Eventos, Taquilla, Accesos/QR, Auditoría/Reportes), mientras que en los prototipos HTML y en `surfaces-and-layouts.md` se desglosan **8 vistas independientes** (separando Mantenimientos/Agenda técnica y Configuración/Tarifario en rutas de primer nivel).
* **Impacto:** Desfase en el enrutamiento de React Router (`AppRoutes.tsx`) y en la comprobación de permisos RBAC por vista.
* **Remediación:** Reflejar en `arquitectura.md` si las rutas son 6 agrupadas con pestañas secundarias o si se adoptan las 8 rutas directas de la barra lateral.

---

#### `[DIS-A05]` Parámetros y restricciones en `configuracion_sistema`
* **Artefactos impactados:** [modelo-datos.md](../../modelo-datos.md) v6.2 (tabla `configuracion_sistema`), [alcance.md](../../alcance.md) §2.4, [requisitos-funcionales.md](../../requisitos/requisitos-funcionales.md) (`RF-06` a `RF-08`).
* **Discrepancia:** En `modelo-datos.md` v6.2 se incluye el parámetro `limite_boletos` en la tabla `configuracion_sistema`. Sin embargo, [alcance.md](../../alcance.md) §2.4 y los requerimientos funcionales fijan el límite de boletos como una constante invariable de negocio (`<= 10` boletos por orden) que no es configurable por el Administrador. Además, los campos `cierre_taquilla_min` y `retencion_cancelacion_pct` tienen restricciones `CHECK >= 0`, cuando la regla de negocio exige `cierre_taquilla_min > 0` (presencial 30 min) y `retencion_cancelacion_pct = 50.00`.
* **Impacto:** Ambigüedad sobre si el límite de 10 boletos puede alterarse en tiempo de ejecución o si debe quedar como constante inmutable de backend.
* **Remediación:** Ajustar la documentación de `configuracion_sistema` aclarando qué parámetros son dinámicos y cuáles son constantes fijas del sistema.

---

#### `[DIS-A06]` Residuos de arquitectura pre-v6.2 en `docs/arquitectura.md`
* **Artefactos impactados:** [arquitectura.md](../../arquitectura.md) L225, L313, L318–319, L500.
* **Discrepancia:** En [arquitectura.md](../../arquitectura.md) subsisten referencias al diseño relacional anterior:
  - L225: Se menciona `payment_intent_id` dentro de `orden_compra`, cuando en v6.2 se normalizó en la tabla desacoplada `pago`.
  - L313: Se referencia `hora_inicio` y `hora_fin` en la entidad `Funcion`, mientras que en v6.2 se normalizaron a `fecha_hora_inicio` y `fecha_hora_fin` (`TIMESTAMPTZ`).
  - L318–319: Se listan estados de pago antiguos (`EN_REVISION`, `APROBADO`, `RECHAZADO`), contradiciendo los estados oficiales de `pago` (`PENDIENTE`, `COMPLETADO`, `FALLIDO`, `REEMBOLSADO`).
  - L500: Se menciona una tarea periódica que libera "todos los apartados vencidos", omitiendo la comprobación por función y el candado pesimista ordenado.
* **Impacto:** Confusión técnica durante la lectura de la arquitectura de backend.
* **Remediación:** Actualizar las líneas indicadas en `arquitectura.md` para reflejar con exactitud las columnas y estados del modelo relacional v6.2.

---

#### `[DIS-A07]` Conflicto de diseño tipográfico y cromático entre directrices genéricas y oficiales
* **Artefactos impactados:** `.agents/skills/frontend-design/SKILL.md`, `.agents/skills/teatro-design-system/SKILL.md`.
* **Discrepancia:** La skill general `frontend-design` incluye directivas que desaconsejan fondos cálidos/crema, tipografías serif clásicas y el uso de mayúsculas sostenidas (`ALL CAPS`). En cambio, el sistema de diseño oficial de la institución (`teatro-design-system`) **exige mandatoriamente** el color `Arena Cálida` (`#F6F4EF`), el encabezado monumental en `Cinzel` (fuente serif) y botones en versalitas / mayúsculas para la jerarquía del recinto.
* **Impacto:** Riesgo de que un agente de frontend intente "corregir" la identidad visual oficial aplicando estilos genéricos minimalistas.
* **Remediación:** Confirmar en `AGENT.md` y en `teatro-design-system` que el sistema de diseño institucional prevalece de manera absoluta sobre las recomendaciones estéticas de `frontend-design`.

---

### 🔵 Severidad MEDIA

#### `[DIS-M01]` Dependencia de `mutmut` incompatible con la exclusión de `pytest`
* **Artefactos impactados:** [stack-tecnologico.md](../../stack-tecnologico.md) §3.2, §4.
* **Discrepancia:** En `stack-tecnologico.md` §3.2 se lista `mutmut` como herramienta aprobada de pruebas de mutación, mientras que en §4 se prohíbe explícitamente `pytest` en el backend para preservar la compatibilidad nativa con `Django TestCase`. Sin embargo, las versiones recientes de `mutmut` (v3+) tienen una dependencia dura obligatoria con el arnés de `pytest`.
* **Impacto:** Fallo al intentar correr `mutmut` en el pipeline de CI si no se congela una versión compatible con el runner de Django (`mutmut 2.x`) o un wrapper ejecutor.
* **Remediación:** Especificar en `stack-tecnologico.md` el uso fijado de `mutmut 2.x` con runner personalizado de Django (`python manage.py test`), o detallar su invocación.

---

#### `[DIS-M02]` Agrupación plana de módulos en la configuración de `import-linter`
* **Artefactos impactados:** [stack-tecnologico.md](../../stack-tecnologico.md) §3.2, [arquitectura.md](../../arquitectura.md) §2.
* **Discrepancia:** La configuración de ejemplo de `import-linter` agrupa los 6 módulos base (`usuarios`, `configuracion`, `recinto`, `agenda`, `auditoria`, `pagos`) en un mismo nivel horizontal. No obstante, en la arquitectura existen dependencias internas directas (por ejemplo, `agenda` referencia a `recinto`, y `auditoria` referencia a `usuarios`).
* **Impacto:** Si `import-linter` prohíbe importaciones cruzadas entre módulos base de manera indiscriminada, bloqueará relaciones de clave foránea indispensables para la integridad del sistema.
* **Remediación:** Configurar contratos de capa (`layers`) o contratos de independencia (`independence`) en `import-linter` que permitan dependencias acíclicas autorizadas entre módulos base.

---

#### `[DIS-M03]` Enlaces documentales rotos en el repositorio
* **Artefactos impactados:** [docs/README.md](../../README.md), [modelo-datos.md](../../modelo-datos.md).
* **Discrepancia:** Se identificaron rutas rotas en la navegación interna de la documentación:
  1. `docs/README.md` (L13) enlaza a `informe-cambios-modelo-datos.md` en la raíz de `docs/`, pero el archivo físico se encuentra en `docs/reportes/informe-cambios-modelo-datos.md`.
  2. `modelo-datos.md` (L6–7) enlaza a diagramas y reportes históricos que fueron reorganizados en carpetas (`./reportes/auditoria-egm-er-v5.3.md` en vez de `./reportes/egm/auditoria-egm-er-v5.3.md`).
* **Impacto:** Dificultad de navegación para revisores humanos y herramientas de documentación estática.
* **Remediación:** Corregir los enlaces relativos en `docs/README.md` y en `modelo-datos.md`.

---

#### `[DIS-M04]` Trazabilidad incompleta de reglas de montaje y anticipo en diagramas
* **Artefactos impactados:** [alcance.md](../../alcance.md) §2.9.D, [RF-10](../../requisitos/requisitos-funcionales.md), [RF-11](../../requisitos/requisitos-funcionales.md), diagramas de secuencia `SD01` y `SD02`.
* **Discrepancia:** Las reglas que estipulan que no puede existir una función sin previo montaje técnico (`RF-10`) y la obligatoriedad del anticipo del 50% previo a la publicación en cartelera (`RF-11`) están descritas en prosa y en requerimientos, pero no se detallan con mensajes explícitos de guarda en los diagramas de interacción `SD01` y `SD02`.
* **Impacto:** Riesgo de omisión de validaciones en los serializers o servicios de agenda técnica.
* **Remediación:** Incorporar notas de guarda (`alt / [anticipo_recibido >= 50%]` y `[montaje_previo_valido]`) en los diagramas de secuencia respectivos.

---

#### `[DIS-M05]` Omisión del código HTTP `429 Too Many Requests` en respuestas de error de `contrato-api.md`
* **Artefactos impactados:** [contrato-api.md](../../contrato-api.md) §1, §7.
* **Discrepancia:** Aunque [arquitectura.md](../../arquitectura.md) y [RNF-08](../../requisitos/requisitos-no-funcionales.md) definen límites estrictos de tasa (rate limiting) para login, apartado y validación QR, el contrato de API no documenta el formato del error `429` ni el encabezado `Retry-After`.
* **Impacto:** Los clientes de frontend no tendrán un contrato formal para manejar reintentos controlados ante respuestas de exceso de tasa.
* **Remediación:** Incluir el catálogo de respuestas `429` con el código de error `code: "LIMITE_PETICIONES_EXCEDIDO"` en §7 de `contrato-api.md`.

---

#### `[DIS-M06]` Cobertura explícita de pruebas de concurrencia en Taquilla
* **Artefactos impactados:** [plan-pruebas.md](../../plan-pruebas.md) §4.
* **Discrepancia:** El plan maestro de pruebas detalla exhaustivamente las pruebas concurrentes de apartado web (`10 min + 5 min`), pero omite detallar la prueba de contención de dos cajeros de taquilla intentando cobrar simultáneamente el último asiento disponible en efectivo/terminal presencial.
* **Impacto:** Lagunas en la cobertura de casos de prueba con `TransactionTestCase` para el flujo presencial.
* **Remediación:** Añadir el caso `TC-CONC-04: Conflicto de Venta Simultánea en Taquilla Física` en el plan de pruebas.

---

### 🟢 Severidad BAJA / MEJORA

#### `[DIS-B01]` Campo `apellidos` en cuentas internas de sistema
* **Discrepancia:** `contrato-api.md` exige `apellidos` en la respuesta de usuario, pero las cuentas de servicio o administradores institucionales genéricos pueden no requerirlo.
* **Remediación:** Asegurar que `apellidos` acepte `null` o cadena vacía en serializers de autenticación para personal operativo.

#### `[DIS-B02]` Estandarización de cuerpo JSON para errores de validación
* **Discrepancia:** `contrato-api.md` utiliza `{ "error": "...", "code": "..." }`, mientras que DRF genera por defecto diccionarios anidados por campo en errores `400` (`{ "campo": ["error"] }`).
* **Remediación:** Documentar en el contrato el formateador personalizado de excepciones (`custom_exception_handler`) que unifique la respuesta de DRF bajo el esquema institucional `{ "error": "...", "code": "...", "detalles": { ... } }`.

#### `[DIS-B03]` Documentación de turnos mixtos en `TarifaTurno`
* **Discrepancia:** Se define que un evento puede rentar turnos Matutino, Vespertino o Completo, pero falta detallar la fórmula de descuento o recargo cuando se contrata turno completo.
* **Remediación:** Incorporar una nota en `alcance.md` y `modelo-datos.md` clarificando que la tarifa completa se liquida con base en el catálogo de turnos parametrizado en la base de datos.

#### `[DIS-B04]` Metadatos de versión en diagramas PlantUML
* **Discrepancia:** Varios encabezados de diagramas `.puml` mantienen comentarios con versión `v5.3`.
* **Remediación:** Actualizar los encabezados a `v6.2` mediante un barrido menor en los archivos `.puml`.

---

## 3. Matriz de Preguntas de Diseño para Toma de Decisiones

Para facilitar la resolución coordinada de estos hallazgos, se sintetizan las siguientes **5 preguntas clave**:

| # | Pregunta Clave | Alternativas de Solución | Recomendación Auditoría |
| :-: | :--- | :--- | :--- |
| **1** | ¿Cuál es el aforo exacto e incontrovertible del Teatro? | **A)** 1,728 butacas (564 Luneta, incluyendo 12 accesibles).<br>**B)** 1,730 butacas (566 Luneta). | **Opción A (1,728)**: Alinea el 100% de las fuentes normativas y el modelo relacional v6.2. |
| **2** | ¿Cómo se modelan las solicitudes de cambio de cotización (`POST cotizaciones/{id}/cambios/`)? | **A)** Crear tabla dedicada `solicitud_cambio_cotizacion`.<br>**B)** Registrar en `registro_auditoria` con metadatos en JSONB.<br>**C)** Eliminar endpoint y requerir cancelación y nueva cotización. | **Opción B**: Evita sobrecargar el modelo relacional manteniendo trazabilidad estricta. |
| **3** | ¿Cómo debe visualizarse el estado `CORTESIA` en el mapa de butacas público? | **A)** Identificador diferenciado (5 colores de butacas).<br>**B)** Agrupado visualmente con el color de `VENDIDA` para el público general. | **Opción A en backend / Opción B en frontend público**: El backend siempre envía `CORTESIA`; el frontend público no permite seleccionarla. |
| **4** | ¿Cómo se persiste la anulación de boletos/órdenes en taquilla? | **A)** Agregar estado `ANULADA` en `OrdenCompra`.<br>**B)** Usar estado `REEMBOLSADA_AUTOMATICA` o registrar transacción negativa en `pago`. | **Opción A**: Aporta máxima claridad operativa a los cajeros y corte de caja. |
| **5** | ¿Cómo se ejecutará `mutmut` sin arrastrar la dependencia de `pytest`? | **A)** Fijar `mutmut 2.x` en `stack-tecnologico.md`.<br>**B)** Sustituir `mutmut` por otra técnica o script de mutación propio.<br>**C)** Ejecutar mutación en un contenedor de QA aislado. | **Opción A**: Mantiene la herramienta oficial aprobada sin violar la prohibición de pytest en producción. |

---

## 4. Plan de Acción y Próximos Pasos

1. **Inmediato (P0 — Correcciones de Integridad):**
   - Actualizar `docs/aforo_preliminar.json` para reflejar con exactitud las 564 butacas de Luneta y 1,728 totales.
   - Corregir en [maquinas-de-estado.md](../../maquinas-de-estado.md) y `me02-evento.puml` la transición `T-2.5` (`VENCIDO_SIN_PUBLICAR -> PENDIENTE_PUBLICACION`).
   - Corregir enlaces rotos en [docs/README.md](../../README.md) y [modelo-datos.md](../../modelo-datos.md).
2. **Corto Plazo (P1 — Sincronización de Contratos y Skills):**
   - Homogeneizar enums en [contrato-api.md](../../contrato-api.md) (`SPEI`, `puerta_acceso`, `REEMBOLSO_EXTERNO`, etc.).
   - Actualizar las skills `.agents/skills/django-teatro-backend` y `.agents/skills/teatro-reglas-negocio` eliminando la referencia al `bulk_create` fijo de 1,728 e indicando `<= 1,728` según secciones asignadas.
   - Purgar menciones de columnas y estados obsoletos en [arquitectura.md](../../arquitectura.md).
3. **Mediano Plazo (P2 — Alineación UI y QA):**
   - Incorporar el caso de prueba `TC-CONC-04` de taquilla concurrente en [plan-pruebas.md](../../plan-pruebas.md).
   - Documentar la respuesta `429` y el manejador global de excepciones en el contrato de API.
