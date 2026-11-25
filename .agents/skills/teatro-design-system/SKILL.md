---
name: teatro-design-system
description: Sistema de diseño y guía de implementación frontend para "El Foro Monumental" (Teatro de la Ciudad de Coatzacoalcos). Úsala obligatoriamente siempre que vayas a crear, migrar, refactorizar, diseñar o revisar vistas, componentes, dashboards, taquilla, formularios de cotización, mapas de butacas o validadores QR del proyecto Teatro de la Ciudad — incluso cuando el usuario pida simplemente "implementar la pantalla en React/Next/Vue", "hacer el panel admin", "armar el flujo de boletos" o "migrar una vista del prototipo" sin mencionar explícitamente la palabra diseño. Preserva la identidad institucional (Azul Golfo, Arena Cálida, Dorado Atardecer, Azul Nocturno del Golfo), las 3 superficies diferenciadas, la jerarquía Cinzel + Manrope y la invariante arquitectónica de 1,728 butacas en 6 secciones.
---

# Sistema Visual "El Foro Monumental" — Teatro de la Ciudad de Coatzacoalcos

Esta skill garantiza que la implementación productiva del frontend (cualquier framework: React, Next.js, Vue, Astro, Tailwind CSS o HTML estático) conserve exactamente la identidad arquitectónica, jerarquía, accesibilidad y reglas de dominio definidas en el prototipo oficial (`DESIGN.md`, `.impeccable/design.json` y `PRODUCT.md`).

## Principio rector: Un ecosistema con tres registros especializados

El Teatro de la Ciudad traduce la presencia cívica del recinto diseñado por el Arq. Abraham Zabludovsky a **tres caras de una misma familia cromática**, evitando que el backstage parezca una plantilla genérica gris/negra y evitando que el verificador encandile en un vestíbulo oscuro:

| Superficie | Propósito | Fondo dominante | Tipografía rectora |
| :--- | :--- | :--- | :--- |
| **1. Portal Público y Cotizador** | Descubrir cartelera, elegir butacas y cotizar renta | `Blanco Nube` (`#F8F9FA`) + cabecera `Azul Golfo` (`#1E3A8A`) | `Cinzel` (títulos de obra y `h1`/`h2`) + `Manrope` (cuerpo y precios) |
| **2. Consola Operativa Admin** | Gestionar cotizaciones `ME-01`, cartelera `ME-02`, agenda, sala y ventas | `Arena Cálida` (`#F6F4EF`) + navbar superior `Azul Golfo` en **4 pilares** + sub-barra `#EFECE4` | `Manrope` tabular (`.tabular-nums`) en tablas, cifras y controles; `Cinzel` solo en nombres de espectáculo |
| **3. Puerta QR (`verificador.html`)** | Validación rápida en acceso con una mano y baja luz ambiental | `Azul Nocturno del Golfo` (`#0B1736`) + tarjetas `#13244E` | `Manrope` legible con lectura ampliada de localidad y `Cinzel` solo en título de puerta |

*(La vista de **Taquilla Física** mantiene la barra operativa oscura de caja `bg-slate-950` con el visor compartido `8 + 4` sobre `#F8F9FA` para distinguir claramente al cajero en ventanilla).*

---

## Carga progresiva: qué referencia leer según la tarea

No cargues todo innecesariamente; lee el archivo específico que corresponda a tu tarea actual:

1. **Al configurar el proyecto nuevo, Tailwind CSS o variables globales de tema:**
   - Lee `references/tokens.md` para colores, rampas, tipografía, radios, sombras y reglas de contraste.
   - Copia `assets/tokens.css` y `assets/tailwind.theme.cjs` al repositorio productivo (ajustando el prefijo/imports de tu bundler).
2. **Al crear o migrar páginas, layouts, barras de navegación, formularios o tablas:**
   - Lee `references/surfaces-and-layouts.md` para respetar retículas (`8 + 4`, `7 + 5`, navbar Admin Opción B en 4 pilares, inspector lateral `sticky`, orden vertical del Verificador QR) y evitar antipatrones.
3. **Al implementar el plano de sala, configurador tarifario, chips de estado o escáner QR:**
   - Lee `references/seatmap-and-states.md` para respetar las **6 secciones oficiales**, las **1,728 butacas (+12 accesibles `♿`)**, colores de estado SVG, badges de máquinas de estado (`ME-01` a `ME-04`) y los 6 veredictos QR.

Si además existen `DESIGN.md`, `PRODUCT.md` e `.impeccable/design.json` en la raíz del repositorio destino, consúltalos para confirmar cualquier ajuste local reciente del proyecto.

---

## Invariantes irrenunciables (por qué importan)

- **1,728 butacas en 6 secciones oficiales (+12 accesibles `♿`):** No son 1,724 ni 1,730 ni 7 zonas. Las únicas secciones válidas son `Luneta` (564), `Platea` (144), `Mezzanine` (291), `Primer Piso` (287), `Segundo Piso` (386) y `Palcos` (56). Divergir rompe la coherencia con el plano arquitectónico del recinto y los boletos emitidos.
- **Sin sidebar negro genérico en Administración:** El panel Admin abandonó el menú lateral oscuro en favor de una barra superior institucional en `Azul Golfo` (`#1E3A8A`) agrupada en 4 pilares (*Hoy*, *Programación*, *Comercial y Sala*, *Recinto*) sobre lienzo `Arena Cálida` (`#F6F4EF`). Volver a `#020617` + `#F1F5F9` desconecta el panel de la marca del Teatro.
- **Sin CMS ni servicios excluidos:** No agregues editores visuales CMS de contenido estático/portada en Admin ni menciones estacionamiento o catering en formularios o fichas técnicas.
- **Jerarquía bilingüe (`Cinzel` vs `Manrope`):** `Cinzel` da solemnidad escénica a carteles y cabeceras públicas, pero empeora la lectura rápida en tablas financieras y formularios. Nunca apliques `font-display` (`Cinzel`) en tablas, inputs, badges ni botones operativos; usa `Manrope` con `tabular-nums` para todas las cifras (`1,728`, MXN, fechas y conteos SLA).
- **Regla del Ámbar consciente de contraste:** `Dorado Atardecer` (`#E58E26`) con texto blanco se reserva a botones CTA públicos sobre fondos claros u oscuros de marketing. En controles operativos (`Admin` y `Verificador QR`), `#E58E26` exige tinta **Carbón Pizarra** (`#0F172A`, contraste `7.0:1`). Sobre fondos blancos o `Arena Cálida`, usa texto **Ámbar Accesible** (`#B45309`, `>= 4.5:1`), nunca `#E58E26` directo como texto pequeño.
- **Quiet Rest & orden visual:** Prefiere superficies sólidas con borde limpio (`1px` en `#E4DED3` o `#E5E7EB`) y evita apilar gradientes decorativos, `blur-3xl`, barras laterales gruesas (`border-l-4`) o filas de 4 tarjetas KPI idénticas con cajas de íconos.

---

## Checklist de verificación antes de entregar UI

Antes de dar por terminada cualquier pantalla o componente migrado:

1. **Identidad de superficie:** ¿La vista usa la paleta exacta de su superficie (`#F8F9FA` público, `#F6F4EF` admin, `#0B1736` puerta QR) y sus activos oficiales (`img/LOGO.svg`, `img/plano-teatro.svg`)?
2. **Tipografía y cifras:** ¿Los encabezados públicos/títulos de obra usan `Cinzel`, los controles/tablas usan `Manrope`, y los precios, fechas y aforos llevan `tabular-nums`?
3. **Contraste y tamaño mínimo:** ¿Todos los textos funcionales, badges, encabezados de tabla e inputs son `>= 12px` (`text-xs`) y cumplen WCAG AA/AAA (tinta `#0F172A` sobre `#E58E26` en Admin/Puerta, `#B45309` para texto ámbar sobre claro)?
4. **Arquitectura operativa correcta:** Si es Admin, ¿usa la barra de 4 pilares + sub-barra Arena y mesa **Split `7+5` con inspector fijo** en lugar de modales repetitivos? Si es Verificador, ¿coloca la tarjeta de veredicto por encima de la cámara/entrada manual y deja cualquier simulador debajo?
5. **Iconografía y accesibilidad:** ¿Se usan íconos SVG consistentes en lugar de emojis de sistema en la interfaz (reservando únicamente `♿` para localidades accesibles en el plano)?
6. **Responsive sin desbordamiento:** Verifica `390px` (móvil) y `1280px` (escritorio) sin `scrollWidth > innerWidth` ni columnas recortadas.
