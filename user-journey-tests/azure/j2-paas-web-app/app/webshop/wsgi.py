"""WSGI entry point. gunicorn is started against webshop.wsgi:application."""

import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "webshop.settings")

application = get_wsgi_application()
