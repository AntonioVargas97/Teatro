"""Enrutamiento raíz de la API REST (/api/v1/)."""

from django.db import connection
from django.http import JsonResponse
from django.urls import path
from django_redis import get_redis_connection


def healthcheck(_request) -> JsonResponse:
    """Verifica conectividad con PostgreSQL y Redis para monitoreo."""
    status_data = {"status": "ok", "database": "ok", "redis": "ok"}
    http_status = 200

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1;")
            cursor.fetchone()
    except Exception:
        status_data["database"] = "error"
        status_data["status"] = "degraded"
        http_status = 503

    try:
        redis_conn = get_redis_connection("default")
        if not redis_conn.ping():
            raise RuntimeError("Redis ping failed")
    except Exception:
        status_data["redis"] = "error"
        status_data["status"] = "degraded"
        http_status = 503

    return JsonResponse(status_data, status=http_status)


urlpatterns = [
    path("api/v1/health/", healthcheck, name="api-healthcheck"),
]
