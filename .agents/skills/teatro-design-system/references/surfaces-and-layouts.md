# Superficies, Layouts y Arquitectura de Vistas

Guía estructural de las cuatro superficies del ecosistema **"El Foro Monumental"**. Úsala al maquetar o migrar pantallas para mantener fidelidad espacial y evitar plantillas genéricas.

---

## 1. Portal Público (`index.html`, `boletos.html`, `cotizar.html`, `cuenta.html`, `usuario.html`, `configurador.html`, `legal.html`)

### Cabecera y Pie Institucional
- **Navbar fija (`sticky top-0 z-50 h-20`)**: fondo `bg-primary` (`#1E3A8A`), borde inferior `border-b border-white/10`.
  - Izquierda: `img/LOGO.svg` en caja blanca (`w-10 h-10 sm:w-11 sm:h-11 rounded-xl bg-white p-0.5`), texto `TEATRO DE LA CIUDAD` + subtítulo `Coatzacoalcos, Veracruz` en `text-secondary`.
  - Centro-derecha: enlaces horizontales con borde inferior activo `text-highlight border-highlight border-b-2`, plus acceso rápido dinámico según rol (`Panel Admin`, `Taquilla`, `Verificador QR`).
  - Derecha: CTA en cápsula `bg-accent text-white font-bold rounded-full` (*Registrarse*) o chip de sesión del usuario.
- **Contenedor público estándar**: fluido de lado a lado con respiro horizontal `px-4 sm:px-6 md:px-[100px]`.
- **Footer (`bg-primary text-white pt-12 pb-8`)**: 4 columnas institucionales con aforo oficial explícito (`1,728 butacas numeradas en 6 secciones`), horarios de taquilla (`Cierre en línea: 30 min antes · Taquilla física: 0 min antes`), dirección física y enlace a `legal.html`.

### Retículas de Trabajo Públicas
- **Mural Principal (`index.html#mural`)**: altura mínima `calc(100vh - 80px)`, titular `Cinzel` (`text-3xl sm:text-5xl lg:text-6xl font-extrabold`) alineado a la derecha sobre velo limpio (`bg-slate-950/50`) sin blur agresivo, y trío de métricas oficiales (`1,728 Butacas Oficiales`, `6 Secciones de Sala`, `67 Varas en Tramoya`). Barra de filtros `sticky top-20` en blanco sólido debajo.
- **Selección de Boletos (`boletos.html`)**: retícula **`8 + 4`** (`lg:col-span-8` visor SVG del mapa oficial + `lg:col-span-4` carrito `sticky`, cronómetro `10:00 min` / `+5:00 min` y botón Stripe).
- **Cotización de Arrendamiento (`cotizar.html`)**: cabecera hero `bg-primary`, ficha técnica de infraestructura escénica en 4 columnas (sin catering ni estacionamiento), seguida de retícula **`7 + 5`** (formulario multi-día a la izquierda + resumen estimado e información de esquema `50/50 vs 100%` a la derecha).

---

## 2. Consola Operativa de Administración — Opción B (`admin/*.html`)

Diseño **Backstage en Arena Cálida** (`body class="bg-arena-canvas text-base-text"`), con ancho máximo contenido `max-w-[1380px] mx-auto px-4 sm:px-6 lg:px-10`.

### Navegación Superior en 4 Pilares + Sub-barra Arena
Abandona el sidebar vertical negro (`#020617`) y el gris frío (`#F1F5F9`):
1. **Barra superior (`bg-primary h-20`)**:
   - Marca izquierda: `img/LOGO.svg` + `TEATRO DE LA CIUDAD` + subtítulo `CONSOLA OPERATIVA` (`text-secondary`).
   - Centro (`hidden lg:flex gap-6`): **4 pilares cognitivos**:
     - `Hoy` (`admin/index.html`) — con pill dorado/Carbón (`#E58E26` / `#0F172A`) si hay pendientes urgentes.
     - `Programación` (`cartelera.html`, `agenda.html`)
     - `Comercial y Sala` (`cotizaciones.html`, `sala.html`, `ventas.html`) — con pill de cotizaciones en revisión.
     - `Recinto` (`configuracion.html`, `usuarios.html`)
   - Derecha: accesos operativos directos (`Taquilla`, `Puerta QR`, `Portal`) + chip de perfil en `bg-golfo-deep` + botón hamburguesa móvil que despliega `#admin-mobile-drawer` en `bg-golfo-deep`.
2. **Sub-barra contextual (`bg-[#EFECE4] border-b border-arena-border`)**:
   - Sub-pestañas en píldora (`bg-primary text-white` activo, `text-golfo-deep/85` inactivo) correspondientes al pilar abierto.
   - Derecha: telemetría fija `Aforo: 1,728 · Hora MX: HH:MM` en `.tabular-nums`.

### Patrones de Pantalla en Admin
- **Sub-cabecera de página**: banda blanca limpia (`bg-white border-b border-arena-border py-5`) con `h1` en `Manrope` (`font-sans text-xl sm:text-2xl font-extrabold text-primary`), descripción corta y máximo 1–2 acciones primarias a la derecha.
- **Tablero Ejecutivo (`admin/index.html`)**:
  - **Tira tabular de 4 métricas**: una sola tarjeta blanca `rounded-2xl border border-arena-border grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 divide-y sm:divide-y-0 sm:divide-x divide-arena-border` con cifras `text-3xl font-extrabold tabular-nums` y enlace sutil. *(Prohibido clonar 4 tarjetas con cajas de íconos coloridos).*
  - **Pulso de Ocupación en Gran Sala (1,728)**: fila de tarjetas compactas por función comercial mostrando progreso visual (`ocupadas / 1,728 localidades` y `%`).
  - **Malla inferior `7 + 5`**: `Decisiones Prioritarias` (SLA vencido, `VENCIDO_SIN_PUBLICAR`, pagos extemporáneos `72 h`) a la izquierda y `Próximas Funciones` con accesos a `Taquilla` / `Puerta QR` a la derecha.
- **Mesas Split `7 + 5` con Inspector Lateral Fijo (`cotizaciones.html` y `cartelera.html`)**:
  - **Izquierda (`lg:col-span-7`)**: tabla densa dentro de `bg-white rounded-2xl border border-arena-border overflow-hidden`, cabecera cálida `bg-[#EFECE4] text-golfo-deep text-xs uppercase tracking-wider font-extrabold`, filas `divide-y divide-arena-border` con máximo 4 columnas limpias para evitar recorte horizontal a `1280px`.
  - **Derecha (`lg:col-span-5 lg:sticky lg:top-36`)**: inspector fijo en línea que se carga automáticamente con el elemento más urgente y permite aprobar, proponer 3 fechas alternativas, resolver `D-15`, subir póster o dar de alta un evento directo **sin abrir modales encadenados**. En móvil (`< 1024px`), al tocar una fila hace `scrollIntoView` hacia el inspector.
- **Sala (`admin/sala.html`)**: retícula `7 + 5` (o `8 + 4` en mapa amplio) con selectores SVG vectoriales limpios (`Bloqueo Técnico` vs `Cortesía ($0 QR)`) y tarjeta lateral fija con Modo Contingencia (`Exportar CSV 24 h antes`, activar contingencia con motivo obligatorio y reconciliar folios).

---

## 3. Verificador de Puerta QR — "Pase de Puerta del Foro" (`verificador.html`)

Diseñado para operación **móvil con una mano en vestíbulos de poca luz** (`body class="bg-nocturno-bg text-white"`):

1. **Barra superior Nocturna (`bg-primary border-b border-white/15`)**: `img/LOGO.svg`, `CONTROL DE ACCESO QR` en `Cinzel` (`font-display`), nombre de staff + reloj MX inicializado de inmediato al cargar (`#ver-clock`), badge `En Línea` (`bg-emerald-950/80 border-emerald-400/50`) y enlace de salida `Portal`.
2. **Contenedor único centrado (`max-w-2xl mx-auto px-4 py-5 space-y-4`)**, en estricto orden vertical de prioridad:
   1. **Tarjeta de Turno y Telemetría (`bg-nocturno-surface border border-secondary/20 rounded-2xl p-4`)**: selector de función objetivo + contador `Ingresados: X / Y emitidos (1,728 sala)` + barra de progreso en `#38BDF8` (`bg-highlight`).
   2. **Tarjeta-Pase de Veredicto Dominante (`#ver-result-card`)**: siempre visible **arriba** de los botones de captura. Encabezado con ícono SVG inequívoco (`check`, `alert-triangle`, `x`) + código de estado + pill `QR CONSUMIDO` / `NO CONSUMIDO`; cuerpo amplio con localidad asignada (`{Sección} · Fila {F} · Asiento {N}`), folio y titular.
   3. **Entrada Manual + Cámara (`bg-nocturno-surface rounded-2xl p-4`)**: input alto (`py-3`) en `bg-nocturno-bg font-mono` + botón dominante `Validar` en `bg-accent text-base-text font-extrabold rounded-full` (`7.0:1`), botón secundario `Activar Cámara del Dispositivo` debajo y aviso normativo de reingreso mediante sello/brazalete.
   4. **Bloques secundarios inferiores**: `Últimos Escaneos en Puerta` y (solo en entorno prototipo/QA) simulador de los 6 casos al final de la página, **nunca por encima del resultado**.

---

## 4. Taquilla Física (`taquilla.html`)

- Cabecera operativa oscura (`bg-slate-950 text-white sticky top-0`) con selector de función comercial, caja rápida de reimpresión excepcional por orden/folio y reloj MX en vivo (`cierre: 0 min antes del inicio`).
- Espacio de trabajo **`8 + 4`** sobre `bg-base-bg`: plano interactivo sincronizado en tiempo real (`window.addEventListener('storage')`) a la izquierda y carrito presencial + cobro (`Efectivo` o `Tarjeta terminal externa`) a la derecha.

---

## 5. Lista Negra Visual (Nunca introducir en migración)

- **No** usar `bg-slate-950` como barra lateral fija ni `#F1F5F9` como fondo de Consola Admin.
- **No** clonar filas de 4 tarjetas KPI con cajas cuadradas de íconos coloridos.
- **No** marcar selección activa o alertas con bordes gruesos unilaterales (`border-l-4`).
- **No** colocar el simulador QA ni filtros secundarios por encima del card de resultado en Puerta QR.
- **No** bajar de `12px` (`text-[10px]` / `text-[11px]`) en tablas, formularios, badges o navegación operativa.
- **No** reintroducir CMS, catering ni estacionamiento en vistas ni semillas.
