"""aws_clients.py — compatibility shim (GCP port).

The unmodified journey app (app.py, db.py) imports `aws_clients` everywhere.
After the migration every call is served by gcp_clients.py; this shim keeps
the import name stable so app.py ships with zero diffs and the journey's
smoke-test.sh passes untouched. Retire it whenever someone gets around to
renaming the imports.
"""

from gcp_clients import *  # noqa: F401,F403
