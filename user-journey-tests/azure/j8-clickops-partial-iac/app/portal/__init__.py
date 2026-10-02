"""Student portal for the university estate (fictional).

The WSGI entry point App Service starts is `portal:app`.
"""

from __future__ import annotations

from flask import Flask

app = Flask(__name__)

from portal import views  # noqa: E402,F401  (routes register on import)
