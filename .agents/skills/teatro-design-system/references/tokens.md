# Tokens de Diseño, Tipografía y Contraste

Fuente canónica extraída de `DESIGN.md`, `.impeccable/design.json` y `js/core/config-store.js`. Para copiar el código directamente al nuevo repositorio, utiliza `assets/tokens.css` y `assets/tailwind.theme.cjs`.

---

## 1. Paleta Oficial ("El Foro Monumental")

| Token Semántico | Variable CSS | Nombre Oficial | Hex | Rol y uso obligatorio |
| :--- | :--- | :--- | :--- | :--- |
| `primary` | `--tc-azul-golfo` | Azul Golfo | `#1E3A8A` | Navbar principal (pública, Admin y Verificador), links primarios, títulos operativos y fila/botón activo |
| `golfo-deep` | `--tc-golfo-deep` | Golfo Profundo | `#162C6B` | Cabeceras tabulares sobre Arena (`text-golfo-deep`), drawers móviles de Admin y acciones secundarias sólidas |
| `secondary` | `--tc-arena-arq` | Arena Arquitectónica | `#D9CBB8` | Subtítulos institucionales sobre fondos oscuros ("Coatzacoalcos, Veracruz", "Consola Operativa"), placeholders sin póster y filetes traslúcidos |
| `arena-canvas` | `--tc-arena-calida` | Arena Cálida | `#F6F4EF` | Lienzo general de la Consola de Administración (`admin/*`), evitando el gris frío `#F1F5F9` |
| — | `--tc-arena-subbar` | Arena Sub-barra | `#EFECE4` | Sub-barra contextual de navegación y cabeceras `<thead>` en tablas administrativas |
| `arena-border` | `--tc-arena-borde` | Arena Borde | `#E4DED3` | Bordes limpios (`1px`) y divisores (`divide-arena-border`) en paneles y tablas de Admin |
| `accent` | `--tc-dorado` | Dorado Atardecer | `#E58E26` | Botones primarios de conversión (`Registrarse`, `Confirmar`, `Validar`, `+ Evento Directo`) y butaca seleccionada |
| `accent-text` | `--tc-ambar-accesible` | Ámbar Accesible | `#B45309` | **Único ámbar válido como texto** sobre `#FFFFFF`, `#F8F9FA` o `#F6F4EF` (`5.02:1` / `4.57:1`) |
| `highlight` | `--tc-celeste` | Celeste Brisa | `#38BDF8` | Indicador de ruta activa sobre barras Azul Golfo, progreso de telemetría QR (`8.24:1` sobre Nocturno) y foco (`focus:ring`) |
| `base-bg` | `--tc-blanco-nube` | Blanco Nube | `#F8F9FA` | Fondo base del Portal Público, campos de entrada (`cotizar`, `cuenta`) y visor de mapa |
| — | `--tc-blanco-puro` | Blanco Puro | `#FFFFFF` | Tarjetas públicas, tablas Admin, inspectores laterales y modales |
| `base-text` | `--tc-carbon` | Carbón Pizarra | `#0F172A` | Texto principal sobre fondos claros/Arena (`16.24:1` sobre Arena) y tinta de botones dorados en Admin/Verificador (`7.0:1`) |
| — | `--tc-pizarra-oscuro` | Pizarra Oscuro | `#020617` | Únicamente menú móvil público (`mobile-nav-menu`), barra de Taquilla (`taquilla.html`) y HUD sobre fotografía; **prohibido** como fondo general o sidebar de Admin |
| `nocturno-bg` | `--tc-nocturno-bg` | Azul Nocturno del Golfo | `#0B1736` | Lienzo exclusivo de `verificador.html` para puertas con iluminación tenue (`17.65:1` con blanco) |
| `nocturno-surface` | `--tc-nocturno-surface` | Superficie Nocturna | `#13244E` | Tarjetas de telemetría, lector manual y bitácora sobre `#0B1736` (`15.11:1` con blanco) |

---

## 2. Reglas de Contraste WCAG 2.1 Verificadas

El uso incorrecto de tonos dorados y arena rompe legibilidad rápidamente. Aplica siempre estas combinaciones:

- **The Contrast-Aware Amber Rule:**
  - *Portal Público (`Persuade`)*: `#E58E26` admite texto `#FFFFFF` en botones pill destacados de conversión.
  - *Consola Admin y Puerta QR (`Operate`)*: los controles con fondo `#E58E26` **deben usar tinta `#0F172A` (`Carbón Pizarra`, contraste `7.0:1` AAA)** y peso `font-extrabold`.
  - *Texto sobre fondo claro/Arena*: usa `text-accent-text` (`#B45309`, `5.02:1` sobre blanco y `4.57:1` sobre `#F6F4EF`), nunca `#E58E26`.
- **Sobre `Azul Golfo` (`#1E3A8A`)**: texto principal `#FFFFFF` (`10.36:1`), enlace activo `text-highlight` (`#38BDF8`) o etiquetas suaves `text-sky-200` / `text-amber-200` / `text-secondary`.
- **Sobre `Nocturno` (`#0B1736` / `#13244E`)**: texto `#FFFFFF` (`17.65:1` / `15.11:1`), telemetría `text-highlight` (`8.24:1`), notas secundarias `text-slate-200` / `text-slate-300` / `text-secondary`.

---

## 3. Tipografía y Regla Bilingüe (`Cinzel` + `Manrope`)

- **Display Font (`font-display`):** `'Cinzel', Georgia, serif` — pesos `600`, `700`, `800`, `900`.
- **Body/UI Font (`font-sans`):** `'Manrope', system-ui, sans-serif` — pesos `400`, `500`, `600`, `700`, `800`.

### The Bilingual Hierarchy Rule
- **`Cinzel` comunica solemnidad escénica:** úsala en el titular del mural (`3rem`–`3.75rem`, `leading-[1.15]`), encabezados `h1`/`h2` del portal público (`1.5rem`–`3rem`, `leading-tight`), nombre del evento en `boletos.html` / inspector de Admin, y título `CONTROL DE ACCESO QR` del verificador.
- **`Manrope` gobierna toda la operación:** úsala en cabeceras `h1` de la consola administrativa (`text-xl sm:text-2xl font-extrabold`), etiquetas (`>= 12px`, `tracking-wider`), tablas, inputs, modales y botones.
- **Cifras tabulares (`.tabular-nums`):** obligatoria en montos MXN, horarios, contadores `1,728`, fechas de tabla y relojes en tiempo real para evitar saltos visuales al actualizar.

---

## 4. Superficies, Elevación y Formas

- **The Solid Surface Priority Rule:** trabaja con colores sólidos y bordes limpios (`1px`). Evita gradientes decorativos, `backdrop-blur-3xl` sobre tablas o vidrio translúcido sobre listados operativos.
- **The Quiet Rest Rule (Elevación declarada una sola vez):**
  - En **Admin**: los paneles reposan planos sobre `#F6F4EF` usando `bg-white border border-arena-border` (sin `shadow-lg`/`shadow-xl` encima de bordes, reservando sombra únicamente al nav `sticky` o modales).
  - En **Portal Público**: cartas en `#FFFFFF` con `border border-gray-200` + `shadow-sm`/`shadow-md` en reposo y `shadow-xl` en hover de cartelera interactiva.
- **Radios de borde:**
  - Portal público tarjetas amplias: `24px` (`rounded-3xl`) o `16px` (`rounded-2xl`).
  - Paneles operativos Admin y tarjetas Nocturnas: `16px` (`rounded-2xl`).
  - Inputs, sub-bloques internos y alertas: `12px` (`rounded-xl`).
  - Botones de acción y chips de estado: cápsula completa `9999px` (`rounded-full`).
- **Estados seleccionados en filas o tarjetas:** prohibidas las barras laterales gruesas (`border-l-4`). Resalta la selección con tinte completo suave y anillo interior: `bg-primary/[0.06] ring-1 ring-inset ring-primary/30`.
