# Plano de 1,730 Butacas, Estados UI y Veredictos QR

Referencia oficial extraída de `js/core/config-store.js`, `js/plano-teatro-svg.js`, `js/components/seat-map.js`, `js/core/state-machines.js` y `js/views/verificador.js`.

---

## 1. Invariante Arquitectónico: 6 Secciones y 1,730 Butacas Oficiales

Nunca cambies estos identificadores, conteos ni colores estructurales en el plano SVG ni en los configuradores:

| ID Sección | Nombre Oficial | Color Hex | Butacas | Precio Base Sugerido (MXN) | Bloques / Filas clave |
| :--- | :--- | :--- | :---: | :---: | :--- |
| `luneta` | **Luneta** | `#DC2626` | `566` | `$650` | Filas `Q` a `A`, más `AA` y `BB` (`IZQUIERDO`, `CENTRAL`, `DERECHO`) |
| `platea` | **Platea** | `#EA580C` | `144` | `$520` | Filas `O` a `A` en laterales (`IZQUIERDO` y `DERECHO`) |
| `mezzanine` | **Mezzanine** | `#1E3A8A` | `291` | `$480` | Filas `X` a `R` (`IZQUIERDO`, `CENTRAL`, `DERECHO`) |
| `primer-piso` | **Primer Piso** | `#15803D` | `287` | `$380` | Filas `G` a `A` (41 asientos por fila) |
| `segundo-piso` | **Segundo Piso** | `#7E22CE` | `386` | `$300` | Filas `K` a `A` |
| `palcos` | **Palcos** | `#0284C7` | `56` | `$580` | 12 cabinas completas: Nivel 1 (`P1`–`P5`, `P8`: 28) y Nivel 2 (`P9`–`P14`: 28) |

- **Suma verificada:** `566 + 144 + 291 + 287 + 386 + 56 = 1,730` localidades exactas.
- **Localidades accesibles (`♿`, 12 en total + 6 acompañantes):**
  - `luneta`: `BB-1`, `BB-2`, `BB-25`, `BB-26`, `A-1`, `A-2`, `A-29`, `A-30`
  - `platea`: `A-1`, `A-2`, `A-5`, `A-6`
  - Deben distinguirse visualmente con contorno exterior azul (`#0284C7`) y punto identificador, además de marcarse explícitamente en leyenda y resumen.

### Reglas de Zoom e Interacción del Plano SVG (`viewBox="0 0 1100 940"`)
- **Umbral LOD semántico (`ZOOM_SEAT_THRESHOLD = 1.7`):** por debajo de `1.7x` se muestran las 6 macro-secciones sólidas con su nombre, aforo y rango tarifario; al llegar a `>= 1.7x` las macro-formas bajan a `fill-opacity="0.16"` y aparecen las **1,730 butacas individuales**. Escala máxima `4.5x`.
- **4 modos de operación soportados por el componente del plano:** `public`, `taquilla`, `admin-sala` y `configurator`.
- **Configurador tarifario (`configurador.html`):** configuración de secciones del evento (conservación 6 secciones, sección única, agrupación o subdivisión de hasta ≤ 6 por sección oficial) y fases de venta consecutivas, con piso `>= $100.00 MXN`, cobertura `100%` sin butacas huérfanas y nombre único por evento. Al publicar el evento, la configuración se congela.

---

## 2. Estados Visuales de Cada Butaca (Color + Forma + Símbolo)

Para cumplir accesibilidad y no depender solo del color, cada estado combina relleno, trazo, cursor y marca:

| Estado de Butaca | Relleno | Trazo / Estilo | Texto / Marca SVG | Comportamiento según modo |
| :--- | :--- | :--- | :--- | :--- |
| **DISPONIBLE** | `#FFFFFF` | Color de sección del evento (`1.5px`) o `#0284C7` si es accesible | Número en `#0F172A` | Seleccionable |
| **SELECCIONADA** | `#E58E26` | `#0F172A` (`2px`) | Número `#FFFFFF` + marca `✓` (`#0F172A`) | Deseleccionable |
| **APARTADA (otro carrito)** | `#FEF3C7` | `#B45309` (`stroke-dasharray="2 1.5"`) | Número `#92400E` + marca `⏳` | Bloqueada (`not-allowed`) |
| **VENDIDA** | `#CBD5E1` | `#94A3B8` | Línea diagonal `#64748B` (`seat-cross`) | Bloqueada (`not-allowed`) |
| **BLOQUEO_TECNICO** | `#1E293B` | `#475569` | Número `#94A3B8` + marca `✕` (`#CBD5E1`) | Editable solo en `admin-sala` |
| **CORTESIA** (`admin-sala`) | `#EDE9FE` | `#6D28D9` | Número `#4C1D95` + marca `★` (`#6D28D9`) | En `public`/`taquilla` se visualiza igual que `VENDIDA` |
| **Sección Deshabilitada** | Opacidad `0.25` (bloque) / `0.22` (butaca en `#E2E8F0`) | `#94A3B8` | Etiqueta oscura `#0F172A` (`SECCIÓN NO HABILITADA EN ESTE EVENTO`) | Bloqueada |
| **Huérfana (`configurator`)** | `#FEF2F2` | `#EF4444` (`1.8px`) | Número `#0F172A` | Impide guardar/publicar hasta cubrir 100% |

---

## 3. Semáforo de Badges Operativos (Consola Admin)

Todas las píldoras usan `rounded-full text-xs font-bold px-2.5 py-0.5` sobre fondos suaves de alto contraste:

### Cotizaciones (`ME-01`) y SLA
- **SLA Atrasada (`ATRASADA`):** `bg-red-100 text-red-900`
- **SLA Por Vencer (`POR_VENCER`):** `bg-amber-100 text-amber-950`
- **SLA Atendida (`ATENDIDA`):** `bg-emerald-100 text-emerald-900`
- **SLA En Tiempo:** `bg-sky-100 text-sky-900`
- **Estado `ME-01` por defecto:** `bg-primary/10 text-primary`
- **Banner agenda disponible:** `bg-emerald-50 border-emerald-200 text-emerald-950`
- **Banner empalme (`409 Conflict`):** `bg-red-50 border-red-200 text-red-950`

### Cartelera y Eventos (`ME-02`)
- `PUBLICADO`: `bg-emerald-100 text-emerald-900`
- `VENCIDO_SIN_PUBLICAR`: `bg-red-100 text-red-950`
- `CANCELADO_POR_*`: `bg-slate-200 text-slate-800`
- Pendientes / en revisión: `bg-amber-100 text-amber-950`

### Calendario Maestro (`admin/agenda.html`)
- `MANTENIMIENTO`: `bg-red-700 text-white`
- `MONTAJE`: `bg-slate-700 text-white`
- `CONFIRMADO`: `bg-primary text-white`
- `PRE_RESERVADO`: `bg-accent text-slate-950`
- `PROPUESTA_RETENIDA` / otro: `bg-sky-800 text-white`

---

## 4. Los 6 Veredictos Deterministas del Escáner QR (`verificador.html`)

La máquina `ME-04` evalúa en orden estricto 7 reglas que producen los siguientes estados visuales de `#ver-result-card` (`rounded-2xl border-2`):

| Código | Clases de Tarjeta | Ícono SVG | Pill Consumo | Regla / Cuándo ocurre |
| :--- | :--- | :--- | :--- | :--- |
| **`VALIDO`** | `bg-emerald-900 text-white border-emerald-400` | Check (`✓`) | `QR CONSUMIDO` | Boleto `EMITIDO`, coincide turno (si se filtró) y hora actual dentro de `[T_inicio - 2h, T_fin]` |
| **`YA_UTILIZADO`** | `bg-amber-300 text-slate-950 border-amber-500` | Alerta triángulo (`!`) | `NO CONSUMIDO` | Estado `USADO` o `USADO_CONTINGENCIA`; muestra hora y verificador previos |
| **`OTRA_FUNCION`** | `bg-purple-900 text-white border-purple-400` | Cruz (`×`) | `NO CONSUMIDO` | Token válido, pero pertenece a otra fecha/función distinta al turno seleccionado |
| **`DEMASIADO_PRONTO`** | `bg-sky-900 text-white border-sky-400` | Alerta triángulo (`!`) | `NO CONSUMIDO` | Hora actual anterior a `T_inicio - 2h`; indica la hora de apertura |
| **`FUNCION_CONCLUIDA`** | `bg-slate-800 text-white border-slate-500` | Cruz (`×`) | `NO CONSUMIDO` | Hora actual posterior a `hora_fin` de la función |
| **`INVALIDO` / `INVALIDADO`** | `bg-red-900 text-white border-red-400` | Cruz (`×`) | `NO CONSUMIDO` | Folio/firma inexistente, boleto invalidado o evento cancelado |
