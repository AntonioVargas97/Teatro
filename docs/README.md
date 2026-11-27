# Documentación

Alcance, requerimientos, arquitectura, tecnología, modelo de datos, máquinas de estado, contrato API, pruebas y diagramas del Teatro de la Ciudad de Coatzacoalcos.

- `alcance.md`: reglas de negocio, plazos, límites y exclusiones.
- `requisitos/requisitos-funcionales.md`: especificación de 103 requerimientos funcionales atómicos (`RF-01` a `RF-103`).
- `requisitos/requisitos-no-funcionales.md`: especificación de 43 requerimientos no funcionales verificables (`RNF-01` a `RNF-43`) bajo ISO/IEC 25010.
- `arquitectura.md`: capas, módulos, concurrencia, RBAC, calidad y ADRs.
- `stack-tecnologico.md`: versiones aprobadas, herramientas de QA y librerías excluidas.
- `contrato-api.md`: contrato REST `/api/v1/` (rutas, esquemas JSON, errores `code`, throttling y webhooks).
- `modelo-datos.md`: modelo relacional v6.2 (44 tablas, 6 módulos base y 5 de dominio).
- `modelado_datos/`: diagramas `Teatro_MR_v6.2.drawio` (modelo relacional) y `Teatro_ER_Chen_v6.2.drawio` (entidad-relación en notación Chen).
- `reportes/informe-cambios-modelo-datos.md`: informe de cambios de la v5.3 a la v6.2.
- `maquinas-de-estado.md` y `maquinas-de-estado/`: estados, guardas y transiciones, con diagramas `me01` a `me04`.
- `diagramas-uml/`: diagramas de clases, enumeraciones, casos de uso (`01`–`10`), robustez (`RB01`–`RB10`) y secuencia (`SD01`–`SD10`) en PlantUML (UML 2.5.1).
- `plan-pruebas.md`: plan maestro de pruebas ISO/IEC/IEEE 29119-3 con RTM completa (`RF`, `RNF`, transiciones y `SD`), concurrencia y técnicas avanzadas.
- `prototipo/`: prototipo visual de referencia (`DESIGN.md`, `PRODUCT.md`, `design.json`).
- `reportes/`: auditorías inmutables (solo se agregan archivos nuevos).
