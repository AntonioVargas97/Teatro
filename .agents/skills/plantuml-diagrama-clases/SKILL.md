---
name: plantuml-diagrama-clases
description: Reglas para crear y verificar diagramas de clases UML 2.5.1 en PlantUML con relaciones que no se cruzan. Úsala siempre que se cree, edite, revise o renderice un diagrama de clases (dominio, módulos, enumeraciones) en docs/diagramas-uml/ o cualquier .puml de clases, aunque el usuario no mencione UML ni PlantUML.
---

# Diagramas de clases UML 2.5.1 en PlantUML

Guía para producir diagramas de clases **legibles a simple vista**: relaciones identificables, **cero cruces** y notación UML vigente (2.5.1). Complementa las fuentes de verdad del proyecto; nunca las contradice.

## 1. Fuentes y ubicación

| Qué | Dónde |
| :-- | :-- |
| Entidades, atributos y reglas | `docs/arquitectura.md` (Entidades Nucleares, Módulos, Reglas entre módulos), `docs/alcance.md` |
| Estados y literales de enumeraciones | `docs/maquinas-de-estado.md` y `docs/maquinas-de-estado/*.puml` |
| Archivos de salida | `docs/diagramas-uml/diagrama-clases-<tema>.puml` (solo el fuente `.puml`; los PNG/SVG de verificación no se versionan) |

- **No inventes** atributos, estados ni relaciones: si algo no está en las fuentes de verdad, déjalo fuera y repórtalo como pendiente.
- `database/*.sql` son referencia documental y pueden estar vacíos; el modelo vive en `docs/` (ADR-02).
- Si el diagrama revela una contradicción o laguna en las fuentes, corrige primero la fuente (regla de sincronización de `AGENTS.md`).

## 2. Notación UML 2.5.1 (qué usar y cuándo)

| Concepto | PlantUML | Regla |
| :-- | :-- | :-- |
| Asociación | `A "1" -- "0..*" B` | Por defecto. Multiplicidad en **ambos** extremos, siempre. |
| Asociación navegable | `A "0..*" --> "1" B` | Flecha abierta = A conoce a B pero B no conoce a A. Úsala para reflejar dependencias unidireccionales (ej. dominio → módulos transversales, ADP). |
| Composición | `Todo "1" *-- "1..*" Parte` | Ciclo de vida coincidente y propiedad exclusiva (rombo relleno junto al todo). Multiplicidad del extremo todo = `1` o `0..1`. |
| Agregación compartida | **No usar** | UML 2.5.1 no le da semántica precisa; usa asociación simple o composición. |
| Generalización | `Hija --|> Padre` | Solo si existe herencia real en las fuentes. |
| Clase de asociación | `(A, B) .. Clase` | Solo cuando la relación N:M tiene atributos propios. |
| Restricción | `{xor}`, `{unique}`, `{>= 100.00}` | Atributos con `{...}`; restricciones entre asociaciones en la leyenda. |
| Enumeración | `class X <<enumeration>>` con literales en MAYÚSCULAS | Literales sin visibilidad ni tipo. |
| Atributo | `+ nombre : Tipo [0..1] = default {propiedad}` | Visibilidad (`+ - # ~`), nombre, tipo, multiplicidad si no es `1`, valor por defecto. |

Reglas adicionales:
- Un atributo que apunta a otra clase del diagrama **debe ser una asociación**, no un atributo. Excepción documentada: referencias lógicas por id a módulos que no deben importarse (ej. `RegistroAuditoria.actorId`), explicadas en la leyenda.
- Estereotipo por módulo (`<<ventas>>`, `<<cartelera>>`…) y un color por módulo con leyenda.
- Nombres de rol/asociación solo si aportan significado; el verbo con `>` indica el sentido de lectura.
- Los tipos enumerados se detallan en un diagrama aparte (`diagrama-clases-enumeraciones.puml`) para no saturar el principal.

## 3. Procedimiento para lograr cero cruces

1. **Lista** clases y relaciones (grafo). Elimina las relaciones **derivables** (ej. `Boleto → OrdenCompra` ya se deduce de `Boleto → DisponibilidadButaca → OrdenCompra`) y repórtalo en la leyenda.
2. **Comprueba planaridad** a mano: busca ciclos y dibuja el grafo sobre una rejilla. Si un ciclo obliga a cruzar, quita/mueve una relación derivable o reubica la clase "puente".
3. **Asigna posiciones** en rejilla (filas = rangos, columnas = orden horizontal). Coloca los hubs (clases con muchas relaciones) con espacio libre en cada lado.
4. **Fuerza la rejilla** con direcciones en cada relación: `-right-`, `-left-`, `-down-`, `-up-`. Una relación `A -right- B` coloca `B` a la derecha de `A`.
5. **Alinea con enlaces ocultos** cuando una clase se descoloca: `A -[hidden]right- B`, `A -[hidden]down- B`. Para colgar clases sueltas (sin relaciones) úsalos también.
6. **Estilo base**: `skinparam linetype ortho`, `nodesep/ranksep 70`, `hide empty members`, `hide circle`, `skinparam classAttributeIconSize 0`.
7. **Renderiza y verifica** (sección 4). Itera hasta que el verificador diga `OK: sin cruces` **y** revises la imagen.

Lecciones aprendidas con PlantUML + Graphviz:
- `-left-`/`-right-` **no garantizan el mismo rango**: si dos clases deben quedar en la misma fila, añade `A -[hidden]right- B`.
- Con `linetype ortho` las **etiquetas de relaciones con codos flotan lejos de la línea**: etiqueta solo relaciones rectas; en las demás confía en multiplicidades y leyenda.
- Una relación que queda pegada al borde de otra clase suele indicar un hueco de rejilla: reordena en vez de añadir más ayudas.
- Evita `package`/`rectangle` para agrupar módulos en el diagrama principal: los clusters de Graphviz rompen la rejilla. Usa estereotipo + color + leyenda.
- Cambiar un enlace oculto puede reacomodar todo el diagrama: verifica de nuevo tras cada cambio.

## 4. Renderizado y verificación

Requisitos: Java, `plantuml.jar` (extensión VS Code `jebbs.plantuml` o descarga oficial) y **Graphviz** (`dot`). Si no hay permisos para instalar, descarga el zip portable de Graphviz a una carpeta temporal y define `GRAPHVIZ_DOT`.

```powershell
# PNG para revisar visualmente
powershell -File .agents/skills/plantuml-diagrama-clases/scripts/render_puml.ps1 docs/diagramas-uml/diagrama-clases-dominio.puml -Format png
# SVG + verificación automática de cruces y atravesamientos
powershell -File .agents/skills/plantuml-diagrama-clases/scripts/render_puml.ps1 docs/diagramas-uml/diagrama-clases-dominio.puml -Format svg -Check
```

`scripts/check_crossings.py <archivo.svg>` falla (código 1) si dos relaciones se intersectan o si una relación atraviesa una clase que no es uno de sus extremos. La salida va a `$env:TEMP\puml-out` salvo que se indique `-OutDir`; **no** guardes imágenes dentro del repositorio salvo petición expresa.

> [!IMPORTANT]
> El verificador no detecta etiquetas mal ubicadas ni líneas pegadas a un borde: siempre abre el PNG y revisa legibilidad.

## 5. Lista de verificación antes de entregar

- [ ] Cada clase, atributo, multiplicidad y literal sale de las fuentes de verdad (nada inventado).
- [ ] Multiplicidad en ambos extremos de toda asociación; sin agregación compartida.
- [ ] Composición solo con ciclo de vida coincidente; navegabilidad respeta ADP (transversales no conocen al dominio).
- [ ] `check_crossings.py` → `OK: sin cruces` y revisión visual del PNG.
- [ ] Leyenda con colores por módulo, restricciones `{xor}` y relaciones omitidas por ser derivables.
- [ ] Enumeraciones en su diagrama aparte; los literales coinciden con `docs/maquinas-de-estado.md`.
- [ ] Archivo en `docs/diagramas-uml/` con nombre `diagrama-clases-<tema>.puml`.
