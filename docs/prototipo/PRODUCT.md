# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

**Usuario principal: el público asistente.** Personas de Coatzacoalcos y del sur de Veracruz que buscan qué hay en el Teatro de la Ciudad y quieren comprar sus boletos **eligiendo su butaca** sobre el plano real de la sala. Las decisiones de producto se toman pensando primero en ellas.

Otras audiencias del ecosistema:
- **Organizadores y solicitantes con cuenta (`USUARIO`):** solicitan cotización para arrendar el teatro (Comercial, Público o Privado), dan seguimiento y configuran tarifas cuando aplica.
- **Taquilla física (`CAJERO`):** opera la venta presencial sincronizada en tiempo real con el inventario web y reimpresión de boletos.
- **Personal de puerta (`VERIFICADOR`):** valida boletos QR en acceso mediante consola móvil nocturna.
- **Administración del recinto (`ADMIN`):** gestiona tablero operativo, cotizaciones (`ME-01`), cartelera (`ME-02`), agenda maestra anti-choques, bloqueos/cortesías/contingencia de sala, ventas y parámetros operativos.

## Product Purpose

Portal oficial y consola operativa del Teatro de la Ciudad de Coatzacoalcos donde el recinto vende **todos** sus boletos directamente, con selección de butaca numerada y QR de un solo uso, además de publicar la cartelera y gestionar solicitudes de arrendamiento.

El proyecto es una **propuesta formal para la administración real del Teatro / Centro de Convenciones**. El éxito es convencer a esa administración de adoptarlo: el prototipo demuestra con credibilidad que el recinto puede operar su propia venta, puerta y relación con el público bajo la identidad definida en [DESIGN.md](DESIGN.md).

## Positioning

Hoy cada evento se vende en una boletera externa distinta (Eticket, TusBoletos.mx, Ticketmanía, Tiketpass, ShowBizTicket, Notikumi, entre otras), además de la taquilla física. Este portal **reemplaza esa fragmentación**: una sola venta, con la marca del propio teatro (*El Foro Monumental*), sobre el plano oficial de sus **1,728 butacas en 6 secciones**. Una boletera genérica no puede ofrecer esa fidelidad espacial ni coherencia institucional.

## Operating Context

- El recinto está en Av. Abraham Zabludovsky #201, Col. El Encanto, C.P. 96535, dentro del complejo del Centro de Convenciones de Coatzacoalcos, Veracruz.
- Programación variada: ballet (p. ej. El Cascanueces), conciertos pop, rock y sinfónicos, teatro, danza, eventos comunitarios gratuitos y eventos privados.
- Operación horaria oficial en `America/Mexico_City`; venta en línea cierra **30 min** antes de la función y taquilla física cierra a **0 min** (hora exacta de inicio).
- El prototipo opera con compatibilidad dual (`file://` y servidor HTTP estático) simulando persistencia y reloj en `localStorage` bajo módulos `window.TC`.

## Capabilities and Constraints

**Ya presente en el prototipo:**
- **Cartelera (`index.html`):** búsqueda, filtro por categoría y fechas; diferencia eventos **Comerciales** (con venta numerada) de **Públicos** (*Entrada Libre · Control de acceso por el organizador hasta 1,728 personas*) y oculta **Privados**. Selector de función cuando existen múltiples funciones.
- **Compra de boletos (`boletos.html`) y Taquilla Física (`taquilla.html`):** mapa SVG oficial (`img/plano-teatro.svg` / `js/plano-teatro-svg.js`) con **6 secciones oficiales y 1,728 butacas numeradas** (**Luneta** 564, **Platea** 144, **Mezzanine** 291, **Primer Piso** 287, **Segundo Piso** 386, **Palcos** 56; incluye **12 lugares accesibles `♿`**). Zoom semántico LOD (`>= 1.7x`), límite anti-reventa de hasta `10` boletos por función, apartado temporal de `10 min` (+`5 min` en pago) y pasarela simulada.
- **Configurador tarifario (`configurador.html`):** secciones del evento (conservación 6 secciones, sección única, agrupación o subdivisión de hasta ≤ 6 por sección oficial), fases de venta consecutivas, piso tarifario `>= $100.00 MXN`, cobertura 100% sin butacas huérfanas y congelamiento al publicar.
- **Cotización y seguimiento (`cotizar.html`, `usuario.html`):** solicitud multi-día/turno para modalidades Comercial, Público o Privado, catálogo oficial de infraestructura/extras, subtotal estimado referencial, esquema `50/50` vs `100%`, aceptación de fechas alternativas (`48 h`) y gestión de pagos.
- **Cuentas, auth y cumplimiento (`cuenta.html`, `legal.html`):** cuenta obligatoria para comprar y cotizar, recuperación de contraseña, control RBAC por rol, Aviso de Privacidad (LFPDPPP) y Términos y Condiciones.
- **Verificador de puerta QR (`verificador.html`):** interfaz móvil nocturna (*Pase de Puerta del Foro*) con validación atómica, telemetría en vivo y las **6 respuestas deterministas** (`VALIDO`, `YA_UTILIZADO`, `OTRA_FUNCION`, `DEMASIADO_PRONTO`, `FUNCION_CONCLUIDA`, `INVALIDO`).
- **Consola Administrativa (`admin/*.html`):** interfaz en Arena Cálida (`#F6F4EF`) con cabecera Azul Golfo de **4 pilares** (*Hoy*, *Programación*, *Comercial y Sala*, *Recinto*) y mesas **Split `7+5`**: resumen operativo (`admin/index.html`), cotizaciones `ME-01` (`admin/cotizaciones.html`), cartelera y compuerta `D-15` (`admin/cartelera.html`), calendario maestro anti-choques (`admin/agenda.html`), bloqueos técnicos/cortesías/contingencia (`admin/sala.html`), órdenes y bitácora inmutable (`admin/ventas.html`), usuarios (`admin/usuarios.html`) y parámetros snapshot (`admin/configuracion.html`).

**Restricciones y exclusiones:**
- Idioma: español de México. Moneda: `MXN`. Zona horaria: `America/Mexico_City`.
- La capacidad mostrada debe coincidir exactamente con el plano oficial: **1,728 butacas en 6 secciones** (`+12 accesibles`).
- **Exclusiones explícitas:** sin módulo CMS para editar diseño o textos estáticos institucionales, sin servicios de catering/alimentos ni estacionamiento, y sin borrado físico de registros financieros o eventos confirmados.

**Decisiones abiertas (no inventar):**
- Integración con pasarela de pago real (Stripe) y backend persistente del repositorio productivo.
- Operación puntual para eventos externos por orden de llegada sin boletería del recinto.
- Si el Auditorio anexo (220–224 personas) entra en una fase posterior.

## Brand Commitments

- Nombre: **Teatro de la Ciudad de Coatzacoalcos**, parte del Centro de Convenciones de Coatzacoalcos, Veracruz.
- Logotipo oficial del prototipo: `img/LOGO.svg` (variante oscura `img/LOGO_OSCURO.svg`).
- Voz institucional del propio recinto y sistema visual unificado **El Foro Monumental** definido en `DESIGN.md` y `.impeccable/design.json`.

## Evidence on Hand

- Investigación del recinto, sus secciones y eventos previos: `../Inveztigaciones/*.md`.
- Plano oficial de la sala: `img/Plano_Teatro.jpeg`. Versión interactiva: `img/plano-teatro.svg`.
- Fotografía de la Gran Sala: `img/teatro-sala-interior.jpg`.
- **Ausencias que no se deben fabricar:** no hay testimonios, cifras reales de venta, acuerdos cerrados con la administración ni datos de usuarios reales. Los eventos, boletos y cotizaciones iniciales del prototipo son datos de demostración.

## Product Principles

1. **La compra es el camino crítico.** Del cartel a la butaca pagada con la menor fricción posible. Todo lo demás se subordina a ese recorrido.
2. **Fidelidad al recinto real.** Las **1,728 localidades**, **6 secciones**, numeración y horarios reflejan el teatro verdadero y se verifican contra la configuración oficial.
3. **El teatro es dueño de su relación con el público.** Las tres superficies (portal, consola backstage y puerta QR) refuerzan una sola familia institucional coherente.
4. **Operable por el personal del teatro.** Cartelera, agenda, cotizaciones, tarifas de sala, taquilla y acceso QR se operan desde la consola administrativa sin intervención de desarrollo ni CMS sobre el diseño.
5. **Credibilidad ante la administración.** Ninguna afirmación, cifra o promesa sin respaldo en la evidencia disponible.

## Accessibility & Inclusion

Sitio público institucional y consolas operativas con objetivo **WCAG 2.1 AA** (alcanzando **AAA** en controles críticos de Admin y Verificador QR). La selección de butacas debe operar en móvil e indicar disponibilidad, selección, ocupación, bloqueo y **12 lugares accesibles (`♿`)** mediante forma, borde, símbolo y texto, nunca solo por color.
