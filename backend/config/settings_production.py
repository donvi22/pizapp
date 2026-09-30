"""Configuración de la demo pública. La clave se genera en el servidor."""
import json
import os

from django.core.exceptions import ImproperlyConfigured

from .settings import *  # noqa: F403

config_path = BASE_DIR / ".production.json"
config = json.loads(config_path.read_text(encoding="utf-8")) if config_path.exists() else {}

DEBUG = False
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY") or config.get("secret_key", "")
if len(SECRET_KEY) < 50 or SECRET_KEY.startswith("django-insecure-"):
    raise ImproperlyConfigured("Genera la configuración con prepare_production.py.")

ALLOWED_HOSTS = (
    [host.strip() for host in os.environ["DJANGO_ALLOWED_HOSTS"].split(",") if host.strip()]
    if "DJANGO_ALLOWED_HOSTS" in os.environ else config.get("allowed_hosts", [])
)
if not ALLOWED_HOSTS or any("*" in host for host in ALLOWED_HOSTS):
    raise ImproperlyConfigured("Configura los dominios concretos de la demo.")

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_ROOT = BASE_DIR / "media"
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
        "OPTIONS": {"timeout": 20, "transaction_mode": "IMMEDIATE"},
    },
}

# HTTPS también se fuerza en el panel del alojamiento, incluidos los estáticos.
SECURE_SSL_REDIRECT = True
SECURE_HSTS_SECONDS = 3600
SECURE_HSTS_INCLUDE_SUBDOMAINS = False
SECURE_HSTS_PRELOAD = False
# Son recomendaciones opcionales. En esta primera demo solo se aplica HSTS al
# dominio de la app; no se registra el dominio del proveedor en listas preload.
SILENCED_SYSTEM_CHECKS = ["security.W005", "security.W021", "mail.W001"]
# Esta versión utiliza avisos dentro de la app y no envía correo electrónico.
MAILERS = {}
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "DENY"
CSRF_TRUSTED_ORIGINS = [f"https://{host}" for host in ALLOWED_HOSTS]
CORS_ALLOWED_ORIGINS = []  # Flutter y API comparten origen en producción.
CORS_ALLOW_ALL_ORIGINS = False

REST_FRAMEWORK = {
    **REST_FRAMEWORK,
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
}

PIZAPP_MAX_UPLOAD_BYTES = 20 * 1024 * 1024
PIZAPP_PROJECT_STORAGE_BYTES = 100 * 1024 * 1024
PIZAPP_TOTAL_STORAGE_BYTES = 200 * 1024 * 1024
