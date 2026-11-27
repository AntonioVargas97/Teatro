---
name: Teatro de la Ciudad de Coatzacoalcos
description: Sistema visual cívico, cálido y operativo para la cartelera, venta directa de 1,730 butacas en 6 secciones, consola administrativa en Arena Cálida y control de acceso QR en Azul Nocturno del Golfo.
colors:
  azul-golfo: "#1E3A8A"
  golfo-profundo: "#162C6B"
  arena-arquitectonica: "#D9CBB8"
  arena-calida: "#F6F4EF"
  arena-borde: "#E4DED3"
  dorado-atardecer: "#E58E26"
  ambar-accesible: "#B45309"
  celeste-brisa: "#38BDF8"
  blanco-nube: "#F8F9FA"
  blanco-puro: "#FFFFFF"
  carbon-pizarra: "#0F172A"
  pizarra-oscuro: "#020617"
  nocturno-golfo: "#0B1736"
  nocturno-superficie: "#13244E"
typography:
  display:
    fontFamily: "Cinzel, Georgia, serif"
    fontSize: "3.75rem"
    fontWeight: 800
    lineHeight: 1.15
    letterSpacing: "-0.025em"
  headline:
    fontFamily: "Cinzel, Georgia, serif"
    fontSize: "1.875rem"
    fontWeight: 800
    lineHeight: 1.2
    letterSpacing: "-0.025em"
  title:
    fontFamily: "Manrope, system-ui, sans-serif"
    fontSize: "1.125rem"
    fontWeight: 700
    lineHeight: 1.375
    letterSpacing: "0em"
  body:
    fontFamily: "Manrope, system-ui, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.625
    letterSpacing: "0em"
  label:
    fontFamily: "Manrope, system-ui, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 700
    lineHeight: 1.33
    letterSpacing: "0.05em"
rounded:
  sm: "6px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  full: "9999px"
spacing:
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
  xl: "40px"
  container-x: "100px"
components:
  button-primary:
    backgroundColor: "{colors.dorado-atardecer}"
    textColor: "{colors.blanco-puro}"
    rounded: "{rounded.full}"
    padding: "10px 20px"
  button-operate-accent:
    backgroundColor: "{colors.dorado-atardecer}"
    textColor: "{colors.carbon-pizarra}"
    rounded: "{rounded.full}"
    padding: "10px 18px"
  button-secondary:
    backgroundColor: "{colors.blanco-puro}"
    textColor: "{colors.azul-golfo}"
    rounded: "{rounded.full}"
    padding: "10px 20px"
  card-surface:
    backgroundColor: "{colors.blanco-puro}"
    textColor: "{colors.carbon-pizarra}"
    rounded: "{rounded.md}"
    padding: "20px"
  input-field:
    backgroundColor: "{colors.blanco-nube}"
    textColor: "{colors.carbon-pizarra}"
    rounded: "{rounded.md}"
    padding: "12px 16px"
  badge-category:
    backgroundColor: "{colors.azul-golfo}"
    textColor: "{colors.blanco-puro}"
    rounded: "{rounded.sm}"
    padding: "4px 10px"
---

# Design System: Teatro de la Ciudad de Coatzacoalcos

## Overview

**Creative North Star: "El Foro Monumental"**

La identidad visual del ecosistema traduce la presencia cívica y arquitectónica del recinto diseñado por el Arq. Abraham Zabludovsky a tres caras especializadas con un ADN compartido: el **Portal Público** (`Persuade / Experience`), la **Consola Operativa de Administración** (`Operate — Backstage en Arena Cálida`) y el **Puesto de Puerta QR** (`Operate — Azul Nocturno del Golfo`).

En el portal público, `Cinzel` domina los hitos escénicos y `Manrope` sostiene la lectura operativa de cartelera, precios y compra sobre el plano oficial de **1,730 butacas en 6 secciones** (`+12` accesibles `♿`). En las superficies operativas internas (`admin/*.html` y `verificador.html`), la jerarquía se invierte hacia la velocidad tabular (`tabular-nums`), contraste WCAG 2.1 AA/AAA estricto y ausencia de ruido visual, manteniendo inconfundiblemente la misma familia cromática del Teatro.

**Key Characteristics:**
- Ecosistema cohesivo en torno a `Azul Golfo` (`#1E3A8A`) y `Arena Arquitectónica` (`#D9CBB8`) para público, backstage y puerta QR.
- Superficies luminosas en portal (`#F8F9FA`) y lienzo cálido arquitectónico en administración (`#F6F4EF`), evitando fondos genéricos gris/negro.
- Consola administrativa con **Cabecera Institucional Azul Golfo (4 pilares)**, sub-barra Arena contextual y mesas de trabajo **Split `7+5`** con inspector lateral fijo.
- Verificador QR nocturno en **`Azul Nocturno del Golfo` (`#0B1736`)** con tarjeta-pase dominante superior, telemetría en vivo (`Ingresados / Emitidos`) y simulador de pruebas en franja inferior secundaria.

## Colors

Una paleta institucional sobria que combina azul profundo del Golfo, calidez arenosa inspirada en la arquitectura del recinto y un acento ámbar reservado para la acción y los estados clave.

### Primary
- **Azul Golfo** (`azul-golfo`, `#1E3A8A`): Color estructural principal en barras superiores (pública, admin y verificador), enlaces primarios, etiquetas y cabeceras de sección.
- **Golfo Profundo** (`golfo-profundo`, `#162C6B`): Variante estructural oscura para cabeceras tabulares en Arena, drawers móviles administrativos y acciones secundarias sólidas.
- **Dorado Atardecer** (`dorado-atardecer`, `#E58E26`): Acento principal de conversión ("Registrarse", "Ver más", "Pagar con Tarjeta") y selección de butaca. En controles operativos (`admin` y `verificador`) combina con **Carbón Pizarra** (`#0F172A`, contraste `7.0:1`).

### Secondary
- **Arena Arquitectónica** (`arena-arquitectonica`, `#D9CBB8`): Subtítulos institucionales en cabeceras oscuras ("Coatzacoalcos, Veracruz", "Consola Operativa"), tarjetas sin póster y filetes traslúcidos en modo nocturno.
- **Arena Cálida** (`arena-calida`, `#F6F4EF`) y **Arena Borde** (`arena-borde`, `#E4DED3`): Lienzo general de la Consola de Administración y bordes de paneles/tablas, manteniendo calidez arquitectónica (`16.24:1` con Carbón Pizarra).

### Tertiary
- **Celeste Brisa** (`celeste-brisa`, `#38BDF8`): Enlaces activos sobre barra Azul Golfo, barra de telemetría de ingreso en puerta (`8.24:1` sobre Nocturno) y anillos de foco (`focus:ring`).

### Neutral y Nocturno
- **Blanco Nube** (`blanco-nube`, `#F8F9FA`): Lienzo general público, campos de formulario y visor base del mapa de sala.
- **Blanco Puro** (`blanco-puro`, `#FFFFFF`): Tarjetas de cartelera, tablas, inspectores laterales y modales.
- **Carbón Pizarra** (`carbon-pizarra`, `#0F172A`): Texto principal de lectura sobre fondos claros/Arena y texto sobre botones dorados en consola operativa (`7.0:1`).
- **Pizarra Oscuro** (`pizarra-oscuro`, `#020617`): Menús desplegables móviles en portal público y controles HUD flotantes sobre fotografía.
- **Azul Nocturno del Golfo** (`nocturno-golfo`, `#0B1736`) y **Superficie Nocturna** (`nocturno-superficie`, `#13244E`): Fondo (`17.65:1` con blanco) y tarjetas (`15.11:1`) exclusivas de `verificador.html` para vestibulos con luz tenue sin perder la raíz azul del Teatro.
- **Ámbar Accesible** (`ambar-accesible`, `#B45309`): Texto de acento sobre Blanco Puro (`5.02:1`) o Arena Cálida (`4.57:1`).

### Named Rules
**The Contrast-Aware Amber Rule.** Usa `Dorado Atardecer` con texto blanco en botones CTA públicos (`Persuade`) y fondos oscuros; usa `Dorado Atardecer` con texto `Carbón Pizarra` (`7.0:1`) en controles operativos de Admin y Verificador; y usa `Ámbar Accesible` cuando el texto de acento vaya sobre `Blanco Puro`, `Blanco Nube` o `Arena Cálida`.

**The Solid Surface Priority Rule.** Los bloques estructurales y tarjetas se apoyan en colores sólidos y bordes limpios. Evita gradientes pesados o desenfoques invasivos (`blur-3xl`) que compitan con fotografías, tablas o el mapa de sala.

## Typography

**Display Font:** `Cinzel`, `Georgia, serif` (pesos `600`, `700`, `800`, `900`)
**Body Font:** `Manrope`, `system-ui, sans-serif` (pesos `400`, `500`, `600`, `700`, `800`)

**Character:** `Cinzel` aporta solemnidad cívica a títulos de obra y encabezados de portada, mientras `Manrope` (apoyado con `tabular-nums` en consola y taquilla) asegura escaneo veloz en horarios, aforos (`1,730`), métricas SLA e importes en MXN.

### Hierarchy
- **Display** (`800`, `3rem`–`3.75rem`, `line-height: 1.15`): Titular principal del mural en `index.html`.
- **Headline** (`800`–`900`, `1.5rem`–`3rem`, `line-height: 1.2`): Títulos `h1`/`h2` en vistas públicas y nombre de espectáculo activo.
- **Title** (`700`–`800`, `1rem`–`1.5rem`, `line-height: 1.3`): Cabeceras operativas en Admin (`Manrope`), títulos de tarjetas e inspector lateral.
- **Body** (`400`–`500`, `0.875rem`–`1rem`, `line-height: 1.625`): Sinopsis, descripciones, preguntas frecuentes (`<= 65ch` en textos legales).
- **Label** (`700`, `0.75rem`, `letter-spacing: 0.05em`): Etiquetas de formulario, insignias, cabeceras de tabla y badges de estado (`>= 12px` en controles funcionales).

### Named Rules
**The Bilingual Hierarchy Rule.** En superficies públicas, `Cinzel` encabeza títulos de obra y secciones `h1`/`h2`; en la consola `Operate` (`admin/*.html` y `verificador.html`), `Manrope` gobierna toda la interfaz tabular y `Cinzel` queda acotada al nombre de eventos o cabecera de puerta. Nunca la uses en tablas, inputs ni botones.

## Layout

- **Portal Público y Operaciones Presenciales:** Contenedor fluido (`px-4 sm:px-6 md:px-[100px]`), navbar fija superior de `80px` en Azul Golfo. `boletos.html` y `taquilla.html` usan retícula **`8 + 4`** y `cotizar.html` usa **`7 + 5`**.
- **Consola Administrativa (`/admin/`):** Abandona el sidebar oscuro lateral para adoptar la **Cabecera Superior Azul Golfo (`80px`) agrupada en 4 pilares** (*Hoy*, *Programación*, *Comercial y Sala*, *Recinto*) + **Sub-barra contextual en Arena** (`#EFECE4`) sobre un lienzo cálido `#F6F4EF` con ancho máximo `1380px`.
  - *Resumen Operativo (`admin/index.html`):* Tira tabular unificada de 4 cifras (con divisores verticales limpios, sin tarjetas clonadas con iconos), pulso de ocupación de sala (`X / 1,730`) y malla `7 + 5` de decisiones prioritarias y próximas funciones.
  - *Cotizaciones (`admin/cotizaciones.html`) y Eventos (`admin/cartelera.html`):* Mesas de trabajo **Split `7 + 5`** con bandeja tabular a la izquierda e **Inspector Lateral Fijo (`sticky`)** a la derecha para aprobar, proponer fechas alternativas, resolver `D-15`, publicar o reprogramar sin modales superpuestos.
- **Verificador Puerta QR (`verificador.html`):** Columna centrada (`max-w-2xl`) en Azul Nocturno `#0B1736` diseñada para operación con una mano: barra de turno y telemetría arriba (`Ingresados / Emitidos`), **Tarjeta-Pase de Veredicto dominante sobre el lector** (`#ver-result-card`), formulario manual + cámara en zona media y bloque inferior separado para bitácora y simulador de QA (`§2.8`).

## Elevation & Depth

El sistema trabaja con **elevación declarada una sola vez**: en consola administrativa e inspectores, los paneles descansan planos sobre el lienzo Arena (`bg-white border border-arena-border`, sin apilar sombra amplia sobre borde); la sombra `md`/`xl` se reserva a barras sticky, tarjetas públicas en cartelera interactiva, menús desplegables y modales activos.

### Shadow Vocabulary
- **Reposo suave** (`0 1px 2px rgba(15, 23, 42, 0.05)`): Mapa de sala y FAQ públicas.
- **Tarjeta / Barra activa** (`0 4px 6px -1px rgba(15, 23, 42, 0.1), 0 2px 4px -2px rgba(15, 23, 42, 0.1)`): Tarjetas públicas de cartelera y barra de filtros sticky.
- **Elevación interactiva** (`0 20px 25px -5px rgba(15, 23, 42, 0.1), 0 8px 10px -6px rgba(15, 23, 42, 0.1)`): Hover de tarjetas de cartelera, desplegables y modales Stripe / QR.

### Named Rules
**The Quiet Rest Rule.** Las superficies descansan con contraste tonal (`Blanco Puro` sobre `Arena Cálida` o `Blanco Nube`) y borde `1px` limpio, reservando sombras pronunciadas exclusivamente a capas flotantes o interacción.

## Shapes

Contenedores operativos contenidos (`12px`–`16px`: `rounded-xl` / `rounded-2xl` en Admin y Verificador; `24px` solo en tarjetas/paneles amplios del portal público), campos en `12px` y botones de acción principales en píldora completa (`9999px`). En tarjetas y listas activas no se usan barras gruesas unilaterales (`border-l-4`): los estados seleccionados usan tinte completo suave (`bg-primary/[0.06] ring-1 ring-inset ring-primary/30`).

## Components

- **Buttons:** Cápsula `9999px`. Público primario: `bg-accent text-white`; Operativo Admin/Verificador: `bg-primary text-white` (`10.36:1`) o `bg-accent text-base-text` (`7.0:1`).
- **Tables (Consola Admin):** Cabecera cálida `bg-[#EFECE4] text-golfo-deep` con divisores `divide-arena-border`, cifras con `.tabular-nums`, sin cabeceras negras sólidas.
- **Signature Component — Mapa Interactivo de Butacas (`img/plano-teatro.svg`):** **6 secciones oficiales** (`Luneta` `#DC2626` · 566, `Platea` `#EA580C` · 144, `Mezzanine` `#1E3A8A` · 291, `Primer Piso` `#15803D` · 287, `Segundo Piso` `#7E22CE` · 386, `Palcos` `#0284C7` · 56) sumando **1,730 localidades** (+ **12 accesibles `♿`**) con zoom semántico LOD (`>= 1.7x`) y 4 modos (`public`, `taquilla`, `admin-sala`, `configurator`).
- **Signature Component — Tarjeta-Pase Verificador QR (`verificador.html`):** Bandeja superior segmentada con ícono SVG inequívoco, banda de estado (`VALIDO`, `YA_UTILIZADO`, `OTRA_FUNCION`, `DEMASIADO_PRONTO`, `FUNCION_CONCLUIDA`, `INVALIDO`), lectura ampliada de Sección/Fila/Asiento y telemetría de ingreso.

## Do's and Don'ts

### Do:
- **Do** usar la familia `#1E3A8A` + `#F6F4EF` en Admin y `#0B1736` + `#13244E` en Verificador para sostener la pertenencia al ecosistema sin caer en grises o negros genéricos.
- **Do** mantener `>= 12px` (`text-xs`) en toda etiqueta funcional, tabla o chip operativo y `tabular-nums` en cifras.
- **Do** usar íconos SVG consistentes en controles y veredictos (reservando `♿` solo como marcador físico de localidad accesible).

### Don't:
- **Don't** introducir gradientes decorativos, `blur-3xl`, barras laterales unilaterales (`border-l-4`) ni tarjetas clonadas con cajas de íconos en paneles administrativos.
- **Don't** colocar el simulador de pruebas por encima del bloque de resultado en `verificador.html`.
- **Don't** alterar las **6 secciones oficiales** ni el total de **1,730 butacas** en el plano oficial ni mezclar estilos de boleteras externas.
