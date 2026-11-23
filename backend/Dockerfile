# Imagen oficial del backend — Plataforma Teatro de la Ciudad de Coatzacoalcos
# Python 3.12+ según docs/stack-tecnologico.md
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    TZ=UTC

WORKDIR /app

# Dependencias mínimas de sistema (healthchecks/utilidades).
# psycopg[binary], reportlab y Pillow se instalan desde wheels sin compilar Cairo/Pango.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip && pip install -r /app/requirements.txt

COPY . /app

RUN mkdir -p /app/media /app/staticfiles

EXPOSE 8000

CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3"]
