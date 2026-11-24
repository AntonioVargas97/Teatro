# Reporte Consolidado de Auditoría EGM — Fuentes de Verdad

* **Documentos auditados exclusivamente:** `docs/alcance.md`, `docs/arquitectura.md` y `docs/stack-tecnologico.md`.
* **Revisores ejecutados:** `egm-design`, `egm-implementation-readiness`, `egm-zoom-out`, `egm-codebase-details` y `egm-comprehension`.
* **Nota de alcance:** Se excluyen `docs/maquinas-de-estado.md`, `docs/maquinas-de-estado/*.puml` y la documentación/código que sigue en proceso (como `docs/modelo-datos.md`, `database/*.sql`, módulos aún no implementados de `backend/apps/*` y `frontend/src/*`, y `.github/workflows/pruebas.yml`).

---

## 1. Hallazgos Críticos / Bloqueantes

### [C-01] `[RESUELTO]` Colisión en `BloqueoAgenda` (`ExclusionConstraint`) entre Arrendamiento (`RENTA`) y `Función` (`FUNCION`)
* **Ubicación:** `docs/arquitectura.md` (L277–278, L297, L358) y `docs/alcance.md` (§2.2 L45, §2.4 L73).
* **Resolución aplicada:** Se definió que en arrendamientos la `Cotización` crea los bloques `RENTA` y cada `Función` referencia al bloque padre validando contención y no traslape entre funciones hermanas en `AgendaService` (sin duplicar bloques); en eventos directos se crean bloques `FUNCION` / `MANTENIMIENTO` por bloque operativo; las opciones de `PROPUESTA_RETENIDA` deben ser no traslapadas entre sí; `reprogramar_bloque()` bloquea con `select_for_update()` y marca `LIBERADO` el bloque anterior antes de insertar el nuevo; `AgendaService` ejecuta liberación *lazy* de bloques expirados antes de validar disponibilidad; y la migración inicial de `agenda` incluye `BtreeGistExtension()`.

### [C-02] `[RESUELTO]` Inviabilidad técnica de reembolso automático API en Stripe para fichas (OXXO/SPEI) y riesgo en `dual-write`
* **Ubicación:** `docs/alcance.md` (§2.10), `docs/arquitectura.md` (Diagrama 3, Entidades Nucleares, Celery Worker) y `docs/stack-tecnologico.md` (§1.2, §2.4).
* **Resolución aplicada:** Se diferenció reembolso técnico automático vía Stripe API para pagos con tarjeta vs. estado `REEMBOLSO_BANCARIO_PENDIENTE` con alerta al Admin para devolución bancaria externa del 100% en fichas SPEI/efectivo fuera de ventana (incluyendo saldo D-21 tardío); se desacoplaron las llamadas HTTP de Stripe fuera de `select_for_update()` permitiendo reintentos dentro de vigencia; se exigió `now() <= hora_fin` y función no cancelada para reasignar órdenes expiradas; y se aseguró idempotencia/no pérdida de webhooks mediante `stripe_event_id` con estado, `transaction.on_commit()`, `acks_late=True` y enrutamiento por `metadata.modulo`.

### [C-03] `[RESUELTO]` Riesgos operativos en VPS (`2 vCPU / 4 GB RAM`), Redis compartido, Rate Limiting y `/media/`
* **Ubicación:** `docs/arquitectura.md`, `docs/stack-tecnologico.md` y `docs/alcance.md`.
* **Resolución aplicada:** Se especificó polling ligero con `.values_list()` + caché breve `2–3 s` / `ETag`; tuning de Gunicorn (`gthread`, `--workers 3 --threads 4`), `CONN_MAX_AGE=60` y Celery `--concurrency=2`; Redis con `appendonly yes`, `maxmemory-policy noeviction` y bases lógicas separadas (`db 0/1/2`); rate limiting por IP en Nginx solo en rutas anónimas (eximiendo webhooks/health) y `ScopedRateThrottle` por `user.id` en DRF para QR/carrito/taquilla; contrato `{token}` (`QR_HMAC_SECRET`) vs `{folio_corto, funcion_id}` (Base32 $\geq 8$ caracteres) bloqueando solo `Boleto` y con códigos HTTP únicos (`409` / `422` / `400/404`); endpoint `@ensure_csrf_cookie` + revocación inmediata (`is_active`/`session_version`) + `PASSWORD_RESET_TIMEOUT = 1800`; y `client_max_body_size 6m;`, cabeceras `nosniff`/`CSP` en `/media/` y re-codificación Pillow sin EXIF.

### [C-04] `[RESUELTO]` Contradicción aritmética en fecha límite de publicación (`< 15d` vs `3d`) y estados faltantes de `Evento` / `Cotización`
* **Ubicación:** `docs/alcance.md` (§2.2) y `docs/arquitectura.md` (Entidades Nucleares).
* **Resolución aplicada:** Se fijó `fecha_limite_publicacion = min(inicio_primer_bloque_reservado, max(primera_fecha - 15d, fecha_pago + 3d))` garantizando al menos 3 días naturales sin vencer después del evento; se agregaron los estados `OPERACION_SIN_CARTELERA` (para eventos `Privado` y resolución #3 de vencimiento) y `FINALIZADO` en `Evento`; se aclaró que `REPROGRAMADO` se registra sobre la `Función` manteniendo el `Evento` visible; y se listaron los estados oficiales y sub-estado financiero en `Cotización`.

### [C-05] `[RESUELTO]` Fórmulas del cotizador multi-día, esquema D-21 y geometría de `ConfiguradorTarifas`
* **Ubicación:** `docs/alcance.md` (§2.3, §2.5, §3.4, §3.10) y `docs/arquitectura.md` (Entidades Nucleares, Módulos, Pruebas y Patrones).
* **Resolución aplicada:** Se fijó unidad de cobro configurable por ítem (`POR_EVENTO`, `POR_DIA`, `POR_TURNO`, `POR_UNIDAD`) para extras/infraestructura; ensayos y montaje incluidos en precio al rentar más de 1 día o más de 1 función el mismo día (solo reservan agenda); precios netos finales en MXN sin IVA adicional; esquema `50/50` permitido con `>= 21 d` (`100%` obligatorio con `< 21 d`, corte en `D-21 23:59:59`, anticipo redondeado `ROUND_HALF_UP` y `saldo = total - anticipo`); y sub-secciones representadas como bloques rectangulares `(fila_inicio, fila_fin, col_inicio, col_fin)` en graderías + cabinas completas `palco_ids` en `Palcos` (dejando el catálogo físico exacto de las 1,728 butacas para `docs/modelo-datos.md`).

---

## 2. Hallazgos Altos / Importantes (Sincronización entre Documentos y Repo)

### [I-01] Inconsistencia terminológica y de modelos entre `alcance.md`, `arquitectura.md` y `stack-tecnologico.md`
* **Entidades y campos mezclados:** `LocalidadFuncion` vs `DisponibilidadButaca` (`arquitectura.md` L178, L281, L320, L756); `Carrito (Temporal)` + `Venta y Pago` vs `Orden` (L282–283 vs `alcance.md` L169); estados en masculino/femenino (`apartado`/`apartada`, `vendido`/`vendida`); `usado_at` vs español; `@fullcalendar/react` (`stack-tecnologico.md` L107) mezclando orígenes (`FUNCION`, `RENTA`, `MANTENIMIENTO`) con estados (`PROPUESTA_RETENIDA`, `PRE_RESERVADO`) y omitiendo `CONFIRMADO`.
* **Siglas y etiqueta sin definir:** `Solución B` (`arquitectura.md` L100, L351, L536, L874 — nunca se explica qué fue Solución A), `LFPDPPP`, `INAPAM`, `SPEI`, `CFDI`, `CMS`, `POS`, `PWA`, `Anti-IDOR / BOLA`, `RPO / RTO`, `SLA`, `KISS` y `línea de captura`.
* **Límite `<= 10` boletos y candados:** Bloquear solo `LocalidadFuncion` elegidas permite apartar `6 + 6 = 12` en dos pestañas; requiere orden global (`Usuario -> Orden -> LocalidadFuncion`). También debe verificarse antes de reasignar pagos tardíos.
* **Dependencia circular potencial en `cartelera`:** `ConfiguracionSistema`, turnos y extras viven en `cartelera` (`arquitectura.md` L319), pero `ventas` y `cotizaciones` dependen de ellos mientras `cotizaciones` origina eventos en `cartelera`. Conviene mover configuración a un módulo transversal sin imports hacia arriba (`configuracion/`) y vigilar fronteras con `import-linter`.

### [I-02] Reglas operativas subespecificadas
* **Creación de `Funciones` y `LocalidadFuncion`:** No se precisa en qué momento se crean `Funciones` desde una `Cotización` multi-día ni cuándo se insertan (`bulk_create`) las 1,728 filas por función comercial; tampoco cómo representar funciones que cruzan medianoche.
* **Cierres, prórrogas, cancelación y contingencia:** Falta definir si carritos en `APARTADO` pueden iniciar `checkout` tras `-30m` web / `0m` taquilla; qué pasa con boletos vendidos en `CANCELADO_POR_ARRENDATARIO` (`2.9.A`); si reprogramar recalcula `D-21`/`D-15`; qué es "días hábiles" (L–V vs festivos); si `ADMIN` debe aprobar eventos Públicos; cuál es el primer comando para crear el `ADMIN` inicial sin Django Admin; y qué cambia técnicamente al activar modo contingencia + formato de reconciliación en lote.
* **Seguridad y entorno:** `PASSWORD_RESET_TIMEOUT` por defecto de Django es 3 días (fijar p. ej. `1800 s` para "expiración corta"); parametrizar `SESSION_COOKIE_SECURE` / `CSRF_TRUSTED_ORIGINS` para HTTP local y pruebas móviles con `@vitejs/plugin-basic-ssl`; y definir categorías de eventos en cartelera.

### [I-03] Desalineaciones entre los 3 documentos y el estado actual del repositorio
* **`docs/stack-tecnologico.md` vs `frontend/package.json` y `backend/requirements.txt`:**
  * `stack-tecnologico.md` L114 agrupa `vite` y `@vitejs/plugin-react` bajo `^5.4.x`, pero en `package.json` `@vitejs/plugin-react` es `^4.3.4`; también agrupa versiones distintas en `postcss` (`^8.4.49`), `autoprefixer` (`^10.4.20`), `eslint-plugin-react-hooks` (`^5.0.0`), `typescript-eslint` (`^8.15.0`), `@testing-library/jest-dom` (`^6.6.3`), `jsdom` (`^25.0.0`) y omite `@types/react` / `@types/react-dom`.
  * `stack-tecnologico.md` L7 indica que `backend/requirements.txt` tiene versiones fijadas, mientras L136 pospone fijar `==` hasta antes del VPS.
* **`docs/arquitectura.md` vs repo:**
  * Duplica el árbol de directorios 3 veces (L464–579 vs L585–648 y L670–724), cita `STACK_TECNOLOGICO.md` (inexistente), mezcla `.env.example` raíz con `backend/.env.example`, omite `QR_HMAC_SECRET` / `STRIPE_PUBLIC_KEY` de `backend/.env.example`, mezcla `/api/` vs `/api/v1/`, ubica `ContingenciaBoletosPage.tsx` en `features/boletos/` siendo exclusiva de Admin, y no contempla vistas de `Auditoria` y `Ventas Globales` en `features/admin/`.
* **Formato Markdown/LaTeX roto (artefactos de Google Docs):** Escapes `\$`, `1\.`, `\-`, `http\://`, bloques Mermaid/PlantUML/JSON sin identificador de lenguaje en `arquitectura.md`, negritas envolviendo todo `alcance.md` y un `1. ` huérfano al final de `stack-tecnologico.md` (L137).

---

## 3. Análisis de Viabilidad para 4 Semanas / 6 Integrantes (`egm-zoom-out`)

Si el equipo busca proteger la entrega de **4 semanas**, `egm-zoom-out` señala los mayores focos de sobreingeniería candidatos a simplificarse o pasar a Fase 2:
1. **`ConfiguracionSistema` (17 parámetros en UI + *snapshot*):** mover tiempos/umbrales a constantes en `settings.py` y dejar editable solo tarifario de rentas/extras.
2. **Eliminación total de Django Admin + `@fullcalendar/react`:** mantener Django Admin (restringido a `ADMIN`, auditado) para CRUDs administrativos y dejar en React solo las pantallas operativas clave (cotizaciones/agenda en tabla y bloqueos/cortesías sobre el mapa).
3. **Sub-secciones 2D (`<= 36` zonas en `ConfiguradorTarifas`):** lanzar v1 con las **6 secciones oficiales** (o cortes simples por fila).
4. **Excepciones complejas de arrendamiento/boletos:** triple bloqueo `PROPUESTA_RETENIDA` × 3, `VENCIDO_SIN_PUBLICAR` (4 salidas), `PAGO_EXTEMPORANEO_EN_REVISION` (72h), gracia `+5m`, reasignación tras expiración y reembolsos automáticos por fichas Stripe.
5. **Modo contingencia completo (reconciliación en lote + 4 plantillas `reportlab`):** simplificar a exportación CSV de emergencia y HTML imprimible / PDF minimalista.
6. **Duplicación documental + `database/*.sql`:** dejar cifras y reglas solo en `alcance.md`, librerías solo en `stack-tecnologico.md` y eliminar árboles repetidos en `arquitectura.md`.
