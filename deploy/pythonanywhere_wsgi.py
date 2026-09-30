"""Copia este contenido en el archivo WSGI indicado por el panel Web."""
import os
import sys

project_path = "/home/TU_USUARIO/PizarraApp/backend"
if project_path not in sys.path:
    sys.path.insert(0, project_path)

os.environ["DJANGO_SETTINGS_MODULE"] = "config.settings_production"

from django.core.wsgi import get_wsgi_application

application = get_wsgi_application()
