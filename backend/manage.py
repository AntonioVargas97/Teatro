#!/usr/bin/env python
"""Punto de entrada de línea de comandos de Django para tareas administrativas."""

import os
import sys


def main() -> None:
    """Ejecuta comandos administrativos de Django."""
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "No se pudo importar Django. Verifica que el entorno esté activo "
            "o que estés ejecutando dentro del contenedor Docker."
        ) from exc
    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
